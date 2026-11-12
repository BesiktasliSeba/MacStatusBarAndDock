// DisplaySettings.h -- the Display menu and the Display Settings window (MacStatusBar&Dock 1.8.7 commit 11; plans/design-1.8.7-displays.md
// section 6). Included by StatusBar.x after the native windows (NativeWindow.h) and the menus (DMPresentMenu).
//  - The Display menu: a title right of Window (before Audio) while a display is connected. Its rows: the display's name and mode (3840 x 2160), how
//    it shows (its own desktop, or a mirror of the iPad: read only), then Display Settings... (16+, with the per-display settings on). iPadOS 15: the
//    display mirrors on every engine, so the menu only says so. Ported from the iOS 15 branch's menu (ext-display-15) without its backend.
//  - Display Settings: one view (DMDispSettingsView) made from the rows' table (common/DisplayRows.h): the display's name and mode on top, each row
//    with its control, a dot and a reset arrow on a row changed for this display, its footer, and Use iPad Settings at the bottom with a confirmation.
//    What a row shows and every change go through common/DisplayRowStore.h (the writer Settings' Displays page uses too) and DMDispWrite. It follows
//    the displays domain and the iPad's own settings live (Settings' page and the window follow each other).
//  - Its hosts: on the iPad a native window (DMDispSettingsWindow, "Display Settings"; Esc or Command-W close it); on the TV a panel in the TV's own
//    scene (the per-scene layer helper, SceneLayer.h, role "dispsettings", just under our menus): a title bar with the red light, moved by its title
//    bar, closed by the red light, Esc (SpringBoard holds the keys for it while it is the key target: opened or clicked last), the escape gesture, the
//    screen going off or its display going, no Dock icon and no Mac Switcher record. It edits the
//    display named by the menu it came from: a TV bar's own display, or from the iPad's bar the display connected.
//  - The crash map: this file and the DMDisp... functions are Display Settings' (tools/crashmap-rules.txt). With its switch off the menu shows only
//    "External Display" and Extended / Mirroring from public calls: no display key, registry, mode or CADisplay read (DMDispMenuOpenPlain).
#pragma once
#include "../common/DisplayRows.h"
#include "../common/DisplayRowStore.h"

@class DMDispSettingsView;
static void DMDispPanelClose(NSString *why);
static void DMDispSettingsOpen(NSString *display, BOOL onTV);

// ---- which display, and what it has ------------------------------------------------------------------------------------------------------------
// The display a view is on (a TV bar's), else the one connected (iPadOS drives one external display at a time): the one SpringBoard has a desktop on
// first. nil: none connected (or no readable key).
__attribute__((noinline)) static NSString *DMDispMenuDisplayOf(UIView *v) {
    UIScreen *ext = v ? DMExternalScreenOf(v) : nil;
    NSString *k = ext ? DMDispKeyOfScreen(ext) : nil;
    if (k) return k;
    NSArray<UIScreen *> *screens = DMDispScreens();
    NSString *any = nil;
    for (UIScreen *s in screens) {
        NSString *d = DMDispKeyOfScreen(s);
        if (!d) continue;
        if (DMSceneLayerSceneOf(DMDispDesktopScreen(d, screens))) return d;
        if (!any) any = d;
    }
    return any;
}
static BOOL DMDispIsDesktop(NSString *display) { return display && DMSceneLayerSceneOf(DMDispDesktopScreen(display, DMDispScreens())) != nil; }
// The display's mode as its own pixels: the registry's (the CADisplay's current mode), else read now; "" when none.
static NSString *DMDispModeText(NSString *display, NSDictionary *info) {
    NSString *m = MSBDDispStoreMode(info);
    if (m) return m;
    UIScreen *s = display ? DMDispDesktopScreen(display, DMDispScreens()) : nil;
    id mode = s ? MSBDDispGet(MSBDDispCADisplayOfConfig(MSBDDispConfigOfScreen(s)), "currentMode") : nil;
    unsigned long w = DMDispGetUnsigned(mode, "width"), h = DMDispGetUnsigned(mode, "height");
    return w && h ? [NSString stringWithFormat:@"%lu x %lu", w, h] : @"";
}
// What a display has now, for the rows' "shown when" (DisplayRows.h).
static MSBDDispCtx DMDispCtxFor(NSString *display) {
    MSBDDispCtx c;
    c.osMajor = (int)[NSProcessInfo processInfo].operatingSystemVersion.majorVersion;
    c.extended = c.osMajor >= 16 && DMDispIsDesktop(display);
    c.ourBar = !gStockBar;
    BOOL dockLoaded = NO; (void)DMDockAutoHideLive(&dockLoaded);
    c.ourDock = MSBDDispStoreOurDock(dockLoaded);   // (the Dock part loaded and its own switch on: as Settings' page reads it, DisplayRowStore.h)
    c.smEngine = DMSMEngine();
    c.finder = gFinderOn;
    NSDictionary *all = MSBDDispStoreAll();
    c.scales = (int)MSBDDispStoreScaleChoices(all, MSBDDispStoreInfo(all, display), NULL).count;   // (More Space, commit 13: a choice only where iPadOS lists 2+)
    c.release = MSBD_DISP_RELEASE;
    return c;
}

// ---- the Display menu ---------------------------------------------------------------------------------------------------------------------------
// The title shows while a display is connected (HDMI, USB-C or AirPlay): another UIScreen than the iPad's.
static BOOL DMDispMenuWanted(void) { return !gStockBar && DMDispScreens().count > 1; }
// Display Settings off (the crash guard's step for it, or the user): the menu from public calls only -- no display key, no registry, no mode or CADisplay
// read, nothing of what the switch names (review: a crash in those reads was blamed on Display Settings, the guard switched it off, and the next tap
// on Display crashed again in the same reads, so the whole tweak went off). "External Display", and whether SpringBoard has a desktop on another
// screen (a window scene of its own there: Extended) or none (Mirroring).
static void DMDispMenuOpenPlain(UIButton *btn, int os, BOOL onTV) {
    BOOL extended = NO;
    if (os >= 16) {
        @try {
            UIScreen *main = [UIScreen mainScreen];
            for (UIScene *sc in [UIApplication sharedApplication].connectedScenes)
                if ([sc isKindOfClass:[UIWindowScene class]] && ((UIWindowScene *)sc).screen && ((UIWindowScene *)sc).screen != main) extended = YES;
        } @catch (NSException *e) {}
    }
    NSArray *items = @[ [[DMRow alloc] initWithTitle:@"External Display" enabled:NO handler:nil],
                        [[DMRow alloc] initWithTitle:(extended ? @"Extended Display" : @"Mirroring the iPad") enabled:NO handler:nil] ];
    DMPresentMenu(btn, kDispLabelKey, kDispPillKey, items);
    DMLog([NSString stringWithFormat:@"[display] menu opened on the %@'s bar with Display Settings off (%@; no display read)", onTV ? @"TV" : @"iPad", extended ? @"its own desktop" : @"mirroring"]);
}
__attribute__((noinline)) static void DMDispMenuOpen(UIButton *btn) {
    if (DMTitleTapWithMenuOpen(btn)) return;
    DM_FEATURE_MARK("display-menu");
    int os = (int)[NSProcessInfo processInfo].operatingSystemVersion.majorVersion;
    BOOL onTV = DMExternalScreenOf(btn) != nil;
    if (!gDMDispLayerOn) { DMDispMenuOpenPlain(btn, os, onTV); return; }   // (the switch off: no key, registry or mode read)
    NSString *display = DMDispMenuDisplayOf(btn);
    NSDictionary *info = MSBDDispStoreInfo(MSBDDispStoreAll(), display);
    NSString *mode = DMDispModeText(display, info);
    NSString *line = mode.length ? [NSString stringWithFormat:@"%@  %@", MSBDDispStoreName(info), mode] : MSBDDispStoreName(info);
    BOOL extended = os >= 16 && DMDispIsDesktop(display);
    NSMutableArray *items = [NSMutableArray array];
    [items addObject:[[DMRow alloc] initWithTitle:line enabled:NO handler:nil]];
    [items addObject:[[DMRow alloc] initWithTitle:(extended ? @"Extended Display" : @"Mirroring the iPad") enabled:NO handler:nil]];
    int scaleNow = 0;
    NSArray<NSArray *> *scales = extended ? MSBDDispStoreScaleChoices(MSBDDispStoreAll(), info, &scaleNow) : @[];
    if (scales.count) {   // (More Space, commit 13: the scales iPadOS offers this display, the one in use ticked)
        [items addObject:[NSNull null]];
        for (NSArray *c in scales) {
            int v = [c[0] intValue];
            DMRow *row = [[DMRow alloc] initWithTitle:c[1] enabled:YES handler:DMCloseThen(^{ DMMoreSpaceSet(display, v); })];
            row.checked = v == scaleNow;
            [items addObject:row];
        }
    }
    if (os >= 16 && display) {
        [items addObject:[NSNull null]];
        [items addObject:[[DMRow alloc] initWithTitle:@"Display Settings…" enabled:extended handler:DMCloseThen(^{ DMDispSettingsOpen(display, onTV); })]];
    }
    DMPresentMenu(btn, kDispLabelKey, kDispPillKey, items);
    DMLog([NSString stringWithFormat:@"[display] menu opened on the %@'s bar: %@ (%@, %@, settings %@)", onTV ? @"TV" : @"iPad", display ?: @"no key", line,
           extended ? @"its own desktop" : @"mirroring", (os >= 16 && display) ? @"offered" : @"not offered"]);
}

// ---- the view ---------------------------------------------------------------------------------------------------------------------------------
@interface DMDispSettingsView : UIView
@property (nonatomic, copy) NSString *display;
@property (nonatomic, copy) void (^onClose)(void);
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, assign) BOOL askingUseIPad;
- (instancetype)initWithDisplay:(NSString *)display;
- (void)dm_reload;
- (CGFloat)dm_contentHeightForWidth:(CGFloat)w;
- (NSString *)dm_state;
- (BOOL)dm_setRow:(NSString *)rowId value:(id)value;
- (BOOL)dm_resetRow:(NSString *)rowId;
- (void)dm_useIPadAsk;
- (void)dm_useIPadConfirmed;
@end
static NSHashTable<DMDispSettingsView *> *gDMDispViews;   // (every open Display Settings view: the live follow)

@implementation DMDispSettingsView {
    int _tokens[3];
    BOOL _following;   // (its notes registered: only while it is in a window)
}
- (instancetype)initWithDisplay:(NSString *)display {
    if (!(self = [super initWithFrame:CGRectMake(0, 0, 460, 400)])) return nil;
    _display = [display copy];
    _scroll = [[UIScrollView alloc] initWithFrame:self.bounds];
    _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scroll.alwaysBounceVertical = NO;
    [self addSubview:_scroll];
    _stack = [UIStackView new];
    _stack.axis = UILayoutConstraintAxisVertical; _stack.spacing = 0; _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_scroll addSubview:_stack];
    [NSLayoutConstraint activateConstraints:@[
        [_stack.topAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.topAnchor constant:14],
        [_stack.bottomAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.bottomAnchor constant:-16],
        [_stack.leadingAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.leadingAnchor constant:18],
        [_stack.trailingAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.trailingAnchor constant:-18]]];
    if (!gDMDispViews) gDMDispViews = [NSHashTable weakObjectsHashTable];
    [gDMDispViews addObject:self];
    [self dm_reload];
    return self;
}
// Live while it is shown: a change from Settings' page, the other host or the iPad's own settings shows at once. The notes are taken when the view goes
// into a window and let go when it leaves one (its host closed), not only at its end: a closed view never rebuilds on a post. Every control's action
// holds the view weakly (no cycle view -> control -> action -> view), so a closed host's view goes.
- (void)dm_follow:(BOOL)on {
    if (on == _following) return;
    _following = on;
    if (!on) { for (int i = 0; i < 3; i++) if (_tokens[i]) { notify_cancel(_tokens[i]); _tokens[i] = 0; } return; }
    const char *names[3] = { MSBD_DISP_NOTIFY, "com.besiktasliseba.macstatusbar/prefsChanged", "com.besiktasliseba.dockmagnification/prefsChanged" };
    __weak DMDispSettingsView *weakSelf = self;
    for (int i = 0; i < 3; i++) notify_register_dispatch(names[i], &_tokens[i], dispatch_get_main_queue(), ^(int t) { [weakSelf dm_reload]; });
    [self dm_reload];   // (what changed while it was out of a window)
}
- (void)didMoveToWindow { [super didMoveToWindow]; [self dm_follow:self.window != nil]; }
- (void)dealloc { [self dm_follow:NO]; }
static UILabel *DMDispLabel(NSString *t, UIFont *f, UIColor *c) {
    UILabel *l = [UILabel new]; l.text = t; l.font = f; l.textColor = c; l.numberOfLines = 0; return l;
}
- (UIView *)dm_gap:(CGFloat)h { UIView *v = [UIView new]; [v.heightAnchor constraintEqualToConstant:h].active = YES; return v; }
// One row: [dot] title ... control [iPad's value, reset arrow]; its footer under it.
- (UIView *)dm_row:(const MSBDDispRow *)r all:(NSDictionary *)all enabled:(BOOL)enabled {
    __weak DMDispSettingsView *ws = self;   // (the controls' actions: never the view itself)
    int from = 0;
    id v = MSBDDispRowShownValue(all, _display, r, &from);
    BOOL changed = from == kMSBDDispFromOverride;
    UIView *box = [UIView new];
    UIStackView *line = [UIStackView new];
    line.axis = UILayoutConstraintAxisHorizontal; line.alignment = UIStackViewAlignmentCenter; line.spacing = 8;
    UIView *dot = [UIView new];
    dot.backgroundColor = [UIColor systemBlueColor]; dot.layer.cornerRadius = 3; dot.hidden = !changed;
    [dot.widthAnchor constraintEqualToConstant:6].active = YES; [dot.heightAnchor constraintEqualToConstant:6].active = YES;
    [line addArrangedSubview:dot];
    UILabel *title = DMDispLabel(@(r->title), [UIFont systemFontOfSize:13], enabled ? [UIColor labelColor] : [UIColor tertiaryLabelColor]);
    [title setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [line addArrangedSubview:title];
    NSString *rowId = @(r->rowId);
    UIControl *control = nil;
    if (r->kind == kMSBDRowSwitch) {
        UISwitch *sw = [UISwitch new]; sw.on = [v boolValue]; sw.transform = CGAffineTransformMakeScale(0.8, 0.8);
        [sw addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { [ws dm_setRow:rowId value:@(((UISwitch *)a.sender).on)]; }] forControlEvents:UIControlEventValueChanged];
        control = sw;
    } else if (r->kind == kMSBDRowSlider) {
        UISlider *sl = [UISlider new]; sl.minimumValue = r->lo; sl.maximumValue = r->hi; sl.value = [v doubleValue]; sl.continuous = NO;
        [sl.widthAnchor constraintEqualToConstant:150].active = YES;
        const MSBDDispRow *rr = r;
        [sl addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { [ws dm_setRow:rowId value:@(MSBDDispSliderValue(rr, ((UISlider *)a.sender).value))]; }] forControlEvents:UIControlEventValueChanged];
        control = sl;
    } else if (r->kind == kMSBDRowScale) {   // (More Space, commit 13: Apple's own scales; the one in use selected, a choice set, then kept or reverted)
        int now = 0;
        NSArray<NSArray *> *choices = MSBDDispStoreScaleChoices(all, MSBDDispStoreInfo(all, _display), &now);
        UISegmentedControl *seg = [UISegmentedControl new];
        for (NSUInteger i = 0; i < choices.count; i++) { [seg insertSegmentWithTitle:choices[i][1] atIndex:i animated:NO]; if ([choices[i][0] intValue] == now) seg.selectedSegmentIndex = (NSInteger)i; }
        [seg addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
            NSInteger i = ((UISegmentedControl *)a.sender).selectedSegmentIndex;
            if (i >= 0 && i < (NSInteger)choices.count) [ws dm_setRow:rowId value:choices[i][0]];
        }] forControlEvents:UIControlEventValueChanged];
        control = seg;
        changed = NO;   // (Apple's store, not an override: no dot, no reset)
    } else if (r->kind == kMSBDRowChoice) {
        NSMutableArray *titles = [NSMutableArray array];
        for (int i = 0; i < r->choices; i++) [titles addObject:@(r->choiceTitles[i])];
        UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:titles];
        int idx = r->choiceValues[0] ? MSBDDispChoiceIndexText(r, [v isKindOfClass:[NSString class]] ? [v UTF8String] : "") : MSBDDispChoiceIndexNum(r, [v doubleValue]);
        seg.selectedSegmentIndex = idx;
        const MSBDDispRow *rr = r;
        [seg addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
            NSInteger i = ((UISegmentedControl *)a.sender).selectedSegmentIndex;
            if (i < 0 || i >= rr->choices) return;
            [ws dm_setRow:rowId value:(rr->choiceValues[0] ? (id)@(rr->choiceValues[i]) : (id)@((int)i))];
        }] forControlEvents:UIControlEventValueChanged];
        control = seg;
    }
    if (control) { control.enabled = enabled; control.accessibilityLabel = @(r->title); [line addArrangedSubview:control]; }
    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
    [reset setImage:[UIImage systemImageNamed:@"arrow.uturn.backward.circle"] forState:UIControlStateNormal];
    int def = 0;
    BOOL hasDef = MSBDDispDisplayDefault(r->part, r->key, &def);
    NSString *back = hasDef ? @MSBD_DISP_TEXT_DEFAULT_ON : [@"iPad: " stringByAppendingString:MSBDDispRowValueText(r, MSBDDispRowIPadValue(r))];
    reset.accessibilityLabel = [NSString stringWithFormat:@"%s, %@", MSBD_DISP_TEXT_RESET, back];
    reset.hidden = !changed; reset.enabled = enabled;
    [reset addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { [ws dm_resetRow:rowId]; }] forControlEvents:UIControlEventTouchUpInside];
    [line addArrangedSubview:reset];
    UIStackView *col = [UIStackView new];
    col.axis = UILayoutConstraintAxisVertical; col.spacing = 2; col.translatesAutoresizingMaskIntoConstraints = NO;
    [col addArrangedSubview:line];
    NSMutableArray *notes = [NSMutableArray array];
    if (r->footer) [notes addObject:@(r->footer)];
    if (changed) [notes addObject:back];
    if (notes.count) {
        UILabel *f = DMDispLabel([notes componentsJoinedByString:@" "], [UIFont systemFontOfSize:11], [UIColor secondaryLabelColor]);
        [col addArrangedSubview:f];
    }
    [box addSubview:col];
    [NSLayoutConstraint activateConstraints:@[[col.topAnchor constraintEqualToAnchor:box.topAnchor constant:6], [col.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-6],
                                              [col.leadingAnchor constraintEqualToAnchor:box.leadingAnchor], [col.trailingAnchor constraintEqualToAnchor:box.trailingAnchor],
                                              [line.heightAnchor constraintGreaterThanOrEqualToConstant:30]]];
    box.accessibilityIdentifier = rowId;
    return box;
}
- (void)dm_reload {
    __weak DMDispSettingsView *ws = self;   // (the buttons' actions: never the view itself)
    for (UIView *v in [_stack.arrangedSubviews copy]) { [_stack removeArrangedSubview:v]; [v removeFromSuperview]; }
    NSDictionary *all = MSBDDispStoreAll();
    BOOL layerOn = MSBDDispStoreLayerOn(all), connected = [MSBDDispStoreConnected(all) containsObject:_display];
    NSDictionary *info = MSBDDispStoreInfo(all, _display);
    MSBDDispCtx ctx = DMDispCtxFor(_display);
    [_stack addArrangedSubview:DMDispLabel(MSBDDispStoreName(info), [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold], [UIColor labelColor])];
    NSString *mode = DMDispModeText(_display, info);
    if (mode.length) [_stack addArrangedSubview:DMDispLabel(mode, [UIFont systemFontOfSize:12], [UIColor secondaryLabelColor])];
    [_stack addArrangedSubview:[self dm_gap:6]];
    NSString *top = @(MSBDDispTopText(layerOn, connected, ctx.extended));   // (a display gone says so, not the mirror's words: DisplayRows.h)
    [_stack addArrangedSubview:DMDispLabel(top, [UIFont systemFontOfSize:12], [UIColor secondaryLabelColor])];
    [_stack addArrangedSubview:[self dm_gap:8]];
    int shown = 0;
    for (int i = 0; i < MSBD_DISP_ROW_COUNT; i++) {
        const MSBDDispRow *r = MSBDDispRowAt(i);
        if (!MSBDDispRowShown(r, &ctx)) continue;
        BOOL enabled = MSBDDispRowEnabled(r, &ctx, connected, layerOn);
        if (enabled && r->dependsOn) {   // (the amount follows its switch: greyed while magnification is off for this display)
            const MSBDDispRow *dep = MSBDDispRowFor(r->part, r->dependsOn);
            if (dep && ![MSBDDispRowShownValue(all, _display, dep, NULL) boolValue]) enabled = NO;
        }
        if (shown++) { UIView *sep = [UIView new]; sep.backgroundColor = [UIColor separatorColor]; [sep.heightAnchor constraintEqualToConstant:0.5].active = YES; [_stack addArrangedSubview:sep]; }
        [_stack addArrangedSubview:[self dm_row:r all:all enabled:enabled]];
    }
    if (ctx.extended && MSBDDispStoreOverscanTip(info)) {   // (More Space's reading, commit 13: iPadOS does not shrink the picture for this TV)
        [_stack addArrangedSubview:[self dm_gap:6]];
        [_stack addArrangedSubview:DMDispLabel(@MSBD_DISP_TEXT_OVERSCAN, [UIFont systemFontOfSize:11], [UIColor secondaryLabelColor])];
    }
    [_stack addArrangedSubview:[self dm_gap:14]];
    UIStackView *buttons = [UIStackView new];
    buttons.axis = UILayoutConstraintAxisHorizontal; buttons.spacing = 10; buttons.alignment = UIStackViewAlignmentCenter;
    [buttons addArrangedSubview:[UIView new]];
    BOOL anyOwn = MSBDDispStoreHasOwn(all, _display);   // (its rows' changes only, as Settings' page: never More Space's records)
    if (_askingUseIPad) {
        [_stack addArrangedSubview:DMDispLabel(@MSBD_DISP_TEXT_USE_IPAD_ASK, [UIFont systemFontOfSize:12], [UIColor labelColor])];
        [_stack addArrangedSubview:[self dm_gap:6]];
        UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
        [cancel setTitle:@"Cancel" forState:UIControlStateNormal];
        [cancel addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { ws.askingUseIPad = NO; [ws dm_reload]; }] forControlEvents:UIControlEventTouchUpInside];
        [buttons addArrangedSubview:cancel];
        UIButton *ok = [UIButton buttonWithType:UIButtonTypeSystem];
        [ok setTitle:@MSBD_DISP_TEXT_USE_IPAD forState:UIControlStateNormal];
        ok.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        [ok addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { [ws dm_useIPadConfirmed]; }] forControlEvents:UIControlEventTouchUpInside];
        [buttons addArrangedSubview:ok];
    } else {
        UIButton *use = [UIButton buttonWithType:UIButtonTypeSystem];
        [use setTitle:@MSBD_DISP_TEXT_USE_IPAD forState:UIControlStateNormal];
        use.enabled = anyOwn && layerOn;
        [use addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { [ws dm_useIPadAsk]; }] forControlEvents:UIControlEventTouchUpInside];
        [buttons addArrangedSubview:use];
    }
    [_stack addArrangedSubview:buttons];
}
- (CGFloat)dm_contentHeightForWidth:(CGFloat)w {
    [self layoutIfNeeded];
    CGSize s = [_stack systemLayoutSizeFittingSize:CGSizeMake(w - 36, UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    return ceil(s.height + 30);
}
// A change from a row's control: the override for this display, through the one writer (DMDispWrite); the switch's old state for the crash guard.
- (BOOL)dm_setRow:(NSString *)rowId value:(id)value {
    const MSBDDispRow *r = MSBDDispRowById(rowId.UTF8String);
    if (r && r->kind == kMSBDRowScale && _display && [value isKindOfClass:[NSNumber class]]) { DMMoreSpaceSet(_display, [value intValue]); return YES; }   // (Apple's own call: MoreSpace.h)
    if (!r || !_display || !value || !MSBDDispRowForm(r, value)) return NO;
    NSDictionary *all = MSBDDispStoreAll();
    BOOL was = r->kind == kMSBDRowSwitch && [MSBDDispRowShownValue(all, _display, r, NULL) boolValue];
    id stored = r->kind == kMSBDRowSwitch ? (id)([value boolValue] ? (__bridge id)kCFBooleanTrue : (__bridge id)kCFBooleanFalse) : MSBDDispRowForm(r, value);
    BOOL ok = DMDispWrite(_display, r->part, r->key, stored, was, @(r->title));
    DMLog([NSString stringWithFormat:@"[dispsettings] %@: %s set to %@ for this display%@", _display, r->title, stored, ok ? @"" : @" (refused)"]);
    [self dm_reload];
    return ok;
}
- (BOOL)dm_resetRow:(NSString *)rowId {
    const MSBDDispRow *r = MSBDDispRowById(rowId.UTF8String);
    if (!r || !_display) return NO;
    BOOL was = r->kind == kMSBDRowSwitch && [MSBDDispRowShownValue(MSBDDispStoreAll(), _display, r, NULL) boolValue];
    BOOL ok = DMDispWrite(_display, r->part, r->key, nil, was, @(r->title));
    DMLog([NSString stringWithFormat:@"[dispsettings] %@: %s back to %@", _display, r->title, MSBDDispDisplayDefault(r->part, r->key, NULL) ? @"the display default" : @"the iPad's"]);
    [self dm_reload];
    return ok;
}
- (void)dm_useIPadAsk { _askingUseIPad = YES; [self dm_reload]; }
- (void)dm_useIPadConfirmed {
    _askingUseIPad = NO;
    int n = MSBDDispStoreUseIPad(_display);
    DMDispReload();
    DMLog([NSString stringWithFormat:@"[dispsettings] %@: Use iPad Settings, %d change(s) of this display deleted", _display, n]);
    [self dm_reload];
}
// (debug and logs) every shown row as "ROW_ID=value (from) [enabled]"
- (NSString *)dm_state {
    NSDictionary *all = MSBDDispStoreAll();
    BOOL layerOn = MSBDDispStoreLayerOn(all), connected = [MSBDDispStoreConnected(all) containsObject:_display];
    MSBDDispCtx ctx = DMDispCtxFor(_display);
    NSMutableArray *a = [NSMutableArray array];
    for (int i = 0; i < MSBD_DISP_ROW_COUNT; i++) {
        const MSBDDispRow *r = MSBDDispRowAt(i);
        if (!MSBDDispRowShown(r, &ctx)) continue;
        int from = 0; id v = MSBDDispRowShownValue(all, _display, r, &from);
        if (r->kind == kMSBDRowScale) { int now = 0; NSArray *ch = MSBDDispStoreScaleChoices(all, MSBDDispStoreInfo(all, _display), &now); v = [NSString stringWithFormat:@"%d of %lu", now, (unsigned long)ch.count]; }
        [a addObject:[NSString stringWithFormat:@"%s=%@ (%@)%@", r->rowId, v, from == kMSBDDispFromOverride ? @"own" : from == kMSBDDispFromDefault ? @"default" : @"iPad",
                      MSBDDispRowEnabled(r, &ctx, connected, layerOn) ? @"" : @" greyed"]];
    }
    return [NSString stringWithFormat:@"%@ extended %d connected %d layer %d: %@", _display, ctx.extended, connected, layerOn, [a componentsJoinedByString:@", "]];
}
@end

// ---- the iPad's host: a native window ---------------------------------------------------------------------------------------------------------
@interface DMDispSettingsWindow : DMNativeWindow
@property (nonatomic, strong) DMDispSettingsView *settings;
@end
static DMDispSettingsWindow *gDMDispSettingsWindow;
@implementation DMDispSettingsWindow
- (BOOL)dm_handleKey:(UIKey *)key {   // (Esc and Command-W close it, as a Mac's settings window)
    BOOL cmd = (key.modifierFlags & UIKeyModifierCommand) != 0;
    if (key.keyCode == UIKeyboardHIDUsageKeyboardEscape || (cmd && [key.charactersIgnoringModifiers isEqualToString:@"w"])) { [self close]; return YES; }
    return NO;
}
@end
static void DMDispSettingsOpenIPad(NSString *display) {
    DMDispSettingsWindow *w = gDMDispSettingsWindow;
    if (w && ![w.settings.display isEqualToString:display]) { [w close]; w = nil; }
    if (!w) {
        CGRect d = DMNativeDesktop();
        CGFloat width = 460, height = MIN(MAX(320.0, d.size.height - 60.0), 640.0);
        w = [[DMDispSettingsWindow alloc] initWithTitle:@"Display Settings" frame:CGRectMake(round(CGRectGetMidX(d) - width / 2.0), round(CGRectGetMidY(d) - height / 2.0), width, height)];
        w.appName = @"Display Settings";
        w.minSize = CGSizeMake(380, 300);
        DMDispSettingsView *v = [[DMDispSettingsView alloc] initWithDisplay:display];
        v.frame = w.contentView.bounds; v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [w.contentView addSubview:v];
        w.settings = v;
        CGFloat want = [v dm_contentHeightForWidth:width] + kNWTitleH;
        if (want < height) { CGRect f = w.frame; f.size.height = MAX(300.0, want); f.origin.y = round(CGRectGetMidY(d) - f.size.height / 2.0); w.frame = f; }
        w.onClose = ^(DMNativeWindow *x) { if (gDMDispSettingsWindow == x) gDMDispSettingsWindow = nil; DMLog(@"[dispsettings] the iPad's window closed"); };
        gDMDispSettingsWindow = w;
    }
    [w show];
    DMLog([NSString stringWithFormat:@"[dispsettings] the iPad's window for %@ shown at %@", display, NSStringFromCGRect(w.frame)]);
}

// ---- the TV's host: a panel in the TV's own scene ---------------------------------------------------------------------------------------------
static UIWindow *gDMDispPanelWindow;
static UIView *gDMDispPanel;
static id gDMDispPanelLock;   // (SpringBoard holds the keys while the panel is the key target: Esc closes it)
static BOOL gDMDispPanelKeys;  // (the panel is the key target: opened, or clicked last)
static id DMDispPanelHitTest(UIWindow *self, SEL _cmd, CGPoint p, UIEvent *e) {   // (only the panel takes events; the rest passes through)
    for (UIView *v in [self.subviews reverseObjectEnumerator]) {
        if (v.hidden || v.alpha < 0.01) continue;
        UIView *h = [v hitTest:[v convertPoint:p fromView:self] withEvent:e];
        if (h) return h;
    }
    return nil;
}
static BOOL DMDispPanelAXEscape(UIWindow *self, SEL _cmd) { if (!gDMDispPanel) return NO; DMDispPanelClose(@"the escape gesture"); return YES; }
@interface DMDispPanelMover : NSObject
@property (nonatomic, assign) CGPoint start;
@end
@implementation DMDispPanelMover
- (void)pan:(UIPanGestureRecognizer *)g {   // (moved by its title bar, kept on the TV)
    UIView *p = gDMDispPanel, *w = p.superview;
    if (!p || !w) return;
    if (g.state == UIGestureRecognizerStateBegan) self.start = p.center;
    CGPoint t = [g translationInView:w];
    CGFloat hw = p.bounds.size.width / 2.0, hh = p.bounds.size.height / 2.0;
    p.center = CGPointMake(MIN(MAX(self.start.x + t.x, hw), w.bounds.size.width - hw), MIN(MAX(self.start.y + t.y, hh + 24.0), w.bounds.size.height - 40.0));
}
@end
static DMDispPanelMover *gDMDispPanelMover;
// The keys, as a native window has them (NativeWindow.h DMNativeFocus): the panel holds SpringBoard's keyboard focus only while it is the key target --
// when it opens and after a click in it --, and a click anywhere else (an app's window on the TV or on the iPad, our bar, the desktop) gives the keys
// back, so typing reaches what was clicked and Esc there is that app's. It is a pass-through window: what lies beside it stays usable while it is open.
static void DMDispPanelKeys(BOOL take, NSString *why) {
    if (!gDMDispPanel) take = NO;
    BOOL was = gDMDispPanelKeys;
    gDMDispPanelKeys = take;
    if (take && !gDMDispPanelLock && gDMDispPanelWindow && DMHardwareKeyboardAttached()) gDMDispPanelLock = DMSpringBoardFocusLock(gDMDispPanelWindow, @"MacStatusBar Display Settings");
    if (!take && gDMDispPanelLock) { id l = gDMDispPanelLock; gDMDispPanelLock = nil; MSBDFocusUnlock(l); }
    if (was != take) DMLog([NSString stringWithFormat:@"[dispsettings] the TV's panel %@ (%@; SpringBoard holds the keys %d)", take ? @"has the keys" : @"gave the keys back", why, gDMDispPanelLock != nil]);
}
// Which a touch is: in the panel (its own view, or a point inside it on its screen: the system gestures' copy of the touch), or anywhere else.
__attribute__((noinline)) static void DMDispPanelTouch(UIEvent *event) {
    UIView *p = gDMDispPanel;
    if (!p.window) return;
    for (UITouch *t in event.allTouches) {
        if (t.phase != UITouchPhaseBegan || t.type == UITouchTypeIndirect) continue;   // (a finger or a click decides, as for the native windows; a trackpad's scroll or move does not)
        BOOL inside = t.view && [t.view isDescendantOfView:p];
        UIWindow *tw = t.window;
        if (!inside && tw && tw.screen == p.window.screen) {
            CGPoint sp = [tw convertPoint:[t locationInView:nil] toCoordinateSpace:tw.screen.coordinateSpace];
            inside = [p pointInside:[p convertPoint:sp fromCoordinateSpace:p.window.screen.coordinateSpace] withEvent:nil];
        }
        DMDispPanelKeys(inside, inside ? @"a click in it" : @"a click elsewhere");
        return;
    }
}
// SpringBoard's -sendEvent: sees every touch (an app's too, through the system gestures' window on each display): hooked once, at the first panel, and
// only passed on (the crash map passes over it: tools/crashmap-rules.txt).
static void (*o_DMDispPanelSendEvent)(id, SEL, UIEvent *);
__attribute__((noinline)) static void DMDispPanelSendEvent(id self, SEL _cmd, UIEvent *event) {
    if (gDMDispPanel && event.type == UIEventTypeTouches) DMDispPanelTouch(event);
    o_DMDispPanelSendEvent(self, _cmd, event);
}
static void DMDispPanelWatchTouches(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    Class sb = objc_getClass("SpringBoard"); SEL s = @selector(sendEvent:);
    if (sb && class_getInstanceMethod(sb, s)) MSHookMessageEx(sb, s, (IMP)DMDispPanelSendEvent, (IMP *)&o_DMDispPanelSendEvent);
    else DMLog(@"[dispsettings] no -[SpringBoard sendEvent:]: the TV's panel keeps the keys while it is open");
}
static void DMDispPanelClose(NSString *why) {
    UIView *p = gDMDispPanel; UIWindow *w = gDMDispPanelWindow;
    gDMDispPanel = nil;
    gDMDispPanelKeys = NO;
    id lock = gDMDispPanelLock; gDMDispPanelLock = nil;
    if (lock) MSBDFocusUnlock(lock);
    [p removeFromSuperview];
    if (w && !w.subviews.count) w.hidden = YES;
    if (p) DMLog([NSString stringWithFormat:@"[dispsettings] the TV's panel closed (%@)", why]);
}
static void DMDispSettingsOpenTV(NSString *display) {
    UIScreen *screen = DMDispDesktopScreen(display, DMDispScreens());
    UIWindow *w = DMSceneLayer(screen, @"dispsettings", kMenuWindowLevel - 1, (DMSceneLayerKind){ "MSBDispSettingsWindow", (IMP)DMDispPanelHitTest, (IMP)DMDispPanelAXEscape, "dispsettings" },
                               ^(NSArray<UIWindow *> *gone) { for (UIWindow *x in gone) if (x == gDMDispPanelWindow) { DMDispPanelClose(@"its display went away"); gDMDispPanelWindow = nil; } });
    if (!w) { DMLog([NSString stringWithFormat:@"[dispsettings] %@: no scene of SpringBoard's on that display: the iPad's window instead", display]); DMDispSettingsOpenIPad(display); return; }
    if (gDMDispPanel) DMDispPanelClose(@"opened again");
    gDMDispPanelWindow = w;
    w.overrideUserInterfaceStyle = DMSystemInterfaceStyle();
    const CGFloat W = 480.0, T = 30.0;
    DMDispSettingsView *v = [[DMDispSettingsView alloc] initWithDisplay:display];
    CGFloat H = MIN(MAX(300.0, [v dm_contentHeightForWidth:W] + T), w.bounds.size.height - 120.0);
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(round((w.bounds.size.width - W) / 2.0), round((w.bounds.size.height - H) / 2.0), W, H)];
    panel.layer.shadowColor = [UIColor blackColor].CGColor; panel.layer.shadowOpacity = 0.3; panel.layer.shadowRadius = 24.0; panel.layer.shadowOffset = CGSizeMake(0, 12.0);
    panel.accessibilityViewIsModal = YES;
    UIView *card = [[UIView alloc] initWithFrame:panel.bounds];
    card.backgroundColor = [UIColor systemBackgroundColor];
    card.layer.cornerRadius = kNWCorner; card.layer.cornerCurve = kCACornerCurveContinuous; card.clipsToBounds = YES;
    card.layer.borderWidth = 0.5; card.layer.borderColor = [UIColor colorWithWhite:0.5 alpha:0.35].CGColor;
    [panel addSubview:card];
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, T)];
    bar.backgroundColor = [UIColor secondarySystemBackgroundColor];
    UILabel *title = [[UILabel alloc] initWithFrame:bar.bounds];
    title.text = @"Display Settings"; title.textAlignment = NSTextAlignmentCenter; title.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [bar addSubview:title];
    UIButton *red = [UIButton buttonWithType:UIButtonTypeCustom];   // (the red light: closes it; its touch area round it)
    red.frame = CGRectMake(2, -1, 32, 32);
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(11, 9, 14, 14)];
    dot.backgroundColor = DMLightColor(0); dot.layer.cornerRadius = 7; dot.userInteractionEnabled = NO;
    [red addSubview:dot];
    red.accessibilityLabel = @"Close";
    [red addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { DMDispPanelClose(@"the red light"); }] forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:red];
    if (!gDMDispPanelMover) gDMDispPanelMover = [DMDispPanelMover new];
    [bar addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:gDMDispPanelMover action:@selector(pan:)]];
    [card addSubview:bar];
    v.frame = CGRectMake(0, T, W, H - T); v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [card addSubview:v];
    [w addSubview:panel];
    gDMDispPanel = panel;
    w.hidden = NO;
    DMDispPanelWatchTouches();
    DMDispPanelKeys(YES, @"opened");
    DMLog([NSString stringWithFormat:@"[dispsettings] the TV's panel for %@ shown at %@ (window level %.1f, keys held %d)", display, NSStringFromCGRect(panel.frame), w.windowLevel, gDMDispPanelLock != nil]);
}
// Esc on the TV's panel (SpringBoard's -pressesBegan:withEvent:, DMOverlayPressesBegan; a menu open closes first), while it is the key target: Esc with
// another window clicked since is that window's.
static BOOL DMDispPanelEscape(NSSet<UIPress *> *presses) {
    if (!gDMDispPanel || !gDMDispPanelKeys) return NO;
    for (UIPress *p in presses) if (p.key.keyCode == UIKeyboardHIDUsageKeyboardEscape) { DMDispPanelClose(@"Esc"); return YES; }
    return NO;
}
static void DMDispSettingsOpen(NSString *display, BOOL onTV) {
    DM_FEATURE_MARK("display-settings-window");
    if (!display || !gDMDispLayerOn) return;
    if (onTV) DMDispSettingsOpenTV(display); else DMDispSettingsOpenIPad(display);
}

// ---- the start ---------------------------------------------------------------------------------------------------------------------------------
// The Display title comes and goes with a display (its screens one by one: again a moment later).
static void DMDispSettingsInit(void) {
    for (NSString *n in @[UIScreenDidConnectNotification, UIScreenDidDisconnectNotification])
        [[NSNotificationCenter defaultCenter] addObserverForName:n object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            for (UIView *fg in gCopies.allObjects) [fg setNeedsLayout];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ for (UIView *fg in gCopies.allObjects) [fg setNeedsLayout]; });
        }];
}

#if DEBUG
// dset_open_ipad / dset_open_tv: Display Settings for the connected display on that host; dset_state: what the open views show; dset_set_<ROW>_<v>
// (switch 0 / 1, choice index, slider number), dset_reset_<ROW>, dset_useipad_ask, dset_useipad_ok, dset_close: through each open view's own actions.
static BOOL DMDispSettingsTrigger(NSString *cmd) {
    NSString *display = DMDispMenuDisplayOf(nil);
    if ([cmd isEqualToString:@"dset_open_ipad"] || [cmd isEqualToString:@"dset_open_tv"]) { DMDispSettingsOpen(display, [cmd hasSuffix:@"tv"]); return YES; }
    if ([cmd isEqualToString:@"dset_close"]) { [gDMDispSettingsWindow close]; DMDispPanelClose(@"dset_close"); return YES; }
    NSArray<DMDispSettingsView *> *views = gDMDispViews.allObjects;
    if ([cmd isEqualToString:@"dset_state"]) {
        DMLog([NSString stringWithFormat:@"[dispsettings] state: %lu view(s); window %d panel %d", (unsigned long)views.count, gDMDispSettingsWindow != nil, gDMDispPanel != nil]);
        for (DMDispSettingsView *v in views) if (v.window) DMLog([NSString stringWithFormat:@"[dispsettings]   %@ on %@: %@", v.window == gDMDispPanelWindow ? @"TV panel" : @"iPad window", NSStringFromCGRect([v convertRect:v.bounds toView:nil]), [v dm_state]]);
        return YES;
    }
    for (DMDispSettingsView *v in views) {
        if (!v.window) continue;
        if ([cmd hasPrefix:@"dset_set_"]) {
            NSString *rest = [cmd substringFromIndex:9];
            NSRange u = [rest rangeOfString:@"_" options:NSBackwardsSearch];
            if (u.location == NSNotFound) return YES;
            NSString *rowId = [rest substringToIndex:u.location], *val = [rest substringFromIndex:u.location + 1];
            const MSBDDispRow *r = MSBDDispRowById(rowId.UTF8String);
            if (!r) return YES;
            id value = r->kind == kMSBDRowSwitch ? @([val intValue] != 0) : (r->kind == kMSBDRowChoice && r->choiceValues[0]) ? (id)@(r->choiceValues[MAX(0, MIN(r->choices - 1, [val intValue]))])
                     : r->kind == kMSBDRowChoice ? (id)@([val intValue]) : (id)@([val doubleValue]);
            [v dm_setRow:rowId value:value];
        } else if ([cmd hasPrefix:@"dset_reset_"]) [v dm_resetRow:[cmd substringFromIndex:11]];
        else if ([cmd isEqualToString:@"dset_useipad_ask"]) [v dm_useIPadAsk];
        else if ([cmd isEqualToString:@"dset_useipad_ok"]) [v dm_useIPadConfirmed];
        return YES;   // (one view acts: the window and the panel write the same keys)
    }
    return [cmd hasPrefix:@"dset_"];
}
#endif
