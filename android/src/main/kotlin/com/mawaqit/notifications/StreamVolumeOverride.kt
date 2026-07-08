package com.mawaqit.notifications

import android.content.Context
import android.media.AudioManager
import android.util.Log

/**
 * Temporarily overrides a single audio stream's volume for the per-prayer adhan
 * level, then restores the pre-override level afterwards.
 *
 * The original level is persisted to SharedPreferences BEFORE each change, so a
 * process death mid-adhan can be healed on the next start by calling [restore]
 * (the sentinel survives the process, the in-memory [activeStream] does not).
 *
 * Not thread-safe: all calls are expected on the service's main thread.
 */
internal class StreamVolumeOverride(context: Context) {

    private val audioManager =
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val prefs =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    // The stream whose volume the current playback overrode, so a preview can
    // live-adjust it ([setLevel]) without restarting playback. Null when no
    // override is active in THIS process (note: a sentinel may still be pending
    // from a previous, killed process — that's what [restore] heals).
    var activeStream: Int? = null
        private set

    /**
     * Temporarily set [stream]'s volume to [volumePercent] (floored at
     * [MIN_VOLUME_PERCENT]). The pre-override level is saved to a persistent
     * sentinel BEFORE the change so it survives process death; the sentinel is
     * only written once per override cycle so back-to-back prayers don't capture
     * an already-overridden value as the "original" to restore to.
     */
    fun apply(stream: Int, volumePercent: Int) {
        try {
            val max = audioManager.getStreamMaxVolume(stream)
            if (max <= 0) return
            val pct = volumePercent.coerceIn(MIN_VOLUME_PERCENT, MAX_VOLUME_PERCENT)
            val target = Math.round(pct / 100f * max).coerceIn(1, max)
            val original = audioManager.getStreamVolume(stream)

            if (!prefs.contains(KEY_RESTORE_STREAM)) {
                prefs.edit()
                    .putInt(KEY_RESTORE_STREAM, stream)
                    .putInt(KEY_RESTORE_VOLUME, original)
                    .apply()
            }
            audioManager.setStreamVolume(stream, target, 0) // flag 0 = no volume UI
            activeStream = stream
            Log.d(TAG, "Volume override: stream=$stream original=$original target=$target pct=$pct")
        } catch (t: Throwable) {
            Log.w(TAG, "Failed to apply volume override", t)
        }
    }

    /**
     * Re-apply [volumePercent] to the stream the current playback already
     * overrode, without touching the saved original (so [restore] still returns
     * to the pre-preview level). Used for live slider adjustment during a preview.
     */
    fun setLevel(volumePercent: Int) {
        val stream = activeStream ?: return
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

    /** Restore the system stream volume saved by [apply], if any. */
    fun restore() {
        activeStream = null
        try {
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

    companion object {
        private const val TAG = "StreamVolumeOverride"

        // Floor so the in-app slider can never fully mute the adhan.
        const val MIN_VOLUME_PERCENT = 10
        const val MAX_VOLUME_PERCENT = 100

        // Pending-restore sentinel: written before we override the system stream
        // volume so a process death mid-adhan can be healed on the next start.
        private const val PREFS_NAME = "mawaqit_adhan_player"
        private const val KEY_RESTORE_STREAM = "pending_restore_stream"
        private const val KEY_RESTORE_VOLUME = "pending_restore_volume"
    }
}
