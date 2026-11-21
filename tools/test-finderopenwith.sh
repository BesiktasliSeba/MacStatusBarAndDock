#!/bin/bash
# Mac test of Open With (1.8.8.1 B67, KT 21 Nov: "ipa's etc should be able to be opened in trollstore"): statusbar/FinderOpenWith.h's rule (which apps
# claim a file, the list's order, where the copy goes: test-finderopenwith.m), then the wiring as built: Finder's and the desktop's menus, the apps
# read from their Info.plists off the main thread, the hand-over (a copy, never the file; the app opened as from its Dock icon, a window when apps
# open as windows; the copy's URL to its window's scene), the Dock's Downloads stack's way in, the scene lookup, the crash map.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -framework UniformTypeIdentifiers -o "$W/tow" test-finderopenwith.m
"$W/tow"
F=../statusbar/Finder.h
O=../statusbar/FinderOpenWith.h
D=../statusbar/Desktop.h
S=../statusbar/StatusBar.x
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$2"; }
has() { grep -qF -- "$2" <<< "$1"; }
check "Finder.h includes FinderOpenWith.h, Foundation only (no UIKit, nothing of SpringBoard's)" \
  "grep -q '^#include \"FinderOpenWith.h\"' $F && [ \"\$(grep -c '^#import\|^#include' $O)\" = 2 ] && grep -q '^#import <Foundation/Foundation.h>' $O && grep -q '^#include <string.h>' $O && ! grep -q 'UIKit\|objc_msgSend\|SpringBoard\b.*(' $O"
check "  ... and no block in it: a block's symbol (___DMFinder...) is not Finder's by the crash map's symbol rule, every function there is a DMFinderOpenWith... one" \
  "! grep -v '^//' $O | grep -q '\\^' && grep -q 'sortUsingFunction:DMFinderOpenWithCompare context:NULL' $O"
MENU=$(awk 'index($0, "- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)cmi configurationForMenuAtLocation:(CGPoint)loc {") == 1 {f=1} f {print} f && /^}/ {exit}' $F)
# (three lines in a row: Open, the submenu made, the submenu added -- adjacent, each line whole)
seq3() { awk -v a="$2" -v b="$3" -v c="$4" '{ l[NR] = $0 } END { for (i = 1; i + 2 <= NR; i++) if (l[i] == a && l[i+1] == b && l[i+2] == c) { print "ok"; exit } }' <<< "$1" | grep -q ok; }
check "Finder's menu for one item: Open With right after Open, the item's own submenu (none for a folder, an app or an iCloud file not downloaded)" \
  "seq3 \"\$MENU\" '            [top addObject:A(@\"Open\", nil, ^{ [w open:it]; })];' '            UIMenu *openWith = DMFinderOpenWithMenu(it, w, nil);   // (the apps that open this file, as a Mac'\\''s Open With: an .ipa in TrollStore, 1.8.8.1 B67)' '            if (openWith) [top addObject:openWith];' \
   && [ \$(grep -c 'DMFinderOpenWithMenu(' $F) = 3 ]"
check "  ... not in the menu for several selected items (an Open With is for one file, as Share's list is the same for all)" \
  "! awk '/if \(many\) \{/{m=1} /\} else if \(it\) \{/{m=0} m && /DMFinderOpenWithMenu/{print}' <<< \"\$MENU\" | grep -q . && awk '/if \(many\) \{/{m=1} /\} else if \(it\) \{/{m=0; e=1} e && /DMFinderOpenWithMenu\(it, w, nil\)/{print}' <<< \"\$MENU\" | grep -q ."
check "the desktop's menu: Open With for one icon (none for several selected), after Open, with Finder's operations host for its sheets" \
  "seq3 \"\$(cat $D)\" '        [top addObject:A(@\"Open\", nil, ^{ [ws dm_openItems:sel newWindow:NO]; })];' '        UIMenu *openWith = many ? nil : DMFinderOpenWithMenu(v.item, ops, nil);   // (one file: the apps that open it, as Finder'\\''s menu, 1.8.8.1 B67)' '        if (openWith) [top addObject:openWith];' \
   && [ \$(grep -c 'DMFinderOpenWithMenu(' $D) = 1 ] && grep -qF 'DMFinderWindow *ops = DMFinderOps();' $D"
SM=$(fn '__attribute__((visibility("default"))) BOOL MSBDFinderStackItemMenu(NSString *path, CGPoint sp, UIView *from, dispatch_block_t open, dispatch_block_t closeStack) {' $F)
check "the Dock's Downloads stack's item menu (B66): Open With right after its Open, one file's submenu, its rows closing the stack first (1.8.8.1 integration)" \
  "has \"\$SM\" '        if (r == kDMFSMOpen) { UIMenu *ow = DMFinderOpenWithMenu(it, DMFinderOps(), close); if (ow) [group addObject:ow]; }   // (B67: the apps that open the file, after Open, as in Finder'\\''s own menu; its rows close the stack first)' \
   && [ \$(grep -c 'DMFinderOpenWithMenu(it, DMFinderOps(), close)' $F) = 1 ] && awk '/\\[group addObject:e\\];/{e=NR} /DMFinderOpenWithMenu\\(it, DMFinderOps\\(\\), close\\)/{o=NR} END{exit !(e && o == e + 1)}' <<< \"\$SM\""
M=$(fn 'static UIMenu *DMFinderOpenWithMenu(DMFinderItem *it, DMFinderWindow *w, dispatch_block_t before) {' $F)
check "the submenu: nil for a folder or an iCloud file, nil when no app claims it; each row hands the file to its app (the window weakly)" \
  "has \"\$M\" 'if (!it || it.dir || it.cloud) return nil;' && has \"\$M\" 'if (!apps.count) return nil;' && has \"\$M\" 'if (first) first(); DMFinderOpenWith(path, b, ws ?: DMFinderOps());' && has \"\$M\" '__weak DMFinderWindow *ws = w;' && has \"\$M\" 'menuWithTitle:@\"Open With\"'"
A=$(fn 'static NSArray<NSDictionary *> *DMFinderOpenWithAppsFor(NSString *path) {' $F)
check "the apps: FinderOpenWith.h's claim with every type of the extension and their parents, its order; no hidden app, no Safari, not SpringBoard, only apps with a Home Screen icon" \
  "has \"\$A\" 'int r = DMFinderOpenWithRank(@{@\"CFBundleDocumentTypes\": a[@\"d\"]}, ext, types);' && has \"\$A\" 'return DMFinderOpenWithOrder(found);' && has \"\$A\" 'if ([hidden containsObject:b] || DMFinderAppRefusesFiles(b) || [b isEqualToString:@\"com.apple.springboard\"]) continue;' \
   && has \"\$A\" 'if (r > 0 && DMHasHomeIcon(b))' && has \"\$A\" 'NSSet *hidden = DMFinderHiddenApps();' && has \"\$A\" 'if (!ext.length) return @[];' \
   && fn 'static NSArray<NSString *> *DMFinderOpenWithTypes(NSString *ext) {' $F | grep -qF 'typesWithTag:ext tagClass:UTTagClassFilenameExtension conformingToType:nil' && fn 'static NSArray<NSString *> *DMFinderOpenWithTypes(NSString *ext) {' $F | grep -qF 'for (UTType *s in t.supertypes)'"
X=$(fn 'static NSArray<NSDictionary *> *DMFinderOpenWithIndex(BOOL wait) {' $F)
check "the apps' document types: read from each installed app's Info.plist, kept 30 s and made again in the background; only a menu before the first one waits, a Finder window opening reads them ahead" \
  "fn 'static NSArray<NSDictionary *> *DMFinderOpenWithScan(void) {' $F | grep -qF 'URLByAppendingPathComponent:@\"Info.plist\"' && fn 'static NSArray<NSDictionary *> *DMFinderOpenWithScan(void) {' $F | grep -qF '@\"allInstalledApplications\"' \
   && has \"\$X\" 'CACurrentMediaTime() - gFinderOpenWithAt > 30.0' && has \"\$X\" 'if (start) dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{' && has \"\$X\" 'if (!have && wait) {' && has \"\$X\" 'os_unfair_lock_lock(&gFinderOpenWithLock);' \
   && has \"\$A\" 'DMFinderOpenWithIndex(YES)' && fn 'static void DMFinderOpen(NSString *path, BOOL newWindow) {' $F | grep -qF 'DMFinderOpenWithIndex(NO);'"
check "  ... the read never on the main thread: only in the background block; the first menu waits for it at most 0.5 s, then goes without Open With (1.8.8.1 B67 review: a whole read there froze SpringBoard as long as LaunchServices took)" \
  "[ \$(grep -c 'DMFinderOpenWithScan()' <<< \"\$X\") = 1 ] && awk '/if \\(start\\) dispatch_group_async\\(group, /{b=NR} /NSArray \\*now = DMFinderOpenWithScan\\(\\);/{s=NR} END{exit !(b && s == b + 1)}' <<< \"\$X\" \
   && has \"\$X\" 'if (dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC))) != 0) {' && ! has \"\$X\" 'DISPATCH_TIME_FOREVER' \
   && awk '/dispatch_group_wait\\(group,/{w=NR} w && NR > w && /return @\\[\\];/{r=NR; exit} END{exit !(w && r)}' <<< \"\$X\" && [ \$(grep -c 'DMFinderOpenWithScan()' $F) = 1 ]"
H=$(fn 'static void DMFinderOpenWith(NSString *path, NSString *bundle, DMFinderWindow *w) {' $F)
check "the hand-over copies, never hands the file itself: a clone (else a copy within Share's cap, 200 MB kept free) into FinderOpenWith.h's place, a free name there, off the main thread" \
  "has \"\$H\" 'dispatch_async(DMFDStageQueue(), ^{' && has \"\$H\" 'NSString *dir = DMFinderOpenWithInbox(container, fallback), *why = nil;' && has \"\$H\" 'NSString *dst = DMFinderStagedPath(dir, name);' \
   && has \"\$H\" 'clonefile(src.fileSystemRepresentation, dst.fileSystemRepresentation, 0) == 0' && has \"\$H\" 'if (size > kFDCopyCap)' && has \"\$H\" 'size + 200ULL * 1024 * 1024 > DMFinderFreeSpace(dir)' && has \"\$H\" 'ok = [fm copyItemAtPath:src toPath:dst error:&e];' \
   && ! has \"\$H\" 'fileURLWithPath:src' && ! has \"\$H\" 'fileURLWithPath:path' && ! has \"\$H\" 'moveItemAtPath' && ! has \"\$H\" 'removeItemAtPath'"
check "  ... the app's data container (LaunchServices'), else Finder's own folder for that app in SpringBoard's tmp" \
  "has \"\$H\" 'container = DMFDContainer(bundle).path;' && has \"\$H\" '[[NSTemporaryDirectory() stringByAppendingPathComponent:@\"msb-finder-openwith\"] stringByAppendingPathComponent:bundle]'"
check "  ... then the app opens as from its Dock icon (DMOpenApp: a window when apps open as windows, on every engine) and the copy's URL goes to its window's scene" \
  "awk '/DMOpenApp\(bundle\);/{o=NR} /DMFinderOpenWithHandTo\(bundle, dst, 0\);/{d=NR} /if \(!ok\) \{/{k=NR} END{exit !(k && o > k && d == o + 1)}' <<< \"\$H\" && has \"\$H\" 'DM_FEATURE_MARK(\"finder-open-with\");'"
T=$(fn 'static void DMFinderOpenWithHandTo(NSString *bundle, NSString *dst, int attempt) {' $F)
check "  ... once the app is up in front (its scene foreground: ours or FrontBoard's), waited for up to 60 s -- Fit's question holds a launch --, then DMDeliverURLToWindow; never up: only our copy goes" \
  "has \"\$T\" 'if (fg) { DMDeliverURLToWindow(bundle, [NSURL fileURLWithPath:dst], 0); return; }' && has \"\$T\" 'id scene = DMSceneForBundle(bundle) ?: DMFrontBoardSceneForBundle(bundle);' && has \"\$T\" 'if (attempt >= 240) {' \
   && has \"\$T\" '(int64_t)(0.25 * NSEC_PER_SEC)' && has \"\$T\" '[[NSFileManager defaultManager] removeItemAtPath:dst error:nil];' && [ \$(grep -c 'removeItemAtPath' <<< \"\$T\") = 1 ] && ! has \"\$H\" 'DMDeliverURLToWindow'"
check "  ... a copy that can't be made: a sheet says why, nothing opens" \
  "has \"\$H\" 't be opened in %@\", name, app] message:why' && awk '/if \(!ok\) \{/{k=NR} /sheetTitle:/{s=NR} /return;/{if (k && !r) r=NR} END{exit !(k && s > k && r > s)}' <<< \"\$H\""
DL=$(fn 'static void DMDeliverURLToWindow(NSString *bundleID, NSURL *url, int attempt) {' $S)
check "the URL reaches a window just opened: the scene our hook saw, else FrontBoard's own (a 16 Stage Manager window, an app starting)" \
  "has \"\$DL\" 'id scene = DMSceneForBundle(bundleID) ?: DMFrontBoardSceneForBundle(bundleID);' && has \"\$DL\" 'if (!scene || !fg || content < 2) {' && has \"\$DL\" 'UIOpenURLAction' \
   && awk '/^static id DMFrontBoardSceneForBundle\(NSString \*bundleID\) \{/{a=NR} /^static void DMDeliverURLToWindow\(NSString \*bundleID, NSURL \*url, int attempt\) \{/{b=NR} END{exit !(a && b > a)}' $S"
check "  ... a row may do something first (the Dock's Downloads stack closes itself, as its other rows do: its item menu is Finder's own); Finder's and the desktop's pass nothing" \
  "has \"\$M\" 'dispatch_block_t first = [before copy];' && [ \$(grep -c 'DMFinderOpenWithMenu(it, w, nil)' $F) = 1 ] && [ \$(grep -c 'DMFinderOpenWithMenu(v.item, ops, nil)' $D) = 1 ]"
check "a crash in Open With is Finder's: its functions are DMFinder... (the symbol rule) or in Finder.h (the file rule), FinderOpenWith.h's too" \
  "grep -q '^sym MacStatusBarCore ^_?DM(Finder|Native|OpenFinder|OpenNativeWindow)\\[A-Z\\] finder' crashmap-rules.txt && grep -q '^file MacStatusBarCore ^(Finder|NativeWindow)\\\\.h\$ finder' crashmap-rules.txt \
   && [ \$(grep -c '^static' $O) -gt 0 ] && ! grep '^static' $O | grep -v '^static [^(]*[ *]DMFinderOpenWith[A-Za-z]*('"
check "nothing of it is reached from a constructor: the menus and the stack call it, never a %ctor or the prefs load" \
  "! awk '/^%ctor/{c=1} c && /DMFinderOpenWith/{print} c && /^}/{c=0}' $S | grep -q ."
[ $fails = 0 ] && echo "test-finderopenwith: wiring checks pass" || { echo "test-finderopenwith: wiring checks FAILED"; exit 1; }
