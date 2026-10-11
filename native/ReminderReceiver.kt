package org.yfca.epi_app

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Shows one grouped reminder notification; tapping opens the app (FRS-REM-02, 03). */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        ReminderStore.ensureChannel(ctx)
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (!nm.areNotificationsEnabled()) return
        val id = intent.getIntExtra("id", 1)
        val title = intent.getStringExtra("title") ?: ""
        val body = intent.getStringExtra("body") ?: ""
        val child = intent.getStringExtra("child") ?: ""
        val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            // One child: open that record after unlock; several: open the due list (FRS-REM-02).
            putExtra("epi_child", if (child.isEmpty()) "*" else child)
        }
        val content = if (launch == null) null else PendingIntent.getActivity(
            ctx, id, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val n = Notification.Builder(ctx, ReminderStore.CHANNEL_ID)
            .setSmallIcon(ctx.applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(content)
            // Names stay off the lock screen; a generic version is shown there.
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(
                Notification.Builder(ctx, ReminderStore.CHANNEL_ID)
                    .setSmallIcon(ctx.applicationInfo.icon)
                    .setContentTitle(title)
                    .setContentText(ctx.getString(android.R.string.untitled))
                    .build()
            )
            .build()
        nm.notify(id, n)
    }
}

/** Rebuilds stored reminders after restart, time or zone change and app update (FRS-REM-05). */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        ReminderStore.rescheduleStored(ctx)
    }
}
