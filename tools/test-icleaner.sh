#!/bin/bash
# Mac test of iCleaner in Finder (1.8.5 item 1): the shared rules (common/ICleaner.h, test-icleaner.m) and the wiring -- SpringBoard never starts
# iCleaner (the root helper's launchd job runs it, as a drive's eject); only the official package, only its own program, only `-clean -printresults`;
# the sidebar row only while it is installed and never a place (no path, not in Go); the respring is ours.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -framework CoreFoundation -o "$W/tic" test-icleaner.m
"$W/tic"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
P=../statusbar/ICleanerPanel.h; F=../statusbar/Finder.h; S=../macsettings/sshtoggled/main.m; C=../common/ICleaner.h
check "SpringBoard never starts iCleaner (no spawn and no iCleaner path in Finder's side)" \
  "! grep -n 'posix_spawn\|MSBDRunHelperTimed\|NSTask\|kMSBDICleanBinary, args' $P $F && ! grep -n 'iCleaner.app/iCleaner\|usr/bin/icleaner' $P $F ../statusbar/StatusBar.x"
check "the helper runs exactly iCleaner -clean -printresults, the binary from the shared path, never stopped halfway (no time limit: dpkg may be at work)" \
  "grep -q 'char \*args\[\] = { \"iCleaner\", \"-clean\", \"-printresults\", NULL };' $S && grep -q 'MSBDRunHelperTimed(kMSBDICleanBinary, args, kMSBDICleanTimeout, &out, &status, &late)' $S && [ \$(grep -c 'kMSBDICleanBinary' $S) -ge 3 ] && grep -q 'static const double kMSBDICleanTimeout = 0.0;' $C"
check "the official package only (the shared name; no other iCleaner package named in the new code)" \
  "grep -q 'kMSBDICleanPackage      @\"com.exile90.icleanerpro\"' $C && ! grep -n 'cypwn' $C $P && ! awk '/---- 6. iCleaner in Finder/,/^#if DEBUG\n\/\/ --dry-run/' $S | grep -q cypwn"
check "the helper checks the package, the file list and a regular root file before it runs anything" \
  "grep -q 'MSBDPackageOnDisk(DpkgStatus(), kMSBDICleanPackage)' $S && grep -q 'containsObject:@kMSBDICleanBinary' $S && grep -q 'lstat(kMSBDICleanBinary, &st) != 0 || !S_ISREG(st.st_mode) || st.st_uid != 0' $S"
check "the helper takes the request away at once, accepts only MSBDICleanRequestFrom's, runs one clean at a time" \
  "awk '/^static void ICleanRequest/,/^}/' $S | awk '/if \(gICleanBusy\)/{b=1} b && /CFPreferencesSetValue\(key, NULL/{t=1} t && /MSBDICleanRequestFrom/{print \"ok\"; exit}' | grep -q ok"
check "the helper listens for Finder and answers a request left at its start" \
  "grep -q 'notify_register_dispatch(kMSBDICleanRequestName' $S && grep -q 'ICleanRequest(@\"daemon start\")' $S"
check "the dry run is debug-only and needs a root-owned flag (no clean of a test iPad)" \
  "awk '/^static NSData \*ICleanDryRunOutput/{n++} END{exit n==2?0:1}' $S && grep -q 'lstat(ESTATEDIR \"/iclean-dryrun\", &st) != 0 || !S_ISREG(st.st_mode) || st.st_uid != 0' $S && grep -q 'static NSData \*ICleanDryRunOutput(void) { return nil; }' $S"
check "Finder takes only root's own answer file, and only the answer with its request's id" \
  "grep -q 'S_ISREG(st.st_mode) || st.st_uid != 0' $P && grep -q 'MSBDEjectAnswerLine(\[NSData dataWithContentsOfFile:@kMSBDICleanAnswerFile\], rid)' $P"
check "the row: only while iCleaner Pro is installed, in the window's sidebar only (not DMFinderSidebar, so not in Go), with no path" \
  "grep -q 'if (!DMICleanAvailable() || !s.count) return s;' $P && grep -q '@\"tool\": @\"iclean\"}' $P && [ \$(grep -c '_places = DMFinderSidebarForWindow();' $F) = 2 ] && ! grep -q 'iclean' <(awk '/^static NSArray<NSDictionary \*> \*DMFinderSidebar\(void\)/,/^}/' $F)"
check "the row's tap opens the panel; a tool row is never gone to or dropped onto as a place" \
  "grep -q 'if (\[r\[@\"tool\"\] isEqualToString:@\"iclean\"\]) { DMICleanOpenPanel(); return; }' $F && grep -q 'return rows\[r\]\[@\"p\"\] ?: self.path;' $F"
check "the panel says a clean can remove packages (iCleaner's unused dependencies) and Finder's give-up line says it is still cleaning" \
  "grep -q 'and packages nothing needs if you turned that on in iCleaner' $P && grep -q 'iCleaner is still cleaning. It finishes on its own' $C && grep -q 'DMICleanShowPanel(\[line isEqualToString:kMSBDICleanNoAnswerLine\] ? 2 : 3, err, NO);' $P"
check "the respring is ours (Respring in the Apple menu), never iCleaner's -respring" \
  "grep -q 'DMRespringChecked();' $P && ! grep -n '\"-respring\"\|-autorespring' $P $S"
[ $fails = 0 ] && echo "test-icleaner: all PASS" || { echo "test-icleaner: FAILED"; exit 1; }
