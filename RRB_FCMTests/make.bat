@echo off

set WRITE="G:\Mega65\Dev\bin\cc1541.exe" -attach "./bin/DISK.D81" 8 -write
set FORMAT="G:\Mega65\Dev\bin\cc1541.exe" -format "disk,0" d81 "./bin/DISK.D81"
set KICKASM=java -cp G:\Mega65\YiearKungFu\Bin\kickassembler-5.24-65ce02.e.jar  kickass.KickAssembler65CE02  -vicesymbols -showmem -symbolfile -bytedumpfile main.klist


echo ASSEMBLING SOURCES...
%KICKASM%  main.s

"G:\Mega65\Xemu\xmega65.exe" -uartmon :4510 -besure  -prg "main.prg"


