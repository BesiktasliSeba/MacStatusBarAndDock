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

- **Report a Problem** (Settings > Status Bar, and the note after an automatic crash recovery) opens a new GitHub issue **in your browser, filled in for you to read, edit and send or discard yourself**. It contains your iPad model (for example iPad13,4), iPadOS version, window engine and its version, the tweak's version, and after a crash a short summary of this tweak's own part of the crash log. Nothing is sent unless you submit the issue.
- **Links** in Settings (the window engines' pages, credits, the Reynard browser) open in your browser only when you tap them.
- **About This iPad** in the Apple menu shows your iPad's serial number on screen, like a Mac does. It is only displayed, never sent or stored.
- **The SSH switch** (Settings, only shown when OpenSSH is installed) starts or stops OpenSSH, which is a network service. The tweak never changes SSH on its own: after installing, OpenSSH stays as it was until you use the switch, and your choice then sticks across restarts. A small root helper (`com.besiktasliseba.sshtoggled`) does the starting and stopping, because Settings isn't allowed to. It stays running as a small local root daemon, waiting for signals from Settings, because the Settings app can't do these privileged steps itself (starting and stopping OpenSSH, and switching window engines). **The helper is not an SSH server and accepts no network connections:** it only reacts to a local signal from Settings and reads what to do from a Settings preference apps can't write.
- **Automatic Crash Recovery** reads the iPad's own crash logs locally, to see whether a SpringBoard crash came from this tweak.

### Checking it yourself

- A source search for networking APIs (`NSURLSession`, `NSURLConnection`, `NSURLRequest`, `NSStream`, `CFStream`, `CFSocket`, `CFNetwork`, Network.framework's `nw_`, `socket(`, `connect(`, `getaddrinfo`, `gethostbyname`, `curl_`) finds no networking implementation (`WKWebView` appears once in `appbridge/AppBridge.x`, only to find an app's own web page view for the Print and Share menu items).
- Report a Problem: `common/CrashExplain.h` (`MSBD_REPORT_URL` and the text it fills in).
- The root helper: `macsettings/sshtoggled/main.m` (SSH on/off, window-engine exclusivity, giving settings back on removal).
- What gets loaded where: `loader/Loader.c` (see "How it's built" in the README).
- Every published package's checksum and the source commit it was built from: [RELEASES.md](https://github.com/BesiktasliSeba/repo/blob/main/RELEASES.md) in the Sileo repo.

## Reporting a security problem

Please don't post details of a security problem in a public issue. Use GitHub's private reporting instead: the **Security** tab of this repository > **Report a vulnerability**. You'll get an answer there.

## Supported versions

Only the latest version gets fixes. Update from the Sileo repo: https://besiktasliseba.github.io/repo/
