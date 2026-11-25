# RAMTEST — les 64 Ko de base

**Fichier :** `ramtest464.asm` (autonome, n'utilise pas `cpclib.asm`) · **Binaire :** `RAMTEST.BIN`

## But
Tester **chaque octet** des 64 Ko de RAM de base (#0000-#FFFF), y compris l'écran, la zone système et l'endroit où le programme est chargé — ce que la plupart des testeurs ne font pas.

## Principe (relocalisation)
- DI, ROM basse et haute coupées.
- **Phase A** : le programme tourne dans un bloc de 2 Ko (#8000-#87FF) et teste tout le reste (#0000-#7FFF et #8800-#FFFF).
- **Phase B** : une petite routine relogeable est copiée en #4000 (RAM déjà validée), sauvegarde le bloc #8000-#87FF en #4800, le teste avec les mêmes algorithmes, puis le restaure.

## Tests (couleur du bord)
| N° | Bord | Test | Ce qu'il détecte |
|---|---|---|---|
| 1 | bleu | 8 motifs fixes `00 FF 55 AA 33 CC 0F F0` : tout remplir puis tout relire | bits collés, lignes de données |
| 2 | magenta | adresse dans adresse : octet = `L xor H`, puis inverse | lignes d'adresse, multiplexeurs 74LS153, alias |
| 3 | cyan | March C- : `↑w0 ↑(r0,w1) ↑(r1,w0) ↓(r0,w1) ↓(r1,w0) r0` | cellules collées, couplages, transitions |
| 4 | jaune | pseudo-aléatoire (LFSR 16 bits, graine différente à chaque passe) | défauts dépendant des données |
| 5 | orange | rétention : `55` puis `AA`, attente ~4 s, relecture | cellules qui fuient, rafraîchissement |
| 6 | blanc | bloc du programme #8000-#87FF (versions courtes de 1 à 5) | — |
| — | vert | passe OK (~1 min) | — |
| — | **rouge** | **erreur** | — |

## Écran d'erreur
Test, passe, **adresse**, attendu, lu, **XOR** et liste des **bits faux (D0-D7)**.
Sur le 464, chaque 4164 porte un bit de données : le bit fautif désigne le boîtier (voir le schéma de la carte pour la correspondance bit → IC).

## Limites
- Ne teste pas la RAM paginée / extension → **MEMTEST**.
- Si la machine plante sans message : le bloc #8000-#87FF lui-même est suspect (déplacer `BLK`).
