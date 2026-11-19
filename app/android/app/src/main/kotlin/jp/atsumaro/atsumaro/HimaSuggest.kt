package jp.atsumaro.atsumaro

import android.content.Context

/**
 * Values shared by the channel, the worker and the notification.
 *
 * The native side owns one SharedPreferences file ([PREFS_NAME]); Dart only reaches it
 * through the [CHANNEL] MethodChannel so the two halves can never disagree about keys.
 */
internal object HimaSuggest {
    const val CHANNEL = "jp.atsumaro.atsumaro/suggest"
    const val PREFS_NAME = "hima_suggest"
    const val WORK_NAME = "hima-suggest"

    const val EVENT_ACTION = "onAction"

    const val ACTION_EXTRA = "hima_suggest_action"
    const val TOKEN_EXTRA = "hima_suggest_token"

    /**
     * True on the 「今はいい」 broadcast of the demo notification. It travels as an extra rather
     * than as a second receiver, because the two differ only in what they are allowed to touch:
     * the demo one dismisses the demo notification and nothing else.
     */
    const val DEMO_EXTRA = "hima_suggest_demo"

    /** Tap of the notification body: open the app and offer the mood picker. */
    const val ACTION_DECLARE = "declare"

    /**
     * 「ひまにする」: open the app and declare at once, without the picker. A separate action
     * rather than an extra on [ACTION_DECLARE], so Dart decides what to do from one string and
     * a build that predates the buttons cannot mistake one for the other.
     */
    const val ACTION_DECLARE_NOW = "declare_now"

    /**
     * Tap action of the developer demo notification (see `HimaSuggestNotifier.postDemo`). It is
     * a distinct string so Dart can tell a demo tap from a real suggestion: outside demo mode it
     * ignores `demo_declare` instead of opening the declaration flow.
     */
    const val ACTION_DEMO_DECLARE = "demo_declare"

    /** 「ひまにする」 of the demo notification; the demo session maps it to [ACTION_DECLARE_NOW]. */
    const val ACTION_DEMO_DECLARE_NOW = "demo_declare_now"

    // A new id, not an edit: Android keeps the importance a channel was created with, so the
    // old channel could never become a heads-up one.
    const val NOTIFICATION_CHANNEL_ID = "hima_suggest_alert"
    const val LEGACY_NOTIFICATION_CHANNEL_ID = "hima_suggest"
    const val NOTIFICATION_CHANNEL_NAME = "ひま提案"
    const val NOTIFICATION_ID = 1001

    /**
     * The demo notification gets its own ID and PendingIntent request code, so posting it can
     * never replace a real suggestion that is still in the shade, and cancelling or tapping one
     * never touches the other.
     */
    const val DEMO_NOTIFICATION_ID = 1002
    const val DEMO_PENDING_INTENT_REQUEST = 1

    val DEFAULT_TARGETS = listOf("com.twitter.android", "com.google.android.youtube")

    /**
     * Lengths of target use a suggestion may require, in the order the settings screen shows
     * them. The worker has no UI of its own, so the channel rejects anything else instead of
     * rounding it into a neighbour: the user would otherwise see a threshold they never chose.
     */
    val APP_TRIGGER_MINUTE_CHOICES = listOf(5, 15, 30, 60)
    const val DEFAULT_APP_TRIGGER_MINUTES = 5

    // A target the user removed and later re-added may not be installed; the spec still
    // wants a readable name, and the package name is the last resort.
    private val displayNames = mapOf(
        "com.twitter.android" to "X",
        "com.google.android.youtube" to "YouTube",
    )

    fun isInstalled(context: Context, packageName: String): Boolean = runCatching {
        @Suppress("DEPRECATION")
        context.packageManager.getApplicationInfo(packageName, 0)
    }.isSuccess

    fun label(context: Context, packageName: String): String {
        @Suppress("DEPRECATION")
        val info = runCatching { context.packageManager.getApplicationInfo(packageName, 0) }.getOrNull()
            ?: return displayNames[packageName] ?: packageName
        return context.packageManager.getApplicationLabel(info).toString()
    }
}
