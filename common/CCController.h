// CCController.h -- Control Center's controller in SpringBoard, for every part that asks whether Control Center is up or puts it away
// (statusbar/StatusBar.x, dock/Dock.x). 15-17: +[SBControlCenterController sharedInstance]. iPadOS 18 has no shared instance (read on 18.5): Control
// Center belongs to each window scene there (-[SBWindowScene controlCenterController], the same class with the same -isPresented / -isVisible /
// -isPresentedOrDismissing / -presentAnimated: / -dismissAnimated:), so every call made through the shared instance did nothing on 18 -- "Open
// Activity Monitor" in the RAM & CPU panel left Control Center open over the window, and every "is Control Center up?" said no (A12Z, 1.7.0).
// There: the controller of SpringBoard's scene on the iPad's own screen. nil where neither is there.
#pragma once
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "AlertQueue.h"   // (MSBDMainWindowScene: SpringBoard's scene on the iPad's own screen)

static inline id MSBDControlCenterController(void) {
    Class c = objc_getClass("SBControlCenterController");
    if (!c) return nil;
    SEL shared = NSSelectorFromString(@"sharedInstance");
    if ([(id)c respondsToSelector:shared]) return ((id (*)(id, SEL))objc_msgSend)((id)c, shared);
    UIWindowScene *scene = MSBDMainWindowScene();
    SEL own = NSSelectorFromString(@"controlCenterController");
    id cc = [scene respondsToSelector:own] ? ((id (*)(id, SEL))objc_msgSend)(scene, own) : nil;
    return [cc isKindOfClass:c] ? cc : nil;
}
