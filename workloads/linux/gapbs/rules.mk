GAPBS_WORKLOAD_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
GAPBS_REPO_ROOT := $(abspath $(GAPBS_WORKLOAD_DIR)/../../..)
GAPBS_SELF_MAKEFILE := $(GAPBS_WORKLOAD_DIR)/rules.mk
GAPBS_ROOT_MAKEFILE := $(GAPBS_REPO_ROOT)/Makefile
GAPBS_RECURSE_MAKEFILE := $(if $(filter $(GAPBS_ROOT_MAKEFILE),$(abspath $(firstword $(MAKEFILE_LIST)))),$(GAPBS_ROOT_MAKEFILE),$(GAPBS_SELF_MAKEFILE))
GAPBS_SCRIPTS_DIR := $(GAPBS_REPO_ROOT)/scripts
GAPBS_DTS_DIR := $(GAPBS_REPO_ROOT)/dts
GAPBS_BUILD_DIR ?= $(GAPBS_REPO_ROOT)/build/linux-workloads/gapbs
GAPBS_IMAGE_DIR ?= $(GAPBS_REPO_ROOT)/build/images/gapbs
GAPBS_HELPER := $(GAPBS_WORKLOAD_DIR)/gapbs-package.py
GAPBS_GRAPH_DIR ?= /nfs/share/manyang/gapbs-graphs/serialized
GAPBS_CROSS_COMPILE ?= $(if $(CROSS_COMPILE),$(CROSS_COMPILE),riscv64-unknown-linux-gnu-)
GAPBS_DEFAULT_DTB ?= xiangshan-fpga-noAIA-mem64g-novec
GAPBS_DTB_MIN_MEMORY_BYTES ?= 68719476736
GAPBS_BUILDROOT_DIR ?= $(abspath $(if $(BUILDROOT_DIR),$(BUILDROOT_DIR),$(GAPBS_REPO_ROOT)/build/buildroot))
GAPBS_LINUX_IMAGE ?= $(if $(LINUX_IMAGE),$(LINUX_IMAGE),$(GAPBS_BUILDROOT_DIR)/output/images/Image)
GAPBS_GCPT_BIN ?= $(if $(GCPT_BIN),$(GCPT_BIN),$(GAPBS_REPO_ROOT)/build/LibCheckpointAlpha/build/gcpt.bin)
GAPBS_SBI_BUILD_DIR ?= $(if $(SBI_BUILD_DIR),$(SBI_BUILD_DIR),$(GAPBS_REPO_ROOT)/build/opensbi)
GAPBS_SBI_BIN ?= $(if $(SBI_BIN),$(SBI_BIN),$(GAPBS_SBI_BUILD_DIR)/build/platform/generic/firmware/fw_jump.bin)
GAPBS_BUILDROOT_CROSS_COMPILE ?= $(GAPBS_BUILDROOT_DIR)/output/host/bin/riscv64-linux-
GAPBS_DTC ?= $(GAPBS_BUILDROOT_DIR)/output/host/bin/dtc
GAPBS_DTS_SOURCES := $(shell find $(GAPBS_DTS_DIR) -type f 2>/dev/null)
GAPBS_ALL_CASES := $(shell python3 $(GAPBS_HELPER) --list-cases)

WORKLOAD_DIRS += $(GAPBS_BUILD_DIR)

define add_gapbs_case
$(GAPBS_BUILD_DIR)/$(1)/download/sentinel:
	@mkdir -p "$$(@D)"
	@touch "$$@"

$(GAPBS_BUILD_DIR)/$(1)/rootfs.cpio: $$(GAPBS_HELPER) $$(GAPBS_WORKLOAD_DIR)/build.sh $(GAPBS_BUILD_DIR)/$(1)/download/sentinel $$(GAPBS_SCRIPTS_DIR)/build-workload-linux.sh
	@GAPBS_CASE="$(1)" \
	CROSS_COMPILE="$$(GAPBS_BUILDROOT_CROSS_COMPILE)" \
	GAPBS_GRAPH_DIR="$$(GAPBS_GRAPH_DIR)" \
	bash "$$(GAPBS_SCRIPTS_DIR)/build-workload-linux.sh" "$$(GAPBS_WORKLOAD_DIR)" "$(GAPBS_BUILD_DIR)/$(1)"

$(GAPBS_BUILD_DIR)/$(1)/fw_payload.bin: $$(GAPBS_DTS_SOURCES) $$(GAPBS_GCPT_BIN) $$(GAPBS_SCRIPTS_DIR)/build-firmware-linux.sh $(GAPBS_BUILD_DIR)/$(1)/rootfs.cpio $$(GAPBS_LINUX_IMAGE) $$(GAPBS_SBI_BIN)
	@printf '[gapbs] Assembling firmware for $(1)\n'
	@CROSS_COMPILE="$$(GAPBS_BUILDROOT_CROSS_COMPILE)" \
	DTC="$$(GAPBS_DTC)" \
	DEFAULT_DTB="$$(GAPBS_DEFAULT_DTB)" \
	DTB_MIN_MEMORY_BYTES="$$(GAPBS_DTB_MIN_MEMORY_BYTES)" \
	bash "$$(GAPBS_SCRIPTS_DIR)/build-firmware-linux.sh" "$$(GAPBS_GCPT_BIN)" "$$(GAPBS_SBI_BUILD_DIR)" "$$(GAPBS_DTS_DIR)" "$$(GAPBS_LINUX_IMAGE)" "$(GAPBS_BUILD_DIR)/$(1)"

linux/gapbs-$(1): $(GAPBS_BUILD_DIR)/$(1)/fw_payload.bin

WORKLOAD_PHONY_TARGETS += linux/gapbs-$(1)

$(GAPBS_IMAGE_DIR)/bin/$(1).fw_payload.bin: $(GAPBS_BUILD_DIR)/$(1)/fw_payload.bin
	@mkdir -p "$(GAPBS_IMAGE_DIR)/bin"
	@cp "$(GAPBS_BUILD_DIR)/$(1)/fw_payload.bin" "$(GAPBS_IMAGE_DIR)/bin/$(1).fw_payload.bin"
endef

$(foreach case,$(GAPBS_ALL_CASES),$(eval $(call add_gapbs_case,$(case))))

gapbs-list:
	@echo $(GAPBS_ALL_CASES)

gapbs-images:
	@[ -n "$(strip $(GAPBS_ALL_CASES))" ] || { echo '[gapbs] error: no cases -- gapbs-package.py --list-cases produced nothing'; exit 1; }
	@for case in $(GAPBS_ALL_CASES); do \
		$(MAKE) --no-print-directory -f "$(GAPBS_RECURSE_MAKEFILE)" "$(GAPBS_IMAGE_DIR)/bin/$$case.fw_payload.bin" || exit $$?; \
	done
	@printf '[gapbs] Output written to %s\n' "$(abspath $(GAPBS_IMAGE_DIR))"

.PHONY: gapbs-list gapbs-images
