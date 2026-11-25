; =====================================================================
;  PWRTEST - charge maximale de l'alimentation - CPC 464 - RASM
;
;  Charges cumulees :
;   - MOTEUR du lecteur K7 (bit 4 du port C du PPI) : de loin la plus
;     grosse charge du 464 -> appuyer sur PLAY SANS cassette
;   - SON : 3 voies en carre ~110 Hz, en phase, volume 15 (ampli HP interne)
;   - CPU + RAM a 100 % : PUSH 16 Ko, LDIR 16 Ko vers l'ecran, relecture
;     POP, avec des mots alternes #FF00/#00FF (commutation maximale du bus)
;   - ecran : toutes les encres + bord en blanc vif
;  Deux regimes qui alternent toutes les ~8 s :
;   - charge FIXE (tout allume)
;   - charge PULSEE ~2 Hz (moteur + son ON/OFF) : appels de courant brusques,
;     le pire cas pour la regulation et les decouplages
;  Toutes les ~16 s, ecran d'etat 2 s. Erreur RAM => arret, ecran rouge.
;
;  BASIC :  MEMORY &7FFF:LOAD"PWRTEST.BIN",&8000:CALL &8000
; =====================================================================

PW_BUF  equ #4000               ; tampon #4000-#7FFF (16 Ko)

        org #8000

;---------------------------------------------------------------------
; INITIALISATION : consignes a l'ecran (10 s pour appuyer sur PLAY),
; programmation de l'AY (3 voies en carre ~110 Hz, periode #238 avec une
; horloge AY de 1 MHz), moteur ON, ecran tout blanc.
;---------------------------------------------------------------------
pw_start:
        di
        ld sp,#9000
        call lib_init
        call lib_silence
        call lib_cls
        ld hl,pw_intro
        ld d,0
pw_t1:  push de
        push hl
        ld e,0
        call lib_locate
        pop hl
        call lib_prt
        inc hl
        pop de
        inc d
        inc d
        ld a,(hl)
        or a
        jr nz,pw_t1
        ld h,22                 ; ~10 s pour appuyer sur PLAY
        call lib_wait
        ; son : 3 voies, periode #238 (~110 Hz), tonalites ON, bruit OFF
        ld hl,pw_psgi
pw_s1:  ld a,(hl)
        cp #FF
        jr z,pw_s2
        inc hl
        ld c,(hl)
        inc hl
        push hl
        call lib_psgw
        pop hl
        jr pw_s1
pw_s2:  call pw_on
        call pw_white
        ld hl,0
        ld (pw_iter),hl

; ---------------------------------------------------------------------
;---------------------------------------------------------------------
; BOUCLE DE CHARGE (~0,25 s)
; 1) 8192 PUSH : #4000-#7FFF rempli de #FF00 ou #00FF (alterne a chaque boucle :
;    chaque ligne de donnees bascule a chaque acces = courant maximal)
; 2) LDIR 16 Ko vers l'ecran (invisible : toutes les encres sont blanches)
; 3) relecture de l'ecran par 8192 POP : la moindre erreur arrete le test
; 4) regime : bit 5 de la boucle = 0 -> charge FIXE ; = 1 -> charge PULSEE
;    (moteur + son ON/OFF une boucle sur deux, ~2 Hz)
;---------------------------------------------------------------------
pw_loop:
        ld hl,#FF00             ; motif alterne a chaque boucle
        ld a,(pw_iter)
        rra
        jr nc,pw_p1
        ld hl,#00FF
pw_p1:  ld (pw_pat),hl
        ; 1) PUSH 16 Ko dans #4000-#7FFF
        ld (pw_sp),sp
        ld sp,PW_BUF+#4000
        ld a,128                ; 128 x 64 PUSH = 16 Ko
pw_l1:
        repeat 64
        push hl
        rend
        dec a
        jp nz,pw_l1
        ld sp,(pw_sp)
        ; 2) LDIR 16 Ko vers l'ecran (invisible : encres blanches)
        ld hl,PW_BUF
        ld de,#C000
        ld bc,#4000
        ldir
        ; 3) relecture de l'ecran par POP
        ld (pw_sp),sp
        ld sp,#C000
        ld de,(pw_pat)
        xor a                   ; 256 x 32 POP = 16 Ko
pw_l3:
        repeat 32
        pop hl
        or a
        sbc hl,de
        jp nz,pw_bad
        rend
        dec a
        jp nz,pw_l3
        ld sp,(pw_sp)
        ; 4) regime fixe / pulse
        ld a,(pw_iter)
        and #20
        jr z,pw_fix
        ld a,(pw_iter)
        rra
        jr c,pw_fix
        call pw_off
        jr pw_nx
pw_fix: call pw_on
pw_nx:  ld hl,(pw_iter)
        inc hl
        ld (pw_iter),hl
        ld a,l
        and #3F
        jp nz,pw_loop
        call pw_status
        jp pw_loop

; ---------------------------------------------------------------------
;---------------------------------------------------------------------
; Moteur ON (bit 4 du port C du PPI, garde dans lib_pcb) + volumes a 15.
; pw_off : moteur OFF + volumes a 0.
;---------------------------------------------------------------------
pw_on:  ld a,#10                ; moteur ON
        ld (lib_pcb),a
        ld b,#F6
        out (c),a
        ld c,15
        jr pw_vol
pw_off: xor a                   ; moteur OFF
        ld (lib_pcb),a
        ld b,#F6
        out (c),a
        ld c,0
pw_vol: ld a,8
        push bc
        call lib_psgw
        pop bc
        ld a,9
        push bc
        call lib_psgw
        pop bc
        ld a,10
        jp lib_psgw

;---------------------------------------------------------------------
; Les 16 encres et le bord en blanc vif (#4B).
;---------------------------------------------------------------------
pw_white:                       ; 16 encres + bord en blanc vif
        ld bc,#7F00
pw_w1:  out (c),c
        ld a,#4B
        out (c),a
        inc c
        ld a,c
        cp 16
        jr nz,pw_w1
        ld a,#10
        out (c),a
        ld a,#4B
        out (c),a
        ret

;---------------------------------------------------------------------
; Ecran d'etat ~2 s toutes les 64 boucles.
;---------------------------------------------------------------------
pw_status:                      ; ecran d'etat ~2 s
        call lib_inks
        call lib_cls
        ld de,#0000
        call lib_locate
        ld hl,pw_m0
        call lib_prt
        ld de,#0200
        call lib_locate
        ld hl,pw_m1
        call lib_prt
        ld hl,(pw_iter)
        call lib_hex16
        ld de,#0300
        call lib_locate
        ld hl,pw_m2
        call lib_prt
        ld a,#52
        call lib_border
        ld h,5
        call lib_wait
        jp pw_white

; erreur : (SP-2) = mot fautif, HL = lu - attendu
;---------------------------------------------------------------------
; Erreur : SP pointe juste apres le mot fautif ; HL = lu - attendu.
;---------------------------------------------------------------------
pw_bad: ld (pw_bsp),sp
        ld sp,(pw_sp)
        add hl,de               ; HL = valeur lue
        ld (pw_rd),hl
        call pw_off
        call lib_silence
        call lib_inks
        call lib_cls
        ld a,#4C
        call lib_border
        ld de,#0000
        call lib_locate
        ld hl,pw_m0
        call lib_prt
        ld de,#0200
        call lib_locate
        ld hl,pw_e1
        call lib_prt
        ld de,#0400
        call lib_locate
        ld hl,pw_e2
        call lib_prt
        ld hl,(pw_bsp)
        dec hl
        dec hl
        call lib_hex16
        ld hl,pw_e3
        call lib_prt
        ld hl,(pw_pat)
        call lib_hex16
        ld hl,pw_e4
        call lib_prt
        ld hl,(pw_rd)
        call lib_hex16
        ld de,#0600
        call lib_locate
        ld hl,pw_m1
        call lib_prt
        ld hl,(pw_iter)
        call lib_hex16
pw_hang:
        jr pw_hang

; registre, valeur
pw_psgi:
        db 0,#38, 1,#02, 2,#38, 3,#02, 4,#38, 5,#02, 6,0, 7,#38
        db #FF

pw_intro:
        db "PWRTEST 464 - charge maximale de l'alimentation",0
        db "1. Appuie sur PLAY SANS cassette : le moteur K7 va tourner",0
        db "2. Son carre ~110 Hz volume max sur 3 voies (molette volume a fond)",0
        db "3. Ecran blanc, CPU + RAM a 100 % (copies #FF00/#00FF en continu)",0
        db "4. Alternance ~8 s : charge FIXE / charge PULSEE 2 Hz",0
        db "5. Mesure le 5 V a l'oscilloscope SUR LA CARTE (RAM, Gate Array)",0
        db "6. Etat toutes les ~16 s. Arret + bord rouge si la RAM perd une donnee",0
        db "Demarrage dans 10 secondes...",0
        db 0

pw_m0:  db "PWRTEST 464 - charge maximale",0
pw_m1:  db "Boucles : &",0
pw_m2:  db "Aucune erreur. Ca repart...",0
pw_e1:  db "*** ERREUR RAM SOUS CHARGE ***",0
pw_e2:  db "Adresse : &",0
pw_e3:  db "   attendu : &",0
pw_e4:  db "   lu : &",0

pw_iter: dw 0
pw_pat:  dw 0
pw_sp:   dw 0
pw_bsp:  dw 0
pw_rd:   dw 0

        include "cpclib.asm"
pw_fin:
        assert pw_fin < #8F00
        save "PWRTEST.BIN",#8000,pw_fin-#8000,AMSDOS
