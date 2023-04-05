# 03-MultiTasking -- Multitarea cooperativa en RISC-V

[os.c]:https://github.com/lesterbogran/mini-riscv-os/blob/master/03-MultiTasking/os.c

[task.c]:https://github.com/lesterbogran/mini-riscv-os/blob/master/03-MultiTasking/task.c

[user.c]:https://github.com/lesterbogran/mini-riscv-os/blob/master/03-MultiTasking/user.c

[sys.s]:https://github.com/lesterbogran/mini-riscv-os/blob/master/03-MultiTasking/sys.s

Proyecto -- https://github.com/lesterbogran/mini-riscv-os/tree/master/03-MultiTasking

En el capítulo anterior, [02-ContextSwitch](02-ContextSwitch.md), presentamos el mecanismo de cambio de contexto en la arquitectura RISC-V. En este capítulo, entraremos en el mundo de los procesos múltiples y explicaremos cómo escribir un sistema operativo "multitarea cooperativa".


## Multitarea cooperativa

Los sistemas operativos modernos tienen una función (Preemptive) que utiliza interrupciones de tiempo para detener los procesos de manera forzada. Esto permite interrumpir un proceso que esté acaparando demasiado tiempo de CPU y cambiarlo por otro proceso para que pueda ser ejecutado.

En los sistemas sin mecanismos de interrupción de tiempo, el sistema operativo no puede interrumpir un proceso abusivo. Por lo tanto, se debe confiar en que cada proceso ceda el control al sistema operativo de manera voluntaria, para permitir que todos los procesos tengan la oportunidad de ejecutarse.

Este tipo de sistema multitarea que depende del mecanismo de entrega voluntaria de control se llama sistema de multitarea cooperativa (Cooperative Multitasking).

Tanto el sistema operativo Windows 3.1 lanzado por Microsoft en 1991, como el sistema [HeliOS](https://github.com/MannyPeterson/HeliOS) en la placa única de Arduino, utilizan el mecanismo de multitarea cooperativa.

En este capítulo, diseñaremos un sistema operativo de multitarea cooperativa en un procesador RISC-V.

Primero, echemos un vistazo al resultado de la ejecución del sistema.

```sh
$ make qemu
Press Ctrl-A and then X to exit QEMU
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -kernel os.elf
OS start
OS: Activate next task
Task0: Created!
Task0: Now, return to kernel mode
OS: Back to OS

OS: Activate next task
Task1: Created!
Task1: Now, return to kernel mode
OS: Back to OS

OS: Activate next task
Task0: Running...
OS: Back to OS

OS: Activate next task
Task1: Running...
OS: Back to OS

OS: Activate next task
Task0: Running...
OS: Back to OS

OS: Activate next task
Task1: Running...
OS: Back to OS

OS: Activate next task
Task0: Running...
OS: Back to OS

OS: Activate next task
Task1: Running...
OS: Back to OS

OS: Activate next task
Task0: Running...
QEMU: Terminated
```

Usted puede ver que el sistema cambia constantemente entre dos tareas, Task0 y Task1, pero en realidad el proceso de cambio es el siguiente:

```
OS=>Task0=>OS=>Task1=>OS=>Task0=>OS=>Task1 ....
```

## Tarea del usuario (User task) [user.c]

En [user.c], definimos dos tareas, user_task0 y user_task1, y las inicializamos en la función user_init.

* https://github.com/lesterbogran/mini-riscv-os/blob/master/03-MultiTasking/user.c

```cpp
#include "os.h"

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

void user_task1(void)
{
	lib_puts("Task1: Created!\n");
	lib_puts("Task1: Now, return to kernel mode\n");
	os_kernel();
	while (1) {
		lib_puts("Task1: Running...\n");
		lib_delay(1000);
		os_kernel();
	}
}

void user_init() {
	task_create(&user_task0);
	task_create(&user_task1);
}
```

## Programa principal [os.c]

Luego, en el programa principal del sistema operativo, os.c, usamos un gran bucle para planificar la ejecución de cada proceso en orden de rotación.

* https://github.com/lesterbogran/mini-riscv-os/blob/master/03-MultiTasking/os.c

```cpp
#include "os.h"

void os_kernel() {
	task_os();
}

void os_start() {
	lib_puts("OS start\n");
	user_init();
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

El método de planificación descrito anteriormente es, en principio, consistente con el [Round Robin Scheduling](https://en.wikipedia.org/wiki/Round-robin_scheduling), pero el Round Robin Scheduling generalmente debe ser utilizado en conjunto con un mecanismo de interrupción de tiempo. Dado que el código de este capítulo no tiene un mecanismo de interrupción de tiempo, solo se puede considerar una versión de Round Robin Scheduling de multitarea cooperativa.

La multitarea cooperativa depende de que cada tarea ceda voluntariamente el control, como en el caso de user_task0, donde cada vez que se llama a la función os_kernel(), se invoca el mecanismo de cambio de contexto para ceder el control al sistema operativo [os.c].

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

La función os_kernel() de [os.c] llama a task_os() de [task.c].

```cpp
void os_kernel() {
	task_os();
}
```

La función os_kernel() en [os.c] llamará a task_os() en [task.c], mientras que task_os() llamará a sys_switch en [sys.s] para cambiar al modo kernel del sistema operativo.

```cpp
// switch back to os
void task_os() {
	struct context *ctx = ctx_now;
	ctx_now = &ctx_os;
	sys_switch(ctx, &ctx_os);
}
```

Entonces, todo el sistema funciona en cooperación entre os_main(), user_task0(), y user_task1(), alternando entre ellos de manera intercambiable y mutuamente respetuosa.

[os.c]

```cpp
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

[user.c]

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

void user_task1(void)
{
	lib_puts("Task1: Created!\n");
	lib_puts("Task1: Now, return to kernel mode\n");
	os_kernel();
	while (1) {
		lib_puts("Task1: Running...\n");
		lib_delay(1000);
		os_kernel();
	}
}
```

¡Ese es un ejemplo específico y detallado de un sistema operativo cooperativo multitarea en el procesador RISC-V!

## Build & Run

```sh
user@DESKTOP-96FRN6B MINGW64 /d/ccc109/sp/11-os/mini-riscv-os/03-MultiTasking 
(master)
$ make clean
rm -f *.elf

user@DESKTOP-96FRN6B MINGW64 /d/ccc109/sp/11-os/mini-riscv-os/03-MultiTasking 
(master)
$ make
riscv64-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima 
-mabi=ilp32 -T os.ld -o os.elf start.s sys.s lib.c task.c os.c user.c

user@DESKTOP-96FRN6B MINGW64 /d/ccc109/sp/11-os/mini-riscv-os/03-MultiTasking 
(master)
$ make qemu
Press Ctrl-A and then X to exit QEMU
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -kernel os.elf
OS start
OS: Activate next task
Task0: Created!
Task0: Now, return to kernel mode
OS: Back to OS

OS: Activate next task
Task1: Created!
Task1: Now, return to kernel mode
OS: Back to OS

OS: Activate next task
Task0: Running...
OS: Back to OS

OS: Activate next task
Task1: Running...
OS: Back to OS

OS: Activate next task
Task0: Running...
OS: Back to OS

OS: Activate next task
Task1: Running...
OS: Back to OS

OS: Activate next task
Task0: Running...
OS: Back to OS

OS: Activate next task
Task1: Running...
OS: Back to OS

OS: Activate next task
Task0: Running...
QEMU: Terminated
```
