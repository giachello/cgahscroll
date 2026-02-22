; sounds.asm
; Sound data for the game
; Each sound is a sequence of 16-bit values representing frequencies , terminated by a 0

sound_ptr dw 0

sound_laser 	dw	1193,	1255,	1325,	1403,	1491,	1590,	1704,	1835,	1988,	2169,	2386,	0

sound_explosion	dw	16361,	16413,	22935,	25186,	18304,	27607,	27737,	0

melody	dw 	1809,	1521,	1207,	904,	1015,	1207,	1521,	1809,	1809,	1521,	1207,	1015,	1207,	1521,	1809,	0ffffh,	1521,	1355,	1207,	1521,	1809,	1521,	1207,	904,	1015,	1207,	1521,	1355,	1207,	904,	1015,	0

