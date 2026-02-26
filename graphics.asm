; graphics.asm 
; Graphics routines

; print_string
; init_bios_charset_ptr
; write_string
; fill_rect
; fill_rect_8px_aligned
; clear_screen

; ------------------------------
; Print ASCIIZ string at DS:SI using BIOS teletype.
print_string:
    push ax
    push bx
.next_char:
    lodsb
    or al, al
    jz .done
    mov ah, 0Eh
    xor bh, bh
    mov bl, 15
    int 10h
    jmp .next_char
.done:
    pop bx
    pop ax
    ret

; ------------------------------
; Cache BIOS character set bitmap pointer into bios_charset_ptr (offset,segment). Only works on EGA +
; Prefer INT 10h AX=1130h BH=00h (INT 1Fh 8x8 graphics font pointer),
; then fall back to reading INT 1Fh vector directly from IVT.
get_ega_bios_charset_ptr:
    push es
    push bp
    push bx

    mov ax, 1130h
    mov bh, 03h
    int 10h
    mov [bios_charset_ptr], bp
    mov [bios_charset_ptr+2], es

    mov ax, [bios_charset_ptr]
    or ax, [bios_charset_ptr+2]
    jnz .done

    mov ah, 35h
    mov al, 1Fh
    int 21h
    mov [bios_charset_ptr], bx
    mov [bios_charset_ptr+2], es

.done:
    pop bx
    pop bp
    pop es
    ret

; ------------------------------
; Draw ASCIIZ string in graphics mode using BIOS charset bitmaps.
; Stack params (word): str_ptr, x, y, color_mask.
; Uses color_mask on even scanlines, and color_mask rotated right by 2 on odd scanlines.
; Assumes x is 4-pixel aligned.
write_string:
    push bp
    mov bp, sp
    push si
    push di
    sub sp, 20

    mov al, [bp+10]                ; color_mask low byte
    mov [bp-2], al                 ; even mask
    mov cl, 2
    ror al, cl
    mov [bp-4], al                 ; odd mask

    mov ax, [bp+6]                 ; x
    shr ax, 1
    shr ax, 1
    mov [bp-6], ax                 ; current x byte offset
    mov ax, [bp+8]                 ; y
    mov [bp-8], ax                 ; base y

    mov si, [bp+4]                 ; string pointer (DS:SI)

.char_loop:
    lodsb
    or al, al
    jz .done

    xor ah, ah
    shl ax, 1
    shl ax, 1
    shl ax, 1                      ; AX = char_code * 8
    add ax, [bios_charset_ptr]     ; AX = glyph base offset in font segment
    mov [bp-20], ax
    mov word [bp-10], 0            ; row = 0

.row_loop:
    ; Read one font row byte from BIOS charset pointer using DS.
    push ds
    mov bx, [bp-20]
    mov ax, [bios_charset_ptr+2]
    mov ds, ax
    mov al, [bx]
    pop ds
    mov [bp-14], al
    inc bx
    mov [bp-20], bx

    ; Select row mask based on absolute scanline parity.
    mov ax, [bp-8]
    add ax, [bp-10]
    test al, 1
    jz .row_even
    mov dl, [bp-4]
    jmp .row_mask_ready
.row_even:
    mov dl, [bp-2]
.row_mask_ready:

    ; Compute destination row base in video memory.
    mov ax, [bp-8]
    add ax, [bp-10]
    shl ax, 1
    mov bx, ax
    mov di, [y_base+bx]
    mov ax, [start_addr]
    shl ax, 1
    add di, ax
    add di, [bp-6]

    ; Left 4 pixels (font bits 7..4) -> destination byte [ES:DI].
    mov al, [bp-14]
    mov cl, 4
    shr al, cl
    and al, 0Fh
    xor bh, bh
    mov bl, al
    mov al, [write_string_nibble_to_pair_mask+bx]
    mov ah, al
    and al, dl
    not ah
    mov bl, [es:di]
    and bl, ah
    or bl, al
    mov [es:di], bl

    ; Right 4 pixels (font bits 3..0) -> destination byte [ES:DI+1].
    mov al, [bp-14]
    and al, 0Fh
    xor bh, bh
    mov bl, al
    mov al, [write_string_nibble_to_pair_mask+bx]
    mov ah, al
    and al, dl
    not ah
    mov bl, [es:di+1]
    and bl, ah
    or bl, al
    mov [es:di+1], bl

    inc word [bp-10]
    cmp word [bp-10], 8
    jb .row_loop

    add word [bp-6], 2
    jmp .char_loop

.done:
    add sp, 20
    pop di
    pop si
    pop bp
    ret

write_string_nibble_to_pair_mask:
    db 00h,03h,0Ch,0Fh,30h,33h,3Ch,3Fh,0C0h,0C3h,0CCh,0CFh,0F0h,0F3h,0FCh,0FFh


; -----------------------------
; Fill rectangle (x1,y1)-(x2,y2) with a 4-pixel byte pattern.
; Stack params (word): x1, y1, x2, y2, pattern_byte.
; Alternates scanlines by rotating the pattern right by 2 bits.
fill_rect:
    push bp
    mov bp, sp
    push si
    push di
    sub sp, 2
    mov al, [bp+4]
    mov [bp-2], al
    mov si, [bp+10]    ; y1
.y_loop:
    ; Base pattern on even rows relative to y1, rotated pattern on odd rows.
    mov al, [bp-2]
    mov dx, si
    sub dx, [bp+10]
    test dl, 1
    jz .pattern_ready
    mov cl, 2
    ror al, cl
.pattern_ready:
    push ax             ; save ax which is used for color/pattern
    ; Compute scanline base offset in BX
    mov bx, si
    mov ax, bx
    and bx, 1
    mov cl, 13
    shl bx, cl         ; (y & 1) * 0x2000
    shr ax, 1
    mov dx, ax
    mov cl, 6
    shl dx, cl          ; (y >> 1) * 64
    mov cl, 4
    shl ax, cl          ; (y >> 1) * 16
    add dx, ax         ; (y >> 1) * 80
    add bx, dx         ; line base
    ; Apply scroll offset so drawing matches displayed position
    mov ax, [start_addr]
    shl ax, 1          ; words -> bytes
    add bx, ax
    ; Byte offsets for start/end
    mov ax, [bp+12]    ; x1
    mov cl, 2
    shr ax, cl          ; start byte
    add ax, bx         ; start offset
    mov di, ax
    mov ax, [bp+8]     ; x2
    mov cl, 2
    shr ax, cl          ; end byte
    add ax, bx         ; end offset
    mov bx, ax
    cmp di, bx
    pop ax       ; restore color/pattern
    je .single_byte

    ; First (partial) byte: keep left pixels before x1
    mov dx, [bp+12]    ; x1
    and dl, 3
    mov cl, 4
    sub cl, dl
    shl cl, 1
    mov dl, 0FFh
    shl dl, cl         ; keep-left mask
    mov ah, [es:di]
    and ah, dl
    mov dh, dl
    not dh             ; write mask
    mov dl, al
    and dl, dh
    or ah, dl
    mov [es:di], ah

    ; Middle full bytes
    inc di
    cmp di, bx
    jge .last_byte
.mid_loop:
    mov [es:di], al
    inc di
    cmp di, bx
    jl .mid_loop

.last_byte:
    ; Last (partial) byte: keep right pixels after x2
    mov dx, [bp+8]     ; x2
    and dl, 3
    mov cl, 3
    sub cl, dl
    shl cl, 1
    mov dl, 1
    shl dl, cl
    dec dl             ; keep-right mask
    mov ah, [es:bx]
    and ah, dl
    mov dh, dl
    not dh             ; write mask
    mov dl, al
    and dl, dh
    or ah, dl
    mov [es:bx], ah
    jmp .next_row

.single_byte:
    ; Single byte: keep left of x1 and right of x2
    mov dx, [bp+12]    ; x1
    and dl, 3
    mov cl, 4
    sub cl, dl
    shl cl, 1
    mov ah, 0FFh
    shl ah, cl         ; keep-left mask (in AH)
    mov dx, [bp+8]     ; x2
    and dl, 3
    mov cl, 3
    sub cl, dl
    shl cl, 1
    mov dl, 1
    shl dl, cl
    dec dl             ; keep-right mask (in DL)
    or dl, ah          ; combined keep mask (in DL)
    mov ah, [es:di]
    and ah, dl
    mov dh, dl
    not dh             ; write mask
    mov dl, al
    and dl, dh
    or ah, dl
    mov [es:di], ah

.next_row:

    inc si
    cmp si, [bp+6]     ; y2
    jbe .y_loop

    add sp, 2
    pop di
    pop si
    pop bp
    ret


; -----------------------------
; Fill 8-pixel wide rectangle at aligned X with a 4-pixel byte pattern.
; Stack params (word): x, y1, y2, pattern_byte.
; Assumptions:
; - width is fixed at 8 pixels (2 bytes in mode 4)
; - x is aligned to an 8-pixel boundary
; - odd scanlines use pattern rotated right by 2 bits
fill_rect_8px_aligned:
    push bp
    mov bp, sp
    push si
    push di
    sub sp, 2

    ; Build base and odd-row (rotated) pattern words.
    mov al, [bp+4]
    mov ah, al
    mov dx, ax         ; DX = base pattern word
    mov cl, 2
    ror al, cl
    mov ah, al
    mov [bp-2], ax     ; [bp-2] = rotated pattern word

    ; Precompute x byte offset (x / 4), valid because x is 8-pixel aligned.
    mov di, [bp+10]
    shr di, 1
    shr di, 1

    ; Compute starting video offset for (x, y1), including scroll.
    ; Use y_base lookup to avoid recomputing CGA row addressing math.
    mov bx, [bp+8]     ; y1
    shl bx, 1
    mov bx, [y_base+bx]
    mov ax, [start_addr]
    shl ax, 1          ; words -> bytes
    add bx, ax
    add bx, di

    ; total_rows = (y2 - y1 + 1)
    mov cx, [bp+6]
    sub cx, [bp+8]
    inc cx
    mov si, cx
    push bx                    ; save y1 base for second pass

    ; Pass 1: y1, y1+2, y1+4, ...
    mov ax, cx
    inc ax
    shr ax, 1                  ; ceil(total_rows/2)
    mov cx, ax
.first_rows_loop:
    mov [es:bx], dx
    add bx, 80                 ; same parity next row
    loop .first_rows_loop

    ; Pass 2: y1+1, y1+3, y1+5, ...
    pop bx
    mov cx, si
    shr cx, 1                  ; floor(total_rows/2)
    jcxz .rows_done
    cmp bx, 2000h
    jb .second_from_even
    sub bx, 8112               ; odd plane -> next even row
    jmp .second_rows_loop
.second_from_even:
    add bx, 8192               ; even plane -> next odd row
.second_rows_loop:
    mov ax, [bp-2]
    mov [es:bx], ax
    add bx, 80                 ; same parity next row
    loop .second_rows_loop
.rows_done:

    add sp, 2
    pop di
    pop si
    pop bp
    ret

; -----------------------------
; clear screen
clear_screen:
    xor ax, ax
    push ax
    push ax
    mov ax, HSIZE-1
    push ax
    mov ax, 199
    push ax
    xor ax, ax
    push ax
    call fill_rect
    add sp, 10
    ret
