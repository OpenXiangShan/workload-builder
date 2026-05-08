#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from collections import deque
from pathlib import Path


BENCHMARKS = (
    ("500.perlbench_r", "perlbench", "rate", ("int",)),
    ("502.gcc_r", "gcc", "rate", ("int",)),
    ("503.bwaves_r", "bwaves", "rate", ("fp",)),
    ("505.mcf_r", "mcf", "rate", ("int",)),
    ("507.cactuBSSN_r", "cactuBSSN", "rate", ("fp",)),
    ("508.namd_r", "namd", "rate", ("fp",)),
    ("510.parest_r", "parest", "rate", ("fp",)),
    ("511.povray_r", "povray", "rate", ("fp",)),
    ("519.lbm_r", "lbm", "rate", ("fp",)),
    ("520.omnetpp_r", "omnetpp", "rate", ("int",)),
    ("521.wrf_r", "wrf", "rate", ("fp",)),
    ("523.xalancbmk_r", "xalancbmk", "rate", ("int",)),
    ("525.x264_r", "x264", "rate", ("int",)),
    ("526.blender_r", "blender", "rate", ("fp",)),
    ("527.cam4_r", "cam4", "rate", ("fp",)),
    ("531.deepsjeng_r", "deepsjeng", "rate", ("int",)),
    ("538.imagick_r", "imagick", "rate", ("fp",)),
    ("541.leela_r", "leela", "rate", ("int",)),
    ("544.nab_r", "nab", "rate", ("fp",)),
    ("548.exchange2_r", "exchange2", "rate", ("int",)),
    ("549.fotonik3d_r", "fotonik3d", "rate", ("fp",)),
    ("554.roms_r", "roms", "rate", ("fp",)),
    ("557.xz_r", "xz", "rate", ("int",)),
    ("600.perlbench_s", "perlbench", "speed", ("int",)),
    ("602.gcc_s", "gcc", "speed", ("int",)),
    ("603.bwaves_s", "bwaves", "speed", ("fp",)),
    ("605.mcf_s", "mcf", "speed", ("int",)),
    ("607.cactuBSSN_s", "cactuBSSN", "speed", ("fp",)),
    ("619.lbm_s", "lbm", "speed", ("fp",)),
    ("620.omnetpp_s", "omnetpp", "speed", ("int",)),
    ("621.wrf_s", "wrf", "speed", ("fp",)),
    ("623.xalancbmk_s", "xalancbmk", "speed", ("int",)),
    ("625.x264_s", "x264", "speed", ("int",)),
    ("627.cam4_s", "cam4", "speed", ("fp",)),
    ("628.pop2_s", "pop2", "speed", ("fp",)),
    ("631.deepsjeng_s", "deepsjeng", "speed", ("int",)),
    ("638.imagick_s", "imagick", "speed", ("fp",)),
    ("641.leela_s", "leela", "speed", ("int",)),
    ("644.nab_s", "nab", "speed", ("fp",)),
    ("648.exchange2_s", "exchange2", "speed", ("int",)),
    ("649.fotonik3d_s", "fotonik3d", "speed", ("fp",)),
    ("654.roms_s", "roms", "speed", ("fp",)),
    ("657.xz_s", "xz", "speed", ("int",)),
    ("996.specrand_fs", "specrand_f", "speed", ("fp",)),
    ("997.specrand_fr", "specrand_f", "rate", ("fp",)),
    ("998.specrand_is", "specrand_i", "speed", ("int",)),
    ("999.specrand_ir", "specrand_i", "rate", ("int",)),
)

WORKLOADS_BY_MODE = {
    "rate": ("test", "train", "refrate"),
    "speed": ("test", "train", "refspeed"),
}

INPUT_ALIASES = {
    "ref": {"rate": "refrate", "speed": "refspeed"},
    "refrate": {"rate": "refrate"},
    "refspeed": {"speed": "refspeed"},
    "test": {"rate": "test", "speed": "test"},
    "train": {"rate": "train", "speed": "train"},
}


def format_cmd(cmd):
    return " ".join(shlex.quote(str(part)) for part in cmd)


def progress_prefix():
    current = os.environ.get("SPEC2017_PROGRESS_K", "1")
    total = os.environ.get("SPEC2017_PROGRESS_N", "1")
    return f"[spec2017 {current}/{total}]"


def status(message):
    print(f"{progress_prefix()} {message}", flush=True)


def read_log_tail(log_path, max_lines=40):
    with open(log_path, "r", encoding="utf-8", errors="replace") as f:
        lines = deque(f, maxlen=max_lines)
    return "".join(lines).rstrip()


def maybe_read_log_tail(log_path, max_lines=40):
    if log_path.is_file():
        tail = read_log_tail(log_path, max_lines=max_lines)
        if tail:
            return f"\nLast log lines from {log_path}:\n{tail}"
    return ""


def run(cmd, *, env=None, cwd=None, log_path=None, summary=None, capture=False):
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
            stdout=subprocess.PIPE if capture else log,
            stderr=subprocess.STDOUT,
            text=True,
        )
        if capture and result.stdout:
            log.write(result.stdout)
        log.write("\n")
    if result.returncode != 0:
        tail = read_log_tail(log_path)
        detail = f"\nLast log lines from {log_path}:\n{tail}" if tail else ""
        raise RuntimeError(f"command failed: {command_text}\nSee {log_path}{detail}")
    return result.stdout if capture else None


def file_sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def case_name(short, mode, workload):
    return f"{short}_{mode}_{workload}"


def all_cases():
    cases = {}
    for bench_dir, short, mode, tags in BENCHMARKS:
        for workload in WORKLOADS_BY_MODE[mode]:
            name = case_name(short, mode, workload)
            cases[name] = {
                "bench_dir": bench_dir,
                "short": short,
                "mode": mode,
                "workload": workload,
                "tags": [*tags, mode, workload],
            }
    return cases


def filter_cases(cases, input_set, mode):
    selected = {}
    for name, case in cases.items():
        if mode not in (None, "", "all") and case["mode"] != mode:
            continue
        if input_set not in (None, "", "all"):
            if input_set == "ref":
                if case["workload"] not in ("refrate", "refspeed"):
                    continue
            elif case["workload"] != input_set:
                continue
        selected[name] = case
    return selected


def resolve_case_name(bench, input_set, mode):
    cases = all_cases()
    if not bench:
        return ""
    if bench in cases:
        return bench
    if input_set not in INPUT_ALIASES:
        raise RuntimeError("SPEC2017_INPUT must be one of: test, train, ref, refrate, refspeed, all")
    if mode not in ("rate", "speed"):
        raise RuntimeError("MODE/SPEC2017_MODE must be rate or speed for a single BENCH build")
    workload = INPUT_ALIASES[input_set].get(mode)
    if workload is None:
        raise RuntimeError(f"input {input_set!r} is not valid for mode {mode!r}")
    matches = [case for case in cases.values() if case["short"] == bench and case["mode"] == mode and case["workload"] == workload]
    if len(matches) != 1:
        choices = " ".join(sorted(cases))
        raise RuntimeError(f"cannot resolve BENCH={bench!r}; use a full case name. Available cases: {choices}")
    return case_name(matches[0]["short"], mode, workload)


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
    return str(gcc_path)[: -len("gcc")], gcc_path.parent.parent


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


def tree_metadata(source):
    source = Path(source).resolve()
    archive = source / "install_archives" / "cpu2017.tar.xz"
    if archive.is_file():
        return {
            "source": str(source),
            "archive_size": archive.stat().st_size,
            "archive_mtime_ns": archive.stat().st_mtime_ns,
        }
    return {"source": str(source)}


def spec_tree_complete(path):
    cpu_root = path / "benchspec" / "CPU"
    return (path / "bin" / "specperl").is_file() and all((cpu_root / bench_dir).is_dir() for bench_dir, *_ in BENCHMARKS)


def prepared_workspace_meta(path):
    meta = path / ".workload-builder-prepare.meta"
    if meta.is_file():
        return meta.read_text(encoding="utf-8", errors="replace")
    return ""


def make_tree_user_writable(path):
    for root, dirs, files in os.walk(path, followlinks=False):
        root_path = Path(root)
        try:
            root_path.chmod(root_path.stat().st_mode | 0o700)
        except OSError:
            pass
        for name in dirs:
            dir_path = root_path / name
            if dir_path.is_symlink():
                continue
            try:
                dir_path.chmod(dir_path.stat().st_mode | 0o700)
            except OSError:
                pass
        for name in files:
            file_path = root_path / name
            if file_path.is_symlink():
                continue
            try:
                file_path.chmod(file_path.stat().st_mode | 0o600)
            except OSError:
                pass


def copy_spec_source(source, dest, log_path):
    source = Path(source).resolve()
    metadata_path = dest / ".workload-builder-source.json"
    desired = tree_metadata(source)
    if metadata_path.is_file():
        try:
            if load_json(metadata_path) == desired and (
                (dest / "install.sh").is_file() or (dest / "bin" / "runcpu").is_file()
            ):
                return
        except Exception:
            pass
    if dest.exists():
        shutil.rmtree(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    status(f"Copying SPEC2017 source tree to {dest}")
    run(["cp", "-R", "--reflink=auto", str(source), str(dest)], log_path=log_path, summary=f"Copying source tree (log: {log_path})")
    make_tree_user_writable(dest)
    write_json(metadata_path, desired)


def install_spec_tree(source_copy, spec_tree, log_path):
    if spec_tree_complete(spec_tree):
        return spec_tree
    if spec_tree_complete(source_copy):
        return source_copy
    marker = spec_tree / ".workload-builder-installed"
    if marker.is_file() and spec_tree_complete(spec_tree):
        return spec_tree
    if spec_tree.exists():
        shutil.rmtree(spec_tree)
    spec_tree.parent.mkdir(parents=True, exist_ok=True)
    status(f"Installing SPEC2017 working tree to {spec_tree}")
    env = os.environ.copy()
    env["SPEC_NOCHECK"] = "1"
    run(
        [str(source_copy / "install.sh"), "-f", "-d", str(spec_tree)],
        cwd=source_copy,
        env=env,
        log_path=log_path,
        summary=f"Installing SPEC2017 tree (log: {log_path})",
    )
    marker.write_text("installed\n", encoding="utf-8")
    return spec_tree


def prepare_spec_tree(spec_source, out_dir, log_dir):
    base_dir = out_dir.parent
    source_copy = base_dir / "spec-source"
    spec_tree = base_dir / "spec-tree"
    prepare_log = log_dir / "prepare-spec-tree.log"
    copy_spec_source(spec_source, source_copy, prepare_log)
    return install_spec_tree(source_copy, spec_tree, prepare_log)


def build_local_config(template_cfg, generated_cfg, output_root, jobs):
    text = template_cfg.read_text(encoding="utf-8")
    filtered_lines = []
    for line in text.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("output_root") and "=" in line:
            continue
        if stripped.startswith("makeflags") and "=" in line:
            continue
        filtered_lines.append(line)
    generated_cfg.parent.mkdir(parents=True, exist_ok=True)
    generated_cfg.write_text(
        "\n".join(
            [
                "# Auto-generated by spec2017-package.py",
                f"# Template: {template_cfg}",
                f"output_root = {output_root}",
                f"makeflags = -j{jobs}",
                "",
                *filtered_lines,
                "",
            ]
        ),
        encoding="utf-8",
    )
    return generated_cfg


def shared_build_dir_for(out_dir, bench_dir, tune):
    return out_dir.parent / "_bench-builds" / bench_dir / tune


def shared_build_metadata(spec_cfg, spec_source, cross_compile, tune, compiler_root, gnu_toolchain_root):
    return {
        "spec_cfg_sha256": file_sha256(spec_cfg),
        "spec_source": str(spec_source),
        "spec_source_meta": prepared_workspace_meta(Path(spec_source)),
        "cross_compile": cross_compile,
        "tune": tune,
        "compiler_root": str(compiler_root),
        "gnu_toolchain_root": str(gnu_toolchain_root),
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


def explain_missing_elf(output_root, bench_dir, tune):
    build_root = output_root / "benchspec" / "CPU" / bench_dir / "build"
    if not build_root.is_dir():
        return ""
    build_dirs = sorted(path for path in build_root.iterdir() if path.is_dir())
    if not build_dirs:
        return ""
    latest = max(build_dirs, key=lambda path: path.stat().st_mtime)
    details = [f"Latest build directory: {latest}"]
    for name in ("make.err", "make.out"):
        tail = maybe_read_log_tail(latest / name)
        if tail:
            details.append(tail.lstrip("\n"))
            break
    return "\n" + "\n".join(details)


def export_build_log_artifact(build_log, out_dir):
    if not build_log.is_file():
        return None
    log_dir = out_dir / "logs" / "build_elf"
    log_dir.mkdir(parents=True, exist_ok=True)
    exported_log = log_dir / build_log.name
    shutil.copy2(build_log, exported_log)
    return exported_log


def runcpu_env(spec_dir, compiler_root, gnu_toolchain_root):
    env = os.environ.copy()
    env.update(spec_env(spec_dir))
    env["SPEC"] = str(spec_dir)
    env["SPEC2017_COMPILER_ROOT"] = str(compiler_root)
    env["SPEC2017_GNU_TOOLCHAIN_ROOT"] = str(gnu_toolchain_root)
    return env


def build_elf(spec_dir, bench_dir, spec_cfg, spec_source, out_dir, log_dir, cross_compile, tune, jobs, compiler_root, gnu_toolchain_root):
    shared_dir = shared_build_dir_for(out_dir, bench_dir, tune)
    output_root = shared_dir / "runcpu-output"
    generated_cfg = shared_dir / "runcpu-config" / spec_cfg.name
    shared_log_dir = shared_dir / "logs"
    build_log = shared_log_dir / "build.log"
    exe_dir = output_root / "benchspec" / "CPU" / bench_dir / "exe"
    metadata_path = shared_dir / "build-meta.json"
    metadata = shared_build_metadata(spec_cfg, spec_source, cross_compile, tune, compiler_root, gnu_toolchain_root)
    if metadata_path.is_file():
        try:
            cached_metadata = load_json(metadata_path)
        except Exception:
            cached_metadata = None
        if cached_metadata == metadata:
            try:
                elf = select_built_elf(exe_dir, tune)
            except Exception:
                elf = None
            if elf is not None:
                status(f"Reusing {bench_dir} build from {shared_dir}")
                export_build_log_artifact(build_log, out_dir)
                return elf, output_root
    if output_root.exists():
        shutil.rmtree(output_root)
    if generated_cfg.parent.exists():
        shutil.rmtree(generated_cfg.parent)
    if shared_log_dir.exists():
        shutil.rmtree(shared_log_dir)
    shared_log_dir.mkdir(parents=True, exist_ok=True)
    build_local_config(spec_cfg, generated_cfg, output_root, jobs)
    status(f"Generated SPEC cfg: {generated_cfg}")
    env = runcpu_env(spec_dir, compiler_root, gnu_toolchain_root)
    cmd = [
        str(spec_dir / "bin" / "runcpu"),
        "--action",
        "build",
        "--config",
        str(generated_cfg),
        "--tune",
        tune,
        "--noreportable",
        "--iterations",
        "1",
        bench_dir,
    ]
    run(cmd, cwd=spec_dir, env=env, log_path=build_log, summary=f"Building {bench_dir} with runcpu (log: {build_log})")
    try:
        elf = select_built_elf(exe_dir, tune)
    except RuntimeError as exc:
        detail = explain_missing_elf(output_root, bench_dir, tune)
        raise RuntimeError(str(exc) + detail) from exc
    write_json(metadata_path, metadata)
    export_build_log_artifact(build_log, out_dir)
    return elf, output_root


def export_elf_artifact(elf, case_name_value, out_dir):
    elf_dir = out_dir / "elf"
    elf_dir.mkdir(parents=True, exist_ok=True)
    exported_elf = elf_dir / f"{case_name_value}.elf"
    shutil.copy2(elf, exported_elf)
    return exported_elf


def select_run_dir(output_root, bench_dir, tune, workload):
    run_root = output_root / "benchspec" / "CPU" / bench_dir / "run"
    if not run_root.is_dir():
        raise RuntimeError(f"runcpu did not create run directory root: {run_root}")
    pattern = f"run_{tune}_{workload}_"
    candidates = [path for path in run_root.iterdir() if path.is_dir() and path.name.startswith(pattern)]
    if not candidates:
        available = " ".join(sorted(path.name for path in run_root.iterdir() if path.is_dir()))
        raise RuntimeError(f"no run directory matching {pattern!r} under {run_root}; available: {available}")
    return max(candidates, key=lambda path: path.stat().st_mtime)


def prepare_run_dir(spec_dir, bench_dir, workload, generated_output_root, spec_cfg, tune, log_dir, compiler_root, gnu_toolchain_root):
    setup_log = log_dir / "runsetup.log"
    env = runcpu_env(spec_dir, compiler_root, gnu_toolchain_root)
    cmd = [
        str(spec_dir / "bin" / "runcpu"),
        "--action",
        "runsetup",
        "--config",
        str(spec_cfg),
        "--tune",
        tune,
        "--size",
        workload,
        "--copies",
        "1",
        "--noreportable",
        "--iterations",
        "1",
        bench_dir,
    ]
    run(cmd, cwd=spec_dir, env=env, log_path=setup_log, summary=f"Preparing run directory for {bench_dir}/{workload} (log: {setup_log})")
    return select_run_dir(generated_output_root, bench_dir, tune, workload)


def copy_tree_contents(src, dst):
    dst.mkdir(parents=True, exist_ok=True)
    for item in src.iterdir():
        target = dst / item.name
        if item.is_symlink():
            if target.exists() or target.is_symlink():
                target.unlink()
            os.symlink(os.readlink(item), target)
        elif item.is_dir():
            if target.exists():
                shutil.rmtree(target)
            shutil.copytree(item, target, symlinks=True)
        else:
            shutil.copy2(item, target)


def shell_from_specinvoke(spec_dir, run_dir, log_dir):
    cmd_file = run_dir / "speccmds.cmd"
    if not cmd_file.is_file():
        raise RuntimeError(f"speccmds.cmd not found in run directory: {run_dir}")
    log_path = log_dir / "specinvoke-dryrun.log"
    env = os.environ.copy()
    env.update(spec_env(spec_dir))
    output = run(
        [str(spec_dir / "bin" / "specinvoke"), "-nn", str(cmd_file)],
        cwd=run_dir,
        env=env,
        log_path=log_path,
        summary=f"Rendering speccmds.cmd to shell (log: {log_path})",
        capture=True,
    )
    commands = []
    run_dir_ref = f"../{run_dir.name}/"
    for line in output.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith("specinvoke exit:"):
            continue
        if stripped.startswith("export ") or stripped.startswith("unset ") or stripped.startswith("cd "):
            continue
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", stripped):
            continue
        line = line.replace(run_dir_ref, "./")
        line = line.replace(str(run_dir) + "/", "./")
        line = line.replace(str(run_dir), "/spec")
        commands.append(line)
    if not commands:
        raise RuntimeError(f"specinvoke produced no runnable shell commands from {cmd_file}")
    return commands


def sanitize_name(value):
    value = re.sub(r"[^A-Za-z0-9_.+-]+", "_", value)
    value = re.sub(r"_+", "_", value).strip("._-")
    return value or "run"


def command_label(command, index):
    match = re.search(r"(?:^|[ \t])(?:1?>|>>)\s*([^ \t]+)", command)
    if match:
        label = match.group(1).strip("'\"")
        if label.endswith(".out"):
            label = label[:-4]
        return sanitize_name(label)
    words = shlex.split(command, posix=True)
    if words:
        return sanitize_name(Path(words[0]).name)
    return f"run{index}"


def run_variants(case_name_value, run_commands):
    total = len(run_commands)
    seen = {}
    variants = []
    for index, command in enumerate(run_commands):
        label = command_label(command, index)
        if total == 1:
            name = case_name_value
        else:
            name = f"{case_name_value}_{index:02d}_{label}"
        count = seen.get(name, 0)
        seen[name] = count + 1
        if count:
            name = f"{name}_{count}"
        commands = [command]
        # x264 pass 2 depends on stats produced by the immediately previous pass 1 run.
        if index > 0 and "--pass 2" in command and "--stats " in command and "--pass 1" in run_commands[index - 1]:
            commands = [run_commands[index - 1], command]
        variants.append({"name": name, "index": index, "commands": commands})
    return variants


def write_variants_metadata(out_dir, variants):
    serializable = []
    for variant in variants:
        serializable.append(
            {
                "command_count": len(variant["commands"]),
                "name": variant["name"],
                "index": variant["index"],
                "build_dir": str(variant["build_dir"]),
            }
        )
    write_json(out_dir / "variants.json", serializable)


def write_runtime_files(pkg_dir, case_name_value, run_commands, profiling):
    spec_root = pkg_dir / "spec"
    run_sh = spec_root / "run.sh"
    script_lines = [
        "#!/bin/sh",
        "set -e",
        "mkdir -p /proc /sys /tmp",
        "mount -t proc proc /proc 2>/dev/null || true",
        "mount -t sysfs sysfs /sys 2>/dev/null || true",
        "cd /spec",
        "export LC_ALL=C",
        "export OMP_NUM_THREADS=1",
        "export OMP_THREAD_LIMIT=1",
        "ulimit -s unlimited 2>/dev/null || true",
        f"echo '======== BEGIN {case_name_value} ========'",
        "date -R || true",
        "status=0",
        "set +e",
    ]
    for command in run_commands:
        command_lines = [
            "if [ \"$status\" -eq 0 ]; then",
            f"  spec_cmd={shlex.quote(command)}",
            "  echo \"CMD: $spec_cmd\"",
        ]
        if profiling == "1":
            command_lines.extend(["  nemu-trap 256", "  nemu-trap 257"])
        command_lines.extend(
            [
                "  sh -c \"$spec_cmd\"",
                "  status=$?",
            ]
        )
        command_lines.append("  nemu-trap \"$status\"")
        command_lines.append("fi")
        script_lines.extend(
            command_lines
        )
    script_lines.extend(
        [
            "set -e",
            "if [ \"$status\" -ne 0 ]; then",
            "  echo \"SPEC2017 command failed with status $status\"",
            "  for log in *.err *.out; do",
            "    [ -f \"$log\" ] || continue",
            "    echo \"----- $log -----\"",
            "    tail -n 40 \"$log\" || true",
            "  done",
            "fi",
            "date -R || true",
            f"echo '======== END   {case_name_value} ========'",
            "exit $status",
            "",
        ]
    )
    run_sh.write_text("\n".join(script_lines), encoding="utf-8")
    run_sh.chmod(0o755)
    etc = pkg_dir / "etc"
    etc.mkdir(parents=True, exist_ok=True)
    (etc / "inittab").write_text("::once:/bin/sh /spec/run.sh\n", encoding="utf-8")


def package_runtime_variant(variant, run_dir, profiling):
    build_dir = variant["build_dir"]
    pkg_dir = build_dir / "package"
    if pkg_dir.exists():
        shutil.rmtree(pkg_dir)
    (pkg_dir / "spec").mkdir(parents=True)
    status(f"Packaging rootfs for {variant['name']}")
    copy_tree_contents(run_dir, pkg_dir / "spec")
    write_runtime_files(pkg_dir, variant["name"], variant["commands"], profiling)


def package_case(args):
    cases = all_cases()
    if args.case not in cases:
        choices = " ".join(sorted(cases))
        raise RuntimeError(f"unknown SPEC2017 case {args.case!r}; available cases: {choices}")
    case = cases[args.case]
    spec_source = Path(args.spec_source).resolve()
    if not spec_tree_complete(spec_source):
        raise RuntimeError(f"SPEC2017 workspace is not prepared: {spec_source}")
    spec_cfg = Path(args.spec_config).resolve()
    pkg_dir = Path(args.pkg_dir).resolve() if args.pkg_dir else None
    out_dir = Path(args.out_dir).resolve()
    log_dir = Path(args.log_dir).resolve() if args.log_dir else out_dir / "logs"
    spec_dir = spec_source
    cross_compile, detected_toolchain_root = resolve_cross_compile(args.cross_compile)
    compiler_root = Path(args.compiler_root).resolve() if args.compiler_root else detected_toolchain_root
    gnu_toolchain_root = Path(args.gnu_toolchain_root).resolve() if args.gnu_toolchain_root else detected_toolchain_root
    elf, output_root = build_elf(
        spec_dir,
        case["bench_dir"],
        spec_cfg,
        spec_source,
        out_dir,
        log_dir,
        cross_compile,
        args.tune,
        args.jobs,
        compiler_root,
        gnu_toolchain_root,
    )
    exported_elf = export_elf_artifact(elf, args.case, out_dir)
    status(f"Exported ELF: {exported_elf}")
    if args.elf_only:
        return
    run_dir = prepare_run_dir(
        spec_dir,
        case["bench_dir"],
        case["workload"],
        output_root,
        shared_build_dir_for(out_dir, case["bench_dir"], args.tune) / "runcpu-config" / spec_cfg.name,
        args.tune,
        log_dir,
        compiler_root,
        gnu_toolchain_root,
    )
    run_commands = shell_from_specinvoke(spec_dir, run_dir, log_dir)
    if args.all_runs:
        variants = run_variants(args.case, run_commands)
        variant_root = out_dir / "runs"
        if variant_root.exists():
            shutil.rmtree(variant_root)
        for variant in variants:
            variant["build_dir"] = variant_root / variant["name"]
            package_runtime_variant(variant, run_dir, args.profiling)
        write_variants_metadata(out_dir, variants)
        return
    if pkg_dir is None:
        raise RuntimeError("--pkg-dir is required unless --elf-only is set")
    if pkg_dir.exists():
        shutil.rmtree(pkg_dir)
    (pkg_dir / "spec").mkdir(parents=True)
    status(f"Packaging rootfs for {args.case}")
    copy_tree_contents(run_dir, pkg_dir / "spec")
    write_runtime_files(pkg_dir, args.case, run_commands, args.profiling)


def prepare_only(args):
    spec_source = Path(args.spec_source).resolve()
    out_dir = Path(args.out_dir).resolve()
    log_dir = Path(args.log_dir).resolve() if args.log_dir else out_dir / "logs"
    spec_dir = prepare_spec_tree(spec_source, out_dir, log_dir)
    status(f"Prepared SPEC2017 working tree: {spec_dir}")


def list_packaged_variants(args):
    out_dir = Path(args.out_dir).resolve()
    variants_path = out_dir / "variants.json"
    if not variants_path.is_file():
        raise RuntimeError(f"variant metadata not found: {variants_path}")
    variants = load_json(variants_path)
    for variant in variants:
        print(f"{variant['name']}\t{variant['build_dir']}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--list-cases", action="store_true")
    parser.add_argument("--resolve-case", action="store_true")
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--list-packaged-variants", action="store_true")
    parser.add_argument("--bench")
    parser.add_argument("--input-set", choices=("test", "train", "ref", "refrate", "refspeed", "all"), default="all")
    parser.add_argument("--mode", choices=("rate", "speed", "all"), default="all")
    parser.add_argument("--case")
    parser.add_argument("--spec-source")
    parser.add_argument("--spec-config")
    parser.add_argument("--pkg-dir")
    parser.add_argument("--out-dir")
    parser.add_argument("--cross-compile", default="riscv64-unknown-linux-gnu-")
    parser.add_argument("--compiler-root")
    parser.add_argument("--gnu-toolchain-root")
    parser.add_argument("--log-dir")
    parser.add_argument("--tune", default="base")
    parser.add_argument("--jobs", default=str(os.cpu_count() or 1))
    parser.add_argument("--elf-only", action="store_true")
    parser.add_argument("--all-runs", action="store_true")
    parser.add_argument("--profiling", choices=("0", "1"), default="1")
    args = parser.parse_args()
    if args.list_cases:
        print(" ".join(filter_cases(all_cases(), args.input_set, args.mode).keys()))
        return
    if args.resolve_case:
        try:
            print(resolve_case_name(args.bench, args.input_set, args.mode))
        except Exception as exc:
            parser.error(str(exc))
        return
    if args.prepare_only:
        missing = [name for name in ("spec_source", "out_dir") if getattr(args, name) in (None, "")]
        if missing:
            parser.error("missing required arguments: " + ", ".join("--" + x.replace("_", "-") for x in missing))
        try:
            prepare_only(args)
        except Exception as exc:
            print(f"{progress_prefix()} error: {exc}", file=sys.stderr)
            sys.exit(1)
        return
    if args.list_packaged_variants:
        if not args.out_dir:
            parser.error("--out-dir is required with --list-packaged-variants")
        try:
            list_packaged_variants(args)
        except Exception as exc:
            print(f"{progress_prefix()} error: {exc}", file=sys.stderr)
            sys.exit(1)
        return
    required = ["case", "spec_source", "spec_config", "out_dir", "cross_compile"]
    if not args.elf_only:
        required.append("pkg_dir")
    missing = [name for name in required if getattr(args, name) in (None, "")]
    if missing:
        parser.error("missing required arguments: " + ", ".join("--" + x.replace("_", "-") for x in missing))
    try:
        package_case(args)
    except Exception as exc:
        print(f"{progress_prefix()} error: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
