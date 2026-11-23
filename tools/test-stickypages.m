// Mac test of sticky notes on other Home Screen pages (1.8.8.2 F36, KT 22 Nov: "allowing sticky notes in other pages too"; "they can be dragged to
// second page, and ... an option move it to another page automatically without dragging"): common/StickyNotes.h's page key, which page a note
// shows on, the side of the screen a dragged note turns the pages at, its times and the page a turn goes to. Run by test-stickypages.sh.
#import <Foundation/Foundation.h>
#include "../common/StickyNotes.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; printf("PASS  "); } else { fails++; printf("FAIL  "); } printf(__VA_ARGS__); printf("\n"); } while (0)

int main(void) { @autoreleasepool {
    // ---- which page: the key, and where a note shows ----
    NSString *p1 = @"8F0E2B54-1D3A-4C6E-9F80-A1B2C3D4E5F6", *p2 = @"07A1C2D3-1111-4222-8333-944455566677", *p3 = @"B0B1B2B3-2222-4333-8444-955566677788";
    NSArray *pages = @[p1, p2, p3];
    CHECK([MSBDStickyPageKey(p2) isEqualToString:[@"home:" stringByAppendingString:p2]] && [MSBDStickyPageIdOf(MSBDStickyPageKey(p2)) isEqualToString:p2], "a page's key is \"home:\" and iPadOS's own page id, read back");
    CHECK(!MSBDStickyPageKey(@"") && !MSBDStickyPageKey(@4) && !MSBDStickyPageKey(nil) && !MSBDStickyPageIdOf(@"home:") && !MSBDStickyPageIdOf(@"display:tv") && !MSBDStickyPageIdOf(@"desk:2") && !MSBDStickyPageIdOf(@7),
          "no key from no id; a key of another kind (the TV's, a Mac Switcher desktop's: later) is no Home Screen page");
    NSMutableString *lng = [NSMutableString string]; while (lng.length < MSBD_NOTE_PAGE_MAX) [lng appendString:@"x"];
    CHECK(!MSBDStickyPageKey(lng) && MSBDStickyPageKey([lng substringToIndex:MSBD_NOTE_PAGE_MAX - 5]).length == MSBD_NOTE_PAGE_MAX, "a key is never longer than the store keeps (200 characters)");
    CHECK(MSBDStickyPageShown(nil, pages) == 0 && MSBDStickyPageShown(MSBDStickyPageKey(p3), pages) == 2 && MSBDStickyPageShown(MSBDStickyPageKey(p2), pages) == 1, "no key: page 1 (every 1.8.8.1 note); a page's key: that page");
    CHECK(MSBDStickyPageShown(MSBDStickyPageKey(@"AAAAAAAA-0000-4000-8000-000000000000"), pages) == 0, "a page that is not shown now (removed, hidden): page 1, its key kept by the caller");
    CHECK(MSBDStickyPageShown(MSBDStickyPageKey(p1), pages) == 0 && MSBDStickyPageShown(MSBDStickyPageKey(p2), @[p2, p1]) == 0, "a note on the page that is first now: page 1");
    CHECK(MSBDStickyPageShown(MSBDStickyPageKey(p2), nil) == 0 && MSBDStickyPageShown(@"display:tv", pages) == 0, "pages not readable here, or a key of another kind: page 1");
    // ---- a hidden page (KT 22 Nov, option A): its notes hide with it, as its icons and widgets do; a removed page's notes still show on page 1 ----
    NSSet *hidden = [NSSet setWithObject:p3]; NSArray *shownNow = @[p1, p2];
    CHECK(MSBDStickyPageOrHidden(MSBDStickyPageKey(p3), shownNow, hidden) == MSBD_NOTE_PAGE_HIDDEN, "a note of a hidden page: shown nowhere (it hides with the page)");
    CHECK(MSBDStickyPageOrHidden(MSBDStickyPageKey(p3), pages, hidden) == 2, "  ... the page shown again: back on it");
    CHECK(MSBDStickyPageOrHidden(MSBDStickyPageKey(@"AAAAAAAA-0000-4000-8000-000000000000"), shownNow, hidden) == 0, "a removed page (neither shown nor hidden): page 1, as before");
    CHECK(MSBDStickyPageOrHidden(MSBDStickyPageKey(p3), shownNow, nil) == 0 && MSBDStickyPageOrHidden(nil, shownNow, hidden) == 0 && MSBDStickyPageOrHidden(MSBDStickyPageKey(p2), shownNow, hidden) == 1,
          "hidden pages not readable here: page 1 (never lost); no key: page 1; a shown page: that page");
    CHECK(MSBDStickyPageOrHidden(MSBDStickyPageKey(p3), @[p1], hidden) == MSBD_NOTE_PAGE_HIDDEN && MSBDStickyPageOrHidden(MSBDStickyPageKey(p3), nil, hidden) == MSBD_NOTE_PAGE_HIDDEN,
          "  ... also with page 1 the only page shown (other pages read as off)");
    // ---- the screen's side ----
    CGFloat W = 1194; CGRect area = CGRectMake(6, 30, 1182, 726);
    CHECK(MSBDStickyEdgeSide(600, W, CGRectGetMinX(area), CGRectGetMaxX(area)) == 0 && MSBDStickyEdgeSide(25, W, 6, 1188) == 0 && MSBDStickyEdgeSide(W - 25, W, 6, 1188) == 0, "a finger inside the screen: no side");
    CHECK(MSBDStickyEdgeSide(24, W, 6, 1188) == -1 && MSBDStickyEdgeSide(0, W, 6, 1188) == -1 && MSBDStickyEdgeSide(W - 24, W, 6, 1188) == 1 && MSBDStickyEdgeSide(W + 5, W, 6, 1188) == 1, "within 24 pt of the left or right side: that side");
    CHECK(MSBDStickyEdgeSide(100, W, 110, 1188) == -1 && MSBDStickyEdgeSide(1100, W, 6, 1090) == 1 && MSBDStickyEdgeSide(120, W, 110, 1188) == 0, "a side Dock: past the free area's side there (over the Dock) is that side");
    CHECK(MSBDStickyEdgeSide(NAN, W, 6, 1188) == 0 && MSBDStickyEdgeSide(0, 50, 6, 44) == 0, "no number, or no screen to speak of: no side");
    CHECK(!MSBDStickyEdgeTurnDue(0.59, 0) && MSBDStickyEdgeTurnDue(0.6, 0) && !MSBDStickyEdgeTurnDue(0.99, 1) && MSBDStickyEdgeTurnDue(1.0, 1) && MSBDStickyEdgeTurnDue(1.0, 3),
          "kept at the side 0.6 s: the page turns; kept there, one more page each 1.0 s");
    // ---- the page a turn goes to (the root folder's indexes: the Today View before the first icon page, the App Library after the last) ----
    CHECK(MSBDStickyTurnTarget(1, 1, 0, 1, 4) == 2 && MSBDStickyTurnTarget(2, -1, 0, 1, 4) == 1, "left to right: the right side is the next page, the left side the one before");
    CHECK(MSBDStickyTurnTarget(1, -1, 0, 1, 4) == -1 && MSBDStickyTurnTarget(4, 1, 0, 1, 4) == -1, "  ... never to the Today View before page 1 nor to the App Library after the last page");
    CHECK(MSBDStickyTurnTarget(1, -1, 1, 1, 4) == 2 && MSBDStickyTurnTarget(2, 1, 1, 1, 4) == 1, "a right-to-left layout: its next page is at the left");
    CHECK(MSBDStickyTurnTarget(0, 1, 0, 0, 0) == -1 && MSBDStickyTurnTarget(0, 0, 0, 0, 3) == -1 && MSBDStickyTurnTarget(2, 1, 0, 3, 1) == -1, "one page, no side, or indexes that make no sense: no turn");
    // ---- every page's notes against the free area it settled at (1.8.8.2, seen on iPadOS 17.5.1) ----
    {   // (a respring: the desktop's first pass against SpringBoard's own Dock figure, the Dock measured 1.3 s on, 4.4 pt taller; the tick looks every 1 s)
        CGRect sbFigure = CGRectMake(6, 41, 1012, 1245.6), measured = CGRectMake(6, 41, 1012, 1241.2), seen = CGRectZero, laid = sbFigure; double seenAt = 0;
        int passAt = -1;
        for (int t = 0; t <= 5; t++) {
            CGRect now = t < 2 ? sbFigure : measured;
            if (MSBDStickyAreaSettled(now, &seen, &seenAt, (double)t, laid)) { if (passAt < 0) passAt = t; laid = now; }
        }
        CHECK(passAt == 3 && CGRectEqualToRect(laid, measured), "the free area changed after a respring (the Dock measured) and held: page 1's pass runs against it, as page 2's notes already follow it");
        seen = CGRectZero; seenAt = 0; laid = sbFigure; passAt = -1;
        for (int t = 0; t <= 6; t++) {   // (a Dock mid animation: another area at every look)
            CGRect now = CGRectMake(6, 41, 1012, 1230.0 + t);
            if (MSBDStickyAreaSettled(now, &seen, &seenAt, t * 0.25, laid)) passAt = t;
        }
        CHECK(passAt < 0, "  ... an area that does not hold (a Dock mid animation): no pass");
        seen = sbFigure; seenAt = 0;
        CHECK(!MSBDStickyAreaSettled(sbFigure, &seen, &seenAt, 9.0, sbFigure) && !MSBDStickyAreaSettled(CGRectZero, &seen, &seenAt, 9.0, sbFigure) && !MSBDStickyAreaSettled(CGRectZero, &seen, &seenAt, 19.0, sbFigure),
              "  ... the area the last pass had, or no area (a desktop not on its page): no pass");
    }
    // ---- where a note that rode a turn lands (1.8.8.2, seen on iPadOS 17.5.1): the page the turn went to, also while the page still slides ----
    CHECK(MSBDStickyDropPage(1, 0, 2) == 1 && MSBDStickyDropPage(0, 1, 2) == 0 && MSBDStickyDropPage(2, 1, 3) == 2,
          "let go after a turn: on the page the last turn went to, whatever page iPadOS's index still answers mid slide (17.5.1: the page being left, 0.70 s after reaching the side)");
    CHECK(MSBDStickyDropPage(-1, 1, 2) == 1 && MSBDStickyDropPage(5, 1, 2) == 1 && MSBDStickyDropPage(2, 0, 2) == 0, "  ... no turn, or the turn's page gone since: the page shown now");
    {   // (the iPadOS 17.5.1 drop replayed: the finger reaches the right side at 0, the turn at 0.6 to 0.7 s (the 0.1 s tick), iPadOS's index still page 1
        //  until about 0.75 s; lifted at 0.70 s: page 1 by the page shown, page 2 by the turn)
        long turned = -1; NSUInteger shownByIndex = 0, landsOld = 0, landsNew = 0;
        for (double t = 0.0; t <= 0.70 + 1e-9; t += 0.1) { if (turned < 0 && MSBDStickyEdgeTurnDue(t, 0)) turned = MSBDStickyTurnTarget(1, 1, 0, 1, 2) - 1; }
        landsOld = shownByIndex; landsNew = MSBDStickyDropPage(turned, shownByIndex, 2);
        CHECK(turned == 1 && landsOld == 0 && landsNew == 1, "  ... 17.5.1: lifted 0.70 s after reaching the side, the turn already made: page 2 (the page shown now said page 1)");
    }
    // ---- Move to Page turns the Home Screen to the note's page (KT 22 Nov): the folder's index of that icon page, never the Today View or the App Library ----
    CHECK(MSBDStickyPageTurnIndex(0, 3, 1, 3) == 1 && MSBDStickyPageTurnIndex(2, 3, 1, 3) == 3 && MSBDStickyPageTurnIndex(1, 3, 0, 2) == 1, "Move to Page: page 1, 3 (a Today View page before page 1) and 2 (none): the folder's own index of that page");
    CHECK(MSBDStickyPageTurnIndex(3, 3, 1, 3) == -1 && MSBDStickyPageTurnIndex(-1, 3, 1, 3) == -1, "  ... no page past the last or before the first (never the App Library or the Today View)");
    CHECK(MSBDStickyPageTurnIndex(1, 3, 1, 4) == -1 && MSBDStickyPageTurnIndex(1, 3, 1, 2) == -1 && MSBDStickyPageTurnIndex(0, 0, 0, -1) == -1 && MSBDStickyPageTurnIndex(0, 2, -1, 0) == -1,
          "  ... the folder counting other pages than were read (a hidden page, a page made meanwhile), or no indexes: no turn");
    // ---- 30 notes in total over every page (the store's cap: MSBD_NOTES_MAX, test-stickystore) ----
    CHECK(MSBD_NOTES_MAX == 30, "30 notes in total, over every page");
    printf("test-stickypages: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
} }
