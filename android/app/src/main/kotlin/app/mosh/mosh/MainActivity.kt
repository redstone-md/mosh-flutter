package app.mosh.mosh

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var callPermissions: MoshCallPermissions? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MoshNative.initialize(applicationContext)
        MoshMedia.initialize(applicationContext)
        callPermissions = MoshCallPermissions(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        callPermissions?.complete(requestCode, grantResults)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        callPermissions?.dispose()
        callPermissions = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
