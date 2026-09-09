#ifndef CHIBI_PLATFORM_H
#define CHIBI_PLATFORM_H

/* QEMU virt: NS16550 UART, 8-bit MMIO / register stride 1. */
#define UART_MMIO_WIDTH 1
#define UART0_BASE 0x10000000UL
#define UART_THR  0x00UL
#define UART_IER  0x01UL
#define UART_LSR  0x05UL
#define UART_LSR_THRE (1U << 5)
#define UART_LSR_TEMT (1U << 6)

#endif
