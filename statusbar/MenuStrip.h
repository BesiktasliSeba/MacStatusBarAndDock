// statusbar/MenuStrip.h -- Scroll Menus That Don't Fit (1.8.8.2), SpringBoard's side. Included by StatusBar.x before the bar's layout hook; the
// layout (-dm_layoutLogoBody) calls DMStripLayout once the rule of the bar's two ends (common/BarEnds.h) has laid the titles out. The numbers:
// common/MenuStrip.h (plain C, Mac-tested: tools/test-menustrip.sh; the real layout with this code: tools/test-barends.sh).
//
// When: Settings > Status Bar > Scroll Menus That Don't Fit on (gScrollMenus: on unless switched off), an app in front showing its own menus (Show
// Apps' Own Menus), and the two ends' rule left one or more of them out (a narrow bar in portrait, a larger Menu Bar Size, many status icons).
// Then the titles between the app's name and our Go -- File, Edit and the app's own -- are a strip: whole titles from its first one, a chevron at
// each cut edge, our Go, Window, Display and Audio at a fixed place after it. Anywhere else (room for every title, the switch off, our Finder, the
// Lock Screen) this does nothing and the bar is exactly as before.
// How it moves: a finger swiped sideways on it (fingers only: the pointer's click and drag stays a click), a trackpad's two-finger scroll and a mouse
// wheel over it, and a click or tap on a chevron (the next or the previous page; an assistive feature uses the chevrons as buttons too, "More
// Menus" and "Previous Menus"). Never while one of our menus is open on that screen: no title moves under an open menu (F-7, AppMenus.h
// DMAMTitlesToLay), and a touch then goes to the menu's catch-all as before. Each display's bar is its own (the iPad's, the TV's: B69): where the
// strip of each starts is kept per display, for the app in front there, until another app comes to the front, one with a strip or not (back
// at its start).
// The bar's region actions (iPadOS's Notification Center and Control Center from the bar) never start in the strip's room: it is ours
// (StatusBar.x DMPointOverOurControl), as the titles are.
#include "../common/MenuStrip.h"

#ifndef MSBD_STRIP_REFUSED
#define MSBD_STRIP_REFUSED(fg, in)   // (the Mac test's look at a strip refused for its room: tools/test-barends.m; nothing here)
#endif

// Per display (0 the iPad's own bars, 1 another display's): the app the strip was last moved for, and the title it starts with (nil: the start).
static NSString *gStripBundle[2], *gStripFirst[2];

// A copy's strip as its last layout made it (kStripStateKey; none while the bar has no strip): what the gestures and the chevrons move.
@interface DMStripState : NSObject {
@public
    MSBDStripIn in;
    int first, count, display;
    BOOL rtl, ours;   // (ours: our Go, Window, Display and Audio are titles of the strip too -- no room beside it for them)
    CGFloat k;
}
@property (nonatomic, copy) NSArray<NSString *> *names;
@property (nonatomic, copy) NSString *bundle;
@end
@implementation DMStripState
@end

// The chevron's picture: pointing toward the leading edge before the titles, the trailing edge after them (right to left: mirrored).
static UIImage *DMStripChevronImage(UIFont *font, BOOL pointsLeft) {
    static NSMutableDictionary<NSString *, UIImage *> *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    CGFloat pt = MAX(6.0, round(font.pointSize * 0.85));
    NSString *key = [NSString stringWithFormat:@"%.1f/%d", pt, pointsLeft];
    UIImage *img = cache[key];
    if (!img) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:pt weight:UIImageSymbolWeightSemibold];
        img = [[UIImage systemImageNamed:pointsLeft ? @"chevron.left" : @"chevron.right" withConfiguration:cfg] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        if (img) { if (cache.count > 16) [cache removeAllObjects]; cache[key] = img; }
    }
    return img;
}
static CGFloat DMStripChevronWidth(UIFont *font) { UIImage *i = DMStripChevronImage(font, YES); return i ? ceil(i.size.width) : ceil(font.pointSize * 0.6); }

static void DMStripPage(UIView *fg, int dir);
// One chevron (before the titles, or after them): its picture and its button, whose touch area reaches 8 pt x k either side as a title's does.
__attribute__((noinline)) static void DMStripChevron(UIView *fg, BOOL rtl, BOOL before, BOOL show, CGFloat x, CGFloat midY, CGFloat k, UIFont *font) {
    const void *iconKey = before ? kStripPrevIconKey : kStripNextIconKey, *buttonKey = before ? kStripPrevButtonKey : kStripNextButtonKey;
    UIImageView *icon = objc_getAssociatedObject(fg, iconKey);
    UIButton *btn = objc_getAssociatedObject(fg, buttonKey);
    if (!show) { icon.hidden = YES; btn.hidden = YES; return; }
    UIImage *img = DMStripChevronImage(font, before != rtl);
    if (!img) { icon.hidden = YES; btn.hidden = YES; return; }
    if (!icon) {
        icon = [UIImageView new];
        icon.userInteractionEnabled = NO;
        icon.isAccessibilityElement = NO;   // (its button is the element)
        [fg addSubview:icon];
        objc_setAssociatedObject(fg, iconKey, icon, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DMAXButton *b = [DMAXButton buttonWithType:UIButtonTypeCustom];
        b.pointerInteractionEnabled = DMButtonPointerEffects();   // (iPadOS's highlight only with its own pointer, as the titles')
        b.accessibilityLabel = before ? @"Previous Menus" : @"More Menus";
        b.accessibilityHint = before ? @"Shows the menus before these." : @"Shows the menus after these.";
        __weak UIView *weakFg = fg;
        int dir = before ? -1 : 1;
        [b addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { UIView *f = weakFg; if (f) DMStripPage(f, dir); }] forControlEvents:UIControlEventTouchUpInside];
        [fg addSubview:b];
        objc_setAssociatedObject(fg, buttonKey, b, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        btn = b;
    }
    if (icon.image != img) icon.image = img;
    CGSize s = img.size;
    icon.frame = DMBarRect(fg, rtl, CGRectMake(x, round(midY + kTitleDrop * k - s.height / 2.0), s.width, s.height));
    btn.frame = DMBarRect(fg, rtl, CGRectMake(x - 8.0 * k, 0, s.width + 16.0 * k, DMBarCopyHeight(fg)));
    icon.hidden = btn.hidden = NO;
    [fg bringSubviewToFront:icon];
    [fg bringSubviewToFront:btn];
}

// No strip on this copy (any more): the chevrons go, the record with them.
__attribute__((noinline)) static void DMStripOff(UIView *fg) {
    if (!objc_getAssociatedObject(fg, kStripStateKey) && !objc_getAssociatedObject(fg, kStripPrevIconKey)) return;
    const void *keys[] = { kStripPrevIconKey, kStripPrevButtonKey, kStripNextIconKey, kStripNextButtonKey };
    for (unsigned i = 0; i < sizeof keys / sizeof keys[0]; i++) ((UIView *)objc_getAssociatedObject(fg, keys[i])).hidden = YES;
    if (objc_getAssociatedObject(fg, kStripStateKey) && DMTestFlag("/tmp/macstatusbar-debug")) DMLog([NSString stringWithFormat:@"[menustrip] %p: no strip", fg]);
    objc_setAssociatedObject(fg, kStripStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Whether p (in the copy's own coordinates) lies in its strip's room, the chevrons' touch areas included. Never on a copy laid out locked or
// collapsing (its chevrons hidden there by DMHideAppBarItemsOf; the narrow layout ends the strip, DMStripOff).
__attribute__((noinline)) static BOOL DMStripInRoom(UIView *fg, CGPoint p) {
    DMStripState *st = objc_getAssociatedObject(fg, kStripStateKey);
    if (!st || p.y < 0.0 || p.y > fg.bounds.size.height || fg.bounds.size.width < 300.0 || [objc_getAssociatedObject(fg, kBarLookLockedKey) boolValue]) return NO;
    CGFloat lead = st->rtl ? fg.bounds.size.width - p.x : p.x;
    return lead >= st->in.start - 8.0 * st->k && lead <= st->in.end + 8.0 * st->k;
}

// Our titles after the app's, as the bar lays them (the same rules as the room kept for them, AppMenus.h's reserve in -dm_layoutLogoBody): Go
// always, Window while windowing, Display while a display is connected, Audio while something plays. Bit 0 Go, 1 Window, 2 Display, 3 Audio.
static int DMStripOursWanted(void) {
    return 1 | ((DMActiveEngine() != DMEngineNone || DMSMEngine() || DMNativeActiveApp()) ? 2 : 0) | (DMDispMenuWanted() ? 4 : 0) | (gAudioTabShown ? 8 : 0);
}
// A title's keys and what its tap opens: our Edit, Go, Window, Display, Audio (NO: one of the app's own, in a slot).
static BOOL DMStripTitleKeys(NSString *t, const void **lk, const void **bk, const void **pk, void (^*tap)(UIButton *)) {
    if ([t isEqualToString:kMSBDAppMenuEdit]) { *lk = kEditLabelKey; *bk = kEditButtonKey; *pk = kEditPillKey; *tap = ^(UIButton *b) { DMLog(@"[editbutton] tapped"); DMOpenEditMenu(b); }; return YES; }
    if ([t isEqualToString:@"Go"]) { *lk = kGoLabelKey; *bk = kGoButtonKey; *pk = kGoPillKey; *tap = ^(UIButton *b) { DMLog(@"[gobutton] tapped"); DMOpenGoMenu(b); }; return YES; }
    if ([t isEqualToString:@"Window"]) { *lk = kWinLabelKey; *bk = kWinButtonKey; *pk = kWinPillKey; *tap = ^(UIButton *b) { DMLog(@"[winbutton] tapped"); DMOpenWindowMenu(b); }; return YES; }
    if ([t isEqualToString:@"Display"]) { *lk = kDispLabelKey; *bk = kDispButtonKey; *pk = kDispPillKey; *tap = ^(UIButton *b) { DMLog(@"[dispbutton] tapped"); DMDispMenuOpen(b); }; return YES; }
    if ([t isEqualToString:@"Audio"]) { *lk = kAudioLabelKey; *bk = kAudioButtonKey; *pk = kAudioPillKey; *tap = ^(UIButton *b) { DMLog(@"[audiobutton] tapped"); DMOpenAudioMenu(b); }; return YES; }
    return NO;
}

static void DMStripAttach(UIView *fg);
// The strip, laid out after the two ends' rule laid the titles out (appRight: the app's name's end; stripEnd: where the room kept for our own titles
// starts, titleMaxRight less it; titleMaxRight: the titles' end). amShown, the app's own titles shown, in their slots' order, is made again here.
// No room for a strip beside ours (a narrow bar at a larger size, a long app name with the traffic lights, many of ours, many icons): ours join it,
// every title after the app's name scrolls, nothing is left out. Not even room for that: the two ends' rule as it is.
// YES: the strip is in use, and leftEnd is the titles' new end (our last title's, or the strip's). NO: nothing changed (the chevrons hidden, if any).
__attribute__((noinline)) static BOOL DMStripLayout(UIView *fg, BOOL rtl, UIFont *timeFont, CGFloat centreY, CGFloat k, NSString *bundle, int display,
                                                    NSArray<NSString *> *amWant, NSMutableArray<NSString *> *amShown, CGFloat appRight,
                                                    CGFloat stripEnd, CGFloat titleMaxRight, CGFloat *leftEnd) {
    // (the place is the app in front's: another app at the front of this display, with a strip or without one -- every title fits, or it has no
    //  menus of its own --, and the strip starts again from its first title. 1.8.8.2: reset only where a strip was laid out, so Safari came back
    //  where it was left after Clock, on iPadOS 17.5.1. The Home Screen and our Finder, no app's titles, keep it)
    if (bundle.length && display >= 0 && display <= 1 && ![gStripBundle[display] isEqualToString:bundle]) { gStripBundle[display] = [bundle copy]; gStripFirst[display] = nil; }
    if (!gScrollMenus || !bundle.length || appRight <= 0 || !amWant.count || amShown.count >= amWant.count || display < 0 || display > 1) { DMStripOff(fg); return NO; }
    NSMutableArray<NSString *> *names = [NSMutableArray array];   // (the strip's titles: File before our Edit, the app's others after it)
    if ([amWant containsObject:kMSBDAppMenuFile]) [names addObject:kMSBDAppMenuFile];
    [names addObject:kMSBDAppMenuEdit];
    for (NSString *t in amWant) if (![t isEqualToString:kMSBDAppMenuFile] && ![t isEqualToString:kMSBDAppMenuEdit] && names.count < kMSBDStripMax) [names addObject:t];
    MSBDStripIn in;
    memset(&in, 0, sizeof in);
    in.n = (int)names.count;
    for (int i = 0; i < in.n; i++) in.w[i] = DMAMTitleWidth(names[i], timeFont);
    in.gap = kTitleGap * k; in.chev = DMStripChevronWidth(timeFont); in.minShown = kTitleMinShown;
    in.start = appRight + kTitleGap * k; in.end = stripEnd;
    BOOL withOurs = NO;
    if (!MSBDStripRoomOK(&in)) {   // (no room beside ours: ours in the strip, to the titles' end)
        int want = DMStripOursWanted();
        NSArray<NSString *> *ourNames = @[@"Go", @"Window", @"Display", @"Audio"];
        for (int i = 0; i < 4; i++) if (((want >> i) & 1) && names.count < kMSBDStripMax) [names addObject:ourNames[i]];
        in.n = (int)names.count;
        for (int i = 0; i < in.n; i++) in.w[i] = DMAMTitleWidth(names[i], timeFont);
        in.end = titleMaxRight;
        if (!MSBDStripRoomOK(&in)) { MSBD_STRIP_REFUSED(fg, &in); DMStripOff(fg); return NO; }   // (too little room even for that: the two ends' rule as it is)
        withOurs = YES;
    }
    DM_FEATURE_MARK("scroll-menus");
    NSUInteger at = gStripFirst[display] ? [names indexOfObject:gStripFirst[display]] : 0;
    MSBDStripOut o = MSBDStripAt(&in, at == NSNotFound ? 0 : (int)at);
    // the titles shown, whole (the first one cut short only when it alone is wider than the room); the others hidden with their highlights
    NSMutableSet<NSString *> *shown = [NSMutableSet set];
    [amShown removeAllObjects];
    for (int j = 0; j < o.count; j++) {
        NSString *t = names[o.first + j];
        // (a whole title is laid out whole however close to the titles' end it ends: DMLayoutTitle's least room, kTitleMinShown, is for a title
        //  cut short -- Go, 19 pt, the strip's last title with no window engine, else hid there and could not be reached from any page)
        CGFloat x = o.x[j], maxRight = (j == o.count - 1 && o.lastW < in.w[o.first + j]) ? x + o.lastW : MAX(titleMaxRight, x + kTitleMinShown);
        const void *lk = NULL, *bk = NULL, *pk = NULL; void (^tap)(UIButton *) = nil;
        if (DMStripTitleKeys(t, &lk, &bk, &pk, &tap)) {
            if (DMLayoutTitle(fg, rtl, lk, bk, pk, t, UIFontWeightRegular, timeFont, centreY, x, maxRight, tap) > 0) [shown addObject:t];
        } else {
            NSUInteger slot = amShown.count;
            if (slot >= kMSBDAppMenuSlots) break;
            if (DMLayoutTitle(fg, rtl, &gAMLabelKeys[slot], &gAMButtonKeys[slot], &gAMPillKeys[slot], t, UIFontWeightRegular, timeFont, centreY, x, maxRight,
                              ^(UIButton *b) { DMOpenAppOwnMenu(b); }) > 0) [amShown addObject:t];
        }
    }
    for (NSString *t in withOurs ? @[kMSBDAppMenuEdit, @"Go", @"Window", @"Display", @"Audio"] : @[kMSBDAppMenuEdit]) {   // (ours the strip does not show now)
        const void *lk = NULL, *bk = NULL, *pk = NULL; void (^tap)(UIButton *) = nil;
        if ([shown containsObject:t] || !DMStripTitleKeys(t, &lk, &bk, &pk, &tap)) continue;
        ((UIView *)objc_getAssociatedObject(fg, lk)).hidden = YES;
        ((UIView *)objc_getAssociatedObject(fg, bk)).hidden = YES;
        ((UIView *)objc_getAssociatedObject(fg, pk)).hidden = YES;
    }
    DMStripChevron(fg, rtl, YES, o.prev, o.prevX, centreY, k, timeFont);
    DMStripChevron(fg, rtl, NO, o.next, o.nextX, centreY, k, timeFont);
    CGFloat end = o.next ? o.nextX + in.chev : (o.count ? o.x[o.count - 1] + o.lastW : in.start);
    if (!withOurs) {
        // ours after the strip, where the room kept for them starts: the same place whichever titles the strip shows (each as the two ends' rule
        // laid it out: shown, or not wanted)
        const void *ours[4][3] = { { kGoLabelKey, kGoButtonKey, kGoPillKey }, { kWinLabelKey, kWinButtonKey, kWinPillKey },
                                   { kDispLabelKey, kDispButtonKey, kDispPillKey }, { kAudioLabelKey, kAudioButtonKey, kAudioPillKey } };
        CGFloat x = in.end + in.gap;
        for (int i = 0; i < 4; i++) {
            UILabel *l = objc_getAssociatedObject(fg, ours[i][0]);
            if (!l || l.hidden || !l.text.length) continue;
            CGFloat r = DMLayoutTitle(fg, rtl, ours[i][0], ours[i][1], ours[i][2], l.text, UIFontWeightRegular, timeFont, centreY, x, titleMaxRight, ^(UIButton *b) {});
            if (r > 0) { end = r; x = r + in.gap; }
        }
    }
    DMStripState *was = objc_getAssociatedObject(fg, kStripStateKey), *st = [DMStripState new];
    st->in = in; st->first = o.first; st->count = o.count; st->display = display; st->rtl = rtl; st->k = k; st->ours = withOurs;
    st.names = names; st.bundle = bundle;
    if ((!was || was->first != st->first || was->count != st->count || ![was.names isEqualToArray:names]) && DMTestFlag("/tmp/macstatusbar-debug"))
        DMLog([NSString stringWithFormat:@"[menustrip] %p: %@ shows %@ of %@ (room %.1f..%.1f, chevrons %d %d)", fg, bundle,
               [[names subarrayWithRange:NSMakeRange(o.first, o.count)] componentsJoinedByString:@" "], [names componentsJoinedByString:@" "], in.start, in.end, o.prev, o.next]);
    objc_setAssociatedObject(fg, kStripStateKey, st, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DMStripAttach(fg);
    if (leftEnd) *leftEnd = withOurs ? in.end : end;   // (ours in the strip: its whole room, the same from every page, so the date does not come and go as it moves)
    return YES;
}

// The strip's titles' labels (ours and the app's own slots), for the slide.
static NSArray<UILabel *> *DMStripLabels(UIView *fg) {
    NSMutableArray *a = [NSMutableArray array];
    const void *keys[] = { kEditLabelKey, kGoLabelKey, kWinLabelKey, kDispLabelKey, kAudioLabelKey };
    for (unsigned i = 0; i < sizeof keys / sizeof keys[0]; i++) { UILabel *l = objc_getAssociatedObject(fg, keys[i]); if (l) [a addObject:l]; }
    for (unsigned i = 0; i < kMSBDAppMenuSlots; i++) { UILabel *l = objc_getAssociatedObject(fg, &gAMLabelKeys[i]); if (l) [a addObject:l]; }
    return a;
}
// After a move: a title that stays slides from where it was (inside the strip's room both times, so over nothing else); one that comes in fades
// in once the slide is over (so nothing slides over it); one that goes is gone at once. Reduce Motion: no slide, the titles fade in.
static void DMStripSlide(UIView *fg, NSDictionary<NSString *, NSValue *> *was) {
    BOOL still = MSBReduceMotion();
    for (UILabel *l in DMStripLabels(fg)) {
        if (l.hidden || !l.text.length) continue;
        NSValue *old = was[l.text];
        if (old && !still) {
            CGFloat dx = CGRectGetMidX(old.CGRectValue) - CGRectGetMidX(l.frame);
            if (fabs(dx) < 0.5) continue;
            CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"position.x"];
            a.fromValue = @(dx); a.toValue = @0.0; a.additive = YES; a.duration = 0.16;
            a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            [l.layer addAnimation:a forKey:nil];
        } else {
            CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"opacity"];
            a.fromValue = @0.0; a.toValue = @1.0; a.duration = 0.12;
            if (!still) { a.beginTime = [l.layer convertTime:CACurrentMediaTime() fromLayer:nil] + 0.12; a.fillMode = kCAFillModeBackwards; }
            [l.layer addAnimation:a forKey:nil];
        }
    }
}
// The strip of this copy from title f: kept for its display and app, the copy laid out again now (the others of that display at their next pass).
__attribute__((noinline)) static void DMStripGo(UIView *fg, int f, NSString *why) {
    DMStripState *st = objc_getAssociatedObject(fg, kStripStateKey);
    if (!st || f < 0 || f >= (int)st.names.count || f == st->first) return;
    UIScreen *ms = [UIScreen mainScreen];
    if (gOverlay && (fg.window.screen ?: ms) == (gOverlay.window.screen ?: ms)) {   // (F-7: no title moves under one of our menus open on its screen, whatever asks)
        DMLog([NSString stringWithFormat:@"[menustrip] %@ (%@): one of our menus is open on its screen: the strip stays", st.bundle, why]);
        return;
    }
    int d = st->display;
    gStripBundle[d] = [st.bundle copy];
    gStripFirst[d] = f > 0 ? st.names[f] : nil;
    NSMutableDictionary<NSString *, NSValue *> *was = [NSMutableDictionary dictionary];
    for (UILabel *l in DMStripLabels(fg)) if (!l.hidden && l.text.length) was[l.text] = [NSValue valueWithCGRect:l.frame];
    [fg setNeedsLayout];
    [fg layoutIfNeeded];
    DMStripSlide(fg, was);
    for (UIView *c in gCopies.allObjects) if (c != fg && (DMExternalScreenOf(c) != nil) == (d == 1)) [c setNeedsLayout];
    DMStripState *now = objc_getAssociatedObject(fg, kStripStateKey);
    DMLog([NSString stringWithFormat:@"[menustrip] %@ (%@): the menus from %@, %d of %lu shown", st.bundle, why, st.names[f], now ? now->count : 0, (unsigned long)st.names.count]);
}
static void DMStripPage(UIView *fg, int dir) {
    // (a chevron used while one of our menus is open: a touch that reached it instead of the menu's catch-all, as a title's can at the top edge in
    //  portrait, or an assistive feature's: as with a title used then (DMTitleTapWithMenuOpen), the menu closes, and nothing moves under it, F-7)
    if (gOverlay) { DMLog(@"[menustrip] a chevron used while a menu is open: the menu closes, the strip stays"); DMCloseOverlay(); return; }
    DMStripState *st = objc_getAssociatedObject(fg, kStripStateKey);
    if (!st) return;
    DMStripGo(fg, dir > 0 ? MSBDStripPageNext(&st->in, st->first) : MSBDStripPagePrev(&st->in, st->first), dir > 0 ? @"the next page" : @"the page before");
}
// A title the bar is asked to open that the strip does not show now (the app's fresh answer, which a title's tap asks for, put another menu before
// it: AppMenus.h DMOpenAppOwnMenu): the strip moves to show it. YES when it shows now. (Any keyboard way to the bar's titles goes through here too:
// none so far -- B57, the arrow keys through our menus, is not built; the assistive features reach the hidden titles by the chevrons.)
__attribute__((noinline)) static BOOL DMStripReveal(UIView *fg, NSString *title) {
    DMStripState *st = objc_getAssociatedObject(fg, kStripStateKey);
    NSUInteger i = st && title ? [st.names indexOfObject:title] : NSNotFound;
    if (i == NSNotFound) return NO;
    int f = MSBDStripReveal(&st->in, st->first, (int)i);
    if (f < 0) return NO;
    if (f != st->first) DMStripGo(fg, f, @"a menu asked to open");
    DMStripState *now = objc_getAssociatedObject(fg, kStripStateKey);
    return now && (int)i >= now->first && (int)i < now->first + now->count;
}
// A swipe or a two-finger scroll that began with title began first has moved by moved points along the strip (leading coordinates).
__attribute__((noinline)) static void DMStripMoved(UIView *fg, int began, double moved) {
    DMStripState *st = objc_getAssociatedObject(fg, kStripStateKey);
    if (st) DMStripGo(fg, MSBDStripFirstAfterMove(&st->in, began, moved), @"a swipe");
}
// A mouse wheel's notch (moved: minus toward the later titles): one title on.
__attribute__((noinline)) static void DMStripWheel(UIView *fg, double moved) {
    DMStripState *st = objc_getAssociatedObject(fg, kStripStateKey);
    if (st && moved != 0.0) DMStripGo(fg, MSBDStripStep(&st->in, st->first, moved < 0.0 ? 1 : -1), @"the wheel");
}
// A movement in the copy's own coordinates along the strip: a finger's sideways only; a scroll's larger one (a wheel turns only up and down),
// sideways in leading coordinates.
static double DMStripAlong(UIView *fg, CGPoint t, BOOL scroll) {
    DMStripState *st = objc_getAssociatedObject(fg, kStripStateKey);
    double x = st && st->rtl ? -t.x : t.x;
    return (!scroll || fabs(t.x) >= fabs(t.y)) ? x : t.y;
}
// Where a swipe or a scroll began, in the copy's own coordinates (asked as it begins). A finger: where it is. A scroll -- a trackpad's two fingers,
// a mouse wheel -- happens where the pointer is, and the pointer stays there: its place over the copy, as the copy's hover sees it (pointerIn: the
// pointer over the copy now; 1.8.8.3). Without it (no pointer over the copy: a scroll sent with no pointer there), as 1.8.8.2: the continuous
// scroll's pan (moving) from its location less its translation -- UIKit moves that pan's location with the scroll, as a finger dragging would
// (iPadOS 17.5.1: a sideways scroll over Go, at 393, asked at 353, inside the strip's room) -- and the wheel's pan from its location. That location
// less the translation was still not where it began: the translation leaves out the pan's first ~10 pt, so a sideways scroll beginning 3 to 7 pt
// past the room's end (Go's button at 373) was read inside it and moved the strip (17.5.1, x 366 and 370 with the room ending at 363).
__attribute__((noinline)) static CGPoint DMStripBeganAt(UIView *fg, UIPanGestureRecognizer *g, BOOL moving, BOOL pointerIn, CGPoint pointerAt) {
    if (pointerIn) return pointerAt;   // (a scroll with the pointer over the copy: where the pointer is)
    CGPoint p = [g locationInView:fg];
    if (!moving) return p;
    CGPoint t = [g translationInView:fg];
    return CGPointMake(p.x - t.x, p.y - t.y);
}
// Whether a swipe or a scroll at p may move the strip: the copy has one, p lies in its room, none of our menus is open on its screen (F-7), not
// locked, and a finger's swipe goes sideways (up and down are iPadOS's pulls from the top). A scroll either way: up and down move it as sideways
// does (as a Mac scrolls a row with a vertical wheel, DMStripAlong).
__attribute__((noinline)) static BOOL DMStripCanBegin(UIView *fg, CGPoint p, CGPoint velocity, BOOL finger) {
    if (!DMStripInRoom(fg, p) || DMBarLockedNow() || fg.hidden || !fg.window) return NO;
    if (!finger) {   // (a scroll: the strip's room itself, not the chevrons' touch areas past its ends, where Go's button begins, 1.8.8.2)
        DMStripState *st = objc_getAssociatedObject(fg, kStripStateKey);
        CGFloat lead = st->rtl ? fg.bounds.size.width - p.x : p.x;
        if (lead < st->in.start || lead > st->in.end) return NO;
    }
    UIScreen *ms = [UIScreen mainScreen];
    if (gOverlay && (fg.window.screen ?: ms) == (gOverlay.window.screen ?: ms)) return NO;
    return !finger || fabs(velocity.x) > fabs(velocity.y);
}

// The gestures on a copy with a strip (made once, the first time it has one): a finger's swipe, a two-finger scroll (trackpad, Magic Mouse) and a
// mouse wheel. They begin only in the strip's room; a touch anywhere else is never looked at.
@interface DMStripHandler : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *fg;
@property (nonatomic, weak) UIPanGestureRecognizer *touch, *swipe, *wheel;
@property (nonatomic, weak) UIHoverGestureRecognizer *hover;
@property (nonatomic) int began;
@property (nonatomic) CFTimeInterval wheelAt;
@property (nonatomic) BOOL pointerIn;     // (the pointer over the copy now, and where: its hover, 1.8.8.3 -- a scroll is judged where it is)
@property (nonatomic) CGPoint pointerAt;
@end
@implementation DMStripHandler
// (the hover beside every other recognizer on the bar -- the traffic lights', the TV bar's auto-hide: it only reads where the pointer is)
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)o { return g == self.hover; }
- (void)hovered:(UIHoverGestureRecognizer *)g {
    UIView *fg = self.fg;
    BOOL in = fg && (g.state == UIGestureRecognizerStateBegan || g.state == UIGestureRecognizerStateChanged);
    self.pointerIn = in;
    if (in) self.pointerAt = [g locationInView:fg];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    // (the hover reads the pointer wherever it comes onto the copy -- past the room too, over Go or the clock, where a scroll must not begin: a
    //  hover is a touch to UIKit, and one refused where it came on is never followed on that visit; review 1.8.8.3)
    if (g == self.hover) return YES;
    UIView *fg = self.fg;
    return fg && DMStripInRoom(fg, [touch locationInView:fg]);
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if (g == self.hover) return YES;   // (the pointer's place, only read)
    UIView *fg = self.fg;
    if (!fg) return NO;
    BOOL finger = g == self.touch;
    CGPoint v = finger ? [(UIPanGestureRecognizer *)g velocityInView:fg] : CGPointZero;
    if (!DMStripCanBegin(fg, DMStripBeganAt(fg, (UIPanGestureRecognizer *)g, g == self.swipe, !finger && self.pointerIn, self.pointerAt), v, finger)) return NO;   // (a scroll: where the pointer is)
    DMStripState *st = objc_getAssociatedObject(fg, kStripStateKey);
    self.began = st ? st->first : 0;
    return YES;
}
- (void)moved:(UIPanGestureRecognizer *)g {
    UIView *fg = self.fg;
    if (!fg || g.state != UIGestureRecognizerStateChanged) return;
    DMStripMoved(fg, self.began, DMStripAlong(fg, [g translationInView:fg], g != self.touch));
}
- (void)notch:(UIPanGestureRecognizer *)g {
    UIView *fg = self.fg;
    if (!fg || (g.state != UIGestureRecognizerStateBegan && g.state != UIGestureRecognizerStateChanged)) return;
    double d = DMStripAlong(fg, [g translationInView:fg], YES);
    if (fabs(d) < 0.5) return;
    [g setTranslation:CGPointZero inView:fg];
    CFTimeInterval now = CACurrentMediaTime();
    if (now - self.wheelAt < 0.08) return;   // (one title a notch, however a notch comes)
    self.wheelAt = now;
    DMStripWheel(fg, d);
}
@end
__attribute__((noinline)) static void DMStripAttach(UIView *fg) {
    if (objc_getAssociatedObject(fg, kStripHandlerKey)) return;
    DMStripHandler *h = [DMStripHandler new];
    h.fg = fg;
    UIPanGestureRecognizer *touch = [[UIPanGestureRecognizer alloc] initWithTarget:h action:@selector(moved:)];
    touch.allowedTouchTypes = @[@(UITouchTypeDirect), @(UITouchTypePencil)];   // (the pointer's click and drag stays a click)
    touch.maximumNumberOfTouches = 1;
    touch.delaysTouchesEnded = NO;   // (a tap on a title ends at once, as before)
    touch.delegate = h;
    UIPanGestureRecognizer *swipe = [[UIPanGestureRecognizer alloc] initWithTarget:h action:@selector(moved:)];
    swipe.allowedTouchTypes = @[];
    swipe.allowedScrollTypesMask = UIScrollTypeMaskContinuous;
    swipe.delegate = h;
    UIPanGestureRecognizer *wheel = [[UIPanGestureRecognizer alloc] initWithTarget:h action:@selector(notch:)];
    wheel.allowedTouchTypes = @[];
    wheel.allowedScrollTypesMask = UIScrollTypeMaskDiscrete;
    wheel.delegate = h;
    UIHoverGestureRecognizer *hover = [[UIHoverGestureRecognizer alloc] initWithTarget:h action:@selector(hovered:)];   // (where the pointer is: a scroll's place)
    hover.cancelsTouchesInView = NO; hover.delaysTouchesBegan = NO; hover.delaysTouchesEnded = NO;   // (it only watches: a click on a title, Go or the clock as before)
    hover.delegate = h;
    [fg addGestureRecognizer:touch]; [fg addGestureRecognizer:swipe]; [fg addGestureRecognizer:wheel]; [fg addGestureRecognizer:hover];
    h.touch = touch; h.swipe = swipe; h.wheel = wheel; h.hover = hover;
    objc_setAssociatedObject(fg, kStripHandlerKey, h, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // (the recognizers hold their target weakly)
}
