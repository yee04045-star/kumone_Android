/*
 * Adapted from the direct USB Audio Class design in:
 * https://github.com/Ma145/decent-player
 * MIT License, Copyright (c) 2026 Marcelo Silva. See
 * third_party/licenses/DECENT_PLAYER_MIT.txt in this repository.
 */

#include "usb_audio_output.h"

#include <jni.h>
#include <android/log.h>
#include <cerrno>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <new>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/usbdevice_fs.h>

#ifndef USBDEVFS_URB_ISO_ASAP
#define USBDEVFS_URB_ISO_ASAP 0x02
#endif

#define TAG "KumoneUsbAudio"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

static inline float clampf(float v) {
    return v > 1.0f ? 1.0f : (v < -1.0f ? -1.0f : v);
}

static void convertFloatToInt16(const float* src, uint8_t* dst, int n) {
    auto* out = reinterpret_cast<int16_t*>(dst);
    for (int i = 0; i < n; ++i) {
        double s = static_cast<double>(clampf(src[i])) * 32768.0;
        if (s > 32767.0) s = 32767.0;
        if (s < -32768.0) s = -32768.0;
        out[i] = static_cast<int16_t>(s);
    }
}

static void convertFloatToInt24(const float* src, uint8_t* dst, int n) {
    for (int i = 0; i < n; ++i) {
        double s = static_cast<double>(clampf(src[i])) * 8388608.0;
        if (s > 8388607.0) s = 8388607.0;
        if (s < -8388608.0) s = -8388608.0;
        int32_t v = static_cast<int32_t>(s);
        dst[i * 3] = static_cast<uint8_t>(v & 0xff);
        dst[i * 3 + 1] = static_cast<uint8_t>((v >> 8) & 0xff);
        dst[i * 3 + 2] = static_cast<uint8_t>((v >> 16) & 0xff);
    }
}

static void convertFloatToInt32(const float* src, uint8_t* dst, int n) {
    auto* out = reinterpret_cast<int32_t*>(dst);
    for (int i = 0; i < n; ++i) {
        double s = static_cast<double>(clampf(src[i])) * 2147483648.0;
        if (s > 2147483647.0) s = 2147483647.0;
        if (s < -2147483648.0) s = -2147483648.0;
        out[i] = static_cast<int32_t>(s);
    }
}

static bool allocRing(KumoneUsbAudioContext* ctx) {
    const size_t urbSize = sizeof(usbdevfs_urb) +
        KUMONE_USB_PACKETS_PER_URB * sizeof(usbdevfs_iso_packet_desc);
    for (int i = 0; i < KUMONE_USB_NUM_URBS; ++i) {
        ctx->ring[i].urb = static_cast<usbdevfs_urb*>(calloc(1, urbSize));
        ctx->ring[i].buffer = static_cast<uint8_t*>(malloc(KUMONE_USB_URB_BUFFER_SIZE));
        if (!ctx->ring[i].urb || !ctx->ring[i].buffer) {
            LOGE("allocRing failed at %d", i);
            for (int j = 0; j <= i; ++j) {
                free(ctx->ring[j].urb);
                free(ctx->ring[j].buffer);
                ctx->ring[j].urb = nullptr;
                ctx->ring[j].buffer = nullptr;
            }
            return false;
        }
    }
    return true;
}

static void freeRing(KumoneUsbAudioContext* ctx) {
    for (int i = 0; i < KUMONE_USB_NUM_URBS; ++i) {
        free(ctx->ring[i].urb);
        free(ctx->ring[i].buffer);
        ctx->ring[i].urb = nullptr;
        ctx->ring[i].buffer = nullptr;
    }
}

static void discardAndDrain(KumoneUsbAudioContext* ctx) {
    for (int i = 0; i < KUMONE_USB_NUM_URBS; ++i) {
        if (ctx->ring[i].urb) ioctl(ctx->fd, USBDEVFS_DISCARDURB, ctx->ring[i].urb);
    }
    if (ctx->feedbackInFlight && ctx->feedbackUrb) {
        ioctl(ctx->fd, USBDEVFS_DISCARDURB, ctx->feedbackUrb);
    }
    for (int attempt = 0; attempt < 800; ++attempt) {
        usbdevfs_urb* completed = nullptr;
        int rc = ioctl(ctx->fd, USBDEVFS_REAPURBNDELAY, &completed);
        if (rc == 0 && completed != nullptr) continue;
        if (rc < 0 && errno != EAGAIN) break;
        usleep(1000);
    }
    ctx->urbsInFlight = 0;
    ctx->submitIdx = 0;
    ctx->reapIdx = 0;
    ctx->feedbackInFlight = false;
}

static bool submitFeedback(KumoneUsbAudioContext* ctx) {
    if (ctx->endpointFeedback <= 0 || ctx->feedbackInFlight || !ctx->feedbackUrb) return false;
    const size_t sz = sizeof(usbdevfs_urb) + sizeof(usbdevfs_iso_packet_desc);
    memset(ctx->feedbackUrb, 0, sz);
    ctx->feedbackUrb->type = USBDEVFS_URB_TYPE_ISO;
    ctx->feedbackUrb->flags = USBDEVFS_URB_ISO_ASAP;
    ctx->feedbackUrb->endpoint = static_cast<unsigned char>(ctx->endpointFeedback);
    ctx->feedbackUrb->buffer = ctx->feedbackBuffer;
    ctx->feedbackUrb->buffer_length = 4;
    ctx->feedbackUrb->number_of_packets = 1;
    ctx->feedbackUrb->iso_frame_desc[0].length = 4;
    if (ioctl(ctx->fd, USBDEVFS_SUBMITURB, ctx->feedbackUrb) < 0) return false;
    ctx->feedbackInFlight = true;
    return true;
}

static void handleFeedback(KumoneUsbAudioContext* ctx) {
    ctx->feedbackInFlight = false;
    if (ctx->feedbackUrb->iso_frame_desc[0].actual_length >= 4) {
        const uint8_t* b = ctx->feedbackBuffer;
        uint32_t raw = static_cast<uint32_t>(b[0]) |
                       (static_cast<uint32_t>(b[1]) << 8) |
                       (static_cast<uint32_t>(b[2]) << 16) |
                       (static_cast<uint32_t>(b[3]) << 24);
        double fpmf = raw / 65536.0;
        double nominal = static_cast<double>(ctx->sampleRate) / 8000.0;
        if (fpmf > nominal * 0.98 && fpmf < nominal * 1.02) {
            ctx->calibratedFpmf = fpmf;
        }
    }
    submitFeedback(ctx);
}

static int reapOne(KumoneUsbAudioContext* ctx, int timeoutMs) {
    for (int i = 0; i < timeoutMs * 4; ++i) {
        usbdevfs_urb* completed = nullptr;
        int rc = ioctl(ctx->fd, USBDEVFS_REAPURBNDELAY, &completed);
        if (rc == 0 && completed != nullptr) {
            if (completed == ctx->feedbackUrb) {
                handleFeedback(ctx);
                continue;
            }
            ctx->reapIdx = (ctx->reapIdx + 1) % KUMONE_USB_NUM_URBS;
            if (ctx->urbsInFlight > 0) --ctx->urbsInFlight;
            return 0;
        }
        if (rc < 0 && errno != EAGAIN) return -1;
        usleep(250);
    }
    return -2;
}

static bool submitUrb(KumoneUsbAudioContext* ctx, const int* packetBytes, int packetCount, int totalBytes) {
    if (packetCount <= 0 || totalBytes <= 0) return false;
    KumoneUrbSlot* slot = &ctx->ring[ctx->submitIdx];
    const size_t clearSize = sizeof(usbdevfs_urb) +
        packetCount * sizeof(usbdevfs_iso_packet_desc);
    memset(slot->urb, 0, clearSize);
    slot->urb->type = USBDEVFS_URB_TYPE_ISO;
    slot->urb->flags = USBDEVFS_URB_ISO_ASAP;
    slot->urb->endpoint = static_cast<unsigned char>(ctx->endpointOut);
    slot->urb->buffer = slot->buffer;
    slot->urb->buffer_length = totalBytes;
    slot->urb->number_of_packets = packetCount;
    int offset = 0;
    for (int i = 0; i < packetCount; ++i) {
        slot->urb->iso_frame_desc[i].length = static_cast<unsigned>(packetBytes[i]);
        offset += packetBytes[i];
    }
    if (ioctl(ctx->fd, USBDEVFS_SUBMITURB, slot->urb) < 0) {
        LOGE("SUBMITURB failed errno=%d (%s)", errno, strerror(errno));
        return false;
    }
    ctx->submitIdx = (ctx->submitIdx + 1) % KUMONE_USB_NUM_URBS;
    ++ctx->urbsInFlight;
    return true;
}

void kumoneSubmitPcm(KumoneUsbAudioContext* ctx, const uint8_t* pcmData, int totalBytes) {
    if (!ctx || !ctx->running.load() || !pcmData || totalBytes <= 0) return;

    const uint8_t* data = pcmData;
    int dataLen = totalBytes;
    uint8_t* merged = nullptr;
    if (ctx->residualBytes > 0) {
        dataLen += ctx->residualBytes;
        merged = static_cast<uint8_t*>(malloc(dataLen));
        if (!merged) return;
        memcpy(merged, ctx->residualBuffer, ctx->residualBytes);
        memcpy(merged + ctx->residualBytes, pcmData, totalBytes);
        data = merged;
        ctx->residualBytes = 0;
    }

    int offset = 0;
    while (offset < dataLen && ctx->running.load()) {
        if (ctx->urbsInFlight >= KUMONE_USB_NUM_URBS) {
            int rc = reapOne(ctx, 250);
            if (rc < 0) {
                LOGE("URB reap failed rc=%d", rc);
                ctx->running.store(false);
                break;
            }
        }

        int packetBytes[KUMONE_USB_PACKETS_PER_URB] = {};
        int packetCount = 0;
        int totalPacketBytes = 0;
        const double fpmf = ctx->calibratedFpmf;
        for (int p = 0; p < KUMONE_USB_PACKETS_PER_URB; ++p) {
            const int remaining = dataLen - offset - totalPacketBytes;
            if (remaining <= 0) break;
            ctx->frameAccumulator += fpmf;
            int frames = static_cast<int>(ctx->frameAccumulator);
            ctx->frameAccumulator -= frames;
            int bytes = frames * ctx->bytesPerFrame;
            if (bytes <= 0 || bytes > remaining) break;
            packetBytes[packetCount++] = bytes;
            totalPacketBytes += bytes;
        }

        if (packetCount < KUMONE_USB_PACKETS_PER_URB || totalPacketBytes <= 0) {
            const int leftover = dataLen - offset;
            if (leftover > 0 && leftover < KUMONE_USB_URB_BUFFER_SIZE) {
                memcpy(ctx->residualBuffer, data + offset, leftover);
                ctx->residualBytes = leftover;
            }
            break;
        }

        KumoneUrbSlot* slot = &ctx->ring[ctx->submitIdx];
        if (totalPacketBytes > KUMONE_USB_URB_BUFFER_SIZE) {
            LOGE("URB payload too large: %d", totalPacketBytes);
            ctx->running.store(false);
            break;
        }
        memcpy(slot->buffer, data + offset, totalPacketBytes);
        if (!submitUrb(ctx, packetBytes, packetCount, totalPacketBytes)) {
            ctx->running.store(false);
            break;
        }
        offset += totalPacketBytes;
        const int frames = totalPacketBytes / ctx->bytesPerFrame;
        ctx->framesWritten += frames;
    }
    if (offset < dataLen && ctx->residualBytes == 0) {
        int leftover = dataLen - offset;
        if (leftover > 0 && leftover < KUMONE_USB_URB_BUFFER_SIZE) {
            memcpy(ctx->residualBuffer, data + offset, leftover);
            ctx->residualBytes = leftover;
        }
    }
    free(merged);
}

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_ryanheise_just_1audio_KumoneUsbStream_nativeCreate(
    JNIEnv*, jobject, jint fd, jint interfaceId, jint endpointOut, jint endpointFeedback,
    jint sampleRate, jint channelCount, jint bitDepth, jint maxPacketSize) {
    auto* ctx = new(std::nothrow) KumoneUsbAudioContext{};
    if (!ctx) return 0;
    ctx->fd = fd;
    ctx->interfaceId = interfaceId;
    ctx->endpointOut = endpointOut;
    ctx->endpointFeedback = endpointFeedback;
    ctx->sampleRate = sampleRate;
    ctx->channelCount = channelCount;
    ctx->bitDepth = bitDepth;
    ctx->bytesPerSample = bitDepth / 8;
    ctx->bytesPerFrame = ctx->bytesPerSample * channelCount;
    ctx->maxPacketSize = maxPacketSize;
    ctx->running.store(false);
    ctx->calibratedFpmf = static_cast<double>(sampleRate) / 8000.0;
    ctx->feedbackUrb = nullptr;
    ctx->feedbackInFlight = false;
    if (!allocRing(ctx)) {
        delete ctx;
        return 0;
    }
    const size_t feedbackSize = sizeof(usbdevfs_urb) + sizeof(usbdevfs_iso_packet_desc);
    ctx->feedbackUrb = static_cast<usbdevfs_urb*>(calloc(1, feedbackSize));
    if (!ctx->feedbackUrb) {
        freeRing(ctx);
        delete ctx;
        return 0;
    }
    memset(ctx->feedbackBuffer, 0, sizeof(ctx->feedbackBuffer));
    return reinterpret_cast<jlong>(ctx);
}

JNIEXPORT jboolean JNICALL
Java_com_ryanheise_just_1audio_KumoneUsbStream_nativeStart(JNIEnv*, jobject, jlong handle) {
    auto* ctx = reinterpret_cast<KumoneUsbAudioContext*>(handle);
    if (!ctx) return JNI_FALSE;
    ctx->submitIdx = 0;
    ctx->reapIdx = 0;
    ctx->urbsInFlight = 0;
    ctx->frameAccumulator = 0.0;
    ctx->framesWritten = 0;
    ctx->residualBytes = 0;
    ctx->calibratedFpmf = static_cast<double>(ctx->sampleRate) / 8000.0;
    ctx->running.store(true);
    if (ctx->endpointFeedback > 0) submitFeedback(ctx);
    return JNI_TRUE;
}

JNIEXPORT void JNICALL
Java_com_ryanheise_just_1audio_KumoneUsbStream_nativeStop(JNIEnv*, jobject, jlong handle) {
    auto* ctx = reinterpret_cast<KumoneUsbAudioContext*>(handle);
    if (!ctx) return;
    ctx->running.store(false);
}

JNIEXPORT void JNICALL
Java_com_ryanheise_just_1audio_KumoneUsbStream_nativeFlush(JNIEnv*, jobject, jlong handle) {
    auto* ctx = reinterpret_cast<KumoneUsbAudioContext*>(handle);
    if (!ctx) return;
    ctx->running.store(false);
    discardAndDrain(ctx);
    ctx->frameAccumulator = 0.0;
    ctx->residualBytes = 0;
    ctx->framesWritten = 0;
}

JNIEXPORT jint JNICALL
Java_com_ryanheise_just_1audio_KumoneUsbStream_nativeDrain(JNIEnv*, jobject, jlong handle) {
    auto* ctx = reinterpret_cast<KumoneUsbAudioContext*>(handle);
    if (!ctx) return 0;
    ctx->running.store(false);
    int before = ctx->urbsInFlight;
    int drained = 0;
    while (ctx->urbsInFlight > 0) {
        int rc = reapOne(ctx, 500);
        if (rc < 0) break;
        ++drained;
    }
    if (ctx->urbsInFlight > 0) discardAndDrain(ctx);
    return before > 0 ? drained : 0;
}

JNIEXPORT void JNICALL
Java_com_ryanheise_just_1audio_KumoneUsbStream_nativeDestroy(JNIEnv*, jobject, jlong handle) {
    auto* ctx = reinterpret_cast<KumoneUsbAudioContext*>(handle);
    if (!ctx) return;
    ctx->running.store(false);
    if (ctx->urbsInFlight > 0 || ctx->feedbackInFlight) discardAndDrain(ctx);
    free(ctx->feedbackUrb);
    ctx->feedbackUrb = nullptr;
    freeRing(ctx);
    delete ctx;
}

JNIEXPORT jboolean JNICALL
Java_com_ryanheise_just_1audio_KumoneUsbStream_nativeIsRunning(JNIEnv*, jobject, jlong handle) {
    auto* ctx = reinterpret_cast<KumoneUsbAudioContext*>(handle);
    return (ctx && ctx->running.load()) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jlong JNICALL
Java_com_ryanheise_just_1audio_KumoneUsbStream_nativeGetFramesWritten(JNIEnv*, jobject, jlong handle) {
    auto* ctx = reinterpret_cast<KumoneUsbAudioContext*>(handle);
    return ctx ? static_cast<jlong>(ctx->framesWritten) : 0;
}

JNIEXPORT void JNICALL
Java_com_ryanheise_just_1audio_KumoneUsbStream_nativeWriteRaw(
    JNIEnv* env, jobject, jlong handle, jbyteArray pcm, jint inputBitDepth) {
    auto* ctx = reinterpret_cast<KumoneUsbAudioContext*>(handle);
    if (!ctx || !ctx->running.load() || !pcm) return;
    const jsize inputBytes = env->GetArrayLength(pcm);
    if (inputBytes <= 0) return;
    const int inputBps = inputBitDepth / 8;
    if (inputBps <= 0) return;
    const int totalSamples = inputBytes / inputBps;
    const int outputBytes = totalSamples * ctx->bytesPerSample;
    auto* temp = static_cast<uint8_t*>(malloc(outputBytes));
    if (!temp) return;
    jbyte* raw = env->GetByteArrayElements(pcm, nullptr);
    if (!raw) { free(temp); return; }

    if (inputBitDepth == ctx->bitDepth) {
        memcpy(temp, raw, inputBytes);
    } else if (inputBitDepth == 16 && ctx->bitDepth == 32) {
        auto* out = reinterpret_cast<int32_t*>(temp);
        auto* in = reinterpret_cast<const int16_t*>(raw);
        for (int i = 0; i < totalSamples; ++i) out[i] = static_cast<int32_t>(in[i]) << 16;
    } else if (inputBitDepth == 24 && ctx->bitDepth == 32) {
        auto* out = reinterpret_cast<int32_t*>(temp);
        auto* in = reinterpret_cast<const uint8_t*>(raw);
        for (int i = 0; i < totalSamples; ++i) {
            int32_t s = static_cast<int32_t>(in[i * 3]) |
                        (static_cast<int32_t>(in[i * 3 + 1]) << 8) |
                        (static_cast<int32_t>(in[i * 3 + 2]) << 16);
            if (s & 0x800000) s |= 0xff000000;
            out[i] = s << 8;
        }
    } else {
        env->ReleaseByteArrayElements(pcm, raw, JNI_ABORT);
        free(temp);
        return;
    }
    env->ReleaseByteArrayElements(pcm, raw, JNI_ABORT);
    kumoneSubmitPcm(ctx, temp, outputBytes);
    free(temp);
}

JNIEXPORT void JNICALL
Java_com_ryanheise_just_1audio_KumoneUsbStream_nativeWriteFloat(
    JNIEnv* env, jobject, jlong handle, jfloatArray pcm) {
    auto* ctx = reinterpret_cast<KumoneUsbAudioContext*>(handle);
    if (!ctx || !ctx->running.load() || !pcm) return;
    const jsize samples = env->GetArrayLength(pcm);
    if (samples <= 0) return;
    const int outputBytes = samples * ctx->bytesPerSample;
    auto* temp = static_cast<uint8_t*>(malloc(outputBytes));
    if (!temp) return;
    jfloat* raw = env->GetFloatArrayElements(pcm, nullptr);
    if (!raw) { free(temp); return; }
    switch (ctx->bitDepth) {
        case 16: convertFloatToInt16(raw, temp, samples); break;
        case 24: convertFloatToInt24(raw, temp, samples); break;
        case 32: convertFloatToInt32(raw, temp, samples); break;
        default:
            env->ReleaseFloatArrayElements(pcm, raw, JNI_ABORT);
            free(temp);
            return;
    }
    env->ReleaseFloatArrayElements(pcm, raw, JNI_ABORT);
    kumoneSubmitPcm(ctx, temp, outputBytes);
    free(temp);
}

} // extern "C"
