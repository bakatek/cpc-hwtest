; =====================================================================
;  Z80TEST - Z80 a 100 % : jeux d'instructions + stabilite - CPC 464
;  RASM
;
;  7 groupes calculent chacun une SIGNATURE 32 bits (double somme de
;  Fletcher) des resultats ET des drapeaux (bits non documentes 3 et 5
;  masques) :
;   1 ALU 8 bits   : ADD ADC SUB SBC AND XOR OR CP (A et operande 0-255,
;                    retenue 0 et 1) = 655 360 operations
;   2 UNAIRES      : DAA CPL NEG RLCA RRCA RLA RRA RLC RRC RL RR SLA SRA
;                    SRL INC DEC CCF SCF, A 0-255 x 8 combinaisons N/H/C
;   3 PREFIXE CB   : les 32 opcodes CB sur A (rotations, SLL, BIT, RES, SET)
;   4 16 bits      : ADD/ADC/SBC HL,BC sur valeurs pseudo-aleatoires
;   5 BLOCS        : LDIR LDDR CPIR CPDR + controle des registres
;   6 IX/IY/EX     : indexes, EX (SP), EXX, EX AF,AF', RLD, RRD
;   7 MULTIPLICATION 16x16->32 (decalages / retenues)
;
;  Passe 1 = reference. Passes suivantes : la moindre signature differente
;  = erreur (Z80 instable). Le CPU tourne a 100 % en permanence (DI).
;  Astuce : lance le meme BIN dans un emulateur precis (ACE-DL, CPCEC...)
;  et compare les signatures de la passe 1 => verifie aussi la JUSTESSE.
;
;  BASIC :  MEMORY &7FFF:LOAD"Z80TEST.BIN",&8000:CALL &8000
; =====================================================================

NGRP    equ 7
Z_BUF   equ #4000

        org #8000

;---------------------------------------------------------------------
; INITIALISATION : DI (le CPU tourne a 100 % sans interruption).
;---------------------------------------------------------------------
z_start:
        di
        ld sp,#9000
        call lib_init
        call lib_cls
        ld de,#0000
        call lib_locate
        ld hl,z_m0
        call lib_prt
        ld de,#0200
        call lib_locate
        ld hl,z_m1
        call lib_prt
        ld hl,0
        ld (z_pass),hl
        ld hl,z_err
        ld b,NGRP*2
z_z1:   ld (hl),0
        inc hl
        djnz z_z1

; ---------------------------------------------------------------------
;---------------------------------------------------------------------
; BOUCLE DES PASSES : execute les 7 groupes. Chacun remet a zero la
; signature (z_s1/z_s2) puis l'accumule. La passe 0 sert de reference (copiee
; dans z_ref) ; aux passes suivantes, toute signature differente = erreur.
;---------------------------------------------------------------------
z_loop:
        ld hl,z_gtab
        ld (z_gptr),hl
        xor a
        ld (z_gi),a
z_lp1:  ld a,(z_gi)             ; marque "en cours"
        add a,4
        ld d,a
        ld e,0
        call lib_locate
        ld a,'>'
        call lib_putc
        ld hl,0
        ld (z_s1),hl
        ld (z_s2),hl
        ld hl,(z_gptr)
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (z_gptr),hl
        ex de,hl
        call z_jphl
        ; range la signature
        call z_resptr           ; DE = index*4
        ld hl,z_res
        add hl,de
        ld de,(z_s1)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld de,(z_s2)
        ld (hl),e
        inc hl
        ld (hl),d
        ; compare a la reference (sauf passe 0)
        ld hl,(z_pass)
        ld a,h
        or l
        jr z,z_lp3
        call z_resptr
        ld hl,z_res
        add hl,de
        push hl
        ld hl,z_ref
        add hl,de
        pop de
        ld b,4
z_lp2:  ld a,(de)
        cp (hl)
        jr nz,z_lpe
        inc de
        inc hl
        djnz z_lp2
        jr z_lp3
z_lpe:  ld a,(z_gi)
        add a,a
        ld e,a
        ld d,0
        ld hl,z_err
        add hl,de
        inc (hl)
        jr nz,z_lp3
        inc hl
        inc (hl)
z_lp3:  call z_showg
        ld a,(z_gi)
        inc a
        ld (z_gi),a
        cp NGRP
        jp nz,z_lp1
        ; fin de passe
        ld hl,(z_pass)
        ld a,h
        or l
        jr nz,z_lp4
        ld hl,z_res
        ld de,z_ref
        ld bc,NGRP*4
        ldir
z_lp4:  ld hl,(z_pass)
        inc hl
        ld (z_pass),hl
        ld de,#0D00
        call lib_locate
        ld hl,z_m2
        call lib_prt
        ld hl,(z_pass)
        call lib_hex16
        ld hl,z_err             ; bord vert si 0 erreur, rouge sinon
        ld b,NGRP*2
        xor a
z_lp5:  or (hl)
        inc hl
        djnz z_lp5
        or a
        ld a,#52
        jr z,z_lp6
        ld a,#4C
z_lp6:  call lib_border
        jp z_loop

z_resptr:                       ; DE = (z_gi)*4
        ld a,(z_gi)
        add a,a
        add a,a
        ld e,a
        ld d,0
        ret

;---------------------------------------------------------------------
; Temoin d'activite : couleur du bord = compteur courant.
;---------------------------------------------------------------------
z_tick:                         ; temoin d'activite : couleur du bord = (z_a)
        push bc
        ld bc,#7F10
        out (c),c
        ld a,(z_a)
        and #1F
        or #40
        out (c),a
        pop bc
        ret

z_jphl: jp (hl)
z_jpiy: jp (iy)

; ligne d'un groupe : "  n NOM  SIGNATURE  ERREURS"
;---------------------------------------------------------------------
; Affiche la ligne du groupe : numero, nom, signature 32 bits, erreurs.
;---------------------------------------------------------------------
z_showg:
        ld a,(z_gi)
        add a,4
        ld d,a
        ld e,0
        call lib_locate
        ld a,' '
        call lib_putc
        ld a,(z_gi)
        add a,'1'
        call lib_putc
        ld a,' '
        call lib_putc
        ld a,(z_gi)
        add a,a
        ld e,a
        ld d,0
        ld hl,z_names
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        call lib_prt
        ld hl,(z_s2)
        call lib_hex16
        ld hl,(z_s1)
        call lib_hex16
        ld hl,z_m3
        call lib_prt
        ld a,(z_gi)
        add a,a
        ld e,a
        ld d,0
        ld hl,z_err
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        jp lib_hex16

; ---------------------------------------------------------------------
; melange : DE = valeur  (S1 += DE ; S2 += S1)  - preserve HL, BC, IX, IY
;---------------------------------------------------------------------
; SIGNATURE (double somme de Fletcher 16 bits) : S1 += DE ; S2 += S1.
; z_mixf masque d'abord les bits 3 et 5 de F (non documentes, differents selon
; emulateurs) pour que la signature soit comparable a un emulateur precis.
;---------------------------------------------------------------------
z_mixf: ld a,e                  ; idem mais E = drapeaux, bits 3/5 masques
        and #D7
        ld e,a
z_mix:  push hl
        ld hl,(z_s1)
        add hl,de
        ld (z_s1),hl
        ex de,hl
        ld hl,(z_s2)
        add hl,de
        ld (z_s2),hl
        pop hl
        ret

;---------------------------------------------------------------------
; LFSR 16 bits de Galois (polynome #B400) : valeurs pseudo-aleatoires
; reproductibles a l'identique d'une passe a l'autre.
;---------------------------------------------------------------------
z_lfsr: srl h                   ; HL = LFSR 16 bits (detruit A)
        rr l
        ret nc
        ld a,h
        xor #B4
        ld h,a
        ret

; ===================== GROUPE 1 : ALU 8 bits ==========================
;---------------------------------------------------------------------
; GROUPE 1 - ALU 8 bits : 10 operations x 256 valeurs de A x 256 operandes
; (ADC/SBC avec retenue 0 puis 1). Resultat ET drapeaux dans la signature.
;---------------------------------------------------------------------
z_g1:   ld iy,z_add
        call z_bin
        ld iy,z_adc0
        call z_bin
        ld iy,z_adc1
        call z_bin
        ld iy,z_sub
        call z_bin
        ld iy,z_sbc0
        call z_bin
        ld iy,z_sbc1
        call z_bin
        ld iy,z_and
        call z_bin
        ld iy,z_xor
        call z_bin
        ld iy,z_or
        call z_bin
        ld iy,z_cp
        jp z_bin

z_bin:  xor a                   ; A = 0..255, B = 0..255
        ld (z_a),a
z_bn1:  ld b,0
z_bn2:  call z_jpiy             ; -> DE = AF
        call z_mixf
        djnz z_bn2
        call z_tick
        ld a,(z_a)
        inc a
        ld (z_a),a
        jr nz,z_bn1
        ret

z_add:  ld a,(z_a)
        add a,b
        push af
        pop de
        ret
z_adc0: ld a,(z_a)
        or a
        adc a,b
        push af
        pop de
        ret
z_adc1: ld a,(z_a)
        scf
        adc a,b
        push af
        pop de
        ret
z_sub:  ld a,(z_a)
        sub b
        push af
        pop de
        ret
z_sbc0: ld a,(z_a)
        or a
        sbc a,b
        push af
        pop de
        ret
z_sbc1: ld a,(z_a)
        scf
        sbc a,b
        push af
        pop de
        ret
z_and:  ld a,(z_a)
        and b
        push af
        pop de
        ret
z_xor:  ld a,(z_a)
        xor b
        push af
        pop de
        ret
z_or:   ld a,(z_a)
        or b
        push af
        pop de
        ret
z_cp:   ld a,(z_a)
        cp b
        push af
        pop de
        ret

; ===================== GROUPE 2 : unaires =============================
;---------------------------------------------------------------------
; GROUPE 2 - instructions unaires : chaque operation est executee pour
; A = 0..255 et les 8 combinaisons des drapeaux C, N, H en entree (DAA en
; depend directement).
;---------------------------------------------------------------------
z_g2:   ld hl,z_utab
z_g21:  ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,d
        or e
        ret z
        push hl
        push de
        pop iy
        call z_un
        pop hl
        jr z_g21

z_un:   xor a                   ; A 0..255 x 8 combinaisons C/N/H
        ld (z_a),a
z_un1:  ld c,8
z_un2:  ld a,c
        dec a
        ld b,a
        and 3                   ; C (bit0) et N (bit1)
        ld e,a
        ld a,b
        and 4
        add a,a
        add a,a                 ; H (#10)
        or e
        ld e,a
        ld a,(z_a)
        ld d,a
        push de
        pop af
        call z_jpiy
        push af
        pop de
        call z_mixf
        dec c
        jr nz,z_un2
        call z_tick
        ld a,(z_a)
        inc a
        ld (z_a),a
        jr nz,z_un1
        ret

z_utab: dw z_daa,z_cpl,z_neg,z_rlca,z_rrca,z_rla,z_rra,z_rlc,z_rrc
        dw z_rl,z_rr,z_sla,z_sra,z_srl,z_inc,z_dec,z_ccf,z_scf,0

z_daa:  daa
        ret
z_cpl:  cpl
        ret
z_neg:  neg
        ret
z_rlca: rlca
        ret
z_rrca: rrca
        ret
z_rla:  rla
        ret
z_rra:  rra
        ret
z_rlc:  rlc a
        ret
z_rrc:  rrc a
        ret
z_rl:   rl a
        ret
z_rr:   rr a
        ret
z_sla:  sla a
        ret
z_sra:  sra a
        ret
z_srl:  srl a
        ret
z_inc:  inc a
        ret
z_dec:  dec a
        ret
z_ccf:  ccf
        ret
z_scf:  scf
        ret

; ===================== GROUPE 3 : prefixe CB (auto-modifiant) =========
;---------------------------------------------------------------------
; GROUPE 3 - prefixe CB : code AUTO-MODIFIANT. L'octet z_cbop parcourt
; #07, #0F ... #FF = les 32 instructions CB agissant sur A (RLC..SRL, SLL non
; documentee, BIT/RES/SET 0-7), pour A = 0..255 et retenue 0/1.
;---------------------------------------------------------------------
z_g3:   ld a,7                  ; opcodes CB xx avec registre A : 07,0F,...,FF
        ld (z_cbop),a
z_g31:  xor a
        ld (z_a),a
z_g32:  ld a,(z_a)
        or a                    ; retenue 0
        call z_cbx
        ld a,(z_a)
        scf                     ; retenue 1
        call z_cbx
        ld a,(z_a)
        inc a
        ld (z_a),a
        jr nz,z_g32
        ld a,(z_cbop)
        add a,8
        ld (z_cbop),a
        cp 7
        jr nz,z_g31
        ret

z_cbx:  db #CB
z_cbop: db #07
        push af
        pop de
        jp z_mixf

; ===================== GROUPE 4 : 16 bits =============================
;---------------------------------------------------------------------
; GROUPE 4 - arithmetique 16 bits : ADD HL,BC, ADC HL,BC et SBC HL,BC
; (retenue 0/1) sur 64 x 256 paires de valeurs pseudo-aleatoires.
;---------------------------------------------------------------------
z_g4:   ld hl,#1234
        ld (z_v1),hl
        ld hl,#ACE1
        ld (z_v2),hl
        ld a,64
        ld (z_a),a
z_g41:  ld hl,(z_v1)
        call z_lfsr
        ld (z_v1),hl
        xor a
        ld (z_b),a
z_g42:  ld hl,(z_v2)
        call z_lfsr
        ld (z_v2),hl
        ld b,h
        ld c,l                  ; BC = v2
        ld hl,(z_v1)
        add hl,bc
        push af
        ex de,hl
        call z_mix
        pop de
        call z_mixf
        ld hl,(z_v1)
        or a
        adc hl,bc
        push af
        ex de,hl
        call z_mix
        pop de
        call z_mixf
        ld hl,(z_v1)
        scf
        adc hl,bc
        push af
        ex de,hl
        call z_mix
        pop de
        call z_mixf
        ld hl,(z_v1)
        or a
        sbc hl,bc
        push af
        ex de,hl
        call z_mix
        pop de
        call z_mixf
        ld hl,(z_v1)
        scf
        sbc hl,bc
        push af
        ex de,hl
        call z_mix
        pop de
        call z_mixf
        ld a,(z_b)
        inc a
        ld (z_b),a
        jr nz,z_g42
        ld a,(z_a)
        dec a
        ld (z_a),a
        jr nz,z_g41
        ret

; ===================== GROUPE 5 : instructions de bloc ================
;---------------------------------------------------------------------
; GROUPE 5 - instructions de bloc : LDIR, LDDR, CPIR, CPDR sur 1 Ko
; aleatoire (16 fois) ; registres finaux, drapeaux et contenu copie signes.
;---------------------------------------------------------------------
z_g5:   ld hl,#BEEF
        ld (z_v1),hl
        ld a,16
        ld (z_a),a
z_g51:  ld de,Z_BUF             ; remplit 1 Ko
        ld bc,#400
z_g52:  ld hl,(z_v1)
        call z_lfsr
        ld (z_v1),hl
        ld a,l
        ld (de),a
        inc de
        dec bc
        ld a,b
        or c
        jr nz,z_g52
        ; LDIR
        ld hl,Z_BUF
        ld de,Z_BUF+#400
        ld bc,#400
        ldir
        call z_mreg
        ; LDDR
        ld hl,Z_BUF+#3FF
        ld de,Z_BUF+#BFF
        ld bc,#400
        lddr
        call z_mreg
        ; CPIR
        ld hl,Z_BUF
        ld bc,#400
        ld a,(z_v1)
        cpir
        call z_mreg
        ; CPDR
        ld hl,Z_BUF+#3FF
        ld bc,#400
        ld a,(z_v1+1)
        cpdr
        call z_mreg
        ; somme des copies (#4400-#4BFF)
        ld hl,Z_BUF+#400
        ld bc,#400
z_g53:  ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        call z_mix
        dec bc
        ld a,b
        or c
        jr nz,z_g53
        ld a,(z_a)
        dec a
        ld (z_a),a
        jr nz,z_g51
        ret

z_mreg:                         ; melange AF, BC, DE, HL (etat apres l'instruction)
        push af
        push hl
        push bc
        call z_mix              ; DE
        pop de
        call z_mix              ; BC
        pop de
        call z_mix              ; HL
        pop de
        jp z_mixf               ; AF

; ===================== GROUPE 6 : IX/IY, echanges, RLD/RRD ============
;---------------------------------------------------------------------
; GROUPE 6 - IX/IY (deplacements +/-), EX (SP),IX, EXX, EX AF,AF',
; RLD/RRD : 4096 iterations sur des valeurs pseudo-aleatoires.
;---------------------------------------------------------------------
z_g6:   ld hl,#5EED
        ld (z_v1),hl
        ld ix,Z_BUF+#100
        ld iy,Z_BUF+#200
        ld a,16
        ld (z_c),a
        xor a
        ld (z_b),a
z_g61:  ld hl,(z_v1)
        call z_lfsr
        ld (z_v1),hl
        ld a,l
        ld (ix+5),a
        ld a,h
        add a,(ix+5)
        ld (iy-3),a
        sub (ix+5)
        xor (iy-3)
        ld (ix+1),a
        inc (ix+1)
        ld (iy+2),h
        rlc (iy+2)
        rr (ix+1)
        ld (iy+7),l
        xor (iy+7)
        adc a,(ix+1)
        sbc a,(iy+2)
        bit 3,(ix+4)
        push af
        pop de
        call z_mixf
        ld e,(ix+1)
        ld d,(iy+2)
        call z_mix
        ; echanges
        ld hl,(z_v1)
        ld de,#A55A
        exx
        ld hl,#3C3C
        ld de,(z_v1)
        add hl,de
        exx
        ex de,hl                ; DE = v1, HL = #A55A
        push hl
        ex (sp),ix              ; IX = #A55A, pile = ancien IX
        add ix,de
        push ix
        pop de
        call z_mix
        ex (sp),ix              ; IX restaure, pile = resultat
        pop de
        call z_mix
        exx
        ex de,hl                ; DE = HL' (#3C3C + v1)
        call z_mix
        exx
        ld a,(z_v1)
        ex af,af'
        ld a,#77
        ex af,af'
        ld e,a
        ld d,0
        call z_mix
        ; RLD / RRD
        ld hl,Z_BUF+#300
        ld a,(z_v1+1)
        ld (hl),a
        ld a,(z_v1)
        rld
        push af
        pop de
        call z_mixf
        ld e,(hl)
        ld d,a
        call z_mix
        rrd
        push af
        pop de
        call z_mixf
        ld e,(hl)
        ld d,a
        call z_mix
        ; 256 x 16 iterations
        ld a,(z_b)
        inc a
        ld (z_b),a
        jp nz,z_g61
        ld a,(z_c)
        dec a
        ld (z_c),a
        jp nz,z_g61
        ld ix,Z_BUF+#100        ; IX/IY remis a leur valeur
        ld iy,Z_BUF+#200
        ret

; ===================== GROUPE 7 : multiplication 16x16 ================
;---------------------------------------------------------------------
; GROUPE 7 - multiplication 16x16 -> 32 bits par decalages/additions
; (ADD HL,HL / RL / ADC) sur 2048 paires.
;---------------------------------------------------------------------
z_g7:   ld hl,#C0DE
        ld (z_v1),hl
        ld hl,#F00D
        ld (z_v2),hl
        ld bc,2048
z_g71:  push bc
        ld hl,(z_v1)
        call z_lfsr
        ld (z_v1),hl
        ex de,hl
        ld hl,(z_v2)
        call z_lfsr
        ld (z_v2),hl
        ld b,h
        ld c,l
        call z_mul              ; DEHL = DE * BC
        push hl
        call z_mix              ; DE (poids fort)
        pop de
        call z_mix              ; HL (poids faible)
        pop bc
        dec bc
        ld a,b
        or c
        jr nz,z_g71
        ret

;---------------------------------------------------------------------
; DE x BC -> DE:HL (32 bits).
;---------------------------------------------------------------------
z_mul:  ld hl,0
        ld a,16
z_mu1:  add hl,hl
        rl e
        rl d
        jr nc,z_mu2
        add hl,bc
        jr nc,z_mu2
        inc de
z_mu2:  dec a
        jr nz,z_mu1
        ret

; ---------------------------------------------------------------------
;---------------------------------------------------------------------
; Table des groupes et de leurs noms.
;---------------------------------------------------------------------
z_gtab:  dw z_g1,z_g2,z_g3,z_g4,z_g5,z_g6,z_g7
z_names: dw z_n1,z_n2,z_n3,z_n4,z_n5,z_n6,z_n7
z_n1:   db "ALU 8 bits         ",0
z_n2:   db "Unaires/DAA        ",0
z_n3:   db "Prefixe CB         ",0
z_n4:   db "Arith. 16 bits     ",0
z_n5:   db "Blocs LDIR/CPIR... ",0
z_n6:   db "IX/IY/EX/RLD/RRD   ",0
z_n7:   db "Multiplication     ",0

z_m0:   db "Z80TEST 464 - jeu d'instructions + stabilite a 100 % (DI)",0
z_m1:   db "  # Groupe              Signature  Erreurs",0
z_m2:   db "Passes terminees : &",0
z_m3:   db "   &",0

z_s1:   dw 0
z_s2:   dw 0
z_v1:   dw 0
z_v2:   dw 0
z_a:    db 0
z_b:    db 0
z_c:    db 0
z_gi:   db 0
z_gptr: dw 0
z_pass: dw 0
z_res:  ds NGRP*4
z_ref:  ds NGRP*4
z_err:  ds NGRP*2

        include "cpclib.asm"
z_fin:
        assert z_fin < #8F00
        save "Z80TEST.BIN",#8000,z_fin-#8000,AMSDOS
