# Suite de tests matériels Amstrad CPC (464 / 6128 / Plus)

Programmes de diagnostic en Z80 (assembleur **RASM**) pour localiser une panne : RAM, Gate Array, Z80, bus, alimentation, RAM d'extension (y compris émulée, par ex. PicoCPC).

| Programme | Fichier | Teste | Doc |
|---|---|---|---|
| RAMTEST | `ramtest464.asm` | les 64 Ko de base, 100 % des adresses | [RAMTEST.md](RAMTEST.md) |
| MEMTEST | `memtest.asm` | toute la RAM paginée / extensions (jusqu'à 512 Ko), fuites, rafales, exécution | [MEMTEST.md](MEMTEST.md) |
| LEAKTEST | `leaktest.asm` | fuites extension → RAM interne, scénario par scénario (PUSH, LDI, OUT + écriture immédiate…) | [LEAKTEST.md](LEAKTEST.md) |
| GATEST | `gatest.asm` | Gate Array : interruptions, OUT, pagination ROM, HALT | [GATEST.md](GATEST.md) |
| BURSTTEST | `bursttest.asm` | accès bus à vitesse max (LDI, PUSH, POP, OUT, PSG) | [BURSTTEST.md](BURSTTEST.md) |
| Z80TEST | `z80test.asm` | jeu d'instructions Z80 + stabilité à 100 % | [Z80TEST.md](Z80TEST.md) |
| PWRTEST | `pwrtest.asm` | alimentation sous charge maximale et pulsée | [PWRTEST.md](PWRTEST.md) |
| DSKTEST | `dsktest.asm` + `mkdsktest.py` | accès disquette, cas limites (formats exotiques, effacés, CRC, overrun…) sur `DSKTEST.DSK`, lecture seule | [DSKTEST.md](DSKTEST.md) |
| CARTTEST | `carttest.asm` via `cart128/256/512.asm` | cartouche CPR exécutée depuis la cartouche : lecture, exécution M1, `&DF`, RMR2, interruptions | [CARTTEST.md](CARTTEST.md) |
| (bibliothèque) | `cpclib.asm` | affichage mode 2, accès AY — inclus par tous sauf RAMTEST | [CPCLIB.md](CPCLIB.md) |

## Assemblage

Tous les fichiers dans le même dossier, puis :

```
rasm ramtest464.asm     -> RAMTEST.BIN
rasm memtest.asm        -> MEMTEST.BIN
rasm leaktest.asm       -> LEAKTEST.BIN
rasm gatest.asm         -> GATEST.BIN
rasm bursttest.asm      -> BURSTTEST.BIN
rasm z80test.asm        -> Z80TEST.BIN
rasm pwrtest.asm        -> PWRTEST.BIN
rasm dsktest.asm        -> DSKTEST.BIN
python3 mkdsktest.py DSKTEST.BIN DSKTEST.DSK
rasm cart128.asm        -> CART128.CPR  (idem cart256, cart512)
```

Pas d'option `-ob` : la directive `save` en fin de source écrit le binaire avec son en-tête AMSDOS.

## Lancement (BASIC)

```
MEMORY &7FFF:LOAD"MEMTEST.BIN",&8000:CALL &8000
```

(remplacer le nom). Les tests ne rendent jamais la main : **reset** pour sortir.

## Points communs

- Tous chargés en `&8000`, ROM basse et haute **coupées** pendant le test : on voit la vraie RAM.
- Affichage en mode 2 (80 colonnes) avec la fonte lue dans la ROM basse.
- Les nombres sont affichés en hexadécimal (`&`).
- **Couleur du bord** : indique le test en cours ; **vert** = passe OK ; **rouge** = erreur.
- Les tests tournent en boucle : laisser tourner longtemps (30 min à plusieurs heures), à froid puis à chaud.

## Ordre conseillé pour une machine instable

1. RAMTEST (base) → 2. MEMTEST (extension) → 3. GATEST → 4. BURSTTEST → 5. Z80TEST → 6. PWRTEST (avec oscilloscope sur le 5 V **de la carte**).
