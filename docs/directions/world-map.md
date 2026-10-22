# Мир и карта
Обновлено: 2026-10-22. Активность: **активно** (следующий срез — «Текущий мир»).

## Цель
Единая играбельная карта `scenes/landscape_compact.tscn` со всеми принятыми наработками
(земля, рисованные материалы, свет, вода, трава, деревья, камни); планировщик размещает
объекты, не зная, как они сгенерированы.

## Владельцы
- Сцена и загрузка: `scenes/landscape_compact.tscn`, `scripts/ember_map_loader.gd`, `scripts/world_canvas.gd`.
- Земля (колонны, вода): `content/world_terrains/landscape_compact.res`, `scripts/prototypes/ember_terrain_pilot_*.gd`,
  `ember_terrain_*` (в папке `prototypes/` лежит и рабочий код, не только пробы).
- Вода: `scripts/prototypes/ember_compact_water_*.gd`, `shaders/ember_voxel_surface_water.gdshader`.
- Свет: `scripts/ember_lights.gd`, `compact_material_light_mode` в `EmberMapLoader`.
- Редактор мира: `addons/ember_import/ember_world_editor.gd`.

## Принято автором
- По словам автора (22.10): вода, трава, деревья, новые редакторы приняты — каждое в своей тестовой сцене.
- Камень (рамка, рисунок, виды 4/5/6, подробный с живыми гранями 30 мм) принят в тестовой сцене
  `compact_environment_material_review`.

## Сделано без приёмки
- Камень поставлен в `landscape_compact` (yaw 90°, X112/Y-3/Z200, 16 ед./блок): не парит, на сухом плато,
  три вида работают; `tools/test_landscape_rock_placement.gd`. Скриншоты — Evidence ember-rock-form-probe/.

## Открыто
- **`landscape_compact` устарела** (правилась 29.09): земля без ролей материалов (палитра 6 цветов, `palette_surface_roles`
  пуст → плоские старые цвета), свет «Прежний свет» (mode 0), нет травы и деревьев. Море есть (80 тыс. колонн).
- Нет карты, где есть всё сразу: свежая земля `material_review_ground.tres` (рисованные материалы, 12×12 м) без воды.
- Свет карты: mode 0 делает камень бледным, mode 1 при солнце 0.3 тёмный, mode 1 + дневной пресет review
  возвращает вид камня, но перекрашивает карту — решение автора OPEN (`landscape-light/` в evidence).
- 49 сцен-проб только для тестов/документов, 6 сцен-сирот (см. quality-cleanup.md).

## Где остановились
Шаг 1 контракта «Текущий мир»: таблица «что нужно для переноса» по слоям и объектам (земля/материалы, свет,
трава, деревья/камни, вода). Затем переносить по одному в `landscape_compact`, после каждого шага — кадры автору.

## Зависимости
Берёт: облики и форму (objects-looks), материалы (materials), Source от генераторов/редактора.
Отдаёт: карту для боя, игровых систем и персонажей.

## Ссылки
`../EMBER_TERRAIN_AUTHORING.md`, `../EMBER_WORLD_AUTHORING_ARCHITECTURE.md`, `../EMBER_WATER_RENDERING.md`,
`../../MIGRATION_TEST_PLAN.md` → «Rock in the map 22 Oct».
