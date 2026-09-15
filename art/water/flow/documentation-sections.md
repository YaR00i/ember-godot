## docs/EMBER_NOW.md

<!-- BEGIN water-w03-d97c-20260915; transfer this section only -->
## Вода W03 — живая светлая сеть и бирюзовый цвет, art OPEN

2026-09-15: пользователь уточнил, что характер воды создают меняющиеся белые
сетки, показывающие грани колебаний, и попросил больше бирюзы. Existing water
shader/.tres получил стилизованную surface light network: continuous wave-time,
world-anchored moving cells с pixel edges/gaps, shallow→deep attenuation и
distance fade. Цвет насыщеннее, shallow alpha0.50, roughness0.22; W02 pixel
reflections сохранены. Это видимый рисунок в материале, не настоящая проекция
caustics на дно. Source/editor/physics/foam/wake/swimming прежние. Native close/
game/wide animation и flow/storage/Sky/alpha/seam/regressions evidence:
art/water/flow/HANDOFF.md. Art/input/main integration OPEN; commit/push нет.
<!-- END water-w03-d97c-20260915 -->

## docs/EMBER_PRODUCT_PLAN.md

<!-- BEGIN water-w03-d97c-20260915; transfer this section only -->
Water W03 approved for native visual probe2026-09-15: keep W01 movement and W02
pixel reflections, add a changing white light-cell network and stronger turquoise
body colour. Existing water material only; network is stronger over shallows,
weaker at depth and filtered at distance. It visually expresses water facets but
does not project physically refracted caustics onto bottom geometry. Source/
editor/physics/foam/wakes/swimming unchanged. Native close/game/wide animation
available; art/main/input acceptance OPEN. Evidence:art/water/flow/HANDOFF.md.
<!-- END water-w03-d97c-20260915 -->

## docs/EMBER_TECHNICAL_HANDOFF.md

<!-- BEGIN water-w03-d97c-20260915; transfer this section only -->
W03 graphics2026-09-15: existing water fragment reuses connected ripple network,
advected/bent by existing continuous optical slopes. New ShaderMaterial controls:
flow_network_strength0.60, deep_ratio0.32, warp0.10, pixel_density32. World grid,
continuous seconds (independent from legacy stepped colour FPS), sparse moving
gaps, top faces only, derivative distance fade0.025..0.10. Legacy network alpha0
on canonical .tres avoids a duplicate loop/look. New body colours turquoise,
palette influence0.06, shallow alpha0.50; roughness0.22 sharpens W01/W02 optics.
No emission/vertex displacement/bottom projection/refraction/schema or physics.
Native movement/depth/disabled/distance/split-negative tests plus related gates:
art/water/flow/HANDOFF.md. Art/input/main integration OPEN; transfer only W03
incremental patch and marked docs. Known QA probe warning retained, no engine fix.
<!-- END water-w03-d97c-20260915 -->

## MIGRATION_TEST_PLAN.md

<!-- BEGIN water-w03-d97c-20260915; transfer this section only -->
W03 native light-network evidence2026-09-15: close-before/no-network/flow and
game/wide flow each48real Forward+ frames. Diagnostic executes production fragment
and exposes flow mask: split at non-cell edge and negative/positive coordinates
5significant pixels/average0.0000153; continuous-time movement31406pixels/
average0.0922; shallow0.1238 vs deep0.0737; disabled and distant-subpixel masks
vanish. Independent custom material save/reopen, Sky/alpha, W02 pixel, Surface/
object/seam and related headless gates PASS; Source guard/editor import documented
inart/water/flow/HANDOFF.md. Two diagnostic fixture failures (wrong emission output,
then weak distance threshold) retained separately and corrected. Manual art/input/
main integration OPEN; no bottom-caustic projection, refraction or swimming gate.
<!-- END water-w03-d97c-20260915 -->
