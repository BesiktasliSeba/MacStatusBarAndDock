#!/bin/bash
# Mac test of Quick Look in Finder (1.8.4.2 item 2): the viewer for a file (common/PreviewPick.h, test-previewpick.c) and the wiring in
# SpringBoard (statusbar/Finder.h, DMQuickLookWindow): iPadOS's QLPreviewController inside our own Quick Look window, a child view controller of
# the native layer's root (never presented), QuickLook.framework opened at its first use (not linked, never loaded for a thumbnail), our own
# viewers kept for pictures, PDFs, media and text.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -O0 -Wall -o "$W/tpp" test-previewpick.c && "$W/tpp" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }
m() { awk -v h="$2" '!p && index($0, h) == 1 {p=1} p {print} p && /^}/ {exit}' "$1"; }
H=../statusbar/Finder.h
check "Finder includes the rule and QuickLook's declarations" "grep -q '#include \"../common/PreviewPick.h\"' $H && grep -q '#import <QuickLook/QuickLook.h>' $H"
check "QuickLook is opened at its first use, by itself (a PDF's thumbnail opens PDFKit, not QuickLook), and not linked" \
  "fn $H 'static Class DMFinderQLClass(' | grep -q 'dlopen(\"/System/Library/Frameworks/QuickLook.framework/QuickLook\", RTLD_LAZY)' \
   && ! fn $H 'static Class DMFinderClass(' | grep -q QuickLook && ! grep -q 'QuickLook' ../statusbar/Makefile \
   && ! grep -q '\[QLPreviewController ' $H && ! grep -q '\[QLPreviewController class\]' $H"
check "  ... asked only for a file it may show (pictures, PDFs, media and text never load it)" \
  "fn $H 'static unsigned DMQLFlags(' | grep -q 'Class qc = mayUse ? DMFinderQLClass() : Nil;' && fn $H 'static unsigned DMQLFlags(' | grep -q '\[qc canPreviewItem:\[NSURL fileURLWithPath:path\]\]'"
check "the viewer is the rule's" "m $H '- (void)dm_show:(NSString *)path extra:(unsigned)extra {' | grep -q 'int pick = MSBDPreviewPick(flags);'"
check "  ... ours for pictures, PDFs, media, text (as before), the icon for the rest" \
  "m $H '- (void)dm_show:(NSString *)path extra:(unsigned)extra {' | grep -q '} else if (pick == MSBD_PV_IMAGE) {' \
   && m $H '- (void)dm_show:(NSString *)path extra:(unsigned)extra {' | grep -q '} else if (pick == MSBD_PV_PDF && DMFinderClass(@\"PDFView\")) {' \
   && m $H '- (void)dm_show:(NSString *)path extra:(unsigned)extra {' | grep -q '} else if (pick == MSBD_PV_MEDIA && DMFinderClass(@\"AVPlayerViewController\")) {' \
   && m $H '- (void)dm_show:(NSString *)path extra:(unsigned)extra {' | grep -q '} else if (pick == MSBD_PV_TEXT) {'"
check "  ... Quick Look's viewer; if it can't be shown, ours as before" \
  "m $H '- (void)dm_show:(NSString *)path extra:(unsigned)extra {' | grep -q 'if (pick == MSBD_PV_QUICKLOOK) { v = \[self dm_quickLookView:path\]; if (!v) pick = MSBDPreviewPick((flags & ~MSBD_PVF_QL) | MSBD_PVF_QL_OFF); }'"
check "  ... a picture ImageIO can't read: shown again, Quick Look's if it can" \
  "m $H '- (void)dm_show:(NSString *)path extra:(unsigned)extra {' | grep -q 'dm_show:path extra:MSBD_PVF_UNREADABLE\]'"
check "Quick Look's viewer: a child of the layer's root view controller, its view in our window; never presented" \
  "m $H '- (UIView *)dm_quickLookView:(NSString *)path {' | grep -q '\[root addChildViewController:_ql\];' \
   && m $H '- (UIView *)dm_quickLookView:(NSString *)path {' | grep -q '\[self.contentView addSubview:_ql.view\];' \
   && m $H '- (UIView *)dm_quickLookView:(NSString *)path {' | grep -q '\[_ql didMoveToParentViewController:root\];' \
   && m $H '- (UIView *)dm_quickLookView:(NSString *)path {' | grep -q 'UIViewController \*root = gNativeLayer.rootViewController;' \
   && ! grep -q 'presentViewController:_ql' $H"
check "  ... its items from our data source; out of the hierarchy when the window closes" \
  "grep -q '@interface DMQuickLookWindow : DMNativeWindow <QLPreviewControllerDataSource' $H && grep -q '^- (NSInteger)numberOfPreviewItemsInPreviewController:' $H \
   && m $H '- (void)dm_quickLookRemove {' | grep -q '\[_ql removeFromParentViewController\];' && grep -q '^- (void)close { \[_player pause\]; _player = nil; DMFinderSizeCancel(self, nil); \[self dm_quickLookRemove\]; \[super close\]; }' $H"
check "a folder in Quick Look: its icon, kind and size (worked out as in Get Info)" \
  "m $H '- (void)dm_show:(NSString *)path extra:(unsigned)extra {' | grep -q 'DMFinderSizeAsk(it.path, self, YES);' && fn $H 'static void DMFinderSizeDone(' | grep -q '\[(DMQuickLookWindow \*)w dm_folderSizeDone:path state:state\];'"
check "the debug switches are compiled into debug builds only" \
  "[ \"\$(fn $H 'static unsigned DMQLFlags(' | awk '/^#if DEBUG/{d=1} /msb-ql(off|all)/{print d+0} /^#endif/{d=0}' | sort -u | tr -d '\n')\" = 1 ]"
check "no em dash in the feature's files" "! grep -q \$'\\xe2\\x80\\x94' ../common/PreviewPick.h test-previewpick.c test-previewpick.sh && ! m $H '- (void)dm_show:(NSString *)path extra:(unsigned)extra {' | grep -q \$'\\xe2\\x80\\x94'"
[ $fails = 0 ] && echo "test-previewpick: all checks pass" || { echo "test-previewpick: checks FAILED"; exit 1; }
