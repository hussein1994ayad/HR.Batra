package com.batra.hrpro.hr_pro

import android.annotation.SuppressLint
import android.os.SystemClock
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.batra.hrpro/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStableDeviceId" -> result.success(stableDeviceId())
                    "clockSnapshot" -> result.success(clockSnapshot())
                    else -> result.notImplemented()
                }
            }
    }

    // عدّاد منذ تشغيل الموبايل (يكمل والشاشة مطفية وما يتأثر بتغيير الساعة) + رقم التشغيل:
    // التطبيق يحسب منهم وقت البصمة الحقيقي بدون إنترنت (تدقيق 14/10 BUG-001).
    private fun clockSnapshot(): Map<String, Any> = mapOf(
        "elapsedMs" to SystemClock.elapsedRealtime(),
        "bootId" to "count:" + Settings.Global.getInt(contentResolver, Settings.Global.BOOT_COUNT, -1),
    )

    // ANDROID_ID ثابت لنفس الجهاز ونفس مفتاح التوقيع، ويبقى بعد حذف التطبيق
    // وإعادة تثبيته — مناسب لقفل الجهاز الواحد.
    @SuppressLint("HardwareIds")
    private fun stableDeviceId(): String? {
        val id = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
        return if (id.isNullOrBlank()) null else "android-$id"
    }
}
