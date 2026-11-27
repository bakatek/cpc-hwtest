; =====================================================================
;  MAPTEST - configurations RAM C1 / C3, ecriture sous ROM, execution
;  CPC 464 / 6128 + extension (PicoCPC...) - RASM - avec cpclib.asm
;
;  Cas non couverts par MEMTEST et trouves en mettant au point la PicoCPC
;  (demo Batman Forever, 11/2026) :
;
;   0 C3 ecr -> C0 lect : en C3, la page de base 3 est en #4000. On y
;     ecrit, puis on relit la meme memoire en C0 par #C000. Sur un 464,
;     C3 n'existe pas : c'est l'extension qui l'emule. Elle doit aussi
;     rendre visible en #C000 ce qui a ete ecrit par #4000 (le chargeur
;     de Batman Forever charge ainsi des donnees, relues ensuite en C0).
;   1 C3 ecr : fuite page 1 : les memes ecritures ne doivent pas toucher
;     la RAM de base page 1 (#4000 en C0).
;   2 C3 PUSH -> C0 : meme chose, ecritures en rafale (PUSH).
;   3 C0 ecr -> C3 lect : sens inverse.
;   4 C1 ROM haute active : ecr. page 7 : en C1, la page 7 de l'extension
;     est en #C000, SOUS la ROM haute. Les ecritures vont a la RAM meme si
;     la ROM est active (POKE du BASIC en C1). Relecture par #4000 en C7.
;   5 C1 ROM haute : fuite page 3 : ces ecritures ne doivent pas toucher
;     la RAM de base page 3 (ecran).
;   6 C1 exec page 7 en #C000 : code ecrit par #4000 (C7) puis execute en
;     #C000 en C1, ROM coupees (musique de Batman Forever).
;   7 C3 exec page 3 en #4000 : code ecrit en C0 par #C000, execute en C3
;     par #4000.
;   8 C3 ecr -> exec C0 : code ecrit en C3 par #4000, execute en C0 par
;     #C000 (decompresseur de Batman Forever).
;
;  L'ecran est en page 3 (#C000) : on n'utilise que les 48 octets non
;  affiches a la fin de chaque bloc de 2 Ko (#C7D0-#C7FF, #CFD0-#CFFF...,
;  #FFD0-#FFFF), soit 384 octets, vus en #47D0, #4FD0... en C3.
;  Chaque passe fait 16 tours avec une valeur differente : une ecriture
;  perdue laisse l'ancienne valeur et se voit au tour suivant.
;  Sans extension (lignes 4 a 6 impossibles), ces lignes restent a "--".
;
;  BASIC :  MEMORY &7FFF:LOAD"MAPTEST.BIN",&8000:CALL &8000
; =====================================================================

NR      equ 9                   ; lignes du tableau
SZ      equ 6                   ; erreurs (2), adresse (2), attendu, lu
ROUNDS  equ 16
REF     equ #3C                 ; motif de reference de la RAM de base
MT_RESULT     equ #9F00               ; resultat des routines executees

        org #8000

mt_start:
        di
        ld sp,#C000
        call lib_init
        call lib_cls
        ld de,#0000
        call lib_locate
        ld hl,mt_m0
        call lib_prt
        ld de,#0200
        call lib_locate
        ld hl,mt_hdr
        call lib_prt
        ld hl,mt_nm0            ; noms, lignes 3 a 11
        ld d,3
mt_n1:  push de
        push hl
        ld e,0
        call lib_locate
        pop hl
        call lib_prt
        inc hl
        pop de
        inc d
        ld a,d
        cp 3+NR
        jr nz,mt_n1
        ld hl,mt_tab            ; RAZ des compteurs
        ld b,NR*SZ
mt_z1:  ld (hl),0
        inc hl
        djnz mt_z1
        ld hl,0
        ld (mt_pass),hl
        ; extension presente ? (page 7 en #4000 differente de la base)
        ld bc,#7FC0
        out (c),c
        ld a,#5A
        ld (#4000),a
        ld bc,#7FC7
        out (c),c
        ld a,#A5
        ld (#4000),a
        ld bc,#7FC0
        out (c),c
        ld a,(#4000)
        sub #5A
        ld (mt_noext),a         ; 0 = extension presente
        ld a,#C0+0
        ld (mt_key),a

;----------------------------------------------------------------------
; BOUCLE PRINCIPALE
;----------------------------------------------------------------------
mt_loop:
        ld b,ROUNDS
mt_r1:  push bc
        ld a,(mt_seed)
        add a,#25
        ld (mt_seed),a
        ld a,(mt_noext)
        or a
        call z,mt_t45           ; d'abord : ROM haute (fuite page 3 encore mesurable)
        ld a,(mt_noext)
        or a
        call z,mt_t6
        call mt_t01
        call mt_t2
        call mt_t3
        call mt_t7
        call mt_t8
        pop bc
        djnz mt_r1
        ld hl,(mt_pass)
        inc hl
        ld (mt_pass),hl
        call mt_show
        jp mt_loop

;----------------------------------------------------------------------
; parcours des 8 blocs de 48 octets : A = poids fort du bloc 0
; (#C7 vue #C000, #47 vue #4000 en C3)
; mt_wr : ecrit (L xor cle) ; mt_ck : compare, erreurs dans IX
;----------------------------------------------------------------------
mt_wr:  ld h,a
        ld d,8
mt_w1:  ld l,#D0
        ld b,48
mt_w2:  ld a,(mt_key)
        xor l
        ld (hl),a
        inc l
        djnz mt_w2
        ld a,h
        add a,8
        ld h,a
        dec d
        jr nz,mt_w1
        ret

mt_ck:  ld h,a
        ld d,8
mt_c1:  ld l,#D0
        ld b,48
mt_c2:  ld a,(mt_cmode)         ; 0 : L xor cle ; 1 : cle seule (PUSH)
        or a
        ld a,(mt_key)
        jr nz,mt_c3
        xor l
mt_c3:  ld c,a
        ld a,(hl)
        cp c
        call nz,mt_err          ; C = attendu, A = lu, HL = adresse
        inc l
        djnz mt_c2
        ld a,h
        add a,8
        ld h,a
        dec d
        jr nz,mt_c1
        ret

; erreur : compteur + derniere adresse, attendu, lu (preserve HL, BC, DE)
mt_err: push hl
        ld (ix+5),a
        ld (ix+4),c
        ld (ix+2),l
        ld (ix+3),h
        ld l,(ix+0)
        ld h,(ix+1)
        inc hl
        ld a,h                  ; sature a #FFFF
        or l
        jr z,mt_e1
        ld (ix+0),l
        ld (ix+1),h
mt_e1:  pop hl
        ret

mt_c0:  ld bc,#7FC0
        out (c),c
        ret
mt_c3c: ld bc,#7FC3
        out (c),c
        ret

;----------------------------------------------------------------------
; 0 et 1 : C3 ecriture LD (HL),A -> C0 lecture ; fuite page 1
;----------------------------------------------------------------------
mt_t01: call mt_c0
        ld a,(mt_seed)
        push af
        ld a,REF                ; page 1 de base = reference
        ld (mt_key),a
        xor a
        ld (mt_cmode),a
        ld a,#47
        call mt_wr
        pop af
        ld (mt_key),a
        call mt_c3c
        ld a,#47                ; page 3 vue en #4000
        call mt_wr
        call mt_c0
        ld ix,mt_tab+0*SZ
        ld a,#C7                ; relue en #C000
        call mt_ck
        ld a,REF
        ld (mt_key),a
        ld ix,mt_tab+1*SZ
        ld a,#47                ; page 1 intacte ?
        jp mt_ck

;----------------------------------------------------------------------
; 2 : C3 PUSH -> C0 (valeur constante = cle)
;----------------------------------------------------------------------
mt_t2:  ld a,(mt_seed)
        cpl
        ld (mt_key),a
        ld d,a
        ld e,a
        ld (mt_sp),sp
        call mt_c3c
        ld h,#48                ; fin du bloc 0 en #4000 (#47D0-#47FF)
        ld a,8
mt_p1:  ld l,0
        ld sp,hl
        push de                 ; 24 PUSH = 48 octets
        push de
        push de
        push de
        push de
        push de
        push de
        push de
        push de
        push de
        push de
        push de
        push de
        push de
        push de
        push de
        push de
        push de
        push de
        push de
        push de
        push de
        push de
        push de
        ld c,a
        ld a,h
        add a,8
        ld h,a
        ld a,c
        dec a
        jr nz,mt_p1
        ld sp,(mt_sp)
        call mt_c0
        ld a,1
        ld (mt_cmode),a
        ld ix,mt_tab+2*SZ
        ld a,#C7
        call mt_ck
        xor a
        ld (mt_cmode),a
        ret

;----------------------------------------------------------------------
; 3 : C0 ecriture -> C3 lecture
;----------------------------------------------------------------------
mt_t3:  ld a,(mt_seed)
        xor #81
        ld (mt_key),a
        call mt_c0
        ld a,#C7
        call mt_wr
        call mt_c3c
        ld ix,mt_tab+3*SZ
        ld a,#47
        call mt_ck
        jp mt_c0

;----------------------------------------------------------------------
; 4 et 5 : C1, ROM haute ACTIVE : ecriture page 7 en #C000
;----------------------------------------------------------------------
mt_t45: call mt_c0
        ld a,REF                ; page 3 de base (ecran, octets caches) = reference
        ld (mt_key),a
        ld a,#C7
        call mt_wr
        ld a,(mt_seed)
        xor #5A
        ld (mt_key),a
        ld bc,#7F86             ; mode 2, ROM basse coupee, ROM HAUTE ACTIVE
        out (c),c
        ld bc,#7FC1
        out (c),c
        ld a,#C7                ; ecriture sous la ROM
        call mt_wr
        ld bc,#7F8E             ; ROM coupees
        out (c),c
        ld bc,#7FC7             ; page 7 vue en #4000
        out (c),c
        ld ix,mt_tab+4*SZ
        ld a,#47
        call mt_ck
        call mt_c0
        ld a,REF
        ld (mt_key),a
        ld ix,mt_tab+5*SZ
        ld a,#C7                ; RAM de base page 3 intacte ?
        jp mt_ck

;----------------------------------------------------------------------
; routine executee : LD HL,0 / LD B,n / INC HL / DJNZ / LD (MT_RESULT),HL / RET
; copiee en (DE), n = cle ; mt_run : verifie MT_RESULT = n
;----------------------------------------------------------------------
mt_put: ld hl,mt_rt
        ld bc,mt_rte-mt_rt
        ldir
        ret
mt_patch:                       ; HL = adresse de la routine : n = cle (jamais 0)
        ld a,(mt_seed)
        or 1
        ld (mt_key),a
        inc hl
        inc hl
        inc hl
        inc hl
        ld (hl),a
        ret
mt_res: ld hl,(MT_RESULT)             ; IX = ligne, DE = adresse de la routine
        ld a,(mt_key)
        ld c,a
        ld a,h
        or a
        ld a,l
        jr nz,mt_rs1
        cp c
        ret z
mt_rs1: ex de,hl
        jp mt_err
mt_rt:  ld hl,0
        ld b,1
mt_rt1: inc hl
        djnz mt_rt1
        ld (MT_RESULT),hl
        ret
mt_rte:

; 6 : C1, page 7 en #C000, ROM coupees (code ecrit par #4000 en C7)
mt_t6:  ld bc,#7FC7
        out (c),c
        ld de,#47D0
        call mt_put
        ld hl,#47D0
        call mt_patch
        call mt_c0
        ld hl,0
        ld (MT_RESULT),hl
        ld bc,#7FC1
        out (c),c
        call #C7D0
        call mt_c0
        ld ix,mt_tab+6*SZ
        ld de,#C7D0
        jp mt_res

; 7 : C3, page 3 en #4000 (code ecrit en C0 par #C000, bloc 1)
mt_t7:  call mt_c0
        ld de,#CFD0
        call mt_put
        ld hl,#CFD0
        call mt_patch
        ld hl,0
        ld (MT_RESULT),hl
        call mt_c3c
        call #4FD0
        call mt_c0
        ld ix,mt_tab+7*SZ
        ld de,#4FD0
        jp mt_res

; 8 : code ecrit en C3 par #4000 (bloc 2), execute en C0 par #C000
mt_t8:  call mt_c3c
        ld de,#57D0
        call mt_put
        ld hl,#57D0
        call mt_patch
        call mt_c0
        ld hl,0
        ld (MT_RESULT),hl
        call #D7D0
        ld ix,mt_tab+8*SZ
        ld de,#D7D0
        jp mt_res

;----------------------------------------------------------------------
; affichage du tableau, bord vert (tout a 0) ou rouge
;----------------------------------------------------------------------
mt_show:
        ld de,#0000+60
        call lib_locate
        ld hl,mt_mp
        call lib_prt
        ld hl,(mt_pass)
        call lib_hex16
        ld ix,mt_tab
        ld d,3
        ld c,0                  ; C <> 0 : au moins une erreur
mt_s1:  push de
        ld e,40
        call lib_locate
        ld a,(mt_noext)         ; lignes 4 a 6 sans extension
        or a
        jr z,mt_s3
        ld a,d
        cp 3+4
        jr c,mt_s3
        cp 3+7
        jr nc,mt_s3
        ld hl,mt_mx
        call lib_prt
        jr mt_s4
mt_s3:  ld l,(ix+0)
        ld h,(ix+1)
        ld a,h
        or l
        or c
        ld c,a
        push bc
        call lib_hex16
        ld a,' '
        call lib_putc
        ld a,' '
        call lib_putc
        ld l,(ix+2)
        ld h,(ix+3)
        call lib_hex16
        ld a,' '
        call lib_putc
        ld a,(ix+4)
        call lib_hex8
        ld a,' '
        call lib_putc
        ld a,(ix+5)
        call lib_hex8
        pop bc
mt_s4:  ld de,SZ
        add ix,de
        pop de
        inc d
        ld a,d
        cp 3+NR
        jr nz,mt_s1
        ld a,c
        or a
        ld a,#52                ; vert
        jr z,mt_s2
        ld a,#4C                ; rouge
mt_s2:  jp lib_border

;----------------------------------------------------------------------
mt_m0:  db "MAPTEST - C1/C3, ecriture sous ROM, execution",0
mt_mp:  db "PASSE ",0
mt_mx:  db "--   (pas d'extension)",0
mt_hdr: db "TEST                                    ERR   ADR  ATT LU",0
mt_nm0: db "0 C3 ecr #4000 -> C0 lect #C000",0
        db "1 C3 ecr : fuite RAM base page 1",0
        db "2 C3 PUSH #4000 -> C0 lect #C000",0
        db "3 C0 ecr #C000 -> C3 lect #4000",0
        db "4 C1 ROM haute active: ecr page 7",0
        db "5 C1 ROM haute: fuite base page 3",0
        db "6 C1 exec page 7 en #C000",0
        db "7 C3 exec page 3 en #4000",0
        db "8 C3 ecr code -> exec C0 #C000",0

mt_seed:  db 0
mt_key:   db 0
mt_cmode: db 0
mt_noext: db 0
mt_pass:  dw 0
mt_sp:    dw 0
mt_tab:   ds NR*SZ

        include "cpclib.asm"

mt_fin:
        save "MAPTEST.BIN",#8000,mt_fin-#8000,AMSDOS
