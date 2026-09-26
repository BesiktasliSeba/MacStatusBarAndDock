// OffAlert.h -- the "MacStatusBar Is Off" alert, shown by the Dock's SpringBoard part (MacDock line), 2026-09-26.
// MacSettings' root helper (sshtoggled) gives the window engines their user's own settings back when MacStatusBar is switched off in Choicy or
// iCleaner Pro. Normally it does that the moment the switch is flipped, so the user's own respring finishes it. If it only noticed after a respring
// (its slow fallback), it asks for one more: a daemon cannot show a system alert on iOS 15, so SpringBoard shows it, stock-style. It used to live in
// MacSettingsBadge, which only the MacStatusBar line loads -- exactly the line that is off when the alert is needed -- so it could never appear.
#pragma once
#import <UIKit/UIKit.h>
#import <objc/message.h>
#include <notify.h>
#include <sys/stat.h>
#include <time.h>
#import "AlertQueue.h"   // (one alert of ours at a time, never over the Lock Screen)

static UIWindow *gMSBDOffAlertWindow;
static void MSBDPresentMacStatusBarOffAlert(NSString *msg, int attempt);
static void MSBDShowMacStatusBarOffAlert(void) {
    // Anyone can post com.besiktasliseba.msb.offrestored, so the alert is shown only for a real switch-off: the helper's root-owned marker must
    // exist, the root-owned alert file must be recent (under 5 minutes), and each alert file is shown once (SpringBoard cannot delete it).
    static time_t shownFor = 0;
    struct stat mk, al;
    if (lstat("/var/jb/var/lib/sshtoggled-engines/msb-off-restored", &mk) != 0 || !S_ISREG(mk.st_mode) || mk.st_uid != 0) return;
    if (lstat("/var/jb/var/lib/sshtoggled-engines/msb-off-alert", &al) != 0 || !S_ISREG(al.st_mode) || al.st_uid != 0) return;
    if (time(NULL) - al.st_mtime > 300 || al.st_mtime == shownFor) return;
    NSString *msg = [NSString stringWithContentsOfFile:@"/var/jb/var/lib/sshtoggled-engines/msb-off-alert" encoding:NSUTF8StringEncoding error:nil];
    if (!msg.length || gMSBDOffAlertWindow) return;
    shownFor = al.st_mtime;
    MSBDPresentMacStatusBarOffAlert(msg, 0);
}
// Shown when the iPad is unlocked and no other alert of ours is up (checked once a second, for up to 10 minutes); put away when the iPad locks
// (its Respring button must never work over the Lock Screen) and shown again after the unlock, until one of its buttons is used.
static void MSBDPresentMacStatusBarOffAlert(NSString *msg, int attempt) {
    if (gMSBDOffAlertWindow) return;
    if (MSBDAlertLockedOrCovered() || MSBDAlertBusy(nil)) {
        if (attempt < 600) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ MSBDPresentMacStatusBarOffAlert(msg, attempt + 1); });
        return;
    }
    UIWindow *w = MSBDMakeAlertWindow(UIWindowLevelAlert + 1);
    gMSBDOffAlertWindow = w;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"MacStatusBar Is Off" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) { gMSBDOffAlertWindow.hidden = YES; gMSBDOffAlertWindow = nil; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Respring" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        gMSBDOffAlertWindow.hidden = YES; gMSBDOffAlertWindow = nil;
        SEL relaunch = NSSelectorFromString(@"_relaunchSpringBoardNow");
        if ([[UIApplication sharedApplication] respondsToSelector:relaunch]) ((void (*)(id, SEL))objc_msgSend)([UIApplication sharedApplication], relaunch);
    }]];
#if DEBUG   // (test evidence: the MacStatusBar line, which has the screen captures, is off while this alert shows)
    FILE *lf = fopen("/tmp/msbd-offalert.log", "a");
    if (lf) { fprintf(lf, "%ld shown: %s\n", (long)time(NULL), msg.UTF8String); fclose(lf); }
    [w.rootViewController presentViewController:a animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:w.bounds.size];
            UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *c) { [w drawViewHierarchyInRect:w.bounds afterScreenUpdates:NO]; }];
            [UIImagePNGRepresentation(img) writeToFile:@"/tmp/msbd-offalert.png" atomically:YES];
        });
    }];
#else
    [w.rootViewController presentViewController:a animated:YES completion:nil];
#endif
    MSBDAlertCloseOnLock(w, ^{
        if (gMSBDOffAlertWindow == w) gMSBDOffAlertWindow = nil;
        MSBDPresentMacStatusBarOffAlert(msg, 0);   // (again after the unlock)
    });
}
// From SpringBoard's %ctor: listen for the helper's request.
static void MSBDWatchMacStatusBarOff(void) {
    static int t = 0;
    if (!t) notify_register_dispatch("com.besiktasliseba.msb.offrestored", &t, dispatch_get_main_queue(), ^(int tok) { MSBDShowMacStatusBarOffAlert(); });
}
