target = iphone:clang:10.0:6.0
ARCHS ?= armv6 arm64
debug ?= no
GO_EASY_ON_ME = 1
include $(THEOS)/makefiles/common.mk

CPROJ = curl
curl_TAG = curl-7_58_0

CFGOPTS = --host=$(subst arm64,aarch64,$(ARCH))-apple-darwin --prefix=/usr --with-darwinssl
CC = "xcrun -sdk iphoneos clang"
CFLAGS = -isysroot $(ISYSROOT) $(SDKFLAGS) $(VERSIONFLAGS) $(_THEOS_TARGET_CC_CFLAGS) -w
CPP = $(CC) -E
CPPFLAGS = $(CFLAGS)
LDFLAGS = #-isysroot $(SYSROOT) $(SDKFLAGS) $(VERSIONFLAGS) $(LEGACYFLAGS) -multiply_defined suppress
MAKEFLAGS = NO_DARWIN_PORTS=1 NO_FINK=1 -j16

SIGN_BINS = $(shell find $(THEOS_STAGING_DIR) -type f -perm +111)
SIGN_LIBS = $(shell find $(THEOS_STAGING_DIR) -name *.so)

ARCH = $(basename $@)
BUILD = $(ARCH).$(CPROJ)build

.PHONY: configured built staged

$(CPROJ):
	$(ECHO_NOTHING)git submodule update $@$(ECHO_END)

%.patched: $(CPROJ).diff $(CPROJ)
	$(ECHO_NOTHING)cd $(CPROJ); git checkout $($(CPROJ)_TAG)$(ECHO_END)
	rm -rf $(CPROJ).patched
	cp -a $(CPROJ) $(CPROJ).patched
	cd $(CPROJ).patched; patch -p1 < ../$(CPROJ).diff; ./buildconf

%.configured: $(CPROJ).patched
	rm -rf $(BUILD)
	cp -a $(CPROJ).patched $(BUILD)
	cd $(BUILD); \
		CC=$(CC) \
	 	CFLAGS="$(CFLAGS) -arch $(ARCH)" \
		LDFLAGS="$(LDFLAGS) -arch $(ARCH)" \
		CPPFLAGS="$(CPPFLAGS) -arch $(ARCH)" \
		./configure $(CFGOPTS)
	$(ECHO_NOTHING)touch $@$(ECHO_END)

configured: $(foreach ARCH,$(ARCHS), $(ARCH).configured)

%.built: $(foreach ARCH,$(ARCHS), $(ARCH).configured)
	$(MAKE) -C $(BUILD) $(MAKEFLAGS)
	touch $@

built: $(foreach ARCH,$(ARCHS), $(ARCH).built)

internal-all:: built

%.staged: $(foreach ARCH,$(ARCHS), $(ARCH).built)
	@echo Copying $(ARCH)
	$(ECHO_NOTHING)rm -rf $(THEOS_OBJ_DIR)/$(ARCH)/$(ECHO_END)
	$(ECHO_NOTHING)$(MAKE) -C $(BUILD) $(MAKEFLAGS) DESTDIR=$(THEOS_OBJ_DIR)/$(ARCH)/ install$(ECHO_END)
	$(ECHO_NOTHING)touch $@$(ECHO_END)
	@echo Finished copying $(ARCH)

staged: $(foreach ARCH,$(ARCHS), $(ARCH).staged)
	@echo -n Staging copies of perl...
	$(ECHO_NOTHING)rsync -a $(foreach ARCH,$(ARCHS), $(THEOS_OBJ_DIR)/$(ARCH)/) $(THEOS_STAGING_DIR)$(ECHO_END)
	@echo done.
	@echo -n Merging binaries...
	$(ECHO_NOTHING)set -e ;\
	BINS=$$(for file in $$(find $(THEOS_STAGING_DIR) -type f -perm +111); do file -h -b --mime $$file | grep -q "charset=binary" && echo $$file || true; done | sed -e 's|$(THEOS_STAGING_DIR)||g') ;\
	for file in $$BINS; do \
		rm $(THEOS_STAGING_DIR)/$$file; \
		$(_THEOS_PLATFORM_LIPO) $(foreach ARCH,$(ARCHS),-arch $(ARCH) $(THEOS_OBJ_DIR)/$(ARCH)/$$file) -create -output $(THEOS_STAGING_DIR)/$$file ;\
	done$(ECHO_END)
	@echo done.
	
#$(ECHO_NOTHING)$(foreach FILE,$(SIGN_BINS),file -h -b --mime $(FILE) | grep -q "charset=binary" && ldid -Sent.xml $(FILE) || true;)$(ECHO_END)
after-stage:: staged
	@echo -n Signing binaries...
	$(ECHO_NOTHING)set -e ;\
	BINS=$$(for file in $(SIGN_BINS); do file -h -b --mime $$file | grep -q "charset=binary" && echo $$file || true; done) ;\
	for file in $$BINS; do ldid -Sent.xml $$file; done;$(ECHO_END)
	@echo done.
	@echo -n Signing libraries...
	$(ECHO_NOTHING)set -e ;\
	BINS=$$(for file in $(SIGN_LIBS); do file -h -b --mime $$file | grep -q "charset=binary" && echo $$file || true; done) ;\
	for file in $$BINS; do ldid -S $$file; done;$(ECHO_END)
	@echo done.

after-clean::
	@echo -n Cleaning temporary build files...
	$(ECHO_NOTHING)rm -rf *.patched$(ECHO_END)
	@echo -n .
	$(ECHO_NOTHING)rm -rf *.$(CPROJ)build$(ECHO_END)
	@echo -n .
	$(ECHO_NOTHING)rm -rf *.configured$(ECHO_END)
	@echo -n .
	$(ECHO_NOTHING)rm -rf *.staged$(ECHO_END)
	@echo -n .
	$(ECHO_NOTHING)rm -rf *.built$(ECHO_END)
	@echo done.

include $(THEOS_MAKE_PATH)/null.mk
