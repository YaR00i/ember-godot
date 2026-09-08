# Ember Godot — технический handoff

Актуально: 8 сентября 2026. Editor stop-line v2.56.1, gameplay v2.64.2.

Документ описывает текущее устройство, owners и реальные долги. Полный прежний
текст можно восстановить из монолитного Git checkpoint `20685ac`; это не
детальная цепочка исторических commits. Журнал каждой версии здесь больше не
ведётся. Ближайшая задача находится в `docs/EMBER_NOW.md`.

## Источники правды

Этот репозиторий владеет runtime, Godot editor plugins, сценами и новым
контентом Ember. `../joi-conductor` — временный read-only архив legacy pack для
явного одноразового импорта. Новые механики, модели, карты и решения создаются
здесь.

Канонические документы:

- текущая точка: `docs/EMBER_NOW.md`;
- продукт и порядок: `docs/EMBER_PRODUCT_PLAN.md`;
- игровой дизайн: `docs/EMBER_GAME_DESIGN.md`;
- рабочий процесс: `docs/EMBER_WORKFLOW.md`;
- выход из JOI: `docs/EMBER_JOI_EXIT_PLAN.md`;
- автоматические и ручные gates: `MIGRATION_TEST_PLAN.md`;
- editor UX: `docs/EMBER_EDITOR_UX_AUDIT.md`;
- addons и ownership: `docs/EMBER_ADDONS.md`.

## Неподвижные технические границы

- Godot 4 Forward+ — единственный runtime и authoring target.
- Карты принадлежат `.tscn`; canonical voxel-модель —
  `content/voxel_models/*.tres` (`EmberVoxelModelResource`). Mesh, collision,
  thumbnail, prefab и MeshLibrary являются производными данными.
- Не создаются второй renderer, voxel editor, combat resolver, gameplay owner
  или параллельная schema.
- Preview и commit используют один расчёт. Editor-only selection, overlays,
  camera и layout не сериализуются в gameplay Resource.
- Collision, высота и navigation игрока/AI читают одну физическую поверхность.
- Legacy JOI читается только importer-ом; новые runtime-зависимости запрещены.

## Карта owners

### Voxel Surface и производные данные

- `scripts/ember_voxel_model_resource.gd` — canonical palette, voxels, groups,
  water/fill и schema Surface.
- `addons/ember_import/ember_voxel_sculpt_model.gd` — чистая editor-модель;
  `ember_voxel_sculpt_actions.gd` — mutation/Undo; workspace только связывает UI.
- `scripts/ember_voxel_surface_mesher.gd` и
  `scripts/ember_voxel_surface_materials.gd` — visual projection.
- `scripts/ember_voxel_surface_physics.gd` и
  `scripts/ember_voxel_surface_projection.gd` — collision, height и world sample.
- `content/world_surfaces/<map_id>_surface.tres` — canonical world Surface;
  `content/combat/surfaces/*.tres` — visual Surface боевого поля.

### Exploration, interactions и content

- `scripts/ember_map_loader.gd` — загрузка карты и нативной Surface.
- `scripts/ember_interact.gd`, `ember_interact_rules.gd` и
  `ember_interaction_ui.gd` — scene-owned binding и запуск взаимодействия.
- `scripts/ember_action_script.gd` — runtime action chain; `.tres`-источники
  находятся в `content/action_scripts/`.
- `scripts/ember_dialogue_resource.gd`, `ember_quest_resource.gd`,
  `ember_item_resource.gd` и `ember_shop_resource.gd` — canonical Resources
  соответствующих систем. Их catalogs остаются native-first.
- `addons/ember_import/ember_graph_workspace.gd` — единый крупный authoring
  workspace; специализированные editors/inspectors не владеют runtime state.

### Party, save и переход в бой

- `scripts/ember_explore_state.gd` — единственный mutable/save owner мира,
  партии, общей сумки, флагов и прогресса.
- `scripts/ember_party_state.gd` — чистая нормализация, derived stats, XP и
  level-up; он ничего не сохраняет самостоятельно.
- `scripts/ember_combat_transition.gd` — guarded-транзакция мир → бой → мир.
  Бой получает глубокую копию предбоевого состояния и возвращает результат один
  раз.
- Save v2 хранит три ручных файла и отдельный autosave в
  `user://ember-save-v2/ember_p1/`. Для каждого из четырёх постоянных героев
  сохраняются level, XP, текущие HP/MP и пять слотов экипировки; derived stats
  пересчитываются.
- Одноразовая v1→v2 миграция сначала делает byte-identical backup. Удаление слота
  также оставляет recovery-копию в `deleted_saves`.

### Combat

- `scripts/prototypes/ember_combat_prototype.gd` — единственный pure resolver,
  command preview/commit и stale-result guard.
- `scripts/prototypes/ember_combat_terrain.gd` — общая математика высоты,
  distance, LOS и terrain reactions.
- `scripts/prototypes/ember_combat_grid.gd` — dense Battlefield navigation,
  reachable/path, staged movement и positional planning.
- `scripts/prototypes/ember_combat_lab.gd` — controller команды, targeting и HUD.
- `scripts/prototypes/ember_combat_grid_3d_world.gd` и представления grid —
  projection/animation, а не второй gameplay owner.
- `scripts/prototypes/ember_combat_action_resource.gd`,
  `ember_combat_effect_resource.gd`, `ember_combat_unit_resource.gd`,
  `ember_battlefield_resource.gd` и `ember_encounter_resource.gd` — authoring
  contracts; экземпляры находятся в `content/combat/`.

## Текущее состояние editor и Surface

Surface Canvas поддерживает палитру, локальную кисть и пипетку, selection,
именованные/цветные группы, editor-only visibility, 3/5/7 palette ramps,
height slice, region editing, sculpt, water fill, bottom-only view, chunk preview,
Undo/Redo и guarded save/discard/reopen.

Большая 24×24 Surface измерена на реальном dense Resource. Sparse-aware
heightfield, editor-only cache и native chunk backend ускорили hot paths без
смены schema. Подтверждённый профиль sandbox:

- dense channels: 9.84 MiB;
- load около 0.80 с, save около 0.13 с;
- synchronous Canvas open около 0.12 с вместо 0.79 с;
- group filter около 0.019 с вместо 0.71 с;
- exact chunk около 5.9–6.6 мс вместо 25.5 мс.

Оснований для sparse/chunk persistence нет. Воспроизводимый gate —
`tools/test_surface_large_profile.gd`, подробности —
`docs/EMBER_SURFACE_LARGE_PROFILE.md`.

`agent_sandbox` и `fan_town` используют одну physical Surface для visual,
collision и route heights. `fan_town` 32×32 хранит около 12 MiB voxel bytes;
load 1.0–1.3 с и save 0.14–0.17 с не обосновывают новую schema. Native mesher
обслуживает сухие чанки; water-bearing chunks сохраняют точную full-map
координатную проекцию шейдера без швов. Новая физика заменяет legacy collision
атомарно после полного rebuild.

Surface Canvas, Ember Graph, Object Inspector и bounded migration dashboard
находятся на stop-line. Общий polish не продолжается без конкретного production
workflow, который текущие инструменты не закрывают.

## Текущее состояние миграции G1/G2/G3

Read-only report и dashboard показывают ownership, состояние prefab, usage и
ошибки без записи canonical content. Strict dry-run сравнивает occupancy,
metadata, mesh arrays и collision до разрешения ограниченной batch mutation.

Текущий voxel ownership: 15 native / 162 legacy. Derived baseline: 63 ready /
25 stale / 88 missing. Шесть используемых sandbox-моделей и семь ready-моделей
`fan_town` перенесены ограниченными Undo/Redo batches. Остальные 25 scene-used
stale prefab меняют видимые грани, 18 — collision, поэтому их нельзя
пересобирать вслепую; это будущая visual review по необходимости production-зоны.

`ensure_saved()` идемпотентен для актуального prefab. Принудительный rebuild
разрешён только явной editor-командой или подтверждённой migration mutation.
Отключённый `at-icons` изолирован через `.gdignore`; автоматизация не запускает
live checkout с `--headless --editor`.

## Текущее состояние партии и exploration loop

Партия постоянна: протагонист, Мира, Орик и Сена. В мире выбранный лидер остаётся
единственным controller, а трое спутников — presentation-проекция безопасного
пути. `Tab` меняет лидера, `T` переключает живую формацию и «паровозик»; это
session-only state и не расширяет save v2.

Inventory/equipment, shop, HP/consumables, quests, action chains, dialogue и
переходы между картами существуют в graybox. Нативные catalogs являются
основным путём; оставшиеся `EmberPack` fallback удаляются только вертикальными
миграционными срезами после parity.

## Текущее состояние Combat Lab

Два dense-поля 10×8 и 16×12 используют одну проходимую высоту на колонку. Jump,
height-aware range, LOS, падение, толчок, подъём/бросок, pathfinding и AI проходят
через общие terrain/resolver rules. Последний измеренный E5 16×12 поиск целей
для auto-approach занимает в среднем около 4.73 мс; оснований менять dense
Battlefield нет.

Бой поддерживает:

- постоянную партию, STR/MAG/DEF/RES/SPD/ACC/LUCK, derived EVA/CRIT, HP/MP,
  equipment, XP/level-up и возврат результата в save v2;
- единый hostile RNG, зафиксированный в preview и применяемый без reroll;
  попадание, крит и урон не раскрываются игроку до commit;
- детерминированные поддержку, лечение, предметы, механизмы и устойчивости;
- Wet, Frozen, Burning, пар/проводимость, Землю и Ветер через reusable
  `effect → action → unit` Resources;
- три личных направления каждого героя и две authored парные техники с
  фиксированным партнёром, радиусом, общей MP-ценой и задержкой;
- предмет из общей сумки за полный ход с точным списанием одного stack;
- равный XP всем четырём героям, сохранение дефицита HP/MP и возврат павшего с
  1 HP после победы;
- поэтапный UI `browse → confirm action → target → commit`, корректный cancel и
  адаптивный список `Умения / Магия / Предметы` рядом с основным кольцом;
- свободный плавный yaw при заблокированном pitch по умолчанию, отдельный
  orthogonal toggle, независимые axis locks, authored camera values и отсутствие
  mouse-wheel zoom во время боя;
- общий auto-approach для ближней/дальней hostile-команды: достижимая позиция
  завершает атаку, недоход останавливает героя и применяет Defend без расхода
  выбранной атаки.

Projection-only animation queue показывает движение, подъём, дугу броска,
выпад, hit squash и defend pulse после уже рассчитанного preview. Status badges
показывают тип и длительность buff/debuff. Эти проекции не мутируют snapshot.

Единая нативная библиотека `эффекты / умения и магия / герои и существа`
создаёт, дублирует и связывает canonical `.tres`, блокируя save при validation
errors. Новая низкоуровневая операция всё ещё требует реализации и targeted
resolver test; редактор не генерирует gameplay-код.

## Следующий технический срез

Актуальный порядок всегда берётся из `docs/EMBER_NOW.md`. Ближайший кандидат —
расширение существующего positional planner на непарные support/heal/item/cell/
lift commands и battle-only удержание поднятой цели. Парные техники остаются на
своём authored-радиусе и не входят в этот срез. Точный UI-порядок после lift-цели
и запрет обычных direct/cell/AOE/status effects по удерживаемой цели зафиксированы
в GDD. Это ещё не реализовано и не разрешает второй resolver или изменение
schema.

## Известные долги

- Нативных voxel Resources значительно меньше legacy-моделей; generated prefab
  не доказывает ownership.
- Physical world Surface есть у sandbox и `fan_town`, battle Surface — у
  `colored_crossing`; остальные карты ещё используют legacy terrain.
- Несколько catalog/loader классов всё ещё используют `EmberPack`; новые вызовы
  туда запрещены.
- 25 scene-used stale voxel prefab требуют visual review перед миграцией.
- Поражение/Retry и предбоевая расстановка ещё не закрыты production-правилами.
- Первый малый сквозной D3-участок ещё не собран.
- Финальный запуск без физически доступного sibling JOI не пройден.

## Проверки

Godot console: `tools/godot/Godot_v4.7.2-stable_win64_console.exe`.
Targeted scripts находятся в `tools/test_*.gd`; fixtures сохраняются в
`user://`, авторские карты не перезаписываются. Актуальные suites и ручные gates
перечислены в `MIGRATION_TEST_PLAN.md`.

Рабочий checkout нельзя запускать через `--headless --editor`. Изменения UI,
render, physics, input и игрового ощущения после headless gates проверяются в
обычном Godot 4 Forward+.
