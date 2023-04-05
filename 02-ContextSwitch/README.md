# 02-ContextSwitch -- Cambio de contexto en RISC-V

Proyecto -- https://github.com/ccc-c/mini-riscv-os/tree/master/02-ContextSwitch

En el capítulo anterior [01-HelloOs](01-HelloOs.md), presentamos cómo imprimir cadenas en el puerto serie UART en la arquitectura RISC-V. En este capítulo, avanzaremos hacia el sistema operativo y presentaremos la técnica misteriosa del "cambio de contexto" (Context-Switch).

## os.c

Aquí está el código principal de 02-ContextSwitch, llamado os.c. Además del propio sistema operativo (OS), el programa también tiene una "tarea" (task):

* https://github.com/ccc-c/mini-riscv-os/blob/master/02-ContextSwitch/os.c

```cpp
#include "os.h"

#define STACK_SIZE 1024
uint8_t task0_stack[STACK_SIZE];
struct context ctx_os;
struct context ctx_task;

extern void sys_switch();

void user_task0(void)
{
	lib_puts("Task0: Context Switch Success !\n");
	while (1) {} // stop here.
}

int os_main(void)
{
	lib_puts("OS start\n");
	ctx_task.ra = (reg_t) user_task0;
	ctx_task.sp = (reg_t) &task0_stack[STACK_SIZE-1];
	sys_switch(&ctx_os, &ctx_task);
	return 0;
}
```

La tarea (task) es una función, en el archivo os.c anterior, se llama user_task0. Para realizar el cambio de contexto, establecemos ctx_task.ra como user_task0. Dado que ra es el registro de almacenamiento temporal de la dirección de retorno (return address), su función es reemplazar el contador de programa (pc) con ra al ejecutar la instrucción ret, de manera que la instrucción ret salte a la función indicada en ra para su ejecución.

```cpp
	ctx_task.ra = (reg_t) user_task0;
	ctx_task.sp = (reg_t) &task0_stack[STACK_SIZE-1];
	sys_switch(&ctx_os, &ctx_task);
```

Sin embargo, cada tarea debe tener un espacio de pila para poder realizar llamadas a funciones en un entorno de lenguaje C. Por lo tanto, asignamos un espacio de pila para task0 y utilizamos ctx_task.sp para apuntar al inicio de la pila.

Luego, llamamos a `sys_switch(&ctx_os, &ctx_task)` para cambiar desde el programa principal a task0. La función sys_switch se encuentra en [sys.s](https://github.com/ccc-c/mini-riscv-os/blob/master/02-ContextSwitch/sys.s) y es una función en lenguaje ensamblador. Su contenido es el siguiente:

```s
# Context switch
#
#   void sys_switch(struct context *old, struct context *new);
# 
# Save current registers in old. Load from new.

.globl sys_switch
.align 4
sys_switch:
        ctx_save a0  # a0 => struct context *old
        ctx_load a1  # a1 => struct context *new
        ret          # pc=ra; swtch to new task (new->ra)
```

En RISC-V, los parámetros se almacenan principalmente en los registros temporales a0, a1, ..., a7. Solo cuando los parámetros superan los ocho, se pasan por la pila.

La función en lenguaje C correspondiente a sys_switch es la siguiente:

```cpp
void sys_switch(struct context *old, struct context *new);
```

En el código anterior, a0 corresponde a old (el contexto de la tarea anterior) y a1 corresponde a new (el contexto de la nueva tarea). La función sys_switch tiene la función de almacenar el contexto de la tarea anterior y luego cargar el contexto de la nueva tarea para comenzar a ejecutarla.

El último ret es muy importante, ya que cuando se carga el contexto de la nueva tarea, también se carga el registro ra. Por lo tanto, cuando se ejecuta el ret, el valor de pc se establece en ra y se salta a la nueva tarea (por ejemplo, `void user_task0(void)` ) para comenzar a ejecutarla.

`ctx_save` y `ctx_load` son dos macros de lenguaje ensamblador que se utilizan en sys_switch. Se definen de la siguiente manera:

```s
# ============ MACRO ==================
.macro ctx_save base
        sw ra, 0(\base)
        sw sp, 4(\base)
        sw s0, 8(\base)
        sw s1, 12(\base)
        sw s2, 16(\base)
        sw s3, 20(\base)
        sw s4, 24(\base)
        sw s5, 28(\base)
        sw s6, 32(\base)
        sw s7, 36(\base)
        sw s8, 40(\base)
        sw s9, 44(\base)
        sw s10, 48(\base)
        sw s11, 52(\base)
.endm

.macro ctx_load base
        lw ra, 0(\base)
        lw sp, 4(\base)
        lw s0, 8(\base)
        lw s1, 12(\base)
        lw s2, 16(\base)
        lw s3, 20(\base)
        lw s4, 24(\base)
        lw s5, 28(\base)
        lw s6, 32(\base)
        lw s7, 36(\base)
        lw s8, 40(\base)
        lw s9, 44(\base)
        lw s10, 48(\base)
        lw s11, 52(\base)
.endm
# ============ Macro END   ==================
```

Durante el cambio de contexto en RISC-V, es necesario guardar los registros temporales como ra, sp, s0 a s11, etc. El código anterior básicamente lo copié de xv6, un sistema operativo de enseñanza, y lo modifiqué para la versión de 32 bits de RISC-V. La dirección web original del código fuente es la siguiente:

* https://github.com/mit-pdos/xv6-riscv/blob/riscv/kernel/swtch.S

En el archivo de cabecera [riscv.h](https://github.com/ccc-c/mini-riscv-os/blob/master/02-ContextSwitch/riscv.h), definimos la estructura struct context en lenguaje C, que se ve así:

```cpp
// Saved registers for kernel context switches.
struct context {
  reg_t ra;
  reg_t sp;

  // callee-saved
  reg_t s0;
  reg_t s1;
  reg_t s2;
  reg_t s3;
  reg_t s4;
  reg_t s5;
  reg_t s6;
  reg_t s7;
  reg_t s8;
  reg_t s9;
  reg_t s10;
  reg_t s11;
};
```

De esta manera, hemos cubierto los detalles del cambio de contexto "Context Switching", por lo que el siguiente programa principal puede cambiar sin problemas de `os_main` a `user_task0`

```cpp
int os_main(void)
{
	lib_puts("OS start\n");
	ctx_task.ra = (reg_t) user_task0;
	ctx_task.sp = (reg_t) &task0_stack[STACK_SIZE-1];
	sys_switch(&ctx_os, &ctx_task);
	return 0;
}
```

Los siguientes son los resultados de ejecución de todo el proyecto:

```sh
user@DESKTOP-96FRN6B MINGW64 /d/ccc109/sp/11-os/mini-riscv-os/03-ContextSwitch (master)    
$ make 
riscv64-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -T os.ld -o os.elf start.s sys.s lib.c os.c

user@DESKTOP-96FRN6B MINGW64 /d/ccc109/sp/11-os/mini-riscv-os/03-ContextSwitch (master)    
$ make qemu
Press Ctrl-A and then X to exit QEMU
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -kernel os.elf
OS start
Task0: Context Switch Success !
QEMU: Terminated
```

¡Lo anterior es el método de implementación del mecanismo "Context-Switch" en RISC-V!
