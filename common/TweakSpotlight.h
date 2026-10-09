// TweakSpotlight.h -- the tweak settings rows donated to Spotlight ("Tweak Settings" in the Spotlight group of the Status Bar page; off unless
// switched on), shared by Settings (macsettings/TweakSearch.x: Settings' own CoreSpotlight index, whenever Settings starts or a switch changes) and
// SpringBoard (statusbar/SpotlightFiles.x: the same index, written for Settings, when a tweak is installed or removed while Settings is closed, and
// everything deleted when MacStatusBar&Dock itself is removed). Both build the same rows (common/TweakIndex.h, the same configuration) and keep one
// record of what was donated (com.besiktasliseba.macsettings tweakSpotlightHash / tweakSpotlightDate), so neither donates what the other already did.
// The includer defines MTS_LOG(...) first (variadic: a message expression has commas the preprocessor would split).
#pragma once
#import <UIKit/UIKit.h>
#import <CoreSpotlight/CoreSpotlight.h>
#import <notify.h>
#import <objc/runtime.h>
#import <unistd.h>
#import "TweakIndex.h"

#define kMTSSettingsDomain CFSTR("com.besiktasliseba.macsettings")
#define kMTSBarDomain CFSTR("com.besiktasliseba.macstatusbar")
#define kMTSPLDir @"/var/jb/Library/PreferenceLoader/Preferences"
#define kMTSBundleDir @"/var/jb/Library/PreferenceBundles"
#define kMTSIndexName @"com.besiktasliseba.msbd.TweakSettings"
#define kMTSRemoveAllNote "com.besiktasliseba.msbd.spotlight.removeall"   // (posted by the root helper when MacStatusBar&Dock is removed)
static const NSTimeInterval kMTSRedonateAfter = 7 * 86400.0;  // (donated rows live 30 days; donated again a week after the last time)

static BOOL MTSBool(CFStringRef key, CFStringRef domain, BOOL fallback) {
    CFPreferencesAppSynchronize(domain);
    CFPropertyListRef v = CFPreferencesCopyAppValue(key, domain);
    BOOL on = fallback;
    if (v && CFGetTypeID(v) == CFBooleanGetTypeID()) on = CFBooleanGetValue(v);
    else if (v && CFGetTypeID(v) == CFNumberGetTypeID()) { int n = fallback; CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &n); on = n != 0; }
    if (v) CFRelease(v);
    return on;
}
// The Status Bar page's Spotlight group (Tweak Settings, Actions, Windows, Desktop and Downloads) works only while our status bar is in use: with
// "Use Stock Status Bar" the group is hidden (stockHides), and Mac Status Bar switched off ("tweakEnabled") means not one part of it runs. Either
// way its switches count as off, and Tweak Settings' rows leave Spotlight (Settings and SpringBoard each delete a donation made before).
static BOOL MTSBarInUse(void) { return MTSBool(CFSTR("tweakEnabled"), kMTSBarDomain, YES) && !MTSBool(CFSTR("stockStatusBar"), kMTSBarDomain, NO); }
static BOOL MTSSpotlightSwitch(void) { return MTSBarInUse() && MTSBool(CFSTR("spotlightTweakSettings"), kMTSBarDomain, NO); }

static uint64_t MTSHomeBarPill(void) {   // (MacSettings.x HBPillState: 1 = this iPad has no home bar, so no Home Bar row)
    static int token = 0;
    if (!token) notify_register_check("com.besiktasliseba.machomebar.pill", &token);
    uint64_t v = 0; notify_get_state(token, &v);
    return v;
}
// The index's configuration: tweak pages (PreferenceLoader), our own pages and our rows of Settings' main list, as MacSettings.x adds them.
// Pointer and Keyboard (only there while a trackpad or keyboard is attached) are added by the Settings search itself, never donated.
static MTIConfig *MTSBaseConfig(void) {
    MTIConfig *c = [MTIConfig new];
    c.plDirs = @[kMTSPLDir];
    c.bundleDirs = @[kMTSBundleDir, @"/var/jb/System/Library/PreferenceBundles"];
    c.supportDir = @"/var/jb/Library/Application Support";
    c.languages = [NSLocale preferredLanguages];
    c.cfVersion = kCFCoreFoundationVersionNumber;
    c.maxPerPane = 400; c.maxTotal = 6000;
    c.own = @[@{@"id": @"MAC_STATUS_BAR", @"title": @"Status Bar", @"bundle": [kMTSBundleDir stringByAppendingPathComponent:@"MacStatusBarPrefs.bundle"]},
              @{@"id": @"DOCK_MAGNIFICATION", @"title": @"Dock", @"bundle": [kMTSBundleDir stringByAppendingPathComponent:@"DockMagnificationPrefs.bundle"]}];
    c.skipBundles = @[@"MacStatusBarPrefs", @"DockMagnificationPrefs"];   // (on iPadOS 17 our page is also a PreferenceLoader entry, hidden while our row is there)
    NSMutableArray *x = [NSMutableArray array];
    if (access("/var/jb/usr/sbin/sshd", F_OK) == 0) [x addObject:@{@"id": @"SSH_TOGGLE", @"title": @"SSH"}];
    if (MTSHomeBarPill() != 1) [x addObject:@{@"id": @"HOMEBAR_TOGGLE", @"title": @"Home Bar"}];
    c.extras = x;
    return c;
}

// ---- items in Apple's format (PSCoreSpotlightIndexer's: subject, contentDescription, keywords, theme = category, ranking hint) ----------------
static NSData *MTSThumbnail(NSString *path) {   // (the page's icon, made small: one per donated row)
    static NSCache *cache; static dispatch_once_t once; dispatch_once(&once, ^{ cache = [NSCache new]; });
    if (!path) return nil;
    id hit = [cache objectForKey:path];
    if (hit) return hit == [NSNull null] ? nil : hit;
    UIImage *img = [UIImage imageWithContentsOfFile:path];
    NSData *png = nil;
    if (img.size.width > 0) {
        UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat]; f.scale = 2;
        png = UIImagePNGRepresentation([[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(29, 29) format:f] imageWithActions:^(UIGraphicsImageRendererContext *c) { [img drawInRect:CGRectMake(0, 0, 29, 29)]; }]);
    }
    [cache setObject:png ?: (id)[NSNull null] forKey:path];
    return png;
}
// spotlight NO: a row for the Settings search (Apple's breadcrumb, the page before its rows); YES: a donated row (where it is: "Settings → Atria
// → General"; the lowest ranking hint, so Apple's own rows rank first; the page's icon; lives 30 days).
static CSSearchableItem *MTSItem(MTIEntry *e, BOOL spotlight, NSString *settingsName) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CSSearchableItemAttributeSet *a = [[CSSearchableItemAttributeSet alloc] initWithItemContentType:@"com.apple.Preferences.firstParty"];
#pragma clang diagnostic pop
    a.title = e.title; a.displayName = e.title; a.subject = e.title;
    NSString *settings = MTIStr(settingsName) ?: @"Settings";
    a.contentDescription = spotlight ? (e.crumb.length ? [NSString stringWithFormat:@"%@ → %@", settings, e.crumb] : settings) : (e.crumb ?: @"");
    a.keywords = e.keywords;
    a.theme = e.category;
    a.identifier = e.uid;
    a.rankingHint = spotlight ? @0 : @(e.depth);
    if (spotlight) a.thumbnailData = MTSThumbnail(e.iconPath);
    CSSearchableItem *it = [[CSSearchableItem alloc] initWithUniqueIdentifier:e.uid domainIdentifier:kMTIDomain attributeSet:a];
    if (spotlight) it.expirationDate = [NSDate dateWithTimeIntervalSinceNow:30 * 86400.0];
    return it;
}

// ---- Settings' own CoreSpotlight index -----------------------------------------------------------------------------------------------------
// In Settings: its own index. In SpringBoard: the same index written for Settings (CoreSpotlight's bundle identifier initializer; SpringBoard has
// com.apple.private.corespotlight.internal) -- nil when that initializer is not there.
@interface CSSearchableIndex (MSBDBundleOverride)
- (instancetype)initWithName:(NSString *)name protectionClass:(NSString *)protectionClass bundleIdentifier:(NSString *)bundleIdentifier;
@end
static CSSearchableIndex *MTSSpotIndex(void) {
    static CSSearchableIndex *idx; static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!objc_getClass("CSSearchableIndex")) return;
        if ([[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.Preferences"])
            idx = [[CSSearchableIndex alloc] initWithName:kMTSIndexName protectionClass:NSFileProtectionCompleteUntilFirstUserAuthentication];   // (Apple's own items' protection class)
        else if ([CSSearchableIndex instancesRespondToSelector:@selector(initWithName:protectionClass:bundleIdentifier:)])
            idx = [[CSSearchableIndex alloc] initWithName:kMTSIndexName protectionClass:NSFileProtectionCompleteUntilFirstUserAuthentication bundleIdentifier:@"com.apple.Preferences"];
    });
    return idx;
}
static NSString *MTSStoredString(CFStringRef key) {
    CFPreferencesAppSynchronize(kMTSSettingsDomain);
    CFPropertyListRef v = CFPreferencesCopyAppValue(key, kMTSSettingsDomain);
    NSString *s = v && CFGetTypeID(v) == CFStringGetTypeID() ? [(__bridge NSString *)v copy] : nil;
    if (v) CFRelease(v);
    return s;
}
static void MTSStoreDonation(NSString *hash) {   // (what was donated and when; nil = nothing donated: both keys removed)
    CFPreferencesSetAppValue(CFSTR("tweakSpotlightHash"), (__bridge CFStringRef)hash, kMTSSettingsDomain);
    CFPreferencesSetAppValue(CFSTR("tweakSpotlightDate"), hash ? (__bridge CFStringRef)[NSString stringWithFormat:@"%.0f", [NSDate date].timeIntervalSince1970] : NULL, kMTSSettingsDomain);
    CFPreferencesAppSynchronize(kMTSSettingsDomain);
}
static BOOL MTSWait(void (^start)(void (^done)(NSError *)), NSError **error, double seconds) {   // (one CoreSpotlight call, waited for)
    __block NSError *err = nil;
    dispatch_semaphore_t s = dispatch_semaphore_create(0);
    start(^(NSError *e) { err = e; dispatch_semaphore_signal(s); });
    BOOL inTime = dispatch_semaphore_wait(s, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC))) == 0;
    if (error) *error = inTime ? err : [NSError errorWithDomain:@"msbd" code:1 userInfo:@{NSLocalizedDescriptionKey: @"no answer"}];
    return inTime && !err;
}
// Everything we donated, deleted (the switch off, or MacStatusBar&Dock removed). Blocking: call it off the main thread.
static void MTSDeleteSpotlight(NSString *why) {
    CSSearchableIndex *idx = MTSSpotIndex();
    if (!idx) return;
    NSError *e = nil;
    BOOL ok = MTSWait(^(void (^done)(NSError *)) { [idx deleteSearchableItemsWithDomainIdentifiers:@[kMTIDomain] completionHandler:done]; }, &e, 20);
    if (ok) MTSStoreDonation(nil);
    MTS_LOG([NSString stringWithFormat:@"Spotlight: donation deleted (%@)%@", why, ok ? @"" : [@" error " stringByAppendingString:e.localizedDescription ?: @"?"]]);
}
// The donation brought up to date (blocking: call it off the main thread). Off: whatever we donated is deleted. On: donated again when the rows
// changed or a week after the last donation, all at once (ours deleted, then the new set: removed tweaks vanish). all = MTIBuild(MTSBaseConfig()).
static void MTSSyncSpotlight(NSArray<MTIEntry *> *all, BOOL on, NSString *why) {
    NSString *had = MTSStoredString(CFSTR("tweakSpotlightHash"));
    if (!on || !all) { if (had) MTSDeleteSpotlight(why); return; }
    CSSearchableIndex *idx = MTSSpotIndex();
    if (!idx) { MTS_LOG(@"Spotlight: no index to donate to"); return; }
    NSString *hash = MTIContentHash(all);
    double at = [MTSStoredString(CFSTR("tweakSpotlightDate")) doubleValue];
    if ([hash isEqualToString:had] && [NSDate date].timeIntervalSince1970 - at < kMTSRedonateAfter) { MTS_LOG([NSString stringWithFormat:@"Spotlight: donation current (%@, %lu rows)", why, (unsigned long)all.count]); return; }
    NSString *settings = MTIStr([[NSBundle bundleWithPath:@"/Applications/Preferences.app"] localizedInfoDictionary][@"CFBundleDisplayName"]) ?: @"Settings";   // (the app's name in the user's language)
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:all.count];
    for (MTIEntry *e in all) @autoreleasepool { [items addObject:MTSItem(e, YES, settings)]; }
    NSError *e = nil;
    BOOL ok = MTSWait(^(void (^done)(NSError *)) { [idx deleteSearchableItemsWithDomainIdentifiers:@[kMTIDomain] completionHandler:done]; }, &e, 20);
    for (NSUInteger i = 0; ok && i < items.count; i += 200) {
        NSArray *chunk = [items subarrayWithRange:NSMakeRange(i, MIN((NSUInteger)200, items.count - i))];
        ok = MTSWait(^(void (^done)(NSError *)) { [idx indexSearchableItems:chunk completionHandler:done]; }, &e, 30);
    }
    if (ok) MTSStoreDonation(hash);
    MTS_LOG([NSString stringWithFormat:@"Spotlight: %lu rows donated (%@)%@", (unsigned long)items.count, why, ok ? @"" : [@" error " stringByAppendingString:e.localizedDescription ?: @"?"]]);
}
