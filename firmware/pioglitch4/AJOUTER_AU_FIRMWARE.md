# Ajouter l'analyseur de rebonds à un autre firmware PicoCPC

Ce document s'adresse à qui écrit son propre firmware PicoCPC (RP2350B) et veut que **GLITCH**, **GLITCH256** et **PINMAP** fonctionnent avec. Il décrit **ce qu'il faut ajouter**, pas un code à copier : `pioglitch4` est un patch binaire du firmware 1.02, mais tout ici se transpose en C avec le SDK Pico.

Ce qu'il faut :
- une machine d'état PIO libre ;
- un canal DMA ;
- 48 Ko de RAM ;
- trois commandes de plus sur le port `&FBF2` ;
- un appel dans la boucle principale du core0.

L'automate du bus et le reste du firmware ne changent pas.

---

## 1. Ce que les programmes CPC attendent

### Protocole
C'est le protocole habituel du port de commande `&FBF2` :
1. le CPC écrit un octet de commande ;
2. il relit l'état jusqu'à ce qu'il ne vaille plus 1 (« occupé ») ;
3. la valeur lue est la réponse.

Les programmes ont un délai maximum : sans réponse, ils affichent « PicoCPC absente ». Si la réponse à `&E8` n'est pas 0, ils affichent « Il faut le firmware pioglitch4 ».

| Commande | Rôle | Réponse |
|---|---|---|
| `&E8` | **Arme** la capture (efface l'anneau, démarre PIO + DMA) | `0` ; `5` si la mémoire manque |
| `&E9` | **Fige** la capture et **analyse** l'anneau | `0` ; `2` = la FIFO a débordé (échantillons perdus) ; `6` = pas armé ; `7` = moins de 200 µs depuis `&E8` |
| `&EA` | Remet tous les compteurs à zéro | `0` |
| `&EB` | Renvoie le **demi-octet suivant** du résultat, poids fort d'abord | `&20 + valeur` (jamais 0 ni 1, pour ne pas être confondu avec « OK » ou « occupé ») |
| `&EC` | Revient au début du résultat | `0` |
| `&80`-`&8F` | Numéro de l'**activité** en cours (0-15), pour les compteurs par activité | `0` |

### Séquence côté CPC
- **GLITCH**, pour chaque mesure :
  1. `&80+n` ;
  2. `&E8` ;
  3. 1 à 3 ms d'activité (PUSH, LDI, OUT…) ;
  4. `&E9`.

  Toutes les quelques mesures, `&EC` puis 2 × 1012 fois `&EB` pour lire le résultat.
- **PINMAP** : `&E8`, une courte attente, `&E9`, `&EC`, puis seulement les 68 premiers octets (2 × 68 `&EB`).

`&E5`-`&E7` (test du port au démarrage) ne sont pas utilisés par ces programmes.

---

## 2. Capture de GPIO0-31 : une machine d'état et un DMA

**Programme PIO : une seule instruction.** `in pins, 32` (code `0x4000`), qui boucle sur elle-même :
- `EXECCTRL` : `wrap_top` et `wrap_bottom` sur l'instruction ;
- `IN_BASE = 0` ;
- **autopush à 32 bits**, décalage à droite ;
- **FIFO RX jointe** (8 mots) ;
- diviseur **4**. À 360 MHz, cela fait 1 échantillon toutes les 11,1 ns.

Dans `pioglitch4`, c'est la SM1 du PIO2 qui le fait. L'instruction occupe le seul emplacement libre (31), derrière l'automate RAMDIS.

**Contrainte du RP2350B.** Une machine d'état ne voit que 32 GPIO consécutives, à partir du `GPIOBASE` de son PIO (0 ou 16). Pour voir GPIO0-31, elle doit tourner dans un PIO dont `GPIOBASE = 0` :
- s'il en reste un libre, c'est le plus simple ;
- sinon, une SM libre et un emplacement libre dans un PIO à `GPIOBASE = 0` suffisent, sans gêner les autres SM.

**DMA** (canal 15 dans `pioglitch4`) :
- source : la FIFO RX de la SM, adresse fixe ;
- destination : un **anneau de 32 Ko** (8 192 échantillons = 91 µs), avec le bouclage d'adresse du DMA (`RING_SIZE = 15`, sur l'écriture) ;
- **l'anneau doit être aligné sur 32 Ko** ;
- transferts de 32 bits, DREQ = RX de la SM ;
- compteur « sans fin » : `0xFFFFFFFF`, ou le mode *endless* du RP2350.

**`&E8`** :
1. arrête la SM ;
2. annule le DMA (`CHAN_ABORT`) ;
3. efface le drapeau RXSTALL de la SM (`FDEBUG`) ;
4. programme la SM et le DMA ;
5. note l'heure (timer en µs) ;
6. relève les sorties (voir § 4) ;
7. redémarre la SM avec `CLKDIV_RESTART` / `SM_RESTART`.

**`&E9`** :
1. arrête la SM ;
2. lit l'adresse d'écriture du DMA : c'est la position de l'échantillon le plus récent ;
3. annule le DMA.

Ensuite :
- si RXSTALL est levé (des échantillons ont été perdus), on répond 2 après l'analyse ;
- si moins de 200 µs se sont écoulées depuis `&E8`, l'anneau n'est pas plein : on répond 7 sans analyser ;
- sinon on **analyse les 8 192 échantillons**, du plus ancien au plus récent (§ 5).

L'analyse prend quelques ms sur le core0. Le CPC attend en lisant « occupé ».

---

## 3. GPIO32-47 : lecture par le core0

Le PIO ne peut pas voir à la fois GPIO0-31 et GPIO32-47. Ces dernières sont donc lues par le **core0**, dans sa boucle principale, **tant que la capture est armée** :
- interruptions masquées ;
- 4 096 lectures de `SIO GPIO_HI_IN`, déroulées par 8, dans un tampon de 16 Ko ;
- la durée est mesurée avec le timer. La **période moyenne**, environ 3 à 10 ns, est renvoyée dans le résultat ;
- puis analyse immédiate des rebonds sur ces 16 bits (même règle n1 / n2, voies 48-63).

Dans `pioglitch4`, l'appel est un crochet sur la fonction appelée à chaque tour de la boucle principale du core0. Dans un firmware en C, il suffit d'ajouter `glitch_step()` dans la boucle.

---

## 4. Brochage pour PINMAP

Le relevé se fait au moment de `&E8` et de `&E9` (OU des deux) :
- **sens** : pour les 48 GPIO, le bit `OETOPAD` (bit 13) de `IO_BANK0 GPIO_STATUS(n)` indique une broche vue en sortie ;
- **fonction** : le champ `FUNCSEL` (bits 0-4) de `GPIO_CTRL(n)`.

Le résultat contient, pour chaque GPIO, l'octet `FUNCSEL | (sortie << 7)`. Valeurs de FUNCSEL sur le RP2350 :
- 0 = HSTX, 1 = SPI, 2 = UART, 3 = I2C, 4 = PWM, 5 = SIO ;
- 6 / 7 / 8 = PIO0 / 1 / 2 ;
- 9 = QMI / horloge, 10 = USB, 11 = UART auxiliaire ;
- 31 = aucune fonction.

---

## 5. Analyse

Un **rebond** est une broche qui change puis revient à sa valeur :
- après **1 échantillon** : `n1` ;
- après **2 échantillons** : `n2`.

Pour chaque broche, on compte aussi l'**activité**, c'est-à-dire le nombre de changements.

### Le bus multiplexé de la PicoCPC impose des règles
Brochage de la carte : GPIO0-1 = sélection du multiplexeur, GPIO2 = ROMDIS, GPIO3 = RAMDIS, GPIO20-27 = bus, GPIO28-31 = RFSH, IORQ, MREQ, RD/WR.

- **GPIO20-27** : la voie dépend de la sélection.
  - Sélection 3 : A8-A15.
  - Sélection 1 : A0-A7.
  - Sélection 2 : D0-D7. Celles-ci sont rangées en **Dpico** si ROMDIS ou RAMDIS est levé dans l'échantillon (c'est la PicoCPC qui pilote les données), sinon en **Dcpc**.
  - Une impulsion ne compte que si la sélection est restée la même **2 échantillons avant et pendant toute l'impulsion** : le bus suit le multiplexeur avec jusqu'à 11 ns de retard.
  - A0-A7 ne sont donc jamais mesurables, car la sélection 1 ne dure que 1 à 2 échantillons.
- **GPIO28-31** : ne comptent qu'en sélection 2 ou 3, car ailleurs elles portent d'autres signaux. On compte aussi les **creux** (la ligne active remonte 1 échantillon) et les **pics** (l'inverse).
- **GPIO0-1** (sorties de la Pico) : ignorés.

### Ce que l'analyse mesure aussi
- **Position** de chaque rebond de commande depuis le dernier changement du multiplexeur, de 0 à 10 échantillons puis 11+, par sélection (3 et 2).
- **Position des rebonds de D** :
  - depuis la montée de ROMDIS/RAMDIS (Dpico) ou leur descente (Dcpc) ;
  - depuis le **début du cycle Z80** (MREQ ou IORQ devient actif), par pas de 22 ns (16 cases).
- **Compteurs par activité** (16 × 7) : MREQ, autres commandes, Dcpc, Dpico, A8-A15, autres GPIO, nombre d'analyses.
- **Totaux** des 6 groupes.
- **24 échantillons bruts** autour du 1er rebond de commande, qui est le 13e de la série.

Tous les compteurs sont sur **16 bits, saturés** à `FFFF`. Ils s'accumulent d'une analyse à l'autre jusqu'à `&EA`.

La référence exacte de l'algorithme, en C, est `pio/glitch.c` du projet picoCPC_rebuild (fonction `analyse_ring`) : environ 80 lignes, sans dépendance au firmware.

---

## 6. Format du résultat (1 012 octets, 16 bits petit-boutiste)

| Octet | Contenu |
|---|---|
| 0 | `'G'` (signature, vérifiée par les programmes) |
| 1 | version : `2` |
| 2 | drapeaux : bit 0 = débordement vu, bit 1 = au moins une analyse |
| 3 | broche du 1er rebond de commande (28-31), `&FF` = aucun |
| 4 | période de lecture de GPIO32-47 en 0,1 ns |
| 6 | nombre d'échantillons GPIO0-31 (32 bits) |
| 10 | nombre d'échantillons GPIO32-47 (32 bits) |
| 14 | broches vues en sortie (48 bits) |
| 20 | 48 × `FUNCSEL \| sortie << 7` |
| 68 | nombre d'analyses |
| 70 | 0 |
| 72 | 72 voies × (n1, n2, activité), voir le détail juste après |
| 504 | RFSH, IORQ, MREQ, RD/WR × (creux, pics) |
| 520 | position des rebonds de commande : sélection 3 (12 cases), puis sélection 2 (12 cases) |
| 568 | 16 activités × 7 compteurs |
| 792 | 24 échantillons GPIO0-31 (32 bits) |
| 888 | totaux des 6 groupes |
| 900 | position des rebonds de D : Dpico depuis le début du cycle servi (12 cases), Dcpc depuis sa fin (12 cases) |
| 948 | position des rebonds de D depuis le début du cycle Z80 : Dcpc (16 cases), puis Dpico (16 cases) |

Les 72 voies de l'octet 72 sont :
- 0-19 : GPIO0-19 ;
- 20-27 : A8-A15 ;
- 28-35 : A0-A7 ;
- 36-43 : D0-D7 (Dcpc) ;
- 44-47 : RFSH, IORQ, MREQ, RD/WR ;
- 48-63 : GPIO32-47 ;
- 64-71 : D0-D7 (Dpico).

`&EB` lit ce tableau demi-octet par demi-octet (poids fort, puis poids faible de chaque octet) et reste sur le dernier à la fin.

---

## 7. Mémoire et précautions

- **Mémoire** : allouer **une seule fois**, à la première commande, environ 48 Ko :
  - l'anneau de 32 Ko aligné ;
  - le tampon de GPIO32-47 (16 Ko). `pioglitch4` le loge dans la marge perdue par l'alignement si elle suffit ;
  - les compteurs (environ 1 Ko).

  En cas d'échec, répondre 5 à toutes les commandes.
- **L'automate du bus ne doit pas être touché.** On n'arrête que **sa** SM (masque dans `CTRL`), jamais les autres. Si la SM partage le PIO de l'automate, la reprogrammer instruction par instruction et vérifier qu'aucune autre SM n'utilise l'emplacement choisi.
- **Le core1** (service du bus) n'est pas concerné. La lecture de GPIO32-47 masque les interruptions du **core0** seulement, environ 15 à 40 µs par paquet.
- **Bande passante** : à 11 ns, le DMA écrit 360 Mo/s dans la SRAM. Placer l'anneau dans un banc de SRAM différent de celui où le core1 lit son code et ses tables, sinon le service du bus peut ralentir. Le débordement (réponse 2) dit si le DMA a pris du retard.
- **Vérification** : `pioglitch4` a été validé en émulation sur des traces réelles de 464 et de 6128, avec des rebonds injectés, contre une analyse de référence en Python. Une analyse alternative doit donner les **mêmes compteurs** sur les mêmes traces : c'est le moyen le plus simple de la valider.
