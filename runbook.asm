WAVE_KIND_ASTEROID         EQU 0
WAVE_KIND_ALIEN            EQU 1
WAVE_KIND_BOSS             EQU 2
WAVE_KIND_STOP             EQU 3

WAVE_FOREVER               EQU 255
WAVE_DISABLE_ID            EQU 255

WAVE_DEF_KIND              EQU 0
WAVE_DEF_START             EQU 1
WAVE_DEF_PERIOD            EQU 3
WAVE_DEF_REPEATS           EQU 5
WAVE_DEF_SPAWNS            EQU 6
WAVE_DEF_GAP               EQU 7
WAVE_DEF_EXCLUSIVE         EQU 8
WAVE_DEF_ACTION            EQU 9
WAVE_DEF_ON_COMPLETE_WAVE  EQU 10
WAVE_DEF_ON_COMPLETE_DELAY EQU 11
WAVE_DEF_SIZE              EQU 13

WAVE_RT_ENABLED            EQU 0
WAVE_RT_REPEATS_LEFT       EQU 1
WAVE_RT_PENDING            EQU 2
WAVE_RT_GAP                EQU 3
WAVE_RT_NEXT_START         EQU 4
WAVE_RT_ARMED              EQU 6
WAVE_RT_DELAY_TARGET       EQU 7
WAVE_RT_DELAY_REMAIN       EQU 8
WAVE_RT_SIZE               EQU 10

RUNBOOK_WAVE_COUNT         EQU 4

SPAWN_SLOT_POOLED          EQU 0
SPAWN_SLOT_FIXED           EQU 1

SPAWN_PROFILE_SPRITE_PTR   EQU 0
SPAWN_PROFILE_SLOT_MODE    EQU 2
SPAWN_PROFILE_SLOT_INDEX   EQU 3
SPAWN_PROFILE_X_BASE       EQU 4
SPAWN_PROFILE_X_RANGE      EQU 6
SPAWN_PROFILE_Y_BASE       EQU 8
SPAWN_PROFILE_Y_RANGE      EQU 10
SPAWN_PROFILE_VX           EQU 12
SPAWN_PROFILE_VY           EQU 14
SPAWN_PROFILE_POINTS       EQU 16
SPAWN_PROFILE_MOVE_MODE    EQU 18
SPAWN_PROFILE_SIZE         EQU 19

; kind, start, period, repeats, spawns, gap, exclusive,
; action, on_complete_wave, on_complete_delay
runbook_defs:
    db WAVE_KIND_ASTEROID       ; kind
    dw 0                        ; start clock
    dw 40                       ; period
    db WAVE_FOREVER             ; repeats
    db 1                        ; only one asteroid per wave
    db 0                        ; no gap
    db 0                        ; not exclusive
    db 0                        ; action
    db WAVE_DISABLE_ID          ; on_complete_wave
    dw 0                        ; on_complete_delay

    db WAVE_KIND_ALIEN
    dw 640                      ; start clock
    dw 640                      ; period
    db 4                        ; repeat 4 times
    db 8                        ; spawn 8 aliens per wave  
    db 10                       ; gap between spawns
    db 0                        ; not exclusive
    db 0                        ; action
    db WAVE_DISABLE_ID          ; no chained wave
    dw 0

    db WAVE_KIND_STOP
    dw 2759                     ; just before boss start
    dw 0
    db 1
    db 1
    db 0
    db 1                        ; run as exclusive action
    db 0
    db WAVE_DISABLE_ID
    dw 0

    db WAVE_KIND_BOSS
    dw 2760
    dw 0
    db 1
    db 1
    db 0
    db 1
    db 0
    db WAVE_DISABLE_ID
    dw 0

; ------------------------------ Spawn profile per kind:
; x/y are fixed when range=0, otherwise base + random(0..range).
spawn_profiles:
    ; asteroid
    dw asteroid
    db SPAWN_SLOT_POOLED
    db 0
    dw HSIZE-8
    dw 0
    dw 0
    dw VSIZE-8
    dw -2
    dw 0
    dw 10
    db 0

    ; alien
    dw alien_ship
    db SPAWN_SLOT_POOLED
    db 0
    dw HSIZE-16
    dw 0
    dw 140
    dw 0
    dw -2
    dw 3
    dw 100
    db 1

    ; boss
    dw boss_ship
    db SPAWN_SLOT_FIXED
    db BOSS_SLOT_INDEX
    dw 200
    dw 0
    dw 64
    dw 0
    dw -2
    dw 0
    dw 1000
    db 0

; ------------------------------ Runbook runtime
runbook_clock        dw 0
runbook_exclusive_owner db WAVE_DISABLE_ID
runbook_rt           times RUNBOOK_WAVE_COUNT*WAVE_RT_SIZE db 0
boss_active          db 0
