# Z80TEST — jeu d'instructions et stabilité du Z80

**Fichier :** `z80test.asm` + `cpclib.asm` · **Binaire :** `Z80TEST.BIN`

## But
- **Stabilité** : faire tourner le Z80 à 100 % (DI) sur des millions d'instructions et vérifier que les résultats sont **toujours identiques**.
- **Justesse** (optionnel) : comparer les signatures à celles d'un émulateur précis.

## Principe
7 groupes calculent chacun une **signature 32 bits** (double somme de Fletcher) de tous les résultats **et des drapeaux**. Les bits 3 et 5 de F (non documentés) sont masqués.
- Passe 1 = **référence**.
- Passes suivantes : toute signature différente → **Erreurs** +1 pour ce groupe.

## Groupes
| # | Groupe | Contenu |
|---|---|---|
| 1 | ALU 8 bits | ADD, ADC (C=0/1), SUB, SBC (C=0/1), AND, XOR, OR, CP × 256 A × 256 opérandes = 655 360 opérations |
| 2 | Unaires / DAA | DAA, CPL, NEG, RLCA, RRCA, RLA, RRA, RLC, RRC, RL, RR, SLA, SRA, SRL, INC, DEC, CCF, SCF × 256 A × 8 combinaisons C/N/H |
| 3 | Préfixe CB | les 32 opcodes CB sur A (dont SLL), code auto-modifiant, A 0-255, C=0/1 |
| 4 | Arith. 16 bits | ADD/ADC/SBC HL,BC (C=0/1), 16 384 paires aléatoires |
| 5 | Blocs | LDIR, LDDR, CPIR, CPDR sur 1 Ko (×16) : registres, drapeaux, contenu |
| 6 | IX/IY/EX/RLD/RRD | adressage indexé ±d, EX (SP),IX, EXX, EX AF,AF', RLD, RRD |
| 7 | Multiplication | 16×16→32 bits par décalages, 2 048 paires |

## Écran
Une ligne par groupe : `n Nom Signature Erreurs`. `>` = groupe en cours. Le **bord change de couleur en continu** pendant le calcul (témoin d'activité) : s'il se fige, c'est un vrai plantage. Une passe dure 1 à 2 min. En fin de passe : bord vert si 0 erreur, rouge sinon.

## Comparer avec un émulateur
Lancer le même `Z80TEST.BIN` dans un émulateur précis (ACE-DL, CPCEC…) et comparer les 7 signatures de la passe 1. Identiques → le Z80 calcule juste.

## Interpréter
- Erreurs qui apparaissent après plusieurs passes : Z80 instable (alimentation, horloge, Z80 lui-même, bus).
- Signature de passe 1 différente de l'émulateur mais stable : comportement différent (Z80 non Zilog / clone, ou imprécision de l'émulateur).
