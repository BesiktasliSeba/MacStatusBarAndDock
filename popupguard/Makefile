TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = SpringBoard
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

# MacPopupGuard (1.8.8.1 B68): the LNPopupController race guard alone (common/PopupGuard.h), for the package managers that carry that library
# (Sileo, Zebra). The loader gives a recovery app nothing else, and this only when the app contains the library (loader/Loader.c). Every other
# app has the same guard in MacAppBridge.
TWEAK_NAME = MacPopupGuard

MacPopupGuard_FILES = PopupGuardPart.m
# (as every part: each hook keeps its own stack frame while the original runs, 1.8.7.7, GitHub #14)
MacPopupGuard_CFLAGS = -fobjc-arc -fno-optimize-sibling-calls
MacPopupGuard_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
