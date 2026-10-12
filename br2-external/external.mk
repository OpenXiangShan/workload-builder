include $(BR2_EXTERNAL_NEMU_PATH)/package/nemu-trap/nemu-trap.mk
include $(BR2_EXTERNAL_NEMU_PATH)/package/nemu-exec/nemu-exec.mk

ifeq ($(BR2_PACKAGE_QEMU_SYSTEM_KVM),y)
QEMU_OPTS += --enable-kvm-m-mode --enable-kvm-nested
endif
