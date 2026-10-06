// GuidedAccess.h -- Guided Access (Settings > Accessibility > Guided Access): one answer for every part of ours in SpringBoard (1.3.7, audit M-7).
// While a session runs, Guided Access keeps the iPad in one app. Its SpringBoard part (GAXSpringboardServer) stops SpringBoard's own ways out --
// app opens, URL opens, Spotlight, Command-Tab, the Dock, the switcher, icon launches and icon menus -- but nothing of ours: our menus, Finder
// windows, desktop, Downloads panel and traffic lights are SpringBoard UI it does not know, and touches reach them. So each of them steps aside
// while a session runs (statusbar/StatusBar.x DMGuidedAccessChanged, dock/Downloads.m, common/AlertQueue.h).
#pragma once
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <unistd.h>

// Is a Guided Access session running? SpringBoard's own flag, the one its Home button, banners and multitasking controls read
// (SBGuidedAccessIsActive(), kept by SBGuidedAccessListener from the session's start and stop); UIKit's public answer only where SpringBoard has
// neither (another process). Cheap: a function call and an ivar read.
static inline BOOL MSBDGuidedAccessActive(void) {
#if DEBUG
    if (access("/tmp/msb-fake-guided", F_OK) == 0) return YES;   // (debug builds: a session played for the device tests, trigger fakeguided_<0|1>)
#endif
    static BOOL (*sbIsActive)(void) = NULL;
    static Class listener = Nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sbIsActive = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "SBGuidedAccessIsActive");
        if (!sbIsActive) listener = objc_getClass("SBGuidedAccessListener");
    });
    if (sbIsActive) return sbIsActive();
    if (listener) {
        SEL shared = NSSelectorFromString(@"sharedGuidedAccessListener"), active = NSSelectorFromString(@"isGuidedAccessActive");
        id l = [listener respondsToSelector:shared] ? ((id (*)(id, SEL))objc_msgSend)((id)listener, shared) : nil;
        if (l && [l respondsToSelector:active]) return ((BOOL (*)(id, SEL))objc_msgSend)(l, active);
    }
    return [NSThread isMainThread] ? UIAccessibilityIsGuidedAccessEnabled() : NO;
}

// Calls `changed` on the main queue when a session starts or ends: SpringBoard's own notification (SBGuidedAccessActivationChangedNotification,
// posted by SBGuidedAccessListener), and UIKit's public one. Each caller registers once; the observers stay for the process's life.
static inline void MSBDGuidedAccessObserve(dispatch_block_t changed) {
    if (!changed) return;
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithObject:UIAccessibilityGuidedAccessStatusDidChangeNotification];
    NSString *__unsafe_unretained *sbName = (NSString *__unsafe_unretained *)dlsym(RTLD_DEFAULT, "SBGuidedAccessActivationChangedNotification");
    if (sbName && *sbName && [*sbName isKindOfClass:[NSString class]] && ![names containsObject:*sbName]) [names addObject:*sbName];
    dispatch_block_t block = [changed copy];
    for (NSString *n in names)
        [[NSNotificationCenter defaultCenter] addObserverForName:n object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) { block(); }];
}
