# JNI resolves the class/method name exported by mosh-core.
-keep,allowoptimization class app.mosh.mosh.MoshNative { *; }
-keep,allowoptimization class app.mosh.mosh.MoshMedia { *; }
-keep,allowoptimization class app.mosh.mosh.MoshCallCamera { *; }
-keep class org.webrtc.** { *; }
