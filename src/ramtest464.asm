; =====================================================================
;  RAMTEST 464 - test "violent" des 64 Ko de RAM de base (8 x 4164)
;  Assembleur : RASM
;
;  Principe :
;   - DI, ROM basse et haute coupees : on teste la VRAAAIE RAM de #0000 a #FFFF
;   - Phase A : le programme tourne dans un bloc de 2 Ko (#8000-#87FF)
;               et teste TOUT le reste (#0000-#7FFF et #8800-#FFFF)
;   - Phase B : une petite routine copiee en #4000 (RAM deja validee)
;               sauvegarde le bloc #8000-#87FF, le teste, puis le restaure
;   => les 65536 octets sont testes a chaque passe
;
;  Tests (couleur du BORD pendant le test) :
;   1 bleu      motifs fixes 00 FF 55 AA 33 CC 0F F0 (remplir tout, relire tout)
;   2 magenta   adresse dans adresse (L xor H, puis inverse) -> lignes d'adresse,
;               multiplexeurs 74LS153, alias
;   3 cyan      March C- (montant/descendant) -> cellules collees, couplages
;   4 jaune     pseudo-aleatoire LFSR (graine differente a chaque passe)
;   5 orange    retention : 55 puis AA, attente ~4 s, relecture
;   6 blanc     bloc du programme #8000-#87FF (tests 1,2,3,4,5 en version courte)
;   vert        passe OK (affiche le compteur de passes, puis reboucle)
;   ROUGE       ERREUR : adresse, attendu, lu, XOR et numero(s) de bit fautif(s)
;
;  Pendant le test, l'ecran (#C000-#FFFF) affiche les motifs : c'est normal.
;
;  Lancement depuis le BASIC :
;     MEMORY &7FFF:LOAD"RAMTEST.BIN",&8000:CALL &8000
;  Sortie : reset / extinction.
; =====================================================================

BLK     equ #8000       ; bloc du programme (exclu de la phase A)
BLKLEN  equ #800        ; 2 Ko
PADDR   equ #4000       ; ou on copie la routine de la phase B
BACKUP  equ #4800       ; sauvegarde du bloc pendant la phase B
SCR     equ #C000

        org BLK

;---------------------------------------------------------------------
; POINT D'ENTREE : DI, pile dans le bloc protege (#8000-#87FF),
; mode 2, ROM coupees, CRTC sur #C000.
;---------------------------------------------------------------------
start:
        di
        ld sp,BLK+BLKLEN
        ld bc,#7F8E             ; mode 2, ROM basse OFF, ROM haute OFF
        out (c),c
        ld bc,#7F00             ; encre 0 = noir, encre 1 = blanc
        out (c),c
        ld a,#54
        out (c),a
        ld a,1
        out (c),a
        ld a,#4B
        out (c),a
        ld bc,#BC0C             ; CRTC : ecran en #C000, pas de scroll
        out (c),c
        ld bc,#BD30
        out (c),c
        ld bc,#BC0D
        out (c),c
        ld bc,#BD00
        out (c),c

        ld hl,0
        ld (pass),hl

        call cls
        ld de,#0000
        call locate
        ld hl,msg_titre
        call prtstr
        ld de,#0200
        call locate
        ld hl,msg_leg1
        call prtstr
        ld de,#0300
        call locate
        ld hl,msg_leg2
        call prtstr
        ld de,#0400
        call locate
        ld hl,msg_leg3
        call prtstr
        call wait4s

; ---------------------------------------------------------------------
;---------------------------------------------------------------------
; UNE PASSE : T1..T5 sur toute la RAM SAUF le bloc #8000-#87FF,
; puis T6 (routine copiee en #4000) teste le bloc lui-meme.
;---------------------------------------------------------------------
mainloop:
; ---- T1 : motifs fixes ----
        ld a,1
        ld (curtest),a
        ld a,#44                ; bleu
        call border
        ld hl,patterns
        ld b,8
t1lp:   push bc
        push hl
        ld e,(hl)
        ld iy,fill_e
        call callrng
        ld iy,ver_e
        call callrng
        pop hl
        inc hl
        pop bc
        djnz t1lp

; ---- T2 : adresse dans adresse ----
        ld a,2
        ld (curtest),a
        ld a,#58                ; magenta
        call border
        ld e,#00
        call t2run
        ld e,#FF
        call t2run

; ---- T3 : March C- ----
        ld a,3
        ld (curtest),a
        ld a,#46                ; cyan
        call border
        ld e,0                  ; M0 : ^ w0
        ld iy,fill_e
        call callrng
        ld e,0                  ; M1 : ^ r0 w1
        ld d,#FF
        ld iy,mr_up
        call callrng
        ld e,#FF                ; M2 : ^ r1 w0
        ld d,0
        ld iy,mr_up
        call callrng
        ld e,0                  ; M3 : v r0 w1
        ld d,#FF
        ld iy,mr_dn
        call callrng
        ld e,#FF                ; M4 : v r1 w0
        ld d,0
        ld iy,mr_dn
        call callrng
        ld e,0                  ; M5 : r0
        ld iy,ver_e
        call callrng

; ---- T4 : pseudo-aleatoire ----
        ld a,4
        ld (curtest),a
        ld a,#4A                ; jaune
        call border
        ld hl,(pass)
        ld de,#ACE1
        add hl,de
        ld a,h
        or l
        jr nz,t4a
        inc l                   ; graine jamais nulle
t4a:    ld (seed),hl
        ex de,hl
        ld iy,fill_rnd
        call callrng
        ld de,(seed)
        ld iy,ver_rnd
        call callrng

; ---- T5 : retention ----
        ld a,5
        ld (curtest),a
        ld a,#4E                ; orange
        call border
        ld e,#55
        call t5run
        ld e,#AA
        call t5run

; ---- T6 : bloc du programme (routine copiee en #4000) ----
        ld a,6
        ld (curtest),a
        ld a,#4B                ; blanc
        call border
        ld hl,p_start
        ld de,PADDR
        ld bc,p_end-p_start
        ldir
        jp PADDR

after_p:                        ; retour de la phase B, bloc restaure
        ld sp,BLK+BLKLEN
        ld hl,(pass)
        inc hl
        ld (pass),hl
        ld a,#52                ; vert
        call border
        call cls
        ld de,#0000
        call locate
        ld hl,msg_titre
        call prtstr
        ld de,#0200
        call locate
        ld hl,msg_passe
        call prtstr
        ld hl,(pass)
        call phex16
        ld hl,msg_ok
        call prtstr
        call wait4s
        jp mainloop

; ---------------------------------------------------------------------
t2run:  ld iy,fill_adr
        call callrng
        ld iy,ver_adr
        jp callrng

t5run:  ld iy,fill_e
        call callrng
        push de
        call wait4s
        pop de
        ld iy,ver_e
        jp callrng

; appelle (IY) sur les 2 zones hors bloc : HL=debut, BC=longueur
;---------------------------------------------------------------------
; Appelle la routine (IY) sur les deux zones hors bloc :
; #0000-#7FFF puis #8800-#FFFF.
;---------------------------------------------------------------------
callrng:
        ld hl,#0000
        ld bc,BLK
        call jpiy
        ld hl,BLK+BLKLEN
        ld bc,#10000-(BLK+BLKLEN)
jpiy:   jp (iy)

; ---- routines de test (HL=debut, BC=longueur) ----
; erreur -> jp ram_err avec HL=adresse, A=lu, E=attendu

fill_e: ld (hl),e
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,fill_e
        ret

ver_e:  ld a,(hl)
        cp e
        jp nz,ram_err
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,ver_e
        ret

fill_adr:                       ; E = masque
        ld a,l
        xor h
        xor e
        ld (hl),a
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,fill_adr
        ret

ver_adr:
        ld a,l
        xor h
        xor e
        ld d,a
        ld a,(hl)
        cp d
        jr nz,adr_err
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,ver_adr
        ret
adr_err:
        ld e,d
        jp ram_err

mr_up:                          ; E = attendu, D = a ecrire, sens montant
        ld a,(hl)
        cp e
        jp nz,ram_err
        ld (hl),d
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,mr_up
        ret

mr_dn:                          ; idem, sens descendant
        add hl,bc
        dec hl
mrd_lp: ld a,(hl)
        cp e
        jp nz,ram_err
        ld (hl),d
        dec hl
        dec bc
        ld a,b
        or c
        jr nz,mrd_lp
        ret

fill_rnd:                       ; DE = etat LFSR 16 bits
        srl d
        rr e
        jr nc,frn
        ld a,d
        xor #B4
        ld d,a
frn:    ld (hl),e
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,fill_rnd
        ret

ver_rnd:
        srl d
        rr e
        jr nc,vrn
        ld a,d
        xor #B4
        ld d,a
vrn:    ld a,(hl)
        cp e
        jp nz,ram_err
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,ver_rnd
        ret

; ---------------------------------------------------------------------
; ERREUR : HL=adresse, A=lu, E=attendu
;---------------------------------------------------------------------
; Ecran d'erreur : test, passe, adresse, attendu, lu, XOR et liste des
; bits fautifs (sur le 464, 1 bit = 1 boitier 4164).
;---------------------------------------------------------------------
ram_err:
        ld sp,BLK+BLKLEN
        ld (e_adr),hl
        ld (e_lu),a
        ld a,e
        ld (e_att),a
        ld a,#4C                ; rouge
        call border
        call cls
        ld de,#0000
        call locate
        ld hl,msg_titre
        call prtstr
        ld de,#0200
        call locate
        ld hl,msg_err
        call prtstr
        ld a,(curtest)
        add a,'0'
        call putc
        ld a,' '
        call putc
        ld a,(curtest)
        dec a
        add a,a
        ld l,a
        ld h,0
        ld de,tnames
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        call prtstr
        ld de,#0400
        call locate
        ld hl,msg_passe
        call prtstr
        ld hl,(pass)
        call phex16
        ld de,#0500
        call locate
        ld hl,msg_adr
        call prtstr
        ld hl,(e_adr)
        call phex16
        ld de,#0600
        call locate
        ld hl,msg_att
        call prtstr
        ld a,(e_att)
        call phex8
        ld hl,msg_lu
        call prtstr
        ld a,(e_lu)
        call phex8
        ld hl,msg_xor
        call prtstr
        ld a,(e_lu)
        ld b,a
        ld a,(e_att)
        xor b
        call phex8
        ld de,#0800
        call locate
        ld hl,msg_bits
        call prtstr
        ld a,(e_lu)
        ld b,a
        ld a,(e_att)
        xor b
        ld c,a
        ld d,'0'
eb1:    srl c
        jr nc,eb2
        ld a,d
        call putc
        ld a,' '
        call putc
eb2:    inc d
        ld a,d
        cp '8'
        jr nz,eb1
hang:   jr hang                 ; on reste fige, bord rouge

; ---------------------------------------------------------------------
; affichage mode 2 avec la fonte de la ROM basse (#3800)
border: ld bc,#7F10
        out (c),c
        out (c),a
        ret

cls:    ld hl,SCR
        ld de,SCR+1
        ld bc,#3FFF
        ld (hl),0
        ldir
        ret

locate:                         ; D = ligne (0-24), E = colonne (0-79)
        ld hl,SCR
        ld a,d
        or a
        jr z,lc2
        ld bc,80
lc1:    add hl,bc
        dec a
        jr nz,lc1
lc2:    ld d,0
        add hl,de
        ld (curs),hl
        ret

prtstr:  ld a,(hl)
        or a
        ret z
        call putc
        inc hl
        jr prtstr

;---------------------------------------------------------------------
; Affichage mode 2 avec la fonte de la ROM basse (#3800).
;---------------------------------------------------------------------
putc:   push hl
        push de
        push bc
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,#3800
        add hl,de
        ld de,(curs)
        ld bc,#7F8A             ; ROM basse ON le temps de lire la fonte
        out (c),c
        ld b,8
pc1:    ld a,(hl)
        ld (de),a
        inc hl
        ld a,d
        add a,8
        ld d,a
        djnz pc1
        ld bc,#7F8E             ; ROM basse OFF
        out (c),c
        ld hl,(curs)
        inc hl
        ld (curs),hl
        pop bc
        pop de
        pop hl
        ret

phex16: ld a,h
        call phex8
        ld a,l
phex8:  push af
        rrca
        rrca
        rrca
        rrca
        call phexn
        pop af
phexn:  and #0F
        add a,'0'
        cp '9'+1
        jr c,ph1
        add a,7
ph1:    jp putc

wait4s:                          ; ~4 secondes (detruit A, DE, H)
        ld h,8
dl1:    ld de,0
dl2:    dec de
        ld a,d
        or e
        jr nz,dl2
        dec h
        jr nz,dl1
        ret

; ---------------------------------------------------------------------
; PHASE B : code copie et execute en #4000 (JR uniquement en interne,
; appels/sauts internes via adresse PADDR+(x-p_start))
; ---------------------------------------------------------------------
;---------------------------------------------------------------------
; PHASE B (code copie et execute en #4000, relogeable) :
; sauvegarde du bloc #8000-#87FF en #4800, tests du bloc, restauration.
;---------------------------------------------------------------------
p_start:
        ld sp,BACKUP            ; pile entre le code et la sauvegarde
        ld hl,BLK
        ld de,BACKUP
        ld bc,BLKLEN
        ldir                    ; sauvegarde du bloc
        ; motifs fixes
        ld hl,PADDR+(ptbl-p_start)
        ld b,8
pp1:    push bc
        push hl
        ld e,(hl)
        call PADDR+(pfill-p_start)
        call PADDR+(pver-p_start)
        pop hl
        inc hl
        pop bc
        djnz pp1
        ; adresse dans adresse
        ld e,#00
        call PADDR+(pafill-p_start)
        call PADDR+(paver-p_start)
        ld e,#FF
        call PADDR+(pafill-p_start)
        call PADDR+(paver-p_start)
        ; March C-
        ld e,0
        call PADDR+(pfill-p_start)
        ld e,0
        ld d,#FF
        call PADDR+(pmup-p_start)
        ld e,#FF
        ld d,0
        call PADDR+(pmup-p_start)
        ld e,0
        ld d,#FF
        call PADDR+(pmdn-p_start)
        ld e,#FF
        ld d,0
        call PADDR+(pmdn-p_start)
        ld e,0
        call PADDR+(pver-p_start)
        ; aleatoire
        ld de,#ACE1
        call PADDR+(prfill-p_start)
        ld de,#ACE1
        call PADDR+(prver-p_start)
        ; retention
        ld e,#55
        call PADDR+(pfill-p_start)
        call PADDR+(pdelay-p_start)
        call PADDR+(pver-p_start)
        ld e,#AA
        call PADDR+(pfill-p_start)
        call PADDR+(pdelay-p_start)
        call PADDR+(pver-p_start)
        ; restauration et retour
        ld hl,BACKUP
        ld de,BLK
        ld bc,BLKLEN
        ldir
        jp after_p

pfill:  ld hl,BLK
        ld bc,BLKLEN
pf1:    ld (hl),e
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,pf1
        ret

pver:   ld hl,BLK
        ld bc,BLKLEN
pv1:    ld a,(hl)
        cp e
        jp nz,PADDR+(perr-p_start)
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,pv1
        ret

pafill: ld hl,BLK
        ld bc,BLKLEN
paf1:   ld a,l
        xor h
        xor e
        ld (hl),a
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,paf1
        ret

paver:  ld hl,BLK
        ld bc,BLKLEN
pav1:   ld a,l
        xor h
        xor e
        ld d,a
        ld a,(hl)
        cp d
        jr nz,paerr
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,pav1
        ret
paerr:  ld e,d
        jp PADDR+(perr-p_start)

pmup:   ld hl,BLK
        ld bc,BLKLEN
pmu1:   ld a,(hl)
        cp e
        jp nz,PADDR+(perr-p_start)
        ld (hl),d
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,pmu1
        ret

pmdn:   ld hl,BLK+BLKLEN-1
        ld bc,BLKLEN
pmd1:   ld a,(hl)
        cp e
        jp nz,PADDR+(perr-p_start)
        ld (hl),d
        dec hl
        dec bc
        ld a,b
        or c
        jr nz,pmd1
        ret

prfill: ld hl,BLK
        ld bc,BLKLEN
prf1:   srl d
        rr e
        jr nc,prf2
        ld a,d
        xor #B4
        ld d,a
prf2:   ld (hl),e
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,prf1
        ret

prver:  ld hl,BLK
        ld bc,BLKLEN
prv1:   srl d
        rr e
        jr nc,prv2
        ld a,d
        xor #B4
        ld d,a
prv2:   ld a,(hl)
        cp e
        jp nz,PADDR+(perr-p_start)
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,prv1
        ret

pdelay: ld h,8                  ; preserve E
pd1:    ld bc,0
pd2:    dec bc
        ld a,b
        or c
        jr nz,pd2
        dec h
        jr nz,pd1
        ret

;---------------------------------------------------------------------
; Erreur dans le bloc : on le restaure AVANT de sauter a l'ecran d'erreur
; (qui est lui-meme dans ce bloc).
;---------------------------------------------------------------------
perr:                           ; HL=adresse, A=lu, E=attendu
        ex af,af'
        exx
        ld hl,BACKUP            ; on restaure le bloc avant d'afficher
        ld de,BLK
        ld bc,BLKLEN
        ldir
        exx
        ld a,6
        ld (curtest),a
        ex af,af'
        jp ram_err

ptbl:   db #00,#FF,#55,#AA,#33,#CC,#0F,#F0
p_end:

; ---------------------------------------------------------------------
patterns:
        db #00,#FF,#55,#AA,#33,#CC,#0F,#F0

tnames: dw tn1,tn2,tn3,tn4,tn5,tn6
tn1:    db "(motifs fixes)",0
tn2:    db "(adresse/adresse)",0
tn3:    db "(March C-)",0
tn4:    db "(aleatoire)",0
tn5:    db "(retention)",0
tn6:    db "(bloc #8000-#87FF)",0

msg_titre: db "RAMTEST 464 - test violent des 64 Ko (#0000-#FFFF)",0
msg_leg1:  db "Bord: bleu=motifs  magenta=adresse  cyan=March C-",0
msg_leg2:  db "      jaune=aleatoire  orange=retention  blanc=bloc prog",0
msg_leg3:  db "      vert=passe OK   ROUGE=ERREUR   (~1 min par passe)",0
msg_passe: db "PASSE : &",0
msg_ok:    db "  OK",0
msg_err:   db "*** ERREUR - TEST ",0
msg_adr:   db "ADRESSE : &",0
msg_att:   db "ATTENDU : &",0
msg_lu:    db "   LU : &",0
msg_xor:   db "   XOR : &",0
msg_bits:  db "BIT(S) EN DEFAUT (D0-D7) : ",0

; variables (dans le bloc protege)
curs:    dw SCR
pass:    dw 0
seed:    dw 0
e_adr:   dw 0
e_lu:    db 0
e_att:   db 0
curtest: db 0

fin:
        assert fin-BLK < BLKLEN-#40   ; garder de la place pour la pile
        assert p_end-p_start < BACKUP-PADDR-#40

        save "RAMTEST.BIN",BLK,fin-BLK,AMSDOS
