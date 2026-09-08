# Ember Godot — технический handoff

Актуально: 8 сентября 2026. Editor stop-line v2.56.1, gameplay v2.64.4.

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
через общие terrain/resolver rules. Последний измеренный E5 16×12 поиск unit-
целей для auto-approach занимает около 5 мс. Исправленный поиск cell-целей
занимает около 12 мс вместо 378 мс: он ограничен MOVE + authored range и один
раз кэшируется на UI-refresh. Оснований менять dense Battlefield нет.

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
- общий positional auto-approach для непарных hostile/support/heal/item/cell/
  lift-команд: достижимая позиция завершает выбранную команду, а недоход
  останавливает героя и применяет Defend без расхода MP, item или команды;
- cell-target действия подсвечивают только клетки, где эффект выполним в этот
  ход после MOVE; lift-target остаётся на месте до завершения presentation-подхода;
- battle-only связь удержания без новых authored Resources: поднятая цель не
  занимает клетку и пропускает очередь, а носитель получает только синтетические
  `Бросить / Опустить / Удерживать и защищаться`; player и AI используют одну
  legality/preview реализацию.

Projection-only animation queue показывает движение, подъём, дугу броска,
выпад, hit squash и defend pulse после уже рассчитанного preview. Status badges
показывают тип и длительность buff/debuff. Эти проекции не мутируют snapshot.

Единая нативная библиотека `эффекты / умения и магия / герои и существа`
создаёт, дублирует и связывает canonical `.tres`, блокируя save при validation
errors. Новая низкоуровневая операция всё ещё требует реализации и targeted
resolver test; редактор не генерирует gameplay-код.

### Единый ActionPlan поверх v2.64.4 (2026-09-08)

`Grid.action_plan_context` кэширует navigation/movement fields и filters;
`Grid.action_plan` принимает клетку и возвращает `originCell`, `movementPath`,
`destination`, `applicationCell`, `effectCell`, `occupantId`, `cellContent`,
`footprint`, `ok`, `reason`, `commitRule` и приватный `resolved`. Старые
`approach_*_command_preview` — адаптеры этого входа. Выбранная AI-команда
проходит тот же вход с фиксированной позицией; scoring AI не переписан.
Существующий AI pursuit без authored команды сохраняет прежний movement-only
resolver result. Все legality rules остаются в Combat/Terrain, пути — в Grid.

HUD инвалидирует контекст при изменении snapshot или ручной клетки M, а смена
действия выбирает отдельный кэш. Mouse/keyboard cell hover обновляет только план,
подсказку и overlays. 3D переиспользует клеточные overlay meshes/materials;
2D меняет стили существующих кнопок. Hover не вызывает `_refresh()`, rebuild
GridMap/бойцов или polling. Public projection содержит только intent и footprint,
без hit/crit/damage и без зависящих от скрытого исхода cellChanges.

Первый lift-confirm сохраняет неизменяемый план и запускает отдельный Tween
представления поверх тех же unit roots. Подход завершается перед поднятием.
Cancel работает и во время подхода: цель возвращается, носитель идёт по уже
пройденной части маршрута обратно; ранее выбранное M сохраняется. До final
commit snapshot не меняется. Throw/Lower/Hold идут через тот же ActionPlan и
Combat.preview/commit; повторная цель подъёма на стадии броска запрещена.
Action/Effect/Battlefield/save schemas не менялись.

После сигнала завершения presentation HUD показывает существующее круговое меню
у фактической stop-cell носителя только с `Бросить / Опустить / Удержать +
защита`; прежний `CombatLiftChoice` остаётся скрытым. Выход из выбора клетки
броска возвращает это кольцо, а отмена уже из кольца откатывает presentation.
Gameplay resolver и schema этим UI-маршрутом не меняются.

Проверки: `test_combat_action_plan.gd` охватывает классы команд, M в исходной
клетке, revival через клетку, fallback и stale context; `test_combat_lab.gd` —
hover A-B-A, 2D без пересоздания кнопок, 3D без пересоздания units/input,
скрытые поля, lift approach/cancel, включая отмену в середине пути.
Baseline 16×12: cell-query 12.37 ms; после — 12.28 ms. Cached cell ActionPlan
5.04 ms. Forward+ smoke на RTX 5070 подтвердил рендер обоих полей и
обновление overlays; CPU обработчика hover около 9.8/18.1 ms (10×8/16×12).
Замер с ожиданием кадра 29.1/35.5 ms не равен стоимости запроса или среднему FPS.
Пройдено 24/24 combat/battlefield/encounter/party/save scripts (exit 0, без
SCRIPT ERROR/ERROR); после финального UI wiring повторены lab/animation/view.
Основной ActionPlan принят пользователем после ручной проверки в Forward+.
После переноса lift-завершений в кольцо требуется коротко проверить его позицию,
фокус и читаемость мышью/геймпадом.

## Следующий технический срез

Актуальный порядок всегда берётся из `docs/EMBER_NOW.md`. После ручной приёмки
ActionPlan поверх v2.64.4 ближайшие кандидаты — Retry/defeat и deployment. Парные техники остаются
на своём authored-радиусе; их auto-approach не был добавлен скрыто. Текущие
Action/Battlefield/save schemas, один resolver и один navigation owner сохранены.

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
