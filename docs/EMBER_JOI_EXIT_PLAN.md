# Ember — полный выход из JOI

Статус: принято пользователем 2 сентября 2026 года; v2.50 впервые фиксирует
единый read-only baseline G1/G2, v2.51 даёт фильтруемый список всех 263 записей,
а v2.52 после strict dry-run переносит первые шесть sandbox voxel-моделей одной
Undo/Redo batch. V2.53 закрывает physical Surface gate на `agent_sandbox`, а
v2.54 — measured gate на `fan_town`: visual, collision и route heights выводятся
из одного dense Resource. V2.55 после 7/7 strict parity переносит первую
ограниченную партию готовых `fan_town` prefab. Voxel ownership теперь 15 native /
162 legacy; произвольный массовый перенос и
удаление fallback пока запрещены.

V2.56: read-only профиль оставшихся 25 scene-used stale prefab показал реальные
изменения видимых voxel-граней у 25/25 и collision у 18/25. Автоматический batch
не создан; эти модели требуют art review в контексте первой production-зоны
после design Q&A. Это не блокирует stop-line основного редактора и не разрешает
удаление legacy owner.

V2.39: первый explicit height-slice gate закрыт — верхняя плоскость отсечения, closed-cap preview в обоих backend, matching pick/write mask и локальные кисти. Произвольный диапазон слоёв и колонковые операции внутри среза не заявлены. Editor-only состояние не меняет canonical `.tres`. G1 всё ещё требует full-editor lifecycle и масштабирование хранения; G2–G5 не закрыты.

Уточнение G1 на 5 сентября: историческое перечисление v2.00–v2.12 ниже больше не является актуальным остатком кистей. Level/Smooth, slope A→B, shell Raise/Lower, material painting, умный цветовой выбор, отдельная level-fill вода, её tint, bed-only view, перенос world/battle областей, height slices, lifecycle и профиль dense-карты уже реализованы. Shape/Water визуально общие для мира и боя; sandbox и `fan_town` также выводят collision и route heights из той же Surface. Это пока map-level opt-in: остальные карты и G4–G5 не закрыты.

## Конечное состояние

`ember-godot` открывается, редактируется, тестируется и экспортируется без sibling `joi-conductor` и без `ember/pack_path`. JOI/Three/старый sculptor не являются runtime, editor, asset library или content writer. Старый pack хранится отдельно только как архив до завершения сверки и затем может быть удалён без потери игры.

Не переписываем всё одним массовым convert. Каждый домен получает одного Godot owner, visual authoring, runtime parity, save/reopen и тест с намеренно недоступным JOI path. Только после этого его legacy fallback удаляется.

## Владельцы данных

- Карты: `.tscn` владеет композицией, props, regions и interactions. Semantic surface получает один Godot Resource только после sandbox-pilot; он не дублирует scene transforms.
- Voxel-модели: `content/voxel_models/*.tres` (`EmberVoxelModelResource`). Mesh/collision/prefab/thumbnail/MeshLibrary производны.
- Диалоги и цепочки: существующие `content/dialogues/*.tres` и `content/action_scripts/*.tres`; legacy JSON мигрируется через уже существующий native-first catalog.
- Задания, бойцы, действия, AI, encounters и loot: уже Godot Resources.
- Предметы и магазины: существующие native Resources; оставшиеся записи общего legacy catalog переносятся с отчётом.
- VN-фоны и портреты: `assets/vn_*` + native Resources; legacy registries остаются очередью импорта до нулевого остатка.
- Save: Godot остаётся единственным runtime writer. Историческая совместимость формата не является зависимостью от JOI; version bump нужен только при реальном изменении данных.

## Очередность

1. **G1 Voxel ownership/editor.** Native Resource/importer и visual migration queue с Ctrl+Z готовы в v1.98–v1.99. V2.00–v2.12 дают первый style-first shape gate: связный Surface Canvas 4×4, 32-grid, coarse/detail brush, world/battle camera presets, seam-safe frame-budgeted preview, непрерывный drag, time-based bounded Raise/Lower с 1–32 vox/sec, радиусы 1–32, low-latency heightfield draft, overlap-aware caches, coalesced mouse input и непрерывную swept-капсулу без дыр. Hollow-shell остаётся измеримым R&D experiment: она уменьшает filled occupancy, но на fixed array/общем exact mesher пока медленнее и геометрически дороже solid Raise, поэтому не становится новым owner/default. До полного sculpt-gate ещё нужны explicit height slices, Level/Smooth и material-channel painting; chunked world owner проектируется только после ручной приёмки визуального эффекта. Затем parity report, перенос оставшихся моделей и удаление voxel fallback/JOI deep-links.
2. **G2 Content backlog.** Одна общая страница `Миграция контента` показывает legacy/native/missing для dialogue/action/item/shop/VN, умеет открыть owner и переносит по одному либо безопасным batch после dry-run.
3. **G3 Map surface pilot.** Sandbox physical gate закрыт в v2.53, а `fan_town` measured gate — в v2.54: сохранённая Surface проходит 3D paint, collision, height/route query, runtime и save/reopen. Остальной legacy runtime sever относится к G4.
4. **G4 Runtime sever.** Все runtime catalogs становятся native-only. Legacy importers перемещаются в editor-only migration folder и не входят в export.
5. **G5 Physical gate.** Переименовать или временно убрать `joi-conductor`, очистить `ember/pack_path`, запустить headless suite, editor, sandbox, карту, VN, магазин, quest и battle round-trip. После зелёного отчёта архив JOI не нужен проекту.

## Обязательная диагностика

- `legacy remaining`: число и список по каждому домену;
- `native invalid`: Resource, который не проходит validation;
- `reference missing`: scene/document с ID без native owner;
- `derived stale`: prefab/thumbnail/mesh старше source Resource;
- `JOI detached`: тесты проходят при несуществующем pack path.

## Что не делаем

- не поддерживаем двустороннюю синхронизацию;
- не создаём новые Ember-данные в JOI во время миграции;
- не сохраняем абсолютные пути к старому репозиторию в `.tres`;
- не устанавливаем addon, который приносит второй voxel/map/dialogue/quest store;
- не удаляем legacy до checksum/parity и резервной копии.
