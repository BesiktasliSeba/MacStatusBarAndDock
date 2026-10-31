// PrewarmPartID.h -- which prewarm block (the dasd part, prewarmblock/) a running dasd has, so an install restarts dasd only when it has to
// (1.7.2 item 8). Plain C: the part, the root helper (sshtoggled --dasd-part-current) and the Mac test (tools/test-prewarmpartid.sh) run this code.
//  - Why. dasd keeps the code it loaded at its start, and a respring does not restart it; the postinst used to stop it at every install (since
//    1.5.0) so the block loaded. A dasd started again that way works for a long time before it settles: 10 to 26 minutes of CPU on the M1, the same
//    with the block switched off -- the cost of dasd's own start, not of our code. Most updates do not change the part at all.
//  - The part's build ID: the first 16 hex digits of a SHA-256 over the part's sources, its Makefile and the build kind (tools/prewarm-part-id.sh,
//    compiled in as MSBD_DASD_PART_ID), kept in the binary after kMSBDPrewarmPartMarker so the helper reads it from the file installed.
//  - The start stamp: once armed in dasd the part writes "<dasd's pid> <dasd's start time> <its build ID>" to kMSBDPrewarmLoadedFile. The install
//    leaves dasd running only when that stamp is the running dasd's (same pid, same start time, the process named dasd) and names the build ID of
//    the part just installed. Anything else -- no stamp (a first install, a dasd that started without our part, a part its crash guard switched
//    off), another dasd, another build, a helper that cannot tell -- and dasd is restarted as before.
#ifndef MSBD_PREWARM_PART_ID_H
#define MSBD_PREWARM_PART_ID_H
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>

#define kMSBDPrewarmPartMarker  "msbd-dasd-part:"
#define kMSBDPrewarmLoadedFile  "/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-PrewarmBlockLoaded.txt"
#define kMSBDPrewarmPartFile    "/var/jb/usr/lib/MacStatusBarAndDock/PrewarmBlockTweak.dylib"
#define kMSBDPrewarmPartIDLen   16

// The build ID that follows the marker in a file's bytes (exactly kMSBDPrewarmPartIDLen lower-case hex digits), copied to out (17 bytes or more);
// 0 when the bytes have no marker with a well-formed ID after it (an older part, a damaged file), else 1.
static inline int MSBDPrewarmPartIDIn(const unsigned char *bytes, size_t len, char *out, size_t outLen) {
    const size_t ml = sizeof(kMSBDPrewarmPartMarker) - 1;
    if (!bytes || !out || outLen <= kMSBDPrewarmPartIDLen) return 0;
    out[0] = 0;
    for (size_t i = 0; i + ml + kMSBDPrewarmPartIDLen <= len; i++) {
        if (bytes[i] != 'm' || memcmp(bytes + i, kMSBDPrewarmPartMarker, ml) != 0) continue;
        const unsigned char *id = bytes + i + ml;
        int ok = 1;
        for (size_t k = 0; k < kMSBDPrewarmPartIDLen && ok; k++) ok = (id[k] >= '0' && id[k] <= '9') || (id[k] >= 'a' && id[k] <= 'f');
        if (ok && i + ml + kMSBDPrewarmPartIDLen < len && isxdigit(id[kMSBDPrewarmPartIDLen])) ok = 0;   // (longer than an ID: not one)
        if (!ok) continue;
        memcpy(out, id, kMSBDPrewarmPartIDLen); out[kMSBDPrewarmPartIDLen] = 0;
        return 1;
    }
    return 0;
}

// The stamp's one line: "<pid> <start seconds>.<start microseconds> <build ID>". 1 when it is well formed (the ID copied to id, 17 bytes or more).
typedef struct { long pid; long long startSec; long startUsec; } MSBDPrewarmStampProc;
static inline int MSBDPrewarmStampParse(const char *line, MSBDPrewarmStampProc *proc, char *id, size_t idLen) {
    if (!line || !proc || !id || idLen <= kMSBDPrewarmPartIDLen) return 0;
    long pid = 0, usec = -1; long long sec = -1; char got[64] = {0}; int n = 0;
    if (sscanf(line, "%ld %lld.%ld %63s%n", &pid, &sec, &usec, got, &n) != 4) return 0;
    for (const char *rest = line + n; *rest; rest++) if (*rest != '\n' && *rest != '\r' && *rest != ' ') return 0;   // (nothing after the ID)
    if (pid <= 0 || sec <= 0 || usec < 0 || usec >= 1000000 || strlen(got) != kMSBDPrewarmPartIDLen) return 0;
    for (int k = 0; k < kMSBDPrewarmPartIDLen; k++) if (!((got[k] >= '0' && got[k] <= '9') || (got[k] >= 'a' && got[k] <= 'f'))) return 0;
    proc->pid = pid; proc->startSec = sec; proc->startUsec = usec;
    memcpy(id, got, kMSBDPrewarmPartIDLen + 1);
    return 1;
}
static inline int MSBDPrewarmStampFormat(char *out, size_t outLen, long pid, long long startSec, long startUsec, const char *id) {
    return snprintf(out, outLen, "%ld %lld.%06ld %s\n", pid, startSec, startUsec, id ?: "");
}

// The install's question: may dasd keep running? Only when the stamp parses, names the running dasd (the process at that pid is called dasd and
// started at the stamp's time) and the part installed now has the build ID the stamp names.
//   running: the process at the stamp's pid as the system lists it (found NO: none), installedID: the ID in the part's file ("" when it has none).
typedef struct { int found; const char *name; long long startSec; long startUsec; } MSBDPrewarmRunning;
static inline int MSBDPrewarmPartCurrent(const char *stampLine, MSBDPrewarmRunning running, const char *installedID) {
    MSBDPrewarmStampProc p; char id[kMSBDPrewarmPartIDLen + 1];
    if (!MSBDPrewarmStampParse(stampLine, &p, id, sizeof id)) return 0;
    if (!running.found || !running.name || strcmp(running.name, "dasd") != 0) return 0;
    if (running.startSec != p.startSec || running.startUsec != p.startUsec) return 0;
    if (!installedID || strlen(installedID) != kMSBDPrewarmPartIDLen) return 0;
    return strcmp(installedID, id) == 0;
}
#endif
