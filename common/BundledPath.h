// BundledPath.h -- which processes the loader gives the app-side parts (loader/Loader.c; memory audit 1 Nov 2026, code review 2 Nov). Plain C:
// tools/test-bundledpath.sh.
// The Bundles filter com.apple.UIKit matches every process that has UIKit loaded, and many daemons link it without ever starting an app
// (runningboardd, mediaserverd, locationd, CommCenter, a DriverKit HID driver: 50 of 59 such processes on the M1). The app-side parts are for
// processes whose executable is inside a bundle: apps and SpringBoard (.app), app extensions (.appex: an app's PlugIns or Extensions, iOS's own,
// ExtensionKit's /System/Library/ExtensionKit/Extensions) and XPC services (.xpc: WebKit's GPU process plays Safari's web audio) -- wherever the
// bundle lives: /Applications, the app containers, /var/jb, a cryptex (Safari and WebKit come from one on 16+: /private/preboot/Cryptexes/App/...,
// /System/Cryptexes/...). Never a bare daemon (/usr/libexec, /usr/sbin, a framework's Support folder, a name like com.apple.appleseed...), a
// DriverKit driver (.dext) or anything without a path.
#pragma once
#include <string.h>

static inline int MSBDPathHas(const char *path, const char *part) { return path && part && strstr(path, part) != NULL; }
// The executable is inside an .app, .appex or .xpc bundle (the bundle's folder name and a slash: never a name that merely starts with ".app").
static inline int MSBDBundledProcess(const char *path) {
    return MSBDPathHas(path, ".app/") || MSBDPathHas(path, ".appex/") || MSBDPathHas(path, ".xpc/");
}
// An app extension (widgets, keyboards, share sheets, posters): no MixAudio there -- it would only pay for AVFoundation (audio audit F15c).
static inline int MSBDAppExtension(const char *path) { return MSBDPathHas(path, ".appex/"); }
