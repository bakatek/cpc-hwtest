# Firmware de test PicoCPC `pioglitch4`

Firmware de **test** pour la carte PicoCPC (RP2350B). Les programmes [GLITCH](../../doc/GLITCH.md), GLITCH256 et [PINMAP](../../doc/PINMAP.md) en ont besoin. Ce n'est **pas** un firmware d'usage courant : après les tests, reflasher le firmware habituel de la PicoCPC.

| Fichier | Contenu |
|---|---|
| `20261121-1.02-PicoCPC-sp1819-pioglitch4.uf2` | Firmware PicoCPC 1.02 (sp1819) avec le correctif **debounce1** et l'analyseur de rebonds. |

## Ce que le firmware ajoute
- **Analyseur PIO** sur GPIO0-31 : un échantillon toutes les 11,1 ns, anneau DMA de 91 µs. L'automate du bus continue de tourner pendant la mesure.
- **GPIO32-47** lues par le core0 pendant la mesure, environ toutes les 3 à 10 ns. La période réelle est donnée dans le résultat.
- **Correctif debounce1** : RAMDIS piloté par le core1 et insensible aux creux de MREQ de 11 ns, cause des fuites de RAM d'extension sur 464. Il est sans risque sur un CPC+.
- Le **test du port** tourne au démarrage.
- Les **commandes** passent par le port `&FBF2` :
  - `&E8` arme la mesure ;
  - `&E9` la fige et l'analyse ;
  - `&EA` remet les compteurs à zéro ;
  - `&EB` / `&EC` lisent le résultat ;
  - `&80`-`&8F` donnent l'activité en cours.

  Voir le détail dans [doc/GLITCH.md](../../doc/GLITCH.md).

## Installation
1. Débrancher la PicoCPC du CPC.
2. Maintenir **BOOTSEL** et brancher l'USB de la Pico : un disque `RP2350` apparaît.
3. Copier le `.uf2` sur ce disque : la Pico redémarre seule.
4. Rebrancher sur le CPC, puis lancer depuis le BASIC :
   ```
   MEMORY &7FFF:LOAD"GLITCH.BIN",&8000:CALL &8000
   MEMORY &7FFF:LOAD"GLITCH256.BIN",&8000:CALL &8000
   MEMORY &7FFF:LOAD"PINMAP.BIN",&8000:CALL &8000
   ```

Laisser GLITCH tourner au moins 200 passes, puis photographier l'écran.

## Validation
- **En émulation** (code ARM réel, sur des traces de 464 et de 6128) : tous les compteurs, y compris la position des rebonds par rapport au cycle Z80, sont identiques à une référence Python, rebonds injectés compris. Le test du port et le mode ombre passent.
- **Sur machine (464, 26/11/2026)** : le correctif debounce1 a été validé par LEAKTEST, 10 minutes sans fuite. L'affichage v4 de GLITCH n'a pas encore été relevé sur machine.

Une variante `-orig`, avec le RAMDIS d'origine **sans debounce**, a servi aux comparaisons pendant la mise au point. Elle n'est pas fournie : elle a le bug des fuites de RAM d'extension.

## Pour un autre firmware
[AJOUTER_AU_FIRMWARE.md](AJOUTER_AU_FIRMWARE.md) explique comment ajouter la même capture à son propre firmware PicoCPC : commandes, PIO, DMA, analyse, format du résultat.
