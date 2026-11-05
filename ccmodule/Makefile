TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

# MacRAMCPU: our own Control Center module (RAM & CPU, 2 x 1): used and available memory and the CPU load; a tap opens a small detail panel.
# MacSSH (1.7.6): our SSH control (1 x 1, Apple's round toggle): a tap switches SSH, a press and hold shows On / Off and the iPad's address.
# One bundle each for iPadOS 15-18, loaded by Control Center like Apple's modules, each from a folder of our own: common/CCModuleRegister.h puts
# those folders and the modules' identifiers in Control Center's module repository (MacCCGrabber in SpringBoard, MacSettings in Settings on 15-17)
# -- SSH's only with OpenSSH installed.
# MacConnectivity, MacDisplay, MacSound, MacNowPlaying (1.8.1 item 1): our Mac tiles on iPadOS 18 as Control Center's own modules (only there: CCModuleList.h):
# one small class each, the tile and its pages are the status bar part's (statusbar/CC18Tiles.h).
BUNDLE_NAME = MacRAMCPU MacSSH MacConnectivity MacDisplay MacSound MacNowPlaying
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

MacConnectivity_FILES = MSBDMacConnectivityModule.m
MacConnectivity_CFLAGS = -fobjc-arc
MacConnectivity_FRAMEWORKS = UIKit
MacConnectivity_RESOURCE_DIRS = MacTileResources/Connectivity
MacConnectivity_INSTALL_PATH = /usr/lib/MacStatusBarAndDock/ControlCenterMac

MacDisplay_FILES = MSBDMacDisplayModule.m
MacDisplay_CFLAGS = -fobjc-arc
MacDisplay_FRAMEWORKS = UIKit
MacDisplay_RESOURCE_DIRS = MacTileResources/Display
MacDisplay_INSTALL_PATH = /usr/lib/MacStatusBarAndDock/ControlCenterMac

MacSound_FILES = MSBDMacSoundModule.m
MacSound_CFLAGS = -fobjc-arc
MacSound_FRAMEWORKS = UIKit
MacSound_RESOURCE_DIRS = MacTileResources/Sound
MacSound_INSTALL_PATH = /usr/lib/MacStatusBarAndDock/ControlCenterMac

MacNowPlaying_FILES = MSBDMacNowPlayingModule.m
MacNowPlaying_CFLAGS = -fobjc-arc
MacNowPlaying_FRAMEWORKS = UIKit
MacNowPlaying_RESOURCE_DIRS = MacTileResources/NowPlaying
MacNowPlaying_INSTALL_PATH = /usr/lib/MacStatusBarAndDock/ControlCenterMac

include $(THEOS_MAKE_PATH)/bundle.mk
