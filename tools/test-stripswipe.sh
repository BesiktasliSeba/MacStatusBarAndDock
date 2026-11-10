#!/bin/bash
# Mac test of Recent Apps with Left-Edge Swipe (Stage Manager engine, 1.8.4.2, off unless switched on): the gate, the pref, the Settings row and where it
# shows. With it off the gate stays as it was.
set -e
cd "$(dirname "$0")"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
S=../statusbar/StatusBar.x; P=../statusbar/macstatusbarprefs/Resources/Windows.plist; R=../common/OwnPageRows.h; M=../statusbar/macstatusbarprefs/MSBRootListController.m; 
check "the gate: off, held off as before; on, Apple's decides, never over the Mac Switcher's view nor with the Dock at Left" \
  "grep -qF 'if (DMSMFree() && (!gSMStripSwipe || gMSWOpen || gMSWSwitching || DMDockSideNow([UIScreen mainScreen].bounds.size) == MSBDDockLeft)) { DM_FEATURE_MARK(\"sm-no-strip-reveal\"); return NO; }' $S && grep -qF 'BOOL begins = o_SMStripRevealBegin(self, _cmd, g);' $S"
check "the strip stays hidden for Stage Manager, also during a reveal" "grep -qF 'return DMSMFree() ? YES : %orig;' $S && ! grep -qF 'during the swipe.s reveal Stage Manager says strip hidden' $S"
check "off unless switched on, a boolean only" "grep -qF 'static BOOL gSMStripSwipe = NO;' $S && grep -qF 'BOOL stripSwipe = sw && CFGetTypeID(sw) == CFBooleanGetTypeID() && CFBooleanGetValue(sw);' $S"
check "a window drag still can't start in the edge zone" "grep -qF '(IMP)DMSMUnpinBegin' $S"
check "the Settings row: off by default, in a group with a footer, no em dash" \
  "python3 -I -c \"import plistlib,sys; it=plistlib.load(open('$P','rb'))['items']; i=[x.get('id') for x in it].index('STRIP_SWIPE'); s=it[i]; g=it[i-1]; sys.exit(0 if s['key']=='smStripSwipe' and s['default'] is False and g.get('id')=='STRIP_SWIPE_GROUP' and '\\u2014' not in g['footerText'] else 1)\""
check "shown with Stage Manager as the engine only, in the page and the search" \
  "grep -qF 'if ([group isEqualToString:kMSBDStripSwipeGroupID] && (!s.engineWorks || !s.stageManagerEngine || !MSBDStripSwipeOS([NSProcessInfo processInfo].operatingSystemVersion.majorVersion))) return YES;' $R && grep -qF 'inStripSwipe = [sp.identifier isEqualToString:kMSBDStripSwipeGroupID];' $M"
check "  ... and only on iPadOS 16 (18.5: SpringBoard's own assertion on a window closed with the strip out; 17 untried): row and switch" \
  "grep -qF 'static inline BOOL MSBDStripSwipeOS(long major) { return major == 16; }' $R && grep -qF 'if (!MSBDStripSwipeOS([NSProcessInfo processInfo].operatingSystemVersion.majorVersion)) {' $M \
   && grep -qF 'if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion != 16) stripSwipe = NO;' ../statusbar/StatusBar.x"
exit $fails
