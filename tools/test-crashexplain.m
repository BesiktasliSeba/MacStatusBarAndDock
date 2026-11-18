// test-crashexplain.m -- Mac test of common/CrashExplain.h: the guard's explanation, the Report a Problem text (crash summary, tester lines, the
// link's length) and the note about another tweak's crash (dpkg lookup, cache, 24 h). Run: tools/test-crashexplain.sh
#ifndef MSBD_TEST_EXPLAIN_H   // (1.8.7.7: another copy -- the code before the fix, whose new checks must fail)
#define MSBD_TEST_EXPLAIN_H "../common/CrashExplain.h"
#endif
#import MSBD_TEST_EXPLAIN_H
static int fails = 0, total = 0;
static void Check(NSString *what, BOOL ok, NSString *got) {
    total++; if (!ok) fails++;
    printf("%s  %-58s %s\n", ok ? "PASS" : "FAIL", what.UTF8String, got.UTF8String ?: "(nil)");
}
static void Write(const char *path, NSString *text) { [text writeToFile:@(path) atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
static NSString *Stamp(NSTimeInterval ago) {
    NSDateFormatter *df = [NSDateFormatter new]; df.dateFormat = @"yyyy-MM-dd-HHmmss"; df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    return [df stringFromDate:[NSDate dateWithTimeIntervalSinceNow:-ago]];
}
int main(int argc, char **argv) {
    @autoreleasepool {
        BOOL untested = argc > 1 && strcmp(argv[1], "untested") == 0;
        if (untested) MSBDGatePublish(MSBD_GATE_FAKE_STATE, 26);   // (test build: acts as iPadOS 26 -- 17 counts as tested since 24 Oct, 18 since 1.6.0)
        long now = (long)time(NULL);
        NSString *s;
        // 1. The explanation.
        Write(MSBD_GUARD_RECORD, [NSString stringWithFormat:@"time %ld\naction 1\ntested 1\nios 16.5\nbuild 1.0.0\nverdict 1\nblamed MacStatusBarCore.dylib_(faulting_thread)\nswitch com.besiktasliseba.macstatusbar macBanners Mac-Style Banners\nframe MacStatusBarCore.dylib -[MSBBanner layout] + 40\nframe MacStatusBarCore.dylib + 0x4d2\n", now - 7200]);
        s = MSBDGuardExplanation(1, NO, NO);
        Check(@"footer, one switch", [s isEqualToString:@"SpringBoard crashed twice after “Mac-Style Banners” was turned on, so it was turned off. If this keeps happening, tap Report a Problem."], s);
        s = MSBDGuardExplanation(1, NO, YES);
        Check(@"alert, one switch", [s hasSuffix:@"tap Report a Problem in Settings."], s);
        Check(@"alert title, one switch", [MSBDGuardAlertTitle(1) isEqualToString:@"Feature Turned Off"], MSBDGuardAlertTitle(1));
        Write(MSBD_GUARD_RECORD, [NSString stringWithFormat:@"time %ld\naction 1\ntested 1\nverdict 1\nblamed x\nswitch d a Dock Magnification\nswitch d b Mac-Style Banners\nswitch d c Seconds\n", now]);
        s = MSBDGuardExplanation(1, NO, NO);
        Check(@"footer, three switches", [s hasPrefix:@"SpringBoard crashed twice after “Dock Magnification”, “Mac-Style Banners” and “Seconds” were turned on, so they were turned off."], s);
        Check(@"alert title, several", [MSBDGuardAlertTitle(1) isEqualToString:@"Features Turned Off"], MSBDGuardAlertTitle(1));
        Write(MSBD_GUARD_RECORD, [NSString stringWithFormat:@"time %ld\naction 1\ntested 1\nverdict 1\nblamed x\nswitch com.besiktasliseba.macpagedots enabled\n", now]);
        s = MSBDGuardExplanation(1, NO, NO);
        Check(@"untitled (inverted) switch: neutral words", [s hasPrefix:@"The settings you changed last were undone after SpringBoard crashed twice."], s);
        Check(@"alert title, untitled switch", [MSBDGuardAlertTitle(1) isEqualToString:@"Settings Undone"], MSBDGuardAlertTitle(1));
        // Menu Bar Size (a size, no switch: step 1 since 1.8.7.5, audit L62, and step 1b's own target) -- the review of 1.8.7.5
        NSString *sizeLine = @"switch com.besiktasliseba.macstatusbar menuBarSize Menu Bar Size\n";
        Write(MSBD_GUARD_RECORD, [NSString stringWithFormat:@"time %ld\naction 1\ntested 1\nverdict 2\nblamed Apple_code_only\n%@", now, sizeLine]);
        s = MSBDGuardExplanation(1, NO, NO);
        Check(@"footer, Menu Bar Size: set back to Small, no switch words", [s isEqualToString:@"SpringBoard crashed twice after a larger Menu Bar Size was picked, so it was set back to Small. If this keeps happening, tap Report a Problem."], s);
        s = MSBDGuardExplanation(1, NO, YES);
        Check(@"alert, Menu Bar Size", [s isEqualToString:@"SpringBoard crashed twice after a larger Menu Bar Size was picked, so it was set back to Small. If this keeps happening, tap Report a Problem in Settings."], s);
        Check(@"alert title, Menu Bar Size", [MSBDGuardAlertTitle(1) isEqualToString:@"Menu Bar Size Set Back"], MSBDGuardAlertTitle(1));
        Check(@"Report a Problem, Menu Bar Size", [MSBDGuardActionWords(MSBDCrashRecord()) isEqualToString:@"set Menu Bar Size back to Small"], MSBDGuardActionWords(MSBDCrashRecord()));
        Write(MSBD_GUARD_RECORD, [NSString stringWithFormat:@"time %ld\naction 1\ntested 1\nverdict 2\nblamed x\nswitch com.besiktasliseba.macstatusbar wifiMenu Wi-Fi Menu\n%@", now, sizeLine]);
        s = MSBDGuardExplanation(1, NO, NO);
        Check(@"footer, a switch and Menu Bar Size", [s hasPrefix:@"SpringBoard crashed twice after “Wi-Fi Menu” was turned on and a larger Menu Bar Size was picked, so “Wi-Fi Menu” was turned off and Menu Bar Size was set back to Small."], s);
        Check(@"alert title, a switch and Menu Bar Size", [MSBDGuardAlertTitle(1) isEqualToString:@"Features Turned Off"], MSBDGuardAlertTitle(1));
        Check(@"Report a Problem, a switch and Menu Bar Size", [MSBDGuardActionWords(MSBDCrashRecord()) isEqualToString:@"turned off “Wi-Fi Menu”, set Menu Bar Size back to Small"], MSBDGuardActionWords(MSBDCrashRecord()));
        Write(MSBD_GUARD_RECORD, [NSString stringWithFormat:@"time %ld\naction 4\ntested 1\nverdict 1\nblamed MacStatusBarCore.dylib_(faulting_thread)\nfeature com.besiktasliseba.macstatusbar menuBarSize 0 Menu Bar Size|the larger menu bar\n", now]);
        s = MSBDGuardExplanation(4, NO, NO);
        Check(@"step 1b, Menu Bar Size: set back to Small", [s hasPrefix:@"SpringBoard crashed twice in the larger menu bar, so Menu Bar Size was set back to Small."], s);
        Check(@"step 1b alert title, Menu Bar Size", [MSBDGuardAlertTitle(4) isEqualToString:@"Menu Bar Size Set Back"], MSBDGuardAlertTitle(4));
        Check(@"step 1b Report a Problem, Menu Bar Size", [MSBDGuardActionWords(MSBDCrashRecord()) isEqualToString:@"set Menu Bar Size back to Small (only what crashed)"], MSBDGuardActionWords(MSBDCrashRecord()));
        Write(MSBD_GUARD_RECORD, [NSString stringWithFormat:@"time %ld\naction 4\ntested 1\nverdict 1\nblamed x\nfeature com.besiktasliseba.macstatusbar macBanners 0 Mac-Style Banners|the Mac-style banners\n", now]);
        s = MSBDGuardExplanation(4, NO, NO);
        Check(@"step 1b, a switch: as before", [s hasPrefix:@"SpringBoard crashed twice in the Mac-style banners, so “Mac-Style Banners” was turned off."] && [MSBDGuardAlertTitle(4) isEqualToString:@"Feature Turned Off"], s);
        Write(MSBD_GUARD_RECORD, [NSString stringWithFormat:@"time %ld\naction 2\ntested 1\nverdict 1\nblamed x\n", now]);
        s = MSBDGuardExplanation(1, NO, NO);
        Check(@"action 1 but the record is of another action: plain words", [s hasPrefix:@"The features you turned on last were turned off"], s);
        s = MSBDGuardExplanation(2, NO, NO);
        Check(@"safe mode footer", [s isEqualToString:@"MacStatusBar&Dock was turned off after SpringBoard crashed twice. Tap Turn Back On to try again, or Report a Problem."], s);
        s = MSBDGuardExplanation(3, NO, YES);
        Check(@"safe mode alert, kept crashing", [s isEqualToString:@"MacStatusBar&Dock was turned off because SpringBoard kept crashing. To try again, tap Turn Back On in Settings."], s);
        s = MSBDGuardExplanation(2, YES, NO);
        Check(@"untested footer", [s hasSuffix:@"Turn on Enable Anyway to try again, or tap Report a Problem."], s);
        s = MSBDGuardExplanation(2, YES, YES);
        Check(@"untested alert", [s hasSuffix:@"To try again, turn on Enable Anyway in Settings."], s);
        Check(@"nothing done: nil", MSBDGuardExplanation(0, NO, NO) == nil, @"");
        // 2. The Report a Problem text.
        Write(MSBD_GUARD_RECORD, [NSString stringWithFormat:@"time %ld\naction 2\ntested %d\nios 16.5\nbuild 1.0.0\nverdict 1\nblamed MacStatusBarCore.dylib_(faulting_thread)\nframe MacStatusBarCore.dylib -[MSBBanner layout] + 40\nframe MacStatusBarCore.dylib + 0x4d2\nframe MacStatusBarCore.dylib + 0x1\nframe MacStatusBarCore.dylib + 0x2\nframe MacStatusBarCore.dylib + 0x3\nload 1\nshown 2\n", now - 3 * 86400, untested ? 0 : 1]);
        NSURL *url = MSBDReportProblemURL(@"aerial");
        NSString *body = [[NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems.firstObject value];
        printf("---- report body (%lu chars in the link) ----\n%s\n----\n", (unsigned long)url.absoluteString.length, body.UTF8String);
        Check(@"summary: our part", [body containsString:@"- Our part involved: MacStatusBarCore\n"], @"");
        Check(@"summary: guard action", [body containsString:untested ? @"switched Enable Anyway off, 3 days ago" : @"turned MacStatusBar&Dock off (safe mode), 3 days ago"], @"");
        Check(@"summary: 5 frames, ours only", [body containsString:@"MacStatusBarCore.dylib -[MSBBanner layout] + 40\n"] && [body containsString:@"+ 0x3\n```"], @"");
        Check(@"engine version from dpkg", [body containsString:@"- Window engine: Aerial 5.0.1\n"], @"");
        Check(@"our version from dpkg", [body containsString:@"- MacStatusBar&Dock: 1.0.0\n"], @"");
        Check(@"link length safe", url.absoluteString.length <= 6000, [@(url.absoluteString.length) stringValue]);
        Check(@"\"+\" sent as %2B (GitHub reads a bare + as a space)", ![url.query containsString:@"+"] && [url.query containsString:@"%2B%200x4d2"], @"");
        if (untested) {
            Check(@"tester: untested version + Enable Anyway", [body containsString:@"- Untested iPadOS "] && [body containsString:@"(test build acting as 26), Enable Anyway: Off\n"], @"");
            Check(@"tester: switches on (names only)", [body containsString:@"- Switches on: "], @"");
            Check(@"tester: the Windows & Multitasking page's switches first (1.6.0: its own plist)", [body containsString:@"- Switches on: Enable Windowing, "], @"");
        } else Check(@"no tester lines on a tested version", ![body containsString:@"Untested"], @"");
        Check(@"nothing personal: no paths", ![body containsString:@"/var/"] && ![body containsString:@"/Users/"] && ![body containsString:@"/private/"], @"");
        Write(MSBD_GUARD_RECORD, [NSString stringWithFormat:@"time %ld\naction 2\ntested 1\nverdict 1\nblamed x\n", now - 8 * 86400]);
        Check(@"record 8 days old: no summary", MSBDReportCrashSummary(5) == nil, @"");
        unlink(MSBD_GUARD_RECORD);
        Check(@"no record: no summary", MSBDReportCrashSummary(5) == nil, @"");
        Write(MSBD_GUARD_RECORD, [NSString stringWithFormat:@"time %ld\naction 1\ntested 1\nverdict 2\nblamed Apple_code_only\n", now]);
        Check(@"Apple-only: \"not known\", never \"none of ours\" (1.8.7.7)", [MSBDReportCrashSummary(5) containsString:@"- Our part involved: not known: only Apple code on the crashing stack\n"], MSBDReportCrashSummary(5));
        Write(MSBD_GUARD_RECORD, [NSString stringWithFormat:@"time %ld\naction 1\ntested 1\nverdict 1\nblamed MacStatusBarSettings.dylib_(exception_backtrace)\n", now]);
        Check(@"a Settings part", [MSBDReportCrashSummary(5) containsString:@"MacStatusBarSettings (a Settings part)"], @"");
        NSMutableString *big = [NSMutableString stringWithFormat:@"time %ld\naction 2\ntested 1\nverdict 1\nblamed MacDock.dylib_(faulting_thread)\n", now];
        for (int i = 0; i < 5; i++) [big appendFormat:@"frame MacStatusBarCore.dylib %@ + 1\n", [@"" stringByPaddingToLength:1400 withString:@"x" startingAtIndex:0]];
        Write(MSBD_GUARD_RECORD, big);
        url = MSBDReportProblemURL(nil);
        Check(@"oversized frames: link shrinks to fit", url.absoluteString.length <= 6000, [@(url.absoluteString.length) stringValue]);
        unlink(MSBD_GUARD_RECORD);
        // 3. Another tweak's crash.
        NSString *path = @"/private/preboot/ABCDEF/jb-XYZ/procursus/Library/MobileSubstrate/DynamicLibraries/SomeOtherTweak.dylib_(faulting_thread)";
        Write(MSBD_GUARD_VERDICTS, [NSString stringWithFormat:@"SpringBoard-%@.ips 1 MacStatusBarCore.dylib_(faulting_thread)\nSpringBoard-%@.ips 3 %@\n", Stamp(7200), Stamp(3600), path]);
        s = MSBDOtherTweakCrashNote();
        Check(@"other tweak: package name from dpkg", [s isEqualToString:@"The last SpringBoard crash came from “Some Other Tweak”."], s);
        Check(@"name cached", [[NSString stringWithContentsOfFile:@MSBD_TWEAKNAME_CACHE encoding:NSUTF8StringEncoding error:nil] containsString:@"\tSome Other Tweak"], @"");
        Write(MSBD_GUARD_VERDICTS, [NSString stringWithFormat:@"SpringBoard-%@.ips 3 /var/jb/usr/lib/TweakInject/Unpackaged.dylib_(faulting_thread)\n", Stamp(600)]);
        s = MSBDOtherTweakCrashNote();
        Check(@"no package: the dylib's name", [s isEqualToString:@"The last SpringBoard crash came from “Unpackaged”."], s);
        Write(MSBD_GUARD_VERDICTS, [NSString stringWithFormat:@"SpringBoard-%@.ips 3 /var/jb/usr/lib/TweakInject/X.dylib_(faulting_thread)\n", Stamp(25 * 3600)]);
        Check(@"older than 24 h: nothing", MSBDOtherTweakCrashNote() == nil, @"");
        Write(MSBD_GUARD_VERDICTS, [NSString stringWithFormat:@"SpringBoard-%@.ips 3 %@\nSpringBoard-%@.ips 2 Apple_code_only\n", Stamp(3600), path, Stamp(60)]);
        Check(@"latest crash Apple-only: nothing", MSBDOtherTweakCrashNote() == nil, @"");
        Write(MSBD_GUARD_VERDICTS, [NSString stringWithFormat:@"SpringBoard-%@.ips 3 %@\nSpringBoard-%@.ips 0 unreadable\n", Stamp(3600), path, Stamp(60)]);
        Check(@"latest crash unreadable: nothing", MSBDOtherTweakCrashNote() == nil, @"");
        Write(MSBD_GUARD_VERDICTS, [NSString stringWithFormat:@"SpringBoard-%@.test.ips 3 %@\n", Stamp(5), path]);
        Check(@"the test report's verdict line counts too", MSBDOtherTweakCrashNote() != nil, MSBDOtherTweakCrashNote());
        unlink(MSBD_GUARD_VERDICTS);
        Check(@"no verdicts: nothing", MSBDOtherTweakCrashNote() == nil, @"");

#if MSBD_EXPLAIN_CAUSES
        // 4. 1.8.7.7 (GitHub #14): what crashed, in words. The verdict file's lines carry "\t<cause>\t<where>\t<n> <other tweaks>" now.
        NSMutableArray<NSString *> *said = [NSMutableArray array];   // (everything shown below: never "none of ours")
        Write(MSBD_GUARD_VERDICTS, [NSString stringWithFormat:@"SpringBoard-%@.ips 3 %@\tEXC_CRASH (SIGSEGV)\t-[_MTLCommandBuffer waitUntilCompleted] (Metal)\t2 SomeOtherTweak.dylib, X.dylib\n", Stamp(600), path]);
        s = MSBDOtherTweakCrashNote(); [said addObject:s ?: @""];
        Check(@"another tweak's crash, a line with its cause: its name", [s isEqualToString:@"The last SpringBoard crash came from “Some Other Tweak”."], s);
        NSString *pop = [NSString stringWithFormat:@"SpringBoard-%@.ips 4 Apple_code_only;_3_other_tweaks_loaded\tNSGenericException: UIPopoverPresentationController (<UIPopoverPresentationController: 0x10a1b2c00>) should have a non-nil sourceView or barButtonItem set before the presentation occurs.\t-[UIPopoverPresentationController presentationTransitionWillBegin] (UIKitCore)\t3 OtherTweakA.dylib, OtherTweakB.dylib, OtherTweakC.dylib\n", Stamp(300)];
        Write(MSBD_GUARD_VERDICTS, [NSString stringWithFormat:@"SpringBoard-%@.ips 3 %@\tEXC_CRASH (SIGSEGV)\t\t0 \n%@", Stamp(600), path, pop]);
        s = MSBDOtherTweakCrashNote(); [said addObject:s ?: @""];
        Check(@"the last crash not pinned on anyone: the quiet note with its cause", [s isEqualToString:@"The last SpringBoard crash could not be pinned on MacStatusBar&Dock or another tweak: NSGenericException: UIPopoverPresentationController (<UIPopoverPresentationController: 0x10a1b2c00>) should have a non-nil sourceView or barButtonItem set before the presentation occurs."], s);
        Write(MSBD_GUARD_VERDICTS, [NSString stringWithFormat:@"SpringBoard-%@.ips 4 Apple_code_only;_1_other_tweak_loaded\tNSInternalInconsistencyException: could not open /var/mobile/Library/Notes/private.txt for file:///var/mobile/Media/DCIM/x.jpg\t\t1 T.dylib\n", Stamp(60)]);
        s = MSBDOtherTweakCrashNote(); [said addObject:s ?: @""];
        Check(@"  ... the user's paths in a reason become <path>", [s containsString:@"could not open <path> for <path>"] && ![s containsString:@"/var/mobile"] && ![s containsString:@"file:"], s);
        Write(MSBD_GUARD_VERDICTS, [NSString stringWithFormat:@"SpringBoard-%@.ips 4 watchdog:Apple_code_only;_1_other_tweak_loaded\tstuck, ended by the watchdog: monitoring timed out for service\t\t1 T.dylib\n", Stamp(60)]);
        s = MSBDOtherTweakCrashNote(); [said addObject:s ?: @""];
        Check(@"  ... stuck, not pinned on anyone", [s hasPrefix:@"SpringBoard last got stuck and the system restarted it; that could not be pinned on MacStatusBar&Dock or another tweak: stuck, ended by the watchdog"], s);
        Write(MSBD_GUARD_VERDICTS, [NSString stringWithFormat:@"SpringBoard-%@.ips 2 Apple_code_only\tEXC_BAD_ACCESS (SIGSEGV)\t\t0 \n", Stamp(60)]);
        Check(@"the last crash Apple-only with nothing else loaded: no note (it counted as ours)", MSBDOtherTweakCrashNote() == nil, @"");
        // the guard's record with the new lines: the summary's Cause / Where / Other tweaks; the notice's Cause line; the loop breaker's words
        NSString *recPop = [NSString stringWithFormat:@"time %ld\naction 1\ntested 1\nios 16.3.1\nbuild 1.8.7.7\nverdict 4\nblamed Apple_code_only;_3_other_tweaks_loaded\ncause NSGenericException: UIPopoverPresentationController (<UIPopoverPresentationController: 0x10a1b2c00>) should have a non-nil sourceView or barButtonItem set before the presentation occurs.\nwhere -[UIPopoverPresentationController presentationTransitionWillBegin] (UIKitCore)\nothers 3 OtherTweakA.dylib, OtherTweakB.dylib, OtherTweakC.dylib\nunknown 2\nswitch com.besiktasliseba.macstatusbar macBanners Mac-Style Banners\n", now];
        Write(MSBD_GUARD_RECORD, recPop);
        NSString *sum = MSBDReportCrashSummary(5); [said addObject:sum ?: @""];
        Check(@"summary: our part \"not known\", other tweaks loaded", [sum containsString:@"- Our part involved: not known: only Apple code on the crashing stack, other tweaks loaded\n"], sum);
        Check(@"summary: the cause (cut at 200)", [sum containsString:@"- Cause: NSGenericException: UIPopoverPresentationController (<UIPopoverPresentationController: 0x10a1b2c00>) should have a non-nil sourceView"], sum);
        Check(@"summary: where", [sum containsString:@"- Where: -[UIPopoverPresentationController presentationTransitionWillBegin] (UIKitCore)\n"], sum);
        Check(@"summary: the other tweaks loaded, by name", [sum containsString:@"- Other tweaks loaded: 3 (OtherTweakA.dylib, OtherTweakB.dylib, OtherTweakC.dylib)\n"], sum);
        s = MSBDGuardNoticeCause(); [said addObject:s ?: @""];
        Check(@"notice: one Cause line, at most 120 characters", [s hasPrefix:@"Cause: NSGenericException: UIPopoverPresentationController"] && s.length <= 7 + 121, s);
        Write(MSBD_GUARD_RECORD, [NSString stringWithFormat:@"time %ld\naction 2\ntested 1\nverdict 1\nblamed MacStatusBarCore.dylib_(faulting_thread)\nframe MacStatusBarCore.dylib + 0x1\n", now]);
        sum = MSBDReportCrashSummary(5); [said addObject:sum ?: @""];
        Check(@"an old record (no cause lines): the summary as before", ![sum containsString:@"- Cause:"] && ![sum containsString:@"- Where:"] && ![sum containsString:@"- Other tweaks"] && [sum containsString:@"- Our part involved: MacStatusBarCore\n"], sum);
        Check(@"  ... and no Cause line on the notice", MSBDGuardNoticeCause() == nil, @"");
        for (int a = 2; a <= 3; a++) for (int u = 0; u <= 1; u++) for (int al = 0; al <= 1; al++) {
            Write(MSBD_GUARD_RECORD, [NSString stringWithFormat:@"time %ld\naction %d\ntested %d\nverdict 4\nblamed Apple_code_only;_2_other_tweaks_loaded\nunknown 4\nloop 1\n", now, a, !u]);
            s = MSBDGuardExplanation(a, u, al); [said addObject:s ?: @""];
            NSString *want = [@"SpringBoard kept crashing and the crashes could not be pinned on MacStatusBar&Dock or another tweak, so MacStatusBar&Dock was turned off to stop the loop. If SpringBoard still crashes with it off, it was not MacStatusBar&Dock: "
                              stringByAppendingString:u ? (al ? @"turn on Enable Anyway in Settings." : @"turn on Enable Anyway.") : (al ? @"tap Turn Back On in Settings." : @"tap Turn Back On.")];
            Check([NSString stringWithFormat:@"loop breaker words (action %d, %@, %@)", a, u ? @"untested" : @"tested", al ? @"notice" : @"footer"], [s isEqualToString:want], s);
        }
        Check(@"loop breaker: notice title", [MSBDGuardAlertTitle(2) isEqualToString:@"MacStatusBar&Dock Turned Off"], MSBDGuardAlertTitle(2));
        s = MSBDGuardActionWords(MSBDCrashRecord()); [said addObject:s ?: @""];
        Check(@"loop breaker: Report a Problem's guard line", [s hasSuffix:@" to stop a crash loop nothing could be pinned on"], s);
        // Report a Problem: the crashes of the last 24 h (also without a guard record), and the link's length with a long reason and 10 other tweaks
        unlink(MSBD_GUARD_RECORD);
        NSMutableString *ten = [NSMutableString string];
        for (int i = 0; i < 10; i++) [ten appendFormat:@"%@LongOtherTweakName%02d.dylib", i ? @", " : @"", i];
        NSString *longReason = [@"NSInternalInconsistencyException: " stringByAppendingString:[@"" stringByPaddingToLength:420 withString:@"reason " startingAtIndex:0]];
        NSMutableString *vf = [NSMutableString string];
        for (int i = 0; i < 7; i++) [vf appendFormat:@"SpringBoard-%@.ips %d %@\t%@\t-[SBSomething crashed] (SpringBoard)\t10 %@\n", Stamp(1000 + i * 600), i % 2 ? 4 : 3, i % 2 ? @"Apple_code_only;_10_other_tweaks_loaded" : path, longReason, ten];
        [vf appendFormat:@"SpringBoard-%@.ips 1 MacStatusBarCore.dylib_(faulting_thread)\tEXC_BAD_ACCESS (SIGSEGV)\tDMStageLights (MacStatusBarCore.dylib)\t0 \n", Stamp(200)];
        [vf appendFormat:@"SpringBoard-%@.ips 4 Apple_code_only;_1_other_tweak_loaded\told one\t\t1 T.dylib\n", Stamp(30 * 3600)];
        Write(MSBD_GUARD_VERDICTS, vf);
        NSString *recent = MSBDReportRecentCrashes(5, 200); [said addObject:recent ?: @""];
        Check(@"recent crashes: newest first, ours named, at most 5, the rest counted", [recent hasPrefix:@"\n**Recent SpringBoard crashes** (24 h)\n- "] && [[recent componentsSeparatedByString:@"\n- "] count] == 7
              && [recent containsString:@": MacStatusBar&Dock -- EXC_BAD_ACCESS (SIGSEGV)\n"] && [recent containsString:@"- and 3 more\n"] && ![recent containsString:@"old one"], recent);
        Check(@"recent crashes: another tweak's by library name, never a path", [recent containsString:@": another tweak (SomeOtherTweak.dylib) -- "] && ![recent containsString:@"/var/"] && ![recent containsString:@"/private/"], recent);
        Check(@"recent crashes: not pinned on anyone", [recent containsString:@": not pinned (only Apple code on the stack, other tweaks loaded) -- NSInternalInconsistencyException"], recent);
        Write(MSBD_GUARD_RECORD, [recPop stringByReplacingOccurrencesOfString:@"others 3 OtherTweakA.dylib, OtherTweakB.dylib, OtherTweakC.dylib" withString:[NSString stringWithFormat:@"others 10 %@", ten]]);
        url = MSBDReportProblemURL(@"aerial");
        body = [[NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems.firstObject value]; [said addObject:body ?: @""];
        Check(@"the link with the crashes and 10 other tweaks: at most 6000 characters", url.absoluteString.length <= 6000, [@(url.absoluteString.length) stringValue]);
        Check(@"  ... the crashes of the last 24 h in it, and the summary's Cause", [body containsString:@"**Recent SpringBoard crashes** (24 h)"] && [body containsString:@"- Cause: "], body);
        Check(@"  ... nothing personal: no paths", ![body containsString:@"/var/"] && ![body containsString:@"/Users/"] && ![body containsString:@"/private/"], @"");
        unlink(MSBD_GUARD_RECORD);
        Write(MSBD_GUARD_VERDICTS, [NSString stringWithFormat:@"SpringBoard-%@.ips 4 Apple_code_only;_3_other_tweaks_loaded\tEXC_CRASH (SIGABRT): uncaught exception, its reason not in the report\t\t3 A.dylib, B.dylib, C.dylib\n", Stamp(120)]);
        url = MSBDReportProblemURL(nil);
        body = [[NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems.firstObject value]; [said addObject:body ?: @""];
        Check(@"no guard record (the guard did nothing): the recent crashes still listed", ![body containsString:@"Crash summary"] && [body containsString:@": not pinned (only Apple code on the stack, other tweaks loaded) -- EXC_CRASH (SIGABRT)"], body);
        {   // (review of 1.8.7.7) a crash on its own (SpringBoard had run a minute, the next start did not crash early) is never judged: our death
            // record's line is all there is of it (#14's crash 4 on 16.3.1). Report a Problem lists it; a line of a judged report is not listed twice.
            NSString *pre = [NSString stringWithFormat:@"%ld\t%ld\tmain\tNSGenericException\tUIPopoverPresentationController should have a non-nil sourceView\tNSException\n", 24305L, now - 121];
            NSString *lone = [NSString stringWithFormat:@"%ld\t%ld\tother\tNSInvalidArgumentException\tan earlier exception of that SpringBoard (handled)\tNSException\n%ld\t%ld\tother\tNSInvalidArgumentException\t-[OtherTweakListener stateService:didReceiveDoNotDisturbStateUpdate:]: unrecognized selector sent to instance 0x283a1c0c0 reading /var/mobile/Library/Preferences/x.plist\tNSException\n",
                              24393L, now - 3700, 24393L, now - 3600];
            NSString *old = [NSString stringWithFormat:@"%ld\t%ld\tmain\tNSRangeException\ttoo old\tNSException\nbroken line\n", 20000L, now - 30 * 3600];
            Write(MSBD_CAUSE_FILE, [NSString stringWithFormat:@"%@%@%@", old, pre, lone]);
            recent = MSBDReportRecentCrashes(5, 200); [said addObject:recent ?: @""];
            Check(@"a crash the guard never judged: listed from our death record, its reason, newest first", [recent containsString:@": not judged (not in a row of crashes) -- NSInvalidArgumentException: -[OtherTweakListener stateService:didReceiveDoNotDisturbStateUpdate:]: unrecognized selector"]
                  && [recent rangeOfString:@"EXC_CRASH (SIGABRT)"].location < [recent rangeOfString:@"not judged"].location, recent);
            Check(@"  ... the last line of that SpringBoard only, its paths as <path>", ![recent containsString:@"an earlier exception"] && [recent containsString:@"reading <path>"] && ![recent containsString:@"/var/mobile"], recent);
            Check(@"  ... a line of a judged report not listed twice; older than 24 h and broken lines left out", ![recent containsString:@"non-nil sourceView"] && ![recent containsString:@"too old"] && [[recent componentsSeparatedByString:@"\n- "] count] == 3, recent);
            url = MSBDReportProblemURL(nil);
            body = [[NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems.firstObject value]; [said addObject:body ?: @""];
            Check(@"  ... in the Report a Problem link, no guard record needed", [body containsString:@": not judged (not in a row of crashes) -- NSInvalidArgumentException: -[OtherTweakListener"] && ![body containsString:@"/var/"], body);
            unlink(MSBD_GUARD_VERDICTS);
            recent = MSBDReportRecentCrashes(5, 200); [said addObject:recent ?: @""];
            Check(@"  ... no verdicts at all: the death record's crashes of 24 h listed (both SpringBoards)", [[recent componentsSeparatedByString:@"\n- "] count] == 3 && [recent containsString:@"non-nil sourceView"] && [recent containsString:@"not judged"], recent);
            Check(@"  ... the quiet note unchanged: judged crashes only", MSBDOtherTweakCrashNote() == nil, MSBDOtherTweakCrashNote());
            unlink(MSBD_CAUSE_FILE);
        }
        {   // a file of the guard's that is not valid UTF-8 (a build that cut a cause inside a character) is still read, byte for byte
            NSMutableData *bad = [[[NSString stringWithFormat:@"SpringBoard-%@.ips 4 Apple_code_only;_1_other_tweak_loaded\tNSGenericException: caf", Stamp(90)] dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
            [bad appendBytes:"\xc3\t\t1 T.dylib\n" length:12];
            [bad writeToFile:@MSBD_GUARD_VERDICTS atomically:YES];
            s = MSBDOtherTweakCrashNote(); [said addObject:s ?: @""];
            Check(@"a verdict file cut inside a character: still read (the note there)", [s hasPrefix:@"The last SpringBoard crash could not be pinned on MacStatusBar&Dock or another tweak: NSGenericException: caf"], s);
        }
        unlink(MSBD_GUARD_VERDICTS);
        Check(@"nothing above says \"none of ours\"", ![[said componentsJoinedByString:@"\n"] containsString:@"none of ours"], @"");
        Check(@"CrashExplain.h's words: no \"none of ours\" left", ![[NSString stringWithContentsOfFile:@"../common/CrashExplain.h" encoding:NSUTF8StringEncoding error:nil] containsString:@"@\"none of ours"], @"");
#else
        Check(@"what crashed in words (cause, where, other tweaks, recent crashes, loop breaker)", NO, @"not in this code");
#endif
    }
    printf("%d/%d passed\n", total - fails, total);
    return fails ? 1 : 0;
}
