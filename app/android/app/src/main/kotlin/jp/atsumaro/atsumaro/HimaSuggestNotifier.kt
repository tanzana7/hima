package jp.atsumaro.atsumaro

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

internal class HimaSuggestNotifier(private val context: Context) {

    @SuppressLint("MissingPermission") // both checks below cover the API 33 runtime permission
    fun post(body: String) {
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        ensureChannel()
        val notification = NotificationCompat.Builder(context, HimaSuggest.NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_hima)
            .setContentTitle(TITLE)
            .setContentText(body)
            .setAutoCancel(true)
            .setContentIntent(declarePendingIntent())
            .build()
        manager.notify(HimaSuggest.NOTIFICATION_ID, notification)
    }

    fun cancel() {
        NotificationManagerCompat.from(context).cancel(HimaSuggest.NOTIFICATION_ID)
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        if (manager.getNotificationChannel(HimaSuggest.NOTIFICATION_CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                HimaSuggest.NOTIFICATION_CHANNEL_ID,
                HimaSuggest.NOTIFICATION_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_DEFAULT,
            ),
        )
    }

    private fun declarePendingIntent(): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .putExtra(HimaSuggest.ACTION_EXTRA, HimaSuggest.ACTION_DECLARE)
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    companion object {
        const val TITLE = "いまひまじゃない？"
        const val USUAL_BODY = "いつものひまな時間だよ。ひまなら友達に知らせよう"

        fun appBody(label: String): String = "$label 見てる？ ひまなら友達に知らせよう"
    }
}
