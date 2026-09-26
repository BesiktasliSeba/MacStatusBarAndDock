TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = DockMagnificationPrefs

DockMagnificationPrefs_FILES = DMRootListController.m
DockMagnificationPrefs_FRAMEWORKS = UIKit
DockMagnificationPrefs_PRIVATE_FRAMEWORKS = Preferences
DockMagnificationPrefs_INSTALL_PATH = /Library/PreferenceBundles
DockMagnificationPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
