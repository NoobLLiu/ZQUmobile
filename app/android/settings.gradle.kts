// 仓库配置：优先走国内镜像（阿里云），再回落官方源。
//
// 背景：本机设置了 http_proxy/https_proxy，走代理访问 dl.google.com 与
// repo.maven.apache.org 会出现连接隧道建立后长时间 0 B/s 的卡死；
// 直连官方源反而不稳，阿里云镜像最快（google 仓库约 31KB/s，0.1s 完成）。
// 因此这里把镜像放在前面，官方源作为兜底。

pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
