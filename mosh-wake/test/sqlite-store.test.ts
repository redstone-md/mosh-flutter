import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { after, test } from "node:test";
import { SqliteStore } from "../src/sqlite-store.ts";

// The deployed service's file predates FCM; its iPhones must keep working.
test("a file from before FCM keeps its devices and takes FCM ones", async () => {
  const dir = mkdtempSync(join(tmpdir(), "mosh-wake-"));
  after(() => rmSync(dir, { recursive: true, force: true }));
  const path = join(dir, "wake.sqlite");
  const old = new DatabaseSync(path);
  old.exec(`CREATE TABLE devices (handle TEXT PRIMARY KEY, secret_hash TEXT NOT NULL, apns TEXT, voip TEXT,
    environment TEXT NOT NULL) STRICT`);
  old.prepare("INSERT INTO devices VALUES (?, ?, ?, ?, ?)").run("iphone", "hash", "aa", null, "sandbox");
  old.close();

  const store = new SqliteStore(path);
  await store.put({ handle: "android", secretHash: "hash", platform: "fcm", fcm: "tok" });

  assert.deepEqual(await store.get("iphone"), {
    handle: "iphone", secretHash: "hash", platform: "apple", apns: "aa", voip: null, environment: "sandbox",
  });
  assert.deepEqual(await store.get("android"), { handle: "android", secretHash: "hash", platform: "fcm", fcm: "tok" });
  await store.forgetToken("android", "tok");
  assert.deepEqual(await store.get("android"), { handle: "android", secretHash: "hash", platform: "fcm", fcm: null });
});
