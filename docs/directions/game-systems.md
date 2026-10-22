# Игровые системы
Обновлено: 2026-10-22. Активность: не заполнено (нужен проход по проекту).

## Цель
Предметы, экипировка, инвентарь, отряд, квесты, диалоги, лавки, сохранения и старт игры — общие модули с одной библиотекой данных.

## Владельцы (известно из структуры)
`addons/ember_import/ember_game_systems_*.gd`, `ember_item_*`, `ember_equipment_preview.gd`, `ember_encounter_*`;
`scripts/ember_equipment.gd`, `ember_inventory_ui.gd`, `ember_party_state.gd`, `ember_explore_state.gd`, `ember_interaction_ui.gd`;
данные `content/items`, `content/quests`, `content/dialogues`, `content/shops`, `content/game_start`.

## Принято автором / Сделано без приёмки / Открыто
Не заполнено. Известно: правки редакторов систем, предметов и экипировки лежат в checkpoint-коммите `0476913`
без проверки в этой линии работы; ручные gates документов прежние.

## Где остановились
Не заполнено.

## Зависимости
Берёт: карту, бой, персонажей. Отдаёт: данные игры карте и редактору.

## Ссылки
`../EMBER_TECHNICAL_HANDOFF.md` → «Общие игровые системы», «Exploration, interactions и content», «Party, save и переход в бой»;
`../EMBER_GAME_DESIGN.md`; `../EMBER_OBJECT_INSPECTOR_DESIGN.md`.
