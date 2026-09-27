package com.batra.hrpro.hr_pro

import android.annotation.SuppressLint
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
                    else -> result.notImplemented()
                }
            }
    }

    // ANDROID_ID ثابت لنفس الجهاز ونفس مفتاح التوقيع، ويبقى بعد حذف التطبيق
    // وإعادة تثبيته — مناسب لقفل الجهاز الواحد.
    @SuppressLint("HardwareIds")
    private fun stableDeviceId(): String? {
        val id = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
        return if (id.isNullOrBlank()) null else "android-$id"
    }
}
