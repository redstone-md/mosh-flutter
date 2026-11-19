# ADR 0055: Android is woken through FCM in our own builds

Date: 2026-11-19
Status: Accepted (MOSH-118); implemented, phone acceptance pending.
Revises the FCM restriction of [ADR 0048](0048-android-background-waiting.md)
for the Google Play and GitHub builds; F-Droid's build keeps it.

## Context

Background waiting ([ADR 0048](0048-android-background-waiting.md)) keeps Moss
connected from a foreground service. The user can stop it, and battery savers
and vendor firmware such as Xiaomi's and Huawei's kill it. Then a message or a
call reaches the phone only once Mosh is opened again. iPhones already have a
way around this: contacts wake them through the wake service
([mosh-wake](../../mosh-wake/README.md),
[the iOS plan](../Proposals/ios-background-delivery.plan.md)). Telegram and its
forks wake Android the same way, through Firebase Cloud Messaging in the builds
that ship with Google services.

## Decision

Our own Android builds register with the wake service like an iPhone does, and
the service wakes them through FCM. Senders do not change: they already wake
any announced address through the build's service.

- **Two builds.** `-PmoshFcm=true` adds `android/app/fcm.gradle.kts` and
  `android/app/src/fcm`: Firebase Messaging, Tink and the messaging service.
  The release workflow sets it when the `MOSH_FIREBASE_CONFIG` secret holds the
  project's `google-services.json`. F-Droid's recipe removes those files, and a
  plain `flutter build` does not set the property, so neither build has Google
  code. Both builds share `src/main`; each takes its own `MoshPush` from
  `src/fcm` or `src/foss`. A Gradle property was chosen over product flavours
  so that `flutter run` and F-Droid's recipe need no `--flavor`.
- **No google-services plugin.** Firebase starts from four string resources,
  which `fcm.gradle.kts` reads from `google-services.json`.
- **Address.** A phone registers `{fcm: <installation id>}`, its Firebase
  installation id, which FCM's HTTP v1 API takes as `message.fid`. The
  registration token API is deprecated since firebase-messaging 25.1.
- **Pushes.** High-priority data messages without `notification`:
  `{kind: "call", call}` that expire at once, `{kind: "message", preview}`, or
  one collapsing `{kind: "message"}`. The rate limits and the sealed preview
  are the iPhone's.
- **Messages** (Kotlin only; neither Rust nor Moss runs). `MoshFcmService`
  opens the preview with the keys Dart left in a Keystore-sealed file
  (`MoshWakeVault`), with the rules of the iOS notification extension: the key
  that opens it names the chat, and a group preview shows only when one of the
  group's members signed it. Group signatures are Ed25519, which Android has
  only from API 33, so the FCM build verifies them with Tink. The notification
  goes through the background delivery publisher, so the lock screen settings
  for names and text apply. A preview it cannot open shows "New message".
  Opening Mosh clears these notifications: the messages arrive over Moss then.
- **Calls.** A call push starts the background waiting service for 45 s, which
  the caller's re-sent wake extends, without changing the saved waiting choice.
  Moss connects, the caller's re-sent offer arrives, and the call rings
  full-screen through the existing call notification. Nothing rings before the
  offer arrives, so there is nothing to answer before the caller is known.
- **Connected phones.** While Mosh is connected (on screen, or waiting in the
  background), a push shows nothing, because Moss delivers the message itself.
  Groups have no keepalive. A phone repeats its group announcements every 10 s
  only while Mosh is on screen. Off screen, a group's members take it for
  absent after 25 s and wake it, so a connected phone may receive pushes it
  does not show.

## Consequences

- The FCM build depends on Google Play services. Without them, or after the
  user force-stops Mosh, only background waiting delivers.
- Google learns when a phone is woken and whether for a call, as Apple does for
  iPhones. Previews stay sealed end to end.
- FCM may deprioritize an app whose high-priority messages show no
  notification. A connected phone in a group drops such pushes, so a phone
  that waits in the background and is in active groups risks it. The
  alternative was a frame per group every 10 s all day.
- The waiting service's "starting" notification is what a call push shows
  until the offer rings, and it stays if the offer never comes, until the 45 s
  run out.
- Messages a push already showed may be notified again if Mosh delivers them
  in the background before the user opens it, for example during a call wake.

## Owner actions

- Create the Firebase project for `app.mosh.mosh` and store its
  `google-services.json` as the `MOSH_FIREBASE_CONFIG` secret.
- Give the wake service host a service account key with permission to send
  FCM messages (`FCM_KEY_FILE`).
