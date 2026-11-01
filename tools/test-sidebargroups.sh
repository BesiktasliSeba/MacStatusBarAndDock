#!/bin/bash
# Mac test of the sidebar's groups (common/SidebarGroups.h, test-sidebargroups.m; 1.7.5 item 2: Notifications & Sounds, Focus & Screen Time on
# iPadOS 15-17), then the wiring as built (macsettings/SidebarGroups.x): grouped only with the link redirect in place, through the list's own calls,
# links and search sections through our rows, nothing on 18.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tsg" test-sidebargroups.m
"$W/tsg"
X=../macsettings/SidebarGroups.x
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$2"; }
check "built into MacSettings (Settings, only while the tweak runs: never in rows-only mode), release builds too" \
  "grep -qE '^MacSettings_FILES = .* SidebarGroups.x' ../macsettings/Makefile"
check "18 (no PSUIPrefsListController) and anything missing: nothing grouped -- never without Settings' URL handler (a link could end on a missing row)" \
  "fn '%ctor {' $X | grep -q 'if (!root || !app || !list) return;' && fn '%ctor {' $X | grep -q 'if (!calls || !links) {' && fn '%ctor {' $X | awk '/if \(!calls \|\| !links\)/{a=NR} /gSGOK = YES;/{b=NR} END{exit !(a && b && a < b)}'"
check "Apple's rows leave through the list's own calls, by the shared MSSGApplyPlan the Mac test runs (from a copy, each row found again first)" \
  "fn 'static void SGApply(id list) {' $X | grep -q 'MSSGApplyPlan(list, ' && ! fn 'static void SGApply(id list) {' $X | grep -qE 'removeObject|insertObject|setArray' && grep -q 'NSArray \*before = \[(NSArray \*)live copy\];' ../common/SidebarGroups.h && grep -q 'if (ia == NSNotFound || ib == NSNotFound) continue;' ../common/SidebarGroups.h"
check "  ... main thread only, never inside itself; a group whose row is gone keeps nothing; the kept rows read under a lock" \
  "fn 'static void SGApply(id list) {' $X | grep -q 'if (!gSGOK || !list || applying || !\[NSThread isMainThread\]) return;' && fn 'static void SGApply(id list) {' $X | grep -q 'SGSetMembers(g, nil);' && grep -q 'static NSArray \*SGMembers(int g) { os_unfair_lock_lock(&gSGLock);' $X"
check "Settings taking one of Apple's grouped rows away ends the group (Apple's other row back); a row put after one goes after ours" \
  "grep -q 'if (spec && \[SGSpecs(self) indexOfObjectIdenticalTo:spec\] == NSNotFound && SGAppleRowGone(self, spec, nil)) return;' $X && grep -q 'if (!inList && MSSGGroupOfApple(ident, NULL) >= 0 && SGAppleRowGone(self, nil, ident)) return;' $X && grep -q '%orig(spec, SGAfterID(self, ident), animated);' $X && grep -q '%orig(specs, SGAfterID(self, ident), animated);' $X"
check "Apple's pages open from our page as Settings makes any row's page (-controllerForSpecifier:, shown on top), by a tap or a link -- never the sidebar's special-bundle loader or the generic tap of a bundle row (both throw, 17.5.1)" \
  "fn '- (UIViewController *)msbd_show:(PSSpecifier *)sp animated:(BOOL)animated {' $X | grep -q '@selector(controllerForSpecifier:), sp)' && fn '- (UIViewController *)msbd_show:(PSSpecifier *)sp animated:(BOOL)animated {' $X | grep -q '@selector(showController:animate:), c, animated)' && grep -q '        \[self msbd_show:sp animated:YES\];' $X && ! grep -qE 'lazyLoadSpecialBundleForSpecifier|msbd_preload|lazyLoadBundle:\)' $X"
check "  ... a link: once our page is settled, shown only once, the rest of the link handed to Apple's page; a link reaching the sidebar another way goes through our row" \
  "grep -q 'BOOL there = above && \[above respondsToSelector:@selector(specifier)\]' $X && grep -q 'if (!row) return \[super prepareHandlingURLForSpecifierID:specID resourceDictionary:dict animatePush:animate withCompletion:completion\];' $X && grep -q '\[(PSListController \*)c handleURL:rest withCompletion:completion\]; return;' $X && grep -q '\[self msbd_open:row rest:rest completion:completion attempt:0\];' $X && grep -q 'if (g >= 0 && SGGrouped(g)) {' $X && grep -q 'd\[@\"root\"\] = @(kMSSGGroups\[g\].ident);' $X"
check "grouped when the sidebar appears, is built again, or a link asks for our row first (a cold start)" \
  "grep -A3 -- '- (void)viewWillAppear:(BOOL)animated {' $X | grep -q 'SGApply(self);' && grep -A3 -- '- (void)reloadSpecifiers {' $X | grep -q 'SGApply(self);' && grep -q 'if (r || inside || MSSGGroupOfOurs(identifier) < 0) return r;' $X && grep -q '    inside = YES; SGApply(self); inside = NO;' $X"
check "links: both of Settings' URL handlers send Apple's grouped pages through our row, only for a group in the sidebar now" \
  "grep -q '%orig(SGRoute(url, fromSearch ? @\"search\" : @\"link\"), animated, fromSearch, completion);' $X && grep -q '%orig(SGRoute(url, @\"open\"));' $X && fn 'static NSURL *SGRoute(NSURL *url, NSString *how) {' $X | grep -q 'MSSGRewrite(s, ^BOOL(int g) { return SGGrouped(g); });'"
check "our page: Apple's own two rows (a tap opens Apple's page as the sidebar did), its title our row's" \
  "fn '- (NSMutableArray *)specifiers {' $X | grep -q 'SGMembers(g)' && grep -q 'if (g >= 0) self.title = SGTitle(g, SGMembers(g));' $X && grep -q '\[super tableView:tv didSelectRowAtIndexPath:ip\];' $X"
check "  ... titled with Apple's own two names (the iPad's language), else ours" \
  "fn 'static NSString *SGTitle(int g, NSArray *members) {' $X | grep -q 'stringWithFormat:@\"%@ & %@\", a, b' && grep -q 'preferenceSpecifierNamed:SGTitle(g, members)' $X"
check "search: a grouped row's section asked of our row, never by Apple's own identifier (its icon lookup takes a missing sidebar cell and threw: 17.5.1); Apple's order inside a group; Apple's row's own icon" \
  "grep -q '    if (ours == category) return %orig;' $X && grep -q '    return %orig(controller, ours);' $X && grep -q 'return %orig(controller, SGCategory(a), SGCategory(b));' $X && grep -q 'if (ga >= 0 && ga == gb && SGMembers(ga)) return ma < mb' $X && grep -q 'return \[img isKindOfClass:\[UIImage class\]\] ? img : %orig(controller, @(kMSSGGroups\[g\].ident));' $X && ! grep -q 'BOOL apple = %orig' $X && ! grep -q 'id apple = %orig' $X"
check "our row: Apple's first row's icon (its image or the keys its cell loads it by), a plain link to our page" \
  "fn 'static PSSpecifier *SGMakeRow(int g, NSArray *members) {' $X | grep -q 'rangeOfString:@\"icon\" options:NSCaseInsensitiveSearch' && fn 'static PSSpecifier *SGMakeRow(int g, NSArray *members) {' $X | grep -q 'detail:\[MSSGPageController class\] cell:1'"
[ $fails = 0 ] && echo "test-sidebargroups: wiring checks pass" || { echo "test-sidebargroups: wiring checks FAILED"; exit 1; }
