package app.mosh.mosh

import android.content.Context
import android.os.UserManager
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.io.DataInputStream
import java.io.EOFException
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.security.GeneralSecurityException
import java.security.InvalidKeyException
import java.security.KeyStore
import java.security.MessageDigest
import java.security.UnrecoverableKeyException
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Error codes may cross the channel; provider errors and secret values may not. */
class BackgroundDekException(val code: String) : RuntimeException("History key unavailable")

/** One same-DEK wrapping after first unlock, independent of interactive chat auth. */
internal class MoshBackgroundDek(private val context: Context) {
    private val file by lazy { AtomicFile(File(context.noBackupFilesDir, "background-dek-v1")) }
    private val aad = "${context.packageName}/background-dek/v1".toByteArray(Charsets.UTF_8)

    fun read(): ByteArray? = serialized { readCommitted() }

    fun install(bytes: ByteArray): Unit = serialized {
        validate(bytes)
        if (!matchesExisting(bytes)) persist(bytes, false)
    }

    /** Caller must first obtain a fresh authenticated foreground repair grant. */
    fun recover(bytes: ByteArray, authorized: () -> Boolean): Unit = serialized {
        validate(bytes)
        try {
            if (matchesExisting(bytes)) return@serialized
        } catch (error: Exception) {
            val repairable = error is InvalidKeyException || error is UnrecoverableKeyException ||
                error is BackgroundDekException && error.code in REPAIRABLE
            if (!repairable) throw error
        }
        // Check inside the installation lock, after reads and before alias/file
        // mutation, so waiting behind another owner cannot revive a stale grant.
        if (!authorized()) throw BackgroundDekException("DEK_AUTH_CANCELED")
        persist(bytes, true)
    }

    private fun <T> serialized(operation: () -> T): T = synchronized(LOCK) {
        try {
            if (context.isDeviceProtectedStorage ||
                context.getSystemService(UserManager::class.java)?.isUserUnlocked != true) {
                throw BackgroundDekException("DEK_DEVICE_LOCKED")
            }
            operation()
        } catch (error: BackgroundDekException) {
            throw error
        } catch (_: InvalidKeyException) {
            throw BackgroundDekException("DEK_KEY_INVALID")
        } catch (_: UnrecoverableKeyException) {
            throw BackgroundDekException("DEK_KEY_INVALID")
        } catch (_: IOException) {
            throw BackgroundDekException("DEK_STORAGE_UNAVAILABLE")
        } catch (_: GeneralSecurityException) {
            throw BackgroundDekException("DEK_KEY_UNAVAILABLE")
        } catch (_: RuntimeException) {
            throw BackgroundDekException("DEK_KEY_UNAVAILABLE")
        }
    }

    private fun readCommitted(): ByteArray? {
        val encoded = readEnvelope() ?: return null
        val keys = keyStore()
        if (!keys.containsAlias(ALIAS)) throw BackgroundDekException("DEK_KEY_MISSING")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, existingKey(keys), GCMParameterSpec(128, encoded.copyOfRange(4, 16)))
        cipher.updateAAD(aad)
        val bytes = try {
            cipher.doFinal(encoded, 16, 48)
        } catch (_: AEADBadTagException) {
            throw BackgroundDekException("DEK_ENVELOPE_INVALID")
        }
        validate(bytes)
        return bytes
    }

    private fun readEnvelope(): ByteArray? {
        val input = try {
            file.openRead()
        } catch (_: FileNotFoundException) {
            val base = file.baseFile
            if (base.exists() || File("${base.path}.bak").exists() || File("${base.path}.new").exists()) {
                throw BackgroundDekException("DEK_ENVELOPE_INVALID")
            }
            return null
        }
        try {
            return DataInputStream(input).use {
                val encoded = ByteArray(64)
                it.readFully(encoded, 0, 4)
                if (!encoded.copyOfRange(0, 4).contentEquals(MAGIC)) {
                    throw BackgroundDekException("DEK_ENVELOPE_VERSION")
                }
                it.readFully(encoded, 4, 60)
                if (it.read() != -1) throw BackgroundDekException("DEK_ENVELOPE_INVALID")
                encoded
            }
        } catch (_: EOFException) {
            throw BackgroundDekException("DEK_ENVELOPE_INVALID")
        }
    }

    private fun matchesExisting(bytes: ByteArray): Boolean {
        val existing = readCommitted() ?: return false
        if (!MessageDigest.isEqual(existing, bytes)) throw BackgroundDekException("DEK_CONFLICT")
        return true
    }

    private fun persist(bytes: ByteArray, repair: Boolean) {
        val cipher = encryptionCipher(repair)
        cipher.updateAAD(aad)
        val encrypted = cipher.doFinal(bytes)
        if (cipher.iv.size != 12 || encrypted.size != 48) throw BackgroundDekException("DEK_ENVELOPE_INVALID")
        val output = file.startWrite()
        try {
            output.write(MAGIC + cipher.iv + encrypted)
            // AtomicFile logs some sync failures; make failure observable first.
            output.fd.sync()
            file.finishWrite(output)
        } catch (error: Exception) {
            file.failWrite(output)
            throw error
        }
        val committed = readCommitted()
        if (committed == null || !MessageDigest.isEqual(bytes, committed)) {
            throw BackgroundDekException("DEK_READBACK_FAILED")
        }
    }

    private fun encryptionCipher(repair: Boolean): Cipher {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        try {
            cipher.init(Cipher.ENCRYPT_MODE, wrappingKey(repair))
        } catch (error: InvalidKeyException) {
            if (!repair) throw error
            keyStore().deleteEntry(ALIAS)
            cipher.init(Cipher.ENCRYPT_MODE, wrappingKey(false))
        }
        return cipher
    }

    private fun wrappingKey(repair: Boolean): SecretKey {
        val keys = keyStore()
        if (keys.containsAlias(ALIAS)) {
            try {
                return existingKey(keys)
            } catch (error: Exception) {
                if (!repair || error !is UnrecoverableKeyException &&
                    (error !is BackgroundDekException || error.code != "DEK_KEY_INVALID")) throw error
                keys.deleteEntry(ALIAS)
            }
        }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setKeySize(256)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .setUserAuthenticationRequired(false)
            .build())
        return generator.generateKey()
    }

    private fun existingKey(keys: KeyStore): SecretKey =
        keys.getKey(ALIAS, null) as? SecretKey ?: throw BackgroundDekException("DEK_KEY_INVALID")

    private fun keyStore(): KeyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    private fun validate(bytes: ByteArray) {
        if (bytes.size != 32) throw BackgroundDekException("DEK_INVALID_LENGTH")
    }

    companion object {
        private val LOCK = Any()
        private val MAGIC = byteArrayOf(77, 66, 75, 49)
        private const val ALIAS = "app.mosh.mobile.background-dek.v1"
        private val REPAIRABLE = setOf("DEK_KEY_MISSING", "DEK_KEY_INVALID", "DEK_ENVELOPE_INVALID")
    }
}
