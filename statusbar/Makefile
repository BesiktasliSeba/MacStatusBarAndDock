TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = SpringBoard Preferences
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MacStatusBarCore

MacStatusBarCore_FILES = StatusBar.x
MacStatusBarCore_CFLAGS = -fobjc-arc
MacStatusBarCore_PRIVATE_FRAMEWORKS = BackBoardServices
MacStatusBarCore_FRAMEWORKS = NetworkExtension UniformTypeIdentifiers ImageIO   # (PDFKit, AVKit, AVFoundation: opened by Finder at first use, Finder.h DMFinderClass)

SUBPROJECTS += macstatusbarprefs macstatusbarsettings macpointer

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
