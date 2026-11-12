// MSWDisplays.h -- the Mac Switcher's desktops per display (1.8.7 commits 14-16; plans/design-1.8.7-displays.md section 7). Plain Foundation: the
// model MacSwitcher.h works on and its file, run by the Mac test tools/test-mswdisplays.m (the very code).
//  - A model per display: its desktops (ids, in strip order, Desktop 1 first) and the current one. The iPad's is "main"; another display's is
//    keyed by its display key (common/DisplayPrefs.h: "u-<id>", or "any" for a display with no readable id). Every map keyed by desktop id stays
//    ONE flat map for every display (the window records, the pictures, Fit, full screen, sizes): a desktop id is unique across displays, so a
//    record says by its desktop which display it belongs to (MSWDispOwner).
//  - Ids: the iPad's as before (Desktop 1 = 1, a new one the lowest free number from 2, at most 8: 1-9 ever); another display's from
//    max(every id, 1000) + 1 and never again once used (nextDesk): never an iPad id, also not one an older build wrote.
//  - The file (com.besiktasliseba.macstatusbar.desktops.plist), version 2: version 1's keys stay the iPad's ("desktops", "current") and the records
//    flat ("windows", "frames", ...), plus "version" 2, "nextDesk" and "displays" {key: {desktops, current, lastSeen}}. 1.8.6's loader keeps the
//    iPad's desktops and only the records on them, and drops "displays" at its next save: a downgrade loses the other displays' desktops, nothing
//    else. While the Mac Switcher is off the other displays' desktops stay in this file (only the iPad's go to desktops-kept.plist, as before).
//  - At most 8 other displays remembered (as the displays domain's registry, MSBD_DISP_REMEMBER_MAX): a 9th forgets the one used longest ago of
//    those with one empty desktop, and one with desktops of its own only when every one has (MSWDispTrim; the registry keeps the same ones).
#pragma once
#import <Foundation/Foundation.h>
#include "../common/DisplayPrefs.h"   // (MSBDDispKeyValid: a display key as stored)
// (a small library shared with the Mac test: each build uses the part its commit needs -- the rest unused there is no error)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"

static NSString *const kMSWDispMain = @"main";
static const NSInteger kMSWDispBase = 1000;        // (another display's desktop ids are above it)
static const NSUInteger kMSWDispMaxDisplays = 8;   // (other displays remembered)

@interface DMMSWModel : NSObject {
@public
    NSMutableArray<NSNumber *> *desks;   // the desktops' ids, in strip order (Desktop 1 first)
    NSUInteger cur;                      // the current desktop's place
    id homeShot;                         // (Stage Manager: this display's empty desktop as last left, the picture of any empty desktop of it)
    double tickLast;                     // (MacSwitcherSM.h DMMSWSMApply: this display's own pace, twice a second at most,
    NSNumber *tickPending;               //  and its own "a desktop's stage seen twice in a row")
    int tickPendingSeen;
    BOOL broughtBack;                    // (MacSwitcherSM.h DMMSWSMApplyDisplays: its current desktop's windows asked for since it connected or the start)
    double connectedAt;                  // (when it was seen connected, since the start or its last unplug: 0 while not connected)
}
@property (nonatomic, copy) NSString *key;        // "main", or the display's key
@property (nonatomic, assign) double lastSeen;    // (seconds since 1970: when its Mac Switcher was last used)
@end
@implementation DMMSWModel
@end

// A display key a model may have: "any" or "u-<id>" (never "main", which is the iPad's).
static BOOL MSWDispKeyOK(id k) {
    return [k isKindOfClass:[NSString class]] && [k length] && ![k isEqualToString:kMSWDispMain] && MSBDDispKeyValid([k UTF8String]);
}
// The current desktop's id of a model (1 for an empty iPad model, as DMMSWCurId always had it; 0 for an empty other one).
static NSInteger MSWDispCurId(DMMSWModel *m) {
    if (!m || !m->desks.count) return [m.key isEqualToString:kMSWDispMain] || !m ? 1 : 0;
    return m->desks[MIN(m->cur, m->desks.count - 1)].integerValue;
}
// Every desktop id of the iPad's model and the other displays'.
static NSMutableSet<NSNumber *> *MSWDispAllIds(DMMSWModel *main, NSDictionary<NSString *, DMMSWModel *> *displays) {
    NSMutableSet<NSNumber *> *s = [NSMutableSet set];
    if (main->desks) [s addObjectsFromArray:main->desks];
    for (NSString *k in displays) if (displays[k]->desks) [s addObjectsFromArray:displays[k]->desks];
    return s;
}
// The next id of another display's desktop: above every id there is and above 1000, and never one used before (nextDesk only grows).
static NSInteger MSWDispNextId(NSSet<NSNumber *> *ids, NSInteger nextDesk) {
    NSInteger top = kMSWDispBase;
    for (NSNumber *n in ids) top = MAX(top, n.integerValue);
    return MAX(nextDesk, top + 1);
}
// Which model a desktop is of: the iPad's, another display's, or nil (a desktop of none: a stale record).
static DMMSWModel *MSWDispOwner(NSNumber *desk, DMMSWModel *main, NSDictionary<NSString *, DMMSWModel *> *displays) {
    if (![desk isKindOfClass:[NSNumber class]]) return nil;
    if ([main->desks containsObject:desk]) return main;
    for (NSString *k in displays) if ([displays[k]->desks containsObject:desk]) return displays[k];
    return nil;
}
// What a display's tick does with a window record (MacSwitcherSM.h DMMSWSMApply): one of another model's desktop is not its own -- that model's tick
// decides (a window that went to the other display is forgotten there and joins this one from the stage it shows); its own, and on the iPad one
// of no model (a stale record, as 1.8.6 had it), is kept while its window is in a stage of this display, else forgotten (closed, or gone elsewhere).
typedef NS_ENUM(int, MSWDispFate) { MSWDispFateKeep, MSWDispFateForget, MSWDispFateNotMine };
static MSWDispFate MSWDispRecordFate(id desk, DMMSWModel *tick, DMMSWModel *main, NSDictionary<NSString *, DMMSWModel *> *displays, BOOL aliveHere) {
    DMMSWModel *owner = MSWDispOwner(desk, main, displays);
    if (tick == main ? (owner && owner != main) : owner != tick) return MSWDispFateNotMine;
    return aliveHere ? MSWDispFateKeep : MSWDispFateForget;
}
// Which display the Mac Switcher's keys act on (1.8.7 commit 16; design section 7: Control-Up / Left / Right): a session running -- the view open, a
// switch -- is that display's; else the display of the scene with the keyboard focus; else the display the pointer was on last (its last hover
// there is the last hover of all); else the iPad. session / focus: -1 none or not known, 0 the iPad, 1 another display. hoverOther / hoverAny:
// when the pointer was last seen on another display and on any display (0: never). YES: another display.
static BOOL MSWDispKeysOnOther(int session, int focus, double hoverOther, double hoverAny, BOOL otherThere) {
    if (!otherThere) return NO;
    if (session >= 0) return session == 1;
    if (focus >= 0) return focus == 1;
    return hoverOther > 0 && hoverOther >= hoverAny;
}
// Whose desktops Control-Left / Control-Right switch (1.8.7 review): the keys' display's (MSWDispKeysOnOther) with two or more; when that is another
// display with fewer, and no session runs there, the iPad's with two or more (1.8.6 switched the iPad's whichever display the app with the keyboard
// was on); else none: the keys are not offered and stay the app's. keysOnOther: the keys' display is another one; sessionIdle: no session runs;
// otherDesks / mainDesks: their desktops (0: none, no model). -1 none, 0 the iPad's, 1 the other display's.
static int MSWDispArrowsOn(BOOL keysOnOther, BOOL sessionIdle, NSUInteger otherDesks, NSUInteger mainDesks) {
    if (keysOnOther) {
        if (otherDesks >= 2) return 1;
        if (!sessionIdle) return -1;   // (the view or a switch on that display: never the iPad's under it)
    }
    return mainDesks >= 2 ? 0 : -1;
}
// A new model for another display: one desktop, its id the next one (nextDesk moves on).
static DMMSWModel *MSWDispNewModel(NSString *key, NSSet<NSNumber *> *ids, NSInteger *nextDesk, double now) {
    if (!MSWDispKeyOK(key) || !nextDesk) return nil;
    NSInteger nid = MSWDispNextId(ids, *nextDesk);
    *nextDesk = nid + 1;
    DMMSWModel *m = [DMMSWModel new];
    m.key = key; m.lastSeen = now;
    m->desks = [NSMutableArray arrayWithObject:@(nid)]; m->cur = 0;
    return m;
}
// A new desktop of another display's model: the next id (nextDesk moves on), or 0 at the most desktops.
static NSInteger MSWDispNewDesk(DMMSWModel *m, NSSet<NSNumber *> *ids, NSInteger *nextDesk, NSUInteger maxDesks) {
    if (!m || !nextDesk || m->desks.count >= maxDesks) return 0;
    NSInteger nid = MSWDispNextId(ids, *nextDesk);
    *nextDesk = nid + 1;
    [m->desks addObject:@(nid)];
    return nid;
}
// A model's desktops are the user's own (common/DisplayPrefs.h MSBDDispMSWBusy): two or more, or a window record (`windows`: window -> desktop id,
// gMSWWinDesk or the file's "windows") on one of them.
static BOOL MSWDispBusy(DMMSWModel *m, NSDictionary *windows) {
    if (!m) return NO;
    int records = 0;
    for (id w in windows) if ([windows[w] isKindOfClass:[NSNumber class]] && [m->desks containsObject:windows[w]]) records++;
    return MSBDDispMSWBusy((int)m->desks.count, records);
}
// More than kMSWDispMaxDisplays other displays: one goes (never `keep`, the one in use) -- the one used longest ago of those with one empty desktop;
// one with desktops of its own (MSWDispBusy) only when every one has (review of 1.8.7: by lastSeen alone, a display set up with several desktops
// went before the plain copies the Lightning AV adapter's new id on each connect leaves). Their keys, in the order they went.
static NSArray<NSString *> *MSWDispTrim(NSMutableDictionary<NSString *, DMMSWModel *> *displays, NSString *keep, NSUInteger max, NSDictionary *windows) {
    NSMutableArray<NSString *> *gone = [NSMutableArray array];
    while (displays.count > max) {
        NSString *pick = nil;
        NSArray<NSString *> *keys = [displays.allKeys sortedArrayUsingSelector:@selector(compare:)];
        for (int pass = 0; pass < 2 && !pick; pass++)
            for (NSString *k in keys) {
                if ([k isEqualToString:keep]) continue;
                if (pass == 0 && MSWDispBusy(displays[k], windows)) continue;   // (the plain ones first)
                if (!pick || displays[k].lastSeen < displays[pick].lastSeen) pick = k;
            }
        if (!pick) break;
        [displays removeObjectForKey:pick];
        [gone addObject:pick];
    }
    return gone;
}
// A display forgotten (Settings > Desktop > Displays > Forget This Display, or the 9th): its model goes with every record and per-desktop entry of
// its desktops (windows / frames by window key; fullscreen / leftSizes / fit by desktop id as a string). The ids it had, or nil when it had none.
static NSArray<NSNumber *> *MSWDispForget(NSMutableDictionary<NSString *, DMMSWModel *> *displays, NSString *key, NSMutableDictionary *windows,
                                          NSMutableDictionary *frames, NSArray<NSMutableDictionary *> *byDesk) {
    DMMSWModel *m = key ? displays[key] : nil;
    if (!m) return nil;
    NSArray<NSNumber *> *ids = [m->desks copy] ?: @[];
    [displays removeObjectForKey:key];
    for (NSString *w in [windows.allKeys copy]) if ([ids containsObject:windows[w]]) { [windows removeObjectForKey:w]; [frames removeObjectForKey:w]; }
    for (NSMutableDictionary *d in byDesk) for (NSNumber *n in ids) [d removeObjectForKey:n.stringValue];
    return ids;
}

// ---- the file ---------------------------------------------------------------------------------------------------------------------------------
// Reads a desktops file (version 1 or 2): the iPad's desktops and current one into main (exactly as 1.8.6 read them: Desktop 1 first, other ids
// above 1, no repeat, at most maxDesks), the other displays' into displays (a valid key; ids above 1000 that no other model has; at least one; at
// most maxDesks each; at most kMSWDispMaxDisplays, the ones used last), and nextDesk (never below what the ids need).
static void MSWDispRead(NSDictionary *st, NSUInteger maxDesks, DMMSWModel *main, NSMutableDictionary<NSString *, DMMSWModel *> *displays, NSInteger *nextDesk) {
    main.key = kMSWDispMain;
    main->desks = [NSMutableArray arrayWithObject:@1]; main->cur = 0;
    [displays removeAllObjects];
    NSInteger next = kMSWDispBase + 1;
    if ([st isKindOfClass:[NSDictionary class]]) {
        NSArray *ids = st[@"desktops"];
        if ([ids isKindOfClass:[NSArray class]]) for (id n in ids) if ([n isKindOfClass:[NSNumber class]] && [n integerValue] > 1 && ![main->desks containsObject:n] && main->desks.count < maxDesks) [main->desks addObject:@([n integerValue])];
        NSNumber *cur = st[@"current"];
        NSUInteger i = [cur isKindOfClass:[NSNumber class]] ? [main->desks indexOfObject:@(cur.integerValue)] : NSNotFound;
        main->cur = i == NSNotFound ? 0 : i;
        NSDictionary *ds = [st[@"displays"] isKindOfClass:[NSDictionary class]] ? st[@"displays"] : nil;
        NSMutableSet<NSNumber *> *used = [NSMutableSet setWithArray:main->desks];
        for (NSString *k in [ds.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            NSDictionary *d = MSWDispKeyOK(k) && [ds[k] isKindOfClass:[NSDictionary class]] ? ds[k] : nil;
            NSArray *dids = [d[@"desktops"] isKindOfClass:[NSArray class]] ? d[@"desktops"] : nil;
            if (!dids) continue;
            DMMSWModel *m = [DMMSWModel new];
            m.key = k; m->desks = [NSMutableArray array];
            for (id n in dids) if ([n isKindOfClass:[NSNumber class]] && [n integerValue] > kMSWDispBase && ![used containsObject:@([n integerValue])] && m->desks.count < maxDesks) { [m->desks addObject:@([n integerValue])]; [used addObject:@([n integerValue])]; }
            if (!m->desks.count) continue;
            NSNumber *c = [d[@"current"] isKindOfClass:[NSNumber class]] ? d[@"current"] : nil;
            NSUInteger ci = c ? [m->desks indexOfObject:@(c.integerValue)] : NSNotFound;
            m->cur = ci == NSNotFound ? 0 : ci;
            m.lastSeen = [d[@"lastSeen"] isKindOfClass:[NSNumber class]] ? [d[@"lastSeen"] doubleValue] : 0;
            displays[k] = m;
        }
        MSWDispTrim(displays, nil, kMSWDispMaxDisplays, [st[@"windows"] isKindOfClass:[NSDictionary class]] ? st[@"windows"] : nil);
        if ([st[@"nextDesk"] isKindOfClass:[NSNumber class]]) next = MAX(next, [st[@"nextDesk"] integerValue]);
    }
    if (nextDesk) *nextDesk = MSWDispNextId(MSWDispAllIds(main, displays), next);
}
// A record's desktop is one of a model (else the record is dropped at load, as 1.8.6 dropped one of a desktop not in "desktops").
static BOOL MSWDispDeskKnown(id desk, DMMSWModel *main, NSDictionary<NSString *, DMMSWModel *> *displays) { return MSWDispOwner(desk, main, displays) != nil; }
// Version 2's own keys into a file being written (its version 1 keys -- the iPad's desktops and the flat records -- are the caller's, as before).
static void MSWDispWrite(NSMutableDictionary *st, NSDictionary<NSString *, DMMSWModel *> *displays, NSInteger nextDesk) {
    NSMutableDictionary *ds = [NSMutableDictionary dictionary];
    for (NSString *k in displays) {
        DMMSWModel *m = displays[k];
        if (!MSWDispKeyOK(k) || !m->desks.count) continue;
        ds[k] = @{@"desktops": [m->desks copy], @"current": @(MSWDispCurId(m)), @"lastSeen": @(m.lastSeen)};
    }
    st[@"version"] = @2;
    st[@"nextDesk"] = @(nextDesk);
    st[@"displays"] = ds;
}
#pragma clang diagnostic pop
