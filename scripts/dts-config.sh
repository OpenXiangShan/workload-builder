#!/usr/bin/env bash

# Generate a recognized DTS basename or preserve an existing custom template.
dts_generate_template() {
    local dts_dir="$1"
    local default_dtb="$2"
    local generator="$(dirname "${BASH_SOURCE[0]}")/generate-nemu-board-dts.py"
    local custom_dir="$(dirname "${BASH_SOURCE[0]}")/../dts"
    local output="$dts_dir/$default_dtb.dts.in"

    python3 "$generator" --name "$default_dtb" --output "$output" \
        --preserve-existing-unsupported \
        --custom-template-dir "$custom_dir"
}

# Print the selected DTS address configuration as three shell words:
# memory base, memory size, and CLINT base.
dts_extract_config() {
    local dts_file="$1"

    if ! [ -f "$dts_file" ]; then
        echo "DTS file not found: $dts_file" >&2
        return 1
    fi

    perl -0777 -ne '
        sub value {
            my ($v) = @_;
            return $v =~ /^0x/i ? hex($v) : int($v);
        }
        sub cells {
            my ($node) = @_;
            return unless $node =~ /reg\s*=\s*<([^>]+)>/s;
            my @cells = $1 =~ /(0x[0-9a-fA-F]+|\d+)/g;
            return @cells;
        }
        sub address {
            my @cells = @_;
            return unless @cells >= 2;
            return (value($cells[0]) << 32) + value($cells[1]);
        }

        my (@memory, @clint);
        while (/(?:[A-Za-z_][A-Za-z0-9_]*:\s*)?[A-Za-z0-9,_-]*memory(?:@[^{]*)?\s*\{(.*?)\};/sg) {
            my $node = $1;
            next unless $node =~ /device_type\s*=\s*"memory"/s;
            my @cells = cells($node);
            next unless @cells >= 4;
            push @memory, [address(@cells[0, 1]), address(@cells[2, 3])];
        }
        while (/(?:[A-Za-z_][A-Za-z0-9_]*:\s*)?[A-Za-z0-9,_-]*clint@[^{]*\s*\{(.*?)\};/sg) {
            my $node = $1;
            next unless $node =~ /compatible\s*=\s*[^;]*"riscv,clint0"/s;
            my @cells = cells($node);
            next unless @cells >= 2;
            push @clint, address(@cells[0, 1]);
        }
        for my $entry (["memory", \@memory], ["CLINT", \@clint]) {
            my ($name, $values) = @$entry;
            if (@$values == 0) {
                print STDERR "DTS does not define a recognized $name node\n";
                exit 1;
            }
            if (@$values > 1) {
                print STDERR "DTS defines multiple recognized $name nodes\n";
                exit 1;
            }
        }
        my ($memory_base, $memory_size) = @{$memory[0]};
        printf "0x%x 0x%x 0x%x\n", $memory_base, $memory_size, $clint[0];
    ' "$dts_file"
}

dts_linux_kernel_address() {
    local memory_base="$1"
    local minimum_offset="$2"
    local alignment=$((2 * 1024 * 1024))

    printf '%s\n' $(( (memory_base + minimum_offset + alignment - 1) / alignment * alignment ))
}
