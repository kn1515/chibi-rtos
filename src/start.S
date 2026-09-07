/* U-Boot bootm handoff: S-mode, satp=0, a0=hart id, a1=DTB address.
 * One boot hart only. No U-Boot services or return path are used. */
    .section .text.boot, "ax", @progbits
    .globl _start
    .type _start, @function
    .balign 4
_start:
    csrci sstatus, 2             /* SIE = 0 */
    csrw sie, zero
    la t0, trap_entry
    csrw stvec, t0
    csrw satp, zero
    sfence.vma zero, zero
    fence.i

    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop
    la sp, __stack_top           /* 16-byte aligned, kernel-owned stack */

    la t0, __bss_start
    la t1, __bss_end
1:
    bgeu t0, t1, 2f
    sd zero, 0(t0)
    addi t0, t0, 8
    j 1b
2:
    /* a0/a1 still contain U-Boot's boot arguments. */
    call kernel_main
    .globl kernel_halt
kernel_halt:
    j kernel_halt               /* no dependency on SBI/WFI emulation */
    .size _start, . - _start

    .section .text.trap, "ax", @progbits
    .balign 4
    .globl trap_entry
trap_entry:
    csrci sstatus, 2
    csrr t0, scause             /* inspect t0/t1/t2 in a debugger */
    csrr t1, sepc
    csrr t2, stval
3:
    j 3b                       /* first milestone: stop on exception */

    .section .note.GNU-stack, "", @progbits
