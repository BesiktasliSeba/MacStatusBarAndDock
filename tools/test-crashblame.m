// test-crashblame.m -- Mac unit test for common/CrashBlame.h (the crash-report classifier). Run: tools/test-crashblame.sh
// (1.8.7.7: MSBD_TEST_FEATURE_H, another copy of CrashFeature.h -- the code before the fix, whose checks of UNPINNED must fail.)
#ifndef MSBD_TEST_FEATURE_H
#define MSBD_TEST_FEATURE_H "../common/CrashFeature.h"
#endif
#import MSBD_TEST_FEATURE_H   // (CrashBlame.h, and the step 1b lookup of the top frame)
#define VUNPINNED 4   // (kMSBDBlameUnpinned, 1.8.7.7: Apple code only, another tweak loaded -- a number here, so the code before it builds too)
static int failures = 0, total = 0;
static const char *V(int v) { return v == kMSBDBlameOurs ? "OURS" : v == kMSBDBlameApple ? "APPLE" : v == kMSBDBlameOther ? "OTHER" : v == VUNPINNED ? "UNPINNED" : "UNKNOWN"; }
static void Check(NSString *label, int got, NSString *blamed, int want) {
    total++;
    BOOL ok = got == want;
    if (!ok) failures++;
    printf("%s  %-48s %-7s (want %-7s) blamed: %s\n", ok ? "PASS" : "FAIL", label.UTF8String, V(got), V(want), blamed.UTF8String);
}
static void Ok(NSString *label, BOOL ok, NSString *got) {   // (a yes/no check, 1.8.7.7)
    total++;
    if (!ok) failures++;
    printf("%s  %-48s %s\n", ok ? "PASS" : "FAIL", label.UTF8String, got.UTF8String ?: "(nil)");
}
static NSData *Report(NSDictionary *body) {
    NSMutableData *d = [[@"{\"bug_type\":\"309\",\"name\":\"SpringBoard\"}\n" dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [d appendData:[NSJSONSerialization dataWithJSONObject:body options:0 error:nil]];
    return d;
}
static NSDictionary *Img(NSString *path) { return @{@"path": path, @"name": path.lastPathComponent}; }
static NSDictionary *F(int i) { return @{@"imageOffset": @1, @"imageIndex": @(i)}; }
int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *dir = argc > 1 ? @(argv[1]) : @"crash-fixtures";
        NSString *b;
        int v;
        // The three fixtures (synthetic reports in the iOS 16 format).
        v = MSBDBlameReportFile([dir stringByAppendingPathComponent:@"ours-in-faulting-thread.ips"], &b);        Check(@"fixture: ours in faulting thread", v, b, kMSBDBlameOurs);
        v = MSBDBlameReportFile([dir stringByAppendingPathComponent:@"other-tweak.ips"], &b);                    Check(@"fixture: another tweak's crash", v, b, kMSBDBlameOther);
        v = MSBDBlameReportFile([dir stringByAppendingPathComponent:@"apple-only-our-class-in-reason.ips"], &b); Check(@"fixture: Apple only, our class in reason", v, b, kMSBDBlameOurs);
        // Watchdog reports (SpringBoard stuck, killed by the system; stacks only in a "stackshot" with unnamed images, named here by UUID). The fixture
        // is a real one (M1, iOS 15.6.1: our debug mainhang_ test), trimmed to SpringBoard's main thread. Image 2e3ea764... = the stuck code.
        NSString *wd = [dir stringByAppendingPathComponent:@"watchdog-stuck-main.ips"];
        NSString *stuck = @"2e3ea764-a57d-4cf0-a1e4-4263b5c18693";
        gMSBDBlameUUIDOverride = @{stuck: @"/var/jb/usr/lib/MacStatusBarAndDock/MacStatusBarCore.dylib"};
        v = MSBDBlameReportFile(wd, &b);   Check(@"watchdog: stuck in our code (counted)", v, b, kMSBDBlameOurs);
        Check(@"watchdog: blamed says watchdog + stuck main thread", [b hasPrefix:@"watchdog:MacStatusBarCore.dylib"] && [b containsString:@"stuck main thread"] ? 1 : 0, b, 1);
        gMSBDBlameUUIDOverride = @{stuck: @"/var/jb/usr/lib/TweakInject/Aerial.dylib"};
        v = MSBDBlameReportFile(wd, &b);   Check(@"watchdog: stuck in another tweak (not counted)", v, b, kMSBDBlameOther);
        gMSBDBlameUUIDOverride = @{};
        v = MSBDBlameReportFile(wd, &b);   Check(@"watchdog: unnamed code on top (counted)", v, b, kMSBDBlameApple);
        gMSBDBlameUUIDOverride = nil;
        {   // no stackshot at all: unknown, still counted, and said to be a watchdog report
            NSMutableDictionary *m = [[NSJSONSerialization JSONObjectWithData:[[NSData dataWithContentsOfFile:wd] subdataWithRange:NSMakeRange(0, 0)] options:0 error:nil] mutableCopy] ?: [NSMutableDictionary dictionary];
            m[@"termination"] = @{@"namespace": @"WATCHDOG", @"code": @1};
            v = MSBDBlameReportData(Report(m), &b);   Check(@"watchdog: no stacks (unknown, counted)", v, b, kMSBDBlameUnknown);
            Check(@"watchdog: no stacks says watchdog", [b hasPrefix:@"watchdog:"] ? 1 : 0, b, 1);
        }
        // Edge cases.
        NSArray *imgs = @[Img(@"/System/Library/CoreServices/SpringBoard.app/SpringBoard"), Img(@"/usr/lib/system/libsystem_kernel.dylib"),
                          Img(@"/var/jb/Library/MobileSubstrate/DynamicLibraries/MacStatusBar.dylib"), Img(@"/var/jb/usr/lib/SomeLib.dylib"),
                          Img(@"/private/preboot/X/jb-Y/procursus/usr/lib/libellekit.dylib"), Img(@"/var/jb/usr/lib/MacStatusBarAndDock/DockMagnification.dylib"),
                          Img(@"/System/Library/Frameworks/Foundation.framework/Foundation")];
        NSDictionary *(^Body)(NSArray *, id, id) = ^NSDictionary *(NSArray *fault, id exc, id asi) {
            NSMutableDictionary *m = [@{@"faultingThread": @0, @"threads": @[@{@"triggered": @YES, @"frames": fault}], @"usedImages": imgs} mutableCopy];
            if (exc) m[@"lastExceptionBacktrace"] = exc;
            if (asi) m[@"asi"] = asi;
            return m;
        };
        // (1.8.7.7, #14: this image list names another tweak, SomeLib.dylib -- so an Apple-only crash here is UNPINNED, weak; APPLE below, with none)
        v = MSBDBlameReportData(Report(Body(@[F(1), F(0)], nil, nil)), &b);                          Check(@"Apple only, nothing of ours, a tweak loaded", v, b, VUNPINNED);
        v = MSBDBlameReportData(Report(Body(@[F(1), F(4), F(0)], nil, nil)), &b);                    Check(@"ElleKit + Apple only, a tweak loaded", v, b, VUNPINNED);
        // (the top-most non-Apple image decides, 2026-09-26: another tweak's crash with our code lower on the stack is theirs)
        v = MSBDBlameReportData(Report(Body(@[F(1), F(3), F(2), F(0)], nil, nil)), &b);              Check(@"other tweak on top, our loader below", v, b, kMSBDBlameOther);
        v = MSBDBlameReportData(Report(Body(@[F(1), F(0)], @[F(6), F(5), F(0)], nil)), &b);          Check(@"ours only in exception backtrace", v, b, kMSBDBlameOurs);
        v = MSBDBlameReportData(Report(Body(@[F(1), F(3), F(0)], nil, @{@"x": @[@"-[DMStageLights update]: bad"]})), &b); Check(@"other tweak's frame, our class in reason", v, b, kMSBDBlameOurs);
        v = MSBDBlameReportData(Report(Body(@[F(1), F(0)], nil, @{@"x": @[@"-[DMFApp bundleIdentifier]: nil; DMCProfile"]})), &b); Check(@"Apple DMF/DMC classes are not ours", v, b, VUNPINNED);
        v = MSBDBlameReportData(Report(Body(@[F(1), F(0)], nil, @{@"x": @[@"assert in com.besiktasliseba.macstatusbar"]})), &b); Check(@"our pref domain in text", v, b, kMSBDBlameOurs);
        v = MSBDBlameReportData(Report(Body(@[F(1), F(3)], nil, @{@"x": @[@"MSBDGuardEvaluate failed"]})), &b); Check(@"MSBD function name in text", v, b, kMSBDBlameOurs);
        v = MSBDBlameReportData(Report(Body(@[F(1), F(3)], nil, @{@"x": @[@"MSBuffer is not ours"]})), &b); Check(@"MSBuffer (MSB + lowercase) is not ours", v, b, kMSBDBlameOther);
        v = MSBDBlameReportData(Report(Body(@[F(99), @{@"imageOffset": @1}], nil, nil)), &b);        Check(@"frames with no known image", v, b, kMSBDBlameUnknown);
        v = MSBDBlameReportData(Report(@{@"usedImages": imgs}), &b);                                    Check(@"no threads at all", v, b, kMSBDBlameUnknown);
        v = MSBDBlameReportData([@"{\"bug_type\":\"309\"}\n{\"threads\": [ {\"frames\": " dataUsingEncoding:NSUTF8StringEncoding], &b); Check(@"truncated report (being written)", v, b, kMSBDBlameUnknown);
        v = MSBDBlameReportData([@"not json at all" dataUsingEncoding:NSUTF8StringEncoding], &b);     Check(@"garbage", v, b, kMSBDBlameUnknown);
        v = MSBDBlameReportData([NSData data], &b);                                                    Check(@"empty file", v, b, kMSBDBlameUnknown);
        v = MSBDBlameReportFile(@"/nonexistent/SpringBoard-x.ips", &b);                                Check(@"missing file", v, b, kMSBDBlameUnknown);
        v = MSBDBlameReportData(Report(@{@"faultingThread": @"zero", @"threads": @[@"x", @{@"triggered": @YES, @"frames": @[F(5)]}], @"usedImages": @[@1, @"x"]}), &b);
        Check(@"wrong types everywhere, no crash", v, b, kMSBDBlameUnknown);
        // Legacy layout: names only in imageExtraInfo, images without paths.
        v = MSBDBlameReportData(Report(@{@"threads": @[@{@"triggered": @YES, @"frames": @[F(0), F(1)]}], @"legacyInfo": @{@"imageExtraInfo": @[@{@"name": @"libsystem_kernel.dylib"}, @{@"name": @"MacStatusBarCore.dylib"}]}}), &b);
        Check(@"legacy imageExtraInfo names", v, b, kMSBDBlameOurs);
        v = MSBDBlameReportData(Report(@{@"threads": @[@{@"triggered": @YES, @"frames": @[F(0)]}], @"binaryImages": @[@{@"path": @"/var/jb/Library/MobileSubstrate/DynamicLibraries/Foo.dylib"}]}), &b);
        Check(@"legacy binaryImages, other tweak", v, b, kMSBDBlameOther);
        // Dopamine reports the tweak folder's real path (.../procursus/usr/lib/TweakInject): our loader there is ours, another tweak there is not.
        v = MSBDBlameReportData(Report(@{@"threads": @[@{@"triggered": @YES, @"frames": @[F(0), F(1)]}], @"usedImages": @[Img(@"/private/preboot/AB/dopamine-X/procursus/usr/lib/TweakInject/SomeTweak.dylib"), Img(@"/private/preboot/AB/dopamine-X/procursus/usr/lib/TweakInject/MacDock.dylib")]}), &b);
        Check(@"Dopamine TweakInject path, another tweak above our loader", v, b, kMSBDBlameOther);
        v = MSBDBlameReportData(Report(@{@"threads": @[@{@"triggered": @YES, @"frames": @[F(1), F(0)]}], @"usedImages": @[Img(@"/private/preboot/AB/dopamine-X/procursus/usr/lib/TweakInject/SomeTweak.dylib"), Img(@"/private/preboot/AB/dopamine-X/procursus/usr/lib/TweakInject/MacDock.dylib")]}), &b);
        Check(@"Dopamine TweakInject path, our loader on top", v, b, kMSBDBlameOurs);
        v = MSBDBlameReportData(Report(@{@"threads": @[@{@"triggered": @YES, @"frames": @[F(0)]}], @"usedImages": @[Img(@"/private/preboot/AB/dopamine-X/procursus/usr/lib/TweakInject/SomeTweak.dylib")]}), &b);
        Check(@"Dopamine TweakInject path, other tweak", v, b, kMSBDBlameOther);
        // Trailing text after the body (seen in a copied report).
        NSMutableData *trail = [Report(Body(@[F(5)], nil, nil)) mutableCopy]; [trail appendData:[@"\n}\nSpringBoard-2026.ips\n" dataUsingEncoding:NSUTF8StringEncoding]];
        v = MSBDBlameReportData(trail, &b);                                                            Check(@"trailing text after the body", v, b, kMSBDBlameOurs);
        // Top-most non-Apple image, pass-through hooks, window engines (audit 3, finding 1). The map marks DockMagnification 0x100-0x1ff (its
        // -[UIApplication sendEvent:] hook) as transparent.
        {
            NSString *map = @"T transparent transparent\nT part part\nP DockMagnification part\nU DockMagnification 22222222-2222-2222-2222-222222222222 arm64e\nR 0 part\nR 100 transparent\nR 200 part\nR 300 -\n";
            NSMutableArray *im = [imgs mutableCopy];
            im[5] = @{@"path": @"/var/jb/usr/lib/MacStatusBarAndDock/DockMagnification.dylib", @"name": @"DockMagnification.dylib", @"uuid": @"22222222-2222-2222-2222-222222222222"};
            [im addObject:Img(@"/var/jb/usr/lib/TweakInject/Aerial.dylib")];                                  // 7: a window engine we drive
            [im addObject:Img(@"/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore")];            // 8
            NSDictionary *(^G)(int, int) = ^NSDictionary *(int i, int off) { return @{@"imageOffset": @(off), @"imageIndex": @(i)}; };
            NSDictionary *(^B2)(NSArray *, id) = ^NSDictionary *(NSArray *fault, id exc) {
                NSMutableDictionary *m = [@{@"faultingThread": @0, @"threads": @[@{@"triggered": @YES, @"frames": fault}], @"usedImages": im} mutableCopy];
                if (exc) m[@"lastExceptionBacktrace"] = exc;
                return m;
            };
            NSArray *tap = @[G(8, 1), G(5, 0x150), G(8, 2), G(0, 1)];   // UIKit crash <- our sendEvent hook <- UIKit <- SpringBoard
            v = MSBDBlameReportBodyMap(B2(@[G(1, 1), G(3, 1), G(8, 1), G(5, 0x150), G(0, 1)], nil), map, &b);   Check(@"other tweak on top, our sendEvent hook below", v, b, kMSBDBlameOther);
            v = MSBDBlameReportBodyMap(B2(@[G(1, 1), G(3, 1), G(8, 1), G(5, 0x150), G(0, 1)], nil), nil, &b);   Check(@"... the same without a map", v, b, kMSBDBlameOther);
            v = MSBDBlameReportBodyMap(B2(@[G(8, 1), G(5, 0x150), G(3, 1), G(0, 1)], nil), map, &b);           Check(@"UIKit crash, our hook called by another tweak", v, b, kMSBDBlameOther);
            v = MSBDBlameReportBodyMap(B2(tap, nil), map, &b);                                                   Check(@"UIKit crash, only our pass-through hook", v, b, kMSBDBlameOurs);
            v = MSBDBlameReportBodyMap(B2(@[G(8, 1), G(5, 0x50), G(8, 2), G(0, 1)], nil), map, &b);            Check(@"crash under our real Dock code", v, b, kMSBDBlameOurs);
            v = MSBDBlameReportBodyMap(B2(@[G(8, 1), G(5, 0x50), G(5, 0x150), G(3, 1)], nil), map, &b);        Check(@"our real code above our hook and a tweak", v, b, kMSBDBlameOurs);
            v = MSBDBlameReportBodyMap(B2(@[G(7, 1), G(8, 1), G(5, 0x50), G(0, 1)], nil), map, &b);            Check(@"Aerial on top, our code calling it", v, b, kMSBDBlameOurs);
            v = MSBDBlameReportBodyMap(B2(@[G(7, 1), G(8, 1), G(5, 0x150), G(0, 1)], nil), map, &b);           Check(@"Aerial on top, only our pass-through below", v, b, kMSBDBlameOther);
            v = MSBDBlameReportBodyMap(B2(@[G(7, 1), G(8, 1), G(0, 1)], nil), map, &b);                        Check(@"Aerial on top, nothing of ours", v, b, kMSBDBlameOther);
            v = MSBDBlameReportBodyMap(B2(@[G(1, 1), G(5, 0x50), G(0, 1)], @[G(6, 1), G(3, 1), G(8, 1)]), map, &b); Check(@"exception thrown in a tweak, ours on the thread", v, b, kMSBDBlameOther);
            v = MSBDBlameReportBodyMap(B2(@[G(1, 1), G(3, 1), G(0, 1)], @[G(6, 1), G(8, 1)]), map, &b);         Check(@"Apple-only exception, a tweak on the thread", v, b, kMSBDBlameOther);
            // A signal handler's frames (above "_sigtramp", e.g. the test builds' death log in MacStatusBarCore) are not the crash (finding 8).
            NSDictionary *sigtramp = @{@"imageOffset": @1, @"imageIndex": @1, @"symbol": @"_sigtramp"};
            v = MSBDBlameReportBodyMap(B2(@[G(1, 1), G(2, 1), sigtramp, G(3, 1), G(0, 1)], nil), map, &b);  Check(@"our signal handler above a tweak's crash", v, b, kMSBDBlameOther);
            v = MSBDBlameReportBodyMap(B2(@[G(1, 1), G(2, 1), sigtramp, G(8, 1), G(0, 1)], nil), map, &b);  Check(@"our signal handler above an Apple crash", v, b, VUNPINNED);
            v = MSBDBlameReportBodyMap(B2(@[G(1, 1), G(3, 1), sigtramp, G(5, 0x50), G(0, 1)], nil), map, &b); Check(@"a tweak's handler above our crash", v, b, kMSBDBlameOurs);
            NSString *image = nil, *uuid = nil, *where = nil; unsigned long long off = 0;
            total++; BOOL got = MSBDFeatureTopFrame(B2(@[G(5, 0x250), sigtramp, G(5, 0x50)], nil), map, &image, &uuid, &off, &where);
            if (!(got && off == 0x50)) { failures++; printf("FAIL  "); } else printf("PASS  ");
            printf("%-48s %s+0x%llx\n", "1b: not the handler's frame", image.UTF8String, off);
            // step 1b's place: our pass-through hook is passed over while other code of ours is there, and used when it is all there is
            total++; got = MSBDFeatureTopFrame(B2(@[G(8, 1), G(5, 0x150), G(5, 0x50), G(0, 1)], nil), map, &image, &uuid, &off, &where);
            if (!(got && off == 0x50)) { failures++; printf("FAIL  "); } else printf("PASS  ");
            printf("%-48s %s+0x%llx\n", "1b: the hook is passed over", image.UTF8String, off);
            total++; got = MSBDFeatureTopFrame(B2(tap, nil), map, &image, &uuid, &off, &where);
            if (!(got && off == 0x150)) { failures++; printf("FAIL  "); } else printf("PASS  ");
            printf("%-48s %s+0x%llx\n", "1b: only the hook -> the hook", image.UTF8String, off);
        }
        // Oversize (over the 3 MB cap): not parsed, counted.
        NSMutableData *big = [NSMutableData dataWithLength:MSBD_BLAME_MAX_BYTES + 1];
        v = MSBDBlameReportData(big, &b);                                                              Check(@"over the size cap", v, b, kMSBDBlameUnknown);
        // The guard's summary: the top frames of OUR images only (symbol + offset, or the offset in the image), at most 5.
        NSDictionary *(^Sym)(int, NSString *) = ^NSDictionary *(int i, NSString *sym) { return @{@"imageOffset": @0x4d2, @"imageIndex": @(i), @"symbol": sym, @"symbolLocation": @40}; };
        NSArray *fr = MSBDBlameOurFrames(Body(@[F(1), Sym(5, @"-[DMStageLights update]"), F(3), F(5), Sym(2, @"(unsymbolicated)"), F(0)], nil, nil), 5);
        total++; if (!([fr isEqual:@[@"DockMagnification.dylib -[DMStageLights update] + 40", @"DockMagnification.dylib + 0x1", @"MacStatusBar.dylib + 0x4d2"]])) { failures++; printf("FAIL  "); } else printf("PASS  ");
        printf("%-48s %s\n", "our frames only, in order", [fr componentsJoinedByString:@" | "].UTF8String);
        fr = MSBDBlameOurFrames(Body(@[F(1), F(0)], @[F(6), F(5), F(5), F(5), F(5), F(5), F(5)], nil), 5);
        total++; if (fr.count != 5) { failures++; printf("FAIL  "); } else printf("PASS  ");
        printf("%-48s %lu frames\n", "from the exception backtrace, at most 5", (unsigned long)fr.count);
        fr = MSBDBlameOurFrames(Body(@[F(1), F(3), F(0)], nil, nil), 5);
        total++; if (fr.count) { failures++; printf("FAIL  "); } else printf("PASS  ");
        printf("%-48s %lu frames\n", "another tweak's crash: no frames at all", (unsigned long)fr.count);
        // Speed on a large realistic report: 900 images, 60 threads x 40 frames.
        NSMutableArray *many = [NSMutableArray array], *threads = [NSMutableArray array];
        for (int i = 0; i < 900; i++) [many addObject:Img([NSString stringWithFormat:@"/System/Library/PrivateFrameworks/F%d.framework/F%d", i, i])];
        for (int t = 0; t < 60; t++) { NSMutableArray *fr = [NSMutableArray array]; for (int k = 0; k < 40; k++) [fr addObject:@{@"imageOffset": @(k), @"symbol": @"-[SBSomething somethingWithArgument:]", @"symbolLocation": @12, @"imageIndex": @((t * 40 + k) % 900)}]; [threads addObject:@{@"id": @(t), @"frames": fr}]; }
        NSData *large = Report(@{@"faultingThread": @3, @"threads": threads, @"usedImages": many});
        CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
        v = MSBDBlameReportData(large, &b);
        printf("      large report: %lu KB classified in %.1f ms (Mac)\n", (unsigned long)large.length / 1024, (CFAbsoluteTimeGetCurrent() - t0) * 1000);
        Check(@"large Apple-only report", v, b, kMSBDBlameApple);

        // Stack overflows (3 Oct 2026, iPad 2): the desktop's hit-test recursion (DMFocusGuideHitTest -> -[SBHomeScreenWindow hitTest:] -> ... ->
        // DMFocusGuideHitTest) ran out of stack inside DMUsableArea (+0x15bbb4), a window-layout helper the desktop's -dm_area had just called; step 1b
        // took that top-most frame of ours and switched Windowing off instead of the desktop. The fixture is the real report (13:28:33), trimmed to its
        // faulting thread (511 frames, symbols kept, device paths replaced). The map is that build's arm64 slice as its rules place these functions
        // (DMUsableArea: windowing; DMFocusGuideHitTest and -[DMDesktop ...]: the desktop; DMNativeDesktop: Finder) -- the build's own map file is
        // not kept, so the ranges are drawn around the report's symbolicated offsets.
        {
            NSString *so = [dir stringByAppendingPathComponent:@"stack-overflow-desktop-recursion.ips"];
            v = MSBDBlameReportFile(so, &b);   Check(@"overflow: ours (the cycle is ours)", v, b, kMSBDBlameOurs);
            Check(@"overflow: blamed names the recursion", [b containsString:@"recursion"] ? 1 : 0, b, 1);
            NSString *map = @"T windowingEnabled pref com.besiktasliseba.macstatusbar windowingEnabled 0 1 Enable Windowing|the window code\n"
                             "T desktopIcons pref com.besiktasliseba.macstatusbar desktopIcons 0 1 Show Desktop Icons|the desktop\n"
                             "T finder pref com.besiktasliseba.macstatusbar finderEnabled 0 1 Finder|Finder\n"
                             "T stock pref com.besiktasliseba.macstatusbar stockStatusBar 1 0 Status Bar Style|the status bar\n"
                             "T part part\nP MacStatusBarCore stock\n"
                             "U MacStatusBarCore 340bf5af-e8fb-4ed7-ac7d-06055d0e91d9 arm64\n"
                             "R 0 stock\nR 2a000 finder\nR 2b000 stock\nR 77000 desktopIcons\nR 82000 stock\nR 15b000 windowingEnabled\nR 15c000 stock\n"
                             "R 273000 desktopIcons\nR 274000 stock\nR 340000 -\n";
            NSDictionary *body = MSBDFeatureBody([NSData dataWithContentsOfFile:so]);
            NSString *image = nil, *uuid = nil, *where = nil; unsigned long long off = 0;
            total++; BOOL got = MSBDFeatureTopFrame(body, map, &image, &uuid, &off, &where);
            BOOL okTop = got && off == 0x2736bc && [where containsString:@"recursion"];
            if (!okTop) failures++;
            printf("%s  %-48s %s+0x%llx (%s)\n", okTop ? "PASS" : "FAIL", "overflow 1b: the cycle's frame, not 0x15bbb4", image.UTF8String, off, where.UTF8String);
            NSString *action = nil, *detail = nil;
            total++; got = MSBDFeatureForReport([NSData dataWithContentsOfFile:so], map, &action, &detail);
            BOOL okAct = got && [action hasPrefix:@"pref MacStatusBarCore com.besiktasliseba.macstatusbar desktopIcons 0"];
            if (!okAct) failures++;
            printf("%s  %-48s %s | %s\n", okAct ? "PASS" : "FAIL", "overflow 1b: the desktop off, not Windowing", action.UTF8String, detail.UTF8String);
            NSArray *ours = MSBDBlameOurFrames(body, 5);
            total++; BOOL okSum = ours.count == 2 && [ours[0] containsString:@"DMFocusGuideHitTest"] && [ours[1] containsString:@"dm_shownAt:"];
            if (!okSum) failures++;
            printf("%s  %-48s %s\n", okSum ? "PASS" : "FAIL", "overflow summary: the cycle's frames, once each", [ours componentsJoinedByString:@" | "].UTF8String);
        }
        {   // Synthetic overflows: the frames that repeat decide; where the stack ran out does not; a cycle of Apple code only, or a short stack, as before.
            NSDictionary *(^G)(int, int) = ^NSDictionary *(int i, int off) { return @{@"imageOffset": @(off), @"imageIndex": @(i)}; };
            NSArray *(^Stack)(NSArray *, NSArray *, int) = ^NSArray *(NSArray *top, NSArray *cycle, int times) {
                NSMutableArray *s = [top mutableCopy];
                for (int t = 0; t < times; t++) [s addObjectsFromArray:cycle];
                return s;
            };
            v = MSBDBlameReportData(Report(Body(Stack(@[G(3, 0x10)], @[G(6, 1), G(5, 0x50), G(0, 2)], 120), nil, nil)), &b);
            Check(@"overflow: a tweak where it ran out, the cycle ours", v, b, kMSBDBlameOurs);
            v = MSBDBlameReportData(Report(Body(Stack(@[G(5, 0x50)], @[G(6, 1), G(3, 0x20), G(0, 2)], 120), nil, nil)), &b);
            Check(@"overflow: ours where it ran out, a tweak's cycle", v, b, kMSBDBlameOther);
            v = MSBDBlameReportData(Report(Body(Stack(@[G(5, 0x50)], @[G(6, 1), G(0, 2)], 150), nil, nil)), &b);
            Check(@"overflow: Apple-only cycle, ours on top (as before)", v, b, kMSBDBlameOurs);
            v = MSBDBlameReportData(Report(Body(Stack(@[G(3, 0x10)], @[G(6, 1), G(5, 0x50), G(0, 2)], 5), nil, nil)), &b);
            Check(@"short stack, ours repeated: no overflow (as before)", v, b, kMSBDBlameOther);
            NSString *image = nil, *uuid = nil, *where = nil; unsigned long long off = 0;
            total++; BOOL got = MSBDFeatureTopFrame(Body(Stack(@[G(5, 0x250)], @[G(6, 1), G(5, 0x50), G(0, 2)], 120), nil, nil), nil, &image, &uuid, &off, &where);
            BOOL ok = got && off == 0x50;
            if (!ok) failures++;
            printf("%s  %-48s %s+0x%llx\n", ok ? "PASS" : "FAIL", "overflow 1b: ours in the cycle over ours on top", image.UTF8String, off);
            total++; got = MSBDFeatureTopFrame(Body(Stack(@[G(5, 0x250)], @[G(6, 1), G(0, 2)], 150), nil, nil), nil, &image, &uuid, &off, &where);
            ok = got && off == 0x250;
            if (!ok) failures++;
            printf("%s  %-48s %s+0x%llx\n", ok ? "PASS" : "FAIL", "overflow 1b: none of ours in the cycle: the top", image.UTF8String, off);
        }

        // ---- 1.8.7.7, GitHub #14: the REAL reports (tools/trim-crash-report.py: other tweaks renamed OtherTweakA.., nothing of the device) ----
        // Issue #14's four (16.3.1, the reporter's iPad): two popover aborts and a Do Not Disturb listener's unknown selector with only Apple code on
        // their stacks and other tweaks loaded -- not pinned on us (UNPINNED, weak), where before they counted as ours and the guard switched the
        // tweak off; a crash on a thread of ColorfulWallpaperX (renamed): another tweak's, as before. Ours still ours: #16's watchdog stackshot (our
        // UUID on the stuck main thread), the 17.5's Notification Center crash (f01: ours on the exception backtrace through our hooks), our crashes
        // of 15-18. Another tweak's still another's. The documented trade-off: two Apple-only crashes that were ours (17.5 Control Center spike, the
        // 16.7.7 Zetsu yield test) are UNPINNED now, with other tweaks loaded (the guard's loop breaker and rule 2 stay for them).
        {
            NSString *(^R)(NSString *) = ^NSString *(NSString *n) { return [dir stringByAppendingPathComponent:n]; };
            struct { const char *file; int want; const char *blamed; } real[] = {
                {"real-issue14-popover-1.ips", VUNPINNED, "Apple code only; 3 other tweaks loaded"}, {"real-issue14-popover-2.ips", VUNPINNED, "Apple code only; 3 other tweaks loaded"},
                {"real-issue14-wallpaper-tweak.ips", kMSBDBlameOther, "OtherTweakA.dylib (faulting thread)"}, {"real-issue14-dnd-listener.ips", VUNPINNED, "Apple code only; 7 other tweaks loaded"},
                {"real-175-nc-pull-ours.ips", kMSBDBlameOurs, "MacStatusBarCore.dylib (exception backtrace)"}, {"real-175-cctiles-ours-reason.ips", kMSBDBlameOurs, "MacStatusBarCore.dylib"},
                {"real-185-tv-ours.ips", kMSBDBlameOurs, "MacStatusBarCore.dylib"}, {"real-18-stage-ours.ips", kMSBDBlameOurs, "MacStatusBarCore.dylib"},
                {"real-156-exception-ours.ips", kMSBDBlameOurs, "MacStatusBarCore.dylib"}, {"real-167-exception-ours.ips", kMSBDBlameOurs, "MacStatusBarCore.dylib"},
                {"real-17-recursion-ours.ips", kMSBDBlameOurs, "MacStatusBarCore.dylib (faulting thread, recursion)"},
                {"real-156-aerial-other.ips", kMSBDBlameOther, "Aerial.dylib"}, {"real-185-cc-module-other.ips", kMSBDBlameOther, "OtherTweakA"},
                {"real-175-cc-spike-apple-only.ips", VUNPINNED, "Apple code only; 8 other tweaks loaded"}, {"real-167-zetsu-yield-apple-only.ips", VUNPINNED, "Apple code only; 17 other tweaks loaded"},
            };
            for (size_t i = 0; i < sizeof real / sizeof real[0]; i++) {
                v = MSBDBlameReportFile(R(@(real[i].file)), &b);
                Check([NSString stringWithFormat:@"real: %s", real[i].file], v == real[i].want && [b containsString:@(real[i].blamed)] ? v : -1, b, real[i].want);
            }
            NSString *wd = R(@"real-issue16-watchdog.ips");
            gMSBDBlameUUIDOverride = @{@"0c9f9299-b5ee-334d-b59e-0105d845aa36": @"/var/jb/usr/lib/MacStatusBarAndDock/MacStatusBarCore.dylib"};
            v = MSBDBlameReportFile(wd, &b);   Check(@"real: #16 watchdog, our UUID on the stuck main thread", v == kMSBDBlameOurs && [b hasPrefix:@"watchdog:MacStatusBarCore"] ? v : -1, b, kMSBDBlameOurs);
            gMSBDBlameUUIDOverride = @{};
            v = MSBDBlameReportFile(wd, &b);   Check(@"real: #16 watchdog, our image not named: cut, APPLE (strong)", v, b, kMSBDBlameApple);
            gMSBDBlameUUIDOverride = nil;
#if MSBD_BLAME_UNPINNED
            // what crashed: the place, the other tweaks, the cause (the report's own reason on 17.5; the exception's kind where there is none)
            NSDictionary *pop = MSBDFeatureBody([NSData dataWithContentsOfFile:R(@"real-issue14-popover-1.ips")]), *dnd = MSBDFeatureBody([NSData dataWithContentsOfFile:R(@"real-issue14-dnd-listener.ips")]);
            NSDictionary *cct = MSBDFeatureBody([NSData dataWithContentsOfFile:R(@"real-175-cctiles-ours-reason.ips")]), *wall = MSBDFeatureBody([NSData dataWithContentsOfFile:R(@"real-issue14-wallpaper-tweak.ips")]);
            NSString *w = MSBDBlameWhere(pop);
            Ok(@"where: popover abort -> the popover's presentation", [w isEqualToString:@"-[UIPopoverPresentationController presentationTransitionWillBegin] (UIKitCore)"], w);
            w = MSBDBlameWhere(dnd);
            Ok(@"where: #14 crash 4 -> Do Not Disturb's call-out", [w containsString:@"-[DNDStateService remoteService:didReceiveDoNotDisturbStateUpdate:]"], w);
            w = MSBDBlameWhere(wall);
            Ok(@"where: the wallpaper tweak's crash -> Metal's wait", [w hasPrefix:@"-[_MTLCommandBuffer waitUntilCompleted]"], w);
            NSArray *o = MSBDBlameOthersInReport(dnd);
            Ok(@"others: #14 crash 4 shows 7 other tweaks (names only)", o.count == 7 && ![[o componentsJoinedByString:@","] containsString:@"/"], [o componentsJoinedByString:@", "]);
            NSString *c = MSBDBlameCauseText(cct, nil);
            Ok(@"cause: 17.5 report's own exceptionReason", [c hasPrefix:@"NSInvalidArgumentException: -[NSConcreteValue discoverableMode]: unrecognized selector"], c);
            c = MSBDBlameCauseText(pop, nil);
            Ok(@"cause: 16.3.1 report without a reason: the exception's kind", [c hasPrefix:@"EXC_CRASH (SIGABRT): uncaught exception"], c);
            c = MSBDBlameCauseText(wall, nil);
            Ok(@"cause: a signal", [c isEqualToString:@"EXC_CRASH (SIGSEGV)"], c);
            // our death record (common/CrashCause.h): the line of that SpringBoard (its pid, written between its launch and the capture + 10 s)
            long pid = [pop[@"pid"] longValue], cap = MSBDBlameReportTime(pop[@"captureTime"]), launch = MSBDBlameReportTime(pop[@"procLaunch"]);
            Ok(@"report times read (launch < capture)", launch > 0 && cap > launch, [NSString stringWithFormat:@"%ld %ld", launch, cap]);
            NSString *reason = @"UIPopoverPresentationController (<UIPopoverPresentationController: 0x10a1b2c00>) should have a non-nil sourceView or barButtonItem set before the presentation occurs.";
            NSString *lines = [NSString stringWithFormat:@"%ld\t%ld\tmain\tNSGenericException\tnot this one\tNSException\n%ld\t%ld\tmain\tNSGenericException\t%@\tNSException\n%ld\t%ld\tmain\tX\tanother pid\tNSException\n%ld\t%ld\tmain\tX\ttoo late\tNSException\n",
                               pid, launch - 100, pid, cap, reason, pid + 1, cap, pid, cap + 60];
            [lines writeToFile:@MSBD_CAUSE_FILE atomically:YES encoding:NSUTF8StringEncoding error:nil];
            NSArray *death = MSBDCauseLineFor(pop);
            Ok(@"death record: the line of that pid and time only", death.count == 6 && [death[4] isEqualToString:reason], [death componentsJoinedByString:@" | "]);
            c = MSBDBlameCauseText(pop, death);
            Ok(@"cause: the death record's reason", [c hasPrefix:@"NSGenericException: UIPopoverPresentationController"] && [c containsString:@"sourceView or barButtonItem"], c);
            Ok(@"death record: another report's pid finds nothing", MSBDCauseLineFor(dnd) == nil, @"");
            // a reason naming our class makes it ours (the classifier reads it with the crash text)
            v = MSBDBlameReportBodyFull(pop, nil, @"-[DMStageLights update]: unrecognized selector sent to instance 0x1", nil, &b, NULL);   Check(@"death reason names DMStageLights: OURS", v, b, kMSBDBlameOurs);
            v = MSBDBlameReportBodyFull(pop, nil, @"-[DMFAppManager x]: unrecognized selector", nil, &b, NULL);                            Check(@"death reason with Apple's DMF class: not ours", v, b, VUNPINNED);
            {   // (review of 1.8.7.7) the parts of the cause line have their room in BYTES of UTF-8: a non-ASCII text took three times its room in
                // characters, and the guard's buffers cut the other tweaks off the line
                NSString *euro = [@"" stringByPaddingToLength:400 withString:@"€" startingAtIndex:0], *thumbs = [@"" stringByPaddingToLength:400 withString:@"👍🏽" startingAtIndex:0];
                NSString *c1 = MSBDCauseOneLine([@"NSGenericException: " stringByAppendingString:euro], 420), *c2 = MSBDCauseOneLine(thumbs, 200), *c3 = MSBDCauseOneLine([@"" stringByPaddingToLength:500 withString:@"a" startingAtIndex:0], 420);
                NSUInteger b1 = [c1 lengthOfBytesUsingEncoding:NSUTF8StringEncoding], b2 = [c2 lengthOfBytesUsingEncoding:NSUTF8StringEncoding], b3 = [c3 lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
                Ok(@"cause cut: 400 three-byte characters -> at most 420 bytes, \"…\" at the end", b1 <= 420 && b1 >= 410 && [c1 hasSuffix:@"€…"], [NSString stringWithFormat:@"%lu bytes", (unsigned long)b1]);
                Ok(@"  ... emoji with a skin tone: at most 200 bytes, never half a character", b2 <= 200 && [c2 hasSuffix:@"👍🏽…"] && [[c2 substringToIndex:c2.length - 1] stringByReplacingOccurrencesOfString:@"👍🏽" withString:@""].length == 0, [NSString stringWithFormat:@"%lu bytes", (unsigned long)b2]);
                Ok(@"  ... ASCII: at most 420 bytes; a short text unchanged", b3 <= 420 && b3 >= 418 && [MSBDCauseOneLine(@" a\tb\nc ", 420) isEqualToString:@"a b c"], [NSString stringWithFormat:@"%lu bytes", (unsigned long)b3]);
            }
            unlink(MSBD_CAUSE_FILE);
            // "another tweak loaded": the infrastructure, the engines we drive and our own probes are not; any thread counts; and only when a report
            // shows none, the tweaks installed for SpringBoard (the helper's look, a block here)
            NSArray *base = @[Img(@"/System/Library/CoreServices/SpringBoard.app/SpringBoard"), Img(@"/usr/lib/system/libsystem_kernel.dylib"), Img(@"/System/Library/Frameworks/Foundation.framework/Foundation")];
            NSDictionary *(^Apple)(NSArray *, NSArray *) = ^NSDictionary *(NSArray *more, NSArray *otherThread) {   // an Apple-only crash, `more` images on another thread
                NSMutableArray *im = [base mutableCopy]; NSMutableArray *ot = [NSMutableArray array];
                for (NSString *path in more) { [ot addObject:F((int)im.count)]; [im addObject:Img(path)]; }
                return @{@"faultingThread": @0, @"threads": @[@{@"triggered": @YES, @"frames": @[F(1), F(2), F(0)]}, @{@"frames": [ot arrayByAddingObjectsFromArray:otherThread ?: @[]]}], @"usedImages": im};
            };
            NSArray *(^none)(void) = ^NSArray *{ return @[]; };
            NSArray *(^one)(void) = ^NSArray *{ return @[@"InstalledTweak.dylib"]; };
            v = MSBDBlameReportBodyFull(Apple(@[], nil), nil, nil, none, &b, NULL);    Check(@"Apple-only, nothing else loaded or installed: APPLE", v, b, kMSBDBlameApple);
            v = MSBDBlameReportBodyFull(Apple(@[], nil), nil, nil, one, &b, NULL);     Check(@"Apple-only, a tweak installed for SpringBoard: UNPINNED", v, b, VUNPINNED);
            v = MSBDBlameReportBodyFull(Apple(@[@"/private/preboot/X/dopamine-X/procursus/basebin/gen/dyld", @"/private/preboot/X/dopamine-X/procursus/basebin/libjailbreak.dylib",
                                               @"/private/preboot/X/dopamine-X/procursus/basebin/rootlesshooks.dylib", @"/private/preboot/X/dopamine-X/procursus/usr/lib/ellekit/MobileSafety.dylib",
                                               @"/private/preboot/X/jb-X/procursus/usr/lib/TweakInject/   Choicy.dylib", @"/cores/binpack/usr/lib/universalhooks.dylib",
                                               @"/var/jb/usr/lib/libellekit.dylib"], nil), nil, nil, none, &b, NULL);
            Check(@"only jailbreak infrastructure loaded: APPLE", v, b, kMSBDBlameApple);
            v = MSBDBlameReportBodyFull(Apple(@[@"/var/jb/usr/lib/TweakInject/Aerial.dylib", @"/var/jb/usr/lib/TweakInject/Zetsu.dylib", @"/var/jb/usr/lib/TweakInject/MilkyWay4.dylib"], nil), nil, nil, none, &b, NULL);
            Check(@"only the window engines we drive: APPLE", v, b, kMSBDBlameApple);
            v = MSBDBlameReportBodyFull(Apple(@[@"/var/jb/usr/lib/TweakInject/MSBDProbe17.dylib", @"/var/jb/usr/lib/MacStatusBarAndDock/MacStatusBarCore.dylib"], nil), nil, nil, none, &b, NULL);
            Check(@"only our own probe and our parts: APPLE", v, b, kMSBDBlameApple);
            v = MSBDBlameReportBodyFull(Apple(@[@"/var/jb/usr/lib/TweakInject/SomeTweak.dylib"], nil), nil, nil, none, &b, NULL);
            Check(@"a tweak on a thread that did not crash: UNPINNED", v == VUNPINNED && [b isEqualToString:@"Apple code only; 1 other tweak loaded"] ? v : -1, b, VUNPINNED);
            v = MSBDBlameReportBodyFull(@{@"usedImages": @[Img(@"/var/jb/usr/lib/TweakInject/SomeTweak.dylib")]}, nil, nil, one, &b, NULL);
            Check(@"no stacks, a tweak loaded: UNKNOWN (strong)", v, b, kMSBDBlameUnknown);
            {   // stackshots: our UUID unnamed on the main thread cuts it (it could be ours: APPLE, strong, whoever else is loaded); a tweak on another
                // SpringBoard thread is "loaded"
                NSDictionary *(^SS)(BOOL) = ^NSDictionary *(BOOL cut) {
                    NSArray *bin = @[@[@"aaaaaaaa-0000-0000-0000-000000000001", @1, @"S"], @[@"bbbbbbbb-0000-0000-0000-000000000002", @2, @"P"], @[@"cccccccc-0000-0000-0000-000000000003", @3, @"P"]];
                    NSDictionary *main = @{@"id": @1, @"dispatch_queue_label": @"com.apple.main-thread", @"userFrames": cut ? @[@[@0, @8], @[@1, @16], @[@0, @32]] : @[@[@0, @16], @[@0, @32]]};
                    NSDictionary *other = @{@"id": @9, @"userFrames": @[@[@2, @64], @[@0, @8]]};
                    return @{@"procName": @"SpringBoard", @"termination": @{@"namespace": @"WATCHDOG"}, @"stackshot": @{@"processByPid": @{@"55": @{@"procname": @"SpringBoard", @"threadById": @{@"1": main, @"9": other}}}, @"binaryImages": bin}};
                };
                gMSBDBlameUUIDOverride = @{@"cccccccc-0000-0000-0000-000000000003": @"/var/jb/usr/lib/TweakInject/SomeTweak.dylib"};
                v = MSBDBlameReportBodyFull(MSBDBlameFromStackshot(SS(YES)), nil, nil, one, &b, NULL);   Check(@"stackshot cut at an unnamed image, a tweak loaded: APPLE", v, b, kMSBDBlameApple);
                v = MSBDBlameReportBodyFull(MSBDBlameFromStackshot(SS(NO)), nil, nil, none, &b, NULL);   Check(@"stackshot, a named tweak on another SpringBoard thread: UNPINNED", v == VUNPINNED && [b hasPrefix:@"watchdog:"] ? v : -1, b, VUNPINNED);
                gMSBDBlameUUIDOverride = nil;
            }
            {   // the tweaks installed for SpringBoard (MSBDBlameOthersInstalled): a tweak folder of plists and libraries, and Choicy's settings
                NSString *td = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"msbd-tweaks-%d", getpid()]];
                [[NSFileManager defaultManager] createDirectoryAtPath:td withIntermediateDirectories:YES attributes:nil error:nil];
                void (^Tweak)(NSString *, NSDictionary *, BOOL) = ^(NSString *name, NSDictionary *filter, BOOL lib) {
                    [(filter ? @{@"Filter": filter} : @{}) writeToFile:[td stringByAppendingPathComponent:[name stringByAppendingString:@".plist"]] atomically:YES];
                    if (lib) [[NSData data] writeToFile:[td stringByAppendingPathComponent:[name stringByAppendingString:@".dylib"]] atomically:YES];
                };
                Tweak(@"SBTweak", @{@"Bundles": @[@"com.apple.springboard"]}, YES);
                Tweak(@"UIKitTweak", @{@"Bundles": @[@"com.apple.UIKit"]}, YES);
                Tweak(@"FoundationTweak", @{@"Bundles": @[@"com.apple.Foundation"]}, YES);
                Tweak(@"ExeTweak", @{@"Executables": @[@"SpringBoard"]}, YES);
                Tweak(@"SettingsOnly", @{@"Bundles": @[@"com.apple.Preferences"]}, YES);
                // (after the g01 device rows) ElleKit's rule, not Substrate's: ANY key that matches loads it, no "Mode"; a CoreFoundationVersion
                // gate first (one number: from that version on; two: never, as ElleKit 1.1.3 / 1.2 read them); Classes not judged here
                Tweak(@"UIKitOrPreferences", @{@"Bundles": @[@"com.apple.UIKit"], @"Executables": @[@"Preferences"]}, YES);   // (our MacStatusBar.plist's shape)
                Tweak(@"SBOrGestalt", @{@"Bundles": @[@"com.apple.springboard"], @"Executables": @[@"MobileGestaltHelper"], @"CoreFoundationVersion": @[@800]}, YES);   // (RocketBootstrap's)
                Tweak(@"SBAndClass", @{@"Bundles": @[@"com.apple.springboard"], @"Classes": @[@"SBIconController"]}, YES);
                Tweak(@"SBUpper", @{@"Bundles": @[@"com.apple.SpringBoard"]}, YES);   // (ElleKit tries it lowercased too)
                Tweak(@"CFText", @{@"Bundles": @[@"com.apple.springboard"], @"CoreFoundationVersion": @[@"9999999"]}, YES);   // (not a number: no gate)
                Tweak(@"CFFuture", @{@"Bundles": @[@"com.apple.springboard"], @"CoreFoundationVersion": @[@9999999]}, YES);
                Tweak(@"CFRange", @{@"Bundles": @[@"com.apple.springboard"], @"CoreFoundationVersion": @[@800, @9999999]}, YES);
                Tweak(@"CFOnly", @{@"CoreFoundationVersion": @[@800]}, YES);
                Tweak(@"ClassOrPreferences", @{@"Classes": @[@"NSObject"], @"Bundles": @[@"com.apple.Preferences"]}, YES);   // (only a class could match)
                Tweak(@"ExeLowercase", @{@"Executables": @[@"springboard"]}, YES);   // (executables match exactly)
                Tweak(@"EmptyFilter", @{}, YES);
                Tweak(@"NoFilter", nil, YES);
                Tweak(@"AnyMode", @{@"Bundles": @[@"com.apple.Preferences"], @"Executables": @[@"SpringBoard"], @"Mode": @"Any"}, YES);
                Tweak(@"ClassesOnly", @{@"Classes": @[@"SBIconController"]}, YES);
                Tweak(@"SwitchedOff", @{@"Bundles": @[@"com.apple.springboard"]}, NO);
                Tweak(@"DeniedEverywhere", @{@"Bundles": @[@"com.apple.springboard"]}, YES);
                Tweak(@"DeniedInSpringBoard", @{@"Bundles": @[@"com.apple.springboard"]}, YES);
                Tweak(@"MacStatusBar", @{@"Bundles": @[@"com.apple.UIKit"]}, YES);
                Tweak(@"Aerial", @{@"Bundles": @[@"com.apple.springboard"]}, YES);
                Tweak(@"   Choicy", @{@"Bundles": @[@"com.apple.Foundation"]}, YES);
                gMSBDBlameTweakDirsOverride = @[td];
                [@{@"globalDeniedTweaks": @[@"DeniedEverywhere"], @"appSettings": @{@"com.apple.springboard": @{@"customTweakConfigurationEnabled": @YES, @"allowDenyMode": @2, @"deniedTweaks": @[@"DeniedInSpringBoard"]}}}
                    writeToFile:@MSBD_CHOICY_PREFS atomically:YES];
                NSArray *got = MSBDBlameOthersInstalled();
                NSArray *want = @[@"AnyMode.dylib", @"CFText.dylib", @"ExeTweak.dylib", @"FoundationTweak.dylib", @"SBAndClass.dylib", @"SBOrGestalt.dylib", @"SBTweak.dylib",
                                  @"SBUpper.dylib", @"UIKitOrPreferences.dylib", @"UIKitTweak.dylib"];
                Ok(@"installed for SpringBoard: filters, a missing library, Choicy, ours, engines", [[got sortedArrayUsingSelector:@selector(compare:)] isEqualToArray:want], [got componentsJoinedByString:@", "]);
                [@{@"appSettings": @{@"com.apple.springboard": @{@"customTweakConfigurationEnabled": @YES, @"allowDenyMode": @1, @"allowedTweaks": @[@"SBTweak"]}}} writeToFile:@MSBD_CHOICY_PREFS atomically:YES];
                got = MSBDBlameOthersInstalled();
                Ok(@"installed: Choicy's allow list for SpringBoard", [got isEqualToArray:@[@"SBTweak.dylib"]], [got componentsJoinedByString:@", "]);
                [@{@"appSettings": @{@"com.apple.springboard": @{@"customTweakConfigurationEnabled": @YES, @"tweakInjectionDisabled": @YES}}} writeToFile:@MSBD_CHOICY_PREFS atomically:YES];
                got = MSBDBlameOthersInstalled();
                Ok(@"installed: Choicy keeps every tweak out of SpringBoard", got.count == 0, [got componentsJoinedByString:@", "]);
                // (after the g01 device rows) the REAL filters of the four test iPads (tools/crash-fixtures/installed/<iOS>-<iPad>: TweakInject's plists,
                // the libraries there, Choicy's global deny list and SpringBoard settings; copied read-only 17 Nov 2026). Want: the tweaks ElleKit loads
                // into SpringBoard there, worked out by hand, in wants.txt beside them (one a line; how each list was found: its own header; out of
                // this code since 1.8.7.9). All of it is private: without the folder (the public tree) this part is a SKIP. With it, each of the four
                // iPads' folders must be there with its TweakInject folder: a missing one fails (it is not passed over)
                NSString *real = [dir stringByAppendingPathComponent:@"installed"];
                if (![[NSFileManager defaultManager] fileExistsAtPath:real]) printf("SKIP  the real installed filters: %s is not here\n", real.UTF8String);
                else {
                    NSFileManager *fm = [NSFileManager defaultManager];
                    for (NSString *dev in @[@"156-m1", @"167-ipad2", @"175-ipad17", @"185-a12z"]) {
                        NSString *src = [real stringByAppendingPathComponent:dev], *t = [td stringByAppendingPathComponent:dev];
                        BOOL isDir = NO;
                        if (!([fm fileExistsAtPath:[src stringByAppendingPathComponent:@"TweakInject"] isDirectory:&isDir] && isDir)) {
                            Ok([NSString stringWithFormat:@"installed, the real filters: %@", dev], NO, [NSString stringWithFormat:@"installed/%@/TweakInject is missing", dev]);
                            continue;
                        }
                        NSMutableArray *w = [NSMutableArray array];   // (wants.txt: a tweak's file name a line, without .dylib, spaces at its start kept; # a comment)
                        NSString *wl = [NSString stringWithContentsOfFile:[src stringByAppendingPathComponent:@"wants.txt"] encoding:NSUTF8StringEncoding error:nil];
                        for (NSString *line in [wl componentsSeparatedByString:@"\n"]) {
                            NSString *n = line;
                            while (n.length && [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[n characterAtIndex:n.length - 1]]) n = [n substringToIndex:n.length - 1];
                            if (n.length && ![n hasPrefix:@"#"]) [w addObject:[n stringByAppendingString:@".dylib"]];
                        }
                        BOOL ok = w.count && [fm copyItemAtPath:[src stringByAppendingPathComponent:@"TweakInject"] toPath:t error:nil];
                        NSString *libs = [NSString stringWithContentsOfFile:[src stringByAppendingPathComponent:@"libraries.txt"] encoding:NSUTF8StringEncoding error:nil];
                        for (NSString *lib in [libs componentsSeparatedByString:@"\n"]) if (lib.length) ok = [[NSData data] writeToFile:[t stringByAppendingPathComponent:lib] atomically:YES] && ok;
                        [fm removeItemAtPath:@MSBD_CHOICY_PREFS error:nil];
                        ok = ok && libs.length && [fm copyItemAtPath:[src stringByAppendingPathComponent:@"choicy.plist"] toPath:@MSBD_CHOICY_PREFS error:nil];
                        gMSBDBlameTweakDirsOverride = @[t];
                        got = ok ? MSBDBlameOthersInstalled() : nil;
                        NSMutableArray *missing = [w mutableCopy], *extra = [got mutableCopy];
                        [missing removeObjectsInArray:got ?: @[]]; [extra removeObjectsInArray:w];
                        Ok([NSString stringWithFormat:@"installed, the real filters: %@ (%lu)", dev, (unsigned long)w.count], ok && [[got sortedArrayUsingSelector:@selector(compare:)] isEqualToArray:[w sortedArrayUsingSelector:@selector(compare:)]],
                           ok ? [NSString stringWithFormat:@"%lu found; missing: %@; extra: %@", (unsigned long)got.count, [missing componentsJoinedByString:@", "] ?: @"", [extra componentsJoinedByString:@", "] ?: @""] : w.count ? @"fixture not readable" : @"wants.txt not readable");
                    }
                }
                [[NSFileManager defaultManager] removeItemAtPath:td error:nil];
                unlink(MSBD_CHOICY_PREFS);
                gMSBDBlameTweakDirsOverride = nil;
            }
#else
            for (const char *what = "UNPINNED's where/cause/others/death record/installed scan"; what; what = NULL) { total++; failures++; printf("FAIL  %-48s not in this code\n", what); }
#endif
        }
    }
    printf("%d/%d passed\n", total - failures, total);
    return failures ? 1 : 0;
}
