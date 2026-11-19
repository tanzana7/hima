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
            // No events were read, so the open interval cannot be verified. Drop it, and take
            // the live screen state: a screen-on during the gap never appears in a later
            // query, and a stale "off" would make every resume below be ignored.
            store.carriedForeground = CarriedForeground(
                packageName = null,
                sinceMs = 0L,
                screenInteractive = ScreenState.isInteractive(context),
            )
            store.lastRunAt = now
            return
        }

        val previousRunAt = store.lastRunAt
        // Only the window counts as usage, but a delayed run also has to know what the user was
        // doing when the window starts: a session that began earlier has no resume event inside
        // it. Read back to the previous run (bounded, because event history is finite) and give
        // up on that state when even the bound does not reach it.
        val windowStart = maxOf(previousRunAt, now - MAX_USAGE_WINDOW_MS).coerceAtMost(now)
        val queryStart = maxOf(previousRunAt, now - MAX_STATE_HISTORY_MS).coerceAtMost(windowStart)
        val carried = if (previousRunAt >= queryStart) {
            store.carriedForeground
        } else {
            store.carriedForeground.withoutForeground()
        }
        val snapshot = TargetUsageReader.read(context, queryStart, windowStart, now, carried)
        store.carriedForeground = snapshot.carried
        recordObservations(store, windowStart, now, snapshot.intervals, targets.toSet())
        store.lastRunAt = now

        if (store.declaredUntil?.let { it > now } == true) return
        if (now - store.lastSuggestAt < SUGGEST_INTERVAL_MS) return
        val minutesOfDay = TokyoTime.minutesOfDay(now)
        if (minutesOfDay in QUIET_HOURS_START until QUIET_HOURS_END) return

        val notifier = HimaSuggestNotifier(context)
        val appLabel = appTriggerLabel(context, snapshot, targets, now)
        if (appLabel != null) {
            if (notifier.post(HimaSuggestNotifier.appBody(appLabel), store)) {
                store.lastSuggestAt = now
            }
            return
        }

        val usualKey = usualTimeKey(store, now, minutesOfDay) ?: return
        if (!notifier.post(HimaSuggestNotifier.USUAL_BODY, store)) return
        val notified = store.notifiedSlots()
        notified.add(usualKey)
        store.saveNotifiedSlots(notified, now)
        store.lastSuggestAt = now
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
     * Key of the usual range that is due now, or null when none matches or it was already
     * suggested today. The caller records the key only after the notification was posted.
     *
     * The suggestion waits for the range to start: these are the minutes the user is usually
     * free, and just before them they may still be busy with something else. Because the worker
     * runs about every 15 minutes, it arrives up to 15 minutes into the range. The last minutes
     * are skipped so a delayed run does not suggest a free time that is already over.
     */
    private fun usualTimeKey(store: HimaSuggestStore, now: Long, minutesOfDay: Int): String? {
        val todayWeekday = TokyoTime.weekday(now)
        val dateKey = TokyoTime.dateKey(now)
        val notified = store.notifiedSlots()
        for (range in UsualTimeRanges.build(store)) {
            if (range.weekday != todayWeekday) continue
            if (minutesOfDay < range.startMin) continue
            if (minutesOfDay >= range.endMin - END_MARGIN_MINUTES) continue
            val key = "$dateKey#${range.startMin}"
            if (key !in notified) return key
        }
        return null
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
            day.seconds[slot] = maxOf(day.seconds[slot], 0)
        }
        // Sum milliseconds per slot within this run, then store seconds (see DayObservation).
        val addedMs = HashMap<String, LongArray>()
        val weekdayByDate = HashMap<String, Int>()
        for (interval in intervals) {
            if (interval.packageName !in targets) continue
            forEachSlot(interval.startMs, interval.endMs) { date, weekday, slot, from, to ->
                val perSlot = addedMs.getOrPut(date) { LongArray(TokyoTime.SLOTS_PER_DAY) }
                perSlot[slot] += to - from
                weekdayByDate[date] = weekday
            }
        }
        for ((date, perSlot) in addedMs) {
            val weekday = weekdayByDate.getValue(date)
            val day = observations.getOrPut(date) { DayObservation(weekday, unobserved()) }
            for (slot in perSlot.indices) {
                if (perSlot[slot] == 0L) continue
                val seconds = (perSlot[slot] / SECOND_MS).toInt()
                if (seconds > 0) day.seconds[slot] = maxOf(day.seconds[slot], 0) + seconds
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

        const val SECOND_MS = 1_000L
        const val MINUTE_MS = 60_000L
        const val MAX_USAGE_WINDOW_MS = 2 * 60 * MINUTE_MS
        const val MAX_STATE_HISTORY_MS = 24 * 60 * MINUTE_MS
        const val SUGGEST_INTERVAL_MS = 90 * MINUTE_MS
        const val APP_TRIGGER_WINDOW_MS = 15 * MINUTE_MS
        const val APP_TRIGGER_MINUTES_MS = 5 * MINUTE_MS
        const val OBSERVATION_RETENTION_DAYS = 35

        const val QUIET_HOURS_START = 2 * 60
        const val QUIET_HOURS_END = 7 * 60
        const val END_MARGIN_MINUTES = 5
    }
}
