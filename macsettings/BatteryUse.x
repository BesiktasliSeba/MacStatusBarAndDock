// Battery Use (MacStatusBar&Dock 1.7.8, battery drain F1; plans/battery-drain.md): our group on Apple's Settings > Battery > Battery Health page
// (opened on iPad by BatteryHealth.x), after our Charging group where the Charge Limit's job puts one, else after our Cycle Count row (right
// after Maximum Capacity), else -- no cycle count figure -- at the end of the page. Stock rows and a footer:
//  - Sleep Guard (switch, on unless switched off): sshtoggled clears a power assertion that keeps the iPad awake after the process that owned it
//    is gone (a SpringBoard that died with its start-up assertion: common/SleepGuard.h).
//  - iPad Can't Sleep (a status row): only while one is stuck and the guard will not or could not clear it -- its reason as the value.
// The page asks the helper for a fresh look when it builds the group with an old state (MSBD_SG_CHECK) and is rebuilt when the helper has written
// a new one while the page shows (MSBD_SG_UPDATED). With another battery health tweak too, as BatteryHealth.x: neither enabler adds a group there.
// A group of our own put into the page's list by its own -specifiers (the page builds every group in code there, 15-18), not one of Apple's
// group builders: the Charging group of the Charge Limit's job stays its own code.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <notify.h>
#import <mach-o/dyld.h>
#import <unistd.h>
#import "../common/SleepGuard.h"

#define MSBD_SG_CHECK   "com.besiktasliseba.sleepguard.check"
#define MSBD_SG_UPDATED "com.besiktasliseba.sleepguard.updated"

@interface PSSpecifier : NSObject
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(long long)cell edit:(Class)edit;
+ (instancetype)groupSpecifierWithID:(NSString *)identifier;
+ (instancetype)groupSpecifierWithName:(NSString *)name;
- (void)setIdentifier:(NSString *)identifier;
- (NSString *)identifier;
- (void)setProperty:(id)value forKey:(NSString *)key;
- (long long)cellType;
@end
@interface UIViewController (MSBUPage)
- (void)reloadSpecifiers;
@end

enum { kMSBUCellGroup = 0, kMSBUCellSwitch = 6, kMSBUCellTitleValue = 4 };
static __weak UIViewController *gMSBUPage;   // (the page showing the group: rebuilt when the helper writes a new state)

static NSDictionary *MSBUState(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:@MSBD_SG_STATE];
    return [d isKindOfClass:[NSDictionary class]] ? d : @{};
}
static NSString *MSBUCantSleepValue(NSDictionary *st) {   // ("Since 3:12 AM" / the reason)
    NSString *why = [st[@"why"] isKindOfClass:[NSString class]] ? st[@"why"] : @"";
    double since = [st[@"stuckSince"] doubleValue];
    if ([why isEqualToString:@"Sleep Guard is off"]) return @"Sleep Guard Off";
    if (since > 0) return [NSString stringWithFormat:@"Since %@", [NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:since]
                                                                                                    dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterShortStyle]];
    return @"";
}
static NSArray *MSBUSpecifiers(UIViewController *page) {
    gMSBUPage = page;
    NSDictionary *st = MSBUState();
    if (time(NULL) - [st[@"checked"] doubleValue] > 60) notify_post(MSBD_SG_CHECK);   // (an old state: the helper looks; MSBD_SG_UPDATED rebuilds)
    PSSpecifier *g = [PSSpecifier groupSpecifierWithName:@"Battery Use"];
    [g setIdentifier:@"MSBD_BATTERY_USE_GROUP"];
    // (KT, 1.7.9: the footer says what it saves -- deep sleep, the processor, the battery -- not only what it does)
    NSMutableString *foot = [@"Sometimes a process that has already quit, such as SpringBoard before a respring, leaves behind a request that keeps "
                             "iPad awake. iPad then can't go into deep sleep with the screen off: the processor keeps running and the battery "
                             "drains much faster than it does asleep, on some iPads by over 10% a day. Sleep Guard clears that leftover request when the screen goes off, so iPad "
                             "sleeps and keeps its charge. It never acts while the screen is on or while something real keeps iPad awake, "
                             "such as music, a download or a backup. MacStatusBar&Dock also pauses its own timers while the screen is off." mutableCopy];
    double cleared = [st[@"lastClear"] doubleValue];
    if (cleared > 0) [foot appendFormat:@" Last cleared %@.", [NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:cleared]
                                                                                              dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle]];
    [g setProperty:foot forKey:@"footerText"];
    PSSpecifier *sw = [PSSpecifier preferenceSpecifierNamed:@"Sleep Guard" target:page set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:)
                                                     detail:Nil cell:kMSBUCellSwitch edit:Nil];
    [sw setProperty:@MSBD_SG_KEY forKey:@"key"];
    [sw setProperty:@MSBD_SG_DOMAIN forKey:@"defaults"];
    [sw setProperty:@YES forKey:@"default"];
    [sw setProperty:@MSBD_SG_CHANGED forKey:@"PostNotification"];
    [sw setIdentifier:@"MSBD_SLEEP_GUARD"];
    NSMutableArray *specs = [NSMutableArray arrayWithObjects:g, sw, nil];
    if ([st[@"cantSleep"] boolValue] && [st[@"stuck"] intValue] > 0) {
        PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:@"iPad Can't Sleep" target:page set:NULL get:@selector(msbdCantSleepValue:) detail:Nil cell:kMSBUCellTitleValue edit:Nil];
        [row setIdentifier:@"MSBD_CANT_SLEEP"];
        [specs addObject:row];
    }
    return specs;
}
static NSString *MSBUCantSleepGetter(id self, SEL _cmd, id specifier) { return MSBUCantSleepValue(MSBUState()); }
// Where the group goes in the page's list: after the Charging group's rows if it is there, else after the Cycle Count group's row (BatteryHealth.x
// adds it right after Maximum Capacity's group, when the gauge has a cycle count), else at the end.
static NSUInteger MSBUInsertIndex(NSArray *specs) {
    NSUInteger after = NSNotFound, n = specs.count;
    for (NSString *anchor in @[@"MSBD_CHARGING_GROUP", @"MSBD_CYCLE_COUNT_GROUP"]) {
        for (NSUInteger i = 0; i < n; i++) {
            if (![[specs[i] identifier] isEqual:anchor]) continue;
            NSUInteger j = i + 1;
            while (j < n && [specs[j] cellType] != kMSBUCellGroup) j++;   // (past the group's rows, to the next group or the end)
            after = j; break;
        }
        if (after != NSNotFound) return after;
    }
    return n;
}
static BOOL MSBUHasGroup(NSArray *specs) {
    for (id s in specs) if ([[s identifier] isEqual:@"MSBD_BATTERY_USE_GROUP"]) return YES;
    return NO;
}

%group MSBUPage
%hook BatteryHealthUIController
- (id)specifiers {
    NSArray *r = %orig;
    if (![r isKindOfClass:[NSArray class]] || MSBUHasGroup(r)) return r;
    NSMutableArray *m = [r mutableCopy];
    NSArray *ours = MSBUSpecifiers((UIViewController *)self);
    [m insertObjects:ours atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(MSBUInsertIndex(m), ours.count)]];
    Ivar iv = class_getInstanceVariable(object_getClass(self), "_specifiers");   // (PSListController's list: the page's later reads see ours)
    if (iv) object_setIvarWithStrongDefault(self, iv, m);
    return m;
}
%end
%end

// What the check below decided (1.7.9, for the Settings search: common/OwnPageState.h): 0 not yet (Apple's battery pages not loaded in this
// process), 1 a page we do not know -- our group is not put in --, 2 our group goes into the page.
static int gMSBUVerdict = 0;
__attribute__((visibility("hidden"))) int MSBUGroupVerdict(void) { return gMSBUVerdict; }   // (TweakSearch.x)
static void MSBUTryInit(void) {
    static BOOL done; if (done) return;
    Class health = objc_getClass("BatteryHealthUIController");
    if (!health) return;
    done = YES;
    if (!class_getInstanceMethod(health, @selector(specifiers)) || !class_getInstanceVariable(health, "_specifiers")) { gMSBUVerdict = 1; return; }   // (a page we do not know)
    gMSBUVerdict = 2;
    class_addMethod(health, sel_registerName("msbdCantSleepValue:"), (IMP)MSBUCantSleepGetter, "@24@0:8@16");
    int t = 0;
    notify_register_dispatch(MSBD_SG_UPDATED, &t, dispatch_get_main_queue(), ^(int tok) {
        UIViewController *page = gMSBUPage;
        if (page.isViewLoaded && page.view.window) [page reloadSpecifiers];
    });
    %init(MSBUPage);
}
static void MSBUBundleLoaded(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef info) { MSBUTryInit(); }
static void MSBUImageAdded(const struct mach_header *mh, intptr_t slide) {
    static BOOL queued; if (queued || !objc_getClass("BatteryHealthUIController")) return;
    queued = YES; dispatch_async(dispatch_get_main_queue(), ^{ MSBUTryInit(); });
}
%ctor {
    MSBUTryInit();
    CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(), NULL, MSBUBundleLoaded, (__bridge CFStringRef)NSBundleDidLoadNotification, NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    _dyld_register_func_for_add_image(MSBUImageAdded);
}
