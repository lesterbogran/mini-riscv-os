# 05-Preemptive -- Sistema operativo integrado de RISC-V

[lib.c]: https://github.com/lesterbogran/mini-riscv-os/blob/master/05-Preemptive/lib.c
[os.c]: https://github.com/lesterbogran/mini-riscv-os/blob/master/05-Preemptive/os.c
[timer.c]: https://github.com/lesterbogran/mini-riscv-os/blob/master/05-Preemptive/timer.c
[sys.s]: https://github.com/lesterbogran/mini-riscv-os/blob/master/05-Preemptive/sys.s
[task.c]: https://github.com/lesterbogran/mini-riscv-os/blob/master/05-Preemptive/task.c
[user.c]: https://github.com/lesterbogran/mini-riscv-os/blob/master/05-Preemptive/user.c

Proyecto -- https://github.com/lesterbogran/mini-riscv-os/tree/master/05-Preemptive

En el capítulo 3, en el archivo [03-MultiTasking](03-MultiTasking.md), implementamos un sistema operativo "multitasking cooperativo". Sin embargo, debido a que no se introdujo un mecanismo de interrupción de tiempo, no puede convertirse en un sistema "multitasking preemptive" (de prioridad).

En el capítulo 4, en el archivo [04-TimerInterrupt](04-TimerInterrupt.md), demostramos el principio del mecanismo de interrupción de tiempo de RISC-V.

Finalmente, en el capítulo 5, planeamos combinar las técnicas de los dos capítulos anteriores para implementar un sistema operativo "preemptive" con interrupción de tiempo forzado. Con esto, nuestro sistema podría considerarse como un pequeño sistema operativo integrado.

## Ejecución del sistema

Primero, echemos un vistazo a la ejecución del sistema. En los resultados de ejecución a continuación, puede ver que el sistema está alternando entre OS, Task0 y Task1.

```sh
$ make qemu
Press Ctrl-A and then X to exit QEMU
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -kernel os.elf
OS start
OS: Activate next task
Task0: Created!
Task0: Running...
Task0: Running...
Task0: Running...
timer_handler: 1
OS: Back to OS

OS: Activate next task
Task1: Created!
Task1: Running...
Task1: Running...
Task1: Running...
timer_handler: 2
OS: Back to OS

OS: Activate next task
Task0: Running...
Task0: Running...
Task0: Running...
timer_handler: 3
OS: Back to OS

OS: Activate next task
Task1: Running...
Task1: Running...
Task1: Running...
timer_handler: 4
OS: Back to OS

OS: Activate next task
Task0: Running...
Task0: Running...
Task0: Running...
QEMU: Terminated
```

Esta situación es muy similar a la que se presentó en el capítulo 3, en el archivo [03-MultiTasking](03-MultiTasking.md), donde se presentó el siguiente orden de ejecución:

```
OS=>Task0=>OS=>Task1=>OS=>Task0=>OS=>Task1 ....
```

La única diferencia es que en el capítulo 3, el proceso del usuario debía devolver el control al sistema operativo de manera activa a través de `os_kernel()`, mientras que en el capítulo actual se utiliza un mecanismo de interrupción de tiempo para forzar el cambio de tareas.

```cpp
void user_task0(void)
{
	lib_puts("Task0: Created!\n");
	lib_puts("Task0: Now, return to kernel mode\n");
	os_kernel();
	while (1) {
		lib_puts("Task0: Running...\n");
		lib_delay(1000);
		os_kernel();
	}
}
```

Correcto, en el archivo [05-Preemptive](05-Preemptive.md) del capítulo actual, el proceso del usuario no necesita devolver el control al sistema operativo de manera activa. En cambio, el sistema operativo forzará la conmutación de tareas mediante la interrupción de tiempo.

```cpp
void user_task0(void)
{
	lib_puts("Task0: Created!\n");
	while (1) {
		lib_puts("Task0: Running...\n");
		lib_delay(1000);
	}
}
```

En el archivo [lib.c] hay una función llamada lib_delay, que en realidad es un bucle de retardo y no devuelve el control.

```cpp
void lib_delay(volatile int count)
{
	count *= 50000;
	while (count--);
}
```

Por el contrario, el sistema operativo recuperará el control forzosamente mediante una interrupción de tiempo. Debido a que lib_delay tiene un retardo largo, el sistema operativo normalmente interrumpirá el bucle while (count--) para recuperar el control.

## Sistema operativo [os.c]

- https://github.com/lesterbogran/mini-riscv-os/blob/master/05-Preemptive/os.c

En el archivo del sistema operativo os.c, al inicio se llama a `user_init()` para permitir que el usuario cree tareas (en este ejemplo, se crean user_task0 y user_task1 en el archivo [user.c]).

```cpp
#include "os.h"

void user_task0(void)
{
	lib_puts("Task0: Created!\n");
	while (1) {
		lib_puts("Task0: Running...\n");
		lib_delay(1000);
	}
}

void user_task1(void)
{
	lib_puts("Task1: Created!\n");
	while (1) {
		lib_puts("Task1: Running...\n");
		lib_delay(1000);
	}
}

void user_init() {
	task_create(&user_task0);
	task_create(&user_task1);
}
```

Después, el sistema operativo establece la interrupción de tiempo a través de la función `timer_init()` dentro de `os_start()`. A continuación, el programa entra en el bucle principal de `os_main()`, que utiliza el método de programación Round-Robin con una gran rueda de turno para seleccionar el siguiente task para ejecutar cada vez que se produce un cambio de contexto (si ya se ha llegado al último task, el siguiente será el primer task).

```cpp

#include "os.h"

void os_kernel() {
	task_os();
}

void os_start() {
	lib_puts("OS start\n");
	user_init();
	timer_init(); // start timer interrupt ...
}

int os_main(void)
{
	os_start();

	int current_task = 0;
	while (1) {
		lib_puts("OS: Activate next task\n");
		task_go(current_task);
		lib_puts("OS: Back to OS\n");
		current_task = (current_task + 1) % taskTop; // Round Robin Scheduling
		lib_puts("\n");
	}
	return 0;
}
```

En el mecanismo de interrupción de 05-Preemptive, modificamos la tabla de vectores de interrupción:

```cpp
.globl trap_vector
# the trap vector base address must always be aligned on a 4-byte boundary
.align 4
trap_vector:
	# save context(registers).
	csrrw	t6, mscratch, t6	# swap t6 and mscratch
        reg_save t6
	csrw	mscratch, t6
	# call the C trap handler in trap.c
	csrr	a0, mepc
	csrr	a1, mcause
	call	trap_handler

	# trap_handler will return the return address via a0.
	csrw	mepc, a0

	# load context(registers).
	csrr	t6, mscratch
	reg_load t6
	mret
```

Cuando ocurre una interrupción, la tabla de vectores de interrupción `trap_vector()` llama al `trap_handler()`:

```cpp
reg_t trap_handler(reg_t epc, reg_t cause)
{
  reg_t return_pc = epc;
  reg_t cause_code = cause & 0xfff;

  if (cause & 0x80000000)
  {
    /* Asynchronous trap - interrupt */
    switch (cause_code)
    {
    case 3:
      lib_puts("software interruption!\n");
      break;
    case 7:
      lib_puts("timer interruption!\n");
      // disable machine-mode timer interrupts.
      w_mie(~((~r_mie()) | (1 << 7)));
      timer_handler();
      return_pc = (reg_t)&os_kernel;
      // enable machine-mode timer interrupts.
      w_mie(r_mie() | MIE_MTIE);
      break;
    case 11:
      lib_puts("external interruption!\n");
      break;
    default:
      lib_puts("unknown async exception!\n");
      break;
    }
  }
  else
  {
    /* Synchronous trap - exception */
    lib_puts("Sync exceptions!\n");
    while (1)
    {
      /* code */
    }
  }
  return return_pc;
}
```

Una vez que se salta a `trap_handler()`, ésta llamará a diferentes manejadores según el tipo de interrupción, por lo que podemos considerarla como una estación intermedia de distribución de tareas de interrupción.

```
                         +----------------+
                         | soft_handler() |
                 +-------+----------------+
                 |
+----------------+-------+-----------------+
| trap_handler() |       | timer_handler() |
+----------------+       +-----------------+
                 |
                 +-------+-----------------+
                         | exter_handler() |
                         +-----------------+
```

trap_handler puede asignar el manejo de interrupciones a diferentes controladores según el tipo de interrupción, lo que puede mejorar en gran medida la capacidad de expansión del sistema operativo.

```cpp
#include "timer.h"

// a scratch area per CPU for machine-mode timer interrupts.
reg_t timer_scratch[NCPU][5];

#define interval 20000000 // cycles; about 2 second in qemu.

void timer_init()
{
  // each CPU has a separate source of timer interrupts.
  int id = r_mhartid();

  // ask the CLINT for a timer interrupt.
  // int interval = 1000000; // cycles; about 1/10th second in qemu.

  *(reg_t *)CLINT_MTIMECMP(id) = *(reg_t *)CLINT_MTIME + interval;

  // prepare information in scratch[] for timervec.
  // scratch[0..2] : space for timervec to save registers.
  // scratch[3] : address of CLINT MTIMECMP register.
  // scratch[4] : desired interval (in cycles) between timer interrupts.
  reg_t *scratch = &timer_scratch[id][0];
  scratch[3] = CLINT_MTIMECMP(id);
  scratch[4] = interval;
  w_mscratch((reg_t)scratch);

  // enable machine-mode timer interrupts.
  w_mie(r_mie() | MIE_MTIE);
}

static int timer_count = 0;

void timer_handler()
{
  lib_printf("timer_handler: %d\n", ++timer_count);
  int id = r_mhartid();
  *(reg_t *)CLINT_MTIMECMP(id) = *(reg_t *)CLINT_MTIME + interval;
}

```

Al ver el `timer_handler()` en el archivo [timer.c], se puede observar que realiza la acción de reiniciar `MTIMECMP`.

```cpp
/* In trap_handler() */
// ...
case 7:
      lib_puts("timer interruption!\n");
      // disable machine-mode timer interrupts.
      w_mie(~((~r_mie()) | (1 << 7)));
      timer_handler();
      return_pc = (reg_t)&os_kernel;
      // enable machine-mode timer interrupts.
      w_mie(r_mie() | MIE_MTIE);
      break;
// ...
```

- Para evitar situaciones de anidamiento de interrupciones con Timer Interrupt, antes de manejar una interrupción, trap_handler() desactiva la interrupción de tiempo (timer interrupt) y la reactiva después de que se complete el manejo.
- Después de que se complete la ejecución de `timer_handler()`, `trap_handler()` apuntará `mepc` a `os_kernel()`, logrando así la función de cambio de tarea. En otras palabras, si la interrupción no es un Timer Interrupt, el contador de programa saltará de vuelta al estado antes de la interrupción, y este paso está definido en `trap_vector()`.

```assembly=
csrr	a0, mepc # a0 => arg1 (return_pc) of trap_handler()
```

> **Complemento**
> En RISC-V, los argumentos de una función se almacenan primero en los registros a0-a7. Si no hay suficientes registros disponibles, entonces se almacenan en la pila (stack).
> Entre ellos, los registros de a0 y a1 también se utilizan como valores de retorno de la función.

Finalmente, recuerda llevar a cabo la inicialización de trap y timer durante el arranque del kernel:

```cpp
void os_start()
{
	lib_puts("OS start\n");
	user_init();
	trap_init();
	timer_init(); // start timer interrupt ...
}
```

A través de la interrupción de tiempo forzamos la recuperación del control, de modo que no tenemos que preocuparnos de que algún proceso malintencionado controle la CPU y haga que el sistema se paralice. Este es el mecanismo de gestión de procesos más importante en los sistemas operativos modernos.

Aunque mini-riscv-os es solo un sistema operativo integrado en miniatura, demuestra los principios de diseño de un "sistema operativo preemptivo" con un código relativamente conciso.

Por supuesto, el camino hacia el aprendizaje del "diseño de sistemas operativos" aún es largo. Mini-riscv-os no tiene "sistema de archivos" y todavía no he aprendido cómo controlar y cambiar entre el modo super y el modo usuario en RISC-V, ni he introducido el mecanismo de memoria virtual de RISC-V. Por lo tanto, el código de este capítulo todavía solo utiliza el modo máquina, lo que significa que no puede proporcionar un mecanismo completo de "permisos y protección".

Afortunadamente, alguien ya ha hecho estas cosas. Puede aprender más sobre estos mecanismos más complejos a través de xv6-riscv, un sistema operativo didáctico diseñado por MIT. El código fuente de xv6-riscv tiene más de ocho mil líneas en total, lo cual no es demasiado en comparación con los sistemas Linux / Windows que tienen entre varios millones y decenas de millones de líneas de código. Por lo tanto, xv6-riscv es un sistema muy conciso.

- https://github.com/mit-pdos/xv6-riscv

Sin embargo, xv6-riscv originalmente solo se podía compilar y ejecutar en Linux, pero modifiqué el archivo mkfs/mkfs.c para que pudiera compilar y ejecutarse en un entorno similar al de mini-riscv-os en Windows con Git Bash.

Puede obtener el código fuente de xv6-riscv para Windows en la siguiente dirección web y luego compilarlo y ejecutarlo para ver si puede aprender principios de diseño de sistemas operativos más avanzados a través de xv6-riscv, sobre la base de lo que aprendió con mini-riscv-os.

- https://github.com/cccriscv/xv6-riscv-win

A continuación se proporcionan más recursos de aprendizaje sobre RISC-V, para facilitar el proceso de aprendizaje del diseño del sistema operativo RISC-V, y así evitar tener que pasar por muchas dificultades y pruebas.

- [AwesomeCS Wiki](https://github.com/ianchen0119/AwesomeCS/wiki)
- [Step by step, learn to develop an operating system on RISC-V](https://github.com/plctlab/riscv-operating-system-mooc)
- [RISC-V 手册 - 一本开源指令集的指南 (PDF)](http://crva.ict.ac.cn/documents/RISC-V-Reader-Chinese-v2p1.pdf)
- [The RISC-V Instruction Set Manual Volume II: Privileged Architecture Privileged Architecture (PDF)](https://riscv.org//wp-content/uploads/2019/12/riscv-spec-20191213.pdf)
- [RISC-V Assembly Programmer's Manual](https://github.com/riscv/riscv-asm-manual/blob/master/riscv-asm.md)
- https://github.com/riscv/riscv-opcodes
  - https://github.com/riscv/riscv-opcodes/blob/master/opcodes-rv32i
- [SiFive Interrupt Cookbook (SiFive 的 RISC-V 中斷手冊)](https://gitlab.com/ccc109/sp/-/blob/master/10-riscv/mybook/riscv-interrupt/sifive-interrupt-cookbook-zh.md)
- [SiFive Interrupt Cookbook -- Version 1.0 (PDF)](https://sifive.cdn.prismic.io/sifive/0d163928-2128-42be-a75a-464df65e04e0_sifive-interrupt-cookbook.pdf)
- Avanzado [proposal for a RISC-V Core-Local Interrupt Controller (CLIC)](https://github.com/riscv/riscv-fast-interrupt/blob/master/clic.adoc)

Espero que este material de enseñanza de mini-riscv-os pueda ayudar a los lectores a ahorrar algo de tiempo en el aprendizaje del diseño de RISC-V OS.

Chen Zhongcheng, 15 de noviembre de 2020, Universidad de Kinmen.
