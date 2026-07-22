#!/usr/bin/env python3
import argparse
import shutil
from pathlib import Path


MAX_HARTS = 128


def positive_harts(value):
    try:
        harts = int(value, 0)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("HARTS must be an integer") from exc
    if not 2 <= harts <= MAX_HARTS:
        raise argparse.ArgumentTypeError(f"HARTS must be in the range 2..{MAX_HARTS}")
    return harts


def copy_spec_tree(src, dst):
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst, symlinks=True)


def write_task_script(spec_dir, hart):
    task = spec_dir / "task.sh"
    task.write_text(
        "\n".join(
            [
                "#!/bin/sh",
                "set -e",
                "/bin/nemu-trap 256",
                "/bin/nemu-trap 257",
                "set +e",
                f'SPEC_ROOT="/spec{hart}" /bin/sh "/spec{hart}/run.sh"',
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


def write_launcher(pkg_dir, harts):
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
        lines.append(f"run_taskset {hart} /spec{hart}/task.sh &")
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

    common = pkg_dir / "spec_common"
    common.mkdir(parents=True, exist_ok=True)
    launcher = common / "launch_multihart.sh"
    launcher.write_text("\n".join(lines), encoding="utf-8")
    launcher.chmod(0o755)


def transform(pkg_dir, harts):
    pkg_dir = pkg_dir.resolve()
    spec = pkg_dir / "spec"
    if not spec.is_dir():
        raise RuntimeError(f"single-hart /spec tree is missing under {pkg_dir}")
    if not (spec / "run.sh").is_file():
        raise RuntimeError(f"single-hart run.sh is missing under {spec}")
    common = pkg_dir / "spec_common"
    if common.exists():
        shutil.rmtree(common)
    common.mkdir(parents=True)

    source = pkg_dir / ".spec_multihart_source"
    if source.exists():
        shutil.rmtree(source)
    shutil.copytree(spec, source, symlinks=True)
    try:
        for hart in range(harts):
            spec_dir = pkg_dir / f"spec{hart}"
            copy_spec_tree(source, spec_dir)
            write_task_script(spec_dir, hart)
        shutil.rmtree(spec)
    finally:
        shutil.rmtree(source)

    write_launcher(pkg_dir, harts)
    etc = pkg_dir / "etc"
    etc.mkdir(parents=True, exist_ok=True)
    (etc / "inittab").write_text("::once:/bin/sh /spec_common/launch_multihart.sh\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pkg-dir", required=True, type=Path)
    parser.add_argument("--harts", required=True, type=positive_harts)
    args = parser.parse_args()
    transform(args.pkg_dir, args.harts)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        raise SystemExit(str(exc))
