// test-dockcolorpage.m -- Settings > Dock > Dock Background's code (1.8.8.1 DOCKCOLOR), run by tools/test-dockcolor.sh (Mac Catalyst). The review of
// DOCKCOLOR found the page checked by its text only: a page that stored nothing passed. Here the page's code runs: the real Dock Background block of
// dock/dockmagnificationprefs/DMRootListController.m (its functions and the colour well's cell, DMDockColorCell) and the list controller's
// -readPreferenceValue: and -setPreferenceValue:specifier:, cut out by the script with the Dock's and Status Bar Background's domains made scratch
// ones (TDP_DOMAIN, TDP_BAR_DOMAIN), on stand-ins for the Preferences framework: each row is its real Root.plist entry, and the controller's own store
// writes the row's key in its domain and posts the row's PostNotification, as PSListController does. With LineSwitch.h's real MSBDNoteSwitch (cut out
// by crashstep-pagescut.py; the part that ends the crash guard's note left out, so the Mac's own note is never read or written: test-menubarsizeguard
// and test-crashstep test it) and the crash guard's real step 1 (CrashGuard.h MSBDGuardSwitchOffRecent) on a scratch list (MSBD_GUARD_RECENT).
// DOCKSLIDER (the 1.8.7.6~b01 pass on all four iPads: the opacity slider moved the Dock only when the finger lifted, PSSliderCell leaves its slider not
// continuous whatever Root.plist says; its "0.70" cut on the iPad 2): the page's real -tableView:cellForRowAtIndexPath: (TDP_CELL) on stand-in slider
// cells as Settings leaves them, with common/SliderCells.h as it is.
#import <UIKit/UIKit.h>
#import <notify.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include "CrashExplain.h"   // (CrashGuard.h: step 1 on the scratch list)
#define MSBD_DOMAIN CFSTR("com.besiktasliseba.macstatusbaranddock")   // (LineSwitch.h's; nothing here reads or writes it)
#include TDP_LINESWITCH_CUT   // (MSBDGuardAction ... MSBDNoteSwitch)
#include "DockColor.h"
#include "SliderCells.h"   // (the page's slider rows: MSBDFitValueLabels, MSBDSliderCellContinuous)
#ifndef kMSBDDockAppLibraryRowID
#define kMSBDDockAppLibraryRowID "SHOW_APP_LIBRARY"   // (DockAppLibrary.h's: Apple's App Library row, in the page's cell method)
#endif
#undef kMSBDBarColorDomain
#define kMSBDBarColorDomain TDP_BAR_DOMAIN

static NSMutableArray<NSString *> *gPosts;   // (what the page posts: the light note, prefsChanged)
static NSMutableArray<NSNumber *> *gPostTimes;   // (when: the light note at most every 0.15 s while dragged)
static uint32_t TNotifyPost(const char *name) { [gPosts addObject:@(name)]; [gPostTimes addObject:@(CFAbsoluteTimeGetCurrent())]; return 0; }
#define notify_post TNotifyPost
static BOOL MSBDMacDockActive(void) { return NO; }

// ---- the Preferences framework, as the page uses it ----
@interface PSSpecifier : NSObject
@property (nonatomic, strong) NSDictionary *item;   // (its Root.plist entry)
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, weak) id target;
- (id)propertyForKey:(NSString *)key;
@end
@implementation PSSpecifier
- (id)propertyForKey:(NSString *)key { return self.item[key]; }
- (NSString *)identifier { return self.item[@"id"]; }
@end
@interface PSTableCell : UITableViewCell
@property (nonatomic, strong) PSSpecifier *specifier;
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid specifier:(PSSpecifier *)specifier;
- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier;
@end
@implementation PSTableCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:rid];
    self.specifier = specifier;
    return self;
}
- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {}
@end
@interface PSSliderCell : PSTableCell   // (as Settings leaves it on iPadOS 15 to 18: its slider not continuous, whatever isContinuous says)
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *value;   // (the value label: the stock cell's, a little narrow for two decimals)
- (id)control;
@end
@implementation PSSliderCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:rid specifier:specifier];
    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 400, 44)];   // (the slider and its label a level down, as in the real cell)
    [self.contentView addSubview:box];
    self.slider = [[UISlider alloc] initWithFrame:CGRectMake(16, 6, 330, 32)];
    self.slider.continuous = NO;
    [box addSubview:self.slider];
    return self;
}
- (void)addValueLabel {   // ("0.70" at the stock size in about the width the iPad 2's 510 pt window gave it)
    self.value = [[UILabel alloc] initWithFrame:CGRectMake(350, 12, 28, 20)];
    self.value.font = [UIFont systemFontOfSize:17];
    self.value.text = @"0.70";
    [self.slider.superview addSubview:self.value];
}
- (id)control { return self.slider; }
@end
@interface PSHonouringSliderCell : PSSliderCell   // (a Settings that does take a row's isContinuous each time it gives the cell a row: not seen on 15 to 18)
@end
@implementation PSHonouringSliderCell
- (void)setSpecifier:(PSSpecifier *)specifier { [super setSpecifier:specifier]; self.slider.continuous = [[specifier propertyForKey:@"isContinuous"] boolValue]; }
@end
static UITableViewCell *gNextCell;   // (the cell Settings hands the page for the next row)
static CFStringRef TDomainOf(PSSpecifier *s) {   // (the row's "defaults", the Dock's domain: the scratch one)
    return [[s propertyForKey:@"defaults"] isEqual:@"com.besiktasliseba.dockmagnification"] ? CFSTR(TDP_DOMAIN) : NULL;
}
@interface PSListController : NSObject
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
- (id)readPreferenceValue:(PSSpecifier *)specifier;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
@end
@implementation PSListController
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath { return gNextCell; }   // (set up for its row)
- (id)readPreferenceValue:(PSSpecifier *)specifier {   // (the stored value, else the row's default)
    CFStringRef d = TDomainOf(specifier);
    if (!d) return nil;
    CFPreferencesSynchronize(d, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPropertyListRef v = CFPreferencesCopyValue((__bridge CFStringRef)[specifier propertyForKey:@"key"], d, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    return v ? CFBridgingRelease(v) : [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {   // (the value into the row's domain, then its PostNotification)
    CFStringRef d = TDomainOf(specifier);
    if (!d) return;
    CFPreferencesSetValue((__bridge CFStringRef)[specifier propertyForKey:@"key"], (__bridge CFPropertyListRef)value, d, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(d, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSString *post = [specifier propertyForKey:@"PostNotification"];
    if (post) notify_post(post.UTF8String);
}
@end
@interface DMRootListController : PSListController
@property (nonatomic, strong) NSMutableArray<NSString *> *reloaded;
@property (nonatomic) int noteGone;
- (void)reloadSpecifierID:(NSString *)identifier animated:(BOOL)animated;
- (void)msbd_guardNoteMaybeGone;
@end

// ---- the page's own code ----
#include TDP_BLOCK
#include TDP_RECENTS
@implementation DMRootListController
- (void)reloadSpecifierID:(NSString *)identifier animated:(BOOL)animated { [self.reloaded addObject:identifier]; }
- (void)msbd_noteSwitch:(id)value specifier:(PSSpecifier *)specifier {}   // (LineSwitch.h's returns for anything but a switch cell: none of these rows is one)
- (void)msbd_guardNoteMaybeGone { self.noteGone++; }
- (void)msbd_appLibrarySwitched:(id)sender {}
#include TDP_CELL
#include TDP_READ
#include TDP_SET
@end
@interface DMDockColorCell (TDP)
- (void)dm_colorChanged;
@end

// ---- the checks ----
static int gFails, gChecks;
static void Check(BOOL ok, NSString *what, NSString *got) {
    gChecks++; if (!ok) gFails++;
    printf("%s  %s%s%s\n", ok ? "PASS" : "FAIL", what.UTF8String, ok || !got ? "" : "\n      got: ", ok || !got ? "" : got.UTF8String);
}
static id Stored(CFStringRef key, CFStringRef domain) {
    CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPropertyListRef v = CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    return v ? CFBridgingRelease(v) : nil;
}
static id Dock(const char *key) { return Stored((__bridge CFStringRef)@(key), CFSTR(TDP_DOMAIN)); }
static void SetDock(const char *key, id v) {
    CFPreferencesSetValue((__bridge CFStringRef)@(key), (__bridge CFPropertyListRef)v, CFSTR(TDP_DOMAIN), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(CFSTR(TDP_DOMAIN), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
static void SetBar(id v) {
    CFPreferencesSetValue(CFSTR("backgroundColor"), (__bridge CFPropertyListRef)v, CFSTR(TDP_BAR_DOMAIN), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(CFSTR(TDP_BAR_DOMAIN), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
static void Automatic(void) { SetDock(kMSBDDockBackgroundKey, nil); SetDock(kMSBDDockBackgroundColorKey, nil); SetDock(kMSBDDockBackgroundOpacityKey, nil); }   // (nothing stored)
static NSString *Recent(void) { return [NSString stringWithContentsOfFile:@MSBD_GUARD_RECENT encoding:NSUTF8StringEncoding error:nil] ?: @""; }
static int Noted(void) {   // (the crash guard's list: lines of Dock Background turned on)
    int n = 0;
    for (NSString *l in [Recent() componentsSeparatedByString:@"\n"]) if ([l hasSuffix:@" " TDP_DOMAIN " dockBackground Dock Background"]) n++;
    return n;
}
static void Turn(double s) { [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:s]]; }
static int Posted(const char *suffix) { int n = 0; for (NSString *p in gPosts) if ([p isEqualToString:[@"com.besiktasliseba.dockmagnification/" stringByAppendingString:@(suffix)]]) n++; return n; }
static BOOL Is(UIColor *c, unsigned rgb) {
    CGFloat r = -1, g = -1, b = -1, a = -1;
    return [c getRed:&r green:&g blue:&b alpha:&a] && fabs(r - ((rgb >> 16) & 255) / 255.0) < 0.003 && fabs(g - ((rgb >> 8) & 255) / 255.0) < 0.003 && fabs(b - (rgb & 255) / 255.0) < 0.003;
}
static NSString *Desc(id v) { return v ? [v description] : @"(nothing)"; }
static PSSliderCell *SliderCell(PSSpecifier *row, BOOL label) { PSSliderCell *c = [[PSSliderCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"PSSliderCell" specifier:row]; if (label) [c addValueLabel]; return c; }
static PSSliderCell *Shown(DMRootListController *page, PSSliderCell *c, PSSpecifier *row) {   // (Settings gives the cell to a row: the page's cell method)
    c.specifier = row; gNextCell = c;
    return (PSSliderCell *)[page tableView:nil cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
}
static BOOL Fits(UILabel *l) {   // (its text shrinks to fit its width, as on the Status Bar page; its place and size kept)
    CGFloat w = [l.text sizeWithAttributes:@{ NSFontAttributeName: l.font }].width;
    return l.adjustsFontSizeToFitWidth && l.minimumScaleFactor > 0 && w * l.minimumScaleFactor <= l.bounds.size.width && CGRectEqualToRect(l.frame, CGRectMake(350, 12, 28, 20));
}
int main(int argc, char **argv) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        if (argc < 2) { printf("FAIL  usage: <Root.plist>\n"); return 1; }
        NSArray *items = [NSDictionary dictionaryWithContentsOfFile:@(argv[1])][@"items"];
        PSSpecifier *row = [PSSpecifier new], *well = [PSSpecifier new], *slider = [PSSpecifier new], *size = [PSSpecifier new];
        for (NSDictionary *it in items) {
            if ([it[@"id"] isEqual:@"DOCK_BACKGROUND"]) row.item = it;
            if ([it[@"id"] isEqual:@"DOCK_BACKGROUND_COLOR"]) well.item = it;
            if ([it[@"id"] isEqual:@"DOCK_BACKGROUND_OPACITY"]) slider.item = it;
            if ([it[@"key"] isEqual:@"dockIconSize"] && [it[@"cell"] isEqual:@"PSSliderCell"]) size.item = it;   // (another of the Dock's sliders)
        }
        if (!row.item || !well.item || !slider.item || !size.item) { printf("FAIL  the Dock Background rows are not in %s\n", argv[1]); return 1; }
        DMRootListController *page = [DMRootListController new];
        page.reloaded = [NSMutableArray array]; gPosts = [NSMutableArray array]; gPostTimes = [NSMutableArray array];
        row.target = well.target = slider.target = page;
        Automatic(); SetBar(@"#FF3B30"); unlink(MSBD_GUARD_RECENT);

        printf("== the colour well shows the colour the Dock draws (decision 3)\n");
        DMDockColorCell *cell = [[DMDockColorCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c" specifier:well];
        UIColorWell *cw = (UIColorWell *)cell.accessoryView;
        Check([cw isKindOfClass:[UIColorWell class]] && Is(cw.selectedColor, 0xFF3B30) && !cw.supportsAlpha, @"nothing stored: the well shows Status Bar Background's colour (#FF3B30), no alpha of its own (the slider is the opacity)", Desc(cw.selectedColor));
        SetDock(kMSBDDockBackgroundColorKey, @"#00FF00");
        DMDockColorCell *cell2 = [[DMDockColorCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c" specifier:well];
        Check(Is(((UIColorWell *)cell2.accessoryView).selectedColor, 0x00FF00), @"  ... once the Dock's own is stored, that one", nil);
        SetDock(kMSBDDockBackgroundColorKey, nil);

        printf("== the Background row\n");
        [gPosts removeAllObjects];
        [page setPreferenceValue:@"color" specifier:row];
        Check([Dock(kMSBDDockBackgroundKey) isEqual:@"color"] && [Dock(kMSBDDockBackgroundColorKey) isEqual:@"#FF3B30"], @"Color chosen the first time: stored, with Status Bar Background's colour stored as the Dock's own", Desc(Dock(kMSBDDockBackgroundColorKey)));
        Check(Posted("prefsChanged") == 1 && !Posted("colorChanged"), @"  ... the Dock told with prefsChanged (the row's own), not the light note", [gPosts description]);
        Check(Noted() == 1 && page.noteGone >= 1, @"  ... noted for the crash guard as Dock Background turned on (and a guard note it ended leaves the page)", Recent());
        SetBar(@"#0000FF");
        [page setPreferenceValue:@"color" specifier:row];
        Check([Dock(kMSBDDockBackgroundColorKey) isEqual:@"#FF3B30"] && Noted() == 1, @"  ... Color again, the menu bar's colour changed since: the Dock's own kept (no live link), not noted twice", Desc(Dock(kMSBDDockBackgroundColorKey)));
        [page setPreferenceValue:@"auto" specifier:row];
        Check([Dock(kMSBDDockBackgroundKey) isEqual:@"auto"] && [Dock(kMSBDDockBackgroundColorKey) isEqual:@"#FF3B30"] && !Noted(), @"Automatic: stored, the colour kept for next time, the crash guard's note taken out", Recent());
        Check([[page readPreferenceValue:row] isEqual:@"auto"], @"  ... the row reads Automatic", nil);

        printf("== the colour well while Automatic\n");
        Automatic(); SetBar(@"#FF3B30"); [gPosts removeAllObjects]; [page.reloaded removeAllObjects];
        cw.selectedColor = [UIColor colorWithRed:0x34 / 255.0 green:0xC7 / 255.0 blue:0x59 / 255.0 alpha:1];
        [cell dm_colorChanged];
        Check([Dock(kMSBDDockBackgroundColorKey) isEqual:@"#34C759"] && [Dock(kMSBDDockBackgroundKey) isEqual:@"color"], @"a colour picked while Automatic: the well's colour stored as \"#RRGGBB\" (not the menu bar's), Background switched to Color", Desc(Dock(kMSBDDockBackgroundColorKey)));
        Check([page.reloaded containsObject:@"DOCK_BACKGROUND"] && Noted() == 1, @"  ... the Background row shows Color at once; noted for the crash guard", [page.reloaded description]);
        Check(!Posted("colorChanged"), @"  ... the light note not posted at once (throttled)", [gPosts description]);
        Turn(0.3);
        Check(Posted("colorChanged") == 1 && !Posted("prefsChanged"), @"  ... posted once within 0.3 s: the light note only, no prefsChanged", [gPosts description]);
        [page.reloaded removeAllObjects];
        cw.selectedColor = [UIColor colorWithRed:1 green:1 blue:1 alpha:1]; [cell dm_colorChanged]; Turn(0.3);
        Check([Dock(kMSBDDockBackgroundColorKey) isEqual:@"#FFFFFF"] && !page.reloaded.count && Noted() == 1, @"  ... another colour while Color: stored; no row reload, not noted again", [page.reloaded description]);

        printf("== the opacity slider while Automatic\n");
        Automatic(); SetBar(@"#FF3B30"); [gPosts removeAllObjects]; [page.reloaded removeAllObjects]; unlink(MSBD_GUARD_RECENT);
        [page setPreferenceValue:@0.4 specifier:slider];
        Check([Dock(kMSBDDockBackgroundOpacityKey) doubleValue] == 0.4 && [Dock(kMSBDDockBackgroundKey) isEqual:@"color"] && [Dock(kMSBDDockBackgroundColorKey) isEqual:@"#FF3B30"],
              @"the slider moved while Automatic: the opacity stored, Background switched to Color, the menu bar's colour stored as the Dock's own (first time)", Desc(Dock(kMSBDDockBackgroundColorKey)));
        Check([page.reloaded containsObject:@"DOCK_BACKGROUND"] && Noted() == 1, @"  ... the Background row shows Color at once; noted for the crash guard", Recent());
        for (int i = 0; i < 10; i++) [page setPreferenceValue:@(0.5 + i * 0.05) specifier:slider];
        Turn(0.3);
        Check(Posted("colorChanged") == 1 && !Posted("prefsChanged") && fabs([Dock(kMSBDDockBackgroundOpacityKey) doubleValue] - 0.95) < 1e-9,
              @"  ... a drag (11 moves at once): the light note once (at most every 0.15 s), no prefsChanged, the last value stored", [gPosts description]);
        [page.reloaded removeAllObjects];
        [page setPreferenceValue:@0.6 specifier:slider]; Turn(0.3);
        Check(!page.reloaded.count && Noted() == 1 && Posted("colorChanged") == 2, @"  ... moved while Color: no row reload, not noted again, the light note again", [gPosts description]);

        printf("== the opacity slider's cell: live while dragged, its value label fits (DOCKSLIDER, the 1.8.7.6~b01 pass)\n");
        PSSliderCell *oc = Shown(page, SliderCell(slider, YES), slider);
        Check(oc.slider.continuous, @"the opacity row: its slider continuous (the value written while dragged, so the Dock and its marks follow)", @"not continuous: written only when the finger lifts");
        Check(Fits(oc.value), @"  ... its value label fits (\"0.70\" in the stock label's width shrinks a touch; its place and size kept)",
              [NSString stringWithFormat:@"adjusts %d, scale %.2f, frame %@", oc.value.adjustsFontSizeToFitWidth, oc.value.minimumScaleFactor, NSStringFromCGRect(oc.value.frame)]);
        PSSliderCell *late = Shown(page, SliderCell(slider, NO), slider);
        [late addValueLabel];
        Turn(0.05);
        Check(Fits(late.value) && late.slider.continuous, @"  ... a value label made during the first layout fits too (the page looks again once the main queue turns)", nil);
        PSSliderCell *sc = Shown(page, SliderCell(size, YES), size);
        Check(!sc.slider.continuous, @"another of the Dock's sliders (Dock Size): left as Settings made it (written when the finger lifts, as before)", nil);
        Check(Fits(sc.value), @"  ... its value label fits as well (the Status Bar page's rule for every slider row)", nil);
        Shown(page, oc, size);
        Check(!oc.slider.continuous, @"  ... the opacity row's cell reused for Dock Size: its slider's own setting back", nil);
        Shown(page, oc, slider);
        Check(oc.slider.continuous, @"  ... and back on the opacity row: continuous again", nil);
        PSSliderCell *own = SliderCell(size, NO); own.slider.continuous = YES;
        Shown(page, own, slider); Shown(page, own, size);
        Check(own.slider.continuous, @"  ... a slider Settings made continuous keeps that for another row (its own setting, not NO)", nil);
        // (review of 7fbb1318: the own setting is taken on the opacity row, so a plist isContinuous there that some Settings took would be given back
        //  to the Dock's other sliders on a reused cell: Dock Size written and prefsChanged posted at every frame of a drag)
        PSHonouringSliderCell *hc = [[PSHonouringSliderCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"PSSliderCell" specifier:slider];
        Shown(page, hc, slider); BOOL hcLive = hc.slider.continuous;
        Shown(page, hc, size); BOOL hcSize = hc.slider.continuous;
        Shown(page, hc, slider);
        Check(hcLive && !hcSize && hc.slider.continuous, @"  ... a Settings that takes isContinuous: the opacity row live, its cell reused for Dock Size written when the finger lifts, live again back on the opacity row",
              [NSString stringWithFormat:@"opacity %d, Dock Size %d, opacity again %d", hcLive, hcSize, hc.slider.continuous]);
        Automatic(); SetDock(kMSBDDockBackgroundKey, @"color"); [gPosts removeAllObjects]; [gPostTimes removeAllObjects];
        for (int i = 0; i <= 12; i++) { [page setPreferenceValue:@(0.7 - i * 0.05) specifier:slider]; Turn(0.05); }   // (a 0.65 s drag, a move every 50 ms)
        NSUInteger during = (NSUInteger)Posted("colorChanged");
        double gap = 1;
        for (NSUInteger i = 1; i < gPostTimes.count; i++) gap = fmin(gap, gPostTimes[i].doubleValue - gPostTimes[i - 1].doubleValue);
        Check(during >= 3 && during <= 5 && gap > 0.13 && !Posted("prefsChanged"), @"  ... dragged: the Dock told while the finger moves, at most every 0.15 s (the light note, no prefsChanged)",
              [NSString stringWithFormat:@"%lu notes, shortest gap %.3f s", (unsigned long)during, gap]);
        [page setPreferenceValue:@(0.7 - 12 * 0.05) specifier:slider]; Turn(0.3);   // (the finger lifts: the cell writes its last value)
        Check(fabs([Dock(kMSBDDockBackgroundOpacityKey) doubleValue] - 0.1) < 1e-9 && (NSUInteger)Posted("colorChanged") <= during + 2 && (NSUInteger)Posted("colorChanged") > during,
              @"  ... lifted: the last value stored and told", [gPosts description]);
        SetDock(kMSBDDockBackgroundOpacityKey, @0.6); SetDock(kMSBDDockBackgroundKey, @"color");

        printf("== the crash guard's step 1, right after Color was chosen (no frame of DockColor.m on the stack)\n");
        char rec[1536] = "";
        int n = MSBDGuardSwitchOffRecent((long)time(NULL) - 120, rec, sizeof rec);
        id after = Dock(kMSBDDockBackgroundKey);
        Check(n == 1 && strstr(rec, "switch " TDP_DOMAIN " dockBackground Dock Background\n"), @"two crashes within 2 min: step 1 sets Dock Background back (its record names it by its row's title)", @(rec));
        Check([after isKindOfClass:[NSNumber class]] && ![after boolValue] && !MSBDDockBackgroundOn([after isKindOfClass:[NSString class]] ? [after UTF8String] : NULL), @"  ... false stored, which is Automatic", Desc(after));
        Check([[page readPreferenceValue:row] isEqual:@"auto"], @"  ... the Background row reads it as Automatic (a list row shows no choice for false as it is)", Desc([page readPreferenceValue:row]));
        [page setPreferenceValue:@"color" specifier:row];
        Check([Dock(kMSBDDockBackgroundKey) isEqual:@"color"] && Noted() == 1, @"  ... Color chosen again from there: stored and noted again", Recent());

        printf("== what the page writes\n");
        NSDictionary *bar = (__bridge_transfer NSDictionary *)CFPreferencesCopyMultiple(NULL, CFSTR(TDP_BAR_DOMAIN), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        NSDictionary *dock = (__bridge_transfer NSDictionary *)CFPreferencesCopyMultiple(NULL, CFSTR(TDP_DOMAIN), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        NSSet *keys = [NSSet setWithArray:dock.allKeys], *three = [NSSet setWithArray:@[@kMSBDDockBackgroundKey, @kMSBDDockBackgroundColorKey, @kMSBDDockBackgroundOpacityKey]];
        Check([bar isEqual:@{ @"backgroundColor": @"#FF3B30" }] && [keys isSubsetOfSet:three], @"the Dock's domain only, its three keys; Status Bar Background's colour only read, never written", [NSString stringWithFormat:@"%@ / %@", bar, dock]);
        Automatic(); SetBar(nil); unlink(MSBD_GUARD_RECENT);
        printf("page: %d checks, %d failed\n", gChecks, gFails);
    }
    return gFails ? 1 : 0;
}
