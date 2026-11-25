# PWRTEST — alimentation sous charge

**Fichier :** `pwrtest.asm` + `cpclib.asm` · **Binaire :** `PWRTEST.BIN`

## But
Mettre la carte dans le cas de consommation le plus défavorable, en **fixe** et en **pulsé**, tout en vérifiant que la RAM ne perd aucune donnée. À faire **avec un oscilloscope sur le 5 V de la carte** (près de la RAM et du Gate Array).

## Charges cumulées
| Charge | Comment |
|---|---|
| **Moteur K7** | bit 4 du port C du PPI. **Appuyer sur PLAY sans cassette** (10 s au démarrage). C'est la plus grosse charge du 464. |
| **Son** | 3 voies AY en carré ~110 Hz, en phase, volume 15 (molette du 464 à fond) : ampli du haut-parleur interne. |
| **CPU + RAM** | en continu : 8 192 PUSH (16 Ko), LDIR 16 Ko vers l'écran, relecture par 8 192 POP. Données `#FF00` / `#00FF` : chaque ligne du bus bascule à chaque accès. |
| **Écran** | 16 encres + bord en blanc vif (effet faible sur la carte si le moniteur est alimenté à part). |

## Deux régimes (alternance toutes les ~8 s)
- **Fixe** : tout allumé.
- **Pulsé** : moteur + son coupés/allumés ~2 Hz → appels de courant brusques (pire cas pour le régulateur, les câbles et les condensateurs de découplage).

## Écran
Pendant la charge l'écran est blanc. Toutes les ~16 s : écran d'état 2 s (nombre de boucles, bord vert). Erreur RAM → arrêt, moteur et son coupés, bord rouge, adresse / attendu / lu.

## Interpréter
- Passe sans erreur mais ondulation importante sur le 5 V (> 100-150 mV) ou creux lors des pulses : alimentation / câble / connecteur limite.
- Erreur RAM seulement en régime pulsé : découplage ou chute de tension.
