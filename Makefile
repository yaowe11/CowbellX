THEOS_PACKAGE_SCHEME = rootless
DEBUG = 0

TARGET := iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SimpleCowbell

SimpleCowbell_FILES = Tweak.x
SimpleCowbell_CFLAGS = -fobjc-arc
SimpleCowbell_FRAMEWORKS = UIKit CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
