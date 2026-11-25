# LEAKTEST — fuites de l'extension vers la RAM de base

**Fichier :** `leaktest.asm` + `cpclib.asm` · **Binaire :** `LEAKTEST.BIN`

## Question posée
Quand on écrit dans une page d'extension (config `&C4` par défaut, constante `LT_CFG`), la **RAM interne** (#4000-#7FFF en C0) reçoit-elle aussi l'écriture ? Et **dans quelles conditions** : rafales avec la page déjà sélectionnée, ou écriture **juste après** l'OUT de sélection ?

Origine : MEMTEST signale une fuite (test 0B) après des rafales PUSH sur la page &C4 d'un 464 avec PicoCPC (octets de base remis à &00 = valeur du premier motif PUSH).

## Déroulement
La RAM de base #4000-#7FFF contient un motif de référence (`L xor H xor #3C`). Pour chaque scénario :
1. **pré-remplissage lent** de la page avec `~V` (page fixe), puis contrôle de la base → statistiques de la ligne 0 ;
2. le **scénario** écrit `V` dans toute la page ;
3. contrôle de la page (**Perdu** = octet qui n'a pas reçu V) et de la base (**Fuite** = octet de base modifié, aussitôt réparé).

`V` change à chaque boucle : `#00`, `#FF`, `#55`, `#AA`.

## Scénarios
| Ligne | Scénario | Accès |
|---|---|---|
| 0 | Remplissage lent (référence) | `LD (HL),A` en boucle (~1 écriture / 9 µs), page fixe |
| 1 | PUSH déroulés | 8 192 PUSH (2 écritures consécutives sans lecture d'instruction), page fixe |
| 2 | LDI déroulés | 8 Ko copiés dans la page (lecture + écriture), page fixe |
| 3 | LD (HL),A déroulés | ~1 écriture / 3 µs, page fixe |
| 4 | OUT + écriture immédiate | pour chaque octet : `OUT page`, `LD (HL),A`, `OUT C0` |
| 5 | OUT + 4 NOP + écriture | idem avec ~4 µs entre la sélection et l'écriture |
| 6 | OUT + PUSH immédiat | `OUT page`, `PUSH`, `OUT C0` (×8 192) |

## Écran
Colonnes : **Iter** (nombre de passages), **Fuite** (octets de base modifiés, cumul), **Adr.** et **Lu** (dernière fuite : adresse, valeur lue), **Perdu** (octets non reçus par la page, cumul). Valeurs en hexadécimal. La ligne 0 n'a pas de colonne « Perdu » significative, et son **Iter** augmente 6 fois plus vite que les autres (un pré-remplissage avant chacun des 6 scénarios).

## Interpréter
| Observation | Conclusion probable |
|---|---|
| Fuites en 1 (et 6), pas en 0/3/4/5 | les **écritures consécutives** (PUSH) sont mal gérées par l'extension, page déjà sélectionnée |
| Fuites ou pertes en 4 mais pas en 5 | **sélection de page trop lente** : l'écriture arrive avant que la nouvelle config soit active |
| Pertes en 4/6 sans fuites | écriture perdue (ni base ni page) au moment du changement de page |
| Fuites partout, même en 0 | décodage, signal RAMDIS ou **connecteur** |
| Valeur lue = V | c'est bien l'écriture du scénario qui fuit |

## Utilisation
Laisser tourner quelques minutes et relever le tableau. Refaire après nettoyage du connecteur d'extension, puis sur un autre CPC si possible. Le tableau est directement transmissible au développeur de l'extension.
