// DefaultsRule.h -- which entries of the defaults versions an install writes (MacStatusBar&Dock, review of 1.8.6; Mac-tested:
// tools/test-defaultsrule.sh). Plain C. The root helper's FreezeOldDefaults (macsettings/sshtoggled/main.m, sshtoggled --freeze-defaults, in the
// postinst) asks these for each entry; its lists (OldDefaults, DefaultsForAll) name the version that brought each entry.
//
// done: the newest defaults version this device settled before (defaultsVersion in our settings: it survives a removal and a purge; 0 = never).
// decisionFresh: dpkg named no old version and no old packages' traces were found (FreezeReason). A reinstall after a removal looks like that too,
// but the device settled a version before: it is an update for the defaults (review of 1.8.6: a 1.8.5 user's remove-then-reinstall was taken
// for a first install, and Show Trash in Dock, off for every 1.8.5 user, came on). Only a device that never settled any version is new.
#pragma once

static inline int MSBDDefaultsFirstInstall(int decisionFresh, long done) { return decisionFresh && done == 0; }
// An old default (OldDefaults), written where nothing is stored: for an update, each entry newer than what the device settled.
static inline int MSBDDefaultsFreezes(long entryVersion, long done, int firstInstall) { return !firstInstall && entryVersion > done; }
// A value for every device (DefaultsForAll), written over what is stored, once: each install that has not settled that version, first or not.
static inline int MSBDDefaultsForAll(long entryVersion, long done) { return entryVersion > done; }
