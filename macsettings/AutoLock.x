// Auto-Lock: 30 minutes, 1 hour and 2 hours in Settings > Display & Brightness > Auto-Lock (2026-09-24), after the longest stock time and
// before Never, looking exactly like the stock rows (same list, same checkmark; titles made by the system's own duration formatter, so they read
// and translate like "15 minutes" above them).
// iOS 15: DBSSettingsController fills that list itself (the plist's 30 s ... 5 min is replaced by what ManagedConfiguration allows: 2/5/10/15 min
// on this iPad) in -_updateAutoLockSpecifiers: / -_localizeAutoLockTitlesWithSpecifiers:, so our three are added right after it has done so. The
// chosen value is stored by the system as usual (ManagedConfiguration's maxInactivity, via -setScreenLock:specifier:), which the idle timer uses.
#import <UIKit/UIKit.h>
#if DEBUG
#define MSTestFlag(path) (access((path), F_OK) == 0)   // a /tmp test switch (debug builds only; a release build behaves as if none existed)
#else
#define MSTestFlag(path) 0
#endif
#import <mach-o/dyld.h>
#import <unistd.h>
#import <objc/message.h>

@interface PSSpecifier : NSObject
- (NSArray *)values;
- (NSDictionary *)titleDictionary;
- (NSDictionary *)shortTitleDictionary;
- (void)setValues:(NSArray *)values titles:(NSArray *)titles shortTitles:(NSArray *)shortTitles;
- (id)propertyForKey:(NSString *)key;
- (void)setProperty:(id)value forKey:(NSString *)key;
- (void)setTitleDictionary:(NSDictionary *)d;
- (void)setShortTitleDictionary:(NSDictionary *)d;
- (NSString *)identifier;
@end

static NSString *MSDurationTitle(NSInteger seconds) {
    static NSDateComponentsFormatter *f;
    if (!f) { f = [NSDateComponentsFormatter new]; f.unitsStyle = NSDateComponentsFormatterUnitsStyleFull; f.allowedUnits = NSCalendarUnitHour | NSCalendarUnitMinute; }
    return [f stringFromTimeInterval:seconds] ?: [NSString stringWithFormat:@"%ld", (long)seconds];
}
static BOOL MSIsAutoLockSpecifier(PSSpecifier *s) {
    if (![s respondsToSelector:@selector(values)] || ![s respondsToSelector:@selector(propertyForKey:)]) return NO;
    id label = [s propertyForKey:@"label"];
    if ([label isEqual:@"AUTOLOCK"] || [[s identifier] isEqual:@"AUTOLOCK"]) return YES;
    NSArray *v = [s values];   // (fallback: the list with 5 minutes and Never in it)
    return [v isKindOfClass:[NSArray class]] && [v containsObject:@300] && ([v containsObject:@(-1)] || [v containsObject:@(INT_MAX)]);
}
static void MSAddLongAutoLockTimes(NSArray *specifiers) {
#if DEBUG
    if (MSTestFlag("/tmp/macsettings-debug")) { FILE *f = fopen("/tmp/macsettings.log", "a"); if (f) { fprintf(f, "autolock: add called (%lu specifiers)\n", (unsigned long)specifiers.count); fclose(f); } }
#endif
    if (MSTestFlag("/tmp/ms-autolock-off")) return;   // (debug kill switch)
    for (PSSpecifier *s in specifiers) {
        @try { if (![s isKindOfClass:NSClassFromString(@"PSSpecifier")] || !MSIsAutoLockSpecifier(s)) continue; } @catch (NSException *e) { continue; }
        NSMutableArray *values = [[s values] mutableCopy];
        if (!values.count) return;
        if ([values containsObject:@1800]) {   // values already ours, but the system may have just put its own titles back: add ours to them again
            NSMutableDictionary *td = [[s titleDictionary] mutableCopy] ?: [NSMutableDictionary dictionary], *sd = [[s shortTitleDictionary] mutableCopy] ?: [NSMutableDictionary dictionary];
            for (NSNumber *v in @[@1800, @3600, @7200]) { if (!td[v]) td[v] = MSDurationTitle(v.integerValue); if (!sd[v]) sd[v] = td[v]; }
            if ([s respondsToSelector:@selector(setTitleDictionary:)]) [s setTitleDictionary:td];
            if ([s respondsToSelector:@selector(setShortTitleDictionary:)]) [s setShortTitleDictionary:sd];
            return;
        }
        // (1.3.7, audit L-21) Only where the system allows them: a device management profile that caps Auto-Lock leaves Never out of the list (the cap
        // is the list's end), and Low Power Mode holds Auto-Lock at 30 seconds -- our longer times would show a tick the system does not keep.
        BOOL neverAllowed = NO;
        for (NSNumber *v in values) { NSInteger x = [v integerValue]; if (x < 0 || x >= INT_MAX) { neverAllowed = YES; break; } }
        if (!neverAllowed || [NSProcessInfo processInfo].isLowPowerModeEnabled) {
#if DEBUG
            if (MSTestFlag("/tmp/macsettings-debug")) { FILE *f = fopen("/tmp/macsettings.log", "a"); if (f) { fprintf(f, "autolock: longer times not added (%s)\n", [NSProcessInfo processInfo].isLowPowerModeEnabled ? "Low Power Mode" : "Auto-Lock is capped: no Never"); fclose(f); } }
#endif
            return;
        }
        NSDictionary *titles = [s titleDictionary], *shortTitles = [s shortTitleDictionary];
#if DEBUG
        if (MSTestFlag("/tmp/macsettings-debug")) {
            NSString *line = [NSString stringWithFormat:@"autolock: values %@ | titles %@ | short %@ | props %@ %@ %@\n", values, titles, shortTitles, [s propertyForKey:@"validValues"], [s propertyForKey:@"validTitles"], [s propertyForKey:@"shortTitles"]];
            FILE *f = fopen("/tmp/macsettings.log", "a"); if (f) { fputs(line.UTF8String, f); fclose(f); }
        }
#endif
        NSUInteger never = values.count;
        for (NSUInteger i = 0; i < values.count; i++) { NSInteger v = [values[i] integerValue]; if (v < 0 || v >= INT_MAX) { never = i; break; } }
        NSMutableArray *t = [NSMutableArray array], *st = [NSMutableArray array];
        NSArray *add = @[@1800, @3600, @7200];
        [values insertObjects:add atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(never, add.count)]];
        for (id v in values) {
            NSString *title = titles[v] ?: MSDurationTitle([v integerValue]);
            [t addObject:title];
            [st addObject:shortTitles[v] ?: title];
        }
        [s setValues:values titles:t shortTitles:st];
        // (the list page rebuilds its rows from these properties too: they must hold the same items, or it throws on the count mismatch)
        if ([s respondsToSelector:@selector(setProperty:forKey:)]) { [s setProperty:values forKey:@"validValues"]; [s setProperty:t forKey:@"validTitles"]; [s setProperty:st forKey:@"shortTitles"]; }
        return;
    }
}

%group MSAutoLock
%hook DBSSettingsController
- (void)_updateAutoLockSpecifiers:(id)specifiers {
    %orig;
    MSAddLongAutoLockTimes([specifiers isKindOfClass:[NSArray class]] ? specifiers : @[specifiers]);
}
- (void)_localizeAutoLockTitlesWithSpecifiers:(id)specifiers {
    %orig;
    MSAddLongAutoLockTimes([specifiers isKindOfClass:[NSArray class]] ? specifiers : @[specifiers]);
}
- (void)updateAutoLockSpecifier {
    %orig;
    SEL specs = NSSelectorFromString(@"specifiers");
    if ([(id)self respondsToSelector:specs]) MSAddLongAutoLockTimes(((id (*)(id, SEL))objc_msgSend)((id)self, specs));
}
%end
%end
%group MSAutoLockDebug
%hook PSListItemsController
- (id)itemsFromParent {
#if DEBUG
    if (MSTestFlag("/tmp/macsettings-debug")) {
        PSSpecifier *p = ((id (*)(id, SEL))objc_msgSend)((id)self, NSSelectorFromString(@"specifier"));
        NSString *line = [NSString stringWithFormat:@"autolock: itemsFromParent values %@ titles %lu short %lu\n", [[p values] componentsJoinedByString:@","], (unsigned long)[p titleDictionary].count, (unsigned long)[p shortTitleDictionary].count];
        FILE *f = fopen("/tmp/macsettings.log", "a"); if (f) { fputs(line.UTF8String, f); fclose(f); }
    }
#endif
    return %orig;
}
%end
%end

// DisplayAndBrightnessSettings is loaded when its page is first opened: the hooks go in as soon as the class exists.
static void MSAutoLockTryInit(void) {
    static BOOL done; if (done) return;
    if (!NSClassFromString(@"DBSSettingsController")) return;
    done = YES; %init(MSAutoLock);
    if (MSTestFlag("/tmp/macsettings-debug")) %init(MSAutoLockDebug);
}
static void MSAutoLockImageAdded(const struct mach_header *mh, intptr_t slide) {   // (not inside the dyld callback itself)
    static BOOL queued; if (queued || !NSClassFromString(@"DBSSettingsController")) return;
    queued = YES; dispatch_async(dispatch_get_main_queue(), ^{ MSAutoLockTryInit(); });
}
%ctor {
    MSAutoLockTryInit();
    _dyld_register_func_for_add_image(MSAutoLockImageAdded);
}
