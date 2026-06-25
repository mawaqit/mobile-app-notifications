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
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import android.view.KeyEvent
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
        // Live-adjust the override level on the currently-playing preview stream
        // without restarting playback (driven by the in-app volume slider).
        const val ACTION_SET_PREVIEW_VOLUME = "com.mawaqit.notifications.ACTION_SET_PREVIEW_VOLUME"

        const val EXTRA_SOUND = "sound"            // raw resource name OR file path / URI
        const val EXTRA_SOUND_TYPE = "soundType"   // "customSound" | "systemSound"
        const val EXTRA_STREAM_USAGE = "streamUsage" // "alarm" | "ringtone" | "notification" | "media"
        const val EXTRA_VOLUME_ENABLED = "customVolumeEnabled" // per-prayer volume override on/off
        const val EXTRA_VOLUME = "adhanVolume"      // 0..100 percent, applied when enabled
        // When true, this playback is the in-app settings preview: it skips the
        // foreground notification (so it doesn't persist) but uses the exact same
        // stream resolution + volume override + restore as a real adhan. The host
        // stops it on sheet-close / app-background.
        const val EXTRA_PREVIEW_MODE = "previewMode"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"

        // Floor so the in-app slider can never fully mute the adhan.
        private const val MIN_VOLUME_PERCENT = 10
        private const val MAX_VOLUME_PERCENT = 100

        // Pending-restore sentinel: written before we override the system stream
        // volume so a process death mid-adhan can be healed on the next start.
        private const val PREFS_NAME = "mawaqit_adhan_player"
        private const val KEY_RESTORE_STREAM = "pending_restore_stream"
        private const val KEY_RESTORE_VOLUME = "pending_restore_volume"

        // i18n strings — Flutter is the source of truth for translation; native
        // strings here are defensive English fallbacks only.
        const val EXTRA_CHANNEL_NAME = "channelName"
        const val EXTRA_CHANNEL_DESCRIPTION = "channelDescription"
        const val EXTRA_STOP_LABEL = "stopLabel"
        const val EXTRA_DEFAULT_TITLE = "defaultTitle"
    }

    private var mediaPlayer: MediaPlayer? = null

    // The stream whose volume the current playback overrode, so the preview can
    // live-adjust it (ACTION_SET_PREVIEW_VOLUME) without restarting playback.
    private var activeOverrideStream: Int? = null

    private val audioManager: AudioManager by lazy {
        getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }

    private val powerManager: PowerManager by lazy {
        getSystemService(Context.POWER_SERVICE) as PowerManager
    }

    // Held for the whole onStartCommand → playback span so the CPU can't suspend
    // mid-setup in Doze. The alarm's wake-from-idle window is short; MediaPlayer
    // .setWakeMode alone is insufficient because its internal lock only engages
    // at start(), but the CPU can suspend BEFORE start() is even reached — which
    // is why the notification posts on time yet audio doesn't render until the
    // next device wake. Acquiring our own lock first closes that gap.
    private var wakeLock: PowerManager.WakeLock? = null

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
            ACTION_SET_PREVIEW_VOLUME -> {
                // Live slider adjustment during a preview — re-apply the level to
                // the stream the current playback already overrode. Must NOT run
                // the restore self-heal, or it would undo the active override.
                val volumePercent = intent.getIntExtra(EXTRA_VOLUME, MAX_VOLUME_PERCENT)
                setActiveStreamVolume(volumePercent)
                return START_NOT_STICKY
            }
            ACTION_PLAY, null -> {
                // Keep the CPU awake through setup AND playback so a Doze-fired
                // alarm renders audio immediately rather than when the device next
                // wakes. Acquired here, before anything else, to close the gap
                // ahead of MediaPlayer.start().
                acquireWakeLock()

                // Self-heal: restore any override left behind by a previous
                // playback whose process was killed before it could restore (and
                // reset before this new play captures a fresh original). Idempotent
                // no-op when there's nothing pending.
                restoreVolumeIfNeeded()

                val sound = intent?.getStringExtra(EXTRA_SOUND).orEmpty()
                val soundType = intent?.getStringExtra(EXTRA_SOUND_TYPE) ?: "customSound"
                val streamUsage = intent?.getStringExtra(EXTRA_STREAM_USAGE) ?: "alarm"
                val volumeEnabled = intent?.getBooleanExtra(EXTRA_VOLUME_ENABLED, false) ?: false
                val volumePercent = intent?.getIntExtra(EXTRA_VOLUME, MAX_VOLUME_PERCENT) ?: MAX_VOLUME_PERCENT
                val previewMode = intent?.getBooleanExtra(EXTRA_PREVIEW_MODE, false) ?: false
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

                // Preview mode skips the foreground notification entirely — it's a
                // transient, in-app, lifecycle-bound preview rather than a real
                // adhan that must persist in the tray.
                if (!previewMode) {
                    startAsForeground(
                        title, body, channelName, channelDescription, stopLabel, defaultTitle,
                        includeStopAction = audible,
                    )
                }

                if (audible) {
                    startPlayback(sound, soundType, streamUsage, volumeEnabled, volumePercent)
                } else if (previewMode) {
                    // Nothing to play (muted) and no notification to show — just stop.
                    stopPlaybackAndSelf()
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
        // Final safety net — guarantees the device volume is never left at the
        // adhan override level, and the wake lock never leaks, if the service is
        // torn down by any path that didn't already clean up.
        restoreVolumeIfNeeded()
        releaseWakeLock()
        super.onDestroy()
    }

    // region playback

    private fun startPlayback(
        sound: String,
        soundType: String,
        streamUsage: String,
        volumeEnabled: Boolean,
        volumePercent: Int,
    ) {
        releasePlayer()

        // True for any app driving the music stream — covers video players
        // (MX Player, YouTube, VLC) and audio apps alike. Treat it as
        // "media is actively playing right now."
        val mediaActive = audioManager.isMusicActive

        // Best-effort: dispatch a global MEDIA_PAUSE so MediaSession-aware
        // players pause without relying on focus arbitration. Many video
        // apps ignore audio-focus changes but honor media key events.
        if (mediaActive) {
            audioManager.dispatchMediaKeyEvent(
                KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PAUSE)
            )
            audioManager.dispatchMediaKeyEvent(
                KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_MEDIA_PAUSE)
            )
        }

        // Decouple focus arbitration from playback routing when media is
        // active:
        //   - focusAttributes masquerades as a media app (USAGE_MEDIA +
        //     CONTENT_TYPE_MUSIC) so other media apps reliably fire their
        //     OnAudioFocusChange path. Most third-party players only listen
        //     for media-stream focus loss; a USAGE_ALARM focus request leaves
        //     them playing.
        //   - playbackAttributes stays USAGE_ALARM + SONIFICATION so the
        //     adhan routes through the alarm stream (bypasses ringer/DnD,
        //     uses the alarm volume slider the user controls for adhan).
        // When no media is active, request and play with the Dart-resolved
        // usage (ringtone or alarm per user prefs + ringer mode).
        val playbackAttributes: AudioAttributes
        val focusAttributes: AudioAttributes
        if (mediaActive) {
            playbackAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            focusAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
        } else {
            val attrs = AudioAttributes.Builder()
                .setUsage(mapUsage(streamUsage))
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            playbackAttributes = attrs
            focusAttributes = attrs
        }

        // Fall back to vibrate only when a real call is active
        // (AudioManager.mode). Any other denial — OEM background policy,
        // media app refusing to release — proceeds with playback; focus is
        // cooperative coordination, MediaPlayer doesn't require it to
        // produce sound.
        val focusGranted = audioFocus.request(focusAttributes)
        if (!focusGranted) {
            val callActive = audioManager.mode == AudioManager.MODE_IN_CALL ||
                audioManager.mode == AudioManager.MODE_IN_COMMUNICATION
            if (callActive) {
                Log.w(TAG, "Focus denied with call active (mode=${audioManager.mode}) — vibrating instead")
                vibrateFallback()
                mainHandler.postDelayed({ stopPlaybackAndPersist() }, 3000L)
                return
            }
            Log.w(TAG, "Focus denied (no call, mediaActive=$mediaActive) — playing anyway")
        }

        val player = MediaPlayer()
        // Secondary wake lock for the playback itself. The PRIMARY guard is the
        // service-held wake lock acquired at the top of onStartCommand — that is
        // what keeps the CPU awake through setup so start() is reached at all in
        // Doze. setWakeMode only engages at start() (too late to bridge the gap),
        // but is kept here as defence in depth for the playback span.
        player.setWakeMode(applicationContext, PowerManager.PARTIAL_WAKE_LOCK)
        player.setAudioAttributes(playbackAttributes)
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
            // Apply the per-prayer volume override just before start(), targeting
            // the stream the player ACTUALLY routes to. When media is active the
            // playback attributes are forced to USAGE_ALARM (see above), so the
            // override must hit STREAM_ALARM regardless of the requested usage —
            // otherwise we'd change the wrong stream's volume.
            if (volumeEnabled) {
                val effectiveUsage =
                    if (mediaActive) AudioAttributes.USAGE_ALARM else mapUsage(streamUsage)
                applyVolumeOverride(streamForUsage(effectiveUsage), volumePercent)
            }
            player.start()
            mediaPlayer = player
            val playbackUsageLog = if (mediaActive) "alarm" else streamUsage
            val focusUsageLog = if (mediaActive) "media" else streamUsage
            Log.d(TAG, "Adhan playback started (playback=$playbackUsageLog, focus=$focusUsageLog, requested=$streamUsage, mediaActive=$mediaActive, sound=$sound, type=$soundType)")
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

    /** The AudioManager stream that a given playback usage routes its volume to. */
    private fun streamForUsage(usage: Int): Int = when (usage) {
        AudioAttributes.USAGE_ALARM                 -> AudioManager.STREAM_ALARM
        AudioAttributes.USAGE_NOTIFICATION_RINGTONE -> AudioManager.STREAM_RING
        AudioAttributes.USAGE_NOTIFICATION          -> AudioManager.STREAM_NOTIFICATION
        AudioAttributes.USAGE_MEDIA                 -> AudioManager.STREAM_MUSIC
        else                                        -> AudioManager.STREAM_ALARM
    }

    /**
     * Temporarily set [stream]'s volume to [volumePercent] (floored at
     * MIN_VOLUME_PERCENT). The pre-override level is saved to a persistent
     * sentinel BEFORE the change so it survives process death; the sentinel is
     * only written once per override cycle so back-to-back prayers don't capture
     * an already-overridden value as the "original" to restore to.
     */
    private fun applyVolumeOverride(stream: Int, volumePercent: Int) {
        try {
            val max = audioManager.getStreamMaxVolume(stream)
            if (max <= 0) return
            val pct = volumePercent.coerceIn(MIN_VOLUME_PERCENT, MAX_VOLUME_PERCENT)
            val target = Math.round(pct / 100f * max).coerceIn(1, max)
            val original = audioManager.getStreamVolume(stream)

            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            if (!prefs.contains(KEY_RESTORE_STREAM)) {
                prefs.edit()
                    .putInt(KEY_RESTORE_STREAM, stream)
                    .putInt(KEY_RESTORE_VOLUME, original)
                    .apply()
            }
            audioManager.setStreamVolume(stream, target, 0) // flag 0 = no volume UI
            activeOverrideStream = stream
            Log.d(TAG, "Volume override: stream=$stream original=$original target=$target pct=$pct")
        } catch (t: Throwable) {
            Log.w(TAG, "Failed to apply volume override", t)
        }
    }

    /**
     * Re-apply [volumePercent] to the stream the current playback already
     * overrode, without touching the saved original (so restore still returns to
     * the pre-preview level). Used for live slider adjustment during a preview.
     */
    private fun setActiveStreamVolume(volumePercent: Int) {
        val stream = activeOverrideStream ?: return
        try {
            val max = audioManager.getStreamMaxVolume(stream)
            if (max <= 0) return
            val pct = volumePercent.coerceIn(MIN_VOLUME_PERCENT, MAX_VOLUME_PERCENT)
            val target = Math.round(pct / 100f * max).coerceIn(1, max)
            audioManager.setStreamVolume(stream, target, 0)
        } catch (t: Throwable) {
            Log.w(TAG, "Failed to set active stream volume", t)
        }
    }

    /** Restore the system stream volume saved by [applyVolumeOverride], if any. */
    private fun restoreVolumeIfNeeded() {
        activeOverrideStream = null
        try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            if (!prefs.contains(KEY_RESTORE_STREAM)) return
            val stream = prefs.getInt(KEY_RESTORE_STREAM, -1)
            val original = prefs.getInt(KEY_RESTORE_VOLUME, -1)
            prefs.edit().remove(KEY_RESTORE_STREAM).remove(KEY_RESTORE_VOLUME).apply()
            if (stream >= 0 && original >= 0) {
                audioManager.setStreamVolume(stream, original, 0)
                Log.d(TAG, "Volume restored: stream=$stream original=$original")
            }
        } catch (t: Throwable) {
            Log.w(TAG, "Failed to restore volume", t)
        }
    }

    /**
     * Acquire a partial wake lock with a generous safety timeout (far longer
     * than any adhan) so a missed release can never leak it. Reference counting
     * is off so repeated acquires are idempotent.
     */
    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        try {
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "mawaqit:adhan_playback",
            ).apply {
                setReferenceCounted(false)
                acquire(10 * 60 * 1000L) // 10-min hard cap; adhan is far shorter
            }
            Log.d(TAG, "Wake lock acquired")
        } catch (t: Throwable) {
            Log.w(TAG, "Failed to acquire wake lock", t)
        }
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Throwable) {}
        wakeLock = null
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
        restoreVolumeIfNeeded()
        releaseWakeLock()
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
        restoreVolumeIfNeeded()
        releaseWakeLock()
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
