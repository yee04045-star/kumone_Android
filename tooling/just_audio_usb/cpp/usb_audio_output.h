/*
 * Adapted from the direct USB Audio Class design in:
 * https://github.com/Ma145/decent-player
 * MIT License, Copyright (c) 2026 Marcelo Silva. See
 * third_party/licenses/DECENT_PLAYER_MIT.txt in this repository.
 */

#pragma once

#include <atomic>
#include <cstdint>
#include <linux/usbdevice_fs.h>

#define KUMONE_USB_PACKETS_PER_URB 8
#define KUMONE_USB_NUM_URBS 64
#define KUMONE_USB_URB_BUFFER_SIZE 8192

struct KumoneUrbSlot {
    usbdevfs_urb* urb;
    uint8_t* buffer;
};

struct KumoneUsbAudioContext {
    int fd;
    int interfaceId;
    int endpointOut;
    int endpointFeedback;
    int sampleRate;
    int channelCount;
    int bitDepth;
    int bytesPerSample;
    int bytesPerFrame;
    int maxPacketSize;
    std::atomic<bool> running;
    int submitIdx;
    int reapIdx;
    int urbsInFlight;
    double frameAccumulator;
    double calibratedFpmf;
    int64_t framesWritten;
    uint8_t residualBuffer[KUMONE_USB_URB_BUFFER_SIZE];
    int residualBytes;
    KumoneUrbSlot ring[KUMONE_USB_NUM_URBS];
    usbdevfs_urb* feedbackUrb;
    uint8_t feedbackBuffer[4];
    bool feedbackInFlight;
};

void kumoneSubmitPcm(KumoneUsbAudioContext* ctx, const uint8_t* pcmData, int totalBytes);
