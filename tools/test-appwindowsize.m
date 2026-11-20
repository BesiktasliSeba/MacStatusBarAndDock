// Mac test of App Window Sizes (1.8.8, KT 12 Nov: a launch size per app; common/AppWindowSize.h, the code SpringBoard and Settings run): the read
// rule (the stored texts and the stored dictionary, 200 entries at most), which size wins (the tables of design 1.1 and 1.3, every input, and
// 1.8.7's answers with no entry), the frames on the 8 iPad desktops of test-windowsize.m in both orientations and on the TV desktops (Small /
// Medium / Large Window Size's own windows, iPhone design 2.1's table as the code computes it), and the change list SpringBoard forgets places
// by (round 4 amendment 1: the first read only sets the baseline). Run by test-appwindowsize.sh, on the header as built and on made-to-fail copies.
#import <Foundation/Foundation.h>
#include "../common/AppWindowSize.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)
static BOOL near(CGFloat a, CGFloat b) { return fabs(a - b) < 0.01; }
static BOOL same(CGRect a, CGRect b) { return near(a.origin.x, b.origin.x) && near(a.origin.y, b.origin.y) && near(a.size.width, b.size.width) && near(a.size.height, b.size.height); }
static BOOL inside(CGRect r, CGRect a) { return r.origin.x >= a.origin.x - 0.01 && r.origin.y >= a.origin.y - 0.01 && CGRectGetMaxX(r) <= CGRectGetMaxX(a) + 0.01 && CGRectGetMaxY(r) <= CGRectGetMaxY(a) + 0.01; }
static BOOL integral(CGRect r) { return r.origin.x == round(r.origin.x) && r.origin.y == round(r.origin.y) && r.size.width == round(r.size.width) && r.size.height == round(r.size.height); }
static const char *S(CGRect r) { static char b[8][96]; static int i = 0; i = (i + 1) % 8; snprintf(b[i], 96, "{%.2f, %.2f, %.2f, %.2f}", r.origin.x, r.origin.y, r.size.width, r.size.height); return b[i]; }

// A read table from a stored value written as Settings writes it (an NSDictionary bridged), through the read rule; readWrong: the type it reported
// for a stored value that is not a dictionary (1.8.8 F3: SpringBoard logs it), else 0 (a value it never wrote stays kNotWritten).
#define kNotWritten ((CFTypeID)987654321)
static CFTypeID readWrong = kNotWritten;
static CFDictionaryRef readOf(id stored, int *bad, int *over) { readWrong = kNotWritten; return MSBDAppSizesRead((__bridge CFTypeRef)stored, bad, over, &readWrong); }
// The change list as an NSArray (and the CF array released).
static NSArray *changed(CFDictionaryRef before, CFDictionaryRef after) { CFArrayRef a = MSBDAppSizesChanged(before, after); NSArray *r = a ? [(__bridge NSArray *)a copy] : nil; if (a) CFRelease(a); return r; }
static NSArray *toForget(bool set, CFDictionaryRef before, CFDictionaryRef after) { CFArrayRef a = MSBDAppSizesToForget(set, before, after); NSArray *r = a ? [(__bridge NSArray *)a copy] : nil; if (a) CFRelease(a); return r; }
static const char *L(NSArray *a) { static char b[4][512]; static int i = 0; i = (i + 1) % 4; snprintf(b[i], 512, "%s", a ? [[a componentsJoinedByString:@","] UTF8String] : "(nil)"); return b[i]; }

// Row A6 / A12b (1.8.8 F2): Fit to Window on and two apps tiled (the tiles as StatusBar.x DMLayoutFrameInArea cuts "left" / "right", 6 pt apart),
// two apps at iPhone opened one after the other, each left out of the tiles and cascaded over them by the engines' one rule (MSBDWindowCascadeIn).
// The second must open one step on from the first, down and right (or level), its corner 34 pt or more away: the first's title bar in sight at its
// left end, where its traffic lights are. Up and left of it, the second's body covers them (the s01 passes, iPad 2: {402, 47} then {302, 20}).
static BOOL twoPhonesOverTiles(CGRect u, CGRect ph, CGRect *first, CGRect *second, int *h1, int *h2) {
    CGFloat halfW = floor((u.size.width - 6.0) / 2.0), rx = u.origin.x + halfW + 6.0;
    CGRect o[3] = { CGRectMake(u.origin.x, u.origin.y, halfW, u.size.height), CGRectMake(rx, u.origin.y, CGRectGetMaxX(u) - rx, u.size.height) };
    *first = MSBDWindowCascadeIn(ph, o, 2, u, 0, h1); o[2] = *first;
    *second = MSBDWindowCascadeIn(ph, o, 3, u, 0, h2);
    double dx = second->origin.x - first->origin.x, dy = second->origin.y - first->origin.y;
    return *h2 > 0 && *h2 <= 8 && inside(*second, u) && dx >= -0.01 && dy >= -0.01 && (dx >= kMSBDCascadeNear - 0.01 || dy >= kMSBDCascadeNear - 0.01);
}

typedef struct { const char *name; CGSize screen; double bar; double dockTopLand, dockTopPort; CGSize phoneLand; } Pad;   // (phoneLand: 2.1's iPhone window in landscape)

int main(void) {
    @autoreleasepool {
        const CGSize least = MSBDWindowMinSize();                      // (Aerial / Zetsu / MilkyWay4: the app 320 x 300 under our 24 pt bar)
        const CGSize smWide = CGSizeMake(414, kMSBDWindowMinAppHeight + 24.0);   // (a wider Stage Manager minimum, as test-windowsize.m's)
        const int apps[6] = { MSBDAppSizeNone, MSBDAppSizeSmall, MSBDAppSizeMedium, MSBDAppSizeLarge, MSBDAppSizeFill, MSBDAppSizeIPhone };
        const char *appName[6] = { "none", "Small", "Medium", "Large", "Fill", "iPhone" };

        // ---- the stored names ----
        CHECK(!strcmp(kMSBDAppWindowSizesKey, "appWindowSizes") && kMSBDAppWindowSizesMax == 200 && near(kMSBDPhoneW, 393) && near(kMSBDPhoneH, 852), "the key, the limit, the phone");
        CHECK(MSBDAppSizeFromName("small") == MSBDAppSizeSmall && MSBDAppSizeFromName("medium") == MSBDAppSizeMedium && MSBDAppSizeFromName("large") == MSBDAppSizeLarge
              && MSBDAppSizeFromName("fill") == MSBDAppSizeFill && MSBDAppSizeFromName("iphone") == MSBDAppSizeIPhone, "the five texts");
        const char *noneTexts[] = { "default", "custom:60x80", "Small", "", "iPhone", "IPHONE", "fill ", " medium", "larg", "phone", "center" };
        for (size_t i = 0; i < sizeof noneTexts / sizeof noneTexts[0]; i++) CHECK(MSBDAppSizeFromName(noneTexts[i]) == MSBDAppSizeNone, "\"%s\" is no entry", noneTexts[i]);
        CHECK(MSBDAppSizeFromName(NULL) == MSBDAppSizeNone, "NULL is no entry");
        CHECK(MSBDAppSizeFromStored(CFSTR("iphone")) == MSBDAppSizeIPhone && MSBDAppSizeFromStored(CFSTR("medium")) == MSBDAppSizeMedium, "stored: a string");
        CHECK(MSBDAppSizeFromStored(NULL) == MSBDAppSizeNone && MSBDAppSizeFromStored((__bridge CFTypeRef)@3) == MSBDAppSizeNone && MSBDAppSizeFromStored(kCFBooleanTrue) == MSBDAppSizeNone
              && MSBDAppSizeFromStored((__bridge CFTypeRef)@{ @"size": @"small" }) == MSBDAppSizeNone && MSBDAppSizeFromStored((__bridge CFTypeRef)@[ @"small" ]) == MSBDAppSizeNone
              && MSBDAppSizeFromStored(CFSTR("smallsmallsmallsmallsmall")) == MSBDAppSizeNone && MSBDAppSizeFromStored(CFSTR("")) == MSBDAppSizeNone,
              "stored: none, a number, a boolean, a dictionary, an array, a long text, an empty one: no entry");
        for (int i = 1; i < 6; i++) {
            const char *n = MSBDAppSizeName(apps[i]);
            CHECK(n && MSBDAppSizeFromName(n) == apps[i], "the name written for %s reads back (%s)", appName[i], n ? n : "NULL");
        }
        CHECK(MSBDAppSizeName(MSBDAppSizeNone) == NULL && MSBDAppSizeName(0) == NULL && MSBDAppSizeName(6) == NULL && MSBDAppSizeName(-7) == NULL, "no entry or anything else: nothing written");

        // ---- the stored dictionary through the read rule ----
        {
            NSString *k255 = [@"" stringByPaddingToLength:255 withString:@"a" startingAtIndex:0], *k256 = [@"" stringByPaddingToLength:256 withString:@"b" startingAtIndex:0];
            NSMutableDictionary *d = [@{ @"com.apple.mobilenotes": @"iphone", @"com.apple.mobilesafari": @"large", @"com.apple.mobiletimer": @"small", @"com.apple.Preferences": @"fill",
                                        @"com.apple.reminders": @"medium",
                                        @"x.default": @"default", @"x.custom": @"custom:60x80", @"x.cap": @"Small", @"x.empty": @"", @"x.number": @7, @"x.dict": @{ @"a": @"small" },
                                        @"x.array": @[ @"small" ], @"x.bool": @YES, @"": @"small" } mutableCopy];
            d[k256] = @"iphone"; d[k255] = @"small"; d[@12] = @"small";
            int bad = -1, over = -1;
            CFDictionaryRef t = readOf(d, &bad, &over);
            CHECK(t && CFDictionaryGetCount(t) == 6 && bad == 11 && over == 0, "the read rule: 6 entries read (%ld), 11 that count as none (%d), none past 200 (%d)", t ? (long)CFDictionaryGetCount(t) : -1L, bad, over);
            CHECK(readWrong == 0, "  ... a dictionary is of the type read: no other type reported (%lu)", (unsigned long)readWrong);
            CHECK(MSBDAppSizeIn(t, CFSTR("com.apple.mobilenotes")) == MSBDAppSizeIPhone && MSBDAppSizeIn(t, CFSTR("com.apple.mobilesafari")) == MSBDAppSizeLarge
                  && MSBDAppSizeIn(t, CFSTR("com.apple.mobiletimer")) == MSBDAppSizeSmall && MSBDAppSizeIn(t, CFSTR("com.apple.Preferences")) == MSBDAppSizeFill
                  && MSBDAppSizeIn(t, CFSTR("com.apple.reminders")) == MSBDAppSizeMedium && MSBDAppSizeIn(t, (__bridge CFStringRef)k255) == MSBDAppSizeSmall, "  ... each app its choice, a 255-character key read");
            CHECK(MSBDAppSizeIn(t, (__bridge CFStringRef)k256) == MSBDAppSizeNone && MSBDAppSizeIn(t, CFSTR("")) == MSBDAppSizeNone && MSBDAppSizeIn(t, CFSTR("x.default")) == MSBDAppSizeNone
                  && MSBDAppSizeIn(t, CFSTR("x.custom")) == MSBDAppSizeNone && MSBDAppSizeIn(t, CFSTR("x.cap")) == MSBDAppSizeNone && MSBDAppSizeIn(t, CFSTR("x.number")) == MSBDAppSizeNone
                  && MSBDAppSizeIn(t, CFSTR("x.dict")) == MSBDAppSizeNone && !CFDictionaryContainsKey(t, (__bridge CFTypeRef)@12) && !CFDictionaryContainsKey(t, CFSTR("x.empty")),
                  "  ... a 256-character key, an empty key, \"default\", \"custom:60x80\", \"Small\", \"\", a number, a dictionary, a number as the key: none");
            CHECK(MSBDAppSizeIn(t, CFSTR("com.apple.mobileslideshow")) == MSBDAppSizeNone && MSBDAppSizeIn(NULL, CFSTR("com.apple.mobilenotes")) == MSBDAppSizeNone
                  && MSBDAppSizeIn(t, NULL) == MSBDAppSizeNone && MSBDAppSizeIn(t, (__bridge CFStringRef)(id)@5) == MSBDAppSizeNone, "  ... an app not listed, no table, no bundle, a bundle that is not a string: none");
            CFRelease(t);
            id notDicts[] = { @"iphone", @[ @{ @"com.apple.mobilenotes": @"iphone" } ], @1, @YES, [NSData data] };
            for (size_t i = 0; i < sizeof notDicts / sizeof notDicts[0]; i++) {
                CFDictionaryRef e = readOf(notDicts[i], &bad, &over);
                CHECK(e && CFDictionaryGetCount(e) == 0 && bad == 0 && over == 0, "a stored value of another type (%s): no app at all", [NSStringFromClass([notDicts[i] class]) UTF8String]);
                CHECK(readWrong == CFGetTypeID((__bridge CFTypeRef)notDicts[i]), "  ... and its type reported for the log (F3, the A12Z's G1: a number left no line): %s",
                      readWrong && readWrong != kNotWritten ? [(__bridge_transfer NSString *)CFCopyTypeIDDescription(readWrong) UTF8String] : "none");
                if (e) CFRelease(e);
            }
            CFDictionaryRef e = MSBDAppSizesRead(NULL, NULL, NULL, NULL);
            CHECK(e && CFDictionaryGetCount(e) == 0, "absent (never set): an empty table, never NULL");
            if (e) CFRelease(e);
            e = readOf(nil, &bad, &over);
            CHECK(e && CFDictionaryGetCount(e) == 0 && bad == 0 && over == 0 && readWrong == 0, "  ... and nothing to log: no bad entry, no other type (%lu)", (unsigned long)readWrong);
            if (e) CFRelease(e);
            e = readOf(@{}, &bad, &over);
            CHECK(e && CFDictionaryGetCount(e) == 0 && bad == 0 && over == 0 && readWrong == 0, "an empty dictionary: an empty table, nothing to log");
            if (e) CFRelease(e);
            // a hand-made table with a choice that is not one (a future build's number): none
            CFMutableDictionaryRef h = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            CFDictionarySetValue(h, CFSTR("a"), (__bridge CFTypeRef)@9); CFDictionarySetValue(h, CFSTR("b"), CFSTR("iphone")); CFDictionarySetValue(h, CFSTR("c"), (__bridge CFTypeRef)@5);
            CHECK(MSBDAppSizeIn(h, CFSTR("a")) == MSBDAppSizeNone && MSBDAppSizeIn(h, CFSTR("b")) == MSBDAppSizeNone && MSBDAppSizeIn(h, CFSTR("c")) == MSBDAppSizeIPhone, "a table entry that is not a choice: none");
            CFRelease(h);
        }
        // 201 entries (Settings stops at 200; a hand-written plist need not): the first 200 by key, the rest logged once; bad entries do not take a place
        {
            NSMutableDictionary *d = [NSMutableDictionary dictionary];
            for (int i = 200; i >= 0; i--) d[[NSString stringWithFormat:@"app.%03d", i]] = (i % 2) ? @"iphone" : @"large";
            int bad = -1, over = -1;
            CFDictionaryRef t = readOf(d, &bad, &over);
            BOOL first200 = CFDictionaryGetCount(t) == 200;
            for (int i = 0; i < 200 && first200; i++) if (MSBDAppSizeIn(t, (__bridge CFStringRef)[NSString stringWithFormat:@"app.%03d", i]) != ((i % 2) ? MSBDAppSizeIPhone : MSBDAppSizeLarge)) first200 = NO;
            CHECK(first200 && MSBDAppSizeIn(t, CFSTR("app.200")) == MSBDAppSizeNone && bad == 0 && over == 1 && readWrong == 0, "201 entries: app.000 to app.199 read, app.200 left (over %d)", over);
            CFRelease(t);
            d[@"aaa.bad"] = @"huge"; d[@"aab.bad"] = @4;
            t = readOf(d, &bad, &over);
            CHECK(CFDictionaryGetCount(t) == 200 && MSBDAppSizeIn(t, CFSTR("app.199")) == MSBDAppSizeIPhone && bad == 2 && over == 1, "  ... two bad entries sorted first take no place (bad %d, over %d)", bad, over);
            CFRelease(t);
            NSMutableDictionary *z = [NSMutableDictionary dictionary];
            for (int i = 0; i < 201; i++) z[[NSString stringWithFormat:@"%c.app%03d", 'z' - (i % 26), i]] = @"small";
            t = readOf(z, &bad, &over);
            NSArray *sortedKeys = [z.allKeys sortedArrayUsingSelector:@selector(compare:)];
            CHECK(CFDictionaryGetCount(t) == 200 && !CFDictionaryContainsKey(t, (__bridge CFStringRef)sortedKeys.lastObject) && CFDictionaryContainsKey(t, (__bridge CFStringRef)sortedKeys.firstObject),
                  "  ... keys in sorted order whatever order they were written in (left: %s)", [sortedKeys.lastObject UTF8String]);
            CFRelease(t);
        }

        // ---- which size wins (1.1): app (none and the five) x Window Size (3) x Open at Fill (2) ----
        {
            // the expected answers written out, row by row: [app][windowSize][fill]
            const int expect[6][3][2] = {
                /* none   */ { { MSBDWindowSizeDefault, kMSBDOpenFill }, { MSBDWindowSizeSmall, kMSBDOpenFill }, { MSBDWindowSizeLarge, kMSBDOpenFill } },
                /* Small  */ { { MSBDWindowSizeSmall, MSBDWindowSizeSmall }, { MSBDWindowSizeSmall, MSBDWindowSizeSmall }, { MSBDWindowSizeSmall, MSBDWindowSizeSmall } },
                /* Medium */ { { MSBDWindowSizeDefault, MSBDWindowSizeDefault }, { MSBDWindowSizeDefault, MSBDWindowSizeDefault }, { MSBDWindowSizeDefault, MSBDWindowSizeDefault } },
                /* Large  */ { { MSBDWindowSizeLarge, MSBDWindowSizeLarge }, { MSBDWindowSizeLarge, MSBDWindowSizeLarge }, { MSBDWindowSizeLarge, MSBDWindowSizeLarge } },
                /* Fill   */ { { kMSBDOpenFill, kMSBDOpenFill }, { kMSBDOpenFill, kMSBDOpenFill }, { kMSBDOpenFill, kMSBDOpenFill } },
                /* iPhone */ { { kMSBDOpenIPhone, kMSBDOpenIPhone }, { kMSBDOpenIPhone, kMSBDOpenIPhone }, { kMSBDOpenIPhone, kMSBDOpenIPhone } },
            };
            const int ws[3] = { MSBDWindowSizeDefault, MSBDWindowSizeSmall, MSBDWindowSizeLarge };
            int rows = 0;
            for (int a = 0; a < 6; a++) for (int w = 0; w < 3; w++) for (int f = 0; f < 2; f++) {
                int got = MSBDOpeningSize(apps[a], ws[w], f);
                CHECK(got == expect[a][w][f], "1.1: app %s, Window Size %d, Open at Fill %d: opens %d (expected %d)", appName[a], ws[w], f, got, expect[a][w][f]);
                for (int own = 0; own < 2; own++) for (int asked = 0; asked < 2; asked++) {
                    bool free_ = MSBDOpensFree(apps[a], f, own, asked);
                    bool want = !own && !asked && (apps[a] != MSBDAppSizeNone || f);   // (1.3: no place of its own, not asked, and its own size or Fill)
                    CHECK(free_ == want, "1.3: app %s, Fill %d, own place %d, asked %d: free %d (expected %d)", appName[a], f, own, asked, free_, want);
                    rows++;
                }
                bool plain = MSBDOpeningIsPlainDefault(apps[a], ws[w], f);
                CHECK(plain == (a == 0 && ws[w] == MSBDWindowSizeDefault && !f), "Aerial 3.0's plain Default: app %s, Window Size %d, Fill %d: %d", appName[a], ws[w], f, plain);
            }
            CHECK(rows == 144, "1.3: 144 rows (%d)", rows);
            // with no entry, 1.8.7's answers on every input: Fill with Open at Fill on, else Window Size; free exactly as MSBDNewWindowAtFill
            for (int w = 0; w < 3; w++) for (int f = 0; f < 2; f++) {
                CHECK(MSBDOpeningSize(MSBDAppSizeNone, ws[w], f) == (MSBDNewWindowAtFill(f, false, false) ? kMSBDOpenFill : ws[w]), "no entry is 1.8.7: Window Size %d, Fill %d", ws[w], f);
                for (int own = 0; own < 2; own++) for (int asked = 0; asked < 2; asked++)
                    CHECK(MSBDOpensFree(MSBDAppSizeNone, f, own, asked) == MSBDNewWindowAtFill(f, own, asked), "no entry is 1.8.7's free window: Fill %d, own %d, asked %d", f, own, asked);
            }
            // a value that is not a choice (a later build's, a bad number) is no entry
            const int junk[] = { 0, 6, 7, -7, 99 };
            for (size_t j = 0; j < sizeof junk / sizeof junk[0]; j++) for (int w = 0; w < 3; w++) for (int f = 0; f < 2; f++)
                CHECK(MSBDOpeningSize(junk[j], ws[w], f) == MSBDOpeningSize(MSBDAppSizeNone, ws[w], f) && MSBDOpensFree(junk[j], f, false, false) == MSBDOpensFree(MSBDAppSizeNone, f, false, false)
                      && MSBDOpeningIsPlainDefault(junk[j], ws[w], f) == MSBDOpeningIsPlainDefault(MSBDAppSizeNone, ws[w], f), "a value %d that is no choice: as no entry", junk[j]);
            CHECK(MSBDOpeningSize(MSBDAppSizeMedium, MSBDWindowSizeLarge, true) == MSBDWindowSizeDefault && MSBDOpeningSize(MSBDAppSizeFill, MSBDWindowSizeSmall, false) == kMSBDOpenFill,
                  "the app's choice wins: Medium with Open at Fill on and Window Size Large is the Default window; Fill with Open at Fill off is Fill");
        }

        // ---- the frames on the iPads (test-windowsize.m's Pad table, u built as it builds it) ----
        const Pad pads[] = {
            { "iPad 2 (9.7\", 16.7.7)", {1024, 768}, 20, 699.07, 970.75, {320, 650} },
            { "M1 (11\", 15.6.1, Medium bar)", {1194, 834}, 30, 763.82, 1142.37, {320, 703} },
            { "17.5 (12.9\" 2nd gen)", {1366, 1024}, 20, 902.00, 1244.00, {379, 845} },
            { "A12Z (12.9\" 4th gen)", {1366, 1024}, 24, 940.00, 1290.00, {393, 876} },
            { "iPad mini 6", {1133, 744}, 24, 660.00, 1060.00, {320, 609} },
            { "iPad Air 4/5, iPad 10", {1180, 820}, 24, 736.00, 1106.00, {320, 682} },
            { "iPad 7-9 (10.2\")", {1080, 810}, 20, 726.00, 1090.00, {320, 676} },
            { "iPad Pro 13\" (M4)", {1376, 1032}, 24, 948.00, 1300.00, {393, 876} },
        };
        int desktops = 0;
        for (size_t p = 0; p < sizeof pads / sizeof pads[0]; p++) for (int o = 0; o < 2; o++) {
            const Pad *pd = &pads[p];
            CGSize s = o ? CGSizeMake(pd->screen.height, pd->screen.width) : pd->screen;
            double dockTop = o ? pd->dockTopPort : pd->dockTopLand, top = pd->bar + 12.0;
            CGRect u = CGRectMake(0, pd->bar, s.width, dockTop - 2.0 - pd->bar);   // (DMUsableArea: under the bar, 2 pt above the Dock, the screen's width)
            const char *shape = o ? "portrait" : "landscape";
            desktops++;
            for (int m = 0; m < 2; m++) {
                CGSize min = m ? smWide : least;
                const char *eng = m ? "Stage Manager (wider minimum)" : "A / Z / M";
                for (int a = 1; a < 6; a++) {
                    int opening = MSBDOpeningSize(apps[a], MSBDWindowSizeDefault, false);
                    CGRect f = MSBDAppWindowFrameIn(opening, u, s, top, 24.0, min);
                    if (apps[a] == MSBDAppSizeFill) { CHECK(CGRectIsNull(f), "%s %s %s: Fill is the engine's own layout (the caller's), not a window here", pd->name, shape, eng); continue; }
                    CHECK(!CGRectIsNull(f) && inside(f, u) && integral(f) && f.size.width >= min.width && f.size.height >= min.height,
                          "%s %s %s, %s: inside the desktop, whole points, at least the minimum (%s in %s)", pd->name, shape, eng, appName[a], S(f), S(u));
                    if (apps[a] == MSBDAppSizeSmall || apps[a] == MSBDAppSizeLarge || apps[a] == MSBDAppSizeMedium) {
                        int w = apps[a] == MSBDAppSizeSmall ? MSBDWindowSizeSmall : apps[a] == MSBDAppSizeLarge ? MSBDWindowSizeLarge : MSBDWindowSizeDefault;
                        CHECK(same(f, MSBDWindowSizeFrameIn(w, u, s, top, min)), "%s %s %s, %s: Window Size's own window to the point (%s)", pd->name, shape, eng, appName[a], S(f));
                    }
                    if (apps[a] == MSBDAppSizeMedium) CHECK(same(f, MSBDWindowCenterIn(u, s, top)), "%s %s %s: Medium is the middle place (MSBDWindowCenterIn %s), not the 66%% x 74%% share", pd->name, shape, eng, S(f));
                }
                CGRect ph = MSBDWindowPhoneIn(u, 24.0, min);
                BOOL held = ph.size.width <= min.width + 0.01;
                double aspect = (ph.size.width / (ph.size.height - 24.0)) / (kMSBDPhoneW / kMSBDPhoneH);
                CHECK(ph.size.width <= fmax(kMSBDPhoneW, min.width) && ph.size.height <= fmax(kMSBDPhoneH + 24.0, min.height) && ph.size.width >= 320.0,
                      "%s %s %s, iPhone %s: at most 393 x 852 under the bar, never under 320 wide", pd->name, shape, eng, S(ph));
                CHECK(held || fabs(aspect - 1.0) <= 0.01, "%s %s %s, iPhone %s: the phone's aspect within 1%% (%.4f) unless held at the minimum width", pd->name, shape, eng, S(ph), aspect);
                CHECK(fabs(CGRectGetMidX(ph) - CGRectGetMidX(u)) <= 1.0 && fabs(CGRectGetMidY(ph) - CGRectGetMidY(u)) <= 1.0, "%s %s %s, iPhone: centred in the desktop (%s in %s)", pd->name, shape, eng, S(ph), S(u));
                CHECK(same(ph, MSBDAppWindowFrameIn(kMSBDOpenIPhone, u, s, top, 24.0, min)), "%s %s %s: the iPhone choice's window is MSBDWindowPhoneIn", pd->name, shape, eng);
                if (!m) {
                    CGSize want = o ? CGSizeMake(393, 876) : pd->phoneLand;
                    CHECK(near(ph.size.width, want.width) && near(ph.size.height, want.height), "%s %s: iPhone %.0f x %.0f as 2.1's table (%.0f x %.0f)", pd->name, shape, ph.size.width, ph.size.height, want.width, want.height);
                    printf("  %-30s %-9s desktop %s: iPhone %s\n", pd->name, shape, S(u), S(ph));
                    // two apps at iPhone with Fit on (1.3): the second one cascade step from the first, both title bars in sight, inside the desktop
                    int how = 0;
                    CGRect second = MSBDWindowCascadeIn(ph, &ph, 1, u, 0, &how);
                    CHECK((how == 1 || how == -1) && inside(second, u) && (fabs(second.origin.x - ph.origin.x) >= kMSBDCascadeNear || fabs(second.origin.y - ph.origin.y) >= kMSBDCascadeNear),
                          "%s %s: a second iPhone window opens one cascade step from the first (how %d, %s)", pd->name, shape, how, S(second));
                }
                {   // row A6 / A12b over Fit's two tiles (1.8.8 F2)
                    CGRect first, second; int h1 = 0, h2 = 0;
                    CHECK(twoPhonesOverTiles(u, ph, &first, &second, &h1, &h2), "%s %s %s, two iPhone windows over Fit's two tiles: the second %s one step on from the first %s, down and right, the first's title bar in sight (how %d, %d)",
                          pd->name, shape, eng, S(second), S(first), h1, h2);
                    if (p == 0 && !o && !m) CHECK(same(first, CGRectMake(402, 47.07, 320, 650)) && same(second, CGRectMake(452, 47.07, 320, 650)), "the iPad 2's s01 row A6: {402, 47.07} then {452, 47.07}, not {302, 20} (%s, %s)", S(first), S(second));
                }
            }
        }
        CHECK(desktops == 16, "16 iPad desktops (%d)", desktops);
        // 2.1's numbers as the design wrote them, read back from the code: the held ones' app area
        {
            CGRect u2 = CGRectMake(0, 20, 1024, 699.07 - 22.0), ph = MSBDWindowPhoneIn(u2, 24, least), noMin = MSBDWindowPhoneIn(u2, 24, CGSizeZero);
            CHECK(near(noMin.size.width, 289) && near(noMin.size.height, 650) && near(ph.size.width, 320), "iPad 2 landscape: the app 289 x 626 held at 320 wide (%s, %s)", S(noMin), S(ph));
            CGRect um = CGRectMake(0, 30, 1194, 763.82 - 32.0), pm = MSBDWindowPhoneIn(um, 24, CGSizeZero);
            CHECK(near(pm.size.width, 313) && near(pm.size.height, 703), "M1 landscape: the app 313 x 679 (%s)", S(pm));
        }

        // ---- the TV desktops (Stage Manager's stage on an external display: our 24 pt bar, the middle place's top at 36) ----
        {
            typedef struct { const char *name; CGSize s; double uh; CGSize phone; } TV;
            const TV tvs[] = {
                { "A12Z's TV 2560 x 1440 (the Dock's 20%)", {2560, 1440}, 1440 - 288 - 2 - 24, {393, 876} },
                { "1920 x 1080 (the Dock's 20%)", {1920, 1080}, 1080 - 216 - 2 - 24, {360, 804} },
                { "1280 x 720 (the Dock's 20%)", {1280, 720}, 720 - 144 - 2 - 24, {320, 528} },
                { "iPad 2's TV 960 x 540 (its Dock top 476.5)", {960, 540}, 450.5, {320, 432} },
                { "960 x 540, the Dock hiding itself", {960, 540}, 516, {320, 495} },
                { "960 x 540, the Dock's 20% fallback", {960, 540}, 406, {320, 390} },
            };
            for (size_t t = 0; t < sizeof tvs / sizeof tvs[0]; t++) for (int m = 0; m < 2; m++) {
                CGSize min = m ? smWide : least;
                CGRect u = CGRectMake(0, 24, tvs[t].s.width, tvs[t].uh);
                for (int a = 1; a < 6; a++) {
                    int opening = MSBDOpeningSize(apps[a], MSBDWindowSizeSmall, false);   // (the TV's own Window Size Small: never asked for an app with a size)
                    CGRect f = MSBDAppWindowFrameIn(opening, u, tvs[t].s, 36, 24, min);
                    if (apps[a] == MSBDAppSizeFill) { CHECK(CGRectIsNull(f), "TV %s: Fill is the engine's own layout", tvs[t].name); continue; }
                    CHECK(!CGRectIsNull(f) && inside(f, u) && integral(f) && f.size.width >= min.width && f.size.height >= min.height, "TV %s min %.0f, %s: inside, whole points, at least the minimum (%s)", tvs[t].name, min.width, appName[a], S(f));
                    if (apps[a] != MSBDAppSizeIPhone) {
                        int w = apps[a] == MSBDAppSizeSmall ? MSBDWindowSizeSmall : apps[a] == MSBDAppSizeLarge ? MSBDWindowSizeLarge : MSBDWindowSizeDefault;
                        CHECK(same(f, MSBDWindowSizeFrameIn(w, u, tvs[t].s, 36, min)), "TV %s, %s: Window Size's own window (%s)", tvs[t].name, appName[a], S(f));
                    }
                }
                CGRect ph = MSBDWindowPhoneIn(u, 24, min);
                CHECK(ph.size.width >= 320 && ph.size.width <= fmax(393, min.width) && ph.size.height <= 876 && inside(ph, u) && integral(ph)
                      && fabs(CGRectGetMidX(ph) - CGRectGetMidX(u)) <= 1.0 && fabs(CGRectGetMidY(ph) - CGRectGetMidY(u)) <= 1.0, "TV %s min %.0f: iPhone %s inside, centred", tvs[t].name, min.width, S(ph));
                if (!m) {
                    CHECK(near(ph.size.width, tvs[t].phone.width) && near(ph.size.height, tvs[t].phone.height), "TV %s: iPhone %.0f x %.0f (2.1: %.0f x %.0f)", tvs[t].name, ph.size.width, ph.size.height, tvs[t].phone.width, tvs[t].phone.height);
                    printf("  TV %-42s desktop %s: iPhone %s\n", tvs[t].name, S(u), S(ph));
                } else CHECK(near(ph.size.width, fmax(414, tvs[t].phone.width)), "TV %s: a wider Stage Manager minimum holds (%s)", tvs[t].name, S(ph));
                CGRect first, second; int h1 = 0, h2 = 0;
                CHECK(twoPhonesOverTiles(u, ph, &first, &second, &h1, &h2), "TV %s min %.0f, two iPhone windows over Fit's two tiles: the second %s one step on from the first %s, down and right, the first's title bar in sight (how %d, %d)",
                      tvs[t].name, min.width, S(second), S(first), h1, h2);
            }
        }
        // ---- no desktop, a small one, a wider minimum ----
        {
            CGSize s = {1024, 768};
            CGRect nulls[] = { CGRectNull, CGRectZero, CGRectMake(0, 20, 0, 600), CGRectMake(0, 20, 1024, -5), CGRectMake(NAN, 20, 1024, 600), CGRectMake(0, 20, INFINITY, 600) };
            for (size_t i = 0; i < sizeof nulls / sizeof nulls[0]; i++) {
                CHECK(CGRectIsNull(MSBDWindowPhoneIn(nulls[i], 24, least)), "no desktop %zu: CGRectNull (the callers keep the engine's frame)", i);
                for (int a = 1; a < 6; a++) CHECK(CGRectIsNull(MSBDAppWindowFrameIn(MSBDOpeningSize(apps[a], 0, false), nulls[i], s, 32, 24, least)), "no desktop %zu, %s: CGRectNull", i, appName[a]);
            }
            CGRect u = CGRectMake(0, 20, 1024, 677);
            CHECK(CGRectIsNull(MSBDWindowPhoneIn(u, NAN, least)) && CGRectIsNull(MSBDWindowPhoneIn(u, -1, least)) && CGRectIsNull(MSBDWindowPhoneIn(u, 24, CGSizeMake(NAN, 324))), "no bar, a negative one, no minimum: CGRectNull");
            CGRect tiny = CGRectMake(0, 24, 300, 280.5), pt = MSBDWindowPhoneIn(tiny, 24, least);
            CHECK(inside(pt, tiny) && integral(pt) && near(pt.size.width, 300) && near(pt.size.height, 280), "a desktop smaller than a window may be: all of it in whole points (%s)", S(pt));
            CGRect odd = CGRectMake(0.5, 24.25, 1023.5, 677.3), po = MSBDWindowPhoneIn(odd, 24, least);
            CHECK(inside(po, odd) && integral(po), "a desktop at half points: inside it, whole points (%s)", S(po));
            CGRect ap = MSBDWindowPhoneIn(CGRectMake(0, 24, 1024, 1264), 24, CGSizeMake(414, 324));
            CHECK(near(ap.size.width, 414) && near(ap.size.height, 876), "a wider minimum (414): the window held at it (%s)", S(ap));
            CHECK(CGRectIsNull(MSBDAppWindowFrameIn(kMSBDOpenFill, u, s, 32, 24, least)) && CGRectIsNull(MSBDAppWindowFrameIn(9, u, s, 32, 24, least)) && CGRectIsNull(MSBDAppWindowFrameIn(-1, u, s, 32, 24, least)),
                  "Fill, or what is no opening: no window here");
        }

        // ---- the change list (1.6, round 4 amendment 1): the first read sets the baseline; then the bundles whose choice changed ----
        {
            CFDictionaryRef empty = readOf(@{}, NULL, NULL), abc = readOf(@{ @"com.c": @"iphone", @"com.a": @"large", @"com.b": @"small" }, NULL, NULL);
            CFDictionaryRef aOnly = readOf(@{ @"com.a": @"large" }, NULL, NULL);
            NSArray *r = toForget(false, empty, abc);
            CHECK(r && r.count == 0, "SpringBoard's first read with 3 apps: nothing forgotten (%s)", L(r));
            r = toForget(false, abc, empty);
            CHECK(r && r.count == 0, "  ... whatever the tables (%s)", L(r));
            r = toForget(true, empty, abc);
            CHECK([r isEqual:(@[ @"com.a", @"com.b", @"com.c" ])], "after the first read, before {} after 3 apps: the 3, sorted (%s)", L(r));
            r = toForget(true, empty, aOnly);
            CHECK([r isEqual:@[ @"com.a" ]], "after the first read, before {} after {A}: A (%s)", L(r));
            r = toForget(true, aOnly, empty);
            CHECK([r isEqual:@[ @"com.a" ]], "before {A} after {}: A, no crash (%s)", L(r));
            CHECK([changed(empty, abc) isEqual:(@[ @"com.a", @"com.b", @"com.c" ])], "the change list itself: before {} after 3 apps: the 3");
            CFDictionaryRef abc2 = readOf(@{ @"com.c": @"iphone", @"com.a": @"medium", @"com.b": @"small" }, NULL, NULL);
            CHECK([changed(abc, abc2) isEqual:@[ @"com.a" ]], "one choice changed: that one (%s)", L(changed(abc, abc2)));
            CFDictionaryRef ab = readOf(@{ @"com.a": @"large", @"com.b": @"small" }, NULL, NULL);
            CHECK([changed(abc, ab) isEqual:@[ @"com.c" ]] && [changed(ab, abc) isEqual:@[ @"com.c" ]], "one removed: that one; one added: that one");
            CFDictionaryRef abcCopy = readOf(@{ @"com.a": @"large", @"com.b": @"small", @"com.c": @"iphone" }, NULL, NULL);
            CHECK(changed(abc, abc).count == 0 && changed(abc, abcCopy).count == 0, "the same table (the same object or read again): none");
            CFDictionaryRef badA = readOf(@{ @"com.a": @"bogus", @"com.b": @"small" }, NULL, NULL), phoneA = readOf(@{ @"com.a": @"iphone", @"com.b": @"small" }, NULL, NULL);
            CHECK([changed(badA, phoneA) isEqual:@[ @"com.a" ]] && [changed(phoneA, badA) isEqual:@[ @"com.a" ]], "a bad text (none by the read rule) to \"iphone\": that one, and back: that one");
            CFDictionaryRef badA2 = readOf(@{ @"com.a": @7, @"com.b": @"small" }, NULL, NULL);
            CHECK(changed(badA, badA2).count == 0, "one bad value to another: no change (none both times)");
            CHECK(changed(empty, empty).count == 0 && toForget(true, empty, empty).count == 0, "both tables empty: none");
            r = changed(NULL, abc);
            NSArray *r2 = changed(abc, NULL), *r3 = changed(NULL, NULL), *r4 = toForget(true, NULL, abc);
            CHECK(r && r2 && r3 && r4 && r.count == 0 && r2.count == 0 && r3.count == 0 && r4.count == 0, "a NULL table (never SpringBoard's): no bundle, so a slip can never forget every app, no crash");
            // every pair of choices (none included): changed exactly when they differ
            for (int i = 0; i < 6; i++) for (int j = 0; j < 6; j++) {
                NSMutableDictionary *b = [NSMutableDictionary dictionaryWithObject:@"small" forKey:@"com.keep"], *a = [b mutableCopy];
                if (apps[i] != MSBDAppSizeNone) b[@"com.x"] = @(MSBDAppSizeName(apps[i]));
                if (apps[j] != MSBDAppSizeNone) a[@"com.x"] = @(MSBDAppSizeName(apps[j]));
                CFDictionaryRef tb = readOf(b, NULL, NULL), ta = readOf(a, NULL, NULL);
                NSArray *c = changed(tb, ta);
                CHECK(i == j ? c.count == 0 : [c isEqual:@[ @"com.x" ]], "%s to %s: %s", appName[i], appName[j], L(c));
                CFRelease(tb); CFRelease(ta);
            }
            // the answer sorted, whatever order the tables hold their keys in
            NSMutableDictionary *many = [NSMutableDictionary dictionary];
            NSArray *names = @[ @"z.app", @"m.app", @"a.app", @"q.app", @"b.app", @"y.app", @"c.app", @"x.app" ];
            for (NSString *n in names) many[n] = @"iphone";
            CFDictionaryRef tm = readOf(many, NULL, NULL);
            NSArray *cm = changed(empty, tm);
            CHECK([cm isEqual:[names sortedArrayUsingSelector:@selector(compare:)]], "the answer sorted (%s)", L(cm));
            NSArray *cm2 = changed(tm, empty);
            CHECK([cm2 isEqual:[names sortedArrayUsingSelector:@selector(compare:)]], "  ... removed ones too (%s)", L(cm2));
            // a hand-made table with a key that is not a string: skipped, no crash
            CFMutableDictionaryRef h = CFDictionaryCreateMutableCopy(NULL, 0, abc);
            CFDictionarySetValue(h, (__bridge CFTypeRef)@42, (__bridge CFTypeRef)@5);
            CHECK([changed(abc, h) isEqual:@[]] && [changed(h, abc) isEqual:@[]], "a key that is not a string: skipped");
            CFRelease(h);
            CFRelease(empty); CFRelease(abc); CFRelease(aOnly); CFRelease(abc2); CFRelease(ab); CFRelease(abcCopy); CFRelease(badA); CFRelease(phoneA); CFRelease(badA2); CFRelease(tm);
        }
        // ---- Settings (C4): the page's choices, titles and footers, the row's count, the 200 limit, the one write ----
        {
            const int order[5] = { MSBDAppSizeSmall, MSBDAppSizeMedium, MSBDAppSizeLarge, MSBDAppSizeFill, MSBDAppSizeIPhone };
            const char *titles[5] = { "Small", "Medium", "Large", "Fill", "iPhone" };
            for (int i = 0; i < 5; i++) CHECK(MSBDAppSizeChoiceAt(i) == order[i] && MSBDAppSizeTitle(order[i]) && !strcmp(MSBDAppSizeTitle(order[i]), titles[i]), "choice %d: %s", i, titles[i]);
            CHECK(MSBDAppSizeChoiceAt(5) == MSBDAppSizeNone && MSBDAppSizeChoiceAt(-1) == MSBDAppSizeNone && !MSBDAppSizeTitle(MSBDAppSizeNone) && !MSBDAppSizeTitle(0) && !MSBDAppSizeTitle(6),
                  "five choices only (no Custom, no Default), and no title for anything else");
            CHECK(MSBDAppSizeFooter(MSBDAppSizeNone) && !strcmp(MSBDAppSizeFooter(MSBDAppSizeNone), "Pick the size this app opens at."), "footer, nothing picked yet");
            CHECK(MSBDAppSizeFooter(MSBDAppSizeFill) && !strcmp(MSBDAppSizeFooter(MSBDAppSizeFill), "The window fills the desktop."), "footer, Fill");
            CHECK(MSBDAppSizeFooter(MSBDAppSizeIPhone) && !strcmp(MSBDAppSizeFooter(MSBDAppSizeIPhone), "A tall window the shape of an iPhone. Most apps show their iPhone layout in it. If the screen is too small, it's made smaller to fit."), "footer, iPhone");
            CHECK(!MSBDAppSizeFooter(MSBDAppSizeSmall) && !MSBDAppSizeFooter(MSBDAppSizeMedium) && !MSBDAppSizeFooter(MSBDAppSizeLarge), "no footer for Small, Medium, Large (nothing about Window Size's Default, amendment 2)");
            for (int c = -1; c <= 6; c++) { const char *f = MSBDAppSizeFooter(c); CHECK(!f || (!strstr(f, "Default") && !strstr(f, "\xE2\x80\x94") && !strstr(f, " -- ") && f[strlen(f) - 1] == '.'), "footer %d: a sentence, no Default, no dash", c); }
            char t[32];
            MSBDAppSizesCountText(0, t, sizeof t); CHECK(!strcmp(t, ""), "count: none shows nothing");
            MSBDAppSizesCountText(1, t, sizeof t); CHECK(!strcmp(t, "1 App"), "count: 1 App (%s)", t);
            MSBDAppSizesCountText(2, t, sizeof t); CHECK(!strcmp(t, "2 Apps"), "count: 2 Apps (%s)", t);
            MSBDAppSizesCountText(200, t, sizeof t); CHECK(!strcmp(t, "200 Apps"), "count: 200 Apps (%s)", t);
            CHECK(MSBDAppSizesCanAdd(0) && MSBDAppSizesCanAdd(199) && !MSBDAppSizesCanAdd(200) && !MSBDAppSizesCanAdd(201) && !MSBDAppSizesCanAdd(-1), "Add App while fewer than 200 are listed");
            // the one write: one entry changed, the rest as stored, NULL (the key removed) with no entry left, never an empty dictionary
            NSDictionary *(^with)(id, NSString *, int) = ^NSDictionary *(id stored, NSString *b, int c) { return CFBridgingRelease(MSBDAppSizesWith((__bridge CFTypeRef)stored, (__bridge CFStringRef)b, c)); };
            CHECK([with(nil, @"com.apple.mobilenotes", MSBDAppSizeIPhone) isEqual:@{ @"com.apple.mobilenotes": @"iphone" }], "write: the first app, the key absent");
            for (int i = 0; i < 5; i++) CHECK([with(nil, @"a.b", order[i]) isEqual:@{ @"a.b": @(MSBDAppSizeName(order[i])) }], "write: %s stored as its text", titles[i]);
            NSDictionary *two = @{ @"a.app": @"small", @"b.app": @"iphone" };
            CHECK([with(two, @"a.app", MSBDAppSizeLarge) isEqual:(@{ @"a.app": @"large", @"b.app": @"iphone" })], "write: a change, the other kept");
            CHECK([with(two, @"a.app", MSBDAppSizeNone) isEqual:@{ @"b.app": @"iphone" }], "write: Remove App, the other kept");
            CHECK(with(@{ @"a.app": @"small" }, @"a.app", MSBDAppSizeNone) == nil, "write: the last app removed: NULL, the key removed (never an empty dictionary)");
            CHECK(with(nil, @"a.app", MSBDAppSizeNone) == nil && with(@{}, @"a.app", MSBDAppSizeNone) == nil, "write: nothing to remove from nothing: still no dictionary");
            CHECK([with(@{ @"a.app": @"custom:60x80", @"b.app": @"small" }, @"b.app", MSBDAppSizeFill) isEqual:(@{ @"a.app": @"custom:60x80", @"b.app": @"fill" })], "write: an entry this release cannot read is kept as stored (a downgrade keeps a future choice)");
            CHECK(with(@{ @"a.app": @7 }, @"a.app", MSBDAppSizeNone) == nil, "write: Remove App on an unreadable entry removes it");
            CHECK([with(@[ @"x" ], @"a.app", MSBDAppSizeSmall) isEqual:@{ @"a.app": @"small" }] && [with(@"text", @"a.app", MSBDAppSizeSmall) isEqual:@{ @"a.app": @"small" }], "write: a stored value that is not a dictionary counts as none");
            CHECK([with(two, @"", MSBDAppSizeSmall) isEqual:two] && [with(two, [@"" stringByPaddingToLength:256 withString:@"x" startingAtIndex:0], MSBDAppSizeSmall) isEqual:two] && [with(two, nil, MSBDAppSizeSmall) isEqual:two],
                  "write: a bundle the read rule refuses (empty, 256 characters, none) changes nothing");
            CHECK([with(two, @"a.app", 0) isEqual:two] && [with(two, @"a.app", 9) isEqual:two], "write: a choice that is neither one of the five nor None changes nothing");
            // what Settings writes reads back as it was picked
            for (int i = 0; i < 5; i++) {
                NSDictionary *w = with(two, @"c.app", order[i]);
                CFDictionaryRef r = readOf(w, NULL, NULL);
                CHECK(MSBDAppSizeIn(r, CFSTR("c.app")) == order[i] && MSBDAppSizeIn(r, CFSTR("a.app")) == MSBDAppSizeSmall && CFDictionaryGetCount(r) == 3, "write then read: %s", titles[i]);
                CFRelease(r);
            }
        }
        printf("test-appwindowsize: %d/%d passed\n", passes, passes + fails);
    }
    return fails ? 1 : 0;
}
