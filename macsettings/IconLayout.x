// IconLayout.x -- keeps Home Screen icons on the screen in portrait when the icon layout only fits landscape (built into MacPageDots).
//
// Why: Atria (me.lau.atria) has ONE set of Home Screen layout numbers for both orientations. The owner's first page is tuned in landscape
// (offset -463, column spacing -325, insets 200): in landscape the icons sit in two neat columns near the left edge, but in portrait the
// same numbers put the columns on top of each other, half off the left edge (M1, iOS 15, 2026-09-24: icon x = 18, -8, -36, ... -170).
// Atria has no per-orientation settings, so this cannot be fixed in its settings without spoiling landscape.
// What: every time an icon list lays out in landscape, each icon's position is remembered (by icon identifier, also saved to a small
// cache file so a respring in portrait works). When the same list lays out in portrait and an icon would end up (partly) off the screen,
// the landscape positions are used instead -- the page then looks the same in both orientations, which is what the landscape tuning
// intended. Lists that fit in portrait are never touched, so ordinary layouts (and other users) are unaffected. Not while editing
// (jiggle mode), so dragging icons keeps SpringBoard's own positions. Kill switch: /tmp/macsettings-noiconfix. Debug log: /tmp/macsettings.log.
#import <UIKit/UIKit.h>
#if DEBUG
#define MSTestFlag(path) (access((path), F_OK) == 0)   // a /tmp test switch (debug builds only; a release build behaves as if none existed)
#else
#define MSTestFlag(path) 0
#endif
#import <unistd.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>

static void ILMLog(NSString *line) {   // (debug builds only: release builds write no /tmp log)
#if DEBUG
    if (!MSTestFlag("/tmp/macsettings-debug")) return;
    FILE *f = fopen("/tmp/macsettings.log", "a"); if (!f) return;
    fprintf(f, "%s\n", line.UTF8String); fclose(f);
#endif
}

@interface SBIconListView : UIView
- (long long)layoutOrientation;
- (NSArray *)icons;
@end
@interface SBIconView : UIView
- (id)icon;
@end

static NSString *const kILCachePath = @"/var/mobile/Library/Caches/com.besiktasliseba.macsettings.landscapeicons.plist";
static NSMutableDictionary<NSString *, NSString *> *gILLandscape;   // icon identifier -> NSStringFromCGPoint(center) in landscape

static void ILLoad(void) {
    if (gILLandscape) return;
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kILCachePath];
    gILLandscape = d ? [d mutableCopy] : [NSMutableDictionary dictionary];
}
static void ILSave(void) {
    static BOOL pending = NO;
    if (pending) return;
    pending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        pending = NO;
        [gILLandscape writeToFile:kILCachePath atomically:YES];
    });
}
static NSString *ILIdentifier(UIView *iconView) {
    id icon = [iconView respondsToSelector:@selector(icon)] ? [(SBIconView *)iconView icon] : nil;
    for (NSString *key in @[@"uniqueIdentifier", @"nodeIdentifier", @"applicationBundleID"]) {
        SEL sel = NSSelectorFromString(key);
        if ([icon respondsToSelector:sel]) {
            id v = ((id (*)(id, SEL))objc_msgSend)(icon, sel);
            if ([v isKindOfClass:[NSString class]] && [v length]) return v;
        }
    }
    return nil;
}
static BOOL ILEditing(UIView *list) {
    SEL sel = NSSelectorFromString(@"isEditing");
    return [list respondsToSelector:sel] && ((BOOL (*)(id, SEL))objc_msgSend)(list, sel);
}
static Class ILIconViewClass(void) { static Class c; if (!c) c = objc_getClass("SBIconView"); return c; }

static void ILAfterLayout(UIView *list) {
    if (MSTestFlag("/tmp/macsettings-noiconfix")) return;
    if (!list.window || list.bounds.size.width < 100 || ILEditing(list)) return;
    NSString *cls = NSStringFromClass([list class]);
    if (![cls isEqualToString:@"SBIconListView"]) return;   // (the Dock's and folders' lists are left alone)
    long long o = [list respondsToSelector:@selector(layoutOrientation)] ? [(SBIconListView *)list layoutOrientation] : 0;
    ILLoad();
    Class iconViewClass = ILIconViewClass();
    if (o == 3 || o == 4) {   // landscape: remember where each icon is
        BOOL changed = NO;
        for (UIView *iv in list.subviews) {
            if (![iv isKindOfClass:iconViewClass] || iv.hidden) continue;
            NSString *ident = ILIdentifier(iv); if (!ident) continue;
            NSString *c = NSStringFromCGPoint(iv.center);
            if (![gILLandscape[ident] isEqualToString:c]) { gILLandscape[ident] = c; changed = YES; }
        }
        if (changed) ILSave();
        return;
    }
    if (o != 1 && o != 2) return;
    CGFloat w = list.bounds.size.width, h = list.bounds.size.height;
    BOOL off = NO;
    for (UIView *iv in list.subviews) {
        if (![iv isKindOfClass:iconViewClass] || iv.hidden) continue;
        CGRect f = iv.frame;
        if (f.origin.x < -1 || CGRectGetMaxX(f) > w + 1) { off = YES; break; }
    }
    if (!off) return;
    int moved = 0, missing = 0;
    for (UIView *iv in list.subviews) {
        if (![iv isKindOfClass:iconViewClass] || iv.hidden) continue;
        NSString *ident = ILIdentifier(iv);
        NSString *c = ident ? gILLandscape[ident] : nil;
        if (!c) { missing++; continue; }
        CGPoint p = CGPointFromString(c);
        CGSize s = iv.bounds.size;
        p.x = MIN(MAX(p.x, s.width / 2), w - s.width / 2);   // (always fully on the screen)
        p.y = MIN(MAX(p.y, s.height / 2), h - s.height / 2);
        if (!CGPointEqualToPoint(iv.center, p)) { iv.center = p; moved++; }
    }
    if (moved || missing) ILMLog([NSString stringWithFormat:@"[iconlayout] portrait list %p: %d icon(s) moved to their landscape places, %d without one", list, moved, missing]);
}

// Atria + a respring: only the top 4 icons of the first page showed until the screen was touched or turned (the owner saw it before any tweak
// of ours was installed, so it is Atria's). Cause, read on the M1 (iPadOS 15, 2026-09-25): right after a respring SpringBoard marks only rows
// 0-1 of the page as visible (visibleRowRange {0, 2}: 4 icon views for 15 icons) -- its guess from the stock grid, which Atria's squeezed
// layout does not follow. After a swipe it marks every row visible ({0, NSUIntegerMax}) and all icons appear. So, once per list and only
// while Atria is loaded: a moment after the list first lays out, if it shows fewer icon views than it has icons and a partial row range,
// it gets the same "every row visible" SpringBoard itself sets after a swipe, and lays out once. Nothing keeps running; later scrolls and turns
// are SpringBoard's as before. Kill switch (debug builds): /tmp/macsettings-norowfix.
static BOOL ILAtriaLoaded(void) {
    static int loaded = -1;
    if (loaded < 0) {
        loaded = 0;
        for (uint32_t i = 0; i < _dyld_image_count(); i++) { const char *n = _dyld_get_image_name(i); if (n && strstr(n, "/Atria.dylib")) { loaded = 1; break; } }
    }
    return loaded == 1;
}
static void ILShowAllRows(UIView *list, NSString *when) {
    if (!list || !list.window || MSTestFlag("/tmp/macsettings-norowfix") || ILEditing(list)) return;
    SEL getSel = NSSelectorFromString(@"visibleRowRange"), setSel = NSSelectorFromString(@"setVisibleRowRange:"), shownSel = NSSelectorFromString(@"numberOfDisplayedIconViews");
    if (![list respondsToSelector:getSel] || ![list respondsToSelector:setSel] || ![list respondsToSelector:shownSel]) return;
    NSRange rows = ((NSRange (*)(id, SEL))objc_msgSend)(list, getSel);
    if (rows.length == 0 || rows.length == NSUIntegerMax) return;   // (not the page on screen, or already every row)
    NSUInteger shown = ((NSUInteger (*)(id, SEL))objc_msgSend)(list, shownSel), count = 0;
    @try { count = [[list valueForKey:@"icons"] count]; } @catch (id e) { return; }
    if (shown >= count) return;
    ((void (*)(id, SEL, NSRange))objc_msgSend)(list, setSel, NSMakeRange(0, NSUIntegerMax));
    SEL layoutSel = NSSelectorFromString(@"layoutIconsIfNeeded");
    if ([list respondsToSelector:layoutSel]) ((void (*)(id, SEL))objc_msgSend)(list, layoutSel);
    NSUInteger after = ((NSUInteger (*)(id, SEL))objc_msgSend)(list, shownSel);
    ILMLog([NSString stringWithFormat:@"[iconlayout] %@: list %p showed %lu of %lu icons (rows %@): every row marked visible, now %lu", when, list, (unsigned long)shown, (unsigned long)count, NSStringFromRange(rows), (unsigned long)after]);
}
static void ILScheduleRowCheck(UIView *list) {
    static NSHashTable *seen; if (!seen) seen = [NSHashTable weakObjectsHashTable];
    if ([seen containsObject:list] || !ILAtriaLoaded() || ![NSStringFromClass([list class]) isEqualToString:@"SBIconListView"]) return;
    [seen addObject:list];
    __weak UIView *weakList = list;
    for (NSNumber *t in @[@1.0, @3.0])   // (twice: the first layouts after a respring come before SpringBoard settles its guess)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(t.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ ILShowAllRows(weakList, [NSString stringWithFormat:@"%.0f s after the first layout", t.doubleValue]); });
}

// (Phase 2b: after a turn to portrait SpringBoard lays the icons out through the animator variant, and the animation's end frames undid the
// correction -- seen after several turns: icons half off the left edge again. So every layout entry point is covered, and a portrait list is
// checked once more after the animation had time to finish.)
static void ILCheckSoon(UIView *list) {
    static NSHashTable *pending; if (!pending) pending = [NSHashTable weakObjectsHashTable];
    if ([pending containsObject:list]) return;
    [pending addObject:list];
    __weak UIView *weakList = list;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIView *l = weakList; if (!l) return;
        [pending removeObject:l];
        ILAfterLayout(l);
    });
}
%hook SBIconListView
- (void)layoutIconsIfNeededWithAnimationType:(long long)type options:(unsigned long long)options {
    %orig;
    ILAfterLayout(self);
    ILCheckSoon(self);
}
- (void)layoutIconsIfNeededUsingAnimator:(id)animator options:(unsigned long long)options {
    %orig;
    ILAfterLayout(self);
    ILCheckSoon(self);
}
- (void)layoutIconsNow {
    %orig;
    ILAfterLayout(self);
    ILCheckSoon(self);
}
- (void)layoutSubviews {
    %orig;
    ILAfterLayout(self);
    ILScheduleRowCheck(self);
}
%end
