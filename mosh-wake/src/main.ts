// Runs the wake service under Node. Configuration comes from the
// environment; the APNs key and team id stay on the host, never in the repo.
//
//   APNS_KEY_FILE   path to the .p8 key from Apple (Keys, Apple Push Notifications service)
//   APNS_KEY_ID     the key's id
//   APNS_TEAM_ID    the developer team id
//   APNS_TOPIC      the app's bundle id (default app.mosh.mosh)
//   WAKE_DB         SQLite file (default ./wake.sqlite)
//   WAKE_HOST/PORT  where to listen (default 127.0.0.1:8790)
//   WAKE_TRUST_PROXY=1  take the caller's address from X-Forwarded-For
import { readFileSync } from "node:fs";
import { serve } from "@hono/node-server";
import { getConnInfo } from "@hono/node-server/conninfo";
import type { Context } from "hono";
import { Http2Apns } from "./apns-http2.ts";
import { createApp } from "./app.ts";
import { ProviderToken } from "./push.ts";
import { SqliteStore } from "./sqlite-store.ts";

function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

const token = new ProviderToken({
  p8: readFileSync(required("APNS_KEY_FILE"), "utf8"),
  keyId: required("APNS_KEY_ID"),
  teamId: required("APNS_TEAM_ID"),
});
await token.current(); // A bad key fails here, at start, not on the first wake.

const trustProxy = process.env.WAKE_TRUST_PROXY === "1";
const clientIp = (c: Context) =>
  (trustProxy && c.req.header("x-forwarded-for")?.split(",")[0]?.trim()) ||
  getConnInfo(c).remote.address ||
  "unknown";

const app = createApp({
  store: new SqliteStore(process.env.WAKE_DB ?? "wake.sqlite"),
  pusher: new Http2Apns(token, process.env.APNS_TOPIC ?? "app.mosh.mosh"),
  clientIp,
});

const port = Number(process.env.WAKE_PORT ?? 8790);
const hostname = process.env.WAKE_HOST ?? "127.0.0.1";
serve({ fetch: app.fetch, port, hostname });
