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
`project.godot` запускает `scenes/fan_town.tscn`; есть sandbox, интерьеры,
`combat_lab` и отдельные terrain/water study-сцены. Это разные уровни готовности.

### Реализованные системы и владельцы

- Карта: `.tscn` владеет композицией, объектами и интерактивными областями;
  `scripts/ember_map_loader.gd` подключает Surface либо compact terrain и проекции.
- Воксельные объекты: `scripts/ember_voxel_model_resource.gd` — исходные данные;
  sculpt model/actions/workspace в `addons/ember_import/` — редактирование,
  генерация и Undo. Меш и физика производны от исходного Resource.
- Земля: `scripts/prototypes/ember_terrain_pilot_resource.gd` — компактные
  колонки высоты, материалов, воды и потока; projection/mesh строят вид и физику.
  `ember_world_editor.gd` маршрутизирует кисти и создание/расширение карты;
  `ember_world_edit_sessions.gd` владеет черновиком, Save и Discard.
- Материалы: `scripts/ember_compact_terrain_pattern.gd` — паттерн 16×16,
  три цвета и параметры поверхности; редактор — compact material pattern dialog.
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
- Найдены 92 voxel `.tres`, 2 dialogue, 13 action, 1 quest, 6 item, 1 shop
  и один encounter (`colored_crossing_demo`). Это инвентарь файлов, не доказательство
  валидности, полноты миграции или готовности главы; бойцы/действия — отдельные Resources.
- Полный Layout/planner дорог, рек и поселений пока относится к архитектурному
  плану. Генераторы объектов и работающие кисти не означают, что он уже готов.
- Ближайший шаг — авторская проба адресной основы/рельефа и контракт разметки;
  приёмка воды/материалов отложена автором. Точный статус и возврат — в NOW;
  последующие результаты — в Product Plan, без автоматического расширения задачи.
- Аудит проверяет исходники и связи, не запускает игру и не подтверждает PASS.
  Живые Forward+ gates воды, editor lifecycle, партии и боевых переходов остаются
  отдельной приёмкой. Отдельные лаборатории не переносить на все карты автоматически.

### Фактическая legacy-граница

Запрет новых JOI-зависимостей действует. Однако целевое «только importer» ещё
не достигнуто: EmberPack при пустом pack_path ищет sibling JOI; runtime catalogs
имеют fallback, а fan_town вызывает hydration legacy regions/cutaway через loader.
Editor dialogue/action stores также сохраняют существующие legacy-записи в JSON
до явной миграции. Полный выход требует G4/G5 из JOI Exit Plan; его нельзя считать
закрытым по наличию native Resources. Старое описание baseline ниже читать вместе
с этим уточнением и актуальным тематическим документом.

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
  и отдельного LOD payload. Projection читает/сохраняет near tile в прежнем бюджете,
  общий MeshLOD worker загружает/сохраняет индексы и ограничивает файлы 512 MiB.
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
  Ограничения, замеры и gates — Water Rendering → «Действующий путь пробы».
  Runtime старт пробных World Canvas продолжает `world_canvas.gd`: экран ждёт
  native projection/physics и `startup_preparation_status()` controller, затем
  создаёт героев, вызывает `initialize_startup_camera()` и открывает управление.
  Фоновые jobs не останавливаются; в 3D экран отсутствует. Ни новый глобальный
  loader, ни смена сюжетного `fan_town.gd` этим срезом не введены.
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
- `scripts/prototypes/ember_terrain_generation_math.gd` — чистый deterministic
  sampler острова/холмов/ridged/приближения эрозии и прежнего creation coast.
  `addons/ember_import/ember_compact_terrain_generation.gd` — bounded job до
  96×96 м, неизменный вход, private sectioned candidate, группы 8×8/шаг высоты 4,
  плавный край с прежней землёй; cancel не пишет source. Лимит высот увеличивает
  только metadata headers; неизменная геометрия не перестраивается из-за ceiling.
  `ember_compact_terrain_generation_dialog.gd` маршрутизирует параметры и явный
  preview; `ember_world_editor.gd` использует прежний edit_region и sessions,
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

- `scripts/ember_map_loader.gd` — загрузка карты и native Surface.
- `scripts/ember_interact.gd`, `scripts/ember_interact_rules.gd`,
  `scripts/ember_interaction_ui.gd` — scene-owned interactions.
- `scripts/ember_action_script.gd` + `content/action_scripts/` —
  canonical action chains.
- `scripts/ember_dialogue_resource.gd` — dialogue data.
- `scripts/ember_quest_resource.gd` — quest data.
- `scripts/ember_item_resource.gd` — item data.
- `scripts/ember_shop_resource.gd` — shop data.
- `addons/ember_import/ember_graph_workspace.gd` — общий content-authoring workspace;
  специализированные панели не получают собственный runtime state.

### Party, save и переход в бой

- `scripts/ember_explore_state.gd` — единственный mutable/save owner мира,
  партии, общей сумки, флагов и прогресса.
- `scripts/ember_party_state.gd` — чистая нормализация, derived stats, XP/level-up;
  самостоятельно ничего не сохраняет.
- `scripts/ember_combat_transition.gd` — guarded world → combat → world transaction.

Save v2:
- три ручных слота + отдельный autosave;
- сохраняет persistent данные всех четырёх героев;
- derived stats пересчитываются;
- миграция старого save сначала создаёт recovery backup;
- удаление save также оставляет recovery-копию.

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
