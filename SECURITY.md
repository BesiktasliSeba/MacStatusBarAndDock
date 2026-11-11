# Security

## What MacStatusBar&Dock does and doesn't do over the network

MacStatusBar&Dock contains **no network or telemetry functionality**. It does not:

- contact any server, the developer's or anyone else's
- send analytics or usage data
- send device identifiers anywhere
- send crash reports automatically
- download or run code from the internet
- update itself (updates come only through your package manager, from the Sileo repo you added)

What it does instead, all on the iPad:

- **Report a Problem** (Settings > Status Bar, and the note after an automatic crash recovery) opens a new GitHub issue **in your browser, filled in for you to read, edit and submit or discard yourself**. It contains your iPad model (for example iPad13,4), iPadOS version, window engine and its version, the tweak's version, and after a crash a short summary of this tweak's own part of the crash log. The report travels in the link to GitHub, so GitHub receives its text when the page opens, even if you never submit it; it is only posted as an issue if you submit it.
- **Links** open in your browser only when you tap them: the window engines' pages in Settings, the Reynard browser's page from the Go menu, and the UTM and VirtualMac pages in About This iPad.
- **Update Available** in the Apple menu reads the package lists your package manager has already downloaded. The tweak doesn't go online to check.
- **The Wi-Fi and VPN menus** use iPadOS's own Wi-Fi and VPN controls on the iPad. The tweak sends nothing of its own.
- **About This iPad** in the Apple menu shows your iPad's serial number on screen, like a Mac does. It is only displayed, never sent or stored.
- **The SSH switch** (Settings and a Control Center control, only shown when OpenSSH is installed) starts or stops OpenSSH, which is a network service. The tweak never changes SSH on its own: after installing, OpenSSH stays as it was until you use the switch, and your choice then sticks across restarts. The Settings app isn't allowed to start or stop OpenSSH, or to switch window engines, Control Centers and banner styles, so a small local root helper (`com.besiktasliseba.sshtoggled`) stays running and does these steps when Settings or Control Center signals it. **The helper is not an SSH server and accepts no network connections:** it only reacts to local signals from Settings, Control Center and Finder (to eject a drive) and to the screen going off (Sleep Guard, below) and to changes of one diagnostics preference (Keep Tailspin Off, below), and reads what to do from preferences apps can't write.
- **Ejecting a drive** (Finder's Eject button and menus, and the Dock's Trash) goes through a small helper, `msbdeject`, because SpringBoard isn't allowed to eject drives. Finder asks the root helper above, which checks that the folder is a USB drive or SD card connected to the iPad and only then runs `msbdeject` for it, as root, one eject at a time. `msbdeject` has no network code, checks the folder again for itself, never ejects the iPad's own storage, and asks iPadOS's storage service (StorageKit) to eject the drive. iPadOS 15 has no StorageKit, so ejecting isn't offered there.
- **Activity Monitor** only reads the process list and the figures iPadOS lets SpringBoard read. Its Quit asks an app to quit, as a swipe up in the App Switcher does.
- **Sleep Guard** (Settings > Battery > Battery Health, on unless you turn it off): each time the screen goes off, the root helper above reads iPadOS's list of power assertions, the requests that keep the iPad awake. If the only one keeping it awake belongs to a process that no longer runs, the helper has launchd start iPadOS's power service (`powerd`) over, which drops that assertion. Never with the screen on or while another process keeps the iPad awake, and at most once in 30 minutes and 6 times a day. Each step goes into a log on the iPad. Nothing is sent anywhere.
- **Battery Health** in Settings reads the battery's capacity and cycle count from iPadOS's battery service, only to show them on that page. It changes nothing about charging: only Charge Limit and Run on Power Adapter, below, do.
- **Charge Limit and Run on Power Adapter** (Settings > Battery > Battery Health, off unless you set them): a second small root helper, `msbdcharge`, a launch daemon of its own (`com.besiktasliseba.chargelimit`), runs only while one of them is set, and the root helper above starts it when Settings sets one. It reads the battery's level and the power adapter from iPadOS's battery service and holds charging with iPadOS's own controls: a power assertion, the battery service's switch that Optimized Battery Charging uses, or, on iPadOS 18 where the iPad has it, iPadOS's own charge limit. Above the limit it can let the iPad use its battery down to it, and it keeps the iPad awake only while it charges toward the limit or uses the battery down to it. It writes none of Apple's preferences. If a hold left by an earlier run keeps charging off, it has `powerd` started over, by Sleep Guard's rules. When both settings are off it lets go of everything and ends, and removing the tweak stops it and gives charging back to iPadOS. It has no network code, and each step goes into a log on the iPad.
- **Keep Tailspin Off** (Settings > Windows & Multitasking, on by default on iPads with 2 GB of memory): while it is on, the root helper above keeps one of iPadOS's diagnostics preferences, `PDSEPrefAllowEnableTailspin` in `com.apple.da`, set to false, so iPadOS's performance diagnostics don't turn on tailspin, a trace of the whole system, by themselves. Turning the switch off or removing the tweak takes that value away again. Nothing is sent anywhere.
- **Control Center Style and Banner Style** (Settings > Status Bar): only the chosen Control Center and banner style load. While Mac or iPadOS is chosen, MacStatusBar&Dock keeps BigSurCenter or Destra from loading in SpringBoard, as it does for the window engines: with an entry in Choicy's list of tweaks not to load, or, without Choicy, the root helper above renames the tweak's library to `.disabled`, as iCleaner Pro does. Each change is recorded on the iPad and given back as it was when you choose that tweak, turn MacStatusBar off in Choicy or iCleaner Pro, downgrade to a version before 1.8.0 or remove MacStatusBar&Dock. A tweak you switched off in Choicy or iCleaner Pro yourself stays off. Nothing is sent anywhere.
- **Automatic Crash Recovery** reads the iPad's own crash logs locally, to see whether a SpringBoard crash came from this tweak.

### Checking it yourself

- A source search for networking APIs (`NSURLSession`, `NSURLConnection`, `NSURLRequest`, `NSStream`, `CFStream`, `CFSocket`, `CFNetwork`, Network.framework's `nw_`, `socket(`, `connect(`, `getaddrinfo`, `gethostbyname`, `curl_`) finds no networking implementation (`WKWebView` appears once in `appbridge/AppBridge.x`, only to find an app's own web page view for the Print and Share menu items).
- Report a Problem: `common/CrashExplain.h` (`MSBD_REPORT_URL` and the text it fills in).
- The root helper: `macsettings/sshtoggled/main.m` (SSH on/off, which window engine, Control Center and banner tweak loads, with the table of these choices in `common/ExclusiveChoice.h`, giving settings back on removal and downgrade, a drive's eject for Finder), `macsettings/sshtoggled/SleepGuardDaemon.h` (Sleep Guard, with its rules in `common/SleepGuard.h`) and `macsettings/sshtoggled/TailspinDaemon.h` (Keep Tailspin Off, with its rules in `common/TailspinGuard.h`).
- The eject helper: `ejecthelper/main.m`, its permissions in `ejecthelper/entitlements.plist`, and the checks of an eject request in `common/DriveEject.h`.
- The charge helper: `chargehelper/main.m`, its permissions in `chargehelper/entitlements.plist`, and its rules in `common/ChargeLimit.h`.
- What gets loaded where: `loader/Loader.c` (see "How it's built" in [docs/development.md](./docs/development.md#how-its-built)).
- Every published package's checksum and the source commit it was built from: [RELEASES.md](https://github.com/BesiktasliSeba/repo/blob/main/RELEASES.md) in the Sileo repo.

## Reporting a security problem

Please don't post details of a security problem in a public issue. Use GitHub's private reporting instead: the **Security** tab of this repository > **Report a vulnerability**. You'll get an answer there.

## Supported versions

Only the latest version gets fixes. Update from the Sileo repo: https://besiktasliseba.github.io/repo/
