TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = SpringBoard Preferences
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DockMagnification

DockMagnification_FILES = Dock.x Downloads.m Launchpad.m RunningIndicator.m FinderIcon.m TrashIcon.m IconTheme.m EditProxy.m Bounce.m DockStyle.m DockAutoHide.m
DockMagnification_FRAMEWORKS = UIKit AVFoundation ImageIO
# (1.8.7.7, GitHub #14: every hook keeps its own stack frame while the original runs -- no tail calls -- so a crash under one of our hooks shows
#  our code on the crashing stack, and the crash guard pins it on us and on the feature, CrashBlame.h / CrashFeature.h. Code generation only.)
DockMagnification_CFLAGS = -fobjc-arc -fno-optimize-sibling-calls

SUBPROJECTS += dockmagnificationprefs dockmagnificationsettings

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
