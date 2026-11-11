# JNI resolves the class/method name exported by mosh-core.
-keep,allowoptimization class app.mosh.mosh.MoshNative { *; }
-keep,allowoptimization class app.mosh.mosh.MoshMedia { *; }
-keep,allowoptimization class app.mosh.mosh.MoshCallCamera { *; }
-keep,allowoptimization class app.mosh.mosh.MoshCallVideo { *; }
-keep class org.webrtc.** { *; }
-keep class livekit.org.webrtc.** { *; }

# Native-only upcalls, as in the pinned JNI Zero proguard.flags. This
# libwebrtc.jar does not package Chromium's consumer keep rules.
-keepclasseswithmembers,includedescriptorclasses,allowoptimization class ** {
    @org.jni_zero.CalledByNative <methods>;
}
-keepclasseswithmembers,includedescriptorclasses,allowoptimization class ** {
    @org.jni_zero.CalledByNativeUnchecked <methods>;
}
-keepclasseswithmembers class ** {
    @org.jni_zero.AccessedByNative <fields>;
}
# The libwebrtc engine's classes carry LiveKit's package prefix.
-keepclasseswithmembers,includedescriptorclasses,allowoptimization class ** {
    @livekit.org.jni_zero.CalledByNative <methods>;
}
-keepclasseswithmembers,includedescriptorclasses,allowoptimization class ** {
    @livekit.org.jni_zero.CalledByNativeUnchecked <methods>;
}
-keepclasseswithmembers class ** {
    @livekit.org.jni_zero.AccessedByNative <fields>;
}
