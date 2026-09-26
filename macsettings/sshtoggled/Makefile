TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TOOL_NAME = sshtoggled
sshtoggled_FILES = main.m
sshtoggled_CFLAGS = -Wall -fobjc-arc
sshtoggled_FRAMEWORKS = Foundation CoreFoundation
sshtoggled_INSTALL_PATH = /usr/libexec

include $(THEOS_MAKE_PATH)/tool.mk
