TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DockMagnificationSettings

DockMagnificationSettings_FILES = DockSettingsRow.x
DockMagnificationSettings_CFLAGS = -fobjc-arc
DockMagnificationSettings_FRAMEWORKS = UIKit
DockMagnificationSettings_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/tweak.mk
