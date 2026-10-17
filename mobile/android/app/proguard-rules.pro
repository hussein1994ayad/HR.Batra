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

# مكتبات JNI (shared_preferences_android 2.5 / Pigeon JNI) تدوّر على دوال Kotlin بالاسم الكامل لتواقيعها،
# فلازم R8 ما يغيّر أسماء أنواع Kotlin الأساسية. بدونها نسخة الإصدار بس تفشل بـ NoSuchMethodError:
# الجلسة ما تنحفظ (يطلع من الحساب كل ما يتسكر التطبيق) وخدمة الموقع بالخلفية ما تشتغل.
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.intrinsics.** { *; }
-keep class kotlin.Unit { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.jvm.internal.DefaultConstructorMarker { *; }
-keep class kotlin.enums.EnumEntries { *; }
