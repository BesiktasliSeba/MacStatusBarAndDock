#!/bin/bash
# Mac test of Finder's Applications rows (statusbar/FinderApps.h, test-finderapps.m; 1.7.6 item 2, KT): each row is the app's .app inside its
# bundle container, so a drag onto the desktop (or into a folder, the Dock's Downloads stack), a copy, Get Info act on the app -- the desktop gets
# "Tips.app", an app item, not the container's UUID folder. Then the wiring as built: where Finder.h's listing makes the row, that the drop copies
# the row's path, that the installed app is never changed, and how the desktop shows, opens and removes an .app item.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tfa" test-finderapps.m
"$W/tfa"
F=../statusbar/Finder.h
D=../statusbar/Desktop.h
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$F"; }
LIST=$(fn 'static NSArray<DMFinderItem *> *DMFinderList(NSString *path, BOOL hidden, NSError **err) {')
check "Finder.h includes FinderApps.h" "grep -q '^#include \"FinderApps.h\"' $F"
check "the listing: in Applications (only there), a UUID folder's row becomes its .app -- path, name, app, kind Application" \
  "echo \"\$LIST\" | grep -q 'if (it.dir && it.name.length == 36 && \[rn isEqualToString:@\"/var/containers/Bundle/Application\"\]) {' && echo \"\$LIST\" | grep -q 'NSString \*app = DMFinderBundleApp(it.path);' && echo \"\$LIST\" | grep -q 'if (app) { it.path = DMFinderNorm(app); it.name = app.lastPathComponent; it.app = it.path; it.kind = @\"Application\"; it.package = YES; }'"
check "  ... the name shown stays the app's own (read from the container before the row becomes the .app), the hidden-app rule still by container" \
  "echo \"\$LIST\" | awk '/if \(n\) it.display = n;/{a=NR} /DMFinderBundleApp\(it.path\)/{b=NR} END{exit !(a && b && a < b)}' && echo \"\$LIST\" | grep -q 'hiddenApps containsObject:DMFinderContainerInfo(DMFinderNorm(u.path))\[1\]'"
check "  ... no other way to the .app is left (the old loop over the container's names is gone)" \
  "! echo \"\$LIST\" | grep -q 'if (\[f hasSuffix:@\".app\"\]) { it.app'"
check "the drop copies what the row is (its path): Finder's drag carries the items, the drop moves / copies their paths" \
  "fn 'static void DMFDDropInto(DMFDrag *d, NSString *dest, DMFinderWindow *host, NSString *where) {' | grep -q '\[host dm_moveItems:\[d.items valueForKey:@\"path\"\] to:dest copy:copy\];'"
check "  ... copied, never moved, out of a place Finder doesn't change (the installed app stays where it is)" \
  "fn 'static BOOL DMFDCopies(DMFDrag *d, NSString *dest) {' | grep -q 'for (DMFinderItem \*it in d.items) if (!DMFinderCanChange(it.path)) return YES;'"
check "  ... the copy keeps the .app's name (a free name in the folder: Tips 2.app beside a Tips.app)" \
  "fn '- (void)dm_run:(NSString *)kind what:(NSString *)what paths:(NSArray<NSString *> *)paths into:(NSString *)dir undoable:(BOOL)undoable {' | grep -q 'NSString \*dst = nil, \*name = src.lastPathComponent;'"
check "the row still opens the app and shows its icon (it.app), Show Package Contents still opens the .app" \
  "fn '- (void)open:(DMFinderItem *)it {' | grep -q 'if (it.app) {' && grep -q 'if (it.app) { UIImage \*ai = DMFinderAppIcon(it, side); if (ai) return ai; }' $F && grep -q 'Show Package Contents\", @\"shippingbox\", ^{ \[w go:it.app ?: it.path\]; }' $F"
check "the desktop: an .app item is the app -- its icon, opened as the app, never a folder to open or to drop into" \
  "grep -q 'if (it.dir && !it.package && !\[it.name hasSuffix:@\".app\"\]) return \[self dm_folderImage\];' $D && grep -q 'if (it.dir && !it.package && !\[it.name hasSuffix:@\".app\"\]) DMFinderOpen(it.path' $D && grep -q 'v.item.dir && !v.item.locked && !v.item.package && !\[v.item.name hasSuffix:@\".app\"\]) { if (icon) \*icon = v; return v.item.path; }' $D"
check "  ... an .app is opened by its Info.plist's bundle id (DMOpenApp), its icon by the same id" \
  "fn '- (void)open:(DMFinderItem *)it {' | grep -q 'stringByAppendingPathComponent:@\"Info.plist\"\]\]\[@\"CFBundleIdentifier\"\];' && grep -q 'NSDictionary \*info = \[NSDictionary dictionaryWithContentsOfFile:\[it.path stringByAppendingPathComponent:@\"Info.plist\"\]\];' $F"
check "a crash in FinderApps.h is Finder's (its functions are DMFinder... -- the symbol rule)" \
  "grep -q '^sym MacStatusBarCore ^_?DM(Finder|Native|OpenFinder|OpenNativeWindow)\\[A-Z\\] finder' crashmap-rules.txt && grep -q '^static NSString \\*DMFinderBundleApp(' ../statusbar/FinderApps.h && [ \$(grep -c '^static' ../statusbar/FinderApps.h) = \$(grep -c '^static [A-Za-z]* \\*\\{0,1\\}DMFinder' ../statusbar/FinderApps.h) ]"
check "the debug drag (fdragto_<name>|<x>,<y>): debug builds only" \
  "awk '/^#if DEBUG/{d=1} /^#endif/{d=0} /^static void DMFinderTestDragTo/{exit !d}' $F && grep -q 'else if (\[cmd hasPrefix:@\"fdragto_\"\]) DMFinderTestDragTo' ../statusbar/StatusBar.x"
[ $fails = 0 ] && echo "test-finderapps: wiring checks pass" || { echo "test-finderapps: wiring checks FAILED"; exit 1; }
