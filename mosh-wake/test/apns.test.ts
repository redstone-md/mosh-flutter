import assert from "node:assert/strict";
import { generateKeyPairSync, verify } from "node:crypto";
import { createServer, type IncomingHttpHeaders } from "node:http2";
import type { AddressInfo } from "node:net";
import { after, test } from "node:test";
import { Http2Apns } from "../src/apns-http2.ts";
import { ProviderToken } from "../src/push.ts";
import type { Device } from "../src/store.ts";

const keys = generateKeyPairSync("ec", { namedCurve: "P-256" });
const p8 = keys.privateKey.export({ type: "pkcs8", format: "pem" }).toString();

/** A local plaintext HTTP/2 stand-in for APNs that answers with `reply`. */
async function fakeApns(reply: { status: number; body?: string }) {
  const seen: { headers: IncomingHttpHeaders; body: string }[] = [];
  const server = createServer((request, response) => {
    let body = "";
    request.on("data", (chunk) => { body += chunk; });
    request.on("end", () => {
      seen.push({ headers: request.headers, body });
      response.writeHead(reply.status).end(reply.body ?? "");
    });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  const apns = new Http2Apns(new ProviderToken({ p8, keyId: "KEY123", teamId: "TEAM456" }), "app.mosh.mosh", {
    production: origin,
    sandbox: origin,
  });
  after(() => { apns.close(); server.close(); });
  return { apns, seen };
}

const device: Device = { handle: "h", secretHash: "s", apns: "aa", voip: "bb", environment: "production" };

test("a call goes as a VoIP push that expires at once, signed by the team's key", async () => {
  const { apns, seen } = await fakeApns({ status: 200 });
  assert.equal(await apns.send(device, "bb", { kind: "call", call: "c-1" }), "sent");

  const [request] = seen;
  assert.ok(request);
  assert.equal(request.headers[":path"], "/3/device/bb");
  assert.equal(request.headers["apns-topic"], "app.mosh.mosh.voip");
  assert.equal(request.headers["apns-push-type"], "voip");
  assert.equal(request.headers["apns-expiration"], "0");
  assert.deepEqual(JSON.parse(request.body), { call: "c-1" });

  const jwt = String(request.headers.authorization).replace(/^bearer /, "");
  const [header, claims, signature] = jwt.split(".");
  assert.deepEqual(JSON.parse(Buffer.from(header!, "base64url").toString()), { alg: "ES256", kid: "KEY123" });
  assert.equal(JSON.parse(Buffer.from(claims!, "base64url").toString()).iss, "TEAM456");
  const signed = verify("sha256", Buffer.from(`${header}.${claims}`), {
    key: keys.publicKey, dsaEncoding: "ieee-p1363",
  }, Buffer.from(signature!, "base64url"));
  assert.ok(signed, "Apple can verify the provider token");
});

test("a message goes as one collapsing alert without names or text", async () => {
  const { apns, seen } = await fakeApns({ status: 200 });
  await apns.send(device, "aa", { kind: "message" });

  const [request] = seen;
  assert.equal(request?.headers["apns-topic"], "app.mosh.mosh");
  assert.equal(request?.headers["apns-push-type"], "alert");
  assert.equal(request?.headers["apns-collapse-id"], "mosh-message");
  assert.deepEqual(JSON.parse(request?.body ?? ""), {
    aps: { alert: { "loc-key": "WAKE_MESSAGE" }, sound: "default", "content-available": 1 },
  });
});

// The phone's notification extension opens the preview; one alert per
// preview, and the closed app is not started for it.
test("a message with a preview goes as its own alert for the notification extension", async () => {
  const { apns, seen } = await fakeApns({ status: 200 });
  await apns.send(device, "aa", { kind: "message", preview: "c2VhbGVk" });

  const [request] = seen;
  assert.equal(request?.headers["apns-push-type"], "alert");
  assert.equal(request?.headers["apns-collapse-id"], undefined);
  assert.deepEqual(JSON.parse(request?.body ?? ""), {
    aps: { alert: { "loc-key": "WAKE_MESSAGE" }, sound: "default", "mutable-content": 1 },
    preview: "c2VhbGVk",
  });
});

test("Apple's answers map to sent, gone and failed", async () => {
  const cases = [
    [{ status: 410, body: '{"reason":"Unregistered"}' }, "gone"],
    [{ status: 400, body: '{"reason":"BadDeviceToken"}' }, "gone"],
    [{ status: 400, body: '{"reason":"BadTopic"}' }, "failed"],
    [{ status: 429, body: '{"reason":"TooManyRequests"}' }, "failed"],
  ] as const;
  for (const [reply, expected] of cases) {
    const { apns } = await fakeApns(reply);
    assert.equal(await apns.send(device, "aa", { kind: "message" }), expected, reply.body);
  }
});
