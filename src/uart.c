#include <stdint.h>
#include "platform.h"
#include "uart.h"

#if UART_MMIO_WIDTH == 4
typedef uint32_t uart_reg_t;
#elif UART_MMIO_WIDTH == 1
typedef uint8_t uart_reg_t;
#else
#error Unsupported UART access width
#endif

static uint32_t read_reg(unsigned long offset)
{
    uint32_t value = *(volatile uart_reg_t *)(UART0_BASE + offset);
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    return value;
}

static void write_reg(unsigned long offset, uint32_t value)
{
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    *(volatile uart_reg_t *)(UART0_BASE + offset) = (uart_reg_t)value;
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
}

void uart_init(void)
{
    /* The boot firmware (U-Boot on Duo, OpenSBI on QEMU virt)
     * leaves the console UART initialized with DLAB clear.
     * Retain its clock, pinmux, baud divisor and FIFO configuration.
     * This kernel uses polling, so UART interrupts are not needed. */
    write_reg(UART_IER, 0);
}

static void uart_putc(char c)
{
    while ((read_reg(UART_LSR) & UART_LSR_THRE) == 0) {
    }
    write_reg(UART_THR, (uint32_t)(unsigned char)c);
}

void uart_puts(const char *text)
{
    while (*text != '\0') {
        if (*text == '\n') {
            uart_putc('\r');
        }
        uart_putc(*text++);
    }
}

void uart_flush(void)
{
    while ((read_reg(UART_LSR) & UART_LSR_TEMT) == 0) {
    }
}
