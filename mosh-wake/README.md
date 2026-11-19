# mosh-wake

iOS gives a closed app no process to listen on Moss with, so a call or a
message to an iPhone could only arrive while Mosh is open. This service
wakes the phone: a contact's Mosh asks it for a push, and it sends Apple a
push that names nobody. A message push may carry the new texts sealed for
the phone, which only the phone's notification extension opens; the
message itself arrives over Moss when Mosh opens. The plan and its
trade-offs are in
[docs/Proposals/ios-background-delivery.plan.md](../docs/Proposals/ios-background-delivery.plan.md).

The service keeps one table: a random wake handle and the phone's APNs
tokens. It does not see who asks for a wake or what the wake is for beyond
"message" or "call". Request limits live in memory and nothing about callers
is written down.

## API

| Request | Body | Answer |
| --- | --- | --- |
| `POST /v1/devices` | `{apns?, voip?, environment}` | `201 {handle, secret}` |
| `PUT /v1/devices/:handle` | same, with `Authorization: Bearer <secret>` | `204` |
| `DELETE /v1/devices/:handle` | `Authorization: Bearer <secret>` | `204` |
| `POST /v1/wake` | `{handle, kind: "message", preview?}` or `{handle, kind: "call", call}` | `202`, `404`, `429`, `502` |

Tokens are hex, `environment` is `sandbox` (Xcode builds) or `production`
(TestFlight and the App Store). The phone keeps the secret and shares the
handle with its contacts inside the encrypted chats. A wake answers `404`
when the handle is unknown or has no token for that kind, so the sender can
stop using it, and `429` when the phone was woken 30 times for messages in
the last minute, or for a call in the last 10 seconds. `preview` is base64url
of at most 3800 characters, so the push stays within Apple's 4 KB.

## Running

```sh
npm ci
APNS_KEY_FILE=/path/AuthKey_XXXX.p8 APNS_KEY_ID=XXXX APNS_TEAM_ID=YYYY npm start
```

The other settings are listed at the top of [src/main.ts](src/main.ts). The
key comes from developer.apple.com: Certificates, Identifiers & Profiles,
Keys, then a key with Apple Push Notifications service. It and the team id
stay on the host. The service listens on 127.0.0.1:8790; put HTTPS in front
of it and set `WAKE_TRUST_PROXY=1` so the limits see callers' addresses.

`src/app.ts`, `src/push.ts` and `src/store.ts` use only web-standard APIs, so
they move to a worker as they are; `src/apns-http2.ts` and
`src/sqlite-store.ts` are the Node side.

## Checks

`npm run check` type-checks, `npm test` runs the API against a stand-in
Apple and the APNs sender against a local HTTP/2 server.
