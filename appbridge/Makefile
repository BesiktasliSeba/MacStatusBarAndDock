TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = SpringBoard
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MacAppBridge

MacAppBridge_FILES = AppBridge.x
MacAppBridge_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
