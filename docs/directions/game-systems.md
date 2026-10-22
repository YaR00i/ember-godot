# Игровые системы
Обновлено: 2026-10-22. Активность: на паузе; активная цель NOW — сборка единой карты.

## Цель
Общие библиотека, отряд, сумка, экипировка, квесты/диалоги/лавки, старт/save для канонической главы без второго runtime.

## Владельцы
- `scripts/ember_explore_state.gd` — mutable/save owner; `scripts/ember_party_state.gd` — нормализация/derived stats/XP.
- `scripts/ember_equipment.gd`, `scripts/ember_inventory_ui.gd` — экипировка/сумка;
  `scripts/ember_game_start_resource.gd`, `content/game_start/default.tres` — рецепт только новой игры.
- `scripts/ember_item_catalog.gd`, `ember_item_resource.gd`, `ember_shop_catalog.gd`, `ember_shop_resource.gd`
  в той же папке — native данные; `content/items/`, `content/item_icons/`, `content/shops/`.
- `scripts/ember_quest_resource.gd`, `ember_quest_state.gd`, `ember_action_catalog.gd`, `ember_action_script.gd`,
  `ember_dialogue_catalog.gd`, `ember_dialogue_session.gd` в той же папке — квесты и исполнение сценок;
  `content/quests/`, `content/action_scripts/`, `content/dialogues/` — соответствующие ресурсы.
- `scripts/ember_explore_scene.gd`, `ember_interact.gd`, `ember_interact_rules.gd`, `ember_interaction_ui.gd`,
  `ember_map_transition.gd` в той же папке — исследование/взаимодействия/переходы.
- `addons/ember_import/ember_game_systems_workspace.gd`, `ember_game_systems_session.gd`,
  `ember_game_systems_store.gd`, `ember_game_systems_catalog.gd` в той же папке — UI/draft/запись/read projection;
  `ember_game_start_editor.gd`, `ember_item_editor.gd` там же. Боевые Resources принадлежат combat.

## Принято автором
- Graybox острова/маяка — базовая спецификация 9 сентября, не готовая глава:
  [GDD](../EMBER_GAME_DESIGN.md) → «Принятая спецификация graybox».
- Контракт активной группы 1–4 согласован 9 сентября, ручная приёмка реализации открыта:
  [GDD](../EMBER_GAME_DESIGN.md) → «Лабораторная партия и тестовые герои».
- Перенос исходных slots экипировки принят: [Handoff](../EMBER_TECHNICAL_HANDOFF.md) → «Общие игровые системы».
- Общая авторская приёмка новой библиотеки/старта/всех игровых систем не подтверждена.

## Сделано без приёмки
- Общая библиотека, Usage/Check, Lab setup/presets/cycle, пять слотов/обувь, уровни/сумка старта;
  прежние saves используют свои данные. QA PASS записаны в NOW/Handoff, своё использование OPEN.
- Native item/shop/story/VN catalogs, переход retired save в native вход с прогрессом,
  recoverable save v2 и equipment backup реализованы; manual старый Load/Save/backup остаётся OPEN.
- `841b294` — native cleanup/библиотека; `6124184` — старт/Lab/условия;
  `0476913` — последующие draft/workspace/item/equipment изменения; checkpoint не принимает результат.
- На входе tracked-правок нет; тесты здесь не запускались, старые PASS взяты из документов.

## Открыто
- Сначала ручной gate одиночки/пары; затем редактируемые квесты/действия/сценки канонического graybox по NOW.
- Свои старты/экипировка/наборы/арены, authored cycle, старый Load/Save/backup, narrow/125% и input.
- Исходный native AV не воспроизведён повторно, причина OPEN; сохранение crash evidence не является crash fix.
- Полный physical/export G4/G5 и живой F5/старый прогресс OPEN; native catalogs не означают полного выхода из JOI.
- Расхождение: Handoff → «Exploration, interactions и content» ещё говорит о старых городах «до retirement»;
  NOW → «Точка возврата к cleanup» и текущие сцены уже фиксируют их вывод. Удалённый runtime-путь не возвращать.

## Где остановились
Первое действие: свой старт/предмет/приём → Save/Undo → Lab → бой → Save/cold Load; отдельно старый save/equipment backup.
Удобство/баланс принимает автор. Следующий контентный контракт — сценки главы после gate активной группы.

## Зависимости
Берёт: карту/входы у world-map, боевой result у combat, IDs/представление героев у characters.
Отдаёт: persistent партию/сумку/прогресс, контент interactions и копию партии в бой; editor правит те же Resources.

## Ссылки
- [NOW](../EMBER_NOW.md) → «Точка возврата к игровым системам», «Точка возврата к cleanup»; [Handoff](../EMBER_TECHNICAL_HANDOFF.md) → «Общие игровые системы», «Party, save и переход в бой»;
  [Test Plan](../../MIGRATION_TEST_PLAN.md) → «Игровые системы…», «Exploration, party и save».
- Проверки: [runner](../../tools/run_game_systems_tests.py), [cycle](../../tools/test_game_systems_cycle.gd),
  [старт](../../tools/test_game_start_authoring.gd), [экипировка](../../tools/test_inventory_equipment.gd),
  [save v2](../../tools/test_party_save_v2.gd), [квесты](../../tools/test_quest_state.gd), [story](../../tools/run_story_tests.py).
