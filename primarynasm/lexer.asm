
bits 64
default rel

global ferric_lex

%define TOK_EOF 0
%define TOK_IDENTIFIER 1
%define TOK_KEYWORD 2
%define TOK_INTEGER 3
%define TOK_FLOAT 4
%define TOK_STRING 5
%define TOK_LPAREN 6
%define TOK_RPAREN 7
%define TOK_LBRACE 8
%define TOK_RBRACE 9
%define TOK_LBRACKET 10
%define TOK_RBRACKET 11
%define TOK_COMMA 12
%define TOK_SEMICOLON 13
%define TOK_COLON 14
%define TOK_DOT 15
%define TOK_PLUS 16
%define TOK_MINUS 17
%define TOK_STAR 18
%define TOK_SLASH 19
%define TOK_PERCENT 20
%define TOK_ASSIGN 21
%define TOK_EQUAL 22
%define TOK_NOT_EQUAL 23
%define TOK_LESS 24
%define TOK_LESS_EQUAL 25
%define TOK_GREATER 26
%define TOK_GREATER_EQUAL 27
%define TOK_AND 28
%define TOK_OR 29
%define TOK_NOT 30
%define TOK_BIT_AND 31
%define TOK_BIT_OR 32
%define TOK_BIT_XOR 33
%define TOK_BIT_NOT 34
%define TOK_SHIFT_LEFT 35
%define TOK_SHIFT_RIGHT 36
%define TOK_PLUS_ASSIGN 37
%define TOK_MINUS_ASSIGN 38
%define TOK_STAR_ASSIGN 39
%define TOK_SLASH_ASSIGN 40
%define TOK_INCREMENT 41
%define TOK_DECREMENT 42
%define TOK_ARROW 43
%define TOK_SCOPE 44
%define TOK_QUESTION 45
%define TOK_ERROR 46

%define ERR_INVALID_CHAR -1
%define ERR_UNTERMINATED_STRING -2
%define ERR_UNTERMINATED_COMMENT -3
%define ERR_TOKEN_CAPACITY -4
%define ERR_INVALID_NUMBER -5
%define ERR_INVALID_ESCAPE -6

%define TOKEN_SIZE 24

section .text

; ferric_lex(source, source_length, token_buffer, token_capacity)
; Windows x64 ABI.
; Token: type dword, offset dword, length dword,
;        line dword, column dword, reserved dword.
; Returns token count including EOF, or a negative error.

ferric_lex:
    push rbp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40

    mov rbx, rcx
    mov rsi, rdx
    mov rdi, r8
    mov r12, r9
    xor r13d, r13d
    mov r14d, 1
    xor r15d, r15d

    test rbx, rbx
    jz .invalid_char
    test rdi, rdi
    jz .capacity_error

.next:
    cmp r13, rsi
    jae .eof

    movzx eax, byte [rbx+r13]

    cmp al, ' '
    je .space
    cmp al, 9
    je .space
    cmp al, 10
    je .newline
    cmp al, 13
    je .carriage
    cmp al, '/'
    je .slash_check

    mov rbp, r13
    mov [rsp+32], r14
    mov [rsp+24], r15

    cmp al, '"'
    je .string_start

    cmp al, '0'
    jb .identifier_check
    cmp al, '9'
    jbe .number_start

.identifier_check:
    cmp al, 'A'
    jb .lower_check
    cmp al, 'Z'
    jbe .identifier_start

.lower_check:
    cmp al, 'a'
    jb .underscore_check
    cmp al, 'z'
    jbe .identifier_start

.underscore_check:
    cmp al, '_'
    je .identifier_start
    jmp .punctuation

.space:
    inc r13
    inc r15
    jmp .next

.newline:
    inc r13
    inc r14
    xor r15d, r15d
    jmp .next

.carriage:
    inc r13
    cmp r13, rsi
    jae .next
    cmp byte [rbx+r13], 10
    jne .next
    inc r13
    inc r14
    xor r15d, r15d
    jmp .next

.slash_check:
    lea rax, [r13+1]
    cmp rax, rsi
    jae .punctuation
    movzx eax, byte [rbx+r13+1]
    cmp al, '/'
    je .line_comment
    cmp al, '*'
    je .block_comment
    jmp .punctuation

.line_comment:
    add r13, 2
    add r15, 2
.line_comment_loop:
    cmp r13, rsi
    jae .next
    movzx eax, byte [rbx+r13]
    cmp al, 10
    je .next
    cmp al, 13
    je .next
    inc r13
    inc r15
    jmp .line_comment_loop

.block_comment:
    add r13, 2
    add r15, 2
.block_comment_loop:
    cmp r13, rsi
    jae .comment_error
    movzx eax, byte [rbx+r13]
    cmp al, '*'
    je .block_star
    cmp al, 10
    je .block_newline
    cmp al, 13
    je .block_carriage
    inc r13
    inc r15
    jmp .block_comment_loop

.block_star:
    lea rax, [r13+1]
    cmp rax, rsi
    jae .block_ordinary
    cmp byte [rbx+r13+1], '/'
    je .block_end
.block_ordinary:
    inc r13
    inc r15
    jmp .block_comment_loop

.block_newline:
    inc r13
    inc r14
    xor r15d, r15d
    jmp .block_comment_loop

.block_carriage:
    inc r13
    cmp r13, rsi
    jae .block_comment_loop
    cmp byte [rbx+r13], 10
    jne .block_comment_loop
    inc r13
    inc r14
    xor r15d, r15d
    jmp .block_comment_loop

.block_end:
    add r13, 2
    add r15, 2
    jmp .next

.identifier_start:
    inc r13
    inc r15
.identifier_loop:
    cmp r13, rsi
    jae .identifier_end
    movzx eax, byte [rbx+r13]
    cmp al, 'A'
    jb .identifier_lower
    cmp al, 'Z'
    jbe .identifier_advance
.identifier_lower:
    cmp al, 'a'
    jb .identifier_digit
    cmp al, 'z'
    jbe .identifier_advance
.identifier_digit:
    cmp al, '0'
    jb .identifier_underscore
    cmp al, '9'
    jbe .identifier_advance
.identifier_underscore:
    cmp al, '_'
    je .identifier_advance
    jmp .identifier_end
.identifier_advance:
    inc r13
    inc r15
    jmp .identifier_loop

.identifier_end:
    mov eax, TOK_IDENTIFIER
    mov rcx, r13
    sub rcx, rbp
    cmp rcx, 2
    je .keyword_two
    cmp rcx, 3
    je .keyword_three
    cmp rcx, 4
    je .keyword_four
    cmp rcx, 5
    je .keyword_five
    cmp rcx, 6
    je .keyword_six
    jmp .emit

.keyword_two:
    cmp word [rbx+rbp], 'if'
    je .keyword_mark
    cmp word [rbx+rbp], 'in'
    je .keyword_mark
    jmp .emit

.keyword_three:
    cmp dword [rbx+rbp], 'int'
    je .keyword_mark
    cmp dword [rbx+rbp], 'for'
    je .keyword_mark
    jmp .emit

.keyword_four:
    cmp dword [rbx+rbp], 'void'
    je .keyword_mark
    cmp dword [rbx+rbp], 'text'
    je .keyword_mark
    cmp dword [rbx+rbp], 'true'
    je .keyword_mark
    cmp dword [rbx+rbp], 'null'
    je .keyword_mark
    cmp dword [rbx+rbp], 'else'
    je .keyword_mark
    cmp dword [rbx+rbp], 'bool'
    je .keyword_mark
    jmp .emit

.keyword_five:
    cmp dword [rbx+rbp], 'fals'
    jne .keyword_float
    cmp byte [rbx+rbp+4], 'e'
    je .keyword_mark
.keyword_float:
    cmp dword [rbx+rbp], 'floa'
    jne .keyword_while
    cmp byte [rbx+rbp+4], 't'
    je .keyword_mark
.keyword_while:
    cmp dword [rbx+rbp], 'whil'
    jne .keyword_break
    cmp byte [rbx+rbp+4], 'e'
    je .keyword_mark
.keyword_break:
    cmp dword [rbx+rbp], 'brea'
    jne .keyword_const
    cmp byte [rbx+rbp+4], 'k'
    je .keyword_mark
.keyword_const:
    cmp dword [rbx+rbp], 'cons'
    jne .emit
    cmp byte [rbx+rbp+4], 't'
    je .keyword_mark
    jmp .emit

.keyword_six:
    cmp dword [rbx+rbp], 'modu'
    jne .keyword_return
    cmp word [rbx+rbp+4], 'le'
    je .keyword_mark
.keyword_return:
    cmp dword [rbx+rbp], 'retu'
    jne .keyword_import
    cmp word [rbx+rbp+4], 'rn'
    je .keyword_mark
.keyword_import:
    cmp dword [rbx+rbp], 'impo'
    jne .keyword_public
    cmp word [rbx+rbp+4], 'rt'
    je .keyword_mark
.keyword_public:
    cmp dword [rbx+rbp], 'publ'
    jne .keyword_double
    cmp word [rbx+rbp+4], 'ic'
    je .keyword_mark
.keyword_double:
    cmp dword [rbx+rbp], 'doub'
    jne .emit
    cmp word [rbx+rbp+4], 'le'
    je .keyword_mark
    jmp .emit

.keyword_mark:
    mov eax, TOK_KEYWORD
    jmp .emit

.number_start:
    xor r8d, r8d
    xor r9d, r9d
.number_loop:
    cmp r13, rsi
    jae .number_end
    movzx eax, byte [rbx+r13]
    cmp al, '0'
    jb .number_dot
    cmp al, '9'
    ja .number_dot
    inc r13
    inc r15
    jmp .number_loop

.number_dot:
    cmp al, '.'
    jne .number_exp
    cmp r8d, 0
    jne .number_end
    lea rcx, [r13+1]
    cmp rcx, rsi
    jae .number_end
    movzx ecx, byte [rbx+r13+1]
    cmp cl, '0'
    jb .number_end
    cmp cl, '9'
    ja .number_end
    mov r8d, 1
    inc r13
    inc r15
    jmp .number_loop

.number_exp:
    cmp al, 'e'
    je .number_exponent
    cmp al, 'E'
    jne .number_end
.number_exponent:
    cmp r9d, 0
    jne .number_end
    mov r9d, 1
    mov r8d, 1
    inc r13
    inc r15
    cmp r13, rsi
    jae .number_error
    movzx eax, byte [rbx+r13]
    cmp al, '+'
    je .number_sign
    cmp al, '-'
    je .number_sign
    jmp .number_exp_digit
.number_sign:
    inc r13
    inc r15
.number_exp_digit:
    cmp r13, rsi
    jae .number_error
    movzx eax, byte [rbx+r13]
    cmp al, '0'
    jb .number_error
    cmp al, '9'
    ja .number_error
    jmp .number_loop

.number_end:
    mov eax, TOK_INTEGER
    test r8d, r8d
    jz .emit
    mov eax, TOK_FLOAT
    jmp .emit

.number_error:
    mov eax, ERR_INVALID_NUMBER
    jmp .return_error

.string_start:
    inc r13
    inc r15
.string_loop:
    cmp r13, rsi
    jae .string_error
    movzx eax, byte [rbx+r13]
    cmp al, '"'
    je .string_end
    cmp al, 10
    je .string_error
    cmp al, 13
    je .string_error
    cmp al, 92
    je .string_escape
    inc r13
    inc r15
    jmp .string_loop
.string_escape:
    inc r13
    inc r15
    cmp r13, rsi
    jae .string_error
    movzx eax, byte [rbx+r13]
    cmp al, 'n'
    je .escape_valid
    cmp al, 'r'
    je .escape_valid
    cmp al, 't'
    je .escape_valid
    cmp al, '0'
    je .escape_valid
    cmp al, 92
    je .escape_valid
    cmp al, '"'
    je .escape_valid
    mov eax, ERR_INVALID_ESCAPE
    jmp .return_error
.escape_valid:
    inc r13
    inc r15
    jmp .string_loop
.string_end:
    inc r13
    inc r15
    mov eax, TOK_STRING
    jmp .emit
.string_error:
    mov eax, ERR_UNTERMINATED_STRING
    jmp .return_error

.punctuation:
    movzx eax, byte [rbx+r13]
    cmp al, '('
    je .p_lparen
    cmp al, ')'
    je .p_rparen
    cmp al, '{'
    je .p_lbrace
    cmp al, '}'
    je .p_rbrace
    cmp al, '['
    je .p_lbracket
    cmp al, ']'
    je .p_rbracket
    cmp al, ','
    je .p_comma
    cmp al, ';'
    je .p_semicolon
    cmp al, ':'
    je .p_colon
    cmp al, '.'
    je .p_dot
    cmp al, '+'
    je .p_plus
    cmp al, '-'
    je .p_minus
    cmp al, '*'
    je .p_star
    cmp al, '/'
    je .p_slash
    cmp al, '%'
    je .p_percent
    cmp al, '='
    je .p_equal
    cmp al, '!'
    je .p_not
    cmp al, '<'
    je .p_less
    cmp al, '>'
    je .p_greater
    cmp al, '&'
    je .p_and
    cmp al, '|'
    je .p_or
    cmp al, '^'
    je .p_xor
    cmp al, '~'
    je .p_bit_not
    cmp al, '?'
    je .p_question
    mov eax, ERR_INVALID_CHAR
    jmp .return_error

.p_lparen: mov eax, TOK_LPAREN
    jmp .single
.p_rparen: mov eax, TOK_RPAREN
    jmp .single
.p_lbrace: mov eax, TOK_LBRACE
    jmp .single
.p_rbrace: mov eax, TOK_RBRACE
    jmp .single
.p_lbracket: mov eax, TOK_LBRACKET
    jmp .single
.p_rbracket: mov eax, TOK_RBRACKET
    jmp .single
.p_comma: mov eax, TOK_COMMA
    jmp .single
.p_semicolon: mov eax, TOK_SEMICOLON
    jmp .single
.p_dot: mov eax, TOK_DOT
    jmp .single
.p_percent: mov eax, TOK_PERCENT
    jmp .single
.p_bit_not: mov eax, TOK_BIT_NOT
    jmp .single
.p_question: mov eax, TOK_QUESTION
    jmp .single
.p_colon:
    mov eax, TOK_COLON
    jmp .check_scope
.p_plus:
    mov eax, TOK_PLUS
    jmp .check_plus
.p_minus:
    mov eax, TOK_MINUS
    jmp .check_minus
.p_star:
    mov eax, TOK_STAR
    jmp .check_star
.p_slash:
    mov eax, TOK_SLASH
    jmp .check_slash
.p_equal:
    mov eax, TOK_ASSIGN
    jmp .check_equal
.p_not:
    mov eax, TOK_NOT
    jmp .check_not_equal
.p_less:
    mov eax, TOK_LESS
    jmp .check_less
.p_greater:
    mov eax, TOK_GREATER
    jmp .check_greater
.p_and:
    mov eax, TOK_BIT_AND
    jmp .check_and
.p_or:
    mov eax, TOK_BIT_OR
    jmp .check_or
.p_xor:
    mov eax, TOK_BIT_XOR
    jmp .single

.check_scope:
    lea rcx, [r13+1]
    cmp rcx, rsi
    jae .single
    cmp byte [rbx+r13+1], ':'
    jne .single
    mov eax, TOK_SCOPE
    jmp .double

.check_plus:
    lea rcx, [r13+1]
    cmp rcx, rsi
    jae .single
    cmp byte [rbx+r13+1], '+'
    je .plus_inc
    cmp byte [rbx+r13+1], '='
    je .plus_asg
    jmp .single
.plus_inc: mov eax, TOK_INCREMENT
    jmp .double
.plus_asg: mov eax, TOK_PLUS_ASSIGN
    jmp .double

.check_minus:
    lea rcx, [r13+1]
    cmp rcx, rsi
    jae .single
    cmp byte [rbx+r13+1], '-'
    je .minus_dec
    cmp byte [rbx+r13+1], '='
    je .minus_asg
    cmp byte [rbx+r13+1], '>'
    je .minus_arr
    jmp .single
.minus_dec: mov eax, TOK_DECREMENT
    jmp .double
.minus_asg: mov eax, TOK_MINUS_ASSIGN
    jmp .double
.minus_arr: mov eax, TOK_ARROW
    jmp .double

.check_star:
    lea rcx, [r13+1]
    cmp rcx, rsi
    jae .single
    cmp byte [rbx+r13+1], '='
    je .star_asg
    jmp .single
.star_asg: mov eax, TOK_STAR_ASSIGN
    jmp .double

.check_slash:
    lea rcx, [r13+1]
    cmp rcx, rsi
    jae .single
    cmp byte [rbx+r13+1], '='
    je .slash_asg
    jmp .single
.slash_asg: mov eax, TOK_SLASH_ASSIGN
    jmp .double

.check_equal:
    lea rcx, [r13+1]
    cmp rcx, rsi
    jae .single
    cmp byte [rbx+r13+1], '='
    je .equal_equal
    jmp .single
.equal_equal: mov eax, TOK_EQUAL
    jmp .double

.check_not_equal:
    lea rcx, [r13+1]
    cmp rcx, rsi
    jae .single
    cmp byte [rbx+r13+1], '='
    je .not_equal
    jmp .single
.not_equal: mov eax, TOK_NOT_EQUAL
    jmp .double

.check_less:
    lea rcx, [r13+1]
    cmp rcx, rsi
    jae .single
    cmp byte [rbx+r13+1], '='
    je .less_equal
    cmp byte [rbx+r13+1], '<'
    je .shift_left
    jmp .single
.less_equal: mov eax, TOK_LESS_EQUAL
    jmp .double
.shift_left: mov eax, TOK_SHIFT_LEFT
    jmp .double

.check_greater:
    lea rcx, [r13+1]
    cmp rcx, rsi
    jae .single
    cmp byte [rbx+r13+1], '='
    je .greater_equal
    cmp byte [rbx+r13+1], '>'
    je .shift_right
    jmp .single
.greater_equal: mov eax, TOK_GREATER_EQUAL
    jmp .double
.shift_right: mov eax, TOK_SHIFT_RIGHT
    jmp .double

.check_and:
    lea rcx, [r13+1]
    cmp rcx, rsi
    jae .single
    cmp byte [rbx+r13+1], '&'
    je .logical_and
    jmp .single
.logical_and: mov eax, TOK_AND
    jmp .double

.check_or:
    lea rcx, [r13+1]
    cmp rcx, rsi
    jae .single
    cmp byte [rbx+r13+1], '|'
    je .logical_or
    jmp .single
.logical_or: mov eax, TOK_OR
    jmp .double

.single:
    inc r13
    inc r15
    jmp .emit
.double:
    add r13, 2
    add r15, 2

.emit:
    ; EAX=type, token starts at RBP and ends at R13.
    cmp qword [rel_token_count], 0
    ; This label is replaced below by the actual counter slot.
    jmp .emit_impl

.emit_impl:
    mov [rsp+16], eax
    mov rax, [rel_token_count]
    cmp rax, r12
    jae .capacity_error
    imul rax, TOKEN_SIZE
    lea rdx, [rdi+rax]
    mov eax, [rsp+16]
    mov [rdx], eax
    mov eax, ebp
    mov [rdx+4], eax
    mov eax, r13d
    sub eax, ebp
    mov [rdx+8], eax
    mov eax, [rsp+32]
    mov [rdx+12], eax
    mov eax, [rsp+24]
    mov [rdx+16], eax
    mov dword [rdx+20], 0
    inc qword [rel_token_count]
    jmp .next

.eof:
    mov rax, [rel_token_count]
    cmp rax, r12
    jae .capacity_error
    imul rax, TOKEN_SIZE
    lea rdx, [rdi+rax]
    mov dword [rdx], TOK_EOF
    mov eax, r13d
    mov [rdx+4], eax
    mov dword [rdx+8], 0
    mov eax, r14d
    mov [rdx+12], eax
    mov eax, r15d
    mov [rdx+16], eax
    mov dword [rdx+20], 0
    inc qword [rel_token_count]
    mov rax, [rel_token_count]
    jmp .return

.comment_error:
    mov eax, ERR_UNTERMINATED_COMMENT
    jmp .return_error
.capacity_error:
    mov eax, ERR_TOKEN_CAPACITY
    jmp .return_error
.invalid_char:
    mov eax, ERR_INVALID_CHAR
.return_error:
    movsxd rax, eax
.return:
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

section .bss
rel_token_count resq 1
