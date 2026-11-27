import assert from "node:assert/strict";
import { test } from "node:test";
import { RateLimit } from "../src/limits.ts";

test("a full limiter forgets its oldest callers instead of growing", () => {
  const limit = new RateLimit(1, 60_000, () => 0, 2);
  for (const key of ["a", "b", "c"]) assert.ok(limit.allow(key));

  assert.equal(limit.allow("c"), undefined, "a recent caller is still limited");
  assert.ok(limit.allow("a"), "the oldest caller made room");
});

test("a refused request does not hold the slot a refund gives back", () => {
  const limit = new RateLimit(1, 10_000, () => 0);
  const refund = limit.allow("k");
  assert.ok(refund);
  assert.equal(limit.allow("k"), undefined);

  refund();
  assert.ok(limit.allow("k"), "the refunded slot is free again");
});

test("a refund that lands after its window does not reopen the next one", () => {
  let now = 0;
  const limit = new RateLimit(1, 10_000, () => now);
  const refund = limit.allow("k");
  assert.ok(refund);
  now = 10_000;
  assert.ok(limit.allow("k"), "a new window opens");

  refund();
  assert.equal(limit.allow("k"), undefined, "the new window's request still counts");
});
