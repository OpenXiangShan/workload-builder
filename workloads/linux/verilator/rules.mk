# This workload takes its payload from outside the repository
# (VERILATOR_GUEST_EMU and VERILATOR_GUEST_IMAGE), so it cannot be built by the
# build-everything targets. Registering it here gives it the standard
# per-workload rules while keeping it out of `make workloads` and `make
# tarball`; build it explicitly with `make linux/verilator`.

$(eval $(call add_workload_linux,verilator))

VERILATOR_BUILD_DIR := build/linux-workloads/verilator

WORKLOADS_LINUX := $(filter-out $(VERILATOR_BUILD_DIR)/$(LINUX_FIRMWARE_FILENAME),$(WORKLOADS_LINUX))
ROOTFS := $(filter-out $(VERILATOR_BUILD_DIR)/rootfs.cpio,$(ROOTFS))
DT_DIRS := $(filter-out $(VERILATOR_BUILD_DIR)/dt,$(DT_DIRS))
