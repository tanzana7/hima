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
import java.util.UUID

internal class HimaSuggestNotifier(private val context: Context) {

    /**
     * Posts only while the feature is still enabled. Disabling and cancelling take the same
     * lock, so a run that started before the user turned the feature off cannot re-post a
     * suggestion after the cancel.
     */
    fun post(body: String, store: HimaSuggestStore): Boolean = synchronized(LOCK) {
        if (!store.enabled) return false
        if (!notificationsAllowed()) return false
        postLocked(HimaSuggest.NOTIFICATION_ID, body, declarePendingIntent(store))
    }

    /**
     * Posts the developer demo variant: same channel, icon, title and bodies as a real
     * suggestion, so it can be checked visually, plus a "デモ" subtext so it is told apart.
     *
     * It is outside every real condition on purpose (the enabled flag, a live declaration, quiet
     * hours, the 90-minute interval), and it records nothing the worker reads: a demo must not
     * delay, replace or suppress a real suggestion. Only the demo notification and its token
     * change. Usage access is not read either, because nothing is observed.
     */
    fun postDemo(body: String, store: HimaSuggestStore): Boolean = synchronized(LOCK) {
        if (!notificationsAllowed()) return false
        postLocked(HimaSuggest.DEMO_NOTIFICATION_ID, body, demoPendingIntent(store), DEMO_SUB_TEXT)
    }

    /** Cancels only the real suggestion; the demo notification has its own ID. */
    fun cancel() {
        synchronized(LOCK) {
            NotificationManagerCompat.from(context).cancel(HimaSuggest.NOTIFICATION_ID)
        }
    }

    /**
     * Drops the demo notification and its token, so a tap on a notification the user already
     * dismissed does nothing instead of declaring later.
     */
    fun cancelDemo(store: HimaSuggestStore) {
        synchronized(LOCK) {
            NotificationManagerCompat.from(context).cancel(HimaSuggest.DEMO_NOTIFICATION_ID)
            store.demoNotificationToken = null
        }
    }

    private fun notificationsAllowed(): Boolean {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return false
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    @SuppressLint("MissingPermission") // every caller checked notificationsAllowed() first
    private fun postLocked(
        id: Int,
        body: String,
        contentIntent: PendingIntent,
        subText: String? = null,
    ): Boolean {
        ensureChannel()
        val notification = NotificationCompat.Builder(context, HimaSuggest.NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_hima)
            .setContentTitle(TITLE)
            .setContentText(body)
            .apply { if (subText != null) setSubText(subText) }
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .build()
        NotificationManagerCompat.from(context).notify(id, notification)
        return true
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

    private fun declarePendingIntent(store: HimaSuggestStore): PendingIntent {
        // See [HimaSuggestStore.notificationToken]. FLAG_UPDATE_CURRENT below swaps the extras
        // of the one PendingIntent, so the posted notification always carries the latest token.
        val token = UUID.randomUUID().toString()
        store.notificationToken = token
        val intent = Intent(context, MainActivity::class.java)
            .putExtra(HimaSuggest.ACTION_EXTRA, HimaSuggest.ACTION_DECLARE)
            .putExtra(HimaSuggest.TOKEN_EXTRA, token)
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun demoPendingIntent(store: HimaSuggestStore): PendingIntent {
        // See [HimaSuggestStore.demoNotificationToken]. The demo action and token are separate
        // from the real ones, so accepting one tap cannot consume or forge the other. The demo
        // notification is replaced in place (FLAG_UPDATE_CURRENT plus its own request code), and
        // each post mints a new token, so only the visible notification's tap is accepted.
        val token = UUID.randomUUID().toString()
        store.demoNotificationToken = token
        val intent = Intent(context, MainActivity::class.java)
            .putExtra(HimaSuggest.ACTION_EXTRA, HimaSuggest.ACTION_DEMO_DECLARE)
            .putExtra(HimaSuggest.TOKEN_EXTRA, token)
        return PendingIntent.getActivity(
            context,
            HimaSuggest.DEMO_PENDING_INTENT_REQUEST,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    companion object {
        const val TITLE = "いまひまじゃない？"
        const val USUAL_BODY = "いつものひまな時間だよ。ひまなら友達に知らせよう"

        /** Serializes posting and cancelling so a disable cannot be followed by a late post. */
        private val LOCK = Any()

        private const val KIND_APP = "app"
        private const val KIND_USUAL = "usual"
        private const val DEMO_SUB_TEXT = "デモ"
        private const val DEMO_DEFAULT_LABEL = "YouTube"

        fun appBody(label: String): String = "$label 見てる？ ひまなら友達に知らせよう"

        /**
         * Body of a demo notification, or null for a kind this build does not know. The kinds
         * reuse the real bodies so the demo shows exactly what a real suggestion would.
         */
        fun demoBody(kind: String?, label: String?): String? = when (kind) {
            KIND_APP -> appBody(label?.takeIf { it.isNotBlank() } ?: DEMO_DEFAULT_LABEL)
            KIND_USUAL -> USUAL_BODY
            else -> null
        }
    }
}
