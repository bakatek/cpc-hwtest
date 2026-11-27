# GLITCH : rebonds sur les entrées de la PicoCPC

Source : `src/glitch.asm`. Binaire : `build/GLITCH.BIN`.

```
MEMORY &7FFF:LOAD"GLITCH.BIN",&8000:CALL &8000
```

**Il faut le firmware de test PicoCPC `pioglitch4`**, fourni dans [`firmware/pioglitch4/`](../firmware/pioglitch4/README.md). Sans lui, le programme affiche « Firmware sans test de rebonds v3 ».

## Pourquoi

Sur un 464, les fuites de la RAM d'extension venaient de **creux parasites de 11 ns au plus
sur MREQ**. Le core1 de la PicoCPC les prenait pour une fin de cycle (voir
`RAPPORT_fuites_RAM_464.md` dans le projet picoCPC_rebuild).

Si une broche rebondit, d'autres le peuvent aussi. GLITCH compte ces impulsions parasites
**sur toutes les entrées du RP2350B**, pendant que le CPC fait des accès typiques.

## Ce que fait le firmware

**GPIO0-31** sont observées par un analyseur PIO :
- 1 échantillon toutes les 11,1 ns ;
- anneau DMA de 91 µs ;
- l'automate RAMDIS continue de tourner pendant la mesure.

**GPIO32-47** sont hors de portée du PIO, à cause de sa fenêtre de broches. Le core0 les lit en
boucle tant que la mesure est armée, environ toutes les 3 à 10 ns. La période réelle est
affichée.

Un rebond est une broche qui change, puis revient à sa valeur, après 1 échantillon (**n1**) ou
2 échantillons (**n2**).

Le bus du CPC passe par un multiplexeur, d'où des règles particulières :
- **A8-A15** (sélection 3) et **D0-D7** (sélection 2) ne comptent que si la sélection est
  restée la même au moins 2 échantillons avant l'impulsion et pendant toute sa durée. Le bus
  suit le multiplexeur avec un retard de 11 ns au plus.
- **RFSH, IORQ, MREQ, RD/WR** (GPIO28-31) ne comptent qu'en sélection 2 ou 3. Dans les autres
  sélections, ces broches portent autre chose.
- **A0-A7 ne sont pas mesurables.** La sélection 1 ne dure que 1 à 2 échantillons ; le tableau
  affiche `n/m`.
- **D0-D7** ne sont mesurés que pendant les sélections 2 assez longues.
- **GPIO0-1** (sélection du multiplexeur) sont ignorés.

## Ce que la v2 ajoute

- **D0-D7 séparés** : `Dcpc` quand le CPC pilote les données, `Dpco` quand la PicoCPC sert le
  cycle (ROMDIS ou RAMDIS levé dans l'échantillon). Un rebond `Dpco` vient de la PicoCPC (ou de
  la contention CPC/PicoCPC), un rebond `Dcpc` du CPC ou du câblage.
- **Creux / pics** sur RFSH, IORQ, MREQ, RD/WR (creux = la ligne active remonte 11 ns).
- **Position** de chaque rebond de commande depuis le dernier changement du multiplexeur, en
  échantillons de 11 ns (0..10, 11+), en sélection 3 et 2. Groupés en 0-1 : commutation du
  multiplexeur de la carte. Répartis : bruit du CPC.
- **Compteurs par activité** (le programme annonce l'activité par `&80`+n).
- **1er rebond** de commande : 24 échantillons autour, sur la ligne qui a rebondi.

## Déroulement

Chaque passe enchaîne 11 activités, chacune répétée 8 fois :
- PUSH, LDI, LD (HL),A et OUT + écriture, d'abord en page `&C4`, puis en RAM de base ;
- lecture de la ROM basse ;
- IN sur le PPI ;
- NOP.

Pour chaque répétition : `&80`+n (activité), `&E8` arme, l'activité tourne 1 à 3 ms, `&E9`
analyse les 91 µs qui précèdent. Les compteurs s'accumulent ; laissez tourner longtemps.

## Variante GLITCH256

`build/GLITCH256.BIN` (`src/glitch256.asm`, même firmware `pioglitch4`) balaye 256 Ko
d'extension : LDI (lecture + écriture) et PUSH (écriture seule) dans chaque bank 0-3, la page
tournant sur les 4 de la bank (`&C4-&C7`, `&CC-&CF`, `&D4-&D7`, `&DC-&DF`), puis LDI en RAM de
base, ROM, NOP. Sur un 6128, la bank 0 est la RAM interne et les banks 1-3 sont servies par la
PicoCPC : on compare les deux sur la même machine.

```
MEMORY &7FFF:LOAD"GLITCH256.BIN",&8000:CALL &8000
```

## Lecture de l'écran

Une seule page, réécrite sur place à chaque passe. Compteurs en hexadécimal sur 3 chiffres
(`FFF` = FFF ou plus). Chaque case `n1/n2` est suivie de `!` si la ligne a rebondi.

| Lignes | Contenu |
|---|---|
| 1-2 | passe et activité en cours, légende |
| 4-7 | tableau par bit (0-7) : `A8-15`, `Dcpc` (le CPC pilote D), `Dpico` (cycle servi par la PicoCPC : ROMDIS/RAMDIS levé) |
| 8-9 | RFSH, IORQ, MREQ, RD/WR, ROMDIS, RAMDIS : `n1/n2` |
| 10 | `cr/pic` : creux / pics d'1 échantillon des 4 lignes de commande |
| 11 | 1er rebond de commande : 24 échantillons (`#` 1, `_` 0, `.` hors sélection 2/3), le rebond est le 13e |
| 12 | autres GPIO (non câblées) : seulement celles qui rebondissent |
| 13-17 | position des rebonds en pas de 11 ns (0..10, 11+) : commandes après changement du multiplexeur (sel3, sel2) ; `Dpico` depuis le début du cycle servi (montée ROMDIS/RAMDIS) ; `Dcpc` depuis sa fin |
| 18-20 | position des rebonds de D depuis le début du cycle Z80 (MREQ ou IORQ devient actif), en ns par pas de 22 ns, `Dcpc` et `Dpico`. Le Z80 lit la donnée en fin de cycle (environ 250-350 ns) : un rebond tôt est un transitoire sans conséquence, un rebond tardif peut fausser la lecture |
| 22-24 | par activité : rebonds bus CPC (MREQ+ctrl+Dcpc+A8-15) et `Dpico` |
| 25 | analyses, débordements FIFO, analyses trop courtes, verdict |

A0-A7 et SEL0-1 ne sont pas affichés (non mesurables).

**Interprétation** : un CPC sain donne `AUCUN`. Un rebond sur MREQ, IORQ, RD/WR ou RFSH
signifie qu'une fin ou un début de cycle peut être mal détecté par la PicoCPC. Comparer 464,
6128 et Plus.

## Commandes du firmware (port `&FBF2`)

| Commande | Effet | Réponse |
|---|---|---|
| `&E8` | Arme la mesure | `0` |
| `&E9` | Fige la mesure et analyse | `0` ; `2` = débordement ; `6` = pas armé ; `7` = moins de 200 µs depuis `&E8` |
| `&EA` | Remet les compteurs à zéro | `0` |
| `&EB` | Demi-octet suivant du résultat | `&20` + valeur |
| `&EC` | Revient au début du résultat | `0` |
| `&80`-`&8F` | Activité en cours (compteurs par activité) | `0` |

Le résultat fait 1012 octets (version 4) :
- `'G'`, version 2, drapeaux, broche du 1er rebond ;
- période GPIO32-47, nombre d'échantillons, broches en sortie, FUNCSEL, nombre d'analyses ;
- 72 voies × (n1, n2, activité) ;
- creux/pics, positions, 16 activités × 7 compteurs, 24 échantillons, totaux ;
- position des rebonds de D depuis le début (Dpico) / la fin (Dcpc) du cycle servi ;
- position des rebonds de D depuis le début du cycle Z80 (16 × 22 ns, Dcpc puis Dpico).

Le détail est dans `pio/glitch.c` (picoCPC_rebuild).

## Limites et validation

- L'analyse du firmware a été vérifiée en émulation (code ARM réel, unicorn) sur de vraies
  traces de 464 et de 6128 : chaque compteur est comparé à une analyse de référence en Python.
  Des impulsions injectées (MREQ creux et pic, GPIO10, D5 servi, D6 CPC, GPIO32-47) sont
  bien comptées, dans la bonne voie, le bon groupe et la bonne activité.
- Le programme CPC n'a pas encore tourné sur machine.
- Un rebond plus court qu'environ 5 ns peut passer entre deux échantillons. Le test donne un
  minimum, pas un compte exact.
