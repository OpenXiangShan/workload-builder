#!/usr/bin/env python3
"""Generate workload-builder DTS templates through nemu_board's DTSGen."""

import argparse
import importlib.util
import json
import os
import re
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NEMU_BOARD_DTSGEN = ROOT / "nemu_board" / "dts" / "DTSGen.py"
PROFILE_FILE = ROOT / "nemu_board" / "dts" / "workload-builder-profiles.json"
DRAM_BASE = 0x80000000
VECTOR_EXTENSIONS = {"v", "zvbb", "zvfh", "zvfhmin", "zvkt",
                     "zvl128b", "zvl32b", "zvl64b"}
INITRD = """linux,initrd-start = <INITRAMFS_BEGIN_HI INITRAMFS_BEGIN_LO>;
linux,initrd-end = <INITRAMFS_END_HI INITRAMFS_END_LO>;"""


class UnsupportedDTSName(ValueError):
    pass


def load_dtsgen():
    spec = importlib.util.spec_from_file_location("nemu_board_dtsgen", NEMU_BOARD_DTSGEN)
    if spec is None or spec.loader is None:
        raise SystemExit(f"cannot load nemu_board DTSGen.py: {NEMU_BOARD_DTSGEN}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.DTSGen


def parse_name(name):
    """Recognize complete built-in names; leave other names to custom templates."""
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", name):
        raise ValueError("--name must be a basename without directory components")
    fixed = {
        "xiangshan": (1, 128 << 20),
        "nutshell": (1, 128 << 20),
        "spike": (1, 2 << 30),
        "spike-2core": (2, 2 << 30),
        "yanqihu": (1, 128 << 20),
        "yanqihu-2core": (2, 128 << 20),
        "xiangshan-fpga-AIA-mem16g": (1, 16 << 30),
    }
    if name in fixed:
        return fixed[name]
    match = re.fullmatch(
        r"(?:xiangshan-fpga-noAIA|xiangshan-qemu-nemu)"
        r"(?:-(?P<harts>[0-9]+)hart)?(?:-mem(?P<memory>[0-9]+)g)?(?:-novec)?",
        name,
    )
    if match is None:
        raise UnsupportedDTSName(f"unsupported DTS basename: {name}")
    nr_harts = int(match["harts"] or 1)
    if not 1 <= nr_harts <= 128:
        raise ValueError("DTS hart count must be in 1..128")
    if nr_harts > 1 and match["memory"] is None:
        raise ValueError("multi-hart DTS names must include an explicit -mem<N>g profile")
    memory = int(match["memory"] or 2) << 30
    if memory <= 0 or memory > (1 << 64) - DRAM_BASE:
        raise ValueError("DTS memory must be positive and fit in the 64-bit address space")
    return nr_harts, memory


def chosen_properties(profile, initrd=True):
    lines = []
    if initrd:
        lines.append(INITRD)
    if profile in {"fpga", "qemu"}:
        lines.append('stdout-path = "serial0:115200n8";')
        lines.append('opensbi-config {\n    compatible = "opensbi,config";\n    cold-boot-harts = <&cpu0>;\n};')
    elif profile == "spike":
        lines.append("stdout-path = &serial0;")
    return "\n".join(lines)


def cache_properties(nemu=False, timebase=False):
    size, sets, tlb = (16384, 64, 32) if nemu else (65536, 256, 48)
    result = ['status = "okay";', "clock-frequency = <0>;"]
    if timebase:
        result.append("timebase-frequency = <1000000>;")
    result += ["tlb-split;"]
    for kind in ("i", "d"):
        result += [f"{kind}-cache-block-size = <64>;",
                   f"{kind}-cache-sets = <{sets}>;",
                   f"{kind}-cache-size = <{size}>;",
                   f"{kind}-tlb-sets = <1>;",
                   f"{kind}-tlb-size = <{tlb}>;"]
    return "\n".join(result)


def serial16550():
    return """uart0: serial@310b0000 {
    compatible = "ns16550a";
    reg = <0x0 0x310b0000 0x0 0x10000>;
    reg-shift = <2>;
    reg-io-width = <4>;
    clock-frequency = <50000000>;
    current-speed = <115200>;
    status = "okay";
};"""


def serial_spike():
    return """serial0: ns16550@10000000 {
    compatible = "ns16550a";
    clock-frequency = <10000000>;
    interrupt-parent = <&plic>;
    interrupts = <1>;
    reg = <0x0 0x10000000 0x0 0x100>;
    reg-shift = <0>;
    reg-io-width = <1>;
};"""


def serial_uartlite():
    return """serial0: serial@40600000 {
    compatible = "xlnx,xps-uartlite-1.00.a";
    reg = <0x0 0x40600000 0x0 0x1000>;
    current-speed = <115200>;
};"""


def debug_controller(nr_harts):
    interrupts = ", ".join(
        f"<&cpu{hart_id}_intc 65535>" for hart_id in range(nr_harts)
    )
    return f"""debug-controller@38020000 {{
    compatible = "sifive,debug-013", "riscv,debug-013";
    debug-attach = "jtag";
    reg = <0x0 0x38020000 0x0 0x1000>;
    reg-names = "control";
    interrupts-extended = {interrupts};
}};"""


def aia_devices():
    return ["""imsics_m: imsics@3a800000 {
    #address-cells = <0>;
    riscv,num-ids = <255>;
    reg = <0x0 0x3a800000 0x0 0x10000>;
    msi-controller;
    interrupt-controller;
    #interrupt-cells = <0>;
    compatible = "riscv,imsics";
    interrupts-extended = <&cpu0_intc 11>;
};""", """imsics_s: imsics@3b000000 {
    #address-cells = <0>;
    riscv,num-ids = <255>;
    reg = <0x0 0x3b000000 0x0 0x80000>;
    msi-controller;
    interrupt-controller;
    #interrupt-cells = <0>;
    compatible = "riscv,imsics";
    riscv,guest-index-bits = <3>;
    interrupts-extended = <&cpu0_intc 9>;
};""", """aplic_s: aplic@31120000 {
    #address-cells = <0>;
    riscv,num-sources = <64>;
    reg = <0x0 0x31120000 0x0 0x8000>;
    msi-parent = <&imsics_s>;
    interrupt-controller;
    #interrupt-cells = <2>;
    compatible = "riscv,aplic";
};""", """aplic_m: aplic@31100000 {
    #address-cells = <0>;
    riscv,delegate = <&aplic_s 1 64>;
    riscv,children = <&aplic_s>;
    riscv,num-sources = <64>;
    reg = <0x0 0x31100000 0x0 0x8000>;
    msi-parent = <&imsics_m>;
    interrupt-controller;
    #interrupt-cells = <2>;
    compatible = "riscv,aplic";
};"""]


def render(name, isa_config_name="kunminghu-v3"):
    nr_harts, memory = parse_name(name)
    DTSGen = load_dtsgen()
    profiles = json.loads(PROFILE_FILE.read_text())
    is_novec = name.endswith("-novec")
    root_nodes = []

    if isa_config_name != "kunminghu-v3" and not name.startswith("xiangshan-fpga-noAIA"):
        raise ValueError("--isa-config is supported by the FPGA noAIA profile only")

    if name.startswith("xiangshan-fpga-noAIA"):
        profile = profiles["fpga-noaia-novec"]
        isa_config = (profile if isa_config_name == "kunminghu-v3"
                      else profile["isa_configs"][isa_config_name])
        isa = set(isa_config["isa_extensions"])
        if not is_novec:
            isa.update(VECTOR_EXTENSIONS)
        else:
            isa.difference_update(VECTOR_EXTENSIONS)
        if nr_harts > 1:
            isa.discard("sstc")
        cpu_props = cache_properties()
        cpu_props += "\ntimebase-frequency = <1000000>;"
        root_nodes.append("""aliases { serial0 = &uart0; };""")
        root_nodes.append("""l2_cache: l2-cache {
    compatible = "cache";
    cache-level = <2>;
    cache-block-size = <64>;
    cache-size = <1048576>;
};""")
        cpu_props += "\nnext-level-cache = <&l2_cache>;"
        legacy_isa = isa_config["legacy_isa"]
        if is_novec:
            legacy_isa = legacy_isa.replace("rv64imafdcvh", "rv64imafdch")
        else:
            legacy_isa = legacy_isa.replace("rv64imafdch", "rv64imafdcvh")
        if nr_harts > 1:
            legacy_isa = legacy_isa.replace("_sstc", "")
        gen = DTSGen(compatible="freechips,rocketchip-unknown-dev",
                     model="xiangshan,Kunminghu-dev",
                     cpu_compatibles=["ICT,xiangshan", "riscv"],
                     isa_extensions=DTSGen.sort_isa_extensions(sorted(isa)),
                     legacy_isa=legacy_isa,
                     mmu_type="riscv,sv48", timebase_freq=1000000,
                     nr_harts=nr_harts, memories=[(DRAM_BASE, memory)],
                     reserved_memories=[], cpu_properties=cpu_props,
                     chosen_properties=chosen_properties("fpga"),
                     root_nodes=root_nodes, cache_block_operations=["zicbom", "zicboz"],
                     interrupts_in_soc=True,
                     soc_compatible=["freechips,rocketchip-unknown-soc", "simple-bus"],
                     plic_node_name="interrupt-controller", interrupt_reg_names="control",
                     plic_ndev=66,
                     uartlite_addr=None,
                     bootargs="console=hvc0 earlycon=sbi loglevel=8")
        gen.add_device(debug_controller(nr_harts))
        gen.add_device(serial16550())
    elif name.startswith("xiangshan-qemu-nemu"):
        isa = set(profiles["qemu-nemu"]["isa_extensions"])
        if is_novec:
            isa.difference_update(VECTOR_EXTENSIONS)
        cpu_props = cache_properties()
        cpu_props += "\nnext-level-cache = <&l2_cache>;"
        root_nodes += ["aliases { serial0 = &uart0; };", """l2_cache: l2-cache {
    compatible = "cache";
    cache-level = <2>;
    cache-block-size = <64>;
    cache-size = <1048576>;
};"""]
        gen = DTSGen(compatible="freechips,rocketchip-unknown-dev", model="qemu,nemu",
                     cpu_compatibles=["ICT,xiangshan", "riscv"],
                     isa_extensions=DTSGen.sort_isa_extensions(sorted(isa)),
                     legacy_isa=(profiles["qemu-nemu"]["legacy_isa"]
                                 if not is_novec else profiles["qemu-nemu"]["legacy_isa"].replace("rv64imafdcvh", "rv64imafdch")),
                     mmu_type="riscv,sv48", timebase_freq=1000000,
                     nr_harts=nr_harts, memories=[(DRAM_BASE, memory)],
                     reserved_memories=[], cpu_properties=cpu_props,
                     chosen_properties=chosen_properties("qemu"), root_nodes=root_nodes,
                     plic_ndev=66,
                     uartlite_addr=None,
                     bootargs="console=hvc0 earlycon=sbi")
        gen.add_device(serial16550())
    elif name == "xiangshan":
        gen = DTSGen(compatible="freechips,rocketchip-unknown-dev",
                     model="freechips,rocketchip-unknown",
                     cpu_compatibles=["UCAS,COOSCA1.0", "riscv"],
                     isa_extensions=DTSGen.sort_isa_extensions("i m a f d c h v".split()),
                     legacy_isa="rv64imafdchv", mmu_type="riscv,sv39",
                     timebase_freq=1000000, memories=[(DRAM_BASE, memory)],
                     reserved_memories=[], plic_machine_first=False,
                     chosen_properties=chosen_properties("nemu"),
                     bootargs="console=hvc0 earlycon=sbi")
    elif name.startswith("spike"):
        nr_harts = 2 if name == "spike-2core" else 1
        gen = DTSGen(compatible="ucbbar,spike-bare-dev", model="ucbbar,spike-bare",
                     isa_extensions=DTSGen.sort_isa_extensions("i m a f d c zicntr zihpm".split()),
                     legacy_isa="rv64imafdc_zicntr_zihpm", mmu_type="riscv,sv57",
                     timebase_freq=10000000, nr_harts=nr_harts, clint_addr=0x02000000,
                     plic_addr=0x0c000000, plic_ndev=31, memories=[(DRAM_BASE, 2 << 30)],
                     reserved_memories=[], chosen_properties=chosen_properties("spike"),
                     uartlite_addr=None, bootargs="console=ttyS0 earlycon",
                     root_nodes=["htif { compatible = \"ucb,htif0\"; };"])
        gen.add_device(serial_spike())
    elif name == "nutshell":
        gen = DTSGen(compatible="freechips,rocketchip-unknown-dev",
                     model="xiangshan,xiangshan-kunminghu",
                     cpu_compatibles=["UCAS,COOSCA1.0", "riscv"],
                     isa_extensions=DTSGen.sort_isa_extensions("i m a c zicntr zicsr zifencei zihpm".split()),
                     legacy_isa="rv64imafdc", mmu_type="riscv,sv39", timebase_freq=1000000,
                     clint_addr=0x38000000, plic_addr=None, memories=[(DRAM_BASE, 128 << 20)],
                     reserved_memories=[], uartlite_addr=None,
                     chosen_properties=chosen_properties("nemu"),
                     bootargs="console=hvc0 earlycon=sbi")
        gen.add_device(serial_uartlite())
    elif name == "xiangshan-fpga-AIA-mem16g":
        isa_config = profiles["fpga-noaia-novec"]["isa_configs"]["kunminghu-v2"]
        isa = set(profiles["fpga-noaia-novec"]["isa_extensions"])
        isa.update(isa_config["isa_extensions"])
        isa.discard("zca")
        isa.update({"smaia", "ssaia", "zabha", "zicbom", "zicboz"})
        isa.update(VECTOR_EXTENSIONS)
        cpu_props = cache_properties(timebase=True) + "\nnext-level-cache = <&l2_cache>;"
        root_nodes = ["aliases { serial0 = &uart0; };", """l2_cache: l2-cache {
    compatible = "cache";
    cache-level = <2>;
    cache-block-size = <64>;
    cache-size = <1048576>;
};"""]
        gen = DTSGen(compatible="freechips,rocketchip-unknown-dev",
                     model="xiangshan,Kunminghu-dev",
                     cpu_compatibles=["ICT,xiangshan", "riscv"],
                     isa_extensions=DTSGen.sort_isa_extensions(sorted(isa)),
                     legacy_isa="rv64imafdcvh_smaia_smstateen_sscofpmf_sstc_zicntr_zihpm_svpbmt_sdtrig_smcsrind_sscsrind_svade",
                     mmu_type="riscv,sv48", timebase_freq=1000000,
                     memories=[(DRAM_BASE, 16 << 30)], reserved_memories=[],
                     plic_addr=None, cpu_properties=cpu_props,
                     chosen_properties=chosen_properties("fpga"), root_nodes=root_nodes,
                     cache_block_operations=["zicbom", "zicboz"], interrupts_in_soc=True,
                     soc_compatible=["freechips,rocketchip-unknown-soc", "simple-bus"],
                     interrupt_reg_names="control",
                     bootargs="console=hvc0 earlycon=sbi loglevel=8")
        gen.add_device(debug_controller(1))
        for device in aia_devices() + [serial16550()]:
            gen.add_device(device)
    elif name.startswith("yanqihu"):
        nr_harts = 2 if name == "yanqihu-2core" else 1
        gen = DTSGen(compatible="freechips,rocketchip-unknown-dev",
                     model="freechips,rocketchip-unknown",
                     cpu_compatibles=["UCAS,COOSCA1.0", "riscv"],
                     isa_extensions=DTSGen.sort_isa_extensions("i m a f d c".split()),
                     legacy_isa="rv64imafdc", mmu_type="riscv,sv39", timebase_freq=1000000,
                     nr_harts=nr_harts, memories=[(DRAM_BASE, 128 << 20)],
                     reserved_memories=[], plic_machine_first=False,
                     chosen_properties=chosen_properties("nemu"),
                     bootargs="console=hvc0 earlycon=sbi")
    else:
        raise UnsupportedDTSName(f"unsupported DTS basename: {name}")

    gen.add_reserved_memory(DRAM_BASE, 0x100000, name="gcpt")
    if nr_harts > 1 and name.startswith(
            ("xiangshan-fpga-noAIA", "xiangshan-qemu-nemu")):
        gen.add_reserved_memory(0x80300000, 0x08300000, name="checkpoint")
    output = gen.gen_dts()
    output = output.replace("0x80300000 0x0 0x8300000", "0x80300000 0x0 0x08300000")
    return "/* Generated by nemu_board for workload-builder. */\n" + output + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True, help="DTS basename without .dts.in")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--isa-config", choices=["kunminghu-v3", "kunminghu-v2"],
                        default="kunminghu-v3",
                        help="named FPGA noAIA ISA declaration (default: kunminghu-v3)")
    parser.add_argument("--custom-template-dir", type=Path, default=None,
                        help="directory holding user-supplied templates for "
                             "unsupported basenames")
    args = parser.parse_args()
    if not args.output.name.endswith(".dts.in"):
        parser.error("--output must end in .dts.in")
    try:
        try:
            output = render(args.name, args.isa_config)
        except UnsupportedDTSName:
            custom = (args.custom_template_dir / f"{args.name}.dts.in"
                      if args.custom_template_dir else None)
            if custom is None or not custom.is_file():
                raise
            output = custom.read_text(encoding="utf-8")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile("w", encoding="utf-8",
                                         dir=args.output.parent, delete=False) as tmp:
            tmp.write(output)
        os.replace(tmp.name, args.output)
    except (OSError, ValueError) as exc:
        parser.error(str(exc))


if __name__ == "__main__":
    main()
