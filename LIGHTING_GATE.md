# Lighting gate

Look at authored `scenes/fan_town.tscn` in Godot 4 Forward+ (night). Tick only what you see. The repeatable production protocol is 0/2/4/8; 12/16 are stress profiles described in [MIGRATION_TEST_PLAN.md](MIGRATION_TEST_PLAN.md).

After confirmed **Ember: Reimport map from pack…**, props are selectable instances. Play: WASD / F / RMB, F3 metrics, F4 light profile. Mechanics: `scenes/agent_sandbox.tscn`, not `hu_tao_yard` / `hu_tao_p1`.

## Must pass

- [x] Night fill from many lanterns, not a flat ambient wash
- [x] Several lamp umbras on terrain and walls (OmniLight shadows, not one sun blob)
- [x] Looking around does not hitch or freeze the editor/game
- [ ] F3 metrics recorded for the same 60-second route at 0 / 2 / 4 / 8 local shadows

## Optional

- [ ] Lamp body / roof occludes its own Omni (ground under a stone lantern is in umbra; light leaves through windows)
- [ ] A prop is selectable in the Scene dock, survives Ctrl+S, and its prefab rebuild does not reset placement
- [ ] WASD walk from `player_start` without falling through terrain
- [ ] F on a door shows map-change (or enters if that `.tscn` exists)
- [ ] Fog / bloom from the map `light` block feels like the JOI look preset

## If lighting fails

The toon shader must leave Godot's default view-space `LIGHT_VERTEX` untouched. A custom `MODEL_MATRIX → world → VIEW_MATRIX` round-trip creates precision drift and shadow-acne waves on large voxel surfaces; the pack's `voxelSnapLight` remains a Three-only look option. Moon / camera / MSAA / atlas size live in the numbered groups on the authored `Map` Inspector. Omni fill stays on; cube shadows only on the nearest street lanterns. Editor viewport shadows are off by default and require the explicit preview switch. Lamp `ShadowBody` is layer 2 so Omni maps do not self-occlude. Stay in JOI for mechanics (`ember-agent` / `agent_sandbox`) and voxel source content. Do not extend the Three atlas.

Directional light keeps the stepped toon ramp. Positional lights use a smooth `N·L` ramp controlled by `Map.lamp_softness` (default `1`). Quantizing the point-light angle creates concentric bands on flat terrain; overlapping lamps turn those bands into tiled color patches even when local shadows are disabled.

Forward+ debanding is available as `Map.use_debanding`, but is off by default for this untextured voxel look: its ordered-dither pattern is more visible than the original color banding. Local-shadow self-interference is controlled separately by `lamp_shadow_bias`, `lamp_shadow_normal_bias`, and `lamp_shadow_blur`; normal bias is the primary control. Changing the project debanding default requires a Play restart.

## After lighting

Maps live in Godot `.tscn`. Reimport from the pack is destructive. JOI Conductor stays the soul/session shell. Voxel bots still draw `.vox` into the JOI pack; import turns them into prefabs.
