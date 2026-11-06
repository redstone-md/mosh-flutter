#!/usr/bin/env node
// Deletes main's superseded Actions cache entries. Caches are saved only from
// main (ADR 0015), so when a key's hash moves, main saves a new entry and the
// old one is never read again; deleting it keeps the 10 GB budget for live
// entries. Runs after CI on main with GH_TOKEN and GH_REPO set.
import { execFileSync } from "node:child_process";
import path from "node:path";
import { pathToFileURL } from "node:url";

/** A key without its trailing hash segments: the cache it is a version of. */
const family = (key) => key.replace(/(-[0-9a-f]{8,})+$/, "");

/**
 * Ids of `entries` ({ id, key, createdAt }) that a newer entry of the same
 * key family has replaced.
 */
export function staleCaches(entries) {
  const newest = new Map();
  for (const entry of entries) {
    const current = newest.get(family(entry.key));
    if (!current || entry.createdAt > current.createdAt) newest.set(family(entry.key), entry);
  }
  return entries.filter((entry) => newest.get(family(entry.key)) !== entry).map(({ id }) => id);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const gh = (...args) => execFileSync("gh", ["cache", ...args], { encoding: "utf8" });
  const entries = JSON.parse(gh("list", "--ref", "refs/heads/main", "--limit", "1000",
    "--json", "id,key,createdAt"));
  const stale = staleCaches(entries);
  for (const id of stale) gh("delete", String(id));
  console.log(`cache-cleanup: ${entries.length} main entries, deleted ${stale.length} superseded`);
}
