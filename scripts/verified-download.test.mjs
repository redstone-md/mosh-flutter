import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { createServer } from "node:http";
import { after, test } from "node:test";
import { downloadVerified } from "./support/verified-download.mjs";

const body = Buffer.from("pinned archive");
const sha256 = createHash("sha256").update(body).digest("hex");

/** Serves `replies` in order, each a status or "bad" for a corrupt body. */
async function serve(replies) {
  let requests = 0;
  const server = createServer((_, response) => {
    const reply = replies[Math.min(requests++, replies.length - 1)];
    response.statusCode = reply === "bad" ? 200 : reply;
    response.end(reply === 200 ? body : "truncated");
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  after(() => server.close());
  return { url: `http://127.0.0.1:${server.address().port}/archive`, requests: () => requests };
}

const options = { attempts: 3, delayMs: 0 };

test("a dropped or corrupt download is retried until the checksum matches", async () => {
  const server = await serve([503, "bad", 200]);
  assert.deepEqual(await downloadVerified(server.url, sha256, options), body);
  assert.equal(server.requests(), 3);
});

test("a missing file fails at once", async () => {
  const server = await serve([404]);
  await assert.rejects(downloadVerified(server.url, sha256, options), /404/);
  assert.equal(server.requests(), 1);
});

test("a download that never verifies fails after the last attempt", async () => {
  const server = await serve(["bad"]);
  await assert.rejects(downloadVerified(server.url, sha256, options), /checksum mismatch/);
  assert.equal(server.requests(), 3);
});
