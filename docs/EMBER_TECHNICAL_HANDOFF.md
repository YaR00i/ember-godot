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
- Voxel schema — 6; compact terrain читает плотную schema 1 и адресную schema 2,
  16 колонок на блок. Schema 2 хранит созданные участки 24×24 м внутри того же
  Resource, без плотных корневых каналов. Потоковая загрузка ещё не реализована.
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

## Карта owners

### Voxel data, Canvas и Surface

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
  До 12 образцов существующей истории `EmberWaterContact3D` задают расходящиеся
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
  wave-equation отклика неподвижных Box/Cylinder контактов. Непроницаемые границы,
  CFL substeps и поглощающий край; четыре ограниченных поля, общий solver для
  live и baked playback. RGBAF atlas хранит периодический отклик/высоту/возраст
  пены/маску; SHA-256 кэш в user:// не заменяет авторский Resource и пока не
  включён в export. Во время подготовки работа разбита на кадры. Shader include
  `ember_compact_wave_obstacles.gdshaderinc` читает поле для высоты/нормали/пены;
  `set_wave_obstacles` добавляет ту же поправку к query без remesh/revision колонок.
  Средняя форма земли, dry-bank coverage и wet-sand state этим solver не меняются.
  Sea leaf отдаёт incident height через ту же `wave_profile`, что использует
  advance; морской shader/CPU отклик синхронизирован с clock морского поля.
  Речной incident описывает главный периодический фронт; мелкая фазовая вариация
  и дополнительные открытые морские волны не решаются этим ограниченным leaf.
  Mode/strength принадлежат прежнему scene controller и World Look/F6 snapshot;
  OptionButton обслуживает enum, snapshot отвергает дробный выбор. Runtime движение
  приостанавливает статический отклик, а не пишет новую bake texture каждый кадр.
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
- `scripts/ember_terrain_plan_resource.gd` — scene-owned authoring plan v1–v8,
  metadata Map `_ember_terrain_plan`, Rect2i в метрах + name/id/generator parameters.
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
  Объекты: optional `EmberVoxelModelResource.material.object_surface` v1 хранит
  default/overrides palette ролей stone/bark/foliage/crystal/ice/glass/legacy; schema 6
  сохранена. `ember_voxel_material_profiles.gd` — чистый владелец enum/preset/
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
  defaults/presets/validation; explicit fields перекрывают профиль; schema6 прежняя.
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
  для filesystem refresh после публикации; он не владеет source data.

Перед добавлением нового editor owner сначала искать существующие Canvas,
generation, placement, publication и scene-authoring пути.

### Exploration, interactions и content

- `scripts/ember_explore_scene.gd` — общий scene play controller: player, party,
  UI и переходы. `world_canvas.gd`/`test_pier.gd` добавляют свой bootstrap/storage,
  но не второй gameplay owner. Перенесён из fan_town без изменения body/UID;
  старые города пока используют тот же controller до content retirement.
- Inspector использует resolved native source owner: `.tres` показывает как
  Godot Resource, Asset tooltip направляет в мастерскую; legacy остаётся явно
  историческим источником до retirement. Snapshot read-only, native label gate
  проходит с недоступным pack path. Map/region validation ещё требует native среза.
- `scripts/ember_map_loader.gd` — загрузка карты и native Surface.
- `scripts/ember_interact.gd`, `scripts/ember_interact_rules.gd`,
  `scripts/ember_interaction_ui.gd` — scene-owned interactions.
  Общие talk/shop/action/launch/quest проверки теперь используют native fixtures
  через `tools/run_interaction_tests.py`, без city/story fixtures. Editor store
  writers в этих tests ограничены disposable проектом; production owners/schema
  не менялись в interaction cleanup. Native/source/save gates PASS; item/shop
  readers больше не требуют compatibility JSON, полный G4/G5 этим не закрыт.
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
- `ember_game_systems_workspace.gd` — общий browser/search/detail/links/commands.
  Один раздел item с фильтрами; route equipment — alias item + equipment filter,
  не второй экран/каталог. Create учитывает тип фильтра, Save сменившего тип
  предмета снимает несовпадающий фильтр. Dirty filter guard сохранён. В draft
  список скрыт, «К библиотеке» возвращает список/фильтры. Отсутствующая связь не открывает
  другую запись; пустой поиск очищает actionable selection.
- `ember_game_systems_session.gd` — один detached draft, local field Undo/Redo,
  validation, file SHA/live source conflict и stable ID guard. Publication/Delete
  snapshots фиксируются в EditorUndoRedoManager GLOBAL_HISTORY: контекст именно
  RefCounted, а не built-in Resource, чтобы история не привязалась к сцене.
- `ember_game_systems_store.gd` — publication adapter к существующим typed
  Resources/ItemStore; не runtime owner/schema. clone использует Godot
  duplicate_deep(INTERNAL): встроенные rows/arrays независимы, external refs общие.
  Save сохраняет UID, Undo/Redo восстанавливают точные bytes; CACHE_MODE_REPLACE
  обновляет published resource, catalog refresh — derived lookup. Delete сохраняет
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
  Effect steps — ordered shared Resource refs с descriptions и duplicate guard;
  Unit action_ids — ordered named picker, missing IDs доступны для удаления.
  Old queued form игнорирует session.changed чужого draft; publisher/Undo owners
  прежние. UI не меняет Resource schema, боевую математику или authored loadouts.
  Unit/AI/Loot/Encounter формы и карточки читают behavior_summary существующих
  Resources. ИИ задаётся stable ID; loot/field/arena — прежними shared refs.
  Каталожные pickers сохраняют текущие external/inline refs и missing IDs;
  continuation picker использует прежние native action-script IDs.
  Один ordered ID list ведёт action assignment и rosters; сторона фильтруется
  только в предложениях, сохранённое не удаляется молча. Повтор Unit ID запрещён
  существующей validation; points/order принадлежат Encounter/Battlefield.
  Loot rows: item picker + chance/min/max SpinBox, copy-on-edit внутренней строки;
  numeric history объединяется по row/key, не затрагивая shared table source.
  Encounter validation допускает только два существующих outcome enums.
  Unit/AI/result/save owners и распределение XP/loot не менялись.
- `ember_game_systems_lab_launcher.gd` — editor process adapter: saved native
  Encounter path → OS.create_process прежнего combat_lab.tscn, без project settings
  или author writes. Одно отслеживаемое окно, 1600×900/30 FPS, отдельный log.
  Workspace не запускает dirty draft; preflight валидирует saved record, runtime
  повторяет проверку. Marker EMBER_LIBRARY_LAB_READY подтверждает consumed ID.
  `EmberCombatTransition` парсит единственный --ember-library-encounter=res://...
  под native encounters root; normal transition/finish в test mode запрещены.
  `ExploreState._ready` до чтения saves отключает persistence/restore и назначает
  process-private paths; Lab не берёт party/inventory/strategy из игрового save.
  `_library_test` — process/UI context, не Resource/save schema. Same Lab/resolver/
  Result считают бой/награду. Test outcome предлагает Retry/Close, скрывает Load,
  не применяет counters/XP/items/scripts и не возвращается на карту. Нормальный
  игровой режим сохраняет переход/поражение/reward path. Общая Lab 3D сцена
  проецирует выбранное Battlefield; декоративный arena_scene не подставляется.
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
  live catalogs при проверке. Current saved library: 71 records / 0 issues;
  malformed fixtures и native navigation QA проверены, user/narrow/125% OPEN.
- `EmberCombatStatusResource` владеет default_duration/reapply/max_duration,
  power_bonus/outgoing_damage_percent/incoming_damage_percent/remove_on_damage.
  Neutral defaults сохраняют baseline. `StatusRules` исполняет общий повтор,
  множители и снятие; DamageRules и единственный CombatPrototype вызывают их.
  Runtime snapshot остаётся ID → remaining turns, decay в конце своего действия.
  Apply effect duration 0 использует default до сокращения устойчивостью.
  Authored apply/remove соблюдает порядок шагов; старое потребление guard
  сохраняет baseline. Commit отклоняет новый preview при смене statusRulesHash;
  StateSchema/apply validation блокируют некорректную native definition.
  Power относится к damaging action, outgoing — scaled direct damage; incoming
  применяется к итоговому damage перед guard. Особые реакции пяти ID прежние;
  periodic damage, independent stacks и новые elemental semantics не реализованы.
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
  Новый layout принадлежит прежним Equipment/Party/
  Explore owners. MOVE/JUMP/knockback/wet modifiers обуви ещё не реализованы.
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

Склейка/разбор сохраняют `ember_voxel_merge_session.gd`/`ember_voxel_merge.gd`:
математика, validation, публикация native assets и один Undo прежние. Один
`ember_voxel_merge_dialog.gd` служит обоим режимам; `use_dock_layout()` отделяет
параметры/preview от прежнего shape controller. `_merge_workspace`/нижняя «Склейка»
зарегистрированы в общем host без нового mode flag. Controls создаются один раз,
`open_merge` привязывает selection/scene/mode; `matches_context` сохраняет session
при повторе команды. Checkbox/primary input лишь инвалидирует dock candidate,
prepare явный; view-only orientation/orbit не меняют session, UPDATE_WHEN_VISIBLE.
Plugin `can_commit` callback сохраняет Canvas dirty guard и при nonmodal Apply;
source/hierarchy/physics stale проверяет прежний session. Cancel освобождает
session/selection/root/undo/preview, controller остаётся для повторного открытия.
Legacy modal вызов используется только старым API/fixtures, второго renderer нет.
Большой prepare/commit остаётся синхронным; source/prefab overrides только fixtures.

Split/conversion используют тот же host и наследуемый shape controller, без
дополнительных mode flags. `pin_preview_action()` закрепляет подготовку для
merge/split/conversion; старый modal API остаётся только для compatibility.
`ember_voxel_split_dialog.gd` создаёт controls один раз, хранит bound weak target;
input убирает splitter/preview, явный prepare вызывает прежний `ember_voxel_object_split`.
Текущие границы/каналы/physics и одна Undo/asset publication не менялись.
`ember_voxel_conversion_dialog.gd` сохраняет bound primitive, единственный compare
control и прежний `ember_voxel_primitive_conversion`: fit, material/physics/stale
validation, original replacement и Canvas owner прежние. Density input масштабирует
XYZ через прежнее правило и инвалидирует оба preview; смена типа требует reopen.
`plugin.gd::_voxel_canvas_is_clean` — общий nonmodal prepare/Apply guard трёх операций.
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

## Combat Lab

Battlefield остаётся dense: текущая лабораторная нагрузка не обосновывает смену
представления.

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
