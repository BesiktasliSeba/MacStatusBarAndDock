#!/bin/bash
# Mac test of Live Activities in the menu bar (1.8.4 item 1): the plain C (common/LiveActivities.h, test-liveactivities.c), and the wiring in
# SpringBoard (statusbar/LiveActivities.h, LiveActivityApps.h, StatusBar.x), Settings (the switch and its Activities page, found by the Settings
# search) and the crash guard's map. The private calls: every one in a table of the types it was read with, and the 17/18 path off on every
# version until a device run of la_probe has confirmed its selectors.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -O2 -Wall -o "$W/tla" test-liveactivities.c && "$W/tla" || fails=1

L=../statusbar/LiveActivities.h; A=../statusbar/LiveActivityApps.h; X=../statusbar/StatusBar.x; P=../statusbar/macstatusbarprefs/Resources/Root.plist
LP=../statusbar/macstatusbarprefs/Resources/LiveActivities.plist; C=../statusbar/macstatusbarprefs/MSBRootListController.m
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }   # one function of a file, from its first line

# ---- Settings: the switch, its page, the search
check "Settings > Status Bar: Live Activities in Menu Bar (liveActivities, on by default, hidden with the stock status bar), then the Activities link" \
  "python3 -I -c \"import plistlib,sys; it=plistlib.load(open('$P','rb'))['items']; ids=[x.get('id') for x in it]; i=ids.index('LIVE_ACTIVITIES'); s=it[i]; g=it[i-1]; l=it[i+1]
sys.exit(0 if s['key']=='liveActivities' and s['default'] is True and s['cell']=='PSSwitchCell' and s['label']=='Live Activities in Menu Bar' and s['defaults']=='com.besiktasliseba.macstatusbar' and s['PostNotification']=='com.besiktasliseba.macstatusbar/prefsChanged' and g['cell']=='PSGroupCell' and g.get('stockHides') is True and l['cell']=='PSLinkCell' and l['detail']=='MSBLiveActivitiesListController' and l['label']=='Activities' and ids.index('BATTERY_MENU') < i < ids.index('LOCK_GROUP') else 1)\""
check "  ... its page: Now Playing, Timers, Calls, Apps (KT's list), each on by default, each telling SpringBoard" \
  "python3 -I -c \"import plistlib,sys; d=plistlib.load(open('$LP','rb')); it=[x for x in d['items'] if x['cell']=='PSSwitchCell']
want=[('Now Playing','liveActivitiesNowPlaying'),('Timers','liveActivitiesTimers'),('Calls','liveActivitiesCalls'),('Apps','liveActivitiesApps')]
sys.exit(0 if [(x['label'],x['key']) for x in it]==want and all(x['default'] is True and x['defaults']=='com.besiktasliseba.macstatusbar' and x['PostNotification']=='com.besiktasliseba.macstatusbar/prefsChanged' for x in it) and d['title']=='Activities' else 1)\""
check "  ... the page is the Status Bar page's controller with LiveActivities.plist, not the root page" \
  "grep -q '^@interface MSBLiveActivitiesListController : MSBRootListController$' $C && grep -q \"^- (NSString \\*)msb_plistName { return @\\\"LiveActivities\\\"; }$\" $C \
   && grep -q 'return !\\[self msb_windowsPage\\] && !\\[self msb_desktopPage\\] && !\\[self msb_liveActivitiesPage\\];' $C"
mkdir -p "$W/lib/PreferenceBundles/MacStatusBarPrefs.bundle" "$W/lib/PreferenceLoader/Preferences"; cp "$P" "$LP" "$W/lib/PreferenceBundles/MacStatusBarPrefs.bundle/"
cat > "$W/tidx.m" <<'OBJC'
#import <Foundation/Foundation.h>
#import "TweakIndex.h"
int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *root = @(argv[1]);
        MTIConfig *c = [MTIConfig new];
        c.plDirs = @[[root stringByAppendingPathComponent:@"PreferenceLoader/Preferences"]]; c.bundleDirs = @[[root stringByAppendingPathComponent:@"PreferenceBundles"]];
        c.supportDir = root; c.languages = @[@"en-US"]; c.cfVersion = 1953.1; c.maxPerPane = 400; c.maxTotal = 6000;
        c.own = @[@{@"id": @"MAC_STATUS_BAR", @"title": @"Status Bar", @"bundle": [root stringByAppendingPathComponent:@"PreferenceBundles/MacStatusBarPrefs.bundle"]}];
        c.skipBundles = @[@"MacStatusBarPrefs"];
        NSArray<MTIEntry *> *index = MTIBuild(c);
        MTIEntry *e = MTIMatch(index, @"live activities in menu bar", 10).firstObject;
        BOOL ok1 = e && [e.title isEqualToString:@"Live Activities in Menu Bar"] && [e.crumb isEqualToString:@"Status Bar"] && [MTIPrefsURL(e.uid) isEqualToString:@"prefs:root=MAC_STATUS_BAR#LIVE_ACTIVITIES"];
        printf("%s  the Settings search: \"live activities in menu bar\" finds %s (%s, %s)\n", ok1 ? "PASS" : "FAIL", e ? e.title.UTF8String : "nothing", e ? e.crumb.UTF8String : "-", e ? MTIPrefsURL(e.uid).UTF8String : "-");
        MTIEntry *t = nil;
        for (MTIEntry *x in MTIMatch(index, @"timers", 20)) if ([x.title isEqualToString:@"Timers"]) { t = x; break; }
        BOOL ok2 = t && [t.crumb containsString:@"Activities"];
        printf("%s    ... \"timers\" finds the Activities page's Timers (%s)\n", ok2 ? "PASS" : "FAIL", t ? t.crumb.UTF8String : "nothing");
        return ok1 && ok2 ? 0 : 1;
    }
}
OBJC
clang -fobjc-arc -Wall -Wno-unused-function -I../common -framework Foundation -o "$W/tidx" "$W/tidx.m" && "$W/tidx" "$W/lib" || fails=1
check "SpringBoard reads the switch and the four kinds as stored (a boolean, else on) and applies them once it is up 8 s" \
  "grep -q 'static const char \\*const laKeys\\[5\\] = { MSBD_LA_KEY, MSBD_LA_NP_KEY, MSBD_LA_TIMERS_KEY, MSBD_LA_CALLS_KEY, MSBD_LA_APPS_KEY };' $X \
   && grep -q 'la\\[i\\] = MSBDLASwitchOn(isBool, isBool && CFBooleanGetValue(laRef));' $X && grep -q 'DMLAApplyPrefs(la\\[0\\] && !DMCtorSkip(\"liveact\"), la\\[1\\], la\\[2\\], la\\[3\\], la\\[4\\]);' $X \
   && fn $L 'static void DMLAApplyPrefs(' | grep -q 'if (age < 8.0) {'"

# ---- the bar
check "the pills are laid out left of the status icons and ours (after the SSH icon), and the keyboard button's place goes by them" \
  "awk '/left = DMLALayoutPills\\(fg, left, timeCentre.y, k\\);/{a=NR} /gStatusIconsLeft = rtl \\? 0.0 : left;   \\/\\/ \\(the keyboard button/{b=NR} /\\[fg bringSubviewToFront:sshIcon\\]; \\[fg bringSubviewToFront:sshButton\\];/{c=NR} END{exit !(a && b == a + 1 && c && c < a)}' $X"
check "  ... in KT's order with the \"+N\" pill for the rest (MSBDLAFit), never past 12 pt beyond the bar's middle (the menus keep the left half)" \
  "fn $L 'static CGFloat DMLALayoutPills(' | grep -q 'MSBDLAFit(widths, n, MSBDLARoom(end, fg.bounds.size.width, round(12.0 \\* k)), gap, plusW, &plus);' \
   && fn $L 'static NSArray<DMLAItem \\*> \\*DMLAShownItems(' | grep -q 'return (NSComparisonResult)DMLAOrder(a, b);' && grep -q 'CGFloat titleMaxRight = locked ? 0.0 : fg.bounds.size.width / 2.0 - 24.0;' $X"
check "  ... gone on the Lock Screen's layout and from a copy that collapsed" \
  "fn $X 'static BOOL DMLayoutWithoutClock(' | grep -q '^    DMLAHidePills(fg);' && grep -q '        DMLAHidePills(fg);   // (the Live Activities. pills too)' $X"
check "  ... the bar's touch rules know them: not the status bar's own action, a menu switch, the first-touch fix, Control Center's pull region" \
  "fn $X 'static BOOL DMPointOverOurControl(' | grep -q 'if (DMLAPillAt(fg, p)) return YES;' && fn $X 'static UIView \\*DMBarControlAtScreenPoint(' | grep -q 'UIView \\*pill = DMLAPillAt(fg, q);' \
   && grep -c 'else if (\\[b isKindOfClass:\\[DMLAPill class\\]\\]) DMLAOpenCard((DMLAPill \\*)b);' $X | grep -q '^2$' && fn $X 'static BOOL DMOurStatusIconsEdge(' | grep -q 'if (DMLAPillsEdge(fg, w, r, &pills))'"
check "a card closes with every menu (its refresh stops, its pill no longer lit), and opens as the menus do (not on the Lock Screen or in Guided Access)" \
  "fn $X 'static void DMCloseOverlay(' | grep -q 'DMLAMenuGone(@\"closed\");' && fn $X 'static void DMRemoveOverlayNow(' | grep -q 'DMLAMenuGone(@\"removed\");' \
   && fn $L 'static void DMLAOpenCard(' | grep -q 'if (DMLockUp(lm) || DMCoverSheetShown())' && fn $L 'static void DMLAOpenCard(' | grep -q 'if (DMGARefuses(@\"Live Activity\")) return;' \
   && fn $L 'static void DMLAOpenCard(' | grep -q 'DMAttachMenuHover(o, fg, host, pill);'"
check "a card's sizes follow Menu Bar Size as our menus' do (its width MSBDMenuTextScaled, every section's size x that scale)" \
  "grep -q 'static CGFloat DMLACardWidth(void) { return MSBDMenuTextScaled(gDMBarSize, 300.0); }' $L && fn $L 'static UIView *DMLAMakeCard(' | grep -q 'gLAZ = W / 300.0;' \
   && grep -q 'static inline CGFloat LZ(CGFloat v) { return round(v \* gLAZ \* 2.0) / 2.0; }' $L && fn $L 'static DMLASection *DMLANowSectionFor(' | grep -q 'CGFloat pad = LZ(14.0), art = LZ(52.0), y = pad;'"
check "the clocks tick only while a running timer or a connected call shows, and wait with the screen off (DMGateTimer); so does an open card's refresh" \
  "fn $L 'static BOOL DMLANeedsClock(' | grep -q 'it.kind == kMSBDLATimer && it.timerState == kMSBDLATimerRunning' && fn $L 'static void DMLAClockApply(' | grep -q 'DMGateTimer(gLAClock);' \
   && fn $L 'static void DMLAOpenCard(' | grep -q 'DMGateTimer(gLACardTimer);'"
check "Now Playing's bars move only while it plays and Reduce Motion is off, at most 20 frames a second" \
  "fn $L '- (void)dm_layoutWithScale:' | grep -q 'BOOL anim = self.moving && !MSBReduceMotion();' && fn $L '- (void)dm_layoutWithScale:' | grep -q 'CAFrameRateRangeMake(10, 20, 20)'"
check "an activity ended from its own card goes at once; any other end stays greyed (MSBD_LA_ENDED_KEEP), then goes" \
  "fn $L 'static void DMLAEnd(' | grep -q 'if (\\[gLAGoneAtOnce containsObject:it.uid\\]) {' && fn $L 'static void DMLAEnd(' | grep -q 'dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((gLAKeep + 0.2) \\* NSEC_PER_SEC))' \
   && grep -q 'static double gLAKeep = MSBD_LA_ENDED_KEEP;' $L"

# ---- the private calls: each one in a table of the types it was read with; nothing on 15/16 or before SpringBoard is 8 s old
sels=$(cat $L $A | grep -o 'sel_registerName("[^"]*")' | sed 's/sel_registerName("\(.*\)")/\1/' | sort -u)
missing=""
for s in $sels; do [ "$s" = alloc ] && continue; grep -q "\"$s\", \"" $L $A || missing="$missing $s"; done
check "every private selector called (sel_registerName) is a row of a type table (kDMLATimerNeeds, kDMLACallNeeds, kDMLAAppListNeeds, kDMLAAppHostNeeds)${missing:+: missing$missing}" "[ -z \"$missing\" ]"
check "  ... and the tables are checked before any call: timers, calls (DMLATypesOK), the apps' listing and live view (their own checks)" \
  "fn $L 'static void DMLATimersStart(' | grep -q 'gLATimersOK = DMLATypesOK(kDMLATimerNeeds' && fn $L 'static void DMLACallsStart(' | grep -q 'gLACallsOK = DMLATypesOK(kDMLACallNeeds' \
   && fn $A 'static BOOL DMLAAppsCheck(' | grep -q 'DMLATypesOK(kDMLAAppListNeeds' && fn $A 'static BOOL DMLAAppsHostOK(' | grep -q 'DMLATypesOK(kDMLAAppHostNeeds'"
check "other apps' Live Activities stay off on every iPadOS until la_probe has confirmed it: no version listed yet; never on 15/16" \
  "grep -q '^static const MSBDLAVersion kMSBDLAAppsListChecked\\[\\] = { { 0, 0, 0 } };' ../common/LiveActivities.h && grep -q '^static const MSBDLAVersion kMSBDLAAppsHostChecked\\[\\] = { { 0, 0, 0 } };' ../common/LiveActivities.h \
   && grep -q 'return major >= 17 && MSBDLAVersionListed(kMSBDLAAppsListChecked' ../common/LiveActivities.h && grep -q 'return major >= 17 && MSBDLAVersionListed(kMSBDLAAppsHostChecked' ../common/LiveActivities.h \
   && fn $A 'static BOOL DMLAAppsCheck(' | grep -q 'BOOL listed = DMLAAppsListedHere(NO);' && fn $A 'static BOOL DMLAAppsHostOK(' | grep -q 'BOOL listed = DMLAAppsListedHere(YES);' \
   && fn $A 'static BOOL DMLAAppsCheck(' | grep -q 'DMLAAppsObserverCovers(objc_getProtocol(\"SBActivityObserver\"), missing)'"
check "  ... the forced tries are a debug build's only (la_apps_try, la_host_try, /tmp/msb-la-noskip), as the read-only probe (la_probe, la_probe_items)" \
  "awk '/^#if DEBUG/{d=1} /^#endif/{d=0} /gLAAppsForced = YES/{if(!d) bad=1; seen=1} END{exit !(seen && !bad)}' $A && awk '/^#if DEBUG/{d=1} /^#endif/{d=0} /gLAHostForced = YES/{if(!d) bad=1; seen=1} END{exit !(seen && !bad)}' $A \
   && awk '/^#if DEBUG/{d=1} /^#endif/{d=0} /msb-la-noskip/{if(!d) bad=1; seen=1} END{exit !(seen && !bad)}' $A && awk '/^#if DEBUG/{d=1} /^#endif/{d=0} /\"la_probe\"/{if(!d) bad=1; seen=1} END{exit !(seen && !bad)}' $A"
check "Apple's own Now Playing and timer activities are left out of the apps' pills (ours show them) -- the Clock's is com.apple.ClockAngel's on 17.5.1 (device pass)" \
  "fn $A 'static BOOL DMLAAppsSkipped(' | grep -q 'com.apple.MediaRemoteUI' && fn $A 'static BOOL DMLAAppsSkipped(' | grep -q 'com.apple.mobiletimer' && fn $A 'static BOOL DMLAAppsSkipped(' | grep -q 'com.apple.ClockAngel'"
check "a timer's card acts on that very timer where MobileTimer offers it (17+: -timerByUpdatingWithState: then -updateTimer:, its states by their names), else on the current timer only (device pass: the Clock's timers are not the current timer on 17.5.1)" \
  "fn $L 'static void DMLATimerAct(' | grep -q 'if (DMLATimerActsOn(it)) {' && fn $L 'static void DMLATimerAct(' | grep -q 'sel_registerName(\"timerByUpdatingWithState:\"), (unsigned long long)st);' \
   && fn $L 'static void DMLATimerAct(' | grep -q 'sel_registerName(\"updateTimer:\"), next);' && fn $L 'static void DMLATimerStatesRead(' | grep -q 'isEqualToString:@\"Paused\"' \
   && fn $L 'static void DMLATimerStatesRead(' | grep -q 'isEqualToString:@\"Running\"' && fn $L 'static void DMLATimerStatesRead(' | grep -q 'isEqualToString:@\"Stopped\"' \
   && fn $L 'static DMLASection \\*DMLATimerSectionFor(' | grep -q 'BOOL buttons = !ended && DMLATimerHasButtons(it);' && grep -q '        it.timerObj = t;' $L \
   && grep -q '{ \"MTTimer\", \"timerByUpdatingWithState:\", \"@24@0:8Q16\", NO, YES },' $L && grep -q '{ \"MTTimerManager\", \"updateTimer:\", \"@24@0:8@16\", NO, YES },' $L"
check "  ... and the Status Bar page's words under the switch name only what this iPadOS shows (no timers or other apps' activities where they are not listed)" \
  "grep -q '\\[sp setProperty:@(MSBDLAGroupFooter(MSBDLATimersRowShown(), MSBDLAAppsRowShown())) forKey:@\"footerText\"\\];' $C"
check "the timer manager is ours, made once and kept (never freed); SpringBoard's activity manager is only observed, never made by us before it is up" \
  "grep -q 'static id gLATimerMgr = nil;   // (ours, kept for SpringBoard.s life)' $L && fn $L 'static void DMLAApplyPrefs(' | grep -q 'DMLAAppsApply(on && apps);'"

# ---- review 1.8.4 M1: nothing new is started in SpringBoard where it is unproven (an empty version list keeps it off, on by default too)
check "M1: the timers source runs only on an iPadOS version in kMSBDLATimersChecked (the versions a real Clock timer has run on: 17.5.1, 18.5), before anything of MobileTimer is asked" \
  "grep -q '^static const MSBDLAVersion kMSBDLATimersChecked\\[\\] = { { 17, 5, 1 }, { 18, 5, 0 } };' ../common/LiveActivities.h && fn $L 'static void DMLATimersStart(' | grep -q 'if (!DMLATimersAllowed())' \
   && fn $L 'static BOOL DMLATimersAllowed(' | grep -q 'return MSBDLATimersListed(v.majorVersion, v.minorVersion, v.patchVersion) != 0;' \
   && awk '/^static void DMLATimersStart\\(/,/^}/' $L | awk '/DMLATimersAllowed/{a=NR} /dlopen|DMLATypesOK|alloc\\]/{if(!b)b=NR} END{exit !(a && b && a < b)}'"
check "  ... MobileTimer's -init must be its own (not NSObject's, whose encoding is the same): the row is marked own and checked against the class's own list" \
  "grep -q '{ \"MTTimerManager\", \"init\", \"@16@0:8\", NO, NO, YES },' $L && fn $L 'static BOOL DMLAOwnMethod(' | grep -q 'class_copyMethodList(c, &n)' \
   && fn $L 'static BOOL DMLATypesOK(' | grep -q 'rows\\[i\\].own && !DMLAOwnMethod('"
check "  ... the scrubber's seek (MRMediaRemoteSetElapsedTime, a call 1.8.3 never made) only where kMSBDLASeekChecked lists the version (17.5.1, 18.5); else the scrubber only shows" \
  "grep -q '^static const MSBDLAVersion kMSBDLASeekChecked\\[\\] = { { 17, 5, 1 }, { 18, 5, 0 } };' ../common/LiveActivities.h && fn $L 'static void DMLANowPlayingSeek(' | grep -q 'if (!DMLASeekAllowed()) return;' \
   && fn $L 'static BOOL DMLASeekAllowed(' | grep -q 'return MSBDLASeekListed(v.majorVersion, v.minorVersion, v.patchVersion) != 0;' \
   && fn $L 'static DMLASection \\*DMLANowSectionFor(' | grep -q 's.scrub.userInteractionEnabled = DMLASeekAllowed();'"
check "  ... calls: TUCallCenter is never made by us -- read only after it has posted a call notification of its own" \
  "fn $L 'static void DMLACallsRead(' | grep -q 'if (!gLACallsHeard) return;' && grep -q 'gLACallsHeard = YES;' $L && ! fn $L 'static void DMLACallsStart(' | grep -q 'DMLACallsRead();'"
check "  ... the forced tries for the device pass (la_timers_try, la_seek_try) are a debug build's only" \
  "awk '/^#if DEBUG/{d=1} /^#endif/{d=0} /gLATimersForced = YES/{if(!d) bad=1; seen=1} END{exit !(seen && !bad)}' $L && awk '/^#if DEBUG/{d=1} /^#endif/{d=0} /gLASeekForced = YES/{if(!d) bad=1; seen=1} END{exit !(seen && !bad)}' $L"

check "P2-L3: the Activities page has its Timers row only where this iPadOS is in the timers list (as SpringBoard runs them): no switch that does nothing" \
  "grep -q '^		if (\\[self msb_liveActivitiesPage\\] && (!MSBDLATimersRowShown() || !MSBDLAAppsRowShown())) {' $C && grep -q 'if ((!timers && \\[key isEqual:kMSBDLATimersRowKey\\]) || (!apps && \\[key isEqual:kMSBDLAAppsRowKey\\])) \\[kept removeObject:sp\\];' $C \
   && awk '/^static inline BOOL MSBDLATimersRowShown\\(void\\) \\{/,/^}/' ../common/OwnPageState.h | grep -q 'return MSBDLATimersListed(v.majorVersion, v.minorVersion, v.patchVersion) != 0;' \
   && grep -q '#define kMSBDLATimersRowKey @MSBD_LA_TIMERS_KEY' ../common/OwnPageRows.h"
check "  ... and the Settings search leaves it out the same way (OwnPageRows.h's rule, with the state the page reads)" \
  "grep -q 'if (bar && !s.laTimersListed && \\[key isEqualToString:kMSBDLATimersRowKey\\]) return YES;' ../common/OwnPageRows.h && grep -q '    s.laTimersListed = MSBDLATimersRowShown();' ../common/OwnPageState.h"
check "  ... and its Apps row (with the group's footer about apps) only where other apps' activities are listed -- never on 15/16 --, the search the same" \
  "awk '/^static inline BOOL MSBDLAAppsRowShown\\(void\\) \\{/,/^}/' ../common/OwnPageState.h | grep -q 'return MSBDLAAppsListed(v.majorVersion, v.minorVersion, v.patchVersion) != 0;' \
   && grep -q 'if (!apps && \\[sp.identifier isEqualToString:@\"LIVE_ACTIVITIES_KINDS\"\\]) \\[sp removePropertyForKey:@\"footerText\"\\];' $C \
   && grep -q 'if (bar && !s.laAppsListed && \\[key isEqualToString:kMSBDLAAppsRowKey\\]) return YES;' ../common/OwnPageRows.h && grep -q '    s.laAppsListed = MSBDLAAppsRowShown();' ../common/OwnPageState.h"


# ---- review 1.8.4 M2: one hosted live view per app card, reused, parented, torn down
check "M2: an open card is compared by its items' signature before anything is built; only a change builds it again" \
  "fn $L 'static void DMLARebuildOpenCard(' | awk '/DMLACardSignatureOf\\(/{if(!a)a=NR} /DMLAMakeCard\\(/{if(!b)b=NR} END{exit !(a && b && a < b)}'"
check "  ... the app's live view: one per activity while its card is open, reused by every rebuild (a record per uid), sized by its own preferred size" \
  "fn $A 'static UIView *DMLAAppsHostedView(' | grep -q 'DMLAHostRecord \\*r = gLAHosts\\[uid\\];' && fn $A 'static UIView *DMLAAppsHostedView(' | grep -q 'DMLAAppsHostHeight(r.host)' && fn $A 'static CGFloat DMLAAppsHostHeight(' | grep -q 'host.preferredContentSize'"
check "  ... a child view controller of its own controller (containment, appearance calls), torn down when its card no longer has it or closes" \
  "grep -q '\\[r.parent addChildViewController:host\\];' $A && grep -q '\\[host didMoveToParentViewController:r.parent\\];' $A && grep -q '\\[r.host removeFromParentViewController\\];' $A \
   && fn $L 'static void DMLARebuildOpenCard(' | grep -q 'DMLAAppsHostsKeep(' && fn $A 'static void DMLAAppsCardGone(' | grep -q 'DMLAAppsHostTearDown('"

check "P2-L2: an app's activity that ends (or is dismissed) while its card is open loses its live view at once; a rebuild keeps only the live views its sections hold" \
  "fn $L 'static void DMLAEnd(' | grep -q 'if (it.kind == kMSBDLAApp) DMLAAppsHostTearDown(it.uid);' && fn $A 'static void DMLAAppsUse(' | grep -q 'if (what == 2) { DMLAAppsHostTearDown(uid);' \
   && fn $L 'static void DMLARebuildOpenCard(' | grep -q 'DMLAAppsHostsKeep(hosting ?: \\[NSSet set\\]);' && ! fn $L 'static void DMLARebuildOpenCard(' | grep -q 'setWithArray:uids' \
   && fn $L 'static UIView \\*DMLAMakeCard(' | grep -q 'if (\\[s isKindOfClass:\\[DMLAAppSection class\\]\\] && ((DMLAAppSection \\*)s).hostsLive) \\[live addObject:uid\\];' \
   && fn $L 'static DMLASection \\*DMLAAppSectionFor(' | grep -q 's.hostsLive = YES; }'"

# ---- review 1.8.4 L5-L10
check "L5: a running timer past its end no longer keeps the 1 s clock; its end is looked at once, a second after it is due, also with no notification" \
  "fn $L 'static BOOL DMLANeedsClock(' | grep -q 'it.timerState == kMSBDLATimerRunning && it.fireAt > now' && fn $L 'static void DMLATimersApply(' | grep -q 'DMLATimerEndLook();' \
   && fn $L 'static void DMLATimerEndLook(' | grep -q '(soonest - now + 1.0) \\* NSEC_PER_SEC'"

check "L6: a drag's end seeks with the scrubber's own position (its sender), never 0 from a section rebuilt away; a rebuild waits while it drags" \
  "grep -q 'DMLAScrubber \\*sc = \\[a.sender isKindOfClass:\\[DMLAScrubber class\\]\\] ? (DMLAScrubber \\*)a.sender : nil;' $L && grep -q 'if (sc && sec && sec.window)' $L \
   && fn $L 'static void DMLARebuildOpenCard(' | grep -q 'if (DMLACardDragging(old)) { gLACardRebuildPending = YES; return; }'"

check "L7: mute and end only on a call whose end is this iPad (-isEndpointOnCurrentDevice there and YES, asked again at the tap); without it the card has no buttons" \
  "fn $L 'static void DMLACallAct(' | grep -q 'if (!DMLATypes(object_getClass(call), \"isEndpointOnCurrentDevice\", \"B16@0:8\", NO) || !DMLACallBool(call, \"isEndpointOnCurrentDevice\")) return;' \
   && fn $L 'static DMLASection *DMLACallSectionFor(' | grep -q 'if (!ended && it.onThisDevice) {' && fn $L 'static void DMLACallsRead(' | grep -q 'it.onThisDevice = hasEnd;'"

check "L8: our activity observer claims only the items we show, takes no alerts (no presentAlert: / dismissAlert: of ours), and swallows an unknown message" \
  "grep -q -- '- (BOOL)shouldHandleActivityItem:(id)item { return DMLAAppsClaims(item); }' $A && ! grep -q -- '- (void)presentAlert:' $A && ! grep -q -- '- (void)dismissAlert:' $A \
   && grep -q -- '- (NSMethodSignature \\*)methodSignatureForSelector:(SEL)sel {' $A && grep -q -- '- (void)forwardInvocation:(NSInvocation \\*)inv {' $A \
   && fn $A 'static BOOL DMLAAppsClaims(' | grep -q 'return \\[bid isKindOfClass:\\[NSString class\\]\\] && !DMLAAppsSkipped(bid);'"

check "L9: a change that keeps the state (Now Playing's art or words, a timer read again) redraws its pills in place; only a copy whose pill changed width lays out" \
  "fn $L 'static void DMLANowPlayingApply(' | grep -q 'DMLARefreshPillsOf(@\"np\");' && ! fn $L 'static void DMLANowPlayingApply(' | grep -q 'setNeedsLayout' \
   && ! fn $L 'static void DMLATimersApply(' | grep -q 'setNeedsLayout' && fn $L 'static void DMLARefreshPillsOf(' | grep -q 'if (fabs(w - p.bounds.size.width) > 0.5) relayout = YES;'"

# ---- the crash guard
check "the crash guard: a crash in the feature's code turns Live Activities in Menu Bar off; in the apps' path only Apps" \
  "grep -q '^target liveActivities pref com.besiktasliseba.macstatusbar liveActivities 0 1 Live Activities in Menu Bar|' crashmap-rules.txt \
   && grep -q '^target liveActivitiesApps pref com.besiktasliseba.macstatusbar liveActivitiesApps 0 1 Apps|' crashmap-rules.txt \
   && grep -q '^sym MacStatusBarCore ^_\\*DMLA(?!Apps)\\[A-Z\\] liveActivities$' crashmap-rules.txt && grep -q '^file MacStatusBarCore ^LiveActivityApps\\\\.h\$ liveActivitiesApps$' crashmap-rules.txt \
   && grep -q '^file MacStatusBarCore ^LiveActivities\\\\.h\$ liveActivities$' crashmap-rules.txt"
check "logs never name a track, a caller or a timer (short ids, kinds and counts only)" \
  "! grep -E 'DMLog\\(.*(it\\.title|it\\.subtitle|displayName|\\.title\\]|title\\])' $L $A"
check "no em dash in the feature's code, test or Settings texts" "! grep -q \$'\\xe2\\x80\\x94' $L $A ../common/LiveActivities.h test-liveactivities.c $LP"
[ $fails = 0 ] && echo "test-liveactivities: all checks pass" || { echo "test-liveactivities: checks FAILED"; exit 1; }
