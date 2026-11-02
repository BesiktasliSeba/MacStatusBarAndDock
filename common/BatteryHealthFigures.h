// BatteryHealthFigures.h -- the figures our Battery Health page shows (MacStatusBar&Dock 1.7.8): Apple's own Settings > Battery > Battery Health
// page, opened on iPad (macsettings/BatteryHealth.x), reads nothing there -- its getters answer -1 / "noBatteryData" on 15.6.1, 16.7.7, 17.5.1 and
// 18.5, and powerd publishes no "Maximum Capacity Percent" on iPad (plans/battery-charging.md, section 5). So the page gets ours, from the battery
// service itself (AppleSmartBattery / AppleARMPMUCharger, readable from Settings without entitlements):
//   Maximum Capacity = NominalChargeCapacity / DesignCapacity (the inputs of powerd's own figure, NCCP), AppleRawMaxCapacity when there is no
//   NominalChargeCapacity, rounded up as Apple's page rounds it (17.5.1 shows 9589 / 10762 = 89.1 % as 90 %), never above 100; Cycle Count =
//   CycleCount.
// Plain C: the Mac test (tools/test-batteryhealth.c) checks these answers.
#pragma once

// The percent, or -1 when the battery service gave nothing usable (no design capacity, no full-charge capacity, an absurd ratio).
static inline int MSBDBatteryHealthPercent(long nominalChargeCapacity, long rawMaxCapacity, long designCapacity) {
    long full = nominalChargeCapacity > 0 ? nominalChargeCapacity : rawMaxCapacity;
    if (designCapacity <= 0 || full <= 0) return -1;
    long p = (full * 100 + designCapacity - 1) / designCapacity;   // (rounded up, as Apple's page does)
    if (p < 1 || p > 150) return -1;   // (a gauge that is still learning, or a wrong design capacity: no figure rather than a wrong one)
    return p > 100 ? 100 : (int)p;
}
// What Apple's page is handed for the battery's service state. Apple's own answer when it has one (>= 0); on iPad it has none (-1, which the page
// shows as "unable to determine"): 0, the normal state, when we have a figure. (The page's other states are Apple's service and recalibration
// texts; we never make those up.)
static inline int MSBDBatteryHealthServiceState(int appleState, int percent) {
    return appleState >= 0 ? appleState : (percent >= 0 ? 0 : appleState);
}
// The performance-management state. Apple's page takes 0 for "no battery data" (+[BatteryUIResourceClass batteryDataUnavailable]: a spinner
// instead of the page, read on 18.5) and iPads answer 0 (the M1 4). 2 -- the normal managed state, what the page shows when all is well -- once
// we have a figure; the page's Peak Performance group itself is left out on iPad.
static inline int MSBDBatteryManagementState(int appleState, int percent) {
    return appleState != 0 ? appleState : (percent >= 0 ? 2 : 0);
}
// The battery check Apple's page waits for before it shows its header (0 = not known yet: the page shows a spinner instead; 1 = checked; 2 =
// unverified battery). On iPad the check never answers: 1 once we have a figure, so the page shows its text and the figure.
static inline int MSBDBatteryGenuineStatus(int appleStatus, int percent) {
    return appleStatus != 0 ? appleStatus : (percent >= 0 ? 1 : 0);
}
