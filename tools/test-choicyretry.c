// test-choicyretry.c: sshtoggled's retry delays for Choicy's settings file (macsettings/sshtoggled/ChoicyRetry.h).
#include <stdio.h>
#include "../macsettings/sshtoggled/ChoicyRetry.h"
static int fails = 0;
static void check(const char *what, int ok) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what); if (!ok) fails = 1; }
int main(void) {
    check("first retry after 5 s", MSBDChoicyRetryDelay(1) == 5.0);
    check("second retry after 60 s", MSBDChoicyRetryDelay(2) == 60.0);
    int none = 1; for (int n = 3; n <= 10000; n++) if (MSBDChoicyRetryDelay(n) != 0.0) none = 0;
    check("no third retry, ever (no file: the folder's watch arms it when it comes)", none);
    double total = 0; int count = 0; for (int n = 1; n <= 10000; n++) { double w = MSBDChoicyRetryDelay(n); if (w > 0) { total += w; count++; } }
    check("a night without Choicy: 2 wake-ups in all (was 720 an hour)", count == 2 && total == 65.0);
    if (fails) { printf("test-choicyretry (compiled): FAILED\n"); return 1; }
    printf("test-choicyretry (compiled): all checks pass\n"); return 0;
}
