; rungine.asm - the runbook engine, which manages timed spawning of waves of enemies.
; The runbook is defined in data as a list of wave definitions, and the engine maintains 
; runtime state for each wave, including when to start the next spawn and how many 
;spawns are pending

; ------------------------------
; Reset the runbook state (runbook_rt).
runbook_reset:
    push bx
    push cx
    push di

    mov word [runbook_clock], 0
    mov byte [runbook_exclusive_owner], WAVE_DISABLE_ID
    mov byte [boss_active], 0

    mov di, runbook_rt
    mov cx, RUNBOOK_WAVE_COUNT*WAVE_RT_SIZE
.zero_rt:
    mov byte [di], 0
    inc di
    loop .zero_rt

    mov bx, runbook_defs
    mov di, runbook_rt
    mov cx, RUNBOOK_WAVE_COUNT
.init_wave:
    mov byte [di+WAVE_RT_ENABLED], 1
    mov al, [bx+WAVE_DEF_REPEATS]
    mov [di+WAVE_RT_REPEATS_LEFT], al
    mov ax, [bx+WAVE_DEF_START]
    mov [di+WAVE_RT_NEXT_START], ax
    mov byte [di+WAVE_RT_DELAY_TARGET], WAVE_DISABLE_ID
    add bx, WAVE_DEF_SIZE
    add di, WAVE_RT_SIZE
    loop .init_wave

    pop di
    pop cx
    pop bx
    ret

; -------------------------------
; Tick the runbook engine, processing any wave activations or spawns that are due.
runbook_tick:
    push bp
    push bx
    push cx
    push dx
    push si
    push di

    ; Advance the global runbook timeline one tick and clear last tick's lock owner.
    inc word [runbook_clock]
    mov byte [runbook_exclusive_owner], WAVE_DISABLE_ID

    ; Pass 1: process delayed activations and discover exclusive owner.
    xor bp, bp
    mov cx, RUNBOOK_WAVE_COUNT
    mov bx, runbook_defs
    mov di, runbook_rt
.pass1:
    ; Count down any delayed "arm wave X" request and fire when it reaches zero.
    mov al, [di+WAVE_RT_DELAY_TARGET]
    cmp al, WAVE_DISABLE_ID
    je .no_delay
    mov ax, [di+WAVE_RT_DELAY_REMAIN]
    cmp ax, 0
    je .delay_fire
    dec word [di+WAVE_RT_DELAY_REMAIN]
    jnz .no_delay
.delay_fire:
    mov al, [di+WAVE_RT_DELAY_TARGET]
    mov byte [di+WAVE_RT_DELAY_TARGET], WAVE_DISABLE_ID
    call runbook_arm_wave_by_id

.no_delay:
    ; Find first active exclusive wave and mark it as the only wave allowed to run this tick.
    cmp byte [runbook_exclusive_owner], WAVE_DISABLE_ID
    jne .next_pass1
    cmp byte [bx+WAVE_DEF_EXCLUSIVE], 0
    je .next_pass1
    cmp byte [di+WAVE_RT_PENDING], 0
    jne .set_owner
    mov al, [bx+WAVE_DEF_KIND]
    cmp al, WAVE_KIND_BOSS
    jne .next_pass1
    cmp byte [boss_active], 0
    je .next_pass1
.set_owner:
    mov ax, bp
    mov [runbook_exclusive_owner], al

.next_pass1:
    inc bp
    add bx, WAVE_DEF_SIZE
    add di, WAVE_RT_SIZE
    dec cx
    jnz .pass1

    ; Pass 2: start/spawn waves, honoring exclusive lock.
    xor bp, bp
    mov cx, RUNBOOK_WAVE_COUNT
    mov bx, runbook_defs
    mov di, runbook_rt
.pass2:
    ; If an exclusive wave owns this tick, every other wave is skipped.
    mov al, [runbook_exclusive_owner]
    cmp al, WAVE_DISABLE_ID
    je .lock_ok
    mov dx, bp
    cmp al, dl
    je .lock_ok
    jmp .next_pass2

.lock_ok:
    ; If wave is already in the middle of a spawn burst, go straight to spawn pacing.
    cmp byte [di+WAVE_RT_PENDING], 0
    jne .maybe_spawn

    ; Explicit arm (manual trigger or delayed trigger): start a fresh burst immediately.
    cmp byte [di+WAVE_RT_ARMED], 0
    je .check_auto_start
    mov byte [di+WAVE_RT_ARMED], 0
    mov al, [bx+WAVE_DEF_SPAWNS]
    mov [di+WAVE_RT_PENDING], al
    mov byte [di+WAVE_RT_GAP], 0
    jmp .maybe_spawn

.check_auto_start:
    ; Auto-start path: requires enabled wave, remaining repeats, and start time reached.
    cmp byte [di+WAVE_RT_ENABLED], 0
    je .next_pass2

    ; On last configured start, optional hook can disable another wave.
    mov al, [bx+WAVE_DEF_REPEATS]
    cmp al, 0
    je .next_pass2
    cmp al, WAVE_FOREVER
    je .check_start_time
    cmp byte [di+WAVE_RT_REPEATS_LEFT], 0
    je .next_pass2

.check_start_time:
    mov ax, [runbook_clock]
    cmp ax, [di+WAVE_RT_NEXT_START]
    jb .next_pass2

    ; Consume one repeat (except forever mode), schedule next cycle, and queue burst size.
    mov al, [bx+WAVE_DEF_REPEATS]
    cmp al, WAVE_FOREVER
    je .skip_last_start_hook
    cmp byte [di+WAVE_RT_REPEATS_LEFT], 1
    jne .skip_last_start_hook
    mov al, [bx+WAVE_DEF_STOP_ON_LAST_START]
    cmp al, WAVE_DISABLE_ID
    je .skip_last_start_hook
    call runbook_disable_wave_by_id
.skip_last_start_hook:

    mov al, [bx+WAVE_DEF_REPEATS]
    cmp al, WAVE_FOREVER
    je .skip_repeat_dec
    dec byte [di+WAVE_RT_REPEATS_LEFT]
.skip_repeat_dec:

    mov ax, [bx+WAVE_DEF_PERIOD]
    add [di+WAVE_RT_NEXT_START], ax

    mov al, [bx+WAVE_DEF_SPAWNS]
    mov [di+WAVE_RT_PENDING], al
    mov byte [di+WAVE_RT_GAP], 0

.maybe_spawn:
    ; Pending burst uses WAVE_RT_GAP as inter-spawn cooldown.
    cmp byte [di+WAVE_RT_PENDING], 0
    je .next_pass2
    cmp byte [di+WAVE_RT_GAP], 0
    je .do_spawn
    dec byte [di+WAVE_RT_GAP]
    jmp .next_pass2

.do_spawn:
    ; Attempt one spawn for this wave kind. On failure, keep pending count for later ticks.
    mov al, [bx+WAVE_DEF_KIND]
    push bx
    push di
    call runbook_spawn_kind
    pop di
    pop bx
    cmp al, 0
    je .next_pass2

    ; Successful spawn consumed one pending unit from this burst.
    dec byte [di+WAVE_RT_PENDING]
    jne .set_gap

    mov al, [bx+WAVE_DEF_REPEATS]
    cmp al, 0
    je .next_pass2
    cmp al, WAVE_FOREVER
    je .next_pass2
    cmp byte [di+WAVE_RT_REPEATS_LEFT], 0
    jne .next_pass2
    cmp byte [di+WAVE_RT_ARMED], 0
    jne .next_pass2

    ; If this was the final spawn of the final repeat, optionally schedule a delayed follow-up wave.
    mov al, [bx+WAVE_DEF_ON_COMPLETE_WAVE]
    cmp al, WAVE_DISABLE_ID
    je .next_pass2
    mov [di+WAVE_RT_DELAY_TARGET], al
    mov ax, [bx+WAVE_DEF_ON_COMPLETE_DELAY]
    mov [di+WAVE_RT_DELAY_REMAIN], ax
    jmp .next_pass2

.set_gap:
    ; More units remain in this burst, so arm the per-wave cooldown before next spawn.
    mov al, [bx+WAVE_DEF_GAP]
    mov [di+WAVE_RT_GAP], al

.next_pass2:
    inc bp
    add bx, WAVE_DEF_SIZE
    add di, WAVE_RT_SIZE
    dec cx
    jnz .pass2

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop bp
    ret

; AL = wave id
runbook_arm_wave_by_id:
    cmp al, RUNBOOK_WAVE_COUNT
    jae .done
    push bx
    push dx
    call runbook_get_rt_ptr_in_bx
    mov byte [bx+WAVE_RT_ENABLED], 1
    mov byte [bx+WAVE_RT_ARMED], 1
    pop dx
    pop bx
.done:
    ret

; AL = wave id
runbook_disable_wave_by_id:
    cmp al, RUNBOOK_WAVE_COUNT
    jae .done
    push bx
    push dx
    call runbook_get_rt_ptr_in_bx
    mov byte [bx+WAVE_RT_ENABLED], 0
    mov byte [bx+WAVE_RT_ARMED], 0
    mov byte [bx+WAVE_RT_PENDING], 0
    mov byte [bx+WAVE_RT_GAP], 0
    pop dx
    pop bx
.done:
    ret

; AL = wave id, returns BX = runbook_rt + id*WAVE_RT_SIZE
runbook_get_rt_ptr_in_bx:
    xor ah, ah
    add ax, ax              ; 2*id
    mov dx, ax              ; 2*id
    add ax, ax              ; 4*id
    add ax, ax              ; 8*id
    add ax, dx              ; 10*id
    mov bx, runbook_rt
    add bx, ax
    ret

; AL = wave kind. Returns AL = 1 on successful spawn, 0 otherwise.
runbook_spawn_kind:
    cmp al, WAVE_KIND_ASTEROID
    je .asteroid
    cmp al, WAVE_KIND_ALIEN
    je .alien
    cmp al, WAVE_KIND_BOSS
    je .boss
    xor al, al
    ret
.asteroid:
    call spawn_asteroid_kind
    ret
.alien:
    call spawn_alien_kind
    ret
.boss:
    call spawn_boss_kind
    ret

spawn_asteroid_kind:
    mov si, sprites_list
    mov cx, BOSS_SLOT_INDEX
.find_free_slot:
    cmp byte [si+SPRITE_COLLIDE], 6
    jae .spawn_here
    add si, SPRITE_STRUCT_SIZE
    loop .find_free_slot
    xor al, al
    ret

.spawn_here:
    mov di, asteroid
    call set_sprite_bitmap_and_cache

    mov ax, [asteroid_spawn_x]
    mov [si+SPRITE_X], ax
    shr ax, 1
    shr ax, 1
    mov [si+SPRITE_X_BYTE], ax

    call rand16
    xor dx, dx
    mov bx, [asteroid_spawn_y_range]
    div bx
    mov [si+SPRITE_Y], dx

    mov ax, [asteroid_vx]
    mov [si+SPRITE_VX], ax
    mov ax, [asteroid_vy]
    mov [si+SPRITE_VY], ax
    mov al, [asteroid_move_mode]
    mov [si+SPRITE_MOVE_MODE], al
    mov ax, [asteroid_points]
    mov [si+SPRITE_POINTS], ax

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

    mov al, 1
    ret

spawn_alien_kind:
    mov si, sprites_list
    mov cx, BOSS_SLOT_INDEX
.find_free_slot:
    cmp byte [si+SPRITE_COLLIDE], 6
    jae .spawn_here
    add si, SPRITE_STRUCT_SIZE
    loop .find_free_slot
    xor al, al
    ret

.spawn_here:
    mov di, alien_ship
    call set_sprite_bitmap_and_cache

    mov ax, [alien_spawn_x]
    mov [si+SPRITE_X], ax
    shr ax, 1
    shr ax, 1
    mov [si+SPRITE_X_BYTE], ax

    mov ax, [alien_spawn_y]
    mov [si+SPRITE_Y], ax
    mov ax, [alien_vx]
    mov [si+SPRITE_VX], ax
    mov ax, [alien_vy]
    mov [si+SPRITE_VY], ax
    mov al, [alien_move_mode]
    mov [si+SPRITE_MOVE_MODE], al
    mov ax, [alien_points]
    mov [si+SPRITE_POINTS], ax

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

    mov al, 1
    ret

spawn_boss_kind:
    cmp byte [boss_active], 0
    jne .fail

    push si
    push di
    push ax
    push bx

    mov si, sprites_list + BOSS_SLOT_INDEX*SPRITE_STRUCT_SIZE
    mov di, boss_ship
    call set_sprite_bitmap_and_cache

    mov ax, [boss_spawn_x]
    mov [si+SPRITE_X], ax
    shr ax, 1
    shr ax, 1
    mov [si+SPRITE_X_BYTE], ax

    mov ax, [boss_spawn_y]
    mov [si+SPRITE_Y], ax
    mov ax, [boss_vx]
    mov [si+SPRITE_VX], ax
    mov ax, [boss_vy]
    mov [si+SPRITE_VY], ax
    mov al, [boss_move_mode]
    mov [si+SPRITE_MOVE_MODE], al
    mov ax, [boss_points]
    mov [si+SPRITE_POINTS], ax

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

    mov byte [boss_active], 1

    pop bx
    pop ax
    pop di
    pop si

    mov al, 1
    ret

.fail:
    xor al, al
    ret
