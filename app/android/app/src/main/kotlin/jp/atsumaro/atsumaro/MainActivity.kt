package jp.atsumaro.atsumaro

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var suggestChannel: MethodChannel? = null
    private var suggestHandler: SuggestChannelHandler? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Cold start from the notification tap: nothing can be delivered to Dart yet, so the
        // action waits for `takePendingAction`.
        consumeSuggestAction(intent, deliverToDart = false)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HimaSuggest.CHANNEL)
        val handler = SuggestChannelHandler(this)
        channel.setMethodCallHandler(handler)
        suggestChannel = channel
        suggestHandler = handler
    }

    override fun onNewIntent(intent: Intent) {
        android.util.Log.i("HimaSuggestDebug", "onNewIntent")
        super.onNewIntent(intent)
        // singleTop keeps the running engine, so the action can go straight to Dart.
        consumeSuggestAction(intent, deliverToDart = true)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        suggestHandler?.onRequestPermissionsResult(requestCode, grantResults)
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    private fun consumeSuggestAction(intent: Intent?, deliverToDart: Boolean) {
        val launchedIntent = intent ?: return
        val action = launchedIntent.getStringExtra(HimaSuggest.ACTION_EXTRA) ?: return
        android.util.Log.i("HimaSuggestDebug", "action=$action deliver=$deliverToDart channel=${suggestChannel != null}")
        // Clearing the extra keeps a re-created activity from replaying the tap.
        launchedIntent.removeExtra(HimaSuggest.ACTION_EXTRA)
        val channel = suggestChannel
        if (deliverToDart && channel != null) {
            channel.invokeMethod(HimaSuggest.EVENT_ACTION, HimaSuggest.ACTION_DECLARE)
        } else {
            HimaSuggestStore(this).pendingAction = action
        }
    }
}
