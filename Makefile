ARCHS = arm64 arm64e
DEBUG = 0
FINALPACKAGE = 1
FOR_RELEASE = 1
PACKAGE_VERSION = $(THEOS_PACKAGE_BASE_VERSION)
TARGET=iphone:16.5:14.0

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = libXelahot

libXelahot_CCFLAGS = -std=c++11 -fno-rtti -DNDEBUG
libXelahot_CFLAGS = -fobjc-arc -Wno-deprecated -Wno-deprecated-declarations
libXelahot_FILES = $(wildcard **/*.xm)
libXelahot_FRAMEWORKS = UIKit MobileCoreServices
libXelahot_LDFLAGS += -install_name @rpath/libXelahot.dylib
libXelahot_INSTALL_PATH = /usr/lib
libXelahot_EXTRA_FRAMEWORKS = CydiaSubstrate

include $(THEOS_MAKE_PATH)/library.mk

after-stage::
	@echo "Applying permissions..."
	find $(THEOS_STAGING_DIR) -type f -exec chmod 644 {} \;
	find $(THEOS_STAGING_DIR) -type f \( -name 'postinst' -o -name 'prerm' \) -exec chmod 755 {} \;
	find $(THEOS_STAGING_DIR) -type d -exec chmod 755 {} \;
