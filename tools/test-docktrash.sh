#!/bin/bash
# Mac test of the Dock's Trash (1.7.0): the shared rules (common/DockTrash.h, test-docktrash.m), and the wiring in the sources -- the switch in the
# Dock's settings (off by default) and its crash-guard rule, both libraries using the shared names, the drag code asking the bin first.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tdt" test-docktrash.m
"$W/tdt"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
P=../dock/dockmagnificationprefs/Resources/Root.plist
check "Settings > Dock > Show Trash in Dock, off by default" \
  "python3 -c \"import plistlib,sys; it=[x for x in plistlib.load(open('$P','rb'))['items'] if x.get('key')=='showTrash']; sys.exit(0 if len(it)==1 and it[0].get('default') is False and it[0].get('label')=='Show Trash in Dock' and it[0].get('PostNotification')=='com.besiktasliseba.dockmagnification/prefsChanged' else 1)\""
check "the Dock reads showTrash, off unless set" "grep -q 'DMCopyPref(CFSTR(\"showTrash\"))' ../dock/Dock.x && grep -q 'BOOL trash = NO;' ../dock/Dock.x"
check "Finder reads the same switch" "grep -q 'CFSTR(\"showTrash\")' ../statusbar/DockTrash.h"
check "the crash guard turns the Trash off (not the whole Dock or Finder)" \
  "grep -q '^target showTrash pref com.besiktasliseba.dockmagnification showTrash 0 0 ' crashmap-rules.txt && grep -q '^file DockMagnification ^TrashIcon' crashmap-rules.txt && grep -q '^file MacStatusBarCore ^DockTrash' crashmap-rules.txt"
check "no raw Trash notification names outside the shared header" \
  "! grep -n 'finder\.trash' ../dock/*.m ../dock/*.x ../statusbar/*.h ../statusbar/*.x | grep -v 'kMSBDTrash'"
check "Finder's drag asks the bin first (move and drop)" "grep -q 'UIView \*bin = DMFDTrashIconAt(sp);' ../statusbar/Finder.h && grep -q 'if (DMFDTrashIconAt(sp)) {' ../statusbar/Finder.h"
check "the bin's look follows a drag of drives from its start to its end" "grep -q 'DMFDTrashSetEject(YES)' ../statusbar/Finder.h && grep -q 'DMFDTrashSetEject(NO)' ../statusbar/Finder.h"
check "the eject helper is built, entitled and checked by the gate" \
  "grep -q 'SUBPROJECTS += ejecthelper' ../Makefile && grep -q 'com.apple.private.storagekitd.statuschange' ../ejecthelper/entitlements.plist && grep -q 'usr/libexec/msbdeject' verify-release.sh"
check "Empty Trash from the Dock is Finder's own question" "grep -q '\[DMFinderOps() emptyTrash\]' ../statusbar/DockTrash.h"
check "Empty Trash from the Dock counts the Trashes off the main thread, then asks on it (a slow drive held SpringBoard)" \
  "awk '/^static void DMDockTrashEmpty/,/^}/' ../statusbar/DockTrash.h | awk '/dispatch_get_global_queue/{q=1} q && /DMDockTrashCountNow\(\)/{c=1} c && /dispatch_get_main_queue/{m=1} m && /emptyTrash\]/{print \"ok\"; exit}' | grep -q ok"
check "Finder spawns the eject helper only through the shared, Mac-tested spawn (only the descriptors it uses)" \
  "grep -q 'MSBDTrashRunHelper(kDockTrashEjectHelper.fileSystemRepresentation, argv, &out, &status)' ../statusbar/DockTrash.h && ! grep -q 'posix_spawn' ../statusbar/DockTrash.h && grep -q 'POSIX_SPAWN_CLOEXEC_DEFAULT' ../common/DockTrash.h"
check "the helper asks StorageKit for a disk's whole disk only where it has that call" \
  "[ \$(grep -c 'wholeDiskForDisk:' ../ejecthelper/main.m) = 1 ] && grep -q 'return disk && \[m respondsToSelector:s\]' ../ejecthelper/main.m"
check "Eject only where this iPadOS can eject (StorageKit, 16 on): the drag's look, the drop's rule and the eject itself" \
  "grep -q '_dyld_shared_cache_contains_path(sk) || access(sk, F_OK) == 0' ../statusbar/DockTrash.h && grep -q 'MSBDTrashDropFor(it, n, DMDockTrashCanEject())' ../statusbar/DockTrash.h && grep -q '!d.items.count || !DMDockTrashCanEject()' ../statusbar/DockTrash.h && grep -q '!gFinderOn || !DMDockTrashCanEject()' ../statusbar/DockTrash.h"
[ $fails = 0 ] && echo "test-docktrash: all wiring checks pass" || { echo "test-docktrash: wiring checks FAILED"; exit 1; }
