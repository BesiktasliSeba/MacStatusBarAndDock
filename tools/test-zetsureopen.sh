#!/bin/bash
# Mac test of a Zetsu reopen right after a close (statusbar/ZetsuReopen.h, test-zetsureopen.c): the request waits for the closed window's
# controller to go, at most 2 s (1.7.4 item 16: a reopen 0.2 s after a close showed no window); and, as built (StatusBar.x), a controller Zetsu
# reopens while it is still closing it is let through (item 18: 8599d01's closed mark blocked that reopen's -setHost:) -- only for an ask 0.5 s or
# more after the close, never the closed window's own pending retry (1.7.4 review) --; a second open of the app while the reopen waits is not run
# full screen too (DMOpenApp's guard, 1.7.4 review); a new window is back at its own place only with a place from before it opened (1.8.1 item 9).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreGraphics -o "$W/tzr" test-zetsureopen.c
"$W/tzr"
X=../statusbar/StatusBar.x; fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$X"; }
check "the close records its controller (weakly) and drops the one-at-a-time note of a window still on its way" \
  "fn 'static void DMZetsuClose(UIWindow *w) {' | grep -q 'c.controller = ctl; c.at = CACurrentMediaTime();' && fn 'static void DMZetsuLaunch(NSString *bundleID) {' >/dev/null && fn 'static void DMZetsuClose(UIWindow *w) {' | grep -q '\\[gZetsuOpening removeObjectForKey:cb\\]'"
check "a reopen waits while the closed controller lives, before the one-at-a-time check, and records when Zetsu was asked" \
  "fn 'static void DMZetsuLaunch(NSString *bundleID) {' | awk '/closed && closed.controller/ {w=NR} /gZetsuOpening\\[bundleID\\];/ {d=NR} /gZetsuAskedAt\\[bundleID\\] = @\\(now\\);/ {a=NR} /postNotification/ {p=NR} END {exit !(w && d && a && p && w < d && a < p)}'"
check "the closed mark keeps the close's time" \
  "grep -q 'objc_setAssociatedObject(self, kZetsuCtlClosedKey, @(CACurrentMediaTime()), OBJC_ASSOCIATION_RETAIN_NONATOMIC);' $X"
check "a closed controller's -setHost: within 1 s after a later ask, made 0.5 s or more after the close, is Zetsu's reopen (ZetsuReopen.h's rule, as tested above): the mark goes and it runs; otherwise it still stops" \
  "awk '/^- \\(void\\)setHost:\\(float\\)ratio \\{/ {f=1} f {print} f && /^}/ {exit}' $X | grep -q 'if (MSBDZetsuReusesClosed(asked != nil, asked.doubleValue, closedAt.doubleValue, CACurrentMediaTime()) && !DMTestFlag(\"/tmp/msb-zetsu-noreuse\")) {' &&awk '/^- \\(void\\)setHost:\\(float\\)ratio \\{/ {f=1} f {print} f && /^}/ {exit}' $X | grep -q 'objc_setAssociatedObject(self, kZetsuCtlClosedKey, nil' && awk '/^- \\(void\\)setHost:\\(float\\)ratio \\{/ {f=1} f {print} f && /^}/ {exit}' $X | grep -q 'zetsu-closed-retry-stop'"
check "a second open (our menus, Finder, Spotlight's rows) while the reopen waits is not run full screen too: the window on its way counts the wait, a window being closed is not the app's window" \
  "fn 'static BOOL DMZetsuWindowOnItsWay(NSString *bundleID) {' | grep -q '|| gZetsuClosed\\[bundleID\\].asking)) return NO;' && fn 'static BOOL DMZetsuWindowOnItsWay(NSString *bundleID) {' | grep -q 'return !zw || \\[objc_getAssociatedObject(zw, kStageClosingKey) boolValue\\];' && fn 'static void DMOpenApp(NSString *bundleID) {' | grep -q 'DMActiveEngine() == DMEngineZetsu && DMZetsuWindowOnItsWay(bundleID) && !DMTestFlag(\"/tmp/msb-zetsu-nolaunchdedupe\")'"
check "a new Zetsu window's own place is read before its move (the move records the frame it was moved to as the app's place: 1.8.1 item 9)" \
  "fn 'static void DMZetsuAdopt(UIWindow *w) {' | awk '/NSValue \\*lastPlace = gLastWindowFrames\\[bundleID\\];/ {r=NR} /DMZetsuMove\\(w, target, NO, nil\\);/ && !m {m=NR} /if \\(MSBDZetsuOpensAtOwnPlace\\(asked, lastPlace != nil\\) && !CGRectIsNull\\(target\\)\\) DMMarkOwnPlace\\(w, target\\);/ {k=NR} END {exit !(r && m && k && r < m && m < k)}' && ! fn 'static void DMZetsuAdopt(UIWindow *w) {' | grep -q 'gLastWindowFrames\\[bundleID\\] && !CGRectIsNull(target)) DMMarkOwnPlace'"
exit $fails
