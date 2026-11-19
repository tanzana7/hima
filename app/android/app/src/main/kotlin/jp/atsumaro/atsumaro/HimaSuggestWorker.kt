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
            // No events were read, so the open interval cannot be verified. Drop it; the next
            // run rebuilds the screen state from its own events.
            store.carriedForeground = CarriedForeground(packageName = null, sinceMs = 0L)
            store.lastRunAt = now
            return
        }

        val previousRunAt = store.lastRunAt
        // The app suggestion counts the whole lookback, so it needs use that ended before the
        // previous run as well. The extra margin tolerates short interruptions and the worker's
        // roughly 15-minute cadence, and it is also what stops use that ended long ago from
        // suggesting anything.
        val requiredMs = store.appTriggerMinutes * MINUTE_MS
        val lookbackStart = now - requiredMs - APP_TRIGGER_MARGIN_MS
        // Learned slots keep their own window: only the time since the previous run belongs to
        // this run, whatever the trigger reads, or a period would be counted twice.
        val observedStart = maxOf(previousRunAt, now - MAX_USAGE_WINDOW_MS).coerceAtMost(now)
        // The read has to reach both starts. A delayed run marks everything from its observation
        // start as observed, so the intervals have to go back that far even when the trigger's
        // lookback is shorter or lies further back.
        val readStart = minOf(lookbackStart, observedStart)
        // Events are read back to the read start (bounded, because event history is finite) and
        // further to where the previous run left off, so the state there can be reconstructed.
        val queryStart = minOf(previousRunAt, readStart)
            .coerceAtLeast(now - MAX_STATE_HISTORY_MS)
            .coerceAtMost(now)
        // The carried state is the state at the previous run, so it describes the query start
        // only when that run is at or after the query start and its open session began before
        // it. That is exactly what it is carried for: a session that started before the read
        // start and may still be running. Otherwise the foreground at the query start is
        // unknown, and starting from nothing is the safe side: the stretch before the first
        // resume is left uncounted rather than credited to an app that may not have been in
        // front.
        val carried = store.carriedForeground
        val seed = if (previousRunAt >= queryStart && carried.sinceMs <= queryStart) {
            carried
        } else {
            carried.withoutForeground()
        }
        val snapshot = TargetUsageReader.read(context, queryStart, readStart, now, seed)
        store.carriedForeground = snapshot.carried
        recordObservations(store, observedStart, now, snapshot.intervals, targets.toSet())
        store.lastRunAt = now

        if (store.declaredUntil?.let { it > now } == true) return
        if (now - store.lastSuggestAt < SUGGEST_INTERVAL_MS) return
        val minutesOfDay = TokyoTime.minutesOfDay(now)
        if (minutesOfDay in QUIET_HOURS_START until QUIET_HOURS_END) return

        val notifier = HimaSuggestNotifier(context)
        val appLabel = appTriggerLabel(context, snapshot, targets, requiredMs, lookbackStart)
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

    /**
     * Label of the target that triggered the app suggestion, or null when it did not fire.
     *
     * Being in a target app right now is not enough: someone who opened YouTube seconds ago
     * must not be told "YouTube 見てる？". The suggestion fires only once the targets were in the
     * foreground for [requiredMs] in total between [lookbackStart] and now. Time across several
     * targets adds up, so a quick hop between X and YouTube still counts.
     *
     * The snapshot reaches further back than [lookbackStart] for the learned slots, so only the
     * part inside the lookback counts here.
     */
    private fun appTriggerLabel(
        context: Context,
        snapshot: UsageSnapshot,
        targets: List<String>,
        requiredMs: Long,
        lookbackStart: Long,
    ): String? {
        val targetPackages = targets.toSet()
        var usedMs = 0L
        var mostRecent: ForegroundInterval? = null
        for (interval in snapshot.intervals) {
            if (interval.packageName !in targetPackages) continue
            if (interval.endMs <= lookbackStart) continue
            usedMs += interval.endMs - maxOf(interval.startMs, lookbackStart)
            if (mostRecent == null || interval.endMs > mostRecent.endMs) mostRecent = interval
        }
        if (usedMs < requiredMs) return null

        // The body names the last target the user used, which is the open session when there is
        // one: its interval ends at now.
        val packageName = mostRecent?.packageName ?: return null
        return HimaSuggest.label(context, packageName)
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

    /**
     * Adds the target time of [observationStart]..[now] to the learned slots.
     *
     * The snapshot may reach back further than that, for the trigger, so every interval is cut
     * to [observationStart] first: a period an earlier run already recorded must not be
     * recorded again.
     */
    private fun recordObservations(
        store: HimaSuggestStore,
        observationStart: Long,
        now: Long,
        intervals: List<ForegroundInterval>,
        targets: Set<String>,
    ) {
        val observations = store.observations()
        forEachSlot(observationStart, now) { date, weekday, slot, _, _ ->
            val day = observations.getOrPut(date) { DayObservation(weekday, unobserved()) }
            day.seconds[slot] = maxOf(day.seconds[slot], 0)
        }
        // Sum milliseconds per slot within this run, then store seconds (see DayObservation).
        val addedMs = HashMap<String, LongArray>()
        val weekdayByDate = HashMap<String, Int>()
        for (interval in intervals) {
            if (interval.packageName !in targets) continue
            val from = maxOf(interval.startMs, observationStart)
            val to = minOf(interval.endMs, now)
            if (to <= from) continue
            forEachSlot(from, to) { date, weekday, slot, slotFrom, slotTo ->
                val perSlot = addedMs.getOrPut(date) { LongArray(TokyoTime.SLOTS_PER_DAY) }
                perSlot[slot] += slotTo - slotFrom
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

        /**
         * How much longer than the chosen length the app trigger looks back. The worker runs
         * about every 15 minutes, so a shorter lookback would miss use that ended just before
         * the previous run, and a session interrupted for a few minutes would fall under the
         * threshold.
         */
        const val APP_TRIGGER_MARGIN_MS = 15 * MINUTE_MS
        const val OBSERVATION_RETENTION_DAYS = 35

        const val QUIET_HOURS_START = 2 * 60
        const val QUIET_HOURS_END = 7 * 60
        const val END_MARGIN_MINUTES = 5
    }
}
