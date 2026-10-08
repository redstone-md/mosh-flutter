# ADR 0044: native call media over Moss

Date: 2026-10-08
Status: Accepted

For [issue 46](https://github.com/redstone-md/mosh-flutter/issues/46), use one
established native engine for audio and video, with all network media carried
by Moss. The main process retains the media owner and its capture, codec,
encryption and playback lifetimes; the separate desktop window receives bounded
video frames for presentation and sends call-bound commands. This preserves the
working call when its presentation process fails and avoids separate audio/video
transport implementations.

Moss owns routing and transport capacity; Mosh owns call admission, device consent
and media processing. Extend Moss when required without introducing another
mandatory server. Relays have a bounded aggregate budget and agreed flow budgets,
with capacity preserved for messages/control and audio prioritized over video.
Increasing every node's default rate alone does not establish those guarantees.

Native ownership resolves the media placement proposed in
[ADR 0012](0012-port-strategy-what-goes-to-dart-vs-mosh-core.md) for this feature.
Moving the engine into the call window would simplify rendering but make media
depend on that process. Keeping a separate video engine beside the current voice
pipeline would duplicate timing, recovery and adaptation work. The chosen boundary
instead requires explicit frame IPC and reproducible native packaging.

The exact engine remains under
[source investigation](../Proposals/issue-46-media-engine.research.md).
Prove native builds, directed Moss media and desktop frame delivery before replacing
the working voice implementation. Existing call-client protocol compatibility is
not required; all participants upgrade together.

Hardware encoding is preferred when the chosen engine and device support it,
but is not a first-release requirement. A software path must pass sustained
720p/30 quality, latency, UI responsiveness and thermal checks. Missing camera
or microphone permission must preserve the remaining receive/send capabilities
instead of making capture a prerequisite for receiving media.
