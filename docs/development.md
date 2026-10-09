# Development

How MacStatusBar&Dock is put together, and how to build and test it. Before you open a pull request, please read [CONTRIBUTING.md](../CONTRIBUTING.md).

## How it's built

iOS injects only two small loaders, the two entries Choicy and iCleaner Pro show: `MacStatusBar.dylib` and `MacDock.dylib`. Each loader looks at the process it was loaded into and loads only the parts meant for that process, from the tweak's own folder (`/var/jb/usr/lib/MacStatusBarAndDock/`).

- On an iPhone nothing is loaded.
- On an iPadOS version that hasn't been tested, only the Settings pages are loaded, unless you choose Enable Anyway.
- A part that Automatic Crash Recovery turned off is skipped.
- Package managers, the jailbreak apps, TrollStore and Filza never get the app parts, so they keep working if an app part ever breaks.

```
MacStatusBar&Dock
│
├── SpringBoard (Home Screen, windows, Dock)
│   ├── MacStatusBarCore    menu bar and app menus, windows and the Window menu, the Stage Manager engine,
│   │                       Mac Switcher, Finder, the desktop, the TextEdit window, Wi-Fi menu, banners, Today panel
│   ├── DockMagnification   Dock, magnification, recent apps, Launchpad, Downloads stack
│   ├── Home Screen parts   MacIconLabels, MacPageDots, MacFolderMenu, MacAppSizeMenu, ForceQuitMenu
│   └── MacLockStatusBar, MacCCGrabber, MacSettingsBadge, VolumeGlobeTweak
│
├── Apps (every app that uses UIKit; MixAudio stays out of app extensions)
│   ├── MacAppBridge        window interaction: menus, typing and Esc, button color for resize handles, small per-app fixes
│   ├── MixAudio            per-app volume and audio mixing
│   ├── GraveEscapeTweak, BrightnessKeyTweak, TabMuteTweak   keyboard keys
│   └── MacHomeBar, MacLargeTitles
│
├── Settings app
│   └── MacSettings, MacEthernetFix, the Status Bar and Dock pages
│
├── pointeruid (the pointer)
│   └── MacPointer          the Mac pointer
│
├── Automatic Crash Recovery (in the loaders)
│   ├── MacCrashBlame       reads a SpringBoard crash report to see whether this tweak caused it
│   └── MacCrashNotice      the one-time alert after it acted
│
└── Root helper (sshtoggled, a small launch daemon)
    ├── SSH on and off from Settings
    ├── window-engine exclusivity (Choicy's list, or iCleaner Pro's renaming without Choicy)
    └── gives the engines' settings back when the tweak is removed or switched off
```

Every part can be traced to its process in `loader/Loader.c` (the `kPayloads` table).

## Where things are

| Folder | What's in it |
|---|---|
| `loader/` | The two loaders and crash recovery's helpers |
| `statusbar/` | MacStatusBarCore, the Status Bar page and MacPointer |
| `dock/` | The Dock and its page |
| `macsettings/` | The Settings app changes, the smaller Home Screen parts and the root helper (`sshtoggled/`) |
| `appbridge/` | MacAppBridge, which runs inside apps |
| `mixaudio/`, `forcequitmenu/`, `graveescape/`, `tabmute/`, `volumeglobe/`, `brightnesskey/` | The smaller parts |
| `common/` | Shared code: the version and device gates, crash recovery, the Choicy and iCleaner Pro handling, diagnostics |
| `layout/DEBIAN/` | The install and removal scripts |
| `tools/` | Mac tests and build helpers |

## Building

You need macOS with [Theos](https://theos.dev), the iPhoneOS 16.5 SDK, GNU Make 4.x and Python 3. Build from a git checkout, so the package can record the commit it was built from (`BuildInfo.txt`).

```
THEOS=~/theos gmake -j4 package                   # debug build
THEOS=~/theos gmake -j4 package FINALPACKAGE=1    # release build
```

- Use `gmake`. macOS's built-in make 3.81 hangs in Theos's bundle step with `-jN`.
- Builds target `arm64 arm64e`, rootless packaging, with a minimum iOS version of 15.0.
- The parts share one Theos object folder, so every source file needs a unique name.
- The package step also builds `CrashMap.txt` from the debug symbols (`tools/make-crashmap.py`, rules in `tools/crashmap-rules.txt`). It tells crash recovery which switch turns off the code that crashed.

## Testing

- `tools/test-*.sh` are Mac tests of the logic that doesn't need an iPad: crash recovery, the install and removal scripts, the Stage Manager engine's maths and checks, the Mac Switcher's slide, desktop icon placement, the update check and more. Each one builds what it needs with clang and prints its result, for example `bash tools/test-smfit.sh`.
- After you add or remove a hook, run `python3 tools/make-hooklist.py`. It regenerates `common/HookList.h`, which the diagnostics on untested iPadOS versions use.
- Everything else needs a real iPad. Please say in your pull request what you tested, on which iPad, iPadOS version and window engine.

## Releases

`tools/verify-release.sh <deb>` checks that a package is a release build of the current commit, complete and free of test tools. Every published package is listed in the Sileo repo's [RELEASES.md](https://github.com/BesiktasliSeba/repo/blob/main/RELEASES.md) with its SHA-256 and the source commit it was built from. A rebuild gives the same code but not a byte-identical package, so compare the source, not the file.
