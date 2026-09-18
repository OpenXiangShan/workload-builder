#!/usr/bin/env python3
"""Build and describe Host/Guest initramfs pairs for virtual Linux workloads."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shlex
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path
from typing import Any


MEMORY_RE = re.compile(r"[1-9][0-9]*[KMGTkmgt]")
HARTS_RE = re.compile(r"[1-9][0-9]*")
NEMU_EXEC_RE = re.compile(r"^(?:/bin/)?nemu-exec(?:[ \t]+(.+))?$")
WORKLOAD_INIT_ACTIONS = {"sysinit", "wait", "once"}
HOST_FIRMWARE_NAMES = {"nemu": "fw_payload.bin", "qemu": "fw_payload.qemu.bin"}
HOST_ENTROPY_SEED = hashlib.sha256(
    b"workload-builder virt host deterministic seed v1"
).digest()


def run(command: list[str], **kwargs: Any) -> subprocess.CompletedProcess[Any]:
    return subprocess.run(command, check=True, **kwargs)


def extract_cpio(archive: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    with archive.open("rb") as source:
        run(
            ["cpio", "-idmu", "--no-absolute-filenames"],
            cwd=destination,
            stdin=source,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )


def pack_cpio(source: Path, archive: Path) -> None:
    archive.parent.mkdir(parents=True, exist_ok=True)
    temporary = archive.with_name(f".{archive.name}.tmp")
    with temporary.open("wb") as output:
        run(
            [
                "sh",
                "-c",
                "find . -print0 | cpio --null -o -H newc --owner=0:0",
            ],
            cwd=source,
            stdout=output,
            stderr=subprocess.PIPE,
        )
    os.replace(temporary, archive)


def validate_resources(guest_harts: str | int, guest_memory: str) -> tuple[int, str]:
    harts = str(guest_harts)
    if not HARTS_RE.fullmatch(harts):
        raise ValueError("VIRT_GUEST_HARTS must be a positive integer")
    if not MEMORY_RE.fullmatch(guest_memory):
        raise ValueError(
            "VIRT_GUEST_MEMORY must be a positive size such as 512M, 8G, or 1T"
        )
    return int(harts), guest_memory.upper()


def validate_qemu_start_timeout(timeout: str | int) -> int:
    value = str(timeout)
    if not re.fullmatch(r"[1-9][0-9]*", value):
        raise ValueError(
            "VIRT_QEMU_START_TIMEOUT must be a positive integer number of seconds"
        )
    return int(value)


def install_guest_runtime(root: Path, buildroot_output: Path) -> None:
    for name in ("nemu-trap", "nemu-exec"):
        destination = root / "bin" / name
        copy_file(buildroot_output / "target" / "bin" / name, destination)
        destination.chmod(destination.stat().st_mode | 0o111)


def install_guest_console(root: Path) -> None:
    """Provide the early kernel console before devtmpfs is mounted."""
    console = root / "dev" / "console"
    console.parent.mkdir(parents=True, exist_ok=True)
    if os.path.lexists(console):
        metadata = console.lstat()
        if stat.S_ISCHR(metadata.st_mode) and metadata.st_rdev == os.makedev(5, 1):
            return
        if console.is_dir():
            raise ValueError(f"Guest console path is a directory: {console}")
        console.unlink()
    os.mknod(console, stat.S_IFCHR | 0o600, os.makedev(5, 1))


def workload_commands(inittab: Path) -> list[str]:
    commands: list[str] = []
    for line_number, line in enumerate(
        inittab.read_text(encoding="utf-8").splitlines(), start=1
    ):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        fields = line.split(":", 3)
        if len(fields) != 4:
            raise ValueError(f"invalid Guest inittab line {line_number}: {line}")
        action = fields[2]
        if action not in WORKLOAD_INIT_ACTIONS:
            raise ValueError(
                f"unsupported Guest inittab action {action!r} on line {line_number}"
            )
        command = fields[3].strip()
        match = NEMU_EXEC_RE.fullmatch(command)
        if match:
            command = (match.group(1) or "").strip()
        if not command:
            raise ValueError(f"empty Guest command on inittab line {line_number}")
        commands.append(command)
    if not commands:
        raise ValueError(f"Guest inittab has no workload actions: {inittab}")
    return commands


def guest_command_script(commands: list[str]) -> str:
    lines = ["#!/bin/sh", *commands]
    lines.extend(["status=$?", 'exit "$status"', ""])
    return "\n".join(lines)


def guest_trap_shim() -> str:
    return "\n".join(
        [
            "#!/bin/sh",
            "status=${1:-0}",
            "run_dir=${VIRT_RUN_DIR:-/run}",
            "case \"$status\" in",
            "    256|257|258) exit 0 ;;",
            "    -*|'') status=1 ;;",
            "    *[!0-9]*) status=1 ;;",
            "esac",
            'if [ "$status" -gt 255 ] 2>/dev/null; then status=1; fi',
            'mkdir -p "$run_dir"',
            'if [ ! -e "$run_dir/virt-nemu-trap.status" ]; then',
            '    printf \'%s\\n\' "$status" > "$run_dir/virt-nemu-trap.status"',
            "fi",
            "exit 0",
            "",
        ]
    )


def guest_runner_script() -> str:
    return "\n".join(
        [
            "#!/bin/sh",
            "set -u",
            "run_dir=${VIRT_RUN_DIR:-/run}",
            "command_file=${VIRT_COMMAND_FILE:-/etc/virt-workload-command}",
            "notify=${VIRT_NEMU_NOTIFY:-/bin/nemu-notify}",
            'mkdir -p "$run_dir"',
            'rm -f "$run_dir/virt-nemu-trap.status"',
            '"$notify" 256',
            '"$notify" 257',
            "set +e",
            '/bin/sh "$command_file"',
            "status=$?",
            "set -e",
            'if [ -s "$run_dir/virt-nemu-trap.status" ]; then',
            '    status=$(cat "$run_dir/virt-nemu-trap.status")',
            "fi",
            "case \"$status\" in ''|*[!0-9]*) status=1 ;; esac",
            'if [ "$status" -gt 255 ]; then status=1; fi',
            'if [ "$status" -eq 0 ]; then printf \'TEST DONE!\\n\'; fi',
            'printf \'VIRT_WORKLOAD_EXIT=%s\\n\' "$status"',
            'if [ "${VIRT_TEST_NO_POWEROFF:-0}" -eq 1 ]; then exit "$status"; fi',
            "while :; do sleep 1; done",
            "",
        ]
    )


def install_guest_exit_adapter(root: Path) -> None:
    inittab = root / "etc" / "inittab"
    direct_init = root / "init"
    if direct_init.is_file() and not direct_init.is_symlink():
        workload_init = root / "sbin" / "virt-workload-init"
        os.replace(direct_init, workload_init)
        commands = ["/sbin/virt-workload-init"]
    else:
        if not inittab.is_file():
            raise FileNotFoundError(inittab)
        commands = workload_commands(inittab)

    command_file = root / "etc" / "virt-workload-command"
    command_file.write_text(guest_command_script(commands), encoding="utf-8")
    command_file.chmod(0o755)

    trap = root / "bin" / "nemu-trap"
    notify = root / "bin" / "nemu-notify"
    copy_file(trap, notify)
    notify.chmod(notify.stat().st_mode | 0o111)
    trap.write_text(guest_trap_shim(), encoding="utf-8")
    trap.chmod(0o755)

    runner = root / "sbin" / "virt-guest-run"
    runner.write_text(guest_runner_script(), encoding="utf-8")
    runner.chmod(0o755)
    inittab.write_text("console::sysinit:/sbin/virt-guest-run\n", encoding="utf-8")
    if not direct_init.exists() and not direct_init.is_symlink():
        direct_init.symlink_to("sbin/init")


def assemble_guest_rootfs(
    destination: Path, workload_rootfs: Path, buildroot_output: Path
) -> None:
    target = buildroot_output / "target"
    if not target.is_dir():
        raise FileNotFoundError(target)
    shutil.copytree(target, destination, symlinks=True)
    extract_cpio(workload_rootfs, destination)
    install_guest_runtime(destination, buildroot_output)
    install_guest_console(destination)
    install_guest_exit_adapter(destination)


def qemu_argv(guest_harts: int, guest_memory: str) -> list[str]:
    return [
        "/usr/bin/qemu-system-riscv64",
        "-machine",
        "virt,aia=none",
        "-bios",
        "none",
        "-accel",
        "kvm",
        "-cpu",
        "host",
        "-smp",
        str(guest_harts),
        "-m",
        guest_memory,
        "-display",
        "none",
        "-monitor",
        "none",
        "-serial",
        "stdio",
        "-no-reboot",
        "-kernel",
        "/guest/Image",
        "-initrd",
        "/guest/rootfs.cpio",
        "-append",
        "console=ttyS0 earlycon=sbi panic=1",
    ]


def host_init_script(
    guest_harts: int,
    guest_memory: str,
    start_timeout: int = 120,
) -> str:
    qemu_arguments = " ".join(
        shlex.quote(arg) for arg in qemu_argv(guest_harts, guest_memory)[1:]
    )
    return "\n".join(
        [
            "#!/bin/sh",
            "set -u",
            "run_dir=${VIRT_RUN_DIR:-/run}",
            "kmsg_dev=${VIRT_KMSG:-/dev/kmsg}",
            "qemu_bin=${VIRT_QEMU_BIN:-/usr/bin/qemu-system-riscv64}",
            "nemu_trap=${VIRT_NEMU_TRAP:-/bin/nemu-trap}",
            "mkdir -p \"$run_dir\"",
            "kmsg() { printf '%s\\n' \"$1\" >> \"$kmsg_dev\"; }",
            "kmsg 'VIRT_HOST: launching KVM guest'",
            "rm -f \"$run_dir/virt-qemu.pipe\" \"$run_dir/virt-qemu.log\" \"$run_dir/virt-qemu.start-timeout\" \"$run_dir/virt-qemu.started\" \"$run_dir/virt-qemu.pid\" \"$run_dir/virt-qemu.completed\"",
            ": > \"$run_dir/virt-qemu.log\"",
            "mkfifo \"$run_dir/virt-qemu.pipe\"",
            f"start_timeout=${{VIRT_QEMU_START_TIMEOUT:-{start_timeout}}}",
            "cr=$(printf '\\r')",
            f'"$qemu_bin" {qemu_arguments} </dev/null > "$run_dir/virt-qemu.pipe" 2>&1 &',
            "qemu_pid=$!",
            "(",
            "    marker_count=0",
            "    workload_status=",
            "    while IFS= read -r line || [ -n \"$line\" ]; do",
            "        line=${line%\"$cr\"}",
            "        printf '%s\\n' \"$line\" >> \"$run_dir/virt-qemu.log\"",
            "        printf '%s\\n' \"$line\" >> \"$kmsg_dev\"",
            "        printf '%s\\n' 1 > \"$run_dir/virt-qemu.started\"",
            "        case \"$line\" in",
            "            VIRT_WORKLOAD_EXIT=[0-9]|VIRT_WORKLOAD_EXIT=[0-9][0-9]|VIRT_WORKLOAD_EXIT=[0-9][0-9][0-9])",
            "                marker_count=$((marker_count + 1))",
            "                workload_status=${line#VIRT_WORKLOAD_EXIT=}",
            "                if [ \"$marker_count\" -eq 1 ]; then",
            "                    printf '%s\\n' 1 > \"$run_dir/virt-qemu.completed\"",
            "                    kill -9 \"$qemu_pid\" 2>/dev/null || true",
            "                fi",
            "                ;;",
            "        esac",
            "    done < \"$run_dir/virt-qemu.pipe\"",
            "    result=1",
            "    if [ -s \"$run_dir/virt-qemu.start-timeout\" ]; then",
            "        kmsg \"VIRT_HOST: QEMU/KVM produced no output within ${start_timeout}s\"",
            "    elif [ \"$marker_count\" -ne 1 ]; then",
            "        kmsg \"VIRT_HOST: expected one Guest exit marker, found $marker_count\"",
            "    elif [ -z \"$workload_status\" ] || [ \"$workload_status\" -gt 255 ] 2>/dev/null; then",
            "        kmsg 'VIRT_HOST: invalid Guest exit marker'",
            "    else",
            "        result=$workload_status",
            "    fi",
            "    kmsg \"VIRT_HOST: workload exit $result\"",
            "    exec \"$nemu_trap\" \"$result\"",
            ") &",
            "reader_pid=$!",
            "printf '%s\\n' \"$qemu_pid\" > \"$run_dir/virt-qemu.pid\"",
            "(",
            "    remaining=$start_timeout",
            "    while [ \"$remaining\" -gt 0 ] && [ ! -s \"$run_dir/virt-qemu.started\" ]; do",
            "        sleep 1",
            "        if [ -s \"$run_dir/virt-qemu.completed\" ] || ! kill -0 \"$qemu_pid\" 2>/dev/null; then exit 0; fi",
            "        remaining=$((remaining - 1))",
            "    done",
            "    if [ ! -s \"$run_dir/virt-qemu.started\" ] && kill -0 \"$qemu_pid\" 2>/dev/null; then",
            "        printf '%s\\n' 1 > \"$run_dir/virt-qemu.start-timeout\"",
            "        qemu_state=$(awk '/^State:/ { print $2 }' \"/proc/$qemu_pid/status\" 2>/dev/null || true)",
            "        qemu_wchan=$(cat \"/proc/$qemu_pid/wchan\" 2>/dev/null || true)",
            "        qemu_syscall=$(cat \"/proc/$qemu_pid/syscall\" 2>/dev/null || true)",
            "        kmsg \"VIRT_HOST: QEMU state=${qemu_state:-unknown} wchan=${qemu_wchan:-unknown} syscall=${qemu_syscall:-unknown}\"",
            "        kill \"$qemu_pid\" 2>/dev/null || true",
            "        sleep 1",
            "        kill -9 \"$qemu_pid\" 2>/dev/null || true",
            "    fi",
            ") &",
            "watchdog_pid=$!",
            "wait \"$qemu_pid\" 2>/dev/null || true",
            "kill \"$watchdog_pid\" 2>/dev/null || true",
            "wait \"$watchdog_pid\" 2>/dev/null || true",
            "wait \"$reader_pid\" 2>/dev/null",
            "result=$?",
            "rm -f \"$run_dir/virt-qemu.pipe\" \"$run_dir/virt-qemu.pid\"",
            "if [ \"${VIRT_TEST_NO_POWEROFF:-0}\" -eq 1 ]; then exit \"$result\"; fi",
            "while :; do :; done",
            "",
        ]
    )


def find_vmlinux(output_dir: Path) -> Path:
    matches = sorted((output_dir / "build").glob("linux-*/vmlinux"))
    if len(matches) != 1:
        raise ValueError(f"expected one vmlinux under {output_dir}, found {matches}")
    return matches[0]


def require_file(path: Path) -> None:
    if not path.is_file() or path.stat().st_size == 0:
        raise FileNotFoundError(path)


def copy_file(source: Path, destination: Path) -> None:
    require_file(source)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(f".{destination.name}.tmp")
    shutil.copy2(source, temporary)
    os.replace(temporary, destination)


def package(args: argparse.Namespace) -> None:
    guest_harts, guest_memory = validate_resources(args.guest_harts, args.guest_memory)
    start_timeout = validate_qemu_start_timeout(args.qemu_start_timeout)
    for path in (
        args.guest_rootfs,
        args.host_rootfs,
        args.guest_image,
        args.host_image,
    ):
        require_file(path)

    output = args.out_dir
    guest_dir = output / "guest"
    host_dir = output / "host"
    guest_dir.mkdir(parents=True, exist_ok=True)
    host_dir.mkdir(parents=True, exist_ok=True)

    copy_file(args.guest_image, guest_dir / "Image")
    copy_file(find_vmlinux(args.guest_buildroot_output), guest_dir / "vmlinux")
    copy_file(args.host_image, host_dir / "Image")
    copy_file(find_vmlinux(args.host_buildroot_output), host_dir / "vmlinux")

    with tempfile.TemporaryDirectory(prefix="virt-guest-") as temp:
        guest_root = Path(temp) / "rootfs"
        assemble_guest_rootfs(
            guest_root, args.guest_rootfs, args.guest_buildroot_output
        )
        pack_cpio(guest_root, guest_dir / "rootfs.cpio")

    with tempfile.TemporaryDirectory(prefix="virt-host-") as temp:
        host_root = Path(temp) / "rootfs"
        extract_cpio(args.host_rootfs, host_root)
        qemu = host_root / "usr" / "bin" / "qemu-system-riscv64"
        require_file(qemu)
        seed = host_root / "var" / "lib" / "seedrng" / "seed.credit"
        seed.parent.mkdir(parents=True, exist_ok=True)
        seed.write_bytes(HOST_ENTROPY_SEED)
        seed.chmod(0o400)
        guest = host_root / "guest"
        guest.mkdir(parents=True, exist_ok=True)
        copy_file(guest_dir / "Image", guest / "Image")
        copy_file(guest_dir / "rootfs.cpio", guest / "rootfs.cpio")
        init_script = host_root / "etc" / "init.d" / "S99virt-workload"
        init_script.parent.mkdir(parents=True, exist_ok=True)
        init_script.write_text(
            host_init_script(guest_harts, guest_memory, start_timeout), encoding="utf-8"
        )
        init_script.chmod(0o755)
        pack_cpio(host_root, host_dir / "rootfs.cpio")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def component(path: Path, relative: str) -> dict[str, str | int]:
    require_file(path)
    return {"path": relative, "bytes": path.stat().st_size, "sha256": sha256(path)}


def parse_needed(elf: Path) -> list[str]:
    output = subprocess.check_output(["readelf", "-d", str(elf)], text=True)
    return re.findall(r"Shared library: \[([^]]+)]", output)


def validate_qemu_root(root: Path) -> dict[str, Any]:
    qemu = root / "usr" / "bin" / "qemu-system-riscv64"
    require_file(qemu)
    header = subprocess.check_output(["readelf", "-h", str(qemu)], text=True)
    if "Machine:" not in header or "RISC-V" not in header:
        raise ValueError(f"Host QEMU is not a RISC-V ELF: {qemu}")
    program_headers = subprocess.check_output(["readelf", "-l", str(qemu)], text=True)
    if "Requesting program interpreter" not in program_headers:
        raise ValueError(f"Host QEMU is not dynamically linked: {qemu}")

    roots = [qemu]
    seen: set[str] = set()
    resolved: dict[str, Path] = {}
    while roots:
        current = roots.pop()
        for name in parse_needed(current):
            if name in seen:
                continue
            seen.add(name)
            candidates = [
                path
                for prefix in (root / "lib", root / "usr" / "lib")
                for path in prefix.glob(f"**/{name}")
            ]
            if not candidates:
                raise ValueError(f"missing dynamic dependency {name} for {current}")
            dependency = candidates[0]
            resolved[name] = dependency
            roots.append(dependency)
    return {
        "sha256": sha256(qemu),
        "needed": sorted(resolved),
        "library_hashes": {name: sha256(path) for name, path in sorted(resolved.items())},
    }


def directory_version(output_dir: Path, prefix: str) -> str:
    matches = sorted(path.name.removeprefix(prefix) for path in (output_dir / "build").glob(f"{prefix}*"))
    if len(matches) != 1:
        raise ValueError(f"expected one {prefix} version under {output_dir}, found {matches}")
    return matches[0]


def config_record(path: Path) -> dict[str, str]:
    require_file(path)
    return {"path": str(path), "sha256": sha256(path)}


def source_record(path: Path, revision: str) -> dict[str, str | int]:
    if path.is_dir():
        record: dict[str, str | int] = {"path": str(path)}
    else:
        record = component(path, str(path))
    record["revision"] = revision
    return record


def buildroot_config(output_dir: Path) -> Path:
    """Resolve both Buildroot O= and the repository's in-tree output layout."""
    candidates = (output_dir / ".config", output_dir.parent / ".config")
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    raise ValueError(f"Buildroot configuration not found near {output_dir}")


def source_record_from_buildroot(output_dir: Path, revision: str) -> dict[str, str | int]:
    matches = sorted((output_dir / "build").glob("linux-*/Makefile"))
    if len(matches) != 1:
        raise ValueError(f"expected one Linux source under {output_dir}, found {matches}")
    return {"path": str(matches[0].parent), "revision": revision}


def buildroot_version(source: Path) -> str:
    makefile = (source / "Makefile").read_text(encoding="utf-8")
    match = re.search(r"^(?:export\s+)?BR2_VERSION\s*:?=\s*(.+)$", makefile, re.MULTILINE)
    return match.group(1).strip() if match else "unknown"


def write_manifest(args: argparse.Namespace) -> None:
    guest_harts, guest_memory = validate_resources(args.guest_harts, args.guest_memory)
    start_timeout = validate_qemu_start_timeout(args.qemu_start_timeout)
    output = args.out_dir
    guest = output / "guest"
    host = output / "host"
    dtb = host / "dt" / f"{args.host_dtb}.dtb"
    firmware_name = HOST_FIRMWARE_NAMES[args.platform]
    host_kernel_config = find_vmlinux(args.host_buildroot_output).parent / ".config"
    guest_kernel_config = find_vmlinux(args.guest_buildroot_output).parent / ".config"
    guest_buildroot_config = buildroot_config(args.guest_buildroot_output)
    host_buildroot_config = buildroot_config(args.host_buildroot_output)

    with tempfile.TemporaryDirectory(prefix="virt-manifest-") as temp:
        host_root = Path(temp) / "rootfs"
        extract_cpio(host / "rootfs.cpio", host_root)
        qemu = validate_qemu_root(host_root)

    qemu_version = directory_version(args.host_buildroot_output, "qemu-")
    if qemu_version != args.inner_qemu_version:
        raise ValueError(
            f"inner QEMU version mismatch: expected {args.inner_qemu_version}, found {qemu_version}"
        )

    argv = qemu_argv(guest_harts, guest_memory)
    data = {
        "schema_version": 2,
        "workload": args.workload_name,
        "platform": args.platform,
        "guest": {
            "harts": guest_harts,
            "memory": guest_memory,
            "Image": component(guest / "Image", "guest/Image"),
            "vmlinux": component(guest / "vmlinux", "guest/vmlinux"),
            "rootfs": component(guest / "rootfs.cpio", "guest/rootfs.cpio"),
            "buildroot_config": config_record(guest_buildroot_config),
            "kernel_config": config_record(guest_kernel_config),
        },
        "host": {
            "dtb_name": args.host_dtb,
            "minimum_memory_bytes": int(args.host_min_memory_bytes),
            "Image": component(host / "Image", "host/Image"),
            "vmlinux": component(host / "vmlinux", "host/vmlinux"),
            "rootfs": component(host / "rootfs.cpio", "host/rootfs.cpio"),
            "firmware": component(
                host / firmware_name, f"host/{firmware_name}"
            ),
            "dtb": component(dtb, f"host/dt/{args.host_dtb}.dtb"),
            "gcpt": component(args.gcpt, str(args.gcpt)),
            "opensbi": component(args.opensbi, str(args.opensbi)),
            "defconfig": config_record(args.host_defconfig),
            "linux_config": config_record(args.host_linux_config),
            "buildroot_config": config_record(host_buildroot_config),
            "kernel_config": config_record(host_kernel_config),
            "linux_source": source_record_from_buildroot(
                args.host_buildroot_output, args.host_linux_revision
            ),
            "opensbi_source": source_record(
                args.opensbi_source, args.opensbi_revision
            ),
        },
        "qemu": {
            "binary": "/usr/bin/qemu-system-riscv64",
            "version": qemu_version,
            "dtb_mode": "qemu-generated",
            "argv": argv,
            "startup_timeout_seconds": start_timeout,
            **qemu,
        },
        "buildroot": {
            "version": buildroot_version(args.buildroot_source),
            "source": str(args.buildroot_source),
        },
    }
    if args.platform == "qemu":
        outer_qemu_harts, outer_qemu_memory = validate_resources(
            args.outer_qemu_harts, args.outer_qemu_memory
        )
        data["outer_qemu"] = {
            "machine": args.outer_qemu_machine,
            "cpu": args.outer_qemu_cpu,
            "harts": outer_qemu_harts,
            "memory": outer_qemu_memory,
            "firmware": component(
                host / firmware_name, f"host/{firmware_name}"
            ),
            "dtb_name": args.host_dtb,
            "dtb": component(dtb, f"host/dt/{args.host_dtb}.dtb"),
            "argv": [
                "qemu-system-riscv64",
                "-machine",
                args.outer_qemu_machine,
                "-accel",
                "tcg",
                "-cpu",
                args.outer_qemu_cpu,
                "-smp",
                str(outer_qemu_harts),
                "-m",
                outer_qemu_memory,
                "-nographic",
                "-no-reboot",
                "-bios",
                f"host/{firmware_name}",
            ],
        }
    manifest = output / "manifest.json"
    temporary = manifest.with_name(".manifest.json.tmp")
    temporary.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, manifest)


def add_resource_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--guest-harts", default="1")
    parser.add_argument("--guest-memory", default="8G")
    parser.add_argument("--qemu-start-timeout", default="120")


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="action", required=True)

    package_parser = subparsers.add_parser("package")
    package_parser.add_argument("--guest-rootfs", type=Path, required=True)
    package_parser.add_argument("--host-rootfs", type=Path, required=True)
    package_parser.add_argument("--guest-image", type=Path, required=True)
    package_parser.add_argument("--host-image", type=Path, required=True)
    package_parser.add_argument("--guest-buildroot-output", type=Path, required=True)
    package_parser.add_argument("--host-buildroot-output", type=Path, required=True)
    package_parser.add_argument("--out-dir", type=Path, required=True)
    add_resource_args(package_parser)

    manifest_parser = subparsers.add_parser("manifest")
    manifest_parser.add_argument("--out-dir", type=Path, required=True)
    manifest_parser.add_argument("--workload-name", required=True)
    manifest_parser.add_argument("--platform", choices=("nemu", "qemu"), required=True)
    manifest_parser.add_argument("--host-dtb", required=True)
    manifest_parser.add_argument("--host-min-memory-bytes", required=True)
    manifest_parser.add_argument("--outer-qemu-machine")
    manifest_parser.add_argument("--outer-qemu-cpu")
    manifest_parser.add_argument("--outer-qemu-harts")
    manifest_parser.add_argument("--outer-qemu-memory")
    manifest_parser.add_argument("--gcpt", type=Path, required=True)
    manifest_parser.add_argument("--opensbi", type=Path, required=True)
    manifest_parser.add_argument("--host-linux-revision", required=True)
    manifest_parser.add_argument("--opensbi-source", type=Path, required=True)
    manifest_parser.add_argument("--opensbi-revision", required=True)
    manifest_parser.add_argument("--host-defconfig", type=Path, required=True)
    manifest_parser.add_argument("--host-linux-config", type=Path, required=True)
    manifest_parser.add_argument("--guest-buildroot-output", type=Path, required=True)
    manifest_parser.add_argument("--host-buildroot-output", type=Path, required=True)
    manifest_parser.add_argument("--buildroot-source", type=Path, required=True)
    manifest_parser.add_argument("--inner-qemu-version", required=True)
    add_resource_args(manifest_parser)

    args = parser.parse_args()
    try:
        if args.action == "package":
            package(args)
        else:
            write_manifest(args)
    except (FileNotFoundError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"error: {exc}", file=os.sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
