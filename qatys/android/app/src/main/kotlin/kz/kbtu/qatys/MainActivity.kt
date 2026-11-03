package kz.kbtu.qatys

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createEventsChannel()
    }

    // Brief §9, "Silent phone": high importance shows a heads-up notification
    // and vibrates even when the ringer is muted. The id matches the server's
    // FCM payload (docs/api.md) and the manifest default.
    private fun createEventsChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "events_high",
            "New events",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "A community you follow published an event"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 400, 200, 400)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
}
