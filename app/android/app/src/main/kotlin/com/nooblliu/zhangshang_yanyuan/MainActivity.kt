package com.nooblliu.zhangshang_yanyuan

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// 应用内更新的原生能力：
/// - deviceAbi：返回本机首选 ABI，用于挑选对应的 split APK；
/// - prepareDownload：准备并返回下载目录（cache/upgrade/）；
/// - installApk：FileProvider + ACTION_VIEW 调起系统安装器。
///
/// 全程不查询已安装应用列表（不需要 QUERY_ALL_PACKAGES）。
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "deviceAbi" -> result.success(deviceAbi())
                    "prepareDownload" -> {
                        val dir = File(cacheDir, "upgrade")
                        if (!dir.exists()) dir.mkdirs()
                        result.success(dir.absolutePath)
                    }
                    "installApk" -> installApk(call.arguments as? String, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun deviceAbi(): String {
        for (abi in Build.SUPPORTED_ABIS) {
            if (abi == "arm64-v8a" || abi == "armeabi-v7a") return abi
        }
        return Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a"
    }

    private fun installApk(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrEmpty()) {
            result.error("invalid_args", "缺少 APK 路径", null)
            return
        }
        try {
            // Android 8+ 需要用户先允许「安装未知应用」；跳到系统设置页，
            // 用户授权回来后 Dart 侧重试（APK 已缓存，不用重新下载）。
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                !packageManager.canRequestPackageInstalls()
            ) {
                startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName"),
                    )
                )
                result.success("needPermission")
                return
            }
            val file = File(path)
            if (!file.exists()) {
                result.error("not_found", "安装包不存在：$path", null)
                return
            }
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success("started")
        } catch (e: Exception) {
            result.error("install_failed", e.message, null)
        }
    }

    companion object {
        private const val CHANNEL = "zsy/updater"
    }
}
