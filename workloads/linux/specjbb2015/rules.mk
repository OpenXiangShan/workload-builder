SPECJBB2015_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SPECJBB2015_BUILD_DIR := build/linux-workloads/specjbb2015
SPECJBB2015_MULTIHART ?= $(MULTIHART)
SPECJBB2015_HARTS ?= $(if $(HARTS),$(HARTS),2)
SPECJBB2015_DEFAULT_DTB ?= $(DEFAULT_DTB)

ifeq ($(filter 1,$(SPECJBB2015_MULTIHART)),1)
ifeq ($(strip $(SPECJBB2015_DEFAULT_DTB)),)
$(error DEFAULT_DTB is required for SPECjbb multi-hart builds)
endif
endif

SPECJBB2015_ROOTFS_HASH := $(shell printf '%s\n' 'harts=$(SPECJBB2015_HARTS)' 'xms=$(SPECJBB_JVM_XMS)' 'xmx=$(SPECJBB_JVM_XMX)' 'mode=$(SPECJBB_MODE)' | sha256sum | cut -d ' ' -f 1)
SPECJBB2015_ROOTFS_STAMP := $(SPECJBB2015_BUILD_DIR)/rootfs-vars.$(SPECJBB2015_ROOTFS_HASH).stamp

.PHONY: specjbb2015-check-inputs
specjbb2015-check-inputs:
	@if [ -z "$(SPECJBB_INPUT)" ] || ! [ -e "$(SPECJBB_INPUT)" ]; then echo "SPECJBB_INPUT must point to licensed SPECjbb2015 media"; exit 1; fi
	@if [ -z "$(SPECJBB_RV_JDK_INPUT)" ] || ! [ -e "$(SPECJBB_RV_JDK_INPUT)" ]; then echo "SPECJBB_RV_JDK_INPUT must point to an RV64 JDK"; exit 1; fi

$(SPECJBB2015_BUILD_DIR)/download/sentinel:
	@mkdir -p "$(@D)"
	@touch "$@"

$(SPECJBB2015_ROOTFS_STAMP):
	@mkdir -p "$(@D)"
	@rm -f "$(@D)"/rootfs-vars.*.stamp
	@touch "$@"

$(SPECJBB2015_BUILD_DIR)/rootfs.cpio: $(shell find $(SPECJBB2015_DIR)) $(TOOLCHAIN_WRAPPER) scripts/build-workload-linux.sh $(SPECJBB2015_BUILD_DIR)/download/sentinel $(SPECJBB2015_ROOTFS_STAMP) | specjbb2015-check-inputs
	@CROSS_COMPILE="$(abspath $(BUILDROOT_DIR)/output/host/bin)/riscv64-linux-" \
	  SPECJBB_INPUT="$(SPECJBB_INPUT)" SPECJBB_RV_JDK_INPUT="$(SPECJBB_RV_JDK_INPUT)" \
	  SPECJBB_JVM_XMS="$(SPECJBB_JVM_XMS)" SPECJBB_JVM_XMX="$(SPECJBB_JVM_XMX)" SPECJBB_MODE="$(SPECJBB_MODE)" \
	  HARTS="$(SPECJBB2015_HARTS)" MULTIHART=0 \
	  bash scripts/build-workload-linux.sh workloads/linux/specjbb2015 $(SPECJBB2015_BUILD_DIR)

$(SPECJBB2015_BUILD_DIR)/fw_payload.bin: $(shell find $(abspath dts)) $(GCPT_BIN) scripts/build-firmware-linux.sh $(SPECJBB2015_BUILD_DIR)/rootfs.cpio $(LINUX_IMAGE) $(SBI_BIN)
	@CROSS_COMPILE="$(abspath $(BUILDROOT_DIR)/output/host/bin)/riscv64-linux-" \
	  DTC="$(abspath $(BUILDROOT_DIR)/output/host/bin)/dtc" DEFAULT_DTB="$(SPECJBB2015_DEFAULT_DTB)" \
	  MULTIHART="$(SPECJBB2015_MULTIHART)" HARTS="$(SPECJBB2015_HARTS)" \
	  bash scripts/build-firmware-linux.sh $(GCPT_BIN) $(SBI_BUILD_DIR) dts $(LINUX_IMAGE) $(SPECJBB2015_BUILD_DIR)

linux/specjbb2015: $(SPECJBB2015_BUILD_DIR)/fw_payload.bin
WORKLOAD_PHONY_TARGETS += linux/specjbb2015
WORKLOAD_DIRS += $(SPECJBB2015_BUILD_DIR)
