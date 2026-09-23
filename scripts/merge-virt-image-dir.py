#!/usr/bin/env python3
"""Combine a regular image export with per-case virt packages."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path


def is_within(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
    except ValueError:
        return False
    return True


def artifact_name(manifest: dict[str, object]) -> str:
    workload = str(manifest["workload"])
    input_data = manifest.get("input")
    input_name = ""
    if isinstance(input_data, dict) and input_data.get("bin"):
        input_name = Path(str(input_data["bin"])).name
    if input_name not in {"fw_payload.bin", "fw_payload.qemu.bin"}:
        for suffix in (".fw_payload.qemu.bin", ".fw_payload.bin", ".bin"):
            if input_name.endswith(suffix):
                return input_name[: -len(suffix)]
    if Path(workload).name != workload or workload in {"", ".", ".."}:
        raise ValueError(f"invalid workload name in virtual manifest: {workload!r}")
    return workload


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def merge(image_dir: Path, virt_dir: Path, output_dir: Path) -> None:
    image_dir = image_dir.resolve()
    virt_dir = virt_dir.resolve()
    output_dir = output_dir.resolve()
    for source in (image_dir, virt_dir):
        if not source.is_dir():
            raise ValueError(f"source directory does not exist: {source}")
    if output_dir.exists() or output_dir.is_symlink():
        raise ValueError(f"output directory already exists: {output_dir}")
    if is_within(output_dir, image_dir) or is_within(output_dir, virt_dir):
        raise ValueError("output directory must not be inside a source directory")

    virtual_cases = []
    names = set()
    for case_dir in sorted(virt_dir.iterdir(), key=lambda item: item.name):
        if not case_dir.is_dir() or not (case_dir / "manifest.json").is_file():
            continue
        manifest = json.loads((case_dir / "manifest.json").read_text(encoding="utf-8"))
        name = artifact_name(manifest)
        if not (image_dir / "bin" / f"{name}.fw_payload.bin").is_file():
            continue
        if name in names:
            raise ValueError(f"duplicate virtual workload name: {name}")
        names.add(name)
        virtual_cases.append((case_dir, manifest, name))
    if not virtual_cases:
        raise ValueError(f"no virtual workloads in {virt_dir} match {image_dir}")

    first_manifest = virtual_cases[0][1]
    gcpt_hash = first_manifest["host"]["gcpt"]["sha256"]
    opensbi_hash = first_manifest["host"]["opensbi"]["sha256"]
    for _, manifest, name in virtual_cases[1:]:
        if manifest["host"]["gcpt"]["sha256"] != gcpt_hash:
            raise ValueError(f"virtual workload uses a different Host GCPT: {name}")
        if manifest["host"]["opensbi"]["sha256"] != opensbi_hash:
            raise ValueError(f"virtual workload uses a different Host OpenSBI: {name}")

    gcpt_bin = Path(first_manifest["host"]["gcpt"]["path"])
    gcpt_elf = gcpt_bin.with_name("gcpt")
    opensbi_bin = Path(first_manifest["host"]["opensbi"]["path"])
    opensbi_elf = opensbi_bin.with_name("fw_jump.elf")
    opensbi_config_data = first_manifest["host"].get("opensbi_config")
    if isinstance(opensbi_config_data, dict):
        opensbi_config = Path(str(opensbi_config_data["path"]))
    else:
        opensbi_config = opensbi_bin.parents[4] / "platform" / "generic" / "configs" / "defconfig"

    output_dir.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(image_dir, output_dir)
    shared_files = {
        gcpt_bin: output_dir / "gcpt" / "gcpt.bin",
        gcpt_elf: output_dir / "gcpt" / "gcpt.elf",
        opensbi_elf: output_dir / "opensbi" / "fw_jump.elf",
        opensbi_config: output_dir / "opensbi" / "defconfig",
    }
    for source, destination in shared_files.items():
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)

    for case_dir, manifest, name in virtual_cases:
        firmware = manifest["host"]["firmware"]
        dtb = manifest["host"]["dtb"]
        kernel_config = Path(manifest["host"]["kernel_config"]["path"])
        system_map = kernel_config.parent / "System.map"
        paths = {
            "firmware": f"bin/{name}.fw_payload.bin",
            "Image": f"kernel/{name}.Image",
            "vmlinux": f"kernel/{name}.vmlinux",
            "kernel_config": f"kernel/{name}.config",
            "system_map": f"kernel/{name}.System.map",
            "rootfs": f"rootfs/{name}.rootfs.cpio",
            "dtb": f"dt/{name}.dtb",
            "dts": f"dt/{name}.dts",
        }
        for relative in paths.values():
            (output_dir / relative).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(case_dir / firmware["path"], output_dir / paths["firmware"])
        shutil.copy2(case_dir / "host" / "Image", output_dir / paths["Image"])
        shutil.copy2(case_dir / "host" / "vmlinux", output_dir / paths["vmlinux"])
        shutil.copy2(kernel_config, output_dir / paths["kernel_config"])
        shutil.copy2(system_map, output_dir / paths["system_map"])
        shutil.copy2(case_dir / "host" / "rootfs.cpio", output_dir / paths["rootfs"])
        shutil.copy2(case_dir / dtb["path"], output_dir / paths["dtb"])
        dts = case_dir / "host" / "dt" / f"{manifest['host']['dtb_name']}.dts"
        shutil.copy2(dts, output_dir / paths["dts"])
        manifest_path = output_dir / "manifest" / f"{name}.json"
        virtual_manifest_path = output_dir / "manifest" / "virt" / f"{name}.json"
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        virtual_manifest_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(case_dir / "manifest.json", virtual_manifest_path)
        image_manifest = {
            "case": name,
            "virtual_manifest": f"manifest/virt/{name}.json",
            "firmware": {
                "file": paths["firmware"],
                "sha256": firmware["sha256"],
            },
            "kernel": {
                "Image": paths["Image"],
                "vmlinux": paths["vmlinux"],
                "system_map": paths["system_map"],
                "config": paths["kernel_config"],
                "sha256": sha256(output_dir / paths["vmlinux"]),
            },
            "initramfs": {
                "file": paths["rootfs"],
                "sha256": manifest["host"]["rootfs"]["sha256"],
            },
            "device_tree": {
                "dtb": paths["dtb"],
                "dts": paths["dts"],
                "basename": manifest["host"]["dtb_name"],
                "sha256": dtb["sha256"],
            },
            "gcpt": {
                "elf": "gcpt/gcpt.elf",
                "binary": "gcpt/gcpt.bin",
                "elf_sha256": sha256(gcpt_elf),
                "binary_sha256": gcpt_hash,
            },
            "opensbi": {
                "elf": "opensbi/fw_jump.elf",
                "config": "opensbi/defconfig",
                "sha256": sha256(opensbi_elf),
            },
        }
        manifest_path.write_text(
            json.dumps(image_manifest, indent=2) + "\n", encoding="utf-8"
        )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Copy an image export and virt packages into one image directory."
    )
    parser.add_argument("--image-dir", type=Path, required=True)
    parser.add_argument("--virt-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    try:
        merge(args.image_dir, args.virt_dir, args.output_dir)
    except (OSError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    print(f"[virt-images] Output written to {args.output_dir.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
