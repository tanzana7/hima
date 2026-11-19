package jp.atsumaro.atsumaro

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 「今はいい」: the user does not want another suggestion for a while.
 *
 * A receiver rather than the activity, because the point of the button is that the app stays
 * closed. It is declared in the manifest with `android:exported="false"` and started by an
 * explicit PendingIntent, so no other app can silence the suggestion; the token check is the same
 * second guard the body tap uses (see [HimaSuggestStore.notificationToken]).
 */
internal class HimaSuggestSnoozeReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val token = intent.getStringExtra(HimaSuggest.TOKEN_EXTRA)
        // The receiver gets a restricted context, so everything that outlives this call is built
        // from the application one.
        val appContext = context.applicationContext
        val store = HimaSuggestStore(appContext)
        if (intent.getBooleanExtra(HimaSuggest.DEMO_EXTRA, false)) {
            // The demo notification only dismisses itself. Recording a snooze here would silence
            // the real worker from a developer tool, which is exactly what the demo is not
            // allowed to do; what the demo's own declaration state shows lives in Dart memory.
            if (token == null || token != store.demoNotificationToken) return
            HimaSuggestNotifier(appContext).cancelDemo(store)
            return
        }
        if (token == null || token != store.notificationToken) return
        // One call records the pause and cancels the notification, under the lock the worker's
        // post takes: a run that was already posting cannot slip a suggestion into the shade after
        // the user asked for two quiet hours. It drops the token as well, so a PendingIntent
        // replayed after the pause was granted can neither extend it nor declare.
        HimaSuggestNotifier(appContext).snooze(store, SNOOZE_MS)
    }

    private companion object {
        /** How long 「今はいい」 keeps the worker quiet. */
        const val SNOOZE_MS = 2 * 60 * 60 * 1000L
    }
}
