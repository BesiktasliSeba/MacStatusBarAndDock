// test-badgehide.m -- Mac test (Mac Catalyst: UIKit on the Mac) of Settings' badge hide (macsettings/Badge.x), as Logos builds it.
// 1.8.7.7: the view-level hide stuck to the badge view. SpringBoard reuses its badge views: the one taken off Settings' icon goes on another app's
// icon later, and stayed hidden there (M1: Sileo's stored 7 missing from the Dock after a respring; its SBIconBadgeView text '6', hidden YES, in
// the 16 Nov note). The hide must follow the view: held while the view is in a hidden app's icon view, SpringBoard's own last hidden / alpha back
// once it is in another app's or a folder's icon view, only what we did undone; taken off (no superview: not drawn) and in between (no icon view,
// an icon view without an icon) as before, also when it comes back onto Settings' icon inside another view (review of the fix, F1: that move
// reaches none of the badge view's hooks, so a hide undone when it was taken off showed Settings' badge there).
// test-badgehide.sh runs Badge.x (BADGE_X: another copy, e.g. the code before the fix) through Theos's logos.pl and builds the output with this
// file: the stand-in SpringBoard classes below (SBIconView, SBIconBadgeView, SBApplicationIcon) and MSHookMessageEx as Substrate does it (a method
// the class has: replaced; one it inherits: added, the original being the superclass's). The chain is the one Badge.x logged on the M1's 15.6.1:
// SBIconBadgeView < SBIconImageView < SBFTouchPassThroughView < SBIconView.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ---- Substrate, as it hooks a message
static NSMutableArray<NSString *> *gHooks;
void MSHookMessageEx(Class cls, SEL sel, IMP hook, IMP *old) {
    if (!gHooks) gHooks = [NSMutableArray array];
    Method m = cls ? class_getInstanceMethod(cls, sel) : NULL;
    if (!m) { if (old) *old = NULL; return; }
    [gHooks addObject:[NSString stringWithFormat:@"%s %@", class_getName(cls), NSStringFromSelector(sel)]];
    unsigned n = 0; BOOL own = NO;
    Method *ms = class_copyMethodList(cls, &n);
    for (unsigned i = 0; i < n; i++) if (ms[i] == m) own = YES;
    free(ms);
    if (own) { IMP was = method_setImplementation(m, hook); if (old) *old = was; }
    else { IMP sup = method_getImplementation(m); class_addMethod(cls, sel, hook, method_getTypeEncoding(m)); if (old) *old = sup; }
}

// ---- SpringBoard, stood in
@interface SBApplicationIcon : NSObject   // (an app's icon: the model)
@property (nonatomic, copy) NSString *kBundle;
@property (nonatomic, strong) id kBadge;
@end
@implementation SBApplicationIcon
- (NSString *)applicationBundleID { return self.kBundle; }
- (id)badgeNumberOrString { return self.kBadge; }
@end
@interface KFolderIcon : NSObject @end   // (a folder's icon: an icon, no app)
@implementation KFolderIcon @end

@interface SBIconView : UIView
@property (nonatomic, strong) id icon;
@property (nonatomic, strong) UIView *kImage;   // (SBIconImageView, inside SBFTouchPassThroughView)
@end
@implementation SBIconView
- (NSString *)applicationBundleIdentifier { return [self.icon respondsToSelector:@selector(applicationBundleID)] ? [self.icon applicationBundleID] : nil; }
@end
@interface KLibraryIconView : SBIconView @end   // (another kind of icon view: the App Library's, a folder's grid)
@implementation KLibraryIconView @end

static int gLayouts;
@interface SBIconBadgeView : UIView @end   // (lays out its text: its own -layoutSubviews; the rest is UIView's)
@implementation SBIconBadgeView
- (void)layoutSubviews { [super layoutSubviews]; gLayouts++; }
@end

static SBApplicationIcon *AppIcon(NSString *bundle, id badge) { SBApplicationIcon *i = [SBApplicationIcon new]; i.kBundle = bundle; i.kBadge = badge; return i; }
static SBIconView *IconView(id icon, Class cls) {
    SBIconView *v = [[(cls ?: [SBIconView class]) alloc] initWithFrame:CGRectMake(0, 0, 60, 60)];
    v.icon = icon;
    UIView *pass = [[UIView alloc] initWithFrame:v.bounds], *image = [[UIView alloc] initWithFrame:v.bounds];
    [v addSubview:pass]; [pass addSubview:image]; v.kImage = image;
    return v;
}
static SBIconBadgeView *Badge(void) { return [[SBIconBadgeView alloc] initWithFrame:CGRectMake(44, -6, 22, 22)]; }
static void Put(UIView *badge, SBIconView *iv) { [iv.kImage addSubview:badge]; }   // (SpringBoard puts its accessory on an icon)
static void Layout(UIView *badge) { int was = gLayouts; [badge setNeedsLayout]; [badge layoutIfNeeded]; if (gLayouts == was) [badge layoutSubviews]; }
static UIView *Box(void) { return [[UIView alloc] initWithFrame:CGRectMake(0, 0, 60, 60)]; }   // (another view the badge view can go into)
static SBIconView *IconViewOf(UIView *badge) { for (UIView *v = badge.superview; v; v = v.superview) if ([v isKindOfClass:[SBIconView class]]) return (SBIconView *)v; return nil; }

static int gChecks, gFails;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
static BOOL Drawn(UIView *b, CGFloat alpha) { return !b.hidden && !b.layer.hidden && fabs(b.alpha - alpha) < 1e-6; }
static NSString *State(UIView *b) { return [NSString stringWithFormat:@"hidden %d, alpha %.2f", b.hidden, b.alpha]; }

int main(void) {
    @autoreleasepool {
        SBApplicationIcon *settings = AppIcon(@"com.apple.Preferences", @3), *sileo = AppIcon(@"org.coolstar.SileoStore", @7), *notes = AppIcon(@"com.apple.mobilenotes", @"New");
        SBIconView *setV = IconView(settings, nil), *silV = IconView(sileo, nil), *notV = IconView(notes, nil), *folV = IconView([KFolderIcon new], nil);

        printf("-- the hooks installed\n");
        NSSet *want = [NSSet setWithArray:@[@"SBApplicationIcon badgeNumberOrString", @"SBIconBadgeView didMoveToSuperview", @"SBIconBadgeView layoutSubviews",
                                            @"SBIconBadgeView setHidden:", @"SBIconBadgeView setAlpha:"]];
        Check(gHooks.count == 5 && [[NSSet setWithArray:gHooks] isEqualToSet:want], [NSString stringWithFormat:@"the value hook and the four badge view hooks, nothing else (%@)", [gHooks componentsJoinedByString:@", "]]);

        printf("-- the value (as before)\n");
        Check([settings badgeNumberOrString] == nil, @"Settings' icon reports no badge");
        Check([[sileo badgeNumberOrString] isEqual:@7] && [[notes badgeNumberOrString] isEqual:@"New"], @"another app's number and string badges pass as they are");
        Check([AppIcon(@"com.apple.Preferences", nil) badgeNumberOrString] == nil && [AppIcon(@"org.coolstar.SileoStore", nil) badgeNumberOrString] == nil, @"no badge stays no badge");

        printf("-- the view on Settings' icon\n");
        { UIView *b = Badge(); Put(b, setV);
          Check(b.hidden, [NSString stringWithFormat:@"a badge view put on Settings' icon is hidden (%@)", State(b)]);
          [b setHidden:NO]; Layout(b);
          Check(b.hidden, @"  ... SpringBoard asking it to show, then laying it out: still hidden");
          [b setAlpha:1.0];
          Check(b.hidden && b.alpha == 0.0, [NSString stringWithFormat:@"  ... SpringBoard's alpha 1 held at 0 there (%@)", State(b)]);
          UIView *k = Badge(); SBIconView *lib = IconView(settings, [KLibraryIconView class]); Put(k, lib);
          Check(k.hidden, @"Settings' badge hidden in another kind of icon view (the App Library's, a folder's grid)"); (void)lib; }

        printf("-- reused on another app's icon (the M1's case)\n");
        { UIView *b = Badge(); Put(b, setV); [b removeFromSuperview]; Put(b, silV); Layout(b);
          Check(Drawn(b, 1.0), [NSString stringWithFormat:@"taken off Settings' icon, put on Sileo's: drawn (%@)", State(b)]); }
        { UIView *b = Badge(); Put(b, setV); Put(b, notV);
          Check(Drawn(b, 1.0), [NSString stringWithFormat:@"moved straight from Settings' icon to another app's: drawn (%@)", State(b)]); }
        { UIView *b = Badge(); Put(b, setV); [b removeFromSuperview];
          Check(b.hidden, [NSString stringWithFormat:@"taken off Settings' icon: still hidden while off (not drawn there; ours stays with it) (%@)", State(b)]);
          Put(b, notV); Check(Drawn(b, 1.0), [NSString stringWithFormat:@"  ... then put on another app's icon: SpringBoard's own back at once (%@)", State(b)]); }
        { UIView *b = Badge(); Put(b, setV); [b removeFromSuperview]; Put(b, folV); Layout(b);
          Check(Drawn(b, 1.0), [NSString stringWithFormat:@"put on a folder's icon (its badge): drawn (%@)", State(b)]); }

        printf("-- what SpringBoard asked on Settings' icon, put back after\n");
        { UIView *b = Badge(); Put(b, setV); [b setAlpha:0.2]; [b setAlpha:0.6]; [b setHidden:YES]; [b setHidden:NO]; Layout(b);
          Check(b.hidden && b.alpha == 0.0, @"alpha 0.2 then 0.6, hidden YES then NO asked there: held hidden, alpha 0");
          [b removeFromSuperview]; Put(b, silV);
          Check(Drawn(b, 0.6), [NSString stringWithFormat:@"  ... on Sileo's icon: SpringBoard's last, shown at 0.6 (%@)", State(b)]); }
        { UIView *b = Badge(); Put(b, setV); [b setHidden:YES]; [b removeFromSuperview]; Put(b, silV); Layout(b);
          Check(b.hidden, @"SpringBoard's own hidden YES (no badge to show) asked there: kept after (as before)"); }
        { UIView *b = Badge(); Put(b, setV); [b setAlpha:0.0]; [b removeFromSuperview]; Put(b, silV);
          Check(!b.hidden && b.alpha == 0.0, [NSString stringWithFormat:@"SpringBoard's own alpha 0 asked there: kept after, our hidden undone (%@)", State(b)]); }
        { UIView *b = Badge(); Put(b, silV); [b setHidden:YES]; Put(b, setV); Put(b, notV); Layout(b);
          Check(b.hidden, @"hidden by SpringBoard on Sileo's icon, then on Settings' and back on an app's: still SpringBoard's hidden (as before)");
          [b setHidden:NO]; Check(Drawn(b, 1.0), @"  ... SpringBoard then shows it: drawn"); }
        { UIView *b = Badge(); Put(b, silV); [b setAlpha:0.3]; Put(b, setV); Check(b.hidden, @"alpha 0.3 on Sileo's icon, then on Settings': hidden");
          Put(b, notV); Check(Drawn(b, 0.3), [NSString stringWithFormat:@"  ... back on an app's: only our hidden undone, its 0.3 as it was (%@)", State(b)]); }

        printf("-- in and out, again and again\n");
        { UIView *b = Badge(); SBIconView *places[] = { setV, silV, setV, folV, setV, notV, setV, setV };
          BOOL ok = YES; NSMutableString *trace = [NSMutableString string];
          for (int i = 0; i < 8; i++) {
              if (i % 3 == 0) [b removeFromSuperview];
              Put(b, places[i]); [b setHidden:NO]; [b setAlpha:1.0]; Layout(b);
              BOOL isSet = places[i] == setV, good = isSet ? (b.hidden && b.alpha == 0.0) : Drawn(b, 1.0);
              [trace appendFormat:@"%@ %@%@; ", isSet ? @"Settings" : @"app", State(b), good ? @"" : @" WRONG"]; ok = ok && good;
          }
          Check(ok, [NSString stringWithFormat:@"Settings, Sileo, Settings, folder, Settings, Notes, Settings, Settings (SpringBoard showing it each time): hidden on Settings' icon only (%@)", trace]); }

        printf("-- in between (as before: Settings' badge never shown on the way)\n");
        { UIView *b = Badge(); SBIconView *iv = IconView(settings, nil); Put(b, iv); UIView *image = iv.kImage, *pass = image.superview, *zoom = [UIView new];
          [zoom addSubview:image]; Layout(b);
          Check(b.hidden, @"Settings' icon image taken into a zoom (no icon view), the badge laid out there: still hidden");
          [pass addSubview:image]; Layout(b);
          Check(b.hidden, @"  ... back in Settings' icon view: hidden"); }
        { UIView *b = Badge(); SBIconView *iv = IconView(settings, nil); Put(b, iv); iv.icon = nil; Layout(b);
          Check(b.hidden, @"Settings' icon view being reused (no icon yet), the badge laid out: still hidden");
          iv.icon = settings; Layout(b); Check(b.hidden, @"  ... Settings' icon again: hidden"); }

        printf("-- inside another view (that view's moves reach none of the badge view's hooks: no didMoveToSuperview, no layout)\n");
        { UIView *b = Badge(); Put(b, setV); Layout(b); [b removeFromSuperview]; UIView *box = Box(); [box addSubview:b]; [setV.kImage addSubview:box];
          Check(b.hidden, [NSString stringWithFormat:@"taken off Settings' icon, put in a view, that view put on Settings' icon, the badge not laid out: hidden (review F1) (%@)", State(b)]);
          Layout(b); Check(b.hidden, @"  ... laid out: hidden"); }
        { UIView *b = Badge(); Put(b, setV); [b removeFromSuperview]; [b setAlpha:1.0]; UIView *box = Box(); [box addSubview:b]; [setV.kImage addSubview:box];
          Check(!Drawn(b, 1.0) && b.hidden, [NSString stringWithFormat:@"  ... SpringBoard's alpha 1 asked while it was off: still hidden (%@)", State(b)]); }
        { UIView *b = Badge(); Put(b, setV); UIView *box = Box(); [box addSubview:b]; [setV.kImage addSubview:box];
          Check(b.hidden, @"moved from Settings' icon straight into a view, that view put on Settings' icon: hidden"); }
        { UIView *b = Badge(); Put(b, silV); UIView *box = Box(); [box addSubview:b]; [setV.kImage addSubview:box]; Layout(b);
          Check(b.hidden, @"Sileo's drawn badge in a view, that view put on Settings' icon: hidden at the badge's next layout"); }
        { UIView *b = Badge(); Put(b, setV); [b removeFromSuperview]; UIView *box = Box(); [box addSubview:b]; [silV.kImage addSubview:box];
          printf("INFO  taken off Settings' icon, put in a view, that view put on Sileo's icon, before any hook of the badge view: %s (ours still; as 1.8.7.6 kept it)\n", State(b).UTF8String);
          Layout(b); Check(Drawn(b, 1.0), [NSString stringWithFormat:@"  ... drawn at the badge's next layout (%@)", State(b)]); }
        { UIView *b = Badge(); Put(b, setV); [b removeFromSuperview]; UIView *box = Box(); [box addSubview:b]; [silV.kImage addSubview:box]; [b setAlpha:1.0];
          Check(Drawn(b, 1.0), [NSString stringWithFormat:@"  ... or at SpringBoard's next setAlpha: (%@)", State(b)]); }
        { UIView *b = Badge(); Put(b, setV); [b setAlpha:1.0]; [b removeFromSuperview]; UIView *box = Box(); [box addSubview:b]; [folV.kImage addSubview:box]; [b setHidden:NO];
          Check(Drawn(b, 1.0), [NSString stringWithFormat:@"  ... or at its next setHidden: (on a folder's icon; our alpha 0 undone too) (%@)", State(b)]); }

        printf("-- an icon view reused in place for another app, the badge left on it\n");
        { UIView *b = Badge(); SBIconView *iv = IconView(settings, nil); Put(b, iv); iv.icon = sileo; Layout(b);
          Check(Drawn(b, 1.0), [NSString stringWithFormat:@"Settings' icon view now Sileo's, the badge laid out: drawn (%@)", State(b)]); }
        { UIView *b = Badge(); SBIconView *iv = IconView(settings, nil); Put(b, iv); [b setAlpha:0.5]; iv.icon = sileo; [b setAlpha:0.9];
          Check(Drawn(b, 0.9), [NSString stringWithFormat:@"  ... SpringBoard's alpha the first thing after: drawn at it, our hidden undone too (%@)", State(b)]); }
        { UIView *b = Badge(); SBIconView *iv = IconView(settings, nil); Put(b, iv); [b setAlpha:0.5]; iv.icon = sileo; [b setHidden:NO];
          Check(Drawn(b, 0.5), [NSString stringWithFormat:@"  ... SpringBoard's hidden NO the first thing after: drawn, our alpha 0 undone to its 0.5 (%@)", State(b)]); }

        printf("-- other badges: never touched\n");
        { UIView *b = Badge(); Put(b, silV); BOOL ok = YES;
          for (int i = 0; i < 40; i++) { BOOL h = (i % 3) == 1; CGFloat a = (i % 5) / 4.0; [b setHidden:h]; [b setAlpha:a]; Layout(b); if (i % 7 == 0) { [b removeFromSuperview]; Put(b, i % 2 ? notV : folV); }
                                         ok = ok && b.hidden == h && b.alpha == a; }
          Check(ok, @"a badge view only ever on other icons: every hidden and alpha SpringBoard asks for, as asked"); }

        printf("-- random sequences\n");
        {   // (SpringBoard's own: what it asked for last; the badge view must show exactly that anywhere but on Settings' icon, and be hidden there)
            srand48(1877);
            long steps = 0, onSettings = 0, elsewhere = 0, off = 0, bad = 0; NSString *first = nil;
            for (int s = 0; s < 3000; s++) {
                SBIconView *a = IconView(settings, nil), *bv = IconView(sileo, nil), *c = IconView([KFolderIcon new], nil);
                UIView *b = Badge(); BOOL askH = NO; CGFloat askA = 1.0; NSMutableString *log = [NSMutableString string];
                for (int i = 0; i < 40; i++, steps++) {
                    int op = (int)(lrand48() % 9);
                    switch (op) {
                        case 0: Put(b, a); [log appendString:@"onA "]; break;
                        case 1: Put(b, bv); [log appendString:@"onB "]; break;
                        case 2: Put(b, c); [log appendString:@"onFolder "]; break;
                        case 3: [b removeFromSuperview]; [log appendString:@"off "]; break;
                        case 4: askH = lrand48() % 2; [b setHidden:askH]; [log appendFormat:@"hidden%d ", askH]; break;
                        case 5: askA = (lrand48() % 5) / 4.0; [b setAlpha:askA]; [log appendFormat:@"alpha%.2f ", askA]; break;
                        case 6: Layout(b); [log appendString:@"layout "]; break;
                        case 7: { SBIconView *v = (SBIconView *)b.superview.superview.superview;   // (the icon view it is on, reused in place, laid out)
                                  if (![v isKindOfClass:[SBIconView class]]) break;
                                  v.icon = v.icon == settings ? sileo : settings; Layout(b); [log appendString:@"swapIcon+layout "]; break; }
                        default: Put(b, lrand48() % 2 ? a : bv); [b setHidden:NO]; askH = NO; [log appendString:@"onAorB+show "]; break;   // (a new badge shown)
                    }
                    if (!b.superview) { off++; continue; }   // (taken off: not drawn, not judged)
                    SBIconView *on = (SBIconView *)b.superview.superview.superview;
                    BOOL isSet = [on isKindOfClass:[SBIconView class]] && on.icon == settings, good;
                    if (isSet) { onSettings++; good = b.hidden; }
                    else { elsewhere++; good = b.hidden == askH && fabs(b.alpha - askA) < 1e-6; }
                    if (!good) { bad++; if (!first) first = [NSString stringWithFormat:@"sequence %d: %@-> %@ (%@)", s, log, State(b), isSet ? @"on Settings' icon" : [NSString stringWithFormat:@"asked hidden %d alpha %.2f", askH, askA]]; }
                }
            }
            Check(bad == 0, [NSString stringWithFormat:@"3000 sequences, %ld steps (%ld on Settings' icon, %ld elsewhere, %ld off: not drawn, not judged): hidden on Settings' icon, SpringBoard's own everywhere else%@",
                             steps, onSettings, elsewhere, off, bad ? [NSString stringWithFormat:@" -- %ld wrong; first: %@", bad, first] : @""]);
        }
        {   // (the same, and a view the badge view can go into, put on icons and taken off: moves that reach none of the badge view's hooks. Judged:
            //  after a hook of the badge view in its place (settled): not drawn on Settings' icon, SpringBoard's own on another icon; on Settings' icon
            //  before any: not drawn while it was held there last (no hook on another icon since, no hidden NO and no alpha above 0 asked outside
            //  Settings' icon). Taken off, in between, and on another icon before any hook: not judged.)
            srand48(18772);
            long steps = 0, setSettled = 0, otherSettled = 0, setHeld = 0, notJudged = 0, bad = 0; NSString *first = nil;
            for (int s = 0; s < 3000; s++) {
                SBIconView *a = IconView(settings, nil), *bv = IconView(sileo, nil), *c = IconView([KFolderIcon new], nil), *on3[] = { a, bv, c };
                UIView *b = Badge(), *box = Box(); BOOL askH = NO, settled = YES, held = NO; CGFloat askA = 1.0; NSMutableString *log = [NSMutableString string];
                for (int i = 0; i < 40; i++, steps++) {
                    int op = (int)(lrand48() % 12); BOOL hook = YES, moved = NO, show = NO;   // (hook: reaches a hook of the badge view; moved: its place changed unseen)
                    switch (op) {
                        case 0: case 1: case 2: hook = b.superview != on3[op].kImage; Put(b, on3[op]); [log appendFormat:@"on%c ", "ABF"[op]]; break;
                        case 3: hook = b.superview != nil; [b removeFromSuperview]; [log appendString:@"off "]; break;
                        case 4: askH = lrand48() % 2; show = !askH; [b setHidden:askH]; [log appendFormat:@"hidden%d ", askH]; break;
                        case 5: askA = (lrand48() % 5) / 4.0; show = askA > 0; [b setAlpha:askA]; [log appendFormat:@"alpha%.2f ", askA]; break;
                        case 6: Layout(b); [log appendString:@"layout "]; break;
                        case 7: hook = b.superview != box; [box addSubview:b]; [log appendString:@"intoBox "]; break;
                        case 8: { int t = (int)(lrand48() % 3); hook = NO; moved = b.superview == box && box.superview != on3[t].kImage; [on3[t].kImage addSubview:box];
                                  [log appendFormat:@"boxOn%c ", "ABF"[t]]; break; }
                        case 9: hook = NO; moved = b.superview == box && box.superview; [box removeFromSuperview]; [log appendString:@"boxOff "]; break;
                        case 10: { SBIconView *v = IconViewOf(b); if (!v) { hook = NO; break; }   // (the icon view it is in, reused in place, the badge laid out)
                                   v.icon = v.icon == settings ? sileo : settings; Layout(b); [log appendString:@"swapIcon+layout "]; break; }
                        default: Put(b, lrand48() % 2 ? a : bv); [b setHidden:NO]; askH = NO; show = YES; [log appendString:@"onAorB+show "]; break;
                    }
                    SBIconView *on = IconViewOf(b);
                    BOOL isSet = on && on.icon == settings, isOther = on && on.icon && !isSet;
                    if (moved) settled = NO;
                    if (hook) {
                        settled = YES;
                        if (isSet) held = YES;
                        else if (isOther || show) held = NO;
                    }
                    BOOL notDrawn = b.hidden || b.alpha < 1e-6, good = YES;
                    if (!b.superview || !on) notJudged++;
                    else if (settled && isSet) { setSettled++; good = notDrawn; }
                    else if (settled) { otherSettled++; good = b.hidden == askH && fabs(b.alpha - askA) < 1e-6; }
                    else if (isSet && held) { setHeld++; good = notDrawn; }
                    else notJudged++;
                    if (!good) { bad++; if (!first) first = [NSString stringWithFormat:@"sequence %d: %@-> %@ (%@)", s, log, State(b), isSet ? (settled ? @"on Settings' icon" : @"on Settings' icon, held there last") : [NSString stringWithFormat:@"asked hidden %d alpha %.2f", askH, askA]]; }
                }
            }
            Check(bad == 0, [NSString stringWithFormat:@"3000 sequences through another view, %ld steps (%ld on Settings' icon after a hook, %ld on another icon after a hook, %ld on Settings' icon unseen but held there last, %ld not judged): never drawn on Settings' icon, SpringBoard's own on another icon%@",
                             steps, setSettled, otherSettled, setHeld, notJudged, bad ? [NSString stringWithFormat:@" -- %ld wrong; first: %@", bad, first] : @""]);
        }
        printf("%d checks, %d failed\n", gChecks, gFails);
        return gFails > 40 ? 40 : gFails;   // (the number of failed checks)
    }
}
