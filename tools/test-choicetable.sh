#!/bin/bash
# Mac test of the choices' table (common/ExclusiveChoice.h, test-choicetable.m; 1.8.0, plans/control-center-1.8.0.md 3.3): one table of the
# choices whose options are other tweaks -- Window Engine, Control Center Style (BigSurCenter), Banner Style (Destra) -- and Choicy's lists
# changed, recorded, given back. Then, in the code as built: Settings and the root helper both go by it (no copy of the lists or the record
# rules left of their own), every apply decides BigSurCenter and Destra, and every give-back -- the switch-off, the removal's --uninstall,
# --restore-engines -- covers them.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/t" test-choicetable.m
"$W/t"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
P=../statusbar/macstatusbarprefs/MSBRootListController.m; H=../macsettings/sshtoggled/main.m; X=../common/ExclusiveChoice.h
check "Settings: the engines' libraries and a pick's change in Choicy from the table (Window Engine and Control Center Style alike), recorded the same way" \
  "grep -q 'static NSDictionary<NSString \\*, NSArray<NSString \\*> \\*> \\*MSBEngineLibraries(void) { return MSBDExValues(@\"windowEngine\"); }' $P \
   && grep -q 'BOOL changed = MSBDExChoicyApply(prefs, record, MSBDExLibs(choice, value ?: @\"\"), MSBOtherChoiceLibraries(choice, value), @\\[\\], nil);' $P \
   && grep -q 'static BOOL MSBChoicyApplyEngine(NSString \\*engine) { return MSBChoicyApplyChoice(@\"windowEngine\", engine); }' $P \
   && grep -q 'static NSString \\*const kMSBChoicyChanges = kMSBDExChoicyRecord;' $P && ! grep -q 'MSBSetMembershipRecorded\\|static void MSBRecordChange' $P"
check "  ... a Choicy file that is there but can't be read is left alone (never replaced by our entries alone)" \
  "grep -q 'if (!prefs) { if (access(kMSBChoicyPrefs.fileSystemRepresentation, F_OK) == 0) return NO; prefs = \\[NSMutableDictionary new\\]; }' $P"
check "the root helper: the engines' table, its rename record, its Choicy change and its give-back from the table; no list rules of its own left" \
  "grep -q 'static NSDictionary<NSString \\*, NSArray<NSString \\*> \\*> \\*EngineLibs(void) { return MSBDExValues(@\"windowEngine\"); }' $H \
   && grep -q 'static NSDictionary<NSString \\*, NSString \\*> \\*EnginePackage(void) { return MSBDExPackages(@\"windowEngine\"); }' $H \
   && grep -q 'return \\[NSMutableOrderedSet orderedSetWithArray:MSBDExRenamesIn(s ?: @\"\")\\];' $H && grep -q 'return MSBDExChoicyUndo(prefs, record); }' $H \
   && grep -q 'BOOL changed = MSBDExChoicyApply(prefs, record, keep, deny, notInstalled, log);' $H \
   && ! grep -q 'static void RecordChange\\|static BOOL SetMembershipRecorded\\|static NSMutableArray \\*ChoicyList\\|ChoicyApplyChosenEngine' $H"
check "  ... the same files: Choicy's settings and our record where Settings writes them" \
  "grep -q '#define kMSBDExChoicyPrefs  @\"/var/jb/var/mobile/Library/Preferences/com.opa334.choicyprefs.plist\"' $X \
   && grep -q '#define kMSBDExChoicyRecord @\"/var/jb/var/mobile/Library/Preferences/MacStatusBar-ChoicyChanges.plist\"' $X \
   && grep -q '#define CHOICYRECORD PREFSDIR \"/MacStatusBar-ChoicyChanges.plist\"' $H && grep -q '#define ESTATEFILE ESTATEDIR \"/renamed\"' $H \
   && grep -q '#define kMSBDExRenameRecord @\"/var/jb/var/lib/sshtoggled-engines/renamed\"' $X && grep -q '#define ESTATEDIR \"/var/jb/var/lib/sshtoggled-engines\"' $H"
check "  ... every give-back covers BigSurCenter: the switch-off and the removal undo our Choicy entries and renames, --restore-engines the renames" \
  "awk '/^static void RestoreForOff/,/^}/' $H | grep -q 'GiveBackChoicyEngines();' && awk '/^static void RestoreForOff/,/^}/' $H | grep -q 'GiveBackAll(@\"Mac Status Bar is switched off\");' \
   && awk '/^static void Uninstall\\(void\\)/,/^}/' $H | grep -q 'GiveBackChoicyEngines();' && awk '/^static void Uninstall\\(void\\)/,/^}/' $H | grep -q 'GiveBackAll(@\"MacStatusBar&Dock removed\");' \
   && grep -q 'strcmp(argv\\[1\\], \"--restore-engines\") == 0) { GiveBackAll(@\"package removed\"); return 0; }' $H"
check "  ... and every apply decides BigSurCenter: a SpringBoard start, an install, a switch-on (Choicy); the iCleaner Pro renames" \
  "grep -q 'ChoicyApplyChoices(\\[reason isEqualToString:@\"manual\"\\] ? @\"manual\" : @\"Mac Status Bar started\");' $H && grep -q 'ChoicyApplyChoices(@\"install\");' $H \
   && awk '/^static void PrepareForOn/,/^}/' $H | grep -q 'ChoicyApplyChoices(why);' && awk '/^static void ApplyEngineRenames/,/^}/' $H | grep -q 'int style = ChosenCCStyle(status, &bsc);'"
check "  ... and Destra (Banner Style): the same applies -- Choicy (start, install, switch-on: ChoicyApplyChoices) and the iCleaner Pro renames" \
  "awk '/^static void ChoicyApplyChoices/,/^}/' $H > \$W/cac && grep -q 'int style = ChosenCCStyle(status, &bsc), banners = ChosenBannerStyle(status, &destra);' \$W/cac \
   && grep -q 'else \\[MSBDBannerLoadsDestra(banners) ? keep : deny addObject:@\"MacOSNotifications\"\\];' \$W/cac \
   && awk '/^static void ApplyEngineRenames/,/^}/' $H | grep -q 'int banners = ChosenBannerStyle(status, &destra);' \
   && awk '/^static void ApplyEngineRenames/,/^}/' $H | grep -q 'else if (destra) DisableOurs(@\"MacOSNotifications\", destra, record,'"
check "  ... SpringBoard told what loads changed from Choicy's lists (taken before the change) and from the libraries' files, not from our record" \
  "awk '/^static void ChoicyApplyChoices/,/^}/' $H > \$W/cac2 && grep -q 'NSDictionary \\*prefsBefore = (__bridge_transfer NSDictionary \\*)CFPropertyListCreateDeepCopy(NULL, (__bridge CFDictionaryRef)prefs, kCFPropertyListImmutable);' \$W/cac2 \
   && [ \$(grep -n 'prefsBefore = ' \$W/cac2 | cut -d: -f1) -lt \$(grep -n 'BOOL changed = MSBDExChoicyApply' \$W/cac2 | cut -d: -f1) ] \
   && grep -q 'return !\\[MSBDExChoicyEntriesOf(prefs, l) isEqualToString:MSBDExChoicyEntriesOf(prefsBefore, l)\\];' \$W/cac2 && grep -q 'if (destra && moved(@\\[@\"MacOSNotifications\"\\])) told |= kChangedBanners;' \$W/cac2 \
   && awk '/^static void ApplyEngineRenames/,/^}/' $H > \$W/ren2 && grep -q 'for (NSString \\*n in MSBDExAllLibs()) if (loads(n)) \\[loadedBefore addObject:n\\];' \$W/ren2 \
   && grep -q 'if (moved(@\\[@\"MacOSNotifications\"\\])) what |= kChangedBanners;' \$W/ren2 && grep -q 'if (what || !\\[record isEqual:before\\]) TellSpringBoardChanged(what ?: kChangedEngines);' \$W/ren2 \
   && ! grep -q 'RecordOf(' $H"
check "  ... the iCleaner Pro renames: the engines' given back alone when none is installed (BigSurCenter still decided), a library renamed only with its package's file list" \
  "awk '/^static void ApplyEngineRenames/,/^}/' $H > \$W/ren && grep -q 'for (NSString \\*n in MSBDExLibs(@\"windowEngine\", nil)) EnableOurs(n, record, @\"no engine installed\");' \$W/ren \
   && ! grep -q 'GiveBackAll(@\"no engine installed\")' \$W/ren && awk '/^static BOOL DisableOurs/,/^}/' $H | grep -q 'if (!OwnedByPackage(pkg, name))'"
check "a downgrade to a version before 1.8.0 (the prerm's --giveback-styles): our Choicy entries and the renames of BigSurCenter and Destra given back from our records, the engines' left (review 1)" \
  "awk '/^static void GiveBackStylesForDowngrade/,/^}/' $H > \$W/gbs && grep -q 'NSMutableArray \\*libs = \\[NSMutableArray arrayWithArray:MSBDExLibs(@\"controlCenterStyle\", nil)\\];' \$W/gbs \
   && grep -q '\\[libs addObjectsFromArray:MSBDExLibs(@\"bannerStyle\", nil)\\];' \$W/gbs && grep -q 'if (MSBDPackageOnDisk(DpkgStatus(), @\"com.opa334.choicy\")) GiveBackChoicyEntriesOf(libs, why);' \$W/gbs \
   && grep -q 'for (NSString \\*n in libs) EnableOurs(n, record, why);' \$W/gbs && grep -q 'SaveRecord(record);' \$W/gbs && ! grep -q 'windowEngine\\|GiveBackAll' \$W/gbs \
   && grep -q 'strcmp(argv\\[1\\], \"--giveback-styles\") == 0) { GiveBackStylesForDowngrade(argc > 2 ? argv\\[2\\] : NULL); return 0; }' $H \
   && grep -q 'strcmp(argv\\[1\\], \"--restore-msb-off\") != 0 && strcmp(argv\\[1\\], \"--giveback-styles\") != 0) return 0;' $H"
check "  ... the partial give-back: ExclusiveChoice.h's, Choicy and the record written as mobile, the record kept (never deleted: Settings would make one from its old copy)" \
  "awk '/^static void GiveBackChoicyEntriesOf/,/^}/' $H > \$W/gbe && grep -q 'NSArray \\*log = MSBDExChoicyUndoOnly(cur, record, libs);' \$W/gbe \
   && grep -q 'AsMobile(^BOOL{ return \\[cur writeToFile:@CHOICYPREFS atomically:YES\\]; });' \$W/gbe && grep -q 'notify_post(\"com.opa334.choicyprefs/ReloadPrefs\");' \$W/gbe \
   && grep -q 'AsMobile(^BOOL{ return \\[record writeToFile:@CHOICYRECORD atomically:YES\\]; });' \$W/gbe && ! grep -q 'unlink' \$W/gbe"
check "safe mode and an untested iPadOS (not meant to run): our Choicy entries for every library of the table given back too, as the iCleaner Pro renames (review 7)" \
  "awk '/^static void ApplyEngines\\(NSString \\*reason\\)/,/^}/' $H > \$W/ae && awk '/if \\(!TweakMeantToRun\\(\\)\\) \\{/{t=NR} /GiveBackAll\\(off\\);/{g=NR} /if \\(ChoicyInstalled\\(status\\)\\) GiveBackChoicyEntriesOf\\(MSBDExAllLibs\\(\\), off\\);/{c=NR} /return;/{if (c && !r) r=NR} END{exit !(t && g > t && c > g && r > c)}' \$W/ae"
[ $fails = 0 ] && echo "test-choicetable: wiring checks pass" || { echo "test-choicetable: wiring checks FAILED"; exit 1; }
