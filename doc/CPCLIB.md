# CPCLIB — bibliothèque commune

**Fichier :** `cpclib.asm` — à inclure **à la fin** de chaque test (`include "cpclib.asm"`), sans ORG.

| Routine | Entrée | Rôle |
|---|---|---|
| `lib_init` | — | mode 2, ROM basse/haute coupées, encres noir/blanc, CRTC écran en #C000 |
| `lib_inks` | — | encre 0 noir, encre 1 blanc, bord noir |
| `lib_border` | A = couleur hardware (#40-#5F) | couleur du bord |
| `lib_cls` | — | efface #C000-#FFFF |
| `lib_locate` | D = ligne, E = colonne | position du curseur |
| `lib_prt` | HL = chaîne terminée par 0 | affiche une chaîne |
| `lib_putc` | A = caractère | affiche un caractère (fonte ROM #3800), préserve HL/DE/BC |
| `lib_hex16` / `lib_hex8` | HL / A | affichage hexadécimal |
| `lib_wait` | H | attente H × ~0,45 s |
| `lib_psgw` | A = registre, C = valeur | écriture AY via le PPI |
| `lib_psgr` | A = registre | lecture AY → A |
| `lib_silence` | — | coupe les 3 voies |

Variables : `lib_curs` (curseur), `lib_pcb` (bits du port C à conserver, ex. moteur = #10), `lib_iff` (1 si le programme tourne avec interruptions : `lib_putc` les réactive alors après sa lecture de fonte).

**Note :** `LD A,I` n'est pas utilisé pour connaître l'état des interruptions : sur Z80 NMOS, une interruption pendant cette instruction peut renvoyer « interruptions coupées » à tort.

**RASM :** les noms de labels sont insensibles à la casse et ne doivent pas reprendre une directive (`STOP`, `PRINT`…) : d'où les préfixes `lib_`, `mx_`, `ga_`…
