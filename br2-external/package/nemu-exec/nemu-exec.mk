NEMU_EXEC_VERSION = 0.0.1
NEMU_EXEC_SITE = $(BR2_EXTERNAL_NEMU_PATH)/package/nemu-exec
NEMU_EXEC_SITE_METHOD = local
NEMU_EXEC_INSTALL_STAGING = NO

define NEMU_EXEC_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) -DNEMU_EXEC_PROFILE=$(if $(BR2_PACKAGE_NEMU_EXEC_PROFILE),1,0) $(@D)/main.c $(@D)/trap.c -o $(@D)/nemu-exec
endef

define NEMU_EXEC_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/nemu-exec $(TARGET_DIR)/bin
endef

define NEMU_EXEC_PERMISSIONS
	/bin/nemu-exec f 4755 root root - - - - -
endef

$(eval $(generic-package))
