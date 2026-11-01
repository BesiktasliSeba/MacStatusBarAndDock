// PrewarmArmed.h -- whether the prewarm block (the dasd part, prewarmblock/) is armed, so Settings offers Prewarm Apps (Windows & Multitasking,
// 1.7.5 item 6) only where the switch does something (1.7.7 item 5: until then the row showed wherever the page did, and where the block was not
// armed the switch silently did nothing -- 1.7.5 code review, n1). Plain C: the part (it writes the record), Settings (the page,
// MSBRootListController.m; the Settings search and Spotlight's Tweak Settings, common/TweakSpotlight.h) and the Mac test (tools/test-prewarmarmed.sh)
// run this code.
//  - The record: one line "<state> <dasd's pid>", written by the part at every start of dasd, armed or not (a start that is not armed must not
//    leave the last start's "armed"), through a new file renamed over the old one, so a reader never sees half a line. "armed": both of dasd's
//    prewarm calls go through its hooks. Not armed: "guard" (its crash-loop guard switched it off), "missing" (_APRSPrewarmInterface or its prewarm
//    call is not there), "shape" (the prewarm call is not of the shape it can refuse), "closure" (the closure-build call is there in another shape:
//    dasd would still prewarm through it, and 18.5 prewarms only that way), "debug" (debug builds: the test switch). Anything else is not armed
//    either (a damaged line, a state a later build adds).
//  - Why a file, not a notify state (the review's idea): a notify state lives only while a process holds its name, and dasd is started on demand
//    and may be ended under memory pressure (EnablePressuredExit in its launchd plist), so the row would come and go with dasd, while the switch
//    works from the first prewarm of the next dasd -- it loads the same part, which makes the same checks on the same iPadOS. The file keeps that
//    verdict across dasd's starts (the same reason made the quit set's file the block's switch, 1.7.1). Not followed: a dasd started later
//    without our part while the files stay (only by keeping our part out of dasd alone, e.g. Choicy's list of daemons): the row stays as the last
//    start of the part left it.
//  - Shown: the record says armed AND the quit set's file is there, i.e. SpringBoard keeps the set (common/PrewarmQuitSet.h: the file goes with
//    Use Stock Status Bar, Mac Status Bar's old off, a SpringBoard without the status bar part and the package's removal; dasd then refuses
//    nothing, switch or not).
//  - No record yet: not shown. That is the honest default: nothing has said that the block can refuse a prewarm on this iPad. It is either a
//    dasd that has not started since the install (the install restarts dasd when the part changed, and launchd starts it again within seconds)
//    or a jailbreak that never puts our part into dasd -- where the switch would do nothing. The row comes with the first start of the part.
#ifndef MSBD_PREWARM_ARMED_H
#define MSBD_PREWARM_ARMED_H
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include "PrewarmQuitSet.h"   // (kMSBDPrewarmQuitSetFile; plain C here)

#define kMSBDPrewarmArmedFile "/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-PrewarmBlockArmed.txt"
// Posted by the part after each record it writes (the file is the verdict; this only says a new one is there): a SpringBoard that made Spotlight's
// Tweak Settings rows before it -- a dasd started after SpringBoard's start -- reads it again and brings the rows up to date when Prewarm Apps'
// row comes or goes (statusbar/SpotlightFiles.x; the 1.7.7 code review: the rows followed the record only when they were made again).
#define kMSBDPrewarmArmedNote "com.besiktasliseba.macstatusbar.prewarm.armed"

// The record's line: "<state> <pid>\n".
static inline int MSBDPrewarmArmedFormat(char *out, size_t outLen, const char *state, long pid) {
    return snprintf(out, outLen, "%s %ld\n", state ? state : "", pid);
}
// Whether a record's line says armed: exactly "armed <pid>" (a positive pid; a line end after it). *pid, when given, gets the pid of any well-formed
// line. Everything else -- no line, another state, a damaged or cut line -- is not armed.
static inline int MSBDPrewarmArmedParse(const char *line, long *pid) {
    char state[16] = {0}; long p = 0; int n = 0;
    if (!line || sscanf(line, "%15s %ld%n", state, &p, &n) != 2 || p <= 0) return 0;
    for (const char *rest = line + n; *rest; rest++) if (*rest != '\n' && *rest != '\r' && *rest != ' ') return 0;   // (nothing after the pid)
    if (pid) *pid = p;
    return strcmp(state, "armed") == 0;
}
// Settings' answer from the record's line (NULL: no record) and whether the quit set's file is there.
static inline int MSBDPrewarmAppsShownFrom(const char *recordLine, int quitSetFileThere) {
    return quitSetFileThere && MSBDPrewarmArmedParse(recordLine, NULL);
}
// ... from the two files as they are now (one small read and one stat: asked whenever the page is built or the search runs).
static inline int MSBDPrewarmAppsShownAt(const char *recordPath, const char *quitSetPath) {
    char line[64] = {0};
    FILE *f = fopen(recordPath, "r");
    int read = f && fgets(line, sizeof line, f) != NULL;
    if (f) fclose(f);
    struct stat st;
    return MSBDPrewarmAppsShownFrom(read ? line : NULL, stat(quitSetPath, &st) == 0);
}
static inline int MSBDPrewarmAppsShown(void) { return MSBDPrewarmAppsShownAt(kMSBDPrewarmArmedFile, kMSBDPrewarmQuitSetFile); }
#endif
