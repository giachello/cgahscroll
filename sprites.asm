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
SPRITE_SCROLL_DELTA_BYTES equ 14
SPRITE_ACCUM_X equ 16
SPRITE_ACCUM_Y equ 18
SPRITE_DRAW_BYTES equ 20
SPRITE_HEIGHT equ 22
SPRITE_PIC_PTR equ 24
SPRITE_STRUCT_SIZE equ 26

cosine_table_40 dw 150,	149,	148,	145,	140,	135,	129,	123,	115,	108,	100,	92,	85,	77,	71,	65,	60,	55,	52,	51,	50,	51,	52,	55,	60,	65,	71,	77,	85,	92,	100,	108,	115,	123,	129,	135,	140,	145,	148,	149

sprites_list:
    dw space_ship
    dw 8            ; x
    dw 8            ; y
    dw 0              ; vx
    dw 0              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide 0= no collision, 1=collision (overlaps non-background pixels), 2-5 animation of explosion, 6 not visible, skip drawing
    db 0            ; movement mode: 0=linear vy, 1=cosine (vy is index into cosine_table_40)
    dw 0              ; scroll bytes since last update
    dw 0              ; accumulated x movement
    dw 0              ; accumulated y movement
    dw 0              ; cached draw bytes
    dw 0              ; cached height
    dw 0              ; cached pic ptr

    dw alien_ship
    dw 300            ; x
    dw 150            ; y
    dw -1              ; vx
    dw 0              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 1        ; movement mode: cosine40
    dw 0              ; scroll bytes since last update
    dw 0              ; accumulated x movement
    dw 0              ; accumulated y movement
    dw 0              ; cached draw bytes
    dw 0              ; cached height
    dw 0              ; cached pic ptr

    dw asteroid
    dw 200            ; x
    dw 10            ; y
    dw 0              ; vx
    dw 0              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0
    dw 0              ; scroll bytes since last update
    dw 0              ; accumulated x movement
    dw 0              ; accumulated y movement
    dw 0              ; cached draw bytes
    dw 0              ; cached height
    dw 0              ; cached pic ptr

    dw asteroid
    dw 200            ; x
    dw 20            ; y
    dw 0              ; vx
    dw 0              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0
    dw 0              ; scroll bytes since last update
    dw 0              ; accumulated x movement
    dw 0              ; accumulated y movement
    dw 0              ; cached draw bytes
    dw 0              ; cached height
    dw 0              ; cached pic ptr

    dw asteroid
    dw 200            ; x
    dw 30            ; y
    dw 0              ; vx
    dw 0              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0
    dw 0              ; scroll bytes since last update
    dw 0              ; accumulated x movement
    dw 0              ; accumulated y movement
    dw 0              ; cached draw bytes
    dw 0              ; cached height
    dw 0              ; cached pic ptr

    dw asteroid
    dw 200            ; x
    dw 40            ; y
    dw 0              ; vx
    dw 0              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0
    dw 0              ; scroll bytes since last update
    dw 0              ; accumulated x movement
    dw 0              ; accumulated y movement
    dw 0              ; cached draw bytes
    dw 0              ; cached height
    dw 0              ; cached pic ptr

    dw asteroid
    dw 200            ; x
    dw 50            ; y
    dw -4              ; vx
    dw 4              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0
    dw 0              ; scroll bytes since last update
    dw 0              ; accumulated x movement
    dw 0              ; accumulated y movement
    dw 0              ; cached draw bytes
    dw 0              ; cached height
    dw 0              ; cached pic ptr

    dw asteroid
    dw 200            ; x
    dw 60            ; y
    dw 0              ; vx
    dw 0              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0
    dw 0              ; scroll bytes since last update
    dw 0              ; accumulated x movement
    dw 0              ; accumulated y movement
    dw 0              ; cached draw bytes
    dw 0              ; cached height
    dw 0              ; cached pic ptr

    dw asteroid
    dw 200            ; x
    dw 70            ; y
    dw 0              ; vx
    dw 0              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0
    dw 0              ; scroll bytes since last update
    dw 0              ; accumulated x movement
    dw 0              ; accumulated y movement
    dw 0              ; cached draw bytes
    dw 0              ; cached height
    dw 0              ; cached pic ptr

    dw asteroid
    dw 200            ; x
    dw 80            ; y
    dw 4              ; vx
    dw -1              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0
    dw 0              ; scroll bytes since last update
    dw 0              ; accumulated x movement
    dw 0              ; accumulated y movement
    dw 0              ; cached draw bytes
    dw 0              ; cached height
    dw 0              ; cached pic ptr

    dw asteroid
    dw 200            ; x
    dw 90            ; y
    dw 0              ; vx
    dw 0              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0
    dw 0              ; scroll bytes since last update
    dw 0              ; accumulated x movement
    dw 0              ; accumulated y movement
    dw 0              ; cached draw bytes
    dw 0              ; cached height
    dw 0              ; cached pic ptr

    dw asteroid
    dw 200            ; x
    dw 100            ; y
    dw 0              ; vx
    dw 0              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0
    dw 0              ; scroll bytes since last update
    dw 0              ; accumulated x movement
    dw 0              ; accumulated y movement
    dw 0              ; cached draw bytes
    dw 0              ; cached height
    dw 0              ; cached pic ptr

    dw asteroid
    dw 200            ; x
    dw 110            ; y
    dw 4              ; vx
    dw -2              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0
    dw 0              ; scroll bytes since last update
    dw 0              ; accumulated x movement
    dw 0              ; accumulated y movement
    dw 0              ; cached draw bytes
    dw 0              ; cached height
    dw 0              ; cached pic ptr

    dw asteroid
    dw 200            ; x
    dw 120            ; y
    dw 0              ; vx
    dw 0              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0
    dw 0              ; scroll bytes since last update
    dw 0              ; accumulated x movement
    dw 0              ; accumulated y movement
    dw 0              ; cached draw bytes
    dw 0              ; cached height
    dw 0              ; cached pic ptr

    dw asteroid
    dw 200            ; x
    dw 130            ; y
    dw 0             ; vx
    dw 0              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0
    dw 0              ; scroll bytes since last update
    dw 0              ; accumulated x movement
    dw 0              ; accumulated y movement
    dw 0              ; cached draw bytes
    dw 0              ; cached height
    dw 0              ; cached pic ptr

    dw asteroid
    dw 200            ; x
    dw 140            ; y
    dw 0              ; vx
    dw 0              ; vy
    dw 0FFFFh       ; vbuf_addr
    db 0              ; collide
    db 0
    dw 0              ; scroll bytes since last update
    dw 0              ; accumulated x movement
    dw 0              ; accumulated y movement
    dw 0              ; cached draw bytes
    dw 0              ; cached height
    dw 0              ; cached pic ptr


align 2

alien_ship dw 16,8,4,alien_ship+8
db 00h,020h,00h,080h
db 00h,0AAh,0AAh,0A0h
db 0Ah,09h,06h,0Ah
db 00h,080h,0A0h,020h
db 00h,08h,02h,00h
db 02h,020h,00h,088h
db 02h,02h,058h,08h
db 00h,02Ah,0AAh,080h
space_ship dw 16,8,4,space_ship+8
db 00h,00h,00h,00h
db 00h,00h,05h,040h
db 00h,06h,0A0h,040h
db 00h,015h,054h,00h
db 00h,00h,03Ch,00h
db 035h,055h,00h,094h
db 00h,01Ah,0A9h,00h
db 00h,00h,00h,00h
asteroid dw 8,8,2,asteroid+8
db 01h,050h
db 011h,011h
db 044h,011h
db 04h,014h
db 04h,044h
db 051h,04h
db 010h,041h
db 01h,040h
hatched_box dw 8,8,2,hatched_box+8
db 099h,099h
db 099h,099h
db 099h,099h
db 099h,099h
db 066h,066h
db 066h,066h
db 066h,066h
db 066h,066h
explode_1 dw 8,8,2,explode_1+8
db 00h,00h
db 00h,00h
db 01h,080h
db 00h,00h
db 00h,00h
db 00h,040h
db 00h,010h
db 00h,00h
explode_2 dw 8,8,2,explode_2+8
db 00h,00h
db 04h,080h
db 010h,04h
db 00h,010h
db 01h,010h
db 02h,010h
db 04h,080h
db 00h,00h
explode_3 dw 8,8,2,explode_3+8
db 04h,010h
db 022h,048h
db 00h,081h
db 010h,018h
db 010h,084h
db 048h,0C4h
db 06h,0Ch
db 01h,00h
explode_4 dw 8,8,2,explode_4+8
db 080h,030h
db 00h,0C2h
db 020h,048h
db 020h,082h
db 023h,08h
db 084h,030h
db 0Ch,020h
db 08h,00h
