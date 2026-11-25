# CPC HW Test — suite de diagnostic matériel Amstrad CPC

Programmes de diagnostic en assembleur Z80 (**RASM**) pour localiser une panne sur **Amstrad CPC 464 / 6128** : RAM de base, RAM paginée et extensions (y compris émulées, par ex. **PicoCPC**), Gate Array, Z80, bus et alimentation.

Chaque test tourne **sans le firmware** (DI ou interruptions maîtrisées, ROM basse et haute coupées) pour voir le vrai matériel, et boucle indéfiniment. On en sort par un **reset**.

## Programmes

| Programme | Source | Ce qui est testé | Documentation |
|---|---|---|---|
| **RAMTEST** | `src/ramtest464.asm` | les 64 Ko de base, 100 % des adresses (y compris l'écran et la zone du programme, par relocalisation) | [doc/RAMTEST.md](doc/RAMTEST.md) |
| **MEMTEST** | `src/memtest.asm` | toute la RAM paginée `&7FC4`–`&7FFF` (jusqu'à 512 Ko) : détection, motifs, March C-, fuites vers la RAM interne, rafales, exécution de code depuis la page, modes C1/C3 | [doc/MEMTEST.md](doc/MEMTEST.md) |
| **GATEST** | `src/gatest.asm` | Gate Array : 6 interruptions par trame, rafales d'OUT, pagination ROM, HALT | [doc/GATEST.md](doc/GATEST.md) |
| **BURSTTEST** | `src/bursttest.asm` | accès bus à vitesse maximale : LDI déroulés, PUSH/POP, OUT GA/CRTC, écriture et relecture de l'AY | [doc/BURSTTEST.md](doc/BURSTTEST.md) |
| **Z80TEST** | `src/z80test.asm` | jeu d'instructions Z80 (7 groupes signés) et stabilité à 100 % de charge | [doc/Z80TEST.md](doc/Z80TEST.md) |
| **PWRTEST** | `src/pwrtest.asm` | alimentation sous charge maximale, fixe et pulsée (moteur K7, son, CPU/RAM) | [doc/PWRTEST.md](doc/PWRTEST.md) |
| *(bibliothèque)* | `src/cpclib.asm` | affichage mode 2, accès AY, utilitaires (incluse par tous sauf RAMTEST) | [doc/CPCLIB.md](doc/CPCLIB.md) |

Les binaires prêts à l'emploi (avec en-tête AMSDOS) sont dans [`build/`](build/).

## Lancement

Depuis le BASIC (remplacer le nom du fichier) :

```
MEMORY &7FFF:LOAD"MEMTEST.BIN",&8000:CALL &8000
```

Tous les programmes se chargent et s'exécutent en `&8000`.

## Lecture des résultats

- Affichage en **mode 2** (80 colonnes) avec la fonte lue dans la ROM basse. Les nombres sont en hexadécimal (`&`).
- **Couleur du bord** : elle indique le test en cours. **Vert** = passe réussie, **rouge** = erreur, avec l'adresse, la valeur attendue, la valeur lue et le XOR à l'écran.
- Laisser tourner longtemps (de 30 min à plusieurs heures), à froid puis à chaud.

## Ordre conseillé pour une machine instable

1. **RAMTEST** (RAM de base)
2. **MEMTEST** (RAM paginée / extension)
3. **GATEST**
4. **BURSTTEST**
5. **Z80TEST** (comparer aussi les signatures de la passe 1 avec un émulateur précis : ACE-DL, CPCEC…)
6. **PWRTEST** (avec un oscilloscope sur le 5 V **de la carte**)

## Assemblage

Il faut [RASM](https://github.com/EdouardBERGE/rasm) (testé avec la v3.3.0). La directive `save` en fin de source écrit le binaire avec son en-tête AMSDOS : pas besoin d'option `-ob`.

```sh
cd src
for f in ramtest464 memtest gatest bursttest z80test pwrtest; do rasm $f.asm; done
mv *.BIN ../build/
```

| Source | Binaire |
|---|---|
| `ramtest464.asm` | `RAMTEST.BIN` |
| `memtest.asm` | `MEMTEST.BIN` |
| `gatest.asm` | `GATEST.BIN` |
| `bursttest.asm` | `BURSTTEST.BIN` |
| `z80test.asm` | `Z80TEST.BIN` |
| `pwrtest.asm` | `PWRTEST.BIN` |

`cpclib.asm` doit se trouver dans le même dossier : il est inclus **à la fin** de chaque source.

> **Note :** `BURSTTEST` dépasse 8 caractères. RASM tronque donc le nom dans l'en-tête AMSDOS (`BURSTTES.BIN`). Sur une disquette AMSDOS, utiliser un nom de 8 caractères au maximum.

## Limites

- MEMTEST couvre 512 Ko au maximum (port `&7Fxx` seul). Les extensions de 1 à 4 Mo, qui utilisent les bits d'adresse A8–A10, ne sont pas couvertes. Le mode C2 n'est pas testé.
- BURSTTEST ne travaille que dans la RAM de base : les rafales sur l'extension sont faites par MEMTEST (test 09).

## Arborescence

```
src/    sources RASM (.asm)
build/  binaires AMSDOS compilés (.BIN)
doc/    documentation détaillée de chaque test
```
