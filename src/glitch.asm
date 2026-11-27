; =====================================================================
;  GLITCH v4 - recherche de rebonds (impulsions parasites) sur toutes les
;  entrees du RP2350B de la PicoCPC, pendant que le CPC travaille.
;  CPC 464 / 6128 / Plus + PicoCPC avec le firmware de test pioglitch4.
;  RASM, a assembler avec cpclib.asm.
;
;  Le firmware observe GPIO0-31 avec un analyseur PIO (1 echantillon toutes
;  les 11,1 ns) et GPIO32-47 par lecture logicielle (~3-10 ns). Pour chaque
;  broche il compte :
;    n1  = impulsions d'1 echantillon  (la broche change puis revient)
;    n2  = impulsions de 2 echantillons
;  Bus multiplexe : A8-A15, A0-A7 (non mesurables : 11-22 ns par cycle) et
;  D0-D7 separes ; D0-D7 separes aussi selon qui pilote les donnees :
;  Dcpc = le CPC, Dpico = la PicoCPC (ROMDIS ou RAMDIS leve).
;  RFSH/IORQ/MREQ/RD-WR : creux et pics, position par rapport au dernier
;  changement du multiplexeur, et 24 echantillons autour du 1er rebond.
;  D0-D7 : position depuis le debut (Dpico) / la fin (Dcpc) du cycle servi,
;  et depuis le debut du cycle Z80 (MREQ ou IORQ actif).
;
;  Chaque passe : 11 activites x 8 (PUSH, LDI, LD (HL),A, OUT + ecriture,
;  en page &C4 puis en RAM de base ; lecture de la ROM basse ; IN ; NOP).
;  Pour chacune : &80+n (activite), &E8 arme, ~1-3 ms d'activite, &E9
;  analyse les 91 us precedents. Les compteurs s'accumulent.
;  Une seule page, reecrite sur place a chaque passe. Les GPIO non cablees
;  n'apparaissent que si elles rebondissent.
;
;  BASIC :  MEMORY &7FFF:LOAD"GLITCH.BIN",&8000:CALL &8000
; =====================================================================

CFG     equ #C4                 ; page d'extension
REPS    equ 8                   ; repetitions de chaque activite par passe
NACT    equ 11
NCH     equ 72
RES_LEN equ 1012                 ; octets du resultat (&EB)
O_CH    equ 72                  ; offsets dans le resultat (voir pio/glitch.c)
O_DIR   equ 504
O_HIST  equ 520
O_ACT   equ 568
O_SNAP  equ 792
O_TOT   equ 888
O_HSRV  equ 900
O_HCYC  equ 948

        org #8000

start:
        di
        ld sp,#C000
        call lib_init
        call header
        ; ---- firmware present ?
        ld a,#EA                ; compteurs a zero
        call pico_cmd
        or a
        jr z,go
        ld de,#0300
        call lib_locate
        ld hl,m_nopico
        cp #FF
        jr z,bad
        ld hl,m_nofw
        cp 3
        jr z,bad
        ld hl,m_err
bad:    push af
        call lib_prt
        pop af
        call lib_hex8
        jr $

go:     ld hl,0
        ld (pass),hl
        ld (nover),hl
        ld (nshort),hl

;----------------------------------------------------------------------
; Une passe : NACT activites x REPS
;----------------------------------------------------------------------
p_loop: ld hl,(pass)
        inc hl
        ld (pass),hl
        xor a
        ld (act),a
a_loop: ld de,#001B
        call lib_locate
        ld hl,m_pass
        call lib_prt
        ld hl,(pass)
        call lib_hex16
        ld hl,m_act
        call lib_prt
        ld a,(act)
        call act_name
        call lib_prt
        ld a,(act)
        or #80                  ; activite en cours pour le firmware
        call pico_cmd
        ld a,REPS
        ld (rep),a
r_loop: call one
        ld hl,rep
        dec (hl)
        jr nz,r_loop
        ld hl,act
        inc (hl)
        ld a,(hl)
        cp NACT
        jr c,a_loop
        call fetch
        jr c,f_bad
        call show
        jp p_loop
f_bad:  ld de,#0300
        call lib_locate
        ld hl,m_fbad
        call lib_prt
        jr $

; A = activite -> HL = nom
act_name:
        add a,a
        ld l,a
        ld h,0
        ld de,t_name
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ret

header: call lib_cls
        ld de,#0000
        call lib_locate
        ld hl,m_title
        call lib_prt
        ld de,#0100
        call lib_locate
        ld hl,m_leg
        jp lib_prt

;----------------------------------------------------------------------
; Une mesure : configuration, &E8, activite, &E9
;----------------------------------------------------------------------
one:    ld (spone),sp
        ld a,(act)
        IFDEF G256
        cp 8                    ; activites 0-7 : bank 0-3 (= act/2), page
        ld bc,#7FC0             ; &C4-&C7 + 8 x bank, tournante (pile dans la page)
        jr nc,on_1
        and 6
        rlca
        rlca
        ld c,a
        ld a,(rep)
        and 3
        add a,c
        add a,#C4
        ld c,a
        ELSE
        cp 4
        ld bc,#7F00+CFG         ; activites 0-3 : page &C4 (pile dans la page)
        jr c,on_1
        ld bc,#7FC0
        ENDIF
on_1:   ld (curcfg),bc
        out (c),c
        ld sp,#8000
        ld a,#E8
        call pico_cmd
        or a
        jr nz,on_9
        ld a,(act)
        add a,a
        ld l,a
        ld h,0
        ld de,t_act
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld de,on_r
        push de
        jp (hl)
on_r:   ld a,#E9
        call pico_cmd
        cp 2
        jr nz,on_2
        ld hl,(nover)
        inc hl
        ld (nover),hl
on_2:   cp 7
        jr nz,on_9
        ld hl,(nshort)
        inc hl
        ld (nshort),hl
on_9:   ld bc,#7FC0
        out (c),c
        ld sp,(spone)
        ret

;----------------------------------------------------------------------
; Activites (~1-3 ms ; les 91 derniers us sont analyses)
;----------------------------------------------------------------------
a_push: ld (spsave),sp
        ld sp,#7000
        ld hl,#A55A
        repeat 1024
        push hl
        rend
        ld sp,(spsave)
        ret
a_ldi:  ld hl,#4000
        ld de,#5000
        ld bc,1024
        repeat 512
        ldi
        rend
        ret
a_ld:   ld hl,#5800
        ld a,#3C
        repeat 768
        ld (hl),a
        inc hl
        rend
        ret
a_out:  ld hl,#5C00
        ld bc,(curcfg)
        ld a,#C3
        repeat 512
        out (c),c
        ld (hl),a
        inc l
        rend
        ret
a_rom:  ld bc,#7F8A             ; ROM basse ON (mode 2)
        out (c),c
        ld hl,#0000
        repeat 512
        ld a,(hl)
        inc hl
        rend
        ld bc,#7F8E
        out (c),c
        ret
a_in:   ld bc,#F500             ; PPI port B (lecture sans effet)
        repeat 512
        in a,(c)
        rend
        ret
a_nop:  repeat 1024
        nop
        rend
        ret

;----------------------------------------------------------------------
; Lecture du resultat : &EC puis 2 x RES_LEN fois &EB (&20 + demi-octet)
; -> rbuf ; Carry = erreur
;----------------------------------------------------------------------
fetch:  ld a,#EC
        call pico_cmd
        or a
        scf
        ret nz
        ld hl,rbuf
        ld (fptr),hl
        ld hl,RES_LEN
        ld (fcnt),hl
fe_1:   call nib
        ret c
        rlca
        rlca
        rlca
        rlca
        ld (ftmp),a
        call nib
        ret c
        ld hl,ftmp
        or (hl)
        ld hl,(fptr)
        ld (hl),a
        inc hl
        ld (fptr),hl
        ld hl,(fcnt)
        dec hl
        ld (fcnt),hl
        ld a,h
        or l
        jr nz,fe_1
        ld a,(rbuf)
        cp 'G'
        scf
        ret nz
        ld a,(rbuf+1)
        cp 4
        scf
        ret nz
        or a
        ret
nib:    ld a,#EB
        call pico_cmd
        ld b,a
        and #F0
        cp #20
        scf
        ret nz
        ld a,b
        and #0F
        ret                     ; (AND -> Carry = 0)

;----------------------------------------------------------------------
; Petits outils d'affichage
;----------------------------------------------------------------------
hexw:   ld l,(ix+0)             ; compteur en (IX) : 3 chiffres hexa
        ld h,(ix+1)
hex3:   ld a,h                  ; HL en 3 chiffres hexa (FFF = FFF ou plus)
        cp #10
        jr c,hx3_1
        ld hl,#0FFF
hx3_1:  ld a,h
        call lib_hexn
        ld a,l
        jp lib_hex8
space:  ld a,' '
        jp lib_putc
; nom de 5 caracteres de la voie A
ch_name:
        ld l,a
        ld h,0
        ld e,l
        ld d,h
        add hl,hl
        add hl,hl
        add hl,de
        ld de,t_ch
        add hl,de
        ld b,5
cn_1:   ld a,(hl)
        call lib_putc
        inc hl
        djnz cn_1
        ret

;----------------------------------------------------------------------
; Page unique, ecrite par-dessus (pas d'effacement : pas de clignotement)
; Seules les lignes du bus sont affichees ; les autres GPIO (non cablees)
; n'apparaissent que si elles rebondissent.
;----------------------------------------------------------------------
show:   ld de,#0300
        call lib_locate
        ld hl,m_bits
        call lib_prt
        ld de,#0400
        ld hl,m_a8
        ld bc,t_a8
        call chrow
        ld de,#0500
        ld hl,m_dcpc
        ld bc,t_dcpc
        call chrow
        ld de,#0600
        ld hl,m_dpco
        ld bc,t_dpco
        call chrow
        ld de,#0700
        call lib_locate
        ld hl,m_chead
        call lib_prt
        ld de,#0800
        ld hl,m_n12
        ld bc,t_ctl
        call chrow
        ; ---- creux / pics
        ld de,#0900
        call lib_locate
        ld hl,m_crp
        call lib_prt
        ld ix,rbuf+O_DIR
        ld b,4
sh_c:   push bc
        call hexw
        ld a,'/'
        call lib_putc
        inc ix
        inc ix
        call hexw
        call space
        inc ix
        inc ix
        pop bc
        djnz sh_c
        ; ---- 1er rebond de commande
        ld de,#0A00
        call clrrow
        ld hl,m_snap
        call lib_prt
        ld a,(rbuf+3)
        cp #FF
        jr nz,sh_5
        ld hl,m_nosnap
        call lib_prt
        jr sh_oth
sh_5:   add a,16                ; broche 28-31 -> voie 44-47
        call ch_name
        ld a,':'
        call lib_putc
        call space
        ld a,(rbuf+3)           ; C = masque dans l'octet 3 : 1 << (broche - 24)
        sub 24-1
        ld b,a
        ld a,1
sh_6:   dec b
        jr z,sh_7
        add a,a
        jr sh_6
sh_7:   ld c,a
        ld ix,rbuf+O_SNAP
        ld b,24
sh_9:   ld a,(ix+0)
        and 2                   ; selection 0/1 : signal non valide
        ld a,'.'
        jr z,sh_10
        ld a,(ix+3)
        and c
        ld a,'_'
        jr z,sh_10
        ld a,'#'
sh_10:  call lib_putc
        inc ix
        inc ix
        inc ix
        inc ix
        djnz sh_9
        ld hl,m_snap2
        call lib_prt
        ; ---- autres GPIO : seulement celles qui rebondissent (4 au plus)
sh_oth: ld de,#0B00
        call clrrow
        ld hl,m_oth
        call lib_prt
        xor a
        ld (nfound),a
        ld hl,t_oth
sh_o1:  ld a,(hl)
        cp #FF
        jr z,sh_o3
        inc hl
        push hl
        ld (ch),a
        call ch_ix
        ld a,(ix+0)
        or (ix+1)
        or (ix+2)
        or (ix+3)
        jr z,sh_o2
        ld a,(nfound)
        inc a
        ld (nfound),a
        cp 5
        jr nc,sh_o2             ; (au-dela de 4 : "..." plus bas)
        ld a,(ch)
        call ch_name
        call space
        ld a,(ch)
        call entry
        call space
sh_o2:  pop hl
        jr sh_o1
sh_o3:  ld a,(nfound)
        or a
        ld hl,m_none
        jr z,sh_o4
        cp 5
        jr c,sh_hist
        ld hl,m_more
sh_o4:  call lib_prt
        ; ---- positions
sh_hist:
        ld de,#0C00
        call lib_locate
        ld hl,m_phead
        call lib_prt
        ld de,#0D00
        call lib_locate
        ld hl,m_p3
        call lib_prt
        ld ix,rbuf+O_HIST
        call hist12
        ld de,#0E00
        call lib_locate
        ld hl,m_p2
        call lib_prt
        call hist12
        ld de,#0F00
        call lib_locate
        ld hl,m_pdp
        call lib_prt
        ld ix,rbuf+O_HSRV
        call hist12
        ld de,#1000
        call lib_locate
        ld hl,m_pdc
        call lib_prt
        call hist12
        ; ---- position des rebonds de D depuis le debut du cycle Z80
        ld de,#1100
        call lib_locate
        ld hl,m_chd
        call lib_prt
        ld de,#1200
        call lib_locate
        ld hl,m_cc
        call lib_prt
        ld ix,rbuf+O_HCYC
        call hist16
        ld de,#1300
        call lib_locate
        ld hl,m_cp
        call lib_prt
        call hist16
        ; ---- activites
        ld de,#1500
        call lib_locate
        ld hl,m_ahead
        call lib_prt
        ld de,#1600
        call lib_locate
        ld hl,m_acpc
        call lib_prt
        xor a
sh_a:   ld (ch),a
        call act_ix
        ld l,(ix+0)             ; bus CPC = MREQ + ctrl + Dcpc + A8-15
        ld h,(ix+1)
        ld e,(ix+2)
        ld d,(ix+3)
        add hl,de
        jr c,sh_sat
        ld e,(ix+4)
        ld d,(ix+5)
        add hl,de
        jr c,sh_sat
        ld e,(ix+8)
        ld d,(ix+9)
        add hl,de
        jr nc,sh_a2
sh_sat: ld hl,#FFFF
sh_a2:  call hex3
        ld hl,m_3sp
        call lib_prt
        ld a,(ch)
        inc a
        cp NACT
        jr c,sh_a
        ld de,#1700
        call lib_locate
        ld hl,m_apco
        call lib_prt
        xor a
sh_b:   ld (ch),a
        call act_ix
        ld l,(ix+6)             ; Dpico
        ld h,(ix+7)
        call hex3
        ld hl,m_3sp
        call lib_prt
        ld a,(ch)
        inc a
        cp NACT
        jr c,sh_b
        ; ---- ligne d'etat
        ld de,#1800
        call lib_locate
        ld hl,m_nan
        call lib_prt
        ld hl,(rbuf+68)
        call lib_hex16
        ld hl,m_per2
        call lib_prt
        ld hl,(nover)
        call lib_hex16
        ld hl,m_short
        call lib_prt
        ld hl,(nshort)
        call lib_hex16
        ld hl,(rbuf+O_TOT)      ; verdict : MREQ, ctrl, Dcpc, A8-15
        ld a,h
        or l
        ld hl,(rbuf+O_TOT+2)
        or h
        or l
        ld hl,(rbuf+O_TOT+4)
        or h
        or l
        ld hl,(rbuf+O_TOT+8)
        or h
        or l
        ld hl,m_verd0
        jr z,sh_v
        ld hl,m_verd1
sh_v:   jp lib_prt

; ligne D : libelle HL puis une case par voie de la liste BC (fin #FF)
chrow:  push bc
        push hl
        call lib_locate         ; (detruit HL)
        pop hl
        call lib_prt
        pop hl
cr_1:   ld a,(hl)
        cp #FF
        ret z
        inc hl
        push hl
        call entry
        pop hl
        jr cr_1
; case de la voie A : "n1 /n2" + '!' si rebond, sinon ' ' (8 caracteres)
entry:  call ch_ix
        call hexw
        ld a,'/'
        call lib_putc
        inc ix
        inc ix
        call hexw
        dec ix
        dec ix
        ld a,(ix+0)
        or (ix+1)
        or (ix+2)
        or (ix+3)
        ld a,' '
        jr z,en_1
        ld a,'!'
en_1:   jp lib_putc
; IX = rbuf + O_CH + 6 x A
ch_ix:  ld l,a
        ld h,0
        add hl,hl
        ld e,l
        ld d,h
        add hl,hl
        add hl,de
        ld de,rbuf+O_CH
        add hl,de
        push hl
        pop ix
        ret
; IX = rbuf + O_ACT + 14 x (ch)
act_ix: ld a,(ch)
        ld l,a
        ld h,0
        add hl,hl
        ld e,l
        ld d,h
        add hl,hl
        add hl,hl
        add hl,hl
        or a
        sbc hl,de
        ld de,rbuf+O_ACT
        add hl,de
        push hl
        pop ix
        ret
; efface la ligne D (79 espaces) et y place le curseur
clrrow: push de
        call lib_locate
        ld b,79
cl_1:   call space
        djnz cl_1
        pop de
        jp lib_locate

hist16: ld b,16
        jr hi_1
hist12: ld b,12                 ; 12 compteurs en (IX), IX avance
hi_1:   push bc
        call hexw
        call space
        inc ix
        inc ix
        pop bc
        djnz hi_1
        ret

;----------------------------------------------------------------------
; Commande picoCPC : A = code -> A = etat final (#FF = pas de reponse)
; (meme protocole que MARGES ; n'ecrit qu'en pile)
;----------------------------------------------------------------------
pico_cmd:
        ld e,a
        ld bc,#FBF2
        ld d,16
        ld hl,0
pc_1:   in a,(c)
        cp 1
        jr z,pc_w1
        or a
        jr z,pc_2
        xor a
        out (c),a
pc_w1:  call pc_tick
        jr nz,pc_1
        ld a,#FF
        ret
pc_2:   out (c),e
pc_3:   in a,(c)
        cp 1
        ret nz
        call pc_tick
        jr nz,pc_3
        ld a,#FF
        ret
pc_tick:
        dec hl
        ld a,h
        or l
        ret nz
        dec d
        ret

        IFDEF G256
t_act:  dw a_ldi,a_push,a_ldi,a_push,a_ldi,a_push,a_ldi,a_push,a_ldi,a_rom,a_nop
t_name: dw g_1,g_2,g_3,g_4,g_5,g_6,g_7,g_8,n_6,n_9,n_11
g_1:    db "LDI bank 0 (&C4-C7)",0
g_2:    db "PUSH bank 0        ",0
g_3:    db "LDI bank 1 (&CC-CF)",0
g_4:    db "PUSH bank 1        ",0
g_5:    db "LDI bank 2 (&D4-D7)",0
g_6:    db "PUSH bank 2        ",0
g_7:    db "LDI bank 3 (&DC-DF)",0
g_8:    db "PUSH bank 3        ",0
m_ahead: db "Activite LDI0  PUSH0 LDI1  PUSH1 LDI2  PUSH2 LDI3  PUSH3 LDIb  ROM   NOP",0
m_title: db "GLITCH256 v4 (pioglitch4)",0
        ELSE
t_act:  dw a_push,a_ldi,a_ld,a_out,a_push,a_ldi,a_ld,a_out,a_rom,a_in,a_nop
t_name: dw n_1,n_2,n_3,n_4,n_5,n_6,n_7,n_8,n_9,n_10,n_11
m_ahead: db "Activite PUSHp LDIp  LD p  OUTp  PUSHb LDIb  LD b  OUTb  ROM   IN    NOP",0
m_title: db "GLITCH v4 (pioglitch4)",0
        ENDIF
n_1:    db "PUSH page &C4      ",0
n_2:    db "LDI page &C4       ",0
n_3:    db "LD (HL),A page &C4 ",0
n_4:    db "OUT + ecr. page &C4",0
n_5:    db "PUSH RAM base      ",0
n_6:    db "LDI RAM base       ",0
n_7:    db "LD (HL),A RAM base ",0
n_8:    db "OUT + ecr. RAM base",0
n_9:    db "lecture ROM basse  ",0
n_10:   db "IN (PPI)           ",0
n_11:   db "NOP                ",0
t_a8:   db 20,21,22,23,24,25,26,27,#FF
t_dcpc: db 36,37,38,39,40,41,42,43,#FF
t_dpco: db 64,65,66,67,68,69,70,71,#FF
t_ctl:  db 44,45,46,47,2,3,#FF
t_oth:  db 4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
        db 48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,#FF

t_ch:   db "SEL0 ","SEL1 ","ROMDS","RAMDS","GP4  ","GP5  ","GP6  ","GP7  "
        db "GP8  ","GP9  ","GP10 ","GP11 ","GP12 ","GP13 ","GP14 ","GP15 "
        db "GP16 ","GP17 ","GP18 ","GP19 ","A8   ","A9   ","A10  ","A11  "
        db "A12  ","A13  ","A14  ","A15  ","A0   ","A1   ","A2   ","A3   "
        db "A4   ","A5   ","A6   ","A7   ","D0cpc","D1cpc","D2cpc","D3cpc"
        db "D4cpc","D5cpc","D6cpc","D7cpc","RFSH ","IORQ ","MREQ ","RD/WR"
        db "GP32 ","GP33 ","GP34 ","GP35 ","GP36 ","GP37 ","GP38 ","GP39 "
        db "GP40 ","GP41 ","GP42 ","GP43 ","GP44 ","GP45 ","GP46 ","GP47 "
        db "D0pco","D1pco","D2pco","D3pco","D4pco","D5pco","D6pco","D7pco"

m_leg:   db "n1/n2 = rebonds de 11/22 ns (hexa).  Dcpc : le CPC pilote D, Dpico : la PicoCPC",0
m_bits:  db "bit        0       1       2       3       4       5       6       7",0
m_a8:    db "A8-15   ",0
m_dcpc:  db "Dcpc    ",0
m_dpco:  db "Dpico   ",0
m_chead: db "        RFSH    IORQ    MREQ    RD/WR   ROMDIS  RAMDIS",0
m_n12:   db "n1/n2   ",0
m_crp:   db "cr/pic  ",0
m_snap:  db "1er rebond ",0
m_nosnap: db ": aucun",0
m_snap2: db " (13e)",0
m_oth:   db "Autres GPIO : ",0
m_none:  db "aucun rebond",0
m_more:  db "...",0
m_phead: db "Position (x 11 ns)    0   1   2   3   4   5   6   7   8   9  10 11+",0
m_p3:    db "ctrl / mux sel3     ",0
m_p2:    db "ctrl / mux sel2     ",0
m_pdp:   db "Dpico / debut Pico  ",0
m_pdc:   db "Dcpc / fin Pico     ",0
m_chd:   db "Debut cycle (ns)  0  22  44  67  89 111 133 155 178 200 222 244 266 289 311 333+",0
m_cc:    db "  Dcpc          ",0
m_cp:    db "  Dpico         ",0
m_acpc:  db "bus CPC  ",0
m_apco:  db "Dpico    ",0
m_3sp:   db "   ",0
m_nopico: db "PicoCPC absente ou ne repond pas : &",0
m_nofw:  db "Firmware sans test de rebonds v4 (mettre pioglitch4) : &",0
m_err:   db "Erreur de la PicoCPC : &",0
m_fbad:  db "Lecture du resultat impossible (firmware pioglitch4 ?)         ",0
m_pass:  db "Passe &",0
m_act:   db "  activite : ",0
m_per2:  db "  debordements &",0
m_short: db "  trop courts &",0
m_nan:   db "Analyses &",0
m_verd0: db "   bus CPC : AUCUN rebond",0
m_verd1: db "   *** REBONDS bus CPC",0

pass:   dw 0
nover:  dw 0
nshort: dw 0
act:    db 0
rep:    db 0
ch:     db 0
nfound: db 0
curcfg: dw 0
spsave: dw 0
spone:  dw 0
fptr:   dw 0
fcnt:   dw 0
ftmp:   db 0
rbuf:   ds RES_LEN

        include "cpclib.asm"
c_fin:
        assert c_fin < #BC00            ; pile en #C000
        IFDEF G256
        save "GLITCH256.BIN",#8000,c_fin-#8000,AMSDOS
        ELSE
        save "GLITCH.BIN",#8000,c_fin-#8000,AMSDOS
        ENDIF
