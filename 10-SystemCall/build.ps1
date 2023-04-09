$CC = "riscv64-unknown-elf-gcc.exe"
$CFLAGS = "-nostdlib","-fno-builtin","-mcmodel=medany","-march=rv32ima","-mabi=ilp32"
$CFLAGS = "-I./include","-nostdlib","-fno-builtin","-mcmodel=medany","-march=rv32ima","-mabi=ilp32","-g","-Wall","-w","-D","CONFIG_SYSCALL"

$OBJDUMP = "riscv64-unknown-elf-objdump.exe"
$GDB = "riscv64-unknown-elf-gdb.exe"

$SOURCE = "src"
$OBJ = @(
"$SOURCE/start.s",
"$SOURCE/sys.s",
"$SOURCE/mem.s",
"$SOURCE/lib.c",
"$SOURCE/timer.c",
"$SOURCE/os.c",
"$SOURCE/task.c",
"$SOURCE/user.c",
"$SOURCE/trap.c",
"$SOURCE/lock.c",
"$SOURCE/plic.c",
"$SOURCE/virtio.c",
"$SOURCE/string.c",
"$SOURCE/alloc.c",
"$SOURCE/syscall.c",
"$SOURCE/usys.s"
)

$QEMU = "qemu-system-riscv32"
$QFLAGS = "-nographic", "-smp", "4", "-machine", "virt", "-bios", "none"
$QFLAGS += "-drive", "if=none,format=raw,file=hdd.dsk,id=x0"
$QFLAGS += "-device", "virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0"

function Generate-RandomDisk {
    Param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        [int]$bs = 1MB,
        [int]$SizeInMB = 32

    )

    "Generando disco"
    
    $blockSize = $bs
    $numBlocks = $SizeInMB

    # Crea un objeto RNGCryptoServiceProvider
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider

    # Abre un archivo para escritura binaria
    $outpath = Join-Path $PWD $FilePath
    $file = [System.IO.File]::OpenWrite($outpath)

    # Genera datos aleatorios y escribe en el archivo
    for ($i = 0; $i -lt $numBlocks; $i++) {
        $bytes = New-Object byte[] $blockSize
        $rng.GetBytes($bytes)
        $file.Write($bytes, 0, $bytes.Length)
    }

    # Cierra el archivo
    $file.Close()
}



#clean
Remove-Item *.elf -Force -ErrorAction SilentlyContinue
Remove-Item hdd.dsk -Force -ErrorAction SilentlyContinue

Generate-RandomDisk -FilePath "hdd.dsk" -SizeInMB 32

#build_os.elf
echo "compilando"
& $CC $CFLAGS -T os.ld -o os.elf $OBJ

#qemu
echo "Press Ctrl-A and then X to exit QEMU"
& $QEMU $QFLAGS -kernel os.elf