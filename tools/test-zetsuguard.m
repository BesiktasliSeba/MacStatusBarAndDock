// Mac test of common/ZetsuGuard.h (1.5.0): Zetsu's dangling ZetsuAlertHostController observer, wrapped. A stand-in class of that name; a block
// that captures it unretained, as Zetsu's does; the notification posted while it lives (the block runs) and after it was freed (the wrapped block
// must not run -- unwrapped it would message freed memory). The controller is found among any of the block's captured words (also after other
// captured variables). Also: blocks with no capture, or that capture no live controller, are left alone; a new controller at a reused address
// never passes as the old one; the class is tracked once and a class with its own +allocWithZone: is left alone.
#import "../common/ZetsuGuard.h"
static int gFail = 0, gPass = 0;
#define CHECK(cond, what) do { if (cond) gPass++; else { gFail++; printf("FAIL: %s\n", what); } } while (0)

@interface ZetsuAlertHostController : NSObject
@property (nonatomic) int calls;
- (id)alertController;
@end
@implementation ZetsuAlertHostController
- (id)alertController { self.calls++; return nil; }
@end
@interface SubHost : ZetsuAlertHostController @end   // (a subclass: its +alloc reaches our added method with itself as the receiver)
@implementation SubHost @end
@interface OwnAllocHost : NSObject @end
@implementation OwnAllocHost
+ (id)allocWithZone:(struct _NSZone *)zone { return [super allocWithZone:zone]; }
@end
static int gRan = 0;

int main(void) {
    @autoreleasepool {
        CHECK(MSBDZetsuTrackHosts([ZetsuAlertHostController class]), "the class is tracked");
        CHECK(!MSBDZetsuTrackHosts([ZetsuAlertHostController class]), "tracked once (its +allocWithZone: is ours now)");
        CHECK(!MSBDZetsuTrackHosts([OwnAllocHost class]), "a class with its own +allocWithZone: is left alone");
        CHECK(!MSBDZetsuTrackHosts(Nil), "no class: nothing");
        @autoreleasepool {   // (logic test C1: this recursed until the stack overflowed)
            SubHost *sub = [SubHost new];
            CHECK(sub != nil && [sub isKindOfClass:[SubHost class]], "a subclass of the tracked class allocates (no recursion)");
            CHECK([gMSBDZetsuHosts containsObject:sub], "and its instance is tracked as a live controller");
            sub = nil;
        }
        CHECK(gMSBDZetsuHosts.allObjects.count == 0, "the subclass instance left the live set when freed");
        NSNotificationCenter *nc = [NSNotificationCenter new];
        id token = nil;
        @autoreleasepool {
            ZetsuAlertHostController *host = [ZetsuAlertHostController new];
            CHECK([gMSBDZetsuHosts containsObject:host], "a new controller is in the live set");
            __unsafe_unretained ZetsuAlertHostController *raw = host;   // (as Zetsu's block holds it: not kept alive)
            void (^zetsu)(NSNotification *) = ^(NSNotification *n) { gRan++; [raw alertController]; };
            id wrapped = MSBDZetsuGuardBlock(zetsu, gMSBDZetsuHosts);
            CHECK(wrapped != nil, "Zetsu's block is wrapped");
            token = [nc addObserverForName:kMSBDZetsuRemoveAlertNote object:nil queue:nil usingBlock:wrapped];
            [nc postNotificationName:kMSBDZetsuRemoveAlertNote object:nil];
            CHECK(gRan == 1 && host.calls == 1, "while the controller lives the block runs");
            host = nil;   // (freed here: ARC releases the last reference)
        }
        CHECK(gMSBDZetsuHosts.allObjects.count == 0, "the freed controller left the live set");
        // a new controller, likely at the same address: it must not count as the old one
        ZetsuAlertHostController *again = [ZetsuAlertHostController new];
        [nc postNotificationName:kMSBDZetsuRemoveAlertNote object:nil];
        CHECK(gRan == 1, "after the controller was freed the wrapped block does not run (even with a new controller around)");
        CHECK(again.calls == 0, "the new controller is not messaged by the old block");
        [nc removeObserver:token];
        // the controller captured after other variables (an object and a number before it): found all the same
        NSObject *other = [NSObject new];
        int gRan2 = 0; __block int *ran2 = &gRan2;
        @autoreleasepool {
            ZetsuAlertHostController *host2 = [ZetsuAlertHostController new];
            __unsafe_unretained ZetsuAlertHostController *raw2 = host2;
            long number = 42;
            void (^later)(NSNotification *) = ^(NSNotification *n) { (void)other; (void)number; (*ran2)++; [raw2 alertController]; };
            const void *words[16]; NSUInteger nw = MSBDBlockCaptureWords(later, words, 16);
            BOOL seen = NO; for (NSUInteger i = 0; i < nw; i++) if (words[i] == (__bridge const void *)host2) seen = YES;
            CHECK(nw >= 3 && seen, "the captured words include the controller (not the first one)");
            id wrapped2 = MSBDZetsuGuardBlock(later, gMSBDZetsuHosts);
            CHECK(wrapped2 != nil, "a block that captures the controller after other variables is wrapped");
            token = [nc addObserverForName:kMSBDZetsuRemoveAlertNote object:nil queue:nil usingBlock:wrapped2];
            [nc postNotificationName:kMSBDZetsuRemoveAlertNote object:nil];
            CHECK(gRan2 == 1 && host2.calls == 1, "it runs while that controller lives");
            host2 = nil;
        }
        [nc postNotificationName:kMSBDZetsuRemoveAlertNote object:nil];
        CHECK(gRan2 == 1, "and not after it was freed");
        [nc removeObserver:token];
        // blocks left alone
        void (^none)(NSNotification *) = ^(NSNotification *n) { gRan += 100; };
        CHECK(MSBDZetsuGuardBlock(none, gMSBDZetsuHosts) == nil, "a block with no capture is left alone");
        void (^notHost)(NSNotification *) = ^(NSNotification *n) { (void)other; };
        CHECK(MSBDZetsuGuardBlock(notHost, gMSBDZetsuHosts) == nil, "a block that captures no live controller is left alone");
        CHECK(MSBDZetsuGuardBlock(nil, gMSBDZetsuHosts) == nil, "no block: nothing");
        const void *w0[4];
        CHECK(MSBDBlockCaptureWords(none, w0, 4) == 0, "no capture: no word read");
        (void)again;
    }
    printf("test-zetsuguard: %d passed, %d failed\n", gPass, gFail);
    return gFail ? 1 : 0;
}
