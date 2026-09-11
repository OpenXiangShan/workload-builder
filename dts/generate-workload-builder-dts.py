#!/usr/bin/env python3
"""Generate a workload-builder .dts.in template (not a compiled DTB)."""

import argparse
import json
import re
from pathlib import Path

from DTSGen import DTSGen


PROFILES = Path(__file__).with_name("workload-builder-profiles.json")
DRAM_BASE = 0x80000000
CHECKPOINT_START = 0x80300000
CHECKPOINT_SIZE = 0x08300000


def positive_int(value):
    number = int(value, 0)
    if number <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return number


def render(args):
    profile = json.loads(PROFILES.read_text())[args.profile]
    isa_config = profile
    if args.isa_config:
        if args.profile != "fpga-noaia-novec":
            raise ValueError("--isa-config is supported by the FPGA profile only")
        if args.isa_config != "kunminghu-v3":
            isa_config = profile["isa_configs"][args.isa_config]
    if not 1 <= args.harts <= 128:
        raise ValueError("--harts must be in 1..128")
    if args.harts > 1 and args.profile != "qemu-nemu":
        raise ValueError("workload-builder multi-hart firmware requires --profile qemu-nemu")
    size = args.memory_size or profile["memory_size"]
    minimum = 0x08600000 if args.harts > 1 else 0x00400000
    if size <= minimum or size > (1 << 64) - DRAM_BASE:
        raise ValueError("memory must contain the boot layout and fit in the 64-bit address space")

    isa = list(dict.fromkeys(args.isa_extensions or isa_config["isa_extensions"]))
    if any(not re.fullmatch(r"[a-z][a-z0-9]*", ext) for ext in isa):
        raise ValueError("ISA extensions must be lowercase extension names")
    removed = set(args.exclude_isa)
    if args.no_vector:
        removed.add("v")
        removed.update(ext for ext in isa if ext == "v" or ext.startswith("zv"))
    # Match workload-builder's QEMU nemu timer restrictions.
    if args.profile == "qemu-nemu":
        removed.add("sstc")
    isa = [ext for ext in isa if ext not in removed]
    if "i" not in isa:
        raise ValueError("the RV64 generator requires the i base extension")
    if {"smaia", "ssaia"} & set(isa):
        raise ValueError("these profiles describe CLINT + PLIC, not AIA")
    if "v" not in isa and any(ext.startswith("zv") for ext in isa):
        raise ValueError("use --no-vector to remove both v and its vector extensions")
    if args.profile == "fpga-noaia-novec" and (
            "v" in isa or any(ext.startswith("zv") for ext in isa)):
        raise ValueError("fpga-noaia-novec cannot advertise vector extensions")

    # Preserve the source template's legacy ISA string unless overridden.
    if args.isa_extensions is None:
        parts = isa_config["legacy_isa"].split("_")
        base = parts[0][4:]  # Do not remove the v in the rv64 prefix.
        for ext in removed:
            if len(ext) == 1:
                base = base.replace(ext, "")
        legacy_isa = "_".join(["rv64" + base] + [ext for ext in parts[1:] if ext not in removed])
    else:
        legacy_isa = "rv64" + "".join(ext for ext in "imafdcbvh" if ext in isa)
        legacy_isa += "".join("_" + ext for ext in isa if len(ext) > 1)

    nemu = args.profile == "nemu"
    fpga = args.profile == "fpga-noaia-novec"
    chosen = """linux,initrd-start = <INITRAMFS_BEGIN_HI INITRAMFS_BEGIN_LO>;
linux,initrd-end = <INITRAMFS_END_HI INITRAMFS_END_LO>;"""
    if not nemu:
        chosen += """
stdout-path = "serial0:115200n8";
opensbi-config {
    compatible = "opensbi,config";
    cold-boot-harts = <&cpu0>;
};"""
    cache_size, cache_sets, tlb_size = (16384, 64, 32) if nemu else (65536, 256, 48)
    cpu_properties = 'status = "okay";\nclock-frequency = <0>;'
    if fpga:
        cpu_properties += f'\ntimebase-frequency = <{args.timebase_freq}>;'
    cpu_properties += '\ntlb-split;'
    for kind in ("i", "d"):
        cpu_properties += f"""
{kind}-cache-block-size = <64>;
{kind}-cache-sets = <{cache_sets}>;
{kind}-cache-size = <{cache_size}>;
{kind}-tlb-sets = <1>;
{kind}-tlb-size = <{tlb_size}>;"""
    root_nodes = []
    if not nemu:
        cpu_properties += "\nnext-level-cache = <&l2_cache>;"
        root_nodes += ['aliases { serial0 = &uart0; };', """l2_cache: l2-cache {
    compatible = "cache";
    cache-level = <2>;
    cache-block-size = <64>;
    cache-size = <1048576>;
};"""]
    else:
        cpu_properties += "\nriscv,pmpregions = <16>;\nriscv,pmpgranularity = <4096>;"

    gen = DTSGen(
        compatible="freechips,rocketchip-unknown-dev",
        model={"fpga-noaia-novec": "xiangshan,Kunminghu-dev",
               "qemu-nemu": "qemu,nemu", "nemu": "freechips,rocketchip-unknown"}[args.profile],
        cpu_compatibles=["UCAS,COOSCA1.0" if nemu else "ICT,xiangshan", "riscv"],
        isa_extensions=isa,
        legacy_isa=legacy_isa,
        nr_harts=args.harts,
        mmu_type=args.mmu_type or ("riscv,sv39" if nemu else "riscv,sv48"),
        timebase_freq=args.timebase_freq,
        memories=[(DRAM_BASE, size)],
        reserved_memories=[],
        uartlite_addr=0x40600000 if nemu else None,
        plic_ndev=64 if nemu else 66,
        plic_machine_first=not nemu,
        cpu_properties=cpu_properties,
        chosen_properties=chosen,
        root_nodes=root_nodes,
        cache_block_operations=["zicbom", "zicboz"] if fpga else None,
        interrupts_in_soc=fpga,
        soc_compatible=(
            ["freechips,rocketchip-unknown-soc", "simple-bus"]
            if fpga else "simple-bus"),
        plic_node_name="interrupt-controller" if fpga else "plic",
        interrupt_reg_names="control" if fpga else None,
        bootargs=args.bootargs if args.bootargs is not None else (
            "console=hvc0 earlycon=sbi loglevel=8" if args.profile == "fpga-noaia-novec"
            else "console=hvc0 earlycon=sbi"),
    )
    gen.add_reserved_memory(DRAM_BASE, 0x100000, name="gcpt")
    if args.harts > 1:
        gen.add_reserved_memory(CHECKPOINT_START, CHECKPOINT_SIZE, name="checkpoint")
    if not nemu:
        gen.add_device("""uart0: serial@310b0000 {
    compatible = "ns16550a";
    reg = <0x0 0x310b0000 0x0 0x10000>;
    reg-shift = <2>;
    reg-io-width = <4>;
    clock-frequency = <50000000>;
    current-speed = <115200>;
    status = "okay";
};""")
    if args.profile != "qemu-nemu":
        debug_addr = 0 if nemu else 0x38020000
        gen.add_device(f"""debug-controller@{debug_addr:x} {{
    compatible = "sifive,debug-013", "riscv,debug-013";
    reg = <0x0 0x{debug_addr:x} 0x0 0x1000>;
    reg-names = "control";
    interrupts-extended = <&cpu0_intc 65535>;
    {'debug-attach = "jtag";' if not nemu else ''}
}};""")
    # workload-builder aaf4d8b validates this field textually with awk.
    # Keep its exact spelling, even though the unpadded value is equivalent.
    dts = gen.gen_dts().replace(
        "reg = <0x0 0x80300000 0x0 0x8300000>;",
        "reg = <0x0 0x80300000 0x0 0x08300000>;")
    return "/* Generated by nemu_board for workload-builder. */\n" + dts + "\n"


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
