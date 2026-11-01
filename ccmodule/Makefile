TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

# MacRAMCPU: our own Control Center module (RAM & CPU, 2 x 1): used and available memory and the CPU load; a tap opens a small detail panel.
# MacSSH (1.7.6): our SSH control (1 x 1, Apple's round toggle): a tap switches SSH, a press and hold shows On / Off and the iPad's address.
# One bundle each for iPadOS 15-18, loaded by Control Center like Apple's modules, each from a folder of our own: common/CCModuleRegister.h puts
# those folders and the modules' identifiers in Control Center's module repository (MacCCGrabber in SpringBoard, MacSettings in Settings on 15-17)
# -- SSH's only with OpenSSH installed.
BUNDLE_NAME = MacRAMCPU MacSSH
MacRAMCPU_FILES = MSBDRAMCPUModule.m
MacRAMCPU_CFLAGS = -fobjc-arc
MacRAMCPU_FRAMEWORKS = UIKit
MacRAMCPU_INSTALL_PATH = /usr/lib/MacStatusBarAndDock/ControlCenter

MacSSH_FILES = MSBDSSHModule.m
MacSSH_CFLAGS = -fobjc-arc
MacSSH_FRAMEWORKS = UIKit
MacSSH_PRIVATE_FRAMEWORKS = ControlCenterUIKit
MacSSH_RESOURCE_DIRS = SSHResources
MacSSH_INSTALL_PATH = /usr/lib/MacStatusBarAndDock/ControlCenterSSH

include $(THEOS_MAKE_PATH)/bundle.mk
