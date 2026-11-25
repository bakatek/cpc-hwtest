; =====================================================================
;  DSKTEST - acces disquette, cas limites (FDC uPD765) - tout CPC - RASM
;
;  A lancer avec la disquette de test DSKTEST.DSK dans le lecteur A:
;  (fabriquee par mkdsktest.py, qui y place aussi DSKTEST.BIN).
;  Le FDC est pilote directement (ports &FA7E moteur, &FB7E etat,
;  &FB7F donnees), sans AMSDOS, interruptions coupees. LECTURE SEULE.
;
;  Le contenu de la disquette de test est connu (LFSR par secteur) :
;   piste 20  : format DATA standard, 9 x 512 (#C1-#C9)
;   piste 21  : 10 secteurs de 512 (#C1-#CA)
;   piste 22  : tailles 128, 256, 512, 1024, 2048 (R = 1..5, N = 0..4)
;   piste 23  : un secteur de 4 Ko (R = #51, N = 5)
;   piste 24  : IDs non standard (C <> piste, H = 1 ou #FF, R = 0, #FF...)
;   piste 25  : secteurs #C2 et #C4 marques EFFACES
;   piste 26  : secteur #C2 avec erreur CRC (donnees)
;   piste 27  : NON FORMATEE
;   pistes 40-41 : format DATA standard (au-dela des 40 pistes)
;
;  Chaque test compte des ERREURS (resultat faux, donnees fausses, FDC
;  bloque) et des ecarts de CONFORMITE (INFO : comportement d'un vrai 765
;  que l'emulation ne reproduit pas forcement, sans danger pour les
;  logiciels courants : fin de lecture par EN, overrun...).
;
;  BASIC :  RUN"DSKTEST.BIN"
;       ou  MEMORY &7FFF:LOAD"DSKTEST.BIN",&8000:CALL &8000
; =====================================================================

BUF     equ #4000               ; tampon de lecture (jusqu'a #5FFF)
NT      equ 15                  ; nombre de tests
COL_ERR equ 46                  ; colonnes des compteurs
COL_INF equ 54

        org #8000

;---------------------------------------------------------------------
; INITIALISATION
;---------------------------------------------------------------------
dk_start:
        di
        ld sp,#C000
        call lib_init
        call lib_cls
        ld hl,dk_vars            ; variables a zero
        ld de,dk_vars+1
        ld bc,dk_vend-dk_vars-1
        ld (hl),0
        ldir
        ld a,#FF
        ld (dk_trk),a            ; piste inconnue
        ld hl,dk_stab            ; ecran fixe
dk_s1:  ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,d
        cp #FF
        jr z,dk_s2
        push hl
        call lib_locate
        pop hl
        call lib_prt
        inc hl
        jr dk_s1
dk_s2:  ; un FDC est-il present ? (sans FDC le bus relit #FF)
        ld bc,#FB7E
        in a,(c)
        cp #FF
        jr nz,dk_s3
        ld de,#1600
        call lib_locate
        ld hl,dk_mnofdc
        call lib_prt
        ld a,#4C
        call lib_border
dk_hang:
        jr dk_hang
dk_s3:  call fd_drain            ; vide un eventuel resultat en attente
        ld bc,#FA7E              ; moteur ON
        ld a,1
        out (c),a
        ld h,3                   ; ~1,3 s : mise en vitesse
        call lib_wait
        ld hl,dk_cspec           ; SPECIFY (valeurs d'AMSDOS)
        call fd_cmd

;---------------------------------------------------------------------
; BOUCLE DES PASSES
;---------------------------------------------------------------------
dk_loop:
        call t_seek              ; 1
        ld hl,dk_tab             ; 2 a 11 et 13 : lectures decrites par la table
dk_l1:  ld a,(hl)
        or a
        jr z,dk_l2
        push hl
        call t_read
        pop hl
        ld de,ENTSZ
        add hl,de
        jr dk_l1
dk_l2:  call t_rid               ; 12
        call t_ovr               ; 14
        call t_inv               ; 15
        ld hl,(dk_pass)
        inc hl
        ld (dk_pass),hl
        call dk_show
        jp dk_loop

;---------------------------------------------------------------------
; TEST 1 - RECALIBRAGE et SEEK : PCN attendu apres chaque deplacement,
; piste 0 signalee par SENSE DRIVE STATUS (ST3 bit 4, INFO).
;---------------------------------------------------------------------
t_seek: ld a,1
        call dk_cur
        call fd_recal
        ld a,2                   ; SENSE DRIVE STATUS : ST3
        ld (dk_cv),a
        ld a,4
        ld (dk_cbuf),a
        xor a
        ld (dk_cbuf+1),a
        ld hl,dk_cv
        call fd_cmd
        ret c
        call fd_res
        ld a,(dk_res)
        and #10
        call z,dk_info           ; piste 0 non signalee
        ld hl,dk_seeks
tk1:    ld a,(hl)
        cp #FF
        ret z
        push hl
        call fd_seek
        pop hl
        inc hl
        jr tk1

;---------------------------------------------------------------------
; LECTURES DECRITES PAR LA TABLE dk_tab (une entree = ENTSZ octets) :
;  test, piste, commande (#46 READ DATA / #4C READ DELETED DATA),
;  C, H, R, N, EOT, nombre de secteurs a verifier (0 = aucun),
;  erreur si (ST0 and m0) <> e0, (ST1 and m1) <> e1, (ST2 and m2) <> e2,
;  INFO   si (ST0 and i0) <> f0, (ST1 and i1) <> f1, (ST2 and i2) <> f2.
;---------------------------------------------------------------------
t_read: ld (dk_ent),hl
        ld a,(hl)
        call dk_cur
        ld ix,(dk_ent)
        ld a,(ix+1)
        call fd_goto
        ld a,(ix+2)              ; commande READ
        ld (dk_cbuf),a
        xor a                    ; lecteur 0, tete 0
        ld (dk_cbuf+1),a
        ld a,(ix+3)              ; C H R N EOT
        ld (dk_cbuf+2),a
        ld a,(ix+4)
        ld (dk_cbuf+3),a
        ld a,(ix+5)
        ld (dk_cbuf+4),a
        ld (dk_esec),a
        ld a,(ix+6)
        ld (dk_cbuf+5),a
        ld a,(ix+7)
        ld (dk_cbuf+6),a
        ld a,#2A                 ; GPL
        ld (dk_cbuf+7),a
        ld a,(ix+6)              ; DTL : #80 si N = 0, sinon #FF
        or a
        ld a,#FF
        jr nz,tr1
        ld a,#80
tr1:    ld (dk_cbuf+8),a
        ld a,9
        ld (dk_cv),a
        ld hl,dk_cv
        call fd_cmd
        ret c
        ld hl,BUF
        call fd_rdfast           ; phase d'execution
        ret c                    ; FDC bloque (erreur deja comptee)
        call fd_res
        call dk_chkst            ; ST0-ST2 contre les masques
        ld ix,(dk_ent)
        ld a,(ix+8)              ; verification des donnees
        or a
        ret z
        ld b,a
        ld a,(ix+5)
        ld (dk_esec),a
        ld hl,BUF
tr2:    push bc
        ld ix,(dk_ent)
        ld b,(ix+6)              ; longueur = 128 << N
        ld de,128
        inc b
tr3:    dec b
        jr z,tr4
        ex de,hl
        add hl,hl
        ex de,hl
        jr tr3
tr4:    ld b,d
        ld c,e
        ld a,(ix+1)              ; graine : (piste xor #A5, R xor #5A)
        xor #A5
        ld d,a
        ld a,(dk_esec)
        xor #5A
        ld e,a
tr5:    srl d
        rr e
        jr nc,tr6
        ld a,d
        xor #B4
        ld d,a
tr6:    ld a,(hl)
        cp e
        call nz,dk_derr
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,tr5
        ld a,(dk_esec)
        inc a
        ld (dk_esec),a
        pop bc
        djnz tr2
        ret

;---------------------------------------------------------------------
; Controle de ST0-ST2 (dk_res) avec les masques de l'entree (dk_ent)
;---------------------------------------------------------------------
dk_chkst:
        ld ix,(dk_ent)
        ld hl,dk_res
        ld b,3
        ld de,0                  ; D = 1 si erreur, E = 1 si ecart INFO
cs1:    ld a,(hl)
        and (ix+9)
        cp (ix+10)
        jr z,cs2
        ld d,1
cs2:    ld a,(hl)
        and (ix+15)
        cp (ix+16)
        jr z,cs3
        ld e,1
cs3:    inc hl
        inc ix
        inc ix
        djnz cs1
        ld a,d
        or a
        jr z,cs4
        ld hl,0
        ld d,0
        ld e,0
        jp dk_err                ; erreur d'etat (ST affiches)
cs4:    ld a,e
        or a
        ret z
        jp dk_info

;---------------------------------------------------------------------
; TEST 12 - READ ID : piste 20 -> C = 20, N = 2, R dans #C1-#C9 ;
; piste 24 -> lecture sans erreur
;---------------------------------------------------------------------
t_rid:  ld a,12
        call dk_cur
        ld a,20
        call fd_goto
        call fd_rid
        ret c
        ld a,(dk_res)
        and #C0
        jr nz,ri_e
        ld a,(dk_res+3)
        cp 20
        jr nz,ri_e
        ld a,(dk_res+6)
        cp 2
        jr nz,ri_e
        ld a,(dk_res+5)
        cp #C1
        jr c,ri_e
        cp #CA
        jr nc,ri_e
        ld a,24
        call fd_goto
        call fd_rid
        ret c
        ld a,(dk_res)
        and #C0
        ret z
ri_e:   ld hl,0
        ld de,0
        jp dk_err

fd_rid: ld a,2                   ; READ ID (MFM), lecteur 0
        ld (dk_cv),a
        ld a,#4A
        ld (dk_cbuf),a
        xor a
        ld (dk_cbuf+1),a
        ld hl,dk_cv
        call fd_cmd
        ret c
        call fd_waitres          ; attend la fin (pas de phase de donnees)
        ret c
        jp fd_res

;---------------------------------------------------------------------
; TEST 14 - OVERRUN : lecture volontairement trop lente (~60 us par
; octet). Un vrai 765 s'arrete avec OR (ST1 bit 4). Pas d'OR = INFO.
; Ne pas finir = ERREUR (FDC bloque).
;---------------------------------------------------------------------
t_ovr:  ld a,14
        call dk_cur
        ld a,20
        call fd_goto
        ld a,#C1
        ld (dk_esec),a
        ld hl,dk_covr
        call fd_cmd
        ret c
        ld hl,BUF
        call fd_rdslow
        ret c
        call fd_res
        ld a,(dk_res+1)
        and #10
        ret nz
        jp dk_info

;---------------------------------------------------------------------
; TEST 15 - COMMANDE INVALIDE (#1F) : un seul octet de resultat, #80
;---------------------------------------------------------------------
t_inv:  ld a,15
        call dk_cur
        ld hl,dk_cinv
        call fd_cmd
        ret c
        call fd_res
        ld a,(dk_nres)
        cp 1
        jr nz,iv_e
        ld a,(dk_res)
        cp #80
        ret z
iv_e:   ld hl,0
        ld de,0
        jp dk_err

;---------------------------------------------------------------------
; FDC - routines de base (BC = #FB7E pendant les echanges)
;---------------------------------------------------------------------
; Envoie la commande HL = (longueur, octets...). CY = 1 si FDC bloque.
fd_cmd: ld a,(hl)
        inc hl
        ld (dk_ccnt),a
fc1:    ld a,(hl)
        inc hl
        call fd_wr
        ret c
        ld a,(dk_ccnt)
        dec a
        ld (dk_ccnt),a
        jr nz,fc1
        ret

fd_wr:                           ; A = octet -> registre de donnees (preserve HL)
        push hl
        ld l,a
        ld bc,#FB7E
        ld de,0
fw1:    in a,(c)
        add a,a                  ; RQM -> CY
        jr nc,fw2
        add a,a                  ; DIO -> CY
        jr c,fw3                 ; le FDC veut envoyer : desynchronise
        inc c
        out (c),l
        dec c
        ex (sp),hl               ; petite attente (mise a jour de l'etat du 765)
        ex (sp),hl
        pop hl
        or a
        ret
fw2:    dec e
        jr nz,fw1
        dec d
        jr nz,fw1
fw3:    pop hl
        jp fd_tout

; Lecture rapide de la phase d'execution (vitesse "chargeur de demo").
; HL = tampon. CY = 1 si le FDC ne repond plus (erreur comptee).
fd_rdfast:
        ld bc,#FB7E
        ld de,0
        ld a,6
        ld (dk_tocnt),a
rf1:    in a,(c)
        jp m,rf2
rfw:    dec e
        jp nz,rf1
        dec d
        jp nz,rf1
        ld a,(dk_tocnt)
        dec a
        ld (dk_tocnt),a
        jp nz,rf1
        jp fd_tout
rf2:    and #20                  ; EXM : encore des donnees ?
        jr z,rfe
        inc c
        in a,(c)
        dec c
        ld (hl),a
        inc hl
        jp rf1
rfe:    in a,(c)                 ; EXM = 0 : resultat seulement si DIO = 1
        and #40                  ; (sinon le 765 n'a pas encore commence)
        ret nz                   ; CY = 0
        jp rfw

; Lecture lente (~60 us entre deux octets) pour provoquer un overrun
fd_rdslow:
        ld bc,#FB7E
        ld de,0
        ld a,6
        ld (dk_tocnt),a
rs1:    in a,(c)
        jp m,rs2
rsw:    dec e
        jp nz,rs1
        dec d
        jp nz,rs1
        ld a,(dk_tocnt)
        dec a
        ld (dk_tocnt),a
        jp nz,rs1
        jp fd_tout
rs2:    and #20                  ; EXM : encore des donnees ?
        jr z,rse
        inc c
        in a,(c)
        dec c
        ld (hl),a
        inc hl
        ld a,15                  ; ~60 us
rs3:    dec a
        jr nz,rs3
        jp rs1
rse:    in a,(c)
        and #40
        ret nz
        jp rsw

; Attend que le FDC passe en phase de resultat (RQM = 1 et DIO = 1)
fd_waitres:
        ld bc,#FB7E
        ld de,0
        ld a,6
        ld (dk_tocnt),a
wr1:    in a,(c)
        and #C0
        cp #C0
        ret z
        dec e
        jr nz,wr1
        dec d
        jr nz,wr1
        ld a,(dk_tocnt)
        dec a
        ld (dk_tocnt),a
        jr nz,wr1
        jp fd_tout

; Lit tous les octets de resultat dans dk_res (dk_nres = nombre)
fd_res: ld bc,#FB7E
        ld hl,dk_res
        xor a
        ld (dk_nres),a
fr1:    ld de,0
fr2:    in a,(c)
        add a,a                  ; RQM
        jr c,fr3
        dec e
        jr nz,fr2
        dec d
        jr nz,fr2
        jp fd_tout
fr3:    add a,a                  ; DIO = 0 : le FDC attend une commande = fin
        ret nc
        inc c
        in a,(c)
        dec c
        ld (hl),a
        inc hl
        ld a,(dk_nres)
        inc a
        ld (dk_nres),a
        cp 8
        ret z
        ex (sp),hl
        ex (sp),hl
        ex (sp),hl
        ex (sp),hl
        jr fr1

; Vide les resultats en attente (au demarrage)
fd_drain:
        ld bc,#FB7E
        ld d,0
dr1:    in a,(c)
        and #C0
        cp #C0
        ret nz
        inc c
        in a,(c)
        dec c
        dec d
        jr nz,dr1
        ret

; FDC bloque : erreur du test en cours, CY = 1
fd_tout:
        ld a,1
        ld (dk_tout),a
        ld hl,#FFFF
        ld de,0
        call dk_err
        call fd_drain
        scf
        ret

; Recalibrage (2 fois au plus si le 765 n'atteint pas la piste 0)
fd_recal:
        ld b,2
rc1:    push bc
        ld hl,dk_crec
        call fd_cmd
        call nc,fd_sense
        pop bc
        jr c,rc2
        ld a,(dk_res)
        and #D0                  ; IC et EC
        cp 0
        jr nz,rc2
        ld a,(dk_res+1)
        or a
        jr nz,rc2
        xor a
        ld (dk_trk),a
        ret
rc2:    djnz rc1
        ld a,#FF
        ld (dk_trk),a
        ld hl,0
        ld de,0
        jp dk_err

; Va sur la piste A si on n'y est pas deja
fd_goto:
        ld hl,dk_trk
        cp (hl)
        ret z
; Seek sur la piste A : PCN = A attendu
fd_seek:
        ld (dk_cbuf+2),a
        ld (dk_trk),a
        ld a,3
        ld (dk_cv),a
        ld a,#0F
        ld (dk_cbuf),a
        xor a
        ld (dk_cbuf+1),a
        ld hl,dk_cv
        call fd_cmd
        jr c,sk1
        call fd_sense
        ret c
        ld a,(dk_res)
        and #E0
        cp #20                   ; seek termine normalement
        jr nz,sk1
        ld a,(dk_res+1)
        ld hl,dk_trk
        cp (hl)
        ret z
sk1:    ld a,#FF
        ld (dk_trk),a
        ld hl,0
        ld de,0
        jp dk_err

; SENSE INTERRUPT STATUS jusqu'a la fin du deplacement (ST0 bit 5)
fd_sense:
        ld a,40                  ; ~40 essais espaces de ~50 ms
        ld (dk_scnt),a
se1:    ld hl,dk_csense
        call fd_cmd
        ret c
        call fd_res
        ret c
        ld a,(dk_nres)
        cp 2
        jr nz,se2
        ld a,(dk_res)
        and #20
        ret nz
se2:    ld de,6000               ; ~40 ms puis nouvel essai
se3:    dec de
        ld a,d
        or e
        jr nz,se3
        ld a,(dk_scnt)
        dec a
        ld (dk_scnt),a
        jr nz,se1
        jp fd_tout

;---------------------------------------------------------------------
; ERREURS
; dk_err  : HL = decalage dans le tampon (#FFFF = FDC bloque), D attendu,
;           E lu ; ST0-ST2 = dk_res. Compte pour le test en cours.
; dk_derr : erreur de donnee pendant la verification (HL = adresse, E
;           attendu, A lu) - preserve tous les registres.
; dk_info : ecart de conformite pour le test en cours.
;---------------------------------------------------------------------
dk_derr:
        push af
        push bc
        push de
        push hl
        ld d,e
        ld e,a
        ld bc,-BUF
        add hl,bc
        call dk_err
        pop hl
        pop de
        pop bc
        pop af
        ret

dk_err: ld (dk_eoff),hl
        ld a,d
        ld (dk_eexp),a
        ld a,e
        ld (dk_erd),a
        ld a,(dk_test)
        ld (dk_etst),a
        ld a,(dk_trk)
        ld (dk_etrk),a
        ld a,(dk_esec)
        ld (dk_esc),a
        ld hl,dk_res
        ld de,dk_est
        ld bc,3
        ldir
        ld hl,dk_errs
        jr dk_cnt

dk_info:
        ld hl,dk_infos
dk_cnt: ld a,(dk_test)           ; compteur 16 bits [test-1]
        dec a
        add a,a
        ld e,a
        ld d,0
        add hl,de
        inc (hl)
        ret nz
        inc hl
        inc (hl)
        ret

;---------------------------------------------------------------------
; AFFICHAGE
;---------------------------------------------------------------------
dk_cur: ld (dk_test),a           ; test en cours (affiche, pour un blocage)
        push af
        ld de,#1500
        call lib_locate
        ld hl,dk_mcur
        call lib_prt
        pop af
        call lib_hex8
        ret

dk_show:
        xor a
        ld (dk_k),a
sw1:    ld hl,dk_errs            ; colonne ERREURS
        ld e,COL_ERR
        call sw_cnt
        ld hl,dk_infos           ; colonne INFO
        ld e,COL_INF
        call sw_cnt
        ld a,(dk_k)
        inc a
        ld (dk_k),a
        cp NT
        jr nz,sw1
        ld de,#1308
        call lib_locate
        ld hl,(dk_pass)
        call lib_hex16
        ld hl,dk_errs            ; erreurs au total ?
        ld b,NT*2
        xor a
sw2:    or (hl)
        inc hl
        djnz sw2
        or a
        ld a,#52                 ; vert
        jr z,sw3
        ld de,#1418              ; derniere erreur
        call lib_locate
        ld a,(dk_etst)
        call lib_hex8
        ld de,#1422
        call lib_locate
        ld a,(dk_etrk)
        call lib_hex8
        ld de,#142B
        call lib_locate
        ld a,(dk_esc)
        call lib_hex8
        ld de,#1431
        call lib_locate
        ld a,(dk_est)
        call lib_hex8
        ld a,' '
        call lib_putc
        ld a,(dk_est+1)
        call lib_hex8
        ld a,' '
        call lib_putc
        ld a,(dk_est+2)
        call lib_hex8
        ld de,#1446
        call lib_locate
        ld hl,(dk_eoff)
        call lib_hex16
        ld a,' '
        call lib_putc
        ld a,(dk_eexp)
        call lib_hex8
        ld a,' '
        call lib_putc
        ld a,(dk_erd)
        call lib_hex8
        ld a,#4C                 ; rouge
sw3:    jp lib_border

sw_cnt:                          ; affiche le compteur [dk_k] de la table HL en colonne E
        push hl
        ld a,(dk_k)
        add a,3
        ld d,a
        call lib_locate
        pop hl
        ld a,(dk_k)
        add a,a
        ld e,a
        ld d,0
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        jp lib_hex16

;---------------------------------------------------------------------
; COMMANDES : longueur, octets (dk_cbuf = parametres variables)
;---------------------------------------------------------------------
dk_cspec: db 3,#03,#A1,#03                ; SPECIFY
dk_crec:  db 2,#07,#00                    ; RECALIBRATE lecteur 0
dk_csense: db 1,#08                       ; SENSE INTERRUPT STATUS
dk_covr:  db 9,#46,#00,20,0,#C1,2,#C1,#2A,#FF ; READ DATA piste 20 #C1 (lente)
dk_cinv:  db 1,#1F

; pistes du test 1 (#FF = fin)
dk_seeks: db 20,41,0,39,1,27,40,2,20,#FF

;---------------------------------------------------------------------
; TABLE DES LECTURES (ENTSZ octets par entree, 0 = fin)
; test, piste, cmd, C, H, R, N, EOT, nb a verifier,
; m0,e0, m1,e1, m2,e2 (ERREUR), i0,f0, i1,f1, i2,f2 (INFO)
;---------------------------------------------------------------------
ENTSZ   equ 21
; lecture normale : erreur si commande invalide, DE/OR/ND/NW/MA, ST2 non nul ;
; INFO si la fin ne se fait pas par EN (ST0 = #40, ST1 bit 7), comme sur un
; vrai CPC (pas de signal TC).
macro RNORM,tst,trk,cc,hh,rr,nn,eot,nv
        db {tst},{trk},#46,{cc},{hh},{rr},{nn},{eot},{nv}
        db #80,0, #37,0, #7F,0,  #C0,#40, #80,#80, 0,0
mend
dk_tab:
        RNORM 2,20,20,0,#C1,2,#C9,9        ; piste entiere (9 secteurs)
        RNORM 2,20,20,0,#C5,2,#C5,1        ; un secteur
        RNORM 3,20,20,0,#C1,2,#C9,9        ; 4 x la piste a vitesse max
        RNORM 3,20,20,0,#C1,2,#C9,9
        RNORM 3,20,20,0,#C1,2,#C9,9
        RNORM 3,20,20,0,#C1,2,#C9,9
        RNORM 4,21,21,0,#C1,2,#CA,10       ; 10 secteurs
        RNORM 5,22,22,0,1,0,1,1            ; 128
        RNORM 5,22,22,0,2,1,2,1            ; 256
        RNORM 5,22,22,0,3,2,3,1            ; 512
        RNORM 5,22,22,0,4,3,4,1            ; 1024
        RNORM 5,22,22,0,5,4,5,1            ; 2048
        RNORM 6,23,23,0,#51,5,#51,1        ; 4096
        RNORM 7,24,#2A,0,#01,2,#01,1       ; C <> piste
        RNORM 7,24,#FF,#FF,#FF,2,#FF,1     ; C, H, R = #FF
        RNORM 7,24,24,1,#C1,2,#C1,1        ; H = 1 sur la face 0
        RNORM 7,24,0,0,0,2,0,1             ; R = 0
        RNORM 7,24,#80,#80,#80,2,#80,1     ; #80
        RNORM 8,25,25,0,#C1,2,#C1,1        ; normal
        ; READ DATA sur secteur efface : donnees lues, ST2 bit 6 (CM) = 1
        db 8,25,#46,25,0,#C2,2,#C2,1, #80,0, #37,0, #40,#40,  0,0, 0,0, 0,0
        ; READ DELETED DATA sur secteur efface : CM = 0
        db 8,25,#4C,25,0,#C4,2,#C4,1, #80,0, #37,0, #40,0,    0,0, 0,0, 0,0
        ; READ DELETED DATA sur secteur normal : CM = 1
        db 8,25,#4C,25,0,#C3,2,#C3,0, #80,0, #37,0, #40,#40,  0,0, 0,0, 0,0
        RNORM 9,26,26,0,#C1,2,#C1,1
        ; erreur CRC des donnees : ST0 = #40, ST1 bit 5 (DE), ST2 bit 5 (DD)
        db 9,26,#46,26,0,#C2,2,#C2,0, #C0,#40, #20,#20, #20,#20,  0,0, 0,0, 0,0
        RNORM 9,26,26,0,#C3,2,#C3,1
        ; secteur inexistant : ST0 = #40, ST1 bit 2 (ND)
        db 10,20,#46,20,0,#D5,2,#D5,0, #C0,#40, #04,#04, 0,0,  0,0, 0,0, 0,0
        ; piste non formatee : ST0 = #40 ; INFO si ST1 bit 0 (MA) absent
        db 11,27,#46,27,0,#C1,2,#C1,0, #C0,#40, 0,0, 0,0,  0,0, #01,#01, 0,0
        RNORM 13,41,41,0,#C1,2,#C9,9       ; piste 41
        RNORM 13,40,40,0,#C1,2,#C9,9       ; piste 40
        db 0

;---------------------------------------------------------------------
; TEXTES : colonne, ligne, texte
;---------------------------------------------------------------------
dk_stab:
        db 0,0,"DSKTEST - ACCES DISQUETTE (FDC 765), DISQUETTE DSKTEST.DSK EN A:",0
        db 0,2,"   TEST                                      ERREURS INFO",0
        db 0,3,"1  RECALIBRAGE ET SEEK (PISTES 0 A 41)       &       &",0
        db 0,4,"2  LECTURE STANDARD 9 x 512 (PISTE 20)       &       &",0
        db 0,5,"3  PISTE ENTIERE x 4, VITESSE MAXIMALE       &       &",0
        db 0,6,"4  10 SECTEURS PAR PISTE (21)                &       &",0
        db 0,7,"5  TAILLES 128 A 2048 OCTETS (22)            &       &",0
        db 0,8,"6  SECTEUR DE 4 KO (23)                      &       &",0
        db 0,9,"7  IDS NON STANDARD (24)                     &       &",0
        db 0,10,"8  SECTEURS EFFACES (25)                     &       &",0
        db 0,11,"9  ERREUR CRC SIMULEE (26)                   &       &",0
        db 0,12,"A  SECTEUR INEXISTANT (20)                   &       &",0
        db 0,13,"B  PISTE NON FORMATEE (27)                   &       &",0
        db 0,14,"C  READ ID (PISTES 20 ET 24)                 &       &",0
        db 0,15,"D  PISTES 40 ET 41                           &       &",0
        db 0,16,"E  OVERRUN (LECTURE TROP LENTE)              &       &",0
        db 0,17,"F  COMMANDE INVALIDE                         &       &",0
        db 0,19,"PASSES &",0
        db 0,20,"DERNIERE ERREUR : TEST &   PISTE &   SECT &  ST &        OFFS/ATT/LU &",0
        db 0,23,"ERREURS = acces faux ou FDC bloque. INFO = ecart a un vrai 765 (voir doc)",0
        db 0,24,"BORD VERT = AUCUNE ERREUR, ROUGE = ERREUR. ECRAN FIGE = PLANTAGE.",0
        db #FF,#FF
dk_mcur: db "EN COURS : TEST &",0
dk_mnofdc: db "PAS DE CONTROLEUR DE DISQUETTE (FDC) : TEST IMPOSSIBLE SUR CETTE MACHINE.",0

;---------------------------------------------------------------------
; VARIABLES
;---------------------------------------------------------------------
dk_vars:
dk_pass:  dw 0
dk_test:  db 0
dk_trk:   db 0
dk_ent:   dw 0
dk_esec:  db 0
dk_tocnt: db 0
dk_scnt:  db 0
dk_tout:  db 0
dk_nres:  db 0
dk_res:   ds 8
dk_tmp:   dw 0
dk_ccnt:  db 0
dk_k:     db 0
dk_cv:    db 0                  ; commande variable : longueur,
dk_cbuf:  ds 9                  ; octets
dk_etst:  db 0
dk_etrk:  db 0
dk_esc:   db 0
dk_est:   ds 3
dk_eoff:  dw 0
dk_eexp:  db 0
dk_erd:   db 0
dk_errs:  ds NT*2
dk_infos: ds NT*2
dk_vend:

        include "cpclib.asm"
dk_fin:
        assert dk_fin < #9000
        save "DSKTEST.BIN",#8000,dk_fin-#8000,AMSDOS
