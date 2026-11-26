import assert from "node:assert/strict";
import { test } from "node:test";
import { RateLimit } from "../src/limits.ts";

test("a full limiter forgets its oldest callers instead of growing", () => {
  const limit = new RateLimit(1, 60_000, () => 0, 2);
  for (const key of ["a", "b", "c"]) assert.ok(limit.allow(key));

  assert.equal(limit.allow("c"), false, "a recent caller is still limited");
  assert.ok(limit.allow("a"), "the oldest caller made room");
});

test("a refused request does not hold the slot a refund gives back", () => {
  const limit = new RateLimit(1, 10_000, () => 0);
  assert.ok(limit.allow("k"));
  assert.equal(limit.allow("k"), false);

  limit.refund("k");
  assert.ok(limit.allow("k"), "the refunded slot is free again");
});
