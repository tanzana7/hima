package jp.atsumaro.atsumaro

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build
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

internal data class UsageSnapshot(
    val intervals: List<ForegroundInterval>,
    val foregroundPackage: String?,
    val carried: CarriedForeground,
)

internal object TargetUsageReader {
    // ACTIVITY_RESUMED / ACTIVITY_PAUSED keep the values of the older
    // MOVE_TO_FOREGROUND / MOVE_TO_BACKGROUND events, so one pair covers API 24..36.
    private const val EVENT_RESUMED = 1
    private const val EVENT_PAUSED = 2

    private data class RawEvent(val type: Int, val packageName: String?, val timeMs: Long)

    /**
     * Rebuilds foreground intervals for [startMs]..[endMs] starting from [carried], so a
     * session that began before the window still counts. Screen-off ends the open interval,
     * and a resume that happens while the screen is off is ignored.
     */
    fun read(
        context: Context,
        startMs: Long,
        endMs: Long,
        carried: CarriedForeground,
    ): UsageSnapshot {
        val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
        val events = manager?.queryEvents(startMs, endMs)
            ?: return UsageSnapshot(emptyList(), null, carried)

        val raw = ArrayList<RawEvent>()
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            raw += RawEvent(event.eventType, event.packageName, event.timeStamp)
        }
        // queryEvents is documented as time ordered, but events sharing a timestamp rely on
        // insertion order, so a stable sort keeps a screen-off before a resume at the same ms.
        raw.sortBy { it.timeMs }

        var currentPackage = carried.packageName
        var currentSince = if (carried.packageName != null) carried.sinceMs else 0L
        var screenInteractive = carried.screenInteractive
        val intervals = ArrayList<ForegroundInterval>()

        fun close(atMs: Long) {
            val packageName = currentPackage ?: return
            val from = maxOf(currentSince, startMs)
            val to = minOf(atMs, endMs)
            if (to > from) intervals += ForegroundInterval(packageName, from, to)
            currentPackage = null
        }

        for (rawEvent in raw) {
            val time = rawEvent.timeMs.coerceIn(startMs, endMs)
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

        val foregroundPackage = if (screenInteractive) currentPackage else null
        val carriedAfter = CarriedForeground(
            packageName = currentPackage,
            sinceMs = if (currentPackage != null) currentSince else 0L,
            screenInteractive = screenInteractive,
        )
        close(endMs)
        return UsageSnapshot(intervals, foregroundPackage, carriedAfter)
    }
}
