# CPC HW Test — suite de diagnostic matériel Amstrad CPC

Programmes de diagnostic en assembleur Z80 (**RASM**) pour localiser une panne sur **Amstrad CPC 464 / 6128** : RAM de base, RAM paginée et extensions (y compris émulées, par ex. **PicoCPC**), Gate Array, Z80, bus et alimentation.

Chaque test tourne **sans le firmware** (DI ou interruptions maîtrisées, ROM basse et haute coupées) pour voir le vrai matériel, et boucle indéfiniment. On en sort par un **reset**.

## Programmes

| Programme | Source | Ce qui est testé | Documentation |
|---|---|---|---|
| **RAMTEST** | `src/ramtest464.asm` | **Les 64 Ko de RAM de base** (`#0000`–`#FFFF`), chaque octet, y compris l'écran et la zone où le programme est chargé.<br>• **1 – Motifs fixes** (bord bleu) : `00 FF 55 AA 33 CC 0F F0`, toute la RAM est remplie puis relue → bits collés, lignes de données<br>• **2 – Adresse dans adresse** (magenta) : octet = `L xor H`, puis l'inverse → lignes d'adresse, multiplexeurs 74LS153, alias<br>• **3 – March C-** (cyan) : `↑w0 ↑(r0,w1) ↑(r1,w0) ↓(r0,w1) ↓(r1,w0) r0` → cellules collées, couplages, transitions<br>• **4 – Pseudo-aléatoire** (jaune) : LFSR 16 bits, graine différente à chaque passe<br>• **5 – Rétention** (orange) : `55` puis `AA`, attente d'environ 4 s, relecture<br>• **6 – Bloc du programme** (blanc) : une routine relogeable copiée en `#4000` sauvegarde `#8000`–`#87FF`, lui applique les tests 1 à 5, puis le restaure<br>En cas d'erreur : adresse, attendu, lu, XOR et **bits fautifs D0–D7** (sur le 464, un bit correspond à un boîtier 4164).<br>*Pas de rafales ni de RAM paginée : voir BURSTTEST et MEMTEST.* | [doc/RAMTEST.md](doc/RAMTEST.md) |
| **MEMTEST** | `src/memtest.asm` | **Toute la RAM paginée** par `&7FC4`–`&7FFF` (64 Ko du 6128, extensions jusqu'à 512 Ko, RAM émulée PicoCPC…), vue par la fenêtre `#4000`–`#7FFF`.<br>• **Détection** : 16 signatures par page → carte des pages `O` présente / `!` anomalie (trou, page partielle) / `.` absente<br>Sur chaque page, 4 tours d'affilée (`MX_ROUNDS`) :<br>• **01** motifs fixes · **02** adresse dans adresse (masque selon la page) · **03** March C- · **04** aléatoire · **05** **fuite** : la RAM interne `#4000`–`#7FFF` ne doit pas avoir bougé (signal RAMDIS)<br>Puis, toujours sur la page :<br>• **09 – Rafales** : 8 192 PUSH déroulés (16 Ko) relus par 8 192 POP avec 8 motifs 16 bits, puis 8 Ko copiés en LDI déroulés<br>• **0A – Exécution de code** : une routine pleine de préfixes CB/DD/ED/FD est copiée à 4 endroits et **exécutée depuis la page** juste après l'`OUT`, avec la pile en base puis dans la page → cycles M1 trop lents<br>• **0B–0F** : contrôle de fuite après chacune de ces étapes<br>Ensuite, sur toutes les pages :<br>• **06 – Croisé** : toutes les pages remplies puis toutes relues → alias entre banques<br>• **07 – Commutation rapide** : un `OUT` vers une page différente avant chaque écriture et chaque lecture<br>• **08 – Modes C1 / C3** : page 3 de l'extension en `#C000`, page de base 3 en `#4000` | [doc/MEMTEST.md](doc/MEMTEST.md) |
| **GATEST** | `src/gatest.asm` | **Gate Array** (40007 / 40010), interruptions actives.<br>• **Interruptions** : il doit y en avoir **exactement 6 par trame** (300 Hz), comptées entre deux VSYNC lues sur le PPI → erreurs INT/TRAME<br>• **Rafale d'OUT** : 256 × (bord, encre 2, encre 3, registre de mode) ; les bandes dans le bord sont normales<br>• **Pagination ROM** : ROM basse activée par blocs de 32 octets, la somme de `#1000`–`#3FFF` doit rester identique (signaux ROMEN / ROMDIS)<br>• **RAM sous la ROM** : ROM coupée, `#1000`–`#3FFF` doit garder son motif<br>• **12 HALT** par boucle (synchronisation façon démo)<br>Compteurs affichés toutes les secondes, tous doivent rester à `0000`. | [doc/GATEST.md](doc/GATEST.md) |
| **BURSTTEST** | `src/bursttest.asm` | **Accès bus à vitesse maximale** dans la RAM de base, façon démo, interruptions coupées.<br>• **LDI déroulés** : 4 096 LDI copient 4 Ko `#4000` → `#5000`, puis comparaison<br>• **PUSH blast** : 6 144 PUSH déroulés remplissent `#9000`–`#BFFF` (le motif 16 bits change à chaque boucle), puis 6 144 POP relisent et comparent<br>• **Lecture POP** : 2 048 POP font la somme de la source, comparée à la référence<br>• **Rafales d'OUT** : GA (encres 2–15, mode) et CRTC (R12/R13) réécrits avec les mêmes valeurs<br>• **PSG** : registres 0–7, 11 et 12 de l'AY écrits avec des valeurs aléatoires puis **relus** via le PPI (volumes à 0 : silencieux)<br>Un compteur d'erreurs par catégorie ; bord rouge dès qu'un compteur n'est plus nul. | [doc/BURSTTEST.md](doc/BURSTTEST.md) |
| **Z80TEST** | `src/z80test.asm` | **Jeu d'instructions et stabilité du Z80** à 100 % de charge (interruptions coupées). Chaque groupe produit une **signature 32 bits** des résultats et des drapeaux (bits 3 et 5 de F masqués) :<br>• **1 – ALU 8 bits** : ADD, ADC, SUB, SBC, AND, XOR, OR, CP × 256 × 256, retenue 0 et 1 (655 360 opérations)<br>• **2 – Unaires** : DAA, CPL, NEG, rotations, décalages, INC, DEC, CCF, SCF × 256 valeurs × 8 combinaisons C/N/H<br>• **3 – Préfixe CB** : les 32 opcodes CB sur A (dont SLL non documenté), code auto-modifiant<br>• **4 – Arithmétique 16 bits** : ADD / ADC / SBC HL,BC sur 16 384 paires aléatoires<br>• **5 – Instructions de bloc** : LDIR, LDDR, CPIR, CPDR sur 1 Ko (registres, drapeaux, contenu)<br>• **6 – IX/IY et échanges** : adressage indexé ±d, EX (SP),IX, EXX, EX AF,AF', RLD, RRD<br>• **7 – Multiplication** 16×16 → 32 bits sur 2 048 paires<br>La passe 1 sert de référence : toute signature différente ensuite = erreur. Les signatures de la passe 1 peuvent être comparées à celles d'un émulateur précis. | [doc/Z80TEST.md](doc/Z80TEST.md) |
| **PWRTEST** | `src/pwrtest.asm` | **Alimentation sous charge maximale**, à observer à l'oscilloscope sur le 5 V de la carte.<br>• **Moteur K7** : bit 4 du port C du PPI (appuyer sur PLAY sans cassette)<br>• **Son** : 3 voies AY en carré à ~110 Hz, en phase, volume 15<br>• **CPU + RAM** : 8 192 PUSH (16 Ko), LDIR de 16 Ko vers l'écran, relecture par 8 192 POP, mots `#FF00` / `#00FF` (chaque ligne de données bascule à chaque accès)<br>• **Écran** : 16 encres et bord en blanc vif<br>• **Deux régimes** alternés toutes les ~8 s : charge **fixe**, puis charge **pulsée** à ~2 Hz (moteur et son coupés et rallumés)<br>Arrêt avec bord rouge si la RAM perd une donnée sous charge. | [doc/PWRTEST.md](doc/PWRTEST.md) |
| *(bibliothèque)* | `src/cpclib.asm` | Pas un test : routines communes (affichage mode 2 avec la fonte de la ROM, hexadécimal, attente, lecture et écriture de l'AY via le PPI), incluses par tous les tests sauf RAMTEST. | [doc/CPCLIB.md](doc/CPCLIB.md) |

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
