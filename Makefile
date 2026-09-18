all: workloads

MULTIHART ?= 0
PLATFORM ?= $(if $(filter 1,$(MULTIHART)),qemu,nemu)
HARTS ?= 2
VIRTUALIZATION ?= 0
QEMU_DEFAULT_DTB ?= xiangshan-qemu-nemu-mem2g
DTS_ISA_CONFIG ?= kunminghu-v3
DTS_DIR := build/generated-dts
export DTS_ISA_CONFIG

ifeq ($(filter $(PLATFORM),nemu qemu),)
$(error PLATFORM must be either nemu or qemu)
endif
ifneq ($(filter-out 0 1,$(VIRTUALIZATION)),)
$(error VIRTUALIZATION must be 0 or 1)
endif
ifeq ($(filter 1,$(VIRTUALIZATION)),1)
ifneq ($(filter 1,$(MULTIHART)),)
$(error VIRTUALIZATION=1 does not accept MULTIHART=1; use VIRT_GUEST_HARTS)
endif
endif
ifeq ($(filter $(DTS_ISA_CONFIG),kunminghu-v2 kunminghu-v3),)
$(error DTS_ISA_CONFIG must be either kunminghu-v2 or kunminghu-v3)
endif
ifeq ($(filter 1,$(MULTIHART)),1)
ifneq ($(PLATFORM),qemu)
$(error MULTIHART=1 requires PLATFORM=qemu)
endif
endif

LINUX_DEFAULT_DTB := $(if $(DEFAULT_DTB),$(DEFAULT_DTB),$(if $(filter 1,$(MULTIHART)),,$(if $(filter qemu,$(PLATFORM)),$(QEMU_DEFAULT_DTB),)))
LINUX_FIRMWARE_FILENAME := $(if $(filter qemu,$(PLATFORM)),fw_payload.qemu.bin,fw_payload.bin)
LINUX_ROOTFS_BUILD_VARS_HASH := $(shell printf '%s\n' \
	'multihart=$(if $(filter 1,$(MULTIHART)),1,0)' \
	'harts=$(if $(filter 1,$(MULTIHART)),$(HARTS),1)' \
	'virtualization=$(VIRTUALIZATION)' | sha256sum | cut -d ' ' -f 1)
LINUX_FIRMWARE_BUILD_VARS_HASH := $(shell printf '%s\n' \
	'multihart=$(if $(filter 1,$(MULTIHART)),1,0)' \
	'harts=$(if $(filter 1,$(MULTIHART)),$(HARTS),1)' \
	'default_dtb=$(if $(LINUX_DEFAULT_DTB),$(LINUX_DEFAULT_DTB),xiangshan)' \
	'dts_isa_config=$(DTS_ISA_CONFIG)' | sha256sum | cut -d ' ' -f 1)

MULTIHART_SUPPORTED_HARTS = $(shell seq 2 128)
ifeq ($(filter 1,$(MULTIHART)),1)
ifeq ($(filter $(HARTS),$(MULTIHART_SUPPORTED_HARTS)),)
$(error HARTS must be an integer in the range 2..128 when MULTIHART=1)
endif
ifeq ($(strip $(DEFAULT_DTB)),)
$(error DEFAULT_DTB must be specified when MULTIHART=1; use the complete DTS basename without .dts.in)
endif
endif

# Download buildroot
#
# BUILDROOT_VERSION is the single place this is pinned. CI derives its cache key
# from it through the print-buildroot-version target, so a bump here is enough.
BUILDROOT_VERSION := 2026.08
BUILDROOT_DIR := build/buildroot
$(BUILDROOT_DIR)/Makefile:
	mkdir -p build
	wget https://buildroot.org/downloads/buildroot-$(BUILDROOT_VERSION).tar.gz -O build/buildroot.tar.gz
	tar -xf build/buildroot.tar.gz -C build
	mv build/buildroot-$(BUILDROOT_VERSION) $(BUILDROOT_DIR)

print-buildroot-version:
	@echo $(BUILDROOT_VERSION)

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

ifeq ($(VIRTUALIZATION),1)
VIRT_ROOT := build/virt-linux-workloads
VIRT_GUEST_HARTS ?= 1
VIRT_GUEST_MEMORY ?= 8G
VIRT_QEMU_START_TIMEOUT ?= 120
VIRT_INNER_QEMU_VERSION := 11.0.0
VIRT_HOST_BUILDROOT_DIR ?= build/buildroot-virt-host
VIRT_HOST_CONFIG := $(VIRT_HOST_BUILDROOT_DIR)/.config
VIRT_HOST_DEFCONFIG := br2-external/configs/nemu_virt_host_defconfig
VIRT_HOST_LINUX_CONFIG := br2-external/board/openxiangshan/nemu/linux-virt-host.config
ifeq ($(filter qemu,$(PLATFORM)),qemu)
VIRT_HOST_DTB ?= xiangshan-qemu-nemu-mem16g
VIRT_OUTER_QEMU_ARGS := --outer-qemu-machine nemu --outer-qemu-cpu rv64,h=true,sstc=false --outer-qemu-harts 1 --outer-qemu-memory 16G
else
VIRT_HOST_DTB ?= xiangshan-fpga-noAIA-mem16g-novec
VIRT_OUTER_QEMU_ARGS :=
endif
VIRT_HOST_FIRMWARE := $(LINUX_FIRMWARE_FILENAME)
VIRT_HOST_MIN_MEMORY_BYTES ?= 17179869184
VIRT_HOST_BUILD_STAMP := $(VIRT_HOST_BUILDROOT_DIR)/.build-complete.stamp
VIRT_HOST_IMAGE := $(VIRT_HOST_BUILDROOT_DIR)/images/Image
VIRT_HOST_ROOTFS := $(VIRT_HOST_BUILDROOT_DIR)/images/rootfs.cpio
VIRT_HOST_QEMU := $(VIRT_HOST_BUILDROOT_DIR)/target/usr/bin/qemu-system-riscv64
VIRT_FAKEROOT := $(BUILDROOT_DIR)/output/host/bin/fakeroot
VIRT_SBI_FDT_ADDR := 0x80200000
VIRT_GCPT_BUILD_DIR := build/LibCheckpointAlpha-virt
VIRT_GCPT_BIN := $(VIRT_GCPT_BUILD_DIR)/build/gcpt.bin
VIRT_GCPT_PATCH := bootloader/LibCheckpointAlpha-virt-fdt.patch
VIRT_GCPT_SOURCES := $(shell find bootloader/LibCheckpointAlpha -path '*/.git' -prune -o -type f -print 2>/dev/null)
VIRT_GCPT_DTS_SOURCES := dts/generate-nemu-board-dts.py dts/DTSGen.py dts/workload-builder-profiles.json
VIRT_GCPT_CONFIG_STAMP := build/LibCheckpointAlpha-virt-config/config.$(shell printf '%s\n' '$(VIRT_HOST_DTB)' '$(VIRT_SBI_FDT_ADDR)' | sha256sum | cut -d ' ' -f 1)
VIRT_BUILD_VARS_CONTENT := platform=$(PLATFORM)\nguest_harts=$(VIRT_GUEST_HARTS)\nguest_memory=$(VIRT_GUEST_MEMORY)\nqemu_start_timeout=$(VIRT_QEMU_START_TIMEOUT)\ninner_qemu_version=$(VIRT_INNER_QEMU_VERSION)\nhost_dtb=$(VIRT_HOST_DTB)\nhost_min_memory=$(VIRT_HOST_MIN_MEMORY_BYTES)
VIRT_BUILD_VARS_HASH := $(shell printf '%b' '$(VIRT_BUILD_VARS_CONTENT)' | sha256sum | cut -d ' ' -f 1)

$(VIRT_HOST_CONFIG): $(BUILDROOT_DIR)/Makefile $(VIRT_HOST_DEFCONFIG) $(VIRT_HOST_LINUX_CONFIG)
	mkdir -p "$(VIRT_HOST_BUILDROOT_DIR)"
	@if test -f "$@"; then $(MAKE) -C $(BUILDROOT_DIR) O=$(abspath $(VIRT_HOST_BUILDROOT_DIR)) BR2_EXTERNAL=$(abspath br2-external) linux-dirclean qemu-dirclean; fi
	$(MAKE) -C $(BUILDROOT_DIR) O=$(abspath $(VIRT_HOST_BUILDROOT_DIR)) BR2_EXTERNAL=$(abspath br2-external) nemu_virt_host_defconfig

$(VIRT_HOST_BUILD_STAMP): $(VIRT_HOST_CONFIG) $(VIRT_HOST_DEFCONFIG) $(VIRT_HOST_LINUX_CONFIG)
	$(MAKE) -C $(BUILDROOT_DIR) O=$(abspath $(VIRT_HOST_BUILDROOT_DIR)) BR2_EXTERNAL=$(abspath br2-external)
	test -s "$(VIRT_HOST_IMAGE)"
	test -s "$(VIRT_HOST_ROOTFS)"
	test -x "$(VIRT_HOST_QEMU)"
	@test -n "$$(find "$(VIRT_HOST_BUILDROOT_DIR)/build" -maxdepth 1 -type d -name 'qemu-*' -print -quit)"
	@host_kernel_config="$$(find "$(VIRT_HOST_BUILDROOT_DIR)/build" -path '*/linux-*/.config' -print -quit)"; test -n "$$host_kernel_config"; grep -qx 'CONFIG_VIRTUALIZATION=y' "$$host_kernel_config"; grep -qx 'CONFIG_KVM=y' "$$host_kernel_config"
	touch "$@"

$(VIRT_GCPT_CONFIG_STAMP):
	mkdir -p "$(@D)"
	rm -f "$(@D)"/config.*
	touch "$@"

$(VIRT_GCPT_BIN): scripts/build-gcpt.sh scripts/dts-config.sh $(VIRT_GCPT_PATCH) $(TOOLCHAIN_WRAPPER) $(VIRT_GCPT_CONFIG_STAMP) $(VIRT_GCPT_SOURCES) $(VIRT_GCPT_DTS_SOURCES)
	CROSS_COMPILE="$(abspath $(BUILDROOT_DIR)/output/host/bin)/riscv64-linux-" GCPT_IMPLEMENTATION=alpha DEFAULT_DTB="$(VIRT_HOST_DTB)" GCPT_SOURCE_PATCH="$(abspath $(VIRT_GCPT_PATCH))" GCPT_PAYLOAD_FDT_ADDR=$(VIRT_SBI_FDT_ADDR) DTS_TEMPLATE_DIR="$(abspath $(DTS_DIR))" bash scripts/build-gcpt.sh bootloader/LibCheckpointAlpha $(VIRT_GCPT_BUILD_DIR)

define add_virtual_linux_case
VIRT_$(subst -,_,$(1))_DIR := $(VIRT_ROOT)/$(3)
VIRT_$(subst -,_,$(1))_VARS := $$(VIRT_$(subst -,_,$(1))_DIR)/vars.$(VIRT_BUILD_VARS_HASH).stamp
VIRT_$(subst -,_,$(1))_PACKAGE := $$(VIRT_$(subst -,_,$(1))_DIR)/package.stamp
VIRT_$(subst -,_,$(1))_FINAL := $$(VIRT_$(subst -,_,$(1))_DIR)/complete.stamp

$$(VIRT_$(subst -,_,$(1))_VARS):
	@mkdir -p "$$(@D)"; rm -f "$$(@D)"/vars.*.stamp; printf '%b\n' '$(VIRT_BUILD_VARS_CONTENT)' > "$$@"

$$(VIRT_$(subst -,_,$(1))_PACKAGE): $(2) $(VIRT_HOST_BUILD_STAMP) $(LINUX_IMAGE) $$(VIRT_$(subst -,_,$(1))_VARS) scripts/build-virtual-workload.py
	@$(VIRT_FAKEROOT) -- python3 scripts/build-virtual-workload.py package --guest-rootfs "$(2)" --host-rootfs "$(VIRT_HOST_ROOTFS)" --guest-image "$(LINUX_IMAGE)" --host-image "$(VIRT_HOST_IMAGE)" --guest-buildroot-output "$(BUILDROOT_DIR)/output" --host-buildroot-output "$(VIRT_HOST_BUILDROOT_DIR)" --out-dir "$$(VIRT_$(subst -,_,$(1))_DIR)" --guest-harts "$(VIRT_GUEST_HARTS)" --guest-memory "$(VIRT_GUEST_MEMORY)" --qemu-start-timeout "$(VIRT_QEMU_START_TIMEOUT)"
	@touch "$$@"

$$(VIRT_$(subst -,_,$(1))_DIR)/host/$(VIRT_HOST_FIRMWARE): $$(VIRT_$(subst -,_,$(1))_PACKAGE) $(VIRT_GCPT_BIN) $(SBI_BIN) $(VIRT_GCPT_DTS_SOURCES) scripts/build-firmware-linux.sh scripts/dts-config.sh
	@CROSS_COMPILE="$(abspath $(BUILDROOT_DIR)/output/host/bin)/riscv64-linux-" DTC="$(abspath $(BUILDROOT_DIR)/output/host/bin/dtc)" DEFAULT_DTB="$(VIRT_HOST_DTB)" DTB_MIN_MEMORY_BYTES="$(VIRT_HOST_MIN_MEMORY_BYTES)" INITRAMFS_OFFSET_ALIGNMENT_MB=2 MULTIHART=0 HARTS=1 FIRMWARE_OUTPUT="$$@" bash scripts/build-firmware-linux.sh "$(VIRT_GCPT_BIN)" "$(SBI_BUILD_DIR)" "$(DTS_DIR)" "$$(VIRT_$(subst -,_,$(1))_DIR)/host/Image" "$$(VIRT_$(subst -,_,$(1))_DIR)/host"

$$(VIRT_$(subst -,_,$(1))_DIR)/manifest.json: $$(VIRT_$(subst -,_,$(1))_PACKAGE) $$(VIRT_$(subst -,_,$(1))_DIR)/host/$(VIRT_HOST_FIRMWARE) scripts/build-virtual-workload.py
	@$(VIRT_FAKEROOT) -- python3 scripts/build-virtual-workload.py manifest --out-dir "$$(VIRT_$(subst -,_,$(1))_DIR)" --workload-name "$(3)" --platform "$(PLATFORM)" --guest-harts "$(VIRT_GUEST_HARTS)" --guest-memory "$(VIRT_GUEST_MEMORY)" --qemu-start-timeout "$(VIRT_QEMU_START_TIMEOUT)" --inner-qemu-version "$(VIRT_INNER_QEMU_VERSION)" --host-dtb "$(VIRT_HOST_DTB)" --host-min-memory-bytes "$(VIRT_HOST_MIN_MEMORY_BYTES)" $(VIRT_OUTER_QEMU_ARGS) --gcpt "$(VIRT_GCPT_BIN)" --opensbi "$(SBI_BIN)" --host-linux-revision "buildroot-selected" --opensbi-source bootloader/opensbi --opensbi-revision "$(shell git -C bootloader/opensbi rev-parse HEAD 2>/dev/null || printf unknown)" --host-defconfig "$(VIRT_HOST_DEFCONFIG)" --host-linux-config "$(VIRT_HOST_LINUX_CONFIG)" --guest-buildroot-output "$(BUILDROOT_DIR)/output" --host-buildroot-output "$(VIRT_HOST_BUILDROOT_DIR)" --buildroot-source "$(BUILDROOT_DIR)"

$$(VIRT_$(subst -,_,$(1))_FINAL): $$(VIRT_$(subst -,_,$(1))_DIR)/manifest.json
	@touch "$$@"

linux/$(1): $$(VIRT_$(subst -,_,$(1))_FINAL)
WORKLOAD_DIRS += $$(VIRT_$(subst -,_,$(1))_DIR)
endef
endif

# Build GCPT. Single-core firmware keeps LibCheckpointAlpha; LibCheckpoint is
# used for the QEMU multi-hart checkpoint format.
SBI_BUILD_DIR := $(if $(filter 1,$(MULTIHART)),build/opensbi-multihart,build/opensbi)
SBI_BIN := $(SBI_BUILD_DIR)/build/platform/generic/firmware/fw_jump.bin

GCPT_IMPLEMENTATION := $(if $(filter 1,$(MULTIHART)),libcheckpoint,alpha)
GCPT_SOURCE_DIR := $(if $(filter 1,$(MULTIHART)),bootloader/LibCheckpoint,bootloader/LibCheckpointAlpha)
GCPT_BUILD_DIR := $(if $(filter 1,$(MULTIHART)),build/LibCheckpoint,build/LibCheckpointAlpha)
GCPT_BIN := $(GCPT_BUILD_DIR)/build/gcpt.bin
GCPT_DEFAULT_DTB ?= $(if $(DEFAULT_DTB),$(DEFAULT_DTB),$(if $(filter qemu,$(PLATFORM)),$(QEMU_DEFAULT_DTB),xiangshan))
GCPT_CONFIGURE_MODE := $(if $(filter 1,$(MULTIHART)),dual_core,normal)
GCPT_SERIAL_PORT ?= $(if $(filter 1,$(MULTIHART)),0x310b0000,)
GCPT_DTB_CONFIG_HASH := $(shell printf '%s\n' "$(GCPT_DEFAULT_DTB)" | sha256sum | cut -d ' ' -f 1)
GCPT_CONFIG_STAMP := $(if $(filter 1,$(MULTIHART)),build/LibCheckpoint-config/mode.$(GCPT_CONFIGURE_MODE).serial-port.$(GCPT_SERIAL_PORT),build/LibCheckpointAlpha-config/dtb.$(GCPT_DTB_CONFIG_HASH))
GCPT_SOURCES := $(if $(filter 1,$(MULTIHART)),$(shell find $(GCPT_SOURCE_DIR) -path '*/.git' -prune -o -path '*/tests' -prune -o -type f -print 2>/dev/null),$(shell find $(GCPT_SOURCE_DIR) -path '*/.git' -prune -o -type f -print 2>/dev/null))
GCPT_DTS_SOURCES := dts/generate-nemu-board-dts.py dts/generate-workload-builder-dts.py \
	dts/DTSGen.py dts/workload-builder-profiles.json \
	$(wildcard dts/$(GCPT_DEFAULT_DTB).dts.in)
$(GCPT_CONFIG_STAMP):
	mkdir -p "$(@D)"
	rm -f $(if $(filter 1,$(MULTIHART)),build/LibCheckpoint-config/mode.*,build/LibCheckpointAlpha-config/dtb.*)
	touch "$@"
$(GCPT_BIN): scripts/build-gcpt.sh scripts/dts-config.sh $(TOOLCHAIN_WRAPPER) $(GCPT_SOURCES) $(GCPT_DTS_SOURCES) $(GCPT_CONFIG_STAMP) $(if $(filter 1,$(MULTIHART)),$(SBI_BIN),)
	CROSS_COMPILE="$(abspath $(BUILDROOT_DIR)/output/host/bin)/riscv64-linux-" \
	GCPT_IMPLEMENTATION="$(GCPT_IMPLEMENTATION)" \
	GCPT_CONFIGURE_MODE="$(GCPT_CONFIGURE_MODE)" \
	GCPT_PAYLOAD_PATH="$(if $(filter 1,$(MULTIHART)),$(abspath $(SBI_BIN)),)" \
	GCPT_SERIAL_PORT="$(GCPT_SERIAL_PORT)" \
	DEFAULT_DTB="$(GCPT_DEFAULT_DTB)" \
	DTS_TEMPLATE_DIR="$(abspath $(DTS_DIR))" \
	bash scripts/build-gcpt.sh $(GCPT_SOURCE_DIR) $(GCPT_BUILD_DIR)

# Build OpenSBI
SBI_CONFIG_STAMP := $(SBI_BUILD_DIR)-config/$(if $(filter 1,$(MULTIHART)),multihart-fixed,dtb.$(GCPT_DTB_CONFIG_HASH))
$(SBI_CONFIG_STAMP):
	mkdir -p "$(@D)"
	rm -f "$(@D)"/dtb.* "$(@D)"/multihart-fixed
	touch "$@"
$(SBI_BIN): scripts/build-sbi.sh scripts/dts-config.sh $(GCPT_DTS_SOURCES) bootloader/opensbi.config $(TOOLCHAIN_WRAPPER) $(SBI_CONFIG_STAMP)
	CROSS_COMPILE="$(abspath $(BUILDROOT_DIR)/output/host/bin)/riscv64-linux-" \
	MULTIHART="$(MULTIHART)" \
	DEFAULT_DTB="$(GCPT_DEFAULT_DTB)" \
	DTS_TEMPLATE_DIR="$(abspath $(DTS_DIR))" \
	bash scripts/build-sbi.sh bootloader/opensbi $(SBI_BUILD_DIR)

define add_workload_linux
# Download files
build/linux-workloads/$(1)/download/sentinel: $$(shell find $$(abspath workloads/linux/$(1)) -iname 'links.txt')
	mkdir -p build/linux-workloads/$(1)/
	bash scripts/download-files.sh workloads/linux/$(1) build/linux-workloads/$(1)/download

# Build and pack workload
build/linux-workloads/$(1)/rootfs-vars.$(LINUX_ROOTFS_BUILD_VARS_HASH).stamp:
	mkdir -p "$$(@D)"
	rm -f "$$(@D)"/rootfs-vars.*.stamp
	touch "$$@"

build/linux-workloads/$(1)/rootfs.cpio: $$(shell find $$(abspath workloads/linux/$(1))) $(TOOLCHAIN_WRAPPER) build/linux-workloads/$(1)/download/sentinel scripts/build-workload-linux.sh scripts/package-multihart-rootfs.py build/linux-workloads/$(1)/rootfs-vars.$(LINUX_ROOTFS_BUILD_VARS_HASH).stamp
	CROSS_COMPILE="$$(abspath $(BUILDROOT_DIR)/output/host/bin)/riscv64-linux-" \
	SYSROOT_DIR="$$(abspath $(BUILDROOT_DIR)/output/staging)" \
	BUILDROOT_DIR="$$(abspath $(BUILDROOT_DIR))" \
	MULTIHART="$$(MULTIHART)" \
	HARTS="$$(HARTS)" \
	VIRTUALIZATION="$$(VIRTUALIZATION)" \
	bash scripts/build-workload-linux.sh workloads/linux/$(1) build/linux-workloads/$(1)

# Build all-in-one firmware
build/linux-workloads/$(1)/firmware-vars.$(LINUX_FIRMWARE_BUILD_VARS_HASH).stamp:
	mkdir -p "$$(@D)"
	rm -f "$$(@D)"/firmware-vars.*.stamp
	touch "$$@"

build/linux-workloads/$(1)/$(LINUX_FIRMWARE_FILENAME): $(GCPT_DTS_SOURCES) $(GCPT_BIN) scripts/build-sbi.sh scripts/dts-config.sh scripts/build-firmware-linux.sh build/linux-workloads/$(1)/rootfs.cpio $(LINUX_IMAGE) $(SBI_BIN) build/linux-workloads/$(1)/firmware-vars.$(LINUX_FIRMWARE_BUILD_VARS_HASH).stamp
	CROSS_COMPILE="$$(abspath $(BUILDROOT_DIR)/output/host/bin)/riscv64-linux-" \
	DTC="$$(abspath $(BUILDROOT_DIR)/output/host/bin)/dtc" \
	DEFAULT_DTB="$(LINUX_DEFAULT_DTB)" \
	FIRMWARE_OUTPUT="$$(abspath $$@)" \
	MULTIHART="$$(MULTIHART)" \
	HARTS="$$(HARTS)" \
	bash scripts/build-firmware-linux.sh $(GCPT_BIN) $(SBI_BUILD_DIR) $(DTS_DIR) $(LINUX_IMAGE) build/linux-workloads/$(1)

linux/$(1): $(if $(filter 1,$(VIRTUALIZATION)),,build/linux-workloads/$(1)/$(LINUX_FIRMWARE_FILENAME))

WORKLOAD_PHONY_TARGETS += linux/$(1)
WORKLOAD_DIRS += build/linux-workloads/$(1)
WORKLOADS_LINUX += build/linux-workloads/$(1)/$(LINUX_FIRMWARE_FILENAME)
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
# QEMU support covers the Linux workloads with QEMU-compatible firmware flows.
# VIRTUALIZATION=1 builds no DTB-based firmware, so it does not depend on that
# list and keeps every Linux workload available on both simulators.
QEMU_SUPPORTED_LINUX_WORKLOADS := coremark spec2006 spec2017
LINUX_QEMU_SUPPORTED_ONLY := $(if $(filter 1,$(VIRTUALIZATION)),,$(filter qemu,$(PLATFORM)))
LINUX_ENABLED_GENERIC_WORKLOADS := $(if $(LINUX_QEMU_SUPPORTED_ONLY),$(filter $(QEMU_SUPPORTED_LINUX_WORKLOADS),$(LINUX_GENERIC_WORKLOADS)),$(LINUX_GENERIC_WORKLOADS))
LINUX_WORKLOAD_RULE_FILES := $(if $(LINUX_QEMU_SUPPORTED_ONLY),$(wildcard $(foreach workload,$(QEMU_SUPPORTED_LINUX_WORKLOADS),workloads/linux/$(workload)/rules.mk)),$(wildcard workloads/linux/*/rules.mk))

$(foreach workload,$(LINUX_ENABLED_GENERIC_WORKLOADS),$(eval $(call add_workload_linux,$(workload))))
$(foreach workload,$(AM_GENERIC_WORKLOADS),$(eval $(call add_workload_am,$(workload))))

# Include workload-specific make rules. A workload can add its own targets by
# placing rules.mk under its workload directory.
-include $(LINUX_WORKLOAD_RULE_FILES)
-include $(wildcard workloads/am/*/rules.mk)

ifeq ($(VIRTUALIZATION),1)
# Each virtual case redefines the workload's usual `linux/<name>` target, which
# is where a workload's own rules expect the build dependency to live.
VIRT_GENERIC_WORKLOADS := $(LINUX_GENERIC_WORKLOADS)
$(foreach workload,$(VIRT_GENERIC_WORKLOADS),$(eval $(call add_virtual_linux_case,$(workload),build/linux-workloads/$(workload)/rootfs.cpio,$(workload))))
VIRT_WORKLOADS_LINUX := $(foreach workload,$(VIRT_GENERIC_WORKLOADS),$(VIRT_$(subst -,_,$(workload))_FINAL))
ifneq ($(strip $(SPEC2006_ALL_CASES)),)
$(foreach case,$(SPEC2006_ALL_CASES),$(eval $(call add_virtual_linux_case,$(case),$(SPEC2006_BUILD_DIR)/$(case)/rootfs.cpio,$(case))))
endif
ifneq ($(strip $(SPEC2017_ALL_CASES)),)
$(foreach case,$(SPEC2017_ALL_CASES),$(eval $(call add_virtual_linux_case,$(case),$(SPEC2017_BUILD_DIR)/$(case)/rootfs.cpio,spec2017-$(case))))
endif
ifneq ($(strip $(SPEC2026_ALL_CASES)),)
$(foreach case,$(SPEC2026_ALL_CASES),$(eval $(call add_virtual_linux_case,$(case),$(SPEC2026_BUILD_DIR)/$(case)/rootfs.cpio,spec2026-$(case))))
endif
ifneq ($(strip $(GAPBS_ALL_CASES)),)
$(foreach case,$(GAPBS_ALL_CASES),$(eval $(call add_virtual_linux_case,gapbs-$(case),$(GAPBS_BUILD_DIR)/$(case)/rootfs.cpio,gapbs-$(case))))
endif
ifneq ($(strip $(ROCKSDB_CASES)),)
$(foreach case,$(ROCKSDB_CASES),$(eval $(call add_virtual_linux_case,rocksdb-$(case),$(ROCKSDB_BUILD_DIR)/$(case)/rootfs.cpio,rocksdb-$(case))))
endif
$(foreach workload,stress-ng specjbb2015 geekbench5 geekbench6,$(if $(wildcard workloads/linux/$(workload)/rules.mk),$(eval $(call add_virtual_linux_case,$(workload),build/linux-workloads/$(workload)/rootfs.cpio,$(workload)))))
endif

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

# Build all all-in-one firmware images, or their virtual counterparts
workloads: $(if $(filter 1,$(VIRTUALIZATION)),$(VIRT_WORKLOADS_LINUX),$(WORKLOADS_LINUX)) $(WORKLOADS_AM_SENTINEL)

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

.PHONY: all $(WORKLOAD_PHONY_TARGETS) init prepare-sdk source workloads rootfs tarball clean-kernel clean-workloads print-buildroot-version
