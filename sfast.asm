; cga_scroll_boxes.asm
; NASM .COM program
; Conventions: routines dont' save AX,BX,CX,DX, but do save SI,DI,BP,ES if used. Stack params are WORDs unless noted otherwise. Screen buffer is accessed via ES.

; CLOCK_TICKS EQU 19912 ; number of PIT ticks for ~1/59.94 Hz delay (for smooth scrolling)
CLOCK_TICKS EQU 39824 ; number of PIT ticks for ~1/30s delay (for smooth scrolling)
CGA_BASE EQU 0B800h
HSCROLL_STEP EQU 2

[map all scroll.map]
CPU 8086
section .text align=16
org 100h

%macro set_cga_palette 3
    mov al, ((%1 << 5) + (%2 << 4) + (%3 & 15))
    mov dx, 03D9h
    out dx, al
%endmacro

%macro play_sound 1
    mov word [sound_ptr], %1
    in al, 61h
    or al, 03h
    out 61h, al
%endmacro

%macro stop_sound 0
    mov word [sound_ptr], 0
    in al, 61h
    and al, 0FCh
    out 61h, al
%endmacro

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
    call sync_vertical_retrace
    call set_pit_rate

    ; Seed RNG from BIOS timer tick
    mov ah, 00h
    int 1Ah            ; CX:DX = ticks since midnight
    mov [seed], dx

    ; Initialize sprites (capture background + draw)
    call init_sprites

    ; fill the top 2 scanlines (0,0)-(319,1) with color 2 to avoid a blank spce when scrolling wraps around
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

; ------------------------------------------------- MAIN LOOP

scroll_loop:
;    call sync_vertical_retrace     ; wait for vertical retrace

    ; Wait for BIOS tick (INT 1Ch) to sync scrolling
.wait_tick:
    cmp byte [tick_flag], 0
    jne .got_tick
    jmp .wait_tick
.got_tick:
    mov byte [tick_flag], 0

    set_cga_palette 1,1,0

    ; Erase sprites at old positions
    call erase_sprites
    ; Erase laser at old position
    call erase_laser


    test [ticks_elapsed], 3
    jz .horizontal_frame_scroll   ; scroll every other tick
    ; if frame doesn't scroll, then just update sprite positions and continue
    xor ax, ax
    push ax
    call update_sprites
    add sp, 2
    jmp .continue_to_forward

.horizontal_frame_scroll:
    ; Update sprite positions
    mov ax, HSCROLL_STEP
    cmp word [start_addr], 39
    jne .have_update_scroll_delta
    mov ax, -78
.have_update_scroll_delta:
    push ax
    call update_sprites
    add sp, 2

    ; Advance scroll position (wrap every 40 words)
    add word [start_addr], (HSCROLL_STEP>>1)  ; 40 words = 80 bytes = 1 scanline
    cmp word [start_addr], 40
    jb .set_scroll
    mov word [start_addr], 0
.set_scroll:
    mov bx, [start_addr]
    call set_start_addr

    call next_mountain

.continue_to_forward:


    ; Advance laser for this cycle
    call advance_laser

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
    cmp al, 39h            ; space (make)
    je .fire
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
    dec word [sprites_list+SPRITE_X_BYTE]
    jmp .continue
.right:
    add word [sprites_list+2], 4
    inc word [sprites_list+10]
    inc word [sprites_list+SPRITE_X_BYTE]
    jmp .continue
.fire:
    call fire_laser
    play_sound sound_laser
    jmp .continue

.continue:

    ; Draw laser before sprites so sprite redraw can collide with it.
    call draw_laser

    ; Redraw sprites at new positions (capture background then draw)
    call draw_sprites

%ifdef STEP_DEBUG
.no_input:
    call get_scancode
    cmp al, 0
    jz .no_input
%endif

    cmp byte [sprites_list+SPRITE_COLLIDE], 6
    je exit_to_dos

    set_cga_palette 0,1,1

    jmp scroll_loop

    ; Back to text mode
exit_to_dos:
    call restore_int1c
    call restore_int9
    xor ax, ax
    call set_pit_rate ; set clock back to 18.2hz

    stop_sound

    ; Wait for key
    mov ah, 00h
    int 16h


    mov ax, 0003h
    int 10h
    ret

; -----------------------------
; draw the next mountain column on the right edge. Mountains are 20 pixels tall and drawn in color 2.
next_mountain:
    ; Delete the last 8 columns of the screen
    mov ax, 312
    push ax
    xor ax, ax
    push ax
    mov ax, 199
    push ax
    xor ax, ax
    push ax          ; color 0 = black
    call fill_rect_8px_aligned
    add sp, 8

    ; Draw a random-height box at x=312..319 from y=0
    mov ax, 312
    push ax
    xor ax, ax
    push ax
    call rand16
    xor dx, dx
    mov bx, 20
    div bx             ; DX = 0..199
    push dx
    mov ax, 2
    push ax
    call fill_rect_8px_aligned
    add sp, 8

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

    mov ax, 199
    push ax
    mov ax, 2
    push ax
    call fill_rect_8px_aligned
    add sp, 8
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
; Laser: 4-pixel white horizontal dash, x aligned to 4.
; Uses screen-space coordinates in laser_x/laser_y.
erase_laser:
    cmp byte [laser_active], 0
    je .done
    mov ax, [laser_x]
    push ax
    mov ax, [laser_y]
    push ax
    mov ax, [laser_x]
    add ax, 3
    push ax
    mov ax, [laser_y]
    push ax
    xor ax, ax
    push ax
    call fill_rect
    add sp, 10
.done:
    ret

advance_laser:
    cmp byte [laser_active], 0
    je .done
    mov ax, [laser_x]
    add ax, 12
    mov [laser_x], ax
    ; 4-pixel dash occupies x..x+3, so x=316 touches the right edge.
    cmp ax, 316
    jb .done
    mov byte [laser_active], 0
.done:
    ret

draw_laser:
    cmp byte [laser_active], 0
    je .done
    mov ax, [laser_x]
    push ax
    mov ax, [laser_y]
    push ax
    mov ax, [laser_x]
    add ax, 3
    push ax
    mov ax, [laser_y]
    push ax
    mov ax, 3          ; white
    push ax
    call fill_rect
    add sp, 10
.done:
    ret

fire_laser:
    ; Launch from 4 pixels right of sprite 0, 4 pixels below sprite top.
    mov bx, [sprites_list+SPRITE_PTR]
    mov ax, [sprites_list+SPRITE_X]
    add ax, [bx]       ; right edge = x + sprite width
    ; Keep 4-pixel boundary alignment without ever moving inside the ship.
    add ax, 3
    and ax, 0FFFCh     ; align up to next multiple of 4
    cmp ax, 316
    jae .done
    mov [laser_x], ax

    mov ax, [sprites_list+SPRITE_Y]
    add ax, 4
    cmp ax, 200
    jae .done
    mov [laser_y], ax
    mov byte [laser_active], 1
.done:
    ret

; -----------------------------
; Fill 8-pixel wide rectangle at aligned X with color.
; Stack params (word): x, y1, y2, color.
; Assumptions:
; - width is fixed at 8 pixels (2 bytes in mode 4)
; - x is aligned to an 8-pixel boundary
fill_rect_8px_aligned:
    push bp
    mov bp, sp
    push si
    push di

    ; Build 2-byte pattern word (both bytes hold the same 4-pixel pattern).
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
    mov ah, al
    mov dx, ax         ; DX = repeated byte pattern word

    ; Precompute x byte offset (x / 4), valid because x is 8-pixel aligned.
    mov di, [bp+10]
    shr di, 1
    shr di, 1

    ; Compute starting video offset for (x, y1), including scroll.
    mov ax, [bp+8]     ; y1
    mov bx, ax
    and bx, 1
    mov cl, 13
    shl bx, cl         ; (y & 1) * 0x2000
    shr ax, 1          ; y >> 1
    mov cx, ax
    mov ax, cx
    shl ax, 1
    shl ax, 1
    shl ax, 1
    shl ax, 1          ; (y >> 1) * 16
    shl cx, 1
    shl cx, 1
    shl cx, 1
    shl cx, 1
    shl cx, 1
    shl cx, 1          ; (y >> 1) * 64
    add ax, cx         ; (y >> 1) * 80
    add bx, ax
    mov ax, [start_addr]
    shl ax, 1          ; words -> bytes
    add bx, ax
    add bx, di

    ; Loop count = (y2 - y1 + 1)
    mov cx, [bp+6]
    sub cx, [bp+8]
    inc cx

    ; Track line parity to step through CGA's even/odd interleaved planes quickly.
    mov al, [bp+8]
    and al, 1

.row_loop:
    mov [es:bx], dx
    test al, 1
    jz .even_to_odd
    sub bx, 8112       ; odd -> next even row
    jmp .next_row
.even_to_odd:
    add bx, 8192       ; even -> next odd row
.next_row:
    xor al, 1
    loop .row_loop

    pop di
    pop si
    pop bp
    ret

; -----------------------------
; Draw sprite at (x,y)
; Register ABI:
;   BX = collide_flag_ptr
;   SI = pic_ptr
;   DI = start_addr_bytes
;   CX = height_pixels
;   DX = draw_bytes
;   AL = y parity (y & 1)
; Uses cached sprite metadata from sprite list entries.
; Return AX=0.
draw_sprite:
    push bp
    push si
    push di

    cmp byte [bx], 7
    je .done

    push di                    ; base start address for row 0
    push cx                    ; original height

    ; Pass 1: rows 0,2,4,... (already contiguous in interlaced sprite data).
    mov bp, cx
    inc bp
    shr bp, 1
.even_rows_loop:
    ; Coarse collision test: if any destination word is non-zero, set collision bit.
    push di
    mov cx, dx         ; draw_bytes
    shr cx, 1          ; word count (sprites assumed multiple of 8px in X)
.collision_scan_loop_even:
    cmp word [es:di], 0
    je .next_collision_word_even
    or byte [bx], 1
    jmp .collision_scan_done_even
.next_collision_word_even:
    add di, 2
    loop .collision_scan_loop_even
.collision_scan_done_even:
    pop di

    mov cx, dx
    shr cx, 1
    rep movsw

    add di, 80
    sub di, dx
    dec bp
    jnz .even_rows_loop

    ; Restore base/height, then Pass 2: rows 1,3,5,...
    pop cx
    pop di
    shr cx, 1
    mov bp, cx
    jz .done
    test al, 1
    jnz .second_pass_starts_even
    add di, 8192
    jmp .odd_rows_loop
.second_pass_starts_even:
    sub di, 8112

.odd_rows_loop:
    push di
    mov cx, dx
    shr cx, 1
.collision_scan_loop_odd:
    cmp word [es:di], 0
    je .next_collision_word_odd
    or byte [bx], 1
    jmp .collision_scan_done_odd
.next_collision_word_odd:
    add di, 2
    loop .collision_scan_loop_odd
.collision_scan_done_odd:
    pop di

    mov cx, dx
    shr cx, 1
    rep movsw

    add di, 80
    sub di, dx
    dec bp
    jnz .odd_rows_loop

.done:
    xor ax, ax
    pop di
    pop si
    pop bp
    ret

; Sprite list helpers
; Entry layout (28 bytes):
;   dw sprite_ptr, dw x, dw y, dw vx, dw vy, dw vbuf_addr, db collide_flag, db move_mode
;   dw scroll_delta_bytes, dw accum_x, dw accum_y, dw draw_bytes, dw height, dw pic_ptr
;   dw x_byte (x/4)
init_sprites:
    push si
    mov cl, [sprites_count]
    xor ch, ch
    mov si, sprites_list

.loop:
    push cx

    mov byte [si+SPRITE_COLLIDE], 0    ; clear collision flag
    mov bx, [si+SPRITE_PTR]
    mov ax, [bx+4]                     ; bytes_per_row
    mov [si+SPRITE_DRAW_BYTES], ax
    mov ax, [bx+2]                     ; height_pixels
    mov [si+SPRITE_HEIGHT], ax
    lea ax, [bx+6]                     ; pic_ptr = sprite_ptr + 6
    mov [si+SPRITE_PIC_PTR], ax

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
    mov [si+SPRITE_X_BYTE], ax
    add bx, ax
    mov [si+SPRITE_VBUF_ADDR], bx        ; cached video-buffer start address

    ; Now draw the sprite (register ABI).
    push si
    lea bx, [si+SPRITE_COLLIDE]
    mov cx, [si+SPRITE_HEIGHT]
    mov dx, [si+SPRITE_DRAW_BYTES]
    mov di, [si+SPRITE_VBUF_ADDR]
    mov ax, [si+SPRITE_Y]
    and al, 1
    mov si, [si+SPRITE_PIC_PTR]
    call draw_sprite
    pop si

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
    cmp byte [si+SPRITE_COLLIDE], 6 ; if sprite is fully exploded, skip erasing since it won't be drawn next frame either
    jae .skip_erase
    mov cx, [si+SPRITE_HEIGHT]
    mov dx, [si+SPRITE_DRAW_BYTES]
    mov di, [si+SPRITE_VBUF_ADDR]
    call clear_sprite
.skip_erase:
    pop cx
    add si, SPRITE_STRUCT_SIZE
    loop .loop
    pop si
    ret

; ------------------------------
; update sprite positions based on velocity, check for collisions, and update collision state. 
; Also apply scroll delta (passed as the only stack parameter) to each sprite's accumulated 
; scroll offset and apply that to the sprite's position if it exceeds a byte boundary 
; (to keep the sprite visually locked to the scrolled background).
update_sprites:
    push bp
    mov bp, sp
    sub sp, 4 ; locals: [bp-2] = old_x_byte, [bp-4] = old_y
    push di
    push si

    ; Input: [bp+4] = scroll-byte delta from erase phase to upcoming draw phase.

    mov cl, [sprites_count]
    xor ch, ch
    mov si, sprites_list
.loop:
    push cx
    mov al, [si+SPRITE_COLLIDE]
    cmp al, 0
    je .state_done
    cmp al, 7
    je .state_done
    cmp al, 1
    je .to_explode_1
    cmp al, 2
    je .to_explode_2
    cmp al, 3
    je .to_explode_3
    cmp al, 4
    je .to_explode_4
    cmp al, 5
    jae .to_explode_5
    jmp .state_done

.to_explode_1:
    play_sound sound_explosion
    mov bx, explode_1
    mov dl, 2
    jmp .set_explosion_sprite

.to_explode_2:
    mov bx, explode_2
    mov dl, 3
    jmp .set_explosion_sprite

.to_explode_3:
    mov bx, explode_3
    mov dl, 4
    jmp .set_explosion_sprite

.to_explode_4:
    mov bx, explode_4
    mov dl, 5
    jmp .set_explosion_sprite

.to_explode_5: 
; terminal situation, the sprite is now fully exploded and should be removed from the screen 
; and ignored for collisions. collide = 5 means a last erase will happen. 6 is fully exploded 
; and the sprite is inactive.
    mov byte [si+SPRITE_COLLIDE], 6
    jmp .addr_done

.set_explosion_sprite:
    mov [si+SPRITE_PTR], bx
    mov [si+SPRITE_COLLIDE], dl
    mov ax, [bx+4]
    mov [si+SPRITE_DRAW_BYTES], ax
    mov ax, [bx+2]
    mov [si+SPRITE_HEIGHT], ax
    lea ax, [bx+6]
    mov [si+SPRITE_PIC_PTR], ax

.state_done:
    mov ax, [si+SPRITE_X_BYTE]
    mov [bp-2], ax
    mov ax, [si+SPRITE_X]     ; x
    add ax, [si+SPRITE_VX]     ; vx
    mov [si+SPRITE_X], ax
    shr ax, 1
    shr ax, 1
    mov [si+SPRITE_X_BYTE], ax
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
    ; Fast skip when x-byte, y, and scroll all stayed unchanged.
    mov ax, [bp+4]
    or ax, ax
    jnz .needs_geo
    mov ax, [si+SPRITE_X_BYTE]
    cmp ax, [bp-2]
    jne .needs_geo
    cmp di, [bp-4]
    jne .needs_geo
    jmp .addr_done

.needs_geo:
    ; Out-of-bounds check on full sprite rectangle.
    mov ax, [si+SPRITE_X]
    test ax, 8000h
    jnz .out_of_bounds
    mov bx, [si+SPRITE_PTR]
    mov dx, [bx]                   ; width_pixels
    add dx, ax
    cmp dx, 320
    ja .out_of_bounds

    mov ax, di                     ; y
    test ax, 8000h
    jnz .out_of_bounds
    mov dx, [bx+2]                 ; height_pixels
    add dx, ax
    cmp dx, 200
    ja .out_of_bounds
    cmp byte [si+SPRITE_COLLIDE], 7
    jne .incremental_vbuf
    mov byte [si+SPRITE_COLLIDE], 0
    mov bx, di
    shl bx, 1
    mov bx, [y_base+bx]
    mov ax, [start_addr]
    shl ax, 1
    add bx, ax
    add bx, [bp+4]
    add bx, [si+SPRITE_X_BYTE]
    mov [si+SPRITE_VBUF_ADDR], bx
    jmp .addr_done

.incremental_vbuf:
    ; Incremental cached video-buffer update:
    ;   + scroll delta
    ;   + x-byte delta
    ;   + (y_base[new_y] - y_base[old_y])
    mov cx, [si+SPRITE_VBUF_ADDR]
    add cx, [bp+4]
    mov ax, [si+SPRITE_X_BYTE]
    sub ax, [bp-2]
    add cx, ax
    mov bx, di
    shl bx, 1
    mov ax, [y_base+bx]
    mov bx, [bp-4]
    shl bx, 1
    sub ax, [y_base+bx]
    add cx, ax
    mov [si+SPRITE_VBUF_ADDR], cx
    jmp .addr_done

.out_of_bounds:
    mov byte [si+SPRITE_COLLIDE], 7
.addr_done:

    pop cx
    add si, SPRITE_STRUCT_SIZE
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
    push si
    lea bx, [si+SPRITE_COLLIDE]
    mov cx, [si+SPRITE_HEIGHT]
    mov dx, [si+SPRITE_DRAW_BYTES]
    mov di, [si+SPRITE_VBUF_ADDR]
    mov ax, [si+SPRITE_Y]
    and al, 1
    mov si, [si+SPRITE_PIC_PTR]
    call draw_sprite
    pop si
.skip_draw:
    pop cx

    add si, SPRITE_STRUCT_SIZE
    loop .loop
    pop si
    ret

; -----------------------------
; Clear sprite area with color 0 at cached start position.
; Register ABI:
;   DI = start_addr_bytes
;   CX = height_pixels
;   DX = draw_bytes
; Assumes clipping/out-of-bounds already handled in update_sprites.
clear_sprite:
    push bp
    push di

    push di                    ; base start address for row 0
    push cx                    ; original height
    xor ax, ax

    ; Pass 1: rows 0,2,4,...
    mov bp, cx
    inc bp
    shr bp, 1
.even_rows_loop:
    mov cx, dx
    shr cx, 1
    rep stosw
    add di, 80
    sub di, dx
    dec bp
    jnz .even_rows_loop

    ; Pass 2: rows 1,3,5,...
    pop cx
    pop di
    shr cx, 1
    mov bp, cx
    jz .done
    cmp di, 2000h
    jb .second_pass_from_even
    sub di, 8112
    jmp .odd_rows_loop
.second_pass_from_even:
    add di, 8192
.odd_rows_loop:
    mov cx, dx
    shr cx, 1
    rep stosw
    add di, 80
    sub di, dx
    dec bp
    jnz .odd_rows_loop

.done:
    pop di
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
;.wait_no_retrace:
;    in al, dx
;    test al, 08h
;    jnz .wait_no_retrace
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
; INT 9h handler: read scancode, set flag, store in our buffer
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
    push si

    mov byte [cs:tick_flag], 1
    inc word [cs:ticks_elapsed]

    mov si, [cs:sound_ptr]
    or si, si
    jz .check_tick_overflow

    push ax
    push bx

    mov bx, [cs:si]
    or bx, bx
    jz .stop_sound

    mov al, 0B6h
    out 43h, al
    mov al, bl
    out 42h, al
    mov al, bh
    out 42h, al

    add si, 2
    mov [cs:sound_ptr], si
    mov bx, [cs:si]
    or bx, bx
    jnz .after_sound

.stop_sound:
    mov word [cs:sound_ptr], 0
    in al, 61h
    and al, 0FCh
    out 61h, al

.after_sound:
    pop bx
    pop ax 

.check_tick_overflow:
    pop si
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
laser_x dw 0
laser_y dw 0
laser_active db 0

y_base:
%assign __y 0
%rep 200
%if (__y & 1)
    dw 8192 + ((__y-1)/2)*80
%else
    dw (__y/2)*80
%endif
%assign __y __y + 1
%endrep

%include "sprites.asm"
%include "sounds.asm"
