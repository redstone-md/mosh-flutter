package app.mosh.mosh

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine

/** The installation keeps one Dart/native owner when Android replaces its UI. */
class MoshApplication : Application() {
    internal val runtime by lazy { MoshAndroidRuntime(this) }
}

internal class MoshAndroidRuntime(application: Application) {
    val engine: FlutterEngine
    val presentation: MoshCallPresentation
    val access: MoshAccess
    private val ringtone: MoshRingtone

    init {
        MoshNative.initialize(application)
        MoshMedia.initialize(application)
        engine = FlutterEngine(application)
        val messenger = engine.dartExecutor.binaryMessenger
        presentation = MoshCallPresentation(messenger)
        access = MoshAccess(application, messenger)
        ringtone = MoshRingtone(application, messenger)
        // FlutterActivity starts Dart with the original launch arguments. Creating
        // this owner alone must not bypass foreground authentication or run main().
    }
}
