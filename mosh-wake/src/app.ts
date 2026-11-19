// The wake service's HTTP API on web-standard Request/Response, so the same
// app runs under Node now and in a worker later.
//
//   POST   /v1/devices          {apns?, voip?, environment} -> 201 {handle, secret}
//   PUT    /v1/devices/:handle  Bearer secret, same body    -> 204
//   DELETE /v1/devices/:handle  Bearer secret               -> 204
//   POST   /v1/wake             {handle, kind, call?, preview?} -> 202 | 404 | 429 | 502
//
// The phone keeps the secret and shares only the handle with its contacts.
import { Hono, type Context } from "hono";
import { RateLimit } from "./limits.ts";
import { base64url, tokenFor, type Pusher, type Wake } from "./push.ts";
import type { Device, DeviceStore, Environment } from "./store.ts";

export interface AppOptions {
  store: DeviceStore;
  pusher: Pusher;
  /** The caller's address, for per-address limits; never stored. */
  clientIp: (c: Context) => string;
  now?: () => number;
}

const MINUTE = 60_000;

export function createApp({ store, pusher, clientIp, now = Date.now }: AppOptions): Hono {
  const registrations = new RateLimit(10, 60 * MINUTE, now);
  const wakesPerAddress = new RateLimit(120, MINUTE, now);
  // Each chat with new texts wakes the phone with their preview, at most
  // every 10 s, so a phone takes bursts; the limit only stops a contact
  // flooding it. A ringing call is re-sent with its offer, so it may wake
  // every 10 s.
  const messageWakes = new RateLimit(30, MINUTE, now);
  const callWakes = new RateLimit(1, 10_000, now);
  const app = new Hono();

  app.post("/v1/devices", async (c) => {
    const tokens = parseTokens(await json(c));
    if (!tokens) return c.json({ error: "invalid tokens" }, 400);
    if (!registrations.allow(clientIp(c))) return c.json({ error: "too many registrations" }, 429);
    const handle = randomToken();
    const secret = randomToken();
    await store.put({ handle, secretHash: await sha256(secret), ...tokens });
    return c.json({ handle, secret }, 201);
  });

  app.put("/v1/devices/:handle", async (c) => {
    const device = await owned(c, store);
    if (!device) return c.json({ error: "unknown handle or wrong secret" }, 401);
    const tokens = parseTokens(await json(c));
    if (!tokens) return c.json({ error: "invalid tokens" }, 400);
    await store.put({ ...device, ...tokens });
    return c.body(null, 204);
  });

  app.delete("/v1/devices/:handle", async (c) => {
    const device = await owned(c, store);
    if (!device) return c.json({ error: "unknown handle or wrong secret" }, 401);
    await store.delete(device.handle);
    return c.body(null, 204);
  });

  app.post("/v1/wake", async (c) => {
    const request = parseWake(await json(c));
    if (!request) return c.json({ error: "invalid wake" }, 400);
    if (!wakesPerAddress.allow(clientIp(c))) return c.json({ error: "too many wakes" }, 429);
    const device = await store.get(request.handle);
    const token = device && tokenFor(device, request.wake);
    if (!device || !token) return c.json({ error: "nothing to wake" }, 404);
    const limit = request.wake.kind === "call" ? callWakes : messageWakes;
    const slot = `${request.handle}:${request.wake.kind}`;
    if (!limit.allow(slot)) return c.json({ error: "woken recently" }, 429);
    const result = await pusher.send(device, token, request.wake);
    // Only a delivered push spends the slot, so a sender may retry at once.
    if (result !== "sent") limit.refund(slot);
    if (result === "gone") {
      await store.forgetToken(device.handle, token);
      return c.json({ error: "nothing to wake" }, 404);
    }
    return result === "sent" ? c.body(null, 202) : c.json({ error: "Apple did not take the push" }, 502);
  });

  return app;
}

const HEX_TOKEN = /^[0-9a-f]{64,200}$/;
const HANDLE = /^[A-Za-z0-9_-]{43}$/;
const CALL_ID = /^[A-Za-z0-9_-]{1,64}$/;
/** Sealed texts that still fit Apple's 4 KB push (mosh-core's PREVIEW_MAX_LEN). */
const PREVIEW = /^[A-Za-z0-9_-]{1,3800}$/;

type Tokens = Pick<Device, "apns" | "voip" | "environment">;

function parseTokens(body: Record<string, unknown>): Tokens | null {
  const token = (value: unknown) => (typeof value === "string" && HEX_TOKEN.test(value) ? value : null);
  const apns = token(body.apns);
  const voip = token(body.voip);
  const environment = body.environment;
  if (environment !== "sandbox" && environment !== "production") return null;
  if ((body.apns !== undefined && !apns) || (body.voip !== undefined && !voip)) return null;
  if (!apns && !voip) return null;
  return { apns, voip, environment: environment satisfies Environment };
}

function parseWake(body: Record<string, unknown>): { handle: string; wake: Wake } | null {
  const { handle, kind, call, preview } = body;
  if (typeof handle !== "string" || !HANDLE.test(handle)) return null;
  if (kind === "message" && preview === undefined) return { handle, wake: { kind } };
  if (kind === "message" && typeof preview === "string" && PREVIEW.test(preview)) {
    return { handle, wake: { kind, preview } };
  }
  if (kind === "call" && typeof call === "string" && CALL_ID.test(call)) return { handle, wake: { kind, call } };
  return null;
}

/** The device named in the path, if the request carries its secret. */
async function owned(c: Context, store: DeviceStore): Promise<Device | undefined> {
  const secret = c.req.header("authorization")?.match(/^Bearer (\S+)$/)?.[1];
  const device = await store.get(c.req.param("handle") ?? "");
  if (!device || !secret) return undefined;
  return sameText(await sha256(secret), device.secretHash) ? device : undefined;
}

async function json(c: Context): Promise<Record<string, unknown>> {
  const body: unknown = await c.req.json().catch(() => null);
  return typeof body === "object" && body !== null ? (body as Record<string, unknown>) : {};
}

function randomToken(): string {
  return base64url(crypto.getRandomValues(new Uint8Array(32)));
}

async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

/** Compares two equal-length hex digests without an early exit. */
function sameText(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return difference === 0;
}
