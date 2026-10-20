package app.mosh.mosh

import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var callPermissions: MoshCallPermissions? = null
    private var ringtone: MoshRingtone? = null
    private var callPresentation: MoshCallPresentation? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MoshNative.initialize(applicationContext)
        MoshMedia.initialize(applicationContext)
        callPermissions = MoshCallPermissions(this, flutterEngine.dartExecutor.binaryMessenger)
        ringtone = MoshRingtone(this, flutterEngine.dartExecutor.binaryMessenger)
        callPresentation = MoshCallPresentation(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onUserLeaveHint() {
        callPresentation?.leaving()
        super.onUserLeaveHint()
    }

    override fun onPictureInPictureModeChanged(pip: Boolean, configuration: Configuration) {
        super.onPictureInPictureModeChanged(pip, configuration)
        callPresentation?.changed(pip)
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
        ringtone?.dispose()
        ringtone = null
        callPresentation?.dispose()
        callPresentation = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
