package app.mosh.mosh

import com.google.crypto.tink.subtle.Ed25519Verify
import java.nio.ByteBuffer
import java.security.GeneralSecurityException
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/**
 * The chats a message preview can come from, as the app left them
 * (lib/src/features/wake/wake_previews.dart), and opening one sealed by a
 * member (mosh-core/src/conversation/wake/preview.rs): AES-256-GCM, base64url
 * of nonce, ciphertext and tag over `{"text": …}`. The key that opens it
 * names the chat. Every member of a group knows its key, so a group preview
 * also carries its author's MLS signature, and the author is the member whose
 * key made it, under the name the app left for them. The same rules as
 * ios/NotificationService/Previews.swift.
 */
internal class MoshPreviewBook private constructor(private val chats: List<Chat>) {
    /** [author]: the group member who signed it; null for a DM. */
    data class Shown(val chat: String, val title: String, val text: String, val author: String? = null)

    /** `members`: the group's other members' MLS keys (base64) and names; null for a DM. */
    private class Chat(val id: String, val name: String, val keys: List<ByteArray>, val members: Map<String, String>?)

    /** The chat whose key opens [preview], with its text; null when none does,
     * or a group's preview is not signed by one of its members. */
    fun open(preview: String): Shown? {
        val sealed = try { Base64.getUrlDecoder().decode(preview) } catch (_: IllegalArgumentException) { return null }
        if (sealed.size <= NONCE + TAG) return null
        for (chat in chats) {
            for (key in chat.keys) {
                val body = opened(sealed, key) ?: continue
                val text = body.optString("text").takeIf { body.has("text") } ?: continue
                val members = chat.members ?: return Shown(chat.id, chat.name, text)
                return signed(chat.id, members, body, text)?.let { author -> Shown(chat.id, chat.name, text, author) }
            }
        }
        return null
    }

    companion object {
        private const val NONCE = 12
        private const val TAG = 16
        private const val SIGNED_AS = "mosh-group-preview-v1"

        /** The chats in [json]; null when it does not read. */
        fun parse(json: String): MoshPreviewBook? = try {
            val list = JSONArray(json)
            MoshPreviewBook((0 until list.length()).map { chat(list.getJSONObject(it)) })
        } catch (_: JSONException) { null } catch (_: IllegalArgumentException) { null }

        private fun chat(json: JSONObject): Chat {
            val keys = json.getJSONArray("keys")
            val members = json.optJSONArray("members")?.let { list ->
                (0 until list.length()).associate { list.getJSONObject(it).let { m -> m.getString("key") to m.getString("name") } }
            }
            return Chat(json.getString("chat"), json.getString("name"),
                (0 until keys.length()).map { Base64.getDecoder().decode(keys.getString(it)) }.filter { it.size == 32 },
                members)
        }

        private fun opened(sealed: ByteArray, key: ByteArray): JSONObject? = try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG * 8, sealed, 0, NONCE))
            JSONObject(String(cipher.doFinal(sealed, NONCE, sealed.size - NONCE), Charsets.UTF_8))
        } catch (_: GeneralSecurityException) { null } catch (_: JSONException) { null }

        /** The name of the member whose key signed [text] for [chat]; null when none did. */
        private fun signed(chat: String, members: Map<String, String>, body: JSONObject, text: String): String? {
            val from = body.optString("from").takeIf { it.isNotEmpty() } ?: return null
            val name = members[from] ?: return null
            return try {
                val signature = Base64.getDecoder().decode(body.optString("sig"))
                Ed25519Verify(Base64.getDecoder().decode(from)).verify(signature, signingInput(SIGNED_AS, chat, text))
                name
            } catch (_: GeneralSecurityException) { null } catch (_: IllegalArgumentException) { null }
        }

        /** Each part as a 4-byte big-endian length and its UTF-8 bytes. */
        fun signingInput(vararg parts: String): ByteArray {
            val encoded = parts.map { it.toByteArray(Charsets.UTF_8) }
            val input = ByteBuffer.allocate(encoded.sumOf { 4 + it.size })
            encoded.forEach { input.putInt(it.size).put(it) }
            return input.array()
        }
    }
}
