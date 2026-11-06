import assert from "node:assert/strict";
import test from "node:test";
import { audit, disallowedSections } from "./license-check.mjs";

const MIT = "MIT License\n\nPermission is hereby granted, free of charge, to any person obtaining a copy";
// MPL-2.0 names the GPL family as "Secondary Licenses" in its own text.
const MPL = "Mozilla Public License Version 2.0\n==================================\n1.12. \"Secondary License\" means either the GNU General Public License, Version 2.0, the GNU Lesser General Public License, Version 2.1, the GNU Affero General Public License, Version 3.0";
const GPL = "                    GNU GENERAL PUBLIC LICENSE\n                       Version 3, 29 June 2007";
const LGPL = "                   GNU LESSER GENERAL PUBLIC LICENSE\n                       Version 2.1, February 1999";

test("permissive and MPL-2.0 packages pass", () => {
  assert.deepEqual(audit([
    { id: "dart:riverpod", texts: [MIT] },
    { id: "go:github.com/anacrolix/torrent", texts: [MPL] },
  ]), []);
});

test("copyleft, unrecognised and missing licenses are reported", () => {
  assert.deepEqual(audit([
    { id: "dart:gpl_package", texts: [GPL] },
    { id: "dart:lgpl_package", texts: [LGPL] },
    { id: "dart:custom", texts: ["All rights reserved."] },
    { id: "go:example.com/bare", texts: [] },
  ]), [
    "dart:gpl_package: GPL is not allowed without a review",
    "dart:lgpl_package: LGPL is not allowed without a review",
    "dart:custom: license not recognised",
    "go:example.com/bare: no license file",
  ]);
});

test("every license file of a package counts", () => {
  assert.deepEqual(audit([
    { id: "dart:dual", texts: [MIT, GPL] },
    { id: "go:example.com/bundled", texts: [`${MPL}\n\nBundled parser:\n${GPL}`] },
  ]), [
    "dart:dual: GPL is not allowed without a review",
    "go:example.com/bundled: GPL is not allowed without a review",
  ]);
});

test("a reviewed package passes whatever its license file says", () => {
  assert.deepEqual(audit([{ id: "go:github.com/anacrolix/sync", texts: [] }]), []);
});

test("libwebrtc notices name every copyleft or H.264 component", () => {
  const notices = "# webrtc\n```\nBSD\n```\n# ffmpeg\n```\nGNU Lesser General Public License\n```\n# opus\n```\nBSD\n```\n# x264\n```\nGNU General Public License\n```\n";
  assert.deepEqual(disallowedSections(notices), ["ffmpeg", "x264"]);
  assert.deepEqual(disallowedSections("# openh264\n```\nBSD-2-Clause\n```\n"), ["openh264"]);
});
