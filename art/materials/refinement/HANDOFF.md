# Material library M02 — reflection / highlights / weak texture

2026-09-15. Пользователь согласовал более естественные блики, отражение окружения
на стенде, регулируемые цветные блики/перелив кристалла и слабую фактуру.
Material/storage/compatibility gates PASS. Native reflection cleanup имеет
известное engine limitation; это не clean lifecycle PASS. Art/input acceptance
и main integration OPEN. Source/schema/mesher/editor/physics/water не менялись.
Main checkout read-only, commit/push нет. Следующий водный срез не начинался.

## Передача

После M01 заменить только текущие library files:
shaders/ember_material_surface.gdshaderinc, scripts/ember_material_library.gd,
materials/library/*.tres, tools/material_library_stand.gd,
tools/render_material_library.gd, tools/test_material_library.gd.
Новый bounded diagnostic: tools/probe_reflection_engine_leak.gd.
Opaque/transparent wrappers, scene stand и stable9IDs прежние.
Existing diorama include/voxel/water materials/helpers/loader не менялись.
Для переноса с нуля использовать M01 file list плюс эти текущие версии.

M01 code snapshot: art/materials/checkpoint-m01/** с .gdignore; старые
art/materials/qa PNG/logs и M01 HANDOFF.md не перезаписаны. Lighting QA также
прежняя. refinement.patch показывает изменение code/presets относительно
M01 snapshot. Snapshot — backup для восстановления файлов по исходным путям
в disposable project, не второй runtime каталог. Его нельзя назначать вместо
активной библиотеки. Новые docs sections только между marker
materials-refinement-d97c-20260915, вырезки в documentation-sections.md.
Полный main loader/docs не заменять.

## Material response

Direct highlights используют GGX distribution, Smith visibility и Schlick
Fresnel вместо прежнего художественного power lobe. Roughness, view/light angle
и metallic влияют на highlight; fragment roughness включает слабую фактуру.
За основу сверены [термы Godot renderer](https://github.com/godotengine/godot/blob/master/servers/rendering/renderer_rd/shaders/scene_forward_lights_inc.glsl).
Это более естественный specular foundation, не заявление о полном physical
rendering: diffuse остаётся diorama toon, нет spectral tracing/energy compensation.
Guard half-vector защищает противоположные LIGHT/VIEW от normalize(0).

Новые ShaderMaterial параметры:

- highlight_color:Color0..1; highlight_color_strength0..1. Цвет прямого блика
  независим от base/emission;0сохраняет нейтральный блик;
- iridescence_strength0..1; iridescence_frequency0.5..6. Художественный angular
  spectral tint прямого блика; не физическая dispersion/refraction. Default
  crystal strength0.25, остальные0. Default colour strength0/white;
- texture_kind:int0..3:0none,1wood fibres,2stone patches,3grain;
- texture_scale0.2..16; texture_strength0..0.3; texture_relief0..0.05.

Все новые параметры проходят type/range/finite validation и сохраняются лишь
в ShaderMaterial .tres. Source preset IDs/каналы не добавлены. Palette остаётся
владельцем voxel colours; shine не объявляется готовым roughness/metallic owner.
Existing emissive/transparency/transmittance автоматически не подключены к
этим modifiers. Highlight tint, spectral controls и texture controls пока не
имеют per-voxel persistence — это следующий editor-owner контракт.

Default weak textures:
wood kind1/scale2/strength0.06/relief0.006;
stone kind2/scale3/strength0.05/relief0.010;
sand kind3/scale3/strength0.035/relief0.004;
остальныеkind0/strength0/relief0. Без фактуры нет fragment noise work.
Local-mesh position используется без UV/изменений mesher. Пространственная
фактура слегка модулирует albedo/roughness и derivative bump нормаль; это не
новая геометрия/collision и не baked текстура. Screen footprint постепенно
ослабляет субпиксельные подробности. NO TIME/camera-anchored random pattern;
это mitigation ряби, не доказательство отсутствия shimmer во всех масштабах.

Native sidebar имеет вкладки Основа/Блики/Фактура/Свечение. Контролы меняют
только выбранный clone. Texture type, colour strength и angular effect можно
выключить независимо. Real mouse/picker/orbit/input acceptance OPEN.

## Reflections owned by stand

Library create не заводит ReflectionProbe. Один ReflectionProbe живёт только
в disposable stand, box projection и UPDATE_ALWAYS для сравнения при изменении
света/образцов. Production owner может выбрать размещение/update policy лишь
в отдельном integration срезе. Sky/Probe reflection не planar mirror/ray tracing;
glass/crystal не преломляют фон и не создают цветные тени.
Авторские light_specular поля не менялись; для direct glints по-прежнему нужен
positive light_specular. Stand lights1. Вода/SSR здесь не тронуты.

## Native и storage gates

qa/test-library.log PASS:all9presets, existing+new typed params, customized
save/reopen каждого из9, immutable original/independent clones, new sidebar
iridescence/texture routing. QA writes только isolated user:// temporary assets.
qa/native-refinement.log:Forward+/Vulkan1.4.351/RTX5070; material pixel assertions
PASS с отдельным известным14TextureRIDs shutdown warning (см. ниже).

GGX shiny gray0.3216 versus dull0.1686. Red highlight control сохраняетR0.2627,
снижаетG/B0.2627→0.1137. Metal reflects red wall behind camera (outside direct
view):red0.7373 без прямого света; no-probe baseline dark. Angular spectrum
on/off меняет реальные pixel bytes. Weak wood texture on/off меняет response;
relief-only test с одинаковым albedo/highlight/roughness подтверждает изменение
освещения отдельно от colour. Emission/no-light/custom save-reopen exact pixels,
alpha behind/front opaque depth, leaf backlighting по-прежнему PASS.

12M02actual viewport/probe PNG,1600x900 main captures. Hero crystal A/B используют
усиленные демонстрационные settings (colour strength0.75, spectral0.8), camera
и lamp/sun angle меняются для видимого блика; это не default preset screenshot
и не fixed-light camera comparison. Общий library-day показывает defaults.
weak-texture/wood-without-texture — одинаковые камера/свет, отличие только wood
strength/relief. Шесть prior-scene guard PNG отдельно, всего18новыхPNG.
Manual view-angle/shimmer inspection на авторских формах остаётся OPEN.

Related gates PASS: diorama_materials, voxel_palette, voxel_prefab_rebuild,
native_surface_water. qa/editor-import.log:isolated --headless --editor --import
completed exit0/no ERROR/SCRIPT ERROR, inherited FanTown text-path UID warnings.
qa/previous-look-source-guard.log:429old Source/scene/prefab files byte-identical,
only owned stand scene added. Corner(day/night)/Pier near+overview rerendered
with M02 files, all6PNG byte-identical to previous lighting candidate.
Старые manifests/PNG/logs не перезаписаны. Это compatibility proof, не FPS/
performance benchmark M02 textures/reflection costs.

## Known engine cleanup limitation, separately from PASS

qa/engine-no-probe.log:empty native scene without probe closes cleanly.
qa/engine-one-probe.log:same minimal fixture with1ReflectionProbe yields
7TextureRIDs leaked at RenderingDevice.finalize on4.7.2. No library shader,
Sky, model or authoring code participates. Official matching bug:
[Godot #122498](https://github.com/godotengine/godot/issues/122498).
Combined native QA has two reflection atlases (stand/local pixel probe), yields
14TextureRIDs diagnostic at shutdown. Process exit0 does NOT make that clean
GPU lifecycle PASS. These runs establish matching shutdown diagnostic only;
they do not measure live editor VRAM accumulation or exact leak size.
Engine fix/build/upgrade, production probes and policy decisions are OUT OF SCOPE.
Issue+logs handed to main coordinator, who confirmed current bounded isolation
is enough. Reflection integration must retain this limitation explicitly.

Early QA attempts recorded separately:failed-first-reflection-cleanup.log;
failed-root-world-swap.log (scenario null ERROR from attempted rootWorld swap,
workaround removed completely, never ship/reintroduce);failed-matte-relief-probe.log
(weak matte response below observable8-bit probe, retested with controlled
highlight/roughness pair, no strengthening of defaults). Initial guessed Variant
view inference fixed with explicit Vector3. Failed files are NOT final clean PASS.

## Reproduce and open gates

Use same owned prepared Temp from M01, copy only listed M02 files. Console
Godot C:/Users/novos/Projects/ember-godot/tools/godot/Godot_v4.7.2-stable_win64_console.exe.

```powershell
$materialFixture = 'C:/Users/novos/AppData/Local/Temp/ember-graphics-d97c-20260915'
$materialGodot = 'C:/Users/novos/Projects/ember-godot/tools/godot/Godot_v4.7.2-stable_win64_console.exe'
& $materialGodot --headless --path $materialFixture --script res://tools/test_material_library.gd
& $materialGodot --path $materialFixture --script res://tools/render_material_library.gd
& $materialGodot --path $materialFixture --script res://tools/probe_reflection_engine_leak.gd -- --probe
& $materialGodot --path $materialFixture res://scenes/material_library_stand.tscn
```

Никаких main writes/commit/push. User manually принимает слабость фактуры,
характер glints/перелива, реальный orbit/controls и результаты на authored forms.
Main integration/editor assignment/Save/Undo остаются следующими шагами.
Вода обсуждается после материала, не реализована этим diff.
