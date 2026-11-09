// test-dockstyle.c: Dock Style, the plain C (common/DockStyle.h, 1.8.4 item 3): the stored choice, what each style draws at the bottom and at a side,
// the glass shelf's geometry for every icon size, the lights and the reflections' places -- and every look drawn into a PNG (argv[1]: a folder;
// none: drawn but not written), on a wallpaper-like background with made-up icons, so the drawing itself can be looked at on the Mac.
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#include <CoreFoundation/CoreFoundation.h>
#include "../common/DockStyle.h"
static int fails = 0;
static void check(const char *what, int ok) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what); if (!ok) fails = 1; }
static int near(double a, double b) { return fabs(a - b) < 0.001; }

// ---- one icon's reflection from layout to layout (review 1.8.4 P2-M1): the rules (MSBDReflectionAtLayout / AtConfirm), run as DockStyle.m runs
// them. A picture is a number (0: missing); held: the picture the holder's snapshot shows; recorded / wanted: the values kept on the holder.
typedef struct { int held, recorded, wanted, hidden, snapshots; } Refl;
static void reflLayout(Refl *r, int pic, int drawn) {
    int act = MSBDReflectionAtLayout(pic != 0, r->recorded && r->recorded == pic, r->wanted && r->wanted == pic, drawn);
    if (act & MSBDReflHide) { r->hidden = 1; return; }
    if (act & MSBDReflWant) { r->recorded = 0; r->wanted = pic; if (act & MSBDReflTakeNow) { r->held = pic; r->snapshots++; } }
    r->hidden = !r->held;
}
static int reflConfirmAs(Refl *r, int pic, int drawn, int tries, int shownAsIs) {
    int act = 0;
    if (r->wanted) {
        act = MSBDReflectionAtConfirm(pic != 0, drawn, tries, shownAsIs);
        if (act == MSBDReflRecord) { r->held = pic; r->snapshots++; r->recorded = pic; r->wanted = 0; }
        else if (act == MSBDReflGiveUp) r->wanted = 0;
    }
    r->hidden = !pic || !r->held;
    return act;
}
static int reflConfirm(Refl *r, int pic, int drawn, int tries) { return reflConfirmAs(r, pic, drawn, tries, 0); }
static void reflections(void) {
    int onlyBits = 1, hideAlone = 1, takeOnlyDrawn = 1;
    for (int k = 0; k < 16; k++) {
        int act = MSBDReflectionAtLayout(k & 1, (k >> 1) & 1, (k >> 2) & 1, (k >> 3) & 1);
        if (act & ~(MSBDReflHide | MSBDReflWant | MSBDReflTakeNow)) onlyBits = 0;
        if (!(k & 1) && act != MSBDReflHide) hideAlone = 0;
        if ((act & MSBDReflTakeNow) && (!((k >> 3) & 1) || !(act & MSBDReflWant))) takeOnlyDrawn = 0;
    }
    check("P2-M1: a layout never records a picture's value, and takes a snapshot only of a drawn picture it wants", onlyBits && takeOnlyDrawn);
    check("  ... a picture missing at a layout: its reflection is kept, hidden (never dropped)", hideAlone);
    Refl r = {0};
    reflLayout(&r, 7, 0);
    int first = r.snapshots == 0 && r.recorded == 0 && r.wanted == 7 && r.hidden;
    int act = reflConfirm(&r, 7, 1, 0);
    check("  ... a new icon laid out before it was drawn: no snapshot then; the confirm a turn later takes it and only then records it",
          first && act == MSBDReflRecord && r.recorded == 7 && r.held == 7 && r.snapshots == 1 && !r.hidden);
    Refl w = {0};
    reflLayout(&w, 7, 0);
    int waits = 1;
    for (int t = 0; t < MSBD_REFLECTION_TRIES; t++) {
        int a = reflConfirm(&w, 7, 0, t);
        if (a != (t + 1 < MSBD_REFLECTION_TRIES ? MSBDReflWait : MSBDReflGiveUp) || w.recorded) waits = 0;
    }
    reflLayout(&w, 7, 1);
    check("  ... still not drawn at the confirm: it waits, nothing recorded; after the last round the wish goes and the next layout wants it again",
          waits && w.wanted == 7 && w.snapshots == 1 && w.recorded == 0 && reflConfirm(&w, 7, 1, 0) == MSBDReflRecord && w.recorded == 7);
    int before = r.snapshots;
    reflLayout(&r, 0, 0);
    int keptHidden = r.hidden && r.recorded == 7 && r.held == 7;
    reflLayout(&r, 7, 1);
    check("  ... a picture missing at one layout (the launch zoom, a drag): kept hidden with its value; back at the next layout with no new snapshot",
          keptHidden && !r.hidden && r.snapshots == before && r.recorded == 7);
    reflLayout(&r, 0, 0);
    reflConfirm(&r, 7, 1, 0);
    check("  ... or back at the confirm, with no layout in between", !r.hidden && r.snapshots == before);
    reflLayout(&r, 9, 1);
    int changed = r.held == 9 && r.recorded == 0 && r.wanted == 9 && r.snapshots == before + 1;
    reflLayout(&r, 9, 1);
    int noSecond = r.snapshots == before + 1;
    reflConfirm(&r, 9, 1, 0);
    check("  ... a changed picture: its snapshot now, none more while it waits, recorded only at the confirm (one snapshot more there)",
          changed && noSecond && r.recorded == 9 && r.wanted == 0 && r.snapshots == before + 2);
    // P3-L2: a picture that only says "not my real image" for good (a Dock folder, an app being installed): recorded as it shows at the last round,
    // so the next layout does not arm the rounds again; one not committed even then gives up as before
    Refl f = {0};
    reflLayout(&f, 5, 0);
    int foldWaits = 1;
    for (int t = 0; t + 1 < MSBD_REFLECTION_TRIES; t++) if (reflConfirmAs(&f, 5, 0, t, 1) != MSBDReflWait || f.recorded) foldWaits = 0;
    int lastRecords = reflConfirmAs(&f, 5, 0, MSBD_REFLECTION_TRIES - 1, 1) == MSBDReflRecord && f.recorded == 5 && !f.hidden;
    int snaps = f.snapshots;
    reflLayout(&f, 5, 0);
    check("P3-L2: a folder's or an installing app's picture (never \"real\"): it waits the rounds, the last one records it as it shows, and the next layout arms nothing",
          foldWaits && lastRecords && f.wanted == 0 && f.snapshots == snaps && !f.hidden);
    Refl g = {0};
    reflLayout(&g, 5, 0);
    for (int t = 0; t + 1 < MSBD_REFLECTION_TRIES; t++) reflConfirmAs(&g, 5, 0, t, 0);
    check("  ... one not even committed at the last round: the wish goes (the next layout wants it again), nothing recorded",
          reflConfirmAs(&g, 5, 0, MSBD_REFLECTION_TRIES - 1, 0) == MSBDReflGiveUp && g.recorded == 0 && g.wanted == 0);
    check("  ... and a missing picture is never recorded at the last round", MSBDReflectionAtConfirm(0, 0, MSBD_REFLECTION_TRIES - 1, 1) == MSBDReflGiveUp);
    double total = 0; int rising = MSBDReflectionRetryDelay(0) == 0.0;
    for (int t = 1; t < MSBD_REFLECTION_TRIES; t++) { total += MSBDReflectionRetryDelay(t); if (MSBDReflectionRetryDelay(t) <= MSBDReflectionRetryDelay(t - 1)) rising = 0; }
    check("  ... the confirm: the next turn first, then later and later, all within 4 s", rising && total < 4.0);
}

// ---- a picture of a Dock: background, the look, made-up icons, their lights and reflections ----
static void icon(CGContextRef c, CGRect r, double hue) {
    double rr = r.size.width * 0.225;
    CGPathRef p = CGPathCreateWithRoundedRect(r, rr, rr, NULL);
    CGContextAddPath(c, p);
    CGContextSetRGBFillColor(c, 0.3 + 0.6 * fabs(sin(hue)), 0.3 + 0.6 * fabs(sin(hue + 2.1)), 0.3 + 0.6 * fabs(sin(hue + 4.2)), 1);
    CGContextFillPath(c);
    CGContextAddPath(c, p);
    CGContextSetRGBStrokeColor(c, 1, 1, 1, 0.35);
    CGContextStrokePath(c);
    CGPathRelease(p);
}
static int render(const char *dir, const char *name, int look, int dark, double W, double H, double picture, int n) {
    double scale = 2.0, pad = 40;
    size_t pw = (size_t)((W + 2 * pad) * scale), ph = (size_t)((H + 2 * pad) * scale);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, pw, ph, 8, 0, cs, kCGImageAlphaPremultipliedLast);
    if (!c) { CGColorSpaceRelease(cs); return 0; }
    CGContextTranslateCTM(c, 0, ph); CGContextScaleCTM(c, scale, -scale);   // (y down, in points, as UIKit draws)
    // a wallpaper: a soft gradient, dark or light
    const CGFloat wall[] = { dark ? 0.10 : 0.55, dark ? 0.12 : 0.70, dark ? 0.20 : 0.92, 1,   dark ? 0.25 : 0.95, dark ? 0.10 : 0.62, dark ? 0.30 : 0.70, 1 };
    const CGFloat ws[] = { 0, 1 };
    CGGradientRef g = CGGradientCreateWithColorComponents(cs, wall, ws, 2);
    CGContextDrawLinearGradient(c, g, CGPointMake(0, 0), CGPointMake(W + 2 * pad, H + 2 * pad), 0);
    CGGradientRelease(g);
    CGContextTranslateCTM(c, pad, pad);
    CGRect b = CGRectMake(0, 0, W, H);
    double gap = (W - n * picture) / (n + 1), y = (H - picture) / 2.0;
    MSBDShelf s = MSBDShelfGeometry(b, picture);
    if (look == MSBDDockLookShelf) MSBDDrawGlassShelf(c, b, s);
    else if (look == MSBDDockLookDarkPanel) MSBDDrawDarkPanel(c, b);
    else if (look == MSBDDockLookFrosted) MSBDDrawFrostedTint(c, b, dark);
    else { CGPathRef p = MSBDRoundRectPath(b, 24); CGContextAddPath(c, p); CGContextSetRGBFillColor(c, 1, 1, 1, dark ? 0.12 : 0.35); CGContextFillPath(c); CGPathRelease(p); }
    for (int i = 0; i < n; i++) {
        CGRect r = CGRectMake(gap + i * (picture + gap), y, picture, picture);
        if (look == MSBDDockLookShelf) {   // its reflection: flipped, squashed, faded, clipped to the shelf's top
            CGRect f = MSBDReflectionFrame(r, s);
            if (f.size.height > 0) {
                CGContextSaveGState(c);
                CGPathRef top = MSBDShelfTopPath(b, s);
                CGContextAddPath(c, top); CGContextClip(c); CGPathRelease(top);
                CGContextSetAlpha(c, MSBD_REFLECTION_ALPHA);
                CGContextTranslateCTM(c, 0, CGRectGetMaxY(r)); CGContextScaleCTM(c, 1, -f.size.height / (r.size.height * 0.5)); CGContextTranslateCTM(c, 0, -CGRectGetMaxY(r));
                icon(c, r, i * 1.3);
                CGContextRestoreGState(c);
            }
        }
        icon(c, r, i * 1.3);
        if (i % 2 == 0) {   // every other app open: its light
            double dot = 4.0;
            if (look == MSBDDockLookShelf) MSBDDrawGlowDot(c, MSBDGlassLightRect(CGRectGetMidX(r), s, dot), 1);
            else if (look == MSBDDockLookDarkPanel) { CGSize z = MSBDPanelLightSize(dot); MSBDDrawGlowDot(c, CGRectMake(CGRectGetMidX(r) - z.width / 2, CGRectGetMaxY(r) + 4, z.width, z.height), 0); }
            else { CGContextSetRGBFillColor(c, dark ? 1 : 0, dark ? 1 : 0, dark ? 1 : 0, 0.85); CGContextFillEllipseInRect(c, CGRectMake(CGRectGetMidX(r) - dot / 2, CGRectGetMaxY(r) + 4, dot, dot)); }
        }
    }
    int ok = 1;
    if (dir) {
        CGImageRef img = CGBitmapContextCreateImage(c);
        char path[1024]; snprintf(path, sizeof path, "%s/%s.png", dir, name);
        CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, (CFIndex)strlen(path), false);
        CGImageDestinationRef d = CGImageDestinationCreateWithURL(url, CFSTR("public.png"), 1, NULL);
        if (d) { CGImageDestinationAddImage(d, img, NULL); ok = CGImageDestinationFinalize(d); CFRelease(d); } else ok = 0;
        CFRelease(url); CGImageRelease(img);
    }
    CGContextRelease(c); CGColorSpaceRelease(cs);
    return ok;
}

int main(int argc, char **argv) {
    const char *dir = argc > 1 ? argv[1] : NULL;
    check("the stored choice: \"glass\", \"frosted\"; anything else or nothing: Default", MSBDDockStyleFromString("glass") == MSBDDockStyleGlass && MSBDDockStyleFromString("frosted") == MSBDDockStyleFrosted
          && MSBDDockStyleFromString(NULL) == MSBDDockStyleDefault && MSBDDockStyleFromString("default") == MSBDDockStyleDefault && MSBDDockStyleFromString("x") == MSBDDockStyleDefault);
    check("  ... the key: dockStyle", !strcmp(kMSBDDockStyleKey, "dockStyle"));
    check("Glass Shelf: the shelf at the bottom, the flat dark panel at a side (as a Mac's side Dock in 10.5-10.9)",
          MSBDDockStyleLook(MSBDDockStyleGlass, 0) == MSBDDockLookShelf && MSBDDockStyleLook(MSBDDockStyleGlass, 1) == MSBDDockLookDarkPanel && MSBDDockStyleLook(MSBDDockStyleGlass, 2) == MSBDDockLookDarkPanel);
    check("Frosted: frosted at the bottom and at a side; Default: iPadOS's own everywhere", MSBDDockStyleLook(MSBDDockStyleFrosted, 0) == MSBDDockLookFrosted && MSBDDockStyleLook(MSBDDockStyleFrosted, 1) == MSBDDockLookFrosted
          && MSBDDockStyleLook(MSBDDockStyleDefault, 0) == MSBDDockLookDefault && MSBDDockStyleLook(MSBDDockStyleDefault, 2) == MSBDDockLookDefault);
    check("  ... only a look of ours hides iPadOS's background and shadow", !MSBDDockStyleHidesApple(MSBDDockLookDefault) && MSBDDockStyleHidesApple(MSBDDockLookShelf) && MSBDDockStyleHidesApple(MSBDDockLookFrosted));
    // the shelf for a platter of 900 x 90 with 64 pt pictures (an iPad Pro's landscape Dock)
    MSBDShelf s = MSBDShelfGeometry(CGRectMake(0, 0, 900, 90), 64);
    check("the shelf: 48 % of the picture deep (30.72 pt), from 59.28 to the platter's bottom (90), its lip 6 pt, its back 28 pt narrower each side",
          near(s.bottom, 90) && near(s.top, 59.28) && near(s.lip, 6) && near(s.front, 84) && near(s.backInset, 28));
    int sane = 1;
    for (double pic = 20; pic <= 120; pic += 7) for (double h = 40; h <= 160; h += 11) {
        MSBDShelf q = MSBDShelfGeometry(CGRectMake(0, 0, 600, h), pic);
        if (!(q.top >= h * 0.58 - 1e-9 && q.top < q.front && q.front < q.bottom && near(q.bottom, h) && q.lip >= 3 && q.backInset > 0 && q.backInset < 300)) sane = 0;
    }
    check("  ... for every picture and platter size: inside the platter's lower 42 %, back before lip before bottom, the back inset less than half", sane);
    CGRect lr = MSBDGlassLightRect(450, s, 4);
    check("a glass light: an ellipse 3.2 x 1.9 dots, centred under the icon on the lip", near(lr.size.width, 13) && near(lr.size.height, 8) && near(CGRectGetMidX(lr), 450.5) && fabs(CGRectGetMidY(lr) - s.front) <= 1.0);
    CGRect pic = CGRectMake(100, 13, 64, 64), rf = MSBDReflectionFrame(pic, s);
    check("a reflection: from the picture's bottom (77) to the lip (84), the picture's width", near(rf.origin.y, 77) && near(rf.size.height, 7) && near(rf.size.width, 64) && near(rf.origin.x, 100));
    check("  ... a picture whose bottom is past the lip: no reflection", MSBDReflectionFrame(CGRectMake(0, 80, 64, 64), s).size.height == 0);
    reflections();
    // the pictures (written only with a folder given)
    int drawn = render(dir, "glass-shelf", MSBDDockLookShelf, 0, 900, 90, 64, 8) && render(dir, "glass-shelf-dark", MSBDDockLookShelf, 1, 900, 90, 64, 8)
             && render(dir, "glass-side-panel", MSBDDockLookDarkPanel, 0, 90, 600, 60, 1) && render(dir, "frosted-light", MSBDDockLookFrosted, 0, 900, 90, 64, 8)
             && render(dir, "frosted-dark", MSBDDockLookFrosted, 1, 900, 90, 64, 8) && render(dir, "default", MSBDDockLookDefault, 0, 900, 90, 64, 8)
             && render(dir, "glass-shelf-small", MSBDDockLookShelf, 0, 600, 70, 46, 7);
    check("every look draws (glass shelf light and dark wallpaper, the side panel, frosted light and dark, a small shelf)", drawn);
    return fails;
}
