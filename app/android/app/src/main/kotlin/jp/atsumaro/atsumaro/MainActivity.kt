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
        // Read before super.onCreate: the engine starts inside super.onCreate, and Dart may ask
        // for the pending action as soon as its isolate runs, before this method returns.
        consumeSuggestAction(intent, deliverToDart = false)
        super.onCreate(savedInstanceState)
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
        // Clearing the extra keeps a re-created activity from replaying the tap.
        launchedIntent.removeExtra(HimaSuggest.ACTION_EXTRA)
        val store = HimaSuggestStore(this)
        // Keep a pending copy first: Dart may not have installed its channel handler yet, and a
        // cold start retrieves the action through takePendingAction.
        store.pendingAction = action
        val channel = suggestChannel
        if (deliverToDart && channel != null) {
            channel.invokeMethod(
                HimaSuggest.EVENT_ACTION,
                HimaSuggest.ACTION_DECLARE,
                object : MethodChannel.Result {
                    // Drop the copy only once Dart confirms onAction arrived, so one tap never
                    // both dispatches an event and replays later through takePendingAction.
                    override fun success(result: Any?) {
                        store.pendingAction = null
                    }

                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit

                    override fun notImplemented() = Unit
                },
            )
        }
    }
}
