#!/usr/bin/env python3
import argparse
import re
from pathlib import Path


MULTIHART_RISCV_ISA = "rv64imafdc"
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


def normalize_cpu_isa(cpu_node_text):
    normalized, replacements = CPU_ISA_PROPERTIES.subn(
        f'\t\t\triscv,isa = "{MULTIHART_RISCV_ISA}";\n', cpu_node_text, count=1
    )
    if replacements != 1:
        raise RuntimeError("CPU node does not contain the expected ISA properties")
    return normalized


def interrupt_list(harts, machine_irq, supervisor_irq):
    return " ".join(
        f"&intc_cpu{hart} {machine_irq} &intc_cpu{hart} {supervisor_irq}"
        for hart in range(harts)
    )


def debug_interrupt_list(harts):
    return " ".join(f"&intc_cpu{hart} 65535" for hart in range(harts))


def align_nemu_plic(text):
    return re.sub(r"riscv,ndev = <(?:0x42|66)>;", "riscv,ndev = <64>;", text)


def replace_fpga_uart_with_nemu_uartlite(text):
    node_header = "\t\tuart0: serial@310b0000 {"
    if node_header not in text:
        return text

    start, end = extract_node(text, node_header)
    comment_start = text.rfind("\n\t\t/*", 0, start)
    if comment_start != -1 and "UART16550" in text[comment_start:start]:
        start = comment_start + 1
    uart = "\n".join(
        [
            "\t\t/*",
            "\t\t * QEMU/NEMU exposes UARTLITE at 0x40600000.",
            "\t\t */",
            "\t\tuart0: serial@40600000 {",
            '\t\t\tcompatible = "xlnx,xps-uartlite-1.00.a";',
            "\t\t\tinterrupt-parent = <&PLIC>;",
            "\t\t\tinterrupts = <3>;",
            "\t\t\tcurrent-speed = <115200>;",
            "\t\t\treg = <0x0 0x40600000 0x0 0x1000>;",
            '\t\t\treg-names = "control";',
            '\t\t\tstatus = "okay";',
            "\t\t};",
        ]
    )
    return text[:start] + uart + text[end:]


def sanitize_nemu_uart_comments(text):
    text = text.replace(
        " * 2. UART16550 is exposed as the serial console.",
        " * 2. QEMU/NEMU UARTLITE is exposed as the serial console.",
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
    if "checkpoint@80300000" in text:
        return text

    start, end = extract_node(text, "\treserved-memory {")
    close = text.rfind("\n\t};", start, end)
    if close == -1:
        raise RuntimeError("reserved-memory node does not have the expected closing brace")
    return text[:close] + CHECKPOINT_RESERVED_NODE + text[close:]


def render(base_text, harts):
    start, end = extract_node(base_text, "\t\tcpu0: cpu@0 {")
    cpu0_node = normalize_cpu_isa(base_text[start:end])
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
    text = align_nemu_plic(text)
    text = replace_fpga_uart_with_nemu_uartlite(text)
    text = sanitize_nemu_uart_comments(text)
    text = add_checkpoint_reserved_memory(text)
    return text


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", required=True, type=Path)
    parser.add_argument("--harts", required=True, type=positive_harts)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    base_text = args.base.read_text(encoding="utf-8")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(render(base_text, args.harts), encoding="utf-8")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        raise SystemExit(str(exc))
