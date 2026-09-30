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
        printf("%d/%d passed\n", pass, n);
        return pass == n ? 0 : 1;
    }
}
