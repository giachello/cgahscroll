; scancode.asm
; NASM .COM program: capture keyboard scancodes via INT 9h
org 100h

start:
    ; Set DS = CS
    push cs
    pop ds

    call install_int9

main_loop:
    ; Wait for a scancode in ring buffer
    cli
    mov al, [sc_head]
    cmp al, [sc_tail]
    sti
    jne .got_code
    cmp byte [esc_flag], 0
    jne exit_to_dos
    jmp main_loop

.got_code:
    cli
    mov al, [sc_tail]
    xor bx, bx
    mov bl, al
    inc al
    and al, 0Fh
    mov [sc_tail], al
    sti

.print:
    ; Print "SC:" then scancode in hex
    mov dx, msg_sc
    mov ah, 09h
    int 21h

    mov al, [sc_buf+bx]
    call print_hex8

    mov dx, msg_crlf
    mov ah, 09h
    int 21h

    jmp main_loop

exit_to_dos:
    call restore_int9
    mov ax, 4C00h
    int 21h

; -----------------------------
; INT 9h handler: read scancode, set flag, flush BIOS buffer
int9_handler:
    push ax
    push bx
    push ds

    push cs ; set DS = CS for accessing our data
    pop ds

    in al, 60h ; get scancode from keyboard controller

    ; Push scan code into ring buffer (overwrite oldest on full)
    xor bh, bh
    mov bl, [sc_head]

    mov [sc_buf+bx], al
    inc bl
    and bl, 0Fh
    cmp bl, [sc_tail]
    jne .store_head
    ; buffer full: advance tail
    mov bh, [sc_tail]
    inc bh
    and bh, 0Fh
    mov [sc_tail], bh
.store_head:
    mov [sc_head], bl
    cmp al, 01h ; is Esc key?
    jne .sendpic
    mov byte [esc_flag], 1

.sendpic:
    mov al, 20h
    out 20h, al

    pop ds
    pop bx
    pop ax
    iret

; -----------------------------
; Install INT 9h handler
install_int9:
    mov ah, 35h
    mov al, 09h
    int 21h
    mov [old9_off], bx
    mov [old9_seg], es
    mov dx, int9_handler
    mov ax, 2509h
    int 21h
    ret

; -----------------------------
; Restore original INT 9h handler
restore_int9:
    mov dx, [old9_off]
    mov ds, [old9_seg]
    mov ax, 2509h
    int 21h
    push cs
    pop ds
    ret

; -----------------------------
; Print AL as two hex digits
print_hex8:
    push ax
    shr al, 4
    call print_hex_nibble
    pop ax
    and al, 0Fh
    call print_hex_nibble
    ret

; -----------------------------
; Print AX as four hex digits
print_hex16:
    push ax
    mov al, ah
    call print_hex8
    pop ax
    call print_hex8
    ret

print_hex_nibble:
    and al, 0Fh
    add al, '0'
    cmp al, '9'
    jbe .out
    add al, 7
.out:
    mov ah, 0Eh
    mov bh, 0
    mov bl, 7
    int 10h
    ret

; -----------------------------
msg_sc   db 'Scancode: ', '$'
msg_crlf db 0Dh,0Ah,'$'

sc_head        db 0
sc_tail        db 0
sc_buf         times 16 db 0
esc_flag      db 0
old9_off dw 0
old9_seg dw 0
