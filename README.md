# MacStatusBar&Dock

A macOS-style desktop for jailbroken iPads: a menu bar with real app menus, Mac-looking windows, a magnifying Dock, Mac-style notification banners, a Mac pointer and a lot of small Mac touches. Built for **rootless jailbreaks on iPadOS 15 and 16**. It works with just your fingers or with a keyboard and trackpad or mouse, in every orientation.

**What's new:** see the [changelog](./CHANGELOG.md). **Checksums and source commits** of every published package: [releases](https://github.com/BesiktasliSeba/repo/blob/main/RELEASES.md).

## Install

Add this repo in Sileo (or Zebra):

```
https://besiktasliseba.github.io/repo/
```

Then install **MacStatusBar&Dock** from the repo. The Mac look is on right after install; most features have their own switch in Settings > Status Bar and Settings > Dock.

## Compatibility

**iPad only, rootless jailbreaks, iPadOS 15 and 16.** On an iPhone the tweak does nothing, even on one made to look like an iPad.

| iPad | iPadOS | Jailbreak | Tested window engines | Status |
|---|---|---|---|---|
| iPad Pro 11" (M1, 2021) | 15.6.1 | Dopamine | Aerial 5.0, Zetsu, MilkyWay4 | ✅ Tested by the developer |
| iPad Pro 9.7" | 16.7.7 | palera1n | Aerial 5.0, Zetsu, Stage Manager (with TrollPad) | ✅ Tested by the developer |
| iPad Pro 10.5" | 16.6.1 | rootless | — | ✅ Reported working by a user |
| iPad Pro (M2, 2022) | 16.0 – 16.6 | Dopamine | Zetsu or Aerial | ⚠️ On 16.0 the Stage Manager engine isn't offered (it needs 16.1). On 16.1 – 16.6 a user reports SpringBoard crashes with it. Use Aerial 5.0 there |
| Other iPads | 15.x, 16.x | rootless | — | Likely to work, not tested |
| iPad Pro 12.9" (M1, 2021) | 17.0 | rootless | Zetsu 1.6.6 | ✅ Reported working by a user since 1.2.4, with **Enable Anyway** |
| Other iPads | 17 and later | — | — | Off by default; **Enable Anyway** in Settings turns it on at your own risk. The Stage Manager engine has an iPadOS 17 version that hasn't been tested on a device yet: testers welcome |

Tried it on another setup? A short note in an issue (works / doesn't) helps fill in this table.

### Known limitations

**Window engines**
- Apple's Stage Manager stays off while another window engine runs (two window systems would fight over the same apps). To use it, pick Stage Manager in Settings > Status Bar > Window Engine. It's tested on iPadOS 16.7.7 only.
- With the Stage Manager engine, going to the Home Screen hides the windows (Stage Manager's own behaviour), and a desktop holds up to 4 windows.
- Aerial 5.0 has to be activated in its own settings before it can open windows; until then apps open full screen, and a note leads you there.
- With Aerial 5.0, don't respring while a VPN is on or was just turned off: Aerial goes online as SpringBoard starts and can hang on a black screen until you restart the iPad. MacStatusBar&Dock warns before resprings that go through iOS (the Apple menu, Settings, Control Center, package managers).

**Apps in windows**
- Some apps, like many games, can't run in a window. Open those full screen.
- The camera only works full screen (iPadOS pauses it in a window). Photos opened from the Camera also stays full screen.

**External displays**
- iPadOS 16 with the Stage Manager engine: the display gets its own Mac desktop (menu bar, Dock, windows, full screen, Window > Move to Other Display). Not yet: an app opened from the display's Dock brings its whole group of windows along; after a respring, windows on the display come back only when opened again; a moved window keeps its size relative to the screen it came from.
- iPadOS 16 with the other engines: windows stay on the iPad; open apps from the display's App Library to use them there.
- iPadOS 15 mirrors the iPad for now. A real second desktop for iPadOS 15 is in the works. An early version already runs its own menu bar, Dock and apps on a TV.

  ![An early iPadOS 15 second desktop on a TV: its own menu bar, a Clock window and a Dock](./images/ios15-tv-desktop-teaser.jpg)

**Audio and banners**
- On iPadOS 15, Safari's sound can stop another app that's playing alone (as on a stock iPad).
- Control Center's Now Playing shows one app at a time, even while several play together with Mix Audio.
- While Destra is on, it shows the notification banners instead of MacStatusBar&Dock.

**Finder**
- iCloud Drive doesn't show in Finder (iPadOS doesn't give Finder access to it); use the Files app for it.
- USB drives and SD cards were tested on iPadOS 15; on iPadOS 16 they haven't been tested with a real drive yet.
- Drag and drop goes from Finder to apps, not from apps into Finder yet.

## Features

The Mac look is on right after install. A few extras start off: the auto-hiding menu bar, seconds in the clock, the keyboard extras, the experimental keyboard button and the Lock Screen options.

### Menu bar
- **A real Mac menu bar**: an Apple menu (About This iPad, App Store, Force Quit, Respring, Safe Mode, Lock Screen, Sleep, Shut Down) and menus for the app in front (App, Edit, Go, Window), in every orientation. Status Bar Style switches between Mac and the stock iPadOS bar.
- **Today drop-down**: tap the clock to drop your Today View widgets down like a menu, with your notifications in their own box above them.
- **Audio mixing per app**, with a volume for each app, right from the menu bar.
- **VPN menu**: the VPN badge becomes its own menu bar item with the VPN's name, Disconnect and a button to its app.
- **Wi-Fi menu**: tap the Wi-Fi icon to turn Wi-Fi on or off, see nearby networks and join one, with the password asked right there. No trip to Control Center.

### Windows
- **Mac windows on the engine you already use** (Aerial 3.0 or 5.0, Zetsu 1.6.2 or 1.6.6, MilkyWay4 on iPadOS 15): title bars, traffic lights, rounded corners, resize handles, and Fit to Window tiling.
- **Stage Manager as a window engine** (iPadOS 16.1 and later, experimental): Apple's own windowing with the Mac look, native full screen that other windows can come over, and its own Mac desktop on an external display.
- **Typing like on a Mac**: only the window you're using keeps a text cursor, and Esc ends typing.

### Finder
- **A Mac Finder window** on every window engine: sidebar, list and icon views, Quick Look, Search, Undo and Put Back, several-item selection, USB drives and SD cards, and drag and drop into apps. It only changes files in your own places, so it can't be used to break the iPad by accident.
- **A desktop** on the first Home Screen page: files and folders from On My iPad > Desktop, placed anywhere and never over your apps. Folders use your Files icon. Select several with a box, drag them anywhere, and long press or right click for Mac actions.
- **Text files** open in a small TextEdit window where you can edit them; changes save by themselves.

### Dock
- **A macOS Dock**: magnification, recent apps, running-app dots, Finder and Launchpad at its start like on a Mac, and a Downloads stack with search that you can drag files into and out of.

### Built to be safe
- **Automatic Crash Recovery**: if a feature is followed by two SpringBoard crashes in a row, it switches itself off instead of leaving you in a crash loop, tells you in Settings, and offers Report a Problem. Another tweak's crash never switches MacStatusBar&Dock off.
- **Off by default on untested iPadOS versions** (unless you choose Enable Anyway), does nothing on an iPhone, and never contacts any server (see [SECURITY.md](./SECURITY.md)).

**Also included:** a Mac pointer (arrow and I-beam, with Pointer Control colors as an option), Mac-style notification banners, Mac-style Haptic Touch menus (Force Quit and App Size on app icons, folder shortcuts), a mute icon, Control Center from the menu bar, a customizable Go menu, an auto-hiding menu bar, Home Screen options (page dots, icon labels, Home Bar), Lock Screen options, keyboard extras (Cmd-Tab to the right window, Esc closes menus, Tab to mute, Globe volume and brightness keys), longer Auto-Lock times, an SSH switch, Ethernet settings, and Reduce Motion support. Every feature has its own switch in Settings, on stock-looking pages right below General.

## Drives in Finder

USB sticks, SSDs and SD card readers show up in Finder under Locations as soon as you connect them.

- **Formats:** exFAT and FAT32 work (tested with a FAT32 USB stick). APFS and Mac OS Extended drives use the same iPadOS support and should work too, but haven't been tested with a real drive yet. NTFS (common on Windows drives) isn't supported by iPadOS itself.
- **FAT32** can't hold files larger than 4 GB; Finder says so before copying. exFAT has no such limit.
- **Power:** SSDs often need more power than a USB stick. Connect them straight to the iPad's USB-C port, or use a powered hub.
- **Trash:** items moved to the Trash stay on the drive (in its own hidden Trash), and Put Back works.
- To disconnect, just unplug the drive when no copy is running.

## Which window engine?

Measured on both test iPads: **Aerial 5.0 is the recommended window engine** on newer and older iPads alike: every window test passed, memory use was the same as the others, and on the older iPad Pro 9.7" it opened windows about twice as fast as Zetsu from a cold start. Zetsu works well too and is a good alternative. MilkyWay4 runs on iPadOS 15 only.

**Stage Manager (iPadOS 16.1 and later)** is an option on iPads that have it (or older iPads with TrollPad): Apple's own windowing with our Mac look, and the only engine whose windows move to an external display. It has been tested on iPadOS 16.7.7; on earlier iPadOS 16 versions it may not work yet.

## Memory use

Measured with Apple's `footprint` tool on both test iPads:

- The tweak's own code uses about 1 MB of private memory inside SpringBoard, and under 1 MB inside each app (the small helpers behind features like per-app volume and the app menu).
- On the iPad Pro 9.7" (2 GB of RAM, iPadOS 16.7.7, Stage Manager engine), SpringBoard used 63 MB with the tweak running, and it stayed flat over a 30 minute check.
- On the iPad Pro 11" (M1, 16 GB, Aerial 5.0 and about 90 other tweaks), SpringBoard used about 100 MB, also flat.
- Picture caches, like the Downloads thumbnails, have a fixed size limit, and iOS empties them when memory runs low.

Most of the memory in use on an iPad belongs to Apple's own background services. On the 2 GB iPad, about 250 of them used 1.1 GB together.

### Tips for older iPads with 2 or 3 GB of RAM

- Use **Aerial 5.0** as the window engine (see above).
- Keep only one window engine loaded, with Choicy or iCleaner Pro.
- Work with 2 or 3 windows at a time. Every window is a running app, and when memory runs short iPadOS closes apps in the background, so they reload when you go back to them.
- Turn off what you don't use: Siri Suggestions (Settings > Siri & Search), Handoff (Settings > General > AirPlay & Handoff) and extra widgets. On the 2 GB test iPad the services behind these features used about 100 MB together.
- Restart the iPad now and then. It had been up for 62 days during these measurements and was busy moving memory in and out of storage.

## Report a Problem

The **Report a Problem** button (Settings > Status Bar) opens a new GitHub issue with your iPad model, iPadOS version, window engine and tweak version filled in, plus, if the crash protection switched something off recently, what and when, and a few lines naming the tweak's own code that crashed. You see the whole text first and can edit it; nothing is sent unless you submit the issue. Nothing personal is included, and the tweak never collects anything in the background.

## Requirements

- A hooking platform: ElleKit, libhooker, or Substrate
- **Choicy** or **iCleaner Pro** (keeps only one window engine loaded at a time)
- Optional window engine: Aerial 3.0 or 5.0, MilkyWay4 0.1.1 (iPadOS 15 only), or Zetsu 1.6.2 or 1.6.6. Other builds run as plain, unmodified windows.

## SSH switch

If OpenSSH is installed, Settings gets an **SSH** switch (between Bluetooth and VPN), so SSH can stay off and be turned on only when you need it. Your choice sticks across restarts; installing the tweak doesn't change whether SSH is on.

Starting and stopping OpenSSH needs root, so a small local helper daemon (`com.besiktasliseba.sshtoggled`) does it (it also keeps only one window engine loaded). **It is not an SSH server and accepts no network connections**: it only reacts to a local signal from Settings and reads what to do from a preference apps can't write. Its code: `macsettings/sshtoggled/main.m`.

## Troubleshooting

- **Both parts switched off?** Turning off both MacStatusBar and MacDock in Settings also hides their Settings pages. Turn them back on in Choicy (or iCleaner Pro), then respring.
- **Crashes after enabling a feature?** Automatic Crash Recovery switches that feature back off after two crashes in a row and tells you in Settings. Use Report a Problem from there.

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

Bug reports and pull requests are welcome. Before your first pull request can be merged, please read [`CONTRIBUTING.md`](./CONTRIBUTING.md). Contributions are only accepted under a short contributor agreement.

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
