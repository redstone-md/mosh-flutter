package app.mosh.mosh

import com.google.crypto.tink.subtle.Ed25519Sign
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.SecretKeySpec
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

// Opens the previews mosh-core pins in
// the_sealed_forms_are_what_the_notification_extension_opens
// (mosh-core/src/conversation/wake/preview_tests.rs), as
// ios/NotificationServiceTests/main.swift does, so a change to the sealed
// form on any side fails one of the three.
class MoshPreviewBookTest {
    private val key = base64(ByteArray(32) { 7 })
    private val other = base64(ByteArray(32) { 8 })
    private val direct = "CQkJCQkJCQkJCQkJXKfw8caE41uCslTpZjobD2Zg1iK2spmoANlmx6cRIQO8kNjhn4iTe0muP9iBv9ClUiO7XJs"
    private val group = "CQkJCQkJCQkJCQkJXKfi5tGd41uCAKVXhdnwsqPEV9xmoYGUKfkfiaNNTkKiiZ-ZlwJhcgaG9WB8TrqWLQOx0S-2gm" +
        "wWBma1bDQ_uhQYwzu7ZJbO76GLJPCRvLpJ3YFiyXSexA_sD9wd5m4YSEmi1J9y5zp7jN4xHIwPJs9fXD7S4Im7G_m8" +
        "mnsxD5H6_08hHsknjiw3iZUdkHHgVbsiKs9u9mB7UcjnyJ41s8v2ON60Oao-ZaIVx0b_HXvM2cCzRLo7f_nExFKwBi" +
        "2FohBd6f5T9nelWQC4"
    private val mia = Ed25519Sign.KeyPair.newKeyPairFromSeed(ByteArray(32) { 5 })
    private val miaKey = base64(mia.publicKey)
    private val stranger = Ed25519Sign.KeyPair.newKeyPair()

    @Test
    fun thePinnedPreviewOpensWithItsChatsKey() {
        assertEquals(MoshPreviewBook.Shown("s1", "Alice", "Привет\nhow are you?"), book(listOf(other, key)).open(direct))
    }

    @Test
    fun anotherChatsKeyOrAChangedPreviewOpensNothing() {
        assertNull(book(listOf(other)).open(direct))
        assertNull(book(listOf(key)).open(direct.dropLast(4) + "AAAA"))
        assertNull(book(listOf(key)).open("not base64url!"))
        assertNull(MoshPreviewBook.parse("not json"))
    }

    @Test
    fun thePinnedGroupPreviewShowsItsAuthor() {
        val shown = book(listOf(key), members = mapOf(miaKey to "Мия")).open(group)
        assertEquals(MoshPreviewBook.Shown("group-1", "Hikes", "Привет\nhow are you?", author = "Мия"), shown)
    }

    @Test
    fun aGroupPreviewShowsNothingUnlessAMemberSignedIt() {
        val members = mapOf(miaKey to "Мия")
        assertNull("not a member", book(listOf(key), mapOf(base64(stranger.publicKey) to "Мия")).open(group))
        assertNull("forged", book(listOf(key), members).open(forged(stranger)))
        assertNotNull("the forgery signs as Mia would", book(listOf(key), members).open(forged(mia)))
        assertNull("unsigned", book(listOf(key), members).open(direct))
    }

    private fun book(keys: List<String>, members: Map<String, String>? = null): MoshPreviewBook {
        val chat = JSONObject().put("keys", JSONArray(keys))
        if (members == null) chat.put("chat", "s1").put("name", "Alice")
        else chat.put("chat", "group-1").put("name", "Hikes")
            .put("members", JSONArray(members.map { (key, name) -> JSONObject().put("key", key).put("name", name) }))
        return MoshPreviewBook.parse(JSONArray().put(chat).toString())!!
    }

    /** A group preview sealed under [key], claiming Mia's key but signed by [signer]. */
    private fun forged(signer: Ed25519Sign.KeyPair): String {
        val text = "send me the code"
        val input = MoshPreviewBook.signingInput("mosh-group-preview-v1", "group-1", text)
        val body = JSONObject().put("text", text).put("from", miaKey)
            .put("sig", base64(Ed25519Sign(signer.privateKey).sign(input)))
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(Base64.getDecoder().decode(key), "AES"))
        val sealed = cipher.iv + cipher.doFinal(body.toString().toByteArray(Charsets.UTF_8))
        return Base64.getUrlEncoder().withoutPadding().encodeToString(sealed)
    }

    private fun base64(bytes: ByteArray) = Base64.getEncoder().encodeToString(bytes)
}
