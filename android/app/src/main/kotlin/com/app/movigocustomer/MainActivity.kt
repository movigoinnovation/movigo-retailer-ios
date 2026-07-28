package com.app.movigocustomer

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.movigo.retailer/location_intent"
    private var pendingLocationUri: String? = null
    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent != null && Intent.ACTION_VIEW == intent.action) {
            val data: Uri? = intent.data
            if (data != null) {
                val uriString = data.toString()
                if (methodChannel != null) {
                    methodChannel?.invokeMethod("onLocationIntentReceived", uriString)
                } else {
                    pendingLocationUri = uriString
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            if (call.method == "getPendingLocationIntent") {
                result.success(pendingLocationUri)
                pendingLocationUri = null
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.movigo.retailer/permissions")
            .setMethodCallHandler { call, result ->
                if (call.method == "getAppVersion") {
                    try {
                        val packageInfo = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                            packageManager.getPackageInfo(packageName, android.content.pm.PackageManager.PackageInfoFlags.of(0))
                        } else {
                            packageManager.getPackageInfo(packageName, 0)
                        }
                        val versionName = packageInfo.versionName ?: "1.0.0"
                        val versionCode = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                            packageInfo.longVersionCode
                        } else {
                            packageInfo.versionCode.toLong()
                        }
                        result.success(mapOf(
                            "versionName" to versionName,
                            "versionCode" to versionCode
                        ))
                    } catch (e: Exception) {
                        result.error("VERSION_ERROR", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
