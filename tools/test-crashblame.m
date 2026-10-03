// test-crashblame.m -- Mac unit test for common/CrashBlame.h (the crash-report classifier). Run: tools/test-crashblame.sh
#import "../common/CrashFeature.h"   // (CrashBlame.h, and the step 1b lookup of the top frame)
static int failures = 0, total = 0;
static const char *V(int v) { return v == kMSBDBlameOurs ? "OURS" : v == kMSBDBlameApple ? "APPLE" : v == kMSBDBlameOther ? "OTHER" : "UNKNOWN"; }
static void Check(NSString *label, int got, NSString *blamed, int want) {
    total++;
    BOOL ok = got == want;
    if (!ok) failures++;
    printf("%s  %-48s %-7s (want %-7s) blamed: %s\n", ok ? "PASS" : "FAIL", label.UTF8String, V(got), V(want), blamed.UTF8String);
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
        v = MSBDBlameReportData(Report(Body(@[F(1), F(0)], nil, nil)), &b);                          Check(@"Apple only, nothing of ours (counted)", v, b, kMSBDBlameApple);
        v = MSBDBlameReportData(Report(Body(@[F(1), F(4), F(0)], nil, nil)), &b);                    Check(@"ElleKit + Apple only (platform = Apple)", v, b, kMSBDBlameApple);
        // (the top-most non-Apple image decides, 2026-09-26: another tweak's crash with our code lower on the stack is theirs)
        v = MSBDBlameReportData(Report(Body(@[F(1), F(3), F(2), F(0)], nil, nil)), &b);              Check(@"other tweak on top, our loader below", v, b, kMSBDBlameOther);
        v = MSBDBlameReportData(Report(Body(@[F(1), F(0)], @[F(6), F(5), F(0)], nil)), &b);          Check(@"ours only in exception backtrace", v, b, kMSBDBlameOurs);
        v = MSBDBlameReportData(Report(Body(@[F(1), F(3), F(0)], nil, @{@"x": @[@"-[DMStageLights update]: bad"]})), &b); Check(@"other tweak's frame, our class in reason", v, b, kMSBDBlameOurs);
        v = MSBDBlameReportData(Report(Body(@[F(1), F(0)], nil, @{@"x": @[@"-[DMFApp bundleIdentifier]: nil; DMCProfile"]})), &b); Check(@"Apple DMF/DMC classes are not ours", v, b, kMSBDBlameApple);
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
            v = MSBDBlameReportBodyMap(B2(@[G(1, 1), G(2, 1), sigtramp, G(8, 1), G(0, 1)], nil), map, &b);  Check(@"our signal handler above an Apple crash", v, b, kMSBDBlameApple);
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
    }
    printf("%d/%d passed\n", total - failures, total);
    return failures ? 1 : 0;
}
