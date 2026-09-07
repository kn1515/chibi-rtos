#ifndef CHIBI_PLATFORM_H
#define CHIBI_PLATFORM_H

/* Original Milk-V Duo: CV1800B, UART0, 32-bit MMIO / register stride 4. */
#define UART0_BASE 0x04140000UL
#define UART_THR  0x00UL
#define UART_IER  0x04UL
#define UART_LSR  0x14UL
#define UART_LSR_THRE (1U << 5)
#define UART_LSR_TEMT (1U << 6)

#endif
