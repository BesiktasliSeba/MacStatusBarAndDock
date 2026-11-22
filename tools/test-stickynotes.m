// Mac test of Sticky Notes' rules (common/StickyNotes.h, the code statusbar/DesktopNotes.h runs; 1.8.8.1): Stickies' colours, where a note is
// shown on the iPad desktops in both orientations and with the Dock at a side, keeping clear of app icons, the lift over the keyboard, the store's
// read rule (never empty when unread, a newer store left alone, bad entries skipped, the caps), the Trash attributes, and the windows' resize maths
// (NativeWindow.h DMNativeResized, built from the source as written) with a note's minimum and area. Run by test-stickynotes.sh.
#import <Foundation/Foundation.h>
#include "../common/StickyNotes.h"
#include "resized.h"   // (test-stickynotes.sh: DMNativeResized cut out of statusbar/NativeWindow.h as it is)

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

typedef struct { const char *name; CGFloat w, h; BOOL sideDock; } Screen;
static const Screen screens[] = {   // (the iPads' screens in points; a Dock at a side takes 90 pt at the left)
    {"11-inch landscape", 1194, 834, NO}, {"11-inch portrait", 834, 1194, NO}, {"12.9 landscape", 1366, 1024, NO}, {"12.9 portrait", 1024, 1366, NO},
    {"10.2 landscape", 1080, 810, NO}, {"10.2 portrait", 810, 1080, NO}, {"11-inch side Dock", 1194, 834, YES}, {"12.9 side Dock", 1366, 1024, YES},
};
static CGRect areaOf(Screen s) {   // (Desktop.h -dm_area: under the 24 pt menu bar, above the Dock, 6 / 4 pt in)
    CGRect d = s.sideDock ? CGRectMake(90, 26, s.w - 90, s.h - 26) : CGRectMake(0, 26, s.w, s.h - (s.w < s.h ? 96 : 84) - 26);
    return CGRectInset(d, 6, 4);
}
static int appRects(Screen s, CGRect area, CGRect *out, int apps) {   // (an app icon grid and the page dots, as test-desktopplace's page 1)
    int n = 0, cols = s.w > s.h ? 6 : 4, rows = s.w > s.h ? 4 : 6;
    CGFloat mx = s.w < s.h ? 70 : 110, my = 50, stepX = (s.w - 2 * mx - 84) / (cols - 1), stepY = (CGRectGetMaxY(area) - 60 - my - 100) / (rows - 1);
    for (int i = 0; i < apps && i < cols * rows; i++) out[n++] = CGRectInset(CGRectMake(mx + (i % cols) * stepX, my + (i / cols) * stepY, 84, 100), -4, -4);
    out[n++] = CGRectMake(s.w / 2 - 72, CGRectGetMaxY(area) - 44, 144.5, 48);
    return n;
}
static BOOL inside(CGRect f, CGRect a) { return CGRectGetMinX(f) >= CGRectGetMinX(a) - 0.01 && CGRectGetMinY(f) >= CGRectGetMinY(a) - 0.01 && CGRectGetMaxX(f) <= CGRectGetMaxX(a) + 0.01 && CGRectGetMaxY(f) <= CGRectGetMaxY(a) + 0.01; }
static BOOL overAny(CGRect f, const CGRect *r, int n) { for (int k = 0; k < n; k++) if (MSBDStickyRectsOverlap(f, r[k])) return YES; return NO; }
static NSString *uuid(void) { return [NSUUID UUID].UUIDString; }
static NSData *plist(id o) { return [NSPropertyListSerialization dataWithPropertyList:o format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL]; }
static NSDictionary *note(NSString *i, NSString *c, double x, double y, double w, double h, NSString *t) { return @{@"id": i, @"color": c, @"x": @(x), @"y": @(y), @"w": @(w), @"h": @(h), @"text": t}; }

int main(void) { @autoreleasepool {
    // ---- colours: Stickies' six, in its order (its Assets.car, sRGB: body / "Spine") ----
    const char *names[] = {"Yellow", "Blue", "Green", "Pink", "Purple", "Gray"};
    const unsigned body[] = {0xFEF49C, 0xADF4FF, 0xB2FFA1, 0xFFC7C7, 0xB6CAFF, 0xEEEEEE}, band[] = {0xFEEA3D, 0x89F0FF, 0x83FE83, 0xFFB2B2, 0x9BB6FE, 0xDADADA};
    CHECK(MSBD_NOTE_COLORS == 6, "six colours, has %d", MSBD_NOTE_COLORS);
    for (int i = 0; i < 6; i++) {
        CGFloat r, g, b, r2, g2, b2; MSBDStickyRGB(kMSBDStickyColors[i].body, &r, &g, &b); MSBDStickyRGB(body[i], &r2, &g2, &b2);
        CHECK(!strcmp(kMSBDStickyColors[i].name, names[i]) && [MSBDStickyColorName(i) isEqualToString:@(names[i])] && MSBDStickyColorIndex(@(names[i])) == i, "colour %d is %s", i, names[i]);
        CHECK(fabs(r - r2) < 1.0 / 255 && fabs(g - g2) < 1.0 / 255 && fabs(b - b2) < 1.0 / 255 && kMSBDStickyColors[i].band == band[i], "colour %s: Stickies' body and band", names[i]);
    }
    CHECK(MSBDStickyColorIndex(@"Orange") == 0 && MSBDStickyColorIndex(nil) == 0 && MSBDStickyColorIndex(@7) == 0 && [MSBDStickyColorName(9) isEqualToString:@"Yellow"], "an unknown colour reads as Yellow");

    // ---- shown: inside the free area, at least the minimum, the stored size kept when it fits, a turn and back the same ----
    for (size_t si = 0; si < sizeof screens / sizeof screens[0]; si++) {
        Screen s = screens[si], t = {s.name, s.h, s.w, s.sideDock};
        CGRect a = areaOf(s), at = areaOf(t);
        int bad = 0, kept = 0, keptWant = 0, back = 0;
        for (double fx = 0; fx <= 1.0001; fx += 0.125) for (double fy = 0; fy <= 1.0001; fy += 0.125) for (int k = 0; k < 4; k++) {
            CGSize sz = k == 0 ? CGSizeMake(220, 180) : k == 1 ? CGSizeMake(60, 30) : k == 2 ? CGSizeMake(3000, 2500) : CGSizeMake(500, 640);
            CGPoint c = CGPointMake(a.origin.x + fx * a.size.width, a.origin.y + fy * a.size.height);
            CGRect f = MSBDStickyFrameAt(a, c, sz);
            if (!inside(f, a) || f.size.width < MIN(MSBD_NOTE_MIN_W, a.size.width) - 0.01 || f.size.height < MIN(MSBD_NOTE_MIN_H, a.size.height) - 0.01) bad++;
            if (sz.width >= MSBD_NOTE_MIN_W && sz.height >= MSBD_NOTE_MIN_H && sz.width <= a.size.width && sz.height <= a.size.height) { keptWant++; if (fabs(f.size.width - sz.width) < 0.01 && fabs(f.size.height - sz.height) < 0.01) kept++; }
            CGRect ft = MSBDStickyFrameAt(at, CGPointMake(at.origin.x + fx * at.size.width, at.origin.y + fy * at.size.height), sz);   // (turned: the same share)
            CGRect f2 = MSBDStickyFrameAt(a, c, sz);   // (and back: the stored size and share never changed)
            if (CGRectEqualToRect(f, f2) && inside(ft, at)) back++;
        }
        CHECK(!bad, "%s: %d frames outside the area or under the minimum", s.name, bad);
        CHECK(kept == keptWant, "%s: the stored size kept where it fits (%d of %d)", s.name, kept, keptWant);
        CHECK(back == 9 * 9 * 4, "%s: a turn and back gives the same frame (%d)", s.name, back);
    }
    CHECK(CGRectEqualToRect(MSBDStickyFrameAt(CGRectMake(0, 0, 100, 60), CGPointMake(50, 30), CGSizeMake(220, 180)), CGRectMake(0, 0, 100, 60)), "an area smaller than the minimum: the area");
    CHECK(inside(MSBDStickyFrameAt(CGRectMake(10, 20, 800, 600), CGPointMake(NAN, INFINITY), CGSizeMake(NAN, 200)), CGRectMake(10, 20, 800, 600)), "no number from the store leaves the area");

    // ---- clear of app icons, widgets and page dots ----
    for (size_t si = 0; si < sizeof screens / sizeof screens[0]; si++) {
        Screen s = screens[si]; CGRect a = areaOf(s), r[64];
        int n = appRects(s, a, r, 8), over = 0, outside = 0, moved = 0; long worst = 0;   // (two rows of apps: room left below them)
        CGRect free0 = CGRectMake(CGRectGetMidX(a) - 110, CGRectGetMinY(a), 220, 180);
        CHECK(CGRectEqualToRect(MSBDStickyPlaceClear(free0, a, NULL, 0, MSBD_NOTE_CLEAR_TESTS, NULL), free0), "%s: a free spot is kept as it is", s.name);
        for (double fx = 0; fx <= 1.0001; fx += 0.1) for (double fy = 0; fy <= 1.0001; fy += 0.1) {
            CGRect f = MSBDStickyFrameAt(a, CGPointMake(a.origin.x + fx * a.size.width, a.origin.y + fy * a.size.height), CGSizeMake(220, 180));
            long tests = 0; CGRect c = MSBDStickyPlaceClear(f, a, r, n, MSBD_NOTE_CLEAR_TESTS, &tests);
            if (tests > worst) worst = tests;
            if (!inside(c, a)) outside++;
            if (overAny(c, r, n)) over++;
            if (!CGRectEqualToRect(c, f)) moved++;
            if (!overAny(f, r, n) && !CGRectEqualToRect(c, f)) over += 1000;   // (a clear frame must never move)
        }
        CHECK(!outside, "%s: %d notes placed outside the area", s.name, outside);
        CHECK(!over, "%s: %d notes left over an app icon or the page dots (or a clear one moved)", s.name, over);
        CHECK(worst <= MSBD_NOTE_CLEAR_TESTS + n, "%s: rect tests within the cap (%ld)", s.name, worst);
        printf("INFO: %-18s 8 apps: %d of 121 note places moved clear, at most %ld rect tests\n", s.name, moved, worst);
        {   // a full page 1 of apps: no room for a note anywhere -- kept inside the area, the cap holds
            CGRect r24[64]; int n24 = appRects(s, a, r24, 24), out24 = 0; long w24 = 0;
            for (double fx = 0; fx <= 1.0001; fx += 0.25) for (double fy = 0; fy <= 1.0001; fy += 0.25) {
                long t24 = 0; CGRect c = MSBDStickyPlaceClear(MSBDStickyFrameAt(a, CGPointMake(a.origin.x + fx * a.size.width, a.origin.y + fy * a.size.height), CGSizeMake(220, 180)), a, r24, n24, MSBD_NOTE_CLEAR_TESTS, &t24);
                if (!inside(c, a)) out24++;
                if (t24 > w24) w24 = t24;
            }
            CHECK(!out24 && w24 <= MSBD_NOTE_CLEAR_TESTS + n24, "%s, a full page of apps: inside the area, rect tests within the cap (%ld)", s.name, w24);
        }
        // a full page (nothing clear anywhere): the frame kept inside the area, the cap holds
        CGRect full[1] = { CGRectInset(a, -10, -10) }; long tests = 0;
        CGRect f = CGRectMake(CGRectGetMaxX(a) - 100, CGRectGetMaxY(a) - 50, 220, 180);
        CGRect c = MSBDStickyPlaceClear(f, a, full, 1, MSBD_NOTE_CLEAR_TESTS, &tests);
        CHECK(CGRectEqualToRect(c, MSBDStickyClampInside(f, a)) && tests <= MSBD_NOTE_CLEAR_TESTS + 1, "%s: a full page gives the frame kept inside the area (%ld tests)", s.name, tests);
        // a new note: top left at the press, clear, inside
        CGRect nf = MSBDStickyNewFrame(CGPointMake(CGRectGetMidX(a), CGRectGetMidY(a)), a, r, n);
        CHECK(inside(nf, a) && !overAny(nf, r, n) && fabs(nf.size.width - 220) < 0.01, "%s: a new note is clear and inside", s.name);
        CGRect nf2 = MSBDStickyNewFrame(CGPointMake(CGRectGetMinX(a) + 400, CGRectGetMinY(a) + 300), a, NULL, 0);
        CHECK(fabs(nf2.origin.x - (CGRectGetMinX(a) + 400)) < 0.01 && fabs(nf2.origin.y - (CGRectGetMinY(a) + 300)) < 0.01, "%s: a new note's top left corner is at the pressed spot", s.name);
    }

    // ---- the lift over a docked keyboard ----
    {
        CGRect home = CGRectMake(100, 600, 220, 180), kb = CGRectMake(0, 500, 1194, 334); CGFloat inset = -1;
        CHECK(CGRectEqualToRect(MSBDStickyLift(home, CGRectZero, 30, &inset), home) && inset == 0, "no keyboard: the note stays");
        CHECK(CGRectEqualToRect(MSBDStickyLift(CGRectMake(100, 100, 220, 180), kb, 30, &inset), CGRectMake(100, 100, 220, 180)) && inset == 0, "a note clear of the keyboard stays");
        CGRect l = MSBDStickyLift(home, kb, 30, &inset);
        CHECK(fabs(CGRectGetMaxY(l) - (500 - 8)) < 0.01 && inset == 0 && l.origin.x == 100 && l.size.height == 180, "lifted: 8 pt above the keyboard");
        CGRect tall = CGRectMake(100, 300, 220, 700); l = MSBDStickyLift(tall, kb, 30, &inset);
        CHECK(fabs(l.origin.y - 30) < 0.01 && fabs(inset - (30 + 700 - 492)) < 0.01, "too tall: never above the top, and the covered part as an inset (%.1f)", inset);
        CGRect high = CGRectMake(100, 20, 220, 600); l = MSBDStickyLift(high, kb, 30, &inset);
        CHECK(l.origin.y <= high.origin.y + 0.01, "the lift only ever moves a note up");
    }

    // ---- the store's read rule ----
    {
        NSMutableArray *shown = [NSMutableArray array], *kept = [NSMutableArray array]; int skipped = -1;
        CHECK(MSBDStickyStoreRead(nil, ENOENT, shown, kept, &skipped) == MSBDStickyNone && MSBDStickyWritable(MSBDStickyNone) && !shown.count, "no file: no notes, writing allowed");
        CHECK(MSBDStickyStoreRead(nil, EACCES, shown, kept, &skipped) == MSBDStickyUnread && MSBDStickyStoreRead(nil, EPERM, shown, kept, NULL) == MSBDStickyUnread && MSBDStickyStoreRead(nil, 0, shown, kept, NULL) == MSBDStickyUnread,
              "a refused read (data protection, permissions, any error but no file): not readable yet");
        CHECK(!MSBDStickyWritable(MSBDStickyUnread) && !MSBDStickyWritable(MSBDStickyNewer), "... and nothing may be written then, nor over a newer store");
        CHECK(MSBDStickyStoreRead([@"not a plist" dataUsingEncoding:NSUTF8StringEncoding], 0, shown, kept, NULL) == MSBDStickyAside && MSBDStickyStoreRead([NSData data], 0, shown, kept, NULL) == MSBDStickyAside
              && MSBDStickyStoreRead(plist(@[@1]), 0, shown, kept, NULL) == MSBDStickyAside && MSBDStickyStoreRead(plist(@{@"version": @1}), 0, shown, kept, NULL) == MSBDStickyAside
              && MSBDStickyStoreRead(plist(@{@"version": @0, @"notes": @[]}), 0, shown, kept, NULL) == MSBDStickyAside && MSBDStickyWritable(MSBDStickyAside), "not a store: put aside, then empty and writable");
        CHECK(MSBDStickyStoreRead(plist(@{@"version": @2, @"notes": @[note(uuid(), @"Blue", 0.5, 0.5, 220, 180, @"MSB-TEST")]}), 0, shown, kept, NULL) == MSBDStickyNewer && !shown.count, "a newer release's store: nothing shown");
        NSString *a = uuid(), *b = uuid();
        NSArray *mixed = @[note(a, @"Pink", 0.2, 0.3, 300, 200, @"MSB-TEST one"), @{@"id": @"not-a-uuid", @"x": @0, @"y": @0, @"w": @1, @"h": @1}, @"junk",
                           @{@"id": uuid(), @"x": @(NAN), @"y": @0, @"w": @200, @"h": @200}, @{@"id": uuid(), @"x": @0, @"y": @0, @"w": @200, @"h": @200, @"text": @5},
                           note(a, @"Blue", 0, 0, 220, 180, @"MSB-TEST again"), note(b, @"Mauve", 7, -3, 5, 99999, @"MSB-TEST two")];
        [shown removeAllObjects]; [kept removeAllObjects];
        CHECK(MSBDStickyStoreRead(plist(@{@"version": @1, @"notes": mixed}), 0, shown, kept, &skipped) == MSBDStickyOK && shown.count == 2 && skipped == 5, "bad entries skipped (%d), good ones read (%lu)", skipped, (unsigned long)shown.count);
        CHECK(shown.count == 2 && [shown[0][@"id"] isEqualToString:a] && [shown[0][@"color"] isEqualToString:@"Pink"] && [shown[1][@"color"] isEqualToString:@"Yellow"]
              && [shown[1][@"x"] doubleValue] == 1 && [shown[1][@"y"] doubleValue] == 0 && [shown[1][@"w"] doubleValue] == MSBD_NOTE_MIN_W && [shown[1][@"h"] doubleValue] == MSBD_NOTE_MAX_SIDE,
              "an unknown colour is Yellow, places and sizes clamped, the order kept");
        NSMutableArray *many = [NSMutableArray array];
        for (int i = 0; i < 31; i++) [many addObject:note(uuid(), @"Green", 0.5, 0.5, 220, 180, [NSString stringWithFormat:@"MSB-TEST %d", i])];
        [shown removeAllObjects]; [kept removeAllObjects];
        MSBDStickyStoreRead(plist(@{@"version": @1, @"notes": many}), 0, shown, kept, NULL);
        CHECK(shown.count == 30 && kept.count == 1 && [kept[0][@"text"] isEqualToString:@"MSB-TEST 30"], "the 31st note is not shown but kept");
        NSData *again = MSBDStickyStoreBuild(shown, kept);
        NSMutableArray *s2 = [NSMutableArray array], *k2 = [NSMutableArray array];
        CHECK(MSBDStickyStoreRead(again, 0, s2, k2, NULL) == MSBDStickyOK && [s2 isEqualToArray:shown] && [k2 isEqualToArray:kept], "written and read back: the same notes, the kept one too");
        NSMutableString *longText = [NSMutableString string]; while (longText.length < MSBD_NOTE_TEXT_MAX + 1) [longText appendString:@"a"];
        NSString *emoji = [[longText substringToIndex:MSBD_NOTE_TEXT_MAX - 1] stringByAppendingString:@"\U0001F600 more"];
        [shown removeAllObjects];
        MSBDStickyStoreRead(plist(@{@"version": @1, @"notes": @[note(uuid(), @"Gray", 0, 0, 220, 180, longText), note(uuid(), @"Gray", 0, 0, 220, 180, emoji)]}), 0, shown, kept, NULL);
        CHECK([shown[0][@"text"] length] == MSBD_NOTE_TEXT_MAX && [shown[1][@"text"] length] == MSBD_NOTE_TEXT_MAX - 1, "the 10,001st character cut; an emoji at the cut goes whole (%lu)", (unsigned long)[shown[1][@"text"] length]);
        CHECK([MSBDStickyTextCut(@"MSB-TEST", 100) isEqualToString:@"MSB-TEST"] && [MSBDStickyTextCut(nil, 5) isEqualToString:@""], "a short text is kept as it is");
        CHECK(MSBDStickyIdValid(uuid()) && !MSBDStickyIdValid(@"x") && !MSBDStickyIdValid(@1) && [MSBDStickyShortId(@"0123456789AB") isEqualToString:@"01234567"] && [MSBDStickyShortId(nil) isEqualToString:@"-"], "the id rule and the short id logs use");
        CHECK([MSBDStickyAsideName(1) isEqualToString:@"StickyNotes-unreadable.plist"] && [MSBDStickyAsideName(3) isEqualToString:@"StickyNotes-unreadable 3.plist"], "a store put aside is never written over");
    }

    // ---- the Trash file's attributes: written and read back ----
    {
        NSString *c = nil; double w = 0, h = 0, fx = -1, fy = -1;
        NSString *attr = MSBDStickyTrashAttr(@"Purple", 300.4, 211.6);
        CHECK([attr isEqualToString:@"1 Purple 300 212"] && MSBDStickyTrashAttrRead(attr, &c, &w, &h) && [c isEqualToString:@"Purple"] && w == 300 && h == 212, "the look attribute round trip (%s)", attr.UTF8String);
        CHECK(!MSBDStickyTrashAttrRead(@"2 Blue 1 1", NULL, NULL, NULL) && !MSBDStickyTrashAttrRead(@"1 Blue x", NULL, NULL, NULL) && !MSBDStickyTrashAttrRead(@"1 Blue -4 9", NULL, NULL, NULL) && !MSBDStickyTrashAttrRead(@3, NULL, NULL, NULL),
              "not a note's attribute: refused");
        CHECK(MSBDStickyTrashAttrRead(@"1 Teal 20 99999", &c, &w, &h) && [c isEqualToString:@"Yellow"] && w == MSBD_NOTE_MIN_W && h == MSBD_NOTE_MAX_SIDE, "an unknown colour and sizes out of range read safely");
        CHECK(MSBDStickyPlaceRead(@"0.25000,0.75000", &fx, &fy) && fx == 0.25 && fy == 0.75 && MSBDStickyPlaceRead(@"-3,9", &fx, &fy) && fx == 0 && fy == 1 && !MSBDStickyPlaceRead(@"0.5", NULL, NULL), "the place attribute in the icons' format");
        CHECK([MSBD_NOTE_TRASH_ORIGIN isEqualToString:@"sticky-note"] && ![MSBD_NOTE_TRASH_ORIGIN hasPrefix:@"/"], "the Trash file's origin is a marker, never a path");
    }

    // ---- the resize: the windows' own maths (DMNativeResized), the note's minimum, kept inside the area ----
    {
        CGRect desk = CGRectMake(6, 30, 1182, 716); CGSize mn = CGSizeMake(MSBD_NOTE_MIN_W, MSBD_NOTE_MIN_H);
        CGRect st = CGRectMake(500, 300, 220, 180);
        CGRect f = DMNativeResized(st, CGPointMake(60, 40), 1, mn, desk, YES);
        CHECK(CGRectEqualToRect(f, CGRectMake(500, 300, 280, 220)), "the right grip grows it to the right and down");
        f = DMNativeResized(st, CGPointMake(-60, 40), 0, mn, desk, YES);
        CHECK(fabs(CGRectGetMaxX(f) - CGRectGetMaxX(st)) < 0.01 && fabs(f.size.width - 280) < 0.01, "the left grip keeps the right edge");
        f = DMNativeResized(st, CGPointMake(-500, -500), 1, mn, desk, YES);
        CHECK(f.size.width == MSBD_NOTE_MIN_W && f.size.height == MSBD_NOTE_MIN_H, "never under the minimum");
        f = DMNativeResized(st, CGPointMake(5000, 5000), 1, mn, desk, YES);
        CHECK(f.size.width <= desk.size.width && CGRectGetMaxY(f) <= CGRectGetMaxY(desk) + 0.01, "never wider than the area, never past its bottom");
        f = DMNativeResized(CGRectMake(1000, 300, 150, 100), CGPointMake(400, 0), 1, mn, desk, YES);
        CHECK(fabs(CGRectGetMaxX(f) - CGRectGetMaxX(desk)) < 0.01 && f.origin.x == 1000 && inside(f, desk) && CGRectEqualToRect(MSBDStickyClampInside(f, desk), f),
              "the right grip past the area's right edge stops at it, the left edge stays (check item 14; 1.8.8.2 B72, test-stickygrip)");
        f = DMNativeResized(CGRectMake(20, 300, 150, 100), CGPointMake(-400, 0), 0, mn, desk, YES);
        CHECK(fabs(CGRectGetMinX(f) - CGRectGetMinX(desk)) < 0.01 && fabs(CGRectGetMaxX(f) - 170) < 0.01 && inside(f, desk) && CGRectEqualToRect(MSBDStickyClampInside(f, desk), f),
              "the left grip past the area's left edge stops at it, the right edge stays");
        f = DMNativeResized(CGRectMake(500, 700, 220, 40), CGPointMake(0, 0), 1, mn, desk, YES);
        CHECK(CGRectGetMaxY(f) <= CGRectGetMaxY(desk) + 0.01 && f.size.height == MSBD_NOTE_MIN_H, "too low for the minimum: it moves up");
    }
    printf("test-stickynotes: %d passed, %d failed\n", passes, fails);
    if (!fails) printf("PASS  the rules (%d checks)\n", passes); else printf("FAIL  the rules (%d of %d checks failed)\n", fails, passes + fails);
    return fails ? 1 : 0;
} }
