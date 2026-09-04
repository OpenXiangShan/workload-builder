#!/usr/bin/env python3
import argparse
import re
from pathlib import Path


MAX_HARTS = 128
CHECKPOINT_RESERVED_NODE = """

		/* Keep the 131 MiB QEMU checkpoint window out of Linux memory. */
		checkpoint: checkpoint@80300000 {
			no-map;
			reg = <0x0 0x80300000 0x0 0x08300000>;
		};"""
CPU_ISA_PROPERTIES = re.compile(
    r'\t\t\triscv,isa = "[^"]+";\n'
    r'\t\t\triscv,isa-base = "[^"]+";\n'
    r"\t\t\triscv,isa-extensions =\n"
    r"(?:\t\t\t\t[^\n]*\n)*?"
    r"\t\t\t\t[^\n]*;\n"
)


def positive_harts(value):
    try:
        harts = int(value, 0)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("harts must be an integer") from exc
    if not 2 <= harts <= MAX_HARTS:
        raise argparse.ArgumentTypeError(f"harts must be in the range 2..{MAX_HARTS}")
    return harts


def positive_memory_gib(value):
    try:
        memory_gib = int(value, 0)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("memory-gib must be an integer") from exc
    if memory_gib <= 0:
        raise argparse.ArgumentTypeError("memory-gib must be greater than zero")
    return memory_gib


def extract_node(text, node_header):
    start = text.index(node_header)
    level = 0
    for idx in range(start, len(text)):
        char = text[idx]
        if char == "{":
            level += 1
        elif char == "}":
            level -= 1
            if level == 0:
                semi = text.index(";", idx)
                return start, semi + 1
    raise RuntimeError(f"node not found: {node_header}")


def cpu_node(cpu0_node, hart):
    node = cpu0_node
    node = node.replace("cpu0: cpu@0", f"cpu{hart}: cpu@{hart}")
    node = node.replace("reg = <0x0>;", f"reg = <0x{hart:x}>;")
    node = node.replace("intc_cpu0", f"intc_cpu{hart}")
    return node


def prepare_multihart_cpu_isa(cpu_node_text):
    match = CPU_ISA_PROPERTIES.search(cpu_node_text)
    if not match:
        raise RuntimeError("CPU node does not contain the expected ISA properties")

    isa_properties = match.group(0)
    isa_properties = isa_properties.replace("_sstc", "")
    isa_properties = isa_properties.replace(', "sstc"', "")
    return cpu_node_text[: match.start()] + isa_properties + cpu_node_text[match.end() :]


def interrupt_list(harts, machine_irq, supervisor_irq):
    return " ".join(
        f"&intc_cpu{hart} {machine_irq} &intc_cpu{hart} {supervisor_irq}"
        for hart in range(harts)
    )


def debug_interrupt_list(harts):
    return " ".join(f"&intc_cpu{hart} 65535" for hart in range(harts))


def align_qemu_plic(text):
    return re.sub(r"riscv,ndev = <(?:0x42|64|66)>;", "riscv,ndev = <66>;", text)


def replace_uart_with_qemu_16550(text):
    match = re.search(r"^\t\tuart0: serial@[0-9a-fA-F]+ \{", text, re.MULTILINE)
    if match is None:
        raise RuntimeError("DTS does not contain the expected uart0 node")

    start, end = extract_node(text, match.group(0))
    prefix = text[:start]
    comment_match = re.search(
        r"(?P<comment>\r?\n[ \t]*/\*(?:[^*]|\*(?!/))*\*/)[ \t]*\r?\n[ \t]*$",
        prefix,
    )
    if comment_match and re.search(
        r"(?i)(?:\bUART(?:LITE|16550)?\b|0x40600000|serial@[0-9a-fA-F]+)",
        comment_match.group("comment"),
    ):
        start = comment_match.start("comment") + 1
    uart = "\n".join(
        [
            "\t\t/*",
            "\t\t * QEMU's nemu machine exposes the XiangShan 16550A UART at 0x310b0000.",
            "\t\t * It is not connected to the PLIC.",
            "\t\t */",
            "\t\tuart0: serial@310b0000 {",
            '\t\t\tcompatible = "ns16550a";',
            "\t\t\tcurrent-speed = <115200>;",
            "\t\t\treg = <0x0 0x310b0000 0x0 0x10000>;",
            "\t\t\treg-shift = <0x2>;",
            "\t\t\treg-io-width = <0x4>;",
            "\t\t\tclock-frequency = <50000000>;",
            '\t\t\tstatus = "okay";',
            "\t\t};",
        ]
    )
    return text[:start] + uart + text[end:]


def sanitize_qemu_comments(text):
    text = text.replace(
        " * XiangShan FPGA DTS used by the fpga board flow.",
        " * XiangShan multi-hart DTS used by QEMU's nemu machine.",
    )
    text = text.replace(
        " * 2. UART16550 is exposed as the serial console.",
        " * 2. QEMU's nemu machine exposes a 16550A serial console.",
    )
    text = text.replace(
        " * 2. QEMU/NEMU UARTLITE is exposed as the serial console.",
        " * 2. QEMU's nemu machine exposes a 16550A serial console.",
    )
    text = text.replace(
        "This FPGA image boots without AIA.",
        "This QEMU configuration boots without AIA.",
    )
    chosen_comment = re.compile(
        r"\n\t\t/\*\n"
        r"\t\t \* On this FPGA DTS the UART16550 interrupt is not wired into Linux\n"
        r"(?:.*?\n)*?"
        r"\t\t \*/\n"
        r"\t\tbootargs = ",
        re.MULTILINE,
    )
    return chosen_comment.sub(
        "\n\t\t/*\n"
        "\t\t * Keep the SBI console as the primary console under QEMU/NEMU.\n"
        "\t\t */\n"
        "\t\tbootargs = ",
        text,
    )


def add_checkpoint_reserved_memory(text):
    start, end = extract_node(text, "\treserved-memory {")
    if re.search(r"@80300000\s*\{", text[start:end]):
        return text

    close = text.rfind("\n\t};", start, end)
    if close == -1:
        raise RuntimeError("reserved-memory node does not have the expected closing brace")
    return text[:close] + CHECKPOINT_RESERVED_NODE + text[close:]


def override_memory_profile(text, memory_gib):
    start, end = extract_node(text, "\tmemory: memory@80000000 {")
    memory_node = text[start:end]
    memory_bytes = memory_gib << 30
    size_high = memory_bytes >> 32
    size_low = memory_bytes & 0xFFFFFFFF
    if size_high > 0xFFFFFFFF:
        raise RuntimeError("memory-gib does not fit in a 64-bit DTS size")

    memory_node, comment_replacements = re.subn(
        r"\t\t/\*\n(?:\t\t \*.*\n)+\t\t \*/(?=\n\t\treg)",
        "\t\t/*\n"
        f"\t\t * Static {memory_gib} GiB memory profile for multi-hart workloads.\n"
        "\t\t */",
        memory_node,
        count=1,
    )
    memory_node, reg_replacements = re.subn(
        r"reg = <0x0 0x80000000 0x[0-9a-fA-F]+ 0x[0-9a-fA-F]+>;",
        f"reg = <0x0 0x80000000 0x{size_high:x} 0x{size_low:08x}>;",
        memory_node,
        count=1,
    )
    if comment_replacements != 1 or reg_replacements != 1:
        raise RuntimeError("memory node does not contain the expected static profile")
    return text[:start] + memory_node + text[end:]


def render(base_text, harts, memory_gib=None):
    start, end = extract_node(base_text, "\t\tcpu0: cpu@0 {")
    cpu0_node = prepare_multihart_cpu_isa(base_text[start:end])
    extra_cpus = "".join("\n\n" + cpu_node(cpu0_node, hart) for hart in range(1, harts))
    text = base_text[:start] + cpu0_node + extra_cpus + base_text[end:]

    text = text.replace(
        "interrupts-extended = <&intc_cpu0 3 &intc_cpu0 7>;",
        f"interrupts-extended = <{interrupt_list(harts, 3, 7)}>;",
    )
    text = text.replace(
        "interrupts-extended = <&intc_cpu0 65535>;",
        f"interrupts-extended = <{debug_interrupt_list(harts)}>;",
    )
    text = text.replace(
        "interrupts-extended = <&intc_cpu0 11 &intc_cpu0 9>;",
        f"interrupts-extended = <{interrupt_list(harts, 11, 9)}>;",
    )
    text = align_qemu_plic(text)
    text = replace_uart_with_qemu_16550(text)
    text = sanitize_qemu_comments(text)
    text = add_checkpoint_reserved_memory(text)
    if memory_gib is not None:
        text = override_memory_profile(text, memory_gib)
    return text


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", required=True, type=Path)
    parser.add_argument("--harts", required=True, type=positive_harts)
    parser.add_argument("--memory-gib", type=positive_memory_gib)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    base_text = args.base.read_text(encoding="utf-8")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        render(base_text, args.harts, memory_gib=args.memory_gib), encoding="utf-8"
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        raise SystemExit(str(exc))
