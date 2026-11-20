package app.mosh.mosh

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.io.File
import java.io.FileNotFoundException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Small texts the wake push needs while Mosh is closed (the registration's
 * secret, the chats' preview keys), each sealed in its own file under one
 * Keystore key. Readable after the first unlock, without the app lock, as
 * the background history key is (ADR 0049).
 */
internal class MoshWakeVault(private val context: Context) {
    fun read(name: String): String? = synchronized(LOCK) {
        val sealed = try { file(name).readFully() } catch (_: FileNotFoundException) { return null }
        require(sealed.size > HEADER && sealed.copyOfRange(0, 4).contentEquals(MAGIC)) { "Sealed $name unreadable" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, sealed.copyOfRange(4, HEADER)))
        cipher.updateAAD(aad(name))
        String(cipher.doFinal(sealed, HEADER, sealed.size - HEADER), Charsets.UTF_8)
    }

    fun write(name: String, value: String): Unit = synchronized(LOCK) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        cipher.updateAAD(aad(name))
        val sealed = MAGIC + cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val target = file(name)
        val output = target.startWrite()
        try {
            output.write(sealed)
            output.fd.sync()
            target.finishWrite(output)
        } catch (error: Exception) {
            target.failWrite(output)
            throw error
        }
    }

    private fun file(name: String) = AtomicFile(File(context.noBackupFilesDir, "wake-$name-v1"))

    private fun aad(name: String) = "${context.packageName}/wake/$name/v1".toByteArray(Charsets.UTF_8)

    private fun key(): SecretKey {
        val keys = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keys.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setKeySize(256)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setUserAuthenticationRequired(false)
            .build())
        return generator.generateKey()
    }

    companion object {
        private val LOCK = Any()
        private val MAGIC = byteArrayOf(77, 87, 75, 49)
        private const val HEADER = 4 + 12
        private const val ALIAS = "app.mosh.wake.v1"
    }
}
