; =====================================================================
;  cpclib.asm - routines communes aux tests CPC 464 (RASM)
;  A inclure A LA FIN du programme (pas d'ORG ici) :  include "cpclib.asm"
;  Affichage mode 2 (80 colonnes) avec la fonte de la ROM basse (#3800)
; =====================================================================

LIB_SCR equ #C000

; mode 2, ROM basse et haute OFF, encres 0 noir / 1 blanc, ecran en #C000
;---------------------------------------------------------------------
; Mode 2 (#8E = ROM basse et haute coupees), encres, CRTC R12/R13 = ecran
; en #C000 sans decalage.
;---------------------------------------------------------------------
lib_init:
        ld bc,#7F8E
        out (c),c
        call lib_inks
        ld bc,#BC0C
        out (c),c
        ld bc,#BD30
        out (c),c
        ld bc,#BC0D
        out (c),c
        ld bc,#BD00
        out (c),c
        ret

lib_inks:                       ; encre 0 = noir, encre 1 = blanc, bord noir
        ld bc,#7F00
        out (c),c
        ld a,#54
        out (c),a
        ld a,1
        out (c),a
        ld a,#4B
        out (c),a
        ld a,#54
        jp lib_border

lib_border:                     ; A = couleur hardware (#40-#5F)
        ld bc,#7F10
        out (c),c
        out (c),a
        ret

lib_cls:
        ld hl,LIB_SCR
        ld de,LIB_SCR+1
        ld bc,#3FFF
        ld (hl),0
        ldir
        ret

lib_locate:                     ; D = ligne (0-24), E = colonne (0-79)
        ld hl,LIB_SCR
        ld a,d
        or a
        jr z,lib_lc2
        ld bc,80
lib_lc1:
        add hl,bc
        dec a
        jr nz,lib_lc1
lib_lc2:
        ld d,0
        add hl,de
        ld (lib_curs),hl
        ret

lib_prt:                        ; HL = chaine terminee par 0
        ld a,(hl)
        or a
        ret z
        call lib_putc
        inc hl
        jr lib_prt

;---------------------------------------------------------------------
; Affiche le caractere A a la position lib_curs (mode 2 : 1 octet = 8
; pixels). La fonte est lue dans la ROM basse (#3800 + 8 x code) : ROM basse
; activee le temps de 8 lectures, avec DI. Les interruptions sont reactivees
; seulement si lib_iff = 1 (on n'utilise pas LD A,I : sur Z80 NMOS, une
; interruption pendant LD A,I peut renvoyer IFF2 = 0 a tort).
;---------------------------------------------------------------------
lib_putc:                       ; A = caractere (preserve HL, DE, BC)
        push hl
        push de
        push bc
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,#3800
        add hl,de
        di                      ; (pas de LD A,I : bug du Z80 NMOS)
        ld de,(lib_curs)
        ld bc,#7F8A             ; ROM basse ON le temps de lire la fonte
        out (c),c
        ld b,8
lib_pc1:
        ld a,(hl)
        ld (de),a
        inc hl
        ld a,d
        add a,8
        ld d,a
        djnz lib_pc1
        ld bc,#7F8E             ; ROM basse OFF
        out (c),c
        ld a,(lib_iff)
        or a
        jr z,lib_pc2
        ei
lib_pc2:
        ld hl,(lib_curs)
        inc hl
        ld (lib_curs),hl
        pop bc
        pop de
        pop hl
        ret

lib_hex16:                      ; HL en hexa
        ld a,h
        call lib_hex8
        ld a,l
lib_hex8:
        push af
        rrca
        rrca
        rrca
        rrca
        call lib_hexn
        pop af
lib_hexn:
        and #0F
        add a,'0'
        cp '9'+1
        jr c,lib_hx1
        add a,7
lib_hx1:
        jp lib_putc

;---------------------------------------------------------------------
; Attente : H x ~0,45 s.
;---------------------------------------------------------------------
lib_wait:                       ; H x ~0,45 s (detruit A, DE, H)
lib_wt1:
        ld de,0
lib_wt2:
        dec de
        ld a,d
        or e
        jr nz,lib_wt2
        dec h
        jr nz,lib_wt1
        ret

; ---- AY-3-8912 via le PPI (lib_pcb = bits du port C a conserver, ex. moteur) ----
;---------------------------------------------------------------------
; Ecriture AY : port A du PPI = n de registre, port C = #C0 (latch),
; puis port A = valeur, port C = #80 (ecriture). lib_pcb conserve les autres
; bits du port C (moteur K7).
;---------------------------------------------------------------------
lib_psgw:                       ; A = registre, C = valeur
        ld b,#F4
        out (c),a
        ld b,#F6
        ld a,(lib_pcb)
        or #C0
        out (c),a
        ld a,(lib_pcb)
        out (c),a
        ld b,#F4
        out (c),c
        ld b,#F6
        ld a,(lib_pcb)
        or #80
        out (c),a
        ld a,(lib_pcb)
        out (c),a
        ret

;---------------------------------------------------------------------
; Lecture AY : latch du registre, port A du PPI passe en ENTREE (#92),
; port C = #40 (lecture), lecture du port A, puis retour en sortie (#82).
;---------------------------------------------------------------------
lib_psgr:                       ; A = registre -> A = valeur lue
        ld b,#F4
        out (c),a
        ld b,#F6
        ld a,(lib_pcb)
        or #C0
        out (c),a
        ld a,(lib_pcb)
        out (c),a
        ld bc,#F792             ; port A en entree
        out (c),c
        ld b,#F6
        ld a,(lib_pcb)
        or #40
        out (c),a
        ld b,#F4
        in a,(c)
        push af
        ld bc,#F782             ; port A en sortie
        out (c),c
        ld b,#F6
        ld a,(lib_pcb)
        out (c),a
        pop af
        ret

lib_silence:                    ; coupe les 3 voies
        ld a,7
        ld c,#3F
        call lib_psgw
        ld a,8
        ld c,0
        call lib_psgw
        ld a,9
        ld c,0
        call lib_psgw
        ld a,10
        ld c,0
        jp lib_psgw

lib_curs: dw LIB_SCR
lib_pcb:  db 0
lib_iff:  db 0                  ; 1 = le programme tourne avec EI
