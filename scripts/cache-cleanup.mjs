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
  for (const { key, createdAt } of entries) {
    if (!(newest.get(family(key)) >= createdAt)) newest.set(family(key), createdAt);
  }
  return entries.filter(({ key, createdAt }) => createdAt < newest.get(family(key))).map(({ id }) => id);
}

/** Main's caches should leave this much of the 10 GB for stale and PR entries. */
const BUDGET_BYTES = 8 * 1024 ** 3;

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const gh = (...args) => execFileSync("gh", args, { encoding: "utf8" });
  const entries = JSON.parse(gh("cache", "list", "--ref", "refs/heads/main", "--limit", "1000",
    "--json", "id,key,createdAt"));
  const stale = staleCaches(entries);
  for (const id of stale) gh("cache", "delete", String(id));
  const { active_caches_size_in_bytes: used } = JSON.parse(gh("api", `repos/${process.env.GH_REPO}/actions/cache/usage`));
  const gigabytes = (used / 1024 ** 3).toFixed(1);
  console.log(`cache-cleanup: ${entries.length} main entries, deleted ${stale.length} superseded, ${gigabytes} GB in use`);
  if (used > BUDGET_BYTES) console.log(`::warning::Actions caches use ${gigabytes} GB, over the 8 GB budget (ADR 0015)`);
}
