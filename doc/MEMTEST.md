# MEMTEST — RAM paginée et extensions (jusqu'à 512 Ko)

**Fichier :** `memtest.asm` + `cpclib.asm` · **Binaire :** `MEMTEST.BIN`

## But
Tester **toute la RAM accessible par les configurations `&7FC4` à `&7FFF`** : 64 Ko supplémentaires d'un 6128, extensions 64 Ko à 512 Ko, RAM **émulée** (PicoCPC…). Vérifier aussi qu'aucune écriture destinée à l'extension ne **fuit** dans la RAM interne, et que la RAM supporte les accès en **rafale** et l'**exécution de code**.

Complémentaire de **RAMTEST** (qui fait les 64 Ko de base). Pour valider toute la mémoire : passer les deux.

## Fonctionnement général
- DI, ROM coupées, pile en #BFFF, programme en #8000.
- Chaque page de 16 Ko est vue dans la **fenêtre #4000-#7FFF**.
- Page *p* (0-31) → config `#C4 + (p/4)*8 + (p and 3)` (banque dans les bits 3-5, page dans les bits 0-1).
- La RAM de base #4000-#7FFF (config C0) reçoit un **motif de référence** (`L xor H xor #3C`) : s'il change, c'est une **fuite**.

## 1. Détection (au démarrage)
1. Les pages 31 → 0 reçoivent chacune **16 signatures** (une tous les 1 Ko). Une page miroir est écrasée ensuite par la vraie.
2. Marque écrite dans la RAM de base aux mêmes endroits (si aucune extension ne répond, les signatures sont écrasées).
3. Relecture : **16/16** = page présente, **0/16** = absente, **entre les deux** = page **partielle** (panne).
4. **N** = dernière page vivante + 1, arrondi à la banque de 64 Ko. Tout ce qui est au-dessus = inexistant.
5. Un **trou** sous N (banque OK, KO, OK) ou une page partielle = **anomalie** : la page est **testée quand même** pour obtenir l'adresse et les bits fautifs.

Carte affichée : `O` OK · `!` anomalie · `.` absente.

## 2. Tests par page (martelage : on reste sur la page)
Pour chaque page, **`MX_ROUNDS` tours** (4 par défaut) d'affilée :

| N° | Test | Détail |
|---|---|---|
| 01 | motifs fixes | 8 motifs, remplissage complet puis relecture |
| 02 | adresse dans adresse | `L xor H xor masque`, masque = page xor (tour×#40), puis inverse |
| 03 | March C- | fond `#00` ou `#55` selon le tour |
| 04 | aléatoire | LFSR, graine = page, tour, passe |
| 05 | **fuite** | la RAM de base n'a pas bougé |

Puis, toujours sur la page :

| N° | Test | Détail |
|---|---|---|
| 09 | **rafales** | 8 192 PUSH déroulés (16 Ko) + relecture par 8 192 POP, 8 motifs 16 bits (`0000 FFFF 00FF FF00 5555 AAAA 33CC C33C`) ; puis 8 Ko copiés en **LDI déroulés** #4000→#6000 dans la page et comparés |
| 0A | **exécution de code** | une routine relogeable, pleine d'instructions préfixées (CB/DD/ED/FD) et utilisant la pile, est copiée en #4000, #5555, #6AAA, #7F00 et **exécutée depuis la page** avec 256 graines. Variante 1 : retour en C0 puis `OUT` vers la page et **saut immédiat** dedans. Variante 2 : **pile dans la page**. Résultat comparé à la même routine exécutée en RAM de base |
| 0B | fuite | contrôle juste après les PUSH/POP |
| 0C | fuite | après les LDI |
| 0D | fuite | après la copie (LDIR) de la routine |
| 0E | fuite | après l'exécution, pile en base |
| 0F | fuite | après l'exécution, pile dans la page |

## 3. Tests globaux (toutes les pages)
| N° | Test | Détail |
|---|---|---|
| 06 | croisé | toutes les pages remplies (LFSR propre à chaque page), puis toutes relues → écriture dans la mauvaise page |
| 07 | commutation rapide | pour chaque octet : `OUT` vers chaque page puis écriture **immédiate** ; même chose en lecture |
| 08 | modes C1 / C3 | la page 3 de l'extension doit apparaître en #C000 (C1 et C3) ; en C3, #4000 doit montrer la page de base 3 (l'écran). C2 n'est pas testé (il remplacerait le programme) |

## Écran d'erreur
N° de test (hexa) et nom, **config &7F** au moment de l'erreur, **adresse**, attendu, lu, XOR, **page testée**, passe.

## Interpréter
- **01-04** : défaut de la RAM de la page (ou de son décodage).
- **05, 0B-0F (fuite)** : une écriture vers l'extension modifie **aussi** la RAM interne → signal **RAMDIS** trop tardif ou mal transmis (émulation, faux contact du connecteur d'extension). Le n° indique quelle étape la provoque ; la valeur lue indique ce qui a été écrit (motif, opcode, adresse de retour…).
- **06** : alias entre pages (bits de banque mal décodés).
- **07** : temps de réaction au changement de page.
- **08** : logique des modes C1/C3.
- **09** : la RAM ne suit pas les accès en rafale.
- **0A** : la RAM répond juste en lecture de données mais **trop tard sur les cycles M1** (lecture d'instruction) → plantages de démos qui exécutent du code en banque. L'adresse affichée est celle de la copie de la routine.

## Durée
~30 s par page et par tour : 4 pages × 4 tours ≈ 2-3 min par passe ; nettement plus en 512 Ko. Réglable par `MX_ROUNDS`.

## Limites
- 512 Ko maximum (port `&7Fxx` seul). Les extensions 1-4 Mo qui utilisent les bits d'adresse A8-A10 ne sont pas couvertes.
- C2 non testé.
