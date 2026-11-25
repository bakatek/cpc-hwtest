; CARTTEST - cartouche de 512 Ko (32 pages, maximum adressable par &DF #80-#9F)
NP equ 32
        buildcpr "CART512.CPR"
        include "carttest.asm"
