#!/bin/sh
# Bring up the guest, start the benchmark server, and hand control to Firefox.
#
# The browser is a stock Debian riscv64 build and cannot link against the
# buildroot rootfs, whose glibc is older than Debian requires. It therefore runs
# inside a chroot holding a self-contained Debian tree. The server stays outside
# that chroot: it is statically linked, and keeping it in the buildroot rootfs
# means the chroot needs no shell and no second copy of the benchmark payload.
#
# Nothing here ends the run. The server issues the NEMU debug call when the
# benchmark reports its results; the trap at the end of this script only fires
# if the browser died first.

set -u

CHROOT=/opt/debian
DOCROOT=/srv/speedometer
PORT=@PORT@
URL='@URL@'
RESULTS=/tmp/speedometer-results.json
LOG_REQUESTS=@LOG_REQUESTS@

echo "speedometer: preparing guest"

# Loopback is the only interface, and the benchmark is served over it.
ifconfig lo 127.0.0.1 netmask 255.0.0.0 up

# Gecko locates its own installation through /proc/self/exe and allocates
# shared memory through /dev/shm, so both have to exist inside the chroot.
mount -t proc proc "$CHROOT/proc"
mount -t sysfs sysfs "$CHROOT/sys"
mount -t devtmpfs devtmpfs "$CHROOT/dev"
mkdir -p "$CHROOT/dev/shm" "$CHROOT/dev/pts"
mount -t tmpfs tmpfs "$CHROOT/dev/shm"
mount -t devpts devpts "$CHROOT/dev/pts"
mount -t tmpfs tmpfs "$CHROOT/tmp"

echo "speedometer: starting server on 127.0.0.1:$PORT"
/usr/local/bin/bench-httpd --root "$DOCROOT" --port "$PORT" --results "$RESULTS" $LOG_REQUESTS &

# The browser must not find the server missing on its first request. A server
# that never comes up would otherwise leave the guest spinning for the rest of
# the run with nothing to show for it.
attempt=0
until wget -q -O /dev/null "http://127.0.0.1:$PORT/index.html"; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 30 ]; then
        echo "speedometer: server did not come up on port $PORT"
        nemu-trap -1
    fi
    sleep 1
done
echo "speedometer: server ready"

# Debian's firefox-esr resolves its libraries through the chroot's own loader,
# so no library path is exported here; what is exported is everything that
# would otherwise put the browser into a sandbox or a crash reporter it cannot
# use, plus a window comfortably larger than the size Speedometer asks for.
export HOME=/root
export TMPDIR=/tmp
export MOZ_HEADLESS_WIDTH=1280
export MOZ_HEADLESS_HEIGHT=1024
export MOZ_DISABLE_CONTENT_SANDBOX=1
export MOZ_DISABLE_GMP_SANDBOX=1
export MOZ_DISABLE_RDD_SANDBOX=1
export MOZ_DISABLE_SOCKET_PROCESS_SANDBOX=1
export MOZ_CRASHREPORTER_DISABLE=1
export LANG=C
export LC_ALL=C

echo "speedometer: launching firefox at $URL"
chroot "$CHROOT" /usr/lib/firefox-esr/firefox-esr \
    --headless --no-remote --new-instance \
    --profile /profile \
    "$URL"

echo "speedometer: browser exited before the benchmark reported results"
nemu-trap -1
