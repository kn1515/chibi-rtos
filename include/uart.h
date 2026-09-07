#ifndef CHIBI_UART_H
#define CHIBI_UART_H

void uart_init(void);
void uart_puts(const char *text);
void uart_flush(void);

#endif
