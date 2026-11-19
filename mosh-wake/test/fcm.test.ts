import assert from "node:assert/strict";
import { generateKeyPairSync, verify } from "node:crypto";
import { test } from "node:test";
import { AccessToken, FcmPusher, serviceAccount } from "../src/fcm.ts";
import type { FcmDevice } from "../src/store.ts";

const keys = generateKeyPairSync("rsa", { modulusLength: 2048 });
const account = serviceAccount(JSON.stringify({
  type: "service_account",
  project_id: "mosh-test",
  client_email: "wake@mosh-test.iam.gserviceaccount.com",
  private_key: keys.privateKey.export({ type: "pkcs8", format: "pem" }).toString(),
  token_uri: "https://oauth2.example/token",
}));
const device: FcmDevice = { handle: "h", secretHash: "s", platform: "fcm", fcm: "tok" };

/** Google's OAuth and FCM endpoints as the service sees them: FCM answers with `reply`. */
function fakeGoogle(reply: { status: number; body?: string }) {
  const sent: { url: string; headers: Headers; body: string }[] = [];
  let grants = 0;
  const fetcher: typeof fetch = async (input, init) => {
    const url = String(input);
    const body = String(init?.body ?? "");
    if (url === account.tokenUri) {
      grants++;
      return Response.json({ access_token: `access-${grants}`, expires_in: 3600, token_type: "Bearer" });
    }
    sent.push({ url, headers: new Headers(init?.headers), body });
    return new Response(reply.body ?? "{}", { status: reply.status });
  };
  let now = 1_000_000;
  const fcm = new FcmPusher(account.projectId, new AccessToken(account, fetcher, () => now), fetcher);
  return { fcm, sent, grants: () => grants, advance: (ms: number) => { now += ms; }, fetcher };
}

test("a call goes as a high-priority data message that expires at once", async () => {
  const { fcm, sent } = fakeGoogle({ status: 200 });
  assert.equal(await fcm.send(device, "tok", { kind: "call", call: "c-1" }), "sent");

  const [request] = sent;
  assert.equal(request?.url, "https://fcm.googleapis.com/v1/projects/mosh-test/messages:send");
  assert.equal(request?.headers.get("authorization"), "Bearer access-1");
  assert.deepEqual(JSON.parse(request?.body ?? ""), {
    message: { fid: "tok", data: { kind: "call", call: "c-1" }, android: { priority: "HIGH", ttl: "0s" } },
  });
});

// No `notification`: Mosh's messaging service decides what shows.
test("messages go as data only: a preview of its own, or one collapsing wake", async () => {
  const { fcm, sent } = fakeGoogle({ status: 200 });
  await fcm.send(device, "tok", { kind: "message", preview: "c2VhbGVk" });
  await fcm.send(device, "tok", { kind: "message" });

  assert.deepEqual(sent.map(({ body }) => JSON.parse(body).message), [
    { fid: "tok", data: { kind: "message", preview: "c2VhbGVk" }, android: { priority: "HIGH" } },
    { fid: "tok", data: { kind: "message" }, android: { priority: "HIGH", collapse_key: "mosh-message" } },
  ]);
});

test("the access token comes from the service account's signed assertion and is reused", async () => {
  const assertions: string[] = [];
  const base = fakeGoogle({ status: 200 });
  let now = 1_000_000;
  const fetcher: typeof fetch = async (input, init) => {
    if (String(input) === account.tokenUri) assertions.push(new URLSearchParams(String(init?.body)).get("assertion") ?? "");
    return base.fetcher(input, init);
  };
  const fcm = new FcmPusher(account.projectId, new AccessToken(account, fetcher, () => now), fetcher);

  await fcm.send(device, "tok", { kind: "message" });
  await fcm.send(device, "tok", { kind: "message" });
  now += 56 * 60_000;
  await fcm.send(device, "tok", { kind: "message" });

  assert.equal(assertions.length, 2, "one grant until five minutes before it ends");
  const [header, claims, signature] = assertions[0]!.split(".");
  assert.deepEqual(JSON.parse(Buffer.from(header!, "base64url").toString()), { alg: "RS256", typ: "JWT" });
  const claimed = JSON.parse(Buffer.from(claims!, "base64url").toString());
  assert.equal(claimed.iss, "wake@mosh-test.iam.gserviceaccount.com");
  assert.equal(claimed.scope, "https://www.googleapis.com/auth/firebase.messaging");
  assert.equal(claimed.aud, account.tokenUri);
  assert.equal(claimed.exp - claimed.iat, 3600);
  assert.ok(verify("sha256", Buffer.from(`${header}.${claims}`), keys.publicKey, Buffer.from(signature!, "base64url")));
});

test("a refused access token is replaced on the next send", async () => {
  const { fcm, grants } = fakeGoogle({ status: 401 });
  assert.equal(await fcm.send(device, "tok", { kind: "message" }), "failed");
  await fcm.send(device, "tok", { kind: "message" });
  assert.equal(grants(), 2);
});

test("FCM's answers map to sent, gone and failed", async () => {
  const error = (status: number, code: string) => ({
    status,
    body: JSON.stringify({ error: { code: status, details: [{ "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError", errorCode: code }] } }),
  });
  const cases = [
    [error(404, "UNREGISTERED"), "gone"],
    [error(403, "SENDER_ID_MISMATCH"), "gone"],
    [error(400, "INVALID_ARGUMENT"), "failed"],
    [error(429, "QUOTA_EXCEEDED"), "failed"],
    [{ status: 503, body: "not json" }, "failed"],
  ] as const;
  for (const [reply, expected] of cases) {
    const { fcm } = fakeGoogle(reply);
    assert.equal(await fcm.send(device, "tok", { kind: "message" }), expected, reply.body);
  }
});

test("a service account key without its fields is refused at start", () => {
  assert.throws(() => serviceAccount(JSON.stringify({ project_id: "p" })), /client_email/);
});
