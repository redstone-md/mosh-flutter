// What a wake sends to Apple, independent of how it reaches Apple: a
// message wake is a fixed localized alert, maybe with the sealed preview the
// phone's notification extension opens, and a call wake is a VoIP push.
import { signJwt } from "./jwt.ts";
import type { PushResult, Wake } from "./push.ts";

export interface ApnsRequest {
  path: string;
  headers: Record<string, string>;
  body: string;
}

/** The APNs HTTP/2 request for `wake`; `topic` is the app's bundle id. */
export function apnsRequest(wake: Wake, token: string, topic: string, jwt: string): ApnsRequest {
  const common = { authorization: `bearer ${jwt}`, "apns-priority": "10" };
  if (wake.kind === "call") {
    return {
      path: `/3/device/${token}`,
      // A call that cannot ring now is not worth delivering later.
      headers: { ...common, "apns-topic": `${topic}.voip`, "apns-push-type": "voip", "apns-expiration": "0" },
      body: JSON.stringify({ call: wake.call }),
    };
  }
  const message = { ...common, "apns-topic": topic, "apns-push-type": "alert" };
  const alert = { "loc-key": "WAKE_MESSAGE" };
  if (wake.preview) {
    return {
      path: `/3/device/${token}`,
      // Each preview is a notification of its own, opened by the phone's
      // notification extension; one it cannot open stays "New message".
      // Without content-available the closed app is not started, so it
      // posts no second notice for the same texts.
      headers: message,
      body: JSON.stringify({ aps: { alert, sound: "default", "mutable-content": 1 }, preview: wake.preview }),
    };
  }
  return {
    path: `/3/device/${token}`,
    // One "New message" stands for any number of them.
    headers: { ...message, "apns-collapse-id": "mosh-message" },
    body: JSON.stringify({ aps: { alert, sound: "default", "content-available": 1 } }),
  };
}

/** Maps APNs's answer: 410, or 400 with a bad token, means the token is dead. */
export function apnsResult(status: number, reason: string | undefined): PushResult {
  if (status === 200) return "sent";
  if (status === 410 || (status === 400 && reason === "BadDeviceToken")) return "gone";
  return "failed";
}

export interface ApnsKey {
  /** PKCS#8 PEM of the .p8 key from Apple. */
  p8: string;
  keyId: string;
  teamId: string;
}

/**
 * Signs APNs provider tokens (ES256 JWT). Apple wants a token refreshed at
 * most every 20 minutes and no older than an hour, so one lives 40 minutes.
 */
export class ProviderToken {
  private cached: { jwt: string; issued: number } | undefined;
  private readonly key: ApnsKey;
  private readonly now: () => number;

  constructor(key: ApnsKey, now: () => number = Date.now) {
    this.key = key;
    this.now = now;
  }

  async current(): Promise<string> {
    const now = this.now();
    if (this.cached && now - this.cached.issued < 40 * 60_000) return this.cached.jwt;
    const claims = { iss: this.key.teamId, iat: Math.floor(now / 1000) };
    const jwt = await signJwt("ES256", { kid: this.key.keyId }, claims, this.key.p8);
    this.cached = { jwt, issued: now };
    return jwt;
  }
}
