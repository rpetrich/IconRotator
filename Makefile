TWEAK_NAME = IconRotator
IconRotator_FILES = Tweak.x
IconRotator_FRAMEWORKS = Foundation UIKit QuartzCore

SDKVERSION = 5.1
INCLUDE_SDKVERSION = 6.1
TARGET_IPHONEOS_DEPLOYMENT_VERSION = 2.0

ADDITIONAL_CFLAGS = -std=c99

include framework/makefiles/common.mk
include framework/makefiles/tweak.mk
