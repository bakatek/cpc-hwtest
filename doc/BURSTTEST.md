# BURSTTEST — accès bus à vitesse maximale

**Fichier :** `bursttest.asm` + `cpclib.asm` · **Binaire :** `BURSTTEST.BIN`

## But
Reproduire les accès « en rafale » des démos (là où une machine limite décroche) et vérifier le résultat de chacun. DI pendant tout le test.

## Étapes de chaque boucle
| Étape | Détail | Compteur |
|---|---|---|
| 1 | **4 096 LDI déroulés** : #4000 → #5000 (4 Ko pseudo-aléatoires), puis comparaison | ERREURS copie LDI |
| 2 | **PUSH blast** : SP = #C000, 6 144 PUSH déroulés remplissent #9000-#BFFF (motif 16 bits différent à chaque boucle), puis **6 144 POP** relisent et comparent | ERREURS PUSH/POP |
| 3 | **Lecture POP** : somme de la source par 2 048 POP, comparée à la référence | ERREURS lecture POP |
| 4 | **Rafales d'OUT** : GA (encres 2-15, mode) et CRTC (R12/R13) réécrits avec les mêmes valeurs | — |
| 5 | **PSG** : registres 0-7, 11, 12 de l'AY écrits avec des valeurs aléatoires puis **relus** via le PPI ; volumes forcés à 0 (silence) | ERREURS relecture PSG |

Bord rouge dès qu'un compteur n'est plus nul.

## Interpréter
- **LDI / PUSH / POP** : la RAM ou le bus ne suit pas les accès consécutifs (timing GA, RAM limite, alimentation).
- **PSG** : chemin PPI ↔ AY (8255, AY-3-8912, pistes).

## Limite
Ne travaille que dans la RAM de base. Les rafales sur l'extension sont dans **MEMTEST** (test 09).
