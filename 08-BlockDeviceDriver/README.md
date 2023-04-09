# 08-BlockDeviceDriver -- Sistema operativo integrado RISC-V

Después de implementar el mecanismo de interrupción externa, agregamos el UART ISR en el Lab anterior. Para que el sistema operativo lea los datos del disco, debemos agregar el VirtIO ISR:

```cpp
void external_handler()
{
  int irq = plic_claim();
  if (irq == UART0_IRQ)
  {
    lib_isr();
  }
  else if (irq == VIRTIO_IRQ)
  {
    virtio_disk_isr();
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

Por supuesto, aún debemos comprender el protocolo VirtIO antes de comenzar.

## Prerrequisitos: Virtio

### Descriptor

El descriptor contiene esta información: dirección, longitud de la dirección, algunas banderas (flags) y otra información.
Usando Descriptor, podemos apuntar el dispositivo a la dirección de memoria de cualquier búfer en la RAM.

```cpp
struct virtq_desc
{
  uint64 addr;
  uint32 len;
  uint16 flags;
  uint16 next;
};
```

- addr: Podemos decirle al dispositivo la ubicación de almacenamiento en cualquier lugar dentro de la dirección de memoria de 64 bits.
- len: Deje que el dispositivo sepa cuánta memoria hay disponible.
- flags: Se utiliza para controlar el descriptor.
- next: Indica al dispositivo el índice del siguiente descriptor. El dispositivo solo lee este campo si se especifica VIRTQ_DESC_F_NEXT. De lo contrario no es válido.

### AvailableRing

El índice utilizado para almacenar el descriptor. Cuando el dispositivo recibe la notificación, verificará el anillo disponible (AvailableRing) para confirmar qué descriptores deben leerse.

> Nota: Tanto Descriptor como AvailableRing se almacenan en RAM.

```cpp
struct virtq_avail
{
  uint16 flags;     // always zero
  uint16 idx;       // driver will write ring[idx] next
  uint16 ring[NUM]; // descriptor numbers of chain heads
  uint16 unused;
};
```

### UsedRing

UsedRing permite que el dispositivo envíe mensajes al sistema operativo, por lo que el dispositivo generalmente lo usa para informar al sistema operativo que ha completado una solicitud notificada previamente.
AvailableRing es muy similar a UsedRing, la diferencia es que el sistema operativo debe comprobar UsedRing para saber qué descriptor se ha reparado.

```cpp
struct virtq_used_elem
{
  uint32 id; // index of start of completed descriptor chain
  uint32 len;
};

struct virtq_used
{
  uint16 flags; // always zero
  uint16 idx;   // device increments when it adds a ring[] entry
  struct virtq_used_elem ring[NUM];
};
```

## Enviar solicitudes de lectura y escritura

Para ahorrar tiempo leyendo VirtIO Spec, este controlador de dispositivo de bloque(Block Device Driver) se refiere a la implementación de xv6-riscv, pero hay muchas capas en la implementación del sistema de archivos xv6:

```
+------------------+
|  File descriptor |
+------------------+
|  Pathname        |
+------------------+
|  Directory       |
+------------------+
|  Inode           |
+------------------+
|  Logging         |
+------------------+
|  Buffer cache    |
+------------------+
|  Disk            |
+------------------+
```

Por último el controlador del dispositivo nos facilitará la implementación del sistema de archivos en el futuro.Además, en referencia al diseño de xv6-riscv, también necesitaremos implementar una capa de caché de búfer para sincronizar los datos en el disco duro.

### Especifica el sector a escribir

```cpp
uint64_t sector = b->blockno * (BSIZE / 512);
```

### Asignar descriptor

Debido a que [qemu-virt](https://github.com/qemu/qemu/blob/master/hw/block/virtio-blk.c) leerá 3 descriptores a la vez,  es necesario asignar estos espacios antes de enviar solicitudes.

```cpp
static int
alloc3_desc(int *idx)
{
  for (int i = 0; i < 3; i++)
  {
    idx[i] = alloc_desc();
    if (idx[i] < 0)
    {
      for (int j = 0; j < i; j++)
        free_desc(idx[j]);
      return -1;
    }
  }
  return 0;
}
```

### Enviar solicitud de bloqueo (Block request)

Declarar la estructura de req:

```cpp
struct virtio_blk_req *buf0 = &disk.ops[idx[0]];
```

Debido a que los discos tienen operaciones de lectura y escritura, para que qemu sepa si debe leer o escribir, debemos escribir una bandera (**flag**) en el miembro `type` de la solicitud.

```cpp
if(write)
  buf0->type = VIRTIO_BLK_T_OUT; // write the disk
else
  buf0->type = VIRTIO_BLK_T_IN; // read the disk
buf0->reserved = 0; // The reserved portion is used to pad the header to 16 bytes and move the 32-bit sector field to the correct place.
buf0->sector = sector; // specify the sector that we wanna modified.
```

### Rellenar el descriptor

En este punto, hemos asignado la información básica de Descriptor y req, y luego podemos completar los datos de estos tres Descriptores:

```cpp
disk.desc[idx[0]].addr = buf0;
  disk.desc[idx[0]].len = sizeof(struct virtio_blk_req);
  disk.desc[idx[0]].flags = VRING_DESC_F_NEXT;
  disk.desc[idx[0]].next = idx[1];

  disk.desc[idx[1]].addr = ((uint32)b->data) & 0xffffffff;
  disk.desc[idx[1]].len = BSIZE;
  if (write)
    disk.desc[idx[1]].flags = 0; // device reads b->data
  else
    disk.desc[idx[1]].flags = VRING_DESC_F_WRITE; // device writes b->data
  disk.desc[idx[1]].flags |= VRING_DESC_F_NEXT;
  disk.desc[idx[1]].next = idx[2];

  disk.info[idx[0]].status = 0xff; // device writes 0 on success
  disk.desc[idx[2]].addr = (uint32)&disk.info[idx[0]].status;
  disk.desc[idx[2]].len = 1;
  disk.desc[idx[2]].flags = VRING_DESC_F_WRITE; // device writes the status
  disk.desc[idx[2]].next = 0;

  // record struct buf for virtio_disk_intr().
  b->disk = 1;
  disk.info[idx[0]].b = b;

  // tell the device the first index in our chain of descriptors.
  disk.avail->ring[disk.avail->idx % NUM] = idx[0];

  __sync_synchronize();

  // tell the device another avail ring entry is available.
  disk.avail->idx += 1; // not % NUM ...

  __sync_synchronize();

  *R(VIRTIO_MMIO_QUEUE_NOTIFY) = 0; // value is queue number

  // Wait for virtio_disk_intr() to say request has finished.
  while (b->disk == 1)
  {
  }

  disk.info[idx[0]].b = 0;
  free_chain(idx[0]);

```

Cuando se llena el Descriptor, `*R(VIRTIO_MMIO_QUEUE_NOTIFY) = 0;` le recordará a VIRTIO que acepte nuestra solicitud de Bloqueo(Block request).

Además, `while (b->disk == 1)` puede garantizar que el sistema operativo continúe ejecutando el siguiente código después de recibir una interrupción externa de Virtio.

## Implementar ISR de VirtIO

Cuando el programa del sistema recibe una interrupción externa, juzgará qué dispositivo externo (VirtIO, UART...) inició la interrupción según el número de IRQ.

```cpp
void external_handler()
{
  int irq = plic_claim();
  if (irq == UART0_IRQ)
  {
    lib_isr();
  }
  else if (irq == VIRTIO_IRQ)
  {
    lib_puts("Virtio IRQ\n");
    virtio_disk_isr();
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

Si VirtIO inicia la interrupción, se reenviará a `virtio_disk_isr()` para su procesamiento.

```cpp
void virtio_disk_isr()
{

  // the device won't raise another interrupt until we tell it
  // we've seen this interrupt, which the following line does.
  // this may race with the device writing new entries to
  // the "used" ring, in which case we may process the new
  // completion entries in this interrupt, and have nothing to do
  // in the next interrupt, which is harmless.
  *R(VIRTIO_MMIO_INTERRUPT_ACK) = *R(VIRTIO_MMIO_INTERRUPT_STATUS) & 0x3;

  __sync_synchronize();

  // the device increments disk.used->idx when it
  // adds an entry to the used ring.

  while (disk.used_idx != disk.used->idx)
  {
    __sync_synchronize();
    int id = disk.used->ring[disk.used_idx % NUM].id;

    if (disk.info[id].status != 0)
      panic("virtio_disk_intr status");

    struct blk *b = disk.info[id].b;
    b->disk = 0; // disk is done with buf
    disk.used_idx += 1;
  }

}
```

La función `virtio_disk_isr()` se encarga principalmente de cambiar el estado del disco y notificar al sistema que las operaciones de lectura/escritura emitidas previamente se han ejecutado correctamente.
En particular, `b->disk = 0;` permite que el ciclo mencionado anteriormente `while (b->disk == 1)` se detenga adecuadamente y libere el spinlock del disco.

```cpp
int os_main(void)
{
	os_start();
	disk_read();
	int current_task = 0;
	while (1)
	{
		lib_puts("OS: Activate next task\n");
		task_go(current_task);
		lib_puts("OS: Back to OS\n");
		current_task = (current_task + 1) % taskTop; // Round Robin Scheduling
		lib_puts("\n");
	}
	return 0;
}
```

Como mini-riscv-os no cuenta con una implementación de lock (bloqueo) capaz de dormir, el autor ejecuta la función de prueba `disk_read()` una vez durante el inicio del sistema. Si se desea implementar un sistema de archivos de nivel superior, será necesario utilizar un sleep lock para evitar que múltiples tareas intenten acceder a los recursos del disco y provoquen un deadlock (bloqueo mutuo).

## Reference

- [xv6-riscv](https://github.com/mit-pdos/xv6-riscv)
- [Lecture: Virtual I/O Protocol Operating Systems Stephen Marz](https://web.eecs.utk.edu/~smarz1/courses/cosc361/notes/virtio/)
- [Implementing a virtio-blk driver in my own operating system](https://brennan.io/2020/03/22/sos-block-device/)
- [xv6-rv32](https://github.com/riscv2os/xv6-rv32?fbclid=IwAR3eeG5jjIrpHM8Rh_0VdaZEikoEEtoIdDHZnx8CxxhqAcE89R0oZQoGaEY)


## Build & Run

```sh
IAN@DESKTOP-9AEMEPL MINGW64 ~/Desktop/mini-riscv-os/08-BlockDeviceDriver (feat/block_driver)
$ make all
rm -f *.elf *.img
riscv64-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -g -Wall -w -T os.ld -o os.elf start.s sys.s lib.c timer.c task.c os.c user.c trap.c lock.c plic.c virtio.c string.c
Press Ctrl-A and then X to exit QEMU
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -drive if=none,format=raw,file=hdd.dsk,id=x0 -device virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0 -kernel os.elf
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

OS: Activate next task
Task0: Created!
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

Puede establecer el punto de interrupción en cualquier archivo c:

```sh
(gdb) b trap.c:27
Breakpoint 2 at 0x80008f78: file trap.c, line 27.
(gdb)
```

Como en el ejemplo anterior, cuando el proceso se ejecuta en trap.c, línea 27 (Timer Interrupt).
El proceso se suspenderá automáticamente hasta que presione la tecla `c` (continue) o `s` (step).
