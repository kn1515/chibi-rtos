OUTPUT_ARCH(riscv)
ENTRY(_start)

/* 2 MiB above DRAM start, outside the OpenSBI reservation.
 * The vendor U-Boot has relocated before accepting boot commands. */
MEMORY {
    RAM (rwx) : ORIGIN = 0x80200000, LENGTH = 1M
}
PHDRS {
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}
SECTIONS {
    . = ORIGIN(RAM);
    .text : ALIGN(4) {
        KEEP(*(.text.boot))
        *(.text .text.*)
    } > RAM :text
    .rodata : ALIGN(16) { *(.rodata .rodata.* .srodata .srodata.*) } > RAM :text
    .data : ALIGN(16) {
        __global_pointer$ = . + 0x800;
        *(.data .data.* .sdata .sdata.*)
    } > RAM :data
    __image_end = .;
    .bss (NOLOAD) : ALIGN(16) {
        __bss_start = .;
        *(.bss .bss.* .sbss .sbss.*)
        *(COMMON)
        . = ALIGN(8);
        __bss_end = .;
    } > RAM :data
    .stack (NOLOAD) : ALIGN(16) {
        __stack_bottom = .;
        . += 16K;
        __stack_top = .;
    } > RAM :data
    __kernel_end = .;
    /DISCARD/ : { *(.comment .note.* .eh_frame .eh_frame_hdr) }
}
ASSERT(_start == 0x80200000, "entry must match FIT load/entry")
ASSERT((__stack_top & 15) == 0, "stack must be 16-byte aligned")
ASSERT(__kernel_end <= ORIGIN(RAM) + LENGTH(RAM), "kernel exceeds its 1 MiB region")
