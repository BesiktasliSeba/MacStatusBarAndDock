TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MacStatusBarSettings

MacStatusBarSettings_FILES = StatusBarSettingsRow.x MSBDSettingsProbe.m
MacStatusBarSettings_CFLAGS = -fobjc-arc
MacStatusBarSettings_FRAMEWORKS = UIKit
MacStatusBarSettings_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/tweak.mk
