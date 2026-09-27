import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// مفاتيح التوقيع تُقرأ من android/key.properties (خارج git). انظر DEVELOPER_GUIDE.md.
// في CI تُكتب هذه الملفات من GitHub Secrets قبل البناء.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
// التوقيع الرسمي فقط إذا وُجد key.properties وملف المفتاح الذي يشير إليه فعلاً
val hasReleaseKeystore = keystorePropertiesFile.exists() &&
    (keystoreProperties["storeFile"] as String?)?.let { file(it).exists() } == true

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

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // بدون key.properties يُوقَّع بمفتاح debug العام — لا تنشر نسخة كهذه للموظفين:
            // أي شخص يستطيع توقيع APK بنفس المفتاح وتثبيته فوق التطبيق.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("⚠️ مفتاح التوقيع الرسمي غير موجود (key.properties أو ملف .jks) — نسخة release موقّعة بمفتاح debug للتجربة فقط.")
                signingConfigs.getByName("debug")
            }
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
