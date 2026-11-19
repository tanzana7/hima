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
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import java.util.UUID

internal class HimaSuggestNotifier(private val context: Context) {

    /**
     * Posts only while the feature and the user both allow it.
     *
     * The worker reads the same conditions before it decides to post, but it can be half-way
     * through that decision when the user declares or presses 「今はいい」. Every suppression takes
     * the lock this method holds, and the conditions are re-read here, so a suggestion cannot
     * appear right after the user asked for none.
     */
    fun post(body: String, store: HimaSuggestStore): Boolean = synchronized(LOCK) {
        if (!store.enabled) return false
        val now = System.currentTimeMillis()
        if (store.declaredUntil?.let { it > now } == true) return false
        if (store.snoozeUntil?.let { it > now } == true) return false
        if (!notificationsAllowed()) return false
        postLocked(HimaSuggest.NOTIFICATION_ID, body, realToken(store), demo = false)
    }

    /**
     * Mirrors the live declaration and takes the posted suggestion away, as one step.
     *
     * The write and the cancel are under the lock [post] takes, and [post] reads the declaration
     * before it notifies: a run that had already begun to post is either refused or cancelled
     * here, so the user never sees a suggestion describing the session they just started. An
     * expiry in the past means "not declared" and must not touch a posted suggestion.
     */
    fun applyDeclaredUntil(store: HimaSuggestStore, until: Long?) {
        synchronized(LOCK) {
            store.declaredUntil = until
            if (until != null && until > System.currentTimeMillis()) cancelLocked(store)
        }
    }

    /**
     * 「今はいい」: pauses the suggestions and takes the posted one away, as one step.
     *
     * Same reason as [applyDeclaredUntil]: recording the pause and cancelling under one lock is
     * what stops a worker run that was already posting from putting a new suggestion in the shade
     * during the pause. [cancelLocked] drops the token too, so the dismissed notification's
     * buttons can never be sent again.
     */
    fun snooze(store: HimaSuggestStore, durationMs: Long) {
        synchronized(LOCK) {
            store.snoozeUntil = System.currentTimeMillis() + durationMs
            cancelLocked(store)
        }
    }

    /**
     * Posts the developer demo variant: same channel, icon, title and bodies as a real
     * suggestion, so it can be checked visually. [marked] adds a "デモ" subtext so it is told
     * apart; the app's 撮影モード turns it off so a recording shows a notification that looks
     * exactly like a real one.
     *
     * A nonzero [delayMs] schedules the post instead of posting it now. It runs on the main
     * looper, because that is the only timer that still fires once the app is in the background,
     * where the owner is while another app fills the screen.
     *
     * It is outside every real condition on purpose (the enabled flag, a live declaration, a
     * 「今はいい」 pause, quiet hours, the 90-minute interval), and it records nothing the worker
     * reads: a demo must not delay, replace or suppress a real suggestion. Only the demo
     * notification and its token change, and its 「今はいい」 only dismisses it (see
     * [HimaSuggestSnoozeReceiver]). Usage access is not read either, because nothing is observed.
     *
     * Answers false at once when notifications are not allowed, and true once the notification
     * was posted or scheduled.
     */
    fun postDemo(body: String, store: HimaSuggestStore, marked: Boolean, delayMs: Long): Boolean =
        synchronized(LOCK) {
            // Every request replaces the one that has not fired yet, including a request that is
            // refused below: a post left queued by an earlier tap would otherwise still be waiting
            // and could appear once the permission is granted again.
            cancelPendingDemoLocked()
            if (!notificationsAllowed()) return false
            if (delayMs <= 0L) return postDemoLocked(body, store, marked)
            // Declared before the runnable so the runnable can recognise itself as the one that
            // is still pending.
            lateinit var task: Runnable
            task = Runnable {
                synchronized(LOCK) {
                    // Cancelled or replaced between the delay elapsing and this run: it must not
                    // post, even where removeCallbacks already missed it.
                    if (pendingDemo === task) {
                        pendingDemo = null
                        // The permission can be revoked during the delay, so it is read again
                        // here rather than trusted from when the post was scheduled.
                        if (notificationsAllowed()) postDemoLocked(body, store, marked)
                    }
                }
            }
            pendingDemo = task
            mainHandler.postDelayed(task, delayMs)
            true
        }

    /**
     * Cancels the real suggestion, and drops its token with it.
     *
     * The token goes no later than the notification: a PendingIntent that was already handed to
     * the system must not be accepted once the suggestion is gone. The demo notification has its
     * own ID and token, so it is untouched.
     */
    fun cancel(store: HimaSuggestStore) {
        synchronized(LOCK) { cancelLocked(store) }
    }

    private fun cancelLocked(store: HimaSuggestStore) {
        NotificationManagerCompat.from(context).cancel(HimaSuggest.NOTIFICATION_ID)
        store.notificationToken = null
    }

    /**
     * Drops the demo notification and its token, so a tap on a notification the user already
     * dismissed does nothing instead of declaring later.
     *
     * A demo post that is still waiting is dropped here too: ending the demo must never be
     * followed by the notification it had scheduled.
     */
    fun cancelDemo(store: HimaSuggestStore) {
        synchronized(LOCK) {
            cancelPendingDemoLocked()
            NotificationManagerCompat.from(context).cancel(HimaSuggest.DEMO_NOTIFICATION_ID)
            store.demoNotificationToken = null
        }
    }

    private fun cancelPendingDemoLocked() {
        pendingDemo?.let { mainHandler.removeCallbacks(it) }
        pendingDemo = null
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
        token: String,
        demo: Boolean,
        subText: String? = null,
    ): Boolean {
        ensureChannel()
        val notification = NotificationCompat.Builder(context, HimaSuggest.NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_hima)
            .setContentTitle(TITLE)
            .setContentText(body)
            // The body is trimmed to the collapsed row; expanding shows all of it instead of
            // clipping the tail, which the shade otherwise does at two lines.
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .apply { if (subText != null) setSubText(subText) }
            // The suggestion arrives while another app fills the screen, so it has to appear on
            // top of it; a silent entry in the shade is seen only after the moment has passed.
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            // A suggestion describes now. Left alone it would still be there hours later, when
            // both buttons and the mood picker it opens would be answering a moment that has
            // passed, so the notification removes itself.
            .setTimeoutAfter(TIMEOUT_MS)
            .setContentIntent(contentIntent(token, demo))
            .addAction(0, DECLARE_NOW_LABEL, declareNowIntent(token, demo))
            .addAction(0, SNOOZE_LABEL, snoozeIntent(token, demo))
            .build()
        NotificationManagerCompat.from(context).notify(id, notification)
        return true
    }

    private fun postDemoLocked(body: String, store: HimaSuggestStore, marked: Boolean): Boolean =
        postLocked(
            HimaSuggest.DEMO_NOTIFICATION_ID,
            body,
            demoToken(store),
            demo = true,
            subText = if (marked) DEMO_SUB_TEXT else null,
        )

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        if (manager.getNotificationChannel(HimaSuggest.NOTIFICATION_CHANNEL_ID) != null) return
        manager.deleteNotificationChannel(HimaSuggest.LEGACY_NOTIFICATION_CHANNEL_ID)
        manager.createNotificationChannel(
            NotificationChannel(
                HimaSuggest.NOTIFICATION_CHANNEL_ID,
                HimaSuggest.NOTIFICATION_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH,
            ),
        )
    }

    /**
     * Mints the one-time token of the real suggestion and stores it for [MainActivity].
     *
     * See [HimaSuggestStore.notificationToken]. One token per post is shared by the body tap and
     * by 「ひまにする」: both describe the same notification, and accepting either clears it, so
     * the other button of a notification that was already acted on does nothing.
     */
    private fun realToken(store: HimaSuggestStore): String {
        val token = UUID.randomUUID().toString()
        store.notificationToken = token
        return token
    }

    /**
     * The demo counterpart of [realToken]. The demo action and token are separate from the real
     * ones, so accepting one tap cannot consume or forge the other; each post mints a new token,
     * so only the visible notification's buttons are accepted.
     */
    private fun demoToken(store: HimaSuggestStore): String {
        val token = UUID.randomUUID().toString()
        store.demoNotificationToken = token
        return token
    }

    /** The body tap: opens the app and offers the mood picker, exactly as before the buttons. */
    private fun contentIntent(token: String, demo: Boolean): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .putExtra(
                HimaSuggest.ACTION_EXTRA,
                if (demo) HimaSuggest.ACTION_DEMO_DECLARE else HimaSuggest.ACTION_DECLARE,
            )
            .putExtra(HimaSuggest.TOKEN_EXTRA, token)
        return PendingIntent.getActivity(
            context,
            if (demo) HimaSuggest.DEMO_PENDING_INTENT_REQUEST else DECLARE_REQUEST,
            intent,
            PENDING_INTENT_FLAGS,
        )
    }

    /** 「ひまにする」: opens the app, which declares without asking. */
    private fun declareNowIntent(token: String, demo: Boolean): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .putExtra(
                HimaSuggest.ACTION_EXTRA,
                if (demo) HimaSuggest.ACTION_DEMO_DECLARE_NOW else HimaSuggest.ACTION_DECLARE_NOW,
            )
            .putExtra(HimaSuggest.TOKEN_EXTRA, token)
        return PendingIntent.getActivity(
            context,
            if (demo) DEMO_DECLARE_NOW_REQUEST else DECLARE_NOW_REQUEST,
            intent,
            PENDING_INTENT_FLAGS,
        )
    }

    /**
     * 「今はいい」: dismisses the suggestion and pauses it for a while.
     *
     * A broadcast, not the activity: the whole point is that the app does not open. The receiver
     * is not exported and this explicit intent names it, so this PendingIntent is the only way to
     * reach it.
     */
    private fun snoozeIntent(token: String, demo: Boolean): PendingIntent {
        val intent = Intent(context, HimaSuggestSnoozeReceiver::class.java)
            .putExtra(HimaSuggest.TOKEN_EXTRA, token)
            .putExtra(HimaSuggest.DEMO_EXTRA, demo)
        return PendingIntent.getBroadcast(
            context,
            if (demo) DEMO_SNOOZE_REQUEST else SNOOZE_REQUEST,
            intent,
            PENDING_INTENT_FLAGS,
        )
    }

    companion object {
        const val TITLE = "いまひまじゃない？"
        const val USUAL_BODY = "いつものひまな時間だよ。友達に知らせよう"

        const val DECLARE_NOW_LABEL = "ひまにする"
        const val SNOOZE_LABEL = "今はいい"

        /** Serializes posting and cancelling so a disable cannot be followed by a late post. */
        private val LOCK = Any()

        /**
         * How long a posted suggestion stays in the shade.
         *
         * Long enough to press a button after the phone was picked up again, short enough that a
         * suggestion never reappears hours later attached to a moment that is over.
         */
        private const val TIMEOUT_MS = 30 * 60 * 1000L

        /**
         * Request codes of the notification's PendingIntents. Each action needs its own: with an
         * equal extra set, two PendingIntents that share a request code are the same instance, so
         * one button's click would replace another's.
         */
        private const val DECLARE_REQUEST = 0
        private const val DECLARE_NOW_REQUEST = 2
        private const val DEMO_DECLARE_NOW_REQUEST = 3
        private const val SNOOZE_REQUEST = 4
        private const val DEMO_SNOOZE_REQUEST = 5

        /**
         * FLAG_UPDATE_CURRENT swaps the extras of a PendingIntent that already exists, so a post
         * replaces the token of the notification it replaces instead of leaving the previous one
         * usable.
         */
        private const val PENDING_INTENT_FLAGS =
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT

        /**
         * The demo post that has been scheduled but has not run yet.
         *
         * Process-wide, not per instance: a notifier is created per channel call, while the
         * scheduled post and the cancel that has to replace it arrive in separate calls.
         */
        private var pendingDemo: Runnable? = null

        /** Created on first use: only a scheduled demo post ever needs it. */
        private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

        private const val KIND_APP = "app"
        private const val KIND_USUAL = "usual"
        private const val DEMO_SUB_TEXT = "デモ"
        private const val DEMO_DEFAULT_LABEL = "YouTube"

        fun appBody(label: String): String = "$label 見てる？ 友達に知らせよう"

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
