#!/bin/sh
set -u

payload_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$payload_dir/specjbb-workload.conf"
harts="${SPECJBB_HARTS:-2}"

run_on_cpu() {
  cpu="$1"; shift
  if [ -x /usr/bin/taskset ]; then /usr/bin/taskset -c "$cpu" "$@"
  elif [ -x /bin/taskset ]; then /bin/taskset -c "$cpu" "$@"
  else echo "SPECjbb launcher: taskset not found" >&2; return 127; fi
}

# profilingv2 starts after the second trap seen on hart 0. Trap 256 is not
# used because disabling timer interrupts can deadlock a timed Java workload.
cpu=0
while [ "$cpu" -lt "$harts" ]; do
  run_on_cpu "$cpu" /bin/nemu-trap 257 || exit $?
  cpu=$((cpu + 1))
done
run_on_cpu 0 /bin/nemu-trap 257 || exit $?

set +e
run_on_cpu "0-$((harts - 1))" /bin/sh "$payload_dir/run.sh"
status=$?
set -e

cpu=0; pids=""
while [ "$cpu" -lt "$harts" ]; do
  run_on_cpu "$cpu" /bin/nemu-trap 258 & pids="$pids $!"
  cpu=$((cpu + 1))
done
for pid in $pids; do wait "$pid"; done
/bin/nemu-trap "$status"
exit "$status"
