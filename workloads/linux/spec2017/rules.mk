SPEC2017_WORKLOAD_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SPEC2017_REPO_ROOT := $(abspath $(SPEC2017_WORKLOAD_DIR)/../../..)
SPEC2017_SELF_MAKEFILE := $(SPEC2017_WORKLOAD_DIR)/rules.mk
SPEC2017_ROOT_MAKEFILE := $(SPEC2017_REPO_ROOT)/Makefile
SPEC2017_RECURSE_MAKEFILE := $(if $(filter $(SPEC2017_ROOT_MAKEFILE),$(abspath $(firstword $(MAKEFILE_LIST)))),$(SPEC2017_ROOT_MAKEFILE),$(SPEC2017_SELF_MAKEFILE))
SPEC2017_SCRIPTS_DIR := $(SPEC2017_REPO_ROOT)/scripts
SPEC2017_DTS_DIR := $(SPEC2017_REPO_ROOT)/dts
SPEC2017_BUILD_DIR ?= $(SPEC2017_REPO_ROOT)/build/linux-workloads/spec2017
SPEC2017_EXPLICIT_CFG := $(if $(filter undefined,$(origin SPEC2017_CFG)),,1)
SPEC2017_RATE_CFG ?= $(SPEC2017_WORKLOAD_DIR)/riscv-gcc15.cfg
SPEC2017_SPEED_CFG ?= $(SPEC2017_WORKLOAD_DIR)/riscv-gcc15.cfg
SPEC2017_HELPER := $(SPEC2017_WORKLOAD_DIR)/spec2017-package.py
SPEC2017_IMAGE_DIR ?= $(SPEC2017_REPO_ROOT)/build/images/$(if $(filter rate,$(SPEC2017_IMAGE_MODE)),spec2017rate,$(if $(filter speed,$(SPEC2017_IMAGE_MODE)),spec2017speed,spec2017))
SPEC2017_SOURCE_SPEC_ISO := $(SPEC2017_ISO)
SPEC2017_PREPARED_SPEC_ROOT := $(SPEC2017_BUILD_DIR)/spec-src
SPEC2017_SOURCE_SPEC_HASH := $(shell if [ -n "$(SPEC2017_SOURCE_SPEC_ISO)" ] && [ -f "$(SPEC2017_SOURCE_SPEC_ISO)" ]; then stat -c '%n:%s:%Y' "$(SPEC2017_SOURCE_SPEC_ISO)"; else printf '%s\n' "$(SPEC2017_SOURCE_SPEC_ISO)"; fi | sha256sum | cut -d ' ' -f 1)
SPEC2017_PREPARE_STAMP := $(SPEC2017_BUILD_DIR)/spec-src.$(SPEC2017_SOURCE_SPEC_HASH).prepared
SPEC2017_PREPARE_SCRIPT := $(SPEC2017_WORKLOAD_DIR)/prepare-spec-workspace.sh
SPEC2017_CROSS_COMPILE ?= riscv64-unknown-linux-gnu-
SPEC2017_COMPILER_ROOT ?=
SPEC2017_GNU_TOOLCHAIN_ROOT ?=
SPEC2017_EXPLICIT_DEFAULT_DTB := $(if $(DEFAULT_DTB),1,$(if $(filter undefined,$(origin SPEC2017_DEFAULT_DTB)),,1))
SPEC2017_DEFAULT_DTB ?= $(if $(DEFAULT_DTB),$(DEFAULT_DTB),xiangshan-fpga-noAIA)
SPEC2017_RATE_DTB_MEMORY ?= 8g
SPEC2017_SPEED_DTB_MEMORY ?= 24g
SPEC2017_DTB_MEMORY ?=
SPEC2017_RATE_DTB_MIN_MEMORY_BYTES ?= 8589934592
SPEC2017_SPEED_DTB_MIN_MEMORY_BYTES ?= 25769803776
SPEC2017_PROFILING ?= $(if $(PROFILING),$(PROFILING),1)
SPEC2017_TUNE ?= base
SPEC2017_JOBS ?= $(shell nproc)
SPEC2017_INPUT ?= $(if $(INPUT),$(INPUT),ref)
SPEC2017_MODE ?= $(if $(MODE),$(MODE),rate)
SPEC2017_IMAGE_INPUT ?= $(SPEC2017_INPUT)
SPEC2017_IMAGE_MODE ?= $(SPEC2017_MODE)
SPEC2017_PROGRESS_K ?= 1
SPEC2017_PROGRESS_N ?= 1
SPEC2017_PROGRESS_PREFIX := [spec2017 $(SPEC2017_PROGRESS_K)/$(SPEC2017_PROGRESS_N)]
SPEC2017_BUILDROOT_DIR ?= $(if $(BUILDROOT_DIR),$(BUILDROOT_DIR),$(SPEC2017_REPO_ROOT)/build/buildroot)
SPEC2017_LINUX_IMAGE ?= $(if $(LINUX_IMAGE),$(LINUX_IMAGE),$(SPEC2017_BUILDROOT_DIR)/output/images/Image)
SPEC2017_GCPT_ELF ?= $(if $(GCPT_ELF),$(GCPT_ELF),$(SPEC2017_REPO_ROOT)/build/LibCheckpointAlpha/build/gcpt)
SPEC2017_GCPT_BIN ?= $(if $(GCPT_BIN),$(GCPT_BIN),$(SPEC2017_REPO_ROOT)/build/LibCheckpointAlpha/build/gcpt.bin)
SPEC2017_SBI_BUILD_DIR ?= $(if $(SBI_BUILD_DIR),$(SBI_BUILD_DIR),$(SPEC2017_REPO_ROOT)/build/opensbi)
SPEC2017_SBI_BIN ?= $(if $(SBI_BIN),$(SBI_BIN),$(SPEC2017_SBI_BUILD_DIR)/build/platform/generic/firmware/fw_jump.bin)
SPEC2017_BUILDROOT_CROSS_COMPILE ?= $(SPEC2017_BUILDROOT_DIR)/output/host/bin/riscv64-linux-
SPEC2017_DTC ?= $(SPEC2017_BUILDROOT_DIR)/output/host/bin/dtc
spec2017_case_dtb_memory = $(if $(SPEC2017_DTB_MEMORY),$(SPEC2017_DTB_MEMORY),$(if $(findstring _speed_,$(1)),$(SPEC2017_SPEED_DTB_MEMORY),$(SPEC2017_RATE_DTB_MEMORY)))
spec2017_case_dtb_profile = $(if $(SPEC2017_EXPLICIT_DEFAULT_DTB),,$(call spec2017_case_dtb_memory,$(1)))
spec2017_case_dtb_name = $(SPEC2017_DEFAULT_DTB)$(if $(call spec2017_case_dtb_profile,$(1)),-mem$(call spec2017_case_dtb_profile,$(1)))
spec2017_case_dtb_tag = $(subst /,_,$(call spec2017_case_dtb_name,$(1)))
spec2017_case_dtb_min_memory_bytes = $(if $(findstring _speed_,$(1)),$(SPEC2017_SPEED_DTB_MIN_MEMORY_BYTES),$(SPEC2017_RATE_DTB_MIN_MEMORY_BYTES))
spec2017_case_cfg = $(if $(SPEC2017_EXPLICIT_CFG),$(SPEC2017_CFG),$(if $(findstring _speed_,$(1)),$(SPEC2017_SPEED_CFG),$(SPEC2017_RATE_CFG)))
spec2017_case_cfg_hash = $(shell if [ -f "$(abspath $(call spec2017_case_cfg,$(1)))" ]; then sha256sum "$(abspath $(call spec2017_case_cfg,$(1)))" | cut -d ' ' -f 1; else printf 'missing'; fi)
SPEC2017_PYTHON := PYTHONDONTWRITEBYTECODE=1 python3
SPEC2017_BUILD_VARS_HASH := $(shell printf '%s\n' '$(SPEC2017_PROFILING)' '$(SPEC2017_TUNE)' '$(SPEC2017_CROSS_COMPILE)' '$(SPEC2017_COMPILER_ROOT)' '$(SPEC2017_GNU_TOOLCHAIN_ROOT)' | sha256sum | cut -d ' ' -f 1)
SPEC2017_CASE := $(shell $(SPEC2017_PYTHON) $(SPEC2017_HELPER) --resolve-case --bench '$(BENCH)' --input-set '$(SPEC2017_INPUT)' --mode '$(SPEC2017_MODE)' 2>/dev/null)
SPEC2017_ALL_CASES := $(shell $(SPEC2017_PYTHON) $(SPEC2017_HELPER) --list-cases --input-set all --mode all 2>/dev/null)
SPEC2017_SELECTED_CASES := $(shell $(SPEC2017_PYTHON) $(SPEC2017_HELPER) --list-cases --input-set $(SPEC2017_INPUT) --mode $(SPEC2017_MODE) 2>/dev/null)
SPEC2017_IMAGE_CASES := $(if $(BENCH),$(SPEC2017_CASE),$(shell $(SPEC2017_PYTHON) $(SPEC2017_HELPER) --list-cases --input-set $(SPEC2017_IMAGE_INPUT) --mode $(SPEC2017_IMAGE_MODE) 2>/dev/null))
SPEC2017_DTS_SOURCES := $(shell find $(SPEC2017_DTS_DIR) -type f 2>/dev/null)

WORKLOAD_DIRS += $(SPEC2017_BUILD_DIR)

spec2017-check-spec-iso:
	@if [ -z "$(SPEC2017_SOURCE_SPEC_ISO)" ]; then \
		echo "SPEC2017_ISO is required, for example:"; \
		echo "  make spec2017-prepare SPEC2017_ISO=/path/to/cpu2017.iso"; \
		echo "  make linux/spec2017 BENCH=mcf MODE=rate INPUT=ref SPEC2017_ISO=/path/to/cpu2017.iso -jN"; \
		echo "  make spec2017-images SPEC2017_ISO=/path/to/cpu2017.iso -jN"; \
		exit 1; \
	fi; \
	if ! [ -f "$(SPEC2017_SOURCE_SPEC_ISO)" ]; then \
		echo "SPEC2017 ISO path does not exist: $(SPEC2017_SOURCE_SPEC_ISO)"; \
		exit 1; \
	fi

spec2017-check-spec-config: spec2017-check-spec-iso
	@if [ "$(SPEC2017_EXPLICIT_CFG)" = 1 ]; then \
		if ! [ -f "$(SPEC2017_CFG)" ]; then \
			echo "SPEC2017 cfg does not exist: $(SPEC2017_CFG)"; \
			exit 1; \
		fi; \
	else \
		if ! [ -f "$(SPEC2017_RATE_CFG)" ]; then \
			echo "SPEC2017 rate cfg does not exist: $(SPEC2017_RATE_CFG)"; \
			exit 1; \
		fi; \
		if ! [ -f "$(SPEC2017_SPEED_CFG)" ]; then \
			echo "SPEC2017 speed cfg does not exist: $(SPEC2017_SPEED_CFG)"; \
			exit 1; \
		fi; \
	fi; \
	if [ -z "$(call spec2017_case_cfg,$(SPEC2017_CASE))" ] && [ -n "$(BENCH)" ]; then \
		echo "Cannot select SPEC2017 cfg for BENCH=$(BENCH), MODE=$(SPEC2017_MODE), INPUT=$(SPEC2017_INPUT)"; \
		exit 1; \
	fi; \
	case "$(SPEC2017_INPUT)" in \
		ref|refrate|refspeed|train|test|all) ;; \
		*) echo "SPEC2017_INPUT/INPUT must be one of: ref, refrate, refspeed, train, test, all"; exit 1 ;; \
	esac; \
	case "$(SPEC2017_MODE)" in \
		rate|speed|all) ;; \
		*) echo "SPEC2017_MODE/MODE must be one of: rate, speed, all"; exit 1 ;; \
	esac; \
	case "$(SPEC2017_PROFILING)" in \
		0|1) ;; \
		*) echo "SPEC2017_PROFILING/PROFILING must be 0 or 1"; exit 1 ;; \
	esac

spec2017-prepare: $(SPEC2017_PREPARE_STAMP)

$(SPEC2017_PREPARE_STAMP): $(SPEC2017_PREPARE_SCRIPT) | spec2017-check-spec-iso
	@printf '$(SPEC2017_PROGRESS_PREFIX) Preparing SPEC workspace at $(SPEC2017_PREPARED_SPEC_ROOT)\n'
	@bash "$(SPEC2017_PREPARE_SCRIPT)" "$(SPEC2017_SOURCE_SPEC_ISO)" "$(SPEC2017_PREPARED_SPEC_ROOT)"
	@touch "$@"

define add_spec2017_case
$(SPEC2017_BUILD_DIR)/$(1)/download/sentinel:
	@mkdir -p $$(@D)
	@touch $$@

$(SPEC2017_BUILD_DIR)/$(1)/cfg.$(call spec2017_case_cfg_hash,$(1)).stamp: | spec2017-check-spec-config
	@mkdir -p "$$(@D)"
	@printf '%s\n' "cfg=$(abspath $(call spec2017_case_cfg,$(1)))" > "$$@"

$(SPEC2017_BUILD_DIR)/$(1)/build-vars.$(SPEC2017_BUILD_VARS_HASH).stamp:
	@mkdir -p "$$(@D)"
	@printf '%s\n' "profiling=$(SPEC2017_PROFILING)" > "$$@"

$(SPEC2017_BUILD_DIR)/$(1)/elf/$(1).elf: $(SPEC2017_PREPARE_STAMP) $(SPEC2017_BUILD_DIR)/$(1)/cfg.$(call spec2017_case_cfg_hash,$(1)).stamp $$(SPEC2017_HELPER) $$(SPEC2017_WORKLOAD_DIR)/build.sh
	@mkdir -p "$$(dir $$@)"
	@WORKLOAD_DIR="$$(abspath $$(SPEC2017_WORKLOAD_DIR))" \
	WORKLOAD_BUILD_DIR="$$(abspath $(SPEC2017_BUILD_DIR)/$(1))" \
	PKG_DIR="$$(abspath $(SPEC2017_BUILD_DIR)/$(1)/package)" \
	CROSS_COMPILE="$$(SPEC2017_CROSS_COMPILE)" \
	SPEC2017_PROGRESS_K="$$(SPEC2017_PROGRESS_K)" \
	SPEC2017_PROGRESS_N="$$(SPEC2017_PROGRESS_N)" \
	SPEC2017_CASE="$(1)" \
	SPEC2017="$$(SPEC2017_PREPARED_SPEC_ROOT)" \
	SPEC2017_CFG="$(abspath $(call spec2017_case_cfg,$(1)))" \
	SPEC2017_COMPILER_ROOT="$$(SPEC2017_COMPILER_ROOT)" \
	SPEC2017_GNU_TOOLCHAIN_ROOT="$$(SPEC2017_GNU_TOOLCHAIN_ROOT)" \
	SPEC2017_TUNE="$$(SPEC2017_TUNE)" \
	SPEC2017_JOBS="$$(SPEC2017_JOBS)" \
	SPEC2017_ELF_ONLY=1 \
	SPEC2017_PROFILING="$$(SPEC2017_PROFILING)" \
	bash "$$(abspath $$(SPEC2017_WORKLOAD_DIR))/build.sh"

$(SPEC2017_BUILD_DIR)/$(1)/rootfs.cpio: $(SPEC2017_PREPARE_STAMP) $(SPEC2017_BUILD_DIR)/$(1)/cfg.$(call spec2017_case_cfg_hash,$(1)).stamp $$(SPEC2017_HELPER) $$(SPEC2017_WORKLOAD_DIR)/build.sh $(SPEC2017_BUILD_DIR)/$(1)/download/sentinel $(SPEC2017_BUILD_DIR)/$(1)/build-vars.$(SPEC2017_BUILD_VARS_HASH).stamp $$(SPEC2017_SCRIPTS_DIR)/build-workload-linux.sh
	@CROSS_COMPILE="$$(SPEC2017_CROSS_COMPILE)" \
	SPEC2017_PROGRESS_K="$$(SPEC2017_PROGRESS_K)" \
	SPEC2017_PROGRESS_N="$$(SPEC2017_PROGRESS_N)" \
	SPEC2017_CASE="$(1)" \
	SPEC2017="$$(SPEC2017_PREPARED_SPEC_ROOT)" \
	SPEC2017_CFG="$(abspath $(call spec2017_case_cfg,$(1)))" \
	SPEC2017_COMPILER_ROOT="$$(SPEC2017_COMPILER_ROOT)" \
	SPEC2017_GNU_TOOLCHAIN_ROOT="$$(SPEC2017_GNU_TOOLCHAIN_ROOT)" \
	SPEC2017_TUNE="$$(SPEC2017_TUNE)" \
	SPEC2017_JOBS="$$(SPEC2017_JOBS)" \
	SPEC2017_PROFILING="$$(SPEC2017_PROFILING)" \
	bash "$$(SPEC2017_SCRIPTS_DIR)/build-workload-linux.sh" "$$(SPEC2017_WORKLOAD_DIR)" "$(SPEC2017_BUILD_DIR)/$(1)"

$(SPEC2017_BUILD_DIR)/$(1)/firmware/dtb-$(call spec2017_case_dtb_tag,$(1)).stamp: spec2017-force
	@mkdir -p "$$(@D)"
	@printf '%s\n' \
		"case=$(1)" \
		"default_dtb=$$(SPEC2017_DEFAULT_DTB)" \
		"profile=$(call spec2017_case_dtb_profile,$(1))" \
		"min_memory_bytes=$(call spec2017_case_dtb_min_memory_bytes,$(1))" > "$$@.tmp"
	@if [ -f "$$@" ] && cmp -s "$$@.tmp" "$$@"; then rm "$$@.tmp"; else mv "$$@.tmp" "$$@"; fi

$(SPEC2017_BUILD_DIR)/$(1)/fw_payload.bin: $$(SPEC2017_DTS_SOURCES) $$(SPEC2017_GCPT_BIN) $$(SPEC2017_SCRIPTS_DIR)/build-firmware-linux.sh $(SPEC2017_BUILD_DIR)/$(1)/rootfs.cpio $$(SPEC2017_LINUX_IMAGE) $$(SPEC2017_SBI_BIN) $(SPEC2017_BUILD_DIR)/$(1)/firmware/dtb-$(call spec2017_case_dtb_tag,$(1)).stamp
	@printf '$(SPEC2017_PROGRESS_PREFIX) Assembling firmware for $(1)\n'
	@CROSS_COMPILE="$$(SPEC2017_BUILDROOT_CROSS_COMPILE)" \
	DTC="$$(SPEC2017_DTC)" \
	DEFAULT_DTB="$$(SPEC2017_DEFAULT_DTB)" \
	DTB_MEMORY_PROFILE="$(call spec2017_case_dtb_profile,$(1))" \
	DTB_MIN_MEMORY_BYTES="$(call spec2017_case_dtb_min_memory_bytes,$(1))" \
	SPEC2017_PROGRESS_K="$$(SPEC2017_PROGRESS_K)" \
	SPEC2017_PROGRESS_N="$$(SPEC2017_PROGRESS_N)" \
	bash "$$(SPEC2017_SCRIPTS_DIR)/build-firmware-linux.sh" "$$(SPEC2017_GCPT_BIN)" "$$(SPEC2017_SBI_BUILD_DIR)" "$$(SPEC2017_DTS_DIR)" "$$(SPEC2017_LINUX_IMAGE)" "$(SPEC2017_BUILD_DIR)/$(1)"

linux/$(1): $(SPEC2017_BUILD_DIR)/$(1)/fw_payload.bin

WORKLOAD_PHONY_TARGETS += linux/$(1)

$(SPEC2017_IMAGE_DIR)/stamps/$(1).images.stamp: $(SPEC2017_PREPARE_STAMP) $(SPEC2017_BUILD_DIR)/$(1)/cfg.$(call spec2017_case_cfg_hash,$(1)).stamp $$(SPEC2017_HELPER) $$(SPEC2017_WORKLOAD_DIR)/build.sh $(SPEC2017_BUILD_DIR)/$(1)/download/sentinel $(SPEC2017_BUILD_DIR)/$(1)/build-vars.$(SPEC2017_BUILD_VARS_HASH).stamp $$(SPEC2017_DTS_SOURCES) $$(SPEC2017_GCPT_BIN) $$(SPEC2017_GCPT_ELF) $$(SPEC2017_SCRIPTS_DIR)/build-firmware-linux.sh $$(SPEC2017_LINUX_IMAGE) $$(SPEC2017_SBI_BIN) | spec2017-check-spec-config
	@printf '$(SPEC2017_PROGRESS_PREFIX) Packaging split run images for $(1)\n'
	@WORKLOAD_DIR="$$(abspath $$(SPEC2017_WORKLOAD_DIR))" \
	WORKLOAD_BUILD_DIR="$$(abspath $(SPEC2017_BUILD_DIR)/$(1))" \
	PKG_DIR="$$(abspath $(SPEC2017_BUILD_DIR)/$(1)/package)" \
	CROSS_COMPILE="$$(SPEC2017_CROSS_COMPILE)" \
	SPEC2017_PROGRESS_K="$$(SPEC2017_PROGRESS_K)" \
	SPEC2017_PROGRESS_N="$$(SPEC2017_PROGRESS_N)" \
	SPEC2017_CASE="$(1)" \
	SPEC2017="$$(SPEC2017_PREPARED_SPEC_ROOT)" \
	SPEC2017_CFG="$(abspath $(call spec2017_case_cfg,$(1)))" \
	SPEC2017_COMPILER_ROOT="$$(SPEC2017_COMPILER_ROOT)" \
	SPEC2017_GNU_TOOLCHAIN_ROOT="$$(SPEC2017_GNU_TOOLCHAIN_ROOT)" \
	SPEC2017_TUNE="$$(SPEC2017_TUNE)" \
	SPEC2017_JOBS="$$(SPEC2017_JOBS)" \
	SPEC2017_ALL_RUNS=1 \
	SPEC2017_PROFILING="$$(SPEC2017_PROFILING)" \
	bash "$$(abspath $$(SPEC2017_WORKLOAD_DIR))/build.sh"
	@printf '$(SPEC2017_PROGRESS_PREFIX) Exporting $(1) split artifacts to $(SPEC2017_IMAGE_DIR)\n'
	@mkdir -p "$(SPEC2017_IMAGE_DIR)/bin" "$(SPEC2017_IMAGE_DIR)/kernel" "$(SPEC2017_IMAGE_DIR)/elf" "$(SPEC2017_IMAGE_DIR)/cmd" "$(SPEC2017_IMAGE_DIR)/rootfs" "$(SPEC2017_IMAGE_DIR)/cfg" "$(SPEC2017_IMAGE_DIR)/gcpt" "$(SPEC2017_IMAGE_DIR)/logs/build_elf" "$(SPEC2017_IMAGE_DIR)/stamps"
	@if [ ! -f "$(SPEC2017_IMAGE_DIR)/cfg/$(notdir $(call spec2017_case_cfg,$(1)))" ]; then \
		cp "$(abspath $(call spec2017_case_cfg,$(1)))" "$(SPEC2017_IMAGE_DIR)/cfg/$(notdir $(call spec2017_case_cfg,$(1)))"; \
	fi
	@if [ ! -f "$(SPEC2017_IMAGE_DIR)/gcpt/gcpt.elf" ] || [ ! -f "$(SPEC2017_IMAGE_DIR)/gcpt/gcpt.bin" ]; then \
		cp "$(SPEC2017_GCPT_ELF)" "$(SPEC2017_IMAGE_DIR)/gcpt/gcpt.elf"; \
		cp "$(SPEC2017_GCPT_BIN)" "$(SPEC2017_IMAGE_DIR)/gcpt/gcpt.bin"; \
	fi
	@rm -f "$(SPEC2017_IMAGE_DIR)/elf/$(1)"_*.elf
	@cp "$(SPEC2017_BUILD_DIR)/$(1)/elf/$(1).elf" "$(SPEC2017_IMAGE_DIR)/elf/$(1).elf"
	@cp "$(SPEC2017_BUILD_DIR)/$(1)/logs/build_elf/build.log" "$(SPEC2017_IMAGE_DIR)/logs/build_elf/$(1).log"
	@$(SPEC2017_PYTHON) "$(SPEC2017_HELPER)" --list-packaged-variants --out-dir "$(SPEC2017_BUILD_DIR)/$(1)" | while IFS="	" read -r variant build_dir; do \
		printf '$(SPEC2017_PROGRESS_PREFIX) Assembling firmware for %s\n' "$$$$variant"; \
		rm -f "$$$$build_dir/rootfs.cpio"; \
		(cd "$$$$build_dir/package" && find . | fakeroot cpio -o -H newc > "$$$$build_dir/rootfs.cpio" 2>/dev/null); \
		CROSS_COMPILE="$$(SPEC2017_BUILDROOT_CROSS_COMPILE)" \
		DTC="$$(SPEC2017_DTC)" \
		DEFAULT_DTB="$$(SPEC2017_DEFAULT_DTB)" \
		DTB_MEMORY_PROFILE="$(call spec2017_case_dtb_profile,$(1))" \
		DTB_MIN_MEMORY_BYTES="$(call spec2017_case_dtb_min_memory_bytes,$(1))" \
		SPEC2017_PROGRESS_K="$$(SPEC2017_PROGRESS_K)" \
		SPEC2017_PROGRESS_N="$$(SPEC2017_PROGRESS_N)" \
		bash "$$(SPEC2017_SCRIPTS_DIR)/build-firmware-linux.sh" "$$(SPEC2017_GCPT_BIN)" "$$(SPEC2017_SBI_BUILD_DIR)" "$$(SPEC2017_DTS_DIR)" "$$(SPEC2017_LINUX_IMAGE)" "$$$$build_dir"; \
		cp "$$$$build_dir/package/spec/run.sh" "$(SPEC2017_IMAGE_DIR)/cmd/$$$$variant.run.sh"; \
		cp "$$(SPEC2017_LINUX_IMAGE)" "$(SPEC2017_IMAGE_DIR)/kernel/$$$$variant.Image"; \
		cp "$$$$build_dir/rootfs.cpio" "$(SPEC2017_IMAGE_DIR)/rootfs/$$$$variant.rootfs.cpio"; \
		cp "$$$$build_dir/fw_payload.bin" "$(SPEC2017_IMAGE_DIR)/bin/$$$$variant.fw_payload.bin"; \
	done
	@touch "$$@"
endef

$(foreach case,$(SPEC2017_ALL_CASES),$(eval $(call add_spec2017_case,$(case))))

linux/spec2017: spec2017-check-spec-config
	@if [ -z "$(BENCH)" ]; then \
		echo "Usage: make linux/spec2017 BENCH=mcf MODE=rate INPUT=ref SPEC2017_ISO=/path/to/cpu2017.iso -jN"; \
		echo "   or: make linux/spec2017 BENCH=mcf_rate_refrate SPEC2017_ISO=/path/to/cpu2017.iso -jN"; \
		exit 1; \
	fi; \
	if [ -z "$(SPEC2017_CASE)" ]; then \
		echo "Cannot resolve SPEC2017 case from BENCH=$(BENCH), MODE=$(SPEC2017_MODE), INPUT=$(SPEC2017_INPUT)"; \
		exit 1; \
	fi
	@$(MAKE) --no-print-directory -f "$(SPEC2017_RECURSE_MAKEFILE)" GCPT_DEFAULT_DTB="$(SPEC2017_DEFAULT_DTB)" $(SPEC2017_BUILD_DIR)/$(SPEC2017_CASE)/fw_payload.bin

spec2017-elf: spec2017-check-spec-config
	@if [ -z "$(BENCH)" ]; then \
		echo "Usage: make spec2017-elf BENCH=mcf MODE=rate INPUT=ref SPEC2017_ISO=/path/to/cpu2017.iso -jN"; \
		exit 1; \
	fi; \
	if [ -z "$(SPEC2017_CASE)" ]; then \
		echo "Cannot resolve SPEC2017 case from BENCH=$(BENCH), MODE=$(SPEC2017_MODE), INPUT=$(SPEC2017_INPUT)"; \
		exit 1; \
	fi
	@$(MAKE) --no-print-directory -f "$(SPEC2017_RECURSE_MAKEFILE)" $(SPEC2017_BUILD_DIR)/$(SPEC2017_CASE)/elf/$(SPEC2017_CASE).elf

spec2017-elfs: spec2017-check-spec-config
	@if [ -z "$(SPEC2017_SELECTED_CASES)" ]; then \
		echo "No SPEC2017 cases selected by SPEC2017_INPUT=$(SPEC2017_INPUT) SPEC2017_MODE=$(SPEC2017_MODE)"; \
		exit 1; \
	fi; \
	total="$(words $(SPEC2017_SELECTED_CASES))"; \
	i=0; \
	for case in $(SPEC2017_SELECTED_CASES); do \
		i=$$((i + 1)); \
		SPEC2017_PROGRESS_K="$$i" SPEC2017_PROGRESS_N="$$total" $(MAKE) --no-print-directory -f "$(SPEC2017_RECURSE_MAKEFILE)" "$(SPEC2017_BUILD_DIR)/$$case/elf/$$case.elf" || exit $$?; \
	done

spec2017-images: spec2017-check-spec-config
	@if [ -n "$(BENCH)" ] && [ -z "$(SPEC2017_CASE)" ]; then \
		echo "Cannot resolve SPEC2017 case from BENCH=$(BENCH), MODE=$(SPEC2017_MODE), INPUT=$(SPEC2017_INPUT)"; \
		exit 1; \
	fi; \
	if [ -z "$(SPEC2017_IMAGE_CASES)" ]; then \
		echo "No SPEC2017 cases selected by SPEC2017_IMAGE_INPUT=$(SPEC2017_IMAGE_INPUT) SPEC2017_IMAGE_MODE=$(SPEC2017_IMAGE_MODE)"; \
		exit 1; \
		fi; \
		rm -rf "$(SPEC2017_IMAGE_DIR)/bin" "$(SPEC2017_IMAGE_DIR)/kernel" "$(SPEC2017_IMAGE_DIR)/elf" "$(SPEC2017_IMAGE_DIR)/cmd" "$(SPEC2017_IMAGE_DIR)/rootfs" "$(SPEC2017_IMAGE_DIR)/cfg" "$(SPEC2017_IMAGE_DIR)/gcpt" "$(SPEC2017_IMAGE_DIR)/logs" "$(SPEC2017_IMAGE_DIR)/stamps"; \
	total="$(words $(SPEC2017_IMAGE_CASES))"; \
	i=0; \
	for case in $(SPEC2017_IMAGE_CASES); do \
		i=$$((i + 1)); \
		SPEC2017_PROGRESS_K="$$i" SPEC2017_PROGRESS_N="$$total" $(MAKE) --no-print-directory -f "$(SPEC2017_RECURSE_MAKEFILE)" GCPT_DEFAULT_DTB="$(SPEC2017_DEFAULT_DTB)" "$(SPEC2017_IMAGE_DIR)/stamps/$$case.images.stamp" || exit $$?; \
	done
	@printf '[spec2017 %s/%s] Output written to %s\n' "$(words $(SPEC2017_IMAGE_CASES))" "$(words $(SPEC2017_IMAGE_CASES))" "$(abspath $(SPEC2017_IMAGE_DIR))"

.PHONY: linux/spec2017 spec2017-check-spec-iso spec2017-check-spec-config spec2017-prepare spec2017-elf spec2017-elfs spec2017-images spec2017-force
