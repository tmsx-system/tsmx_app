package com.tmsxhub

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Environment
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val methodChannelName = "com.tmsxhub/notifications"
    private val fileChannelName = "com.tmsxhub/files"
    private val approvalChannelId = "approval_todo"
    private var permissionResult: MethodChannel.Result? = null
    private var notificationChannel: MethodChannel? = null
    private var pendingTapPayload: Map<String, String>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannel()
        notificationChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            methodChannelName,
        )
        captureNotificationIntent(intent, emitImmediately = false)
        notificationChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> requestNotificationPermission(result)
                "showNotification" -> {
                    val id = call.argument<Int>("id") ?: 1001
                    val title = call.argument<String>("title") ?: "TMSX Hub"
                    val body = call.argument<String>("body") ?: ""
                    val target = call.argument<String>("target") ?: ""
                    showNotification(id, title, body, target)
                    result.success(null)
                }
                "consumeInitialTapPayload" -> {
                    result.success(pendingTapPayload)
                    pendingTapPayload = null
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            fileChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveFileToDownloads" -> saveFileToDownloads(
                    call.argument<String>("sourcePath"),
                    call.argument<String>("fileName"),
                    call.argument<String>("mimeType"),
                    call.argument<String>("subdirectory"),
                    result,
                )
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureNotificationIntent(intent, emitImmediately = true)
    }

    private fun captureNotificationIntent(intent: Intent?, emitImmediately: Boolean) {
        val target = intent?.getStringExtra("notification_target") ?: return
        if (target.isBlank()) return
        val payload = mapOf("target" to target)
        if (emitImmediately) {
            notificationChannel?.invokeMethod("onNotificationTap", payload)
        } else {
            pendingTapPayload = payload
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        permissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            31001,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 31001) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            permissionResult?.success(granted)
            permissionResult = null
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            approvalChannelId,
            "Todo Approval",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Notifikasi dokumen yang menunggu approval"
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(channel)
    }

    private fun showNotification(id: Int, title: String, body: String, target: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("notification_target", target)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, approvalChannelId)
        } else {
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setPriority(Notification.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(id, notification)
    }

    private fun saveFileToDownloads(
        sourcePath: String?,
        fileName: String?,
        mimeType: String?,
        subdirectory: String?,
        result: MethodChannel.Result,
    ) {
        try {
            val source = File(sourcePath ?: "")
            val targetName = fileName?.takeIf { it.isNotBlank() } ?: source.name
            val targetMime = mimeType?.takeIf { it.isNotBlank() } ?: "application/octet-stream"
            val targetSubdirectory = subdirectory?.takeIf { it.isNotBlank() } ?: "TMSX Hub"
            if (!source.exists() || !source.isFile) {
                result.error("FILE_NOT_FOUND", "Source file not found", sourcePath)
                return
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, targetName)
                    put(MediaStore.MediaColumns.MIME_TYPE, targetMime)
                    put(
                        MediaStore.MediaColumns.RELATIVE_PATH,
                        "${Environment.DIRECTORY_DOWNLOADS}/$targetSubdirectory",
                    )
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val resolver = applicationContext.contentResolver
                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                if (uri == null) {
                    result.error("CREATE_FAILED", "Failed to create download file", null)
                    return
                }
                resolver.openOutputStream(uri)?.use { output ->
                    FileInputStream(source).use { input -> input.copyTo(output) }
                }
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                result.success("Download/$targetSubdirectory/$targetName")
                return
            }

            val directory = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                targetSubdirectory,
            )
            if (!directory.exists()) directory.mkdirs()
            val target = File(directory, targetName)
            FileInputStream(source).use { input ->
                FileOutputStream(target).use { output -> input.copyTo(output) }
            }
            result.success(target.absolutePath)
        } catch (error: Exception) {
            result.error("SAVE_FAILED", error.message, null)
        }
    }
}
