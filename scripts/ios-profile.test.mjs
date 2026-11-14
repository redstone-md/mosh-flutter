import assert from "node:assert/strict";
import { createPublicKey, generateKeyPairSync, verify } from "node:crypto";
import test from "node:test";
import { apiToken, appStoreProfile } from "./ios-profile.mjs";

// A fake App Store Connect API: the bundle id, two distribution
// certificates and whatever profiles the test starts with.
function fakeApi(profiles) {
  const calls = [];
  const api = async (method, route, body) => {
    calls.push({ method, route, body });
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
    { attributes: { profileType: "IOS_APP_STORE", uuid: "kept-uuid", profileContent: "a2VwdA==" } },
  ]);

  const profile = await appStoreProfile({ api, bundleId: "app.mosh.mosh", serial: "5c6d7e" });

  assert.deepEqual(profile, { uuid: "kept-uuid", content: "a2VwdA==" });
  assert.equal(calls.some((call) => call.method === "POST"), false);
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
