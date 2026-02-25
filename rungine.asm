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
    ; Register ownership in pass 1:
    ; - BP = wave index
    ; - BX = runbook_defs cursor
    ; - DI = runbook_rt cursor
    ; - CX = loop counter (must survive full pass body)
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
    ; Register ownership in pass 2:
    ; - BP = wave index
    ; - BX = runbook_defs cursor
    ; - DI = runbook_rt cursor
    ; - CX = loop counter (callee calls must not leak CX changes)
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
    ; runbook_spawn_kind clobbers CX internally; preserve pass-2 loop state.
    push bx
    push cx
    push di
    call runbook_spawn_kind
    pop di
    pop cx
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
    cmp al, RUNBOOK_WAVE_COUNT
    jae .fail
    cmp al, WAVE_KIND_STOP
    je .stop_all
    cmp al, WAVE_KIND_BOSS
    jne .kind_ok
    cmp byte [boss_active], 0
    jne .fail
.kind_ok:
    cmp al, WAVE_KIND_BOSS
    je .spawn_sprite
    cmp al, WAVE_KIND_ALIEN
    je .spawn_sprite
    cmp al, WAVE_KIND_ASTEROID
    jne .fail

.spawn_sprite:
    push ax
    call runbook_get_spawn_profile_ptr_in_bx

    mov al, [bx+SPAWN_PROFILE_SLOT_MODE]
    cmp al, SPAWN_SLOT_FIXED
    je .fixed_slot

    mov si, sprites_list
    mov cx, BOSS_SLOT_INDEX
.find_free_slot:
    cmp byte [si+SPRITE_COLLIDE], 6
    jae .have_slot
    add si, SPRITE_STRUCT_SIZE
    loop .find_free_slot
    jmp .fail_pop_kind

.fixed_slot:
    mov si, sprites_list
    xor cx, cx
    mov cl, [bx+SPAWN_PROFILE_SLOT_INDEX]
    jcxz .have_slot
.seek_fixed_slot:
    add si, SPRITE_STRUCT_SIZE
    loop .seek_fixed_slot

.have_slot:
    mov di, [bx+SPAWN_PROFILE_SPRITE_PTR]
    call set_sprite_bitmap_and_cache

    mov ax, [bx+SPAWN_PROFILE_X_BASE]
    mov cx, [bx+SPAWN_PROFILE_X_RANGE]
    cmp cx, 0
    je .x_ready
    push ax
    push bx
    push cx
    call rand16
    pop cx
    pop bx
    inc cx
    xor dx, dx
    div cx
    pop ax
    add ax, dx
.x_ready:
    mov [si+SPRITE_X], ax
    shr ax, 1
    shr ax, 1
    mov [si+SPRITE_X_BYTE], ax

    mov ax, [bx+SPAWN_PROFILE_Y_BASE]
    mov cx, [bx+SPAWN_PROFILE_Y_RANGE]
    cmp cx, 0
    je .y_ready
    push ax
    push bx
    push cx
    call rand16
    pop cx
    pop bx
    inc cx
    xor dx, dx
    div cx
    pop ax
    add ax, dx
.y_ready:
    mov [si+SPRITE_Y], ax

    mov ax, [bx+SPAWN_PROFILE_VX]
    mov [si+SPRITE_VX], ax
    mov ax, [bx+SPAWN_PROFILE_VY]
    mov [si+SPRITE_VY], ax
    mov al, [bx+SPAWN_PROFILE_MOVE_MODE]
    mov [si+SPRITE_MOVE_MODE], al
    mov ax, [bx+SPAWN_PROFILE_POINTS]
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

    pop dx
    cmp dl, WAVE_KIND_BOSS
    jne .not_boss
    mov byte [boss_active], 1
.not_boss:
    mov al, 1
    ret

.fail_pop_kind:
    pop dx
.fail:
    xor al, al
    ret

.stop_all:
    call runbook_stop_other_waves
    mov al, 1
    ret

; AL = wave kind, returns BX = spawn_profiles + kind*SPAWN_PROFILE_SIZE.
runbook_get_spawn_profile_ptr_in_bx:
    xor ah, ah
    mov dx, ax              ; kind
    add ax, ax              ; 2*kind
    mov cx, ax              ; 2*kind
    add ax, ax              ; 4*kind
    add ax, ax              ; 8*kind
    add ax, ax              ; 16*kind
    add ax, cx              ; 18*kind
    add ax, dx              ; 19*kind
    mov bx, spawn_profiles
    add bx, ax
    ret

; Stop all non-boss waves immediately (disable + clear pending state).
runbook_stop_other_waves:
    push bx
    push cx
    push di

    mov cx, RUNBOOK_WAVE_COUNT
    mov bx, runbook_defs
    mov di, runbook_rt
.loop:
    mov al, [bx+WAVE_DEF_KIND]
    cmp al, WAVE_KIND_BOSS
    je .next
    cmp al, WAVE_KIND_STOP
    je .next
    mov byte [di+WAVE_RT_ENABLED], 0
    mov byte [di+WAVE_RT_ARMED], 0
    mov byte [di+WAVE_RT_PENDING], 0
    mov byte [di+WAVE_RT_GAP], 0
    mov byte [di+WAVE_RT_DELAY_TARGET], WAVE_DISABLE_ID
    mov word [di+WAVE_RT_DELAY_REMAIN], 0
.next:
    add bx, WAVE_DEF_SIZE
    add di, WAVE_RT_SIZE
    dec cx
    jnz .loop

    pop di
    pop cx
    pop bx
    ret
