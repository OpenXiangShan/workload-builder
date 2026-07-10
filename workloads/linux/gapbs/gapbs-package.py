#!/usr/bin/env python3
import argparse, os, shutil, subprocess, sys
from pathlib import Path

KERNELS = ("bfs", "sssp", "pr", "cc", "bc", "tc")
GRAPHS = ("road", "twitter", "web")

# graph file suffix + per-kernel args by graph
SUFFIX = {"bfs": ".sg", "pr": ".sg", "cc": ".sg", "bc": ".sg",
          "sssp": ".wsg", "tc": "U.sg"}
SSSP_DELTA = {"road": "50000", "twitter": "2", "web": "2"}

# initramfs newc cpio caps each file at 4 GiB (2**32); split any graph at/above it.
SPLIT_THRESHOLD = 4 * 1024**3
PART_SIZE = "3G"   # each part is well under the 4 GiB cpio limit

def kernel_args(kernel, graph):
    if kernel == "bfs":  return ["-n", "1"]
    if kernel == "cc":   return ["-n", "1"]
    if kernel == "pr":   return ["-i", "1000", "-t", "1e-4", "-n", "1"]
    if kernel == "bc":   return ["-i", "1", "-n", "1"]
    if kernel == "sssp": return ["-d", SSSP_DELTA[graph], "-n", "1"]
    if kernel == "tc":   return ["-n", "1"]
    raise RuntimeError(f"unknown kernel {kernel}")

def all_cases():
    return [f"{k}_{g}" for g in GRAPHS for k in KERNELS]

def parse_case(case):
    kernel, graph = case.split("_", 1)
    if kernel not in KERNELS or graph not in GRAPHS:
        raise RuntimeError(f"unknown gapbs case {case!r}")
    return kernel, graph

def compile_kernel(src_dir, kernel, cross_compile, pkg_dir, log_dir):
    log = log_dir / "build.log"
    cxx = f"{cross_compile}g++ -static"
    cmd = ["make", "-C", str(src_dir), "SERIAL=1", f"CXX={cxx}", kernel]
    log_dir.mkdir(parents=True, exist_ok=True)
    with open(log, "w") as f:
        r = subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT, text=True)
    if r.returncode != 0:
        sys.stderr.write(f"kernel build failed; see {log}\n")
        sys.exit(1)
    dst = pkg_dir / "usr" / "bin" / kernel
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src_dir / kernel, dst)
    dst.chmod(0o755)

def stage_graph(graph_dir, graph, kernel, pkg_dir):
    fname = f"{graph}{SUFFIX[kernel]}"
    src = Path(graph_dir) / fname
    if not src.is_file():
        raise RuntimeError(f"missing graph file: {src}")
    gdir = pkg_dir / "gapbs"
    gdir.mkdir(parents=True, exist_ok=True)
    guest_path = f"/gapbs/{fname}"
    if src.stat().st_size < SPLIT_THRESHOLD:
        shutil.copy2(src, gdir / fname)          # small graph: bundle whole
        return guest_path, False
    parts_dir = gdir / "parts"                    # large graph: split into parts
    parts_dir.mkdir(parents=True, exist_ok=True)
    # zero-padded numeric suffixes so a lexical glob concatenates them in order
    subprocess.run(["split", "-d", "-a", "3", "-b", PART_SIZE,
                    str(src), f"{fname}."], cwd=parts_dir, check=True)
    return guest_path, True                        # guest path is a FIFO fed from parts

def write_runtime(pkg_dir, case, kernel, graph_path, streamed, args):
    cmd = " ".join(["/usr/bin/" + kernel, "-f", graph_path, *args])
    lines = ["#!/bin/sh", "set -e",
             f"echo '======== BEGIN {case} ========'", "date -R || true"]
    if streamed:
        # Rejoin sub-4-GiB parts into the single serialized stream GAPBS expects,
        # through a named FIFO carrying the real .sg/.wsg suffix. GAPBS reads it
        # strictly forward, so a pipe suffices; free each part as it is sent.
        name = graph_path.rsplit("/", 1)[-1]
        lines += [
            f"rm -f {graph_path}",
            f"mkfifo {graph_path}",
            f'( for p in /gapbs/parts/{name}.*; do cat "$p"; rm -f "$p"; done ) > {graph_path} &',
        ]
    lines += [f"echo 'CMD: {cmd}'", "set +e", cmd, "status=$?", "set -e",
              "date -R || true",
              f"echo '======== END   {case} ========'", "exit $status", ""]
    run_sh = pkg_dir / "gapbs" / "run.sh"
    run_sh.write_text("\n".join(lines), encoding="utf-8")
    run_sh.chmod(0o755)
    etc = pkg_dir / "etc"; etc.mkdir(parents=True, exist_ok=True)
    (etc / "inittab").write_text("::sysinit:nemu-exec /bin/sh /gapbs/run.sh\n", encoding="utf-8")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--case")
    ap.add_argument("--list-cases", action="store_true")
    ap.add_argument("--src-dir")
    ap.add_argument("--graph-dir", default=os.environ.get(
        "GAPBS_GRAPH_DIR", "/nfs/share/manyang/gapbs-graphs/serialized"))
    ap.add_argument("--pkg-dir")
    ap.add_argument("--out-dir")
    ap.add_argument("--cross-compile", default=os.environ.get("CROSS_COMPILE", ""))
    args = ap.parse_args()

    if args.list_cases:
        print(" ".join(all_cases())); return
    for req in ("case", "src_dir", "pkg_dir", "out_dir"):
        if not getattr(args, req):
            ap.error(f"--{req.replace('_','-')} is required")

    kernel, graph = parse_case(args.case)
    pkg_dir = Path(args.pkg_dir).resolve()
    log_dir = Path(args.out_dir).resolve() / "logs"
    compile_kernel(Path(args.src_dir).resolve(), kernel, args.cross_compile, pkg_dir, log_dir)
    graph_path, streamed = stage_graph(args.graph_dir, graph, kernel, pkg_dir)
    write_runtime(pkg_dir, args.case, kernel, graph_path, streamed, kernel_args(kernel, graph))

if __name__ == "__main__":
    main()
