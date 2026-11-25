; =====================================================================
;  MEMTEST - RAM d'EXTENSION (banques &7FC4..&7FFF, jusqu'a 512 Ko)
;  CPC 464 / 6128 (+ extensions, PicoCPC...) - RASM
;
;  1. Detection : chaque page de 16 Ko (config #C4 + banque*8 + page)
;     est signee ; les pages fantomes (miroirs, absentes) sont ecartees.
;  Puis en boucle, pour CHAQUE page detectee (fenetre #4000-#7FFF) :
;   T1 motifs fixes 00 FF 55 AA 33 CC 0F F0
;   T2 adresse dans adresse (+ numero de page)
;   T3 March C-
;   T4 pseudo-aleatoire (graine = page + passe)
;   T5 aucune ecriture ne doit FUIR dans la RAM de base (#4000-#7FFF en C0)
;      -> verifie apres chaque page (signal RAMDIS / decodage)
;  Puis sur toutes les pages ensemble :
;   T6 croise : toutes les pages remplies, puis toutes relues (alias)
;   T7 COMMUTATION RAPIDE : on change de page a CHAQUE octet (ecriture puis
;      relecture juste apres l'OUT) = ce que font les demos 128 Ko
; Et pour chaque page aussi :
;   T9  RAFALES : PUSH blast 16 Ko + relecture POP (8 motifs), LDI deroules
;   T10 EXECUTION : une routine bourree de prefixes CB/DD/ED/FD est copiee a
;       4 endroits de la page puis EXECUTEE depuis la page (cycles M1),
;       juste apres le changement de page, avec la pile en base puis
;       DANS la page ; resultat compare a la meme routine executee en base
;   T8 modes C1 / C3 : page 3 vue en #C000 doit etre la meme qu'en C7 ;
;      en C3, #4000 doit montrer la page de base 3 (#C000)
;
;  Erreur => arret, bord rouge, details. Passe OK => bord vert.
;  BASIC :  MEMORY &7FFF:LOAD"MEMTEST.BIN",&8000:CALL &8000
; =====================================================================

MX_WIN  equ #4000
MX_MAXP equ 32                  ; 32 pages = 512 Ko
MX_ROUNDS equ 4                 ; tours de martelage par page avant de passer a la suivante

        org #8000

;---------------------------------------------------------------------
; POINT D'ENTREE (CALL &8000 depuis le BASIC)
; - DI : plus aucune interruption (le firmware est abandonne, sortie = reset)
; - pile en #BFFF (zone #9000-#BFFF libre, jamais testee ici)
; - mode 2 + fonte ROM pour l'affichage, ROM basse/haute coupees
; - toute la RAM paginee est vue par la fenetre #4000-#7FFF (configs &C4-&FF)
;---------------------------------------------------------------------
mx_start:
        di
        ld sp,#C000
        call lib_init
        call mx_base
        call lib_cls
        call mx_title
        ld hl,0
        ld (mx_pass),hl

        ; ---- detection ----
        ; 16 emplacements signes par page, de la page 31 vers la page 0
        ; (une page "miroir" est ecrasee ensuite par la vraie page)
        ld a,MX_MAXP-1
;---------------------------------------------------------------------
; DETECTION, etape 1 : on ECRIT les signatures
; On parcourt les pages de 31 vers 0. Si une page n'existe pas et qu'elle est
; un MIROIR d'une page plus basse (cas typique : extension 64 Ko qui ignore les
; bits de banque), son ecriture sera ensuite ECRASEE par celle de la vraie page.
; mx_sigw ecrit 16 signatures (une tous les 1 Ko) : octet = n de page,
; octet suivant = ~page xor k (k = n de l'emplacement 0..15).
;---------------------------------------------------------------------
mx_d1:  ld (mx_pg),a
        call mx_sel
        call mx_sigw
        ld a,(mx_pg)
        sub 1
        jr nc,mx_d1
        call mx_base            ; marque dans la RAM de base aux memes endroits
        ld hl,MX_WIN
        ld b,16
;---------------------------------------------------------------------
; DETECTION, etape 2 : marque dans la RAM de BASE (config C0), aux 16 memes
; emplacements (#5A,#A5). Si aucune extension ne repond, les ecritures "pages"
; sont tombees dans la base et sont maintenant ecrasees -> page absente.
;---------------------------------------------------------------------
mx_d0:  ld (hl),#5A
        inc hl
        ld (hl),#A5
        dec hl
        ld de,#400
        add hl,de
        djnz mx_d0
        ; relecture : 16/16 = OK, 0/16 = absente, sinon = PARTIELLE
        xor a
        ld (mx_pg),a
        ld (mx_n),a
;---------------------------------------------------------------------
; DETECTION, etape 3 : relecture page par page
;   16/16 signatures OK -> page presente (statut 1)
;    0/16              -> page absente  (statut 0)
;   entre les deux     -> page PARTIELLE = vraie panne (statut 2)
; N (mx_n) = derniere page vivante + 1 (logique de contiguite :
; tout ce qui est au-dessus de N est considere comme inexistant).
;---------------------------------------------------------------------
mx_d2:  ld a,(mx_pg)
        call mx_sel
        call mx_sigr
        ld c,0
        or a
        jr z,mx_d3
        ld c,1
        cp 16
        jr z,mx_d2b
        ld c,2
mx_d2b: ld a,(mx_pg)            ; N = derniere page vivante + 1
        inc a
        ld (mx_n),a
mx_d3:  ld a,(mx_pg)
        ld e,a
        ld d,0
        ld hl,mx_stat
        add hl,de
        ld (hl),c
        inc a
        ld (mx_pg),a
        cp MX_MAXP
        jr nz,mx_d2
        call mx_base
        ; N arrondi a la banque de 64 Ko ; tout ce qui est sous N sera teste
        ld a,(mx_n)
        add a,3
        and #FC
        ld (mx_n),a
        jp z,mx_none
        ld hl,mx_pres
        ld b,0
;---------------------------------------------------------------------
; N est arrondi a la banque de 64 Ko (4 pages). Toutes les pages < N sont
; TESTEES (mx_pres=1), y compris les trous ou pages partielles : le test
; donnera alors l'adresse et les bits exacts de la panne.
;---------------------------------------------------------------------
mx_d4:  ld a,b
        ld c,0
        ld e,a
        ld a,(mx_n)
        dec a
        cp e
        jr c,mx_d4b
        ld c,1
mx_d4b: ld (hl),c
        inc hl
        inc b
        ld a,b
        cp MX_MAXP
        jr nz,mx_d4
        ; carte : O = ok, ! = trou ou page partielle (sous N), . = absente
        ld de,#0200
        call lib_locate
        ld hl,mx_mmap
        call lib_prt
        xor a
        ld (mx_anom),a
        ld b,0
;---------------------------------------------------------------------
; Carte des 32 pages : 'O' page OK, '!' anomalie sous N (trou/partielle),
; '.' page absente au-dessus de N.
;---------------------------------------------------------------------
mx_d5:  ld e,b
        ld d,0
        ld hl,mx_stat
        add hl,de
        ld a,(hl)
        cp 1
        ld a,'O'
        jr z,mx_d6
        ld a,(mx_n)
        dec a
        cp b
        ld a,'.'
        jr c,mx_d6
        ld a,1
        ld (mx_anom),a
        ld a,'!'
mx_d6:  call lib_putc
        inc b
        ld a,b
        cp MX_MAXP
        jr nz,mx_d5
        ld de,#0300
        call lib_locate
        ld hl,mx_md1
        call lib_prt
        ld a,(mx_n)
        call lib_hex8
        ld hl,mx_md2
        call lib_prt
        ld a,(mx_n)
        rrca
        rrca
        and #3F
        call lib_hex8
        ld a,(mx_anom)
        or a
        jr z,mx_d7
        ld de,#0400
        call lib_locate
        ld hl,mx_manom
        call lib_prt
mx_d7:  ld a,(mx_n)
        or a
        jr nz,mx_go
mx_none:
        ld de,#0500
        call lib_locate
        ld hl,mx_mnone
        call lib_prt
mx_hang0:
        jr mx_hang0
mx_go:  ld h,8
        call lib_wait

; =====================================================================
;---------------------------------------------------------------------
; BOUCLE PRINCIPALE (une "passe")
; mx_bfill remplit la RAM de BASE #4000-#7FFF (C0) avec un motif de reference
; (L xor H xor #3C). Toute modification de ce motif pendant les tests = FUITE :
; une ecriture destinee a l'extension est AUSSI arrivee dans la RAM interne
; (signal RAMDIS trop tardif, faux contact, mauvais decodage...).
;---------------------------------------------------------------------
mx_loop:
        ld a,#55                ; bord : passe en cours
        call lib_border
        ld de,#0600
        call lib_locate
        ld hl,mx_mpas
        call lib_prt
        ld hl,(mx_pass)
        call lib_hex16
        ld hl,mx_mrun
        call lib_prt
        call mx_bfill           ; motif de reference dans la RAM de base

        ; ---- T1..T5 : MX_ROUNDS tours d'affilee sur chaque page ----
        xor a
        ld (mx_pg),a
;---------------------------------------------------------------------
; TESTS PAGE PAR PAGE : on reste sur la meme page MX_ROUNDS tours d'affilee
; (martelage), puis rafales (T9) et execution (T10), puis page suivante.
;---------------------------------------------------------------------
mx_p1:  call mx_ispres
        jp z,mx_pnext
        xor a
        ld (mx_r),a
;---------------------------------------------------------------------
; UN TOUR sur la page courante :
;  T1 8 motifs fixes : remplir 16 Ko puis tout relire (cellules collees, bus)
;  T2 adresse dans adresse : octet = L xor H xor masque(page,tour)
;     -> detecte lignes d'adresse coupees/collees et alias
;  T3 March C- (fond #00 ou #55 selon le tour) :
;     ^w0 ; ^(r0,w1) ; ^(r1,w0) ; v(r0,w1) ; v(r1,w0) ; r0
;     -> cellules collees, couplages entre cellules voisines, transitions
;  T4 pseudo-aleatoire LFSR 16 bits (graine = page, tour, passe)
;  T5 controle que la RAM de base n'a pas bouge (fuite)
;---------------------------------------------------------------------
mx_r1:  ld de,#0700
        call lib_locate
        ld hl,mx_mpg
        call lib_prt
        ld a,(mx_pg)
        call mx_cfgof
        call lib_hex8
        ld hl,mx_mtour
        call lib_prt
        ld a,(mx_r)
        inc a
        call lib_hex8
        ld a,(mx_pg)
        call mx_sel
        ; T1 motifs fixes
        ld a,1
        ld (mx_t),a
        ld hl,mx_pats
        ld b,8
mx_t1:  push bc
        push hl
        ld e,(hl)
        call mx_setw
        call mx_fill_e
        call mx_setw
        call mx_ver_e
        pop hl
        inc hl
        pop bc
        djnz mx_t1
        ; T2 adresse dans adresse (masque = page, tour)
        ld a,2
        ld (mx_t),a
        call mx_mask
        call mx_t2
        call mx_mask
        cpl
        ld e,a
        call mx_t2
        ; T3 March C- (fond #00 ou #55 selon le tour)
        ld a,3
        ld (mx_t),a
        ld a,(mx_r)
        and 1
        jr z,mx_b0
        ld a,#55
mx_b0:  ld (mx_bg),a
        ld e,a
        call mx_setw
        call mx_fill_e
        ld a,(mx_bg)
        ld e,a
        cpl
        ld d,a
        call mx_setw
        call mx_mr_up
        ld a,(mx_bg)
        ld d,a
        cpl
        ld e,a
        call mx_setw
        call mx_mr_up
        ld a,(mx_bg)
        ld e,a
        cpl
        ld d,a
        call mx_setw
        call mx_mr_dn
        ld a,(mx_bg)
        ld d,a
        cpl
        ld e,a
        call mx_setw
        call mx_mr_dn
        ld a,(mx_bg)
        ld e,a
        call mx_setw
        call mx_ver_e
        ; T4 aleatoire (graine = page, tour, passe)
        ld a,4
        ld (mx_t),a
        call mx_seed
        push de
        call mx_setw
        call mx_fill_rnd
        pop de
        call mx_setw
        call mx_ver_rnd
        ; T5 la RAM de base ne doit pas avoir bouge
        ld a,5
        ld (mx_t),a
        call mx_base
        call mx_bchk
        ld a,(mx_pg)
        call mx_sel
        ld a,(mx_r)
        inc a
        ld (mx_r),a
        cp MX_ROUNDS
        jp nz,mx_r1

        ; ---- T9 RAFALES sur la page : PUSH blast / POP / LDI deroules ----
        ld a,9
        ld (mx_t),a
        ld de,#0700
        call lib_locate
        ld hl,mx_m9
        call lib_prt
        ld a,(mx_pg)
        call mx_sel
        ld hl,mx_wpats
        ld b,8
;---------------------------------------------------------------------
; T9 RAFALES - PUSH blast : SP = #8000, 8192 PUSH deroules remplissent les
; 16 Ko de la page a la vitesse max du Z80 (comme les demos qui effacent
; l'ecran ou copient des sprites par la pile), puis relecture par 8192 POP.
; 8 motifs 16 bits dont #00FF/#FF00 (tous les bits du bus basculent).
;---------------------------------------------------------------------
mx_9a:  push bc
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        push hl
        ld (mx_bw),de
        ex de,hl                ; HL = motif 16 bits
        ld (mx_ssp),sp
        ld sp,#8000             ; 128 x 64 PUSH = 16 Ko dans la page
        ld a,128
mx_9b:
        repeat 64
        push hl
        rend
        dec a
        jp nz,mx_9b
        ld sp,MX_WIN            ; 256 x 32 POP = relecture des 16 Ko
        ld de,(mx_bw)
        xor a
mx_9c:
        repeat 32
        pop hl
        or a
        sbc hl,de
        jp nz,mx_9err
        rend
        dec a
        jp nz,mx_9c
        ld sp,(mx_ssp)
        pop hl
        pop bc
        dec b
        jp nz,mx_9a
        ld a,11                 ; fuite apres PUSH/POP ?
        call mx_leak
        ld a,9                  ; mx_leak a mis mx_t a 11 : retour au test 9
        ld (mx_t),a
        ; LDI deroules : #4000-#5FFF -> #6000-#7FFF dans la meme page
        call mx_seed
        ld hl,MX_WIN
        ld bc,#2000
        call mx_fill_rnd
        ld hl,#4000
        ld de,#6000
        ld a,128                ; 128 x 64 LDI = 8 Ko
;---------------------------------------------------------------------
; T9 RAFALES - LDI deroules : 8 Ko copies de #4000 vers #6000 DANS la page
; (lecture extension + ecriture extension a la suite, 16 cycles par octet),
; puis comparaison octet par octet.
;---------------------------------------------------------------------
mx_9d:
        repeat 64
        ldi
        rend
        dec a
        jp nz,mx_9d
        ld hl,#4000
        ld de,#6000
        ld bc,#2000
mx_9e:  ld a,(de)
        cp (hl)
        jr nz,mx_9f
        inc hl
        inc de
        dec bc
        ld a,b
        or c
        jr nz,mx_9e
        jr mx_9g
mx_9f:  ld c,(hl)               ; attendu
        ex de,hl                ; HL = adresse de la copie
        ld e,c
        jp mx_err
mx_9g:  ld a,12                 ; fuite apres LDI ?
        call mx_leak

        ; ---- T10 EXECUTION DE CODE depuis la page (cycles M1) ----
        ld a,10
        ld (mx_t),a
        ld de,#0700
        call lib_locate
        ld hl,mx_m10
        call lib_prt
        ld a,(mx_pg)
        ld (mx_rxp),a           ; numero de page grave dans la routine
        call mx_sel
        ld hl,mx_xoffs          ; 4 copies de la routine dans la page
        ld b,4
;---------------------------------------------------------------------
; T10 EXECUTION : 4 copies de la routine mx_rx dans la page
; (#4000, #5555, #6AAA, #7F00), avec le numero de page grave dedans
; (mx_rxp) pour etre sur d'executer la BONNE page et pas un miroir.
;---------------------------------------------------------------------
mx_xa:  push bc
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        push hl
        ld hl,mx_rx
        ld bc,mx_rxe-mx_rx
        ldir
        pop hl
        pop bc
        djnz mx_xa
        ld a,13                 ; fuite apres la copie (LDIR) ?
        call mx_leak
        xor a
        ld (mx_xv),a
;---------------------------------------------------------------------
; T10 : deux variantes, 256 graines chacune, sur les 4 copies
;  mx_xv = 0 : on revient en C0, puis OUT vers la page et JP immediat dedans
;             -> le 1er cycle M1 suit directement le changement de page
;  mx_xv = 1 : meme chose avec la PILE dans la page (#7FFE) : CALL/RET,
;             PUSH/POP et EX (SP) se font dans l'extension
; Le resultat est compare a celui de la meme routine executee en RAM de base.
;---------------------------------------------------------------------
mx_xv1: ld a,10
        ld (mx_t),a
        xor a
        ld (mx_xs),a
mx_xb:  call mx_xseed           ; reference : la meme routine executee en base
        call mx_rx
        ld (mx_xref),hl
        ld hl,mx_xoffs
        ld b,4
mx_xc:  push bc
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        push hl
        ld (mx_xadr),de
        ld a,(mx_xv)
        or a
        jr nz,mx_xvb
        ; a) on revient en C0, puis OUT vers la page et saut IMMEDIAT dedans
        call mx_base
        ld a,(mx_pg)
        call mx_cfgof
        ld (mx_cf),a
        call mx_xseed
        ld hl,(mx_xadr)
        ld a,(mx_cf)
        call mx_xjump
        call mx_xchk
        jr mx_xvn
        ; b) PILE dans la page d'extension
mx_xvb: ld a,(mx_pg)
        call mx_sel
        call mx_xseed
        ld hl,(mx_xadr)
        ld (mx_ssp),sp
        ld sp,#7FFE
        ld a,(mx_cf)
        call mx_xjump
        ld sp,(mx_ssp)
        call mx_xchk
mx_xvn: pop hl
        pop bc
        dec b
        jp nz,mx_xc
        ld a,(mx_xs)
        inc a
        ld (mx_xs),a
        jp nz,mx_xb             ; 256 graines
        ld a,(mx_xv)            ; fuite apres execution (14 = pile en base, 15 = pile en page)
        add a,14
        call mx_leak
        ld a,(mx_pg)
        call mx_sel
        ld a,(mx_xv)
        inc a
        ld (mx_xv),a
        cp 2
        jp nz,mx_xv1
mx_pnext:
        ld a,(mx_pg)
        inc a
        ld (mx_pg),a
        cp MX_MAXP
        jp nz,mx_p1

        ; ---- T6 croise : tout remplir, puis tout relire ----
        ld a,6
        ld (mx_t),a
        xor a
        ld (mx_pg),a
;---------------------------------------------------------------------
; T6 CROISE : toutes les pages remplies (LFSR propre a chaque page), PUIS
; toutes relues. Une ecriture qui atterrit dans une autre page est detectee.
;---------------------------------------------------------------------
mx_c1:  call mx_ispres
        jr z,mx_c2
        ld a,(mx_pg)
        call mx_sel
        call mx_seed
        call mx_setw
        call mx_fill_rnd
mx_c2:  ld a,(mx_pg)
        inc a
        ld (mx_pg),a
        cp MX_MAXP
        jr nz,mx_c1
        xor a
        ld (mx_pg),a
mx_c3:  call mx_ispres
        jr z,mx_c4
        ld a,(mx_pg)
        call mx_sel
        call mx_seed
        call mx_setw
        call mx_ver_rnd
mx_c4:  ld a,(mx_pg)
        inc a
        ld (mx_pg),a
        cp MX_MAXP
        jr nz,mx_c3
        call mx_bleak

        ; ---- T7 commutation rapide : une page differente a chaque acces ----
        ld a,7
        ld (mx_t),a
        ld de,#0700
        call lib_locate
        ld hl,mx_msw
        call lib_prt
        ld hl,MX_WIN
;---------------------------------------------------------------------
; T7 COMMUTATION RAPIDE : pour chaque octet de la fenetre, on passe par
; toutes les pages (OUT puis ecriture immediate), puis meme chose en relecture
; (OUT puis lecture immediate). Teste le temps de reaction au changement de page.
;---------------------------------------------------------------------
mx_s1:  xor a
        ld (mx_pg),a
mx_s2:  call mx_ispres
        jr z,mx_s3
        ld a,(mx_pg)
        call mx_selq            ; OUT puis ecriture immediate
        ld a,l
        xor h
        ld e,a
        ld a,(mx_pg)
        add a,e
        ld (hl),a
mx_s3:  ld a,(mx_pg)
        inc a
        ld (mx_pg),a
        cp MX_MAXP
        jr nz,mx_s2
        inc hl
        ld a,h
        cp #80
        jr nz,mx_s1
        ld hl,MX_WIN            ; relecture entrelacee
mx_s4:  xor a
        ld (mx_pg),a
mx_s5:  call mx_ispres
        jr z,mx_s6
        ld a,(mx_pg)
        call mx_selq            ; OUT puis lecture immediate
        ld a,l
        xor h
        ld e,a
        ld a,(mx_pg)
        add a,e
        ld e,a
        ld a,(hl)
        cp e
        jp nz,mx_err
mx_s6:  ld a,(mx_pg)
        inc a
        ld (mx_pg),a
        cp MX_MAXP
        jr nz,mx_s5
        inc hl
        ld a,h
        cp #80
        jr nz,mx_s4
        call mx_bleak

        ; ---- T8 modes C1 / C3 (premiere banque complete uniquement) ----
        ld a,(mx_pres+3)
        or a
        jp z,mx_pend
        ld a,8
        ld (mx_t),a
        ld a,3                  ; page 3 en #4000 (C7) : motif
        ld (mx_pg),a
        call mx_sel
        ld hl,MX_WIN
;---------------------------------------------------------------------
; T8 MODES C1 / C3 (premiere banque de 64 Ko uniquement)
;  C1 = 0,1,2,7 et C3 = 0,3,2,7 : la page 7 (= page 3 de l'extension, vue en
;  #4000 en C7) doit apparaitre en #C000. En C3, #4000 doit montrer la page
;  de base 3 (#C000 en C0 = l'ecran). C2 n'est pas teste (il remplacerait
;  tout l'espace, code compris).
;---------------------------------------------------------------------
mx_k1:  ld a,l
        xor h
        xor #77
        ld (hl),a
        inc hl
        ld a,h
        cp #80
        jr nz,mx_k1
        ld a,#C1                ; C1 : la meme page doit etre en #C000
        call mx_cfg
        call mx_k8
        ld a,#C3                ; C3 : idem
        call mx_cfg
        call mx_k8
        ; C1 : ecrire en #C000, relire en C7 (#4000)
        ld a,#C1
        call mx_cfg
        ld hl,#C000
mx_k2:  ld a,l
        xor h
        xor #E1
        ld (hl),a
        inc hl
        ld a,h
        or a
        jr nz,mx_k2
        ld a,3
        call mx_sel
        ld hl,MX_WIN
mx_k3:  ld a,h
        add a,#80               ; adresse vue en C1
        xor l
        xor #E1
        ld e,a
        ld a,(hl)
        cp e
        jp nz,mx_err
        inc hl
        ld a,h
        cp #80
        jr nz,mx_k3
        ; C3 : #4000 doit montrer la RAM de base #C000 (l'ecran)
        ld a,#C3
        call mx_cfg
        ld hl,MX_WIN
        ld de,#C000
mx_k4:  ld a,#C0
        call mx_cfg
        ld a,(de)
        ld c,a                  ; octet de base (ecran)
        ld a,#C3
        call mx_cfg
        ld a,(hl)
        cp c
        jr z,mx_k5
        ld e,c
        jp mx_err
mx_k5:  inc hl
        inc de
        ld a,h
        cp #80
        jr nz,mx_k4
        call mx_bleak

;---------------------------------------------------------------------
; Fin de passe : bord vert ~1 s, puis on recommence (graines differentes).
;---------------------------------------------------------------------
mx_pend:                        ; passe terminee
        call mx_base
        ld hl,(mx_pass)
        inc hl
        ld (mx_pass),hl
        ld de,#0700
        call lib_locate
        ld hl,mx_mok
        call lib_prt
        ld a,#52
        call lib_border
        ld h,3
        call lib_wait
        jp mx_loop

; verifie #C000-#FFFF (config courante C1/C3) contre le motif page 3
mx_k8:  ld hl,#C000
mx_k81: ld a,h
        sub #80
        xor l
        xor #77
        ld e,a
        ld a,(hl)
        cp e
        jp nz,mx_err
        inc hl
        ld a,h
        or a
        jr nz,mx_k81
        ret

; =====================================================================
mx_t2:  push de
        call mx_setw
        call mx_fill_adr
        pop de
        call mx_setw
        jp mx_ver_adr

;---------------------------------------------------------------------
; Masque du test d'adresse : page xor (tour * #40).
;---------------------------------------------------------------------
mx_mask:                        ; A = E = page xor (tour * #40)
        ld a,(mx_r)
        rrca
        rrca
        ld e,a
        ld a,(mx_pg)
        xor e
        ld e,a
        ret

;---------------------------------------------------------------------
; Ecrit 16 signatures dans la page courante (une tous les 1 Ko).
;---------------------------------------------------------------------
mx_sigw:                        ; 16 signatures (page, ~page xor k) tous les 1 Ko
        ld hl,MX_WIN
        ld b,16
        ld c,0
mx_sw1: ld a,(mx_pg)
        ld (hl),a
        inc hl
        cpl
        xor c
        ld (hl),a
        dec hl
        ld de,#400
        add hl,de
        inc c
        djnz mx_sw1
        ret

;---------------------------------------------------------------------
; Compte les signatures correctes de la page courante (0 a 16).
;---------------------------------------------------------------------
mx_sigr:                        ; A = nombre de signatures correctes (0..16)
        xor a
        ld (mx_cnt),a
        ld hl,MX_WIN
        ld b,16
        ld c,0
mx_sr1: ld a,(mx_pg)
        cp (hl)
        jr nz,mx_sr2
        cpl
        xor c
        inc hl
        cp (hl)
        dec hl
        jr nz,mx_sr2
        ld a,(mx_cnt)
        inc a
        ld (mx_cnt),a
mx_sr2: ld de,#400
        add hl,de
        inc c
        djnz mx_sr1
        ld a,(mx_cnt)
        ret

; ---- T9 : erreur dans la relecture POP ----
;---------------------------------------------------------------------
; Erreur dans la relecture POP : SP pointe juste apres le mot fautif.
; On determine quel octet (bas ou haut) est faux et on va a mx_err.
;---------------------------------------------------------------------
mx_9err:
        add hl,de               ; HL = mot lu
        ld (mx_tmp),hl
        ld hl,0
        add hl,sp
        dec hl
        dec hl                  ; adresse du mot fautif
        ld a,(mx_tmp)
        cp e
        jp nz,mx_err
        inc hl
        ld a,(mx_tmp+1)
        ld e,d
        jp mx_err

; ---- T10 ----
;---------------------------------------------------------------------
; A = config : OUT &7Fxx puis JP (HL) sans aucune instruction entre les deux.
;---------------------------------------------------------------------
mx_xjump:                       ; A = config : OUT puis saut immediat en (HL)
        ld b,#7F
        out (c),a
        jp (hl)

mx_xseed:                       ; DE = graine
        ld a,(mx_xs)
        ld d,a
        xor #C3
        ld e,a
        ld a,d
        xor #A5
        ld d,a
        ret

;---------------------------------------------------------------------
; Compare HL (resultat execute dans la page) a la reference (mx_xref).
;---------------------------------------------------------------------
mx_xchk:                        ; HL = resultat, doit valoir (mx_xref)
        ld de,(mx_xref)
        ld a,l
        cp e
        jr nz,mx_xe
        ld a,h
        cp d
        ret z
        ld e,d
mx_xe:  ld hl,(mx_xadr)         ; adresse de la copie executee
        jp mx_err

; routine RELOGEABLE (JR/DJNZ seulement), riche en prefixes CB/DD/ED/FD,
; avec pile (PUSH/POP/EX (SP)). Entree DE = graine, sortie HL.
;---------------------------------------------------------------------
; ROUTINE DE TEST EXECUTEE DEPUIS L'EXTENSION
; - RELOGEABLE : uniquement JR/DJNZ, aucune adresse absolue
; - riche en prefixes CB, DD (IX), ED (ADC/SBC HL, NEG), FD (IY) : beaucoup de
;   cycles M1 et d'octets d'instruction lus dans la page
; - utilise la pile (PUSH/POP, EX (SP),HL, EX (SP),IX)
; Entree : DE = graine. Sortie : HL = resultat. Le 1er octet apres "ld a," est
; remplace par le numero de page.
;---------------------------------------------------------------------
mx_rx:  ld a,0
mx_rxp  equ mx_rx+1
        ld b,24
mx_rx1: ld h,d
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
        jr z,mx_rx2
        inc a
mx_rx2: add hl,de
        ex de,hl
        push ix
        pop hl
        add a,l
        djnz mx_rx1
        push iy
        pop hl
        add hl,de
        xor h
        ld h,a
        ret
mx_rxe:

;---------------------------------------------------------------------
; Adresses des 4 copies de la routine dans la page (fin < #7FE0 : la pile
; de la variante "pile dans la page" est en #7FF8-#7FFE).
;---------------------------------------------------------------------
mx_xoffs: dw #4000,#5555,#6AAA,#7F00
mx_wpats: dw #0000,#FFFF,#00FF,#FF00,#5555,#AAAA,#33CC,#C33C

mx_setw: ld hl,MX_WIN
        ld bc,#4000
        ret

;---------------------------------------------------------------------
; Graine LFSR (jamais nulle) dependant de la passe, de la page et du tour.
;---------------------------------------------------------------------
mx_seed:                        ; DE = graine (page, passe), jamais nulle
        ld hl,(mx_pass)
        ld a,(mx_pg)
        xor h
        ld h,a
        ld a,(mx_r)
        xor l
        ld l,a
        ld de,#ACE1
        add hl,de
        ld a,h
        or l
        jr nz,mx_sd1
        inc l
mx_sd1: ex de,hl
        ret

;---------------------------------------------------------------------
; Z si la page mx_pg n'est pas a tester. Preserve HL et DE.
;---------------------------------------------------------------------
mx_ispres:                      ; NZ si la page (mx_pg) existe (preserve HL, DE)
        push hl
        push de
        ld a,(mx_pg)
        ld e,a
        ld d,0
        ld hl,mx_pres
        add hl,de
        ld a,(hl)
        pop de
        pop hl
        or a
        ret

;---------------------------------------------------------------------
; Page (0-31) -> valeur de config : #C4 + banque*8 + (page and 3)
; banque = page/4 (bits 3-5), page dans la banque = bits 0-1 (configs C4-C7).
;---------------------------------------------------------------------
mx_cfgof:                       ; A = page -> A = valeur de config
        push bc
        ld b,a
        and #1C
        add a,a
        ld c,a
        ld a,b
        and 3
        or c
        or #C4
        pop bc
        ret

;---------------------------------------------------------------------
; Selectionne la page A en #4000 (OUT &7F00). mx_cfg : config brute.
; La derniere config envoyee est memorisee dans mx_cf (affichee en cas d'erreur).
;---------------------------------------------------------------------
mx_sel: call mx_cfgof           ; selectionne la page A en #4000
mx_cfg: push bc                 ; A = config brute
        ld (mx_cf),a
        ld bc,#7F00
        out (c),a
        pop bc
        ret

;---------------------------------------------------------------------
; Version rapide de mx_sel pour T7 (preserve HL et DE, detruit B).
;---------------------------------------------------------------------
mx_selq:                        ; version rapide, preserve HL et DE
        call mx_cfgof
        ld (mx_cf),a
        ld b,#7F
        out (c),a
        ret

;---------------------------------------------------------------------
; Retour en config C0 (64 Ko de base seuls).
;---------------------------------------------------------------------
mx_base:
        ld a,#C0
        jr mx_cfg

;---------------------------------------------------------------------
; Remplit la RAM de base #4000-#7FFF avec le motif de reference.
;---------------------------------------------------------------------
mx_bfill:                       ; RAM de base #4000-#7FFF (C0)
        call mx_base
        ld hl,MX_WIN
mx_bf1: ld a,l
        xor h
        xor #3C
        ld (hl),a
        inc hl
        ld a,h
        cp #80
        jr nz,mx_bf1
        ret

;---------------------------------------------------------------------
; A = numero de test : controle la RAM de base (fuite) puis re-selectionne
; la page en cours. Numeros : 5 apres les tours, 11 PUSH/POP, 12 LDI,
; 13 copie de la routine, 14 execution pile en base, 15 pile en page.
;---------------------------------------------------------------------
mx_leak:                        ; A = numero de test : controle la RAM de base
        ld (mx_t),a             ; puis re-selectionne la page en cours
        call mx_base
        call mx_bchk
        ld a,(mx_pg)
        jp mx_sel

;---------------------------------------------------------------------
; Controle de fuite apres T6/T7/T8 : erreur signalee comme test 5 (FUITE)
; et non comme le test qui precede. Reste en C0.
;---------------------------------------------------------------------
mx_bleak:
        ld a,5
        ld (mx_t),a
        call mx_base
        ; (enchaine sur mx_bchk)

;---------------------------------------------------------------------
; Verifie le motif de reference dans la RAM de base. Erreur = FUITE.
;---------------------------------------------------------------------
mx_bchk:                        ; erreur = fuite d'ecriture dans la base
        ld hl,MX_WIN
mx_bc1: ld a,l
        xor h
        xor #3C
        ld e,a
        ld a,(hl)
        cp e
        jp nz,mx_err
        inc hl
        ld a,h
        cp #80
        jr nz,mx_bc1
        ret

; ---- routines de test (HL debut, BC longueur) -> mx_err ----
;---------------------------------------------------------------------
; ROUTINES ELEMENTAIRES : HL = debut, BC = longueur.
; Convention d'erreur : jp mx_err avec HL = adresse, A = lu, E = attendu.
;---------------------------------------------------------------------
mx_fill_e:
        ld (hl),e
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,mx_fill_e
        ret
mx_ver_e:
        ld a,(hl)
        cp e
        jp nz,mx_err
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,mx_ver_e
        ret
mx_fill_adr:
        ld a,l
        xor h
        xor e
        ld (hl),a
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,mx_fill_adr
        ret
mx_ver_adr:
        ld a,l
        xor h
        xor e
        ld d,a
        ld a,(hl)
        cp d
        jr nz,mx_vae
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,mx_ver_adr
        ret
mx_vae: ld e,d
        jp mx_err
;---------------------------------------------------------------------
; Element March montant : lit et verifie E, ecrit D.
;---------------------------------------------------------------------
mx_mr_up:
        ld a,(hl)
        cp e
        jp nz,mx_err
        ld (hl),d
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,mx_mr_up
        ret
;---------------------------------------------------------------------
; Element March descendant (de HL+BC-1 vers HL).
;---------------------------------------------------------------------
mx_mr_dn:
        add hl,bc
        dec hl
mx_md:  ld a,(hl)
        cp e
        jp nz,mx_err
        ld (hl),d
        dec hl
        dec bc
        ld a,b
        or c
        jr nz,mx_md
        ret
;---------------------------------------------------------------------
; LFSR 16 bits de Galois (polynome #B400) : DE = etat, octet ecrit = E.
;---------------------------------------------------------------------
mx_fill_rnd:
        srl d
        rr e
        jr nc,mx_fr
        ld a,d
        xor #B4
        ld d,a
mx_fr:  ld (hl),e
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,mx_fill_rnd
        ret
mx_ver_rnd:
        srl d
        rr e
        jr nc,mx_vr
        ld a,d
        xor #B4
        ld d,a
mx_vr:  ld a,(hl)
        cp e
        jp nz,mx_err
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,mx_ver_rnd
        ret

; =====================================================================
; ERREUR : HL = adresse, A = lu, E = attendu
;---------------------------------------------------------------------
; ECRAN D'ERREUR : on repasse IMPERATIVEMENT en C0 avant d'afficher
; (sinon, en C1/C3, l'ecran #C000 serait une page d'extension).
; Affiche : n du test, config &7F au moment de l'erreur, adresse, attendu,
; lu, XOR (bits fautifs), page testee, passe. Puis arret (reset pour sortir).
;---------------------------------------------------------------------
mx_err: ld sp,#C000
        ld (mx_ea),hl
        ld (mx_el),a
        ld a,e
        ld (mx_ee),a
        ld a,(mx_cf)            ; config au moment de l'erreur
        ld (mx_ec),a
        call mx_base            ; IMPERATIF avant d'afficher
        ld a,#4C
        call lib_border
        call lib_cls
        call mx_title
        ld de,#0200
        call lib_locate
        ld hl,mx_me0
        call lib_prt
        ld a,(mx_t)
        call lib_hex8
        ld a,' '
        call lib_putc
        ld a,(mx_t)
        dec a
        add a,a
        ld e,a
        ld d,0
        ld hl,mx_tn
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        call lib_prt
        ld de,#0400
        call lib_locate
        ld hl,mx_me1
        call lib_prt
        ld a,(mx_ec)
        call lib_hex8
        ld hl,mx_me2
        call lib_prt
        ld hl,(mx_ea)
        call lib_hex16
        ld de,#0500
        call lib_locate
        ld hl,mx_me3
        call lib_prt
        ld a,(mx_ee)
        call lib_hex8
        ld hl,mx_me4
        call lib_prt
        ld a,(mx_el)
        call lib_hex8
        ld hl,mx_me5
        call lib_prt
        ld a,(mx_el)
        ld b,a
        ld a,(mx_ee)
        xor b
        call lib_hex8
        ld de,#0600
        call lib_locate
        ld hl,mx_mpt
        call lib_prt
        ld a,(mx_pg)
        call mx_cfgof
        call lib_hex8
        ld de,#0700
        call lib_locate
        ld hl,mx_mpas
        call lib_prt
        ld hl,(mx_pass)
        call lib_hex16
mx_hang:
        jr mx_hang

mx_title:
        ld de,#0000
        call lib_locate
        ld hl,mx_m0
        jp lib_prt

; =====================================================================
mx_pats: db #00,#FF,#55,#AA,#33,#CC,#0F,#F0
mx_tn:   dw mx_n1,mx_n2,mx_n3,mx_n4,mx_n5,mx_n6,mx_n7,mx_n8,mx_n9,mx_n10
         dw mx_n11,mx_n12,mx_n13,mx_n14,mx_n15
mx_n1:   db "(motifs fixes)",0
mx_n2:   db "(adresse/adresse)",0
mx_n3:   db "(March C-)",0
mx_n4:   db "(aleatoire)",0
mx_n5:   db "(FUITE dans la RAM de base #4000-#7FFF)",0
mx_n6:   db "(croise toutes pages / alias)",0
mx_n7:   db "(commutation rapide de page)",0
mx_n8:   db "(modes C1/C3)",0
mx_n9:   db "(RAFALES PUSH/POP/LDI dans la page)",0
mx_n10:  db "(EXECUTION de code depuis la page, adresse = copie)",0
mx_n11:  db "(FUITE en base apres rafales PUSH/POP)",0
mx_n12:  db "(FUITE en base apres LDI deroules)",0
mx_n13:  db "(FUITE en base apres copie LDIR de la routine)",0
mx_n14:  db "(FUITE en base apres execution, pile en base)",0
mx_n15:  db "(FUITE en base apres execution, pile en page)",0
mx_mpt:  db "Page testee : config &",0
mx_m9:   db "Rafales PUSH/POP/LDI...         ",0
mx_m10:  db "Execution de code (M1)...       ",0

mx_m0:   db "MEMTEST - RAM d'extension (banques &7FC4-&7FFF, 512 Ko max)",0
mx_mmap: db "Pages 0-31 : ",0
mx_md1:  db "Pages testees : &",0
mx_md2:  db "   = banques de 64 Ko : &",0
mx_manom: db "ANOMALIE : trou ou page partielle (!) -> testee quand meme pour detail",0
mx_mtour: db "  tour &",0
mx_mnone: db "Aucune RAM d'extension detectee.",0
mx_mpas: db "Passe : &",0
mx_mrun: db "  en cours...       ",0
mx_mpg:  db "Page config &",0
mx_msw:  db "Commutation rapide + C1/C3...",0
mx_mok:  db "Passe OK                     ",0
mx_me0:  db "*** ERREUR - TEST ",0
mx_me1:  db "Config &7F : &",0
mx_me2:  db "   adresse : &",0
mx_me3:  db "Attendu : &",0
mx_me4:  db "   lu : &",0
mx_me5:  db "   XOR : &",0

;---------------------------------------------------------------------
; VARIABLES
;---------------------------------------------------------------------
mx_pass: dw 0
mx_pg:   db 0
mx_n:    db 0
mx_t:    db 0
mx_cf:   db #C0
mx_ec:   db 0
mx_ea:   dw 0
mx_ee:   db 0
mx_el:   db 0
mx_pres: ds MX_MAXP
mx_stat: ds MX_MAXP
mx_r:    db 0
mx_bg:   db 0
mx_cnt:  db 0
mx_anom: db 0
mx_bw:   dw 0
mx_ssp:  dw 0
mx_tmp:  dw 0
mx_xs:   db 0
mx_xv:   db 0
mx_xref: dw 0
mx_xadr: dw 0

        include "cpclib.asm"
mx_fin:
        assert mx_fin < #BE00         ; pile en #BFFF et dessous
        assert mx_rxe-mx_rx < #E0
        save "MEMTEST.BIN",#8000,mx_fin-#8000,AMSDOS
