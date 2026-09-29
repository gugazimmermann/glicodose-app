package app.glicodose.car_alerts

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.car.app.model.CarColor
import androidx.car.app.notification.CarAppExtender
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Re-posts a hypo/hyper alert so Android Auto can show it over Maps.
class GlicoDoseCarAlertsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "show") {
            result.notImplemented()
            return
        }
        val id = call.argument<Int>("id")
        val title = call.argument<String>("title")
        val body = call.argument<String>("body") ?: ""
        val zone = call.argument<String>("zone")
        if (id == null || title.isNullOrEmpty() || (zone != "hypo" && zone != "hyper")) {
            result.success(null)
            return
        }
        show(id, title, body, zone)
        result.success(null)
    }

    private fun show(id: Int, title: String, body: String, zone: String) {
        val notifier = NotificationManagerCompat.from(appContext)
        if (!notifier.areNotificationsEnabled()) return
        ensureChannel()
        val color = if (zone == "hypo") HYPO_COLOR else HYPER_COLOR
        val notification = NotificationCompat.Builder(appContext, ALERT_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_car_glucose)
            .setContentTitle(title)
            .setContentText(body)
            .setColor(color)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .extend(
                CarAppExtender.Builder()
                    .setImportance(NotificationManagerCompat.IMPORTANCE_HIGH)
                    .setContentTitle(title)
                    .setContentText(body)
                    .setSmallIcon(R.drawable.ic_car_glucose)
                    .setColor(CarColor.createCustom(color, color))
                    .build(),
            )
            .build()
        try {
            notifier.notify(id, notification)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS not granted.
        }
    }

    private fun ensureChannel() {
        val manager = appContext.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(ALERT_CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            ALERT_CHANNEL_ID,
            ALERT_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        )
        channel.description = "Alertas de hipoglicemia, hiperglicemia e sensor parado"
        channel.enableVibration(true)
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val CHANNEL = "app.glicodose/car_alerts"
        const val ALERT_CHANNEL_ID = "libre_glucose_alerts"
        const val ALERT_CHANNEL_NAME = "Alertas de glicose Libre"
        const val HYPO_COLOR = 0xFFC62828.toInt()
        const val HYPER_COLOR = 0xFFF9A825.toInt()
    }
}
