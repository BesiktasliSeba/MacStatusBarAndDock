# MacStatusBar&Dock

A macOS-style desktop for jailbroken iPads: a Mac menu bar with real app menus, Mac windows on the window engine you choose, Mission Control with desktops, a Finder and a magnifying Dock. It works with your fingers or with a trackpad or mouse, in every orientation.

| | |
|---|---|
| Device | iPad only. On an iPhone it does nothing, even on one made to look like an iPad. Builds with the iPad check removed are not made or supported by us. |
| iPadOS | 15 and 16. On 17 and later it stays off until you turn on Enable Anyway (experimental). |
| Jailbreak | Rootless. The test iPads use Dopamine and palera1n. |
| Needs | A hooking platform (ElleKit, libhooker or Substrate), Choicy or iCleaner Pro, and AltList. Sileo installs what's missing. |
| Window engine | Optional: Aerial, Zetsu, MilkyWay4 or Apple's Stage Manager. See [Window engines](#window-engines). |
| License | Free and open source (GPL-3.0-only). |

[Install](#install) · [Features](#features) · [Window engines](#window-engines) · [Compatibility](#compatibility) · [Troubleshooting](#troubleshooting) · [Privacy](#privacy) · [Report a bug](#report-a-bug) · [Settings reference](./docs/settings.md) · [Changelog](./CHANGELOG.md)

## Install

1. In Sileo or Zebra, add this repo. On the iPad you can also open the address in Safari and tap Add to Sileo.

   ```
   https://besiktasliseba.github.io/repo/
   ```

2. Install **MacStatusBar&Dock** and respring when Sileo asks.
3. For windows, add a window engine, or use Apple's Stage Manager on iPadOS 16. Settings > Status Bar > Window Engine lists them, with a GET button for each one you don't have yet.

After the respring:

- Apps still open full screen. Tap the green light in the menu bar to put an app in a window, or turn on **Window > Open Apps as Windows** to open every app in one. With the Stage Manager engine, apps open as windows from the start.
- The switches are in Settings > Status Bar and Settings > Dock, right below General. The [Settings reference](./docs/settings.md) explains each one.
- Desktops and Mission Control stay off until you turn on Settings > Status Bar > Mac Switcher.

Updates come through Sileo, and the Apple menu shows Update Available when your package list has a newer version. The checksum and source commit of every published package are in [RELEASES.md](https://github.com/BesiktasliSeba/repo/blob/main/RELEASES.md).

## Features

| On a Mac | In MacStatusBar&Dock |
|---|---|
| Menu bar with the Apple menu and app menus | The same, plus Wi-Fi, audio and VPN menus |
| Windows with traffic lights | Mac windows on Aerial, Zetsu, MilkyWay4 or Apple's Stage Manager |
| Mission Control and Spaces | The Mac Switcher, with up to 8 desktops that slide with your fingers |
| Finder and the desktop | A Finder window, and your files on the first Home Screen page |
| Dock | A magnifying Dock with Finder, Launchpad, recent apps and a Downloads stack |
| Search in System Settings | A search field at the top of the Settings sidebar |

The Mac look is on right after install, and most features have their own switch. Some extras start off, such as the Mac Switcher, the auto-hiding menu bar, seconds in the clock, tinted resize handles, the keyboard extras and the Lock Screen options. The [Settings reference](./docs/settings.md) shows how each switch starts.

### Menu bar

- The Apple menu has About This iPad, App Store, Force Quit, Respring, Safe Mode, Lock Screen, Sleep and Shut Down. The app in front gets App, Edit, Go and Window menus.
- Tap the clock to drop down your Today View widgets, with your notifications above them.
- The Wi-Fi icon opens a Wi-Fi menu, so you can join a network without Control Center. The Audio menu gives each app its own volume, and apps can play at the same time. While a VPN is connected, it gets its own menu with Disconnect.
- Right-to-left languages get a mirrored menu bar, as on a Mac. Status Bar Style switches back to the stock iPadOS bar.

### Windows

- Title bars, traffic lights, rounded corners and resize handles, on the engine you already use.
- The Window menu has layouts (halves, quarters, Fill Screen, Center) and Fit to Window, which tiles your windows side by side.
- Only the window you're using keeps a text cursor, and Esc ends typing.
- With the Stage Manager engine on iPadOS 16, windows float over your Home Screen and stay where you put them, and an external display gets its own Mac desktop.

### Mac Switcher (Mission Control and Spaces)

Off until you turn it on in Settings > Status Bar > Mac Switcher. It takes the place of the App Switcher.

- Open it with a swipe up and hold, a double press of the Home button, or Control-Up. Your desktops are at the top, and the windows of the current one below.
- Tap + to add a desktop (up to 8). Switch with a four-finger swipe, a swipe along the bottom edge, three fingers on a trackpad, or Control-Left and Control-Right.
- Drag a window onto another desktop to move it there. To remove a desktop, hold it and tap its remove button; its windows move to the desktop next to it.
- It works with every window engine, and your desktops are still there after a respring. Show App Switcher in the Apple menu opens the iPadOS App Switcher once.

### Finder and the desktop

- A Finder window with a sidebar, list and icon views, Quick Look, Search, Undo and Put Back. Open it from the Dock or the Go menu.
- Drag files between Finder windows, the desktop and the Downloads stack, or into an app, which gets a copy.
- Files and folders from On My iPad > Desktop sit on the first Home Screen page, never over your apps.
- Text files open in a small TextEdit window and save by themselves.
- USB drives and SD cards show up under Locations. exFAT and FAT32 work (FAT32 can't hold files over 4 GB). APFS and Mac OS Extended should work but haven't been tested, and iPadOS doesn't read NTFS. An SSD may need a powered hub.
- Finder only changes files in your own places: On My iPad, the apps' Documents folders, drives and its Trash. Everything else can be opened and copied, but not changed.

### Dock

- Magnification, dots under open apps, recent apps, and Finder and Launchpad at its start, like on a Mac.
- A Downloads stack with search, which you can drag files into and out of.
- Haptic Touch menus get Force Quit and App Size on app icons, and a folder's menu lists its apps.

### Settings

- The Status Bar and Dock pages sit right below General and look like Apple's own pages.
- A search field at the top of the Settings sidebar finds Apple's settings, like the search in System Settings on a Mac.

### Also included

- A Mac pointer, with an I-beam over text
- Mac-style notification banners and a mute icon
- A Go menu with the apps you choose, and an auto-hiding menu bar
- Home Screen options: page dots, app names and the Home Bar
- Keyboard extras for keyboards without a function row
- Longer Auto-Lock times, an SSH switch and Ethernet settings
- VoiceOver labels for the menu bar, the traffic lights and Finder, and Reduce Motion support

### Built to be safe

- If SpringBoard crashes twice in a row because of this tweak, Automatic Crash Recovery turns off what crashed, tells you in Settings and offers Report a Problem. A crash in another tweak doesn't count.
- On an iPadOS version it hasn't been tested on, it stays off until you choose Enable Anyway.
- Package managers, the jailbreak apps and Filza never get its app parts, so they keep working and you can always remove it.
- It has no network code. See [Privacy](#privacy).

## Window engines

The menu bar and the Dock work on their own. App windows come from a window engine, and MacStatusBar&Dock gives them the Mac look. Pick one in Settings > Status Bar > Window Engine. Only that one loads (MacStatusBar&Dock sets up Choicy or iCleaner Pro for you), and a switch takes a respring.

| Engine | iPadOS | Notes |
|---|---|---|
| Aerial 5.0 or 3.0, by uz.ra | 15, 16 | The default, marked Recommended. Aerial 5.0 has to be activated in its own settings before it opens windows. |
| Zetsu 1.6.6 or 1.6.2, by Dcsyhi | 15, 16 | A good alternative. Desktops were tested with 1.6.6. |
| MilkyWay4 0.1.1, by akusio | 15 | Adds the Resize Apps to Fit Windows switch. |
| Stage Manager, by Apple | 16 | Experimental. Needs Stage Manager on the iPad (TrollPad adds it to older iPads). Up to 7 windows per desktop. The only engine that gives an external display its own desktop. Tested on 16.7.7. |

Other versions of these engines run on their own, without the Mac look, and Settings marks them "untested version".

Which one? Start with Aerial 5.0, the one marked Recommended. If you already use Zetsu, keep it. On iPadOS 16, pick Stage Manager if you want Apple's own windowing or a desktop on an external display.

## Compatibility

| iPad | iPadOS | Jailbreak | Engines tested | Status |
|---|---|---|---|---|
| iPad Pro 11" (M1, 2021) | 15.6.1 | Dopamine | Aerial 5.0, Zetsu, MilkyWay4 | Tested by the developer |
| iPad Pro 9.7" | 16.7.7 | palera1n | Aerial 5.0, Zetsu, Stage Manager (with TrollPad) | Tested by the developer |
| iPad Pro 10.5" | 16.6.1 | rootless | not reported | Reported working by a user |
| iPad mini 4 | 15.8.8 | rootless | not reported | Reported running by a user. The Dock problem seen there (app icons past the ends of the Dock) is fixed in 1.4.2, awaiting confirmation |
| iPad Pro (M2, 2022) | 16.0 to 16.6 | Dopamine | Zetsu, Aerial | Reported by users with Zetsu or Aerial. Stage Manager engine: see below |
| iPad Pro 12.9" (M1, 2021) | 17.0 | rootless | Zetsu 1.6.6 | Reported working since 1.2.4, with Enable Anyway |
| Other iPads | 15, 16 | rootless | | Likely to work, not tested |
| Other iPads | 17 and later | | | Off until you turn on Enable Anyway, at your own risk |

- iPad Pro (M2) with the Stage Manager engine: offered on 16.1 and later, and as "Untested" on 16.0, where a user confirmed the basics (windows, resizing, traffic lights). On 16.3.1 a user confirmed it runs. On 16.1 to 16.6 another user reports SpringBoard crashes with it, so use Aerial 5.0 there.
- iPadOS 17: the desktop, the Wi-Fi menu, the Mac Switcher, the Stage Manager engine and the search field in the Settings sidebar are offered there, but haven't run on an iPadOS 17 device yet. Testers are welcome.
- iPadOS 18: the Mac Switcher, the desktop and the Wi-Fi menu are not offered.

Tried it on another setup? A [compatibility report](https://github.com/BesiktasliSeba/MacStatusBarAndDock/issues/new?template=compatibility.yml) (works or doesn't) helps fill in this table.

## Known limitations

- The tweak's own menus and Settings pages are in English only.
- Apple's Stage Manager stays off while another window engine runs, because two window systems would fight over the same apps. To use it, pick Stage Manager as the engine.
- With the Stage Manager engine, a desktop holds up to 7 windows.
- Some apps, like many games, only run full screen. The camera works only full screen (iPadOS pauses it in a window), and Photos opened from the Camera stays full screen.
- External displays: on iPadOS 15 the iPad is mirrored. On iPadOS 16 with engines other than Stage Manager, windows stay on the iPad; open apps from the display's App Library to use them there.
- Finder can't show iCloud Drive (iPadOS doesn't allow it), drag and drop goes from Finder into apps but not back yet, and drives have been tested on iPadOS 15 only.
- On iPadOS 15, Safari's sound can stop another app that plays alone, as on a stock iPad. Control Center's Now Playing shows one app at a time.
- While Destra is on, it shows the notification banners instead.

## Troubleshooting

| Problem | What to do |
|---|---|
| Apps open full screen | Turn on Window > Open Apps as Windows, or tap the green light. Aerial 5.0 has to be activated in its own settings first. If Window Engine says None, no tested engine is installed. |
| No desktops or Mission Control | Turn on Settings > Status Bar > Mac Switcher. It isn't offered on iPadOS 18. |
| Stage Manager is greyed out | The footer under Settings > Status Bar > Window Engine says why: no Stage Manager on this iPad (TrollPad adds it), an iPadOS version that isn't supported yet, or a respring needed to check. |
| A feature turned itself off | Automatic Crash Recovery turned it off after crashes. Settings > Status Bar says what and why. Tap Turn Back On to try again, or Report a Problem. |
| SpringBoard keeps crashing | Your jailbreak's Safe Mode starts by itself after quick crashes. Exit Safe Mode, and at the next start crash recovery turns off what crashed. The Apple menu also has Safe Mode. |
| Black screen after a respring, with Aerial 5.0 | Aerial 5.0 goes online while SpringBoard starts, and with a VPN on (or just turned off) it can hang. Restart the iPad and jailbreak again. Next time, don't respring while a VPN is on or was just turned off; MacStatusBar&Dock warns before resprings that go through iOS. |
| The Status Bar and Dock pages are gone | Both MacStatusBar and MacDock were turned off. Turn them back on in Choicy (or iCleaner Pro), then respring. |
| Several window engines installed | That's fine. Only the one picked in Window Engine loads. Leave the engines' entries in Choicy alone: MacStatusBar&Dock manages them. |

To uninstall, remove MacStatusBar&Dock in Sileo. It gives the window engines their own settings back and undoes its Choicy or iCleaner Pro changes. Finder's Trash isn't visible in the Files app and stays behind, so empty it in Finder first.

## Privacy

MacStatusBar&Dock has no network code. It doesn't contact any server, send analytics or crash reports, or update itself. Report a Problem opens a filled-in GitHub issue in your browser, and nothing is sent unless you submit it. About This iPad shows your serial number on screen only. Details, and how to check this in the source: [SECURITY.md](./SECURITY.md).

Window engines are separate tweaks with their own behaviour. For example, Aerial 5.0 goes online when SpringBoard starts.

## Report a bug

The easiest way is on the iPad: Settings > Status Bar > Report a Problem. It opens a new GitHub issue with your iPad model, iPadOS version, window engine and tweak version filled in, plus a short crash summary when crash recovery acted in the last 7 days. You see the whole text first and can change any of it.

You can also [open an issue](https://github.com/BesiktasliSeba/MacStatusBarAndDock/issues/new/choose) from a computer. The form asks for the same details, the steps, and a screenshot or screen recording if you have one.

Please report security problems privately, as described in [SECURITY.md](./SECURITY.md).

## Memory and older iPads

Measured on 1.1.9, before Finder, the desktop and the Mac Switcher were added: over a 30 minute check, SpringBoard used 63 to 69 MB on the 2 GB iPad Pro 9.7" with the Stage Manager engine, and about 100 MB on the M1 iPad Pro. Picture caches have size limits and are emptied when memory runs low, and the Mac Switcher lets go of its desktop pictures then too.

On iPads with 2 or 3 GB of memory:

- Work with 2 or 3 windows at a time. Every window is a running app, and iPadOS closes apps in the background when memory runs short, so they reload when you go back.
- Turn off what you don't use, such as Siri Suggestions (Settings > Siri & Search) and Handoff (Settings > General > AirPlay & Handoff).

## In the works

A real second desktop on external displays for iPadOS 15. An early version already runs its own menu bar, Dock and apps on a TV.

![An early iPadOS 15 second desktop on a TV: its own menu bar, a Clock window and a Dock](./images/ios15-tv-desktop-teaser.jpg)

## Contributing

Bug reports and pull requests are welcome. Please read [CONTRIBUTING.md](./CONTRIBUTING.md) before your first pull request: contributions are accepted under a short contributor agreement. How the parts fit together, and how to build and test: [docs/development.md](./docs/development.md).

## License

Copyright (C) 2026 besiktasliseba

SPDX-License-Identifier: GPL-3.0-only

MacStatusBar&Dock is free software under the GNU General Public License, version 3 only. See [LICENSE](./LICENSE) for the full text.

## Credits

MacStatusBar&Dock gives a Mac look to windows from these engines. Thanks to their developers:

- **Aerial** by uz.ra
- **MilkyWay4** by akusio
- **Zetsu** by Dcsyhi

And thanks to these tweaks for setting the bar:

- **Arrow, Finally.** by Andy Ching, for the Mac pointer
- **Lynx 2** by MTAC
- **Single Mute** by 82Flex, for the mute icon

This tweak does not include or modify any of their files.
