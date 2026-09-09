#!/usr/bin/env bash
set -eo pipefail

if [[ "${CHIBI_SKIP_DEPS:-}" == 1 ]]; then
    echo 'Skipping package installation; checking existing tools next.'
    exit 0
fi
if [[ ! -f /etc/os-release ]]; then
    echo 'Automatic setup supports Ubuntu/Debian. Install GNU RISC-V tools, dtc and u-boot-tools manually.' >&2
    exit 1
fi
. /etc/os-release
if [[ "${ID:-}" != ubuntu && "${ID:-}" != debian ]]; then
    echo 'Automatic setup supports Ubuntu/Debian. See README for manual dependencies.' >&2
    exit 1
fi
privilege=()
if [[ "$EUID" -ne 0 ]]; then privilege=(sudo); fi
"${privilege[@]}" apt-get update
"${privilege[@]}" apt-get install -y make git \
    gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf \
    device-tree-compiler u-boot-tools python3 python3-venv picocom \
    qemu-system-misc opensbi
