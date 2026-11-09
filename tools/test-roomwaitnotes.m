// test-roomwaitnotes.m -- Mac test of the Stage Manager notes while the windows wait for the Dock's room (1.8.4.1 item 8; review of the 1.8.4 fixes L2). During the wait no note was taken,
// so a window put in a layout since the start was in no layout at a turn. The code as built: test-roomwaitnotes.sh cuts it out of statusbar/StatusBar.x.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
static int fails = 0, checks = 0;
static void Expect(BOOL ok, NSString *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
@interface NSValue (CGRectStandIn)
+ (NSValue *)valueWithCGRect:(CGRect)r; - (CGRect)CGRectValue;
@end
@implementation NSValue (CGRectStandIn)
+ (NSValue *)valueWithCGRect:(CGRect)r { return [NSValue valueWithBytes:&r objCType:@encode(CGRect)]; }
- (CGRect)CGRectValue { CGRect r; [self getValue:&r]; return r; }
@end
@interface UIScreen : NSObject
+ (UIScreen *)mainScreen; @property (nonatomic, readonly) CGRect bounds;
@end
@implementation UIScreen
+ (UIScreen *)mainScreen { return [UIScreen new]; }
- (CGRect)bounds { return CGRectMake(0, 0, 1366, 1024); }
@end
static const CGFloat kSMBarH = 24.0;
static int gDMWindowsRoomPending = -1;
static NSMutableDictionary<NSString *, NSString *> *gSMTurnLayout;
static NSMutableDictionary<NSString *, NSString *> *DMSMTurnLayouts(void) { if (!gSMTurnLayout) gSMTurnLayout = [NSMutableDictionary dictionary]; return gSMTurnLayout; }
static NSDictionary<NSString *, NSString *> *gNow;
static NSDictionary<NSString *, NSString *> *DMSMLayoutsFor(NSDictionary<NSString *, NSValue *> *frames) { (void)frames; return gNow; }
#include "roomwait-gen.h"
static NSValue *R(CGFloat x, CGFloat y, CGFloat w, CGFloat h) { return [NSValue valueWithCGRect:CGRectMake(x, y, w, h)]; }
int main(void) { @autoreleasepool {
    gDMWindowsRoomPending = 1;
    gSMTurnLayout = [@{ @"fill": @"fill", @"old": @"left" } mutableCopy];
    NSDictionary *frames = @{ @"fill": R(0, 24, 1366, 1000), @"old": R(0, 24, 683, 1000), @"new": R(683, 24, 683, 900), @"full": R(0, -24, 1366, 1048) };
    gNow = @{ @"new": @"right", @"full": @"fill" };
    DMSMRoomWaitNote(frames);
    NSDictionary *m = DMSMRoomWaitMerged(DMSMTurnLayouts());
    Expect([m[@"new"] isEqual:@"right"], @"a window put in a layout during the wait is there at a turn");
    Expect([m[@"fill"] isEqual:@"fill"] && [m[@"old"] isEqual:@"left"], @"  ... the notes from before the start stay: a window placed for the other room is in no layout of this one");
    Expect(m[@"full"] == nil, @"  ... a full-screen window is noted no more than DMSMTurnNote notes it");
    Expect([gSMTurnLayout[@"new"] length] == 0, @"  ... kept apart: the notes themselves are untouched during the wait");
    gNow = @{};
    DMSMRoomWaitNote(frames);
    m = DMSMRoomWaitMerged(DMSMTurnLayouts());
    Expect(m[@"new"] == nil, @"it left that layout during the wait: gone again");
    Expect([m[@"old"] isEqual:@"left"], @"  ... an older note is not touched by a window that was never noted in the wait");
    gNow = @{ @"old": @"right" };
    DMSMRoomWaitNote(frames);
    m = DMSMRoomWaitMerged(DMSMTurnLayouts());
    Expect([m[@"old"] isEqual:@"right"], @"a window moved to another layout during the wait: the new one wins");
    DMSMRoomWaitLift();
    Expect(gDMWindowsRoomPending == -1, @"the lift ends the wait");
    Expect([gSMTurnLayout[@"old"] isEqual:@"right"], @"  ... what the wait kept joins the notes");
    Expect(gSMRoomWaitLayouts == nil, @"  ... and is forgotten");
    gSMRoomWaitLayouts = [@{ @"x": @"left" } mutableCopy]; gDMWindowsRoomPending = -1;
    m = DMSMRoomWaitMerged(DMSMTurnLayouts());
    Expect(m[@"x"] == nil && gSMRoomWaitLayouts == nil, @"the wait ended some other way: what it kept is dropped");
    printf("%s: %d checks, %d failed\n", fails ? "test-roomwaitnotes FAILED" : "test-roomwaitnotes: all pass", checks, fails);
    return fails ? 1 : 0;
} }
