#include <stdint.h>

#define UART        0x10000000            // La máquina virtual virt de RISC-V tiene la dirección base de mapeo del UART en 0x10000000.
#define UART_THR    (uint8_t*)(UART+0x00) // THR: transmitter holding register
#define UART_RHR    (uint8_t*)(UART+0x00) // RHR: receiving holding register 
#define UART_LSR    (uint8_t*)(UART+0x05) // LSR: line status register 
#define UART_LSR_RX_READY 0x01            // Hay entrada esperando ser leída desde RHR.
#define UART_LSR_EMPTY_MASK 0x40          // LSR Bit 6: Cuando el sexto bit de LSR es 1, significa que el área de transmisión está vacía y puede ser usada para transmitir.

void lib_putc(char ch) {  // Este código está enviando el carácter 'ch' a través del UART para que se imprima en la máquina anfitriona.
	while ((*UART_LSR & UART_LSR_EMPTY_MASK) == 0); // El código está esperando a que el LSR del UART indique que el registro de transmisión está vacío para poder enviar el carácter.
	*UART_THR = ch; // El carácter ch es enviado.
}

void lib_puts(char *s) { // Imprimir una cadena en la máquina anfitriona.
	while (*s) lib_putc(*s++);
}

char lib_getc() {
	while ((*UART_LSR & UART_LSR_RX_READY) == 0); // Espera continuamente hasta que el UART reciba datos (RX_READY).
	return *UART_RHR; // Devuelve el carácter recibido
}

int lib_gets(char *s) {
	char *p = s;
	while (1) {
		char ch = lib_getc();
		lib_putc(ch);
		if (ch == '\n' || ch == '\r') break;
		*p++ = ch;
	}
	*p = '\0';
	return p-s;
}

int os_main(void)
{
	lib_puts("type something:");
	char str[100];
	lib_gets(str);
	lib_puts("\r\nyou type:");
	lib_puts(str);
	lib_puts("\r\n");
	while (1) {} // ¡Hacer que el programa principal se quede aquí, detenido en un bucle infinito!
	return 0;
}
