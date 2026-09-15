## docs/EMBER_NOW.md

<!-- BEGIN water-w01-d97c-20260915; transfer this section only -->
## Вода W01 — optical ripples/reflections/highlights, manual OPEN

2026-09-15: пользователь согласовал спокойную стилизованную воду. Existing
Surface shader/material получили smooth world/block normal ripples без vertex
displacement, dielectric GGX/Fresnel highlights и Sky/probe indirect reflections;
diffuse styling остаётся прежним owner. Shallow opacity0.42, deep0.78; broad
islands приглушены patch_strength0.35, decorative glints и emission по умолчанию
выключены. Source/schema/editor/mesher/physics/foam/contacts/authored scenes
не менялись. Native motion/alpha/reflection/save-reopen и regressions PASS
в disposable Forward+ project; итоговые evidence/art limits:art/water/HANDOFF.md.
Configured QA Sky/probe/specular отдельно от authored WorldCanvas/Pier. Main
integration/art/input OPEN; production lights/environment — отдельный шаг.
Known one-probe shutdown7TextureRIDs сохраняется, engine fix не входит.
Pre-W01/lighting/M01/M02 evidence сохранены; commit/push не выполнялись.
<!-- END water-w01-d97c-20260915 -->

## docs/EMBER_PRODUCT_PLAN.md

<!-- BEGIN water-w01-d97c-20260915; transfer this section only -->
Water W01 approved2026-09-15: calm stylized water with real reflection sources,
light/view-driven highlights, smooth optical ripples, clearer shallows and quieter
colour islands. Existing water owner, no physical wave displacement/Source or
editor schema changes. Native demonstration and authored-map evidence are
separate; scene Sky/probe/specular integration and manual art/input acceptance
OPEN. Material assignment/editor tools remain the main editor-owner contract.
Exact evidence and limits:art/water/HANDOFF.md. No engine upgrade/fix added.
<!-- END water-w01-d97c-20260915 -->

## docs/EMBER_TECHNICAL_HANDOFF.md

<!-- BEGIN water-w01-d97c-20260915; transfer this section only -->
Water W01 graphics2026-09-15: existing shader/.tres, world/block optical normal
waves only, roughness0.28/specular0.36(F0≈0.0207), GGX direct light and normal
Godot Sky/probe indirect specular. Remove global diffuse_toon (its dielectric
indirect term is zero), disable ambient-based specular occlusion; stylized
diffuse remains custom/shared light response. Shallow0.42/deep0.78, patch0.35,
decorative_glints=false/body_emission0. Source/mesher/editor/physics/authored
scenes/foam/contact owners unchanged; existing backdrop uses same shader.
Native motion, reflection/alpha, independent material save/reopen and targeted
regressions evidence inart/water/qa; exact diff/handoff and new parameters:
art/water/HANDOFF.md. QA-only Sky/probe/specular not automatic production setup.
One-probe7TextureRIDs known shutdown warning persists; no engine change.
Production main integration and manual art/input OPEN. Transfer only this section.
<!-- END water-w01-d97c-20260915 -->

## MIGRATION_TEST_PLAN.md

<!-- BEGIN water-w01-d97c-20260915; transfer this section only -->
Water W01 native/storage/compatibility evidence2026-09-15 inart/water/qa.
Actual normals/time/light_specular A/B,48real rendered motion frames, exact
custom ShaderMaterial save/reopen; shallow/deep red backing transmission and
red/green actual Sky reflection with no direct light/ambient. Native independent
water halves/pattern-cell continuity plus Surface/object water/contact/world
projection/palette/prefab/fragment/diorama regressions. Authored WorldCanvas/Pier
before-after separately from QA-configured Sky/probe/specular demonstration.
Canonical429Source bytes unchanged; previous checkpoints/QA retained. Known
one-probe shutdown7TextureRIDs distinguished from assertions PASS; inherited
UID warnings and separate fragment ObjectDB warning retained in logs. Manual art/input/main integration
OPEN; inspect brightness/colour/depth/motion near/far/day/night and contacts.
No physics displacement, producer/schema/editor owner replacement or engine fix.
<!-- END water-w01-d97c-20260915 -->
