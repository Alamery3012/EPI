package org.yfca.epi_app

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject

/**
 * Keeps the full reminder list in private preferences and (re)schedules it.
 * replaceAll() cancels every previous alarm first, so reminders are never
 * duplicated (FRS-REM-04); rescheduleStored() rebuilds them after a restart,
 * time change or app update (FRS-REM-05).
 */
object ReminderStore {
    const val CHANNEL_ID = "epi_reminders"
    private const val KEY_LIST = "reminders"

    fun notificationsEnabled(ctx: Context): Boolean =
        (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).areNotificationsEnabled()

    fun ensureChannel(ctx: Context) {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            val ch = NotificationChannel(CHANNEL_ID, "Vaccination reminders", NotificationManager.IMPORTANCE_DEFAULT)
            ch.description = "Upcoming and overdue vaccination visits"
            nm.createNotificationChannel(ch)
        }
    }

    fun replaceAll(ctx: Context, alarms: List<Map<String, Any?>>) {
        cancelStored(ctx)
        val arr = JSONArray()
        for (a in alarms) {
            val o = JSONObject()
            o.put("id", (a["id"] as Number).toInt())
            o.put("at", (a["at"] as Number).toLong())
            o.put("title", a["title"] as String? ?: "")
            o.put("body", a["body"] as String? ?: "")
            arr.put(o)
        }
        prefs(ctx).edit().putString(KEY_LIST, arr.toString()).commit()
        scheduleAll(ctx, arr)
    }

    fun rescheduleStored(ctx: Context) {
        val arr = stored(ctx)
        cancelAll(ctx, arr)
        scheduleAll(ctx, arr)
    }

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(MainActivity.PREFS, Context.MODE_PRIVATE)

    private fun stored(ctx: Context): JSONArray =
        try {
            JSONArray(prefs(ctx).getString(KEY_LIST, "[]"))
        } catch (e: Exception) {
            JSONArray()
        }

    private fun cancelStored(ctx: Context) = cancelAll(ctx, stored(ctx))

    private fun cancelAll(ctx: Context, arr: JSONArray) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            am.cancel(pending(ctx, o))
        }
    }

    private fun scheduleAll(ctx: Context, arr: JSONArray) {
        ensureChannel(ctx)
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val now = System.currentTimeMillis()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            val at = o.getLong("at")
            if (at <= now) continue
            // Inexact, doze-friendly alarm: a reminder for a calendar day does
            // not need minute precision and needs no special permission.
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending(ctx, o))
        }
    }

    private fun pending(ctx: Context, o: JSONObject): PendingIntent {
        val i = Intent(ctx, ReminderReceiver::class.java).apply {
            action = "org.yfca.epi.REMINDER"
            putExtra("id", o.getInt("id"))
            putExtra("title", o.optString("title"))
            putExtra("body", o.optString("body"))
            putExtra("child", o.optString("child"))
        }
        return PendingIntent.getBroadcast(
            ctx, o.getInt("id"), i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
