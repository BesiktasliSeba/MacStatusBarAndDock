TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = dasd
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PrewarmBlockTweak

PrewarmBlockTweak_FILES = PrewarmBlock.x
# The part's build ID (common/PrewarmPartID.h): from its sources and the build kind, so an install restarts dasd only when the part changed.
# (THEOS_SCHEMA: what the top-level make exports to this one; _THEOS_ON_SCHEMA is set only in the top-level make, and read here it made every
#  debug build's ID the release one. The top Makefile checks the ID in the part it packages.)
MSBD_DASD_PART_ID := $(shell ../tools/prewarm-part-id.sh . $(if $(findstring DEBUG,$(THEOS_SCHEMA)),d,r))
ifeq ($(strip $(MSBD_DASD_PART_ID)),)
$(error the prewarm block's build ID could not be made (tools/prewarm-part-id.sh))
endif
PrewarmBlockTweak_CFLAGS = -fobjc-arc -DMSBD_DASD_PART_ID='"$(MSBD_DASD_PART_ID)"'

include $(THEOS_MAKE_PATH)/tweak.mk
