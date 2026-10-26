# Native Android audio context probe

`node scripts/android-context-check.mjs` builds the production JNI context
bootstrap into an isolated host library and calls it from a real JVM.
It reproduces CPAL's missing-context failure before bootstrap, then checks
null refusal, initialization, Activity recreation and retained application
ownership after garbage collection. A JDK and Rust are required.

It also compiles the production Android communication-input policy with `javac`:
a detected source must remain present in inventory before permission, the paired
default alias is valid, and missing/unsupported independent inputs are rejected.

This does not simulate Android audio devices. Verify their real inventory,
permissions and playback on an Android ARM64 phone as well.

The same command runs the production Android app-lock policy against controlled
elapsed/boot clocks and persistence faults. It checks every accepted delay,
screen-off deadline preservation, same-boot grace, cold/reboot refusal, rollback
and a refused synchronous save. Platform authentication and actual Activity
timing still need a real phone; see [app lock](../../docs/Features/android-app-lock.md).
