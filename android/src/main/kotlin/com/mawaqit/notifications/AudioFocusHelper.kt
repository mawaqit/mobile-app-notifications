package com.mawaqit.notifications

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.util.Log

/**
 * Wraps Android's audio focus API so callers don't deal with the API 26+
 * `AudioFocusRequest` split or with raw listener wiring.
 *
 * Holds the request + listener, invokes [onFocusLost] when something more
 * important takes the audio channel (most commonly a phone call).
 */
internal class AudioFocusHelper(
    context: Context,
    private val handler: Handler,
    private val onFocusLost: () -> Unit,
) {
    private val audioManager: AudioManager =
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    // API 26+ only. Guarded by SDK_INT checks at every access site, so it
    // stays null and the AudioFocusRequest class never loads pre-O.
    private var focusRequest: AudioFocusRequest? = null

    private val listener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        when (focusChange) {
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                Log.d(TAG, "Audio focus lost ($focusChange)")
                onFocusLost()
            }
        }
    }

    /**
     * Requests `AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE` with the given attributes.
     * Returns true when granted; false when denied (e.g. phone call active).
     */
    fun request(attributes: AudioAttributes): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                .setAudioAttributes(attributes)
                .setOnAudioFocusChangeListener(listener, handler)
                .setAcceptsDelayedFocusGain(false)
                .build()
            focusRequest = request
            audioManager.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        } else {
            @Suppress("DEPRECATION")
            val result = audioManager.requestAudioFocus(
                listener,
                AudioManager.STREAM_ALARM,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE,
            )
            result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
    }

    fun abandon() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
            focusRequest = null
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(listener)
        }
    }

    private companion object {
        private const val TAG = "AudioFocusHelper"
    }
}
