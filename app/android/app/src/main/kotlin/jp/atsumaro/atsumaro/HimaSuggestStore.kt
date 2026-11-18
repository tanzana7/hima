package jp.atsumaro.atsumaro

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

internal data class ForecastSlot(val weekday: Int, val startMin: Int, val endMin: Int)

/**
 * Foreground state handed from one worker run to the next, so a target-app session that
 * started before the query window is still counted. The screen flag rides along because the
 * next run has no other way to tell whether a still-open session is really in front of the
 * user when the last screen event fell outside its window.
 */
internal data class CarriedForeground(
    val packageName: String?,
    val sinceMs: Long,
    val screenInteractive: Boolean,
)

/**
 * Target-app minutes seen in one Tokyo date's 30-minute slots.
 * A slot is -1 until a worker run observes it, so "not observed" never reads as "unused".
 */
internal class DayObservation(val weekday: Int, val minutes: IntArray)

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
            screenInteractive = prefs.getBoolean(KEY_SCREEN_INTERACTIVE, true),
        )
        set(value) {
            prefs.edit().apply {
                if (value.packageName == null) {
                    remove(KEY_FOREGROUND_PACKAGE)
                } else {
                    putString(KEY_FOREGROUND_PACKAGE, value.packageName)
                }
                putLong(KEY_FOREGROUND_SINCE, value.sinceMs)
                putBoolean(KEY_SCREEN_INTERACTIVE, value.screenInteractive)
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
            val stored = item.optJSONArray("m") ?: continue
            val minutes = IntArray(TokyoTime.SLOTS_PER_DAY) { -1 }
            for (slot in 0 until minOf(stored.length(), TokyoTime.SLOTS_PER_DAY)) {
                minutes[slot] = stored.optInt(slot, -1)
            }
            result[date] = DayObservation(weekday, minutes)
        }
        return result
    }

    fun saveObservations(observations: Map<String, DayObservation>) {
        val root = JSONObject()
        observations.forEach { (date, day) ->
            root.put(date, JSONObject().put("w", day.weekday).put("m", JSONArray(day.minutes.toList())))
        }
        prefs.edit().putString(KEY_OBSERVATIONS, root.toString()).apply()
    }

    /**
     * Logout only drops what belongs to the signed-in account's suggestion history.
     * Targets and the learned slots describe the phone, so they survive a re-login.
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
        const val KEY_DECLARED_UNTIL = "declaredUntil"
        const val KEY_FORECAST = "forecast"
        const val KEY_LAST_SUGGEST_AT = "lastSuggestAt"
        const val KEY_NOTIFIED_SLOTS = "notifiedSlots"
        const val KEY_LAST_RUN_AT = "lastRunAt"
        const val KEY_FOREGROUND_PACKAGE = "foregroundPackage"
        const val KEY_FOREGROUND_SINCE = "foregroundSince"
        const val KEY_SCREEN_INTERACTIVE = "screenInteractive"
        const val KEY_OBSERVATIONS = "observations"
        const val KEY_PENDING_ACTION = "pendingAction"

        const val NOTIFIED_SLOT_RETENTION_DAYS = 7
    }
}
