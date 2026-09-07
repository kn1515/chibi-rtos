#include <stdint.h>
#include "uart.h"

/* Symbols are also useful when inspecting the ELF with a debugger. */
volatile uint64_t boot_hart_id;
volatile uintptr_t boot_dtb;
volatile uint64_t boot_count;
volatile uint64_t data_cookie = 0x43484942494f5301ULL;

void kernel_main(uint64_t hart_id, uintptr_t dtb)
{
    uart_init();
    if (boot_count != 0 || data_cookie != 0x43484942494f5301ULL) {
        uart_puts("chibi-os: startup memory check failed\n");
        uart_flush();
        return;
    }

    boot_hart_id = hart_id;
    boot_dtb = dtb;
    boot_count = 1;
    uart_puts("Hello chibi-os\n");
    uart_flush();
    /* start.S parks the CPU after this function returns. */
}
