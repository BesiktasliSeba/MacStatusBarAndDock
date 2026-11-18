TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard


include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VolumeGlobeTweak

VolumeGlobeTweak_FILES = VolumeGlobe.x
# (1.8.7.7, GitHub #14: every hook keeps its own stack frame while the original runs -- no tail calls -- so a crash under one of our hooks shows
#  our code on the crashing stack, and the crash guard pins it on us and on the feature, CrashBlame.h / CrashFeature.h. Code generation only.)
VolumeGlobeTweak_CFLAGS = -fobjc-arc -fno-optimize-sibling-calls

include $(THEOS_MAKE_PATH)/tweak.mk
