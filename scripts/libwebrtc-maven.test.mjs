import assert from "node:assert/strict";
import { test } from "node:test";
import { bundle } from "./libwebrtc-maven.mjs";

const spec = { release: "libwebrtc-m150-9c3a138-1", maven: "io.github.example:libwebrtc", commit: "9c3a138" };

test("the bundle lays out the POM and the classified archive with their checksums", () => {
  const files = bundle(spec, Buffer.from("abc"));
  const directory = "io/github/example/libwebrtc/m150-9c3a138-1";
  const archive = `${directory}/libwebrtc-m150-9c3a138-1-android-arm64-release.tar.gz`;
  const pom = `${directory}/libwebrtc-m150-9c3a138-1.pom`;
  assert.deepEqual([...files.keys()].sort(), [
    archive, `${archive}.md5`, `${archive}.sha1`, pom, `${pom}.md5`, `${pom}.sha1`,
  ]);
  assert.equal(files.get(`${archive}.md5`).toString(), "900150983cd24fb0d6963f7d28e17f72");
  assert.equal(files.get(`${archive}.sha1`).toString(), "a9993e364706816aba3e25717850c26c9cd0d89d");
  const project = files.get(pom).toString();
  for (const element of ["<groupId>io.github.example</groupId>", "<artifactId>libwebrtc</artifactId>",
    "<version>m150-9c3a138-1</version>", "<packaging>pom</packaging>"]) {
    assert.ok(project.includes(element), element);
  }
});
