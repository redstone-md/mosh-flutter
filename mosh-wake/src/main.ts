// Runs the wake service under Node. Configuration comes from the
// environment; the keys stay on the host, never in the repo. A host sends
// to Apple, to Firebase or to both, whichever keys it has.
//
//   APNS_KEY_FILE   path to the .p8 key from Apple (Keys, Apple Push Notifications service)
//   APNS_KEY_ID     the key's id
//   APNS_TEAM_ID    the developer team id
//   APNS_TOPIC      the app's bundle id (default app.mosh.mosh)
//   FCM_KEY_FILE    path to the Firebase service account's JSON key
//   WAKE_DB         SQLite file (default ./wake.sqlite)
//   WAKE_HOST/PORT  where to listen (default 127.0.0.1:8790)
//   WAKE_TRUST_PROXY=1  take the caller's address from X-Forwarded-For
import { readFileSync } from "node:fs";
import { serve } from "@hono/node-server";
import { getConnInfo } from "@hono/node-server/conninfo";
import type { Context } from "hono";
import { ProviderToken } from "./apns.ts";
import { Http2Apns } from "./apns-http2.ts";
import { createApp } from "./app.ts";
import { AccessToken, FcmPusher, serviceAccount } from "./fcm.ts";
import type { Pushers } from "./push.ts";
import { SqliteStore } from "./sqlite-store.ts";

function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

const pushers: Pushers = {};

if (process.env.APNS_KEY_FILE) {
  const token = new ProviderToken({
    p8: readFileSync(required("APNS_KEY_FILE"), "utf8"),
    keyId: required("APNS_KEY_ID"),
    teamId: required("APNS_TEAM_ID"),
  });
  await token.current(); // A bad key fails here, at start, not on the first wake.
  pushers.apple = new Http2Apns(token, process.env.APNS_TOPIC ?? "app.mosh.mosh");
}

if (process.env.FCM_KEY_FILE) {
  const account = serviceAccount(readFileSync(process.env.FCM_KEY_FILE, "utf8"));
  const token = new AccessToken(account);
  await token.current(); // As with Apple's key: a bad one fails at start.
  pushers.fcm = new FcmPusher(account.projectId, token);
}

if (!pushers.apple && !pushers.fcm) throw new Error("set APNS_KEY_FILE, FCM_KEY_FILE or both");

const trustProxy = process.env.WAKE_TRUST_PROXY === "1";
const clientIp = (c: Context) =>
  (trustProxy && c.req.header("x-forwarded-for")?.split(",")[0]?.trim()) ||
  getConnInfo(c).remote.address ||
  "unknown";

const app = createApp({
  store: new SqliteStore(process.env.WAKE_DB ?? "wake.sqlite"),
  pushers,
  clientIp,
});

const port = Number(process.env.WAKE_PORT ?? 8790);
const hostname = process.env.WAKE_HOST ?? "127.0.0.1";
serve({ fetch: app.fetch, port, hostname });
