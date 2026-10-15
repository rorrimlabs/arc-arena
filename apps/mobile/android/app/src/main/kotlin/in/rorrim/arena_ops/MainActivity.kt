package `in`.rorrim.arena_ops

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // core/notifications/notification_service.dart: once Android stops
        // asking for the notification permission, the phone's settings are
        // the only place left to turn it on.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYSTEM_SETTINGS)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openNotificationSettings" -> result.success(openNotificationSettings())
                    else -> result.notImplemented()
                }
            }
    }

    /** This app's notification settings (Android 8+), else its App info page. */
    private fun openNotificationSettings(): Boolean {
        val notifications = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            null
        }
        val appInfo = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", packageName, null),
        )
        for (intent in listOfNotNull(notifications, appInfo)) {
            try {
                startActivity(intent)
                return true
            } catch (e: ActivityNotFoundException) {
                // Not on this phone: try the next page.
            }
        }
        return false
    }

    private companion object {
        const val SYSTEM_SETTINGS = "arena_ops/system_settings"
    }
}
