; main.nasm: Reserved runtime entry point.
; This intermediate step sets up the environment, collects arguments,
; and transfers control to the user program. Do not rename this file
; or the `main` symbol unless you are customizing the runtime.

%include "anrc/all"
%include "argparse/all"

global main
global program_exit_early

extern program_entry

section .bss

program_stack_pointer: resq 1
main_args_container: resb args_container_t_size

section .text

; `int main(int argc, char **argv)`
; * **DESC:** Captures `argc`/`argv` into `main_args_container`, clears
;   all registers, calls `program_entry`, restores state, terminates.
; * **PARAM `argc`:** Logical argument count.
; * **PARAM `argv`:** Pointer to argument vector.
; * **RETURNS:** Exit status.
main:
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    mov [rel program_stack_pointer], rsp

    lea r8, [rel main_args_container]
    call _args_collect_from_main

    xor eax, eax
    xor ebx, ebx
    xor ecx, ecx
    xor edx, edx
    xor edi, edi
    xor esi, esi
    ; xor r8d, r8d  ; r8 contains program arguments from argparse
    xor r9d, r9d
    xor r10d, r10d
    xor r11d, r11d
    xor r12d, r12d
    xor r13d, r13d
    xor r14d, r14d
    xor r15d, r15d
    call program_entry

.restore_stack:
    mov rsp, [rel program_stack_pointer]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    ret

; `int program_exit_early(int errno, char *msg)`
; * **DESC:** Terminates program with error code `errno`, optionally
;   printing `msg` to standard error if `errno` is non-zero.
; * **PARAM `errno`:** Process exit code.
; * **PARAM `msg`:** Null-terminated message string or null pointer
;   for no output.
; * **RETURNS:** Exit status.
program_exit_early:
    test r8d, r8d
    mov eax, r8d
    jz main.restore_stack

    test r9, r9
    mov r10d, eax
    jz main.restore_stack

    mov r8, r9
    callclib cc_get_stderr
    mov r9, rax
    callclib 2, cc_fputs

    mov eax, r10d
    jmp main.restore_stack
