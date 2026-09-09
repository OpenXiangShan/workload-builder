ROCKSDB_WORKLOAD_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ROCKSDB_REPO_ROOT := $(abspath $(ROCKSDB_WORKLOAD_DIR)/../../..)
ROCKSDB_SCRIPTS_DIR := $(ROCKSDB_REPO_ROOT)/scripts
ROCKSDB_DTS_DIR := $(ROCKSDB_REPO_ROOT)/dts
ROCKSDB_BUILD_DIR ?= $(ROCKSDB_REPO_ROOT)/build/linux-workloads/rocksdb
ROCKSDB_IMAGE_DIR ?= $(ROCKSDB_REPO_ROOT)/build/images/rocksdb
ROCKSDB_CASES := readwhilewriting readrandomwriterandom updaterandom seekrandomwhilewriting randomtransaction timeseries mixgraph
ROCKSDB_KEYS ?= 1000000
ROCKSDB_OPS ?=
ROCKSDB_THREADS ?= 1
ROCKSDB_VALUE_SIZE ?= 100
# Follow the common Linux workload convention. Profiling remains enabled by
# default; set PROFILING=0 (or ROCKSDB_PROFILING=0) to omit the begin marker.
ROCKSDB_PROFILING ?= $(if $(PROFILING),$(PROFILING),1)
ROCKSDB_DEFAULT_OPS_readwhilewriting := 63440860
ROCKSDB_DEFAULT_OPS_readrandomwriterandom := 107547946
ROCKSDB_DEFAULT_OPS_updaterandom := 65537609
ROCKSDB_DEFAULT_OPS_seekrandomwhilewriting := 42514775
ROCKSDB_DEFAULT_OPS_randomtransaction := 9395846
ROCKSDB_DEFAULT_OPS_timeseries := 61688204
ROCKSDB_DEFAULT_OPS_mixgraph := 95868744
ROCKSDB_DEFAULT_DTB ?= $(if $(DEFAULT_DTB),$(DEFAULT_DTB),xiangshan-fpga-noAIA)
ROCKSDB_BUILDROOT_DIR ?= $(abspath $(if $(BUILDROOT_DIR),$(BUILDROOT_DIR),$(ROCKSDB_REPO_ROOT)/build/buildroot))
ROCKSDB_LINUX_IMAGE ?= $(abspath $(if $(LINUX_IMAGE),$(LINUX_IMAGE),$(ROCKSDB_BUILDROOT_DIR)/output/images/Image))
ROCKSDB_GCPT_BIN ?= $(abspath $(if $(GCPT_BIN),$(GCPT_BIN),$(ROCKSDB_REPO_ROOT)/build/LibCheckpointAlpha/build/gcpt.bin))
ROCKSDB_SBI_BUILD_DIR ?= $(abspath $(if $(SBI_BUILD_DIR),$(SBI_BUILD_DIR),$(ROCKSDB_REPO_ROOT)/build/opensbi))
ROCKSDB_SBI_BIN ?= $(abspath $(if $(SBI_BIN),$(SBI_BIN),$(ROCKSDB_SBI_BUILD_DIR)/build/platform/generic/firmware/fw_jump.bin))
ROCKSDB_CROSS_COMPILE ?= $(if $(CROSS_COMPILE),$(CROSS_COMPILE),riscv64-unknown-linux-gnu-)
ROCKSDB_SYSROOT_DIR ?=
ROCKSDB_MARCH ?= rva23u64
ROCKSDB_MABI ?= lp64d
ROCKSDB_OPT_FLAGS ?= -O3 -ftree-vectorize -ftree-loop-vectorize -ftree-slp-vectorize -mrvv-vector-bits=zvl
ROCKSDB_DTC ?= $(ROCKSDB_BUILDROOT_DIR)/output/host/bin/dtc
ROCKSDB_COMMON_STAMP := $(ROCKSDB_BUILD_DIR)/common.stamp
ROCKSDB_PACKAGE_HELPER := $(ROCKSDB_WORKLOAD_DIR)/package-case.sh
ROCKSDB_DTS_SOURCES := $(shell find $(ROCKSDB_DTS_DIR) -type f 2>/dev/null)
ROCKSDB_NON_COMMON_INPUTS := $(ROCKSDB_WORKLOAD_DIR)/README.md $(ROCKSDB_WORKLOAD_DIR)/links.txt $(ROCKSDB_WORKLOAD_DIR)/rules.mk $(ROCKSDB_PACKAGE_HELPER)
ROCKSDB_COMMON_INPUTS := $(filter-out $(ROCKSDB_NON_COMMON_INPUTS),$(shell find $(ROCKSDB_WORKLOAD_DIR) -type f 2>/dev/null))
ROCKSDB_CASE_FIRMWARE := $(foreach case,$(ROCKSDB_CASES),$(ROCKSDB_BUILD_DIR)/$(case)/fw_payload.bin)
ROCKSDB_COMPILER_ID := $(shell "$(ROCKSDB_CROSS_COMPILE)g++" --version 2>/dev/null | head -n 1)
ROCKSDB_BUILD_VARS_HASH := $(shell printf '%s\n' 'cross_compile=$(ROCKSDB_CROSS_COMPILE)' 'compiler=$(ROCKSDB_COMPILER_ID)' 'sysroot=$(ROCKSDB_SYSROOT_DIR)' 'march=$(ROCKSDB_MARCH)' 'mabi=$(ROCKSDB_MABI)' 'opt_flags=$(ROCKSDB_OPT_FLAGS)' | sha256sum | cut -d ' ' -f 1)
ROCKSDB_BUILD_VARS_STAMP := $(ROCKSDB_BUILD_DIR)/rocksdb-build-vars.$(ROCKSDB_BUILD_VARS_HASH).stamp
ROCKSDB_FIRMWARE_VARS_HASH := $(shell printf '%s\n' 'default_dtb=$(ROCKSDB_DEFAULT_DTB)' | sha256sum | cut -d ' ' -f 1)
ROCKSDB_FIRMWARE_VARS_STAMP := $(ROCKSDB_BUILD_DIR)/rocksdb-firmware-vars.$(ROCKSDB_FIRMWARE_VARS_HASH).stamp
rocksdb_case_ops = $(if $(strip $(ROCKSDB_OPS)),$(ROCKSDB_OPS),$(ROCKSDB_DEFAULT_OPS_$(1)))
rocksdb_case_threads = $(if $(filter timeseries,$(1)),2,$(ROCKSDB_THREADS))
rocksdb_run_vars_hash = $(shell printf '%s\n' 'keys=$(ROCKSDB_KEYS)' 'ops=$(call rocksdb_case_ops,$(1))' 'threads=$(call rocksdb_case_threads,$(1))' 'value_size=$(ROCKSDB_VALUE_SIZE)' 'profiling=$(ROCKSDB_PROFILING)' | sha256sum | cut -d ' ' -f 1)

ifeq ($(filter 0 1,$(ROCKSDB_PROFILING)),)
$(error ROCKSDB_PROFILING/PROFILING must be 0 or 1)
endif

WORKLOAD_DIRS += $(ROCKSDB_BUILD_DIR)

$(ROCKSDB_BUILD_DIR)/download/sentinel: $(ROCKSDB_WORKLOAD_DIR)/links.txt $(ROCKSDB_SCRIPTS_DIR)/download-files.sh
	@mkdir -p "$(@D)"
	@bash "$(ROCKSDB_SCRIPTS_DIR)/download-files.sh" "$(ROCKSDB_WORKLOAD_DIR)" "$(ROCKSDB_BUILD_DIR)/download"

$(ROCKSDB_BUILD_VARS_STAMP):
	@mkdir -p "$(@D)"
	@rm -f "$(@D)"/rocksdb-build-vars.*.stamp
	@touch "$@"

$(ROCKSDB_COMMON_STAMP): $(ROCKSDB_COMMON_INPUTS) $(ROCKSDB_BUILD_VARS_STAMP) $(ROCKSDB_BUILD_DIR)/download/sentinel $(ROCKSDB_SCRIPTS_DIR)/build-workload-linux.sh
	@printf '[rocksdb] Building shared db_bench\n'
	@CROSS_COMPILE="$(ROCKSDB_CROSS_COMPILE)" \
	SYSROOT_DIR="$(ROCKSDB_SYSROOT_DIR)" \
	ROCKSDB_MARCH="$(ROCKSDB_MARCH)" \
	ROCKSDB_MABI="$(ROCKSDB_MABI)" \
	ROCKSDB_OPT_FLAGS="$(ROCKSDB_OPT_FLAGS)" \
	bash "$(ROCKSDB_SCRIPTS_DIR)/build-workload-linux.sh" "$(ROCKSDB_WORKLOAD_DIR)" "$(ROCKSDB_BUILD_DIR)"
	@touch "$@"

$(ROCKSDB_FIRMWARE_VARS_STAMP):
	@mkdir -p "$(@D)"
	@rm -f "$(@D)"/rocksdb-firmware-vars.*.stamp
	@touch "$@"

define add_rocksdb_case
$(ROCKSDB_BUILD_DIR)/$(1)/run-vars.$(call rocksdb_run_vars_hash,$(1)).stamp:
	@mkdir -p "$$(@D)"
	@rm -f "$$(@D)"/run-vars.*.stamp
	@printf '%s\n' \
		"keys=$$(ROCKSDB_KEYS)" "ops=$(call rocksdb_case_ops,$(1))" \
		"threads=$(call rocksdb_case_threads,$(1))" "value_size=$$(ROCKSDB_VALUE_SIZE)" \
		"profiling=$$(ROCKSDB_PROFILING)" > "$$@"

$(ROCKSDB_BUILD_DIR)/$(1)/rootfs.cpio: $$(ROCKSDB_COMMON_STAMP) $$(ROCKSDB_PACKAGE_HELPER) $(ROCKSDB_BUILD_DIR)/$(1)/run-vars.$(call rocksdb_run_vars_hash,$(1)).stamp
	@printf '[rocksdb] Packaging $(1)\n'
	@bash "$$(ROCKSDB_PACKAGE_HELPER)" \
		"$$(ROCKSDB_BUILD_DIR)/package" "$$(ROCKSDB_BUILD_DIR)/$(1)" "$(1)" \
		"$$(ROCKSDB_KEYS)" "$(call rocksdb_case_ops,$(1))" "$(call rocksdb_case_threads,$(1))" "$$(ROCKSDB_VALUE_SIZE)" "$$(ROCKSDB_PROFILING)"

$(ROCKSDB_BUILD_DIR)/$(1)/fw_payload.bin: $$(ROCKSDB_DTS_SOURCES) $$(ROCKSDB_FIRMWARE_VARS_STAMP) $$(ROCKSDB_GCPT_BIN) $$(ROCKSDB_SBI_BIN) $$(ROCKSDB_LINUX_IMAGE) $(ROCKSDB_BUILD_DIR)/$(1)/rootfs.cpio $$(ROCKSDB_SCRIPTS_DIR)/build-firmware-linux.sh $$(ROCKSDB_SCRIPTS_DIR)/dts-config.sh
	@printf '[rocksdb] Assembling firmware for $(1)\n'
	@CROSS_COMPILE="$$(ROCKSDB_CROSS_COMPILE)" \
	DTC="$$(ROCKSDB_DTC)" \
	DEFAULT_DTB="$$(ROCKSDB_DEFAULT_DTB)" \
	FIRMWARE_OUTPUT="$$(abspath $$@)" \
	bash "$$(ROCKSDB_SCRIPTS_DIR)/build-firmware-linux.sh" \
		"$$(ROCKSDB_GCPT_BIN)" "$$(ROCKSDB_SBI_BUILD_DIR)" "$$(ROCKSDB_DTS_DIR)" \
		"$$(ROCKSDB_LINUX_IMAGE)" "$$(ROCKSDB_BUILD_DIR)/$(1)"

linux/rocksdb-$(1): $(ROCKSDB_BUILD_DIR)/$(1)/fw_payload.bin

$(ROCKSDB_IMAGE_DIR)/bin/$(1).fw_payload.bin: $(ROCKSDB_BUILD_DIR)/$(1)/fw_payload.bin
	@mkdir -p "$$(@D)"
	@cp "$$<" "$$@"

WORKLOAD_PHONY_TARGETS += linux/rocksdb-$(1)
endef

$(foreach case,$(ROCKSDB_CASES),$(eval $(call add_rocksdb_case,$(case))))

linux/rocksdb: $(ROCKSDB_CASE_FIRMWARE)

rocksdb-list:
	@echo $(ROCKSDB_CASES)

rocksdb-images: $(foreach case,$(ROCKSDB_CASES),$(ROCKSDB_IMAGE_DIR)/bin/$(case).fw_payload.bin)
	@printf '[rocksdb] Output written to %s\n' "$(ROCKSDB_IMAGE_DIR)"

WORKLOAD_PHONY_TARGETS += linux/rocksdb
.PHONY: rocksdb-list rocksdb-images
