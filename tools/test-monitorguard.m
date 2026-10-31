// Mac test of common/MonitorGuard.h (1.7.3 item 11): a window controller freed without its own close, as Zetsu's ZetsuAppController was on the M1
// (31 Oct). Stand-ins: a layer manager with a KVO-observable "layers", a scene monitor with a WEAK delegate whose -dealloc runs the guard (invalidate,
// and with the fix the owner's cleanup first), and an owner declared like Zetsu's (_manager, then _sceneMonitor: its .cxx_destruct releases the
// monitor first, while _manager is still set) that registers in -setHost: and undoes it only in -CloseAppWindow:.
// Checked: a normal close leaves nothing to do; a controller freed without its close leaves no observer behind (the guard removes its
// registrations: 1, or 2 when it registered twice) and the next change of "layers" is harmless; a monitor replaced while its owner lives does not
// take the owner's observation away; the scene's layer manager is cleaned too when the owner's own ivar is empty; and without the owner's cleanup
// (the guard as it was: invalidate only) the freed controller stays registered -- the state iOS 15's KVO crashed on at the next change of the
// layers. (This Mac's Foundation, macOS 15, skips a freed observer when it notifies -- checked: no call, no crash --, so the crash itself cannot be
// shown here; iOS 15.6.1's did message it.) Run by test-monitorguard.sh.
#import "../common/MonitorGuard.h"
static int gFail = 0, gPass = 0;
#define CHECK(cond, what) do { if (cond) gPass++; else { gFail++; printf("FAIL: %s\n", what); } } while (0)

@interface FakeLayerManager : NSObject
@property (nonatomic, copy) NSSet *layers;
@end
@implementation FakeLayerManager @end

static BOOL gCleanup = YES;   // (the fix on / off)
static int gRemoved = 0, gGuarded = 0;
static id gAlso = nil;        // (the monitor's scene's layer manager, as SpringBoard passes it)
static NSString *gOwnerClass = nil;
@interface FakeMonitor : NSObject {
@public
    BOOL _invalidated;
    __weak id _delegate;
    int _notAnObject;
}
- (void)invalidate;
@end
@implementation FakeMonitor
- (void)invalidate { _invalidated = YES; }
- (void)dealloc {   // (StatusBar.x %group SceneMonitorGuard: a monitor still valid here -- the owner's cleanup, then FrontBoard's own invalidate)
    if (!_invalidated) {
        gGuarded++;
        if (gCleanup) { NSString *c = nil; gRemoved += MSBDMonitorOwnerCleanup(self, "_manager", gAlso, kMSBDMonitorOwnerKeyPath, &c); if (c) gOwnerClass = c; }
        [self invalidate];
    }
}
@end

@interface ZetsuAppController : NSObject {
    FakeLayerManager *_manager;   // (declared before the monitor, as in Zetsu 1.6.6: ivars 104 and 112)
    FakeMonitor *_sceneMonitor;
}
@property (nonatomic) int seen;
- (void)setHost:(FakeLayerManager *)m;
- (void)CloseAppWindow:(BOOL)kill;
- (void)forgetManager;
@end
@implementation ZetsuAppController
- (void)setHost:(FakeLayerManager *)m {   // (Zetsu: observe the scene's layer manager and keep a new monitor whose delegate this is)
    _manager = m;
    [m addObserver:self forKeyPath:@"layers" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:NULL];
    FakeMonitor *mon = [FakeMonitor new];
    mon->_delegate = self;
    _sceneMonitor = mon;   // (a previous one is released here, still valid: the guard sees a live owner)
}
- (void)CloseAppWindow:(BOOL)kill { [_manager removeObserver:self forKeyPath:@"layers"]; _manager = nil; [_sceneMonitor invalidate]; _sceneMonitor = nil; }
- (void)forgetManager { _manager = nil; }
- (void)observeValueForKeyPath:(NSString *)k ofObject:(id)o change:(NSDictionary *)c context:(void *)ctx { self.seen++; }
@end

int main(void) {
    @autoreleasepool {
        // 1. Zetsu's own close: the monitor is invalidated before it goes, nothing for the guard to do
        FakeLayerManager *lm = [FakeLayerManager new];
        @autoreleasepool { ZetsuAppController *z = [ZetsuAppController new]; [z setHost:lm]; [z CloseAppWindow:NO]; z = nil; }
        CHECK(gGuarded == 0 && gRemoved == 0, "a normal close: the guard has nothing to do");
        CHECK(lm.observationInfo == NULL, "a normal close: no observer left");
        // 2. freed without its close (the M1 case): its registration is removed by the guard, the next change is harmless
        gOwnerClass = nil;
        @autoreleasepool { ZetsuAppController *z = [ZetsuAppController new]; [z setHost:lm]; CHECK(lm.observationInfo != NULL, "setHost: registered"); z = nil; }
        CHECK(gGuarded == 1, "freed without its close: the guard saw a valid monitor");
        CHECK(gRemoved == 1, "freed without its close: its one registration removed");
        CHECK([gOwnerClass isEqualToString:@"ZetsuAppController"], "the owner named as the controller");
        CHECK(lm.observationInfo == NULL, "freed without its close: no observer left");
        lm.layers = [NSSet setWithObject:@2];   // (would message the freed controller without the cleanup)
        CHECK(YES, "a change of layers after it is harmless");
        // 3. registered twice (two setHost:), freed without its close: the first monitor goes while its owner lives (left observing), both
        //    registrations go with the second
        gRemoved = 0; gGuarded = 0;
        __attribute__((unused)) ZetsuAppController *keep = nil;
        @autoreleasepool {
            ZetsuAppController *z = [ZetsuAppController new];
            [z setHost:lm]; [z setHost:lm];
            CHECK(gGuarded == 1 && gRemoved == 0, "a monitor replaced while its owner lives: invalidated, the owner's observation kept");
            int before = z.seen; lm.layers = [NSSet setWithObject:@3];
            CHECK(z.seen == before + 2, "the live owner still gets the changes (twice: registered twice)");
            keep = z; z = nil;
        }
        keep = nil;
        CHECK(gGuarded == 2 && gRemoved == 2, "freed without its close after two registrations: both removed");
        CHECK(lm.observationInfo == NULL, "and no observer left");
        lm.layers = [NSSet setWithObject:@4];
        // 4. the owner's own ivar already empty: the scene's layer manager (passed by SpringBoard) is cleaned
        gRemoved = 0; gGuarded = 0;
        FakeLayerManager *scenes = [FakeLayerManager new];
        gAlso = scenes;
        @autoreleasepool { ZetsuAppController *z = [ZetsuAppController new]; [z setHost:scenes]; [z forgetManager]; z = nil; }
        CHECK(gGuarded == 1 && gRemoved == 1, "the owner's ivar empty: removed from the scene's layer manager");
        CHECK(scenes.observationInfo == NULL, "no observer left there");
        gAlso = nil;
        // 5. the helpers on their own
        FakeMonitor *m = [FakeMonitor new];
        CHECK(MSBDIvarRaw(m, "_notAnObject") == NULL, "an ivar that is not an object is not read");
        CHECK(MSBDIvarRaw(m, "_nothing") == NULL, "no such ivar: nothing");
        CHECK(MSBDMonitorOwnerGoing(m) == NULL, "no delegate: no owner");
        ZetsuAppController *live = [ZetsuAppController new];
        m->_delegate = live;
        CHECK(MSBDMonitorOwnerGoing(m) == NULL, "a delegate that lives is not taken for a going owner");
        CHECK(MSBDRemoveObservations(lm, (__bridge void *)live, @"layers") == 0, "removing a registration that is not there: nothing, no exception out");
        m->_invalidated = YES; m = nil; live = nil;
        // 6. the guard as it was (invalidate only): the freed controller stays registered -- iOS 15's KVO messaged it at the next change
        gCleanup = NO; gRemoved = 0; gGuarded = 0;
        FakeLayerManager *old = [FakeLayerManager new];
        @autoreleasepool { ZetsuAppController *z = [ZetsuAppController new]; [z setHost:old]; z = nil; }
        CHECK(gGuarded == 1 && gRemoved == 0 && old.observationInfo != NULL, "without the owner's cleanup a registration of the freed controller is left");
        gCleanup = YES;
    }
    printf("test-monitorguard: %d passed, %d failed\n", gPass, gFail);
    return gFail ? 1 : 0;
}
