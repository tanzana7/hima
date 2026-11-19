package jp.atsumaro.atsumaro

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.text.Collator
import java.util.Locale

/**
 * Dart-facing half of 自動ひま提案. Method handlers already run on the main thread, so every
 * method answers synchronously except the API 33+ notification permission request.
 */
internal class SuggestChannelHandler(private val activity: Activity) : MethodChannel.MethodCallHandler {

    private val store = HimaSuggestStore(activity)
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getState" -> result.success(state())
                "setEnabled" -> result.success(setEnabled(call.arguments as? Boolean ?: false))
                "setTargets" -> result.success(setTargets(packagesArgument(call.arguments)))
                "setAppTriggerMinutes" -> setAppTriggerMinutes(call.arguments, result)
                "listLaunchableApps" -> result.success(launchableApps())
                "openUsageAccessSettings" -> {
                    openUsageAccessSettings()
                    result.success(null)
                }
                "requestNotificationPermission" -> requestNotificationPermission(result)
                "setDeclaredUntil" -> {
                    store.declaredUntil = (call.arguments as? Number)?.toLong()
                    result.success(null)
                }
                "setForecast" -> {
                    store.forecast = forecastArgument(call.arguments)
                    result.success(null)
                }
                "clear" -> {
                    clear()
                    result.success(null)
                }
                "postDemoSuggestion" -> postDemoSuggestion(call.arguments, result)
                "cancelDemoSuggestion" -> {
                    HimaSuggestNotifier(activity).cancelDemo(store)
                    result.success(null)
                }
                "takePendingAction" -> result.success(
                    store.pendingAction.also { store.pendingAction = null },
                )
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("suggest_error", e.message ?: e.javaClass.simpleName, null)
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != PERMISSION_REQUEST_NOTIFICATIONS) return
        val result = pendingPermissionResult ?: return
        pendingPermissionResult = null
        result.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
    }

    private fun state(): Map<String, Any?> = mapOf(
        "enabled" to store.enabled,
        "targets" to store.targets.map { packageName ->
            mapOf(
                "package" to packageName,
                "label" to HimaSuggest.label(activity, packageName),
                "installed" to HimaSuggest.isInstalled(activity, packageName),
            )
        },
        "usageAccess" to UsageAccess.isGranted(activity),
        "notificationsAllowed" to NotificationManagerCompat.from(activity).areNotificationsEnabled(),
        "appTriggerMinutes" to store.appTriggerMinutes,
    )

    private fun setEnabled(enabled: Boolean): Map<String, Any?> {
        store.enabled = enabled
        if (enabled) {
            HimaSuggestScheduler.schedule(activity)
        } else {
            HimaSuggestScheduler.cancel(activity)
            HimaSuggestNotifier(activity).cancel()
        }
        return state()
    }

    private fun setTargets(packages: List<String>): Map<String, Any?> {
        // Order is the user's; duplicates would only make the list ambiguous.
        store.targets = packages.distinct()
        return state()
    }

    /**
     * Stores how long the target apps must be used before a suggestion.
     *
     * Only the choices the settings screen offers are accepted: a threshold the user cannot see
     * or change is worse than a failed call, which the screen reports as a failed save.
     */
    private fun setAppTriggerMinutes(arguments: Any?, result: MethodChannel.Result) {
        val minutes = exactMinutes((arguments as? Map<*, *>)?.get("minutes"))
        if (minutes == null || minutes !in HimaSuggest.APP_TRIGGER_MINUTE_CHOICES) {
            result.error(
                "bad_args",
                "minutes must be one of ${HimaSuggest.APP_TRIGGER_MINUTE_CHOICES}",
                null,
            )
            return
        }
        store.appTriggerMinutes = minutes
        result.success(state())
    }

    /**
     * [value] as a whole number of minutes, or null when it is not one.
     *
     * A fractional value is rejected rather than truncated: `5.9` would otherwise be stored as
     * 5, a length the caller never asked for, and the screen would then show a choice it did not
     * send.
     */
    private fun exactMinutes(value: Any?): Int? {
        val amount = (value as? Number)?.toDouble() ?: return null
        val minutes = amount.toInt()
        return if (minutes.toDouble() == amount) minutes else null
    }

    private fun packagesArgument(arguments: Any?): List<String> =
        (arguments as? List<*>)?.mapNotNull { it as? String }.orEmpty()

    private fun forecastArgument(arguments: Any?): List<ForecastSlot> =
        // Dart forwards the server cache; a malformed entry is dropped instead of failing the
        // whole sync, so one bad slot cannot freeze the usual-time trigger.
        (arguments as? List<*>)?.mapNotNull { entry ->
            val entry = entry as? Map<*, *> ?: return@mapNotNull null
            val weekday = (entry["weekday"] as? Number)?.toInt() ?: return@mapNotNull null
            val startMin = (entry["start_min"] as? Number)?.toInt() ?: return@mapNotNull null
            val endMin = (entry["end_min"] as? Number)?.toInt() ?: return@mapNotNull null
            if (weekday in 0..6 && startMin >= 0 && endMin > startMin) {
                ForecastSlot(weekday, startMin, endMin)
            } else {
                null
            }
        }.orEmpty()

    private fun launchableApps(): List<Map<String, Any>> {
        val packageManager = activity.packageManager
        val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val collator = Collator.getInstance(Locale.JAPANESE)
        return packageManager.queryIntentActivities(launcherIntent, 0)
            .asSequence()
            .filter { it.activityInfo.packageName != activity.packageName }
            .map { it.activityInfo.packageName to it.loadLabel(packageManager).toString() }
            .distinctBy { it.first }
            .sortedWith(Comparator<Pair<String, String>> { a, b -> collator.compare(a.second, b.second) })
            .map { mapOf<String, Any>("package" to it.first, "label" to it.second) }
            .toList()
    }

    private fun openUsageAccessSettings() {
        val withPackage = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            .setData(Uri.fromParts("package", activity.packageName, null))
        try {
            activity.startActivity(withPackage)
        } catch (e: ActivityNotFoundException) {
            // Some OEM builds ignore the package filter; the unscoped screen still works.
            activity.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(NotificationManagerCompat.from(activity).areNotificationsEnabled())
            return
        }
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        pendingPermissionResult?.success(NotificationManagerCompat.from(activity).areNotificationsEnabled())
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            PERMISSION_REQUEST_NOTIFICATIONS,
        )
    }

    private fun clear() {
        store.enabled = false
        store.clearSuggestionState()
        HimaSuggestScheduler.cancel(activity)
        HimaSuggestNotifier(activity).cancel()
    }

    /**
     * Developer demo post: answers whether the notification was posted or scheduled. A missing or
     * unknown kind is a Dart/native contract mismatch, so it fails instead of posting a
     * notification whose body nobody can interpret.
     *
     * `marked` and `delayMs` are optional so a Dart side that predates them still works: it means
     * a marked notification posted immediately.
     */
    private fun postDemoSuggestion(arguments: Any?, result: MethodChannel.Result) {
        val args = arguments as? Map<*, *>
        val body = HimaSuggestNotifier.demoBody(args?.get("kind") as? String, args?.get("label") as? String)
        if (body == null) {
            result.error("bad_args", "unknown demo suggestion kind", null)
            return
        }
        val marked = args?.get("marked") as? Boolean ?: true
        val delayMs = (args?.get("delayMs") as? Number)?.toLong() ?: 0L
        result.success(HimaSuggestNotifier(activity).postDemo(body, store, marked, delayMs.coerceAtLeast(0L)))
    }

    private companion object {
        const val PERMISSION_REQUEST_NOTIFICATIONS = 4301
    }
}
