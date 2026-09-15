## docs/EMBER_NOW.md

<!-- BEGIN graphics-d97c-20260915; transfer this section only -->
## Свет диорамы — graphics worktree, приёмка OPEN

15 сентября: согласованный отдельный художественный срез реализован вd97c,
без переноса в исходный checkout. Один кандидат: сливочно-тёплый directional
response, прохладная цветная тень, мягче переходы toon/shadow mask, согласованная
вода. Existing shaders/materials/EmberLights; один shared shader include.
Авторские Sun/Environment storage fields и Source palette/geometry неизменны;
effective ambient черезRenderingServer RID, loader требует только одной строки.
Runtime pixel idempotence/clear/auto disable-enable/pack-reopen и lifecycle
storage gates PASS. Near/overview Forward+ уголка, холста, Причала, ночной
FanTown8/12 иCombatLab просмотрены. Точные логи/оставшиеся gates:
`art/lighting/README.md`, `art/lighting/qa`.

Это не замена current world editor состояния: его актуальные документы и dirty
работа остаются вC:/Users/novos/Projects/ember-godot. Здесь большие docs старше;
возвращать только явно помеченные graphics sections, не заменять файл целиком.
Новые canopy patterns/PCF penumbra/геометрия не добавлены. Regular beach stair
faces остаются ограничением чернового рельефа. Ручная художественная/input
приёмка пользователя и основная интеграция OPEN; commit/push не выполнялись.
<!-- END graphics-d97c-20260915 -->

## docs/EMBER_TECHNICAL_HANDOFF.md

<!-- BEGIN graphics-d97c-20260915; transfer this section only -->
## Diorama light/material candidate — 2026-09-15, manual OPEN

Existing owners: voxel opaque/alpha andSurface water shaders,2voxel materials,
EmberLights. Shared `shaders/ember_diorama_light.gdshaderinc` owns pure light
math only. No Source/recipe/mesher/physics/editor/autoload/schema changes.
Warm direct/soft bands and cool directional bounce preserve local lamp smooth
ramp; cool Moon uses established voxel response. Water fragment, hash, islands,
network, opacity, UV depth, foam/contact/wake stay unchanged; lighting keeps
stock diffuse_toon for cool directional and local lights without squaring albedo.

Effective ambient applies throughEnvironment RID; authored storage unchanged.
Weakrefs/signature polling restores changed/hidden/missing targets. Null legacy
Moon creates no watcher. Freed/detached target restores once and deletes active
entry; live detach uses nonpersistent one-shot tree_entered, cancelled on target
switch. Weak pending entries do not hold scene/Resource; next owner invocation
cleans expired entries. Active siblingMoon inhibits day ambient. Colour/elevation
guard supports currentfixtures, not a universal day/night model; warm Moon shader
response verified separately. Shadow transition softness does not inventPCF
penumbra or canopy details from binary attenuation.

Main loader is another slice's dirty owner. Transfer only one line after existing
quality-off flags in `_tune_look_environment`:
`EmberLights.apply_diorama_environment(e, _content_node("Look/Sun") as DirectionalLight3D)`.
Source main checkout untouched; QA uses own disposable current-project copy.
`tools/test_diorama_materials.gd` covers immutable storage/constructor parity/
save-reopen, same Sun detach-reattach/reparent/Moon/target cancellation/20close
cycles; --visual compares actual pixels and automatic restore. Rendering fixture
freezes actors only for comparison and waits Surface physics; not gameplay
physics/input acceptance. Measurements are viewport GPU/CPU proxies, notFPS.
Detailed protocol, images/logs and transfer scope: `art/lighting/README.md`.
Manual art/editor working-game view/input and main integration remainOPEN.
<!-- END graphics-d97c-20260915 -->

## docs/EMBER_PRODUCT_PLAN.md

<!-- BEGIN graphics-d97c-20260915; transfer this section only -->
15 сентября: отдельный согласованный graphics кандидат вworktree d97c:
тёплый свет/прохладная тень/согласованная вода на existing owners. Художественная
приёмка и интеграцияOPEN. Это параллельный ограниченный art срез; порядок
основного редактора, ландшафтных зон и дизайн-сессии не меняется. Source palette,
деревья/карты и геометрия не подгонялись под 2D референсы. Технические доказательства
и ограничения находятся в `art/lighting/README.md` и егоQA logs.
<!-- END graphics-d97c-20260915 -->

## MIGRATION_TEST_PLAN.md

<!-- BEGIN graphics-d97c-20260915; transfer this section only -->
## Diorama graphics — 2026-09-15; manual OPEN

Owned disposable current-main Temp fixture only. Never headless-editor inmain.
`test_diorama_materials.gd`: constructors/material owner parity, authored storage,
repeated apply, hidden/zero/cool/missing/freed/detachedSun, same-node reattach,
reparent toactiveMoon andback, stale target cancellation,20open-close with held
Environment, pack/save/reopen inuser://, legacyMoon without watcher.
`--visual` inForward+ checks actual pixel bytes: idempotence, exactclear,
automatic disable-enable, pack-reopen effect. No input/manual camera claim.
Watcher CPU:10kunchanged-signature polls with1live warm entry, separate fromGPU.

`render_diorama.gd` / `run_diorama_qa.ps1`: fixednear/overview, exposure/viewport,
water3.25s; baseline/candidatecorner,fullcurrentCanvas,Pier,FanTown8/12,
cool/warmMoon night+local lamp,CombatLab; physics locked only inrenderfixture.
DiagnosticCanvas shadowsON/OFF/unlit separates stair faces fromshadow/palette
andwaterseams; water8.25s verifies motion. GPU/CPU120-frame median timers,
drawcalls/VRAM are available viewport proxies; no wholeFPS guarantee.
`check_graphics_sources.py`: before/after429content scene/source/prefab hashes.
Relatedwater/Surface/Canvas/prefab regressions and exactlatestlogs:
`art/lighting/qa`. FailedexperimentalQA is excluded fromPASS proof.
Manual art/nightreadability/camera/input/working-game view and mainintegration
remainOPEN. Transfer only thissection into newer source documents.
<!-- END graphics-d97c-20260915 -->