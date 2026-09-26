TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = Preferences

include $(THEOS)/makefiles/common.mk

# MacSettings: everything inside the Settings app. MacSettingsBadge: hides the red badge on the Settings icon (SpringBoard).
# MacLargeTitles: no large titles in Apple's own apps, everywhere (Notes, Reminders, Mail, ...), not just Settings.
# MacHomeBar: no home indicator pill, everywhere (Home Screen and every app) — replicates Trim's "Remove Home Bar".
# MacPageDots: no Home Screen page dots — replicates Lynx's "hidePageDots".  Also IconLayout.x: portrait keeps icons on the screen when the layout only fits landscape (Atria).
# MacIconLabels: no Home Screen icon labels, folders keep theirs — replicates Lynx's "hideIconLabels". Debug-only logging for now.
# MacEthernetFix: replaces the crashing Ethernet-interface detail page with a plain label instead of letting Preferences crash.
# MacAppSizeMenu: adds a disabled "App Size: X" row to a Home Screen icon's Haptic Touch menu.
# MacLockStatusBar: hides the status bar on the Lock Screen.
# MacFolderMenu: adds one row per contained app to a Home Screen FOLDER icon's Haptic Touch menu, tapping a row opens that app.
# MacCCGrabber: hides the small grabber/handle line in the top-right corner of Control Center — replicates Lynx's "hideCCGrabber".
TWEAK_NAME = MacSettings MacSettingsBadge MacLargeTitles MacHomeBar MacPageDots MacIconLabels MacEthernetFix MacAppSizeMenu MacLockStatusBar MacFolderMenu MacCCGrabber

MacSettings_FILES = MacSettings.x PointerSettings.x KeyboardSettings.x AutoLock.x NativeRows.x
ifneq ($(FINALPACKAGE),1)
MacSettings_FILES += SpecDump.x
endif
MacSettings_CFLAGS = -fobjc-arc
MacSettings_PRIVATE_FRAMEWORKS = Preferences

MacSettingsBadge_FILES = Badge.x
MacSettingsBadge_CFLAGS = -fobjc-arc

MacLargeTitles_FILES = LargeTitles.x
MacLargeTitles_CFLAGS = -fobjc-arc

MacHomeBar_FILES = HomeBar.x
MacHomeBar_CFLAGS = -fobjc-arc

MacPageDots_FILES = PageDots.x IconLayout.x
MacPageDots_CFLAGS = -fobjc-arc

MacIconLabels_FILES = IconLabels.x
MacIconLabels_CFLAGS = -fobjc-arc

MacEthernetFix_FILES = EthernetFix.x
MacEthernetFix_CFLAGS = -fobjc-arc

MacAppSizeMenu_FILES = AppSizeMenu.x
MacAppSizeMenu_CFLAGS = -fobjc-arc

MacLockStatusBar_FILES = LockStatusBar.x
MacLockStatusBar_CFLAGS = -fobjc-arc

MacFolderMenu_FILES = FolderMenu.x
MacFolderMenu_CFLAGS = -fobjc-arc

MacCCGrabber_FILES = CCGrabber.x
MacCCGrabber_CFLAGS = -fobjc-arc

SUBPROJECTS += sshtoggled

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
