package app.mosh.mosh

import android.content.res.Configuration
import android.content.Context
import android.app.PictureInPictureUiState
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var callPermissions: MoshCallPermissions? = null
    private var callPresentation: MoshCallPresentation? = null

    override fun provideFlutterEngine(context: Context): FlutterEngine =
        (application as MoshApplication).runtime.engine

    override fun shouldDestroyEngineWithHost(): Boolean = false

    // The retained engine already has its framework state; don't restore an old
    // Activity's snapshot over the live provider/call tree.
    override fun shouldRestoreAndSaveState(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Flutter installs its view during super.onCreate, before a PiP shield
        // can safely be added above it.
        callPresentation?.attach(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        callPermissions = MoshCallPermissions(this, flutterEngine.dartExecutor.binaryMessenger)
        callPresentation = (application as MoshApplication).runtime.presentation
    }

    override fun onUserLeaveHint() {
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
        super.onResume()
        callPresentation?.resumed()
    }

    override fun onPause() {
        callPresentation?.paused()
        super.onPause()
    }

    override fun onStop() {
        callPresentation?.stopped()
        super.onStop()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        callPermissions?.complete(requestCode, grantResults)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        callPermissions?.dispose()
        callPermissions = null
        callPresentation?.detach(this)
        callPresentation = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
