// test-choicetable.m -- Mac test of the choices' table (common/ExclusiveChoice.h, 1.8.0): the table (the engines' as before, BigSurCenter, Destra's),
// Choicy's lists changed and recorded the way Settings and the root helper both change them, the round trip back to the user's own settings, the
// give-back (a switch-off, the removal: our entries only, BigSurCenter too), what counts as the user's own switch-off, and the helper's rename
// record. With Control Center Style's rule (common/CCStyle.h): the iPad 2's setup -- BigSurCenter never set -- picked iPadOS and back. With Banner
// Style's (common/BannerStyle.h, item 2): an M1-like setup -- Destra loading but off in its own settings, Mac-Style Banners on -- updated (Mac, so
// Destra kept out), Destra picked and back, the give-back, the user's own switch-off; both choices in one change.
#import <Foundation/Foundation.h>
#include "../common/CCStyle.h"
#include "../common/BannerStyle.h"
#import "../common/ExclusiveChoice.h"

static int gFail = 0, gN = 0;
static void Expect(BOOL ok, NSString *what) { gN++; if (!ok) { gFail++; printf("  FAIL %s\n", what.UTF8String); } }
static NSMutableDictionary *Deep(NSDictionary *d) {   // (a deep mutable copy: what Settings and the helper read from the file)
    return (NSMutableDictionary *)CFBridgingRelease(CFPropertyListCreateDeepCopy(NULL, (__bridge CFDictionaryRef)d, kCFPropertyListMutableContainersAndLeaves));
}
// The Control Center Style choice applied as both sides do it: BigSurCenter kept with its own style, kept out with any other (installed: else
// our entries taken back).
static BOOL ApplyStyle(NSMutableDictionary *prefs, NSMutableDictionary *record, int style, BOOL installed, NSMutableArray *log) {
    NSArray *keep = installed && MSBDCCStyleLoadsBigSurCenter(style) ? @[@"BigSurCenter"] : @[], *deny = installed && !MSBDCCStyleLoadsBigSurCenter(style) ? @[@"BigSurCenter"] : @[];
    return MSBDExChoicyApply(prefs, record, keep, deny, installed ? @[] : @[@"BigSurCenter"], log);
}

// The Banner Style choice applied as both sides do it: Destra kept with its own style, kept out with any other (installed: else our entries taken
// back).
static BOOL ApplyBanners(NSMutableDictionary *prefs, NSMutableDictionary *record, int style, BOOL installed, NSMutableArray *log) {
    NSArray *keep = installed && MSBDBannerLoadsDestra(style) ? @[@"MacOSNotifications"] : @[], *deny = installed && !MSBDBannerLoadsDestra(style) ? @[@"MacOSNotifications"] : @[];
    return MSBDExChoicyApply(prefs, record, keep, deny, installed ? @[] : @[@"MacOSNotifications"], log);
}

// The published 1.7.9 helper's give-back, as a reference (git show 7115228:macsettings/sshtoggled/main.m, UndoOurChoicyChanges): the window engines'
// entries undone the same way, every other entry of the record skipped ("not a window engine -- left alone"); then it deletes the record.
static void Undo179(NSMutableDictionary *prefs, NSDictionary *record) {
    NSArray *engines = @[@"Aerial", @"MilkyWay4", @"MilkyWay3SubModule", @"Zetsu"];
    NSMutableDictionary *only = [NSMutableDictionary dictionary];
    for (NSString *listKey in record) {
        NSMutableDictionary *e = [NSMutableDictionary dictionary];
        for (NSString *entry in record[listKey]) if ([engines containsObject:entry]) e[entry] = record[listKey][entry];
        if (e.count) only[listKey] = e;
    }
    MSBDExChoicyUndo(prefs, only);
}

int main(void) {
    @autoreleasepool {
        // ---- the table ----
        Expect([MSBDExValues(@"windowEngine") isEqual:(@{@"aerial": @[@"Aerial"], @"milkyway": @[@"MilkyWay4", @"MilkyWay3SubModule"], @"zetsu": @[@"Zetsu"]})],
               @"the engines' libraries, as Settings and the helper had them");
        Expect([MSBDExPackages(@"windowEngine") isEqual:(@{@"aerial": @"jp.uzra.aerial", @"milkyway": @"jp.akusio.milkyway4", @"zetsu": @"jp.dcsyhi.zetsu"})], @"  ... and their packages");
        Expect([MSBDExLibs(@"controlCenterStyle", @"bigsurcenter") isEqual:@[@"BigSurCenter"]] && [MSBDExLibs(@"controlCenterStyle", @"mac") isEqual:@[]]
               && [MSBDExLibs(@"controlCenterStyle", @"stock") isEqual:@[]], @"Control Center Style: BigSurCenter's library; Mac and iPadOS have none (ours, Apple's)");
        Expect(MSBDExPackages(@"controlCenterStyle").count == 0 && MSBDExPackages(@"bannerStyle").count == 0, @"  ... no package named for BigSurCenter or Destra (whichever owns the library)");
        Expect([MSBDExLibs(@"bannerStyle", nil) isEqual:@[@"MacOSNotifications"]] && [MSBDExLibs(@"bannerStyle", @"destra") isEqual:@[@"MacOSNotifications"]]
               && [MSBDExLibs(@"bannerStyle", @"mac") isEqual:@[]] && [MSBDExLibs(@"bannerStyle", @"stock") isEqual:@[]], @"Banner Style (item 2): Destra's MacOSNotifications; Mac and iPadOS have none");
        Expect([MSBDExValues(@"bannerStyle") isEqual:(@{@"destra": @[@"MacOSNotifications"]})] && strcmp(MSBDBannerStyleValue(kMSBDBannerDestra), "destra") == 0,
               @"  ... under the value the Style page stores (Root.plist's destra)");
        Expect([MSBDExLibs(@"windowEngine", @"stagemanager") isEqual:@[]], @"Stage Manager as the engine: no library (Apple's)");
        NSSet *all = [NSSet setWithArray:MSBDExAllLibs()];
        Expect([all isEqual:[NSSet setWithArray:@[@"Aerial", @"MilkyWay4", @"MilkyWay3SubModule", @"Zetsu", @"BigSurCenter", @"MacOSNotifications"]]] && MSBDExAllLibs().count == 6,
               @"every library of the table, once each");
        Expect([MSBDExNameOf(@"MilkyWay3SubModule") isEqual:@"MilkyWay4"] && [MSBDExNameOf(@"MacOSNotifications") isEqual:@"Destra"] && !MSBDExNameOf(@"Choicy"), @"a library's option in words");

        // ---- the iPad 2's Choicy setup: Stage Manager the engine (Aerial and Zetsu kept out: Aerial by us), BigSurCenter loading ----
        NSDictionary *choicy0 = @{@"globalDeniedTweaks": @[@"Rose", @"Zetsu", @"Aerial"], @"preferenceVersion": @1,
                                  @"appSettings": @{@"com.apple.springboard": @{@"customTweakConfigurationEnabled": @NO, @"allowDenyMode": @2, @"allowedTweaks": @[@"BigSurCenter", @"Aerial"], @"deniedTweaks": @[]}}};
        NSDictionary *record0 = @{@"globalDeniedTweaks": @{@"Aerial": @"added"}};
        NSMutableDictionary *prefs = Deep(choicy0), *record = Deep(record0);
        // never set: BigSurCenter (installed, not switched off by the user -- in no list of Choicy's)
        BOOL userOff = MSBDExUserOff(@"BigSurCenter", prefs, record, @[], YES, NO);
        int style = MSBDCCStyleChosen(kMSBDCCStyleNone, YES, userOff, 0);
        Expect(!userOff && style == kMSBDCCStyleBigSurCenter, @"the iPad 2, never set: BigSurCenter (kept on update)");
        Expect(!ApplyStyle(prefs, record, style, YES, nil) && [prefs isEqual:choicy0] && [record isEqual:record0], @"  ... the install's apply changes nothing in Choicy or the record");
        // iPadOS picked: BigSurCenter into the global list, recorded
        Expect(ApplyStyle(prefs, record, kMSBDCCStyleStock, YES, nil), @"iPadOS picked: Choicy changed");
        Expect([prefs[@"globalDeniedTweaks"] isEqual:(@[@"Rose", @"Zetsu", @"Aerial", @"BigSurCenter"])], @"  ... BigSurCenter kept out of every process");
        Expect([record isEqual:(@{@"globalDeniedTweaks": @{@"Aerial": @"added", @"BigSurCenter": @"added"}})], @"  ... recorded as ours");
        Expect([prefs[@"appSettings"] isEqual:choicy0[@"appSettings"]], @"  ... SpringBoard's own list (not in force) left as it is");
        Expect(!ApplyStyle(prefs, record, kMSBDCCStyleStock, YES, nil) && !ApplyStyle(prefs, record, kMSBDCCStyleMac, YES, nil), @"  ... again, or Mac: nothing more to change");
        Expect(!MSBDExUserOff(@"BigSurCenter", prefs, record, @[], YES, NO), @"  ... our own entry is not the user's switch-off");
        // back to BigSurCenter: Choicy and the record exactly as they were
        Expect(ApplyStyle(prefs, record, kMSBDCCStyleBigSurCenter, YES, nil), @"BigSurCenter picked again: Choicy changed");
        Expect([prefs isEqual:choicy0] && [record isEqual:record0], @"  ... Choicy's settings and our record exactly as before the round trip");
        // the stored style gone (never set again) while our entry is there: the default is BigSurCenter again, and it loads
        prefs = Deep(choicy0); record = Deep(record0);
        ApplyStyle(prefs, record, kMSBDCCStyleStock, YES, nil);
        style = MSBDCCStyleChosen(kMSBDCCStyleNone, YES, MSBDExUserOff(@"BigSurCenter", prefs, record, @[], YES, NO), 0);
        Expect(style == kMSBDCCStyleBigSurCenter && ApplyStyle(prefs, record, style, YES, nil) && [prefs isEqual:choicy0] && [record isEqual:record0],
               @"never set again with our entry there: BigSurCenter, and Choicy back as it was");

        // ---- the give-back (a switch-off, the removal): our entries only, BigSurCenter too ----
        prefs = Deep(choicy0); record = Deep(record0);
        ApplyStyle(prefs, record, kMSBDCCStyleStock, YES, nil);
        NSArray *log = MSBDExChoicyUndo(prefs, record);
        Expect([prefs[@"globalDeniedTweaks"] isEqual:(@[@"Rose", @"Zetsu"])], @"give-back: our BigSurCenter and Aerial entries out, the user's Rose and Zetsu stay");
        Expect(![prefs[@"globalDeniedTweaks"] containsObject:@"BigSurCenter"], @"  ... a removal never leaves BigSurCenter denied by us");
        Expect([log containsObject:@"globalDeniedTweaks: removed BigSurCenter (we had added it)"], @"  ... said in the helper's log");
        NSMutableDictionary *user = Deep(choicy0); [user[@"globalDeniedTweaks"] addObject:@"BigSurCenter"];   // (the user's own switch-off: no record of ours)
        NSMutableDictionary *noRecord = Deep(record0);
        MSBDExChoicyUndo(user, noRecord);
        Expect([user[@"globalDeniedTweaks"] containsObject:@"BigSurCenter"], @"  ... the user's own BigSurCenter entry is theirs: left");
        prefs = Deep(choicy0); record = Deep(record0);
        ApplyStyle(prefs, record, kMSBDCCStyleStock, YES, nil);
        [prefs[@"globalDeniedTweaks"] removeObject:@"BigSurCenter"];   // (then the user took it out themselves)
        log = MSBDExChoicyUndo(prefs, record);
        Expect([log containsObject:@"globalDeniedTweaks: BigSurCenter already gone -- left as the user has it"], @"  ... an entry the user changed since: left as the user has it");
        NSMutableDictionary *foreign = Deep(choicy0);
        log = MSBDExChoicyUndo(foreign, @{@"globalDeniedTweaks": @{@"Rose": @"added"}});
        Expect([foreign[@"globalDeniedTweaks"] containsObject:@"Rose"] && [log.firstObject hasSuffix:@"not one of the choices' libraries -- left alone"], @"  ... a record naming another tweak: never touched");

        // ---- SpringBoard's own list in force ----
        NSMutableDictionary *allow = Deep(choicy0);   // (an allow list: BigSurCenter must leave it to be kept out, and come back)
        allow[@"appSettings"][@"com.apple.springboard"][@"customTweakConfigurationEnabled"] = @YES; allow[@"appSettings"][@"com.apple.springboard"][@"allowDenyMode"] = @1;
        NSDictionary *allow0 = [allow copy];
        NSDictionary *allowSnapshot = Deep(allow0);
        record = Deep(record0);
        ApplyStyle(allow, record, kMSBDCCStyleStock, YES, nil);
        Expect(![allow[@"appSettings"][@"com.apple.springboard"][@"allowedTweaks"] containsObject:@"BigSurCenter"] && [record[@"springboard.allowedTweaks"] isEqual:@{@"BigSurCenter": @"removed"}],
               @"SpringBoard's allow list in force: BigSurCenter taken out of it, recorded");
        ApplyStyle(allow, record, kMSBDCCStyleBigSurCenter, YES, nil);
        // (a list's members, not their order: an entry taken out of an allow list and put back goes to its end, as Choicy's own page does it)
        BOOL (^sameSB)(NSDictionary *, NSDictionary *) = ^BOOL(NSDictionary *a, NSDictionary *b) {
            NSMutableDictionary *x = Deep(a[@"appSettings"][@"com.apple.springboard"]), *y = Deep(b[@"appSettings"][@"com.apple.springboard"]);
            for (NSString *k in @[@"allowedTweaks", @"deniedTweaks"]) { x[k] = [NSSet setWithArray:x[k] ?: @[]]; y[k] = [NSSet setWithArray:y[k] ?: @[]]; }
            return [x isEqual:y] && [a[@"globalDeniedTweaks"] isEqual:b[@"globalDeniedTweaks"]];
        };
        Expect(sameSB(allow, allowSnapshot) && [record isEqual:record0], @"  ... and back: as before (the same members; the record exactly)");
        ApplyStyle(allow, record, kMSBDCCStyleMac, YES, nil);
        MSBDExChoicyUndo(allow, record);
        Expect([[NSSet setWithArray:allow[@"appSettings"][@"com.apple.springboard"][@"allowedTweaks"]] isEqual:[NSSet setWithArray:allowSnapshot[@"appSettings"][@"com.apple.springboard"][@"allowedTweaks"]]]
               && [allow[@"globalDeniedTweaks"] isEqual:(@[@"Rose", @"Zetsu"])], @"  ... the give-back puts it back in the allow list too (and every entry of ours out of the global one)");
        NSMutableDictionary *deny = Deep(choicy0);   // (a deny list overriding the global one: BigSurCenter listed there too)
        deny[@"appSettings"][@"com.apple.springboard"][@"customTweakConfigurationEnabled"] = @YES; deny[@"appSettings"][@"com.apple.springboard"][@"overwriteGlobalTweakConfiguration"] = @YES;
        NSDictionary *denySnapshot = Deep(deny);
        record = Deep(record0);
        ApplyStyle(deny, record, kMSBDCCStyleStock, YES, nil);
        Expect([deny[@"appSettings"][@"com.apple.springboard"][@"deniedTweaks"] containsObject:@"BigSurCenter"] && [record[@"springboard.deniedTweaks"] isEqual:@{@"BigSurCenter": @"added"}],
               @"SpringBoard's deny list overriding the global one: BigSurCenter listed there too, recorded");
        ApplyStyle(deny, record, kMSBDCCStyleBigSurCenter, YES, nil);
        Expect([deny isEqual:denySnapshot] && [record isEqual:record0], @"  ... and back: exactly as before");
        NSMutableDictionary *odd = Deep(choicy0);
        odd[@"appSettings"][@"com.apple.springboard"][@"customTweakConfigurationEnabled"] = @YES; odd[@"appSettings"][@"com.apple.springboard"][@"allowDenyMode"] = @7;
        NSDictionary *oddApps = Deep(odd[@"appSettings"]);
        NSMutableArray *lines = [NSMutableArray array];
        record = Deep(record0);
        ApplyStyle(odd, record, kMSBDCCStyleStock, YES, lines);
        Expect([odd[@"appSettings"] isEqual:oddApps] && [odd[@"globalDeniedTweaks"] containsObject:@"BigSurCenter"]
               && [lines containsObject:@"Choicy's SpringBoard mode is unknown -- its SpringBoard list left as it is"], @"an unknown SpringBoard mode: its list left as it is (the global one changed), said in the log");

        // ---- not installed any more: our entry taken back; the engines' entries as before ----
        prefs = Deep(choicy0); record = Deep(record0);
        ApplyStyle(prefs, record, kMSBDCCStyleStock, YES, nil);
        lines = [NSMutableArray array];
        Expect(ApplyStyle(prefs, record, kMSBDCCStyleStock, NO, lines) && [prefs isEqual:choicy0] && [record isEqual:record0]
               && [lines containsObject:@"not installed, our entries taken out again: BigSurCenter"], @"BigSurCenter removed: our entry for it taken out again (the record back too)");
        NSMutableDictionary *eng = Deep(choicy0), *erec = Deep(record0);   // (the engines: Zetsu picked, Aerial installed -- as the helper and Settings did it before the table)
        Expect(MSBDExChoicyApply(eng, erec, MSBDExLibs(@"windowEngine", @"zetsu"), @[@"Aerial"], @[@"MilkyWay4", @"MilkyWay3SubModule"], nil)
               && [eng[@"globalDeniedTweaks"] isEqual:(@[@"Rose", @"Aerial"])] && [erec isEqual:(@{@"globalDeniedTweaks": @{@"Aerial": @"added", @"Zetsu": @"removed"}})],
               @"the engines through the same table: Zetsu picked -- out of the list (recorded), Aerial kept out");

        // ---- the user's own switch-off, and the helper's renames ----
        NSDictionary *c = @{@"globalDeniedTweaks": @[@"BigSurCenter"]};
        Expect(MSBDExUserOff(@"BigSurCenter", c, nil, @[], YES, NO), @"denied in Choicy, no record of ours: the user's");
        Expect(!MSBDExUserOff(@"BigSurCenter", c, @{@"globalDeniedTweaks": @{@"BigSurCenter": @"added"}}, @[], YES, NO), @"  ... with our \"added\": ours");
        Expect(MSBDExUserOff(@"BigSurCenter", nil, nil, @[], NO, YES), @"iCleaner Pro's .disabled (no .dylib), not renamed by us: the user's");
        Expect(!MSBDExUserOff(@"BigSurCenter", nil, nil, @[@"BigSurCenter"], NO, YES), @"  ... renamed by us: ours");
        Expect(!MSBDExUserOff(@"BigSurCenter", nil, nil, @[], YES, YES) && !MSBDExUserOff(@"BigSurCenter", @{}, @{}, @[], YES, NO), @"its .dylib there and in no list: not switched off");
        Expect([MSBDExRenamesIn(@"Aerial\nBigSurCenter\n../evil\nChoicySB\nMacOSNotifications\nAerial\n") isEqual:(@[@"Aerial", @"BigSurCenter", @"MacOSNotifications"])]
               && MSBDExRenamesIn(@"").count == 0, @"the rename record: the table's libraries only, once each (BigSurCenter's renames given back like the engines')");
        // the rule with a user's own switch-off: never set, BigSurCenter switched off by the user -- iPadOS (Mac only when picked), and nothing of ours loads it
        style = MSBDCCStyleChosen(kMSBDCCStyleNone, YES, MSBDExUserOff(@"BigSurCenter", c, nil, @[], YES, NO), 1);
        NSMutableDictionary *cu = Deep(c), *cr = [NSMutableDictionary dictionary];
        Expect(style == kMSBDCCStyleStock && !ApplyStyle(cu, cr, style, YES, nil) && [cu isEqual:c] && cr.count == 0, @"never set, the user keeps BigSurCenter out: iPadOS, Choicy left as the user has it");

        // ---- the user's own switch-off in SpringBoard's own list (Choicy's custom configuration for SpringBoard on): BigSurCenter loads only in
        //      SpringBoard, so that is where a user turns it off. Never set is iPadOS then, and the update never switches it back on (1.8.0 review 2) ----
        NSMutableDictionary *sbDeny = Deep(choicy0);   // (deny mode: BigSurCenter in SpringBoard's own deny list, the user's)
        sbDeny[@"appSettings"][@"com.apple.springboard"][@"customTweakConfigurationEnabled"] = @YES;
        [sbDeny[@"appSettings"][@"com.apple.springboard"][@"deniedTweaks"] addObject:@"BigSurCenter"];
        NSDictionary *sbDeny0 = Deep(sbDeny);
        record = Deep(record0);
        userOff = MSBDExUserOff(@"BigSurCenter", sbDeny, record, @[], YES, NO);
        style = MSBDCCStyleChosen(kMSBDCCStyleNone, YES, userOff, 1);
        Expect(userOff && style == kMSBDCCStyleStock, @"SpringBoard's own deny list names BigSurCenter (custom configuration on, no entry of ours): the user's switch-off -- never set is iPadOS");
        ApplyStyle(sbDeny, record, style, YES, nil);
        Expect([sbDeny[@"appSettings"][@"com.apple.springboard"][@"deniedTweaks"] containsObject:@"BigSurCenter"] && !record[@"springboard.deniedTweaks"],
               @"  ... the update's apply leaves it in SpringBoard's deny list: never switched back on against the user");
        Expect(MSBDExUserOff(@"BigSurCenter", sbDeny, record, @[], YES, NO), @"  ... and it is still the user's at the next start (our global entry beside it changes nothing)");
        MSBDExChoicyUndo(sbDeny, record);
        Expect([sbDeny[@"appSettings"] isEqual:sbDeny0[@"appSettings"]] && [sbDeny[@"globalDeniedTweaks"] isEqual:(@[@"Rose", @"Zetsu"])],
               @"  ... a give-back: SpringBoard's list exactly as the user had it, our entries (BigSurCenter's, Aerial's) out of the global one");
        Expect(!MSBDExUserOff(@"BigSurCenter", sbDeny0, @{@"springboard.deniedTweaks": @{@"BigSurCenter": @"added"}}, @[], YES, NO), @"  ... listed there by us (our \"added\": a deny list overriding the global one): ours");
        NSMutableDictionary *sbOff = Deep(sbDeny0);
        sbOff[@"appSettings"][@"com.apple.springboard"][@"customTweakConfigurationEnabled"] = @NO;
        Expect(!MSBDExUserOff(@"BigSurCenter", sbOff, nil, @[], YES, NO), @"  ... SpringBoard's own lists not in force (custom configuration off): not a switch-off");
        NSMutableDictionary *sbAllow = Deep(choicy0);   // (allow mode: BigSurCenter left out of SpringBoard's own allow list by the user)
        sbAllow[@"appSettings"][@"com.apple.springboard"][@"customTweakConfigurationEnabled"] = @YES; sbAllow[@"appSettings"][@"com.apple.springboard"][@"allowDenyMode"] = @1;
        [sbAllow[@"appSettings"][@"com.apple.springboard"][@"allowedTweaks"] removeObject:@"BigSurCenter"];
        NSDictionary *sbAllow0 = Deep(sbAllow);
        record = Deep(record0);
        userOff = MSBDExUserOff(@"BigSurCenter", sbAllow, record, @[], YES, NO);
        style = MSBDCCStyleChosen(kMSBDCCStyleNone, YES, userOff, 1);
        Expect(userOff && style == kMSBDCCStyleStock, @"left out of SpringBoard's own allow list (custom configuration on, no entry of ours): the user's switch-off -- never set is iPadOS");
        ApplyStyle(sbAllow, record, style, YES, nil);
        Expect(![sbAllow[@"appSettings"][@"com.apple.springboard"][@"allowedTweaks"] containsObject:@"BigSurCenter"] && !record[@"springboard.allowedTweaks"],
               @"  ... the update's apply does not put it in the allow list");
        Expect(!MSBDExUserOff(@"BigSurCenter", sbAllow0, @{@"springboard.allowedTweaks": @{@"BigSurCenter": @"removed"}}, @[], YES, NO), @"  ... left out by us (our \"removed\"): ours");
        NSMutableDictionary *sbNoMode = Deep(sbAllow0); [sbNoMode[@"appSettings"][@"com.apple.springboard"] removeObjectForKey:@"allowDenyMode"];
        Expect(MSBDExUserOff(@"BigSurCenter", sbNoMode, nil, @[], YES, NO), @"  ... no mode stored: an allow list, as Choicy reads it (MSBDExChoicyMode)");
        Expect(!MSBDExUserOff(@"BigSurCenter", choicy0, nil, @[], YES, NO), @"the iPad 2's own setup (custom configuration off, BigSurCenter in its allow list): not switched off");
        NSMutableDictionary *sbOdd = Deep(sbDeny0); sbOdd[@"appSettings"][@"com.apple.springboard"][@"allowDenyMode"] = @7;
        Expect(!MSBDExUserOff(@"BigSurCenter", sbOdd, nil, @[], YES, NO), @"an unknown SpringBoard mode: its list says nothing (MSBDExChoicyApply leaves it alone too)");
        NSMutableDictionary *sbJunk = Deep(sbDeny0); sbJunk[@"appSettings"][@"com.apple.springboard"][@"customTweakConfigurationEnabled"] = @[@1];
        Expect(!MSBDExUserOff(@"BigSurCenter", sbJunk, nil, @[], YES, NO) && !MSBDExUserOff(@"BigSurCenter", @{@"appSettings": @[@"x"]}, nil, @[], YES, NO)
               && !MSBDExUserOff(@"BigSurCenter", @{@"appSettings": @{@"com.apple.springboard": @"x"}}, nil, @[], YES, NO), @"  ... a malformed SpringBoard entry: read as nothing, no exception (SpringBoard reads this too)");
        NSMutableDictionary *dDeny = Deep(sbDeny0); [dDeny[@"appSettings"][@"com.apple.springboard"][@"deniedTweaks"] addObject:@"MacOSNotifications"];
        Expect(MSBDExUserOff(@"MacOSNotifications", dDeny, nil, @[], YES, NO), @"Destra in SpringBoard's own deny list: the user's too (the one reader for every library of the table)");

        // ---- Banner Style: an M1-like setup (Destra installed and loading, off in its own settings; Mac-Style Banners on; engines kept out). A user
        //      Destra showed the banners for (on in its own settings) is the same since KT 3 Nov: never set is ours, its switch not asked ----
        NSDictionary *m10 = @{@"globalDeniedTweaks": @[@"Rose", @"MilkyWay4", @"MilkyWay3SubModule", @"Zetsu"], @"preferenceVersion": @1,
                              @"appSettings": @{@"com.apple.springboard": @{@"customTweakConfigurationEnabled": @NO, @"allowDenyMode": @2, @"allowedTweaks": @[@"Rose"], @"deniedTweaks": @[@"MilkyWay4"]}}};
        NSDictionary *m1r0 = @{@"globalDeniedTweaks": @{@"MilkyWay4": @"added", @"MilkyWay3SubModule": @"added"}};
        prefs = Deep(m10); record = Deep(m1r0);
        BOOL destraOff = MSBDExUserOff(@"MacOSNotifications", prefs, record, @[], YES, NO);
        int banners = MSBDBannerStyleChosen(kMSBDBannerNone, kMSBDBannerMac, YES);
        Expect(!destraOff && banners == kMSBDBannerMac, @"the M1, never set (Destra in no list of the user's): Mac, ours for everyone (KT 3 Nov)");
        Expect(ApplyBanners(prefs, record, banners, YES, nil), @"  ... so Destra is kept out from the update's first start (only one banner system loads)");
        Expect([prefs[@"globalDeniedTweaks"] isEqual:(@[@"Rose", @"MilkyWay4", @"MilkyWay3SubModule", @"Zetsu", @"MacOSNotifications"])]
               && [record isEqual:(@{@"globalDeniedTweaks": @{@"MilkyWay4": @"added", @"MilkyWay3SubModule": @"added", @"MacOSNotifications": @"added"}})], @"  ... in the global list, recorded as ours");
        Expect([prefs[@"appSettings"] isEqual:m10[@"appSettings"]] && !ApplyBanners(prefs, record, kMSBDBannerStock, YES, nil), @"  ... SpringBoard's own list (not in force) as it is; iPadOS: nothing more to change");
        Expect(!MSBDExUserOff(@"MacOSNotifications", prefs, record, @[], YES, NO) && MSBDBannerStyleChosen(kMSBDBannerNone, kMSBDBannerMac, YES) == kMSBDBannerMac,
               @"  ... our entry is not the user's switch-off: still Mac at the next start");
        Expect(ApplyBanners(prefs, record, kMSBDBannerDestra, YES, nil) && [prefs isEqual:m10] && [record isEqual:m1r0], @"Destra picked: Choicy and the record exactly as before (as found)");
        Expect(MSBDBannerStyleChosen(kMSBDBannerDestra, kMSBDBannerMac, YES) == kMSBDBannerDestra, @"  ... and it stays the style although off in its own settings (the pick decides)");
        prefs = Deep(m10); record = Deep(m1r0);
        ApplyBanners(prefs, record, kMSBDBannerMac, YES, nil);
        log = MSBDExChoicyUndo(prefs, record);
        Expect([prefs[@"globalDeniedTweaks"] isEqual:(@[@"Rose", @"Zetsu"])] && [log containsObject:@"globalDeniedTweaks: removed MacOSNotifications (we had added it)"],
               @"give-back (switch-off, removal): our Destra entry out with the engines', the user's own entries stay");
        NSMutableDictionary *mine = Deep(m10); [mine[@"globalDeniedTweaks"] addObject:@"MacOSNotifications"];   // (the user's own: no record of ours)
        Expect(MSBDExUserOff(@"MacOSNotifications", mine, m1r0, @[], YES, NO) && MSBDBannerStyleChosen(kMSBDBannerNone, kMSBDBannerMac, YES) == kMSBDBannerMac,
               @"Destra kept out by the user themselves: theirs; never set is Mac anyway (Destra never the default)");
        NSMutableDictionary *mineRec = Deep(m1r0);
        Expect(!ApplyBanners(mine, mineRec, kMSBDBannerMac, YES, nil) && [mineRec isEqual:m1r0], @"  ... nothing recorded for it (it is in the list already)");
        MSBDExChoicyUndo(mine, mineRec);
        Expect([mine[@"globalDeniedTweaks"] containsObject:@"MacOSNotifications"], @"  ... and a give-back leaves it");
        prefs = Deep(m10); record = Deep(m1r0);
        ApplyBanners(prefs, record, kMSBDBannerStock, YES, nil);
        lines = [NSMutableArray array];
        Expect(ApplyBanners(prefs, record, kMSBDBannerStock, NO, lines) && [prefs isEqual:m10] && [record isEqual:m1r0] && [lines containsObject:@"not installed, our entries taken out again: MacOSNotifications"],
               @"Destra removed: our entry for it taken out again");
        Expect(MSBDExUserOff(@"MacOSNotifications", nil, nil, @[], NO, YES) && !MSBDExUserOff(@"MacOSNotifications", nil, nil, @[@"MacOSNotifications"], NO, YES),
               @"iCleaner Pro's .disabled: the user's unless the helper renamed it");
        // what SpringBoard is told changed (the start's respring question): Choicy's lists themselves, not our record -- the user took our Destra entry
        // out in Choicy, the helper puts it back at the next start: the same record, a different list
        prefs = Deep(m10); record = Deep(m1r0);
        ApplyBanners(prefs, record, kMSBDBannerMac, YES, nil);
        [prefs[@"globalDeniedTweaks"] removeObject:@"MacOSNotifications"];   // (the user, in Choicy)
        NSDictionary *recBefore = Deep(record), *listBefore = Deep(prefs);
        Expect(ApplyBanners(prefs, record, kMSBDBannerMac, YES, nil) && [record isEqual:recBefore], @"the user took our Destra entry out, the helper puts it back: Choicy changed, our record the same");
        Expect(![MSBDExChoicyEntriesOf(prefs, @[@"MacOSNotifications"]) isEqualToString:MSBDExChoicyEntriesOf(listBefore, @[@"MacOSNotifications"])],
               @"  ... so what loads changed for Destra, by Choicy's lists (SpringBoard is told: its question comes)");
        Expect([MSBDExChoicyEntriesOf(prefs, MSBDExLibs(@"windowEngine", nil)) isEqualToString:MSBDExChoicyEntriesOf(listBefore, MSBDExLibs(@"windowEngine", nil))]
               && [MSBDExChoicyEntriesOf(prefs, @[@"BigSurCenter"]) isEqualToString:MSBDExChoicyEntriesOf(listBefore, @[@"BigSurCenter"])], @"  ... and not for the engines or BigSurCenter");
        Expect([MSBDExChoicyEntriesOf(@{@"globalDeniedTweaks": @[@"A"], @"appSettings": @{@"com.apple.springboard": @{@"allowedTweaks": @[@"A"], @"deniedTweaks": @[]}}}, @[@"A", @"B"]) isEqualToString:@"A 110,B 000"]
               && [MSBDExChoicyEntriesOf(@{}, @[@"A"]) isEqualToString:@"A 000"], @"  ... a library's places: the global list, SpringBoard's allow and deny lists");
        // the helper's one change: Control Center Style and Banner Style at once (BigSurCenter loading, Destra kept out), recorded each, back together
        NSMutableDictionary *both = Deep(choicy0), *brec = Deep(record0);
        Expect(MSBDExChoicyApply(both, brec, @[@"BigSurCenter"], @[@"MacOSNotifications"], @[], nil) && [both[@"globalDeniedTweaks"] isEqual:(@[@"Rose", @"Zetsu", @"Aerial", @"MacOSNotifications"])]
               && [brec isEqual:(@{@"globalDeniedTweaks": @{@"Aerial": @"added", @"MacOSNotifications": @"added"}})], @"both choices in one change: BigSurCenter loading as it was, Destra kept out (recorded)");
        Expect(MSBDExChoicyApply(both, brec, @[@"BigSurCenter", @"MacOSNotifications"], @[], @[], nil) && [both isEqual:choicy0] && [brec isEqual:record0], @"  ... Destra picked: everything as before");

        // ---- a downgrade to a version before 1.8.0 (the prerm, sshtoggled --giveback-styles: 1.8.0 review 1): our BigSurCenter and Destra entries
        //      given back, the engines' kept in Choicy and in the record for the older version, which manages them as before -- so its own removal
        //      later (its give-back knows the engines only: Undo179) leaves nothing of ours ----
        NSMutableDictionary *dg = Deep(m10), *dgr = Deep(m1r0);   // (the M1-like setup, SpringBoard's own deny list in force and overriding the global one)
        dg[@"appSettings"][@"com.apple.springboard"][@"customTweakConfigurationEnabled"] = @YES; dg[@"appSettings"][@"com.apple.springboard"][@"overwriteGlobalTweakConfiguration"] = @YES;
        NSDictionary *dgUser = Deep(dg);
        ApplyStyle(dg, dgr, kMSBDCCStyleMac, YES, nil); ApplyBanners(dg, dgr, kMSBDBannerMac, YES, nil);   // (1.8.0: Control Center Style Mac, Banner Style Mac)
        Expect([dg[@"globalDeniedTweaks"] containsObject:@"BigSurCenter"] && [dg[@"appSettings"][@"com.apple.springboard"][@"deniedTweaks"] containsObject:@"MacOSNotifications"]
               && [dgr[@"springboard.deniedTweaks"] isEqual:(@{@"BigSurCenter": @"added", @"MacOSNotifications": @"added"})], @"1.8.0 keeps BigSurCenter and Destra out in both lists, recorded");
        NSMutableDictionary *noGiveBack = Deep(dg);
        Undo179(noGiveBack, dgr);
        Expect([noGiveBack[@"globalDeniedTweaks"] containsObject:@"BigSurCenter"] && [noGiveBack[@"globalDeniedTweaks"] containsObject:@"MacOSNotifications"],
               @"  (downgraded with nothing given back, as the prerm was: the older version's removal leaves both denied for good)");
        NSArray *styles = [MSBDExLibs(@"controlCenterStyle", nil) arrayByAddingObjectsFromArray:MSBDExLibs(@"bannerStyle", nil)];
        Expect([styles isEqual:(@[@"BigSurCenter", @"MacOSNotifications"])], @"the downgrade's libraries: Control Center Style's and Banner Style's, from the table");
        log = MSBDExChoicyUndoOnly(dg, dgr, styles);
        Expect([dg isEqual:dgUser], @"downgrade: Choicy exactly as before 1.8.0 changed it (our BigSurCenter and Destra entries out of both lists, the engines' kept)");
        Expect([dgr isEqual:m1r0], @"  ... our record keeps the engines' entries only, as the older version reads and changes it");
        Expect([log containsObject:@"globalDeniedTweaks: removed BigSurCenter (we had added it)"] && [log containsObject:@"springboard.deniedTweaks: removed MacOSNotifications (we had added it)"],
               @"  ... said in the helper's log");
        Undo179(dg, dgr);
        Expect([dg[@"globalDeniedTweaks"] isEqual:(@[@"Rose", @"Zetsu"])] && [dg[@"appSettings"][@"com.apple.springboard"][@"deniedTweaks"] isEqual:(@[@"MilkyWay4"])],
               @"  ... then the older version removed: nothing of ours left in Choicy, the user's own entries stay");
        dg = Deep(dgUser); dgr = Deep(m1r0);
        ApplyBanners(dg, dgr, kMSBDBannerMac, YES, nil);
        [dg[@"globalDeniedTweaks"] removeObject:@"MacOSNotifications"];   // (the user took our entry out of the global list since)
        log = MSBDExChoicyUndoOnly(dg, dgr, styles);
        Expect([log containsObject:@"globalDeniedTweaks: MacOSNotifications already gone -- left as the user has it"] && [dg isEqual:dgUser] && [dgr isEqual:m1r0],
               @"  ... an entry the user changed since: left as the user has it, and no longer in our record");
        NSMutableDictionary *untouched = Deep(m10), *untouchedR = Deep(m1r0);
        Expect(MSBDExChoicyUndoOnly(untouched, untouchedR, styles).count == 0 && [untouched isEqual:m10] && [untouchedR isEqual:m1r0], @"  ... no entry of ours for them: Choicy and the record left as they are");
        // ---- safe mode and an untested iPadOS (sshtoggled ApplyEngines, MacStatusBarAndDock not meant to run: 1.8.0 review 7): every library of the
        //      table given back, as iCleaner Pro's renames are -- the engines' too --, the record kept for the next start, which applies them again ----
        dg = Deep(dgUser); dgr = Deep(m1r0);
        ApplyStyle(dg, dgr, kMSBDCCStyleMac, YES, nil); ApplyBanners(dg, dgr, kMSBDBannerMac, YES, nil);
        MSBDExChoicyUndoOnly(dg, dgr, MSBDExAllLibs());
        Expect([dg[@"globalDeniedTweaks"] isEqual:(@[@"Rose", @"Zetsu"])] && [dg[@"appSettings"] isEqual:dgUser[@"appSettings"]] && dgr.count == 0,
               @"not meant to run: every entry of ours given back (nothing of the table kept from loading), the record empty");
        Expect(ApplyStyle(dg, dgr, kMSBDCCStyleMac, YES, nil) && ApplyBanners(dg, dgr, kMSBDBannerMac, YES, nil) && [dg[@"globalDeniedTweaks"] containsObject:@"BigSurCenter"]
               && [dgr[@"globalDeniedTweaks"] isEqual:(@{@"BigSurCenter": @"added", @"MacOSNotifications": @"added"})], @"  ... meant to run again: the next apply keeps them out again, recorded");
        printf("test-choicetable: %d/%d passed\n", gN - gFail, gN);
    }
    return gFail ? 1 : 0;
}
