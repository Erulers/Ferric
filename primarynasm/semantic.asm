
bits 64
default rel

global ferric_semantic_analyze
global ferric_semantic_error
global ferric_semantic_reset

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

%define NODE_SIZE 40
%define MAX_SYMBOLS 4096
%define MAX_SCOPES 256
%define SYMBOL_SIZE 32
%define SCOPE_SIZE 24

%define TYPE_UNKNOWN 0
%define TYPE_VOID 1
%define TYPE_INTEGER 2
%define TYPE_FLOAT 3
%define TYPE_TEXT 4
%define TYPE_BOOLEAN 5
%define TYPE_FUNCTION 6
%define TYPE_MODULE 7

%define ERR_NONE 0
%define ERR_NULL_AST -1
%define ERR_SYMBOL_LIMIT -2
%define ERR_SCOPE_LIMIT -3
%define ERR_DUPLICATE -4
%define ERR_UNDECLARED -5
%define ERR_TYPE_MISMATCH -6
%define ERR_INVALID_CALL -7
%define ERR_INVALID_OP -8
%define ERR_INVALID_AST -9
%define ERR_SCOPE_UNDERFLOW -10

section .bss
semantic_ast resq 1
semantic_symbols resb MAX_SYMBOLS * SYMBOL_SIZE
semantic_symbol_count resq 1
semantic_scopes resb MAX_SCOPES * SCOPE_SIZE
semantic_scope_count resq 1
semantic_current_scope resq 1
semantic_error_code resd 1
semantic_error_node resq 1
semantic_result_type resd 1
semantic_walk_depth resd 1
semantic_temp_type resd 1
semantic_temp_node resq 1

section .text

ferric_semantic_reset:
    mov qword [rel semantic_ast], 0
    mov qword [rel semantic_symbol_count], 0
    mov qword [rel semantic_scope_count], 0
    mov qword [rel semantic_current_scope], 0
    mov dword [rel semantic_error_code], ERR_NONE
    mov qword [rel semantic_error_node], 0
    mov dword [rel semantic_result_type], TYPE_UNKNOWN
    mov dword [rel semantic_walk_depth], 0
    mov dword [rel semantic_temp_type], TYPE_UNKNOWN
    mov qword [rel semantic_temp_node], 0
    xor eax, eax
    ret

ferric_semantic_error:
    mov eax, [rel semantic_error_code]
    ret

ferric_semantic_analyze:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    sub rsp, 40

    mov r12, rcx
    test r12, r12
    jz .null_ast

    call ferric_semantic_reset
    mov [rel semantic_ast], r12

    xor edi, edi
    call semantic_push_scope
    test eax, eax
    js .analyze_failed

    mov rdi, r12
    call semantic_visit_node
    test eax, eax
    js .analyze_failed

    xor eax, eax
    jmp .analyze_return

.null_ast:
    mov eax, ERR_NULL_AST
    mov [rel semantic_error_code], eax
    jmp .analyze_return

.analyze_failed:
    mov eax, [rel semantic_error_code]
    test eax, eax
    jnz .analyze_return
    mov eax, ERR_INVALID_AST
    mov [rel semantic_error_code], eax

.analyze_return:
    add rsp, 40
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

semantic_push_scope:
    mov rax, [rel semantic_scope_count]
    cmp rax, MAX_SCOPES
    jae .scope_limit

    imul rax, SCOPE_SIZE
    lea rdx, [rel semantic_scopes]
    add rdx, rax

    mov rcx, [rel semantic_current_scope]
    mov [rdx], rcx
    mov [rdx+8], rdi
    mov dword [rdx+16], 0
    mov dword [rdx+20], 0

    mov rax, [rel semantic_scope_count]
    mov [rel semantic_current_scope], rax
    inc qword [rel semantic_scope_count]
    xor eax, eax
    ret

.scope_limit:
    mov eax, ERR_SCOPE_LIMIT
    mov [rel semantic_error_code], eax
    ret

semantic_pop_scope:
    mov rax, [rel semantic_current_scope]
    test rax, rax
    jz .scope_underflow

    imul rax, SCOPE_SIZE
    lea rdx, [rel semantic_scopes]
    add rdx, rax
    mov rax, [rdx]
    mov [rel semantic_current_scope], rax
    xor eax, eax
    ret

.scope_underflow:
    mov eax, ERR_SCOPE_UNDERFLOW
    mov [rel semantic_error_code], eax
    ret

semantic_find_symbol:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15

    mov r12, rcx
    mov r13, rdx
    mov r14, [rel semantic_symbol_count]

.find_loop:
    test r14, r14
    jz .find_missing

    dec r14
    mov rax, r14
    imul rax, SYMBOL_SIZE
    lea r15, [rel semantic_symbols]
    add r15, rax

    cmp [r15], r12
    jne .find_loop

    cmp [r15+8], r13
    jne .find_loop

    mov eax, r14d
    jmp .find_return

.find_missing:
    mov eax, -1

.find_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

semantic_add_symbol:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40

    cmp qword [rel semantic_symbol_count], MAX_SYMBOLS
    jae .symbol_limit

    mov r12, rcx
    mov r13d, edx
    mov r14d, r8d
    mov r15d, r9d

    mov rcx, r12
    mov rdx, [rel semantic_current_scope]
    call semantic_find_symbol
    test eax, eax
    jns .duplicate

    mov rax, [rel semantic_symbol_count]
    imul rax, SYMBOL_SIZE
    lea rdi, [rel semantic_symbols]
    add rdi, rax

    mov [rdi], r12
    mov rax, [rel semantic_current_scope]
    mov [rdi+8], rax
    mov [rdi+16], r13d
    mov [rdi+20], r14d
    mov [rdi+24], r15d
    mov dword [rdi+28], 0

    inc qword [rel semantic_symbol_count]
    xor eax, eax
    jmp .add_return

.duplicate:
    mov eax, ERR_DUPLICATE
    mov [rel semantic_error_code], eax
    jmp .add_return

.symbol_limit:
    mov eax, ERR_SYMBOL_LIMIT
    mov [rel semantic_error_code], eax

.add_return:
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

semantic_visit_node:
    test rdi, rdi
    jz .visit_invalid

    push rbx
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40

    inc dword [rel semantic_walk_depth]
    cmp dword [rel semantic_walk_depth], 512
    ja .visit_depth_error

    mov r15, rdi
    mov eax, [rdi]

    cmp eax, AST_MODULE
    je .visit_module
    cmp eax, AST_BLOCK
    je .visit_block
    cmp eax, AST_IDENTIFIER
    je .visit_identifier
    cmp eax, AST_INTEGER
    je .visit_integer
    cmp eax, AST_FLOAT
    je .visit_float
    cmp eax, AST_STRING
    je .visit_string
    cmp eax, AST_BINARY
    je .visit_binary
    cmp eax, AST_UNARY
    je .visit_unary
    cmp eax, AST_MEMBER
    je .visit_member
    cmp eax, AST_CALL
    je .visit_call
    cmp eax, AST_ARGUMENTS
    je .visit_arguments

    jmp .visit_invalid_saved

.visit_module:
    mov rbx, [r15+16]

.module_loop:
    test rbx, rbx
    jz .visit_success

    mov rdi, rbx
    call semantic_visit_node
    test eax, eax
    js .visit_done

    mov rbx, [rbx+24]
    jmp .module_loop

.visit_block:
    mov rbx, [r15+16]
    xor edi, edi
    call semantic_push_scope
    test eax, eax
    js .visit_done

.block_loop:
    test rbx, rbx
    jz .block_end

    mov rdi, rbx
    call semantic_visit_node
    test eax, eax
    js .block_fail

    mov rbx, [rbx+24]
    jmp .block_loop

.block_end:
    call semantic_pop_scope
    test eax, eax
    js .visit_done
    jmp .visit_success

.block_fail:
    mov r12d, eax
    call semantic_pop_scope
    mov eax, r12d
    jmp .visit_done

.visit_identifier:
    mov rcx, [r15+8]
    mov rdx, [rel semantic_current_scope]
    call semantic_find_symbol
    test eax, eax
    js .identifier_unresolved

    imul rax, SYMBOL_SIZE
    lea rdx, [rel semantic_symbols]
    mov eax, [rdx+rax+16]
    mov [rel semantic_result_type], eax
    jmp .visit_success

.identifier_unresolved:
    mov eax, ERR_UNDECLARED
    mov [rel semantic_error_code], eax
    mov [rel semantic_error_node], r15
    jmp .visit_done

.visit_integer:
    mov dword [rel semantic_result_type], TYPE_INTEGER
    jmp .visit_success

.visit_float:
    mov dword [rel semantic_result_type], TYPE_FLOAT
    jmp .visit_success

.visit_string:
    mov dword [rel semantic_result_type], TYPE_TEXT
    jmp .visit_success

.visit_binary:
    mov rbx, [r15+8]
    mov r12, [r15+16]

    mov rdi, rbx
    call semantic_visit_node
    test eax, eax
    js .visit_done
    mov r13d, [rel semantic_result_type]

    mov rdi, r12
    call semantic_visit_node
    test eax, eax
    js .visit_done
    mov r14d, [rel semantic_result_type]

    cmp r13d, r14d
    je .binary_same_type

    cmp r13d, TYPE_INTEGER
    jne .binary_type_error
    cmp r14d, TYPE_FLOAT
    jne .binary_type_error

    mov dword [rel semantic_result_type], TYPE_FLOAT
    jmp .visit_success

.binary_same_type:
    cmp r13d, TYPE_INTEGER
    je .binary_numeric
    cmp r13d, TYPE_FLOAT
    je .binary_numeric
    cmp r13d, TYPE_TEXT
    je .binary_text
    jmp .binary_type_error

.binary_numeric:
    mov [rel semantic_result_type], r13d
    jmp .visit_success

.binary_text:
    mov dword [rel semantic_result_type], TYPE_TEXT
    jmp .visit_success

.binary_type_error:
    mov eax, ERR_TYPE_MISMATCH
    mov [rel semantic_error_code], eax
    mov [rel semantic_error_node], r15
    jmp .visit_done

.visit_unary:
    mov rdi, [r15+8]
    call semantic_visit_node
    jmp .visit_done

.visit_member:
    mov rdi, [r15+8]
    call semantic_visit_node
    test eax, eax
    js .visit_done
    mov dword [rel semantic_result_type], TYPE_UNKNOWN
    jmp .visit_success

.visit_call:
    mov rbx, [r15+8]
    mov r12, [r15+16]

    mov rdi, rbx
    call semantic_visit_node
    test eax, eax
    js .visit_done

    mov dword [rel semantic_result_type], TYPE_UNKNOWN

    test r12, r12
    jz .visit_success

    mov rdi, r12
    call semantic_visit_node
    jmp .visit_done

.visit_arguments:
    mov rbx, [r15+16]

.arguments_loop:
    test rbx, rbx
    jz .visit_success

    mov rdi, rbx
    call semantic_visit_node
    test eax, eax
    js .visit_done

    mov rbx, [rbx+24]
    jmp .arguments_loop

.visit_success:
    xor eax, eax
    jmp .visit_done

.visit_invalid_saved:
    mov eax, ERR_INVALID_AST
    mov [rel semantic_error_code], eax
    jmp .visit_done

.visit_depth_error:
    mov eax, ERR_INVALID_AST
    mov [rel semantic_error_code], eax
    dec dword [rel semantic_walk_depth]
    jmp .visit_return

.visit_done:
    dec dword [rel semantic_walk_depth]
    jmp .visit_return

.visit_invalid:
    mov eax, ERR_INVALID_AST
    mov [rel semantic_error_code], eax
    ret

.visit_return:
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rbx
    ret
