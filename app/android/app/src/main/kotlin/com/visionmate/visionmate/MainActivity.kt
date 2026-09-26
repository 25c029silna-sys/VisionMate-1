package com.visionmate.visionmate

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "com.visionmate.app/sms"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "sendSms") {
                val phoneNumber = call.argument<String>("phoneNumber")
                val message = call.argument<String>("message")

                if (phoneNumber.isNullOrEmpty() || message.isNullOrEmpty()) {
                    result.error("INVALID_ARGUMENTS", "Phone number and message must not be empty", null)
                    return@setMethodCallHandler
                }

                try {
                    val smsManager: SmsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        this.getSystemService(SmsManager::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        SmsManager.getDefault()
                    }

                    val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    } else {
                        PendingIntent.FLAG_UPDATE_CURRENT
                    }

                    val sentIntent = PendingIntent.getBroadcast(
                        this,
                        0,
                        Intent("SMS_SENT"),
                        flags
                    )

                    smsManager.sendTextMessage(phoneNumber, null, message, sentIntent, null)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("SMS_FAILED", e.localizedMessage, null)
                }
            } else if (call.method == "makeCall") {
                val phoneNumber = call.argument<String>("phoneNumber")
                if (phoneNumber.isNullOrEmpty()) {
                    result.error("INVALID_ARGUMENTS", "Phone number must not be empty", null)
                    return@setMethodCallHandler
                }
                try {
                    val intent = Intent(Intent.ACTION_CALL, android.net.Uri.parse("tel:$phoneNumber"))
                    intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    // Fall back to ACTION_DIAL if ACTION_CALL fails or permissions pending
                    val dialIntent = Intent(Intent.ACTION_DIAL, android.net.Uri.parse("tel:$phoneNumber"))
                    dialIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    startActivity(dialIntent)
                    result.success(true)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}

