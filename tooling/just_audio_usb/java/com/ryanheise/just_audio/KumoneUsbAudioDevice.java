/*
 * Adapted from the direct USB Audio Class design in:
 * https://github.com/Ma145/decent-player
 * MIT License, Copyright (c) 2026 Marcelo Silva. See
 * third_party/licenses/DECENT_PLAYER_MIT.txt in this repository.
 */

package com.ryanheise.just_audio;

import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.hardware.usb.UsbConstants;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbDeviceConnection;
import android.hardware.usb.UsbInterface;
import android.hardware.usb.UsbManager;
import android.os.Build;
import android.util.Log;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** Small Java-side UAC device manager derived from the direct-usb design used by DecentPlayer. */
final class KumoneUsbAudioDevice {
    private static final String TAG = "KumoneUsbDevice";
    private static final String PERMISSION_ACTION_SUFFIX = ".KUMONE_USB_PERMISSION";

    static final class AltSetting {
        final int alt;
        final int bits;
        AltSetting(int alt, int bits) { this.alt = alt; this.bits = bits; }
    }

    static final class Opened {
        final UsbDeviceConnection connection;
        final int fd;
        final int interfaceId;
        final int endpointOut;
        final int endpointFeedback;
        final int maxPacketSize;
        final int clockSourceId;
        final int bestAlt;
        final int bestBits;
        final List<AltSetting> alts;

        Opened(
                UsbDeviceConnection connection,
                int fd,
                int interfaceId,
                int endpointOut,
                int endpointFeedback,
                int maxPacketSize,
                int clockSourceId,
                int bestAlt,
                int bestBits,
                List<AltSetting> alts) {
            this.connection = connection;
            this.fd = fd;
            this.interfaceId = interfaceId;
            this.endpointOut = endpointOut;
            this.endpointFeedback = endpointFeedback;
            this.maxPacketSize = maxPacketSize;
            this.clockSourceId = clockSourceId;
            this.bestAlt = bestAlt;
            this.bestBits = bestBits;
            this.alts = alts;
        }
    }

    interface PermissionCallback { void onResult(boolean granted); }

    private final Context context;
    private final UsbManager usbManager;
    private UsbDeviceConnection connection;
    private UsbDevice currentDevice;
    private UsbInterface claimedInterface;
    private Opened cached;

    KumoneUsbAudioDevice(Context context) {
        this.context = context.getApplicationContext();
        this.usbManager = (UsbManager) this.context.getSystemService(Context.USB_SERVICE);
    }

    UsbDevice findAudioDevice() {
        if (usbManager == null) return null;
        for (UsbDevice device : usbManager.getDeviceList().values()) {
            for (int i = 0; i < device.getInterfaceCount(); i++) {
                UsbInterface iface = device.getInterface(i);
                if (iface.getInterfaceClass() == UsbConstants.USB_CLASS_AUDIO &&
                        iface.getInterfaceSubclass() == 2) {
                    Log.i(TAG, "USB audio device: " + device.getProductName() +
                            " vid=0x" + Integer.toHexString(device.getVendorId()) +
                            " pid=0x" + Integer.toHexString(device.getProductId()));
                    return device;
                }
            }
        }
        return null;
    }

    boolean hasPermission(UsbDevice device) {
        return device != null && usbManager != null && usbManager.hasPermission(device);
    }

    void requestPermission(UsbDevice device, PermissionCallback callback) {
        if (device == null || usbManager == null) { callback.onResult(false); return; }
        if (usbManager.hasPermission(device)) { callback.onResult(true); return; }

        final String action = context.getPackageName() + PERMISSION_ACTION_SUFFIX;
        Intent intent = new Intent(action).setPackage(context.getPackageName());
        PendingIntent pendingIntent = PendingIntent.getBroadcast(
                context, 2719, intent, PendingIntent.FLAG_MUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);

        BroadcastReceiver receiver = new BroadcastReceiver() {
            @Override public void onReceive(Context ctx, Intent received) {
                if (!action.equals(received.getAction())) return;
                try { context.unregisterReceiver(this); } catch (Throwable ignored) {}
                boolean granted = received.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false);
                callback.onResult(granted);
            }
        };

        IntentFilter filter = new IntentFilter(action);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            context.registerReceiver(receiver, filter);
        }
        usbManager.requestPermission(device, pendingIntent);
    }

    synchronized Opened open(UsbDevice device) {
        if (cached != null && connection != null) return cached;
        close();
        if (device == null || !usbManager.hasPermission(device)) return null;
        UsbDeviceConnection conn = usbManager.openDevice(device);
        if (conn == null) return null;

        UsbInterface streaming = null;
        int endpointOut = -1;
        int endpointFeedback = -1;
        int maxPacket = 0;
        int streamingInterfaceId = -1;

        for (int i = 0; i < device.getInterfaceCount(); i++) {
            UsbInterface iface = device.getInterface(i);
            if (iface.getInterfaceClass() != UsbConstants.USB_CLASS_AUDIO || iface.getInterfaceSubclass() != 2) continue;
            if (iface.getEndpointCount() == 0 || streaming != null) continue;
            for (int e = 0; e < iface.getEndpointCount(); e++) {
                android.hardware.usb.UsbEndpoint ep = iface.getEndpoint(e);
                if (ep.getType() == UsbConstants.USB_ENDPOINT_XFER_ISOC &&
                        ep.getDirection() == UsbConstants.USB_DIR_OUT) {
                    streaming = iface;
                    streamingInterfaceId = iface.getId();
                    endpointOut = ep.getAddress();
                    maxPacket = ep.getMaxPacketSize();
                } else if (ep.getType() == UsbConstants.USB_ENDPOINT_XFER_ISOC &&
                        ep.getDirection() == UsbConstants.USB_DIR_IN) {
                    endpointFeedback = ep.getAddress();
                }
            }
        }
        if (streaming == null || endpointOut < 0) { conn.close(); return null; }

        UsbInterface control = null;
        for (int i = 0; i < device.getInterfaceCount(); i++) {
            UsbInterface iface = device.getInterface(i);
            if (iface.getInterfaceClass() == UsbConstants.USB_CLASS_AUDIO && iface.getInterfaceSubclass() == 1) {
                control = iface; break;
            }
        }
        if (control != null) conn.claimInterface(control, true);
        if (!conn.claimInterface(streaming, true)) { conn.close(); return null; }
        claimedInterface = streaming;

        int zeroAltInterfaceId = -1;
        UsbInterface zeroAlt = null;
        for (int i = 0; i < device.getInterfaceCount(); i++) {
            UsbInterface iface = device.getInterface(i);
            if (iface.getInterfaceClass() == UsbConstants.USB_CLASS_AUDIO &&
                    iface.getInterfaceSubclass() == 2 && iface.getAlternateSetting() == 0) {
                zeroAlt = iface; zeroAltInterfaceId = iface.getId(); break;
            }
        }
        if (zeroAlt != null) conn.setInterface(zeroAlt);

        int clockSourceId = parseClockSourceId(conn);
        List<AltSetting> alts = parseAltSettings(conn);
        AltSetting best = alts.stream().max(Comparator.comparingInt(a -> a.bits)).orElse(new AltSetting(1, 16));
        cached = new Opened(conn, conn.getFileDescriptor(), streamingInterfaceId, endpointOut,
                endpointFeedback, maxPacket, clockSourceId, best.alt, best.bits, alts);
        connection = conn;
        currentDevice = device;
        Log.i(TAG, "Opened USB: " + device.getProductName() + " fd=" + cached.fd +
                " iface=" + cached.interfaceId + " epOut=0x" + Integer.toHexString(cached.endpointOut) +
                " epFb=0x" + Integer.toHexString(cached.endpointFeedback) + " best=" + cached.bestBits + "bit");
        return cached;
    }

    synchronized AltSetting findAltForBits(int bits) {
        if (cached == null || cached.alts.isEmpty()) return new AltSetting(1, 16);
        AltSetting exact = null;
        AltSetting higher = null;
        for (AltSetting alt : cached.alts) {
            if (alt.bits == bits) exact = alt;
            if (alt.bits > bits && (higher == null || alt.bits < higher.bits)) higher = alt;
        }
        if (exact != null) return exact;
        if (higher != null) return higher;
        return cached.alts.stream().max(Comparator.comparingInt(a -> a.bits)).orElse(new AltSetting(1, 16));
    }

    synchronized boolean setAltSetting(int altSetting) {
        if (connection == null || currentDevice == null) return false;
        for (int i = 0; i < currentDevice.getInterfaceCount(); i++) {
            UsbInterface iface = currentDevice.getInterface(i);
            if (iface.getInterfaceClass() == UsbConstants.USB_CLASS_AUDIO &&
                    iface.getInterfaceSubclass() == 2 && iface.getAlternateSetting() == altSetting) {
                return connection.setInterface(iface);
            }
        }
        return false;
    }

    synchronized boolean setSampleRate(int sampleRate) {
        if (connection == null || cached == null) return false;
        int csId = cached.clockSourceId;
        if (csId <= 0) return false;
        byte[] data = new byte[] {
                (byte)(sampleRate & 0xff), (byte)((sampleRate >>> 8) & 0xff),
                (byte)((sampleRate >>> 16) & 0xff), (byte)((sampleRate >>> 24) & 0xff)
        };
        int ret = connection.controlTransfer(0x21, 0x01, 0x0100, csId << 8, data, 4, 1000);
        if (ret >= 0) return true;
        // Some UAC2 devices expose clock controls on a different entity. Leave the stream active
        // and let the DAC follow the selected alternate setting if it supports auto rate detection.
        return false;
    }

    synchronized int getBestBits() { return cached != null ? cached.bestBits : 16; }
    synchronized int getBestAlt() { return cached != null ? cached.bestAlt : 1; }
    synchronized int getFd() { return cached != null ? cached.fd : -1; }
    synchronized int getInterfaceId() { return cached != null ? cached.interfaceId : -1; }
    synchronized int getEndpointOut() { return cached != null ? cached.endpointOut : -1; }
    synchronized int getEndpointFeedback() { return cached != null ? cached.endpointFeedback : -1; }
    synchronized int getMaxPacketSize() { return cached != null ? cached.maxPacketSize : 0; }

    synchronized void close() {
        if (connection != null && claimedInterface != null) {
            try { connection.releaseInterface(claimedInterface); } catch (Throwable ignored) {}
        }
        claimedInterface = null;
        if (connection != null) {
            try { connection.close(); } catch (Throwable ignored) {}
        }
        connection = null;
        currentDevice = null;
        cached = null;
    }

    private int parseClockSourceId(UsbDeviceConnection conn) {
        byte[] raw = conn.getRawDescriptors();
        if (raw == null) return -1;
        boolean inControl = false;
        for (int i = 0; i + 1 < raw.length;) {
            int len = raw[i] & 0xff;
            if (len < 2 || i + len > raw.length) break;
            int type = raw[i + 1] & 0xff;
            if (type == 0x04 && len >= 9) {
                int cls = raw[i + 5] & 0xff;
                int sub = raw[i + 6] & 0xff;
                inControl = cls == 1 && sub == 1;
            } else if (inControl && type == 0x24 && len >= 5 && (raw[i + 2] & 0xff) == 0x0a) {
                return raw[i + 3] & 0xff;
            }
            i += len;
        }
        return -1;
    }

    private List<AltSetting> parseAltSettings(UsbDeviceConnection conn) {
        byte[] raw = conn.getRawDescriptors();
        List<AltSetting> result = new ArrayList<>();
        if (raw == null) return result;
        boolean inStreaming = false;
        int currentAlt = 0;
        for (int i = 0; i + 1 < raw.length;) {
            int len = raw[i] & 0xff;
            if (len < 2 || i + len > raw.length) break;
            int type = raw[i + 1] & 0xff;
            if (type == 0x04 && len >= 9) {
                int cls = raw[i + 5] & 0xff;
                int sub = raw[i + 6] & 0xff;
                currentAlt = raw[i + 3] & 0xff;
                inStreaming = cls == 1 && sub == 2;
            } else if (inStreaming && type == 0x24 && len >= 6 && (raw[i + 2] & 0xff) == 0x02) {
                int subslot = raw[i + 4] & 0xff;
                int bits = raw[i + 5] & 0xff;
                if (currentAlt > 0 && subslot > 0 && bits > 0) result.add(new AltSetting(currentAlt, bits));
            }
            i += len;
        }
        return result;
    }
}
