// The one thing the service keeps: which push tokens a wake handle reaches.
// Async, so a worker port can put it in D1 or KV unchanged.

/** APNs has a separate sandbox for development builds. */
export type Environment = "sandbox" | "production";

/** An iPhone: alert and PushKit tokens, hex. */
export interface AppleTokens {
  platform: "apple";
  /** Token for visible notifications. */
  apns: string | null;
  /** PushKit token for calls. */
  voip: string | null;
  environment: Environment;
}

/** An Android phone with Google Play services: its Firebase installation id, for both kinds. */
export interface FcmTokens {
  platform: "fcm";
  fcm: string | null;
}

export type Tokens = AppleTokens | FcmTokens;
export type Platform = Tokens["platform"];

export type Device = {
  /** Shared with contacts; anyone holding it may ask for a push. */
  handle: string;
  /** SHA-256 of the secret only the phone holds, for updates and removal. */
  secretHash: string;
} & Tokens;

export type AppleDevice = Extract<Device, { platform: "apple" }>;
export type FcmDevice = Extract<Device, { platform: "fcm" }>;

export interface DeviceStore {
  get(handle: string): Promise<Device | undefined>;
  put(device: Device): Promise<void>;
  delete(handle: string): Promise<void>;
  /** Drops `token` from the device if it still has it (the push service said it is dead). */
  forgetToken(handle: string, token: string): Promise<void>;
}
