TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = SpringBoard
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ForceQuitMenu

ForceQuitMenu_FILES = ForceQuitMenu.x
ForceQuitMenu_CFLAGS = -fobjc-arc
ForceQuitMenu_PRIVATE_FRAMEWORKS = BackBoardServices

include $(THEOS_MAKE_PATH)/tweak.mk
