// AppWindowSize.h: App Window Sizes (1.8.8, KT 12 Nov: Settings > Windows & Multitasking > Window Size > App Window Sizes), a launch size per app.
// Plain C on CoreFoundation and CoreGraphics beside WindowSize.h, so the Mac test (tools/test-appwindowsize.sh) runs this very code; SpringBoard
// (StatusBar.x DMLoadPrefs, DMOpeningWindowFrameFor, DMSMOpeningFrameIn) and Settings (MSBAppSizesController.m) both read it.
//  - An app's choice: Small, Medium, Large, Fill or iPhone, stored as one dictionary `appWindowSizes` in com.besiktasliseba.macstatusbar (bundle
//    id -> "small" / "medium" / "large" / "fill" / "iphone"). Absent: no app has a size. Settings removes the key with the last app.
//  - Which size wins (design-1.8.8-app-sizes.md 1.1), for a window that opens with no place of its own on the display it opens on: the app's own
//    choice, else that display's New Windows Open at Fill, else that display's Window Size. The app's choice beats both general rules, Open at
//    Fill included. An app with no entry opens exactly as in 1.8.7.
//  - Medium is the middle place on every engine (MSBDWindowCenterIn, the window MSBDWindowSizeDefault opens; Aerial 3.0's own Default is its
//    own parity item in release-1.8.8.md); Small and Large are Window Size's; Fill is the engine's Fill layout (the caller's, as Open at Fill);
//    iPhone is a phone held upright (MSBDWindowPhoneIn).
//  - Fit to Window (1.3): a window opening at the app's own size, or at Fill, is left out of the tiles (each engine's free windows).
//  - The read rule (3.1): a key that is not a string of 1-255 characters, or a value that is not one of the five texts, counts as no entry; a
//    stored value that is not a dictionary: no app at all; at most 200 entries read, keys in sorted order. Nothing is clamped or rewritten.
//  - The forget on change (1.6, amendment 1 of round 4): the bundles whose choice differs between the table SpringBoard held and the new one;
//    SpringBoard's first read only sets the baseline (MSBDAppSizesToForget with the baseline not yet set answers no bundle).
#ifndef MSBD_APP_WINDOW_SIZE_H
#define MSBD_APP_WINDOW_SIZE_H
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <string.h>
#include "WindowSize.h"

#define kMSBDAppWindowSizesKey "appWindowSizes"   // (com.besiktasliseba.macstatusbar: a dictionary, bundle id -> choice text; absent: no app)
#define kMSBDAppWindowSizesMax 200                // (the most entries read, and the most Settings lists)
#define kMSBDAppBundleMaxLength 255               // (a key longer than this, or empty, is no entry)
#define kMSBDPhoneW 393.0                         // (the app area of an iPhone 14 Pro, 15 and 16, held upright)
#define kMSBDPhoneH 852.0

// An app's choice (the stored text); None: no entry, the app follows Window Size and Open at Fill.
enum { MSBDAppSizeNone = -1, MSBDAppSizeSmall = 1, MSBDAppSizeLarge = 2, MSBDAppSizeMedium = 3, MSBDAppSizeFill = 4, MSBDAppSizeIPhone = 5 };
// What opens (MSBDOpeningSize): WindowSize.h's MSBDWindowSizeDefault 0 / Small 1 / Large 2, or one of these. An app at Medium opens Default.
enum { kMSBDOpenFill = 4, kMSBDOpenIPhone = 5 };

static inline bool MSBDAppSizeValid(int s) { return s == MSBDAppSizeSmall || s == MSBDAppSizeLarge || s == MSBDAppSizeMedium || s == MSBDAppSizeFill || s == MSBDAppSizeIPhone; }

// The read rule on one stored text: the five texts exactly (lower case); anything else (none, "default", "Small", a future "custom:60x80"): None.
static inline int MSBDAppSizeFromName(const char *text) {
    if (!text) return MSBDAppSizeNone;
    if (!strcmp(text, "small")) return MSBDAppSizeSmall;
    if (!strcmp(text, "medium")) return MSBDAppSizeMedium;
    if (!strcmp(text, "large")) return MSBDAppSizeLarge;
    if (!strcmp(text, "fill")) return MSBDAppSizeFill;
    if (!strcmp(text, "iphone")) return MSBDAppSizeIPhone;
    return MSBDAppSizeNone;
}
// ... from the stored value: a string as above; anything else (a number, a dictionary, a text too long to be one of the five): None.
static inline int MSBDAppSizeFromStored(CFTypeRef v) {
    char text[16] = "";
    if (!v || CFGetTypeID(v) != CFStringGetTypeID() || !CFStringGetCString((CFStringRef)v, text, sizeof text, kCFStringEncodingUTF8)) return MSBDAppSizeNone;
    return MSBDAppSizeFromName(text);
}
// The stored text of a choice (Settings writes it, SpringBoard logs it); None or anything else: NULL (nothing to write).
static inline const char *MSBDAppSizeName(int s) {
    switch (s) {
        case MSBDAppSizeSmall: return "small";
        case MSBDAppSizeMedium: return "medium";
        case MSBDAppSizeLarge: return "large";
        case MSBDAppSizeFill: return "fill";
        case MSBDAppSizeIPhone: return "iphone";
        default: return NULL;
    }
}

// ---- the table: the stored dictionary through the read rule (SpringBoard's gAppSizes, Settings' list) ----------------------------------------
// A key the read rule takes: a string of 1-255 characters.
static inline bool MSBDAppBundleKeyValid(CFTypeRef k) {
    if (!k || CFGetTypeID(k) != CFStringGetTypeID()) return false;
    CFIndex n = CFStringGetLength((CFStringRef)k);
    return n >= 1 && n <= kMSBDAppBundleMaxLength;
}
static inline CFComparisonResult MSBDAppBundleCompare(const void *a, const void *b, void *ctx) { (void)ctx; return CFStringCompare((CFStringRef)a, (CFStringRef)b, 0); }
// The table read from the stored value: a new dictionary (bundle id -> CFNumber of the choice), never NULL; absent or not a dictionary: empty.
// Keys in sorted order; at most 200 entries read. bad: the entries that count as none (a bad key or value); over: the good ones past 200;
// wrongType: the type of a stored value that is there but is not a dictionary (a number, a text, an array: no app at all), else 0. Any of the
// three may be NULL. The caller releases the table and logs them once. (1.8.8 F3: a stored value of another type was read as no app with nothing
// to log, as a dictionary with no entries: the G1 row's number on the A12Z left only "0 apps with a size of their own" in the log.)
static inline CFDictionaryRef MSBDAppSizesRead(CFTypeRef stored, int *bad, int *over, CFTypeID *wrongType) {
    if (bad) *bad = 0;
    if (over) *over = 0;
    if (wrongType) *wrongType = stored && CFGetTypeID(stored) != CFDictionaryGetTypeID() ? CFGetTypeID(stored) : 0;
    CFMutableDictionaryRef t = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (!stored || CFGetTypeID(stored) != CFDictionaryGetTypeID()) return t;
    CFDictionaryRef d = (CFDictionaryRef)stored;
    CFIndex n = CFDictionaryGetCount(d);
    if (n <= 0) return t;
    const void **keys = (const void **)calloc((size_t)n, sizeof(void *)), **vals = (const void **)calloc((size_t)n, sizeof(void *));
    if (!keys || !vals) { free(keys); free(vals); return t; }
    CFDictionaryGetKeysAndValues(d, keys, vals);
    CFMutableArrayRef good = CFArrayCreateMutable(kCFAllocatorDefault, n, &kCFTypeArrayCallBacks);
    for (CFIndex i = 0; i < n; i++) {
        if (MSBDAppBundleKeyValid(keys[i]) && MSBDAppSizeFromStored((CFTypeRef)vals[i]) != MSBDAppSizeNone) CFArrayAppendValue(good, keys[i]);
        else if (bad) (*bad)++;
    }
    free(keys); free(vals);
    CFIndex g = CFArrayGetCount(good);
    CFArraySortValues(good, CFRangeMake(0, g), MSBDAppBundleCompare, NULL);
    for (CFIndex i = 0; i < g; i++) {
        if (i >= kMSBDAppWindowSizesMax) { if (over) (*over)++; continue; }
        CFStringRef k = (CFStringRef)CFArrayGetValueAtIndex(good, i);
        int s = MSBDAppSizeFromStored(CFDictionaryGetValue(d, k));
        CFNumberRef num = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &s);
        CFDictionarySetValue(t, k, num);
        CFRelease(num);
    }
    CFRelease(good);
    return t;
}
// An app's choice in a read table; no table, no bundle or no entry: None.
static inline int MSBDAppSizeIn(CFDictionaryRef table, CFStringRef bundle) {
    if (!table || !bundle || CFGetTypeID(bundle) != CFStringGetTypeID()) return MSBDAppSizeNone;
    CFTypeRef v = CFDictionaryGetValue(table, bundle);
    int s = MSBDAppSizeNone;
    if (!v || CFGetTypeID(v) != CFNumberGetTypeID() || !CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &s)) return MSBDAppSizeNone;
    return MSBDAppSizeValid(s) ? s : MSBDAppSizeNone;
}

// ---- which size wins (1.1) and whether Fit leaves the window out (1.3) ---------------------------------------------------------------------
// What opens, from the app's choice (None: no entry) and that display's Window Size and Open at Fill: the app's own choice first (Medium opens
// MSBDWindowSizeDefault, the middle place), else Fill when Open at Fill is on, else Window Size. With app = None it is 1.8.7's answer on every input.
static inline int MSBDOpeningSize(int app, int windowSize, bool fillOn) {
    switch (app) {
        case MSBDAppSizeSmall: return MSBDWindowSizeSmall;
        case MSBDAppSizeMedium: return MSBDWindowSizeDefault;
        case MSBDAppSizeLarge: return MSBDWindowSizeLarge;
        case MSBDAppSizeFill: return kMSBDOpenFill;
        case MSBDAppSizeIPhone: return kMSBDOpenIPhone;
        default: return fillOn ? kMSBDOpenFill : windowSize;
    }
}
// The window opens free (Fit to Window leaves it out of the tiles, no side question): no place of its own, not asked to a frame, and the app's
// own size or Fill. With app = None it is MSBDNewWindowAtFill(fillOn, ownPlace, askedFor) on every input.
static inline bool MSBDOpensFree(int app, bool fillOn, bool ownPlace, bool askedFor) {
    return !ownPlace && !askedFor && (MSBDAppSizeValid(app) || fillOn);
}
// Aerial 3.0 keeps its own opening frame only when what opens is Default by Window Size itself (no app entry, Open at Fill off), as 1.8.7's
// a3Sized; an app the user put at Medium is not plain Default, so it gets the middle place there too.
static inline bool MSBDOpeningIsPlainDefault(int app, int windowSize, bool fillOn) {
    return !MSBDAppSizeValid(app) && !fillOn && windowSize == MSBDWindowSizeDefault;
}

// ---- the frames (2, 2.1) ------------------------------------------------------------------------------------------------------------------
// A desktop the frames can be cut from: not null, every number finite, a width and a height above zero as given (a negative size is not one).
static inline bool MSBDAppDesktopIsOne(CGRect u) {
    return !CGRectIsNull(u) && isfinite(u.origin.x) && isfinite(u.origin.y) && isfinite(u.size.width) && isfinite(u.size.height) && u.size.width > 0.0 && u.size.height > 0.0;
}
// The iPhone choice in the desktop u (the area between the menu bar and the Dock), the whole window with our title bar of `bar` on top: the app
// area 393 x 852 when it fits, else scaled down at the phone's aspect until it fits in 96% of the desktop (Large's margin) under the bar, rounded
// to whole points; never narrower or shorter than the engine's whole-window minimum `min` (320 pt: Slide Over's width, every engine's minimum);
// at most the desktop; centred in it. Upright in both orientations and for every app. A desktop that is not one (null, empty, not finite) or a
// bar that is not one: CGRectNull (the callers keep the engine's own frame).
static inline CGRect MSBDWindowPhoneIn(CGRect u, double bar, CGSize min) {
    if (!MSBDAppDesktopIsOne(u) || !isfinite(bar) || bar < 0.0 || !isfinite(min.width) || !isfinite(min.height)) return CGRectNull;
    double k = fmin(1.0, fmin((0.96 * u.size.width) / kMSBDPhoneW, (0.96 * u.size.height - bar) / kMSBDPhoneH));
    if (!(k > 0.0)) k = 0.0;
    double appW = round(kMSBDPhoneW * k), appH = round(kMSBDPhoneH * k);
    double left = ceil(u.origin.x), top = ceil(u.origin.y), right = floor(CGRectGetMaxX(u)), bottom = floor(CGRectGetMaxY(u));
    double w = fmin(fmax(appW, min.width), right - left), h = fmin(fmax(appH + bar, min.height), bottom - top);
    if (!(w > 0.0) || !(h > 0.0)) return CGRectNull;
    double x = fmax(left, fmin(round(u.origin.x + (u.size.width - w) / 2.0), right - w));
    double y = fmax(top, fmin(round(u.origin.y + (u.size.height - h) / 2.0), bottom - h));
    return CGRectMake(x, y, w, h);
}
// The window for what opens (MSBDOpeningSize's answer) in the desktop u of a screen of `screen`: Default (Window Size's, or an app at Medium),
// Small and Large Window Size's own (MSBDWindowSizeFrameIn, the middle place's top `top`, the engine's minimum `min`); iPhone MSBDWindowPhoneIn
// (our title bar `bar`). Fill is the engine's own Fill layout, which the caller asks before this (as Open at Fill): here, for anything else
// and for a desktop that is not one, CGRectNull. Stage Manager's DMSMNewWindowFrameIn is MSBDWindowSizeFrameIn with Stage Manager's minimum,
// so for Default, Small and Large it is this function there.
static inline CGRect MSBDAppWindowFrameIn(int opening, CGRect u, CGSize screen, double top, double bar, CGSize min) {
    if (!MSBDAppDesktopIsOne(u)) return CGRectNull;   // (one desktop check for every choice; WindowSize.h's own takes a NaN or negative desktop)
    switch (opening) {
        case MSBDWindowSizeDefault: return MSBDWindowSizeFrameIn(MSBDWindowSizeDefault, u, screen, top, min);
        case MSBDWindowSizeSmall: return MSBDWindowSizeFrameIn(MSBDWindowSizeSmall, u, screen, top, min);
        case MSBDWindowSizeLarge: return MSBDWindowSizeFrameIn(MSBDWindowSizeLarge, u, screen, top, min);
        case kMSBDOpenIPhone: return MSBDWindowPhoneIn(u, bar, min);
        default: return CGRectNull;
    }
}

// ---- the forget on change (1.6, round 4 amendment 1) ---------------------------------------------------------------------------------------
// The bundles whose choice differs between two read tables (an entry added, changed or removed), sorted. Both tables are SpringBoard's
// (never NULL: an absent key reads as an empty table); a NULL one answers no bundle, so a slip can never forget every app. A new array, never
// NULL; the caller releases it.
static inline CFArrayRef MSBDAppSizesChanged(CFDictionaryRef before, CFDictionaryRef after) {
    CFMutableArrayRef out = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    if (!before || !after) return out;
    CFDictionaryRef tables[2] = { before, after };
    for (int t = 0; t < 2; t++) {
        CFIndex n = CFDictionaryGetCount(tables[t]);
        if (n <= 0) continue;
        const void **keys = (const void **)calloc((size_t)n, sizeof(void *));
        if (!keys) continue;
        CFDictionaryGetKeysAndValues(tables[t], keys, NULL);
        for (CFIndex i = 0; i < n; i++) {
            if (!keys[i] || CFGetTypeID(keys[i]) != CFStringGetTypeID()) continue;
            CFStringRef k = (CFStringRef)keys[i];
            if (t == 1 && CFDictionaryContainsKey(before, k)) continue;   // (a bundle in both tables is compared once, from `before`)
            if (MSBDAppSizeIn(before, k) != MSBDAppSizeIn(after, k)) CFArrayAppendValue(out, k);
        }
        free(keys);
    }
    CFArraySortValues(out, CFRangeMake(0, CFArrayGetCount(out)), MSBDAppBundleCompare, NULL);
    return out;
}
// What DMLoadPrefs forgets: nothing on SpringBoard's first read since the start (baselineSet NO: that read only sets the table, so a respring
// forgets no place), else the bundles that changed. A new array, never NULL; the caller releases it.
static inline CFArrayRef MSBDAppSizesToForget(bool baselineSet, CFDictionaryRef before, CFDictionaryRef after) {
    if (!baselineSet) return CFArrayCreate(kCFAllocatorDefault, NULL, 0, &kCFTypeArrayCallBacks);
    return MSBDAppSizesChanged(before, after);
}

// ---- Settings (statusbar/macstatusbarprefs/MSBAppSizesController.m, design 3.2 with the closing round 4 amendments) ----------------------------
// The five choices in the order an app's page lists them (i 0-4); anything else: None.
static inline int MSBDAppSizeChoiceAt(int i) {
    switch (i) {
        case 0: return MSBDAppSizeSmall;
        case 1: return MSBDAppSizeMedium;
        case 2: return MSBDAppSizeLarge;
        case 3: return MSBDAppSizeFill;
        case 4: return MSBDAppSizeIPhone;
        default: return MSBDAppSizeNone;
    }
}
// A choice's title (the app's page and the list's value on the right); None or anything else: NULL.
static inline const char *MSBDAppSizeTitle(int s) {
    switch (s) {
        case MSBDAppSizeSmall: return "Small";
        case MSBDAppSizeMedium: return "Medium";
        case MSBDAppSizeLarge: return "Large";
        case MSBDAppSizeFill: return "Fill";
        case MSBDAppSizeIPhone: return "iPhone";
        default: return NULL;
    }
}
// The footer under an app's "Opens At" by its choice (None: nothing picked yet); NULL: no footer. Small, Medium and Large have none: the names say
// it (amendment 2: nothing about Window Size's Default, which is not the middle place on Aerial 3.0).
static inline const char *MSBDAppSizeFooter(int s) {
    switch (s) {
        case MSBDAppSizeNone: return "Pick the size this app opens at.";
        case MSBDAppSizeFill: return "The window fills the desktop.";
        case MSBDAppSizeIPhone: return "A tall window the shape of an iPhone. Most apps show their iPhone layout in it. If the screen is too small, it's made smaller to fit.";
        default: return NULL;
    }
}
// The value on the App Window Sizes row: "1 App", "2 Apps"; no app: "" (nothing shown).
static inline void MSBDAppSizesCountText(CFIndex n, char *out, size_t len) {
    if (!out || !len) return;
    if (n <= 0) out[0] = 0;
    else snprintf(out, len, n == 1 ? "%ld App" : "%ld Apps", (long)n);
}
// Add App takes another app while fewer than 200 are listed (the read rule reads 200 at most, so every app Settings lists is one SpringBoard reads).
static inline bool MSBDAppSizesCanAdd(CFIndex listed) { return listed >= 0 && listed < kMSBDAppWindowSizesMax; }
// Settings' one write: the stored value with one app's entry set to `choice`, or removed with None. Every other entry stays as stored, one this
// release cannot read too (a future choice kept through a downgrade, 3.1). A stored value that is not a dictionary counts as none. A bundle the read
// rule refuses, or a choice that is neither one of the five nor None: the entries as they are. NULL when no entry is left: Settings then removes
// the key (never an empty dictionary). The caller releases it.
static inline CFDictionaryRef MSBDAppSizesWith(CFTypeRef stored, CFStringRef bundle, int choice) {
    CFMutableDictionaryRef d = stored && CFGetTypeID(stored) == CFDictionaryGetTypeID()
        ? CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, (CFDictionaryRef)stored)
        : CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (!d) return NULL;
    if (bundle && MSBDAppBundleKeyValid(bundle)) {
        const char *name = MSBDAppSizeName(choice);
        if (name) {
            CFStringRef v = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingUTF8);
            if (v) { CFDictionarySetValue(d, bundle, v); CFRelease(v); }
        } else if (choice == MSBDAppSizeNone) CFDictionaryRemoveValue(d, bundle);
    }
    if (CFDictionaryGetCount(d) == 0) { CFRelease(d); return NULL; }
    return d;
}

#endif
