; =====================================================================
;  GATEST - stabilite du Gate Array (40007/40010) - CPC 464 - RASM
;
;  Ce qui est verifie en continu :
;   1. INTERRUPTIONS : le GA doit generer exactement 6 interruptions par
;      trame (300 Hz), synchronisees sur la VSYNC (lue sur le PPI).
;      Toute trame avec un autre nombre = erreur "INT/TRAME".
;   2. RAFALES D'OUT : ecritures en rafale dans le GA (bord = "rasters",
;      encres 2/3, registre de mode) comme dans les demos.
;   3. PAGINATION ROM : on bascule la ROM basse ON/OFF par petits blocs :
;      avec ROM ON, #1000-#3FFF doit relire la ROM (somme constante),
;      avec ROM OFF, la RAM dessous doit garder son motif.
;   4. HALT : 12 HALT par boucle (synchro typique des demos).
;
;  Affichage mis a jour toutes les 50 trames (1 s). Les bandes de couleur
;  dans le bord sont normales (c'est la rafale d'OUT).
;
;  BASIC :  MEMORY &7FFF:LOAD"GATEST.BIN",&8000:CALL &8000
; =====================================================================

        org #8000

;---------------------------------------------------------------------
; INITIALISATION
; - vecteur IM 1 : on ecrit "JP ga_int" en RAM #0038 (la ROM basse est coupee,
;   donc le Z80 lit bien la RAM a cette adresse)
; - motif de reference en RAM #1000-#3FFF (sous la ROM basse)
; - somme de reference de la ROM basse #1000-#3FFF
; - RAZ des compteurs, RAZ du compteur d'interruptions du GA (bit 4 = #9E), EI
; - lib_iff = 1 : la lib sait qu'elle doit reactiver les interruptions
;---------------------------------------------------------------------
ga_start:
        di
        ld sp,#9000
        call lib_init
        ; vecteur IM 1 en RAM (ROM basse coupee)
        ld a,#C3
        ld (#0038),a
        ld hl,ga_int
        ld (#0039),hl
        im 1
        call ga_fill
        call ga_romsum
        ld (ga_romref),hl
        call lib_cls
        ld de,#0000
        call lib_locate
        ld hl,ga_m0
        call lib_prt
        ld de,#0300
        call lib_locate
        ld hl,ga_m1
        call lib_prt
        ld de,#0400
        call lib_locate
        ld hl,ga_m2
        call lib_prt
        ld de,#0500
        call lib_locate
        ld hl,ga_m3
        call lib_prt
        ld de,#0600
        call lib_locate
        ld hl,ga_m4
        call lib_prt
        ld de,#0700
        call lib_locate
        ld hl,ga_m5
        call lib_prt
        ld de,#0800
        call lib_locate
        ld hl,ga_m6
        call lib_prt
        ld de,#0A00
        call lib_locate
        ld hl,ga_m7
        call lib_prt
        ld hl,ga_vars           ; remise a zero des compteurs
        ld b,ga_vend-ga_vars
ga_z1:  ld (hl),0
        inc hl
        djnz ga_z1
        ld bc,#7F9E             ; mode 2 + RAZ du compteur d'interruptions du GA
        out (c),c
        ld a,1
        ld (lib_iff),a
        ei

; ---------------------------------------------------------------------
;---------------------------------------------------------------------
; BOUCLE PRINCIPALE (interruptions ACTIVES pendant tout le test)
; 1) rafale de 256 x 7 OUT dans le GA : bord (bandes colorees visibles),
;    encres 2 et 3 (invisibles en mode 2), registre de mode (meme valeur)
; 2) pagination : somme de la ROM basse lue par petits blocs ROM ON
; 3) controle de la RAM sous la ROM (ROM OFF)
; 4) 12 HALT (synchro type demo) ; affichage toutes les 50 trames
;---------------------------------------------------------------------
ga_loop:
        ; 1) rafale d'OUT dans le GA
        ld b,#7F
        ld e,0
ga_p1:  ld a,#10                ; bord
        out (c),a
        ld a,e
        and #1F
        or #40
        out (c),a
        ld a,2                  ; encre 2 (invisible en mode 2)
        out (c),a
        ld a,e
        xor #1F
        and #1F
        or #40
        out (c),a
        ld a,3                  ; encre 3
        out (c),a
        ld a,e
        and #1F
        or #40
        out (c),a
        ld a,#8E                ; registre de mode (meme valeur)
        out (c),a
        dec e
        jr nz,ga_p1
        ld a,#54
        call lib_border

        ; 2) pagination ROM : la ROM doit etre relue a l'identique
        call ga_romsum
        ld de,(ga_romref)
        or a
        sbc hl,de
        jr z,ga_ok1
        ld hl,(ga_romerr)
        inc hl
        ld (ga_romerr),hl
ga_ok1:
        ; 3) la RAM sous la ROM doit etre intacte
        call ga_ramchk
        jr z,ga_ok2
        ld hl,(ga_ramerr)
        inc hl
        ld (ga_ramerr),hl
        call ga_fill
ga_ok2:
        ; 4) HALT x12 (2 trames)
        ld b,12
ga_h1:  halt
        djnz ga_h1

        ; affichage toutes les 50 trames
        ld a,(ga_disp)
        or a
        jr z,ga_loop
        xor a
        ld (ga_disp),a
        call ga_show
        jp ga_loop

; ---------------------------------------------------------------------
; interruption : compte les INT entre deux VSYNC (doit valoir 6)
;---------------------------------------------------------------------
; INTERRUPTION (300 Hz) : compte les INT depuis la derniere VSYNC.
; La VSYNC est lue sur le bit 0 du port B du PPI (&F5xx). Le GA se resynchronise
; sur la VSYNC : une INT tombe pendant chaque VSYNC, et il doit y en avoir
; EXACTEMENT 6 par trame (312 lignes / 52). Autre valeur = erreur INT/TRAME
; (sauf la toute premiere trame, ignoree via ga_sync).
;---------------------------------------------------------------------
ga_int:
        push af
        push bc
        push hl
        ld hl,(ga_icnt)
        inc hl
        ld (ga_icnt),hl
        ld a,(ga_ipf)
        inc a
        ld (ga_ipf),a
        ld b,#F5
        in a,(c)
        rra                     ; bit 0 du port B = VSYNC
        jr nc,ga_ie
        ld a,(ga_ipf)           ; INT pendant la VSYNC : fin de trame
        ld (ga_last),a
        cp 6
        jr z,ga_i1
        ld a,(ga_sync)          ; ignorer la premiere trame
        or a
        jr z,ga_i1
        ld hl,(ga_interr)
        inc hl
        ld (ga_interr),hl
ga_i1:  ld a,1
        ld (ga_sync),a
        xor a
        ld (ga_ipf),a
        ld hl,(ga_frames)
        inc hl
        ld (ga_frames),hl
        ld a,(ga_dcnt)
        inc a
        cp 50
        jr nz,ga_i2
        ld (ga_disp),a
        xor a
ga_i2:  ld (ga_dcnt),a
ga_ie:  pop hl
        pop bc
        pop af
        ei
        ret

; ---------------------------------------------------------------------
;---------------------------------------------------------------------
; Ecrit le motif L xor H xor #A5 dans #1000-#3FFF (RAM sous la ROM basse).
;---------------------------------------------------------------------
ga_fill:                        ; motif en RAM #1000-#3FFF
        ld hl,#1000
        ld bc,#3000
ga_f1:  ld a,l
        xor h
        xor #A5
        ld (hl),a
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,ga_f1
        ret

;---------------------------------------------------------------------
; Verifie ce motif (ROM basse coupee). Z = OK.
;---------------------------------------------------------------------
ga_ramchk:                      ; Z = OK
        ld hl,#1000
        ld bc,#3000
ga_rc1: ld a,l
        xor h
        xor #A5
        cp (hl)
        ret nz
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,ga_rc1
        ret

;---------------------------------------------------------------------
; Somme 16 bits de la ROM basse #1000-#3FFF.
; Lue par blocs de 32 octets avec DI + ROM ON, puis ROM OFF + EI : les
; interruptions ne sont jamais bloquees plus de quelques lignes (sinon l'INT de
; VSYNC serait vue en retard et compterait faux).
;---------------------------------------------------------------------
ga_romsum:                      ; HL = somme de #1000-#3FFF lue ROM ON
        ld hl,0                 ; par blocs de 32 octets (INT bloquees peu de temps)
        ld de,#1000
ga_rs1: di
        ld bc,#7F8A
        out (c),c
        ld b,32
ga_rs2: ld a,(de)
        add a,l
        ld l,a
        jr nc,ga_rs3
        inc h
ga_rs3: inc de
        djnz ga_rs2
        ld bc,#7F8E
        out (c),c
        ld a,(lib_iff)
        or a
        jr z,ga_rs4
        ei
ga_rs4: ld a,d
        cp #40
        jr nz,ga_rs1
        ret

;---------------------------------------------------------------------
; Affiche les compteurs ; message d'erreur si l'un d'eux n'est pas nul.
;---------------------------------------------------------------------
ga_show:
        ld de,#0318
        call lib_locate
        ld hl,(ga_frames)
        call lib_hex16
        ld de,#0418
        call lib_locate
        ld hl,(ga_icnt)
        call lib_hex16
        ld de,#0518
        call lib_locate
        ld a,(ga_last)
        call lib_hex8
        ld de,#0618
        call lib_locate
        ld hl,(ga_interr)
        call lib_hex16
        ld de,#0718
        call lib_locate
        ld hl,(ga_romerr)
        call lib_hex16
        ld de,#0818
        call lib_locate
        ld hl,(ga_ramerr)
        call lib_hex16
        ld hl,(ga_interr)       ; bord rouge permanent si une erreur
        ld de,(ga_romerr)
        add hl,de
        ld de,(ga_ramerr)
        add hl,de
        ld a,h
        or l
        ret z
        ld de,#0A00
        call lib_locate
        ld hl,ga_m8
        jp lib_prt

ga_m0:  db "GATEST 464 - stabilite du Gate Array (INT, OUT, ROM, HALT)",0
ga_m1:  db "Trames (50/s)       : &",0
ga_m2:  db "Interruptions       : &",0
ga_m3:  db "INT derniere trame  : &        (doit etre 06)",0
ga_m4:  db "ERREURS INT/TRAME   : &",0
ga_m5:  db "ERREURS ROM basse   : &",0
ga_m6:  db "ERREURS RAM sous ROM: &",0
ga_m7:  db "Tout doit rester a 0000. Laisser tourner 30 min a 1 h.          ",0
ga_m8:  db "*** ERREUR DETECTEE : le Gate Array (ou son environnement) decroche ***",0

;---------------------------------------------------------------------
; VARIABLES (remises a zero au demarrage, de ga_vars a ga_vend)
;---------------------------------------------------------------------
ga_vars:
ga_icnt:   dw 0
ga_frames: dw 0
ga_interr: dw 0
ga_romerr: dw 0
ga_ramerr: dw 0
ga_ipf:    db 0
ga_last:   db 0
ga_sync:   db 0
ga_dcnt:   db 0
ga_disp:   db 0
ga_vend:
ga_romref: dw 0

        include "cpclib.asm"
ga_fin:
        assert ga_fin < #8F00
        save "GATEST.BIN",#8000,ga_fin-#8000,AMSDOS
