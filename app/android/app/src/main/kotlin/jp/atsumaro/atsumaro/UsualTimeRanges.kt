package jp.atsumaro.atsumaro

/**
 * Usual free time = the cached server forecast merged with the slots learned on the device.
 * The forecast answers "when does the user usually declare?", while the learned slots answer
 * "when does the user actually reach for X or YouTube?", which is when a nudge lands well.
 */
internal object UsualTimeRanges {
    private const val RECENT_DATES = 4
    private const val HIT_MINUTES = 3
    private const val HIT_DATES = 3

    fun build(store: HimaSuggestStore): List<ForecastSlot> {
        val ranges = store.forecast.toMutableList()
        val observations = store.observations()
        val recentDaysByWeekday = (0..6).map { weekday ->
            observations.entries
                .filter { it.value.weekday == weekday }
                .sortedByDescending { it.key }
                .map { it.value }
        }
        for (weekday in 0..6) {
            for (slot in 0 until TokyoTime.SLOTS_PER_DAY) {
                if (isLearned(recentDaysByWeekday[weekday], slot)) {
                    ranges += ForecastSlot(
                        weekday,
                        slot * TokyoTime.SLOT_MINUTES,
                        (slot + 1) * TokyoTime.SLOT_MINUTES,
                    )
                }
            }
        }
        return merge(ranges)
    }

    /**
     * Looks at the 4 most recent same-weekday dates on which the slot was observed: at least
     * 3 of them need 3+ target minutes, and those hits must cover at least half of the
     * observed dates. A date the worker did not observe is never counted as unused, which is
     * why observations keep a -1 marker instead of 0.
     */
    private fun isLearned(observations: List<DayObservation>, slot: Int): Boolean {
        val observedSeconds = observations.mapNotNull { day ->
            val seconds = day.seconds[slot]
            if (seconds >= 0) seconds else null
        }.take(RECENT_DATES)
        if (observedSeconds.isEmpty()) return false
        val hits = observedSeconds.count { it >= HIT_MINUTES * 60 }
        return hits >= HIT_DATES && hits * 2 >= observedSeconds.size
    }

    /** Merges adjacent or overlapping ranges per weekday, like `api/forecast.py` does. */
    private fun merge(ranges: List<ForecastSlot>): List<ForecastSlot> {
        val result = ArrayList<ForecastSlot>()
        for (weekday in 0..6) {
            val perWeekday = ArrayList<ForecastSlot>()
            ranges
                .filter { it.weekday == weekday && it.endMin > it.startMin }
                .sortedBy { it.startMin }
                .forEach { range ->
                    val last = perWeekday.lastOrNull()
                    if (last != null && range.startMin <= last.endMin) {
                        if (range.endMin > last.endMin) {
                            perWeekday[perWeekday.lastIndex] = last.copy(endMin = range.endMin)
                        }
                    } else {
                        perWeekday += range
                    }
                }
            result += perWeekday
        }
        return result
    }
}
