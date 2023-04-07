# 06-Spinlock -- Sistema operativo integrado de RISC-V

## Introducción a Spinlock

Spinlock se puede traducir como bloqueo de giro, y podemos adivinar aproximadamente la función de Spinlock a través del nombre. Al igual que Mutex, Spinlock se puede usar para proteger la sección crítica.Si el subproceso de ejecución no adquiere el bloqueo, entrará en un bucle hasta que sea elegible para el bloqueo, por lo que se denomina bloqueo de giro.

### Operación atómica

Las operaciones atómicas garantizan que una operación no sea interrumpida por otras antes de completarse. Tomando como ejemplo RISC-V, este proporciona el conjunto de instrucciones RV32A, el cual consiste en operaciones atómicas.

![](https://img2018.cnblogs.com/blog/361409/201810/361409-20181029191919995-84497985.png)

Para evitar que múltiples Spinlocks accedan a la misma memoria al mismo tiempo, la implementación de Spinlocks utiliza operaciones atómicas para asegurar un bloqueo correcto.

> De hecho, no solo los Spinlocks, sino que también las cerraduras de exclusión mutua requieren operaciones atómicas en su implementación.

### Crear un Spinlock simple utilizando el lenguaje de programación C.

Considera el siguiente código:

```cpp
typedef struct spinlock{
    volatile uint lock;
} spinlock_t;
void lock(spinlock_t *lock){
    while(xchg(lock−>lock, 1) != 0);
}
void unlock(spinlock_t *lock){
    lock->lock = 0;
}
```

A través del código de ejemplo, se pueden observar varios puntos:

- La palabra clave volatile en lock. 
  El uso de la palabra clave volatile permite al compilador saber que la variable puede ser accedida en situaciones impredecibles, por lo que no se deben optimizar las instrucciones que involucran la variable para evitar almacenar los resultados en un registro, sino escribirlos directamente en la memoria.
- Función lock.
  [`xchg(a,b)`](https://zh.m.wikibooks.org/zh-hant/X86%E7%B5%84%E5%90%88%E8%AA%9E%E8%A8%80/%E5%9F%BA%E6%9C%AC%E6%8C%87%E4%BB%A4%E9%9B%86/IA32%E6%8C%87%E4%BB%A4:xchg) 可以將 a, b 兩個變數的內容對調，並且該函式為原子操作，當 lock 值不為 0 時，執行緒便會不停的自旋等待，直到 lock 為 0 (也就是可供上鎖)為止。
- Función unlock.
  Debido a que solo un hilo puede adquirir el bloqueo al mismo tiempo, no hay problema de acceso concurrente al liberarlo. Debido a esto, el ejemplo no utiliza operaciones atómicas.

## Spinlock en mini-riscv-os.

### basic lock

En primer lugar, como mini-riscv-os es un sistema operativo Single hart, aparte de utilizar operaciones atómicas, en realidad hay una forma muy simple de lograr el efecto de bloqueo:

```cpp
void basic_lock()
{
  w_mstatus(r_mstatus() & ~MSTATUS_MIE);
}

void basic_unlock()
{
  w_mstatus(r_mstatus() | MSTATUS_MIE);
}
```

En [lock.c], hemos implementado un bloqueo muy simple. Cuando llamamos a `basic_lock()` en el programa, se desactiva el mecanismo de interrupción del modo de máquina del sistema. De esta manera, podemos asegurarnos de que ningún otro programa acceda a la memoria compartida, evitando que se produzca una condición de carrera.

### spinlock

El bloqueo anterior tiene una clara deficiencia: **si el programa que adquiere el bloqueo nunca lo libera, todo el sistema se bloqueará**, para garantizar que el sistema operativo aún pueda mantener su mecanismo multitarea, debemos implementar bloqueos más complejos:

- [os.h]
- [lock.c]
- [sys.s]

```cpp
typedef struct lock
{
  volatile int locked;
} lock_t;

void lock_init(lock_t *lock)
{
  lock->locked = 0;
}

void lock_acquire(lock_t *lock)
{
  for (;;)
  {
    if (!atomic_swap(lock))
    {
      break;
    }
  }
}

void lock_free(lock_t *lock)
{
  lock->locked = 0;
}
```

De hecho, el código anterior es básicamente igual que el ejemplo de Spinlock presentado anteriormente. Cuando lo implementamos en el sistema, solo necesitamos lidiar con un problema más complicado, que es implementar la operación de intercambio atómico `atomic_swap()`.

```assembly=
.globl atomic_swap
.align 4
atomic_swap:
        li a5, 1
        amoswap.w.aq a5, a5, 0(a0)
        mv a0, a5
        ret
```

En el programa anterior, leemos el valor de "locked" en la estructura de bloqueo, lo intercambiamos con el valor `1` y finalmente devolvemos el contenido del registro `a5`.

Al resumir el resultado de la ejecución del programa, podemos obtener dos casos:

1. Éxito en la obtención del bloqueo:
Cuando `lock->locked` es `0`, después del intercambio realizado por `amoswap.w.aq`, el valor de `lock->locked` se convierte en `1` y el valor de retorno (Valor de `a5`) es `0`:

```cpp
void lock_acquire(lock_t *lock)
{
  for (;;)
  {
    if (!atomic_swap(lock))
    {
      break;
    }
  }
}
```
Cuando el valor de retorno es `0`, `lock_acquire()` saldrá del bucle infinito y entrará en la sección crítica para su ejecución. 

2. Falla al obtener el bloqueo, por lo tanto, sigue intentando obtener el bloqueo en un bucle infinito.


## Lectura adicional

Si estás interesado en `Race Condition`, `Critical sections`, `Mutex`, puedes leer la sección de Programación Concurrente en [AwesomeCS Wiki](https://github.com/ianchen0119/AwesomeCS/wiki).

## Build & Run

```sh
IAN@DESKTOP-9AEMEPL MINGW64 ~/Desktop/mini-riscv-os/06-Spinlock (feat/spinlock)
$ make
riscv64-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -g -Wall -T os.ld -o os.elf start.s sys.s lib.c timer.c task.c os.c user.c trap.c lock.c

IAN@DESKTOP-9AEMEPL MINGW64 ~/Desktop/mini-riscv-os/06-Spinlock (feat/spinlock)
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
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
timer interruption!
timer_handler: 1
OS: Back to OS

OS: Activate next task
Task1: Created!
Task1: Running...
Task1: Running...
Task1: Running...
Task1: Running...
Task1: Running...
Task1: Running...
Task1: Running...
Task1: Running...
Task1: Running...
Task1: Running...
Task1: Running...
Task1: Running...
Task1: Running...
Task1: Running...
timer interruption!
timer_handler: 2
OS: Back to OS

OS: Activate next task
Task2: Created!
The value of shared_var is: 550
The value of shared_var is: 600
The value of shared_var is: 650
The value of shared_var is: 700
The value of shared_var is: 750
The value of shared_var is: 800
The value of shared_var is: 850
The value of shared_var is: 900
The value of shared_var is: 950
The value of shared_var is: 1000
The value of shared_var is: 1050
The value of shared_var is: 1100
The value of shared_var is: 1150
The value of shared_var is: 1200
The value of shared_var is: 1250
The value of shared_var is: 1300
The value of shared_var is: 1350
The value of shared_var is: 1400
The value of shared_var is: 1450
The value of shared_var is: 1500
The value of shared_var is: 1550
The value of shared_var is: 1600
timer interruption!
timer_handler: 3
OS: Back to OS

OS: Activate next task
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
timer interruption!
timer_handler: 4
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

You can set the breakpoint in any c file:

```sh
(gdb) b trap.c:27
Breakpoint 2 at 0x80008f78: file trap.c, line 27.
(gdb)
```

As the example above, when process running on trap.c, line 27 (Timer Interrupt).
The process will be suspended automatically until you press the key `c` (continue) or `s` (step).
