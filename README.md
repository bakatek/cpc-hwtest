# CPC HW Test — suite de diagnostic matériel Amstrad CPC

Programmes de diagnostic en assembleur Z80 (**RASM**) pour localiser une panne sur **Amstrad CPC 464 / 6128 / Plus** : RAM de base, RAM paginée et extensions (y compris émulées, par ex. **PicoCPC**), Gate Array, Z80, bus, alimentation, et accès aux périphériques émulés (disquette, cartouche).

Chaque test tourne **sans le firmware** (DI ou interruptions maîtrisées, ROM basse et haute coupées) pour voir le vrai matériel, et boucle indéfiniment. On en sort par un **reset**.

## Programmes

| Programme | Source | Ce qui est testé | Documentation |
|---|---|---|---|
| **RAMTEST** | `src/ramtest464.asm` | **Les 64 Ko de RAM de base** (`#0000`–`#FFFF`), chaque octet, y compris l'écran et la zone où le programme est chargé.<br>• **1 – Motifs fixes** (bord bleu) : `00 FF 55 AA 33 CC 0F F0`, toute la RAM est remplie puis relue → bits collés, lignes de données<br>• **2 – Adresse dans adresse** (magenta) : octet = `L xor H`, puis l'inverse → lignes d'adresse, multiplexeurs 74LS153, alias<br>• **3 – March C-** (cyan) : `↑w0 ↑(r0,w1) ↑(r1,w0) ↓(r0,w1) ↓(r1,w0) r0` → cellules collées, couplages, transitions<br>• **4 – Pseudo-aléatoire** (jaune) : LFSR 16 bits, graine différente à chaque passe<br>• **5 – Rétention** (orange) : `55` puis `AA`, attente d'environ 4 s, relecture<br>• **6 – Bloc du programme** (blanc) : une routine relogeable copiée en `#4000` sauvegarde `#8000`–`#87FF`, lui applique les tests 1 à 5, puis le restaure<br>En cas d'erreur : adresse, attendu, lu, XOR et **bits fautifs D0–D7** (sur le 464, un bit correspond à un boîtier 4164).<br>*Pas de rafales ni de RAM paginée : voir BURSTTEST et MEMTEST.* | [doc/RAMTEST.md](doc/RAMTEST.md) |
| **MEMTEST** | `src/memtest.asm` | **Toute la RAM paginée** par `&7FC4`–`&7FFF` (64 Ko du 6128, extensions jusqu'à 512 Ko, RAM émulée PicoCPC…), vue par la fenêtre `#4000`–`#7FFF`.<br>• **Détection** : 16 signatures par page → carte des pages `O` présente / `!` anomalie (trou, page partielle) / `.` absente<br>Sur chaque page, 4 tours d'affilée (`MX_ROUNDS`) :<br>• **01** motifs fixes · **02** adresse dans adresse (masque selon la page) · **03** March C- · **04** aléatoire · **05** **fuite** : la RAM interne `#4000`–`#7FFF` ne doit pas avoir bougé (signal RAMDIS)<br>Puis, toujours sur la page :<br>• **09 – Rafales** : 8 192 PUSH déroulés (16 Ko) relus par 8 192 POP avec 8 motifs 16 bits, puis 8 Ko copiés en LDI déroulés<br>• **0A – Exécution de code** : une routine pleine de préfixes CB/DD/ED/FD est copiée à 4 endroits et **exécutée depuis la page** juste après l'`OUT`, avec la pile en base puis dans la page → cycles M1 trop lents<br>• **0B–0F** : contrôle de fuite après chacune de ces étapes<br>Ensuite, sur toutes les pages :<br>• **06 – Croisé** : toutes les pages remplies puis toutes relues → alias entre banques<br>• **07 – Commutation rapide** : un `OUT` vers une page différente avant chaque écriture et chaque lecture<br>• **08 – Modes C1 / C3** : page 3 de l'extension en `#C000`, page de base 3 en `#4000` | [doc/MEMTEST.md](doc/MEMTEST.md) |
| **LEAKTEST** | `src/leaktest.asm` | **Fuites de l'extension vers la RAM interne**, scénario par scénario, sur une page (`&C4` par défaut, constante `LT_CFG`). Écrit une valeur V dans toute la page et compte les octets de la RAM de base `#4000`–`#7FFF` modifiés (**fuites**, réparés aussitôt) et les octets de la page qui n'ont pas reçu V (**perdus**) :<br>• **0 – Remplissage lent** (référence) : `LD (HL),A` en boucle, page fixe<br>• **1 – PUSH déroulés** : 8 192 PUSH, page fixe (cas du test 0B de MEMTEST)<br>• **2 – LDI déroulés** : 8 Ko copiés dans la page<br>• **3 – LD (HL),A déroulés** : une écriture toutes les ~3 µs<br>• **4 – OUT + écriture immédiate** : pour chaque octet, `OUT` page, écriture, `OUT` C0<br>• **5 – OUT + 4 NOP + écriture** : même chose avec ~4 µs entre la sélection et l'écriture<br>• **6 – OUT + PUSH immédiat** (× 8 192)<br>Le tableau (compteurs, dernière adresse et valeur) permet de distinguer : écritures consécutives mal gérées, sélection de page trop lente, ou défaut de décodage / RAMDIS / connecteur. | [doc/LEAKTEST.md](doc/LEAKTEST.md) |
| **MAPTEST** | `src/maptest.asm` | **Configurations C1 / C3, écriture sous ROM, exécution**, cas non couverts par MEMTEST (trouvés avec la démo *Batman Forever* sur 464 + PicoCPC). Utilise les 384 octets non affichés de l'écran (page 3) et la page 7 de l'extension, 16 valeurs par passe :<br>• **0 / 2** : écriture en **C3** par `#4000` (`LD` puis PUSH), relue en **C0** par `#C000` (C3 émulé sur 464)<br>• **1** : ces écritures ne doivent pas toucher la page de base 1<br>• **3** : écriture en C0 par `#C000`, relue en C3 par `#4000`<br>• **4 / 5** : écriture dans la page 7 en **C1 avec la ROM haute active** (POKE du BASIC), relue par `#4000` ; la page de base 3 ne doit pas bouger<br>• **6** : **exécution** de code dans la page 7 en `#C000` (C1)<br>• **7** : exécution de la page 3 en `#4000` (C3)<br>• **8** : code écrit en C3, exécuté en C0 (cas *Batman Forever*) | [doc/MAPTEST.md](doc/MAPTEST.md) |
| **GATEST** | `src/gatest.asm` | **Gate Array** (40007 / 40010), interruptions actives.<br>• **Interruptions** : il doit y en avoir **exactement 6 par trame** (300 Hz), comptées entre deux VSYNC lues sur le PPI → erreurs INT/TRAME<br>• **Rafale d'OUT** : 256 × (bord, encre 2, encre 3, registre de mode) ; les bandes dans le bord sont normales<br>• **Pagination ROM** : ROM basse activée par blocs de 32 octets, la somme de `#1000`–`#3FFF` doit rester identique (signaux ROMEN / ROMDIS)<br>• **RAM sous la ROM** : ROM coupée, `#1000`–`#3FFF` doit garder son motif<br>• **12 HALT** par boucle (synchronisation façon démo)<br>Compteurs affichés toutes les secondes, tous doivent rester à `0000`. | [doc/GATEST.md](doc/GATEST.md) |
| **BURSTTEST** | `src/bursttest.asm` | **Accès bus à vitesse maximale** dans la RAM de base, façon démo, interruptions coupées.<br>• **LDI déroulés** : 4 096 LDI copient 4 Ko `#4000` → `#5000`, puis comparaison<br>• **PUSH blast** : 6 144 PUSH déroulés remplissent `#9000`–`#BFFF` (le motif 16 bits change à chaque boucle), puis 6 144 POP relisent et comparent<br>• **Lecture POP** : 2 048 POP font la somme de la source, comparée à la référence<br>• **Rafales d'OUT** : GA (encres 2–15, mode) et CRTC (R12/R13) réécrits avec les mêmes valeurs<br>• **PSG** : registres 0–7, 11 et 12 de l'AY écrits avec des valeurs aléatoires puis **relus** via le PPI (volumes à 0 : silencieux)<br>Un compteur d'erreurs par catégorie ; bord rouge dès qu'un compteur n'est plus nul. | [doc/BURSTTEST.md](doc/BURSTTEST.md) |
| **Z80TEST** | `src/z80test.asm` | **Jeu d'instructions et stabilité du Z80** à 100 % de charge (interruptions coupées). Chaque groupe produit une **signature 32 bits** des résultats et des drapeaux (bits 3 et 5 de F masqués) :<br>• **1 – ALU 8 bits** : ADD, ADC, SUB, SBC, AND, XOR, OR, CP × 256 × 256, retenue 0 et 1 (655 360 opérations)<br>• **2 – Unaires** : DAA, CPL, NEG, rotations, décalages, INC, DEC, CCF, SCF × 256 valeurs × 8 combinaisons C/N/H<br>• **3 – Préfixe CB** : les 32 opcodes CB sur A (dont SLL non documenté), code auto-modifiant<br>• **4 – Arithmétique 16 bits** : ADD / ADC / SBC HL,BC sur 16 384 paires aléatoires<br>• **5 – Instructions de bloc** : LDIR, LDDR, CPIR, CPDR sur 1 Ko (registres, drapeaux, contenu)<br>• **6 – IX/IY et échanges** : adressage indexé ±d, EX (SP),IX, EXX, EX AF,AF', RLD, RRD<br>• **7 – Multiplication** 16×16 → 32 bits sur 2 048 paires<br>La passe 1 sert de référence : toute signature différente ensuite = erreur. Les signatures de la passe 1 peuvent être comparées à celles d'un émulateur précis. | [doc/Z80TEST.md](doc/Z80TEST.md) |
| **PWRTEST** | `src/pwrtest.asm` | **Alimentation sous charge maximale**, à observer à l'oscilloscope sur le 5 V de la carte.<br>• **Moteur K7** : bit 4 du port C du PPI (appuyer sur PLAY sans cassette)<br>• **Son** : 3 voies AY en carré à ~110 Hz, en phase, volume 15<br>• **CPU + RAM** : 8 192 PUSH (16 Ko), LDIR de 16 Ko vers l'écran, relecture par 8 192 POP, mots `#FF00` / `#00FF` (chaque ligne de données bascule à chaque accès)<br>• **Écran** : 16 encres et bord en blanc vif<br>• **Deux régimes** alternés toutes les ~8 s : charge **fixe**, puis charge **pulsée** à ~2 Hz (moteur et son coupés et rallumés)<br>Arrêt avec bord rouge si la RAM perd une donnée sous charge. | [doc/PWRTEST.md](doc/PWRTEST.md) |
| **DSKTEST** | `src/dsktest.asm`<br>`src/mkdsktest.py` | **Accès disquette, cas limites** (contrôleur µPD765 réel ou émulé, PicoCPC…), en **lecture seule**, sur la disquette de test `DSKTEST.DSK` au contenu connu. Le contrôleur est piloté directement ; chaque attente a un délai maximum (un contrôleur bloqué est compté comme erreur, la machine ne se fige pas).<br>• **1 – Recalibrage et seek** (pistes 0 à 41, PCN vérifié)<br>• **2–3 – Lecture standard** 9 × 512, piste entière en une commande, 4 fois de suite à vitesse maximale (boucle façon chargeur de démo)<br>• **4 – 10 secteurs** par piste · **5 – Tailles** 128 à 2048 · **6 – Secteur de 4 Ko**<br>• **7 – IDs non standard** : C ≠ piste, C/H/R = `#FF`, H = 1, R = 0…<br>• **8 – Secteurs effacés** (READ DATA / READ DELETED DATA, bit CM)<br>• **9 – Erreur CRC simulée** · **A – Secteur inexistant** · **B – Piste non formatée** · **C – READ ID**<br>• **D – Pistes 40 et 41** · **E – Overrun** (lecture trop lente) · **F – Commande invalide**<br>Données vérifiées octet par octet, octets d'état ST0–ST2 comparés à ceux d'un vrai 765. Deux colonnes : **ERREURS** (accès faux) et **INFO** (écart de conformité sans danger pour les logiciels courants). | [doc/DSKTEST.md](doc/DSKTEST.md) |
| **CARTTEST** | `src/carttest.asm`<br>`src/cart128/256/512.asm` | **Cartouche (CPR)**, pour les plantages aléatoires des cartouches émulées sur CPC+ (Pang, Sonic…). Le test **est une cartouche** : il démarre seul et s'exécute depuis la cartouche, interruptions actives, comme un jeu. Trois tailles : 128 Ko (cartouches d'origine), 256 Ko, 512 Ko (maximum adressable).<br>• **1 – Signatures** : carte des 32 pages `&DF #80`–`#9F` (présente / miroir / absente), stable d'une passe à l'autre<br>• **2 – Lecture** `LD A,(HL)` de toutes les données ; page 0 : vue ROM basse = vue ROM haute<br>• **3 – Rafales** : LDI déroulés et somme par POP<br>• **4 – Exécution depuis la cartouche** (cycles M1) à 4 adresses par page, aussi juste après un `OUT &DF`<br>• **5 – Commutation rapide** : `OUT &DF` puis lecture immédiate, une page différente à chaque octet<br>• **6 – RMR2** (CPC+) : pages 0–7 en ROM basse à `#0000`, `#4000` et `#8000`<br>• **7 – Mappage `&DF` 0 / 7** (CPC+)<br>• **8 – Interruptions** : 6 par trame, avec la routine d'interruption dans la cartouche<br>Le test continue après une erreur ; la ligne **EN COURS** indique ce qui tournait en cas de plantage. Sur un CPC sans ASIC, les tests 6 et 7 sont sautés. | [doc/CARTTEST.md](doc/CARTTEST.md) |
| **GLITCH** | `src/glitch.asm` | **Rebonds (impulsions parasites) sur toutes les entrées du RP2350B de la PicoCPC**, avec le firmware de test `pioglitch4`. Le firmware observe GPIO0-31 (analyseur PIO, 11 ns) et GPIO32-47 (lecture logicielle) pendant 11 activités (PUSH, LDI, LD, OUT + écriture en page `&C4` puis en RAM de base, ROM basse, IN, NOP) et compte les impulsions d'1 et 2 échantillons par broche : A8-A15, D0-D7, RFSH, IORQ, MREQ, RD/WR séparés selon le multiplexeur (A0-A7 non mesurables), D0-D7 séparés selon qui pilote (CPC / PicoCPC) ; v2 : compteurs par activité, creux/pics, position par rapport au multiplexeur, tracé du 1er rebond. Verdict sur le bus CPC : `AUCUN` ou `*** REBONDS`. | [doc/GLITCH.md](doc/GLITCH.md) |
| *(bibliothèque)* | `src/cpclib.asm` | Pas un test : routines communes (affichage mode 2 avec la fonte de la ROM, hexadécimal, attente, lecture et écriture de l'AY via le PPI), incluses par tous les tests sauf RAMTEST. | [doc/CPCLIB.md](doc/CPCLIB.md) |

Les binaires prêts à l'emploi (avec en-tête AMSDOS), la disquette de test `DSKTEST.DSK` et les cartouches `CART128/256/512.CPR` sont dans [`build/`](build/), et aussi dans les [releases](../../releases).

## Lancement

Depuis le BASIC (remplacer le nom du fichier) :

```
MEMORY &7FFF:LOAD"MEMTEST.BIN",&8000:CALL &8000
```

Tous les programmes se chargent et s'exécutent en `&8000`.

Deux exceptions :
- **DSKTEST** : mettre `DSKTEST.DSK` dans le lecteur A: puis `RUN"DSKTEST.BIN"` (le programme est sur la disquette).
- **CARTTEST** : charger `CART512.CPR` (ou 128 / 256) comme une cartouche (PicoCPC : `CCAT` / `CRUN`) ; il démarre seul.

## Lecture des résultats

- Affichage en **mode 2** (80 colonnes) avec la fonte lue dans la ROM basse. Les nombres sont en hexadécimal (`&`).
- **Couleur du bord** : elle indique le test en cours. **Vert** = passe réussie, **rouge** = erreur, avec l'adresse, la valeur attendue, la valeur lue et le XOR à l'écran.
- Laisser tourner longtemps (de 30 min à plusieurs heures), à froid puis à chaud.

## Ordre conseillé pour une machine instable

1. **RAMTEST** (RAM de base)
2. **MEMTEST** (RAM paginée / extension), puis **LEAKTEST** si MEMTEST signale une fuite, et **MAPTEST** (C1 / C3, écriture sous ROM) si un logiciel 128 Ko plante
3. **GATEST**
4. **BURSTTEST**
5. **Z80TEST** (comparer aussi les signatures de la passe 1 avec un émulateur précis : ACE-DL, CPCEC…)
6. **PWRTEST** (avec un oscilloscope sur le 5 V **de la carte**)

Pour les problèmes de périphériques émulés (PicoCPC…) : **DSKTEST** (disquette) et **CARTTEST** (cartouche, CPC+). Pour le bruit du bus vu par la PicoCPC : **GLITCH** (firmware de test `pioglitch4`).

## Assemblage

Il faut [RASM](https://github.com/EdouardBERGE/rasm) (testé avec la v3.3.0). La directive `save` en fin de source écrit le binaire avec son en-tête AMSDOS : pas besoin d'option `-ob`.

```sh
cd src
for f in ramtest464 memtest leaktest maptest gatest bursttest z80test pwrtest dsktest glitch glitch256 pinmap; do rasm $f.asm; done
for n in 128 256 512; do rasm cart$n.asm; done      # cartouches CARTTEST
python3 mkdsktest.py DSKTEST.BIN DSKTEST.DSK       # disquette de test (après dsktest)
mv *.BIN *.CPR DSKTEST.DSK ../build/
```

| Source | Binaire |
|---|---|
| `ramtest464.asm` | `RAMTEST.BIN` |
| `memtest.asm` | `MEMTEST.BIN` |
| `leaktest.asm` | `LEAKTEST.BIN` |
| `maptest.asm` | `MAPTEST.BIN` |
| `gatest.asm` | `GATEST.BIN` |
| `bursttest.asm` | `BURSTTEST.BIN` |
| `z80test.asm` | `Z80TEST.BIN` |
| `pwrtest.asm` | `PWRTEST.BIN` |
| `glitch.asm` | `GLITCH.BIN` |
| `glitch256.asm` | `GLITCH256.BIN` |
| `pinmap.asm` | `PINMAP.BIN` |
| `dsktest.asm` + `mkdsktest.py` | `DSKTEST.BIN`, `DSKTEST.DSK` |
| `cart128.asm` / `cart256.asm` / `cart512.asm` (incluent `carttest.asm` et `cartfont.asm`) | `CART128.CPR` / `CART256.CPR` / `CART512.CPR` |

`cpclib.asm` doit se trouver dans le même dossier : il est inclus **à la fin** de chaque source (sauf RAMTEST et CARTTEST, qui n'utilisent pas le firmware ni sa fonte). `mkdsktest.py` demande Python 3, sans module externe.

> **Note :** `BURSTTEST` dépasse 8 caractères. RASM tronque donc le nom dans l'en-tête AMSDOS (`BURSTTES.BIN`). Sur une disquette AMSDOS, utiliser un nom de 8 caractères au maximum.

## Limites

- MEMTEST couvre 512 Ko au maximum (port `&7Fxx` seul). Les extensions de 1 à 4 Mo, qui utilisent les bits d'adresse A8–A10, ne sont pas couvertes. Le mode C2 n'est pas testé.
- BURSTTEST ne travaille que dans la RAM de base : les rafales sur l'extension sont faites par MEMTEST (test 09).
- DSKTEST et CARTTEST n'ont pas encore été validés sur machine ni dans un émulateur : leur contenu (disquette, cartouches) a été vérifié par des scripts indépendants. Voir la section « Limites et validation » de leur documentation.

## Arborescence

```
src/    sources RASM (.asm) et générateur de la disquette de test (mkdsktest.py)
build/  binaires AMSDOS (.BIN), cartouches (.CPR), disquette de test (.DSK)
doc/    documentation détaillée de chaque test
```
