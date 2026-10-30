// PrewarmQuitSet.h -- the quit set's file: SpringBoard writes it (statusbar/StatusBar.x, DMPrewarmQuitWriteFile) before it tells dasd the set
// changed, the dasd part reads it (prewarmblock/PrewarmBlock.x). Plain Foundation so the Mac test (tools/test-prewarmquitset.m) runs this very code.
//  - Why a file of its own. dasd read the set through cfprefsd until 1.7.0, but cfprefsd answers a sandboxed process only for the preference
//    domains its sandbox allows, and dasd's allows Apple's own: on Dopamine cfprefsd answered anyway, on palera1n it answered nothing (iPad 2,
//    16.7.7, 29 Oct: "refreshed: 0 app(s)" with 6 in the set; the sandbox refuses dasd the domain and the path when asked, while dasd's own read of
//    a file in the jailbreak's folder goes through). The file cfprefsd keeps our preferences in would not do either: cfprefsd wrote it 4 to 10 s
//    after a change (iPad 2, four changes, 30 Oct), so a prewarm asked in between still saw the old set. This file is written at once (within
//    3 ms of the change there), in the jailbreak's preferences folder, where dasd already keeps its start count.
#ifndef MSBD_PREWARM_QUIT_SET_H
#define MSBD_PREWARM_QUIT_SET_H
#import <Foundation/Foundation.h>
#include <sys/stat.h>

#define kMSBDPrewarmQuitSetFile "/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-PrewarmQuitSet.plist"

// The bundle identifiers stored under "quitSet" in the file's contents (a property list: XML as SpringBoard writes it, or binary). Anything
// else -- no file, an empty or damaged one, another type -- is an empty set; empty names and non-strings are left out.
static inline NSSet<NSString *> *MSBDPrewarmQuitSetFromPlist(NSData *data) {
    if (!data.length) return [NSSet set];
    id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
    id list = [plist isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)plist)[@"quitSet"] : nil;
    NSMutableSet<NSString *> *set = [NSMutableSet set];
    if ([list isKindOfClass:[NSArray class]]) for (id b in (NSArray *)list) if ([b isKindOfClass:[NSString class]] && [(NSString *)b length]) [set addObject:b];
    return [set copy];
}
// The file's contents for a set (the apps in their order, oldest quit first): what SpringBoard writes.
static inline NSData *MSBDPrewarmQuitSetPlist(NSArray<NSString *> *apps) {
    return [NSPropertyListSerialization dataWithPropertyList:@{@"quitSet": apps ?: @[]} format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
}

// Which file was read: its modification time and size (present NO: there was none). A file whose stamp is not the one read last is read again --
// SpringBoard replaces it on every change (an atomic write), so a change dasd was not told of is still found (the notification comes from the same
// write, but a restart of either side can fall between them).
typedef struct { BOOL present; long long sec, nsec, size; } MSBDPrewarmFileStamp;
static inline MSBDPrewarmFileStamp MSBDPrewarmStampOf(const struct stat *st) {
    MSBDPrewarmFileStamp s = { NO, 0, 0, 0 };
    if (st) { s.present = YES; s.sec = (long long)st->st_mtimespec.tv_sec; s.nsec = (long long)st->st_mtimespec.tv_nsec; s.size = (long long)st->st_size; }
    return s;
}
static inline BOOL MSBDPrewarmStampChanged(MSBDPrewarmFileStamp was, MSBDPrewarmFileStamp now) {
    if (was.present != now.present) return YES;
    return now.present && (was.sec != now.sec || was.nsec != now.nsec || was.size != now.size);
}

#endif
