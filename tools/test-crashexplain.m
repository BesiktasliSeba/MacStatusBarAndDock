// test-crashexplain.m -- Mac test of common/CrashExplain.h: the guard's explanation, the Report a Problem text (crash summary, tester lines, the
// link's length) and the note about another tweak's crash (dpkg lookup, cache, 24 h). Run: tools/test-crashexplain.sh
#import "../common/CrashExplain.h"
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
        if (untested) MSBDGatePublish(MSBD_GATE_FAKE_STATE, 17);   // (test build: acts as iPadOS 17)
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
            Check(@"tester: untested version + Enable Anyway", [body containsString:@"- Untested iPadOS "] && [body containsString:@"(test build acting as 17), Enable Anyway: Off\n"], @"");
            Check(@"tester: switches on (names only)", [body containsString:@"- Switches on: "], @"");
        } else Check(@"no tester lines on a tested version", ![body containsString:@"Untested"], @"");
        Check(@"nothing personal: no paths", ![body containsString:@"/var/"] && ![body containsString:@"/Users/"] && ![body containsString:@"/private/"], @"");
        Write(MSBD_GUARD_RECORD, [NSString stringWithFormat:@"time %ld\naction 2\ntested 1\nverdict 1\nblamed x\n", now - 8 * 86400]);
        Check(@"record 8 days old: no summary", MSBDReportCrashSummary(5) == nil, @"");
        unlink(MSBD_GUARD_RECORD);
        Check(@"no record: no summary", MSBDReportCrashSummary(5) == nil, @"");
        Write(MSBD_GUARD_RECORD, [NSString stringWithFormat:@"time %ld\naction 1\ntested 1\nverdict 2\nblamed Apple_code_only\n", now]);
        Check(@"Apple-only: part named as none of ours", [MSBDReportCrashSummary(5) containsString:@"none of ours on the crashing stack"], @"");
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
    }
    printf("%d/%d passed\n", total - fails, total);
    return fails ? 1 : 0;
}
