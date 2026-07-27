# v0.11.0 — RA2/YR asset-pipeline foundation

## Replaced

- Removed the v0.10.x assumption that generating hundreds of nearly identical `.tscn` files constitutes full compatibility.
- Restored the v0.9.2 stable RTS project as the engine base.

## Added

- Provenance-preserving Westwood INI parser.
- Correct RA2 → YR overlay model for Rules, Art, Sound and AI data.
- Full index of the supplied 11,526 supported resource files.
- 559 registered TechnoType records:
  - 65 infantry
  - 80 vehicles
  - 12 aircraft
  - 402 buildings and map objects
- Weapon, projectile, warhead and sound reference graphs.
- Exact infantry Sequence frame calculations and explicit RA2/Godot facing conversion.
- Theater-aware SHP resolution and generic fallback.
- Building component graph including buildup and active/damaged animations.
- VXL/HVA body, turret and barrel pairing.
- VPL parser and remap-mask generation.
- RA2/YR database browser on the main menu.
- Rebuild command accepting ZIP files or extracted directories.
- Representative validated previews for E1, HTNK, GAPOWR, GAWEAP and YAPOWR.

## Known boundary

This release validates the resource model and references. It does not claim that all 559 objects or all special RA2/YR mechanics are playable yet.
