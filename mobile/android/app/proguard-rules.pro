# Flutter ProGuard Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Prevent R8 from removing annotations
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Supabase / GoTrue / Postgrest
-dontwarn okio.**
-dontwarn javax.annotation.**

# Firebase
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Google Play Core & Deferred Components
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

