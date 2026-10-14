package `in`.rorrim.arena_ops

import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "in.rorrim.arena_ops/alarm_sound"
    private var ringtone: Ringtone? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "playAlarm" -> {
                    try {
                        stopCurrentRingtone()
                        val alertUri: Uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)

                        ringtone = RingtoneManager.getRingtone(applicationContext, alertUri)?.apply {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                                audioAttributes = AudioAttributes.Builder()
                                    .setUsage(AudioAttributes.USAGE_ALARM)
                                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                    .build()
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                isLooping = true
                            }
                            play()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("PLAY_ERROR", e.message, null)
                    }
                }
                "stopAlarm" -> {
                    stopCurrentRingtone()
                    result.success(true)
                }
                "isAlarmPlaying" -> {
                    result.success(ringtone?.isPlaying == true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun stopCurrentRingtone() {
        try {
            ringtone?.let {
                if (it.isPlaying) {
                    it.stop()
                }
            }
        } catch (_: Exception) {}
        ringtone = null
    }

    override fun onDestroy() {
        stopCurrentRingtone()
        super.onDestroy()
    }
}
