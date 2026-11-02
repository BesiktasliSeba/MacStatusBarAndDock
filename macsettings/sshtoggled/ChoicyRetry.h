// ChoicyRetry.h -- how long sshtoggled waits before looking for Choicy's settings file again when it is not there (battery drain F7, 1.7.8).
// The preferences folder's own file watch arms the file's watch when the file comes; these retries are only a safety net: the first after 5 s,
// the second after 60 s, then none (0). Plain C: tools/test-choicyretry.sh.
#pragma once
static inline double MSBDChoicyRetryDelay(int attempt) {   // (attempt: 1 = the first retry)
    if (attempt == 1) return 5.0;
    if (attempt == 2) return 60.0;
    return 0.0;
}
