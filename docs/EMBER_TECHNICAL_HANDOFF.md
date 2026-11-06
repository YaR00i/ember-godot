# Ember Godot — технический handoff

Краткий обзор сверён с рабочими файлами 2026-09-30: ветка
`codex/editor-performance-brush-checkpoint`, HEAD `2349e47` и локальные изменения.
Это не объявление всех локальных проб принятыми; подробные gates сверять по теме.
Этот файл хранит действующие архитектурные контракты, owners и технические долги.
Текущая рабочая точка и ближайший порядок находятся в `docs/EMBER_NOW.md`.

Перед изменением кода сверять handoff с текущим checkout, `git status --short`,
последними commits и реальными вызовами через `rg`. Незавершённые локальные
editor/performance и art-черновики не являются принятыми контрактами `main`.

Подробная история конкретных оптимизаций, benchmark-цифры, промежуточные версии
инструментов и закрытые исправления не являются обязательным контекстом.
Их source of truth — Git history, targeted tests и специализированные документы.

## Статичный внешний mesh28.10

Этап7: editor cycle/fresh play/3 looks PASS; промежуточная оптимизация загрузки/полной сферы —
[Производительность мира](EMBER_WORLD_PERFORMANCE.md#отложенные-сборка-и-сфера) → «Отложенные сборка и сфера». Ручная приёмка остаётся OPEN.

Подготовка аномалии использует прежние owners: TerrainLookBake.AnomalyJob считает только
CPU arrays в WorkerThreadPool; Nodes/ArrayMesh/MultiMesh подключаются на основном потоке.
Устаревшая работа отменяется и не публикуется. Correspondence упаковывает совпадающие
вершины напрямую; scatter_values считает height deltas один раз на patch, spatial groups
читают тот же буфер. MapLoader отбирает кандидатов опоры по bounds, Prop сохраняет прежний
точный floor sampler/canonical mesh. Source/коллизия и движение сферы этим не меняются.
SolidSurface.detailed_volume_from_boundary повторно использует опубликованную границу;
living_mesh хранит CPU geometry через прежний DerivedDataCache в user://ember-solid-living-cache
(128MiB, ключ по Source/профилю/масштабу/pulls/контрактам/версии движка). Это удаляемые
производные данные, не новый формат авторского Source. Startup shelf читает готовые thumbnails;
недостающие рендерятся прежним путём после подготовки при открытой библиотеке.

Повторное открытие28.10: MaterialHeight.cached_bake сохраняет прежний optical bake через
DerivedDataCache в user://ember-material-height-cache (8MiB на запись,64MiB общий trim,
16 CPU images). Ключ: CONTRACT/MAX_SIZE/engine + содержимое/размер/формат/mips исходного
Image и точные softness/sharpness. Повреждение/несовпадение payload вызывает прежний bake.
Каждому потребителю возвращается отдельный Image: generate_mipmaps/resize не меняют кэш.
SurfaceMaterials.set_terrain_depth_profiles и Height.texture_for используют этот путь;
прямая bake остаётся чистым эталонным расчётом. Модуль Height — @tool: без него Godot
оставлял static cache_directory пустым в настоящем редакторе и дисковый кэш не работал.
Авторские Pattern/текстуры/Source, разрешение1024px и шейдер не меняются; числа — World Authoring.

SurfaceMaterials._png_bank теперь переиспользует только неизменяемый Texture2DArray цветных
картинок. Ключ — упорядоченные уникальные Texture2D instance IDs;16 weak cache records.
Живой bank удерживает исходные текстуры, чтобы их ID не менялись без реальной смены источника.
Texture2D.changed очищает каталог производных банков; следующий bind готовит новый снимок.
Это кэш процесса, не Source/schema/файл карты. PNG means/layer indices вычисляются прежним
способом; каждая роль/палитра сохраняет свои lookup textures и CPU images. Масштаб, tint,
periodicity, свет и live preview не становятся общими. Пользователи банка его не обновляют.
Проверка normalizing/mips/linear means/private previews/source replacement и native pixel parity —
test_material_color_bank. Измерения main-copy — [Производительность мира](EMBER_WORLD_PERFORMANCE.md#доверенная-текущая-точка) → «Доверенная текущая точка».

TerrainProjection._publication_budget_us: первый editor open нового projection получает
мягкий лимит12000us, остальные кадры4000us. Бюджет общий для poll готовых jobs, подключения
тайлов и look queue; число workers/математика/atomic mesh+collision commit не менялись.
Флаг runtime-only: сбрасывается при завершении initial open, begin_live_brush, apply_columns
и profile operation resize/sections. Повторное открытие существующего документа не включает
startup budget. End brush его не возвращает; runtime остаётся4000us.
Profile snapshot различает startup/interactive calls/max time. Targeted editor preparation
проверяет переключение бюджетов, геометрию/коллизию/stale/live; данные карты не менялись.

TreeLookBake после Astra/high audit помечен @tool: native editor теперь инициализирует прежний
static cache_directory. Explicit empty override остаётся допустимым. Два fresh native editor
процесса: cold4 builds, warm4 disk hits/0 builds, geometry/Source exact; main default cache4 hits/0 builds.
Обычный SceneTree test сам назначал каталог и не закрывал этот editor-only gate; новый owner
проверки — tools/editor_test_tree_look_cache.gd. Source script SHA в key по-прежнему означает
первый cold build нового набора. Готовые4 records перенесены в user:// рабочего проекта.
Map._refresh_world_look11,2→5,38с inclusive, ready QA43,0→36,7с. Открыты shelf.prepare5,35с,
foliage tail≈10,3с; библиотека/очереди не менялись в срезе TreeLookBake.
Точность clocks/рекомендуемый contract/evidence — [Производительность мира](EMBER_WORLD_PERFORMANCE.md#доверенная-текущая-точка) → «Доверенная текущая точка».

VoxelCatalog.definitions(true) использует прежний DerivedDataCache для маленьких описаний
(id/name/tags/density/size/owner), не загружая packed voxel arrays на cache hit.
Owner — Catalog._metadata_definition/_metadata_of; full definitions/definition/native_resource
и загрузка объекта для редактирования/размещения не изменены. user://ember-voxel-catalog-cache,
1MiB на record/16MiB trim, METADATA_VERSION1 + engine/ModelResource script SHA/path/full file SHA.
Путь файла перечисляется прежним _resource_paths, поэтому удалённые Source не оживляются кэшем.
ResourceLoader.has_cached сначала выбирает живой Resource: unsaved Inspector metadata видны,
но не записываются в persistent cache под хешем старого файла. Missing/remapped raw files или
отключённый cache directory оставляют прежний ResourceLoader-путь. Malformed/corrupt snapshots
перечитываются из native Source; snapshot не содержит geometry channels/Resource references.
Startup/обычное открытие используют один путь; панель/группы/поиск/preview renderer не менялись.
Metadata/source invalidation + library publication tests PASS; native UI/цифры — World Authoring.

DetailPreparation.material_patterns объединяет чтение сохранённых пресетов на один process frame.
Painted GrassPatch передаёт snapshot через прежний SurfaceMaterials.private_patterns; следующий
кадр перечитывает данные. ShaderMaterial и все изменяемые lookup textures по-прежнему личные,
scatter keys/бюджет/Source/history не менялись. Native parity/preview isolation/3looks/stale PASS.
Tail10,8→9,2с в focused-паре; полная readiness остаётся OPEN. Evidence — World Authoring.

Build28.10: DerivedDataCache.SHIPPED_CACHES расширяет прежний packaged fallback на7 canonical
каталогов, ключи/header/validation сохраняются; custom/editor caches не подхватывают packaged.
PreparedBundle/ExportPlugin принимают те же records. ExportPlugin отдельно включает original PNG
деревьев (ключи используют file SHA), удаляет только производные solid bindings с приватного Mesh;
Source/geometry/art materials сохраняются, Prop восстанавливает bindings до игры.
MapLoader editor-only singleton вместо прямого класса позволяет парсинг release template.
WorldCanvas._startup_status ждёт grass/look work и без сферы; Native barrier PASS.
StartupDiagnostics opt-in --ember-profile, без флага нет sampler/log writes; user logs1Гц/long frames/
CPU+GPU/pending/cache records. Tool run_world_build_probe.py проверяет standalone launch, не F6.
Cold shipped1333 hits/0 misses;≈68с до управления, сфера≈40с/first render≈17с — OPEN.
Размер/used-only bundle/динамический whitelist ещё не production. World Authoring → Windows-сборка.


`ember_voxel_mesh_import.gd` — bounded GLTFDocument preparation: normalize one closed static mesh,
explicit low representation via existing ImporterMesh.generate_lods, Y/Z triangle bins and even/odd
X-ray voxel fill. Limits20k triangles/262144 cells/2M bin refs; ambiguous open rows rejected.
UV/albedo sampling transfers colour into a bounded voxel palette. No new engine dependency/renderer.
`EmberVoxelModelResource.external_surface` — optional version1 provenance in the same Source,
empty for legacy. Original path/hash, prepared detailed/low paths, fingerprint of voxel frame,
paint/channels/material mapping. to_definition/existing Session FIELDS/validation include it.
`ember_external_mesh_surface.gd` owns validation/pristine decision; changed derivative always
uses the previous solid-volume renderer. `EmberVoxelProp` caches prepared displays in its usual
Mesh slot and returns canonical authoring_visual_state/physics; preview/Save use the existing Session.
No rebuild/import on world-look input. Original/low Standard materials are preserved; native voxel
rendering stays on the previous renderer. Shared/mixed roles and arbitrary material conversion OPEN.
`prepare_external_coastal_rock.gd` is the explicit first-asset recipe, guards existing native owner/
manual edits, publishes Source+prefab via ModelStore.install_prepared_asset. Cached appearances,
canonical voxel-boundary and collision are binary resources under content/mesh_models/coastal_rock/
prepared/<original+contract hash>/. Bump external build contract on algorithm changes; old referenced
versions remain available. Prefab≈1.3KB, Source≈216KB. Source GLB stays read-only.
Main ExternalCoastalRock is placed at(-40,15,862); original and Source: vox_external_coastal_rock.
Owners/gates/evidence — World Authoring → «Внешний камень: оригинал и три облика28.10».
Native source/editor/physics checks PASS. The same WorldAnomaly now accepts the pristine external
prop via External.anomaly_material: disposable opaque UV/albedo ShaderMaterial for this first rock,
original texture/roughness/metallic/specular retained; no mutation of prepared StandardMaterial.
Correspondence.carrier(reference_uv=true) prepares chart-local UVs/authored normals and uses a
separate external-uv1 cache key. Shared geometry targets/field and canonical physics retain owners.
Palette lookup comes from the ordinary voxel material; existing map cell/levels settings bind to
the adapter. Original StandardMaterial/mesh are restored outside the field or when disabled.
Native test_external_mesh_anomaly PASS (real preparation/global switch/motion/material/light),
ordinary anomaly_surface_light PASS. No Save path/schema changes in this adapter slice.
Not a general StandardMaterial converter: extra texture channels/transparency/features OPEN.
Manual mouse/author art/full main startup/F6 OPEN. Existing ordinary volume_smooth native PASS.

## Краткий контекст для синхронизации

Ember — проект 3D-игры с исследованием мира, диалогами, заданиями и клеточным
боем, вместе с нативными инструментами создания контента в Godot. Технические
инструменты и лаборатории уже работают в коде; завершённая каноническая стартовая
глава этим не подтверждается. Игровой канон принадлежит GDD, а не реализации.
`project.godot` запускает `scenes/landscape_compact.tscn`; старые sandbox, интерьеры,
`combat_lab` и отдельные terrain/water study-сцены. Это разные уровни готовности.

### Реализованные системы и владельцы

- Карта: `.tscn` владеет композицией, объектами и интерактивными областями;
  `scripts/ember_map_loader.gd` подключает Surface либо compact terrain и проекции.
  `EmberInteractionContent` читает каталог по native dependencies и saved
  map/region metadata через SceneState, включая instances/inheritance и transforms
  под `Regions`. Запуск узлов/JOI JSON для reference query не нужен. Метаданные
  отделены от live Resources, cache сверяет SHA сцен и зависимостей. Inspector
  target references проверяет сохранённую сцену; локальные несохранённые triggers,
  interaction binding и spawn используют общий `EmberMapLoader.find_region`.
  `EmberMapVisuals` показывает лёгкий список карт, затем схему сохранённых регионов
  выбранной карты; это не изображение рельефа. Нового persisted owner/schema нет.
- Воксельные объекты: `scripts/ember_voxel_model_resource.gd` — исходные данные;
  sculpt model/actions/workspace в `addons/ember_import/` — редактирование,
  генерация и Undo. Меш и физика производны от исходного Resource.
- Земля: `scripts/prototypes/ember_terrain_pilot_resource.gd` — компактные
  колонки высоты, материалов, воды и потока; projection/mesh строят вид и физику.
  `ember_world_editor.gd` маршрутизирует кисти и создание/расширение карты;
  `ember_world_edit_sessions.gd` владеет черновиком, Save и Discard.
- Материалы: `scripts/ember_compact_terrain_pattern.gd` — паттерн 16×16,
  три цвета и параметры поверхности; редактор — compact material component:
  параметры в `Ember · Мир`, сетка в нижней панели «Рисунок земли».
  Воксельный свет: чистая shader math — `ember_voxel_light.gdshaderinc`, вызовы в terrain/toon shaders;
  параметры — Map (`voxel_light_cell_m`, `voxel_light_levels`), UI — прежний WorldLookPanel.
  Projection/Prop/GrassPatch связывают только uniform; anomaly clones обновляет существующий signal.
  Tree materials принадлежат derived mesh своего Prop/облика; общие prefab/cache materials не изменяются.
  POM colour/DEPTH прежние, shadow-light sample ограничен исходной height cell. Трава использует
  ember_texel_plane_shift → view-vector только в painterly_blades; остальные consumers прежние.
  Grass shimmer regression/PCSS grain — Terrain Authoring → «Воксельный свет основной карты».
  TAA — scene-owned Map.use_taa (old default false, main true); прежний filter main5(Ultra).
  Map.apply_viewport_quality — единый runtime/editor viewport binder; WorldLookPanel слушает quality_changed,
  настраивает4EditorInterface viewport и восстанавливает их baseline при смене/закрытии Map/release.
  Sun мягкость/дальность/каскады не переписываются. Gates/cost/limitations — Water Rendering → «Вид мира».
- Вода: compact terrain хранит наличие/уровень/поток, scene/material — вид;
  `ember_compact_planar_reflection_study.gd`, `ember_compact_river_phase.gd`,
  `ember_water_contact_3d.gd` строят пробный рендер и контакт. World Look panel
  и water preview debugger передают настройки F6 в авторскую сцену через Undo.
- Мир: `ember_player.gd` — движение; `ember_party_followers.gd` — следование
  группы; `ember_interact.gd` — двери, события, задания, магазины и сундуки.
- Контент: dialogue/action/quest/item/shop Resources и catalogs — определения;
  `ember_graph_workspace.gd` — авторинг диалогов/цепочек, VN-preview и переход
  к связанному объекту в 3D. Наличие этих функций не закрывает весь удобный UX.
- Прогресс: autoload `EmberExploreProgress` из `ember_explore_state.gd` —
  флаги, группа, инвентарь, магазины и сохранения; `ember_party_state.gd` —
  расчёты/нормализация группы, не второй writer сохранений.
- Бой: `ember_combat_prototype.gd` — единая модель preview/commit;
  Battlefield Resource — клетки, высоты и hitbox; Encounter Resource — состав,
  арена и результаты. `ember_combat_transition.gd` — переход мир/бой/мир.
  Редакторы Battlefield/Encounter и отдельный 3D painter уже существуют.
- `addons/ember_import/plugin.gd` подключает инструменты; editor preparation
  обслуживает подготовку редактора, а не становится owner игровых данных.

### Форматы и степень готовности

- `.tscn` — карты/арены; `.tres` — voxel, dialogue, action, quest, item, shop,
  combat и material Resources; compact-карты также используют бинарный `.res`.
- Voxel schema — 7 (optional published tree surface; legacy empty); compact terrain читает плотную schema 1 и адресную schema 2,
  16 колонок на блок. Schema 2 хранит созданные участки 24×24 м внутри того же
  Resource, без плотных корневых каналов. Потоковая загрузка ещё не реализована.
  29.10 `TerrainSections.MAX_AXIS=24`: envelope576м, без смены schema. `window()`
  выбирает пересекающиеся payloads адресно; aligned flow и SurfaceRules сохраняют прежнюю
  семантику/метаданные. Validation повторно проверяет shared payload только один раз внутри
  вызова, без долгоживущего кэша. Это не lazy file I/O: `.res` декодируется целиком.
  В editor для большой schema2 Map/Projection теперь считают бюджет fine tiles; малые карты
  и runtime сохраняют старую границу. Projection хранит/освобождает near mesh/collision/field,
  MeshBuilder.OverviewJob готовит coarse массивы секций через прежний bank-material contract.
  Обе стороны стыка имеют визуальное закрытие; оно не меняет fine physics/Source.
  Floor query сохраняет `solid`/каноническую высоту вне физики, добавляет `physics_ready`;
  вне resident tiles хранится максимум последнее временное поле, не вся карта.
  Grove/Plan теперь допускают массовую расстановку; source file I/O, runtime,
  дистанционная активность объектов и остальные потребители остаются OPEN.
  Dataset/evidence — [Производительность мира](EMBER_WORLD_PERFORMANCE.md#владельцы-и-работающий-путь) → «Владельцы и работающий путь».
- Runtime save v2 — JSON в `user://ember-save-v2`, три ручных слота и autosave.
  Legacy JOI JSON пока остаётся совместимостью, не новым каноническим форматом.
- Текущий native inventory: 93 voxel `.tres`, 2 dialogue, 2 combat action,
  0 quest, 7 item, 0 shop
  и один encounter (`colored_crossing_demo`). Это инвентарь файлов, не доказательство
  валидности, полноты миграции или готовности главы; бойцы/действия — отдельные Resources.
- Вступление боя принадлежит `colored_crossing_intro.tres`, затем action
  `colored_crossing_start` запускает тот же `colored_crossing_demo`. Старый
  sandbox dialogue ID выведен; Resource UID и прежний `new_flag=true` сохранены.
  Текст/переходы/UI publication/save проверены; ручной диалог → бой OPEN.
- Полный Layout/planner дорог, рек и поселений пока относится к архитектурному
  плану. Генераторы объектов и работающие кисти не означают, что он уже готов.
- Ближайший шаг — авторская проба адресной основы/рельефа и контракт разметки;
  приёмка воды/материалов отложена автором. Точный статус и возврат — в NOW;
  последующие результаты — в Product Plan, без автоматического расширения задачи.
- Аудит проверяет исходники и связи, не запускает игру и не подтверждает PASS.
  Живые Forward+ gates воды, editor lifecycle, партии и боевых переходов остаются
  отдельной приёмкой. Отдельные лаборатории не переносить на все карты автоматически.

### Фактическая legacy-граница

Запрет новых JOI-зависимостей действует. Runtime item/icon/shop/action/dialogue/VN
и voxel catalogs native-only; exploration startup не делает map JSON reimport,
region/footprint hydration или legacy roof build. Native сценам old pack не нужен
для этих paths. EmberPack при пустом pack_path всё ещё ищет sibling JOI для явных
offline import/migration tools. Активные editor open/selection/Canvas/rebuild/
diagnostics не читают pack; UI reimport/legacy links/migration batches удалены.
Missing native source не запускает импорт и не меняет готовый объект. Старые
load_map/EmberPack helpers и offline migration APIs ещё физически существуют;
export boundary, retired references и physical G4/G5 требуют отдельной сверки. Retired контент не переносится целиком.
Текущий статус/архив — JOI Exit Plan и NOW; old baseline ниже не заменяет их.


## Неподвижные технические границы

- Godot 4 Forward+ — единственный runtime и authoring target.
- Текущий 3D physics backend — встроенный Jolt Physics, owner `project.godot`.
  HeightMap/Concave,Source и controller прежние;native surface/step/Hoshi/crates/
  dense cold/return проверены. Restart редактора и ручное ощущение OPEN;
  измерения/границы — [World Performance](EMBER_WORLD_PERFORMANCE.md).
- Карты принадлежат `.tscn`.
- Canonical voxel source — `content/voxel_models/*.tres`
  (`EmberVoxelModelResource`).
- Mesh, collision, thumbnail, prefab и MeshLibrary — производные данные.
- Не создавать второй renderer, voxel editor, combat resolver, gameplay/save owner
  или параллельную schema без отдельного доказанного архитектурного решения.
- Preview и commit используют один расчёт.
- Editor-only selection, overlays, camera, layout и transient preview state
  не сериализуются в gameplay Resource.
- Collision, высота и navigation игрока/AI должны читать одну физическую поверхность.
- Целевая граница: legacy JOI доступен только importer-у; новые runtime-зависимости
  от sibling JOI запрещены. Существующий долг — в «Фактическая legacy-граница» выше.
- Общая математика должна жить в чистых leaf-модулях; UI маршрутизирует команды.
- Тяжёлые операции не выполняются на каждый мелкий input: preview дешёвый,
  точный commit выполняется на pointer-up/Enter.
- Изменение schema закрывается вертикально:
  Resource → validation → editor → runtime/preview → serialization → tests → docs.

## Слои и зависимости (решение автора 22 октября 2026)

Source (воксельные данные, хозяин формы) → генераторы (создают Source) → планировщик
(где и что поставить) → облики (Source → форма и материал) → материалы и текстуры →
свет и окружение. Нижний слой не знает верхних. Планировщик знает модель и вид, но не
способ генерации. В существующем palette-пути материал адресуется по material_id,
а не по типу объекта; это не обязательная новая схема для всех поверхностей и воды.
Облики имеют один вход (Source → форма и материал); стратегия зависит от типа
поверхности (твёрдое, ветви/листва, земля). Состояние по направлениям — docs/directions/.
Известный долг: слой «облики» пока реализован отдельно для камня, дерева и земли.

Общая цель — предсказуемое назначение/изменение материала через обычный editor,
его preview и сохранение у заявленных потребителей. Один шейдер для всего мира
не требуется: геометрия/шейдеры земли, твёрдых объектов, листвы и воды могут различаться
у существующих owners. Набор общих свойств и применимость проверяются до расширения;
готовность земли/камня не доказывает подключение дерева/травы/воды. Это целевая
граница, не утверждение о завершённой интеграции. Процесс — Workflow → «Общие изменения и потребители»;
текущий срез — directions/world-map.md, совместимость воды — EMBER_WATER_RENDERING.md.

## Карта owners

### Voxel data, Canvas и Surface

- Массовая расстановка29.10: прежние Grove/Plan считают local support только у кандидатов,
  LRU≤16 полей; region budget64 на24×24м, общий минимум256 и64 на созданную секцию.
  Это authoring quota, не runtime/LOD budget. Provenance v2 исключает служебные render units
  и instance light; legacy v1 продолжает защищать несовпадения. Новая схема Source не вводится.
  `ember_tree_look_bake` разделяет immutable meshes между экземплярами; fast cache ограничен
  четырьмя Source, инвалидируется Resource.changed и editor filesystem_changed.
  `EmberVoxelProp` держит отдельные surface override materials; authoring_visual_state/PRE_SAVE
  восстанавливают authored bindings, snapshots сохраняют prefab refs без производных мешей.
  Native859 props PASS; `_submit_grove` теперь использует прежнюю generation queue и
  `Grove.begin_publication/step_publication/take_publication`: до commit узлы без owner,
  native packing/Grove snapshot их исключают; отмена/save hook снимают весь partial batch.
  Stale проверяет прежние объекты, исключая только свои временные экземпляры. Финальная
  history-команда назначает owner уже подключённым узлам без повторного `_ready` всего batch.
  Подробности локальны после distance-среза ниже; полный residency/HLOD OPEN.
  Замеры Apply до distance-среза — [Производительность мира](EMBER_WORLD_PERFORMANCE.md#владельцы-и-работающий-путь) → «Владельцы и работающий путь».
- Object distance29.10: MapLoader владеет очередью/наблюдателем и bounded8 shared LOD meshes;
  Prop — transient near/far carriers и authored bindings, WorldDetailPolicy —36/44м по bounds,
  выбор/authoring preview/draft защищены. Прямую замену Mesh новая очередь не перезаписывает.
  CPU geometry helper — прежний `ember_terrain_mesh_lod.object_mesh`: SurfaceTool.index,
  ImporterMesh native index LOD; Source/physics и три художественных облика не заменяются.
  Подробные формы/материалы восстанавливаются по одному prop; mesh publish/bind также порционные.
  `TreeLookBake` и `SolidMaterialLayers` держат weak carrier refs: живые потребители разделяют
  geometry, кэш не удерживает ненужный последний carrier. Для рощи/публикации без owner
  подготавливается только выбранный подробный облик; save-post возвращает вид через очередь.
  Editor detailed look0; runtime/другие облики сохраняют прежний путь. Root nodes/canonical
  collision/Source остаются в памяти. Замеры/открытый return step — [Производительность мира](EMBER_WORLD_PERFORMANCE.md#владельцы-и-работающий-путь) → «Владельцы и работающий путь»; полная выгрузка scene nodes/HLOD не реализованы.
- Return29.10: `SolidMaterialLayers._prepared`≤8 держит weak GPU mesh и CPU arrays/face Image;
  `_prepare_data` отделён от `_publish`, Source mesh.changed инвалидирует запись.
  Face descriptors не пересчитываются при обычном возврате. Prop._solid_source держит≤4
  model Resources (authoring_source bypass; changed/filesystem_changed invalidation),
  `_living_for` использует packed snapshot. Это read/preparation cache, не второй Source owner.
  Native return step27мс; обычные ShaderMaterial/physics/serialization contracts сохранены.
  GrassPatch cold scatter использует прежний MapLoader._solid_floor_candidates один раз на
  расширенный patch; однопараметрический surface_floor_sample сохранён, локальный список
  передаётся через surface_floor_sample_with_candidates.
  DetailPreparation/cache format неизменны; exact21 records трёх обликов сохранены.
  Native2304 patches cold ready23,2→6,3с. Стартовые material templates готовятся штатным
  ResourceLoader у DetailPreparation, pipeline cards — существующим EditorPreparation gate;
  shader body один в ember_compact_terrain_body.gdshaderinc, private material bindings сохранены.
  Mesher готовит residency edge arrays в CPU worker; Projection восстанавливает overview
  один раз на регион до release и делит текущий shared budget с grass (Performance owner). Policy добавляет tile запаса
  для дальних углов retained patch при прежнем budget≤384.
  Shader peak170→51мс, moving near ready194/194; общий moving frame/ручной вид OPEN.
  Сплошной луг29.10: existing DetailPreparation содержит weak sleeping registry с ограниченным
  round-robin опросом вместо callback каждого дальнего GrassPatch; Projection опрашивает его.
  Runtime с authoritative detail_poll_epoch завершает sweep один раз до изменения inputs;
  bounds setters/transform reindex инвалидируют его. Paused ancestor сохраняет retry;
  editor/custom projection без epoch остаётся на periodic fallback. Ни Source,ни residency
  policy не меняются;cost/evidence и открытый120 gate — EMBER_WORLD_PERFORMANCE.md.
  GrassPatch хранит typed map Node с is_instance_valid,очищает при exit/reparent;
  Node reference не удерживает удалённую карту. Context/sleeping refs остаются weak.
  project.godot задаёт PSO cache save growth64MiB;cache enabled,save-on-exit прежний.
  Это снижает частоту тяжёлой сериализации,не ограничивает cache и не закрывает stalls.
  Instance shader buffer524288 vec4 slots (8MiB) вместо65536: общий dense population
  stress превысил прежние4096 instances и воспроизвёл renderer allocation errors.
  Это конечный запас32768 instances, не доказательство отсутствия утечек.
  EmberAnimationDistanceLod — leaf policy HoshiVisual: near/party full,30/15Hz,
  offscreen5/hidden2Hz; накопленное время для pose/morph/secondary bones, без
  замедления physics/AI. Flight/ragdoll сохраняют владельца; near-offscreen full.
  HoshiVisual `important_character` — export-флаг важного героя хаба независимо
  от активной партии. EmberPlayer/EmberPartyFollowers защищены автоматически.
  HoshiVisual удерживает одну avatar PackedScene/AnimationLibrary:instances сами
  не сохраняют PackedScene cache. Streaming caller вызывает `prepare_resources(host)`
  до reveal;готовность включает toon/outline templates. Sync setup остаётся fallback
  первого player. GPU crowd palette/clock пока external QA,не второй runtime owner.
  HoshiVisual `_select_motion()` сохраняет default idle/walk/run;stress subclass
  выбирает клип через этот же crossfade/LOD/blink owner. Только locomotion меняет
  playback speed от скорости тела. Stress controller отдельно чередует idle/walk/run;
  `test_crowd_animation_mix` с `EMBER_STRESS_MOTIONS` добавляет talk/sit/dance.
  Retarget tool поддерживает `clips=idle,walk,run,talk,sit,dance`;default по-прежнему3.
  Библиотека6клипов создаётся в отдельный output,private original motion не перезаписан.
  Projection `prepare_floor_query(point)` готовит один точечный CPU snapshot в
  штатном WorkerThreadPool;FieldJob использует прежний halo/фильтр/правила формы.
  Один task наprojection,результат принимается только для того же document/revision;
  смена/закрытие joins task через `_cancel_mesh_lods`. Обычные массовые запросы
  сохраняют full-tile cache;prepared point не заменяет renderer/collision/navigation.
  Stress preload сцен — ResourceLoader,публикация по одному цельному объекту закадр.
  Crate records восстанавливаются после подключения всего пакета;иначе частичный
  stream создавал лишние физические экземпляры. Body admission guard:11→27 (+16).
  У ordinary NPC экземпляры SpringBoneSimulator3D.active=false;body/morph/physics
  продолжаются. Важность возвращает только authored-active springs с reset истории
  после новой позы. Партия4 не ограничивает число важных героев(минимум8 поавтору).
  Original avatar/motion/REST неизменны;редкие hero hair ticks не реализованы.
  Подготовка Hoshi01.11: stage_hoshi_avatar.py → hoshi_avatar_bake.gd.txt →
  tools/fixtures/hoshi_native_lods.gd. Native ImporterMesh генерирует index LOD тела/
  волос offline. В производный ArrayMesh переносятся только LOD indices; исходные
  packed vertex/normal/tangent/skin streams сохраняются (повторный native encoding
  иначе округлял normals/tangents). Face с57blend shapes остаётся исходным.
  tools/prepare_hoshi_native_lods.gd может подготовить уже staged avatar в явно
  указанный output без Companion/config; текущий private avatar подключён на main,
  backup вне Git у evidence. CPU runtime generation/new renderer не добавлены.
  Это render LOD,не полная выгрузка NPC/rig/AI. Body и gameplay/save owners прежние.
  Geometry diagnostic01.11 принадлежит EmberBenchmarkOverlay, подключённому ExploreScene:
  F2 normal/native LIGHTING/wire,Shift+F2 mesh_lod_threshold0/full или исходный auto.
  Только session viewport state; authored mesh/material/Source не меняются, exit восстанавливает
  исходный debug draw/threshold. Native primitive counters и FPS окна не заменяют stress gate;
  alpha/vertex caveat, main counts и evidence — Performance → «Геометрия отдельно от материалов».
  EmberRuntimeShadowLod — производный SHADOWS_ONLY mesh с native LOD, теми же
  материалами и явными instance overrides. Полный binding/eligibility остаётся
  в существующем bounded object-detail poll;камера вызывает Prop.recheck_runtime_shadow_receivers
  и helper.recheck_receivers уже готовой геометрии. Derived bounds/transform/layers обновляются
  полным poll;изменения Source/receiver/party/local lights/low Sun возвращают full caster.
  Решение о full caster общее для обоих путей;новой очереди/формата нет. Map profile сохраняет
  object-only process_us и отдельно публикует shadow_context_us/total_process_us.
  Native guards/A-B-A/render parity и пределы — Performance «Исправление CPU shadow-context04.11».
  Count-bounded poll128 дополнительно уступает после≈1мс с сохранением cursor;
  допускается хотя бы1шаг,explicit full refresh(max_props0) прежний. Native шаг и
  финальная сортировка могут превысить порог;это не обещание hard1мс всего callback.
  Instance writes Map rim/FruitTree/WorldAnomaly идут через helper.forward_instance_parameter:
  Source setter прежний, proxy получает запись через WeakRef metadata binding.
  Stable poll не читает RS uniforms; raw внешние setter требуют helper.invalidate_instance_parameters.
  Geometry/material/caster setters также coalesced по текущему значению: native
  same-value surface material/cast setters всё равно ставили instance dependencies
  на обновление. lod_bias сравнивается is_equal_approx из-за float precision.
  Источник восстанавливается до удаления proxy. Temporal directional cache отложен
  решением автора: остаёмся на штатном Godot.
  MapLoader physics activity использует weak registry существующего WorldRecovery:
  CharacterBody/RigidBody удерживают terrain support; безопасные дальние
  StaticBody отключаются штатным DISABLE_MODE_REMOVE без смены shape/source.
  Возврат36м, удаление48м; teleport/recovery сперва поднимает опоры, затем ждёт
  подробный пол. Изменение кванта одного участника пересматривает только его окрестности.
  WorldRecovery принимает opt-in `runtime_simulation_required()->bool` у CharacterBody:
  controller владеет importance/quest/combat/view/shadow demand. False приостанавливает
  только его physics callback и исключает anchor;Node/pose/velocity/state остаются.
  True возвращает anchor/пол до движения;priority-200 перед Map-100. Cancelled wake,
  independent pause,снятие opt-in при wake,смена World3D/removal owner сохраняют callback ownership.
  Текущий consumer — passive stress PopulationActor:near/shadow guard64м,важные always-on.
  Без opt-in прежний tick/support;RigidBody включая sleeping/frozen остаются anchors.
  WorldItem сохраняет свой progress/freeze owner. Source/shape/NPC RAM paging и
  production AI этим не реализованы. Проверки/пределы — Performance → шаг3.
  Общий gameplay stress01.11 — tools/test_world_gameplay_stress.gd:runtime copy main,
  external576 fixture bundle,32Hoshi+production harvest-prefabs с независимымиIDs,
  real Player strike/nearest/interact/autosave,SourceSHAguards. Никакого нового
  runtime owner/схемы механик. Full vs interactions scopes и результаты — Performance.
  Тотжеharness mode=cpu даёт reversible NPC motion/animation/secondary/blink иworld
  callback ablations;самproduction runtime этимрежимом не меняется. Clean иprofiled
  интервалы раздельны;native coroutine total неexclusive CPU. Findings — Performance.
  Flag-gated unavailable WorldItems остаются в recovery/save registry,но исключены
  из eager floor preparation и physics anchors. Hide re-arms waiting;reveal/available
  restore делают once prepare и readiness hold доthaw;pending impulse применяется одинраз.
  Обычные frozen/sleeping/carried/actors не фильтруются. Focused physics check PASS;
  общий dense outcome — Performance. Это ещё не полная выгрузка дальних dynamic props.
  Очередь coroutine turns возобновляется через SceneTreeTimer после Node._process, земля раньше
  scatter; edit/draft wake приоритетен. Exit/release отменяет waiters и возвращает processing.
  Это scheduling производных в editor/runtime;он не выгружает весь мир и не меняет Source/Resource.
  Dispatcher учитывает фактический ground slice через finish_ground; время постороннего
  editor/UI между node phase и timer не отнимает allowance. Editor scatter starts/worker
  resumes входят через in_budget_turn, без обхода очереди через deferred starts.
  Очередь сортируется по прежнему camera ground-focus: полосы4м, FIFO внутри полосы,
  edit автора раньше расстояния. Новый ticket вставляется в порядок; общий пересчёт
  только при изменении anchor. GrassPatch exit/residency release немедленно отменяет его
  waiters. Это освобождает coroutine data, не меняет Source или радиусы видимости.
  После готовности12×12м focus-core ground оставляет4мс для ожидающего scatter из общего
  allowance8мс; при недостроенном core/отсутствии scatter земля сохраняет8мс.
  Core — прежний travel gate, не покрытие всей видимой камеры; wide/manual gate открыт.
  Реализация команды29.10: working Ground factory использует existing compiled far shader
  без POM/manual DEPTH/искусственного normal relief во всех3 обликах; height bank не строится.
  EmberVoxelSurfaceMaterials хранит special-object depth APIs; presets не переписаны.
  MaterialPatternDialog/_open_material_pattern дают ground context и правдивые disabled
  relief controls. Grass/flower препроцессор исключает optical/coastal работу; single-slot
  shortcut сохраняет цвет/свет. Native foliage24/24RGB exact; сохранения/preset/history PASS.
  SmoothSurface производит disposable render_detail: exact planar collapse и native
  ImporterMesh/meshoptimizer LOD с проверкой реальной ошибки fine поверхности. Полные
  arrays/layout/collision остаются каноническими. Mesh publication/GeometryCache переносят
  render LOD отдельно; LookBake получает прежнюю fine topology и сохраняет tangent.
  Оба blend=true/false имеют LOD; одинаковые palette IDs нормализуются только внутри
  simplifier input. False-only cache namespace обновлён, true arrays/key битово сохранены.
  Projection/MapLoader/GrassPatch/DetailPreparation работают с bounded residency и runtime.
  Старые имена supports_editor_residency/editor_detail_active сохранены, семантика общая.
  WorldCanvas передаёт set_runtime_start_anchor до создания Player/FollowCamera, затем
  observer использует actual camera и защищает target/party. После saved/transition spawn
  есть второй near-ready gate. Резкий произвольный teleport пока отдельный открытый риск.
  Projection теперь заранее создаёт пустые resident tile hosts по прежнему column budget
  (384 на576м fixture), включая Ground/Water/Physics/ResidencyEdge. При обычном движении
  _tiles меняет ключ→host; host не удаляется/не переименовывается, GPU buffers/materials/
  physics shape очищаются на release. Общий запас hosts ограничен capacity; временно
  защищённые brush tiles допускаются сверх него и удаляются при освобождении.
  Overview ResidencyEdge также создаётся заранее. Иначе любой late child заставлял native
  editor повторно запрашивать property lists всех25848 authored patches. Source/schema/
  density/radii/physics data прежние; hosts не имеют owner и не входят в PackedScene.
  GrassPatch density_cells — read-only snapshot: assignment копирует Dictionary и один раз
  проверяет storage validity; brush/history заменяют целую маску. In-place mutation не путь записи.
  Сохранённые density_cells/density_mask и формат прежние; _get_property_list объявляет только
  их dynamic storage вместо _validate_property на каждом унаследованном Node3D property.
  Пустой внутренний DerivedGrass создаётся при _ready; preparation/release меняют только
  disposable buffers/materials, не добавляют узлы и не инвалидируют весь editor scene tree.
  GrassPatch не пересылает неизменные fade uniforms; shader identity входит в ключ состояния.
  MapLoader rim recognition включает common-body wrapper. EditorPreparation принудительно
  обновляет autowrap через get_line_count перед container minimum: старый height2170px исправлен.
  Условия/проверки — [Производительность мира](EMBER_WORLD_PERFORMANCE.md#владельцы-и-работающий-путь) → «Владельцы и работающий путь».
- Oak look pilot16 Oct: `ember_tree_look_bake` derives wood/canopy from the published
  Source and `ember_tree_surface.leaf_layout`; geometry roots carry patch descriptors
  without changing accepted card buffers. `compact_oak_looks_study` is the only caller
  selecting the extra visual shell. Shared `ember_object_look_clip` is disabled by
  default; opposite local planes affect colour/shadow passes. Existing toon/rim/leaf
  parameters retained; voxel leaf wrapper removes alpha clipping from solid cubes,
  bark pixel sampling defaults to0. Voxel leaf CUSTOM2 carries source-group normals
  for the shared rim; diffuse CUSTOM1 remains faceted. `build_faceted` uses6-sided
  branch tubes + folded alpha leaf patches from the same supports, unpixelated art.
  `ember_leaf_shape_mask` derives three contour fields from separate alpha leaves;
  `ember_tree_faceted_leaves` uses the same toon body with faceted-only shape/amount
  uniforms. Original RGB/PNG remain owners; mask is process-cached LAB data, not
  a Source field. This clips contours, not area-preserving shape replacement.
  One existing wood collider. No schema/editor/
  production WorldLook integration, export bake or universal morph. Detailed rules,
  limitations and acceptance — Terrain Authoring → «Три облика одного дуба».

- Accepted rock group production transfer17 Oct: canonical voxel Source
  content/voxel_models/vox_painted_rock_group.tres retains all six occupancy/part IDs.
  Optional Resource.solid_surface publishes plane directions + occupancy reference;
  ember_voxel_solid_surface fits supports, existing Prefab owns mesh AND collider.
  Manual sculpt invalidates the published hull and uses exact voxel meshing.
  Model duplicate deep-copies PackedVector3Array; Canvas dirty/save/discard tracks
  the new field. Existing model/tree/terrain paths opt out by default.
  Prop/Map floor queries share transformed triangles; compact navigation samples
  them and invalidates on transform/mesh changes. Map light mode also binds props.
  Deferred rim binding now uses WeakRef: transient Canvas nodes may disappear
  before the deferred call; no invalid typed Node is queued.
  Ordinary saved scene compact_environment_material_review.tscn references a saved
  ground Source with1619 old rock columns lowered, plus actual rock/oak props and
  accepted grass buffer. Reopen does not execute LAB geometry/foliage recipes.
  This supersedes the LAB-only physics limitation FOR THIS GROUP/compact scene;
  it is not a generic terrain rock converter or a global world switch. Surface
  vertices differ from the accepted triangulated LAB hull by≤1.823mm (gate2mm).
  Evidence/tests/manual gates: Terrain Authoring → rock form/colour;
  current author acceptance: directions/objects-looks.md (detailed look/living faces not accepted).
  20 Oct: solid_surface.build also writes CUSTOM0 form normals (CONTRACT v2, welded,
  angle-weighted); material_for opts into object-local projection + form rim via
  solid_projection_mode/solid_form_rim/solid_facet_bias/solid_local_unit_m
  (apply_form_look; Prop syncs unit from block_world_size). The terrain shader keeps
  these uniforms off by default. cartoon_stone owns rim 0.5 (style_rim_*), band solid_rim_edge 0.17..0.21
  (ember_stylized_rim_shaped; shared ember_stylized_rim keeps 0.10..0.32).
  CUSTOM1..3 = distances to convex hull edges + neighbour normals (attach_edge_frame; CONTRACT v4);
  the vertex shader keeps only silhouette edges; Pattern.style_rim_width_mm (GPU lookup alpha,
  dialog slider) frames the rim, min 1.5 px; width 0 = old facing band. Rim form normal travels to light()
  via texture_projection_normal (varying budget is 32).
  Detailed look (look 2): solid_surface.material_for(mesh, true) uses solid_depth_shader()
  (#define EMBER_SOLID_DEPTH + material depth include variants) and binds a height map from
  scripts/ember_material_height.gd (Pattern.depth_*); Prop syncs solid_depth_world_to_local and
  the sun direction; test_rock_detailed_look / test_depth_control.
  Living faces (look 2 geometry, 22 Oct): solid_surface.hull_faces is the one face enumeration for
  build() and living_mesh(model, unit_m, pulls) (cached; LivingFaces inner class: blurred occupancy field,
  Delaunay per face, pull fades at hull edges and at creases with other parts' hulls, form normal read back
  from the hull fan). Pattern.form_pull_mm per palette slot (living_pulls); Prop._living_for/_sync_living
  swap the mesh, the editor releases the slider to rebuild. surface_floor_sample now reads the hull mesh,
  not the displayed look. test_rock_living_faces / test_depth_control.
  B material layers25.10: Pattern owns six optional stone_* controls (legacy opt-out);
  existing dialog owns history/Save/Cancel and routes through light_profile_previewed.
  SolidSurface.material_for + Prop._living_for bind ember_solid_material_layers.gd only
  to detailed solid meshes. It reuses hull_faces, caches labeled copies (UV2.y), unchanged
  positions/collider; old prototype is a shim. ember_solid_material_layers.gdshaderinc shares
  base renderer/POM; no second renderer/new varyings. Color/height use matching face UV.
  Per-slot numeric table updates from CPU Image; no GPU readback/remesh on slider input.
  Physical edge width uses object scale; low/voxel remain unchanged. Anomaly carrier forwards
  one detailed face ID per carrier triangle (layered cache3, other refs2); profiles share live
  texture with clones and effects fade with the common sphere field. refresh_material_bindings
  already forwards all uniforms. cartoon_stone enables B; source/prefab/map bytes unchanged.
  Focused editor/depth + native main/looks/sphere/fresh PASS; physical input/art acceptance OPEN.
  Owners/gates/evidence — Terrain Authoring → «Слои камня Б», directions/materials.md.
  Ray context01.11: existing EMBER_DEPTH_CONTEXT passes cached weathering weight,
  triplanar axes and width divisor per fragment, in addition to edge context.
  Optical depth/steps/fades and paint/profile data unchanged; ordinary finish keeps
  its wrapper, no extra varyings. Comparison material() expands the shared body include
  before inserting its old hooks. Native editor/three-look cycle PASS; main GPU evidence
  and dense acceptance belong to Performance → «Дорогой ближний камень».
  SolidSurface.far_depth_shader reuses the full program bindings but compiles out
  POM/manual DEPTH after fade. Prop._sync_depth_program chooses by full world AABB,
  restores near/editor/active Source/no camera, keeps material identity; runtime priority1
  follows default camera0. No change to published material/source serialization.
  Native bound/pixel/cache/3look and dense moving render checks PASS;whole120FPS OPEN.
  Stock LightmapGI01.11 compatibility ONLY: tools/editor_test_static_shadow_bake.gd builds
  a disposable main-source patch+rock fixture, tools/fixtures/ember_lightmap_probe.gd
  preserves native indexed upload, remaps UV2 palette/face IDs into spare CUSTOM0.w,
  then rebuilds native LOD indices without replacing accepted packed vertex streams.
  tools/test_static_shadow_bake.gd proves static cached shadows and dynamic receiver limits.
  No production Source/schema/material/editor path changed. Hybrid integration,3looks,
  revision invalidation,memory/full stress and editor clean exit OPEN;Performance owns evidence.
  Weathering28.10: Pattern.stone_weathering_enabled / прежний dialog / stone_profiles row1.z.
  Detail-only coverage/height; optional explicit edge context in common parallax, no new varying
  or plant cache overwrite. Off retains legacy branch; owners/gates — Terrain Authoring →
  «Связная фактура стыков28.10». Native switch/history/save/main3 looks/shared bark compile PASS.
  Building Massing v0 (25.10): ember_voxel_building_generator.gd is another provider in existing
  Generator/Recipe/Creation/GenerationPanel/GeneratorPanel. Source/prefab/recipe vox_coastal_house;
  ordinary convex parts + voxel_part_ids/solid_surface, same SolidSurface look/physics owner.
  Source buffers are filled locally, bounded2 097 152 cells; candidate_limit1. Metre descriptors use
  float precision/arrow steps, old integer fields unchanged. Shared hull_faces colour fallback checks
  the part owner in eight cells incident to its support corner. Single-colour signatures unchanged;
  multicolour derived contract adds solid-part-palette-v1. Prop material refresh defaults missing gray/mode.
  Native house editor/save/history + three global main looks PASS; old rock buffers identical.
  Manual art/input OPEN; exterior masses only. Details/gates — World Authoring → Building Massing v0.
  Building plan05.11: BuildingLayout/BuildingPlanField extend existing GeneratorRecipe.structure,
  both creation/edit panels, Canvas forwards optional3D plan input. Rectangular core + one low rear annex;
  lightweight draft/release Undo, explicit exact preparation, shared variant save/protection.
  Optional validated solid_surface.building_entry is derived point/normal, baked to prefab mesh
  metadata. EmberBuildingEntrance reads the published authoring mesh frame; no runtime recipe.
  Entrance/return follow Source update/Undo/3looks; runtime process stops after initial placement.
  wing_side/width/length are provider parameters; Layout owns exposed edges/bounds/frame offset.
  Existing house edit freezes Recipe.fixed_corner. The generated solid_surface.building_offset
  feeds the prefab mesh/collision position adapter. The viewport uses the same offset relative
  to the open Source, including on a second edit. Legacy Sources without the offset keep their frame.
  Five annex convex parts, lean-to below main eave; original roof coverage retained, cap32 unchanged.
  With wing_roof=1 the full-height gabled wing shares the exterior slope and clips both roof
  extents at the join. Its five parts use the same Source/convex prefab path.
  Optional opposite_wing uses the same provider with its own dimensions
  and roof. Layout owns wall IDs 7–9 and the gap between roof overhangs.
  Roof option 2 clips the main and perpendicular wing slope at their equal-height
  plane. A six-part convex wing includes the infill under the valley.
  Low wings can slide along the rear wall with wing_inset_m / opposite_inset_m.
  Layout reserves wall IDs 10–11 for rear strips exposed by a slide.
  wing_on_side rotates one lean-to and its wall frame by a quarter turn. The
  convex fill keeps ordered grid bounds. Wall segment 12 is for picking only,
  remapped to its original side-wall opening ID before save.
  entry_canopy adds three convex parts in the door frame using the existing
  roof/timber slots. Layout guards the budget and the adjoining roof footprint.
  window_style applies a shared profile to all window openings. The stone chamfer
  and arch preserve the frame/glass two-part contract and existing opening IDs.
  Main CoastalHouse uses vox_coastal_house_wing32parts, original/layout variants preserved; coastal_house_interior
  uses existing ExploreScene/MapLoader/MapTransition. Native layout/wing/Canvas/save/route/actual3looks PASS;
  manual input/art/dense quarter/large mixed assemblies OPEN. Owner — World Authoring plan05.11.
  Cliffs v0 (26.10): ember_voxel_cliff_generator.gd in the existing registry/recipe/workspaces.
  Three layered Sources/prefabs/recipes on main, 16 vox/m, max524288 cells, candidate_limit1.
  form_strength defaults0 for existing recipes,65 for new ones; 9/18 convex pieces model
  irregular contours, tapered walls and terraces (0 preserves the old3/6-piece form).
  Same main assets updated; Evening preset/visible warm sky saved in existing scene nodes.
  GeneratorGeometry owns the unchanged shared convex fill; house delegates to it.
  SolidSurface/Prop owns look meshes and physical support; no terrain/schema/union replacement.
  Native Source/editor/persistence and9 main-copy look/support comparisons PASS; manual art/input OPEN.
  Canvas Grab silhouette (26.10): Fragment._grab_plan + SolidSurface.grab_profile include the
  compatible occupancy profile in the same preview/Undo transaction; unknown ownership stays protected.
  ObjectSession compares/captures Prop.authoring_visual_state; refresh_authoring_projection clears
  stale solid look caches after publication/Undo while retaining map light. Unknown replacement rejected.
  Solid POM is limited to its selected palette slot. One plateau manually edited on main; its recipe
  cannot overwrite the manual result. Pointer/API, persistence, looks/physics/colours PASS; mouse OPEN.
  Canonical details/gates — World Authoring → «Ручной силуэт через Canvas» / «Уступы v0».
  Side carve (26.10): SolidSurface.uses_volume/volume_geometry/volume_mesh derive a surface-net
  boundary from edited occupancy; no Source schema/extra mode flag. Valid owned Remove keeps
  the shared material path; later Grab cannot restore a convex shell over the cavity.
  Detailed/low share positions (smooth/flat normals); voxel uses exact cells. Prop aligns the
  generated collision/floor with the canonical carved boundary across all display looks,
  preserving authored overrides; voxel display cubes do not move the physical edge. ObjectSession
  normalizes known derived collision as well as visual state; unknown replacement still rejected.
  Prefab adds VOLUME_CONTRACT only for edited volumes; unedited solid cache keys stay unchanged.
  Main plateau Source/prefab updated, Scene/Terrain/Plan/other cliffs unchanged. Native Canvas/
  persistence/3 looks/physics PASS; art/mouse and compact derived prefab storage remain OPEN.
  Canonical scope/cost — World Authoring → «Единая объёмная лепка».
  Solid union (26.10): existing Merge.plan remaps rotated guides and complete surface identity
  (palette RGB + generic role + solid role + material ID); combined solid_surface has optional
  topology=volume. Validation/UsesVolume handle it; old profiles are unchanged. Separate builds
  one valid owned volume profile from each current part. Mixed solid/plain sources are rejected.
  Prop captures the published override before derived material initialization; merge no longer
  mistakes generated look material for an authored replacement. Unknown materials stay protected.
  Native dialog/history/persistence/3 looks/physics PASS, manual input/art OPEN. Main result
  EarthCliffUnion keeps original assets. Canonical scope — World Authoring → «Склейка объёмов26.10».
  Continuous Canvas (26.10): CanvasForms/Panel route existing Merge/FragmentExtract against live
  WorldEditSessions drafts; created props use ObjectSession.open_created and non-exported
  Prop.authoring_source until ordinary transactional publication. No second document/renderer.
  Scene history retains membership/pose/data; pointer-up is one undo, movement reuses cached meshes.
  Recovery manifest carries optional canvas_layout (group/pose/created/removed originals).
  Save removes clean draft overlays; Source/prefab and three runtime looks retain existing owners.
  Fixture/native main-copy checks PASS; mouse/art acceptance OPEN. Scope/limits — World Authoring
  → «Единый процесс лепки». Working main, terrain, Plan and original assets unchanged by this slice.
  Volume Smooth (26.10): existing TOOL_SMOOTH routes object/solid sessions to VolumeSmooth's
  local immutable occupancy filter; terrain retains heightfield smoothing. Source stays discrete,
  material/part donors are categorical; optional inherited owners join the existing stroke delta.
  Workspace uses one math worker and one exact preview chunk worker, per-chunk stale revisions,
  common mesh installation; dry chunks use existing VoxMesher directly to avoid SurfaceMesher's
  mesh array readback/copy. No new renderer/schema. Undo/Cancel/reopen/discard and three looks
  remain existing owners. Scope/evidence/manual gates — World Authoring → «Объёмное сглаживание стыка».
  Volume Stamp (26.10): existing Stamp/Extract/Panel retain solid profile/parts on capture.
  Merge/Stamp share MaterialProfiles.palette_identity (RGB + palette role + solid role + material ID).
  Placement maps material slots and transformed guides; default unassigned part creates owned
  stamp parts. Interaction selects the created part; Workspace tracks part UI through history.
  Existing Fragment/WorldEditSessions remain owners; no Source schema or renderer added.
  Native real-cliff fixture/library/preview/history/save/reopen/discard/3 looks==collision PASS;
  manual input/art OPEN. Legacy pointer-line Stamp FAIL6 also reproduces on pre-slice baseline.
  Limits/evidence/current gate — World Authoring → «Объёмный штамп»; main assets unchanged.
  World scale (22 Oct): solid look = metres via AUTHORED_BLOCK_M; Prop._sync_solid_unit sets solid_local_unit_m 1.0
  and set_world_scale(material, block_world_size) rescales the world-space depth (amplitude, fade); maps draw a
  block as 16 units. landscape_compact now holds PaintedRockGroup; test_landscape_rock_placement.
  Instance pattern scale (27 Oct): Prop.material_pattern_scale, default1, belongs to .tscn, not Source/Pattern.
  bind_pattern_size sets solid_pattern_scale, solid_texture_unit_m and ember_texture_world_unit using visual
  global scale / units per metre. Local colour/height/stone face UV share this scale; physical depth/rims unchanged.
  InspectorPlugin supplies native EditorProperty; anomaly material copies rebind the same values without remesh.
  Forward+ fixture + native Inspector history/save/reopen/discard PASS; manual art/input OPEN.
  Surface-net fairing (27 Oct): Solid.volume_geometry retains dual-quad connectivity/material IDs,
  relaxes points along net edges in4 Jacobi passes (no triangle diagonals), clips to original cell
  and0.35 voxel total movement; original mesh bounds fixed. Smooth/flat/collision share positions;
  voxel display still uses Source cubes. VOLUME_CONTRACT v3-surface-paint-weights invalidates derived prefabs.
  Three main volume assets republished with external binary collisions; map/terrain/Source hashes unchanged.
  Plane RED13.65°→GREEN1.98°; cavity/history/save/discard, floor/rays/3 looks and fresh publications PASS.
  Evidence and manual gate — Terrain Authoring → loose soil.
  Volume paint blend (27 Oct): incident dual-quads vote once per shared net point; existing terrain
  _emit_blended packs three slots/weights. Original face ID remains in alpha for picking. Band spans
  adjacent voxel rows (~12.5cm at16vox/m); voxel look unchanged. No vertex/normal/physics changes.
  Three main volume meshes/prefabs republished; existing collision files reused without writes.
  Pure mask/junction/geometry checks + cavity/paint/history/save/discard + native main3 looks PASS;
  visual acceptance OPEN. Depth still uses dominant profile/ray, not blended independent height fields.
  Depth distance (27 Oct): Map.bind_material_depth_distance owns existing near/far metre policy.
  TerrainProjection, VoxelProp material recreation/unit sync and anomaly alternate copies rebind it;
  prop metres use block_world_size/AUTHORED_BLOCK_M, independently of pattern/light-cell units.
  Existing panel/history/save/reopen/discard/three looks PASS; no remesh. Manual distance art gate OPEN.
  Shared library depth (27 Oct): Solid.bind_detail/update_detail now route through existing
  SurfaceMaterials.set_terrain_depth_profiles; all painted slots retain individual Pattern height/amplitude.
  Common shader bank sampling uses EMBER_MATERIAL_BANK_DEPTH; one dominant profile/ray, other paint colours
  remain intact. Detail solids keep1024px, ground256px; immutable GPU banks share a bounded weak cache,
  numeric tables remain local. Amplitude edits do not upload images; legacy single-profile probes remain opt-out.
  POM uses plane projection with authored lighting normal, avoiding exposed internal tessellation.
  No Source/Pattern schema or physics changes. Current scope/evidence — Terrain Authoring → library section.
  Prop.set_solid_look + solid_surface.build_voxel_look: dev look switch (voxel/low poly),
  display only; test_rock_look_switch. Facet
  normals still own diffuse light and collider; test_rock_form_transfer.

- Material recipe pilot16 Oct: `ember_material_look_bake` derives image regions and
  flat grass silhouettes; `ember_material_shapes_study` binds cached variants to
  existing SurfaceMaterials/Pattern/toon/POM. `ember_material_shape_study` opt-in
  changes grass brush coordinates only, with the existing light equations.
  Height bytes remain unchanged; colour filtering protects relief and tile edges.
  No new persisted schema/editor. The LAB fixes smooth terrain geometry across
  all3 comparisons; oak shells reuse LookBake. Rules/gates in Terrain Authoring.

- Coherent look LAB16 Oct: `ember_coherent_looks_study` extends the material-only
  fixture; `ember_terrain_look_bake` projects smooth vertices onto 8-cell planar
  triangles, retaining material channels, and pixel-bakes paired colour/height.
  Voxel ground uses existing `EmberTerrainPilotMesh.build_tile`; smooth physics
  stays owned by projection. Grass x/z/seed/density are retained with prebaked
  visual y anchors. No production switch/physics policy; max facet deviation
  0.56m and unreduced material triangles are explicit gates, not accepted gameplay.

- Natural rock follow-up: `ember_natural_rock_study` keeps coherent grass and the
  smooth/voxel shells; `TerrainLook.adaptive_heights/rock_faceted` replaces rock
  facets using bounded field approximation (3.74cm measured). Fine paint topology
  remains; normals follow adaptive supporting planes. `ember_natural_rock_recipe`
  owns the new derived colour/height pair; original paving/POM/light owners stay.
  Plain/material comparison is LAB-only; art/contact/LOD not accepted. The author
  rejected the ordinary rounded foundation, so bounded approximation is not an art pass.
  `tools/capture_rock_form_rules.gd` now probes only the ordinary plain rock through
  existing Source.surface_rules / Smooth.field/build / apply_study_smooth_tile.
  Radius1 and protection75% use private documents; mesh/collision/floor move together.
  No source-file/material/grass changes. Smaller rounding cannot create absent chips.
  The author rejected `capture_rock_planes` (Source cuts + blended normals):
  still rounded terrain growths with ground paint on their sides.
  Current `tools/capture_rock_three_looks.gd` extends `capture_rock_solid.gd`:
  fixture columns -> one private EmberVoxelModelResource (six merge_parts) ->
  detailed18 supporting planes, faceted14 planes, native VoxMesher at6.25cm.
  All variants read the same occupancy. Side inclinations fit source column extents;
  primary slopes match between detailed/faceted; sharp normals, same stone shader.
  Resource validation/save-reopen/ownership/immutable Source/native return-frame/
  grass/depth/Sol hashes PASS. Evidence and saved Source: `ember-rock-three-looks/`.
  Known fixture segmentation only, convex fits approximate source concavities.
  Corresponding AABB-corner discrepancy up to26.7cm; surface error NOT established.
  Collider/floor/navigation absent: not a production converter or gameplay shell.
  `capture_rock_surface_detail.gd` now cuts two major masses in the private common
  voxel Source, explicitly authorized by the author; all three looks regenerate.
  Ordinary/faceted share recipe guide directions and remeasure plane distances
  from occupied voxel corners. This is recipe-guided convex fitting, NOT general
  feature extraction. `capture_rock_three_looks::faceted_look` adds a narrow hook;
  default remains unchanged. No production schema/renderer/generator edits.
  `test_rock_surface_detail` checks deterministic edits, permitted part changes,
  native-source parity, closed oriented edges and bounds; native guards PASS.
  Source extents change≤6.25cm; principal lean within prior2° gate. Full silhouette
  equality is not claimed. Evidence `ember-rock-source-breaks/`; author accepted
  this form as a sufficient working baseline for material work, not final B art.
  Physics/surface correspondence/anomaly transitions remain OPEN.
  Material follow-up: `capture_rock_material_looks` uses a `look_material` hook on
  the same geometry; `ember_natural_rock_recipe` owns the LAB colour/height master.
  `ember_material_look_bake::calm_variant` derives low-detail pigment; existing
  `TerrainLook.pixel_image` samples paired voxel maps. Stone-only coverage avoids
  projecting terrain paint onto object sides. Common POM/light shader unchanged.
  Evidence `ember-rock-material-looks/`; master height/Source/geometry exact;
  3 presets/back sun, POM on/off/return and focused tests PASS. Material art OPEN:
  continue with Sol, preserve geometry/depth/light/foliage. Validate detailed,
  faceted and voxel looks sequentially, then scene-wide coherence; moving sphere
  transitions follow endpoint style acceptance (Product Plan owns sequencing).
  Sol follow-up: `capture_rock_texture_refinement` retains revision0 pigment and
  compares revision1 broad drawn masses/softer fracture pigment on unchanged meshes.
  Master and all derived height images equal the prior trial; POM4cm/32 unchanged.
  36 A/B pairs and180 camera-sweep frames; context remains a fixed control scene.
  Evidence `ember-rock-texture-refinement/`; author accepted B as a working pigment
  baseline on16 October ("пока подойдет"). Full environment/production gates remain OPEN.
  Static world projection only; object-local anchoring/morph/edit overrides pending.

- Current stone paint/relief pilot17 October: NaturalRock.painted_structure builds
  a cached periodic32 warm/cool mineral guide from immutable raw artwork; r-b,
  binomial smoothing/percentile10-90/three soft levels/.25-.75, not recovered shape.
  Same2.4m span; voxel16 paired colour/height.6mm trace gives at most3mm actual span.
  Existing COLOUR_PROBE shared_height reads the POM height for baseline normals;
  fragment passes its exact fade/facing amplitude as function argument, no varying.
  Shared branch handles walls; old flag=false behaviour/PNG override retained.
  `capture_rock_paint_relief`: A previous lines/depth, B raw flat, C same B pigment
  plus shallow relief.6 tests/final Forward+ PASS:162 stills/540 camera/108 moving
  sun frames,54 exact returns/3 zero-flat cases,1 guide bake.54 prior controls have
  tiny cross-build raster differences (mean<=.0003RGB8, isolated max30); not exact.
  Source/physics/paint/other materials retained; initial failed GPU logs preserved.
  Evidence `ember-rock-paint-relief/`; user likes trial17 October, personal review
  deferred. Art/height guide/flat-vs-3mm choice/weak-PC OPEN.
  New shallow height remains LAB; raw colour transfer is described below.
  No new silhouette or universal material converter.

- Current stone pigment candidate17 October: NaturalRock.maps(size,2) loads
  `rock-painted-calm-v2.png` (built-in imagegen; provenance/prompt/SHA beside report)
  and overlays the same sparse fracture paths with quieter pigment. Default1
  and every height/mip remain unchanged. Faceted calm256/65%, voxel16/15cm.
  `capture_rock_painted_refinement` extends consolidated/accepted-road capture,
  fixes road B/soil v4/grass/oak and changes stone PNG only. Existing optional
  COLOUR_PROBE path adds colour_probe_height_slot/png: slot_optical_height reads
  the preserved old bank layer for far fine relief while albedo reads new layer.
  No new shader contour/height solver/schema; same POM/light/roughness/geometry.
  5 tests/Forward+ PASS:54 pairs/360 motion/36 exact returns,36 prior A controls,
  9 disabled-branch exact comparisons; POM and Source save/reopen guards PASS.
  Evidence `ember-rock-painted-refinement/`; art/manual movement/weak-PC OPEN.
  Raw colour transfer is complete below; overlaid fracture variant remains a LAB
  candidate. Shallow-depth pilot above stays separate.

- Stone raw painted colour production transfer17 October: cartoon_stone.tres now
  uses exact256px rock-painted-calm-v2-runtime.png copied from paint-relief B/C
  paint-0.png, tint90938f/span2.4m, periodic=true/relief=false. No fracture overlay,
  new height guide or shader change. Existing Pattern/MaterialDialog/SurfaceMaterials
  own persistence/history/atlas refresh; Source/shape/paint/physics retained.
  Ordinary material keeps zero depth. Legacy MaterialDepthStudy explicitly pins old
  PNG sampling flags when assigning its own old stone_color.png so the new main
  colour-only default cannot alter that historical POM4cm/32 study. No production
  POM activation is implied. Existing height/coverage and shader sources unchanged.
  Soil transfer harness adds overridable material/before/reference/shader/depth hooks;
  road/soil defaults retained. Stone current uses actual projection material, A rebuilds
  old Resource, LAB replay appends recipe colour through existing Materials; no
  probe shader required for zero-depth normal material. Derived65%/pixel16 remain LAB.
  Eight tests PASS;54 pairs/54 exact colour replay/54 returns/108 motion; cold six
  game frames exact. Existing POM on/off/return separately checked. Shader source
  guard plus6 exact historical POM-stand frames against preserved road transfer.
  Source is byte-identical, controls reuse compiled resource; initial independent compilation
  differed2 edge pixels/max9RGB8, not claimed exact. Personal live/weak-PC OPEN.
  Evidence ember-stone-editor-transfer/; Terrain Authoring owns conclusions.

- Consolidated material review: `tools/capture_environment_material_review.gd`
  reuses soil/grass/road/rock recipe/capture owners and scene `set_material_style`
  for the existing oak variants. Floor geometry/physics remain fixed; no new art,
  no production switch. Soil v4 colour only (depth review deferred by author),
  rock B4cm/32, grass B, road B candidate, existing faceted leaf candidate.
  Forward+108 stills/180 motion frames/36 exact returns,12 exact v4 controls,
  POM toggles, Source save/reopen and no oak remesh PASS;4 focused tests PASS.
  Evidence `ember-environment-material-review/`17 October; art/road/leaves/motion
  manual/weak-PC OPEN. Sequencing and current return point stay in NOW.

- Road refinement following consolidated review: existing SandRoad recipe adds
  painted_image/painted_variants using the immutable accepted soil v4 master.
  Same1.5m repeat, calm65% without resampling, voxel16; private Pattern base tint
  b9a47c instead of d7c08c. Original procedural functions remain replayable.
  `capture_road_painted_refinement` extends the consolidated capture; camera hook
  narrows to4 views. Same road_material owner changes only slot2 pigment/tint;
  finish/depth/light/other layers retained, existing road pixel_relief verified0.
  3 tests/Forward+ PASS:72 pairs/360 motion/48 exact returns,54 original controls
  exactly match prior review. Evidence `ember-road-painted-refinement/`17 October.
  Author accepted painted road B as working baseline17 October; acceptance JSON
  beside report. Overall coherence direction liked; rock/bark pigment polish and
  later depth refinement requested. Final style/manual movement/weak-PC OPEN;
  Subsequent main-editor colour transfer is complete as described below; no new shader.

- Road B production transfer: existing cartoon_sand.tres shares the accepted256px
  soil v4 runtime PNG, base tint b9a47c/repeat1.5m, albedo_periodic=true and
  albedo_relief_enabled=false. No new bitmap/schema/shader. Existing MaterialDialog,
  Pattern and SurfaceMaterials own history/serialization and normal projection
  atlas refresh; saved assignments retain IDs/paint without remesh. SurfaceMaterials
  duplicates get_image() before bank resize/mip generation so shared texture/cache
  images and other material means cannot be mutated by bank order. Texture mapping
  test isolates legacy periodic=false explicitly instead of assuming sand's default.
  Seven tests PASS, including road and soil editor round trips/other lookup guards.
  capture_road_editor_transfer reuses configurable soil harness:54 pairs/54 exact LAB,
  54 exact returns/108 motion frames, six exact fresh-process road frames. Historical
  isolated-soil comparison uses the existing sparse compiler-rounding bound; ordinary
  cold Save/Reopen remains strict. Frozen shader controls≤3 pixels/max2RGB8.
  Soil historical:4 frames exact,2 evening frames differ by one grass-edge pixel
  at(1,46)/1RGB8; isolated soil region exact in all6.
  New depth remains LAB; production is smooth, other look checks remain LAB.
  Evidence ember-road-editor-transfer/17 October; personal live/weak-PC gates OPEN.

- Soil optical-depth LAB: `ember_soil_depth_recipe` preserves accepted v4 colour,
  derives broad height via64px/percentile8-92/bounds0.28-0.72, paired pixel8 voxel
  height. SurfaceMaterials adds optional secondary binding to the existing POM
  shader: shared origin/steps/fade; separate height/coverage/slots/amount/sun.
  One selected profile per fragment (secondary priority), primary retained.
  Profile bit is packed into existing LOD sign to stay within varying limit;
  no second ray solver/renderer/schema. Soil4/grass3 coverage uses exact corner
  weights. `capture_soil_depth`:0/8/16mm tracing ranges,162 stills/270 motion.
  5 tests/native PASS,54 flat and90 motion controls exact against v4; zero in3
  looks and strength return exact. Actual height span about3.5/7mm. Depth art
  OPEN; colour accepted. LAB report `ember-soil-depth/`17 October. Source/physics/
  paint/light and primary depth retained; editor/weak-PC/full-world gates OPEN.

- Soil reference-guided LAB v4: author approved a trial based on Genshin's day
  road after rejecting fine v2 and camouflage v3. New imagegen asset
  `content/terrain_materials/textures/soil-painted-genshin-v4.png`; large coherent
  painted earth forms for the isometric camera. Recipe keeps revisions0/1/2,
  default3=new PNG; full-size calm65%/pixel8 retained. Capture A=v3/B=v4.
  Existing bank/slot4/colour-only shader; no shader/height/roughness/geometry/
  source/light changes, new depth deferred.3 focused/native PASS,54 pairs and
  180 motion frames;54 A stills and90 motion controls exactly match prior v3.
  V4 accepted as the working pigment baseline17 October ("вот хорошая"). Preserve
  artwork/scale/light; next depth contract not started. Motion/weak-PC/full-world
  gates OPEN. Evidence/prompt/references `ember-soil-genshin-v4/`.
  Colour transfer now uses soil_grain with exact accepted256px runtime derivative.
  Pattern optional albedo_periodic(false)/albedo_relief_enabled(true) preserve old
  defaults; soil opts into periodic colour without luminance height. SurfaceMaterials
  encodes the relief opt-out as signed png_lookup role B, existing shader uses abs(B)
  for projection and excludes negative roles from inferred height/bump. No new sampler,
  renderer or POM solver. Existing PNG dialog EDIT_FIELDS/history/save/discard own flags.
  Source palette/IDs/geometry/physics and old authored height/roughness/finish unchanged;
  normal projection atlas refresh does not remesh. Six tests/two Forward+ runs PASS:
  54 pairs/54 exact LAB matches/54 exact returns/108 motion frames, six fresh-process
  game frames exact. Native editor shown; original stone POM on/off/return retained.
  Six frozen old-shader controls have≤3 changed pixels/max2RGB8 rounding, explicitly
  bounded separately from exact B/LAB/returns. Personal live/weak-PC acceptance OPEN.
  Known dock width gate is baseline326 vs302, frozen/current equal; no widening.
  Evidence `ember-soil-editor-transfer/`; Terrain Authoring owns conclusions.


- Accepted grass ground material transfer17 October: cartoon_grass.tres uses exact
  exported256px embedded painted_light_grass artwork, tint637f50 and its existing
  grass_light profile. Current24 October material span4m, optical depth2mm/softness4/sharpness0.02;
  span drives both metre-scaled brush light and colour. Existing bank/UI allow grass depth (0 disables),
  clumps remain without POM. Lookup row3 alpha/varying spare component carries span; no new varying.
  Live preview reuses cached lookup images; discard restores span/depth, bank holds source-texture refs.
  Current native material/history/save/reopen/discard and main-map gates — Terrain Authoring, «Зелёное покрытие земли».
  Periodic colour/albedo_relief_enabled=false retained independently of bank POM; remaining
  authored channels unchanged. Pattern/MaterialDialog/SurfaceMaterials/Projection
  retain ownership, no new schema or renderer. Saved assignments update on load.
  Existing LAB clumps remain unchanged; no new runtime foliage authoring/converter.
  Last1254px source in this set is replaced256px, so derived bank shrinks1254→256;
  other source art/parameters exact, their resampling/mips not claimed pixel-exact.
  Capture reuses stone/soil harness plus editor hook, actual production material and
  existing recipe replay. Native54 pairs/54 exact replay/54 returns/108 motion;
  preview edits small lookup in place, Undo/Discard exact/no remesh; grass-only
  region responds to real shadows in all3 presets with exact returns.10 tests PASS.
  Six cold game frames exact; six historical POM-stand frames exact versus copied
  road-transfer reference, previous report preserved.
  Legacy POM on/off/return retained, shader source unchanged. Art/live/weak-PC OPEN.
  Evidence ember-grass-editor-transfer/; Terrain Authoring owns conclusions.

- Derived grass LAB: `ember_grass_look_recipe` keeps accepted Image/ArrayMesh0;
  calm16/85% +7-corner flat clumps and pixel32 +3.125cm local contour derive1/2.
  `EmberMaterialLookBake.grass_mesh` adds optional preserve_height; legacy defaults
  unchanged. Real fixture coarse tip was12.5cm; new14cm matches the original.
  `capture_grass_derived_looks` reuses the A/B pipeline with fixed road B, accepted
  rock B and unchanged9493 scatter transforms. Road slot helper options reuse the
  existing Materials formatter for grass slot3; depth/light/other slots guarded.
  54 pairs/180 sweep frames,3 tests/Forward+ PASS.18 ordinary pairs exact;6 prior
  game frames exact. Prototype triangles44/20/56 (old44/28/16). Author accepted
  grass B as a working baseline16 October. Road acceptance, weak-PC/forest and
  production integration OPEN. Evidence `ember-grass-derived-looks/`.
  Terrain Authoring owns conclusions; no new runtime Source or physical field.

- Sand road pigment LAB: `ember_sand_road_recipe` owns a periodic1.5m master;
  existing calm12/30% and pixel16 helpers derive its other presentations.
  `capture_sand_road_looks` reuses the existing rock A/B matrix. Materials formats
  the private pattern; only fixture sand slot2 and its new bank layer change.
  Existing bank layers/non-road slots/depth/light/finish are guarded unchanged.
  Source/contour/physics/grass/tree and accepted rock B remain controls;18 game
  control frames match the prior trial exactly.36 A/B pairs/180 sweep frames,
  recipe and shared bake tests PASS. Art OPEN; no production editor transfer.
  Evidence `ember-sand-road-looks/`; Terrain Authoring owns current conclusions.


- Painted tree authoring: `ember_voxel_generator`/LargeTreeProvider/BranchLayout +
  Recipe/GenerationPanel/RecipePanel remain the same owners. Five `vox_painted_*`
  Sources and existing editor Recipes expose accepted species directly in Objects.
  Optional Source schema7 `tree_surface` publishes bounded supports/settings and
  occupancy/paint reference; Recipe stays editor-only. `ember_tree_surface.gd`
  reconstructs bark/cards from Source without running the generator at runtime.
  Shared math: `ember_tree_surface_geometry`, `ember_tree_rounded_geometry`,
  `ember_tree_bark_surface`, `ember_tree_species`; old prototype inputs only extend
  these modules. No second renderer/editor/preset owner. Prefab/Store signatures
  include the shared tree render contract; live mesh copies preserve raw buffers
  to avoid re-quantizing normals/custom channels. `_surfaces` serialization property
  is covered against pinned Godot4.7. Source palette/index paint maps to wood;
  occupancy edits fall back to authored voxels. Wood collider and trunk frame agree.
  Common toon implementation lives in `ember_voxel_toon_body.gdshaderinc`; small
  base/bark/foliage/card entries select defines and remain external shader resources.
  Existing WorldLook rim master recognizes those entries. Current controls/gates/
  render delta and performance limits — Terrain Authoring → «Пять пород в основном редакторе».

  Oak colour-only LAB trial17 October: `capture_oak_bark_painted` compares accepted
  oak-v2-calm C against separate imagegen oak-v3-painted; changes only bark albedo
  on the same three wood materials. Existing branch projection3m/voxel6.25cm,
  Source/paint/all mesh arrays/leaf B/light/rim parameters unchanged.3 targeted
  tests and Forward+ PASS:54 pairs/360 camera frames/108 local exact returns/
  36 cross-look returns; Source data save/reopen exact (QA path excluded).
  Existing test_voxel_bark_pattern fails at missing GenerationPanel.controls.bark_pattern;
  test/UI owners unchanged from baseline, gate OPEN. User accepted B as working
  colour baseline17 October; shallow recesses are the separate LAB trial below.
  B colour is now the main-editor/runtime binding; depth strength remains deferred.
  Evidence/decision `ember-oak-bark-painted/manual-acceptance.json`.

  Production colour transfer17 October: Species.BARK_ART[1] uses unchanged oak-v3-painted.
  TreeSurface.render_contract adds oak-only material version to existing Prefab/Store
  signatures and Surface mesh cache. Other species contracts/Source bytes unchanged.
  ObjectSession/SceneRefresh accepts value-equivalent reloaded oak ShaderMaterials
  and only the known C→B artwork change; shader/other parameters/texture bytes,
  render priority/next pass/local flag retain the manual-edit guard (numeric Source
  roundtrip epsilon only). Existing refresh updates placed trees with Undo/Redo;
  ordinary Prefab load invalidates stale copies. No background author-map/Source writes.
  Four targeted tests/two related regressions PASS; Forward+54 pairs/54 exact returns,
  19 exact preview/runtime/reopen cases and real shadow captures. Smooth production;
  fresh runtime --bases explicitly verifies B/mips without relief, five Source-only
  reconstructions/collision/map reopen PASS; no Recipe evaluation.
  three-look derivatives stay LAB. Personal live/input/weak-PC acceptance OPEN.
  Owners/gates/evidence — Terrain Authoring → «Перенос принятой коры Б в editor/runtime».

  Bark relief LAB: `ember_painted_bark_relief_recipe` selects sparse valleys in
  four artwork-specific UV corridors, R8/mips256, content/version cache1 bake/run.
  Shared bark include owns continuous/discrete support UV and blending for pigment/
  height. Private BARK_RELIEF_STUDY binding/include reuses existing parallax solver16;
  trace0/3/6mm with height0.5−0.5mask -> inward max0/1.5/3mm. Original-coordinate LOD
  fixed before ray iterations, shared normal/fade; macro-normal rim and LIGHT_VERTEX/
  real shadows retained. No Source schema or main-editor material defaults changed.
  `capture_oak_bark_relief` + junction/technical supplements:4 tests/three Forward+ runs PASS,
  216 ordinary+54 technical stills/540 game/90 close/72 sun frames;270 local+90 cross-look
  exact returns,15 frozen-zero+15 disabled-zero exact controls. Technical view temporarily
  clips foliage with existing object-look inputs; all restored. Initial rim-zero discrepancy fixed;
  Source/paint/full mesh arrays/leaf B/material/light/physics guards PASS. Art strength/
  live motion/weak-PC/depth production transfer OPEN. User17 October sees little difference;
  preserve/defer, no strength picked. Evidence/decision `ember-oak-bark-relief/manual-review.json`;
  preserved-code + preservation-manifest keep the implementation/PNG snapshot without commit.

- `scripts/ember_voxel_model_resource.gd` — canonical palette, voxels, groups,
  water/fill и voxel schema.
- `EmberVoxelCatalog` — native-only runtime/полка: content/voxel_models .tres/.res
  и export remaps; metadata enumeration не раскрывает geometry channels.
  `EmberVoxelPrefab` source/mesh/body/grid paths больше не читают JOI JSON/VOX;
  native mesher/physics/material contract прежний. Источников 93: один необходимый
  Причалу crate_stack импортирован с exact visual/collision parity, прежние 92 и
  все authored prefabs/maps не изменены. Binary Resource/remap preview/PCK PASS.
  `EmberVoxelLegacyImporter` держит явную import inventory/source signatures;
  migration report и Store используют её отдельно от runtime catalog. Старый
  material label нормализуется в preflight тем же способом, что в importer;
  новый renderer/schema не добавляется. Explicit import Undo восстанавливает
  exact prior derived files при удалении созданного native source; native source
  restore продолжает rebuild. Queue/batch/forced interruption и shelf gates PASS.
  ObjectSession/SceneRefresh читают только native sources; открытие отсутствующего
  source возвращает понятный отказ без изменения prefab. Store.owner native-only;
  legacy eligibility существует лишь в explicit can_import_legacy API/offline tools.
  Plugin Surface opening и WorldSurfaceSelector используют map-owned Resource;
  hydration flags не включают JSON fallback. ContentMigrationReport теперь native
  inventory; Dashboard сохраняет filters/search/attention и user diagnostic export,
  убирает city batch/preflight/import controls. Shelf/ToolsDock/plugin убрали old
  import/reimport links, callbacks и confirmation; geometry/serialization owners
  прежние. run_native_editor_tests.py: save/discard/Undo/Redo/missing source/native
  rebuild/selector/report/UI PASS, four negative controls и working refusal PASS.
  Scene-refresh regression и disposable editor/import с обоими Ember plugins PASS;
  native story/voxel/PCK gates также PASS. Ручной Forward+ и полный G4/G5 OPEN.
- `addons/ember_import/ember_voxel_sculpt_model.gd` — чистая editor-модель.
- `addons/ember_import/ember_voxel_sculpt_actions.gd` — mutations и Undo.
- `scripts/ember_voxel_surface_mesher.gd` — visual mesh projection.
- `scripts/ember_voxel_surface_materials.gd` — visual materials.
- `scripts/ember_voxel_surface_physics.gd` — collision/physical surface.
- `scripts/ember_voxel_surface_projection.gd` — world sampling/height projection.
- `content/world_surfaces/<map_id>_surface.tres` — canonical world Surface.
- `scripts/prototypes/ember_terrain_pilot_resource.gd` и
  `content/world_terrains/landscape_compact.res` — первый scene-owned компактный
  грунт для отдельной копии Landscape; ручная приёмка native editor открыта.
  `EmberMapLoader.compact_terrain` исключает плотную Surface как активный грунт
  этой сцены, а `ember_terrain_pilot_projection.gd` строит вид и физику из одного
  документа. Чистый leaf `ember_terrain_sections.gd` адресует те же шесть каналов
  schema 2, проверяет ограниченную оболочку и создаёт временные окна у стыков;
  `ember_terrain_pilot_mesh.gd` хранит ground side spans в своём `Triangles`,
  объединяет только смежные одинаковые bands перед созданием ArrayMesh и
  возвращает те же faces для collision. Top/water пути и Resource прежние;
  `build_tile(..., coalesce_ground_sides=false)` оставляет старую сборку editor;
  projection включает coalescing только вне `Engine.is_editor_hint()`. Это
  runtime-derived policy, не экспортируемое поле/схема и не второй mesher.
  Sectioned brush читает каналы payload пачками, BrushMath считает группу по
  одному массиву; TerrainSections.write сохраняет copy-on-write на batch.
  Projection.apply_columns принимает необязательный written_source только для
  уже записанного собственного source: сравнивает прежний document, инвалидирует
  tile/навигацию/воду и разделяет готовые immutable payloads вместо второй записи.
  Остальные callers используют обычный write; Undo/recovery snapshots неизменны.
  `ember_terrain_ground_lod.gd` и `ember_terrain_water_lod.gd` — CPU leaves для
  derived runtime ArrayMesh indices, не второй renderer/mesher/schema. Общий
  `ember_terrain_mesh_lod.gd` владеет boundary math, статическим batch Callable и
  cancellation RefCounted без Node refs. Projection держит одну очередь обоих
  видов mesh и один Thread низкого приоритета; main thread публикует ArrayMesh
  в общем tile-бюджете и отбрасывает stale mesh по identity. Ground RAM cache
  использует tile/column revision; water не переиспользует этот ключ, поскольку
  shoreline fields могут remesh без изменения column revision. WorldCanvas ждёт
  pending_runtime_lod_count; profile разделяет ground_lod_* и water_lod_*, общий
  runtime_mesh_ready_ms/pending_runtime_lods. После подготовки Godot выбирает LOD
  без camera callback/remesh; Ground/Water.lod_bias=0.25 только runtime. Ближние
  arrays и physics точные. Ground защищает border/material-ID, water — все грани
  мелководья/depth/color/UV переходов, walls/swash/sheet, tile/1m patch borders;
  boundary и minimum-gain checks оставляют точный fallback. Water хранит один
  дальний уровень с динамическим error floor 8 source units, пределом span 1m
  patch и глубиной >1m. Editor не ставит jobs и не обращается к geometry disk cache.
  `ember_terrain_geometry_cache.gd` — runtime derived owner точных arrays/collision
  и отдельного LOD payload. Projection передаёт CPU snapshot/до 32 near requests
  в тот же worker: GeometryCache.prepare_batch считает keys, читает и проверяет
  массивы; мягкий предел 64 MiB плюс одна запись до 16 MiB. Main публикует meshes/
  physics, cold build/write остаются там. Worker также готовит LOD/trim 512 MiB.
  Следующая near пачка не начинается до освобождения результатов; persistent
  section payloads snapshot не мутируются, dense channels копируются на revision.
  Request serial защищает coalesced columns/swash/sheet; pending не исчезает до
  publication, cancel/close/resize join освобождает snapshot/results. Нельзя
  переносить этот путь в editor/brush. Thread-start fallback синхронный.
  Content key: VERSION/Godot, tile+3×3 neighbours, palette/origin, policy,
  swash/sheet. При изменении mesher/topology/LOD math повышать GeometryCache.VERSION.
  `ember_derived_data_cache.gd` — общий атомарный Zstd/checksum transport;
  object decoding выключен, arrays/index ranges и collision parity проверяются.
  Missing/stale/corrupt/I-O возвращают обычную сборку. Near/LOD разные файлы:
  промежуточный water remesh не теряет готовые индексы. Cancellation не держит
  Node refs, публикация по identity прежняя; валидные stale-input данные допустимы
  в content-addressed cache. Profile geometry_cache_* и *_lod_cache_hits/misses
  разделяют hash/read/write/LOD I-O/trim и derivation CPU. WorldCanvas barrier
  включает cache jobs, physics и publication; camera/editor brush не вызывают I/O.
  Cache read также отдаёт проверенные ground_arrays/water_arrays; cold write
  отдаёт те же CPU arrays сериализации. Projection направляет их в существующий
  MeshLOD worker вместо повторного surface_get_arrays. Packed buffers COW-shared,
  после job освобождаются, постоянного CPU array cache в tiles нет. Cache-disabled
  fallback прежний; disk schema/VERSION, LOD math, near/physics и editor не менялись.
  Profile geometry_cache_decode/validate/upload_us разделяет near read;
  runtime_lod_array_readbacks/readback_us считает только fallback извлечение для LOD.
  geometry_prepare_* считает jobs/batches/stale/max_tiles/max_bytes/failures;
  key/read timings теперь CPU worker, mesh_us — основной build/publication.
  `tools/prepare_terrain_geometry_cache.gd` — explicit headless CLI saved compact
  scene/Resource → существующие water/geometry/LOD caches. Scene вне дерева, policy
  наследуется из единственного MapLoader либо задаётся для Terrain Resource.
  Regions CPU producer готовит swash/sheet; тот же TerrainPilotMesh в dummy storage
  собирает по одному tile без GPU/physics Nodes. Base и final coastal варианты,
  exact arrays/collision и LOD keys совпадают с runtime, VERSION/schema/math прежние.
  Source не записывается, editor/F6 автоматически команду не вызывают. Финальный
  trim проверяет полноту geometry/LOD files. `--bundle=res://build/terrain-prepared`
  сохраняет только использованные geometry/LOD/water keys; Regions отдаёт ephemeral
  cache_keys, не Resource/schema. `ember_terrain_prepared_bundle.gd` владеет build
  manifest/checksums/ограниченными файлами одной compact-карты. EmberImportPlugin
  регистрирует TerrainCacheExport: валидный bundle → add_file под res://ember-prepared;
  invalid → warning/skip, обычная runtime сборка остаётся. Generated directory ignored.
  DerivedDataCache читает local, затем packaged при transport miss; owner validation
  прежняя. Geometry near/LOD и WaterCache задают packaged roots только для своих
  canonical user directories; editor_hint и custom fixtures не читают shipped data.
  Запись/trim остаются user-only, cold/semantic-invalid fallback прежний. Новая карта/
  версия/policy меняет content key, не требует manifest lookup или копирования в user.
  Native exported PCK/empty user caches/256 м barrier+walk проверены; release template
  binary, другой ПК и агрегирование нескольких карт остаются отдельными gates.
  Тот же TerrainPilotMesh имеет opt-in optimize_water_mesh: Triangles.mesh
  индексирует water arrays через SurfaceTool без перестановки triangles. Нормали,
  COLOR.a depth, UV-маркеры walls/swash/sheet и исходная геометрия сохраняются.
  Cache глубины (x,z,level) принадлежит только текущему Triangles/build_tile;
  editor не создаёт его. Projection включает runtime_water_mesh_optimization
  только вне editor_hint; section window сохраняет index buffer при переносе.
  Profile water_vertices считает сохранённые vertices, water_source_vertices —
  прежние углы triangles, water_indices — indexed draw references. Schema,
  shader, физика и camera lifecycle прежние; geometry cache принадлежит owner выше.
  Замеры и водный ручной gate — Water Rendering.
  Замеры и ручной gate —
  Terrain Authoring → «Производительность и границы доказательств».
  `tools/benchmark_compact_world_scale.gd` — отдельная заполненная 256 м fixture
  через прежний sampler/Resource, native cold/warm/controllers/occlusion A/B;
  не runtime owner. Замеры/ограничения — Terrain Authoring → «Проба заполненного
  острова 256 м». Occluders остаются диагностическими, production policy нет.
  renderer и механика остаются прежними. Необязательный `palette_surface_roles` хранит смысловую роль
  слота палитры (`soil`, `grass`, `sand`, `stone`); пустой массив старой карты
  означает неизвестную роль, не миграцию по цвету. Нативный 3D-редактор меняет
  роль всего слота одной Undo-командой, Save использует прежнюю транзакцию.
  `floor_surface_sample()` возвращает роль верхнего покрытия; смена одних ролей
  обновляет проекцию без remesh. Имя `pilot` сохраняется до принятия среза.
  Необязательный `water_flow` хранит вектор направления и относительной
  скорости на каждый блок 16×16 колонок внутри того же Resource; пустой массив
  означает стоячую воду старых карт. Вектор не создаёт жидкость в сухой колонке.
  Расширение карты переносит старые векторы и заполняет новый участок по
  выбранному режиму. Пока поле создаёт только отдельная проба реки;
  общего инструмента рисования потока в редакторе ещё нет. Пробный водный
  контроллер строит из того же compact Resource временную R32-карту высот
  соседних колонок: F6 использует её, чтобы не принимать боковые грани дна за
  погружённые объекты в экранном проходе преломления. Карта не сериализуется.
  Для пробной пены контроллер также выводит временное поле расстояния от мокрой
  колонки до сухого берега; авторская карта и её схема не меняются. Высота
  волны в пробе снижается по глубине и расстоянию до сухой границы. Береговая
  пена следует той же фазе, что и геометрия воды; F6 отдельно задаёт силу,
  ширину, резкость и ход пены, а также силу речного гребня.
  Широкая речная волна двигает mesh; короткая рябь остаётся в оптическом
  нормале, поскольку её высоту сетка с шагом 8 передаёт гранёно. Белизна
  гребня использует широкую волну и затухает у берега; толщина и чёткость её линии
  независимы от белизны. Производная RG32-карта расстояния вдоль одиночного русла
  и поперечной координаты строится чистым leaf-модулем
  `ember_compact_river_phase.gd` из существующего `water_flow`. Она интегрирует
  направление по центру потока; локальные повороты не вращают мировую фазу.
  Это визуальное поле пробной карты, не новая schema, владелец течения или
  решатель физики; разветвлённые/замкнутые потоки ещё не поддержаны. На тихих
  берегах не подмешиваются короткие морские волны. Оптическая рябь использует
  два ограниченных цикла переноса с разными фазами, следуя принципу
  [Water Flow in Portal 2](https://cdn.akamai.steamstatic.com/apps/valve/2010/siggraph2010_vlachos_waterflow.pdf).
  Шаг 4 проверен сравнительными Forward+ кадрами без заметной пользы для пробы.
  Compact projection входит в группу существующих water projections, поэтому
  `EmberWaterContact3D` использует её обычный `water_surface_sample()` для
  мокрой маски и следов. Только помеченные `static_surface_foam_footprint`
  BoxMesh и CylinderMesh на пробной карте отдают этому же компоненту
  сечение на уровне воды; контроллер передаёт до восьми аналитических контуров
  через uniforms (R8-поле остаётся производным диагностическим полем), а поверхность рисует
  контактную пену вместо плоского кругового QuadMesh. Верхнеуровневые узлы
  контакта читают именно прямого родителя, иначе R8-маска пуста. Для других карт и
  объектов остаётся прежнее отображение контакта. Контроллер пробы теперь
  `@tool`: editor и runtime используют общую подготовку полей и параметров.
  В редакторе не создаются игровые камеры, FogVolume и F6 UI; обычный экранный
  путь преломления сохраняется. Контуры объектов проверяются раз в 250 мс и
  обновляются при изменении формы/положения/флага, без пересчёта берега и течения.
  Поля земли обновляются после завершения мазка/очереди tile по revision
  существующей projection. Настройки Inspector меняют только uniforms.
  В F6 контуры обновляются вместе с объектами, без пересчёта terrain-полей.
  Герой и спутники создают одинаковый `EmberWaterContact3D`; контроллер читает
  контакты сцены, включая соседей Map. Runtime node_added/node_removed помечают кэш dirty, который
  обновляется после готовности воды: герои появляются позже неё. Hidden contacts остаются в кэше для show,
  но upload исключает их из волн и бюджета; движение не вызывает rescan/terrain rebuild. Статика opt-in.
  Следующие отдельные дуги описывают retained mode0; main mode2 использует общий
  contact field стоя/в движении — owner `ember_compact_wave_obstacles.gd` ниже.
  До 12 образцов существующей истории `EmberWaterContact3D`, с долей каждому видимому контакту, задают расходящиеся
  дуги, небольшое смещение вершин и нормали. Разнесённые образцы помечаются при
  рождении; живые дуги не меняют origin при новом input. `reaction_birth_seconds`
  плавно наращивает height/foam. Речной фронт выпуклый по flow; процедурная
  фактура привязана к номеру фронта и влияет только на пену.
  История не сериализуется; flat wake
  скрыт только у интегрированных контактов. Остальные карты сохраняют прежний путь.
  «Вид мира → Вода» маршрутизирует существующие scene exports через тот же
  EditorUndoRedoManager; `WATER_VALUES` — общая UI-таблица editor/F6, не schema.
  `ember_water_preview_debugger.gd` зарегистрирован существующим editor plugin:
  транспорт F6 передаёт allowlisted snapshot панели того же scene/node path.
  Панель валидирует весь набор до применения и пишет одну history action
  через свойства существующего owner; UI refresh не попадает в remote history.
  Ctrl+S остаётся владельцем дискового сохранения. Камеры/позиции не импортируются.
  `EmberLights.SUN_LOOK_VALUES` хранит только UI metadata и преобразование двух
  углов в rotation существующего Sun. Панель/F6 используют один allowlist, общий
  water+sun перенос атомарен и проходит одну history action. `Sun`/`.tscn` остаются
  владельцами света; controller обновляет caustic/ray direction при его повороте.
  `ember_compact_ripple_field.gd` — производная общая периодическая 128×128 RGBAH
  основа ячеистой ряби, создаётся один раз; trial shader деформирует её в fragment
  без изменения mesh/physics. Три новых scene exports входят в прежний WATER_VALUES.
  Roughness/specular общие для реки/моря; flow меняет перенос ряби, не включает отдельный материал у устья.
  `study_coastal_slope` читает градиент билинейной высоты покрытых sea cells:
  missing river guard/край поля не дают ложную высоту 0 в оптическом нормале.
  `test_compact_water_sun.gd` проверяет настоящий GPU fragment и sparse-field край.
  Shader также добавляет временную
  сетку пены после речного фронта и общий bounded width pulse кромок берега/объектов;
  значения живут в прежних scene exports (`foam_width_pulse` включён в общий UI/snapshot).
  Корень shoreline band закреплён на мокрой границе distance field; ширина,
  wave arrival и width pulse изменяют внешний край, не смещают всю полосу от берега.
  `water_level_offset_voxels` сохраняется тем же scene controller (UI/F6 snapshot).
  `EmberTerrainPilotProjection.set_water_surface_offset` — производный путь одного
  сдвига в water material и `water_surface_sample`; water revision обновляет контакты,
  column revision/terrain levels не меняются. Trial shader сдвигает верх/обод боковин,
  оставляет их дно; контроллер обновляет reflection/underwater/light plane.
  Это общий сдвиг моря/реки −0,75…0; авторская мокрая маска сохраняется.
  `ember_compact_water_regions.gd` — transient helper прежнего water controller:
  неизменный terrain snapshot → один CPU worker → общий граф связности моря →
  поля созданных участков с halo → постепенная main-thread загрузка/материалы →
  существующая projection mesh-очередь → готовая общая версия shader/query.
  Runtime больших карт29.10: global sea/lake topology остаётся точной, dry/uniform
  summaries компактны; dense fields spatial requested вокруг bootstrap/camera/actor/party.
  Initial required48м, prepare по existing detail_end(default100м), retention8м, batch2.
  Поля commit по batch, startup ждёт published required_ready(), дальние текстуры получают
  существующий shader fallback. Small/editor meaningful wet/shore eager path сохранён.
  Motion/departure/stale revisions отменяют batch; arrival/release под активными contacts
  инвалидируют obstacle signature. Global flow/phase сохраняются, Source не densify.
  PlanarReflection guard берёт общий Sections24×384/576м; старый22 cap был runtime blocker.
  Water-owner dry576ready2,134с/0fields, wet3requiredready3,320с; полный native gate отдельно.
  Cache key учитывает persistent payloads соседей, ocean flags и высотный origin;
  отмена новых revisions/Undo и close не публикуют устаревший результат.
  Projection stage/commit держит региональные material overrides и пересобирает
  только изменённые dry-bank/spill tiles; ground light/atlas продолжают прежний owner.
  Flow/phase общие на 1 м, dense window ограничен регионом, авторские данные не
  сериализуются повторным форматом. Поля/texture duplication готовятся до commit.
  `ember_compact_water_cache.gd` — disposable storage этого же регионального пути:
  content/version/mask key → records/shore/height bytes → SeaSwash.restore_static →
  прежний upload/commit. `user://ember-water-region-cache`, Zstd/checksum/size cap,
  temp rename, 256 MiB quota; missing/corrupt/I-O — fallback build. Binary transport
  вынесен в DerivedDataCache, прежние `.ewc`/header/API совместимы. Живая история
  не пишется на диск; source Resources, физика и renderer прежние. При изменении
  статической береговой математики повышать Cache.VERSION. Диагностика регионов
  разделяет disk hits/I-O, components, coast build, restore и общий worker.
  Regions также сохраняет local labels/groups/spills: отдельный COMPONENT_VERSION,
  section address/content-neighbours key, bounded payload validation. Глобальный
  ocean graph остаётся свежим; RAM identity и coast keys не заменены. Статистика
  component_disk_hits/component_builds отделяет восстановление от flood fill.
  `tools/prepare_compact_water_cache.gd` вызывает тот же CPU worker для сохранённой
  карты/Terrain вне tree: только user derived cache, без GPU/геометрии/source writes.
  Это явная локальная подготовка, не shipping bake или новый editor job.
  Ограничения, замеры и gates — Water Rendering → «Действующий путь пробы».
  Runtime старт пробных World Canvas продолжает `world_canvas.gd`: экран ждёт
  native projection/physics и `startup_preparation_status()` controller, затем
  создаёт героев, вызывает `initialize_startup_camera()` и открывает управление.
  Фоновые jobs не останавливаются; в 3D экран отсутствует. Ни новый глобальный
  loader, ни смена логики общего `ember_explore_scene.gd` этим срезом не введены.
  Дистанции водной microdetail принадлежат тому же controller (`water_detail_begin_m`,
  `water_detail_end_m`) и общей WATER_VALUES: panel/Undo/F6 snapshot → common
  региональные uniforms → camera-distance branch прежнего shader. Mesh, query,
  clock и GPU-история не переключаются с расстоянием; детали/gates — Water Rendering.
  `ember_compact_sea_swash.gd` — owner производного морского поля и общего профиля:
  открытый wet edge, shore distances, высота/покрытие/пена/остаточная влажность.
  Flow guard оставляет реке прежний путь. `set_sea_swash` возобновляет очередь
  затронутых тайлов и добавляет временные dry-bank клетки в существующий Water
  mesh через прежний MeshBuilder; animation не делает remesh. Общий shader include
  даёт Water и compact ground одни текстуры. `ember_compact_sea_swash_gpu.gd`
  использует главный Forward+ RenderingDevice и Texture2DRD; compute GLSL
  обновляет историю по единожды загруженным shore records и малой таблице
  прежнего профиля. Нет полного CPU-обхода/texture upload или readback каждый шаг.
  Dry-bank query считает текущую точку/билинейную высоту общей математикой;
  исторический query ограничен по клеткам/времени, headless остаётся CPU reference.
  Детальный берег: foam carrier RGBAF/R32G32B32A32_SFLOAT (R=age,
  G=unclamped surface,B=crest profile,A=grain). State RGBA/legacy sampling сохранены. Projection выводит
  `sea_smooth_shore` только для detailed/ground_style1; shader пересекает волну с
  реальным opaque depth, общий край с AA0.02ед./pixel footprint. Фронт пены читает
  continuous depth/BA отдельно от прежних web/pattern/age; старые width/sharpness
  controls связаны с ним. Общий face gate для трёх обликов читает inland normal
  из signed coast distance и наклон unclamped G через `study_sea_surface_slope`.
  Это убирает постоянный shallow-edge до волны и вторую кромку на тыльном мелководье;
  crest/grain/web/age прежние, legacy coverage/клеточные координаты сохранены.
  «Живая поверхность»: `wave_state` имеет out crest_phase и прежнюю wrapper API;
  математика волны не изменена. Fragment переиспользует фазу/высоту для редких
  плавно затухающих клочков прежней `study_foam_trail_pattern` в открытом море;
  coastal/river/depth/distance masks защищают прежние пути. Controller exports
  `sea_crest_foam_strength`/`sea_crest_foam_amount` входят в WATER_VALUES и общий
  uniform broadcast, panel/F6 snapshot/Undo/save без отдельного owner/schema.
  Новый слой default0; main preset и gates — Water Rendering → «Живая поверхность».
  Дополнительных CPU/history/readback/geometry jobs нет.
  «Пена по волне»: `study_sea_crest_foam` растёт до пика, decay после; seed скрыт
  во впадине. Live `study_object_foam` берёт R/G/B/A общего obstacle field для
  клочков отклика, distance только ограничивает область; legacy band сохранён.
  Контроллер/schema/settings/берег прежние. GPU/native main PASS, ручная приёмка OPEN —
  Water Rendering → «Ориентир для пены».
  Цвет/оптика принадлежат тому же controller: export colors `shallow_color`/
  `deep_color` (WATER_COLORS), числовые `water_color_start_m`/`water_color_end_m`/
  `water_color_softness`/`water_density`/`water_transparency` (WATER_VALUES).
  Старые shader deep_start/end получают метры с учётом Map.imported_tile_size;
  единый fragment helper управляет gradient/transmission, сохраняя прежние defaults,
  foam/shape/physics. ColorPicker и numeric history используют существующую панель;
  F6 allowlist проверяет оба типа атомарно и не принимает перевёрнутый диапазон.
  Scene/Source не переписаны. Доказательства/ограничения — Water Rendering → «Цвет и прозрачность».
  Тонкое преломление едино через raw wet/dry границу,
  normal — центрированные наклоны. Mesher готовит шаг1 у swash bounds.grow(8),
  дальний шаг8 прежний; geometry cache salt shore-grid-1 только для swash-тайлов.
  Surface query(true)
  сравнивает ту же волну с `_smooth_height`; low poly/voxel — прежний путь.
  Новых Source/Map полей и динамического remesh нет; gates — Water Rendering
  → «Берег детального мира». GLSL/image format менять вместе, импорт обновлять
  в отдельном cache; старый imported shader с новым carrier даёт неверные каналы.
  Ground shader показывает тот же локальный высыхающий след. GPU handles
  освобождаются при замене/удалении owner, frozen preview не повторяет dispatch.
  Runtime activity продолжает того же Regions owner: core distance до камеры
  или Player 48 м, hysteresis 8 м; near GPU 20 Гц, far interior 5 Гц, обе стороны
  seam-полосы 8 cells — 20 Гц. Swash хранит отдельный last-full GPU clock;
  GPU bridge использует один shader и дополнительный compact border uniform set,
  counters full/border/processed_records. CPU-query clock остаётся 20 Гц;
  query promote публикует текущее поле без повторного шага истории и держит core
  2 с. Settings/reset/frozen/no-observers — full fallback. Editor policy/border
  buffers исключены; cache key, terrain Resource, geometry и physics owners прежние.
  Полное sleep/streaming не введены. Замеры и ограничения — Water Rendering
  → «Runtime-частота морского набега».
  Water shader переиспользует base wave height/crest phase и пропускает только
  нулевые optional/uniform вклады; derivative-dependent foam web сохраняется.
  Controller/Regions передают только изменённые параметры. Regional snapshots
  независимы, packed arrays копируются, bind/commit сбрасывает broadcast cache;
  новые materials и aging wakes получают актуальные значения. Это transient
  transport, не Resource schema/cache эффектов. Замеры/ограничения — Water
  Rendering → «Стоимость рисования поверхности и передача параметров».
  Десять sea/sand exports принадлежат тому же controller/UI/F6 snapshot; авторские
  terrain каналы, коллизия земли и column revision этим путём не меняются.
  Тот же sea leaf хранит RF age texture пены после входящего фронта; shader
  переиспользует `study_foam_trail_pattern` для реки и моря. Морские foam strength/
  trail strength/lifetime независимы от речных, включая coastal obstacle patches.
  Approach distance/strength задают единый профиль рождения/набега/отката и входят
  в settings signature cache обтекания; GPU/query смешивают внешнюю зону 15…24.
  Формат state/age textures прежний, поля теперь региональные; sea time/period uniforms производны от
  прежнего controller. Сетка не создаёт геометрию и не рисуется на осушенном песке.
  Derived поле, foam age и runtime wetness не сериализуются. Weather/общие реакции материалов
  остаются отдельным срезом; ограничения и замер поля — в документе воды.
  `ember_compact_waterfall.gd` — чистый производный leaf одного осевого перелива
  из прежних water levels/flow. Sheet batches входят в существующий Water mesh
  через `MeshBuilder.build_tile`; UV.x < −3 отделяет их от поверхности/стенок/
  dry-bank плёнки. Они добавляются после stitching; статическая стенка выбранного
  перелива подавлена. Ground collision/source не меняются. `set_waterfall` обновляет
  только затронутые тайлы; RGBAF impact поле анимируется 20 Гц без remesh, lower-wet
  query читает тот же билинейный подъём. Общий shader/include использует прежний
  пенный web. Четыре exports/World Look/F6 snapshot принадлежат тому же controller;
  поля не сохраняются. Отдельный fixture Resource/scene — compact_waterfall_study;
  falling fragment не композитит opaque screen colour; верхний approach ограничен
  spill width/верхней высотой/32 вокселями и использует тот же thread pattern/phase
  с уменьшающимся к уступу градиентом. Это оптический shader путь, без новых данных
  или изменения collision/query. Shader speed/strength относятся к подходу и струе;
  ограничения нескольких уровней и ручной gate — в документе воды.
  Водопад не создаёт новую историю контакта или terrain schema.
  `ember_compact_wave_obstacles.gd` — один производный leaf локального линейного
  wave-equation отклика контактов. Box/Cylinder дают сечение; ArrayMesh — производный
  SDF64² от `ember_water_mesh_section.gd`, остальные типы — прежний radius.
  Один срез использует CPU distance и прежний shader contact distance atlas8 slots;
  горизонтальное движение/yaw без rebuild, cache32 уровней/инвалидация Mesh.changed.
  `water_interaction_shape` одного EmberWaterContact3D
  передаёт контур/скорость/id для props и актёров. Непроницаемые границы,
  CFL substeps и поглощающий край; четыре ограниченных поля, общий solver для
  live и baked playback. RGBAF atlas хранит периодический отклик/высоту/возраст
  пены/маску; version3 кодирует total height/age по wet mask, чтение нормализовано
  у solid boundary. SHA-256 учитывает байты сечения, не process-local Image id.
  Кэш в user:// не заменяет авторский Resource и пока не
  включён в export. Во время подготовки работа разбита на кадры. Shader include
  `ember_compact_wave_obstacles.gdshaderinc` читает поле для высоты/нормали/пены;
  `set_wave_obstacles` добавляет ту же поправку к query без remesh/revision колонок.
  Средняя форма земли, dry-bank coverage и wet-sand state этим solver не меняются.
  Sea leaf отдаёт incident height через ту же `wave_profile`, что использует
  advance; морской shader/CPU отклик синхронизирован с clock морского поля.
  Речной incident описывает главный периодический фронт; мелкая фазовая вариация
  и дополнительные открытые морские волны не решаются этим ограниченным leaf.
  Mode/strength принадлежат прежнему scene controller и World Look/F6 snapshot;
  OptionButton обслуживает enum, snapshot отвергает дробный выбор. Main mode2:
  WorkerThreadPool строит incident tables по приватным working_copy/coast snapshots;
  live стартует без пятициклового bake/cache write. Малый оператор/маска обновляются
  с20Гц, поле/история сохраняются при ходе/остановке; motion forcing и incoming
  проходят одну equation. Layout по габаритам контактов сохраняет sponge margin;
  при дальнем ходе pending patch наследует перекрытие world-space state. Id allocation
  и прежний MAX_PATCHES не позволяют бесконечно запрашивать пятую область.
  Static cache hash исключает runtime id/velocity. Частота/цена/gates — Water Rendering
  → «Единое взаимодействие объектов с водой». Controller больше не отключает поле
  при движении. Live не накладывает старые analytic arcs; contact foam зависит от
  field, `object_wave_interaction` — производный uniform, не authored schema.
  EmberVoxelProp синхронизирует прежние water flag/radius и в editor/runtime;
  derived contact без owner не сериализуется. Исходный prefab/Source не изменены.
  Отдельная сцена сравнения — compact_wave_obstacle_study; приёмка/цена в теме воды.
  Визуальные границы и ручная приёмка — `EMBER_WATER_RENDERING.md`.
  В 3D-редакторе, где пробная камера дна не работает, шейдер читает непреломлённый
  экранный пиксель под водой. Стоимость дополнительной карты на телефоне пока
  не измерена.
- `content/combat/surfaces/*.tres` — visual Surface боевого поля.
- `addons/ember_import/ember_world_editor.gd` — маршрутизация нативного 3D UI
  и input, не второй voxel editor.
- `addons/ember_import/ember_voxel_preview_renderer.gd` — единственный renderer
  карточек библиотеки. Готовые 128px изображения сохраняются как производный
  локальный кэш в `user://ember_voxel_previews`; ключ включает версию renderer,
  ID, источник, время изменения и размер файла. Изменённый/новый объект и
  повреждённый кэш требуют только своей новой миниатюры. `ember_editor_preparation.gd`
  показывает окно после проверки каталога лишь при незакрытой очереди миниатюр;
  готовность открытых сцен проверяется отдельно. Исходные модели и prefab не
  переписываются этим кэшем.
- `addons/ember_import/ember_world_brush_parameters.gd` — editor-only каталог
  общих параметров и наборов для кистей. `ember_world_editor.gd` создаёт из
  описаний одни общие controls и показывает их по выбранному инструменту;
  значения передаются существующему владельцу мазка. Каталог не сохраняется
  в карту и не является второй системой кистей.
- `addons/ember_import/ember_compact_terrain_brush.gd` — единый проход
  компактных кистей по профилю сетки 2×2/8×8/16×16 на блок, шагу высоты 4/8/1 воксель
  и форме следа; чистая математика
  профиля и высоты в `scripts/prototypes/ember_terrain_pilot_brush_math.gd`.
  Эти editor-only настройки не меняют terrain Resource и не создают второго
  owner высоты, цвета или воды. Для Undo крупного мазка кисть копирует длинные
  смежные отрезки PackedArray после сортировки индексов, а фрагментированные
  изменения собирает в заранее выделенные массивы. Штатный Undo owner и
  поячеечная точность остаются прежними; `test_compact_undo_snapshot.gd`
  воспроизводит снимок ~1 млн колонок и проверяет Undo/Redo.
  Для schema 2 baseline/Undo держат неизменные версии только затронутых
  payloads; live stamp копирует эти участки, включая корректную толщину cap.
  Cancel/Undo восстанавливают все каналы участка, а не только его высоту.
  Для schema 1 `cap_depths` также входят в baseline, компактные history-снимки и Cancel.
  При понижении Resource/brush ограничивают cap высотой; исходная меньшая толщина сохраняется.
  Dense projection принимает точные caps уже записанного `written_source`, включая Undo и изменение
  только глубины; без записанного Source ограничивает собственный cap. Schema и owner сохранения прежние.
- Main3×3(25.10): Source1152²/9 full24m sections; original48×25m and world poses retained.
  section_selection.complete/completed_section + generation finish partial payloads, skip retained columns,
  blend against actual old extents. Map explicit smooth budget1572864, default262144 unchanged;
  upper opt-in2097152, brush shape_* uses the same Map budget.
  Plan v12 `coast`: directed editable shoreline, sea to its right; existing composition/provenance,
  channels/render and native plan/generation panels. No parallel sea schema/renderer.
  Geometry is terrain Source; line/level/depth/shore parameters belong to scene Map metadata.
  Old profiles join without a second submerged ridge; generation areas exclude retained old data.
  Brush part history includes changed indices; projection.apply_columns(...,restore_payload=true)
  restores exact caps/base/side and queues footprint+halo. Same-size section reopen diffs64-cell
  windows before queueing, avoiding whole24m remesh on small Discard. Large editor prep remains open.
  Full3×3 anomaly preparation timed out at241s (137 bindings at226s); movement after full
  preparation was not tested. Existing all-tile carrier/target preparation is the next perf risk,
  not an accepted scalable result. Ordinary editor pauses it as before.
  Details/manual gates — World Authoring → «Приоритет25.10 · карта3×3».
- `scripts/ember_terrain_plan_resource.gd` — scene-owned authoring plan v1–v12,
  metadata Map `_ember_terrain_plan`, Rect2i в метрах + name/id/generator parameters.
  Shoreline editor25.10: same Plan v12 persists as a compressed scene/Map-owned `.res`;
  `.tscn` keeps its reference. WorldEditSessions publishes Plan and Source in the same
  transaction, checks external file hashes, rolls back failed native saves, and gives Save As
  an independent Plan path. Legacy inline Plan still reads; no second data schema.
  Grove recovery snapshots preserve native prefab instance boundaries and authored additions,
  excluding ownerless runtime children and inherited derived mesh/material overrides. Legacy
  flattened snapshots still restore. This prevents458MB main snapshots and a native Save wait.
  Public WorldEditor.forward_input routes plan gestures before its nonmodal recipe guard;
  prior direct `_forward_plan_map` tests missed this integration defect. Plugin entry is covered.
  WorldEditor owns temporary point dragging; release commits one existing history action,
  Esc cancels the ghost. Terrain changes only through existing Composition Preview/Apply.
  ExtensionPreview follows current world_look (voxel / faceted low poly / detailed) even
  while open; it restores hidden source tiles on Cancel. Layout and settings stay in the
  existing plan/generation panels. Manual input and large preparation performance remain open.
  `ember_terrain_plan_dialog.gd` (VBoxContainer) и WorldEditor используют прежнее
  3D-выделение и существующий dock `Ember · Мир`;
  WorldEditSessions держит baseline/dirty/Save/Discard/recovery и не публикует
  terrain при metadata-only Save. `ember_terrain_cache_export.gd` удаляет plan
  metadata из export scene, сохраняя исходную `.tscn`. Генерация по плану —
  прежний exact candidate/Undo; изменение плана инвалидирует preview.
  v1/missing-version области остаются областями полного генератора; v2 хранит
  plateau kind, enabled и локальные before/after/protected patches. v3 добавляет
  lake kind с water_m/depth_m/shore_m, before tops/bases/waters/colors/side paint
  и ожидаемое течение по игровым блокам. v2 patches читаются без миграции на open;
  явный edit/Apply обновляет private copy. v4 добавляет river kind, points_m,
  width/depth/shore/flow и before_flows; upgrade v3 сохраняет original lake channels.
  v5 добавляет mountain kind, height_m/summit_m/slope_m без новых patch channels;
  upgrade v4 сохраняет original before_flows. Гора использует общий radial
  smoothstep по эллипсу, абсолютную отметку вершины и raise-only height blend.
  Ширина вершины + два склона не больше меньшей стороны bounds; input сухой,
  покрытие/вода/flow не пишутся. Исходные более высокие колонки сохраняются.
  v6 добавляет road kind, points_m/width_m/edge_m/grade_percent без новых patches.
  v7 добавляет grove kind и object_layers (member ID/slot, expected pose/parent/
  name/content signature, protection/tombstones), читает v1–v6 без миграции на open.
  v8 добавляет placement kind/clearance_m и общий набор native model_ids;
  v1–v7 не мигрируют при чтении, selected grove обновляется явным edit/Apply.
  Единственный `ember_grove_planner.gd` расширен на обычные native props без
  обязательного recipe; каталог — прежний `EmberVoxelCatalog`, visual entries —
  `EmberVoxelVisuals`, UI фильтрует ready/native. Base voxel bounds/transform circle — pure
  `ember_voxel_placement_math.gd`; private job spatial grid 4 м учитывает старые
  и новые props. Метаданные/снимки/IDs прежние; API/filename grove оставлены для
  совместимости, второй planner не добавлен. Legacy grove seed/math сохранены.
  `ember_grove_planner.gd` владеет editor-only placement/provenance; math —
  прежний leaf `ember_terrain_plan_math.gd`. Используются сохранённые large_tree
  recipes/native prefabs и `EmberSceneAuthoring.make_model_instance`, обычные
  scene props с общей геометрией/физикой. `ember_grove_preview.gd` — derived view;
  WorldEditor использует общий generation-context/dock/host, одну Undo-команду.
  Sessions держит member snapshot/Discard/recovery и saved pose baseline;
  export customizer убирает plan/member/group metadata, не props. Terrain channels
  и runtime generation не добавлены. Лимиты и OPEN gates — World Authoring / роща.
  Старые схемы не мигрируют на open; upgrade v4/v5 сохраняет original flow.
  Curve2D/samples — private derived cache, не новый scene owner. translated
  переносит точки/границы и before/expected flow keys. Lake не пишет flow;
  river берёт уровни через общий восстановленный источник + предыдущие влияния,
  вырезает русло и пишет касательный поток в существующий water_flow.
  Ручные изменения колонки защищают и её общий block-flow. Финализация flow
  идёт один раз на плитку; равномерный нулевой поток нормализуется в empty array.
  Math —
  `ember_terrain_plan_math.gd`, job — `ember_terrain_plan_composition.gd`.
  WorldEditor атомарно применяет candidate + provenance через прежние sessions;
  generation-context composition объединяет plateau/lake/river/mountain/road, UI fields остаются
  в прежнем dock/host. Job пишет те же terrain channels, legacy Terrain schema 2
  не меняется. Лимит retained следа — прежние 256 плиток 4×4 м; river job
  берёт swept corridor вместо полного bbox, endpoint preparation также бюджетирована.
  WorldEditor маршрутизирует click/Enter/Backspace/Esc и перенамечивание пути
  через общий host; compose без selected id сохраняет прежний выбор области.
  `_path_points/_path_hover/_path_draw_cache`, `_forward_plan_path` и
  `_finish_plan_path` — один transient input/overlay для river/road. Чистые
  path_curve/error/sample/bounds принадлежат прежнему Math; river compatibility
  entrypoints делегируют туда. Road job бюджетированно проецирует предыдущие
  влияния на baseline, выводит end ground levels/grade, пишет blended height,
  soil top в core и сбрасывает side overrides в своём следе. Water/flow не пишутся.
  Wet/no-ground path, grade above limit, hidden-water undercut и missing soil
  отклоняются; точные source/expected каналы остаются в прежнем local patch.
  `ember_compact_map_extension_preview.gd.show_area(..., prepare_water)` для
  локальной композиции в нынешнем study shader создаёт частные WaterRegions
  exact candidate, материал каждой региональной плитки и cancellable worker.
  Shader/mesher/cache владельцы прежние; этот job запускается только по Preview,
  источнику/сессии и runtime план не передаётся. Step budget полей/mesh — 3/4 мс;
  большие shader-пробы и несколько уровней planar/underwater требуют своих gates.
  TerrainResource/Sections.validation_errors optional local_sections проверяет
  payload затронутых участков, все headers остаются проверяемыми; default без
  subset сохраняет полную проверку. Limits/гейты — World Layout / Terrain Authoring.
- `scripts/prototypes/ember_terrain_generation_math.gd` — чистый deterministic
  sampler острова/холмов/ridged/приближения эрозии, игровой суши (`plains`) и
  прежнего creation coast. Plains использует jittered опорные участки, постоянную
  внутреннюю высоту и smoothstep по ближайшей грани Voronoi; минимум соседних
  биссектрис сохраняет непрерывность при смене конкурирующих опор внутри ячейки.
  `_sites` — производный кэш текущего sampler/job, не второй owner или runtime cache.
  Опциональные flat_fraction/flat_size_m/micro_m/flat_transition_m принадлежат
  словарю параметров scene-owned области; PLAINS_DEFAULTS добавляются только
  новому профилю, старый DEFAULTS/индексы/высоты сохранены. На экспортируемую
  физическую землю рецепт не влияет после Apply; gameplay не запускает generator.
  `addons/ember_import/ember_compact_terrain_generation.gd` — bounded job до
  96×96 м, неизменный вход, private sectioned candidate, группы 8×8/шаг высоты 4,
  плавный край с прежней землёй; cancel не пишет source. Лимит высот увеличивает
  только metadata headers; неизменная геометрия не перестраивается из-за ceiling.
  Для plains ceiling учитывает micro_m, а сухие площадки получают прежнюю траву.
  Полная генерация заменяет выбранные каналы; защита ручных правок остаётся
  owner локальной композиции плато. Resource/plan version не изменены.
  `ember_compact_terrain_generation_dialog.gd` (VBoxContainer) маршрутизирует
  параметры и явный preview в том же dock; четыре plains controls видны только
  этому профилю, скрыты в plateau. Pinned Apply/cancel принадлежат UI,
  закрывает их только WorldEditor после успеха; `ember_world_editor.gd` использует прежний edit_region и sessions,
  проверяет stale version и применяет exact candidate одной Undo-командой.
  «+ Участок» запускает в том же WorldEditor signed 3D selection по 24 м;
  `ember_compact_section_selection.gd` — pure address/budget/rebase leaf.
  Generation.begin(..., true) готовит только отсутствующие участки, общий sampler
  и переход с новых колонок к retained boundary. Новая область — до 96×96 м.
  Сдвиг адресов компенсируется Map.position и обратным сдвигом групп: global
  земля/объекты остаются на месте. History/recovery принадлежат прежним sessions.
  Уточнение25.10: rebase сохраняет фактические частичные края (384×400 →768×400),
  layout включает WorldAnomaly в history/save/recovery. Generation переводит мировые
  метры в локальные высоты с вычетом origin_y; mainland не строит островной обрыв/
  песчаный кант. Optional land_shape=island/mainland живёт в прежнем Recipe/Math,
  mainland использует существующую версию плана11, старые островные recipes прежние.
  Map main использует прежний compact_smooth_study_column_limit=524288; поле должно
  загружаться до compact_terrain/compact_ground_style. UI shape cap читает Map limit.
  Terrain mesh._add_side разрешает section/local index для cap/base/top/overrides;
  anomaly carrier cache version2 инвалидирует неполные старые carriers. Wave field
  инициализирует отсутствующий patch.time из clock при повторной подготовке.
  Карта/рецепт/ограничения и открытая приёмка — World Authoring → «Западная поляна».
  Опушка25.10 использует прежний GrovePlanner/placement, четыре области/7 props.
  Проверка детального бюджета в begin читает Map.smooth_column_limit(), не MAX_COLUMNS.
  DetailBrush._index_patches строит transient spatial lookup по актуальному map/parent frame
  на отпечаток, разделяя kind/flower Source/library variant/mixed. Имена после signed rebase
  не являются адресом: старые плитки доступны paint/erase на прежней мировой позиции.
  Новая схема/renderer/сохранённый индекс не добавлены; owners/evidence — World Authoring → «Прибрежная опушка».
  `ember_compact_map_extension_preview.gd.show_area` — прежний mesher/materials,
  без collision/serialization; временные Map/group transforms восстанавливаются
  до native Save и до snapshot toolbar Save. Сохранение — прежняя `.tscn` + terrain
  `.res`, без recipe в gameplay Resource и без генерации при F6.
  `EmberMapLoader.safe_spawn_world` разрешает высоту входа по прежней физической
  поверхности при подъёме земли, сохраняя авторский маркер. FanTown применяет
  её также к сохранённой позиции; намеренно поднятый старт не опускается.
- `ember_compact_map_dialog.gd` — VBoxContainer с подготовленным Creation source,
  pinned preview/Create/Cancel. `plugin.gd` размещает его в прежнем `Ember · Мир`;
  WorldEditor держит transient creation-page mode, блокирует authoring input и
  возвращает прежнюю страницу. Dock доступен без active editing/Map. Plugin
  временно скрывает и возвращает исходную видимость остальных 3D toolbars;
  Cancel/смена сцены освобождают candidate, не пишут старую карту. API Create —
  прежний `EmberCompactMapCreation`, существующие files защищены до и при commit.
- `addons/ember_import/ember_compact_map_creation.gd` и
  `ember_compact_map_extension.gd` — создание плоской карты по участкам
  24×24 блока и обратимое добавление к части края/всему краю/свободному адресу
  существующего compact Resource. Новый файл сразу sectioned; legacy переводится
  в черновике при адресном добавлении, записывается только по явному Save.
  Режим расширения выбирается между ровным участком с переходом в 2 блока
  от точной соседней границы и прежним продолжением края. Временный
  `ember_compact_map_extension_preview.gd` показывает выбранный результат
  только на новом участке и примыкающих tile через тот же terrain mesher;
  он не сохраняется в карту. Текущие каналы жидкости хранят только воду;
  добавление других типов потребует отдельного решения о схеме данных.
  Scene `Map.authored_size_blocks` и стандартные группы содержимого меняются
  вместе с черновиком через `ember_world_editor.gd`; публикация остаётся у
  `ember_world_edit_sessions.gd`. Новый формат земли не вводится. Текущий
  тестовый предел — 4 участка на ось при создании, 5 после расширения.
  `ember_terrain_pilot_projection.gd` пропускает повторное открытие идентичных
  данных и при расширении переиспользует внутренние tile/коллизию; очередь
  содержит новую полосу и стык. При несовпадении размеров или источника
  редактор использует полную перестройку.
  Для интерактивной правки очередь использует флаг присутствия каждого tile и
  сортируется перед очередным кадром; повторные отпечатки не множат задание.
  В native editor для dense smooth ground `SmoothSurface.build` сохраняет CPU layout:
  материальные каналы и явные роли верхних/нижних вершин. `layout_key` включает покраску,
  основу, занятость, размеры и origin; высотные правки повторно не считают материалы.
  `HeightUpdateJob` считает field/позиции/нормали на immutable working_copy через
  WorkerThreadPool; одновременно максимум 2 задачи. Внутри того же live stroke новая
  высотная правка не отменяет выполняемый шаг: epoch и неизменный layout разрешают
  его промежуточный показ; более новый request остаётся pending до своего обновления.
  Приоритет — центр кисти. За границами мазка serial проверяется строго; Cancel/Undo
  не разрешают публикацию старого шага, reset/open/resize завершают и очищают jobs.
  Только главный поток создаёт ArrayMesh/коллизию и публикует с ними picking/floor field;
  старое поле остаётся доступным, пока новый tile готовится, без синхронного field в hover.
  Это CPU cache, без частичного GPU upload. Покраска/дыры/смена основы и sectioned
  terrain сохраняют прежний полный путь; shader/schema/runtime owners не меняются.
  `SmoothSurface.material_weights` переиспользует строки точного separable kernel;
  `FieldJob` читает готовые dense heights напрямую; generic/sectioned sampling остаётся
  fallback, численный результат совпадает. `CompactBrush.stamp` передаёт центр очереди,
  не создавая историю/новый Source для промежуточных показов.
  `LookBake.faceted` кеширует пробы/нормали внутри build. CompactBrush history берёт
  готовые плотные массивы и длинные диапазоны, без per-column Resource getters.
  В `_stamp_point` dense group bounds проверяются до обхода каналов: has_column сохраняется
  только для sparse sections; touched/influence и detail baseline читаются из готовых массивов.
  Coarse baseline/математика и Source writers прежние. Это сокращает CPU input сборку большой
  маски, не меняет mesh quality/очередь/радиус. Замер max radius8 — directions/editor.
  Замер/ручная приёмка этого среза — directions/editor → «Результат».
  Сетка наведения — editor-only shader overlay на уже построенных `Ground`
  mesh каждого видимого tile. `ember_world_editor.gd` выбирает нужные tile и
  передаёт положение, форму и радиус кисти; shader рисует белые линии 8/16,
  мягкое затухание и жёлтую выбранную клетку только на верхних гранях.
  `ember_terrain_pilot_projection.gd` прикрепляет overlay и к обновлённому
  Ground после мазка, снимает его при выходе из радиуса/режима. Наведение не
  создаёт узлы или mesh сетки и не меняет Resource, коллизию и gameplay
  материал. Повторное событие в той же клетке не меняет shader uniforms.
  Overlay даёт дополнительный проход рисования на подсвеченных tile; его
  стоимость и плавность первого входа ещё требуют живой проверки в 3D Godot.
  Compact ground mesh сохраняет palette index в alpha вершинного цвета; RGB
  остаётся авторской палитрой. Вода берёт новый оптический материал из
  `EmberVoxelSurfaceMaterials`; общий preset отключает прежнюю движущуюся
  сетку и использует оптические волны с небольшими подвижными отблесками,
  которые получают яркость от света сцены. Глубокая часть более плотная,
  мелководье пропускает цвет дна. Изменение одного ShaderMaterial видно на
  Surface и компактной карте после повторной загрузки ресурса. Геометрия берега остаётся её
  прежним владельцем. Один shader
  `ember_compact_terrain_textured.gdshader` читает 16×16 рисунок выбранного
  слота из общего атласа; lookup отличает назначенные слоты от плоских.
  Старый режим 0 использует `ember_diorama_light.gdshaderinc`, fill и цветной
  bounce. Scene-owned `EmberMapLoader.compact_material_light_mode` выбирает
  0/1/2, `compact_material_gray_preview` даёт одноцветное сравнение. Projection
  передаёт их в тот же shader, без remesh/recollision/перестройки полей воды.
  `ember_material_light.gdshaderinc` — чистый leaf GGX/Smith/Schlick;
  режимы 1/2 отключают постоянную emission/fill граней, используют ROUGHNESS
  и ATTENUATION; пластик добавляет покрытие, мокрый песок сохраняет roughness.
  Gloss/sheen того же finish lookup управляют шероховатостью/силой отражения.
  Старый diorama ambient RID применяется только в режиме 0; остальные
  восстанавливают authored Environment. SSAO остаётся свойством Environment,
  принудительное отключение убрано; SSIL/SDFGI/volumetric fog ещё выключены.
  Панель «Материалы» использует прежний Undo/Redo; все look-поля сохраняются
  в `.tscn`, не в terrain Resource. Проба/ручные gates — тематический документ
  земли; runtime-панель пробы меняет те же owners без собственной сериализации.
  Общая карта теперь хранит `EmberMapLoader.world_look` (0 детальный / 1 low poly / 2 voxel;
  -1 сохраняет старую сцену). Projection кеширует производные меши по tile и инвалидирует
  при перестройке; collision/floor остаются прежними. `EmberVoxelProp.set_world_look`
  маршрутизирует существующие rock/tree bake; pre-save восстанавливает опубликованный mesh,
  post-save возвращает отображение, поэтому карта не сериализует производные буферы.
  `scripts/ember_grass_patch.gd` хранит параметры участка в scene Node;внутренний
  MultiMesh следует сухой травяной земле и общему Pattern/свету.
  Для detailed grass01.11 использует общий baked `prefabs/voxels/meshes/grass_card_contour.res`
  (8triangles),builder — `tools/build_grass_card_contour.gd`/Fixture/supporting trapezoid.
  Расстановка/ключи transform-cache/опора используют прежний полный card footprint;
  atlas image не обрабатывается runtime. Такой же contour в cuttable/стерне/herb visual.
  Grass0 — baked contour8triangles/native card LOD8; low1 — старый `Styles.grass_mesh`, voxel2 — прежний
  outline/snapshot. Оба исходника сохранены, WorldAnomaly использует прежний low correspondence.
  Маски/seed/материалы не менялись. Painted detail mode того же owner хранит
  плитки4м/density_cells25см/kind/seed/вариации; общий leaf — `ember_detail_scatter.gd`.
  Object grass/flowers (27 Oct): painted detail brush uses Map.surface_floor_sample and physical
  face palette roles from VoxelProp. Transient prop XZ bins index canonical collider faces;
  object signatures join nearby patch cache keys. Map.surface_object_changed dirties only overlapping
  painted patches after source/transform changes. Actual root vertices in all looks are checked;
  detailed grass applies height shear, leaving y=0 roots fixed; low/voxel stay upright.
  Anomaly object roots retain zero terrain endpoint delta. Existing non-vegetation detail rules remain.
  Main one new/one updated EDM1 mask; prior values/size/seed preserved. Native history/save/looks,
  movement/repaint invalidation, exact physics and anomaly root control PASS; mouse/art acceptance OPEN.
  Persistence25.10: same scene-owned dictionary/API, storage field `density_mask` with EDM1
  bounded lossless Zstd; legacy text reads normally. `_validate_property` omits valid legacy
  dictionaries on new Save. Invalid legacy data/corrupt blobs remain recoverable and validate.
  Projection owns derived surface_tile_revisions (height/paint/wetness/halo), separate from
  height-only brush-grid revisions. Grass local stamps preserve unrelated prepared scatter;
  section restore retains unaffected surface versions. No new Source/scheduler/renderer.
  Main parity/CPU/GPU limitations — World Authoring → «Маски, локальное обновление».

  `addons/ember_import/ember_detail_brush.gd` наследует object-brush input/history; host route `details`.
  Библиотечный kind2 сохраняет detail_preset/variant/mixed; `ember_detail_pattern_bake.gd` готовит
  rock recipe и обычный KIND_VOLUME с существующим multipart solid_surface через прежние Solid
  buffer methods. Природные Sources/presets — `vox_detail_{daisy,wildflowers,wheat,shell}`; часть
  формы не сливается с остальными. Явный refresh перечитывает data Resources, не скрипты.
  CPU — WorkerThreadPool/private snapshot,
  mesh/material upload — main thread; кеш8 наборов, одна плитка/MultiMesh на форму с hash partition.
  Мелкий stone-декор (`GrassPatch.is_detail_stone`) использует одну faceted форму в0/1 и hidden2;
  sphere grass_form1 сжимает его в voxel-области, voxel-only binding для него не создаётся.
  Крупные EmberVoxelProp не затронуты. Derived scatter кешируется; сцена хранит маски, не instances.
  Цветущая трава kind3: `ember_flowered_grass.gd` кеширует3 формы, Source — прежний Pattern
  `terrain_materials/meadow_{daisy,buttercup,lilac}_cover.tres`/parts PNG. flower_shape0/1/2 —
  сохранённое/валидируемое поле Pattern, default0; 3 растения на mesh, 186/186/888 треугольников.
  `compact_flower_material`/EMBER_FLOWER_COVER — прежний shader, локальные UV/palette uniform,
  alpha scissor0.55, grass pigment/свет. Без voxel Source, формы одинаковы0/1/2, sphere один binding.
  Кисть выбирает3 Source; kind3 mask key учитывает путь, legacy daisy key сохранён. MaterialPatternDialog
  cover-режим правит PNG/tint/shape с private preview/Undo/Save/Cancel; shape меняет только patch
  этого Source и инвалидирует sphere binding прежним scatter/mesh identity путём. Движение без подготовки.
  Main5/10/8 групп; focused sets/history/save/reopen/discard, active sphere shape edit/main PASS.
  Native RGBA-рисовалки нет; колосья/ракушки черновые, voxel-пробы цветов отключены/не удалены.
  Gates/evidence — World Authoring → «Текстурная цветущая трава — текущий срез25.10». `EmberTreeLookBake.prepare` подключает оба
  вида при начальном world_look, одинаковые Sources используют общий кеш в памяти и
  `user://ember-tree-look-cache` через прежний `ember_derived_data_cache.gd` (256 МБ, до 128 МБ на запись).
  Хранятся native surface buffers/маска без Materials/Objects; текущие материалы привязываются после чтения.
  `EmberVoxelModelResource.to_definition(true)` даёт отдельный packed snapshot без расширения в Variant arrays;
  default definition/schema/сохранение не менялись. Ключ — Source/код/artwork/engine; ручная приёмка открыта.
  Пустой кеш считается синхронно при открытии; фоновая сборка не включена. Метрики — directions/world-map.md.
  Локальная область — scene-owned `Map/WorldAnomaly`, `scripts/ember_world_anomaly_3d.gd`:
  одна сфера, параметры через существующий WorldLookPanel/историю. Общая математика shader-поля —
  `shaders/ember_world_anomaly.gdshaderinc`; движение меняет только instance uniforms.
  `ember_terrain_look_bake.anomaly_carrier` дополняет fine top вырожденными внутренними voxel-ступенями;
  в detailed/low они схлопнуты, при переходе раскрываются вместе с соседними верхними гранями.
  `ember_anomaly_correspondence.gd` заранее привязывает готовую voxel-топологию камня/коры к detailed,
  готовит текстуры целей на вершину; nearest triangle через spatial buckets, единая позиция для UV-швов.
  Fragment lighting25.10: detailed solid computes texel origin from morphed terrain_world_position
  through existing solid_depth_world_to_local, retaining authored terrain_position for pigment/POM.
  Prepared non-MultiMesh surfaces (ground/solid) shift LIGHT_VERTEX on the geometric plane,
  without extrapolating NORMAL across unfolding risers. Shared shader owns this correction;
  carrier/targets/Source/physics unchanged, grass and unprepared/global-look paths unchanged.
  test_world_anomaly_surface_light compares GPU morph to an independently baked same surface;
  legacy origin negative control fails. Main view/motion verified; author art/input gate OPEN.
  Носитель приближает детальный силуэт. CPU-буферы/цели кешируются прежним атомарным derived cache
  в `user://ember-anomaly-cache` (256 МБ); версии ключей принадлежат helper. Runtime GPU-операций в workers нет.
  `EmberTreeLookBake.anomaly_meshes` сохраняет исходные карточки и опорные точки, для voxel они
  схлопываются целиком; готовые voxel-листья растут ячейками. Reference vertex карточки = base+7;
  cell faces имеют порядок [0,2,1,0,3,2] — связан с shader-вычислением центра целой ячейки.
  GrassPatch владеет всеми coloured look meshes; сфера копирует его готовую расстановку в internal
  MultiMesh с дельтами посадки в INSTANCE_CUSTOM, не рассеивает траву заново при движении поля.
  Инвалидация отслеживает и mesh, и сам MultiMesh (плотность может поменяться без нового mesh),
  удаляет только устаревшие bindings; завершённые незатронутые Source сохраняются. Незаконченная
  группа после отмены не считается готовой. Terrain carriers и tree anomaly meshes кешируются
  тем же CPU-транспортом; terrain key включает локальный halo, а не глобальную ревизию карты.
  Ground material distance29.10: SurfaceMaterials.compact_terrain_bank_far_shader использует
  тот же shader без compile-фичи POM/DEPTH. Projection._far_ground_materials — disposable copies
  по canonical region/base, с общими текстурами; invalidation на look/material/light/preview/water
  rebinding. WorldDetailPolicy выбирает по ближайшей точке world AABB только за существующим
  depth-fade endpoint с запасом/гистерезисом. Source/mesh/collision/history не меняются.
  Подключено в editor look0; другие looks/runtime/prepared anomaly — прежний путь. Доказательства,
  оговорка раннего aggregate probe и следующий шаг — [Производительность мира](EMBER_WORLD_PERFORMANCE.md#доверенная-текущая-точка) → «Доверенная текущая точка».
  Adaptive far geometry29.10: Surface.build_arrays keeps canonical collision/field and derives
  bounded render fans via fixed32/16/8/4 blocks. Mixed slot IDs/weights and triangle-overlay errors
  validated; holes/side paint/more3 slots retain fine geometry. Editor GeometryCache far key
  editor-top-adaptive-v2 uses payload editor_version2 with separate collision_faces; v1/full unchanged.
  MeshBuilder section translation handles visual and physical arrays separately. Projection owns
  selection/publication; WorldDetailPolicy.ground_lod_enabled is session-only. Runtime/looks1/2
  unchanged. Scope/gates/evidence — [Производительность мира](EMBER_WORLD_PERFORMANCE.md#доверенная-текущая-точка) → «Доверенная текущая точка».
  Editor detail policy28.10: EmberWorldDetailPolicy (leaf без данных/задач), TerrainProjection
  и GrassPatch продолжают существующие jobs/GeometryCache/DetailPreparation. В editor look0
  точные ближние/плоские far surfaces имеют разные cache keys; остальные looks земли пока точные.
  Дальние детали освобождают только производные MultiMesh/material/transform arrays; Source/маски
  и история сохраняются. Геометрический fade — opt-in uniform общего shader, default off.
  WorldCanvas/StartupDiagnostics используют detail_preparation_pending; runtime барьер прежний.
  Throughput30.10: `ember_detail_scatter.gd::TerrainJob` считает обычные grass/flowers по
  immutable local columns/fine fields; `DetailPreparation` владеет2 worker admissions,
  cancel/early cleanup signal/join. GrassPatch проверяет cancelled/_scatter_current до публикации.
  Physical candidates/tilted terrain/kind1/2 сохраняют foreground path; schemas/cache seeds прежние.
  Sleeping admission index находится только в том же Preparation: source64 bins,≤16/patch,
  oversized fallback, transform notification и O(1) remove. Policy/Projection решают residency;
  Source/authoring/history не переносятся в index. Runtime/editor используют общий путь.
  Exact parity/lifetime/admission и native immediate move PASS;120FPS/manual view OPEN.
  Данные — World Authoring → «Фоновая подготовка и пробуждение травы30.10».
  GrassPatch surface_object_changed подключён только у resident painted patches; exit/return dirty.
  QA grass residency04.11 наблюдает Map.detail_scatter_changed(publication/look/release);
  GrassPatch.set_detail_render_override — transient native visibility handoff,не Source/save.
  QA worker bytes→bounded RD pool/generation guards принадлежат внешнему qa_stream_grass;
  compute иshader fade следуют одному живому projection. Production GPU adapter не подключён.
  Shared DetailPreparation приоритетно доставляет completed material/cache-read owner,пока
  он удерживает bounded slot:иначе dense nearer retries могут бесконечно не пускать его.
  RED→GREEN/cancel/teardown иdense GPU return PASS;latency/memory/art/120FPS OPEN — Performance.
  MapLoader владеет одним ObjectLOD.ObjectJob: main snapshot, CPU ImporterMesh worker, main publish,
  stale/disabled discard и exit join; прежние cache8/prop/physics/material owners. Poll distances local.
  Перенос04.11: для named tree_bark тот же ObjectJob выбирает первый meshoptimizer LOD
  как near presentation, compact vertices и строит дальние native LOD; Source/коллизия не меняются.
  GrassPatch.grass_render_mesh держит один derived ArrayMesh ordinary8→6→4 с прежними
  вершинами/UV/атласом/roots, native projected-error selection; look1/2 прежние.
  FloweredGrass05.11:6thin plant families в том же GrassPatch detail_kind3, включая wheat;
  cache keyed by existing flower_shape0..5, TerrainMeshLOD.object_mesh даёт native distance LOD.
  Pattern/validation/dialog/brush/save используют тот же Resource, без нового renderer/scatter.
  Voxel flowers удалены; старый wheat только tools/fixtures, main mask переведён на cover.
  Near geometry/UV/color первых3 exact,6sets/history/save/3looks и main FOV40/70 PASS;
  детали/цена/пределы — Terrain Authoring «Цветы, высокая трава и ориентир Zelda03.11».
  Source assets не перезаписываются. Геометрия/материалы/main3looks/native editor save/reopen
  проверены; нагрузочный маршрут и ограничения — Performance «Возврат к созданию локации».
  Far preflight в том же MapLoader: threaded Source read → Layers.PreparationJob CPU arrays/model →
  прежний Layers cache8 → main prepared_mesh. Один CPU object job суммарно с ObjectLOD.
  VoxelProp.remember_solid_source сохраняет cache4/hooks; volume far не читает ненужный Source.
  Source/mesh edit invalidates/discards, disabled rejects, exit joins CPU и loader request.
  SurfaceMaterials.DepthPreparationJob в том же object budget1 готовит private CPU height Images;
  MaterialHeight.read_bake — прежний transport/algorithm, remember_bake/shared caches на main.
  Map держит source Texture2D до handoff host→material; changed/disabled/exit/remove reject/release.
  VoxelProp first sun lookup сохраняет preorder/internal и завершает поиск на первом свете.
  Pixel/private-preview/cache/lifetime/handoff/last-consumer/save/return/Undo/discard PASS.
  Последний native max47/36мс, GPU14–15мс/120FPS OPEN.
  Последние gates/evidence — [Производительность мира](EMBER_WORLD_PERFORMANCE.md#доверенная-текущая-точка) → «Доверенная текущая точка».
  Свет30.10: main Map.directional_shadow_filter5→2 одобрен автором для дальнейшей проверки,
  остальные Scene bytes сохранены. Existing quality/panel owner прежний, shader/body неизменны.
  Native visual profiler доступен с --remote-debug local:// + EngineDebugger visual profiler;
  RD timestamps дают generation≈0,5–0,7мс, opaque≈11мс. Low2 fixed near/wide9,6–11,0мс.
  UI/history/native fixture save/reopen/discard PASS; manual/gameplay/120FPS OPEN.
  Owner — [Производительность мира](EMBER_WORLD_PERFORMANCE.md#доверенная-текущая-точка) → «Доверенная текущая точка»; отдельные CPU stalls отложены автором до после света.
  Audit/cache/revision/4-corner/rock-return fixes сохранены. World prep30.10: CacheTrimJob
  один/context, только disposable paths, coalescing/cancel/join; main16–30мкс вместо63–65мс.
  Grass signature стартует под бюджетом; TerrainJob смешанного patch считает clear cells,
  object cells остаются прежним exact sampler; ranges merge сохраняет3 typed looks/порядок.
  Preview/unsupported cases fallback; parity/lifetime/cache PASS. Prepare29м/fade16–24/release32.
  Fully faded conservative world bounds скрывают только пустые draws; anomaly path защищён.
  Cold95м required61/32→0/0; real release/return258/258,272/272 exact;physicssupport0misses.
  2/4мс отвергнуты: общий8мс прежний. Wall p9523,1/24,7,max32,5/36,7;GPU p959,2/9,1мс.
  После whole-frame audit GrassPatch сохраняет bounds по transform/map/unit/mode/size/tuft size;
  readiness scan только для dirty rebuild после transform/revision/surface invalidation.
  Residency/fade/process callbacks и editor owners прежние. Native dense1440p median
  19,32/19,10→15,86/15,53мс,p9528,40/29,34→24,12/26,23; cold required/floor0/0,
  unload/exactreturn258/258. Local edits/cache/admission PASS. Preparation также хранит до16
  private saved material templates по SHA файла; per-frame copies отделяют6packed channels,
  импортированные textures общие; release освобождает templates. Ground timer начинается ДО
  observer/residency, soft8мс прежний. Native parity/same-second save/private/release/budget PASS.
  Cold median19,34/18,04→18,46/15,83;p9526,89/29,19→25,42/25,80;max72,60/55,02мс.
  Cold coverage/floor0/0, unload/return258/258 exact. Новый stalls slice: VoxelProp разделяет
  immutable floor faces/slots/roles stamp и world query bins; заполняются только запрошенные bins,
  projected triangle bounds хранятся в PackedInt32Array и сбрасываются по mesh/shape/transform/
  cell-size changes. Signature tuple/cache format прежние; collision Resource не заменяется.
  GrassPatch после TerrainJob.ready повторно ждёт budget turn до foreground roots/merge.
  Policy prepare30/fade16–24/release32; ground prepare учитывает диагональный угол default4м
  patch+halo, capacity384/release circle прежние. 29м и30м без ground support отклонены.
  Cold required/floor0/0; release267/267, return265exact+2unused hysteresis. Job poll max
  8,55→0,40мс,signature17,36→4,76; whole p9526,37/26,35→25,13/26,79, FPS gain не доказан.
  Whole max61,38/46,72; старые72мс не воспроизведены/не объяснены, cache write max3,46мс
  не доказан их причиной. Далее — remaining budget-turn/whole-frame GPU и согласованный
  mixed stress. Source/authoring nodes остаются в RAM;
  массовые NPC/dynamic physics и больший мир отдельно не приняты по производительности.
  Render frame30.10: Projection._published_water — derived weak inventory непустых Water
  fine/overview instances; publication/release/open/resize его обновляют. Water controller
  решает floor capture demand в frame_pre_draw и освобождает callback в _exit_tree;
  unknown owner conservatively ON, Regions count не заменяет actual mesh presence.
  EMBER_FLOWER_COVER компилирует один profile (vertex заполняет три одинаковых slots);
  generic grass сохраняет mixed fallback. Source/collision/schema/плотность прежние.
  Materials.prepare_terrain_roles/apply_prepared_terrain_roles разделяют packing и binding;
  Runtime GrassPatch использует Preparation.bind_saved_material_roles_async:один private
  digest worker/result на context,delivery через общий budget,patch cancel без IO wait,
  context teardown join. Новые/изменённые файлы перепроверяются прежним sync path.
  Private lookup bindings/live profile replay после await сохраняют editor preview;
  source/layout mismatch отменяет кандидат. CPU/evidence/120 gate — Performance owner.
  Preparation.bind_saved_material_roles хранит≤16 prepared payloads по saved SHA/layout/palette
  и texture revision. Private GPU textures/4mutable CPU images, weak PNG bank/release сохранены.
  Terrain body water-camera discard исключает IN_SHADOW_PASS; native red→green и реальные
  camera-pass regressions PASS. Self-shadow flicker на зелёных склонах — live gate автора OPEN.
  Regions._selection_cores — derived revision/connectivity halo filter; distances/readiness
  and cancellation remain live. Unknown connectivity conservatively retains every source core.
  Surface.prepare_render_upload использует CPU SurfaceTool.index и remap native LOD;
  MeshBuilder/HeightUpdateJob передают transient upload,canonical layout/Source/cache schema прежние.
  Main-thread publication потребляет indexed upload;residency seams тоже indexed.
  OverviewJob.index_upload готовит immutable CPU chunks/identity indices. Projection._update_overview_ground
  хранит revision-scoped ArrayMesh/coverage mask и обновляет render index buffer штатным RenderingServer API.
  Hidden patch — degenerate triangles,all-covered Ground hidden;новый revision создаёт новый mesh.
  Picking читает document/fields,не CPU triangle cache overview;water/seams и Source schema прежние.
  WorldCanvas.is_world_preparation_complete читает прежний startup barrier,не новый flag.
  Preparation.frame_budget_us выбирает startup/editor/active brush5мс или gameplay3мс;
  replacement/reparent не сохраняют чужую фазу. Physics/preview/pixels/gates — Performance owner.
  Preparation разделяет текущие и повторно запрошенные budget turns:один ticket
  исполняется максимум раз за dispatch,чтобы near waiter не блокировал дальнего
  владельца bounded digest/read slot. Cancel/prioritize/release охватывают обе очереди.
  Preparation.foreground объединяет begin_ground/finish_ground + finish_detail + timer queue;
  sleeping admission внутри ground не дебетуется дважды. Weak per-patch context + shared poll epoch
  сохраняют Source/transform/material/anomaly invalidators; Engine editor fast guard отключён.
  PilotMesh.prepare_heightmap_collision хранит immutable float grid CPU payload; EditorTilePublication
  создаёт HeightMapShape3D. Projection принимает Shape3D и collision_position; holes/walls/nonuniform
  placement и deform study используют прежний Concave. Канонические faces/field/cache3 сохранены.
  Flower fragment early alpha clip сохраняет threshold/pigment; native RGB parity/GPU A–B–A PASS.
  Main Sun.angular0/filter2 по разрешению автора на чёткие тени; sunset/blur/distance прежние.
  Astra/Terra audit не обосновывает замену terrain renderer: measured cost material/receiving.
  Uniform tables/guarded sampling rejected; compiled detailed variant QA-only, не новый production owner.
  Materials.refresh_terrain_features выбирает shared immutable program по10живым feature flags,
  cap32Shaders (stress2); uniforms/texture bindings прежние. Materials profile APIs,
  MapLoader.bind_voxel_light, Projection и GrassPatch light/look/publication обновляют варианты.
  Grass publication теперь ждёт `Materials.prepare_terrain_features_step` впрежнем
  Preparation dispatcher:короткая генерация,≤2threaded ResourceLoader requests,
  live binding тольконаmain;failed staging возвращает sync путь. Генератор уsync
  иincremental общий;временные `.tres/.gdshader` принадлежат user cache,не карте.
  Runtime raw changes этих flags требуют refresh; tool-editor/headless generic. ResourceLoader
  раскрывает ShaderInclude; Source/physics/save schema не менялись. Native3looks/render/live PASS.
  Native проверки/числа/открытый gate — [Производительность мира](EMBER_WORLD_PERFORMANCE.md#доверенная-текущая-точка) → «Доверенная текущая точка».
  120FPS/stalls/ручной view/долгая память OPEN; owner — [Производительность мира](EMBER_WORLD_PERFORMANCE.md#доверенная-текущая-точка) → «Доверенная текущая точка».
  Параметры пока сессионные в code, не новая Resource-схема/панель. Ограничения и дальнейший
  маршрут — [Производительность мира](EMBER_WORLD_PERFORMANCE.md#доверенная-текущая-точка) → «Доверенная текущая точка»; общий streaming ещё не завершён.
  GrassPatch порционно готовит расстановку, отменяет устаревшую и атомарно публикует MultiMesh;
  материал переиспользуется до изменения палитры, профиль обновляется прежней командой.
  Воксельная трава отображается производными группами 4×4 м, без изменения исходной расстановки.
  Bounds всех endpoints определяют отсечение; voxel-only представления выключены в low poly.
  MapLoader.anomaly_materials_changed передаёт текущие profiles/light/depth подготовленным материалам.
  Представления — internal/без owner, дочерние исходному visual, чтобы сохранять transform/picking
  исходного prop/patch; pre-save возвращает исходные render layers, удаление сферы убирает её производные.
  Общий world_look 1/2 показывает исходный путь. В редакторе исходный путь активен до явной кнопки
  «Предпросмотр аномалии»; вход в World Editor/мазок возвращает его на всю сессию. Сессионное
  состояние не экспортируется и не пишет историю. Runtime готовит сферу внутри startup gate
  WorldCanvas; движение поля не готовит меши/расстановку. Несколько сфер пока вне контракта.
  Native runtime/editor checks и открытая визуальная приёмка — directions/world-map.md.
  `EmberCompactTerrainPattern.depth_texture` — optional paired optical height; null сохраняет
  derivation из рисунка, используется terrain и solid consumers. Старые Resources совместимы.
  Terrain bank-depth — compile feature того же shader/solver: profiles по palette slot,
  height Texture2DArray, глубина/fade × map units; grass role исключён. Неиспользуемые
  ground custom hull channels исключены из этого варианта, varying budget не расширялся.
  `ember_texture_world_unit` default 1 сохраняет прежние сцены; новая карта и пучки передают
  imported_tile_size, поэтому цвет/height используют одну метровую привязку. Коллизии не меняются.
  WorldLookPanel маршрутизирует параметры выбранного GrassPatch через прежнюю историю;
  scatter/derived MultiMesh остаются у GrassPatch, а параметры — в `.tscn`.
  Bank-depth различает наличие водных passes и камеру текущего прохода: POM исключается
  только из служебных reflection/refraction views, не из камеры героя. Эффект проверен
  парой depth on/off на реальной основной карте с водой.
  Объекты: optional `EmberVoxelModelResource.material.object_surface` v1 хранит
  default/overrides palette ролей stone/bark/foliage/crystal/ice/glass/legacy; поля schema6
  сохранены в schema7. `ember_voxel_material_profiles.gd` — чистый владелец enum/preset/
  validation/remap, без RGB inference. VoxMesher переносит Vector4(role,roughness,
  F0,grain) в ARRAY_CUSTOM0/RGBA_FLOAT; padded regions, SurfaceMesher и session
  ProjectionCache сохраняют поток/формат. Cache key учитывает параметры, signature
  получает object-surface-v2-light-finish только у opt-in моделей; legacy mesh не инвалидируются
  глобальным bump. Существующие генераторы записывают роли, stamp/merge учитывают
  их при dedup цветов и переносят в прежний property transaction/Resource.
  `ember_voxel_surface_light.gdshaderinc` использует общий material-light leaf;
  старые toon/transparent shaders читают роль, дают GGX specular/IBL и статическую
  role-specific normal/roughness с derivative fade; bark local-Y fibres, foliage
  roughness0.68/F0.028. Активный diffuse не повторяет ALBEDO, общий чистый BRDF leaf
  нормирует /PI; specular учитывает SPECULAR_AMOUNT. Без роли/compare-off diorama
  сохранён, direct-specular отсутствует;
  прежние COLOR/alpha/flat geometry/collision сохранены. Количество surfaces не растёт.
  Трава/грунт: прежний EmberCompactTerrainPattern хранит optional micro_relief,
  micro_size_m, micro_roughness с validation/default strengths0. SurfaceMaterials
  кодирует grass1/soil2 в B role_lookup и добавляет RGBAF detail_lookup256×1;
  обновление только на назначение/Save. Terrain shader вызывает один чистый leaf
  ember_terrain_surface_detail.gdshaderinc: static quantized groups/grains,
  три height samples, view-normalized basis, roughness variation/derivative fade.
  Local positions/16 дают logical metre scale, без runtime CPU/remesh/новых граней.
  Та же MaterialPatternDialog draft/history/Save/Cancel/variant routing сохраняет
  три поля; controls недоступны для stone/sand. Отдельные grass_surface/soil_surface
  сохраняют прежние artwork/палитру. ground_material_study — один Map, внешний
  compact Resource8×8м и presentation-only F/G/L/ПКМ; форма/collision общие.
  grass_painted — отдельный прежний TerrainPattern с новым top/side artwork и
  более крупной/мягкой micro-фактурой, без новых полей/shader math. Builder --painted
  создаёт отдельный ground_grass_painted_study на той же геометрии/свете и тех же
  грунтовых ID; общий native driver выбирает study path/variant через QA env.
  Independent surface artwork в прежнем TerrainPattern: optional top/side
  relief/roughness arrays16×16 уровней0/1/2, pattern_size_m(default4) и
  roughness_variation(default0). Empty relief наследует color heights, empty
  roughness нейтральна; sides наследуют top. Factory пишет height в alpha прежних
  atlases, добавляет два R8 roughness atlas(128KiB) и RGBAF surface_lookup4KiB.
  Smooth bark LAB: RestoredTreeFixture keeps selected17/7 scaffold/clouds/wood
  from the old LAB; Source SHA/counts match. PaintedBarkProjection binds existing
  bark role + derived CUSTOM1 support pairs and RGBAF frame lookup. Optional
  painted include on existing toon shader projects artwork in local coordinates,
  blends neighbours, unwraps atan derivatives, uses source-owned PNG/mipmaps.
  The same factory now compares old/coarse bark and painted foliage. Optional
  foliage include samples object-local triplanar3.5m, retains original paint as
  relative pigment, reuses painterly light helpers and painted_light_grass profile.
  No canopy geometry/normal/UV changes; old painted render matches A exactly.
  Leaf-card LAB extends the same material factory/renderer: saved scaffold →
  TreeLeafCardsFixture fixed quad layers + CUSTOM1 group normals, one mesh;
  optional LEAF_CARDS define supplies UV alpha scissor/cull_disabled. 394quads/
  788tris, source paint unchanged. TreeLeafCardsStudy inherits the old fixture
  and keeps rounded A; targets/limits — Terrain Authoring → «Аниме-ориентир деревьев».
  Ground POM/grass/floor retained; tree has no new collision/authoring transfer.
  Active parametric LAB: LargeTreeProvider opt-in oak21 → pure BranchLayout
  recursive growth (tree-gen/MIT attribution in THIRD_PARTY_NOTICES). Existing
  Recipe.structure version1/Source owner, four bounded count/depth/variation
  parameters.21 allows≤768 supports/order4 (worst603), crown markers≤128;
  old20 keeps256,1–19 keep128, defaults/LATEST_VERSIONS remain17.
  branch_seed metadata + topology comparison regenerate changed21 scaffold;
  appearance-only edits retain lines. Generator descriptors expose controls,
  same GeneratorPanel/Creation transaction; context.field_keys focuses LAB only.
  ParametricStudy compares20/21 plain/bark, density presets and cache restore
  on preview removal; no collider/cards/camera-owner transfer. Source/Recipe
  save/reopen, existing panel Undo/Redo/discard/preview equality checked.
  Foliage21 LAB adds existing crown_cards optional branch_growth path; Source21
  remains bare/unchanged. Last two branch levels own stem UV vertices; one
  derived curved-card mesh (normal1967/23604tris), existing atlasv2 and material
  factory. Group+whole-crown normals, accepted grass light profile, no shader/
  collider/new asset changes. Foliage21Study extends ParametricStudy and caches
  baseline foliage for preview removal; production renderer transfer deferred.
  Shape/volume21 accepted as a basis; foliage/bark artwork needs refinement.
  Material-only LAB revision2026-10-15: Foliage21Study clones existing materials,
  swaps only albedo (atlasv3_quiet/barkv4_soft), and offers old/leaf/leaf+bark buttons.
  Support projection/mesh/UV/normals/light owners unchanged; native previous frame
  is pixel-exact. Artwork acceptance OPEN — Terrain Authoring → «Построение дерева».
  Minimal one/two-tone atlas variants follow in the same LAB; factory/geometry
  owners unchanged. Temporary nearest/no-mip sampler clone largely removes dark
  edge net; original material restored exactly, shader files remain unchanged.
  Approved leaf-optics trial2026-10-15: same factory artwork(path, alpha_edges)
  opt-in cache prepares padded RGB + alpha-weighted straight-colour mipmaps;
  default path and authored PNG/alpha unchanged, filtered sampler retained.
  Shared painterly light owns material rim weight and pure transmission helper;
  leaf-card uniforms default0/saturation1 preserve prior materials. Directional
  LIGHT_COLOR/ATTENUATION drive both additions, no emission. Foliage21Study owns
  five comparison stages and transient saturation1.18/transmission0.28/rim0.23
  sliders; v7_air_gaps is optional artwork, same mesh/UV/normals/Source/wood.
  Native previous-frame and zero-Sun comparisons are pixel-exact. Ground light
  changes from gaps are subtle; atmosphere rays and production/editor profile
  transfer deferred. Artistic/F6 gates — Terrain Authoring → «Построение дерева».
  Separate-leaf first-stage samples: Foliage21Study opt-in button extracts1/6
  existing curved cards into preview-only meshes away from the tree. Original
  tree arrays/material stay exact; v8 atlas and local material uniform comparison
  use existing artwork cache/toon/common light. No new geometry/data owner or
  profile schema. Historical tree frame pixel-exact; new LAB variant described
  below, production material transfer awaits art review — Terrain Authoring →
  «Построение дерева».
  Shadow diagnostic on same samples: QA-only controls confirm real shadow path,
  sensitive to depth bias/PCSS; macro/geometric normal controls don't eliminate
  ripple. Bias1.6 clears one card but alters group/receiver shadow coverage, so
  no global bias/light profile change applied. ATTENUATION has no caster
  identity; selective internal-shadow response needs a separate boundary choice.
  Source/study/shader assets and baseline return exact; evidence and gates —
  Terrain Authoring → «Исследование рисованной листвы».
  Whole-tree trial approved next: Foliage21Study material variant5 clones sample
  stage2 with requested shadow0.4;0.35/1.0 and original return available in LAB.
  Transient material/panel only, original default and sample independent; no
  shader/factory/generator/schema/camera changes. Native3×2×tree/game, near/far/
  side/back/motion and original return exact; same-atlas ground shadow ROI exact.
  Canopy remains dense, grain and art/input gate OPEN. Game framing still clips
  part of canopy; no camera direction accepted. Contract/evidence — Terrain
  Authoring → «Исследование рисованной листвы», ember-tree-leaves-40/.
  Density trial follows user's feedback: existing BranchingFixture owns pure
  thin_crown_cards(full,coverage), stable whole branch+t puffs ranked per crown
  owner; nested subsets retain positions/UV/colour/custom macro normals exactly.
  Packed geometric normals retain direction (max error0.00012894), full buffers
  untouched;100% returns full instance. Foliage21Study owns transient slider/cache,
  release/Enter/focus commit, no per-drag rebuild; only material variant5 thinned.
  Existing shader/material40%/Source/wood/floor/physics preserved; normal count
  889→534 puffs at60%,1967→1186 cards. Old100 frame and return exact, fixture and
  native3×2×tree/game/near/far/orbit guards PASS. Artistic density/F6/input and
  production Recipe transfer OPEN; evidence — ember-tree-leaf-density/.
  User now prefers45% as next visual basis and wants local thinning/internal
  shading controls. QA only `capture_tree_shadow_modes.gd` clones low0.55/0.80,
  caster OFF/receive0/AO controls,3×2×tree/game/external shield. Cast OFF like grass
  loses canopy ground shadow; receive0 loses external response; macro/AO darkening
  is separate. All25 protected files/baseline45/return exact; no installed change.
  Local density/dark-form UI contract now implemented below; true
  caster-selective internal shadow requires separate boundary,
  not a renaming of general strength. Evidence — ember-tree-shadow-modes/.
  Current LAB: Foliage21Study starts trial5/global45/shadow0.4/depth100(low0.24).
  BranchingFixture.crown_leaf_groups + optional local_coverage in thin_crown_cards
  own eight actual crown parts; UI frame highlights full part bounds, hidden F1,
  caster OFF/GI disabled. Local factor retains other owners exactly; cache key
  includes local percentages; new branch preview clears local overrides/selection.
  Form-depth slider sets existing leaf low only, no shader/math/schema change.
  Existing RecipePanel.history owns local/depth/reset Undo/Redo; recipe unchanged.
  Native3×2×tree/game/views/motion/local drag-one-build/cache/reset/F1/zero-Sun/
  external/ground guards PASS; baseline/control-only/current post-blocker return
  exact; post-blocker numeric precision gate max1 RGB8 level/≤128 pixels.
  Personal art/input/production transfer OPEN. Evidence — ember-tree-leaf-local/.
  Grass-family A/B: same Foliage21Study set_tree_leaf_shared_light owns a temporary
  material clone; existing foliage include adds RGB artwork strength default1,
  candidate .18 + current-card pigment reference/base/response from grass Pattern.
  No mesh/alpha/shadow casting changes, receiving .4 retained. Native3×2×tree,
  exact original A/return, ground ROI/data/POM/external/zero-Sun guards PASS.
  Fixed B turns off on form/shadow edits; old controls/resources preserved.
  User accepted calmer B direction; movement/production gate OPEN; details — Terrain Authoring, evidence
  ember-tree-grass-light/. No production schema or selective self-shadow fix.
  Tree rim LAB: ember_stylized_rim.gdshaderinc owns shared pure response extracted
  exactly from painterly light; voxel_toon exposes object_style_rim_enabled/strength,
  defaults false/0. Directional LIGHT_COLOR × raw ATTENUATION, existing normals.
  Foliage21Study owns B/wood clones and transient toggle + wood .45/leaf .18 sliders.
  OFF restores base bark; A/form/shadow disables rim. Native baseline/off/return,
  ground ROI, Source/mesh/Recipe/POM, strength0/zero-Sun/full-shadow guards PASS.
  User accepted B + .45/.18 rim. Permanent controls now live in WorldLook/Pattern/
  existing model.material.object_surface.style_rim; PalettePanel + canonical Actions
  handle object role controls. Material-only bindings cover Canvas, world draft,
  Prefab and SurfaceProjection; per-instance map master preserves shared assets.
  Single shared include; no new renderer/preset family. Native/targeted PASS,
  editor/F6/125%/movement manual OPEN. Full B artwork authoring remains deferred.
  Current evidence — ember-style-rim-transfer/; details/gates — Terrain Authoring.
  Bark species trial: Foliage21Study owns transient A/B/C albedo selector, default C;
  same PaintedBark projection/material instances and Source rim bindings retained.
  Six imagegen assets/provenance in material_studies/trees/bark_species_v1; only oak
  fitted, C user-accepted. Other bark assets candidates; own F6/motion OPEN.
  Native/fixture guards PASS; owners/gates — Terrain Authoring → «Крупная рисованная
  кора и кандидаты пород»; evidence ember-bark-species/.
  Birch22: explicit tree_type2 opt-in in same LargeTreeProvider/BranchLayout; defaults
  remain14/17/13/12/15 and oak21 exact. Same Recipe normalization/validation,
  build_on_structure rebuild, editing descriptors/RecipePanel history/save paths.
  SpeciesFixture/SpeciesStudy derive LAB meshes/cards only; five old support-mass
  diagrams plus accepted oak, own birch atlas/bark via unchanged painted shader.
  Native/5 targeted checks PASS; birch look accepted, manual/production OPEN. Owners/gates —
  Terrain Authoring → «Пять пород и берёза22»; evidence ember-birch-species/.
  SpeciesStudy owns transient birch controls via existing RecipePanel.history;
  BranchingFixture owns whole-puff global/local thinning, Profiles existing rim binding.
  Accepted60%/388 cards/B/40%/.45/.18 retained; release once/bounded32 mesh cache;
  stale local history guarded by Source identity. LAB foliage settings not Recipe data.
  Current birch controls/evidence — ember-birch-controls/; maple follow-up below.
  Maple23 opt-in/type3 uses same Provider/BranchLayout/Recipe, short trunk/wide forks;
  old defaults and oak21/birch22 unchanged. MapleStudy configures shared SpeciesStudy
  via species hooks, no separate light/controls/thinning implementation. New own atlas
  maple_v1/v2-rooted plus saved maple bark candidate; no shader edits. Native matrix,
  maple and birch controls PASS, art/manual/production OPEN. Owners/gates — Terrain
  Authoring → «Клён23»; current evidence ember-maple-species/.
  Maple shape follow-up: old crown_shape0/default scene preserved exactly;1 routes
  new upright supports through same BranchLayout, provider rebuild/validation and
  Recipe. Shared SpeciesStudy.trial_field_keys exposes fifth form field only maple.
  Existing Recipe variants saved under maple_v1/variations; wide liked/preserved,
  upright accepted as primary on 2026-10-15. Assets/light unchanged; current evidence
  ember-maple-shapes/, details/gates — Terrain Authoring → «Клён23».
  Savanna24 opt-in/type0: BranchLayout._savanna_plan uses same recursive supports,
  Provider validation/Source and Generator/Panel count fields. Shallow crown guides/
  card orientation gated24 only; accepted21/22/23 outputs exact. SpeciesFixture and
  SavannaStudy reuse same controller/Recipe/history, directory hook and accepted
  reference factory. Own savanna_v1/v2-calm atlas, existing savanna bark; shader intact.
  Native matrix/controls/Recipe checks and4 regressions PASS; art/F6/motion and
  production foliage serialization OPEN. Current evidence ember-savanna-species/;
  owners/gates — Terrain Authoring → «Саванна24». Shape0 rejected by user, retained.
  Savanna shape1 blockout: _savanna_umbrella_plan and shared recursion feed same
  Provider/Recipe supports; shape toggle rebuild gated24. Species.crown_blockout
  reuses existing Rounded implicit-volume union with inverse vertical scaling.
  SavannaShapeStudy keeps same Recipe/history, hides final-foliage tab; reference
  trees/light exact. Native callbacks/3 views+above/light matrix and5 regressions
  PASS, silhouette accepted as base; manual motion OPEN. Evidence
  ember-savanna-canopy/. SavannaLeafStudy continues that same Source with v3-small-
  patches atlas and opt-in Branching canopy_envelope placement inside branch-owned
  supports. Derived root.point is card anchor; root.attachment is actual shoot
  attachment. No Resource/schema owner change. SpeciesStudy.trial_card_options
  preserves placement in Recipe preview. Terminal t1 puffs now replace3 attempts
  with small flat fans along actual final shoot segment; derived tip_priority
  retains them first within the same density budget,0% still removes all.
  Support-envelope exception only for these tagged fans; Source/history/light exact.
  Native matrix/controls/Source/wood/collision exact; canopy/species/foliage21
  regressions after tip coverage,6 original patch regressions PASS; leaf art/
  motion/production transfer OPEN. Current evidence ember-savanna-tip-cover/;
  previous leaf placement preserved in ember-savanna-leaf-patches/.
  Spruce25 first silhouette: explicit25/tree4 only, existing Provider/BranchLayout
  plan/Recipe and same SpeciesStudy/RecipePanel owners. _spruce_plan has continuous
  leader, staggered whorls/twigs and branch-owned overlapping crown supports.
  Rounded.smooth_wood optional ellipsoid_radii reuses same extraction; default
  capsules and previous species frames unchanged. Species.crown_blockout(flatten0)
  consumes actual ellipsoid radii. Six shape controls; foliage tab hidden, no
  needle artwork or production appearance save. test/capture_spruce_shape owns
  Source/Recipe/preview/history/3 views/light matrix/reference guards; scalar branch
  text roundtrip tolerance1e-6, Source/collision/crown faces exact. Evidence
  ember-spruce-shape/; visual form/F6/motion OPEN. User then authorized needle trial
  while explicitly questioning protrusions; shape is not accepted. Species.
  spruce_needles/compact_tree_spruce_needles_study reuse same controller and Source.
  Branching.crown_cards needle_sprays opt-in25 anchors drooping/tapered fans on real
  shoots, terminal priority in same global/local thinning. crown_card_sample
  optional start_card keeps default sample path unchanged. Own spruce_v1 needle
  atlas/provenance, existing spruce bark, shader/light intact;1032 full/617 at60%.
  Same Recipe options survive preview/discard and save/reopen reconstruction;
  appearance still transient LAB. test/capture_spruce_needles + generic controls
  own gates; reference frame tolerance max1 RGB8/≤8px, actual0–1px; other data guards
  strict. Evidence ember-spruce-needles/. Art/form/upper coverage/F6/motion OPEN.
  User rejected that needle/form trial; new spruce25 crown_shape1 routes to
  BranchLayout._spruce_bough_plan: paired laterals/fine hanging shoots,473 branches/
  552 segments/85 supports, Source4d4733cf…; previous shape0 dfd9f454… preserved.
  Provider.build_on_structure regenerates shape switch for25. Branching needle_boughs
  only25/shape1: real shoot anchors, smaller tips, basal+terminal priority in same
  thinning;2166 full/1328 at60%. Same atlas/bark/shaders/light. Species.spruce_limb
  selects actual primary subtree; leaves exact displayed subset, wood rebuilt as
  tubes from same supports. SpruceBoughStudy inherits NeedlesStudy, same Recipe/
  controls/history owners,7 shape controls; recipe dir spruce25-bough-lab. Native
  bough/whole-tree/matrix/controls and4 regressions PASS;15 protected SHA exact.
  User-requested density pass:12 tiers instead9 at same height,13 leader sites
  instead11; first bough/BranchLayout exact. cap12 only25/shape1; max hierarchy
  fits existing768-segment budget. Old9-tier Source007ce55b… preserved.
  Evidence ember-spruce-density/ (before: ember-spruce-bough/); final crown frames
  accepted as working base. Personal F6/motion OPEN; production appearance transfer
  implemented in the current painted-tree owner entry above.
  Evidence — ember-tree-rim-light/; contract/gates — Terrain Authoring.
  Earlier grass-light report game frames duplicated tree view; rim capture now
  restores gameplay transform/FOV explicitly and asserts distinct cameras.
  Approved response trial: existing toon/leaf include owns opt-in directional
  painted_leaf_shadow_strength(default1); same LIGHT_COLOR, alpha/casting and
  local-light attenuation. Foliage21Study sample stage2 alone owns transient
  slider; old sample stages/tree unchanged. Native default/before/return/zero-Sun/
  Omni frames exact, external shield confirms both received shadow kinds weaken;
  ground ROI exact for3×2×3 comparisons. Grain contrast reduced, strict noise gate
  still FAIL. Prior60% recommendation superseded by user's40% whole-tree trial
  above; no gameplay schema/geometry/common math or production transfer.
  Evidence/gates/contract —
  Terrain Authoring → «Исследование рисованной листвы».

  Artistic colour/height/voxel/editor gates — Terrain Authoring →
  «Гладкое дерево и нарисованная кора». Old blurry bark look rejected.
  Bark LAB: existing BarkPattern owns support coordinates and signed v2 stroke
  contour; old v1/v2 marks stay exact. LargeTree build output supplies transient
  lines/offset, no Resource/schema changes. BarkFixture derives one RGBA3D field
  from private Recipe/palette; private object_surface bark roles1–3, leaves legacy.
  Existing voxel toon shader opt-in include reuses shared parallax solver24,
  inward relief<=5.04mm, no DEPTH/geometry/collision changes. Instance materials
  share the field, retain individual local Sun. Production cache/editor transfer
  and artistic acceptance OPEN — Terrain Authoring → «Кора — первая LAB-проба».
  Readability LAB: compact_diorama_readability_study продолжает PaintedLightStudy
  на existing voxel Source fixture; Map floor owns terrain and tuft support.
  Existing Player/PartyFollowers/private ExploreState retain hero scale; Kai name
  only Unit.display_name (protagonist ID/save unchanged). Camera settings use
  FollowCamera with explicit height reset. Existing Prefab.prepare_resource creates
  private door/tree; conditional door scale uses existing shared visual/collider
  configure path. Quiet PNG include is opt-in in existing terrain shader, POM intact.
  Permanent reference owner — docs/art/references/allfiring/environments/README.md.
  Limits/manual choice — Terrain Authoring → «Читаемость диорамы — этап0а».
  Material looks LAB: compact_material_looks_study наследует принятый grass_field,
  PaintedLightStudy/tuft scatter и DepthStudy/POM. Existing terrain shader получает
  opt-in EMBER_MATERIAL_LOOK_STUDY + общий material_look_study include; А использует
  исходный shader, Б angular normal steps, В world-metric texel-centre lighting/
  colour + независимые intensity levels. Sample normals reuse existing fragment-
  to-light channel (Forward+≤32 varyings); PNG mip footprint прежний через textureGrad.
  Source/Pattern/schema/editor/geometry unchanged; limits/gates — Terrain Authoring,
  «Три подачи материала и света». Большой world foliage/low-poly не реализованы.
  Shape editor: optional TerrainPilotResource.surface_rules — root-owned sparse
  64×64 byte tiles, Source-space addresses. SurfaceRules leaf хранит codec/window/
  copy-on-write patches/rebase/validation; dense/sectioned schema1/2 прежние.
  SmoothSurface.FieldJob применяет Source rules к общим угловым высотам; пустой
  слой exact legacy. Source working_copy/Sections/window/extension/rebase/cache
  и Grove field/stale paths учитывают слой. GroundVoxel игнорирует его геометрию.
  CompactTerrainBrush shape_round/protect/clear копит private cells до end,
  один history action, cancel без writes; Projection.apply_surface_rules только
  local halo tiles. WorldEditor «Сгладить» разделяет common heights/smooth rules;
  existing session Save/Reopen/Discard/recovery, Source validation и styles owners.
  Guard32×32, ручная UX/F6/perf/weak-PC приёмка OPEN — Terrain Authoring.
  Стенка земли27.10: WorldEditor._pick_compact(paint) → Projection.pick_ground_top(surface_details)
  → CompactTerrainBrush.stamp_surface → TerrainPilotResource.side_overrides/write_side_overrides.
  Прежние column_material_overrides и paint locks, sparse before/after в одной истории; Projection
  apply_side_materials инвалидирует локальные tiles. SmoothSurface делит окрашенные наклонные
  triangles по высоте материала, field не меняет; layout.side_paint блокирует corner-only update.
  GeometryCache side-paint-2 — только окна с overrides. HoverGrid shader рисует side contour.
  Low-poly ввод остаётся по detailed source; точная привязка к faceted silhouette OPEN.
  Gates/границы — World Authoring → «Земля · резкий уступ и боковая покраска27.10».
  Shape LAB: compact_terrain_shape_study и ember_terrain_shape_fixture задают
  один обычный Source8×8м. SmoothSurface.controlled_field / FieldJob opt-in profile
  задаёт strength/radius_cells/passes, slope-aware edge weight и protected_regions
  с feather в world metres. Default field/source/schema/cache прежние, точное
  сравнение с frozen previous implementation PASS. Settings fixture-owned, не
  сериализуются в Terrain Resource; смена материала не меняет derived heights.
  Shape controller готовит все tiles перед общей публикацией через прежний
  Projection.apply_study_smooth_tile; Player pause при перестройке. MountainAnomaly
  prepare_morph_fields переиспользует прежний алгоритм после A/B, без второго Player.
  Shared mesh/collision/floor/pick/nav и старые half/voxel endpoints PASS;
  полный rebuild с morph targets около2–3с. Локальные Source rules/editor lifecycle
  продолжены выше; большой speed budget/визуальная приёмка OPEN — Terrain Authoring.
  LAB material depth: compact_material_depth_study + presentation subclass
  ember_material_depth_study.gd продолжают тот же Map/Source/Smooth/Player.
  SurfaceMaterials optional private_patterns overrides не пишут общие Resources.
  Общий texture_mapping core: текущие world metres/actual face normal; одна
  проекция и масштаб цвета/height. periodic_material_ids → png_lookup.a
  отключает half-tile blend только для готовых периодических пар; legacy прежний.
  Общий ember_material_parallax solver и ember_terrain_material_depth binding
  включаются factory по EMBER_TERRAIN_MATERIAL_DEPTH; обычный shader не пишет DEPTH.
  Выбранные кромки grass/soil и soil/stone — ember_material_transitions.gdshaderinc:
  существующие slots → общие веса цвета/света, grass coverage привязывает SurfaceMaterials.
  cartoon_grass теперь читает grass-painted-calm-v1 через прежний PNG bank; покрытие
  использует нормаль формы, painterly_blades сохраняют прежний свет. Новый вид OPEN;
  владельцы/ограничения — Terrain Authoring → «Спокойное травяное покрытие27.10».
  CUSTOM0/ref coords убраны: стыки/растяжение исправлены, including mid-morph.
  Generic factory API/depth slots поддерживают любую роль, не только stone.
  Направление объёма принято; своя оценка исправления и границы — Terrain Authoring.
  source schema/editor/cache и existing morph/physics owners не расширены.
  Height/coverage текстуры строятся один раз; camera input меняет только камеру.
  Source/geometry/physics/picking/nav/coords/Save/no frame jobs/native QA PASS,
  manual look/weak PC и +1мс close goal OPEN — Terrain Authoring.
  LAB0б: compact_painted_light_study / ember_painted_light_study наследуют depth
  стенд, используют новый6×6 Source и private painted_light_* Patterns. Общий
  terrain shader opt-in EMBER_PAINTERLY_STUDY включает ember_painterly_light leaf;
  обычные карты его не компилируют. POM/texture_mapping/physics owners прежние.
  Sun/Environment штатные scene nodes, F6 comparison toggles временные.
  LAB готовит stone-weighted field через Smooth.field(...,1), передаёт его в
  прежний Smooth.build(...,prepared_field)/apply_study_smooth_tile до morph.
  Default3 exact с прежним кодом; один field для mesh/collision/floor/nav.
  LAB grass_tuft_mesh + study MultiMesh: поле12×12м9621 clumps/423324tri, тот же
  ShaderMaterial/grass/light, POM off только на травинках. Bounded jittered patches
  внутри grass покрытия и у sand края, фиксированный seed, Source unchanged.
  compact_grass_field_study наследует painted LAB, новый Source192²; малый6×6 сохранён.
  Footprint9 excludes stone/steps; все vertices заранее проверяют base/half/voxel
  через общий Smooth.sample. Непригодные места исключаются один раз; ширина >=30%.
  Вертикальные корни следуют Map.floor при morph; размер/anchors не меняются.
  Этот способ опирается на текущую линейную смесь полей; новые зоны требуют пересчёта.
  No physics/ветер/мелкие cast shadows; native vertex clearance во всех фазах PASS.
  Цвет от ground Pattern, blade root/tip tint; T toggle, saved export.
  H/grass_masses — exported LAB flag: общее world-space поле нормалей/три тона
  для травы и земли, слабый root tint и up ambient на cards. Общий shader include,
  не новый renderer; no remesh/scatter. H-off exact прежнему полю, H return/native
  и exported Save/reopen PASS. Принцип для материалов — внешний Unified Looks Plan;
  собственный проход/мерцание и крутые склоны/стенки OPEN.
  Автору понравились световые мазки. J/grass_color — следующий exported LAB flag:
  близкие оттенки direct light по общему ember_painted_grass_steps, H-on only;
  отдельные цветовые clouds отвергнуты и удалены. Общий ground/cards, no ALBEDO/
  Source/Pattern writes, нормализация яркости direct light. Native J-off
  exact с принятыми мазками в прежней .52-пробе; shared flag/Save-reopen/no remesh PASS.
  Принятый low=.64; grass_light_* opt-in поля теперь у CompactTerrainPattern.
  MaterialPatternDialog использует прежний draft/Undo/Save, отдельные light controls
  и явный подбор; base/light/shadow artwork semantics прежние. Small preview
  сигнал WorldEditor→TerrainPilotProjection→SurfaceMaterials меняет только lookup,
  Cancel/variant switch восстанавливают baseline, Save обновляет shared Pattern.
  RGBAF grass_light_lookup256×4 и прежние slots/weights различают варианты;
  defaultdisabled сохраняет legacy. LAB ground/cards делят lookup, F6 — private
  copy сохранённого Pattern, root exports остаются совместимым study payload.
  Shadow fill по directional ATTENUATION, не
  расстояние внутрь кроны; no-shadow/zero-light exact native PASS. F6-панель временная,
  постоянный профиль в Pattern editor. Evening/Day/Night — общий EmberLights
  MATERIAL_LIGHT_PRESETS, native Sun/Environment и кнопки прежнего WorldLookPanel;
  atomic scene Undo/Save, ambient COLOR, камера/exposure/tonemap прежние.
  Перенос и связанные regressions/native matrix/два варианта/preview/Discard PASS;
  grass delta<=2/255 vs LAB. Варьирующие normal duplicates убраны в light()
  для Forward+ лимита32; bevel/POM/math владельцы прежние. Подробности/gates — Terrain Authoring.
  Production foliage authoring/LOD/три формы пучков не реализованы.
  Bevel LAB: compact_bevel_light_study наследует оригинальную сцену Sol +
  ember_bevel_light_study controller. EMBER_BEVEL_STUDY в общем terrain shader
  использует POM slopes/одну height sample через ember_bevel_light leaf для света
  на фасках; не меняет NORMAL/DEPTH/geometry. Выключен вне отдельной компиляции.
  Directional gain + self-shadow/ATTENUATION; thresholds пока для paired PNG Sol.
  Native A=Sol/GPU depth exact, Source/physics/Save PASS; manual/perf OPEN.
  Targeted/native PASS, плиты/grass light/back+lateral rim, ручная приёмка OPEN;
  локальный morph только внутри полного тайла. Детали — Terrain Authoring, LAB0б.
  independent_surface_enabled defaultfalse защищает старые baked materials;
  set_roles включает после upload. Roughness side selector отделён от color/height
  side flags. Shader normals/roughness/derivative fade не создают geometry/physics.
  Та же editor grid маршрутизирует color/relief/roughness, per-layer/face Undo,
  grayscale PNG и Save; channel transient. grass_impasto/soil_grain и
  ground_finish_study отдельные, legacy не мигрируются, geometry общей пробы точная.
  Результат, доказательства и manual gates — Terrain Authoring / материалы.
  Optional object_surface.optics v1 хранит прежние strength/clarity/body/IOR/
  thickness/cloud/colors и finish (legacy или ice_clean/ice_natural/crystal_clean/
  crystal_rough), surface roughness/detail, cloud blur/opacity, absorption,
  crack strength/scale/width и bubble strength/scale. Profiles — единый owner
  defaults/presets/validation; explicit fields перекрывают профиль; поля schema6 сохранены в schema7.
  HTML strings factory превращает в source_color. Rock provider назначает природные
  профили новым crystal/ice; прежние sources не переписываются, same-family regen
  сохраняет авторские параметры. Prefab.refractive_material хранит resolved source
  params/role в metadata, один shader без новых граней/surfaces/recollision.
  Signature object-optics-v3-reference-finishes добавляется только opt-in.
  Surface-optics leaf: view-space refraction/depth/Beer-Lambert, общий BRDF, static
  local field/seed. Cloud blur/opacity отделены от поверхности. Три ограниченных
  fracture sheets + jittered bubbles на двух фиксированных внутренних пробах,
  derivative AA, без TIME/texture/raymarch/Voronoi27. Watershader не меняется;
  отдельного viewport/камеры нет. Thickness — приближение, screen capture не
  содержит других прозрачных поверхностей. Base material compatibility сохраняет
  optical settings; несовместимые stamp/merge отклоняются до изменения source.
  ember_object_material_study.gd — scene-owned Inspector/light/uniform overrides,
  не второй renderer. Source params остаются исходной основой, mesh metadata
  сохраняет optical material при Save-off/Reopen/Enable. Профили и простой probe
  меняют material/uniform, не geometry/source/collision. Шесть baked примеров в
  scenes/object_material_study.tscn; neutral light, три presets + optional SSAO.
  effective_light выводит preset offset/scale из сохранённой дневной основы, без
  мутации manual controls. Runtime 1/2/3/Space/G/O/R/C/F сравнивает без записи.
  Gates/ограничения — Terrain Authoring / «Материалы и рабочий интерфейс».
  Правая панель `ember_world_look_panel.gd` внутри «Редактировать мир» меняет
  Sun и Environment сцены через Undo/Redo: силу и тон света, мягкость и
  включение тени, свет/тон окружения, экспозицию, контраст и насыщенность.
  Контраст/насыщенность включают штатные Environment adjustments. Значения
  сохраняются в `.tscn` и не попадают в terrain Resource.
  `palette_surface_roles` хранит смысловую роль, а необязательный
  `palette_material_ids` — имя варианта для того же слота. Старые карты без
  второго массива используют вариант с именем роли. Несколько слотов одной
  роли могут использовать разные рисунки рядом; смена рисунка обновляет атлас
  без remesh/recollision. Добавление слота перестраивает tile один раз.
  Именованные `content/terrain_materials/*.tres` хранят паттерн 16×16 как
  индексы трёх тонов, необязательный боковой `side_pixels`, сами непрозрачные
  тона и три параметра поверхности:
  глянец, силу блика и рельеф пикселей. У старых паттернов нулевые значения
  сохраняют матовый вид; атлас передаёт рельеф через alpha, отдельный lookup —
  глянец и блик. Пустой боковой массив сохраняет старое отображение; непустой
  должен содержать 256 индексов 0..2. Второй атлас 16×4096 передаёт боковой
  рисунок/высоту; зелёный канал role lookup отмечает отдельные бока. Vertex
  COLOR.a остаётся индексом палитры, geometry/physics не меняются. Для новых
  боковых рисунков normal строится в локальной плоскости грани и преобразуется
  в view space; заполнение бокового света использует геометрическую нормаль,
  не зависит от поворота камеры. Старые варианты сохраняют прежнюю отделку.
  Один общий паттерн меняет все карты, где он выбран.
  `ember_compact_material_pattern_dialog.gd` теперь VBoxContainer, хранит один
  draft/history/opened_path/hash и два UI controls. Plugin регистрирует grid
  в прежнем bottom-panel API, parameters_panel принадлежит прежнему правому dock;
  общий component освобождает history/parameters при shutdown. WorldEditor
  хранит transient material mode и weak map + slot/expected ID для назначения
  нового варианта; смена scene не переадресует этот слот. Dirty switch решается
  inline; сворачивание не равно Cancel, файл меняется только Save/новым вариантом.
  `EmberCompactTerrainPattern` валидирует их; `ember_voxel_surface_materials.gd`
  создаёт из них ImageTexture с nearest sampling. Редактор меняет черновик
  клеток/тонов через существующую сетку `ember_voxel_pattern_editor.gd`,
  локально отменяет и повторяет штрихи; явное сохранение записывает общий
  Resource и заменяет uniform открытой карты без remesh. PNG 16×16 можно
  экспортировать и импортировать через Aseprite при тех же трёх тонах; выбор
  верха/боков определяет адрес правки/PNG. Undo хранит адрес грани и возвращает
  пустой fallback; импорт сверяет реальные RGBA8-тона. Диалог освобождает свой
  UndoRedo при уничтожении. Новые `*_relief` — отдельные варианты пробной
  `compact_material_relief_study`, без миграции остальных карт.
  Закрытый без сохранения черновик не меняет файл. Старые bitmap в
  `assets/terrain_textures` остаются сравнительными арт-образцами.
  Рисунок привязан к координатам земли и зеркально повторяется.
  `ember_terrain_pilot_mesh.gd` строит плоский сухой tile одной верхней гранью,
  а на сложных tile объединяет равные верхние и водные площадки внутри tile
  в прямоугольники и пропускает проверку боковых стен их внутренних клеток.
  Детальные колонки и границы между tile не теряются.
  Для неоднородного tile из однородных квадратов 8×8 тот же построитель
  объединяет верх и воду по квадратам, а боковые грани строит широкими
  отрезками. Он проверяет исходные колонки и соседнюю полосу; детальная
  колонка, override материала или неоднородный стык возвращают прежний
  точный путь без изменения Resource. Профиль считает `grouped_8_tiles`.
  Collision по-прежнему
  использует треугольники той же сетки. Это ускоряет первое открытие ровных
  больших карт без изменения terrain Resource или editor/runtime owner.
  Пассивный `profile_snapshot()` в этой же проекции разделяет validation,
  copy, расчёт граней, создание Mesh Resource, узлы, visual и создание/подключение
  коллизии по времени основного потока; editor-only
  `ember_terrain_diagnostics.gd` снимает отдельные счётчики 3D viewport и
  сохраняет отчёт в `user://`. Профиль повторённого берега 4×4 показывает
  основной CPU-вклад mesh и collision. После объединения верхних площадок
  видимый автономный Forward+ профиль `tools/profile_compact_terrain_forward.gd`
  дал для повторённого берега 4×4 ~4,49 с до полной карты против ~5,80 с,
  984 видимых draw calls и ~0,58 мс GPU против ~1,24 мс готового кадра на
  RTX 5070. Проверка `tools/test_terrain_mesh_rectangles.gd` сопоставляет
  исходные ячейки с видимой землёй, боковыми стенами и водой до/после
  детальной правки.
  При живом компактном мазке запросы к уже ожидающему tile объединяются;
  повторная сборка того же tile ограничена 50 мс, а его последние данные и
  физическая форма обязательно достраиваются после редактирования. Первый
  запрос не задерживается. Счётчики `coalesced_tile_requests`,
  `deferred_repeat_builds`, `repeat_edit_builds` и `max_pending_age_us`
  позволяют сверить выигрыш и задержку в настоящей записи 3D-редактора.
  Нативный 3D viewport показал отдельное узкое место: во время открытия
  4×4 карты запросы `_get_configuration_warnings()` заново обходили все
  колонки после каждого добавления производных tile. `EmberMapLoader`
  пропускает этот повторный обход, пока уже проверенная проекция строит
  карту; для ошибочного Resource и после сборки предупреждения проверяются
  полностью. Повторное открытие в том же Forward+ редакторе изменилось
  с ~27,8 до ~0,75 с. Сцена с объектами и эффектами отдельно не измерена.
  После большого мазка Godot также запрашивал warnings уже при пустой очереди:
  живой кадр 369 мс содержал 362 мс полной validation 2,36 млн колонок.
  Для собственного компактного editor draft, проверенного при открытии и
  ограниченно меняемого кистью/Undo, этот повторный обход пропущен; Save и
  Resources вне активного editor draft по-прежнему проверяются. Ручная запись
  Forward+ после правки показала ноль таких вызовов и ноль кадров >100 мс;
  во время большого мазка остаются отдельные кадры до ~73 мс.
- `addons/ember_import/ember_world_edit_sessions.gd` — общие черновики
  сцены/Surface/объекта и единая транзакция Save. Периодический аварийный
  черновик сохраняет отдельную копию Resource через `WorkerThreadPool`,
  не читая живую карту из рабочего потока. При явном Save, смене сцены или
  выходе ожидает эту запись, затем пишет актуальный черновик. Формат
  manifest получает optional `compact_layout` для положения Map/групп и накопленного
  сдвига расширений. Discard выводит размер из baseline terrain и вычитает только
  этот сдвиг, не отменяя независимое движение групп. Save принимает текущую
  расстановку; recovery проверяет тип/конечность metadata до применения. Старый
  manifest читается, но без layout потерянный west/north shift не восстановить.
  `WorldEditor.commit_compact_extent_repair` — отдельная Undo-команда служебного
  размера для старых несовпадений; кнопка принадлежит прежнему extension dialog.
  Resource и manifest сначала пишутся во
  временные файлы и заменяются после успешной записи.
- `addons/ember_import/ember_voxel_object_session.gd` и
  `addons/ember_import/ember_voxel_model_store.gd` — подготовка независимого объекта,
  publication source/prefab и guarded baseline.
- `addons/ember_import/ember_editor_filesystem.gd` — общий editor-only adapter
  для filesystem refresh после публикации; он не владеет source data. `request_file`
  объединяет normalized res:// paths и вызывает native update_file только после
  quiet deadline, вне import/scan и weak scan leases. Полный/source scan имеет
  приоритет над адресными updates; callback requests не теряются. Text Resources
  игровых систем не запускают background scan всего проекта при каждом Save/Undo.

Перед добавлением нового editor owner сначала искать существующие Canvas,
generation, placement, publication и scene-authoring пути.

### Exploration, interactions и content

- Полётная проба27.10: `scenes/wing_flight_trial.tscn` — разрешённая автором отдельная
  небесная трасса. `ember_player.gd` сохраняет collision owner и включает transient
  `ember_wing_flight_motion.gd`; `ember_follow_camera.gd` полностью наследует ориентацию.
  `ember_wing_flight_trial.gd` ведёт ворота/паузу/повтор с private ExploreState без записи;
  общая карта, партия и бой к пробе не привязываются. Запуск/правила/ручной gate —
  GDD → «Полёт на крыльях»; targeted/Forward+ — Test Plan → «Полёт на крыльях27.10».
  Hoshi-режим: `ember_wing_flap_motion.gd` наследует прежнюю математику полёта и ведёт
  ход/прыжок/deploy/очередь boost/автовзмахи, ограничивает крен/тангаж через прежний
  motion hook; input/collision/ground support остаются у Player. Пробел/A → jump_pressed,
  RT/Ctrl → дискретный boost; обычный наземный player вне этого режима не менялся.
  `ember_hoshi_flight_visual.gd` — частная презентация с BoneAttachment, родными
  клипами основных суставов крыла, процедурным коконом/поджатием ног и пробным наклоном
  тела, без правки Hoshi source. Оборот presentation не попадает в physical orientation.
  StartPlatform принадлежит прежней .tscn, активен только в этом режиме; контакт опоры
  до вылета не считается аварией. Camera framing scale0.6 только для Хоши.
  Приватные ассеты/ограничение вспомогательных костей/запуск — тот же раздел GDD.
- `scripts/ember_explore_scene.gd` — общий scene play controller: player, party,
  UI и переходы. `world_canvas.gd` добавляет bootstrap/storage, но не второй gameplay owner.
  Старые города и Test Pier удалены; `test_exploration_mechanics.gd` использует общий
  controller и генерируемую fixture. Прикладные editor gates — через
  `run_remaining_editor_tests.py --mechanics-editor`; реальные карты туда не копируются.
- Inspector использует resolved native source owner: `.tres` показывает как
  Godot Resource, Asset tooltip направляет в мастерскую; legacy остаётся явно
  историческим источником до retirement. Snapshot read-only, native label gate
  проходит с недоступным pack path. Map/region validation ещё требует native среза.
- `scripts/ember_map_loader.gd` — загрузка карты и native Surface.
- `scripts/ember_interact.gd`, `scripts/ember_interact_rules.gd`,
  `scripts/ember_interaction_ui.gd` — scene-owned interactions.
  `ember_dialogue_session.gd` также владеет bounded transcript показанных строк/
  выбранных ответов; InteractionUi показывает его по H без продвижения/команд.
  История живёт в памяти UI, game save прежний. Прямой activate_dialogue и
  dialogue_closed(completed) используются отдельной постановочной пробой;
  она ждёт выбор и использует изолированный ExploreState, не реальный save.
  Owners/инструкция/проверки — Inspector Design I3.15 «Диалог и история29.10».
  Action play_cutscene/presentationId ждёт scene-owned presenter через тот же
  queue owner. Store/карточки/Graph поддерживают привязку; один leaf
  `ember_story_binding.gd` читает её в editor/runtime. Serial/disconnect защищают
  от позднего продолжения отменённого показа; внутренний Dialogue временно
  использует ту же Session/историю и ExploreState. Первая сборка — только
  camera_preset_study/harbor_cargo_story_trial; main camera/input/save OPEN — I3.15
  «Квест → сценка → награда29.10». Старый main reward Action не заменён.
  Создание сборки — `ember_story_authoring_dialog.gd` (pending UI) +
  `ember_story_authoring.gd` (builder/validation) → прежний InspectorActions
  create_story_scene/EditorUndoRedoManager и scene Save. Cue Resource хранит
  только time/Dialogue; Source refs/AnimationLibrary принадлежат `.tscn`.
  Runtime использует прежний presenter, несколько cues и Camera/input restore;
  authored nodes фиксируются до ready, без сериализации transient UI. Инструкция/
  ограничения/проверки — I3.15 «Создание сценки автором29.10».
  Общие talk/shop/action/launch/quest проверки теперь используют native fixtures
  через `tools/run_interaction_tests.py`, без city/story fixtures. Editor store
  writers в этих tests ограничены disposable проектом; production owners/schema
  не менялись в interaction cleanup. Native/source/save gates PASS; item/shop
  readers больше не требуют compatibility JSON, полный G4/G5 этим не закрыт.
- Quest purchase29.10: QuestCatalog numeric projection `progressMode=purchase`,
  purchaseShopId/purchaseItemId/requiredCount; ExploreState.buy передаёт успешную
  покупку в тот же economy commit до signals/autosave. Личный numeric flag,
  active/available gate, без event log/нового save owner. Economy stack_full
  отказывает без списания; InteractionUi показывает причину. Оба Quest editors
  используют `ember_quest_purchase_fields.gd` (catalog-only UI), Store валидирует
  ассортимент; Journal/Tracker показывают count. Owners/инструкция/QA/main gate —
  Inspector Design I3.15 «Цель «Купить»29.10»; проверка test_quest_purchase.gd.
- Quest handover29.10: Quest.progressMode=handover/handoverItemId/requiredCount;
  Catalog projection принимает inventory явно (Journal/Tracker), до сдачи count
  не сериализуется. Прежний quest-event compiler → Action handover_quest_items
  (questId/objectiveId/rewards); ExploreState.handover_quest_items проверяет active/
  available, обычный exchange фиксирует inventory и bool flag до observers/save.
  Разговоры компилируются прежними InspectorActions с одним Undo; item/count
  не копируются в costs. UsageIndex/маркер/Action card/Store/Graph поддерживают шаг,
  прямой authored true/done не обходит сдачу. Owners/gates/evidence — Inspector
  Design I3.15 «Цель «Собрать и передать»29.10», test_quest_handover.gd.
- Mechanism circuits29.10: `ember_mechanism_graph.gd` — pure DAG/boolean validation;
  `ember_mechanism_circuit.gd` — единственный runtime маршрутизации; typed child
  `ember_mechanism_component.gd` — sensing/effectors. Источники plate/lever, логика
  all/any/not, door/lamp. `.tscn` хранит circuit_id/links и components с NodePath;
  graph_position metadata не gameplay Resource. Lever flags в ExploreState, позиции/
  находки в прежних world_items; outputs/pressed не дублируются в save.
  `ember_mechanism_lever_interact.gd` использует прежний F. World containment —
  одна leaf-проверка с QuestObjectZone. `ember_mechanism_workspace.gd` — native
  GraphEdit Window, InspectorActions — единственный scene writer/history. Basic/
  workshop builder общий; старый ember_pressure_gate — compatibility envelope к
  Circuit, первая edit-команда переводит script/children одним Undo. Прежнего
  отдельного контроллера двери нет. Native EUM/Undo/save/reopen/discard/conversion,
  physics/save и live Forward+ PASS, exit0; свой UX/main/streaming OPEN. Owners/
  `ember_mechanism_world_wires.gd` добавляет editor-only overlay/input в обычном3D
  viewport: тот же snapshot/InspectorActions, без scene nodes/новой сериализации.
  Plugin маршрутизирует режим до кистей; свойства выбирают компонент в прежнем окне.
  Роль обычному объекту: InspectorActions.assign_mechanism_role + контекстные плитки;
  новый Circuit без builder либо компонент существующего, один Undo на назначение.
  Binding scope — authored scene (Circuit.binding_scene), NodePath к соседним веткам;
  предметы не переподчиняются/не меняют script. Валидация запрещает второй target owner
  между circuits и чужую сцену/вложенный набор. Прямое назначение всех4 ролей;
  door/plate создают authored helpers через ember_mechanism_role_geometry (mesh AABB,
  тело/BoxShape/Area). Исходный prop не переподчиняется, helper refs проходят тот же
  Undo/replace; снятие роли убирает helper и возвращает старые StaticBody shapes.
  Runtime component удерживает clearance в закрытом проходе; пустой plate.crate_path
  означает character/спокойный rigid вес, конкретный crate — прежний строгий Rules.
  Автозоны/физический луч/занятый проход/снятие/Undo/reopen Forward+ и native EUM PASS;
  точность AABB/мышь/main/streaming OPEN. Targeted runtime F→lamp,
  hierarchy/Undo/save/reopen/discard и native role UI PASS; streaming/main OPEN.
  Projection/input/native Forward+ overlay/EUM/save/reopen/discard PASS; ручной input/
  split-view/main OPEN. Инструкция/evidence — Inspector Design I3.15
  «Конструктор механизмов29.10»/«3D-провода29.10»/«Роли обычных объектов29.10».
  Hold29.10: Component.kind=hold/hold_seconds (default3,0.05–120),1in/1out;
  Model.advance чисто возвращает values/timers, Circuit владеет transient
  timer_remaining и обновляет его в том же physics step. Snapshot/form/.tscn
  сохраняют только длительность; rebuild сбрасывает countdown, layout — нет.
  Ретриггер обновляет duration; disconnected input очищает. Пауза следует физике.
  Targeted duration/runtime/pause/Undo/reopen и native Graph/EUM PASS; автор/main OPEN.
  Owner — Inspector Design I3.15 «Задержка выключения29.10».
  Latch29.10: Component.kind=latch,2in Включить/Сброс, reset priority. Model.advance
  возвращает чистую проекцию latches; Circuit берёт bool из ExploreState.flags,
  mechanism_latch_<circuit_id>_<component_id> и публикует изменения set_flags_batch.
  Batch целиком валидируется до мутации, один observer/autosave на cascade step,
  никаких записей на неизменных кадрах. Circuit не шагает при pending spawn restore.
  Runtime cascade/save/reload/reset/pending guard + native Graph/EUM/reopen +
  party_save_v2 PASS; автор/main OPEN — I3.15 «Фиксация сигнала29.10».
  WorldWires.logic_requested→Inspector→Workspace.add_logic создаёт узел+входящий
  провод одной Actions-командой, затем continue_from ведёт выход. Пустой щелчок
  во время провода открывает ограниченный PopupMenu; popup_hide cleanup deferred,
  поскольку движок скрывает меню до id_pressed. Source/scene/mode guards обязательны.
  Optional snapshot.world_position ↔ component metadata mechanism_world_position:
  circuit-local Vector3, finite validation, только authoring. Metadata-only Actions
  не rebuild; source .tscn/Undo/property edits сохраняют размещение. Native menu
  key/3D gesture/продолжение/EUM/save/reopen/discard PASS, native-wire-add-*.png.
  WorldWires drag: pending weak Circuit/id, проекция camera-depth + delta, override
  только overlay до release; _finish_drag пишет snapshot.world_position прежними
  Actions. Metadata-only сохраняет Component identity/countdown. Click/Esc/scene/
  mode/внешний scene_binding_changed сбрасывают pending без записи. Explicit logical
  anchors проецируются непрерывно вместо автоматической сетки экранных слотов.
  Feedback кешируется по source/document через Model.errors, hover красного входа
  рисует ограниченную подсказку; backend остаётся одним. Gesture press/release не
  протекает в native selection при scene_binding_changed. Targeted и native EUM/
  Forward+ PASS, native-wire-drag-preview.png/native-wire-port-feedback.png.
  Mechanism UI29.10: выбран authoring flow «3D+боковая панель». Новый
  ember_mechanism_inspector переиспользует Control свойств Workspace и прежние
  InspectorActions; второго property writer/schema нет. Plugin владеет EditorDock,
  WorldWires — одним toolbar toggle/компактными портами/режимом без кистей при ports off.
  На scene switch панель возвращает picker WorldWires, затем освобождает свой UI;
  свойства old graph не копируются. Primary roles/logic menu/wires/Undo/source reopen/
  rebind/toggle-state и native EditorDock/EUM/save/discard PASS. 1280 проверен для
  самих controls в preview; полная host-компоновка/мышь/main OPEN. Исследование/инструкция
  и evidence — Inspector Design I3.15 «Интерфейс механизмов29.10».
- `scripts/ember_region.gd` — chest prompt/activate и производный ChestVisual;
  opened keys/inventory сохраняет общий ExploreState. Общий ExploreScene вызывает
  `MapLoader.refresh_region_runtime`: только native bindings/visuals всех Regions,
  включая вложенные; JSON никогда не дополняет их saved свойства при startup.
  ExploreScene не вызывает load_map для пустой сцены; footprint использует saved
  extent/import stats, ZERO при десериализации не запускает JSON lookup. Явный
  старый load_map helper сохранён для tools; editor reimport UI удалён. Старые
  hydration flags не меняют runtime behavior.
  `refresh_cutaway_runtime` связывает saved Cutaways volumes, включая вложенные,
  не создаёт roofs из JSON и не удаляет authored nodes. EmberCutawayVolume на
  _ready восстанавливает transient Roof reference; repeated binding idempotent,
  reveal/fade/transparency/structural shadow прежние. Saved/reopen и four negative
  controls PASS; ручной Forward+ остаётся OPEN.
  Сохранённый progress выбирает open visual при reload, serialized closed visual
  заменяется, reused model учитывает block size. Headless gate PASS; Forward+ OPEN.
- `EmberActionCatalog`/`EmberActionResource` и `EmberDialogueCatalog`/
  `EmberDialogueResource` — native-only story documents. Runtime executor
  `ember_action_script.gd` и `EmberDialogueSession` прежние; graph/step schema
  не менялись. IDs/owner/read, Store write/delete и snapshot/restore работают
  только с .tres/remap. JSON read/write/delete/restore и migration UI удалены.
  `run_story_tests.py`: guarded create/edit/delete/Undo, simple dialogue cards,
  scene/action/quest binding/clone/orphan и binary PCK PASS. Snapshot ID/native,
  old legacy snapshot fields игнорируются без записи. Остались 2 combat actions/
  2 dialogues; две unused цепочки sbx_bush_se_actions/_2 с retired map targets
  побайтно архивированы и выведены из активного каталога. Report отвязан от
  исторических VoxelBatches. Static incoming reference scan, фактическая загрузка
  2 native combat actions и editor/save regressions PASS. 11 city-only tools/tests
  с UID и offline batch definitions выведены в checked supplemental ZIP.
  run_mixed_editor_tests.py: 10 Inspector/Graph/picker/scene/sculpt/physics gates
  используют guarded synthetic native scenes/models/story/VN; Undo/Redo,
  source SHA, save/reopen, branch ports/clipboard, actors/cache и routes PASS.
  General assertions сохранены; selector/physics ожидают нынешний native-only
  контракт. Остальные perf/shapes/diorama/prefab/Python теперь используют
  те же guarded native owners: 15 mixed gates + Python static PASS. Large
  profile сохраняет 24x24/16/32, dry/wet и object context; CPU PASS, длинные
  visible A/B OPEN. Actual disposable Forward+ shape editor create/paint/grow/
  save/reopen/callback/unload PASS; native diorama pixel safety PASS. Prefab
  UID/cache/transparency/placement invariants PASS. Python VOX input генерируется,
  Native VoxParser/VoxMesher/import Resource parity PASS; historical assertions
  archived. Семь old scenes выведены после refreshed archive SHA/CRC
  (998 files); остальные 704 author data files неизменны. Metadata/models/
  prefab/materials сохранены, shared barrel/crate_stack нужны Причалу. Static
  restoration guard + startup/editor/save/transition regressions PASS. Exclusive
  ресурсы сверить отдельно; author F5/Load и полный physical G4/G5 OPEN.
- `EmberVnAssets` — один native-only background/portrait resolver; descriptors
  content/vn_backgrounds и content/vn_portraits, images assets/vn_*. JOI registry
  reads и relative pack paths удалены. res:// сохраняется для PCK, metadata reload
  игнорирует stale Resource cache. CPU image bytes и imported Texture2D remaps
  используют прежний preview owner; render layers/draft Undo/schema не менялись.
  run_vn_asset_tests.py: guarded import/reopen, unique IDs, picker/missing IDs,
  poison/missing JOI, binary descriptors + imported-texture PCK PASS. Два фона
  сохранены, native portraits пусты; historical art не импортировался.
  Ручные VN/Graph image/input, Undo/Redo и Ctrl+S/reopen gates остаются OPEN.
- `scripts/ember_quest_resource.gd` — quest data.
- `scripts/ember_item_catalog.gd` — единый native-only resolver предметов/иконок;
  `EmberItemResource` в content/items и `EmberItemIconResource` в content/item_icons
  сохраняют исходные Dictionaries. Семь current items/шесть icons, без чтения
  items/catalog.json. Missing IDs дают empty, native/remap Resources работают
  и в PCK. ItemVisuals остаётся единственной pixel projection. ItemStore/editor/
  Inspector сохраняют validation/Undo/Redo; legacy migration route удалён.
  `run_item_resource_test.py`: editor/runtime, poison/missing JSON и binary PCK PASS.
- `scripts/ember_shop_catalog.gd`/`EmberShopResource` — native-only shop data и
  resolver; definition/IDs/owner не читают shops/catalog.json. Resource/remap
  lookup работает в binary PCK. ShopStore/ShopEditor/Inspector сохраняют validation,
  create/edit/discard/Undo/Redo; obsolete migration route удалён.
  `run_shop_tests.py`: neutral shop fixtures, цены/stock/buy/sell/save и PCK PASS.
  Listing/save schema и Economy/ExploreState не менялись; persisted stock даже
  retired shop IDs сохраняется. Village_kiosk/sandbox_notice_quest и 9 city-only
  action Resources выведены в checked archive, вместе с двумя retired Surfaces.
  Native actual-catalog/save gate PASS: flags/stock/unknown items не теряются,
  retired quest/shop не отображаются, current battle queue и shared models прежние.
  Graph lifecycle gate использует neutral fixtures; frame/focus/orphan checks PASS.
  Старый sandbox dialogue остаётся referenced текущим combat start; не удалялся. Вывод данных — JOI Exit Plan; ручной Forward+ OPEN.
- `addons/ember_import/ember_graph_workspace.gd` — общий content-authoring workspace;
  специализированные панели не получают собственный runtime state.

### Party, save и переход в бой

- Квестовые действия05.11: прежние QuestStore/Graph/QuestEditor/QuestCatalog принимают
  `world_action` (destroy/reveal_leaves/cut_grass/collect/craft + target/count).
  WorldItem/LeafPile/CuttableGrass/BerryBush/recipe commit → ExploreState → прежние
  numeric flags и единый autosave. Два общих файла описаний/селекторов не исполняют
  прогресс; второй bus/save-owner не вводился. UI/границы/команды — Inspector I3.15
  «Действия в мире как цели05.11». Ручное авторство своего задания/main OPEN.
- Груз между картами05.11: MapTransition process-local IDs→ExploreState.adopt_carried_items→
  ExploreScene restore той же записи/героя. WorldItems v2 optional physical/carrierHeroId
  нормализует переносимые WorldItem свойства, без второго save-owner. Дефолтные старые
  записи совместимы; чужая mapId не даёт старому prefab перезаписать/дублировать груз.
  WorldItem берёт родительский map_id до регистрации; F у доступной двери входит,
  иначе ставит. Tab перепривязывает тело к тому же hero_id; возврат — к входу новой карты.
  WorldRecovery deferred-ID guards устраняют регистрацию удалённого body.
  Fresh native cargo/профиль/save/Tab/norespawn, physical/world-item/map/combat/recovery
  regressions PASS; manual input OPEN. Owners/ограничения — Inspector I3.15 «Перенос груза между картами05.11».
- Рецепты05.11: authored `EmberCraftRecipeResource` + `ember_crafting_station.gd`
  EmberInteract adapter, общая InteractionUi MODE_CRAFT. State.preview_exchange —
  прежний расчёт обмена без мутации; exchange_items/craft_recipe остаются единственным
  commit/autosave. Учебные workbench/kitchen подключены в chapter1_estate/home;
  recipe/станция редактируются native Inspector, save schema неизменна.
  Границы/проверки — Inspector I3.15 «Верстак и кухня05.11»; manual input/DPI OPEN.
- Макет главы05.11:13native `scenes/chapter1_*.tscn` через существующий `world_canvas.gd`,
  общий отдельный `sandbox_storage_root=user://ember-chapter1-blockout`; main save не заменён.
  Builders/ресурсы/границы — Inspector I3.15 «Проходимый макет локаций05.11».
  `EmberMapLoader._region_nodes` ищет Regions→Props рекурсивно и без повторов, чтобы
  объектные Door/return_* и свободные Region имели единый поиск/occupancy. Входы/NPC
  движутся со своей группой; defaultentry новых карт первый. Схема save не менялась.
  Native route/movedbuilding/NPC/shop/coldload и старый maptransition PASS; ручной проход OPEN.
- `scripts/ember_explore_state.gd` — единственный mutable/save owner мира,
  партии, общей сумки, флагов и прогресса.
- `scripts/ember_party_state.gd` — чистая нормализация, derived stats, XP/level-up;
  самостоятельно ничего не сохраняет.
- Inventory/equipment, health/consumables, party followers и defeat/respawn gates
  запускаются через `tools/run_party_tests.py`: saved native карта, current native
  consumables и synthetic equipment в guarded disposable проекте. Старые города/
  предметы/модели не нужны; реальные State/UI/Player/Followers owners и save v2
  сохранены. Item/save schema не менялась; item compatibility JSON больше не нужен.
  Party/save v2 также включён в runner на neutral equipment. Headless/negative
  controls PASS, ручной Forward+ OPEN.
- `scripts/ember_combat_transition.gd` — guarded world → combat → world transaction.

Save v2:
- `EmberMapTransition.saved_destination` владеет маршрутом retired/missing saves
  к landscape_compact. `_saved_spawn_at_entry` — только session flag существующего
  ExploreState; consume возвращает null, и ExploreScene использует native вход.
  Старые XYZ не переносятся, native saved XYZ сохраняются. V1 сначала конвертируется
  с исходной локацией, затем разрешается в памяти; source/backup не переписываются.
  Menu валидирует сцену в detached State, принимает прогресс до удаления уходящей
  сцены и откатывает его при ошибке перехода. Native save destination QA PASS;
  Forward+ F5/Save/Load OPEN. Формат save не менялся.
- три ручных слота + отдельный autosave;
- `has_pending_spawn_restore()` читает существующий load/restore flag без новой
  schema/state. Пока новый player не потребил loaded spawn, уходящий ExploreScene
  не делает exit autosave: иначе прежняя позиция затирала pending restore/autosave.
  Обычный departure без pending restore сохраняется как прежде. Native pause-menu
  same-map reload/cross-map load gate PASS; ручной Forward+ остаётся OPEN;
- JSON сначала полностью пишется/проверяется в соседнем временном файле;
  прежний слот остаётся в `.previous` до публикации нового. Ошибка не обновляет
  remembered progress и не посылает `saved`; при неудачном rollback копия остаётся
  для восстановления при load/metadata. Это recoverable replace, не обещание
  атомарного Windows rename или защиты от отключения питания;
- сохраняет persistent данные всех четырёх героев;
- derived stats пересчитываются; неизвестная retired saved экипировка возвращается
  в сумку без применения выдуманного stackMax=99. Её ID/count сохраняются при
  повторном load/save, но retired item не получает активной definition. V1 с
  явным valid maxHp не читает stage JSON, HP ratio сохраняется; schema не менялась;
- Layout экипировки теперь weapon/armor/shoes/accessory1/accessory2 в прежнем
  envelope v2. Единственный import_saved у EmberEquipment переводит body/accessory;
  head/arena_weapon/unknown slots возвращаются в сумку через Party normalize и
  Explore owner без stack truncation. Повторная нормализация не выдаёт вещи снова.
  Load не пишет source; перед explicit Save старого layout сохраняется exact
  equipment_migration_backups/<filename>-<SHA>.json. Неудачная/повреждённая копия
  блокирует перезапись исходника. Архивы не участвуют в automatic recovery/delete.
- миграция старого save сначала создаёт recovery backup;
- удаление save также оставляет recovery-копию.
- удаление охватывает остаточную `.previous`, чтобы слот не восстановился снова.

Активный состав 1–4 хранится через существующий Explore/save owner,
а не отдельную party-систему. Battle получает process-local копии и возвращает
результат через существующую transition boundary.

### Combat

- `scripts/prototypes/ember_combat_prototype.gd` — единственный pure resolver,
  preview/commit и stale-result guard.
- `scripts/prototypes/ember_combat_status_rules.gd`,
  `scripts/prototypes/ember_combat_damage_rules.gd` и
  `scripts/prototypes/ember_combat_effect_rules.gd` — stateless leaf rules,
  не отдельные resolvers.
- `scripts/prototypes/ember_combat_state_schema.gd` — validation snapshot/result.
- `scripts/prototypes/ember_combat_terrain.gd` — height, distance, LOS и terrain reactions.
- `scripts/prototypes/ember_combat_grid.gd` — dense Battlefield navigation, reachable/path,
  staged movement и positional planning.
- `scripts/prototypes/ember_combat_lab.gd` — command/targeting/HUD controller.
- 3D/grid view classes — projection и animation, не gameplay owners.
- Action/Effect/Status/Unit/Battlefield/Encounter Resources —
  authoring contracts в `content/combat/`.

## Текущее состояние editor и world authoring

### Общие игровые системы · единая библиотека, draft и общие операции

- `ember_game_systems_catalog.gd` — editor-only read projection существующих
  item/combat catalogs и Battlefield Resources; не новый runtime catalog/schema.
  `saved_record` и `incoming_links(..., Store.SPECS)` читают exact native paths
  с CACHE_MODE_IGNORE, не меняя dirty source/cache. Saved consumers индексируются
  по пути, одинаковые ID/имена не схлопываются. Семантические relations и legacy
  static dependency/quoted-ID scan объединены в одну строку на файл; confirmed
  direct/file refs отличаются от candidate text matches. Item's reverse loot
  relations не считаются incoming consumers. Scan только по explicit Open/Refresh,
  фильтр работает локально. Старый conservative `incoming` для Delete не менялся.
- `ember_game_systems_usage_panel.gd` — bounded read-only native Tree/search/detail,
  double-click/Open, FileSystem и Refresh. Metadata — module/id/path/saved SHA,
  не сериализуется в gameplay data. Workspace проверяет SHA/exists/type/ID перед
  переходом; stale/deleted rows требуют Refresh, dirty draft остаётся открытым.
  `select_module(..., preferred_path)` + `_selected_path` выбирают exact record
  даже при duplicate ID/filename mismatch, не обнуляют чужой dirty cache. Деталь
  читает saved record, последующий draft остаётся под прежними live-source/path
  guards. Side list selection/dirty Cancel/pending navigation сохраняют path.
  Back возвращает исходную запись/category/search, переход прокручивает выбранную
  строку и верх карточки. FileSystem route сохраняет library/draft и закрывает
  popup. Publication даёт явный stale feedback, без automatic project rescan.
- `ember_game_systems_workspace.gd` — общий browser/search/detail/links/commands.
  Один раздел item с фильтрами; route equipment — alias item + equipment filter,
  не второй экран/каталог. Create учитывает тип фильтра, Save сменившего тип
  предмета снимает несовпадающий фильтр. Dirty filter guard сохранён. В draft
  список скрыт, «К библиотеке» возвращает список/фильтры. Отсутствующая связь не открывает
  другую запись; пустой поиск очищает actionable selection.
- Узкое окно/125% общей библиотеки: Workspace._fit_library_layout читает
  доступный parent/main-screen размер, заменяет боковую навигацию compact picker
  с прежним select_module/dirty guard; check button reparented, не дублирован.
  SplitContainer может складывать library/detail по вертикали; header и draft
  toolbar — HFlowContainer, publication/session прежние. Create без auto wrap
  Window (прежний popup вырос до500×2229); delete/dirty dialog wrap text при
  bounded Window (прежний long-name delete был шире1280). Runtime Lab._fit_hud_layout
  на resize/min-size/refresh уменьшает боковые панели, давая ширину ability info,
  подгоняет header/min-size консоли/footer без потери console input и Reset/Menu.
  Timeline — прежние восемь entries в ScrollContainer. Headers имеют tooltips,
  outcome остаётся в прежнем Result owner. Никакой gameplay/save/schema логики
  этот layout не меняет. Native --ui-layout: actual EditorInterface scale1.25 в
  отдельном APPDATA, окно1280×800→1600×900, формы/диалоги/сложные условия/Save/
  reopen/Undo/Redo/dirty Cancel; game content_scale_factor1.25 с шестью conditional
  steps, hover/scroll/Cancel/MP/turn PASS. Исходные author data frozen; настройки
  пользователя не меняются. Captures/evidence — Migration Plan; свои input,
  другие DPI/размеры и игровое ощущение OPEN.
  Исходный QA exit0xC0000005 сохранён в Temp/ember-ui-layout-editor-exit-failure.log.
  Повторная диагностика cold/warm/fast exit/scan/preview и 24 publication cycles
  под Windows debugger не воспроизвела исходный AV; причина остаётся OPEN.
  `run_game_systems_tests.execute` сохраняет при native AV/heap corruption/fast-fail
  собственный sandbox вместе с cache, журналом и replay.json в Temp/ember-native-crash-*.
  Пользовательский APPDATA и посторонний environment не копируются; отдельный
  sandbox APPDATA сохраняется с переназначением пути. Fatal verdict остаётся FAIL.
  `test_game_systems_crash_capture.py` проверяет сохранность состояния и author
  guards; synthetic exit не считается воспроизведением Godot bug. Исключённый
  probe/точные ограничения и evidence — Migration Plan → повторная диагностика.
  Первое действие при новом AV: строка NATIVE CRASH EVIDENCE → сохранённые
  sandbox/cache/log/launch/replay → точное воспроизведение в копии. Успешные повторы
  не объявлять исправлением исходного native вылета.
  29.10: новый editor-exit0xC0000005 после PASS picker сценки в отдельном
  sandbox; повтор exit0, причина не установлена, production fix не заявлен.
  NATIVE CRASH EVIDENCE — `C:/Users/novos/Documents/Codex/2026-10-29/quest-presentation/native-crash-evidence.json`:
  launch/сохранённый fixture/cache, editor-shutdown-av.log, probe-shutdown-av.gd
  и успешный editor.log. Нельзя считать первый native процесс чистым PASS.
- `ember_game_systems_session.gd` — один detached draft, local field Undo/Redo,
  validation, file SHA/live source conflict и stable ID guard. Publication/Delete
  snapshots фиксируются в EditorUndoRedoManager GLOBAL_HISTORY: контекст именно
  RefCounted, а не built-in Resource, чтобы история не привязалась к сцене.
- `ember_game_systems_store.gd` — publication adapter к существующим typed
  Resources/ItemStore; не runtime owner/schema. clone использует Godot
  duplicate_deep(INTERNAL): встроенные rows/arrays независимы, external refs общие.
  Save сохраняет UID, Undo/Redo восстанавливают точные bytes; CACHE_MODE_REPLACE
  обновляет published resource, catalog refresh — derived lookup. `_sync` передаёт
  изменённый path общей Filesystem.request_file; `_on_published` обновляет только
  UI/catalog, без дополнительного full scan. Native ResourceSaver также вызывает
  EditorFileSystem.update_file. Delete сохраняет
  backup в user://ember-editor-resource-backups и проверяет прямые refs/quoted IDs.
- `ember_game_systems_draft_editor.gd` — нативные controls по существующей metadata;
  предметы используют публичный setup_document/document_changed прежнего
  EmberItemEditor. SpinBox подключается один раз без его внутреннего LineEdit.
  Toolbar закреплён сверху. Клетки/
  размеры поля сохраняются и редактируются прежним painter, не сырым новым UI.
  Status/effect формы показывают behavior summary; восемь operation-specific
  групп скрывают неактивные поля без потери значений. Status ID — native picker,
  remove/spread IDs — checklists, включая сохранённые отсутствующие IDs.
  Action form показывает `EmberCombatActionResource.behavior_summary` и русские
  параметры; lift/force/duo fields скрыты лишь когда не нужны и имеют neutral
  значения. Сохранённые несовместимые значения доступны для correction, validation
  прежняя. `requirements_text` — информационная строка, не script/condition owner.
  Effect steps — ordered shared Resource refs с descriptions и duplicate guard.
  `_effect_picker` в том же DraftEditor добавляет LineEdit search + OptionButton
  + read-only behavior preview до Add. Один snapshot Catalog.entries на форму;
  ввод фильтрует имя/ID/description/behavior summary без чтения файлов и публикации.
  Selection metadata остаётся исходным Resource, preview tooltip — точный path.
  Used IDs отключены, no matches/all used дают объяснение и disabled Add.
  `_effect_query/_effect_selected_path` живут только у формы; filter/selection
  не пишутся в Resource и не создают Undo, filter сохраняется при rebuild.
  Add/Remove/reorder/Undo/Redo/Save по-прежнему принадлежат прежней session.
  Native focused effect-picker + --actions/--effect-conditions PASS; UI просмотрен,
  user input/narrow/125% OPEN; evidence — Migration Plan.
  Unit action_ids — ordered named picker, missing IDs доступны для удаления.
  Old queued form игнорирует session.changed чужого draft; publisher/Undo owners
  прежние. Общие формы сохраняют authored loadouts; отдельное расширение Action
  status predicates и его schema описано ниже.
  Unit/AI/Loot/Encounter формы и карточки читают behavior_summary существующих
  Resources. ИИ задаётся stable ID; loot/field/arena — прежними shared refs.
  Каталожные pickers сохраняют текущие external/inline refs и missing IDs;
  continuation picker использует прежние native action-script IDs.
  Один ordered ID list ведёт action assignment и rosters; сторона фильтруется
  только в предложениях, сохранённое не удаляется молча. Повторы героев/action
  assignment запрещены; enemy_unit_ids допускает повтор одного шаблона.
  Points/order принадлежат Encounter/Battlefield.
  Loot rows: item picker + chance/min/max SpinBox, copy-on-edit внутренней строки;
  numeric history объединяется по row/key, не затрагивая shared table source.
  Encounter validation допускает только два существующих outcome enums.
  Unit/AI/result/save owners и распределение XP/loot не менялись.
- Условия отдельных эффектов: `EmberCombatEffectResource` хранит два optional
  PackedStringArray `target_required_status_ids/target_forbidden_status_ids`,
  empty defaults; definition проецирует `targetRequiredStatusIds/targetForbiddenStatusIds`.
  Validation блокирует missing/duplicate/contradictory IDs и пробелы, а также
  MOVE_ACTOR с target predicates (его destination обязан быть пустым).
  Signature/clone/Save используют прежний Resource/session/store. Common form —
  именованные status checklists, включая исправление сохранённого missing ID;
  операция не уничтожает условия. Catalog relations/incoming и saved checker
  учитывают новые refs. Единственный `EffectRules.target_condition_reason` читает
  исходный target snapshot; target_conditions_met использует тот же predicate
  с дешёвым failure sentinel без lookup имён. apply_authored_effects не проверяет
  resolved patches. `conditional_intent` форматирует только conditional rows:
  success либо первая missing/forbidden/empty-subject причина с StatusRules name.
  Никаких вызовов preview или чтения rolls/damage/outcome в этом пути нет.
  `Combat.describe_intent` ставит блок перед общими деталями, выбирает SELF actor
  и CELL occupant из selection snapshot; unset target приглашает выбрать цель.
  Lab._on_grid_cell_hovered обновляет видимый ability info тем же intent, сохраняя
  прежнюю public field projection; обновление не коммитит бой. Срабатывание
  оговорено попаданием/устойчивостью. Targeted 64 seeds с hit/miss дают одинаковый
  текст и не мутируют state; native A/B/empty hover/Cancel + прежний HUD gate и
  15 combat/save regressions PASS. Native preview просмотрен при 1600×900;
  свой ввод/длинные цепочки/narrow/125% OPEN. Evidence — Migration Plan.
  SELF/CELL semantics и границы — GDD → этап 3.5. Inactive steps пропускаются с
  объяснением в notes, не меняют свой reaction/footprint и не блокируют цель
  неактивным heal. Pure chain без активного шага/базового эффекта исключает цель;
  существующий fire focus bonus остаётся источником базового урона. Условия
  не меняют порядок самих операций цепочки или старые presets/status roles.
  Eligible/valid targets → Grid/ИИ/HUD и preview/commit используют те же правила;
  `effectConditionsHash` и StateSchema защищают commit от stale/malformed условий.
  Save schema прежняя, authored content не перенастроен. Targeted --effect-conditions,
  related conditions/groups/operations/usage/check/15 regressions и native --cycle
  PASS; форма и боевой экран просмотрены. Свои сочетания/input/narrow/125%/баланс
  OPEN. Evidence — Migration Plan.
- Повторные враги: `EmberEncounterResource.enemy_instances()` — единственная
  проекция ordered enemy_unit_ids в локальные runtime IDs. Первый сохраняет
  template ID; последующие получают __instance_N с обходом всех authored IDs
  участников и уже выданных aliases. Это runtime identity, не новые Unit Resources
  и не второй roster owner. initial_state делает deep copy каждого definition,
  задаёт id/cell, у aliased врага optional templateId. Только при повторе name
  получает префикс №ordinal, видимый в узкой очереди/targeting/3D. Unique encounters
  сохраняют прежние IDs/definition fields. PackedStringArray serializer, signature
  и Save schema прежние; missing/wrong-team/field capacity validation сохранена.
  Герои по-прежнему уникальны. Common builder и прежний Encounter Inspector
  разрешают повтор врага, row Remove/Up/Down и Undo используют прежний history.
  «Где используется» подтверждает общий шаблон одним file consumer.
  Result.build перечисляет instance IDs; loot_preview получает общий Resource
  через snapshot.templateId fallback runtime ID. Roll key содержит instance ID/
  slot, поэтому каждый враг даёт свой deterministic loot и defeated/tag counters.
  XP остаётся наградой встречи каждому герою; Transition/Explore once-only owner
  не меняется. Изменения характеристик шаблона учитываются в новых initial states,
  не перезаписывая HP/MP/статусы активных участников. Общие Action/AI/Loot читаются
  прежними каталогами; замораживание всех definitions на время боя не добавлено.
  Существующие fixed partner IDs парных действий остаются фиксированными ID,
  не превращаются в автоматический выбор любого экземпляра. Индивидуальные
  overrides экземпляра не добавлены. Targeted --enemy-instances и прежние
  encounters/lab-setup/operations/usage/check/15 regressions PASS. Native --cycle:
  author three rows/Undo/Redo/Save/reopen, обычный map battle/AI/Retry/Load/re-entry,
  victory3/loot6/XP35 once/Save/fresh Load; snapshots и исходные author data frozen.
  Common native roster/width, номера/цели/Result просмотрены; manual свои встречи/
  порядок/расстановка/input/narrow/125% OPEN. Evidence — Migration Plan.
- `tools/run_game_systems_tests.py --cycle` — сквозной author/play/fresh-load gate.
  `editor_test_game_systems_cycle.gd` использует настоящий plugin, Create dialog,
  typed forms/pickers и Save button; Save/reopen/Discard/field Undo проверены.
  `test_game_systems_cycle.gd` запускает обычный Transition/Lab/Result в новом
  процессе: native selection handlers/Combat.commit, shared equipment/status/
  effect/action/AI/loot, double Continue, menu Save/Load. Третий процесс читает
  те же private saves через normal autoload, затем native Load; сравниваются
  party/HP/MP/XP/5 slots/inventory/flags/group/strategy/chests/shop state и XZ.
  Completion flag не допускает повторных наград. Fixture задаёт identities и
  saved hash/UID evidence; native test-map alias регистрируется до cold autoload,
  чтобы реальная destination validation видела его. Resources заморожены между
  фазами; originals восстановлены после теста, рабочие author hashes неизменны.
  Runtime QA windowed 1600×900/30 FPS, отдельный user dir на весь тестовый цикл.
  `Store.blank(field)` теперь заполняет typed Array[Vector2i] через assign:
  прежняя generic Resource assignment обычного Array падала при Create с нуля.
  Размеры/стартовые клетки/schema не изменены; full-cycle/operations/navigation PASS.
- `tools/run_game_systems_tests.py --stability` — regression для native publication
  lifetime. Прежний короткий Save/Undo/Redo/reopen/delete воспроизвёл 0xC0000005
  на втором Save; Windows debugger подтвердил invalid read без SCRIPT ERROR.
  В обычном baseline также были get_dependencies errors: full scan читал записи
  во время Undo/delete. Адресное update_file при прежних cache/forms прошло 24
  цикла без AV/errors. Убран запускавший эту комбинацию full scan библиотеки;
  pending index updates принадлежат прежней общей Filesystem queue, файлы
  записываются синхронно, CACHE_MODE_REPLACE/UID/schema сохраняются.
  Постоянный native gate чередует быстрые и последовательные Save/Undo/Redo/
  reopen/edit/delete, проверяет FileSystem presence/absence, точные bytes/UID,
  held cached Resource values и отсутствие лишних full scans. 12 циклов PASS;
  fake queue проверяет busy/coalescing/source/full priority и reentrant callbacks.
  Исходные полные --editor и --cycle после исправления PASS; live author data/
  cache/saves не используются. Логи Temp/ember-game-systems-stability-rapid-fixed.log,
  ember-game-systems-editor-stability-fixed.log, ember-game-systems-cycle-stability-fixed.log.
  Debug evidence — Temp/ember-editor-crash-20261012 (AV code/address, baseline/
  variant logs). Полный dump получить не удалось; точный C++ frame не установлен.
  Исправлен воспроизводимый publication trigger, не доказана стабильность всех
  native/GPU сценариев. Ручные обычные Save/Undo/Redo/reopen остаются OPEN.
  Native reference: https://docs.godotengine.org/en/stable/classes/class_editorfilesystem.html#class-editorfilesystem-method-update-file;
  Godot 4.7.2 EditorNode::_resource_saved → update_file, а update_files удаляет
  index/UID для отсутствующего файла; renderer/importer и scene save owner прежние.
- `ember_game_systems_lab_setup_dialog.gd` — native настройки теста и локальные
  именованные наборы. Roster из saved Encounter; individual opt-in level/five
  slots и shared consumable bag. Load — одна local Undo/Redo команда; Cancel
  отбрасывает transient edits, explicit preset writes остаются. Launch context
  по пути встречи помнится только в workspace session; наборы — отдельно на диске.
  Save new/Update с rename, exact preset ID, Load, Delete confirmation/undo delete;
  наборы фильтруются по отсортированному составу героев, не по встрече/порядку.
  Numeric/picker input сохраняет controls/focus и cached catalogs; Load/reopen
  читает свежие каталоги. Missing items видимы для исправления, launch/save blocked.
  Размер scroll измеряется по native OK row/theme/wrapped labels; body/feedback
  не закрывают OK/Cancel. Forward+ screenshot/geometry gate; manual 125% OPEN.
- `ember_game_systems_lab_preset_store.gd` — единственный editor preference IO
  owner наборов: user://ember-library-lab/presets.json, format 1, records с ID/name/
  sorted heroes/setup. Не gameplay Resource, не initial loadout или save schema.
  Envelope/shape/duplicate IDs/names/size limits проверяются без catalog deletion;
  при Save существующий Setup.prepare заново валидирует items/levels/slots/counts.
  SHA expected-file guards и publication revision защищают stale updates/undo
  после чужого no-op Save. Staged bytes проверяются; Windows source сначала
  сохраняется в .previous, rollback/recover missing main без потери old bytes.
  Corrupt main не переписывается. Last delete можно вернуть до следующей записи;
  это explicit preference operation, не author/global publication Undo owner.
  --presets: три свежих процесса write/reopen/private battle; --presets-editor:
  focused native forms/popup/Save/recreated dialog/Load/real adapter child PASS.
- `scripts/prototypes/ember_combat_lab_setup.gd` — чистый transient test adapter.
  Проверяет roster, whole level 1..99, exact five slots/hero eligibility, native
  consumables/counts/stack cap и existing ItemStore validator. PartyState
  `derived_stats_for_unit`/`project_combat_member` — общий расчёт/проекция для
  campaign и saved hero cards; campaign HERO_IDS/normalize/save не менялись.
  `normalized_input` канонизирует проверенные JSON whole level/counts в int:
  loaded presets/native controls/Undo сравнивают одинаковый input. Payload version
  и gameplay schema прежние. Default без overrides оставляет authored stats без пересчёта; opt-in начинает
  с полных HP/MP/нулевого XP. Combat остаётся единственным resolver.
- `ember_game_systems_lab_launcher.gd` — editor process adapter: saved native
  Encounter path → OS.create_process прежнего combat_lab.tscn, без project settings
  или author writes. Одно отслеживаемое окно, 1600×900/30 FPS, отдельный log.
  Workspace не запускает dirty draft; preflight валидирует saved record, runtime
  повторяет проверку. Marker EMBER_LIBRARY_LAB_READY подтверждает consumed ID.
  Optional setup передаётся временным versioned JSON под user://ember-library-lab/
  requests через --ember-library-setup=<absolute path>, без command-line JSON.
  Native root/normalized path, 128 KiB/version/encounter identity, duplicate/orphan
  args и настройки проверяются снова runtime; consumed request удаляется Lab.
  `EmberCombatTransition` парсит единственный --ember-library-encounter=res://...
  под native encounters root; любой setup flag также включает isolation до saves.
  Normal transition/finish в test mode запрещены.
  `ExploreState._ready` до чтения saves отключает persistence/restore и назначает
  process-private paths; Lab не берёт party/inventory/strategy из игрового save.
  Test projection применяется только к opt-in heroes; private inventory snapshot
  задаёт стартовую bag, Retry восстанавливает неизменный setup и исходные counts.
  `_library_test` — process/UI context, не Resource/save schema. Same Lab/resolver/
  Result считают бой/награду. Test outcome предлагает Retry/Close, скрывает Load,
  не применяет counters/XP/items/scripts и не возвращается на карту. Нормальный
  игровой режим сохраняет переход/поражение/reward path. `combat_lab.tscn` —
  Node3D shell с отдельными Arena и CombatHUDLayer. `_install_encounter_arena`
  после завершения child-ready traversal, до UI/state, заменяет default Arena
  выбранной saved arena_scene; Battlefield встречи назначается перед add_child.
  Корень — прежний EmberCombatGrid3DWorld или его наследник; renderer/physics/
  camera/input остаются прежними. Декор/свет/камера сохраняются, семантическое
  поле арены не меняет encounter field. Активируется CameraRig/CombatCamera3D:
  дополнительная камера декора не подменяет rendering/picking. Retry сохраняет
  один экземпляр арены;
  2D скрывает весь её 3D root. Installer общий для ordinary transition и library
  test; standalone Lab без authored encounter сохраняет default Arena. Transition
  до смены сцены валидирует saved encounter/arena; после consume HUD назначает
  encounter field до Arena ready, затем подключает сигналы и создаёт battle state.
  Retry не инстанцирует арену повторно; defeat Load освобождает весь shell и lock,
  re-entry создаёт новую selected arena. Награды/return/save принадлежат прежнему
  Transition/ExploreState; format Resources/saves и Combat resolver не менялись.
  `EmberEncounterResource.arena_validation_errors` проверяет script ancestry и
  обязательные typed node paths через SceneState, включая inherited/instanced
  bases; validation не запускает author _init/_ready. Это existing Resource
  validator, не новый scene/schema owner. Save/launch/checker используют его.
  Неподходящая/пустая сцена блокируется; native --lab/--arena и arena picker
  Undo/Redo/Save/reopen PASS; ручное окружение/камера/narrow/125% OPEN.
- `ember_game_systems_library_check.gd` — read-only SceneTree utility: raw saved
  .tres paths из Store.SPECS + icon/story_action identities, fresh Resource loads.
  ID namespaces раздельны; дубли не схлопываются каталогом. Existing Resource/
  ItemStore validators владеют правилами; enum options берутся из metadata.
  Проверяются recursive file dependencies и активные ID links; wrong nested
  action effect type отсекается до validator. Иконки/story bodies не валидируются
  полностью. Хеши исходных файлов позволяют заметить их изменение при чтении;
  это не атомарный snapshot всего каталога. Нет author writes или auto repair.
  `ember_game_systems_check_service.gd` запускает отдельный headless процесс,
  poll/timeout/report identity/log completeness; SCRIPT ERROR не считается clean.
  JSON/log — user://ember-library-check. Cancel останавливает только свой PID.
  `--ember-library-check=` входит в isolated_editor_process guard Transition/
  ExploreState до save restore. MCP Runtime для этого флага пропускает shared
  ready/IPC регистрацию; normal gameplay и Lab MCP path этим не отключаются.
  `ember_game_systems_check_panel.gd` — native report/search/detail/repeat, saved
  scope и stale reminder. Exact path → прежний Inspector route или FileSystemDock;
  ID alias не используется, dirty draft блокирует переход. Workspace не reloads
  live catalogs при проверке. Current saved library: 74 records / 0 issues;
  malformed fixtures и native navigation QA проверены, user/narrow/125% OPEN.
- `EmberGameStartResource` / `content/game_start/default.tres` — одна recipe
  для новой игры: `hero_levels`, `hero_equipment`, `inventory`. ID default;
  отсутствующий герой = level 1 / пустые пять слотов, bag по умолчанию 20 coin.
  Fixed HERO_IDS/Equipment.SLOTS не меняются; XP 0, полные HP/MP рассчитывает
  PartyState. Надетые вещи — отдельные экземпляры от указанных в общей сумке.
  Validation проверяет целые уровни 1–99, IDs героев/предметов, exact five slots,
  Item/Equipment совместимость и allowedHeroIds, положительные целые bag counts
  до stackMax. Пустая сумка легальна. Author validation читает только referenced
  Items fresh; UI держит view snapshot вариантов, не gameplay cache/owner.
  `prepare()` строит deep-isolated party/bag через PartyState без мутации config.
  Только `ExploreState.reset_new_game()` применяет полностью проверенную recipe;
  при ошибке возвращает false и сохраняет весь прежний live progress.
  Если boot не смог загрузить save и recipe отсутствует/невалидна, создаётся
  нейтральная временная сессия с warning и persistence_enabled=false: существующие
  файлы saves не перезаписываются. PartyState.new_game/normalize и load/migration
  остаются нейтральными и не применяют authored старт к загруженным данным.
  Save v2 schema прежняя. Runtime read учитывает exported Resource remaps.
  Common Catalog/Store/Session: module start, singleton Create/Copy/Delete
  заблокированы в UI/commands/session; обычные Save/global publication Undo/UID.
  `ember_game_start_editor.gd` — четыре native hero tabs, level/compatible gear,
  текущие derived HP/MP/str/def/speed и общий bag с item/count/Add/Remove.
  Numeric input copy-on-edit/field merge, без пересборки всей формы; UI Undo
  rebuild принадлежит общему DraftEditor. Item/Unit links идут в «Где используется»
  и saved checker, включая malformed dictionaries без crash.
  --start/--start-editor и расширенный --cycle проверяют рецепт → новый runtime →
  ordinary combat/result/menu Save → fresh Load, без выдачи тестового оружия кодом.
  --operations/--check/--usage, 15 regressions, шесть party и четыре interaction
  gates PASS; clean checker 72 records/0 issues до malformed fixtures.
  Исходный authored default сохраняет прежнее поведение. Свои старты, мышь,
  узкое окно/125% и игровая приёмка OPEN; сохранения пользователя gates не читают.
- `EmberCombatActionResource` владеет четырьмя PackedStringArray:
  actor/target_required/forbidden_status_ids (полные имена в Resource), defaults
  empty, и embedded `value_conditions: Array[Dictionary]`, default empty.
  Числовая row: subject actor/target, stat hp/mp, comparison gte/lte, unit
  points/percent, value int 0..1_000_000 points или 0..100 percent; пять exact keys.
  `equipment_conditions: Array[Dictionary]`, default empty: четыре exact String
  keys subject(actor/target), mode(item/occupied/empty), slot, item_id.
  Slot — canonical Equipment.SLOTS, или пустая строка «любой» только для item;
  item_id непустой только для item. ItemCatalog/Equipment остаются владельцами
  идентичности предметов и совместимости пяти слотов. Items в bag не учитываются.
  Отсутствующая equipment у unarmed unit означает пустые слоты; malformed shape
  не проходит predicate. Occupied — непустой ID в snapshot; точный item дополнительно
  проверяет совместимость со слотом через текущий catalog/Equipment.slots_for_item.
  Gear validation проверяет shape/IDs/slots/duplicates/CELL и SELF merge, empty
  против occupied/item, разные items в одном slot. Any-item requirements проходят
  ограниченный matching пяти слотов, включая два weapons/три разных accessories
  и fixed-slot ограничения. Actor/target независимо до SELF merge.
  Runtime validation использует check_item_settings=false: IDs проверяются по
  native directory/remaps, без fresh-load всех referenced Resources на каждый
  кандидат; metadata читается при совпадении надетого ID. Author/checker validation
  по умолчанию читает ItemCatalog fresh и проверяет совместимость до публикации.
  Отдельного Resource/predicate registry/runtime owner нет. Projection
  `applicationConditions`/`application_conditions()` сохраняет snake_case keys;
  вложенные rows копируются глубоко. Signature,
  validation и behavior summary включают их. `ember_combat_action_conditions.gd`
  — stateless leaf: AND присутствия/отсутствия через StatusRules.has (turns > 0),
  unknown/duplicates/conflicts/CELL target и SELF cross-contradiction validation.
  Numeric validation отсекает malformed/unknown/duplicates и несовместимые bounds
  в одной мере; SELF объединяет actor/target bounds. Mixed points/percent могут
  зависеть от конкретного max; доступность проверяется на реальном бойце.
  Точное сравнение percent: current*100 ≥/≤ threshold*maximum, без округления.
  Max <= 0/не int блокирует percent с причиной; points проверяют current независимо
  от max. Все predicates проверяются на pre-cost/pre-effect snapshot, включая
  SELF healing/MP cost. Состояние игрока/цели после effects не отменяет действие.
  Terrain wet tags не означают активный unit status. Проверяется исполнитель
  и выбранная основная цель до effects; вторичные/соседние получатели эффектов
  не становятся отдельными predicate targets. CELL допускает только actor rules.
  CombatPrototype.action_condition_reason фильтрует/поясняет условия вместе с
  eligible/valid IDs/cells, проверяет
  preview и повторно commit; Grid/AI/HUD используют прежние общие paths.
  Preview optional int actionConditionsHash отказывает изменённым правилам;
  даже без hash commit заново проверяет текущие predicates. Snapshot/save schema
  прежние, Result schema расширена optional guard. Item и synthetic held commands
  остаются без predicates; отпускание уже поднятой цели не блокируется новыми
  требованиями исходного lift action. Empty defaults сохраняют старый контент.
  Common draft builder: именованные subject/presence/status → Add и removable
  строки; numeric builder subject/stat/unit + comparison/threshold/Add, saved rows
  напрямую меняют threshold/comparison/unit с Undo, Delete/Discard прежние.
  Numeric input copy-on-edit, history key row/value; malformed rows остаются
  читаемыми/removable. Повторы/противоречия блокируют Add/Save, несовместимые saved
  IDs/target rows не скрываются. Gear rows меняют subject/mode/slot/item, copy-on-edit,
  без второго draft/history owner. Mode→occupied/empty явно очищает item_id и
  задаёт weapon, если прежний slot был any; один Undo возвращает целую row.
  Несовместимый/отсутствующий item остаётся в picker и блокирует Save; malformed
  saved row можно убрать. CELL actor-only общий для всех трёх видов rules.
  Catalog.relations/incoming_links связывают условия со статусами и предметами;
  saved checker проверяет неоднозначные gear item refs, conservative Delete guard
  сохранён. --conditions/--gear-conditions/full --editor/15 --regressions и --cycle
  с saved status/numeric/gear predicates в трёх процессах PASS.
  Native form/width/screenshot проверены; manual свои условия/input/narrow/125%
  OPEN. `condition_groups: Array[Dictionary]`, default[] — плоские AND/OR группы
  в прежнем Action Resource. Каждая group содержит mode all/any и optional те же
  шесть leaf fields; группы и legacy mandatory rules соединены AND. Вложенные
  группы/неизвестные ключи/пустые группы блокируют Save. Каждая OR альтернатива
  валидируется отдельно; противоречия разных альтернатив не считаются AND-конфликтом.
  В ALL группе действуют прежние проверки joint bounds/slots/SELF. Полная
  разрешимость комбинации разных групп статически не вычисляется.
  Conditions.pair_reason проверяет actor+основную target совместно, поэтому
  false actor branch не отбрасывает true target branch. Combat сохраняет ранний
  gate только для mandatory actor rules; pair gate общий для target enumeration,
  preview/commit, Grid approach, AI и HUD. CELL допускает actor-only группы,
  SELF использует одного бойца для обеих сторон. Pre-cost/pre-effect, optional
  guard hash и независимая перепроверка commit сохранены; save/snapshot schema
  не меняется. application_conditions/to_definition/signature включают deep copy
  групп. Catalog/usage/checker учитывают status/item refs в группах.
  DraftEditor выбирает mandatory root или группу, меняет all/any, добавляет и
  удаляет её с прежним history owner; выбор группы остаётся editor-only.
  Все три существующих builders редактируют выбранную группу copy-on-edit.
  Некорректная сохранённая группа остаётся в draft/feedback и удаляется явно;
  display copy фильтрует неотрисовываемые строки без исправления файла.
  `--condition-groups`, прежние conditions/gear, operations/usage/check и
  15 regressions PASS. Native cycle: mode Undo/Redo, Save/reopen/Discard,
  новый runtime с обеими OR ветками/отказом → ordinary result → fresh Load PASS;
  снимок/width guard проверены. Свои группы/input/narrow/125% OPEN.
  Стартовые комплекты описаны выше, свойства обуви — в блоке Equipment/Party ниже.
  Первый полный --editor не получил ready/log от Lab child; последовательный
  повтор без изменения launcher PASS, причина первого запуска не установлена.
  Evidence — Migration Plan; это не гарантия всех launch/native/GPU сценариев.
  Авторский контент не переписан.
- `EmberCombatStatusResource` владеет default_duration/reapply/max_duration,
  power_bonus/outgoing_damage_percent/incoming_damage_percent/remove_on_damage
  и `turn_end_hp_change: int -999..999`, default 0 (`turnEndHpChange` в projection).
  Neutral defaults сохраняют baseline. `StatusRules` исполняет общий повтор,
  множители и снятие; DamageRules и единственный CombatPrototype вызывают их.
  Runtime statuses хранит ID → int turns; opt-in независимые дозы используют ID → Array[int] timers в том же owner, decay в конце своего действия.
  Apply effect duration 0 использует default до сокращения устойчивостью.
  Authored apply/remove соблюдает порядок шагов; старое потребление guard
  сохраняет baseline. Commit отклоняет новый preview при смене statusRulesHash;
  StateSchema/apply validation блокируют некорректную native definition.
  Power относится к damaging action, outgoing — scaled direct damage; incoming
  применяется к итоговому damage перед guard. Особые реакции пяти ID прежние;
  новые elemental semantics и накопление непериодических модификаторов не реализованы.
  `max_stacks:int` [1,12], default1 / projection maxStacks / signature / validation
  принадлежат тому же StatusResource; >1 требует ненулевой turn_end_hp_change.
  При maxStacks1 прежние refresh/keep_longest/extend/ignore и scalar snapshots
  сохранены. При >1 StatusRules.set_status копирует timers, добавляет дозу либо
  заменяет минимальный timer входящим (при равенстве первый). Pending apply в одной
  цепочке учитывается; resistance сокращает новую дозу до добавления. Scalar
  legacy counter при включённом opt-in читается как одна доза. StateSchema
  проверяет nonempty arrays, cap, positive integer timers; схема обычного save
  не меняется, статусы остаются battle-local. durations/remaining/count/timer_text
  — единые leaf helpers; проверка наличия не аллоцирует список для scalar.
  Turn-end HP умножается на count; power/outgoing/incoming действуют один раз.
  remove/removeOnDamage очищают весь ID, decay удаляет истёкшие дозы независимо.
  Наличие для conditions/element reactions и spread source duration используют
  remaining=max timers; spread накладывает одну дозу с этим сроком, не копирует
  весь массив. _apply_unit_effects копирует array в preview/commit без aliasing.
  HUD status text/icons/3D badges показывают count/timers; журнал — суммарные HP.
  Console add-status идёт через тот же set_status. DraftEditor скрывает single
  reapply/maxDuration при >1; limit/HP/Undo/Redo/Discard/Save/reopen/UID прежние.
  Canonical poison/regeneration defaults не переписаны. --stacks/--periodic,
  related conditions/operations/check и 15 regressions PASS. Native author→fresh
  Forward+ HP25→30→18 (две дозы −6), timers1/3→2 и journal/badges PASS; ordinary
  cycle с authored stackable статусом — Migration Plan. Manual свои дозы/баланс/
  input/narrow/125% OPEN. Один native editor exit0xC0000005 после формы сохранён
  в Temp/ember-stacks-editor-exit-failure.log; следующий полный native gate exit0,
  причина crash не доказана.
  `StatusRules.turn_end()` — pure leaf: после эффектов собственного действия
  сначала сумма положительных HP до maxHp, затем сумма отрицательных до 0,
  затем removeOnDamage при реальном periodic уроне и прежний decay. Это выбранный
  автором порядок, не net sum; сортировка IDs влияет только на имена в журнале.
  Уже павший не лечится. Последний remaining turn срабатывает; снятый статус
  исключён, новый self-status действует сразу. Чужой ход/дуэтный помощник не
  получают отдельный tick. Fixed periodic HP не масштабируется defense/guard/
  crit/outgoing/incoming modifiers; negative tick может добить.
  CombatPrototype._apply_unit_effects — общий action projection для commit и
  точного internal turn_end_preview, без копии всего combat state на preview.
  Neutral statuses не создают дополнительную actor copy. HP/statuses применяет
  прежний commit, затем прежние timeline/held release/outcome. Rule signature
  включает HP field, stale guard сохранён; runtime/save schema не расширены.
  Exact internal preview/log объясняет actual healing→damage; публичный intent
  использует только текущие известные правила без скрытых hit/crit/HP deltas.
  HUD journal follows bottom, чтобы многострочный turn-end результат был виден.
  Новые native poison/regeneration templates: −5/+5 HP, три хода, без назначения
  старым действиям/бойцам. Это редактируемые значения, не принятый баланс.
  Common draft/validation/summary/Undo/Save/reopen используют Resource metadata.
  Targeted periodic + прежние statuses/15 regressions/conditions/clean checker
  PASS; focused native editor и fresh Forward+ battle также PASS. Единственный
  native 0xC0000005 при выходе после успешных form/publication gates не повторился
  в следующем запуске; причина неизвестна, не объявлять общей stability fix.
  Свои приёмы/статусы, input/narrow/125% и баланс OPEN. Evidence — Migration Plan.
- `ember_item_editor.gd` — формы семи типов с русскими labels, native icon picker,
  экипировочными max HP/MP/allowedHeroIds и использованием HP/MP/revive/range/delay.
  Неактивные значения и extension metadata сохраняются. Текущие типы включают
  shoes; legacy weapon_arena/head читаются, но не экипируются. Body armor читает
  прежний native Resource без перезаписи, explicit Save нормализует slot в armor.
  Отрицательные HP/MP-бонусы допустимы. Неизвестные hero IDs сохраняются.
  `ember_item_store.gd` нормализует существующие optional keys и проверяет
  экипируемость armor/положительный combatDelay; runtime owner/schema не добавлены.
- `ember_equipment_preview.gd` — editor-only выбор героя/уровня, пяти исходных
  слотов и accessory target; до/после считает через Party.derived_stats и
  Equipment.equip. До использует published definitions, после — подставленный
  draft, без записи в Resource/Explore. Комплект сворачивается; контекст держит
  DraftEditor, переживает field Undo/Redo и не попадает в item serialization.
- `ember_equipment.gd` владеет пятью слотами, slots_for_item, import_saved и
  возвратом owned instances без loot cap. ArenaAtk — compatibility projection
  того же weapon atk. Party разрешает аксессуары всем; обувь/оружие/броня
  используют прежний allowedHeroIds. Inventory UI даёт explicit accessory1/2
  или первый свободный (иначе 1); перенос исходных slots принят пользователем.
- `ember_graph_workspace.gd` монтирует kind `systems`; dirty draft защищён при
  Home/graph navigation/search/module/selection. Double-click открывает draft.
  Старые browser/Inspector/form/Lab routes доступны отдельно; combat Create/Copy
  ведут в common draft, Save старого combat browser использует общий publisher.
- `plugin.gd` добавляет Tool menu «Ember: Игровые системы»; reload/unload сохранён.
  Новый layout принадлежит прежним Equipment/Party/Explore owners.
- Обувь: optional item-definition keys `moveBonus` [-12,12], `jumpBonus` [-8,8],
  `pushResistanceBonus`/`wetResistanceBonus` [0,12], default0. ItemStore требует
  конечные целые числа; ItemEditor показывает поля только shoes, скрытые данные
  сохраняет. Equipment.footwear_bonuses читает только shoes в слоте shoes;
  Party.derived_stats добавляет бонусы к Unit base, MOVE/JUMP снизу0, Wet — к
  base statusResistances.wet. project_combat_member переносит существующие
  combat fields; другие statusResistances не теряет. Preview/Inventory используют
  тот же derived результат. Снимки боя остаются прежними; save хранит ID вещи,
  Load пересчитывает значения без новой миграции. Grid MOVE/JUMP, порог push и
  StatusRules duration-minus-resistance остаются единственными runtime rules.
  Защита сокращает новое Wet application, не старые статусы и не свойства клетки;
  overworld movement не меняется. `--footwear` и extended native `--cycle` PASS:
  Undo/Redo/Discard/Save/reopen/UID, unsaved fitting, bag equip/unequip, обычный
  бой/result/Retry/fresh Load. Manual свои обувь/бой/баланс/narrow/125% OPEN.
- Native CRUD/identity/ref/UID/conflict, item type/hidden values/filter guards,
  signed bonuses/hero restrictions через PartyState и расходник через прежний
  preview/commit + items/PCK/Graph regressions и real
  Forward+ draft fields/Save/reopen/global Undo/plugin lifecycle PASS;
  новые status rules/ordered chain/stale guard и related combat gates PASS;
  авторская оценка удобства OPEN. Этапы — Product Plan → «Игровые системы редактора».

Surface Canvas уже покрывает основной voxel workflow:
- palette и picker;
- selection и группы;
- sculpt/height tools;
- water/fill;
- slice/region режимы;
- chunk preview;
- Undo/Redo;
- guarded Save/Discard/Reopen.

Большая dense Surface ранее профилировалась без основания для общей смены schema.
После ручного отказа от Landscape V2 измерен новый bottleneck на копии берега:
~15 с до полной первичной проекции. Поэтому только для обычной земли начат
вертикальный компактный путь на отдельной сцене Landscape. Это не перенос всех
старых Surface и не смена voxel-схемы объектов; ручная приёмка ещё открыта.

Native Surface projection пока используется старым миром/Canvas и связанными
боевыми представлениями. В compact Landscape вид, collision и route height
выводятся из одного колонкового документа. Для physical maps эти результаты
должны оставаться согласованными.

Object/world workshop использует существующие owners для:
- Object Canvas;
- простых voxel-форм;
- scene context в Canvas;
- точной voxel-расстановки;
- групп/linked copies;
- секций и assembly Canvas;
- merge/split;
- object placement brush;
- генеративных environment-объектов;
- relief/coast/water инструментов.

`addons/ember_import/ember_world_panel_host.gd` — единственный owner lifecycle
перенесённых панелей map/material/objects/placement/shape/duplicate/merge/split/conversion. WorldEditor
регистрирует routes после создания controls; host хранит active_id, pending/cancel
callbacks, предыдущий workspace и toolbar visibility. Mode queries в WorldEditor —
вычисляемые views, не отдельное состояние. `can_leave_panel()` — общий guard;
registry скрывает прежние страницы. WorldEditor только представляет page/preview
в dock/bottom-panel API; инструменты сохраняют свои сессии, расчёт и commit.
Input routing в plugin использует host.blocks_viewport_tools(): numeric focus не
перехватывается, камера PASS, material history проходит через прежний controller,
object brush остаётся в прежнем 3D path. Scene-bound callbacks очищают контекст,
material.persist_scene сохраняет независимый dirty файл. Map.is_dirty() сравнивает
параметры с исходными и учитывает подготовленный source; новых Resource полей нет.
При plugin shutdown routes освобождаются до controls. Новые UI-срезы подключать
регистрацией, без копирования lifecycle/guards/toolbars и без второго owner данных.

Параметры scene object brush принадлежат прежнему `ember_voxel_object_brush.gd`.
`plugin.gd::_open_object_brush_settings` маршрутизирует в WorldEditor/dock без
AcceptDialog. `WorldEditor.object_parameters` — один набор controls: в активном
мире находится в Tools, вне мира временно в `_object_brush_workspace`; значения
синхронизируются из кисти без signals. Sidebar mode не включает `WorldEditor.active`
и не перехватывает placement input. Stop/Esc/scene change возвращают controls и
прежнюю видимость toolbars. Параметры остаются editor-only; форматы источника,
scene-instance ownership, prefab/physics/один Undo за мазок не менялись.

Точная расстановка сохраняет `ember_voxel_placement_session.gd` и чистый
`ember_voxel_placement_math.gd`. Прежний `ember_voxel_placement_dialog.gd` теперь
VBoxContainer с `parameters_panel` и нижним SubViewport; один `_planned_world`,
session и набор derived target/context копий. `plugin.gd::_place_voxel_selection`
повторно показывает тот же bound session, plugin регистрирует нижнюю «Расстановка»,
WorldEditor представляет `_placement_workspace`, lifecycle/guard принадлежат host.
Apply выбирает исходный target, session commit хранит transform в `.tscn` одной
Undo action; scene switch/Cancel очищают session/context, другой selected node не
перенаправляет Apply. Bottom collapse не сбрасывает план, UPDATE_WHEN_VISIBLE
останавливает скрытый viewport. Форматы моделей/prefab/мировой физики прежние.

«+ Форма» сохраняет `ember_voxel_shape_creation.gd`/`ember_voxel_shapes.gd` и
existing model store. `ember_voxel_shape_dialog.gd` — VBox controller; параметры
и SubViewport отделяются методом `use_dock_layout`, plugin регистрирует нижнюю
«Новая форма», WorldEditor маршрутизирует `_shape_workspace`. Один candidate
prepared→commit, поля лишь инвалидируют его, Cancel/scene change очищают root/parent/
preview refs. Create сохраняет native assets, одну scene action и прежний Canvas path.
Legacy callers/fixtures наследуют те же fields/preview и получают ограниченный
ConfirmationDialog через modal adapter; `get_ok_button`/`canceled` совместимы.
До popup preview остаётся в прежнем scroll box для legacy camera/input path; при
удалении wrapper сразу скрывается, чтобы не удерживать exclusive child window.
Controller/renderer/model-owner не дублируются. Source/prefab overrides — только fixtures.

Дублирование сохраняет `ember_voxel_scene_assembly.gd` и проверки
`ember_voxel_placement_session.gd`. Прежний `ember_voxel_duplicate_dialog.gd` теперь
VBox controller с `parameters_panel` и нижним SubViewport (UPDATE_WHEN_VISIBLE).
`plugin.gd::_scene_assembly_command(4)` повторно показывает bound session; WorldEditor
представляет `_duplicate_workspace`, host вызывает прежние guard/cancel при смене. Prepare
меняет derived poses/mesh copies, commit сохраняет экземпляры `.tscn` одной action.
После успеха сохраняется прежний `_last_duplicate_step`; command 5 по-прежнему
создаёт одну копию текущего selected prop. Источники/Assets/schema/physics не менялись.

Склейка/разбор26.10 перенесены в общий CanvasForms/FormsPanel и WorldEditSessions.
Прежние merge dialog/session удалены; Scene commands открывают те же dirty drafts.
Toolbar и menu используют plugin._open_selected_canvas: один prop открывает общий world draft,
2–32 — прежний CanvasForms; wrapper assembly сохраняет свой путь, пустой выбор не берёт stale target.
Inspector оставляет primary «Редактировать в Canvas», shared/linked/independent — в прежнем action signal
через «Модель и копии…». Native --canvas-entry-only PASS; авторская оценка OPEN.
WorldEditor.activate_context — общий вход Alt+Q/target picker/EditorSelection; WorldEditSessions
сохраняет отдельные черновики и единую историю сцены. InspectorModel.voxel_owner разворачивает
производный preview prop к авторскому. Workspace.open_world_draft и world_context_return_requested
связывают Canvas с тем же entry; WorldEditor/BrushProfiles переносят кисть/физический радиус,
неподдерживаемое действие явно отключено. Незавершённый жест/candidate блокирует переход.
Native --world-context-only PASS на main-copy; ручная приёмка и QA shutdown OPEN — World Authoring.
Merge.plan/separate — единственная математика, ObjectSession.can_replace_geometry — общий
guard authored material/collision; SceneAssembly защищает структуру/связи. Явные align/bake
и detached preview/Cancel/stale/commit перенесены в FormsPanel, публикация — прежний Save.
BrushProfiles владеет общими tool labels/mask policy, FormsPanel — формами и их вводом;
CanvasMode.FORMS исключает одновременную активность кисти. World Smooth solid объекта использует тот же VolumeSmooth worker прямо в3D: immutable baseline,
сегменты/донорские материалы+parts, применение через прежнюю delta/history, locked/region guards,
retired jobs после Cancel и join при exit. Heightfield остаётся прежним CompactTerrainBrush/Source.
Нативный --world-smooth-only PASS, ручная оценка OPEN — World Authoring → «Сглаживание прямо в3D».
SculptModel.SurfacePlaneJob — чистый локальный расчёт плоскости для прежнего Level: immutable voxels/
parts, fixed plane normal/point, режим fill+cut или cut-only, inward donor без перекраски исходного объёма.
WorldEditor переиспользует очередь worker/Cancel/retired/delta/history/preview; BrushParameters задаёт
видимость параметров, слой влияния и смещение в vox. Земля остаётся высотной. Native --world-plane-only
и math --plane PASS. Canvas Level использует тот же SurfacePlaneJob в прежней VolumeSmooth очереди;
mask/locked/EditBounds/parts/history прежние. BrushProfiles хранит mode/offset editor-only; WorldEditor
передаёт mode/offset/depth вместе с tool/radius. Profile restore повторно выставляет mask policy, глубина
plane не квантуется max8 от прежнего Smooth. Native --canvas-plane-only и --canvas-plane-transfer-only
PASS; подробности/границы/приёмка — World Authoring → «Общая плоскость Canvas/3D».
BrushProfiles.MAX_RADIUS_VOXELS256/normalize_profile сохраняют унаследованный большой радиус и
smooth_strength1–8. Workspace._select_numeric_brush_value добавляет точный inherited preset,
world_brush_settings/set_world_brush_settings передают только сопоставимые операции:
Smooth volume force, Add/Remove depth, Grab softness. WorldEditor._adopt_canvas_brush_settings
заменяет прежний plane-only adapter и включает прежние plane mode/offset/depth. Heightfield/relief
сохраняют свою семантику; новый глобальный hardness algorithm не вводился. Native --brush-settings-only
и editor-profile serialization PASS; Source/schema прежние — World Authoring → «Общие параметры кистей».
WorldEditSessions entry.canvas_guard — один transient owner mask/region/height по Source/цели.
Workspace публикует SelectionPanel.history_state при выходе/изменении выбора; hidden source events
не стирают guard. restore_world_guard возвращает его на тот же Source, stale grid блокируется.
Selection.mask_allows/axis/key — общая leaf math панели и мира; compile_brush_guard фиксирует
membership/region/height на pointer-down. World _apply_batch фильтрует все voxel channels до записи,
Model/worker locked groups сохраняются; _shared_mask_normal фиксирует signed face и Add adjacent.
Grab с mask недоступен, иначе прежний Fragment получает пересечение областей/height. Source/schema,
публикация и история прежние; mask не сериализуется в gameplay. Gates/evidence — World Authoring
→ «Маска и защита Canvas/3D». CanvasForms capture/history теперь включают per-body guard;
select завершает старый input, Workspace._guard_transition подавляет промежуточную публикацию,
binding возвращает guard выбранного Source. Selection.translate_brush_guard переносит обычную
сетку merge; scope не округляется, активная неточная защита отклоняет plan. Shared Source/Stamp
путь прежний. Полный main-copy --forms-cycle-only PASS — World Authoring → «Формы и библиотека».


 Полный текущий контракт,
limits/evidence/ручные gates — World Authoring → «Единое управление миром и Canvas».
Чистый WorldEditSessions preview сохраняет оригинал; geometry_changed создаёт прежнюю
проекцию на первом реальном изменении и возвращает оригинал при Undo до clean. Dirty solid
SurfaceProjection использует ObjectLookJob → Solid.look_geometry/look_meshes → Prefab.preview_from_looks
→ прежний EmberVoxelProp. Snapshot/revision отбрасывает stale; object_frame берётся у прежнего
ObjectSession при подключении, включая смену размера Source. Физический prop/floor — через
неэкспортируемую authoring_preview WeakRef; исходный collision layer меняется только PhysicsServer.
Выход/Undo/Discard/Save возвращают исходную поверхность; reenter восстанавливает geometry subscriptions.
Retired handles собирает sessions.poll_recovery; нового Source owner/renderer/schema нет.
Solid.active допускает легальную часть0 «Добавленное»; uses_volume выбирает volume и для неё,
даже если occupancy вернулась к reference. Материалы volume читаются по voxel palette, не convex owner.
Физика опубликованного volume в EmberVoxelProp привязана к канонической _hull_mesh (она содержит
вогнутую объёмную границу), а не текущим кубикам/детальному обличью. _sync_volume_collision и floor
используют эту же поверхность; авторская коллизия защищена. Край ступеньки между обликами —
test_solid_volume --physical-looks; связанный native штамп проверяет каноническую коллизию.
Отрицательные/вне диапазона IDs по-прежнему отвергаются; Source/Parts.stroke не меняются.
Prefab сохранённого Corner с869 такими клетками восстановлен Store.install_derived_prefab в Forward+,
без записи Source/main. Gate/backup/ограничение headless TextureLayered — World Authoring, Add27.10.
EmberVoxelProp._bind_map_lighting восстанавливает material light/gray
вместе с voxel light после rebuild/POST_SAVE; fallback light mode1 соответствует фабрике.
Регрессия чистого Canvas/пустого Save проверена test_canvas_appearance на реальных main assets;
ручной повтор после перезапуска Godot и понятность входов ещё OPEN. Main/Source не переписаны.

Split/conversion используют тот же host и наследуемый shape controller, без
дополнительных mode flags. `pin_preview_action()` закрепляет подготовку для
split/conversion; старый modal API остаётся только для compatibility.
`ember_voxel_split_dialog.gd` создаёт controls один раз, хранит bound weak target;
input убирает splitter/preview, явный prepare вызывает прежний `ember_voxel_object_split`.
Текущие границы/каналы/physics и одна Undo/asset publication не менялись.
`ember_voxel_conversion_dialog.gd` сохраняет bound primitive, единственный compare
control и прежний `ember_voxel_primitive_conversion`: fit, material/physics/stale
validation, original replacement и Canvas owner прежние. Density input масштабирует
XYZ через прежнее правило и инвалидирует оба preview; смена типа требует reopen.
`plugin.gd::_voxel_canvas_is_clean` — общий nonmodal prepare/Apply guard split/conversion.
Cancel/commit/scene change освобождают source/root/undo/candidates; controllers
переиспользуются, preview UPDATE_WHEN_VISIBLE. Collision alignment — прежняя отдельная
ConfirmationDialog/Undo; большие prepare/commit синхронны. Resource/schema не менялись.

Отдельный `scenes/world_canvas.tscn` и
`content/world_surfaces/world_canvas_surface.tres` дают проверочную
физическую карту 24×25 блоков с водой, берегом и дном. Причал и его Surface
остаются авторскими и не заменяются; главная сцена проекта не переключена.
Первичное построение Холста мира через `tools/world_canvas_layout.gd`
не является runtime provider; builder отказывает в перезаписи существующего
Source. F6 использует прежний play controller и ждёт готовности Surface physics.

Режим «Редактировать мир» уже доступен прямо в 3D: форма/покраска/берег,
дно/вода, смягчение, мягкое вытягивание и object brush идут через прежние
Canvas/brush/generator owners. 3D и Canvas работают с тем же Resource-черновиком
и историей сцены; переключение режима не публикует данные. Новая земля Причала
создаётся только после явного выбора участка, заполняя пустые колонки.
Существующие объекты, вода и физика сцены не преобразуются автоматически.
Генератор новой вариации по-прежнему требует явной команды «Сохранить вариацию
и поставить»; общий Save не публикует неразмещённый preview.

`Map.surface_origin` задаёт начало общей Surface; старые сцены сохраняют
нулевое значение, Холст мира и новая земля используют смещение вниз. Вода
сохраняет прежнюю fill boundary schema, без миграции старых authored arrays.
Brush preview и commit используют один расчёт. Мазок — одна Undo/Redo-команда;
изменяются затронутые mesh/physics chunks и соседние границы, без полного
remesh на каждый input. Обычный сплошной грунт использует heightfield
collision, навесы и пустоты — точные открытые voxel faces. World/player
sampling и collision должны оставаться согласованными; многоуровневая
навигация пещер этим срезом не добавлена.

Общий Save работает **в пределах текущей сцены**: проверяет цели и baseline
всех грязных черновиков, готовит независимые объекты, публикует source/prefab/
Surface и сцену, затем принимает новые baselines. При ошибке восстанавливает
точные файлы и сохраняет несохранённые черновики. Кнопка и Ctrl+S используют
штатный scene Save Godot с external-data hook; повторно вызывать
`EditorInterface.save_scene` из hook нельзя. Recovery хранится только в
`user://ember_world_drafts` и сверяет сцену и source hashes; это не gameplay
Resource и не проектный autosave.

Автоматические `tools/test_world_canvas.gd`, `tools/test_world_editor.gd` и
связанные regressions прошли на checkpoint. Нативные fixtures использовали
отдельный checkout/cache; они не подтверждают удобство камеры, мазка,
Save/Discard/Cancel и игровое ощущение. Ручной сценарий остаётся открытым в
`MIGRATION_TEST_PLAN.md`. Подробные измерения хранить в targeted tests и
`EMBER_SURFACE_LARGE_PROFILE.md`, не размножать здесь.

Не превращать handoff в перечень всех версий инструментов. Актуальные
конкретные возможности подтверждать в коде и targeted tests.

Surface Canvas, Ember Graph, Object Inspector и migration dashboard не получают
общий бесконечный polish: новый editor-срез начинается от конкретного production
workflow, который текущие инструменты не закрывают.

## Exploration и партия

`EmberPlayer` остаётся единственным CharacterBody/controller мира.
Выбранный лидер управляется напрямую; followers являются presentation-проекцией
существующего party state.
`EmberExplorationHeroScale` задаёт временные пропорции exploration-заглушек при
1 блоке = 1 м: Мира 1,5 блока, протагонист 1,8, Орик и Сена по 1,7.
Лидер меняет высоту видимой капсулы и коллизии при смене героя; followers
используют те же видимые размеры. Радиус физической капсулы остаётся 2,5
внутренней единицы на блок 16: увеличение его до ширины заглушки ломало
подъём на ступень 4; полноту силуэта пока даёт visual mesh. Это масштаб
заглушек, не финальный рост арта.

Существуют graybox-системы:
- movement/camera;
- followers и смена лидера;
- inventory/equipment;
- shops;
- HP/consumables/defeat;
- quests;
- action chains;
- dialogue;
- map transitions;
- world ↔ combat handoff.

Native catalogs — основной путь. Оставшиеся `EmberPack` fallbacks удаляются
только вертикальными migration-срезами после parity.

### Проверка взаимодействий27.10 — перед первым сценарием на main

Согласованный вход этого чата: проверить старые осмотр/выбор/предмет/задание,
повторный запуск и save/load, затем определить конкретный пробел authoring UX.
Первичный аудит ещё не имел размещённого примера на `landscape_compact.tscn`.
Теперь там подключена миссия ниже; root `world_canvas.gd` наследует прежний
exploration runtime и его UI. Старый аудит не заменяет проверок нового среза.

Четыре существующих gates через `python tools/run_interaction_tests.py` PASS:
talk/shop, action chain, launch rules, quest state. Синтетические native Resources
и saves изолированы, исходные shared inputs проверены хешами. Настоящая chain
talk → coin reward → flag → wait сохраняется один раз; награда/флаг переживают
reopen. One-shot completion и условия отдельно проверены launch-rules gate.
Native Forward+30FPS action-chain gate PASS; просмотрены настоящие QuestEditor,
choice/reward, inventory и journal widgets при1280×800 в disposable project.
Это API/render-аудит на fixtures, не ручная приёмка ввода/похода по всей main.

Выявлены и устранены два препятствия проверки: `EmberVoxelProp.apply_voxel_light_settings`
допускал PrimitiveMesh к `surface_get_name`; теперь именованные presentation surfaces
обрабатываются только для ArrayMesh ([Godot API](https://docs.godotengine.org/en/stable/classes/class_arraymesh.html#class-arraymesh-method-surface-get-name)).
Нужная runtime coverage texture отсутствовала в disposable package: interaction fixture
даёт нейтральный process-local ImageTexture после проверки sandbox. Это не тест
вида травы, рабочие PNG/импорт/материалы не менялись. Native UI probe дополнительно
копирует `scenes/combat`, поскольку quest counter picker читает существующие encounters.

UX наблюдения: QuestEditor показывает status/objective flags и dependency IDs рядом
с обычными полями; в1280×800 три цели требуют прокрутки. На момент аудита Journal
показывал save keys/тестовый сброс; в миссии ниже они скрыты в обычном режиме.
Inventory сохраняет прежние текстовые колонки, choice — W/S/F подсказку.
При этом ActionChainEditor уже умеет picker событий «начать/выполнить цель/завершить»
и подставляет прежний set_flag; второй event owner или новый quest runtime не нужен.
Это наблюдения текущих виджетов, не принятый новый UX.

Выбранный результат — одна сквозная миссия, правила в GDD → «Послание на берегу».
Текущие механики/main-размещения и новые проверки принадлежат следующему разделу.
Evidence: `C:/Users/novos/Documents/Codex/2026-10-27/ember-interaction-audit/`:
interaction-gates/native-action/native-ui logs, пять PNG, external probe/runner.

### Предметы в мире и бутылка — сквозная проба27.10

Цель автора — **вся** миссия: бутылка → письмо → фигура за домом →3 ракушки →
кабан/инициатива/бой → кожа → возврат/награда. 28.10 автор прошёл всю цепочку
и подтвердил работоспособность. Новая обратная связь ниже ещё требует оценки.
На main размещены MessageBottle на песке около(148,3,212), ShoreKeeper за прежним
CoastalHouse около(-244,13,208),3 ShoreShell на берегу и ShoreBoarZone за домом.
Поле5×5м начинается(-304,12,256), кабан патрулирует вокруг(-248,12,312).
Старая карта не заменялась,
её сторонние изменения сохранены. Фигура — переиспользованный armor stand с
готовым mesh без зависимости от удалённого voxel Source; это временный арт.

Owners:
- `EmberItemResource.definition`: optional `worldScene`, `openContents`, `useScriptId`,
  `useLabelRu`; ItemStore validation и прежний ItemEditor сохраняют эти поля.
  Контейнер и читаемый предмет разделены: либо содержимое, либо событие использования.
- `EmberExploreState`: единственный owner inventory/flags и optional save-v2
  `worldItems`. Старые v2 без этого поля читаются как пустой набор; new game/legacy
  reset и adopt_loaded_save учитывают его. Второго файла прогресса нет.
- `ember_world_items.gd`: чистая проверка записей ID/itemId/mapId/count/position/rotation;
  finite bounds, до4096 записей. Authored count0 сохраняет отсутствие находки;
  подобранные динамические drop-записи удаляются, не накапливая tombstones.
- `ember_world_item_3d.gd`: RigidBody3D/mesh/derived collider, штатная гравитация,
  поза перед save и при сне. Локальная физическая скорость после load начинается
  с нуля. `ember_world_item_interact.gd` использует прежний F/EmberInteract маршрут.
  `ember_item_presentation.gd` — native данные формы/центра/PhysicsMaterial/damping
  у модели; default box сохраняется. Производная Shape3D имеет настоящий размер,
  scale коллизии единичный; общий cache до16 форм, инвалидируется source.changed.
  Очередь release impulse/spin применяется после thaw и очищается restore/carry/
  recovery, не сериализуется. Нового physics/save owner нет.
  Carry/throw/push, масса/размер и radius возврата живут здесь же; исходная поза
  authored items сохраняется в прежних placement settings ExploreScene, не в новом save.
  `ember_world_recovery.gd` — один общий killbox/проверка пропущенного пересечения;
  регистрирует тела один раз и через node_added. ExploreScene возвращает персонажей
  без лечения; WorldItem возвращает себя/очищает carrier/пишет прежний worldItems.
  Weight plate — прежние MechanismComponent/Graph/Circuit/Workspace/Actions; поля
  required_weight/character_weight сериализуются в .tscn. Scope/ручные gates:
  Inspector Design I3.15 «Толкание, бросок и возврат29.10», test_physical_crates.gd.
- Контактное разрушение/первый battle bridge29.10: WorldItem.break_impact_speed и
  throw_damage сохраняются прежними placement settings. Direct-body impulse/mass
  (только breakable, max_contacts8) вызывает прежний deferred receive_world_hit;
  combat_suspended исключает capture/availability/physics/recovery до возврата.
  `ember_combat_world_items.gd` — чистое преобразование того же pickup_id в
  process-local units/holds. Team object/маркер worldItemId проверяется StateSchema;
  нет initiative/outcome, HP1 обозначает целостность, не новую RPG-сущность.
  FieldEncounter захватывает переносимые одноклеточные предметы поля/носителя,
  передаёт начальную копию CombatLab (в том числе Retry), сообщает return positions.
  Prototype считает попадание/промах/land-cell и сохраняет existing held commands;
  pickup без RNG, промах не удерживает предмет. Grid3D проецирует native worldScene,
  тот же arc/break effect. ExploreState.apply_combat_result(victory) нормализует
  worldItems count/poses в общей транзакции до autosave. Scene-swap route, push-only
  props/плиты/таймеры удержания не подключены. Scope/evidence/tests — Inspector I3.15
  «Столкновения ящиков и первый перенос в бой29.10».
  ЛКМ проходит Player._unhandled_input → world_strike → receive_world_hit объекта.
  ExploreState.destroy_world_item атомарно фиксирует отсутствие в прежнем worldItems,
  без inventory/reward и новых полей save. Cosmetic `ember_world_break_effect.gd`
  использует8 заранее собранных meshes, максимум4 активных эффекта/1,1с жизни.
  Source `quest_carry_crate.tres` → `tools/build_crate_break_effect.gd` → производный
  `prefabs/items/quest_crate_break.scn`; bake/source palette/hash проверяет
  test_world_strike.gd. Scope/ручные gates — Inspector I3.15 «Удар и разрушение29.10».
  `ember_leaf_pile.gd` — scene-owned Area/cover, тот же receive_world_hit; player
  body_entered на mask2 вызывает его deferred после query flush, без polling.
  Мониторинг не переключается при reveal/load, повтор/посторонние тела/combat защищены; раскрывает
  прежний authored flag. Готовый WorldItem с available_flag_id скрыт до удара;
  ExploreScene._refresh_world_items остаётся единственным владельцем проекции тел.
  Разметание — flags, подбор — прежний worldItems count0; отдельного spawn/save нет.
  Общий world_break_effect получил параметры lifetime/gravity/launch/radius для
  конкретного leaf preset; прежние crate defaults сохраняются. Leaf branch хранит240
  исходных poses/UV,4 независимых MultiMesh buffers/эффект,9 launch-only terrain rays;
  lifetime2,8с/уменьшение только в конце. Обе leaf сцены используют общий tree shader.
  `vox_painted_maple_autumn` — прежние Source/Recipe/prefab, builder build_autumn_maple;
  Вариант сохранён; `_palette` — двухцветная спокойная окраска старого maple atlas.
  Recipe/Provider optional tree_leaf_secondary_color/tree_leaf_palette_strength →
  tree_surface.settings → Surface.build → общий shader ramp;0 сохраняет прежний вид.
  Поля creation/edit/history/save/validation — прежние owners, Terrain Authoring →
  «Цвет листвы29.10», test_tree_leaf_palette. Main/Props/AutumnMaple/Palette рядом с кучкой.
  Builder/asset/status —
  Inspector I3.15 «Кучка листьев29.10», test_leaf_pile.gd.
- `ember_cuttable_grass.gd` наследует прежний cover/flag/pickup/save путь листьев,
  отключает body monitoring и связывает CutStubble с тем же flag. Builder готовит
  accepted grass cards/общий terrain foliage material, stubble clip только в bake;
  `ember_grass_cut_effect` — прежний cosmetic budget,64 individual blade meshes/4
  MultiMesh buffers, ветер/lifetime0,65с, shrink в конце/без ground rays/physics bodies.
  native material bank выпекается через Forward+, не dummy headless. Existing herb
  получил worldScene `herb_sprig.scn`; stats прежние. Main/Props/CuttableGrass.
  Assets/ограничения/test_cuttable_grass/evidence — Inspector I3.15 «Срезаемая трава29.10».
  Срез01.11:grass-slot main при bake без отдельного tint;пучок/стерня/разлёт используют
  прежний compiled feature program. Runtime не дублирует стоящие meshes/materials;
  gameplay/leaf gates PASS,render-crop/чистый замер/ручная приёмка — World Performance.
- `ember_fruit_tree.gd`: Area strike adapter, повторная crown реакция и однократный
  authored flag → прежний gated WorldItem apple. Per-instance tree_hit_sway в
  tree-card shader/общем surface vertex hook, physics Tween0,65с; bark/mesh/collision
  неизменны, Material не клонируется. Новые apple item/icon/native model и fruit_tree
  prefab, вложенный прежний oak; main Map/Props/FruitTree. Scope/tests/evidence —
  Inspector I3.15 «Дерево с яблоком29.10». GrassPatch всё ещё декоративный: решение
  о массовом скашивании/возврате вида при входе отдельно записано в GDD/World Authoring.
- `ember_berry_bush.gd`: EmberInteract harvest adapter; F → прежний
  ExploreState.exchange_items с completion flag в той же транзакции. Ни второго
  inventory/save owner, ни физических WorldItem на кусте. Полная стопка/lock/repeat
  сохраняют плоды. Leaf/berry visibility следует progress_changed и cold restore.
  Основа — opt-in BushProvider/version7, обычные Source/recipe/EmberVoxelProp.
  Несколько базальных побегов/ветви строятся BranchLayout helpers и хранятся в
  прежнем tree_surface. Shared tree projection получает проверяемые settings
  plant_kind=shrub/shrub_leaf_scale; обычные деревья без них идут прежним путём.
  Fine-only wood не вызывает append пустой coarse surface. Leaf cards/art/shader
  переиспользованы. `ember_voxel_fruit_placement.gd` берёт branch_id/t тонких
  веточек, builder запекает маленькие парные ягоды/короткие плодоножки. Старым
  cloud Sources оставлен fallback по voxels. Нового renderer/save/runtime generation
  нет. Общая редакторская команда урожая и обычный tree
  branch-frame adapter ещё OPEN; live regen плодовых узлов не заявлен.
  Native model/item/icon/builder/main placement/test — Inspector I3.15 «Ягодный куст29.10».
- `EmberExploreScene`: проекция записей в тела текущей карты, восстановление поз,
  проверка наличия поверхности перед выбрасыванием, существующая inventory/action UI.
  WorldCanvas выбирает save context после child-ready: authored pickups регистрируются
  после этого в прежнем exploration setup. Regression фиксирует исчезновение при старте.
- `ember_quest_giver_interact.gd`: выбирает прежний action script по первой доступной
  цели **прежней** QuestCatalog.projection; собственных квестовых flags/state не вводит.
  `available_flag_id` у authored ракушек включает вид/физику/F после согласия помочь.
- Шаг `exchange_items` дополняет прежние ActionScript/Store/ChainEditor/InteractionUi:
  costs/rewards проверяются целиком до изменения inventory. Открытие контейнера
  использует тот же exchange в ExploreState. При недостатке предметов очередь
  останавливается, продолжение notice не выполняет последующие флаги/награды.
  У hand-in flag идёт сразу после exchange **до** благодарственного диалога, чтобы
  Esc на нём не потерял прогресс. Reward-stage отдаёт кожу и получает10 монет один раз.
- `ember_item_counts_editor.gd`: общий выбор предметов/количеств для содержимого
  контейнера и обмена, без текстового JSON. ItemEditor/ActionChainEditor сохраняют
  прежних владельцев записи/истории. Giver mapping пока экспортирован в сцене;
  полная переработка authoring UX ещё не сделана. В обычном журнале скрыты
  будущие заблокированные цели, ключи флагов и сброс; `show_debug_progress`
  оставляет диагностику только для явно включённого режима.

`content/items/shore_*`, `content/quests/shore_message.tres`, `content/action_scripts/shore_*`
и `content/dialogues/shore_*` — обычный авторский контент прежних catalogs. Чтение
письма записывает только read objective; projection сама делает квест активным.
Повторное чтение не откатывает завершённую миссию. Бутылка/пустая бутылка/письмо —
отдельные предметы. Нового крафта нет. Source бутылки —
`art/props/message_bottle/message_bottle.blend`, GLB intermediates в assets;
они `.gdignore`, runtime native meshes/materials встроены в `prefabs/items/*.tscn`.
Ракушка получена из существующего `content/voxel_models/vox_detail_shell.tres` через
прежнюю voxel geometry, исходник не менялся. Три новых художественных облика не заявлены.

Рекомендация физики/сохранения сверена с [Godot RigidBody3D](https://docs.godotengine.org/en/stable/classes/class_rigidbody3d.html)
и [Saving games](https://docs.godotengine.org/en/stable/tutorials/io/saving_games.html):
движение рассчитывает физика, сохраняются идентичность и поза; вводить показанный
в tutorial отдельный save owner вместо ExploreState не требуется.

Боевой вход:
- `ember_shore_boar.gd` — патруль/контакт/ЛКМ и направление удара; собственного
  урона/resolver нет. Кабан появляется после сдачи ракушек, исчезает после победы.
- `ember_field_encounter.gd` — показ прежнего `combat_lab.tscn` дочерним узлом
  текущего мира. ExploreState/CombatTransition сохраняют snapshot/lock/result.
  Оригинальные Map/terrain/environment остаются, exploration actors/HUD временно скрыты.
  Первый authored участок только ровный: лучи проверяют опору/нормали и перепад≤2
  world units(12.5см); при изменённом препятствием участке вход отклоняется.
- Прежний Grid3DWorld скрывает GridMap и отключает его коллизию; линии/актеры
  проецируются на существующую землю. Масштаб16/1.2 даёт выбранную автором клетку1м.
  Camera focus/picking учитывают transform. Новый физический пол не создаётся.
- Initial initiative меняет только nextAt в копии состояния, Retry повторяет правило.
  Начальный ход врага выполняется после подтверждения расстановки без тупика ввода.
- `content/combat/{battlefields,encounters,units,loot_tables}/shore_boar*.tres` —
  прежние native Resources. Пробный low-poly кабан — native prefab примитивов,
  герои в бою пока прежние капсулы. Каталог не добавляет нового врага в baseline:
  Encounter явно передаёт roster прежнему Combat.initial_state.
- CombatResult остаётся owner броска добычи. Transition выдаёт её прежним grant_item
  **до** autosave вместе с победой/XP; внутренние show_item_reward шаги только
  показывают квитанцию, не выдают повторно. Обычные authored give_item не менялись.
  Возврат восстанавливает управление/камеру и позицию лидера по финальной клетке.

Проверки и доказательства — Test Plan → «Послание на берегу27.10».
Автоматическая проверка настоящего боя/ИИ/возврата/кожи/награды PASS на fixture
и сквозным Forward+ API-проходом участка main без замены мира. Выявлены и исправлены
camera transform и видимость полевого врага во время боя; точный scope — Test Plan.
Полное прохождение автором подтверждено28.10. Ощущение инициативы/баланс,
анимации/облики и общий authoring UX отдельно ещё OPEN.

Вторая цепочка28.10 — `harbor_cargo`/«Груз у берега»: один
`prefabs/items/harbor_cargo_quest.tscn` на main/Map/Props/HarborCargoQuest.
Quest/NPC objective_scripts/Dialogue/Action/enter-trigger/WorldItem/settle-zone
используют прежних owners; новых runtime scripts нет. Четыре стадии и3 монеты,
напоминания и done-route не дают повторной награды. Золотая рамка — сохранённая
геометрия по main Surface; изменение рельефа требует её перестановки.
Технические gates и ручная приёмка — Test Plan → «Груз у берега28.10»;
пробелы authoring/следующая рекомендация — Inspector Design → I3.15.

Обратная связь взаимодействий28.10:
- Player._nearest — единый query owner для F и InteractionFocus. Сначала точная
  distance_to_world/region distance/strict12,затем live availability только кандидата,
  который может стать ближайшим. Group order/held priority/live flags сохранены;
  cache/задержка обновления не вводились. Native regressions/performance — Performance owner.
- `ember_interaction_focus.gd` читает прежний Player._nearest: только доступный
  объект на расстоянии F. Derived MeshInstance копии используют source mesh/skin,
  собственный outline material; авторские материалы/mesh/collision не меняются.
  `ember_interaction_outline.gdshader` — inverted hull со смещением в пикселях;
  `ember_interaction_mask.gdshader` пишет union силуэта в stencil reference64,
  outline читает его после маски. Это убирает заливку прозрачной бутылки и
  внутренние швы; depth test контура сохраняется. Подсказка[F] постоянного
  экранного размера над проекцией mesh bounds; сбор, уход, диалог/сумка,
  бой и освобождение объекта очищают focus. Подключение — общий ExploreScene,
  а не отдельные скрипты бутылки/ракушки/NPC.
- `ember_quest_tracker_ui.gd` — read-only текущий доступный этап прежней projection,
  справа над миром; прогресс стадий/новое задание/завершение дают короткий toast.
  При стартовой загрузке показана активная цель без ложного объявления новой.
  Новые quest flags, отдельный save/tracker state или второй журнал не создаются.
- FieldEncounter замораживает контроллеры, но оставляет мир/модели видимыми:
  удар-кольцо → одновременные дуги в клетки0.58с с малым разносом стартов →
  приземление. Камера за0.85с интерполирует прежний мировой вид к перспективному
  виду поля; прозрачный input shield блокирует команды, чёрного покрытия нет.
  Математика дуги переиспользует прежний Grid3DWorld._set_arc_position.
- `PartyFollowers.combat_world_actors()` отдаёт видимых спутников по hero_id;
  лидер — прежний EmberPlayer, враги поля задают combat_unit_id(включая ID
  экземпляров повторяющегося шаблона). FieldEncounter сохраняет эти Node/model
  identities и после прыжка следует за прежними _unit_roots проекции. Клоны
  геометрии соответствующих бойцов скрыты, HP-подписи остаются у общего renderer.
  Поза/риг Хоши не редактируются; body animation пока процедурный перенос,
  отдельного production jump/боевого stance нет.
- `continuousEntry`/`presentation_ready`/`finish_world_entry` связывают прежний
  Lab с показом. До посадки нет команд и AI, в том числе при четырёх героях без
  дополнительной расстановки. Retry сохраняет snapshot/подтверждённые клетки;
  result/loot/save остаются у прежних owners. После возврата binding отключается,
  восстановлены контроллеры/подписи/камера. Вид/темп новой подачи вручную OPEN.
  PackedScene прежнего Lab загружается при подготовке field zone, до контакта.
  Внешний вид перехода с отпрыжками одобрен автором; новые боевые позы/баланс
  этим не утверждены.
- Подбор28.10: `EmberInteract.activate_from(actor)` передаёт прежнему activate
  контекст собирающего персонажа, WorldItemInteract маршрутизирует его в take.
  Inventory/worldItems/autosave фиксируются прежним pickup_world_item до анимации.
  После успешной выдачи ItemVisual переносится в отдельный runtime
  `ember_item_pickup_effect.gd`: дуга0.44с к голове, пауза0.07с, схлопывание0.16с.
  Pivot по mesh bounds сохраняет исходную модель/позу предмета; цель следует за
  движущимся персонажем. У эффекта нет коллизий/интерактива/save state; удаление
  персонажа/сцены отменяет только показ. Отказ выдачи не забирает visual и не
  создаёт эффект; повторный F не выдаёт предмет второй раз.
- Общая `ember_arc_motion.gd` — чистая формула прежней дуги. Grid3DWorld и pickup
  effect используют её без зависимости эффекта от боевого renderer.
  Содержимое бутылки/награды NPC отдельно не анимируются: текущий срез — подбор
  физических WorldItem предметов с земли. Новая подача подбора вручную OPEN.
Основа shader проверена по [Godot4.7 Spatial shaders](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html):
POSITION/VIEWPORT_SIZE/MODELVIEW_NORMAL_MATRIX; screen-space контур не требует
менять основной voxel shader или добавлять второй renderer. Native кадры/проверки — Test Plan.

## Combat Lab

Battlefield остаётся dense: текущая лабораторная нагрузка не обосновывает смену
представления. Lab shell/выбранная тестовая arena_scene и проверки совместимости —
«Общие игровые системы» выше; World projection owner не изменён.

Существующий боевой baseline включает:
- 10×8 и 16×12 fields;
- height-aware movement, Jump, LOS и pathfinding;
- staged action planning;
- единый preview/commit resolver;
- hostile RNG, фиксируемый до commit без раскрытия результата игроку;
- support/heal/items;
- canonical Status/Effect/Action Resources;
- Wet/Frozen/Burning и связанные elemental interactions;
- push, lift, carry, throw и fall;
- positional auto-approach;
- active party 1–4;
- victory/result/XP;
- safe defeat + Retry из точного предбоевого состояния;
- authored prebattle deployment;
- projection-only animation queue.

Player и AI используют общие legality/resolver rules. Projection/HUD не мутируют
battle snapshot.

Новая низкоуровневая боевая операция добавляется только когда её нельзя выразить
существующими Action/Effect/Status контрактами, и требует targeted resolver test.

## Migration / legacy

Migration dashboard и dry-run должны оставаться read-only до успешного parity.
Mutation gates queue/batch запускает `tools/run_voxel_migration_tests.py` в
отдельных временных проектах с синтетическими JSON/VOX fixtures. Прямой запуск
этих двух GDScript-тестов в рабочем проекте блокируется до записи; механизм
миграции и его owners прежние. Подробные проверки — Migration gates в test plan.
Migration dock открывает постоянную полку через `voxel_library_requested`;
неиспользуемый старый popup и его сигнал placement удалены. Добавлением владеют
object-library `place_requested` → plugin → SceneAuthoring; Inspector refresh
и открытие native Resource в dock сохранены. Gates — «Нижняя полка объектов 3D».
Старый неиспользуемый tree-object dialog удалён; plugin продолжает создавать
GenerationPanel. Совместимость classic и текущих recipe, exact preview/save,
параметры и layout проверяют generation_session/workshop_generator_save и
large_tree_object; действующие генераторы/Creation и версии данных сохранены.

На текущем checkpoint остаётся значимый legacy-хвост:
- native voxel Resources существенно меньше legacy-моделей;
- часть prefab ready, часть stale/missing;
- scene-used stale prefab могут менять visual geometry и collision при rebuild.

Generated prefab сам по себе не доказывает canonical ownership.
Forced rebuild разрешён только явной editor-командой или подтверждённой
migration mutation.

Новые вызовы к legacy `EmberPack` запрещены.
Финальный migration gate — запуск без физически доступного sibling JOI.

## Известные долги

Открыты:
- недостаточное покрытие legacy-моделей canonical voxel Resources;
- карты, которые ещё используют legacy terrain вместо physical Surface;
- оставшиеся `EmberPack` loader/catalog fallbacks;
- scene-used stale voxel prefab, требующие visual review перед миграцией;
- отсутствие первого малого полностью сквозного D3 production-участка;
- не закрытый финальный запуск без sibling JOI;
- отдельные manual gates editor/party, точный статус которых нужно сверять
  с более свежим checkout.
- нативная ручная приёмка World Canvas и 3D-редактора ещё не завершена;
  большой радиус, полностью заполненная карта и recovery могут требовать
  отдельного измерения, если мешают работе.

Не переносить старый manual gate в новую задачу автоматически:
если более свежий commit его закрыл или superseded — удалить его из NOW/handoff.

## Проверки

Godot console:
`tools/godot/Godot_v4.7.2-stable_win64_console.exe`

Targeted tests находятся в `tools/test_*.gd`.

Правила:
- fixtures писать в `user://`, не в авторские карты;
- обычные targeted scripts:
  `--headless --path . --script res://tools/test_....gd`;
- рабочий checkout не запускать через `--headless --editor`;
- editor/import smoke выполнять только в отдельном checkout/cache;
- UI/render/physics/input/game feel после headless tests проверять
  в обычном Godot 4 Forward+;
- performance change требует matched baseline, correctness parity
  и повторных замеров;
- Save/editor slice должен проверять Undo/Redo, Save/Reopen, Discard,
  validation и targeted regressions.

Полный актуальный список suites/manual gates — `MIGRATION_TEST_PLAN.md`.

## Маршруты к деталям

- текущая точка — `docs/EMBER_NOW.md`;
- рабочий процесс/Task Contract — `docs/EMBER_WORKFLOW.md`;
- продуктовый порядок — `docs/EMBER_PRODUCT_PLAN.md`;
- игровой дизайн — `docs/EMBER_GAME_DESIGN.md`;
- UI — `docs/EMBER_UI_PIPELINE.md`;
- JOI exit — `docs/EMBER_JOI_EXIT_PLAN.md`;
- Surface performance — `docs/EMBER_SURFACE_LARGE_PROFILE.md`;
- будущие planners, World Layout и биомы —
  `docs/EMBER_WORLD_AUTHORING_ARCHITECTURE.md`;
- regression/manual gates — `MIGRATION_TEST_PLAN.md`;
- специализированные editor-планы — релевантные файлы `docs/`.

Большие документы открывать поиском по релевантным разделам.
Git history хранит завершённую техническую летопись.

## Как обновлять handoff

Добавлять сюда только долговечную информацию:
- owner изменился;
- изменился canonical data flow;
- появился/исчез архитектурный контракт;
- schema/save/runtime boundary реально изменились;
- появился долг, способный повлиять на будущие реализации.

Не добавлять:
- дневник по датам;
- все промежуточные версии одной функции;
- полные benchmark-таблицы;
- списки PASS каждого теста;
- закрытые локальные баги;
- художественную историю итераций.

Текущий feature status и ближайшие шаги принадлежат `EMBER_NOW.md`,
а завершённая история — Git.
