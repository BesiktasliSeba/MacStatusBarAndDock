TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

# Signed with macOS's own codesign, ad hoc, entitlements in DER form too (ejecthelper/Makefile: this Mac's ldid signatures are killed at launch on
# iPadOS 15 and later when they carry entitlements).
TARGET_CODESIGN = codesign

include $(THEOS)/makefiles/common.mk

# The Charge Limit's job (launchd com.besiktasliseba.chargelimit, root): holds the battery at the limit set in Settings > Battery > Battery Health &
# Charging (common/ChargeLimit.h). Its entitlements: the battery service's own write permission, for PredictiveChargingInhibit on the PMU iPads
# (as PowerUIAgent has it); powerd's assertions need root only.
TOOL_NAME = msbdcharge
msbdcharge_FILES = main.m
msbdcharge_CFLAGS = -Wall -fobjc-arc
msbdcharge_FRAMEWORKS = Foundation CoreFoundation IOKit
msbdcharge_CODESIGN_FLAGS = -f -s - --entitlements entitlements.plist --generate-entitlement-der
msbdcharge_INSTALL_PATH = /usr/libexec

include $(THEOS_MAKE_PATH)/tool.mk
