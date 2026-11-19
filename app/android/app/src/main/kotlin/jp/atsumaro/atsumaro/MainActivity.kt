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
        val token = launchedIntent.getStringExtra(HimaSuggest.TOKEN_EXTRA)
        // Clearing the extras keeps a re-created activity from replaying the tap.
        launchedIntent.removeExtra(HimaSuggest.ACTION_EXTRA)
        launchedIntent.removeExtra(HimaSuggest.TOKEN_EXTRA)
        val store = HimaSuggestStore(this)
        // Only the posted notification knows the token (see HimaSuggestStore.notificationToken
        // and HimaSuggestStore.demoNotificationToken); anything else that launches this exported
        // activity with the extra is ignored. Each action is checked against its own token, so a
        // demo notification can neither carry the real token nor consume the real suggestion's
        // tap: both may be in the shade at once.
        val accepted = when (action) {
            HimaSuggest.ACTION_DECLARE, HimaSuggest.ACTION_DECLARE_NOW ->
                token != null && token == store.notificationToken
            HimaSuggest.ACTION_DEMO_DECLARE, HimaSuggest.ACTION_DEMO_DECLARE_NOW ->
                token != null && token == store.demoNotificationToken
            else -> false
        }
        if (!accepted) return
        // Only the token that matched is cleared; the other notification may still be posted.
        //
        // The body tap is cleared at once: its notification is auto-cancelled by the launch, so
        // nothing can send it again. 「ひまにする」 is different. It keeps its token, because the
        // real notification stays in the shade until Dart reports the declaration; if that
        // declaration fails, the user has to be able to press the button — or the body — again
        // from the same notification. The token is dropped together with the notification instead
        // (HimaSuggestNotifier.cancel), so it still never outlives the suggestion it belongs to.
        when (action) {
            HimaSuggest.ACTION_DECLARE -> store.notificationToken = null
            HimaSuggest.ACTION_DEMO_DECLARE, HimaSuggest.ACTION_DEMO_DECLARE_NOW ->
                store.demoNotificationToken = null
            else -> Unit
        }
        // The demo suggestion has no native declaration to mirror, so its 「ひまにする」 drops the
        // notification here; the real one is cancelled when Dart reports the live declaration
        // with setDeclaredUntil, which leaves it in the shade — with a usable token — when the
        // declaration failed.
        if (action == HimaSuggest.ACTION_DEMO_DECLARE_NOW) {
            HimaSuggestNotifier(this).cancelDemo(store)
        }
        // The action is always stored, and stays stored until Dart reads it with
        // takePendingAction. `onAction` is only a nudge: Dart answers it before it reads, and
        // a read that was already in flight re-reads afterwards, so clearing the copy when the
        // nudge is answered would lose the tap. Reading consumes it, so it is never taken twice.
        // A demo tap stores "demo_declare" ("demo_declare_now" for its button) the same way; Dart
        // ignores those actions outside demo mode, so a stray demo notification cannot declare
        // for the user.
        store.pendingAction = action
        val channel = suggestChannel
        if (deliverToDart && channel != null) {
            channel.invokeMethod(HimaSuggest.EVENT_ACTION, action)
        }
    }
}
