// DockStyle.h -- Settings > Dock > Dock Style (MacStatusBar&Dock 1.8.4 item 3): the Dock as Mac OS X drew it before today's, drawn by us in plain
// CoreGraphics (no Apple picture is shipped or read), shared by the Dock (dock/DockStyle.m) and the Mac test, which renders every style to PNG
// (tools/test-dockstyle.sh) so the drawing can be looked at without an iPad.
//  - Default: today's Dock, iPadOS's own platter (nothing of ours is drawn).
//  - Glass Shelf (Mac OS X 10.5 to 10.9): a 3D glass shelf the icons stand on, seen from above -- its top a trapezoid (narrower at the back), a bright
//    front lip, a darker front face --, the icons' reflections on it, and the open apps' glowing blue-white lights on the lip. At a side the Mac's
//    Dock was a flat dark panel in those years, so a side Dock is that panel (with white lights).
//  - Frosted (10.10 to 10.15): a flat translucent rectangle with small corners -- the system's blur under a light (or, in Dark Mode, dark) tint
//    and a thin border --, the open apps' small dots as today.
// All sizes come from the platter's own bounds and the icons' picture height, so every Icon Size, Magnification and position keeps working.
#ifndef MSBD_DOCK_STYLE_H
#define MSBD_DOCK_STYLE_H
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <string.h>

#define kMSBDDockStyleKey "dockStyle"   // (com.besiktasliseba.dockmagnification) "glass" or "frosted"; anything else, or never set: Default
enum { MSBDDockStyleDefault = 0, MSBDDockStyleGlass = 1, MSBDDockStyleFrosted = 2 };
static inline int MSBDDockStyleFromString(const char *s) {
    if (!s) return MSBDDockStyleDefault;
    if (!strcmp(s, "glass")) return MSBDDockStyleGlass;
    if (!strcmp(s, "frosted")) return MSBDDockStyleFrosted;
    return MSBDDockStyleDefault;
}
// What a style draws at a side (the Dock turned): Glass Shelf becomes the dark panel, as on a Mac of those years; Frosted stays frosted.
enum { MSBDDockLookDefault = 0, MSBDDockLookShelf = 1, MSBDDockLookDarkPanel = 2, MSBDDockLookFrosted = 3 };
static inline int MSBDDockStyleLook(int style, int side) {
    if (style == MSBDDockStyleGlass) return side ? MSBDDockLookDarkPanel : MSBDDockLookShelf;
    if (style == MSBDDockStyleFrosted) return MSBDDockLookFrosted;
    return MSBDDockLookDefault;
}

// ---- the glass shelf's geometry (y down, in the platter's own space) ----
// depth: the shelf's height on the screen, a share of the icons' picture (48 %), never more than 42 % of the platter; lip: the front face's height;
// top: where the shelf's top surface starts (its back edge); front: where the lip begins; back: how far the back edge is inset at each end (the
// perspective: the back edge is narrower than the front).
typedef struct { double top, front, bottom, backInset, lip; } MSBDShelf;
static inline MSBDShelf MSBDShelfGeometry(CGRect b, double picture) {
    MSBDShelf s;
    double depth = picture * 0.48, cap = b.size.height * 0.42;
    if (!(depth > 6.0)) depth = 6.0;
    if (depth > cap) depth = cap;
    s.lip = fmax(3.0, round(depth * 0.18));
    s.bottom = CGRectGetMaxY(b);
    s.front = s.bottom - s.lip;
    s.top = s.bottom - depth;
    s.backInset = round(depth * 0.9);
    return s;
}
// The top surface (a trapezoid) as a path.
static inline CGPathRef MSBDShelfTopPath(CGRect b, MSBDShelf s) {
    CGMutablePathRef p = CGPathCreateMutable();
    CGPathMoveToPoint(p, NULL, CGRectGetMinX(b) + s.backInset, s.top);
    CGPathAddLineToPoint(p, NULL, CGRectGetMaxX(b) - s.backInset, s.top);
    CGPathAddLineToPoint(p, NULL, CGRectGetMaxX(b), s.front);
    CGPathAddLineToPoint(p, NULL, CGRectGetMinX(b), s.front);
    CGPathCloseSubpath(p);
    return p;
}
static inline void MSBDFillGradient(CGContextRef c, CGPathRef clip, CGPoint a, CGPoint z, const CGFloat *rgba, const CGFloat *stops, size_t n) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGGradientRef g = CGGradientCreateWithColorComponents(cs, rgba, stops, n);
    CGContextSaveGState(c);
    CGContextAddPath(c, clip);
    CGContextClip(c);
    CGContextDrawLinearGradient(c, g, a, z, kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    CGContextRestoreGState(c);
    CGGradientRelease(g);
    CGColorSpaceRelease(cs);
}
// The shelf: a soft shadow under it, the top surface (frosted glass, lighter toward the front, a faint blue at the back), the bright lip line, the
// front face (lighter at its top), a dark line under it.
static inline void MSBDDrawGlassShelf(CGContextRef c, CGRect b, MSBDShelf s) {
    CGPathRef top = MSBDShelfTopPath(b, s);
    CGColorSpaceRef gs = CGColorSpaceCreateDeviceGray();
    const CGFloat shadowGray[] = { 0.0, 0.35 };
    CGColorRef shadow = CGColorCreate(gs, shadowGray);
    CGContextSaveGState(c);
    CGContextSetShadowWithColor(c, CGSizeMake(0, 2), 6, shadow);
    CGContextAddPath(c, top);
    CGContextAddRect(c, CGRectMake(CGRectGetMinX(b), s.front, b.size.width, s.lip));
    CGContextSetRGBFillColor(c, 0.80, 0.84, 0.90, 0.22);   // (a light base for the shadow; the glass shows the wallpaper through)
    CGContextFillPath(c);
    CGContextRestoreGState(c);
    CGColorRelease(shadow);
    CGColorSpaceRelease(gs);
    const CGFloat topColors[] = { 0.80, 0.88, 0.98, 0.22,   0.93, 0.95, 0.99, 0.42,   1.00, 1.00, 1.00, 0.72 };
    const CGFloat topStops[] = { 0.0, 0.55, 1.0 };
    MSBDFillGradient(c, top, CGPointMake(0, s.top), CGPointMake(0, s.front), topColors, topStops, 3);
    // the back edge: a thin light line
    CGContextSetRGBStrokeColor(c, 1, 1, 1, 0.45);
    CGContextSetLineWidth(c, 1.0);
    CGContextMoveToPoint(c, CGRectGetMinX(b) + s.backInset, s.top + 0.5);
    CGContextAddLineToPoint(c, CGRectGetMaxX(b) - s.backInset, s.top + 0.5);
    CGContextStrokePath(c);
    // the front face
    CGMutablePathRef face = CGPathCreateMutable();
    CGPathAddRect(face, NULL, CGRectMake(CGRectGetMinX(b), s.front, b.size.width, s.lip));
    const CGFloat faceColors[] = { 0.86, 0.88, 0.92, 0.85,   0.55, 0.58, 0.64, 0.75 };
    const CGFloat faceStops[] = { 0.0, 1.0 };
    MSBDFillGradient(c, face, CGPointMake(0, s.front), CGPointMake(0, s.bottom), faceColors, faceStops, 2);
    CGPathRelease(face);
    // the lip: a bright line where the top meets the front, and a dark one at the very bottom
    CGContextSetRGBStrokeColor(c, 1, 1, 1, 0.95);
    CGContextSetLineWidth(c, 1.0);
    CGContextMoveToPoint(c, CGRectGetMinX(b), s.front + 0.5);
    CGContextAddLineToPoint(c, CGRectGetMaxX(b), s.front + 0.5);
    CGContextStrokePath(c);
    CGContextSetRGBStrokeColor(c, 0, 0, 0, 0.35);
    CGContextMoveToPoint(c, CGRectGetMinX(b), s.bottom - 0.5);
    CGContextAddLineToPoint(c, CGRectGetMaxX(b), s.bottom - 0.5);
    CGContextStrokePath(c);
    CGPathRelease(top);
}
// A rounded rectangle path.
static inline CGPathRef MSBDRoundRectPath(CGRect r, double radius) {
    double rr = fmin(radius, fmin(r.size.width, r.size.height) / 2.0);
    return CGPathCreateWithRoundedRect(r, rr, rr, NULL);
}
// The side panel (Glass Shelf at a side): dark translucent glass, a light edge inside, small corners.
static inline double MSBDDarkPanelCorner(CGRect b) { return fmin(10.0, fmin(b.size.width, b.size.height) * 0.12); }
static inline void MSBDDrawDarkPanel(CGContextRef c, CGRect b) {
    CGRect r = CGRectInset(b, 0.5, 0.5);
    CGPathRef p = MSBDRoundRectPath(r, MSBDDarkPanelCorner(b));
    const CGFloat colors[] = { 0.16, 0.17, 0.19, 0.78,   0.06, 0.06, 0.07, 0.86 };
    const CGFloat stops[] = { 0.0, 1.0 };
    MSBDFillGradient(c, p, CGPointMake(0, CGRectGetMinY(r)), CGPointMake(0, CGRectGetMaxY(r)), colors, stops, 2);
    CGContextAddPath(c, p);
    CGContextSetRGBStrokeColor(c, 1, 1, 1, 0.28);
    CGContextSetLineWidth(c, 1.0);
    CGContextStrokePath(c);
    CGPathRelease(p);
}
// Frosted: over the system's blur (the Dock draws it under this), a light tint (Dark Mode: a dark one) and a thin border; corners of 6 pt.
#define MSBD_FROSTED_CORNER 6.0
static inline void MSBDDrawFrostedTint(CGContextRef c, CGRect b, int dark) {
    CGRect r = CGRectInset(b, 0.25, 0.25);
    CGPathRef p = MSBDRoundRectPath(r, MSBD_FROSTED_CORNER);
    CGContextAddPath(c, p);
    if (dark) CGContextSetRGBFillColor(c, 0.12, 0.12, 0.13, 0.42); else CGContextSetRGBFillColor(c, 0.97, 0.97, 0.98, 0.38);
    CGContextFillPath(c);
    CGContextAddPath(c, p);
    if (dark) CGContextSetRGBStrokeColor(c, 1, 1, 1, 0.16); else CGContextSetRGBStrokeColor(c, 1, 1, 1, 0.55);
    CGContextSetLineWidth(c, 0.5);
    CGContextStrokePath(c);
    CGPathRelease(p);
}

// ---- the open apps' lights ----
// Glass Shelf: a glowing blue-white light on the lip (an ellipse, white at its heart, blue around, fading out), dot: today's dot's size.
static inline CGSize MSBDGlassLightSize(double dot) { return CGSizeMake(round(dot * 3.2), round(dot * 1.9)); }
static inline CGRect MSBDGlassLightRect(double centerX, MSBDShelf s, double dot) {
    CGSize z = MSBDGlassLightSize(dot);
    return CGRectMake(round(centerX - z.width / 2.0), round(s.front - z.height / 2.0 + 0.5), z.width, z.height);
}
static inline void MSBDDrawGlowDot(CGContextRef c, CGRect r, int blue) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    const CGFloat blueGlow[] = { 1, 1, 1, 1,   0.80, 0.93, 1.0, 0.95,   0.45, 0.72, 1.0, 0.55,   0.40, 0.65, 1.0, 0.0 };
    const CGFloat whiteGlow[] = { 1, 1, 1, 1,   1, 1, 1, 0.85,   0.85, 0.90, 1.0, 0.35,   0.85, 0.90, 1.0, 0.0 };
    const CGFloat stops[] = { 0.0, 0.22, 0.55, 1.0 };
    CGGradientRef g = CGGradientCreateWithColorComponents(cs, blue ? blueGlow : whiteGlow, stops, 4);
    CGContextSaveGState(c);
    CGContextTranslateCTM(c, CGRectGetMidX(r), CGRectGetMidY(r));
    CGContextScaleCTM(c, r.size.width / 2.0, r.size.height / 2.0);   // (a circle of radius 1, stretched to the light's ellipse)
    CGContextDrawRadialGradient(c, g, CGPointZero, 0, CGPointZero, 1.0, 0);
    CGContextRestoreGState(c);
    CGGradientRelease(g);
    CGColorSpaceRelease(cs);
}
// At a side (the dark panel): a small white light, twice the dot.
static inline CGSize MSBDPanelLightSize(double dot) { return CGSizeMake(round(dot * 2.2), round(dot * 2.2)); }

// ---- the icons' reflections on the shelf ----
// An icon's picture (its frame in the platter's space) reflected in the shelf's top: flipped below the picture's bottom, squashed to the shelf's
// depth, from the picture's bottom down to the lip; clear past the lip. Returns the reflection's frame (its height 0: no room).
static inline CGRect MSBDReflectionFrame(CGRect picture, MSBDShelf s) {
    double y = CGRectGetMaxY(picture), h = fmin(picture.size.height * 0.5, s.front - y);
    if (!(h > 1.0)) return CGRectMake(picture.origin.x, y, picture.size.width, 0);
    return CGRectMake(picture.origin.x, y, picture.size.width, h);
}
#define MSBD_REFLECTION_ALPHA 0.40
// One icon's reflection from one Dock layout to the next (dock/DockStyle.m; review 1.8.4 P2-M1: they heal themselves). Each icon keeps one holder
// for as long as it is in the Dock; the snapshot in it is taken again only for a new or changed picture (review 1.8.4 L10), and the picture's
// check value is recorded only by the confirm, a turn of the main run loop later, from a snapshot taken then of a picture that has been drawn: a
// snapshot of a view not drawn yet is empty, and a value recorded from it kept the blank one for good.
// At a layout -- hasPic: the icon's picture shows now; recordedSame: the value recorded for the snapshot held is the picture's now; wantedSame: a
// snapshot of the picture as it is now waits for its confirm; drawn: the picture has been drawn (in a window, its layer committed once). Never a
// record here, and never a reflection dropped for a picture missing at one layout (the launch zoom, a drag): it is kept, hidden, and shows again
// with the picture.
enum { MSBDReflShow = 0, MSBDReflHide = 1, MSBDReflWant = 2, MSBDReflTakeNow = 4 };   // (bits)
static inline int MSBDReflectionAtLayout(int hasPic, int recordedSame, int wantedSame, int drawn) {
    if (!hasPic) return MSBDReflHide;
    if (recordedSame || wantedSame) return MSBDReflShow;
    return MSBDReflWant | (drawn ? MSBDReflTakeNow : 0);   // (a snapshot now only of a drawn picture: shown at once, recorded at the confirm)
}
// The confirm: the main run loop's next turn after a layout wanted a snapshot (or hid a reflection), then again a little later while one waits
// (MSBDReflectionRetryDelay), MSBD_REFLECTION_TRIES rounds at most. A picture that shows and has been drawn: its snapshot is taken again and its
// value recorded; else it waits. At the last round a picture that shows as it is -- in its window, its layers committed, only its own "real image"
// answer still no: a Dock folder, an app being installed or offloaded, which draw that for as long as they are there -- is recorded as it shows,
// so no layout arms the rounds for it again (review 1.8.4 P3-L2); one not even that far: the wish goes, and the next layout wants it again.
#define MSBD_REFLECTION_TRIES 6
enum { MSBDReflRecord = 1, MSBDReflWait = 2, MSBDReflGiveUp = 3 };
static inline int MSBDReflectionAtConfirm(int hasPic, int drawn, int tries, int shownAsIs) {
    if (hasPic && drawn) return MSBDReflRecord;
    if (tries + 1 < MSBD_REFLECTION_TRIES) return MSBDReflWait;
    return hasPic && shownAsIs ? MSBDReflRecord : MSBDReflGiveUp;
}
static inline double MSBDReflectionRetryDelay(int tries) {   // (seconds before round `tries`: 0 = the next turn)
    static const double d[MSBD_REFLECTION_TRIES] = { 0.0, 0.1, 0.25, 0.5, 1.0, 2.0 };
    return d[tries < 0 ? 0 : tries >= MSBD_REFLECTION_TRIES ? MSBD_REFLECTION_TRIES - 1 : tries];
}

// ---- what the styles take from iPadOS's own platter ----
// Default: nothing. Any other look: iPadOS's background (its material) and its shadow are hidden while ours shows, and given back with Default.
static inline int MSBDDockStyleHidesApple(int look) { return look != MSBDDockLookDefault; }
#endif
