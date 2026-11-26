// test-macresizeswitch.m -- Mac test (Mac Catalyst) of Settings > Pointer > Mac Resize Pointers in SpringBoard (1.8.9; KT 25 Nov ~19:35: "Resize
// cursor ability on versions except 18 should be off by default too, since it might affect how windows behave for users"). statusbar/ResizeFact.h
// is built as it ships (RZ_FACT_H: that file in a tree whose common/ holds MacResizeCursor.h, PointerFade.h and MacPointerStatus.h) on stand-ins
// for what StatusBar.x gives it, and its follow (DMRZFollow, as the MacPointer bridge calls it at a settings change and every 2 s) is played:
//  - the switch off with everything else on (Pointer Style Mac, a trackpad or mouse attached, MacPointer drawing, the crash guard's piece not off,
//    a window engine with a shown grip, a system gestures window): no hook of the windows' hovered edge, no recognizer on the system gestures
//    window, no word on the resize note, MacPointer's word not even read -- at the first follow and at the 2 s follows after it;
//  - the switch on: the hook, the recognizer and the word (so the stand-ins do see an install); a band's fact is said;
//  - off again: the fact goes, the recognizer goes, the hook (in since the switch-on) passes straight through; on again: no second hook.
// RZT_SKIPPED=1 (the environment): the crash guard's piece "resizePointers" off, the switch on: the one clear of an earlier SpringBoard's word
// (pointeruid would draw it otherwise: the switch's review, finding 1) and nothing more -- no hook, no recognizer, MacPointer's word not read.
// Built on the follow before the switch (1.8.9's ResizeFact.h before it, from tools/test-macresizecursor.sh) the off rows must fail.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <notify.h>   // (first: the calls below are the harness's own, by the macros after the stand-ins)
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "common/MacPointerStatus.h"   // (MacPointer's word: as StatusBar.x has it before ResizeFact.h; -I the tree)

static int fails = 0, passes = 0;
static void Check(BOOL ok, NSString *what) {
    if (ok) passes++; else fails++;
    printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String);
}

// ---- the stand-ins for StatusBar.x ----
static NSMutableArray<NSString *> *gLog;   // (what ResizeFact.h logged, for the failure detail)
static void DMLog(NSString *s) { [gLog addObject:s ?: @""]; }
#define DM_FEATURE_MARK(name) do { } while (0)
#define DMTestFlag(path) 0
typedef enum { DMEngineNone = 0, DMEngineMilkyWay, DMEngineAerial, DMEngineZetsu } DMEngine;
static DMEngine gEngine = DMEngineZetsu;
static DMEngine DMActiveEngine(void) { return gEngine; }
static NSArray<UIView *> *gStages;
static NSArray<UIView *> *DMAerialStages(void) { return gStages ?: @[]; }
static BOOL DMStageMinimized(UIView *stage) { (void)stage; return NO; }
static id DMStageValue(UIView *stage, NSArray<NSString *> *keys) { (void)stage; (void)keys; return nil; }
static const void *kStageClosingKey = &kStageClosingKey, *kStageEnteringKey = &kStageEnteringKey, *kStageGripBLKey = &kStageGripBLKey, *kStageGripBRKey = &kStageGripBRKey;
static const void *kA5GripBLKey = &kA5GripBLKey, *kA5GripBRKey = &kA5GripBRKey, *kZetsuGripLKey = &kZetsuGripLKey, *kZetsuGripRKey = &kZetsuGripRKey, *kMWGripKey = &kMWGripKey;
static char kA5MinWatchedKey;
@interface DMA5GripBox : UIView
@property (nonatomic, weak) UIView *handle;
@end
@implementation DMA5GripBox
@end
static CGPoint *DMA5CornerOffsetAt(UIView *stage) { (void)stage; return NULL; }
static CGRect *DMA5ResizeStartAt(UIView *stage) { (void)stage; return NULL; }
static CGSize DMEngineWindowMin(void) { return CGSizeMake(320, 324); }
#define kMSBDWindowMinWidth 320.0
static const CGFloat kSM17MinWindowHeight = 300.0;
static CGSize MSBDWindowMinSize(void) { return CGSizeMake(320, 324); }
static BOOL DMSMEngine(void) { return NO; }
static int DMSMLayoutGen(void) { return 18; }
static NSString *DMSMNorm(const char *t) { NSMutableString *s = [NSMutableString string]; for (const char *p = t; p && *p; p++) if (*p < '0' || *p > '9') [s appendFormat:@"%c", *p]; return s; }
static NSString *DMSMSigOfMethod(Method m) { return m ? DMSMNorm(method_getTypeEncoding(m)) : nil; }
static NSString *DMSMExpect(const char *ret, ...) {
    NSMutableString *s = [NSMutableString stringWithFormat:@"%s@:", ret];
    va_list ap; va_start(ap, ret); for (const char *a = va_arg(ap, const char *); a; a = va_arg(ap, const char *)) [s appendString:@(a)]; va_end(ap);
    return s;
}
static CGFloat gSoftKeyboardH = 0;
static NSArray<UIWindow *> *gWindows;
static NSArray<UIWindow *> *DMAllWindows(void) { return gWindows ?: @[]; }
static BOOL DMSBIsBarWindowName(NSString *name) { return [name isEqualToString:@"UIStatusBarWindow"]; }
static BOOL DMWindowWorkNeeded(void) { return YES; }
static int gSkipped = 0;   // (RZT_SKIPPED: the crash guard's piece off)
static int MSBDCrashSkipped(const char *piece) { return gSkipped && strcmp(piece, "resizePointers") == 0; }
static BOOL gDMPointerAttached = YES;
__attribute__((unused)) static BOOL gDMPtrResizeOn = NO;   // (Settings > Pointer > Mac Resize Pointers as the bridge read it; the old follow never reads it)
@interface DMPtrHoverRecognizer : UIHoverGestureRecognizer
@end
@implementation DMPtrHoverRecognizer
@end
// Substrate's message hook: counted, the original handed back.
static int gHooks = 0;
static void MSHookMessageEx(Class c, SEL s, IMP imp, IMP *orig) { (void)imp; gHooks++; Method m = class_getInstanceMethod(c, s); if (orig) *orig = m ? method_getImplementation(m) : NULL; }
// Darwin notifications: every call kept (name, and the state set), MacPointer's word made to say "draws".
static NSMutableArray<NSString *> *gNotes;
static NSMutableDictionary<NSNumber *, NSString *> *gTokenNames;
static uint64_t gMPStatusWord;
static int gNextToken = 100;
static uint32_t RZTNoteRegisterCheck(const char *name, int *t) { [gNotes addObject:[NSString stringWithFormat:@"register %s", name]]; *t = gNextToken++; gTokenNames[@(*t)] = @(name); return NOTIFY_STATUS_OK; }
static uint32_t RZTNoteRegisterDispatch(const char *name, int *t, dispatch_queue_t q, notify_handler_t h) { (void)q; (void)h; [gNotes addObject:[NSString stringWithFormat:@"dispatch %s", name]]; *t = gNextToken++; gTokenNames[@(*t)] = @(name); return NOTIFY_STATUS_OK; }
static uint32_t RZTNoteSetState(int t, uint64_t v) { [gNotes addObject:[NSString stringWithFormat:@"set %@ 0x%llx", gTokenNames[@(t)], v]]; return NOTIFY_STATUS_OK; }
static uint32_t RZTNoteGetState(int t, uint64_t *v) {
    NSString *n = gTokenNames[@(t)];
    [gNotes addObject:[NSString stringWithFormat:@"get %@", n]];
    *v = [n isEqualToString:@MSBD_MP_STATUS] ? gMPStatusWord : 0;
    return NOTIFY_STATUS_OK;
}
static uint32_t RZTNotePost(const char *name) { [gNotes addObject:[NSString stringWithFormat:@"post %s", name]]; return NOTIFY_STATUS_OK; }
#define notify_register_check RZTNoteRegisterCheck
#define notify_register_dispatch RZTNoteRegisterDispatch
#define notify_set_state RZTNoteSetState
#define notify_get_state RZTNoteGetState
#define notify_post RZTNotePost

// Apple's window container with the hovered-edge method ResizeFact.h hooks (its types as on iPadOS 16-18: v@:Q).
@interface SBFluidSwitcherItemContainer : UIView
- (void)_updateForPointerHoveringOverEdge:(unsigned long long)edge;
@end
@implementation SBFluidSwitcherItemContainer
- (void)_updateForPointerHoveringOverEdge:(unsigned long long)edge { (void)edge; }
@end

#include RZ_FACT_H

static NSUInteger OurRecognizers(UIWindow *w) {
    NSUInteger n = 0;
    for (UIGestureRecognizer *g in w.gestureRecognizers) if ([g isKindOfClass:[DMPtrHoverRecognizer class]]) n++;
    return n;
}
static BOOL NoteSeen(NSString *prefix) { for (NSString *n in gNotes) if ([n hasPrefix:prefix]) return YES; return NO; }
static NSString *Notes(void) { return gNotes.count ? [gNotes componentsJoinedByString:@"; "] : @"none"; }

int main(void) {
    @autoreleasepool {
        gLog = [NSMutableArray array]; gNotes = [NSMutableArray array]; gTokenNames = [NSMutableDictionary dictionary];
        gMPStatusWord = MSBDMPPack(4242, MSBD_MP_V_ALONE, 0, 0, 0);
        Check(MSBDMPVerdictDraws(MSBDMPVerdict(gMPStatusWord)), @"the stand-in MacPointer says it draws (alone)");
        // a system gestures window (UIKit's own class, as SpringBoard has it) and a Zetsu window with its bottom-left grip box, shown
        Class sgw = objc_getClass("_UISystemGestureWindow");
        UIWindow *gestures = [[sgw alloc] initWithFrame:CGRectMake(0, 0, 1366, 1024)];
        gestures.hidden = NO;
        UIWindow *zetsu = [[UIWindow alloc] initWithFrame:CGRectMake(100, 100, 600, 400)];
        zetsu.hidden = NO;
        UIView *grip = [[UIView alloc] initWithFrame:CGRectMake(0, 368, 32, 32)];
        [zetsu addSubview:grip];
        objc_setAssociatedObject(zetsu, kZetsuGripLKey, grip, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        gStages = @[zetsu]; gWindows = @[gestures, zetsu];
        Check(sgw && [NSStringFromClass([gestures class]) isEqualToString:@"_UISystemGestureWindow"] && OurRecognizers(gestures) == 0, @"the stage: UIKit's system gestures window, no recognizer of ours yet");
        if (getenv("RZT_SKIPPED")) {   // the crash guard's piece off, Mac Resize Pointers on (iPadOS 18's default), everything else on
            gSkipped = 1; gDMPtrResizeOn = YES;
            for (int i = 0; i < 4; i++) DMRZFollow(YES);
            NSUInteger clears = 0; for (NSString *n in gNotes) if ([n isEqualToString:@"set " MSBD_RZ_NOTE " 0x0"]) clears++;
            Check(clears == 1 && NoteSeen(@"post " MSBD_RZ_NOTE), [NSString stringWithFormat:@"piece off, switch on: an earlier SpringBoard's word cleared once (notes: %@)", Notes()]);
            Check(gHooks == 0 && OurRecognizers(gestures) == 0, [NSString stringWithFormat:@"piece off: no hook (%d), no recognizer (%lu)", gHooks, (unsigned long)OurRecognizers(gestures)]);
            Check(!NoteSeen(@"register " MSBD_MP_STATUS) && !NoteSeen(@"dispatch "), [NSString stringWithFormat:@"piece off: MacPointer's word not read, no fade watch (notes: %@)", Notes()]);
            [gNotes removeAllObjects]; gDMPtrResizeOn = NO; DMRZFollow(YES); gDMPtrResizeOn = YES; DMRZFollow(YES);
            Check(gNotes.count == 0, [NSString stringWithFormat:@"piece off: switched off and on again, nothing more said (notes: %@)", Notes()]);
            printf("test-macresizeswitch (piece off): %d passed, %d failed\n", passes, fails);
            return fails ? 1 : 0;
        }

        // 1. the switch off (iPadOS 15-17 by default), everything else on: the first follow and three 2 s follows
        gDMPtrResizeOn = NO;
        for (int i = 0; i < 4; i++) DMRZFollow(YES);
        Check(gHooks == 0, [NSString stringWithFormat:@"off: no hook of the windows' hovered edge (hooks %d)", gHooks]);
        Check(OurRecognizers(gestures) == 0, [NSString stringWithFormat:@"off: no recognizer on the system gestures window (%lu)", (unsigned long)OurRecognizers(gestures)]);
        Check(!NoteSeen(@"register " MSBD_RZ_NOTE) && !NoteSeen(@"post " MSBD_RZ_NOTE) && !NoteSeen(@"set " MSBD_RZ_NOTE), [NSString stringWithFormat:@"off: no word on the resize note (notes: %@)", Notes()]);
        Check(!NoteSeen(@"register " MSBD_MP_STATUS) && !NoteSeen(@"get " MSBD_MP_STATUS), [NSString stringWithFormat:@"off: MacPointer's word not even read (notes: %@)", Notes()]);
        Check(!NoteSeen(@"dispatch "), [NSString stringWithFormat:@"off: no fade watch registered (notes: %@)", Notes()]);
        Check(gNotes.count == 0, [NSString stringWithFormat:@"off: no Darwin notification call at all (notes: %@)", Notes()]);
        SBFluidSwitcherItemContainer *c = [[SBFluidSwitcherItemContainer alloc] initWithFrame:CGRectMake(200, 100, 600, 500)];   // (a window's container)
        [gestures addSubview:c];
        // the other offs: Pointer Style iPadOS, no trackpad or mouse -- with the switch on too
        gDMPtrResizeOn = YES; gDMPointerAttached = NO; DMRZFollow(YES); DMRZFollow(NO); DMRZFollow(YES);
        NSUInteger clears = 0; for (NSString *n in gNotes) if ([n isEqualToString:@"set " MSBD_RZ_NOTE " 0x0"]) clears++;
        Check(gHooks == 0 && OurRecognizers(gestures) == 0 && !NoteSeen(@"get " MSBD_MP_STATUS) && clears == 1,
              [NSString stringWithFormat:@"on, but no trackpad or mouse (or Pointer Style iPadOS): nothing installed or read, an earlier SpringBoard's word cleared once (notes: %@)", Notes()]);
        [gNotes removeAllObjects];

        // 2. the switch on (iPadOS 18 by default, or the user's choice on 15-17)
        gDMPointerAttached = YES; gDMPtrResizeOn = YES;
        DMRZFollow(YES);
        Check(gHooks == 1, [NSString stringWithFormat:@"on: the hovered edge's hook goes in (hooks %d)", gHooks]);
        Check(OurRecognizers(gestures) == 1, [NSString stringWithFormat:@"on: the recognizer on the system gestures window (%lu)", (unsigned long)OurRecognizers(gestures)]);
        Check(!NoteSeen(@"set " MSBD_RZ_NOTE) && !NoteSeen(@"post " MSBD_RZ_NOTE), [NSString stringWithFormat:@"on: nothing said at the switch-on (the earlier word was cleared already; notes: %@)", Notes()]);
        [gNotes removeAllObjects];
        DMRZHoverEdge(c, @selector(_updateForPointerHoveringOverEdge:), 4);   // (right edge)
        BOOL said = NO; for (NSString *n in gNotes) if ([n hasPrefix:@"set " MSBD_RZ_NOTE " "] && ![n hasSuffix:@" 0x0"]) said = YES;
        Check(said, [NSString stringWithFormat:@"on: a band's hover says its fact (notes: %@)", Notes()]);

        // 3. off again (the user's choice): the fact and the recognizer go; the hook stays in (it cannot come out) and passes straight through
        gDMPtrResizeOn = NO; [gNotes removeAllObjects];
        DMRZFollow(YES);
        Check(NoteSeen(@"set " MSBD_RZ_NOTE " 0x0"), [NSString stringWithFormat:@"off again: the fact goes (notes: %@)", Notes()]);
        Check(OurRecognizers(gestures) == 0, @"off again: the recognizer goes");
        [gNotes removeAllObjects];
        DMRZHoverEdge(c, @selector(_updateForPointerHoveringOverEdge:), 1);
        DMRZFollow(YES); DMRZFollow(YES);
        Check(gNotes.count == 0, [NSString stringWithFormat:@"off again: a band's hover and the 2 s follows say nothing (notes: %@)", Notes()]);
        // 4. on again: no second hook, the recognizer back
        gDMPtrResizeOn = YES; DMRZFollow(YES);
        Check(gHooks == 1 && OurRecognizers(gestures) == 1, [NSString stringWithFormat:@"on again: the hook once only (hooks %d), the recognizer back (%lu)", gHooks, (unsigned long)OurRecognizers(gestures)]);
        gDMPtrResizeOn = NO; DMRZFollow(YES);
    }
    printf("test-macresizeswitch: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
}
