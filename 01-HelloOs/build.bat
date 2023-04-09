@echo off
set CC=riscv64-unknown-elf-gcc
set CFLAGS=-nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32

set QEMU=qemu-system-riscv32
set QFLAGS=-nographic -smp 4 -machine virt -bios none

set OBJDUMP=riscv64-unknown-elf-objdump

set SRC=start.s os.c

:clean
del *.elf

:build_os.elf: 
echo compilando
%CC% %CFLAGS% -T os.ld -o os.elf %SRC%

:qemu
echo Press Ctrl-A and then X to exit QEMU
%QEMU% %QFLAGS% -kernel os.elf


