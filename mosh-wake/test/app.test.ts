import assert from "node:assert/strict";
import { test } from "node:test";
import { createApp } from "../src/app.ts";
import type { Pusher, PushResult, Wake } from "../src/push.ts";
import { SqliteStore } from "../src/sqlite-store.ts";

const APNS = "a".repeat(64);
const VOIP = "b".repeat(64);

/** Apple as the service sees it: records pushes, answers with `result`. */
class FakeApple implements Pusher {
  sent: { token: string; wake: Wake }[] = [];
  result: PushResult = "sent";
  async send(_device: unknown, token: string, wake: Wake): Promise<PushResult> {
    this.sent.push({ token, wake });
    return this.result;
  }
}

function service() {
  let now = 1_000_000;
  const apple = new FakeApple();
  const app = createApp({ store: new SqliteStore(":memory:"), pusher: apple, clientIp: () => "198.51.100.7", now: () => now });
  const call = (method: string, path: string, body?: object, secret?: string) =>
    app.request(path, {
      method,
      headers: { "content-type": "application/json", ...(secret ? { authorization: `Bearer ${secret}` } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
  const register = async (tokens: object = { apns: APNS, voip: VOIP }) => {
    const response = await call("POST", "/v1/devices", { environment: "production", ...tokens });
    assert.equal(response.status, 201);
    return (await response.json()) as { handle: string; secret: string };
  };
  const wake = (handle: string, kind: string, extra: object = {}) =>
    call("POST", "/v1/wake", { handle, kind, ...extra });
  return { apple, call, register, wake, advance: (ms: number) => { now += ms; } };
}

test("a message wake reaches the alert token once a minute", async () => {
  const { apple, register, wake, advance } = service();
  const { handle } = await register();

  assert.equal((await wake(handle, "message")).status, 202);
  assert.equal((await wake(handle, "message")).status, 429);
  advance(60_000);
  assert.equal((await wake(handle, "message")).status, 202);

  assert.deepEqual(apple.sent, [
    { token: APNS, wake: { kind: "message" } },
    { token: APNS, wake: { kind: "message" } },
  ]);
});

test("a call wake carries its call id to the VoIP token on its own limit", async () => {
  const { apple, register, wake, advance } = service();
  const { handle } = await register();
  await wake(handle, "message");

  assert.equal((await wake(handle, "call", { call: "c-1" })).status, 202);
  assert.equal((await wake(handle, "call", { call: "c-1" })).status, 429);
  advance(10_000);
  assert.equal((await wake(handle, "call", { call: "c-1" })).status, 202);

  assert.deepEqual(apple.sent.slice(1), [
    { token: VOIP, wake: { kind: "call", call: "c-1" } },
    { token: VOIP, wake: { kind: "call", call: "c-1" } },
  ]);
});

test("nothing is pushed for an unknown handle or a kind the phone has no token for", async () => {
  const { apple, register, wake } = service();
  const { handle } = await register({ apns: APNS });

  assert.equal((await wake("x".repeat(43), "message")).status, 404);
  assert.equal((await wake(handle, "call", { call: "c-1" })).status, 404);
  assert.deepEqual(apple.sent, []);
});

test("only the secret's holder can change or remove a device", async () => {
  const { apple, call, register, wake } = service();
  const { handle, secret } = await register({ apns: APNS });
  const path = `/v1/devices/${handle}`;

  assert.equal((await call("PUT", path, { environment: "production", voip: VOIP }, "wrong")).status, 401);
  assert.equal((await call("PUT", path, { environment: "production", voip: VOIP }, secret)).status, 204);
  assert.equal((await wake(handle, "call", { call: "c-1" })).status, 202);
  assert.equal(apple.sent[0]?.token, VOIP);

  assert.equal((await call("DELETE", path, undefined, "wrong")).status, 401);
  assert.equal((await call("DELETE", path, undefined, secret)).status, 204);
  assert.equal((await wake(handle, "message")).status, 404);
});

test("a token Apple calls dead is forgotten", async () => {
  const { apple, register, wake, advance } = service();
  const { handle } = await register();
  apple.result = "gone";

  assert.equal((await wake(handle, "message")).status, 404);
  advance(60_000);
  assert.equal((await wake(handle, "message")).status, 404);
  assert.equal((await wake(handle, "call", { call: "c-1" })).status, 404);
  assert.equal(apple.sent.length, 2, "the VoIP token was dead too after its own push");
});

test("a push Apple refuses is reported as a gateway failure and may be retried at once", async () => {
  const { apple, register, wake } = service();
  const { handle } = await register();
  apple.result = "failed";
  assert.equal((await wake(handle, "message")).status, 502);

  apple.result = "sent";
  assert.equal((await wake(handle, "message")).status, 202);
});

test("malformed registrations and wakes are refused", async () => {
  const { call, register, wake } = service();
  const { handle } = await register();
  for (const body of [
    { environment: "production" },
    { environment: "staging", apns: APNS },
    { environment: "production", apns: "not-hex" },
    { environment: "production", apns: APNS, voip: 7 },
  ]) {
    assert.equal((await call("POST", "/v1/devices", body)).status, 400, JSON.stringify(body));
  }
  assert.equal((await wake(handle, "call")).status, 400, "a call needs its id");
  assert.equal((await wake(handle, "ring")).status, 400);
  assert.equal((await wake("short", "message")).status, 400);
});

test("one address cannot register more than ten devices an hour", async () => {
  const { call, register } = service();
  for (let i = 0; i < 10; i++) await register();
  const response = await call("POST", "/v1/devices", { environment: "production", apns: APNS });
  assert.equal(response.status, 429);
});
