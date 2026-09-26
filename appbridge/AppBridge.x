#import <substrate.h>
#if DEBUG
#define MSTestFlag(path) (access((path), F_OK) == 0)   // a /tmp test switch (debug builds only; a release build behaves as if none existed)
#else
#define MSTestFlag(path) 0
#endif
// MacAppBridge: runs inside every app. Mac Status Bar (in SpringBoard) posts the Darwin notification "com.besiktasliseba.appbridge.resign.<hash>" (hash = FNV-1a of the app's
// bundle id, 8 hex digits) and the app with that hash sends "resign first responder" to whatever is typing, which puts its on-screen keyboard away. SpringBoard
// cannot do that itself: the keyboard belongs to the app.
#import <UIKit/UIKit.h>
#import <notify.h>
#import <objc/message.h>
#import <dlfcn.h>   // Dl_info/dladdr — used by the (still-off) idiom experiment below in both debug and release builds; only ever imported inside
                     // the #if DEBUG block before, which a real FINALPACKAGE=1 DEBUG=0 build of this exact file had apparently never caught.

static void MABRegister(void) {
    NSString *bundle = [NSBundle mainBundle].bundleIdentifier;
    if (!bundle.length || [bundle isEqualToString:@"com.apple.springboard"] || ![UIApplication sharedApplication]) return;
    uint32_t hash = 2166136261u;
    for (const char *c = bundle.UTF8String; *c; c++) { hash ^= (uint8_t)*c; hash *= 16777619u; }
    char name[64]; snprintf(name, sizeof name, "com.besiktasliseba.appbridge.resign.%08x", hash);
    static int token = 0;
    notify_register_dispatch(name, &token, dispatch_get_main_queue(), ^(int t) {
        [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder) to:nil from:nil forEvent:nil];
    });
}

// Tells SpringBoard when this app was tapped or clicked (a click of a trackpad or a mouse at once, a finger tap when it did not move), so its window can be
// raised; scrolling and dragging do not count. SpringBoard listens for "com.besiktasliseba.appbridge.touched.<hash>".
static void MABTouched(void) {
    static uint32_t hash = 0; static char name[64]; static CFTimeInterval last = 0;
    if (!hash) {
        NSString *bundle = [NSBundle mainBundle].bundleIdentifier;
        if (!bundle.length || [bundle isEqualToString:@"com.apple.springboard"]) return;
        hash = 2166136261u;
        for (const char *c = bundle.UTF8String; *c; c++) { hash ^= (uint8_t)*c; hash *= 16777619u; }
        snprintf(name, sizeof name, "com.besiktasliseba.appbridge.touched.%08x", hash);
    }
    CFTimeInterval now = CACurrentMediaTime();
    if (now - last < 0.25) return;
    last = now;
    notify_post(name);
    notify_post("com.besiktasliseba.appbridge.anytouch");   // (any app: SpringBoard popovers of ours -- the Dock's Downloads panel -- close on a tap in an app)
}
static NSMutableDictionary<NSValue *, NSArray *> *gTouchStarts;
#if DEBUG
static void MABLog(NSString *line);
#endif

// "Print…"/"Share…" in the app name menu: found and activated the same way VoiceOver would (an accessibilityActivate on whatever looks right), not a
// keyboard shortcut, so it works with no hardware keyboard attached. A Share button is close to universal (the square-and-arrow-up icon, "Share" in
// every language VoiceOver speaks); a dedicated Print button is rarer, so Print falls back to Share when it does not find one of its own — Print is
// usually one of the choices inside the sheet Share opens.
static BOOL MABLabelMatches(NSString *label, NSString *keyword) {
    return label.length && [[label lowercaseString] containsString:keyword];
}
// A bar button item is not a view (no subviews of its own), but it is still an accessibility element with a label — VoiceOver reads a plain system
// "Action" (share) button as "Share", so the label is enough; walked separately from the view hierarchy below.
// A bar button whose OWN accessibilityLabel is empty (Notes' toolbar buttons all are) still has a real answer sitting on its customView, or a lone image
// view inside it — the customView is searched the same way a plain view is; failing that, whatever a tap would actually hit (the item itself, or its
// customView) is handed back so it can at least be tapped, even with no name to go on.
static id MABFindControl(UIView *v, NSString *keyword, int depth);
static id MABFindBarButton(UIViewController *vc, NSString *keyword, int depth) {
    if (!vc || depth > 6) return nil;
    NSArray<UIBarButtonItem *> *all = [[vc.navigationItem.rightBarButtonItems ?: @[] arrayByAddingObjectsFromArray:vc.navigationItem.leftBarButtonItems ?: @[]] arrayByAddingObjectsFromArray:vc.toolbarItems ?: @[]];
    for (UIBarButtonItem *item in all) {
        if (MABLabelMatches(item.accessibilityLabel, keyword)) return item;
        if (item.customView) { id found = MABFindControl(item.customView, keyword, 0); if (found) return found; }
    }
    for (UIViewController *c in vc.childViewControllers) { id found = MABFindBarButton(c, keyword, depth + 1); if (found) return found; }
    if (vc.presentedViewController) { id found = MABFindBarButton(vc.presentedViewController, keyword, depth + 1); if (found) return found; }
    return nil;
}
// A UITabBar's buttons (and some other stock controls) are not accessibility elements themselves at all — VoiceOver instead reads separate proxy
// objects the bar hands out through the classic UIAccessibilityContainer protocol (-accessibilityElementCount / -accessibilityElementAtIndex:), which
// every view can implement whether or not it is one. accessibilityActivate on the PROXY, once found, correctly reaches the real button behind it.
static id MABFindContainerElement(UIView *v, NSString *keyword, int depth) {
    if (!v || depth > 14) return nil;
    if ([v respondsToSelector:@selector(accessibilityElementCount)]) {
        NSInteger n = [v accessibilityElementCount];
        if (n != NSNotFound) for (NSInteger i = 0; i < n; i++) {
            id el = [v accessibilityElementAtIndex:i];
            if (!el) continue;
            NSString *label = [el respondsToSelector:@selector(accessibilityLabel)] ? [el accessibilityLabel] : nil;
            if (MABLabelMatches(label, keyword)) return el;
            if ([el isKindOfClass:[UIView class]]) { id found = MABFindContainerElement(el, keyword, depth + 1); if (found) return found; }
        }
    }
    return nil;
}
static id MABFindControl(UIView *v, NSString *keyword, int depth) {
    if (!v || v.hidden || v.alpha < 0.05 || depth > 14) return nil;
    if (v.isAccessibilityElement && MABLabelMatches(v.accessibilityLabel, keyword)) return v;   // any view can answer for VoiceOver, not only UIControl
    id container = MABFindContainerElement(v, keyword, 0);
    if (container) return container;
    for (UIView *sub in v.subviews) { id found = MABFindControl(sub, keyword, depth + 1); if (found) return found; }
    return nil;
}
static id MABFindAnywhere(NSString *keyword) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSArray<UIWindow *> *windows = [UIApplication sharedApplication].windows;
#pragma clang diagnostic pop
    for (UIWindow *w in windows) { if (w.hidden || !w.rootViewController) continue; id f = MABFindBarButton(w.rootViewController, keyword, 0); if (f) return f; }
    for (UIWindow *w in windows) { if (w.hidden) continue; id f = MABFindControl(w, keyword, 0); if (f) return f; }
    return nil;
}
static BOOL MABAccessibilityTap(id el) {
    if (![el respondsToSelector:@selector(accessibilityActivate)]) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(el, @selector(accessibilityActivate));
}
// Some controls (App Store's own tab bar, and the account/profile button in its nav bar) are not accessibility elements at all — ax=0,
// no label, nothing through the container protocol either — so MABFindAnywhere/MABFindControl never reach them, keyword or no keyword.
// When the class name is already known (found once via a class dump), it is faster and more reliable to search for that directly and
// activate it as an ordinary control, bypassing accessibility entirely.
static id MABFindViewByClassName(UIView *v, NSString *classSubstring, int depth) {
    if (!v || v.hidden || v.alpha < 0.05 || depth > 20) return nil;
    if ([NSStringFromClass([v class]) rangeOfString:classSubstring options:NSCaseInsensitiveSearch].location != NSNotFound) return v;
    for (UIView *sub in v.subviews) { id found = MABFindViewByClassName(sub, classSubstring, depth + 1); if (found) return found; }
    return nil;
}
static id MABFindClassAnywhere(NSString *classSubstring) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSArray<UIWindow *> *windows = [UIApplication sharedApplication].windows;
#pragma clang diagnostic pop
    for (UIWindow *w in windows) { if (w.hidden) continue; id f = MABFindViewByClassName(w, classSubstring, 0); if (f) return f; }
    return nil;
}
// A UIControl found this way has no accessibility label to activate through VoiceOver, but it is a real control all the same: firing its
// own touch-up-inside reaches whatever target/action it was set up with, same as a finger actually tapping it would.
static void MABActivateControl(id v) {
    if ([v isKindOfClass:[UIControl class]]) { [(UIControl *)v sendActionsForControlEvents:UIControlEventTouchUpInside]; return; }
    MABAccessibilityTap(v);   // not a UIControl: fall back on the off chance it is still an accessibility element
}
// (MABTap above, debug-only, is unrelated: a tap-by-index helper for scripted UI testing)
// Many apps put Share (and Print, inside it) behind a secondary "More" button rather than a control labelled "Share" itself — Notes is one. When the
// keyword itself is not found directly, "More" is tried instead, and once whatever it opens (a menu, a popover, an action sheet — all just more view
// hierarchy) has had a moment to appear, the search runs again for the real keyword within that.
static void __attribute__((unused)) MABActivate(NSString *keyword) {
    id found = MABFindAnywhere(keyword);
#if DEBUG
    MABLog([NSString stringWithFormat:@"activate: %@ -> %@", keyword, found ? NSStringFromClass([found class]) : @"not found"]);
#endif
    if (found) { MABAccessibilityTap(found); return; }
    id more = MABFindAnywhere(@"more");
    if (!more) return;
    MABAccessibilityTap(more);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        id foundNow = MABFindAnywhere(keyword);
#if DEBUG
        MABLog([NSString stringWithFormat:@"activate: %@ (after More) -> %@", keyword, foundNow ? NSStringFromClass([foundNow class]) : @"still not found"]);
#endif
        MABAccessibilityTap(foundNow);
    });
}
// ===== Print…/Share… v2 (M1 pipeline task 2, 2026-09-24) ===================================================================================
// Root cause of "Share and Print not working": Apple's own apps (Safari, Notes, Photos, ...) give their toolbar buttons their VoiceOver names through
// accessibility bundles that are only loaded while an assistive technology runs, so the label search above finds nothing (every label is nil; seen
// in Safari: "activate: share -> not found"). What those buttons do carry, always, is their SF Symbol: a Share button shows
// "square.and.arrow.up", a Print button "printer". So the button is found by its symbol first (then by label, for apps that label their buttons).
// When an app has no such button at all, the menu row still does something useful instead of nothing: Print… opens the standard print dialog for
// the app's main content (a web page, a text view, or else a picture of the window), and Share… opens the standard share sheet for the same content.
static UIView *MABFindSymbolView(UIView *v, NSString *symbol, int depth) {
    if (!v || v.hidden || v.alpha < 0.05 || depth > 40) return nil;
    UIImage *img = nil;
    if ([v isKindOfClass:[UIImageView class]]) img = ((UIImageView *)v).image;
    else if ([v isKindOfClass:[UIButton class]]) img = [(UIButton *)v imageForState:UIControlStateNormal] ?: ((UIButton *)v).currentImage;
    if (img && [img.description containsString:[NSString stringWithFormat:@"symbol(system: %@)", symbol]] && !CGRectIsEmpty(v.bounds)) return v;
    for (UIView *sub in v.subviews.reverseObjectEnumerator) { UIView *f = MABFindSymbolView(sub, symbol, depth + 1); if (f) return f; }
    return nil;
}
static BOOL MABTapView(UIView *v) {   // the nearest control around it gets a real touch-up-inside; else it is activated like VoiceOver would
    for (UIView *x = v; x; x = x.superview) {
        if ([x isKindOfClass:[UIControl class]] && ((UIControl *)x).enabled) { [(UIControl *)x sendActionsForControlEvents:UIControlEventTouchUpInside]; return YES; }
        if ([x isKindOfClass:[UIWindow class]]) break;
    }
    return MABAccessibilityTap(v);
}
static UIWindow *MABKeyWindow(void) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIWindow *best = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) { if (w.hidden || !w.rootViewController) continue; if (w.isKeyWindow) return w; if (!best && w.windowLevel == UIWindowLevelNormal) best = w; }
#pragma clang diagnostic pop
    return best;
}
static BOOL MABTapSymbol(NSString *symbol) {
    UIWindow *key = MABKeyWindow();
    UIView *v = key ? MABFindSymbolView(key, symbol, 0) : nil;
    if (!v) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (UIWindow *w in [UIApplication sharedApplication].windows) { if (w == key || w.hidden) continue; v = MABFindSymbolView(w, symbol, 0); if (v) break; }
#pragma clang diagnostic pop
    }
#if DEBUG
    MABLog([NSString stringWithFormat:@"symbol %@ -> %@", symbol, v ? NSStringFromClass([v.superview class]) : @"not found"]);
#endif
    return v ? MABTapView(v) : NO;
}
// The app's main content: the biggest visible web view or text view of the key window.
static UIView *MABMainContentView(void) {
    UIWindow *key = MABKeyWindow(); if (!key) return nil;
    Class web = NSClassFromString(@"WKWebView");
    UIView *best = nil; CGFloat bestArea = 0;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:key];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if (v.hidden || v.alpha < 0.05) continue;
        if ((web && [v isKindOfClass:web]) || ([v isKindOfClass:[UITextView class]] && ((UITextView *)v).text.length)) {
            CGRect r = [v convertRect:v.bounds toView:key]; CGFloat area = CGRectIntersection(r, key.bounds).size.width * CGRectIntersection(r, key.bounds).size.height;
            if (area > bestArea) { bestArea = area; best = v; }
            continue;
        }
        [stack addObjectsFromArray:v.subviews];
    }
    return bestArea > 100 * 100 ? best : nil;
}
static UIImage *MABWindowPicture(void) {
    UIWindow *key = MABKeyWindow(); if (!key) return nil;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithBounds:key.bounds];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) { [key drawViewHierarchyInRect:key.bounds afterScreenUpdates:NO]; }];
}
static UIViewController *MABTopController(void) {
    UIViewController *vc = MABKeyWindow().rootViewController;
    while (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) vc = vc.presentedViewController;
    return vc;
}
static void MABPrintContent(void) {
    UIView *content = MABMainContentView();
    UIPrintInteractionController *pic = [UIPrintInteractionController sharedPrintController];
    UIPrintInfo *info = [UIPrintInfo printInfo];
    info.jobName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"] ?: @"Document";
    pic.printInfo = info;
    pic.printFormatter = nil; pic.printingItem = nil; pic.printPageRenderer = nil;
    if (content) pic.printFormatter = [content viewPrintFormatter];
    else { UIImage *img = MABWindowPicture(); if (!img) return; info.outputType = UIPrintInfoOutputPhoto; pic.printingItem = img; }
    UIWindow *key = MABKeyWindow();
    CGRect anchor = CGRectMake(CGRectGetMidX(key.bounds) - 1, 0, 2, 1);
    [pic presentFromRect:anchor inView:key animated:YES completionHandler:nil];
}
static void MABShareContent(void) {
    UIViewController *top = MABTopController(); if (!top || top.isBeingPresented) return;
    UIView *content = MABMainContentView();
    NSMutableArray *items = [NSMutableArray array];
    if (content && [content respondsToSelector:NSSelectorFromString(@"URL")]) { id url = ((id (*)(id, SEL))objc_msgSend)(content, NSSelectorFromString(@"URL")); if ([url isKindOfClass:[NSURL class]]) [items addObject:url]; }
    if (!items.count && [content isKindOfClass:[UITextView class]]) [items addObject:((UITextView *)content).text];
    if (!items.count) { UIImage *img = MABWindowPicture(); if (img) [items addObject:img]; }
    if (!items.count) return;
    UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
    UIWindow *key = MABKeyWindow();
    avc.popoverPresentationController.sourceView = key;
    avc.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(key.bounds) - 1, 0, 2, 1);
    avc.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionUp;
    [top presentViewController:avc animated:YES completion:nil];
}
static BOOL MABLabelIs(NSString *label, NSString *word) {   // "Share" or "Share…" or "Share Note", not "Shared with You"
    NSString *l = [label lowercaseString];
    return l.length && ([l isEqualToString:word] || [l hasPrefix:[word stringByAppendingString:@" "]] || [l hasPrefix:[word stringByAppendingString:@"…"]]);
}
static void MABShareOrPrint(BOOL print) {
    if (print) {
        if (MABTapSymbol(@"printer")) return;
        id l = MABFindAnywhere(@"print"); if (l && MABLabelIs([l accessibilityLabel], @"print")) { MABAccessibilityTap(l); return; }
        MABPrintContent();
    } else {
        if (MABTapSymbol(@"square.and.arrow.up")) return;
        id l = MABFindAnywhere(@"share"); if (l && MABLabelIs([l accessibilityLabel], @"share")) { MABAccessibilityTap(l); return; }
        MABShareContent();
    }
}
#if DEBUG
static void MABDumpClasses(void) {
    NSMutableString *out = [NSMutableString stringWithString:@"classes:"];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.hidden) continue;
        [out appendFormat:@"\nwindow %@ %@", NSStringFromClass([w class]), NSStringFromCGRect(w.bounds)];
        void (^walk)(UIView *, int); __block __weak void (^weakWalk)(UIView *, int);
        void (^walkImpl)(UIView *, int) = ^(UIView *v, int depth) {
            if (!v || depth > 16) return;
            NSMutableString *pad = [NSMutableString string]; for (int i = 0; i < depth; i++) [pad appendString:@"  "];
            [out appendFormat:@"\n%@%@ ax=%d label=\"%@\"", pad, NSStringFromClass([v class]), v.isAccessibilityElement, v.accessibilityLabel];
            for (UIView *sub in v.subviews) weakWalk(sub, depth + 1);
        };
        walk = walkImpl; weakWalk = walkImpl;
        walk(w, 0);
    }
#pragma clang diagnostic pop
    MABLog(out);
}
static void MABDumpControls(void) {
    NSMutableString *out = [NSMutableString stringWithString:@"controls:"];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.hidden) continue;
        void (^walk)(UIView *, int); __block __weak void (^weakWalk)(UIView *, int);
        void (^walkImpl)(UIView *, int) = ^(UIView *v, int depth) {
            if (!v || v.hidden || v.alpha < 0.05 || depth > 10) return;
            if ([v isKindOfClass:[UIControl class]] && v.accessibilityLabel.length) [out appendFormat:@"\n  view %@ label \"%@\"", NSStringFromClass([v class]), v.accessibilityLabel];
            for (UIView *sub in v.subviews) weakWalk(sub, depth + 1);
        };
        walk = walkImpl; weakWalk = walkImpl;
        walk(w, 0);
        if (w.rootViewController) {
            void (^dumpVC)(UIViewController *, int); __block __weak void (^weakDumpVC)(UIViewController *, int);
            void (^dumpVCImpl)(UIViewController *, int) = ^(UIViewController *vc, int depth) {
                if (!vc || depth > 8) return;
                for (UIBarButtonItem *item in vc.navigationItem.rightBarButtonItems) [out appendFormat:@"\n  rbar %@ label \"%@\"", NSStringFromClass([vc class]), item.accessibilityLabel];
                for (UIBarButtonItem *item in vc.navigationItem.leftBarButtonItems) [out appendFormat:@"\n  lbar %@ label \"%@\"", NSStringFromClass([vc class]), item.accessibilityLabel];
                for (UIBarButtonItem *item in vc.toolbarItems) [out appendFormat:@"\n  tbar %@ label \"%@\"", NSStringFromClass([vc class]), item.accessibilityLabel];
                for (UIViewController *c in vc.childViewControllers) weakDumpVC(c, depth + 1);
                if (vc.presentedViewController) weakDumpVC(vc.presentedViewController, depth + 1);
            };
            dumpVC = dumpVCImpl; weakDumpVC = dumpVCImpl;
            dumpVC(w.rootViewController, 0);
        }
    }
#pragma clang diagnostic pop
    MABLog(out);
}
#endif
static void MABRegisterActions(void) {
    NSString *bundle = [NSBundle mainBundle].bundleIdentifier;
    if (!bundle.length || [bundle isEqualToString:@"com.apple.springboard"]) return;
    uint32_t hash = 2166136261u; for (const char *c = bundle.UTF8String; *c; c++) { hash ^= (uint8_t)*c; hash *= 16777619u; }
    static int tokenShare = 0, tokenPrint = 0;
    char name[64];
    snprintf(name, sizeof name, "com.besiktasliseba.appbridge.share.%08x", hash);
    notify_register_dispatch(name, &tokenShare, dispatch_get_main_queue(), ^(int t) { MABShareOrPrint(NO); });
#if DEBUG
    static int tokenDump = 0;
    snprintf(name, sizeof name, "com.besiktasliseba.appbridge.dumpctrl.%08x", hash);
    notify_register_dispatch(name, &tokenDump, dispatch_get_main_queue(), ^(int t) { MABDumpControls(); });
    static int tokenDumpCls = 0;
    snprintf(name, sizeof name, "com.besiktasliseba.appbridge.dumpcls.%08x", hash);
    notify_register_dispatch(name, &tokenDumpCls, dispatch_get_main_queue(), ^(int t) { MABDumpClasses(); });
    // taptabbutton: one-off test helper for the Arcade->Updates tab rename — finds the actual on-screen UITabBarButton whose label now reads
    // "Updates" and fires its own touch-up-inside, exercising the exact same path a finger tap on it would (through the real UITabBarController
    // delegate callback), not the account button directly.
    static int tokenTapTabButton = 0;
    snprintf(name, sizeof name, "com.besiktasliseba.appbridge.taptabbutton.%08x", hash);
    notify_register_dispatch(name, &tokenTapTabButton, dispatch_get_main_queue(), ^(int t) {
        // The label sits at a different depth under different buttons (confirmed by a class dump: some buttons wrap it in an extra view, some do
        // not), so this looks for the label itself anywhere in the tree, then walks back UP to the nearest UITabBarButton ancestor to tap.
        __block id found = nil;
        void (^walk)(UIView *, int); __block __weak void (^weakWalk)(UIView *, int);
        void (^walkImpl)(UIView *, int) = ^(UIView *v, int depth) {
            if (!v || found || depth > 20) return;
            if ([NSStringFromClass([v class]) isEqualToString:@"UITabBarButtonLabel"]) {
                NSString *text = [v respondsToSelector:@selector(text)] ? ((NSString *(*)(id, SEL))objc_msgSend)(v, @selector(text)) : nil;
                MABLog([NSString stringWithFormat:@"taptabbutton: saw label text=\"%@\"", text]);
                if ([text isEqualToString:@"Updates"]) {
                    UIView *ancestor = v.superview;
                    while (ancestor && ![NSStringFromClass([ancestor class]) isEqualToString:@"UITabBarButton"]) ancestor = ancestor.superview;
                    found = ancestor ?: v;
                    return;
                }
            }
            for (UIView *sub in v.subviews) weakWalk(sub, depth + 1);
        };
        walk = walkImpl; weakWalk = walkImpl;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (UIWindow *w in [UIApplication sharedApplication].windows) { if (w.hidden) continue; walk(w, 0); if (found) break; }
#pragma clang diagnostic pop
        MABLog([NSString stringWithFormat:@"taptabbutton: %@ (%@)", found ? @"found, tapping" : @"not found", found ? NSStringFromClass([found class]) : @""]);
        if (found && [found isKindOfClass:[UIControl class]]) [(UIControl *)found sendActionsForControlEvents:UIControlEventTouchUpInside];
    });
#endif
    snprintf(name, sizeof name, "com.besiktasliseba.appbridge.print.%08x", hash);
    notify_register_dispatch(name, &tokenPrint, dispatch_get_main_queue(), ^(int t) {
        MABShareOrPrint(YES);   // a Print button if the app has one, else the standard print dialog for the app's content (see MABShareOrPrint)
    });
    // "Check for Updates…": the App Store's own Updates tab has had no working itms-apps:// deep link since its iOS 13 redesign, and its tab bar
    // exposes nothing to VoiceOver at all (every button ax=0, no label, nothing through the container protocol either — confirmed by a full class
    // dump), so it can't be found or tapped that way. The account/profile avatar in the nav bar opens the same Updates screen (this is what Lynx's
    // own "Updates" tab actually does under the hood too, and it is why a manual tap on that avatar reaches Updates even in windowed App Store,
    // where Lynx's replacement tab bar button does nothing) — it is a real control, AppStore.AccountButton, just with no accessibility label of its
    // own either, so it is found by class name instead and activated directly, bypassing accessibility entirely.
    static int tokenUpdates = 0;
    snprintf(name, sizeof name, "com.besiktasliseba.appbridge.updates.%08x", hash);
    notify_register_dispatch(name, &tokenUpdates, dispatch_get_main_queue(), ^(int t) {
        // Mac Status Bar reposts this several times to survive a cold launch, since a post that arrives before this app's own registration has
        // finished is simply lost (Darwin notifications are not queued) — but the button is a toggle: tapping it again once Updates is already open
        // closes it, and a further post reopens it, which is what made this visibly bounce open/closed/open a few times in a row. A time check alone
        // is not enough to stop that: several of the reposts typically arrive before the very first one has actually found the button and tapped it
        // (that takes a moment on a cold launch), so each starts its own independent retry chain and more than one can succeed within the same
        // instant. gInFlight closes that gap — only one retry chain is ever allowed to be waiting at a time; every post that arrives while one is
        // already in progress, or within a few seconds of the last successful tap, is ignored outright rather than starting a chain of its own.
        static BOOL gInFlight = NO;
        static CFTimeInterval lastActivated = 0;
        if (gInFlight || CACurrentMediaTime() - lastActivated < 8.0) {
#if DEBUG
            MABLog(@"updates: skipped, already in flight or activated recently");
#endif
            return;
        }
        gInFlight = YES;
        // A cold launch of the App Store can still be finishing its own startup when this arrives; retried every half second for a few seconds rather
        // than given up on after one try. A plain self-capturing __block recursive block: safe here since it always terminates within 8 tries.
        __block void (^attempt)(int);
        attempt = ^(int tries) {
            id btn = MABFindClassAnywhere(@"AccountButton");
#if DEBUG
            MABLog([NSString stringWithFormat:@"updates: try %d -> %@", tries, btn ? NSStringFromClass([btn class]) : @"not found"]);
#endif
            if (btn) { lastActivated = CACurrentMediaTime(); gInFlight = NO; MABActivateControl(btn); attempt = nil; return; }
            if (tries <= 0) { gInFlight = NO; attempt = nil; return; }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ attempt(tries - 1); });
        };
        attempt(8);
    });
    // Undo/Redo: the standard UIResponderStandardEditActions selectors, sent the same way the shake-to-undo gesture (or Cmd+Z) reaches an app's own
    // NSUndoManager — works whether or not a hardware keyboard is attached, and needs no button to find.
    static int tokenUndo = 0, tokenRedo = 0;
    snprintf(name, sizeof name, "com.besiktasliseba.appbridge.undo.%08x", hash);
    notify_register_dispatch(name, &tokenUndo, dispatch_get_main_queue(), ^(int t) { [[UIApplication sharedApplication] sendAction:@selector(undo:) to:nil from:nil forEvent:nil]; });
    snprintf(name, sizeof name, "com.besiktasliseba.appbridge.redo.%08x", hash);
    notify_register_dispatch(name, &tokenRedo, dispatch_get_main_queue(), ^(int t) { [[UIApplication sharedApplication] sendAction:@selector(redo:) to:nil from:nil forEvent:nil]; });
}
%hook UIApplication
- (void)sendEvent:(UIEvent *)event {
    %orig;
    if (event.type != UIEventTypeTouches) return;
    if (!gTouchStarts) gTouchStarts = [NSMutableDictionary dictionary];
    for (UITouch *t in event.allTouches) {
        NSValue *key = [NSValue valueWithNonretainedObject:t];
#if DEBUG
        if (MSTestFlag("/tmp/macstatusbar-debug")) {
            CGPoint p = [t locationInView:nil];
            MABLog([NSString stringWithFormat:@"touch: phase %ld type %ld at %@ view %@ window %@", (long)t.phase, (long)t.type, NSStringFromCGPoint(p), NSStringFromClass([t.view class]), NSStringFromClass([t.window class])]);
        }
#endif
        if (t.phase == UITouchPhaseBegan) {
            if (t.type == UITouchTypeIndirectPointer) MABTouched();   // a click
            else { CGPoint p = [t locationInView:nil]; gTouchStarts[key] = @[@(p.x), @(p.y), @(CACurrentMediaTime())]; }
        } else if (t.phase == UITouchPhaseEnded || t.phase == UITouchPhaseCancelled) {
            NSArray *start = gTouchStarts[key];
            if (start && t.phase == UITouchPhaseEnded) {
                CGPoint p = [t locationInView:nil];
                if (hypot(p.x - [start[0] doubleValue], p.y - [start[1] doubleValue]) < 12.0 && CACurrentMediaTime() - [start[2] doubleValue] < 0.8) MABTouched();   // a tap
            }
            [gTouchStarts removeObjectForKey:key];
        }
    }
}
%end

// The Arcade tab, relabelled Updates — the same idea as Lynx's own "useArcadeUpdates" feature (Arcade is the tab App Store itself makes least use
// of, so it is repointed at Updates instead of adding a sixth tab), done here so it also works in windowed App Store, where Lynx's own replacement
// button does nothing at all (confirmed: Lynx's relabelled tab opens Updates only when App Store is full screen). Selecting it activates the same
// account/profile button "Check for Updates…" does (com.besiktasliseba.appbridge.updates above, found by class name since it has no accessibility label of
// its own), so both paths behave identically and share the one place that knows how to reach Updates. Scoped to the App Store's own process only:
// this group is not %init'd at all unless the running bundle is com.apple.AppStore (decided once, in %ctor).
%group MABAppStoreTabs
// UITabBarController's own -tabBar:didSelectItem: (the classic, public interception point) never fires for App Store's tab bar — confirmed on
// device: logging its every call, unconditionally, produced nothing at all when the renamed tab was tapped. App Store's tab view is SwiftUI's own
// TabView, which happens to render a real, ordinary UITabBar/UITabBarButton underneath (confirmed by a class dump) but wires selection up to its
// own content switching directly, bypassing the UITabBarControllerDelegate protocol method entirely. The one thing that can't be routed around is
// the button's own touch dispatch: whatever private target/action UITabBar attached to it when it was built, that dispatch still has to go through
// UIControl's own -sendAction:to:forEvent:, so that is where this is intercepted instead — recognizing the button not by target or action (both
// private and unstable across iOS versions) but by the same label text this feature itself set.
static BOOL MABViewIsRenamedUpdatesTab(UIView *v, int depth) {
    if (!v || depth > 12) return NO;
    if ([NSStringFromClass([v class]) isEqualToString:@"UITabBarButtonLabel"]) {
        NSString *text = [v respondsToSelector:@selector(text)] ? ((NSString *(*)(id, SEL))objc_msgSend)(v, @selector(text)) : nil;
        if ([text isEqualToString:@"Updates"]) return YES;
    }
    for (UIView *sub in v.subviews) if (MABViewIsRenamedUpdatesTab(sub, depth + 1)) return YES;
    return NO;
}
%hook UIControl
- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    if ([NSStringFromClass([self class]) isEqualToString:@"UITabBarButton"] && MABViewIsRenamedUpdatesTab((UIView *)self, 0)) {
        id btn = MABFindClassAnywhere(@"AccountButton");
#if DEBUG
        MABLog([NSString stringWithFormat:@"tab button sendAction swallowed -> %@", btn ? NSStringFromClass([btn class]) : @"not found"]);
#endif
        if (btn) MABActivateControl(btn);
        return;   // swallowed: Arcade's own action (whatever it is) never runs, so its content never loads underneath
    }
    %orig;
}
%end
%hook UITabBar
- (void)setItems:(NSArray<UITabBarItem *> *)items animated:(BOOL)animated {
    for (UITabBarItem *it in items) {
        if ([it.title isEqualToString:@"Arcade"]) {
            it.title = @"Updates";
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:23 weight:UIImageSymbolWeightRegular];
            it.image = [UIImage systemImageNamed:@"arrow.down.circle" withConfiguration:cfg];
            it.selectedImage = [UIImage systemImageNamed:@"arrow.down.circle.fill" withConfiguration:cfg];
            break;
        }
    }
    %orig;
}
%end
%end

#if DEBUG
#import <dlfcn.h>
#import <objc/runtime.h>
#import <objc/message.h>
// Debug log in the app's own temporary folder (an app cannot log where SpringBoard can read; read it over ssh from the app container tmp folder).
static void MABLog(NSString *line) {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"mab.log"];
    NSString *full = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], line];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!h) { [full writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil]; return; }
    [h seekToEndOfFile]; [h writeData:[full dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile];
}
static BOOL MABHardwareAttached(void) {
    static BOOL (*fn)(void); if (!fn) fn = dlsym(RTLD_DEFAULT, "GSEventIsHardwareKeyboardAttached");
    return fn ? fn() : NO;
}
static void MABListMethods(NSString *className, NSString *keyword) {
    Class c = NSClassFromString(className);
    for (int meta = 0; meta < 2; meta++) {
        unsigned n = 0; Method *l = class_copyMethodList(meta ? object_getClass(c) : c, &n);
        for (unsigned i = 0; i < n; i++) { NSString *name = NSStringFromSelector(method_getName(l[i])); if ([[name lowercaseString] containsString:keyword]) MABLog([NSString stringWithFormat:@"method %@ %@[%@ %@] %s", className, meta ? @"+" : @"-", className, name, method_getTypeEncoding(l[i])]); }
        free(l);
    }
}
static BOOL gForceSoftware = NO;   // hwkb: the app behaves as if no hardware keyboard were attached (UIKit's own answers are overridden below)
static void MABSetHardware(BOOL attached) {
    gForceSoftware = !attached;
    id impl = nil; Class ki = NSClassFromString(@"UIKeyboardImpl");
    if ([ki respondsToSelector:NSSelectorFromString(@"activeInstance")]) impl = ((id (*)(id, SEL))objc_msgSend)((id)ki, NSSelectorFromString(@"activeInstance"));
    SEL changed = NSSelectorFromString(@"hardwareKeyboardAvailabilityChanged");
    if ([impl respondsToSelector:changed]) ((void (*)(id, SEL))objc_msgSend)(impl, changed);
    SEL appChanged = NSSelectorFromString(@"_hardwareKeyboardAvailabilityChanged:");
    if ([[UIApplication sharedApplication] respondsToSelector:appChanged]) ((void (*)(id, SEL, id))objc_msgSend)([UIApplication sharedApplication], appChanged, nil);
    MABLog([NSString stringWithFormat:@"hwkb: forced software keyboard %d (impl %@)", gForceSoftware, impl ? @"yes" : @"no"]);
}
// (plain method swizzling, not Logos hooks: Logos would emit its declarations for these also in release builds, where this block is left out)
static BOOL (*gOrigInHardwareMode)(id, SEL), (*gOrigShouldMinimize)(id, SEL), (*gOrigImplAttached)(id, SEL);
static BOOL MABNewInHardwareMode(id self, SEL _cmd) { return gForceSoftware ? NO : gOrigInHardwareMode(self, _cmd); }
static BOOL MABNewShouldMinimize(id self, SEL _cmd) { return gForceSoftware ? NO : gOrigShouldMinimize(self, _cmd); }
static BOOL MABNewImplAttached(id self, SEL _cmd) { return gForceSoftware ? NO : gOrigImplAttached(self, _cmd); }
static void MABInstallDebugHooks(void) {
    Class ui = NSClassFromString(@"UIKeyboard"), impl = NSClassFromString(@"UIKeyboardImpl");
    Method m = class_getClassMethod(ui, NSSelectorFromString(@"isInHardwareKeyboardMode"));
    if (m) { gOrigInHardwareMode = (BOOL (*)(id, SEL))method_getImplementation(m); method_setImplementation(m, (IMP)MABNewInHardwareMode); }
    m = class_getClassMethod(ui, NSSelectorFromString(@"shouldMinimizeForHardwareKeyboard"));
    if (m) { gOrigShouldMinimize = (BOOL (*)(id, SEL))method_getImplementation(m); method_setImplementation(m, (IMP)MABNewShouldMinimize); }
    m = class_getInstanceMethod(impl, NSSelectorFromString(@"hardwareKeyboardAttached"));
    if (m) { gOrigImplAttached = (BOOL (*)(id, SEL))method_getImplementation(m); method_setImplementation(m, (IMP)MABNewImplAttached); }
}
// Debug builds only: "com.besiktasliseba.appbridge.focus.<hash>" focuses the largest visible text field or text view of the app, so a test can bring the keyboard up
// without a touch.
static void MABFocus(void) {
    UIView *best = nil; CGFloat bestArea = 0;
    #pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSArray<UIWindow *> *windows = [UIApplication sharedApplication].windows;
#pragma clang diagnostic pop
    for (UIWindow *w in windows) {
        if (w.hidden) continue;
        NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
        while (stack.count) {
            UIView *v = stack.lastObject; [stack removeLastObject]; [stack addObjectsFromArray:v.subviews];
            BOOL editable = ([v isKindOfClass:[UITextView class]] && ((UITextView *)v).isEditable) || [v isKindOfClass:[UITextField class]] || ([v conformsToProtocol:@protocol(UIKeyInput)] && [v canBecomeFirstResponder] && ![v isKindOfClass:NSClassFromString(@"WKContentView")]);
            if (!editable || v.hidden || v.alpha < 0.05 || !v.window) continue;
            CGFloat area = v.bounds.size.width * v.bounds.size.height;
            if (area > bestArea) { best = v; bestArea = area; }
        }
    }
    if (!best) {   // Safari: the address field only exists after its button is tapped
        for (UIWindow *w in windows) {
            NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
            while (stack.count) {
                UIView *v = stack.lastObject; [stack removeLastObject]; [stack addObjectsFromArray:v.subviews];
                if ([v isKindOfClass:[UIControl class]] && [NSStringFromClass([v class]) containsString:@"URLButton"] && v.window && !v.hidden) { [(UIControl *)v sendActionsForControlEvents:UIControlEventTouchUpInside]; MABLog(@"focus: address button pressed"); return; }
            }
        }
    }
    // A field that is first responder already (an earlier focus whose keyboard was put away since) does not bring the keyboard up again: give it up first.
    BOOL was = best.isFirstResponder;
    if (was) { [best resignFirstResponder]; [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder) to:nil from:nil forEvent:nil]; }
    if ([best isKindOfClass:[UITextView class]]) { UITextView *tv = (UITextView *)best; MABLog([NSString stringWithFormat:@"focus: candidate %@ frame %@ editable %d selectable %d interaction %d scene state %ld", NSStringFromClass([tv class]), NSStringFromCGRect([tv convertRect:tv.bounds toView:nil]), tv.isEditable, tv.isSelectable, tv.userInteractionEnabled, (long)tv.window.windowScene.activationState]); }
    if ([best isKindOfClass:[UITextView class]] && ![(UITextView *)best isEditable]) {   // (Notes shows a note read-only until it is tapped): a new note is what a person would start
        ((UITextView *)best).editable = YES;
        MABLog([NSString stringWithFormat:@"focus: made it editable, now %d", ((UITextView *)best).isEditable]);
        if (![(UITextView *)best isEditable]) {
            for (UIWindow *w in windows) {
                NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
                while (stack.count) {
                    UIView *v = stack.lastObject; [stack removeLastObject]; [stack addObjectsFromArray:v.subviews];
                    NSString *label = v.accessibilityLabel;
                    if (label.length && v.window && !v.hidden && ([label isEqualToString:@"New Note"] || [label isEqualToString:@"Compose"] || [label isEqualToString:@"New note"])) {
                        BOOL r = [v accessibilityActivate]; MABLog([NSString stringWithFormat:@"focus: activated %@ (%@) %d", label, NSStringFromClass([v class]), r]); return;
                    }
                }
            }
        }
    }
    __block BOOL ok = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((was ? 0.5 : 0.0) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ ok = [best becomeFirstResponder]; if (![best isFirstResponder]) return; [best reloadInputViews]; });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((was ? 2.0 : 1.5) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        Class ki = NSClassFromString(@"UIKeyboardImpl");
        id impl = [ki respondsToSelector:NSSelectorFromString(@"activeInstance")] ? ((id (*)(id, SEL))objc_msgSend)((id)ki, NSSelectorFromString(@"activeInstance")) : nil;
        MABLog([NSString stringWithFormat:@"focus: (was first responder %d) %@ becomeFirstResponder %d, isFirstResponder %d, window key %d, state %ld, keyboard impl %@, hardware mode %d", was, best ? NSStringFromClass([best class]) : @"nothing to focus", ok, best.isFirstResponder, best.window.isKeyWindow, (long)[UIApplication sharedApplication].applicationState, impl ? @"yes" : @"no", MABHardwareAttached()]);
    });
}

// Debug: how an app sees its window (traits, screen, split views), and a stand-in for tapping the k-th row/cell of its biggest list.
static void MABDescribeVC(UIViewController *vc, int depth, NSMutableString *out) {
    if (!vc || depth > 8) return;
    NSString *pad = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
    [out appendFormat:@"\n%@%@ view %@ hSize %ld", pad, NSStringFromClass([vc class]), vc.isViewLoaded ? NSStringFromCGRect([vc.view convertRect:vc.view.bounds toView:nil]) : @"(not loaded)", (long)vc.traitCollection.horizontalSizeClass];
    if ([vc isKindOfClass:[UISplitViewController class]]) {
        UISplitViewController *sp = (UISplitViewController *)vc;
        [out appendFormat:@" [split collapsed %d displayMode %ld preferredMode %ld columns %lu]", sp.isCollapsed, (long)sp.displayMode, (long)sp.preferredDisplayMode, (unsigned long)sp.viewControllers.count];
    }
    if ([vc isKindOfClass:[UINavigationController class]]) [out appendFormat:@" [nav depth %lu]", (unsigned long)((UINavigationController *)vc).viewControllers.count];
    for (UIViewController *c in vc.childViewControllers) MABDescribeVC(c, depth + 1, out);
    if (vc.presentedViewController) { [out appendString:@"\n(presented)"]; MABDescribeVC(vc.presentedViewController, depth + 1, out); }
}
static void MABTraits(void) {
    NSMutableString *out = [NSMutableString stringWithFormat:@"traits: screen %@ scale %.1f idiom %ld", NSStringFromCGRect([UIScreen mainScreen].bounds), [UIScreen mainScreen].scale, (long)[UIDevice currentDevice].userInterfaceIdiom];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        [out appendFormat:@"\nwindow %@ frame %@ hidden %d key %d hSize %ld vSize %ld scene %@", NSStringFromClass([w class]), NSStringFromCGRect(w.frame), w.hidden, w.isKeyWindow, (long)w.traitCollection.horizontalSizeClass, (long)w.traitCollection.verticalSizeClass, w.windowScene ? NSStringFromCGRect(w.windowScene.coordinateSpace.bounds) : @"none"];
        if (!w.hidden && w.rootViewController) MABDescribeVC(w.rootViewController, 1, out);
    }
#pragma clang diagnostic pop
    MABLog(out);
}
// Live call-tracing for the Settings/MilkyWay collapse investigation: samples MABTraits() repeatedly across a window (meant to bracket a
// resize triggered from the SpringBoard side while this runs), so a real resize's effect on EVERY view controller's own traitCollection
// (not just the window's) can be read directly over time, instead of needing to catch a callback on whatever exact subclass happens to
// override it (the lesson from tonight's Ethernet-fix investigation: a swizzle on a base class silently never fires if the real subclass
// overrides the same method itself — polling the actual state sidesteps that entirely, at the cost of only catching changes at whatever
// cadence this samples, not the exact instant).
static void MABTraitWatch(NSInteger seconds) {
    MABLog([NSString stringWithFormat:@"traitwatch: starting, %ld s at 0.4 s intervals", (long)seconds]);
    for (NSInteger i = 0; i <= seconds * 2; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            MABLog([NSString stringWithFormat:@"traitwatch: t=%.1fs", i * 0.4]);
            MABTraits();
        });
    }
}
// Best-effort trace of the two standard UIKit callbacks a real size-class crossing would normally deliver, on the base UIViewController
// class. Caveat, confirmed real tonight (the Ethernet-fix investigation): if Settings' own view controllers override these themselves —
// very likely for a UISplitViewController-based app — this swizzle on the BASE class never fires for THOSE instances, only for whatever
// leaf view controller in the hierarchy happens to not override it. Still informative either way: firing anywhere confirms the callback
// mechanism is alive at all; never firing anywhere is itself a real, if broader, signal. MABTraitWatch above is the more conclusive check.
static void (*gOrigTraitChange)(id, SEL, id);
static void MABNewTraitChange(id self, SEL _cmd, id previous) {
    MABLog([NSString stringWithFormat:@"trace: traitCollectionDidChange: on %@ (was %@ now %@)", NSStringFromClass([self class]), previous, [self respondsToSelector:@selector(traitCollection)] ? ((id (*)(id, SEL))objc_msgSend)(self, @selector(traitCollection)) : @"?"]);
    gOrigTraitChange(self, _cmd, previous);
}
static void (*gOrigTransitionSize)(id, SEL, CGSize, id);
static void MABNewTransitionSize(id self, SEL _cmd, CGSize size, id coordinator) {
    MABLog([NSString stringWithFormat:@"trace: viewWillTransitionToSize: on %@ -> %@", NSStringFromClass([self class]), NSStringFromCGSize(size)]);
    gOrigTransitionSize(self, _cmd, size, coordinator);
}
static void MABInstallTraitTrace(void) {
    Method m = class_getInstanceMethod([UIViewController class], @selector(traitCollectionDidChange:));
    if (m) { gOrigTraitChange = (void (*)(id, SEL, id))method_getImplementation(m); method_setImplementation(m, (IMP)MABNewTraitChange); }
    m = class_getInstanceMethod([UIViewController class], @selector(viewWillTransitionToSize:withTransitionCoordinator:));
    if (m) { gOrigTransitionSize = (void (*)(id, SEL, CGSize, id))method_getImplementation(m); method_setImplementation(m, (IMP)MABNewTransitionSize); }
    MABLog(@"trace: trait/transition trace installed on base UIViewController");
}
static UIView *MABBiggestList(void) {
    UIView *best = nil; CGFloat bestArea = 0;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.hidden) continue;
        NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
        while (stack.count) {
            UIView *v = stack.lastObject; [stack removeLastObject]; [stack addObjectsFromArray:v.subviews];
            if (!([v isKindOfClass:[UITableView class]] || [v isKindOfClass:[UICollectionView class]]) || v.hidden || !v.window) continue;
            CGRect r = [v convertRect:v.bounds toView:nil]; CGFloat a = r.size.width * r.size.height;
            if (a > bestArea) { best = v; bestArea = a; }
        }
    }
#pragma clang diagnostic pop
    return best;
}
static void MABTapAt(NSInteger fixed) {
    UIView *list = MABBiggestList();
    if (!list) { MABLog(@"tap: no list found"); return; }
    NSIndexPath *ip = nil; id delegate = nil; BOOL done = NO;
    if ([list isKindOfClass:[UITableView class]]) {
        UITableView *t = (UITableView *)list; NSArray *vis = t.indexPathsForVisibleRows; static NSUInteger tapCount; ip = vis.count ? vis[(fixed >= 0 ? (NSUInteger)fixed : tapCount++) % vis.count] : nil; delegate = t.delegate;
        if (ip) { [t selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionNone]; if ([delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) { [delegate tableView:t didSelectRowAtIndexPath:ip]; done = YES; } }
    } else {
        UICollectionView *c = (UICollectionView *)list; NSArray *vis = [c.indexPathsForVisibleItems sortedArrayUsingSelector:@selector(compare:)]; static NSUInteger tapCountC; ip = vis.count ? vis[(fixed >= 0 ? (NSUInteger)fixed : tapCountC++) % vis.count] : nil; delegate = c.delegate;
        if (ip) { [c selectItemAtIndexPath:ip animated:NO scrollPosition:UICollectionViewScrollPositionNone]; if ([delegate respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) { [delegate collectionView:c didSelectItemAtIndexPath:ip]; done = YES; } }
    }
    UIView *cell = nil; if (ip) cell = [list isKindOfClass:[UITableView class]] ? [(UITableView *)list cellForRowAtIndexPath:ip] : [(UICollectionView *)list cellForItemAtIndexPath:ip];
    MABLog([NSString stringWithFormat:@"tap: %@ %@ item %@ cell %@ delegate %@ selected via delegate %d", NSStringFromClass([list class]), NSStringFromCGRect([list convertRect:list.bounds toView:nil]), ip, cell ? NSStringFromClass([cell class]) : @"none", delegate ? NSStringFromClass([delegate class]) : @"none", done]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ MABTraits(); });
}
static void MABTap(void) { MABTapAt(-1); }
static UINavigationController *MABTopNav(UIViewController *vc) {
    UINavigationController *found = nil;
    if ([vc isKindOfClass:[UINavigationController class]] && ((UINavigationController *)vc).viewControllers.count > 1) found = (UINavigationController *)vc;
    for (UIViewController *c in vc.childViewControllers) { UINavigationController *n = MABTopNav(c); if (n) found = n; }
    return found;
}
static void MABBack(void) {
    UINavigationController *nav = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *w in [UIApplication sharedApplication].windows) if (!w.hidden && w.rootViewController) { UINavigationController *n = MABTopNav(w.rootViewController); if (n) nav = n; }
#pragma clang diagnostic pop
    if (nav) [nav popViewControllerAnimated:NO];
    MABLog([NSString stringWithFormat:@"back: %@", nav ? [NSString stringWithFormat:@"popped, depth now %lu", (unsigned long)nav.viewControllers.count] : @"nothing to go back to"]);
}

// Debug: trace what an app does to show a new screen (push, present, show, showDetail), with a short call stack from the app's own code.
static void MABTraceCall(NSString *what, id target, id arg) {
    NSMutableString *stack = [NSMutableString string]; int n = 0;
    for (NSString *line in [NSThread callStackSymbols]) {
        if (n++ < 2) continue;
        if ([line containsString:@"Sofascore"] || [line containsString:@"Reminders"]) { [stack appendFormat:@"\n      %@", [line substringFromIndex:MIN((NSUInteger)4, line.length)]]; if (stack.length > 900) break; }
    }
    MABLog([NSString stringWithFormat:@"trace: %@ on %@ arg %@%@", what, NSStringFromClass([target class]), NSStringFromClass([arg class]), stack]);
}
#define MAB_TRACE1(cls, sel, retT) do { Method m = class_getInstanceMethod([cls class], @selector(sel)); if (m) { __block IMP orig = method_getImplementation(m); \
    method_setImplementation(m, imp_implementationWithBlock(^retT(id self, id a, BOOL b) { MABTraceCall(@#sel, self, a); return ((retT (*)(id, SEL, id, BOOL))orig)(self, @selector(sel), a, b); })); } } while (0)
static void MABInstallTrace(void) {
    { Method m = class_getInstanceMethod([UINavigationController class], @selector(pushViewController:animated:)); __block IMP orig = m ? method_getImplementation(m) : NULL;
      if (m) method_setImplementation(m, imp_implementationWithBlock(^void(id self, id vc, BOOL a) { MABTraceCall(@"push", self, vc); ((void (*)(id, SEL, id, BOOL))orig)(self, @selector(pushViewController:animated:), vc, a); })); }
    { Method m = class_getInstanceMethod([UIViewController class], @selector(showDetailViewController:sender:)); __block IMP orig = m ? method_getImplementation(m) : NULL;
      if (m) method_setImplementation(m, imp_implementationWithBlock(^void(id self, id vc, id sender) { MABTraceCall(@"showDetail", self, vc); ((void (*)(id, SEL, id, id))orig)(self, @selector(showDetailViewController:sender:), vc, sender); })); }
    { Method m = class_getInstanceMethod([UIViewController class], @selector(showViewController:sender:)); __block IMP orig = m ? method_getImplementation(m) : NULL;
      if (m) method_setImplementation(m, imp_implementationWithBlock(^void(id self, id vc, id sender) { MABTraceCall(@"show", self, vc); ((void (*)(id, SEL, id, id))orig)(self, @selector(showViewController:sender:), vc, sender); })); }
    { Method m = class_getInstanceMethod([UIViewController class], @selector(presentViewController:animated:completion:)); __block IMP orig = m ? method_getImplementation(m) : NULL;
      if (m) method_setImplementation(m, imp_implementationWithBlock(^void(id self, id vc, BOOL a, id c) { MABTraceCall(@"present", self, vc); ((void (*)(id, SEL, id, BOOL, id))orig)(self, @selector(presentViewController:animated:completion:), vc, a, c); })); }
    { Method m = class_getInstanceMethod([UIApplication class], @selector(openURL:options:completionHandler:)); __block IMP orig = m ? method_getImplementation(m) : NULL;
      if (m) method_setImplementation(m, imp_implementationWithBlock(^void(id self, id url, id o, id c) { MABTraceCall(@"openURL", self, url); ((void (*)(id, SEL, id, id, id))orig)(self, @selector(openURL:options:completionHandler:), url, o, c); })); }
    MABLog(@"trace: installed");
}

// Debug: lists inside the cells of the biggest list (Sofascore's sections are wrapper cells that hold their own lists / stacks): describe them, or select an item of one.
static NSArray<UIView *> *MABAllLists(void) {
    NSMutableArray *found = [NSMutableArray array];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.hidden) continue;
        NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
        while (stack.count) {
            UIView *v = stack.lastObject; [stack removeLastObject]; [stack addObjectsFromArray:v.subviews];
            if (([v isKindOfClass:[UITableView class]] || [v isKindOfClass:[UICollectionView class]]) && !v.hidden && v.window) [found addObject:v];
        }
    }
#pragma clang diagnostic pop
    [found sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) { return [@([a convertRect:a.bounds toView:nil].origin.y) compare:@([b convertRect:b.bounds toView:nil].origin.y)]; }];
    return found;
}
static void MABDescribeLists(void) {
    NSMutableString *out = [NSMutableString stringWithString:@"lists:"];
    NSUInteger i = 0;
    for (UIView *l in MABAllLists()) {
        NSInteger rows = [l isKindOfClass:[UITableView class]] ? [(UITableView *)l numberOfRowsInSection:0] : [(UICollectionView *)l numberOfItemsInSection:0];
        [out appendFormat:@"\n  #%lu %@ %@ items(sec0) %ld delegate %@ dataSource %@", (unsigned long)i++, NSStringFromClass([l class]), NSStringFromCGRect([l convertRect:l.bounds toView:nil]), (long)rows,
            [l isKindOfClass:[UITableView class]] ? NSStringFromClass([[(UITableView *)l delegate] class]) : NSStringFromClass([[(UICollectionView *)l delegate] class]),
            [l isKindOfClass:[UITableView class]] ? NSStringFromClass([[(UITableView *)l dataSource] class]) : NSStringFromClass([[(UICollectionView *)l dataSource] class])];
    }
    MABLog(out);
}
static void MABScrollBy(CGFloat dy) {
    UIView *list = MABBiggestList();
    if (!list) { MABLog(@"scroll: no list found"); return; }
    UIScrollView *sv = (UIScrollView *)list;
    CGPoint p = sv.contentOffset; p.y = MAX(0, MIN(sv.contentSize.height - sv.bounds.size.height, p.y + dy));
    [sv setContentOffset:p animated:NO];
    MABLog([NSString stringWithFormat:@"scroll: %@ to %@", NSStringFromClass([list class]), NSStringFromCGPoint(p)]);
}
static void MABSelectInListSection(NSInteger listIndex, NSInteger item, NSInteger section);
static void MABSelectInList(NSInteger listIndex, NSInteger item) { MABSelectInListSection(listIndex, item, 1); }
static void MABSelectInListSection(NSInteger listIndex, NSInteger item, NSInteger section) {
    NSArray *lists = MABAllLists();
    if (listIndex >= (NSInteger)lists.count) { MABLog(@"tapin: no such list"); return; }
    UIView *l = lists[listIndex]; NSIndexPath *ip = [NSIndexPath indexPathForItem:item inSection:section]; BOOL done = NO; id delegate = nil;
    if ([l isKindOfClass:[UITableView class]]) { UITableView *t = (UITableView *)l; delegate = t.delegate; if ([delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) { [t selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionNone]; [delegate tableView:t didSelectRowAtIndexPath:ip]; done = YES; } }
    else { UICollectionView *c = (UICollectionView *)l; delegate = c.delegate; if ([delegate respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) { [c selectItemAtIndexPath:ip animated:NO scrollPosition:UICollectionViewScrollPositionNone]; [delegate collectionView:c didSelectItemAtIndexPath:ip]; done = YES; } }
    MABLog([NSString stringWithFormat:@"tapin: list #%ld %@ item %ld delegate %@ selected %d", (long)listIndex, NSStringFromClass([l class]), (long)item, delegate ? NSStringFromClass([delegate class]) : @"none", done]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ MABTraits(); });
}
// Debug: "com.besiktasliseba.appbridge.viewtree.<hash>" logs every window of the app (scene, frame, root/presented controllers) and its view tree (depth 5, deeper
// only for views whose class names look like popups/sheets/presentations), to find views laid out for a stale size (M1 pipeline, Sileo queue).
static void MABViewTreeLine(UIView *v, int depth, NSMutableString *out) {
    NSString *cls = NSStringFromClass([v class]);
    BOOL keyword = [cls rangeOfString:@"Popup|Presentation|Dimming|Transition|Sheet|Queue|Download|Drop|Shadow|Container" options:NSRegularExpressionSearch].location != NSNotFound;
    if (depth > 5 && !keyword) return;
    if (depth > 14) return;
    CGRect f = [v convertRect:v.bounds toView:nil];
    [out appendFormat:@"%*s%@ %p win{%.0f,%.0f %.0fx%.0f}%@%@\n", depth * 2, "", cls, v, f.origin.x, f.origin.y, f.size.width, f.size.height, v.hidden ? @" HIDDEN" : @"", v.alpha < 0.99 ? [NSString stringWithFormat:@" a%.2f", v.alpha] : @""];
    for (UIView *sv in v.subviews) MABViewTreeLine(sv, depth + 1, out);
}
static void MABViewTree(void) {
    NSMutableString *out = [NSMutableString stringWithString:@"viewtree:\n"];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        UIWindowScene *sc = w.windowScene;
        [out appendFormat:@"WINDOW %@ %p frame %@ key %d hidden %d level %.0f scene %p (%@) sceneBounds %@ root %@\n", NSStringFromClass([w class]), w, NSStringFromCGRect(w.frame), w.isKeyWindow, w.hidden, w.windowLevel, sc, sc ? @(sc.activationState) : @"-", sc ? NSStringFromCGRect(sc.coordinateSpace.bounds) : @"-", w.rootViewController ? NSStringFromClass([w.rootViewController class]) : @"-"];
        for (UIViewController *vc = w.rootViewController.presentedViewController; vc; vc = vc.presentedViewController)
            [out appendFormat:@"  presented %@ style %ld view %@ inWindow %d\n", NSStringFromClass([vc class]), (long)vc.modalPresentationStyle, NSStringFromCGRect([vc.view convertRect:vc.view.bounds toView:nil]), vc.view.window != nil];
        if (!w.hidden) MABViewTreeLine(w, 1, out);
    }
#pragma clang diagnostic pop
    MABLog(out);
}
// Debug: "com.besiktasliseba.appbridge.popuptrace.<hash>" traces LNPopupController (the popup/queue bar library Sileo and others use): every present/dismiss/open/
// close of the popup bar, and hiding of LNPopupBar, with the controller's view width and its popup-related Swift ivars (M1 pipeline, Sileo queue stuck).
static NSString *MABIvarSummary(id obj) {
    NSMutableString *m = [NSMutableString string];
    for (Class c = [obj class]; c && c != [UIViewController class]; c = class_getSuperclass(c)) {
        unsigned n = 0; Ivar *iv = class_copyIvarList(c, &n);
        for (unsigned i = 0; i < n; i++) {
            const char *name = ivar_getName(iv[i]), *type = ivar_getTypeEncoding(iv[i]);
            if (!name || !strcasestr(name, "popup")) continue;
            ptrdiff_t off = ivar_getOffset(iv[i]);
            if (type && type[0] == 'B') [m appendFormat:@" %s=%d", name, *(BOOL *)((uint8_t *)(__bridge void *)obj + off)];
            else if (!type || !type[0]) [m appendFormat:@" %s(byte)=%d", name, *(uint8_t *)((uint8_t *)(__bridge void *)obj + off)];
        }
        free(iv);
    }
    return m;
}
static void MABPopupLog(NSString *what, id vc) {
    UIViewController *c = [vc isKindOfClass:[UIViewController class]] ? vc : nil;
    MABLog([NSString stringWithFormat:@"popup: %@ on %@ width %.0f scene %@%@", what, c ? NSStringFromClass([c class]) : @"?", c.isViewLoaded ? c.view.bounds.size.width : -1, c.view.window.windowScene ? @(c.view.window.windowScene.activationState) : @"-", c ? MABIvarSummary(c) : @""]);
}
static void (*oPresentBar)(id, SEL, id, BOOL, id);
static void hPresentBar(id self, SEL _cmd, id content, BOOL animated, void (^completion)(void)) {
    MABPopupLog(@"presentPopupBar", self);
    oPresentBar(self, _cmd, content, animated, completion ? ^{ MABPopupLog(@"presentPopupBar DONE", self); completion(); } : ^{ MABPopupLog(@"presentPopupBar DONE", self); });
}
static void (*oDismissBar)(id, SEL, BOOL, id);
static void hDismissBar(id self, SEL _cmd, BOOL animated, void (^completion)(void)) {
    MABPopupLog(@"dismissPopupBar", self);
    oDismissBar(self, _cmd, animated, completion ? ^{ MABPopupLog(@"dismissPopupBar DONE", self); completion(); } : ^{ MABPopupLog(@"dismissPopupBar DONE", self); });
}
static void (*oOpenPopup)(id, SEL, BOOL, id);
static void hOpenPopup(id self, SEL _cmd, BOOL animated, void (^completion)(void)) {
    MABPopupLog(@"openPopup", self);
    oOpenPopup(self, _cmd, animated, completion ? ^{ MABPopupLog(@"openPopup DONE", self); completion(); } : ^{ MABPopupLog(@"openPopup DONE", self); });
}
static void (*oClosePopup)(id, SEL, BOOL, id);
static void hClosePopup(id self, SEL _cmd, BOOL animated, void (^completion)(void)) {
    MABPopupLog(@"closePopup", self);
    oClosePopup(self, _cmd, animated, completion ? ^{ MABPopupLog(@"closePopup DONE", self); completion(); } : ^{ MABPopupLog(@"closePopup DONE", self); });
}
static void (*oBarSetHidden)(id, SEL, BOOL);
static void hBarSetHidden(id self, SEL _cmd, BOOL h) {
    if (h != [(UIView *)self isHidden]) {
        NSArray *st = [NSThread callStackSymbols];
        MABLog([NSString stringWithFormat:@"popup: LNPopupBar hidden %d <- %@", h, [[st subarrayWithRange:NSMakeRange(1, MIN((NSUInteger)8, st.count - 1))] componentsJoinedByString:@" | "]]);
    }
    oBarSetHidden(self, _cmd, h);
}
static void MABInstallPopupTrace(void) {
    Class vc = [UIViewController class];
    MSHookMessageEx(vc, @selector(presentPopupBarWithContentViewController:animated:completion:), (IMP)hPresentBar, (IMP *)&oPresentBar);
    MSHookMessageEx(vc, @selector(dismissPopupBarAnimated:completion:), (IMP)hDismissBar, (IMP *)&oDismissBar);
    MSHookMessageEx(vc, @selector(openPopupAnimated:completion:), (IMP)hOpenPopup, (IMP *)&oOpenPopup);
    MSHookMessageEx(vc, @selector(closePopupAnimated:completion:), (IMP)hClosePopup, (IMP *)&oClosePopup);
    Class bar = NSClassFromString(@"LNPopupBar");
    if (bar) MSHookMessageEx(bar, @selector(setHidden:), (IMP)hBarSetHidden, (IMP *)&oBarSetHidden);
    MABLog([NSString stringWithFormat:@"popup: trace installed (present %d dismiss %d open %d close %d bar %d)", oPresentBar != NULL, oDismissBar != NULL, oOpenPopup != NULL, oClosePopup != NULL, oBarSetHidden != NULL]);
}
// Debug: "com.besiktasliseba.appbridge.keycmds.<hash>": every UIKeyCommand reachable from the key window's first responder (or its root view controller) up the
// responder chain, plus views showing the share/print SF Symbols (M1 pipeline task 2, Share/Print menu rows).
static void MABSymbolViews(UIView *v, NSMutableString *out, int depth) {
    if (!v || depth > 30) return;
    UIImage *img = nil;
    if ([v isKindOfClass:[UIImageView class]]) img = ((UIImageView *)v).image;
    else if ([v isKindOfClass:[UIButton class]]) img = [(UIButton *)v imageForState:UIControlStateNormal];
    NSString *d = img ? img.description : nil;
    if ([d containsString:@"square.and.arrow.up"] || [d containsString:@"printer"] || [d containsString:@"ellipsis"])
        [out appendFormat:@"\n  symbol view %@ in %@ hidden %d: %@", NSStringFromClass([v class]), NSStringFromClass([v.superview class]), v.hidden, [d substringToIndex:MIN((NSUInteger)120, d.length)]];
    for (UIView *sub in v.subviews) MABSymbolViews(sub, out, depth + 1);
}
static void MABKeyCommands(void) {
    NSMutableString *out = [NSMutableString stringWithString:@"keycmds:"];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIWindow *key = nil; for (UIWindow *w in [UIApplication sharedApplication].windows) if (w.isKeyWindow) key = w;
#pragma clang diagnostic pop
    UIResponder *r = nil;
    for (UIView *v in (key ? @[key] : @[])) { NSMutableArray *st = [NSMutableArray arrayWithObject:v]; while (st.count) { UIView *x = st.lastObject; [st removeLastObject]; if (x.isFirstResponder) { r = x; break; } [st addObjectsFromArray:x.subviews]; } }
    if (!r) { UIViewController *vc = key.rootViewController; while (vc.presentedViewController) vc = vc.presentedViewController; r = vc; }
    [out appendFormat:@" start %@", r ? NSStringFromClass([r class]) : @"none"];
    for (UIResponder *x = r; x; x = x.nextResponder) for (UIKeyCommand *c in x.keyCommands)
        [out appendFormat:@"\n  %@: '%@' input '%@' mods %ld action %@", NSStringFromClass([x class]), c.title ?: c.discoverabilityTitle, c.input, (long)c.modifierFlags, NSStringFromSelector(c.action)];
    if (key) MABSymbolViews(key, out, 0);
    MABLog(out);
}
// Debug: "com.besiktasliseba.appbridge.testnotif.<hash>" posts a harmless local notification from this app (if it is allowed to notify), to test banners
// (M1 pipeline task 3, our macOS-style banners). Text comes from /tmp/mab-notif-text if present (unsandboxed apps only), else a fixed test line.
#import <UserNotifications/UserNotifications.h>
static void MABTestNotification(void) {
    UNUserNotificationCenter *c = [UNUserNotificationCenter currentNotificationCenter];
    [c getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *st) {
        MABLog([NSString stringWithFormat:@"testnotif: authorization %ld alert %ld", (long)st.authorizationStatus, (long)st.alertSetting]);
        if (st.authorizationStatus != UNAuthorizationStatusAuthorized && st.authorizationStatus != UNAuthorizationStatusProvisional) return;
        UNMutableNotificationContent *n = [UNMutableNotificationContent new];
        NSString *custom = [NSString stringWithContentsOfFile:@"/tmp/mab-notif-text" encoding:NSUTF8StringEncoding error:nil];
        NSArray *parts = [custom componentsSeparatedByString:@"|"];
        n.title = parts.count > 0 && [parts[0] length] ? parts[0] : @"Banner test";
        n.body = parts.count > 1 ? parts[1] : @"This is a test notification from the Mac Status Bar banner work. It can be dismissed.";
        UNNotificationRequest *r = [UNNotificationRequest requestWithIdentifier:[NSString stringWithFormat:@"mab-test-%.0f", CACurrentMediaTime() * 1000] content:n trigger:[UNTimeIntervalNotificationTrigger triggerWithTimeInterval:3 repeats:NO]];
        [c addNotificationRequest:r withCompletionHandler:^(NSError *e) { MABLog([NSString stringWithFormat:@"testnotif: added %@", e ?: @"ok"]); }];
    }];
}
static void MABRegisterFocus(void) {
    NSString *bundle = [NSBundle mainBundle].bundleIdentifier;
    if (!bundle.length || [bundle isEqualToString:@"com.apple.springboard"]) return;
    uint32_t hash = 2166136261u;
    for (const char *c = bundle.UTF8String; *c; c++) { hash ^= (uint8_t)*c; hash *= 16777619u; }
    char name[64]; snprintf(name, sizeof name, "com.besiktasliseba.appbridge.focus.%08x", hash);
    static int token = 0;
    notify_register_dispatch(name, &token, dispatch_get_main_queue(), ^(int t) { MABFocus(); });
    static int tokenOff = 0, tokenOn = 0, tokenList = 0;
    char n2[64]; snprintf(n2, sizeof n2, "com.besiktasliseba.appbridge.hwoff.%08x", hash);
    notify_register_dispatch(n2, &tokenOff, dispatch_get_main_queue(), ^(int t) { MABSetHardware(NO); });
    snprintf(n2, sizeof n2, "com.besiktasliseba.appbridge.hwon.%08x", hash);
    notify_register_dispatch(n2, &tokenOn, dispatch_get_main_queue(), ^(int t) { MABSetHardware(YES); });
    static int tokenPopupTrace = 0;
    snprintf(n2, sizeof n2, "com.besiktasliseba.appbridge.popuptrace.%08x", hash);
    notify_register_dispatch(n2, &tokenPopupTrace, dispatch_get_main_queue(), ^(int t) { static BOOL done; if (!done) { done = YES; MABInstallPopupTrace(); } });
    static int tokenKeyCmds = 0;
    snprintf(n2, sizeof n2, "com.besiktasliseba.appbridge.keycmds.%08x", hash);
    notify_register_dispatch(n2, &tokenKeyCmds, dispatch_get_main_queue(), ^(int t) { MABKeyCommands(); });
    static int tokenTestNotif = 0;
    snprintf(n2, sizeof n2, "com.besiktasliseba.appbridge.testnotif.%08x", hash);
    notify_register_dispatch(n2, &tokenTestNotif, dispatch_get_main_queue(), ^(int t) { MABTestNotification(); });
    static int tokenRuntime = 0;   // runtime: /tmp/mab-runtime holds "classes <substring>" or "methods <Class> <keyword>" (unsandboxed apps; read-only lookups)
    snprintf(n2, sizeof n2, "com.besiktasliseba.appbridge.runtime.%08x", hash);
    notify_register_dispatch(n2, &tokenRuntime, dispatch_get_main_queue(), ^(int t) {
        NSArray *a = [[[NSString stringWithContentsOfFile:@"/tmp/mab-runtime" encoding:NSUTF8StringEncoding error:nil] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsSeparatedByString:@" "];
        if (a.count >= 3 && [a[0] isEqualToString:@"methods"]) { MABListMethods(a[1], [a[2] lowercaseString]); MABLog(@"runtime: methods done"); }
        else if (a.count >= 2 && [a[0] isEqualToString:@"classes"]) {
            unsigned n = 0; Class *all = objc_copyClassList(&n); NSMutableArray *hits = [NSMutableArray array];
            for (unsigned i = 0; i < n && hits.count < 80; i++) { NSString *cn = NSStringFromClass(all[i]); if ([cn rangeOfString:a[1] options:NSCaseInsensitiveSearch].location != NSNotFound) [hits addObject:cn]; }
            free(all); MABLog([NSString stringWithFormat:@"runtime: classes %@: %@", a[1], [hits componentsJoinedByString:@" "]]);
        }
    });
    static int tokenViewTree = 0;
    snprintf(n2, sizeof n2, "com.besiktasliseba.appbridge.viewtree.%08x", hash);
    notify_register_dispatch(n2, &tokenViewTree, dispatch_get_main_queue(), ^(int t) { MABViewTree(); });
    static int tokenTraits = 0, tokenTap = 0;
    snprintf(n2, sizeof n2, "com.besiktasliseba.appbridge.traits.%08x", hash);
    notify_register_dispatch(n2, &tokenTraits, dispatch_get_main_queue(), ^(int t) { MABTraits(); });
    static int tokenTraitWatch = 0, tokenTraitTrace = 0;
    snprintf(n2, sizeof n2, "com.besiktasliseba.appbridge.traitwatch.%08x", hash);
    notify_register_dispatch(n2, &tokenTraitWatch, dispatch_get_main_queue(), ^(int t) { MABTraitWatch(12); });   // 12 s window: bracket a resize triggered from the SpringBoard side while this runs
    snprintf(n2, sizeof n2, "com.besiktasliseba.appbridge.traittrace.%08x", hash);
    notify_register_dispatch(n2, &tokenTraitTrace, dispatch_get_main_queue(), ^(int t) { static BOOL done; if (!done) { done = YES; MABInstallTraitTrace(); } });
    static int tokenScroll = 0;
    snprintf(n2, sizeof n2, "com.besiktasliseba.appbridge.scroll.%08x", hash);
    notify_register_dispatch(n2, &tokenScroll, dispatch_get_main_queue(), ^(int t) { MABScrollBy(2000); });
    static int tokenTypeTest = 0;
    snprintf(n2, sizeof n2, "com.besiktasliseba.appbridge.typetest.%08x", hash);
    notify_register_dispatch(n2, &tokenTypeTest, dispatch_get_main_queue(), ^(int t) {
        // Testing Undo/Redo: focuses a text field the same way "focus" does, then types a marker string into it one character at a time, the way a real
        // keystroke would — so it actually registers as separate undoable steps, not one big insert.
        MABFocus();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            id r = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            for (UIWindow *w in [UIApplication sharedApplication].windows) {
                if (!w.isKeyWindow) continue;
                NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
                while (stack.count) { UIView *v = stack.lastObject; [stack removeLastObject]; [stack addObjectsFromArray:v.subviews]; if (v.isFirstResponder) { r = v; break; } }
            }
#pragma clang diagnostic pop
            NSString *marker = @"UNDOTEST";
            for (NSUInteger i = 0; i < marker.length; i++) if ([r respondsToSelector:@selector(insertText:)]) [(id<UITextInput>)r insertText:[marker substringWithRange:NSMakeRange(i, 1)]];
            MABLog([NSString stringWithFormat:@"typetest: typed into %@", r ? NSStringFromClass([r class]) : @"nothing (no first responder found)"]);
        });
    });
    static int tokenLists = 0, tokenIn[8], tokenIn0[8], tokenSec1_0, tokenTapItem;
    snprintf(n2, sizeof n2, "com.besiktasliseba.appbridge.tapsec1_0.%08x", hash);
    notify_register_dispatch(n2, &tokenSec1_0, dispatch_get_main_queue(), ^(int t) { MABSelectInListSection(0, 0, 1); });
    // tapitem_<bundle>: fully parameterized (unlike tapin<N>/tapsec1_0, which each hardcode two of the three numbers) — reads
    // "<list> <item> <section>" from /tmp/macappbridge-tapitem, written just before posting this, since a Darwin notification carries no
    // payload of its own.
    snprintf(n2, sizeof n2, "com.besiktasliseba.appbridge.tapitem.%08x", hash);
    notify_register_dispatch(n2, &tokenTapItem, dispatch_get_main_queue(), ^(int t) {
        NSString *s = [NSString stringWithContentsOfFile:@"/tmp/macappbridge-tapitem" encoding:NSUTF8StringEncoding error:nil];
        NSArray<NSString *> *parts = [[s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsSeparatedByString:@" "];
        if (parts.count == 3) MABSelectInListSection([parts[0] integerValue], [parts[1] integerValue], [parts[2] integerValue]);
    });
    snprintf(n2, sizeof n2, "com.besiktasliseba.appbridge.lists.%08x", hash);
    notify_register_dispatch(n2, &tokenLists, dispatch_get_main_queue(), ^(int t) { MABDescribeLists(); });
    for (int k = 0; k < 8; k++) {
        snprintf(n2, sizeof n2, "com.besiktasliseba.appbridge.tapin%d.%08x", k, hash);
        notify_register_dispatch(n2, &tokenIn[k], dispatch_get_main_queue(), ^(int t) { MABSelectInList(k, 1); });
        snprintf(n2, sizeof n2, "com.besiktasliseba.appbridge.tapin%dz.%08x", k, hash);
        notify_register_dispatch(n2, &tokenIn0[k], dispatch_get_main_queue(), ^(int t) { MABSelectInList(k, 0); });
    }
    static int tokenTrace = 0;
    snprintf(n2, sizeof n2, "com.besiktasliseba.appbridge.trace.%08x", hash);
    notify_register_dispatch(n2, &tokenTrace, dispatch_get_main_queue(), ^(int t) { static BOOL done; if (!done) { done = YES; MABInstallTrace(); } });
    static int tokenBack = 0, tokenTapN[6];
    snprintf(n2, sizeof n2, "com.besiktasliseba.appbridge.back.%08x", hash);
    notify_register_dispatch(n2, &tokenBack, dispatch_get_main_queue(), ^(int t) { MABBack(); });
    for (int k = 0; k < 6; k++) {
        snprintf(n2, sizeof n2, "com.besiktasliseba.appbridge.tapn%d.%08x", k, hash);
        notify_register_dispatch(n2, &tokenTapN[k], dispatch_get_main_queue(), ^(int t) { MABTapAt(k); });
    }
    snprintf(n2, sizeof n2, "com.besiktasliseba.appbridge.tap.%08x", hash);
    notify_register_dispatch(n2, &tokenTap, dispatch_get_main_queue(), ^(int t) { MABTap(); });
    static int tokenHunt = 0;
    snprintf(n2, sizeof n2, "com.besiktasliseba.appbridge.hunt.%08x", hash);
    notify_register_dispatch(n2, &tokenHunt, dispatch_get_main_queue(), ^(int t) {
        for (NSString *cn in @[@"SofascoreApp.SplitViewController", @"SofascoreApp.MainMatchesViewController", @"SofascoreApp.TabViewController"]) {
            Class c = NSClassFromString(cn); unsigned n = 0; Method *l = c ? class_copyMethodList(c, &n) : NULL;
            MABLog([NSString stringWithFormat:@"hunt: %@ %s, %u methods", cn, c ? "found" : "MISSING", n]);
            for (unsigned i = 0; i < n; i++) MABLog([NSString stringWithFormat:@"hunt:   %@ -%@", cn, NSStringFromSelector(method_getName(l[i]))]);
            free(l);
        }
    });
    snprintf(n2, sizeof n2, "com.besiktasliseba.appbridge.list.%08x", hash);
    notify_register_dispatch(n2, &tokenList, dispatch_get_main_queue(), ^(int t) {
        for (NSString *cn in @[@"UIKeyboardImpl", @"UIKeyboard", @"UIKeyboardSceneDelegate", @"UIApplication"]) { MABListMethods(cn, @"hardware"); MABListMethods(cn, @"softwarekeyboard"); }
        MABLog(@"list done");
    });
}
#endif


// ============================================================================================
// SCREEN-SIZE COMPATIBILITY MODE (opt-in allowlist, SofaScore + Reminders + Settings confirmed): apps
// that decide between their iPad and iPhone layouts from the SCREEN size ([UIScreen mainScreen].bounds)
// rather than from their window's own trait collections / size classes keep their iPad layout in a
// small window (a detail screen that never opens, columns cut off; Sofascore is one: its own split
// view reports the full screen's size even inside a half window; Settings under MilkyWay is another —
// this was the ORIGINAL motivating bug: hard, character-precise clipping and a persistent grey gap at
// steady state, not an animation glitch, matching this exact signature).
//
// ROOT CAUSE (found tonight, on a real iPhone X, by reading Aerial.dylib itself): Aerial/MilkyWay
// resize an app's SCENE FRAME when they put it in a window, but never touch UIScreen.mainScreen.
// bounds at all. A scene-aware app (reads its own window/scene geometry, or trait collections/size
// classes fed by that geometry) sees the smaller size correctly through the frame change alone —
// that is exactly why most apps have no problem in a narrow window, and exactly why this fix reads
// the app's OWN window scene rather than needing SpringBoard to tell it anything. An app that
// instead reads UIScreen.mainScreen.bounds directly stays convinced it is still on the full,
// physical device screen no matter how small its window gets, because that property genuinely never
// changes: on an iPad this is a wide screen, so the bug never resolves; on the iPhone X the exact
// same bug is invisible only because the real physical screen is already phone-narrow, not because
// anything about Aerial's own resize mechanism is different there.
//
// WHY OPT-IN, NOT BLANKET (design choice, made deliberately): a blanket override of every app's
// UIScreen would also reach apps that read real screen dimensions on purpose and correctly — a game
// choosing a rendering resolution, a camera/photo app sizing a capture buffer against the real pixel
// grid — and there is no reliable way from outside the app to tell "reads it because of this bug"
// apart from "reads it deliberately, correctly". A small, explicit, reviewable list keeps the blast
// radius to exactly the apps confirmed to need it; every other app's UIScreen is never touched by
// this feature at all — no hook is even installed, no code runs, for anyone not on the list.
//
// WHY THIS DESIGN, GIVEN THE HISTORY: three earlier attempts at this exact feature all reliably hung
// the app (SofaScore) at launch (a 30 s FRONTBOARD launch-watchdog kill), across three different data
// sources for the override value (an on-demand UIApplication.windows call, a cached+main-thread-gated
// version of the same, and a fully lock-free version fed by SpringBoard over a Darwin notification,
// which is what the two globals and the comment above USED to describe here). The one thing all three
// shared, unchanged across every attempt: a per-call-site dladdr() lookup (cached after the first hit,
// but every call site is a cache MISS the first time it is seen) to tell the app's own code apart from
// UIKit's internal use of -bounds. dladdr walks dyld's own loaded-image table under dyld's own lock;
// -bounds is confirmed (by the comment that used to be here) to be called very often, from more than
// one thread — and a cold launch is exactly when dyld is busiest resolving lazy symbols on the main
// thread too. Sustained contention on that same lock, at exactly the moment a fresh app has the most
// never-before-seen -bounds call sites to classify, is a plausible explanation for a reliable ~30 s
// hang that never threw or crashed (a real deadlock would show up as SIGABRT/backtrace; a slow
// contended lock just looks like nothing happening, which is what the launch watchdog saw). This
// version changes three things at once, each independently reducing that specific risk:
//   (a) the size comes from the app's OWN window scene directly (UIWindowScene.coordinateSpace.
//       bounds), read on a light periodic timer — never from inside the swizzled getter itself, and
//       never over a cross-process round trip at all (the stated preference, and it is exactly the
//       same geometry a scene-aware app already reads correctly, so it is known-good data);
//   (b) "is this the app's own code" is answered with a plain pointer-range check against the app's
//       own loaded images' __TEXT segments (computed ONCE, up front, not per call site) instead of a
//       dladdr lookup per never-before-seen call site — no dyld lock is ever touched from inside
//       -bounds, or anywhere near the busiest part of launch, at all;
//   (c) the swizzle is only ever installed once the app has genuinely finished launching
//       (UIApplicationDidBecomeActiveNotification, plus a short extra margin for FrontBoard's own
//       scene-geometry negotiation to settle) instead of at %ctor/cold-launch time — clear of the
//       exact window every earlier attempt hung inside, regardless of what the actual root cause
//       upstream of that turns out to be.
// This is still a real, non-trivial change to a public but very frequently-called system API, inside
// two apps the owner uses daily. It has never been tested on a device. Test it deliberately, one app at a
// time, watching specifically for the same 30 s-hang failure mode seen three times before, before
// trusting it — do not treat "it compiles" as "it is safe".
//
// Deliberately NOT hooked: .scale/.nativeScale (the device's real pixel density does not change when
// an app is windowed — the window is still rendered at the same @2x/@3x scale as always, just into a
// smaller area; faking this would make rendering wrong, not more correct, for every app on the list).
// .nativeBounds/.currentMode are also left real for now: they are the properties a genuine
// resolution-dependent decision (the exact case this feature must not interfere with) is more likely
// to read than plain .bounds is, and none of SofaScore/Reminders/Settings has been shown to need them —
// .bounds alone is the one actually described (by both apps' own behaviour and the class names found
// during earlier investigation, e.g. SofaScore's own SplitViewController/collapse-delegate code) as
// what decides their layout. Revisit only if testing shows .bounds alone is not enough.
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
static NSSet<NSString *> *MABScreenCompatAllowlist(void) {
    static NSSet<NSString *> *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ set = [NSSet setWithArray:@[@"com.SofaScore.iOS", @"com.apple.reminders", @"com.apple.Preferences"]]; });   // expand here as more apps are confirmed
    return set;
}
static CGRect (*gOrigScreenBounds)(id, SEL);
static NSString *gAppBundlePath;
static __unsafe_unretained UIScreen *gMainScreen;   // (set once the app is running: asking for the main screen inside its own -bounds could re-enter its creation)
static volatile CGFloat gCompatW = 0, gCompatH = 0;   // last known window-scene size; 0 = not known yet (never override while 0)

// Pure pointer-arithmetic replacement for a per-call dladdr() lookup: the app's own __TEXT range is
// recorded ONCE, up front; from then on, telling a return address apart from UIKit's own code is one
// range comparison, no lock, no syscall, nothing dyld has to serialize with any other thread.
//   Confirmed live (real device testing) that enumerating ALL loaded images by path and matching
// against the app's own bundle path is NOT reliable on this OS/dyld combination: _dyld_get_image_name()
// returned "/usr/lib/libSystem.B.dylib" for every one of the first several hundred (of 934) indices
// checked, on a real launch, including index 0 — clearly not each image's real install name, a dyld3/4
// shared-cache-era quirk of the legacy enumeration API, not a bug in the matching logic itself (an
// earlier version here tried matching resolved-vs-unresolved "/private/var" path forms, which was a
// real, separate bug, but did not explain this). What IS a stable, documented dyld contract regardless
// of that: index 0 in this table is ALWAYS the main executable. This only covers the app's own main
// executable, not a separate embedded framework it might also ship — a real, accepted scope reduction,
// not a safety concern (a return address in an unrecognized embedded framework just falls through to
// "not app code" and the real screen size, i.e. the fix silently does less than it could, never more
// than it should); SofaScore's own layout code (its "SofascoreApp" Swift module, seen directly by class
// name during earlier investigation) is very likely the main executable itself, not a separate
// framework, for a typical single-target app — worth confirming if the fix turns out incomplete later.
static uintptr_t gAppTextStart, gAppTextEnd;
static void MABComputeAppImageRanges(void) {
    const struct mach_header_64 *mh = (const struct mach_header_64 *)_dyld_get_image_header(0);   // 0: always the main executable
    if (!mh) return;
    unsigned long size = 0;
    uint8_t *base = getsegmentdata(mh, "__TEXT", &size);
    if (!base || !size) return;
    gAppTextStart = (uintptr_t)base;
    gAppTextEnd = (uintptr_t)base + size;
}
static BOOL MABIsAppCode(void *caller) {
    uintptr_t ra = (uintptr_t)caller;
    return gAppTextStart && ra >= gAppTextStart && ra < gAppTextEnd;
}

// Kept live the same low-cost way the (separate, still-off) idiom experiment below already does:
// a light periodic poll on the main thread, never from inside the swizzled getter itself, so -bounds
// itself only ever reads two already-updated floats — no UIKit call in the swizzle at all.
static void MABCompatRefreshFromWindow(void) {
    if (![NSThread isMainThread]) return;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIWindow *found = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.hidden || w.windowLevel != UIWindowLevelNormal) continue;
        found = w; break;
    }
#pragma clang diagnostic pop
    if (!found || !found.windowScene) return;
    CGRect b = found.windowScene.coordinateSpace.bounds;
    if (b.size.width <= 0 || b.size.height <= 0) return;
    gCompatW = b.size.width; gCompatH = b.size.height;
}
static CGRect MABCompatBounds(id self, SEL _cmd) {
    CGRect real = gOrigScreenBounds(self, _cmd);
    if (!gMainScreen || self != gMainScreen || gCompatW <= 0) return real;                          // not the main screen, or no window size known yet: untouched
    if (gCompatW >= real.size.width - 0.5 && gCompatH >= real.size.height - 0.5) return real;        // full screen (or as good as): untouched, exactly as today
    if (!MABIsAppCode(__builtin_return_address(0))) return real;                                     // UIKit's own internal use of -bounds: untouched
    return CGRectMake(0, 0, gCompatW, gCompatH);
}
static void MABInstallScreenCompat(void) {
    if (!gMainScreen) {
#if DEBUG
        MABLog(@"screen-compat: aborted, gMainScreen nil");
#endif
        return;
    }
    MABComputeAppImageRanges();
    if (!gAppTextStart) {
#if DEBUG
        MABLog(@"screen-compat: aborted, could not read the main executable's own __TEXT segment");
#endif
        return;   // could not find our own __TEXT range: refuse to guess, leave UIScreen untouched
    }
    MABCompatRefreshFromWindow();
    // (Phase 2b, 2026-09-24: cheaper. The window size is re-read on a 0.5 s timer that only runs while the app is active -- stopped in the
    // background, started again on becoming active -- and has 0.25 s tolerance so the system can coalesce its wakeups with others; plus an
    // immediate refresh on those transitions. SofaScore's "too many wakeups" reports (230/s) were sampled in SofaScore's own code, not here,
    // but a window app kept in the foreground behind others no longer wakes up for this at all.)
    static NSTimer *timer = nil;
    void (^start)(void) = ^{
        if (timer) return;
        MABCompatRefreshFromWindow();
        timer = [NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *tm) { MABCompatRefreshFromWindow(); }];
        timer.tolerance = 0.25;
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    };
    start();
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) { start(); }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) { [timer invalidate]; timer = nil; }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) { MABCompatRefreshFromWindow(); }];
    Method m = class_getInstanceMethod([UIScreen class], @selector(bounds));
    if (!m) return;
    gOrigScreenBounds = (CGRect (*)(id, SEL))method_getImplementation(m);
    method_setImplementation(m, (IMP)MABCompatBounds);
#if DEBUG
    MABLog([NSString stringWithFormat:@"screen-compat: installed (__TEXT %#lx-%#lx)", (unsigned long)gAppTextStart, (unsigned long)gAppTextEnd]);
#endif
}
// Only even considered once the app has genuinely finished launching (not at %ctor/cold-launch time,
// which is when all three earlier attempts hung) — a further 1.5 s margin past "did become active" on
// top of that, since FrontBoard's own scene-geometry negotiation can still be settling for a moment
// after that notification fires. Note this means a COLD launch straight into an already-narrow window
// may show the wrong (uncollapsed) layout for its first second or two until this installs and the app
// next re-evaluates its layout (a resize, rotation, or trait-change callback) — the reported bug is
// about narrowing an already-open window, which is well past this delay by construction; a cold-launch-
// into-window case is a separate, lower-priority nuance worth confirming during testing, not solving
// blindly here.
// Safety valve, checked in BOTH debug and release builds (not gated by #if DEBUG): if this ever needs
// to be turned off on-device without a rebuild/reinstall — e.g. after a hang, once the app has been
// force-quit/rebooted back to responsive — leaving /tmp/macappbridge-screencompat-off present stops
// any FUTURE launch of an allowlisted app from installing the swizzle at all (existing rule elsewhere
// in this project: a flag file's mtime, not its removal, is what a sandboxed/mobile process can act
// on reliably — this one is only ever read, never written or deleted by the tweak itself).
static void MABScheduleScreenCompatInstall(void) {
    static BOOL scheduled = NO;   // NSNotificationCenter observers can fire more than once (e.g. background/foreground cycles); install exactly once
    if (scheduled) return;
    scheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ MABInstallScreenCompat(); });
}
static void MABRegisterScreenCompat(void) {
    if (MSTestFlag("/tmp/macappbridge-screencompat-off")) return;
    NSString *bundle = [NSBundle mainBundle].bundleIdentifier;
    if (![MABScreenCompatAllowlist() containsObject:bundle]) return;   // not one of the known-broken apps: nothing installed, nothing touched, ever
    gAppBundlePath = [NSBundle mainBundle].bundlePath;
#if DEBUG
    MABLog([NSString stringWithFormat:@"screen-compat: MABRegisterScreenCompat entered, applicationState=%ld", (long)[UIApplication sharedApplication].applicationState]);
#endif
    // Confirmed live (real device testing): this %ctor's own dispatch_async to the main queue can lose the race against the app's own launch —
    // by the time it runs, UIApplicationDidBecomeActiveNotification may already have fired once, before this observer was even registered to
    // hear it, and NSNotificationCenter never replays a past notification to a new observer — so waiting on the notification ALONE silently
    // never installs anything for an app that never leaves the foreground again. Checking the CURRENT applicationState first covers exactly
    // that already-missed case; the observer stays registered too, as a fallback for the (also real) case where this runs before the app has
    // become active yet, and for any future background/foreground cycle.
    if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive) MABScheduleScreenCompatInstall();
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        MABScheduleScreenCompatInstall();
    }];
}


// ============================================================================================
// SOFASCORE PHONE LAYOUT IN A NARROW WINDOW (com.SofaScore.iOS only).
//
// WHAT SOFASCORE DECIDES ITS LAYOUT ON (found 2026-09-24: a read-only probe inside SofaScore on the iPhone X, disassembly of
// SofascoreApp, and live tests on the M1): its own class method +[DeviceInfo isPad] (= UIDevice userInterfaceIdiom == pad). In
// -[TabViewController viewDidLoad] every tab gets its container from it, once: iPad -> a SofascoreApp.SplitViewController (list left,
// match right), iPhone -> a plain UINavigationController. ~40 other places ask it too (headers, ads, sizes). SofaScore never looks at
// the screen size or size classes for this, so an iPhone always shows the phone layout and an iPad always the split layout, whatever
// the window size.
//
// WHY NOT A LIVE SIZE-CLASS SWITCH (tried and tested on the M1 first): a compact size-class override on SofaScore's split views does
// collapse them to one column (it looks right), but SofaScore opens a match by pushing onto split.viewControllers[1] and silently does
// nothing when the split has only one column, so in that state tapping a match does nothing. The only state where everything works
// in a narrow window is the real phone layout, which SofaScore builds only at launch.
//
// FIX: +[DeviceInfo isPad] answers NO for the whole life of a SofaScore process that starts in a narrow window (scene narrower than
// 700 pt when SofaScore first asks with a known scene size, i.e. while it builds its tabs). The answer is decided once and never
// changes afterwards, so all of SofaScore's callers always agree (exactly like on an iPhone). A full-screen launch (or a wide window)
// is never touched and keeps the iPad layout. UIDevice/UITraitCollection are NOT changed: only SofaScore's own helper, so UIKit and
// every other library keep the real iPad idiom. Trade-off: the layout is chosen per launch; a phone-layout SofaScore later made wide
// or full screen keeps the phone layout (stretched, fully working) until it is relaunched, and an iPad-layout SofaScore made narrow
// keeps the split layout (as before this fix) until relaunched. The hook is installed in %ctor through the runtime only
// (objc_getClass/object_getClass + method_setImplementation, which never run +initialize), and nothing touches UIScreen there:
// messaging UIScreen that early deadlocks the launch in +[UIScreen initialize] (seen on the iPhone X; the likely cause of the old
// SofaScore launch hangs). Kill switch: /tmp/macappbridge-sofaphone-off (read at launch).
static BOOL (*gOrigSofaIsPad)(id, SEL);
static int gSofaPhone = -1;   // -1 not decided yet, 0 iPad layout, 1 phone layout (decided once per process)
static CGFloat MABSofaSceneWidth(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return 0;
    for (UIScene *s in app.connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        CGFloat w = ((UIWindowScene *)s).coordinateSpace.bounds.size.width;
        if (w > 0) return w;
    }
    return 0;
}
// The window size SpringBoard (Mac Status Bar) publishes for this app BEFORE it launches it into a window (DMSendWindowSize: state =
// width << 32 | height, 0 = full screen). Needed because at launch the app's scene first appears at the full screen size and is only
// shrunk to the window a moment later, after SofaScore has already built its tabs.
static CGFloat MABSofaPublishedWidth(void) {
    uint32_t hash = 2166136261u;
    for (const char *c = "com.SofaScore.iOS"; *c; c++) { hash ^= (uint8_t)*c; hash *= 16777619u; }
    char name[64]; snprintf(name, sizeof name, "com.besiktasliseba.appbridge.wsize.%08x", hash);
    int token = 0; uint64_t state = 0;
    if (notify_register_check(name, &token) != NOTIFY_STATUS_OK) return 0;
    notify_get_state(token, &state); notify_cancel(token);
    return (CGFloat)(uint32_t)(state >> 32);
}
static BOOL MABSofaIsPad(id self, SEL _cmd) {
    BOOL real = gOrigSofaIsPad(self, _cmd);
    if (!real) return real;
    if (gSofaPhone < 0 && [NSThread isMainThread]) {
        static int calls = 0; calls++; (void)calls;   // (read by the debug log only)
        CGFloat pub = MABSofaPublishedWidth();
        CGFloat w = pub > 0 ? pub : MABSofaSceneWidth();   // published window width first; 0 there = full screen -> the scene's own size
#if DEBUG
        MABLog([NSString stringWithFormat:@"sofa-phone: published width %.0f, scene width %.0f", pub, MABSofaSceneWidth()]);
#endif
        if (w > 0) {
            gSofaPhone = w < 700 ? 1 : 0;
            // Tell SpringBoard (Mac Status Bar's quick relaunch) which layout this process was built with: state 1 = phone, 2 = iPad.
            // The token stays registered for the life of the process, so the state is readable until SofaScore quits (then it reads 0).
            static int layoutToken = 0;
            if (!layoutToken) notify_register_check("com.besiktasliseba.appbridge.sofalayout", &layoutToken);
            if (layoutToken) { notify_set_state(layoutToken, gSofaPhone ? 1 : 2); notify_post("com.besiktasliseba.appbridge.sofalayout"); }
#if DEBUG
            MABLog([NSString stringWithFormat:@"sofa-phone: decided at call %d, scene width %.0f -> %@", calls, w, gSofaPhone ? @"PHONE layout" : @"iPad layout"]);
#endif
        }
#if DEBUG
        else MABLog([NSString stringWithFormat:@"sofa-phone: call %d before any scene has a size (answered iPad)", calls]);
#endif
    }
    return gSofaPhone == 1 ? NO : real;
}
static void MABInstallSofaPhone(void) {   // called from %ctor: runtime calls only, no UIKit messaging
    if (MSTestFlag("/tmp/macappbridge-sofaphone-off")) return;
    if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.SofaScore.iOS"]) return;
    Class c = objc_getClass("DeviceInfo");
    Method m = c ? class_getInstanceMethod(object_getClass((id)c), @selector(isPad)) : NULL;   // class method: look it up on the metaclass
    if (!m) return;   // a SofaScore version without this helper: do nothing
    gOrigSofaIsPad = (BOOL (*)(id, SEL))method_getImplementation(m);
    method_setImplementation(m, (IMP)MABSofaIsPad);
}


// A universal app (it has an iPhone layout too) in a narrow window: its own code is told it runs on an iPhone, so it takes the phone navigation (a detail screen
// covers the list, like Settings) instead of an iPad layout the window is too small for. Only for the app's own code (not UIKit or other system code), only while the
// window's horizontal size class is compact, and only for apps that list the iPhone in UIDeviceFamily.
static NSInteger (*gOrigDeviceIdiom)(id, SEL);
static NSInteger (*gOrigTraitIdiom)(id, SEL);
static BOOL MABWindowCompact(void) {
    static BOOL cached = NO; static CFTimeInterval cachedAt = -10; static __thread BOOL busy;
    CFTimeInterval now = CACurrentMediaTime();
    if (!gMainScreen || busy || ![NSThread isMainThread] || now - cachedAt < 0.25) return cached;
    busy = YES; cachedAt = now; cached = NO;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.hidden || w.windowLevel != UIWindowLevelNormal) continue;
        cached = w.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact && w.bounds.size.width < 700;
        break;
    }
#pragma clang diagnostic pop
    busy = NO; return cached;
}
static BOOL MABCallerIsApp(void *caller) {
    Dl_info info;
    return dladdr(caller, &info) && info.dli_fname && gAppBundlePath.length && strncmp(info.dli_fname, gAppBundlePath.UTF8String, gAppBundlePath.length) == 0;
}
static NSInteger MABDeviceIdiom(id self, SEL _cmd) {
    NSInteger real = gOrigDeviceIdiom(self, _cmd);
    if (real != UIUserInterfaceIdiomPad || !MABCallerIsApp(__builtin_return_address(0))) return real;
    return MABWindowCompact() ? UIUserInterfaceIdiomPhone : real;
}
static NSInteger MABTraitIdiom(id self, SEL _cmd) {
    NSInteger real = gOrigTraitIdiom(self, _cmd);
    if (real != UIUserInterfaceIdiomPad || !MABCallerIsApp(__builtin_return_address(0))) return real;
    return MABWindowCompact() ? UIUserInterfaceIdiomPhone : real;
}
__attribute__((unused)) static void MABInstallIdiom(void) {
    NSString *bundle = [NSBundle mainBundle].bundleIdentifier;
    if (!bundle.length || [bundle hasPrefix:@"com.apple."]) return;   // (system apps use size classes)
    NSArray *family = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"UIDeviceFamily"];
    if (![family containsObject:@1]) return;   // (an iPad-only app has no phone layout to fall back to)
    gAppBundlePath = [NSBundle mainBundle].bundlePath;
    Method m = class_getInstanceMethod([UIDevice class], @selector(userInterfaceIdiom));
    if (m) { gOrigDeviceIdiom = (NSInteger (*)(id, SEL))method_getImplementation(m); method_setImplementation(m, (IMP)MABDeviceIdiom); }
    m = class_getInstanceMethod([UITraitCollection class], @selector(userInterfaceIdiom));
    if (m) { gOrigTraitIdiom = (NSInteger (*)(id, SEL))method_getImplementation(m); method_setImplementation(m, (IMP)MABTraitIdiom); }
}

// ===== LNPopupController race guard (M1 pipeline 2026-09-24, Sileo "queue gets stuck in a window") =====================================================
// Sileo (and other apps built on the LNPopupController library) show a popup bar (Sileo: the "Queued" bar in the tab bar) only when the app is wider than
// a threshold (Sileo: 768 pt) and remove it when narrower. When a window changes size quickly across that threshold (full screen -> window goes through
// a short in-between size; a fast resize does the same), the app asks LNPopupController to dismiss the bar and, before that animation is over, to present
// it again. The library does not handle the overlap: the late "dismiss finished" step hides the bar AFTER it was presented again, so the app believes the
// bar is up while it is hidden, and the next Queue tap opens an invisible popup over a dimmed window (stuck). Fix: present/dismiss calls on one controller
// are run one at a time; a call that arrives while the opposite one is still animating waits for it, and only the latest request runs. Every completion
// block the app passed is still called exactly once. A 2 s safety net runs the waiting call if a completion never comes.
#import <objc/runtime.h>
static char kMABPopupBusy, kMABPopupPending;
static void (*oMABPresentBar)(id, SEL, id, BOOL, id);
static void (*oMABDismissBar)(id, SEL, BOOL, id);
static void MABPopupRun(id vc, int op, id content, BOOL animated, void (^completion)(void));
static void MABPopupFinished(id vc, NSNumber *token) {
    if (![objc_getAssociatedObject(vc, &kMABPopupBusy) isEqual:token]) return;   // already finished (completion or safety net)
    objc_setAssociatedObject(vc, &kMABPopupBusy, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    void (^next)(void) = objc_getAssociatedObject(vc, &kMABPopupPending);
    objc_setAssociatedObject(vc, &kMABPopupPending, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (next) next();
}
static void MABPopupRun(id vc, int op, id content, BOOL animated, void (^completion)(void)) {
    NSNumber *busy = objc_getAssociatedObject(vc, &kMABPopupBusy);
    if (busy) {   // one is still animating: remember only the latest request (its completion, and any replaced request's completion, run after it)
        void (^oldCompletion)(void) = objc_getAssociatedObject(vc, "mabPendingCompletion");
        void (^merged)(void) = ^{ if (oldCompletion) oldCompletion(); if (completion) completion(); };
        objc_setAssociatedObject(vc, "mabPendingCompletion", merged, OBJC_ASSOCIATION_COPY_NONATOMIC);
        __weak id weakVC = vc;
        objc_setAssociatedObject(vc, &kMABPopupPending, ^{
            id strong = weakVC; if (!strong) return;
            void (^c)(void) = objc_getAssociatedObject(strong, "mabPendingCompletion");
            objc_setAssociatedObject(strong, "mabPendingCompletion", nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
            MABPopupRun(strong, op, content, animated, c);
        }, OBJC_ASSOCIATION_COPY_NONATOMIC);
        return;
    }
    static long counter = 0;
    NSNumber *token = @(++counter);
    objc_setAssociatedObject(vc, &kMABPopupBusy, token, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak id weakVC = vc;
    void (^done)(void) = ^{ if (completion) completion(); id strong = weakVC; if (strong) MABPopupFinished(strong, token); };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ id strong = weakVC; if (strong) MABPopupFinished(strong, token); });
    if (op == 1) oMABPresentBar(vc, @selector(presentPopupBarWithContentViewController:animated:completion:), content, animated, done);
    else oMABDismissBar(vc, @selector(dismissPopupBarAnimated:completion:), animated, done);
}
static void hMABPresentBar(id self, SEL _cmd, id content, BOOL animated, void (^completion)(void)) {
    if (![NSThread isMainThread]) { oMABPresentBar(self, _cmd, content, animated, completion); return; }
    MABPopupRun(self, 1, content, animated, completion);
}
static void hMABDismissBar(id self, SEL _cmd, BOOL animated, void (^completion)(void)) {
    if (![NSThread isMainThread]) { oMABDismissBar(self, _cmd, animated, completion); return; }
    MABPopupRun(self, 2, nil, animated, completion);
}
static void MABInstallPopupGuard(void) {
    if (!NSClassFromString(@"LNPopupBar")) return;   // only apps that contain LNPopupController
    Class vc = [UIViewController class];
    SEL ps = @selector(presentPopupBarWithContentViewController:animated:completion:), ds = @selector(dismissPopupBarAnimated:completion:);
    if (!class_getInstanceMethod(vc, ps) || !class_getInstanceMethod(vc, ds)) return;
    MSHookMessageEx(vc, ps, (IMP)hMABPresentBar, (IMP *)&oMABPresentBar);
    MSHookMessageEx(vc, ds, (IMP)hMABDismissBar, (IMP *)&oMABDismissBar);
}
%ctor {
    // MABInstallIdiom();   // (separate experiment, off: an iPhone idiom for universal apps in a compact window; not shown to help SofaScore)
#if DEBUG
    MABLog([NSString stringWithFormat:@"%%ctor fired, bundle=%@", [NSBundle mainBundle].bundleIdentifier]);
#endif
    %init;   // the touch hook above
    MABInstallSofaPhone();   // SofaScore only: its phone layout when it starts in a narrow window (runtime calls only, safe this early)
    if ([[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.AppStore"]) %init(MABAppStoreTabs);
#if DEBUG
    MABInstallDebugHooks();   // a software keyboard on demand
#endif
    dispatch_async(dispatch_get_main_queue(), ^{
        // Confirmed on-device crash: the filter above (com.apple.UIKit) matches any process that merely LINKS UIKit, not only real apps —
        // runningboardd does, and is not one (it never calls UIApplicationMain), so +[UIScreen mainScreen] threw there, uncaught, taking the
        // whole daemon down in a crash loop (froze the device: runningboardd is load-bearing for every other process's lifecycle). checking
        // sharedApplication here, not synchronously at the top of %ctor, is deliberate — this dispatch_async has already yielded to the host
        // process's own run loop once by the time it runs, so a genuine app has had the chance to call UIApplicationMain and set it by now;
        // checking any earlier would incorrectly reject real apps too, which have not started up yet at dylib-load time.
#if DEBUG
        MABLog([NSString stringWithFormat:@"dispatch_async fired, sharedApplication=%@", [UIApplication sharedApplication]]);
#endif
        if (![UIApplication sharedApplication]) return;
        gMainScreen = [UIScreen mainScreen];
        MABRegister();
        MABRegisterActions();
        MABInstallPopupGuard();   // apps with LNPopupController only (Sileo): popup bar present/dismiss one at a time
        MABRegisterScreenCompat();   // no-op for every app except the small allowlist (see above) — registers only, installs much later
#if DEBUG
        MABRegisterFocus();
#endif
    });
}
