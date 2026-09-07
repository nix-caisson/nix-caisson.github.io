# Brand assets

Working drafts of the caisson visual identity ("Caisson Waterline"
concept: the engineered foundation below the waterline, the visible
structure above it).

| File | Use |
|---|---|
| `emblem.svg` | Square mark (512), large surfaces |
| `badge.svg` | Reduced mark for avatar sizes (32–260 px); the org profile picture |
| `favicon.svg` | Reduced mark for 16–64 px |
| `wordmark.svg` | Horizontal logotype |
| `social-card.svg` | GitHub social preview source (1280×640) |
| `emblem-dark.svg` | Night variant: the Bay Lights on the suspenders, structure as silhouette |
| `social-card-dark.svg` | Night variant of the card, same vocabulary |
| `wordmark-dark.svg` | Night logotype for dark surfaces |

The wordmarks have transparent backgrounds by design: place the day
wordmark on light surfaces (fog tokens) and the night wordmark on dark
ones (night tokens) — and composite over the intended surface when
generating previews. The favicon is dark-native and serves both modes.

## Palette

| Token | Hex |
|---|---|
| iron | `#43464B` |
| fog-light | `#D8DBDE` |
| deep-water | `#27394E` |
| bedrock | `#1B2635` |
| nix-blue | `#5277C3` |
| nix-sky | `#7EBAE4` |
| gold (rivet only) | `#C9A227` |
| violet (easter egg) | `#7F5AB6` |

Night tokens (dark variants — night falling on the same bridge; the
suspenders become the Bay Lights and only the foundation keeps its color):

| Token | Hex |
|---|---|
| night-sky | `#151B24` |
| night-water | `#0E141D` |
| night-bedrock | `#090E15` |
| silhouette (structure) | `#39414C` |
| led | `#E8ECF2` |
| caisson fill (night) | `#1C2836` |

## Rendering

PNGs are generated with resvg, e.g.:

```
resvg assets/brand/social-card.svg social-card.png
```

The wordmark and social card use a font stack (`Inter`, IBM Plex Sans,
DejaVu Sans, system fallback); rendered output depends on fonts present
at render time. Pin a font before publishing final raster assets.

## Rules

One metaphor per surface; fog greys are the neutral field; blue marks
the foundation lattice; gold appears exactly once per surface (a rivet);
violet stays at easter-egg subtlety. Do not derive marks from the NixOS
snowflake logo.
