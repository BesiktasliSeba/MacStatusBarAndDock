TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = SpringBoard Preferences
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MacStatusBarCore

MacStatusBarCore_FILES = StatusBar.x SpotlightFiles.x ChargeQuiet.x
# (1.8.7.7, GitHub #14: every hook keeps its own stack frame while the original runs -- no tail calls -- so a crash under one of our hooks shows
#  our code on the crashing stack, and the crash guard pins it on us and on the feature, CrashBlame.h / CrashFeature.h. Code generation only.)
MacStatusBarCore_CFLAGS = -fobjc-arc -fno-optimize-sibling-calls
MacStatusBarCore_PRIVATE_FRAMEWORKS = BackBoardServices
MacStatusBarCore_FRAMEWORKS = NetworkExtension UniformTypeIdentifiers ImageIO CoreSpotlight AudioToolbox IOKit   # (PDFKit, AVKit, AVFoundation: opened by Finder at first use, Finder.h DMFinderClass; AudioToolbox: the Trash emptied sound, SpringBoard has it loaded anyway)

SUBPROJECTS += macstatusbarprefs macstatusbarsettings macpointer

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
