; =====================================================================
;  CARTTEST - test de la cartouche (CPR) : CPC+ / GX4000, et tout CPC
;  dont la cartouche est emulee (PicoCPC...) - RASM
;
;  Ce source n'est pas assemble seul : il est inclus par cart128.asm,
;  cart256.asm ou cart512.asm, qui fixent NP (nombre de pages de 16 Ko)
;  et le nom du fichier .CPR produit.
;
;  La cartouche EST le test : elle demarre seule (pas de firmware) et son
;  code tourne en permanence DEPUIS la cartouche (page 0 en ROM basse),
;  interruptions actives, comme un jeu. Le contenu de chaque page est connu,
;  donc chaque octet lu est verifie :
;   1 SIGNATURES : chaque page &DF #80+p porte son numero -> carte des pages
;     (presente / miroir / absente), stable d'une passe a l'autre
;   2 LECTURE    : LD A,(HL) sur toutes les donnees de chaque page ; page 0 :
;     vue ROM basse (#0000) = vue ROM haute (#C000, &DF #80)
;   3 RAFALES    : LDI deroules (4 Ko) et somme par POP (15 Ko), interruptions
;     coupees le temps des POP
;   4 EXECUTION  : une routine a prefixes CB/DD/ED/FD est EXECUTEE depuis
;     4 endroits de chaque page (cycles M1) ; aussi juste apres l'OUT &DF
;   5 COMMUTATION RAPIDE : OUT &DF puis lecture IMMEDIATE, page differente
;     a chaque octet
;   6 RMR2 (CPC+ seulement) : pages 0-7 en ROM basse a #0000, #4000, #8000,
;     signature, donnees et execution (code lance depuis la RAM)
;   7 MAPPAGE &DF (CPC+ seulement) : &DF 0 -> page 1, &DF 7 -> page 3
;   8 INTERRUPTIONS : 6 par trame, routine d'interruption dans la cartouche
;  Les erreurs sont comptees ; le test continue (on attend un PLANTAGE).
;
;  Organisation des pages p >= 1 (vues en #C000 par &DF #80+p) :
;   #C000-#C00F  #FF
;   #C010-#C01F  signature "CARTTEST", p, 255-p, NP, VERSION, #5A, #A5, 0, p
;   #C020-#C0FF  octet = adresse basse xor p xor #A5         (test 5)
;   #C100-#FBFF  15 Ko pseudo-aleatoires (LFSR, graine #5A3C xor p*#101)
;   #FC00-#FFFF  4 copies de la routine d'execution (test 4), une par 256 o.
;  Page 0 : code du test (#0000-), meme signature en #0010, fonte en #3900.
; =====================================================================

VERSION equ 1
        assert NP==8 || NP==16 || NP==32

; ---- RAM ----
BUF     equ #4000               ; tampon des LDI (4 Ko)
KRAM2   equ #5000               ; noyau RMR2, copie utilisee quand la ROM est en #8000
KRAM1   equ #9000               ; noyau RMR2, copie utilisee pour #0000 / #4000
RXRAM   equ #9800               ; routine d'execution de reference (en RAM)
VARS    equ #A000               ; variables du programme
; Zone d'ecran NON AFFICHEE (#C7D0-#C7FF) : toujours en RAM quelle que soit la
; place de la ROM basse (noyau RMR2). La ROM haute doit etre coupee pour la lire.
K_P     equ #C7D0               ; page testee par le noyau
K_L     equ #C7D1               ; emplacement 0/1/2 = #0000/#4000/#8000
K_BASE  equ #C7D2               ; octet haut de l'emplacement
K_SP    equ #C7D4
K_SEED  equ #C7D6
K_REF   equ #C7D8
K_EADR  equ #C7DA               ; derniere erreur du noyau : adresse,
K_EXP   equ #C7DC               ; attendu,
K_RD    equ #C7DD               ; lu
K_STUB  equ #C7F0               ; "JP (HL)" pour les appels depuis le noyau
SCR     equ #C000
FONT    equ #3800

; ---- variables (VARS) ----
v_pass  equ VARS+#00            ; passes terminees (16 bits)
v_frm   equ VARS+#02            ; trames (16 bits)
v_ipf   equ VARS+#04            ; interruptions dans la trame en cours
v_last  equ VARS+#05            ; interruptions de la derniere trame
v_sync  equ VARS+#06            ; 0 = ignorer la prochaine fin de trame
v_plus  equ VARS+#07            ; 1 = ASIC detecte (CPC+)
v_first equ VARS+#08            ; 1 = premiere passe
v_pg    equ VARS+#09            ; page en cours
v_test  equ VARS+#0A            ; test en cours
v_k     equ VARS+#0B            ; compteur
v_curs  equ VARS+#0C            ; curseur ecran (16 bits)
v_ssp   equ VARS+#0E
v_xseed equ VARS+#10
v_xref  equ VARS+#12
v_xadr  equ VARS+#14
v_xs    equ VARS+#16
v_icnt  equ VARS+#18            ; interruptions (16 bits)
v_e_t   equ VARS+#1A            ; derniere erreur : test,
v_e_p   equ VARS+#1B            ; page,
v_e_a   equ VARS+#1C            ; adresse (16 bits),
v_e_x   equ VARS+#1E            ; attendu,
v_e_r   equ VARS+#1F            ; lu
v_err   equ VARS+#20            ; 8 compteurs d'erreurs (16 bits)
v_map   equ VARS+#30            ; etat des 32 pages
v_psum  equ VARS+#50            ; somme POP de reference de chaque page (32 x 16 bits)
V_LEN   equ #90

; =====================================================================
; Routine d'execution (test 4 et 6) : RELOGEABLE (JR/DJNZ seulement),
; prefixes CB/DD/ED/FD, pile. Entree DE = graine, sortie HL. Le 1er octet
; apres "LD A," est le numero de la page (pour ne pas confondre les pages).
; =====================================================================
macro RXCODE,pg
        ld a,{pg}
        ld b,24
@l1:    ld h,d
        ld l,e
        add hl,hl
        adc hl,de
        ex de,hl
        rlc e
        rr d
        xor e
        add a,d
        ld c,a
        or a
        sbc hl,bc
        push hl
        pop ix
        add ix,de
        push ix
        pop iy
        add iy,bc
        push iy
        ex (sp),hl
        ex (sp),ix
        pop iy
        neg
        srl h
        rl l
        set 3,e
        res 6,d
        bit 5,h
        jr z,@l2
        inc a
@l2:    add hl,de
        ex de,hl
        push ix
        pop hl
        add a,l
        djnz @l1
        push iy
        pop hl
        add hl,de
        xor h
        ld h,a
        ret
mend

macro SIGN,pg
        db "CARTTEST",{pg},255-{pg},NP,VERSION,#5A,#A5,0,{pg}
mend

; =====================================================================
; PAGE 0 : le programme (ROM basse, #0000)
; =====================================================================
        bank 0
        org #0000
        di
        jp ct_init
        ds #10-$,#FF
        SIGN 0
        ds #38-$,#FF
        jp ct_isr                ; IM 1 : la routine d'interruption est dans la cartouche
        ds #40-$,#FF

;---------------------------------------------------------------------
; INITIALISATION (pas de firmware : on programme tout)
;---------------------------------------------------------------------
ct_init:
        di
        im 1
        ld sp,#C000
        ld bc,#F782              ; PPI : A sortie, B entree, C sortie
        out (c),c
        ld bc,#F600
        out (c),c
        ld bc,#7FC0              ; RAM : 64 Ko de base
        out (c),c
        ld bc,#7F8A              ; mode 2, ROM basse ON, ROM haute OFF
        out (c),c
        ld bc,#DF80              ; ROM haute = page 0 de la cartouche
        out (c),c
        ld hl,ct_crtc            ; CRTC : valeurs standard, ecran en #C000
        ld bc,#BC00
ci1:    out (c),c
        ld a,(hl)
        inc b
        out (c),a
        dec b
        inc hl
        inc c
        ld a,c
        cp 16
        jr nz,ci1
        call ct_silence
        ld bc,#7F00              ; encre 0 noir, encre 1 blanc, bord noir
        out (c),c
        ld a,#54
        out (c),a
        ld a,1
        out (c),a
        ld a,#4B
        out (c),a
        ld a,#54
        call ct_border
        call ct_cls              ; (ROM haute coupee : LDIR relit la RAM)
        ld hl,VARS               ; variables a zero
        ld de,VARS+1
        ld bc,V_LEN-1
        ld (hl),0
        ldir
        ld hl,ct_kern            ; noyau RMR2 en RAM (2 copies)
        ld de,KRAM1
        ld bc,ct_kend-ct_kern
        ldir
        ld hl,ct_kern
        ld de,KRAM2
        ld bc,ct_kend-ct_kern
        ldir
        ld hl,ct_rx              ; routine de reference en RAM
        ld de,RXRAM
        ld bc,ct_rxe-ct_rx
        ldir
        ld a,#E9                 ; JP (HL)
        ld (K_STUB),a
        ld a,1
        ld (v_first),a
        call ct_psums
        ; ASIC : deverrouillage puis detection (sans effet sur un CPC classique)
        ld hl,ct_useq
        ld b,#BC
        ld d,17
ci2:    ld a,(hl)
        out (c),a
        inc hl
        dec d
        jr nz,ci2
        call KRAM1               ; A = 1 si la ROM basse se deplace (RMR2) = CPC+
        ld (v_plus),a
        call ct_screen
        call ct_show             ; compteurs a zero des le depart
        call ct_ei

;---------------------------------------------------------------------
; BOUCLE DES PASSES
;---------------------------------------------------------------------
ct_loop:
        call t_sig
        call t_ld
        call t_burst
        call t_exec
        call t_switch
        ld a,(v_plus)
        or a
        jr z,cl1
        call t_rmr2
        call t_dfmap
cl1:    xor a
        ld (v_first),a
        ld hl,(v_pass)
        inc hl
        ld (v_pass),hl
        call ct_show
        jp ct_loop

;---------------------------------------------------------------------
; INTERRUPTION (300 Hz) - dans la cartouche
; Compte les INT entre deux VSYNC (PPI port B bit 0) : 6 attendues par trame.
; Fait aussi clignoter le coin haut droit de l'ecran (temoin de vie).
;---------------------------------------------------------------------
ct_isr:
        push af
        push bc
        push hl
        ld hl,(v_icnt)
        inc hl
        ld (v_icnt),hl
        ld hl,v_ipf
        inc (hl)
        ld b,#F5
        in a,(c)
        rra
        jr nc,cs3
        ld a,(v_ipf)             ; INT pendant la VSYNC : fin de trame
        ld (v_last),a
        cp 6
        jr z,cs1
        ld a,(v_sync)            ; trame partielle (apres un DI) : ignoree
        or a
        jr z,cs1
        ld hl,(v_err+14)
        inc hl
        ld (v_err+14),hl
cs1:    ld a,1
        ld (v_sync),a
        xor a
        ld (v_ipf),a
        ld hl,(v_frm)
        inc hl
        ld (v_frm),hl
        ld a,l                   ; temoin de vie
        ld (SCR+79),a
cs3:    pop hl
        pop bc
        pop af
        ei
        ret

ct_ei:  xor a                    ; reactive les INT ; la 1re trame est ignoree
        ld (v_sync),a
        ei
        ret

;---------------------------------------------------------------------
; TEST 1 - SIGNATURES : etat de chaque page &DF #80+p
;  1 presente (signature de p)  2 miroir (signature de p mod NP)
;  3 absente (pas de signature) 4 signature d'une autre page
;---------------------------------------------------------------------
t_sig:  ld a,1
        call ct_cur
        xor a
        ld (v_pg),a
ts1:    call ct_curpg
        ld a,(v_pg)
        call ct_selp
        ld hl,#C010
        ld de,#0010
        ld b,8
ts2:    ld a,(de)
        cp (hl)
        jr nz,ts_bad
        inc hl
        inc de
        djnz ts2
        ld a,(#C018)
        ld c,a
        ld a,(#C019)
        cpl
        cp c
        jr nz,ts_bad
        ld a,(#C01A)
        cp NP
        jr nz,ts_bad
        ld a,(v_pg)
        cp c
        ld a,1
        jr z,ts_set
        ld a,(v_pg)
        and NP-1
        cp c
        ld a,2
        jr z,ts_set
        ld a,4
        jr ts_set
ts_bad: ld a,3
ts_set: ld c,a                   ; C = etat
        call ct_upoff
        ld a,(v_pg)
        ld e,a
        ld d,0
        ld hl,v_map
        add hl,de
        ld a,(v_first)
        or a
        jr nz,ts_new
        ld a,(hl)                ; l'etat ne doit pas changer
        and #7F
        cp c
        jr z,ts_chk
        ld d,a                   ; attendu = ancien etat
        ld e,c                   ; lu = nouvel etat
        ld hl,#C010
        ld a,1
        call ct_err
        ld a,(v_pg)
        ld e,a
        ld d,0
        ld hl,v_map
        add hl,de
ts_new: ld (hl),c
ts_chk: ld a,(v_pg)              ; une page < NP doit etre presente
        cp NP
        jr nc,ts_nx
        ld a,c
        cp 1
        jr z,ts_nx
        ld a,(hl)
        or #80                   ; marque "erreur" pour la carte
        ld (hl),a
        ld d,1
        ld e,c
        ld hl,#C018
        ld a,1
        call ct_err
ts_nx:  ld a,(v_pg)
        inc a
        ld (v_pg),a
        cp 32
        jp nz,ts1
        jp ct_upoff

;---------------------------------------------------------------------
; TEST 2 - LECTURE LD A,(HL) des donnees de chaque page ; page 0 : la vue
; ROM basse (#0000) doit etre identique a la vue ROM haute (#C000).
;---------------------------------------------------------------------
t_ld:   ld a,2
        call ct_cur
        xor a
        ld (v_pg),a
        call ct_curpg
        xor a
        call ct_selp
        ld hl,#0000
tl0:    ld a,h
        or #C0
        ld d,a
        ld e,l
        ld a,(de)                ; vue ROM haute
        cp (hl)                  ; vue ROM basse
        jr z,tl0b
        push de
        ld d,(hl)                ; attendu = ROM basse
        ld e,a                   ; lu = ROM haute
        ex (sp),hl               ; HL = adresse en ROM haute
        ld a,2
        call ct_err
        pop hl
tl0b:   inc hl
        ld a,h
        cp #40
        jr nz,tl0
        ld a,1
tl1:    ld (v_pg),a
        cp NP
        jp nc,ct_upoff
        call ct_curpg
        ld a,(v_pg)
        call ct_selp
        call ct_seed
        ld hl,#C100
        ld bc,#3B00
tl2:    srl d
        rr e
        jr nc,tl3
        ld a,d
        xor #B4
        ld d,a
tl3:    ld a,(hl)
        cp e
        call nz,ct_err2
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,tl2
        ld a,(v_pg)
        inc a
        jr tl1

ct_err2:                         ; erreur de donnee : HL adr, E attendu, A lu
        push de                  ; (preserve tous les registres)
        push af
        ld d,e
        ld e,a
        ld a,(v_test)
        call ct_err
        pop af
        pop de
        ret

;---------------------------------------------------------------------
; TEST 3 - RAFALES : 4 096 LDI deroules (#C100 -> tampon en RAM), tampon
; verifie ; puis somme des 15 Ko de donnees par 7 552 POP (DI).
;---------------------------------------------------------------------
t_burst:
        ld a,3
        call ct_cur
        ld a,1
tb0:    ld (v_pg),a
        cp NP
        jp nc,ct_upoff
        call ct_curpg
        ld a,(v_pg)
        call ct_selp
        ld hl,#C100
        ld de,BUF
        ld a,64                  ; 64 x 64 LDI = 4 Ko
tb1:
        repeat 64
        ldi
        rend
        dec a
        jp nz,tb1
        call ct_seed
        ld hl,BUF
        ld bc,#1000
tb2:    srl d
        rr e
        jr nc,tb3
        ld a,d
        xor #B4
        ld d,a
tb3:    ld a,(hl)
        cp e
        call nz,ct_err3
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,tb2
        ; somme par POP (interruptions coupees : la pile est dans la ROM)
        di
        ld (v_ssp),sp
        ld sp,#C100
        ld hl,0
        ld a,236                 ; 236 x 32 POP = 15 104 octets
tb4:
        repeat 32
        pop de
        add hl,de
        rend
        dec a
        jp nz,tb4
        ld sp,(v_ssp)
        call ct_ei
        ex de,hl                 ; DE = somme lue
        ld a,(v_pg)
        add a,a
        ld l,a
        ld h,0
        ld bc,v_psum
        add hl,bc
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a                   ; HL = somme attendue
        or a
        sbc hl,de
        jr z,tb5
        add hl,de
        ld a,l                   ; on signale l'octet de poids faible
        ld l,e
        ld e,l
        ld d,a
        ld hl,#C100
        ld a,3
        call ct_err
tb5:    ld a,(v_pg)
        inc a
        jp tb0

ct_err3:                         ; erreur dans le tampon : adresse ROM = HL + #8100
        push hl
        push bc
        ld bc,#C100-BUF
        add hl,bc
        call ct_err2
        pop bc
        pop hl
        ret

;---------------------------------------------------------------------
; TEST 4 - EXECUTION depuis chaque page (#FC00, #FD00, #FE00, #FF00),
; 32 graines. a) page deja selectionnee, CALL ; b) ROM haute sur la page 0,
; puis OUT &DF vers la page et saut IMMEDIAT dans la page.
; Resultat compare a la meme routine executee en RAM.
;---------------------------------------------------------------------
t_exec: ld a,4
        call ct_cur
        ld a,1
te0:    ld (v_pg),a
        cp NP
        jp nc,ct_upoff
        call ct_curpg
        ld a,(v_pg)
        ld (RXRAM+1),a           ; numero de page dans la copie de reference
        xor a
        ld (v_xs),a
te1:    ld a,(v_xs)              ; graine
        ld d,a
        xor #C3
        ld e,a
        ld a,d
        xor #A5
        ld d,a
        ld (v_xseed),de
        call RXRAM
        ld (v_xref),hl
        ld hl,#FC00
te2:    ld (v_xadr),hl
        ld a,(v_pg)              ; a) page selectionnee, CALL
        call ct_selp
        ld de,(v_xseed)
        ld hl,(v_xadr)
        call ct_jphl
        call ct_xchk
        xor a                    ; b) page 0, puis OUT + saut immediat
        call ct_selp
        ld de,(v_xseed)
        ld hl,(v_xadr)
        ld a,(v_pg)
        or #80
        call ct_xjump
        call ct_xchk
        ld hl,(v_xadr)
        inc h
        jr nz,te2
        ld a,(v_xs)
        inc a
        ld (v_xs),a
        cp 32
        jr nz,te1
        ld a,(v_pg)
        inc a
        jr te0

ct_jphl: jp (hl)

ct_xjump:                        ; A = valeur &DF : OUT puis saut immediat
        ld b,#DF
        out (c),a
        jp (hl)

ct_xchk:                         ; HL = resultat, compare a v_xref
        ld de,(v_xref)
        ld a,l
        cp e
        jr nz,cx1
        ld a,h
        ld e,d
        cp e
        ret z
cx1:    ld d,e                   ; attendu
        ld e,a                   ; lu
        ld hl,(v_xadr)
        ld a,4
        jp ct_err

;---------------------------------------------------------------------
; TEST 5 - COMMUTATION RAPIDE : pour chaque octet #C020-#C0FF, on passe par
; toutes les pages : OUT &DF puis lecture IMMEDIATE (attendu L xor p xor #A5).
;---------------------------------------------------------------------
t_switch:
        ld a,5
        call ct_cur
        ld a,NP
        cp 2
        ret c
        call ct_upon
        ld hl,#C020
tw1:    ld a,1
        ld (v_pg),a
tw2:    or #80
        ld b,#DF
        out (c),a
        ld e,(hl)                ; lecture juste apres l'OUT
        ld a,l
        xor #A5
        ld d,a
        ld a,(v_pg)
        xor d
        cp e
        jr z,tw3
        ld d,a                   ; attendu
        ld a,5
        call ct_err
tw3:    ld a,(v_pg)
        inc a
        ld (v_pg),a
        cp NP
        jr nz,tw2
        inc l
        jr nz,tw1
        jp ct_upoff

;---------------------------------------------------------------------
; TEST 6 - RMR2 (CPC+) : pages 0-7 en ROM basse a #0000, #4000, #8000.
; Le noyau tourne en RAM (#9000, ou #5000 quand la ROM est en #8000).
;---------------------------------------------------------------------
t_rmr2: ld a,6
        call ct_cur
        call ct_upoff            ; les variables du noyau sont en #C7xx
        xor a
        ld (v_pg),a
tr1:    call ct_curpg
        xor a
        ld (v_k),a
tr2:    ld a,(v_pg)
        ld (K_P),a
        ld (RXRAM+1),a
        ld a,(v_k)
        ld (K_L),a
        ld de,#1D0F              ; graine fixe pour l'execution
        ld (K_SEED),de
        call RXRAM
        ld (K_REF),hl
        di
        ld a,(v_k)
        cp 2
        jr z,tr3
        call KRAM1+2
        jr tr4
tr3:    call KRAM2+2
tr4:    push af
        call ct_ei
        pop af
        or a
        jr z,tr5
        ld hl,(K_EADR)
        ld a,(K_EXP)
        ld d,a
        ld a,(K_RD)
        ld e,a
        ld a,6
        call ct_err
tr5:    ld a,(v_k)
        inc a
        ld (v_k),a
        cp 3
        jr nz,tr2
        ld a,(v_pg)
        inc a
        ld (v_pg),a
        cp NP
        ret z
        cp 8
        jr nz,tr1
        ret

;---------------------------------------------------------------------
; TEST 7 - MAPPAGE &DF du CPC+ : &DF 0 et &DF #21 -> page 1, &DF 7 -> page 3
;---------------------------------------------------------------------
t_dfmap:
        ld a,7
        call ct_cur
        call ct_upon
        ld bc,#DF00
        ld d,1
        call td1
        ld bc,#DF21
        ld d,1
        call td1
        ld a,NP
        cp 4
        jp c,ct_upoff
        ld bc,#DF07
        ld d,3
        call td1
        jp ct_upoff
td1:    out (c),c
        ld a,c
        ld (v_pg),a
        ld a,(#C018)
        cp d
        ret z
        ld e,a
        ld hl,#C018
        ld a,7
        jp ct_err

;---------------------------------------------------------------------
; OUTILS
;---------------------------------------------------------------------
ct_selp:                         ; A = page : &DF #80+A, ROM haute ON
        push bc
        or #80
        ld b,#DF
        out (c),a
        pop bc
ct_upon:
        push bc
        ld bc,#7F82              ; mode 2, ROM basse ON, ROM haute ON
        out (c),c
        pop bc
        ret
ct_upoff:
        push bc
        ld bc,#7F8A              ; ROM haute OFF (lecture de la RAM #C000)
        out (c),c
        pop bc
        ret

ct_seed:                         ; DE = graine de la page (v_pg)
        ld a,(v_pg)
        xor #5A
        ld d,a
        ld a,(v_pg)
        xor #3C
        ld e,a
        ret

;---------------------------------------------------------------------
; Sommes POP de reference, calculees avec le LFSR (sans lire la cartouche)
;---------------------------------------------------------------------
ct_psums:
        ld a,1
cp1:    ld (v_pg),a
        cp NP
        ret nc
        call ct_seed
        ld hl,0
        ld bc,#3B00/2
cp2:    push bc
        srl d                    ; octet de poids faible
        rr e
        jr nc,cp3
        ld a,d
        xor #B4
        ld d,a
cp3:    ld c,e
        srl d                    ; octet de poids fort
        rr e
        jr nc,cp4
        ld a,d
        xor #B4
        ld d,a
cp4:    ld b,e
        add hl,bc
        pop bc
        dec bc
        ld a,b
        or c
        jr nz,cp2
        ex de,hl
        ld a,(v_pg)
        add a,a
        ld l,a
        ld h,0
        ld bc,v_psum
        add hl,bc
        ld (hl),e
        inc hl
        ld (hl),d
        ld a,(v_pg)
        inc a
        jr cp1

;---------------------------------------------------------------------
; ERREUR : A = test, HL = adresse, D = attendu, E = lu (page = v_pg)
; Compte l'erreur et memorise la derniere. Preserve BC, DE, HL.
;---------------------------------------------------------------------
ct_err: push hl
        push de
        push bc
        ld (v_e_t),a
        ld (v_e_a),hl
        ld a,d
        ld (v_e_x),a
        ld a,e
        ld (v_e_r),a
        ld a,(v_pg)
        ld (v_e_p),a
        ld a,(v_e_t)
        dec a
        add a,a
        ld e,a
        ld d,0
        ld hl,v_err
        add hl,de
        inc (hl)
        jr nz,ce1
        inc hl
        inc (hl)
ce1:    pop bc
        pop de
        pop hl
        ret

;---------------------------------------------------------------------
; AFFICHAGE (fonte de la cartouche en #3900, ROM basse toujours active)
;---------------------------------------------------------------------
ct_border:
        ld bc,#7F10
        out (c),c
        out (c),a
        ret

ct_cls: ld hl,SCR
        ld de,SCR+1
        ld bc,#3FFF
        ld (hl),0
        ldir
        ret

ct_loc: ld hl,SCR                ; D = ligne, E = colonne
        ld a,d
        or a
        jr z,cl3
        ld bc,80
cl2:    add hl,bc
        dec a
        jr nz,cl2
cl3:    ld d,0
        add hl,de
        ld (v_curs),hl
        ret

ct_prt: ld a,(hl)
        or a
        ret z
        call ct_putc
        inc hl
        jr ct_prt

ct_putc:                         ; A = caractere (preserve HL, DE, BC)
        push hl
        push de
        push bc
        cp #60
        jr c,pc1
        and #DF                  ; minuscules -> majuscules
pc1:    ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,FONT
        add hl,de
        ld de,(v_curs)
        ld b,8
pc2:    ld a,(hl)
        ld (de),a
        inc hl
        ld a,d
        add a,8
        ld d,a
        djnz pc2
        ld hl,(v_curs)
        inc hl
        ld (v_curs),hl
        pop bc
        pop de
        pop hl
        ret

ct_hex16:
        ld a,h
        call ct_hex8
        ld a,l
ct_hex8:
        push af
        rrca
        rrca
        rrca
        rrca
        call ct_hexn
        pop af
ct_hexn:
        and #0F
        add a,'0'
        cp '9'+1
        jr c,ch1
        add a,7
ch1:    jp ct_putc

ct_cur:                          ; A = test en cours (affiche, pour un plantage)
        ld (v_test),a
        push af
        ld de,#1400
        call ct_loc
        ld hl,ct_mcur
        call ct_prt
        pop af
        add a,'0'
        call ct_putc
        ld hl,ct_mcpg
        jp ct_prt

ct_curpg:                        ; affiche la page en cours
        ld de,#1418
        call ct_loc
        ld a,(v_pg)
        jp ct_hex8

ct_silence:
        ld a,7
        ld c,#3F
        call ct_psgw
        ld a,8
        ld c,0
        call ct_psgw
        ld a,9
        call ct_psgw
        ld a,10
ct_psgw:                         ; A = registre, C = valeur (AY via le PPI)
        ld b,#F4
        out (c),a
        ld b,#F6
        ld a,#C0
        out (c),a
        xor a
        out (c),a
        ld b,#F4
        out (c),c
        ld b,#F6
        ld a,#80
        out (c),a
        xor a
        out (c),a
        ret

;---------------------------------------------------------------------
; Ecran fixe
;---------------------------------------------------------------------
ct_screen:
        ld hl,ct_stab
cs4:    ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,d
        cp #FF
        jr z,cs5
        push hl
        call ct_loc
        pop hl
        call ct_prt
        inc hl
        jr cs4
cs5:    ld de,#0028              ; taille de la cartouche
        call ct_loc
        ld hl,ct_mpg
        call ct_prt
        ld de,#010A
        call ct_loc
        ld hl,ct_mnop
        ld a,(v_plus)
        or a
        jr z,cs6
        ld hl,ct_mplus
cs6:    jp ct_prt

;---------------------------------------------------------------------
; Etat : carte des pages, compteurs, derniere erreur, bord
;---------------------------------------------------------------------
ct_show:
        ld de,#030E              ; carte des 32 pages
        call ct_loc
        ld hl,v_map
        ld b,32
sh1:    ld a,(hl)
        push hl
        ld hl,ct_mapc
        bit 7,a
        jr z,sh2
        ld a,5
sh2:    and 7
        ld e,a
        ld d,0
        add hl,de
        ld a,(hl)
        call ct_putc
        pop hl
        inc hl
        djnz sh1
        ld hl,v_err              ; compteurs d'erreurs
        ld d,7
        ld b,8
sh3:    push bc
        push de
        push hl
        ld e,45
        call ct_loc
        pop hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ex de,hl
        call ct_hex16
        ex de,hl
        pop de
        inc d
        pop bc
        djnz sh3
        ld de,#1008
        call ct_loc
        ld hl,(v_pass)
        call ct_hex16
        ld de,#1017
        call ct_loc
        ld hl,(v_frm)
        call ct_hex16
        ld de,#1029
        call ct_loc
        ld a,(v_last)
        call ct_hex8
        ld hl,v_err              ; total
        ld b,8
        xor a
sh4:    or (hl)
        inc hl
        djnz sh4
        or a
        ld a,#52                 ; vert
        jr z,sh5
        ld de,#1218              ; derniere erreur
        call ct_loc
        ld a,(v_e_t)
        call ct_hex8
        ld de,#1221
        call ct_loc
        ld a,(v_e_p)
        call ct_hex8
        ld de,#1229
        call ct_loc
        ld hl,(v_e_a)
        call ct_hex16
        ld de,#1237
        call ct_loc
        ld a,(v_e_x)
        call ct_hex8
        ld de,#123E
        call ct_loc
        ld a,(v_e_r)
        call ct_hex8
        ld a,#4C                 ; rouge
sh5:    jp ct_border

;---------------------------------------------------------------------
; Noyau RMR2, copie et execute en RAM. RELOGEABLE : sauts JR/DJNZ
; seulement ; adresses absolues uniquement vers K_xxx et la RAM de test.
;  KRAM+0 : detection de l'ASIC (DI) -> A = 1 si CPC+
;  KRAM+2 : test de la page K_P a l'emplacement K_L (DI) -> A = 0 si OK,
;           sinon 1 et K_EADR / K_EXP / K_RD
;---------------------------------------------------------------------
ct_kern:
        jr kd0
        jr kt0
kd0:    xor a                    ; RAM #4010/#4019 : temoins
        ld (#4010),a
        ld (#4019),a
        ld bc,#7FA8              ; RMR2 : page 0 en #4000 (CPC+ deverrouille)
        out (c),c
        ld a,(#4010)
        cp 'C'
        jr nz,kd1
        ld a,(#4011)
        cp 'A'
        jr nz,kd1
        ld a,(#4019)
        cp #FF
        jr nz,kd1
        ld a,1
        jr kd2
kd1:    xor a
kd2:    ld bc,#7FA0              ; RMR2 : page 0 en #0000
        out (c),c
        ld bc,#7F8A              ; (CPC classique : &A8/&A0 = mode 0 -> on remet tout)
        out (c),c
        ret

kt0:    ld (K_SP),sp
        ld a,(K_L)
        cp 2
        jr nz,kt1
        ld sp,#7FF0              ; ROM en #8000-#BFFF : pile en #4000-#7FFF
kt1:    ld a,(K_L)
        add a,a
        add a,a
        add a,a
        ld b,a
        ld a,(K_P)
        or b
        or #A0
        ld b,#7F
        out (c),a                ; RMR2 : page K_P a l'emplacement K_L
        ld a,(K_L)
        rrca
        rrca
        ld (K_BASE),a
        ld h,a
        ld l,#10
        ld e,'C'
        ld a,(hl)
        cp e
        jr nz,kt_err
        ld l,#18
        ld a,(K_P)
        ld e,a
        ld a,(hl)
        cp e
        jr nz,kt_err
        ld a,(K_P)
        or a
        jr z,kt_ok               ; page 0 : signature seulement
        ld d,a                   ; graine de la page
        ld e,a
        ld a,d
        xor #5A
        ld d,a
        ld a,e
        xor #3C
        ld e,a
        ld a,(K_BASE)
        inc a
        ld h,a
        ld l,0                   ; base + #100
        ld bc,#3B00
kt2:    srl d
        rr e
        jr nc,kt3
        ld a,d
        xor #B4
        ld d,a
kt3:    ld a,(hl)
        cp e
        jr nz,kt_err
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,kt2
        ld a,(K_BASE)            ; execution des 4 copies (base + #3C00...)
        add a,#3C
        ld h,a
        ld l,0
        ld b,4
kt4:    push bc
        push hl
        ld de,(K_SEED)
        call K_STUB              ; JP (HL)
        ld de,(K_REF)
        ld a,l
        cp e
        jr nz,kt_xe
        ld a,h
        ld e,d
        cp e
        jr nz,kt_xe
        pop hl
        pop bc
        inc h
        djnz kt4
kt_ok:  xor a
        jr kt_end
kt_xe:  pop hl                   ; HL = adresse de la copie (A, E conserves)
        pop bc
kt_err: ld (K_EADR),hl           ; HL adresse, A lu, E attendu
        ld (K_RD),a
        ld a,e
        ld (K_EXP),a
        ld a,1
kt_end: ld bc,#7FA0              ; RMR2 : page 0 en #0000
        out (c),c
        ld sp,(K_SP)
        ret
ct_kend:

; routine d'execution de reference (copiee en RXRAM, numero de page patche)
ct_rx:  RXCODE 0
ct_rxe:
        assert ct_rxe-ct_rx < #100
        assert ct_kend-ct_kern < #400

; ---------------------------------------------------------------------
ct_crtc: db 63,40,46,#8E,38,0,25,30,0,7,0,0,#30,0,0,0
ct_useq: db #FF,#00,#FF,#77,#B3,#51,#A8,#D4,#62,#39,#9C,#46,#2B,#15,#8A,#CD,#EE
ct_mapc: db "?OM.!!"         ; 0 ? 1 presente 2 miroir 3 absente 4 autre 5 erreur

; textes fixes : ligne, colonne, texte
ct_stab:
        db 0,0,"CARTTEST V1 - TEST DE CARTOUCHE (CPR) -",0
        db 0,1,"MACHINE : ",0
        db 0,3,"PAGES 00-31 :",0
        db 0,4,"O PRESENTE  M MIROIR  . ABSENTE  ! ERREUR (PAGE < TAILLE ABSENTE OU INSTABLE)",0
        db 0,6,"   TEST                                     ERREURS",0
        db 0,7,"1  SIGNATURES DES PAGES (&DF #80-#9F)       &",0
        db 0,8,"2  LECTURE LD A,(HL) DE TOUTES LES DONNEES  &",0
        db 0,9,"3  RAFALES LDI / POP                        &",0
        db 0,10,"4  EXECUTION DEPUIS LA PAGE (CYCLES M1)     &",0
        db 0,11,"5  COMMUTATION RAPIDE &DF + LECTURE         &",0
        db 0,12,"6  RMR2 : PAGES 0-7 EN #0000/#4000/#8000    &",0
        db 0,13,"7  MAPPAGE &DF 0 ET 7 (CPC+)                &",0
        db 0,14,"8  INTERRUPTIONS (6 PAR TRAME)              &",0
        db 0,16,"PASSES &       TRAMES &       INT/TRAME &   (DOIT ETRE 06)",0
        db 0,18,"DERNIERE ERREUR : TEST &   PAGE &   ADR &     ATTENDU &   LU &",0
        db 0,22,"BORD VERT = AUCUNE ERREUR  ROUGE = ERREUR  ECRAN FIGE = PLANTAGE",0
        db 0,23,"LE COIN HAUT DROIT CLIGNOTE TANT QUE LES INTERRUPTIONS TOURNENT",0
        db #FF,#FF
        if NP==8
ct_mpg:  db "CPR 128 KO (8 PAGES)",0
        elseif NP==16
ct_mpg:  db "CPR 256 KO (16 PAGES)",0
        else
ct_mpg:  db "CPR 512 KO (32 PAGES)",0
        endif
ct_mplus: db "CPC+ (ASIC DETECTE) : TESTS 1 A 8",0
ct_mnop: db "PAS D'ASIC (CPC CLASSIQUE) : TESTS 6 ET 7 SAUTES",0
ct_mcur: db "EN COURS : TEST ",0
ct_mcpg: db " PAGE &",0

ct_end:
        assert ct_end <= FONT+#100      ; le code ne doit pas atteindre la fonte (#3900)

        org FONT+#100
        include "cartfont.asm"

; =====================================================================
; PAGES 1 .. NP-1 (vues en #C000)
; =====================================================================
        repeat NP-1,pp
        bank pp
        org #C000
        ds 16,#FF
        SIGN pp
        tg=#20
        repeat #E0
        db (tg^pp^#A5)&#FF
        tg=tg+1
        rend
        seed=#5A3C^(pp*#101)
        repeat #3B00
        if seed&1
        seed=(seed>>1)^#B400
        else
        seed=seed>>1
        endif
        db seed&#FF
        rend
        repeat 4
        RXCODE pp
        ds #100-($&#FF),#FF
        rend
        rend
