# ADR-047 — Tone mapping des vidéos HDR

## Statut
Proposé

Complète [ADR-008](ADR-008-pipeline-video-hls.md) (transcodage HLS), sans le remplacer.

## Contexte
Les iPhone filment en HDR par défaut : HEVC 10 bits, primaires BT.2020, transfert HLG (Dolby Vision 8.4, dont la couche de base est en HLG). Le worker produit du H.264 8 bits 4:2:0 lisible partout (ADR-008). Il convertissait les pixels en 8 bits sans tenir compte de leur couleur, et recopiait les étiquettes de la source.

Résultat, mesuré sur une mire convertie en HDR (blanc à 203 nits, comme le recommande BT.2408) : des couleurs délavées et grisâtres, avec un écart (PSNR) de 8 à 10 dB avec la mire d'origine. C'était une limite documentée : « HDR converti en SDR sans tone mapping ».

## Décision
- **Détection** : `probe` lit le transfert de la piste vidéo (ffprobe `color_transfer`). **PQ** (`smpte2084` : HDR10, Dolby Vision 5) ou **HLG** (`arib-std-b67` : iPhone) → `MediaInfo.hdr`. Les autres vidéos ne changent pas.
- **Chaîne de filtres** (`TONE_MAPPING_FILTER`, `media/ffmpeg.ts`) : `zscale` passe en lumière linéaire (`npl=100` : 100 nits = blanc SDR), puis convertit les primaires en BT.709 ; `tonemap=mobius` (sans désaturation) ; `zscale` applique ensuite le transfert et la matrice BT.709 en plage limitée, et la sortie est en 8 bits 4:2:0.
  - Appliquée **une seule fois** avant la déclinaison en résolutions (`split`), et à la miniature (mêmes couleurs).
  - Les fichiers tone mappés sont **étiquetés BT.709** (`-color_primaries`, `-color_trc`, `-colorspace`), au lieu de recopier les étiquettes HDR de la source.
- **Opérateur `mobius`** (choix argumenté par mesure) : il garde intacts les tons moyens, sous environ 30 % du blanc, et compresse en douceur les hautes lumières. Écart avec la mire d'origine (blanc à 203 nits) :

| Conversion | PQ | HLG |
|---|---|---|
| Sans tone mapping (avant) | 8,4 dB | 10,2 dB |
| `hable` | 15,0 dB | 15,0 dB |
| `reinhard` | 20,0 dB | 19,9 dB |
| `mobius` | 21,9 dB | 21,6 dB |
| `clip` | 23,1 dB | 22,7 dB |

  `clip` gagne de peu, mais seulement parce que la mire n'a pas de reflet au-dessus du blanc. Sur une vraie vidéo HDR, il écrase les reflets (jusqu'à 1000 nits) en aplats blancs.
- **FFmpeg** : `zscale` exige une compilation avec zimg. Elle est vérifiée sur les trois FFmpeg utilisés, qui ont aussi `tonemap` :

| FFmpeg | Version | Écart (même vidéo PQ) |
|---|---|---|
| Homebrew (développement) | 8.0.1 | 21,8 dB |
| Alpine (image Docker du worker) | 8.1.2 | 21,8 dB |
| Ubuntu 24.04 (CI) | 6.1.1 | 21,8 dB |

- **Filtres absents** (choix du développeur) : le worker les cherche au démarrage (`supportsToneMapping`, `ffmpeg -filters`). S'ils manquent, il démarre quand même, signale un avertissement dans ses journaux, et convertit les vidéos HDR comme avant : des couleurs ternes valent mieux qu'aucune vidéo.

## Alternatives
- **`libplacebo`** (tone mapping BT.2390, de meilleure qualité) : il exige Vulkan, donc un GPU ou un rendu logiciel lent dans un conteneur. Écarté.
- **Opérateurs `hable` ou `reinhard`** : `hable` assombrit nettement l'image, `reinhard` est moins fidèle que `mobius` (voir le tableau). Écartés.
- **Garder la vidéo en HDR** (HEVC 10 bits ou H.264 High 10 en HLS) : les couleurs seraient exactes sur un écran HDR, mais le H.264 10 bits n'est pas décodé matériellement par les iPhone. Il faudrait une seconde échelle HEVC, ce qui doublerait le stockage et le temps de transcodage. Écarté pour l'instant.
- **Refuser de démarrer sans les filtres** : cohérent avec l'arrêt quand FFmpeg manque, mais tout s'arrêterait pour un défaut qui ne touche que les couleurs des vidéos HDR. Écarté.

## Conséquences
### Positives
- Les vidéos HDR d'iPhone gardent leurs couleurs dans le feed et dans les miniatures.
- Les fichiers produits sont correctement étiquetés BT.709.
- Aucune dépendance nouvelle : les trois FFmpeg ont déjà les filtres.

### Négatives
- Transcodage un peu plus long pour une vidéo HDR : la conversion se fait en lumière linéaire, en virgule flottante.
- Pas de HDR sur les écrans qui le permettent : l'image est en SDR pour tous.
- `mobius` à `npl=100` assombrit légèrement une vidéo dont le blanc est au-dessus de 100 nits.
- Une vidéo HDR sans étiquette de transfert n'est pas reconnue et reste convertie comme avant.

## Liens
- ADR-008 — Pipeline vidéo et HLS
- ADR-012 — Traitement asynchrone
