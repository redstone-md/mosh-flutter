# Native Android audio context probe

`node scripts/android-context-check.mjs` builds the production JNI context
bootstrap into an isolated host library and calls it from a real JVM.
It reproduces CPAL's missing-context failure before bootstrap, then checks
null refusal, initialization, Activity recreation and retained application
ownership after garbage collection. A JDK and Rust are required.

This does not simulate Android audio devices. Verify their real inventory,
permissions and playback on an Android ARM64 phone as well.
