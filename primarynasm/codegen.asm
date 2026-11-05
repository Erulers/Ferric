
bits 64
default rel

global ferric_codegen
global ferric_codegen_error

%define AST_MODULE 1
%define AST_BLOCK 2
%define AST_CALL 3
%define AST_IDENTIFIER 4
%define AST_INTEGER 5
%define AST_FLOAT 6
%define AST_STRING 7
%define AST_BINARY 8
%define AST_UNARY 9
%define AST_MEMBER 10
%define AST_ARGUMENTS 11

%define MAX_DEPTH 512

%define ERR_NONE 0
%define ERR_NULL_AST -1
%define ERR_DEPTH -2
%define ERR_UNSUPPORTED -3
%define ERR_STRING_LIMIT -4
%define ERR_OUTPUT -5

extern fopen
extern fclose
extern fprintf

section .data
mode_write db "w", 0
fmt_integer db "    mov rax, %lld", 10, 0
fmt_global db "global main", 10, "global WinMain", 10, "global ferric_program", 10, 0
fmt_section db "section .text", 10, 0
fmt_entry db "main:", 10, "WinMain:", 10, "ferric_program:", 10, 0
fmt_app_call db "    sub rsp, 40", 10, "    call ferric_run_window", 10, "    add rsp, 40", 10, 0
fmt_gui_support:
    db "extern GetModuleHandleA", 10, "extern RegisterClassExA", 10, "extern LoadCursorA", 10, "extern CreateWindowExA", 10, "extern ShowWindow", 10
    db "extern UpdateWindow", 10, "extern GetMessageA", 10, "extern TranslateMessage", 10, "extern DispatchMessageA", 10
    db "extern DefWindowProcA", 10, "extern PostQuitMessage", 10, "section .text", 10, "ferric_run_window:", 10
    db "    push rbp", 10, "    mov rbp, rsp", 10, "    sub rsp, 128", 10, "    xor ecx, ecx", 10, "    call GetModuleHandleA", 10
    db "    mov [rel ferric_instance], rax", 10, "    mov dword [rel ferric_wndclass], 80", 10, "    mov dword [rel ferric_wndclass+4], 3", 10
    db "    lea rax, [rel ferric_wndproc]", 10, "    mov [rel ferric_wndclass+8], rax", 10, "    mov rax, [rel ferric_instance]", 10
    db "    mov [rel ferric_wndclass+24], rax", 10, "    xor ecx, ecx", 10, "    mov edx, 32512", 10, "    call LoadCursorA", 10, "    mov [rel ferric_wndclass+40], rax", 10
    db "    lea rax, [rel ferric_class_name]", 10, "    mov [rel ferric_wndclass+64], rax", 10, "    lea rcx, [rel ferric_wndclass]", 10, "    call RegisterClassExA", 10
    db "    test eax, eax", 10, "    jz .gui_done", 10, "    xor ecx, ecx", 10, "    lea rdx, [rel ferric_class_name]", 10
    db "    lea r8, [rel ferric_window_title]", 10, "    mov r9d, 0x10CF0000", 10, "    mov qword [rsp+32], 0x80000000", 10
    db "    mov qword [rsp+40], 0x80000000", 10, "    mov qword [rsp+48], 800", 10, "    mov qword [rsp+56], 500", 10
    db "    mov qword [rsp+64], 0", 10, "    mov qword [rsp+72], 0", 10, "    mov rax, [rel ferric_instance]", 10
    db "    mov [rsp+80], rax", 10, "    mov qword [rsp+88], 0", 10, "    call CreateWindowExA", 10, "    test rax, rax", 10
    db "    jz .gui_done", 10, "    mov [rbp-8], rax", 10, "    mov rcx, rax", 10, "    mov edx, 5", 10, "    call ShowWindow", 10
    db "    mov rcx, [rbp-8]", 10, "    call UpdateWindow", 10, ".gui_message_loop:", 10, "    lea rcx, [rbp-64]", 10
    db "    xor edx, edx", 10, "    xor r8d, r8d", 10, "    xor r9d, r9d", 10, "    call GetMessageA", 10, "    test eax, eax", 10
    db "    jle .gui_done", 10, "    lea rcx, [rbp-64]", 10, "    call TranslateMessage", 10, "    lea rcx, [rbp-64]", 10
    db "    call DispatchMessageA", 10, "    jmp .gui_message_loop", 10, ".gui_done:", 10, "    xor eax, eax", 10
    db "    add rsp, 128", 10, "    pop rbp", 10, "    ret", 10, "ferric_wndproc:", 10, "    cmp edx, 2", 10
    db "    je .gui_wm_destroy", 10, "    sub rsp, 40", 10, "    call DefWindowProcA", 10, "    add rsp, 40", 10, "    ret", 10
    db ".gui_wm_destroy:", 10, "    sub rsp, 40", 10, "    xor ecx, ecx", 10, "    call PostQuitMessage", 10
    db "    add rsp, 40", 10, "    xor eax, eax", 10, "    ret", 10, "section .data", 10, "align 8", 10
    db "ferric_instance dq 0", 10, "ferric_wndclass times 80 db 0", 10, "ferric_class_name db 'FERRICNativeWindow', 0", 10
    db "ferric_window_title db 'FERRIC Window', 0", 10, 0
fmt_return db "    xor eax, eax", 10, "    ret", 10, 0
fmt_push db "    push rax", 10, 0
fmt_pop db "    pop r10", 10, 0
fmt_add db "    add rax, r10", 10, 0
fmt_sub db "    sub r10, rax", 10, "    mov rax, r10", 10, 0
fmt_mul db "    imul rax, r10", 10, 0
fmt_div db "    mov r11, rax", 10, "    mov rax, r10", 10, "    cqo", 10, "    idiv r11", 10, 0
fmt_and db "    and rax, r10", 10, 0
fmt_or db "    or rax, r10", 10, 0
fmt_xor db "    xor rax, r10", 10, 0
fmt_cmp db "    cmp r10, rax", 10, 0
fmt_equal db "    sete al", 10, "    movzx rax, al", 10, 0
fmt_not_equal db "    setne al", 10, "    movzx rax, al", 10, 0
fmt_less db "    setl al", 10, "    movzx rax, al", 10, 0
fmt_less_equal db "    setle al", 10, "    movzx rax, al", 10, 0
fmt_greater db "    setg al", 10, "    movzx rax, al", 10, 0
fmt_greater_equal db "    setge al", 10, "    movzx rax, al", 10, 0
fmt_neg db "    neg rax", 10, 0
fmt_not db "    test rax, rax", 10, "    sete al", 10, "    movzx rax, al", 10, 0
fmt_bit_not db "    not rax", 10, 0

section .bss
codegen_file resq 1
codegen_ast resq 1
codegen_source resq 1
codegen_error resd 1
codegen_depth resd 1
codegen_current_node resq 1
codegen_saved_left resq 1
codegen_saved_right resq 1
codegen_operator resd 1
codegen_has_gui resd 1

section .text

ferric_codegen_error:
    mov eax, [codegen_error]
    ret

ferric_codegen:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40

    mov dword [codegen_error], ERR_NONE
    mov dword [codegen_depth], 0
    mov dword [codegen_has_gui], 0

    test rcx, rcx
    jz .null_ast

    test rdx, rdx
    jz .null_path

    mov [codegen_ast], rcx
    mov [codegen_source], r8

    mov rcx, rdx
    lea rdx, [mode_write]
    call fopen
    test rax, rax
    jz .output_error

    mov [codegen_file], rax

    mov rcx, rax
    lea rdx, [fmt_global]
    xor eax, eax
    call fprintf

    mov rcx, [codegen_file]
    lea rdx, [fmt_section]
    xor eax, eax
    call fprintf

    mov rcx, [codegen_file]
    lea rdx, [fmt_entry]
    xor eax, eax
    call fprintf

    mov rdi, [codegen_ast]
    call codegen_node

    test eax, eax
    js .generation_failed

    mov rcx, [codegen_file]
    lea rdx, [fmt_return]
    xor eax, eax
    call fprintf

    cmp dword [codegen_has_gui], 0
    je .main_body_complete
    mov rcx, [codegen_file]
    lea rdx, [fmt_gui_support]
    xor eax, eax
    call fprintf

.main_body_complete:

    mov rcx, [codegen_file]
    call fclose

    xor eax, eax
    jmp .return

.null_ast:
    mov eax, ERR_NULL_AST
    jmp .set_error

.null_path:
    mov eax, ERR_OUTPUT
    jmp .set_error

.output_error:
    mov eax, ERR_OUTPUT
    jmp .set_error

.generation_failed:
    mov rcx, [codegen_file]
    call fclose
    mov eax, [codegen_error]
    jmp .return

.set_error:
    mov [codegen_error], eax

.return:
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

codegen_emit:
    sub rsp, 40
    mov rcx, [codegen_file]
    mov rdx, rsi
    xor eax, eax
    call fprintf
    add rsp, 40
    ret

codegen_node:
    test rdi, rdi
    jz .invalid

    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40

    inc dword [codegen_depth]
    cmp dword [codegen_depth], MAX_DEPTH
    ja .depth_error

    mov r15, rdi
    mov [codegen_current_node], rdi
    mov eax, [r15]

    cmp eax, AST_MODULE
    je .module
    cmp eax, AST_BLOCK
    je .block
    cmp eax, AST_CALL
    je .call
    cmp eax, AST_IDENTIFIER
    je .identifier
    cmp eax, AST_INTEGER
    je .integer
    cmp eax, AST_FLOAT
    je .float
    cmp eax, AST_STRING
    je .string
    cmp eax, AST_BINARY
    je .binary
    cmp eax, AST_UNARY
    je .unary
    cmp eax, AST_MEMBER
    je .member
    cmp eax, AST_ARGUMENTS
    je .arguments

    jmp .unsupported

.module:
    mov rbx, [r15+16]

.module_loop:
    test rbx, rbx
    jz .success

    mov rdi, rbx
    call codegen_node
    test eax, eax
    js .done

    mov rbx, [rbx+24]
    jmp .module_loop

.block:
    mov rbx, [r15+16]

.block_loop:
    test rbx, rbx
    jz .success

    mov rdi, rbx
    call codegen_node
    test eax, eax
    js .done

    mov rbx, [rbx+24]
    jmp .block_loop

.integer:
    mov rcx, [codegen_file]
    lea rdx, [fmt_integer]
    mov r8, [r15+8]
    xor eax, eax
    call fprintf
    jmp .success

.float:
.string:
.identifier:
.member:
.arguments:
    mov eax, ERR_UNSUPPORTED
    jmp .fail

.call:
    ; Native GUI intrinsic: application(). Emits a real Win32 top-level window.
    mov rax, [r15+8]
    test rax, rax
    jz .call_unsupported
    cmp dword [rax], AST_IDENTIFIER
    jne .call_unsupported
    mov rdx, [rax+8]              ; identifier source offset
    mov rcx, [rax+16]             ; identifier length
    cmp rcx, 11
    jne .call_unsupported
    mov rsi, [codegen_source]
    test rsi, rsi
    jz .call_unsupported
    add rsi, rdx
    cmp byte [rsi], 'a'
    jne .call_unsupported
    cmp byte [rsi+1], 'p'
    jne .call_unsupported
    cmp byte [rsi+2], 'p'
    jne .call_unsupported
    cmp byte [rsi+3], 'l'
    jne .call_unsupported
    cmp byte [rsi+4], 'i'
    jne .call_unsupported
    cmp byte [rsi+5], 'c'
    jne .call_unsupported
    cmp byte [rsi+6], 'a'
    jne .call_unsupported
    cmp byte [rsi+7], 't'
    jne .call_unsupported
    cmp byte [rsi+8], 'i'
    jne .call_unsupported
    cmp byte [rsi+9], 'o'
    jne .call_unsupported
    cmp byte [rsi+10], 'n'
    jne .call_unsupported
    mov dword [codegen_has_gui], 1
    mov rcx, [codegen_file]
    lea rdx, [fmt_app_call]
    xor eax, eax
    call fprintf
    jmp .success

.call_unsupported:
    mov eax, ERR_UNSUPPORTED
    jmp .fail

.binary:
    mov r12, [r15+8]
    mov r13, [r15+16]
    mov r14d, [r15+4]

    mov rdi, r12
    call codegen_node
    test eax, eax
    js .done

    lea rsi, [fmt_push]
    call codegen_emit

    mov rdi, r13
    call codegen_node
    test eax, eax
    js .done

    lea rsi, [fmt_pop]
    call codegen_emit

    cmp r14d, 16
    je .binary_add
    cmp r14d, 17
    je .binary_sub
    cmp r14d, 18
    je .binary_mul
    cmp r14d, 19
    je .binary_div
    cmp r14d, 21
    je .binary_equal
    cmp r14d, 22
    je .binary_equal
    cmp r14d, 23
    je .binary_not_equal
    cmp r14d, 24
    je .binary_less
    cmp r14d, 25
    je .binary_less_equal
    cmp r14d, 26
    je .binary_greater
    cmp r14d, 27
    je .binary_greater_equal
    cmp r14d, 31
    je .binary_and
    cmp r14d, 32
    je .binary_or
    cmp r14d, 33
    je .binary_xor

    mov eax, ERR_UNSUPPORTED
    jmp .fail

.binary_add:
    lea rsi, [fmt_add]
    call codegen_emit
    jmp .success

.binary_sub:
    lea rsi, [fmt_sub]
    call codegen_emit
    jmp .success

.binary_mul:
    lea rsi, [fmt_mul]
    call codegen_emit
    jmp .success

.binary_div:
    lea rsi, [fmt_div]
    call codegen_emit
    jmp .success

.binary_equal:
    lea rsi, [fmt_cmp]
    call codegen_emit
    lea rsi, [fmt_equal]
    call codegen_emit
    jmp .success

.binary_not_equal:
    lea rsi, [fmt_cmp]
    call codegen_emit
    lea rsi, [fmt_not_equal]
    call codegen_emit
    jmp .success

.binary_less:
    lea rsi, [fmt_cmp]
    call codegen_emit
    lea rsi, [fmt_less]
    call codegen_emit
    jmp .success

.binary_less_equal:
    lea rsi, [fmt_cmp]
    call codegen_emit
    lea rsi, [fmt_less_equal]
    call codegen_emit
    jmp .success

.binary_greater:
    lea rsi, [fmt_cmp]
    call codegen_emit
    lea rsi, [fmt_greater]
    call codegen_emit
    jmp .success

.binary_greater_equal:
    lea rsi, [fmt_cmp]
    call codegen_emit
    lea rsi, [fmt_greater_equal]
    call codegen_emit
    jmp .success

.binary_and:
    lea rsi, [fmt_and]
    call codegen_emit
    jmp .success

.binary_or:
    lea rsi, [fmt_or]
    call codegen_emit
    jmp .success

.binary_xor:
    lea rsi, [fmt_xor]
    call codegen_emit
    jmp .success

.unary:
    mov r12, [r15+8]
    mov r13d, [r15+4]

    mov rdi, r12
    call codegen_node
    test eax, eax
    js .done

    cmp r13d, 17
    je .unary_negate
    cmp r13d, 30
    je .unary_not
    cmp r13d, 34
    je .unary_bit_not

    mov eax, ERR_UNSUPPORTED
    jmp .fail

.unary_negate:
    lea rsi, [fmt_neg]
    call codegen_emit
    jmp .success

.unary_not:
    lea rsi, [fmt_not]
    call codegen_emit
    jmp .success

.unary_bit_not:
    lea rsi, [fmt_bit_not]
    call codegen_emit
    jmp .success

.success:
    xor eax, eax
    jmp .done

.invalid:
    mov eax, ERR_NULL_AST
    jmp .fail_unframed

.depth_error:
    mov eax, ERR_DEPTH
    jmp .fail

.unsupported:
    mov eax, ERR_UNSUPPORTED

.fail:
    mov [codegen_error], eax

.done:
    dec dword [codegen_depth]
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

.fail_unframed:
    mov [codegen_error], eax
    ret
