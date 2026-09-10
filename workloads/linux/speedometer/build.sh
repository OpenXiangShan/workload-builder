#!/usr/bin/env bash
# Assemble the speedometer image: a Debian riscv64 Firefox in a chroot, the
# Speedometer payload, and the server that ties them to NEMU's profiler.
set -euo pipefail
shopt -s nullglob

: "${WORKLOAD_DIR:?WORKLOAD_DIR is required}"
: "${SRC_DIR:?SRC_DIR is required}"
: "${PKG_DIR:?PKG_DIR is required}"
: "${CROSS_COMPILE:?CROSS_COMPILE is required}"

PORT="${SPEEDOMETER_PORT:-8000}"
ITERATIONS="${SPEEDOMETER_ITERATIONS:-10}"
SUITES="${SPEEDOMETER_SUITES:-}"
VIEWPORT="${SPEEDOMETER_VIEWPORT:-1024x768}"
LOG_REQUESTS="${SPEEDOMETER_LOG_REQUESTS:-0}"

if [[ ! "$ITERATIONS" =~ ^[0-9]+$ ]] || [[ "$ITERATIONS" -lt 1 ]]; then
    echo "ERROR: SPEEDOMETER_ITERATIONS must be a positive integer, got '$ITERATIONS'" >&2
    exit 1
fi
if [[ ! "$PORT" =~ ^[0-9]+$ ]] || [[ "$PORT" -lt 1 ]] || [[ "$PORT" -gt 65535 ]]; then
    echo "ERROR: SPEEDOMETER_PORT must be a TCP port number, got '$PORT'" >&2
    exit 1
fi

FILES_DIR="$WORKLOAD_DIR/files"
CHROOT_DIR="$PKG_DIR/opt/debian"
DOCROOT_DIR="$PKG_DIR/srv/speedometer"

# The Debian userland
#
# Unpacking the .deb files directly avoids needing root, a foreign-architecture
# emulator or a package database. None of the packages in the closure need their
# maintainer scripts to run: what the browser requires is files.
firefox_debs=("$SRC_DIR"/firefox-esr_*.deb)
payloads=("$SRC_DIR"/speedometer-*.tar.gz)
if [[ "${#firefox_debs[@]}" -ne 1 ]] || [[ "${#payloads[@]}" -ne 1 ]]; then
    echo "ERROR: expected exactly one firefox-esr .deb and one Speedometer archive in $SRC_DIR" >&2
    exit 1
fi

mkdir -p "$CHROOT_DIR"
deb_count=0
for deb in "$SRC_DIR"/*.deb; do
    dpkg-deb -x "$deb" "$CHROOT_DIR"
    deb_count=$((deb_count + 1))
done
if [[ "$deb_count" -eq 0 ]]; then
    echo "ERROR: no .deb files in $SRC_DIR; check links.txt" >&2
    exit 1
fi
echo "unpacked $deb_count Debian packages"

if [[ ! -x "$CHROOT_DIR/usr/lib/firefox-esr/firefox-esr" ]]; then
    echo "ERROR: firefox-esr binary missing from the unpacked tree" >&2
    exit 1
fi
if [[ ! -e "$CHROOT_DIR/usr/lib/ld-linux-riscv64-lp64d.so.1" ]]; then
    echo "ERROR: Debian dynamic loader missing from the unpacked tree" >&2
    exit 1
fi

# Debian is a merged-usr layout, and every binary still names the loader as
# /lib/ld-linux-riscv64-lp64d.so.1. The compatibility symlinks that make that
# resolve come from base-files, which nothing in the closure depends on.
for merged in bin sbin lib; do
    ln -sfn "usr/$merged" "$CHROOT_DIR/$merged"
done

# Documentation, translations and packaging metadata are dead weight in an
# initramfs that has to be resident in guest RAM for the whole run.
rm -rf \
    "$CHROOT_DIR/usr/share/doc" \
    "$CHROOT_DIR/usr/share/man" \
    "$CHROOT_DIR/usr/share/info" \
    "$CHROOT_DIR/usr/share/locale" \
    "$CHROOT_DIR/usr/share/help" \
    "$CHROOT_DIR/usr/share/lintian" \
    "$CHROOT_DIR/usr/share/bug"

# The mount points boot.sh populates, and the identity files that glibc and
# GTK look up during startup. The machine id is fixed rather than generated so
# that two builds of the same image behave identically.
mkdir -p \
    "$CHROOT_DIR/proc" "$CHROOT_DIR/sys" "$CHROOT_DIR/dev" \
    "$CHROOT_DIR/tmp" "$CHROOT_DIR/root" "$CHROOT_DIR/run" \
    "$CHROOT_DIR/profile"
chmod 1777 "$CHROOT_DIR/tmp"

printf 'root:x:0:0:root:/root:/bin/false\n' > "$CHROOT_DIR/etc/passwd"
printf 'root:x:0:\n' > "$CHROOT_DIR/etc/group"
printf 'speedometer\n' > "$CHROOT_DIR/etc/hostname"
printf '127.0.0.1\tlocalhost speedometer\n' > "$CHROOT_DIR/etc/hosts"
printf 'passwd: files\ngroup: files\nhosts: files\n' > "$CHROOT_DIR/etc/nsswitch.conf"
printf '00000000000000000000000000000000\n' > "$CHROOT_DIR/etc/machine-id"
: > "$CHROOT_DIR/etc/resolv.conf"

install -Dm 644 "$FILES_DIR/user.js" "$CHROOT_DIR/profile/user.js"

# The benchmark payload
#
# The tree is served as published; only the harness entry point is touched, and
# only to load the hook that reports progress to the server.
mkdir -p "$DOCROOT_DIR"
tar -C "$DOCROOT_DIR" --strip-components=1 -xf "${payloads[0]}"

if [[ ! -f "$DOCROOT_DIR/index.html" ]] || [[ ! -f "$DOCROOT_DIR/resources/main.mjs" ]]; then
    echo "ERROR: unpacked Speedometer tree does not look like a benchmark root" >&2
    exit 1
fi

install -Dm 644 "$FILES_DIR/harness-hook.mjs" "$DOCROOT_DIR/resources/harness-hook.mjs"
python3 - "$DOCROOT_DIR/index.html" <<'PYTHON'
import sys

path = sys.argv[1]
anchor = '<script src="resources/main.mjs" type="module"></script>'
hook = '<script src="resources/harness-hook.mjs" type="module"></script>'

with open(path) as handle:
    markup = handle.read()

if anchor not in markup:
    raise SystemExit(f"harness entry point not found in {path}")
if hook in markup:
    raise SystemExit(0)

# Module scripts run in document order, so the hook sees a fully constructed
# benchmark client on the global object.
with open(path, "w") as handle:
    handle.write(markup.replace(anchor, anchor + "\n        " + hook, 1))
PYTHON

# The server
"${CROSS_COMPILE}gcc" -Wall -Wextra -O2 -static \
    -o "$SRC_DIR/bench-httpd" "$FILES_DIR/bench-httpd.c"
"${CROSS_COMPILE}strip" -s "$SRC_DIR/bench-httpd"
install -Dm 755 "$SRC_DIR/bench-httpd" "$PKG_DIR/usr/local/bin/bench-httpd"

# Boot glue
query="startAutomatically&iterationCount=$ITERATIONS&viewport=$VIEWPORT"
if [[ -n "$SUITES" ]]; then
    query="$query&suites=$SUITES"
fi
url="http://127.0.0.1:$PORT/index.html?$query"

log_requests_flag=""
if [[ "$LOG_REQUESTS" == "1" ]]; then
    log_requests_flag="--log-requests"
fi

# The query string separators are ampersands, which sed would expand to the
# matched text in the replacement.
sed -e "s|@PORT@|$PORT|g" -e "s|@URL@|${url//&/\\&}|g" \
    -e "s|@LOG_REQUESTS@|$log_requests_flag|g" \
    "$FILES_DIR/boot.sh" > "$SRC_DIR/boot.sh"
install -Dm 755 "$SRC_DIR/boot.sh" "$PKG_DIR/speedometer/boot.sh"
install -Dm 644 "$WORKLOAD_DIR/inittab" "$PKG_DIR/etc/inittab"

# Provenance: a bin file on its own should still say what it runs.
{
    echo "speedometer url: $url"
    echo "firefox package: $(basename "${firefox_debs[0]}")"
    echo "debian packages: $deb_count"
    echo "speedometer payload: $(basename "${payloads[0]}")"
} > "$PKG_DIR/speedometer/build.meta"

echo "speedometer image contents: $(du -sh "$PKG_DIR" | cut -f1)"
