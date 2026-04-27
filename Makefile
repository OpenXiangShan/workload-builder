all: workloads

DEFAULT_DTB ?= xiangshan

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
$(GCPT_BIN): scripts/build-gcpt.sh $(TOOLCHAIN_WRAPPER)
	CROSS_COMPILE="$(abspath $(BUILDROOT_DIR)/output/host/bin)/riscv64-linux-" bash scripts/build-gcpt.sh bootloader/LibCheckpointAlpha $(GCPT_BUILD_DIR)

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
build/linux-workloads/$(1)/rootfs.cpio: $$(shell find $$(abspath workloads/linux/$(1))) $(TOOLCHAIN_WRAPPER) build/linux-workloads/$(1)/download/sentinel scripts/build-workload-linux.sh
	CROSS_COMPILE="$$(abspath $(BUILDROOT_DIR)/output/host/bin)/riscv64-linux-" \
	SYSROOT_DIR="$$(abspath $(BUILDROOT_DIR)/output/staging)" \
	BUILDROOT_DIR="$$(abspath $(BUILDROOT_DIR))" \
	bash scripts/build-workload-linux.sh workloads/linux/$(1) build/linux-workloads/$(1)

# Build all-in-one firmware
build/linux-workloads/$(1)/fw_payload.bin: $$(shell find $$(abspath dts)) $(GCPT_BIN) dts/xiangshan.dts.in scripts/build-sbi.sh scripts/build-firmware-linux.sh build/linux-workloads/$(1)/rootfs.cpio $(LINUX_IMAGE) build/opensbi/build/platform/generic/firmware/fw_jump.bin
	CROSS_COMPILE="$$(abspath $(BUILDROOT_DIR)/output/host/bin)/riscv64-linux-" \
	DTC="$$(abspath $(BUILDROOT_DIR)/output/host/bin)/dtc" \
	DEFAULT_DTB="$(DEFAULT_DTB)" \
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

# Define all workloads
$(eval $(call add_workload_linux,hello))
$(eval $(call add_workload_linux,rvv-bench))
$(eval $(call add_workload_linux,coremark))
$(eval $(call add_workload_linux,coremark-pro))
$(eval $(call add_workload_linux,kvmtool))
$(eval $(call add_workload_linux,litmus-tests-riscv))
$(eval $(call add_workload_am,riscv-tests))
$(eval $(call add_workload_am,riscv-vector-tests))
$(eval $(call add_workload_am,cputest))
$(eval $(call add_workload_am,misc-tests))
$(eval $(call add_workload_am,hello))
$(eval $(call add_workload_am,coremark))

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
