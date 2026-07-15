all: workloads

MULTIHART ?= 0
HARTS ?= 2
LINUX_MULTIHART_DEFAULT_DTB := xiangshan-fpga-noAIA-$(HARTS)hart-mem8g
LINUX_DEFAULT_DTB := $(if $(DEFAULT_DTB),$(DEFAULT_DTB),$(if $(filter 1,$(MULTIHART)),$(LINUX_MULTIHART_DEFAULT_DTB),))

# Download buildroot
BUILDROOT_DIR := build/buildroot
$(BUILDROOT_DIR)/Makefile:
	mkdir -p build
	wget https://buildroot.org/downloads/buildroot-2025.08.1.tar.gz -O build/buildroot.tar.gz
	tar -xf build/buildroot.tar.gz -C build
	mv build/buildroot-2025.08.1 $(BUILDROOT_DIR)

# Prepare buildroot SDK
TOOLCHAIN_WRAPPER := $(BUILDROOT_DIR)/output/host/bin/toolchain-wrapper
$(TOOLCHAIN_WRAPPER): br2-external/configs/nemu_defconfig $(BUILDROOT_DIR)/Makefile
	$(MAKE) -C $(BUILDROOT_DIR) BR2_EXTERNAL=$(abspath br2-external) nemu_defconfig
	$(MAKE) -C $(BUILDROOT_DIR) BR2_EXTERNAL=$(abspath br2-external) prepare-sdk
	touch $(TOOLCHAIN_WRAPPER)

# Build Linux kernel
LINUX_IMAGE := $(BUILDROOT_DIR)/output/images/Image
$(LINUX_IMAGE): $(TOOLCHAIN_WRAPPER) br2-external/configs/nemu_defconfig br2-external/board/openxiangshan/nemu/linux.config
	$(MAKE) -C $(BUILDROOT_DIR) BR2_EXTERNAL=$(abspath br2-external) nemu_defconfig
	$(MAKE) -C $(BUILDROOT_DIR) BR2_EXTERNAL=$(abspath br2-external)

# Build LibCheckpointAlpha
GCPT_BUILD_DIR := build/LibCheckpointAlpha
GCPT_BIN := $(GCPT_BUILD_DIR)/build/gcpt.bin
GCPT_DEFAULT_DTB ?= $(if $(DEFAULT_DTB),$(DEFAULT_DTB),$(if $(filter 1,$(MULTIHART)),$(LINUX_MULTIHART_DEFAULT_DTB),xiangshan))
GCPT_DEFAULT_DTB_STAMP := build/LibCheckpointAlpha-config/dtb.$(shell printf '%s\n' "$(GCPT_DEFAULT_DTB)" | sha256sum | cut -d ' ' -f 1)
GCPT_SOURCES := $(shell find bootloader/LibCheckpointAlpha -path '*/.git' -prune -o -type f -print 2>/dev/null)
GCPT_DTS_SOURCES := $(shell find dts -type f 2>/dev/null)
$(GCPT_DEFAULT_DTB_STAMP):
	mkdir -p "$(@D)"
	rm -f build/LibCheckpointAlpha-config/dtb.*
	touch "$@"
$(GCPT_BIN): scripts/build-gcpt.sh $(TOOLCHAIN_WRAPPER) $(GCPT_SOURCES) $(GCPT_DTS_SOURCES) $(GCPT_DEFAULT_DTB_STAMP)
	CROSS_COMPILE="$(abspath $(BUILDROOT_DIR)/output/host/bin)/riscv64-linux-" \
	DEFAULT_DTB="$(GCPT_DEFAULT_DTB)" \
	DTS_TEMPLATE_DIR="$(abspath dts)" \
	bash scripts/build-gcpt.sh bootloader/LibCheckpointAlpha $(GCPT_BUILD_DIR)

# Build OpenSBI
SBI_BUILD_DIR := build/opensbi
SBI_BIN := $(SBI_BUILD_DIR)/build/platform/generic/firmware/fw_jump.bin
$(SBI_BIN): scripts/build-sbi.sh bootloader/opensbi.config $(TOOLCHAIN_WRAPPER)
	CROSS_COMPILE="$(abspath $(BUILDROOT_DIR)/output/host/bin)/riscv64-linux-" bash scripts/build-sbi.sh bootloader/opensbi build/opensbi

define add_workload_linux
# Download files
build/linux-workloads/$(1)/download/sentinel: $$(shell find $$(abspath workloads/linux/$(1)) -iname 'links.txt')
	mkdir -p build/linux-workloads/$(1)/
	bash scripts/download-files.sh workloads/linux/$(1) build/linux-workloads/$(1)/download

# Build and pack workload
build/linux-workloads/$(1)/rootfs.cpio: $$(shell find $$(abspath workloads/linux/$(1))) $(TOOLCHAIN_WRAPPER) build/linux-workloads/$(1)/download/sentinel scripts/build-workload-linux.sh scripts/package-multihart-rootfs.py workloads/linux/common/before_workload.c workloads/linux/common/after_workload.c
	CROSS_COMPILE="$$(abspath $(BUILDROOT_DIR)/output/host/bin)/riscv64-linux-" \
	SYSROOT_DIR="$$(abspath $(BUILDROOT_DIR)/output/staging)" \
	BUILDROOT_DIR="$$(abspath $(BUILDROOT_DIR))" \
	MULTIHART="$$(MULTIHART)" \
	HARTS="$$(HARTS)" \
	bash scripts/build-workload-linux.sh workloads/linux/$(1) build/linux-workloads/$(1)

# Build all-in-one firmware
build/linux-workloads/$(1)/fw_payload.bin: $$(shell find $$(abspath dts)) $(GCPT_BIN) dts/xiangshan.dts.in scripts/build-sbi.sh scripts/build-firmware-linux.sh build/linux-workloads/$(1)/rootfs.cpio $(LINUX_IMAGE) build/opensbi/build/platform/generic/firmware/fw_jump.bin
	CROSS_COMPILE="$$(abspath $(BUILDROOT_DIR)/output/host/bin)/riscv64-linux-" \
	DTC="$$(abspath $(BUILDROOT_DIR)/output/host/bin)/dtc" \
	DEFAULT_DTB="$(LINUX_DEFAULT_DTB)" \
	bash scripts/build-firmware-linux.sh $(GCPT_BIN) build/opensbi dts $(LINUX_IMAGE) build/linux-workloads/$(1)

linux/$(1): build/linux-workloads/$(1)/fw_payload.bin

WORKLOAD_PHONY_TARGETS += linux/$(1)
WORKLOAD_DIRS += build/linux-workloads/$(1)
WORKLOADS_LINUX += build/linux-workloads/$(1)/fw_payload.bin
ROOTFS += build/linux-workloads/$(1)/rootfs.cpio
DT_DIRS += build/linux-workloads/$(1)/dt
TARFLAGS += --transform='s|^build/linux-workloads/$(1)|workloads/linux/$(1)|'
endef

define add_workload_am
# Download files
build/am-workloads/$(1)/download/sentinel: $$(shell find $$(abspath workloads/am/$(1)) -iname 'links.txt')
	mkdir -p build/am-workloads/$(1)/
	bash scripts/download-files.sh workloads/am/$(1) build/am-workloads/$(1)/download

# Build and pack workload
build/am-workloads/$(1)/sentinel: $$(shell find $$(abspath workloads/am/$(1))) $(TOOLCHAIN_WRAPPER) build/am-workloads/$(1)/download/sentinel scripts/build-workload-am.sh
	CROSS_COMPILE="$$(abspath $(BUILDROOT_DIR)/output/host/bin)/riscv64-linux-" \
	SYSROOT_DIR="$$(abspath $(BUILDROOT_DIR)/output/staging)" \
	ARCH="$(ARCH)" \
	CPPFLAGS="$(CPPFLAGS)" \
	bash scripts/build-workload-am.sh workloads/am/$(1) build/am-workloads/$(1) nexus-am

am/$(1): build/am-workloads/$(1)/sentinel

WORKLOAD_PHONY_TARGETS += am/$(1)
WORKLOAD_DIRS += build/am-workloads/$(1)
WORKLOADS_AM += build/am-workloads/$(1)/package
WORKLOADS_AM_SENTINEL += build/am-workloads/$(1)/sentinel
TARFLAGS += --transform='s|^build/am-workloads/$(1)/package|workloads/am/$(1)|'
endef

# Auto-register simple workloads. Workloads that need custom targets can place
# a rules.mk in their own directory and manage their rules there.
LINUX_WORKLOAD_RULE_DIRS := $(patsubst workloads/linux/%/rules.mk,%,$(wildcard workloads/linux/*/rules.mk))
AM_WORKLOAD_RULE_DIRS := $(patsubst workloads/am/%/rules.mk,%,$(wildcard workloads/am/*/rules.mk))
LINUX_WORKLOAD_DIRS := $(patsubst workloads/linux/%/build.sh,%,$(wildcard workloads/linux/*/build.sh))
AM_WORKLOAD_DIRS := $(patsubst workloads/am/%/build.sh,%,$(wildcard workloads/am/*/build.sh))
LINUX_GENERIC_WORKLOADS := $(sort $(filter-out $(LINUX_WORKLOAD_RULE_DIRS),$(LINUX_WORKLOAD_DIRS)))
AM_GENERIC_WORKLOADS := $(sort $(filter-out $(AM_WORKLOAD_RULE_DIRS),$(AM_WORKLOAD_DIRS)))

$(foreach workload,$(LINUX_GENERIC_WORKLOADS),$(eval $(call add_workload_linux,$(workload))))
$(foreach workload,$(AM_GENERIC_WORKLOADS),$(eval $(call add_workload_am,$(workload))))

# Include workload-specific make rules. A workload can add its own targets by
# placing rules.mk under its workload directory.
-include $(wildcard workloads/linux/*/rules.mk)
-include $(wildcard workloads/am/*/rules.mk)

# Pack all workloads
build/workloads.tar.zstd: $(WORKLOADS_LINUX) $(WORKLOADS_AM_SENTINEL)
	tar -c $(WORKLOADS_LINUX) $(ROOTFS) $(DT_DIRS) $(WORKLOADS_AM) $(TARFLAGS) | zstd -f -3 -T0 -o build/workloads.tar.zstd

# PHONY targets

init:
	git submodule update --init --recursive

# Prepare buildroot toolchain
prepare-sdk: $(TOOLCHAIN_WRAPPER)

# Download all source files needed by buildroot
source: $(BUILDROOT_DIR)/Makefile
	make -C $(BUILDROOT_DIR) BR2_EXTERNAL=$(abspath br2-external) nemu_defconfig
	make -C $(BUILDROOT_DIR) BR2_EXTERNAL=$(abspath br2-external) source

# Build all all-in-one firmware images
workloads: $(WORKLOADS_LINUX) $(WORKLOADS_AM_SENTINEL)

# Build all rootfs
rootfs: $(ROOTFS)

# Pack images and rootfs
tarball: build/workloads.tar.zstd

# Remove the buildroot outputs (toolchain, stageing files and output files for building the kernel)
clean-kernel:
	rm -rf $(BUILDROOT_DIR)/output

# Remove all built workloads
clean-workloads:
	rm -rf $(WORKLOAD_DIRS) build/workloads.tar.zstd build/rootfs.tar.zstd

.PHONY: all $(WORKLOAD_PHONY_TARGETS) init prepare-sdk source workloads rootfs tarball clean-kernel clean-workloads
