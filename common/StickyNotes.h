// StickyNotes.h -- Sticky Notes on the desktop (1.8.8.1): the rules, Foundation and CoreGraphics only, so the Mac test (tools/test-stickynotes.sh)
// runs this very code. The notes themselves -- their views, the typing, the store's file -- are statusbar/DesktopNotes.h.
//  - Colours: macOS Stickies' six (its asset catalog, sRGB): the paper and the band at its top. The same in Dark Mode, as on a Mac (paper is paper).
//  - A note keeps its own size in points (only a resize changes it) and its place as its centre's share of the desktop's places area, as an icon
//    does. Shown, it is kept inside the free area (under the menu bar, above the Dock), at least the minimum size, and clear of the Home Screen's
//    app icons, widgets and page dots: they draw over it and take its touches.
//  - The store: one binary plist {version 1, notes [{id, color, x, y, w, h, text}]}, the array's order the stacking order (last on top). A store that
//    could not be read is never taken for an empty one: nothing is shown and nothing is written until a read worked or found no file.
//  - Caps: 30 notes shown (any more are kept as stored), 10,000 characters a note (a longer text is cut, never inside a character).
//  - Privacy: nothing here logs. Note text is only ever a value in the store, never a key, a name, a format or a message.
#ifndef MSBD_STICKY_NOTES_H
#define MSBD_STICKY_NOTES_H
#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <errno.h>
#include <math.h>

#define MSBD_NOTES_MAX 30             // (notes shown; New Sticky Note is greyed at this many)
#define MSBD_NOTE_TEXT_MAX 10000      // (characters a note keeps: a paste is cut to fit)
#define MSBD_NOTE_DRAW_MAX 8000       // (characters an idle note draws: more than any note on any iPad can show)
#define MSBD_NOTE_W 220.0
#define MSBD_NOTE_H 180.0
#define MSBD_NOTE_MIN_W 120.0
#define MSBD_NOTE_MIN_H 80.0
#define MSBD_NOTE_MAX_SIDE 4096.0
#define MSBD_NOTE_BAND 6.0            // (the band at the top, in the colour's darker shade)
#define MSBD_NOTE_LIFT_GAP 8.0        // (a note lifted over the keyboard ends this far above it)
#define MSBD_NOTE_CLEAR_STEP 8.0      // (MSBDStickyPlaceClear's rings)
#define MSBD_NOTE_CLEAR_TESTS 60000L  // (... and its cap of rect tests a note)
#define MSBD_NOTES_VERSION 1
#define MSBD_NOTE_TRASH_ORIGIN @"sticky-note"                 // (Finder's origin attribute of a note's Trash file: a marker, never a path)
#define MSBD_NOTE_TRASH_ATTR "com.besiktasliseba.stickynote"   // (... and its look: "1 <color> <w> <h>", never text)
#define MSBD_NOTE_TRASH_NAME @"Sticky Note.txt"

typedef struct { const char *name; unsigned body, band; } MSBDStickyColor;
static const MSBDStickyColor kMSBDStickyColors[] = {   // (Stickies' order; body / band ("Spine") from /System/Applications/Stickies.app's Assets.car)
    { "Yellow", 0xFEF49C, 0xFEEA3D }, { "Blue", 0xADF4FF, 0x89F0FF }, { "Green", 0xB2FFA1, 0x83FE83 },
    { "Pink", 0xFFC7C7, 0xFFB2B2 }, { "Purple", 0xB6CAFF, 0x9BB6FE }, { "Gray", 0xEEEEEE, 0xDADADA },
};
#define MSBD_NOTE_COLORS ((int)(sizeof(kMSBDStickyColors) / sizeof(kMSBDStickyColors[0])))
static inline int MSBDStickyColorIndex(id name) {   // (an unknown or missing colour reads as Yellow)
    if (![name isKindOfClass:[NSString class]]) return 0;
    for (int i = 0; i < MSBD_NOTE_COLORS; i++) if ([(NSString *)name isEqualToString:@(kMSBDStickyColors[i].name)]) return i;
    return 0;
}
static inline NSString *MSBDStickyColorName(int i) { return @(kMSBDStickyColors[i >= 0 && i < MSBD_NOTE_COLORS ? i : 0].name); }
static inline void MSBDStickyRGB(unsigned hex, CGFloat *r, CGFloat *g, CGFloat *b) { *r = ((hex >> 16) & 0xFF) / 255.0; *g = ((hex >> 8) & 0xFF) / 255.0; *b = (hex & 0xFF) / 255.0; }

// ---- where a note is shown ----
// Open interiors meet (edges that only touch do not), as the desktop's placer counts an icon over a rect (DesktopPlace.h DMPlacerOver).
static inline BOOL MSBDStickyRectsOverlap(CGRect a, CGRect b) {
    return CGRectGetMinX(a) < CGRectGetMaxX(b) && CGRectGetMaxX(a) > CGRectGetMinX(b) && CGRectGetMinY(a) < CGRectGetMaxY(b) && CGRectGetMaxY(a) > CGRectGetMinY(b);
}
// f moved inside the area (and made no larger than it).
static inline CGRect MSBDStickyClampInside(CGRect f, CGRect area) {
    f.size.width = MIN(f.size.width, area.size.width); f.size.height = MIN(f.size.height, area.size.height);
    f.origin.x = MAX(CGRectGetMinX(area), MIN(f.origin.x, CGRectGetMaxX(area) - f.size.width));
    f.origin.y = MAX(CGRectGetMinY(area), MIN(f.origin.y, CGRectGetMaxY(area) - f.size.height));
    return f;
}
// The note as shown: its stored size where it fits (at least the minimum, at most the area), centred at c, inside the area. A turn and back
// gives the same frame: nothing here changes what is stored.
static inline CGRect MSBDStickyFrameAt(CGRect area, CGPoint c, CGSize size) {
    CGFloat w = isfinite(size.width) ? size.width : MSBD_NOTE_W, h = isfinite(size.height) ? size.height : MSBD_NOTE_H;
    w = MIN(MAX(w, MSBD_NOTE_MIN_W), area.size.width); h = MIN(MAX(h, MSBD_NOTE_MIN_H), area.size.height);
    CGFloat cx = isfinite(c.x) ? c.x : CGRectGetMidX(area), cy = isfinite(c.y) ? c.y : CGRectGetMidY(area);
    return MSBDStickyClampInside(CGRectMake(cx - w / 2.0, cy - h / 2.0, w, h), area);
}
// The nearest frame of the same size, inside the area, over none of the rects (app icons, widgets, page dots): moved in 8 pt steps on growing
// square rings around it, nearest first. At most maxTests rect tests (a page full of app icons gives up early): then the nearest clear one found,
// else the frame kept inside the area. *tests: how many were made (the Mac test).
static inline CGRect MSBDStickyPlaceClear(CGRect frame, CGRect area, const CGRect *rects, int n, long maxTests, long *tests) {
    long done = 0;
    CGRect f0 = MSBDStickyClampInside(frame, area), best = CGRectNull;
    CGFloat bestD = CGFLOAT_MAX, step = MSBD_NOTE_CLEAR_STEP;
    int maxRing = (int)ceil(MAX(area.size.width, area.size.height) / step) + 1;
    for (int ring = 0; ring <= maxRing && done <= maxTests; ring++) {
        if (!CGRectIsNull(best) && (ring - 1) * step > bestD) break;   // (every point farther out is farther than the one found)
        for (int dy = -ring; dy <= ring && done <= maxTests; dy++) {
            BOOL edge = dy == -ring || dy == ring;
            for (int dx = -ring; dx <= ring && done <= maxTests; dx += (edge || ring == 0) ? 1 : 2 * ring) {
                CGRect c = MSBDStickyClampInside(CGRectOffset(f0, dx * step, dy * step), area);
                CGFloat d = hypot(c.origin.x - f0.origin.x, c.origin.y - f0.origin.y);
                if (d >= bestD) continue;
                BOOL clear = YES;
                for (int k = 0; k < n && clear; k++) { done++; if (MSBDStickyRectsOverlap(c, rects[k])) clear = NO; }
                if (clear) { best = c; bestD = d; }
            }
        }
    }
    if (tests) *tests = done;
    return CGRectIsNull(best) ? f0 : best;
}
// A new note: its top left corner at the pressed spot, the default size, then clear of the rects as above.
static inline CGRect MSBDStickyNewFrame(CGPoint press, CGRect area, const CGRect *rects, int n) {
    CGRect f = MSBDStickyClampInside(CGRectMake(press.x, press.y, MIN(MSBD_NOTE_W, area.size.width), MIN(MSBD_NOTE_H, area.size.height)), area);
    return MSBDStickyPlaceClear(f, area, rects, n, MSBD_NOTE_CLEAR_TESTS, NULL);
}
// A docked on-screen keyboard that would cover the note lifts it until its bottom is 8 pt above the keyboard, never above `top` (the free area's).
// A note still too tall for that: *inset is how much of it the keyboard covers, a bottom inset for its text. No keyboard, or clear of it: home.
static inline CGRect MSBDStickyLift(CGRect home, CGRect keyboard, CGFloat top, CGFloat *inset) {
    if (inset) *inset = 0;
    CGFloat line = CGRectGetMinY(keyboard) - MSBD_NOTE_LIFT_GAP;
    if (CGRectIsEmpty(keyboard) || CGRectGetMaxY(home) <= line) return home;
    CGRect f = home;
    f.origin.y = MIN(home.origin.y, MAX(top, line - home.size.height));   // (only ever up)
    CGFloat over = CGRectGetMaxY(f) - line;
    if (over > 0 && inset) *inset = over;
    return f;
}

// ---- the store ----
typedef enum { MSBDStickyNone = 0, MSBDStickyOK = 1, MSBDStickyUnread = 2, MSBDStickyAside = 3, MSBDStickyNewer = 4 } MSBDStickyStatus;
// none: no file (first use); ok: read; unread: the read was refused (data protection before the first unlock, permissions, any error but "not
// there") -- tried again later, never written over; aside: there but not a store (put aside, then empty); newer: a later release's store (after a
// downgrade) -- left alone, never written.
static inline BOOL MSBDStickyWritable(MSBDStickyStatus s) { return s == MSBDStickyNone || s == MSBDStickyOK || s == MSBDStickyAside; }
static inline NSString *MSBDStickyStatusName(MSBDStickyStatus s) {
    switch (s) { case MSBDStickyNone: return @"none"; case MSBDStickyOK: return @"ok"; case MSBDStickyUnread: return @"unread"; case MSBDStickyAside: return @"aside"; case MSBDStickyNewer: return @"newer"; }
    return @"?";
}
// A note's id: a UUID as NSUUID writes it, 36 characters -- the only ids read. Logs name a note by its first 8 characters only.
static inline BOOL MSBDStickyIdValid(id x) { return [x isKindOfClass:[NSString class]] && [(NSString *)x length] == 36 && [[NSUUID alloc] initWithUUIDString:x] != nil; }
static inline NSString *MSBDStickyShortId(NSString *noteId) { return [noteId isKindOfClass:[NSString class]] && noteId.length >= 8 ? [noteId substringToIndex:8] : @"-"; }
// At most max characters, never half of one: an emoji or a letter with its accents at the cut goes whole.
static inline NSString *MSBDStickyTextCut(id t, NSUInteger max) {
    if (![t isKindOfClass:[NSString class]]) return @"";
    NSString *s = t;
    if (s.length <= max) return s;
    return [s substringToIndex:[s rangeOfComposedCharacterSequenceAtIndex:max].location];
}
static inline double MSBDStickyClamp(double v, double lo, double hi) { return v < lo ? lo : v > hi ? hi : v; }
// One stored entry made safe to show, or nil when it is no note: an id, the four numbers finite; an unknown colour is Yellow, the place and size
// clamped, the text cut at the cap.
static inline NSMutableDictionary *MSBDStickyEntryRead(id e) {
    if (![e isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *d = e;
    if (!MSBDStickyIdValid(d[@"id"])) return nil;
    for (NSString *k in @[@"x", @"y", @"w", @"h"]) if (![d[k] isKindOfClass:[NSNumber class]] || !isfinite([d[k] doubleValue])) return nil;
    id text = d[@"text"];
    if (text && ![text isKindOfClass:[NSString class]]) return nil;
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    m[@"id"] = d[@"id"];
    m[@"color"] = MSBDStickyColorName(MSBDStickyColorIndex(d[@"color"]));
    m[@"x"] = @(MSBDStickyClamp([d[@"x"] doubleValue], 0, 1)); m[@"y"] = @(MSBDStickyClamp([d[@"y"] doubleValue], 0, 1));
    m[@"w"] = @(MSBDStickyClamp([d[@"w"] doubleValue], MSBD_NOTE_MIN_W, MSBD_NOTE_MAX_SIDE)); m[@"h"] = @(MSBDStickyClamp([d[@"h"] doubleValue], MSBD_NOTE_MIN_H, MSBD_NOTE_MAX_SIDE));
    m[@"text"] = MSBDStickyTextCut(text ?: @"", MSBD_NOTE_TEXT_MAX);
    return m;
}
// The store as read: from the file's data, or from the error of its read (errno's: ENOENT is "no file"). shown: the notes to show, at most 30, in
// stacking order; kept: entries past the cap, written back as stored; *skipped: entries that are no note (or a second one with the same id).
static inline MSBDStickyStatus MSBDStickyStoreRead(NSData *data, int readErr, NSMutableArray<NSMutableDictionary *> *shown, NSMutableArray *kept, int *skipped) {
    if (skipped) *skipped = 0;
    if (!data) return readErr == ENOENT ? MSBDStickyNone : MSBDStickyUnread;
    id plist = data.length ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL] : nil;
    if (![plist isKindOfClass:[NSDictionary class]]) return MSBDStickyAside;
    id v = plist[@"version"], notes = plist[@"notes"];
    if (![v isKindOfClass:[NSNumber class]] || ![notes isKindOfClass:[NSArray class]]) return MSBDStickyAside;
    if ([v integerValue] > MSBD_NOTES_VERSION) return MSBDStickyNewer;
    if ([v integerValue] < 1) return MSBDStickyAside;
    NSMutableSet *ids = [NSMutableSet set];
    for (id e in notes) {
        NSMutableDictionary *m = MSBDStickyEntryRead(e);
        if (!m || [ids containsObject:m[@"id"]]) { if (skipped) (*skipped)++; continue; }
        [ids addObject:m[@"id"]];
        if (shown.count < MSBD_NOTES_MAX) [shown addObject:m]; else [kept addObject:e];
    }
    return MSBDStickyOK;
}
// The file to write: the notes shown (their known keys only), then the kept ones as they were stored.
static inline NSData *MSBDStickyStoreBuild(NSArray<NSDictionary *> *shown, NSArray *kept) {
    NSMutableArray *all = [NSMutableArray array];
    for (NSDictionary *n in shown) {
        if (!MSBDStickyIdValid(n[@"id"])) continue;
        [all addObject:@{@"id": n[@"id"], @"color": MSBDStickyColorName(MSBDStickyColorIndex(n[@"color"])), @"x": @([n[@"x"] doubleValue]), @"y": @([n[@"y"] doubleValue]),
                         @"w": @([n[@"w"] doubleValue]), @"h": @([n[@"h"] doubleValue]), @"text": MSBDStickyTextCut(n[@"text"], MSBD_NOTE_TEXT_MAX)}];
    }
    if (kept.count) [all addObjectsFromArray:kept];
    return [NSPropertyListSerialization dataWithPropertyList:@{@"version": @(MSBD_NOTES_VERSION), @"notes": all} format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
}
// A store put aside keeps every older one: StickyNotes-unreadable.plist, then "... 2", "... 3" (n: 1, 2, 3...).
static inline NSString *MSBDStickyAsideName(int n) { return n <= 1 ? @"StickyNotes-unreadable.plist" : [NSString stringWithFormat:@"StickyNotes-unreadable %d.plist", n]; }

// ---- a note in the Trash ----
// The Trash file's look attribute: "1 <color> <w> <h>" (version 1), never text. Read back: NO when it is not one.
static inline NSString *MSBDStickyTrashAttr(id color, double w, double h) { return [NSString stringWithFormat:@"1 %@ %.0f %.0f", MSBDStickyColorName(MSBDStickyColorIndex(color)), w, h]; }
static inline BOOL MSBDStickyTrashAttrRead(id s, NSString **color, double *w, double *h) {
    if (![s isKindOfClass:[NSString class]]) return NO;
    NSArray<NSString *> *q = [(NSString *)s componentsSeparatedByString:@" "];
    if (q.count != 4 || ![q[0] isEqualToString:@"1"]) return NO;
    double a = q[2].doubleValue, b = q[3].doubleValue;
    if (!isfinite(a) || !isfinite(b) || a <= 0 || b <= 0) return NO;
    if (color) *color = MSBDStickyColorName(MSBDStickyColorIndex(q[1]));
    if (w) *w = MSBDStickyClamp(a, MSBD_NOTE_MIN_W, MSBD_NOTE_MAX_SIDE);
    if (h) *h = MSBDStickyClamp(b, MSBD_NOTE_MIN_H, MSBD_NOTE_MAX_SIDE);
    return YES;
}
// The place attribute the desktop's icons carry to the Trash (Finder.h kFinderDesktopPlaceAttr, "fx,fy"), read for a note: NO when not one.
static inline BOOL MSBDStickyPlaceRead(id s, double *fx, double *fy) {
    if (![s isKindOfClass:[NSString class]]) return NO;
    NSArray<NSString *> *q = [(NSString *)s componentsSeparatedByString:@","];
    if (q.count != 2) return NO;
    double a = q[0].doubleValue, b = q[1].doubleValue;
    if (!isfinite(a) || !isfinite(b)) return NO;
    if (fx) *fx = MSBDStickyClamp(a, 0, 1);
    if (fy) *fy = MSBDStickyClamp(b, 0, 1);
    return YES;
}
// ---- the desktop's typing at a layout transition (1.8.8.2, B74; statusbar/Desktop.h DMDesktopTypingAtTransition reads SpringBoard's side) ----
// A note (or a name: they share the one typing window) being typed in ends when SpringBoard begins a transition that presents Spotlight, on any
// display (its search field gets the keys from then on: Design v2 2k, "another SpringBoard text field taking the typing"), or that takes the iPad's
// own display to a full-screen app or window: SpringBoard's application mode (3) there, with our Stage Manager engine only when the stage holds a
// full-screen window (its windows are a stage in that mode, the desktop behind them), with Aerial, Zetsu, MilkyWay4 and no windowing always (their
// windows lie over the Home Screen, so that mode is an app full screen). Home (1), the App Switcher (2), another display, a state that could not be
// read: the typing goes on, and the tick's and the touches' rules decide as before.
typedef enum { MSBDStickyTypingGoesOn = 0, MSBDStickyTypingSpotlight = 1, MSBDStickyTypingFullScreen = 2 } MSBDStickyTypingEnd;
static inline MSBDStickyTypingEnd MSBDStickyTypingAt(BOOL spotlight, BOOL stateRead, BOOL onIPad, long long mode, BOOL smEngine, BOOL stageFull) {
    if (spotlight) return MSBDStickyTypingSpotlight;
    if (!stateRead || !onIPad || mode != 3) return MSBDStickyTypingGoesOn;
    return (!smEngine || stageFull) ? MSBDStickyTypingFullScreen : MSBDStickyTypingGoesOn;
}
static inline NSString *MSBDStickyTypingWhy(MSBDStickyTypingEnd e) {
    return e == MSBDStickyTypingSpotlight ? @"Spotlight opens" : e == MSBDStickyTypingFullScreen ? @"a window or app went full screen" : nil;
}
#endif
