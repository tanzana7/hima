package jp.atsumaro.atsumaro

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.os.Process

internal object UsageAccess {
    /**
     * Checked through AppOps rather than `UsageStatsManager` because `queryEvents` returns an
     * empty stream without the grant, which is indistinguishable from "the user did nothing".
     */
    fun isGranted(context: Context): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager ?: return false
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
        } else {
            appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }
}

/** A stretch of time during which [packageName] was the foreground activity. */
internal data class ForegroundInterval(val packageName: String, val startMs: Long, val endMs: Long)

internal object ScreenState {
    /**
     * Live interactive state from the power manager. Usage events only cover the query window,
     * so they cannot repair a flag that went stale while no events were read, and the newest
     * event can lag behind the actual screen.
     */
    fun isInteractive(context: Context): Boolean =
        (context.getSystemService(Context.POWER_SERVICE) as? PowerManager)?.isInteractive ?: true
}

internal data class UsageSnapshot(
    val intervals: List<ForegroundInterval>,
    val carried: CarriedForeground,
)

internal object TargetUsageReader {
    // ACTIVITY_RESUMED / ACTIVITY_PAUSED keep the values of the older
    // MOVE_TO_FOREGROUND / MOVE_TO_BACKGROUND events, so one pair covers API 24..36.
    private const val EVENT_RESUMED = 1
    private const val EVENT_PAUSED = 2

    private data class RawEvent(val type: Int, val packageName: String?, val timeMs: Long)

    /**
     * Rebuilds foreground intervals for [usageStartMs]..[endMs] starting from [carried], so a
     * session that began before that start still counts. Events are read from [queryStartMs]:
     * it can reach further back than [usageStartMs], because the state at that start is only
     * known from what happened before it. Only the time from [usageStartMs] counts as usage.
     * Screen-off ends the open interval, and a resume while the screen is off is ignored.
     */
    fun read(
        context: Context,
        queryStartMs: Long,
        usageStartMs: Long,
        endMs: Long,
        carried: CarriedForeground,
    ): UsageSnapshot {
        val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
        val events = manager?.queryEvents(queryStartMs, endMs)
            ?: return UsageSnapshot(
                emptyList(),
                CarriedForeground(null, 0L),
            )

        val raw = ArrayList<RawEvent>()
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            raw += RawEvent(event.eventType, event.packageName, event.timeStamp)
        }
        // queryEvents is documented as time ordered, but events sharing a timestamp rely on
        // insertion order, so a stable sort keeps a screen-off before a resume at the same ms.
        raw.sortBy { it.timeMs }

        // The screen state at [queryStartMs] is rebuilt rather than carried: the flag a previous
        // run stored is the state at the *end* of that run, and the window now reaches further
        // back. Reading it as the starting state would count a resume that happened while the
        // screen was still off, before the screen-on later in the window. Transitions alternate
        // and the live state is known, so the transitions since the start give it back.
        val interactiveNow = ScreenState.isInteractive(context)
        val transitions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            raw.count { rawEvent ->
                val time = rawEvent.timeMs.coerceIn(queryStartMs, endMs)
                time > queryStartMs &&
                    (
                        rawEvent.type == UsageEvents.Event.SCREEN_INTERACTIVE ||
                            rawEvent.type == UsageEvents.Event.SCREEN_NON_INTERACTIVE
                        )
            }
        } else {
            // These events only exist from P on, and the replay below ignores them before that.
            0
        }

        var currentPackage = carried.packageName
        var currentSince = if (carried.packageName != null) carried.sinceMs else 0L
        var screenInteractive = if (transitions % 2 == 0) interactiveNow else !interactiveNow
        val intervals = ArrayList<ForegroundInterval>()

        fun close(atMs: Long) {
            val packageName = currentPackage ?: return
            val from = maxOf(currentSince, usageStartMs)
            val to = minOf(atMs, endMs)
            if (to > from) intervals += ForegroundInterval(packageName, from, to)
            currentPackage = null
        }

        for (rawEvent in raw) {
            val time = rawEvent.timeMs.coerceIn(queryStartMs, endMs)
            if (rawEvent.type == EVENT_RESUMED) {
                val packageName = rawEvent.packageName ?: continue
                if (!screenInteractive) continue
                if (packageName == currentPackage) continue
                close(time)
                currentPackage = packageName
                currentSince = time
            } else if (rawEvent.type == EVENT_PAUSED) {
                if (rawEvent.packageName != null && rawEvent.packageName == currentPackage) close(time)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                if (rawEvent.type == UsageEvents.Event.SCREEN_INTERACTIVE) {
                    screenInteractive = true
                } else if (rawEvent.type == UsageEvents.Event.SCREEN_NON_INTERACTIVE) {
                    close(time)
                    screenInteractive = false
                }
            }
        }

        val carriedAfter = CarriedForeground(
            packageName = currentPackage,
            sinceMs = if (currentPackage != null) currentSince else 0L,
        )
        close(endMs)
        return UsageSnapshot(intervals, carriedAfter)
    }
}
