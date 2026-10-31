// test-driveeject.m -- Mac test of a drive's eject and name (common/DriveEject.h, 1.7.3): what the root helper accepts as a request (an id, one
// volume folder in a connected drive's shape, fresh), the mount check (a connected drive's own mount point from a local disk, never the root file
// system), the answer file (only the answer to our own request), msbdeject's run (its line, the time limit), the dialog's words, a drive's name
// (its volume's label, not 18's UUID folder), the disk's BSD name for DiskArbitration, and that "the helper is running" means a live process of
// that name. With --name <folder> / --da <disk> <mount point> it reads a mounted image's name / runs ejecthelper/DAEject.h's eject against it
// (tools/test-driveeject.sh, MSBD_LIVE_DA=1).
#import <Foundation/Foundation.h>
#include "../common/DriveEject.h"
#include "../ejecthelper/DAEject.h"

static int fails = 0, checks = 0;
static void ok(NSString *what, BOOL cond) { checks++; if (!cond) { fails++; printf("FAIL %s\n", what.UTF8String); } }
static void eqs(NSString *what, NSString *got, NSString *want) { checks++; if (!(got == want || [got isEqualToString:want])) { fails++; printf("FAIL %s: got \"%s\", want \"%s\"\n", what.UTF8String, got.UTF8String ?: "(nil)", want.UTF8String ?: "(nil)"); } }

static NSString *const kRID = @"0123456789abcdef0123456789abcdef";
static NSString *const kVol = @"/var/mobile/Library/LiveFiles/com.apple.filesystems.userfsd/5D3A6E1C-0B7F-4C2B-9E61-2A8F0C1D4E77";
static NSDictionary *Req(id rid, id vol, id at) { NSMutableDictionary *d = [NSMutableDictionary dictionary]; if (rid) d[@"id"] = rid; if (vol) d[@"volume"] = vol; if (at) d[@"at"] = at; return d; }

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc == 3 && !strcmp(argv[1], "--name")) {   // (the live run: what Finder would call the volume mounted there)
            struct statfs fs; if (statfs(argv[2], &fs) != 0) return 1;
            printf("%s\n", MSBDDriveName([NSString stringWithUTF8String:fs.f_mntonname], [NSString stringWithUTF8String:fs.f_mntfromname], MSBDDriveVolumeLabel(fs.f_mntonname)).UTF8String);
            return 0;
        }
        if (argc == 4 && !strcmp(argv[1], "--da")) {   // (the live run against a disk image: busy with a file held open, then the eject itself)
            NSString *held = [[NSString stringWithUTF8String:argv[3]] stringByAppendingPathComponent:@"held.txt"];
            [@"x" writeToFile:held atomically:NO encoding:NSUTF8StringEncoding error:nil];
            int fd = open(held.fileSystemRepresentation, O_RDONLY);
            MSBDDAResult r = MSBDDAEject(argv[2], argv[3]);
            printf("busy: code %d (%s), still mounted %d\n", r.code, r.why, MSBDDAStillMounted(argv[3]));
            close(fd);
            MSBDDAResult r2 = MSBDDAEject(argv[2], argv[3]);
            printf("eject: code %d (%s), still mounted %d\n", r2.code, r2.why, MSBDDAStillMounted(argv[3]));
            return r.code == 3 && r2.code == 0 && !MSBDDAStillMounted(argv[3]) ? 0 : 1;
        }
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        NSString *rid = nil, *vol = nil, *why = nil;

        // ---- the request: who may ask is the preferences' business; WHAT is accepted is this ----
        ok(@"a request as Finder makes it is taken", MSBDEjectRequestFrom(Req(kRID, kVol, @(now)), now, &rid, &vol, &why) && [rid isEqualToString:kRID] && [vol isEqualToString:kVol] && !why);
        ok(@"  ... the /private/var spelling too", MSBDEjectRequestFrom(Req(kRID, [@"/private" stringByAppendingString:kVol], @(now)), now, &rid, &vol, &why));
        ok(@"  ... asked 39 s ago (Finder still waits)", MSBDEjectRequestFrom(Req(kRID, kVol, @(now - 39)), now, &rid, &vol, &why));
        for (id notDict in @[@"x", @[kRID, kVol], @42, [NSNull null]]) ok([NSString stringWithFormat:@"not a dictionary (%@): ignored, nobody told", [notDict class]], !MSBDEjectRequestFrom(notDict, now, &rid, &vol, &why) && !rid);
        ok(@"nothing at all: ignored", !MSBDEjectRequestFrom(nil, now, &rid, &vol, &why) && !rid);
        for (id badID in @[@"0123456789abcdef0123456789abcde", @"0123456789ABCDEF0123456789ABCDEF", @"0123456789abcdef0123456789abcdeg", @"0123456789abcdef0123456789abcdef0", @1234, @""])
            ok([NSString stringWithFormat:@"a bad id (%@): ignored, nobody to tell", badID], !MSBDEjectRequestFrom(Req(badID, kVol, @(now)), now, &rid, &vol, &why) && !rid);
        NSMutableDictionary *extra = [Req(kRID, kVol, @(now)) mutableCopy]; extra[@"args"] = @"--force";
        ok(@"an extra key (an argument): refused, and answered", !MSBDEjectRequestFrom(extra, now, &rid, &vol, &why) && [rid isEqualToString:kRID] && [why isEqualToString:@"that isn't a request Finder makes"]);
        ok(@"no time: refused, answered", !MSBDEjectRequestFrom(Req(kRID, kVol, nil), now, &rid, &vol, &why) && rid && why);
        ok(@"a time that is not a number: refused", !MSBDEjectRequestFrom(Req(kRID, kVol, @"now"), now, &rid, &vol, &why) && rid);
        ok(@"asked 41 s ago: too old (never carried out later, at a helper's next start)", !MSBDEjectRequestFrom(Req(kRID, kVol, @(now - 41)), now, &rid, &vol, &why) && [why hasPrefix:@"the request is too old"]);
        ok(@"asked a day ago: too old", !MSBDEjectRequestFrom(Req(kRID, kVol, @(now - 86400)), now, &rid, &vol, &why) && rid);
        ok(@"from the future: refused", !MSBDEjectRequestFrom(Req(kRID, kVol, @(now + 60)), now, &rid, &vol, &why) && rid);
        ok(@"a time of NAN: refused", !MSBDEjectRequestFrom(Req(kRID, kVol, @(NAN)), now, &rid, &vol, &why) && rid);
        NSArray *badVolumes = @[ @"relative/path", @"/var/mobile", @"/var/mobile/Library/LiveFiles", @"/var/mobile/Library/LiveFiles/com.apple.filesystems.userfsd",
            [kVol stringByAppendingString:@"/DCIM"], @"/var/mobile/Library/LiveFiles/p/../../../../etc", @"/var/mobile/Library/LiveFiles/p/v/../../../../../private/var",
            @"/var/mobile/Library/LiveFiles/p/v\n/etc", [NSString stringWithFormat:@"%@%C", kVol, (unichar)0], @"/", @"",
            [@"/var/mobile/Library/LiveFiles/p/" stringByPaddingToLength:1100 withString:@"x" startingAtIndex:0], @"/var/mobile/Library/LiveFilesX/p/v" ];
        for (NSString *b in badVolumes) ok([NSString stringWithFormat:@"not a drive's folder (%@): refused, answered", b.length > 60 ? [[b substringToIndex:60] stringByAppendingString:@"..."] : b],
                                           !MSBDEjectRequestFrom(Req(kRID, b, @(now)), now, &rid, &vol, &why) && [rid isEqualToString:kRID] && [why isEqualToString:@"it isn't a connected drive"] && !vol);
        ok(@"a volume that is not a string: refused", !MSBDEjectRequestFrom(Req(kRID, @[kVol], @(now)), now, &rid, &vol, &why) && rid);
        {   // (a lone UTF-16 surrogate: a property list carries it -- the request comes through cfprefsd --, the file system can't spell it, and the root
            //  helper's -fileSystemRepresentation of an accepted one raised: the helper ended. Refused before that, and answered.)
            unichar lone[] = { 0xD800, 'x' };
            NSString *odd = [kVol stringByAppendingString:[NSString stringWithCharacters:lone length:2]];
            NSData *pl = [NSPropertyListSerialization dataWithPropertyList:Req(kRID, odd, @(now)) format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
            id back = pl ? [NSPropertyListSerialization propertyListWithData:pl options:0 format:NULL error:nil] : nil;
            ok(@"a volume with a lone surrogate comes through a binary property list (as a request does)", [back isKindOfClass:[NSDictionary class]] && [back[@"volume"] isEqualToString:odd]);
            ok(@"  ... and is refused (no file system spelling), answered", !MSBDEjectRequestFrom(back, now, &rid, &vol, &why) && [rid isEqualToString:kRID] && [why isEqualToString:@"it isn't a connected drive"] && !vol);
            NSString *longOne = [[kVol stringByDeletingLastPathComponent] stringByAppendingPathComponent:[@"" stringByPaddingToLength:500 withString:@"é" startingAtIndex:0]];   // (a drive's shape, under 1024 characters, past PATH_MAX in UTF-8)
            ok(@"  ... as is one longer than the file system's longest path", longOne.length <= 1024 && MSBDEjectInLiveFiles(MSBDEjectNorm(longOne)) && !MSBDEjectRequestFrom(Req(kRID, longOne, @(now)), now, &rid, &vol, &why) && !vol);
            for (NSString *b in @[kVol, [@"/private" stringByAppendingString:kVol], [kVol stringByReplacingOccurrencesOfString:@"5D3A6E1C" withString:@"Ünïcödé"]]) {
                BOOL taken = MSBDEjectRequestFrom(Req(kRID, b, @(now)), now, &rid, &vol, &why);
                BOOL spelled = NO; @try { spelled = taken && vol.fileSystemRepresentation != NULL; } @catch (NSException *e) { spelled = NO; }
                ok([NSString stringWithFormat:@"every volume taken has a file system spelling (%@)", b.lastPathComponent], taken && spelled);
            }
        }
        NSString *a = MSBDEjectNewRequestID(), *b = MSBDEjectNewRequestID();
        ok(@"Finder's ids: 32 hex digits, a new one each time", MSBDEjectIsRequestID(a) && MSBDEjectIsRequestID(b) && ![a isEqualToString:b]);

        // ---- the mount check (statfs's answer for the folder) ----
        NSString *mp = MSBDEjectCheckMount(kVol, [@"/private" stringByAppendingString:kVol], @"fat://disk2s1/NO NAME", 0, &why);
        eqs(@"a connected drive's own mount point (UserFS, 15): taken, Finder's spelling", mp, kVol);
        ok(@"  ... from /dev/disk4s1 (18's FSKit) too", MSBDEjectCheckMount(kVol, kVol, @"/dev/disk4s1", 0, &why) != nil);
        ok(@"a folder inside the drive (not its own folder): refused", !MSBDEjectCheckMount([kVol stringByAppendingString:@"/DCIM"], kVol, @"fat://disk2s1/NO NAME", 0, &why) && [why isEqualToString:@"it isn't a drive's own folder"]);
        ok(@"a network share mounted there: refused", !MSBDEjectCheckMount(kVol, kVol, @"smb://server/share", 0, &why) && [why isEqualToString:@"it isn't a drive connected to this iPad"]);
        ok(@"a source that only looks like a disk: refused", !MSBDEjectCheckMount(kVol, kVol, @"://disk2s1", 0, &why) && !MSBDEjectCheckMount(kVol, kVol, @"fat://server/disk2s1", 0, &why));
        ok(@"the root file system: refused", !MSBDEjectCheckMount(kVol, kVol, @"/dev/disk0s1s1", MNT_ROOTFS, &why) && [why isEqualToString:@"it is the iPad's own storage"]);
        ok(@"the iPad's own storage (/var/mobile): refused", !MSBDEjectCheckMount(@"/var/mobile", @"/private/var/mobile", @"/dev/disk1s7", 0, &why) && [why isEqualToString:@"it isn't a connected drive"]);
        ok(@"a provider folder that is a mount point itself: refused", !MSBDEjectCheckMount(@"/var/mobile/Library/LiveFiles/p", @"/var/mobile/Library/LiveFiles/p", @"fat://disk2s1/X", 0, &why));
        // (on this Mac: real folders through realpath and statfs)
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"msbd-eject-%d", getpid()]];
        [[NSFileManager defaultManager] createDirectoryAtPath:tmp withIntermediateDirectories:YES attributes:nil error:nil];
        ok(@"a folder that is no mount point (the debug fake drive's kind): refused", !MSBDEjectVolumeAt(tmp.fileSystemRepresentation, NULL, &why) && [why isEqualToString:@"it isn't a drive's own folder"]);
        ok(@"the root file system's own folder: refused", !MSBDEjectVolumeAt("/", NULL, &why) && [why isEqualToString:@"it isn't a connected drive"]);
        ok(@"a folder that isn't there: refused", !MSBDEjectVolumeAt("/nonexistent/msbd", NULL, &why) && [why isEqualToString:@"that folder isn't there"]);
        [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];

        // ---- the answer ----
        NSData *ans = MSBDEjectAnswerData(kRID, @"busy: Resource busy");
        eqs(@"the answer to our request is read", MSBDEjectAnswerLine(ans, kRID), @"busy: Resource busy");
        ok(@"another request's answer is not ours", MSBDEjectAnswerLine(ans, @"ffffffffffffffffffffffffffffffff") == nil);
        ok(@"no answer without an id of ours (a bad id never matches)", MSBDEjectAnswerLine(ans, @"x") == nil && MSBDEjectAnswerLine(ans, nil) == nil);
        ok(@"a file of one line is no answer", MSBDEjectAnswerLine([kRID dataUsingEncoding:NSUTF8StringEncoding], kRID) == nil);
        ok(@"a huge file is no answer", MSBDEjectAnswerLine([NSMutableData dataWithLength:5000], kRID) == nil);
        eqs(@"a line with newlines in it stays one line", MSBDEjectAnswerLine(MSBDEjectAnswerData(kRID, @"error: a\nb\rc"), kRID), @"error: a b c");
        ok(@"a very long line is kept to 1 KB", MSBDEjectAnswerLine(MSBDEjectAnswerData(kRID, [@"error: " stringByPaddingToLength:3000 withString:@"y" startingAtIndex:0]), kRID).length == 1024);

        // ---- msbdeject's run, as one line ----
        eqs(@"the helper's own line", MSBDEjectHelperAnswer(0, [@"ok\n" dataUsingEncoding:NSUTF8StringEncoding], NO), @"ok");
        eqs(@"  ... its last line", MSBDEjectHelperAnswer(0, [@"note\nbusy: in use\n" dataUsingEncoding:NSUTF8StringEncoding], NO), @"busy: in use");
        eqs(@"no answer from it", MSBDEjectHelperAnswer(0, [NSData data], NO), @"error: the eject helper gave no answer");
        eqs(@"it couldn't be started (EPERM, 18's SpringBoard spawn)", MSBDEjectHelperAnswer(1, nil, NO), @"error: the eject helper couldn’t be started (1)");
        eqs(@"no pipe", MSBDEjectHelperAnswer(-1, nil, NO), @"error: the eject helper couldn’t be started (no pipe)");
        eqs(@"stopped at its time limit", MSBDEjectHelperAnswer(0, nil, YES), @"error: the eject didn’t finish in time");

        // ---- the dialog's words ----
        NSString *title = nil, *message = nil;
        ok(@"ok: no dialog (the drive just leaves the sidebar)", !MSBDEjectMessage(@"ok", @"NO NAME", &title, &message) && !title && !message);
        ok(@"in use: a Mac's words", MSBDEjectMessage(@"busy: Resource busy", @"NO NAME", &title, &message)
           && [title isEqualToString:@"The disk “NO NAME” wasn’t ejected because one or more programs may be using it."] && [message isEqualToString:@"Close the files on it and try again."]);
        ok(@"refused: the reason as a sentence", MSBDEjectMessage(@"refused: it is the iPad's own storage", @"NO NAME", &title, &message)
           && [title isEqualToString:@"The disk “NO NAME” couldn’t be ejected."] && [message isEqualToString:@"It is the iPad's own storage."]);
        ok(@"the helper not running: said so", MSBDEjectMessage(kMSBDEjectNoHelperLine, @"USB", &title, &message)
           && [title isEqualToString:@"The disk “USB” couldn’t be ejected."] && [message isEqualToString:@"MacStatusBar&Dock’s helper isn’t running. Try again in a moment; if it keeps happening, reinstall MacStatusBar&Dock."]);
        ok(@"no answer in time: said so", MSBDEjectMessage(kMSBDEjectNoAnswerLine, @"USB", &title, &message) && [message isEqualToString:@"MacStatusBar&Dock’s helper didn’t answer. Try again in a moment."]);
        ok(@"a reason ending in a full stop gets no second one", MSBDEjectMessage(@"error: Done.", @"USB", &title, &message) && [message isEqualToString:@"Done."]);
        ok(@"no name: Untitled", MSBDEjectMessage(@"error: x", @"", &title, &message) && [title containsString:@"“Untitled”"]);
        ok(@"no reason: no message", MSBDEjectMessage(@"error", @"USB", &title, &message) && title && !message);
        // (the debug fake drive, end to end without a drive: the helper refuses its request -- a folder outside LiveFiles -- and Finder says why)
        ok(@"a fake drive's request: refused, answered", !MSBDEjectRequestFrom(Req(kRID, @"/var/mobile/Documents/5D3A6E1C-0B7F-4C2B-9E61-2A8F0C1D4E77", @(now)), now, &rid, &vol, &why) && rid);
        NSString *line = MSBDEjectAnswerLine(MSBDEjectAnswerData(rid, [@"refused: " stringByAppendingString:why]), kRID);
        ok(@"  ... and Finder says it isn't a connected drive", MSBDEjectMessage(line, @"NO NAME", &title, &message) && [title isEqualToString:@"The disk “NO NAME” couldn’t be ejected."] && [message isEqualToString:@"It isn't a connected drive."]);

        // ---- a drive's name ----
        NSString *uuidFolder = kVol;
        eqs(@"18 (FSKit): the volume's label, not the UUID folder", MSBDDriveName(uuidFolder, @"/dev/disk4s1", @"NO NAME"), @"NO NAME");
        eqs(@"  ... whatever the source says", MSBDDriveName(uuidFolder, @"msdos://disk4s1/5D3A6E1C-0B7F-4C2B-9E61-2A8F0C1D4E77", @"NO NAME"), @"NO NAME");
        eqs(@"15 (UserFS): no label read -- the name in the mount's source", MSBDDriveName(@"/var/mobile/Library/LiveFiles/com.apple.filesystems.userfsd/NO NAME", @"fat://disk2s1/NO NAME", nil), @"NO NAME");
        eqs(@"  ... a second drive of the same name (its folder \"NO NAME 1\") is \"NO NAME\" too, as in Files", MSBDDriveName(@"/var/mobile/Library/LiveFiles/com.apple.filesystems.userfsd/NO NAME 1", @"fat://disk3s1/NO NAME", nil), @"NO NAME");
        eqs(@"a label of spaces only: the source's name", MSBDDriveName(uuidFolder, @"exfat://disk3s1/Backup", @"   "), @"Backup");
        eqs(@"a URL-spelled source name", MSBDDriveName(uuidFolder, @"exfat://disk3s1/My%20Drive", nil), @"My Drive");
        eqs(@"  ... a % that is not a URL's stays", MSBDDriveName(uuidFolder, @"fat://disk2s1/100%", nil), @"100%");
        eqs(@"no label, no name in the source: the folder's name", MSBDDriveName(uuidFolder, @"msdos://disk4s1", nil), uuidFolder.lastPathComponent);
        eqs(@"  ... a network source names nothing", MSBDDriveName(@"/x/share", @"smb://host/share", nil), @"share");
        eqs(@"a label with spaces kept as it is", MSBDDriveName(uuidFolder, nil, @"KT USB 2"), @"KT USB 2");
        NSString *boot = MSBDDriveVolumeLabel("/");
        ok([NSString stringWithFormat:@"the label is read from the file system (this Mac's boot volume: \"%@\")", boot], boot.length > 0);
        ok(@"no label for a folder that isn't there", MSBDDriveVolumeLabel("/nonexistent/msbd") == nil && MSBDDriveVolumeLabel(NULL) == nil);

        // ---- DiskArbitration's BSD name (the 15 eject) ----
        eqs(@"UserFS's source", MSBDDriveBSDName(@"fat://disk2s1/NO NAME"), @"disk2s1");
        eqs(@"a device path", MSBDDriveBSDName(@"/dev/disk4s1"), @"disk4s1");
        eqs(@"a source without a name", MSBDDriveBSDName(@"msdos://disk4s1"), @"disk4s1");
        eqs(@"a whole disk", MSBDDriveBSDName(@"/dev/disk4"), @"disk4");
        eqs(@"an APFS volume's", MSBDDriveBSDName(@"/dev/disk3s1s1"), @"disk3s1s1");
        for (NSString *bad in @[@"smb://server/share", @"fat://disk/NO NAME", @"fat://disk2s/X", @"fat://disk2ss1/X", @"fat://diskX/", @"/dev/rdisk2", @"/dev/disk2s1/../disk0", @""])
            ok([NSString stringWithFormat:@"not a disk's BSD name: %@", bad], MSBDDriveBSDName(bad) == nil);

        // ---- the helper is running: a live process of that name ----
        const char *me = getprogname();
        ok(@"this test's own pid and name: running", MSBDEjectProcessNamed((uint64_t)getpid(), me));
        ok(@"  ... under another name: not the helper", !MSBDEjectProcessNamed((uint64_t)getpid(), kMSBDEjectHelperName));
        pid_t gone = fork();
        if (gone == 0) _exit(0);
        int st = 0; waitpid(gone, &st, 0);
        ok(@"a pid left by a process that has gone: not running", !MSBDEjectProcessNamed((uint64_t)gone, me));
        ok(@"no pid, or one that can't be a pid: not running", !MSBDEjectProcessNamed(0, me) && !MSBDEjectProcessNamed((uint64_t)INT32_MAX + 5, me));

        // ---- msbdeject's run with a time limit ----
        char *quick[] = { "/bin/sh", "-c", "echo note; echo ok", NULL };
        NSData *out = nil; int status = -1; BOOL late = YES;
        int rc = MSBDRunHelperTimed("/bin/sh", quick, 5.0, &out, &status, &late);
        eqs(@"a helper that answers: its line", MSBDEjectHelperAnswer(rc, out, late), @"ok");
        ok(@"  ... ended by itself, in time", rc == 0 && !late && WIFEXITED(status) && WEXITSTATUS(status) == 0);
        char *slow[] = { "/bin/sh", "-c", "echo started; exec sleep 30", NULL };
        CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
        rc = MSBDRunHelperTimed("/bin/sh", slow, 0.5, &out, &status, &late);
        double took = CFAbsoluteTimeGetCurrent() - t0;
        ok([NSString stringWithFormat:@"a helper that hangs is stopped at the limit (%.2f s)", took], rc == 0 && late && took < 3.0 && WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL);
        eqs(@"  ... and the answer says so", MSBDEjectHelperAnswer(rc, out, late), @"error: the eject didn’t finish in time -- started");
        char *closer[] = { "/bin/sh", "-c", "exec >&-; exec sleep 30", NULL };
        t0 = CFAbsoluteTimeGetCurrent();
        rc = MSBDRunHelperTimed("/bin/sh", closer, 0.5, &out, &status, &late);
        took = CFAbsoluteTimeGetCurrent() - t0;
        ok([NSString stringWithFormat:@"one that closes its output but goes on running is stopped too (%.2f s)", took], rc == 0 && late && took < 3.0);
        rc = MSBDRunHelperTimed("/nonexistent/msbdeject", quick, 5.0, &out, &status, &late);
        ok(@"a helper that is not there: posix_spawn's error, no answer, no status", rc != 0 && out == nil && status == -1 && !late);
        eqs(@"  ... said as such", MSBDEjectHelperAnswer(rc, out, late), [NSString stringWithFormat:@"error: the eject helper couldn’t be started (%d)", rc]);

        // ---- DiskArbitration (15): the code is here and its functions are found on this Mac (the live run: MSBD_LIVE_DA=1) ----
        MSBDDAFuncs f;
        ok(@"DiskArbitration's functions are found where it is there", MSBDDALoad(&f));
        MSBDDAResult r = MSBDDAEject("disk999s9", "/nonexistent/msbd");
        ok([NSString stringWithFormat:@"a disk the system doesn't know: not ejected, said why (%s)", r.why], r.code == 1 && strlen(r.why) > 0);
        ok(@"busy statuses: DiskArbitration's busy and exclusive access, the kernel's EBUSY", MSBDDABusyStatus((int32_t)0xF8DA0002) && MSBDDABusyStatus((int32_t)0xF8DA0004) && MSBDDABusyStatus((int32_t)(0xC000 | EBUSY)) && !MSBDDABusyStatus((int32_t)0xF8DA0007) && !MSBDDABusyStatus(0));
    }
    printf("test-driveeject: %d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
