// PrewarmQuitSet.h -- the quit set's file: SpringBoard writes it (statusbar/StatusBar.x, DMPrewarmQuitWriteFile) before it tells dasd the set
// changed, the dasd part reads it (prewarmblock/PrewarmBlock.x). Plain Foundation so the Mac test (tools/test-prewarmquitset.m) runs this very code.
//  - Why a file of its own. dasd read the set through cfprefsd until 1.7.0, but cfprefsd answers a sandboxed process only for the preference
//    domains its sandbox allows, and dasd's allows Apple's own: on Dopamine cfprefsd answered anyway, on palera1n it answered nothing (iPad 2,
//    16.7.7, 29 Oct: "refreshed: 0 app(s)" with 6 in the set; the sandbox refuses dasd the domain and the path when asked, while dasd's own read of
//    a file in the jailbreak's folder goes through). The file cfprefsd keeps our preferences in would not do either: cfprefsd wrote it 4 to 10 s
//    after a change (iPad 2, four changes, 30 Oct), so a prewarm asked in between still saw the old set. This file is written at once (within
//    3 ms of the change there), in the jailbreak's preferences folder, where dasd already keeps its start count.
//  - The file is also the block's on/off (1.7.1): there while the status bar part runs and keeps the set (it writes the file at every start), gone
//    when nothing keeps one -- Use Stock Status Bar or Mac Status Bar's old on/off switched off (StatusBar.x DMPrewarmBlockOff), a SpringBoard
//    without the status bar part (the crash guard's safe mode or step 1b, an untested iPadOS without Enable Anyway: loader/Loader.c), the package
//    removed (postrm), an install for a SpringBoard that keeps none (postinst: MSBDPrewarmQuitSetKept below). Not a SpringBoard with no loader of
//    ours at all (the MacStatusBar line switched off in Choicy or iCleaner Pro, ElleKit's Safe Mode): nothing removes the file there, and a dasd
//    that still has our part goes on refusing its set until dasd starts again -- as the notify state stayed on before 1.7.1; Choicy and iCleaner
//    keep the part out of the next dasd as well. Until 1.7.1 the switch was a notify state SpringBoard published at its start, which lives only
//    while a process holds the name. After the postinst stops dasd, launchd
//    starts it again only when something asks for it: on the M1 in the same second as the new SpringBoard of the install's respring (01:26:57 and
//    02:40:25, 30 Oct), with the old SpringBoard gone and the new one's status bar part not yet started -- that dasd read "off" and let its first
//    prewarms through (an app the user had quit "allowed (block off)"). The same for any dasd start before SpringBoard's.
//    (The path is plain C for the loader; the rest is Foundation.)
#ifndef MSBD_PREWARM_QUIT_SET_H
#define MSBD_PREWARM_QUIT_SET_H

#define kMSBDPrewarmQuitSetFile "/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-PrewarmQuitSet.plist"

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#include <sys/stat.h>

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

// Whether SpringBoard keeps a quit set -- the file there, the block on -- from what it decides that by at its start: Mac Status Bar's old on/off
// (tweakEnabled: none or YES is on, anything else off, as StatusBar.x's %ctor reads it), Use Stock Status Bar (stockStatusBar: YES is on, as
// DMStockBarSwitch reads it) -- both remove the file (DMPrewarmBlockOff) -- and whether its status bar part runs at all (the version gate and the
// crash guard's safe mode: without it the loader removes the file). The postinst's first copy of the file asks this (sshtoggled --quit-set-kept):
// a file made for a SpringBoard that keeps no set had dasd refuse those apps until that SpringBoard's start removed it (code review, 30 Oct).
static inline BOOL MSBDPrewarmQuitSetKept(id tweakEnabled, id stockStatusBar, BOOL partRuns) {
    CFTypeID b = CFBooleanGetTypeID();
    BOOL enabled = !tweakEnabled || (CFGetTypeID((__bridge CFTypeRef)tweakEnabled) == b && [(NSNumber *)tweakEnabled boolValue]);
    BOOL stock = stockStatusBar && CFGetTypeID((__bridge CFTypeRef)stockStatusBar) == b && [(NSNumber *)stockStatusBar boolValue];
    return partRuns && enabled && !stock;
}

#endif   // __OBJC__
#endif
