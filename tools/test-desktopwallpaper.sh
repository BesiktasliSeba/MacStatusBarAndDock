#!/bin/bash
# Mac test of Settings > Desktop > Desktop Picture (1.8.6): the rules (test-desktopwallpaper.m on common/DesktopWallpaper.h), then the wiring as
# built: where SpringBoard puts the picture and what it never touches, page 1 only, the prefs it reads, the Settings page; no pictures shipped.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -framework CoreGraphics -o "$W/twp" test-desktopwallpaper.m
"$W/twp"
D=../statusbar/DesktopWallpaper.h; P=../statusbar/macstatusbarprefs/MSBWallpaperController.m; X=../statusbar/StatusBar.x
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$D"; }
check "SpringBoard: the picture goes in the Home Screen variant's own view (17+: PBUIPosterHomeViewController's), as its last subview" \
  "fn 'static UIView *DMWPFindHost(BOOL *shared, NSString **note) {' | grep -q 'DMWPViewOfController(w, @\"PBUIPosterHomeViewController\")' && fn 'static void DMWPTick(void) {' | grep -q '\[host addSubview:gWPPlane\];' && fn 'static void DMWPTick(void) {' | grep -q 'bringSubviewToFront:gWPPlane'"
check "  ... 15/16: the controller's Home Screen view, or the shared one gated by the active variant" \
  "fn 'static UIView *DMWPFindHost(BOOL *shared, NSString **note) {' | grep -q '@\"_homescreenWallpaperView\", @\"_sharedWallpaperView\"' && fn 'static void DMWPUpdateAlpha(void) {' | grep -q 'p.sharedVariant && !DMWPSharedHomeNow()' && fn 'static BOOL DMWPSharedHomeNow(void) {' | grep -q '@\"activeVariant\", @\"variant\"'"
check "  ... the shared view fails closed: locked, blank or no variant to read = not shown, hidden at once on the lock and the blank (review 1.8.6 M1)" \
  "fn 'static BOOL DMWPSharedHomeNow(void) {' | grep -q 'if (locked || blank) return NO;' && fn 'static void DMWPWatchLock(void) {' | grep -q 'com.apple.springboard.hasBlankedScreen' && grep -q 'if (shared) DMWPWatchLock();' $D"
check "nothing of Apple's written: no wallpaper setter, no write to /Library/Wallpaper, no property of their views set" \
  "! grep -n -E 'setWallpaper|setActiveVariant|writeToFile|createFileAtPath|removeItemAtPath|setHidden|setAlpha:' $D | grep -v '^ *//' | grep -q . && ! grep -q 'host\\.\\(alpha\\|hidden\\|transform\\)' $D"
check "page 1 only: the alpha follows the icon scroll view's position against page 1's place (watched by KVO, and every tick)" \
  "fn 'static double DMWPPageOneShown(void) {' | grep -q 'fabs(sc.contentOffset.x - pageX) / pw' && grep -q 'addObserver:gWPWatch forKeyPath:@\"contentOffset\"' $D && fn 'static void DMWPTick(void) {' | grep -q 'DMWPUpdateAlpha();'"
check "laid out as the interface is turned (the wallpaper window does not turn): the screen's interface space mapped into the host, quarter turns only" \
  "fn 'static void DMWPFollowTurn(DMWPPlane *p, UIView *host) {' | grep -q 'convertPoint:CGPointZero fromCoordinateSpace:ui' && fn 'static void DMWPFollowTurn(DMWPPlane *p, UIView *host) {' | grep -q 'fabs(t.a \\* t.d - t.b \\* t.c) != 1.0' && fn 'static void DMWPTick(void) {' | grep -q 'DMWPFollowTurn(gWPPlane, host);'"
check "the TV (KT 10 Nov): the same picture in SBExternalDisplayWallpaperViewController's container on the TV's screen, its last subview, every tick" \
  "fn 'static UIView *DMWPFindTVHost(NSString **note) {' | grep -q 'DMWPViewOfController(w, @\"SBExternalDisplayWallpaperViewController\")' && fn 'static UIView *DMWPFindTVHost(NSString **note) {' | grep -q 'w.screen == \[UIScreen mainScreen\]) continue;' && fn 'static void DMWPTVTick(void) {' | grep -q '\[host addSubview:gWPTVPlane\];' && fn 'static void DMWPTick(void) {' | grep -q 'DMWPTVTick();'"
check "  ... no pages on the TV (shown with its picture), gone with the TV (picture freed), None removes it too" \
  "fn 'static void DMWPUpdateAlpha(void) {' | grep -q 'gWPTVPlane.image ? 1.0 : 0.0' && fn 'static void DMWPTVTick(void) {' | grep -q 'DMWPRemoveTV(@\"no external display desktop now\")' && fn 'static void DMWPRemove(NSString \*why) {' | grep -q 'DMWPRemoveTV(why);'"
check "  ... decoded at the TV's own pixels (its mode), light or dark as the iPad's own screen" \
  "fn 'static void DMWPDecodeIfNeeded(DMWPPlane \*p) {' | grep -q 'DMCall(disp, @\"currentMode\")' && fn 'static BOOL DMWPDarkNow(UIView \*v) {' | grep -q '\[UIScreen mainScreen\].traitCollection.userInterfaceStyle'"
check "touches never stop at the picture" "grep -q 'hitTest:(CGPoint)p withEvent:(UIEvent \\*)e { return nil; }' $D"
check "the picture: decoded off the main thread, the part shown at the screen's pixels" \
  "fn 'static void DMWPDecodeIfNeeded(DMWPPlane *p) {' | grep -q 'dispatch_get_global_queue' && fn 'static CGImageRef DMWPDecode(' | grep -q 'MSBDWallpaperPart(path, iw, ih, spw, sph)' && fn 'static CGImageRef DMWPDecode(' | grep -q 'MSBDWallpaperDecodeSize(part, spw, sph)'"
check "  ... again when the screen turns or the appearance changes (the dark picture)" \
  "fn 'static void DMWPDecodeIfNeeded(DMWPPlane *p) {' | grep -q 'DMWPSameShape(pts, p.shownFor)' && fn 'static NSString *DMWPWantedPath(DMWPPlane *p) {' | grep -q 'gWPDark && DMWPDarkNow(p)'"
check "  ... a picture that can't be read: not tried again at every tick, nothing old left on screen, the light one when the dark one fails (review 1.8.6 M2, L1)" \
  "fn 'static void DMWPDecodeIfNeeded(DMWPPlane *p) {' | grep -q 'p.failedPath isEqualToString:path\] && DMWPSameShape(pts, p.failedFor)' && grep -q 'q.image = nil; q.shownPath = nil;' $D"
check "  ... never more than twice the screen's pixels decoded (a panorama: review 1.8.6 M3)" "fn 'static CGImageRef DMWPDecode(' | grep -q 'budget = 2.0 \* spw \* sph'"
check "prefs: only allowed paths are read; None removes the view and the picture" \
  "fn 'static NSString *DMWPReadPath(const char *key) {' | grep -q 'MSBDWallpaperPathAllowed(s)' && fn 'static void DMWPApplyPref(void) {' | grep -q 'DMWPRemove(@\"None\")'"
check "wired: the 0.2 s tick and the notification" \
  "grep -q '^    DMWPTick();' $X && grep -q 'notify_register_dispatch(kMSBDWallpaperNotify' $X && grep -q '#include \"DesktopWallpaper.h\"' $X"
check "crash guard: a crash in it sets Desktop Picture to None" \
  "grep -q '^target desktopWallpaper pref com.besiktasliseba.macstatusbar desktopWallpaperPath 0 0 offtext=none' crashmap-rules.txt && grep -q '^sym MacStatusBarCore \\^_?DMWP\\[A-Z\\] desktopWallpaper' crashmap-rules.txt"
check "Settings: the Desktop page's Desktop Picture row opens the gallery" \
  "grep -q '<string>MSBWallpaperController</string>' ../statusbar/macstatusbarprefs/Resources/Desktop.plist && grep -q 'MSBWallpaperController.m' ../statusbar/macstatusbarprefs/Makefile"
check "Settings: None first, then Photos, Mac Wallpapers (the folder, Add from Files), iPadOS's" \
  "grep -q '@\"id\": @\"none\", @\"name\": @\"None\"' $P && grep -q '@\"Choose from Photos\"' $P && grep -q 'titles addObject:@\"Mac Wallpapers\"' $P && grep -q '@\"Add from Files\"' $P && grep -q 'titles addObject:@\"iPadOS\"' $P"
check "Settings: Photos through the system's picker only (no library access), the copy made smaller, the one before removed" \
  "grep -q 'PHPickerViewController alloc' $P && ! grep -q -E 'PHPhotoLibrary|PHAsset|requestAuthorization' $P && grep -q 'kCGImageSourceThumbnailMaxPixelSize: @(maxPixel)' $P && grep -q 'hasPrefix:kMSBDWallpaperPhotoPrefix\] && !\[f isEqualToString:keep.lastPathComponent\]' $P && grep -q 'maxPixel = MIN(maxPixel, 2.0 \* need);' $P"
check "Settings: a Photos pick is written even when the page has gone, the copies before removed only after (review 1.8.6 L4)" \
  "grep -q 'else WPWriteChoice(@\"photo\", path, nil);' $P && grep -q '^\t\t\tWPRemoveOldPhotos(path);' $P"
check "Settings: Add from Files is the document picker as a copy, into the folder under a name that replaces nothing" \
  "grep -q 'initForOpeningContentTypes:@\[UTTypeImage\] asCopy:YES' $P && grep -q 'MSBDWallpaperImportName(u.lastPathComponent' $P && grep -q 'copyItemAtPath:u.path toPath:to' $P && ! grep -q -E '[^e]moveItemAtPath|removeItemAtPath:to' $P"
check "a Mac's dynamic wallpaper (several pictures in one HEIC): its primary picture, in SpringBoard and Settings" \
  "grep -q 'CGImageSourceGetPrimaryImageIndex(src)' $D && grep -c 'CGImageSourceGetPrimaryImageIndex(s)' $P | grep -q 2"
check "Settings: the button tiles (Choose from Photos, Add from Files) never reach the thumbnails, and a thumbnail never takes a missing path" \
  "grep -q 'isEqualToString:@\"pick\"\] || \[it\[@\"kind\"\] isEqualToString:@\"add\"\]) {' $P && grep -A1 'static UIImage \*WPThumb(NSString \*src) {' $P | grep -q '!src.length) return nil;'"
check "no pictures shipped: nothing under layout/ is a picture of a wallpaper, no generator" \
  "! find ../layout -iname '*.jpg' -o -iname '*.heic' -o -iname '*.png' | grep -q . && ! test -e make-wallpapers.py"
[ $fails = 0 ] && echo "ALL WIRING PASS" || { echo "WIRING FAILED"; exit 1; }
