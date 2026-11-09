#!/bin/bash
# Mac test of Apple's "Show App Library in Dock" on our Dock page applying at once (1.8.4.1 item 2; common/DockAppLibrary.h, test-dockapplibrary.c),
# then the sites: our page tells SpringBoard once Apple's own switch has changed; the Dock part runs the Dock's parked icon updates (only Apple's own
# two methods, in their shapes, never during a transition) and lays the Dock out again, three passes; and the sweep of the Dock page's other rows
# (Downloads From's Safari row read fresh).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -o "$W/tal" test-dockapplibrary.c
"$W/tal"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
P=../dock/dockmagnificationprefs/DMRootListController.m; D=../dock/Dock.x; DL=../dock/Downloads.m; H=../common/DockAppLibrary.h
fn() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' $2 > "$W/fn"; }
has() { grep -qF -- "$1" "$W/fn"; }   # (a line, as written, in the function fn read last)
before() { awk -v a="$1" -v b="$2" 'index($0, a) && !x {x=NR} index($0, b) && !y {y=NR} END{exit !(x && y && x < y)}' "$W/fn"; }
check "our Dock page: Apple's own App Library row's switch gets one more target (after Apple's, never in place of it), which tells SpringBoard" \
  "grep -qF '#import \"../../common/DockAppLibrary.h\"' $P && grep -qF '#import <notify.h>' $P \
   && fn '- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {' $P \
   && has 'UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];' \
   && has '[sp.identifier isEqualToString:@kMSBDDockAppLibraryRowID]' && has '[(UIControl *)control removeTarget:self action:@selector(msbd_appLibrarySwitched:) forControlEvents:UIControlEventValueChanged];' \
   && has '[(UIControl *)control addTarget:self action:@selector(msbd_appLibrarySwitched:) forControlEvents:UIControlEventValueChanged];' && ! has 'setTarget:' && ! has 'removeTarget:nil' \
   && fn '- (void)msbd_appLibrarySwitched:(id)sender {' $P && has 'notify_post(kMSBDDockAppLibraryNote);'"
check "  ... a reused cell: ours comes off every row's control first and goes back on the App Library row's only (review 1.8.4.1 L1: another switch on that cell told SpringBoard too)" \
  "fn '- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {' $P && has 'if (![control isKindOfClass:[UIControl class]]) return cell;' \
   && before 'removeTarget:self action:@selector(msbd_appLibrarySwitched:)' '[sp.identifier isEqualToString:@kMSBDDockAppLibraryRowID]' \
   && before '[sp.identifier isEqualToString:@kMSBDDockAppLibraryRowID]' 'addTarget:self action:@selector(msbd_appLibrarySwitched:)' && [ \$(grep -c 'msbd_appLibrarySwitched:) forControlEvents' \$W/fn) = 2 ]"
check "SpringBoard: the Dock part listens for it, and each pass runs the parked icon updates, lays the Dock out again and draws the Launchpad picture again" \
  "grep -qF '#include \"../common/DockAppLibrary.h\"' $D && grep -qF 'DMAppLibraryInDockChanged, CFSTR(kMSBDDockAppLibraryNote), NULL,' $D \
   && fn 'static void DMAppLibraryInDockChanged(CFNotificationCenterRef c, void *o, CFNotificationName n, const void *obj, CFDictionaryRef info) {' $D \
   && has 'for (int i = 0; i < kMSBDDockAppLibraryPassCount; i++) {' && has 'kMSBDDockAppLibraryPassAt[i] * NSEC_PER_SEC' \
   && before 'DMDockRunParkedUpdates(why);' 'DMRelayoutDock();' && before 'DMRelayoutDock();' 'DMRefreshLaunchpadIcons();'"
check "  ... the parked updates: every Dock window's view controllers, only where both of Apple's methods are there in their shapes, never during a transition (MSBDDockRunParked), guarded; the recents' left to their own step, after the fade of an icon they removed (review 1.8.4.1 L2)" \
  "fn 'static void DMDockRunParkedUpdates(NSString *why) {' $D && has 'SEL pendingSel = sel_registerName(\"deferredIconUpdates\"), perform = sel_registerName(\"_performDeferredIconUpdates\");' \
   && has 'isEqualToString:@\"SBFloatingDockWindow\"' && has '[todo addObjectsFromArray:vc.childViewControllers];' && has 'id sugg = gDMSuggestionsVC;' \
   && has 'DMFlushDeferredDockIcons(why);' && ! has '[todo addObject:sugg]' && before '[todo addObjectsFromArray:vc.childViewControllers];' 'if (vc == sugg) continue;' \
   && before 'if (vc == sugg) continue;' 'Method mp = class_getInstanceMethod(' \
   && has 'if (!ep || !er || strcmp(ep, \"@16@0:8\") || strcmp(er, \"v16@0:8\")) continue;' && has 'if (MSBDDockRunParked(pending, busy)) {' \
   && has '@try {' && has '} @catch (NSException *e) {' && before 'busy = coord && [coord respondsToSelector:busySel]' 'if (MSBDDockRunParked(pending, busy)) {' \
   && fn 'static void DMFlushDeferredDockIconsAfter(NSString *why, double delay, int tries) {' $D && has 'if (vc && tries < 20 && DMDockIconFading(vc)) { DMFlushDeferredDockIconsAfter(why, 0.05, tries + 1); return; }'"
check "  ... the functions follow the recents' own parked-update code (gDMSuggestionsVC is declared before them)" \
  "awk '/^static __weak id gDMSuggestionsVC = nil;/{a=NR} /^static void DMDockRunParkedUpdates\\(NSString \\*why\\) \\{/{b=NR} END{exit !(a && b && a < b)}' $D"
check "sweep of the Dock page: Downloads From's Safari row is read fresh (its domain synchronised first: no notification is posted for it, and the Safari answer came one use late)" \
  "fn 'static NSArray<DMDownloadSource *> *DMSources(void) {' $DL && before 'CFPreferencesAppSynchronize(DM_DOMAIN);' 'CFPropertyListRef s = CFPreferencesCopyValue(CFSTR(\"downloadsSafari\")'"
check "no em dash in what this item added" "! grep -q \$'\\xe2\\x80\\x94' $H"
exit $fails
