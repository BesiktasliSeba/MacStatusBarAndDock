#!/bin/bash
# Mac test of Share for an app (1.7.7 item 7, KT: an Applications row -- any .app -- shares as an .ipa): statusbar/FinderIPA.h's name, staged name, types, layout
# and FairPlay check (test-finderipa.m, with an iOS executable from the real linker when an iOS SDK is here), the .ipa that Foundation's zip makes of the
# staged Payload folder (listed: Payload/<Name>.app at its root, permissions kept, nothing else), then the wiring as built: the hand name and type,
# the stage path (the one zip, its size rules), the App Store line before the hand-over, the menus, the app bridge's type.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -framework UniformTypeIdentifiers -o "$W/tfi" test-finderipa.m
SDK=$(ls -d "$HOME"/theos/sdks/iPhoneOS*.sdk 2>/dev/null | tail -1)
if [ -n "$SDK" ] && printf 'int main(void) { return 0; }\n' > "$W/m.c" && clang -target arm64-apple-ios15.0 -isysroot "$SDK" -o "$W/ios-exe" "$W/m.c" 2>/dev/null; then export IOS_EXE="$W/ios-exe"; fi
IPA_OUT="$W/Fix It 1.2.ipa" "$W/tfi"
F=../statusbar/Finder.h
I=../statusbar/FinderIPA.h
D=../statusbar/Desktop.h
B=../appbridge/AppBridge.x
fails=0
EMDASH=$(printf '\342\200\224')   # (the em dash, made from its bytes: public files carry none)
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$F"; }
Z="$W/Fix It 1.2.ipa"
LIST=$(zipinfo "$Z" 2>/dev/null | grep -E '^[-dl]' || true)
check "the .ipa's root is Payload/<Name>.app: every entry under Payload/Fix.app/" \
  "[ -n \"\$LIST\" ] && ! zipinfo -1 \"\$Z\" | grep -v '^Payload/Fix.app/'"
check "  ... every file of the bundle in it (6), and nothing else -- no __MACOSX, not the installer's files beside the bundle" \
  "[ \$(zipinfo -1 \"\$Z\" | grep -vc '/\$') = 6 ] && ! zipinfo -1 \"\$Z\" | grep -q -e __MACOSX -e iTunesMetadata -e BundleMetadata && zipinfo -1 \"\$Z\" | grep -qx 'Payload/Fix.app/SC_Info/Fix.sinf'"
check "  ... permissions kept: the executable and a framework's binary 755, a read-only file 444, the rest 644" \
  "echo \"\$LIST\" | grep -q '^-rwxr-xr-x .* Payload/Fix.app/Fix\$' && echo \"\$LIST\" | grep -q '^-rwxr-xr-x .* Payload/Fix.app/Frameworks/A.framework/A\$' && echo \"\$LIST\" | grep -q '^-r--r--r-- .* Payload/Fix.app/Base.lproj/ro.strings\$' && echo \"\$LIST\" | grep -q '^-rw-r--r-- .* Payload/Fix.app/Info.plist\$'"
check "  ... and it unzips as an app: Payload/Fix.app/Info.plist names the executable that is there" \
  "mkdir \"\$W/u\" && (cd \"\$W/u\" && unzip -q \"\$Z\") && [ \"\$(plutil -extract CFBundleExecutable raw -o - \"\$W/u/Payload/Fix.app/Info.plist\")\" = Fix ] && [ -x \"\$W/u/Payload/Fix.app/Fix\" ]"
check "Finder.h includes FinderIPA.h" "grep -q '^#include \"FinderIPA.h\"' $F"
check "an app is an Applications row or any .app folder (Finder's own rule for Show Package Contents)" \
  "grep -q '^static BOOL DMFDIsApp(DMFinderItem \*it) { return it.dir && (it.app.length || \[it.name hasSuffix:@\".app\"\]); }' $F"
check "its hand name is the .ipa's: the app's shown name (LaunchServices', for an installed bundle id only), its version" \
  "fn 'static NSString *DMFDIPAName(DMFinderItem *it) {' | grep -q 'NSString \*shown = bid.length && DMAppInstalled(bid) ? DMCall(DMProxyForBundle(bid), @\"localizedName\") : nil;' && fn 'static NSString *DMFDIPAName(DMFinderItem *it) {' | grep -q 'return DMFinderIPAFileName(DMFinderIPAAppName(info, app, shown), DMFinderIPAVersion(info));' && grep -q 'static NSString \*DMFDHandName(DMFinderItem \*it) { return DMFDIsApp(it) ? DMFDIPAName(it) : it.dir ? \[it.name stringByAppendingPathExtension:@\"zip\"\] : it.name; }' $F"
check "its type: com.apple.itunes.ipa when this iPad declares it, else what \".ipa\" is here (FinderIPA.h's list, its first)" \
  "fn 'static NSString *DMFDUTI(DMFinderItem *it) {' | grep -q 'if (DMFDIsApp(it)) return DMFinderIPATypes().firstObject;' && grep -q 'UTType \*ipa = \[UTType typeWithIdentifier:@\"com.apple.itunes.ipa\"\];' $I && grep -q 'NSString \*own = (ipa.isDeclared ? ipa : \[UTType typeWithFilenameExtension:@\"ipa\"\]).identifier ?: UTTypeData.identifier;' $I"
STAGE=$(fn 'static NSDictionary *DMFDStageItem(DMFDrag *d, DMFinderItem *it, NSString *dir, NSString **why) {')
check "the stage: an app laid out as Payload/<Name>.app, then zipped by the one zip a folder gets (Finder has a single zip, NSFileCoordinator's)" \
  "echo \"\$STAGE\" | grep -q 'NSString \*what = app ? DMFinderIPAStage(src, zdir, &err) : src;' && echo \"\$STAGE\" | grep -q 'coordinateReadingItemAtURL:\[NSURL fileURLWithPath:what\] options:NSFileCoordinatorReadingForUploading' && [ \$(grep -c 'NSFileCoordinatorReadingForUploading' $F) = 1 ]"
check "  ... room for the copy too when the app can't be cloned (another volume: /Applications), the iPad never filled (200 MB kept)" \
  "echo \"\$STAGE\" | grep -q 'BOOL clone = !app || DMFinderIPASameVolume(src, zdir);' && echo \"\$STAGE\" | grep -q '(unsigned long long)size \* (clone ? 1 : 2) + reserve > room' && echo \"\$STAGE\" | grep -q 'const unsigned long long reserve = 200ULL \* 1024 \* 1024;'"
check "  ... a name already staged gets a free one (two copies of an app make one .ipa name: FinderIPA.h's, tried above)" \
  "echo \"\$STAGE\" | grep -q 'NSString \*dst = DMFinderStagedPath(dir, name);' && echo \"\$STAGE\" | grep -q 'name = dst.lastPathComponent;' && ! echo \"\$STAGE\" | grep -q 'for (int n = 2;'"
check "the size rules are the folder's, unchanged: asks above 200 MB, refused above 2 GB" \
  "grep -q 'static const unsigned long long kFDZipAsk = 200ULL \* 1024 \* 1024, kFDZipCap = 2048ULL \* 1024 \* 1024;' $F"
ASK=$(fn 'static void DMFDAskFirst(DMFDrag *d, DMFinderWindow *w, void (^go)(void), void (^stop)(NSString *why)) {')
check "before the hand-over: folders and apps counted against the cap and the ask, apps checked for FairPlay (read only)" \
  "echo \"\$ASK\" | grep -q 'DMFDFolderSize(p, kFDZipCap + 1)' && echo \"\$ASK\" | grep -q 'if (DMFinderIPAEncrypted(a) == 1) store++;' && echo \"\$ASK\" | grep -q 'if (total > kFDZipCap)' && echo \"\$ASK\" | grep -q 'if (total <= kFDZipAsk && !storeTitle) { go(); return; }'"
check "  ... the App Store line, plain (KT's words): \"This app is from the App Store. Its copy only opens on iPads signed in with the same Apple ID.\"" \
  "echo \"\$ASK\" | grep -q '@\"This app is from the App Store.\"' && echo \"\$ASK\" | grep -q '@\"Its copy only opens on iPads signed in with the same Apple ID.\"' && ! echo \"\$ASK\" | grep -q \"\$EMDASH\""
check "  ... one sheet at most: the line alone (Continue / Cancel), or inside the size question" \
  "echo \"\$ASK\" | grep -q 'sheetTitle:storeTitle message:storeLine field:nil action:@\"Continue\"' && echo \"\$ASK\" | grep -q 'message:storeTitle ? \[NSString stringWithFormat:@\"%@ %@ %@\", how, storeTitle, storeLine\] : how' && [ \$(echo \"\$ASK\" | grep -c 'sheetTitle:') = 2 ]"
check "a drop asks there as before; Share asks before it opens the app (its window would cover the sheet) and the hand-over doesn't ask again" \
  "fn 'static void DMFDHandOver(' | grep -q 'if (!folders || d.asked) { stage(); return; }' && fn 'static void DMFDHandOver(' | grep -q 'DMFDAskFirst(d, w, stage, fail);' && fn 'static void DMFinderShareTo(' | grep -q 'DMFDAskFirst(d, from, ^{ d.asked = YES; a(); }, ^(NSString \*why) {'"
check "  ... after a stop that said why (or a Cancel), Share adds no \"didn't take the file\" sheet over it" \
  "fn 'static void DMFDHandOver(' | grep -q 'd.told = why.length && !\[why hasPrefix:@\"the app\"\];' && fn 'static void DMFinderShareTo(' | grep -q 'if (!ok && !d.told) \[wfrom sheetTitle:'"
check "Share keeps nothing once it is over: its wait for the app's window is held by its pending retry only, the window weakly -- a drag begun during the count (neither go nor stop runs) or a question gone unanswered left the record, its items and the window held for good (1.7.7 review N1)" \
  "fn 'static void DMFinderShareTo(' | grep -q '__weak DMFinderWindow \*wfrom = from;' && fn 'static void DMFinderShareTo(' | grep -q '__block int tries = 0; __block __weak void (^again)(void) = nil;' && fn 'static void DMFinderShareTo(' | grep -q 'void (^n)(void) = again;' && ! fn 'static void DMFinderShareTo(' | grep -q 'attempt' && [ \$(fn 'static void DMFinderShareTo(' | grep -c '\[from sheetTitle:') = 0 ] && grep -q '            if (d.finished) return;' $F"
check "the menus: Share for a file or an app, alone or several selected; a plain folder still has none in Finder's menus" \
  "grep -q 'if ((!it.dir || DMFDIsApp(it)) && !it.cloud) {' $F && grep -q 'files = files && (!x.dir || DMFDIsApp(x)) && !x.cloud;' $F && [ \$(grep -c 'DMFinderShareTo(@\[it\], b, w)\|DMFinderShareTo(many, b, w)' $F) = 2 ]"
check "the desktop's menu shares every icon as before (an .app icon now as an .ipa: the same hand-over)" \
  "grep -q 'DMFinderShareTo(sel, b, DMFinderOps());' $D"
check "nothing is decrypted: the executable is only opened for reading, no cryptid written, no mapping of it" \
  "grep -q 'open(path.fileSystemRepresentation, O_RDONLY | O_CLOEXEC)' $I && ! grep -n 'O_RDWR\|O_WRONLY\|mmap\|mremap_encrypted\|cryptid = \|pwrite\|fwrite' $I"
check "an app's entry names its types: the .ipa's own, then a zip named .ipa (Files takes archives, names the file by the type); both entry forms carry them" \
  "grep -q 'static NSArray<NSString \*> \*DMFDUTIs(DMFinderItem \*it) { return DMFDIsApp(it) ? DMFinderIPATypes() : @\[DMFDUTI(it)\]; }' $F && grep -q '@\"uti\": DMFDUTI(it), @\"utis\": DMFDUTIs(it)}\];' $F && grep -q 'return @{@\"path\": dst, @\"name\": name, @\"uti\": DMFDUTI(it), @\"utis\": DMFDUTIs(it)};' $F"
check "the app bridge offers a staged file under every type SpringBoard named too (what the extension gives first); an older sender's one type still works" \
  "grep -q 'for (id t in \[e\[@\"utis\"\] isKindOfClass:\[NSArray class\]\] ? e\[@\"utis\"\] : (uti ? @\[uti\] : @\[\]))' $B && grep -q 'for (NSString \*t in utis) if (ip && !\[ip.registeredTypeIdentifiers containsObject:t\])' $B && grep -q 'registerFileRepresentationForTypeIdentifier:t fileOptions:0 visibility:NSItemProviderRepresentationVisibilityAll loadHandler:^NSProgress \*(void (^c)(NSURL \*, BOOL, NSError \*)) { c(url, NO, nil); return nil; }\];' $B"
check "  ... and Share's fallback never picks a one-line text field (Files' search field took an .ipa's URL as text in an empty folder)" \
  "grep -q 'BOOL field = \[v isKindOfClass:\[UITextField class\]\];' $B && grep -q 'if (field || !\[ia isKindOfClass:\[UIDropInteraction class\]\]) continue;' $B"
check "a crash in FinderIPA.h is Finder's (its functions are DMFinder... -- the symbol rule)" \
  "grep -q '^sym MacStatusBarCore ^_?DM(Finder|Native|OpenFinder|OpenNativeWindow)\\[A-Z\\] finder' crashmap-rules.txt && [ \$(grep -c '^static' $I) -gt 0 ] && ! grep '^static' $I | grep -v '^static [^(]*[ *]DMFinder[A-Za-z]*('"
check "the test machinery (selectmany, menu, shareops, ipainfo): debug builds only" \
  "awk '/^#if DEBUG/{d=1} /^#endif/{d=0} /else if \(\[act isEqualToString:@\"(selectmany|menu|shareops|ipainfo)\"\]\)/{n++; if (!d) bad=1} END{exit !(n == 4 && !bad)}' $F"
[ $fails = 0 ] && echo "test-finderipa: wiring checks pass" || { echo "test-finderipa: wiring checks FAILED"; exit 1; }
