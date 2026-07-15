SPEC2006_WORKLOAD_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SPEC2006_REPO_ROOT := $(abspath $(SPEC2006_WORKLOAD_DIR)/../../..)
SPEC2006_SELF_MAKEFILE := $(SPEC2006_WORKLOAD_DIR)/rules.mk
SPEC2006_ROOT_MAKEFILE := $(SPEC2006_REPO_ROOT)/Makefile
SPEC2006_RECURSE_MAKEFILE := $(if $(filter $(SPEC2006_ROOT_MAKEFILE),$(abspath $(firstword $(MAKEFILE_LIST)))),$(SPEC2006_ROOT_MAKEFILE),$(SPEC2006_SELF_MAKEFILE))
SPEC2006_SCRIPTS_DIR := $(SPEC2006_REPO_ROOT)/scripts
SPEC2006_DTS_DIR := $(SPEC2006_REPO_ROOT)/dts
SPEC2006_BUILD_DIR ?= $(SPEC2006_REPO_ROOT)/build/linux-workloads/spec2006
SPEC2006_CASE_CONFIG := $(SPEC2006_WORKLOAD_DIR)/spec06.json
SPEC2006_CFG ?= $(SPEC2006_WORKLOAD_DIR)/configs/riscv_gcc15_base.cfg
SPEC2006_HELPER := $(SPEC2006_WORKLOAD_DIR)/spec2006-package.py
SPEC2006_IMAGE_DIR ?= $(SPEC2006_REPO_ROOT)/build/images/spec2006
SPEC2006_SOURCE_SPEC_ISO := $(SPEC2006_ISO)
SPEC2006_PREPARED_SPEC_ROOT := $(SPEC2006_BUILD_DIR)/spec-src
SPEC2006_SOURCE_SPEC_HASH := $(shell printf '%s\n' "$(SPEC2006_SOURCE_SPEC_ISO)" | sha256sum | cut -d ' ' -f 1)
SPEC2006_PREPARE_STAMP := $(SPEC2006_BUILD_DIR)/spec-src.$(SPEC2006_SOURCE_SPEC_HASH).prepared
SPEC2006_PREPARE_SCRIPT := $(SPEC2006_WORKLOAD_DIR)/prepare-spec-workspace.sh
SPEC2006_CROSS_COMPILE ?= riscv64-unknown-linux-gnu-
SPEC2006_COMPILER_ROOT ?=
SPEC2006_GNU_TOOLCHAIN_ROOT ?=
SPEC2006_JEMALLOC_ROOT ?=
SPEC2006_MULTIHART ?= $(MULTIHART)
SPEC2006_HARTS ?= $(if $(HARTS),$(HARTS),2)
SPEC2006_MULTIHART_DEFAULT_DTB := xiangshan-fpga-noAIA-$(SPEC2006_HARTS)hart-mem8g
SPEC2006_DEFAULT_DTB ?= $(if $(DEFAULT_DTB),$(DEFAULT_DTB),$(if $(filter 1,$(SPEC2006_MULTIHART)),$(SPEC2006_MULTIHART_DEFAULT_DTB),xiangshan-fpga-noAIA-novec))
SPEC2006_TUNE ?= base
SPEC2006_JOBS ?= $(shell nproc)
SPEC2006_INPUT ?= ref
SPEC2006_PROGRESS_K ?= 1
SPEC2006_PROGRESS_N ?= 1
SPEC2006_PROGRESS_PREFIX := [spec2006 $(SPEC2006_PROGRESS_K)/$(SPEC2006_PROGRESS_N)]
SPEC2006_BUILDROOT_DIR ?= $(if $(BUILDROOT_DIR),$(BUILDROOT_DIR),$(SPEC2006_REPO_ROOT)/build/buildroot)
SPEC2006_LINUX_IMAGE ?= $(if $(LINUX_IMAGE),$(LINUX_IMAGE),$(SPEC2006_BUILDROOT_DIR)/output/images/Image)
SPEC2006_GCPT_ELF ?= $(if $(GCPT_ELF),$(GCPT_ELF),$(SPEC2006_REPO_ROOT)/build/LibCheckpointAlpha/build/gcpt)
SPEC2006_GCPT_BIN ?= $(if $(GCPT_BIN),$(GCPT_BIN),$(SPEC2006_REPO_ROOT)/build/LibCheckpointAlpha/build/gcpt.bin)
SPEC2006_SBI_BUILD_DIR ?= $(if $(SBI_BUILD_DIR),$(SBI_BUILD_DIR),$(SPEC2006_REPO_ROOT)/build/opensbi)
SPEC2006_SBI_BIN ?= $(if $(SBI_BIN),$(SBI_BIN),$(SPEC2006_SBI_BUILD_DIR)/build/platform/generic/firmware/fw_jump.bin)
SPEC2006_BUILDROOT_CROSS_COMPILE ?= $(SPEC2006_BUILDROOT_DIR)/output/host/bin/riscv64-linux-
SPEC2006_DTC ?= $(SPEC2006_BUILDROOT_DIR)/output/host/bin/dtc
SPEC2006_CASE := $(if $(INPUT),$(BENCH)_$(INPUT),$(BENCH))
SPEC2006_ALL_CASES := $(shell python3 $(SPEC2006_HELPER) --cases-config $(SPEC2006_CASE_CONFIG) --list-cases 2>/dev/null)
SPEC2006_SELECTED_CASES := $(shell python3 $(SPEC2006_HELPER) --cases-config $(SPEC2006_CASE_CONFIG) --list-cases --input-set $(SPEC2006_INPUT) 2>/dev/null)
SPEC2006_IMAGE_CASES := $(if $(BENCH),$(SPEC2006_CASE),$(SPEC2006_SELECTED_CASES))
SPEC2006_ELF_TARGETS := $(foreach case,$(SPEC2006_SELECTED_CASES),$(SPEC2006_BUILD_DIR)/$(case)/elf/$(case).elf)
SPEC2006_DTS_SOURCES := $(shell find $(SPEC2006_DTS_DIR) -type f 2>/dev/null)
SPEC2006_CFG_HASH := $(shell if [ -f "$(abspath $(SPEC2006_CFG))" ]; then sha256sum "$(abspath $(SPEC2006_CFG))" | cut -d ' ' -f 1; else printf 'missing'; fi)
SPEC2006_DEFAULT_DTB_STAMP := $(SPEC2006_BUILD_DIR)/dtb.$(shell printf '%s\n' "$(SPEC2006_DEFAULT_DTB)" | sha256sum | cut -d ' ' -f 1)
SPEC2006_BUILD_VARS_HASH := $(shell printf '%s\n' '$(SPEC2006_INPUT)' '$(SPEC2006_TUNE)' '$(SPEC2006_JOBS)' '$(SPEC2006_CROSS_COMPILE)' 'multihart=$(SPEC2006_MULTIHART)' 'harts=$(SPEC2006_HARTS)' | sha256sum | cut -d ' ' -f 1)
spec2006_case_image_stamp = $(SPEC2006_IMAGE_DIR)/stamps/$(1).images.stamp

WORKLOAD_DIRS += $(SPEC2006_BUILD_DIR)

spec2006-check-spec-iso:
	@if [ -z "$(SPEC2006_SOURCE_SPEC_ISO)" ]; then \
		echo "SPEC2006_ISO is required, for example:"; \
		echo "  make linux/spec2006 BENCH=astar INPUT=biglakes SPEC2006_ISO=/path/to/cpu2006.iso -jN"; \
		exit 1; \
	fi; \
	if ! [ -f "$(SPEC2006_SOURCE_SPEC_ISO)" ]; then \
		echo "SPEC ISO path does not exist: $(SPEC2006_SOURCE_SPEC_ISO)"; \
		exit 1; \
	fi; \
	if ! [ -f "$(SPEC2006_CFG)" ]; then \
		echo "SPEC2006 cfg does not exist: $(SPEC2006_CFG)"; \
		exit 1; \
	fi; \
	if ! [ -f "$(SPEC2006_CASE_CONFIG)" ]; then \
		echo "SPEC2006 case config does not exist: $(SPEC2006_CASE_CONFIG)"; \
		exit 1; \
	fi; \
	case "$(SPEC2006_INPUT)" in \
		ref|train|test|all) ;; \
		*) echo "SPEC2006_INPUT must be one of: ref, train, test, all"; exit 1 ;; \
	esac

spec2006-prepare: $(SPEC2006_PREPARE_STAMP)

$(SPEC2006_PREPARE_STAMP): $(SPEC2006_PREPARE_SCRIPT) $(SPEC2006_SOURCE_SPEC_ISO) | spec2006-check-spec-iso
	@printf '$(SPEC2006_PROGRESS_PREFIX) Preparing SPEC workspace at $(SPEC2006_PREPARED_SPEC_ROOT)\n'
	@bash "$(SPEC2006_PREPARE_SCRIPT)" "$(SPEC2006_SOURCE_SPEC_ISO)" "$(SPEC2006_PREPARED_SPEC_ROOT)"
	@touch "$@"

$(SPEC2006_DEFAULT_DTB_STAMP):
	@mkdir -p "$(@D)"
	@rm -f "$(SPEC2006_BUILD_DIR)"/dtb.*
	@touch "$@"

spec2006-force:

define add_spec2006_case
$(SPEC2006_BUILD_DIR)/$(1)/download/sentinel:
	@mkdir -p $$(@D)
	@touch $$@

$(SPEC2006_BUILD_DIR)/$(1)/build-vars.$(SPEC2006_BUILD_VARS_HASH).stamp:
	@mkdir -p "$$(@D)"
	@printf '%s\n' "input=$(SPEC2006_INPUT)" "tune=$(SPEC2006_TUNE)" "jobs=$(SPEC2006_JOBS)" "cross_compile=$(SPEC2006_CROSS_COMPILE)" "multihart=$(SPEC2006_MULTIHART)" "harts=$(SPEC2006_HARTS)" > "$$@"

$(SPEC2006_BUILD_DIR)/$(1)/cfg.stamp: spec2006-force
	@mkdir -p "$$(@D)"
	@printf '%s\n' \
		"cfg=$$(abspath $$(SPEC2006_CFG))" \
		"hash=$$(SPEC2006_CFG_HASH)" > "$$@.tmp"
	@if [ -f "$$@" ] && cmp -s "$$@.tmp" "$$@"; then rm "$$@.tmp"; else mv "$$@.tmp" "$$@"; fi

$(SPEC2006_BUILD_DIR)/$(1)/elf/$(1).elf: $(SPEC2006_PREPARE_STAMP) $(SPEC2006_BUILD_DIR)/$(1)/cfg.stamp $$(SPEC2006_HELPER) $$(SPEC2006_WORKLOAD_DIR)/build.sh $$(SPEC2006_CASE_CONFIG)
	@mkdir -p "$$(dir $$@)"
	@WORKLOAD_DIR="$$(abspath $$(SPEC2006_WORKLOAD_DIR))" \
	WORKLOAD_BUILD_DIR="$$(abspath $(SPEC2006_BUILD_DIR)/$(1))" \
	PKG_DIR="$$(abspath $(SPEC2006_BUILD_DIR)/$(1)/package)" \
	CROSS_COMPILE="$$(SPEC2006_CROSS_COMPILE)" \
	SPEC2006_PROGRESS_K="$$(SPEC2006_PROGRESS_K)" \
	SPEC2006_PROGRESS_N="$$(SPEC2006_PROGRESS_N)" \
	SPEC2006_CASE="$(1)" \
	SPEC2006="$$(SPEC2006_PREPARED_SPEC_ROOT)" \
	SPEC2006_CASE_CONFIG="$$(abspath $$(SPEC2006_CASE_CONFIG))" \
	SPEC2006_CFG="$$(abspath $$(SPEC2006_CFG))" \
	SPEC2006_COMPILER_ROOT="$$(SPEC2006_COMPILER_ROOT)" \
	SPEC2006_GNU_TOOLCHAIN_ROOT="$$(SPEC2006_GNU_TOOLCHAIN_ROOT)" \
	SPEC2006_JEMALLOC_ROOT="$$(SPEC2006_JEMALLOC_ROOT)" \
	SPEC2006_TUNE="$$(SPEC2006_TUNE)" \
	SPEC2006_JOBS="$$(SPEC2006_JOBS)" \
	SPEC2006_ELF_ONLY=1 \
	bash "$$(abspath $$(SPEC2006_WORKLOAD_DIR))/build.sh"

$(SPEC2006_BUILD_DIR)/$(1)/rootfs.cpio: $(SPEC2006_PREPARE_STAMP) $(SPEC2006_BUILD_DIR)/$(1)/cfg.stamp $$(SPEC2006_HELPER) $$(SPEC2006_WORKLOAD_DIR)/build.sh $$(SPEC2006_CASE_CONFIG) $(SPEC2006_BUILD_DIR)/$(1)/download/sentinel $(SPEC2006_BUILD_DIR)/$(1)/build-vars.$(SPEC2006_BUILD_VARS_HASH).stamp $$(SPEC2006_SCRIPTS_DIR)/build-workload-linux.sh $$(SPEC2006_SCRIPTS_DIR)/package-multihart-rootfs.py $$(SPEC2006_REPO_ROOT)/workloads/linux/common/before_workload.c $$(SPEC2006_REPO_ROOT)/workloads/linux/common/after_workload.c
	@CROSS_COMPILE="$$(SPEC2006_CROSS_COMPILE)" \
	SPEC2006_PROGRESS_K="$$(SPEC2006_PROGRESS_K)" \
	SPEC2006_PROGRESS_N="$$(SPEC2006_PROGRESS_N)" \
	SPEC2006_CASE="$(1)" \
	SPEC2006="$$(SPEC2006_PREPARED_SPEC_ROOT)" \
	SPEC2006_CASE_CONFIG="$$(abspath $$(SPEC2006_CASE_CONFIG))" \
	SPEC2006_CFG="$$(abspath $$(SPEC2006_CFG))" \
	SPEC2006_COMPILER_ROOT="$$(SPEC2006_COMPILER_ROOT)" \
	SPEC2006_GNU_TOOLCHAIN_ROOT="$$(SPEC2006_GNU_TOOLCHAIN_ROOT)" \
	SPEC2006_JEMALLOC_ROOT="$$(SPEC2006_JEMALLOC_ROOT)" \
	SPEC2006_TUNE="$$(SPEC2006_TUNE)" \
	SPEC2006_JOBS="$$(SPEC2006_JOBS)" \
	MULTIHART="$$(SPEC2006_MULTIHART)" \
	HARTS="$$(SPEC2006_HARTS)" \
	bash "$$(SPEC2006_SCRIPTS_DIR)/build-workload-linux.sh" "$$(SPEC2006_WORKLOAD_DIR)" "$(SPEC2006_BUILD_DIR)/$(1)"

$(SPEC2006_BUILD_DIR)/$(1)/fw_payload.bin: $$(SPEC2006_DTS_SOURCES) $$(SPEC2006_DEFAULT_DTB_STAMP) $$(SPEC2006_GCPT_BIN) $$(SPEC2006_SCRIPTS_DIR)/build-firmware-linux.sh $(SPEC2006_BUILD_DIR)/$(1)/rootfs.cpio $$(SPEC2006_LINUX_IMAGE) $$(SPEC2006_SBI_BIN)
	@printf '$(SPEC2006_PROGRESS_PREFIX) Assembling firmware for $(1)\n'
	@CROSS_COMPILE="$$(SPEC2006_BUILDROOT_CROSS_COMPILE)" \
	DTC="$$(SPEC2006_DTC)" \
	DEFAULT_DTB="$$(SPEC2006_DEFAULT_DTB)" \
	SPEC2006_PROGRESS_K="$$(SPEC2006_PROGRESS_K)" \
	SPEC2006_PROGRESS_N="$$(SPEC2006_PROGRESS_N)" \
	bash "$$(SPEC2006_SCRIPTS_DIR)/build-firmware-linux.sh" "$$(SPEC2006_GCPT_BIN)" "$$(SPEC2006_SBI_BUILD_DIR)" "$$(SPEC2006_DTS_DIR)" "$$(SPEC2006_LINUX_IMAGE)" "$(SPEC2006_BUILD_DIR)/$(1)"

linux/$(1): $(SPEC2006_BUILD_DIR)/$(1)/fw_payload.bin

WORKLOAD_PHONY_TARGETS += linux/$(1)

$(call spec2006_case_image_stamp,$(1)): $(SPEC2006_PREPARE_STAMP) $(SPEC2006_BUILD_DIR)/$(1)/fw_payload.bin $(SPEC2006_GCPT_ELF) $(SPEC2006_GCPT_BIN) $(SPEC2006_LINUX_IMAGE) | spec2006-check-spec-iso
	@printf '$(SPEC2006_PROGRESS_PREFIX) Exporting $(1) artifacts to $(SPEC2006_IMAGE_DIR)\n'
	@mkdir -p "$(SPEC2006_IMAGE_DIR)/bin" "$(SPEC2006_IMAGE_DIR)/kernel" "$(SPEC2006_IMAGE_DIR)/rootfs" "$(SPEC2006_IMAGE_DIR)/elf" "$(SPEC2006_IMAGE_DIR)/cmd" "$(SPEC2006_IMAGE_DIR)/cfg" "$(SPEC2006_IMAGE_DIR)/gcpt" "$(SPEC2006_IMAGE_DIR)/logs/build_elf" "$(SPEC2006_IMAGE_DIR)/stamps"
	@if [ ! -f "$(SPEC2006_IMAGE_DIR)/cfg/$(notdir $(SPEC2006_CFG))" ]; then \
		printf '$(SPEC2006_PROGRESS_PREFIX) Exporting spec2006 cfg to $(SPEC2006_IMAGE_DIR)/cfg\n'; \
		cp "$(SPEC2006_CFG)" "$(SPEC2006_IMAGE_DIR)/cfg/$(notdir $(SPEC2006_CFG))"; \
	fi
	@if [ ! -f "$(SPEC2006_IMAGE_DIR)/gcpt/gcpt.elf" ] || [ ! -f "$(SPEC2006_IMAGE_DIR)/gcpt/gcpt.bin" ]; then \
		printf '$(SPEC2006_PROGRESS_PREFIX) Exporting gcpt artifacts to $(SPEC2006_IMAGE_DIR)/gcpt\n'; \
		cp "$(SPEC2006_GCPT_ELF)" "$(SPEC2006_IMAGE_DIR)/gcpt/gcpt.elf"; \
		cp "$(SPEC2006_GCPT_BIN)" "$(SPEC2006_IMAGE_DIR)/gcpt/gcpt.bin"; \
	fi
	@cp "$(SPEC2006_BUILD_DIR)/$(1)/elf/$(1).elf" "$(SPEC2006_IMAGE_DIR)/elf/$(1).elf"
	@cp "$(SPEC2006_BUILD_DIR)/$(1)/logs/build_elf/build.log" "$(SPEC2006_IMAGE_DIR)/logs/build_elf/$(1).log"
	@cp "$(SPEC2006_LINUX_IMAGE)" "$(SPEC2006_IMAGE_DIR)/kernel/$(1).Image"
	@cp "$(SPEC2006_BUILD_DIR)/$(1)/rootfs.cpio" "$(SPEC2006_IMAGE_DIR)/rootfs/$(1).rootfs.cpio"
	@cp "$(SPEC2006_BUILD_DIR)/$(1)/fw_payload.bin" "$(SPEC2006_IMAGE_DIR)/bin/$(1).fw_payload.bin"
	@if [ -f "$(SPEC2006_BUILD_DIR)/$(1)/package/spec/run.sh" ]; then \
		cp "$(SPEC2006_BUILD_DIR)/$(1)/package/spec/run.sh" "$(SPEC2006_IMAGE_DIR)/cmd/$(1).run.sh"; \
	else \
		cp "$(SPEC2006_BUILD_DIR)/$(1)/package/spec_common/launch_multihart.sh" "$(SPEC2006_IMAGE_DIR)/cmd/$(1).run.sh"; \
	fi
	@touch "$$@"
endef

$(foreach case,$(SPEC2006_ALL_CASES),$(eval $(call add_spec2006_case,$(case))))

linux/spec2006: spec2006-check-spec-iso
	@if [ -z "$(BENCH)" ]; then \
		echo "Usage: make linux/spec2006 BENCH=astar INPUT=biglakes SPEC2006_ISO=/path/to/cpu2006.iso -jN"; \
		echo "   or: make linux/spec2006 BENCH=astar_biglakes SPEC2006_ISO=/path/to/cpu2006.iso -jN"; \
		exit 1; \
	fi
	@$(MAKE) --no-print-directory -f "$(SPEC2006_RECURSE_MAKEFILE)" GCPT_DEFAULT_DTB="$(SPEC2006_DEFAULT_DTB)" $(SPEC2006_BUILD_DIR)/$(SPEC2006_CASE)/fw_payload.bin

spec2006-elf: spec2006-check-spec-iso
	@if [ -z "$(BENCH)" ]; then \
		echo "Usage: make spec2006-elf BENCH=astar INPUT=biglakes SPEC2006_ISO=/path/to/cpu2006.iso -jN"; \
		echo "   or: make spec2006-elf BENCH=astar_biglakes SPEC2006_ISO=/path/to/cpu2006.iso -jN"; \
		exit 1; \
	fi
	@$(MAKE) --no-print-directory -f "$(SPEC2006_RECURSE_MAKEFILE)" $(SPEC2006_BUILD_DIR)/$(SPEC2006_CASE)/elf/$(SPEC2006_CASE).elf

spec2006-elfs: spec2006-check-spec-iso
	@if [ -z "$(SPEC2006_SELECTED_CASES)" ]; then \
		echo "No SPEC2006 cases selected by SPEC2006_INPUT=$(SPEC2006_INPUT)"; \
		exit 1; \
	fi; \
	for case in $(SPEC2006_SELECTED_CASES); do \
		$(MAKE) --no-print-directory -f "$(SPEC2006_RECURSE_MAKEFILE)" "$(SPEC2006_BUILD_DIR)/$$case/elf/$$case.elf" || exit $$?; \
	done

spec2006-images: spec2006-check-spec-iso
	@if [ -n "$(BENCH)" ] && [ -z "$(filter $(SPEC2006_CASE),$(SPEC2006_ALL_CASES))" ]; then \
		echo "Unknown SPEC2006 case for BENCH=$(BENCH) INPUT=$(INPUT)"; \
		exit 1; \
	fi; \
	if [ -z "$(SPEC2006_IMAGE_CASES)" ]; then \
		echo "No SPEC2006 cases selected by SPEC2006_INPUT=$(SPEC2006_INPUT)"; \
		exit 1; \
	fi; \
	rm -rf "$(SPEC2006_IMAGE_DIR)/bin" "$(SPEC2006_IMAGE_DIR)/kernel" "$(SPEC2006_IMAGE_DIR)/rootfs" "$(SPEC2006_IMAGE_DIR)/elf" "$(SPEC2006_IMAGE_DIR)/cmd" "$(SPEC2006_IMAGE_DIR)/cfg" "$(SPEC2006_IMAGE_DIR)/gcpt" "$(SPEC2006_IMAGE_DIR)/logs" "$(SPEC2006_IMAGE_DIR)/stamps"; \
	total="$(words $(SPEC2006_IMAGE_CASES))"; \
	i=0; \
	for case in $(SPEC2006_IMAGE_CASES); do \
		i=$$((i + 1)); \
		SPEC2006_PROGRESS_K="$$i" SPEC2006_PROGRESS_N="$$total" $(MAKE) --no-print-directory -f "$(SPEC2006_RECURSE_MAKEFILE)" GCPT_DEFAULT_DTB="$(SPEC2006_DEFAULT_DTB)" "$(call spec2006_case_image_stamp,$$case)" || exit $$?; \
	done
	@printf '[spec2006 %s/%s] Output written to %s\n' "$(words $(SPEC2006_IMAGE_CASES))" "$(words $(SPEC2006_IMAGE_CASES))" "$(abspath $(SPEC2006_IMAGE_DIR))"

.PHONY: linux/spec2006 spec2006-check-spec-iso spec2006-force spec2006-prepare spec2006-elf spec2006-elfs spec2006-images
