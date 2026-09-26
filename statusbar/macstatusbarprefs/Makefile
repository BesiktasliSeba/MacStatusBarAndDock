TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = MacStatusBarPrefs

MacStatusBarPrefs_FILES = MSBRootListController.m MSBGoAppsController.m
MacStatusBarPrefs_FRAMEWORKS = UIKit
MacStatusBarPrefs_PRIVATE_FRAMEWORKS = Preferences
MacStatusBarPrefs_INSTALL_PATH = /Library/PreferenceBundles
MacStatusBarPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
