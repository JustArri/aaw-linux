################################################################################
#
# aaw
#
################################################################################

AAW_VERSION = 0.1.0
AAW_SITE = $(BR2_EXTERNAL_AAW_PATH)/aaw
AAW_SITE_METHOD = local
AAW_OVERRIDE_SRCDIR_RSYNC_EXCLUSIONS = \
	--exclude .ignore/ \
	--exclude target/ \
	--exclude frontend/node_modules/ \
	--exclude frontend/.svelte-kit/

AAW_DEPENDENCIES = \
	alsa-lib \
	libsndfile \
	pipewire \
	host-clang \
	host-cmake \
	host-pkgconf

AAW_CARGO_BUILD_OPTS = --no-default-features --bin aaw

AAW_CARGO_ENV = \
	CMAKE_TOOLCHAIN_FILE=$(HOST_DIR)/share/buildroot/toolchainfile.cmake \
	LIBCLANG_PATH=$(HOST_DIR)/lib \
	BINDGEN_EXTRA_CLANG_ARGS="--target=$(GNU_TARGET_NAME) --sysroot=$(STAGING_DIR)"

define AAW_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 \
		$(@D)/target/$(RUSTC_TARGET_NAME)/release/aaw \
		$(TARGET_DIR)/usr/bin/aaw
endef

define AAW_USERS
	aaw -1 aaw -1 * /var/lib/aaw - audio,pipewire AAW daemon
endef

define AAW_INSTALL_INIT_SYSTEMD
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_AAW_PATH)/package/aaw/aaw.service \
		$(TARGET_DIR)/usr/lib/systemd/system/aaw.service
endef

$(eval $(cargo-package))

