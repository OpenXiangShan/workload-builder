#!/bin/sh
set -eu

if [ -r /etc/default/stress-ng ]; then
    # shellcheck disable=SC1091
    . /etc/default/stress-ng
fi
STRESS_NG_OPS="${STRESS_NG_OPS:-1}"
STRESS_NG_STRESSORS="${STRESS_NG_STRESSORS:-}"
STRESS_NG_ARGS="${STRESS_NG_ARGS:---oom-avoid --skip-silent --metrics-brief}"
STRESS_NG_VM_BYTES="${STRESS_NG_VM_BYTES:-16M}"
STRESS_NG_CYCLIC_POLICY="${STRESS_NG_CYCLIC_POLICY:-rr}"

case "$STRESS_NG_OPS" in
    ''|*[!0-9]*|0)
        echo "invalid STRESS_NG_OPS: $STRESS_NG_OPS" >&2
        nemu-trap 2
        exit 2
        ;;
esac

if [ -n "$STRESS_NG_STRESSORS" ]; then
    stressors="$STRESS_NG_STRESSORS"
    mode="selected stressors"
    set -- --timeout 0
else
    stressors="$(/usr/bin/stress-ng --stressors)"
    mode="all stressors"
    set -- --all 1 --timeout 0
fi

echo "======== BEGIN stress-ng ========"
date -R || true
echo "MODE: ${mode}, parallel, ${STRESS_NG_OPS} bogo ops per stressor"
echo "EXTRA ARGS: ${STRESS_NG_ARGS}"

# stress-ng has no global bogo-op limit. Explicitly select every stressor so
# that its matching --*-ops option is associated with it, while --all keeps
# the full-pressure parallel mode. Unsupported and pathological stressors are
# skipped by stress-ng.
attempted=0
for stressor in $stressors; do
    attempted=$((attempted + 1))
    set -- "$@" "--${stressor}" 1
    case "$stressor" in
        vm)
            set -- "$@" --vm-bytes "$STRESS_NG_VM_BYTES"
            ;;
        cyclic)
            set -- "$@" --cyclic-policy "$STRESS_NG_CYCLIC_POLICY"
            ;;
    esac
    set -- "$@" "--${stressor}-ops" "$STRESS_NG_OPS"
done
# STRESS_NG_ARGS is intentionally a configurable shell-style argument string.
# shellcheck disable=SC2086
set -- "$@" ${STRESS_NG_ARGS}

set +e
/usr/bin/stress-ng "$@"
status=$?
set -e
# stress-ng uses 3 and 4 when stressors are unavailable because of guest
# resources or implementation support. These are expected skips in --all mode.
case "$status" in
    3|4) status=0 ;;
esac
date -R || true
echo "======== END stress-ng (${attempted} attempted, status=${status}) ========"
nemu-trap "$status"
