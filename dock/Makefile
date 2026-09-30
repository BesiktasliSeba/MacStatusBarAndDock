TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = SpringBoard Preferences
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DockMagnification

DockMagnification_FILES = Dock.x Downloads.m Launchpad.m RunningIndicator.m FinderIcon.m
DockMagnification_FRAMEWORKS = UIKit AVFoundation ImageIO
DockMagnification_CFLAGS = -fobjc-arc

SUBPROJECTS += dockmagnificationprefs dockmagnificationsettings

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
