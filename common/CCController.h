// CCController.h -- Control Center's controller in SpringBoard, for every part that asks whether Control Center is up or puts it away
// (statusbar/StatusBar.x, dock/Dock.x). 15-17: +[SBControlCenterController sharedInstance]. iPadOS 18 has no shared instance (read on 18.5): Control
// Center belongs to each window scene there (-[SBWindowScene controlCenterController], the same class with the same -isPresented / -isVisible /
// -isPresentedOrDismissing / -presentAnimated: / -dismissAnimated:), so every call made through the shared instance did nothing on 18 -- "Open
// Activity Monitor" in the RAM & CPU panel left Control Center open over the window, and every "is Control Center up?" said no (A12Z, 1.7.0).
// There: the controller of SpringBoard's scene on the iPad's own screen. nil where neither is there.
// 15-17 (1.8.0.1): the shared instance as SpringBoard has made it, never made by us (common/SBShared.h): +sharedInstance made it when it was not
// there yet, and asked from our constructor before SpringBoard's launch had made its main workspace, -[SBControlCenterController init] raised and
// SpringBoard went down at its start (a slow start: the iPad 2 on 16.7.7, ElleKit's Safe Mode after it). Every caller asks or acts on Control Center
// SpringBoard has built (it builds it in its own launch); nil until then.
#pragma once
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "AlertQueue.h"   // (MSBDMainWindowScene: SpringBoard's scene on the iPad's own screen)
#import "SBShared.h"     // (MSBDSBSharedIfExists)

static inline id MSBDControlCenterController(void) {
    Class c = objc_getClass("SBControlCenterController");
    if (!c) return nil;
    SEL shared = NSSelectorFromString(@"sharedInstance");
    if ([(id)c respondsToSelector:shared]) return MSBDSBSharedIfExists(c);
    UIWindowScene *scene = MSBDMainWindowScene();
    SEL own = NSSelectorFromString(@"controlCenterController");
    id cc = [scene respondsToSelector:own] ? ((id (*)(id, SEL))objc_msgSend)(scene, own) : nil;
    return [cc isKindOfClass:c] ? cc : nil;
}
