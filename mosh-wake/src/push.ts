// What a wake is, independent of which push service carries it. Nothing
// here names a sender, a recipient or a chat: a message wake may carry the
// texts sealed for the phone's own keys, and a call wake carries only the
// caller's random call id.
import type { AppleDevice, Device, FcmDevice } from "./store.ts";

/** `preview`: the texts sealed for the phone, opaque here (base64url). */
export type Wake = { kind: "message"; preview?: string } | { kind: "call"; call: string };

/** `gone`: the push service says the token no longer reaches an app. */
export type PushResult = "sent" | "gone" | "failed";

export interface Pusher<D extends Device = Device> {
  send(device: D, token: string, wake: Wake): Promise<PushResult>;
}

/** The push services this host can reach; a host may have either or both. */
export interface Pushers {
  apple?: Pusher<AppleDevice>;
  fcm?: Pusher<FcmDevice>;
}

/** Sends `wake` through the device's own push service. */
export function sendWake(pushers: Pushers, device: Device, token: string, wake: Wake): Promise<PushResult> {
  switch (device.platform) {
    case "apple":
      return pushers.apple?.send(device, token, wake) ?? Promise.resolve("failed");
    case "fcm":
      return pushers.fcm?.send(device, token, wake) ?? Promise.resolve("failed");
  }
}

/** The token a wake goes to, or none when the phone gave none for it. */
export function tokenFor(device: Device, wake: Wake): string | null {
  if (device.platform === "fcm") return device.fcm;
  return wake.kind === "call" ? device.voip : device.apns;
}
