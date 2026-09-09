#!/usr/bin/env bash
set -eo pipefail
qemu="${CHIBI_QEMU:-qemu-system-riscv64}"
bios="${CHIBI_QEMU_BIOS:-default}"
if ! command -v "$qemu" >/dev/null; then
    echo 'qemu-system-riscv64 is missing. Run make setup first.' >&2
    exit 1
fi
if [[ "$bios" == none ]]; then
    echo 'S-mode requires OpenSBI. Use QEMU_BIOS=default or an OpenSBI firmware path.' >&2
    exit 1
fi
# QEMU generates the virt DTB and OpenSBI supplies the S-mode handoff.
# Use the QEMU-specific ELF, never the Duo FIT/binary.
echo 'QEMU console: press Ctrl+C to exit.'
exec "$qemu" -machine virt -accel tcg -m 128M -smp 1 \
    -display none -monitor none \
    -chardev stdio,id=console,signal=on -serial chardev:console \
    -bios "$bios" -kernel build/qemu/chibi-os.elf
