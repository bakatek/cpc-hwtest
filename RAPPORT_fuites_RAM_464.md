# picoCPC sur CPC 464 : fuites d'écritures de la RAM d'extension

Rapport technique sur le firmware `20261121-1.02-PicoCPC-sp1819`, novembre 2026.

## 1. Le symptôme

Sur un 464, la picoCPC sert de RAM d'extension : pages `&C4`, `&C5`… dans la fenêtre `&4000-&7FFF`.
Quand le Z80 écrit dans une page d'extension, la picoCPC doit lever **RAMDIS** pendant tout le
cycle. Sinon, la RAM interne du 464 reçoit elle aussi l'écriture.

Une **fuite**, c'est une écriture destinée à la page d'extension qui modifie aussi la RAM de base.

Le programme de test LEAKTEST (LEAKDIAG pour la version détaillée) écrit en rafales dans la page
`&C4` (PUSH, LDI, LD (HL),A, OUT + écriture), puis relit la RAM de base. Le critère retenu est
**10 minutes sans aucune fuite**.

Historique :
- Le firmware du 25/10 ne fuit pas.
- Les fuites apparaissent dans les firmwares à partir du 30/10 et existent toujours dans celui du 21/11.
- Avec le firmware d'origine du 21/11, LEAKDIAG mesure 0 écriture perdue mais quelques fuites sur
  6 tours : PUSH 5, LDI &A6, OUT+PUSH &C. La valeur relue est toujours `00`.
- Les fuites sont rares et dépendent du type d'instruction. Cela fait penser à un problème de
  timing, pas de logique.

## 2. Rappels sur le matériel

- Le RP2350 voit le bus du CPC à travers un **multiplexeur** commandé par GPIO0-1 :
  - sélection 3 : A8-A15 sur GPIO20-27 ;
  - sélection 1 : A0-A7 ;
  - sélection 2 : D0-D7.
- GPIO28-31 portent RFSH, IORQ, MREQ et RD/WR (un seul fil pour les deux), mais **seulement en
  sélection 2 ou 3**.
- RAMDIS sort sur GPIO3.
- Dans le firmware d'origine, c'est le **core1** qui gère tout par logiciel :
  1. il attend le début d'un cycle MREQ/IORQ ;
  2. il bascule le multiplexeur pour lire l'adresse ;
  3. il choisit un handler selon la zone et le sens ;
  4. le handler lève RAMDIS si la zone est servie par la picoCPC ;
  5. le core1 attend la fin du cycle (boucle en `0x20080020`), relâche RAMDIS et recommence.

## 3. La méthode : mesurer au lieu de deviner

Les premières tentatives étaient des corrections « à l'aveugle » et ont échoué. Le tableau du
§6 les liste.

J'ai donc ajouté au firmware un **analyseur logique interne**, sans matériel supplémentaire :
- une machine d'état (SM) de PIO2, libre dans le firmware d'origine, échantillonne GPIO20-31,
  GPIO0-1, ROMDIS et RAMDIS toutes les 11,1 ns (4 cycles PIO à 360 MHz) ;
- un DMA vide ces échantillons dans un anneau de 32 Ko, sans aucune charge pour le core1 ;
- le déclenchement est programmable, et les commandes passent par le port `&FBF2` (`&E1` arme,
  `&E2` fige, `&E3` écrit `CAPTnnn.BIN` sur la carte SD) ;
- le décodage se fait sur PC (`tools/capdecode.py`).

Cette mesure a corrigé plusieurs hypothèses fausses. Par exemple, GPIO28 est **RFSH** et non WR,
comme je le supposais. Les signaux de GPIO28-31 n'ont de sens qu'en sélection 2/3.

## 4. La cause des fuites

L'analyseur a compté les événements « RAMDIS inactif alors que MREQ est actif, pendant une
écriture en `&4000-&7FFF` » (firmware capture5 + LEAKCAP).

Constats :
- Il y en a environ `&190` par ligne du test, **y compris sur les lignes sans fuite**. Le trou de
  RAMDIS est donc fréquent, et il ne fuit que de temps en temps.
- MREQ (GPIO30) présente des **creux parasites d'un seul échantillon (≤ 11 ns)** au milieu des
  cycles d'écriture.
- Ces creux apparaissent :
  - uniquement en sélection 3 ;
  - 1 à 4 échantillons après le retour du multiplexeur en sélection 3 ;
  - au moment où le bus passe de `00` à `7F` ou `FF`.

  C'est donc un **bruit de commutation** du multiplexeur qui se couple sur la ligne MREQ.
- La boucle de fin de cycle du core1 (`0x20080020` : `mrc`, `tst`, `bne`) lit ce creux et croit
  le cycle terminé :
  1. elle **relâche RAMDIS au milieu de l'écriture** ;
  2. elle voit ensuite un « nouveau » cycle et relève RAMDIS environ 90 ns plus tard.
- Dans les anneaux de capture5, 16 des 84 écritures en page montraient ce trou.
- Quand le trou tombe au mauvais moment par rapport à l'écriture dans la DRAM du 464, l'octet
  part aussi en RAM interne : c'est la fuite.

Ce mécanisme explique aussi pourquoi **tout ajout de temps dans le core1 aggrave le problème**.
Avec hold1 (relâchement de RAMDIS retardé d'environ 70 ns), on a eu des milliers de fuites. Le
core1 doit être revenu dans son attente de début de cycle moins de ~100 ns après la fin de MREQ.
Au-delà, il rate le début du cycle suivant.

Je n'ai pas établi pourquoi le firmware du 25/10 ne fuyait pas. La correction du 30/10 que j'ai
annulée (ramdisfix1) ne suffit pas. Vu ce mécanisme, la cause probable est un timing de boucle
core1 légèrement différent, qui rend la lecture du creux plus ou moins probable.

### Preuve conservée

Les anneaux d'origine de capture5 ont été effacés de la carte SD : les chiffres `&190` et 16/84
viennent de l'analyse faite à ce moment-là.

Les creux sont aussi visibles dans les traces conservées, par exemple
`captures/pioshadcap3/CAPT001.BIN`, enregistrée avec le correctif debounce1 en place :
- 41 creux d'un échantillon de MREQ en sélection 3, tous pendant un cycle avec RAMDIS levé ;
- passage du bus de `00` vers `7F`/`FF` au moment du creux ;
- position après le retour en sélection 3 : 2 échantillons (18 fois), 1 (6), 4 (7), 8 (5)…

Extrait de cette trace, une écriture en page, 1 caractère = 11,1 ns, `^` = le creux :

```
                    ^
sel     122222222333333333333333333333333333333333
MREQ    _###########_#############################
RD/WR   ___#######################################
RAMDIS  ___#######################################
```

Avec le correctif, RAMDIS reste levé malgré le creux. Sans le correctif, le core1 le relâchait
à cet endroit.

## 5. Les correctifs

### 5.1 debounce1 : anti-rebond de la fin de cycle (correctif minimal, sur le core1)

La fin de cycle n'est acceptée que si une **seconde lecture, environ 18 ns plus tard**, la
confirme. Le stub est placé en scratch X, après le code core1 d'origine, et la boucle
`0x20080020` y saute.

```
L:  mrc  p0,#0,r3,c0,c8,#0   @ GPIO hi (MREQ/IORQ)
    tst  r2,r3
    bne  L                   @ cycle en cours
    movs r3,#1
D:  subs r3,#1               @ ~18 ns
    bne  D
    mrc  p0,#0,r3,c0,c8,#0   @ confirmation
    tst  r2,r3
    bne  L                   @ c'était un creux : on reste dans le cycle
    b.w  0x20080028          @ vraie fin de cycle (suite d'origine)
```

Le coût est d'environ 28 ns, sur la seule détection de fin. Source : `tools/patch_debounce.py`.

Validation sur le 464 :
- debounce1cap + LEAKCAP : le nombre d'événements tombe à ~0.
- debounce1 : **LEAKTEST 10 min, 0 fuite, 0 perte.**

### 5.2 RAMDIS par automate PIO (correctif robuste)

debounce1 marche, mais le core1 reste au bord de son budget de temps. Le but est donc de sortir
RAMDIS du logiciel : un automate sur PIO2 (SM0) pilote GPIO3 par side-set. Source :
`pio/ramdis2.pio`, 31 instructions.

Fonctionnement :
- Il relève RFSH et A15-A13 **uniquement en sélection 3 établie**, juste avant le front de MREQ.
- Il saute dans une table de 8 instructions, une par zone de 8 Ko : `jmp yes side 1` ou
  `jmp no side 0`.
  - Le core1 recalcule cette table à chaque changement de ses tables de handlers (sorties de la
    fusion, `FUN_10020160`, `FUN_1001e8dc`).
  - Une zone est active si son handler de lecture ou d'écriture lève RAMDIS.
- La fin de cycle n'est retenue qu'après plusieurs relectures consécutives de MREQ inactif. Ce
  filtre absorbe les creux de ≤ 11 ns.
- Environ 170 ns après MREQ, l'automate relit GPIO3 et le compare à sa décision. En cas de
  désaccord, il envoie un instantané dans la FIFO, vers un journal DMA.

Comparaison sur les traces réelles :

| | core1 (origine) | automate |
|---|---|---|
| RAMDIS monte après MREQ | 78-100 ns | 11-33 ns, donc bien avant WR (≥ 56 ns) |
| RAMDIS retombe après la fin de MREQ | 22-44 ns | 44-67 ns, cycle suivant ≥ 111 ns après |

#### Mise au point (étape « ombre »)

L'automate tournait d'abord en parallèle : GPIO3 restait au core1 et l'automate journalisait
ses désaccords.
- pioshadow1 à pioshadow3 : 0 fuite, mais environ 1 500 à 1 700 désaccords par série.
- L'analyseur, déclenché au premier désaccord (pioshadcap3), en a montré la vraie cause.

**Environ 100 ns après chaque fin de cycle, le core1 fait une excursion du multiplexeur
(sélection 1 → 0 → 2 → 3, environ 40 ns).** Le MREQ du rafraîchissement commence souvent
pendant cette excursion. L'automate relevait alors l'octet bas ou une donnée à la place de
l'adresse.

Extrait de `captures/pioshadcap3/CAPT000.BIN` : la fin d'un cycle, l'excursion, puis le
rafraîchissement. En sélection 1, la colonne MREQ n'est pas significative.

```
sel     333333333333333333333333331122333333333333
MREQ    ################____________##############
RFSH    __________________########__##############
```

v5 ne relève l'adresse qu'en sélection 3 établie : `wait 1 gpio 0 [4]`, `wait 1 gpio 1`,
`mov osr, pins`, `jmp pin`.

Vérifications de la v5 :
- Le simulateur `tools/pio_ramdis2_sim.py`, rejoué sur les traces, reproduisait les désaccords
  des versions précédentes. Sur ces mêmes traces, il donne 0 désaccord avec la v5.
- Sur le matériel, en ombre (pioshadcap5) : **13 itérations de LEAKSHAD, 0 désaccord.**

#### En service

pioservice5 donne GPIO3 à l'automate ; debounce1 reste en place pour les décisions du core1.

Validation sur le 464 : **LEAKTEST 10 min, 0 fuite, 0 perte.**

Il reste à faire : des essais d'usage normal (MEMTEST, jeux, disquette).

## 6. Ce qui n'a pas marché, et pourquoi

| Version | Idée | Résultat | Explication trouvée ensuite |
|---|---|---|---|
| ramdisfix1 | Remettre le `clr(0x3F0)` du firmware du 24/10 dans les handlers | Fuit toujours | Ce n'était pas la cause |
| ramdispio1-4 | Premier automate PIO, conçu sans mesures | Blocages, pertes, puis écran corrompu | Mauvaises hypothèses : GPIO28 pris pour WR, adresse lue trop tard, excursion du multiplexeur inconnue |
| wrlate1 | Ajouter un cas « écriture tardive » au tri du core1 | Fuites immédiates | Ce cas était en fait un rafraîchissement (RFSH) |
| hold1 | Retarder le relâchement de RAMDIS d'environ 70 ns dans le core1 | Des milliers de fuites | Le core1 rate alors le début du cycle suivant |
| capture1-5 | Analyseur interne | — | A permis de trouver la cause (§4) |

Ce qu'il faut retenir : sans mesure, on corrige un modèle faux du bus. Pour tout futur travail
sur le timing, l'analyseur interne (`--capture`) est l'outil à utiliser.

## 7. Vérification par machine

Les machines diffèrent (464 de 1982, 6128, 6128+, cartes mères plus ou moins bruitées).

`cpctests/MARGES.BIN` enregistre 8 traces avec le firmware pioshadcap6. `tools/marges.py`
compare ensuite chaque mesure à ce que l'automate exige : fenêtre, retard du bus, creux, écarts
entre cycles, durées actives.

| | Résultat |
|---|---|
| 464 | Toutes les marges tiennent |
| 6128 | Mêmes timings, toutes les marges tiennent |

Point serré : la fenêtre en sélection 3 après MREQ. On mesure 11-33 ns pour 22 ns exigés, et la
résolution de l'analyseur est de 11 ns. Le LEAKTEST sans fuite montre qu'elle n'est pas ratée
en pratique.

Remarque : GPIO31 ne montre WR que pendant que RAMDIS est levé. Une écriture que la picoCPC ne
sert pas n'a donc pas de WR visible. C'est normal et ce n'est pas un défaut de la machine.

## 8. Fichiers

| Rôle | Fichiers |
|---|---|
| Automate | `pio/ramdis2.pio` ; installation, mise à jour de la table et commandes : `pio/shadow_patch.S` |
| Construction | `tools/patch_shadow.py` (`--service`, `--capture`) ; `tools/patch_debounce.py` |
| Tests en émulation (code ARM réel, unicorn) | `tools/emu_shadow_test.py` |
| Simulateur PIO et rejeu de traces | `tools/pio_ramdis2_sim.py` (`--pieges` : 77 cas synthétiques) |
| Analyse des traces | `tools/capdecode.py`, `tools/shadcap_analyse.py`, `tools/marges.py` |
| Programmes CPC | `cpctests/` (LEAKDIAG, LEAKCAP, LEAKSHAD, MARGES, CAPTURE) |
| Traces | `captures/` (pioshadow1-3, pioshadcap3, marges_464, marges_6128) |
