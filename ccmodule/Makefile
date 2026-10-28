TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

# MacRAMCPU: our own Control Center module (RAM & CPU, 2 x 1): used and available memory and the CPU load; a tap opens a small detail panel.
# One bundle for iPadOS 15-18, loaded by Control Center like Apple's modules from our own folder: common/CCModuleRegister.h puts that folder
# and the module's identifier in Control Center's module repository (MacCCGrabber in SpringBoard, MacSettings in Settings on 15-17).
BUNDLE_NAME = MacRAMCPU
MacRAMCPU_FILES = MSBDRAMCPUModule.m
MacRAMCPU_CFLAGS = -fobjc-arc
MacRAMCPU_FRAMEWORKS = UIKit
MacRAMCPU_INSTALL_PATH = /usr/lib/MacStatusBarAndDock/ControlCenter

include $(THEOS_MAKE_PATH)/bundle.mk
