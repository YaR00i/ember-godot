## docs/EMBER_NOW.md

<!-- BEGIN water-w04-d97c-20260915; transfer this section only -->
## Вода W04 — резкие блики, тени и свет под поверхностью, art OPEN

2026-09-15: после первой W04-проверки пользователь отклонил шумные блики, мягкие
тени и отсутствие тени причала. Review2 убрал random breakup: direct GGX теперь
заменяется цельными двухуровневыми world-cell бликами. Для тени WATER LIGHT_VERTEX
привязывается к центру мировой ячейки, ATTENUATION квантуется, а native probe
отключает stochastic soft filter; поднятый disposable причал явно отбрасывает тень
досок и опор в воду. Optional screen/depth branch по-прежнему показывает пиксельно
преломлённое видимое дно и движущийся свет. Все три mix по умолчанию0, W03 сохранён.
Review2 GIF и измерения вart/water/lightplay/HANDOFF.md. Глобальный hard-shadow
режим пока только probe: style-wide runtime решение OPEN. Source/editor/physics/
swimming прежние; art/main/input integration OPEN; commit/push нет.

Там же review3 cohesion probe после уточнения пользователя: соседние world cells и
близкие фазы поддерживают цельный движущийся блик и закрывают одноклеточные разрывы.
Параметр по умолчанию0, поэтому review2/W03 не изменены; art confirmation OPEN.

Пользователь отклонил review3: isotropic neighbour hold позволял краевым клеткам
двигаться в сторону от общей формы. Review4 переносит одно frozen light field по
единому direction/speed; клетка появляется только на leading edge и исчезает на
trailing edge. Review2 при cohesion0 pixel-exact; review4 art confirmation OPEN.

Review4 сохранил направление, но не дал нужный тип формы. Пользователь уточнил:
сам блик должен напоминать broad curved connected силуэт тени причала. Review5
порогует целиком advected smooth field в крупные световые пятна и пикселизирует
только их край. Shape0 остаётся review2 pixel-exact; art acceptance OPEN.

Пользователь отклонил review5 как просто движущиеся пятна и вернул ориентир к
чистым крупным бликам review2. Review6 сохраняет их оптический wave-normal рисунок,
но переводит выборку с центров клеток на непрерывную world coordinate; две слабые
встречные волны плавно изгибают только край. Поэтому форма шатается и меняется без
покадровых скачков квадратов. Smooth motion/edge wobble по умолчанию0, review2
остаётся pixel-exact; review6 art acceptance OPEN.

Пользователь оценил review6 как ближе к цели, но слишком мягким и заметно уходящим
к морю, и запросил живой подбор. Review7 разделяет перенос формы и дрожание края:
новые travel/wobble speed имеют независимые параметры, а стартовый вариант ставит
travel0.02, threshold0.991 и более яркое ядро. `scenes/water_lab.tscn` с one-click
`water_lab.bat` запускается в генерируемом isolated Forward+ runtime, редактирует
только duplicate существующего water material, даёт tabs Блики/Движение/Вода/
Свет и тень, Review2/reset и portable JSON copy/export. Main material/map не пишет;
native control/export/reset test PASS. Пользовательский подбор и art acceptance OPEN.

После поворота Water Lab на90° пользователь обнаружил, что рисунок блика резко
перестраивался. Причины подтверждены: preview ошибочно переориентировал солнце при
каждом orbit, а direct mask целиком использовал view-dependent half-vector. Солнце
теперь фиксировано в world space; `pixel_highlight_view_dependence` default1 сохраняет
Review2, а Water Lab стартует с0.15 и позволяет0 для полностью художественно
закреплённого рисунка. Два frozen Forward+ ракурса и native fixed-sun assertion PASS.
<!-- END water-w04-d97c-20260915 -->

## docs/EMBER_PRODUCT_PLAN.md

<!-- BEGIN water-w04-d97c-20260915; transfer this section only -->
Water W04 native art probe2026-09-15, review2 after user rejection: remove random
highlight breakup and use larger intact white/cyan light cells; quantize water's
shadow sample spatially and tonally; use hard directional filtering so the visible
pier boards/posts cast a clean block shadow. Full shallow-water candidate retains
depth/luminance-masked screen-space bottom refraction/caustics. Each material feature
is adjustable and defaults off. Hard filter is currently QA-only because making it
runtime-wide is a separate art/performance choice. No new material owner, authored
scene, editor schema, physics or swimming change. Art/main/input acceptance OPEN.
Evidence:art/water/lightplay/HANDOFF.md.
<!-- END water-w04-d97c-20260915 -->

## docs/EMBER_TECHNICAL_HANDOFF.md

<!-- BEGIN water-w04-d97c-20260915; transfer this section only -->
W04 graphics2026-09-15 review2 extends the existing water shader only. Optional
direct-light controls replace smooth GGX with clean two-band highlights computed
from one optical normal per world cell; the rejected random hash breakup was removed.
Optional shadow controls snap LIGHT_VERTEX to a world-cell centre, then quantize
directional ATTENUATION by threshold and step count. The native art probe also uses
RenderingServer SHADOW_QUALITY_HARD with angular distance0 to remove stochastic PCF
grain; project/runtime shadow quality was not changed. Optional Forward+ screen/depth
branch nearest-samples a2px refracted opaque bottom, reconstructs world position and
masks two moving cellular networks by depth/luminance. Canonical .tres stores all
controls with three mix values0, preserving W03. No physical volume, second owner or
transparent shadow-casting claim. Evidence:art/water/lightplay/HANDOFF.md. Art/input/
main integration and style-wide shadow-filter decision OPEN.

Review3 adds `pixel_highlight_cohesion` default0. At1 it spatially averages direct
alignment across four neighbour cells, averages nearby analytic phases and holds
near-threshold cells supported by neighbours/phases; opposite lit neighbours close
one-cell holes. This is stateless and deterministic, with no history buffer or new
owner. Cohesion0 rerender is pixel-exact to review2. Evidence in W04 HANDOFF.

Review3 neighbour/phase hold was rejected for lateral boundary-cell drift. Review4
reuses the same default0 switch but cohesion1 now samples one time-frozen optical
alignment field at `cell_center - normalized(flow_direction) * time * flow_speed`.
Four-neighbour averaging changes the contour only; every feature advects by the same
world vector. New direction/speed parameters serialize in the existing material.
Review2/W03 remain exact at cohesion0; art acceptance OPEN.

Review5 replaces the cohesion1 directional alignment field with a two-octave
`broad_value_noise` mask in anisotropic flow/side coordinates. The complete static
field is advected by direction*time*speed and thresholded at cell centres, yielding
large connected curved patches with a stepped contour and no per-cell motion owner.
New shape scale/threshold serialize in the existing material; shape0 preserves
review2/W03. Evidence in W04 HANDOFF; art acceptance OPEN.

Review6 returns to the review2 optical-normal highlight after review5 read as
translated blobs. `pixel_highlight_smooth_motion` blends the optical sample from the
world-cell centre to continuous surface coordinates. `pixel_highlight_edge_wobble`
adds two low-frequency counter-moving coordinate offsets before the existing wave
slope, so thresholded highlight edges deform continuously while the clean two-band
interior remains intact. Both default0 and serialize in the existing material;
review2/W03 remain exact. Evidence in W04 HANDOFF; art acceptance OPEN.

Review7 separates continuous-highlight translation from contour deformation through
`pixel_highlight_travel_speed` and `pixel_highlight_wobble_speed`, both stored in the
existing ShaderMaterial and defaulting1 for exact prior behavior. The candidate uses
travel0.02, edge wobble0.08, threshold0.991 and core0.998. `water_lab.bat` invokes
`tools/run_water_lab.ps1`, which copies only the existing water shader/material,
shared include and the preview scene into `%LOCALAPPDATA%/Temp/ember-water-lab-d97c`
and launches a clean Forward+ project. `tools/water_lab.gd` edits an in-memory
duplicate, exports JSON to clipboard and user://, and never publishes maps/materials.
`test_water_lab.gd` verifies live controls, standing/review2/reset and source
invariance. User art selection remains OPEN.

Water Lab camera-orbit correction: `_update_camera()` no longer rewrites the sun
basis. `pixel_highlight_view_dependence` blends a camera-stable sun-crest alignment
with the physical LIGHT+VIEW half-vector; default1 takes the exact legacy branch,
while the stand preset uses0.15. Dot products remain in one view-space frame, so the
sun-crest result is invariant under camera rotation with fixed world light. Frozen
quarter-turn captures and `test_water_lab.gd` verify fixed sun; Review2 pixel control
remains exact.
<!-- END water-w04-d97c-20260915 -->

## MIGRATION_TEST_PLAN.md

<!-- BEGIN water-w04-d97c-20260915; transfer this section only -->
W04 native light-play review2 evidence2026-09-15: unchanged close-current plus
review2 close sharp/shadow/caustics and game caustics each48real Forward+ frames at
12fps. Rejected highlight random mask was removed; disposable pier was raised enough
to project its boards/posts beyond the deck. Production native diagnostic: clean
cell highlight changed36423pixels over24levels and reduced >240 bright pixels
19181→2245; snapped/quantized shadow changed20446pixels over8levels; isolated bottom
light changed23996pixels and its3.25→4.25 motion changed14395. 7native and13headless
related gates PASS. Custom controls clone/save/
reopen exactly and W03 defaults remain disabled. Manual art/main/input and global
hard-shadow choice OPEN. Screen-space bottom light is not physical volumetric
caustics, bottom projection, swimming or gameplay-camera acceptance.

Review3 cohesion probe: `review3-close-connected` has48native Forward+ frames and
12fps GIF. Cohesion1 changes34601pixels over8levels versus sharp; cohesion0 rerender
matches saved review2 exactly. Targeted native shader/response plus headless defaults
and material clone/save/reopen PASS. User motion/shape acceptance OPEN.

Review4 directional-flow probe after user rejected lateral review3 cell drift:
`review4-close-flowing` has48 Forward+ frames and12fps GIF. Native flowing response
changes96867pixels over8levels versus sharp; headless defaults and custom flow
direction/speed save/reopen PASS. Cohesion0 current render remains pixel-exact to
saved review2 (same pixel SHA-256). User direction/shape acceptance OPEN.

Review5 connected-patch probe: `review5-close-patches` contains48 Forward+ frames
and12fps GIF. Native patch response changes345612pixels over8levels versus sharp;
headless defaults and shape scale/threshold save/reopen PASS. Shape0 current render
remains pixel-exact to saved review2. User art acceptance OPEN.

Review6 smooth-edge probe: `review6-close-wobble` contains48 Forward+ frames and
12fps GIF. Continuous sampling plus weak edge wobble changes31791pixels with average
0.9425 versus review2 sharp; native shader response and headless defaults/custom
save/reopen PASS. Smooth motion0 rerender remains pixel-exact to saved review2. User
art acceptance OPEN.

Review7 stationary-edge probe: `review7-close-standing` contains48 Forward+ frames
and12fps GIF. Highlight translation is independently reduced to0.02 while edge wobble
continues at1.15; threshold0.991/core0.998 sharpen the visible areas. Native and
headless water tests plus custom parameter save/reopen PASS; disabled motion controls
remain pixel-exact to saved review2. Isolated `Water Lab` Forward+ capture PASS and
`test_water_lab.gd` confirms >=25 live controls, presets, reset, portable JSON and no
canonical material mutation. User tuning/art acceptance OPEN.

Water Lab orbit regression: compare frozen `water-lab-fixed-sun-a.png` and
`water-lab-fixed-sun-b.png` after a90° orbit. Sun Basis must remain exact while the
world-anchored highlight orientation rotates only with the rendered plane. Native
test asserts unchanged sun Basis and standing view-dependence0.15. The new material
control defaults1; exact Review2 render SHA remains unchanged. PASS.
<!-- END water-w04-d97c-20260915 -->
