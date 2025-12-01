; program.nasm: Application entry point.

%include "anrc/all"
%include "main.inc"
%include "program.inc"

global program_entry

section .rotext

; `static const char *hello_world_msg`
; * **DESC:** Message to print to standard output.
hello_world_msg:
    db "Hello, World!", `\n`, 0

section .text

; `int program_entry(args_container_t args)`
; * **DESC:** Start of main application logic.
; * **PARAM `args`:** Program arguments.
; * **RETURNS:** Exit status.
program_entry:
    lea r8, [rel hello_world_msg]
    callclib 1, cc_printf

    ; Start coding here!

    xor eax, eax
    ret
