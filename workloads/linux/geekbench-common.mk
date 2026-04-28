GEEKBENCH_DEFAULT_DTB = $(if $(DEFAULT_DTB),$(DEFAULT_DTB),xiangshan-fpga-noAIA)

define add_workload_linux_geekbench
# Download files
build/linux-workloads/$(1)/download/sentinel: $$(shell find $$(abspath workloads/linux/$(1)) -iname 'links.txt')
	mkdir -p build/linux-workloads/$(1)/
	bash scripts/download-files.sh workloads/linux/$(1) build/linux-workloads/$(1)/download

# Track Geekbench-specific build options without making generic Linux workload
# rules aware of them.
build/linux-workloads/$(1)/build-vars.$$(shell printf '%s\n%s' "$$(PROFILING)" "$$(GEEKBENCH_ARGS)" | sha256sum | cut -d ' ' -f 1):
	mkdir -p build/linux-workloads/$(1)
	rm -f build/linux-workloads/$(1)/build-vars.*
	touch $$@

# Build and pack workload
build/linux-workloads/$(1)/rootfs.cpio: $$(shell find $$(abspath workloads/linux/$(1))) $(TOOLCHAIN_WRAPPER) build/linux-workloads/$(1)/download/sentinel build/linux-workloads/$(1)/build-vars.$$(shell printf '%s\n%s' "$$(PROFILING)" "$$(GEEKBENCH_ARGS)" | sha256sum | cut -d ' ' -f 1) scripts/build-workload-linux.sh
	CROSS_COMPILE="$$(abspath $(BUILDROOT_DIR)/output/host/bin)/riscv64-linux-" \
	SYSROOT_DIR="$$(abspath $(BUILDROOT_DIR)/output/staging)" \
	BUILDROOT_DIR="$$(abspath $(BUILDROOT_DIR))" \
	PROFILING="$(PROFILING)" \
	GEEKBENCH_ARGS="$(GEEKBENCH_ARGS)" \
	bash scripts/build-workload-linux.sh workloads/linux/$(1) build/linux-workloads/$(1)

# Build all-in-one firmware
build/linux-workloads/$(1)/fw_payload.bin: $$(shell find $$(abspath dts)) $(GCPT_BIN) dts/xiangshan.dts.in scripts/build-sbi.sh scripts/build-firmware-linux.sh build/linux-workloads/$(1)/rootfs.cpio $(LINUX_IMAGE) build/opensbi/build/platform/generic/firmware/fw_jump.bin
	CROSS_COMPILE="$$(abspath $(BUILDROOT_DIR)/output/host/bin)/riscv64-linux-" \
	DTC="$$(abspath $(BUILDROOT_DIR)/output/host/bin)/dtc" \
	DEFAULT_DTB="$(GEEKBENCH_DEFAULT_DTB)" \
	bash scripts/build-firmware-linux.sh $(GCPT_BIN) build/opensbi dts $(LINUX_IMAGE) build/linux-workloads/$(1)

linux/$(1): build/linux-workloads/$(1)/fw_payload.bin

WORKLOAD_PHONY_TARGETS += linux/$(1)
WORKLOAD_DIRS += build/linux-workloads/$(1)
WORKLOADS_LINUX += build/linux-workloads/$(1)/fw_payload.bin
ROOTFS += build/linux-workloads/$(1)/rootfs.cpio
DT_DIRS += build/linux-workloads/$(1)/dt
TARFLAGS += --transform='s|^build/linux-workloads/$(1)|workloads/linux/$(1)|'
endef
