// DndSwitchShim.h -- MacStatusBar&Dock 1.8.7.8: a narrow WORKAROUND for another tweak's defect, not a fix of ours (GitHub #14, crash 4).
// A class named DndSwitch from another tweak (NSObject <SwitchProtocol>) reads the Do Not Disturb state by adding itself to Do Not Disturb's
// DNDStateService as a state listener (-addStateUpdateListener:error:), but has no -stateService:didReceiveDoNotDisturbStateUpdate:, the one
// method a listener is sent, and never takes itself off. Do Not Disturb sends that method to each listener it holds (weakly) on its call-out
// queue at every state change, without asking first: a change that lands while such an object is alive is an unrecognized selector there, and
// SpringBoard aborts with only Apple code on the stack (com.apple.donotdisturb.StateService.call-out; fixture tools/crash-fixtures/
// real-issue14-dnd-listener.ips).
// Once, after SpringBoard has loaded its libraries (StatusBar.x's constructor hands it to the main queue), that class is given an empty method
// of that name, and only when all of these hold: the class exists, a protocol named SwitchProtocol exists and the class adopts it, and neither
// the class nor a superclass answers the selector. class_addMethod never replaces a method. No hook: nothing of SpringBoard's or Do Not
// Disturb's changes, and no other class is touched. Plain Objective-C runtime: the Mac test tools/test-dndswitch-shim.sh runs it with stand-ins.
#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// (a DND state update for such an object: not wanted, it reads the state once -- nothing done)
static void MSBDDndSwitchUpdateIgnored(id self, SEL _cmd, id service, id update) { (void)self; (void)_cmd; (void)service; (void)update; }

typedef NS_ENUM(int, MSBDDndShimResult) {
    MSBDDndShimNoClass = 0,       // (no class named DndSwitch: nothing to do)
    MSBDDndShimNoProtocol,        // (no protocol named SwitchProtocol: not the class this is for)
    MSBDDndShimNotAdopted,        // (a DndSwitch that does not adopt SwitchProtocol: not the class this is for)
    MSBDDndShimHasIt,             // (it answers the selector already: left as it is)
    MSBDDndShimAdded,             // (the empty method added)
    MSBDDndShimNotAdded,          // (class_addMethod said no)
};
static inline MSBDDndShimResult MSBDDndSwitchShim(void) {
    Class c = objc_getClass("DndSwitch");
    if (!c) return MSBDDndShimNoClass;
    Protocol *p = objc_getProtocol("SwitchProtocol");
    if (!p) return MSBDDndShimNoProtocol;
    if (!class_conformsToProtocol(c, p)) return MSBDDndShimNotAdopted;
    SEL sel = sel_registerName("stateService:didReceiveDoNotDisturbStateUpdate:");
    if (class_respondsToSelector(c, sel)) return MSBDDndShimHasIt;
    return class_addMethod(c, sel, (IMP)MSBDDndSwitchUpdateIgnored, "v32@0:8@16@24") ? MSBDDndShimAdded : MSBDDndShimNotAdded;
}
static inline const char *MSBDDndShimText(MSBDDndShimResult r) {
    switch (r) {
        case MSBDDndShimNoClass: return "no DndSwitch class: nothing added";
        case MSBDDndShimNoProtocol: return "a DndSwitch class, no SwitchProtocol: nothing added";
        case MSBDDndShimNotAdopted: return "a DndSwitch class without SwitchProtocol: nothing added";
        case MSBDDndShimHasIt: return "another tweak's DndSwitch has the DND listener method: left as it is";
        case MSBDDndShimAdded: return "another tweak's DndSwitch had no DND listener method: an empty one added (its state updates are no crash now)";
        case MSBDDndShimNotAdded: return "another tweak's DndSwitch had no DND listener method: not added (class_addMethod said no)";
    }
    return "?";
}
