/*
 * Adapted from the direct USB Audio Class design in:
 * https://github.com/Ma145/decent-player
 * MIT License, Copyright (c) 2026 Marcelo Silva. See
 * third_party/licenses/DECENT_PLAYER_MIT.txt in this repository.
 */

package com.ryanheise.just_audio;

import android.content.Context;
import android.hardware.usb.UsbDevice;
import android.util.Log;

/** Global switch/state shared by MainActivity and just_audio's Android audio sink. */
public final class KumoneUsbExclusiveController {
    private static final String TAG = "KumoneUsbExclusive";
    private static volatile boolean enabled;
    private static KumoneUsbAudioDevice deviceManager;

    public interface PermissionCallback {
        void onResult(boolean granted);
    }

    private KumoneUsbExclusiveController() {}

    public static synchronized void setEnabled(Context context, boolean value) {
        if (deviceManager == null) deviceManager = new KumoneUsbAudioDevice(context);
        enabled = value;
        Log.i(TAG, "exclusive USB " + (value ? "enabled" : "disabled"));
    }

    public static synchronized void disable(Context context) {
        enabled = false;
        KumoneUsbAudioSink.releaseActiveForExclusiveOff();
        if (deviceManager != null) deviceManager.close();
        Log.i(TAG, "exclusive USB disabled and device released");
    }

    public static boolean isEnabled() {
        return enabled;
    }

    public static synchronized UsbDevice findDevice(Context context) {
        if (deviceManager == null) deviceManager = new KumoneUsbAudioDevice(context);
        return deviceManager.findAudioDevice();
    }

    public static synchronized boolean hasPermission(Context context, UsbDevice device) {
        if (deviceManager == null) deviceManager = new KumoneUsbAudioDevice(context);
        return deviceManager.hasPermission(device);
    }

    public static synchronized void requestPermission(
            Context context, UsbDevice device, final PermissionCallback callback) {
        if (deviceManager == null) deviceManager = new KumoneUsbAudioDevice(context);
        deviceManager.requestPermission(device, new KumoneUsbAudioDevice.PermissionCallback() {
            @Override public void onResult(boolean granted) {
                callback.onResult(granted);
            }
        });
    }

    static synchronized KumoneUsbAudioDevice device(Context context) {
        if (deviceManager == null) deviceManager = new KumoneUsbAudioDevice(context);
        return deviceManager;
    }
}
