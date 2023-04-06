# 04-TimerInterrupt -- Interrupción de tiempo de RISC-V

[os.c]: https://github.com/lesterbogran/mini-riscv-os/blob/master/04-TimerInterrupt/os.c
[timer.c]: https://github.com/lesterbogran/mini-riscv-os/blob/master/04-TimerInterrupt/timer.c
[sys.s]: https://github.com/lesterbogran/mini-riscv-os/blob/master/04-TimerInterrupt/sys.s

Proyecto -- https://github.com/lesterbogran/mini-riscv-os/tree/master/04-TimerInterrupt

En el capítulo anterior, [03-MultiTasking](03-MultiTasking.md), implementamos un sistema operativo de multitarea cooperativo. Sin embargo, debido a la falta de un mecanismo de interrupción de tiempo, no puede convertirse en un sistema de multitarea preemptivo(Preemptive).

Este capítulo allanará el camino para el Capítulo 5, que se enfocará en un sistema de multitarea preemptivo. Aquí, se presentará cómo utilizar el mecanismo de interrupción de tiempo en el procesador RISC-V. Con la interrupción de tiempo, podemos recuperar el control forzadamente en intervalos regulares sin temor a que un proceso malicioso retenga el control del sistema y se niegue a cederlo al sistema operativo.

## Conocimientos previos necesarios

Antes de aprender cómo implementar un mecanismo de interrupción de tiempo en un sistema, es necesario entender algunas cosas primero:

- Cómo generar una interrupción de tiempo (Timer interrupt)
- ¿Qué es la tabla de vectores de interrupción?
- Registro de estado y control (CSR)

### Cómo generar una interrupción de tiempo (Timer interrupt)

La arquitectura RISC-V establece que toda plataforma de sistema debe tener un temporizador. Además, este temporizador debe tener dos registros temporales de 64 bits, llamados mtime y mtimecmp. El primero se utiliza para registrar el valor actual del temporizador, mientras que el segundo se utiliza para comparar con el valor de mtime. Cuando el valor de mtime es mayor que el valor de mtimecmp, se genera una interrupción.
Estos dos registros también están definidos en el archivo [riscv.h](https://github.com/lesterbogran/mini-riscv-os/blob/master/04-TimerInterrupt/riscv.h):

```cpp
// ================== Timer Interrput ====================

#define NCPU 8             // maximum number of CPUs
#define CLINT 0x2000000
#define CLINT_MTIMECMP(hartid) (CLINT + 0x4000 + 4*(hartid))
#define CLINT_MTIME (CLINT + 0xBFF8) // cycles since boot.
```

Después de entender cómo generar una interrupción de temporizador, más adelante en este artículo encontraremos un fragmento de código que describe el intervalo de tiempo entre cada interrupción.

Además, también necesitamos habilitar las interrupciones de temporizador durante la inicialización del sistema. La forma específica de hacerlo es estableciendo el bit correspondiente a las interrupciones de temporizador en el registro `mie` en 1.

### ¿Qué es la tabla de vectores de interrupción?

La tabla de vectores de interrupción es una tabla mantenida por el programa del sistema en la que podemos colocar el correspondiente Interrupt_Handler. De esta manera, cuando se produce una interrupción de tiempo, el sistema entrará en el Interrupt_Handler y, después de que se complete el procesamiento de interrupciones y excepciones, volverá a la dirección de la instrucción original para continuar la ejecución.

> Complemento:
> Cuando ocurre una excepción o una interrupción, el procesador detiene el trabajo actual y apunta la dirección del contador de programa (Program counter) a la dirección apuntada por mtvec para comenzar la ejecución. Este comportamiento es como si se hubiera caído en una trampa (trap), por lo que en la arquitectura RISC-V se define esta acción como "Trap". En el sistema operativo xv6 (risc-v), también podemos encontrar una serie de operaciones para manejar las interrupciones en el código fuente del kernel (en su mayoría definido en Trap.c).

### CSR

La arquitectura RISC-V define muchos registros, algunos de los cuales se definen como registros de control y estado, es decir, CSR (Control and status registers), que se utilizan para configurar o registrar el estado de funcionamiento del procesador.

- CSR
  - mtvec: Cuando se produce una excepción, el contador de programa (PC) se dirige a la dirección apuntada por mtvec y continúa la ejecución desde allí.
  - mcause: registra la causa de la excepción.
  - mtval: registra el mensaje de la excepción.
  - mepc: es la dirección a la que el contador de programa (PC) apuntaba antes de entrar en la excepción. Si el manejo de la excepción se completa, el contador de programa puede leer esa dirección y continuar la ejecución desde allí.
  - mstatus: El registro mstatus se actualiza con ciertos valores de campo cuando se produce una excepción en el procesador RISC-V.
  - mie determina si se procesa o no una interrupción.
  - mip refleja el estado de espera de diferentes tipos de interrupciones
- Memory Address Mapped
  - mtime: registra el valor del temporizador
  - mtimecmp: almacenar el valor de comparación del temporizador
  - msip: Generar o terminar una interrupción de software.
  - PLIC: Platform-Level Interrupt Controller

Además, RISC-V define una serie de instrucciones que permiten a los desarrolladores operar con los registros CSR.

- csrs
Establecer en 1 el bit especificado en el registro CSR.

```assembly=
csrsi mstatus, (1 << 2)
```

Correcto, esta instrucción establecerá el tercer bit a partir del bit menos significativo (LSB) en 1 en el registro mstatus.

- csrc
  Establecer el bit especificado en 0 en el registro CSR.

```assembly=
csrsi mstatus, (1 << 2)
```

Correcto, esa instrucción establecerá el tercer bit desde LSB en 0 en el registro mstatus.

- csrr[c|s]
  Cargar el valor del CSR en un registro general.

```assembly=
csrr to, mscratch
```

- csrw
  Escribir el valor del registro general en el CSR

```assembly=
csrw	mepc, a0
```

- csrrw[i]
  Escribir el valor de csr en rd y al mismo tiempo escribir el valor de rs1 en csr

```assembly=
csrrw rd, csr, rs1/imm
```

Mirándolo desde otra perspectiva:

```assembly=
csrrw t6, mscratch, t6
```

La operación anterior permite intercambiar los valores de t6 y mscratch.

## Ejecución del sistema

Primero, demos una muestra del estado de ejecución del sistema. Después de construir el proyecto en la carpeta 04-TimerInterrupt utilizando comandos como "make clean" y "make", puedes ejecutarlo utilizando "make qemu". El resultado es el siguiente:

```
$ make
riscv64-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -T os.ld -o os.elf start.s sys.s lib.c timer.c os.c
$ make qemu
Press Ctrl-A and then X to exit QEMU
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -kernel os.elf
OS start
timer_handler: 1
timer_handler: 2
timer_handler: 3
timer_handler: 4
timer_handler: 5
timer_handler: 6
$ make clean
rm -f *.elf
$ make
riscv64-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -T os.ld -o os.elf start.s sys.s lib.c timer.c os.c
$ make qemu
Press Ctrl-A and then X to exit QEMU
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -kernel os.elf
OS start
timer_handler: 1
timer_handler: 2
timer_handler: 3
timer_handler: 4
timer_handler: 5
timer_handler: 6
timer_handler: 7
timer_handler: 8
timer_handler: 9
```

El sistema imprimirá el mensaje `timer_handler: i` aproximadamente una vez por segundo de manera estable, lo que indica que el mecanismo de interrupción de tiempo se ha iniciado con éxito y que se están produciendo interrupciones periódicas.

## Programa principal [os.c]

Antes de explicar la interrupción de tiempo, echemos un vistazo al contenido del programa principal del sistema operativo [os.c].

```cpp
#include "os.h"

int os_main(void)
{
	lib_puts("OS start\n");
	timer_init(); // start timer interrupt ...
	while (1) {} // os : do nothing, just loop!
	return 0;
}
```

La función principal del programa básicamente imprime `OS start`, inicia la interrupción del temporizador y luego entra en el bucle infinito de la función os_loop().

¿Pero por qué el sistema seguirá imprimiendo mensajes como `timer_handler: i` después de eso?

```
timer_handler: 1
timer_handler: 2
timer_handler: 3
```

¡Esto, por supuesto, es causado por el mecanismo de interrupción del tiempo!

Miremos el contenido de [timer.c], preste especial atención a la línea `w_mtvec((reg_t)sys_timer)`, cuando ocurra la interrupción de tiempo, el programa saltará al lenguaje ensamblador sys_timer en [sys.s ] función.

```cpp
#include "timer.h"

#define interval 10000000 // cycles; about 1 second in qemu.

void timer_init()
{
  // each CPU has a separate source of timer interrupts.
  int id = r_mhartid();

  // ask the CLINT for a timer interrupt.
  *(reg_t*)CLINT_MTIMECMP(id) = *(reg_t*)CLINT_MTIME + interval;

  // set the machine-mode trap handler.
  w_mtvec((reg_t)sys_timer);

  // enable machine-mode interrupts.
  w_mstatus(r_mstatus() | MSTATUS_MIE);

  // enable machine-mode timer interrupts.
  w_mie(r_mie() | MIE_MTIE);
}
```

Y en la función `sys_timer` en [sys.s], se utiliza la instrucción privilegiada `csrr` para almacenar temporalmente la dirección del punto de interrupción en el registro de privilegios `mepc` y guardarlo en `a0`. Después de que se ejecute `timer_handler()`, se puede volver al punto de interrupción a través de `mret`.

```s
sys_timer:
	# call the C timer_handler(reg_t epc, reg_t cause)
	csrr	a0, mepc
	csrr	a1, mcause
	call	timer_handler

	# timer_handler will return the return address via a0.
	csrw	mepc, a0

	mret # back to interrupt location (pc=mepc)
```

En este caso, el lector debe primero comprender el mecanismo de interrupción de RISC-V. Básicamente, RISC-V tiene tres modos de ejecución: modo máquina (machine mode), modo super (super mode) y modo usuario (user mode)

Todos los ejemplos de mini-riscv-os en este libro se ejecutan en modo máquina (machine mode) y no utilizan el modo super (super mode) o el modo usuario (user mode).

MEPC es utilizado en modo máquina (machine mode) y cuando se produce una interrupción, el hardware automáticamente ejecuta la acción de asignar el valor de PC a MEPC.

Cuando sys_timer ejecuta la instrucción MRET en modo supervisor (super mode), el hardware ejecuta la acción de asignar el valor de MEPC a PC, lo que permite que el programa salte de regreso al punto de interrupción original y continúe su ejecución, como si nada hubiera pasado.

Hasta aquí hemos proporcionado una explicación general del mecanismo de interrupción de RISC-V. Sin embargo, para comprender en detalle el proceso, es necesario entender los registros privilegiados del modo máquina (machine mode) del procesador RISC-V, como mhartid (ID del núcleo del procesador), mstatus (registro de estado) y mie (registro de interrupción), entre otros.

```cpp
#define interval 10000000 // cycles; about 1 second in qemu.

void timer_init()
{
  // each CPU has a separate source of timer interrupts.
  int id = r_mhartid();

  // ask the CLINT for a timer interrupt.
  *(reg_t*)CLINT_MTIMECMP(id) = *(reg_t*)CLINT_MTIME + interval;

  // set the machine-mode trap handler.
  w_mtvec((reg_t)sys_timer);

  // enable machine-mode interrupts.
  w_mstatus(r_mstatus() | MSTATUS_MIE);

  // enable machine-mode timer interrupts.
  w_mie(r_mie() | MIE_MTIE);
}
```

Además, también es necesario comprender las áreas de mapeo de memoria virt en la máquina virtual QEMU de RISC-V, como CLINT_MTIME, CLINT_MTIMECMP, entre otras.

El mecanismo de interrupción de tiempo de RISC-V implica comparar los valores de dos registros, CLINT_MTIME y CLINT_MTIMECMP. Cuando el valor de CLINT_MTIME supera al valor de CLINT_MTIMECMP, se produce una interrupción de tiempo.

Por lo tanto, la función timer_init() contiene las siguientes instrucciones:

```cpp
 *(reg_t*)CLINT_MTIMECMP(id) = *(reg_t*)CLINT_MTIME + interval;
```

Estas instrucciones se utilizan para establecer el primer momento de interrupción.

De manera similar, en la función timer_handler del archivo [timer.c], también se debe establecer el próximo momento de interrupción:

```cpp
reg_t timer_handler(reg_t epc, reg_t cause)
{
  reg_t return_pc = epc;
  // disable machine-mode timer interrupts.
  w_mie(~((~r_mie()) | (1 << 7)));
  lib_printf("timer_handler: %d\n", ++timer_count);
  int id = r_mhartid();
  *(reg_t *)CLINT_MTIMECMP(id) = *(reg_t *)CLINT_MTIME + interval;
  // enable machine-mode timer interrupts.
  w_mie(r_mie() | MIE_MTIE);
  return return_pc;
}
```

De esta manera, cuando se llegue al siguiente valor de CLINT_MTIMECMP, CLINT_MTIME superará a CLINT_MTIMECMP y se producirá otra interrupción.

Esto es todo en cuanto al mecanismo de interrupción de tiempo del procesador RISC-V en la máquina virtual virt.


## Build & Run

```
$ make
riscv64-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -T os.ld -o os.elf start.s sys.s lib.c timer.c os.c
$ make qemu
Press Ctrl-A and then X to exit QEMU
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -kernel os.elf        
OS start
timer_handler: 1
timer_handler: 2
timer_handler: 3
timer_handler: 4
timer_handler: 5
QEMU: Terminated
```
