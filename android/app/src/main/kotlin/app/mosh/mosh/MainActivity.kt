package app.mosh.mosh

import android.content.res.Configuration
import android.content.Context
import android.content.Intent
import android.app.PictureInPictureUiState
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var callPermissions: MoshCallPermissions? = null
    private var callPresentation: MoshCallPresentation? = null
    private var access: MoshAccess? = null
    private var waiting: MoshWaiting? = null

    override fun provideFlutterEngine(context: Context): FlutterEngine {
        MoshWaitingSystemStop(this).reopened()
        return (application as MoshApplication).runtime.engine
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false

    // The retained engine already has its framework state; don't restore an old
    // Activity's snapshot over the live provider/call tree.
    override fun shouldRestoreAndSaveState(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        val entry = intent
        intent = MoshTransferIntents.forFlutter(MoshCallIntents.forFlutter(entry))
        super.onCreate(savedInstanceState)
        // Flutter installs its view during super.onCreate, before a PiP shield
        // can safely be added above it.
        callPresentation?.attach(this)
        access?.attach(this)
        waiting?.attach(this)
        waiting?.callIntent(entry)
        waiting?.transfers?.accept(entry)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(MoshTransferIntents.forFlutter(MoshCallIntents.forFlutter(intent)))
        waiting?.callIntent(intent)
        waiting?.transfers?.accept(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        callPermissions = MoshCallPermissions(this, flutterEngine.dartExecutor.binaryMessenger)
        callPresentation = (application as MoshApplication).runtime.presentation
        access = (application as MoshApplication).runtime.access
        waiting = (application as MoshApplication).runtime.waiting
    }

    override fun onUserLeaveHint() {
        access?.leaving()
        callPresentation?.leaving()
        super.onUserLeaveHint()
    }

    override fun onPictureInPictureModeChanged(pip: Boolean, configuration: Configuration) {
        super.onPictureInPictureModeChanged(pip, configuration)
        callPresentation?.changed(pip)
    }

    @android.annotation.TargetApi(31)
    override fun onPictureInPictureUiStateChanged(state: PictureInPictureUiState) {
        super.onPictureInPictureUiStateChanged(state)
        if (Build.VERSION.SDK_INT >= 35 && state.isTransitioningToPip) {
            callPresentation?.preparing()
        }
    }

    override fun onResume() {
        access?.resumed()
        super.onResume()
        callPresentation?.resumed()
        waiting?.resumed()
    }

    override fun onPause() {
        access?.paused()
        waiting?.paused()
        callPresentation?.paused()
        super.onPause()
    }

    override fun onStop() {
        access?.stopped()
        callPresentation?.stopped()
        super.onStop()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        callPermissions?.complete(requestCode, grantResults)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        access?.result(requestCode, resultCode)
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        callPermissions?.dispose()
        callPermissions = null
        callPresentation?.detach(this)
        callPresentation = null
        access?.detach(this)
        access = null
        waiting?.detach(this)
        waiting = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
