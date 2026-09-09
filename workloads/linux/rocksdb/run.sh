#!/bin/sh
set -eu

[ ! -r /etc/default/rocksdb ] || . /etc/default/rocksdb

db_root=${ROCKSDB_DB:-/tmp/rocksdb}
keys=${ROCKSDB_KEYS:-1000000}
ops=${ROCKSDB_OPS:-100000000}
threads=${ROCKSDB_THREADS:-1}
value_size=${ROCKSDB_VALUE_SIZE:-100}
profiling=${ROCKSDB_PROFILING:-1}
case_filter=${ROCKSDB_CASES:-readwhilewriting,readrandomwriterandom,updaterandom,seekrandomwhilewriting,randomtransaction,timeseries,mixgraph}

case "$profiling" in
    0|1) ;;
    *) echo "ROCKSDB_PROFILING/PROFILING must be 0 or 1: $profiling" >&2; exit 2 ;;
esac

mkdir -p "$db_root"

run_case() {
    case_name=$1
    case_db="$db_root/$case_name"
    prepare_db=false
    rm -rf "$case_db"
    mkdir -p "$case_db"

    common_args="--db=$case_db --num=$keys --value_size=$value_size"
    common_args="$common_args --disable_wal=true --compression_type=none --statistics=false"
    args="--benchmarks=$case_name $common_args --reads=$ops --writes=$ops --threads=$threads"
    case "$case_name" in
        readwhilewriting|seekrandomwhilewriting)
            prepare_db=true
            args="$args --finish_after_writes=true --use_existing_db=true --use_existing_keys=true"
            ;;
        readrandomwriterandom|updaterandom)
            prepare_db=true
            args="$args --use_existing_db=true --use_existing_keys=true"
            ;;
        randomtransaction)
            args="$args --transaction_db=true --transaction_sets=2"
            ;;
        timeseries)
            args="$args --key_id_range=$keys --time_range=100000 --expire_style=compaction_filter"
            ;;
        mixgraph)
            prepare_db=true
            args="$args --use_existing_db=true --use_existing_keys=true --mix_max_scan_len=100"
            args="$args --mix_get_ratio=0.83 --mix_put_ratio=0.14 --mix_seek_ratio=0.03"
            ;;
        *)
            echo "unknown RocksDB case: $case_name" >&2
            return 1
            ;;
    esac

    echo "[rocksdb] $case_name keys=$keys ops=$ops threads=$threads"
    if [ "${prepare_db:-false}" = true ]; then
        # shellcheck disable=SC2086
        /usr/bin/rocksdb-db-bench --benchmarks=fillrandom $common_args \
            --writes="$keys" --threads=1
    fi
    if [ "$profiling" = 1 ]; then
        nemu-trap 257
    fi
    # shellcheck disable=SC2086
    /usr/bin/rocksdb-db-bench $args
    rm -rf "$case_db"
}

old_ifs=$IFS
IFS=,
for case_name in $case_filter; do
    IFS=$old_ifs
    [ -n "$case_name" ] || continue
    run_case "$case_name"
    IFS=,
done
IFS=$old_ifs

nemu-trap
