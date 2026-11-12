// DisplayScale.h -- More Space: a display's scales as iPadOS offers them (MacStatusBar&Dock 1.8.7 commit 13; plans/design-1.8.7-displays.md
// sections 4 and 8). Plain C: SpringBoard's scale choice (statusbar/DisplayScale.h), Settings' Displays page and the Mac test
// (tools/test-displayscale.c) share it.
//  - Apple's own call, no hooks: SpringBoard's external display service lists the scales a display supports as a bitmask (SBSConnectedDisplayInfo
//    -supportedScales: bit n = scale n) and the one in use (-displayModeSettings: "scale: .Standard; overscan: .None"). Only a listed scale is ever
//    made: SpringBoardServices asserts on any other (0 aborted SpringBoard, S2 on the A12Z, 11 Nov). The A12Z's 4K TV and the iPad 2's 1080p TV list
//    one (mask 2, .Standard): no row there.
//  - The row (Resolution) only where two or more are listed; its choices in the scales' order, named from Apple's own names (.Standard = Default;
//    a name with Larger or Zoom = Larger Text, with Space or Dense = More Space; any other: Apple's name as it is).
//  - A change is kept or reverted (15 s, reverting by itself), and SpringBoard keeps what it was before the change until it is kept, reverted, or
//    60 s have passed: a start within 2 min of a change that was never kept or reverted (the scale took SpringBoard down) sets the old scale back.
//  - The overscan tip ("If the edges are cut off...") where iPadOS does not shrink the picture for the TV (overscan .None).
#pragma once
#include <string.h>
#include <stdbool.h>
#include <stdio.h>

#define MSBD_DISP_SCALE_MAX 15            // (bits 1-15: scale 0 is no scale, SpringBoardServices asserts on it)
#define MSBD_DISP_SCALE_KEEP_SECONDS 15   // (the keep-or-revert question reverts by itself after this)
#define MSBD_DISP_SCALE_CRASH_WINDOW 120  // (a start this soon after an unresolved change: the change is taken back)
#define MSBD_DISP_SCALE_DROP_AFTER 60     // (an unresolved record older than this, SpringBoard still running: dropped)
#define MSBD_DISP_SCALE_PENDING_KEY "scalePending"   // (part disp: {old, new, at})
#define MSBD_DISP_SCALE_REQUEST_KEY "scaleRequest"   // (part disp: a scale asked for by Settings' page; SpringBoard sets it and deletes the key)

// The scales listed in a mask, in order (at most max into out): how many.
static inline int MSBDDispScaleListed(unsigned long long mask, int *out, int max) {
    int n = 0;
    for (int v = 1; v <= MSBD_DISP_SCALE_MAX; v++) if (mask & (1ULL << v)) { if (out && n < max) out[n] = v; n++; }
    return n;
}
static inline bool MSBDDispScaleIsListed(unsigned long long mask, int scale) { return scale >= 1 && scale <= MSBD_DISP_SCALE_MAX && (mask & (1ULL << scale)) != 0; }
// The Resolution row: only where there is a choice (two or more listed).
static inline bool MSBDDispScaleRowWanted(unsigned long long mask) { return MSBDDispScaleListed(mask, NULL, 0) >= 2; }
// May `want` be set: listed and not the one in use (an unlisted value is never made).
static inline bool MSBDDispScaleCanSet(unsigned long long mask, int current, int want) { return MSBDDispScaleIsListed(mask, want) && want != current; }

// Apple's name of a field in SBSDisplayModeSettings' description ("<SBSDisplayModeSettings: 0x..; scale: .Standard; overscan: .None>"): "Standard".
// false when the field is not there.
static inline bool MSBDDispScaleFieldName(const char *desc, const char *field, char *out, size_t n) {
    if (!desc || !field || !out || n < 2) return false;
    out[0] = 0;
    char pat[40];
    snprintf(pat, sizeof pat, "%s: .", field);
    const char *p = strstr(desc, pat);
    if (!p) return false;
    p += strlen(pat);
    size_t k = 0;
    while (p[k] && ((p[k] >= 'A' && p[k] <= 'Z') || (p[k] >= 'a' && p[k] <= 'z') || (p[k] >= '0' && p[k] <= '9')) && k + 1 < n) { out[k] = p[k]; k++; }
    out[k] = 0;
    return k > 0;
}
static inline bool MSBDDispHas(const char *s, const char *w) { return s && w && strstr(s, w) != NULL; }
// The choice's title from Apple's name: Standard is Default; Larger / Zoom Larger Text; Space / Dense More Space; else NULL (show Apple's name).
static inline const char *MSBDDispScaleTitle(const char *appleName) {
    if (!appleName || !*appleName) return NULL;
    if (strcmp(appleName, "Standard") == 0) return "Default";
    if (MSBDDispHas(appleName, "Larger") || MSBDDispHas(appleName, "Zoom")) return "Larger Text";
    if (MSBDDispHas(appleName, "Space") || MSBDDispHas(appleName, "Dense")) return "More Space";
    return NULL;
}
// The overscan tip: where iPadOS does not shrink the picture for the display (its overscan compensation .None), a TV may cut the edges off.
static inline bool MSBDDispOverscanTip(const char *overscanName) { return overscanName && strcmp(overscanName, "None") == 0; }

// At SpringBoard's start, with a change's record {at} left: 1 = set the old scale back (SpringBoard started within 2 min of a change never kept or
// reverted), 2 = drop the record (older), 0 = no record.
enum { kMSBDDispScaleStartNothing = 0, kMSBDDispScaleStartRevert = 1, kMSBDDispScaleStartDrop = 2 };
static inline int MSBDDispScaleAtStart(int hasPending, long now, long at) {
    if (!hasPending) return kMSBDDispScaleStartNothing;
    long age = now - at;
    return (age >= 0 && age <= MSBD_DISP_SCALE_CRASH_WINDOW) ? kMSBDDispScaleStartRevert : kMSBDDispScaleStartDrop;
}
// While running: the keep-or-revert question's answer once its time is up (no answer: revert), and when an unresolved record is dropped.
static inline bool MSBDDispScaleRevertsNow(int answered, long now, long asked) { return !answered && now - asked >= MSBD_DISP_SCALE_KEEP_SECONDS; }
static inline bool MSBDDispScaleDropNow(long now, long at) { return now - at >= MSBD_DISP_SCALE_DROP_AFTER; }
// A set's outcome, read back (review: the set's completion is taken as "answered" only, its parameters never read): done when the display's scale in
// use is the one asked for; a display not listed after the tries (a scale change can make it reconnect): unknown, counted as done, so the
// keep-or-revert question is still asked and nothing stays unasked.
static inline bool MSBDDispScaleSetTook(int listed, int now, int want) { return !listed || now == want; }
// A revert's try (the question's Revert or its time up, the start's revert): done when taken back, or when the display is listed and nothing is left to
// take back (the old scale no longer listed, or already in use).
// The start's revert of a change never kept, after a try: true = the record goes (taken back; or the display listed and nothing to take back: the old
// scale no longer listed, or already in use; or the 2-minute window over), false = kept, to try again when the display connects (not listed yet:
// SpringBoard's service not serving yet, or the TV not back yet a few seconds into a respring; or the set refused).
static inline bool MSBDDispScaleRevertDone(int took, int listed, unsigned long long mask, int current, int old) {
    return took || (listed && (!MSBDDispScaleIsListed(mask, old) || current == old));
}
static inline bool MSBDDispScaleStartRevertDrop(int took, int listed, unsigned long long mask, int current, int old, long now, long at) {
    return MSBDDispScaleRevertDone(took, listed, mask, current, old) || MSBDDispScaleAtStart(1, now, at) != kMSBDDispScaleStartRevert;
}
