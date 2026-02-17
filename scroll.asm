; cga_scroll_boxes.asm
; NASM .COM program
; Conventions: routines dont' save AX,BX,CX,DX, but do save SI,DI,BP,ES if used. Stack params are WORDs unless noted otherwise. Screen buffer is accessed via ES.

CLOCK_TICKS EQU 19912 ; number of PIT ticks for ~1/18.2 second delay (for smooth scrolling)
CGA_BASE EQU 0B800h

[map all scroll.map]
CPU 8086
section .text align=16
org 100h

start:
    ; Set DS = CS
    push cs
    pop ds
    ; Set ES = CGA base for direct screen access
    mov ax, CGA_BASE
    mov es, ax

    ; Switch to CGA 320x200 4-color mode (mode 4)
    mov ax, 0004h
    int 10h

    call install_int9 ; keyboard interrupt handler for non-blocking input
    call install_int1c ; timer tick handler for smooth scrolling (optional, can also just poll BIOS tick flag without chaining handler)
    mov ax, CLOCK_TICKS ; set clock to 59.94hz
    call set_pit_rate

    ; Seed RNG from BIOS timer tick
    mov ah, 00h
    int 1Ah            ; CX:DX = ticks since midnight
    mov [seed], dx

    ; Initialize sprites (capture background + draw)
    call init_sprites

    ; fill the top 2 scanlines (0,0)-(319,1) with color 2 to create a "status bar" area that won't show sprite corruption as they scroll up
    xor ax, ax
    push ax
    push ax
    mov ax, 319
    push ax
    mov ax, 1
    push ax
    mov ax, 2
    push ax          ; color 0 = black
    call fill_rect
    add sp, 10

    ; Scroll via CGA CRTC start address (infinite)
    mov word [start_addr], 0   ; start address in WORDS
scroll_loop:
    ; Wait for BIOS tick (INT 1Ch) to sync scrolling
.wait_tick:
    cmp byte [tick_flag], 0
    jne .got_tick
    jmp .wait_tick
.got_tick:
    inc word [ticks_elapsed]
    mov byte [tick_flag], 0
    test [ticks_elapsed], 1
    jnz scroll_loop   ; scroll every other tick

;    mov al, [sc_head]
;    cmp al, [sc_tail]
;    je scroll_loop

    ; Erase sprites at old positions
    call erase_sprites
    ; Update sprite positions
    mov ax, 2
    cmp word [start_addr], 39
    jne .have_update_scroll_delta
    mov ax, -78
.have_update_scroll_delta:
    push ax
    call update_sprites
    add sp, 2

    call get_scancode

    ; Extended keys: use scan code in AH
    cmp al, 48h            ; up
    je .up
    cmp al, 50h            ; down
    je .down
    cmp al, 4Bh            ; left
    je .left
    cmp al, 4Dh            ; right
    je .right
    cmp al, 01h            ; Esc
    je exit_to_dos
    jmp .continue

.up:
    sub word [sprites_list+4], 4
    sub word [sprites_list+10], 160
    jmp .continue
.down:
    add word [sprites_list+4], 4
    add word [sprites_list+10], 160
    jmp .continue
.left:
    sub word [sprites_list+2], 4
    dec word [sprites_list+10]
    jmp .continue
.right:
    add word [sprites_list+2], 4
    inc word [sprites_list+10]
    jmp .continue

.continue:
    ; Advance scroll position (wrap every 40 words)
    add word [start_addr], 1  ; 40 words = 80 bytes = 1 scanline
    cmp word [start_addr], 40
    jb .set_scroll
    mov word [start_addr], 0
.set_scroll:
    mov bx, [start_addr]
    call set_start_addr

    ; Redraw sprites at new positions (capture background then draw)
    call draw_sprites

    ; Delete the last 8 columns of the screen
    mov ax, 312
    push ax
    xor ax,ax
    push ax
    mov ax, 319
    push ax
    mov ax, 199
    push ax
    xor ax, ax
    push ax          ; color 0 = black
    call fill_rect
    add sp, 10

    ; Draw a random-height box at x=312..319 from y=0
    mov ax, 312
    push ax
    xor ax, ax
    push ax
    mov ax, 319
    push ax
    call rand16
    xor dx, dx
    mov bx, 20
    div bx             ; DX = 0..199
    push dx
    mov ax, 2
    push ax
    call fill_rect
    add sp, 10

    ; draw a random-height box at x=312..319 from the bottom up
    mov ax, 312
    push ax
    call rand16
    xor dx, dx
    mov bx, 20
    div bx             ; DX = 0..199
    neg dx
    add dx,199
    push dx

    mov ax, 319
    push ax
    mov ax, 199
    push ax
    mov ax, 2
    push ax
    call fill_rect
    add sp, 10

    cmp byte [sprites_list+SPRITE_COLLIDE], 6
    je exit_to_dos

    jmp scroll_loop

    ; Back to text mode
exit_to_dos:
    call restore_int1c
    call restore_int9
    xor ax, ax
    call set_pit_rate ; set clock back to 18.2hz


    ; Wait for key
    mov ah, 00h
    int 16h


    mov ax, 0003h
    int 10h
    ret

; -----------------------------
; Fill rectangle (x1,y1)-(x2,y2) with color
; Stack params (word): x1, y1, x2, y2, color. 
fill_rect:
    push bp
    mov bp, sp
    push si
    push di

    ; Build 4-pixel pattern byte from 2-bit color
    mov al, [bp+4]
    and al, 3
    mov ah, al
    mov cl, 2
    shl ah, cl
    or al, ah
    mov ah, al
    mov cl, 4
    shl ah, cl
    or al, ah
    mov si, [bp+10]    ; y1
.y_loop:
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

    pop di
    pop si
    pop bp
    ret

; -----------------------------
; Draw sprite at (x,y)
; Stack params (word): start_addr_bytes, x, y, sprite_ptr, collide_flag_ptr
; Sprite format (DS: sprite_ptr):
;   dw width_pixels   (multiple of 4)
;   dw height_pixels
;   dw bytes_per_row  (precomputed at init/load)
;   dw pic_ptr        (precomputed at init/load)
;   db mask[height * bytes_per_row]
;   db picture[height * bytes_per_row]
; Mask semantics: 1 bits keep background, 0 bits allow picture to draw.
; Return the collide flag in ax: 0 = no collision, 1 = collision (sprite overlaps non-background pixels)
draw_sprite:
    push bp
    mov bp, sp
    sub sp, 8          ; locals: [bp-2]=draw_bytes, [bp-4]=start_byte, [bp-6]=flag_ptr, [bp-8]=parity
    push si
    push di

    mov bx, [bp+4]     ; collide_flag_ptr
    mov [bp-6], bx
    mov bx, [bp+6]     ; sprite_ptr
    mov cx, [bx+2]     ; height_pixels (row count)
    mov dx, [bx+4]     ; precomputed bytes_per_row
    mov [bp-2], dx     ; draw_bytes (full row; no right-edge clipping)
    lea si, [bx+8]     ; mask_ptr
    mov di, [bx+6]     ; precomputed pic_ptr
    mov ax, [bp+8]     ; y start

    ; Clip Y
    test ax, 8000h     ; y < 0 (signed) => out of bounds
    jnz .done
    cmp ax, 200
    jae .done
    mov bx, 200
    sub bx, ax         ; visible_rows
    cmp cx, bx
    jbe .rows_ok
    mov cx, bx
.rows_ok:

    ; Clip X (x is multiple of 4). If the sprite would clip at right edge,
    ; skip drawing entirely instead of partial scanlines.
    mov bx, [bp+10]    ; x start
    cmp bx, 320
    jae .done
    shr bx, 1
    shr bx, 1          ; start_byte
    mov [bp-4], bx
    mov dx, [bp-2]     ; draw_bytes
    mov ax, bx
    add ax, dx
    cmp ax, 80
    ja .done

    mov dx, cx          ; row count
    mov ax, [bp+8]     ; y start
    and al, 1
    mov [bp-8], al
    mov bx, [bp+12]    ; cached sprite start address in CGA buffer
    add bx, [bp-4]     ; apply clipped x byte offset

.row_loop:
    mov cx, [bp-2]     ; draw_bytes
    shr cx, 1          ; word count (sprites assumed multiple of 8px in X)
.word_loop:
    mov ax, [es:bx]    ; get the screen pixels
    and ax, [si]       ; apply mask (1=keep screen, 0=draw)
    cmp ax, [es:bx]
    je .no_collide_w
    push bx             ; set the collide flag in the sprite 
    mov bx, [bp-6]
    or  byte [bx], 1    ; collision bit 0 => 1
    pop bx
    or  ax, [di]       ; apply picture
    mov [es:bx], ax
    add bx, 2
    add si, 2
    add di, 2
    dec cx
    jz .row_done_fast
    jmp .word_loop_fast
.no_collide_w:
    or  ax, [di]       ; apply picture
    mov [es:bx], ax    ; write back to screen
    add bx, 2
    add si, 2
    add di, 2
    loop .word_loop

.row_done:
    ; Advance to next scanline start
    mov al, [bp-8]
    test al, 1
    jz .even_to_odd
    sub bx, 8112       ; odd -> even
    sub bx, [bp-2]     ; skip bytes on odd line to get to next line
    jmp .next_line
.even_to_odd:
    add bx, 8192       ; even -> odd
    sub bx, [bp-2]
.next_line:
    xor byte [bp-8], 1

    dec dx
    jnz .row_loop
    jmp .done

.row_loop_fast:
    mov cx, [bp-2]
    shr cx, 1
.word_loop_fast:
    mov ax, [es:bx]
    and ax, [si]
    or  ax, [di]
    mov [es:bx], ax
    add bx, 2
    add si, 2
    add di, 2
    dec cx
    jnz .word_loop_fast

.row_done_fast:
    mov al, [bp-8]
    test al, 1
    jz .even_to_odd_fast
    sub bx, 8112
    sub bx, [bp-2]
    jmp .next_line_fast
.even_to_odd_fast:
    add bx, 8192
    sub bx, [bp-2]
.next_line_fast:
    xor byte [bp-8], 1
    dec dx
    jnz .row_loop_fast

.done:
    mov ax,[bp-6]
    pop di
    pop si
    add sp, 8
    pop bp
    ret

; Sprite list helpers
; Entry layout (14 bytes):
;   dw sprite_ptr, dw x, dw y, dw vx, dw vy, dw vbuf_addr, db collide_flag, db pad
init_sprites:
    push si
    mov cl, [sprites_count]
    xor ch, ch
    mov si, sprites_list

.loop:
    push cx

    mov byte [si+SPRITE_COLLIDE], 0    ; clear collision flag
    ; Compute and cache the sprite's video buffer start address for faster drawing later. Also clear the collision flag byte.
    mov ax, [si+SPRITE_Y]         ; y
    mov bx, ax
    and bx, 1
    mov cl, 13
    shl bx, cl             ; (y & 1) * 0x2000
    shr ax, 1
    mov cl, 4
    shl ax, cl             ; (y >> 1) * 16
    mov dx, ax
    shl dx, 1
    shl dx, 1              ; (y >> 1) * 64
    add dx, ax             ; (y >> 1) * 80
    add bx, dx
    mov ax, [start_addr]
    shl ax, 1              ; words -> bytes
    add bx, ax
    mov ax, [si+2]         ; x
    shr ax, 1
    shr ax, 1              ; x / 4
    add bx, ax
    mov [si+SPRITE_VBUF_ADDR], bx        ; cached video-buffer start address

    ; Now draw the sprite
    push word [si+SPRITE_VBUF_ADDR]  ; cached start address
    push word [si+SPRITE_X]   ; x
    push word [si+SPRITE_Y]   ; y
    mov bx, [si+SPRITE_PTR]       ; sprite ptr
    push bx
    lea bx, [si+SPRITE_COLLIDE]    ; collide_flag ptr
    push bx
    call draw_sprite
    add sp, 10

    pop cx
    add si, SPRITE_STRUCT_SIZE
    loop .loop
    pop si
    ret

erase_sprites:
    push si
    mov cl, [sprites_count]
    xor ch, ch
    mov si, sprites_list
.loop:
    push cx
    push word [si+SPRITE_VBUF_ADDR]  ; cached start address
    push word [si+SPRITE_X]   ; x
    push word [si+SPRITE_Y]   ; y
    push word [si+SPRITE_PTR]       ; sprite ptr
    call clear_sprite
    add sp, 8
    pop cx
    add si, SPRITE_STRUCT_SIZE
    loop .loop
    pop si
    ret

update_sprites:
    push bp
    mov bp, sp
    sub sp, 4 ; locals: [bp-2] = scroll delta, [bp-4] = old_y
    push di
    push si

    ; Input: [bp+4] = scroll-byte delta from erase phase to upcoming draw phase.
    mov ax, [bp+4]
    mov [bp-2], ax

    mov cl, [sprites_count]
    xor ch, ch
    mov si, sprites_list
.loop:
    push cx
    mov al, [si+SPRITE_COLLIDE]
    cmp al, 0
    je .state_done
    cmp al, 1
    je .to_explode_1
    cmp al, 3
    je .to_explode_2
    cmp al, 4
    je .to_explode_3
    cmp al, 5
    je .to_explode_4
    jmp .state_done

.to_explode_1:
    mov word [si+SPRITE_PTR], explode_1
    mov byte [si+SPRITE_COLLIDE], 3
    jmp .state_done

.to_explode_2:
    mov word [si+SPRITE_PTR], explode_2
    mov byte [si+SPRITE_COLLIDE], 4
    jmp .state_done

.to_explode_3:
    mov word [si+SPRITE_PTR], explode_3
    mov byte [si+SPRITE_COLLIDE], 5
    jmp .state_done

.to_explode_4:
    mov word [si+SPRITE_PTR], explode_4
    mov byte [si+SPRITE_COLLIDE], 6

.state_done:

    mov ax, [si+SPRITE_X]     ; x
    add ax, [si+SPRITE_VX]     ; vx
    mov [si+SPRITE_X], ax
    mov dx, [si+SPRITE_Y]     ; old y
    mov [bp-4], dx

    ; If movement mode byte is 1, use vy as cosine-table index.
    cmp byte [si+SPRITE_MOVE_MODE], 1
    jne .linear_y
    mov ax, [si+SPRITE_VY]
    inc ax
    cmp ax, 40
    jb .cos_idx_ok
    xor ax, ax
.cos_idx_ok:
    mov [si+SPRITE_VY], ax
    shl ax, 1
    mov bx, ax
    mov di, [cosine_table_40+bx]
    mov [si+SPRITE_Y], di
    jmp .y_updated

.linear_y:
    mov di, dx
    add di, [si+SPRITE_VY]     ; new y
    mov [si+SPRITE_Y], di

.y_updated:

    ; Recompute cached video-buffer address from absolute x/y and upcoming scroll.
    mov ax, di
    test ax, 8000h
    jnz .addr_done
    cmp ax, 200
    jae .addr_done

    mov bx, ax
    and bx, 1
    mov cl, 13
    shl bx, cl                   ; (y & 1) * 0x2000
    shr ax, 1
    mov dx, ax
    shl dx, 1
    shl dx, 1
    shl dx, 1
    shl dx, 1                    ; (y >> 1) * 16
    mov cx, dx
    shl dx, 1
    shl dx, 1                    ; (y >> 1) * 64
    add cx, dx                   ; (y >> 1) * 80
    add bx, cx
    mov ax, [start_addr]
    shl ax, 1
    add ax, [bp-2]               ; next frame scroll base in bytes
    add bx, ax
    mov ax, [si+SPRITE_X]
    shr ax, 1
    shr ax, 1                    ; x / 4
    add bx, ax
    mov [si+SPRITE_VBUF_ADDR], bx
.addr_done:

    pop cx
    add si, 14
    dec cx
    jnz .loop
    pop si
    pop di
    add sp, 4
    pop bp
    ret

draw_sprites:
    push si
    mov cl, [sprites_count]
    xor ch, ch
    mov si, sprites_list
.loop:
    push cx
    cmp byte [si+SPRITE_COLLIDE], 6
    jae .skip_draw
    push word [si+SPRITE_VBUF_ADDR]  ; cached start address
    push word [si+SPRITE_X]   ; x
    push word [si+SPRITE_Y]   ; y
    push word [si+SPRITE_PTR]       ; sprite ptr
    lea bx, [si+SPRITE_COLLIDE]    ; collide_flag ptr
    push bx
    call draw_sprite
    add sp, 10
.skip_draw:
    pop cx

    add si, SPRITE_STRUCT_SIZE
    loop .loop
    pop si
    ret

; -----------------------------
; Clear sprite area with color 0 at (x,y)
; Stack params (word): start_addr_bytes, x, y, sprite_ptr
clear_sprite:
    push bp
    mov bp, sp
    sub sp, 4          ; locals: [bp-2]=draw_bytes, [bp-4]=start_byte
    push si
    push di

    mov si, [bp+4]     ; sprite_ptr
    mov cx, [si+2]     ; height_pixels (row count)
    mov dx, [si+4]     ; precomputed bytes_per_row
    mov ax, [bp+6]     ; y start

    ; Clip Y
    cmp ax, 200
    jae .done
    mov bx, 200
    sub bx, ax         ; visible_rows
    cmp cx, bx
    jbe .rows_ok
    mov cx, bx
.rows_ok:

    ; Clip X (x is multiple of 4). If the sprite would clip at right edge,
    ; skip clearing entirely instead of partial scanlines.
    mov bx, [bp+8]     ; x start
    cmp bx, 320
    jae .done
    shr bx, 1
    shr bx, 1          ; start_byte
    mov [bp-4], bx
    mov ax, bx
    add ax, dx
    cmp ax, 80
    ja .done
    mov [bp-2], dx     ; draw_bytes == bytes_per_row

    mov ax, [bp+6]     ; y start
    mov dl, al
    and dl, 1
    mov di, [bp+10]    ; cached sprite start address in CGA buffer
    add di, [bp-4]     ; apply clipped x byte offset

    xor ax, ax
.row_loop:
    push cx
    mov cx, [bp-2]     ; draw_bytes
    shr cx, 1          ; word count (sprites assumed multiple of 8px in X)
    rep stosw

.row_done:
    ; Advance to next scanline start
    test dl, 1
    jz .even_to_odd
    sub di, 8112
    sub di, [bp-2]
    jmp .next_line
.even_to_odd:
    add di, 8192
    sub di, [bp-2]
.next_line:
    xor dl, 1

    pop cx
    loop .row_loop

.done:
    pop di
    pop si
    add sp, 4
    pop bp
    ret

; -----------------------------
; Set CGA CRTC start address
; BX = start address in words
set_start_addr:
    mov dx, 3D4h
    mov al, 0Ch
    out dx, al
    inc dx
    mov al, bh
    out dx, al

    dec dx
    mov al, 0Dh
    out dx, al
    inc dx
    mov al, bl
    out dx, al
    ret

; -----------------------------
; Sync for the next vertical retrace start
sync_vertical_retrace:
    mov dx, 03DAh
.wait_no_retrace:
    in al, dx
    test al, 08h
    jnz .wait_no_retrace
.wait_retrace:
    in al, dx
    test al, 08h
    jz .wait_retrace
    ret

; -----------------------------
; 16-bit LCG random
; seed = seed*25173 + 13849
rand16:
    mov ax, [seed]
    mov bx, 25173
    mul bx             ; DX:AX = AX * 25173
    add ax, 13849
    mov [seed], ax
    ret

; -----------------------------
short_delay:
    mov cx, 2000
.delay:
    loop .delay
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

; -----------------------------
; Print AL as two hex digits
print_hex8:
    push ax
    mov cl, 4
    shr al, cl
    call print_hex_nibble
    pop ax
    and al, 0Fh
    call print_hex_nibble
    ret

print_hex_nibble:
    push bx
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
    pop bx
    ret

; -----------------------------
; Set cursor position (text mode)
; DH = row, DL = column, BH = page
set_cursor_pos:
    mov ah, 02h
    int 10h
    ret

; -----------------------------
; Install INT 9h handler (keyboard IRQ)
install_int9:
    push es
    cli
    mov ah, 35h
    mov al, 09h
    int 21h
    mov [old9_off], bx
    mov [old9_seg], es
    mov dx, int9_handler
    mov ax, 2509h
    int 21h
    sti
    pop es
    ret

; -----------------------------
; Restore original INT 9h handler
restore_int9:
    push ds
    cli
    mov dx, [old9_off]
    mov ds, [old9_seg]
    mov ax, 2509h
    int 21h
    sti
    pop ds
    ret

; -----------------------------
; get next scancode from buffer, or 0 if empty. Return in AL.
get_scancode:
    cli
    xor bh, bh
    mov bl, [sc_tail]

    cmp byte bl, [sc_head]
    je .empty
    mov al, [sc_buf+bx]
    inc bl
    and bl, 0Fh
    mov [sc_tail], bl
    jmp .got_scancode
.empty:
    mov al, 0
.got_scancode:
    sti
    ret
; -----------------------------
; INT 9h handler: read scancode, set flag, flush BIOS buffer
int9_handler:
    push ax
    push bx
    push ds

    push cs ; set DS = CS for accessing our data
    pop ds

    in al, 60h ; get scancode from keyboard controller
    push ax
    in  al, 61h ; Ack the interrupt by toggling bit 7 of port 61h
    mov ah, al
    or  al, 80h
    out 61h, al
    mov al, ah
    out 61h, al
    pop ax
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
    jne .done
    mov byte [esc_flag], 1

.done:
    mov al, 20h
    out 20h, al

    pop ds
    pop bx
    pop ax
    iret


; -----------------------------
; Set PIT channel 0 rate (divisor in AX, 0 means 65536)
set_pit_rate:
    push ax
    mov al, 36h
    out 43h, al
    pop ax
    out 40h, al
    mov al, ah
    out 40h, al
    ret

; -----------------------------
; Install INT 1Ch handler (BIOS timer tick)
install_int1c:
    push es
    cli
    mov ah, 35h
    mov al, 1Ch
    int 21h
    mov [old1c_off], bx
    mov [old1c_seg], es
    mov dx, int1c_handler
    mov ax, 251Ch
    int 21h
    sti
    pop es
    ret

; -----------------------------
; Restore original INT 1Ch handler
restore_int1c:
    push ds
    cli
    mov dx, [old1c_off]
    mov ds, [old1c_seg]
    mov ax, 251Ch
    int 21h
    sti
    pop ds
    ret

; -----------------------------
; INT 1Ch handler: set tick flag, chain old handler at ~18.2 Hz
int1c_handler:
    mov byte [cs:tick_flag], 1
    add [cs:tick_acc], word CLOCK_TICKS
    jno .no_overflow
    jmp far [cs:old1c_off]
.no_overflow:
    iret



section .data align=16

; -----------------------------
seed  dw 0
x1    dw 0
y1    dw 0
x2    dw 0
y2    dw 0
w     dw 0
h     dw 0
color db 0

; ----------------------------- Keyboard buffer (ring of 16 bytes)
sc_head        db 0
sc_tail        db 0
sc_buf         times 16 db 0
esc_flag      db 0

old9_off dw 0
old9_seg dw 0

; ------------------------------ Timer handler

ticks_elapsed dw 0
tick_flag db 0
old1c_off dw 0
old1c_seg dw 0
tick_acc dw 0

; ----------------------------- Screen and sprites

start_addr dw 0
sprites_count db 16

SPRITE_PTR equ 0
SPRITE_X equ 2
SPRITE_Y equ 4
SPRITE_VX equ 6
SPRITE_VY equ 8
SPRITE_VBUF_ADDR equ 10
SPRITE_COLLIDE equ 12
SPRITE_MOVE_MODE equ 13
SPRITE_STRUCT_SIZE equ 14

sprites_list:
    dw space_ship
    dw 8            ; x
    dw 8            ; y
    dw 0              ; vx
    dw 0              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide 0= no collision, 1=collision (overlaps non-background pixels), 2-5 animation of explosion, 6 not visible, skip drawing
    db 0            ; movement mode: 0=linear vy, 1=cosine (vy is index into cosine_table_40)

    dw alien_ship
    dw 300            ; x
    dw 150            ; y
    dw -1              ; vx
    dw 0              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 1

    dw asteroid
    dw 200            ; x
    dw 10            ; y
    dw 4              ; vx
    dw 1              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0

    dw asteroid
    dw 200            ; x
    dw 20            ; y
    dw 4              ; vx
    dw -1              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0

    dw asteroid
    dw 200            ; x
    dw 30            ; y
    dw -4              ; vx
    dw 2              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0

    dw asteroid
    dw 200            ; x
    dw 40            ; y
    dw -4              ; vx
    dw -2              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0

    dw asteroid
    dw 200            ; x
    dw 50            ; y
    dw -4              ; vx
    dw 4              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0

    dw asteroid
    dw 200            ; x
    dw 60            ; y
    dw 4              ; vx
    dw -4              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0

    dw asteroid
    dw 200            ; x
    dw 70            ; y
    dw 0              ; vx
    dw 0              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0

    dw asteroid
    dw 200            ; x
    dw 80            ; y
    dw 4              ; vx
    dw -1              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0

    dw asteroid
    dw 200            ; x
    dw 90            ; y
    dw 0              ; vx
    dw 0              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0

    dw asteroid
    dw 200            ; x
    dw 100            ; y
    dw 4              ; vx
    dw 2              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0

    dw asteroid
    dw 200            ; x
    dw 110            ; y
    dw 4              ; vx
    dw -2              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0

    dw asteroid
    dw 200            ; x
    dw 120            ; y
    dw 0              ; vx
    dw 0              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0

    dw asteroid
    dw 200            ; x
    dw 130            ; y
    dw 8             ; vx
    dw -8              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0

    dw asteroid
    dw 200            ; x
    dw 140            ; y
    dw 8              ; vx
    dw 8              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0

cosine_table_40 dw 150,	149,	148,	145,	140,	135,	129,	123,	115,	108,	100,	92,	85,	77,	71,	65,	60,	55,	52,	51,	50,	51,	52,	55,	60,	65,	71,	77,	85,	92,	100,	108,	115,	123,	129,	135,	140,	145,	148,	149


align 2

alien_ship dw 16,8,4,alien_ship+40
db 0FFh,0CFh,0FFh,03Fh
db 0FFh,0F3h,0FCh,0FFh
db 0FFh,00h,00h,0Fh
db 0FCh,0CFh,0FFh,033h
db 0F0h,0F0h,0F0h,0F0h
db 0FCh,0FCh,03h,0F3h
db 0FFh,03Fh,0Fh,0CFh
db 0FFh,0C0h,00h,03Fh

db 00h,020h,00h,080h
db 00h,08h,02h,00h
db 00h,0AAh,0AAh,0A0h
db 02h,020h,00h,088h
db 0Ah,09h,06h,0Ah
db 02h,02h,058h,08h
db 00h,080h,0A0h,020h
db 00h,02Ah,0AAh,080h
space_ship dw 16,8,4,space_ship+40
db 0FFh,0FFh,0FFh,0FFh
db 0FFh,0FFh,0C3h,0FFh
db 0FFh,0FFh,0F0h,03Fh
db 0C0h,00h,0FFh,03h
db 0FFh,0F0h,0Fh,03Fh
db 0FFh,0C0h,00h,0FFh
db 0FFh,0C0h,03h,0FFh
db 0FFh,0FFh,0FFh,0FFh

db 00h,00h,00h,00h
db 00h,00h,03Ch,00h
db 00h,00h,05h,040h
db 035h,055h,00h,094h
db 00h,06h,0A0h,040h
db 00h,01Ah,0A9h,00h
db 00h,015h,054h,00h
db 00h,00h,00h,00h
asteroid dw 8,8,2,asteroid+24
db 0FCh,0Fh
db 0F3h,033h
db 0CCh,0CCh
db 0Ch,0F3h
db 033h,0CCh
db 0CFh,03Ch
db 0F3h,0C3h
db 0FCh,03Fh

db 01h,050h
db 04h,044h
db 011h,011h
db 051h,04h
db 044h,011h
db 010h,041h
db 04h,014h
db 01h,040h
hatched_box dw 8,8,2,hatched_box+24
db 00h,00h
db 00h,00h
db 00h,00h
db 00h,00h
db 00h,00h
db 00h,00h
db 00h,00h
db 00h,00h

db 099h,099h
db 066h,066h
db 099h,099h
db 066h,066h
db 099h,099h
db 066h,066h
db 099h,099h
db 066h,066h
explode_1 dw 8,8,2,explode_1+24
db 0FFh,0FFh
db 0FFh,0FFh
db 0FFh,0FFh
db 0FFh,03Fh
db 0FCh,03Fh
db 0FFh,0CFh
db 0FFh,0FFh
db 0FFh,0FFh

db 00h,00h
db 00h,00h
db 00h,00h
db 00h,040h
db 01h,080h
db 00h,010h
db 00h,00h
db 00h,00h
explode_2 dw 8,8,2,explode_2+24
db 0FFh,0FFh
db 0FCh,0CFh
db 0F3h,03Fh
db 0FCh,0CFh
db 0CFh,0F3h
db 0F3h,03Fh
db 0FFh,0CFh
db 0FFh,0FFh

db 00h,00h
db 01h,010h
db 04h,080h
db 02h,010h
db 010h,04h
db 04h,080h
db 00h,010h
db 00h,00h
explode_3 dw 8,8,2,explode_3+24
db 0F3h,0CFh
db 0CFh,033h
db 0CCh,033h
db 033h,033h
db 0FFh,03Ch
db 0F0h,0F3h
db 0CFh,0C3h
db 0FCh,0FFh

db 04h,010h
db 010h,084h
db 022h,048h
db 048h,0C4h
db 00h,081h
db 06h,0Ch
db 010h,018h
db 01h,00h
explode_4 dw 8,8,2,explode_4+24
db 03Fh,0CFh
db 0CCh,0F3h
db 0FFh,03Ch
db 033h,0CFh
db 0CFh,033h
db 0F3h,0CFh
db 0CFh,03Ch
db 0F3h,0FFh

db 080h,030h
db 023h,08h
db 00h,0C2h
db 084h,030h
db 020h,048h
db 0Ch,020h
db 020h,082h
db 08h,00h
