package jp.atsumaro.atsumaro

import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

/**
 * Every slot calculation lives in Asia/Tokyo with weekday 0 = Monday, the convention the
 * server forecast already uses (`api/forecast.py`). Keeping it in one object is what stops
 * the device time zone and Calendar's Sunday-first week from leaking into slot math: a user
 * travelling abroad still has the same "usual time" slots.
 */
internal object TokyoTime {
    const val SLOT_MINUTES = 30
    const val SLOTS_PER_DAY = 48

    private const val MINUTE_MS = 60_000L

    private val zone: TimeZone = TimeZone.getTimeZone("Asia/Tokyo")

    fun calendar(epochMs: Long): Calendar = Calendar.getInstance(zone).apply { timeInMillis = epochMs }

    fun startOfDay(epochMs: Long): Long = calendar(epochMs).apply {
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }.timeInMillis

    /** 0 = Monday .. 6 = Sunday; Calendar counts Sunday as 1, so shift Monday to zero. */
    fun weekday(epochMs: Long): Int =
        (calendar(epochMs).get(Calendar.DAY_OF_WEEK) - Calendar.MONDAY + 7) % 7

    fun minutesOfDay(epochMs: Long): Int {
        val cal = calendar(epochMs)
        return cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
    }

    /** yyyy-MM-dd in Tokyo. ISO dates compare chronologically, which the retention rules rely on. */
    fun dateKey(epochMs: Long): String = formatDate(calendar(epochMs))

    fun dateKeyDaysAgo(days: Int, now: Long): String =
        formatDate(calendar(now).apply { add(Calendar.DAY_OF_MONTH, -days) })

    /** Start of the 30-minute slot that contains [epochMs]. */
    fun slotStart(epochMs: Long): Long {
        val slot = minutesOfDay(epochMs) / SLOT_MINUTES
        return startOfDay(epochMs) + slot * SLOT_MINUTES * MINUTE_MS
    }

    private fun formatDate(cal: Calendar): String = String.format(
        Locale.ROOT,
        "%04d-%02d-%02d",
        cal.get(Calendar.YEAR),
        cal.get(Calendar.MONTH) + 1,
        cal.get(Calendar.DAY_OF_MONTH),
    )
}
