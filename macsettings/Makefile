TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = Preferences

include $(THEOS)/makefiles/common.mk

# MacSettings: everything inside the Settings app. MacSettingsBadge: the Settings part SpringBoard loads -- hides the red badge on the Settings icon,
# and keeps the longer Auto-Lock times in SpringBoard's idle timer (AutoLockTimer.x).
# MacLargeTitles: no large titles in Apple's own apps, everywhere (Notes, Reminders, Mail, ...), not just Settings.
# MacHomeBar: no home indicator pill, everywhere (Home Screen and every app) — replicates Trim's "Remove Home Bar".
# MacPageDots: no Home Screen page dots — replicates Lynx's "hidePageDots".  Also IconLayout.x: portrait keeps icons on the screen when the layout only fits landscape (Atria).
# MacIconLabels: no Home Screen icon labels, folders keep theirs — replicates Lynx's "hideIconLabels". Debug-only logging for now.
# MacEthernetFix: replaces the crashing Ethernet-interface detail page with a plain label instead of letting Preferences crash.
# MacAppSizeMenu: adds a disabled "App Size: X" row to a Home Screen icon's Haptic Touch menu.
# MacLockStatusBar: hides the status bar on the Lock Screen.
# MacFolderMenu: adds one row per contained app to a Home Screen FOLDER icon's Haptic Touch menu, tapping a row opens that app.
# MacCCGrabber: hides the small grabber/handle line in the top-right corner of Control Center — replicates Lynx's "hideCCGrabber".
# MacAddToFolder: "Add to Folder" in an app icon's Haptic Touch menu (1.7.2): the app moves into a Home Screen folder, or a new one.
# MacLockScreen: Mac Lock Screen (1.8.9, F49): a light, part-by-part Mac style over the Lock Screen, off by default (MacLockScreen.x).
TWEAK_NAME = MacSettings MacSettingsBadge MacLargeTitles MacHomeBar MacPageDots MacIconLabels MacEthernetFix MacAppSizeMenu MacLockStatusBar MacFolderMenu MacCCGrabber MacAddToFolder MacLockScreen

MacSettings_FILES = MacSettings.x PointerSettings.x KeyboardSettings.x CustomShortcuts.x AutoLock.x NativeRows.x SidebarSearch.x TweakSearch.x AppleGroups18.x SidebarGroups.x BatteryHealth.x BatteryUse.x BatteryHealthLink.x
ifneq ($(FINALPACKAGE),1)
MacSettings_FILES += SpecDump.x
endif
MacSettings_CFLAGS = -fobjc-arc
MacSettings_PRIVATE_FRAMEWORKS = Preferences
MacSettings_FRAMEWORKS = CoreSpotlight

MacSettingsBadge_FILES = Badge.x AutoLockTimer.x
# (1.8.7.7, GitHub #14: every hook keeps its own stack frame while the original runs -- no tail calls -- so a crash under one of our hooks shows
#  our code on the crashing stack, and the crash guard pins it on us and on the feature, CrashBlame.h / CrashFeature.h. Code generation only;
#  the parts below, which run in SpringBoard, not MacSettings and MacEthernetFix, which run in Settings only.)
MacSettingsBadge_CFLAGS = -fobjc-arc -fno-optimize-sibling-calls

MacLargeTitles_FILES = LargeTitles.x
MacLargeTitles_CFLAGS = -fobjc-arc -fno-optimize-sibling-calls

MacHomeBar_FILES = HomeBar.x
MacHomeBar_CFLAGS = -fobjc-arc -fno-optimize-sibling-calls

MacPageDots_FILES = PageDots.x IconLayout.x
MacPageDots_CFLAGS = -fobjc-arc -fno-optimize-sibling-calls

MacIconLabels_FILES = IconLabels.x
MacIconLabels_CFLAGS = -fobjc-arc -fno-optimize-sibling-calls

MacEthernetFix_FILES = EthernetFix.x
MacEthernetFix_CFLAGS = -fobjc-arc

MacAppSizeMenu_FILES = AppSizeMenu.x
MacAppSizeMenu_CFLAGS = -fobjc-arc -fno-optimize-sibling-calls

MacLockStatusBar_FILES = LockStatusBar.x
MacLockStatusBar_CFLAGS = -fobjc-arc -fno-optimize-sibling-calls

MacFolderMenu_FILES = FolderMenu.x
MacFolderMenu_CFLAGS = -fobjc-arc -fno-optimize-sibling-calls

MacCCGrabber_FILES = CCGrabber.x
MacCCGrabber_CFLAGS = -fobjc-arc -fno-optimize-sibling-calls

MacAddToFolder_FILES = AddToFolder.x
MacAddToFolder_CFLAGS = -fobjc-arc -fno-optimize-sibling-calls

MacLockScreen_FILES = MacLockScreen.x
MacLockScreen_CFLAGS = -fobjc-arc -fno-optimize-sibling-calls
MacLockScreen_FRAMEWORKS = UIKit QuartzCore CoreGraphics

SUBPROJECTS += sshtoggled

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
