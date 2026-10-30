TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

# Signed with macOS's own codesign, ad hoc: iPadOS 15 and later run an executable with entitlements only when its signature carries them in DER
# form as well, which this Mac's ldid does not write (a helper signed by it was killed at launch on the 17.5, exit 137); codesign does.
TARGET_CODESIGN = codesign

include $(THEOS)/makefiles/common.mk

# The Dock's Trash ejects a drive dropped on it the way the Files app does: StorageKit's storagekitd, whose state-changing requests need its
# entitlement. SpringBoard does not have it, so this helper (spawned by Finder, statusbar/DockTrash.h) does, and nothing else.
TOOL_NAME = msbdeject
msbdeject_FILES = main.m
msbdeject_CFLAGS = -Wall -fobjc-arc
msbdeject_FRAMEWORKS = Foundation CoreFoundation
msbdeject_CODESIGN_FLAGS = -f -s - --entitlements entitlements.plist --generate-entitlement-der
msbdeject_INSTALL_PATH = /usr/libexec

include $(THEOS_MAKE_PATH)/tool.mk
