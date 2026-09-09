#!/bin/sh
set -eu

payload_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$payload_dir/specjbb-workload.conf"
export JAVA_HOME="$payload_dir/jdk"
export PATH="$JAVA_HOME/bin:/bin:/usr/bin" LANG=C LC_ALL=C TZ=UTC
mkdir -p /proc /sys /tmp
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
cd "$payload_dir/specjbb"
jar="$payload_dir/specjbb/specjbb2015.jar"
[ -f "$jar" ] || { echo "SPECjbb jar not found: $jar" >&2; exit 1; }
exec "$JAVA_HOME/bin/java" -server "-Xms$SPECJBB_JVM_XMS" "-Xmx$SPECJBB_JVM_XMX" -jar "$jar" -m "$SPECJBB_MODE"
