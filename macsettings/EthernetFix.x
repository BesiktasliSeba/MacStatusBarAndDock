// EthernetFix.x -- Settings > General > Ethernet (MacSettings, Settings app only). What it does today:
//  - the Ethernet section is always listed, with or without an adapter (EthernetAlwaysShow, below; ported from Lynx's showSettingsEthernetSection);
//  - Apple's page for one interface (AppleEthernetSettingsController, which embeds WiFi's WFNetworkSettingsViewController) throws in stock iPadOS
//    ("-[AppleEthernetSettingsController network]: unrecognized selector") and used to crash Preferences. Both controllers' lifecycle calls are
//    wrapped in @try/@catch: a throw shows a plain "aren't available" message instead of a crash. A row tap on the interface list is also answered
//    with a "Not Available" alert where that hook fires (it did not for a simulated tap).
// Status: the WFNetworkSettingsViewController catch was seen catching on a real tap (that is where the exception reason above comes from); that the
// page now never crashes on the current build still needs the real-adapter hand test. The notes below keep the history of the earlier attempts
// (attempts 1-2 were replaced; 3-6 are what runs now).
#import <UIKit/UIKit.h>
#if DEBUG
#define MSTestFlag(path) (access((path), F_OK) == 0)   // a /tmp test switch (debug builds only; a release build behaves as if none existed)
#else
#define MSTestFlag(path) 0
#endif
#import <unistd.h>
#import "../common/OtherTweaks.h"

static void MLog(NSString *line) {   // (debug builds only: release builds write no /tmp log)
#if DEBUG
    if (!MSTestFlag("/tmp/macsettings-debug")) return;
    FILE *f = fopen("/tmp/macsettings.log", "a"); if (!f) return;
    fprintf(f, "%s\n", line.UTF8String); fclose(f);
#endif
}

// AppleEthernetSettingsController lives in a plugin bundle Settings only loads once you actually navigate to Ethernet — it almost
// certainly does not exist yet when this dylib's %ctor runs at Preferences' launch, so hooking it directly (objc_getClass would return
// NULL, and Logos would silently skip installing the hook) does not work — confirmed on-device: it still crashed. Hooked on UIViewController
// instead (always loaded) and filtered by a fresh isKindOfClass: check inside, done at call time rather than once at ctor time, since by
// the time any -viewDidLoad actually runs, whatever class it belongs to must already be loaded.
// Confirmed by logging every -viewDidLoad in Preferences: this hook DID fire and DID match AppleEthernetSettingsController, yet
// WFNetworkSettingsViewController's own -viewDidLoad still ran (and still crashed) right after. That means the child is embedded earlier
// than -viewDidLoad — almost certainly a storyboard "container view" relationship, which instantiates and adds the child during
// -loadView (as the storyboard unarchives), before -viewDidLoad ever runs. -loadView is hooked instead: replacing it outright (never
// calling %orig, so the storyboard is never unarchived and the broken child is never created) is the only point early enough to matter.
// Primary defense: never let the tap that would push into the crashing detail page happen at all. AppleEthernetController (no
// "Settings" in the name — a genuinely different, sibling class, confirmed by logging every -viewDidLoad in Preferences) is the
// INTERFACES LIST page (showing "Ethernet Adapter (en2)" / "(en3)"); its row selection is what pushes AppleEthernetSettingsController.
// Blocking the selection outright sidesteps every bit of uncertainty about exactly where inside the destination controller's own
// lifecycle the crash actually happens — it is simply never reached.
%hook UIViewController
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    Class listClass = objc_getClass("AppleEthernetController");
    MLog([NSString stringWithFormat:@"[ethernetfix] didSelectRow on %@ (listClass %@, match %d)", NSStringFromClass([self class]), listClass ? @"found" : @"NOT found", listClass && [self isKindOfClass:listClass]]);
    if (listClass && [self isKindOfClass:listClass]) {
        MLog(@"[ethernetfix] blocked a row selection on AppleEthernetController (would have pushed the crashing detail page)");
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Not Available"
            message:@"Settings for this Ethernet interface aren't available (this is a stock Apple bug that crashes without this)."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        UIViewController *presenter = self;
        while (presenter.presentedViewController) presenter = presenter.presentedViewController;
        [presenter presentViewController:alert animated:YES completion:nil];
        return;
    }
    %orig;
}
%end
// SIXTH ATTEMPT, superseding the two hooks that used to be here (kept the file-level attempt log above for history).
// REAL BUG IN THE ORIGINAL APPROACH, found from this session's own direct evidence: a fresh crash log showed the
// UNMODIFIED body of -[AppleEthernetSettingsController viewDidLoad] running (its own real symbol/offset in its own
// plugin bundle image, setting up a UITableView and calling -setFrame: on it, which is exactly what threw) -- meaning
// the -viewDidLoad hook above, despite being logged as "installed" at %ctor time, was NEVER ACTUALLY INTERCEPTING calls
// to it. Root cause: AppleEthernetSettingsController overrides -viewDidLoad itself (confirmed directly by that crash
// frame's own symbol), so Objective-C message dispatch resolves straight to the SUBCLASS's own implementation --
// hooking the SUPERCLASS's (UIViewController's) implementation, even with an isKindOfClass: check inside, can only ever
// intercept a call that WOULD have run UIViewController's own base method; it can never intercept a subclass's own
// override, no matter how the check inside is written. This is not a lazy-loading problem (that's what the generic-
// superclass-hook workaround elsewhere in this codebase is correctly for) -- -loadView's hook above genuinely worked
// only because AppleEthernetSettingsController happens to inherit UIViewController's base -loadView rather than
// overriding it too. Fix: hook the exact class directly, the same way WFNetworkSettingsViewController is hooked below
// (which DOES work, confirmed by its own catch firing in a real crash log tonight) -- and since AppleEthernetSettingsController
// is a real, nameable class (not one requiring runtime string lookup tricks), a plain @interface forward-declaration is enough
// for Logos to resolve it, same as any other named class in this file. No more replacing -loadView/-viewDidLoad outright:
// %orig now runs FULLY (so whatever the real Settings UI would normally show still shows, unless it throws), wrapped in
// @try/@catch, exactly the same robust, don't-need-to-know-the-exact-nested-cause pattern already proven below.
// In a NAMED group, deliberately NOT %init'd at %ctor time: the class must actually exist for %init to resolve and
// install this hook, and (unlike WFNetworkSettingsViewController, apparently preloaded for some unrelated WiFi-Settings
// reason) it genuinely is not loaded yet at Preferences' cold launch -- confirmed directly: a crash log AFTER this exact
// hook was shipped still showed -[AppleEthernetSettingsController viewDidLoad]'s own unmodified symbol running, meaning
// %init silently found no class to hook. See the %ctor below for the poll that installs this group once the class is
// real, the moment the user actually navigates far enough to load it.
%group EthernetDetailFix
@interface AppleEthernetSettingsController : UIViewController
@end
%hook AppleEthernetSettingsController
- (void)viewDidLoad {
    @try {
        %orig;
    } @catch (NSException *e) {
        MLog([NSString stringWithFormat:@"[ethernetfix] AppleEthernetSettingsController -viewDidLoad threw %@: %@ -- showing a fallback view instead of crashing", e.name, e.reason]);
        for (UIView *v in [self.view.subviews copy]) [v removeFromSuperview];
        self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(self.view.bounds, 24.0, 24.0)];
        label.text = @"Ethernet settings for this interface aren't available.\n\n(Apple's own settings page for this crashes — this message replaces it rather than letting that happen.)";
        label.numberOfLines = 0;
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = [UIColor secondaryLabelColor];
        label.font = [UIFont systemFontOfSize:15];
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:label];
    }
}
- (void)viewWillAppear:(BOOL)animated {
    @try {
        %orig;
    } @catch (NSException *e) {
        MLog([NSString stringWithFormat:@"[ethernetfix] AppleEthernetSettingsController -viewWillAppear: threw %@: %@ -- swallowed", e.name, e.reason]);
    }
}
- (void)viewDidLayoutSubviews {
    @try {
        %orig;
    } @catch (NSException *e) {
        MLog([NSString stringWithFormat:@"[ethernetfix] AppleEthernetSettingsController -viewDidLayoutSubviews threw %@: %@ -- swallowed", e.name, e.reason]);
    }
}
%end
%end   // EthernetDetailFix group

// FOURTH ATTEMPT (2026-09-23), found after the owner reproduced the crash with a REAL Ethernet interface connected (not just a
// phantom/disconnected one -- confirmed via a fresh crash log that it is the exact same crash regardless, ruling out
// "maybe a real connection behaves differently"). This one is a fundamentally different angle from the three attempts
// above, all of which tried to intercept navigation BEFORE reaching the crash site (and none of which actually stopped
// it, even attempt #3's row-selection block, confirmed against a real tap this time, not just simulated selection).
// Instead of guessing where in Settings' navigation architecture to intercept, this fixes the crash AT its exact site,
// regardless of how it's reached.
//
// Real crash log, read fresh, not reused from before: -[_UIFilteredDataSource tableView:numberOfRowsInSection:] forwards
// to its own `_tableDataSource` ivar (confirmed via classearch_/methsearch_: `id<UITableViewDataSource> _tableDataSource`,
// a plain generic UIKit wrapper class -- NOT Ethernet-specific, likely reused all over Settings for search-filtered
// lists) and throws doesNotRecognizeSelector: because that wrapped object does not actually respond to the required
// UITableViewDataSource method it's being asked for -- a genuine stock Apple bug in how WFNetworkSettingsViewController
// (WiFi framework code, reused for the Ethernet page) configures this wrapper for an Ethernet interface specifically.
// Fix: hook the three UITableViewDataSource methods _UIFilteredDataSource implements itself (found via a full method
// dump, not guessed -- it also custom-implements -respondsToSelector:/-forwardingTargetForSelector:, forwarding
// everything ELSE to _tableDataSource, but these three it answers directly, which is exactly where the crash is) and
// defensively check the wrapped `tableDataSource` actually responds before forwarding to %orig at all. This ONLY
// changes behavior when the wrapped object is ALREADY broken (a well-formed _UIFilteredDataSource anywhere else in
// Settings responds YES and behaves exactly as before, %orig runs normally) -- same category as every other hook in
// this codebase: wrapping an existing method the OS already calls, never alloc/init of anything.
// FIFTH ATTEMPT, same session: the fourth attempt above (guarding _UIFilteredDataSource's three data-source methods with a
// respondsToSelector check before forwarding) did NOT stop the crash -- confirmed against a second real tap: the crash log
// shows the hook DID fire (`_logos_method$_ungrouped$_UIFilteredDataSource$tableView$numberOfRowsInSection$` is right there
// in the stack) and fell through to %orig, meaning `tableDataSource` DID claim to respond to the selector being guarded --
// so the real crash is happening from something ELSE %orig's own implementation calls internally that this codebase does
// not have visibility into (this .ips crash format does not include the NSException's reason string, so the exact missing
// selector name could not even be read off the log). Rather than keep guessing which nested call needs guarding, this
// switches to a robust, catch-all approach: `@try`/`@catch` genuinely catches an uncaught NSException in Objective-C (this
// crash IS one -- SIGABRT via objc_exception_throw/doesNotRecognizeSelector:, not a raw memory-corruption SIGSEGV), so
// wrapping the one call that we know reliably triggers the whole broken cascade (WFNetworkSettingsViewController's own
// -viewDidLoad, named directly in every crash log so far) stops it regardless of exactly which selector deep inside is
// actually missing. If it throws, replace the crashing view controller's content with a plain fallback message instead of
// letting the exception propagate up and abort the process.
@interface WFNetworkSettingsViewController : UIViewController
@end
%hook WFNetworkSettingsViewController
// TRUE ROOT CAUSE FOUND (confirmed via the caught exception's own reason string, not guessed): the exception says
// `-[AppleEthernetSettingsController network]: unrecognized selector` -- WFNetworkSettingsViewController (reused
// WiFi-framework UI) asks whatever embeds it for a `-network` (a WFNetwork object, presumably), and
// AppleEthernetSettingsController (the Ethernet-specific parent, never designed as a WiFi data source) simply never
// implements it. That single missing method is what corrupts the `_UIFilteredDataSource` setup, which then throws from
// MULTIPLE different table view call sites at different times (-viewDidLoad's own initial layout, and separately, later,
// -viewWillAppear:'s/-viewDidAppear:'s content-offset restoration -- confirmed via a second real crash log after the
// -viewDidLoad fix alone). Rather than patch every individual call site one at a time as new ones turn up, the same
// @try/@catch fallback pattern is applied to all three UIViewController lifecycle methods that could plausibly trigger
// the same broken data source.
- (void)viewDidLoad {
    @try {
        %orig;
    } @catch (NSException *e) {
        MLog([NSString stringWithFormat:@"[ethernetfix] WFNetworkSettingsViewController -viewDidLoad threw %@: %@ -- showing a fallback view instead of crashing", e.name, e.reason]);
        for (UIView *v in [self.view.subviews copy]) [v removeFromSuperview];
        self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(self.view.bounds, 24.0, 24.0)];
        label.text = @"Ethernet settings for this interface aren't available.\n\n(Apple's own settings page for this crashes — this message replaces it rather than letting that happen.)";
        label.numberOfLines = 0;
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = [UIColor secondaryLabelColor];
        label.font = [UIFont systemFontOfSize:15];
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:label];
    }
}
- (void)viewWillAppear:(BOOL)animated {
    @try {
        %orig;
    } @catch (NSException *e) {
        MLog([NSString stringWithFormat:@"[ethernetfix] WFNetworkSettingsViewController -viewWillAppear: threw %@: %@ -- swallowed", e.name, e.reason]);
    }
}
- (void)viewDidAppear:(BOOL)animated {
    @try {
        %orig;
    } @catch (NSException *e) {
        MLog([NSString stringWithFormat:@"[ethernetfix] WFNetworkSettingsViewController -viewDidAppear: threw %@: %@ -- swallowed", e.name, e.reason]);
    }
}
- (void)viewDidLayoutSubviews {
    @try {
        %orig;
    } @catch (NSException *e) {
        MLog([NSString stringWithFormat:@"[ethernetfix] WFNetworkSettingsViewController -viewDidLayoutSubviews threw %@: %@ -- swallowed", e.name, e.reason]);
    }
}
%end

// ALWAYS SHOW THE ETHERNET SECTION (2026-09-24; ported from Lynx's "showSettingsEthernetSection", which the M1 had on): Settings >
// General only lists Ethernet while it sees an Ethernet interface, and Preferences asks this watcher (Preferences.framework, the same
// class Lynx hooks) whether there is one. Answering YES keeps the section visible with no adapter connected, on iOS 15 and 16; the pages
// behind it are the stock ones (with the crash catches above). Installed only if the class exists.
%group EthernetAlwaysShow
@interface PSSystemConfigurationDynamicStoreEthernetWatcher : NSObject
@end
%hook PSSystemConfigurationDynamicStoreEthernetWatcher
- (BOOL)hasEthernetNetworkInterfaces {
    return YES;
}
%end
%end

%ctor {
    %init;
    if (MSBDOtherTweakDoing(kMSBDDupEthernetSection, NO)) MLog(@"[ethernetfix] Lynx shows the Ethernet section already: ours is not added");
    else if (objc_getClass("PSSystemConfigurationDynamicStoreEthernetWatcher")) {
        %init(EthernetAlwaysShow);
        MLog(@"[ethernetfix] the Ethernet section is always shown (PSSystemConfigurationDynamicStoreEthernetWatcher hooked)");
    } else MLog(@"[ethernetfix] PSSystemConfigurationDynamicStoreEthernetWatcher not found: the Ethernet section shows only with an adapter");
    // AppleEthernetSettingsController does not exist yet at this point (confirmed live, see the EthernetDetailFix group's
    // own comment above) -- poll for it rather than %init'ing that group immediately, since %init only ever resolves the
    // class ONCE, at the moment it's called; a class that shows up later would be silently missed forever otherwise.
    // Every 0.5s is cheap (a single objc_getClass call) and the timer cancels itself the instant the class is found, so
    // this costs nothing once Settings has actually been navigated deep enough to load it.
    static dispatch_source_t ethernetPoll;
    ethernetPoll = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(ethernetPoll, dispatch_time(DISPATCH_TIME_NOW, 0), (uint64_t)(0.5 * NSEC_PER_SEC), 100 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(ethernetPoll, ^{
        if (objc_getClass("AppleEthernetSettingsController")) {
            %init(EthernetDetailFix);
            MLog(@"[ethernetfix] AppleEthernetSettingsController became available -- EthernetDetailFix hook installed");
            dispatch_source_cancel(ethernetPoll);
        }
    });
    dispatch_resume(ethernetPoll);
}
