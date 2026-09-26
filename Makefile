TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

# The two lines Choicy / iCleaner Pro show: small loaders (loader/Loader.c) for the parts ("payloads") built by the subprojects below.
TWEAK_NAME = MacStatusBar MacDock
MacStatusBar_FILES = loader/Loader.c
MSBD_BUILD_VERSION := $(shell sed -n 's/^Version: //p' control)
MacStatusBar_CFLAGS = -DMSBD_LINE_DOCK=0 -DMSBD_BUILD_VERSION='"$(MSBD_BUILD_VERSION)"'
MacDock_FILES = loader/Loader.c
MacDock_CFLAGS = -DMSBD_LINE_DOCK=1 -DMSBD_BUILD_VERSION='"$(MSBD_BUILD_VERSION)"'

# The crash guard's helper (common/CrashGuard.h): judges a SpringBoard crash report with Foundation, which the loaders do not link. Opened by the
# guard only when it has to; never loaded as a part.
LIBRARY_NAME = MacCrashBlame
MacCrashBlame_FILES = loader/CrashBlameHelper.m loader/CrashFeatureHelper.m
MacCrashBlame_CFLAGS = -fobjc-arc
MacCrashBlame_FRAMEWORKS = Foundation
MacCrashBlame_INSTALL_PATH = /usr/lib/MacStatusBarAndDock

# The crash guard's one-time notice (loader/CrashNotice.m): a stock alert on the Home Screen after the guard acted. No hooks; SpringBoard's loaders
# open it only while an unshown guard record exists (also when the guard turned the tweak off). Never loaded as a part.
LIBRARY_NAME += MacCrashNotice
MacCrashNotice_FILES = loader/CrashNotice.m
MacCrashNotice_CFLAGS = -fobjc-arc
MacCrashNotice_FRAMEWORKS = Foundation UIKit
MacCrashNotice_INSTALL_PATH = /usr/lib/MacStatusBarAndDock

# Each part keeps its own project (it used to be a tweak of its own); they are moved out of the tweak folder when packaged.
SUBPROJECTS += statusbar macsettings dock appbridge mixaudio forcequitmenu graveescape tabmute volumeglobe brightnesskey

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/library.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

PAYLOADS = BrightnessKeyTweak DockMagnification DockMagnificationSettings ForceQuitMenu GraveEscapeTweak MacAppBridge MacAppSizeMenu MacCCGrabber \
           MacEthernetFix MacFolderMenu MacHomeBar MacIconLabels MacLargeTitles MacLockStatusBar MacPageDots MacPointer MacSettings MacSettingsBadge \
           MacStatusBarCore MacStatusBarSettings MixAudio TabMuteTweak VolumeGlobeTweak

# BuildInfo.txt (next to the parts): the commit this package was built from, whether the tree had uncommitted changes, whether it is a debug build.
# tools/verify-release.sh compares it with the tree, so a stale or debug package is never published by mistake.
# The crash guard's step 1b map (common/CrashStep.h): which feature a crash address in a part belongs to, from the build's debug symbols
# (tools/make-crashmap.py, tools/crashmap-rules.txt); shipped as CrashMap.txt next to the parts, read only after crashes that count.
# Only the two loaders stay in the tweak folder; every part goes to usr/lib/MacStatusBarAndDock (not a tweak folder, so no Choicy/iCleaner line of its own).
internal-stage::
	$(ECHO_NOTHING)set -e; T="$(THEOS_STAGING_DIR)"; D="$$T/Library/MobileSubstrate/DynamicLibraries"; P="$$T/usr/lib/MacStatusBarAndDock"; \
	mkdir -p "$$P"; \
	for n in $(PAYLOADS); do mv -f "$$D/$$n.dylib" "$$P/$$n.dylib"; rm -f "$$D/$$n.plist"; done; \
	left=$$(ls "$$D" | grep -v -E '^(MacStatusBar|MacDock)\.(dylib|plist)$$' || true); [ -z "$$left" ] || { echo "unexpected files in the tweak folder: $$left"; exit 1; }; \
	python3 tools/make-crashmap.py tools/crashmap-rules.txt "$(THEOS_OBJ_DIR)" "$$P" . "$$P/CrashMap.txt"; \
	{ echo "commit $$(git rev-parse HEAD 2>/dev/null || echo unknown)"; \
	  echo "dirty $$(if [ -n "$$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then echo 1; else echo 0; fi)"; \
	  echo "debug $(if $(findstring DEBUG,$(_THEOS_ON_SCHEMA)),1,0)"; echo "version $(MSBD_BUILD_VERSION)"; } > "$$P/BuildInfo.txt"$(ECHO_END)
