# CARTTEST — cartouche (CPR) : lecture, exécution, pagination

**Fichiers :** `carttest.asm` (+ `cartfont.asm`), assemblé via `cart128.asm`, `cart256.asm` ou `cart512.asm` · **Cartouches :** `CART128.CPR`, `CART256.CPR`, `CART512.CPR`

## Pourquoi
Sur CPC+, des cartouches émulées par la PicoCPC plantent de façon aléatoire (Pang, et surtout Sonic). Un jeu en cartouche **exécute son code directement depuis la ROM**, avec les interruptions actives, et change de page en permanence. Ce sont les accès les plus sensibles au timing pour une émulation :
- le **cycle M1** (lecture d'instruction) laisse moins de temps que la lecture d'une donnée ;
- une lecture qui suit **immédiatement** un `OUT &DFxx` (changement de page) ne laisse presque aucun délai.

CARTTEST **est lui-même une cartouche** : il démarre seul, sans firmware, et son code tourne depuis la cartouche, exactement comme un jeu. Le contenu de chaque page est connu, donc **chaque octet lu est vérifié**.

## Tailles
| Fichier | Taille | Correspond à |
|---|---|---|
| `CART128.CPR` | 128 Ko (8 pages) | les cartouches d'origine (Pang, Burnin' Rubber…) |
| `CART256.CPR` | 256 Ko (16 pages) | cartouches homebrew moyennes |
| `CART512.CPR` | 512 Ko (32 pages) | **maximum** adressable par `&DF #80`–`#9F`, utilisé par les grosses cartouches homebrew |

Commencer par **CART512** : c'est le pire cas, car toutes les pages existent et sont toutes testées.

## Lancement
Charger le `.CPR` comme une cartouche (PicoCPC : dossier des cartouches, `CCAT` / `CRUN`). L'écran s'affiche immédiatement en mode 2.

Il fonctionne sur **CPC+ / GX4000**, et sur **tout CPC** dont la cartouche est émulée. Si l'ASIC n'est pas détecté (CPC classique), les tests 6 et 7 sont sautés et l'écran l'indique.

## Tests (en boucle)
| N° | Test | Détail |
|---|---|---|
| 1 | **Signatures** | Chaque valeur `&DF #80+p` (p = 0–31) est sélectionnée et la signature de la page est lue. Résultat : carte `O` présente, `M` miroir (cartouche plus petite que 512 Ko), `.` absente, `!` erreur. Une page sous la taille de la cartouche doit être présente, et la carte ne doit jamais changer d'une passe à l'autre. |
| 2 | **Lecture** | `LD A,(HL)` sur les 15 Ko de données de chaque page, comparées au LFSR. Pour la page 0, la vue ROM basse (`#0000`) est comparée à la vue ROM haute (`#C000`). |
| 3 | **Rafales** | 4 096 LDI déroulés (ROM → RAM) puis vérification, et somme des 15 Ko par 7 552 POP. Les interruptions sont coupées pendant les POP, comme dans un jeu qui lit des données par la pile. |
| 4 | **Exécution (M1)** | Une routine pleine de préfixes CB/DD/ED/FD qui utilise la pile est **exécutée depuis la cartouche**, à `#FC00`, `#FD00`, `#FE00` et `#FF00` de chaque page, avec 32 graines. Deux variantes : page déjà sélectionnée, ou `OUT &DF` suivi d'un **saut immédiat** dans la page. Le résultat est comparé à la même routine exécutée en RAM. |
| 5 | **Commutation rapide** | Pour chaque octet de `#C020`–`#C0FF`, on passe par toutes les pages : `OUT &DF` puis lecture **immédiate**. |
| 6 | **RMR2** (CPC+) | Pages 0 à 7 mises en ROM basse à `#0000`, `#4000` et `#8000` : signature, données et exécution des 4 copies de la routine. Ce test tourne depuis la RAM, puisque la ROM basse se déplace. |
| 7 | **Mappage `&DF`** (CPC+) | `&DF 0` et `&DF #21` doivent donner la page 1, `&DF 7` la page 3 (compatibilité BASIC / AMSDOS). |
| 8 | **Interruptions** | La routine d'interruption est **dans la cartouche** (`#0038`). Il doit y en avoir exactement 6 par trame, comptées entre deux VSYNC. |

## Écran
- Carte des 32 pages et un compteur d'erreurs par test (hexadécimal).
- `PASSES`, `TRAMES` (50 par seconde) et `INT/TRAME` (doit valoir `06`).
- **Dernière erreur** : test, page (ou valeur `&DF`), adresse, valeur attendue, valeur lue.
- **EN COURS : TEST n PAGE &pp** : si la machine plante, cette ligne indique ce qui tournait à ce moment-là.
- **Coin en haut à droite** : il clignote tant que les interruptions tournent. S'il est figé, la machine a planté.
- Bord **vert** = aucune erreur, **rouge** = au moins une erreur. Le test continue après une erreur pour pouvoir compter.

## Interpréter
| Observation | Piste |
|---|---|
| Plantage (écran figé), `EN COURS` sur le test 4 | lectures d'instruction (M1) depuis la cartouche trop lentes ou fausses |
| Erreurs au test 5, pas au test 2 | l'émulation réagit trop lentement au changement de page `&DF` |
| Erreurs au test 3 seulement | accès consécutifs rapides (LDI, POP) mal servis |
| Erreurs au test 8 | interruptions perdues ou en trop pendant l'exécution en cartouche |
| Erreurs aux tests 6 et 7 seulement | gestion de RMR2 ou de la compatibilité `&DF` de l'ASIC |
| Carte instable (test 1) | sélection de page `&DF` peu fiable |

## Organisation d'une page (p ≥ 1, vue en `#C000`)
| Zone | Contenu |
|---|---|
| `#C000`–`#C00F` | `#FF` |
| `#C010`–`#C01F` | signature : `"CARTTEST"`, p, 255−p, nombre de pages, version, `#5A`, `#A5`, 0, p |
| `#C020`–`#C0FF` | octet = (adresse basse) xor p xor `#A5` (test 5) |
| `#C100`–`#FBFF` | 15 Ko pseudo-aléatoires : LFSR 16 bits de Galois (`#B400`), graine `#5A3C` xor (p × `#101`) |
| `#FC00`–`#FFFF` | 4 copies de la routine d'exécution, une tous les 256 octets |

La page 0 contient le programme. Il porte la même signature en `#0010`, et sa fonte (dessin original, majuscules) est en `#3900`.

## Limites et validation
- Le test n'a été validé **ni sur un CPC+ réel ni dans un émulateur Plus**. Le contenu des `.CPR` produits a été vérifié par un script indépendant (format RIFF, signatures, données, copies de la routine). Les registres du Plus (`&DF`, RMR2, déverrouillage de l'ASIC) suivent ceux de l'émulateur Caprice32.
- À valider de préférence d'abord dans un émulateur Plus (ACE-DL, Caprice32, WinAPE), où le résultat attendu est : 0 erreur partout et `INT/TRAME` à `06`.
- Les cartouches de plus de 512 Ko, qui utilisent des mappers non standard, ne sont pas couvertes.
