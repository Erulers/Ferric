
bits 64
default rel

global ferric_parse
global ferric_parser_init
global ferric_parser_error

%define TOK_EOF             0
%define TOK_IDENTIFIER      1
%define TOK_KEYWORD         2
%define TOK_INTEGER         3
%define TOK_FLOAT           4
%define TOK_STRING          5
%define TOK_LPAREN          6
%define TOK_RPAREN          7
%define TOK_LBRACE          8
%define TOK_RBRACE          9
%define TOK_LBRACKET       10
%define TOK_RBRACKET       11
%define TOK_COMMA          12
%define TOK_SEMICOLON      13
%define TOK_COLON          14
%define TOK_DOT            15
%define TOK_PLUS           16
%define TOK_MINUS          17
%define TOK_STAR            18
%define TOK_SLASH           19
%define TOK_PERCENT         20
%define TOK_ASSIGN          21
%define TOK_EQUAL           22
%define TOK_NOT_EQUAL       23
%define TOK_LESS            24
%define TOK_LESS_EQUAL      25
%define TOK_GREATER         26
%define TOK_GREATER_EQUAL   27
%define TOK_AND             28
%define TOK_OR              29
%define TOK_NOT             30
%define TOK_BIT_AND         31
%define TOK_BIT_OR          32
%define TOK_BIT_XOR         33
%define TOK_BIT_NOT         34
%define TOK_SHIFT_LEFT      35
%define TOK_SHIFT_RIGHT     36
%define TOK_PLUS_ASSIGN     37
%define TOK_MINUS_ASSIGN    38
%define TOK_STAR_ASSIGN     39
%define TOK_SLASH_ASSIGN    40
%define TOK_INCREMENT       41
%define TOK_DECREMENT       42
%define TOK_ARROW           43
%define TOK_SCOPE           44
%define TOK_QUESTION        45
%define TOK_ERROR           46

%define AST_MODULE          1
%define AST_BLOCK           2
%define AST_CALL             3
%define AST_IDENTIFIER       4
%define AST_INTEGER          5
%define AST_FLOAT            6
%define AST_STRING           7
%define AST_BINARY           8
%define AST_UNARY            9
%define AST_MEMBER          10
%define AST_ARGUMENTS       11

%define NODE_SIZE           40
%define NODE_CAPACITY       4096
%define MAX_DEPTH           256

%define ERR_NONE             0
%define ERR_UNEXPECTED      -1
%define ERR_EXPECTED_TOKEN  -2
%define ERR_DEPTH           -3
%define ERR_NODE_CAPACITY   -4
%define ERR_ARGUMENT        -5
%define ERR_EXPRESSION      -6

section .bss
parser_tokens       resq 1
parser_token_count  resq 1
parser_token_index  resq 1
parser_nodes        resq 1
parser_node_count   resq 1
parser_error        resd 1
parser_depth        resd 1
parser_expected     resd 1
parser_current     resq 1
parser_root        resq 1

section .text

ferric_parser_init:
    mov [parser_tokens], rcx
    mov [parser_token_count], rdx
    mov [parser_nodes], r8
    mov qword [parser_token_index], 0
    mov qword [parser_node_count], 0
    mov dword [parser_error], ERR_NONE
    mov dword [parser_depth], 0
    mov dword [parser_expected], 0
    mov qword [parser_current], 0
    mov qword [parser_root], 0
    xor eax, eax
    ret

ferric_parser_error:
    mov eax, [parser_error]
    ret

ferric_parse:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40

    mov r12, rcx
    mov r13, rdx
    mov r14, r8
    mov r15, r9

    mov [parser_tokens], r12
    mov [parser_token_count], r13
    mov [parser_nodes], r14
    mov qword [parser_token_index], 0
    mov qword [parser_node_count], 0
    mov dword [parser_error], ERR_NONE
    mov dword [parser_depth], 0

    call parser_parse_program
    test eax, eax
    js .parse_failed

    mov eax, [parser_error]
    test eax, eax
    jnz .parse_failed

    mov rax, [parser_node_count]
    mov [r15], rax
    xor eax, eax
    jmp .parse_return

.parse_failed:
    mov [r15], rax

.parse_return:
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

parser_peek:
    mov rax, [parser_token_index]
    cmp rax, [parser_token_count]
    jae .peek_eof

    imul rax, 24
    mov rdx, [parser_tokens]
    add rdx, rax
    mov eax, [rdx]
    ret

.peek_eof:
    xor eax, eax
    ret

parser_advance:
    mov rax, [parser_token_index]
    cmp rax, [parser_token_count]
    jae .advance_eof

    imul rax, 24
    mov rdx, [parser_tokens]
    add rdx, rax
    mov [parser_current], rdx
    mov eax, [rdx]
    inc qword [parser_token_index]
    ret

.advance_eof:
    xor eax, eax
    ret

parser_expect:
    mov [parser_expected], ecx
    call parser_advance
    cmp eax, [parser_expected]
    jne .expect_error
    xor eax, eax
    ret

.expect_error:
    mov dword [parser_error], ERR_EXPECTED_TOKEN
    mov eax, ERR_EXPECTED_TOKEN
    ret

parser_new_node:
    mov rax, [parser_node_count]
    cmp rax, NODE_CAPACITY
    jae .node_error

    imul rax, NODE_SIZE
    mov rdx, [parser_nodes]
    add rdx, rax

    mov dword [rdx], ecx
    mov dword [rdx+4], 0
    mov qword [rdx+8], 0
    mov qword [rdx+16], 0
    mov qword [rdx+24], 0
    mov qword [rdx+32], 0

    inc qword [parser_node_count]
    mov rax, rdx
    ret

.node_error:
    mov dword [parser_error], ERR_NODE_CAPACITY
    xor eax, eax
    ret

parser_parse_program:
    mov ecx, AST_MODULE
    call parser_new_node
    test rax, rax
    jz .program_error

    mov [parser_root], rax

.program_loop:
    call parser_peek
    test eax, eax
    jz .program_done

    call parser_parse_statement
    test rax, rax
    jz .program_error

    ; Expression parsing uses RBX internally, so always reload the module
    ; root from parser state after returning from a statement.
    mov rbx, [parser_root]
    mov rdx, [rbx+16]
    test rdx, rdx
    jnz .program_append

    mov [rbx+16], rax
    jmp .program_loop

.program_append:
    mov rcx, rdx

.program_find_tail:
    mov rdx, [rcx+24]
    test rdx, rdx
    jz .program_attach
    mov rcx, rdx
    jmp .program_find_tail

.program_attach:
    mov [rcx+24], rax
    jmp .program_loop

.program_done:
    ; ferric_parse returns a status code, not an AST pointer. The module
    ; is node zero in the caller-provided AST buffer.
    xor eax, eax
    ret

.program_error:
    cmp dword [parser_error], ERR_NONE
    jne .program_error_return
    mov dword [parser_error], ERR_UNEXPECTED
.program_error_return:
    mov eax, ERR_UNEXPECTED
    ret

parser_parse_statement:
    call parser_parse_expression
    test rax, rax
    jz .statement_error

    mov rbx, rax
    call parser_peek

    cmp eax, TOK_SEMICOLON
    jne .statement_optional_semicolon

    call parser_advance
    mov rax, rbx
    ret

.statement_optional_semicolon:
    cmp eax, TOK_RBRACE
    je .statement_ok
    cmp eax, TOK_EOF
    je .statement_ok

    mov dword [parser_error], ERR_EXPECTED_TOKEN
    xor eax, eax
    ret

.statement_ok:
    mov rax, rbx
    ret

.statement_error:
    xor eax, eax
    ret

parser_parse_expression:
    call parser_parse_binary
    ret

parser_parse_binary:
    call parser_parse_postfix
    test rax, rax
    jz .binary_error

    mov rbx, rax

.binary_loop:
    call parser_peek

    cmp eax, TOK_PLUS
    jb .binary_done
    cmp eax, TOK_OR
    ja .binary_done

    mov r12d, eax
    call parser_advance

    call parser_parse_postfix
    test rax, rax
    jz .binary_error

    mov r13, rax
    mov ecx, AST_BINARY
    call parser_new_node
    test rax, rax
    jz .binary_error

    mov [rax+8], rbx
    mov [rax+16], r13
    mov [rax+4], r12d
    mov rbx, rax
    jmp .binary_loop

.binary_done:
    mov rax, rbx
    ret

.binary_error:
    xor eax, eax
    ret

parser_parse_postfix:
    call parser_parse_primary
    test rax, rax
    jz .postfix_error

    mov rbx, rax

.postfix_loop:
    call parser_peek

    cmp eax, TOK_LPAREN
    je .postfix_call

    cmp eax, TOK_DOT
    je .postfix_member

    jmp .postfix_done

.postfix_call:
    call parser_advance

    mov ecx, AST_CALL
    call parser_new_node
    test rax, rax
    jz .postfix_error

    mov [rax+8], rbx
    mov r12, rax

    call parser_peek
    cmp eax, TOK_RPAREN
    je .postfix_empty_args

    mov ecx, AST_ARGUMENTS
    call parser_new_node
    test rax, rax
    jz .postfix_error

    mov r13, rax

.postfix_arg_loop:
    call parser_parse_expression
    test rax, rax
    jz .postfix_error

    mov rdx, [r13+16]
    test rdx, rdx
    jnz .postfix_arg_append

    mov [r13+16], rax
    jmp .postfix_arg_after

.postfix_arg_append:
    mov rcx, rdx

.postfix_arg_tail:
    mov rdx, [rcx+24]
    test rdx, rdx
    jz .postfix_arg_attach
    mov rcx, rdx
    jmp .postfix_arg_tail

.postfix_arg_attach:
    mov [rcx+24], rax

.postfix_arg_after:
    call parser_peek
    cmp eax, TOK_COMMA
    jne .postfix_args_done
    call parser_advance
    jmp .postfix_arg_loop

.postfix_args_done:
    mov [r12+16], r13

    mov ecx, TOK_RPAREN
    call parser_expect
    test eax, eax
    js .postfix_error

    mov rbx, r12
    jmp .postfix_loop

.postfix_empty_args:
    call parser_advance
    mov rbx, r12
    jmp .postfix_loop

.postfix_member:
    call parser_advance
    mov ecx, TOK_IDENTIFIER
    call parser_expect
    test eax, eax
    js .postfix_error

    mov r12, [parser_current]

    mov ecx, AST_MEMBER
    call parser_new_node
    test rax, rax
    jz .postfix_error

    mov [rax+8], rbx
    mov rdx, [r12+8]
    mov [rax+16], rdx
    mov rbx, rax
    jmp .postfix_loop

.postfix_done:
    mov rax, rbx
    ret

.postfix_error:
    xor eax, eax
    ret

parser_parse_primary:
    call parser_advance
    mov r12d, eax

    cmp eax, TOK_IDENTIFIER
    je .primary_identifier
    cmp eax, TOK_KEYWORD
    je .primary_identifier
    cmp eax, TOK_INTEGER
    je .primary_integer
    cmp eax, TOK_FLOAT
    je .primary_float
    cmp eax, TOK_STRING
    je .primary_string
    cmp eax, TOK_LPAREN
    je .primary_group

    mov dword [parser_error], ERR_EXPRESSION
    xor eax, eax
    ret

.primary_identifier:
    mov ecx, AST_IDENTIFIER
    jmp .primary_token

.primary_integer:
    mov ecx, AST_INTEGER
    jmp .primary_token

.primary_float:
    mov ecx, AST_FLOAT
    jmp .primary_token

.primary_string:
    mov ecx, AST_STRING

.primary_token:
    call parser_new_node
    test rax, rax
    jz .primary_error

    mov rdx, [parser_current]
    mov ecx, [rdx+4]
    mov [rax+8], rcx
    mov ecx, [rdx+8]
    mov [rax+16], rcx
    ret

.primary_group:
    call parser_parse_expression
    test rax, rax
    jz .primary_error

    mov rbx, rax
    mov ecx, TOK_RPAREN
    call parser_expect
    test eax, eax
    js .primary_error

    mov rax, rbx
    ret

.primary_error:
    xor eax, eax
    ret
