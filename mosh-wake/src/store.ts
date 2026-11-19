// The one thing the service keeps: which Apple push tokens a wake handle
// reaches. Async, so a worker port can put it in D1 or KV unchanged.

/** APNs has a separate sandbox for development builds. */
export type Environment = "sandbox" | "production";

export interface Device {
  /** Shared with contacts; anyone holding it may ask for a push. */
  handle: string;
  /** SHA-256 of the secret only the phone holds, for updates and removal. */
  secretHash: string;
  /** Token for visible notifications, hex. */
  apns: string | null;
  /** PushKit token for calls, hex. */
  voip: string | null;
  environment: Environment;
}

export interface DeviceStore {
  get(handle: string): Promise<Device | undefined>;
  put(device: Device): Promise<void>;
  delete(handle: string): Promise<void>;
  /** Drops `token` from the device if it still has it (Apple said it is dead). */
  forgetToken(handle: string, token: string): Promise<void>;
}
