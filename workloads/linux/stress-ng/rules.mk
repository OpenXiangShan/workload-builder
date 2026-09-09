STRESS_NG_OPS ?= 1
STRESS_NG_STRESSORS ?=
STRESS_NG_ARGS ?= --oom-avoid --skip-silent --metrics-brief
STRESS_NG_VM_BYTES ?= 16M
STRESS_NG_CYCLIC_POLICY ?= rr
STRESS_NG_BUILD_VARS_HASH := $(shell printf '%s\n' \
	'$(if $(PROFILING),$(PROFILING),0)' \
	'$(STRESS_NG_OPS)' '$(STRESS_NG_STRESSORS)' '$(STRESS_NG_ARGS)' \
	'$(STRESS_NG_VM_BYTES)' '$(STRESS_NG_CYCLIC_POLICY)' | \
	sha256sum | cut -d ' ' -f 1)
STRESS_NG_BUILD_DIR := build/linux-workloads/stress-ng
STRESS_NG_BUILD_VARS_STAMP := $(STRESS_NG_BUILD_DIR)/build-vars.$(STRESS_NG_BUILD_VARS_HASH).stamp

# The generic Linux workload recipe invokes build.sh as a child process.
# Export the command line so that build.sh can record it in the guest image.
export STRESS_NG_OPS STRESS_NG_STRESSORS STRESS_NG_ARGS
export STRESS_NG_VM_BYTES STRESS_NG_CYCLIC_POLICY
export PROFILING

$(STRESS_NG_BUILD_VARS_STAMP):
	mkdir -p "$(@D)"
	rm -f "$(@D)"/build-vars.*.stamp
	touch "$@"

$(eval $(call add_workload_linux,stress-ng))

# Rebuild the rootfs when the guest's stress-ng command line changes.
$(STRESS_NG_BUILD_DIR)/rootfs.cpio: $(STRESS_NG_BUILD_VARS_STAMP)
