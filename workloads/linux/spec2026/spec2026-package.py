#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import shlex
import shutil
import subprocess
import sys
from collections import deque
from pathlib import Path

INPUT_SETS = ("ref", "train", "test")
DEFAULT_LABEL = "spec2026"
ALL_CASES = (
    "706.stockfish_r",
    "707.ntest_r",
    "708.sqlite_r",
    "709.cactus_r",
    "710.omnetpp_r",
    "714.cpython_r",
    "721.gcc_r",
    "722.palm_r",
    "723.llvm_r",
    "727.cppcheck_r",
    "729.abc_r",
    "731.astcenc_r",
    "734.vpr_r",
    "735.gem5_r",
    "736.ocio_r",
    "737.gmsh_r",
    "748.flightdm_r",
    "749.fotonik3d_r",
    "750.sealcrypto_r",
    "753.ns3_r",
    "765.roms_r",
    "766.femflow_r",
    "767.nest_r",
    "772.marian_r",
    "777.zstd_r",
    "782.lbm_r",
    "800.pot3d_s",
    "801.xz_s",
    "803.sph_exa_s",
    "807.ntest_s",
    "809.cactus_s",
    "811.tealeaf_s",
    "816.nab_s",
    "817.flac_s",
    "820.cloverleaf_s",
    "821.gcc_s",
    "822.palm_s",
    "823.llvm_s",
    "827.cppcheck_s",
    "829.abc_s",
    "834.vpr_s",
    "835.gem5_s",
    "838.diamond_s",
    "846.minizinc_s",
    "849.fotonik3d_s",
    "853.ns3_s",
    "854.graph500_s",
    "857.namd_s",
    "865.roms_s",
    "867.nest_s",
    "872.marian_s",
    "881.neutron_s",
    "998.specrand_s",
    "999.specrand_r",
)


def format_cmd(cmd):
    return " ".join(shlex.quote(str(part)) for part in cmd)


def progress_prefix():
    current = os.environ.get("SPEC2026_PROGRESS_K", "1")
    total = os.environ.get("SPEC2026_PROGRESS_N", "1")
    return f"[spec2026 {current}/{total}]"


def status(message):
    print(f"{progress_prefix()} {message}", flush=True)


def read_log_tail(log_path, max_lines=40):
    with open(log_path, "r", encoding="utf-8", errors="replace") as f:
        lines = deque(f, maxlen=max_lines)
    return "".join(lines).rstrip()


def run(cmd, *, env=None, cwd=None, log_path=None, summary=None):
    command_text = format_cmd(cmd)
    if summary:
        status(summary)

    if log_path is None:
        raise ValueError("log_path is required")

    log_path.parent.mkdir(parents=True, exist_ok=True)
    with open(log_path, "a", encoding="utf-8") as log:
        log.write(f"$ {command_text}\n")
        if cwd is not None:
            log.write(f"# cwd: {cwd}\n")
        log.flush()
        result = subprocess.run(
            cmd,
            cwd=cwd,
            env=env,
            check=False,
            stdout=log,
            stderr=subprocess.STDOUT,
            text=True,
        )
        log.write("\n")

    if result.returncode != 0:
        tail = read_log_tail(log_path)
        detail = f"\nLast log lines from {log_path}:\n{tail}" if tail else ""
        raise RuntimeError(f"command failed: {command_text}\nSee {log_path}{detail}")


def capture(cmd, *, env=None, cwd=None, log_path=None, summary=None):
    command_text = format_cmd(cmd)
    if summary:
        status(summary)

    result = subprocess.run(
        cmd,
        cwd=cwd,
        env=env,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )

    if log_path is not None:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with open(log_path, "w", encoding="utf-8") as log:
            log.write(f"$ {command_text}\n")
            if cwd is not None:
                log.write(f"# cwd: {cwd}\n")
            log.write(result.stdout)
            if result.stdout and not result.stdout.endswith("\n"):
                log.write("\n")

    if result.returncode != 0:
        detail = result.stdout[-4000:] if result.stdout else ""
        raise RuntimeError(f"command failed: {command_text}\n{detail}")

    return result.stdout


def case_mode(case_name):
    if case_name.endswith("_s"):
        return "speed"
    if case_name.endswith("_r"):
        return "rate"
    raise RuntimeError(f"unexpected SPEC2026 case name: {case_name}")


def filter_cases(cases, input_set, mode):
    if input_set not in (None, "", "all", *INPUT_SETS):
        choices = ", ".join((*INPUT_SETS, "all"))
        raise RuntimeError(f"unknown SPEC2026 input set {input_set!r}; available: {choices}")
    if mode in (None, "", "all"):
        return cases
    if mode not in ("rate", "speed"):
        raise RuntimeError("unknown SPEC2026 mode {!r}; available: rate, speed, all".format(mode))
    return tuple(case for case in cases if case_mode(case) == mode)


def normalize_runtime_input_set(input_set):
    if input_set == "all":
        return "ref"
    return input_set


def file_sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def maybe_load_json(path):
    if not path.is_file():
        return None
    try:
        return load_json(path)
    except Exception:
        return None


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def build_local_config(template_cfg, generated_cfg):
    filtered_lines = []
    for line in template_cfg.read_text(encoding="utf-8").splitlines():
        if line.strip() == "__HASH__":
            break
        filtered_lines.append(line)
    generated_cfg.parent.mkdir(parents=True, exist_ok=True)
    generated_cfg.write_text("\n".join(filtered_lines) + "\n", encoding="utf-8")
    return generated_cfg


def spec_env(spec_dir):
    script = f"cd {shlex.quote(str(spec_dir))} && . ./shrc >/dev/null && env -0"
    raw = subprocess.check_output(["bash", "-lc", script])
    env = {}
    for item in raw.split(b"\0"):
        if not item:
            continue
        key, value = item.split(b"=", 1)
        env[key.decode()] = value.decode()
    return env


def resolve_cross_compile(prefix):
    gcc_name = prefix if prefix.endswith("gcc") else prefix + "gcc"
    gcc_path = Path(gcc_name)
    if not gcc_path.is_absolute():
        found = shutil.which(gcc_name)
        if found is None:
            raise RuntimeError(f"cannot locate compiler for CROSS_COMPILE={prefix!r}")
        gcc_path = Path(found)
    if not gcc_path.is_file():
        raise RuntimeError(f"compiler does not exist: {gcc_path}")
    gcc_path = gcc_path.resolve()
    if not gcc_path.name.endswith("gcc"):
        raise RuntimeError(f"unexpected compiler name for CROSS_COMPILE={prefix!r}: {gcc_path.name}")
    cross_compile = str(gcc_path)[: -len("gcc")]
    toolchain_root = gcc_path.parent.parent
    return cross_compile, toolchain_root


def case_base_name(case_name):
    if "." not in case_name or "_" not in case_name:
        raise RuntimeError(f"unexpected SPEC2026 case name: {case_name}")
    return case_name.split(".", 1)[1].rsplit("_", 1)[0]


def shared_build_dir_for(out_dir, case_name, tune):
    return out_dir.parent / "_bench-builds" / case_name / tune


def shared_build_metadata(spec_cfg, spec_dir, cross_compile, tune, compiler_root, jobs):
    return {
        "spec_cfg_sha256": file_sha256(spec_cfg),
        "spec_dir": str(spec_dir),
        "cross_compile": cross_compile,
        "tune": tune,
        "compiler_root": str(compiler_root),
        "jobs": jobs,
        "label": DEFAULT_LABEL,
    }


def select_built_elf(exe_dir, tune):
    if not exe_dir.is_dir():
        raise RuntimeError(f"runcpu did not create exe directory: {exe_dir}")
    candidates = [path for path in exe_dir.iterdir() if path.is_file() and not path.name.endswith(".md5")]
    if not candidates:
        raise RuntimeError(f"no executable produced by runcpu under {exe_dir}")
    preferred = [path for path in candidates if f"_{tune}." in path.name]
    if preferred:
        candidates = preferred
    return max(candidates, key=lambda path: path.stat().st_mtime)


def explain_missing_elf(output_root, case_name):
    build_root = output_root / "benchspec" / "CPU" / case_name / "build"
    if not build_root.is_dir():
        return ""

    build_dirs = sorted(path for path in build_root.iterdir() if path.is_dir())
    if not build_dirs:
        return ""

    latest = max(build_dirs, key=lambda path: path.stat().st_mtime)
    details = [f"Latest build directory: {latest}"]
    for name in ("make.err", "make.out"):
        file_path = latest / name
        if file_path.is_file():
            tail = read_log_tail(file_path)
            if tail:
                details.append(f"Last log lines from {file_path}:\n{tail}")
                break
    return "\n" + "\n".join(details)


def export_elf_artifact(elf, case_name, out_dir):
    elf_dir = out_dir / "elf"
    elf_dir.mkdir(parents=True, exist_ok=True)
    exported_elf = elf_dir / f"{case_name}.elf"
    shutil.copy2(elf, exported_elf)
    return exported_elf


def export_build_log_artifact(build_log, out_dir):
    if not build_log.is_file():
        return None
    log_dir = out_dir / "logs" / "build_elf"
    log_dir.mkdir(parents=True, exist_ok=True)
    exported_log = log_dir / build_log.name
    shutil.copy2(build_log, exported_log)
    return exported_log


def build_elf(spec_dir, case_name, spec_cfg, out_dir, log_dir, cross_compile, tune, jobs, compiler_root):
    shared_dir = shared_build_dir_for(out_dir, case_name, tune)
    output_root = shared_dir / "runspec-output"
    generated_cfg = shared_dir / "runcpu-config" / spec_cfg.name
    shared_log_dir = shared_dir / "logs"
    build_log = shared_log_dir / "build.log"
    exe_dir = output_root / "benchspec" / "CPU" / case_name / "exe"
    metadata_path = shared_dir / "build-meta.json"
    build_state_path = shared_dir / "build-state.json"
    metadata = shared_build_metadata(spec_cfg, spec_dir, cross_compile, tune, compiler_root, jobs)

    cached_metadata = maybe_load_json(metadata_path)
    if cached_metadata == metadata:
        try:
            elf = select_built_elf(exe_dir, tune)
        except Exception:
            elf = None
        if elf is not None:
            if not generated_cfg.is_file():
                build_local_config(spec_cfg, generated_cfg)
            status(f"Reusing {case_name} build from {shared_dir}")
            export_build_log_artifact(build_log, out_dir)
            return elf, output_root, generated_cfg

    build_state = maybe_load_json(build_state_path)
    if cached_metadata is None and build_state == metadata:
        try:
            elf = select_built_elf(exe_dir, tune)
        except Exception:
            elf = None
        if elf is not None:
            if not generated_cfg.is_file():
                build_local_config(spec_cfg, generated_cfg)
            status(f"Recovering completed {case_name} build from {shared_dir}")
            write_json(metadata_path, metadata)
            if build_state_path.is_file():
                build_state_path.unlink()
            export_build_log_artifact(build_log, out_dir)
            return elf, output_root, generated_cfg

    resumable = False
    if cached_metadata is None:
        if build_state == metadata:
            resumable = True
        elif output_root.exists() or generated_cfg.parent.exists() or build_log.is_file():
            resumable = True

    if resumable:
        status(f"Resuming {case_name} build from {shared_dir}")
    else:
        if output_root.exists():
            shutil.rmtree(output_root)
        if generated_cfg.parent.exists():
            shutil.rmtree(generated_cfg.parent)
        if shared_log_dir.exists():
            shutil.rmtree(shared_log_dir)
    shared_log_dir.mkdir(parents=True, exist_ok=True)
    if not generated_cfg.is_file():
        build_local_config(spec_cfg, generated_cfg)
    write_json(build_state_path, metadata)

    env = os.environ.copy()
    env.update(spec_env(spec_dir))
    env["SPEC"] = str(spec_dir)

    runcpu = spec_dir / "bin" / "runcpu"
    cmd = [
        str(runcpu),
        "--action",
        "build",
        "--config",
        str(generated_cfg),
        "--output_root",
        str(output_root),
        "--label",
        DEFAULT_LABEL,
        "--define",
        f"gcc_dir={compiler_root}",
        "--define",
        f"build_ncpus={jobs}",
        "--tune",
        tune,
        case_name,
    ]
    run(
        cmd,
        cwd=spec_dir,
        env=env,
        log_path=build_log,
        summary=f"Building {case_name} with runcpu (log: {build_log})",
    )

    try:
        elf = select_built_elf(exe_dir, tune)
    except RuntimeError as exc:
        detail = explain_missing_elf(output_root, case_name)
        raise RuntimeError(str(exc) + detail) from exc

    write_json(metadata_path, metadata)
    if build_state_path.is_file():
        build_state_path.unlink()
    export_build_log_artifact(build_log, out_dir)
    return elf, output_root, generated_cfg


def select_primary_run_dir(run_root):
    if not run_root.is_dir():
        raise RuntimeError(f"runcpu did not create run directory: {run_root}")

    candidates = [path for path in run_root.iterdir() if path.is_dir() and path.name.endswith(".0000")]
    if not candidates:
        candidates = [path for path in run_root.iterdir() if path.is_dir()]
    if not candidates:
        raise RuntimeError(f"no run directories produced by runcpu under {run_root}")
    return max(candidates, key=lambda path: path.stat().st_mtime)


def matching_run_dirs(run_root, primary_run_dir):
    prefix = primary_run_dir.name.rsplit(".", 1)[0] + "."
    matches = [path for path in run_root.iterdir() if path.is_dir() and path.name.startswith(prefix)]
    if not matches:
        matches = [primary_run_dir]
    return sorted(matches)


def generate_runtime_script(spec_dir, primary_run_dir, run_root, target_run_root, script_path, log_path):
    env = os.environ.copy()
    env.update(spec_env(spec_dir))
    env["SPEC"] = str(spec_dir)

    output = capture(
        [str(spec_dir / "bin" / "specinvoke"), "-nn"],
        cwd=primary_run_dir,
        env=env,
        log_path=log_path,
        summary=f"Generating replay script for {primary_run_dir.name} (log: {log_path})",
    )

    lines = output.splitlines()
    if lines and lines[-1].startswith("specinvoke exit:"):
        lines.pop()

    rewritten = "\n".join(line.replace(str(run_root), str(target_run_root)) for line in lines)
    if rewritten:
        rewritten += "\n"
    script_path.write_text(rewritten, encoding="utf-8")
    script_path.chmod(0o755)


def write_runtime_files(pkg_dir, case_name, primary_run_dir_name):
    spec_root = pkg_dir / "spec"
    target_run_dir = Path("/spec") / "benchspec" / "CPU" / case_name / "run" / primary_run_dir_name

    run_sh = spec_root / "run.sh"
    run_sh.write_text(
        "\n".join(
            [
                "#!/bin/sh",
                "set -e",
                f"echo '======== BEGIN {case_name} ========'",
                "date -R || true",
                f"cd {target_run_dir}",
                "set +e",
                "sh ./doit.sh",
                "status=$?",
                "set -e",
                "date -R || true",
                f"echo '======== END   {case_name} ========'",
                "exit $status",
                "",
            ]
        ),
        encoding="utf-8",
    )
    run_sh.chmod(0o755)

    etc = pkg_dir / "etc"
    etc.mkdir(parents=True, exist_ok=True)
    (etc / "inittab").write_text("::sysinit:nemu-exec /bin/sh /spec/run.sh\n", encoding="utf-8")


def package_run_tree(spec_dir, generated_cfg, case_name, pkg_dir, output_root, input_set, tune, jobs, compiler_root, log_dir):
    runtime_input_set = normalize_runtime_input_set(input_set)
    env = os.environ.copy()
    env.update(spec_env(spec_dir))
    env["SPEC"] = str(spec_dir)

    runsetup_log = log_dir / "runsetup.log"
    runcpu = spec_dir / "bin" / "runcpu"
    cmd = [
        str(runcpu),
        "--action",
        "runsetup",
        "--config",
        str(generated_cfg),
        "--output_root",
        str(output_root),
        "--label",
        DEFAULT_LABEL,
        "--define",
        f"gcc_dir={compiler_root}",
        "--define",
        f"build_ncpus={jobs}",
        "--tune",
        tune,
        "--size",
        runtime_input_set,
        case_name,
    ]
    run(
        cmd,
        cwd=spec_dir,
        env=env,
        log_path=runsetup_log,
        summary=f"Setting up run directory for {case_name} [{runtime_input_set}] (log: {runsetup_log})",
    )

    run_root = output_root / "benchspec" / "CPU" / case_name / "run"
    primary_run_dir = select_primary_run_dir(run_root)

    spec_root = pkg_dir / "spec"
    target_run_root = spec_root / "benchspec" / "CPU" / case_name / "run"
    target_run_root.mkdir(parents=True, exist_ok=True)

    specinvoke_log = log_dir / "specinvoke.log"
    generate_runtime_script(
        spec_dir,
        primary_run_dir,
        run_root,
        Path("/spec") / "benchspec" / "CPU" / case_name / "run",
        primary_run_dir / "doit.sh",
        specinvoke_log,
    )

    for src_dir in matching_run_dirs(run_root, primary_run_dir):
        dst_dir = target_run_root / src_dir.name
        if dst_dir.exists():
            shutil.rmtree(dst_dir)
        shutil.copytree(src_dir, dst_dir, symlinks=True)

    write_runtime_files(pkg_dir, case_name, primary_run_dir.name)


def package_case(args):
    if args.case not in ALL_CASES:
        choices = " ".join(sorted(ALL_CASES))
        raise RuntimeError(f"unknown SPEC2026 case {args.case!r}; available cases: {choices}")

    spec_dir = Path(args.spec).resolve()
    spec_cfg = Path(args.spec_config).resolve()
    pkg_dir = Path(args.pkg_dir).resolve() if args.pkg_dir else None
    out_dir = Path(args.out_dir).resolve()
    log_dir = Path(args.log_dir).resolve() if args.log_dir else out_dir / "logs"

    cross_compile, detected_toolchain_root = resolve_cross_compile(args.cross_compile)
    compiler_root = Path(args.compiler_root).resolve() if args.compiler_root else detected_toolchain_root

    elf, output_root, generated_cfg = build_elf(
        spec_dir,
        args.case,
        spec_cfg,
        out_dir,
        log_dir,
        cross_compile,
        args.tune,
        args.jobs,
        compiler_root,
    )
    exported_elf = export_elf_artifact(elf, args.case, out_dir)
    status(f"Exported ELF: {exported_elf}")

    if args.elf_only:
        return

    if pkg_dir is None:
        raise RuntimeError("--pkg-dir is required unless --elf-only is set")
    if pkg_dir.exists():
        shutil.rmtree(pkg_dir)
    (pkg_dir / "spec").mkdir(parents=True)

    package_run_tree(
        spec_dir,
        generated_cfg,
        args.case,
        pkg_dir,
        output_root,
        args.input_set,
        args.tune,
        args.jobs,
        compiler_root,
        log_dir,
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--case")
    parser.add_argument("--list-cases", action="store_true")
    parser.add_argument("--spec")
    parser.add_argument("--spec-config")
    parser.add_argument("--pkg-dir")
    parser.add_argument("--out-dir")
    parser.add_argument("--cross-compile", default=os.environ.get("CROSS_COMPILE", "riscv64-unknown-linux-gnu-"))
    parser.add_argument("--compiler-root")
    parser.add_argument("--log-dir")
    parser.add_argument("--tune", default=os.environ.get("SPEC2026_TUNE", "base"))
    parser.add_argument("--jobs", type=int, default=int(os.environ.get("SPEC2026_JOBS", "1")))
    parser.add_argument("--input-set", default=os.environ.get("SPEC2026_INPUT", "ref"))
    parser.add_argument("--mode", default=os.environ.get("SPEC2026_MODE", "all"))
    parser.add_argument("--elf-only", action="store_true")
    args = parser.parse_args()

    try:
        cases = filter_cases(ALL_CASES, args.input_set, args.mode)
        if args.list_cases:
            print(" ".join(cases))
            return

        required = {
            "--case": args.case,
            "--spec": args.spec,
            "--spec-config": args.spec_config,
            "--out-dir": args.out_dir,
        }
        missing = [name for name, value in required.items() if not value]
        if missing:
            raise RuntimeError(f"missing required arguments: {' '.join(missing)}")

        package_case(args)
    except Exception as exc:
        print(f"{progress_prefix()} ERROR: {exc}", file=sys.stderr)
        raise


if __name__ == "__main__":
    main()
