# The speedometer image is assembled from Debian packages fetched at build
# time: around 110 MB per build, from an archive that removes superseded files.
# Any pinned package being rebuilt upstream turns the download into a 404, so
# leaving this in the default set would fail builds of unrelated workloads.
#
# The build rules are the generic ones; only the registration differs. Build it
# with `make linux/speedometer`.
$(eval $(call add_workload_linux,speedometer))

SPEEDOMETER_BUILD_DIR := build/linux-workloads/speedometer

WORKLOADS_LINUX := $(filter-out $(SPEEDOMETER_BUILD_DIR)/$(LINUX_FIRMWARE_FILENAME),$(WORKLOADS_LINUX))
ROOTFS := $(filter-out $(SPEEDOMETER_BUILD_DIR)/rootfs.cpio,$(ROOTFS))
DT_DIRS := $(filter-out $(SPEEDOMETER_BUILD_DIR)/dt,$(DT_DIRS))
TARFLAGS := $(filter-out --transform='s|^$(SPEEDOMETER_BUILD_DIR)|workloads/linux/speedometer|',$(TARFLAGS))
