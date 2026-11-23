// StickyNotes.h -- Sticky Notes on the desktop (1.8.8.1): the rules, Foundation and CoreGraphics only, so the Mac test (tools/test-stickynotes.sh)
// runs this very code. The notes themselves -- their views, the typing, the store's file -- are statusbar/DesktopNotes.h.
//  - Colours: macOS Stickies' six (its asset catalog, sRGB): the paper and the band at its top. The same in Dark Mode, as on a Mac (paper is paper).
//  - A note keeps its own size in points (only a resize changes it) and its place as its centre's share of the desktop's places area, as an icon
//    does. Shown, it is kept inside the free area (under the menu bar, above the Dock), at least the minimum size, and clear of the Home Screen's
//    app icons, widgets and page dots: they draw over it and take its touches.
//  - The store: one binary plist {version 1, notes [{id, color, x, y, w, h, text}]}, the array's order the stacking order (last on top). A store that
//    could not be read is never taken for an empty one: nothing is shown and nothing is written until a read worked or found no file. 1.8.8.2: an
//    entry may also carry "page" (its Home Screen page, F36) and "name" (its own name, F37), and keys this release does not know are kept and
//    written back as read; still version 1 (1.8.8.1 reads it and drops the two: every note on page 1, with its default name, none lost).
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
#define MSBD_NOTE_BAR 22.0            // (the top bar, in the colour's darker shade: the note's move handle; 1.8.8.2 B78, the 6 pt band before)
#define MSBD_NOTE_HOLD_TO_MOVE 0.2    // (a finger held this long, still, on a note's paper before a move drags it: 1.8.8.2 B78; its bar drags at once)
#define MSBD_NOTE_LIFT_GAP 8.0        // (a note lifted over the keyboard ends this far above it)
#define MSBD_NOTE_CLEAR_STEP 8.0      // (MSBDStickyPlaceClear's rings)
#define MSBD_NOTE_CLEAR_TESTS 60000L  // (... and its cap of rect tests a note)
#define MSBD_NOTES_VERSION 1
#define MSBD_NOTE_PAGE_MAX 200        // (a page key's length at most: "home:<iPadOS's page id>", 1.8.8.2 F36)
#define MSBD_NOTE_NAME_MAX 100        // (a note's own name, characters at most, 1.8.8.2 F37)
#define MSBD_NOTE_TRASH_ORIGIN @"sticky-note"                 // (Finder's origin attribute of a note's Trash file: a marker, never a path)
#define MSBD_NOTE_TRASH_ATTR "com.besiktasliseba.stickynote"   // (... and its look: "1 <color> <w> <h>", never text)
#define MSBD_NOTE_TRASH_PAGE_ATTR "com.besiktasliseba.stickynote.page"   // (... and its page key, 1.8.8.2 F36: Put Back puts it back there)
#define MSBD_NOTE_TRASH_NAME_ATTR "com.besiktasliseba.stickynote.name"   // (... and a note's own name, 1.8.8.2 F37: Put Back gives it back; never its text)
#define MSBD_NOTE_DEFAULT_NAME @"Sticky Note"                          // (the name of a note with no name of its own and no text, 1.8.8.2 F37)

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
// Open interiors meet (edges that only touch do not), as the desktop's placer counts an icon over a rect (DesktopPlace.h DMPlacerOver). By more
// than MSBD_NOTE_TOUCH_SLOP (1.8.8.2 B72): a note placed against an icon touches it, and the round trip of its place through the store (the
// centre's share of the area) comes back a few 1e-13 pt off, which counted as over it and moved the note 8 pt at the next layout.
#define MSBD_NOTE_TOUCH_SLOP 0.001
static inline BOOL MSBDStickyRectsOverlap(CGRect a, CGRect b) {
    return CGRectGetMinX(a) < CGRectGetMaxX(b) - MSBD_NOTE_TOUCH_SLOP && CGRectGetMaxX(a) > CGRectGetMinX(b) + MSBD_NOTE_TOUCH_SLOP
        && CGRectGetMinY(a) < CGRectGetMaxY(b) - MSBD_NOTE_TOUCH_SLOP && CGRectGetMaxY(a) > CGRectGetMinY(b) + MSBD_NOTE_TOUCH_SLOP;
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
// A corner's resize stopped where the note would meet the rects (1.8.8.2 B72: the page's app icons, widgets and page dots, which the layout keeps
// every note clear of -- a note grown over them was moved clear at the let go, carrying its size: its other side moved, or it jumped up off the
// page dots). want is the frame the grip gives (DMNativeResized, kept inside the area): its top and its fixed side (the right edge for the left
// grip, tag 0; the left edge for the right grip, tag 1) stay; its moving side and its bottom grow only as far as they stay clear, MSBD_NOTE_CLEAR_GAP
// short of a rect they stop at. Width then height, and height then width, are both worked out, and the one whose moving corner is nearer want's
// (the finger's) is kept. A rect whose near side is already inside the frame (one the note lay over when the drag began: the layout could not
// clear it either) is passed over; want over no rect it did not start over: want as it is.
#define MSBD_NOTE_CLEAR_GAP 1.0
static inline CGFloat MSBDStickyGrowWidth(CGFloat x0, int tag, CGFloat top, CGFloat h, CGFloat cur, CGFloat want, const CGRect *rects, int n) {
    if (want <= cur) return want;
    CGFloat limit = want;
    for (int k = 0; k < n; k++) {
        if (!(CGRectGetMinY(rects[k]) < top + h && CGRectGetMaxY(rects[k]) > top)) continue;   // (beside the frame's rows only)
        CGFloat d = tag == 1 ? CGRectGetMinX(rects[k]) - x0 : x0 - CGRectGetMaxX(rects[k]);   // (from the fixed side to the rect's near side)
        if (d >= cur - 1e-6 && d - MSBD_NOTE_CLEAR_GAP < limit) limit = d - MSBD_NOTE_CLEAR_GAP;
    }
    return MAX(cur, limit);
}
static inline CGFloat MSBDStickyGrowHeight(CGFloat x0, int tag, CGFloat top, CGFloat w, CGFloat cur, CGFloat want, const CGRect *rects, int n) {
    if (want <= cur) return want;
    CGFloat lo = tag == 1 ? x0 : x0 - w, hi = tag == 1 ? x0 + w : x0, limit = want;
    for (int k = 0; k < n; k++) {
        if (!(CGRectGetMinX(rects[k]) < hi && CGRectGetMaxX(rects[k]) > lo)) continue;   // (under the frame's columns only)
        CGFloat d = CGRectGetMinY(rects[k]) - top;
        if (d >= cur - 1e-6 && d - MSBD_NOTE_CLEAR_GAP < limit) limit = d - MSBD_NOTE_CLEAR_GAP;
    }
    return MAX(cur, limit);
}
static inline CGRect MSBDStickyResizeClear(CGRect start, CGRect want, int tag, CGSize minSize, const CGRect *rects, int n) {
    if (n <= 0 || !rects || CGRectIsNull(want) || CGRectIsEmpty(want)) return want;
    BOOL any = NO;
    for (int k = 0; k < n && !any; k++) if (MSBDStickyRectsOverlap(want, rects[k]) && !MSBDStickyRectsOverlap(start, rects[k])) any = YES;
    if (!any) return want;
    CGFloat x0 = tag == 1 ? CGRectGetMinX(want) : CGRectGetMaxX(want), top = CGRectGetMinY(want);
    CGFloat w0 = MAX(MIN(start.size.width, want.size.width), MIN(minSize.width, want.size.width)), h0 = MAX(MIN(start.size.height, want.size.height), MIN(minSize.height, want.size.height));
    CGFloat wa = MSBDStickyGrowWidth(x0, tag, top, h0, w0, want.size.width, rects, n), ha = MSBDStickyGrowHeight(x0, tag, top, wa, h0, want.size.height, rects, n);   // (width first)
    CGFloat hb = MSBDStickyGrowHeight(x0, tag, top, w0, h0, want.size.height, rects, n), wb = MSBDStickyGrowWidth(x0, tag, top, hb, w0, want.size.width, rects, n);   // (height first)
    CGFloat da = hypot(want.size.width - wa, want.size.height - ha), db = hypot(want.size.width - wb, want.size.height - hb);
    CGFloat w = db < da ? wb : wa, h = db < da ? hb : ha;
    return CGRectMake(tag == 1 ? x0 : x0 - w, top, w, h);
}
// Over any of the rects (more than touching them)?
static inline BOOL MSBDStickyOverAny(CGRect f, const CGRect *rects, int n) {
    for (int k = 0; k < n; k++) if (MSBDStickyRectsOverlap(f, rects[k])) return YES;
    return NO;
}
// No clear frame of the note's size on its page (1.8.8.2, the Dock at a side moved the icons into a note that had no room left): the frame pulled in
// from its sides that meet the rects, as a resize stops at them (B72: MSBD_NOTE_CLEAR_GAP short), at least minSize. Each step takes, of every
// rect it still meets, the trim of one side that keeps the most of it (its left side to the rect's right, its right side to the rect's left, its
// top below it, its bottom above it); a rect given up is never met again (the frame only shrinks), so at most n steps. CGRectNull when no such
// frame of at least minSize is clear.
static inline CGRect MSBDStickyTrimClear(CGRect f, const CGRect *rects, int n, CGSize minSize) {
    const CGFloat g = MSBD_NOTE_CLEAR_GAP;
    for (int step = 0; step <= n; step++) {
        CGRect best = CGRectNull; CGFloat most = -1.0; BOOL over = NO;
        for (int k = 0; k < n; k++) {
            CGRect r = rects[k];
            if (!MSBDStickyRectsOverlap(f, r)) continue;
            over = YES;
            CGRect c[4] = {
                CGRectMake(CGRectGetMaxX(r) + g, f.origin.y, CGRectGetMaxX(f) - CGRectGetMaxX(r) - g, f.size.height),
                CGRectMake(f.origin.x, f.origin.y, CGRectGetMinX(r) - g - f.origin.x, f.size.height),
                CGRectMake(f.origin.x, CGRectGetMaxY(r) + g, f.size.width, CGRectGetMaxY(f) - CGRectGetMaxY(r) - g),
                CGRectMake(f.origin.x, f.origin.y, f.size.width, CGRectGetMinY(r) - g - f.origin.y) };
            for (int s = 0; s < 4; s++) {
                if (!(c[s].size.width >= minSize.width && c[s].size.height >= minSize.height)) continue;
                CGFloat a = c[s].size.width * c[s].size.height;
                if (a > most) { most = a; best = c[s]; }
            }
        }
        if (!over) return f;
        if (CGRectIsNull(best)) return CGRectNull;
        f = best;
    }
    return MSBDStickyOverAny(f, rects, n) ? CGRectNull : f;
}
// Where a note is shown, clear of its page's app icons, widgets and page dots (1.8.8.2): the nearest clear frame of its size (MSBDStickyPlaceClear);
// where its page has none, smaller where it is (MSBDStickyTrimClear: B72's rule, the sides that meet them pulled in); else the minimum size at the
// nearest clear place; else the frame kept inside the area, as before (a page full of icons). Before, a note with no clear frame of its size stayed
// under the icons. Nothing here changes what is stored: with room again the note shows at its size. *anchor (may be NULL): the frame of the note's
// own size the result came from; a drop or a move stores its centre, so the next layout, which starts from the stored centre and size, gives the
// same frame.
static inline CGRect MSBDStickyPlaceClearFit(CGRect frame, CGRect area, const CGRect *rects, int n, CGSize minSize, long maxTests, CGRect *anchor) {
    CGRect f0 = MSBDStickyClampInside(frame, area);
    CGRect f = MSBDStickyPlaceClear(frame, area, rects, n, maxTests, NULL);
    if (anchor) *anchor = f;
    if (!MSBDStickyOverAny(f, rects, n)) return f;   // (clear at its size: as before)
    if (anchor) *anchor = f0;
    CGRect t = MSBDStickyTrimClear(f0, rects, n, minSize);
    if (!CGRectIsNull(t)) return t;
    CGSize s = CGSizeMake(MIN(minSize.width, f0.size.width), MIN(minSize.height, f0.size.height));
    CGRect m = MSBDStickyPlaceClear(CGRectMake(CGRectGetMidX(f0) - s.width / 2.0, CGRectGetMidY(f0) - s.height / 2.0, s.width, s.height), area, rects, n, maxTests, NULL);
    return MSBDStickyOverAny(m, rects, n) ? f0 : m;
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

// ---- a press on a note (1.8.8.2 B78: one decider -- the desktop's -dm_event: follows the press, the desktop's tap only reports the release) ----
// A press types in the note only when it never went past its drag distance (4 pt a pointer, 10 pt a finger: -dm_event:'s own), no menu of ours is
// up and it was let go before the menu's time (a pointer's click held still or a finger's hold opens the menu instead). Before, UIKit's tap decided
// on its own allowance (far more than 4 pt): a short pointer drag moved the note AND typed in it.
static inline BOOL MSBDStickyPressTypes(int moved, int menuUp, double heldFor, double menuTime) { return !moved && !menuUp && heldFor <= menuTime; }
// Did the press a tap ends move past its drag distance? UIKit gives a touch to its gestures (the tap's -gestureRecognizer:shouldReceiveTouch:)
// before SpringBoard's -sendEvent: (where -dm_event: starts following the press), and a tap reports where its touch went DOWN, so neither the order
// of the two nor the tap's location tells (1.8.8.2's test build: every short drag and flick typed). The tap is matched to its press by the touch
// itself (samePress: the touch -dm_event: followed is the tap's): that press's own note of it (pressMoved) or its travel from down to its last point;
// and, whoever followed it, the tap's own touch's travel from where it went down to where it is at the tap (where it lifted). NaN travels count as 0.
static inline BOOL MSBDStickyTapMoved(int samePress, int pressMoved, double pressTravel, double tapTravel, double dragDistance) {
    return (samePress && (pressMoved || pressTravel > dragDistance)) || tapTravel > dragDistance;
}
// The top bar is the note's handle: a press that begins on it is the note's from the touch down (no hold, the page never turns from it). Elsewhere a
// finger is held MSBD_NOTE_HOLD_TO_MOVE first (a quicker swipe turns the page). A pointer drags at once anywhere (Desktop.h's rule).
static inline CGRect MSBDStickyBarRect(CGRect note) { return CGRectMake(note.origin.x, note.origin.y, note.size.width, MIN(MSBD_NOTE_BAR, MAX(0.0, note.size.height))); }
// A rect of finite numbers only (no NaN, no infinity): CGRectNull, the answer of CGRectInset for an inset past the rect's size, has an infinite origin.
static inline BOOL MSBDStickyRectOK(CGRect r) { return isfinite(r.origin.x) && isfinite(r.origin.y) && isfinite(r.size.width) && isfinite(r.size.height); }
// ... a point and a transform of finite numbers only (the notes' setters refuse any other: DesktopNotes.h DMStickySetFrame and its siblings).
static inline BOOL MSBDStickyPointOK(CGPoint p) { return isfinite(p.x) && isfinite(p.y); }
static inline BOOL MSBDStickyTransformOK(CGAffineTransform t) { return isfinite(t.a) && isfinite(t.b) && isfinite(t.c) && isfinite(t.d) && isfinite(t.tx) && isfinite(t.ty); }
// The field a note's name is edited in, in its top bar (1.8.8.2 F37): the bar inset 6 pt at the sides and 2 pt at the top and the bottom, never past
// the bar's size. A bar not laid out yet (zero) gives a zero rect at its origin, never CGRectNull: in 1.8.8.2's test build the field was made with
// CGRectInset of such a bar (an infinite origin), and UIKit's selection grabbers over it got a NaN position (SpringBoard raised).
#define MSBD_NOTE_NAME_INSET_X 6.0
#define MSBD_NOTE_NAME_INSET_Y 2.0
static inline CGRect MSBDStickyNameFieldRect(CGRect bar) {
    if (!MSBDStickyRectOK(bar)) return CGRectZero;
    bar = CGRectStandardize(bar);
    CGFloat dx = MIN(MSBD_NOTE_NAME_INSET_X, bar.size.width / 2.0), dy = MIN(MSBD_NOTE_NAME_INSET_Y, bar.size.height / 2.0);
    return CGRectMake(bar.origin.x + dx, bar.origin.y + dy, bar.size.width - 2.0 * dx, bar.size.height - 2.0 * dy);
}
static inline BOOL MSBDStickyOnBar(CGRect note, CGPoint p) { return CGRectContainsPoint(MSBDStickyBarRect(note), p); }
static inline double MSBDStickyHoldToMove(int onBar) { return onBar ? 0.0 : MSBD_NOTE_HOLD_TO_MOVE; }
// A double tap or click on a note's bar edits its name (1.8.8.2 F37): a second tap on the same note's bar within MSBD_NOTE_BAR_TWICE (the desktop
// icons' double tap time). On an idle note the first tap does not begin the typing at once (with the on-screen keyboard the note is lifted over it
// and its bar's taps are off, so a second tap never reached a bar: 1.8.8.2's test build): its typing begins when that time is over, only if
// nothing came between -- this was still the last bar tap (a second one renamed it), no touch began since, the app in front is the same, no
// typing began another way.
#define MSBD_NOTE_BAR_TWICE 0.45
static inline BOOL MSBDStickyBarTwice(NSString *lastId, NSString *noteId, double since) { return lastId && noteId && [lastId isEqualToString:noteId] && since >= 0 && since < MSBD_NOTE_BAR_TWICE; }
static inline BOOL MSBDStickyBarOnceTypes(int stillThisTap, int touchSince, int frontSame, int typingAlready) { return stillThisTap && !touchSince && frontSame && !typingAlready; }

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
// A stored page key (1.8.8.2 F36): a string of 1 to MSBD_NOTE_PAGE_MAX characters, else nil (the desktop's: Home Screen page 1).
static inline NSString *MSBDStickyPageRead(id p) { return [p isKindOfClass:[NSString class]] && [(NSString *)p length] >= 1 && [(NSString *)p length] <= MSBD_NOTE_PAGE_MAX ? p : nil; }
// A note's own name as kept (1.8.8.2 F37): line breaks and tabs made spaces, no spaces at its ends, at most MSBD_NOTE_NAME_MAX characters (never
// half of one); nil when nothing is left (the default name, StickyNotes.h MSBDStickyNameShown).
static inline NSString *MSBDStickyNameClean(id n) {
    if (![n isKindOfClass:[NSString class]]) return nil;
    NSMutableString *m = [(NSString *)n mutableCopy];
    for (NSString *x in @[@"\r\n", @"\r", @"\n", @"\t", @"\u2028", @"\u2029"]) [m replaceOccurrencesOfString:x withString:@" " options:0 range:NSMakeRange(0, m.length)];
    NSString *t = MSBDStickyTextCut([m stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]], MSBD_NOTE_NAME_MAX);
    t = [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return t.length ? t : nil;
}
// The name a note shows in its top bar (1.8.8.2 F37): its own name, else the first line of its text that is not blank (as kept: MSBDStickyNameClean),
// else "Sticky Note". Its Move to Trash file is named after it.
static inline NSString *MSBDStickyNameShown(id name, id text) {
    NSString *own = MSBDStickyNameClean(name);
    if (own) return own;
    __block NSString *line = nil;
    if ([text isKindOfClass:[NSString class]]) [(NSString *)text enumerateLinesUsingBlock:^(NSString *l, BOOL *stop) { NSString *t = MSBDStickyNameClean(l); if (t) { line = t; *stop = YES; } }];
    return line ?: MSBD_NOTE_DEFAULT_NAME;
}
// The Trash file's name for a note (1.8.8.2 F37): its name shown, a "/" or ":" made "-", no control character, no leading dot, at most 200 bytes of
// UTF-8 (never half a character), then ".txt" -- Finder's Trash numbers it when the name is taken. Nothing usable left: "Sticky Note.txt".
static inline NSString *MSBDStickyTrashFileName(id shown) {
    NSString *n = MSBDStickyNameClean(shown) ?: MSBD_NOTE_DEFAULT_NAME;
    NSMutableString *m = [NSMutableString string];
    for (NSUInteger i = 0; i < n.length; ) {
        NSRange r = [n rangeOfComposedCharacterSequenceAtIndex:i];
        NSString *c = [n substringWithRange:r];
        unichar u = [c characterAtIndex:0];
        if ([c isEqualToString:@"/"] || [c isEqualToString:@":"]) c = @"-";
        else if (u < 0x20 || u == 0x7F) c = @"";
        if ([m lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + [c lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 200) break;
        [m appendString:c]; i = NSMaxRange(r);
    }
    while ([m hasPrefix:@"."]) [m deleteCharactersInRange:NSMakeRange(0, 1)];
    NSString *base = [m stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [(base.length ? base : MSBD_NOTE_DEFAULT_NAME) stringByAppendingString:@".txt"];
}
// The keys this release reads into an entry; any other key an entry carries is kept as it was read (a later release's, 1.8.8.2).
static inline BOOL MSBDStickyKnownKey(id k) { return [@[@"id", @"color", @"x", @"y", @"w", @"h", @"text", @"page", @"name"] containsObject:k]; }
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
    NSString *page = MSBDStickyPageRead(d[@"page"]), *name = MSBDStickyNameClean(d[@"name"]);   // (1.8.8.2: optional; absent, page 1 and the default name)
    if (page) m[@"page"] = page;
    if (name) m[@"name"] = name;
    for (id k in d) if (!MSBDStickyKnownKey(k)) m[k] = d[k];   // (a later release's keys, kept as read)
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
// The file to write: the notes shown (their known keys, the page and the name when they have them, and any key a later release wrote, as read), then
// the kept ones as they were stored.
static inline NSData *MSBDStickyStoreBuild(NSArray<NSDictionary *> *shown, NSArray *kept) {
    NSMutableArray *all = [NSMutableArray array];
    for (NSDictionary *n in shown) {
        if (!MSBDStickyIdValid(n[@"id"])) continue;
        NSMutableDictionary *o = [@{@"id": n[@"id"], @"color": MSBDStickyColorName(MSBDStickyColorIndex(n[@"color"])), @"x": @([n[@"x"] doubleValue]), @"y": @([n[@"y"] doubleValue]),
                                    @"w": @([n[@"w"] doubleValue]), @"h": @([n[@"h"] doubleValue]), @"text": MSBDStickyTextCut(n[@"text"], MSBD_NOTE_TEXT_MAX)} mutableCopy];
        NSString *page = MSBDStickyPageRead(n[@"page"]), *name = MSBDStickyNameClean(n[@"name"]);
        if (page) o[@"page"] = page;
        if (name) o[@"name"] = name;
        for (id k in n) if (!MSBDStickyKnownKey(k)) o[k] = n[k];
        [all addObject:o];
    }
    if (kept.count) [all addObjectsFromArray:kept];
    return [NSPropertyListSerialization dataWithPropertyList:@{@"version": @(MSBD_NOTES_VERSION), @"notes": all} format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
}
// A store put aside keeps every older one: StickyNotes-unreadable.plist, then "... 2", "... 3" (n: 1, 2, 3...).
static inline NSString *MSBDStickyAsideName(int n) { return n <= 1 ? @"StickyNotes-unreadable.plist" : [NSString stringWithFormat:@"StickyNotes-unreadable %d.plist", n]; }

// ---- other Home Screen pages (1.8.8.2 F36) ----
// A note belongs to a Home Screen page: no page key, the desktop's (page 1); "home:<id>", the page with iPadOS's own id (its icon list's model's
// -uniqueIdentifier: kept across resprings and page moves; a page number is never stored, pages move and go). A note whose page is not shown now --
// removed, or ids not readable here -- shows on page 1, keeping its key (never lost). A HIDDEN page's notes hide with it, as its icons and widgets
// do, and are back when it is shown again (KT 22 Nov). The page that is first now is page 1 as well.
static inline NSString *MSBDStickyPageKey(id pageId) { return [pageId isKindOfClass:[NSString class]] && [(NSString *)pageId length] >= 1 && [(NSString *)pageId length] <= MSBD_NOTE_PAGE_MAX - 5 ? [@"home:" stringByAppendingString:pageId] : nil; }
static inline NSString *MSBDStickyPageIdOf(id key) { NSString *k = MSBDStickyPageRead(key); return [k hasPrefix:@"home:"] && k.length > 5 ? [k substringFromIndex:5] : nil; }
static inline NSUInteger MSBDStickyPageShown(id key, NSArray<NSString *> *pageIds) {   // (the index in pageIds, page 1 first, a note shows on)
    NSString *i = MSBDStickyPageIdOf(key);
    if (!i || ![pageIds isKindOfClass:[NSArray class]]) return 0;
    NSUInteger k = [pageIds indexOfObject:i];
    return k == NSNotFound ? 0 : k;
}
// ... and with the hidden pages' ids (the root folder's lists that say they are hidden): MSBD_NOTE_PAGE_HIDDEN for a note of a hidden page that is
// not shown (it shows nowhere until the page is back); else its page as above. No hidden ids readable: as above (page 1, never lost).
#define MSBD_NOTE_PAGE_HIDDEN NSNotFound
static inline NSUInteger MSBDStickyPageOrHidden(id key, NSArray<NSString *> *pageIds, NSSet<NSString *> *hiddenIds) {
    NSString *i = MSBDStickyPageIdOf(key);
    if (i && [hiddenIds isKindOfClass:[NSSet class]] && [hiddenIds containsObject:i] && !([pageIds isKindOfClass:[NSArray class]] && [pageIds containsObject:i])) return MSBD_NOTE_PAGE_HIDDEN;
    return MSBDStickyPageShown(key, pageIds);
}
// Taking a dragged note to another page: its finger within MSBD_NOTE_EDGE of the screen's left or right side (or past the free area's side there: a
// side Dock) for MSBD_NOTE_EDGE_FIRST turns the page, and again each MSBD_NOTE_EDGE_AGAIN while it stays (an icon's drag in jiggle mode does that).
#define MSBD_NOTE_EDGE 24.0
#define MSBD_NOTE_EDGE_FIRST 0.6
#define MSBD_NOTE_EDGE_AGAIN 1.0
static inline int MSBDStickyEdgeSide(CGFloat x, CGFloat screenW, CGFloat areaMinX, CGFloat areaMaxX) {   // (-1 the left side, 1 the right, 0 neither)
    if (!isfinite(x) || screenW < 4 * MSBD_NOTE_EDGE) return 0;
    if (x <= MAX(MSBD_NOTE_EDGE, areaMinX)) return -1;
    if (x >= MIN(screenW - MSBD_NOTE_EDGE, areaMaxX)) return 1;
    return 0;
}
static inline BOOL MSBDStickyEdgeTurnDue(double still, int turnsSoFar) { return still >= (turnsSoFar ? MSBD_NOTE_EDGE_AGAIN : MSBD_NOTE_EDGE_FIRST); }
// The folder's page index a turn goes to: the next page toward that side (a right-to-left layout has its next pages at the left), never before the
// first icon page (the Today View) or after the last (the App Library); -1 when there is none that way.
static inline long MSBDStickyTurnTarget(long current, int side, int rtl, long first, long last) {
    long t = current + (long)side * (rtl ? -1 : 1);
    return side && first <= last && t >= first && t <= last ? t : -1;
}
// The free area a page's notes are laid out against (1.8.8.2, seen on iPadOS 17.5.1: page 2's notes 3.7 pt higher after a respring, page 1's not).
// A note's place is a share of the desktop's free area (the page less the menu bar and the Dock), and that area changes after SpringBoard starts:
// until the Dock is measured it is SpringBoard's own figure for it, then the Dock's top (the tallest Dock seen kept). Another page's notes are laid
// out again whenever their page shows and the area differs from their last layout; page 1's only in the desktop's own pass, which ran on a frame
// change or a dirty pass and never on the area alone: so after a respring the two pages were laid out against different areas. Now the desktop's
// pass also runs once the free area has changed and held MSBD_NOTE_AREA_SETTLE s (a Dock mid animation moves nothing): every page against the area
// it has settled at. seen / seenAt: the area last seen and since when (kept by the caller); laid: the area the last pass used. YES: a pass is due.
#define MSBD_NOTE_AREA_SETTLE 0.5
static inline BOOL MSBDStickyAreaSettled(CGRect now, CGRect *seen, double *seenAt, double t, CGRect laid) {
    if (!CGRectEqualToRect(now, *seen)) { *seen = now; *seenAt = t; return NO; }
    return t - *seenAt >= MSBD_NOTE_AREA_SETTLE && !CGRectIsEmpty(now) && !CGRectEqualToRect(now, laid);
}
// The page a note that rode a turn lands on (1.8.8.2, seen on iPadOS 17.5.1): the page its drag's last turn went to (turnedTo, page 1 is 0; -1 none),
// the one shown once the slide ends -- iPadOS's own page index still answers the page it slides from for a while after the turn (on 17.5.1 a
// finger lifted 0.70 s after reaching the side, the page already turning, let the note go on the page being left), else the page shown now.
// pages: how many there are now (a turn's page gone since: the page shown now).
static inline NSUInteger MSBDStickyDropPage(long turnedTo, NSUInteger pageNow, NSUInteger pages) {
    return turnedTo >= 0 && (NSUInteger)turnedTo < pages ? (NSUInteger)turnedTo : pageNow;
}
// Move to Page turns the Home Screen to the note's new page (1.8.8.2 F36, KT 22 Nov: "it can turn to that page when moved"): the folder's page index
// of icon page `page` (page 1 is 0) is the first icon page's plus it -- only when the folder counts exactly the pages read (first to last), so
// never the Today View or the App Library; -1 otherwise (no turn).
static inline long MSBDStickyPageTurnIndex(long page, long pages, long first, long last) {
    return pages >= 1 && first >= 0 && last - first + 1 == pages && page >= 0 && page < pages ? first + page : -1;
}

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
