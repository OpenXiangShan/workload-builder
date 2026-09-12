#!/usr/bin/env python3
"""Generate a workload-builder .dts.in template (not a compiled DTB)."""

import argparse
import importlib.util
from pathlib import Path

GENERATOR = Path(__file__).with_name("generate-nemu-board-dts.py")


def positive_int(value):
    number = int(value, 0)
    if number <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return number


def load_generator():
    spec = importlib.util.spec_from_file_location("workload_builder_dts", GENERATOR)
    if spec is None or spec.loader is None:
        raise SystemExit(f"cannot load DTS generator: {GENERATOR}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def render(args):
    if args.harts > 1 and args.profile != "qemu-nemu":
        raise ValueError("workload-builder multi-hart firmware requires --profile qemu-nemu")
    if args.profile == "fpga-noaia-novec" and args.isa_extensions is not None:
        has_vector = any(ext == "v" or ext.startswith("zv")
                         for ext in args.isa_extensions)
        if has_vector and not args.no_vector:
            raise ValueError("fpga-noaia-novec cannot advertise vector extensions")
    vector_mode = "remove" if (
        args.no_vector or args.profile == "fpga-noaia-novec") else None
    generator = load_generator()
    return generator.render_profile(
        args.profile,
        nr_harts=args.harts,
        memory=args.memory_size,
        isa_config_name=args.isa_config,
        isa_extensions=args.isa_extensions,
        exclude_isa=args.exclude_isa,
        vector_mode=vector_mode,
        timebase_freq=args.timebase_freq,
        mmu_type=args.mmu_type,
        bootargs=args.bootargs,
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=["fpga-noaia-novec", "qemu-nemu", "nemu"],
                        default="fpga-noaia-novec")
    parser.add_argument("--harts", type=positive_int, default=1)
    memory = parser.add_mutually_exclusive_group()
    memory.add_argument("--memory-gib", type=positive_int)
    memory.add_argument("--memory-size", type=positive_int, help="Bytes, decimal or 0x-prefixed")
    parser.add_argument("--timebase-freq", type=positive_int, default=1000000)
    parser.add_argument("--mmu-type", choices=["riscv,sv39", "riscv,sv48", "riscv,sv57"])
    parser.add_argument("--bootargs")
    parser.add_argument("--isa-config", choices=["kunminghu-v3", "kunminghu-v2"],
                        help="Named FPGA ISA declaration (default: kunminghu-v3)")
    parser.add_argument("--isa-extensions", nargs="+", help="Replace the profile's ISA list")
    parser.add_argument("--exclude-isa", nargs="+", default=[], help="Remove exact extension names")
    parser.add_argument("--no-vector", action="store_true", help="Remove v and all zv* declarations")
    parser.add_argument("--output", "-o", type=Path, help=".dts.in path; otherwise write to stdout")
    args = parser.parse_args()
    if args.memory_gib is not None:
        args.memory_size = args.memory_gib << 30
    if args.output and not args.output.name.endswith(".dts.in"):
        parser.error("--output must end in .dts.in (output contains initramfs placeholders)")
    try:
        output = render(args)
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(output)
        else:
            print(output, end="")
    except (ValueError, OSError) as exc:
        parser.error(str(exc))


if __name__ == "__main__":
    main()
