TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

# MacSpotlight: our sections in Apple's Spotlight (Actions, Windows; 1.4.3, S-3), inside the Spotlight app (loader/Loader.c loads it only there).
TWEAK_NAME = MacSpotlight

MacSpotlight_FILES = MacSpotlight.x
MacSpotlight_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
