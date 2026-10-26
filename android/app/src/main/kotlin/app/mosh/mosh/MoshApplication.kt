package app.mosh.mosh

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/** The installation keeps one Dart/native owner when Android replaces its UI. */
class MoshApplication : Application() {
    private val owner = lazy { MoshAndroidRuntime(this) }
    internal val runtime get() = owner.value
    internal val existingRuntime get() = if (owner.isInitialized()) owner.value else null
}

internal class MoshAndroidRuntime(application: Application) {
    val engine: FlutterEngine
    val presentation: MoshCallPresentation
    val access: MoshAccess
    val waiting: MoshWaiting
    private val ringtone: MoshRingtone

    init {
        MoshNative.initialize(application)
        MoshMedia.initialize(application)
        engine = FlutterEngine(application)
        val messenger = engine.dartExecutor.binaryMessenger
        presentation = MoshCallPresentation(messenger)
        access = MoshAccess(application, messenger)
        ringtone = MoshRingtone(application, messenger)
        waiting = MoshWaiting(application, messenger, access, ringtone)
        // FlutterActivity starts Dart with the original launch arguments. Creating
        // this owner alone must not bypass foreground authentication or run main().
    }

    fun startInBackground() {
        if (!engine.dartExecutor.isExecutingDart) {
            engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        }
    }
}
