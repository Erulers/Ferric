
bits 64
default rel

global main

extern fopen
extern fclose
extern fgetc
extern malloc
extern free
extern fprintf
extern printf
extern ferric_lex
extern ferric_parse
extern ferric_semantic_analyze
extern ferric_codegen

%define MAX_SOURCE_SIZE 16777216
%define MAX_TOKENS 262144
%define TOKEN_SIZE 24
%define NODE_SIZE 40
%define MAX_NODES 65536

%define ERR_ARGUMENTS 1
%define ERR_OPEN_SOURCE 2
%define ERR_SOURCE_SIZE 3
%define ERR_MEMORY 4
%define ERR_LEXER 6
%define ERR_PARSER 7
%define ERR_SEMANTIC 8
%define ERR_CODEGEN 9

section .data
usage_message db "Usage: ferric <input.ferric> <output.asm>", 10, 0
open_mode db "rb", 0
error_arguments db "FERRIC: expected input and output paths", 10, 0
error_open db "FERRIC: could not open source file", 10, 0
error_size db "FERRIC: source file size is invalid or exceeds the limit", 10, 0
error_memory db "FERRIC: memory allocation failed", 10, 0
error_lexer db "FERRIC: lexical analysis failed", 10, 0
error_parser db "FERRIC: parsing failed", 10, 0
error_semantic db "FERRIC: semantic analysis failed", 10, 0
error_codegen db "FERRIC: code generation failed", 10, 0

section .bss
source_file resq 1
source_path resq 1
output_path resq 1
source_buffer resq 1
source_size resq 1
read_count resq 1
token_buffer resq 1
token_count resq 1
ast_buffer resq 1
ast_count resq 1
exit_code resd 1

section .text

main:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72

    ; Do not store arguments over saved RBX/RSI at [rbp-8] and [rbp-16].
    mov dword [exit_code], 0

    cmp ecx, 3
    jl .arguments_error

    mov rax, [rdx+8]
    mov [source_path], rax

    mov rax, [rdx+16]
    mov [output_path], rax

    mov rcx, [source_path]
    lea rdx, [open_mode]
    call fopen
    test rax, rax
    jz .open_error

    mov [source_file], rax

    ; Read from the stream until EOF instead of trusting ftell/fseek size
    ; measurements. This works for regular files and avoids false read errors
    ; when the CRT reports a different size than the bytes actually returned.
    ; Allocate the maximum supported source size plus a trailing NUL byte.
    mov rcx, MAX_SOURCE_SIZE + 1
    call malloc
    test rax, rax
    jz .memory_error

    mov [source_buffer], rax
    mov r12, rax
    xor r13d, r13d

.read_loop:
    mov rcx, [source_file]
    call fgetc
    cmp eax, -1
    je .read_eof

    cmp r13, MAX_SOURCE_SIZE
    jae .size_error

    mov [r12+r13], al
    inc r13
    jmp .read_loop

.read_eof:
    mov [source_size], r13
    mov [read_count], r13
    mov byte [r12+r13], 0

    mov rcx, [source_file]
    call fclose
    mov qword [source_file], 0

    mov rcx, MAX_TOKENS * TOKEN_SIZE
    call malloc
    test rax, rax
    jz .memory_error

    mov [token_buffer], rax

    mov rcx, [source_buffer]
    mov rdx, [source_size]
    mov r8, [token_buffer]
    mov r9, MAX_TOKENS
    call ferric_lex
    test eax, eax
    js .lexer_error

    mov [token_count], rax

    mov rcx, MAX_NODES * NODE_SIZE
    call malloc
    test rax, rax
    jz .memory_error

    mov [ast_buffer], rax

    mov rcx, [token_buffer]
    mov rdx, [token_count]
    mov r8, [ast_buffer]
    lea r9, [ast_count]
    call ferric_parse
    test eax, eax
    js .parser_error

    ; The native backend resolves its own built-ins (including application()).
    ; Semantic analysis remains available as a separate API for future strict mode.
    mov rcx, [ast_buffer]
    mov rdx, [output_path]
    mov r8, [source_buffer]
    call ferric_codegen
    test eax, eax
    js .codegen_error

    jmp .cleanup

.arguments_error:
    lea rcx, [error_arguments]
    call printf
    mov dword [exit_code], ERR_ARGUMENTS
    jmp .cleanup

.open_error:
    lea rcx, [error_open]
    call printf
    mov dword [exit_code], ERR_OPEN_SOURCE
    jmp .cleanup

.size_error:
    lea rcx, [error_size]
    call printf
    mov dword [exit_code], ERR_SOURCE_SIZE
    jmp .cleanup

.memory_error:
    lea rcx, [error_memory]
    call printf
    mov dword [exit_code], ERR_MEMORY
    jmp .cleanup

.lexer_error:
    lea rcx, [error_lexer]
    call printf
    mov dword [exit_code], ERR_LEXER
    jmp .cleanup

.parser_error:
    lea rcx, [error_parser]
    call printf
    mov dword [exit_code], ERR_PARSER
    jmp .cleanup

.semantic_error:
    lea rcx, [error_semantic]
    call printf
    mov dword [exit_code], ERR_SEMANTIC
    jmp .cleanup

.codegen_error:
    lea rcx, [error_codegen]
    call printf
    mov dword [exit_code], ERR_CODEGEN

.cleanup:
    mov rcx, [source_file]
    test rcx, rcx
    jz .cleanup_source
    call fclose

.cleanup_source:
    mov rcx, [source_buffer]
    test rcx, rcx
    jz .cleanup_tokens
    call free

.cleanup_tokens:
    mov rcx, [token_buffer]
    test rcx, rcx
    jz .cleanup_ast
    call free

.cleanup_ast:
    mov rcx, [ast_buffer]
    test rcx, rcx
    jz .finish
    call free

.finish:
    mov eax, [exit_code]

    add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret
