# Редактор
Обновлено: 2026-10-22. Активность: на паузе; активная цель NOW — сборка единой карты.

## Цель
Править объекты, карту и игровой контент в существующем native Godot editor с понятным preview,
Undo/Redo и сохранением; панели не создают второго владельца данных или runtime.

## Владельцы
- `addons/ember_import/plugin.gd` — вход; в той же папке `ember_voxel_sculpt_workspace.gd`,
  `ember_voxel_sculpt_model.gd`, `ember_voxel_sculpt_actions.gd` — объектная мастерская, модель и команды.
- Там же: `ember_voxel_model_store.gd`, `ember_voxel_object_session.gd` — публикация Source и сессия;
  `scripts/ember_voxel_model_resource.gd`, `content/voxel_models/*.tres` — данные, prefab производный.
- `addons/ember_import/ember_world_editor.gd`, `ember_voxel_stamp_panel.gd` в той же папке — мир и штампы;
  `scenes/*.tscn`, `content/world_terrains/*.res` — карта и компактная земля.
- В той же папке addon: `ember_compact_material_pattern_dialog.gd` — Pattern;
  `ember_graph_workspace.gd`, `ember_object_inspector_panel.gd` — граф и Inspector.
- Там же: `ember_game_systems_workspace.gd`, `ember_game_systems_session.gd`, `ember_game_systems_store.gd` —
  библиотека/draft/запись; gameplay Resources остаются у game-systems/combat.

## Принято автором
- Панель поверхности прохода, voxel-кисти и устранение левитации над балкой — 13 сентября:
  [Test Plan](../../MIGRATION_TEST_PLAN.md) → «Поверхность прохода (ручная приёмка подтверждена…)».
- Общие кисти, параметры и наведение: [NOW](../EMBER_NOW.md) → «Точка возврата к инструментам»;
  это не приёмка обоих следов/каналов и полного цикла всех инструментов.
- Общее «все новые редакторы приняты» в NOW/GDD/Handoff/Test Plan не подтверждено;
  Handoff → «Известные долги» оставляет ручную приёмку World Canvas/3D открытой.

## Сделано без приёмки
- Сглаживание/round/protect/clear и smooth-рельеф в прежних командах; native Undo/Redo/save/reopen/discard PASS
  записаны в NOW → «Точка возврата к ручным правилам формы»; личные мазки/стыки/ощущение OPEN.
- Библиотека игровых систем и combat UI при 125% проверены технически, свой ввод OPEN:
  [NOW](../EMBER_NOW.md) → «Точка возврата к игровым системам».
- `d9e33a9` — shape/material workflow; `41247dd` — деревья в мастерской;
  `0476913` — последующие workspace/generator/store и UI-правки; checkpoint не является приёмкой.
- На входе tracked-правок нет; тесты и native editor в этом документационном проходе не запускались.

## Открыто
- Свои Undo/Redo/save/reopen/discard, оба следа/каналы, narrow 1280×720/125%, thumbnail cache,
  создание/расширение и live опора: NOW → «Точка возврата к инструментам».
- Pattern UI gate 302/326px, швы, weak-PC; игровые формы/input — в собственных gates.
- Нет команды создания `solid_surface` из частей: workspace сохраняет/восстанавливает уже существующие данные,
  публикует их пока `tools/publish_rock_shape.gd`. «Не умеет создать» не означает «не умеет сохранить».
- Причины исходных native AV/shutdown и GPU TDR OPEN; поздний успешный запуск не является crash fix.
- Большой размер workspace сам по себе не обосновывает разбиение без конкретного симптома/контракта.

## Где остановились
Выбрать один незакрытый сценарий на `landscape_compact` либо fixture 4×4/5×4, сверить gate темы;
первое действие — живой input → Undo/Redo → Save/reopen → Discard → F6. Не начинать новый UI-rework.

## Зависимости
Берёт: Resource/validation и команды у generators, world-map, materials, combat/game-systems.
Отдаёт: сохранённый Source/сцену/контент, preview и историю; gameplay state не принадлежит панелям.

## Ссылки
- [UI Rework](../EMBER_EDITOR_UI_REWORK_PLAN.md), [UI Pipeline](../EMBER_UI_PIPELINE.md),
  [Inspector](../EMBER_OBJECT_INSPECTOR_DESIGN.md), [Handoff](../EMBER_TECHNICAL_HANDOFF.md) → «Voxel data, Canvas и Surface».
- [Test Plan](../../MIGRATION_TEST_PLAN.md) → «Surface и voxel authoring», «Graph, Object Inspector и native content».
- Тесты: [layout](../../tools/test_voxel_workshop_layout.gd), [roundtrip](../../tools/test_scene_edit_roundtrip.gd),
  [опора](../../tools/test_walk_surface_mask.gd), [панели](../../tools/test_world_panel_host.gd),
  [библиотека](../../tools/test_game_systems_workspace.gd); native fixtures — только disposable checkout/cache.