# Редактор
Обновлено: 2026-10-22. Активность: не заполнено (нужен проход по проекту).

## Цель
Единый редактор: воксельная мастерская (лепка, части, штампы), редактор мира (земля, кисти), окна материалов.
Один владелец данных, UI только маршрутизирует команды.

## Владельцы (известно из структуры)
`addons/ember_import/plugin.gd`, `ember_voxel_sculpt_workspace.gd` (6,4 тыс. строк), `ember_voxel_sculpt_model.gd`,
`ember_world_editor.gd` (3,7 тыс. строк), `ember_voxel_stamp_panel.gd`, `ember_object_inspector_*`,
`ember_compact_material_pattern_dialog.gd`.

## Принято автором
По словам автора (22.10): новые редакторы приняты. Детали не сверены.

## Сделано без приёмки / Открыто / Где остановились
Не заполнено. Известно: нет кнопки «твёрдая форма из частей» (`solid_surface` создаётся скриптом) — см. objects-looks.md.
Очень большие файлы (workspace, graph workspace 5,3 тыс.) — кандидаты на разбиение.

## Зависимости
Создаёт и правит Source для objects-looks; окно материалов — для materials.

## Ссылки
`../EMBER_EDITOR_UI_REWORK_PLAN.md`, `../EMBER_UI_PIPELINE.md`, `../EMBER_OBJECT_INSPECTOR_DESIGN.md`, `../EMBER_EDITOR_UX_AUDIT.md` (старый).
