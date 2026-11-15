# iOS: calls and messages while Mosh is closed

Status: approved by the owner on 2026-11-15; tracked as MOSH-109 with one
issue per layer (MOSH-110 to MOSH-113). Builds on MOSH-77 (iOS calls on the
call engine).

## Problem

Android receives in the background by keeping a Moss attachment alive in a
foreground service ([ADR 0048](../ADR/0048-android-background-waiting.md)).
iOS suspends a backgrounded app within seconds and gives a closed one no
process at all, so nothing listens on Moss. Moss has no store-and-forward
either: a DM leaves the sender's outbox only while both installations are
online together ([Architecture](../Architecture.md), outbox).

The only way iOS starts a closed app is an Apple push (APNs). Background App
Refresh runs when iOS decides, often hours apart, and never for a call. A push
must be sent by a server that holds an APNs key. Mosh has no such server.

## What established messengers do

- Calls: a PushKit VoIP push launches the app, which must report the call to
  CallKit before the handler returns (iOS 13+ terminates apps that do not).
  The system incoming-call screen rings, including on the lock screen. Signal,
  WhatsApp and Telegram all work this way.
- Messages: a visible alert push. Signal and Element send content-free pushes
  and let a Notification Service Extension fetch and decrypt the message. An
  extension has about 30 seconds and a 24 MB memory limit.

## Proposal

### 1. Wake service (new, `mosh-wake/`)

A small TypeScript service ([mosh-wake](../../mosh-wake/README.md)) on
web-standard Request/Response, so it runs under Node now and can move to a
worker later. It stores nothing but `wake handle -> APNs tokens`.

- `POST /v1/devices` with the phone's tokens returns a random 256-bit wake
  handle and a secret. The phone shares the handle and keeps the secret,
  which updates or removes the device. Rotating means registering anew and
  removing the old handle.
- `POST /v1/wake {handle, kind: call | message}` sends one push. Rate limits
  per handle: one message push a minute (coalesced), one call push every
  10 s; per address 120 wakes a minute.

The push payload carries no names or text. A message push is an alert with a
localized key ("New message") plus `mutable-content`. A call push carries the
call id only.

The service learns the handle, the time and the sender's IP address. It does
not learn who sent the push, who receives it or anything in the chat. Apple
learns the same plus the device. This is the one central component in Mosh's
message path, so the plan keeps it replaceable: the URL is a build constant,
and the service is in this repository under the same licence.

### 2. Publishing the handle

The iPhone registers on launch and sends its wake handle to its contacts and
linked devices inside the existing MLS conversations, as a signed device
packet next to the identity claim. Only admitted counterparts and the user's
own linked devices see it. Removing a contact or a device rotates the handle.
This is a wire and schema change (a new packet tag and a stored handle per
counterpart installation), so its exact shape comes for approval with layer 2.

### 3. Who sends a wake (all platforms)

- Messages: when the outbox holds queued DM work for a counterpart installation
  that has a wake handle and no authenticated connection, the sender asks the
  service once per batch and keeps retrying the DM as it does today. Because
  the sender is online at that moment, the woken phone usually finds it.
- Calls: when a call offer goes to an installation with a handle that is not
  connected, send a `call` wake together with the offer. The caller's existing
  30-second ring and offer retransmission cover the phone's start-up.
- Groups and channels: same rule for members' installations, coalesced.

Desktop and Android builds therefore make an HTTPS request to the service when
a contact uses an iPhone. No request is made otherwise.

### 4. iOS client

- Capabilities: Push Notifications, background modes `voip` and
  `remote-notification`. `scripts/ios-profile.mjs` enables the App ID's push
  capability through the App Store Connect API, and the export applies the
  entitlements.
- CallKit: a `CXProvider` reports incoming calls (from the VoIP push, name
  "Mosh" until the authenticated offer arrives and the name is updated),
  answer/decline/end map to the existing native call controls, and outgoing
  calls go through `CXStartCallAction` so iOS treats them as phone calls.
  CallKit activates the audio session; libwebrtc's `RTCAudioSession` switches
  to manual audio and starts when CallKit says so. `includesCallsInRecents` is
  off, so Mosh calls stay out of the Phone app's history and iCloud.
- Messages, first version: the alert shows "New message" without name or text.
  If iOS gives the app background time, the app connects, receives the DM,
  removes the generic alert and posts a local notification with the real
  content, following the existing name and text privacy settings.
- Messages, later (not in this plan): a Notification Service Extension that
  decrypts on its own. That needs Moss, MLS state and the database shared
  between two processes within 24 MB, which is a separate project.

## Delivery in layers

1. Wake service with tests against APNs sandbox, deployed by the owner.
2. iOS: register, publish the handle, CallKit for incoming and outgoing calls,
   VoIP push. Senders on every platform wake for calls. A call reaches a
   closed iPhone.
3. Message wakes from every platform, generic alert, background fetch and the
   real-content local notification.
4. Group and channel wakes.

Each layer ships on its own; layer 2 alone already fixes calls.

## Owner actions

- Create an APNs key (Certificates, Identifiers & Profiles, Keys, Apple Push
  Notifications service) and give the `.p8` and key id to the service host.
- Host the service. For tests and the rollout it runs on the development
  machine; it moves to a worker or another machine afterwards. A worker must
  reach APNs over HTTP/2; if it cannot, only `src/apns-http2.ts` stays on a
  Node host.

## Risks

- Start-up time: a woken iPhone must start Flutter, Moss and the DM runtime
  and find the caller within the ring. If Moss discovery takes longer than
  about 20 s, the call is missed. Measured on the device in layer 2.
- A message sent just before the sender goes offline still waits until both
  are online, as today.
- A force-quit app gets VoIP pushes but not background time for messages, so
  those show only the generic alert until the user opens Mosh.
- Apple rejects apps that use VoIP pushes for anything but calls, so message
  wakes never use the VoIP channel.
- Anyone who has the handle (a contact) can send pushes up to the rate limit.
- F-Droid may label the Android build "NonFreeNet" for contacting the service.

## Checks

- Service: unit tests for registration, rotation and rate limits; an
  integration test against the APNs sandbox in CI with a test key.
- Rust: sender tests on `MemoryNet` that a disconnected installation with a
  handle gets exactly one wake per batch and a connected one gets none.
- iOS: CI build with the entitlements; on the phone, a call and a message to
  a locked iPhone with Mosh closed, then force-quit, from desktop and Android.
