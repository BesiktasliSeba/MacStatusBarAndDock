// WelcomeRule.h -- the one-time welcome alert's two decisions (MacStatusBar&Dock, 1.6.0; Mac-tested: tools/test-welcomerule.sh). Plain C.
// The welcome ("Welcome to your new iPad") greets a FIRST install when it first runs on a tested iPadOS version. The root helper decides at
// install time whether there is one to show (sshtoggled --welcome-check, first in the postinst: the marker file welcome-pending, or welcomeShown);
// SpringBoard decides at its start whether to show it (statusbar/StatusBar.x DMCheckWelcome).
//
// Untested iPadOS versions never get the welcome ("Enable Anyway": at the user's own risk), and since 1.6.0 that refusal is final for the install.
// Before, SpringBoard refused without recording it and every update kept the marker, so the update that made a version tested showed the
// first-install welcome to people who had used the tweak there for weeks: every iPadOS 18 install, on 1.6.0~rc5 (A12Z, 28 Oct 2026; by the same
// code, the iPadOS 17 installs from before 1.5.0 when 1.5.0 made 17 tested). Now:
//  - SpringBoard, refusing on an untested version (the tweak runs there only with Enable Anyway on): done for this install (welcomeShown).
//  - The helper: a marker still pending is consumed when this install has run on an untested version, which our Enable Anyway key tells (on or
//    off: only an untested version writes it -- its switch or the crash guard -- and only the package's removal clears it). That is the state the
//    builds before 1.6.0 left behind; an install that never ran there (no key) keeps its welcome for its first real run.
#pragma once

typedef enum { kMSBDWelcomeKeep = 0, kMSBDWelcomeMarkPending, kMSBDWelcomeMarkShown } MSBDWelcomeInstall;
// The helper at install time. pending: the marker is there; enableAnywaySet: our Enable Anyway key exists (VersionGate.h MSBD_GATE_KEY);
// notFirst: something shows that our package or its settings were here before (an upgrade, the migration marker, the old packages, our settings).
static inline MSBDWelcomeInstall MSBDWelcomeAtInstall(int pending, int enableAnywaySet, int notFirst) {
    if (pending) return enableAnywaySet ? kMSBDWelcomeMarkShown : kMSBDWelcomeKeep;
    return notFirst ? kMSBDWelcomeMarkShown : kMSBDWelcomeMarkPending;
}

typedef enum { kMSBDWelcomeNone = 0, kMSBDWelcomeShow, kMSBDWelcomeDoneUnshown } MSBDWelcomeStart;
// SpringBoard at its start (our status bar runs): nothing to do, show it (once the Home Screen is free), or done without showing (welcomeShown is
// written: an untested version). pending: the marker; shown: welcomeShown; tested: MSBDVersionTested().
static inline MSBDWelcomeStart MSBDWelcomeAtStart(int pending, int shown, int tested) {
    if (!pending || shown) return kMSBDWelcomeNone;
    return tested ? kMSBDWelcomeShow : kMSBDWelcomeDoneUnshown;
}
