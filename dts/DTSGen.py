#!/usr/bin/env python3

from functools import cmp_to_key
import re
import json

class DTSGen:
    def __init__(self,
                 compatible: str | list = "xiangshan,nemu-board",
                 model: str = "XiangShan",
                 cpu_compatibles: list | None = None,
                 isa_extensions: list = ["i", "m", "a", "f", "d", "c"],
                 mmu_type="riscv,sv39",
                 timebase_freq: int = 10000000, # 10 MHz
                 nr_harts: int = 1,
                 clint_addr: int = 0x38000000,
                 plic_addr: int = 0x3c000000,
                 memories: list = [(0x80000000, 8*1024*1024*1024)], # [(start, size)], default 8 GB at 2 GB
                 reserved_memories: list = [], # [(start, size)]
                 bootargs: str = "console=hvc0 earlycon=sbi rdinit=/sbin/init",
                 rng_seed: bytes = b"XIANGSHAN_NEMU_BOARD_RANDOM_SEED",
                 uartlite_addr: int = 0x40600000,
                 nemu_sdhci_addr: int = None,
                 plic_ndev: int = 64,
                 plic_machine_first: bool = True,
                 cpu_properties: str = "",
                 chosen_properties: str = "",
                 root_nodes: list | None = None,
                 legacy_isa: str | None = None,
                 cache_block_operations: list | None = None,
                 interrupts_in_soc: bool = False,
                 soc_compatible: str | list = "simple-bus",
                 plic_node_name: str = "plic",
                 interrupt_reg_names: str | None = None):
        self.isa_extensions = isa_extensions
        self.mmu_type = mmu_type
        self.timebase_freq = timebase_freq
        self.nr_harts = nr_harts
        self.clint_addr = clint_addr
        self.plic_addr = plic_addr
        self.memories = memories
        self.reserved_memories = list(reserved_memories)
        self.plic_ndev = plic_ndev
        self.plic_machine_first = plic_machine_first
        self.cpu_properties = cpu_properties
        self.chosen_properties = chosen_properties
        self.root_nodes = list(root_nodes or [])
        self.legacy_isa = legacy_isa
        self.cache_block_operations = cache_block_operations
        self.interrupts_in_soc = interrupts_in_soc
        self.soc_compatible = ([soc_compatible] if isinstance(soc_compatible, str)
                               else soc_compatible)
        self.plic_node_name = plic_node_name
        self.interrupt_reg_names = interrupt_reg_names
        if isinstance(compatible, str):
            self.compatible = [compatible]
        else:
            self.compatible = compatible
        self.model = model
        if cpu_compatibles is None:
            self.cpu_compatibles = ["riscv"]
        elif isinstance(cpu_compatibles, str):
            self.cpu_compatibles = [cpu_compatibles]
        else:
            self.cpu_compatibles = cpu_compatibles
        self.bootargs = bootargs
        # Note: console=hvc0 is a hack for NEMU Uartlite to use SBI
        # console to get around the lack of TX FIFO empty interrupt
        # implementation. The proper param should be "console=ttyUL0"
        # for Uartlite IP on Xilinx FPGA.
        # Ensure we have set the following kernel configs:
        # CONFIG_NONPORTABLE=y
        # CONFIG_HVC_RISCV_SBI=y
        self.rng_seed = rng_seed
        self.soc_devices = [] # [dev_str0, ...]
        if uartlite_addr is not None and plic_addr is not None:
            self.soc_devices.append(self.__gen_uartlite(uartlite_addr, 3))
        if nemu_sdhci_addr is not None:
            self.soc_devices.append(self.__gen_nemu_sdhci(nemu_sdhci_addr))

    def add_reserved_memory(self, start: int, size: int, name: str | None = None, no_map: bool = True):
        self.reserved_memories.append({
            "start": start,
            "size": size,
            "name": name,
            "no_map": no_map,
        })
        return self

    def indent(text, level: int = 4):
        indent_str = ' ' * level
        return "\n".join(indent_str + line if line.strip() != "" else line for line in text.split("\n"))

    def gen_addrsize(addrsize, cell_number):
        res = ""
        for i in range(cell_number):
            res += f"0x{(addrsize >> (32 * (cell_number - i - 1))) & 0xFFFFFFFF:x} "
        return res.strip()

    def __gen_memory(self, memory_start, memory_size):
        return f"""
memory@{memory_start:x} {{
    device_type = "memory";
    reg = <{DTSGen.gen_addrsize(memory_start, 2)} {DTSGen.gen_addrsize(memory_size, 2)}>;
}};
""".strip()

    def __gen_isa_string(self, isa, cacheline_size=64):
        # Cache parameters are used for Zicbom / Zicbop / Zicboz
        # support in Linux
        cache_block_operations = (set(self.cache_block_operations)
                                  if self.cache_block_operations is not None
                                  else {"zicbom", "zicbop", "zicboz"})
        return f"""
{ f"riscv,cbom-block-size = <{cacheline_size}>;" if "zicbom" in isa and "zicbom" in cache_block_operations else "" }
{ f"riscv,cbop-block-size = <{cacheline_size}>;" if "zicbop" in isa and "zicbop" in cache_block_operations else "" }
{ f"riscv,cboz-block-size = <{cacheline_size}>;" if "zicboz" in isa and "zicboz" in cache_block_operations else "" }
riscv,isa = "{self.legacy_isa or ('rv64i' + ''.join(ext for ext in 'mafdcvh' if ext in isa))}";
riscv,isa-base = "rv64i";
riscv,isa-extensions = {", ".join(f'"{ext}"' for ext in isa)};
""".strip()

    def __gen_cpu_node(self, hart_id, isa):
        # Reference: https://github.com/torvalds/linux/blob/master/Documentation/devicetree/bindings/riscv/cpus.yaml
        compatible_list = ", ".join(f'"{compatible}"' for compatible in self.cpu_compatibles)
        return f"""
cpu{hart_id}: cpu@{hart_id:x} {{
    compatible = {compatible_list};
    device_type = "cpu";
    mmu-type = "{self.mmu_type}";
    reg = <{hart_id}>;
{DTSGen.indent(self.__gen_isa_string(isa))}
{DTSGen.indent(self.cpu_properties)}

    cpu{hart_id}_intc: interrupt-controller {{
        #interrupt-cells = <1>;
        compatible = "riscv,cpu-intc";
        interrupt-controller;
    }};
}};
""".strip()

    def __gen_cpus(self):
        cpu_nodes = "\n".join(
            self.__gen_cpu_node(hart_id, self.isa_extensions) + "\n"
            for hart_id in range(self.nr_harts)
        )
        return f"""
cpus {{
    #address-cells = <1>;
    #size-cells = <0>;
    timebase-frequency = <{self.timebase_freq}>;

{DTSGen.indent(cpu_nodes)}
}};
""".strip()

    def __gen_clint(self):
        # Reference: https://github.com/torvalds/linux/blob/master/Documentation/devicetree/bindings/timer/sifive%2Cclint.yaml
        if self.clint_addr == None:
            return ""
        # 3 is MSI, 7 is MTI
        cpu_intc_list = [f"<&cpu{hart_id}_intc 3>, <&cpu{hart_id}_intc 7>" for hart_id in range(self.nr_harts)]
        cpu_intc_head = "    interrupts-extended = ";
        cpu_intc_str = cpu_intc_head
        for each_intc in zip(cpu_intc_list, list(range(self.nr_harts))):
            cpu_intc_str += each_intc[0]
            if each_intc[1] != self.nr_harts - 1:
                cpu_intc_str += ",\n" + " " * (len(cpu_intc_head))
        return f"""
clint: clint@{self.clint_addr:x} {{
    compatible = "riscv,clint0";
    reg = <{DTSGen.gen_addrsize(self.clint_addr, 2)} {DTSGen.gen_addrsize(0x10000, 2)}>;
{f'    reg-names = "{self.interrupt_reg_names}";' if self.interrupt_reg_names else ''}
{cpu_intc_str};
}};
""".strip()

    def __gen_plic(self, max_priority: int = 7, ndev: int = 64):
        # Reference: https://github.com/torvalds/linux/blob/master/Documentation/devicetree/bindings/interrupt-controller/sifive%2Cplic-1.0.0.yaml
        if self.plic_addr is None:
            return ""
        # 11 is MEI, 9 is SEI
        irqs = (11, 9) if self.plic_machine_first else (9, 11)
        cpu_intc_list = [f"<&cpu{hart_id}_intc {irqs[0]}>, <&cpu{hart_id}_intc {irqs[1]}>" for hart_id in range(self.nr_harts)]
        cpu_intc_head = "    interrupts-extended = ";
        cpu_intc_str = cpu_intc_head
        for each_intc in zip(cpu_intc_list, list(range(self.nr_harts))):
            cpu_intc_str += each_intc[0]
            if each_intc[1] != self.nr_harts - 1:
                cpu_intc_str += ",\n" + " " * (len(cpu_intc_head))
        return f"""
plic: {self.plic_node_name}@{self.plic_addr:x} {{
    compatible = "riscv,plic0";
    reg = <{DTSGen.gen_addrsize(self.plic_addr, 2)} {DTSGen.gen_addrsize(0x4000000, 2)}>;
{f'    reg-names = "{self.interrupt_reg_names}";' if self.interrupt_reg_names else ''}
    #interrupt-cells = <1>;
    interrupt-controller;
{cpu_intc_str};
    riscv,max-priority = <{max_priority}>;
    riscv,ndev = <{ndev}>;
}};
""".strip()

    def __gen_reserved_memory(self):
        if len(self.reserved_memories) == 0:
            return ""
        res = f"""
reserved-memory {{
    #address-cells = <2>;
    #size-cells = <2>;
    ranges;
"""
        for entry, idx in zip(self.reserved_memories, list(range(len(self.reserved_memories)))):
            if isinstance(entry, dict):
                start = entry["start"]
                size = entry["size"]
                name = entry.get("name") or f"resv{idx}"
                no_map = entry.get("no_map", True)
            else:
                start, size = entry
                name = f"resv{idx}"
                no_map = True

            entry_lines = [
                f"{name}@{start:x} {{",
                f"    reg = <{DTSGen.gen_addrsize(start, 2)} {DTSGen.gen_addrsize(size, 2)}>;",
            ]
            if no_map:
                entry_lines.append("    no-map;")
            entry_lines.append("};")
            res += DTSGen.indent("\n".join(entry_lines) + "\n")
        res += "};"
        return res

    def __gen_uartlite(self, uartlite_addr, plic_addr):
        # https://github.com/torvalds/linux/blob/master/Documentation/devicetree/bindings/serial/xlnx%2Copb-uartlite.yaml
        # Uartlite hardware does not handle clock division, so we do
        # not specify clocks here
        return f"""
serial@{uartlite_addr:x} {{
    compatible = "xlnx,xps-uartlite-1.00.a";
    reg = <{DTSGen.gen_addrsize(uartlite_addr, 2)} {DTSGen.gen_addrsize(0x1000, 2)}>;
    interrupts-extended = <&plic {plic_addr}>;
    current-speed = <115200>;
    xlnx,data-bits = <8>;
    xlnx,use-parity = <0>;
}};
""".strip()

    def __gen_nemu_sdhci(self, sd_addr):
        return f"""
mmc@{sd_addr:x} {{
    compatible = "nemu,sdhost";
    reg = <{DTSGen.gen_addrsize(sd_addr, 2)} {DTSGen.gen_addrsize(0x1000, 2)}>;
}};
""".strip()

    def __gen_soc(self):
        compatible_list = ", ".join(f'"{compatible}"' for compatible in self.soc_compatible)
        res = f"""
soc {{
    #address-cells = <2>;
    #size-cells = <2>;
    compatible = {compatible_list};
    ranges;
""" + "\n"
        if self.interrupts_in_soc:
            for dev_str in (self.__gen_clint(), self.__gen_plic(ndev=self.plic_ndev)):
                if dev_str:
                    res += DTSGen.indent(dev_str, 4) + "\n\n"
        for dev_str in self.soc_devices:
            res += DTSGen.indent(dev_str, 4) + "\n\n"
        res += "};"
        return res.strip()

    def sort_isa_extensions(ext_list: list):
        SINGLE_ORDER = list("IMAFDQLCBKJTPVH")
        # Helper to categorize an extension name
        def ext_category(ext: str):
            """Return (category, key1, key2) so sorting works:
            category:
            0 = single-letter standard
            1 = standard Z* (multi-letter beginning with 'Z')
            2 = supervisor-level S*, hypervisor H*, machine-level Zxm*, etc.
            3 = non-standard X*
            key1/key2: for ordering within category
            """
            # normalize
            e = ext.strip()
            # Remove version suffixes (e.g., p0, p1p2, digits) for ordering only
            e_base = re.sub(r'[0-9pP].*$', '', e)
            # Single-letter standard?
            if len(e_base) == 1 and e_base.upper() in SINGLE_ORDER:
                return (0, SINGLE_ORDER.index(e_base.upper()), "")
            # Supervisor-level (S*), Hypervisor-level (H*), Machine-level (Zxm*), etc.
            if re.match(r'^(S|Sh|Sm|Zxm)', e_base, re.IGNORECASE):
                return (2, e_base.lower(), "")
            # Z* standard unprivileged
            if e_base.startswith("Z"):
                # use the letter after Z to map to SINGLE_ORDER index if possible
                cat0 = e_base[1].upper()
                idx = SINGLE_ORDER.index(cat0) if cat0 in SINGLE_ORDER else ord(cat0)
                return (1, idx, e_base.lower())
            # Non-standard X*
            if e_base.startswith("X"):
                return (3, e_base.lower(), "")
            # Unknown / fallback
            return (4, e_base.lower(), "")
        def compare_ext(a: str, b: str):
            ca = ext_category(a)
            cb = ext_category(b)
            if ca < cb:
                return -1
            if ca > cb:
                return 1
            # same category — compare category-specific keys
            if ca[1] != cb[1]:
                return -1 if ca[1] < cb[1] else 1
            # tie-breaker: lex order on base
            return -1 if ca[2] < cb[2] else (1 if ca[2] > cb[2] else 0)
        return sorted(ext_list, key=cmp_to_key(compare_ext))


    def get_isa_extensions_by_rva_profile(rva_profile: str):
        RVA20U64 = {
            "i", "m", "a", "f", "d", "c",
            "zicsr", "zicntr"
            # "ziccif", "ziccrse", "ziccamoa", "za128rs", "zicclsm"
        }
        RVA20S64 = RVA20U64.union({
            "zifencei"
            # "ss1p11", "svbare", "sv39", "svade", "ssccptr",
            # "sstvecd", "sstvala"
        })
        # Don't use 'b' for backward compatibility as it ratified in 2024
        RVA22U64 = RVA20U64.union({
            "zba", "zbb", "zbs", "zihpm", "zihintpause", "zicbom",
            "zicbop", "zicboz", "zfhmin", "zkt"
            # "za64rs", "zic64b"
        })
        RVA22S64 = RVA22U64.union({
            "zifencei", "svpbmt", "svinval"
            # "ss1p12", "svbare", "sv39", "svade", "ssccptr",
            # "sstvecd", "sstvala", "sscounterenw"
        })
        RVA23U64 = RVA22U64.union({
            "v", "zvfhmin", "zvbb", "zvkt", "zihintntl", "zicond",
            "zimop", "zcmop", "zcb", "zfa", "zawrs", "supm"
        })
        RVA23S64 = RVA23U64.union({
            "zifencei", "svpbmt", "svinval", "sstc", "sscofpmf",
            "sha", "h"
            # "ss1p13", "ssnpm", "ssu64xl", "ssstateen", "shtvala",
            # "shvstvecd", "shvsatpa", "shgatpa"
        })
        if rva_profile == "rva20u64":
            return DTSGen.sort_isa_extensions(list(RVA20U64))
        elif rva_profile == "rva20s64":
            return DTSGen.sort_isa_extensions(list(RVA20S64))
        elif rva_profile == "rva22u64":
            return DTSGen.sort_isa_extensions(list(RVA22U64))
        elif rva_profile == "rva22s64":
            return DTSGen.sort_isa_extensions(list(RVA22S64))
        elif rva_profile == "rva23u64":
            return DTSGen.sort_isa_extensions(list(RVA23U64))
        elif rva_profile == "rva23s64":
            return DTSGen.sort_isa_extensions(list(RVA23S64))
        assert False, f"Unknown rva profile string: {rva_profile}"

    def add_device(self, dev_str: str):
        self.soc_devices.append(dev_str)
        return self

    def gen_dts(self):
        compatible_list = ", ".join(f'"{compatible}"' for compatible in self.compatible)
        bootargs = (DTSGen.indent(f"bootargs = {json.dumps(self.bootargs)};", 8)
                    if self.bootargs else "")
        rng_seed = ""
        if self.rng_seed:
            ascii_seed = self.rng_seed.decode("ascii", "backslashreplace")
            hex_seed = " ".join(f"0x{byte:02x}" for byte in self.rng_seed)
            rng_seed = DTSGen.indent(
                f'/* ASCII: "{ascii_seed}" */\nrng-seed = /bits/ 8 <{hex_seed}>;', 8)
        memories = DTSGen.indent("\n".join(
            self.__gen_memory(start, size) for (start, size) in self.memories
        ))
        return f"""
/dts-v1/;

/ {{
    #address-cells = <2>;
    #size-cells = <2>;
    compatible = {compatible_list};
    model = "{self.model}";

    chosen {{
{bootargs}
{rng_seed}
{DTSGen.indent(self.chosen_properties, 8)}
    }};

{memories}

{DTSGen.indent(self.__gen_cpus())}

{DTSGen.indent(self.__gen_clint()) if not self.interrupts_in_soc else ''}

{DTSGen.indent(self.__gen_plic(ndev=self.plic_ndev)) if not self.interrupts_in_soc else ''}

{DTSGen.indent(self.__gen_reserved_memory())}

{DTSGen.indent(self.__gen_soc())}

{DTSGen.indent(chr(10).join(self.root_nodes))}

}};
""".strip()


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser("DTSGen: Generate Device Tree Source for NEMU Board")
    parser.add_argument("--compatible", type=str, nargs='+', default=["xiangshan,nemu-board"], help="Root compatible strings in priority order")
    parser.add_argument("--model", type=str, default="XiangShan", help="Root model string")
    parser.add_argument("--cpu-compatible", type=str, nargs='+', default=["riscv"], help="CPU compatible strings in priority order")
    parser.add_argument("--nr-harts", "-n", type=int, default=1, help="Number of harts")
    parser.add_argument("--nemu-sdhci-addr", "-s", type=lambda x: int(x,0), default=None, help="NEMU SDHCI address")
    parser.add_argument("--uartlite-addr", type=lambda x: int(x,0), default=0x40600000, help="UARTLite MMIO base address")
    parser.add_argument("--reserve-mem", "-r", type=lambda x: int(x,0), nargs=2, action='append', default=[], help="Reserved memory regions, specify as start size pairs (hex 0x... or decimal)")
    parser.add_argument("--direct-map-mem", type=lambda x: int(x,0), nargs=2, action='append', default=[], help="Reserved direct-map regions, specify as start size pairs (hex 0x... or decimal)")
    parser.add_argument("--isa-extensions", "-i", type=str, nargs='+', default=["i", "m", "a", "f", "d", "c"], help="ISA extensions, e.g., i m a f d c")
    parser.add_argument("--rva-profile", "-p", type=str, default="rva20u64", help="rva profile string, e.g., rva20u64, rva22s64, rva23s64")
    parser.add_argument("--bootargs", "-b", type=str, default="console=hvc0 earlycon=sbi rdinit=/sbin/init", help="Kernel boot arguments")
    parser.add_argument("--memory-size", "-m", type=lambda x: int(x,0), default=8*1024*1024*1024, help="Total memory size in bytes (hex 0x... or decimal)")
    parser.add_argument("--mmu-type", type=str, default="riscv,sv39", help="MMU type")
    parser.add_argument("--timebase-freq", "-t", type=int, default=10000000, help="Timebase frequency in Hz (default 10 MHz)")
    args = parser.parse_args()
    isa_exts = set(args.isa_extensions)
    if args.rva_profile:
        isa_exts.update(set(DTSGen.get_isa_extensions_by_rva_profile(args.rva_profile)))
    dtsgen = DTSGen(
        compatible=args.compatible,
        model=args.model,
        cpu_compatibles=args.cpu_compatible,
        nr_harts=args.nr_harts,
        uartlite_addr=args.uartlite_addr,
        nemu_sdhci_addr=args.nemu_sdhci_addr,
        isa_extensions=DTSGen.sort_isa_extensions(list(isa_exts)),
        bootargs=args.bootargs,
        mmu_type=args.mmu_type,
        timebase_freq=args.timebase_freq,
        memories=[(0x80000000, args.memory_size)]
    )
    for start, size in args.reserve_mem:
        dtsgen.add_reserved_memory(start, size)
    for start, size in args.direct_map_mem:
        dtsgen.add_reserved_memory(start, size, name="direct_map", no_map=False)
    print(dtsgen.gen_dts())
