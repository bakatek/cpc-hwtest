; GLITCH256 : GLITCH v4 sur 256 Ko d'extension (banks 0-3, pages &C4-&DF).
; Activites : LDI (lecture + ecriture) et PUSH (ecriture) dans chaque bank, la page
; tournant sur les 4 de la bank (&C4-&C7 + 8 x bank) ; puis LDI en RAM de base, ROM, NOP.
; Sur 6128 : bank 0 = RAM interne, banks 1-3 = PicoCPC -> comparaison sur la meme machine.
;  BASIC :  MEMORY &7FFF:LOAD"GLITCH256.BIN",&8000:CALL &8000
G256    equ 1
        include "glitch.asm"
