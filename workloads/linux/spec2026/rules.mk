SPEC2026_WORKLOAD_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SPEC2026_REPO_ROOT := $(abspath $(SPEC2026_WORKLOAD_DIR)/../../..)
SPEC2026_SELF_MAKEFILE := $(SPEC2026_WORKLOAD_DIR)/rules.mk
SPEC2026_ROOT_MAKEFILE := $(SPEC2026_REPO_ROOT)/Makefile
SPEC2026_RECURSE_MAKEFILE := $(if $(filter $(SPEC2026_ROOT_MAKEFILE),$(abspath $(firstword $(MAKEFILE_LIST)))),$(SPEC2026_ROOT_MAKEFILE),$(SPEC2026_SELF_MAKEFILE))
SPEC2026_SCRIPTS_DIR := $(SPEC2026_REPO_ROOT)/scripts
SPEC2026_DTS_DIR := $(SPEC2026_REPO_ROOT)/dts
SPEC2026_BUILD_DIR ?= $(SPEC2026_REPO_ROOT)/build/linux-workloads/spec2026
SPEC2026_CFG ?= $(SPEC2026_WORKLOAD_DIR)/riscv_gcc15_base.cfg
SPEC2026_HELPER := $(SPEC2026_WORKLOAD_DIR)/spec2026-package.py
SPEC2026_IMAGE_DIR ?= $(SPEC2026_REPO_ROOT)/build/images/$(if $(filter rate,$(SPEC2026_IMAGE_MODE)),spec2026rate,$(if $(filter speed,$(SPEC2026_IMAGE_MODE)),spec2026speed,spec2026))
SPEC2026_IMAGE_RATE_DIR ?= $(SPEC2026_REPO_ROOT)/build/images/spec2026rate
SPEC2026_IMAGE_SPEED_DIR ?= $(SPEC2026_REPO_ROOT)/build/images/spec2026speed
SPEC2026_SOURCE_SPEC_ISO := $(SPEC2026_ISO)
SPEC2026_PREPARED_SPEC_ROOT := $(SPEC2026_BUILD_DIR)/spec-src
SPEC2026_SOURCE_SPEC_HASH := $(shell printf '%s\n' "$(SPEC2026_SOURCE_SPEC_ISO)" | sha256sum | cut -d ' ' -f 1)
SPEC2026_PREPARE_STAMP := $(SPEC2026_BUILD_DIR)/spec-src.$(SPEC2026_SOURCE_SPEC_HASH).prepared
SPEC2026_PREPARE_SCRIPT := $(SPEC2026_WORKLOAD_DIR)/prepare-spec-workspace.sh
SPEC2026_CROSS_COMPILE ?= riscv64-unknown-linux-gnu-
SPEC2026_TUNE ?= base
SPEC2026_JOBS ?= $(shell nproc)
SPEC2026_INPUT ?= $(if $(INPUT),$(INPUT),ref)
SPEC2026_MODE ?= $(if $(MODE),$(MODE),rate)
SPEC2026_IMAGE_INPUT ?= $(if $(IMAGE_INPUT),$(IMAGE_INPUT),$(SPEC2026_INPUT))
SPEC2026_IMAGE_MODE ?= $(if $(IMAGE_MODE),$(IMAGE_MODE),$(SPEC2026_MODE))
SPEC2026_PROGRESS_K ?= 1
SPEC2026_PROGRESS_N ?= 1
SPEC2026_PROGRESS_PREFIX := [spec2026 $(SPEC2026_PROGRESS_K)/$(SPEC2026_PROGRESS_N)]
SPEC2026_BUILDROOT_DIR ?= $(if $(BUILDROOT_DIR),$(BUILDROOT_DIR),$(SPEC2026_REPO_ROOT)/build/buildroot)
SPEC2026_LINUX_IMAGE ?= $(if $(LINUX_IMAGE),$(LINUX_IMAGE),$(SPEC2026_BUILDROOT_DIR)/output/images/Image)
SPEC2026_GCPT_ELF ?= $(if $(GCPT_ELF),$(GCPT_ELF),$(SPEC2026_REPO_ROOT)/build/LibCheckpointAlpha/build/gcpt)
SPEC2026_GCPT_BIN ?= $(if $(GCPT_BIN),$(GCPT_BIN),$(SPEC2026_REPO_ROOT)/build/LibCheckpointAlpha/build/gcpt.bin)
SPEC2026_SBI_BUILD_DIR ?= $(if $(SBI_BUILD_DIR),$(SBI_BUILD_DIR),$(SPEC2026_REPO_ROOT)/build/opensbi)
SPEC2026_SBI_BIN ?= $(if $(SBI_BIN),$(SBI_BIN),$(SPEC2026_SBI_BUILD_DIR)/build/platform/generic/firmware/fw_jump.bin)
SPEC2026_BUILDROOT_CROSS_COMPILE ?= $(SPEC2026_BUILDROOT_DIR)/output/host/bin/riscv64-linux-
SPEC2026_DTC ?= $(SPEC2026_BUILDROOT_DIR)/output/host/bin/dtc
SPEC2026_EXPLICIT_DEFAULT_DTB := $(if $(filter undefined,$(origin DEFAULT_DTB)),,1)
SPEC2026_DEFAULT_DTB ?= $(if $(DEFAULT_DTB),$(DEFAULT_DTB),xiangshan-fpga-noAIA)
SPEC2026_RATE_DTB_MEMORY ?= 8g
SPEC2026_SPEED_DTB_MEMORY ?= 64g
SPEC2026_DTB_MEMORY ?=
SPEC2026_RATE_DTB_MIN_MEMORY_BYTES ?= 8589934592
SPEC2026_SPEED_DTB_MIN_MEMORY_BYTES ?= 68719476736
SPEC2026_ALL_CASES := $(shell python3 $(SPEC2026_HELPER) --list-cases --mode all 2>/dev/null)
SPEC2026_SELECTED_CASES := $(shell python3 $(SPEC2026_HELPER) --list-cases --input-set $(SPEC2026_INPUT) --mode $(SPEC2026_MODE) 2>/dev/null)
SPEC2026_IMAGE_CASES := $(if $(BENCH),$(BENCH),$(shell python3 $(SPEC2026_HELPER) --list-cases --input-set $(SPEC2026_IMAGE_INPUT) --mode $(SPEC2026_IMAGE_MODE) 2>/dev/null))
SPEC2026_DTS_SOURCES := $(shell find $(SPEC2026_DTS_DIR) -type f 2>/dev/null)
SPEC2026_CFG_HASH := $(shell if [ -f "$(abspath $(SPEC2026_CFG))" ]; then sha256sum "$(abspath $(SPEC2026_CFG))" | cut -d ' ' -f 1; else printf 'missing'; fi)
SPEC2026_BUILD_VARS_HASH := $(shell printf '%s\n' '$(SPEC2026_INPUT)' '$(SPEC2026_TUNE)' '$(SPEC2026_JOBS)' '$(SPEC2026_CROSS_COMPILE)' | sha256sum | cut -d ' ' -f 1)

spec2026_case_dtb_memory = $(if $(SPEC2026_DTB_MEMORY),$(SPEC2026_DTB_MEMORY),$(if $(filter %_s,$(1)),$(SPEC2026_SPEED_DTB_MEMORY),$(SPEC2026_RATE_DTB_MEMORY)))
spec2026_case_dtb_profile = $(if $(SPEC2026_EXPLICIT_DEFAULT_DTB),,$(call spec2026_case_dtb_memory,$(1)))
spec2026_case_dtb_name = $(SPEC2026_DEFAULT_DTB)$(if $(call spec2026_case_dtb_profile,$(1)),-mem$(call spec2026_case_dtb_profile,$(1)))
spec2026_case_dtb_tag = $(subst /,_,$(call spec2026_case_dtb_name,$(1)))
spec2026_case_dtb_min_memory_bytes = $(if $(filter %_s,$(1)),$(SPEC2026_SPEED_DTB_MIN_MEMORY_BYTES),$(SPEC2026_RATE_DTB_MIN_MEMORY_BYTES))
spec2026_case_image_dir = $(SPEC2026_IMAGE_DIR)
spec2026_case_image_stamp = $(call spec2026_case_image_dir,$(1))/stamps/$(1).images.stamp

WORKLOAD_DIRS += $(SPEC2026_BUILD_DIR)

spec2026-check-spec-iso:
	@if [ -z "$(SPEC2026_SOURCE_SPEC_ISO)" ]; then \
		echo "SPEC2026_ISO is required, for example:"; \
		echo "  make linux/spec2026 BENCH=706.stockfish_r SPEC2026_ISO=/path/to/cpu2026-1.0.1.iso -jN"; \
		exit 1; \
	fi; \
	if ! [ -f "$(SPEC2026_SOURCE_SPEC_ISO)" ]; then \
		echo "SPEC ISO path does not exist: $(SPEC2026_SOURCE_SPEC_ISO)"; \
		exit 1; \
	fi; \
	if ! [ -f "$(SPEC2026_CFG)" ]; then \
		echo "SPEC2026 cfg does not exist: $(SPEC2026_CFG)"; \
		exit 1; \
	fi; \
	case "$(SPEC2026_INPUT)" in \
		ref|train|test|all) ;; \
		*) echo "SPEC2026_INPUT must be one of: ref, train, test, all"; exit 1 ;; \
	esac; \
	case "$(SPEC2026_IMAGE_INPUT)" in \
		ref|train|test|all) ;; \
		*) echo "SPEC2026_IMAGE_INPUT must be one of: ref, train, test, all"; exit 1 ;; \
	esac; \
	case "$(SPEC2026_MODE)" in \
		rate|speed|all) ;; \
		*) echo "SPEC2026_MODE/MODE must be one of: rate, speed, all"; exit 1 ;; \
	esac; \
	case "$(SPEC2026_IMAGE_MODE)" in \
		rate|speed|all) ;; \
		*) echo "SPEC2026_IMAGE_MODE must be one of: rate, speed, all"; exit 1 ;; \
	esac

spec2026-force:

spec2026-prepare: $(SPEC2026_PREPARE_STAMP)

$(SPEC2026_PREPARE_STAMP): $(SPEC2026_PREPARE_SCRIPT) $(SPEC2026_SOURCE_SPEC_ISO) | spec2026-check-spec-iso
	@printf '$(SPEC2026_PROGRESS_PREFIX) Preparing SPEC workspace at $(SPEC2026_PREPARED_SPEC_ROOT)\n'
	@bash "$(SPEC2026_PREPARE_SCRIPT)" "$(SPEC2026_SOURCE_SPEC_ISO)" "$(SPEC2026_PREPARED_SPEC_ROOT)"
	@touch "$@"

define add_spec2026_case
$(SPEC2026_BUILD_DIR)/$(1)/download/sentinel:
	@mkdir -p "$$(@D)"
	@touch "$$@"

$(SPEC2026_BUILD_DIR)/$(1)/cfg.$(SPEC2026_CFG_HASH).stamp: | spec2026-check-spec-iso
	@mkdir -p "$$(@D)"
	@printf '%s\n' "cfg=$(abspath $(SPEC2026_CFG))" > "$$@"

$(SPEC2026_BUILD_DIR)/$(1)/build-vars.$(SPEC2026_BUILD_VARS_HASH).stamp:
	@mkdir -p "$$(@D)"
	@printf '%s\n' "input=$(SPEC2026_INPUT)" "tune=$(SPEC2026_TUNE)" "jobs=$(SPEC2026_JOBS)" "cross_compile=$(SPEC2026_CROSS_COMPILE)" > "$$@"

$(SPEC2026_BUILD_DIR)/$(1)/firmware/dtb-$(call spec2026_case_dtb_tag,$(1)).stamp: spec2026-force
	@mkdir -p "$$(@D)"
	@printf '%s\n' \
		"case=$(1)" \
		"default_dtb=$$(SPEC2026_DEFAULT_DTB)" \
		"profile=$(call spec2026_case_dtb_profile,$(1))" \
		"min_memory_bytes=$(call spec2026_case_dtb_min_memory_bytes,$(1))" > "$$@.tmp"
	@if [ -f "$$@" ] && cmp -s "$$@.tmp" "$$@"; then rm "$$@.tmp"; else mv "$$@.tmp" "$$@"; fi

$(SPEC2026_BUILD_DIR)/$(1)/elf/$(1).elf: $(SPEC2026_PREPARE_STAMP) $(SPEC2026_BUILD_DIR)/$(1)/cfg.$(SPEC2026_CFG_HASH).stamp $(SPEC2026_BUILD_DIR)/$(1)/build-vars.$(SPEC2026_BUILD_VARS_HASH).stamp $$(SPEC2026_HELPER) $$(SPEC2026_WORKLOAD_DIR)/build.sh
	@mkdir -p "$$(dir $$@)"
	@WORKLOAD_DIR="$$(abspath $$(SPEC2026_WORKLOAD_DIR))" \
	WORKLOAD_BUILD_DIR="$$(abspath $(SPEC2026_BUILD_DIR)/$(1))" \
	PKG_DIR="$$(abspath $(SPEC2026_BUILD_DIR)/$(1)/package)" \
	CROSS_COMPILE="$$(SPEC2026_CROSS_COMPILE)" \
	SPEC2026_PROGRESS_K="$$(SPEC2026_PROGRESS_K)" \
	SPEC2026_PROGRESS_N="$$(SPEC2026_PROGRESS_N)" \
	SPEC2026_CASE="$(1)" \
	SPEC2026="$$(SPEC2026_PREPARED_SPEC_ROOT)" \
	SPEC2026_CFG="$$(abspath $$(SPEC2026_CFG))" \
	SPEC2026_TUNE="$$(SPEC2026_TUNE)" \
	SPEC2026_JOBS="$$(SPEC2026_JOBS)" \
	SPEC2026_ELF_ONLY=1 \
	bash "$$(abspath $$(SPEC2026_WORKLOAD_DIR))/build.sh"

$(SPEC2026_BUILD_DIR)/$(1)/rootfs.cpio: $(SPEC2026_PREPARE_STAMP) $(SPEC2026_BUILD_DIR)/$(1)/cfg.$(SPEC2026_CFG_HASH).stamp $(SPEC2026_BUILD_DIR)/$(1)/build-vars.$(SPEC2026_BUILD_VARS_HASH).stamp $$(SPEC2026_HELPER) $$(SPEC2026_WORKLOAD_DIR)/build.sh $(SPEC2026_BUILD_DIR)/$(1)/download/sentinel $$(SPEC2026_SCRIPTS_DIR)/build-workload-linux.sh
	@CROSS_COMPILE="$$(SPEC2026_CROSS_COMPILE)" \
	SPEC2026_PROGRESS_K="$$(SPEC2026_PROGRESS_K)" \
	SPEC2026_PROGRESS_N="$$(SPEC2026_PROGRESS_N)" \
	SPEC2026_CASE="$(1)" \
	SPEC2026="$$(SPEC2026_PREPARED_SPEC_ROOT)" \
	SPEC2026_CFG="$$(abspath $$(SPEC2026_CFG))" \
	SPEC2026_INPUT="$$(SPEC2026_INPUT)" \
	SPEC2026_TUNE="$$(SPEC2026_TUNE)" \
	SPEC2026_JOBS="$$(SPEC2026_JOBS)" \
	bash "$$(SPEC2026_SCRIPTS_DIR)/build-workload-linux.sh" "$$(SPEC2026_WORKLOAD_DIR)" "$(SPEC2026_BUILD_DIR)/$(1)"

$(SPEC2026_BUILD_DIR)/$(1)/fw_payload.bin: $$(SPEC2026_DTS_SOURCES) $(SPEC2026_BUILD_DIR)/$(1)/firmware/dtb-$(call spec2026_case_dtb_tag,$(1)).stamp $$(SPEC2026_GCPT_BIN) $$(SPEC2026_SCRIPTS_DIR)/build-firmware-linux.sh $(SPEC2026_BUILD_DIR)/$(1)/rootfs.cpio $$(SPEC2026_LINUX_IMAGE) $$(SPEC2026_SBI_BIN)
	@printf '$(SPEC2026_PROGRESS_PREFIX) Assembling firmware for $(1)\n'
	@CROSS_COMPILE="$$(SPEC2026_BUILDROOT_CROSS_COMPILE)" \
	DTC="$$(SPEC2026_DTC)" \
	DEFAULT_DTB="$$(SPEC2026_DEFAULT_DTB)" \
	DTB_MEMORY_PROFILE="$(call spec2026_case_dtb_profile,$(1))" \
	DTB_MIN_MEMORY_BYTES="$(call spec2026_case_dtb_min_memory_bytes,$(1))" \
	SPEC2026_PROGRESS_K="$$(SPEC2026_PROGRESS_K)" \
	SPEC2026_PROGRESS_N="$$(SPEC2026_PROGRESS_N)" \
	bash "$$(SPEC2026_SCRIPTS_DIR)/build-firmware-linux.sh" "$$(SPEC2026_GCPT_BIN)" "$$(SPEC2026_SBI_BUILD_DIR)" "$$(SPEC2026_DTS_DIR)" "$$(SPEC2026_LINUX_IMAGE)" "$(SPEC2026_BUILD_DIR)/$(1)"

linux/$(1): $(SPEC2026_BUILD_DIR)/$(1)/fw_payload.bin

WORKLOAD_PHONY_TARGETS += linux/$(1)

$(call spec2026_case_image_stamp,$(1)): $(SPEC2026_BUILD_DIR)/$(1)/fw_payload.bin $(SPEC2026_GCPT_ELF) $(SPEC2026_GCPT_BIN) $(SPEC2026_LINUX_IMAGE) | spec2026-check-spec-iso
	@printf '$(SPEC2026_PROGRESS_PREFIX) Exporting $(1) artifacts to $(call spec2026_case_image_dir,$(1))\n'
	@mkdir -p "$(call spec2026_case_image_dir,$(1))/bin" "$(call spec2026_case_image_dir,$(1))/kernel" "$(call spec2026_case_image_dir,$(1))/rootfs" "$(call spec2026_case_image_dir,$(1))/elf" "$(call spec2026_case_image_dir,$(1))/cmd" "$(call spec2026_case_image_dir,$(1))/cfg" "$(call spec2026_case_image_dir,$(1))/gcpt" "$(call spec2026_case_image_dir,$(1))/logs/build_elf" "$(call spec2026_case_image_dir,$(1))/stamps"
	@cp "$(SPEC2026_CFG)" "$(call spec2026_case_image_dir,$(1))/cfg/$(notdir $(SPEC2026_CFG))"
	@cp "$(SPEC2026_GCPT_ELF)" "$(call spec2026_case_image_dir,$(1))/gcpt/gcpt.elf"
	@cp "$(SPEC2026_GCPT_BIN)" "$(call spec2026_case_image_dir,$(1))/gcpt/gcpt.bin"
	@cp "$(SPEC2026_BUILD_DIR)/$(1)/elf/$(1).elf" "$(call spec2026_case_image_dir,$(1))/elf/$(1).elf"
	@cp "$(SPEC2026_BUILD_DIR)/$(1)/logs/build_elf/build.log" "$(call spec2026_case_image_dir,$(1))/logs/build_elf/$(1).log"
	@cp "$(SPEC2026_LINUX_IMAGE)" "$(call spec2026_case_image_dir,$(1))/kernel/$(1).Image"
	@cp "$(SPEC2026_BUILD_DIR)/$(1)/rootfs.cpio" "$(call spec2026_case_image_dir,$(1))/rootfs/$(1).rootfs.cpio"
	@cp "$(SPEC2026_BUILD_DIR)/$(1)/fw_payload.bin" "$(call spec2026_case_image_dir,$(1))/bin/$(1).fw_payload.bin"
	@cp "$(SPEC2026_BUILD_DIR)/$(1)/package/spec/run.sh" "$(call spec2026_case_image_dir,$(1))/cmd/$(1).run.sh"
	@touch "$$@"
endef

$(foreach case,$(SPEC2026_ALL_CASES),$(eval $(call add_spec2026_case,$(case))))

linux/spec2026: spec2026-check-spec-iso
	@if [ -z "$(BENCH)" ]; then \
		echo "Usage: make linux/spec2026 BENCH=706.stockfish_r SPEC2026_ISO=/path/to/cpu2026-1.0.1.iso -jN"; \
		exit 1; \
	fi
	@$(MAKE) --no-print-directory -f "$(SPEC2026_RECURSE_MAKEFILE)" GCPT_DEFAULT_DTB="$(SPEC2026_DEFAULT_DTB)" $(SPEC2026_BUILD_DIR)/$(BENCH)/fw_payload.bin

spec2026-elf: spec2026-check-spec-iso
	@if [ -z "$(BENCH)" ]; then \
		echo "Usage: make spec2026-elf BENCH=706.stockfish_r SPEC2026_ISO=/path/to/cpu2026-1.0.1.iso -jN"; \
		exit 1; \
	fi
	@$(MAKE) --no-print-directory -f "$(SPEC2026_RECURSE_MAKEFILE)" $(SPEC2026_BUILD_DIR)/$(BENCH)/elf/$(BENCH).elf

spec2026-elfs: spec2026-check-spec-iso
	@if [ -z "$(SPEC2026_SELECTED_CASES)" ]; then \
		echo "No SPEC2026 cases selected by SPEC2026_INPUT=$(SPEC2026_INPUT)"; \
		exit 1; \
	fi; \
	for case in $(SPEC2026_SELECTED_CASES); do \
		$(MAKE) --no-print-directory -f "$(SPEC2026_RECURSE_MAKEFILE)" "$(SPEC2026_BUILD_DIR)/$$case/elf/$$case.elf" || exit $$?; \
	done

spec2026-images: spec2026-check-spec-iso
	@if [ -n "$(BENCH)" ] && [ -z "$(filter $(BENCH),$(SPEC2026_ALL_CASES))" ]; then \
		echo "Unknown SPEC2026 case BENCH=$(BENCH)"; \
		exit 1; \
	fi; \
	if [ -z "$(SPEC2026_IMAGE_CASES)" ]; then \
		echo "No SPEC2026 cases selected by SPEC2026_IMAGE_INPUT=$(SPEC2026_IMAGE_INPUT), SPEC2026_IMAGE_MODE=$(SPEC2026_IMAGE_MODE)"; \
		exit 1; \
	fi; \
	rm -rf "$(SPEC2026_IMAGE_DIR)/bin" "$(SPEC2026_IMAGE_DIR)/kernel" "$(SPEC2026_IMAGE_DIR)/rootfs" "$(SPEC2026_IMAGE_DIR)/elf" "$(SPEC2026_IMAGE_DIR)/cmd" "$(SPEC2026_IMAGE_DIR)/cfg" "$(SPEC2026_IMAGE_DIR)/gcpt" "$(SPEC2026_IMAGE_DIR)/logs" "$(SPEC2026_IMAGE_DIR)/stamps"; \
	total="$(words $(SPEC2026_IMAGE_CASES))"; \
	i=0; \
	for case in $(SPEC2026_IMAGE_CASES); do \
		i=$$((i + 1)); \
		SPEC2026_INPUT="$(SPEC2026_IMAGE_INPUT)" SPEC2026_PROGRESS_K="$$i" SPEC2026_PROGRESS_N="$$total" $(MAKE) --no-print-directory -f "$(SPEC2026_RECURSE_MAKEFILE)" GCPT_DEFAULT_DTB="$(SPEC2026_DEFAULT_DTB)" "$(call spec2026_case_image_stamp,$$case)" || exit $$?; \
	done
	@printf '[spec2026 %s/%s] Output written to %s\n' "$(words $(SPEC2026_IMAGE_CASES))" "$(words $(SPEC2026_IMAGE_CASES))" "$(abspath $(SPEC2026_IMAGE_DIR))"

.PHONY: linux/spec2026 spec2026-check-spec-iso spec2026-prepare spec2026-elf spec2026-elfs spec2026-images spec2026-force
