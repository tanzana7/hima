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
    const val ACTION_DECLARE = "declare"

    /**
     * Tap action of the developer demo notification (see `HimaSuggestNotifier.postDemo`). It is
     * a distinct string so Dart can tell a demo tap from a real suggestion: outside demo mode it
     * ignores `demo_declare` instead of opening the declaration flow.
     */
    const val ACTION_DEMO_DECLARE = "demo_declare"

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
