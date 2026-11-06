# Ember — производительность мира

Обновлено: 2026-11-04. Это единственный владелец текущего performance-контракта
земли, растительности, объектов, воды и освещения. Здесь хранятся действующие
решения и незакрытые проверки; последовательность старых проб сюда не дописывается.
Активное действие — [NOW](EMBER_NOW.md), продуктовая очередь —
[Product Plan](EMBER_PRODUCT_PLAN.md), архитектура авторинга —
[World Authoring](EMBER_WORLD_AUTHORING_ARCHITECTURE.md).

## Цель и границы

- Минимум **120 FPS при native 2560×1440** на RTX 5070: бюджет кадра 8,33 мс.
  Средний FPS и GPU одного неподвижного ракурса этот порог не принимают.
- Ближняя плотность, состав нагрузки и внутреннее разрешение сохраняются.
  Дальний LOD принимается по покрытию, силуэту и плавности переходов.
- Камера меняет угол и масштаб: FOV 40/70, близкий и широкий/наклонный вид.
  Приёмка включает движение через стыки, холодный старт и возврат.
- Рабочая карта — `scenes/landscape_compact.tscn`; отдельный 576-метровый полигон
  является стресс-fixture, а не второй развиваемой картой.
- Forward+ и существующие Scene/Resource остаются основой. Новый renderer,
  mesher, формат мира или замена terrain не утверждены.
- Автор отложил сферу и `.exe`: сейчас обычный editor/gameplay без сферы.
  Механика сферы и три облика сохранены, отключение не означает удаление.
- GTX 1060 у автора — будущая проверка на реальном слабом ПК. Вариант 3/6 GB,
  CPU/RAM, разрешение и требуемые FPS ещё не заданы. Модель iGPU неизвестна.
  Меню качества/автонастройка сейчас отложены. Проверка 1060 не заменяет порог 5070.

## Короткий вход: что уже известно и когда проверять заново

Текущий договор — 120 FPS в полном 2560×1440, прежняя плотность и дальность.
Автор хочет запас для будущего наполнения; 200 FPS — пожелание о запасе,
а не новый согласованный порог. Текущий стресс8важных героев+32NPC не прошёл120FPS.
Старые результаты пустого мира, 16 NPC и статического кадра этот статус не заменяют.

- **Уже применяется:** Jolt/HeightMap общей поверхности,native meshoptimizer LOD,
  пространственные MultiMesh травы,worker IO/digest/scatter и bounded publication,
  overview index reuse,animation distance LOD,physics interest иshadow geometry LOD.
  Повторно предлагать их как отсутствующую основу нельзя;owners ниже.
- **Измерено сейчас:** native motion≈38% main в dense crowd;body_test_motion main-only.
  RigidBody32NPC даёт≈2мс,но меняет контакт сящиком и пока не принят;rig/render и
  world callbacks тоже стоят времени. Это не доказательство,что надо менять всюземлю. Hidden pickups
  больше не удерживают опору,но whole-FPS gain отэтого не установлен.
  GPU NPC6клипов QA снизил matched wall16,404→11,276мс;8important native,120FPS OPEN.
  Grass3LOD/цветы/ветер проверены вместе;меньше геометрии не дало отдельного GPU gain.
- **Отклонено только по конкретной пробе:** cached spring axes — нет frame gain;
  global/cold-first queue aging — хуже coverage. Повтор требует новой причины,
  изменения алгоритма/условий или опровержения прежней evidence,а не забывания итога.
- **Не реализовано/не принято:** state-aware дальний HLOD/cluster,полныйNPC/Source
  paging,grass far coverage LOD и явный prewarm следующего camera view.
  Impostors не отвергнуты: первая проба невалидна. Terrain3D не признан медленным:
  замена отложена из-за Source/editor/physics/трёх обликов. Temporal sun cache отложен автором.
- **Исследовано01.11:** оригинальные слайды Pearl Abyss и shipped resources подтверждают
  staged view-based streaming, baked/stateful proxies и общий interaction framework.
  Применимость/неизвестное — «Что берём из опубликованных игр»;это не реализация вEmber.

Перед новым повтором назвать изменившееся условие и вопрос,который старые данные
не закрывают. Каждый новый метод записывать здесь один раз: источник/наблюдение,
применимость к владельцу, статус и условие возврата. Подробные замеры и evidence
остаются ссылками; следующая задача меняется в существующей последовательности и NOW.

## Геометрия отдельно от материалов: обратимая диагностика01.11

Текущий срез автора: на основной карте видеть реальную сетку/автоматический LOD,
затем сравнивать материалы при прежней плотности/дальности. Source/editor не удаляются.
Owner — `EmberBenchmarkOverlay`, подключённый прежним `EmberExploreScene` в Play.
`F2`: исходный вид → native `DEBUG_DRAW_LIGHTING` → native wireframe → исходный.
`Shift+F2`: штатный mesh LOD ↔ threshold0/full geometry; исходный threshold
восстанавливается точно, удаление overlay восстанавливает исходный viewport.
Свет/тени/физика/камера не переключаются вместе с материалами. Никакой записи в
материалы, Mesh или Source; показатели primitive counts относятся к проходам,
а не к числу уникальных треугольников Source. Wireframe показывает действующую
сетку, но сам дорог и не служит оценкой игровой производительности.

Native LIGHTING заменяет пользовательские материалы, включая alpha/vertex effects;
ветер/карточки/шейдерный fade могут выглядеть иначе. Поэтому это диагностическая
граница material path, не чистая стоимость одного fragment shader и не игровой PASS.
FPS окна и p95 используют одни samples; смена режима сбрасывает окно.

`tools/test_geometry_diagnostic_view.gd`: Forward+ sphere near1560/far48/full12480
actual visible primitives; source material/mesh identity и точный restore PASS.
С аргументами `-- main output=<directory>` инструмент снимает normal/material-free/
wire/normal на настоящей main-copy с изолированными save/storage,2560×1440 scale1,
FOV40/distance120 и FOV70/distance600. `lod-only` — normal auto/full/auto.
Плотность/дальность объектов не снижаются. Это два статических вида авторской карты,
не576м stress и не расширенная нагрузка32NPC; общий120FPS gate остаётся открытым.

Evidence: `C:/Users/novos/Documents/Codex/2026-11-01/ember-geometry-diagnostic/`.
Near GPU normal9,157→LIGHTING2,134→normal9,306мс; visible973909/shadow1045442
одинаковы между режимами. Wide normal3,769→LIGHTING2,205→normal4,010мс;
visible2239561/shadow886297 одинаковы. На near существенен material/pixel path;
это не доказательство,что всю разницу создаёт земля или что её topology оптимальна.
Камера совпадает внутри каждого сравнения, Source `.tscn`/terrain SHA unchanged.
Снимки LIGHTING/wire просмотрены; F5/клавиши/движущиеся LOD оценивает автор.
Основной viewport переключается отдельно; отражения/подготовка мира не отключаются.
Main auto/full/auto PASS: near visible973909/1181361/973909,
shadow1045442/3368710/1045442; wide visible2239561/3854783/2239561,
shadow886297/4565699/886297. Wide GPU auto3,946/full6,286/auto4,008мс.
Near GPU8,451/9,454/7,116мс нестабилен между контролями; процент выигрыша здесь
не выводить. Подтверждена экономия фактической геометрии/теней, не оптимальность всей земли.
Повторный снимок FPS до обновления оверлея мог показывать старое секундное значение
Performance.TIME_FPS после startup; актуальный FPS окна устранит это расхождение.
Shadow-only control (`shadow-cost/`):полные материалы/autoLOD,shadow on/off/on.
Near GPU8,363/8,538/8,240мс при shadow1045442/0/1045442:выигрыш не установлен.
Wide3,958/3,441/3,985мс при shadow886297/0/886297:в этом статическом виде около0,53мс.
Большое число shadow primitives само по себе не доказывает,что именно тени
создают near material delta. Свет/тени основной карты по этой диагностике не урезались.

Готовая основа: [Godot native mesh LOD](https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html).
У Unity Terrain геометрия также строится из [heightmap](https://docs.unity.com/en-us/engine/6000.6/manual/creating-environments/script-terrain/terrain-heightmaps),
есть [heightmap LOD/frustum culling](https://docs.unity.com/en-us/engine/6000.7/script-reference/unityengine/terrain/enableheightmaplodfrustumculling).
Сам редактор в движке не требует постоянно рисовать authoring-сетку; применимость
другого runtime-представления земли остаётся открытой. Подтверждённое ограничение
mixed-palette plane shortcut описано ниже у terrain owner, его whole-frame вклад пока неизвестен.

### Дорогой ближний камень: контекст оптической глубины01.11

Разделённый read-only разбор shader path и terrain blending нашёл конкретные границы.
Материал камня в foreground использует `EmberVoxelSolidSurface.solid_depth_shader`:
32 ray steps +5 уточнений и до8 self-shadow samples, stone depth20мм.
Ground POM уже отключён; `albedo_relief_enabled=false` у камня не выключает optical depth.
Depth-only контроль9 уникальных detailed materials:near GPU8,368/off5,283/on9,263мс;
wide3,684/off4,011/on3,928мс — вдали выигрыша не установлено.
Отключение uniform оставляет compiled `DEPTH=FRAGCOORD.z`: это не noDEPTH shader.
Сокращать дальность/steps или выключать рельеф этим срезом не стали.

Реализовано у прежних shader owners: ray-invariant weathering weight, triplanar axes
и width factor вычисляются один раз на fragment и передаются через существующий
EMBER_DEPTH_CONTEXT, вместе с прежним edge context. Sampler, маска, свет, количество
шагов, amplitudes/fades и Source не меняются; новых varyings/schema нет.
`stone_finish` использует прежнюю wrapper-функцию. Патч —
`ember_solid_material_layers.gdshaderinc`, `ember_terrain_material_depth.gdshaderinc`,
`ember_compact_terrain_body.gdshaderinc`.

Native main A/B/A (old/optimized/old) near GPU9,262/7,555/9,191мс,
wall10,185/8,546/10,260мс;visible973909 иshadow1045442 exact между фазами.
Это≈18% GPU экономии только данного near view, не whole-game120FPS PASS.
Wide GPU3,895/3,961/4,026мс:отдельного выигрыша нет.
Evidence `weathering-cost/`, исходные3includes — `weathering-reference/` рядом с diagnostic.
Reference — рекурсивно раскрытый прежний shader с теми же defines; normal controls
возвращаются между фазами. Foreground rock ROI x1750:2350/y800:1350 RGB MAE
old/new0,000224 против old/old0,000291; >2/255 pixels0,111% против0,248%.
Это parity на фоне temporal noise, не bit-exact screenshot assertion;новый near снимок просмотрен.
Focused native editor/three-look PASS;comparison helper раскрывает body include перед hooks.
Dense full regression завершён:engine/script errors0,Source/collision/actions/save/release/return
PASS;coverage FAIL и120FPS OPEN сохраняются. Текущие цифры — раздел ниже.

Terrain blend: UV/UV2 IDs выбираются на triangle, COLOR — веса, slots `flat`.
Удаление `_render_palette_ids_valid` ломает покраску; arbitrary mixed flat не сворачивается
без изменения material representation. Обоснованный будущий опыт — отделить paint lookup
от render mesh у текущего smooth owner, сохранив Source/fine floor/editor/остальные облики.
Сравнить суммарный GPU: lookup добавляет texture cost и не гарантирует ускорение.
Редактор переписывать не требуется. Нишевый affine-COLOR shortcut без main coverage не внедрялся.
Готовые принципы: [Godot GPU optimization](https://github.com/godotengine/godot-docs/blob/master/tutorials/performance/gpu_optimization.rst),
[3D optimization](https://github.com/godotengine/godot-docs/blob/master/tutorials/performance/optimizing_3d_performance.rst).
Nonperiodic4tap seam не приоритет: основные grass/soil/sand материалы уже periodic/1tap.

### Дальний solid без ручного DEPTH01.11

Прежний detailed материал сохраняет цвет/слои/finish, но после полного затухания optical
depth использует compiled `EMBER_SOLID_FAR` у того же owner. Геометрия/дальность/residency/
плотность прежние. Body сохраняет depth uniform bindings, затем far define выключает
POM/ручную DEPTH-запись/light multiplier; общий edge context остаётся доступен finish.
`SolidSurface.far_depth_shader` переиспользует программу для исходного shader;
material identity/texture bindings не меняются. `Prop._sync_depth_program` использует
camera→world AABB целиком:вход за fade_far+2м,возврат до fade_far+0,5м.
Default camera priority0,runtime depth process priority1;editor/active Source/morph/no camera
держат full. Published-state owner исключает derived material из authoring serialization.

Native `tools/test_solid_far_material.gd` PASS:auto far/near corner/return/active Source restore,
те же mesh/streams/material/profile/fade uniforms. В640² fully-faded comparison5 pixels
отличаются >2/255,max17/255 — редкие raster/shadow edge samples при снятии manual depth;
это не bit-exact и требует ручной оценки. `test_stone_material_layers` editor/3looks PASS.
Main full/auto/full near GPU8,471/7,693/7,734мс,auto count0;gain не приписывать новой
программе. Wide3,798/3,982/4,156мс,auto count5;visible2239561 exact,устойчивого gain нет.
Evidence `ember-geometry-diagnostic/far-program-cost/`. Native opaque-overlap stress
2560×1440,64copies+original same mesh,303940visible primitives,TAAoff/sunshadowoff:
full4,408/far0,717/full4,432мс GPU. Это экономия в плотном перекрытии,не общий игровойFPS.
Log `C:/Users/novos/AppData/Local/Temp/ember-world-systems-qa/solid-far-overlap.log`.
Dense moving render regression `mode=render` PASS:тот же576м/25848patches/859props/
32NPC/96harvest/16crates/4houses/8lamps,actual2560×1440 scale1,FOV40/70.
Clean median15,127/16,198мс,p9528,880/30,419,p9939,300/39,761,max69,004/51,097.
Устойчивый whole-frame gain не установлен,120FPS OPEN. Fallen0,engine/script errors0,
Source inputs SHA unchanged. Evidence `ember-gameplay-stress/far-program/`.
Неповторённые actions/cold coverage/release-return остаются у последнего full baseline;
его coverage FAIL не закрыт render-mode PASS. Nonlayered far compile/idempotent cache PASS.

### Штатное запекание солнечных теней01.11 — совместимость, не интеграция

Проба по просьбе автора:main Source patch128²+существующий rock,без NPC/анимаций,
в отдельном native editor checkout. Production runtime/maps/resources не менялись.
Owners пробы: `tools/editor_test_static_shadow_bake.gd`,
`tools/fixtures/ember_lightmap_probe.gd`, `tools/test_static_shadow_bake.gd`.
Evidence `C:/Users/novos/Documents/Codex/2026-11-01/ember-static-shadow-probe/`.
Использована кнопка штатного LightmapGIEditorPlugin:сам bake не привязан к GDScript API.
QualityLow/bounces0/no environment bake:проверяется directional shadowmask,не новая GI/художественная настройка.
Sun18°/yaw−55°,bakeDynamic,режим OVERLAY в runtime сохраняет baked static shadow вблизи
и добавляет runtime shadows. REPLACE по [официальному контракту](https://docs.godotengine.org/en/stable/classes/class_lightmapgidata.html)
использует mask только за shadow_max_distance;при отключённых static casters вблизи тени пропадут.

UV2 занят palette/face IDs. На производной копии исходный vertex ID временно сохраняется
в COLOR для штатной unwrap;затем все атрибуты возвращаются по точному remap.
Palette3+face ID пакуются в прежний неиспользуемый CUSTOM0.w;остальные15float custom
компонентов не меняются,adapter shader читает эти IDs,нативный UV2 получает bake atlas.
Это только fixture adapter,не новый Source format/production renderer.
Использован существующий prepare_render_upload:земля16641→16641vertices,
32768→32768triangles;rock14028vertices/4676triangles без потерь. Indexed unwrap≈1,575/0,048с.
Native bake с прогретыми kernel shaders≈3,79с,полный вызов4,106с;ранний cold запуск≈10с.
Штатная unwrap сбрасывает LOD. Пробный rebuild ImporterMesh вернул6levels16384…514tri,
с exact packed vertex/attribute streams и проверкой flat palette/face IDs.
Полный height-error/seam/3look stress этим не принят;Source/collision остаются fine owners.

Runtime normal native2560×1440/scale1,FOV40,near0,05/far4000,TAAoff,та же base geometry.
Paint parity:0pixels >2/255,max1/255. Native LOD visible37456→6736 с теми же packed
vertex/attribute buffers. Static/dynamic/LOD результаты — runtime-result.json. Статическая mask
видна при0shadow draws/0shadow primitives;динамический cube добавляет1draw/12primitives.
Это техническая совместимость,не dense-world120FPS PASS;на двух meshes GPU1,200 realtime
против1,217 baked и1,217 baked+cube:устойчивого выигрыша нет,переход не принимать по FPS этой пробы.
Текстурные image payloads≈1,5MiB для пробы;не полный VRAM/process peak и не оценка всего мира.
Важная граница:убрать все static casters нельзя — dynamic receiver в тени скалы нуждается
в её realtime caster рядом;cached surface mask не затемняет его сама. Проба использует cube,
не меняет персонажей;геометрическая окклюзия выбрана по реальному triangle и sun ray.
В ROI51×54 без static caster998pixels меняются >2/255;возврат static caster приближает
receiver к realtime baseline(остаток15edge pixels). Projection ROI переведён из logical
1600×900 в actual2560×1440:не использовать неподтверждённые ранние ROI результаты.
Editor bake/reopen data сохранены;на закрытии изолированного editor остаётся native
get_node outside active tree error,clean-exit gate OPEN. Runtime cleanup проверяется отдельно.

Рекомендация:гибридное встраивание через прежние derived/cache owners — baked static
receivers +near static/dynamic casters для движущихся receivers;во время authoring/при
невалидном bake остаётся прежний динамический путь. Перед интеграцией нужны cache revision,
совместимые LOD/UV2 всех3обликов,4light presets,память/публикация и общая dense проверка.
Никакие плотность/дальность/тени основной карты ради этой пробы не сокращались.

### Срезаемая трава и листья01.11 — материал и render-crop

По просьбе автора текущий срез переключён со static-shadow integration на траву.
`build_cuttable_grass.gd` берёт цвет/ID покрытия из grass-slot Source main при bake,
включает smooth binding/16 units per metre, убирает отдельный tint0,75. В asset
попадает только grass-role, не остальные покрытия карты. Высокая форма,3 карточных
пучка/24 triangles,стерня4,2 units,64 cut wisps/4 batches и herb/F прежние.
`ember_cuttable_grass` и `ember_grass_cut_effect` подключают прежний
`refresh_terrain_features` для общих материалов при первом использовании;
геометрия/материал не дублируются на каждый стоящий пучок,нового tick нет.
Основная карта уже ссылается на обновлённые prefabs/materials,Source/размещение/
плотность/дальность/персонажи/анимации не менялись. Это не runtime palette rebinding:
после изменения авторского покрытия нужен повторный bake этого производного asset.

Native `test_cuttable_grass`:walk/UI/wall/combat guards,LMB/стерня/разлёт,одна награда,
F,три cold saves,roundtrip/cleanup и compiled program/binding PASS.
Прежний `test_leaf_pile`:удар/проход/reentry/подбор/save/cleanup PASS,код листьев прежний.
`test_cuttable_grass_render`:native2560×1440/TAAoff,FOV40,max_fps60;
render-only Source-crop128×128cells,4096ordinary/128harvest/16leaf piles.
Base/compiled/base-return сохраняют45568 visible primitives;новых ошибок нет.
Последний GPU median33,564/2,528/33,872мс,p9543,544/3,296/44,605мс.
**Параллельно работал Aion2:это наблюдение,не чистый benchmark и не whole-frame gain.**
Этот crop не принимает gameplay/streaming/все3облика или full120FPS;прежний stress
и его открытые gates сохраняются. Чистое повторение без второй игры/ручной main вид OPEN.
Evidence:`C:/Users/novos/Documents/Codex/2026-11-01/ember-cuttable-grass/`;
build/after/leaf/render.log,render/render-result.json,pixel-parity.json и PNG.

Исследование размещения/стоимости травы01.11,без изменения картинки/runtime:
- Detailed `grass_card_mesh`:4 разнесённые плоскости/8triangles;высокий asset
  объединяет3 таких группы с scale(60,120,60). Автор считает размещение плоским;
  последний кадр не является art-приёмкой. Наращивать плотность для сокрытия панелей
  без сравнения форм не рекомендуется.
- `grass-cards-runtime.png`512²:при alpha>=141/255 исходные четыре256²ячейки имеют
  покрытие9,65/11,72/15,19/12,05%. Это mip0/без фильтрации,не замер экранного overdraw
  и не доля GPU времени. Большая прозрачная площадь — кандидат для более тесной
  геометрии вокруг рисунка/узких непрозрачных лезвий вместо широкого прямоугольника.
- Early alpha discard уже есть в начале fragment(),alpha scissor0,55 уже включён;
  не предлагать их как отсутствующие. Ordinary patch cast_shadow=OFF;builder высокой
  травы/разлёта отдельно OFF не задаёт. Не считать все виды травы автоматически
  бестеневыми. Даже без shadow caster общий пигмент/lighting/alpha sample не бесплатны;
  число строк общего include не доказывает выполнение отключённых compiled ветвей.
- Готовые методы:пространственные MultiMesh уже есть;один draw сокращает submission,
  но не число фрагментов/перекрытий. Godot GPU optimization/MultiMesh — ссылки ниже.
  GPU Gems7 (только конструкция объёма,не устаревший alpha-blend pipeline):
  https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-7-rendering-countless-blades-waving-grass
  разнесение направлений для разных ракурсов. GPUOpen2024 (ссылка ниже):корни в области
  patch с разными направлениями/изгибом,дальний LOD с компенсацией покрытия.
  Mesh shaders не требуются и не выбраны для GTX1060.
- Рекомендация следующего визуального сравнения:прежние карточки vs геометрия,
  теснее повторяющая силуэт/разнесённые узкие травинки;для высокого пучка разнести
  корни,направления и высоты вместо простого вытягивания3 одинаковых групп.
  Использовать прежние mesh/scatter/material owners,без нового renderer;плотность,
  дальность,палитра и покрытие сохраняются. Рисунок/объём принимает автор.
  Чистый native1440p A/B на одинаковых near/wide кадрах без Aion2 должен отдельно
  показать стоимость геометрии,alpha/пигмента/света;общий120FPS gate остаётся прежним.

Контурная трава01.11:подключена к основной карте по решению автора;общий120FPS OPEN.
- Автор согласовал простой контур без уменьшения плотности/дальности,тени высокой
  травы сохраняем. Aion2 закрыт,отсутствие процесса проверено перед измерением.
  `grass_card_contour_mesh(Image)` у прежнего Fixture теперь использует встроенные
  Geometry2D.convex_hull/triangulate_polygon для консервативных границ рисунка с8px
  полями. Исходные UV/плоскости/нормали/пигмент/позы сохранены;8→28triangles/tuft,
  площадь0,70557 (-29,44%). Предыдущие58triangles/полосы не выбраны;их evidence
  сохраняется в ember-grass-contour,измерения с Aion2 не использовать как baseline.
- Native Source-crop4096ordinary/128high/16leaf piles,2560×1440,TAAoff,FOV40,
  uncapped/vsyncoff,near/wide/oblique,тот же материал и число растений. Ordinary
  caster OFF,high ON;sun shadow distance1600units. Все9снимков завершены,
  SourceSHA сохранён,script/engine errors0. Raw PNG warning — bake-only Image input,
  PNG input применяется только в bake/probe. Runtime читает готовый ArrayMesh;
  персонажи/анимации не менялись. Консервативная посадка использует прежний card footprint.
- Первое cards/contour/cards-return GPU median:near2,687/2,414/2,694мс;
  wide1,110/1,036/1,110;oblique1,179/1,037/1,180. На этом crop GPU≈7–12% дешевле,
  не вся игра. Render CPU med≈0,10–0,134мс;90samples/view — короткая выборка.
- Из-за wall p95 выполнено только повторное near A/B/A,не весь suite:
  по2с/489,502,472frames. GPU median3,139/2,902/3,207мс;p953,892/3,631/3,921;
  p994,158/3,972/4,292. Wall med3,541/3,346/3,627мс;p958,336/8,554/8,640;
  p9912,466/11,815/12,105;max13,325/13,876/13,064. Render CPU≈0,14мс.
  Выигрыш GPU повторился,но frame tails остаются:стабильные120FPS **не приняты**.
  Теперь sample() использует минимум2с/120frames с p95/p99/max,не фиксированные90.
- Тени присутствуют во всех3ракурсах. Shadow primitives old/new:near26504/38684,
  wide15472/23512,oblique29592/41568. Visible old/new near47616/137216,
  wide45568/135168. Дополнительная geometry/shadow работа включена в GPU измерение.
- Изображение не bit-exact:>2/255 различаются0,210%/0,030%/0,032%pixels
  near/wide/oblique;cards-return совпадает с cards точно. Кадры просмотрены;
  тонкие края/тени,движение/мipmap/fade требуют ручной оценки,стриминг не проверялся.
- Evidence:`C:/Users/novos/Documents/Codex/2026-11-01/ember-grass-hull/` и
  `ember-grass-hull-near-confirm/`:geometry-result.json,PNG;у первого pixel-comparison.json;
  соседние log-файлы. Crop не заменяет dense gameplay gate;подключение описано ниже.

Подключение к main01.11:
- `ember_grass_patch.gd` читает shared grass_card_contour.res (≈1,4КБ),без обработки
  PNG при старте. Обычная трава8triangles вблизи/native ArrayMesh LOD8 вдали;
  дальний уровень содержит исходные8triangles/UV/пигмент,не меньше растений.
  Native key0,05 выбран на1440p near/wide/oblique:выбор индексов делает Godot,
  дополнительных CPU distance callbacks нет. Общая Source-схема не менялась.
- Высокий cuttable/стерня/herb visual пересобраны прежним builder из общего контура;
  высокая трава24triangles/три пучка,тени ON,стерня4,2 units,награда/физика прежние.
  Native strike/F/guards/три cold-save/roundtrip/cleanup PASS.
- Native actual landscape_compact:126ordinary patches,87populated,63329tufts в
  стартовой активной области;shared mesh/UV/палитра,3looks/точный return retained
  buffers и authored size/seed/masks/poses PASS. В test_grass_cards_main ожидание
  переведено на прежний public detail_preparation_pending;временно открытые камерой
  участки не сравниваются с отсутствующим snapshot,камера возвращается к игровой.
  Main PNG — ember-grass-hull/main;мышь/личное F5/вид переходов остаются автору.
- Pure contour28 без LOD на dense live crowd дал GPU7,608мс против свежего baseline7,000:
  не переносить локальный выигрыш на всю дальнюю массу. Поэтому добавлен штатный LOD.
- `-- lod-parity`:4096ordinary,исходные карты vs forced native far,2560×1440;
  ни одного отличия >2/255. Число instances4096 сохранено. Наблюдение счётчика Godot:
  visible primitives показывает8 вместо32768 для того же изображения при MultiMeshLOD;
  по этому счётчику нельзя доказывать уменьшение растений. Source buffers/image обязательны.
- Final LOD crop old/new/old GPU:near2,699/2,427/2,707;wide1,106/1,058/1,106;
  oblique1,178/1,038/1,178мс. Минимум2с/sample,тени есть во всех3ракурсах,errors0.
  Evidence:ember-grass-lod-parity/lod-parity.json и ember-grass-hull-lod-final/geometry-result.json.
  Окончательный общий render-route — ember-gameplay-stress/grass-hull-lod;
  baseline — grass-hull-before,невыбранный all28 — grass-hull-after.
- Все3 render runs технически PASS,engine/script errors0. Итоговый LOD сохраняет
  начальное покрытие ровно:205766grass/8539flower/621wheat/263resident;baseline такой же.
  Live32NPC wall median20,630→20,369мс,GPU7,000→6,031;p95GPU7,839→6,423,
  p998,108→6,487. Это≈14% GPU gain этого нагруженного кадра,не whole-FPS gain.
  Clean out40/back70 wall med16,177/16,364→16,111/16,550мс;
  p9530,243/29,914→30,314/30,727;p9942,013/40,674→42,670/42,829;
  max89,999/87,707→83,002/78,783. ПаденийNPC/ящиков0,32NPC/16crates/4houses/
  8lamps/4local shadows сохранены. 120FPS **OPEN**;полный wall кадр почти прежний.
  Render mode не повторяет harvest/cold coverage/release;действует прежний полный
  baseline/coverage FAIL,а срезание/подбор/cold saves проверены отдельным cuttable gate.
  Подключение травы завершено технически;личное F5/движение/переходы остаются автору.
  Дальнейший приоритет автора — персонажи/анимации,не ещё одна полировка травы.

Уменьшение по просьбе автора01.11 — текущий вариант:
- Обычный пучок28→8triangles,высокий84→24:по2triangles на каждую из4карточек,
  у высокого3пучка. Вместо28-triangle hull — поддерживающая трапеция вокруг
  padded artwork. Она не срезает исходный консервативный контур;площадь0,75146
  исходных прямоугольников вместо0,70557. Дополнительные прозрачные поля — осознанная
  цена меньшей geometry,материал/атлас/позы/дальность/количество растений прежние.
- Cut wisps10→3triangles/blade:root/upper bend/tip,один quad+tip triangle;средний
  перегиб и обратные дубликаты убраны,cull_disabled сохраняет обе стороны. Все64
  blades/4batches/ветер/lifetime/постепенное исчезновение сохранены. Native cuttable
  guards/стерня/тени/подбор/три saves/roundtrip/cleanup и3triangles assertion PASS.
- Main/3looks/retained return/UV/shared mesh/authored fields PASS;126ordinary/
  87populated/63329tufts в стартовой области. Evidence:ember-grass-simple/main и cut.
- Dense mode=render PASS,errors0,начальные205766grass/8539flower/621wheat совпадают
  с предыдущим вариантом. Clean out40/back70 wall med15,850/15,895мс;
  p9530,409/30,168;p9942,509/40,491;max81,321/104,849. Whole120FPS **OPEN**.
  Отдельный static GPU median7,037 против прежних6,031 потребовал контрольного A/B.
- В том же запущенном dense кадре заменяли только ordinary mesh,current8/previous28/
  current8-return:GPU med5,993/6,096/6,015мс;p956,439/6,548/6,486;
  p996,602/6,693/6,659. Wall med19,791/20,038/20,444мс. Instance buffers точные,
  материалы/популяция/камера прежние,errors0. Регресс GPU в этом контроле не повторился;
  небольшой выигрыш не переносить на FPS всейигры. `EMBER_GRASS_COMPARE_MESH` —
  opt-in только stress harness:диагностика завершается без повторения clean route.
- Evidence:ember-gameplay-stress/grass-simple и grass-simple-compare,root
  C:/Users/novos/Documents/Codex/2026-11-01/. Предыдущие варианты сохранены в
  ember-grass-simple/previous-28-lod.res,previous-high.scn,previous-scatter.scn.
  Срез сокращения геометрии закончен технически;ручной F5/вид движущихся краёв OPEN.

## Доверенная текущая точка

Текущий игровой stress01.11 — `tools/test_world_gameplay_stress.gd`,
evidence `C:/Users/novos/Documents/Codex/2026-11-01/ember-gameplay-stress/weathering-context/`.
Автор расширил нагрузку:прежний dense576м/25848patches/859props/16ящиков/4дома/8фонарей
+32анимированных Hoshi(136bones),32яблони,32ягодных куста,32срезаемых пучка.
Это новый baseline,не A/B с прежними16NPC. Native Forward+ Vulkan/Jolt60Hz,
actual2560×1440/scale1/TAA,uncapped,прежние density64/10/8 и grass/flower size+25%.

- Все32NPC active;центры27/FOV40 и32/FOV70 внутри frustum. Это не pixel occlusion
  count;native screenshots просмотрены,толпа действительно попадает в кадр.
- Clean out40/back70:median15,133/15,404мс;p9529,452/29,216мс;
  p9940,806/40,532мс;max82,587/79,336мс;96,54/97,14%кадров дороже8,33мс.
  **120FPS OPEN**. Live crowd с диагностическими render timers отдельно:
  wall median19,737мс,GPU7,137мс,renderCPU3,956мс. Устойчивый whole-crowd gain
  от shader context не установлен. Предыдущий Performance physics monitor14,638мс обновляется с собственной
  частотой:это ориентир следующего профиля,не точное покадровое exclusive CPU время.
- Реальные `world_strike`/nearest/`_try_interact`:яблоко падает/подбирается,
  ягоды+3,herb+1,стерня появляется,повторной награды нет. После release/return
  сохранены whole/dropped/collected состояния,остальные экземпляры неизменны;
  Реальные автосохранения остались в уникальном user://ember-tests/ sandbox.
  Предыдущий synchronous operation wall(including save wait):первый удар41,4–46,1мс,
  повторный удар безsave23,6мс,подбор12,6–21,5мс. Это не exclusive CPU/autosave attribution.
- Streaming gate **FAIL**:out1138/1950affected frames(max49absent patches),
  back475/1885(max38). Floor0/0,все32NPC/16ящиков живы. Release283/283,
  return281exact+2необязательных hysteresis-band patches. Engine/script errors0,
  Source inputs3+main.tscn SHA неизменны. Не наследовать старый streaming PASS.
  Baseline hidden-pickup-fix:median15,080/15,767мс;p9528,217/29,418;
  coverage1425/1945 и695/1834. Новый run не является streaming fix или whole-FPS gain.
- Исправлена availability-aware preparation/physics interest:закрытый flag-gated
  WorldItem остаётся в recovery/save registry,но не prepare/anchor. Hide re-arms hold;
  first/repeated/remote reveal и available restore делают once prepare,ждутfloor,
  потом thaw/однократный pending impulse. Обычные sleeping/frozen/carried/actors сохранены.
  Focused physics RED→GREEN;native harvest/return PASS. Активных anchors вlivecrowd
  125→55,подробных tiles520→396. Это устранение лишней работы,**не whole-FPS gain**.
  Доисправления `full/`:median14,866/15,780мс,p9529,096/28,837;coverage1083/1918,
  476/1825affectedframes. Hidden-pickup-fix coverage был хуже;причинность одним run не доказана.
  Скрытые предметы не должны служить случайным prewarm:нужен явный camera/view interest.
  Старый counterfactual108tiles относится только к64stress pickups. Текущий raw
  hidden_support.marginal=-8 недействителен какgain:он исключал64stress IDs,но оставлял
  ещё закрытые authored pickups,которые новаяpolicy тоже исключает. Будущий harness
  считает все закрытые WorldItems иsame-world live bodies;этот diagnostic поправлен
  послеrun,check-only PASS,на clean/coverage/action проверки не влияет.
  CPU/physics32NPC измерены ниже;далее secondary rig path и явный view preparation;
  synchronous action/save cost остаётся отдельной измеренной проблемой.

Harness использует production prefabs fruit_tree.scn/berry_bush.scn/cuttable_grass.scn
с уникальными стабильнымиIDs доadd_child;после добавления — штатный world-item refresh.
Обычный GrassPatch не принимает удар:срезаемые пучки не доказывают срез всего луга.
CLI:после `--` передать `fixture-root=<папка terrain_576.res,population.scn,plan.res>`
`output=<папка>` `[cache=<папка>]` `[mode=full|interactions|render|cpu]`. Native Forward+/Jolt и
private Hoshi обязательны;missing catalog/worldScene/icon/input завершают до сцены.
`mode=interactions` сохраняет полную популяцию и реальные действия,пропускает только
moving/coverage;его PASS не равен full PASS. Input bundle+manifest — evidence/fixture.
Рабочая авторская карта не переписывается,второй развиваемой карты нет.

Начальный `initial/` run отвергнут:изолированный старый stage не содержал актуальные
apple/forest_berry/herb Resources. После полной синхронизации code/content/prefabs/
scenes/shaders/cache проверены preflight и actual bindings. Файлы runtime механик
не менялись. Один interaction approach поправлен с5 до10world units,сохранив
production reach и настоящую проверку свободного места средиNPC/тел.

### Вклад NPC, анимаций и обслуживания мира01.11

`mode=cpu` того жеharness,изолированный Forward+/Vulkan/Jolt/native2560×1440,
actualFOV70,scale1,TAA,uncapped;32NPC/136bones и вся прежняя dense нагрузка сохранены.
Это stationary attribution,не moving/cold coverage acceptance. Evidence:
`C:/Users/novos/Documents/Codex/2026-11-01/ember-cpu-attribution/`
(`result.json`,`summary.json`,`cpu-sample-*.json`,`engine.log`,`harness.gd`).

В каждой фазе минимум240frames/3секунды после1,6секундыsettle;GPU/script profiler
выключены. Между отключениями возврат кполному режиму,все модели остаются вмире.
Семь full controls:median19,855–20,697мс,p9525,106–27,587мс.
- Только NPC controllers off:median17,270мс,p9519,873. Это fixture move_and_slide,
  не productionAI;native CharacterBody/коллизии не удалялись.
- Только NPC animations off:11,555мс,p9514,986.
- NPC controllers+animations off:8,817мс,p9511,094;не gameplay120PASS.
- World script callbacks off(562узла внеplayer/NPC subtrees):15,572мс,p9517,536.
  Native rendering/physics/timers/coroutines остаются;это не цена всего мира.
- Только blink morph writes off:19,909мс,p9526,320 — заметныйgain не установлен.
- Только32SpringBoneSimulator active=false:14,727мс,p9517,479.
  Это временное диагностическое изменение движения волос/одежды,не принятое качество.

Отдельный instrumented full interval:GPU median6,765мс,renderCPU3,969;
32NPC controller call scopes наrenderframe median2,043мс,p954,277;
Hoshi visual call scopes0,900мс,p951,053. Разница абляций больше синхронного scope:
обновления рига запускают отложенную native обработку;её точный внутренний участок
ещё не установлен. Нельзя всю разницу назвать GDScript временем или сложить gains.
Performance physics monitor обновляется отдельно и не даёт exclusive CPU attribution.

Native scripts profiler — ещё отдельные180frames сoverhead. Coroutine cpu_comparison
накапливает ожидание и исключена изCPU rankings;ACCUMULATED total тоже неCPU сумма.
Контроллер:0,495с/8096calls;GrassPatch._process0,245с inclusive/48240calls;
shadow update0,078с/4793calls;Map object poll0,127с/126calls. Это profiled interval,
не clean per-frame budget;вложенные scopes не складывать.

Exit0,engine/script errors0,SourceSHA unchanged;всеcallback/blink/spring flags восстановлены,
32NPC/16ящиков alive;220135vegetation instances/25848patches до/после совпали,
camera transform/FOV70/native resolution сохранились. Initial sibling
`ember-cpu-attribution-initial-diagnostic-errors/` отвергнут как чистаяприёмка:
typed Array.has получал неCharacterBody при обходе;typeguard исправлен передповтором.

Проверка secondary path01.11:штатный mutable_bone_axes=false сравнен сtrue.
360nativeForward+шагов idle/walk/run+bodymotion дали exact совпадение всех136post-modifier
bone transforms. Но dense32NPC A/B/A **не дал whole-frame gain**:cached axes
median20,088/19,983мс,p9525,518/25,718;исходныйmutable режим19,954мс,p9525,363.
Candidate runtime helper удалён;источник Хоши/частота/quality policy не менялись.
Evidence `C:/Users/novos/Documents/Codex/2026-11-01/ember-secondary-rig/`:
quality-native.log,axes-quality.json,combined/result.json,combined/harness.gd,
rejected-candidate-hoshi-visual.gd. Это отрицательный эксперимент,не оптимизация.
Новая focused проверка установила near120pose=120spring steps,far15spring:
двойного native advance не обнаружено. Механизм callback не обходит существующийLOD.
cpu-secondary harness оставлен только как диагностическое сравнение;его PASS
не принимает performance. Повтор общего moving маршрута не запускался послеотката:
runtime representation не изменилось,старые coverage/120 gates остаются открытыми.

### Постоянные каналы locomotion01.11 — отклонено

После завершения геометрии травы автор перевёл приоритет на персонажей/анимации.
Native inventory:Face/Body/Hair используют один Skin и один SkinReference RID на
скелет;повторного skin binding нет. Callback setter штатного Skeleton3D уже
пропускает неизменное значение. Новые runtime wrappers для них не добавлялись.

Проба убирала12постоянных finger rotation tracks изкаждого idle/walk/run:56→44,
общая библиотека на всехNPC,постоянные позы задавались приsetup. Источник/REST/136bones,
частота pose/springs,плотность/дальность не менялись. 480native шагов сcrossfade,
body motion,NPC manual/party automatic modes:post-modifier maxposition0,000000127м,
maxbasis0,000002427,ошибок0. Более широкое удаление констант корпуса/глаз отклонено:
оно давало заметно большую численную разницу входов secondary simulation.

Dense32NPC same-process original/compact/original,Forward+/Jolt/native1440p,
render timers off,по240frames после1,6сsettle:wallmedian19,881/20,157/21,526мс,
p9526,336/26,278/30,398мс. Ускорение **не подтверждено**,контроли дрейфуют.
Candidate полностью откатан;исходные клипы и runtimeчастота сохранены. Новый moving
маршрут не запускался послеотката:production representation идентично baseline.
Evidence:`C:/Users/novos/Documents/Codex/2026-11-01/ember-motion-compact/`
(fingers/pose-quality.json,crowd/result.json,сохранённые candidate/harness/оригинал);
skin inventory — соседний`ember-character-skins/skin-inventory.json`.
Это отрицательный эксперимент,не новыйFPSgain. Следующий предмет работы — стоимость
native secondary rig;повтор cached axes/constant tracks не нужен. Снижение качества
ближних волос/частоты всего скелета и custom engine этим срезом не согласованы.

### CPU после разделения важных героев и NPC01.11

Задача автора — найти оставшийся расход при8important+32ordinary,native2560×1440,
без снижения плотности/дальности. Production-код не менялся;расширен существующий
`test_world_gameplay_stress.gd`,`mode=cpu-hub`. Никаких новых героев/party/save IDs.
ActualFOV70,TAA,scale1,Forward+/Vulkan/Jolt,uncapped;все модели/геометрия/физические
тела остаются. Temporary cuts восстанавливаются;это attribution,не gameplay120PASS.
Каждый interval240frames≥3с после1,6сsettle,render timers off;между cuts полныйрежим.

Первый прогон:семь controls wallmedian17,724–18,407мс,p9523,243–30,195.
- 32ordinary controller callbacks off:15,620мс,p9519,716. Это fixture move_and_slide,
  не стоимость productionAI;семь hub controllers и player продолжаются.
- 32ordinary visual callbacks off(их springs ужеOFF):15,459мс,p9518,974.
- Только secondary восьми важных героев off:16,535мс,p9519,863.
- Восемь важных visual callbacks+secondary off:16,256мс,p9522,673.
- Все40visual callbacks+secondary off:12,944мс,p9516,005;даже это не120FPS.
- 562world script callbacks внеplayer/crowd subtrees off:14,080мс,p9516,994.
Разницы — пересекающиеся counterfactual эффекты,не exclusive CPU scopes и не сумма.
Наиболее крупная совокупность — animation/rig updates≈5мс;world callbacks≈4мс,
ordinary controllers≈2–3мс. Волосы восьми героев≈1–2мс уже не главный одиночныйвклад.

Уточняющий прогон толькоworld groups оправдан вкладом≈4мс,весь прежний gate не повторён:
`EMBER_CPU_HUB_WORLD=1 mode=cpu-hub`. Пять controls18,358–18,934мс.
- 268GrassPatch callbacks off:16,943мс,p9526,651 — вклад≈1,4–2,0мс.
- ОдинMapLoader(его idle+physics callbacks)off:16,907мс,p9521,891 — вклад≈1,5–2,0мс.
- 60VoxelProp callbacks off:18,546мс,p9525,927 — устойчивого выигрыша нет.
- Остальные233callbacks off:17,389мс,p9524,163 — меньший совокупныйвклад.
Группы классифицированы текущими owners;inventory paths/scripts сохранён вresult.
Это не цена всей травы/всей карты/всех объектов:render/native/timers остаются.

После восстановления отдельно instrumented live:GPUmedian7,421/7,458мс,
последнийp959,050/p999,748мс,20%GPUframes>8,33мс;renderCPUmedian4,591/4,689мс.
Walllive17,949/18,808мс. ПоэтомуCPU — первый приоритет,но GPUtails тоже не проходят
120budget. Вычитать GPU изwall нельзя. Вполныхcontrols былиmax≈190–208мс;
отключениеworld callbacks не устранило большие stalls. Их источник не установлен,
нельзя приписывать их этим же steady-cost группам или объявлять системными.

Оба exit0/errors0,полное восстановлениеcallback/spring flags,camera exact,
39crowd actors+player supported,SourceSHA unchanged;NPCsolvers0/important8.
Evidence:`C:/Users/novos/Documents/Codex/2026-11-01/ember-cpu-hub/`:
`result/result.json`,`attribution-harness.gd`,`world-groups/result.json`,
`world-groups/harness.gd`,cpu-sample rows иlogs. Production hair policy сохранена.
Новый moving/cold/interaction прогон не нужен:менялась толькодиагностика;старыеgates OPEN.
Следующий практический срез — регулярные GrassPatch проверки готовых участков и
MapLoader activity/detail checks;менять existing scheduling/cache invalidation,
а не плотность/дальность/геройское качество. Затем ordinary pose/controller cost.
VoxelProp callback микроправки и повтор cached axes/constant tracks не приоритет.

Архитектурная гипотеза автора01.11:строить лёгкую поверхность с переменной
детализацией,затем при необходимости вокселизировать;деревья тоже рассмотреть
отдельно. Пока обсуждение,не разрешение на новый mesher/миграцию. Рекомендация:
разделять редактируемый источник и runtime mesh;основной рельеф — поверхность
высот/упрощённыечанки,локальная voxel geometry только где нужна объёмность.
Полная повторная вокселизация может вернуть плотную сетку;низкополигональность
не следует из порядка конвертации. Flat coalescing/nativeLOD уже есть,но качество
ближнего smooth/mixed-material meshing отдельным последнимCPUзамером не принято.
Возможная ограниченная проверка:один существующий участок main,один источник,
текущий mesh vs облегчённый derived mesh,сохранить силуэт/цвет/стыки/общую физическую
поверхность;измерить подготовку,CPU/GPU/память. До неё всюземлю/деревья не переделывать.
Для готового heightmap/clipmap подхода изучать
[архитектуруTerrain3D](https://terrain3d.readthedocs.io/en/latest/docs/system_architecture.html);
clipmap распределяетLOD подкамеру,это не автоматическое упрощение по кривизне.
Текущий приоритет grass/map CPUchecks сам собой этойидеей не заменяется.

### Новая обычная земля:первичная проба Terrain3D01.11

Автор уточнил направление:обычный рельеф первичен,вокселизация только ПОСЛЕ его
оптимизации. Не derived mesh прежних voxel-колонок. Текущийpriority переключён
наограниченный spike;точка возврата — grass/map CPU checks выше. Production owners,
карта,герои/материалы/плотность/дальность не менялись;нетнового renderer вcheckout.

Готоваяоснова Terrain3D v1.1.0-stable,MIT,официальный release Godot4.5–4.8+;
изолированный внешнийproject сGodot4.7.2/Forward+/Vulkan/Jolt/native2560×1440.
НовыйRF heightmap512²:холм/узкийгребень,4региона256²,vertex_spacing1,mesh_size16,
6clipmapLOD,диагностическийshow_colormap безконтента Ember. API brush33² меняет
48→54м,сохранённыйисточник reload54м,physicsray54м. Движение камерыFOV70 выполнено;
обычный/wireframe PNG просмотрены. Exit0,script/engine errors0 вфинальном прогоне.
Это техническаяпригодность готовойосновы,не принятая интеграция/визуальнаякисть.

Последнийprobe(≥2с/1800+frames наinterval):near40/wide70/moving70 wallmedian
0,963/0,959/0,927мс,p951,433/1,414/1,506,p991,661/1,592/3,859;
max130,716/131,575/16,391. GPUmedian0,900/0,897/0,867мс,p951,347/1,341/1,308.
Статические visible primitives12624/27416. Длинные wallпаузы есть даже вэтой
отдельнойпробе;их причину/связь сEmber stalls не установили. Нельзя объявлять
terrain готовым кминимальным120FPS или сравнивать его≈1мс сполным40rig кадром.

API edit+GPUmap upload+локальная dynamic collision rebuild17,296мс однократно;
import→60settle frames189,405мс(не exclusiveCPU import). Исходная проба fullcollision
всех4регионов дала289,759мсcommit иотложена;штатный dynamic collision mode дешевле.
Ранняя directheight edit безcollision.update оставляла старуюфизику48м;исправлено
официальнымcollision.update(...,true). Нужен единый commit terrain+physics вбудущей
интеграции,а не несогласованные поверхности. Undo/Redo/discard/UI здесь не проверены.

Evidence:`C:/Users/novos/Documents/Codex/2026-11-01/ember-primary-terrain/`:
result.json,probe.gd,native-moving.log,ordinary.png,wireframe.png,source-regions/,
initial-stale-collision.json,full-collision-control.json. Disposable project:
`C:/Users/novos/AppData/Local/Temp/ember-primary-terrain-probe/project`.
Дальше — interactive authoring исравнение наодномexisting main участке вQA,затем
одинаковыйdense gate. Вокселизацию/деревья не начинать до обычнойземли;выбор схемы
источника/migration отдельный gate. Первичное решение/ограничения — Terrain Authoring.
Источники:[официальныйrelease](https://github.com/TokisanGames/Terrain3D/releases/tag/v1.1.0-stable),
[clipmap architecture](https://terrain3d.readthedocs.io/en/1.1/docs/system_architecture.html),
[Collision API](https://github.com/TokisanGames/Terrain3D/blob/v1.1.0-stable/doc/api/class_terrain3dcollision.rst).

### Прямое сравнение current smooth mesher и Terrain3D01.11

Разрешение автора:сравнить альтернативу,закрепить правило против длительной
оптимизации безпроверки готовых вариантов. Правило добавлено вAGENTS/Workflow;
это не автоматическое разрешение migration. Реализация сравнения тольковQA,
production код/карта/плотность/дальность не менялись.

Один continuous64×64м field:плоскость+холм+узкийгребень. Current использует
реальные SmoothSurface.build_arrays→nativeLOD→prepare_render_upload/publish,
256чанков64²,шаг0,0625м;prepared_field передан напрямую,без source conversion/
smooth filter. Terrain3D1.1.0 — image256²,шаг0,25м,mesh_size16/6LOD. Одинаковая
исходнаяформа,норазная дискретизация! max difference2,198см на2000height queries
черезget_surface_height. Это LOD0 data check,не доказательство5см error всех
дальних renderLOD/физики. Sides/edge policy тоже различаются;manual silhouettes OPEN.

Native1440p/scale1/TAA/FOV40 и70,Forward+/Vulkan/RTX5070,uncapped. Порядок
current/Terrain3D/current-return втомже процессе. По≥240frames/2,5с после90frames
settle. Оба минимальные одноцветные unshaded paths:StandardMaterial уcurrent,
upstream minimum vertex shader сconstant fragment уTerrain3D. Нет terrain layer
texturing наобоих;диагностические цвета отличаются(assetless gray уTerrain3D),
pixel/material parity не заявлена. Это стоимость renderer paths,не всего terrain.

Bare near40 GPUmedian1,026/0,712/1,025мс;wide70 0,786/0,551/0,760мс.
Visible triangles45416→11640near,80732→25832wide;draws112→12 и256→26.
Подготовкаcurrent geometry51,399с(включает16frame yields),Terrain3D import+30frame
settle0,332с;shared field≈0,37с отдельно. Image extraction/конструкторTerrain3D
вданный import timer не входят. Это не полнаясравнимая загрузка приложения:
объёмдискретизации иработы различается;вреальномредактореcurrent имеетcached update.

Loaded — теже40Hoshi(8important/32ordinary),теже262144grass(64/м²),одниMMbuffers
иакторы междуфазами,безуменьшения растительности. НетNPCcontrollers/worldcallbacks,
props/flowers/water/Embermaterials/света полнойсцены;physics выключена уобоих.
near40 wallmedian5,326/5,069/5,431мс,p956,801/5,979/6,597,
p9911,031/6,394/7,378;GPU4,401/4,372/4,472мс.
wide70 wallmedian4,934/4,590/4,741мс,p956,358/5,683/5,905,
p997,014/6,464/6,542;GPU3,554/3,855/3,572мс.
Wallmax128–153мс встречается вcontrols/bare;candidate near7,095/wide8,175мс
вэтомкоротком loaded interval. Исчезновениеstalls не доказано,их причину не нашли.
Результат:небольшоеулучшениеwall≈0,2–0,36мс относительно соседнихcontrols,
GPU приloaded wide хуже≈0,3мс. Меньшеtriangles не означает пропорциональныйFPSgain.

Финальный exit0/nativeerrors0,qualitycheck PASS. Начальныепробы не принимать:
raw get_height сравнивал nearest texel сsurface вместоget_surface_height;
default color-debug оставлялдругой material path;первыйminimum override не учёл
debug injection uv идалshadererror. ИхJSON сохранены какrejected controls,
финальнаяпроба отдельная:accepted-native.log/result.json/accepted-harness.gd,
terrain_ab_minimum.gdshader/verification.json иPNG в
`C:/Users/novos/Documents/Codex/2026-11-01/ember-terrain-ab/`.
Both backends resident одновременно:счётчикиRAM/VRAM изsamples не являются их
раздельнойценой/выгрузкой. Полный8important+32NPC gameplay18мс сюда не переносится.

Рекомендация:продолжить Terrain3D как кандидата первичнойобычнойземли из-за
готового authoring/дешёвойподготовки,но не объявлять его выбранным production
renderer или решением120FPS. Следующий integration gate — кисть/Undo/save/общая
physics surface и тотжеdensemain workload,включаяworldlogic/materials. До него
текущую картуне переносить;вокселизация/деревья остаются следующимэтапом.

### Terrain3D:authoring backend иmain render integration01.11

Срез автора выполнен вQA,безmigration. NativeGodot4.7.2 Forward+/Jolt editor:
Terrain3DEditor Sculpt/Average→GodotEditorUndoRedoManager.3samples=однаaction;
54→56,863140→54,733410м. Всеprimaryregionheightbytes exact послеUndo/Redo;
physicsray послеUndo53,999992м приdata54м. Save/discard/reload exact. Последние
sculpt139,534мс/3samples,smooth78,422мс/4samples inclusive,не per-frame budget.
Incremental save_directory требует unchanged backingfiles приSaveAs. Mouse/UI,
Emberпанели/dirty state/validation ещёOPEN. Nativehistorybridge использует4штатных
forwardingmethods,это backend APIgate,не полнаяприёмка upstreamUI. Evidence:
`C:/Users/novos/Documents/Codex/2026-11-01/ember-terrain-authoring/` result.json,
editor-physics.log,runner.gd,saved-regions/. Initial crash —fixture.plugin.ui null;
первыеhash/save проверки использовали неподходящиеimagearray/backingfiles. Исправлены,
не являются доказаннымиproductionдефектами Terrain3D.

Main-copy:1440p/scale1/TAA/FOV40/70,8important+32NPC ипрежниеobjects/grass/lights/
callbacks. Подменяется толькоrender221resident groundtiles в64мcrop:region512,
heightimage1024²,обеfine spacing1/16м. MaxLOD0dataheight difference1,569мм/1707points;
не доказательство error дальнегоrenderLOD. Старыеphysics/height/scatter/navigation
остаютсяauthoritative,candidatecollisionsOFF. Во всехфазахanchors142/tiles516/
harveststates совпали;сравнение с прежнимиanchors62 не являетсяпарным. Original
илиconstantunshaded crop;Terrain3Dminimumshader/diagnosticfill,неmaterialparity.

original/neutral-current/neutral-Terrain3D/neutral-return/original-return,
180frames после20settle,render timers ON,не cleanmovingroute. Neutral A/B/A:
FOV40 wallmedian18,058/17,489/17,801мс,p9526,342/25,177/24,677,
p9933,930/41,018/40,099;GPU6,201/6,206/6,207,renderCPU3,67/3,49/3,65мс.
FOV70 wall20,261/18,800/19,592мс,p9532,711/27,316/27,614,
p9948,340/42,627/38,587;GPU6,369/6,523/6,503,renderCPU4,66/4,36/4,66мс.
OriginalGPU6,723/6,753near,7,351/7,258wide:нейтральныйматериал экономит≈0,5–1мсGPU,
mesh replacement GPUgain не дал. Candidatewall нижеcontrols,норазброс/частичная
подмена не позволяют обещать весьframegain migration. Candidatemax201,880/207,256мс.
Exit0/nativeerrors0,SourceSHA unchanged,original visibility/materialrefs restored,
все39crowd+player supported. Automatedcorrectness PASS;**visualintegration OPEN**:
видны diagnosticchecker/crop/LODseams. Не равноценнаякартинка и неproductionвыбор.
Стараяподготовка/физика/grasschecks продолжалась:это неCPUтест полного новогоowner.
Следующийgate — shader/стыки/preview,затем единыйsource→physics/scatter/editor;
не повтор того же meshbenchmark. Вокселизация позже. Evidence:
`C:/Users/novos/Documents/Codex/2026-11-01/ember-terrain-main-ab/` final/result.json,
final.log,terrain_main_ab.gd,harness.gd,verification.json,PNG. Rejectedimports не
использовать:region_size доnativeinit оставался256;после treeinit установлен512,
свойство иуспехимпорта проверяются доhidingoldground.120FPS/stalls OPEN.

### Terrain3D:освещённый участок безdebugfill02.11

Продолжение тольковQA:рабочаякарта/productionrenderer не менялись. Вместо рваной
маскиfine residency подменён цельный32×32м crop(64fine tiles),вокруг него64м поле
поддержки. Внутриcrop все исходныеfine tiles обязательны. За пределамивидимогоcrop
допускается coarse support,ноfragment исключает его изотрисовки. Нет искусственных
controlmap holes по границамsleeping tiles;старыйoverview подcrop не дублируется,
так каквесьcrop уже занятfine tiles. Native clipmap target —player;mesh_size48/
5LOD,region512,spacing1worldunit=1/16м. Это изменениестенда/настроек,не исправление
установленного upstream mesher bug. Предыдущий64мhole-mask A/B не повторялся.

ШтатныйTerrain3Dminimumshader сохраняетlighting/height-derived normals,его
constantalbedo заменён нацветземли идобавленаcrop boundary. Currentcontrol —
обычныйlit StandardMaterial тогоцвета/roughness0,7. Всеshow_* debug flags выключены
послеdeferred initialization ипроверены вкаждойфазе. Нормали/свет/тени работают;
старыеchecker/видимыещели не обнаружены наFOV40/70 кадрах. Это focusedvisual check,
неприёмка финальныхматериалов/всехдальностей. Старыйsource/physics/scatter остались.

Тотжеnative1440p/TAA/8important+32NPC/прежниеgrass/props/lights/callbacks;
180frames +20settle,render timersON. Litcurrent/Terrain3D/current-return:
FOV40 wallmedian16,919/16,761/16,610мс,p9520,314/22,567/20,835,
p9927,624/28,720/32,261;GPU5,619/5,884/5,405 — устойчивогоnear gain нет.
FOV70 wall18,389/17,829/18,404мс,p9524,386/22,877/26,128,
p9934,765/31,129/39,305;GPU6,060/6,297/6,042 — wall≈0,57мс лучше,ноGPU дороже.
С64мunshaded01.11 напрямую не сравнивать:другиеcrop/material/clipmap settings.
Sourceheight maxdifference1,745мм;prepare3034мс включает30liveframe settle.

Отдельный **motion-only** gate не повторяетstaticA/B:actualplayer идёт по короткому
существующемуAStar маршруту внутриcrop ивозвращается.2legs/168frames,fallen0,
restoration exact,SourceSHA unchanged,engine/script errors0 вдвух прогонах.
Кадры послекаждойноги просмотрены,старыещели/заливка не повторились. Motion wallmax
1115,528мс загрязнён PNGcapture междуlegs;это не cleanFPS/stall оценка. Авторская
оценка непрерывногоLOD/управления иобщий120FPS остаютсяOPEN.
Evidence:`C:/Users/novos/Documents/Codex/2026-11-02/ember-terrain-visual/`:
result/result.json,engine.log,motion/result.json,motion.log,motion_leg*.png,
terrain_main_ab.gd,terrain_visual_lit.gdshader,harness.gd,verification.json.
Текущийсрез визуальнойпробы закрыт технически;далее — единыйновыйsource→physics/
scatter/Embereditor безmigration авторскихкарт. Не запускать сноваэтотжеmeshA/B
без новогоизменения/риска. Ни120FPS,ниготовый новыйредактор не объявлены.

### Terrain3D: первичный источник, физика и трава02.11

Проверка выполнена только во внешней QA-копии `landscape_compact`, не в рабочей
карте. Внутри цельного32×32м участка Terrain3DData стал источником высоты для
native renderer/collision, Ember floor queries и существующего grass scatter.
Начальная форма импортирована из прежнего stress-рельефа для сопоставимости;
последующая лепка меняла только native heightmap. Старые semantic paint/water
данные сохранены как fixture, это не законченная миграция схемы. Снаружи участка
прежний источник/физика; внутри старые GroundPhysics выключены. Native controlmap
holes исключают физику снаружи, поддерживающие render-данные не рисуются.

**Результат:** final Forward+/Jolt exit0, script/engine errors0, утечек на выходе0.
На исходной, изменённой и загруженной поверхности по200native rays и8стыковых
rays проходят; максимальное floor/collider расхождение≈1,52мм. Native кисть
подняла точку на≈17,9см; три operate дают одну Undo action. Undo/Redo возвращают
height bytes точно; save/reload отбрасывает несохранённую правку. Legacy Resource
до/после побайтово одинаков. Реальный игрок проходит короткий маршрут туда/обратно
(2legs/182frames); все8важных+32обычных NPC и объекты остаются поддержанными.

**Найденный пробел интеграции:** revision недостаточно для grass disk cache:
его content digest считал только legacy integer heights. Новый источник менялся,
но получал прежние transforms из кэша. QA-adapter добавляет namespace и реальные
native float heights в digest, штатный scatter/worker не заменён ручным сдвигом.
После правки1034/1034пучка сохранены,564изменили высоту; max root error≈1,80мм.
Проверен painted ordinary look0; это не приёмка всех растительных видов/трёх обликов.
Reload пустого texture bank снова включает `show_checkered`; перед capture/debug
аудитом флаг явно выключен. Final capture flags пусты, снимок просмотрен без сетки.

**Стоимость и граница выбора:** diagnostic whole-frame FOV70/native2560×1440 с
прежней плотностью/дальностью: wall median18,236мс, p9524,857/p9934,166/max47,303;
GPU median6,473мс. Это не чистый moving FPS gate и не доказательство выигрыша
первичного источника. Прежний CPU/world budget остаётся открытым,120FPS не достигнут.
Полная QA-синхронизация native физики≈0,56–0,59с. Отдельная штатная API-проба:
Full rebuild563,579мс; update одного512²region58,872мс, изменённая высота физически
подтверждена. Dynamic mode запрошенный radius512 ограничил до256world units(16м)
при шаге1unit/16unit на метр; shape_size16. Внутри обещанного радиуса200-ray пробы
дают120/120 и95/95 валидных внутренних точек до/после сдвига. Весь32мcrop он не
покрывает:156/200 и135/200, это ожидаемая граница, не готовая замена общей физики.
Forced dynamic rebuild234,490мс; восемь последовательных сдвигов на1м стоят
18,123–21,105мс на прямой update, не wall FPS. Настройка проверена, custom renderer/
collision scheduler не создавался. Дешёвый residency/update физики остаётся gate
перед production migration; нельзя компенсировать его выпадением NPC сквозь землю.

**Открыто:** Ember UI/paint/три облика, navigation acceptance, весь мир/дальний вид,
физический residency для нескольких акторов, холодная подготовка/телепорт/память,
manual camera/LOD/brush и общий120FPS. Новая основа остаётся QA-кандидатом;
авторские карты/production owners не заменены. Следующий запрос автора после
проверки кандидата — бюджет персонажей/анимаций: использовать прежние замеры и
разделить стоимость появления NPC и постоянной симуляции; не начинать заново mesh A/B.
После текущего этапа домов вернуться к [демо Gamefromscratch](https://www.youtube.com/watch?v=kD6GCH1odnk)
и сравнить готовые возможности уже опробованного Terrain3D 1.1.0. В этой версии есть
отдельный океанский clipmap с примером материала и пример GPU-травы на частицах.
На прежнем километровом полигоне поверх Terrain3D работали трава и материал воды Ember.
На том же рельефе, разрешении и маршруте сравнить штатные варианты с ними по отдельности,
сопоставляя плотность, дальность, качество берега и p95/p99. Показанные в ролике 144 FPS
не заменяют замер. [Состав релиза Terrain3D 1.1.0](https://github.com/TokisanGames/Terrain3D/releases/tag/v1.1.0-stable).

Evidence: `C:/Users/novos/Documents/Codex/2026-11-02/ember-terrain-primary-integration/`:
`final/result.json`, `final/engine.log`, `final/primary70.png`, `collision-modes-bounded.json`
и точные QA adapters/исходники для восстановления пробы. `result/` невалиден из-за
ошибки загрузки helper; `verified/` воспроизводит старый grass digest;
`cache-fixed/` проходит поведение, но reload ещё включает debug checker. Каноническое
доказательство — `final/`. Все stage-only hooks после проверки восстановлены.

### План персонажей:партия и массовые NPC01.11

Запрос автора:у массовых NPC отключать физическую симуляцию волос,у важных героев
сохранять её. Уточнение автора:партия4,важных героев минимум8 суммарно;в хабе
герои вне активной партии имеют такое же качество. Численного лимита важности нет.
Реализация в прежних owners,один ember_worker Sol/high;общая проверка — координатор.

**Вывод и готовые подходы.** Важность/видимость и бюджет времени определяют
качество обновлений,а не единое правило для всех NPC. Epic Animation Budget
Allocator ограничивает CPU-бюджет,реже обновляет менее значимые скелеты и может
интерполировать позы. Animation Sharing переиспользует результат оценки позы
для групп совместимых персонажей. Это разные механизмы:общая AnimationLibrary
в Ember ещё не означает общую рассчитанную позу. Groom scalability отдельно
рассматривает simulation/interpolation/rendering;его strand-пайплайн не является
ценой наших VRoid hair meshes. Данных о внутренней политике NPC Crimson/Genshin
из этого исследования нет;общий приём не приписывается конкретной игре.

Godot уже даёт SpringBoneSimulator3D,наследуемый active=false для отключения
обработки и reset() для безопасного возврата после скачка позы. В текущем Ember
существующий distance LOD совместно шагает AnimationPlayer и модификаторы NPC;
партия защищена full-rate. У SpringBoneSimulator3D нет отдельного публичного
планировщика simulation tick;Skeleton3D.advance обновляет модификаторы скелета.
Поэтому обещать отдельные30Hz волосы при120Hz теле простым переключателем нельзя.
Редкая физика без подходящего шага/сохранения результата может дать скачки.

**Текущее поведение.** NPC springs OFF,партия и явно важные герои ON в прежнем качестве.
Обычные idle/walk/run,повороты,моргание и skinning NPC остаются;волосы продолжают
следовать костям головы/тела,но самостоятельной инерции без отдельного клипа нет.
Для заметных NPC позже возможны заранее записанные движения волос,не solver на
каждого. Это художественная альтернатива,не обязательная работа первого среза.
Важность независима от активной партии:export `important_character` у HoshiVisual,
плюс автоматическая защита прежних EmberPlayer/EmberPartyFollowers. Частоты60/30Hz
— лишь кандидаты отдельной пробы,если стоимость важных ригов останется существенной;
нужны устойчивый шаг и плавный
вывод,не снижение частоты всего персонажа. За кадром учитывать видимые тени.

**Порядок работы и приёмка:**
1. В `ember_hoshi_visual.gd` и существующем `ember_animation_distance_lod.gd`
   отделить разрешение secondary simulation от частоты locomotion. Использовать
   прежнее определение EmberPlayer/EmberPartyFollowers,без новой party/save схемы.
   NPC springs не исполняются;переключение роли/повторный setup восстанавливает
   authored состояние и сбрасывает историю springs при необходимости. Проверить,
   что отключаемые цепочки не содержат обязательной анимации/механики одежды.
2. Показать NPC и партию на landscape_compact. Focused native gate:0spring steps
   у NPC при работающем idle/walk/run;у героя/спутника springs продолжаются;
   REST/клипы/моргание/движение/физика прежние;возврат без выброса волос. Ручная
   оценка неподвижных волос NPC и отсутствия неприятных пересечений обязательна.
3. Один относящийся dense маршрут:32NPC плюс8важных Hoshi(лидер+7hub visuals),одинаковая
   нагрузка baseline/candidate,native1440p,FOV40/70,плотность/дальность прежние.
   Раздельно wall/GPU,p95/p99/max,счётчики springs и CPU-scope;не выдавать сумму
   scoped вызовов за всю native стоимость. Подтвердить,что solver ограничен важными героями.
   Прежняя диагностическая абляция32NPC ON/OFF≈20/14,7мс не прогноз этого нового
   состава;120FPS не гарантирует. Если кадр всё ещё дорогой,выбрать по новому
   измерению controller/rig/rendering,а не снова уменьшать constant tracks.

**Focused gate реализован и проверен:** `test_animation_distance_lod.gd`,native
Forward+/RTX5070,errors0:ordinary NPC near120/far15pose evaluations на120frames,
реальных spring bone отклонений0;nonparty hub hero120poses и самостоятельное hair
motion;party protection,authored inactive restoration,hidden→important/teleport
finite,blink/time/physics regressions PASS. Сигнал modification_processed не
является счётчиком реальных springsteps;проверяется поза внутри modifier lifecycle.
Source/REST/клипы не менялись. Evidence:`ember-npc-secondary-policy/native-focused-final.log/.json`
под прежним внешним корнем01.11. Ручная визуальная оценка пока OPEN.

**Общий native gate завершён:**`EMBER_HERO_HUB_STRESS=1 mode=render`,Forward+/Vulkan/
Jolt,actual2560×1440 scale1,TAA,uncapped,32ordinary+7explicit hub heroes+player=8important.
Это восемь копий существующего136bone Hoshi rig для бюджета,не восемь новых production
героев/IDs. FOV70 все39добавленных актёров вкадре;прежние растения/предметы/свет сохранены.
Same-process all-springs/policy/all-springs-return,по240frames≥3с после1,6сsettle,
без render timers:wallmedian25,942/**17,901**/24,899мс,p9533,269/25,504/32,064,
p9946,575/38,580/38,463,max212,895/220,763/54,924. Уменьшение median≈7–8мс
подтверждено обоими контролями;max/stalls этим не исправлены. Вcandidate32обычных
solvers inactive,восемь важных active;частоты тела/важных ригов междуфазами прежние.
После восстановленияpolicy отдельный instrumented live:GPUmedian6,126мс,p956,633,
wallmedian17,945мс,p9523,350. Это диагностический interval,не чистый moving120PASS.
Clean FOV40 out/FOV70 return:median18,592/20,064мс,p9534,086/35,947,
p9947,188/56,231,max239,585/237,103. Оба маршрута завершены,engine/script errors0,
population fallen0,SourceSHA unchanged,exit0. Render-correctness PASS,120FPS FAIL/OPEN.
Предыдущие15,850/15,895мс относились к32NPC+одному лидеру;новый состав тяжелее,
это не парное сравнение и не доказательство регрессии policy. Interactions/cold coverage/
release-return не повторялись,их прежние gates сохраняются. Evidence:
`C:/Users/novos/Documents/Codex/2026-11-01/ember-npc-secondary-policy/hub-stress/`
(`result.json`,`cpu-sample-*.json`,`harness.gd`,`npc_draw_fov40/70.png`,соседнийengine log).
Следующий фокус — оставшийся CPU whole-frame budget при8важных ригах/32NPC;
hair policy принята технически,повтор ablation безновой причины не нужен.

**Делегирование среза:** один ember_worker Sol/high выполнил visual/LOD/focused gate,
координатор принял стабильный результат и выполняет dense маршрут.
Отдельная Astra/high нужна только при выявленной архитектурной границе независимого
secondary scheduler;read-only вопрос и файлы согласовать отдельно. Вложенных
агентов,параллельных писателей и отдельного renderer/движка не требуется.

Источники(первичные,проверены01.11):
- [Epic Animation Budget Allocator](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-budget-allocator-in-unreal-engine).
- [Epic Animation Sharing](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-sharing-plugin-in-unreal-engine).
- [Epic Groom Scalability](https://dev.epicgames.com/documentation/en-us/unreal-engine/groom-scalability-and-performance-with-unreal-engine).
- [Godot SkeletonModifier3D](https://docs.godotengine.org/en/stable/classes/class_skeletonmodifier3d.html),
  [SpringBoneSimulator3D](https://docs.godotengine.org/en/stable/classes/class_springbonesimulator3d.html),
  [Skeleton3D](https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html).
Далее согласованный живой разбор Crimson:fixed view/turn/NPC route,сначала проверить
настройки/FG/scale,внешние CPU/GPU/present metrics отдельно отEmber native timers.
Физические/анимационные внутренности Crimson по внешним счётчикам не устанавливаются.
Общий world callback overhead остаётся отдельным измеренным вкладом.
Полная выгрузка NPC,physics оптимизация,явныйview prewarm и120FPS ещё OPEN.
Для сравнения сCrimson конкретный вопрос — cadence/представление дальних ригов.
Игра запущена черезSteam послезавершения GodotQA;автор подтвердил открытое место сNPC.
Живой маршрут завершён: `crimson-rendering/live-20261101-025944/`,
capture-metadata.complete=true, три exit0, процесс3564/одна swapchain/DXGI.
PresentMon2.6.0: по20с still/camera-turn/NPC-walk,977/1069/971 кадров.
Внешние ETW метрики; настройки DLSS4.5/Balanced59%, FG=false, HAGS=2.
- Средний present FPS:49,01/53,62/48,75. Медиана FrameTime:19,942/18,446/20,500мс.
- FrameTime p95:22,163/21,741/23,100мс; p99:24,646/22,981/24,069мс.
- GPUBusy median:19,849/18,365/20,414мс. Это внешняя занятость GPU,
  не тот же scope, что Godot viewport GPU timer, и не доказательство единственного bottleneck.
- Turn/walk max26,125/27,486мс, кадров>50мс нет. Still max206,554мс,
  четыре кадра>50мс сгруппированы на2,637–3,222с; CPU/GPU wait вырос,
  PresentMode сменился Independent→Composed→Independent. Фокус/overlay — гипотеза;
  причина не установлена, связывать эти паузы с NPC/streaming оснований нет.
- Process private median11,61/11,63/11,97GiB,working set6,38/6,43/6,60GiB.
  CIM DedicatedUsage≈33GB превышает physical VRAM:не считать resident VRAM usage.
  Отдельный nvidia-smi после маршрута:12227MiB total/8271MiB used на всём GPU,
  не историческая и не per-process память Crimson.
Summary/CSV SHA и границы — `summary.json`, воспроизведение — `summarize_capture.py`.
Внутренние LOD cadence, CPU цена NPC/физики и pass breakdown этим не измерены.
Один короткий маршрут не закрывает долгую стабильность/холодный teleport/утечки.
Повтор без нового вопроса не нужен; настройки/игра оставлены автору без изменений.

Runner `Start-Crimson-Capture.ps1`: own named ETW sessions/targetPID filter,
external process/GPU counters, русские голосовые подсказки с проверкой слышимости.
Старый `live-20261101-025154` — только1006still frames: PS5Start-Process вернулnullExitCode,
runner неверно остановился и написалFinished. Исправлено через owned.NETProcess,
async stdout/stderr,проверку всех3этапов/CSV и явныйfailure. PS5.1 selftest3×exit0+exit7 PASS.
Текущий повтор успешно прошёл все три этапа; старый partial не смешивать с ним.
SHA256PresentMon `b2a706bc6ad475749e3b7e3409263aa1e6906d45bdcf993f6dbc0f660188f1af`.
НастройкиDLSS4.5/Balanced59% иCinematic-Maximum прочитаны;actual viewport ещёнеизмерен.
Данныеизразныхигр неравнозначныеpass timings.
УстановленныйFrameViewSDK DLL неexportFvSDK_Initialize;probe прекращён,
сервисFvSvc не запускался,установок/правучётнойзаписи/инъекцийнебыло.
Автор сообщил два вылета Crimson доигрового прохода. Read-only minidump inventory
170modules:exe наD:,VERSION.dll изSystem32,OptiScaler/DLSS-NR modules отсутствуют;
старыймод остаётся вбывшемC:-install ивэтомдампе незагружен. Exception0x887a0006
(DXGI_ERROR_DEVICE_HUNG),не доказательство конкретнойпричины.
Actualoptions:Custom/Cinematic-Maximum,DLSS4.5,Balanced59%,FrameGeneration=true,
DynamicMFG=true,RT/RR=true. HAGSregistryHwSchMode1;свежийgame log прямоотмечает
DLSS-G initialization failed/requiresGPUhardware scheduling. Это проверяемый
конфликтнастроек,не доказаннаяпричинаGPUhang.
Внешниеevidence:crash-module-report.json,read_crash_modules.py,исходныеoptions и
FG-off candidate сохранены вcrimson-rendering. Авторразрешилприменитьтолько_enableFrameGeneration=false;
original/backupSHA256c90a6fa9f9b2d359fbd6d93a6a004d1f73fdba79f2ac6234a7bd0b5bfd30720d,
appliedSHA2563f656e989a792d39fce01325437c15dc9d1706d1a6a4d05f168bcd8350071f70.
FG-off запуск тожеупал;false сохранился,новыйdumpтотже0x887a0006. Systemevent4101
подтверждаетnvlddmkm timeout/recovery обоихзапусков;этоTDR,а не установленнаяпричина.
АвторвключилHAGS иперезагрузилWindows:HwSchMode2 подтверждён,FG=false/scale59% сохранены.
Авторсообщил стабильныйкороткийпроход;свежийlogнепоказываетстаруюHAGSinit ошибку.
Long-session/crashcause ещёOPEN. Драйвер/остальноеquality агентомнеменялись.

### Предыдущий профиль16NPC — отдельная нагрузка

Последняя совмещённая population-проверка:
`C:/Users/novos/Documents/Codex/2026-11-01/ember-npc-lod-admission/final/`.
Статус **streaming/cold-detail/return gate PASS на этом маршруте;120FPS OPEN**.
Ручная игровая/визуальная приёмка OPEN. Stock Godot выбран автором;
temporal directional cache отложен. Animation distance LOD/physics activity/native
shadow geometry LOD включены в существующие runtime owners, а не только в fixture.
Dense576м сохранён, дополнительно16 Hoshi NPC/16 ящиков/4 дома/8 фонарей,45physics anchors.
Vulkan Forward+, actual2560×1440/scale1/TAA/Jolt60Hz/uncapped/vsync0; без снижения нагрузки.

- Clean движение FOV40/70: median8,313/9,368мс;p9515,450/17,103мс;
  p9922,497/23,788мс;max56,368/49,863мс;49,77/67,84% кадров дороже8,33мс.
  Cross-run control до текущих изменений (`ember-active-cost/object-budget/`):
  median8,747/10,083мс;p9516,808/19,305мс;p9939,063/41,216мс.
  Нагрузка/плотность/маршрут прежние;это совместный результат изменений,не изолированный
  множитель одной оптимизации и не минимум120FPS.
- Последний frozen render snapshot (`integrated/`,native character LOD уже включён):
  GPU median5,458/5,884/6,268/6,524мс (near40/near70/wide40/wide70),
  p955,738/6,159/6,649/6,850мс. После scheduling/coalescing статическая матрица не
  повторялась:неизменный render path ранее проверен;moving gate измерен отдельно.
- Cold-detail движение:0affected frames из3294/3082 на out40/back70, floor0/0.
  Release281/return281exact,strict check PASS,exit0. Поле missing в summary — максимум
  одновременных absent buffers, **не число кадров**;frames считаются по per-frame trace.
- Release281/281, return281exact;все16NPC/16ящиков живы, fallen0, pending support0.
  Canonical tree source/shape identities сохранены;engine/script errors0.
  Последний resident snapshot:Godot static allocator≈4,22GB,renderer video≈1,83GB;
  это не process working set/DXGI peak или доказательство полного Source-unload.
- Ограничение этого прежнего профиля: оставались CPU/native frame cost и кадры>8,33мс.
  Подготовка/возврат именно16NPC маршрута больше не отдельный
  FAIL;освобождение всего NPC/Source RAM этим не реализовано. Новый renderer/снижение
  плотности/расширение test matrix этим результатом не обоснованы.

Предыдущая интеграционная проверка без дополнительного населения:
`D:/Codex/ember-resident-frame-20261031/integrated-cache64/`.
Текущий срез31.10: существующий MapLoader object poll дополнен кооперативным порогом
1мс при прежнем count cap128. Сохраняется cursor,каждый turn допускает хотя бы1шаг;
полный явный refresh(max_props0) остаётся синхронным. Это не жёсткий лимит native
вызова: один шаг и финальная сортировка могут превысить порог. Source/радиусы/mesh
и collision не менялись. `test_object_poll_budget` RED→GREEN проверяет уступку после
costly operation,полный sweep без starvation/дубликатов и explicit full refresh.
Внешний CPU profile (`ember-active-cost/profile/`) показал object poll p953,349/max6,151мс,
из них shadow p952,480/max4,292мс. Этот диагностический обратный маршрут не дошёл до
конца за70с и **не принимается как FPS/stress gate**; scopes используются только
для локальной стоимости. Последующий uninstrumented full route выше завершён.
В его correctness trace poll p95≈1,16/1,18мс,max4,52/4,30мс (sampled values).
Полного NPC scene streaming/Source RAM paging в этом срезе не добавлено:
Hoshi presentation sampling/WorldRecovery participant support сохраняют своих owners.

Срез01.11: native index LOD Hoshi Body/Hair подключён в текущий private avatar и
его существующий staging. Использован штатный
[ImporterMesh.generate_lods](https://docs.godotengine.org/en/stable/classes/class_importermesh.html#class-importermesh-method-generate-lods),
без runtime remesh/второго renderer. Source vertices/normals/tangents/skin arrays
битово сохранены;native-generated indices переносятся в исходный packed vertex
stream. Face с57morphs не упрощается. Save/reload candidate skin/morph audit PASS;
native idle/walk/run forced-base pixels exact,far visible primitives91065→16449
(включаяoutline),shadow182132→32900. Это fixture counts,не whole-frame множитель.
Near/far screenshots просмотрены,ручнаяоценкадвижения/LOD остаётся у автора.
Source Companion/VRM/config не менялись,исходный staged avatar сохранён вне Git.
Подробности/candidate — `C:/Users/novos/Documents/Codex/2026-10-31/ember-npc-residency/`.

Очереди01.11: sleeping admission сохраняет следующий живойID при перестроении
индекса в прежнем окне. Actual scanner churn RED→GREEN;радиусы30/24/32м и бюджеты
прежние. Это устраняет один механизм starvation,не принимает весь streaming.
Native stage trace далее доказал другие задержки:initial queue55frames/812мс,
completed material slotowner35frames/423мс,позднее foreground continuation.
Global aging и cold-first aging ухудшили native coverage и **отклонены**;их поля/
priority modes отсутствуют в production. Negative evidence и стадии:
`C:/Users/novos/Documents/Codex/2026-11-01/ember-grass-phase-probe/rejected/negative-evidence.json`.
Сохранён безопасный early available gate перед ordering/dispatch count при нулевом
бюджете; nonempty spatial queue/cancel targeted PASS. Дальняя работа по-прежнему
не может обходить foreground allowance или author urgent priority.

Shadow coalescing01.11:повторные geometry/material/caster записи пропускаются.
В [точном Godot ed1daf0bf](https://github.com/godotengine/godot/blob/ed1daf0bf/servers/rendering/renderer_scene_cull.cpp#L1030)
same-value surface override и cast-shadow setter всё равно ставят instance dependencies
на обновление. Заявки объединяются,их количество не равно числу rebuilds;общий gain
определяется только moving run. Existing native shadow fixture PASS,pixels/LOD/
clear/rebind/lifetime сохранены,stable uniform getters0.
Парный текущий baseline3MB: `D:/Codex/ember-resident-frame-20261031/integrated/`.
Предыдущий signature baseline: `D:/Codex/ember-resident-guards-20261031/integrated/`.
Предыдущая nearest baseline: `D:/Codex/ember-frame-hotpaths-20261031/integrated-final/`.
Предыдущий clean baseline: `D:/Codex/ember-overview-index-20261031/integrated/`.
Предыдущий baseline: `D:/Codex/ember-overview-updates-20261031/integrated/`.
Предыдущий indexing baseline: `D:/Codex/ember-ground-publication-20261031/`.
`fine-profile/` и `after-profile/` — CPU phase attribution;`acceptance/` — fixed5мс,
`budget3/` — fixed3мс comparison. Production использует существующий startup barrier.
Native2560×1440,scale1,TAA ON,вечер,real Player/physics,95м/FOV40→70.
Dense576×576м:25848patches,64grass/10flowers/8wheat,859добавленных props.
Обычная трава/цветы увеличены на25% (25560stress patches); плотность/дальность прежние.
На main изменён только tuft_size212grass/flower nodes,камушки/пшеница прежние.

- Устранена повторная полная validation готовой пшеницы: bounded successful
  snapshots всех stored geometry/recipe fields замечают и in-place edits.
  Real-wheat targeted warm5,08→0,32мс,не whole-frame gain.
- Синхронная cache write дала cold wall641,24мс,из них598,475мс Storage.write.
  Теперь immutable payload пишет worker/private Storage. Synthetic slow80мс
  producer82,95мс→41мкс;native worker88,19мс завершился на кадре5,659мс.
  Это доказательство разделения потоков,не парный benchmark скорости диска.
- Observer больше не публикует уходящие overview вне admission deadline.
  Запросы объединяются в `_overview_dirty`; один регион восстанавливает overview
  перед release fine/collision. Coverage пересчитывается по текущему wanted;
  устаревший revision не освобождает новую поверхность. Map-owner lookup
  готовой травы очищается при exit/reparent;typed Node validity и local proof ниже.
- В `project.godot` выбран встроенный **Jolt Physics**, прежние HeightMap/Concave
  формы и controller сохранены. Live query partition: DEFAULT terrain p951,137мс,
  props0,008;Jolt terrain0,048мс,all0,052мс. Это локальный CPU gain≈22–24x,не FPS.
- Render upload земли/стыков теперь использует exact attribute indexing в CPU worker:
  стандартный SurfaceTool.create_from_arrays→index→commit_to_arrays. В fixture26112
  vertices→5253/5448 без удаления треугольников,смены атрибутов/LOD thresholds.
  Ground-upload active-frame median2,646→0,579мс,p954,135→1,137мс;это CPU scope.
  Canonical layout/коллизия/носители обликов остаются fine,temporary upload не сериализуется.
  Native pixels/shadows на flat/slope/mixed и двух LOD biases exact;швы exact.
- Исправлена взаимная блокировка priority queue: ближайший waiter занятого digest/read
  slot повторно вставлялся в текущий dispatch и вытеснял дальнего владельца результата.
  Повторные turns теперь идут в следующий dispatch;band/urgent/FIFO и allowance прежние.
  Cancel/prioritize/release учитывают обе очереди. Регрессия RED→GREEN,реальные
  bounded material/read slots и native cancel/teardown PASS. Без instrumentation
  старый static startup не завершился за90с;исправленный завершился за21,823с.
  Это устранение зависания,не множитель скорости обычного запуска.
- Overview Ground сохраняет ArrayMesh и обновляет только index buffer штатным
  [RenderingServer.mesh_surface_update_index_region](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-mesh-surface-update-index-region).
  OverviewJob пакует immutable per-patch16/32-bit chunks;main thread меняет mask/indices.
  Скрытые triangles вырождены,all-covered Ground невидим,source revision создаёт новый mesh.
  Source/physics/picking/water/seams прежние;это derived RAM payload,не новая schema/cache.
  Native flat/slope/mixed:exact pixels/shadows,all/half/checker/hidden/return,same RID,
  source-revision replacement и активный shadow receiver PASS. Native admission/slots/policy PASS.
  Local alternating-mask median221–231→26мкс,p95252–278→32–33мкс;
  live publication active p951,514→1,010мс. Scopes вложены,не множитель FPS.
  A/B/A whole-frame p95:old7,808/8,567мс,new repeat7,843/8,635мс — устойчивый
  общий FPS gain **не подтверждён**,сохранено локальное улучшение подготовки.
  Internal static return snapshot≈+22,5MiB;это не process/DXGI peak.
- Player._nearest больше не вычисляет доступность/квестовые маршруты далёких
  объектов. Сначала прежняя точная distance_to_world/region distance и strict12,
  потом availability только кандидата,который может стать ближайшим. Player origin
  читается один раз;кэша целей/флагов и снижения частоты нет. Общий owner для F и focus.
  Live-scene A/B/A(8interact nodes,3точки) даёт median0,186→0,014мс при тех же целях.
  Это≈13x только query,не whole FPS. Native regression проверяет live flags/one-shot,
  unavailable nearer fallback,large/rotated volume,ties/hidden/deleted/moved player,
  strict threshold/held pickup. Guarded native launch-rules и physical crates PASS.
- Clean gameplay после distance-first nearest,Jolt и allowance5→3мс:
  median5,986/6,689мс,p957,969/8,748,
  p999,587/10,192,max35,700/28,900;
  3.47/7.28% кадров>8,33мс.
  **Минимум120FPS не достигнут.** В текущем3MB baseline p958,048/8,778мс,
  max19,093/34,279мс. Общий FPS gain от64MB и Node-owner не доказан;текущий FOV70
  медленнее прежнего signature baseline(p958,120мс),нет основания приписывать разницу
  одной правке. Старые clean464,510мс остаются частью открытого long-session/stall gate;
  отсутствие их в текущем run не является полной приёмкой.
- Frozen GPU (мс): near40 median5,411/p955,688;near70 median6,079/p956,367;wide40 median6,411/p956,704;wide70 median6,269/p956,678.
  Это отдельно от gameplay FPS;GPU correctness traces stale и не используются.
- Scatter-cache-cold out/return: absent/pending/floor0/0 в каждом кадре;
  release281/281,return281 exact;Source/shape IDs/transforms576trees exact.
  Geometry/shader caches тёплые;startup21,641с не принимает fully cold startup.
  Дополнительно actual foot gap min−0,00146raw/max0,56130raw:нет провала через землю.
  Correctness wall включает измерительный checker и не заменяет clean FPS.
  GPU fields внутри correctness traces INVALID/stale (timers disabled);
  авторитетны только frozen GPU snapshots и отдельные clean wall timings.
- Existing WorldCanvas.is_world_preparation_complete читает прежний _startup_complete;
  DetailPreparation.frame_budget_us использует5мс под cover,3мс после reveal.
  Editor/активная кисть/owners без такого startup barrier сохраняют5мс,brush cap4мс.
  Phase не дублируется в context:recreate/reparent читает актуального owner.
  Новый fixed3мс после indexing прошёл coverage0/0/release/return,но startup27,799с
  вместо15,003с fixed5мс;выбран фазовый вариант(startup21,641с в текущем run).
  Старый3мс до IO/index fixes с absent4/3 не является текущей приёмкой.
- Runtime sleeping admission завершает bounded sweep один раз на authoritative
  policy/source epoch,а не повторяет его каждый кадр. Новая область/Source/transform/
  footprint/index требуют нового sweep;paused ancestors оставляют retry до resume.
  Editor/custom projection без epoch сохраняет прежний periodic fallback.
  Same-route instrumented sleeping median0,713→0,019мс,p950,916→0,036мс;
  это локальный CPU scope,не множитель FPS. Stable128polls:65386→0повторных bounds reads.
- Повторные SHA/file checks saved material roles перенесены в один worker на context.
  Runtime потребляет приватные saved templates и прежний bounded CPU payload cache;
  cold/changed file перепроверяется прежним sync path только при digest mismatch.
  Independent GPU textures/4mutable images,texture revisions и PNG weak bank сохранены.
  Same-route role bind median1,262→0,285мс,p951,565→0,345;
  digest poll p95all0,049мс. Active queued p954,584→2,414мс;это CPU scopes,не FPS.
  Slow80ms producer80,922мс→native44мкс,worker продолжает IO при идущих кадрах.
  Layout/source guard и coalesced live profile replay сохраняют preview через await.
  Native byte parity/private binding/file-change/cancel/join/Undo/save/reopen PASS.
- Validation/admission regressions RED→GREEN;native pattern-library,
  surface-rules,main-view и dense async/cold PASS. Writer snapshot/cancel-before-
  enqueue/count+bytes/join PASS;Astra review существенных blockers не нашёл.
  Текущий dense run включает прежние malformed-input writer guards.
  Publication admission RED→GREEN: expired budget/quick reverse/stale overview/
  per-region deadline/convergence;travel и native resident-slot reuse PASS.
  Owner lifetime:ancestor reparent/detach/reattach/off-tree и detail preparation PASS.
  Jolt native:5120surface rays(max height error0,00000763raw),step30/60/120Hz,
  Hoshi capsule/movement и physical crates/F/G/push/weights/save/Undo/reopen PASS.
  Editor/game требуют restart для нового backend;ручное ощущение движения/предметов OPEN.

Native LOD resident-деревьев,feature programs,local HeightMap и HP query сохранены.
Прежний LOD wide6,2–6,3→5,7мс,guards editor/preview/look1/2,LOD0 pixel controls —
`D:/Codex/ember-wide-objects-20261031/`;это отдельный GPU gain,не whole FPS.
Material evidence — `D:/Codex/ember-material-path-20261030/acceptance/`;
отклонённый grass map-projection cache — `D:/Codex/ember-cost-breakdown-20261031/`.
Main Sun angular0/filter2/blur1/distance1600;ручная камера/полосы теней/размер травы OPEN.

## Измеренная причина и принятые решения

### Регулярная CPU стоимость31.10

CPU attribution: `D:/Codex/ember-resident-guards-20261031/`;current owner/cache controls:
`D:/Codex/ember-resident-frame-20261031/`.
Native profile13624frames:grass aggregate median1,298/p951,889мс;stable9582frames
без update median1,262/p951,516мс. Area reads median0,196мс;scopes вложены.
Только292кадра обновляли>100patches;signature1315calls на1311frames:
active-frame median0,385/p950,517мс. Это profile с overhead,не clean FPS.
`GrassPatch._surface_signature` теперь получает map owner один раз перед обходом
solid props,вместо повторного map lookup на каждом объекте;обход/порядок/данные прежние.
Same-scene alternating A/B10rounds×150queries:median199,537→139,900мкс(≈30%),
old/new signature exact. Native clean-resident/owner reparent,epoch/same-frame edits,
local sculpt/paint/restore PASS. Общего FPS множителя эта проверка не доказывает.
Typed context(2,615→2,602мкс),interned arguments(2,635→2,602мкс) не дали полезного
выигрыша;uniform coalescing2,537→2,602мкс замедлил update. Эти варианты отклонены.
Прежний широкий profile:player physics0,910,HUD0,325,party sync0,275мс;
nearest aggregate0,359/p950,704мс устранён distance-first путём без cache/паузы UI.
Unit.to_definition0,052мс aggregate не оправдывает новый owner/cache статистики.
Map cache теперь typed Node + is_instance_valid вместо WeakRef.get_ref/cast на каждом
обращении. Exit/reparent очищает его;off-tree authoring не сохраняет owner.
[Node/Object ссылки не управляют временем жизни объекта](https://docs.godotengine.org/en/stable/classes/class_object.html#description).
Stable callback alternating12rounds×20000:2,594→2,430мкс(≈6,3% локально).
Native owner-lifetime/reparent,clean-resident,epoch/material/replacement PASS.
Следующий обычный CPU кандидат —282stable callbacks/frame и массовые observer updates;
полный solid-prop scan на signature остаётся,новый shared cache не вводился.
Новый diagnostic slow-frame разбор:в паузе462,176мс grass1,328мс,updates0;
440,374мс между last-script callback и render-pre. Это место ожидания,не доказанная
причина GPU/драйвера;прежний native stack sampler к этому кадру не подключён.
Shared allowance прежний;frame budget до8,33 не принимает p99/stalls.

### Большие паузы и сохранение PSO кэша31.10

Воспроизведён источник пауз400–500мс: сохранение большого Vulkan pipeline cache.
Атрибуция конкретных старых случайных кадров по native stack остаётся OPEN.
Evidence — `D:/Codex/ember-resident-frame-20261031/findings.json` и `cache-*.gd/json/log`.
QA PSO cache перед пробой932051292bytes(≈889MiB),накоплен исследованиями;обычный
пользовательский cache142224494bytes только прочитан,не очищался/не переписывался.
Это CPU/дисковый shader cache,не измерение занятой VRAM и не authored Source.

В [исходнике именно ed1daf0bf](https://github.com/godotengine/godot/blob/ed1daf0bf/servers/rendering/rendering_device.cpp#L8617)
порог означает прирост размера до следующей записи,а не секунды. Worker сериализует
полный cache под RenderingDevice lock;Vulkan сериализация включает копию и hash blob.
Поэтому сохранение может задержать render thread без роста компиляций в этом кадре.
Single-pipeline A/B/A:без сохранения max10,074/9,219мс;при forced save max473,780мс,
pipeline creation≈9мс во всех случаях. Это специальный диагностический trigger.
3072новых compute pipelines при штатном default3MB:frame max506,523мс и Updated PSO
до окончания измерения;при64MB max78,066мс,полусекундного сохранения внутри пробы нет.
Оба запуска native,cache enabled,pipeline creation max8,669/8,853мс,exit0.
Это control persistence cost,не sparse приёмка густого gameplay или FPS.

В `project.godot` применён штатный [save_chunk_size_mb=64](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-rendering-rendering-device-pipeline-cache-save-chunk-size-mb).
Кэш остаётся включённым;финальный save при закрытии сохранён. Записи происходят реже,
но рост ещё на64MiB снова может вызвать большой save:это не полное устранение stalls,
не cap размера cache и не уменьшение качества/плотности/дальности. Нужен long-session gate.

Новый passive native control:4dense маршрута,3520стеков,пауза400–500мс не повторилась;
p95suspend0,088мс,max9,263мс(диагностика не clean FPS). Старые десять маршрутов тоже
не принимали отсутствие паузы за исправление. Main/render callback один OS thread;
Godot id не Win32 TID. Sampler подтверждён controlled350ms/SleepEx/NtDelayExecution.
WPR текущему token недоступен;official binary без PDB,Godot module+offset не имя функции.
Старый кадр467,958мс имел post-draw gap461,944мс,completion21/39мкс и отсутствие
роста pipeline counters;новый scoped462,176мс — gap440,374мс last-script→render-pre.
Эти места совместимы с ожиданием внутри renderer,но не доказывают одинаковую причину.
Verbose isolated probes также показывают существующее loader сообщение ReShade64.dll1114;
системная Vulkan-конфигурация не менялась;ошибка не атрибутирована старым паузам.

## Владельцы и работающий путь

### Земля и общая физическая поверхность

`scripts/prototypes/ember_terrain_pilot_projection.gd` владеет publication,
fine residency, overview и очередью. `ember_terrain_smooth_surface.gd` готовит
отдельный render_detail и native mesh LOD; каноническая authoring grid остаётся
источником. Native LOD 4096→2048→1024→512 и оба blend modes проверены.
Старый `_queue_ground_lod()` со skip style1 не описывает этот smooth-путь.

Уточнение по вопросу автора о «полигонах каждой ячейки»: `render_detail()` уже
сворачивает совместимую плоскость в 2 треугольника. Но `_render_plane_indices()` требует
совпадающих нормалей и COLOR/UV/UV2, а `_render_palette_ids_valid()` сохраняет границы
палитры. Поэтому визуально плоский участок со смешанной покраской не обязан получить
минимальную геометрию: материал и упрощение связаны атрибутами вершин.
Это подтверждённое ограничение представления, не доказанный whole-frame bottleneck.
Отделение точности покраски/масок от плотности render mesh — архитектурный кандидат;
он обязан сохранить blending, три облика, физическую поверхность и редактирование.
Переписывание mesher или новый renderer из этого автоматически не следуют.

`ember_terrain_pilot_mesh.gd` и его `EditorTilePublication`
публикуют точный HeightMapShape3D из той же float32 grid/диагоналей.
Holes/walls/nonuniform placement и deform study используют Concave fallback.
Canonical faces, floor field, picking и navigation не меняются на дальний LOD.
Native rays/cache/offset/affine/deform технически проверены; ручные стыки OPEN.
Физический backend — Jolt Physics (`project.godot`),не новый renderer/addon/формат.
В live query A/B земля,а не props,занимала≈1,14мс в DEFAULT;Jolt с прежними
HeightMap снизил p95 до0,048мс. Exact Concave control дал лишь≈20% и не перенесён.
Совместимость — native surface/step/Hoshi/crates и dense cold/return;ощущение вручную OPEN.
Официальная интеграция: [Using Jolt Physics](https://docs.godotengine.org/en/4.6/tutorials/physics/using_jolt_physics.html).
Brush hover временно удерживает fine surface; runtime remesh не добавляется
на мелкий editor input. История/preview/commit принадлежат прежним editor owners.

### Объекты и растительность

`scripts/prototypes/ember_world_detail_policy.gd` задаёт локальные области,
prepare/fade/release и hysteresis. `scripts/ember_grass_patch.gd` использует
пространственные MultiMesh patches; источник расстановки и плотность не заменены.
Grass prepare 30 м, fade 16–24 м, release 32 м; fine cap 384 прежний.
Clear/stale/worker cancellation, exact scatter и unload/return проверены.

Объекты используют общий native mesh LOD и shared immutable geometry. В runtime
look0 carrier получают и resident-деревья; их экранную детализацию выбирает камера,
а не радиус подготовки игрока. `object_lod_allowed()` сохраняет editor/preview/
look1/2 guards и проверку Source перед публикацией. Тяжёлые
производные carriers живут локально и освобождаются последним потребителем.
Source nodes и физика объектов пока остаются. Реальный HLOD/cluster/impostor
не объявлен реализованным. Восстановление и ввод/история применяют прежнюю
порционную публикацию, один Undo и исключение незавершённого Apply из save.

`scripts/ember_detail_preparation.gd` объединяет foreground allowance и очереди.
Runtime poll epoch/weak context переиспользуются по identity/revision/policy/
transform/brush; patch отдельно проверяет dirty/bounds/material/shader/anomaly.
Editor fast guard отключён; invalidation/lifetime/cancel не заменяются таймером.

### Материалы, вода и кэши

`scripts/ember_voxel_surface_materials.gd` и
`shaders/ember_compact_terrain_body.gdshaderinc` — общий material owner.
Saved CPU packing bounded 16/context по source/file SHA/texture revisions;
редактируемые CPU images и GPU bindings приватны, PNG banks weak/shared.
Нельзя объединять editable preview state ценой утечки между объектами.
Artwork/depth/collision принадлежат своим данным, не shader cache metadata.

Water Regions отбирает immutable eligible cores, сохраняя actual demand,
publication/readiness/cancel. Floor-capture viewport отключён только когда
нет опубликованного water demand; frustum/region count не заменяют этот gate.
Water-camera vertex discard исключён из shadow pass. Один исправленный дефект
не принимает всё self-shadow мерцание зелёных склонов.
Подробности water look/activity — [Water Rendering](EMBER_WATER_RENDERING.md).

Geometry/LOD, water, tree, details, height, solid и anomaly caches остаются
производными: content/version/dependency key, validation, stale/corrupt fallback.
CPU image LRU 24 MiB и geometry disk cache 512 MiB не ограничивают RAM/VRAM мира.
Source terrain и authoring nodes пока целиком в памяти; detail release этого
не исправляет. Масштабирование всей памяти **OPEN**.

Подготовка scatter-кэша: `ember_detail_preparation.gd` принимает immutable
снимок готовых transforms, затем один worker/private Storage выполняет
serialization/ZSTD/flush/atomic rename. До16 активных+ожидающих jobs и8MiB
оценки payload snapshots; сериализованный/сжатый scratch отдельно, это не RAM peak.
Переполнение пропускает необязательную запись, а не публикацию травы. Cancel
проверяется до принятия; принятый content-addressed snapshot валиден после ухода
patch. Обычный patch release не ждёт IO. Context teardown синхронно завершает
принятые записи/join, поэтому latency закрытия карты остаётся отдельным gate.
Runtime scatter reads используют `read_async` того же preparation owner:
до2 активных+готовых результатов на context,private Storage/settings snapshot,
checksum/decompress/decode/transform validation в worker. Completed result держит
слот до budgeted delivery. Production raw input≤4MiB/read;decoded/scratch и
переданные patch данные отдельно,это не общий RAM cap. Sync `read` оставлен
для compatibility/tests. Patch cancel не ждёт IO;context teardown join может ждать.
Материал в подготовке получает те же light/gray/cover обновления,что опубликованный:
устаревший кандидат больше не перезаписывает preview после await. Object edits
инвалидируют также unpainted scatter;null/removed projection не создаёт новый context.
Native slow80ms regression: producer80,788мс→40мкс с продолжающимися кадрами,
не benchmark общего FPS. Native cache/lifetime/material-preview и pattern-library
Undo/Redo/save/reopen PASS;ручное ощущение кисти/движения остаётся OPEN.
Async read evidence: `D:/Codex/ember-jolt-frame-20261031/`:
`profile/` — pre-fix instrumentation,`acceptance/result.json` — финальный dense run.
Начальный failed instrumentation log исключён;startup31,657с с тёплой geometry/shaders
не принимает fully cold startup. GPU correctness traces stale,их не использовать.

`bind_saved_material_roles_async` использует тот же DetailPreparation:одна digest
задача/готовый результат на context,immutable path/layout snapshots,без Node/callback
в worker. Ready только будит consumer;доставка/привязка входят через wait_for_turn.
Ушедший patch отменяет consumer без ожидания IO,task держит слот до join;context
teardown дожидается IO и остаётся latency gate. Синхронный public material path
сохранён для редакторских команд/tests. Мismatch digest вызывает прежнюю sync
перепроверку,чтобы save между observation/delivery не отравил payload key.
GrassPatch проверяет source/layout после await;во время ожидания role binding
последние live profile commands на palette IDs объединяются и воспроизводятся
после получения приватных lookup images. Reset/cancel освобождают временные ссылки.
Малый probe без resident PNG-bank consumer пересоздавал банк≈75мс:он исключён
из оценки warm-field gain,не объясняет автоматически прежний57мс gameplay frame.
Полный cold startup/нулевые consumers/долгая память сохраняют отдельные gates.

Runtime sleeping admission отсекает broad-bin false positives по прежней policy
и свежим cached world bounds; собственный stale bounds cache не добавлен.
`PatternBake._validated` исключает external/tree validation с внешними зависимостями;
независимый Astra review не нашёл пропущенных dependencies/thread-safety blockers.

Render upload использует штатную [SurfaceTool.index](https://docs.godotengine.org/en/4.7/classes/class_surfacetool.html#class-surfacetool-method-index).
prepare_render_upload не генерирует LOD/нормали и не меняет Source:сопоставляет
полные vertex attributes,переназначает base/все LOD indices,сохраняет треугольники.
Уже planar6-vertex путь/неподдержанные каналы/indexed input остаются на прежнем пути.
MeshBuilder.prepare_editor_tile делает CPU indexing после world offset;HeightUpdateJob
использует тот же leaf. GPU allocation/publication остаются на main thread.
Transient render_upload/residency_edge_upload живут до commit;canonical arrays/layout,
physics/navigation/editor и cache schema/version прежние. Это не whole-memory unloading.
Ограничения потоков — [Godot4.7 Thread-safe APIs](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html).
Native5120surface rays,max error0,00000763raw;existing8tools/Undo/Redo/save/reopen и
WorldDetail flat/mixed/LOD/canonical-carrier/height-update regressions PASS.
Личные мазки/движение/сфера/широкие художественные переходы автором ещё не приняты.

`_sync_ground_residency` теперь только помечает уходящие регионы, сохраняя fine,
physics и smooth fields. `_poll_overviews` использует одну транзакцию для completed
job и dirty region: актуальный wanted/revision → overview → release fine.
Deadline проверяется перед каждым регионом;время одной публикации не делится.
До продвижения очереди возможно временное превышение числа fine hosts;это не новый
жёсткий memory cap. Fresh run проверен;после горячей замены скрипта старый overview
без revision требует пересоздания проекции. Source/дальность/плотность прежние.

## Единственная текущая последовательность

### Возврат к созданию локации

Решение автора04.11: редкое зависание39мс отложено. Приоритет — общая пригодность систем мира и возможность лепить и наполнять игру. Усталость от оптимизации не меняет целевой минимум120FPS и не превращает открытые gates в PASS.

**Перенос в main04.11 реализован, авторская приёмка OPEN.** Сам перенос оптимизаций не переписывал Source карты/земли; изменения применяются общими владельцами к существующим и новым экземплярам. Native editor и игра проверены в отдельной копии текущего проекта. Последующее наполнение уже меняет авторскую main: двор/soil-дорожка/маски и текущие проверки принадлежат [Миру и карте](directions/world-map.md#текущий-срез--обжитой-двор0411). Цифры A/B ниже относятся к варианту до этого наполнения. Редкие зависания не возвращаются в активную очередь без нового решения автора.

Сверка систем и граница переноса:

- **Земля/материалы:** main уже использует Jolt/общую физическую поверхность, shared material/cache, worker preparation, native/overview LOD и bounded publication. Owner — MapLoader/TerrainPilotProjection/SurfaceMaterials. Terrain3D из полигона не переносится: интеграция Ember UI/Source/save/3looks и production residency ещё не готова; меньший кадр внешней пробы не принимает замену.
- **Трава/цветы:** прежние GrassPatch/DetailPreparation/MultiMesh и авторские masks/seed/tuft size сохраняются. Ordinary detailed grass получила один общий derived ArrayMesh8→6→4 через штатный projected-error LOD. Ближние vertices/indices/UV/цвет/нормали и атлас прежние, tangents при повторной native упаковке округляются менее чем на0,0001. Root positions и плотность не прореживаются. Look1/2 и высокая срезаемая трава не менялись. Compute residency/GPU flowers и гибкая QA-панель не стали production автоматически: нужен штатный editor/save/cut/3looks adapter; возвращаться при конкретном authoring/performance препятствии.
- **Деревья/камни/props:** прежний MapLoader ObjectJob готовит первый упрощённый уровень named tree_bark как ближний, уплотняет используемые вершины и строит последующие native LOD. Worker/main publication, weak cache/invalidation, отмена и бюджеты прежние. Дуб58868→27812tri, берёза18504→8594, осенний клён39140→18082; материалы/Source/коллизия сохранены. Rocks/props уже проходят штатные ObjectLOD/depth/far owners, отдельный renderer не вводился.
- **Свет/вода:** существующие main sky/sun/material/water и native shadows сохранены; CPU shadow-context owner уже общий. QA shadow quality panel, shadowmask и engine fork не переносятся этим срезом: качество/стыки не приняты, bake authoring интеграция не завершена. Новые SSAO/художественные изменения не нужны готовности редактора.
- **Персонажи:** main сохраняет обычных player/followers/Hoshi и уже действующие animation/physics/shadow distance owners. GPU NPC6clips и expanded crowd остаются QA до полноценного lifecycle/authoring/visual gate. Две текущие фигуры main не принимают нагрузку8important+32NPC.

Проверка полезного сценария в **настоящем native editor** копии `landscape_compact`: существующая кисть лепки → Undo/Redo → покраска → кисть травы → постановка дуба → Undo/Redo → Save World → новый несохранённый мазок → discard → native reload. Данные земли совпали с сохранёнными, прошли validation; новый дуб и density layer сохранились. В Forward+ игре загружен именно этот сохранённый дуб, персонаж прошёл4,37м и остался на полу. Проверка через API не принимает ручное ощущение мыши и игрового управления. Editor screenshot показывает загруженный интерфейс с камерой по умолчанию, художественную приёмку им не закрывать.

Targeted checks: `test_main_ready_lods` (3реальные породы/оригинальные materials/near grass exact/distant native4tri), `test_tree_runtime_materials` (shared/private overrides/source/release), `test_detail_brush` (paint/erase/cancel/history/save/reopen), `test_canvas_forms --lifecycle-only` PASS. Последний тест приведён к действующему физическому контракту: stable canonical hull во всех обликах, а не равенство коллизии визуальным кубикам; look1 дополнительно сравнивает hull faces. Native editor успешно завершил сценарий, но вывел ошибки загрузки необязательного zylann.voxel DLL в копии и RID/ObjectDB warnings при остановке; это не crash/teardown fix.

**Общий маршрут main:** Godot4.7.2 Forward+, RTX5070, фактический viewport2560×1440, scale1, MSAA0, VSyncOFF, без cap; сохранены плотность/дальность/свет/вода,2участника партии,223плитки деталей и5tree sources. На spawn и в dense ordinary grass — одинаковое горизонтальное качание yaw±1,1rad, FOV40/70,360измеренных кадров на фазу original/optimized/original; после перемещения отдельные optimized return фазы. Исходный контроль сохраняет прежние native tree LOD и grass8tri, а не отключает всё LOD. После холодного startup, смены варианта и телепорта есть подготовка; эти окна не входят в следующие steady-state числа и не доказывают бесшовный дальний streaming.

- Spawn FOV40: median6,186/5,870/6,193мс; optimized p957,187/p997,559/max7,795. FOV70:5,839/5,472/5,777мс; optimized p956,853/p997,244/max7,407.
- Dense FOV40:4,571/4,163/4,587мс; optimized p955,289/p995,662/max6,019. FOV70:5,236/4,802/5,278мс; optimized p956,557/p996,866/max7,370. Сокращение median в этих видах примерно5–9%.
- Return FOV40/70: median5,924/5,545; p957,357/6,913; p997,646/7,312; max7,887/8,075мс. GPU median spawn optimized5,174/4,780, dense3,540/3,925, return5,208/4,764мс; renderCPU — в JSON. CPU process/physics Performance monitors обновляются раз в секунду: их held samples диагностические, не per-frame quantiles и не слагаемые wall/GPU.
- Engine static memory≈895→894→895MiB, engine video≈1514→1508→1514MiB; это не полная память процесса/долгая сессия. Original-контроль всё ещё дал редкий max34,361мс; peak/stall разбор отложен. В первом коротком optimized повторе также был max11,779мс. Одна чистая серия ниже8,33мс не принимает120FPS во всех позициях/плотностях/crowd.

Evidence/replay: `C:/Users/novos/Documents/Codex/2026-11-04/ember-main-ready/`: isolated `project/addons/readiness_probe/probe.gd`, `project/tools/main_readiness_route.gd`, `evidence/editor.json`, `editor4.log`, `route.json`, `route-full.log`, `lods.log`, `tree-materials.log`, `canvas.log`, `detail.log`, `main/main-checks.json`, игровые PNG. Только isolated copy с `.isolated-main-readiness`; не подключать временный probe к рабочему checkout. Повторять этот маршрут при относящемся изменении, полный suite не требуется. Полигон1км и expanded crowd gates сохраняют прежний статус.

Штатная основа переноса: [ArrayMesh LOD index buffers](https://docs.godotengine.org/en/stable/classes/class_arraymesh.html#class-arraymesh-method-add-surface-from-arrays), [GeometryInstance3D projected LOD bias](https://docs.godotengine.org/en/stable/classes/class_geometryinstance3d.html#class-geometryinstance3d-property-lod-bias). Из полигонного решения перенесено представление8→6→4, выбор уровня передан существующему Godot renderer; нового render backend нет. Источники игровых подходов и альтернативы остаются ниже у существующих владельцев.



### Системная оптимизация мира

#### Игровой полигон площадью 1 км²

С 04.11 сравнение систем идёт также на цельной процедурной локации без NPC. Один рецепт задаёт границы районов в метрах, количество объектов и плотность травы и цветов. Генератор создаёт случайный рельеф либо принимает серую PNG высот (8/16 бит). Он прокладывает улицы, ищет свободные места с допустимым уклоном выше воды, оставляет проходы и записывает фактически размещённые количества. Повтор с тем же seed воспроизводим. При импорте пользовательского PNG форма поверхности принадлежит изображению. Процедурный вариант формирует котловину озера, русло до края карты и горный хребет.

Инструмент — `tools/kilometre_world/run.py`. Для новой внешней папки выполнить `python tools/kilometre_world/run.py generate --workspace <папка> --terrain-addon <каталог terrain_3d> --seed 1415908579`. Нужны Godot 4.7.2, Terrain3D 1.1, Python с NumPy/Pillow и Tk для оконного режима. `--heightmap <png> --min-height 0 --max-height 180` задаёт диапазон высот. `Author.cmd` открывает план местности и поля выбранного района. `Play.cmd` запускает текущую сборку, `Generate.cmd` создаёт вариант по локальному `recipe.json`, `Stress.cmd` сохраняет измерения и шесть видов в `evidence`. Каждая новая сборка сохраняется отдельно.

1–6 открывают районы, 7 — вид на закат с берега. WASD/Shift/ПКМ — движение, бег и камера. F3 позволяет выбрать форму травы, плотность, ширину, высоту, блик, ветер и высоту берегового набега. Кнопка сохранения восстанавливает вид при следующем игровом запуске. G меняет плотность травы, F — цветов, T — тени. Стресс-прогон начинает со штатных настроек независимо от личного профиля.

Полигон использует QA StudyState, материалы формы и GPU-отбор с непрямой отрисовкой. Автор предпочитает прежние мелкие пучки. При первом запуске выбран пучок из четырёх текстурированных плоскостей (всего восемь треугольников). При уменьшении размера на экране остаются сначала три плоскости, затем две перекрещивающиеся. Порог 15/6 экранных пикселей. F3 позволяет вернуть 8 на всех расстояниях. Отдельные травинки 3/2/1, карточки к камере и четвёртый широкий пучок остаются в меню. Сохранённый выбор автора имеет приоритет. Адаптер Terrain3D использует ограниченное окно GPU, стабильные корни и материал Б с настраиваемым солнцем. Сухая земля матовая. Для новой копии установщик берёт QA grass и лицензию карточки из EMBER_GRASS_QA, затем использует локальные файлы.

В F3 дымка вдали (обычный глубинный туман, по умолчанию выкл) и SSAO (выкл / слабое / исходное) независимы и сохраняются с видом. Отдельный несохраняемый переключатель нагрузки создаёт у текущей позиции до восьми анимированных Hoshi и четырёх кабанов. Для сопоставимого замера выбрать луг. Это тест движения, физики, теней и анимации; квесты и боевой ИИ подключаются на игровой карте. Кадр HUD показывает измеренный FPS и максимум за последнюю секунду.

16 регионов Terrain3D по 250 м, шаг высоты 0,9765625 м. Для километрового полигона все регионы уже резидентны. Штатный Full/Game готовит реальную физическую поверхность один раз перед передачей управления, около 0,30 с; телепорт больше не перестраивает тот же пол. Для воды используются основной материал Ember и профиль набега EmberCompactSeaSwash.wave_profile, пересекающийся с картой высот. Берег и след на песке используют одну фазу. Полная история пены компактного океана, отражения объектов и подводная камера остаются отдельной интеграцией. У деревьев упрощённая ближняя сетка и дальние LOD.

От Guerrilla взят вопрос, какие данные можно приготовить до появления района. У miHoYo важна отдельная цена близких и дальних каскадов. Для Ember проверить на одном seed деревья с полным материалом, их тени и упрощённое дальнее представление. Сравнивать силуэт из деревни и с горы, покой, вращение, проход в обе стороны, p99/max и память. Затем проверить выгрузку другого района с уникальными ресурсами. [Guerrilla, Streaming the World of Horizon Zero Dawn](https://www.guerrilla-games.com/read/Streaming-the-World-of-Horizon-Zero-Dawn) · [miHoYo, консольный рендер Genshin Impact, слайды 17–21](https://image.docswell.com/s/UnityJapan/KWRPQ5-210617-unity-dojo20211mihoyozhenzhongyi).

На seed 1415908579 размещены все 1 620 объектов. В Forward+ при native 2560×1440 на RTX 5070 проверены шесть мест при FOV40/70, непрерывное движение камеры на 600 м и обратно при 40 м/с и физическая опора в 31 точке. Максимальная погрешность физики менее 0,4 мм. Густой лес и длинный маршрут выходят за бюджет 8,33 мс. Полный бюджет и ручная оценка изображения остаются открытыми.

При неизменном seed и наполнении, RTX 5070, native 1440p, прогоны `route_20261104_210732` → `route_20261104_211540`: в лесу при вращении стоя p99 11,27 → 8,72 мс, с Shift и поворотом 13,04 → 10,09 мс. Деревня → гора / обратно на 40 м/с — p99 9,74 / 9,95 мс в обновлённой сборке, максимумы 27,48 / 13,25 мс. В отдельном A/B/A среди 157 видовых групп деревьев при неизменных материалах, траве и камере подмена только сеток дала медиану леса 10,34 → 7,60 → 10,54 мс. Ближний дуб 58 868 → 27 812 треугольников, берёза 18 504 → 8 594. Дальние LOD сохраняются. Ручная оценка силуэтов, берега, плотности и общий бюджет открыты.

После этапа домов в сравнении дальнего леса проверить штатные Godot visibility ranges с одним упрощённым представлением на группу крон. Одинаковые ближняя геометрия, материал, плотность, тени, разрешение и маршрут. Оценить GPU, p99 кадра, силуэт и переходы. У Toni Macaroni кластерные LOD сменяются дальними воксельными представлениями, а на горизонте используются прокси без данных каждого экземпляра. Это референс для группировки, его публичные цифры не сопоставимы с нашим игровым маршрутом. [Описание Forest Showcase](https://www.youtube.com/watch?v=uR5EvBWxN14) · [Godot Visibility ranges](https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html).

**Замер с предпочтительными пучками.** На RTX 5070 при native 2560×1440 и одинаковом повороте над лугом кадр с землёй и небом стоил 1,23–1,35 мс по медиане в двух прогонах. В замере A/B/A (пучки 8 / 8→6→4 / 8, SSAO исходное) медианы 3,156 / 3,047 / 3,169 мс, p99 5,780 / 5,626 / 5,815 мс. При ~35 055 видимых пучках количество треугольников на пучках 280 440 → 187 628 (3 116 ближних, 17 474 средних, 14 464 дальних). Плотность, атлас и ближняя форма прежние. Ветер и небольшой поворот камеры записаны для ручной оценки перехода. Для SSAO выкл / слабое / исходное / выкл медианы 2,81 / 3,19 / 3,33 / 2,77 мс; лёгкая дымка с SSAO выкл 2,80 мс, повтор без дымки 2,70 мс. Числа относятся к этому виду луга. [Guerrilla о геометрии и стоимости растительности Horizon](https://www.gdcvault.com/play/1025530/) · [Sucker Punch о GPU-траве](https://gdcvault.com/play/1027214/) · [miHoYo о разной роли способов AO](https://image.docswell.com/s/UnityJapan/KWRPQ5-210617-unity-dojo20211mihoyozhenzhongyi).

**Дальний перелёт и рабочие потоки.** Для неподвижной карты используется штатная полная коллизия Terrain3D. На этой Windows-машине (20 логических процессоров, RTX 5070, native 1440p) с автоматическим пулом и динамическим полом были кадры 23–55 мс. В части из них длинное ожидание следовало за первым сигналом физики. В других долго шёл интервал между сигналами рендера. На полном полу также зарегистрирован кадр 33 мс. В выборке одного такого интервала большая часть циклов процесса пришлась за пределы главного потока; конкретную функцию ожидания это не определяет. [Реализация динамической и полной коллизии Terrain3D 1.1](https://github.com/TokisanGames/Terrain3D/blob/v1.1.0-stable/src/terrain_3d_collision.cpp).

Внешний полигон ограничивает общий WorkerThreadPool Godot четырьмя рабочими потоками (или меньшим числом доступных CPU). На том же полном полу, том же seed и маршруте 600 м туда/обратно максимумы по отдельным плечам: 4 потока — 6,95/7,16 мс; автоматический пул — 32,06/43,67 мс; повтор с 4 потоками — 7,05/7,31 мс. Процессы без ограничения в других повторах могли уложиться в бюджет. Это настройка отдельной карты, не универсальный лимит для всего Ember. Медианная рабочая память процесса в одном сопоставлении около 1 518 МиБ на полном полу и 1 484 МиБ на динамическом. Сравнить штатным run.py trace, --dynamic-floor возвращает прежний пол, --auto-workers — прежнюю политику потоков. JSON содержит фазовые отметки и позицию; trace пишет файлы после плеча, общее stress отдельно проверяет пол/камеру.

**Настройки мазка.** F3 → «Проба со старой карты» восстанавливает форму карточек и настройки manual-snapshot-1113408: 50%, ширина 6×, высота 0,30×, группировка 0%, пятно 0,5 м, ветер 1/1/0°. Камера и основной выбор пучков остаются отдельными. Для низких широких отдельных травинок после пробы переключить только форму. Плотность 0–200%, ширина 0,25–6×, высота 0,25–3×. Доступны группировка, размер пятна, примесь собственного цвета, приём солнечных теней, сила/скорость/направление ветра. Дымка есть вверху панели и сохраняется с видом. Последовательность корней GPU распределена равномернее внутри плитки; дополнительные корни появляются в устойчивых координатах. Удвоенный пул резервируется только при повышенной плотности или группировке, требующей запаса кандидатов. При стандартных 22 группах/м² это около 152 МиБ дополнительных крупных буферов за сессию. Локальные районные плотности по-прежнему задаются в рецепте конструктора.

При FOV70 на лугу число выбранных GPU-травинок 0/100/150/200/100% — 0/299 338/448 074/597 370/299 338. Для низких широких отдельных травинок на том же лугу медианы при 100/200/100% — 3,41/4,29/3,41 мс, p99 5,50/6,45/5,47 мс (автоматический пул). Сохранение и повторное открытие 200%, размеров, пятен, цвета, теней и дымки проверены. Историческая проба и новый снимок рядом — evidence/paint-qa-215934/brushes.jpg. Вид в движении принимает автор.

**Поворот на горе, повтор 04.11.** Команда run.py mountain --workspace <папка> использует прежнюю последовательность шести районов при FOV40/70 и ещё 12 повторов горы в каждом угле обзора. Два новых процесса, seed1415908579, native2560×1440/scale1, RTX5070, полный физический пол и 4 рабочих потока, без NPC. Всего на горе 52 интервала по 2,2 с и 76 001 измеренный кадр. Поворот стоя проверен при FOV40, поворот с движением и физическим Shift — при FOV70. Максимумы двух запусков 4,754 и 5,034 мс, худшие p99 4,160/4,281 мс. Фокус окна сохранялся во всех измеряемых кадрах, потери Shift не было, интервалы выше 10 мс отсутствовали во всей серии из 72 проверок. Evidence — mountain_20261104_221745 и mountain_20261104_221945/mountain.json.

В историческом route_20261104_221045 на mountain70 был кадр 39,095 мс, но на самом длинном кадре ещё не записывались границы этапов или фокус. В конце той фазы Shift уже не определялся как нажатый. Это не устанавливает причину задержки. В текущем повторе максимальный кадр 5,034 мс сопровождался выборками GPU3,617 и render CPU0,528 мс; их нельзя складывать или приписывать старому выбросу. mountain_probe.gd сохраняет интервалы между process/physics/pre_draw/post_draw, два соседних кадра, состояние окна и ввода при новом выбросе. Для исторических 39 мс причина остаётся неподтверждённой. Изменены диагностика и команда воспроизведения; настройки вида в этом срезе не менялись.

**Общий маршрут.** В route_20261104_221234 все 12 коротких проверок укладывались в 8,33 мс; перелёт туда/обратно max7,19/7,22 мс. 31 проба физики прошла с погрешностью до0,35мм. Один удачный общий маршрут и ограниченный повтор горы не дают гарантии минимума120FPS в любой позиции.

Группа на лугу остаётся отдельной проверкой без боевого ИИ. В actors_20261104_221154 все 8 NPC и 4 кабана были на полу, p99 с группой 4,91 мс, max 5,79 мс в измеренном интервале.

Автор переключил приоритет с отдельных координат на масштабирование локации. Пойманные пики сохраняются как регрессии маршрута. Локальный пик снова становится рабочей задачей, если нарушает игру либо воспроизводит общий дефект класса объектов, например первое назначение материала во время движения. Ближайшие решения принимаем по трём раздельным нагрузкам: холодный вход, стоимость уже видимого плотного мира и рост памяти при расширении карты.

**Бюджеты кадра.** На больших секционных картах земля делит время подключения с растительностью через `EmberDetailPreparation`. У объектов своя ограниченная очередь в `EmberMapLoader`; региональная вода через `EmberCompactWaterRegions` расходует собственный лимит на подготовку и выгрузку в GPU. Совпадение этих расходов возможно. Проверка в инструментированной копии Windows-экспорта, с исходными плотностью и тенями: RTX 5070, Forward+, фактические 2560×1440, FOV70. Две позиции, три запуска (стартовая зона, холодный/повторный проход на холме), стояние, поворот, бег, три секунды ускорения, обратный ход. Из 14 952 интервалов 200 превысили 8,33 мс. В 164 из этих 200 суммарно меньше 1 мс заняли измеренные участки CPU для земли/травы, обработки очереди объектов и подготовки региональной воды. Только в четырёх интервалах две из трёх групп одновременно стоили хотя бы по 0,5 мс. Это не полный CPU/GPU-профиль. Такого результата недостаточно, чтобы переписывать все очереди или принимать 120 FPS. Отдельный плотный полигон без NPC по-прежнему имеет p99 14,70 мс при беге на 96 м.

**Размер локации при неизменном виде игрока.** На одном и том же маршруте сравнили обычную сцену, ту же сцену с тремя добавочными группами существующего декора вне дальности камеры, затем снова обычную сцену. В опытном варианте на 60 экземпляров больше; исходные модели общие, дальних уникальных текстур и новой земли нет. Живых узлов 2 650 → 2 944 → 2 650, зарегистрированных объектов карты 22 → 82 → 22. p99 кадра 9,36 → 9,10 → 9,01 мс. VRAM в конце 1 471 → 1 511 → 1 487 МиБ. Невидимые экземпляры могут сохранять цену в памяти даже при близком p99. Карта сейчас является одной авторской сценой; подгрузка ближнего вида и снятие физики вдали сами по себе не выгружают всю ветку сцены. Перед изменением этой границы проверить соседний район с **другими** ресурсами, освобождение при уходе и повторное использование при возврате. Физическая опора, сохранения и авторская карта остаются обязательными условиями.

**Полнота пакета локации.** На чистом профиле обычного экспорта один маршрут создал 93 записи геометрии, 97 записей растительности и 9 записей воды. Их ключей в исходном пакете не было. В A/B/A те же 199 записей (13,33 МиБ) добавили только к проверочной сборке. Старт процесса до начала маршрута: 37,19 → 34,26 → 38,53 с. На этом проходе дополнительная сборка не создала записей этих трёх кэшей. При восстановлении только папок shader_cache и vulkan на этой же машине старт занял 21,18 с, а игра создала все 199 записей мира. Полностью прогретый профиль дал 13,34 с. Это отдельные причины долгого входа. Результат графического кэша зависит от устройства. Эти замеры не доказывают покрытие всей карты и не измеряют холодный диск ОС. Штатный `tools/run_world_build_probe.py` теперь сообщает объём и число новых файлов по кэшу; `--require-prepared` на изолированной неизменённой карте требует пустого исходного профиля производных данных и отсутствия новых записей к концу стандартной проверки. Штатный тест дошёл до готового мира в двух экспортах. Строгий режим вернул ошибку на исходном пакете с 199 новыми записями и прошёл на опытном с нулём. Обычная проверка запуска сохраняет прежние критерии. Пакет из одного наблюдавшегося маршрута служит экспериментом, входами штатной сборки должны быть сохранённая карта, её зависимости и версия алгоритма.

**Подходы разработчиков и их место в Ember.** Guerrilla держит самый грубый уровень земли доступным, а для зон событий разделяет подсказку о загрузке и сигнал активации. В Ember базовое представление, опора и подробный вид нужно проверять по отдельности. [Guerrilla, Streaming the World of Horizon Zero Dawn, слайды 37–40](https://www.guerrilla-games.com/read/Streaming-the-World-of-Horizon-Zero-Dawn). Sucker Punch описывает загрузку небольших mip-уровней текстур с индексом при старте и чтение нужного диапазона подробных данных позднее. Для Ember это основание измерять вес обязательных зависимостей района и цену дополнительной детализации. [Sucker Punch, Zen of Streaming](https://gdcvault.com/play/1027545/Zen-of-Streaming-Building-and). miHoYo описывает запечённые данные сцены для отражений, переосвещение при игре, приоритет и разрешение локальных теней. Для Ember важен принцип: отдельно определить, какие данные зависят от авторской карты, а какие приходится менять при движении или смене света. [miHoYo, слайды 38–39 и 56–57](https://image.docswell.com/s/UnityJapan/KWRPQ5-210617-unity-dojo20211mihoyozhenzhongyi).

**Порядок работы.** Следующий игровой срез — сравнить обычное и плотное поле без NPC по всему маршруту при FOV40/70: сначала стоимость уже готового вида и движения через границы, затем A/B одного дальнего представления при тех же ближнем покрытии, цвете, свете и физике. По сборке — получить воспроизводимый перечень обязательных данных для входа и соседних участков и проверить на другом старте. До расширения карты — проверить память дальнего района с уникальными ресурсами при входе, уходе и возврате. Нативные диапазоны видимости Godot — кандидат для групп дальних объектов, если измерения покажут цену их отрисовки; выгрузку памяти проверять отдельно. Приёмка — готовый ближний мир, p95/p99, доля кадров выше 8,33 мс и ограниченный рост RAM/VRAM между проходами. [Godot, Visibility ranges (HLOD)](https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html). Данные, сценарии A/B/A и сводка — `C:/Users/novos/Documents/Codex/2026-11-04/ember-world-system-budget/`.

### Ограниченная GPU-проба травы03.11

**Текущий согласованный срез:** координатор — LOD/ветер травы и сборка;
Sol/high — только QA GPU NPC на6клипах; Luna/medium — read-only аудит стволов,
листвы и кустов с ограниченной рекомендацией. Один писатель/GPU-прогон за раз.
Все реализации остаются disposable QA, production migration не разрешена.
Stock4.7.2/Forward+/Jolt/Safe, native2560×1440/TAAon, прежние плотность/дальность,
8important/32ordinary,39NPC+player,25848patches/220135instances иharvest/дома/свет сохранены.
Source/редактор/физика/save/main не менялись; общий120FPS gate **OPEN**.

**NPC6клипов выполнен технически, не перенос вruntime.** Idle/walk/run/talk/sit/dance,
631paletteframes/4,12MB;39984vertex checks на22surfaces, max error3,385мм.
Same-load native/GPU/native wall median16,404/11,276/16,440мс;
GPU p9515,212/p9923,795/max42,159мс. Восемь важных сохраняют native springs;
39акторов независимо меняют клипы, переход0,18с сохраняет bounded native fallback:
обычно максимум6ordinary,при массовой39смене — все32 на время перехода.
Matched proof использует полный index mesh ordinary в обоих вариантах,47 103tri/NPC;
это не production spatial LOD. Отдельный GPU6,816→7,293мс не ускорился.
Evidence: `C:/Users/novos/Documents/Codex/2026-11-03/ember-npc-six-gpu/Report.md`.

**Трава:** прежний GPU-пилот расширен до3→2→1triangles/blade (5/4/3vertices),
выбор по проекции высоты на экран, morph двух сторон. Тот же seed/корни/высота/
дальность;8стеблей на210975пучков =1687800potential. Один MultiMesh/3indirect draws,
общий output103,02MiB +6,44MiB classification вместо206MiB у первой пробы.
Три диапазона упакованы через atomic counts/prefix/barriers без overlap/overflow.
На неподвижной камере повторный cull не нужен; vertex wind/growth не перестраивают
placement. Growth — только показ формы0/50/100%, не приёмка cold streaming.
У ordinary нет alpha-карточки/собственной тени; высокая срезаемая трава/тени прежние.
Удалена12% примесь фиксированного зелёного: общий ground-slot pigment/light binding;
прямого чтения смешанного цвета земли под каждым корнем нет. Цвет оценивает автор.

**Цветы:** тот же GrassPatch Source/8539clusters,3вида и число соцветий сохранены.
Near186/888tri → mid84/390 → far6/30; упрощаются стебли/листья/контур соцветия,
вдали остаётся quad каждого соцветия. Высота+15%/общая зелень прежнего QA-preview,
лепестки/атлас/позиции прежние. Центральный HLOD, hysteresis и0,15с dither переход;
shader wind/growth, без alpha blend. Геометрия resident цветов на широком виде
3,609→2,753–2,764Mtri (≈23–24%); это не счётчик только видимых фрагментов.
Цветы не переведены на compute culling/indirect; игровой cut/save owner прежний.

**Измеренный результат.** Общий corrected A/B/A wall16,567/12,084/16,608мс;
ветер11,992мс. Эта дельта включает NPC, её нельзя приписывать траве.
Отдельный tuning при одинаковых baked NPC/цветах: old2LOD / pixels20-10 /
40-20 /60-30 /old-return GPU7,596/7,969/7,834/7,647/7,665мс.
Pixels40-20 даёт на FOV70 counts[9921,115932,391706]:653333tri против831775
у старого3→1 (−21,5%);60-30 —555100tri (−33,3%). GPU gain не доказан.
На FOV40 вариант40-20,наоборот,405039tri против370073:экранный размер сохраняет
больше формы при увеличении. Больше LOD само по себе не является оптимизацией.
Live40-20+ветер:wall median11,245/p9513,400/p9921,480/max42,225мс;
74,27%frames выше8,333мс, binding median0,189мс. ≈89FPS median, **120FPS OPEN**.
Новый grass/HLOD не переносить ради FPS по меньшему triangle count; возврат к нему
после измеренной причины shader/overdraw/culling либо принятого улучшения картинки.

**Деревья/кусты:** аудит подтвердил shared immutable meshes и worker/native index LOD,
не отсутствие LOD. В fixture доступны bark oak48248→24124→12062→6028→2442→1202tri;
leaves10620→3688→160. Birch leaves4656→1670→20; куст7620→1598.
Это доступные уровни, не фактический выбор камеры. Более ранний native bias1/0,5/1
дал GPU8,808/8,764/8,729мс:ускорение не подтверждено,вruntime не переносить.
Общего ветра деревьев нет,только hit sway FruitTree. Ягоды отдельными узлами вне
PlantLOD. Следующие кандидаты: плавный silhouette-preserving canopy HLOD и группировка
ягод в прежнем prefab builder с сохранением harvest ID; новых owners/Source нет.
Source стволов/крон и художественная форма этим срезом не упрощались.

**Проверки/границы:** corrected combined и tuning PASS,engine/script/leaks0,
3прежних UID warnings. FOV40/70/40/70:181775/517559selected точно как у2LOD;
close/high показывают смену распределения, buffers/220135instances/6clips/8heroes/
support/возврат native/освобождение ресурсов сохранены. Статические40/70/high/growth
кадры просмотрены; ручной цвет/плавность/TAA/motion vectors и настоящий streaming OPEN.
Первый combined ошибочно собрал mid mesh без сокращения tangent array; отвергнут.
3LOD smoke24blades=[8,8,8],prefix[0,8,16] и teardown проверены после исправления.
Source guards относятся к frozen cohort до возобновления residency,не закрывают paging.
RD uniform set освобождается до classification buffer; command RID workaround4.7.2
прежний. GPU timestamp единицы сверены с profiler движка:наносекунды,ms=raw/1e6.
Live QA snapshot≈8,88GiB working set/11,48GiB private,system VRAM4925MiB с двумя
сравниваемыми представлениями; это не peak/production/GTX1060 memory acceptance.
Sources/manifest/данные/как повторить: `C:/Users/novos/Documents/Codex/2026-11-03/ember-vegetation-package/README.md`.
Прежние2LOD/пигмент/5→3tri доказательства сохранены в `ember-gpu-grass/README.md`;
первый невидимый вариант без custom AABB отвергнут; production ordinary8/high24tri прежние.

**Ручной проход автора03.11:** согласована отдельная QA-сессия с кнопкой
«Производительность»/F3;extends существующего EmberBenchmarkOverlay,production UI прежний.
FPS/wall p95/p99/max/пики/график,renderCPU/GPU,Godot memory/draw counters;
таймерGPU выключается с закрытием панели. Это не OS utilization% и не input latency;
engine counters могут отставать до1с. Временные grass/flower pixelLOD,tree bias,
near/far sampling32ordinary,режимnative/GPU,ветер strength/speed/worlddirection,
камера;8important full. Есть reset/return-to-start/JSON snapshot,без authoring/save схемы.
QA-трава/цветы остаются fixed-start preview;новые streamed patches прежние,об этом явно
написано вUI. Native API controls/ненулевойdraw/буферы/сброс/teardown/3вкладки/JSON PASS,
engine/script errors0;mouse/keyboard/manual art OPEN. Общего ветра крон по-прежнему нет.
Запуск/кадры/sources/verification: `C:/Users/novos/Documents/Codex/2026-11-03/ember-manual-performance/README.md`.
Основа — [Godot Performance](https://docs.godotengine.org/en/4.7/classes/class_performance.html)
и прежний native lod_bias;новая telemetry-служба/renderer не добавлялись.

**Результат ручного прохода автора03.11 — не принят по производительности.**
Автор наблюдает90→80→60,иногда50FPS,в том числе без NPC в кадре;это наблюдение,
причина пока не установлена. Скриншот: [manual-performance](art/references/manual-performance-20261103.png):
81,9FPS/12,21мс,p9515,15/p9924,74/max39,83мс,пик с начала55,85мс;96%кадров>8,33мс.
Найден настоящий сохранённый автором `manual-snapshot-1022901.json`:1200frames/16,607с,
72,259FPS/13,839мс,median12,889/p9525,040/p9931,723/max58,573мс;
88,75%>8,33мс,пик с начала569,823мс. Последний пик не локализован и не равен max окна.
GPU6,555/renderCPU1,425/engine frame11,133/physics26,659мс — раздельные,
несинхронно обновляемые счётчики;не складывать и не выводить причину одним вычитанием.
8important/32ordinary/39NPC/fallen0/pending support0 сохранены;grass230410instances,
280resident/pending0 при fixed GPU source210975пучков. Это смешанный путь streaming.
Автор менял настройки:LOD grass/flowers2×,tree2,05×,FOV52°,polar76°,wind1,25/speed1,6;
реальный viewport2560×1373/scale1,а заголовок панели ошибочно фиксирован2560×1440.
Не сравнивать этот проход напрямую с прежним fixed1440p baseline.
`manual-snapshot-69122.json` — автоматический setup snapshot после PNG,не ручной baseline;
его851,9мс содержит служебную подготовку и не принимается как чистый игровой hitch.
Оба JSON искриншот сохранены в `C:/Users/novos/Documents/Codex/2026-11-03/ember-manual-feedback/`.

**Пункт1 после отдыха03.11 — инструмент готов,причина полного кадра ещё открыта.**
Существующие внешние `qa_manual_panel.gd`/`qa_manual_session.gd` расширены без правок
production runtime/Source. Заголовок читает фактический render target/3D scale/режим;
обычный launcher просит fullscreen2560×1440. Не использовать `ViewportTexture.get_size()`
как размер framebuffer:в4.7.2 он дополнительно умножает canvas stretch;visible rect×stretch
сверен с readback2560×1440. Регрессия header1280×720 воспроизведена до исправления;
native UI test покрывает scale0,5 и canvas1600×900→2560×1440,arming/смену настроек.
F8/кнопка во вкладке «Кадр» пишет20с после2с подготовки в bounded RAM buffer;
timestamps/wall/physics tick count/контекст камеры/NPC/object preparation/binding и
раздельные delayed render/engine counters. Файл float64+JSON создаётся после остановки;
настройки/resize/потеря фокуса помечают прерванную запись. Нормальный ручной запуск
больше не повторяет старый UI/6clip proof и не сохраняет3PNG перед выдачей управления.

Короткий native1440p маршрут,в каждой чистой фазе6с,GPU timers OFF:
- NPC в кадре30–33:90,7FPS,p9514,35/p9922,97/max44,89мс.
- После разворота осталось2–4NPC:89,2FPS,p9516,31/p9924,90/max36,44мс.
- Широкий вид35–37NPC:75,3FPS,p9519,64/p9935,12/max37,90мс.
- Движение14,01м:65,2FPS,p9524,98/p9936,93/max37,78мс.
- Возврат:85,0FPS,p9514,98/p9924,23/max39,30мс.
Отдельный4с render diagnostic:GPU median8,88мс;не смешивать с чистыми wall фазами.
8important/32ordinary/39NPC/fallen0 сохранены;плотность/дальность прежние. Переходы
камеры/подготовка/PNG/save исключены из интервалов;cold/transition spikes этим не закрыты.
Сбор trace median64–68мкс/кадр;это измеренная диагностическая добавка,не нулевая стоимость.
Physics cadence:near без physics tick median7,90мс,с1tick12,28мс;разворот7,57/12,12мс,
wide9,32/13,44мс,движение9,71/14,63мс. Это связь с physics-step работой на CPU,не
доказательство стоимости одного конкретного callback и не сумма engine monitors.
Object preparation p99≈1,19–1,46мс,обычный NPC binding p99≈0,26–0,41мс:эти два
локальных участка не объясняют весь кадр. Приоритет attribution — physics callbacks/
motion/support и общий render;текущие данные не доказывают цену каждой подсистемы.
Performance gate120FPS остаётся OPEN,это воспроизведение,не FPS improvement.

Evidence: `C:/Users/novos/Documents/Codex/2026-11-03/ember-frame-trace/`:
`route-verified/` сырые интервалы/реальный PNG;`analysis.json` и`analyze_trace.py`.
Первый `route/` отклонён из-за ошибочной проверки texture size. Во втором все интервалы
native1440p иполны,но process verdict false:строгий assert0NPC не прошёл(остались2–4).
Это сохранено,не объявлять полным offscreen PASS. Анализ проверяет фактическую
малую когорту;сценарий для повторения исправлен на проверку исключения dense cohort,
после изменения только этого assert новый полный прогон не выполнялся.
Ручная оценка F8/полного экрана автором OPEN;основной мир и6clip proof не принимались заново.

**Пункт2 после отдыха03.11 — готов к ручному проходу,не новый FPS PASS.**
В ручной QA-сессии Ctrl шаг0,4×/Shift временное ускорение1,6×;при двух клавишах шаг.
Настройки сессионные:EmberPlayer по умолчанию сохраняет прежний Shift шаг/без boost,
flight path не менялся. EmberFollowCamera.look_offset задаёт screen-right/world-up
без изменения FOV/дистанции/наклона;ползунки «Точка взгляда» во вкладке «Дальность»
передают метры,есть общий reset и snapshot JSON. Значение по умолчанию0,Resource/save
для камеры не расширялись. Виды/число травы,дальность и8important сохранены.
ВQA два из16SturdyCrate перенесены к старту;первый получил native breakable/effect/
contact настройки и подпись,второй остаётся прочным. Placement settings обновлены.
Общий WorldItem3D выравнивает предмет надголовой по высоте капсулы/низу mesh,
с yaw героя и фиксированными pitch/roll;исправление действует в основном runtime.
Данные/инварианты предметов принадлежат Inspector I3.15;нового save/physics owner нет.

Native Forward+ PASS:physical crates regression была RED до carry fix и GREEN после;
tilted pickup→overhead/yaw/move/combat resume,прежние F/G/веса/void/save/load/Undo/reopen.
World strike native PASS:held/UI/wall/reach/big guards,break FX/one save/cold load.
В полной QA-локации Input state дал скорости48/19,2/76,8world units/s(normal/Ctrl/Shift),
offset2м/1м реально сместил камеру/reset вернул её,JSON/подписи/типы/total16/8heroes PASS.
Native PNG просмотрены;мышь/OS-клавиатура/ощущение/mainF5 остаются ручными OPEN.
Evidence: `C:/Users/novos/Documents/Codex/2026-11-03/ember-qa-controls/`.
Обычный `ember-manual-performance/Start-Ember-Manual.cmd` обновлён;QA/root owners
сверены. Root .tscn/Resource иproject.godot не менялись. Новый FPS/stress не измерялся:
срез меняет удобство ручного прохода,не принимает120FPS. Следующий результат — пункт3.

**Пункт3 после отдыха03.11 — physics attribution и исправление повторного recovery в fixture.**
В disposable QA временно измерены11physics scopes,без production instrumentation.
На готовом GPU6clip workload с39controllers/8important,один physics tick:
controllers median1,872мс near/1,923wide/1,951movement;Map activity0,436/0,432/0,435мс;
player0,576/0,583/0,708мс;recovery median≈0,09–0,10мс,но max11–23мс.
Это wall scopes вызовов,не exclusive native engine CPU;outer WorldCanvas включает
ExploreScene,их нельзя складывать. Engine step вне callbacks этим не измерен.
Повторная узкая запись связала пики с `recover_body` и synchronous autosave:
MessageBottle,HarborCargoQuest/Crate,PhysicalCrates/SmallCrate/SturdyCrate падали
ниже−256;отдельный A/B также выявил LargeCrate. Это исходные предметы main,
оставшиеся на старой Y после подмены земли вstress;новые16pop crates были на месте.
Например,bottleY3 при canonical floor44,127;старые small/sturdyY15,5 приfloor52/56.
Они возвращались к той же неверной высоте,снова падали и снова сохранялись вне кадра.

Исправлен существующий fixture owner `tools/test_world_gameplay_stress.gd`:
`align_legacy_fixture_items` после подготовки земли и до persistence/timing поднимает
только активные buried authored items на canonical surface с учётом низа mesh,
сохраняет XZ/количество/ID,передаёт новые poses прежним placement/ExploreState/recovery
owners и штатной подготовке опоры. Авторские .tscn/Resource и production physics/save
не менялись;автосохранение/защита от падения не выключались. В этом срезе5items.

Чистый matched A/B/A/B,без callback wrappers/GPU timers,10с каждая фаза:
- Старая расстановка:17saves,mean11,100/p9922,925/max36,285мс.
- Исправленная:0saves,mean10,800/p9914,662/max15,556мс.
- Возврат старой:17saves,mean11,092/p9922,017/max44,623мс.
- Возврат исправленной:0saves,mean10,835/p9914,157/max22,380мс.
Средний FPS≈90→92–93;это в первую очередь исправление хвостов,не достижение120FPS.
Никаких выводов о стоимости всего Godot или травы из этих emergency saves не делать.
Ранние live p99/max этой fixture содержали дефект;считать их общим наблюдением
старого workload,не отдельной ценой grass/NPC или доказательством GPU stalls.
Не обнулять остальные изолированные render/geometry/correctness результаты автоматически.

Один подтверждающий native2560×1440/scale1 маршрут после исправления:6полных phases,
near92,0FPS/p9914,94/max16,57мс;wide79,4/p9920,81/max29,04;
движение68,6/p9926,40/max28,78;возврат89,0/p9915,17/max16,73.
0game autosaves за весь маршрут,16pop crates/39NPC/8important/fallen0,Source guards PASS.
GPU diagnostic отделён;120FPS/native1440p иполная art/gameplay приёмка остаются OPEN.
Все11временных instrumentation overlays сняты;основной runtime12guards byte-equal.
Ручной launcher использует исправленный общий stress bootstrap.
Evidence: `C:/Users/novos/Documents/Codex/2026-11-03/ember-physics-attribution/`:
`profile/`, `profile-deep/`, `support-ab/`, `verified-route/`, `analysis.json`, архив overlays.
Shared runtime materials проверены и подключены ниже;повтор recovery и six-clip
correctness без новой причины не нужен.

**Пункт3 — shared tree materials03.11,внедрено технически;120FPS OPEN.**
644tree carriers используют5mesh/2shader/1288surface bindings. Старый per-prop clone
давал1288active materials при10разных наборах параметров. Ограниченный runtime A/B
объединял только побитно одинаковые shader/priority/next-pass/uniform bindings;
меши/LOD/culling/shadows/physics/Source/8important не менялись.
Stock [Forward+ automatic instancing](https://docs.godotengine.org/en/4.7/tutorials/performance/optimizing_3d_performance.html#use-automatic-instancing)
использует одинаковые mesh/material. Merger не нужен:он добавил бы отдельную
сборку/LOD/streaming границу без необходимости текущего результата.

Matched whole-frame original/shared/original,7с каждая фаза,live6clips/physics,
GPU timers OFF;метры камеры/FOV/разрешение одинаковы внутри тройки:
- Near mean11,007/10,771/11,079мс,≈2–3% gain;visible draws749→714,
  shadow draws1368→1239;tail p99≈15,12/14,94/14,99мс.
- Wide mean11,634/11,173/11,527мс,≈3–4% gain;visible1173→1052,
  shadow1653→1535;p99≈15,11/15,14/15,09мс,снижения p99 здесь нет.
- Отдельная3с render diagnostic:near GPU9,277→9,135/renderCPU1,843→1,650мс;
  wide GPU8,351→7,942/renderCPU2,318→2,018мс. Не складывать scopes.
Frozen1440p/paused/time_scale0/TAAOFF RGB original/shared совпали пиксель в пиксель.
Перед live timings TAA/time_scale/physics возвращены. Это небольшой общий gain,
не120FPS и не доказательство дешёвой всей растительности.

Внедрение в существующих owners:MapLoader.runtime_tree_material держит map-local
weak registry по Source Material ID/look и каноническим параметрам. Prop получает
общий derived binding только вruntime;Engine.is_editor_hint сохраняет прежние
private duplicates. Source/индивидуальные overrides/разные карты/облики не сливаются.
Изменение параметров Source при существующем cache invalidation создаёт новую версию,
не мутирует старую. Не полагаться на ShaderMaterial.changed:uniform setter его не
вызывает. Property enumeration нормализует defaults вдвижке4.7.2,какduplicate();
signature читается после этой нормализации,иначе первая копия оставалась бы отдельной.
Registry не удерживает неиспользуемые материалы;новый lookup чистит stale weak entries.
Нового Resource/schema/renderer/addon и новых editor controls нет.

test_tree_runtime_materials native Forward+ PASS:2maps/3look bindings/return,
private override/source change/instance values/original semantic values/weak release.
Первый тест выявил default normalization/синтетический vec4 color hint,исправлено;
его отклонённый log сохранён. Это binding regression,не визуальная art-приёмка3looks.
Проверка итогового root-кода на denseQA:1288bindings→10active materials,
map registry16entries(часть для retained источников),RGB shared/private-copy exact;
16crates/39NPC/8important/fallen0,6native1440p intervals/move/return/0game saves PASS.
Пример route:near91,7/wide81,4/move72,3FPS;с другим запуском не считать matched A/B.
Контрольный p99 near15,66/wide20,05/move27,30мс;120FPS/хвосты остаются открытыми.
Runtime путь подключён кmain через общиеProp/Map scripts;ручной main/editor/3looks
по-прежнему OPEN. Author scene/Resources/project.godot не менялись.
Evidence:`C:/Users/novos/Documents/Codex/2026-11-03/ember-material-instancing/`:
`ab/`, `analysis.json`, `binding-test.log`, `runtime-route/`, `runtime-verification.json`.
GPU NPC native/spatial LOD проверены следующим ограниченным сравнением;его результат ниже.

**Пункт3 — геометрия GPU NPC03.11:штатный index LOD включён в ручном QA;120FPS OPEN.**
Существующие body/hair ArrayMesh уже содержат offline native LOD;`duplicate()` в GPU
palette сохраняет их и все vertex/skin streams. Face/57morphs остаются исходными.
QA manual session принудительно ставила `lod_bias=1e6` для прежнего full-index
сравнения анимаций. Блокировка снята:ordinary native fallback и GPU batches используют
исходный bias1;8important/player/physics/плотность/дальность не менялись.
Это настройка внешнего QA,не production-миграция GPU NPC и не новая схема меша.

Matched whole-frame full/native/full,7с/фаза,GPU timers OFF,native2560×1440,FOV70:
- Near10,624/10,485/10,703мс;wide10,810/10,685/10,823мс,≈1–2% gain.
- Повтор full/native/…/full/native:near baseline10,917→10,626мс,wide10,786→10,586мс,
  ≈2–3%. Эти сравнения меняли только GPU batch bias;native crossfade ещё full-index.
  Итоговая сессия дополнительно возвращает исходный native fallback bias;её route
  проверяет корректность отдельно,не приписывает ей процент от другого запуска.
- Реальная разница visible primitives в первом сравнении≈24,6тыс при≈13,5–15млн
  примитивов проходов. Наличие многих уровней LOD не означает дешёвую всю геометрию.

Проверен bounded pooled spatial MultiMesh на8/16/32м,без нового shader/поз/mesh data.
32ordinary перегруппировывались в13/6/3ячейки;исходные материалы/palette/face VERTEX_ID
и native0,18с fallback сохранены. Frozen1440p/TAAoff grouping-only кадры near/wide
совпали побитно:разбиение не удаляло видимых NPC. Однако matched whole frame хуже:
8м near10,89→11,07/wide11,10→12,02мс;16м near11,13/wide10,89;
32м near11,36/wide10,71мс против native common≈10,63/10,59мс в том же повторе.
Visible draws wide1052→1237/1126 для16/32м;binding≈0,18→0,23мс.
GPU-only выгода8м wide≈8,27→7,21мс не перекрыла CPU стоимость;это отклонённая проба.
Spatial код удалён из действующего QA и сохранён только в evidence. Возврат — другой
измеренный размер/размещение толпы или доказанный culling bottleneck;эти же размеры
на тех же32NPC без новой причины не повторять. Не внедрять «больше групп» по одному GPU timer.

Итоговый native route:source/batch bias1,21mesh семиimportant NPC прежние плюс нетронутый
player;near40/near70/wide70 frozen PNG просмотрены. Mean absolute RGB разница с full
≈0,0005/0,012/0,00008 из255;это не критерий качества движущейся TAA картинки.
Native1440p npc_in_view/camera_away/wide_view завершены;движение/возврат/GPU diagnostic
первого прохода прерваны focus_lost и не принимаются. Повторены только эти три фазы:
все complete,14м движения,fallen0/16crates/39NPC/8important/0game saves,errors0.
Контрольный маршрут (не matched с другим запуском):near≈99,3/wide≈88,9/move≈70,7FPS,
p99≈14,27/18,55/26,00мс;120FPS OPEN. Manual launcher22source hashes согласованы,
временный spatial manager восстановлен побитно. Ручной вид/ощущение остаются OPEN.
Temporal path проверен следующим срезом;полная ручная TAA/art-приёмка остаётся OPEN.
Evidence:`C:/Users/novos/Documents/Codex/2026-11-03/ember-gpu-npc-lod/`:
`native-ab/`,`spatial-ab/`,`large-cells/`,`analysis.json`,`prototype/`,`native-route/`.

**Пункт3 — temporal history GPU NPC03.11:основной fallback-дефект исправлен вQA;ручной вид OPEN.**
Stock4.7.2 уже вычисляет предыдущую позу с предыдущими MultiMesh custom data:
[Forward+ vertex shader](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl),
[MultiMesh history](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/storage_rd/mesh_storage.cpp).
У baked path bone palette неизменна,phase/blink/fallback передаются INSTANCE_CUSTOM;
вторая собственная история поз/движок fork не нужны. Mutable live-palette diagnostic
не имеет истории самой texture и не считается принятым temporal path;панель использует baked.

Воспроизведён дефект:на native crossfade0,18с GPU-вершины схлопывались вVERTEX0;
при возврате previous position оставалась в этой точке,даже если NPC не двигался.
Малый native Forward+ probe использует настоящий palette.adapt,skin attributes,
Compositor readback velocity через compute→storage buffer. Native velocity texture
не разрешает прямой texture_get_data;инструмент не меняет render buffers игры.
Still/settled motion0,реальные pose/transform шаги по9px;hidden→visible давал31,85px.
Regression на старом capture RED,с исправлением GREEN:возврат0px,настоящие шаги9px.

Текущий QA adapter сохраняет deformed vertices и передаёт flat hidden flag вfragment.
Для двух существующих toon/outline shaders поднимает уже используемый alpha-scissor
cutoff у скрытых instances. Исходные uniforms/textures/skin/face/LOD/visible cohort прежние.
Прямой discard сравнивался первым:его matched near показал≈+0,24мс;он сохранён
только в evidence. Выбран прежний alpha-scissor path;прямое превосходство двух
кандидатов друг над другом не измерялось. Новых production classes/Resource/renderer нет.

Dense32ordinary+8important/native1440p/TAAON:контролируемый неподвижный возврат
с прежним shader давал max178,42px/64904pixels>1px;alpha-scissor max3,22px/142pixels>1px.
Остаток>2px —33pixels в7×11px области около лица,не массовая история всех мешей;
это открытая визуальная граница,а не доказательство полного отсутствия TAA ghosting.
Camera sweep/PNG просмотрены;32ordinary продолжают6clips/native crossfade,8important full.

Matched whole-frame old/fixed/old,7с/фаза,GPU timers/readback OFF вtiming intervals:
near mean10,255/10,354/10,118мс;wide10,648/10,943/10,932мс.
Середина относительно двух baseline≈+0,17/+0,15мс (≈1,6/1,4%),ускорение не заявляется.
Movement14м/return/fallen0/39NPC/16crates/0game saves/errors0 PASS;mean movement≈12,96мс,
p99≈26,71мс. Это исправление temporal correctness,120FPS остаётся OPEN.
Ручной launcher использует alpha-scissor candidate;полная art/TAA-приёмка и перенос
GPU NPC наmain остаются OPEN. Повтор six-clip skin parity без изменения данных не нужен.
Evidence:`C:/Users/novos/Documents/Codex/2026-11-03/ember-gpu-npc-temporal/`:
`probe-before/`,`probe-alpha/`,`verify_probe.py`,`scene-alpha/`,`verification.json`.

**Пункт4 — Dylearn/FlexibleToon04.11:вариантБ принят для дальнейшего ручного QA.**
Изучен [Dylearn demo](https://github.com/DylearnDev/Dylearn-3D-Pixel-Art-Grass-Demo/tree/7486b9b99834d95c4287cc917971b3d74ba37d8c)
на commit7486b9b. Это30тыс видимых QuadMesh0,2×0,3м вSubViewport640×360,
не native1440p система streaming/LOD. ВGrass shader есть64-character loop вvertex,
noise textures/rotation/billboard/fake perspective/clouds;весь набор не переносился.
Код MIT;assets отдельно CC BY4.0/условия LICENSE,Waterfowl logo исключён. В выбранном
ручном варианте используются только идеи/адаптация кода с notice,без чужих textures/models.
Видео по прямому URL не прочитано;выводы основаны на самом demo/scene/shaders,не просмотре ролика.

Ограниченный A/B/C на нашей исходной посадке210975roots×8potential blades:
А — текущая геометрия3/2/1tri и полный прежний свет;Б — та же геометрия/ветер/ground pigment,
root LIGHT_VERTEX/world-up normal и hybrid toon по мотивам Dylearn/FlexibleToon;
В — cylindrical cards с demo grassleaf,тот же GPU culling/LOD classification/roots.
Б не копирует яркую палитру,clouds/stepped5Hz/64-character loop и не умножает ALBEDO
вlight повторно:Godot уже умножает diffuse на albedo. Глобальный material owner не менялся.
В использует2/2/2tri;его ширина≈1,03005×базовой по alpha coverage30,9% и средней
проекции травинки. Это приблизительное покрытие,не pixel/силуэт parity двух форм.
Ни плотность,ни дистанция/fade,ни разрешение не уменьшались. Цветы/высокая срезаемая трава прежние.

Native2560×1440/FOV40+70/TAAON live,windON/39NPC/8important. Frozen PNG для сравнения
сняты отдельно сtime_scale0/TAAOFF;selected blade/LOD counts всех трёх вариантов совпали.
Первый wide20м/polar70/yaw0,35 оказался внутри tree crown:его timing не принимает
широкий вид травы. Исходники сохранены с этой пометкой. Только wide повторён с yaw3,09889,
тем же20м/FOV70/polar70/всеми деревьями;camera вне AABB крон,PNG показывает открытый луг.
Это исправление QA-ракурса,не новый auto-obstruction камеры вигре. Старые wide числа
без проверки кадра не доказывают цену открытого обзора мира.

Matched7с whole frame А/Б/В/А,render timersOFF;отдельные3с GPU intervals:
- Near:А mean10,463/10,588мс,Б10,259 (≈−2,54%),В10,216 (≈−2,95%).
  GPU А8,772/Б7,827/В8,178мс. P99 Б14,075 против А13,628/13,877мс:tails не улучшились.
- Clear wide:А10,989/11,096,Б10,774 (≈−2,43%),В10,944 (≈−0,89%).
  GPU А8,865/Б8,043/В8,428мс. P99 Б14,184 против А14,393/14,698мс.
  Б экономит≈0,82–0,95мс GPU,но только≈0,27мс полного кадра;120FPS остаётся OPEN.
Б выбран автором через сравнение04.11 именно для дальнейшего QA;это не art-приёмка всей карты.

Итоговый ManualGrass.make_material использует прежний renderer/state и один output buffer,
wind controls/геометрия/roots прежние. Временный card State из обычного запуска убран;
эксперимент и лицензированная texture сохранены только в QA evidence. Shader logic
итогового Б совпала с измеренным после удаления comments/unused sampler/whitespace.
Native integration route6phases/14м/move-return/native1440p/errors0/0game saves/8important PASS.
Wide smoke использует открытый QA yaw;ручной default yaw при отдалении может попасть
вкрону,ПКМ меняет обзор. Auto-fade/обход камеры не добавлялся. 120FPS/production/main,
подгрузка новых GPU участков/выгрузка/возврат/полная RAM и ручная moving art/TAA OPEN.
Evidence:`C:/Users/novos/Documents/Codex/2026-11-03/ember-grass-material-ab/`:
`reference/`,`scene-ab/`,`clear-wide/`,`analysis.json`,`comparison.png`,`adopted-route/`,`verification.json`.

**Пункт5 — GPU grass residency04.11:реализовано вQA,performance gate открыт.**
`qa_stream_grass.gd/.glsl` переиспользует исходные GrassPatch посадки и прежние3/2/1tri,
материалБ/ветер/GPU culling/indirect. Map.detail_scatter_changed сообщает публикацию,
смену облика и release; transient render override скрывает native только после GPU handoff.
Подготовка CPU bytes — WorkerThreadPool;≤2jobs/готовых payloads,≤64KiB upload/frame,
один publishing;generation tokens отклоняют stale CPU/render results. Смена FOV не
переупаковывает готовые roots. Освобождённые диапазоны/тайлы переиспользуются.
Material fade anchor/range/enable теперь следуют живому projection вместе с compute:
первый вариант загружал новые roots,но shader скрывал их около старого центра — отклонён.

Найден отдельный native starvation:40near retries могут исчерпать frame budget до
готового дальнего владельца единственного material digest или двух cache-read slots.
Shared DetailPreparation теперь приоритетно доставляет готовый bounded result;
budget/лимиты/отмена прежние. Dense regression RED→GREEN;async material/cache cancellation,
teardown/transport и native grass visibility/clean resident PASS. Editor использует тот же
owner;его ручная нагрузочная/визуальная приёмка этим gameplay run не закрывается.

Итоговый native1440p/FOV40→70 маршрут:detach/reentry/east80м/return/rapid anchors,
227новых GPU patches,845commits/641drops,overflow0/stale reject1/missing_ready0,
0game saves/fallen0/8important. Selected blades start517559/east531624;PNG вновой области
показывает густую траву. UI renderer selection/reset API иnative panel PNG PASS.
Main adapter tick max1,397мс,CPU worker0,807мс,RD upload0,013мс;это отдельные максимумы,
не сумма кадра. Whole frame east mean12,132/p9917,698мс,return10,462/p9914,712 —120FPS OPEN.
Source preparation после80м40,113с/return26,789с/rapid19,557с **слишком медленная**;
результат не объявляет быстрый teleport или отсутствие видимого pop-in. Первый timeout240с
и предшествующие пустые PNG отвергнуты;ошибки диагностического IPC отдельно отfinal run.

Пул524288roots/1024tiles:output256MiB+roots16MiB+classification16MiB остаются выделены;
release логический,не возврат VRAM драйверу. Это больше fixed-start output103MiB;
weak-PC/полная память OPEN. Ordinary upright look0 поддержан;иной palette/source остаётся native.
Цветы пока fixed-start HLOD,высокая срезаемая трава/её тени прежние. Main GPU migration,
ручной art/motion/TAA/стыки иобщий120FPS OPEN. Архив/launcher manifest27files обновлены.
Evidence:`C:/Users/novos/Documents/Codex/2026-11-04/ember-grass-streaming/verification.json`,
`accepted-route/`,`accepted-route.log`,`fairness-red.log`,`fairness-green.log`,`panel.png`.

**Текущий ручной выбор травы04.11 — отдельный QA-инструмент,не новый FPS PASS.**
Автор разрешил менять количество пучков,чтобы сравнить более редкую широкую траву.
F3→«Трава»:GPU blades3/2/1tri,прежний8tri tuft иcylindrical camera-facing alpha-scissor card;
количество0–100%,ширина0,25–6×,высота0,25–3×,кучность0–100% иразмер пятен0,5–8м.
`qa_grass_study` расширяет прежний incremental adapter:stable root selection иVoronoi-пятна,
без XZ-переноса корней/пересборки земли/повторного upload. Снижение количества — ожидаемая
доля по пространству,не точное число вкаждом кадре;при100% все корни сохранены.
Три формы используют один output pool/один MultiMesh с9surface commands;активны3LOD
для blades/cards,1дляпучков. Переключение не меняет mesh/command RID и не выделяет второй output.
Это цена QA-сравнения,не прежний matched performance baseline и не art-приёмка формы.
Сброс только травы/общий сброс иSave slice сохраняют временные значения вsnapshot;
основная карта/Source не меняются. Native renderer во«Дальности» обходит эти регуляторы.
Card texture `grassleaf` byDylearn,CC BY4.0;original license/ATTRIBUTION входят в32file manifest.
Один короткий native1440p functional smoke(60FPS cap только probe):три формы видимы,
UI signals/25% count/ширина3× при высоте1×/reset/no root reupload/8important PASS;
PNG формы/панели просмотрены. Длинный stress иновыйFPS gain не заявлены по просьбе автора.
Открыты авторский выбор,верхний/движущийся вид/ветер/TAA/стыки ипроизводительность после выбора.
Высокая срезаемая трава/цветы прежние;смешивание форм отложено до выбора отдельных.
Evidence:`C:/Users/novos/Documents/Codex/2026-11-04/ember-grass-controls/verification.json`;
`smoke.log`,`smoke/style0.png`…`style2.png`,`smoke/panel.png`. Launcher тот же.
Ручной запуск после выдачи автору завершалсядо MANUAL_QA_READY:collision-aware route
не найден,base fixture явно quit1. Это не доказанный GPU/device crash и не3рисуемых луга.
Manual needs_automatic_route=false пропускает лишний autowalk gate;остальные fixtures defaulttrue.
Перед готовностью есть QA loading screen;GPU profiler теперьoff поумолчанию,включается явно.
Targeted survival принудительно запрещает строить autowalk route,переключает0/1/2/0 ичитает
все9indirect instance counts:унеактивных форм0;общие roots/output переиспользуются.
20с ready/native1440p/FOV70/near:mean10,184мс(≈98FPS),p9913,940/max31,583;
0errors/0game saves/fallen0. Это стационарное наблюдение,не120FPS/manual motion acceptance.
Оригинальный launcher отдельно доведён доMANUAL_QA_READY,32hash manifest обновлён.
Evidence:`C:/Users/novos/Documents/Codex/2026-11-04/ember-manual-launch-fix/verification.json`,
user-godot.log/accepted.log/live-launch.json. Внутренний rejected-initialize log — отсутствовавший
super._initialize при добавлении загрузочного экрана;исправлен до новой выдачи автору.
После выбора вернуться кпункту5(source preparation40с/return27с),не повторять materialAB.

**Текущий план аудита 04.11: плотность GPU-травы и накопление работы при поворотах камеры.**
04.11 автор согласовал диагностику и исправление измеренного CPU shadow-context.
Технический результат/открытая ручная приёмка — ниже;перенос GPU-пути QA на main не согласован.
Ранее выполненные QA-срезы1–5 и отвергнутые варианты описаны выше; повторять их без причины не нужно.

**Наблюдения автора, ещё не отдельный контролируемый замер.** В покое около140FPS;
при последовательных поворотах без перемещения FPS постепенно снижается, иногда до60,
Draw Calls растут; после остановки камеры FPS постепенно восстанавливается. При почти нулевой
плотности один из счётчиков пучков/травинок заметно не уменьшался. Сначала установить, какой
именно счётчик наблюдался и что он обозначает; его неисправность не считать доказанной.
Предпочтительный художественный вариант автора сохраняется: снижение плотности для диагностической
матрицы — временный контроль, не способ получить performance PASS ухудшением картинки.

**Подтверждено чтением действующего кода; стоимость в кадре ещё не приписана этим механизмам.**
- QA `grass_amount` через ManualSession.apply_settings→Study.configure задаёт GPU-отбор;
  это отдельный регулятор от авторских density_cells/параметров посадки GrassPatch.
  Настройки QA сохраняются в snapshot JSON, но не меняют авторский Resource/карту.
- Надпись «GPU: готовых пучков» получает meadow.source_count: это подключённые исходные
  корни, а не отобранные после плотности или видимые травинки. Неизменность этого числа
  сама по себе допустима; пока не установлено, именно ли его имел в виду автор.
- Camera payload меняется при вращении: VegetationGrass._process заново вызывает compute.
  StudyState.update задаёт диапазоны dispatch_roots и dispatch_roots*blades независимо от
  процента отбора, включая0%; фильтрация уменьшает результат, но не эти размеры запуска.
  Отсутствие отдельного раннего пути0% подтверждено кодом; выигрыш его изменения не измерен.
- В QA NPC qa_npc_six_visual._process таймер перехода уменьшается на dt лишь при обновлении
  позы; при редком LOD переход растягивается. Это найденный дефект логики, не доказательство,
  что именно он вызывает постепенную просадку при вращении. Исправление ещё не выполнялось.
- Карточки имеют одинаковую2tri геометрию всех3LOD, пучки используют один уровень;
  ползунок качества не равен дальности исчезновения. Цветочный HLOD охватывает стартовый cohort.

**Гипотезы, которые надо развести измерением.** Полный GPU-обход кандидатов/пустых диапазонов;
изменение camera-derived residency и churn тайлов; накопление готовых/устаревших задач,
публикаций и render-thread команд; массовые обновления shadow proxies; смена видимой геометрии,
альфа-overdraw/материалы; растянутые native NPC transitions; ошибки или запаздывание телеметрии.
Рост Draw Calls при другом ракурсе может быть обычным изменением видимости. Накопление и утечка
пока не доказаны. Системная ошибка организации данных допустима как гипотеза; фундаментальная
замена земли/renderer/LOD или обвинение движка требуют измеренных оснований.

**Минимальная диагностика — до исправлений.**
1. Проследить оба входа плотности: editor/native параметр → Resource/scene serialization
   и save/reopen → CPU scatter; QA-регулятор → session settings/snapshot JSON → отбор GPU.
   Затем проверить цепь uniforms/input buffers → classification/compaction → output/indirect
   commands → отрисовка. Указать, где значение должно действовать и где не обязано менять данные.
2. Составить словарь существующих счётчиков с owner/единицами/временем обновления:
   исходные корни; потенциальные травинки выбранной формы; выделенная ёмкость и занятые
   диапазоны GPU; отобранные по density/frustum/distance экземпляры поLOD; число экземпляров
   и треугольников в фактических indirect commands. Отделить это от пиксельной видимости,
   engine/driver primitive counters и суммарных проходов/теней. Проверить UI binding,
   актуальность frame/generation и обновление после density/style/LOD/camera changes.
3. На одной готовой сцене выполнить матрицу100/50/10/0% с одинаковыми Source/seed/камерой,
   дальностью, шириной, высотой, группировкой, светом и сопоставимым состоянием NPC.
   Для каждого значения записать selected counts поLOD и active indirect commands,
   размеры GPU dispatch/объём чтения и записи, Draw Calls visible/shadow, CPU/GPU и wall
   median/p95/p99/max, память. GPU-профиль с его overhead отделить от чистого полного кадра.
   Проверить масштабирование работы, не требуя линейного изменения FPS или Draw Calls:
   batching может сохранять число вызовов при уменьшении числа экземпляров.
4. Отдельный gate0%: выбранная форма визуально отсутствует, старые indirect counts очищены,
   не осталось stale draw данных; определить, какой GPU/CPU обход всё ещё выполняется и зачем.
   Цветы, высокая срезаемая/исходная трава и другие облики учитывать раздельно — их присутствие
   не означает отказ0% выбранной формы. Проверить возврат0→100 без потери данных/новой посадки.
5. Отдельно от ходьбы: закрепить персонажа и выбранный автором preset, после готовности
   пройти «покой → последовательные одинаковые повороты → покой», вернуть исходный ракурс.
   Измерять на одной временной шкале CPU/GPU/wall, Draw Calls, GPU recull и dispatch ranges,
   active/resident/pending tiles и корни, uploads/rebuilds/commits/drops, shadow-context/proxy
   updates. Учесть, что Map object-profile начинается после shadow-context и не включает его.
6. Для terrain/grass/objects/flowers/NPC/shadows различать длину очереди, bytes, возраст самой
   старой задачи, ready/in-flight/stale/cancelled, requested/published generations; время
   CPU подготовки, main publication, render-thread submission и GPU выполнения. Проверить
   освобождение Nodes/RIDs/диапазонов, повторные подписки и незавершённую работу между поворотами.
   После остановки отследить время восстановления FPS и опустошения очередей/стабилизации памяти;
   истечение ограниченного ожидания фиксировать как незавершённую работу, не PASS.
7. Проверить повторы на неизменных Source/revision/material/seed/настройках: не инвалидирует ли
   камера посадку/кэш/тайлы, не публикуется ли тот же результат снова, не обходятся ли пустые
   слоты и не накапливаются ли устаревшие запросы. При одинаковом состоянии мира и возврате
   к прежнему ракурсу сравнить размеры активного набора/очередей/ресурсов с началом.
   Повторять/расширять маршрут только при конкретной неоднозначности или найденном дефекте.

**Возможные исправления — только после результата и отдельного согласования.**
- Неверная семантика/обновление счётчика → исправить подпись, источник или frame freshness;
  не менять значение декоративно ради ожидаемого уменьшения.
- Ненужный полный обход → ранний0% со сбросом старых commands, активные диапазоны/compact
  selected data, разделение обновлений camera visibility и неизменной посадки. Измерить цену
  compaction и переключения LOD; сохранить покрытие и устойчивость силуэта.
- Churn/очереди → coalescing по owner/generation, отмена stale, bounded admission/publication,
  гистерезис и переиспользование существующего кэша/пула. Новую очередь для каждого типа не вводить.
- Тени/NPC → измерить отдельно и исправить конкретные обновления/таймер перехода, сохранить
  восемь важных героев, корректные тени, коллизии и анимационное время.
- Если доминирует runtime preparation текущего terrain, сравнить существующий cache/editor_surface
  с предварительно подготовленными ресурсами одного участка. Source, высота и physics остаются
  общими; учитывать размер пакета, cold/warm load, return и локальную инвалидацию. Миграция
  на второй редактор/независимую карту/renderer не согласована.

**Остальная очередь сохраняется:** точный billboard/UV-приём Dylearn вместо текущего cylindrical
эксперимента (субтитры ещё не получены), проверка минимальных материалов травы/листвы без слепого
переноса всех возможностей demo; честные LOD/дальность; lifecycle/GPU-путь цветов; медленная
source preparation40с после80м/27с return; память, moving TAA/art, weak-PC и общий120FPS.
Предыдущие полезные shared materials/native LOD/bounded workers не убирать без сопоставимого A/B.

**Точка возврата.** В блоках 1–2 мира без NPC приоритет автора — поле травы при ускоренном беге с Shift и смене ракурса. Ожидание телепорта допустимо. Приёмка движения требует одновременно готовой растительности впереди игрока и устойчивого кадра. Толпа возвращается в блоке 3.

### Плавность мира до добавления NPC

**Результат отдельного маршрута 04.11.** На внешней копии полигона 576 м работал только игрок. Из дерева сцены до симуляции исключена зона кабана, спутники и 39 тестовых NPC не создавались. Сохранены WorldCanvas, игрок с физикой, 859 добавленных props, 4 дома, 16 ящиков, 8 фонарей, урожай, 25 848 участков растительности, GPU grass, цветы и исходные тени. Единственный CharacterBody3D — Player, спутников 0, плотность 100%. Система воды активна, но в этом сухом fixture нет wet sections. Официальный Godot 4.7.2, Forward+/Jolt, RTX5070, fullscreen 2560×1440, scale1. До передачи управления прошло около 48 с вместе с построением и проверками QA. Это запуск процесса с существующим дисковым кэшем.

- При FOV40 покой / медленный поворот / резкий поворот дали p99 6,58 / 6,70 / 6,90 мс. Реальная ходьба по 12 м туда и обратно дала p99 8,46 / 8,74 мс.
- При FOV70 те же три фазы дали p99 7,21 / 8,11 / 9,39 мс. Реальный ускоренный проход на 32 м туда и обратно дал p99 13,40 / 13,33 мс, max 36,55 / 18,55 мс, доля кадров выше бюджета 32,3% / 39,1%. Зарегистрированы настоящие перемещения, модификаторы скорости и готовность пола в конце каждого пути. Скорость и FOV в проходах менялись вместе. Отдельный GPU probe резкого поворота дал p99 5,17 мс при FOV40 и 8,41 мс при FOV70.
- В исходном QA вызовы подготовки назначения во время ожидания не обеспечили пол в новой области за 20 с. Игрок туда не переносился. Последующий запрос исходной позиции проверял уже занятую область. Пики во время такого опроса включают цену повторной команды подготовки.
- В независимом QA сравнении одна штатная команда подготовки не обеспечила пол в том же назначении за 4 с. Единственное изменение в terrain owner для варианта сравнения — удерживать точку назначения среди источников подготовки во время пересчёта списка. В той же сцене и точке на 80 м восточнее коллизия подтвердилась запросом к физическому миру через 105 мс, передача управления после шага физики — через 119 мс. Для настоящего возврата получено 8 и 14 мс. При изменении назначения предыдущее действительно удерживалось и затем вышло из списка. Новая опора была готова через 109 мс после замены запроса. Во всех трёх переносах выборочные проверки высоты после переноса не показали провала.
- Критерий наличия ближних буферов и завершения их обновления достигнут через 5,70 с при первом переносе, 4,61 с при возврате и 17,23 с при смене назначения (от первого запроса). Это прокси покрытия с выборкой раз в 250 мс. Время первого полностью нарисованного изображения и отсутствие видимых дыр требуют отдельного подтверждения. Во время первого перехода источник GPU-травы имел ноль готовых пучков суммарно 1,74 с, при возврате 0,32 с. Возможен показ штатного представления в промежутке. Пики кадра 41–48 мс остаются. Отмена проверена для удержания физической области, поздняя публикация всех типов объектов отдельно не доказана.

**Первый отрисованный кадр телепорта, QA 04.11.** На том же полигоне без NPC сравнили перенос на 80 м, возврат и замену назначения. Исходный вид сохранялся до подтверждения пола физическим лучом и готовности ближнего покрытия. Для контроля только пола ожидание до переноса на восток составило 0,12 с, первый кадр показал голую землю, а буферы полного ближнего покрытия собрались ещё через 5,18 с. При полной подготовке двух зон все 145 нужных GPU-участков назначения были готовы до переноса, но даже восьмой снятый кадр оставался голым. Обновление камеры, области видимости и параметров растений перед первой отрисовкой показало траву и цветы сразу. Длительность кадров измеряли отдельно от захвата изображений.

- Полная сборка соседней земли перед использованием размещения растений задерживала перенос на 8,10 / 8,41 / 9,01 с соответственно. Когда валидные позиции разрешили читать до сборки земли вне площадки под игроком, получили 3,42 / 2,82 / 3,62 с. Без готового пола перенос не выполнялся. Зафиксированы 177 / 186 / 179 ранних попаданий в кэш. Отсутствие записи в кэше в этих запусках не воспроизводилось.
- При первом переносе ближайшее покрытие на старом месте сохранялось по выборке. Пик составил около 360 тыс. корней при одновременной подготовке обеих зон. VRAM в окне после переноса достигла 2227 MiB против 2038 MiB при подготовке только пола. После замены запроса отменённая точка вышла из удержания, переполнений пула не зарегистрировано.
- В варианте с ранним чтением p99 после переноса составил 15,30 / 12,65 / 12,92 мс, max 86,52 / 80,57 / 86,51 мс. Один бюджет кадра — 8,33 мс. Прототип остаётся внешним. Приёмка требует устранить скачок, проверить промах кэша, быстрый проход через стыки и ручной вид на основной карте.

Измерения и изображения находятся в `C:/Users/novos/Documents/Codex/2026-11-04/` в каталогах `ember-cover-ab`, `ember-cover-handoff` и `ember-cover-cache`. Чистые серии содержат покадровый `world-alone.json`, отдельные запуски со снимками — `east_draw1.png` и `east_settled.png`. Сравнение изображений — `ember-cover-cache/teleport-comparison.jpg`.

Отдельная инструментированная трасса первого переноса при фактическом FOV40 находится в `ember-cover-trace/warm-clean/first-frame-trace.json`. В первом интервале 90,94 мс суммарно 53,68 мс заняли 538 последовательных вызовов `EmberGrassPatch._process`. Самый долгий одиночный вызов занял 0,39 мс. Обработчик земли в этом интервале занял 1,4 мс. Времена вложенных обработчиков нельзя складывать с общим временем кадра. Замеры вращения на месте и широкого движения относятся к отдельному маршруту.

**Проверка причины.** В `ember-cover-release` внешняя проба ограничила освобождение ушедших участков растительности примерно 1,1 мс работы за кадр. Остальные настройки и плотность совпадали с вариантом раннего чтения кэша. В серии без захвата изображений первые кадры заняли 28,92 / 14,62 / 30,94 мс вместо 86,52 / 80,57 / 86,51 мс. Худшие кадры за всё окно после переноса составили 36,63 / 36,00 / 36,62 мс, p99 — 13,45 / 11,42 / 12,59 мс. Управление передано через 3,23 / 2,50 / 3,82 с. Освобождены 268 / 270 / 268 участков, в конце ни один проверенный участок старого вида не удерживался за радиусом. Переполнений и ошибок стенда нет. Готовность всех буферов по фактической камере после первого переноса отмечена через 0,86 с против 0,41 с до ограничения. В порционной пробе за перенос накопилось 7–8 тысяч отложенных попыток. Для интеграции проверить очередь однократной постановки с повторной проверкой актуальности, отмену при быстром возврате и промах кэша. Остаточный max приходится на кадр через 0,49–0,72 с после переноса. Отнесение его к конкретной подсистеме требует отдельной трассы.

Evidence — `C:/Users/novos/Documents/Codex/2026-11-04/ember-world-alone/`, `accepted/summary.json`, `pin/summary.json`, raw `world-alone.json`, `Run.ps1`, `Run-Pin.ps1`. Первая сборка стенда выявила кабана и спутника, следующая остановилась до построения сцены из-за неверного базового класса тестового скрипта. В результаты вошли два исправленных запуска с настоящим WorldCanvas. Временное изменение QA projection возвращено после сравнения. Общий gate мира без NPC открыт.

**Поздний пик переноса и быстрый ход, QA 04.11.** Тот же игрок прошёл по 32 м туда и обратно при фактическом FOV70 после двух переносов при FOV40. В серии без трассировки поздний max в окне 0,3–1,1 с после переноса составил 36,09 мс на восток и 33,69 мс на возврате. В диагностической серии в двух отдельных кадрах работа региона земли заняла 30,10 и 24,11 мс. Другой кадр длиной 47,09 мс включал около 34 мс между сигналами начала и конца отрисовки. Эта длительность не идентифицирует виновника внутри движка. [Границы сигналов RenderingServer](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-signal-frame-post-draw).

- Проба освобождала до четырёх мелких участков за одно обновление региона. Для 560 выгруженных участков проверены маска замещающей земли и отсутствие запроса на удержание участка, ошибок 0. Чистый поздний max стал 41,66 / 32,65 мс, при быстром движении наружу max остался 34,16 мс. Это основание оставить фиксированную порцию экспериментом. Проверка маски не заменяет визуальную приёмку мокрых стыков.
- В кадре быстрого хода длиной 34,33 мс обработчик карты занял 27,83 мс, обработчик земли 0,08 мс. Более узкая трасса поймала переход `vox_coastal_house` к ближней геометрии за 26,85 мс, тот же путь после телепорта занял 26,99 мс. Предварительное получение штатной поверхности для пяти домов занимало 24,89–25,64 мс на экземпляр. В контрольной серии без трассировки на 30–31-м метре быстрого прохода худший кадр с подготовленными домами занял 11,53 мс против 34,16 мс при той же организации земли. Максимум всего прохода остался 28,85 мс в другой точке. На конец маршрута формы коллизий домов сохранились, зарегистрированы три обращения к подготовленной геометрии.

**Отдельный запуск с сохранённой геометрией.** Внешний QA сохранил штатный ближний меш дома в один Godot Resource размером 268 377 байт. После повторной загрузки сверены массивы поверхностей и метаданные данных с результатом штатной сборки для каждого из пяти домов. В новом процессе тот же файл подключён ко всем пяти за 45,6 мс вместе с проверкой отпечатков входов, файла и поверхности. Внутри измеренного маршрута произошли три обращения к готовой поверхности, формы физики сохранили исходные экземпляры. Лимит выгрузки земли в четыре участка в этом запуске снят. На 30–31-м метре max составил 16,24 мс против исходных 34,07 мс. За весь проход получен отдельный кадр 84,04 мс на 2,64-м метре. После телепорта max 31,26 / 36,61 мс. Замены общей системы объектов и принятой интеграции в main нет. Перед переносом требуется владелец пересборки производного ресурса при изменении источника или материала и проверка на основной карте. Godot поддерживает совместное использование загруженного меша несколькими узлами. [Godot Resources](https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html).

В повторном запуске того же файла пик на 30–31-м метре составил 11,92 мс, а на 2–3-м метре — 12,63 мс. Единичные 84,04 мс на втором метре не воспроизвелись, их причина открыта. При повторе максимумы за быстрый проход и обратный путь составили 20,01 / 20,64 мс, после переноса и возврата — 30,43 / 40,45 мс. Прямой проход в обоих запусках превысил 8,33 мс примерно в 37–38% кадров.

Сырые ряды, записи по владельцам и параметры запуска находятся в `C:/Users/novos/Documents/Codex/2026-11-04/` в каталогах `ember-residual`, `ember-residual-batch`, `ember-residual-house` и `ember-residual-shared`. В последнем лежат `prepared-house.res`, манифест входов и серии `bake`, `clean`, `repeat`. Чистые серии записаны отдельно от трасс. Прогоны охватывают сухой полигон с существующим кэшем. Точный пользовательский сценарий с вращением камеры на месте остаётся отдельной проверкой.

**Выгрузка земли, ориентиры Zelda и Genshin.** Для визуальной непрерывности мира автор выбрал ориентиры *Tears of the Kingdom* и *Genshin Impact*. Nintendo NERD описывает непрерывный LOD для глубин, пещер, колодцев и небесных островов. Для Ember проверяем свой переход: замещающая земля должна быть видна до снятия ближнего участка. [Nintendo NERD, terrain rendering](https://www.nerd.nintendo.com/2024/06/24/TOTK1.html).

Технический директор miHoYo в докладе о консольном рендере Genshin описал предварительное сохранение данных сцены для отражений и последовательное обновление одной пробы на протяжении нескольких кадров. Переносимый принцип — отделять подготовленные данные от работы, которую придётся выполнить во время игры, и измерять всю последовательность. В Ember этот принцип испытан для освобождения земли. Внутренний алгоритм её выгрузки в Genshin по этому докладу определить нельзя. [Unity Japan / miHoYo, слайды 56–57](https://image.docswell.com/s/UnityJapan/KWRPQ5-210617-unity-dojo20211mihoyozhenzhongyi).

- На сухом полигоне 576 м, с готовым домом, при native 1440p / FOV40 и переносе на 80 м в позднем кадре снятие физической формы суммарно заняло 0,21 / 0,12 мс на первом переносе и возврате. Удаление записей участков заняло 22,14 / 22,83 мс. В отдельной трассе самый долгий вызов удаления одного набора CPU-массивов `_editor_surface_layouts` занял 21,87 / 22,45 мс. Эти массивы также нужны для альтернативных видов земли.
- Проба с одним фоновым заданием для освобождения CPU-массивов почти обнулила время их удаления на основном потоке, но в чистом прогоне поздний max остался 29,34 / 35,56 мс против 29,93 / 34,71 мс у базы. В инструментированном первом переносе 22,50 мс пришлись уже на снятие физических форм. Эти интервалы показывают, в каком вызове проявилась задержка. Причина остановки внутри движка пока не установлена.
- Вторая проба сразу убирает запись из активной карты и освобождает старые CPU-массивы на главном потоке по одному участку за кадр. Очередь ограничена 320 записями. Измерение продолжается до её опустошения. Проверены первое посещение, возврат и смена назначения. Каждый раз перед снятием мелкой земли проверялись открытая маска замещающей поверхности и отсутствие физического запроса на удержание. Это проверка данных сухого участка, визуальная приёмка на мокрых стыках открыта.

В двух чистых запусках с очисткой по одному участку поздний max (0,3–1,1 с после переноса) составил 14,36 / 13,60 мс на восток и 20,94 / 22,37 мс при возврате. За три переноса зарегистрировано 858 выгрузок с подтверждённой маской, включая случай со сменой назначения. Пик очереди 281, к концу каждой фазы она пуста. Плата за снижение пика видна в одинаковом двухсекундном окне возврата: доля кадров дольше 8,33 мс выросла с 14,1% до 44,1 / 46,2%. На быстром проходе при FOV70 фактический путь 32 м туда и обратно дал p99 13,66 / 14,90 мс и max 16,61 / 22,85 мс. Физическая поверхность подтвердилась на обоих концах.

Третья проба освобождает до одного набора массивов после подготовки земли, только если от её текущего бюджета остаётся больше 0,35 мс. В первом чистом прогоне поздний max составил 13,92 / 13,02 / 13,19 мс для востока, возврата и замены назначения. В первые две секунды возврата доля кадров вне бюджета составила 11,5%. При первом переносе за это же окно получено 27,6% против исходных 24,5%, первый кадр занял 36,18 мс. Очередь достигла 290 из 320 записей, полностью освободилась, все 858 проверок выгрузки прошли. Худший кадр и ожидание управления учитываются отдельно от позднего пика.

В независимом повторе этой пробы поздний max на переносе и возврате составил 13,78 / 14,77 мс. За первые две секунды вне бюджета оказались 23,4 / 14,3% кадров, против 24,5 / 14,1% у базы. Управление вернулось через 3,19 / 2,61 с. Быстрый проход на 32 м при FOV70 дал p99 13,48 / 14,14 мс и max 17,91 / 18,32 мс. Пол подтвердился в обе стороны, очередь в конце пуста. Это выигрыш в позднем рывке; стабильные 120 FPS в движении ещё не достигнуты.

Исходники опытов и сырые ряды находятся в `C:/Users/novos/Documents/Codex/2026-11-04/` в каталогах `ember-tile-retire`, `ember-tile-field`, `ember-tile-drain`, `ember-tile-paced`, `ember-tile-paced-travel`, `ember-tile-slack` и `ember-tile-slack-travel`. Инструментированные трассы и обычные запуски записаны отдельно. Результаты относятся к внешнему QA; основная карта и ручная приёмка остаются открытыми.

**Точка остановки проверки телепорта.** Автор допускает ожидание телепорта и дал приоритет обычному движению мира без NPC. В QA перенос на восток / возврат / смена назначения заняли 24,15 / 12,81 / 23,65 мс от перемещения до сигнала конца первой отрисовки, полные интервалы кадров — 28,73 / 17,82 / 24,64 мс. Перемещение и камера на востоке заняли вместе 0,02 мс, принудительное обновление области земли — ещё 2,76 мс. Между началом и концом отрисовки прошло 13,59 мс на востоке против 1,85 мс при возврате. В отдельном запуске с маркерами конкретного кадра диапазон меток GPU составил 6,13 / 5,20 / 4,74 мс. Сигнал конца отрисовки не измеряет показ на физическом дисплее. Ранняя подготовка видимости 181–183 участков не улучшила время до конца первой отрисовки, вариант не выбран. Измерения — `ember-first-edge`, `ember-first-render`, `ember-first-prefade` в каталоге QA за 04.11. [Godot RenderingServer](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-signal-frame-post-draw).

**Обычное перемещение и трава.** Автор видел, как при ускорении с Shift трава остаётся позади. Резкий поворот на месте отдельно не проверял. Первичный QA-проход на восток упёрся в препятствие на 51-м метре. Для воспроизведения выбран открытый коридор существующего полигона. Один реальный игрок пробегает 96 м вперёд и столько же обратно при FOV70, native 2560×1440, максимальная скорость 4,8 м/с. На каждом шаге выборки проверяются участки обычной травы, центры которых находятся в поле зрения камеры. Видимая нативная подмена учитывается отдельно от пустого участка. Это техническая выборка через 0,2 с, не попиксельный критерий полноты кадра.

На первом посещении открытого коридора ближняя зона до 16 м оставалась готовой. Во внешней зоне 16–24 м за прямой проход получено 63 пустых наблюдения из 2700, ближайшее на 21,7 м. В начале стоянки пустовали 9 из 30 дальних участков, затем покрытие догнало игрока. В ранее посещённом коридоре эффект мог не воспроизвестись. При вращении на месте на FOV40 и 70 в выборке пустых участков не найдено. Центр подготовки двигался всего на 0,5–0,8 м, число корней оставалось 210 975. Это не исключает рывки времени кадра.

Положение для визуального исчезновения травы использовало тот же центр, что и периодическая подготовка мира. При прямом беге он обновился около 80 раз за 20,4 с, сдвигался до 1,5 м за раз. В QA граница видимости вычислена по актуальной камере на той же плоскости, а проверка готовности участков сохранила прежнюю частоту. В прямом сравнении максимум шага видимой границы сократился примерно до 0,10 м. Плотность и дистанции 16–24 м остались прежними.

В контрольном сравнении все запуски начинали с копий одинаковых 3320 файлов размещения, для которых проверена общая контрольная сумма. Если земля уже рассчитана, исходный вариант и вариант плавного визуального фокуса не показали дыр в выборках этого маршрута. При пустом дисковом кэше земли исходный вариант дал 577 пустых наблюдений из 3578 внутри 16 м и 1299 из 2721 в кольце 16–24 м. На прямом ходе ближайший пустой участок был в 3,64 м. После остановки некоторые участки оставались пустыми в течение всей девятисекундной проверки. Упреждение на две секунды по фактической скорости с пределом 12 м использует существующую область предварительной подготовки; при Shift получается 9,6 м. При тех же начальных данных пропуски сократились до 308 из 3617 и 938 из 2738 соответственно. Проба с дополнительным ограничением выгрузки дала 299 и 924 пропуска, а рывки при остановке сохранились. Её отдельным исправлением не считать. Размер участков, плотность, ближний вид, дистанция исчезновения и физическая поверхность сохранены.

При тех же упреждении, плотности и пустом кэше земли QA получил готовые позиции из предыдущего расчёта исходных данных. Пакет содержит 3545 записей, 94 821 981 байт; покрытие проверено для этого коридора. На первом прямом проходе зарегистрировано 0 пропусков из 3600 ближних и 2724 дальних наблюдений, на обратном — 0 из 3557 и 2644. В девятисекундных остановках пропусков также нет. Изменения фокуса визуального исчезновения не превышали 0,10 м за кадр, физическая опора подтвердилась на обоих концах. При беге p99 составил 14,36 / 16,07 мс и max 22,70 / 22,13 мс. Это отдельный QA-вариант. Выпуск позиций для основной карты и проверка локальных изменений описаны ниже. Штатная проверка ключа кэша и расчёт при промахе остаются активными; именно такой промах на неподготовленном маршруте всё ещё может быть заметен.

Ручной полигон без NPC — `C:/Users/novos/Documents/Codex/2026-11-04/ember-grass-play/Start-Grass-QA.cmd`. Персонаж стартует перед открытым коридором. F3 открывает панель, Shift + W ведут вдоль маршрута. Автоматическая проверка через этот же запуск прошла 96,03 м со скоростью до 4,8 м/с с переключением ракурса на 180° и 90° во время бега. По 196 выборкам пустых участков в ближней и дальней зоне не найдено, переполнений нет, пол готов. p99 13,22 мс и max 42,35 мс; вид и ощущение управления ещё оценивает автор. Замеры и исходники — `ember-grass-travel`, `ember-grass-lane`, `ember-grass-cold`, `ember-grass-fresh`, `ember-grass-packed` в каталоге QA за 04.11. Пакет для ручного запуска имеет отдельную копию данных и после выхода восстанавливает скрипты общего QA-окружения.

Предпочтение автора — одна визуально непрерывная трава. В QA одни сохранённые положения корней питают GPU-вариант обычной травы. Нативный вариант может кратко оставаться видимым до готовности GPU, на расстоянии меняется детализация тех же травинок. Открытым остаётся ручное сравнение формы, цвета и перехода, особенно при боковом свете. Для масштаба полей с индивидуальными травинками на GPU есть отдельный доклад разработчика Sucker Punch. [Procedural Grass in Ghost of Tsushima](https://gdcvault.com/play/1027214/).

**Выпуск позиций для сохранённой карты.** Сборка мира через `tools/prepare_world_bundle.gd` теперь сама вызывает `tools/prepare_grass_positions.gd`. Сборщик проходит по окрашенным участкам обычной травы в сохранённой сцене. На каждом участке штатный `EmberGrassPatch` либо читает готовую запись, либо рассчитывает положения тем же способом, что и игра. Запись содержит три вида детализации. Манифест связывает путь участка с ключом его исходных данных и передаёт экспортёру файлы для `res://ember-prepared/details`. Удалённые участки исчезают из перечня травы; при стирании последнего участка допустим пустой манифест. Физические границы препятствий для ключа берутся у того же владельца, который проверяет опору травинок. Редактор, формат карты и исходные маски не меняются.

Отдельную сборку можно повторить командой `godot --headless --path . --script res://tools/prepare_grass_positions.gd -- --source=res://scenes/landscape_compact.tscn --output=<абсолютный-путь-к-отдельному-каталогу>`. Сборщик публикует обычный манифест подготовленных данных; экспорт всего мира по-прежнему использует существующий изолированный профиль EmberBuildProbe. Неподготовленные запросы в игре сохраняют обычный путь расчёта.

На основной карте получены 125 записей (2 390 794 байта), 70 164 положения в ближнем виде. При повторном выпуске 125 из 125 файлов сохранили время записи. В отдельном запуске с пустым локальным кэшем Forward+ прочитал все 125 из PCK, без генерации этих участков. На fixture проверены живая правка маски и её отмена, подъём земли, появление и перенос камня с другой отображаемой геометрией, удаление участков вплоть до пустой карты. Для нетронутого участка проверен прежний ключ, отсутствие вычисления позиций и соответствие загруженного GPU-буфера данным пакета. Это проверка подготовки и чтения, не приёмка 120 FPS. Артефакты — `C:/Users/novos/Documents/Codex/2026-11-04/ember-grass-map-bake/`, отдельный пакет `landscape-grass.pck`, манифест `verified/manifest.json`.

Повтор связанного плотного QA-маршрута с новым определением физических препятствий прошёл 96,03 м с Shift и сменой ракурса на 180° и 90°. В 195 выборках до 24 м пропусков не обнаружено, опора сохранилась, переполнений GPU не было. p99 14,34 мс, max 36,84 мс. Это внешний полигон без NPC; ручное ощущение основного игрового запуска остаётся открытым.

У Guerrilla автор размещения задаёт правила, а *Horizon Zero Dawn* вычисляет результат на GPU вокруг игрока. Для Ember берём разделение авторских правил и производных позиций; выбор подготовить позиции до игры сделан по нашим холодным проходам. У miHoYo есть конкретный пример такого разделения для отражений: команда заранее сохраняет данные сцены и обновляет освещение проб во время игры. Это отдельная техника освещения, а не свидетельство устройства травы в Genshin. [Доклад Guerrilla о размещении в Horizon](https://www.gdcvault.com/play/1024700/) · [Доклад miHoYo, слайды 56–57](https://image.docswell.com/s/UnityJapan/KWRPQ5-210617-unity-dojo20211mihoyozhenzhongyi).

**Windows-экспорт основной карты, 04.11.** Для ручной игры открыть `C:/Users/novos/Documents/Codex/2026-11-04/ember-release-travel/Play.cmd`. Он запускает оконный исполняемый файл в полноэкранном режиме с отдельными сохранениями. Текущая карта использует Хоши, WASD для обычного бега и Shift для медленного шага. В отдельном плотном полигоне выше Shift по-прежнему ускоряет. В экспортной копии включены двоичные сцены, загружаемые по имени, в том числе аватар и предметы. Первый неполный экспорт с заглушкой исключён из замеров.

На RTX 5070, Forward+, без VSync, масштаб 3D 1,0. Снимки конечного буфера подтвердили 2560×1440. В игровой сцене два CharacterBody3D. Из одинаковой стартовой точки в двух отдельных прогретых профилях персонаж пробежал 17,77 м, прошёл ещё 3,59–3,61 м с Shift и вернулся примерно на 21,5 м. Вращение камеры на месте длилось четыре секунды. При FOV40/70 соответственно p99 вращения — 7,60/8,05 мс (максимум 8,04/8,29), бега — 8,34/7,40 мс, возврата — 8,41/7,53 мс. При беге медиана draw calls выше на широком угле (985 против 655), хотя p99 там ниже. Это короткий маршрут обычной карты.

Экспортёр включил 361 готовую запись мира, из них 125 записей обычной окрашенной травы. На маршруте из чистого профиля получены 104 чтения травы из пакета, 101 участок получил ключ, число генераций было нулевым. На паре FOV40/70 повторён тот же результат. Каждые 200 мс проверялся видимый центр окрашенного участка ближе 16 м. Каждый обнаруженный пустой участок проверен по соответствующей записи пакета: предусмотрено ноль корней. Покрытие в промежутках между выборками и внешний вид перехода проверяет автор. От старта процесса до начала измерительного маршрута в первом прогоне прошло 31,9 с, в повторном с сохранением — 12,2 с. Эти времена включают загрузку, выбор направления и секундную выдержку.

На проходах **из сохранённых позиций** картина отличалась. FOV40 дал кадр 822 мс при возврате, FOV70 — 597 мс во время бега. Воспроизведение из той же позиции FOV70 дало 598 мс у координат (113, 10, 560) в единицах Godot. В этой точке окно было в фокусе, GPU занял около 4,6 мс, счётчики компиляции draw/mesh/surface не изменились. Обработка земли заняла 0,044 мс. При повторе с таймером вокруг `EmberVoxelProp._living_for` кадр занял 598,06 мс, переход `vox_earth_cliff_straight` в ближний вид — 584,95 мс, включая 581,12 мс в `_living_for`. Отдельный кадр 822 мс на другом возврате пока не атрибутирован. Полные ряды — `C:/Users/novos/Documents/Codex/2026-11-04/ember-release-travel/measurements/`: `same40/same70` имеют общий старт, `native40/wide70` документируют другие старты, `trace70/object70` повторяют место длинного кадра.

**A/B одного уступа.** Для отдельного экспортного кандидата штатный метод построил детальную сетку единственного `vox_earth_cliff_straight` этой карты заранее. После сохранения и загрузки нативного ArrayMesh совпали массивы поверхностей, типы примитивов, имена и метаданные данных. Размер 1 661 757 байт. При том же старте, направлении и FOV70 в кадре активации уступа 598,06 → 10,46 мс, внутри перехода объекта 584,95 → 5,13 мс. Максимум всего шестисекундного бега 598,06 → 79,15 мс. Персонаж успел пройти дальше за то же время. На угловом уступе остался кадр 57,03 мс, на `vox_merge_20548286_0` — 79,15 мс (из них 70,04 мс в переключении объекта). Для визуального сравнения кандидат запускается через `Play-Prepared-Cliff.cmd` из каталога `ember-release-travel`. Метод проверен в диагностическом экспорте. Ручной вид, 822-мс остановка другого возврата и общий бюджет открыты.

**Штатный экспорт и подгрузка объектов.** Плагин экспорта Ember строит конечный ArrayMesh из сохранённого объекта основной карты, его актуальной модели и материалов. В PCK попадают шесть разных сеток для девяти экземпляров (34,57 МиБ суммарно). Сверка всех девяти позиций из конечного пакета со штатным построением совпала по массивам поверхностей, метаданным и пикселям текстур граней. Индекс принадлежит этой конкретной карте и связывает путь экземпляра и модель с контрольной суммой байтов сетки. Копии делят ресурс. При изменении исходника или формы материала следующий экспорт заново рассчитывает результат. Исходная карта и сохранения игрока остаются у прежних владельцев.

В игре `EmberMapLoader` начинает фоновое чтение во внешней зоне (на этой карте 44 м). Переход к ближнему виду запрашивается с 36 м. Система проверяет готовность записи и актуальность экземпляра перед подключением. Пока запрос выполняется, на сцене остаётся прежняя геометрия с её коллизией. Если игрок уходит, просроченный результат не публикуется, лишняя ссылка освобождается. Вращение камеры не перемещает зону подготовки. Команда для ручного запуска актуального экспорта — `C:/Users/novos/Documents/Codex/2026-11-04/ember-depth-return/Play.cmd`.

У штатной камеры исследования центр подготовки теперь следует за персонажем. Раньше он получался пересечением луча камеры с фиксированной плоскостью, поэтому на склоне разворот мог изменить набор нужных участков. Для свободной камеры и редактора продолжается расчёт точки обзора. В экспортированной игре за четыре секунды резких поворотов на месте при FOV40 и FOV70 центр подготовки переместился на 0,00 м. На повторе быстрого прохода за три секунды персонаж продвинулся на 14,04 м против 3,61 м при медленном шаге. Максимальное горизонтальное отставание опорной точки при ускорении — 1,20 м (обновление раз в 0,25 с). В наблюдавшихся кадрах ожидания сохранялись видимая сетка и коллизия. В выборках ближней травы на ускорении все пустые участки соответствовали нулю корней в пакете.

На RTX 5070, Forward+ 2560×1440, FOV70, тот же старт и направление, кадр переключения прямого уступа занял 9,32 мс против исходных 598,06 мс. Счётчик подтвердил использование готовых сеток для всех трёх пересечённых тяжёлых объектов. На угловом уступе и объединённом объекте остались кадры 35,89 и 53,35 мс.

На повторе того же возврата FOV40 исходный максимум составил 319,37 мс, переключение готового выступа заняло 265,49 мс внутри кадра 284,25 мс. Из них 4,05 мс пришлось на получение дальнего шейдера и 238,82 мс на первое присвоение его живому материалу. В обоих длинных кадрах счётчик компиляций Surface вырос на шесть. Загрузка карты теперь один раз подготавливает настоящие назначения ближнего и дальнего шейдеров для обычных и слоистых материалов. В изолированном A/B подготовка заняла около 0,54 с под экраном загрузки, максимум возврата упал до 34,31 мс. Смена только визуального вида также перестала читать все треугольники для проверки коллизии, когда уже установлен исходный коллайдер и другая форма не запрашивается. При переходе на иную физическую сетку проверка принадлежности опубликованной формы сохранена. Смена света, ракурса, параметров и порога глубины по-прежнему обрабатывается в игре.

В двух стартах финальной Windows-сборки (RTX 5070, Forward+ 2560×1440, FOV40, одинаковая сохранённая позиция и команды) кадр активации выступа составил 6,31 и 7,70 мс, из них 3,21 и 3,26 мс внутри переключения. Максимумы всего возврата — 32,20 и 32,56 мс, p99 — 9,14 и 10,21 мс. В обоих случаях остаточный максимум находился около (219, −8, 374) в единицах Godot, при нулевом времени переключения объекта. Его причина и строгие 120 FPS открыты. Проверены сохранение текстур, порога и режима деформации в тесте дальнего материала, а также коллайдер и лучи по поверхности во всех трёх видах модели. Сводка и исходные трассы — `C:/Users/novos/Documents/Codex/2026-11-04/ember-depth-return/comparison.json` и соседняя папка `measurements`. Ограничения предварительной подготовки для конкретного устройства описаны в [документации Godot о компиляции программ рендера](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html).

Ключи данных проверены на копии проекта. Правки модели и силы изменения формы материала дают разную геометрию, возврат исходников восстановил первоначальный результат. Холодная отмена запроса, возврат, сохранение коллизии и пикселей текстуры граней покрыты `test_packed_object_detail.gd`. Замеры — `C:/Users/novos/Documents/Codex/2026-11-04/ember-object-prefetch/measurements/`, `anchor70`, `sprint70`, `anchor40`, диагностика `trace40`. В файле `anchor-fast70` фактически использовался обычный медленный Shift; для ускорения брать `sprint70`. Изменения входов — `inputs.json`.

На отдельном плотном полигоне без NPC проверена та же привязка к игроку с прежними экспериментальными GPU-травой и предзагрузкой по скорости. При FOV70 герой прошёл 96,03 м со скоростью до 4,8 м/с, включая смену ракурса на 180° и 90°. В 196 выборках до 24 м пропусков покрытия не найдено, опора сохранилась, переполнений не было. p95 11,65 мс, p99 14,70 мс, максимум 46,50 мс. Данные — `ember-object-prefetch/dense-verified/play-smoke.json`. Это отдельная проверка плотности; предсказание скорости этого полигона пока не входит в экспорт основной карты.

В докладе Guerrilla для Horizon разделены подготовка содержимого вокруг игрока и его активация при приближении. Это задаёт проверяемый вопрос для Ember: была ли работа сделана до того, как результат понадобился в кадре? Счётчик построения травы, чтение пакета и время кадра поэтому измеряются отдельно. [Guerrilla, Streaming the World of Horizon Zero Dawn, слайды 16 и 37–40](https://www.guerrilla-games.com/read/Streaming-the-World-of-Horizon-Zero-Dawn).

**Что уже известно.** Прогоны с выключенным движением или скрытыми моделями оставляли тела, часть обработки и изменённые условия готовности земли. Малый тест одного участка и пустая сцена также имеют другую нагрузку. Приёмка плотного мира без NPC открыта.

В архивном сценарии перехода на 80 м участок измерения начинался уже после проверки опоры. До 30 последовательных кадров с пустой очередью исходной растительности прошло 40,113 с, при возврате 26,789 с. Внешний тест в каждом кадре вызывал `grass_status()`, обходивший все 25 848 участков. Затем проверка GPU-очереди, включая 20 стабильных кадров, заняла ещё 265 и 223 мс соответственно. Эти времена показывают завершение очередей. Когда игрок увидел пригодный кадр и сколько стоил сам наблюдатель, тот протокол не записывал.

1. На существующем полигоне 576 м запускать только игрока, без создания дополнительных NPC, их коллизий, анимационных пакетов и пакетного рендера толпы. Проверять состав фактической сцены. Сохранить землю, траву, цветы, деревья, дома, ящики, воду, освещение, плотность и дальность. Отдельно фиксировать время холодного старта до передачи управления.
2. При native 2560×1440 и FOV 40/70 записать покой, медленный и резкий разворот, ходьбу, быстрый ход через границы участков, разворот назад и повтор маршрута. Сохранять покадровое время, p95/p99/max, количество и подряд идущие кадры выше 8,33 мс, CPU/GPU раздельно, объём подготовленных/подключённых данных и память после возврата. Получать события очереди у владельца или с редкой выборкой. Не помещать полный обход растительности в измеряемый кадр.
3. Для телепорта отдельно испытать первое посещение, тёплый возврат и смену назначения во время подготовки. Записать от запроса до готовности пола, до первого вида с нужным покрытием, до передачи управления и до завершения дальних деталей. Проверить отсутствие провала игрока, дыр в земле и появления отменённой работы в кадре. Считать длинные кадры на всём переходе, включая подготовку.
4. По месту задержки сравнить текущую реализацию с одним более простым вариантом на том же маршруте. Возможные кандидаты — подготовленные заранее данные размещения у источника растительности либо временная точка предварительной загрузки у места назначения с использованием действующих owners земли, физики и растительности. Выбирать по измерению очереди. Условие принятия — выигрыш кадра и времени видимой готовности при прежних покрытии, физике, сохранениях и ограниченной памяти. После этого возвращать NPC и сравнивать с принятой базой.

Для быстрого наземного движения у Insomniac единицей проверки был городской квартал, который игрок пересекает на игровой скорости. Для Ember отсюда следует проверка реального перемещения через стык. [Доклад разработчика Sunset Overdrive](https://www.gdcvault.com/play/1022268/Streaming-in-Sunset-Overdrive-s)

Epic описывает временный источник загрузки у назначения телепорта, ожидание готовности и последующий перенос игрока. Для Ember это кандидат на сравнение поверх существующего `prepare_physics_destination` с отдельной готовностью видимого мира. [World Partition, Streaming Sources](https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partition-in-unreal-engine#streamingsources)

Наблюдение автора о проявлении персонажей «по пикселям» относится к визуальному переходу. Его можно обсуждать при работе над появлением NPC. Цель текущего этапа — устойчивый кадр мира. Общий порог 120 FPS и перенос на основную карту остаются открытыми.
Матрицу плотности и независимые прежние проверки без относящегося изменения не повторять.

### Остаточная цена кадра04.11 — атрибуция и контроль компонентов

Автор отложил ручную оценку теней до возвращения домой и запросил дальнейший поиск
дорогих кадров. Контракт этого среза: на текущем native-shadow QA разделить физику,
анимацию,землю/растительность и рендер,затем проверить дорогие группы одним изменением
за раз. Без снижения качества в рабочем режиме,новых механик,миграции/commit и помощников.
Production/main и постоянные QA sources не менялись;готовый результат — доказанная
очередь узких мест,не обещание нового FPS. Прежняя матрица теней не повторялась.

**Условия.** Тот же официальный Godot4.7.2/Vulkan Forward+/Jolt/RTX5070,
actual fullscreen2560×1440/scale1/FOV70,distance12.5м,polar50.4203°,обычный captured
QA preset(native Source shadows,PCFLow4096/2каскада/blendON),dense576м/25848patches/
859props/39NPC+игрок/8важных/16ящиков/4дома/8ламп. GPU grass210975roots/208tiles,
очереди пусты. Игрок на месте,yaw±90°4Hz;наклон/zoom/плотность прежние.

**CPU-атрибуция.** Временные wrappers только в12файлах Temp QA:Map process/physics/
object poll/restore,terrain observer/support/material/process,DetailPreparation sleeping,
WorldRecovery anchors/physics,native/ordinary visuals,animation advance/flush,palette,
GPU grass/flowers process,панель. Nested stack отдельно считает inclusive/self/calls;
итог не складывает родителя с дочерним scope. NPC move callback использует существующий
measure_calls. Completed callbacks собираются за wall interval,engine/OS/GPU wait и
отложенные native Skeleton/Jolt callbacks этим не покрываются целиком.
Wrapper OFF rapid15с:median10.695/p9914.531мс. ON rapid30с:10.726/14.598мс;
большого искажения wall не видно,но это не нулевая цена профилирования.

- На rapid кадры с NPC physics callback:median11.370мс,без него7.452мс.
  Корреляция сама по себе не изолирует причину;ниже отдельный контроль.
- Сумма движения39NPC за обычный физический шаг≈1.85мс,p99≈2.386мс по render interval;
  несколько physics catchup ticks в одном кадре увеличивают сумму. Это не общий physics time.
- Terrain observer inclusive p99≈2.250мс,terrain process≈3.144мс. Обход≈0.25с,
  ordinary frame self terrain≈0.05мс;это источник периодической цены,не постоянные3мс.
- Object poll p99≈0.975мс;Map physics inclusive≈1.264мс,возврат коллизий≈0.831мс,
  anchors≈0.451мс. Суммировать эти вложенные значения нельзя.
- Все ordinary visuals self mean≈0.215мс,palette total p99≈0.283мс;
  animation flush self mean≈0.197мс,native visual inclusive p99≈0.334мс.
  Это вызванный скриптом путь,не вся native цена skin/skeleton/VRM.
- GPU-grass process mean≈0.141мс,цветы≈0.178мс,панель≈0.011мс.

Отдельные GPU probes:still median7.578/p997.660мс,rapid7.685/12.967мс;
render CPU rapid median1.471/p993.002мс. Эти часы отдельно от clean wall.
Самый длинный clean/profile rapid кадр60.133мс имел117NPCcalls(3physics ticks),
move5.895мс+прочие callback self3.476мс. Обычная скриптовая работа его полностью
не объясняет;33/27мс spikes тоже не имеют одного дорогого measured callback.
Не объявлять их доказанной утечкой,shader compile,OS preemption или Jolt bug.

**Контроли компонентов.** Один новый живой процесс,одинаковый NPC/LOD checkpoint
перед каждым arm,3сwarmup/3сstill/12сrapid/5сотдельныйGPU/3сreturn. Данные ниже —
clean rapid median/p99 и отдельный GPU median/p99,вмс.
- Полная исходная нагрузка:10.654/15.678;GPU7.753/10.211.
- NPC controller physics OFF:8.127/11.478(−23.7%median);GPU6.997/9.268.
  Останавливает и age/animation selection/root transforms в этом fixture,поэтому
  дельта2.53мс — цена группы работы,не чистая exclusive цена body_test_motion.
- Process hierarchy восьми важных visuals OFF:9.731/14.882(−8.7%);GPU7.200/9.461.
  Геометрия остаётся,поза/secondary processing заморожены. Качество не предлагается снижать.
- Только рендер всех персонажей скрыт:9.019/13.940(−15.4%);GPU6.160/8.557.
  Движение39тел и8native processing сохранены;visibility может влиять и на native work.
- Только GPU-grass draw layer0:10.385/15.376(−2.5%);GPU7.384/9.808.
  Compute/roots/streaming продолжаются,исходная CPU-трава не включалась.
- Только flower-HLOD render скрыт:9.883/14.939(−7.2%);GPU6.909/9.331.
- Только Map/Props render скрыт:10.069/13.486(−5.5%);GPU7.357/7.901.
  Это группа scenery/её теней,не изолированный материал деревьев.
- Полная нагрузка вернулась:10.609/15.574;GPU7.750/10.233.
  Drift median−0.42%,p99−0.66%;активны39physical callbacks/8native visuals.

Эти deltas перекрываются и не складываются. OFF controls нужны для атрибуции,
не принимают120FPS и не становятся игровым default. Даже controller-OFF p9911.478мс.
0errors/0game saves,позиция игрока/Source roots/tiles/очереди сохранены,конечное качество
8important восстановлено. Все12probes возвращены побайтно;archive/Temp34SHA совпали.

**Вывод для совместного кадра с толпой.** Внутри блока NPC приоритет — движение/физические
запросы NPC,затем рендер персонажей;цветы и observer земли — следующие измеренные группы.
GPU-трава уже сравнительно недорога;это не основание снова снижать её плотность.
Текущий результат подтверждает прежний native profiler02.11 на новом составе рендера,
а не открывает тот же controller вопрос заново. Jolt/точный HeightMap уже применены.
Прежние full triangle fallback/перенос CharacterBody вworkers/Separate не повторять:
старые доказательства/ограничения сохраняются. RigidBody32NPC уже дал≈2мс в прошлой
пробе,но менял контакт сящиком и не принят;новый renderer baseline не закрывает этот gate.
Перед такой заменой нужно сохранить gameplay contacts и провести сопоставимый current A/B;
не подменять движение/единую физическую поверхность ради FPS. Этот вопрос возвращается
в блоке 3 после проверки мира без NPC. В этом диагностическом контракте ни одно поведение
движения не менялось. Хвосты27–60мс и GPU углы до≈13мс остаются самостоятельными gates.

Методика: [Godot Profiler](https://docs.godotengine.org/en/stable/tutorials/scripting/debug/the_profiler.html)
различает self/inclusive и допускает scoped µs measurement;
[Collision shapes](https://docs.godotengine.org/en/stable/tutorials/physics/collision_shapes_3d.html)
описывает стоимость представлений. [HeightMapShape3D](https://docs.godotengine.org/en/stable/classes/class_heightmapshape3d.html)
уже используется там,где соответствует общей физической поверхности;ссылка не новая миграция.

Первый инструментированный запуск REJECTED до измерений:wrapper helper names совпали
в base/derived scripts и вызвали рекурсию. Собственный процесс остановлен,12исходников
восстановлены;новая обвязка имеет уникальное имя на source file. Ошибочные данные не
участвуют в выводе. Valid profile-fixed и components завершены exit0/errors[].
Evidence:`C:/Users/novos/Documents/Codex/2026-11-04/ember-frame-attribution/`:
`profile-fixed/frame-attribution.json`,`analysis.json`,`components/component-controls.json`,
`component-analysis.json`,`verification.json`,`Run-Attribution.ps1`,`Run-Components.ps1`.

### Настройки теней QA04.11 — панель и параметрический прогон

Автор попробовал native Source-тени:«вроде чувствуется лучше»,затем прямо запросил
настройки качества/разрешения/мягкости/технологий и отдельного тестировщика.
Контракт: расширить существующие ManualSession/ManualPanel, временные настройки
на сеанс, тот же dense QA и native1440p; сравнить параметры на одинаковом yaw-маршруте.
Один `ember_tester`(GPT-6.1 Sol/medium),без правок runtime/авторских сцен,получил стабильный
стенд и узкую матрицу; координатор не повторял переданный прогон/анализ. Приёмка
движущегося вида/мыши/качества у автора; это не перенос всего GPU QA на main.

**Доступно.** Прежний `Start-Ember-Manual.cmd` → F3 → «Тени»: Hard/PCF/PCSS,
5уровней фильтра,карта солнца1024/2048/4096/8192,1/2/4каскада,мягкость края,
угловой размер солнца PCSS,смешивание стыков,дальность; отдельно тени фонарей,
их атлас и фильтр. Есть общий диагностический OFF,прежний отдельный shadow LOD
для сравнения,shadow-only reset и общий reset. Настройки и live light state
сохраняются в snapshot/trace. Значения не записываются в авторскую карту/Resource.
Default QA использует native Source caster,сохраняя исходные световые параметры.
Рендер/растительность/NPC/плотность/камера/launcher остались прежними. Автовыбор
более грубого художественного профиля не выполнялся.

Owners:архивный `ember-manual-performance/prototype/qa_manual_session.gd`,
`qa_manual_panel.gd`,новый узкий `qa_manual_shadows.gd`; последний хранит только
нативные setter/capture и defaults. Session маршрутизирует команды,Panel — UI.
Сохранённый QA manifest34files;archive/Temp совпали,main runtime scripts не изменены.
Глобальные atlas/filter задаются через RenderingServer;matching getters в Godot нет,
поэтому capture честно разделяет applied globals и реальные light/local-atlas readback.
PCSS=light_angular_distance>0;Hard принудительноangular0/filterHARD;PCF angular0.
Состояния контролов исключают неработающую мягкость вHard и PCSSangle вPCF.
Ray tracing/запекание/temporal shadow cache не добавлялись под видом нового режима.

**Проверка.** Native Godot4.7.2/Vulkan Forward+/Jolt/RTX5070,actual fullscreen2560×1440
scale1;плотные576м/25848patches/859props/39NPC+игрок/8важных/16ящиков/4дома/8ламп.
Checkpoint NPC+LOD clocks сбрасывается перед каждым вариантом,игрок неподвижен.
3сwarmup/PNG вне timing/3сstill/8сyaw±90°4Hz/4сотдельный GPU probe/2сreturn.
27cases:23приFOV70 по одному параметру и профили,4приFOV40 для сочетаний/return.
Отдельно5коротких FOV70cases закрыли пробел exact captured default и local atlas2048/8192.
Дважды всю матрицу не запускали. Каждая конфигурация имеет raw frames/settings/live
camera/light state,wall median/p95/p99/max/%over8.33,GPU/renderCPU,draws,RAM/VRAM.
37source SHA стабильны,queues пусты,210975roots/208tiles и8important сохранены,0game saves.
Нет shader/script/engine errors;3UID-warning берёзы успешно разрешены по пути.

Проверены команды панели,реальные sun/atlas readback,Hard/PCSS/path/on/off,оба reset,
snapshot metadata и native UI top/bottom. PNG проверил тестировщик:текст читается,
scroll/reset доступны;на fast заметно грубее дальние тени деревьев. Мерцание/мышь/art OPEN.
Первый matrix exit1 имел единственный ложный strict Dictionary== assertion snapshot:
13int→float после JSON и polar rounding≈4.26e−14°. Все36keys семантически совпали.
Tiny headless probe exit0 подтвердил normalized equality;исправлен только test assertion,
измеренный source/manifest сохранены. Focused followup выполнил fixed UI gate:exit0/errors[].
Это устранение ошибки проверки,не исправление gameplay serializer и не повтор performance.

**Контролируемые результаты.** Основной matrix baseline — PCF Low4096/4каскада/blendOFF;
это специальный эталон,не исходный captured default2каскада/blendON.
- FOV70 baseline median/p99:10.767/15.504мс,GPUmedian7.842мс.
- PCF Low4096/2каскада/blendOFF:10.301/14.526мс,GPU7.400 (−4.3%/−6.3% от4cascade).
- Fast PCF VeryLow2048/2каскада/blendOFF:10.182/14.591мс,GPU7.103 (−5.4%median).
  FOV40:8.649/13.658мс,GPU6.248;median−8.7%,ноp99+5.9% к4cascade reference.
- PCFUltra:12.137/17.315мс;atlas8192:11.237/16.535мс,VRAM≈2240MiB против≈2047.
- Soft PCSSMedium4096/4каскада:11.726/16.566мс,GPU8.838;вариант мягкого вида,не ускорение.
- Hard почти не изменил wall:10.750/15.600мс;уменьшать качество ради этого не рекомендуется.
Baseline return drift median+0.08% FOV70/−0.34% FOV40;малые дельты не устойчивый выигрыш.

**Сравнение с точным текущим default.** Focused5cases сохранили PCFLow4096/2каскада,
blendON,localatlas4096 и все прочие captured settings:
- Default median/p95/p99:10.660/14.611/15.770мс,GPUmedian7.800.
- Только blendOFF:10.215/13.380/15.207мс (−4.17/−8.43/−3.57%),GPU7.440.
  Цена — несглаженные стыки каскадов;вид в движении выбирает автор. Рекомендация —
  попробовать этот один переключатель,не менять автоматически default.
- Localatlas2048/8192:median10.710/10.749мс,GPU7.749/7.765,VRAM≈2024/2146MiB
  против≈2048 уcaptured4096. Скоростная польза не доказана;оставить4096.
  Реальный readback2048→8192→4096 подтверждён;ночная/другая локальная сцена не измерялась.
- Captured return median10.667(+0.066%),p9915.714;дрейфp95−4.76% ограничивает хвостовые дельты.

**Ограничения и следующий шаг.** Общий120FPS OPEN:уblendOFF68.2%rapid-кадров выше8.33мс;
даже all-shadowsOFF control не закрыл бюджет. На основном маршруте тени — часть цены,
не единственное узкое место. CPU/GPU работают параллельно,числа не складывать.
RAM выросла≈4800→5333MiB за последовательную матрицу;это не cold память каждого
профиля и не доказанная утечка. VRAM/RAM — учёт Godot,полнаяresidency не измерялась.
Узкий 2cascade4096/blendOFF приFOV40 отдельно не измерен;fast/soft там проверены.
GTX1060/night/temporal art/main migration/вся программа оптимизации остаются OPEN.
Текущий срез настроек технически завершён;дальнейший перебор без нового вопроса не нужен.
После авторского выбора — вернуться к измеренным остаточным CPU/GPU/stalls и прежней
единой очереди,включая NPC transition timer/source preparation,без нового shadow backlog.

Первичные API/ограничения: [DirectionalLight3D](https://docs.godotengine.org/en/stable/classes/class_directionallight3d.html),
[Light3D PCSS/blur](https://docs.godotengine.org/en/stable/classes/class_light3d.html#class-light3d-property-light-angular-distance),
[RenderingServer atlas/filter](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-directional-shadow-atlas-set-size).
Evidence:`C:/Users/novos/Documents/Codex/2026-11-04/ember-shadow-settings/`:
`tester-report.md/json`,`tester-followup-report.md/json`,`matrix/shadow-matrix.json`,
`matrix/shadow-panel.png`,`matrix/shadow-panel-bottom.png`,`tester-json-probe.json`,
`integration.json`,`Run-Matrix.ps1`,`measured-manifest.json`,`staged-manifest.json`.

### Резкие повороты04.11 — штатные тени против отдельного shadow LOD

После ручного теста автор сообщил о резких поворотах влево/вправо без перемещения,
draw calls1830–2299 и среднем FPS65–81. Предыдущая локальная правка корректна, но
camera-performance автором не принят. Новый контракт: воспроизвести именно резкие
смены направления, проверить накопление в одном ракурсе, установить измеренную причину
и сравнить существующий путь со штатным механизмом до следующих локальных оптимизаций.
Runtime owners/main/канонический QA-пакет не изменялись; сравнение во внешнем QA.

**Воспроизведение.** Обычный manual launch, его defaults: FOV70, distance12.5м,
polar50.4203°, GPU grass style0/100%/width1/height1/patch2м. Это отличается от прежнего
прогона snapshot(FOV45/style2/50%) и плавного круга6с. Официальный Godot4.7.2,
Vulkan/Forward+/Jolt/RTX5070, actual fullscreen2560×1440/scale1, прежние dense576м,
25848patches/859props/39NPC+игрок/8important native/16ящиков/4дома/8ламп.
Игрок фиксирован; NPC живые. Других Godot-процессов при замере не было.
Чистые timing samples с выключенными GPU timers; readback/JSON вне их интервалов.
Probe median≈64–72µs, один подробный срез в2с; runtime owners без инструментации.

Маршрут: покой8с → yaw±90°/2Hz30с → исходный вид12с → ±90°/4Hz30с → исходный вид20с
→ ±180°/1Hz30с → исходный вид20с. Наклон/zoom/позиция игрока прежние.
Медианы кадра:10.698 →13.114 →10.848 →14.964 →10.740 →13.102 →10.860мс.
У 4Hz p9921.385/max33.139мс. Тяжёлые резкие повороты воспроизведены; постоянного
накопления в исходном ракурсе за этот маршрут не получено. Это не опровержение
другого положения/пресета/более долгой пользовательской сессии и не точный replay140→60.
GPU grass всё время208tiles/210975roots,0pending/jobs/publishing,0новых uploads/drops.
Draw calls меняются с видом и теневыми проходами:4Hz median1999/max4172; после возврата
median2110 против2022 до. Нельзя по этому объявлять утечку или отсутствие других очередей.
Фоновое native-представление NPC колеблется, но при4Hz fallback median3/max6,
после остановки median7/max11 при восстановившемся wall. Это не причина найденной
основной добавочной CPU-цены. Известный transition timer остаётся отдельным открытым дефектом.

**Постепенность показания FPS.** ManualPanel.frame_stats считает FPS как1000×count/sum
по кольцу1200кадров, а draw calls берёт текущим monitor. Медленные кадры постепенно
вытесняют быстрые; окно расширяется во времени. Offline replay записанных wall rows
через ту же формулу даёт после начала4Hz≈99.2/94.3/87.6/79.4/71.9/69.3/68.6FPS
на0/2/5/10/15/20/29с. При этом ранняя/поздняя медиана самого4Hz15.016/14.568мс:
стоимость поворотов не нарастает. Модель пропускает неснятые межфазовые кадры,
это не точный захват значений панели автора. Она подтверждает механизм плавного
индикатора при стабильной тяжёлой нагрузке; исходную более долгую сессию не закрывает.
Evidence:`rolling-counter-model.json`;реальная цена CPU выше не считается ошибкой индикатора.
**Причина и проверка альтернативы.** При4Hz shadow-context median≈3.39мс вместо≈0.05мс
в покое: при изменении квантованных receivers синхронно перепроверяются≈700готовых
proxy через Prop/RuntimeShadowLOD. Предыдущая правка убрала повторный полный binding,
но сам скриптовый обход, guards и native property getters остались дорогими.
Не продолжать оптимизацию этого обхода без сравнения с native source casters.

Один живой процесс, тот же checkpoint актёров/анимаций и LOD clocks, A/B/A:
custom shadow LOD → `Map.set_runtime_shadow_lod_enabled(false)` → custom return.
Штатный контроль возвращает исходные caster, сохраняет native mesh LOD, материалы,
геометрию видимых объектов и динамические тени. Это не выключение солнца/теней.
Каждый arm:4сwarmup,5сstill,20сrapid4Hz, отдельные GPU samples3сstill/8сrapid,3сreturn.
Важные8/количество NPC/плотность/карта не менялись;0errors/0saves.

- Чистый rapid wall median:13.546 →10.901 →13.619мс (−19.5–20.0%).
- Чистый rapid p99:19.994 →14.962 →19.691мс (−24.0–25.2%).
- Shadow-context median:3.3805 →0.002 →3.405мс.
- Still median:10.180 →10.161 →10.317мс; выигрыш связан с поворотами.
- Rapid total draw median:2106 →2178 →2111. Больший счётчик совместим с более быстрым кадром.
- Отдельный GPU rapid median:7.822 →7.871 →7.826мс; p9910.523 →10.452 →10.547мс.
  GPU-выигрыша текущей custom shadow LOD на этой RTX5070/сцене не видно; слабый GPU не проверен.

Red-capable `check_rapid.py`: rapid median≥1.25×still — FAIL. Baseline ratio1.399 FAIL;
matched customA1.331 FAIL/nativeB1.073 PASS/custom-return1.320 FAIL. Этот узкий сигнал
проверяет надбавку резких поворотов, не абсолютный120FPS. Native B всё ещё имеет76.2%
кадров выше8.33мс, max36.097мс и GPU p9910.452мс: общий stress/120FPS OPEN.
CPU/GPU clocks не складывались; max/stalls контролем не объявлены устранёнными.

**Рекомендация до среза настроек выше.** Для следующего среза предпочесть штатные source-тени
вместо дальнейшей доводки отдельного shadow LOD на текущей нагрузке. Готов отдельный
интерактивный `ember-rapid-yaw-audit/Start-Native-Shadows.cmd`: обычная сессия и тот же
API, явная подпись режима. Его script parse PASS; native API отработал в live A/B/A.
Сам CMD вручную не запускался, физическая мышь/art/manual acceptance остаются автору.
Канонический Start-Ember-Manual/33file manifest и main scripts сохранены; предложение
не считается production migration или приёмкой всей программы оптимизации.
Перед переключением общего default закрыть относящийся view/light/return gate;
GTX1060/dense-scale остаётся ограничением. Возврат custom допустим при измеренном
общем выигрыше на GPU-limited нагрузке и закрытом CPU-бюджете, а не по одному числу triangles.
Далее атрибутировать оставшиеся CPU/GPU/stalls по прежней очереди, без повторения densityAB.

**Первичные источники.** [Viewport render passes](https://docs.godotengine.org/en/stable/classes/class_viewport.html#enum-viewport-renderinfotype)
отделяет visible/shadow/canvas; объект может участвовать в нескольких shadow splits/lights.
[Performance](https://docs.godotengine.org/en/stable/classes/class_performance.html)
предупреждает о задержке отдельных monitors. [Mesh LOD](https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html)
описывает штатный выбор детализации и необходимость измерять пользу при CPU limit.
Выбор native для этой сцены следует из приведённого A/B/A, а не из обещания документации.

Evidence:`C:/Users/novos/Documents/Codex/2026-11-04/ember-rapid-yaw-audit/`:
`baseline/rapid.json`, `baseline/analysis.json`, `native-ab/native-ab.json`,
`native-ab/summary.json`, `check_rapid.py`, `Run-Rapid.ps1`, `Run-Native-Ab.ps1`,
`qa_rapid_yaw.gd`, `qa_shadow_native_ab.gd`, `verification.json`.

### Исправление CPU shadow-context04.11 — technical PASS, ручная приёмка OPEN

Согласованный срез выполнен в прежних MapLoader/Prop/RuntimeShadowLOD. При смене receivers
Map вызывает `Prop.recheck_runtime_shadow_receivers` → `RuntimeShadowLOD.recheck_receivers`:
проверяются уже подключённая геометрия/критические изменения Source и прежнее условие
полного caster. Полная eligibility/property/material/instance-parameter привязка остаётся
в существующем bounded object poll. Новых очередей, renderer, persisted fields или preset нет.
Положение/bounds/layers/материал/skin/script/caster меняются → Source сразу возвращается;
ресурсные mesh/shader/material изменения по-прежнему используют существующую invalidation.
Общая `_full_caster_required` сохраняет48/42м,солнце/locals/receiver footprint/party/маски;
камера не создаёт proxy и не перестраивает bindings. Source caster включается до удаления proxy.
Map profile теперь отдельно отдаёт `shadow_context_us` и `total_process_us`; прежний
`process_us` сохраняет область только object-detail, чтобы не поменять смысл старых данных.

В ограниченном stable probe512full updates:guard2348мкс,property sync2248мкс,decision1134мкс,
materials826мкс,parameters204мкс;RS value getters0. Это цена повторного CPU обслуживания
на fixture,не полный кадр. Быстрый путь переиспользует уже проверенные bounds/transform/layers.
[Godot4.7.2 MeshInstance3D](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/3d/mesh_instance_3d.cpp#L349-L380)
не уведомляет `property_list_changed` при raw surface override setter:поэтому pointer-проверка
surface overrides сохранена;полагаться только на Resource.changed было бы недостаточно.

**Проверки.** Обновлённый `tools/test_runtime_shadow_lod.gd` на старых owners дал RED:
64реальных изменения receiver bounds повторяли full update. На исправленных — GREEN:
full update не вызывается,proxy сохраняется;near entry/transform/bounds/layers/surface override
возвращают full caster немедленно. Остальные относящиеся native проверки alpha/vertex/instance
uniform/default/rebind/sun/local/long-shadow/Source/reparent/lifetime/collision прошли в том же
прогоне. Source geometry/visible primitives прежние,shadow4226→134 остаётся прежним LOD;
изображение same-bias proxy/source exact. Новых проверок editor history/save не требовалось:
схема/авторский документ не меняются;существующая pre-save очистка proxy проверена.

**Matched dense A/B/A.** Одна live-сессия,прежний snapshot/FOV45/2560×1440/scale1/Jolt,
8important+32ordinary/859props/25848patches. Старый→новый→старый путь задавался только
временным QA probe,production-флаг не вводился. Каждый arm:покой3с→5оборотов/30с→покой5с;
player fixed,NPC продолжают работу,их controller/pose/LOD clocks восстанавливаются между arms.
GPU timers OFF;все условия/ширина/плотность/дальность/свет прежние. Общий probe≈0.07мс/кадр
и малые временные обёртки одинаковы в обоих путях;метрики не объявляются чистым release baseline.

Turn shadow-context p99:12.684→4.074→12.745мс,max18.821→5.993→15.676мс.
Полный wall p95:17.841→12.926→18.470мс,p9923.898→18.446→24.117мс;
max55.642→37.406→48.652мс,mean8.374→7.881→8.392мс. Это≈66% снижения p99 shadow CPU
и≈23–24% снижения p99 полного кадра,но не устранение всех stalls. Всё ещё28.3%кадров нового
пути выше8.33мс:120FPS gate OPEN. Средние≈127FPS не закрывают минимум120.
Roots219826/visible draw median218 во всех turn arms;первый old arm дополнительно подключил
один поздно готовый patch1013roots/32416bytes,последующие два без uploads. Путь new_B имел
тот же больший cohort,что old_A_return;выигрыш не получен уменьшением растительности.

**Вид.** После timing выполнены три пары old/new/old приFOV40/40/70 и разных yaw,
native1440p. Engine time_scale0/scene processing disabled/TAA OFF только в отдельном capture;
этот freeze не использовался для FPS. Все3пары и old-return control:0отличающихся RGB-пикселей;
visible/shadow primitives и число proxy совпадают. Кадр широкого вида просмотрен. Moving TAA,
физическая мышь и ощущение плавности у автора ещё OPEN;автоматическая точность кадра их не заменяет.

Исправление подключено к main через существующие scripts;саму авторскую карту не меняли.
Те же3shared owner файла обновлены в постоянном manual QA,manifest теперь33files с helper;
все SHA архив/Temp совпали. Остальной GPU-путь остаётся только QA:это не production migration.
Прежний `Start-Ember-Manual.cmd` запускает исправленный путь,настройки/launcher не переделаны.
Временные probes убраны из runtime owners и проверены побайтно;сырые старые audit inputs сохранены.
Evidence:`C:/Users/novos/Documents/Codex/2026-11-04/ember-shadow-context-fix/`:
red.json/green.json,stable-subprofile.json,aba/audit.json,analysis.json,parity PNG,
package-verification.json;`Run-Comparison.ps1` воспроизводит A/B/A в прежнем внешнем QA.

**Осталось:** camera-performance автором не принят;последующий rapid/native A/B/A выше
заменяет рекомендацию продолжать этот shadow sweep. Полный кадр требует отдельной
атрибуции оставшихся задержек,включая Map physics/terrain/NPC. CPU-обход теневых объектов ещё
стоит до≈6мс в измеренном max;не объявлять его hard1мс. Историческое постепенное140→60 всё
ещё не имеет точного replay. Source preparation40с/27с,memory,другие четыре блока и main/weak-PC
приёмка сохраняются. Матрицу плотности,уже успешные независимые проверки и этот A/B без новой
причины не повторять. Новую очередь/geometry/LOD/качество теней этим результатом не расширять.

### Результат диагностики плотности и камеры04.11

Автор согласовал диагностику и временную инструментацию; уточнил, что поворачивал камеру
только влево/вправо, без наклона/приближения. На диагностическом этапе production-код,
настройки карты и постоянный QA-пакет не менялись. Все32 SHA архивного пакета и Temp совпали перед запуском и после
возврата временных проб. QA остаётся отдельной проверкой, не приёмкой main.

**Условия.** Официальный Godot4.7.2/ed1daf0bf, Vulkan/Forward+/Jolt, RTX5070,
фактический fullscreen2560×1440/scale1; прежний dense576м/25848patches/859props,
39NPC+игрок/8important native,16ящиков/4дома/8ламп. Игрок неподвижен, NPC продолжают
свои анимации/движение. GPU timers — отдельные интервалы; readback/PNG/JSON вне замеров.
Параметры — последний сохранённый manual-snapshot-1113408.json:карточки2,50%,ширина6,
высота0.3,кучность0,patch0.5м,FOV45,дистанция12.5м,наклон50.42°. Это сохранённая проба,
не новый art lock. Матрица меняет только процент; после неё восстановлены исходные значения.

**Плотность и счётчики.** В стартовой точке210975 подключённых корней/208участков,
capacity524288roots. Selected indirect instances при100/50/10/0/100%:
447393/223864/45386/0/447393; повторные100% точно совпали, все9commands при0% нулевые.
Кадр0% просмотрен: выбранная GPU-трава отсутствует, отдельные цветы/высокая трава остаются.
UI«готовых пучков» — source_count, не selected: его постоянство корректно; какой именно
счётчик имел в виду автор, по имени ещё не установлено.

Есть второй важный предел: общий engine primitive monitor≈153M почти не меняется с плотностью.
В [исходнике4.7.2](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp#L992-L1018)
CPU-оценка умножает геометрию на instance_count, не читает GPU indirect selected counts.
Наш output MultiMesh выделяет524288×8экземпляров на9surfaces с суммой36tri:
150994944теоретических примитива ещё до остального мира. Это не число фактически
отобранных травинок/растеризованных треугольников. Draw Calls также не обязаны масштабироваться
с плотностью: [ветка indirect](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp#L536-L550)
оставляет команды, меняется их instance count. Декоративно уменьшать счётчики нельзя.

При0% dispatch_roots остаётся210975,потенциальных слотов формы1687800;это активный диапазон,
а не вся capacity524288roots. При неподвижной камере повторного compute нет; при вращении
примерно один recull на кадр. Стоимость оставшегося compute при0% отдельно не приписана.
Статический GPU viewport median100/50/10/0/100%=8.166/7.405/6.585/6.161/8.209мс;
чистый wall median10.505/10.010/9.422/9.486/10.474мс. Живые NPC сохраняют вариативность;
это локальная диагностика двух сторон кадра, не сумма CPU+GPU и не120FPS PASS.

**Повороты.** Два места:канонический старт и положение из сохранённого среза. Второе
восстановлено из настоящего Transform камеры:ошибка позиции7.63e-5world units,
направления6.66e-8. Старые часы/позы NPC snapshot не сохранял; точного replay всей сессии нет.
Маршрут:покой8с→5оборотов по6с→покой15с,возврат того же yaw; GPU-диагностика отдельно.
В точке среза чистый wall median7.257→7.137→7.414мс,p9911.410→24.454→12.866мс;
turn max54.469мс. GPU viewport median4.664→4.572→4.668мс,не равен всему custom compute.
Постепенное140→60/рост draw calls не воспроизведены:обороты не ухудшаются последовательно,
visible draw median218; grass queues пусты,первая серия добавила один поздно готовый участок
и32416bytes,следующая без uploads/rebuilds. Это отвергает непрерывный churn GPU-травы
на этом маршруте, но не доказывает отсутствие любых очередей/утечек во всех системах.

**Измеренный CPU-пик.** После исправления потери записей на границе physics/process
временные события привязаны к wall-интервалам по одному монотонному clock,29588events.
В повторе turn p9924.249мс/max46.853мс. Из3569кадров186длиннее18мс:
их median wall21.192мс,shadow-context12.307мс; у2781кадра быстрее9мс shadow-context0.053мс.
Turn shadow-context p9912.622/max19.983мс. Внутренний shadow-context входит в Map process,
эти времена НЕ складывать. Map physics в длинных кадрах median0.415/max8.453мс;
terrain process median0.080/max4.271мс; GPU-grass CPU process median0.189/max0.300мс.
CPU submission custom compute обычно0.019мс,max0.214мс в отдельном probe;
это не измерение длительности самого GPU kernel. Проба добавляет около0.07мс на кадр,
плюс малые обёртки/сбор событий; её показатели не объявлять чистым performance улучшением.

Owner:MapLoader._update_runtime_shadow_context вызывается ДО старта прежнего object-profile.
При смене quantized receivers он синхронно обходит runtime shadow props; Prop→RuntimeShadowLOD
проверяет eligibility/границы/материалы и при необходимости возвращает/создаёт caster proxy.
Подтверждена крупная CPU-стоимость всего этого вызова в воспроизводимых рывках; цена отдельных
внутренних проверок/restore ещё не разделена. Это основание для следующего ограниченного
среза теней, не доказательство всех причин длительной просадки автора и не разрешение убрать тени.

**Проверенная сторона подхода.** [Разработчик Godot15.09.2026](https://godotengine.org/article/rendering-cpu-optimizations/)
и [NVIDIA27.10.2026](https://docs.nvidia.com/nsight-graphics/UserGuide/expected-workflow.html)
требуют сначала определить ограничивающий CPU/GPU путь. Текущий замер даёт основание
сначала сокращать повторную CPU-работу теней у прежних owners. Штатные instancing/nativeLOD
и существующий compute/indirect не заменять из-за общего primitive monitor.
[RenderingServer](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-measured-render-time-cpu)
разделяет viewport render,frame setup и scripts; [RenderingDevice](https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html#class-renderingdevice-method-buffer-get-data)
предупреждает о блокировке GPU при sync readback. Поэтому эти величины/окна разделены.
Современный [GPUOpen grass2024](https://gpuopen.com/learn/mesh_shaders/mesh_shaders-procedural_grass_rendering/)
сохраняет покрытие при дальнем сокращении геометрии; mesh shaders не являются согласованной
зависимостью/готовым путём stock Godot. Внедрение новой технологии не требуется этим диагнозом.

Evidence:`C:/Users/novos/Documents/Codex/2026-11-04/ember-density-camera-audit/`:
run1/audit.json — density/старт;run2/audit.json — положение snapshot/чистый кадр/GPU;
run4/audit.json+timing-attribution.json — привязанные CPU events;run3 — промежуточный probe,
чьи frame summaries неполны,не использовать их для суммарной атрибуции. Парсерные ошибки
временной инструментации устранены до рабочего запуска. run1/2/3/4 runtime errors0,
no game saves/8important сохранены; temporary production-owner copies возвращены побайтно.
`Run-Audit.ps1`,`Run-Snapshot.ps1`,`Run-Attribution.ps1` — воспроизведение в прежнем внешнемQA;
последний сохраняет изменённые исходники, проверяет baseline и возвращает временные замеры.
Точные payload/семантика счётчиков/JSON snapshot проверены; старый save/reopen native mask
принадлежит test_grass_mask_storage,его успешные независимые проверки заново не запускались.

### Полный порядок продолжения04.11 — пять рабочих блоков

Это маршрут оставшейся работы, не обещание закончить за пять правок или пять запусков.
Подробный диагностический протокол и условия исправлений — в разделе04.11 выше.
Прежние пункты1–5 после отдыха03.11 не удалены: инструмент кадра и QA-управление
технически готовы; physics/recovery/shared materials имеют свои результаты; материалБ
выбран дляQA; streaming реализован, но подготовка/полный кадр/приёмка остаются OPEN.
Четыре пункта краткого ответа в чате были группировкой, а не сокращением очереди.

1. **Доказать причину просадки.** Плотность/семантика счётчиков/матрица100–50–10–0%
   и отдельный camera-only маршрут с восстановлением; очереди, shadow-context, повторные
   расчёты и реальныйGPU-диапазон. Результат: факты, отвергнутые гипотезы, измеренная причина
   либо конкретный пробел. Диагностика04.11 выполнена:плотность/семантика установлены,
   измерен CPU shadow-context;постепенное140→60 не воспроизведено. Подробности выше.
2. **Исправить измеренную причину и проверить жизненный цикл.** После согласования —
   один ограниченный срез существующих owners; при необходимости сравнение представлений,
   а не бесконечные локальные cuts. Сюда относятся source preparation40с/return27с,
   публикация/отмена/освобождение, цена пула и подготовленные runtime-данные. Проверить
   исправленный маршрут/возврат и затронутые инварианты; не обещать заранее, что дело в чанках.
3. **Закрыть NPC/анимации в совместном кадре.** Найденный transition timer, цена native
   fallback и physics/activity; шесть независимых анимаций, восемь важных героев,32ordinary.
   Проверить время переходов/поз и offscreen/return. Техническую six-clip parity не повторять
   без относящихся изменений; новая модель качества/physics или engine fork не разрешены.
4. **Довести выбранную растительность и визуальные регуляторы.** Художественный preset
   автора; точный Dylearn billboard/UV вместо неполного cylindrical варианта; действующие
   LOD/дальность травы и цветов; streaming цветов вместо fixed-start; стоимость материалов/
   overdraw. Деревья/кусты: фактический nativeLOD, силуэт крон/ветер/ягоды и необходимость
   упрощения — по измерению и согласованию вида. Не снижать плотность/дальность радиPASS.
5. **Совместная приёмка и решение о переносе.** Один относящийся dense-маршрут с реальными
   NPC/harvest/props/светом: native1440p, FOV40/70/широкий/наклонный вид, движение/стыки,
   cold/return/телепорт, p95/p99/max и память. Сначала качество/120FPS и ручная оценка вQA;
   production migration согласовать отдельно и закрыть на единой main-карте. GTX1060/iGPU —
   отдельный профиль с согласованной целью, не обещание120FPS. Город/локальные источники/
   новыеэффекты — последующая нагрузка; не объявлять её принятой нынешним срезом.

Каждый блок заканчивается наблюдаемым результатом и одним следующим действием.
Повторная диагностика нужна при новом противоречии/изменении, а не автоматически.
Пакет передачи04.11 — навигационный снимок этой очереди; её owner остаётся этот документ.

### Сводный аудит02.11 — факты и следующий план

По запросу автора проведён read-only аудит двумя помощниками: Astra/high —
доказательства/целый кадр/движок; explorer — фактические LOD/activity/residency paths.
Координатор проверил готовые механизмы Godot и опубликованные подходы открытых игр.
Автор согласовал выполнение плана02.11. Шаг1 выполнен во внешней QA-копии одним
worker; шаги1–2 и opt-in активность шага3 проверены. Следующий — шаг4:
native skin/morph/submission и CPU/render thread; качество/плотность/дальность прежние.
Engine fork/новый renderer/миграция земли этим не разрешены.

**Что доказано и что нельзя заключать из55FPS.** Последний FOV70 с40полными rig
даёт18,236мс wall median; все39crowd meshes пересекают кадр. Подменён32м terrain
crop внутри576м источника, не весь мир. Без render timers прежние controls дают
17,724–18,407мс: только измерительными накладными расходами провал не объясняется.
GPU6,473мс не складывается с wall/physics/render CPU; physics monitor повторяет
одни значения на нескольких кадрах и не доказывает цену исключительно Jolt.
Главный первый приоритет — CPU/синхронизация, но прежние GPU p95>8,33мс тоже OPEN.
Одно отключение всех visual callbacks давало12,944мс, world callbacks14,080мс;
их эффекты пересекаются. Совместный остаток теперь измерен — пункт1 ниже.
Общий потолок55 опровергнут пустым контролем, цена native хвостов/утечка не установлены.
Простой rig controller не является production AI.

**Покрытие этапов по фактическому коду:**

- Рендер/culling: Godot frustum и native mesh LOD уже используются. Offscreen
  caster может оставаться нужен для видимой тени. Собственный shader/pass cost,
  submission и GPU skinning/morph за кадром не установлены одним script scheduler.
- Анимации: ordinary pose/blink — full/30/15Hz по дальности,5Hz offscreen,
  hidden2Hz; near offscreen full ради теней. Это существует, не новая задача.
  Important/party full-rate даже hidden; их качество сохраняется. До scheduler
  остаются ежекадровые visual checks. Bone LOD/pose sharing отсутствуют;
  index LOD не уменьшает skin streams/кости, morph meshes пропускаются.
- Физика/логика: stress controllers делают move_and_slide каждый physics tick.
  Анимационный LOD не выключает их. Теперь явно разрешивший это controller может
  заснуть через WorldRecovery и отпустить floor anchors;неизвестные Character и
  все доступные RigidBody,включая sleeping/frozen,сохраняют прежние опоры.
- Residency/память: часть статических collider снимается, grass MultiMesh/cache
  освобождаются; исходные props/ресурсы и NPC instances остаются. Полного
  distance unload NPC нет. Hidden/frozen/detached/freed — разные состояния.
- Подготовка: workers/очереди/отмена есть; GPU upload, instantiate, attach и часть
  collision construction остаются в main thread. Лимит на очередь не гарантирует,
  что отдельная неделимая публикация уложится в него. Cold/teleport считать отдельно.
- Свет/материалы: упрощения и static-prop shadow proxies подключены; production
  lightmap/shadowmask ещё нет. Нельзя писать «всё запекли». Temporal sun cascade
  cache отложен при штатном Godot; очередной bake не обоснован текущим CPU провалом.
- Масштабирование: GTX1060, полный RAM/VRAM release-return, wind/wet/city/light
  нагрузка ещё не приняты. RTX5070 результат не обещает производительность слабого ПК.

**Согласованный порядок — пять проверяемых результатов; сейчас шаг2:**

1. **Контроль общего кадра и совместного остатка — завершён02.11.** QA-only
   subclass прежнего cpu-hub, без root code diff. Full A/B/C median18,173/17,452/
   17,331мс, p9524,052/22,355/22,659. Совместно выключены40visual callbacks,
   39fixture controllers,562world callbacks(grass268/map1/props60/other233) и
   springs; player physics сохранена. Joint median6,848мс,p958,216/p9918,517/
   max34,839;3,747%кадров>8,33. Эти отключения замораживают поведение и не являются
   production оптимизацией. Их общий эффект не складывать с прежними отдельными cuts.
   Выбрана ветка CPU scheduling/ready-world checks; универсальный engine/render
   floor выше8,33мс для этой фиксированной сцены не подтверждён. Tail trace остаётся OPEN.
   MCPRuntime polling OFF даёт17,409мс,p9523,200 — внутри соседнего full дрейфа,
   отдельного выигрыша нет. EmberExploreProgress и hidden LightingBenchmark delta
   sampler сохранены; profiler/GPUtimers OFF. Не заявлять отсутствие всех наблюдателей.
   Corrected empty actual2560×1440/TAA/MSAA0/Forward+/Vulkan: median0,832мс,
   p957,575/p999,394/max12,028;1946frames≥3с,14visible/44shadow primitives,2draws,
   безautoloads. Это контроль потолка, не shipping/120minimum PASS. Console engine,
   без export/release. Jolt60Hz/uncapped/VSyncOFF;CPU i5-13600K/RTX5070 driver617.14.
   Native+empty exit0,engine/script/device errors0;20verification checks PASS.
   Camera/process/modes/springs8/0 exact restore,5319public MeshInstances и
   1684CollisionShapes с теми же identities;25848patches/268resident/220135grass
   instances exact,fallen0,SourceSHA exact. Internal grass MultiMesh identities не
   сняты generic public traversal — это граница доказательства, counts проверены.
   Первый native отвергнут из-за typed-array guard в helper, исправленный принят;
   первый emptyMSAA2 неauthoritative, заменён одним correctedMSAA0. Не повторять их.
   Evidence:`C:/Users/novos/Documents/Codex/2026-11-02/ember-frame-residual/`:
   `native/result.json`, raw samples, `empty-corrected-result/result.json`,
   `verification.json`, `invocations.json`, `frame_residual.gd`, logs/preflight.
   Для повтора helper сначала вернуть в QA `tools/qa_frame_residual.gd`;
   invoke-native/empty-corrected содержат точные вызовы. Сейчас helper снят,
   owned children0, env/project/override/.gdignore и весь dirty status сохранены.
2. **Обслуживание мира — grass/MapLoader исправлены, Hoshi обвязка проверена02.11.**
   В existing GrassPatch ранний возврат теперь предшествует `_world_area()`,
   когда epoch/revision/transform/paint mode/map unit/material/shader/anomaly
   неизменны. Size edits по-прежнему dirty. Новый scheduler/cache owner не добавлен;
   усложнённый candidate кэширования projection отклонён как неокупившийся.
   Новый regression в `test_detail_poll_epoch` воспроизводит прежний лишний query
   (baseline RED), final Forward+ GREEN: unchanged/query,paint mode/unit,material/
   shader/context replacement,source revision/transform/dirty. Native fade и
   `test_grass_clean_resident` также PASS: fade/residency/readiness/rebuild и
   rotated/scaled/reparented/Undo-style bounds;Source/формат/сохранения не менялись.
   Same-process old/new/old/new/old,40rig/FOV70/native2560×1440/timersOFF:
   старые median18,075/17,914/17,923мс; новые17,605/17,794мс. Относительно среднего
   соседних controls выигрыши0,390/0,125мс — небольшой эффект≈0,25мс, не прорыв FPS.
   New p9523,187/23,459,p9933,332/30,976,max40,986/39,444;tail/120FPS gate OPEN.
   Все resident grass mesh/material/MultiMesh IDs и instance buffer hashes совпали
   в5интервалах,плотность/дальность/акторская нагрузка прежние. First candidate
   comparison также содержит actual short out/return2legs/195frames,floor/fallen0,
   pending0;268→284→284resident допустимы как hysteresis/неточный возврат. Это не
   full-distance release или закрытие прежнего coverage gate. Простая final правка
   возвращает прежний map lookup,не меняет опробованную fade/residency логику.
   Native comparisons/focused checks exit0,errors/leaks0. QA-only hooks сняты,
   staged grass совпадает с root. Evidence:
   `C:/Users/novos/Documents/Codex/2026-11-02/ember-ready-grass/`:
   minimal/result.json + engine.log,comparison/result.json,poll/clean-resident.log,
   before/final scripts,comparison helpers,scoped patches,verification.json.
   Profile counters inclusive/instrumented,их≈1,7мс не считать exclusive scope.
   MapLoader02.11: instrumented process≈0,7мс/callback,physics≈0,6мс/tick;
   основное — object poll и activity checks, shadow-context≈0,07мс. Это inclusive
   profile scopes с overhead,их не складывать с CPU/GPU/wall.
   ПрямаяScript identity вместо повторногоload в physics/shadow guard проверена,
   whole-frame gain не установлен и ОБЕ правки откатаны. Не повторять этот candidate.
   Принят другой measured path: одновременное обновление позиций многих anchors
   больше не читает bounds всех suspended props отдельно на каждого участника.
   `_restore_physics_near_points` делает один проход по пропам с текущими bounds и
   проверяет все возвращающиеся точки; single-point path и36/48м/4м thresholds прежние.
   Нет сохранённого bounds cache,нового spatial index/owner или задержки восстановления.
   На той же native576м/40rig нагрузке62anchors/556suspended принудительная activity
   invalidation через реальный `_physics_process` стоила old56,293–64,056мс,
   new6,538–6,661мс,old-return55,292–57,630мс (по4операции). Это controlled
   source-edit/return-equivalent burst,не установленная причина старых natural stalls.
   Clean full кадр old17,819/new17,690/return17,863мс — устойчивый заметный FPSgain
   не заявлен;newp9522,996/p9935,215,120FPS/редкие паузы остаются OPEN.
   Все geometry/material/collider IDs иSourceSHA сохранены,floor/fallen0. Native
   final `test_runtime_physics_activity` PASS:single/multi actor/teleport/source edit/
   return;новый45-anchor bound-query regression baseline RED/final GREEN и последний
   участник получает floor. Native batch exit0/errors/leaks0,QA hooks сняты.
   Evidence:`C:/Users/novos/Documents/Codex/2026-11-02/ember-map-activity/`:
   batch/result.json+engine.log,final-physics.log,batch-red.log,verification.json,
   map-before/map-accepted/scoped patches,batch-harness и rejected comparison.
   Регулярный object poll не выключен. Новые MapLoader микро-кэши без причины не вводить.
   Hoshi02.11: тот же dense576м/40rig/native1440p/FOV70,timersOFF. Instrumented240frames:
   importance lookup≈0,11мс/frame,вложенный party ancestor walk≈0,07мс;ради такой цены
   role-cache/invalidation не добавлен. Hoshi process≈1,35мс inclusive,внутри него
   AnimationPlayer.advance≈0,67мс;эти числа не складывать и не вычитать из абляций.
   Skeleton.advance≈0,014мс лишь ставит часть работы в очередь,не измеряет весь skeleton.
   По [исходнику Godot4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/scene/3d/skeleton_3d.cpp)
   список modifiers включает inactive children;наличие списка сохраняет полный bone backup.
   Проверен QA-only stock detach32inactive ordinary springs;8important и частота прежние.
   Attached/detached/attached/detached/attached median18,297/18,214/17,823/18,611/17,870мс,
   p9525,097/24,810/23,908/25,791/23,256. Устойчивого whole-frame gain нет: candidate REJECTED.
   Топология/owners/порядок children восстановлены,geometry/material/collider IDs exact,
   fallen0,errors/leaks0;root Hoshi/LOD не менялись,QA helper снят. Повтор без новой причины не нужен.
   Evidence:`C:/Users/novos/Documents/Codex/2026-11-02/ember-hoshi-callback/`:
   profile/result.json,modifier-probe/result.json,engine logs,оба harness,verification.json.
   Role-cache/detach,grass/MapLoader и общую CPU-диагностику без причины не повторять.
3. **Активность NPC02.11 — opt-in sleep/wake подключён; AI/Source paging OPEN.**
   У existing WorldRecovery controller с `runtime_simulation_required()->bool` владеет
   потребностью в симуляции;неизвестные actors и RigidBody не замораживаются автоматически.
   Sleep останавливает только physics callback,сохраняет узел/позу/velocity/state и
   снимает его floor anchor. Wake сначала возвращает anchor/опоры,затем ждёт готовый
   пол;priority-200 перед Map-100/движением. Cancelled wake,independent pause,
   снятие opt-in при wake,выход из World3D/удаление owner сохраняют владение callback.
   [VisibleOnScreenEnabler3D](https://docs.godotengine.org/en/stable/classes/class_visibleonscreenenabler3d.html)
   управляет process_mode по видимости:для whole actor не выбран,так как Ember нужны
   отдельные shadow/gameplay demand и floor hold;подходит для чисто визуального subtree.
   Текущий consumer — passive PopulationActor стресс-теста,не production AI:64м near
   и консервативный64м frustum/shadow margin;важные герои всегда требуют simulation.
   Same-scene native1440p/FOV70/timersOFF,8important+32ordinary:далеко128м live/on/live/on/live
   median14,241/11,585/14,201/11,638/14,014мс;выигрыш≈2,55мс. Dormant31,anchors62→31,
   fine floor417–419→401–402;один shadow/view-needed NPC намеренно остаётся активным.
   On p9514,158/14,719,p9923,321/23,210,max42,909/33,171:120FPS OPEN.
   Near loop-only check при always-required demand18,027/18,101/17,914мс;это не
   точный A/B стоимости полной near policy. После возвратов default policy18,208мс;
   выигрыша рядом нет. Все32ordinary рядом видны и в≈11м:distance unload их не ускоряет.
   Два128м out/return:far dormant29/31,return0;anchors62,fallen/pending0,cohort IDs/Source SHA
   exact. Return nodes67776/67776,floor396/396,grass263resident/217048instances exact;
   engine static+0,49MB/video+0,29MB между возвратами — не полный OS/RID leak или release gate.
   Native focused RED→GREEN,final stress exit0/errors/leaks0;FOV40/70,near hidden и
   conservative far demand проверены. Фактический occluded/видимый shadow pixel gate,
   manual transitions,production AI/quest/combat demand,save-state paging и слабый ПК OPEN.
   Evidence:`C:/Users/novos/Documents/Codex/2026-11-02/ember-actor-activity/`:
   final/result.json+raw/log,physics-final.log,RED logs,verification.json,scoped patches/harness.
   Native unregistered-point preload и harness с обязательными32sleeping отвергнуты;
   правильный return перемещает удерживаемое registered body до ожидания пола.
   Preload ещё не зарегистрированной позиции требует отдельного destination-lifetime
   решения у существующего projection owner;не считать нынешний prepare мгновенным teleport.
   Полные NPC/Source instances остаются resident;выгрузка требует реального AI/save owner
   и цены памяти. Сейчас следующий шаг4 закрывает near CPU/render стоимость,не повтор sleep A/B.
4. **Цена видимых персонажей02.11 — main-thread limit доказан; threading gate OPEN.**
   Тот же40rig/native1440p/FOV70/TAA/MSAA0:GPU median6,256мс,p956,810;
   render CPU4,630мс,wall≈18мс. Windows thread counters:один самый ранний поток
   занимает3922из4060мс≈97%ядра,весь process≈1,17логических ядер. Это CPU execution,
   не доказанная долгая GPU wait;thread counters не являются native function profile.
   У avatar3mesh/22surfaces/33240base vertices/136bones/57face morphs;скрытие только
   геометрии32ordinary при живых controllers/animations даёт13,060мс и2040→856draws:
   ≈37draws/rig. Это counterfactual,не принятая меньшая плотность.
   Stock [custom_aabb](https://docs.godotengine.org/en/stable/classes/class_geometryinstance3d.html#class-geometryinstance3d-property-custom-aabb)
   A/B/A/B/A:18,271/17,557/18,132/17,567/18,018мс. Broad bounds
   дали≈0,58мс,ноvisible≈4,86→5,30M/shadow≈5,6→6,5M из-заLOD/culling. Не внедрены;
   возврат только после animation-envelope/pixel/shadow/LOD gate. Material sharing/merge не проверены.
   По просьбе автора проверен stock `--render-thread safe/separate/safe`,без изменения
   project.godot:main/render engine IDs1/1→1/5→1/1;Safe medians17,827–18,137 и17,886–18,054мс.
   Separate первый interval14,182,p9518,633;два прогретых10,676/10,621,p9512,933/12,569,
   p9915,285/18,346,max34,634/33,049. Два активных native CPU потока подтверждены.
   Скриптовая корректность/Source/cohort IDs/full39controllers/8important/floor PASS,
   но6native texture-update errors:Separate НЕ принят. В stock Godot он
   [экспериментальный](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html).
   Ошибка совпадает с [подтверждённой гонкой font atlas](https://github.com/godotengine/godot/issues/122206),
   но локальный font-only992frames её не повторил:не объявлять источник всех6ошибок доказанным.
   Этот независимый пример без Ember дал вSeparate finalize-thread error/2ObjectDB leaks,
   Safe чистый;shutdown stderr отдельно вfont-only/console-shutdown-excerpt.txt,файловый log его не содержит.
   Возврат кSeparate — после error-free font/startup/exit и render/physics/editor gates;
   fork/смена движка не согласованы. Startup≈43k sync diagnostics не переносить на steady кадр:
   во2/3clean intervals новых warnings нет;GPU/timer-query interval сам синхронизирует потоки.
   Проверка native Skeleton process groups и pure pose sampling завершена ниже:
   workers действительно задействованы,whole-frame выигрыш не получен. Следующий
   gate — стоимость terrain motion queries (native profile получен ниже);новый animator/parallel
   manager без такого обоснования не вводить. Physics/партия/importance/save owners прежние.
   Evidence:`C:/Users/novos/Documents/Codex/2026-11-02/ember-visible-rigs/`:
   native/,safe_A/,separate/(engine.log.gz),safe_B/,font-only/,samplers/harness,verification.json.
   Production-код/настройки не менялись;120FPS OPEN. Cold destination lifetime и
   terrain authoring gates прежние (шаг3);не повторять общий renderer/terrain A/B.
5. **Одна совместная приёмка и слабый ПК.** Повторить неизменённый dense маршрут
   native2560×1440/FOV40/70, static/wide/move/cold/return; wall/CPU/GPU,p95/p99/max,
   coverage и память. Цель120FPS не выполнена одной хорошей средней. После
   конкретного выигрыша на основном ПК запускать тот же revision на GTX1060;
   разрешение/качество/порог для него согласовать отдельно. Недоступность второго
   ПК не блокирует первые срезы. Новый городской контент не добавлять ради диагностики.

**Принципы и остановка.** Culling, simulation throttling и выгрузка не подменяют
друг друга. Асинхронное чтение не гарантирует дешёвую публикацию. Неизменные
данные не должны заново готовиться каждый кадр; cache identity включает источник
и его revision/содержимое. Локальный PASS и число треугольников не принимают весь
кадр. Каждая следующая правка связывается с измеренной причиной; успешные проверки
без новых рисков не повторять. Не возвращаться к cached spring axes, constant
tracks, VoxelProp микроправкам, чужому общему PresentMon маршруту и снижению бюджета,
которое уже теряло coverage. Сохранять отдельный gate редких старых stalls/PSO,
не объявлять все выбросы ни компиляцией, ни системными скриншотами без trace.

Owners кода: `ember_animation_distance_lod`, `ember_hoshi_visual`,
`ember_world_recovery`, `ember_map_loader`, `ember_detail_preparation`,
`ember_grass_patch`, прежний projection; новый parallel manager не согласован.
Evidence: CPU-раздел01.11 и primary-source раздел02.11 выше; минимальные будущие
команды/результаты сохранять в их evidence, не создавать второй backlog.

### Многопоточность игры и редактора02.11

Контракт автора: использовать штатный Godot,готовые фоновые механизмы и прежних
owners;устранить последовательную дорогую работу без снижения плотности,дальности,
частоты ближних NPC и качества8важных героев. Astra/high проверяет границы runtime
thread safety,explorer — существующие editor paths;оба read-only,координатор пишет
и проверяет. Это продолжение шага4,не новая программа оптимизации/миграция движка.

**Уже работает.** На текущем i5-13600K14cores/20threads WorkerThreadPool max_threads=-1,
low_priority_ratio=0,3;shader cache и pipeline cache включены. Save chunk64MB —
порог порции сохранения,не максимальный размер кэша. Terrain shape/preparation,
scatter/cache reads,threaded ResourceLoader и recovery уже имеют фоновые paths.
Нагрузка одного главного потока не означает,что весь Ember до этого был однопоточным.
Новые очереди вместо этих owners не создавать. Минимальный CPU ещё не выбран;
GTX1060 не определяет CPU второго ПК,фиксированное число workers всем ПК не задавать.

**Проверено на той же нагрузке.** Safe/native1440p/FOV70/TAA/MSAA0,8important+32ordinary,
39controllers/62anchors:только32ordinary Skeleton3D имеют отдельные группы order1,
после main pose writes order0;important/камера/physics/importance/blink прежние.
Skeleton_updated подтвердил main ID1→20worker IDs→ID1. Main/workers/main/workers/main
wall median17,832/18,258/17,810/18,569/17,697мс;worker p9524,806/24,242мс,
main p9523,061–24,131. Все32×136 global bone poses совпали для idle/walk/run и
возврата,geometry/skin/material IDs/Source SHA exact,fallen/pending0,native errors0.
**Отдельный перенос Skeleton отклонён по регрессии всего кадра**,а не из-за
недоказанного визуального дефекта. Повтор только при изменении размера задач/
native bottleneck,не ради большей загрузки ядер. Production Hoshi/настройки не менялись.

Pure sampler component отдельно:32rig/55rotation+1position track,4private jobs,
immutable native Animation interpolation→barrier→main bone setters;idle/walk/run
poses PASS. Serial≈0,31–0,36мс,parallel≈0,29мс,native AnimationPlayer.advance≈0,37–0,47мс,
native return≈0,41–0,48мс. Это только sampling/apply scope,не gameplay/frame PASS;
crossfade/LOD/skin submission не заменены. Ради≈0,1–0,18мс не вводить второй animator.

**Границы движка.** В4.7.2 обнаружен неатомарный redraw counter `changes++` перед
очередью bone commands. Это source-level C++ data race при пересечении потоков;
потеря bone commands/повреждение позы локально не показаны. При
OS.low_processor_usage_mode=false решение draw не зависит от `has_changed()`.
Не связывать это с Separate texture errors и не удалять рабочий ResourceLoader.
Источники: [command wrapper](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/server_wrap_mt_common.h#L342-L351),
[counter](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/rendering_server_default.h#L102-L120),
[draw loop](https://github.com/godotengine/godot/blob/4.7.2-stable/main/main.cpp#L5085-L5096).
Настоящий [Godot editor отключает Node threading](https://github.com/godotengine/godot/blob/4.7.2-stable/editor/editor_node.cpp#L927);
F6/gameplay — другой режим. Для editor применять WorkerThreadPool с immutable snapshot,
revision/cancel и main-thread publication;UI/Undo/Resource/mesh/collision остаются у прежних owners.

**Порядок дальнейшей работы.** Native CPU hot functions получены ниже:крупный расход —
CharacterBody motion queries по детальной земле. Простая смена HeightMap на полный
triangle mesh отклонена. Перед дальнейшими локальными правками сравнить готовый
способ движения массовых NPC и физическое представление поверхности;новый controller/
движок требует отдельного архитектурного решения. Shader warmup не выдавать за ускорение
steady кадра. Не переносить
move_and_slide/чужие Nodes в workers и не вводить новую систему под гипотезу.
Для editor отдельно нужны main-copy baseline и разбивка snapshot/job/publication/release;
старые60FPS fixtures и обрезанная3×3 queue не принимают dense editing. Затем повторить
только связанный общий маршрут из шага5;не повторять уже отклонённые опыты без новой причины.

Canvas release trace исправлен: `pointer_up.inclusive_usec` теперь включает
`worker_completion`;раньше ожидание smooth/plane worker было до начала scope.
`test_voxel_editor_release_trace.gd`:контролируемое40мс ожидание RED≈46µs→GREEN≈40,1мс;
без trace поведение/число ожиданий прежние. Это исправление измерения,не ускорение кисти.
Native editor baseline:копия основной72×72м карты1152²columns,все324tiles/очередь,
реальный viewport1501×1164/FOV70,uncapped/vsync OFF. Это не576м игровой stress.
Начальная подготовка:324worker jobs/972publication steps,очередь0;наведение
через существующие pick+overlay≈5,6–13,7мс. Raise32steps:stamp median17,323/p9527,088/
max46,560мс,release12,015мс;полное завершение сsettle27,82с. Smooth32steps:
28,857/45,114/167,609мс,release1,812мс,сsettle2,43с. Эти scopes не складывать с
worker CPU totals. Recovery12,5с:frame median5,532/p958,138/max25,577мс,очередь0,
Source validation PASS. Родные Undo/save здесь не менялись и повторно не принимались.
Scripted command pass не принимает native editor shutdown:после DONE get_node outside
tree error/7ObjectDB leaks;причина не установлена. Первый QA запуск потерял entry
при асинхронном scene switch и не является baseline;во втором session binding исправлен.
Для следующего editor среза отдельно измерить pick против overlay и gather/snapshot
против публикации;не переносить UI/Undo/активный Resource в workers. Ручное наведение/
отпускание,полный dense editor масштаб и общий120FPS остаются OPEN.
Evidence:`C:/Users/novos/Documents/Codex/2026-11-02/ember-multicore/`:
engine-settings.json,pose-sampler.json,skeleton-groups/result.json+raw,
editor-baseline.json/editor-baseline-final.log,release-red/green.log,scoped QA harnesses.
Не принимать component PASS вместо кадра.

### Нативный профиль кадра и release02.11

Завершён следующий согласованный диагностический шаг,без изменения production-кода.
Внешняя копия неизменённого Godot4.7.2/ed1daf0bf собрана MSVC с
`production=yes debug_symbols=yes separate_debug_symbols=yes`;D3D12/accesskit отключены
только в диагностическом бинарнике,используется прежний Vulkan Forward+.
Официальный Windows binary не имеет symbols — это [ограничение поставки](https://docs.godotengine.org/en/stable/engine_details/development/profiling/index.html),
а не причина медленного кадра. Рабочий Godot не заменён,engine fork не принят.
Готовый Very Sleepy0.91 захватил main thread8,031с/3157samples с локальным PDB;
два чистых интервала до профилировщика≈17,308/17,349мс. Сборка — диагностическая,
не строгий compiler-equivalent performance A/B официальному бинарнику.

На прежнем native1440p/FOV70/TAA/MSAA0/scale1,8important+32ordinary:
- `CharacterBody3D::move_and_slide`≈37,7% веса выборок main;внутри него
  `JoltPhysicsDirectSpaceState3D::body_test_motion`≈35,2%,height-field convex collision≈30,9%.
  Floor snap≈15,6% и recovery≈17,5% вложены в этот путь;проценты не складывать.
- `RenderingServerDefault::draw`≈17,3%,native Skeleton notification≈4,7%.
  Это named paths,не вся цена renderer/анимаций. GDScriptFunction::call≈71,7%
  inclusive включает native physics;exclusive VM≈4,9%,не обвинять интерпретатор в71,7%.
- Взвешенные samples — оценка времени в профилированном интервале,не точные
  exclusive миллисекунды чистого кадра. Сам harness в ожидании capture делает file-exists poll.

**Подтверждённая граница API:** [PhysicsServer3DWrapMT::body_test_motion](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/physics_3d/physics_server_3d_wrap_mt.h#L273-L281)
прямо отклоняет вызов вне main thread. [Builtin Jolt создаётся через эту обёртку](https://github.com/godotengine/godot/blob/4.7.2-stable/modules/jolt_physics/register_types.cpp#L44-L50).
WorkerThreadPool/Node groups/отдельный physics thread не отменяют этот guard.
Это ограничение текущего CharacterBody-пути,не доказательство однопоточности всей физики.

Проверен готовый exact triangle fallback на официальном движке:396resident shapes,
те же canonical faces/3,244M triangles;только физическое представление,не render LOD.
Height/triangles/height/triangles/height:wall median18,856/21,110/19,584/20,925/18,438мс,
triangle p9530,865/29,461 против height24,684–26,301. Вариант отклонён по регрессии.
Rays совпали до7,63e-6units/normal1,19e-5;bool160motion queries без расхождений,
max travel delta0,00896units≈0,56мм превысила заранее выбранный0,005units gate.
Возврат восстановил shape Resources/positions;fallen/pending0,39controllers и62anchors
сохранены. Script PASS этой пробы не объявлен,новую tolerance ради PASS не вводить.

**Отдельный release baseline:** официальный4.7.2 template,debug/editor features false,
native1440p/FOV70/TAA/MSAA0/scale1,тот же dense576м/8important+32ordinary/39controllers,
62anchors/396floor tiles/220135grass+flowers+wheat. Wall median15,645/16,340мс,
p9517,720/19,054,p9921,383/27,119,max47,412/37,550;все480frames выше8,33мс.
Correctness/8heroes quality/floor PASS,native errors0;120FPS OPEN. Это независимый
baseline,не чистый release-vs-editor A/B:packaged resources,отключён MCP autoload,
different static-physics residency counts. Старые release пробы28.10 были без Hoshi/crowd.
Первые упаковки не являются baseline:неполные dependencies,editor-only MCP,неперенесённый
QA override/Jolt иmissing exported GDExtension. Итоговый pack использует merged runtime
settings,свои DLL иimport remaps;raw SHA упакованного `.tscn` недоступен,исходный scene
и внешние fixture SHA защищены вне пакета. Рабочие карты/настройки не менялись.

**Вывод и следующий gate:** потокам мешает конкретный synchronous API и цена контактов,
а не выключенный общий multicore флаг. Готовый RigidBody/Jolt проверен ниже:частичный
выигрыш подтверждён,поведение не эквивалентно. До переноса согласовать требования к
ordinary controller (контакт сдинамическими объектами/ступени/AI/save),затем адаптировать
готовый путь только при сохранении этих требований. Точное упрощение физической
поверхности остаётся альтернативой,не уже выполненным срезом. Не снижать physics
frequency/контакты молча;important качество и единая поверхность сохраняются.
При незакрытом бюджете — ограниченный одинаковый междвижковый стенд до миграции.
Unity [Jobs](https://docs.unity3d.com/6000.0/Documentation/Manual/JobSystemOverview.html)
и [Entities Character Controller](https://docs.unity3d.com/Packages/com.unity.charactercontroller@1.4/manual/index.html),
Unreal [parallel AnimGraph](https://dev.epicgames.com/documentation/unreal-engine/graphing-in-animation-blueprints-in-unreal-engine)
дают готовые альтернативы;не заменяют измерение Ember. У Unreal async Character Movement
также [отмечен недоработанным](https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-engine-console-variables-reference),
поэтому не обещать переносом автоматические120FPS. Принятого выбора другого движка нет.

Evidence:`C:/Users/novos/Documents/Codex/2026-11-02/ember-native-frame/`:
build-native.cmd/log+source SHA,symbols-native/main.sleepy/hot-functions.json,
collision-frame/result.json+raw,release-merged/result.json+raw/log,QA harnesses/verification.
Нативный профиль теперь воспроизводим без повторной сборки и без Computer Use.

### RigidBody/Jolt для обычных NPC02.11

Согласованная обратимая QA-проба на официальном Godot4.7.2 Forward+/Jolt,Safe:
тот же dense576м/native2560×1440/FOV70/TAA/MSAA0/scale1. Только32ordinary заменены
на штатный RigidBody3D с `_integrate_forces`;8important остаются CharacterBody.
Та же capsule shape/layers/masks,те же MeshInstance/Mesh/Skin/material IDs,
39crowd AnimationPlayer играют во всех интервалах,8hero springs активны.
Новые тела не frozen/sleeping,physics frequency прежняя;переключение вне замера.
Это иной способ управления телом,не автоматическое распараллеливание CharacterBody.
Рекомендация штатного API — [RigidBody3D](https://docs.godotengine.org/en/stable/classes/class_rigidbody3d.html).

Чистое A/B/A/B/A по240frames:Character wall median18,307/19,107/18,311мс,
Rigid16,183/16,681мс;около2мс/11–12% выигрыша. p95 Character23,978–24,962,
Rigid18,910–19,561; p99 Character32,097–40,493,Rigid29,532–31,223;
max Character42,354–62,129,Rigid37,622–39,801. Все1200frames выше8,33мс,
120FPS OPEN. Это engine-run comparison,не release A/B и не новая release оценка.
62anchors/396floor tiles/39NPC сохранены,fallen/pending0,источники SHA прежние.

Автоматические slope/flat/seam:idle drift0,стык пересечён;за2с путь Character
15,996–16,129units,Rigid15,729–16,121,uphill15,630vs15,223. Максимальное смещение
стопы от canonical floor≈0,008units≈0,5мм;это не проверка всех ступеней/препятствий.
Контакт ссуществующим ящиком **неэквивалентен**:Character сдвинул его≈2,16units,
Rigid≈0,008units,сам отклонился вбок≈2,52units. Поэтому controller **не внедрён**;
AI/save/ступени/ручное ощущение OPEN. Важные герои и production Hoshi/stress owner прежние.

При переключении воспроизведена ошибка WorldRecovery:живое тело вне SceneTree всёещё
читалось как участник мира. Owner теперь пропускает detached/другойWorld3D до возврата,
сохраняя pending support lease. `test_world_recovery_detached` native Forward+ RED→GREEN,
existing `test_runtime_physics_activity` Forward+ PASS;чистое сравнение native errors0.
Первая проба с native errors не является performance evidence.
Evidence:`C:/Users/novos/Documents/Codex/2026-11-02/ember-rigid-npc/clean/result.json`,
raw CPU intervals/clean log,regression logs и архив QA prototype рядом.
QA controller/visual adapter сняты после пробы;только исправление WorldRecovery и
regression остаются врабочем коде. Для возврата использовать этот архив,не повторять обзор.

### Массовые NPC: альтернативы представления02.11

Автор согласовал исследование Astra/high (Jolt) и Sol/high (готовая crowd animation),
оба read-only без вложенного делегирования;координатор владеет реализацией/QA.
Результат среза — убрать подтверждённые spawn/publication паузы и сравнить
представление32ordinary при прежних8important. Fork/замена controller не приняты.

- [Epic Mass Representation](https://dev.epicgames.com/documentation/unreal-engine/overview-of-mass-gameplay-in-unreal-engine)
  разделяет high/low Actor, instanced mesh и отсутствие представления; pooling/LOD
  встроены. Это пример разделения данных, симуляции и картинки, не доказательство
  внутреннего устройства Warframe/другой игры. Сохранять видимую плотность Ember.
- [Animation Sharing](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-sharing-plugin-in-unreal-engine)
  делит рассчитанные позы между совместимыми скелетами; существующая общая библиотека
  Ember этого не делает. [Animation Budget Allocator](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-budget-allocator-in-unreal-engine)
  управляет частотой по CPU-бюджету. Это разные методы; sampling-only опыт выше
  не принимает и не отклоняет полное instanced представление толпы.
- Готовый [Godot VAT/MultiMesh plugin](https://github.com/antzGames/Godot_Vertex_Animation_Textures_Plugin),
  MIT/Godot4.5+: GPU воспроизводит запечённые вершины, MultiMesh группирует отрисовку.
  Не подходит напрямую текущей Хоши. Ограничения README: модель
  <8192vertices, суммарно <8192frames, нет смешивания разных клипов; нужен Blender bake.
  Source:3meshes/22surfaces/33240used vertices;Hair surface19283vertices уже выше
  предела,а текущий crossfade0,18с нужен. Не установлен;demo FPS не являются Ember evidence.
  [shadecoredev native baker](https://github.com/shadecoredev/AnimatedMultimeshInstance3D)
  также ограничен8192 и вbaker читает толькоsurface0;не принимает наши22surfaces.
  Нужная адаптация выбрана по [instanced palette skinning](https://developer.nvidia.com/gpugems/gpugems3/part-i-geometry/chapter-2-animated-crowd-rendering),не по чужимFPS.
- [Jolt Character/CharacterVirtual](https://github.com/jrouwe/JoltPhysics/blob/master/Docs/Architecture.md#character-controllers-character-controllers)
  — готовые контроллеры: первый дешёвый rigid-body вариант, второй поддерживает
  конкурентные updates, но имеет свои правила контактов и порядка симуляции.
  В локальном source4.7.2 оба есть в thirdparty; Godot CharacterBody по-прежнему
  вызывает main-thread-only body_test_motion. Доступ к JoltSpace/PhysicsSystem
  найден во внутреннем C++ API, не как готовый публичный GDScript контроллер.
  Возможный ограниченный module/engine prototype должен использовать ту же physics
  space и canonical поверхность, безопасную фазу/locks и публикацию без обращений
  к SceneTree из workers. Это проверка интеграции, а не снятие thread guard.
  Astra уточнила:внутренние Godot helpers используютNoLock/общийtemp allocator;
  CharacterVsCharacterCollisionSimple vendored5.5 требует sequential calls,а
  raw Jolt bodies ломают ожидания Godot userdata. Нужны штатныеRID/proxies,отдельные
  scratch/locks и безопасная фаза. Готовой GDExtension без сменыbackend не найдено.

### Подготовка NPC и grass feature programs02.11

**Runtime исправления:**`EmberHoshiVisual` удерживает PackedScene/AnimationLibrary,
`prepare_resources(host)` использует штатный ResourceLoader и получает только
готовые scene/motion/toon+outline material templates. Stress populate вызывает его
до появления NPC. Старый sync setup остаётся для совместимости первого player:
не обещать,что холодный неподготовленный вызов стал мгновенным.
Реальный Hoshi spawn80actors/2раунда:baseline median445/439мс,max770мс;
удержание сцены даёт≈2,2мс повторно,а background prepare убирает первый cold resource/
material read из spawn. Prepared median2,143/2,064мс,max3,330мс;полная подготовка
занимает≈0,73с заранее,не исчезает. Это isolated spawn correctness/perf,не120FPS gate.
Source Scene/mesh/skin/clips/важность прежние;cache держит только один avatar asset,
это не полная выгрузка NPC/Source изRAM.

У травы настоящий dense startup выявил publish max73,1мс;разбивка повторила63,8мс,
из них63,6мс — `refresh_terrain_features`,buffer0,109мс. Owner Materials теперь
генерирует тот же текст по одному feature step;временный private ShaderMaterial
загружается штатным threaded ResourceLoader. ВGrass публикация ждёт готовности через
прежний budget dispatcher;live binding/Node не входят вworker. Одновременно≤2
генераций/загрузок,program cache32;изменившийся binding не получает старыйkey,
ошибка staging/loader сохраняет sync fallback. Временные файлы удаляются послеload.
Финальный dense:549warmup steps max2,117мс,p990,910;527publications max0,873мс,
p990,687,готовы220135instances/25848patches/268resident,pending0.
Source SHA/62anchors/396tiles/39NPC/8important сохранены,fallen/waiting/pending0.
Native correctness PASS/errors/leaks0;обычный native кадр17,740/17,593мс,
p9522,540/23,060,max47,356/52,756. Это проверка regression,не доказательство steady FPS gain.

`test_hoshi_resource_preparation`/existing Hoshi player PASS;
`test_terrain_feature_preparation`:coalescing,смена features,потеря последнего
binding,drain иbyte-equal sync/incremental code PASS;`test_terrain_material_features`
commands/все3looks/texture RID+pixel parity и`test_solid_far_material` PASS.

### Камера, повторная сборка травы и диагностические PNG02.11

Автор уточнил сценарий: запуск stress → персонаж/NPC → широкий ракурс.
В исходном `npc_visibility` чтение GPU-изображения занимало 13,6/15,4мс,
синхронное сжатие/запись PNG — 1223,9/1115,3мс; соответствующие wall-паузы
1286,8/1474,3мс. Это помеха от диагностики, не цена генерации травы.
Теперь штатный WorkerThreadPool пишет максимум два отдельных CPU Image;
viewport читается только на main. Задачи опрашиваются без блокировки и обязательно
joined до чистых замеров/выхода; ошибки записи входят в correctness result.
Тот же native1440p/FOV40/70 маршрут: enqueue 8мкс, readback 12,6/13,8мс,
PNG 1185,9/1112,2мс в фоне. На двух capture-переходах wall-пауз ≥80мс больше нет.
Оба файла сохранены; 39 NPC обрабатываются, FOV70 — все39 центров в кадре;
финально прежние 220135 instances/268 resident/pending0, source SHA прежние.
Фоновая запись полностью завершена до FPS-интервалов: это не игровой FPS gain.

Отдельно на готовой сцене шесть смен FOV40/70, polar0,95/0,45, distance95/140м:
все268 MultiMesh buffers прежние, release/rebuild/publication0. Этот warm-сценарий
не охватывал сам запуск. Повторное уточнение автора выявило отдельную ошибку stress:
`accept_world` после `npc_visibility` умножал размер всех grass/flower patches на1,25.
Setter помечал их dirty; показанная трава действительно росла и собиралась повторно.
Native воспроизведение: до камеры267 buffers, после259 resized/replaced,260 publications
(одна для нового участка); regression assertions RED. Теперь окончательный размер1,25
задаётся при создании patches до startup. Тот же маршрут GREEN:268→268 buffers,
resized/replaced/missing/publications0; прежние220135 instances, плотность64/10/8,
seed/Source/геометрия/тени/дальность и итоговый размер прежние. Runtime grass owner
не менялся; это устранение лишней операции сценария, не steady FPS gain.
Coverage всей панорамы, произвольная телепортация, стартовая подготовка fixture/harvest
и общий120FPS gate остаются открытыми.
Evidence: `C:/Users/novos/Documents/Codex/2026-11-02/ember-camera-grass/`:
`baseline/result.json`, `capture-baseline/result.json`, `capture-after/result.json`,
native logs и `verification.json`. Size regression evidence:
`C:/Users/novos/Documents/Codex/2026-11-02/ember-grass-startup/`:
`baseline/result.json` RED, `after/result.json` GREEN, `prototype/qa_grass_startup.gd`
и `verification.json`. Harness повторяет production stress с `mode=cpu-hub` и сверяет
размер/identity готовых buffers до камеры и после settle; instrumentation снята.
Референсы автора по слоям земли/травы сохранены у Terrain Authoring; art-замены нет.

### GPU crowd prototype02.11 — не внедрён

QA-only,штатный4.7.2 Forward+/Jolt/Safe,native1440p/FOV70/TAA/MSAA0/scale1.
Первый adapter оставил native poses и передавал32palettes в3MultiMesh;упаковка/
upload≈1,8мс,кадр≈18→16мс. Вдаль source LOD/групповыеbounds требуют проверки.
Primitive counter4.7.2 не умножает index LOD ветку наMultiMesh instance_count
(`render_forward_clustered.cpp:1105–1124`);его падение не доказывает срез геометрии.

Выбранная проба:60Hz native bake291frames/3clips,bone texture1899648bytes;
native rig сохраняется для0,18с crossclip fallback,моргание отдельно. Контроллеры/
collision/8important native прежние;плотность/дальность не сокращаются.
Matched full-index32ordinary A/B/A/B/A:wall native18,844/18,172/18,004мс,
baked12,074/11,892; p95native23,691–26,483,baked14,298/14,850;
p99native32,693–34,349,baked22,790/28,845,max baked33,995/36,226.
Независимых phases30/32,CPU binding≈0,189мс;не синхронная толпа с одной позой.
Actual native LOD:FOV70 native18,134→baked11,907мс;FOV40 16,482→11,239мс.
Отдельный intrusive GPU probe:median7,694→7,504мс,p95baked8,431;не смешивать его
счистыми wall intervals. **120FPS OPEN**;это не release сравнение.

19992vertex checks по22surfaces/idle-walk-run:60Hz matrix interpolation отличается
отnative quaternion sampling максимум≈3,385мм. Снимки внастоящей сцене сTAA OFF
осмотрены;это не автоматическая pixel equivalence. Walk→idle→run→idle сохраняет
native fallback;max frame переходов16,8–32,4мс,массовые transitions не приняты.
Открыто передruntime:motion vectors/TAA вдвижении,spatial LOD/culling/bounds,
mass transitions,полные morph/events/attachments и ручной вид. Providers остаются
вRAM;полная NPC выгрузка иproduction clock/save/AI ещё не подключены.
Далее — закрыть эти конкретные gates и включить путь через существующего Hoshi owner,
а не повторять общий аудит/самостоятельно заменять движок.

Evidence:`C:/Users/novos/Documents/Codex/2026-11-02/ember-crowd-animation/`:
spawn-baseline/prepared.json,feature-chunked-frame/result.json,baked-diverse/result.json,
native logs/snapshots,prototype/ иverification.json. Неудачные worker/async пробы не
перенесены;production Material owner использует polling+ResourceLoader,не static coroutine.
QA adapters сняты после проверки;рабочие карты/арты иконтроллеры прежние.

### Разные анимации NPC03.11 — native correctness

Автор потребовал проверять разные движения одновременно. Локальный Quaternius
`UAL1_Standard.glb` содержит43clips;нового скачивания/зависимости нет. Прежний retarget
через RetargetModifier3D перенёс отдельную6clip библиотеку:idle/walk/run/talk/sit/dance.
`retarget_hoshi_locomotion` принимает `clips=...`,default остаётся idle/walk/run;
одноразовые clips в этот loop-профиль не входят. Model/REST/рабочий motion.res прежние.
Все10248keys исходных3клипов совпали с расширенной библиотекой,delta0.

Production Hoshi сохраняет выбор locomotion;узкий `_select_motion()` позволяет
stress subclass выбирать клип через тот же native crossfade/LOD/blink owner.
Только walk/run масштабируются по скорости. Никакого нового AI/action/save owner.
Обычный stress controller теперь чередует idle/walk/run со сдвигами phase;при наличии
дополнительных clips включает их. Скорости/распределение движения fixture изменились:
старые numbers не являются baseline нового сценария.

`tools/test_crowd_animation_mix.gd`,native Forward+/Jolt/TAA/2560×1440,mode=cpu-hub,
`EMBER_STRESS_MOTIONS=<отдельная6clip motion.res>`:dense576м,39NPC+player/8important,
прежние220135vegetation/16crates/4houses/8lamps. Все6типов активны одновременно;
за11с все39NPC меняют clips,normal max1смена/кадр,3658разных actor/clip/phase samples.
Отдельный burst39смен/кадр PASS;fallen/waiting/support0,62anchors/396floor tiles,
8hero solvers и0ordinary solvers прежние. На сохранённых FOV40/70 кадрах native
AnimationPlayer реально играет все6clips;центров вкадре23/34,обрабатываются39.
Это проверка разнообразия иnative correctness,не visual/120FPS acceptance.

На фоне заявленной работы Blender wall median15,659мс,p9517,899,p9919,196,max49,443.
Это наблюдение нового workload;не причинное сравнение с прежним uniform motion.
Existing Hoshi player native PASS:run/stop/Shift walk/hero return/REST/floor.
Кадр mixed сцены осмотрен;поза сидения проверяет анимацию без добавления стула/AI.
GPU candidate пока проверен только на прежних3clips:следующий A/B должен bake все6,
проверить staggered иburst transitions,TAA/motion vectors/LOD. На его production
перенос и120FPS эти native результаты не дают автоматического PASS.
Evidence: `C:/Users/novos/Documents/Codex/2026-11-02/ember-npc-mixed/`:
`clips/motion-source.json`, `library-checks.json`, `native-mix/result.json`,
`player/player-checks.json`,native logs и `verification.json`.

### Порции высокой травы и подготовка посадки03.11

Автор наблюдал четыре зависания после появленияNPC,когда добавлялись деревья,
кусты и высокая срезаемая трава. Exact native stress baseline:96объектов по24закадр,
wall802–2725мс,4stalls≥100мс. Instantiate max0,974мс,attach1,745мс — не источник секунд.
Синхронный `load(berry_bush.scn)` занимал1,822с;native main profile и scoped callbacks
исключили map process/deferred style binding как причину остальных секунд.
Ground placement запрашивал высоту за пределами готовых полей,вычисляя64×64 tile.
Проверка тем же SmoothSurface.field на5точках:поле79,9–82,7мс,точечный footprint
5,2–5,7мс,разница высот0. Snapshot использует существующий halo/правила формы.

Projection теперь предоставляет `prepare_floor_query`:одна private dense window
и один WorkerThreadPool task наprojection,никаких live Nodes/документа вworker.
Результат кладётся в один point cache только при прежних document ID/revision.
Отмена/закрытие joins task;синхронный fallback иbulk authoring/navigation сохраняют
полный tile cache. Обычный surface_floor_sample после подготовки по-прежнему
учитывает землю и физические объекты,схема Source/высота/collision не заменены.

Stress начинает threaded ResourceLoader запросы сцен до reveal,получает только
готовые PackedScene;ссылки удерживаются. Высота готовится доsafe_spawn/ground_at;
один полностью настроенный объект подключается закадр. При разнесении crates
восстановление records во время незаконченного пакета создавало лишние тела
(142anchors вместо62). Теперь все16тел подключаются доregister/restore;guard11→27
item bodies. Этот промежуточный `accepted/` отвергнут как несопоставимый workload.

Принятый technical check — `admission/`:прежние39NPC+player,8important,
16crates/4houses/8lamps,32trees/32bushes/32cuttable tufts,220135vegetation,
62anchors/396floor tiles,pending/fallen/waiting0. Native1440p/scale1/TAA/Forward+/Jolt,
плотность/дальность/исходные assets прежние. Spawn-window wall median30,575мс,
p9544,156,p9955,384,max67,746мс,stalls≥100мс0 вместо4;всё окно7,741→4,574с.
Ground query после подготовки max1,976мс,attach1,632мс,instantiate0,544мс.
Порог100мс закрывает именно прежние секундные stalls,не принимает120FPS или идеальную
плавность. Короткие пики/первое появлениеNPC/полный cold fixture остаются OPEN.
Промежуточные synchronous/cooperative варианты не принимаются как итоговый путь.

`test_terrain_point_query`:72surface samples иsnapshot comparisons,flat/slope/steps,
mixed palette/round+protect rules,dense/sectioned,seam/edges,repeat/revision PASS;
native async ready/stale/cancel/join PASS. `test_cuttable_grass` в guarded staged QA
Forward+ PASS:cut/stubble/loot/guards/three cold saves/scene roundtrip/cleanup.
Stock mixed runner обнаружил отсутствующий в своём stage grass-painted-calm PNG;
это отдельная staging-граница,не runtime FAIL;исходные материалы/карта не переписаны.
Ручное ощущение появления объектов ещё оценивает автор. GPU-candidate6clips остаётся
следующим NPC gate;данные spawn не принимают его или общий120FPS.
Evidence:`C:/Users/novos/Documents/Codex/2026-11-03/ember-harvest-spawn/`:
baseline/callbacks/profile,point-probe.json,admission/result.json,
accepted-comparison.json,point-query-final.log,cut-gameplay-staged.log,
prototype/ иverification.json. Диагностические adapters сняты после проверки.

## Общая приёмка и оставшиеся gates

Для изменённого фундаментального пути baseline и послеизменённый маршрут
используют одинаковые source/seed/load/camera/native quality. Engine editor,
fixed render snapshot и настоящий gameplay называются отдельно.
Нужны CPU/GPU/wall, p95/p99/max/stalls, память, cold/warm и release/return.
Viewport/camera/FOV/scale читаются из настоящего runtime, не из metadata.
Физика/высота/navigation должны сохранять одну поверхность; pending не равен hole.

Проверка полноты31.10: доступные на штатном движке системы ниже реализованы;
это не объявление полного performance PASS. Общая проверка с населением отделена
от прежних замеров пустого ландшафта.
- Реализованы native geometry LOD земли/деревьев/подходящих props,shared geometry,
  spatial MultiMesh grass fade/release,дальнее упрощение материалов,порционные очереди,
  cancellation и hysteresis. Трава не отбрасывает собственных теней.
- Main Sun имеет2PSSM splits/чёткие тени/дальность;это пространственная детализация,
  **не** редкое обновление дальних cascades. Собственный temporal shadow cache/
  interleaving отсутствует. В [Godot ed1daf0bf](https://github.com/godotengine/godot/blob/ed1daf0bf/servers/rendering/renderer_scene_cull.cpp#L3478)
  directional cascades идут отдельным render-путём;dirty/atlas reuse локальных
  Omni/Spot не является готовым решением temporal caching солнечных каскадов.
  Решение автора01.11:утро/день/вечер/ночь — явные переключения preset,без непрерывного
  realtime day cycle. Статический bake/cache применим,но camera shadow coverage,
  геометрия/LOD/streaming меняются и при неподвижном солнце.
  Штатный [LightmapGI shadowmask](https://docs.godotengine.org/en/stable/classes/class_lightmapgi.html#class-lightmapgi-property-shadowmask-mode)
  поддерживает baked directional shadows статических объектов вдали;[bake editor-only](https://docs.godotengine.org/en/stable/classes/class_lightmapgi.html),
  не runtime-пересчёт в экспортированной игре. Для4preset нужны соответствующие baked data,
  UV2 bake layout и инвалидирование после authoring. Текущий UV2 несёт paint/face IDs,
  поэтому требуется отдельное производное представление. Dynamic receivers/casters,
  ветер/harvest и3облика проверять отдельно:static surface bake не равен cached world
  shadowmap для NPC. Это кандидат штатного движка,не реализованныйcache;
  temporal cascade fork отложен,свет/дальность текущей карты не изменены.
  Отложенная мысль автора01.11 для будущих изменяемых дальних объектов:обновлять
  затронутые тени порционно/реже,важным движущимся объектам давать больший приоритет.
  Перемещение/удаление/смена формы должны инвалидировать прежний след тени;
  геометрия и её тень не должны расходиться на неопределённое время. Приближение
  камеры должно повышать актуальность;частоты/допустимая задержка ещё не выбраны.
  При проектировании отличать заранее динамические объекты от бывшей статики:
  обычный LightmapGI bake не умеет автоматически удалять вклад отдельного объекта
  в runtime. Такой сценарий требует изменяемого кэша либо другого разделения данных;
  это условие выбора технологии,не обещание возможностей текущего bake.
  Автор наблюдал ступенчатое изменение дальних теней при рассвете в Crimson Desert;
  это визуальное наблюдение,не подтверждение конкретного cache/cadence алгоритма.
  Текущий срез/порядок не расширяется:сначала static base,потом NPC/animation иlocal lights.
- HoshiVisual использует `EmberAnimationDistanceLod`: полная частота рядом/у лидера/
  группы, затем30/15Hz, вне кадра5Hz, hidden2Hz. Ближний offscreen персонаж остаётся
  full-rate ради тени. AnimationPlayer/morph/secondary bones продвигают накопленное
  время; physics/AI не замедляются. Flight/ragdoll сохраняют собственный путь.
- Object apply_object_detail(false) освобождает производные detail carriers и
  выключает свой material process,но Source nodes/canonical physics остаются.
  Дополнительно Map удаляет из активного PhysicsServer безопасные дальние StaticBody
  через штатный DISABLE_MODE_REMOVE: возврат36м/удаление48м относительно всех живых
  физических участников, не только игрока. Shape/source остаются в RAM. Recovery
  заранее восстанавливает опоры и удерживает тела до готовности подробного пола;
  terrain поддерживает участки под дальними NPC/предметами. Полного sector Source
  paging и общего AI scheduler нет;WorldRecovery принимает явный simulation
  demand opt-in контроллеров,без замены их gameplay/save owner (шаг3 выше).
  При смене кванта позиции восстанавливаются окрестности только изменившихся
  участников; bounds при удалении считаются один раз на prop. Регрессия полного
  обхода всех45 anchors при движении одного воспроизведена и исправлена;
  targeted test проверяет1restore вместо45.
- `EmberRuntimeShadowLod` использует принятый native LOD mesh в отдельном
  SHADOWS_ONLY instance:48/42м, lod_bias0.35, прежние материалы/alpha/vertex animation.
  Ближние receiver/party, низкое солнце и локальные тени имеют консервативный fallback.
  Proxy не получает вторую автоматическую привязку style uniforms; копируются только
  значимые overrides, изменения coalesced. Общие anomaly/rim/tree instance uniforms
  закреплены в slots0..3: разные shader variants больше не назначают им разные индексы.
  Stable poll не вызывает dynamic get_property_list и не читает renderer uniforms.
  Map rim/FruitTree sway/WorldAnomaly передают записи через
  `EmberRuntimeShadowLod.forward_instance_parameter`; Source остаётся владельцем.
  WeakRef binding немедленно обновляет proxy. Начальный snapshot/rebind синхронный.
  Внешний raw setter требует `invalidate_instance_parameters(visual)`; штатный
  Godot не предоставляет события произвольной записи uniform. Такой invalidate
  сначала возвращает Source caster, затем bounded admission поднимает новый snapshot.
  Clear/default/rebind/lifetime и512 updates с0source/default getters и0rebuild/scan
  проверены native. Одна property introspection cache не убирала RS value getters:
  даже get_instance_shader_parameter обращается к RenderingServer в штатном движке.
  Camera receiver sweep использует recheck_receivers готового proxy;полный binding
  остаётся bounded poll. Данные/ограничения — «Исправление CPU shadow-context04.11».
  Это геометрический LOD, не temporal cache.
  Автор выбрал штатный Godot; temporal cache солнечных каскадов отложен, engine fork
  не согласован. Tree HLOD/impostors и grass far-LOD с компенсацией покрытия пока нет.
- Mesh LOD технически проверен,но плавность переходов/силуэт/склоны требуют автора;
  population stress с анимированными NPC/предметами/поселением/локальным светом не принят.

Состояние внешних методов:impostors не отвергнуты как технология — первая проба
невалидна/не принята;Terrain3D отложен из-за Source/editor/physics/трёх обликов,
а не признан медленным. Mesh-shader grass не выбран как обязательный путь GTX1060;
обычные distance LOD/coverage методы этим не запрещены. Interleaved shadows и
animation LOD не должны числиться отклонёнными: первое отложено, второе реализовано.
Отклонённые микроварианты map cache/uniform guards относятся только к тем измерениям.
Технические проверки: animation distance LOD и physics activity headless PASS;
shadow LOD Vulkan/D3D12 PASS, в fixture shadow primitives4226→134 при неизменных
visible4226 и draw calls2. Same-bias proxy/source pixels exact,512 stable binding
updates/clear/rebind без ошибок. Это локальный результат, не множитель общего FPS.
Совмещённая нагрузка:16 анимированных Hoshi NPC,16 физических ящиков,4 дома,
8 фонарей поверх прежнего dense576м. Проверка обнаружила переполнение штатного
instance-uniform buffer65536 slots:4096 instances по16 slots. Применено524288
slots (8MiB вместо1MiB, до32768 instances); разрешение/плотность не снижены.
Предел конечен, long-session gate остаётся. Это устранение подтверждённой capacity
ошибки; утечка движка не доказана.
Evidence: `C:/Users/novos/Documents/Codex/2026-10-31/ember-world-systems/`;
первый population-run с renderer errors отклонён, не является performance baseline.
Повтор с увеличенным buffer выявил независимую регрессию: новый shadow poll вызывал
dynamic property introspection, candidate p95143,525мс против baseline17,045мс.
Такой candidate отклонён. После исправления introspection `population-final/`
выявил полный45anchor restore; после его исправления `population-active-anchor/`
дал median8,724/10,475мс, но p9523,995/35,462мс против control16,637/17,361мс.
Это не принятый performance результат. Убран оставшийся RS getter poll;
текущий candidate+correctness результат — `population-forward/`, baseline из
`population-active-anchor/` не повторяется и обозначен как cross-run reference.
Крупный новый renderer или перенос Source этим аудитом не согласовывается.

Открыты и не принимаются предыдущими локальными PASS:
- 120 FPS, p95/p99/max и невоспроизведённые stalls полного кадра.
- Зелёные склоны self-shadow в движении и новые тонкие полосы жёстких теней.
- Ручные near/far LOD, широкие/наклонные виды, coverage и бесшовные переходы.
- Fully cold startup, длительное движение/память, произвольный teleport.
- Общий wet-world appearance/readiness, wind/mixed нагрузка и слабое устройство.
- Авторские кисть/мышь/125%/save/reopen/discard и полный authoring сценарий.
- Сфера, экспорт, package size/used-record selection и отдельный release startup.
- Причины прежних AV/shutdown/TDR; отсутствие нового вылета не означает fix.

Для editor data/commands обязательны относящиеся Undo/Redo/save/reopen/discard/
validation. Автоматический PASS не заменяет автора. Нужен связанный stress,
а не весь suite без причины; успешные независимые проверки не повторяются.
Подробные исполняемые сценарии — [Test Plan](../MIGRATION_TEST_PLAN.md),
процесс — [Workflow](EMBER_WORKFLOW.md#пайплайн-производительности).

## Что берём из опубликованных игр

### Crimson Desert: проверенные данные и граница переноса01.11

#### Архитектурные выводы: слайды разработчиков и байты ресурсов

Исследование завершено без изменения кода, карты и настроек. Первичный материал —
фотографии слайдов Pearl Abyss с gamescom dev 2026, опубликованные 4Gamer.
Журналистский пересказ отдельно от видимого содержания слайда. Локальные индексы,
SHA, смещения и ограничения сохранены в `crimson-architecture-study/terrain/terrain-ledger.json`
и `materials/{resource-inventory,payload-samples,provenance}.json` внутри
`C:/Users/novos/Documents/Codex/2026-11-01/`.

1. **Готовить несколько представлений для текущего и будущего вида.**
   [Слайд 019](https://www.4gamer.net/games/484/G048495/20260826050/screenshot.html?num=019)
   разделяет загрузку пространства, mip текстур и LOD мешей; чтение, распаковка
   и подготовка идут асинхронно с приоритетами.
   [Слайд 020](https://www.4gamer.net/games/484/G048495/20260826050/screenshot.html?num=020)
   показывает ступени детализации и запечённый дальний proxy, сохраняющий силуэт.
   **Ember:** worker-подготовка и overview уже есть. Явный интерес будущего ракурса
   и отдельная готовность картинки ещё отсутствуют. Пол под телом — другой gate.
   Сохранять предыдущий валидный вид до публикации замены; не увеличивать все радиусы.
2. **Дальний proxy должен учитывать состояние исходных объектов.**
   [Слайд 031](https://www.4gamer.net/games/484/G048495/20260826050/screenshot.html?num=031)
   сообщает о секторах назначения объектов 256 м. Это не размер height tile и не рецепт Ember.
   [Слайд 033](https://www.4gamer.net/games/484/G048495/20260826050/screenshot.html?num=033)
   показывает дальние состояния форта после событий/разрушения и связь с исходными объектами.
   В поставленных proxy проверены ссылки на отдельные DDS и tree/Impostor/*.pat;
   точные пути/смещения — CD-TER-01. Это состав пакета, а не наблюдение draw.
   **Ember:** mesh LOD отдельных объектов не заменяет HLOD групп и выгрузку узлов/RAM.
   Производные представления можно запекать, сохраняя `.tscn`, Source и ExploreState
   владельцами. Срубленное дерево должно исчезать и из дальнего представления.
3. **Форма земли, локальная детализация и набор художественных деталей раздельны.**
   [Слайд 027](https://www.4gamer.net/games/484/G048495/20260826050/SS/027.jpg)
   показывает основу height/normal и mask/region для дополнительного displacement.
   [Слайд 029](https://www.4gamer.net/games/484/G048495/20260826050/SS/029.jpg)
   — повторно используемые cliff presets из ограниченного набора мешей и текстур.
   **Ember:** единая физическая поверхность и оптическая микродеталь уже разделены.
   Штатные LOD и дешёвый shader path уже применяются. Это не основание вводить второй
   renderer или объявлять полную замену terrain необходимой. Cartoon-стиль сам по себе
   не ограничивает число слоёв, выборок, alpha overlap, проходов и стоимость ригов.
   Пересмотр по вопросуавтора01.11:фото66(027) действительно явно показывает
   Height Map+Normal Map как Base Terrain Data,Mask/Region Map — Additional
   Displacement;фото71(029) — reusable cliff meshes. Этот принцип был записан,
   но ранее не проверен как альтернативная первичнаяоснова:сохранялся voxel source.
   Теперь автор явно поменял порядок authoring:ordinary terrain первичен,
   voxelization производнаяпозже;Terrain3D spike выше проверяет этугипотезу.
   Heightmap — кандидат дляосновного открытого рельефа,не универсальный объёмный
   формат(одна высота наXZ);normal map не заменяет геометрию. Слайд не доказывает,
   что Crimson использует Terrain3D/егоclipmap или нашу будущуювокселизацию.
4. **Общие входные данные взаимодействий, разные способы реакции.**
   [Слайд 024](https://www.4gamer.net/games/484/G048495/20260826050/SS/024.jpg)
   содержит contact position / force direction / action state и получателей:
   растительность, конструкции, вода, ткань, частицы, объекты и NPC.
   Число физических тел, решатель и частота обновления не показаны.
   **Ember:** пригибание травы может использовать ограниченное локальное воздействие
   в прежнем shader; срез/поломка остаются сохранённым игровым состоянием.
   Готовый аналог, не доказанный алгоритм Crimson:
   [Tiago Sousa/Crytek, GPU Gems 3, ch16](https://developer.nvidia.com/gpugems/gpugems3/part-iii-rendering/chapter-16-vegetation-procedural-animation-and-shading-crysis)
   — крупный изгиб и мелкая анимация на GPU с жёсткостью/фазой в данных вершин.
   Новый fluid solver или физическое тело каждой травинки этим не обоснованы.
5. **Материалы и impostor-ресурсы растительности в поставке подтверждены.**
   Найдены grassleaf/grassbranch/grassfrond/standardterrainmesh.material и тройка
   deadgrass.imp + impostor_color.dds + impostor_depth.dds. Заголовок `IMP ` прочитан;
   материал остаётся непрозрачным. Индексы/выборки и ограничения — в materials ledger.
   Имена не доказывают активный shader, число ракурсов или стоимость.
   **Ember:** пространственные MultiMesh и EMBER_TERRAIN_CHEAP уже есть.
   [Godot MultiMesh](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html)
   отсеивает группу целиком: один огромный batch увеличивает лишнее покрытие.
   Размер неделимой публикации/объём upload — отдельный измеряемый бюджет.

**Не установлены:** точный двухматериальный blend из четырёх sets, unified fluid wind,
screen-space GPU clutter, алгоритм GPU grass scatter/геометрии, пороги LOD,
CPU animation scheduler и per-system cost. Некоторые детали есть только в пересказе;
не превращать их в факты. EXE-строки и PresentMon эти вопросы не закрывают.

**Следующее решение для Ember:** закончить существующую систему представлений:
явный prewarm известного будущего ракурса, сохранение дальнего покрытия до замены,
отдельная готовность физической опоры. Stateful HLOD групп, запекание производных
и runtime paging — следующий архитектурный срез, не уже принятая реализация.
Замена самого mesher требует отдельной измеренной причины; текущие 32NPC данные
её не доказывают. Этот путь не обещает автоматически устранить стоимость близких ригов.

При реализации сохранять одну очередь и owners: deadline до неделимой операции,
bytes/готовые результаты в backpressure, revision/lifetime после await. Если одна
операция превышает бюджет, уменьшать её единицу или объём; очередь не прервёт upload
посередине. Приёмка — тот же dense маршрут после относящегося изменения, а не новый
прогон неизменной системы ради уверенности.

Графический захват draw/texture/shader ресурсов остаётся отдельным вопросом.
В проверенных типовых install/PATH местах RenderDoc/Nsight/PIX не найдены.
Перед захватом проверить поддержку текущего D3D12/RT/DRM пути; такой захват сам по себе
не покажет CPU-анимации. Установок и инъекций в этом исследовании не было.

#### Граница прежней проверки поставки

Автор подтвердил установленную игру и запросил исследование. Read-only REA:
`D:/SteamLibrary/steamapps/common/Crimson Desert`,Steam build26345091,
EXE1.0.0.3460,SHA256 `4e38ce1d8fe98eee7be0e26026a1d24ea6a17e80aa88e906b5f3ed553af11f63`.
Evidence: `C:/Users/novos/Documents/Codex/2026-11-01/crimson-rendering/`
(`crimson-local-ledger.json`,`inspect_shipped.py`),REA
`ev_a4509104a2775d41a9b9523a25520ecc72b28d16ea97ed2acf7a3ea62fca5234`.
Игра не запускалась;полные PAZ payloads не извлекались.

- Индекс0015/0.pamt:369139file records,проверены ranges в57PAZ и таблицы имён.
  `sectorlevel/proxylod` содержит238658файловых записей;это не число секторов,
  draw calls или одновременно resident объектов. Есть отдельный rootlevel/proxylod.
- Выборочные физические заголовки подтверждают proxy `.pam` с`PAR ` и DDS:
  global color2048²/12mip,height(-10,-10)512²/10,shoreline_sdf512²/10,
  normal256²/9. Раздельные готовые представления подтверждены;их runtime usage неизвестен.
- Имена terrain height/texture-index shaders и virtual-texture budget вEXE
  не доказывают geometry clipmaps,активное CPU/GPU расписание или быстрый teleport.
- [Pearl Abyss,gamescom dev2026](https://www.pearlabyss.com/ko-kr/Board/Detail?_boardNo=15224)
  подтверждает загрузку пространства/данных по положению и взгляду игрока.
  Точные пороги,кэши и алгоритм из пресс-релиза не следуют.

Применение вEmber:сохранять дальний silhouette/берег обзорным представлением,
а физическую опору подробного поля готовить по реальной необходимости.
[Godot HLOD](https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html)
уже умеет заменять группу объектов одним дальним представлением;native mesh LOD
сам по себе не уменьшает число объектов. Новый renderer/terrain stack не вводится.
[Geometry clipmaps](https://developer.nvidia.com/gpugems/gpugems2/part-i-geometric-complexity/chapter-2-terrain-rendering-using-gpu-based-geometry)
— известный terrain-кандидат,не установленный алгоритм Crimson Desert.

Близкие смены ракурса/переносы — отдельный открытый сценарий:заранее подготовить
известный следующий вид,удержать текущий до его готовности;при переносе тела
проверить ещё и физическую опору. Existing MapTransition.change_scene пока вызывает
change_scene_to_file,включая ту же карту;это не готовый camera-cut путь.
[Background loading](https://docs.godotengine.org/en/stable/tutorials/io/background_loading.html)
убирает блокирующее чтение только при проверке готовности доget;не гарантирует
дешёвую instantiation/upload/первый кадр. Near-instant cold arbitrary teleport не обещан.
Проверка будущего среза:camera-only и body transfer раздельно,первый кадр/пауза/
берег/скалы/FOV70,cold/warm/release-return,те же плотность/дальность/native разрешение.

Правило автора для props:до взаимодействия нет активной симуляции;после импульса
физика,после успокоения сон. Дальний мелкий предмет может оставаться записью состояния.
Freeze/sleep штатного RigidBody не равны выгрузке узла/коллизии/RAM;visible=false
тоже не снимает physics interest. Полный lifecycle/source paging ещё не реализован;
скрытые flag-gated harvest pickups исправляются отдельно без изменения save owner.

### Coding Quests03.11 — комментарии и применимость к Ember

Автор попросил разобрать [Why 3D Games Look Bad in Godot](https://www.youtube.com/watch?v=0792U-wuwjA),
прежде всего опыт разработчиков в комментариях. Прочитана техническая часть выборки
350комментариев/ответов (186root/164replies,sort=top),29выделены с permalink.
Выборка ограничена350;часть reply API возвращала incomplete data,это не все комментарии.
Оригинальное описание/закреплённый комментарий получены анонимно через установленный
yt-dlp;без cookies,загрузки видео и запуска чужого проекта. Текстовый разбор автора
доступен через [его статью](https://codingquests.io/blog/how-to-make-godot-3d-look-better);
сам видеоряд в этом срезе не анализировался. Runtime/editor/maps/QA UI не менялись,
работающий ручной проход не прерывался. Performance-тестов/установки addon не было.

**Уточнение FPS:** по оригинальному описанию автора75FPS — cap75Hz монитора,
около134FPS приvsyncOFF;первый вариант46–50FPS. Pinned comment дополнительно
заявляет5мониторов/OBS/другой софт. Это условия/утверждения автора,не matched benchmark.
Его уменьшение дальности/числа grass copies иизменениеMSAA не принимают наш контракт
неизменной плотности/native1440p. Комментарии о200FPS на5070/300FPS на большой карте
без общего fixture/камеры/качества/хвостов — полезные ориентиры,не гарантированный результат.

**Объединение неподвижных деталей/материалы — действительный непроверенный кандидат.**
[@MoopusMaximus](https://www.youtube.com/watch?v=0792U-wuwjA&lc=UgwL0XCqkpmO_nFwqFB4AaABAg)
описывает StaticMeshMerger,зоны скрытия/async возврат иотдельный shadow fade локальных lights.
Найден [кандидат Static Mesh Merger](https://github.com/EverettM12/Static-Mesh-Merger),MIT,
ранняя версия;точный repo/version комментатор не указал. Source plugin.gd/merge_utils.gd
прочитан и сохранён с exact Git blob hashes. Группирует поверхности по Material,
создаёт ArrayMesh через SurfaceTool;не переносит native indexLOD/не реализует streaming.
Утверждение «тени вычисляются один раз после merge» неверно:merge не shadow bake/cache.
В Ember `EmberVoxelProp.apply_voxel_light_settings` уже делит immutable tree meshes,
раньше дублировал surface materials для каждого экземпляра. [Forward+ automatic instancing](https://docs.godotengine.org/en/4.7/tutorials/performance/optimizing_3d_performance.html#use-automatic-instancing)
требует одинаковые mesh/material. Кандидат проверен и подключён03.11:
«Пункт3 — shared tree materials» выше,1288bindings→10active materials,
whole frame near≈−2–3%/wide≈−3–4%;map/look/private/editor границы сохранены.
Тот же merger оставил бы отдельные surfaces по уникальным materials. Local static
render batches остаются альтернативой при новом bottleneck;не склеивать весь мир,
подвижные/harvest объекты или ломать3looks/LOD/IDs/collision/shadow/culling ради merge.

**Occlusion/помещения:** [ветка о batching](https://www.youtube.com/watch?v=0792U-wuwjA&lc=UgxfO1X4RHmcX7D9d_B4AaABAg)
не заменяет штатный frustum culling,он уже есть. [Godot occlusion](https://docs.godotengine.org/en/4.7/tutorials/3d/occlusion_culling.html)
полезнее в комнатах/за крупными заслонами и имеет CPU цену. В нашем открытом поле
сам по себе не обещает gain. State-aware room visibility/paging ещё OPEN;нельзя скрывать
все offscreen caster без учёта теней в кадре. visible=false не выгружает physics/Source.

**Локальный свет:** [distance_fade_shadow](https://docs.godotengine.org/en/4.7/classes/class_light3d.html#class-light3d-property-distance-fade-shadow)
есть уOmni/Spot отдельно от окончания света. У Ember уже есть nearest shadow budget
вMapLoader.refresh_omni_shadow_focus;штатный distance_fade вMapLoader/Lights не подключён.
Кандидат для прежнего local-light stress,не замена солнцу/всей системе активности.
Комментарий «omni всегда6maps» слишком общий:уGodot есть cube/dual-paraboloid;
наш tune_omni_shadows действительно выбираетSHADOW_CUBE. Spot меняет форму света,
поэтому это отдельный художественный выбор,не бесплатная техническая замена.

**Запекание/две группы света:** [@FLNKmusic](https://www.youtube.com/watch?v=0792U-wuwjA&lc=Ugz-9gJKXWsp5YTgNHZ4AaABAg)
предлагает baked static receivers иразные receiver/caster masks для moving/static объектов.
[Light3D](https://docs.godotengine.org/en/4.7/classes/class_light3d.html) поддерживает обе masks,
но «два солнца» не кэшируют realtime casters. Наш предыдущий LightmapGI/shadowmask
compatibility gate уже доказал необходимость static caster для moving receiver в тени скалы.
Не повторять bake только из-за комментария. Возврат к гибриду — после решения
UV2/3looks/revision/4пресетов и receiver routing;temporal cascade cache наstock не появился.
[LightmapGI](https://docs.godotengine.org/en/4.7/tutorials/3d/global_illumination/using_lightmap_gi.html)
резервируетUV2,не обновляется на runtime;«всё запечь» не закрывает editor/streaming.

**То,что уже применяется:** native LOD/пространственный grass MultiMesh/QA GPU culling,
background preparation иbounded publish,ordinary grass без теней;уGPU grass нетalpha-card.
Совет «сделать opaque» не новый метод для этого кандидата. Alpha scissor/hash не равны
alpha blend и не устраняют всю fragment/depth работу. SDFGI/SSIL/volumetric fog уже
выключены вMapLoader._tune_look_environment;SSAO вmain Environment включён,его автоматически
не убирали. [SDFGI](https://docs.godotengine.org/en/4.7/tutorials/3d/global_illumination/using_sdfgi.html)
не поддерживает dynamic occluders — противоположный совет вкомментариях неточен.

**Советы по виду:** [@Radxix](https://www.youtube.com/watch?v=0792U-wuwjA&lc=UgxO5x9zBjvnc-E2Yu54AaABAg)
и[@foxidgamedev](https://www.youtube.com/watch?v=0792U-wuwjA&lc=UgzdTY4lwb3ANf6B6st4AaABAg)
полезно выделяют согласованную палитру/материалы,умеренные ambient/AO/fog,LUT иветер
от закреплённого корня. ВершиннаяY не обязана быть0..1:нужны относительная высота/маска.
В Ember grass wind уже вершинами,leaf bake хранит групповую light_normal;ветра крон нет.
Normal/height map могут заменить мелкий рельеф без изменения силуэта,но POM не бесплатен:
его дорогой ближний путь укамня уже измерен/оптимизирован выше. Новая art-правка/AgX/GI
по ролику не включались;у мультяшного мира нет требования повторить все12effects автора.

Данные/извлечение/350comments/29permalinks/проверенные source blobs:
`C:/Users/novos/Documents/Codex/2026-11-03/ember-codingquests-study/`.
Приоритет ручного QA не меняется. Следующий GPU NPC gate иусловия возврата к grass
остаются в текущем срезе;этот разбор не создаёт параллельный optimization backlog.


### Остальные применяемые источники

Обновление02.11, только чтение, без установки/копирования чужого renderer:

- [Godot CPU/SceneTree](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html)
  различает hidden/paused и удаление из дерева; это готовый механизм кандидата
  residency, а не доказательство нашего gain. [Background loading](https://docs.godotengine.org/en/stable/tutorials/io/background_loading.html):
  load_threaded_get может блокировать до готовности; instantiate/attach проверять отдельно.
  [Occlusion](https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html)
  имеет CPU цену и требует достаточного заслонения; открытая поляна не обещает выигрыша.
- [Veloren, опубликованная архитектура LoD](https://veloren.net/blog/devblog-81/)
  разделяет terrain height/color/horizon и ближний voxel mesh; offscreen shadow-only
  объекты сохраняются. [Дальние деревья](https://veloren.net/blog/devblog-171/)
  представлены типом/положением и дешёвой моделью вместо полной детальной генерации.
  [Открытая Terrain API0.18](https://docs.veloren.net/veloren_voxygen/scene/terrain/struct.Terrain.html)
  отдельно хранит shadow_chunks и отказывается от ненужного remesh. Полезны границы
  представлений/активности; это не замер Ember и не готовый Godot addon. Переписывать
  voxel runtime этим обзором не предлагается; код не переносился.
- [Luanti mesh worker/queue, прочитано02.11](https://github.com/luanti-org/luanti/blob/master/src/client/mesh_generator_thread.cpp):
  очередь объединяет повторные запросы блока, различает urgent, workers возвращают
  результаты с epoch; устаревшие результаты повторно ставятся/отбрасываются. Принцип —
  не готовить и не публиковать потерявшее актуальность. Проверять наши существующие
  revision/cancellation/budget owners, не добавлять второй scheduler ради примера.

- [miHoYo / Zhenzhong Yi, Unity Japan, 2021](https://www.slideshare.net/slideshow/210617-unity-dojo20211mihoyozhenzhongyi/249437133),
  slides 9–10/18–23/35/38–44/56–62: отдельные mobile и PC/console pipelines,
  динамические сутки/погода; дальние cascades обновляют interleaved, soft filtering
  ограничивают penumbra mask, AO считают при половинной ширине/высоте.
  Статические локальные тени/probe data готовят заранее, динамическое дополняют
  и обновляют порционно. Это не доказательство полностью запечённого солнца.
  Принцип — ограничить место/частоту дорогой работы; не копировать 8 cascades
  или миллисекунды чужой платформы. Genshin terrain/grass/streaming не установлены.
- [HoYoverse 4.4, 2024](https://blog.playstation.com/2024/01/19/genshin-impact-version-4-4-brings-new-friends-and-visual-enhancements-jan-31/):
  GFF/Gradient Tint Rock имеют упрощённый mobile вариант. Полезны крупные
  цветовые массы и атмосфера; статья не доказывает fog как маскировку LOD или gain.
  [Версия 4.0](https://blog.playstation.com/2023/08/04/genshin-impact-version-4-0-launches-august-16-first-details/)
  описывает GI в отдельных областях, не алгоритм или бюджет нашей сцены.
- [Campo Santo, Firewatch, GDC 2016](https://media.gdcvault.com/gdc2016/Presentations/Ng_Jane_MakingTheWorld.pdf),
  PDF 45–46/52/29–39: дальнее дерево до 4-triangle billboard, меняющийся alpha
  cutoff сохраняет пышность, упрощаются тени; мир загружается секторами.
  Применимость — coverage/силуэт и отдельная цена теней/памяти. Shadow proxy
  может разойтись с нашей лепкой; переходные volumes требуют адаптации к камере.
- [Guerrilla, Horizon Zero Dawn, GDC 2018](https://media.gdcvault.com/gdc2018/presentations/gilbert_sanders_between_tech_and.pdf),
  Shading → Pixel Program: Alpha: depth-only foliage и дальнейшее shading
  с depth equality. Проверено по индексированному тексту; точный слайд не подтверждён.
  Цель доклада 30 FPS. Forward+ уже имеет prepass, Ember — early alpha clip:
  это повод измерить повторную fragment работу, не добавлять дублирующий renderer.
- [Godot GPU optimization](https://docs.godotengine.org/en/stable/tutorials/performance/gpu_optimization.html):
  batching снижает submissions, но группа целиком ограничивает culling;
  fragment/texture bandwidth и alpha overlap имеют собственную стоимость.
  Один draw не делает её бесплатной. Общий GPU/CPU% не заменяет pass/frame times.
  [Shadow bias](https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html#tweaking-shadow-bias)
  требует проверки контакта/тонких теней, не слепого повышения значения.

- [Godot mesh LOD / meshoptimizer](https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html)
  уже является нашим готовым алгоритмом. Исправлено его подключение к resident
  деревьям вместо нового renderer. [ArrayMesh.shadow_mesh](https://docs.godotengine.org/en/stable/classes/class_arraymesh.html#class-arraymesh-property-shadow-mesh)
  требует тех же позиций вершин и LOD: произвольный дешёвый hull туда не подставлять.
- [Terrain3D architecture](https://github.com/TokisanGames/Terrain3D/blob/main/doc/docs/system_architecture.md):
  geometry clipmaps создают сетку один раз и меняют высоты на GPU. Это подходящий
  внешний ориентир для отдельного terrain-пути,но замена нашего Source/editor/
  трёх обликов/physics требует доказанного terrain-geometry bottleneck и решения автора.
  [Terrain3D foliage](https://terrain3d.readthedocs.io/en/latest/docs/instancer.html)
  использует пространственные MultiMesh cells и отдельный shadow impostor.
  У нас пространственные patches уже есть; чужой размер32м не переносить вслепую.
- [GPUOpen grass,2024](https://gpuopen.com/learn/mesh_shaders/mesh_shaders-procedural_grass_rendering/):
  GPU generation,плавный LOD,компенсация покрытия шириной оставшихся лезвий.
  Это не разрешение уменьшать нашу ближнюю плотность. Mesh shaders не универсальны
  для слабого-PC пути: [NVIDIA](https://developer.nvidia.com/blog/introduction-turing-mesh-shaders/)
  вводит их с Turing;базовый путь для GTX1060 не должен их требовать.
- [Godot-imposter,MIT](https://github.com/zhangjt93/godot-imposter),pin
  `e86fd4786d36202129c7b7d5873131fc21dbbe72`: external-only proof,не установлен.
  Бейкер требует адаптации наших ShaderMaterial alpha/normal;standalone preview
  выявил ещё alpha-weighted blending/edge issues. Первый batch с shader fallback
  INVALID,его GPU цифры отвергнуты. Исправленный standalone — только визуальный
  прототип,без production/performance приёмки. Сейчас выбран существующий native LOD.

## Воспроизводимость и evidence

Последние авторитетные наборы:
- `D:/Codex/ember-frame-hotpaths-20261031/`:baseline/ — вложенные scopes,не FPS;
  nearest regression RED→GREEN;live-scene query A/B/A в integrated-final/.
  integrated-final/ — clean/cold/release/return/frozen GPU,engine errors0.
  Guarded interaction-qa создан existing mixed fixture builder,Forward+/Jolt;launch-rules/
  physical-crates PASS,shared inputs hash unchanged. Первый unguarded launch отказался.
  integrated/ — предварительный run с2ошибками удаления benchmark probes:не приёмка;
  corrected queue_free lifecycle и свежий cold cache проверены в integrated-final/.
  verification-summary.json/final-root/ закрепляют проверенные границы и исходники.
- `D:/Codex/ember-native-waits-20261031/`:diagnostic only,не новый cleanFPS baseline.
  native/ и native-repeat/ — UDP markers;2post-measurement events исключены.
  passive-control-result.json — controlled350ms native sampler proof;passive-world/ и
  passive-world-stacks.json/native-summary.json —4timed routes/3500снимков,ни одного
  прежнего400–500мс stall. verification-summary.json фиксирует отсутствие runtime fix.
- `D:/Codex/ember-overview-index-20261031/`:native index regression RED→GREEN,
  admission/slots/policy PASS;integrated/ — current dense/cold/release/return/frozen GPU.
  trace/,trace-legacy/,trace-repeat/ — scoped A/B/A;completions/ — old production
  с queue/IO completion/MCP scopes,slow-frames.json фиксирует468мс и быстрые callbacks.
  candidate/ и final-root/ хранят exact исходники;verification-summary.json — границы.
- `D:/Codex/ember-overview-updates-20261031/`:fairness-integration-red/green и
  native fairness/cache-read/material/preparation/pattern-library logs;startup-before
  timeout90с, startup-after21,823с. profile-fixed/ — вложенные CPU scopes;
  profile-startup-failed/ и index-update-probe — не приёмка. Integrated/ — чистый
  production dense маршрут после queue fix;verification-summary.json хранит итог.
- `D:/Codex/ember-collision-cost-20261031/`:queries/ — live all/none/repeat;
  partition/ — terrain/props/none в живом step со всеми streamed slots;
  triangles/ — exact Concave control,не production;jolt-query/ — unchanged HeightMap.
  jolt-full/ — full dense/cold/return/actual foot;jolt-final/ — повтор clean/GPU;
  default-return/ — ближайший DEFAULT control;jolt-budget3/ — REJECTED coverage/startup.
  probe/ с disabled Scene INVALID для стоимости collision (все hits0),не baseline.
  Native targeted logs/root-backend.log и verification-summary.json фиксируют границы;
  ранние partition startup и crates missing-fixture/refusal — setup failures,не приёмка.
- `D:/Codex/ember-ground-admission-20261031/`:baseline/ — исходные enlarged routes;
  final/ — production native dense/cold/return/frozen GPU;profile/ — отдельные CPU
  scopes,не cleanFPS. Admission RED→GREEN,travel/native slots/owner lifetime/detail
  preparation logs и verification-summary.json. Baseline первый out имеет117мс
  outlier;warm trace out p9512,718мс. Парный общий FPS gain не заявлен.
- `D:/Codex/ember-active-world-20261031/`: phases/attribution/callback-detail/
  material-detail — CPU isolation;production5 — measured sync-IO stall;
  async-final — enlarged native5ms/cold/return and frozen GPU;main-view — main
  grass before/after. acceptance/ — REJECTED3ms (есть absent buffers),не PASS.
  validation/cache-write RED→GREEN,preparation/cache-maintenance/native logs и
  verification-summary.json фиксируют scope;correctness GPU timers stale,не использовать.
- `D:/Codex/ember-wide-objects-20261031/`: probe/ — cast/LOD attribution; первый unshaded control INVALID
  из-за duplicate render_mode,его lighting цифры отвергнуты. lighting-valid/ —
  исправленный A/B/A: wide40/70 без lighting/receiving дешевле на0,330/0,536мс GPU;
  это не полная цена материала,production освещение сохранено;
  resident-lods/ — cause isolation;acceptance/ — production stress;lod0-parity/ —
  base geometry images;verification-summary.json — verdicts. Surface-lods strict
  attribute parity не прошла;impostor-probe первый batch INVALID,не приёмка.
- `D:/Codex/ember-render-decision-20261030/`: controls/, profile-controls/,
  detailed-controls/, guard-controls/, crisp-gameplay/, verification-summary.json.
  В двух последних shader probes label `profile_tables` наследован harness и
  означает их candidate, а не uniform-table реализацию.
- `D:/Codex/ember-frame-budget-20261030/`: final5/ — coverage/release/return;
  alpha-gameplay/ — прежний полный кадр; alpha-probe/ — GPU A/B/A;
  alpha-pixel/ — parity TAA OFF; HeightMap/epoch/shared-budget logs.
  coverage-final/shared4 — отклонённый budget, не принятый результат.
- `D:/Codex/ember-frame-accounting-20261030/selection-clean-valid/` — прежний
  baseline; selection-clean/ INVALID из-за устаревших stage sources.
- `D:/Codex/ember-active-frame-20261030/` — предыдущие shadow-pass/profiling
  и water/material lifetime доказательства; старые тайминги не текущий baseline.
- `D:/Codex/ember-world-integration-qa-20261029/` — native LOD/physics/3looks;
  `C:/Users/novos/Documents/Codex/2026-10-29/ember-grove-scale/` — 859 props/plan;
  `D:/Codex/ember-optimization-team-20261029/` — общий preservation manifest.

QA workspace/caches на D:; child-only APPDATA/storage wrapper:
`D:/Codex/ember-visible-first-20261029/Run-GodotQa.ps1`.
Не запускать рабочий checkout с `--headless --editor`, не трогать чужие процессы.
Stage sources сверяются с root до прогона и восстанавливаются по SHA после.
CPU image/texture lifetime и холодный cache не подменяются прогретым stage.

## Отложенные сборка и сфера

DerivedDataCache.SHIPPED_CACHES: geometry/water/trees/details/height/solids/anomaly.
PreparedBundle/ExportPlugin используют прежние keys/transport/validation;
runtime local→packaged fallback не применяется к editor/custom test directories.
Diagnostic exporter сохраняет authored data, восстанавливает производные solid
materials из metadata, включает динамические shader/prefab/PNG dependencies.
Startup barrier ждёт ground/physics/LOD, foliage, optional sphere, water и camera
до управления. `--ember-profile` включает StartupDiagnostics; без флага sampler off.

Диагностическая Windows x86_64 release `.exe` проверена на одной main-copy;
это не shipping builder и не приёмка персонажей/игры. Prepared snapshot содержит
лишние варианты; used-record selection, multi-map catalogue, минимальный package,
чистый release startup/другой ПК/экспортные ресурсы остаются OPEN.
Артефакт: `C:/Users/novos/Documents/Codex/2026-10-28/ember-build-probe/`.
Прежняя сфера давала около 40 с подключения, первый render `.exe` около 17 с;
конкретные операции не разделены и отложены автором. Без сферы editor/gameplay
проверяются отдельно; старые 1600×900 export FPS не сравниваются с native1440.

Перед возвратом к сборке согласовать платформу/карты, отбирать только используемые
validated prepared records и не включать рабочие/старые caches. Source bytes,
derived bytes, build/user caches, итоговый пакет, RAM/VRAM и время подготовки/
старта — разные бюджеты. Универсальный предел MB не утверждён. Editor сохраняет
отзывчивость и authoring state; экспорт не заменяет runtime оптимизацию.
Сначала аппаратный и memory gate, затем дополнительный HLOD/bake только по
измеренному ограничению. Кэши удаляемы без потери карты; покадровая история на диск
не сохраняется. Дорогая новая зависимость/owner требует отдельного решения.

## Навигация после сокращения документации

Старые результаты 28–30.10 из World Authoring сжаты в текущие разделы выше.
Незакоммиченные оригиналы сохранены перед переносом:
`D:/Codex/ember-doc-restructure-20261030/original/`, manifest-before.json.
Backup и Git служат истории, не вторым активным backlog. Ссылки evidence остаются
проверкой конкретного утверждения; повторные PASS и журнал команд сюда не дописывать.
