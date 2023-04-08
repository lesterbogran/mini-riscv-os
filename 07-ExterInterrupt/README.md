# 07-ExterInterrupt -- Sistema operativo embebido de RISC-V

## Prerequisitos

### PIC

PIC (Controlador Programable de Interrupciones) es un circuito de propósito especial que ayuda al procesador a manejar solicitudes de interrupción que ocurren simultáneamente desde diferentes fuentes. Ayuda a determinar la prioridad de las IRQ y permite que la CPU cambie al procedimiento de manejo de interrupción más adecuado.

### Interrupt

Primero, revisemos los tipos de interrupciones de RISC-V, que se pueden subdividir en varias categorías:

- Local Interrupt
  - Software Interrupt
  - Timer Interrupt
- Global Interrupt
  - External Interrupt

Cada código de excepción (Exception code) de los diferentes tipos de interrupciones también tiene una definición detallada en el libro de especificaciones:

![](https://camo.githubusercontent.com/9f3e34c3f929a4b693a1c198586e0a67c78f8e3d42773fafde0746355196030d/68747470733a2f2f692e696d6775722e636f6d2f7a6d756b6e51722e706e67)

> El código de excepción (Exception code) se registra en el registro mcause

Si queremos que los programas del sistema que se ejecutan en RISC-V admitan el manejo de interrupciones, también necesitamos configurar el valor del campo del registro MIE:

```cpp
// Machine-mode Interrupt Enable
#define MIE_MEIE (1 << 11) // external
#define MIE_MTIE (1 << 7)  // timer
#define MIE_MSIE (1 << 3)  // software
// enable machine-mode timer interrupts.
w_mie(r_mie() | MIE_MTIE);
```

### PLIC

Después de revisar brevemente el manejo de interrupciones presentado anteriormente, volvamos al punto principal de este artículo y veamos **PLIC**
PLIC (Controlador de Interrupciones a Nivel de Plataforma) es el PIC diseñado para la plataforma RISC-V
En realidad, habrá varias fuentes de interrupción (teclado, ratón, disco duro, etc.) conectadas al PLIC, el cual determinará la prioridad de estas interrupciones y las asignará al Hart (la unidad mínima de hardware de subprocesos en RISC-V) del procesador para su manejo.

### IRQ

> En ciencias de la computación, una interrupción se refiere a una señal recibida por el procesador desde el hardware o el software que indica la ocurrencia de algún evento que requiere atención, esta situación se llama interrupción. Por lo general, al recibir señales asíncronas del hardware periférico o señales sincrónicas del software, el procesador realizará el procesamiento correspondiente de hardware/software. Emitir tales señales se llama solicitud de interrupción (IRQ). -- Wikipedia

En el caso de la máquina virtual RISC-V - Virt en Qemu, su [código fuente](https://github.com/qemu/qemu/blob/master/include/hw/riscv/virt.h) define las IRQ de diferentes interrupciones.

```cpp
enum {
    UART0_IRQ = 10,
    RTC_IRQ = 11,
    VIRTIO_IRQ = 1, /* 1 to 8 */
    VIRTIO_COUNT = 8,
    PCIE_IRQ = 0x20, /* 32 to 35 */
    VIRTIO_NDEV = 0x35 /* Arbitrary maximum number of interrupts */
};
```

Cuando escribimos un sistema operativo, podemos utilizar los códigos IRQ para identificar el tipo de interrupción externa, como la entrada del teclado o la lectura/escritura del disco. En cuanto a estos temas, el autor profundizará en futuros artículos.

### El mapa de memoria(memory map) de PLIC.

¿Cómo podemos comunicarnos con el PLIC?
PLIC utiliza el mecanismo de Memory Map, mapeando información importante en la memoria principal. De esta manera, podemos comunicarnos con PLIC accediendo a la memoria.
Podemos seguir viendo el [código fuente de Virt](https://github.com/qemu/qemu/blob/master/hw/riscv/virt.c) en Qemu, que define la ubicación virtual de PLIC:

```cpp
static const MemMapEntry virt_memmap[] = {
    [VIRT_DEBUG] =       {        0x0,         0x100 },
    [VIRT_MROM] =        {     0x1000,        0xf000 },
    [VIRT_TEST] =        {   0x100000,        0x1000 },
    [VIRT_RTC] =         {   0x101000,        0x1000 },
    [VIRT_CLINT] =       {  0x2000000,       0x10000 },
    [VIRT_PCIE_PIO] =    {  0x3000000,       0x10000 },
    [VIRT_PLIC] =        {  0xc000000, VIRT_PLIC_SIZE(VIRT_CPUS_MAX * 2) },
    [VIRT_UART0] =       { 0x10000000,         0x100 },
    [VIRT_VIRTIO] =      { 0x10001000,        0x1000 },
    [VIRT_FW_CFG] =      { 0x10100000,          0x18 },
    [VIRT_FLASH] =       { 0x20000000,     0x4000000 },
    [VIRT_PCIE_ECAM] =   { 0x30000000,    0x10000000 },
    [VIRT_PCIE_MMIO] =   { 0x40000000,    0x40000000 },
    [VIRT_DRAM] =        { 0x80000000,           0x0 },
};
```

Cada fuente de interrupción de PLIC está representada por un registro, al agregar `offset`, que es el desplazamiento del registro, a `PLIC_BASE`, podemos conocer la ubicación de ese registro en la memoria principal mapeada por PLIC.

```
0xc000000 (PLIC_BASE) + offset = Mapped Address of register
```

## Empecemos por la tarea de habilitar las interrupciones externas en mini-riscv-os.

Primero, al ver `plic_init()`, este archivo está definido en `plic.c`:

```cpp
void plic_init()
{
  int hart = r_tp();
  // QEMU Virt machine support 7 priority (1 - 7),
  // The "0" is reserved, and the lowest priority is "1".
  *(uint32_t *)PLIC_PRIORITY(UART0_IRQ) = 1;

  /* Enable UART0 */
  *(uint32_t *)PLIC_MENABLE(hart) = (1 << UART0_IRQ);

  /* Set priority threshold for UART0. */

  *(uint32_t *)PLIC_MTHRESHOLD(hart) = 0;

  /* enable machine-mode external interrupts. */
  w_mie(r_mie() | MIE_MEIE);

  // enable machine-mode interrupts.
  w_mstatus(r_mstatus() | MSTATUS_MIE);
}
```

Al ver el ejemplo anterior, `plic_init()` realiza principalmente estas operaciones de inicialización:

- Configurar la prioridad de UART_IRQ. 
  Debido a que el PLIC puede gestionar múltiples fuentes de interrupción externas, debemos establecer el orden de prioridad para diferentes fuentes de interrupción. Cuando estas fuentes de interrupción entren en conflicto, el PLIC sabrá cuál IRQ debe procesar primero.
- Activar la interrupción UART para hart0
- Establecer el umbral(threshold)
  Los IRQs que estén por debajo o igual que este valor de umbral serán ignorados por el PLIC. Si modificamos el ejemplo a:

```cpp
*(uint32_t *)PLIC_MTHRESHOLD(hart) = 10;
```

Así, el sistema ya no manejará la IRQ de UART.

- ctivar las interrupciones externas y las interrupciones globales en modo máquina (Machine mode)
  Cabe señalar que en este proyecto, la interrupción global en modo Máquina se habilitó originalmente en `trap_init()` Después de esta modificación, hemos cambiado `plic_init()` para que sea responsable.

> Además de PLIC debe inicializarse, UART también debe inicializarse, como configurar **velocidad en baudios (baud rate)** y otras acciones, `uart_init()` se define en `lib.c`, los lectores interesados ​​pueden consultarlo mediante ellos mismos.

### Modificar el controlador de excepciones (Trap Handler)

```
                         +-----------------+
                         | soft_handler()  |
                 +-------+-----------------+
                 |
+----------------+       +-----------------+
| trap_handler() +-------+ timer_handler() |
+----------------+       +-----------------+
                 |
                 +-------+-----------------+
                         | exter_handler() |
                         +-----------------+
```

Anteriormente, `trap_handler()` solo admitía el procesamiento de interrupciones de tiempo, esta vez queremos que admita el procesamiento de interrupciones externas:

```cpp
/* In trap.c */
void external_handler()
{
  int irq = plic_claim();
  if (irq == UART0_IRQ)
  {
    lib_isr();
  }
  else if (irq)
  {
    lib_printf("unexpected interrupt irq = %d\n", irq);
  }

  if (irq)
  {
    plic_complete(irq);
  }
}
```

Debido a que el objetivo esta vez es permitir que el sistema operativo maneje UART IRQ, no es difícil encontrar a través del código anterior que solo manejamos UART:

```cpp
/* In lib.c */
void lib_isr(void)
{
    for (;;)
    {
        int c = lib_getc();
        if (c == -1)
        {
            break;
        }
        else
        {
            lib_putc((char)c);
            lib_putc('\n');
        }
    }
}
```

El principio de `lib_isr()` también es bastante simple, solo detecta repetidamente si el registro RHR del UART ha recibido nuevos datos, y si está vacío (c == -1), saltará fuera del bucle.

> Los registros relacionados con UART se definen en `riscv.h`. Esta vez, se agregan algunas direcciones de registro para admitir `lib_getc()`. El contenido general es el siguiente:
>
> ```cpp
> #define UART 0x10000000L
> #define UART_THR (volatile uint8_t *)(UART + 0x00) // THR:transmitter holding register
> #define UART_RHR (volatile uint8_t *)(UART + 0x00) // RHR:Receive holding register
> #define UART_DLL (volatile uint8_t *)(UART + 0x00) // LSB of Divisor Latch (write mode)
> #define UART_DLM (volatile uint8_t *)(UART + 0x01) // MSB of Divisor Latch (write mode)
> #define UART_IER (volatile uint8_t *)(UART + 0x01) // Interrupt Enable Register
> #define UART_LCR (volatile uint8_t *)(UART + 0x03) // Line Control Register
> #define UART_LSR (volatile uint8_t *)(UART + 0x05) // LSR:line status register
> #define UART_LSR_EMPTY_MASK 0x40                   // LSR Bit 6: Transmitter empty; both the THR and LSR are empty
> ```

Este es el contenido general de las modificaciones realizadas en esta entrega. Hay algunos detalles de implementación que no se mencionan aquí, por lo que se recomienda a los lectores interesados que inspeccionen directamente el código fuente para obtener más información.
Con estas bases, en el futuro se pueden agregar características como:

- virtio driver & file system
- system call
- mini shell
  y otras funciones, haciendo que `mini-riscv-os` sea más escalable.

## Reference

- [Step by step, learn to develop an operating system on RISC-V](https://github.com/plctlab/riscv-operating-system-mooc)
- [Qemu](https://github.com/qemu/qemu)
- [AwesomeCS wiki](https://github.com/ianchen0119/AwesomeCS/wiki/2-5-RISC-V::%E4%B8%AD%E6%96%B7%E8%88%87%E7%95%B0%E5%B8%B8%E8%99%95%E7%90%86----PLIC-%E4%BB%8B%E7%B4%B9)


## Build & Run

```sh
IAN@DESKTOP-9AEMEPL MINGW64 ~/Desktop/mini-riscv-os/07-ExterInterrupt (feat/getchar)
$ make
riscv64-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -g -Wall -T os.ld -o os.elf start.s sys.s lib.c timer.c task.c os.c user.c trap.c lock.c plic.c

IAN@DESKTOP-9AEMEPL MINGW64 ~/Desktop/mini-riscv-os/07-ExterInterrupt (feat/getchar)
$ make qemu
Press Ctrl-A and then X to exit QEMU
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -kernel os.elf
OS start
OS: Activate next task
Task0: Created!
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
external interruption!
j
Task0: Running...
Task0: Running...
external interruption!
k
Task0: Running...
Task0: Running...
Task0: Running...
external interruption!
j
Task0: Running...
external interruption!
k
external interruption!
j
Task0: Running...
timer interruption!
timer_handler: 1
OS: Back to OS
QEMU: Terminated
```

## Debug mode

```sh
make debug
riscv64-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -g -Wall -T os.ld -o os.elf start.s sys.s lib.c timer.c task.c os.c user.c trap.c lock.c
Press Ctrl-C and then input 'quit' to exit GDB and QEMU
-------------------------------------------------------
Reading symbols from os.elf...
Breakpoint 1 at 0x80000000: file start.s, line 7.
0x00001000 in ?? ()
=> 0x00001000:  97 02 00 00     auipc   t0,0x0

Thread 1 hit Breakpoint 1, _start () at start.s:7
7           csrr t0, mhartid                # read current hart id
=> 0x80000000 <_start+0>:       f3 22 40 f1     csrr    t0,mhartid
(gdb)
```

### set the breakpoint

Puede establecer el punto de interrupción en cualquier archivo c:

```sh
(gdb) b trap.c:27
Breakpoint 2 at 0x80008f78: file trap.c, line 27.
(gdb)
```

Como en el ejemplo anterior, cuando el proceso se ejecuta en trap.c, línea 27 (Interrupción del temporizador).
El proceso se suspenderá automáticamente hasta que presione la tecla `c` (continuar) o `s` (paso).
