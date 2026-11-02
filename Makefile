# Nogram for iOS 6 — Telegram-style demo client built with Theos.
#
# armv7 only: every device that runs iOS 6 is 32-bit. iPhoneOS 9.3 and 10.3
# are the last SDKs (theos/sdks) that still carry armv7 slices; newer ones
# link nothing for this architecture.
TARGET := iphone:clang:9.3:6.0
ARCHS = armv7
INSTALL_TARGET_PROCESSES = Nogram
# dpkg on iOS 6 jailbreaks predates xz; gzip is the safe choice.
THEOS_PLATFORM_DEB_COMPRESSION_TYPE = gzip

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Nogram

Nogram_FILES = $(wildcard Sources/*.m) $(wildcard Sources/mtproto/*.c)
Nogram_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore Security
Nogram_LIBRARIES = z
# The UIKit APIs iOS 6 has are the ones later SDKs mark deprecated
# (sizeWithFont:, UITextAttribute*, setFinishedSelectedImage:, ...): that is
# deliberate, so the deprecation noise is turned off.
Nogram_CFLAGS = -ISources/mtproto -fobjc-arc -Wno-deprecated-declarations -Wno-unguarded-availability -Wno-unguarded-availability-new

include $(THEOS_MAKE_PATH)/application.mk

after-install::
	install.exec "uicache"
