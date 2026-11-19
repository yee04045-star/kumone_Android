/*
 * Adapted from the direct USB Audio Class design in:
 * https://github.com/Ma145/decent-player
 * MIT License, Copyright (c) 2026 Marcelo Silva. See
 * third_party/licenses/DECENT_PLAYER_MIT.txt in this repository.
 */

package com.ryanheise.just_audio;

import android.content.Context;

import androidx.annotation.Nullable;
import androidx.media3.exoplayer.DefaultRenderersFactory;
import androidx.media3.exoplayer.audio.AudioSink;
import androidx.media3.exoplayer.audio.DefaultAudioSink;

/** DefaultRenderersFactory with an optional direct USB audio sink. */
public final class KumoneUsbRenderersFactory extends DefaultRenderersFactory {
    public KumoneUsbRenderersFactory(Context context) {
        super(context);
    }

    @Override
    @Nullable
    protected AudioSink buildAudioSink(
            Context context,
            boolean enableFloatOutput,
            boolean enableAudioTrackPlaybackParams) {
        DefaultAudioSink delegate = new DefaultAudioSink.Builder(context)
                .setEnableFloatOutput(enableFloatOutput)
                .setEnableAudioTrackPlaybackParams(enableAudioTrackPlaybackParams)
                .build();
        return new KumoneUsbAudioSink(delegate, context);
    }
}
