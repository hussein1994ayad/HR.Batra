plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.batra.hrpro.hr_pro"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.batra.hrpro.hr_pro"
        // ⬇️  خفّضنا minSdk من 26 إلى 24 لدعم Android 7 (Nougat) — تغطية سوقية أكبر.
        minSdk = 24
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO(android-release): استبدل بمفاتيح release keystore حقيقية
            // عند الحصول على حساب Google Play Console:
            //   1. أنشئ keystore: keytool -genkey -v -keystore batra.jks -alias batra ...
            //   2. أضف key.properties (خارج git) بالمفاتيح
            //   3. استبدل السطر أدناه بـ signingConfigs.getByName("release")
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
}
