SPEC2006_WORKLOAD_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SPEC2006_REPO_ROOT := $(abspath $(SPEC2006_WORKLOAD_DIR)/../../..)
SPEC2006_SELF_MAKEFILE := $(SPEC2006_WORKLOAD_DIR)/rules.mk
SPEC2006_ROOT_MAKEFILE := $(SPEC2006_REPO_ROOT)/Makefile
SPEC2006_RECURSE_MAKEFILE := $(if $(filter $(SPEC2006_ROOT_MAKEFILE),$(abspath $(firstword $(MAKEFILE_LIST)))),$(SPEC2006_ROOT_MAKEFILE),$(SPEC2006_SELF_MAKEFILE))
SPEC2006_SCRIPTS_DIR := $(SPEC2006_REPO_ROOT)/scripts
SPEC2006_DTS_DIR := $(SPEC2006_REPO_ROOT)/dts
SPEC2006_BUILD_DIR ?= $(SPEC2006_REPO_ROOT)/build/linux-workloads/spec2006
SPEC2006_CASE_CONFIG := $(SPEC2006_WORKLOAD_DIR)/spec06.json
SPEC2006_CFG ?= $(SPEC2006_WORKLOAD_DIR)/riscv_gcc15_base.cfg
SPEC2006_HELPER := $(SPEC2006_WORKLOAD_DIR)/spec2006-package.py
SPEC2006_IMAGE_DIR ?= $(SPEC2006_REPO_ROOT)/build/images/spec2006
SPEC2006_SPEC_ROOT := $(if $(SPEC2006),$(SPEC2006),$(SPEC))
SPEC2006_CROSS_COMPILE ?= riscv64-unknown-linux-gnu-
SPEC2006_COMPILER_ROOT ?=
SPEC2006_GNU_TOOLCHAIN_ROOT ?=
SPEC2006_JEMALLOC_ROOT ?=
SPEC2006_DEFAULT_DTB ?= xiangshan-fpga-noAIA
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
SPEC2006_IMAGE_CASES := $(SPEC2006_SELECTED_CASES)
SPEC2006_ELF_TARGETS := $(foreach case,$(SPEC2006_SELECTED_CASES),$(SPEC2006_BUILD_DIR)/$(case)/elf/$(case).elf)
SPEC2006_DTS_SOURCES := $(shell find $(SPEC2006_DTS_DIR) -type f 2>/dev/null)

WORKLOAD_DIRS += $(SPEC2006_BUILD_DIR)

spec2006-check-spec-dir:
	@if [ -z "$(SPEC2006_SPEC_ROOT)" ]; then \
		echo "SPEC or SPEC2006 is required, for example:"; \
		echo "  make linux/spec2006 BENCH=astar INPUT=biglakes SPEC=/path/to/cpu2006 -jN"; \
		echo "  make linux/spec2006 BENCH=astar INPUT=biglakes SPEC2006=/path/to/cpu2006 -jN"; \
		exit 1; \
	fi; \
	if ! [ -d "$(SPEC2006_SPEC_ROOT)" ]; then \
		echo "SPEC path does not exist or is not a directory: $(SPEC2006_SPEC_ROOT)"; \
		exit 1; \
	fi; \
	if ! [ -x "$(SPEC2006_SPEC_ROOT)/bin/runspec" ]; then \
		echo "runspec not found under $(SPEC2006_SPEC_ROOT)/bin/runspec"; \
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

define add_spec2006_case
$(SPEC2006_BUILD_DIR)/$(1)/download/sentinel:
	@mkdir -p $$(@D)
	@touch $$@

$(SPEC2006_BUILD_DIR)/$(1)/elf/$(1).elf: spec2006-check-spec-dir $$(SPEC2006_HELPER) $$(SPEC2006_WORKLOAD_DIR)/build.sh $$(SPEC2006_CASE_CONFIG) $$(SPEC2006_CFG)
	@mkdir -p "$$(dir $$@)"
	@WORKLOAD_DIR="$$(abspath $$(SPEC2006_WORKLOAD_DIR))" \
	WORKLOAD_BUILD_DIR="$$(abspath $(SPEC2006_BUILD_DIR)/$(1))" \
	PKG_DIR="$$(abspath $(SPEC2006_BUILD_DIR)/$(1)/package)" \
	CROSS_COMPILE="$$(SPEC2006_CROSS_COMPILE)" \
	SPEC2006_PROGRESS_K="$$(SPEC2006_PROGRESS_K)" \
	SPEC2006_PROGRESS_N="$$(SPEC2006_PROGRESS_N)" \
	SPEC2006_CASE="$(1)" \
	SPEC2006="$$(SPEC2006_SPEC_ROOT)" \
	SPEC2006_CASE_CONFIG="$$(abspath $$(SPEC2006_CASE_CONFIG))" \
	SPEC2006_CFG="$$(abspath $$(SPEC2006_CFG))" \
	SPEC2006_COMPILER_ROOT="$$(SPEC2006_COMPILER_ROOT)" \
	SPEC2006_GNU_TOOLCHAIN_ROOT="$$(SPEC2006_GNU_TOOLCHAIN_ROOT)" \
	SPEC2006_JEMALLOC_ROOT="$$(SPEC2006_JEMALLOC_ROOT)" \
	SPEC2006_TUNE="$$(SPEC2006_TUNE)" \
	SPEC2006_JOBS="$$(SPEC2006_JOBS)" \
	SPEC2006_ELF_ONLY=1 \
	bash "$$(abspath $$(SPEC2006_WORKLOAD_DIR))/build.sh"

$(SPEC2006_BUILD_DIR)/$(1)/rootfs.cpio: spec2006-check-spec-dir $$(SPEC2006_HELPER) $$(SPEC2006_WORKLOAD_DIR)/build.sh $$(SPEC2006_CASE_CONFIG) $$(SPEC2006_CFG) $(SPEC2006_BUILD_DIR)/$(1)/download/sentinel $$(SPEC2006_SCRIPTS_DIR)/build-workload-linux.sh
	@CROSS_COMPILE="$$(SPEC2006_CROSS_COMPILE)" \
	SPEC2006_PROGRESS_K="$$(SPEC2006_PROGRESS_K)" \
	SPEC2006_PROGRESS_N="$$(SPEC2006_PROGRESS_N)" \
	SPEC2006_CASE="$(1)" \
	SPEC2006="$$(SPEC2006_SPEC_ROOT)" \
	SPEC2006_CASE_CONFIG="$$(abspath $$(SPEC2006_CASE_CONFIG))" \
	SPEC2006_CFG="$$(abspath $$(SPEC2006_CFG))" \
	SPEC2006_COMPILER_ROOT="$$(SPEC2006_COMPILER_ROOT)" \
	SPEC2006_GNU_TOOLCHAIN_ROOT="$$(SPEC2006_GNU_TOOLCHAIN_ROOT)" \
	SPEC2006_JEMALLOC_ROOT="$$(SPEC2006_JEMALLOC_ROOT)" \
	SPEC2006_TUNE="$$(SPEC2006_TUNE)" \
	SPEC2006_JOBS="$$(SPEC2006_JOBS)" \
	bash "$$(SPEC2006_SCRIPTS_DIR)/build-workload-linux.sh" "$$(SPEC2006_WORKLOAD_DIR)" "$(SPEC2006_BUILD_DIR)/$(1)"

$(SPEC2006_BUILD_DIR)/$(1)/fw_payload.bin: $$(SPEC2006_DTS_SOURCES) $$(SPEC2006_GCPT_BIN) $$(SPEC2006_SCRIPTS_DIR)/build-firmware-linux.sh $(SPEC2006_BUILD_DIR)/$(1)/rootfs.cpio $$(SPEC2006_LINUX_IMAGE) $$(SPEC2006_SBI_BIN)
	@printf '$(SPEC2006_PROGRESS_PREFIX) Assembling firmware for $(1)\n'
	@CROSS_COMPILE="$$(SPEC2006_BUILDROOT_CROSS_COMPILE)" \
	DTC="$$(SPEC2006_DTC)" \
	DEFAULT_DTB="$$(SPEC2006_DEFAULT_DTB)" \
	SPEC2006_PROGRESS_K="$$(SPEC2006_PROGRESS_K)" \
	SPEC2006_PROGRESS_N="$$(SPEC2006_PROGRESS_N)" \
	bash "$$(SPEC2006_SCRIPTS_DIR)/build-firmware-linux.sh" "$$(SPEC2006_GCPT_BIN)" "$$(SPEC2006_SBI_BUILD_DIR)" "$$(SPEC2006_DTS_DIR)" "$$(SPEC2006_LINUX_IMAGE)" "$(SPEC2006_BUILD_DIR)/$(1)"

linux/$(1): $(SPEC2006_BUILD_DIR)/$(1)/fw_payload.bin

WORKLOAD_PHONY_TARGETS += linux/$(1)

$(SPEC2006_IMAGE_DIR)/bin/$(1).fw_payload.bin: $(SPEC2006_BUILD_DIR)/$(1)/fw_payload.bin $(SPEC2006_LINUX_IMAGE)
	@printf '$(SPEC2006_PROGRESS_PREFIX) Exporting $(1) artifacts to $(SPEC2006_IMAGE_DIR)\n'
	@mkdir -p "$(SPEC2006_IMAGE_DIR)/bin" "$(SPEC2006_IMAGE_DIR)/kernel" "$(SPEC2006_IMAGE_DIR)/elf" "$(SPEC2006_IMAGE_DIR)/cfg" "$(SPEC2006_IMAGE_DIR)/gcpt"
	@if [ ! -f "$(SPEC2006_IMAGE_DIR)/cfg/$(notdir $(SPEC2006_CFG))" ]; then \
		printf '$(SPEC2006_PROGRESS_PREFIX) Exporting spec2006 cfg to $(SPEC2006_IMAGE_DIR)/cfg\n'; \
		cp "$(SPEC2006_CFG)" "$(SPEC2006_IMAGE_DIR)/cfg/$(notdir $(SPEC2006_CFG))"; \
	fi
	@if [ ! -f "$(SPEC2006_IMAGE_DIR)/gcpt/gcpt.elf" ] || [ ! -f "$(SPEC2006_IMAGE_DIR)/gcpt/gcpt.bin" ]; then \
		printf '$(SPEC2006_PROGRESS_PREFIX) Exporting gcpt artifacts to $(SPEC2006_IMAGE_DIR)/gcpt\n'; \
		cp "$(SPEC2006_GCPT_ELF)" "$(SPEC2006_IMAGE_DIR)/gcpt/gcpt.elf"; \
		cp "$(SPEC2006_GCPT_BIN)" "$(SPEC2006_IMAGE_DIR)/gcpt/gcpt.bin"; \
	fi
	@cp $(SPEC2006_BUILD_DIR)/$(1)/elf/$(1).elf $(SPEC2006_IMAGE_DIR)/elf/$(1).elf
	@cp $(SPEC2006_LINUX_IMAGE) $(SPEC2006_IMAGE_DIR)/kernel/$(1).Image
	@cp $(SPEC2006_BUILD_DIR)/$(1)/fw_payload.bin $(SPEC2006_IMAGE_DIR)/bin/$(1).fw_payload.bin
endef

$(foreach case,$(SPEC2006_ALL_CASES),$(eval $(call add_spec2006_case,$(case))))

linux/spec2006: spec2006-check-spec-dir
	@if [ -z "$(BENCH)" ]; then \
		echo "Usage: make linux/spec2006 BENCH=astar INPUT=biglakes SPEC=/path/to/cpu2006 -jN"; \
		echo "   or: make linux/spec2006 BENCH=astar_biglakes SPEC=/path/to/cpu2006 -jN"; \
		exit 1; \
	fi
	@$(MAKE) --no-print-directory -f "$(SPEC2006_RECURSE_MAKEFILE)" $(SPEC2006_BUILD_DIR)/$(SPEC2006_CASE)/fw_payload.bin

spec2006-elf: spec2006-check-spec-dir
	@if [ -z "$(BENCH)" ]; then \
		echo "Usage: make spec2006-elf BENCH=astar INPUT=biglakes SPEC=/path/to/cpu2006 -jN"; \
		echo "   or: make spec2006-elf BENCH=astar_biglakes SPEC=/path/to/cpu2006 -jN"; \
		exit 1; \
	fi
	@$(MAKE) --no-print-directory -f "$(SPEC2006_RECURSE_MAKEFILE)" $(SPEC2006_BUILD_DIR)/$(SPEC2006_CASE)/elf/$(SPEC2006_CASE).elf

spec2006-elfs: spec2006-check-spec-dir
	@if [ -z "$(SPEC2006_SELECTED_CASES)" ]; then \
		echo "No SPEC2006 cases selected by SPEC2006_INPUT=$(SPEC2006_INPUT)"; \
		exit 1; \
	fi; \
	for case in $(SPEC2006_SELECTED_CASES); do \
		$(MAKE) --no-print-directory -f "$(SPEC2006_RECURSE_MAKEFILE)" "$(SPEC2006_BUILD_DIR)/$$case/elf/$$case.elf" || exit $$?; \
	done

spec2006-images: spec2006-check-spec-dir
	@if [ -z "$(SPEC2006_IMAGE_CASES)" ]; then \
		echo "No SPEC2006 cases selected by SPEC2006_INPUT=$(SPEC2006_INPUT)"; \
		exit 1; \
	fi; \
	total="$(words $(SPEC2006_IMAGE_CASES))"; \
	i=0; \
	for case in $(SPEC2006_IMAGE_CASES); do \
		i=$$((i + 1)); \
		SPEC2006_PROGRESS_K="$$i" SPEC2006_PROGRESS_N="$$total" $(MAKE) --no-print-directory -f "$(SPEC2006_RECURSE_MAKEFILE)" "$(SPEC2006_IMAGE_DIR)/bin/$$case.fw_payload.bin" || exit $$?; \
	done
	@printf '[spec2006 %s/%s] Output written to %s\n' "$(words $(SPEC2006_IMAGE_CASES))" "$(words $(SPEC2006_IMAGE_CASES))" "$(abspath $(SPEC2006_IMAGE_DIR))"

.PHONY: linux/spec2006 spec2006-check-spec-dir spec2006-elf spec2006-elfs spec2006-images
