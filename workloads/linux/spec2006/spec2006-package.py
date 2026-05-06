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


def format_cmd(cmd):
    return " ".join(shlex.quote(str(part)) for part in cmd)


def progress_prefix():
    current = os.environ.get("SPEC2006_PROGRESS_K", "1")
    total = os.environ.get("SPEC2006_PROGRESS_N", "1")
    return f"[spec2006 {current}/{total}]"


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


def load_cases(path):
    with open(path, "r", encoding="utf-8") as f:
        cases = json.load(f)
    if not isinstance(cases, dict):
        raise RuntimeError(f"case config must be a JSON object: {path}")
    return cases


def file_sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def filter_cases(cases, input_set):
    if input_set in (None, "", "all"):
        return cases
    if input_set not in INPUT_SETS:
        choices = ", ".join((*INPUT_SETS, "all"))
        raise RuntimeError(f"unknown SPEC2006 input set {input_set!r}; available: {choices}")
    return {
        name: case
        for name, case in cases.items()
        if input_set in case.get("type", [])
    }


def input_set_for_case(case):
    for name in INPUT_SETS:
        if name in case.get("type", []):
            return name
    raise RuntimeError(f"case has no input set marker in type: {case.get('type')}")


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


def bench_dir_for_base(spec_dir, base_name):
    root = spec_dir / "benchspec" / "CPU2006"
    matches = []
    for path in root.iterdir():
        if not path.is_dir() or "." not in path.name:
            continue
        suffix = path.name.split(".", 1)[1]
        if suffix == base_name:
            matches.append(path.name)
    if len(matches) != 1:
        raise RuntimeError(f"cannot map base benchmark {base_name!r} to SPEC benchmark directory")
    return matches[0]


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


def copy_tree_contents(src, dst):
    if not src.is_dir():
        return
    dst.mkdir(parents=True, exist_ok=True)
    for item in src.iterdir():
        target = dst / item.name
        if item.is_dir():
            if target.exists():
                shutil.rmtree(target)
            shutil.copytree(item, target, symlinks=True)
        else:
            shutil.copy2(item, target)


def stage_inputs(spec_dir, bench_dir, base_name, input_set, stage_root):
    bench_data = spec_dir / "benchspec" / "CPU2006" / bench_dir / "data"
    if stage_root.exists():
        shutil.rmtree(stage_root)
    base_stage = stage_root / base_name
    base_stage.mkdir(parents=True)
    copy_tree_contents(bench_data / "all" / "input", base_stage)
    copy_tree_contents(bench_data / input_set / "input", base_stage)
    return stage_root


def install_case_files(case, stage_root, spec_root):
    spec_root.mkdir(parents=True, exist_ok=True)
    for entry in case.get("files", []):
        parts = entry.split()
        if len(parts) == 3 and parts[0] == "dir":
            _, dest_name, rel_path = parts
            src = stage_root / rel_path
            if not src.is_dir():
                raise RuntimeError(f"missing SPEC input directory {src}")
            if dest_name == ".":
                copy_tree_contents(src, spec_root)
            else:
                dst = spec_root / dest_name
                if dst.exists():
                    shutil.rmtree(dst)
                shutil.copytree(src, dst, symlinks=True)
        elif len(parts) == 1:
            src = stage_root / entry
            if not src.is_file():
                raise RuntimeError(f"missing SPEC input file {src}")
            shutil.copy2(src, spec_root / src.name)
        else:
            raise RuntimeError(f"unsupported SPEC file entry: {entry}")


def shell_command(binary_name, args):
    before_redirect = []
    stdin_file = None
    iterator = iter(args)
    for arg in iterator:
        if arg == "<":
            try:
                stdin_file = next(iterator)
            except StopIteration as exc:
                raise RuntimeError("input redirection without file") from exc
            rest = list(iterator)
            if rest:
                raise RuntimeError(f"unsupported arguments after input redirection: {rest}")
            break
        before_redirect.append(arg)

    words = ["./" + binary_name] + before_redirect
    cmd = " ".join(shlex.quote(x) for x in words)
    if stdin_file is not None:
        cmd += " < " + shlex.quote(stdin_file)
    return cmd


def write_runtime_files(pkg_dir, case_name, binary_name, args):
    spec_root = pkg_dir / "spec"
    command = shell_command(binary_name, args)
    run_sh = spec_root / "run.sh"
    run_sh.write_text(
        "\n".join(
            [
                "#!/bin/sh",
                "set -e",
                "cd /spec",
                f"echo '======== BEGIN {case_name} ========'",
                f"md5sum ./{shlex.quote(binary_name)}",
                "date -R || true",
                f"spec_cmd={shlex.quote(command)}",
                "echo \"CMD: $spec_cmd\"",
                "set +e",
                "sh -c \"$spec_cmd\"",
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


def export_elf_artifact(elf, case_name, out_dir):
    elf_dir = out_dir / "elf"
    elf_dir.mkdir(parents=True, exist_ok=True)
    exported_elf = elf_dir / f"{case_name}.elf"
    shutil.copy2(elf, exported_elf)
    return exported_elf


def install_runtime_binary(elf, binary_name, pkg_dir):
    spec_root = pkg_dir / "spec"
    shutil.copy2(elf, spec_root / binary_name)
    (spec_root / binary_name).chmod(0o755)


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
                "# Auto-generated by spec2006-package.py",
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


def shared_build_metadata(spec_cfg, spec_dir, cross_compile, tune, compiler_root, gnu_toolchain_root, jemalloc_root):
    return {
        "spec_cfg_sha256": file_sha256(spec_cfg),
        "spec_dir": str(spec_dir),
        "cross_compile": cross_compile,
        "tune": tune,
        "compiler_root": str(compiler_root),
        "gnu_toolchain_root": str(gnu_toolchain_root),
        "jemalloc_root": str(jemalloc_root),
    }


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def select_built_elf(exe_dir, tune):
    if not exe_dir.is_dir():
        raise RuntimeError(f"runspec did not create exe directory: {exe_dir}")
    candidates = [path for path in exe_dir.iterdir() if path.is_file() and not path.name.endswith(".md5")]
    if not candidates:
        raise RuntimeError(f"no executable produced by runspec under {exe_dir}")
    preferred = [path for path in candidates if f"_{tune}." in path.name]
    if preferred:
        candidates = preferred
    return max(candidates, key=lambda path: path.stat().st_mtime)


def explain_missing_elf(output_root, bench_dir, tune):
    build_root = output_root / "benchspec" / "CPU2006" / bench_dir / "build"
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


def cfg_requires_jemalloc(spec_cfg):
    text = spec_cfg.read_text(encoding="utf-8")
    return "JEMALLOC_PATH" in text or "-ljemalloc" in text


def build_elf(spec_dir, bench_dir, spec_cfg, out_dir, log_dir, cross_compile, tune, jobs, compiler_root, gnu_toolchain_root, jemalloc_root):
    shared_dir = shared_build_dir_for(out_dir, bench_dir, tune)
    output_root = shared_dir / "runspec-output"
    generated_cfg = shared_dir / "runspec-config" / spec_cfg.name
    shared_log_dir = shared_dir / "logs"
    build_log = shared_log_dir / "build.log"
    exe_dir = output_root / "benchspec" / "CPU2006" / bench_dir / "exe"
    metadata_path = shared_dir / "build-meta.json"
    metadata = shared_build_metadata(
        spec_cfg,
        spec_dir,
        cross_compile,
        tune,
        compiler_root,
        gnu_toolchain_root,
        jemalloc_root,
    )

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
                return elf, build_log

    if output_root.exists():
        shutil.rmtree(output_root)
    if generated_cfg.parent.exists():
        shutil.rmtree(generated_cfg.parent)
    if shared_log_dir.exists():
        shutil.rmtree(shared_log_dir)
    shared_log_dir.mkdir(parents=True, exist_ok=True)

    build_local_config(spec_cfg, generated_cfg, output_root, jobs)
    status(f"Generated SPEC cfg: {generated_cfg}")

    env = os.environ.copy()
    env.update(spec_env(spec_dir))
    env["SPEC"] = str(spec_dir)
    env["LLVM_INSTALL_PATH"] = str(compiler_root)
    env["GNU_RISCV64_PATH"] = str(gnu_toolchain_root)
    env["JEMALLOC_INSTALL_PATH"] = str(jemalloc_root)

    runspec = spec_dir / "bin" / "runspec"
    cmd = [
        str(runspec),
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
    run(
        cmd,
        cwd=spec_dir,
        env=env,
        log_path=build_log,
        summary=f"Building {bench_dir} with runspec (log: {build_log})",
    )

    try:
        elf = select_built_elf(exe_dir, tune)
    except RuntimeError as exc:
        detail = explain_missing_elf(output_root, bench_dir, tune)
        raise RuntimeError(str(exc) + detail) from exc
    write_json(metadata_path, metadata)
    return elf, build_log


def package_case(args):
    cases = load_cases(args.cases_config)
    if args.case not in cases:
        choices = " ".join(sorted(cases))
        raise RuntimeError(f"unknown SPEC2006 case {args.case!r}; available cases: {choices}")

    spec_dir = Path(args.spec).resolve()
    spec_cfg = Path(args.spec_config).resolve()
    pkg_dir = Path(args.pkg_dir).resolve() if args.pkg_dir else None
    out_dir = Path(args.out_dir).resolve()
    log_dir = Path(args.log_dir).resolve() if args.log_dir else out_dir / "logs"

    cross_compile, detected_toolchain_root = resolve_cross_compile(args.cross_compile)
    compiler_root = Path(args.compiler_root).resolve() if args.compiler_root else detected_toolchain_root
    gnu_toolchain_root = Path(args.gnu_toolchain_root).resolve() if args.gnu_toolchain_root else detected_toolchain_root
    env_jemalloc_root = os.environ.get("SPEC2006_JEMALLOC_ROOT") or os.environ.get("JEMALLOC_INSTALL_PATH")
    if args.jemalloc_root:
        jemalloc_root = Path(args.jemalloc_root).resolve()
    elif env_jemalloc_root:
        jemalloc_root = Path(env_jemalloc_root).resolve()
    else:
        jemalloc_root = (out_dir.parent / "jemalloc" / "install").resolve()

    jemalloc_library = jemalloc_root / "lib" / "libjemalloc.a"
    if cfg_requires_jemalloc(spec_cfg) and not jemalloc_library.is_file():
        raise RuntimeError(
            f"jemalloc library not found: {jemalloc_library}; "
            "set SPEC2006_JEMALLOC_ROOT or JEMALLOC_INSTALL_PATH to a valid install prefix"
        )

    case = cases[args.case]
    base_name = case["base_name"]
    bench_dir = bench_dir_for_base(spec_dir, base_name)
    input_set = input_set_for_case(case)

    elf, build_log = build_elf(
        spec_dir,
        bench_dir,
        spec_cfg,
        out_dir,
        log_dir,
        cross_compile,
        args.tune,
        args.jobs,
        compiler_root,
        gnu_toolchain_root,
        jemalloc_root,
    )
    exported_elf = export_elf_artifact(elf, args.case, out_dir)
    status(f"Exported ELF: {exported_elf}")

    if args.elf_only:
        return

    stage_root = out_dir / "spec-stage" / args.case
    status(f"Staging inputs for {args.case}")
    stage_inputs(spec_dir, bench_dir, base_name, input_set, stage_root)

    if pkg_dir is None:
        raise RuntimeError("--pkg-dir is required unless --elf-only is set")
    if pkg_dir.exists():
        shutil.rmtree(pkg_dir)
    (pkg_dir / "spec").mkdir(parents=True)

    status(f"Packaging rootfs for {args.case}")
    install_case_files(case, stage_root, pkg_dir / "spec")
    install_runtime_binary(elf, base_name, pkg_dir)
    write_runtime_files(pkg_dir, args.case, base_name, case.get("args", []))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cases-config")
    parser.add_argument("--list-cases", action="store_true")
    parser.add_argument("--input-set", choices=(*INPUT_SETS, "all"), default="all")
    parser.add_argument("--case")
    parser.add_argument("--spec")
    parser.add_argument("--spec-config")
    parser.add_argument("--pkg-dir")
    parser.add_argument("--out-dir")
    parser.add_argument("--cross-compile", default="riscv64-unknown-linux-gnu-")
    parser.add_argument("--compiler-root")
    parser.add_argument("--gnu-toolchain-root")
    parser.add_argument("--jemalloc-root")
    parser.add_argument("--log-dir")
    parser.add_argument("--tune", default="base")
    parser.add_argument("--jobs", default=str(os.cpu_count() or 1))
    parser.add_argument("--elf-only", action="store_true")
    args = parser.parse_args()

    if args.list_cases:
        if not args.cases_config:
            parser.error("--cases-config is required with --list-cases")
        try:
            cases = filter_cases(load_cases(args.cases_config), args.input_set)
        except Exception as exc:
            parser.error(str(exc))
        print(" ".join(cases.keys()))
        return

    required = ["cases_config", "case", "spec", "spec_config", "out_dir", "cross_compile"]
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
