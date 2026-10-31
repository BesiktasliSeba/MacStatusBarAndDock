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
- **The SSH switch** (Settings, only shown when OpenSSH is installed) starts or stops OpenSSH, which is a network service. The tweak never changes SSH on its own: after installing, OpenSSH stays as it was until you use the switch, and your choice then sticks across restarts. The Settings app isn't allowed to start or stop OpenSSH, or to switch window engines, so a small local root helper (`com.besiktasliseba.sshtoggled`) stays running and does these steps when Settings signals it. **The helper is not an SSH server and accepts no network connections:** it only reacts to local signals from Settings and from Finder (to eject a drive), and reads what to do from preferences apps can't write.
- **Ejecting a drive** (Finder's Eject button and menus, and the Dock's Trash) goes through a small helper, `msbdeject`, because SpringBoard isn't allowed to eject drives. Finder asks the root helper above, which checks that the folder is a USB drive or SD card connected to the iPad and only then runs `msbdeject` for it, as root, one eject at a time. `msbdeject` has no network code, checks the folder again for itself, never ejects the iPad's own storage, and asks iPadOS's storage service (StorageKit) to eject the drive. iPadOS 15 has no StorageKit, so ejecting isn't offered there.
- **Activity Monitor** only reads the process list and the figures iPadOS lets SpringBoard read. Its Quit asks an app to quit, as a swipe up in the App Switcher does.
- **Automatic Crash Recovery** reads the iPad's own crash logs locally, to see whether a SpringBoard crash came from this tweak.

### Checking it yourself

- A source search for networking APIs (`NSURLSession`, `NSURLConnection`, `NSURLRequest`, `NSStream`, `CFStream`, `CFSocket`, `CFNetwork`, Network.framework's `nw_`, `socket(`, `connect(`, `getaddrinfo`, `gethostbyname`, `curl_`) finds no networking implementation (`WKWebView` appears once in `appbridge/AppBridge.x`, only to find an app's own web page view for the Print and Share menu items).
- Report a Problem: `common/CrashExplain.h` (`MSBD_REPORT_URL` and the text it fills in).
- The root helper: `macsettings/sshtoggled/main.m` (SSH on/off, window-engine exclusivity, giving settings back on removal, a drive's eject for Finder).
- The eject helper: `ejecthelper/main.m`, its permissions in `ejecthelper/entitlements.plist`, and the checks of an eject request in `common/DriveEject.h`.
- What gets loaded where: `loader/Loader.c` (see "How it's built" in [docs/development.md](./docs/development.md#how-its-built)).
- Every published package's checksum and the source commit it was built from: [RELEASES.md](https://github.com/BesiktasliSeba/repo/blob/main/RELEASES.md) in the Sileo repo.

## Reporting a security problem

Please don't post details of a security problem in a public issue. Use GitHub's private reporting instead: the **Security** tab of this repository > **Report a vulnerability**. You'll get an answer there.

## Supported versions

Only the latest version gets fixes. Update from the Sileo repo: https://besiktasliseba.github.io/repo/
