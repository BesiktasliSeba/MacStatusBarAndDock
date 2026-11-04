// Mac test of Window Size (common/WindowSize.h, the code StatusBar.x runs: 1.8.0 item 4): the size a new window opens at on every engine. On the
// iPads' real desktops (as the iPad 2 and the M1 opened windows, both orientations) and on the other screens iPadOS 15-18 runs on: Default is the middle
// place exactly as before (the "center" layout, copied below as it was), Small the Window menu's Small, Large 92% x 96% of the desktop; Small and
// Large centred in the desktop, inside it, never smaller than a window may be, Small never bigger than Default and Large never smaller; Stage
// Manager's card of the window (our title bar off) fits its desktop as it is, so the Stage Manager engine ends exactly where the others do; a tall
// Dock, a small desktop and no desktop; the stored text as both sides read it.
// The engine parity of 1.8.0 (KT 3 Nov: a behaviour that differs between engines is a bug): one Default on every engine (Stage Manager's own 60% x 72%
// gone), the Window menu's Large Window Size's Large (it was 86% x 92%), one rule for a window opening over another (MSBDWindowCascadeIn: the
// other engines' steps as they were, copied below, but never past the Dock; Stage Manager's front-window cascade gone) -- the same windows whichever
// engine's frames it is handed (Aerial 5.x's stages, the windows) --, and No Fit's free window (copied as it was). Run by test-windowsize.sh.
#import <Foundation/Foundation.h>
#include "../common/WindowSize.h"
#include "../statusbar/SMFit.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)
static BOOL near(CGFloat a, CGFloat b) { return fabs(a - b) < 0.01; }
static BOOL same(CGRect a, CGRect b) { return near(a.origin.x, b.origin.x) && near(a.origin.y, b.origin.y) && near(a.size.width, b.size.width) && near(a.size.height, b.size.height); }
static BOOL inside(CGRect r, CGRect a) { return r.origin.x >= a.origin.x - 0.01 && r.origin.y >= a.origin.y - 0.01 && CGRectGetMaxX(r) <= CGRectGetMaxX(a) + 0.01 && CGRectGetMaxY(r) <= CGRectGetMaxY(a) + 0.01; }
static BOOL integral(CGRect r) { return r.origin.x == round(r.origin.x) && r.origin.y == round(r.origin.y) && r.size.width == round(r.size.width) && r.size.height == round(r.size.height); }
static const char *S(CGRect r) { static char b[8][96]; static int i = 0; i = (i + 1) % 8; snprintf(b[i], 96, "{%.2f, %.2f, %.2f, %.2f}", r.origin.x, r.origin.y, r.size.width, r.size.height); return b[i]; }

// The middle place as StatusBar.x's DMLayoutFrameInArea cut it before 1.8.0 (copied: Default must stay exactly this), and the Window menu's Small.
static CGRect oldCenter(CGRect u, CGSize screen, CGFloat top) { return CGRectMake(round(screen.width * 0.11), top, round(screen.width * 0.78), fmin(round(screen.height * 0.80), CGRectGetMaxY(u) - top)); }
static CGRect oldSmall(CGRect u) { CGFloat w = round(u.size.width * 0.50), h = round(u.size.height * 0.58); return CGRectMake(round(u.origin.x + (u.size.width - w) / 2.0), round(u.origin.y + (u.size.height - h) / 2.0), w, h); }
// Stage Manager's card area (StatusBar.x DMSMCardDesk, copied): the desktop under our 24 pt title bar.
static CGRect cardDesk(CGRect u) { return CGRectMake(u.origin.x, u.origin.y + 24.0, u.size.width, u.size.height - 24.0); }
// The Window menu's Large before 1.8.0 (DMLayoutFrameInArea "large", copied): 86% x 92% of the desktop.
static CGRect oldMenuLarge(CGRect u) { CGFloat w = round(u.size.width * 0.86), h = round(u.size.height * 0.92); return CGRectMake(round(u.origin.x + (u.size.width - w) / 2.0), round(u.origin.y + (u.size.height - h) / 2.0), w, h); }
// Stage Manager's default window before 1.8.0 (DMSMJoinAttributes, copied): its card 60% x 72% of the screen around (50%, 48%).
static CGRect oldSMDefaultCard(CGSize s) { return CGRectMake(0.5 * s.width - 0.3 * s.width, 0.48 * s.height - 0.36 * s.height, 0.6 * s.width, 0.72 * s.height); }
// The other engines' cascade before 1.8.0 (DMCascadeStage, copied as it was): over another window by more than 45%, steps of 50 / 44 pt, down and
// right then up and left, the top-left corner 34 pt clear of every other window's; the bottom could reach `slack` (30) pt past the desktop. own:
// 1.7.5 item 13.
static CGRect oldCascade(CGRect base, const CGRect *o, int n, CGRect usable, int own, double slack) {
    int overlaps = 0;
    for (int i = 0; i < n; i++) if (MSBDWindowOverlap(base, o[i]) > 0.45) overlaps = 1;
    if (!overlaps) return base;
    if (own) { int on = 0; for (int i = 0; i < n; i++) if (fabs(o[i].origin.x - base.origin.x) < 34.0 && fabs(o[i].origin.y - base.origin.y) < 34.0) on = 1; if (!on) return base; }
    for (int k = 1; k <= 8; k++) for (int sign = 1; sign >= -1; sign -= 2) {
        CGRect f = CGRectOffset(base, sign * k * 50.0, sign * k * 44.0);
        f.origin.x = fmax(usable.origin.x, fmin(f.origin.x, CGRectGetMaxX(usable) - f.size.width));
        f.origin.y = fmax(usable.origin.y, fmin(f.origin.y, CGRectGetMaxY(usable) + slack - f.size.height));
        int clear = 1;
        for (int i = 0; i < n; i++) if (fabs(o[i].origin.x - f.origin.x) < 34.0 && fabs(o[i].origin.y - f.origin.y) < 34.0) clear = 0;
        if (clear) return f;
    }
    return base;
}
// No Fit's free window before 1.8.0 (DMNoFitFrame at Default, copied): the middle place no bigger than the desktop less 48 pt, centred in it.
static CGRect oldNoFit(CGRect c, CGRect usable) { CGFloat w = fmin(c.size.width, usable.size.width - 48.0), h = fmin(c.size.height, usable.size.height - 48.0); return CGRectIntegral(CGRectMake(CGRectGetMidX(usable) - w / 2.0, CGRectGetMidY(usable) - h / 2.0, w, h)); }
// Aerial 5.x's stage around a window (its margins: 13 top, 6 at the sides, 12 under it on the M1) and back.
static CGRect grow(CGRect w) { return CGRectMake(w.origin.x - 6, w.origin.y - 13, w.size.width + 12, w.size.height + 25); }
static CGRect shrink(CGRect st) { return CGRectMake(st.origin.x + 6, st.origin.y + 13, st.size.width - 12, st.size.height - 25); }

typedef struct { const char *name; CGSize screen; double bar; double dockTopLand, dockTopPort; } Pad;   // (dockTop: the Dock's top as DMUsableArea uses it)

int main(void) {
    @autoreleasepool {
        CGSize least = MSBDWindowMinSize();
        // ---- the stored text, as SpringBoard (DMLoadPrefs) and Settings (MSBRootListController.m) read it ----
        CHECK(MSBDWindowSizeFromName("small") == MSBDWindowSizeSmall && MSBDWindowSizeFromName("large") == MSBDWindowSizeLarge, "small / large");
        CHECK(MSBDWindowSizeFromName("default") == MSBDWindowSizeDefault && MSBDWindowSizeFromName("") == MSBDWindowSizeDefault && MSBDWindowSizeFromName(NULL) == MSBDWindowSizeDefault
              && MSBDWindowSizeFromName("Small") == MSBDWindowSizeDefault && MSBDWindowSizeFromName("smallish") == MSBDWindowSizeDefault, "anything else is Default (\"default\", none, another case or word)");
        CHECK(!strcmp(MSBDWindowSizeName(MSBDWindowSizeSmall), "small") && !strcmp(MSBDWindowSizeName(MSBDWindowSizeLarge), "large") && !strcmp(MSBDWindowSizeName(MSBDWindowSizeDefault), "default")
              && !strcmp(MSBDWindowSizeName(7), "default"), "the names written and logged");
        CFNumberRef one = (__bridge CFNumberRef)@1;
        CHECK(MSBDWindowSizeFromStored(CFSTR("small")) == MSBDWindowSizeSmall && MSBDWindowSizeFromStored(CFSTR("large")) == MSBDWindowSizeLarge, "stored: the strings");
        CHECK(MSBDWindowSizeFromStored(NULL) == MSBDWindowSizeDefault && MSBDWindowSizeFromStored(kCFBooleanFalse) == MSBDWindowSizeDefault && MSBDWindowSizeFromStored(one) == MSBDWindowSizeDefault
              && MSBDWindowSizeFromStored(CFSTR("default")) == MSBDWindowSizeDefault, "stored: never set, the crash guard's false, a number, \"default\": Default");
        CHECK(MSBDWindowSizeFromStored(CFSTR("smallsmallsmallsmallsmallsmall")) == MSBDWindowSizeDefault && MSBDWindowSizeFromStored(CFSTR("larg")) == MSBDWindowSizeDefault,
              "stored: a text too long for the reader, or a near miss: Default");
        CHECK(!strcmp(kMSBDWindowSizeKey, "windowSize"), "the key: windowSize");
        CHECK(near(kMSBDWindowSmallW, 0.50) && near(kMSBDWindowSmallH, 0.58) && near(kMSBDWindowLargeW, 0.92) && near(kMSBDWindowLargeH, 0.96), "the shares: Small 50%% x 58%%, Large 92%% x 96%%");

        // ---- the iPads: the two we run (desktops measured live, 1.8.0~w01: DMUsableArea's Dock top, the bar), and the other iPadOS 15-18 screens ----
        const Pad pads[] = {
            { "iPad 2 (9.7\", 16.7.7)", {1024, 768}, 20, 699.07, 970.75 },
            { "M1 (11\", 15.6.1, Medium bar)", {1194, 834}, 30, 763.82, 1142.37 },
            { "17.5 (12.9\" 2nd gen)", {1366, 1024}, 20, 902.00, 1244.00 },
            { "A12Z (12.9\" 4th gen)", {1366, 1024}, 24, 940.00, 1290.00 },
            { "iPad mini 6", {1133, 744}, 24, 660.00, 1060.00 },
            { "iPad Air 4/5, iPad 10", {1180, 820}, 24, 736.00, 1106.00 },
            { "iPad 7-9 (10.2\")", {1080, 810}, 20, 726.00, 1090.00 },
            { "iPad Pro 13\" (M4)", {1376, 1032}, 24, 948.00, 1300.00 },
        };
        for (size_t p = 0; p < sizeof(pads) / sizeof(pads[0]); p++) {
            for (int o = 0; o < 2; o++) {
                const Pad *pd = &pads[p];
                CGSize s = o ? CGSizeMake(pd->screen.height, pd->screen.width) : pd->screen;
                double dockTop = o ? pd->dockTopPort : pd->dockTopLand, top = pd->bar + 12.0;
                CGRect u = CGRectMake(0, pd->bar, s.width, dockTop - 2.0 - pd->bar);   // (DMUsableArea: under the bar, 2 pt above the Dock, the screen's width)
                const char *shape = o ? "portrait" : "landscape";
                CGRect d = MSBDWindowSizeFrameIn(MSBDWindowSizeDefault, u, s, top, least), sm = MSBDWindowSizeFrameIn(MSBDWindowSizeSmall, u, s, top, least), lg = MSBDWindowSizeFrameIn(MSBDWindowSizeLarge, u, s, top, least);
                printf("  %-26s %-9s desktop %s: Small %s  Default %s  Large %s\n", pd->name, shape, S(u), S(sm), S(d), S(lg));
                CHECK(same(d, oldCenter(u, s, top)) && same(MSBDWindowCenterIn(u, s, top), oldCenter(u, s, top)), "%s %s: Default is the middle place as before (%s, was %s)", pd->name, shape, S(d), S(oldCenter(u, s, top)));
                CHECK(same(sm, oldSmall(u)) && same(MSBDWindowShareIn(u, kMSBDWindowSmallW, kMSBDWindowSmallH), oldSmall(u)), "%s %s: Small is the Window menu's Small (%s)", pd->name, shape, S(sm));
                CHECK(same(lg, MSBDWindowShareIn(u, kMSBDWindowLargeW, kMSBDWindowLargeH)), "%s %s: Large is 92%% x 96%% of the desktop (%s)", pd->name, shape, S(lg));
                for (int k = 0; k < 3; k++) {
                    CGRect f = k == 0 ? sm : (k == 1 ? d : lg);
                    CHECK(inside(f, u) && integral(f) && f.size.width >= least.width && f.size.height >= least.height, "%s %s, size %d: inside the desktop, whole points, at least 320 x 324 (%s)", pd->name, shape, k, S(f));
                }
                CHECK(fabs(CGRectGetMidX(sm) - CGRectGetMidX(u)) <= 1.0 && fabs(CGRectGetMidY(sm) - CGRectGetMidY(u)) <= 1.0 && fabs(CGRectGetMidX(lg) - CGRectGetMidX(u)) <= 1.0
                      && fabs(CGRectGetMidY(lg) - CGRectGetMidY(u)) <= 1.0, "%s %s: Small and Large centred in the desktop", pd->name, shape);
                CHECK(fabs(CGRectGetMidX(d) - s.width / 2.0) <= 1.0 && near(d.origin.y, top), "%s %s: Default centred on the screen, 12 pt under the bar", pd->name, shape);
                // a size you can tell apart: Small at most ~2/3 of Default's width and height, Large at least 1.15 x its width and never shorter
                CHECK(sm.size.width <= d.size.width * 0.70 && sm.size.height <= d.size.height * 0.75, "%s %s: Small clearly smaller (%.0f x %.0f of %.0f x %.0f)", pd->name, shape, sm.size.width, sm.size.height, d.size.width, d.size.height);
                CHECK(lg.size.width >= d.size.width * 1.15 && lg.size.height >= d.size.height + 1.0, "%s %s: Large clearly larger (%.0f x %.0f of %.0f x %.0f)", pd->name, shape, lg.size.width, lg.size.height, d.size.width, d.size.height);
                // Stage Manager (DMSMJoinAttributes): the card of the window -- our title bar off -- fits the card area as it is, so the window it gives is
                // the engines' window exactly; Default too (1.8.0: DMSMNewWindowFrameIn at every choice, its minimum 320 x 324 there)
                for (int k = 0; k < 3; k++) {
                    CGRect f = k == 0 ? sm : (k == 1 ? d : lg), card = MSBDWindowCardOf(f, 24.0);
                    CGSize pts = card.size; CGPoint cp = CGPointMake(CGRectGetMidX(card), CGRectGetMidY(card));
                    int moved = DMSMFitInDesk(&pts, &cp, cardDesk(u));
                    CGRect back = CGRectMake(cp.x - pts.width / 2.0, cp.y - pts.height / 2.0 - 24.0, pts.width, pts.height + 24.0);
                    CHECK(!moved && same(back, f) && same(MSBDWindowOfCard(CGPointMake(CGRectGetMidX(card), CGRectGetMidY(card)), card.size, 24.0), f),
                          "%s %s, %s on Stage Manager: its card %s fits as it is, the window %s", pd->name, shape, k == 0 ? "Small" : (k == 1 ? "Default" : "Large"), S(card), S(back));
                }
                // One Default on every engine (1.8.0): Stage Manager's is the engines' middle place, no longer 60% x 72% of the screen
                CGRect smDefault = MSBDWindowSizeFrameIn(MSBDWindowSizeDefault, u, s, top, CGSizeMake(fmax(320.0, kMSBDWindowMinWidth), kMSBDWindowMinAppHeight + 24.0));
                CGRect oldSM = oldSMDefaultCard(s);
                CHECK(same(smDefault, d) && !same(MSBDWindowCardOf(smDefault, 24.0), oldSM) && MSBDWindowCardOf(smDefault, 24.0).size.width > oldSM.size.width + 50.0,
                      "%s %s: Stage Manager's Default %s is the engines' (%s), not its old card %s", pd->name, shape, S(smDefault), S(d), S(oldSM));
                // The Window menu's Small and Large are Window Size's (one definition): each engine's layout path -- the shape, then its minimum -- gives the
                // very window Window Size opens; its Large is no longer 86% x 92%
                CGRect menuSmall = MSBDWindowMinSlotOf(MSBDWindowSizeShapeIn(MSBDWindowSizeSmall, u, s, top), MSBDWindowKeepForLayout("small"), u, least);
                CGRect menuLarge = MSBDWindowMinSlotOf(MSBDWindowSizeShapeIn(MSBDWindowSizeLarge, u, s, top), MSBDWindowKeepForLayout("large"), u, least);
                CHECK(same(menuSmall, sm) && same(menuSmall, oldSmall(u)), "%s %s: the Window menu's Small is Window Size's Small, as it was (%s)", pd->name, shape, S(menuSmall));
                CHECK(same(menuLarge, lg) && !same(menuLarge, oldMenuLarge(u)) && menuLarge.size.width > oldMenuLarge(u).size.width, "%s %s: the Window menu's Large is Window Size's Large %s (was %s)", pd->name, shape, S(menuLarge), S(oldMenuLarge(u)));
                CHECK(same(MSBDWindowSizeShapeIn(MSBDWindowSizeDefault, u, s, top), d), "%s %s: the shape at Default is the middle place", pd->name, shape);
                // No Fit's free window at Default: the rule as it was (DMNoFitFrame), Stage Manager's too -- it was the middle place itself
                CGRect nf = MSBDWindowNoFitIn(d, u);
                CHECK(same(nf, oldNoFit(d, u)) && inside(nf, u) && fabs(CGRectGetMidY(nf) - CGRectGetMidY(u)) <= 1.0 && !same(nf, d), "%s %s: No Fit's window %s centred, as before (the middle place %s)", pd->name, shape, S(nf), S(d));
                // The cascade on this desktop, every engine: windows opened one after another at Default each go where the rule puts them -- the second 50 / 44 pt
                // down and right, the third up and left (to the top), the rest further out -- inside the desktop, at the old rule's places wherever those were
                // inside it too, never two corners together
                {
                    CGRect open[8]; int n = 0;
                    open[n++] = d;
                    for (int w = 1; w < 8; w++) {
                        int how = 0;
                        CGRect f = MSBDWindowCascadeIn(d, open, n, u, 0, &how), old = oldCascade(d, open, n, u, 0, 30.0);
                        CHECK(inside(f, u), "%s %s: window %d %s inside the desktop", pd->name, shape, w + 1, S(f));
                        CHECK(same(f, oldCascade(d, open, n, u, 0, 0.0)), "%s %s: window %d where the old rule put it with the desktop's bottom as its limit (%s)", pd->name, shape, w + 1, S(f));
                        if (w <= 2 && inside(old, u)) CHECK(same(f, old), "%s %s: window %d where the old rule put it (%s, was %s)", pd->name, shape, w + 1, S(f), S(old));
                        // (the second 50 / 44 pt on -- lifted where that would reach under the Dock: the small iPads' landscape desktops, where the old rule's
                        //  second window reached 17 pt under it)
                        if (w == 1) CHECK(how == 1 && near(f.origin.x, d.origin.x + 50) && near(f.origin.y, fmin(d.origin.y + 44, CGRectGetMaxY(u) - d.size.height)), "%s %s: the second window 50 / 44 pt on (%s)", pd->name, shape, S(f));
                        if (w == 2) CHECK(how == -1 && near(f.origin.x, d.origin.x - 50) && near(f.origin.y, u.origin.y), "%s %s: the third up and left, at the top (%s)", pd->name, shape, S(f));
                        BOOL clear = how != MSBDCascadeNoRoom ? !MSBDWindowCornerTaken(f, open, n) : YES;
                        CHECK(clear, "%s %s: window %d's corner clear of the others", pd->name, shape, w + 1);
                        open[n++] = f;
                    }
                }
            }
        }
        // the iPad 2 in points, as its Stage Manager engine opened them (1.8.0~w01, 3 Nov: the Dock's top 699.07 in landscape, 970.75 in portrait)
        {
            CGRect uL = CGRectMake(0, 20, 1024, 677.07), uP = CGRectMake(0, 20, 768, 948.75);
            CHECK(same(MSBDWindowSizeFrameIn(MSBDWindowSizeSmall, uL, CGSizeMake(1024, 768), 32, least), CGRectMake(256, 162, 512, 393)), "iPad 2 landscape Small {256, 162, 512, 393}");
            CHECK(same(MSBDWindowSizeFrameIn(MSBDWindowSizeDefault, uL, CGSizeMake(1024, 768), 32, least), CGRectMake(113, 32, 799, 614)), "iPad 2 landscape Default {113, 32, 799, 614}");
            CHECK(same(MSBDWindowSizeFrameIn(MSBDWindowSizeLarge, uL, CGSizeMake(1024, 768), 32, least), CGRectMake(41, 34, 942, 650)), "iPad 2 landscape Large {41, 34, 942, 650}");
            CHECK(same(MSBDWindowSizeFrameIn(MSBDWindowSizeSmall, uP, CGSizeMake(768, 1024), 32, least), CGRectMake(192, 219, 384, 550)), "iPad 2 portrait Small {192, 219, 384, 550}");
            CHECK(same(MSBDWindowSizeFrameIn(MSBDWindowSizeDefault, uP, CGSizeMake(768, 1024), 32, least), CGRectMake(84, 32, 599, 819)), "iPad 2 portrait Default {84, 32, 599, 819}");
            CHECK(same(MSBDWindowSizeFrameIn(MSBDWindowSizeLarge, uP, CGSizeMake(768, 1024), 32, least), CGRectMake(31, 39, 707, 911)), "iPad 2 portrait Large {31, 39, 707, 911}");
        }
        // the M1 in points, as Aerial 5.1 opened them (1.8.0~w02, 3 Nov: Menu Bar Size Medium's 30 pt bar, the Dock's top 763.82 / 1142.37; Aerial's stage
        // is the window grown by its margins, 13 / 6 / 12 / 6 there)
        {
            CGRect uL = CGRectMake(0, 30, 1194, 731.82), uP = CGRectMake(0, 30, 834, 1110.37);
            CGSize sL = {1194, 834}, sP = {834, 1194};
            CHECK(same(MSBDWindowSizeFrameIn(MSBDWindowSizeSmall, uL, sL, 42, least), CGRectMake(299, 184, 597, 424)), "M1 landscape Small {299, 184, 597, 424}");
            CHECK(same(MSBDWindowSizeFrameIn(MSBDWindowSizeDefault, uL, sL, 42, least), CGRectMake(131, 42, 931, 667)), "M1 landscape Default {131, 42, 931, 667}");
            CHECK(same(MSBDWindowSizeFrameIn(MSBDWindowSizeLarge, uL, sL, 42, least), CGRectMake(48, 44, 1098, 703)), "M1 landscape Large {48, 44, 1098, 703}");
            CHECK(same(MSBDWindowSizeFrameIn(MSBDWindowSizeSmall, uP, sP, 42, least), CGRectMake(209, 263, 417, 644)), "M1 portrait Small {209, 263, 417, 644}");
            CHECK(same(MSBDWindowSizeFrameIn(MSBDWindowSizeDefault, uP, sP, 42, least), CGRectMake(92, 42, 651, 955)), "M1 portrait Default {92, 42, 651, 955}");
            CHECK(same(MSBDWindowSizeFrameIn(MSBDWindowSizeLarge, uP, sP, 42, least), CGRectMake(34, 52, 767, 1066)), "M1 portrait Large {34, 52, 767, 1066}");
        }

        // ---- the cascade rule itself (MSBDWindowCascadeIn: DMCascadeStage on Aerial, Zetsu, MilkyWay4; DMSMJoinAttributes on Stage Manager) ----
        {
            CGRect u = CGRectMake(0, 24, 1024, 673.07);   // (the iPad 2's landscape desktop)
            CGRect a = CGRectMake(113, 36, 799, 614);
            int how = -7;
            CGRect none[1] = { CGRectMake(920, 30, 100, 100) };
            CHECK(same(MSBDWindowCascadeIn(a, none, 1, u, 0, &how), a) && how == MSBDCascadeStays, "a window over no other one by more than 45%% stays (how %d)", how);
            CHECK(same(MSBDWindowCascadeIn(a, NULL, 0, u, 0, &how), a) && how == MSBDCascadeStays && CGRectIsNull(MSBDWindowCascadeIn(CGRectNull, none, 1, u, 0, &how)), "no other window, or no window: as it is");
            // the 45% line: of the SMALLER window (a small window inside a big one is covered entirely)
            CGRect big = CGRectMake(0, 24, 1024, 673), small = CGRectMake(300, 200, 300, 200);
            CHECK(near(MSBDWindowOverlap(small, big), 1.0) && near(MSBDWindowOverlap(big, small), 1.0) && near(MSBDWindowOverlap(a, CGRectMake(2000, 0, 10, 10)), 0.0), "the overlap: the share of the smaller window");
            CGRect left40[1] = { CGRectMake(a.origin.x + a.size.width * 0.60, a.origin.y, a.size.width, a.size.height) };   // (40% of it covered)
            CGRect left50[1] = { CGRectMake(a.origin.x + a.size.width * 0.50 - 1, a.origin.y + 200, a.size.width, a.size.height) };
            CHECK(same(MSBDWindowCascadeIn(a, left40, 1, u, 0, &how), a) && how == MSBDCascadeStays, "40%% covered: stays (%.2f)", MSBDWindowOverlap(a, left40[0]));
            CGRect m50 = MSBDWindowCascadeIn(CGRectMake(113, 36, 400, 300), (CGRect[]){ CGRectMake(113 + 150, 36 + 10, 400, 300) }, 1, u, 0, &how);
            CHECK(how == 1 && same(m50, CGRectMake(163, 80, 400, 300)), "over half of it covered: moved one step (how %d, %s)", how, S(m50));
            (void)left50;
            // own place (1.7.5 item 13): over another window it stays, unless its corner sits on the other's
            CGRect over[1] = { CGRectMake(300, 120, 600, 500) };
            CHECK(same(MSBDWindowCascadeIn(a, over, 1, u, 1, &how), a) && how == MSBDCascadeOwnKept, "own place over another window: kept (how %d)", how);
            CGRect onIt[1] = { CGRectMake(a.origin.x + 5, a.origin.y + 5, 700, 500) };
            CGRect f = MSBDWindowCascadeIn(a, onIt, 1, u, 1, &how);
            CHECK(how == 1 && same(f, CGRectOffset(a, 50, 44)), "own place on another window's corner: moved on (how %d, %s)", how, S(f));
            CHECK(same(MSBDWindowCascadeIn(a, onIt, 1, u, 1, &how), oldCascade(a, onIt, 1, u, 1, 30.0)) && same(MSBDWindowCascadeIn(a, over, 1, u, 1, &how), oldCascade(a, over, 1, u, 1, 30.0)), "own place: as the old rule");
            // a step that would reach under the Dock is lifted to the desktop's bottom (the old rule let it 30 pt past); one past the right edge pulled back
            CGRect lows3[3] = { a, CGRectMake(163, 80, 799, 614), CGRectMake(63, 24, 799, 614) };   // (the first three, as they open)
            CGRect g = MSBDWindowCascadeIn(a, lows3, 3, u, 0, &how), og = oldCascade(a, lows3, 3, u, 0, 30.0);
            CHECK(how == 2 && inside(g, u) && near(CGRectGetMaxY(g), CGRectGetMaxY(u)) && near(g.origin.x, 213) && CGRectGetMaxY(og) > CGRectGetMaxY(u) + 1.0,
                  "the fourth window two steps down: at the desktop's bottom %s (the old rule %s, under the Dock)", S(g), S(og));
            CGRect rightEdge = CGRectMake(600, 36, 400, 300);
            f = MSBDWindowCascadeIn(rightEdge, (CGRect[]){ rightEdge }, 1, u, 0, &how);
            CHECK(how == 1 && near(CGRectGetMaxX(f), CGRectGetMaxX(u)) && near(f.origin.y, 80), "a step past the right edge: pulled back to it (%s)", S(f));
            // a window wider than the desktop keeps its left edge on the screen
            CGRect wide = CGRectMake(0, 24, 1100, 400);
            f = MSBDWindowCascadeIn(wide, (CGRect[]){ wide }, 1, u, 0, &how);
            CHECK(near(f.origin.x, 0) && f.origin.y > wide.origin.y, "wider than the desktop: its left edge stays on the screen (%s)", S(f));
            // no clear place: where it opened (a crowd of windows on every step's corner)
            CGRect crowd[17]; int n = 0; crowd[n++] = a;
            for (int k = 1; k <= 8; k++) for (int sign = 1; sign >= -1; sign -= 2) {
                CGRect t = CGRectOffset(a, sign * k * 50.0, sign * k * 44.0);
                t.origin.x = fmax(u.origin.x, fmin(t.origin.x, CGRectGetMaxX(u) - t.size.width)); t.origin.y = fmax(u.origin.y, fmin(t.origin.y, CGRectGetMaxY(u) - t.size.height));
                if (n < 17) crowd[n++] = t;
            }
            CHECK(same(MSBDWindowCascadeIn(a, crowd, n, u, 0, &how), a) && how == MSBDCascadeNoRoom, "every place taken: where it opened (how %d)", how);
            // the same windows whichever engine's frames it is handed: Aerial 5.x's stages (the windows grown by Aerial's margins) in the stage desktop
            // give the windows Zetsu's, MilkyWay4's and Stage Manager's frames give -- a random sweep of desktops of up to eight windows
            srand48(18003);
            int sweeps = 0, moved = 0;
            for (int t = 0; t < 4000; t++) {
                CGRect du = CGRectMake(0, 24 + 6 * (t % 2), 768 + drand48() * 600, 600 + drand48() * 500);
                int k = 1 + (int)(drand48() * 7);
                CGRect ws[8], st[8];
                for (int i = 0; i < k; i++) {
                    CGFloat w = 320 + drand48() * (du.size.width - 320), h = 324 + drand48() * (du.size.height - 324);
                    ws[i] = CGRectIntegral(CGRectMake(du.origin.x + drand48() * (du.size.width - w), du.origin.y + drand48() * (du.size.height - h), w, h));
                    if (drand48() < 0.3 && i) ws[i].origin = CGPointMake(ws[i - 1].origin.x + 10 * drand48(), ws[i - 1].origin.y + 10 * drand48());   // (some on another's corner)
                    st[i] = grow(ws[i]);
                }
                CGRect nw = MSBDWindowSizeFrameIn(MSBDWindowSizeDefault, du, CGSizeMake(du.size.width, du.size.height + 120), du.origin.y + 12, least);
                if (CGRectIsNull(nw) || !inside(nw, du)) continue;
                int own = (int)(drand48() * 2), h1 = 0, h2 = 0;
                CGRect byWindow = MSBDWindowCascadeIn(nw, ws, k, du, own, &h1), byStage = shrink(MSBDWindowCascadeIn(grow(nw), st, k, grow(du), own, &h2));
                sweeps++; if (h1 != MSBDCascadeStays && h1 != MSBDCascadeOwnKept) moved++;
                if (!same(byWindow, byStage) || h1 != h2 || !inside(byWindow, du)) { CHECK(0, "sweep %d: by the windows %s (how %d), by Aerial's stages %s (how %d), desktop %s", t, S(byWindow), h1, S(byStage), h2, S(du)); break; }
            }
            CHECK(sweeps > 3000 && moved > 500, "sweep: %d desktops, %d new windows moved on -- the same place by any engine's frames, inside the desktop", sweeps, moved);
        }
        // ---- a tall Dock (the iPad 2 in landscape with a 130 pt Dock): Default reaches the desktop's bottom, so Large gets Default's height ----
        {
            CGSize s = {1024, 768}; CGRect u = CGRectMake(0, 20, 1024, 768 - 130 - 2 - 20);
            CGRect d = MSBDWindowSizeFrameIn(MSBDWindowSizeDefault, u, s, 32, least), lg = MSBDWindowSizeFrameIn(MSBDWindowSizeLarge, u, s, 32, least);
            CHECK(near(d.size.height, CGRectGetMaxY(u) - 32) && near(lg.size.height, d.size.height) && lg.size.width > d.size.width && inside(lg, u)
                  && fabs(CGRectGetMidY(lg) - CGRectGetMidY(u)) <= 1.0, "a tall Dock: Large %s keeps Default's height (%s), centred in %s", S(lg), S(d), S(u));
        }
        // ---- a desktop narrower than the screen (none on our iPads, the rule's own guard): Large never narrower than Default, Small never wider ----
        {
            CGSize s = {1024, 768}; CGRect u = CGRectMake(112, 20, 800, 677);   // (Large's 92% would be 736, Default 799 wide)
            CGRect d = MSBDWindowSizeFrameIn(MSBDWindowSizeDefault, u, s, 32, least), lg = MSBDWindowSizeFrameIn(MSBDWindowSizeLarge, u, s, 32, least);
            CGRect nu = CGRectMake(312, 20, 400, 677), ns = MSBDWindowSizeFrameIn(MSBDWindowSizeSmall, nu, s, 32, least), nd = MSBDWindowCenterIn(nu, s, 32);   // (Default wider than this desktop)
            CHECK(near(lg.size.width, d.size.width) && inside(lg, u) && fabs(CGRectGetMidX(lg) - CGRectGetMidX(u)) <= 1.0, "a narrow desktop: Large %s as wide as Default %s, centred", S(lg), S(d));
            CHECK(ns.size.width <= nd.size.width && inside(ns, nu) && near(ns.size.width, 320), "a narrower one: Small %s inside it, no wider than Default", S(ns));
            CGSize wide = {1024, 768}; CGRect w2 = CGRectMake(0, 20, 1024, 677);
            CGRect sm2 = MSBDWindowSizeShapeIn(MSBDWindowSizeSmall, CGRectMake(0, 20, 1024, 677), CGSizeMake(600, 768), 32);   // (Default 78% of a 600 pt screen: 468)
            CHECK(near(sm2.size.width, 468) && inside(sm2, w2), "a screen narrower than its desktop: Small %s held to Default's width", S(sm2));
            (void)wide;
        }
        // ---- a small desktop (a screen smaller than any iPad's): Small grows to the smallest window around its middle; one smaller than that: all of it ----
        {
            CGSize s = {600, 500}; CGRect u = CGRectMake(0, 24, 600, 420);
            CGRect sm = MSBDWindowSizeFrameIn(MSBDWindowSizeSmall, u, s, 36, least);
            CHECK(near(sm.size.width, 320) && near(sm.size.height, 324) && inside(sm, u) && fabs(CGRectGetMidX(sm) - CGRectGetMidX(u)) <= 0.5, "a small desktop: Small at the smallest window, around its middle (%s)", S(sm));
            CGRect tiny = CGRectMake(0, 24, 300, 280);
            CGRect lt = MSBDWindowSizeFrameIn(MSBDWindowSizeLarge, tiny, CGSizeMake(300, 330), 36, least), st = MSBDWindowSizeFrameIn(MSBDWindowSizeSmall, tiny, CGSizeMake(300, 330), 36, least);
            CHECK(same(lt, tiny) && same(st, tiny), "a desktop smaller than a window may be: all of it (%s, %s)", S(lt), S(st));
            CGSize wide = {414, 324};   // (a wider minimum of Stage Manager's: Small grows to it)
            CHECK(near(MSBDWindowSizeFrameIn(MSBDWindowSizeSmall, u, s, 36, wide).size.width, 414), "Stage Manager's own wider minimum is kept");
        }
        // ---- no desktop ----
        CHECK(CGRectIsNull(MSBDWindowSizeFrameIn(MSBDWindowSizeSmall, CGRectNull, CGSizeMake(1024, 768), 32, least)) && CGRectIsNull(MSBDWindowSizeFrameIn(MSBDWindowSizeLarge, CGRectZero, CGSizeMake(1024, 768), 32, least))
              && CGRectIsNull(MSBDWindowSizeFrameIn(MSBDWindowSizeDefault, CGRectMake(0, 20, 1024, 600), CGSizeZero, 32, least)) && CGRectIsNull(MSBDWindowSizeFrameIn(MSBDWindowSizeSmall, CGRectMake(0, 20, 1024, 600), CGSizeMake(1024, 768), NAN, least)),
              "no desktop, no screen or no top: CGRectNull (the callers keep what they had)");
        CHECK(CGRectIsNull(MSBDWindowCardOf(CGRectNull, 24)) && same(MSBDWindowCardOf(CGRectMake(10, 30, 500, 400), 24), CGRectMake(10, 54, 500, 376)), "the card: the window under our 24 pt title bar");
        // ---- a TV (Stage Manager's stage on an external display, 1920 x 1080: its own 24 pt bar, a Dock of 20%, the middle place's top at 36) ----
        {
            CGSize s = {1920, 1080}; CGRect u = CGRectMake(0, 24, 1920, 1080 - 216 - 2 - 24);
            CGRect d = MSBDWindowSizeFrameIn(MSBDWindowSizeDefault, u, s, 36, least), sm = MSBDWindowSizeFrameIn(MSBDWindowSizeSmall, u, s, 36, least), lg = MSBDWindowSizeFrameIn(MSBDWindowSizeLarge, u, s, 36, least);
            CHECK(inside(sm, u) && inside(lg, u) && sm.size.width < d.size.width && lg.size.width > d.size.width && same(d, oldCenter(u, s, 36)), "a TV: %s %s %s", S(sm), S(d), S(lg));
        }
        printf("test-windowsize: %d/%d passed\n", passes, passes + fails);
    }
    return fails ? 1 : 0;
}
