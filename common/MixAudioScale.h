// MixAudioScale.h -- the per-app level (Mac Status Bar's Audio menu) applied to an app's own output unit: MixAudio's render notification on a
// RemoteIO unit (mixaudio/MixAudio.x, MARenderNotify). Plain C, so the Mac test (tools/test-mixaudioscale.sh) runs this very code.
//
// A unit's render notification gets the buffers the unit hands on, in the format of the unit's OUTPUT scope, element 0. On a RemoteIO unit
// that is the system's side (32-bit float, non-interleaved, on every iPad measured), already converted from the app's own format, which is its
// INPUT scope (16-bit integer for many game engines). Until 1.8.8.3 the samples were read in the app's format: for a 16-bit game any level
// between 0 and 1 turned its sound into full-scale noise (GitHub #18: lower = much louder). So now:
//  - the format is read on the output scope (MSBDMixScaleRender's reader), once per unit, again after a change (MSBDMixScaleForget);
//  - the buffer list must have exactly that format's shape (MSBDMixLayoutMatches), or the format is read again: at once, for that same buffer,
//    when it had matched before (the route changed under it), else for the next buffer, then every MSBD_MIX_SCALE_REREAD buffers;
//  - only the sample formats below are scaled (MSBDMixSampleKind); any other format, or a shape that still does not match, is left exactly as
//    it is, so the worst case is "not scaled", never louder;
//  - the gain is clamped to 0...1 and ramps across a buffer, per frame, from the last gain used (no click when the slider moves).
#pragma once
#include <CoreAudioTypes/CoreAudioTypes.h>
#include <stdint.h>
#include <string.h>

enum { MSBDMixSampleUnknown = 0, MSBDMixSampleFloat32, MSBDMixSampleInt16, MSBDMixSampleInt32 };

// The sample formats scaled: linear PCM, native (little) endian, packed, and 32-bit float, 16-bit signed integer or 32-bit signed integer
// (also fixed point such as 8.24: a fraction scales the same). Anything else is unknown: 8-bit unsigned (its silence is 128), 24-bit in 3 or
// 4 bytes, 64-bit float, big endian, compressed formats, a format with no channels or no frame size.
static inline int MSBDMixSampleKind(const AudioStreamBasicDescription *f) {
    if (!f || f->mFormatID != kAudioFormatLinearPCM || !f->mChannelsPerFrame || !f->mBytesPerFrame || !f->mBitsPerChannel) return MSBDMixSampleUnknown;
    UInt32 flags = f->mFormatFlags;
    if (flags & kAudioFormatFlagIsBigEndian) return MSBDMixSampleUnknown;
    UInt32 sampleBytes = f->mBitsPerChannel / 8;   // (one channel's sample; non-interleaved: one buffer's frame is one sample)
    if (sampleBytes * 8 != f->mBitsPerChannel) return MSBDMixSampleUnknown;
    if (f->mBytesPerFrame != ((flags & kAudioFormatFlagIsNonInterleaved) ? sampleBytes : sampleBytes * f->mChannelsPerFrame)) return MSBDMixSampleUnknown;
    if (flags & kAudioFormatFlagIsFloat) return f->mBitsPerChannel == 32 ? MSBDMixSampleFloat32 : MSBDMixSampleUnknown;
    if (!(flags & kAudioFormatFlagIsSignedInteger)) return MSBDMixSampleUnknown;
    if (f->mBitsPerChannel == 16) return MSBDMixSampleInt16;
    if (f->mBitsPerChannel == 32) return MSBDMixSampleInt32;
    return MSBDMixSampleUnknown;
}

// The buffer list has exactly the format's shape: one buffer per channel (non-interleaved) or one buffer of all channels, each with data and
// frames x bytes per frame of it.
static inline int MSBDMixLayoutMatches(const AudioStreamBasicDescription *f, UInt32 frames, const AudioBufferList *io) {
    if (!f || !io || !frames || !f->mChannelsPerFrame || !f->mBytesPerFrame) return 0;
    int nonInterleaved = (f->mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    UInt32 buffers = nonInterleaved ? f->mChannelsPerFrame : 1, channels = nonInterleaved ? 1 : f->mChannelsPerFrame;
    if (io->mNumberBuffers != buffers) return 0;
    uint64_t bytes = (uint64_t)frames * f->mBytesPerFrame;
    for (UInt32 b = 0; b < buffers; b++)
        if (!io->mBuffers[b].mData || io->mBuffers[b].mNumberChannels != channels || io->mBuffers[b].mDataByteSize != bytes) return 0;
    return 1;
}

// Scales the buffers in place (the shape already checked): gain from `from` at the first frame towards `to`, the same for every channel of a frame.
static inline void MSBDMixScaleSamples(int kind, const AudioStreamBasicDescription *f, UInt32 frames, AudioBufferList *io, float from, float to) {
    UInt32 channels = (f->mFormatFlags & kAudioFormatFlagIsNonInterleaved) ? 1 : f->mChannelsPerFrame;
    float step = (to - from) / (float)frames;
    for (UInt32 b = 0; b < io->mNumberBuffers; b++) {
        void *data = io->mBuffers[b].mData;
        for (UInt32 i = 0; i < frames; i++) {
            float g = from + step * (float)i;
            size_t k = (size_t)i * channels;
            if (kind == MSBDMixSampleFloat32) { float *x = (float *)data + k; for (UInt32 c = 0; c < channels; c++) x[c] *= g; }
            else if (kind == MSBDMixSampleInt16) { SInt16 *x = (SInt16 *)data + k; for (UInt32 c = 0; c < channels; c++) x[c] = (SInt16)((float)x[c] * g); }
            else if (kind == MSBDMixSampleInt32) { SInt32 *x = (SInt32 *)data + k; for (UInt32 c = 0; c < channels; c++) x[c] = (SInt32)((double)x[c] * (double)g); }
        }
    }
}

// One output unit's state. Zeroed except lastGain (1.0: nothing scaled yet): MSBD_MIX_SCALE_STATE_INIT.
typedef struct {
    AudioStreamBasicDescription fmt;   // the unit's output-scope format, as last read
    float lastGain;                    // the gain the last buffer ended at (1.0 = untouched)
    unsigned char known;               // fmt read and still current
    unsigned char fresh;               // fmt read for the buffers now coming, not yet matched by one
    unsigned short misses;             // buffers left untouched in a row (a scaled buffer sets it back to 0, a read does not)
} MSBDMixScaleState;
#define MSBD_MIX_SCALE_STATE_INIT { {0}, 1.0f, 0, 0, 0 }
#define MSBD_MIX_SCALE_REREAD 256      // buffers that still do not match after two reads: read again every this many buffers (a few seconds)

static inline void MSBDMixScaleForget(MSBDMixScaleState *s) { s->known = 0; }   // the format may have changed: read it before the next buffer

typedef int (*MSBDMixReadFormat)(void *ctx, AudioStreamBasicDescription *out);   // 1 when the unit's output-scope format was read into out

// One render of the output element: 1 = scaled, 0 = nothing to do (full level, nothing to ramp from, or no frames), -1 = left untouched
// (format not scaled or the buffers not in its shape). The reader runs only when the format is not known, never twice for one buffer: once per
// unit, then after a forget; when a format that matched stops matching (the route changed and its notice is not here yet), at once for that
// same buffer, so it is scaled as soon as the unit has the new format (as 1.8.8.2 scaled a float app's buffers whatever their shape); after a
// read that does not match, once more for the next buffer (the unit's format one buffer behind its buffers), then every
// MSBD_MIX_SCALE_REREAD untouched buffers.
static inline int MSBDMixScaleRender(MSBDMixScaleState *s, float target, UInt32 frames, AudioBufferList *io, MSBDMixReadFormat read, void *ctx) {
    if (!(target >= 0.0f)) target = 0.0f; else if (target > 1.0f) target = 1.0f;   // (NaN reads as 0: never above the app's own level)
    if (target >= 0.999f && s->lastGain >= 0.999f) return 0;
    if (!io || !frames) return 0;
    int kind = MSBDMixSampleUnknown;
    for (int tries = 0; tries < 2; tries++) {
        if (!s->known) {
            if (!read(ctx, &s->fmt)) memset(&s->fmt, 0, sizeof s->fmt);   // (unreadable: an unknown format)
            s->known = 1; s->fresh = 1;
        }
        kind = MSBDMixSampleKind(&s->fmt);
        if (kind != MSBDMixSampleUnknown && MSBDMixLayoutMatches(&s->fmt, frames, io)) break;
        kind = MSBDMixSampleUnknown;
        if (s->fresh) break;   // (read and not matched since: the rule below says when to read again)
        s->known = 0;          // it matched the buffers before: they changed under it, read it again now, for this buffer
    }
    if (kind == MSBDMixSampleUnknown) {
        ++s->misses;
        if (s->misses == 1 || s->misses % MSBD_MIX_SCALE_REREAD == 0) s->known = 0;   // read again for the next buffer, then every MSBD_MIX_SCALE_REREAD
        s->lastGain = 1.0f;   // (this buffer plays at the app's own level: the next scaled one ramps down from there)
        return -1;
    }
    s->fresh = 0; s->misses = 0;
    float from = s->lastGain;
    s->lastGain = target;
    MSBDMixScaleSamples(kind, &s->fmt, frames, io, from, target);
    return 1;
}
