package app.mosh.mosh

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Key I/O stays off the platform thread. */
internal class MoshAccessKeys(context: Context) {
    private val storage = MoshBackgroundDek(context)
    private val worker = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())

    fun dispatch(call: MethodCall, result: MethodChannel.Result): Boolean {
        if (call.method !in METHODS) return false
        try {
            when (call.method) {
                "readBackgroundDek" -> execute(result) { storage.read() }
                "installBackgroundDek" -> {
                    val bytes = validatedBytes(call.arguments)
                    execute(result, bytes) { storage.install(bytes); null }
                }
            }
        } catch (error: BackgroundDekException) {
            result.error(error.code, "History key unavailable", null)
        }
        return true
    }

    private fun validatedBytes(arguments: Any?): ByteArray {
        val bytes = arguments as? ByteArray
        if (bytes == null || bytes.size != 32) throw BackgroundDekException("DEK_INVALID_LENGTH")
        return bytes.copyOf()
    }

    private fun execute(result: MethodChannel.Result, bytes: ByteArray? = null, operation: () -> Any?) {
        worker.execute {
            try {
                val value = operation()
                handler.post { result.success(value) }
            } catch (error: BackgroundDekException) {
                handler.post { result.error(error.code, "History key unavailable", null) }
            } catch (_: Exception) {
                handler.post { result.error("DEK_STORAGE_UNAVAILABLE", "History key unavailable", null) }
            } finally {
                bytes?.fill(0)
            }
        }
    }

    companion object {
        private val METHODS = setOf("readBackgroundDek", "installBackgroundDek")
    }
}
