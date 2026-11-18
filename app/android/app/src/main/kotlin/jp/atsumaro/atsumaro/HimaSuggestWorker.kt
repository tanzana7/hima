package jp.atsumaro.atsumaro

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

/**
 * Periodic check behind 自動ひま提案. It only ever posts a notification; declaring stays a user
 * action, so a wrong guess never writes session state.
 */
internal class HimaSuggestWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        val now = System.currentTimeMillis()
        try {
            check(now)
        } catch (t: Throwable) {
            // Return success even on an unexpected failure: a periodic worker that reports
            // failure is retried with the same broken input, and the next 15-minute run is a
            // better retry. The log keeps the cause visible.
            Log.w(TAG, "hima suggestion check failed", t)
        }
        return Result.success()
    }

    private fun check(now: Long) {
        val context = applicationContext
        val store = HimaSuggestStore(context)
        val targets = store.targets
        if (!store.enabled || !UsageAccess.isGranted(context) || targets.isEmpty()) {
            store.lastRunAt = now
            return
        }

        // The carried state can be older than the query window after a long Doze, so the
        // window is capped at 2 hours; observations then cover only what was really queried.
        val windowStart = maxOf(store.lastRunAt, now - MAX_USAGE_WINDOW_MS).coerceAtMost(now)
        val snapshot = TargetUsageReader.read(context, windowStart, now, store.carriedForeground)
        store.carriedForeground = snapshot.carried
        recordObservations(store, windowStart, now, snapshot.intervals, targets.toSet())
        store.lastRunAt = now

        if (store.declaredUntil?.let { it > now } == true) return
        if (now - store.lastSuggestAt < SUGGEST_INTERVAL_MS) return
        val minutesOfDay = TokyoTime.minutesOfDay(now)
        if (minutesOfDay in QUIET_HOURS_START until QUIET_HOURS_END) return

        val appLabel = appTriggerLabel(context, snapshot, targets, now)
        if (appLabel != null) {
            HimaSuggestNotifier(context).post(HimaSuggestNotifier.appBody(appLabel))
            store.lastSuggestAt = now
            return
        }

        if (fireUsualTime(store, now, minutesOfDay)) {
            HimaSuggestNotifier(context).post(HimaSuggestNotifier.USUAL_BODY)
            store.lastSuggestAt = now
        }
    }

    /** Label of the target that triggered the app suggestion, or null when it did not fire. */
    private fun appTriggerLabel(
        context: Context,
        snapshot: UsageSnapshot,
        targets: List<String>,
        now: Long,
    ): String? {
        val targetPackages = targets.toSet()
        val foreground = snapshot.foregroundPackage?.takeIf { it in targetPackages }
        val recentStart = now - APP_TRIGGER_WINDOW_MS
        val recentMs = snapshot.intervals
            .filter { it.packageName in targetPackages && it.endMs > recentStart }
            .sumOf { it.endMs - maxOf(it.startMs, recentStart) }
        if (foreground == null && recentMs < APP_TRIGGER_MINUTES_MS) return null

        // The most recent target names the app in the body; the foreground app is by
        // definition the most recent one when it is a target.
        val mostRecent = foreground
            ?: snapshot.intervals
                .filter { it.packageName in targetPackages }
                .maxByOrNull { it.endMs }
                ?.packageName
            ?: targets.first()
        return HimaSuggest.label(context, mostRecent)
    }

    /**
     * Fires once per usual range and day. The range starts 15 minutes early so a run that is
     * delayed by Doze still lands inside the range instead of losing the whole slot.
     */
    private fun fireUsualTime(store: HimaSuggestStore, now: Long, minutesOfDay: Int): Boolean {
        val todayWeekday = TokyoTime.weekday(now)
        val dateKey = TokyoTime.dateKey(now)
        val notified = store.notifiedSlots()
        for (range in UsualTimeRanges.build(store)) {
            if (range.weekday != todayWeekday) continue
            if (minutesOfDay < range.startMin - LEAD_MINUTES) continue
            if (minutesOfDay >= range.endMin - LEAD_MINUTES) continue
            if (!notified.add("$dateKey#${range.startMin}")) continue
            store.saveNotifiedSlots(notified, now)
            return true
        }
        return false
    }

    private fun recordObservations(
        store: HimaSuggestStore,
        windowStart: Long,
        now: Long,
        intervals: List<ForegroundInterval>,
        targets: Set<String>,
    ) {
        val observations = store.observations()
        forEachSlot(windowStart, now) { date, weekday, slot, _, _ ->
            val day = observations.getOrPut(date) { DayObservation(weekday, unobserved()) }
            day.minutes[slot] = maxOf(day.minutes[slot], 0)
        }
        for (interval in intervals) {
            if (interval.packageName !in targets) continue
            forEachSlot(interval.startMs, interval.endMs) { date, weekday, slot, from, to ->
                val day = observations.getOrPut(date) { DayObservation(weekday, unobserved()) }
                val previous = maxOf(day.minutes[slot], 0)
                day.minutes[slot] = previous + Math.round((to - from).toDouble() / MINUTE_MS).toInt()
            }
        }
        val oldestKeptDate = TokyoTime.dateKeyDaysAgo(OBSERVATION_RETENTION_DAYS - 1, now)
        observations.keys.retainAll { it >= oldestKeptDate }
        store.saveObservations(observations)
    }

    private inline fun forEachSlot(
        startMs: Long,
        endMs: Long,
        block: (date: String, weekday: Int, slot: Int, from: Long, to: Long) -> Unit,
    ) {
        var cursor = startMs
        while (cursor < endMs) {
            val slotStart = TokyoTime.slotStart(cursor)
            val slotEnd = slotStart + TokyoTime.SLOT_MINUTES * MINUTE_MS
            val segmentEnd = minOf(slotEnd, endMs)
            val slot = ((slotStart - TokyoTime.startOfDay(cursor)) / (TokyoTime.SLOT_MINUTES * MINUTE_MS)).toInt()
            block(TokyoTime.dateKey(cursor), TokyoTime.weekday(cursor), slot, cursor, segmentEnd)
            cursor = segmentEnd
        }
    }

    private fun unobserved() = IntArray(TokyoTime.SLOTS_PER_DAY) { -1 }

    private companion object {
        const val TAG = "HimaSuggest"

        const val MINUTE_MS = 60_000L
        const val MAX_USAGE_WINDOW_MS = 2 * 60 * MINUTE_MS
        const val SUGGEST_INTERVAL_MS = 90 * MINUTE_MS
        const val APP_TRIGGER_WINDOW_MS = 15 * MINUTE_MS
        const val APP_TRIGGER_MINUTES_MS = 5 * MINUTE_MS
        const val OBSERVATION_RETENTION_DAYS = 35

        const val QUIET_HOURS_START = 2 * 60
        const val QUIET_HOURS_END = 7 * 60
        const val LEAD_MINUTES = 15
    }
}
