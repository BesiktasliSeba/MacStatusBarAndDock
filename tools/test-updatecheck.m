// test-updatecheck.m -- dpkg version order used by the Apple menu's update row (common/UpdateCheck.h). Run: tools/test-updatecheck.sh
#import <Foundation/Foundation.h>
#include "../common/UpdateCheck.h"
int main(void) {
    @autoreleasepool {
        struct { const char *a, *b; int want; } t[] = {
            {"1.1.8", "1.1.7", 1}, {"1.1.7", "1.1.7", 0}, {"1.1.10", "1.1.9", 1}, {"1.1.7-4+debug", "1.1.7", 1},
            {"1.1.7", "1.1.7-4+debug", -1}, {"1.2", "1.1.99", 1}, {"1.0~beta1", "1.0", -1}, {"1:1.0", "2.0", 1},
            {"1.1.7-2", "1.1.7-10", -1}, {"1.1.7a", "1.1.7", 1}, {"1.0.10", "1.1.0", -1},
        };
        int pass = 0, n = sizeof t / sizeof t[0];
        for (int i = 0; i < n; i++) {
            int r = MSBDVersionCompare(@(t[i].a), @(t[i].b)); r = r > 0 ? 1 : r < 0 ? -1 : 0;
            BOOL ok = r == t[i].want; pass += ok;
            printf("%s  %s vs %s -> %d (want %d)\n", ok ? "PASS" : "FAIL", t[i].a, t[i].b, r, t[i].want);
        }
        // the lists (1.5.1: Havoc's too, a few MB, searched for our stanza only): our versions found, another package's never taken
        NSString *havoc = @"Package: com.example.other\nVersion: 9.9\nDepends: firmware\n\n"
                           "Package: com.besiktasliseba.macstatusbaranddock\nName: MacStatusBar&Dock\nVersion: 1.5.1\nArchitecture: iphoneos-arm64\n\n"
                           "Package: com.example.addon\nVersion: 3.0\nDepends: com.besiktasliseba.macstatusbaranddock (>= 1.5)\nDescription: Package: com.besiktasliseba.macstatusbaranddock\nVersion: 7.0\n\n"
                           "Package: com.besiktasliseba.macstatusbaranddock\nVersion: 1.5.0\n";
        struct { NSString *text, *best, *want; const char *what; } l[] = {
            { havoc, nil, @"1.5.1", "Havoc-like list: our newest stanza (not another package's version, not a Depends line)" },
            { havoc, @"1.6.0", @"1.6.0", "a newer version from the other list stays" },
            { @"Package: com.besiktasliseba.macstatusbaranddock\nVersion: 1.4.5\n", nil, @"1.4.5", "our repo's list, one stanza, no blank line at the end" },
            { @"Package: com.besiktasliseba.macstatusbaranddockx\nVersion: 9.0\n\n", nil, nil, "a longer package name is not ours" },
            { nil, nil, nil, "no list" },
        };
        int ln = sizeof l / sizeof l[0];
        for (int i = 0; i < ln; i++) {
            NSString *got = MSBDNewestVersionInList(l[i].text, l[i].best);
            BOOL ok = (got == l[i].want) || [got isEqualToString:l[i].want]; pass += ok;
            printf("%s  %s -> %s\n", ok ? "PASS" : "FAIL", l[i].what, got.UTF8String ?: "nil");
        }
        n += ln;
        printf("%d/%d passed\n", pass, n);
        return pass == n ? 0 : 1;
    }
}
