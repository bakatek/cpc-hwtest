# MAPTEST — configurations C1 / C3, écriture sous ROM, exécution

**Fichier :** `maptest.asm` + `cpclib.asm` · **Binaire :** `MAPTEST.BIN`

## Question posée
Les configurations RAM `&C1` et `&C3`, et les écritures faites pendant qu'une ROM masque la RAM, se comportent-elles comme sur un 6128 ? On regarde en particulier deux cas :
- **C3 sur 464.** En C3, la page de base 3 (celle de l'écran, `#C000`) apparaît aussi en `#4000`. Le 464 n'a pas cette configuration, c'est l'extension (PicoCPC…) qui l'émule. Ce qu'on écrit par `#4000` en C3 doit ensuite se relire par `#C000` en C0, et inversement.
- **Écriture sous ROM.** Une écriture en `#C000-#FFFF` va à la RAM même quand la ROM haute est active (par exemple un `POKE` du BASIC en C1). En C1, cette RAM est la page 7 de l'extension.

Ces cas ne sont pas couverts par MEMTEST. Son test 08 lit et écrit les modes C1/C3 par une seule fenêtre, avec les ROM coupées.

**Origine.** La démo *Batman Forever* plantait sur un 464 avec PicoCPC, toujours au même endroit :
- son chargeur lit la disquette en C3 et écrit les secteurs par `#4000` ;
- elle décompresse ensuite ces données en C0, en les relisant par `#C000`.

La PicoCPC ne voyait pas ces écritures en C3. Elle les prenait pour des lectures : son signal /RD forcé tôt dans le cycle (protection de la DRAM du 464) masquait le vrai sens du cycle. Le décompresseur relisait donc d'anciennes données et produisait du code faux.

Le même mécanisme faisait perdre les écritures dans la page 7 en C1 quand la ROM haute était active. Exemple : `OUT &7F00,&C1:POKE &F9D0,x` depuis le BASIC.

## Déroulement
L'écran est en page 3 (`#C000`) : pour ne pas l'abîmer, les tests sur la page 3 n'utilisent que les **48 octets non affichés** à la fin de chaque bloc de 2 Ko : `#C7D0-#C7FF`, `#CFD0-#CFFF`, …, `#FFD0-#FFFF`, soit **384 octets**. En C3, ils sont vus en `#47D0`, `#4FD0`, …, `#7FD0`.

Interruptions coupées, ROM coupées sauf pour les lignes 4 et 5. Chaque passe fait **16 tours**, avec une valeur différente à chaque tour (`L xor clé`, la clé change à chaque tour). Une écriture perdue laisse donc la valeur du tour précédent et se voit tout de suite.

| Ligne | Test | Ce qui est fait | Ce qui est vérifié |
|---|---|---|---|
| 0 | C3 écr. `#4000` → C0 lect. `#C000` | En C3, `LD (HL),A` sur les 384 octets vus en `#47D0…` | Relus en C0 par `#C7D0…` : la page 3 a bien reçu les écritures |
| 1 | C3 écr. : fuite RAM base page 1 | Avant la ligne 0, la page de base 1 (`#47D0…` en C0) reçoit un motif de référence | Après les écritures C3, la page 1 n'a pas bougé (sur un 464, l'écriture ne doit pas aller dans la DRAM de la page 1) |
| 2 | C3 PUSH → C0 | En C3, 24 PUSH par bloc (48 octets), valeur constante | Relus en C0 par `#C000` (rafales d'écritures sans lecture d'instruction entre elles) |
| 3 | C0 écr. `#C000` → C3 lect. `#4000` | En C0, écriture par `#C7D0…` | Relus en C3 par `#47D0…` |
| 4 | C1, ROM haute active : écriture page 7 | Mode `&86` (ROM haute active), C1, écriture en `#C7D0…` (sous la ROM) | ROM coupées, C7 : relus par `#47D0…` dans la page 7. **Demande une extension.** |
| 5 | C1, ROM haute : fuite base page 3 | Avant la ligne 4, les octets cachés de l'écran (`#C7D0…` en C0) reçoivent la référence | Ils n'ont pas bougé : l'écriture en page 7 ne doit pas toucher la page de base 3 |
| 6 | C1 : exécution de la page 7 en `#C000` | Une petite routine (`LD HL,0 / LD B,n / INC HL / DJNZ / LD (#9F00),HL / RET`) est écrite par `#47D0` en C7, puis appelée en `#C7D0` en C1, ROM coupées | `#9F00` = n (n change à chaque tour). **Demande une extension.** |
| 7 | C3 : exécution de la page 3 en `#4000` | La routine est écrite en C0 par `#CFD0`, puis appelée en C3 par `#4FD0` | Résultat = n |
| 8 | C3 écr. du code → exécution en C0 | La routine est écrite en C3 par `#57D0`, puis appelée en C0 par `#D7D0` | Résultat = n (le cas de *Batman Forever*) |

L'ordre réel d'un tour est : 4-5, 6, 0-1, 2, 3, 7, 8. Les lignes 4 et 5 passent en premier, car sur une PicoCPC/464 la page 3 est ensuite servie par la PicoCPC (voir Limites).

## Écran
Pour chaque ligne :
- **ERR** : nombre d'erreurs cumulé (saturé à `FFFF`) ;
- **ADR** : adresse de la dernière erreur ;
- **ATT** : valeur attendue ;
- **LU** : valeur lue.

Pour les lignes 6 à 8, **ADR** est l'adresse d'appel de la routine, et **LU** l'octet bas du résultat. Le numéro de passe s'affiche en haut à droite.

Bord **vert** : tout est à 0. Bord **rouge** : au moins une erreur. Sans extension, les lignes 4 à 6 affichent `--`.

Si une routine exécutée (lignes 6 à 8) est fausse, le programme peut planter au lieu de compter l'erreur. Un plantage juste après le lancement désigne donc ces lignes.

## Interpréter
| Observation | Conclusion probable |
|---|---|
| Erreurs en 0, 2 et 8, rien en 3 et 7 | Les **écritures en C3** ne sont pas vues par l'extension : elle les prend pour des lectures. Sur PicoCPC : /RD (GPIO32) forcé avant que le PIO du bus ait relevé le sens du cycle. |
| Erreurs en 1 | Les écritures C3 **atteignent la DRAM de la page 1** du 464 : l'extension ne bloque pas l'écriture interne (GPIO32 forcé trop tard). |
| Erreurs en 4, ligne 5 à 0 | Écriture sous la ROM haute **perdue** : pendant le cycle, le CPC croit à une lecture et allume sa ROM, ou l'extension sert la ROM au lieu d'écrire. |
| Erreurs en 5 | L'écriture en page 7 a aussi modifié la **page de base 3** (fuite, connecteur, RAMDIS). |
| Erreurs en 6 seulement | Les cycles M1 dans la page 7 en `#C000` sont trop lents ou mal servis. |
| Erreurs en 3 ou 7 | La **lecture** C3 émulée est fausse (copie de la page 3 non à jour). |
| Erreurs rares (quelques-unes par passe) | Problème de **timing** à la limite : regarder les marges (PicoCPC : commande `RDW`). |

## Résultats de référence (PicoCPC, 464, 27/11/2026)
| Firmware | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|---|
| Avant correction (`RDW 2` : /RD relevé à 69 ns) | `07A8` | 0 | `05D7` | 0 | `0008` | 0 | 0 | 0 | `0003` |
| Après correction (/RD relevé à 47 ns, GPIO32 forcé après) | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

## Limites
- **Couverture de la page 3.** Seuls 384 octets de la page 3 sont testés (ceux que l'écran n'affiche pas). Une erreur de timing touche n'importe quelle adresse, donc ces octets suffisent à la voir.
- **Ligne 5 sur PicoCPC/464.** Dès la première écriture en C3, la PicoCPC sert elle-même les lectures de la page 3. La DRAM de cette page peut en effet être en retard sur sa copie. La ligne 5 relit alors cette copie, pas la DRAM : elle ne mesure vraiment la DRAM qu'au premier tour de la première passe. L'écran, lui, montre toujours la DRAM.
- **ROM basse non testée.** L'écriture sous la ROM basse n'est pas testée : il faudrait la configuration C2, qui remplace aussi la zone du programme.
