# Генераторы
Обновлено: 2026-10-22. Активность: не заполнено (нужен проход по проекту).

## Цель
Создавать Source (деревья, камни, кусты, трава) по правилам; про облик, материал и свет не знают.

## Владельцы (известно из структуры)
`addons/ember_import/ember_voxel_generator*.gd` (панель, геометрия, пресеты, рецепт), `ember_voxel_rock_generator.gd`,
`ember_voxel_tree_generator.gd`, `ember_voxel_large_tree_generator.gd`, `ember_voxel_bush_generator.gd`,
`ember_voxel_grass_generator.gd`; исследования деревьев — `scripts/prototypes/ember_tree_*_study.gd`.

## Принято автором
Пять пород деревьев (по словам автора и коммиту `41247dd`); детали не сверены.

## Сделано без приёмки / Открыто / Где остановились
Не заполнено. Известно: генератор камней не создаёт `solid_surface` (твёрдую форму из частей) — см. objects-looks.md.

## Зависимости
Отдаёт Source в objects-looks. Берёт параметры из редактора.

## Ссылки
`../EMBER_BRUSH_WORKSHOP_PLAN.md`, `../EMBER_TERRAIN_AUTHORING.md` → «Пять пород в основном редакторе».
