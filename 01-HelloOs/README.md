# 01-HelloOs -- Programa de entrada y salida integrado RISC-V

Proyecto -- https://github.com/lesterbogran/mini-riscv-os/tree/master/01-HelloOs

En esta serie de artículos, presentaremos cómo construir un sistema operativo integrado en un procesador RISC-V. Este sistema operativo se llama mini-riscv-os. (En realidad, es una serie de programas en lugar de un único sistema)

Primero, en este capítulo, presentaremos cómo escribir un programa muy simple que puede imprimir ¡Hola, OS!.`Hello OS!`

## os.c

https://github.com/lesterbogran/mini-riscv-os/blob/master/01-HelloOs/os.c

```cpp
#include <stdint.h>

#define UART        0x10000000
#define UART_THR    (uint8_t*)(UART+0x00) // THR:transmitter holding register
#define UART_LSR    (uint8_t*)(UART+0x05) // LSR:line status register
#define UART_LSR_EMPTY_MASK 0x40          // LSR Bit 6: Transmitter empty; both the THR and LSR are empty

int lib_putc(char ch) {
	while ((*UART_LSR & UART_LSR_EMPTY_MASK) == 0);
	return *UART_THR = ch;
}

void lib_puts(char *s) {
	while (*s) lib_putc(*s++);
}

int os_main(void)
{
	lib_puts("Hello OS!\n");
	while (1) {}
	return 0;
}
```

La máquina virtual RISC-V predeterminada en QEMU se llama virt, y la ubicación de mapeo de memoria del UART comienza en 0x10000000. El método de mapeo es el siguiente:

```
Area de mapeo UART

0x10000000 THR (Transmitter Holding Register) tambien es RHR (Receive Holding Register)
0x10000001 IER (Interrupt Enable Register)
0x10000002 ISR (Interrupt Status Register)
0x10000003 LCR (Line Control Register)
0x10000004 MCR (Modem Control Register)
0x10000005 LSR (Line Status Register)
0x10000006 MSR (Modem Status Register)
0x10000007 SPR (Scratch Pad Register)
```

Si enviamos un carácter al registro THR del UART, podemos imprimir ese carácter, pero antes de enviarlo, debemos asegurarnos de que el sexto bit de LSR sea 1 (lo que significa que la zona de envío del UART está vacía y podemos enviar caracteres).

```
THR Bit 6: Transmitter empty; both the THR and shift register are empty if this is set.
```

Así que hemos creado la siguiente función para enviar un carácter al UART para que se imprima en la máquina host (host). (Como los sistemas integrados generalmente no tienen dispositivos de visualización, se envía de vuelta a la máquina host para su visualización):

```cpp
int lib_putc(char ch) {
	while ((*UART_LSR & UART_LSR_EMPTY_MASK) == 0);
	return *UART_THR = ch;
}
```

Después de imprimir un solo carácter, podemos usar la función lib_puts(s) para imprimir una gran cantidad de caracteres.

```cpp
void lib_puts(char *s) {
	while (*s) lib_putc(*s++);
}
```

Por lo tanto, nuestro programa principal llamó a lib_puts para imprimir `Hello OS!`.

```cpp
int os_main(void)
{
	lib_puts("Hello OS!\n");
	while (1) {}
	return 0;
}
```

Aunque nuestro programa principal tiene solo 22 líneas, el proyecto 01-HelloOs no solo incluye el programa principal, sino también el archivo de inicio start.s, el archivo de enlace os.ld y el archivo de construcción Makefile.

## Archivo Makefile

El Makefile en mini-riscv-os suele ser similar en todas partes. Aquí está el Makefile de 01-HelloOs:

```Makefile
CC = riscv64-unknown-elf-gcc
CFLAGS = -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32

QEMU = qemu-system-riscv32
QFLAGS = -nographic -smp 4 -machine virt -bios none

OBJDUMP = riscv64-unknown-elf-objdump

all: os.elf

os.elf: start.s os.c
	$(CC) $(CFLAGS) -T os.ld -o os.elf $^

qemu: $(TARGET)
	@qemu-system-riscv32 -M ? | grep virt >/dev/null || exit
	@echo "Press Ctrl-A and then X to exit QEMU"
	$(QEMU) $(QFLAGS) -kernel os.elf

clean:
	rm -f *.elf
```

Algunas de las sintaxis de Makefile no son fáciles de entender, especialmente los siguientes símbolos:

```
$@: el archivo objetivo de la regla.
$*: representa el archivo especificado por el objetivo, pero sin la extensión.
$<: el primer archivo en la lista de dependencias. (Dependencies file)
$^: todos los archivos en la lista de dependencias.
$?: la lista de archivos en la lista de dependencias que son más nuevos que el archivo objetivo.


?=: si la variable no está definida, entonces se le asigna un nuevo valor.
:=: make expande todo el Makefile y luego determina el valor de la variable.
```

Las siguientes dos líneas en el archivo Makefile mencionado anteriormente:

```Makefile
os.elf: start.s os.c
	$(CC) $(CFLAGS) -T os.ld -o os.elf $^
```

El símbolo `$^` se reemplaza por `start.s os.c`, por lo que la línea completa `$(CC) $(CFLAGS) -T os.ld -o os.elf $^` se expande en la siguiente instrucción.

```
riscv64-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -T os.ld -o os.elf start.s os.c
```

En el Makefile usamos riscv64-unknown-elf-gcc para compilar y luego usamos qemu-system-riscv32 para ejecutar. El proceso de ejecución de 01-HelloOs es el siguiente:

```
user@DESKTOP-96FRN6B MINGW64 /d/ccc109/sp/11-os/mini-riscv-os/01-HelloOs (master)
$ make clean
rm -f *.elf

user@DESKTOP-96FRN6B MINGW64 /d/ccc109/sp/11-os/mini-riscv-os/01-HelloOs (master)
$ make
riscv64-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -T os.ld -o os.elf start.s os.c

user@DESKTOP-96FRN6B MINGW64 /d/ccc109/sp/11-os/mini-riscv-os/01-HelloOs (master)
$ make qemu
Press Ctrl-A and then X to exit QEMU
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -kernel os.elf
Hello OS!
QEMU: Terminated
```

Primero se usa make clean para borrar los archivos compilados de la última vez, luego se llama a riscv64-unknown-elf-gcc mediante make para compilar el proyecto. A continuación se muestra el comando de compilación completo.

```
$ riscv64-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -T os.ld -o os.elf start.s os.c
```

Donde `-march=rv32ima` indica que deseamos generar código para el conjunto de instrucciones I+M+A de 32 bits:(https://www.sifive.com/blog/all-aboard-part-1-compiler-args)：

```
I: Conjunto de instrucciones básicas de enteros (Integer)
M: Incluye multiplicación y división (Multiply)
A: Incluye instrucciones atómicas (Atomic)
C: Usa compresión de 16 bits (Compact) -- Nota: no hemos agregado C, por lo que las instrucciones generadas son de 32 bits puros, no comprimidas a 16 bits, ya que queremos que la longitud de las instrucciones sea consistente y que todas sean de 32 bits de principio a fin.
```

La opción `-mabi=ilp32` significa que el código binario generado es para una arquitectura de 32 bits en términos de enteros.

- ilp32: int, long, and pointers are all 32-bits long. long long is a 64-bit type, char is 8-bit, and short is 16-bit.
- lp64: long and pointers are 64-bits long, while int is a 32-bit type. The other types remain the same as ilp32.

El parámetro `-mcmodel=medany` indica que la dirección de los símbolos generados debe estar dentro de los 2GB y se pueden direccionar mediante enlaces estáticos.

- `-mcmodel=medany`
    * Generate code for the medium-any code model. The program and its statically defined symbols must be within any single 2 GiB address range. Programs can be statically or dynamically linked.

Los parámetros más detallados de gcc para RISC-V se pueden encontrar en el siguiente documento:

* https://gcc.gnu.org/onlinedocs/gcc/RISC-V-Options.html

Además, se utilizan los parámetros `-nostdlib -fno-builtin` que significan que no se enlazará con la biblioteca estándar (ya que en sistemas empotrados a menudo se requiere crear su propia biblioteca) por favor consulte el siguiente documento:

* https://gcc.gnu.org/onlinedocs/gcc/Link-Options.html


## Link Script (Archivo de enlace) (os.ld)

Además, el parámetro `-T os.ld` especifica el archivo os.ld como el script de enlace: (el script de enlace es un archivo que describe cómo colocar los segmentos de programa TEXT, de datos DATA y de datos no inicializados BSS en la memoria)

```ld
OUTPUT_ARCH( "riscv" )

ENTRY( _start )

MEMORY
{
  ram   (wxa!ri) : ORIGIN = 0x80000000, LENGTH = 128M
}

PHDRS
{
  text PT_LOAD;
  data PT_LOAD;
  bss PT_LOAD;
}

SECTIONS
{
  .text : {
    PROVIDE(_text_start = .);
    *(.text.init) *(.text .text.*)
    PROVIDE(_text_end = .);
  } >ram AT>ram :text

  .rodata : {
    PROVIDE(_rodata_start = .);
    *(.rodata .rodata.*)
    PROVIDE(_rodata_end = .);
  } >ram AT>ram :text

  .data : {
    . = ALIGN(4096);
    PROVIDE(_data_start = .);
    *(.sdata .sdata.*) *(.data .data.*)
    PROVIDE(_data_end = .);
  } >ram AT>ram :data

  .bss :{
    PROVIDE(_bss_start = .);
    *(.sbss .sbss.*) *(.bss .bss.*)
    PROVIDE(_bss_end = .);
  } >ram AT>ram :bss

  PROVIDE(_memory_start = ORIGIN(ram));
  PROVIDE(_memory_end = ORIGIN(ram) + LENGTH(ram));
}
```

## Programa de arranque o inicio (start.s)

En sistemas embebidos, además del programa principal, a menudo se necesita un programa de inicio escrito en lenguaje ensamblador. El programa de inicio start.s en 01-HelloOs tiene el siguiente contenido: (principalmente para iniciar solo un núcleo en una arquitectura de múltiples núcleos, mientras que los demás núcleos duermen, lo que simplifica las cosas y no requiere considerar demasiados problemas de procesamiento paralelo).
 
```s
.equ STACK_SIZE, 8192

.global _start

_start:
    # setup stacks per hart
    csrr t0, mhartid                # read current hart id
    slli t0, t0, 10                 # shift left the hart id by 1024
    la   sp, stacks + STACK_SIZE    # set the initial stack pointer 
                                    # to the end of the stack space
    add  sp, sp, t0                 # move the current hart stack pointer
                                    # to its place in the stack space

    # park harts with id != 0
    csrr a0, mhartid                # read current hart id
    bnez a0, park                   # if we're not on the hart 0
                                    # we park the hart

    j    os_main                    # hart 0 jump to c

park:
    wfi
    j park

stacks:
    .skip STACK_SIZE * 4            # allocate space for the harts stacks

```

## Ejecutar con QEMU

Cuando escribes "make qemu", Make ejecutará las siguientes instrucciones:

```
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -kernel os.elf
```

El comando `make qemu` ejecuta la siguiente instrucción, que significa que se debe ejecutar el archivo kernel os.elf con qemu-system-riscv32. La opción `-bios none` significa que no se usará la BIOS de entrada/salida básica. La opción `-nographic` indica que no se usará el modo de gráficos. La opción `-machine virt` especifica que la arquitectura de la máquina virtual es la "virt", que es la predeterminada de QEMU para RISC-V.

Cuando escribes make qemu, ¡verás la siguiente pantalla!

```
$ make qemu
Press Ctrl-A and then X to exit QEMU
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -kernel os.elf
Hello OS!
QEMU: Terminated
```

Esta es la apariencia básica de un programa Hello World en el sistema embebido RISC-V.

## Build & Run

```sh
user@DESKTOP-96FRN6B MINGW64 /d/ccc109/sp/11-os/mini-riscv-os/01-HelloOs (master)
$ make clean
rm -f *.elf

user@DESKTOP-96FRN6B MINGW64 /d/ccc109/sp/11-os/mini-riscv-os/01-HelloOs (master)
$ make 
riscv64-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -T os.ld -o os.elf start.s os.c

user@DESKTOP-96FRN6B MINGW64 /d/ccc109/sp/11-os/mini-riscv-os/01-HelloOs (master)
$ make qemu
Press Ctrl-A and then X to exit QEMU
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -kernel os.elf
Hello OS!
```
