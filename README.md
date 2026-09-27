# MacStatusBar&Dock

A macOS-style desktop for jailbroken iPads: a menu bar with real app menus, Mac-looking windows, a magnifying Dock, Mac-style notification banners, a Mac pointer and a lot of small Mac touches. Built for **rootless jailbreaks on iPadOS 15 and 16**. It works with just your fingers or with a keyboard and trackpad or mouse, in portrait and landscape — every orientation.

**What's new:** see the [changelog](./CHANGELOG.md).

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
  - External displays on iPadOS 16 (used as a separate screen through Stage Manager or TrollPad): to use windowed apps on the external display, open them from the App Library on that display. Apps opened from its Dock or from Spotlight open on the iPad, and windows can't be moved between displays yet. For apps anywhere on the external display, turn off Enable Windowing and use Stage Manager. On iPadOS 15 the external display mirrors the iPad, windows included.
  - On iPadOS 15, Safari's sound can stop another app that's playing alone — it plays on its own, as on a stock iPad.
  - Control Center's Now Playing controls only ever show one app at a time — usually whichever started playing most recently — even while several apps are playing together with Mix Audio.
  - Stage Manager (iPadOS 16) stays off while windowing runs with a window engine, because two window systems would fight over the same apps. To use Stage Manager, turn off Enable Windowing in Settings > Status Bar; it comes back on by itself.
  - Some apps, like many games, can't run in a window. Open those full screen.
  - The camera only works full screen: iPadOS pauses it for apps in a window. The Camera app always opens full screen; for other apps, switch to full screen while you use the camera.
  - Photos opened from inside the Camera opens full screen. Keep it full screen: turning it into a window then closes Photos (Photos can't change its layout while showing a single photo).
  - Aerial 5.0 has to be activated in its own settings before it can open windows. Until then, apps open full screen, and a note leads you to Aerial's settings.
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
- **VPN icon** — a VPN icon shows while a VPN is connected; its menu tells you which app it runs through, opens that app, or goes to VPN & Device Management.
- **Mac pointer** — a macOS arrow cursor and I-beam with a trackpad or mouse, with a choice of style and size.
- **Haptic Touch menus** — long-press a Home Screen app icon for Force Quit and App Size, or a folder icon to jump straight to one of its apps.
- **Mac windows** on the window engine you already use (Aerial 3.0 or 5.0, MilkyWay4 on iPadOS 15 only, or Zetsu 1.6.2 or 1.6.6): a title bar, traffic lights and rounded corners, with Fit to Window tiling (a third window asks which side it goes on, or No Fit to leave it untiled) and resize handles tinted in each app's color.
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
- **Built-in safety** — off by default on untested iPadOS versions (unless you choose Enable Anyway), does nothing at all on an iPhone, and if a feature you just turned on is followed by two SpringBoard crashes in a row, only that feature is switched back off automatically, with a note in Settings and a Report a Problem button.

## Which window engine?

Measured on both test iPads: Aerial 5.0 is the recommended window engine on newer and older iPads alike — every window test passed, memory use was the same as the others, and on the older iPad Pro 9.7" it opened windows about twice as fast as Zetsu from a cold start. Zetsu works well too and is a good alternative. MilkyWay4 runs on iPadOS 15 only.

## Report a Problem

The Report a Problem button (Settings > Status Bar, and the crash protection's note) opens a new GitHub issue in your browser, filled in with your iPad model, iPadOS version, window engine and its version, and the tweak's version. If the crash protection switched something off in the last 7 days, it adds what it turned off and when, and a few lines naming the tweak's own code that crashed (nothing from other apps or tweaks); on an untested iPadOS version, which of the tweak's switches are on. Nothing is sent by itself: you see the whole text first, can change or delete any of it, and it's only posted if you submit the issue (a GitHub account is needed). Nothing personal is included, and the tweak collects nothing in the background.

## Requirements

- A hooking platform: ElleKit, libhooker, or Substrate
- **Choicy** or **iCleaner Pro** (keeps only one window engine loaded at a time)
- Optional window engine: Aerial 3.0 or 5.0, MilkyWay4 0.1.1 (iPadOS 15 only), or Zetsu 1.6.2 or 1.6.6. Other builds run as plain, unmodified windows.

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
