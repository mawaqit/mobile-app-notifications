package com.mawaqit.notifications

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Foreground service that plays the adhan via MediaPlayer on a user-selectable
 * audio stream (alarm / ringtone / notification / media).
 *
 * Why this exists: notification-played sounds can be silenced by a single
 * volume-key press on Android (system-level UX hook). Owning playback in a
 * service detaches it from that hook — volume keys then only adjust loudness.
 */
class AdhanPlayerService : Service() {

    companion object {
        private const val TAG = "AdhanPlayerService"

        private const val NOTIFICATION_ID = 7733
        private const val CHANNEL_ID = "mawaqit_adhan_playback"

        const val ACTION_PLAY = "com.mawaqit.notifications.ACTION_PLAY"
        const val ACTION_STOP = "com.mawaqit.notifications.ACTION_STOP"

        const val EXTRA_SOUND = "sound"            // raw resource name OR file path / URI
        const val EXTRA_SOUND_TYPE = "soundType"   // "customSound" | "systemSound"
        const val EXTRA_STREAM_USAGE = "streamUsage" // "alarm" | "ringtone" | "notification" | "media"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"

        // i18n strings — Flutter is the source of truth for translation; native
        // strings here are defensive English fallbacks only.
        const val EXTRA_CHANNEL_NAME = "channelName"
        const val EXTRA_CHANNEL_DESCRIPTION = "channelDescription"
        const val EXTRA_STOP_LABEL = "stopLabel"
        const val EXTRA_DEFAULT_TITLE = "defaultTitle"
    }

    private var mediaPlayer: MediaPlayer? = null

    private val audioManager: AudioManager by lazy {
        getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }

    // Focus-loss is most often a phone call interrupting the adhan; we stop
    // playback but keep the notification visible so the user can still see
    // which prayer fired once the call ends.
    private val audioFocus: AudioFocusHelper by lazy {
        AudioFocusHelper(this, mainHandler) { stopPlaybackAndPersist() }
    }

    private val vibrator: Vibrator? by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        // Channel is created/refreshed in startAsForeground() so it can use the
        // up-to-date translated strings sent from Dart with every play call.
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopPlaybackAndSelf()
                return START_NOT_STICKY
            }
            ACTION_PLAY, null -> {
                val sound = intent?.getStringExtra(EXTRA_SOUND).orEmpty()
                val soundType = intent?.getStringExtra(EXTRA_SOUND_TYPE) ?: "customSound"
                val streamUsage = intent?.getStringExtra(EXTRA_STREAM_USAGE) ?: "alarm"
                val title = intent?.getStringExtra(EXTRA_TITLE).orEmpty()
                val body = intent?.getStringExtra(EXTRA_BODY).orEmpty()
                val channelName = intent?.getStringExtra(EXTRA_CHANNEL_NAME) ?: "Adhan playback"
                val channelDescription = intent?.getStringExtra(EXTRA_CHANNEL_DESCRIPTION).orEmpty()
                val stopLabel = intent?.getStringExtra(EXTRA_STOP_LABEL) ?: "Stop"
                val defaultTitle = intent?.getStringExtra(EXTRA_DEFAULT_TITLE) ?: "Adhan"

                // If the resolved stream will be silenced by the current ringer
                // state (e.g. user has play-in-silent off + phone is muted),
                // skip MediaPlayer entirely and omit the Stop action — there's
                // nothing to stop. The heads-up notification still appears.
                val audible = isStreamAudible(streamUsage)
                startAsForeground(
                    title, body, channelName, channelDescription, stopLabel, defaultTitle,
                    includeStopAction = audible,
                )
                if (audible) {
                    startPlayback(sound, soundType, streamUsage)
                } else {
                    Log.i(TAG, "Stream '$streamUsage' is silenced — visual notification only")
                    mainHandler.postDelayed({ stopPlaybackAndPersist() }, 3000L)
                }
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releasePlayer()
        super.onDestroy()
    }

    // region playback

    private fun startPlayback(sound: String, soundType: String, streamUsage: String) {
        releasePlayer()

        val usage = mapUsage(streamUsage)
        val attributes = AudioAttributes.Builder()
            .setUsage(usage)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        // Request the audio channel exclusively. If denied:
        // - alarm stream: Vivo/OEM may block focus even when no call is active;
        //   attempt playback anyway since USAGE_ALARM routes through the alarm
        //   audio path which bypasses ringer restrictions at a lower level.
        // - any other stream: a real call is holding focus — vibrate and give up.
        val focusGranted = audioFocus.request(attributes)
        if (!focusGranted) {
            if (streamUsage != "alarm") {
                Log.w(TAG, "Audio focus denied on non-alarm stream — vibrating instead")
                vibrateFallback()
                mainHandler.postDelayed({ stopPlaybackAndPersist() }, 3000L)
                return
            }
            Log.w(TAG, "Audio focus denied on alarm stream — attempting playback anyway")
        }

        val player = MediaPlayer()
        player.setAudioAttributes(attributes)
        player.setOnCompletionListener {
            Log.d(TAG, "Playback completed — notification persists until next prayer or dismiss")
            stopPlaybackAndPersist()
        }
        player.setOnErrorListener { _, what, extra ->
            Log.e(TAG, "MediaPlayer error what=$what extra=$extra")
            stopPlaybackAndSelf()
            true
        }

        try {
            when {
                sound.isEmpty() -> {
                    // "Beep / Default" — Dart sent sound='' (was 'DEFAULT') with soundType='none'.
                    // Play the short system notification sound to match the "Beep" UI label.
                    player.setDataSource(this, android.provider.Settings.System.DEFAULT_NOTIFICATION_URI)
                }
                soundType == "systemSound" -> {
                    // User-picked ringtone (content/file URI or absolute path).
                    val uri = parseSoundUri(sound)
                    if (uri == null) {
                        Log.w(TAG, "systemSound with empty uri — using default ringtone")
                        player.setDataSource(this, android.provider.Settings.System.DEFAULT_RINGTONE_URI)
                    } else {
                        player.setDataSource(this, uri)
                    }
                }
                else -> {
                    // customSound — look up raw resource by name in the host app.
                    val resId = resources.getIdentifier(sound, "raw", packageName)
                    if (resId == 0) {
                        Log.e(TAG, "Raw resource not found: $sound — stopping")
                        stopPlaybackAndSelf()
                        return
                    }
                    resources.openRawResourceFd(resId).use { afd ->
                        player.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                    }
                }
            }
            player.prepare()
            player.start()
            mediaPlayer = player
            Log.d(TAG, "Adhan playback started (usage=$streamUsage, sound=$sound, type=$soundType)")
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to start playback", t)
            try { player.release() } catch (_: Throwable) {}
            stopPlaybackAndSelf()
        }
    }

    private fun parseSoundUri(raw: String): Uri? {
        if (raw.isEmpty()) return null
        // Allow either a URI ("content://...", "file://...") or a bare path
        val parsed = Uri.parse(raw)
        return if (parsed.scheme.isNullOrEmpty()) Uri.parse("file://$raw") else parsed
    }

    private fun mapUsage(name: String): Int = when (name.lowercase()) {
        "ringtone"     -> AudioAttributes.USAGE_NOTIFICATION_RINGTONE
        "notification" -> AudioAttributes.USAGE_NOTIFICATION
        "media"        -> AudioAttributes.USAGE_MEDIA
        else           -> AudioAttributes.USAGE_ALARM
    }

    private fun releasePlayer() {
        mediaPlayer?.let { mp ->
            try {
                if (mp.isPlaying) mp.stop()
            } catch (_: Throwable) {}
            try { mp.release() } catch (_: Throwable) {}
        }
        mediaPlayer = null
    }

    /**
     * Full cleanup — used for explicit user actions (Stop / swipe), errors,
     * and audio focus loss. The notification is removed.
     */
    private fun stopPlaybackAndSelf() {
        mainHandler.removeCallbacksAndMessages(null)
        releasePlayer()
        audioFocus.abandon()
        cancelVibration()
        // Cancel the notification explicitly — covers the case where the service
        // had previously detached so stopForeground alone wouldn't remove it.
        getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION_ID)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    /**
     * Soft stop — used when the adhan/beep finishes naturally and when the
     * call-fallback vibration window completes. Releases audio resources but
     * leaves the notification in the tray so the user can see "the last
     * prayer fired" until the next one arrives (auto-replaced via the fixed
     * NOTIFICATION_ID) or they dismiss it manually.
     */
    private fun stopPlaybackAndPersist() {
        mainHandler.removeCallbacksAndMessages(null)
        releasePlayer()
        audioFocus.abandon()
        cancelVibration()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_DETACH)
        }
        stopSelf()
    }

    private fun vibrateFallback() {
        val v = vibrator?.takeIf { it.hasVibrator() } ?: return
        // Three short pulses — recognizable as "something deliberate" without
        // being aggressive. Tagged USAGE_ALARM so DnD doesn't suppress it.
        val pattern = longArrayOf(0, 500, 300, 500, 300, 500)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val effect = VibrationEffect.createWaveform(pattern, -1)
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            v.vibrate(effect, attrs)
        } else {
            @Suppress("DEPRECATION")
            v.vibrate(pattern, -1)
        }
    }

    private fun cancelVibration() {
        try { vibrator?.cancel() } catch (_: Throwable) {}
    }

    // endregion

    // region notification

    /**
     * Creates the channel on first use, or updates its name and description on
     * subsequent calls — Android's createNotificationChannel updates only those
     * two fields after the channel exists; importance/sound stay frozen.
     */
    private fun ensureNotificationChannel(name: String, description: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java) ?: return

        // IMPORTANCE_HIGH so the notification appears as a heads-up popup when
        // the adhan fires. setSound(null, null) keeps the channel itself silent —
        // the actual audio comes from MediaPlayer in this service, not the channel.
        val channel = NotificationChannel(
            CHANNEL_ID,
            name,
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            this.description = description
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
    }

    /**
     * Stream is audible right now if it bypasses the ringer (alarm / media) or
     * the ringer is in normal mode. Ringtone and notification streams are
     * silenced in silent or vibrate mode.
     */
    private fun isStreamAudible(streamUsage: String): Boolean = when (streamUsage.lowercase()) {
        "alarm", "media" -> true
        else -> audioManager.ringerMode == AudioManager.RINGER_MODE_NORMAL
    }

    private fun startAsForeground(
        title: String,
        body: String,
        channelName: String,
        channelDescription: String,
        stopLabel: String,
        defaultTitle: String,
        includeStopAction: Boolean,
    ) {
        ensureNotificationChannel(channelName, channelDescription)

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this, 0, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        val stopIntent = Intent(this, AdhanPlayerService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        // Fires when the user swipes the notification away — stops playback.
        val deletePendingIntent = PendingIntent.getService(
            this, 2, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(resolveSmallIcon())
            .setContentTitle(title.ifEmpty { defaultTitle })
            .setContentText(body)
            .setOngoing(true)
            // Each new play call (next prayer) should heads-up pop again, even
            // though the notification ID is reused — false here is required for
            // the persist-until-next-prayer UX. Channel sound is null, so this
            // doesn't cause repeated audible alerts.
            .setOnlyAlertOnce(false)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .apply { contentIntent?.let { setContentIntent(it) } }
            .setDeleteIntent(deletePendingIntent)
            .apply { if (includeStopAction) addAction(0, stopLabel, stopPendingIntent) }
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun resolveSmallIcon(): Int {
        val byName = resources.getIdentifier("notification_icon", "drawable", packageName)
        if (byName != 0) return byName
        return applicationInfo.icon.takeIf { it != 0 } ?: android.R.drawable.ic_lock_silent_mode_off
    }

    // endregion
}
