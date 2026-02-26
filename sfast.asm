; cga_scroll_boxes.asm
; NASM .COM program
; Conventions: routines dont' save AX,BX,CX,DX, but do save SI,DI,BP,ES if used. Stack params are WORDs unless noted otherwise. Screen buffer is accessed via ES.

; CLOCK_TICKS EQU 19912 ; number of PIT ticks for ~1/59.94 Hz delay (for smooth scrolling)
CLOCK_TICKS EQU 39824 ; number of PIT ticks for ~1/30s delay (for smooth scrolling)
CGA_BASE EQU 0B800h
HSCROLL_STEP EQU 2
PLAYER_SPRITE_INDEX EQU 31
BOSS_SLOT_INDEX EQU 23
HSIZE EQU 320
VSIZE EQU 184
MOUNTAIN_MAX_HEIGHT EQU 30
MOUNTAIN_COLOR EQU 22h
ASTEROID_SPAWN_CYCLE_DELAY EQU 20
ALIEN_WAVE_CYCLE_DELAY EQU 320
 
LASER_Y_OFFSET EQU 8 ; where the laser fires relative to the top of the ship sprite

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
    set_cga_palette 0,1,0

    call install_int9 ; keyboard interrupt handler for non-blocking input
    call install_int1c ; timer tick handler for smooth scrolling (optional, can also just poll BIOS tick flag without chaining handler)
    mov ax, CLOCK_TICKS ; set clock to 59.94hz
    call sync_vertical_retrace
    call set_pit_rate
    mov word [start_addr], 0   ; start address in WORDS

    ; Seed RNG from BIOS timer tick
    mov ah, 00h
    int 1Ah            ; CX:DX = ticks since midnight
    mov [seed], dx
    call show_title_screen
    call seed_sprites_list_defaults
    call start_new_game


; ------------------------------------------------- MAIN LOOP
; Scroll via CGA CRTC start address (infinite)
scroll_loop:
;    call sync_vertical_retrace     ; wait for vertical retrace

    ; Wait for BIOS tick (INT 1Ch) to sync scrolling
.wait_tick:
    cmp byte [tick_flag], 0
    jne .got_tick
    jmp .wait_tick
.got_tick:
    mov byte [tick_flag], 0

%ifdef DEBUG
    set_cga_palette 1,1,0
%endif

    ; Erase sprites at old positions
    call erase_sprites
    ; Erase laser at old position
    call erase_laser


    cmp byte [boss_active], 0
    jne .no_scroll_frame

    test [ticks_elapsed], 3
    jz .horizontal_frame_scroll   ; scroll every other 4th tick
    ; if frame doesn't scroll, then just update sprite positions and continue
.no_scroll_frame:
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

    ; Spawn/update runbook scheduler.
    call runbook_tick

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
    sub word [sprites_list+PLAYER_SPRITE_INDEX*SPRITE_STRUCT_SIZE+SPRITE_Y], 4
    sub word [sprites_list+PLAYER_SPRITE_INDEX*SPRITE_STRUCT_SIZE+SPRITE_VBUF_ADDR], 160
    jmp .continue
.down:
    add word [sprites_list+PLAYER_SPRITE_INDEX*SPRITE_STRUCT_SIZE+SPRITE_Y], 4
    add word [sprites_list+PLAYER_SPRITE_INDEX*SPRITE_STRUCT_SIZE+SPRITE_VBUF_ADDR], 160
    jmp .continue
.left:
    sub word [sprites_list+PLAYER_SPRITE_INDEX*SPRITE_STRUCT_SIZE+SPRITE_X], 4
    dec word [sprites_list+PLAYER_SPRITE_INDEX*SPRITE_STRUCT_SIZE+SPRITE_VBUF_ADDR]
    dec word [sprites_list+PLAYER_SPRITE_INDEX*SPRITE_STRUCT_SIZE+SPRITE_X_BYTE]
    jmp .continue
.right:
    add word [sprites_list+PLAYER_SPRITE_INDEX*SPRITE_STRUCT_SIZE+SPRITE_X], 4
    inc word [sprites_list+PLAYER_SPRITE_INDEX*SPRITE_STRUCT_SIZE+SPRITE_VBUF_ADDR]
    inc word [sprites_list+PLAYER_SPRITE_INDEX*SPRITE_STRUCT_SIZE+SPRITE_X_BYTE]
    jmp .continue
.fire:
    cmp byte [player_respawn_delay], 0
    jne .continue
    cmp byte [sprites_list+PLAYER_SPRITE_INDEX*SPRITE_STRUCT_SIZE+SPRITE_COLLIDE], 6
    je .continue
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

    cmp byte [sprites_list+PLAYER_SPRITE_INDEX*SPRITE_STRUCT_SIZE+SPRITE_COLLIDE], 6
    jne .boss_status_check
    cmp byte [lives], 0
    je exit_to_dos
    cmp byte [player_respawn_delay], 0
    je .do_respawn
    dec byte [player_respawn_delay]
    jmp .boss_status_check
.do_respawn:
    call respawn_player

    ; Boss resolution:
    ; - collide=6: player killed boss => victory
    ; - collide=7 or x<=0 while alive: boss reached left side => restart game
.boss_status_check:
    cmp byte [boss_active], 0
    je .check_game_over
    mov al, [sprites_list+BOSS_SLOT_INDEX*SPRITE_STRUCT_SIZE+SPRITE_COLLIDE]
    cmp al, 6
    je .boss_victory
    cmp al, 7
    je .boss_failed
    cmp al, 0
    jne .check_game_over
    cmp word [sprites_list+BOSS_SLOT_INDEX*SPRITE_STRUCT_SIZE+SPRITE_X], 0
    jg .check_game_over
.boss_failed:
    call start_new_game
    jmp scroll_loop
.boss_victory:
    mov byte [victory_flag], 1
    jmp exit_to_dos
.check_game_over:
    cmp byte [lives], 0
    je exit_to_dos

%ifdef DEBUG
    set_cga_palette 0,1,1
%endif

    jmp scroll_loop

    ; Back to text mode
exit_to_dos:
    call restore_int1c
    call restore_int9
    xor ax, ax
    call set_pit_rate ; set clock back to 18.2hz

    stop_sound
    mov ax, game_over_text
    cmp byte [victory_flag], 0
    je .print_end_text
    mov ax, victory_text
.print_end_text:
    mov bx, ax
    mov ax, 0bbh
    push ax                        ; color mask
    mov ax, 96
    push ax                        ; y (row 12 * 8)
    mov ax, 128
    push ax                        ; x (col 16 * 8)
    push bx                        ; ASCIIZ pointer
    call write_string
    add sp, 8


    mov ah, 00h     ; Wait for key
    int 16h


    mov ax, 0003h ; restore text mode
    int 10h
    ret

; -----------------------------
; draw the next mountain column on the right edge. Mountains are 20 pixels tall and use pattern 0AAh.
next_mountain:
    ; Delete the last 8 columns of the screen
    mov ax, HSIZE-8
    push ax
    xor ax, ax
    push ax
    mov ax, VSIZE-1
    push ax
    xor ax, ax
    push ax          ; pattern 00h = black
    call fill_rect_8px_aligned
    add sp, 8

    ; Draw a random-height box at x=312..319 from y=0
    mov ax, HSIZE-8
    push ax
    xor ax, ax
    push ax
    call rand16
    xor dx, dx
    mov bx, MOUNTAIN_MAX_HEIGHT
    div bx             ; DX = 0..199
    push dx
    mov ax, MOUNTAIN_COLOR
    push ax
    call fill_rect_8px_aligned
    add sp, 8

    ; draw a random-height box at x=312..319 from the bottom up
    mov ax, HSIZE-8
    push ax
    call rand16
    xor dx, dx
    mov bx, MOUNTAIN_MAX_HEIGHT
    div bx             ; DX = 0..199
    neg dx
    add dx,VSIZE-1
    push dx

    mov ax, VSIZE-1
    push ax
    mov ax, MOUNTAIN_COLOR
    push ax
    call fill_rect_8px_aligned
    add sp, 8
    ret

; -----------------------------
; Laser: up to 4 independent 8-pixel white dashes, x aligned to 4.
erase_laser:
    push si
    push di
    mov cx, 4
    xor si, si
.loop:
    cmp byte [laser_active_arr+si], 0
    je .next
    mov di, si
    shl di, 1
    mov bx, [laser_y_arr+di]
    shl bx, 1
    mov bx, [y_base+bx]
    mov ax, [start_addr]
    shl ax, 1
    add bx, ax
    mov ax, [laser_x_arr+di]
    shr ax, 1
    shr ax, 1                    ; x / 4
    add bx, ax
    xor ax, ax
    mov [es:bx], ax              ; clear 8 pixels (2 bytes)
.next:
    inc si
    loop .loop
    pop di
    pop si
.done:
    ret

advance_laser:
    push si
    push di
    mov cx, 4
    xor si, si
.loop:
    cmp byte [laser_active_arr+si], 0
    je .next
    mov di, si
    shl di, 1
    mov ax, [laser_x_arr+di]
    add ax, 12
    mov [laser_x_arr+di], ax
    ; 8-pixel dash occupies x..x+7.
    cmp ax, HSIZE-8
    jb .next
    mov byte [laser_active_arr+si], 0
.next:
    inc si
    loop .loop
    pop di
    pop si
.done:
    ret

draw_laser:
    push si
    push di
    mov cx, 4
    xor si, si
.loop:
    cmp byte [laser_active_arr+si], 0
    je .next
    mov di, si
    shl di, 1
    mov bx, [laser_y_arr+di]
    shl bx, 1
    mov bx, [y_base+bx]
    mov ax, [start_addr]
    shl ax, 1
    add bx, ax
    mov ax, [laser_x_arr+di]
    shr ax, 1
    shr ax, 1                    ; x / 4
    add bx, ax
    mov ax, 0FFFFh
    mov [es:bx], ax              ; draw 8 white pixels (2 bytes)
.next:
    inc si
    loop .loop
    pop di
    pop si
.done:
    ret

fire_laser:
    ; Launch from 4 pixels right of the player sprite, 4 pixels below sprite top.
    ; Uses round-robin slot replacement across 4 independent beams.
    mov bx, [sprites_list+PLAYER_SPRITE_INDEX*SPRITE_STRUCT_SIZE+SPRITE_PTR]
    mov ax, [sprites_list+PLAYER_SPRITE_INDEX*SPRITE_STRUCT_SIZE+SPRITE_X]
    add ax, [bx]       ; right edge = x + sprite width
    ; Keep 4-pixel boundary alignment without ever moving inside the ship.
    add ax, 3
    and ax, 0FFFCh     ; align up to next multiple of 4
    cmp ax, HSIZE-8
    jae .done
    mov cx, ax

    mov ax, [sprites_list+PLAYER_SPRITE_INDEX*SPRITE_STRUCT_SIZE+SPRITE_Y]
    add ax, LASER_Y_OFFSET
    cmp ax, VSIZE-1
    jae .done
    mov dx, ax

    xor bx, bx
    mov bl, [laser_next_slot]
    mov al, bl
    inc byte [laser_next_slot]
    and byte [laser_next_slot], 3

    shl bx, 1
    mov [laser_x_arr+bx], cx
    mov [laser_y_arr+bx], dx

    xor bx, bx
    mov bl, al
    mov byte [laser_active_arr+bx], 1
.done:
    ret

; -----------------------------
; Capture immutable startup sprite list into a working seed buffer.
seed_sprites_list_defaults:
    push si
    push di
    push cx
    cld
    mov si, sprites_list
    mov di, sprites_list_seed
    mov cx, (32*SPRITE_STRUCT_SIZE)/2
    rep movsw
    pop cx
    pop di
    pop si
    ret

; Reset all gameplay state and restart a fresh run.
start_new_game:
    push ax
    push bx
    push cx
    push si
    push di

    stop_sound
    call clear_screen

    ; Restore sprite list defaults.
    cld
    mov si, sprites_list_seed
    mov di, sprites_list
    mov cx, (32*SPRITE_STRUCT_SIZE)/2
    rep movsw

    mov word [start_addr], 0
    mov bx, [start_addr]
    call set_start_addr

    mov word [score], 0
    mov byte [lives], 3
    mov byte [player_respawn_delay], 0
    call runbook_reset
    mov byte [victory_flag], 0

    call init_sprites
    call update_score_display

    mov ax, [sprites_list+PLAYER_SPRITE_INDEX*SPRITE_STRUCT_SIZE+SPRITE_X]
    mov [player_spawn_x], ax
    mov ax, [sprites_list+PLAYER_SPRITE_INDEX*SPRITE_STRUCT_SIZE+SPRITE_Y]
    mov [player_spawn_y], ax

    set_cga_palette 0,1,1

    ; Fill the top 2 scanlines for wrap-around visuals.
    xor ax, ax
    push ax
    push ax
    mov ax, HSIZE-1
    push ax
    mov ax, 1
    push ax
    mov ax, MOUNTAIN_COLOR
    push ax
    call fill_rect
    add sp, 10

    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

; -----------------------------
; Title screen: draw title sprite, play melody, print captions, wait for key.
show_title_screen:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    ; Clear screen
    call clear_screen

    ; Draw title_screen sprite at x=80, y=50.
    mov byte [title_dummy_collide], 0
    mov bx, title_dummy_collide
    mov si, title_screen+6
    mov di, 2020                 ; y_base[50] + (80/4) = 2000 + 20
    mov cx, 100
    mov dx, 40
    mov ax, 0
    call draw_sprite

    play_sound melody

    ; Print "(C) THX 2026" at text cursor-equivalent position: col 13,row 20 => x=104,y=160.
    mov ax, 077h
    push ax
    mov ax, 160
    push ax
    mov ax, 104
    push ax
    mov ax, title_line_1
    push ax
    call write_string
    add sp, 8

    ; Print "PRESS SPACE TO PLAY" at col 10,row 22 => x=80,y=176.
    mov ax, 077h
    push ax
    mov ax, 176
    push ax
    mov ax, 80
    push ax
    mov ax, title_line_2
    push ax
    call write_string
    add sp, 8

.wait_key:
    call get_scancode
    cmp al, 39h            ; space (continue)
    jne .wait_key

    stop_sound
    mov byte [sc_head], 0
    mov byte [sc_tail], 0
    call clear_screen

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
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
; Entry layout (30 bytes):
;   dw sprite_ptr, dw x, dw y, dw vx, dw vy, dw vbuf_addr, db collide_flag, db move_mode
;   dw scroll_delta_bytes, dw accum_x, dw accum_y, dw draw_bytes, dw height, dw pic_ptr
;   dw x_byte (x/4), dw points
init_sprites:
    push si
    mov cl, [sprites_count]
    xor ch, ch
    mov si, sprites_list

.loop:
    push cx

    mov bx, [si+SPRITE_PTR]
    mov ax, [bx+4]                     ; bytes_per_row
    mov [si+SPRITE_DRAW_BYTES], ax
    mov ax, [bx+2]                     ; height_pixels
    mov [si+SPRITE_HEIGHT], ax
    lea ax, [bx+6]                     ; pic_ptr = sprite_ptr + 6
    mov [si+SPRITE_PIC_PTR], ax

    ; Compute and cache the sprite's video buffer start address for faster drawing later.
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

    ; Draw only active sprites at init time.
    cmp byte [si+SPRITE_COLLIDE], 6
    jae .skip_init_draw

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
.skip_init_draw:

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
    cmp al, 6
    jae .addr_done
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
    cmp si, sprites_list + PLAYER_SPRITE_INDEX*SPRITE_STRUCT_SIZE
    je .player_hit
    mov ax, [si+SPRITE_POINTS]
    or ax, ax
    jz .no_score_add
    add [score], ax
    call update_score_display
.no_score_add:
    play_sound sound_explosion
    mov bx, explode_1
    mov dl, 2
    jmp .set_explosion_sprite

.player_hit:
    cmp byte [lives], 0
    je .player_no_lives

    dec byte [lives]
    mov al, [lives]
    cmp al, 2
    je .hide_life_30
    cmp al, 1
    je .hide_life_29
    mov byte [sprites_list+28*SPRITE_STRUCT_SIZE+SPRITE_COLLIDE], 7
    jmp .no_score_add
.hide_life_30:
    mov byte [sprites_list+30*SPRITE_STRUCT_SIZE+SPRITE_COLLIDE], 7
    jmp .no_score_add
.hide_life_29:
    mov byte [sprites_list+29*SPRITE_STRUCT_SIZE+SPRITE_COLLIDE], 7
    jmp .no_score_add

.player_no_lives:
    mov byte [si+SPRITE_COLLIDE], 6
    jmp .addr_done

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
    cmp si, sprites_list + PLAYER_SPRITE_INDEX*SPRITE_STRUCT_SIZE
    jne .set_explode_done
    mov byte [player_respawn_delay], 40
.set_explode_done:
    mov byte [si+SPRITE_COLLIDE], 6
.to_explode_7:
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

; -----------------------------
; Update score digits shown by sprites 24..27.
; sprite 24 = thousands, 25 = hundreds, 26 = tens, 27 = ones
update_score_display:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov ax, [score]
    mov bx, 10

    ; ones -> sprite 27
    xor dx, dx
    div bx
    mov cx, ax
    mov si, sprites_list + 27*SPRITE_STRUCT_SIZE
    mov ax, dx
    shl ax, 1
    xchg ax, bx
    mov di, [numeral_ptrs+bx]
    xchg ax, bx
    call set_sprite_bitmap_and_cache
    mov ax, cx

    ; tens -> sprite 26
    xor dx, dx
    div bx
    mov cx, ax
    mov si, sprites_list + 26*SPRITE_STRUCT_SIZE
    mov ax, dx
    shl ax, 1
    xchg ax, bx
    mov di, [numeral_ptrs+bx]
    xchg ax, bx
    call set_sprite_bitmap_and_cache
    mov ax, cx

    ; hundreds -> sprite 25
    xor dx, dx
    div bx
    mov cx, ax
    mov si, sprites_list + 25*SPRITE_STRUCT_SIZE
    mov ax, dx
    shl ax, 1
    xchg ax, bx
    mov di, [numeral_ptrs+bx]
    xchg ax, bx
    call set_sprite_bitmap_and_cache
    mov ax, cx

    ; thousands -> sprite 24
    xor dx, dx
    div bx
    mov si, sprites_list + 24*SPRITE_STRUCT_SIZE
    mov ax, dx
    shl ax, 1
    xchg ax, bx
    mov di, [numeral_ptrs+bx]
    xchg ax, bx
    call set_sprite_bitmap_and_cache

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; SI = sprite entry, DI = new sprite bitmap pointer
set_sprite_bitmap_and_cache:
    mov [si+SPRITE_PTR], di
    mov ax, [di+4]
    mov [si+SPRITE_DRAW_BYTES], ax
    mov ax, [di+2]
    mov [si+SPRITE_HEIGHT], ax
    lea ax, [di+6]
    mov [si+SPRITE_PIC_PTR], ax
    ret


; Respawn sprite 31 at saved spawn position and reactivate it.
respawn_player:
    push ax
    push bx
    push si
    push di

    mov si, sprites_list + PLAYER_SPRITE_INDEX*SPRITE_STRUCT_SIZE
    mov di, big_space_ship
    call set_sprite_bitmap_and_cache

    mov ax, [player_spawn_x]
    mov [si+SPRITE_X], ax
    shr ax, 1
    shr ax, 1
    mov [si+SPRITE_X_BYTE], ax

    mov ax, [player_spawn_y]
    mov [si+SPRITE_Y], ax

    mov word [si+SPRITE_VX], 0
    mov word [si+SPRITE_VY], 0
    mov byte [si+SPRITE_MOVE_MODE], 0
    mov word [si+SPRITE_POINTS], 0
    mov word [si+SPRITE_SCROLL_DELTA_BYTES], 0
    mov word [si+SPRITE_ACCUM_X], 0
    mov word [si+SPRITE_ACCUM_Y], 0

    mov bx, [si+SPRITE_Y]
    shl bx, 1
    mov bx, [y_base+bx]
    mov ax, [start_addr]
    shl ax, 1
    add bx, ax
    add bx, [si+SPRITE_X_BYTE]
    mov [si+SPRITE_VBUF_ADDR], bx

    mov byte [si+SPRITE_COLLIDE], 0
    play_sound melody

    pop di
    pop si
    pop bx
    pop ax
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
; This routine also plays sound effects.
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

%include "graphics.asm"
%include "rungine.asm"

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
title_dummy_collide db 0
title_line_1 db "(C) THX 2026",0
title_line_2 db "PRESS SPACE TO PLAY",0
game_over_text db "GAME OVER",0
victory_text db "VICTORY",0

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
score dw 0
lives db 3
player_respawn_delay db 0
victory_flag db 0
bios_charset_ptr dw 0FA6Eh,0f000h      ; CGA font data 
player_spawn_x dw 64
player_spawn_y dw 64
numeral_ptrs dw numeral_0, numeral_1, numeral_2, numeral_3, numeral_4, numeral_5, numeral_6, numeral_7, numeral_8, numeral_9

; ------------------------------ Laser state (4 independent beams)
laser_x_arr dw 0, 0, 0, 0
laser_y_arr dw 0, 0, 0, 0
laser_active_arr db 0, 0, 0, 0
laser_next_slot db 0

; ------------------------------ Precomputed Y offsets for CGA mode 4 row addressing math
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
%include "runbook.asm"

sprites_list_seed times (32*SPRITE_STRUCT_SIZE) db 0
