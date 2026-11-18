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
    const val ACTION_DECLARE = "declare"

    const val NOTIFICATION_CHANNEL_ID = "hima_suggest"
    const val NOTIFICATION_CHANNEL_NAME = "ひま提案"
    const val NOTIFICATION_ID = 1001

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
