// TailspinDaemon.h -- Keep Tailspin Off in sshtoggled (root; 1.7.9, KT 2 Nov). Rules and the why: common/TailspinGuard.h.
// The helper keeps HangTracer's PDSEPrefAllowEnableTailspin = false in com.apple.da (user mobile, through cfprefsd, as perfdiagsselfenabled
// writes and reads it) while the switch is on, and takes its own false away when the switch goes off or at a removal. It looks when it starts,
// when Settings says the switch changed, and when com.apple.da's file changes (iPadOS's own tasking writes that domain too: a value taken away
// is written again). A tailspin perfdiagsselfenabled has turned on already is turned off at once where iPadOS has the tailspin tool (15, 16:
// `tailspin disable`, as by hand -- 16.7.7's tool takes no bare `reset`, exit 64; the next daily run then applies the system default, off);
// without it (17, 18) that next run turns it off. Each change is logged
// (ELog) and the state written for Settings (kMSBDTailspinStateFile: shown where perfdiagsselfenabled reads the key). The tool runs off the main
// queue (TGTurnOff): SSH, the engines and Sleep Guard's screen-off look never wait for it.
#include "../../common/TailspinGuard.h"

#define TG_DA_FILE "/var/mobile/Library/Preferences/" kMSBDPDSEDomain ".plist"   // (cfprefsd's file of the domain: watched for changes)
#ifndef TG_TOOL   // (overridable for the Mac test)
#define TG_TOOL "/usr/bin/tailspin"
#endif

static BOOL TGSwitchOn(void) {
    CFStringRef d = CFSTR("com.besiktasliseba.macstatusbar");
    CFPreferencesSynchronize(d, CFSTR("mobile"), kCFPreferencesAnyHost);
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR(kMSBDTailspinKey), d, CFSTR("mobile"), kCFPreferencesAnyHost);
    int stored = MSBDTailspinOffStored(v);
    if (v) CFRelease(v);
    return MSBDTailspinOffOn(stored, MSBDPrewarmRAM()) != 0;
}
static int TGAppleValue(void) {
    CFPreferencesSynchronize(CFSTR(kMSBDPDSEDomain), CFSTR("mobile"), kCFPreferencesAnyHost);
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR(kMSBDPDSEAllowKey), CFSTR(kMSBDPDSEDomain), CFSTR("mobile"), kCFPreferencesAnyHost);
    int r = MSBDPDSEAllowRead(v);
    if (v) CFRelease(v);
    return r;
}
static void TGSetAppleValue(CFBooleanRef value) {   // (NULL: taken away)
    CFPreferencesSetValue(CFSTR(kMSBDPDSEAllowKey), value, CFSTR(kMSBDPDSEDomain), CFSTR("mobile"), kCFPreferencesAnyHost);
    CFPreferencesSynchronize(CFSTR(kMSBDPDSEDomain), CFSTR("mobile"), kCFPreferencesAnyHost);
}
// Whether this iPadOS's perfdiagsselfenabled reads the key: the binary scanned once per file (its inode, size and time: an iPadOS update).
static BOOL TGSupported(void) {
    static struct stat seen; static BOOL have = NO, answer = NO;
    struct stat st;
    if (stat(kMSBDPDSEPath, &st) != 0) { have = NO; return NO; }
    if (have && st.st_ino == seen.st_ino && st.st_size == seen.st_size && st.st_mtimespec.tv_sec == seen.st_mtimespec.tv_sec) return answer;
    answer = MSBDPDSESupportsAt(kMSBDPDSEPath) != 0; seen = st; have = YES;
    return answer;
}
// tailspin's configuration as tailspind keeps it: on (1) / off (0) / unknown (-1), and who set it ("perfdiagsselfenabled [38726]").
static int TGTailspinOn(NSString **modifier) {
    NSDictionary *c = [NSDictionary dictionaryWithContentsOfFile:@kMSBDTailspinConfig];
    if (modifier) *modifier = [c[@"EnabledModifier"] isKindOfClass:[NSString class]] ? c[@"EnabledModifier"] : @"";
    id e = c[@"Enabled"];
    return [e respondsToSelector:@selector(boolValue)] ? ([e boolValue] ? 1 : 0) : -1;
}
// Apple's tool (`tailspin disable`), at most 10 s: on TGTurnOff's queue only, never on the main queue.
static int TGRunTool(const char *arg) {
    char *const argv[] = { (char *)"tailspin", (char *)arg, NULL };
    posix_spawn_file_actions_t fa; posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_addopen(&fa, 1, "/dev/null", O_WRONLY, 0); posix_spawn_file_actions_addopen(&fa, 2, "/dev/null", O_WRONLY, 0);
    pid_t pid; int st = 0, rc = posix_spawn(&pid, TG_TOOL, &fa, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&fa);
    if (rc != 0) return -1;
    pid_t done = 0;
    for (int i = 0; i < 200 && (done = waitpid(pid, &st, WNOHANG)) == 0; i++) usleep(50000);
    if (done == 0) { kill(pid, SIGKILL); waitpid(pid, &st, 0); return -2; }
    return WIFEXITED(st) ? WEXITSTATUS(st) : -3;
}
static NSDictionary *TGState(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:@kMSBDTailspinStateFile];
    return [d isKindOfClass:[NSDictionary class]] ? d : @{};
}
static void TGWriteState(NSDictionary *d) {   // (for Settings, then its note)
    mkdir(ESTATEDIR, 0755);
    [d writeToFile:@kMSBDTailspinStateFile atomically:YES];
    chmod(kMSBDTailspinStateFile, 0644);
    notify_post(kMSBDTailspinUpdated);
}
// `tailspin disable` on a queue of its own: it returns in well under a second, but can take the tool's full 10 s when tailspind is slow (the
// daily perfdiagsselfenabled run that has just turned it on, the very moment this is for), and the helper's main queue -- SSH, the engines,
// Sleep Guard's screen-off look, the next look here -- waited all that time (code review). One run at a time: a look during it leaves it to that
// run. When it ends, back on the main queue: logged, and the state the look wrote (our record of the false first of all) gets tailspin's new
// configuration.
static BOOL gTGToolRunning = NO;   // (main queue)
static void TGTurnOff(NSString *why, NSString *mod) {
    if (gTGToolRunning) { ELog(@"tailspin (%@): on by %@ -- the tailspin tool is at it already", why, mod); return; }
    static dispatch_queue_t q;
    if (!q) q = dispatch_queue_create("com.besiktasliseba.sshtoggled.tailspin", DISPATCH_QUEUE_SERIAL);
    gTGToolRunning = YES;
    dispatch_async(q, ^{
        int rc = TGRunTool("disable");
        dispatch_async(dispatch_get_main_queue(), ^{
            @autoreleasepool {
                gTGToolRunning = NO;
                NSString *m2 = nil; int on = TGTailspinOn(&m2);
                ELog(@"tailspin (%@): on by %@ -- turned off with the tailspin tool (exit %d): now %@ by %@", why, mod, rc, on == 1 ? @"ON" : on == 0 ? @"off" : @"unknown", m2);
                NSMutableDictionary *d = [TGState() mutableCopy];
                d[@"checked"] = @(time(NULL)); d[@"tailspinOn"] = @(on); d[@"modifier"] = m2 ?: @"";
                TGWriteState(d);
            }
        });
    });
}
static void TGApply(NSString *why) {
    @autoreleasepool {
        BOOL supported = TGSupported(), wantOff = TGSwitchOn();
        int apple = TGAppleValue(), owned = [TGState()[@"owned"] boolValue], ownedAfter = 0;
        MSBDTGAction a = MSBDTailspinDecide(supported, wantOff, apple, owned, &ownedAfter);
        if (a == kMSBDTGWriteFalse) TGSetAppleValue(kCFBooleanFalse);
        else if (a == kMSBDTGRemove) TGSetAppleValue(NULL);
        int after = a == kMSBDTGLeave ? apple : TGAppleValue();
        if (a != kMSBDTGLeave) ELog(@"tailspin (%@): %@ %s in %s (now %d)", why, a == kMSBDTGWriteFalse ? @"set" : @"took our", kMSBDPDSEAllowKey, kMSBDPDSEDomain, after);
        NSString *mod = nil; int on = TGTailspinOn(&mod);
        TGWriteState(@{ @"checked": @(time(NULL)), @"supported": @(supported), @"keepOff": @((BOOL)(supported && wantOff)), @"owned": @((BOOL)(ownedAfter != 0)),
                        @"allow": @(after), @"tailspinOn": @(on), @"modifier": mod ?: @"", @"why": why ?: @"" });   // (now: the record of our false is right for the next look, whatever the tool does)
        if (supported && wantOff && after == 0 && MSBDTailspinOnBySelfEnablement(on, mod.UTF8String)) {
            if (access(TG_TOOL, X_OK) == 0) TGTurnOff(why, mod);
            else ELog(@"tailspin (%@): on by %@ -- no tailspin tool here: off at perfdiagsselfenabled's next daily run", why, mod);
        }
    }
}
// Removal: our false taken away (iPadOS's default back), whatever the switch says.
static void TGGiveBack(NSString *why) {
    int apple = TGAppleValue();
    if ([TGState()[@"owned"] boolValue] && apple == 0) { TGSetAppleValue(NULL); ELog(@"%@: %s in %s taken away (iPadOS's default back)", why, kMSBDPDSEAllowKey, kMSBDPDSEDomain); }
    unlink(kMSBDTailspinStateFile);
}
// com.apple.da's file watched (cfprefsd replaces it: the watch is armed again on the new file); changes come in bursts, one look 2 s after.
static void TGWatchDomainFile(void) {
    static dispatch_source_t src; static BOOL pending = NO;
    if (src && !dispatch_source_testcancel(src)) return;
    int fd = open(TG_DA_FILE, O_EVTONLY | O_CLOEXEC);
    if (fd < 0) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 600 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ TGWatchDomainFile(); }); return; }   // (no file yet)
    src = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, fd, DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_REVOKE, dispatch_get_main_queue());
    dispatch_source_set_event_handler(src, ^{   // (the static, not a capture: a cancelled source is not kept alive by its own handler)
        unsigned long got = dispatch_source_get_data(src);
        if (got & (DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_REVOKE)) dispatch_source_cancel(src);
        if (pending) return;
        pending = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ pending = NO; TGWatchDomainFile(); TGApply(@"com.apple.da changed"); });
    });
    dispatch_source_set_cancel_handler(src, ^{ close(fd); });
    dispatch_resume(src);
}
static void TGStart(void) {
    int t1 = 0, t2 = 0;
    notify_register_dispatch(kMSBDTailspinChanged, &t1, dispatch_get_main_queue(), ^(int t) { TGApply(@"the switch changed"); });
    notify_register_dispatch("com.apple.da.tasking_changed", &t2, dispatch_get_main_queue(), ^(int t) { TGApply(@"iPadOS's diagnostics tasking changed"); });
    TGApply(@"the helper started");
    TGWatchDomainFile();
}
