#!/usr/bin/env python3
import argparse
import shutil
from pathlib import Path


def positive_harts(value):
    try:
        harts = int(value, 0)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("HARTS must be an integer") from exc
    if harts < 2:
        raise argparse.ArgumentTypeError("HARTS must be at least 2")
    return harts


def workload_name(value):
    path = Path(value)
    if not value or value in (".", "..") or path.name != value:
        raise argparse.ArgumentTypeError("workload name must be a single directory name")
    return value


def copy_workload_tree(src, dst):
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst, symlinks=True)


def write_task_script(workload_dir, workload, hart):
    task = workload_dir / "task.sh"
    workload_path = f"/{workload}{hart}"
    command = f'/bin/sh "{workload_path}/run.sh"'
    if workload == "spec":
        command = f'SPEC_ROOT="{workload_path}" {command}'
    task.write_text(
        "\n".join(
            [
                "#!/bin/sh",
                "set -e",
                "/bin/nemu-trap 256",
                "/bin/nemu-trap 257",
                "set +e",
                command,
                "status=$?",
                "set -e",
                "/bin/nemu-trap 258",
                "exit $status",
                "",
            ]
        ),
        encoding="utf-8",
    )
    task.chmod(0o755)


def write_launcher(pkg_dir, harts, workload):
    lines = [
        "#!/bin/sh",
        "",
        "run_taskset() {",
        '  cpu="$1"',
        "  shift",
        "",
        "  if [ -x /usr/bin/taskset ]; then",
        '    /usr/bin/taskset -c "$cpu" "$@"',
        "  elif [ -x /bin/taskset ]; then",
        '    /bin/taskset -c "$cpu" "$@"',
        "  else",
        '    echo "launch_multihart.sh: taskset not found"',
        "    exit 127",
        "  fi",
        "}",
        "",
        "set +e",
    ]
    for hart in range(harts):
        lines.append(f"run_taskset {hart} /{workload}{hart}/task.sh &")
        lines.append(f"pid{hart}=$!")
    lines.append("status=0")
    for hart in range(harts):
        lines.append(f'wait "$pid{hart}"')
        lines.append("rc=$?")
        lines.append('if [ "$status" -eq 0 ] && [ "$rc" -ne 0 ]; then')
        lines.append("  status=$rc")
        lines.append("fi")
    lines.append('/bin/nemu-trap "$status"')
    lines.append("exit $status")
    lines.append("")

    common = pkg_dir / f"{workload}_common"
    common.mkdir(parents=True, exist_ok=True)
    launcher = common / "launch_multihart.sh"
    launcher.write_text("\n".join(lines), encoding="utf-8")
    launcher.chmod(0o755)


def transform(pkg_dir, harts, workload):
    pkg_dir = pkg_dir.resolve()
    workload_dir = pkg_dir / workload
    if not workload_dir.is_dir():
        raise RuntimeError(f"single-hart /{workload} tree is missing under {pkg_dir}")
    if not (workload_dir / "run.sh").is_file():
        raise RuntimeError(f"single-hart run.sh is missing under {workload_dir}")
    common = pkg_dir / f"{workload}_common"
    if common.exists():
        shutil.rmtree(common)
    common.mkdir(parents=True)

    source = pkg_dir / f".{workload}_multihart_source"
    if source.exists():
        shutil.rmtree(source)
    shutil.copytree(workload_dir, source, symlinks=True)
    try:
        for hart in range(harts):
            hart_dir = pkg_dir / f"{workload}{hart}"
            copy_workload_tree(source, hart_dir)
            write_task_script(hart_dir, workload, hart)
        shutil.rmtree(workload_dir)
    finally:
        shutil.rmtree(source)

    write_launcher(pkg_dir, harts, workload)
    etc = pkg_dir / "etc"
    etc.mkdir(parents=True, exist_ok=True)
    (etc / "inittab").write_text(
        f"::once:/bin/sh /{workload}_common/launch_multihart.sh\n", encoding="utf-8"
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pkg-dir", required=True, type=Path)
    parser.add_argument("--harts", required=True, type=positive_harts)
    parser.add_argument("--workload-name", default="spec", type=workload_name)
    args = parser.parse_args()
    transform(args.pkg_dir, args.harts, args.workload_name)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        raise SystemExit(str(exc))
