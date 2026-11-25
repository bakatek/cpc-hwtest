# GATEST — stabilité du Gate Array

**Fichier :** `gatest.asm` + `cpclib.asm` · **Binaire :** `GATEST.BIN`

## But
Vérifier en continu les fonctions du Gate Array (40007 / 40010) que les démos sollicitent : génération des interruptions, écritures en rafale, pagination ROM, synchronisation par HALT. **Interruptions actives** pendant tout le test.

## Ce qui est fait à chaque boucle
1. **Rafale d'OUT** : 256 × (bord, encre 2, encre 3, registre de mode). Les bandes colorées dans le bord sont **normales**.
2. **Pagination ROM** : la ROM basse est activée par blocs de 32 octets (DI, très court) et la somme de #1000-#3FFF doit être identique à la référence.
3. **RAM sous la ROM** : ROM coupée, #1000-#3FFF doit garder son motif.
4. **12 HALT** (2 trames).

## Contrôle des interruptions
Le GA génère une interruption toutes les 52 lignes (300 Hz) et se **resynchronise sur la VSYNC**. Le programme lit la VSYNC sur le PPI (port B, bit 0) et compte les interruptions entre deux VSYNC : il doit y en avoir **exactement 6 par trame**.

## Écran (mis à jour toutes les 50 trames = 1 s)
| Ligne | Valeur attendue |
|---|---|
| Trames | augmente de 50/s |
| Interruptions | augmente de 300/s |
| INT dernière trame | **06** |
| ERREURS INT/TRAME | **0000** |
| ERREURS ROM basse | **0000** |
| ERREURS RAM sous ROM | **0000** |

Toute erreur → message en bas de l'écran.

## Interpréter
- **INT/TRAME** : interruptions perdues ou en trop → GA, horloge, CRTC (VSYNC).
- **ROM basse** : la ROM n'est pas lue correctement quand elle est activée → GA (signal ROMEN), ROM, bus, ou périphérique qui perturbe (ROMDIS).
- **RAM sous ROM** : la RAM est modifiée/mal lue → RAM ou décodage.
- **Plantage pur** (affichage figé) : instabilité grave (GA, alimentation, horloge).

## Historique
La première version pouvait se figer à cause d'un **bug du programme** (`LD A,I` sur Z80 NMOS) : corrigé, ne pas tenir compte des plantages de cette version.
