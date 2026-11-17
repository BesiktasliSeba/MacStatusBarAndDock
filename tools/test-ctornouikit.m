// test-ctornouikit.m -- see test-ctornouikit.sh. What Finder's side of the Dock's Trash decides while SpringBoard starts (GitHub #16): the real
// code cut out of the part -- statusbar/DockTrash.h's gDockTrashOn and DMDockTrashPrefOn (ct-pref.inc), statusbar/DisplayPrefs.h's DMDispScreens
// (ct-screens.inc), DockTrash.h's DMDockTrashExternalDisplay and DMDockTrashApplyPref (ct-apply.inc) -- run on stand-ins: UIScreen (a class of
// that name here, no UIKit: every +screens / +mainScreen counted, inside the constructor or after it), the Dock's settings (showTrash in
// com.besiktasliseba.dockmagnification: off, on or not set), a display's own Show Trash in Dock (DMDispBool: not set = ON, the display default,
// or off), Finder's switch, the bin's watch and count. The constructor as StatusBar.x runs it: gDMInCtor set, Finder's start (DMFinderDockInit
// -> DMDockTrashInit -> DMDockTrashApplyPref with Finder not on yet, then gFinderOn and DMDockTrashApplyPref again, DMFinderApplyPref), the
// screens asked once (the backstop), gDMInCtor cleared; then one turn of the main queue. One scenario per process; built twice, release and DEBUG.
// A scenario: finder-<on|off>.trash-<no|yes|unset>.tv-<none|on|off> (a TV connected at the start, its own Show Trash in Dock not set or off).
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <string.h>
#if DEBUG
#define DEBUG_BUILD YES
#else
#define DEBUG_BUILD NO
#endif

static BOOL gDMInCtor = NO;   // (StatusBar.x's: set by the constructor below)
static BOOL gFinderOn = NO;   // (StatusBar.x's: Finder's switch as applied)
static NSMutableArray<NSString *> *gLog;
static void TLog(NSString *s) { if (!gLog) gLog = [NSMutableArray array]; [gLog addObject:s]; if (getenv("CT_LOG")) printf("   log: %s\n", s.UTF8String); }
static int LogCount(NSString *part) { int n = 0; for (NSString *l in gLog) if ([l rangeOfString:part].location != NSNotFound) n++; return n; }
#if DEBUG
#define DMLog(...) TLog(__VA_ARGS__)
#else
#define DMLog(...) do { if (0) { (void)(__VA_ARGS__); } } while (0)   // (as StatusBar.x's release DMLog)
#endif
#define DM_FEATURE_MARK(x) do {} while (0)

// ---- UIScreen: the iPad's and a TV's; every ask counted
@interface UIScreen : NSObject
+ (NSArray<UIScreen *> *)screens;
+ (UIScreen *)mainScreen;
@end
static int gAskedInCtor, gAskedAfter, gScreensAfter;
static UIScreen *gMain, *gTV;
static BOOL gTVConnected = NO;
@implementation UIScreen
+ (void)asked:(BOOL)list { if (gDMInCtor) gAskedInCtor++; else { gAskedAfter++; if (list) gScreensAfter++; } }
+ (NSArray<UIScreen *> *)screens { [self asked:YES]; return gTVConnected ? @[gMain, gTV] : @[gMain]; }
+ (UIScreen *)mainScreen { [self asked:NO]; return gMain; }
@end

// ---- the Dock's settings: showTrash in its domain (-1 not set, 0 off, 1 on)
static int gShowTrash = -1, gPrefReads, gPrefOther;
static Boolean TAppSync(CFStringRef app) { return true; }
static CFPropertyListRef TCopyValue(CFStringRef key, CFStringRef app, CFStringRef user, CFStringRef host) {
    gPrefReads++;
    if (!CFEqual(key, CFSTR("showTrash")) || !CFEqual(app, CFSTR("com.besiktasliseba.dockmagnification")) || user != kCFPreferencesCurrentUser || host != kCFPreferencesAnyHost) { gPrefOther++; return NULL; }
    return gShowTrash < 0 ? NULL : CFRetain(gShowTrash ? kCFBooleanTrue : kCFBooleanFalse);
}
#define CFPreferencesAppSynchronize TAppSync
#define CFPreferencesCopyValue TCopyValue
#include "ct-pref.inc"   // (the real gDockTrashOn, DMDockTrashPrefOn)
#undef CFPreferencesAppSynchronize
#undef CFPreferencesCopyValue

// ---- the bin's watch and count (DockTrash.h's own, not under test): how often, and the state each saw
static int gWatches, gRecounts;
static void DMDockTrashWatchFolders(void) { gWatches++; }
static void DMDockTrashRecount(NSString *why) { gRecounts++; }

#include "ct-screens.inc"   // (the real DMDispScreens)

// ---- a display's own Show Trash in Dock (DisplayPrefs.h DMDispBool): the iPad's screen answers the iPad's value; the TV its own, ON when not set
static int gTVOwn = -1, gDispWrongRow;
#define DMDispBool TDispBool   // (the getter by this name stays the layers' and readers' own: test-displayreaders.sh lists who calls it)
static BOOL TDispBool(UIScreen *s, const char *part, const char *key, BOOL ipad) {
    if (!s || s == [UIScreen mainScreen]) return ipad;
    if (strcmp(part, "dock") || strcmp(key, "showTrash")) { gDispWrongRow++; return ipad; }
    return gTVOwn < 0 ? YES : gTVOwn != 0;
}

#include "ct-apply.inc"   // (the real DMDockTrashExternalDisplay, DMDockTrashApplyPref)

static int gPass, gFail;
static void Check(BOOL ok, NSString *what) { if (ok) gPass++; else gFail++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }

int main(int argc, char **argv) {
    @autoreleasepool {
        const char *fin[] = { "on", "off" }, *tr[] = { "no", "yes", "unset" }, *tv[] = { "none", "on", "off" };
        if (argc > 1 && !strcmp(argv[1], "list")) {
            for (int f = 0; f < 2; f++) for (int t = 0; t < 3; t++) for (int v = 0; v < 3; v++) printf("finder-%s.trash-%s.tv-%s\n", fin[f], tr[t], tv[v]);
            return 0;
        }
        char f[8] = "", t[8] = "", v[8] = "";
        if (argc < 2 || sscanf(argv[1], "finder-%7[a-z].trash-%7[a-z].tv-%7[a-z]", f, t, v) != 3) { printf("FAIL  usage: %s list | finder-<on|off>.trash-<no|yes|unset>.tv-<none|on|off>\n", argv[0]); return 2; }
        const char *trash = strdup(t);   // (the switch's word, for the checks inside the block below)
        BOOL finder = !strcmp(f, "on");
        gShowTrash = !strcmp(t, "no") ? 0 : !strcmp(t, "yes") ? 1 : -1;
        gTVConnected = strcmp(v, "none") != 0; gTVOwn = !strcmp(v, "off") ? 0 : -1;
        gMain = [UIScreen new]; gTV = [UIScreen new];
        BOOL ipadOn = gShowTrash != 0, tvOn = gTVConnected && gTVOwn != 0;
        BOOL wantStart = finder && ipadOn, wantAfter = finder && (ipadOn || tvOn);
        BOOL displaysAsked = finder && !ipadOn;   // (only then is a display's own switch needed)

        // ---- the constructor (StatusBar.x %ctor): Finder's start, as DMFinderApplyPref runs it
        gDMInCtor = YES;
        DMDockTrashApplyPref();   // (DMFinderDockInit -> DMDockTrashInit: Finder not on yet)
        if (finder) { gFinderOn = YES; DMDockTrashApplyPref(); }   // (gFinderOn = on; DMDockTrashApplyPref();)
        NSArray *during = DMDispScreens();   // (anything else of the constructor that asks: the backstop)
        gDMInCtor = NO;
        BOOL onAtEnd = gDockTrashOn; int watchesAtEnd = gWatches;

        Check(gAskedInCtor == 0, [NSString stringWithFormat:@"%s: UIScreen not asked while the constructor runs (asked %d time(s))", argv[1], gAskedInCtor]);
        Check(during.count == 0, [NSString stringWithFormat:@"%s: DMDispScreens answers no screen during the constructor (%lu)", argv[1], (unsigned long)during.count]);
        Check(onAtEnd == wantStart, [NSString stringWithFormat:@"%s: at the end of the constructor the bin is %s, by the Dock's switch alone (want %s)", argv[1], onAtEnd ? "on" : "off", wantStart ? "on" : "off"]);
        Check(watchesAtEnd == (wantStart ? 1 : 0), [NSString stringWithFormat:@"%s: the Trash watched from the start only when the switch is on (%d watch update(s))", argv[1], watchesAtEnd]);
        Check(gPrefOther == 0 && gDispWrongRow == 0, [NSString stringWithFormat:@"%s: the Dock's showTrash (its domain, the user's, any host) and the display's dock/showTrash read, nothing else", argv[1]]);
        if (DEBUG_BUILD) Check(LogCount(@"[dispprefs] the screens were asked while SpringBoard starts") == 1, [NSString stringWithFormat:@"%s: (debug) the backstop's line, once", argv[1]]);
        else Check(gLog.count == 0, [NSString stringWithFormat:@"%s: (release) nothing logged", argv[1]]);

        // ---- one turn of the main queue: after every initializer
        dispatch_async(dispatch_get_main_queue(), ^{
            Check(gDockTrashOn == wantAfter, [NSString stringWithFormat:@"%s: after one turn of the main queue the bin is %s (want %s: the iPad's switch %s, %s)", argv[1],
                  gDockTrashOn ? "on" : "off", wantAfter ? "on" : "off", trash, gTVConnected ? (gTVOwn ? "a TV with its own not set (ON)" : "a TV with its own off") : "no TV"]);
            Check(gScreensAfter == (displaysAsked ? 1 : 0), [NSString stringWithFormat:@"%s: the displays asked once after the start exactly when the iPad's switch left it open (%d time(s))", argv[1], gScreensAfter]);
            Check(gWatches == watchesAtEnd + ((wantAfter && !wantStart) ? 1 : 0), [NSString stringWithFormat:@"%s: the watch follows the bin's change only (%d update(s) in all)", argv[1], gWatches]);
            if (DEBUG_BUILD && displaysAsked) Check(LogCount(@"[trash] SpringBoard's start: the iPad's Show Trash in Dock is off") >= 1, [NSString stringWithFormat:@"%s: (debug) the start's wait for the displays logged", argv[1]]);
            // ---- later, as the connect / disconnect observers apply it (DMDockTrashInit, unchanged): the display check as before the change
            if (finder && !ipadOn) {
                BOOL was = gTVConnected; int own = gTVOwn;
                gTVConnected = YES; gTVOwn = -1; DMDockTrashApplyPref();
                Check(gDockTrashOn, [NSString stringWithFormat:@"%s: a TV connecting after the start: the bin served (its own default ON)", argv[1]]);
                gTVConnected = NO; DMDockTrashApplyPref();
                Check(!gDockTrashOn, [NSString stringWithFormat:@"%s: ... and not after it goes", argv[1]]);
                gTVConnected = was; gTVOwn = own;
            }
            printf("%d passed, %d failed\n", gPass, gFail);
            exit(gFail ? 1 : 0);
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{ printf("FAIL  the main queue never turned\n"); exit(3); });
        dispatch_main();
    }
}
