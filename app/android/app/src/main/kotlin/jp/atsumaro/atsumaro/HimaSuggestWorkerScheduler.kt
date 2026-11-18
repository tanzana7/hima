package jp.atsumaro.atsumaro

import android.content.Context
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

internal object HimaSuggestScheduler {
    private const val PERIOD_MINUTES = 15L

    /**
     * 15 minutes is WorkManager's minimum period. WorkManager persists the request and
     * restores it after a reboot, so no boot receiver and no foreground service are needed.
     * Delays from Doze or OEM battery limits are expected: the next run still evaluates the
     * whole window since the previous one.
     */
    fun schedule(context: Context) {
        val request = PeriodicWorkRequestBuilder<HimaSuggestWorker>(PERIOD_MINUTES, TimeUnit.MINUTES).build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            HimaSuggest.WORK_NAME,
            ExistingPeriodicWorkPolicy.UPDATE,
            request,
        )
    }

    fun cancel(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(HimaSuggest.WORK_NAME)
    }
}
