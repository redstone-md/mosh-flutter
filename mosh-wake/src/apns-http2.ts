// Sends wakes to APNs over HTTP/2 from Node, keeping one connection per
// environment open as Apple asks providers to.
import { connect, type ClientHttp2Session } from "node:http2";
import { apnsRequest, apnsResult, type ProviderToken } from "./apns.ts";
import type { Pusher, PushResult, Wake } from "./push.ts";
import type { AppleDevice, Environment } from "./store.ts";

export const APPLE_ORIGINS: Record<Environment, string> = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
};

export class Http2Apns implements Pusher<AppleDevice> {
  private readonly sessions = new Map<Environment, ClientHttp2Session>();
  private readonly token: ProviderToken;
  private readonly topic: string;
  private readonly origins: Record<Environment, string>;

  constructor(token: ProviderToken, topic: string, origins = APPLE_ORIGINS) {
    this.token = token;
    this.topic = topic;
    this.origins = origins;
  }

  async send(device: AppleDevice, token: string, wake: Wake): Promise<PushResult> {
    const request = apnsRequest(wake, token, this.topic, await this.token.current());
    try {
      const { status, body } = await this.post(device.environment, request.path, request.headers, request.body);
      return apnsResult(status, reasonOf(body));
    } catch (error) {
      console.error(`APNs ${device.environment} request failed: ${String(error)}`);
      return "failed";
    }
  }

  close(): void {
    for (const session of this.sessions.values()) session.close();
    this.sessions.clear();
  }

  private session(environment: Environment): ClientHttp2Session {
    const open = this.sessions.get(environment);
    if (open && !open.closed && !open.destroyed) return open;
    const session = connect(this.origins[environment]);
    const forget = () => {
      if (this.sessions.get(environment) === session) this.sessions.delete(environment);
    };
    session.on("close", forget);
    session.on("error", forget);
    session.on("goaway", forget);
    this.sessions.set(environment, session);
    return session;
  }

  private post(environment: Environment, path: string, headers: Record<string, string>, body: string) {
    return new Promise<{ status: number; body: string }>((resolve, reject) => {
      const stream = this.session(environment).request({ ":method": "POST", ":path": path, ...headers });
      let status = 0;
      let text = "";
      stream.setEncoding("utf8");
      stream.setTimeout(10_000, () => stream.close());
      stream.on("response", (head) => { status = Number(head[":status"]); });
      stream.on("data", (chunk: string) => { text += chunk; });
      stream.on("end", () => resolve({ status, body: text }));
      stream.on("error", reject);
      stream.end(body);
    });
  }
}

function reasonOf(body: string): string | undefined {
  try {
    const reason: unknown = JSON.parse(body).reason;
    return typeof reason === "string" ? reason : undefined;
  } catch {
    return undefined;
  }
}
