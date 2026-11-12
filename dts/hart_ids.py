#!/usr/bin/env python3

import argparse
import re


MAX_HART_ID = 4094


def normalize_hart_ids(value, count):
    try:
        ids = [int(part.strip(), 0) for part in value.split(",")]
    except ValueError as exc:
        raise ValueError("hart IDs must be comma-separated integers") from exc
    if any(hart < 0 or hart > MAX_HART_ID for hart in ids):
        raise ValueError(f"hart IDs must be in the range 0..{MAX_HART_ID}")
    if len(ids) != count:
        raise ValueError(f"expected {count} hart IDs, found {len(ids)}")
    if len(ids) != len(set(ids)):
        raise ValueError("hart IDs must be unique")
    if 0 not in ids:
        raise ValueError("hart IDs must include 0")
    return [0] + [hart for hart in ids if hart != 0]


def remap_custom_dts(text, ids):
    nodes = list(re.finditer(r"\bcpu@[0-9a-fA-F]+\s*\{", text))
    if len(nodes) != len(ids):
        raise ValueError(f"expected {len(ids)} CPU nodes, found {len(nodes)}")

    parts = []
    previous_end = 0
    for node, hart in zip(nodes, ids):
        start = node.start()
        depth = 0
        for end in range(start, len(text)):
            if text[end] == "{":
                depth += 1
            elif text[end] == "}":
                depth -= 1
                if depth == 0:
                    end = text.index(";", end) + 1
                    break
        else:
            raise ValueError("unterminated CPU node")

        body = text[start:end]
        body = re.sub(r"cpu@[0-9a-fA-F]+", f"cpu@{hart:x}", body, count=1)
        body, replacements = re.subn(
            r"\breg\s*=\s*<[^>]+>\s*;", f"reg = <0x{hart:x}>;", body, count=1
        )
        if replacements != 1:
            raise ValueError(f"CPU node cpu@{hart:x} has no reg property")
        parts.extend((text[previous_end:start], body))
        previous_end = end

    parts.append(text[previous_end:])
    return "".join(parts)


def main():
    parser = argparse.ArgumentParser(description="Normalize configured hart IDs.")
    parser.add_argument("--ids", required=True)
    parser.add_argument("--harts", required=True, type=int)
    args = parser.parse_args()
    try:
        ids = normalize_hart_ids(args.ids, args.harts)
    except ValueError as exc:
        parser.error(str(exc))
    print(",".join(map(str, ids)))


if __name__ == "__main__":
    main()
