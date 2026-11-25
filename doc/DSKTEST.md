# DSKTEST — accès disquette, cas limites (FDC µPD765)

**Fichiers :** `dsktest.asm` + `cpclib.asm`, `mkdsktest.py` · **Produits :** `DSKTEST.BIN`, disquette de test `DSKTEST.DSK`

## But
Vérifier que les accès au contrôleur de disquette, **réel ou émulé** (PicoCPC…), se comportent comme sur un vrai 765, y compris dans les cas que les jeux, les démos et les protections utilisent : formats non standard, secteurs effacés, erreurs CRC, lectures à vitesse maximale. **Lecture seule** : la disquette n'est jamais modifiée.

Le contrôleur est piloté directement (port moteur `&FA7E`, registre d'état `&FB7E`, registre de données `&FB7F`), sans AMSDOS et interruptions coupées. Toutes les attentes ont un **délai maximum** : un contrôleur qui ne répond plus est compté comme une erreur, au lieu de figer la machine.

## Lancement
1. Mettre `DSKTEST.DSK` dans le lecteur **A:** (PicoCPC : `|DLOAD`).
2. `RUN"DSKTEST.BIN"` (ou `MEMORY &7FFF:LOAD"DSKTEST.BIN",&8000:CALL &8000`).

Il fonctionne sur tout CPC qui a un contrôleur de disquette : 6128, 464 avec DDI-1, 6128+, 464+ avec lecteur externe. Sans contrôleur (GX4000, 464 nu), un message l'indique.

## La disquette de test
`mkdsktest.py` fabrique une image EDSK de 42 pistes au format DATA d'AMSDOS, avec `DSKTEST.BIN` dans le catalogue. Les données de chaque secteur sont connues : LFSR de graine ((piste << 8) | R) xor `#A55A`.

| Piste | Contenu |
|---|---|
| 0–1 | catalogue + `DSKTEST.BIN` |
| 20 | format DATA standard, 9 × 512 (`#C1`–`#C9`) |
| 21 | **10 secteurs** de 512 (`#C1`–`#CA`) |
| 22 | **tailles** 128, 256, 512, 1024, 2048 (R = 1–5, N = 0–4) |
| 23 | un secteur de **4 Ko** (R = `#51`, N = 5) |
| 24 | **IDs non standard** : C ≠ piste (`#2A`), C/H/R = `#FF`, H = 1 sur la face 0, R = 0, C/H/R = `#80` |
| 25 | `#C2` et `#C4` marqués **effacés** (deleted data) |
| 26 | `#C2` avec une **erreur CRC** sur les données |
| 27 | **non formatée** |
| 40–41 | format DATA standard, **au-delà des 40 pistes** |

## Tests (en boucle)
| N° | Test | Attendu |
|---|---|---|
| 1 | Recalibrage, puis seek vers 20, 41, 0, 39, 1, 27, 40, 2, 20 | PCN = piste demandée (info : ST3 indique la piste 0 après le recalibrage) |
| 2 | Piste 20 lue d'un coup (`#C1`→`#C9`), puis un secteur isolé | données exactes, aucun bit d'erreur |
| 3 | Piste 20 entière, 4 fois de suite, avec la boucle de lecture la plus rapide (façon chargeur de démo) | idem |
| 4 | 10 secteurs en une commande | idem |
| 5 | Tailles 128 à 2048 | idem |
| 6 | Secteur de 4 Ko | idem |
| 7 | IDs non standard (la commande donne C, H, R, N de l'ID) | idem |
| 8 | READ DATA sur un secteur effacé, READ DELETED DATA sur un secteur effacé et sur un normal | données lues ; ST2 bit 6 (CM) = 1, 0, 1 |
| 9 | Secteur avec erreur CRC | ST0 = `#40`, ST1 bit 5 (DE), ST2 bit 5 (DD) ; secteurs voisins normaux |
| A | Secteur `#D5` inexistant | ST0 = `#40`, ST1 bit 2 (ND) |
| B | Piste 27 non formatée | ST0 = `#40` (info : ST1 bit 0, MA) |
| C | READ ID sur les pistes 20 et 24 | sans erreur ; C = 20, N = 2, R dans `#C1`–`#C9` |
| D | Pistes 40 et 41 | lecture complète exacte |
| E | **Overrun** : lecture volontairement trop lente (~60 µs par octet) | un vrai 765 s'arrête avec ST1 bit 4 (OR), sinon INFO ; ne pas finir du tout = ERREUR |
| F | Commande invalide (`#1F`) | un seul octet de résultat, `#80` |

## ERREURS et INFO
- **ERREURS** : données fausses, bits d'erreur inattendus, résultat absent, ou contrôleur qui ne répond plus. Un logiciel qui fait ce type d'accès échouera ou plantera.
- **INFO** : écart avec un vrai 765 qui ne gêne pas les logiciels courants mais peut gêner une protection. Exemples : lecture terminée sans le bit EN (sur un vrai CPC, toute lecture se termine par ST0 = `#40`, ST1 = `#80`, car le signal TC n'est pas câblé), overrun non simulé, MA absent sur une piste vierge.

## Écran
Une ligne par test (erreurs, info), le nombre de passes, la **dernière erreur** (test, piste, secteur, ST0 ST1 ST2, puis position dans le tampon, attendu, lu ; position `FFFF` = contrôleur bloqué) et **EN COURS** (test qui tournait si la machine se fige). Bord vert = aucune erreur, rouge = erreur.

## Reconstruire la disquette
```sh
cd src && rasm dsktest.asm && python3 mkdsktest.py DSKTEST.BIN DSKTEST.DSK
```
Le script et la table `dk_tab` de `dsktest.asm` doivent rester cohérents.

## Limites et validation
- Ce test n'a pas encore tourné sur une machine ni dans un émulateur. La disquette produite a été relue par un analyseur indépendant (catalogue, fichier, données, IDs), et chaque entrée de la table a été recoupée avec les secteurs réellement présents.
- Pas d'écriture ni de formatage, et une seule face.
- Le secteur « taille 6 » des protections (8 Ko qui débordent sur l'index) et les secteurs « faibles » ne sont pas testés : sur un vrai lecteur, leur résultat n'est pas reproductible.
