# mosh-wake

iOS gives a closed app no process to listen on Moss with, so a call or a
message to an iPhone could only arrive while Mosh is open. Android has
background waiting, but the user, battery savers and vendor firmware stop
it. This service wakes the phone: a contact's Mosh asks it for a push, and
it sends Apple, or Firebase Cloud Messaging for an Android phone, a push
that names nobody. A message push may carry the new texts sealed for the
phone, which only the phone opens; the message itself arrives over Moss
when Mosh connects. The plan and its trade-offs are in
[docs/Proposals/ios-background-delivery.plan.md](../docs/Proposals/ios-background-delivery.plan.md)
and, for Android, [ADR 0055](../docs/ADR/0055-android-wakes-through-fcm.md).

The service keeps one table: a random wake handle and the phone's push
tokens. It does not see who asks for a wake or what the wake is for beyond
"message" or "call". Request limits live in memory and nothing about callers
is written down.

## API

| Request | Body | Answer |
| --- | --- | --- |
| `POST /v1/devices` | `{apns?, voip?, environment}` or `{fcm}` | `201 {handle, secret}` |
| `PUT /v1/devices/:handle` | same, with `Authorization: Bearer <secret>` | `204` |
| `DELETE /v1/devices/:handle` | `Authorization: Bearer <secret>` | `204` |
| `POST /v1/wake` | `{handle, kind: "message", preview?}` or `{handle, kind: "call", call}` | `202`, `404`, `429`, `502` |

An iPhone registers its APNs tokens in hex, with `environment` `sandbox`
(Xcode builds) or `production` (TestFlight and the App Store). An Android
phone registers `fcm`, its Firebase installation id, used for both kinds; a host without a
Firebase key refuses it. Either may move to the other under the same
handle. The phone keeps the secret and shares the
handle with its contacts inside the encrypted chats. A wake answers `404`
when the handle is unknown or has no token for that kind, so the sender can
stop using it, and `429` when the phone took 30 message wakes in the current
minute window, or a call wake in the current 10-second one. The windows are
fixed, so a burst across two of them can reach twice the limit; the limits
stop floods, they do not pace. `preview` is base64url
of at most 3800 characters, so the push stays within the 4 KB Apple and
FCM take.

Apple gets an alert, or a VoIP push for a call. Firebase gets a
high-priority data message to the installation id (`message.fid`) with no `notification`: `{kind: "call", call}`
that expires at once, or `{kind: "message", preview?}`. Mosh's own
messaging service shows it, as FCM expects every high-priority message to
end in a notification.

## Running

```sh
npm ci
APNS_KEY_FILE=/path/AuthKey_XXXX.p8 APNS_KEY_ID=XXXX APNS_TEAM_ID=YYYY \
FCM_KEY_FILE=/path/firebase-service-account.json npm start
```

A host needs the Apple key, the Firebase key or both, and refuses
registrations for a push service it has no key for.

The other settings are listed at the top of [src/main.ts](src/main.ts). The
key comes from developer.apple.com: Certificates, Identifiers & Profiles,
Keys, then a key with Apple Push Notifications service. The Firebase key
comes from the Firebase console: Project settings, Service accounts,
Generate new private key; the account needs permission to send FCM
messages. All of them stay on the host. The service listens on 127.0.0.1:8790; put HTTPS in front
of it and set `WAKE_TRUST_PROXY=1` so the limits see callers' addresses.

`src/app.ts`, `src/push.ts`, `src/apns.ts`, `src/fcm.ts`, `src/jwt.ts` and
`src/store.ts` use only web-standard APIs, so they move to a worker as they
are; `src/apns-http2.ts` and `src/sqlite-store.ts` are the Node side. A
file from before FCM is rebuilt once at start, keeping its devices.

## Checks

`npm run check` type-checks, `npm test` runs the API against stand-in push
services, the APNs sender against a local HTTP/2 server and the FCM sender
against a stand-in Google.
