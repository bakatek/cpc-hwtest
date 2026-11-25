; =====================================================================
;  LEAKTEST - fuites de la RAM d'extension vers la RAM de base
;  CPC 464 + extension (PicoCPC...) - RASM - a assembler avec cpclib.asm
;
;  QUESTION : quand on ecrit dans une page d'extension (config &C4..),
;  la RAM INTERNE (#4000-#7FFF en C0) est-elle modifiee aussi ?
;  Et dans quelles conditions : rafales d'ecritures avec la page deja
;  selectionnee depuis longtemps, ou ecriture juste apres l'OUT de
;  selection de la page ?
;
;  Chaque scenario ecrit la valeur V dans TOUTE la page (#4000-#7FFF) :
;   0 Remplissage lent  : LD (HL),A en boucle, page fixe (reference)
;   1 PUSH deroules     : 8192 PUSH, page fixe (fuite vue dans MEMTEST, test 0B)
;   2 LDI deroules      : 8 Ko copies dans la page, page fixe
;   3 LD (HL),A deroules: 1 ecriture toutes les ~3 us, page fixe
;   4 OUT + ecriture    : pour CHAQUE octet : OUT page, LD (HL),A IMMEDIAT,
;                         OUT C0  -> l'ecriture suit directement la selection
;   5 OUT + 4 NOP       : idem avec 4 NOP (~4 us) entre l'OUT et l'ecriture
;   6 OUT + PUSH        : OUT page, PUSH IMMEDIAT, OUT C0 (x 8192)
;
;  Pour chaque scenario, on mesure :
;   FUITES  = octets de la RAM de BASE #4000-#7FFF modifies (puis repares)
;   PERDUS  = octets de la page d'extension qui n'ont PAS recu V
;  avec la derniere adresse touchee et la valeur lue.
;
;  LECTURE DES RESULTATS :
;   - fuites seulement en 1 (et 6) mais pas en 3/4/5 -> ecritures
;     consecutives sans lecture d'instruction (PUSH) mal gerees
;   - fuites/pertes en 4 mais pas en 5 -> SELECTION DE PAGE trop lente
;     (l'ecriture arrive avant que la nouvelle config soit prise en compte)
;   - fuites partout, meme en 0 -> decodage / RAMDIS / connecteur
;
;  BASIC :  MEMORY &7FFF:LOAD"LEAKTEST.BIN",&8000:CALL &8000
; =====================================================================

LT_CFG  equ #C4                 ; page d'extension testee (modifiable)
NS      equ 7                   ; nombre de lignes du tableau
SZ      equ 9                   ; taille d'une ligne de statistiques

        org #8000

;----------------------------------------------------------------------
; INITIALISATION : DI, ecran, motif de reference dans la RAM de base
;----------------------------------------------------------------------
lt_start:
        di
        ld sp,#C000             ; pile en #BFFF (zone #9000-#BFFF non testee)
        call lib_init
        call lib_cls
        ld de,#0000
        call lib_locate
        ld hl,lt_m0
        call lib_prt
        ld a,LT_CFG             ; page reellement testee
        call lib_hex8
        ld de,#0100
        call lib_locate
        ld hl,lt_m1
        call lib_prt
        ld de,#0300
        call lib_locate
        ld hl,lt_hdr
        call lib_prt
        ld hl,lt_nm0            ; noms des scenarios, lignes 4 a 10
        ld d,4
lt_n1:  push de
        push hl
        ld e,0
        call lib_locate
        pop hl
        call lib_prt
        inc hl
        pop de
        inc d
        ld a,d
        cp 4+NS
        jr nz,lt_n1
        ld de,#0D00
        call lib_locate
        ld hl,lt_m2
        call lib_prt
        ld de,#0E00
        call lib_locate
        ld hl,lt_m3
        call lib_prt
        ; RAM de base #4000-#7FFF (C0) = L xor H xor #3C
        ld bc,#7FC0
        out (c),c
        ld hl,#4000
lt_f1:  ld a,l
        xor h
        xor #3C
        ld (hl),a
        inc hl
        ld a,h
        cp #80
        jr nz,lt_f1
        ld hl,lt_tab            ; RAZ des statistiques
        ld b,NS*SZ
lt_z1:  ld (hl),0
        inc hl
        djnz lt_z1
        xor a
        ld (lt_vi),a

;----------------------------------------------------------------------
; BOUCLE : pour chaque scenario
;   a) pre-remplissage lent de la page avec ~V, controle de la base
;      (comptabilise sur la ligne 0 "Remplissage lent")
;   b) le scenario ecrit V dans toute la page
;   c) controle de la page (PERDUS) puis de la base (FUITES)
; La valeur V change a chaque boucle : #00, #FF, #55, #AA.
;----------------------------------------------------------------------
lt_loop:
        ld a,(lt_vi)
        and 3
        ld e,a
        ld d,0
        ld hl,lt_vals
        add hl,de
        ld a,(hl)
        ld (lt_val),a
        ld hl,lt_scen
        ld ix,lt_tab+SZ
        ld b,NS-1
lt_l1:  push bc
        push hl
        push ix
        ld ix,lt_tab            ; a) ligne 0
        call lt_prefill
        call lt_bchk
        ld a,5
        call lt_incix
        pop ix
        pop hl
        push hl
        ld e,(hl)               ; b) scenario
        inc hl
        ld d,(hl)
        ex de,hl
        call lt_jphl
        call lt_extchk          ; c)
        call lt_bchk
        ld a,5
        call lt_incix
        ld de,SZ
        add ix,de
        pop hl
        inc hl
        inc hl
        pop bc
        dec b
        jp nz,lt_l1
        call lt_show
        ld hl,lt_vi
        inc (hl)
        jp lt_loop

lt_jphl: jp (hl)

;----------------------------------------------------------------------
; SCENARIOS : ecrivent V (lt_val) dans toute la page #4000-#7FFF
; (ne doivent pas toucher IX)
;----------------------------------------------------------------------
lt_push:                        ; 1) 8192 PUSH, page selectionnee avant
        call lt_sel
        ld a,(lt_val)
        ld h,a
        ld l,a
        ld (lt_ssp),sp
        ld sp,#8000
        ld a,128
lt_pu1:
        repeat 64
        push hl
        rend
        dec a
        jp nz,lt_pu1
        ld sp,(lt_ssp)
        ret

lt_ldi:                         ; 2) source #4000-#5FFF = V (lent), puis
        call lt_sel             ;    8192 LDI vers #6000-#7FFF
        ld a,(lt_val)
        ld hl,#4000
lt_ld0: ld (hl),a
        inc hl
        bit 5,h                 ; arret en #6000
        jr z,lt_ld0
        ld hl,#4000
        ld de,#6000
        ld a,128
lt_ld1:
        repeat 64
        ldi
        rend
        dec a
        jp nz,lt_ld1
        ret

lt_ldhl:                        ; 3) LD (HL),A / INC L deroules
        call lt_sel
        ld a,(lt_val)
        ld hl,#4000
lt_lh1:
        repeat 256
        ld (hl),a
        inc l
        rend
        inc h
        bit 7,h
        jp z,lt_lh1
        ret

lt_out0:                        ; 4) OUT page / ecriture immediate / OUT C0
        ld bc,#7FC0
        out (c),c
        ld d,LT_CFG
        ld e,#C0
        ld a,(lt_val)
        ld hl,#4000
lt_o01:
        repeat 16
        out (c),d
        ld (hl),a
        out (c),e
        inc hl
        rend
        bit 7,h
        jp z,lt_o01
        ret

lt_out4:                        ; 5) idem avec 4 NOP apres l'OUT
        ld bc,#7FC0
        out (c),c
        ld d,LT_CFG
        ld e,#C0
        ld a,(lt_val)
        ld hl,#4000
lt_o41:
        repeat 16
        out (c),d
        nop
        nop
        nop
        nop
        ld (hl),a
        out (c),e
        inc hl
        rend
        bit 7,h
        jp z,lt_o41
        ret

lt_outp:                        ; 6) OUT page / PUSH immediat / OUT C0
        ld bc,#7FC0
        out (c),c
        ld d,LT_CFG
        ld e,#C0
        ld a,(lt_val)
        ld h,a
        ld l,a
        ld (lt_ssp),sp
        ld sp,#8000
        xor a                   ; 256 x 32 = 8192 PUSH
lt_op1:
        repeat 32
        out (c),d
        push hl
        out (c),e
        rend
        dec a
        jp nz,lt_op1
        ld sp,(lt_ssp)
        ret

;----------------------------------------------------------------------
; OUTILS
;----------------------------------------------------------------------
lt_sel:                         ; selectionne la page (preserve A)
        push af
        ld bc,#7F00
        ld a,LT_CFG
        out (c),a
        pop af
        ret

lt_prefill:                     ; page = ~V, ecriture lente, page fixe
        call lt_sel
        ld a,(lt_val)
        cpl
        ld hl,#4000
lt_pf1: ld (hl),a
        inc hl
        bit 7,h
        jr z,lt_pf1
        ret

lt_extchk:                      ; PERDUS : octets de la page <> V
        call lt_sel
        ld a,(lt_val)
        ld e,a
        ld hl,#4000
lt_ec1: ld a,(hl)
        cp e
        jr z,lt_ec2
        ld a,7
        call lt_incix
lt_ec2: inc hl
        ld a,h
        cp #80
        jr nz,lt_ec1
        ret

lt_bchk:                        ; FUITES : base #4000-#7FFF (C0) modifiee ?
        ld bc,#7FC0             ; chaque octet fautif est compte, note,
        out (c),c               ; puis REPARE
        ld hl,#4000
lt_bc1: ld a,l
        xor h
        xor #3C
        cp (hl)
        jr nz,lt_bcf
lt_bc2: inc hl
        ld a,h
        cp #80
        jr nz,lt_bc1
        ret
lt_bcf: ld e,a                  ; attendu
        ld a,(hl)
        ld (ix+4),a             ; valeur lue
        ld (ix+2),l             ; adresse
        ld (ix+3),h
        ld (hl),e               ; reparation
        xor a
        call lt_incix
        jr lt_bc2

lt_incix:                       ; incremente le mot 16 bits en (IX+A)
        push hl                 ; preserve HL, DE, BC
        push de
        push ix
        pop hl
        ld e,a
        ld d,0
        add hl,de
        inc (hl)
        jr nz,lt_ii1
        inc hl
        inc (hl)
lt_ii1: pop de
        pop hl
        ret

;----------------------------------------------------------------------
; AFFICHAGE : une ligne par scenario
; ligne de stats (SZ = 9 octets) :
;  +0 fuites (16b) +2 derniere adresse (16b) +4 derniere valeur lue
;  +5 iterations (16b) +7 octets perdus dans la page (16b)
;----------------------------------------------------------------------
lt_show:
        ld ix,lt_tab
        ld d,4
        ld b,NS
lt_sh1: push bc
        push de
        ld e,34
        call lib_locate
        ld l,(ix+5)
        ld h,(ix+6)
        call lib_hex16
        call lt_sp2
        ld l,(ix+0)
        ld h,(ix+1)
        call lib_hex16
        call lt_sp2
        ld l,(ix+2)
        ld h,(ix+3)
        call lib_hex16
        ld a,' '
        call lib_putc
        ld a,(ix+4)
        call lib_hex8
        call lt_sp2
        ld l,(ix+7)
        ld h,(ix+8)
        call lib_hex16
        ld de,SZ
        add ix,de
        pop de
        inc d
        pop bc
        djnz lt_sh1
        ld de,#0C00
        call lib_locate
        ld hl,lt_m4
        call lib_prt
        ld a,(lt_val)
        call lib_hex8
        ld hl,lt_m5
        call lib_prt
        ld a,(lt_vi)
        call lib_hex8
        ret

lt_sp2: ld a,' '
        call lib_putc
        jp lib_putc

;----------------------------------------------------------------------
; DONNEES
;----------------------------------------------------------------------
lt_scen: dw lt_push,lt_ldi,lt_ldhl,lt_out0,lt_out4,lt_outp
lt_vals: db #00,#FF,#55,#AA

lt_m0:  db "LEAKTEST - fuites extension -> RAM de base, page &",0
lt_m1:  db "Ecrit V dans la page ; compte les octets modifies en base et non recus en page",0
lt_m2:  db "Fuite = octet de la RAM de base #4000-#7FFF modifie (repare ensuite)",0
lt_m3:  db "Perdu = octet de la page qui n'a pas recu V   (valeurs en hexa)",0
lt_m4:  db "Valeur V : &",0
lt_m5:  db "   boucles : &",0
lt_hdr: db "Scenario                          Iter  Fuite Adr. Lu  Perdu",0
lt_nm0:  db "Remplissage lent (reference)      ",0
lt_nm1:  db "PUSH deroules, page fixe          ",0
lt_nm2:  db "LDI deroules, page fixe           ",0
lt_nm3:  db "LD (HL),A deroules, page fixe     ",0
lt_nm4:  db "OUT page + ecriture IMMEDIATE     ",0
lt_nm5:  db "OUT page + 4 NOP + ecriture       ",0
lt_nm6:  db "OUT page + PUSH IMMEDIAT          ",0

lt_val:  db 0
lt_vi:   db 0
lt_ssp:  dw 0
lt_tab:  ds NS*SZ

        include "cpclib.asm"
lt_fin:
        assert lt_fin < #9000
        save "LEAKTEST.BIN",#8000,lt_fin-#8000,AMSDOS
