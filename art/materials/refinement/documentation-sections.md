## docs/EMBER_NOW.md

<!-- BEGIN materials-refinement-d97c-20260915; transfer this section only -->
## Материалы M02 — слабая фактура/блики/отражения, manual OPEN

2026-09-15: пользователь согласовал refinement библиотеки. Existing9presets
получили GGX direct highlights, independent tint/angular crystal colour и weak
wood/stone/sand factures (albedo/roughness/normal, screen-footprint filter).
ReflectionProbe только disposable stand, library не создаёт probes. Material/
storage/compatibility gates PASS; native probe cleanup имеет известный engine
warning7TextureRIDs/minimal scene, matching Godot#122498, не clean lifecycle PASS.
M01 snapshot/QA и lighting evidence отдельно сохранены.429old Source hashes и
6old lighting/water PNG прежние. Передача:art/materials/refinement/HANDOFF.md.
Main integration/art/input и editor assignment OPEN. Engine fix/build/prod
probes не входят. Воду обсудить после библиотеки, здесь не менять.
<!-- END materials-refinement-d97c-20260915 -->

## docs/EMBER_TECHNICAL_HANDOFF.md

<!-- BEGIN materials-refinement-d97c-20260915; transfer this section only -->
## Material M02 — 2026-09-15, manual/integration OPEN

Existing library only: GGX/Smith/Schlick direct specular, bounded artistic tint/
angular spectrum, local-position derivative texture/roughness/bump, weak defaults.
New params:highlight_color/strength,iridescence_strength/frequency,texture_kind/
scale/strength/relief; ShaderMaterial storage ONLY, no voxel/schema/mesher/editor
migration. Stable9IDs unchanged. Stand-only box-projected ReflectionProbe,
no automatic probe per material. Canonical old voxel/water/lighting untouched.
Native material assertions/custom save-reopen/related gates/429Source hash and
6prior-scene PNG guards PASS. Engine cleanup separate: empty native no-probe
clean,1probe7TextureRIDs at finalize on4.7.2, matching#122498; combinedQA14.
No statement about live VRAM accumulation/leak size. No engine workaround;
attempted World3D swap removed. Preserve M01/lighting evidence. Handoff/API/
weak defaults/limits/logs:art/materials/refinement/HANDOFF.md.
<!-- END materials-refinement-d97c-20260915 -->

## docs/EMBER_PRODUCT_PLAN.md

<!-- BEGIN materials-refinement-d97c-20260915; transfer this section only -->
## Materials M02 — 2026-09-15

Approved library refinement improves highlights/crystal colour and weak tactile
texture; reflection comparison only on native stand. Manual art/input/main
integration pending. Known Godot probe shutdown cleanup warning separated from
material PASS; production reflection policy/engine fix not silently added.
No editor/water/order changes. Discuss water and remaining materials afterwards.
Details:art/materials/refinement/HANDOFF.md.
<!-- END materials-refinement-d97c-20260915 -->

## MIGRATION_TEST_PLAN.md

<!-- BEGIN materials-refinement-d97c-20260915; transfer this section only -->
## Material M02 gates — 2026-09-15, manual OPEN

PASS customized9preset save/reopen/validation/independent instances/new sidebar
controls. Native material assertions PASS:GGX, colour/angular glints, environment
reflection outside direct view, weak texture and independent relief, alpha/depth,
emission/no-light/reopen, transmission. Related4gates PASS. Isolated import
completed without errors.429oldSource bytes and6previous lighting/water PNG equal.
Probe GPU cleanup NOT cleanPASS: minimal no-probe clean,1probe7TextureRIDs shutdown
warning on4.7.2 matchingGodot#122498; combinednativeQA14. No live VRAM claims.
Failed cleanup attempts separate/removed. M01 evidence retained. Manual authored
forms/view-angle/shimmer and real native input/main integration OPEN.
Evidence:art/materials/refinement/qa; exact protocol/HANDOFF alongside.
<!-- END materials-refinement-d97c-20260915 -->
