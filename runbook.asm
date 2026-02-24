WAVE_KIND_ASTEROID         EQU 0
WAVE_KIND_ALIEN            EQU 1
WAVE_KIND_BOSS             EQU 2

WAVE_FOREVER               EQU 255
WAVE_DISABLE_ID            EQU 255

WAVE_DEF_KIND              EQU 0
WAVE_DEF_START             EQU 1
WAVE_DEF_PERIOD            EQU 3
WAVE_DEF_REPEATS           EQU 5
WAVE_DEF_SPAWNS            EQU 6
WAVE_DEF_GAP               EQU 7
WAVE_DEF_EXCLUSIVE         EQU 8
WAVE_DEF_STOP_ON_LAST_START EQU 9
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

RUNBOOK_WAVE_COUNT         EQU 3

; kind, start, period, repeats, spawns, gap, exclusive,
; stop_wave_on_last_start, on_complete_wave, on_complete_delay
runbook_defs:
    db WAVE_KIND_ASTEROID       ; kind
    dw 0                        ; start clock
    dw 40                       ; period
    db WAVE_FOREVER             ; repeats
    db 1                        ; only one asteroid per wave
    db 0                        ; no gap
    db 0                        ; not exclusive
    db WAVE_DISABLE_ID          ; stop_wave_on_last_start
    db WAVE_DISABLE_ID          ; on_complete_wave
    dw 0                        ; on_complete_delay

    db WAVE_KIND_ALIEN
    dw 320                      ; start clock at 320 cycles
    dw 640                      ; period
    db 4                        ; repeat 4 times
    db 8                        ; spawn 8 aliens per wave  
    db 10                       ; gap between spawns
    db 0                        ; not exclusive
    db 0
    db WAVE_KIND_BOSS           ; start wave 2 (WAVE_KIND_BOSS) on completion
    dw 200                      ; ...after 200 cycles

    db WAVE_KIND_BOSS
    dw 0
    dw 0
    db 0
    db 1
    db 0
    db 1
    db WAVE_DISABLE_ID
    db WAVE_DISABLE_ID
    dw 0

; ------------------------------ Spawn tuning per kind
asteroid_spawn_x     dw HSIZE-8
asteroid_spawn_y_range dw VSIZE-8
asteroid_vx          dw -2
asteroid_vy          dw 0
asteroid_move_mode   db 0
asteroid_points      dw 10

alien_spawn_x        dw HSIZE-16
alien_spawn_y        dw 140
alien_vx             dw -2
alien_vy             dw 3
alien_move_mode      db 1
alien_points         dw 100

boss_spawn_x         dw 200
boss_spawn_y         dw 64
boss_vx              dw -2
boss_vy              dw 0
boss_move_mode       db 1
boss_points          dw 1000

; ------------------------------ Runbook runtime
runbook_clock        dw 0
runbook_exclusive_owner db WAVE_DISABLE_ID
runbook_rt           times RUNBOOK_WAVE_COUNT*WAVE_RT_SIZE db 0
boss_active          db 0
