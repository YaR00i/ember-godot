# Генераторы
Обновлено: 2026-10-22. Активность: на паузе; активная цель NOW — сборка единой карты.

## Цель
Получать воспроизводимый Source одного объекта или локального рельефа; размещение леса/дороги принадлежит planner.
Сохранять рецепты и ручные правки; новые основы должны доходить до `landscape_compact`.

## Владельцы
- `addons/ember_import/ember_voxel_generator.gd`, `ember_voxel_generator_geometry.gd` в той же папке — общий provider.
- Там же: `ember_voxel_tree_generator.gd`, `ember_voxel_large_tree_generator.gd`, `ember_voxel_rock_generator.gd`,
  `ember_voxel_bush_generator.gd`, `ember_voxel_grass_generator.gd` — конкретные генераторы.
- Там же: `ember_voxel_generator_recipe.gd`, `ember_voxel_generator_presets.gd`, `ember_voxel_generation_session.gd`,
  `ember_voxel_generator_panel.gd`, `ember_voxel_generation_panel.gd` — параметры, пресеты, партии и история.
- `scripts/ember_tree_species.gd`, `scripts/ember_tree_surface.gd` — новые породы и публикация оформления.
- `content/editor/voxel_generators/*.tres`, `content/editor/voxel_generator_presets/*.tres` — editor-only рецепты;
  `scripts/ember_voxel_model_resource.gd`, `content/voxel_models/*.tres` — Source, runtime не читает Recipe.
- Рельеф: `addons/ember_import/ember_compact_terrain_generation.gd`, `scripts/prototypes/ember_terrain_generation_math.gd`;
  план/расстановка — соседний owner `scripts/ember_terrain_plan_resource.gd`, не генератор одиночного объекта.

## Принято автором
- Дуб, берёза, клён и ель (16 октября); саванна не принята —
  [NOW](../EMBER_NOW.md) → «Активная цель», абзац «Пять пород перенесены…».
- Первый workflow камней подтверждён, но это не приёмка всех форм/материалов:
  [Test Plan](../../MIGRATION_TEST_PLAN.md) → «Камни в мастерской генерации — 13 сентября2026…».
- Старые pixel-art/clouds режимы пяти пород имеют отдельную приёмку:
  [Test Plan](../../MIGRATION_TEST_PLAN.md) → «Общие pixel-art/clouds режимы всех5 пород…»; новые породы этим не принимаются.

## Сделано без приёмки
- Пять Sources `vox_painted_*` доступны через обычную библиотеку/мастерскую; личная плотность/движение OPEN.
- `41247dd` сохранил перенос пород; `0476913` — последующие provider/panels/tree surfaces, без приёмки checkpoint.
- Генерация/фактура/покрытия, fine16, крупные зоны и placement имеют записанные QA PASS;
  свои остров/мазки/посадка/weak-PC не приняты — NOW → «Точка возврата к материалам».
- На входе `git status`: tracked-правок по направлению нет; тесты в этом проходе не запускались.

## Открыто
- Саванна: листва/ветвление; ветер, LOD, лес и общий переключатель трёх обликов не закрыты.
- Каменный генератор не публикует `solid_surface`: это пока `tools/publish_rock_shape.gd`, путь отдельной группы.
- Расхождение с границей «не знает облика»: provider вызывает `TreeSurface.publish`, Recipe содержит оформление;
  `tree_surface` сохраняет его в Source. Целевое разделение слоёв ещё не завершено.
- Ранняя рабочая основа саванны в Terrain Authoring не отменяет более позднее «не принята» в NOW.

## Где остановились
Четыре основы опубликованы, саванна сохранена для отдельного согласования. Сначала сверить перенос с world-map;
при возврате открыть готовый дуб → «Генератор» → плотность → preview/Undo → Save/reopen/F6.
Оценить свой ввод/движение; правку саванны согласовать отдельно, остальные четыре породы сохранить.

## Зависимости
Берёт: параметры/историю у editor, палитры и оформление у materials/objects-looks.
Отдаёт: Source и editor-only Recipe; objects-looks строит вид, world-map/planner выбирает место.

## Ссылки
- [World Authoring](../EMBER_WORLD_AUTHORING_ARCHITECTURE.md) → «1. Generator», «Порядок развития»;
  [Terrain Authoring](../EMBER_TERRAIN_AUTHORING.md) → «Пять пород в основном редакторе».
- Тесты: [generator](../../tools/test_voxel_generator.gd), [session](../../tools/test_voxel_generation_session.gd),
  [editing](../../tools/test_voxel_generator_editing.gd), [деревья](../../tools/test_tree_editor_transfer.gd),
  [камни](../../tools/test_voxel_rock_objects.gd), [рельеф](../../tools/test_terrain_generation_split.gd).