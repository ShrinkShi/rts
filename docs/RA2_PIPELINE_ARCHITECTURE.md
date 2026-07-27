# RA2 / Yuri's Revenge compatibility pipeline v0.11.0

## Scope of this release

This release replaces the discarded v0.10.x "one generic prefab per object" approach with a provenance-preserving data and asset index. It is the first infrastructure phase, not a claim that every RA2/YR mechanic is already playable.

The pipeline currently builds a complete searchable index from the supplied extracted game data:

- `rules.ini` overlaid by `rulesmd.ini`
- `art.ini` overlaid by `artmd.ini`
- `sound.ini` overlaid by `soundmd.ini`
- `ai.ini` overlaid by `aimd.ini`
- all supplied SHP, VXL, HVA, PAL, VPL, theater tile, PCX, FNT and AUD files

Every effective INI value records its winning source file, source line, layer, and overridden history.

## Data flow

```text
RA2 extracted directory / ra2.zip
YR extracted directory / ra2md.zip
              │
              ├── Westwood INI parser
              │     ├── case-insensitive sections and keys
              │     ├── duplicate-key history
              │     └── RA2 → YR overlay provenance
              │
              ├── asset index
              │     ├── pack and folder priority
              │     ├── SHA-1 identity
              │     ├── theater filename substitution
              │     └── extension/type classification
              │
              ├── entity graph
              │     ├── TechnoType → Art section → image files
              │     ├── Infantry Sequence → exact frame indices
              │     ├── voxel body / turret / barrel / HVA pairing
              │     ├── building body / buildup / active / damaged components
              │     └── Weapon → Projectile → Warhead → Sound references
              │
              └── Godot JSON database and representative PNG validation assets
```

## Corrected infantry direction model

The official infantry Sequence blocks are treated as:

```text
RA2 order: S, SW, W, NW, N, NE, E, SE
```

Iron Meridian's angle index starts at screen-right and rotates clockwise:

```text
Godot order: E, SE, S, SW, W, NW, N, NE
```

The generated database stores the explicit mapping:

```text
Godot → RA2: 6, 7, 0, 1, 2, 3, 4, 5
```

For a Sequence entry such as `Walk=8,6,6`, the third number is the facing stride, not a facing count. The importer generates the exact source-frame list for every Godot direction.

## Theater resolution

`NewTheater=yes` replaces the second character of an artwork stem:

| Theater | Letter | Example from `GAPOWR` |
|---|---:|---|
| Snow | A | `GAPOWR` |
| Temperate | T | `GTPOWR` |
| Urban | U | `GUPOWR` |
| Desert | D | `GDPOWR` |
| Lunar | L | `GLPOWR` |
| New urban | N | `GNPOWR` |
| Generic fallback | G | `GGPOWR` |

The resolver also distinguishes normal artwork directories from ISO/buildup directories.

## Building component model

A building is no longer treated as one image. The database resolves and preserves:

- main body and body damage/rubble frames
- `Buildup`
- `ActiveAnim`, `ActiveAnimTwo`, `ActiveAnimThree`
- damaged active animations
- idle, production, deploying, roof and door animations
- bib shape
- foundation and occupy height
- damage-fire offsets
- animation start, loop range, rate, layer, Z adjust and Y sort

Art aliases are resolved before file lookup. For example an `ActiveAnimDamaged` section may point to the same SHP as the normal animation but use a different frame range.

## Voxel model

The index resolves conventional components separately:

```text
unit.vxl / unit.hva
unittur.vxl / unittur.hva
unitbarl.vxl / unitbarl.hva
unitwo.vxl / unitwo.hva when NoSpawnAlt=yes
```

The validation preview uses VXL geometry, HVA matrices, and the supplied `voxels.vpl` color ramps. Exact Westwood normal-vector lighting is deliberately marked as unfinished rather than being reported as pixel-perfect.

## Team-color support

SHP and VXL previews generate a separate remap mask for palette indices 16–31. Runtime team coloring should use this mask, not blue-pixel detection or whole-sprite multiplication.

## Generated data

```text
data/ra2/catalog.json             lightweight Godot browser catalog
data/ra2/entities/<id>.json       one detailed record per object
data/ra2/database.json            complete combined database
data/ra2/assets.json              full asset index
data/ra2/issues.json              unresolved or intentionally absent references
data/ra2/weapons.json
data/ra2/projectiles.json
data/ra2/warheads.json
data/ra2/sounds.json
```

## Rebuild

Place the source ZIPs beside the project, or pass absolute paths:

```bat
build_ra2_pipeline_windows.bat "D:\RA2\ra2.zip" "D:\RA2\ra2md.zip"
```

The script accepts either ZIPs or extracted directories and stores extraction cache under `.ra2_cache/`, which is ignored by Git.
