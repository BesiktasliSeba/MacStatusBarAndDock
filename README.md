# MacStatusBar&Dock

A macOS-style desktop for jailbroken iPads: a menu bar with real app menus, Mac-looking windows, a magnifying Dock, Mac-style notification banners, a Mac pointer and a lot of small Mac touches. Built for **rootless jailbreaks on iPadOS 15 and 16**. It works with just your fingers or with a keyboard and trackpad or mouse, in portrait and landscape — every orientation.

**What's new:** see the [changelog](./CHANGELOG.md). **Checksums and source commits** of every published package: [releases](https://github.com/BesiktasliSeba/repo/blob/main/RELEASES.md).

## Install

Add this repo in Sileo (or Zebra):

```
https://besiktasliseba.github.io/repo/
```

Then install **MacStatusBar&Dock** from the repo. The Mac look is on right after install; most features have their own switch in Settings > Status Bar and Settings > Dock.

## Compatibility

- **iPad only.** MacStatusBar&Dock checks your device and does nothing on an iPhone, even one made to look like an iPad by another tweak.
- Tested: iPad Pro 11" M1, iPadOS 15.6.1 (Dopamine); iPad Pro 9.7", iPadOS 16.7.7.
- Other iPads on iPadOS 15.x / 16.x will likely work but haven't been tested.
- Rootless jailbreaks only.
- **Known limitations:**
  - External displays on iPadOS 16: with the Stage Manager window engine the display gets its own Mac desktop (menu bar, Dock, windows, full screen, Window > Move to Other Display). Not yet: opening an app from the display's Dock brings that app's whole group of windows along (Stage Manager's own rule); after a respring, windows on the display come back only when opened again; a moved window keeps its size relative to the screen it came from; the Window menu doesn't check-mark the layout of windows on the display; up to 4 windows per desktop. With the other engines, windows stay on the iPad: open apps from the display's App Library to use them there.
  - On iPadOS 15 the external display mirrors the iPad for now. A real second desktop for iPadOS 15 is in the works, and an early version already runs its own menu bar, Dock and apps on a TV.

    ![An early iPadOS 15 second desktop on a TV: its own menu bar, a Clock window and a Dock](./images/ios15-tv-desktop-teaser.jpg)

  - On iPadOS 15, Safari's sound can stop another app that's playing alone — it plays on its own, as on a stock iPad.
  - Control Center's Now Playing controls only ever show one app at a time — usually whichever started playing most recently — even while several apps are playing together with Mix Audio.
  - Apple's Stage Manager (iPadOS 16) stays off while windowing runs with another window engine, because two window systems would fight over the same apps. To use it, pick Stage Manager as the window engine in Settings > Status Bar > Window Engine.
  - With the Stage Manager engine, going to the Home Screen hides the windows (Stage Manager's own behaviour), and a desktop holds up to 4 windows.
  - Some apps, like many games, can't run in a window. Open those full screen.
  - The camera only works full screen: iPadOS pauses it for apps in a window. The Camera app always opens full screen; for other apps, switch to full screen while you use the camera.
  - Photos opened from inside the Camera opens full screen. Keep it full screen: turning it into a window then closes Photos (Photos can't change its layout while showing a single photo).
  - Aerial 5.0 has to be activated in its own settings before it can open windows. Until then, apps open full screen, and a note leads you to Aerial's settings.
  - With Aerial 5.0, don't respring while a VPN is on or was just turned off: Aerial goes online as SpringBoard starts and can hang on a black screen until you restart the iPad. MacStatusBar&Dock warns before a respring that goes through iOS (the Apple menu, Settings, Control Center toggles, package managers), not before one that ends SpringBoard directly.
  - While Destra is switched on, it shows the notification banners instead of MacStatusBar&Dock (both at once squeeze every banner).
- **iPadOS 17 and other versions (experimental):** the tweak installs but keeps itself off until you turn on Enable Anyway in Settings. It hasn't been tested there, so use it at your own risk. The crash protection still works, and Report a Problem in Settings fills in a short summary for you — reports from iPadOS 17 users are very welcome.
- **Both parts switched off?** If you turn off both MacStatusBar and MacDock in Settings, their Settings pages go away too. Turn them back on in Choicy (or iCleaner Pro), then respring.

## Features

The Mac look is on right after install. A few extras start off: the auto-hiding menu bar, seconds in the clock, the keyboard extras, the experimental keyboard button and the Lock Screen options.

- **Status Bar Style: Mac or Stock** — Mac gives you the full menu bar, app menus, audio mixing and Mac-style windows; Stock keeps the standard iPadOS status bar while your window engine keeps running with its own settings.
- **Menu bar with app menus** — an Apple menu (About This iPad, App Store, Force Quit, Respring, Safe Mode, Lock Screen, Sleep, Shut Down) and menus for the front app (App, Edit, Go, Window), in every orientation.
- **Go Menu** — choose and reorder the apps in the Go menu, the same way you'd customize Control Center. New installs start with Calendar, Terminal, Maps and Reynard.
- **Today drop-down** — tap the clock to drop your Today View widgets down like a menu, with your notifications in their own box above them (newest first; tap to open, swipe to clear).
- **Control Center** opens from the status bar (with BigSurCenter installed, its panel size can be set in Settings).
- **Mac-style notification banners** in the top-right corner.
- **Mute icon** — a small status bar icon shows while the iPad is on silent (its own switch in Settings).
- **VPN menu** — while a VPN is connected, iOS's own VPN badge shows as its own item next to the status icons, like on a Mac. Its menu shows the VPN's name and has Disconnect (auto-connect goes off too), a button that opens the VPN's app and VPN & Device Management. With Aerial 5.0, respring buttons warn first while a VPN is on, because Aerial goes online as SpringBoard starts and can hang on a black screen.
- **Mac pointer** — a macOS arrow cursor and I-beam with a trackpad or mouse, with a choice of style and size. Optionally it takes the Color, Border Width and Increase Contrast from Accessibility > Pointer Control (Use Pointer Control Style, off by default).
- **Haptic Touch menus** — long-press a Home Screen app icon for Force Quit and App Size, or a folder icon to jump straight to one of its apps. Menus look like a Mac's (slimmer rows that adapt to a trackpad or mouse); choose Mac or Stock in Settings > Status Bar > App Menus.
- **Stage Manager window engine (iPadOS 16)** — iPadOS's own Stage Manager runs your windows with a Mac look: title bars with traffic lights, native full screen that other windows can come over, the Window menu (layouts, Fit to Window, Swap, Move to Other Display) and a choice of resize handles. On iPads with Stage Manager, or older iPads with TrollPad; with an external display it gets its own Mac desktop.
- **Mac windows** on the window engine you already use (Aerial 3.0 or 5.0, MilkyWay4 on iPadOS 15 only, or Zetsu 1.6.2 or 1.6.6): a title bar, traffic lights and rounded corners, with Fit to Window tiling (a third window asks which side it goes on, or No Fit to leave it untiled) and resize handles that can be tinted in each app's color (Tint Resize Handles, off by default).
- **Dock** with macOS-style magnification, recent apps (plus a suggested or Handoff app), running-app indicators, a Launchpad icon, and a Downloads stack (choose which apps' downloads appear from a link in Settings).
- **Audio mixing per app**, with a volume for each app, set from the menu bar.
- **Auto-hiding menu bar** (optional, off by default).
- **Home Screen switches** — hide the page dots or the icon labels, added right on Apple's own Home Screen settings page, and the Home Bar (the line at the bottom edge) is hidden, with its own switch.
- **Lock Screen options** — hide the status bar on the Lock Screen, or skip it after a respring (no passcode set only).
- **Settings integration** — stock-looking pages right below General (Status Bar, Dock, Control Center), plus three longer Auto-Lock times (30 min/1 h/2 h), an SSH switch and an always-visible Ethernet section.
- **Keyboard extras** (off until you turn them on) — Cmd-Tab picks the right window, Escape closes menus, Tab to mute, Globe volume keys, brightness/keyboard-backlight keys.
- **Typing in windows like a Mac** — only the window you're using keeps a text cursor, and Esc ends typing in a windowed app (its own switch).
- **A one-time welcome message** after your first install, pointing you to Settings (never shown again, and never shown on an update).
- **Reduce Motion support** — menus, windows and banners cross-fade instead of zooming or springing when you use Reduce Motion.
- **Automatic Crash Recovery** — if turning on a feature is followed by two SpringBoard crashes in a row, MacStatusBar&Dock switches that feature back off by itself instead of leaving your iPad in a crash loop, and tells you in Settings, with a Report a Problem button. It also tells a stuck SpringBoard (restarted by the system) from a crash, and only counts problems in its own code: another tweak's crash or hang never switches MacStatusBar&Dock off.
- **Built-in safety** — off by default on untested iPadOS versions (unless you choose Enable Anyway), does nothing at all on an iPhone, and never contacts any server (see [SECURITY.md](./SECURITY.md)).

## Which window engine?

Measured on both test iPads: **Aerial 5.0 is the recommended window engine** on newer and older iPads alike — every window test passed, memory use was the same as the others, and on the older iPad Pro 9.7" it opened windows about twice as fast as Zetsu from a cold start. Zetsu works well too and is a good alternative. MilkyWay4 runs on iPadOS 15 only.

**Stage Manager (iPadOS 16)** is an option on iPads that have it (or older iPads with TrollPad): Apple's own windowing with our Mac look, and the only engine whose windows move to an external display. It has been tested on iPadOS 16.7.7; on earlier iPadOS 16 versions it may not work yet.

## Report a Problem

The Report a Problem button (Settings > Status Bar, and the Automatic Crash Recovery note) opens a new GitHub issue in your browser, filled in with your iPad model, iPadOS version, window engine and its version, and the tweak's version. If the crash protection switched something off in the last 7 days, it adds what it turned off and when, and a few lines naming the tweak's own code that crashed (nothing from other apps or tweaks); on an untested iPadOS version, which of the tweak's switches are on. Nothing is sent by itself: you see the whole text first, can change or delete any of it, and it's only posted if you submit the issue (a GitHub account is needed). Nothing personal is included, and the tweak collects nothing in the background.

## Requirements

- A hooking platform: ElleKit, libhooker, or Substrate
- **Choicy** or **iCleaner Pro** (keeps only one window engine loaded at a time)
- Optional window engine: Aerial 3.0 or 5.0, MilkyWay4 0.1.1 (iPadOS 15 only), or Zetsu 1.6.2 or 1.6.6. Other builds run as plain, unmodified windows.

## SSH switch

If OpenSSH is installed, MacStatusBar&Dock adds an **SSH** switch to Settings (between Bluetooth and VPN), so you can keep the SSH service off and turn it on only when you need it, instead of leaving it running all the time. The switch is not shown when OpenSSH isn't installed.

- **Your choice sticks:** when you switch SSH off, it stays off across restarts until you switch it on again. The tweak doesn't change SSH on its own, so after installing, OpenSSH is on or off exactly as it was before.
- **Why there's a helper:** starting and stopping OpenSSH needs root rights that the Settings app doesn't have, so a small helper daemon (`com.besiktasliseba.sshtoggled`) does it. The helper stays running as a small local root daemon, waiting for signals from Settings, because the Settings app can't do these privileged steps itself (starting and stopping OpenSSH, and switching window engines). **The helper is not an SSH server and accepts no network connections.** It only reacts to a local signal from Settings, and reads what to do from a Settings preference that apps can't write, so a faked signal can at most repeat your own choice. Its code: `macsettings/sshtoggled/main.m`.

Without the switch, OpenSSH typically runs all the time and SSH is reachable whenever your iPad is on a network. With it, you can keep it off and switch it on only for the moment you need it.

## How it's built

iOS injects only **two small loaders**, the two entries Choicy and iCleaner Pro show: `MacStatusBar.dylib` and `MacDock.dylib`. Each loader looks at the process it was loaded into and loads only the parts meant for that process, from the tweak's own folder (`/var/jb/usr/lib/MacStatusBarAndDock/`). On an iPhone nothing is loaded; on an iPadOS version that hasn't been tested, only the Settings pages are loaded (unless you choose Enable Anyway).

```
MacStatusBar&Dock
│
├── SpringBoard (Home Screen, windows, Dock)
│   ├── MacStatusBarCore    menu bar, app menus, windows (Fit to Window, traffic lights), banners, Today panel
│   ├── DockMagnification   Dock magnification, recent apps, Launchpad, Downloads
│   ├── Home Screen parts   MacIconLabels, MacPageDots, MacFolderMenu, MacAppSizeMenu, ForceQuitMenu
│   ├── MacLockStatusBar, MacCCGrabber, MacSettingsBadge, VolumeGlobeTweak
│   └── Automatic Crash Recovery   switches a feature back off if it's followed by SpringBoard crashes
│
├── Apps (every app that uses UIKit, not app extensions for audio)
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
└── Root helper (sshtoggled, a small launch daemon)
    ├── SSH on/off from Settings
    ├── window-engine exclusivity (Choicy's list, or iCleaner Pro's renaming without Choicy)
    └── gives engine settings back when the tweak is removed or switched off
```

Every part can be traced to its process in `loader/Loader.c` (the `kPayloads` table).

## Building with Theos

Build on macOS with [Theos](https://theos.dev) and the iPhoneOS 16.5 SDK:

```
THEOS=~/theos gmake -j4 package                   # debug build
THEOS=~/theos gmake -j4 package FINALPACKAGE=1     # release build
```

Use GNU Make 4.x (`gmake`); macOS's built-in make 3.81 hangs in Theos's bundle step with `-jN`. Builds target `arm64 arm64e`, rootless packaging, with a minimum iOS version of 15.0.

## Contributing

Bug reports and pull requests are welcome. Before your first pull request can be merged, please read [`CONTRIBUTING.md`](./CONTRIBUTING.md) — contributions are only accepted under a short contributor agreement.

## License

GPL-3.0-only. See [`LICENSE`](./LICENSE) for the full text.

## Credits

### Window engines

MacStatusBar&Dock gives a Mac look to windows from these engines. Thanks to their developers:

- **Aerial** by uz.ra
- **MilkyWay4** by akusio
- **Zetsu** by Dcsyhi

### Inspiration

Thanks to these tweaks for setting the bar:

- **Arrow, Finally.** by Andy Ching, for the Mac pointer
- **Lynx 2** by MTAC
- **Single Mute** by 82Flex, for the mute icon

This tweak does not include or modify any of their files.
