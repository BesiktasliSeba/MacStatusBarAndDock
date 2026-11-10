# Development

How MacStatusBar&Dock is put together, and how to build and test it. Before you open a pull request, please read [CONTRIBUTING.md](../CONTRIBUTING.md).

## How it's built

iOS injects only two small loaders, the two entries Choicy and iCleaner Pro show: `MacStatusBar.dylib` and the Dock's loader beside it. Each loader looks at the process it was loaded into and loads only the parts meant for that process, from the tweak's own folder (`/var/jb/usr/lib/MacStatusBarAndDock/`).

- On an iPhone nothing is loaded.
- On an iPadOS version that hasn't been tested, only the Settings pages are loaded, unless you choose Enable Anyway.
- A part that Automatic Crash Recovery turned off is skipped.
- Package managers, the jailbreak apps, TrollStore and Filza never get the app parts, so they keep working if an app part ever breaks.

```
MacStatusBar&Dock
│
├── SpringBoard (Home Screen, windows, Dock)
│   ├── MacStatusBarCore    menu bar and app menus, windows and the Window menu, the Stage Manager engine,
│   │                       Mac Switcher, Finder, the desktop, the TextEdit and Activity Monitor windows, Wi-Fi and battery menus, banners, Today panel, the Mac Control Center
│   ├── DockMagnification   Dock, magnification, recent apps, Launchpad, Downloads stack, Trash
│   ├── Home Screen parts   MacIconLabels, MacPageDots, MacFolderMenu, MacAppSizeMenu, ForceQuitMenu, MacAddToFolder
│   ├── MacRAMCPU, MacSSH   the RAM & CPU and SSH controls, modules Control Center loads from the tweak's folder
│   ├── MacConnectivity, MacDisplay, MacSound, MacNowPlaying   the Mac Control Center's tiles on iPadOS 18, modules too; MacStatusBarCore draws them
│   └── MacHomeBar, MacLockStatusBar, MacCCGrabber, MacSettingsBadge, VolumeGlobeTweak
│
├── Apps (apps, app extensions and XPC services that use UIKit, never bare daemons; MixAudio stays out of app extensions)
│   ├── MacAppBridge        window interaction: menus, typing and Esc, button color for resize handles, small per-app fixes
│   ├── MixAudio            per-app volume and audio mixing
│   ├── GraveEscapeTweak, BrightnessKeyTweak, TabMuteTweak   keyboard keys
│   └── MacLargeTitles
│
├── Settings app
│   └── MacSettings, MacEthernetFix, the Status Bar, Desktop, Windows & Multitasking and Dock pages, and the Battery Health page with its Battery Use group
│
├── pointeruid (the pointer)
│   └── MacPointer          the Mac pointer
│
├── Automatic Crash Recovery (in the loaders)
│   ├── MacCrashBlame       reads a SpringBoard crash report to see whether this tweak caused it
│   └── MacCrashNotice      the one-time alert after it acted
│
├── Eject helper (msbdeject, a small program the root helper starts)
│   └── ejects a USB drive or SD card for Finder's Eject and the Dock's Trash, which SpringBoard isn't allowed to do
│
└── Root helper (sshtoggled, a small launch daemon)
    ├── SSH on and off from Settings and Control Center, with each switch's result in its state file for every switch to show
    ├── which window engine, Control Center and banner tweak loads (Choicy's list, or iCleaner Pro's renaming without Choicy)
    ├── a drive's eject for Finder: it checks that the folder is a connected drive's, then runs the eject helper
    ├── Sleep Guard: with the screen off, has launchd start powerd over when a power assertion of a process that's gone is the only one keeping the iPad awake
    ├── Keep Tailspin Off: keeps PDSEPrefAllowEnableTailspin false in com.apple.da, so perfdiagsselfenabled doesn't turn tailspin on, and takes that value away when switched off or removed
    └── gives the engines' settings back when the tweak is removed or switched off, and has SpringBoard lower a stored Auto-Lock of 2 hours then
```

Every part can be traced to its process in `loader/Loader.c` (the `kPayloads` table), except the Control Center modules above, which Control Center loads itself, and the eject helper, a program of its own.

## Where things are

| Folder | What's in it |
|---|---|
| `loader/` | The two loaders and crash recovery's helpers |
| `statusbar/` | MacStatusBarCore, the Status Bar and Windows & Multitasking pages, and MacPointer |
| `dock/` | The Dock and its page |
| `ccmodule/` | The RAM & CPU, SSH and Mac tile Control Center modules |
| `ejecthelper/` | The eject helper (`msbdeject`), which the root helper runs for Finder's Eject and the Dock's Trash |
| `macsettings/` | The Settings app changes, the smaller Home Screen parts and the root helper (`sshtoggled/`) |
| `appbridge/` | MacAppBridge, which runs inside apps |
| `mixaudio/`, `forcequitmenu/`, `graveescape/`, `tabmute/`, `volumeglobe/`, `brightnesskey/` | The smaller parts |
| `common/` | Shared code: the version and device gates, crash recovery, the Choicy and iCleaner Pro handling, diagnostics |
| `layout/DEBIAN/` | The install and removal scripts |
| `tools/` | Mac tests and build helpers |

## Window API for other tweaks (V1)

Other tweaks in SpringBoard can lay out the front window and go Home through three C functions exported by MacStatusBarCore.dylib (`/var/jb/usr/lib/MacStatusBarAndDock/MacStatusBarCore.dylib`; find them with `dlopen(path, RTLD_LAZY | RTLD_NOLOAD)` and `dlsym`). Call them on SpringBoard's main thread. V1 is stable: its names, arguments and return codes will not change, and a V2 would come next to it.

- `int MSBDKeyPilotLayoutV1(const char *layout)`: `left`, `right`, `top`, `bottom`, `topleft`, `topright`, `bottomleft`, `bottomright`, `fill`, `center`, `small` or `large`, the Window menu's layouts for the front window, with every window engine. With Finder or TextEdit in front, that window takes the layout, also with no window engine. Returns 0 dispatched, 1 not on the main thread, 2 unknown layout, 3 no window engine, 4 no active app, 5 the app only runs full screen, 6 locked or busy (the Lock Screen or Notification Center, a transition, a switcher, Control Center, Guided Access, one of the tweak's menus, or windows the tweak is about to place). The checks run in the order 1, 2, 6, 3, 4, 5. 0 does not mean the window has moved yet.
- `int MSBDKeyPilotHomeV1(void)`: Home, with every window minimized, with every window engine. Returns 0 dispatched, 1 not on the main thread, 6 locked or in Guided Access. A second call within a second is the same Home, and at the Home Screen it only minimizes the windows.
- `int MSBDKeyPilotHomeEnvironmentV1(void)`: 1 Home Screen, 2 App Switcher, 3 an app; -1 not on the main thread or unknown, -2 locked.

The API was designed by wanghuangjie for [KeyPilot](https://github.com/wanghuangjie/KeyPilot), and its names, arguments and return codes are his: see [WINDOW_MANAGEMENT.md](https://github.com/wanghuangjie/KeyPilot/blob/main/integrations/WINDOW_MANAGEMENT.md). The code is in `statusbar/WindowAPI.h` and `statusbar/WindowAPIRule.h`, and `tools/test-windowapi.sh` tests its rules.

## Building

You need macOS with [Theos](https://theos.dev), the iPhoneOS 16.5 SDK, GNU Make 4.x and Python 3. Build from a git checkout, so the package can record the commit it was built from (`BuildInfo.txt`).

```
THEOS=~/theos gmake -j4 package                   # debug build
THEOS=~/theos gmake -j4 package FINALPACKAGE=1    # release build
```

- Use `gmake`. macOS's built-in make 3.81 hangs in Theos's bundle step with `-jN`.
- Builds target `arm64 arm64e`, rootless packaging, with a minimum iOS version of 15.0.
- The parts share one Theos object folder, so every source file needs a unique name.
- The eject helper is signed with macOS's own `codesign`, which writes its entitlements in the form iPadOS 15 and later require (`ejecthelper/Makefile`).
- The package step also builds `CrashMap.txt` from the debug symbols (`tools/make-crashmap.py`, rules in `tools/crashmap-rules.txt`). It tells crash recovery which switch turns off the code that crashed.
- The package step also checks that the prewarm part carries the build ID its sources and build kind make (`tools/prewarm-part-id.sh`, `common/PrewarmPartID.h`). An install leaves dasd running only when the block it has already loaded carries that ID, and restarts it otherwise.
- Each start of the prewarm part in dasd writes down whether it armed (`common/PrewarmArmed.h`). Settings, its search and Spotlight's Tweak Settings offer Prewarm Apps only where it did.

## Testing

- `tools/test-*.sh` are Mac tests of the logic that doesn't need an iPad: crash recovery, the install and removal scripts, the Stage Manager engine's maths and checks, the Mac Switcher's slide, desktop icon placement, window snapping, the menu bar's sizes, the eject requests, the update check and more. Each one builds what it needs with clang and prints its result, for example `bash tools/test-smfit.sh`.
- After you add or remove a hook, run `python3 tools/make-hooklist.py`. It regenerates `common/HookList.h`, which the diagnostics on iPadOS 17 and later use.
- Everything else needs a real iPad. Please say in your pull request what you tested, on which iPad, iPadOS version and window engine.

## Releases

`tools/verify-release.sh <deb>` checks that a package is a release build of the current commit, complete and free of test tools. Every published package is listed in the Sileo repo's [RELEASES.md](https://github.com/BesiktasliSeba/repo/blob/main/RELEASES.md) with its SHA-256 and the source commit it was built from. A rebuild gives the same code but not a byte-identical package, so compare the source, not the file.
