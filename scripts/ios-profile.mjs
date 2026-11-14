#!/usr/bin/env node
// Finds or creates the App Store provisioning profile for the iOS app and
// the imported Apple Distribution certificate, installs it for Xcode and
// prints its UUID (scripts/ios-package.sh exports with it).
//
//   node scripts/ios-profile.mjs <AuthKey.p8> <bundle id> <certificate serial>
//
// Reads APP_STORE_CONNECT_ISSUER_ID and APP_STORE_CONNECT_KEY_ID. An App
// Manager key may read and create profiles, but Xcode's automatic signing
// would reach for cloud-managed certificates, which need an Admin key; so the
// profile comes from the App Store Connect API and the export signs manually.
// The profile is named after the certificate's serial, so a renewed
// certificate gets its own profile on the first build that uses it.
import { createPrivateKey, sign } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

const API = "https://api.appstoreconnect.apple.com/v1";
// Xcode 16 reads the first, older Xcodes the second.
const PROFILE_DIRS = [
  path.join(os.homedir(), "Library/Developer/Xcode/UserData/Provisioning Profiles"),
  path.join(os.homedir(), "Library/MobileDevice/Provisioning Profiles"),
];

/** A short-lived App Store Connect API token (ES256 JWT). */
export function apiToken({ issuerId, keyId, p8 }, now = Math.floor(Date.now() / 1000)) {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const unsigned = `${encode({ alg: "ES256", kid: keyId, typ: "JWT" })}.${encode({
    iss: issuerId, iat: now, exp: now + 600, aud: "appstoreconnect-v1",
  })}`;
  const signature = sign("sha256", Buffer.from(unsigned), {
    key: createPrivateKey(p8), dsaEncoding: "ieee-p1363",
  });
  return `${unsigned}.${signature.toString("base64url")}`;
}

/** Serial numbers as Apple and openssl print them: hex, any case, maybe zero-padded. */
const sameSerial = (a, b) => a.replace(/^0+/, "").toUpperCase() === b.replace(/^0+/, "").toUpperCase();

/**
 * The active App Store profile for `bundleId` and the certificate with
 * `serial`, created when there is none. Returns `{ uuid, content }`, the
 * content being the base64 .mobileprovision.
 */
export async function appStoreProfile({ api, bundleId, serial }) {
  const bundle = (await api("GET", `/bundleIds?filter[identifier]=${encodeURIComponent(bundleId)}`))
    .data.find((item) => item.attributes.identifier === bundleId);
  if (!bundle) throw new Error(`bundle id ${bundleId} is not registered`);
  const certificate = (await api("GET", "/certificates?filter[certificateType]=DISTRIBUTION&limit=200"))
    .data.find((item) => sameSerial(item.attributes.serialNumber, serial));
  if (!certificate) throw new Error(`no Apple Distribution certificate with serial ${serial}`);

  const name = `Mosh App Store ${serial.toUpperCase()}`;
  const existing = (await api("GET", `/profiles?filter[name]=${encodeURIComponent(name)}&filter[profileState]=ACTIVE`))
    .data.find((item) => item.attributes.profileType === "IOS_APP_STORE");
  const profile = existing ?? (await api("POST", "/profiles", {
    data: {
      type: "profiles",
      attributes: { name, profileType: "IOS_APP_STORE" },
      relationships: {
        bundleId: { data: { type: "bundleIds", id: bundle.id } },
        certificates: { data: [{ type: "certificates", id: certificate.id }] },
      },
    },
  })).data;
  return { uuid: profile.attributes.uuid, content: profile.attributes.profileContent };
}

function restClient(token, fetchImpl = fetch) {
  return async (method, route, body) => {
    const response = await fetchImpl(`${API}${route}`, {
      method,
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: body && JSON.stringify(body),
    });
    const json = await response.json();
    if (!response.ok) {
      throw new Error(`${method} ${route.split("?")[0]}: ${response.status} ${json.errors?.[0]?.detail ?? ""}`);
    }
    return json;
  };
}

async function main([keyPath, bundleId, serial]) {
  const { APP_STORE_CONNECT_ISSUER_ID: issuerId, APP_STORE_CONNECT_KEY_ID: keyId } = process.env;
  if (!keyPath || !bundleId || !serial || !issuerId || !keyId) {
    throw new Error("usage: ios-profile.mjs <AuthKey.p8> <bundle id> <certificate serial>, with the key ids in the environment");
  }
  const token = apiToken({ issuerId, keyId, p8: await readFile(keyPath, "utf8") });
  const { uuid, content } = await appStoreProfile({ api: restClient(token), bundleId, serial });
  for (const dir of PROFILE_DIRS) {
    await mkdir(dir, { recursive: true });
    await writeFile(path.join(dir, `${uuid}.mobileprovision`), Buffer.from(content, "base64"));
  }
  console.log(uuid);
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(`ios-profile: ${error.message}`);
    process.exit(1);
  });
}
