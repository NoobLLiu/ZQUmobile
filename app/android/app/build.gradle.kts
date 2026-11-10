import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 发布签名：signing 密钥库不进货，由 CI 从 Secrets 还原 / 本机放在
// android/key.properties（均已被 .gitignore 排除），见 android/key.properties.example。
// 关键点：之前 release 用的是 debug 签名，CI runner 每跑一次都会新生成一个 debug.keystore，
// 导致每个版本的签名都不一样，装新版本时必然报「签名不一致」。改成固定 release 密钥后，
// 同一台手机上的新版本可以直接覆盖安装。
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val keystoreProperties =
    Properties().apply {
        if (hasReleaseKeystore) {
            FileInputStream(keystorePropertiesFile).use { load(it) }
        }
    }

android {
    namespace = "com.nooblliu.zhangshang_yanyuan"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications 需要 java.time 等 API 的脱糖支持
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.nooblliu.zhangshang_yanyuan"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 固定密钥库签名（密钥库不进版本库，见文件头注释）
    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // 没有密钥库（例如别人 clone 下来自己编）时退回 debug 签名，
            // 但那种包不能覆盖安装官方包，仅用于本地跑 --release 验证。
            signingConfig =
                if (hasReleaseKeystore) {
                    signingConfigs.getByName("release")
                } else {
                    logger.warn(
                        "⚠ 未找到 android/key.properties，release 将使用 debug 签名，该包无法覆盖安装官方版本。",
                    )
                    signingConfigs.getByName("debug")
                }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 配合 isCoreLibraryDesugaringEnabled（flutter_local_notifications 要求）
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
