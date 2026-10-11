package org.yfca.epi_app

import android.Manifest
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.CalendarContract
import android.provider.MediaStore
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import java.security.SecureRandom
import java.util.TimeZone
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec

/**
 * Native services for the EPI app: Android Keystore, PIN hashing, reminders,
 * device calendar and saving exports. All framework APIs, no extra libraries.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "org.yfca.epi/native"
    private var pendingResult: MethodChannel.Result? = null
    private val reqNotifications = 41
    private val reqCalendar = 42

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Hide child data from screenshots and the recent-apps preview (FRS-SEC-06).
        // Debug builds skip this so QA can take screenshots; release builds always set it.
        val debuggable = (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (!debuggable) {
            window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getDbKey" -> result.success(dbKey(this))
                    "hashPin" -> result.success(hashPin(call.argument<String>("pin")!!, call.argument<String>("salt")!!))
                    "notificationsEnabled" -> result.success(ReminderStore.notificationsEnabled(this))
                    "requestNotificationPermission" -> requestNotifications(result)
                    "setReminders" -> {
                        val alarms = call.argument<List<Map<String, Any?>>>("alarms") ?: emptyList()
                        ReminderStore.replaceAll(this, alarms)
                        result.success(true)
                    }
                    "requestCalendarPermission" -> requestCalendar(result)
                    "calendarUpsert" -> result.success(
                        calendarUpsert(
                            (call.argument<Any?>("eventId") as Number?)?.toLong(),
                            call.argument<String>("title") ?: "",
                            call.argument<String>("description") ?: "",
                            (call.argument<Any?>("start") as Number).toLong(),
                        )
                    )
                    "calendarDelete" -> {
                        val id = (call.argument<Any?>("eventId") as Number).toLong()
                        if (hasCalendarPermission()) {
                            contentResolver.delete(ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, id), null, null)
                        }
                        result.success(true)
                    }
                    "saveToDownloads" -> result.success(
                        saveToDownloads(call.argument<ByteArray>("bytes")!!, call.argument<String>("name")!!, call.argument<String>("mime")!!)
                    )
                    "wipe" -> {
                        ReminderStore.replaceAll(this, emptyList())
                        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().commit()
                        try {
                            val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                            ks.deleteEntry(KEY_ALIAS)
                        } catch (e: Exception) {
                            // nothing to delete
                        }
                        result.success(true)
                    }
                    "appVersion" -> {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        result.success(info.versionName ?: "")
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("native_error", e.message, null)
            }
        }
    }

    // ---------- permissions ----------
    private fun requestNotifications(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(ReminderStore.notificationsEnabled(this))
            return
        }
        pendingResult = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), reqNotifications)
    }

    private fun hasCalendarPermission(): Boolean =
        checkSelfPermission(Manifest.permission.WRITE_CALENDAR) == PackageManager.PERMISSION_GRANTED &&
            checkSelfPermission(Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED

    private fun requestCalendar(result: MethodChannel.Result) {
        if (hasCalendarPermission()) {
            result.success(true)
            return
        }
        pendingResult = result
        requestPermissions(arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR), reqCalendar)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val r = pendingResult ?: return
        pendingResult = null
        when (requestCode) {
            reqNotifications -> r.success(ReminderStore.notificationsEnabled(this))
            reqCalendar -> r.success(hasCalendarPermission())
            else -> r.success(false)
        }
    }

    // ---------- calendar (FRS-REM-08, 09) ----------
    private fun writableCalendarId(): Long? {
        val projection = arrayOf(CalendarContract.Calendars._ID, CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL)
        contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI, projection,
            "${CalendarContract.Calendars.VISIBLE} = 1", null, null
        )?.use { c ->
            while (c.moveToNext()) {
                if (c.getInt(1) >= CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR) return c.getLong(0)
            }
        }
        return null
    }

    private fun calendarUpsert(eventId: Long?, title: String, description: String, start: Long): Long? {
        if (!hasCalendarPermission()) return null
        val values = ContentValues().apply {
            put(CalendarContract.Events.DTSTART, start)
            put(CalendarContract.Events.DTEND, start + 30 * 60 * 1000)
            put(CalendarContract.Events.TITLE, title)
            put(CalendarContract.Events.DESCRIPTION, description)
            put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
        }
        if (eventId != null) {
            val n = contentResolver.update(
                ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventId), values, null, null
            )
            if (n > 0) return eventId
        }
        val calId = writableCalendarId() ?: return null
        values.put(CalendarContract.Events.CALENDAR_ID, calId)
        val uri = contentResolver.insert(CalendarContract.Events.CONTENT_URI, values) ?: return null
        return ContentUris.parseId(uri)
    }

    // ---------- exports ----------
    private fun saveToDownloads(bytes: ByteArray, name: String, mime: String): String {
        if (Build.VERSION.SDK_INT >= 29) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/EPI")
            }
            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Cannot create file in Downloads")
            contentResolver.openOutputStream(uri)!!.use { it.write(bytes) }
            return "Downloads/EPI/$name"
        }
        val dir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: filesDir
        val f = File(dir, name)
        f.writeBytes(bytes)
        return f.absolutePath
    }

    companion object {
        const val PREFS = "epi_native"
        private const val KEY_ALIAS = "epi_db_wrap_key"

        /** Database key: random 32 bytes, wrapped with an AES key held in the Android Keystore. */
        fun dbKey(ctx: Context): String {
            val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val wrapping = wrappingKey()
            val stored = prefs.getString("db_key", null)
            if (stored != null) {
                val parts = stored.split(":")
                val iv = Base64.decode(parts[0], Base64.NO_WRAP)
                val enc = Base64.decode(parts[1], Base64.NO_WRAP)
                val c = Cipher.getInstance("AES/GCM/NoPadding")
                c.init(Cipher.DECRYPT_MODE, wrapping, GCMParameterSpec(128, iv))
                return toHex(c.doFinal(enc))
            }
            val raw = ByteArray(32).also { SecureRandom().nextBytes(it) }
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.ENCRYPT_MODE, wrapping)
            val enc = c.doFinal(raw)
            val value = Base64.encodeToString(c.iv, Base64.NO_WRAP) + ":" + Base64.encodeToString(enc, Base64.NO_WRAP)
            prefs.edit().putString("db_key", value).commit()
            return toHex(raw)
        }

        private fun wrappingKey(): SecretKey {
            val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            (ks.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
            val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            gen.init(
                KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build()
            )
            return gen.generateKey()
        }

        fun hashPin(pin: String, saltHex: String): String {
            val salt = saltHex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
            val spec = PBEKeySpec(pin.toCharArray(), salt, 20000, 256)
            val f = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
            return toHex(f.generateSecret(spec).encoded)
        }

        private fun toHex(b: ByteArray): String = b.joinToString("") { "%02x".format(it) }
    }
}
