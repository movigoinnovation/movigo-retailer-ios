# Flutter, Firebase, Google Maps and Play Core split-install classes all ship
# their own consumer-rules.pro inside their AARs, which R8 merges automatically.
# Do NOT re-add blanket "-keep class x.y.** { *; }" rules for these libraries —
# they disable shrinking/optimization for the whole package and are what Play
# Console's "R8 config could be causing higher memory usage and lower
# performance" warning flags (see Drivers_app's proguard-rules.pro).
-dontwarn io.flutter.embedding.**
-dontwarn com.google.firebase.**
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# Razorpay
-keepattributes *Annotation*
-dontwarn com.razorpay.**
-keep class com.razorpay.** { *; }
-optimizations !method/inlining/*
-keepclasseswithmembers class * {
  public void onPayment*(...);
}

# Geolocator
-keep class com.baseflow.geolocator.** { *; }
-dontwarn com.baseflow.geolocator.**

# Image Cropper
-keep class com.yalantis.ucrop.** { *; }
-dontwarn com.yalantis.ucrop.**

# General
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception
-dontwarn javax.annotation.**

# SLF4J binding is optional. Some socket/Pusher dependencies reference StaticLoggerBinder,
# but the app works with SLF4J's no-operation fallback when no binding is packaged.
-dontwarn org.slf4j.impl.StaticLoggerBinder
-dontwarn org.slf4j.impl.**
-dontwarn org.slf4j.**
