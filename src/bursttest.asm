; =====================================================================
;  BURSTTEST - acces bus a vitesse max (rafales "facon demo") - CPC 464
;  RASM
;
;  Chaque boucle enchaine, sans interruption (DI), ce que font les demos :
;   1. LDI deroules : copie de 4 Ko #4000 -> #5000, puis comparaison
;   2. PUSH blast : 12 Ko (#9000-#BFFF) remplis a coups de PUSH (motif
;      change a chaque boucle), puis relus a coups de POP et verifies
;   3. POP read : somme de 4 Ko lus par POP, comparee a la reference
;   4. Rafales d'OUT : GA (encres 2-15, registre de mode) et CRTC (R12/R13)
;   5. PSG : ecriture puis RELECTURE des registres 0-6, 7, 11, 12 de l'AY
;      via le PPI (volumes a 0 : silencieux)
;
;  Un compteur d'erreurs par categorie ; bord rouge des qu'une erreur apparait.
;  BASIC :  MEMORY &7FFF:LOAD"BURSTTEST.BIN",&8000:CALL &8000
; =====================================================================

BU_SRC  equ #4000               ; 4 Ko source
BU_DST  equ #5000               ; 4 Ko destination LDI
BU_BLS  equ #9000               ; zone PUSH blast #9000-#BFFF (12 Ko)

        org #8000

;---------------------------------------------------------------------
; INITIALISATION : DI, source pseudo-aleatoire 4 Ko en #4000, somme de
; reference par POP, RAZ des compteurs, affichage des libelles.
;---------------------------------------------------------------------
bu_start:
        di
        ld sp,#9000
        call lib_init
        call lib_silence
        ; source pseudo-aleatoire
        ld hl,#ACE1
        ld de,BU_SRC
        ld bc,#1000
bu_i1:  srl h
        rr l
        jr nc,bu_i2
        ld a,h
        xor #B4
        ld h,a
bu_i2:  ld a,l
        ld (de),a
        inc de
        dec bc
        ld a,b
        or c
        jr nz,bu_i1
        call bu_popsum
        ld (bu_ref),hl
        ld hl,bu_vars
        ld b,bu_vend-bu_vars
bu_z1:  ld (hl),0
        inc hl
        djnz bu_z1
        call lib_cls
        ld de,#0000
        call lib_locate
        ld hl,bu_m0
        call lib_prt
        ld hl,bu_lab
        ld d,3
bu_lb:  push de
        push hl
        ld e,0
        call lib_locate
        pop hl
        call lib_prt
        inc hl
        pop de
        inc d
        ld a,(hl)
        or a
        jr nz,bu_lb

; ---------------------------------------------------------------------
;---------------------------------------------------------------------
; BOUCLE : chaque etape reproduit un acces "demo" a vitesse maximale.
; 1) 4096 LDI deroules (#4000 -> #5000), puis comparaison octet par octet
;---------------------------------------------------------------------
bu_loop:
        ; 1) LDI deroules : 64 x 64
        ld hl,BU_SRC
        ld de,BU_DST
        ld a,64
bu_l1:
        repeat 64
        ldi
        rend
        dec a
        jp nz,bu_l1
        ld hl,BU_SRC
        ld de,BU_DST
        ld bc,#1000
bu_v1:  ld a,(de)
        cp (hl)
        jr nz,bu_e1
        inc hl
        inc de
        dec bc
        ld a,b
        or c
        jr nz,bu_v1
        jr bu_ok1
bu_e1:  ld hl,(bu_err1)
        inc hl
        ld (bu_err1),hl
bu_ok1:
        ; 2) PUSH blast puis verification par POP
        ld a,(bu_iter)
        and 7
        add a,a
        ld e,a
        ld d,0
        ld hl,bu_pats
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (bu_pat),de
        ex de,hl                ; HL = motif
        ld (bu_sp),sp
        ld sp,#C000
        ld a,96                 ; 96 x 64 PUSH = 12 Ko
;---------------------------------------------------------------------
; 2) PUSH BLAST : SP = #C000, 6144 PUSH deroules remplissent #9000-#BFFF
;    avec un motif 16 bits (change a chaque boucle), puis 6144 POP relisent
;    et comparent (SBC HL,DE). L'ecran n'est pas touche : l'etat reste lisible.
;---------------------------------------------------------------------
bu_l2:
        repeat 64
        push hl
        rend
        dec a
        jp nz,bu_l2
        ld sp,BU_BLS
        ld de,(bu_pat)
        ld a,192                ; 192 x 32 POP = 12 Ko
bu_l3:
        repeat 32
        pop hl
        or a
        sbc hl,de
        jp nz,bu_e2
        rend
        dec a
        jp nz,bu_l3
        ld sp,(bu_sp)
        jr bu_ok2
bu_e2:  ld sp,(bu_sp)
        ld hl,(bu_err2)
        inc hl
        ld (bu_err2),hl
;---------------------------------------------------------------------
; 3) somme de la source par 2048 POP, comparee a la reference
;---------------------------------------------------------------------
bu_ok2:
        ; 3) somme par POP de la source
        call bu_popsum
        ld de,(bu_ref)
        or a
        sbc hl,de
        jr z,bu_ok3
        ld hl,(bu_err3)
        inc hl
        ld (bu_err3),hl
;---------------------------------------------------------------------
; 4) rafales d'OUT : GA (encres 2-15, registre de mode) et CRTC (R12/R13
;    reecrits avec les memes valeurs : aucun effet visible, mais le bus I/O
;    est sollicite comme dans une demo)
;---------------------------------------------------------------------
bu_ok3:
        ; 4) rafales d'OUT GA + CRTC (valeurs sans effet visible)
        ld e,0
bu_o1:  ld b,#7F
        ld a,e
        and #0F
        or 2                    ; encres 2..15
        out (c),a
        ld a,e
        and #1F
        or #40
        out (c),a
        ld a,#8E
        out (c),a
        ld bc,#BC0C
        out (c),c
        ld bc,#BD30
        out (c),c
        ld bc,#BC0D
        out (c),c
        ld bc,#BD00
        out (c),c
        dec e
        jr nz,bu_o1
        ; 5) PSG ecriture / relecture
        call bu_psg
        ; affichage
        ld hl,(bu_iter)
        inc hl
        ld (bu_iter),hl
        call bu_show
        jp bu_loop

; ---------------------------------------------------------------------
;---------------------------------------------------------------------
; HL = somme 16 bits de la source (4 Ko) lue par POP deroules.
;---------------------------------------------------------------------
bu_popsum:                      ; HL = somme 16 bits de BU_SRC (4 Ko) par POP
        ld (bu_sp),sp
        ld sp,BU_SRC
        ld hl,0
        ld a,64                 ; 64 x 32 POP = 4 Ko
bu_ps1:
        repeat 32
        pop de
        add hl,de
        rend
        dec a
        jp nz,bu_ps1
        ld sp,(bu_sp)
        ret

;---------------------------------------------------------------------
; 5) PSG : chaque registre du tableau est ecrit avec une valeur
; pseudo-aleatoire (masque, bits forces) puis RELU via le PPI (port A en
; entree). Compare sous masque : les bits inexistants de l'AY relisent 0.
; Volumes laisses a 0 et mixer a #3F : silencieux.
;---------------------------------------------------------------------
bu_psg:                         ; table : registre, masque alea, bits forces, masque compare
        ld ix,bu_ptab
bu_pg1: ld a,(ix+0)
        cp #FF
        ret z
        ld hl,(bu_rnd)          ; valeur pseudo-aleatoire
        srl h
        rr l
        jr nc,bu_pg2
        ld a,h
        xor #B4
        ld h,a
bu_pg2: ld (bu_rnd),hl
        ld a,l
        and (ix+1)
        or (ix+2)
        ld (bu_pv),a
        ld c,a
        ld a,(ix+0)
        call lib_psgw
        ld a,(ix+0)
        call lib_psgr
        and (ix+3)
        ld c,a
        ld a,(bu_pv)
        and (ix+3)
        cp c
        jr z,bu_pg3
        ld hl,(bu_err4)
        inc hl
        ld (bu_err4),hl
bu_pg3: ld de,4
        add ix,de
        jr bu_pg1

;---------------------------------------------------------------------
; registre, masque aleatoire, bits forces, masque de comparaison
;---------------------------------------------------------------------
bu_ptab:
        db 0,#FF,0,#FF, 1,#0F,0,#0F, 2,#FF,0,#FF, 3,#0F,0,#0F
        db 4,#FF,0,#FF, 5,#0F,0,#0F, 6,#1F,0,#1F, 7,#00,#3F,#3F
        db 11,#FF,0,#FF, 12,#FF,0,#FF
        db 8,#00,0,#1F, 9,#00,0,#1F, 10,#00,0,#1F
        db #FF

;---------------------------------------------------------------------
; Affiche les compteurs ; bord rouge si au moins une erreur.
;---------------------------------------------------------------------
bu_show:
        ld de,#0320
        call lib_locate
        ld hl,(bu_iter)
        call lib_hex16
        ld de,#0420
        call lib_locate
        ld hl,(bu_err1)
        call lib_hex16
        ld de,#0520
        call lib_locate
        ld hl,(bu_err2)
        call lib_hex16
        ld de,#0620
        call lib_locate
        ld hl,(bu_err3)
        call lib_hex16
        ld de,#0720
        call lib_locate
        ld hl,(bu_err4)
        call lib_hex16
        ld hl,(bu_err1)
        ld de,(bu_err2)
        add hl,de
        ld de,(bu_err3)
        add hl,de
        ld de,(bu_err4)
        add hl,de
        ld a,h
        or l
        ld a,#54
        jr z,bu_sh1
        ld a,#4C
bu_sh1: jp lib_border

bu_pats:
        dw #0000,#FFFF,#00FF,#FF00,#5555,#AAAA,#33CC,#C33C

bu_m0:  db "BURSTTEST 464 - rafales bus (LDI / PUSH / POP / OUT / PSG)",0
bu_lab: db "Boucles                         : &",0
        db "ERREURS copie LDI deroulee      : &",0
        db "ERREURS PUSH blast / POP        : &",0
        db "ERREURS lecture POP (somme)     : &",0
        db "ERREURS relecture PSG (AY)      : &",0
        db 0

bu_vars:
bu_iter: dw 0
bu_err1: dw 0
bu_err2: dw 0
bu_err3: dw 0
bu_err4: dw 0
bu_vend:
bu_ref:  dw 0
bu_pat:  dw 0
bu_sp:   dw 0
bu_rnd:  dw #1D0F
bu_pv:   db 0

        include "cpclib.asm"
bu_fin:
        assert bu_fin < #8F00
        save "BURSTTEST.BIN",#8000,bu_fin-#8000,AMSDOS
