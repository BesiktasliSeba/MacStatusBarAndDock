// test-jbinfo.m -- Mac test of which jailbreak About This iPad and the Shut Down question name (statusbar/JailbreakInfo.h), on fake roots made
// like the iPads' own: the iPad 2's palera1n (its marker's exact text), the M1's Dopamine 2.4.5, and the other cases.
#import <Foundation/Foundation.h>
#import "../statusbar/JailbreakInfo.h"

static int gFail = 0, gN = 0;
static NSString *gTmp;
static NSString *Root(NSString *name, NSDictionary<NSString *, NSString *> *files) {
    NSString *r = [gTmp stringByAppendingPathComponent:name];
    for (NSString *p in files) {
        NSString *f = [r stringByAppendingString:p];
        [[NSFileManager defaultManager] createDirectoryAtPath:[f stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
        if ([p hasSuffix:@"/"]) [[NSFileManager defaultManager] createDirectoryAtPath:f withIntermediateDirectories:YES attributes:nil error:nil];
        else [files[p] writeToFile:f atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:r withIntermediateDirectories:YES attributes:nil error:nil];
    return r;
}
static void Expect(NSString *what, MSBDJailbreak jb, NSString *title, NSString *restart) {
    gN++;
    NSString *t = MSBDJailbreakTitle(jb), *s = MSBDJailbreakAfterRestart(jb);
    if (![t isEqualToString:title] || ![s isEqualToString:restart]) { gFail++; printf("  FAIL %s: \"%s\" / \"%s\"\n", what.UTF8String, t.UTF8String, s.UTF8String); }
    else printf("  ok   %s: %s | %s\n", what.UTF8String, t.UTF8String, s.UTF8String);
}
int main(void) {
    @autoreleasepool {
        gTmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        NSString *(^app245)(NSString *) = ^NSString *(NSString *b) { return [b isEqualToString:@"com.opa334.Dopamine"] ? @"2.4.5" : nil; };
        NSString *(^noApp)(NSString *) = ^NSString *(NSString *b) { return nil; };
        // the iPad 2 (16.7.7, palera1n rootless): its marker's exact text (60 bytes), /cores/binpack, no Dopamine app
        Expect(@"iPad 2 palera1n", MSBDJailbreakAt(Root(@"ipad2", @{@"/var/jb/.installed_palera1n": @"Bootstrapper-Name=palera1nLoader\nBootstrapper-Version=2.1.1\n",
                                                                @"/var/jb/.procursus_strapped": @"", @"/cores/binpack/": @""}), noApp),
               @"palera1n (Loader 2.1.1)", @"You will need to run palera1n from a computer again after turning it back on.");
        // the M1 (15.6.1, Dopamine 2.4.5): basebin/.version and the app agree
        Expect(@"M1 Dopamine", MSBDJailbreakAt(Root(@"m1", @{@"/var/jb/.installed_dopamine": @"", @"/var/jb/basebin/.version": @"2.4.5\n"}), app245),
               @"Dopamine 2.4.5", @"You will need to run Dopamine again after turning it back on.");
        // Dopamine whose basebin has no version file: the app's
        Expect(@"Dopamine, app version", MSBDJailbreakAt(Root(@"dopa-app", @{@"/var/jb/.installed_dopamine": @""}), app245),
               @"Dopamine 2.4.5", @"You will need to run Dopamine again after turning it back on.");
        // Dopamine with neither: the name alone; a junk version file is not shown
        Expect(@"Dopamine, no version", MSBDJailbreakAt(Root(@"dopa-none", @{@"/var/jb/.installed_dopamine": @"", @"/var/jb/basebin/.version": @"<html>"}), noApp),
               @"Dopamine", @"You will need to run Dopamine again after turning it back on.");
        // the old bug: no Dopamine marker, the app installed somewhere -- not Dopamine (the marker decides)
        Expect(@"palera1n with a Dopamine app around", MSBDJailbreakAt(Root(@"p-dapp", @{@"/var/jb/.installed_palera1n": @"", @"/cores/binpack/": @""}), app245),
               @"palera1n", @"You will need to run palera1n from a computer again after turning it back on.");
        // palera1n found by its binpack alone, and rootful palera1n's marker
        Expect(@"palera1n by binpack", MSBDJailbreakAt(Root(@"p-bin", @{@"/cores/binpack/": @""}), noApp),
               @"palera1n", @"You will need to run palera1n from a computer again after turning it back on.");
        Expect(@"palera1n rootful", MSBDJailbreakAt(Root(@"p-ful", @{@"/.installed_palera1n": @"Bootstrapper-Name=palera1nLoader\nBootstrapper-Version=1.0.0\n"}), noApp),
               @"palera1n (Loader 1.0.0)", @"You will need to run palera1n from a computer again after turning it back on.");
        // another loader name is shown as it is
        Expect(@"palera1n, other bootstrapper", MSBDJailbreakAt(Root(@"p-other", @{@"/var/jb/.installed_palera1n": @"Bootstrapper-Name=Sileo\nBootstrapper-Version=2.5\n"}), noApp),
               @"palera1n (Sileo 2.5)", @"You will need to run palera1n from a computer again after turning it back on.");
        // other jailbreaks by their marker
        Expect(@"NathanLR", MSBDJailbreakAt(Root(@"nathan", @{@"/var/jb/.installed_nathanlr": @""}), noApp),
               @"NathanLR", @"You will need to run NathanLR again after turning it back on.");
        Expect(@"Fugu15 Max", MSBDJailbreakAt(Root(@"fugu", @{@"/var/jb/.installed_fugu15max": @""}), noApp),
               @"Fugu15 Max", @"You will need to run Fugu15 Max again after turning it back on.");
        Expect(@"unknown marker", MSBDJailbreakAt(Root(@"other", @{@"/var/jb/.installed_somejb": @""}), noApp),
               @"Somejb", @"You will need to run Somejb again after turning it back on.");
        // nothing at all
        Expect(@"no jailbreak found", MSBDJailbreakAt(Root(@"none", @{@"/var/jb/.procursus_strapped": @""}), noApp),
               @"Unknown", @"You will need to jailbreak this iPad again after turning it back on.");
        [[NSFileManager defaultManager] removeItemAtPath:gTmp error:nil];
        if (gFail) { printf("test-jbinfo: %d of %d FAILED\n", gFail, gN); return 1; }
        printf("test-jbinfo: %d/%d passed\n", gN, gN);
        return 0;
    }
}
