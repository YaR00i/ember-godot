## docs/EMBER_NOW.md

<!-- BEGIN water-w02-d97c-20260915; transfer this section only -->
## Вода W02 — пиксельные отражения, художественная приёмка OPEN

2026-09-15: после понравившегося движения W01 пользователь разрешил native A/B
пиксельных отражений/бликов и бирюзового цвета. Existing water shader/.tres:
world-cell optical normals, размер1/2voxel, сила0..1, continuous time/body-facing/
VIEW и screen-footprint fade. Source/editor/mesher/physics/foam/wakes прежние.
Native close/game/wide GIF и perspective/camera evidence, storage/alpha/Sky/
split/negative-coordinate/related regressions PASS:art/water/pixel/HANDOFF.md.
На широкой воде при прямом солнце рисунок плотный; спокойствие для долгого
плавания ещё выбрать. Пользователь хочет иногда плавать между островами,
механика здесь не определена/не реализована. Art/input/main integration OPEN;
рефракция дна, production environment и плавание — отдельные срезы. Старые
W01/M01/M02/lighting evidence сохранены; commit/push не выполнялись.
<!-- END water-w02-d97c-20260915 -->

## docs/EMBER_PRODUCT_PLAN.md

<!-- BEGIN water-w02-d97c-20260915; transfer this section only -->
Water W02 approved for native comparison2026-09-15: retain W01 motion, pixel-shape
reflections/highlights through world-cell optical normals, turquoise palette,
adjustable size/strength and distant detail fade. Same Surface water owner;
Source/editor/physics/foam/wakes unchanged. One-/two-voxel animations on close/
game/wide fixtures supplied; artistic choice/main integration/input OPEN.
Future occasional swimming between islands is a user direction, not implemented
travel mechanics. Calm wide-water glint density, actual bottom refraction and
character swimming/interaction require later decisions. Evidence/limits and
incremental transfer:art/water/pixel/HANDOFF.md. No engine change or commit/push.
<!-- END water-w02-d97c-20260915 -->

## docs/EMBER_TECHNICAL_HANDOFF.md

<!-- BEGIN water-w02-d97c-20260915; transfer this section only -->
W02 graphics2026-09-15: existing water shader/.tres adds reflection_pixel_size
0.0625block(default1voxel; QAcoarse0.125), reflection_pixel_strength0..1(default1).
Sample existing bent wave slopes at fixed world-cell centers; continuous time/
VIEW/body-facing opacity, fade cells with0.75..2pixel footprint, derivatives
from unquantized coordinate. Turquoise .tres3colours; all W01 optical/alpha/
foam/contact/Source/physics owners retained. Sky/probe/GGX remain W01; no
screen-wide colour pixel pass/refraction/planar mirror/swimming added.
Native pixel/alpha/Sky/storage/seam/Surface/object gates and11headless regressions
PASS;429Source unchanged. Native movement/close/game/wide/perspective/camera
evidence:art/water/pixel/HANDOFF.md. Initial logical-viewport diagnostic failure
archived; known one-probe7TextureRID shutdown warning unchanged. Transfer only
W02 incremental patch + marked docs, never whole stale docs. Main integration,
art/input and wide-water calmness OPEN; authored colours can override defaults.
<!-- END water-w02-d97c-20260915 -->

## MIGRATION_TEST_PLAN.md

<!-- BEGIN water-w02-d97c-20260915; transfer this section only -->
W02 native water pixel evidence2026-09-15: art/water/pixel/qa, one-/two-voxel/
W01same-camera GIF, new-colour smooth control; close/game/wide/perspective and
frozen-water camera translation. Native optical within-cell max0, negative/
positive world cells, split not aligned to cell edges0difference; strength0
continuous475/576cells, size/time response, subpixel exact convergence PASS.
Material custom save/reopen, real Sky and alpha, existing seam/noise diagnostics,
stock/native Surface0different/8171visible and object motion6741pixels PASS.
11headless regressions,429canonical Source guard and isolated editor import PASS.
Initial512image/logical1280camera mismatch archived separately; active final
logs noERROR/SCRIPTERROR/FAIL, UID/fragmentObjectDB and probe7TextureRID diagnostics
retained as warnings, no clean engine-lifecycle claim. Manual choose pixel size/
glint calmness near/game/wide/day/night and verify contacts/input in Forward+.
Art/input/main integration OPEN; no gameplay swimming or bottom refraction.
<!-- END water-w02-d97c-20260915 -->
