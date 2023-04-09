$CC = "riscv64-unknown-elf-gcc.exe"
$CFLAGS = "-nostdlib","-fno-builtin","-mcmodel=medany","-march=rv32ima","-mabi=ilp32"
$QEMU = "qemu-system-riscv32"
$QFLAGS = "-nographic", "-smp", "4", "-machine", "virt", "-bios", "none"
$OBJDUMP = "riscv64-unknown-elf-objdump.exe"
$SRC = "start.s","os.c"

#clean
Remove-Item *.elf -Force -ErrorAction SilentlyContinue

#build_os.elf
echo "compilando"
& $CC $CFLAGS -T os.ld -o os.elf $SRC

#qemu
echo "Press Ctrl-A and then X to exit QEMU"
& $QEMU $QFLAGS -kernel os.elf