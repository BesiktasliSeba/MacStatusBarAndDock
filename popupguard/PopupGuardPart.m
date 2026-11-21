// MacPopupGuard (1.8.8.1 B68): the LNPopupController race guard (common/PopupGuard.h) on its own, for the package managers built on that
// library (Sileo, Zebra): their queue bar no longer ends up hidden while they believe it is shown -- a Queue tap then opened an invisible popup over
// a dimmed window -- when a window changes size or the queue changes quickly. The loader opens this part only in a recovery app that contains the
// library (loader/Loader.c MSBDRecoveryApp, MSBDHasPopupLibrary), and nothing else of ours there; on an untested iPadOS or in the crash guard's
// safe mode not at all (rows only). Every other app gets the same guard from MacAppBridge. No UIKit asked: the runtime only, from the app's first
// main-queue turn (as MacAppBridge installs it).
#import <substrate.h>
#import <Foundation/Foundation.h>
#include "../common/PopupGuard.h"

__attribute__((constructor)) static void MSBDPopupGuardPartStart(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        Class vc = objc_getClass("UIViewController");
        if (objc_getClass("LNPopupBar") && vc) MSBDPopupGuardInstall(vc);
    });
}
