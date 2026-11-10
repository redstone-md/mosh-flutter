import assert from "node:assert/strict";
import test from "node:test";
import { rows, table } from "./call-video-bench.mjs";

const row = (name, width, height, ms) =>
  `call-video-bench ${JSON.stringify({ case: name, width, height, ms })}`;

test("a case becomes one line with its time and share of a core at 30 fps per size", () => {
  const output = ["Compiling mosh-core", row("scale", 1280, 720, 3.64), "test result: ok",
    row("scale", 640, 360, 0.734), row("scale", 1920, 1080, 20)].join("\n");
  assert.equal(table(rows(output)), [
    "| Case | 640x360 | 1280x720 | 1920x1080 |",
    "|------|---------|----------|-----------|",
    "| scale | 0.73 (2%) | 3.64 (11%) | 20.0 (60%) |",
  ].join("\n"));
});

test("cases keep the order they ran in, and a size that did not run stays empty", () => {
  const measured = rows([row("second", 640, 360, 1), row("first", 1280, 720, 0.004)].join("\n"));
  assert.deepEqual(table(measured).split("\n").slice(2), [
    "| second | 1.00 (3%) |  |  |",
    "| first |  | 0.00 (0%) |  |",
  ]);
});
