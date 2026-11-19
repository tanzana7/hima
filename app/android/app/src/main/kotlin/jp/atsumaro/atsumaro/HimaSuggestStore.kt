package jp.atsumaro.atsumaro

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

internal data class ForecastSlot(val weekday: Int, val startMin: Int, val endMin: Int)

/**
 * Foreground state handed from one worker run to the next, so a target-app session that
 * started before the query window is still counted.
 *
 * Only the package travels with it: the screen state at the start of a run is rebuilt from that
 * run's own events, because the carried flag would describe the end of the previous run, which
 * is a different instant once a run reads further back (see [TargetUsageReader.read]).
 */
internal data class CarriedForeground(
    val packageName: String?,
    val sinceMs: Long,
) {
    /**
     * Ends the open interval. Used when the events between two runs were not observed:
     * carrying the package would replay a pause or a screen lock that happened in the gap as
     * "still in front".
     */
    fun withoutForeground(): CarriedForeground = copy(packageName = null, sinceMs = 0L)
}

/**
 * Target-app seconds seen in one Tokyo date's 30-minute slots.
 * A slot is -1 until a worker run observes it, so "not observed" never reads as "unused".
 *
 * Seconds, not minutes: one slot is filled by several worker runs, and rounding each run's
 * share to whole minutes before adding would turn repeated 31-second glances into minutes
 * and drop repeated 29-second ones. The threshold is applied to the stored total instead.
 */
internal class DayObservation(val weekday: Int, val seconds: IntArray)

/** Thin wrapper around the single `hima_suggest` SharedPreferences file. */
internal class HimaSuggestStore(context: Context) {
    private val prefs =
        context.applicationContext.getSharedPreferences(HimaSuggest.PREFS_NAME, Context.MODE_PRIVATE)

    var enabled: Boolean
        get() = prefs.getBoolean(KEY_ENABLED, false)
        set(value) {
            prefs.edit().putBoolean(KEY_ENABLED, value).apply()
        }

    /** Ordered target packages; the default list applies only until Dart sets its own. */
    var targets: List<String>
        get() {
            val raw = prefs.getString(KEY_TARGETS, null) ?: return HimaSuggest.DEFAULT_TARGETS
            val array = runCatching { JSONArray(raw) }.getOrNull() ?: return HimaSuggest.DEFAULT_TARGETS
            return (0 until array.length()).mapNotNull { index ->
                array.optString(index).takeIf { it.isNotEmpty() }
            }
        }
        set(value) {
            prefs.edit().putString(KEY_TARGETS, JSONArray(value).toString()).apply()
        }

    /**
     * Minutes of target use the app suggestion waits for. Like [targets] this describes the
     * phone rather than the signed-in account, so [clearSuggestionState] keeps it.
     *
     * A stored value the settings screen does not offer reads as the default: the worker must
     * always have a threshold, and guessing one from an old or foreign build is worse than
     * falling back to the default the user sees.
     */
    var appTriggerMinutes: Int
        get() = prefs.getInt(KEY_APP_TRIGGER_MINUTES, HimaSuggest.DEFAULT_APP_TRIGGER_MINUTES)
            .takeIf { it in HimaSuggest.APP_TRIGGER_MINUTE_CHOICES }
            ?: HimaSuggest.DEFAULT_APP_TRIGGER_MINUTES
        set(value) {
            prefs.edit().putInt(KEY_APP_TRIGGER_MINUTES, value).apply()
        }

    var declaredUntil: Long?
        get() = if (prefs.contains(KEY_DECLARED_UNTIL)) prefs.getLong(KEY_DECLARED_UNTIL, 0L) else null
        set(value) {
            prefs.edit().apply {
                if (value == null) remove(KEY_DECLARED_UNTIL) else putLong(KEY_DECLARED_UNTIL, value)
            }.apply()
        }

    var lastSuggestAt: Long
        get() = prefs.getLong(KEY_LAST_SUGGEST_AT, 0L)
        set(value) {
            prefs.edit().putLong(KEY_LAST_SUGGEST_AT, value).apply()
        }

    var lastRunAt: Long
        get() = prefs.getLong(KEY_LAST_RUN_AT, 0L)
        set(value) {
            prefs.edit().putLong(KEY_LAST_RUN_AT, value).apply()
        }

    /** A notification tap that Dart has not picked up yet. Cleared by `takePendingAction`. */
    var pendingAction: String?
        get() = prefs.getString(KEY_PENDING_ACTION, null)
        set(value) {
            prefs.edit().apply {
                if (value == null) remove(KEY_PENDING_ACTION) else putString(KEY_PENDING_ACTION, value)
            }.apply()
        }

    /**
     * The one-time token carried by the notification that is currently posted.
     *
     * MainActivity is the exported launcher, so any app can start it with an explicit intent
     * and copy the action extra. Only the notification's own PendingIntent knows this random
     * value, which is what makes a tap from it distinguishable from a forged launch. A new
     * post replaces it, and accepting a tap clears it, so a token works once.
     */
    var notificationToken: String?
        get() = prefs.getString(KEY_NOTIFICATION_TOKEN, null)
        set(value) {
            prefs.edit().apply {
                if (value == null) remove(KEY_NOTIFICATION_TOKEN) else putString(KEY_NOTIFICATION_TOKEN, value)
            }.apply()
        }

    var forecast: List<ForecastSlot>
        get() = parseForecast(prefs.getString(KEY_FORECAST, null))
        set(value) {
            val array = JSONArray()
            value.forEach { slot ->
                array.put(
                    JSONObject()
                        .put("weekday", slot.weekday)
                        .put("start_min", slot.startMin)
                        .put("end_min", slot.endMin),
                )
            }
            prefs.edit().putString(KEY_FORECAST, array.toString()).apply()
        }

    var carriedForeground: CarriedForeground
        get() = CarriedForeground(
            packageName = prefs.getString(KEY_FOREGROUND_PACKAGE, null),
            sinceMs = prefs.getLong(KEY_FOREGROUND_SINCE, 0L),
        )
        set(value) {
            prefs.edit().apply {
                if (value.packageName == null) {
                    remove(KEY_FOREGROUND_PACKAGE)
                } else {
                    putString(KEY_FOREGROUND_PACKAGE, value.packageName)
                }
                putLong(KEY_FOREGROUND_SINCE, value.sinceMs)
            }.apply()
        }

    fun notifiedSlots(): MutableSet<String> = HashSet(prefs.getStringSet(KEY_NOTIFIED_SLOTS, null) ?: emptySet())

    fun saveNotifiedSlots(slots: Set<String>, now: Long) {
        val oldestKeptDate = TokyoTime.dateKeyDaysAgo(NOTIFIED_SLOT_RETENTION_DAYS, now)
        val kept = slots.filterTo(HashSet()) { key -> key.substringBefore('#') >= oldestKeptDate }
        prefs.edit().putStringSet(KEY_NOTIFIED_SLOTS, kept).apply()
    }

    fun observations(): MutableMap<String, DayObservation> {
        val raw = prefs.getString(KEY_OBSERVATIONS, null)
        val result = HashMap<String, DayObservation>()
        if (raw.isNullOrEmpty()) return result
        val root = runCatching { JSONObject(raw) }.getOrNull() ?: return result
        for (date in root.keys()) {
            val item = root.optJSONObject(date) ?: continue
            val weekday = item.optInt("w", -1)
            if (weekday !in 0..6) continue
            val stored = item.optJSONArray("s") ?: continue
            val seconds = IntArray(TokyoTime.SLOTS_PER_DAY) { -1 }
            for (slot in 0 until minOf(stored.length(), TokyoTime.SLOTS_PER_DAY)) {
                seconds[slot] = stored.optInt(slot, -1)
            }
            result[date] = DayObservation(weekday, seconds)
        }
        return result
    }

    fun saveObservations(observations: Map<String, DayObservation>) {
        val root = JSONObject()
        observations.forEach { (date, day) ->
            root.put(date, JSONObject().put("w", day.weekday).put("s", JSONArray(day.seconds.toList())))
        }
        prefs.edit().putString(KEY_OBSERVATIONS, root.toString()).apply()
    }

    /**
     * Logout only drops what belongs to the signed-in account's suggestion history.
     * Targets, the learned slots and the trigger length describe the phone, so they survive a
     * re-login.
     */
    fun clearSuggestionState() {
        prefs.edit()
            .remove(KEY_DECLARED_UNTIL)
            .remove(KEY_FORECAST)
            .remove(KEY_LAST_SUGGEST_AT)
            .remove(KEY_NOTIFIED_SLOTS)
            .apply()
    }

    private fun parseForecast(raw: String?): List<ForecastSlot> {
        if (raw.isNullOrEmpty()) return emptyList()
        val array = runCatching { JSONArray(raw) }.getOrNull() ?: return emptyList()
        return (0 until array.length()).mapNotNull { index ->
            val item = array.optJSONObject(index) ?: return@mapNotNull null
            val weekday = item.optInt("weekday", -1)
            val start = item.optInt("start_min", -1)
            val end = item.optInt("end_min", -1)
            if (weekday in 0..6 && start >= 0 && end > start) ForecastSlot(weekday, start, end) else null
        }
    }

    private companion object {
        const val KEY_ENABLED = "enabled"
        const val KEY_TARGETS = "targets"
        const val KEY_APP_TRIGGER_MINUTES = "appTriggerMinutes"
        const val KEY_DECLARED_UNTIL = "declaredUntil"
        const val KEY_FORECAST = "forecast"
        const val KEY_LAST_SUGGEST_AT = "lastSuggestAt"
        const val KEY_NOTIFIED_SLOTS = "notifiedSlots"
        const val KEY_LAST_RUN_AT = "lastRunAt"
        const val KEY_FOREGROUND_PACKAGE = "foregroundPackage"
        const val KEY_FOREGROUND_SINCE = "foregroundSince"
        const val KEY_OBSERVATIONS = "observations"
        const val KEY_PENDING_ACTION = "pendingAction"
        const val KEY_NOTIFICATION_TOKEN = "notificationToken"

        const val NOTIFIED_SLOT_RETENTION_DAYS = 7
    }
}
