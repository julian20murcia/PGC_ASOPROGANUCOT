package com.example.pgc_asoproganucot

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val NOTIFICATIONS_CHANNEL_ID = "asoproganucott_alerts"
        private const val NOTIFICATIONS_CHANNEL_NAME = "Entregas y Liquidaciones"
        private const val METHOD_CHANNEL = "com.example.pgc_asoproganucot/notifications"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ensureNotificationChannel()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensureNotificationChannel()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "showNotification") {
                    val id = call.argument<Int>("id")
                        ?: (System.currentTimeMillis() % Int.MAX_VALUE).toInt()
                    val title = call.argument<String>("title") ?: "ASOPROGANUCOTT"
                    val body = call.argument<String>("body") ?: ""
                    showLocalNotification(id, title, body)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(NOTIFICATIONS_CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            NOTIFICATIONS_CHANNEL_ID,
            NOTIFICATIONS_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Avisos de entregas diarias, cierres quincenales y comunicados."
            enableVibration(true)
        }
        manager.createNotificationChannel(channel)
    }

    private fun showLocalNotification(id: Int, title: String, body: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        try {
            ensureNotificationChannel()
            val manager = getSystemService(NotificationManager::class.java) ?: return
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pendingIntent = PendingIntent.getActivity(this, 0, intent, pendingFlags)

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, NOTIFICATIONS_CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this).setPriority(Notification.PRIORITY_HIGH)
            }

            val notification = builder
                .setSmallIcon(R.drawable.ic_stat_notification)
                .setColor(getColor(R.color.notification_accent))
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setAutoCancel(true)
                .setContentIntent(pendingIntent)
                .build()

            manager.notify(id, notification)
        } catch (_: SecurityException) {
            // Permiso denegado en tiempo de ejecución.
        }
    }
}
