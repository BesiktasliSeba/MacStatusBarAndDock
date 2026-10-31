#!/bin/bash
# Mac test of a drive's eject and name (1.7.3): the shared rules (common/DriveEject.h, test-driveeject.m) and the wiring -- SpringBoard never starts
# the eject helper (iPadOS 18 refuses that spawn): every way to eject asks the root helper's launchd job, which checks the request and the volume
# itself and runs msbdeject with that one argument; Finder takes only root's answer to its own request; a drive is named by its volume's label.
# MSBD_LIVE_DA=1: also ejecthelper/DAEject.h (the 15 eject) against a FAT disk image of its own (made, attached hidden, ejected, removed).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -framework CoreFoundation -o "$W/tde" test-driveeject.m
"$W/tde"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
D=../statusbar/DriveEject.h; T=../statusbar/DockTrash.h; F=../statusbar/Finder.h; S=../macsettings/sshtoggled/main.m; E=../ejecthelper/main.m
check "SpringBoard never starts a process for the eject (no spawn in Finder's, the bin's or the eject's code)" \
  "! grep -n 'posix_spawn\|MSBDRunHelperTimed\|NSTask' $D $T $F && ! grep -n 'kMSBDEjectHelperPath\|usr/libexec/msbdeject' $D $T $F ../statusbar/StatusBar.x"
check "every way to eject goes through DMDriveEject: the bin, the sidebar's button, its VoiceOver action, its menu, a list item's menu" \
  "grep -q 'DMDriveEject(d\[@\"p\"\], d\[@\"t\"\]);' $T && [ \$(grep -c 'DMDriveEject(root, name)' $F) -ge 4 ]"
check "File > Eject (Command-E): the File menu's row, the key command and the key itself" \
  "grep -q 'items = DMDriveEjectMenuWith(items, f);' ../statusbar/StatusBar.x && grep -q 'if (!DMDriveCanEject()) return items;' $D && grep -q 'K(@\"e\", UIKeyModifierCommand, @\"dm_keyEject:\")' $F && grep -q 'case UIKeyboardHIDUsageKeyboardE: if (cmd) { DMDriveEjectFromWindow(self); return YES; }' $F"
check "Eject is offered only where this iPadOS can eject (button, menus, File > Eject, the bin); 15's DiskArbitration eject waits for its device test" \
  "grep -q 'static const BOOL kDMDriveEject15Ready = NO;' $D && grep -q 'static BOOL DMDockTrashCanEject(void) { return DMDriveCanEject(); }' $T && grep -q 'DMDriveCanEject()) {' $F && grep -q 'if (!f || !DMDriveCanEject()) return @\[\];' $D"
check "Finder asks: the request in our preferences, then the post; the helper looked for first, the answer waited for with a limit" \
  "awk '/^static NSString \*DMDriveEjectAsk/,/^}/' $D | awk '/MSBDEjectHelperRunning/{h=1} h && /notify_register_dispatch\(kMSBDEjectAnswerName/{r=1} r && /CFPreferencesSetValue\(key, \(__bridge CFDictionaryRef\)req/{w=1} w && /notify_post\(kMSBDEjectRequestName\)/{p=1} p && /kMSBDEjectWait/{print \"ok\"; exit}' | grep -q ok"
check "  ... and looks at the answer file itself every half second meanwhile (a lost post costs half a second, not the whole wait)" \
  "awk '/^static NSString \*DMDriveEjectAsk/,/^}/' $D | awk '/dispatch_semaphore_wait\(got, dispatch_time\(DISPATCH_TIME_NOW, \(int64_t\)\(0.5 \* NSEC_PER_SEC\)\)\)/{w=1} w && /polled = DMDriveEjectReadAnswer\(rid\);/{print \"ok\"; exit}' | grep -q ok"
check "Finder takes only root's own answer file, and only the answer with its request's id" \
  "grep -q 'S_ISREG(st.st_mode) || st.st_uid != 0' $D && grep -q 'MSBDEjectAnswerLine(\[NSData dataWithContentsOfFile:@kMSBDEjectAnswerFile\], rid)' $D"
check "the root helper takes the eject request: its post, its pid published for Finder, a request left at its start answered or dropped" \
  "grep -q 'notify_register_dispatch(kMSBDEjectRequestName' $S && grep -q 'notify_set_state(alive, (uint64_t)getpid())' $S && grep -q 'EjectRequest(@\"daemon start\")' $S"
check "  ... reads the request, takes it away before anything else, accepts only MSBDEjectRequestFrom's" \
  "awk '/^static void EjectRequest/,/^}/' $S | awk '/CFPreferencesCopyValue\(key/{c=1} c && /CFPreferencesSetValue\(key, NULL/{d=1} d && /MSBDEjectRequestFrom\(/{print \"ok\"; exit}' | grep -q ok"
check "  ... checks the volume against the mount table itself and runs msbdeject with that one argument, with a time limit" \
  "grep -q 'NSString \*mp = good ? MSBDEjectVolumeAt(vol.fileSystemRepresentation, &from, &no) : nil;' $S && grep -q 'const char \*arg = mp ? mp.fileSystemRepresentation : \"/var/mobile\";' $S && grep -q 'char \*args\[\] = { \"msbdeject\", dry ? \"--check\" : (char \*)arg, dry ? (char \*)arg : NULL, NULL };' $S && grep -q 'if (!mp && !dry) line = ' $S && grep -q 'if (!good && !dry) {' $S && grep -q 'MSBDRunHelperTimed(kMSBDEjectHelperPath, args, kMSBDEjectHelperTimeout' $S"
check "  ... one at a time, never starting over (a cfprefsd restart) while an eject runs" \
  "grep -q 'if (gEjectBusy) { gEjectAgain = YES; return; }' $S && grep -q 'if (gEjectBusy) return;   // (an eject is under way' $S"
check "  ... answers in root's folder: a new file renamed in place, then the post" \
  "awk '/^static void EjectWriteAnswer/,/^}/' $S | awk '/mkstemp/{m=1} m && /rename\(tmp, kMSBDEjectAnswerFile\)/{r=1} r && /notify_post\(kMSBDEjectAnswerName\)/{print \"ok\"; exit}' | grep -q ok"
check "  ... the test run (msbdeject --check, nothing ejected) only in debug builds, only with root's flag" \
  "awk '/^#if DEBUG/{d=1} d && /static BOOL EjectDryRun\(void\) { struct stat st;/{print \"ok\"; exit} /^#endif/{d=0}' $S | grep -q ok && grep -q 'static BOOL EjectDryRun(void) { return NO; }' $S"
check "msbdeject checks the folder with the same rules (no copy of its own) and ejects with DiskArbitration where StorageKit is missing" \
  "grep -q 'MSBDEjectVolumeAt(arg, &from, &why)' $E && grep -q 'if (!m) return EjectWithoutStorageKit(vol, from);' $E && ! grep -q 'static NSString \*CheckedVolume' $E"
check "  ... DiskArbitration's unmount is never forced, and the disk is never let go under a mounted volume" \
  "! grep -n '0x00080000\|kDADiskUnmountOptionForce *=\|MNT_FORCE' ../ejecthelper/DAEject.h && grep -q 'if (MSBDDAStillMounted(mountPoint)) { snprintf(r.why, sizeof r.why, \"it is still mounted\"); goto out; }' ../ejecthelper/DAEject.h"
check "  ... no DiskArbitration answer can land after the eject has returned: off the session's queue, the queue drained, then released (its wait lives on the stack)" \
  "awk '/^static inline MSBDDAResult MSBDDAEject/,/^}/' ../ejecthelper/DAEject.h | awk '/^out:/{o=1} o && /f.setQueue\(s, NULL\);/{u=1} u && /dispatch_sync\(q, \^\{\}\);/{d=1} d && /CFRelease\(s\);/{print \"ok\"; exit} o && /CFRelease/ && !d{exit}' | grep -q ok"
check "a drive is named by its volume's label (read once per mount), its folder's item and the window's title follow" \
  "grep -q 'NSString \*name = MSBDDriveName(on, from, DMFinderDriveLabel(&fs\[i\])) ?: on.lastPathComponent;' $F && grep -q 'if (inLiveFiles && it.dir) { NSDictionary \*dv = DMFinderDriveInfo(it.path); if (dv) it.display = dv\[@\"t\"\]; }' $F && grep -q 'DMFinderDriveNameFor(root)' $F"
check "  ... the label is never read on the main thread (a slow drive's server must not hold SpringBoard): a queue reads it, then the drives are looked at again" \
  "grep -q 'if (!\[NSThread isMainThread\]) return DMFinderDriveLabelRead(key, mountPoint, failed);' $F && awk '/^static NSString \*DMFinderDriveLabel\(const struct statfs/,/^}/' $F | awk '/dispatch_async\(dispatch_get_global_queue/{q=1} q && /DMFinderDriveLabelRead\(key, mountPoint, failed\);/{r=1} r && /DMFinderDrivesCheck\(@\"a drive.s name read\"\)/{print \"ok\"; exit}' | grep -q ok"
check "a crash in the eject's code turns Finder off, not the whole status bar" "grep -q '^file MacStatusBarCore ^DriveEject\\\\.h\$ finder' crashmap-rules.txt"
check "the answer file goes at removal" "grep -q 'rm -f \"\$S/eject-answer\" \"\$S\"/.eject-answer.\* \"\$S/eject-dryrun\"' ../layout/DEBIAN/postrm"
if [ "${MSBD_LIVE_DA:-0}" = 1 ]; then   # (on this Mac: a FAT image of our own, attached hidden at a folder named like 18's UUID mounts -- macOS 15 mounts it with FSKit)
    # M: the folder as msbdeject is handed it (the /var spelling of a link, as Finder's /var/mobile/... on the iPad); MR: the kernel's (/private/var)
    M="$W/5D3A6E1C-0B7F-4C2B-9E61-2A8F0C1D4E77"; MR="$(cd "$W" && pwd -P)/5D3A6E1C-0B7F-4C2B-9E61-2A8F0C1D4E77"
    hdiutil create -quiet -size 8m -fs "MS-DOS FAT16" -volname MSBDTEST -layout MBRSPUD "$W/fat.dmg"
    mkdir -p "$M"; hdiutil attach -quiet -nobrowse -mountpoint "$MR" "$W/fat.dmg"
    trap 'hdiutil detach -force "$MR" >/dev/null 2>&1 || true; rm -rf "$W"' EXIT
    DEV=$(mount | grep " on $MR " | sed -E 's|^/dev/(disk[0-9]+s[0-9]+) .*|\1|')
    check "live: the drive's name is its volume's label (\"MSBDTEST\"), not its UUID folder" "[ \"\$(\"$W/tde\" --name \"$M\")\" = MSBDTEST ]"
    check "live: DiskArbitration's eject -- busy with a file open (nothing unmounted), then unmounted and let go" "[ -n \"$DEV\" ] && \"$W/tde\" --da \"$DEV\" \"$M\""
    check "live: the image is gone from the mount table" "! mount | grep -q \" on $MR \""
fi
[ $fails = 0 ] && echo "test-driveeject: all wiring checks pass" || { echo "test-driveeject: wiring checks FAILED"; exit 1; }
