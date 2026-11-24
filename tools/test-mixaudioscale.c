// test-mixaudioscale.c -- Mac test of the per-app level on an app's own output unit (MixAudio, 1.8.8.3, GitHub #18): the real render notification
// of mixaudio/MixAudio.x (cut out by test-mixaudioscale.sh into notify.inc: MAUnitState, gMAUnits, MAForgetUnitFormats, MAReadOutputFormat,
// MARenderNotify) and common/MixAudioScale.h, on a model of a RemoteIO unit. The app writes its samples in its own format (the unit's input
// scope); the system converts them to its side (the output scope) and the render notification gets those buffers, as measured on iPadOS 15.6.1:
// 32-bit float, non-interleaved, 2 x 1 channel at 48 kHz, also for a 16-bit app and for a 44.1 kHz one. AudioUnitGetProperty is this file's
// stand-in: it answers each scope with the unit's format and counts the reads. Run by test-mixaudioscale.sh.
#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
#include <string.h>
#include <math.h>
#include <pthread.h>
#include <AudioToolbox/AudioToolbox.h>
#ifndef YES
typedef signed char BOOL;
#define YES ((BOOL)1)
#define NO ((BOOL)0)
#endif
#if HAVE_SCALE_H
#include "common/MixAudioScale.h"
#endif

// What notify.inc needs from the rest of MixAudio.x
#define DM_FEATURE_MARK(name) do { } while (0)
static int gInCall = 0;
static int MAInCall(void) { return gInCall; }
static volatile float gMAOutputMult = 1.0f;

// The unit: its two formats, as AudioUnitGetProperty gives them
typedef struct { AudioStreamBasicDescription in, out; int readsIn, readsOut, failOut; } FakeUnit;
OSStatus AudioUnitGetProperty(AudioUnit unit, AudioUnitPropertyID prop, AudioUnitScope scope, AudioUnitElement elem, void *data, UInt32 *size) {
    FakeUnit *u = (FakeUnit *)unit;
    if (!u || prop != kAudioUnitProperty_StreamFormat || elem != 0 || !data || !size || *size < sizeof(AudioStreamBasicDescription)) return kAudioUnitErr_InvalidProperty;
    if (scope == kAudioUnitScope_Input) { u->readsIn++; memcpy(data, &u->in, sizeof u->in); }
    else if (scope == kAudioUnitScope_Output) { u->readsOut++; if (u->failOut) return kAudioUnitErr_InvalidProperty; memcpy(data, &u->out, sizeof u->out); }
    else return kAudioUnitErr_InvalidScope;
    *size = sizeof(AudioStreamBasicDescription);
    return noErr;
}

#include "notify.inc"

static int fails = 0, checks = 0;
static void Check(int ok, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
#include <stdarg.h>
static void Check(int ok, const char *fmt, ...) {
    va_list ap; va_start(ap, fmt); checks++;
    printf("%s  ", ok ? "PASS" : "FAIL"); vprintf(fmt, ap); printf("\n");
    va_end(ap); if (!ok) fails++;
}

// ---- formats ----
static AudioStreamBasicDescription PCM(double rate, UInt32 ch, UInt32 bits, UInt32 sampleBytes, UInt32 flags) {
    AudioStreamBasicDescription f; memset(&f, 0, sizeof f);
    f.mSampleRate = rate; f.mFormatID = kAudioFormatLinearPCM; f.mFormatFlags = flags; f.mChannelsPerFrame = ch; f.mBitsPerChannel = bits;
    f.mBytesPerFrame = (flags & kAudioFormatFlagIsNonInterleaved) ? sampleBytes : sampleBytes * ch;
    f.mBytesPerPacket = f.mBytesPerFrame; f.mFramesPerPacket = 1;
    return f;
}
#define NI kAudioFormatFlagIsNonInterleaved
static AudioStreamBasicDescription F32(double rate, UInt32 ch, UInt32 ni) { return PCM(rate, ch, 32, 4, kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | ni); }
static AudioStreamBasicDescription I16(double rate, UInt32 ch, UInt32 ni) { return PCM(rate, ch, 16, 2, kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked | ni); }
static AudioStreamBasicDescription I32(double rate, UInt32 ch, UInt32 ni, UInt32 fraction) {
    return PCM(rate, ch, 32, 4, kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked | ni | (fraction << kLinearPCMFormatFlagsSampleFractionShift));
}
static const char *FmtName(const AudioStreamBasicDescription *f, char *out, size_t n) {
    if (f->mFormatID != kAudioFormatLinearPCM) { snprintf(out, n, "a compressed format"); return out; }
    UInt32 fr = (f->mFormatFlags & kLinearPCMFormatFlagsSampleFractionMask) >> kLinearPCMFormatFlagsSampleFractionShift;
    snprintf(out, n, "%s%u-bit %s%s%s %s %.1f kHz", (f->mFormatFlags & kAudioFormatFlagIsBigEndian) ? "big-endian " : "", (unsigned)f->mBitsPerChannel,
             (f->mFormatFlags & kAudioFormatFlagIsFloat) ? "float" : (f->mFormatFlags & kAudioFormatFlagIsSignedInteger) ? "integer" : "unsigned",
             fr ? (fr == 24 ? " 8.24" : " fixed") : "", (f->mFormatFlags & NI) ? " non-interleaved" : " interleaved",
             f->mChannelsPerFrame == 1 ? "mono" : f->mChannelsPerFrame == 2 ? "stereo" : "multichannel", f->mSampleRate / 1000.0);
    return out;
}

// ---- buffers in a format's shape, holding a sine (amplitude 0.01, -43 dBFS rms as the test player on the iPad) ----
typedef struct { AudioBufferList *abl; UInt32 frames; AudioStreamBasicDescription f; double *ref; } Bufs;   // ref: [frame * channels + channel], -1...1
static double gPhase = 0;
static int Kind(const AudioStreamBasicDescription *f) {   // 'f' float32, 'i' int16, 'I' int32, 0 other
    if (f->mFormatID != kAudioFormatLinearPCM || (f->mFormatFlags & kAudioFormatFlagIsBigEndian)) return 0;
    if ((f->mFormatFlags & kAudioFormatFlagIsFloat) && f->mBitsPerChannel == 32) return 'f';
    if ((f->mFormatFlags & kAudioFormatFlagIsSignedInteger) && f->mBitsPerChannel == 16 && (f->mBytesPerFrame == 2 || f->mBytesPerFrame == 2 * f->mChannelsPerFrame)) return 'i';
    if ((f->mFormatFlags & kAudioFormatFlagIsSignedInteger) && f->mBitsPerChannel == 32) return 'I';
    return 0;
}
static double Scale(const AudioStreamBasicDescription *f) {   // full scale of an integer format
    UInt32 fr = (f->mFormatFlags & kLinearPCMFormatFlagsSampleFractionMask) >> kLinearPCMFormatFlagsSampleFractionShift;
    if (Kind(f) == 'i') return fr ? (double)(1u << fr) : 32767.0;
    return fr ? (double)(1u << fr) : 2147483647.0;
}
static void *At(Bufs *b, UInt32 frame, UInt32 ch, size_t sampleBytes) {
    int ni = (b->f.mFormatFlags & NI) != 0;
    if (ni) return (char *)b->abl->mBuffers[ch].mData + (size_t)frame * sampleBytes;
    return (char *)b->abl->mBuffers[0].mData + ((size_t)frame * b->f.mChannelsPerFrame + ch) * sampleBytes;
}
static void Fill(Bufs *b, double amp) {
    UInt32 ch = b->f.mChannelsPerFrame; int k = Kind(&b->f);
    for (UInt32 i = 0; i < b->frames; i++) {
        double v = amp * sin(gPhase); gPhase += 2 * M_PI * 440.0 / 48000.0;
        for (UInt32 c = 0; c < ch; c++) {
            double vc = c ? v * 0.5 : v;   // (the right channel at half: a per-frame gain keeps the two apart exactly)
            if (k == 'f') { float s = (float)vc; memcpy(At(b, i, c, 4), &s, 4); b->ref[i * ch + c] = s; }
            else if (k == 'i') { SInt16 s = (SInt16)lrint(vc * Scale(&b->f)); memcpy(At(b, i, c, 2), &s, 2); b->ref[i * ch + c] = s / Scale(&b->f); }
            else if (k == 'I') { SInt32 s = (SInt32)lrint(vc * Scale(&b->f)); memcpy(At(b, i, c, 4), &s, 4); b->ref[i * ch + c] = s / Scale(&b->f); }
        }
    }
    if (!k) for (UInt32 n = 0; n < b->abl->mNumberBuffers; n++) { unsigned char *p = b->abl->mBuffers[n].mData; for (UInt32 j = 0; j < b->abl->mBuffers[n].mDataByteSize; j++) p[j] = (unsigned char)(rand() & 0xff); }
}
static double Read(Bufs *b, UInt32 frame, UInt32 c) {   // a sample as the speaker gets it (-1...1; NaN / inf as they are)
    int k = Kind(&b->f);
    if (k == 'f') { float s; memcpy(&s, At(b, frame, c, 4), 4); return s; }
    if (k == 'i') { SInt16 s; memcpy(&s, At(b, frame, c, 2), 2); return s / Scale(&b->f); }
    SInt32 s; memcpy(&s, At(b, frame, c, 4), 4); return s / Scale(&b->f);
}
// Buffers in format f's shape; bytesPerFrame 0 (a compressed format): one buffer of 400 bytes
static Bufs Make(const AudioStreamBasicDescription *f, UInt32 frames) {
    Bufs b; memset(&b, 0, sizeof b); b.f = *f; b.frames = frames;
    int ni = (f->mFormatFlags & NI) != 0;
    UInt32 n = (ni && f->mBytesPerFrame) ? f->mChannelsPerFrame : 1;
    b.abl = calloc(1, offsetof(AudioBufferList, mBuffers) + n * sizeof(AudioBuffer));
    b.abl->mNumberBuffers = n;
    for (UInt32 i = 0; i < n; i++) {
        UInt32 bytes = f->mBytesPerFrame ? frames * f->mBytesPerFrame : 400;
        b.abl->mBuffers[i].mNumberChannels = ni ? 1 : f->mChannelsPerFrame;
        b.abl->mBuffers[i].mDataByteSize = bytes;
        b.abl->mBuffers[i].mData = calloc(1, (size_t)bytes * 4 + 64);   // (room past the end: a copy that writes beyond a buffer fails a check, never the heap)
    }
    b.ref = calloc((size_t)frames * (f->mChannelsPerFrame ? f->mChannelsPerFrame : 1), sizeof(double));
    return b;
}
static void Free(Bufs *b) { for (UInt32 i = 0; i < b->abl->mNumberBuffers; i++) free(b->abl->mBuffers[i].mData); free(b->abl); free(b->ref); }
static unsigned char *Snap(Bufs *b, size_t *len) {   // every byte of the buffers, to prove "untouched"
    size_t n = 0; for (UInt32 i = 0; i < b->abl->mNumberBuffers; i++) n += b->abl->mBuffers[i].mDataByteSize;
    unsigned char *s = malloc(n ? n : 1), *p = s;
    for (UInt32 i = 0; i < b->abl->mNumberBuffers; i++) { memcpy(p, b->abl->mBuffers[i].mData, b->abl->mBuffers[i].mDataByteSize); p += b->abl->mBuffers[i].mDataByteSize; }
    *len = n; return s;
}

// ---- the unit in MixAudio's table, and one render ----
static FakeUnit gUnit;
static MAUnitState *Unit(AudioStreamBasicDescription app, AudioStreamBasicDescription io) {
    memset(&gUnit, 0, sizeof gUnit); gUnit.in = app; gUnit.out = io;
    memset(gMAUnits, 0, sizeof gMAUnits);
    MAUnitState *st = &gMAUnits[0];
    st->unit = (AudioUnit)&gUnit;
#if HAVE_SCALE_H
    st->scale.lastGain = 1.0f;   // (as AudioComponentInstanceNew's hook starts a unit: MSBD_MIX_SCALE_STATE_INIT)
#else
    st->lastGain = 1.0f;
#endif
    gInCall = 0;
    return st;
}
static void AppSetsFormat(MAUnitState *st, AudioStreamBasicDescription app) {   // what MixAudio's AudioUnitSetProperty hook does after the app's call
    gUnit.in = app;
#if HAVE_SCALE_H
    MSBDMixScaleForget(&st->scale);
#else
    st->known = NO;
#endif
}
static void Render(MAUnitState *st, Bufs *b, UInt32 bus, AudioUnitRenderActionFlags fl) {
    AudioTimeStamp ts; memset(&ts, 0, sizeof ts);
    MARenderNotify(st, &fl, &ts, bus, b->frames, b->abl);
}

// One buffer after the notification: against the app's own samples x the gain (from g0 at the first frame to g1, steady when equal)
typedef struct { double sumOut, sumRef, maxErr; long louder, bad, n; } Stats;
static void Measure(Bufs *b, double g0, double g1, Stats *s, int steady) {
    UInt32 ch = b->f.mChannelsPerFrame; int k = Kind(&b->f);
    double lsb = k == 'f' ? 1e-7 : 1.0 / Scale(&b->f) + 1e-12;
    for (UInt32 i = 0; i < b->frames; i++) for (UInt32 c = 0; c < ch; c++) {
        double ref = b->ref[i * ch + c], out = Read(b, i, c);
        double hi = fabs(ref) * fmax(g0, g1) + lsb;
        if (!isfinite(out) || fabs(out) > hi) s->louder++;
        if (!isfinite(out) || fabs(out) < fabs(ref) * fmin(g0, g1) - lsb - 1e-9) s->bad++;
        if (steady) { double e = isfinite(out) ? fabs(out - ref * g1) : 1e9; if (e > s->maxErr) s->maxErr = e; s->sumOut += isfinite(out) ? out * out : 1e9; s->sumRef += ref * ref; }
        s->n++;
    }
}
static double DB(double sumOut, double sumRef) { return sumOut <= 0 ? -INFINITY : 10 * log10(sumOut / sumRef); }

// The level held on a playing app: the first buffer ramps from full level, the next ones are steady
static void Level(AudioStreamBasicDescription app, AudioStreamBasicDescription io, float level, UInt32 frames) {
    char an[96], on[96]; FmtName(&app, an, sizeof an); FmtName(&io, on, sizeof on);
    MAUnitState *st = Unit(app, io);
    gMAOutputMult = level;
    Stats s; memset(&s, 0, sizeof s);
    int untouched = 1;
    for (int n = 0; n < 6; n++) {
        Bufs b = Make(&io, frames); Fill(&b, 0.01);
        size_t len; unsigned char *before = Snap(&b, &len);
        Render(st, &b, 0, kAudioUnitRenderAction_PostRender);
        size_t len2; unsigned char *after = Snap(&b, &len2);
        if (memcmp(before, after, len)) untouched = 0;
        Measure(&b, n == 0 ? 1.0 : level, level, &s, n > 0);
        free(before); free(after); Free(&b);
    }
    double tol = Kind(&io) == 'f' ? 1e-6 : 2.0 / Scale(&io) + 1e-9;
    if (level >= 1.0f) Check(untouched && !s.louder, "app %s -> output side %s, level 1.00: every byte as the app made it (%s)", an, on, untouched ? "untouched" : "CHANGED");
    else if (level <= 0.0f) Check(s.sumOut == 0 && !s.louder && !s.bad, "app %s -> output side %s, level 0.00: silent after the first buffer's ramp (%s), %ld samples above the app's own",
                                  an, on, s.sumOut == 0 ? "silent" : "NOT silent", s.louder);
    else {
        double want = 20 * log10(level), got = DB(s.sumOut, s.sumRef);
        Check(fabs(got - want) < 0.05 && s.maxErr <= tol && !s.louder && !s.bad, "app %s -> output side %s, level %.2f: %+.2f dB (want %+.2f), largest error %.2g, %ld samples above the app's own",
              an, on, level, got, want, s.maxErr, s.louder);
    }
}

// The notification gets buffers that do not have the output side's shape: never written (they could be any format)
static void Untouched(const char *what, AudioStreamBasicDescription app, AudioStreamBasicDescription io, AudioStreamBasicDescription bufs, float level) {
    MAUnitState *st = Unit(app, io);
    gMAOutputMult = level;
    int same = 1;
    for (int n = 0; n < 4; n++) {
        Bufs b = Make(&bufs, 470); Fill(&b, 0.01);
        size_t len; unsigned char *before = Snap(&b, &len);
        Render(st, &b, 0, kAudioUnitRenderAction_PostRender);
        size_t len2; unsigned char *after = Snap(&b, &len2);
        if (memcmp(before, after, len)) same = 0;
        free(before); free(after); Free(&b);
    }
    Check(same, "%s, level %.2f: left untouched (%s)", what, level, same ? "every byte as it was" : "WRITTEN");
}

int main(void) {
    srand(7);
    const UInt32 F = 470;   // frames per buffer (the iPad's output side: odd counts happen)
    AudioStreamBasicDescription ipad = F32(48000, 2, NI);   // the output side measured on iPadOS: 32-bit float, non-interleaved, stereo, 48 kHz
    struct { const char *why; AudioStreamBasicDescription app; } apps[] = {
        { "a game engine's 16-bit", I16(48000, 2, 0) }, { "16-bit non-interleaved", I16(48000, 2, NI) }, { "16-bit at 44.1 kHz", I16(44100, 2, 0) },
        { "16-bit mono", I16(48000, 1, 0) }, { "32-bit float non-interleaved (Spotify, AVAudioEngine)", F32(48000, 2, NI) },
        { "32-bit float interleaved", F32(44100, 2, 0) }, { "8.24 fixed point (Core Audio's old canonical)", I32(44100, 2, NI, 24) },
    };
    float levels[] = { 1.0f, 0.5f, 0.1f, 0.0f };
    printf("-- the app's format on the iPad's output side (32-bit float, non-interleaved): each level\n");
    for (size_t a = 0; a < sizeof apps / sizeof apps[0]; a++) for (size_t l = 0; l < 4; l++) Level(apps[a].app, ipad, levels[l], F);
    printf("-- other output sides (the integer formats scaled as integers, interleaved per frame)\n");
    AudioStreamBasicDescription sides[] = { I16(48000, 2, 0), I16(48000, 2, NI), I32(48000, 2, NI, 24), I32(48000, 2, 0, 0), F32(48000, 2, 0), F32(48000, 1, NI), F32(44100, 6, NI) };
    for (size_t i = 0; i < sizeof sides / sizeof sides[0]; i++) { Level(F32(48000, 2, NI), sides[i], 0.5f, F); Level(I16(48000, 2, 0), sides[i], 0.5f, F); Level(I16(48000, 2, 0), sides[i], 0.0f, 333); }
    Level(I16(48000, 2, 0), ipad, 0.01f, 1024);
    Level(I16(48000, 2, 0), ipad, 0.9f, 1);

    printf("-- formats that are not scaled: left untouched at any level\n");
    AudioStreamBasicDescription f64 = PCM(48000, 2, 64, 8, kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | NI);
    AudioStreamBasicDescription u8 = PCM(48000, 2, 8, 1, kAudioFormatFlagIsPacked);
    AudioStreamBasicDescription i24 = PCM(48000, 2, 24, 3, kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked | NI);
    AudioStreamBasicDescription i24in32 = PCM(48000, 2, 24, 4, kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsAlignedHigh | NI);
    AudioStreamBasicDescription u16 = PCM(48000, 2, 16, 2, kAudioFormatFlagIsPacked);
    AudioStreamBasicDescription be16 = PCM(48000, 2, 16, 2, kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked | kAudioFormatFlagIsBigEndian);
    AudioStreamBasicDescription aac; memset(&aac, 0, sizeof aac); aac.mFormatID = kAudioFormatMPEG4AAC; aac.mSampleRate = 48000; aac.mChannelsPerFrame = 2; aac.mFramesPerPacket = 1024;
    struct { const char *what; AudioStreamBasicDescription f; } unknown[] = {
        { "output side 64-bit float", f64 }, { "output side 8-bit unsigned (silence is 128)", u8 }, { "output side 16-bit unsigned", u16 }, { "output side 24-bit packed", i24 },
        { "output side 24-bit in 4 bytes", i24in32 }, { "output side big-endian 16-bit", be16 }, { "output side a compressed format", aac },
    };
    for (size_t i = 0; i < sizeof unknown / sizeof unknown[0]; i++) {
        char what[160]; snprintf(what, sizeof what, "app 16-bit interleaved, %s", unknown[i].what);
        Untouched(what, I16(48000, 2, 0), unknown[i].f, unknown[i].f, 0.5f);
        Untouched(what, I16(48000, 2, 0), unknown[i].f, unknown[i].f, 0.0f);
    }
    printf("-- buffers not in the output side's shape: left untouched\n");
    Untouched("the notification given the app's own 16-bit interleaved buffers (1 x 2 channels), the output side 2 x 1 float", I16(48000, 2, 0), ipad, I16(48000, 2, 0), 0.5f);
    Untouched("the notification given 16-bit non-interleaved buffers (2 x 1, half the bytes), the output side 2 x 1 float", I16(48000, 2, NI), ipad, I16(48000, 2, NI), 0.5f);
    Untouched("the notification given mono buffers, the output side stereo", F32(48000, 1, NI), ipad, F32(48000, 1, NI), 0.1f);
    Untouched("the notification given 4 x 1 buffers, the output side 2 x 1", F32(48000, 4, NI), ipad, F32(48000, 4, NI), 0.1f);
    Untouched("the notification given 16-bit stereo interleaved (4 bytes a frame), the output side float mono (4 bytes a frame, 1 channel a buffer)", I16(48000, 2, 0), F32(48000, 1, NI), I16(48000, 2, 0), 0.5f);
    {   // the output side's format cannot be read: untouched
        MAUnitState *st = Unit(I16(48000, 2, 0), ipad); gUnit.failOut = 1; gMAOutputMult = 0.5f;
        Bufs b = Make(&ipad, F); Fill(&b, 0.01); size_t len; unsigned char *before = Snap(&b, &len);
        Render(st, &b, 0, kAudioUnitRenderAction_PostRender);
        size_t len2; unsigned char *after = Snap(&b, &len2);
        Check(!memcmp(before, after, len), "the output side's format cannot be read: the buffer left untouched");
        free(before); free(after); Free(&b);
    }

    printf("-- what is never scaled: level 1.0, bus 1 (the microphone), the pre-render call, a call\n");
    {
        MAUnitState *st = Unit(I16(48000, 2, 0), ipad); gMAOutputMult = 1.0f;
        for (int n = 0; n < 50; n++) { Bufs b = Make(&ipad, F); Fill(&b, 0.01); Render(st, &b, 0, kAudioUnitRenderAction_PostRender); Free(&b); }
        Check(gUnit.readsOut == 0 && gUnit.readsIn == 0, "level 1.0 over 50 buffers: no format read at all (reads: output side %d, app's %d)", gUnit.readsOut, gUnit.readsIn);
        gMAOutputMult = 0.5f;
        Bufs b = Make(&ipad, F); Fill(&b, 0.01); size_t len; unsigned char *before = Snap(&b, &len);
        Render(st, &b, 1, kAudioUnitRenderAction_PostRender); Render(st, &b, 0, kAudioUnitRenderAction_PreRender);
        size_t len2; unsigned char *after = Snap(&b, &len2);
        Check(!memcmp(before, after, len), "level 0.5: bus 1 and the pre-render call leave the buffer untouched");
        free(before); free(after); Free(&b);
        gInCall = 1;
        Stats s; memset(&s, 0, sizeof s); int same = 1;
        for (int n = 0; n < 4; n++) { Bufs c = Make(&ipad, F); Fill(&c, 0.01); unsigned char *p = Snap(&c, &len); Render(st, &c, 0, kAudioUnitRenderAction_PostRender); unsigned char *q = Snap(&c, &len2); if (memcmp(p, q, len)) same = 0; free(p); free(q); Free(&c); }
        Check(same, "level 0.5 in a call (a voice or video chat mode): full level, untouched");
        gInCall = 0;
    }

    printf("-- the level changed while playing: the first buffer ramps, never above the app's own level\n");
    {
        MAUnitState *st = Unit(I16(48000, 2, 0), ipad);
        float seq[] = { 1.0f, 0.5f, 0.5f, 0.1f, 0.1f, 1.0f, 1.0f, 0.0f, 0.0f, 0.5f };
        long louder = 0, bad = 0; double lastErr = 0;
        for (size_t n = 0; n < sizeof seq / sizeof seq[0]; n++) {
            float prev = n ? seq[n - 1] : 1.0f;
            gMAOutputMult = seq[n];
            Bufs b = Make(&ipad, F); Fill(&b, 0.01); Render(st, &b, 0, kAudioUnitRenderAction_PostRender);
            Stats s; memset(&s, 0, sizeof s); Measure(&b, prev, seq[n], &s, prev == seq[n]);
            louder += s.louder; bad += s.bad; if (prev == seq[n] && s.maxErr > lastErr) lastErr = s.maxErr;
            Free(&b);
        }
        Check(!louder && !bad && lastErr < 1e-6, "1.0, 0.5, 0.1, 1.0, 0.0, 0.5 while playing a 16-bit app: every sample between the two levels of its ramp, steady buffers exact (%ld above, %ld below, error %.2g)", louder, bad, lastErr);
        Check(gUnit.readsOut == 1, "  ... the output side's format read once for the whole run (%d reads)", gUnit.readsOut);
    }

    printf("-- the format changes mid-stream\n");
    {   // the route changes (the output side mono now) with no call from the app, its notice not here yet: the unit has the new format already,
        // so the first buffer in the new shape is read again at once and scaled (1.8.8.2 scaled a float app's buffers whatever their shape: not
        // one buffer of it at the app's own level after a route change, so none now either)
        MAUnitState *st = Unit(I16(48000, 2, 0), ipad); gMAOutputMult = 0.5f;
        for (int n = 0; n < 3; n++) { Bufs b = Make(&ipad, F); Fill(&b, 0.01); Render(st, &b, 0, kAudioUnitRenderAction_PostRender); Free(&b); }
        AudioStreamBasicDescription mono = F32(48000, 1, NI); gUnit.out = mono;
        Stats s; memset(&s, 0, sizeof s);
        for (int n = 0; n < 3; n++) { Bufs b = Make(&mono, F); Fill(&b, 0.01); Render(st, &b, 0, kAudioUnitRenderAction_PostRender); Measure(&b, 0.5, 0.5, &s, 1); Free(&b); }
        Check(!s.louder && !s.bad && s.maxErr < 1e-6 && fabs(DB(s.sumOut, s.sumRef) + 6.02) < 0.05, "the output side turns mono without a route notice: the first mono buffer already -6 dB exact, as the next ones (%+.2f dB, %ld samples above the level)",
              DB(s.sumOut, s.sumRef), s.louder);
        Check(gUnit.readsOut == 2, "  ... the output side read twice in all (%d)", gUnit.readsOut);
    }
    {   // the same with the unit's format one buffer behind its buffers: that buffer untouched (the app's own level, never above), the next read again
        MAUnitState *st = Unit(I16(48000, 2, 0), ipad); gMAOutputMult = 0.5f;
        for (int n = 0; n < 3; n++) { Bufs b = Make(&ipad, F); Fill(&b, 0.01); Render(st, &b, 0, kAudioUnitRenderAction_PostRender); Free(&b); }
        AudioStreamBasicDescription mono = F32(48000, 1, NI);   // (the unit still says stereo for the first mono buffer)
        Bufs b1 = Make(&mono, F); Fill(&b1, 0.01); size_t len; unsigned char *before = Snap(&b1, &len);
        Render(st, &b1, 0, kAudioUnitRenderAction_PostRender);
        size_t len2; unsigned char *after = Snap(&b1, &len2);
        int same = !memcmp(before, after, len);
        free(before); free(after); Free(&b1);
        gUnit.out = mono;
        Stats s; memset(&s, 0, sizeof s);
        Bufs b2 = Make(&mono, F); Fill(&b2, 0.01); Render(st, &b2, 0, kAudioUnitRenderAction_PostRender); Measure(&b2, 1.0, 0.5, &s, 0); Free(&b2);
        Stats s3; memset(&s3, 0, sizeof s3);
        Bufs b3 = Make(&mono, F); Fill(&b3, 0.01); Render(st, &b3, 0, kAudioUnitRenderAction_PostRender); Measure(&b3, 0.5, 0.5, &s3, 1); Free(&b3);
        Check(same, "the unit's format a buffer behind (still stereo for the first mono buffer): that buffer left untouched");
        Check(!s.louder && !s.bad && s3.maxErr < 1e-6 && fabs(DB(s3.sumOut, s3.sumRef) + 6.02) < 0.05, "  ... the next one read again and ramped down from full level, then -6 dB exact (%+.2f dB)", DB(s3.sumOut, s3.sumRef));
        Check(gUnit.readsOut == 3, "  ... never two reads for one buffer: the first, then the stale one at once, then the next buffer's (%d)", gUnit.readsOut);
    }
#if HAVE_SCALE_H
    {   // with the route notice (MixAudio's observer: MAForgetUnitFormats), the first buffer in the new shape is already scaled
        MAUnitState *st = Unit(I16(48000, 2, 0), ipad); gMAOutputMult = 0.5f;
        for (int n = 0; n < 3; n++) { Bufs b = Make(&ipad, F); Fill(&b, 0.01); Render(st, &b, 0, kAudioUnitRenderAction_PostRender); Free(&b); }
        AudioStreamBasicDescription mono = F32(48000, 1, NI); gUnit.out = mono;
        MAForgetUnitFormats();
        Stats s; memset(&s, 0, sizeof s);
        Bufs b = Make(&mono, F); Fill(&b, 0.01); Render(st, &b, 0, kAudioUnitRenderAction_PostRender); Measure(&b, 0.5, 0.5, &s, 1); Free(&b);
        Check(s.maxErr < 1e-6 && !s.louder && fabs(DB(s.sumOut, s.sumRef) + 6.02) < 0.05, "the route changes with the notice (MAForgetUnitFormats): the first mono buffer already -6 dB exact (%+.2f dB)", DB(s.sumOut, s.sumRef));
        Check(gUnit.readsOut == 2, "  ... read again once (%d reads)", gUnit.readsOut);
    }
#else
    Check(0, "the route notice: no MAForgetUnitFormats in MixAudio.x");
#endif
    {   // the output side changes sample format (32-bit float -> 16-bit, same channels): one buffer untouched, then scaled as 16-bit
        MAUnitState *st = Unit(F32(48000, 2, NI), ipad); gMAOutputMult = 0.5f;
        for (int n = 0; n < 3; n++) { Bufs b = Make(&ipad, F); Fill(&b, 0.01); Render(st, &b, 0, kAudioUnitRenderAction_PostRender); Free(&b); }
        AudioStreamBasicDescription s16 = I16(48000, 2, NI); gUnit.out = s16;
        long louder = 0; Stats s; memset(&s, 0, sizeof s);
        for (int n = 0; n < 4; n++) { Bufs b = Make(&s16, F); Fill(&b, 0.01); Render(st, &b, 0, kAudioUnitRenderAction_PostRender); Stats t; memset(&t, 0, sizeof t); Measure(&b, 1.0, 0.5, &t, 0); louder += t.louder; if (n >= 2) Measure(&b, 0.5, 0.5, &s, 1); Free(&b); }
        Check(!louder && s.maxErr <= 2.0 / 32767 && fabs(DB(s.sumOut, s.sumRef) + 6.02) < 0.1, "the output side turns 16-bit mid-stream: never above the app's own, then -6 dB as 16-bit (%+.2f dB)", DB(s.sumOut, s.sumRef));
    }
    {   // the app sets another format while playing (16-bit -> float): read again; the output side is the same, so the level stays exact
        MAUnitState *st = Unit(I16(48000, 2, 0), ipad); gMAOutputMult = 0.1f;
        Stats s; memset(&s, 0, sizeof s);
        for (int n = 0; n < 8; n++) {
            if (n == 4) AppSetsFormat(st, F32(44100, 2, 0));
            Bufs b = Make(&ipad, F); Fill(&b, 0.01); Render(st, &b, 0, kAudioUnitRenderAction_PostRender); if (n) Measure(&b, 0.1, 0.1, &s, 1); Free(&b);
        }
        Check(!s.louder && s.maxErr < 1e-6 && fabs(DB(s.sumOut, s.sumRef) + 20) < 0.05, "the app sets a float format mid-stream (16-bit before): -20 dB exact before and after (%+.2f dB), the output side read again (%d reads)", DB(s.sumOut, s.sumRef), gUnit.readsOut);
    }
    {   // a shape that never matches: read again now and then, never every buffer
        MAUnitState *st = Unit(I16(48000, 2, 0), ipad); gMAOutputMult = 0.5f;
        AudioStreamBasicDescription other = I16(48000, 2, 0); int same = 1;
        for (int n = 0; n < 600; n++) {
            Bufs b = Make(&other, 256); Fill(&b, 0.01); size_t len; unsigned char *p = Snap(&b, &len);
            Render(st, &b, 0, kAudioUnitRenderAction_PostRender);
            size_t len2; unsigned char *q = Snap(&b, &len2); if (memcmp(p, q, len)) same = 0; free(p); free(q); Free(&b);
        }
        Check(same && gUnit.readsOut >= 1 && gUnit.readsOut <= 4, "600 buffers that never have the output side's shape: all untouched, the format read %d times (not on every buffer)", gUnit.readsOut);
    }

#if HAVE_SCALE_H
    printf("-- common/MixAudioScale.h\n");
    {
        struct { const char *what; AudioStreamBasicDescription f; int want; } kinds[] = {
            { "32-bit float non-interleaved", F32(48000, 2, NI), MSBDMixSampleFloat32 }, { "32-bit float interleaved", F32(48000, 2, 0), MSBDMixSampleFloat32 },
            { "16-bit interleaved", I16(44100, 2, 0), MSBDMixSampleInt16 }, { "16-bit non-interleaved", I16(48000, 2, NI), MSBDMixSampleInt16 },
            { "32-bit integer", I32(48000, 2, 0, 0), MSBDMixSampleInt32 }, { "8.24 fixed point", I32(48000, 2, NI, 24), MSBDMixSampleInt32 },
            { "64-bit float", f64, MSBDMixSampleUnknown }, { "8-bit unsigned", u8, MSBDMixSampleUnknown }, { "16-bit unsigned", u16, MSBDMixSampleUnknown }, { "24-bit packed", i24, MSBDMixSampleUnknown },
            { "24-bit in 4 bytes", i24in32, MSBDMixSampleUnknown }, { "big-endian 16-bit", be16, MSBDMixSampleUnknown }, { "AAC", aac, MSBDMixSampleUnknown },
        };
        for (size_t i = 0; i < sizeof kinds / sizeof kinds[0]; i++) Check(MSBDMixSampleKind(&kinds[i].f) == kinds[i].want, "sample kind: %s -> %d (want %d)", kinds[i].what, MSBDMixSampleKind(&kinds[i].f), kinds[i].want);
        AudioStreamBasicDescription odd = I16(48000, 2, 0); odd.mBytesPerFrame = 2;
        Check(MSBDMixSampleKind(&odd) == MSBDMixSampleUnknown, "sample kind: 16-bit stereo interleaved claiming 2 bytes a frame -> unknown");
        AudioStreamBasicDescription none = F32(48000, 2, NI); none.mChannelsPerFrame = 0;
        Check(MSBDMixSampleKind(&none) == MSBDMixSampleUnknown && MSBDMixSampleKind(NULL) == MSBDMixSampleUnknown, "sample kind: no channels, no format -> unknown");

        Bufs b = Make(&ipad, 100);
        Check(MSBDMixLayoutMatches(&ipad, 100, b.abl), "shape: 2 x 1 float buffers of 100 frames match the output side");
        Check(!MSBDMixLayoutMatches(&ipad, 99, b.abl), "shape: the wrong frame count does not");
        b.abl->mBuffers[1].mNumberChannels = 2; Check(!MSBDMixLayoutMatches(&ipad, 100, b.abl), "shape: a buffer with 2 channels does not"); b.abl->mBuffers[1].mNumberChannels = 1;
        void *d = b.abl->mBuffers[1].mData; b.abl->mBuffers[1].mData = NULL; Check(!MSBDMixLayoutMatches(&ipad, 100, b.abl), "shape: a buffer with no data does not"); b.abl->mBuffers[1].mData = d;
        b.abl->mNumberBuffers = 1; Check(!MSBDMixLayoutMatches(&ipad, 100, b.abl), "shape: one buffer for two channels does not"); b.abl->mNumberBuffers = 2;
        Check(!MSBDMixLayoutMatches(&ipad, 0, b.abl) && !MSBDMixLayoutMatches(&ipad, 100, NULL), "shape: no frames, no list: no");
        Free(&b);

        // the gain: clamped to 0...1, ramped per frame (every channel of a frame the same), full level after an untouched buffer
        MSBDMixScaleState s = MSBD_MIX_SCALE_STATE_INIT;
        AudioStreamBasicDescription st2 = F32(48000, 2, 0);
        gUnit.out = st2; gUnit.failOut = 0; gUnit.readsOut = 0;
        Bufs c = Make(&st2, 64); Fill(&c, 0.01);
        Check(MSBDMixScaleRender(&s, 2.0f, 64, c.abl, MAReadOutputFormat, &gUnit) == 0 && gUnit.readsOut == 0, "a level above 1 counts as 1: nothing done, nothing read");
        int r = MSBDMixScaleRender(&s, 0.5f, 64, c.abl, MAReadOutputFormat, &gUnit);
        int perFrame = 1, falls = 1; double lastG = 2;
        for (UInt32 i = 0; i < 64; i++) {
            double gl = Read(&c, i, 0) / c.ref[i * 2], gr = Read(&c, i, 1) / c.ref[i * 2 + 1];
            if (c.ref[i * 2] != 0 && fabs(gl - gr) > 1e-5) perFrame = 0;
            if (c.ref[i * 2] != 0) { if (gl > lastG + 1e-5) falls = 0; lastG = gl; }
        }
        Check(r == 1 && perFrame && falls, "0.5 after full level on interleaved stereo: scaled (%d), left and right get the same gain in every frame, the gain only falls", r);
        Check(fabs(Read(&c, 1, 0) / c.ref[2] - (1.0 - 0.5 / 64)) < 1e-4, "  ... ramp from 1.0 at the first frame (frame 1 at %.4f)", Read(&c, 1, 0) / c.ref[2]);
        Free(&c);
        Bufs z = Make(&st2, 64); Fill(&z, 0.01);
        MSBDMixScaleRender(&s, NAN, 64, z.abl, MAReadOutputFormat, &gUnit);
        Bufs z2 = Make(&st2, 64); Fill(&z2, 0.01);
        MSBDMixScaleRender(&s, NAN, 64, z2.abl, MAReadOutputFormat, &gUnit);
        int zero = 1; for (UInt32 i = 0; i < 64; i++) if (Read(&z2, i, 0) != 0 || Read(&z2, i, 1) != 0) zero = 0;
        Check(zero, "a level that is not a number counts as 0 (silent), never louder");
        Free(&z); Free(&z2);
        // after an untouched buffer the next scaled one starts at full level (no step down in the middle of a sound)
        s = (MSBDMixScaleState)MSBD_MIX_SCALE_STATE_INIT; gUnit.out = ipad; gUnit.readsOut = 0;
        Bufs p = Make(&ipad, 64); Fill(&p, 0.01); MSBDMixScaleRender(&s, 0.5f, 64, p.abl, MAReadOutputFormat, &gUnit); Free(&p);
        Bufs p2 = Make(&ipad, 64); Fill(&p2, 0.01); MSBDMixScaleRender(&s, 0.5f, 64, p2.abl, MAReadOutputFormat, &gUnit); Free(&p2);
        AudioStreamBasicDescription mono = F32(48000, 1, NI);
        Bufs q = Make(&mono, 64); Fill(&q, 0.01);
        Check(MSBDMixScaleRender(&s, 0.5f, 64, q.abl, MAReadOutputFormat, &gUnit) == -1 && s.lastGain == 1.0f, "an untouched buffer (another shape) sets the last gain to full level");
        Free(&q);
        gUnit.out = mono;
        Bufs q2 = Make(&mono, 64); Fill(&q2, 0.01);
        Check(MSBDMixScaleRender(&s, 0.5f, 64, q2.abl, MAReadOutputFormat, &gUnit) == 1 && fabs(Read(&q2, 0, 0) / q2.ref[0] - 1.0) < 1e-5 && s.lastGain == 0.5f, "  ... so the next scaled one ramps from 1.0 (first frame at %.4f) to 0.5", Read(&q2, 0, 0) / q2.ref[0]);
        Free(&q2);
        // reads: once while it matches; MSBDMixScaleForget reads again
        s = (MSBDMixScaleState)MSBD_MIX_SCALE_STATE_INIT; gUnit.out = ipad; gUnit.readsOut = 0;
        for (int n = 0; n < 100; n++) { Bufs m = Make(&ipad, 128); Fill(&m, 0.01); MSBDMixScaleRender(&s, 0.3f, 128, m.abl, MAReadOutputFormat, &gUnit); Free(&m); }
        Check(gUnit.readsOut == 1, "100 matching buffers: the format read once (%d)", gUnit.readsOut);
        MSBDMixScaleForget(&s);
        { Bufs m = Make(&ipad, 128); Fill(&m, 0.01); MSBDMixScaleRender(&s, 0.3f, 128, m.abl, MAReadOutputFormat, &gUnit); Free(&m); }
        Check(gUnit.readsOut == 2, "  ... after MSBDMixScaleForget read again (%d)", gUnit.readsOut);
        // a shape that never matches after a fresh read: read again every MSBD_MIX_SCALE_REREAD buffers
        s = (MSBDMixScaleState)MSBD_MIX_SCALE_STATE_INIT; gUnit.readsOut = 0;
        for (int n = 0; n < 600; n++) { Bufs m = Make(&mono, 128); Fill(&m, 0.01); MSBDMixScaleRender(&s, 0.3f, 128, m.abl, MAReadOutputFormat, &gUnit); Free(&m); }
        Check(MSBD_MIX_SCALE_REREAD == 256 && gUnit.readsOut == 4, "600 buffers of another shape: read at the first, the second, the 257th and the 513th (%d reads)", gUnit.readsOut);
        // unreadable: an unknown format, untouched, tried again later
        s = (MSBDMixScaleState)MSBD_MIX_SCALE_STATE_INIT; gUnit.readsOut = 0; gUnit.failOut = 1;
        int un = 1; for (int n = 0; n < 300; n++) { Bufs m = Make(&ipad, 128); Fill(&m, 0.01); if (MSBDMixScaleRender(&s, 0.3f, 128, m.abl, MAReadOutputFormat, &gUnit) != -1) un = 0; Free(&m); }
        gUnit.failOut = 0;
        Check(un && gUnit.readsOut == 3, "an output format that cannot be read: 300 buffers untouched, tried at the first, the second and the 257th (%d)", gUnit.readsOut);
        { Bufs m = Make(&ipad, 128); Fill(&m, 0.01); for (int n = 0; n < 256; n++) MSBDMixScaleRender(&s, 0.3f, 128, m.abl, MAReadOutputFormat, &gUnit); Free(&m); }
        Check(s.known && s.fmt.mFormatID == kAudioFormatLinearPCM && s.lastGain == 0.3f, "  ... once it can be read, scaled again");
    }
#else
    Check(0, "common/MixAudioScale.h is not in this tree");
#endif

    printf("%s: %d/%d\n", fails ? "test-mixaudioscale FAILED" : "test-mixaudioscale: all pass", checks - fails, checks);
    return fails > 99 ? 99 : fails;
}
