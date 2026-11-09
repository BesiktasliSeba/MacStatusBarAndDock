# Settings reference

Every switch MacStatusBar&Dock adds, where to find it, what it does, and how it starts on a new install. An update keeps the values you had. "Respring" means the change takes effect after a respring, and Settings offers one.

On an iPadOS version that hasn't been tested, the top of the Status Bar and Dock pages shows **Enable Anyway** (off), which lets the tweak run at your own risk. After Automatic Crash Recovery has acted, the same place says what it turned off, with **Turn Back On** and **Report a Problem**.

On iPadOS 18, Settings has no room for tweak rows in its sidebar, so Status Bar, Desktop, Windows & Multitasking and Dock are in a MacStatusBar&Dock group at the top of Settings > General, together with the sidebar rows further down this page.

## Settings > Status Bar

| Setting | What it does | New install |
|---|---|---|
| MacStatusBar | Turns off everything except the Dock (respring). | On |
| Status Bar Style | Mac: the Mac menu bar with app menus, audio mixing and Mac windows. Stock: the iPadOS status bar, and your window engine runs on its own (respring). | Mac |
| Show Seconds | Seconds in the menu bar clock. | Off |
| Clock Opens Today View | Tapping the clock drops down your Today View widgets. | On |
| Notifications in Today View | Your notifications in a box above the widgets. | On |
| Show Spotlight Search | A magnifying glass next to the clock that opens Spotlight. | On |
| Tweak Settings | Your tweaks' settings in Spotlight, in a section after Apple's results. | Off |
| Actions | Show Desktop, your desktops, Downloads, New Finder Window, Activity Monitor, Lock Screen and Force Quit in Spotlight, when what you type matches. Typing an action's name brings the Actions to the top of the results, right after Apple's Top Hit when there is one. | Off |
| Windows | Your open windows in Spotlight, when what you type matches. | Off |
| Desktop and Downloads | Files in On My iPad > Desktop and Downloads in Spotlight: right away on iPadOS 15, once iPadOS indexes them on 16. Needs Files allowed in Settings > Siri & Search. | Off |
| Menu Bar Size | Small is the standard size. Medium and Large make the menu bar taller, with larger text, icons and menus that are easier to tap with a finger. Window title bars keep their size (respring). | Small |
| Automatically Hide and Show the Status Bar | Hides the menu bar until the pointer reaches the top edge. | Off |
| Banner Style | Mac: notification banners come in at the top right, like on a Mac. iPadOS: Apple's own banners. Destra: Destra's banners, while Destra is installed (a switch to or from it takes a respring). Only the chosen style loads. | Mac, or iPadOS if you had turned off Mac-Style Banners |
| Go Menu > Apps | Choose and order the apps in the Go menu. | |
| Finder | Off removes Finder completely, with its Dock icon and the desktop. | On |
| Activity Monitor > Show in App Library | Activity Monitor as an app in the App Library, in its Utilities category and its search. A tap opens the Activity Monitor window, and Add to Dock in its menu puts it in the Dock. Off also takes it out of the Dock, and on puts it back. | On |
| Report a Problem | Opens a filled-in GitHub issue in your browser. The report is part of the link, so GitHub receives it when the page opens. It is only posted if you submit it. | |
| Background | Automatic: a color behind the menu bar, unless ColorBar15 already colors it. Also Always On or Off. | Automatic |
| Color and opacity | The background color, used while the menu bar text is light. | 70% |
| Control Center Style | Which Control Center opens. Mac: a Control Center like the Mac's, with Airplane Mode, Wi-Fi and Bluetooth (with pages for networks and devices), Display and Sound sliders (Sound's page has a volume for each app) and Now Playing above your other controls. On iPadOS 18, + and the power button sit at its top, Display's page has Dark Mode, Night Shift and True Tone, and Mac has its own list of controls, made once from yours, so iPadOS's own list isn't changed. Mac needs Status Bar Style Mac, and with it the menu bar's Control Center icon shows also while Battery Menu is off. iPadOS: Apple's own. BigSurCenter: while it's installed, with a GET button on iPadOS 15 and 16 while it isn't. Only the chosen one loads, and a switch to or from BigSurCenter takes a respring. | BigSurCenter if it's installed, else iPadOS |
| Hide Grabber (with Control Center Style iPadOS) | Hides the short line at the top right of Control Center. | On |
| Control Center size (with Mac or BigSurCenter) | How large Control Center opens. With Mac on iPadOS 18 it doesn't resize it yet. Not shown with Status Bar Style Stock. | 100% with Mac, 82% with BigSurCenter |
| Haptic Touch Menus | Mac: slimmer long-press menus that turn compact with a trackpad or mouse. Stock: Apple's menus. | Mac |
| Force Quit in App Menus | Force Quit in app icon menus. | On |
| App Size in App Menus | The app's size at the top of its icon menu. | On |
| Folder Apps in Folder Menus | A folder's long-press menu lists its apps. | On |
| Add App to Folder in App Menus | Add App to Folder in the menus of apps on the Home Screen, in folders and in the App Library: the app moves into the Home Screen folder you pick, or into a new one made where the app was. A full folder is greyed out. Not on the Dock's icons. While the AddToFolder tweak is installed, its item is used instead. | On |
| Updates Tab in App Store | The Updates tab in place of Arcade. | On |
| Hide Large Titles | Compact titles in Apple's own apps, like Mac apps. Applies the next time an app opens. | On |
| Search Field in Settings | A search field at the top of the Settings sidebar, with Apple's own results. iPadOS 15 to 17. | On |
| Include Tweak Settings | The search also finds other tweaks' settings. MacStatusBar&Dock's own settings are found either way, as long as their page shows them. iPadOS 15 to 17. | Off |
| Keyboard Button in Status Bar (Experimental) | iPadOS 15 with a hardware keyboard: the floating keyboard and dictation button moves into the menu bar. | Off |
| Esc Ends Typing in Windows | Esc puts away the text cursor in a window. Terminal apps keep their Esc. | On |
| Mix Audio Between Apps | Apps can play at the same time, each with its own volume in the Audio menu. | On |
| Show Mute Icon | A mute icon in the menu bar while the iPad is muted. | On |
| Wi-Fi Menu | The Wi-Fi icon opens a Wi-Fi menu. | On |
| Battery Menu | The battery in the menu bar opens a battery menu, as on a Mac, with its level and power source, a Low Power Mode switch, Sleep Guard and Battery Settings. A Control Center icon next to the clock opens Control Center, and the swipe down from the top right still does. Off: a click on the battery opens Control Center, and there's no icon unless Control Center Style is Mac. The icon lights up while Control Center is open, and a second tap closes it. | On, also after an update |
| Live Activities in Menu Bar | What's playing and your calls show as small pills next to the status icons, like on a Mac, and on iPadOS 17.5.1 and 18.5 Clock timers too. A tap on one opens a card to control it, and the card's title opens the app. One that has ended stays greyed out for a few minutes, then goes. Not shown with Status Bar Style Stock. | On, also after an update |
| Activities | Turns Now Playing and Calls off one by one, and Timers on iPadOS 17.5.1 and 18.5, where timers show. | All on |
| Hide Status Bar on Lock Screen | No status bar on the Lock Screen, and no Control Center line at its top right. | Off |
| Skip Lock Screen After Respring | Goes straight to the Home Screen after a respring. Works only without a passcode. | Off |

## Settings > Desktop

The desktop's settings, on their own page between Status Bar and Windows & Multitasking. The desktop is Finder's: while Finder is off, these rows are greyed out.

| Setting | What it does | New install |
|---|---|---|
| Show Desktop Icons | Files and folders from On My iPad > Desktop on the first Home Screen page. They are separate from your app icons, which stay as they are. | On |
| Hide Desktop Icon Names | Hides the names under every desktop icon. VoiceOver still reads them. An icon's own menu has Hide Name for just that icon. Greyed out while Show Desktop Icons is off. | Off |
| Icon Size | The size of the desktop icons, from 40 to 96 points. The icons change as you drag the slider, their names and spacing follow, and every icon keeps its place. Home Screen app icons stay as they are. | The Home Screen's icon size |
| App Icon Corner Radius | How round the corners of the app icons on the desktop are, from square to a circle. The icons change as you drag the slider. Folders, files and Home Screen icons keep their look. Until you move it, desktop app icons have the same shape as your Home Screen icons, icon theme included. | The Home Screen icons' shape |
| Match Home Screen Icons | Gives desktop app icons your Home Screen icons' shape again, and they follow it from then on. | |

## Settings > Windows & Multitasking

The window settings, on their own page between Desktop and Dock. On iPadOS 15 and 16 the page also shows Apple's Picture in Picture and Gestures settings, which leave General while they are here. On iPadOS 17 and 18, Multitasking & Gestures at the end of the page opens Apple's own page.

| Setting | What it does | New install |
|---|---|---|
| Enable Windowing | Off: no window engine loads and every app opens full screen (respring). | On |
| Window Engine | Which engine runs your windows. Only that one loads (respring). Apple's Stage Manager is listed under Native (not on iPadOS 15), Aerial, Zetsu and MilkyWay4 under Third-Party. With Stage Manager, MacStatusBar&Dock asks before it turns Stage Manager on, and if you say Not Now (or turn it off later), Turn On Stage Manager appears here. With another engine, Stage Manager stays off while it runs and comes back on as you had it when you turn off windowing. | Stage Manager where it runs (iPadOS 16.1 to 18), else Aerial |
| Window Size | The size a new window opens at, with every engine: Small, Default or Large. A window that opens where it last was keeps its size. The Window menu's Small and Large are the same sizes. | Default |
| Double-Tap a Title Bar to | What a double tap on a window's title bar does, as on a Mac, with every engine. Fill or Zoom: the window fills the desktop, and a second double tap gives it its size from before. Minimize: the window goes into its app's icon in the Dock. With no window engine, it sets Finder and TextEdit windows. | Do Nothing (Finder and TextEdit windows zoom until you pick one) |
| Windows Behind Full-Screen Apps | A full-screen app comes in front of your windows, and Window > Bring All to Front brings them back. Off: windows stay in front. | On |
| Resize Handles (Stage Manager engine only) | Mac handles, or Stage Manager's own. | Mac |
| Tint Resize Handles | Resize handles take a soft version of each app's color. | Off |
| New Windows Open at Fill | New windows fill the desktop, with every engine, and Fit to Window doesn't tile them. A window that opens where it last was keeps its place. Hidden while no window engine runs. | Off |
| Home Minimizes Windows | Swiping up from the bottom or pressing the Home button minimizes the windows of the desktop you're on, so the Home Screen shows. Opening an app brings its window back. Keyboard shortcuts for Home, such as Command-H, leave the windows as they are. Off: the windows stay when you go Home. | On, also after an update |
| Resize Apps to Fit Windows (MilkyWay4 only) | Apps lay themselves out for the window. Off: the full-screen layout, scaled down. | On |
| Turn Off Traffic Lights | Hides the window buttons in the menu bar for full-screen apps. | Off |
| Hide Multitasking Dots | Hides the three dots at the top of apps while windowing runs. | On |
| Mac Switcher | Desktops and Mission Control in place of the App Switcher. Turning it off keeps your desktops for when you turn it on again. | Off |
| Go to the App's Desktop | With the Mac Switcher on, opening an app whose window is on another desktop takes you to that desktop. Off: the window comes to the desktop you're on. | Off |
| Prewarm Apps | iPadOS starts some apps in the background before you open them, so they open faster. Off: no app is started before you open it, which keeps that memory free on an iPad with little RAM. Shown only where the tweak can control prewarming on that iPad. | On, Off on iPads with 2 GB of memory |
| Keep Tailspin Off | iPadOS turns on tailspin, a performance trace for Apple's diagnostics, for a few days at a time. It holds tens of MB of memory and samples the whole system many times a second. On: iPadOS doesn't turn it on. Shown only where the tweak can control it on that iPad. | Off, On on iPads with 2 GB of memory |

## Settings > Dock

| Setting | What it does | New install |
|---|---|---|
| Mac-Style Dock | Turns off the Dock features (respring). | On |
| Position on Screen | Where the Dock sits: Bottom, Left or Right. Left and Right apply in landscape, and in portrait the Dock stays at the bottom. At a side, windows on every engine, Home Screen icons, the clock's Today drop-down and Mac-style banners keep clear of it, and over a full-screen app the pointer at that edge brings it out. A change applies at once. | Bottom |
| Dock Style | Default: the Dock as before. Glass Shelf: the glass Dock of Mac OS X 10.5 to 10.9, with the icons' reflections and glowing lights under open apps, and a dark panel at the sides as it was then. Frosted: the flat Dock of 10.10 to 10.15. | Default |
| Magnify Icons | Icons grow under the pointer, with a trackpad or mouse. The slider sets how much, from 1x to 2.5x. | On, 1.22x |
| Icon Size | The size of the Dock icons, from 0.5x to 1.2x. | 0.85x |
| Larger Dock in Portrait | A bigger Dock in portrait. | On |
| Gap to Screen Edge | Space between the Dock and the screen's edge, from 0 to 24 pt. | 6 pt |
| Automatically Hide and Show the Dock | The Dock hides until you swipe up from the bottom of the screen or move the pointer to the edge where it sits, like on a Mac, with every window engine. Windows can use the room it leaves, and it shows while you edit the Home Screen. With the Stage Manager engine it takes the place of Stage Manager's own Dock option, which follows it. | Off, also after an update |
| Animate Opening Applications | An app's icon bounces in the Dock while the app opens, like on a Mac. An app that's already open comes forward without a bounce. Nothing bounces while Reduce Motion is on. | On, also after an update |
| Number of Recent Apps | Up to 10 recent apps after your own (respring). A suggested or Handoff app can appear too. None also turns off Apple's Show Suggested and Recent Apps in Dock. | 3 |
| Show Indicators for Open Apps | A dot under apps that are open, also while their windows are on another desktop or minimized. An app iPadOS starts in the background by itself gets no dot until you open it. | On |
| Show App Library in Dock | Apple's own switch, moved here while the Dock features are on. | Apple's setting |
| Launchpad Icon | A Launchpad icon that opens the App Library. | On |
| Style | The Launchpad icon: Classic (Rocket) or Grid. | Classic |
| Next to Finder | Launchpad sits next to Finder at the start of the Dock. Off: at the end. | On |
| Escape Closes App Library | Esc closes the App Library. | On |
| Show Finder in Dock | Finder as the first Dock icon. Not shown while Finder is off. | On |
| Show Downloads in Dock | The Downloads stack at the end of the Dock. | On |
| Downloads From | Which apps' downloads the stack shows: Safari, plus other apps you pick. | Safari |
| Show Trash in Dock | A Trash at the end of the Dock, after Downloads, while Finder is on. It looks full when Finder's Trash has items, a tap opens it in Finder, and a long press or a right click offers Open and Empty Trash, which asks first. Drop files on it to move them to the Trash, a Dock app to take it out of the Dock, or a drive from Finder's sidebar to eject it (iPadOS 16 to 18). | Off |

## Settings > Home Screen & Multitasking

On iPadOS 15 this page is called Home Screen (Home Screen & Dock while the Dock features are off). MacStatusBar&Dock adds one group to it (on iPadOS 17 and 18 the group is on the Dock page):

| Setting | What it does | New install |
|---|---|---|
| Swipe Up Does Not Open App Library | Stops a swipe up on the Home Screen from opening the App Library. | On |
| Swipe Down Opens App Library | A swipe down on the Home Screen opens the App Library while the menu bar shows its Spotlight button, and Spotlight otherwise. | On |
| Swipe Past Last Page Opens App Library | Swiping past the last Home Screen page opens the App Library, as in iPadOS. Off: the pages end at the last one, and the Dock's Launchpad icon still opens the App Library. | Off, also after an update |
| Show Page Dots | The page dots below the Home Screen icons (respring). | On |
| Show App Names | Names under Home Screen icons. Folders keep theirs either way (respring). | On |

## Rows in the Settings sidebar

These show up only when they apply. While the Pointer and Keyboard rows are there, Apple's own copies of those settings move into them, so each setting has one place. On iPadOS 18 the rows are in the MacStatusBar&Dock group at the top of Settings > General, Apple's pages keep their own rows, and Apple's Hardware Keyboard and Trackpad pages start with the switches from the Keyboard and Pointer pages below.

| Row | What it does | New install |
|---|---|---|
| SSH (when OpenSSH is installed) | Starts or stops OpenSSH. Your choice survives restarts, and installing the tweak never changes it. The SSH control in Control Center does the same. | As it was |
| Home Bar (iPads with a home bar) | Shows the home indicator line at the bottom edge. The swipe works either way. | Off (hidden) |
| Pointer (with a trackpad or mouse) | The pointer page below, followed by Apple's Pointer Control and Trackpad & Mouse settings. | |
| Keyboard (with a hardware keyboard) | The keyboard page below, followed by Apple's Hardware Keyboard settings. | |

On iPadOS 15 to 17, Notifications and Sounds share one row, Notifications & Sounds, and Focus and Screen Time another, Focus & Screen Time. Each opens a page with Apple's two pages on it. Links and search results that lead to one of Apple's four pages open it there.

### Pointer

| Setting | What it does | New install |
|---|---|---|
| Pointer Style | Mac: the Mac arrow and I-beam, with Pointer Animations in Accessibility turned off while it is on (your own setting comes back with the iPadOS pointer, and if you turn them back on, they stay on). iPadOS: Apple's round pointer. The Mac pointer follows Apple's Pointer Size. | Mac |
| Hide in Virtual Mac | Hides the Mac pointer in the VirtualMac app, which draws its own. Shown only on iPads that can run virtual machines (M1 and M2 iPads up to iPadOS 16.3.1). | On |
| Use Pointer Control Style | The Mac pointer takes Color, Border Width and Increase Contrast from Pointer Control. Off: the classic black and white pointer. | Off |
| Block Pointer Pull-Down | Stops the pointer at the top edge from pulling down the Lock Screen. | On |

### Keyboard

For keyboards without a function row, like the original Magic Keyboard for iPad. They apply at once.

| Setting | What it does | New install |
|---|---|---|
| Top-Left Key as Escape | The key at the top left, next to 1, becomes Escape, whatever your layout types there. | Off |
| Tab Key Toggles Mute | A plain Tab mutes and unmutes the iPad instead of typing a tab. Full Keyboard Access keeps Tab. | Off |
| Globe + Option/Control for Volume | Volume keys. Needs the Globe key set to Globe in Modifier Keys. | Off |
| Shift + =/- for Screen Brightness | Screen brightness keys. | Off |
| Shift + Option/Control for Backlight | Keyboard backlight keys, on keyboards with a backlight. | Off |

At the end of the page, after Apple's Hardware Keyboard settings:

| Setting | What it does | New install |
|---|---|---|
| Window Tiling Shortcuts | macOS 15's keys for tiling the front window, with Globe and Control held: an arrow key for that half of the screen, F to fill it, C to center the window at its own size, R to give it back the size it had before. Add Shift to arrange it with the window behind it, or Option and Shift for three windows. They work with every window engine and on Finder and TextEdit windows. On a keyboard without a Globe key, set another key to Globe in Modifier Keys. While this is on, the Globe volume keys and the backlight keys act when you let go of them. | Off |
| KeyPilot (under Custom Shortcuts) | KeyPilot by wanghuangjie is a separate tweak for your own keyboard shortcuts for apps, window layouts and URLs. Its window layouts use MacStatusBar&Dock's windows. GET opens its page while it isn't installed, and OPEN opens it once it is. | |

## Control Center

| Control | What it does | New install |
|---|---|---|
| Mac Connectivity, Mac Display, Mac Sound, Mac Now Playing (iPadOS 18, with Control Center Style Mac) | The Mac Control Center's tiles, at the top of its first page. While Mac is the style, Add a Control lists them under Mac Control Center. Edit mode resizes them: Mac Connectivity 2 x 2 or 4 x 2, Mac Display and Mac Sound 4 x 1 or 2 x 1, Mac Now Playing 4 x 1 or 2 x 2. | Added to Mac's own list of controls |
| RAM & CPU | Available memory, used memory and the CPU load, in a 2 x 1 control. A tap opens the details (memory, CPU and uptime) with Open Activity Monitor. On iPadOS 18, add it with Add a Control, where it's under Activity Monitor (or search for RAM). On iPadOS 15 to 17, add it in Settings > Control Center. With BigSurCenter it fits a square tile. With Memory Magic on iPadOS 15 to 17, a tap on its tile, which shows the same numbers, offers to put RAM & CPU in its place. On iPadOS 15 to 17 it's added by itself once, the first time Control Center opens and closes after an install or update, if it fits at the end without moving anything. Once you take it out, it isn't added again. | Added by itself where it fits (iPadOS 15 to 17), else not added |
| SSH (when OpenSSH is installed) | Turns SSH on and off, as the SSH row in the Settings sidebar does; the two always agree, and so does the menu bar's SSH icon. A press and hold shows whether SSH is on, the iPad's address and the ssh command, and the reason when a switch didn't work. On iPadOS 18, add it with Add a Control, where it's under Settings. On iPadOS 15 to 17, add it in Settings > Control Center. With BigSurCenter on iPadOS 15 and 16 it works there too, and shows up after a respring. | Not added |

## Settings > Battery > Battery Health

On iPad, MacStatusBar&Dock opens Apple's Battery Health page (Battery Health & Charging on iPadOS 16 to 18), with the battery's Maximum Capacity and a Cycle Count row. Rows for iPhone-only features, such as Peak Performance Capability, are left out. It's the tweak's own page, with the group below, also while another battery health tweak is installed. The battery menu's Sleep Guard row opens it.

| Setting | What it does | New install |
|---|---|---|
| Sleep Guard | In the Battery Use group. With the screen off, when the only thing keeping the iPad awake is a hold left behind by a process that's gone, such as a SpringBoard from before a respring, it clears that hold so the iPad can sleep. Never with the screen on or while something else keeps the iPad awake, and at most once in 30 minutes and 6 times a day. While a hold is stuck and not cleared, an iPad Can't Sleep row shows since when. | On |

## Elsewhere in Settings

- Display & Brightness > Auto-Lock offers 30 minutes, 1 hour and 2 hours too, except in Low Power Mode. iPadOS takes any time over an hour for Never, so the tweak keeps 2 hours in SpringBoard's idle timer, and 2 hours is listed only while it can. Removing the tweak or switching MacStatusBar off sets 2 hours to 1 hour, and switching MacStatusBar on again brings the 2 hours back. With an Aerial, Zetsu or MilkyWay4 window in front, the iPad gets the whole Auto-Lock time, as with an app in front.
- Ethernet is listed in the sidebar with or without an adapter, except while a trackpad or mouse and a keyboard are both connected and no adapter is. Then the Pointer and Keyboard rows are there, and Ethernet comes back as soon as an adapter is connected or one of the two is disconnected.

## In the menu bar's Window menu

These two live in the Window menu instead of Settings, so you can change them while you work.

| Item | What it does | New install |
|---|---|---|
| Open Apps as Windows | Apps open as windows from anywhere: the Home Screen, the Dock, Spotlight, links, notifications and other tweaks' launchers. With Aerial it is Aerial's own Control Center toggle. | Off (Stage Manager engine: On) |
| Fit to Window | Tiles your windows side by side, from edge to edge with 6 points between them. When a third app opens, you pick its side, or No Fit. Windows keep their places when one closes or another joins, a minimized window keeps its tile, and a fifth window opens over the tiles. Switched off, it spreads the windows back out at a normal size. | Off |

The Window menu also has Minimize All Windows, Bring All to Front or Send All to Back, the layouts (Fill Screen, Center, halves, quarters, Small, Large) and, with the Stage Manager engine and a display connected, Move to Other Display. Fill Screen, the halves and the quarters reach the screen's edges, from right under the menu bar down to the Dock.

## Always on

These have no switch:

- The red badge on the Settings icon is hidden.
- The Settings app has no large title and no alert banners over its sidebar, and Accessibility starts its own section.
- Command-Tab brings an app's window to the front when it has one, and a quick Command-Tab from a window goes back to the app you used before. Activity Monitor is in Command-Tab too while its window is open.
- Windows have a smallest size with every window engine, as with Stage Manager: the app at least 320 x 300 points, as far as the screen allows.
- New windows open at the same place and size with every window engine, and a new window that would cover another steps aside from it.
- A window you move or resize lines up with the screen edges, the menu bar, the Dock and other windows when you let go of it near them, with every window engine.
- When you turn the iPad, a window in a layout (Fill Screen, a half or a quarter) takes the same layout in the new orientation, and any other window goes back to where it last was in that orientation, with every window engine.
- With Aerial, Zetsu or MilkyWay4 on iPadOS 15 to 18, every app with a window has its card in iPadOS's App Switcher, with a picture of the window. A tap on the card brings the window forward.
- On iPads with a Home button, windows placed before 1.7.1 with a gap under the menu bar move up under it once.
- In portrait, a Home Screen page whose icon layout only fits landscape (for example one tuned with Atria, which keeps one layout for both orientations) keeps its landscape positions, so no icon ends up off the screen. Pages that fit in portrait are left as they are, and so is editing the Home Screen.
