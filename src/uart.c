#include <stdint.h>
#include "platform.h"
#include "uart.h"

static uint32_t read_reg(unsigned long offset)
{
    uint32_t value = *(volatile uint32_t *)(UART0_BASE + offset);
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    return value;
}

static void write_reg(unsigned long offset, uint32_t value)
{
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    *(volatile uint32_t *)(UART0_BASE + offset) = value;
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
}

void uart_init(void)
{
    /* U-Boot leaves UART0 at 115200 8N1 with DLAB clear.
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
