import assert from "node:assert/strict";
import { createPublicKey, generateKeyPairSync, verify } from "node:crypto";
import test from "node:test";
import { apiToken, appStoreProfile } from "./ios-profile.mjs";

// What a profile's content carries once the App ID has push.
const WITH_PUSH = Buffer.from("<key>aps-environment</key><string>production</string>").toString("base64");

// A fake App Store Connect API: the bundle id with its capabilities, two
// distribution certificates and whatever profiles the test starts with.
function fakeApi(profiles, capabilities = [{ attributes: { capabilityType: "PUSH_NOTIFICATIONS" } }]) {
  const calls = [];
  const api = async (method, route, body) => {
    calls.push({ method, route, body });
    if (route.endsWith("/bundleIdCapabilities")) return { data: capabilities };
    if (method === "DELETE" || route === "/bundleIdCapabilities") return {};
    if (route.startsWith("/bundleIds")) {
      return { data: [{ id: "B1", attributes: { identifier: "app.mosh.mosh" } }] };
    }
    if (route.startsWith("/certificates")) {
      return { data: [
        { id: "OLD", attributes: { serialNumber: "0A0B" } },
        { id: "NEW", attributes: { serialNumber: "5C6D7E" } },
      ] };
    }
    if (method === "GET") return { data: profiles };
    return { data: { attributes: { uuid: "created-uuid", profileContent: "Y3JlYXRlZA==" } } };
  };
  return { api, calls };
}

test("the active profile for the certificate is reused", async () => {
  const { api, calls } = fakeApi([
    { attributes: { profileType: "IOS_APP_STORE", uuid: "kept-uuid", profileContent: WITH_PUSH } },
  ]);

  const profile = await appStoreProfile({ api, bundleId: "app.mosh.mosh", serial: "5c6d7e" });

  assert.deepEqual(profile, { uuid: "kept-uuid", content: WITH_PUSH });
  assert.equal(calls.some((call) => call.method !== "GET"), false);
});

test("push is turned on for an App ID that lacks it", async () => {
  const { api, calls } = fakeApi([], []);

  await appStoreProfile({ api, bundleId: "app.mosh.mosh", serial: "5C6D7E" });

  const enabled = calls.find((call) => call.route === "/bundleIdCapabilities").body.data;
  assert.equal(enabled.attributes.capabilityType, "PUSH_NOTIFICATIONS");
  assert.equal(enabled.relationships.bundleId.data.id, "B1");
});

// A profile made before the App ID had push would sign an app whose push
// tokens never arrive.
test("a profile without the push entitlement is replaced", async () => {
  const { api, calls } = fakeApi([
    { id: "P1", attributes: { profileType: "IOS_APP_STORE", uuid: "old-uuid", profileContent: "a2VwdA==" } },
  ]);

  const profile = await appStoreProfile({ api, bundleId: "app.mosh.mosh", serial: "5C6D7E" });

  assert.equal(profile.uuid, "created-uuid");
  assert.ok(calls.some((call) => call.method === "DELETE" && call.route === "/profiles/P1"));
});

test("a missing profile is created for the bundle id and the matching certificate", async () => {
  const { api, calls } = fakeApi([]);

  const profile = await appStoreProfile({ api, bundleId: "app.mosh.mosh", serial: "005C6D7E" });

  assert.equal(profile.uuid, "created-uuid");
  const created = calls.find((call) => call.method === "POST").body.data;
  assert.equal(created.attributes.name, "Mosh App Store 005C6D7E");
  assert.equal(created.relationships.bundleId.data.id, "B1");
  assert.deepEqual(created.relationships.certificates.data, [{ type: "certificates", id: "NEW" }]);
});

test("the API token is an ES256 JWT that the key's public half verifies", () => {
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const p8 = privateKey.export({ type: "pkcs8", format: "pem" });

  const [header, payload, signature] = apiToken({ issuerId: "ISS", keyId: "KID", p8 }, 1000).split(".");

  assert.deepEqual(JSON.parse(Buffer.from(header, "base64url")), { alg: "ES256", kid: "KID", typ: "JWT" });
  assert.deepEqual(JSON.parse(Buffer.from(payload, "base64url")),
    { iss: "ISS", iat: 1000, exp: 1600, aud: "appstoreconnect-v1" });
  assert.ok(verify("sha256", Buffer.from(`${header}.${payload}`),
    { key: createPublicKey(p8), dsaEncoding: "ieee-p1363" }, Buffer.from(signature, "base64url")));
});
