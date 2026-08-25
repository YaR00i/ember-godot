# Ember Godot

Sibling of [joi-conductor](../joi-conductor). **Godot 4.3+ Forward+** lighting spike. Authoring stays in JOI `content/ember`. This repo does not copy the map JSON schema.

Three.js MeshToon cannot host a rich lantern-umbra village. Forward+ can. JOI keeps mechanics (`agent_sandbox`) and the voxel/map editors until the lighting gate passes.

## Open

1. Install [Godot 4.3+](https://godotengine.org/download) (Forward+ / Vulkan).
2. Import this folder (`ember-godot`).
3. Default scene is `scenes/spike.tscn`: one pack lantern (or a fallback tower) + **3 OmniLight3D with shadows** + sun. RMB orbit, wheel zoom.
4. Then File → Open `scenes/fan_town.tscn` (or set it as main scene). Same pack, no second schema.

Pack path is `../joi-conductor/content/ember` next to this repo. Override in Project Settings → `ember/pack_path`.

## Importer

- `.vox` parser matches JOI `voxFile.ts`.
- Axes: MagicaVoxel Z-up → Godot Y-up, `ember(x,y,z) = vox(x,z,y)` (`emberVoxCodec.ts`).
- Voxel props and `emissiveCastsLight` / `emissiveLightShadows` come from the map + model JSON. No Godot-only light table.

Python check (no Godot required):

```
python tools/test_vox_axes.py
```

## Lighting gate

See [LIGHTING_GATE.md](LIGHTING_GATE.md). Do not start play (walk/camera as game) or port the JOI editor until that list is honestly ticked.

## Not this repo

- Iris / Complementary
- Crowd, arena waves, shops
- A second renderer inside joi-conductor
