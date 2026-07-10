#!/usr/bin/env bash
set -euo pipefail

: "${GAPBS_CASE:?GAPBS_CASE is required}"
: "${CROSS_COMPILE:?CROSS_COMPILE is required}"
: "${PKG_DIR:=$WORKLOAD_BUILD_DIR/package}"
: "${GAPBS_GRAPH_DIR:=/nfs/share/manyang/gapbs-graphs/serialized}"

python3 "$WORKLOAD_DIR/gapbs-package.py" \
  --case "$GAPBS_CASE" \
  --src-dir "$WORKLOAD_DIR/source" \
  --graph-dir "$GAPBS_GRAPH_DIR" \
  --pkg-dir "$PKG_DIR" \
  --out-dir "$WORKLOAD_BUILD_DIR" \
  --cross-compile "$CROSS_COMPILE"
