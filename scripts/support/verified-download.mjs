import { createHash } from "node:crypto";
import { setTimeout as sleep } from "node:timers/promises";

class PermanentError extends Error {}

/**
 * The bytes at `url`, checked against their pinned SHA-256. Runner networking
 * drops and truncates downloads now and then, so network errors, 5xx, 429 and
 * checksum mismatches are retried; any other HTTP error fails at once.
 */
export async function downloadVerified(url, sha256, { attempts = 4, timeoutMs = 600_000, delayMs = 5_000 } = {}) {
  for (let attempt = 1; ; attempt++) {
    try {
      const response = await fetch(url, { signal: AbortSignal.timeout(timeoutMs) });
      if (!response.ok) {
        const error = `Download failed: ${response.status} ${url}`;
        throw response.status >= 500 || response.status === 429 ? new Error(error) : new PermanentError(error);
      }
      const bytes = Buffer.from(await response.arrayBuffer());
      if (createHash("sha256").update(bytes).digest("hex") !== sha256) throw new Error(`${url}: checksum mismatch`);
      return bytes;
    } catch (error) {
      if (error instanceof PermanentError || attempt >= attempts) throw error;
      console.warn(`${url}: attempt ${attempt}/${attempts} failed: ${error.message}`);
      await sleep(delayMs * attempt);
    }
  }
}
