/*
 * Adapted from the direct USB Audio Class design in:
 * https://github.com/Ma145/decent-player
 * MIT License, Copyright (c) 2026 Marcelo Silva. See
 * third_party/licenses/DECENT_PLAYER_MIT.txt in this repository.
 */

package com.ryanheise.just_audio;

import android.content.Context;
import android.hardware.usb.UsbDevice;
import android.media.AudioDeviceInfo;
import android.media.AudioManager;
import android.util.Log;

import androidx.annotation.Nullable;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.MimeTypes;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.audio.AudioSink;
import androidx.media3.exoplayer.audio.AudioOffloadSupport;
import androidx.media3.exoplayer.audio.ForwardingAudioSink;
import androidx.media3.exoplayer.audio.DefaultAudioSink;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/**
 * Dual-engine audio sink. Normal playback stays on the existing DefaultAudioSink.
 * When USB Exclusive is enabled and a UAC device is permitted, decoded PCM is mirrored
 * to a direct usbdevfs UAC stream while the delegate AudioTrack is muted and pinned to the speaker.
 */
@UnstableApi
public final class KumoneUsbAudioSink extends ForwardingAudioSink {
    private static final String TAG = "KumoneUsbAudioSink";

    private final DefaultAudioSink delegate;
    private final Context context;
    private final AudioManager audioManager;

    private Format currentFormat;
    private KumoneUsbStream stream;
    private int streamBitDepth;
    private int streamSampleRate;
    private int streamChannels;
    private int currentEncoding = C.ENCODING_PCM_16BIT;
    private boolean directActive;
    private float pendingVolume = 1f;
    private boolean delegateMuted;
    private ByteBuffer zeroBuffer;
    private static volatile KumoneUsbAudioSink activeSink;

    public KumoneUsbAudioSink(DefaultAudioSink delegate, Context context) {
        super(delegate);
        this.delegate = delegate;
        this.context = context.getApplicationContext();
        this.audioManager = (AudioManager) this.context.getSystemService(Context.AUDIO_SERVICE);
        activeSink = this;
    }

    static void releaseActiveForExclusiveOff() {
        KumoneUsbAudioSink sink = activeSink;
        if (sink != null) sink.releaseDirect();
    }

    @Override
    public int getFormatSupport(Format format) {
        if (KumoneUsbExclusiveController.isEnabled() && format != null
                && !MimeTypes.AUDIO_RAW.equals(format.sampleMimeType)) {
            // Force Media3 to decode compressed sources to PCM instead of selecting
            // passthrough output, because only PCM can be sent through the direct UAC path.
            return AudioSink.SINK_FORMAT_UNSUPPORTED;
        }
        return super.getFormatSupport(format);
    }

    @Override
    public AudioOffloadSupport getFormatOffloadSupport(Format format) {
        if (KumoneUsbExclusiveController.isEnabled()) {
            return AudioOffloadSupport.DEFAULT_UNSUPPORTED;
        }
        return super.getFormatOffloadSupport(format);
    }

    @Override
    public void configure(Format inputFormat, int specifiedBufferSize, @Nullable int[] outputChannels)
            throws AudioSink.ConfigurationException {
        currentFormat = inputFormat;
        currentEncoding = inputFormat.pcmEncoding;

        if (directActive && !isDirectCandidate(inputFormat, outputChannels)) {
            releaseDirect();
        }

        super.configure(inputFormat, specifiedBufferSize, outputChannels);

        if (isDirectCandidate(inputFormat, outputChannels) && KumoneUsbExclusiveController.isEnabled()) {
            if (!ensureDirectStream(inputFormat)) {
                Log.w(TAG, "USB exclusive requested but direct stream could not be prepared; using normal output");
                releaseDirect();
            } else {
                muteDelegate();
                routeDelegateToSpeaker();
            }
        } else {
            releaseDirect();
        }
    }

    private boolean isDirectCandidate(Format format, @Nullable int[] outputChannels) {
        if (format == null || !MimeTypes.AUDIO_RAW.equals(format.sampleMimeType)) return false;
        if (format.channelCount <= 0 || format.channelCount > 2) return false;
        if (format.sampleRate <= 0) return false;
        if (outputChannels != null) return false;
        // Direct USB output is intentionally disabled when ExoPlayer is doing time-domain
        // transformations. That keeps the direct path source-faithful.
        if (getPlaybackParameters().speed != 1f || getPlaybackParameters().pitch != 1f) return false;
        if (getSkipSilenceEnabled()) return false;
        return format.pcmEncoding == C.ENCODING_PCM_16BIT
                || format.pcmEncoding == C.ENCODING_PCM_24BIT
                || format.pcmEncoding == C.ENCODING_PCM_32BIT
                || format.pcmEncoding == C.ENCODING_PCM_FLOAT;
    }

    private synchronized boolean ensureDirectStream(Format format) {
        if (!KumoneUsbExclusiveController.isEnabled()) return false;
        if (directActive && stream != null && stream.isRunning()
                && streamSampleRate == format.sampleRate
                && streamChannels == format.channelCount) {
            return true;
        }

        releaseDirect();

        UsbDevice device = KumoneUsbExclusiveController.findDevice(context);
        if (device == null || !KumoneUsbExclusiveController.hasPermission(context, device)) return false;

        KumoneUsbAudioDevice mgr = KumoneUsbExclusiveController.device(context);
        KumoneUsbAudioDevice.Opened opened = mgr.open(device);
        if (opened == null) return false;

        int sourceBits = inputBits(format.pcmEncoding);
        KumoneUsbAudioDevice.AltSetting selected = selectAlt(opened, sourceBits);
        if (selected == null) return false;

        if (!mgr.setAltSetting(0)) {
            Log.w(TAG, "Unable to stop existing USB alt setting");
        }
        mgr.setSampleRate(format.sampleRate);

        KumoneUsbStream newStream = new KumoneUsbStream(
                opened.fd, opened.interfaceId, opened.endpointOut, opened.endpointFeedback,
                format.sampleRate, format.channelCount, selected.bits, opened.maxPacketSize);
        if (!newStream.isReady()) {
            newStream.release();
            return false;
        }

        if (!mgr.setAltSetting(selected.alt)) {
            newStream.release();
            return false;
        }

        // Give the DAC clock/PLL a short settling period after a UAC2 rate/interface switch.
        try { Thread.sleep(30L); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }

        if (!newStream.start()) {
            newStream.release();
            return false;
        }

        stream = newStream;
        streamBitDepth = selected.bits;
        streamSampleRate = format.sampleRate;
        streamChannels = format.channelCount;
        directActive = true;
        Log.i(TAG, "Direct USB active: rate=" + streamSampleRate +
                " channels=" + streamChannels + " sourceBits=" + sourceBits +
                " usbBits=" + streamBitDepth + " device=" + device.getProductName());
        return true;
    }

    @Nullable
    private KumoneUsbAudioDevice.AltSetting selectAlt(KumoneUsbAudioDevice.Opened opened, int sourceBits) {
        KumoneUsbAudioDevice.AltSetting exact = null;
        KumoneUsbAudioDevice.AltSetting higher = null;
        for (KumoneUsbAudioDevice.AltSetting alt : opened.alts) {
            if (alt.bits == sourceBits) exact = alt;
            if (alt.bits > sourceBits && (higher == null || alt.bits < higher.bits)) higher = alt;
        }
        if (exact != null) return exact;
        if (higher != null) return higher;
        return new KumoneUsbAudioDevice.AltSetting(opened.bestAlt, opened.bestBits);
    }

    private int inputBits(int encoding) {
        if (encoding == C.ENCODING_PCM_16BIT) return 16;
        if (encoding == C.ENCODING_PCM_24BIT) return 24;
        return 32;
    }

    @Override
    public boolean handleBuffer(ByteBuffer buffer, long presentationTimeUs, int encodedAccessUnitCount)
            throws AudioSink.InitializationException, AudioSink.WriteException {
        if (!KumoneUsbExclusiveController.isEnabled() && directActive) {
            releaseDirect();
        }

        if (!directActive && KumoneUsbExclusiveController.isEnabled()
                && currentFormat != null && isDirectCandidate(currentFormat, null)) {
            if (ensureDirectStream(currentFormat)) {
                muteDelegate();
                routeDelegateToSpeaker();
            }
        }

        if (!directActive || stream == null || !stream.isRunning()) {
            releaseIfDead();
            unmuteDelegate();
            return super.handleBuffer(buffer, presentationTimeUs, encodedAccessUnitCount);
        }

        int start = buffer.position();
        int remaining = buffer.remaining();
        if (remaining == 0) return true;

        ByteBuffer zeros = zeroBuffer(remaining);
        boolean handled = delegate.handleBuffer(zeros, presentationTimeUs, encodedAccessUnitCount);
        int consumed = zeros.position();
        if (consumed > 0) {
            ByteBuffer chunk = buffer.duplicate().order(ByteOrder.LITTLE_ENDIAN);
            chunk.position(start);
            chunk.limit(start + consumed);
            writeDirect(chunk, currentEncoding);
            buffer.position(start + consumed);
        }
        return handled;
    }

    private ByteBuffer zeroBuffer(int size) {
        if (zeroBuffer == null || zeroBuffer.capacity() < size) {
            zeroBuffer = ByteBuffer.allocateDirect(size).order(ByteOrder.nativeOrder());
        }
        zeroBuffer.clear();
        zeroBuffer.limit(size);
        return zeroBuffer;
    }

    private void writeDirect(ByteBuffer source, int encoding) throws AudioSink.WriteException {
        if (stream == null || !stream.isRunning()) {
            throw new AudioSink.WriteException(-32, currentFormat, true);
        }
        ByteBuffer snapshot = source.slice().order(ByteOrder.LITTLE_ENDIAN);
        int bytes = snapshot.remaining();
        if (encoding == C.ENCODING_PCM_FLOAT) {
            int samples = bytes / 4;
            float[] values = new float[samples];
            snapshot.asFloatBuffer().get(values);
            stream.writeFloat(values);
        } else {
            int bits = inputBits(encoding);
            byte[] raw = new byte[bytes];
            snapshot.get(raw);
            stream.writeRaw(raw, bits);
        }
        if (!stream.isRunning()) {
            throw new AudioSink.WriteException(-32, currentFormat, true);
        }
    }

    private void releaseIfDead() {
        if (stream != null && !stream.isRunning()) releaseDirect();
    }

    private synchronized void releaseDirect() {
        if (stream != null) {
            try { stream.stop(); } catch (Throwable ignored) {}
            try { stream.drain(); } catch (Throwable ignored) {}
            try { stream.release(); } catch (Throwable ignored) {}
            stream = null;
        }
        directActive = false;
        KumoneUsbAudioDevice mgr = KumoneUsbExclusiveController.device(context);
        try { mgr.setAltSetting(0); } catch (Throwable ignored) {}
        try { mgr.close(); } catch (Throwable ignored) {}
        unmuteDelegate();
        clearDelegateRouting();
        if (activeSink == this) activeSink = null;
    }

    private void muteDelegate() {
        if (!delegateMuted) {
            super.setVolume(0f);
            delegateMuted = true;
        }
    }

    private void unmuteDelegate() {
        if (delegateMuted) {
            super.setVolume(pendingVolume);
            delegateMuted = false;
        }
    }

    @Override
    public void setVolume(float volume) {
        pendingVolume = volume;
        if (!directActive) {
            super.setVolume(volume);
        } else {
            super.setVolume(0f);
        }
    }

    private void routeDelegateToSpeaker() {
        try {
            if (android.os.Build.VERSION.SDK_INT < 23) return;
            AudioDeviceInfo[] devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS);
            for (AudioDeviceInfo device : devices) {
                if (device.getType() == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER) {
                    delegate.setPreferredDevice(device);
                    return;
                }
            }
        } catch (Throwable t) {
            Log.w(TAG, "route delegate speaker failed: " + t.getMessage());
        }
    }

    private void clearDelegateRouting() {
        try {
            if (android.os.Build.VERSION.SDK_INT >= 23) delegate.setPreferredDevice(null);
        } catch (Throwable ignored) {}
    }

    @Override
    public void flush() {
        if (directActive) releaseDirect();
        super.flush();
    }

    @Override
    public void reset() {
        if (directActive) releaseDirect();
        super.reset();
    }

    @Override
    public void release() {
        releaseDirect();
        super.release();
    }
}
