package app.mosh.mosh

/**
 * The push service this build is woken through: none. F-Droid's build and a
 * plain `flutter build` receive only while background waiting keeps Moss
 * connected (ADR 0048); the Google Play and GitHub builds take
 * src/fcm/kotlin/app/mosh/mosh/MoshPush.kt instead (ADR 0055).
 */
internal object MoshPush {
    const val wakeable = false

    fun token(done: (String?) -> Unit) = done(null)
}
