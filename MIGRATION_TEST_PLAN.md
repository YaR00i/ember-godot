# Ember — актуальные проверки и migration gates

Статус: рабочая матрица проверок, 8 сентября 2026.

Этот документ отвечает на вопрос «что проверить сейчас». Подробные сценарии
завершённых v1/v2-этапов и старые журналы ручной приёмки можно восстановить из
монолитного Git checkpoint `20685ac`; они не определяют текущий порядок и не
заменяют будущие небольшие checkpoints. Условия окончательного выхода из JOI
принадлежат `docs/EMBER_JOI_EXIT_PLAN.md`.

## Основной принцип

Проверка идёт от узкого к широкому:

1. parse/static contract затронутых файлов;
2. самый узкий `tools/test_*.gd`;
3. связанный suite подсистемы;
4. cross-system regressions владельцев данных;
5. save/reopen, Undo/Redo, discard и validation, если менялся editor;
6. обычный Godot 4 Forward+ для UI, render, physics, input и ощущения;
7. полный headless-набор перед самостоятельным checkpoint.

Скриншот подтверждает композицию, но не клики, focus, input, persistence или
игровое ощущение. Ручная приёмка пользователя обязательна там, где результат
зависит от удобства или визуала.

## Безопасный запуск

Godot console:

`tools/godot/Godot_v4.7.2-stable_win64_console.exe`

Один targeted test:

```powershell
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_example.gd
```

Пакетный repository contract:

```powershell
python tools/test_vox_axes.py
```

Никогда не запускать рабочий checkout через `--headless --editor`: это меняет
editor-themed import variants и вызывает массовый повторный импорт. Editor/import
smoke выполняется только в отдельном checkout или import cache.

Все test fixtures пишутся в `user://` или временные данные. Авторские `.tres` и
`.tscn` не перезаписываются ради теста. Отключённый `addons/at-icons` остаётся
изолирован через `.gdignore`.

## Как выбрать gate

- Документация без изменения контрактов: `git diff --check`, проверка ссылок и
  `python tools/test_vox_axes.py`.
- Resource/schema: validation, normalization, save/reopen и все consumers.
- Editor mutation: model/action test, Undo/Redo, discard, save/reopen и реальный
  Inspector/workspace.
- Runtime state: pure owner test, transition/serialization и запуск сцены.
- Render/physics/input: headless correctness плюс ручной Forward+.
- Производительность: повторяемый профиль на репрезентативной карте до и после;
  schema меняется только при измеренном доказательстве.
- Migration mutation: read-only inventory → strict parity → ограниченная запись →
  Undo/Redo → reopen → frozen-source hash.

## Surface и voxel authoring

Минимальный suite выбирается по затронутому контракту:

- Resource/serialization: `tools/test_native_voxel_resource.gd`;
- selection и masks: `test_voxel_selection.gd`,
  `test_voxel_selection_mask.gd`;
- groups/palette: `test_voxel_groups.gd`, `test_voxel_palette.gd`;
- sculpt/tools: `test_voxel_surface_sculpt.gd`,
  `test_voxel_tools_backend.gd`;
- Canvas lifecycle: `test_surface_canvas_workflow.gd`,
  `test_surface_height_slice.gd`, `test_native_cutaway.gd`;
- large dense profile: `test_surface_large_profile.gd`;
- derived prefab/preview: `test_voxel_prefab_rebuild.gd`,
  `test_voxel_preview_renderer.gd`;
- physical world: `test_world_surface_projection.gd`,
  `test_fan_town_surface_projection.gd`;
- water boundaries/contact: `test_water_contact_boundaries.gd`;
- scale/tile library: `test_voxel_tile_scale.gd`,
  `test_battlefield_tile_library.gd`.

Editor acceptance дополнительно требует:

- одна mutation = одна понятная Undo/Redo-операция;
- Save/Discard/Cancel при выходе и корректный reopen;
- editor-only selection, visibility, camera и slice не попадают в gameplay data;
- мелкий input не запускает полный remesh/reload;
- Surface, world и battle используют одинаковые palette/water границы;
- обычный Forward+ viewport без швов, исчезающих chunks и renderer warnings.

## Graph, Object Inspector и native content

Основные gates:

- `tools/test_graph_workspace.gd` и `test_graph_lifecycle.gd`;
- `test_object_inspector_model.gd`, `test_object_inspector_actions.gd`,
  `test_object_inspector_panel.gd`;
- `test_action_resource.gd`, `test_action_script.gd`,
  `test_action_chain_authoring.gd`;
- `test_dialogue_authoring.gd`, `test_vn_dialogue_resource.gd`;
- `test_quest_state.gd`, `test_quest_journal_authoring.gd`,
  `test_quest_usage_index.gd`;
- `test_item_resource.gd`, `test_shop_resource.gd`,
  `test_shop_persistence.gd`;
- visual catalogs: `test_visual_library.gd`, `test_map_visual_library.gd`,
  `test_voxel_visual_library.gd`, `test_vn_background_library.gd`,
  `test_vn_portrait_library.gd`;
- scene binding: `test_standalone_trigger_authoring.gd`,
  `test_interact_launch_rules.gd`, `test_scene_edit_roundtrip.gd`.

Ручная проверка проводится минимум на 1280×720 и 1600×900, если менялась
компоновка. Нужно проверить mouse и keyboard focus, dirty-draft guard, validation
на конкретном Resource, save/reopen и сохранение scene-owned children после
reimport.

## Exploration, party и save

Основные gates:

- `tools/test_progress_restore.gd`;
- `test_camera_relative_movement.gd`;
- `test_party_save_v2.gd`, `test_party_followers.gd`,
  `test_party_progression.gd`;
- `test_inventory_equipment.gd`, `test_health_consumables.gd`;
- `test_map_transition.gd`, `test_talk_shop.gd`;
- `test_explore_pause_menu.gd`, `test_defeat_respawn.gd`;
- `test_combat_encounter_transition.gd`, `test_combat_result_bridge.gd`.

Обязательные сценарии save:

1. новый старт и три ручных слота;
2. отдельный autosave и metadata без загрузки полного состояния;
3. v1→v2 один раз с byte-identical backup;
4. несовместимая экипировка возвращается в общую сумку;
5. HP/MP/XP/equipment переоткрываются, derived stats пересчитываются;
6. удаление слота требует подтверждения и оставляет recovery-копию;
7. бой получает предбоевой snapshot, Retry начинает с него, результат
   применяется один раз.

Ручной Forward+ gate проверяет смену лидера через `Tab`, оба режима следования,
переход между картами и сохранение/загрузку из реального pause menu.

## Combat

Базовый suite:

- Resource contracts: `tools/test_battlefield_resource.gd`,
  `test_combat_action_resource.gd`, `test_combat_unit_resource.gd`,
  `test_combat_ai_profile_resource.gd`, `test_combat_loot_table_resource.gd`,
  `test_encounter_resource.gd`;
- resolver: `test_combat_prototype.gd`;
- navigation/positioning: `test_combat_grid.gd`;
- controller/HUD: `test_combat_lab.gd`;
- arenas/camera/view: `test_combat_arena_scenes.gd`,
  `test_combat_camera_rig_preview.gd`, `test_combat_vertical_view.gd`;
- animation: `test_combat_vertical_animation.gd`;
- performance: `test_combat_vertical_profile.gd`;
- content/effects: `test_combat_effect_library.gd`,
  `test_combat_personal_actions.gd`;
- inventory/progression: `test_combat_items.gd`,
  `test_party_progression.gd`;
- results/transition: `test_combat_result_bridge.gd`,
  `test_combat_encounter_transition.gd`.

При изменении общей боевой логики сначала запускаются точные targeted tests,
затем все `tools/test_combat*.gd` и соседние Battlefield/Encounter/party/save
gates.

Combat invariants:

- один resolver и один canonical battle snapshot;
- preview и commit используют один зафиксированный результат;
- hostile hit/crit/damage не раскрываются игроку до commit;
- support, healing, movement и mechanisms детерминированы;
- игрок и AI используют одинаковые terrain, range, LOS и path rules;
- одна проходимая высота на колонку, без stacked floors;
- animation/HUD не мутируют gameplay state;
- Retry не сохраняет затраты пробной попытки;
- победный результат и XP применяются ровно один раз.

Ручной Combat Lab gate проверяет поле 10×8 и 16×12, camera axis locks и focus,
mouse/keyboard/gamepad navigation, browse/confirm/target/cancel, auto-approach,
Attack/Defend stop marker, статусы, подъём/бросок и отсутствие исчезновения поля
на допустимом наклоне.

## Lighting и Forward+ gate

Профили света проверяются в порядке `0/2/4/8/12/16`: `8` — production,
`12` и `16` — stress. В Play `F3` показывает active/candidate shadows и
frame/render metrics, `F4` переключает профили. Изменение света, материалов,
воды или derived mesh проверяется на production-профиле и минимум одном stress
профиле; подробный художественный gate остаётся в `LIGHTING_GATE.md`.

Механики проверяются на Ember-сценах, а не на `hu_tao_yard`/`hu_tao_p1`.
Forward+ проверка должна подтвердить отсутствие shader/renderer errors,
исчезающих chunks, неверной прозрачности и изменений collision из-за
visual-only эффекта.

## Активный gate: следующий positional slice

До реализации точный Task Contract сверяется с `docs/EMBER_NOW.md` и GDD.
Минимальная приёмка следующего кандидата:

1. непарные support/heal/item/cell/lift-команды используют тот же positional
   planner, что hostile-команды;
2. hover показывает range и возможную stop-cell, confirm открывает targeting,
   cancel возвращает прежний focus;
3. если применение недостижимо за MOVE, герой останавливается на предельной
   клетке и защищается без расхода MP/item/выбранного действия;
4. подъём может завершиться удержанием; связь живёт только в battle snapshot;
5. удерживаемую цель нельзя атаковать, она пропускает ход без накопления;
6. носитель не перемещается и выбирает только `Бросить`, `Опустить` или
   `Удерживать и защищаться`;
7. после выбора lift-цели UI предлагает `Бросить сейчас / Оставить поднятой`;
   немедленный бросок только затем открывает выбор клетки приземления;
8. гибель носителя детерминированно опускает цель на ближайшую допустимую клетку;
9. stale preview не может списать ресурс или применить результат;
10. AI и player route не расходятся;
11. schema Action/Battlefield/save и owner resolver не меняются.

Удерживаемая цель исключена из обычных direct/cell/AOE/status effects. Носитель
получает эффекты штатно, они не переносятся на удерживаемого бойца, а гибель
носителя освобождает цель. Gate проверяет прямую, клеточную и площадную попытку.

Минимальные автоматические gates: `test_combat_grid.gd`,
`test_combat_prototype.gd`, `test_combat_lab.gd`, `test_combat_items.gd`,
`test_combat_personal_actions.gd`; затем весь combat suite и соседние
transition/party/save tests. Ручная приёмка — обычный Forward+ Combat Lab на
обоих размерах поля.

## Migration gates

### G1/G2 — content ownership

- `tools/test_content_migration_report.gd` и
  `test_content_migration_dashboard.gd` остаются read-only;
- `test_migration_workflow_layout.gd` проверяет bounded editor layout;
- `test_voxel_migration_queue.gd` проверяет bounded candidate selection;
- `test_voxel_migration_batch.gd` проверяет mutation/Undo/Redo;
- sandbox parity/batch: `test_voxel_sandbox_migration_parity.gd`,
  `test_voxel_sandbox_native_batch.gd`;
- `fan_town` parity/batch: `test_voxel_fan_town_ready_migration_parity.gd`,
  `test_voxel_fan_town_ready_native_batch.gd`.

Любой новый batch требует точного списка, strict read-only parity, visual review
реальных изменений, ограниченной записи и подтверждения, что frozen JOI source
остался byte-identical. Ready/stale/missing prefab не равны ownership.

### G3 — physical Surface

`test_world_surface_projection.gd`, `test_fan_town_surface_profile.gd` и
`test_fan_town_surface_projection.gd` подтверждают visual/collision/height/route
из одной Surface. Dense storage меняется только после нового измеренного профиля.

### G4/G5 — выход из JOI

Новые runtime-вызовы `EmberPack` запрещены. Существующие fallback удаляются
вертикально после native parity затронутого домена. Финальный gate запускает
проект с физически недоступным sibling `joi-conductor` и проверяет основные
карты, interaction/content catalogs, save/reopen и бой. Полные критерии — в
`docs/EMBER_JOI_EXIT_PLAN.md`.

## Полный checkpoint gate

Перед самостоятельным Git checkpoint:

1. `git diff --check`;
2. `python tools/test_vox_axes.py`;
3. каждый `tools/test_*.gd` отдельным headless-процессом;
4. повтор targeted suites после любого исправления, найденного полным прогоном;
5. обычный Forward+ на изменённых сценах;
6. ручная приёмка пользователя, если она входит в Task Contract;
7. обновлённые GDD/handoff/`EMBER_NOW.md` без журнала промежуточных версий.

Если обязательный gate недоступен, результат помечается `degraded`: указывается
точная причина, что уже доказано и какое ручное действие осталось. Ошибка в
неизменённой подсистеме не скрывается, но отделяется от regressions текущего
среза доказательством baseline.
