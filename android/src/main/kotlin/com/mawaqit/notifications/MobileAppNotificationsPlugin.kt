package com.mawaqit.notifications

import android.app.ActivityManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MobileAppNotificationsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "MobileAppNotificationsPlugin"
        private const val CHANNEL_NAME = "com.mawaqit.notifications/adhan_player"

        private const val NATIVE_PREFS_FILE = "mawaqit_native_prefs"
        private const val MIGRATION_FLAG_V3 = "migrated_v3_native_player"
        // Substring uniquely identifying the orphan per-sound channels created by
        // the pre-v3 codebase (e.g. "fajr Adhan mawaqit_id", "Silent dhuhr Adhan ...").
        // Does NOT match the new `mawaqit_adhan_playback` channel (underscores)
        // or pre-notification channels (`"Pre fajr "`, no " Adhan " substring).
        private const val ORPHAN_CHANNEL_MARKER = " Adhan "
    }

    private var channel: MethodChannel? = null
    private var appContext: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).apply {
            setMethodCallHandler(this@MobileAppNotificationsPlugin)
        }
        // Runs once per device — idempotent via SharedPreferences flag.
        // Executes from both main and background engines so the migration
        // catches the "user upgrades but never opens the app" case.
        migrateOrphanedAdhanChannels(binding.applicationContext)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = appContext
        if (context == null) {
            result.error("NO_CONTEXT", "Plugin not attached", null)
            return
        }

        when (call.method) {
            "playAdhan" -> {
                val intent = Intent(context, AdhanPlayerService::class.java).apply {
                    action = AdhanPlayerService.ACTION_PLAY
                    putExtra(AdhanPlayerService.EXTRA_SOUND, call.argument<String>("sound").orEmpty())
                    putExtra(AdhanPlayerService.EXTRA_SOUND_TYPE, call.argument<String>("soundType") ?: "customSound")
                    putExtra(AdhanPlayerService.EXTRA_STREAM_USAGE, call.argument<String>("streamUsage") ?: "alarm")
                    putExtra(AdhanPlayerService.EXTRA_VOLUME_ENABLED, call.argument<Boolean>("customVolumeEnabled") ?: false)
                    putExtra(AdhanPlayerService.EXTRA_VOLUME, call.argument<Int>("adhanVolume") ?: 100)
                    putExtra(AdhanPlayerService.EXTRA_PREVIEW_MODE, call.argument<Boolean>("previewMode") ?: false)
                    putExtra(AdhanPlayerService.EXTRA_TITLE, call.argument<String>("title").orEmpty())
                    putExtra(AdhanPlayerService.EXTRA_BODY, call.argument<String>("body").orEmpty())
                    // i18n strings come from Flutter (single source of truth).
                    putExtra(AdhanPlayerService.EXTRA_CHANNEL_NAME, call.argument<String>("channelName") ?: "Adhan playback")
                    putExtra(AdhanPlayerService.EXTRA_CHANNEL_DESCRIPTION, call.argument<String>("channelDescription").orEmpty())
                    putExtra(AdhanPlayerService.EXTRA_STOP_LABEL, call.argument<String>("stopLabel") ?: "Stop")
                    putExtra(AdhanPlayerService.EXTRA_DEFAULT_TITLE, call.argument<String>("defaultTitle") ?: "Adhan")
                }
                startService(context, intent)
                result.success(null)
            }
            "stopAdhan" -> {
                val intent = Intent(context, AdhanPlayerService::class.java).apply {
                    action = AdhanPlayerService.ACTION_STOP
                }
                startService(context, intent)
                result.success(null)
            }
            "setPreviewVolume" -> {
                // Live-adjust the override level on the active preview stream.
                val intent = Intent(context, AdhanPlayerService::class.java).apply {
                    action = AdhanPlayerService.ACTION_SET_PREVIEW_VOLUME
                    putExtra(AdhanPlayerService.EXTRA_VOLUME, call.argument<Int>("adhanVolume") ?: 100)
                }
                startService(context, intent)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startService(context: Context, intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Background callers (the ringAlarm isolate) must use startForegroundService;
            // foreground callers can use a regular start to avoid FGS timeout races.
            if (isAppInForeground(context)) {
                context.startService(intent)
            } else {
                context.startForegroundService(intent)
            }
        } else {
            context.startService(intent)
        }
    }

    private fun isAppInForeground(context: Context): Boolean {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager ?: return false
        val processes = am.runningAppProcesses ?: return false
        val pkg = context.packageName
        return processes.any {
            it.processName == pkg &&
                it.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
        }
    }

    /**
     * One-time cleanup of orphan notification channels left over from the
     * pre-v3 codebase, where each prayer × sound combination created its own
     * channel (e.g. "fajr Adhan mawaqit_id"). Those channels are no longer
     * used — adhan playback now goes through MediaPlayer on the single
     * `mawaqit_adhan_playback` channel — and they'd show up as confusing
     * orphan entries in Settings → Apps → Mawaqit → Notifications.
     *
     * Safe-by-substring: only matches the " Adhan " marker (with surrounding
     * spaces), which uniquely identifies the old channels regardless of
     * prayer-name localization. Pre-notification channels ("Pre fajr ") and
     * the new channel (`mawaqit_adhan_playback`) are untouched.
     */
    private fun migrateOrphanedAdhanChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val prefs = context.getSharedPreferences(NATIVE_PREFS_FILE, Context.MODE_PRIVATE)
        if (prefs.getBoolean(MIGRATION_FLAG_V3, false)) return

        val nm = context.getSystemService(NotificationManager::class.java) ?: return

        var deleted = 0
        try {
            nm.notificationChannels.toList().forEach { ch ->
                if (ch.id.contains(ORPHAN_CHANNEL_MARKER)) {
                    nm.deleteNotificationChannel(ch.id)
                    deleted++
                }
            }
            Log.i(TAG, "Adhan channel migration v3: deleted $deleted orphan channel(s)")
            prefs.edit().putBoolean(MIGRATION_FLAG_V3, true).apply()
        } catch (t: Throwable) {
            // Don't set the flag — let the migration retry on next engine attach.
            Log.e(TAG, "Adhan channel migration v3 failed", t)
        }
    }
}
