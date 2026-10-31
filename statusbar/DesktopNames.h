// DesktopNames.h -- which desktop icons show their name (1.7.2 item 16, KT). An icon's own Hide Name / Show Name (its menu) is kept by name in
// the desktop's plist (com.besiktasliseba.macstatusbar.desktop, "hiddenNames"), as the icons' places are: a move on the desktop keeps the name; a
// respring reads the record back; a rename keeps it (the desktop's own rename at once, one made elsewhere -- the Files app, a Finder window -- by
// the file's inode in the next listing); an item gone from the desktop is forgotten (not while the Desktop folder itself is missing: its icons
// come back with it). Settings > Mac Status Bar > Hide Desktop Icon Names hides every name. The icon keeps its place and size either way: only the
// name goes (VoiceOver still reads it). Foundation only: Desktop.h runs it, tools/test-desktopnames.m checks it on the Mac.
#pragma once
#import <Foundation/Foundation.h>

// The record as stored: an array of names (anything else is no record; entries that are not names are left out).
static NSMutableSet<NSString *> *DMNamesHiddenFromStored(id stored) {
    NSMutableSet<NSString *> *s = [NSMutableSet set];
    if ([stored isKindOfClass:[NSArray class]]) for (id n in (NSArray *)stored) if ([n isKindOfClass:[NSString class]] && [(NSString *)n length]) [s addObject:[(NSString *)n copy]];
    return s;
}
// ... and as it is written: sorted (the same record always writes the same array); none hidden: nothing (the key is removed).
static NSArray<NSString *> *DMNamesHiddenToStore(NSSet<NSString *> *hidden) {
    return hidden.count ? [[hidden allObjects] sortedArrayUsingSelector:@selector(compare:)] : nil;
}
// A listing of the Desktop folder came in: names = the items in it now; inodes = theirs by name; lastInodes = the last listing's (nil: none since
// SpringBoard started). A hidden name whose file is in the folder under a name the last listing did not have -- the same inode, its old name gone
// -- moves to the new name (a rename made elsewhere); a name no item has any more is forgotten. Nothing changes while the folder is missing.
// YES when the record changed (to be saved).
static BOOL DMNamesHiddenFollowListing(NSMutableSet<NSString *> *hidden, NSSet<NSString *> *names, NSDictionary<NSString *, NSNumber *> *inodes,
                                       NSDictionary<NSString *, NSNumber *> *lastInodes, BOOL folderMissing) {
    if (!hidden || !names || folderMissing) return NO;
    BOOL changed = NO;
    NSMutableDictionary<NSNumber *, NSString *> *gone = [NSMutableDictionary dictionary];   // (inode -> a hidden name the folder no longer has)
    for (NSString *old in lastInodes) if ([hidden containsObject:old] && ![names containsObject:old]) gone[lastInodes[old]] = old;
    if (gone.count) for (NSString *n in [[names allObjects] sortedArrayUsingSelector:@selector(compare:)]) {
        NSNumber *ino = inodes[n];
        if (!ino || lastInodes[n] || [hidden containsObject:n]) continue;   // (only a name new in this listing)
        NSString *old = gone[ino];
        if (!old) continue;
        [hidden addObject:n]; [hidden removeObject:old]; [gone removeObjectForKey:ino];
        changed = YES;
    }
    for (NSString *n in [hidden allObjects]) if (![names containsObject:n]) { [hidden removeObject:n]; changed = YES; }
    return changed;
}
// The desktop's own rename (in place), as it is asked for: the new name is hidden at once when the old one is. The old one stays in the record
// until a listing shows the rename done (a rename refused -- the name taken, no permission -- leaves the record as it was, the new name then
// forgotten); never onto a name another item on the desktop has now. YES when the record changed.
static BOOL DMNamesHiddenRenaming(NSMutableSet<NSString *> *hidden, NSString *from, NSString *to, NSSet<NSString *> *names) {
    if (!hidden || !from.length || !to.length || [from isEqualToString:to] || ![hidden containsObject:from] || [hidden containsObject:to] || [names containsObject:to]) return NO;
    [hidden addObject:to];
    return YES;
}
// The menu's row for the icons it is for (the selection, or the icon held): "Show Name" when each of them has its name hidden, else "Hide Name".
static BOOL DMNamesHiddenEvery(NSSet<NSString *> *hidden, NSArray<NSString *> *names) {
    if (!names.count) return NO;
    for (NSString *n in names) if (![hidden containsObject:n]) return NO;
    return YES;
}
// ... chosen: every one of them hidden, or every one shown. YES when the record changed.
static BOOL DMNamesHiddenSet(NSMutableSet<NSString *> *hidden, NSArray<NSString *> *names, BOOL hide) {
    BOOL changed = NO;
    for (NSString *n in names) {
        if (![n isKindOfClass:[NSString class]] || !n.length || [hidden containsObject:n] == hide) continue;
        if (hide) [hidden addObject:n]; else [hidden removeObject:n];
        changed = YES;
    }
    return changed;
}
// Whether an icon shows its name: Settings' Hide Desktop Icon Names hides every name; otherwise the icon's own record.
static BOOL DMNameShows(NSSet<NSString *> *hidden, NSString *name, BOOL everyNameHidden) { return !everyNameHidden && ![hidden containsObject:name]; }
