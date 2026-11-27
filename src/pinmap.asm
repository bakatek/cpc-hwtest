; =====================================================================
;  PINMAP - brochage du RP2350B de la PicoCPC : fonction (FUNCSEL) et
;  sens (vue en sortie) des 48 GPIO, lus par le firmware de test
;  pioglitch4 (resultat de &EB, octets 14-67).
;  BASIC :  MEMORY &7FFF:LOAD"PINMAP.BIN",&8000:CALL &8000
; =====================================================================
        org #8000

start:  di
        ld sp,#C000
        call lib_init
        call lib_cls
        ld de,#0000
        call lib_locate
        ld hl,m_title
        call lib_prt
        ld a,#E8                ; quelques ms de mesure pour relever le sens
        call pico_cmd
        cp #FF
        jp z,nopico
        or a
        jp nz,nofw
        ld b,0
w_1:    djnz w_1
        ld a,#E9
        call pico_cmd
        ld a,#EC
        call pico_cmd
        ld hl,rbuf              ; 68 octets
        ld b,68
f_1:    push bc
        push hl
        call nib
        rlca
        rlca
        rlca
        rlca
        ld (hi4),a
        call nib
        ld hl,hi4
        or (hl)
        pop hl
        ld (hl),a
        inc hl
        pop bc
        djnz f_1
        ld a,(rbuf)
        cp 'G'
        jp nz,nofw
        ; ---- 48 broches, 3 colonnes x 16 lignes
        xor a
        ld (pin),a
p_1:    ld a,(pin)              ; ligne = 2 + pin mod 16, colonne = 26 x (pin / 16)
        and 15
        add a,2
        ld d,a
        ld a,(pin)
        rrca
        rrca
        rrca
        rrca
        and 3
        ld e,a
        add a,a
        add a,a
        add a,a                 ; 8x
        ld c,a
        add a,a                 ; 16x
        add a,c                 ; 24x
        add a,e
        add a,e                 ; 26x
        ld e,a
        call lib_locate
        ld a,'G'
        call lib_putc
        ld a,(pin)
        call dec2
        ld a,' '
        call lib_putc
        ld a,(pin)              ; octet 20 + pin : FUNCSEL | sortie << 7
        ld l,a
        ld h,0
        ld de,rbuf+20
        add hl,de
        ld a,(hl)
        push af
        and 31
        cp 12
        jr c,p_2
        ld a,12                 ; 12 = inconnu, 31 = NULL
        jr p_2
p_2:    ld l,a                  ; nom de 6 caracteres
        ld h,0
        add hl,hl
        ld e,l
        ld d,h
        add hl,hl
        add hl,de
        ld de,t_fn
        add hl,de
        ld b,6
p_3:    ld a,(hl)
        call lib_putc
        inc hl
        djnz p_3
        pop af
        push af
        and 31
        call lib_hex8           ; numero brut
        pop af
        ld hl,m_in
        rla
        jr nc,p_4
        ld hl,m_out
p_4:    call lib_prt
        ld a,(pin)
        call role               ; role connu
        ld a,(pin)
        inc a
        ld (pin),a
        cp 48
        jp c,p_1
        ld de,#1300
        call lib_locate
        ld hl,m_leg
        call lib_prt
        ld de,#1400
        call lib_locate
        ld hl,m_leg2
        call lib_prt
        jr $

; role connu de la broche A (0-3, 20-31), sinon rien
role:   ld c,a
        ld hl,t_lab
rl_1:   ld a,(hl)
        cp #FF
        ret z
        inc hl
        cp c
        jp z,lib_prt
rl_2:   ld a,(hl)
        inc hl
        or a
        jr nz,rl_2
        jr rl_1

; A en decimal sur 2 chiffres
dec2:   ld c,'0'-1
d2_1:   inc c
        sub 10
        jr nc,d2_1
        add a,10+'0'
        push af
        ld a,c
        call lib_putc
        pop af
        jp lib_putc

nopico: ld hl,m_nopico
        jr err
nofw:   ld hl,m_nofw
err:    push hl
        ld de,#0200
        call lib_locate
        pop hl
        call lib_prt
        jr $

nib:    ld a,#EB
        call pico_cmd
        and #0F
        ret

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

; FUNCSEL du RP2350 (datasheet, IO_BANK0 CTRL.FUNCSEL)
t_fn:   db "HSTX  ","SPI   ","UART  ","I2C   ","PWM   ","SIO   "
        db "PIO0  ","PIO1  ","PIO2  ","QMI/CK","USB   ","UARTAX","?     "
t_lab:  db 0," mux0",0, 1," mux1",0, 2," ROMDIS",0, 3," RAMDIS",0
        db 20," bus0",0, 21," bus1",0, 22," bus2",0, 23," bus3",0
        db 24," bus4",0, 25," bus5",0, 26," bus6",0, 27," bus7",0
        db 28," RFSH",0, 29," IORQ",0, 30," MREQ",0, 31," RD/WR",0
        db #FF

m_title: db "PINMAP - fonction et sens des 48 GPIO du RP2350B (firmware pioglitch4)",0
m_in:    db " e",0
m_out:   db " S",0
m_leg:   db "e = entree, S = vue en sortie. Numero = FUNCSEL (1F = aucune fonction).",0
m_leg2:  db "SIO = pilotee par le logiciel. PIO0/1/2 = machine d'etat. I2C/SPI = peripherique.",0
m_nopico: db "PicoCPC absente ou ne repond pas.",0
m_nofw:  db "Il faut le firmware pioglitch4 (ou pioglitch2/3).",0

pin:    db 0
hi4:    db 0
rbuf:   ds 68

        include "cpclib.asm"
c_fin:
        assert c_fin < #BC00
        save "PINMAP.BIN",#8000,c_fin-#8000,AMSDOS
