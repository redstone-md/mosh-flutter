// Sends wakes to Android phones as Firebase Cloud Messaging data messages
// over FCM's HTTP v1 API, on fetch and WebCrypto only. A data message shows
// nothing by itself: Mosh's own messaging service opens the preview or
// starts the call, so Google carries what Apple carries and no more.
import { signJwt } from "./jwt.ts";
import type { Pusher, PushResult, Wake } from "./push.ts";
import type { FcmDevice } from "./store.ts";

/** The parts of a Firebase service account key the service uses. */
export interface ServiceAccount {
  projectId: string;
  clientEmail: string;
  /** PKCS#8 PEM. */
  privateKey: string;
  tokenUri: string;
}

/** Reads the JSON key Firebase hands out for a service account. */
export function serviceAccount(json: string): ServiceAccount {
  const key: unknown = JSON.parse(json);
  const field = (name: string) => {
    const value = fieldOf(key, name);
    if (typeof value !== "string" || !value) throw new Error(`service account key has no ${name}`);
    return value;
  };
  return {
    projectId: field("project_id"),
    clientEmail: field("client_email"),
    privateKey: field("private_key"),
    tokenUri: field("token_uri"),
  };
}

/** An HTTP v1 send request: data only, so Mosh decides what shows. */
export interface FcmMessage {
  message: {
    fid: string;
    data: Record<string, string>;
    android: { priority: "HIGH"; ttl?: string; collapse_key?: string };
  };
}

/**
 * The HTTP v1 message for `wake` to the Firebase installation `fid`. Every wake is high priority, so a phone
 * in Doze gets it at once; Mosh ends each one with a notification or a
 * call, as FCM expects of high-priority messages.
 */
export function fcmMessage(wake: Wake, fid: string): FcmMessage {
  if (wake.kind === "call") {
    // A call that cannot ring now is not worth delivering later.
    return { message: { fid, data: { kind: "call", call: wake.call }, android: { priority: "HIGH", ttl: "0s" } } };
  }
  if (wake.preview) {
    // Each preview is a notification of its own.
    return { message: { fid, data: { kind: "message", preview: wake.preview }, android: { priority: "HIGH" } } };
  }
  // One "New message" stands for any number of them.
  return { message: { fid, data: { kind: "message" }, android: { priority: "HIGH", collapse_key: "mosh-message" } } };
}

/** Maps FCM's answer: an unregistered installation, or one of another project, is dead. */
export function fcmResult(status: number, body: string): PushResult {
  if (status === 200) return "sent";
  const codes = errorCodes(body);
  return codes.includes("UNREGISTERED") || codes.includes("SENDER_ID_MISMATCH") ? "gone" : "failed";
}

/** The `errorCode`s of an FCM error answer; none when it is not one. */
function errorCodes(body: string): string[] {
  let answer: unknown;
  try {
    answer = JSON.parse(body);
  } catch {
    return [];
  }
  const details = fieldOf(fieldOf(answer, "error"), "details");
  if (!Array.isArray(details)) return [];
  return details.flatMap((detail: unknown) => {
    const code = fieldOf(detail, "errorCode");
    return typeof code === "string" ? [code] : [];
  });
}

/** `value[name]` when `value` is an object; JSON from outside is read through this. */
function fieldOf(value: unknown, name: string): unknown {
  return typeof value === "object" && value !== null ? Object.getOwnPropertyDescriptor(value, name)?.value : undefined;
}

const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

/**
 * OAuth access tokens for sending, from the service account's signed
 * assertion. Google's live an hour; one is used until five minutes before
 * it ends, or until FCM refuses it.
 */
export class AccessToken {
  private cached: { token: string; until: number } | undefined;
  private readonly account: ServiceAccount;
  private readonly fetcher: typeof fetch;
  private readonly now: () => number;

  constructor(account: ServiceAccount, fetcher: typeof fetch = fetch, now: () => number = Date.now) {
    this.account = account;
    this.fetcher = fetcher;
    this.now = now;
  }

  async current(): Promise<string> {
    const now = this.now();
    if (this.cached && now < this.cached.until) return this.cached.token;
    const issued = Math.floor(now / 1000);
    const claims = { iss: this.account.clientEmail, scope: SCOPE, aud: this.account.tokenUri, iat: issued, exp: issued + 3600 };
    const assertion = await signJwt("RS256", { typ: "JWT" }, claims, this.account.privateKey);
    const response = await this.fetcher(this.account.tokenUri, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
      signal: AbortSignal.timeout(10_000),
    });
    const answer: unknown = await response.json();
    const token = fieldOf(answer, "access_token");
    const lifetime = fieldOf(answer, "expires_in");
    if (!response.ok || typeof token !== "string" || typeof lifetime !== "number") {
      throw new Error(`Google refused the service account: ${response.status}`);
    }
    this.cached = { token, until: now + (lifetime - 300) * 1000 };
    return token;
  }

  /** FCM refused the token before it ended, so the next send fetches another. */
  forget(): void {
    this.cached = undefined;
  }
}

export class FcmPusher implements Pusher<FcmDevice> {
  private readonly endpoint: string;
  private readonly token: AccessToken;
  private readonly fetcher: typeof fetch;

  constructor(projectId: string, token: AccessToken, fetcher: typeof fetch = fetch) {
    this.endpoint = `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`;
    this.token = token;
    this.fetcher = fetcher;
  }

  async send(_device: FcmDevice, token: string, wake: Wake): Promise<PushResult> {
    try {
      const response = await this.fetcher(this.endpoint, {
        method: "POST",
        headers: { authorization: `Bearer ${await this.token.current()}`, "content-type": "application/json" },
        body: JSON.stringify(fcmMessage(wake, token)),
        signal: AbortSignal.timeout(10_000),
      });
      if (response.status === 401) this.token.forget();
      return fcmResult(response.status, await response.text());
    } catch (error) {
      console.error(`FCM request failed: ${String(error)}`);
      return "failed";
    }
  }
}
