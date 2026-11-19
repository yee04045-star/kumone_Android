/*
 * Adapted from the direct USB Audio Class design in:
 * https://github.com/Ma145/decent-player
 * MIT License, Copyright (c) 2026 Marcelo Silva. See
 * third_party/licenses/DECENT_PLAYER_MIT.txt in this repository.
 */

package com.ryanheise.just_audio;

import android.util.Log;

/** Direct USB Audio Class streaming bridge used by the optional USB-exclusive path. */
public final class KumoneUsbStream {
    private static final String TAG = "KumoneUsbStream";
    private long nativeHandle;

    public KumoneUsbStream(
            int fd,
            int interfaceId,
            int endpointOut,
            int endpointFeedback,
            int sampleRate,
            int channelCount,
            int bitDepth,
            int maxPacketSize) {
        nativeHandle = nativeCreate(
                fd, interfaceId, endpointOut, endpointFeedback,
                sampleRate, channelCount, bitDepth, maxPacketSize);
        if (nativeHandle == 0L) {
            Log.e(TAG, "Failed to create native USB audio stream");
        }
    }

    public boolean isReady() {
        return nativeHandle != 0L;
    }

    public boolean isRunning() {
        return nativeHandle != 0L && nativeIsRunning(nativeHandle);
    }

    public boolean start() {
        return nativeHandle != 0L && nativeStart(nativeHandle);
    }

    public void stop() {
        if (nativeHandle != 0L) nativeStop(nativeHandle);
    }

    public void flush() {
        if (nativeHandle != 0L) nativeFlush(nativeHandle);
    }

    public int drain() {
        return nativeHandle != 0L ? nativeDrain(nativeHandle) : 0;
    }

    public void writeRaw(byte[] pcm, int inputBitDepth) {
        if (nativeHandle != 0L && pcm != null && pcm.length > 0) {
            nativeWriteRaw(nativeHandle, pcm, inputBitDepth);
        }
    }

    public void writeFloat(float[] pcm) {
        if (nativeHandle != 0L && pcm != null && pcm.length > 0) {
            nativeWriteFloat(nativeHandle, pcm);
        }
    }

    public long getFramesWritten() {
        return nativeHandle != 0L ? nativeGetFramesWritten(nativeHandle) : 0L;
    }

    public void release() {
        if (nativeHandle != 0L) {
            nativeDestroy(nativeHandle);
            nativeHandle = 0L;
        }
    }

    private static native long nativeCreate(
            int fd,
            int interfaceId,
            int endpointOut,
            int endpointFeedback,
            int sampleRate,
            int channelCount,
            int bitDepth,
            int maxPacketSize);
    private static native boolean nativeStart(long handle);
    private static native void nativeStop(long handle);
    private static native void nativeFlush(long handle);
    private static native int nativeDrain(long handle);
    private static native void nativeDestroy(long handle);
    private static native boolean nativeIsRunning(long handle);
    private static native long nativeGetFramesWritten(long handle);
    private static native void nativeWriteRaw(long handle, byte[] pcm, int inputBitDepth);
    private static native void nativeWriteFloat(long handle, float[] pcm);

    static {
        System.loadLibrary("kumone_usb_audio");
    }
}
