# 09-MemoryAllocator -- Sistema Operativo Integrado RISC-V

## Conocimientos previos: Escritura de scripts de Linker

Escribir un script de enlace permite al compilador colocar cada sección en la dirección de memoria de la instrucción de acuerdo con nuestras ideas durante la etapa de enlace.

![](https://camo.githubusercontent.com/1d58b18d5a293fe858931e54cce54ac53f4e86b08da25de332a16434688e7434/68747470733a2f2f692e696d6775722e636f6d2f756f72425063642e706e67)

Tome la figura anterior como ejemplo. Cuando se ejecuta el programa del sistema, cada segmento se colocará en la memoria. En cuanto a qué segmentos asignar, los atributos de cada segmento (legible, escribible y ejecutable) deben configurarse utilizando Linker Script ¡Cuéntale al compilador!

### Enseñanza de gramática: Puntos de entrada y estructura

Ver `os.ld` de este proyecto, que es el Linker Script de mini-riscv-os:

```
OUTPUT_ARCH( "riscv" )

ENTRY( _start )

MEMORY
{
  ram   (wxa!ri) : ORIGIN = 0x80000000, LENGTH = 128M
}
```

Observando el script anterior, se pueden sacar varias conclusiones:

- El ejecutable de salida se ejecutará en la plataforma `riscv`
- El punto de entrada del programa es `_start`
- El nombre de la memoria es `ram`, y sus propiedades son:
  - [x] W (writable) (escribible)
  - [x] X (executable) (ejecutable)
  - [x] A (assignable) (assembly)
  - [ ] R (read only) (solo lectura)
  - [ ] I (initialization) (inicialización)
- El punto de partida de la memoria es 0x80000000 y la longitud es de 128 MB, es decir el rango de memoria es: 0x08000000 - 0x88000000.

Luego, se puede ver que el script de enlace (Linker Script) divide varios segmentos en la sección SECTION, que son los siguientes:

- .text
- .rodata
- .data
- .bss

Tomemos como ejemplo uno de estos segmentos para explicar el script:

```
.text : {
    PROVIDE(_text_start = .);
    *(.text.init) *(.text .text.*)
    PROVIDE(_text_end = .);
  } >ram AT>ram :text
```

- `PROVIDE` puede ayudarnos a definir símbolos, que también representan una dirección de memoria
- `*(.text.init) *(.text .text.*)` nos ayuda a hacer coincidir la sección .text en cualquier archivo de objeto.
- `>ram AT>ram :text`

  - ram es VMA (Virtual Memory Address) (dirección de memoria virtual), cuando el programa se está ejecutando, la sección obtendrá esta dirección de memoria.
  - ram: text es LMA (Load Memory Address)(Dirección de memoria de carga), cuando se carga esta sección, se colocará en esta dirección de memoria.

Finalmente, el Linker Script también define los símbolos de inicio y finalización, así como la ubicación del Heap:

  ```
  PROVIDE(_memory_start = ORIGIN(ram));
  PROVIDE(_memory_end = ORIGIN(ram) + LENGTH(ram));

  PROVIDE(_heap_start = _bss_end);
  PROVIDE(_heap_size = _memory_end - _heap_start);
  ```

Si se representa mediante una imagen, la distribución de la memoria es la siguiente:

![](https://camo.githubusercontent.com/6a28844c8d691f8cad5b7b6bcd39ea72a453f4634674dc360fc02da30397f2f5/68747470733a2f2f692e696d6775722e636f6d2f4e434a3342674c2e706e67)

## Vamos al punto

### ¿Qué es el Heap (montón)?

El Heap mencionado en este artículo no es lo mismo que el Heap en estructuras de datos. En este caso, Heap se refiere al espacio de memoria disponible para que el sistema operativo y los procesos lo asignen. Todos sabemos que la pila (Stack) almacena datos de longitud fija que ya han sido inicializados. En comparación con la pila, el Heap es más flexible, ya que podemos asignar la cantidad de espacio que necesitamos y luego recuperarlo después de su uso para evitar desperdiciar memoria.

```cpp
#include <stdlib.h>
int *p = (int*) malloc(sizeof(int));
// ...
free(p);
```

El ejemplo en lenguaje C anterior utiliza `malloc()` para asignar memoria dinámicamente, y llama a `free()` después de su uso para liberar la memoria asignada.

### Implementación en mini-riscv-os 

Después de comprender la estructura de memoria descrita por Heap y Linker Script, ¡ahora podemos entrar en el punto clave de este artículo!
En esta sección, hemos reservado un espacio específico para ser utilizado por el Heap, lo que nos permite implementar una funcionalidad similar a la de un Memory Allocator en nuestro programa del sistema.

```assembly
.section .rodata
.global HEAP_START
HEAP_START: .word _heap_start

.global HEAP_SIZE
HEAP_SIZE: .word _heap_size

.global TEXT_START
TEXT_START: .word _text_start

.global TEXT_END
TEXT_END: .word _text_end

.global DATA_START
DATA_START: .word _data_start

.global DATA_END
DATA_END: .word _data_end

.global RODATA_START
RODATA_START: .word _rodata_start

.global RODATA_END
RODATA_END: .word _rodata_end

.global BSS_START
BSS_START: .word _bss_start

.global BSS_END
BSS_END: .word _bss_end
```

En mem.s, declaramos varias variables, cada una representando los símbolos definidos previamente en el Linker Script. De esta manera, podemos acceder a estas direcciones de memoria en nuestro programa en C.

```cpp
extern uint32_t TEXT_START;
extern uint32_t TEXT_END;
extern uint32_t DATA_START;
extern uint32_t DATA_END;
extern uint32_t RODATA_START;
extern uint32_t RODATA_END;
extern uint32_t BSS_START;
extern uint32_t BSS_END;
extern uint32_t HEAP_START;
extern uint32_t HEAP_SIZE;
```

### Cómo administrar bloques de memoria

De hecho, en los sistemas operativos populares, la estructura del Heap es muy compleja y hay varias listas para administrar bloques de memoria no asignados, así como bloques de memoria asignados de diferentes tamaños.

```cpp
static uint32_t _alloc_start = 0;
static uint32_t _alloc_end = 0;
static uint32_t _num_pages = 0;

#define PAGE_SIZE 256
#define PAGE_ORDER 8
```

En mini-riscv-os, hemos estandarizado el tamaño del bloque en 25b bits, lo que significa que cuando llamamos a `malloc(sizeof(int))`, asigna 256 bits de espacio para esta solicitud.

```cpp
void page_init()
{
  _num_pages = (HEAP_SIZE / PAGE_SIZE) - 2048;
  lib_printf("HEAP_START = %x, HEAP_SIZE = %x, num of pages = %d\n", HEAP_START, HEAP_SIZE, _num_pages);

  struct Page *page = (struct Page *)HEAP_START;
  for (int i = 0; i < _num_pages; i++)
  {
    _clear(page);
    page++;
  }

  _alloc_start = _align_page(HEAP_START + 2048 * PAGE_SIZE);
  _alloc_end = _alloc_start + (PAGE_SIZE * _num_pages);

  lib_printf("TEXT:   0x%x -> 0x%x\n", TEXT_START, TEXT_END);
  lib_printf("RODATA: 0x%x -> 0x%x\n", RODATA_START, RODATA_END);
  lib_printf("DATA:   0x%x -> 0x%x\n", DATA_START, DATA_END);
  lib_printf("BSS:    0x%x -> 0x%x\n", BSS_START, BSS_END);
  lib_printf("HEAP:   0x%x -> 0x%x\n", _alloc_start, _alloc_end);
}
```

En `page_init()`, podemos ver que si hay N bloques de memoria de 256 bits disponibles para asignar, necesitamos implementar una estructura de datos para administrar el estado de los bloques de memoria.

```cpp
struct Page
{
  uint8_t flags;
};
```

Por lo tanto, la memoria Heap se utilizará para almacenar: N estructuras de página y N bloques de memoria de 256 bits, lo que presenta una relación uno a uno. 
En cuanto a cómo distinguir si el bloque de memoria A ha sido asignado, depende de lo que se haya registrado en la bandera del Page Struct correspondiente a él:

- 00: Esto significa que esta página no ha sido asignada
- 01: Esto significa que esta página fue asignada
- 11: Esto significa que esta página fue asignada y es la última página del bloque de memoria asignado

Los estados `00` y `01` son muy fáciles de entender, ¿pero en qué situaciones se usa el estado `11`? Sigamos leyendo:

```cpp
void *malloc(size_t size)
{
  int npages = pageNum(size);
  int found = 0;
  struct Page *page_i = (struct Page *)HEAP_START;
  for (int i = 0; i < (_num_pages - npages); i++)
  {
    if (_is_free(page_i))
    {
      found = 1;

      /*
			 * meet a free page, continue to check if following
			 * (npages - 1) pages are also unallocated.
			 */

      struct Page *page_j = page_i;
      for (int j = i; j < (i + npages); j++)
      {
        if (!_is_free(page_j))
        {
          found = 0;
          break;
        }
        page_j++;
      }
      /*
			 * get a memory block which is good enough for us,
			 * take housekeeping, then return the actual start
			 * address of the first page of this memory block
			 */
      if (found)
      {
        struct Page *page_k = page_i;
        for (int k = i; k < (i + npages); k++)
        {
          _set_flag(page_k, PAGE_TAKEN);
          page_k++;
        }
        page_k--;
        _set_flag(page_k, PAGE_LAST);
        return (void *)(_alloc_start + i * PAGE_SIZE);
      }
    }
    page_i++;
  }
  return NULL;
}
```

Al leer el código fuente de `malloc()`, podemos saber que cuando el usuario intenta obtener un espacio de memoria mayor a 256 bits, primero calculará cuántos bloques de memoria se necesitan para satisfacer la solicitud. Después de completar el cálculo, buscará bloques de memoria contiguos y no asignados en los que pueda dividir la solicitud.

```
malloc(513);
Cause 513 Bits > The size of the 2 blocks,
thus, malloc will allocates 3 blocks for the request.

Before Allocation:

+----+    +----+    +----+    +----+    +----+
| 00 | -> | 00 | -> | 00 | -> | 00 | -> | 00 |
+----+    +----+    +----+    +----+    +----+

After Allocation:

+----+    +----+    +----+    +----+    +----+
| 01 | -> | 01 | -> | 11 | -> | 00 | -> | 00 |
+----+    +----+    +----+    +----+    +----+

```

Una vez asignado, podemos ver que el último bloque de memoria asignado tiene una bandera de 11. De esta manera, cuando el usuario llame a free() para liberar esta memoria, el sistema puede verificar mediante la bandera que el bloque con la marca 11 es el último bloque que debe ser liberado

## Reference

- [10 分鐘讀懂 linker scripts](https://blog.louie.lu/2016/11/06/10%E5%88%86%E9%90%98%E8%AE%80%E6%87%82-linker-scripts/)
- [Step by step, learn to develop an operating system on RISC-V](https://github.com/plctlab/riscv-operating-system-mooc)
- [Heap Exploitation](https://github.com/ianchen0119/About-Security/wiki/Heap-Exploitation)


## Build & Run

```sh
IAN@DESKTOP-9AEMEPL MINGW64 ~/Desktop/mini-riscv-os/09-MemoryAllocator (feat/memoryAlloc)
$ make all
rm -f *.elf *.img
riscv64-unknown-elf-gcc -I./include -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -g -Wall -w -T os.ld -o os.elf src/start.s src/sys.s src/mem.s src/lib.c src/timer.c src/task.c src/os.c src/user.c src/trap.c src/lock.c src/plic.c src/virtio.c src/string.c src/alloc.c
Press Ctrl-A and then X to exit QEMU
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -drive if=none,format=raw,file=hdd.dsk,id=x0 -device virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0 -kernel os.elf
HEAP_START = 8001100c, HEAP_SIZE = 07feeff4, num of pages = 521967
TEXT:   0x80000000 -> 0x8000ac78
RODATA: 0x8000ac78 -> 0x8000b09f
DATA:   0x8000c000 -> 0x8000c004
BSS:    0x8000d000 -> 0x8001100c
HEAP:   0x80091100 -> 0x88000000
OS start
Disk init work is success!
buffer init...
block read...
Virtio IRQ
000000fd
000000af
000000f8
000000ab
00000088
00000042
000000cc
00000017
00000022
0000008e

p = 0x80091700
p2 = 0x80091300
p3 = 0x80091100
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
