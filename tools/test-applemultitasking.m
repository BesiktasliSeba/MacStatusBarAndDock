// Mac test of where Apple keeps its multitasking settings per iPadOS version and how links into them go to our Windows & Multitasking page
// (common/AppleMultitaskingTable.h; 1.6.0).
#import <Foundation/Foundation.h>
#include "../common/AppleMultitaskingTable.h"
static int fails = 0, checks = 0;
static void Check(BOOL ok, NSString *what) { checks++; if (!ok) { fails++; printf("FAIL %s\n", what.UTF8String); } }
static NSArray *Rows(int e) {   // (the rows our page has from an entry, as read on 16.7.7)
    if (e < 0) return @[];
    NSString *page = @(kMSAMSources[e].page);
    if ([page isEqualToString:@"PSGPiPController"]) return @[@"AUTO_PIP", @"ALLOW_PIP"];
    if ([page isEqualToString:@"PSGGesturesController"]) return @[@"MULTITASKING_GESTURES", @"SBUseSystemGestures", @"CORNER_GESTURES", @"ALLOW_FINGER_TO_SWIPE_FROM_CORNER", @"CORNER_SWIPES", @"BOTTOM_LEFT_CORNER_SWIPE", @"BOTTOM_RIGHT_CORNER_SWIPE"];
    return @[];
}
static void Redirect(int os, NSString *page, NSString *path, NSString *wantPage, NSString *wantRow) {
    NSString *row = @"unset";
    int e = MSAMRedirect(os, page, path, ^NSArray<NSString *> *(int i) { return Rows(i); }, &row);
    BOOL ok = wantPage ? (e >= 0 && [@(kMSAMSources[e].page) isEqualToString:wantPage] && [row isEqualToString:wantRow]) : (e == -1 && row == nil);
    Check(ok, [NSString stringWithFormat:@"redirect %d %@ %@ -> entry %d (%s) row %@, want %@ %@", os, page, path, e, e >= 0 ? kMSAMSources[e].page : "-", row, wantPage, wantRow]);
}
int main(void) {
    @autoreleasepool {
        // the table itself: each entry complete for its kind
        for (int i = 0; i < MSAM_SOURCE_COUNT; i++) {
            const MSAMSource *s = &kMSAMSources[i];
            Check(s->os >= 15 && s->page && *s->page, [NSString stringWithFormat:@"entry %d has its version and Apple's page", i]);
            if (s->kind == MSAMRows) {
                Check(s->from && *s->from, [NSString stringWithFormat:@"rows entry %d names Apple's page that leads there", i]);
                Check(MSAMList(s->expect).count > 0, [NSString stringWithFormat:@"rows entry %d says which rows it needs", i]);
                Check(MSAMList(s->fromRows).count > 0, [NSString stringWithFormat:@"rows entry %d says which of Apple's rows go", i]);
                Check(!s->link && !s->linkRow, [NSString stringWithFormat:@"rows entry %d is no link", i]);
            } else {
                Check(s->kind == MSAMLink || s->kind == MSAMPage, [NSString stringWithFormat:@"entry %d: a known kind", i]);
                Check(s->title && *s->title, [NSString stringWithFormat:@"link entry %d has a title for its row", i]);
                Check(!s->from && !s->fromRows && !s->expect && !s->only, [NSString stringWithFormat:@"link entry %d takes nothing of Apple's (Apple's row stays)", i]);
                if (s->kind == MSAMLink) {   // (Apple's own link selects Apple's row of the main list: root=<that row>, nothing after it)
                    Check(s->link && s->linkRow && [@(s->link) isEqualToString:[@"prefs:root=" stringByAppendingString:@(s->linkRow)]], [NSString stringWithFormat:@"link entry %d: its link selects its main-list row", i]);
                } else Check(!s->link && !s->linkRow && s->bundle && *s->bundle, [NSString stringWithFormat:@"page entry %d: Apple's page from its bundle, no link", i]);
            }
        }
        Check(MSAMList(NULL).count == 0 && MSAMList("").count == 0 && [MSAMList("a,,b") isEqualToArray:(@[@"a", @"b"])], @"lists: empty, and empty items left out");
        // per version: 16 has General's two pages, in the order our page shows them; 17 and 18 nothing (SwiftUI pages, no rows); 14 nothing
        NSArray *s16 = MSAMSourcesFor(16);
        Check(s16.count == 2, @"16: two entries");
        Check(s16.count == 2 && !strcmp(kMSAMSources[[s16[0] intValue]].page, "PSGPiPController") && !strcmp(kMSAMSources[[s16[1] intValue]].page, "PSGGesturesController"), @"16: Picture in Picture, then Gestures");
        Check(MSAMSourcesFor(14).count == 0, @"14: nothing");
        // 15 (M1 15.6.1): the same two pages of General as 16, in the same order, taking General's same two rows
        NSArray *s15 = MSAMSourcesFor(15);
        Check(s15.count == 2 && !strcmp(kMSAMSources[[s15[0] intValue]].page, "PSGPiPController") && !strcmp(kMSAMSources[[s15[1] intValue]].page, "PSGGesturesController"), @"15: Picture in Picture, then Gestures");
        for (NSNumber *n in s15) Check(kMSAMSources[n.intValue].kind == MSAMRows && !strcmp(kMSAMSources[n.intValue].from, "PSGGeneralController"), @"15: rows, both from General");
        Check(MSAMSourceTaking(15, @"PSGGeneralController", @"PiP_SPEC") >= 0 && MSAMSourceTaking(15, @"PSGGeneralController", @"GESTURES") >= 0, @"15: General's Picture in Picture and Gestures rows are taken");
        Check(MSAMSourceTaking(15, @"DBSHomeScreenPadListController", @"MULTITASKING_DOCK") == -1 && MSAMSourceTaking(15, @"PSGGeneralController", @"About") == -1, @"15: Home Screen & Dock and General's other rows stay");
        Redirect(15, @"PSGGeneralController", @"GESTURES#ALLOW_FINGER_TO_SWIPE_FROM_CORNER", @"PSGGesturesController", @"ALLOW_FINGER_TO_SWIPE_FROM_CORNER");
        Redirect(15, @"PSGGeneralController", @"PiP_SPEC", @"PSGPiPController", @"AUTO_PIP");
        Redirect(15, @"PSGGeneralController", @"Multitasking_Gesture_Switch", @"PSGGesturesController", @"MULTITASKING_GESTURES");
        // 17 and 18: one row that opens Apple's Multitasking & Gestures page (a SwiftUI page: no rows to show) -- 17 by Apple's own link through Settings'
        // URL handler, selecting Apple's main-list row; 18 (no such handler) Apple's page shown from ours. Nothing of Apple's taken out.
        NSArray *s17 = MSAMSourcesFor(17), *s18 = MSAMSourcesFor(18);
        Check(s17.count == 1 && kMSAMSources[[s17[0] intValue]].kind == MSAMLink, @"17: one link row");
        Check(s18.count == 1 && kMSAMSources[[s18[0] intValue]].kind == MSAMPage, @"18: one page row");
        if (s17.count == 1) {
            const MSAMSource *m = &kMSAMSources[[s17[0] intValue]];
            Check(!strcmp(m->page, "MultitaskingAndGesturesSettings") && !strcmp(m->bundle, "/System/Library/PreferenceBundles/MultitaskingAndGesturesSettings.bundle"), @"17: Apple's page and bundle as read on 17.5");
            Check(!strcmp(m->link, "prefs:root=com.apple.MultitaskingAndGesturesSettings") && !strcmp(m->linkRow, "com.apple.MultitaskingAndGesturesSettings"), @"17: Apple's main-list row com.apple.MultitaskingAndGesturesSettings");
            Check(!strcmp(m->title, "Multitasking & Gestures"), @"17: Apple's title where its row's can't be read");
        }
        if (s18.count == 1) {
            const MSAMSource *m = &kMSAMSources[[s18[0] intValue]];
            Check(!strcmp(m->page, "MultitaskingAndGesturesSettings") && !strcmp(m->bundle, "/System/Library/PreferenceBundles/MultitaskingAndGesturesSettings.bundle"), @"18: Apple's page and bundle as read on 18.5");
            Check(!strcmp(m->title, "Multitasking & Gestures"), @"18: the row's title");
        }
        for (NSString *r in @[@"com.apple.MultitaskingAndGesturesSettings", @"GESTURES", @"PiP_SPEC"]) {
            Check(MSAMSourceTaking(17, @"PSUIPrefsListController", r) == -1 && MSAMSourceTaking(18, @"PSGGeneralController", r) == -1, [NSString stringWithFormat:@"17/18: %@ stays", r]);
        }
        for (NSNumber *n in s16) Check(!strcmp(kMSAMSources[n.intValue].from, "PSGGeneralController"), @"16: both from General");
        // 16: Stage Manager stays on Apple's Home Screen & Multitasking page (not taken: only where Settings itself sees Stage Manager, and with
        // TrollPad Apple's switch reads another key than SpringBoard acts on)
        for (int i = 0; i < MSAM_SOURCE_COUNT; i++) Check(((kMSAMSources[i].page && !strcmp(kMSAMSources[i].page, "DBSMultitaskingContinuousExposeController")) || (kMSAMSources[i].from && !strcmp(kMSAMSources[i].from, "DBSHomeScreenPadListController"))) ? kMSAMSources[i].os != 16 : YES, @"16: no Stage Manager entry");   // (from is NULL for link and page entries: strcmp on it was undefined)
        // which entry takes which of Apple's rows
        Check(MSAMSourceTaking(16, @"PSGGeneralController", @"PiP_SPEC") >= 0, @"16: General's Picture in Picture row is taken");
        Check(MSAMSourceTaking(16, @"PSGGeneralController", @"GESTURES") >= 0, @"16: General's Gestures row is taken");
        Check(MSAMSourceTaking(16, @"PSGGeneralController", @"About") == -1, @"16: General's other rows stay");
        Check(MSAMSourceTaking(16, @"DBSHomeScreenPadListController", @"PiP_SPEC") == -1, @"16: only on General");
        Check(MSAMSourceTaking(17, @"PSGGeneralController", @"GESTURES") == -1, @"17: nothing taken");
        Check(MSAMSourceTaking(16, nil, @"GESTURES") == -1 && MSAMSourceTaking(16, @"PSGGeneralController", nil) == -1, @"nil page or row: nothing");
        // links into them (the path General's page is handed) -> our page, at the row the link names when our page has it, else the entry's first row
        Redirect(16, @"PSGGeneralController", @"GESTURES", @"PSGGesturesController", @"MULTITASKING_GESTURES");
        Redirect(16, @"PSGGeneralController", @"PiP_SPEC", @"PSGPiPController", @"AUTO_PIP");
        Redirect(16, @"PSGGeneralController", @"GESTURES/BOTTOM_LEFT_CORNER_SWIPE", @"PSGGesturesController", @"BOTTOM_LEFT_CORNER_SWIPE");
        Redirect(16, @"PSGGeneralController", @"GESTURES#ALLOW_FINGER_TO_SWIPE_FROM_CORNER", @"PSGGesturesController", @"ALLOW_FINGER_TO_SWIPE_FROM_CORNER");
        Redirect(16, @"PSGGeneralController", @"PiP_SPEC%23ALLOW_PIP", @"PSGPiPController", @"ALLOW_PIP");
        Redirect(16, @"PSGGeneralController", @"GESTURES/NOT_A_ROW", @"PSGGesturesController", @"MULTITASKING_GESTURES");
        Redirect(16, @"PSGGeneralController", @"Multitasking_Gesture_Switch", @"PSGGesturesController", @"MULTITASKING_GESTURES");   // (Settings' own "Gestures" result)
        Check(MSAMSourceTaking(16, @"PSGGeneralController", @"Multitasking_Gesture_Switch") >= 0 && MSAMList(kMSAMSources[MSAMSourceTaking(16, @"PSGGeneralController", @"Multitasking_Gesture_Switch")].fromRows).count == 1,
              @"16: an alias leads to the entry but is not a row taken out");
        Redirect(16, @"PSGGeneralController", @"About", nil, nil);
        Redirect(16, @"PSGGeneralController", @"KEYBOARD/GESTURES", nil, nil);   // (only Apple's row itself, first in the path)
        Redirect(16, @"PSGGeneralController", @"", nil, nil);
        Redirect(16, @"PSGGeneralController", nil, nil, nil);
        Redirect(16, @"PSGGesturesController", @"GESTURES", nil, nil);
        Redirect(17, @"PSGGeneralController", @"GESTURES", nil, nil);
        Redirect(18, @"PSGGeneralController", @"PiP_SPEC", nil, nil);
        // no rows known for the entry (its page not there): the first row it must have
        NSString *row = nil;
        int e = MSAMRedirect(16, @"PSGGeneralController", @"PiP_SPEC", nil, &row);
        Check(e >= 0 && [row isEqualToString:@"AUTO_PIP"], @"without the page's rows: the first row it must have");
    }
    printf("test-applemultitasking: %d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
