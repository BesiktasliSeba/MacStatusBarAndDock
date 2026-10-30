// common/PointerAnim.h -- MacStatusBar&Dock 1.5.1: Apple's Pointer Animations (Accessibility > Pointer Control) with the Mac pointer, the decision
// alone (StatusBar.x DMPointerAnimSync does the reading and writing; Mac test tools/test-pointeranim.sh). Plain C.
// The Mac pointer turns Pointer Animations off once per Mac-pointer period -- the user's own value kept -- and never again in that period (turned back
// on by the user, it stays on), but for Apple's Reduce Motion switch turning them on with it (DMPtrAnimAfterLook, 1.7.0). When the Mac pointer goes
// (the iPadOS pointer picked, the tweak switched off or removed), the kept value comes back, but only while Pointer Animations are still off as we
// left them: a value the user chose since is theirs.
#pragma once
#include <stdbool.h>

typedef struct {
    int set;           // 0 nothing, 1 turn Pointer Animations off, 2 turn them on
    bool applied;      // the Mac pointer's switch-off was applied in this period (stored)
    bool keepSaved;    // the user's own value is stored (in saved)
    bool saved;        // that value
} DMPtrAnimStep;

// Whether the Mac pointer counts for this decision (KT, 25 Oct, after the 1.5.1 logic test): whenever it is SELECTED -- Pointer Style Mac --, with or
// without a mouse or trackpad and whether MacPointer has said anything yet (its state 0, pointeruid not started) or not. It does not count while
// MacPointer stands down for another pointer tweak (state 2: the pointer is not ours), nor while Mac Status Bar is switched off or being removed
// (whatever Pointer Style says: the give-back must not be undone by the next refresh -- logic test B1).
static inline bool DMPtrAnimIsMacPointer(bool styleMac, unsigned long long macPointerState, bool offOrRemoved) {
    return styleMac && macPointerState != 2 && !offOrRemoved;
}
// macPointer: the Mac pointer is the pointer now. applied / savedPresent / saved: what is stored. current: Pointer Animations are on now.
static inline DMPtrAnimStep DMPtrAnimDecide(bool macPointer, bool applied, bool savedPresent, bool saved, bool current) {
    DMPtrAnimStep r = { 0, applied, savedPresent, saved };
    if (macPointer) {
        if (applied) return r;   // (once per period: whatever the user does with it afterwards is theirs)
        r.set = current ? 1 : 0;
        r.applied = true; r.keepSaved = true; r.saved = current;
        return r;
    }
    if (!applied) return r;   // (nothing of ours to give back)
    bool user = savedPresent ? saved : true;   // (no value kept: Apple's default, on)
    r.set = (user && !current) ? 2 : 0;          // (only while it is still off as we left it)
    r.applied = false; r.keepSaved = false; r.saved = false;
    return r;
}
// 1.7.0 (KT): Apple's Reduce Motion switch sets Pointer Animations too -- iPadOS 15.6.1's _AXSSetReduceMotionEnabled(on) is
// _AXSSetReduceMotionEnabledApp(on), then _AXSPointerAllowAppCustomizationSetEnabled(!on) and _AXSPointerEffectScalingSetEnabled(!on), whoever
// flips it (Settings, Shortcuts, Siri) -- so Reduce Motion on and off again turned them back on while the Mac pointer is selected, our switch-off
// being once per period. After the switch-off of this period, each look at the two settings (StatusBar.x DMPointerAnimFollow) tells the two apart:
// Pointer Animations that changed together with Reduce Motion (it changed since the last look, or its change notice came lately) and are now its
// opposite are Apple's doing; any other change is the user's own and stands (userOn: they turned them on themselves). Apple's "on" is taken back
// unless the user had turned them on; Apple's "off" (Reduce Motion on) is left as Apple has it.
typedef struct {
    int set;        // 0 nothing, 1 turn Pointer Animations off (Apple's Reduce Motion switch turned them on)
    bool userOn;    // the user turned them on themselves in this period (stored)
    int by;         // who changed Pointer Animations since the last look: 0 nobody, 1 Apple's Reduce Motion switch, 2 the user
} DMPtrAnimLook;
static inline DMPtrAnimLook DMPtrAnimAfterLook(bool rmBefore, bool paBefore, bool rmNow, bool paNow, bool rmNoticed, bool userOn) {
    DMPtrAnimLook r = { 0, userOn, 0 };
    if (paNow == paBefore) return r;   // (Pointer Animations as at the last look: nothing to tell)
    bool apples = (rmNow != rmBefore || rmNoticed) && paNow == !rmNow;
    if (!apples) { r.by = 2; r.userOn = paNow; return r; }   // (the user's own change: theirs)
    r.by = 1;
    if (paNow && !userOn) r.set = 1;   // (Reduce Motion went off and took them on with it: off again)
    return r;
}
