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

    // A new id, not an edit: Android keeps the importance a channel was created with, so the
    // old channel could never become a heads-up one.
    const val NOTIFICATION_CHANNEL_ID = "hima_suggest_alert"
    const val LEGACY_NOTIFICATION_CHANNEL_ID = "hima_suggest"
    const val NOTIFICATION_CHANNEL_NAME = "ひま提案"
    const val NOTIFICATION_ID = 1001

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
