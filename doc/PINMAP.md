# PINMAP — brochage du RP2350B de la PicoCPC

**Fichier :** `pinmap.asm` + `cpclib.asm` · **Binaire :** `PINMAP.BIN` · **Firmware requis :** [`pioglitch4`](../firmware/pioglitch4/README.md), ou `pioglitch2` / `pioglitch3`

```
MEMORY &7FFF:LOAD"PINMAP.BIN",&8000:CALL &8000
```

## Question posée
Comment le firmware de la PicoCPC configure-t-il réellement les 48 GPIO du RP2350B ? Pour chaque broche, on veut savoir :
- quelle **fonction** elle a : machine d'état PIO0/1/2, logiciel (SIO), I2C, SPI, UART, USB… ;
- si elle est **en sortie**.

Sert à vérifier le brochage du bus CPC (multiplexeur, données, commandes, ROMDIS/RAMDIS) et à repérer les GPIO libres ou pilotées par erreur. C'est un complément de [GLITCH](GLITCH.md) : une broche en sortie qui « rebondit » est pilotée, ce n'est pas du bruit.

## Déroulement
1. `&E8` sur le port `&FBF2` : arme une mesure de quelques ms, ce qui permet au firmware de relever le sens des broches.
   - Sans réponse : « PicoCPC absente ».
   - Réponse non nulle : « Il faut le firmware pioglitch4 ».
2. `&E9` fige la mesure, `&EC` revient au début du résultat. Le programme lit ensuite 68 octets par demi-octets (`&EB`). L'octet 0 doit valoir `'G'`.
3. Pour chacune des 48 broches, l'octet `20 + n` du résultat contient le **FUNCSEL** (bits 0-4) et le **sens vu en sortie** (bit 7).

Le programme n'écrit rien sur le bus du CPC, sauf les commandes vers `&FBF2`. Il s'arrête sur l'écran de résultat : on en sort par un reset.

## Écran
Trois colonnes de 16 lignes, une ligne par GPIO (`G00` à `G47`). Chaque ligne donne :
- le **nom de la fonction** : `HSTX`, `SPI`, `UART`, `I2C`, `PWM`, `SIO`, `PIO0`, `PIO1`, `PIO2`, `QMI/CK`, `USB`, `UARTAX`, ou `?` ;
- le numéro FUNCSEL brut en hexadécimal (`1F` = aucune fonction) ;
- **`e`** pour une entrée, **`S`** pour une broche vue en sortie ;
- le **rôle connu** sur la PicoCPC :
  - `mux0`, `mux1` (GPIO0-1) : sélection du multiplexeur du bus ;
  - `ROMDIS`, `RAMDIS` (GPIO2-3) ;
  - `bus0`-`bus7` (GPIO20-27) : sortie du multiplexeur (adresse ou données) ;
  - `RFSH`, `IORQ`, `MREQ`, `RD/WR` (GPIO28-31).

## Interpréter
| Observation | Signification |
|---|---|
| `bus0-7`, `RFSH`…`RD/WR` en `PIO0`, `e` | normal : le bus est lu par la machine d'état |
| `bus0-7` en `S` hors d'un cycle servi | la PicoCPC pilote les données : contention possible avec le CPC |
| `ROMDIS` / `RAMDIS` en `PIO1` ou `SIO`, `S` | normal : ce sont les sorties de la carte |
| Broche non câblée en `S` | pilotée inutilement : source possible de bruit |
| `1F` | aucune fonction : broche libre |

Le sens est relevé à un instant donné, pendant la mesure. Une broche de données qui passe en sortie seulement pendant les cycles servis peut apparaître `e` ou `S` selon le moment.
