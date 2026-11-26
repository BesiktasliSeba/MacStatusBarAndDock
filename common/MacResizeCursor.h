// common/MacResizeCursor.h -- macOS's resize pointers on our Mac pointer (1.8.9, F51; plans/design-mac-resize-pointers.md). KT 25 Nov: iPadOS 18's
// pointer at a window's edge was a grey circle with arrows around it; it should be "proper and maclike like our pointer".
//   Why the circle: MacPointer (statusbar/macpointer/MacPointer.x, in pointeruid) leaves iPadOS's own drawing in place for the text beam, which it
//   knew as a shape of type 4 or a shape 4 pt or thinner. Read on 18.5 (B0, 25 Nov): a window's resize band gives pointeruid a type 4 PATH shape,
//   a grey capsule with its arrowheads drawn in it, 35 x 14 pt along an edge and 25.8 pt square at a corner (no accessories); the text beam there is
//   a thin type 3 (3 x 24 pt), as on 15.6.1; 17.5.1's beam over Finder's search field was type 4 (1.8.8). So the rule took iPadOS's resize shape for
//   text. Now a beam is only a thin shape, or a type 4 shape without a size of its own or under 6 pt across (MSBDPointerBeamShape), and a state with
//   accessories is never one: with Mac Resize Pointers on (below), the Mac pointer draws at a band in any case.
//   What it draws there: SpringBoard knows which resize place is under the pointer (a window's hovered edge or corner on iPadOS 16-18, our window
//   engines' grips) and says it in one Darwin notification state (the fact, below); MacPointer draws macOS's resize cursor for that place on the
//   Mac arrow's own layer (black, white edge, the arrow's shadow, Pointer Size, the Pointer Control colour) as long as iPadOS's pointer state there
//   carries the arrows that go with it (the evidence: a stale fact never puts a resize glyph anywhere else), and through a resize drag until the
//   button is let go (the latch).
//   The window engines' grips (Aerial, Zetsu, MilkyWay4; 1.8.9, F51b): SpringBoard reads the pointer's hovers on its system gestures window against
//   the grips (statusbar/ResizeFact.h); iPadOS has no resize shape there, so such a fact is its own evidence while it is fresh (MSBDResizeGripFresh).
//   Settings > Pointer > Mac Resize Pointers turns all of it on and off: on by default on iPadOS 18, off on 15-17 (below: the switch); off, the
//   pointer looks as in 1.8.8.4 (MSBDPointerLook1884).
//   The glyphs are our own paths made from macOS 15's own cursors' measured geometry (NSCursor's frame, column and row resize cursors, read on the
//   Mac; tools/test-macresizecursor.m compares them): macOS points x MSBD_RZ_UNIT, the unit of our arrow's path (macOS's arrow is 14.1 pt tall,
//   ours 19.6 units), with the hotspot at (0, 0) as our arrow's tip is.
// Plain C on CoreGraphics (no UIKit): MacPointer.x (pointeruid), statusbar/ResizeFact.h (SpringBoard) and the Mac test use the very same code.
#ifndef MSBD_MAC_RESIZE_CURSOR_H
#define MSBD_MAC_RESIZE_CURSOR_H
#include <CoreGraphics/CoreGraphics.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>

#define MSBD_RZ_NOTE "com.besiktasliseba.macpointer.resize"   // the fact's notify state and its note (posted at each change)
#define MSBD_RZ_UNIT 1.39                                     // one macOS point in our arrow's path units

// What is under the pointer. Kinds: a window's frame (edge or corner), a column divider (left / right), a row divider (up / down).
enum { MSBD_RZ_NONE = 0, MSBD_RZ_FRAME = 1, MSBD_RZ_COLUMN = 2, MSBD_RZ_ROW = 3 };
// Positions: macOS's NSCursorFrameResizePosition bits (a corner is two of them).
enum { MSBD_RZ_TOP = 1, MSBD_RZ_LEFT = 2, MSBD_RZ_BOTTOM = 4, MSBD_RZ_RIGHT = 8 };
// Directions: macOS's NSCursorFrameResizeDirections (inward 1, outward 2). A column's are left 1 / right 2, a row's up 1 / down 2, as macOS's.
enum { MSBD_RZ_INWARD = 1, MSBD_RZ_OUTWARD = 2, MSBD_RZ_ALL = 3 };
// Where the fact came from (logs and Report a Problem only).
enum { MSBD_RZ_SRC_BAND = 1, MSBD_RZ_SRC_GRABBER = 2, MSBD_RZ_SRC_GRIP = 3 };

typedef struct { unsigned kind, position, directions, display, source, generation; } MSBDResizeFact;

// The word: bits 0-3 kind, 4-7 position, 8-9 directions, 10 display (0 the iPad's own, 1 another), 11-12 source, 16-31 a generation that changes
// with every fact SpringBoard sets (so the same place hovered twice is still a change). 0: nothing.
static inline bool MSBDResizePositionValid(unsigned kind, unsigned p) {
    if (kind == MSBD_RZ_FRAME) return p == MSBD_RZ_TOP || p == MSBD_RZ_LEFT || p == MSBD_RZ_BOTTOM || p == MSBD_RZ_RIGHT || p == (MSBD_RZ_TOP | MSBD_RZ_LEFT)
                                   || p == (MSBD_RZ_TOP | MSBD_RZ_RIGHT) || p == (MSBD_RZ_BOTTOM | MSBD_RZ_LEFT) || p == (MSBD_RZ_BOTTOM | MSBD_RZ_RIGHT);
    return (kind == MSBD_RZ_COLUMN || kind == MSBD_RZ_ROW) && p == 0;
}
static inline bool MSBDResizeFactValid(MSBDResizeFact f) {
    return f.kind >= MSBD_RZ_FRAME && f.kind <= MSBD_RZ_ROW && MSBDResizePositionValid(f.kind, f.position) && f.directions >= 1 && f.directions <= 3 && f.display <= 1;
}
static inline uint64_t MSBDResizePack(MSBDResizeFact f) {
    if (!MSBDResizeFactValid(f)) return 0;
    return (uint64_t)(f.kind & 0xF) | ((uint64_t)(f.position & 0xF) << 4) | ((uint64_t)(f.directions & 3) << 8) | ((uint64_t)(f.display & 1) << 10)
         | ((uint64_t)(f.source & 3) << 11) | ((uint64_t)(f.generation & 0xFFFF) << 16);
}
static inline MSBDResizeFact MSBDResizeUnpack(uint64_t w) {
    MSBDResizeFact f = { (unsigned)(w & 0xF), (unsigned)((w >> 4) & 0xF), (unsigned)((w >> 8) & 3), (unsigned)((w >> 10) & 1), (unsigned)((w >> 11) & 3), (unsigned)((w >> 16) & 0xFFFF) };
    if (!MSBDResizeFactValid(f)) { MSBDResizeFact none = {0, 0, 0, 0, 0, 0}; return none; }
    return f;
}
// The same place, whatever the generation and source.
static inline bool MSBDResizeSamePlace(MSBDResizeFact a, MSBDResizeFact b) {
    return a.kind == b.kind && a.position == b.position && a.directions == b.directions && a.display == b.display;
}

// SpringBoard's hovered edge (-[SBFluidSwitcherItemContainer pointerIsHoveringOverEdge], the edge +[SBEdgeResizeSystemPointerInteractionHelper
// shouldBeginPointerInteractionAtLocation:...] reports: 1 top, 2 bottom, 3 left, 4 right, 5 top-left, 6 top-right, 7 bottom-left, 8 bottom-right;
// 0 none) as a position; 0 for anything else.
static inline unsigned MSBDResizePosOfSBEdge(unsigned long long edge) {
    static const unsigned map[9] = { 0, MSBD_RZ_TOP, MSBD_RZ_BOTTOM, MSBD_RZ_LEFT, MSBD_RZ_RIGHT, MSBD_RZ_TOP | MSBD_RZ_LEFT, MSBD_RZ_TOP | MSBD_RZ_RIGHT,
                                     MSBD_RZ_BOTTOM | MSBD_RZ_LEFT, MSBD_RZ_BOTTOM | MSBD_RZ_RIGHT };
    return edge <= 8 ? map[edge] : 0;
}

// ---- one-way arrows (macOS: the arrow points only the way the edge can go) ----
// One axis: the window can shrink on it (above its minimum), the hovered edge can move outward (not at its limit, the window below its maximum).
static inline unsigned MSBDResizeAxisDirections(bool canShrink, bool canGrow) {
    if (canShrink && !canGrow) return MSBD_RZ_INWARD;
    if (!canShrink && canGrow) return MSBD_RZ_OUTWARD;
    return MSBD_RZ_ALL;   // (both, or neither: no one-way claim)
}
// A frame position from both axes' answers: an edge takes its axis's; a corner one-way only when both axes agree.
static inline unsigned MSBDResizeDirectionsOf(unsigned position, bool hShrink, bool hGrow, bool vShrink, bool vGrow) {
    bool h = (position & (MSBD_RZ_LEFT | MSBD_RZ_RIGHT)) != 0, v = (position & (MSBD_RZ_TOP | MSBD_RZ_BOTTOM)) != 0;
    unsigned a = MSBDResizeAxisDirections(hShrink, hGrow), b = MSBDResizeAxisDirections(vShrink, vGrow);
    if (h && v) return a == b ? a : MSBD_RZ_ALL;
    return h ? a : v ? b : MSBD_RZ_ALL;
}
// The window's frame against its limits, all in one space. minSize: the smallest the window may be (a side <= 0: not known, never "at its
// minimum"); area: where its edges may go (CGRectNull: not known, never "at its limit"). tol: how close counts as there (points).
static inline unsigned MSBDResizeDirectionsFor(unsigned position, CGRect frame, CGSize minSize, CGRect area, double tol) {
    if (CGRectIsNull(frame) || CGRectIsEmpty(frame)) return MSBD_RZ_ALL;
    bool known = !CGRectIsNull(area) && !CGRectIsEmpty(area);
    bool hShrink = !(minSize.width > 0 && frame.size.width <= minSize.width + tol);
    bool vShrink = !(minSize.height > 0 && frame.size.height <= minSize.height + tol);
    bool hGrow = true, vGrow = true;
    if (known) {
        if (position & MSBD_RZ_LEFT) hGrow = CGRectGetMinX(frame) > CGRectGetMinX(area) + tol;
        if (position & MSBD_RZ_RIGHT) hGrow = CGRectGetMaxX(frame) < CGRectGetMaxX(area) - tol;
        if (position & MSBD_RZ_TOP) vGrow = CGRectGetMinY(frame) > CGRectGetMinY(area) + tol;
        if (position & MSBD_RZ_BOTTOM) vGrow = CGRectGetMaxY(frame) < CGRectGetMaxY(area) - tol;
    }
    return MSBDResizeDirectionsOf(position, hShrink, hGrow, vShrink, vGrow);
}

// ---- the text beam (iPadOS keeps drawing its own there) ----
// w, h: the shape's bounds (either way round). 15.6.1 and 18.5: a type 3 rounded rect 3 x 24; 17.5.1: type 4 (1.8.8, not measured); iPadOS 18.5's
// resize shapes: type 4, 35 x 14 and 25.8 x 25.8 -- never a beam.
static inline bool MSBDPointerBeamShape(long long type, double w, double h) {
    bool sized = w > 0 && h > 0;
    if (sized && fmin(w, h) <= 4.0) return true;
    return type == 4 && (!sized || fmin(w, h) < 6.0);
}
// ---- the evidence: iPadOS's own resize shape there, or arrows along the same kind of axis ----
// An accessory's angle (radians, any turn between the app's space and the display's: only its class counts): 1 straight (a multiple of 90
// degrees), 2 diagonal (an odd multiple of 45), 0 neither.
static inline int MSBDResizeAngleClass(double angle) {
    if (!isfinite(angle)) return 0;
    double q = fmod(fabs(angle), M_PI_2);   // 0 .. 90 degrees
    if (q < M_PI / 16.0 || q > M_PI_2 - M_PI / 16.0) return 1;
    if (fabs(q - M_PI_4) < M_PI / 16.0) return 2;
    return 0;
}
static inline int MSBDResizeFactClass(MSBDResizeFact f) {
    if (f.kind == MSBD_RZ_COLUMN || f.kind == MSBD_RZ_ROW) return 1;
    if (f.kind != MSBD_RZ_FRAME) return 0;
    bool h = (f.position & (MSBD_RZ_LEFT | MSBD_RZ_RIGHT)) != 0, v = (f.position & (MSBD_RZ_TOP | MSBD_RZ_BOTTOM)) != 0;
    return h && v ? 2 : 1;
}
// 18.5: the band's style is a path shape (type 4) of some size -- what a text beam never is -- long along an edge (35 x 13.96: 2.5 to 1) and
// square at a corner (25.82 x 25.82); the shape must fit the fact's place (an edge 2 to 1 or longer, a corner within 1.3 to 1), so a stale fact
// never puts a glyph on some other path shape (an app's own). Elsewhere arrows (accessories) along the same kind of axis do as well.
static inline bool MSBDResizeShapeEvidence(MSBDResizeFact f, long long type, double w, double h) {
    if (type != 4 || w < 6.0 || h < 6.0) return false;
    double r = fmax(w, h) / fmin(w, h);
    int c = MSBDResizeFactClass(f);
    return c == 1 ? r >= 2.0 : c == 2 ? r <= 1.3 : false;
}
// shape: iPadOS's pointer shape now (type and bounds); count: the state's accessories; angles: those read (nAngles <= count; 0 when they could not
// be read: then any accessory is taken).
static inline bool MSBDResizeEvidence(MSBDResizeFact f, long long shapeType, double shapeW, double shapeH, int count, const double *angles, int nAngles) {
    int want = MSBDResizeFactClass(f);
    if (!want) return false;
    // (1.8.9, F51b: a window engine's grip -- Aerial, Zetsu, MilkyWay4. iPadOS gives no resize shape there: the round pointer, or the app's own shape
    //  under the window's corner (B0, 15.6.1). SpringBoard's own hit test of the grip is the evidence, and the grip takes the click whatever the
    //  app shows under it, as macOS's resize area beats the content: a grip's fact needs nothing of iPadOS's, only that it is fresh -- MacPointer's
    //  MSBDResizeGripFresh. A grip is always a corner.)
    if (f.source == MSBD_RZ_SRC_GRIP) return want == 2;
    if (MSBDResizeShapeEvidence(f, shapeType, shapeW, shapeH)) return true;
    if (count <= 0) return false;
    if (nAngles <= 0) return true;
    for (int i = 0; i < nAngles; i++) if (MSBDResizeAngleClass(angles[i]) == want) return true;
    return false;
}

// ---- what the pointer shows (MacPointer.x MPUpdate, with the Mac pointer enabled) ----
enum { MSBD_PTR_ARROW = 0, MSBD_PTR_BEAM = 1, MSBD_PTR_RESIZE = 2 };
// beamShape: iPadOS's shape is a text beam's (MSBDPointerBeamShape); accessories: how many arrows iPadOS puts around it; factHere: a fact
// for this pointer's display; evidence: MSBDResizeEvidence; live: a resize drag latched (MSBDResizeLatchStep).
static inline int MSBDPointerLook(bool beamShape, int accessories, bool factHere, bool evidence, bool live) {
    if (live || (factHere && evidence)) return MSBD_PTR_RESIZE;
    if (beamShape && accessories <= 0) return MSBD_PTR_BEAM;   // (the root fix: a state with accessories is never the text beam)
    return MSBD_PTR_ARROW;
}
// ---- the switch: Settings > Pointer > Mac Resize Pointers (1.8.9; KT 25 Nov ~19:35: "Resize cursor ability on versions except 18 should be off by
// default too, since it might affect how windows behave for users. If proved well, we can later make it on by default and even remove the
// toggle") ----
// Our preferences (com.besiktasliseba.macstatusbar) hold it only once the user flips it: never set, it is on on iPadOS 18 and later and off on
// 15-17; the user's own choice wins on every version. SpringBoard reads it with Pointer Style, live (StatusBar.x DMPointerBridgeTick, at once
// after Settings' prefsChanged), and says it to pointeruid in the MacPointer bridge's config word (MSBD_RZ_CONFIG_BIT). Off: SpringBoard follows
// no resize place (statusbar/ResizeFact.h: no hook, no recognizer, no word) and the pointer shows what 1.8.8.4 showed (MSBDPointerLook1884).
#define MSBD_RZ_PREF_KEY "macPointerResizePointers"
#define MSBD_RZ_CONFIG_BIT 16ULL   // (bit 4 of com.besiktasliseba.macpointer.config: bit 0 Pointer Style Mac, 2 the auto-hiding bar, 3 Pointer Control Style)
static inline bool MSBDResizePointersDefault(long osMajor) { return osMajor >= 18; }
// What is stored: -1 nothing (or no switch's value: an array, a date ...), 0 off, 1 on. A boolean as Settings' switch writes it; a number or a
// text as Settings' switch would show it (-boolValue: a number not 0; a text whose first character after spaces or tabs, one sign and zeros is
// Y, y, T, t or 1-9), so Settings and SpringBoard never disagree (the switch's review, finding 3).
static inline int MSBDResizePointersStored(CFTypeRef v) {
    if (!v) return -1;
    if (CFGetTypeID(v) == CFBooleanGetTypeID()) return CFBooleanGetValue((CFBooleanRef)v) ? 1 : 0;
    if (CFGetTypeID(v) == CFNumberGetTypeID()) { double d = 0; CFNumberGetValue((CFNumberRef)v, kCFNumberDoubleType, &d); return d != 0 ? 1 : 0; }
    if (CFGetTypeID(v) == CFStringGetTypeID()) {
        CFStringRef t = (CFStringRef)v;
        CFIndex n = CFStringGetLength(t), i = 0;
        UniChar c = 0;
        // (-boolValue skips Foundation's whitespace -- tab, the Unicode space separators, the zero-width space, not line ends; read on macOS 15.7 -- then one sign, then zeros)
        while (i < n && ((c = CFStringGetCharacterAtIndex(t, i)) == ' ' || c == '\t' || c == 0xA0 || c == 0x1680 || (c >= 0x2000 && c <= 0x200B) || c == 0x202F || c == 0x205F || c == 0x3000)) i++;
        if (i < n && ((c = CFStringGetCharacterAtIndex(t, i)) == '+' || c == '-')) i++;
        while (i < n && CFStringGetCharacterAtIndex(t, i) == '0') i++;
        if (i >= n) return 0;
        c = CFStringGetCharacterAtIndex(t, i);
        return c == 'Y' || c == 'y' || c == 'T' || c == 't' || (c >= '1' && c <= '9') ? 1 : 0;
    }
    return -1;
}
static inline bool MSBDResizePointersOn(int stored, long osMajor) { return stored < 0 ? MSBDResizePointersDefault(osMajor) : stored != 0; }
// The switch off: 1.8.8.4's look, by its own rule (MacPointer.x's MPUpdate as published in 1.8.8.4): iPadOS's own shape for a shape 4 pt or
// thinner or any type 4 (its text beam), the Mac arrow for everything else; no fact, no arrows, no latch read. (MIN as Foundation's: a < b ? a : b.)
static inline int MSBDPointerLook1884(long long type, CGRect sb) {
    bool thin = !CGRectIsEmpty(sb) && (sb.size.width < sb.size.height ? sb.size.width : sb.size.height) <= 4.0;
    return thin || type == 4 ? MSBD_PTR_BEAM : MSBD_PTR_ARROW;
}
// The latch: a press (the state's "pressed" going on) while the resize glyph shows keeps that glyph until the button is let go, wherever the
// pointer goes meanwhile (macOS's live resize); a pointer hidden by iPadOS ends it too. Returns whether it is latched now.
typedef struct { bool live, wasPressed; MSBDResizeFact fact; double graceUntil; } MSBDResizeLatch;
static inline bool MSBDResizeLatchStep(MSBDResizeLatch *l, bool pressed, bool hidden, bool showingResize, MSBDResizeFact shown) {
    if (!pressed || hidden) l->live = false;
    else if (!l->wasPressed && showingResize && MSBDResizeFactValid(shown)) { l->live = true; l->fact = shown; }
    l->wasPressed = pressed;   // (a press held through a hide is not a new press when the pointer shows again)
    return l->live;
}
// After the button-up of a GRIP's drag the press's glyph stays a moment (MSBD_RZ_LATCH_GRACE s) until SpringBoard's next word (its hover at the
// release, B0 15.6.1: at the same moment as the button-up) says what is under the pointer now: the corner followed the pointer, so it is usually the
// same glyph and no arrow blinks between. A word that arrives ends the grace at once (MSBDResizeLatchWord); a hidden pointer has none; a band's
// drag has none (F51 as it was: iPadOS's own shape there decides at once -- review 1.8.9 F51b, finding 2). now: seconds, any clock.
#define MSBD_RZ_LATCH_GRACE 0.15
static inline bool MSBDResizeLatchStepAt(MSBDResizeLatch *l, bool pressed, bool hidden, bool showingResize, MSBDResizeFact shown, double now) {
    bool was = l->live;
    bool live = MSBDResizeLatchStep(l, pressed, hidden, showingResize, shown);
    if (live) l->graceUntil = 0;
    else if (was && !hidden && l->fact.source == MSBD_RZ_SRC_GRIP) l->graceUntil = now + MSBD_RZ_LATCH_GRACE;
    else if (hidden) l->graceUntil = 0;
    return live;
}
static inline bool MSBDResizeLatchHolds(const MSBDResizeLatch *l, double now) { return l->live || now < l->graceUntil; }
// Only the grace holds (not a press): what shows then is never a new press's glyph (review 1.8.9 F51b, finding 3: a click right after a release, off
// the grip, latched the held glyph for its whole press).
static inline bool MSBDResizeLatchGraceOnly(const MSBDResizeLatch *l, double now) { return !l->live && now < l->graceUntil; }
static inline void MSBDResizeLatchWord(MSBDResizeLatch *l) { l->graceUntil = 0; }   // (SpringBoard said something new)

// ---- a grip's fact stays only while it is fresh (1.8.9, F51b; design section 12.13) ----
// Nothing of iPadOS confirms a grip's fact in pointeruid, so it lives on a lease: SpringBoard says it again (a new generation) every 0.5 s while it
// stands and at every hover inside the grip; pointeruid lets it go MSBD_RZ_GRIP_LEASE s after the last word (a SpringBoard that died, hangs or was
// turned off by the crash guard leaves no glyph behind), and at the first change of iPadOS's own pointer shape after it (the pointer went on over
// content faster than SpringBoard's word: an app's text beam or button shows at once). arrivedAt / shapeSeqAtArrival: when the word came and the
// shape count then.
#define MSBD_RZ_GRIP_LEASE 1.2
#define MSBD_RZ_GRIP_RESAY 0.4      // (SpringBoard's 0.2 s check says it again at its second tick: 0.4 s, at most ~0.45 with the timer's
                                    //  tolerance -- two words inside the lease even with one tick late; review 1.8.9 F51b, finding 4)
#define MSBD_RZ_GRIP_CHECK 0.2      // (SpringBoard's check while a grip's fact stands)
static inline bool MSBDResizeGripFresh(double now, double arrivedAt, unsigned long shapeSeqNow, unsigned long shapeSeqAtArrival) {
    return arrivedAt > 0 && now >= arrivedAt - 0.05 && now - arrivedAt <= MSBD_RZ_GRIP_LEASE && shapeSeqNow == shapeSeqAtArrival;
}
// SpringBoard's decision for a grip at a hover or a check (statusbar/ResizeFact.h DMRZGripDecide), as plain rules (review 1.8.9 F51b, finding 14):
// grip: a grip is the front-most taker at the point; same: the fact said now is that grip's, at the same place; again: a hover inside it (say it
// again at once: a hover is the freshest word); since: seconds since a fact was last said; factIsGrip: the fact said now is a grip's.
enum { MSBD_RZ_GRIP_NOTHING = 0, MSBD_RZ_GRIP_SAY = 1, MSBD_RZ_GRIP_SAY_AGAIN = 2, MSBD_RZ_GRIP_CLEAR = 3 };
static inline int MSBDResizeGripAction(bool grip, bool same, bool again, double since, bool factIsGrip) {
    if (!grip) return factIsGrip ? MSBD_RZ_GRIP_CLEAR : MSBD_RZ_GRIP_NOTHING;
    if (!same) return MSBD_RZ_GRIP_SAY;
    return (again || since >= MSBD_RZ_GRIP_RESAY - 0.01) ? MSBD_RZ_GRIP_SAY_AGAIN : MSBD_RZ_GRIP_NOTHING;
}
// The check of a standing grip fact goes on (SpringBoard's 0.2 s timer) unless: the screen's bounds changed since the point was read (a turn under
// a resting pointer: the old point means another place -- finding 11), or the fact is another display's and no hover came there for
// MSBD_RZ_GRIP_OTHER_REST s (pointeruid says the fade for the iPad's display only: there the fade note clears; elsewhere the lease ends it --
// finding 10). keep NO: the fact goes.
#define MSBD_RZ_GRIP_OTHER_REST 10.0
static inline bool MSBDResizeGripCheckKeeps(bool boundsSame, unsigned display, double sinceHover) {
    if (!boundsSame) return false;
    return !(display == 1 && sinceHover > MSBD_RZ_GRIP_OTHER_REST);
}

// ---- the glyphs ----
// Measured from macOS 15.6's NSCursor images (8x renders over mid grey, the black only; tools/test-macresizecursor.m), in macOS points:
//  - frame edges: a double arrow 12.6 tip to tip, heads 3.15 long and 6.4 across, shaft 1.65; hotspot (9, 9) in a 20 pt image, about 0.9 up and
//    left of the black's middle, as macOS's arrow's hotspot is 0.875 before its black tip (our arrow's tip is our hotspot: so our glyph's middle
//    is at our hotspot, 0.2 pt lower as macOS's sits); one-way: the outer half, its shaft running 3.7 past the middle;
//  - frame corners: the double arrow on the diagonal, 16.26 tip to tip (an 11.5 pt box), heads right-angled (6.4 across, 3.1 long), shaft 1.6;
//    one-way: the outer half, its shaft 2.0 past the middle (macOS moves the one-way corners' hotspots with the glyph: the same place);
//    (the numbers best fitting macOS's black: tools/test-macresizecursor.m, every one >= 0.85 of macOS's black, intersection over union)
//  - dividers (24 pt images, hotspot in the middle): the arrows 13.75 tip to tip, heads 2.7 long and 5.6 across, shaft 1.5, a bar 1.5 wide and
//    13.5 long across them; one-way: one arrow and the bar.
typedef struct { double x, y; } MSBDRZPt;
static inline void MSBDRZAddPoly(CGMutablePathRef p, const MSBDRZPt *pts, int n, double rot, double s, double dx, double dy) {
    double c = cos(rot), sn = sin(rot);
    for (int i = 0; i < n; i++) {
        double x = (pts[i].x * c - pts[i].y * sn + dx) * s, y = (pts[i].x * sn + pts[i].y * c + dy) * s;
        if (i == 0) CGPathMoveToPoint(p, NULL, x, y); else CGPathAddLineToPoint(p, NULL, x, y);
    }
    CGPathCloseSubpath(p);
}
// An arrow along +x (pointing right; a double one points both ways), centred on the hotspot: half its tip-to-tip length T, heads Lh long and Wh
// across, shaft Ws; a one-way one's shaft ends S behind the middle. Points into pts (at most 10); returns their number.
static inline int MSBDRZArrow(MSBDRZPt *pts, bool twoWay, double T, double Lh, double Wh, double Ws, double S) {
    double b = T - Lh, h = Wh / 2.0, w = Ws / 2.0; int n = 0;
    pts[n++] = (MSBDRZPt){ T, 0 }; pts[n++] = (MSBDRZPt){ b, h }; pts[n++] = (MSBDRZPt){ b, w };
    if (twoWay) { pts[n++] = (MSBDRZPt){ -b, w }; pts[n++] = (MSBDRZPt){ -b, h }; pts[n++] = (MSBDRZPt){ -T, 0 }; pts[n++] = (MSBDRZPt){ -b, -h }; pts[n++] = (MSBDRZPt){ -b, -w }; }
    else { pts[n++] = (MSBDRZPt){ -S, w }; pts[n++] = (MSBDRZPt){ -S, -w }; }
    pts[n++] = (MSBDRZPt){ b, -w }; pts[n++] = (MSBDRZPt){ b, -h };
    return n;
}
// A divider's arrows and bar as one outline (no inner edges for the white edge to draw): arrows along +x with the bar across x = 0. left / right:
// which arrows (macOS's column cursor's directions; a row is the same turned).
static inline int MSBDRZDivider(MSBDRZPt *pts, bool left, bool right) {
    const double T = 6.875, Lh = 2.7, h = 2.8, w = 0.75, bw = 0.75, bh = 6.75;   // (macOS pt; bar 1.5 x 13.5, shaft 1.5)
    double b = T - Lh; int n = 0;
    // from the bar's top right, clockwise (y down)
    pts[n++] = (MSBDRZPt){ bw, -bh };
    if (right) { pts[n++] = (MSBDRZPt){ bw, -w }; pts[n++] = (MSBDRZPt){ b, -w }; pts[n++] = (MSBDRZPt){ b, -h }; pts[n++] = (MSBDRZPt){ T, 0 };
                 pts[n++] = (MSBDRZPt){ b, h }; pts[n++] = (MSBDRZPt){ b, w }; pts[n++] = (MSBDRZPt){ bw, w }; }
    pts[n++] = (MSBDRZPt){ bw, bh }; pts[n++] = (MSBDRZPt){ -bw, bh };
    if (left) { pts[n++] = (MSBDRZPt){ -bw, w }; pts[n++] = (MSBDRZPt){ -b, w }; pts[n++] = (MSBDRZPt){ -b, h }; pts[n++] = (MSBDRZPt){ -T, 0 };
                pts[n++] = (MSBDRZPt){ -b, -h }; pts[n++] = (MSBDRZPt){ -b, -w }; pts[n++] = (MSBDRZPt){ -bw, -w }; }
    pts[n++] = (MSBDRZPt){ -bw, -bh };
    return n;
}
// The turn (radians, y down: clockwise) that takes an arrow pointing right (+x) to point out of the window at this position; 0 for none.
static inline double MSBDRZOutwardAngle(unsigned position) {
    switch (position) {
        case MSBD_RZ_RIGHT: return 0;
        case MSBD_RZ_BOTTOM | MSBD_RZ_RIGHT: return M_PI_4;
        case MSBD_RZ_BOTTOM: return M_PI_2;
        case MSBD_RZ_BOTTOM | MSBD_RZ_LEFT: return 3 * M_PI_4;
        case MSBD_RZ_LEFT: return M_PI;
        case MSBD_RZ_TOP | MSBD_RZ_LEFT: return -3 * M_PI_4;
        case MSBD_RZ_TOP: return -M_PI_2;
        case MSBD_RZ_TOP | MSBD_RZ_RIGHT: return -M_PI_4;
    }
    return 0;
}
// A key for one glyph (kind, position, directions), 0 for none: each glyph's path is made once and kept (MacPointer.x).
static inline unsigned MSBDResizeGlyphKey(MSBDResizeFact f) {
    if (!MSBDResizeFactValid(f)) return 0;
    unsigned d = f.directions;
    if (f.kind == MSBD_RZ_FRAME && d == MSBD_RZ_ALL) {   // (a double arrow is the same both ways: one key per axis)
        unsigned p = f.position;
        if (p == MSBD_RZ_BOTTOM) p = MSBD_RZ_TOP;
        else if (p == MSBD_RZ_RIGHT) p = MSBD_RZ_LEFT;
        else if (p == (MSBD_RZ_BOTTOM | MSBD_RZ_RIGHT)) p = MSBD_RZ_TOP | MSBD_RZ_LEFT;
        else if (p == (MSBD_RZ_BOTTOM | MSBD_RZ_LEFT)) p = MSBD_RZ_TOP | MSBD_RZ_RIGHT;
        return 1 | (p << 4) | (d << 8);
    }
    return f.kind | (f.position << 4) | (d << 8);
}
// The glyph's path in our units, hotspot at (0, 0) (a new path: the caller keeps or releases it); NULL for none.
static inline CGPathRef MSBDResizeGlyphCreate(MSBDResizeFact f) {
    if (!MSBDResizeFactValid(f)) return NULL;
    MSBDRZPt pts[20]; int n = 0; double rot = 0, dx = 0, dy = 0;
    if (f.kind == MSBD_RZ_FRAME) {
        bool corner = (f.position & (MSBD_RZ_LEFT | MSBD_RZ_RIGHT)) && (f.position & (MSBD_RZ_TOP | MSBD_RZ_BOTTOM));
        double T = corner ? 8.13 : 6.3, Lh = corner ? 3.1 : 3.15, Wh = 6.4, Ws = corner ? 1.6 : 1.65, S = corner ? 2.0 : 3.7;
        dx = corner ? 0 : 0.06; dy = 0.2;
        rot = MSBDRZOutwardAngle(f.position);
        if (f.directions == MSBD_RZ_INWARD) rot += M_PI;
        n = MSBDRZArrow(pts, f.directions == MSBD_RZ_ALL, T, Lh, Wh, Ws, S);
    } else {
        n = MSBDRZDivider(pts, f.directions & 1, (f.directions & 2) != 0);
        if (f.kind == MSBD_RZ_ROW) rot = M_PI_2;   // (up 1 / down 2: the column's left / right turned a quarter clockwise -- left goes up)
    }
    if (f.kind == MSBD_RZ_ROW) {   // (a quarter turn clockwise takes -x (left) to -y (up): the column's "left" arrow becomes the row's "up" one)
        for (int i = 0; i < n; i++) { double x = pts[i].x; pts[i].x = -pts[i].y; pts[i].y = x; }
        rot = 0;
    }
    CGMutablePathRef p = CGPathCreateMutable();
    MSBDRZAddPoly(p, pts, n, rot, MSBD_RZ_UNIT, dx, dy);
    return p;
}
#endif
