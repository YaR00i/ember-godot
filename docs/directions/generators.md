# Генераторы
Ориентиры разделены: Genshin/ALLfiring — результат формы по обликам, Blender — методы авторинга,
Sims — удобство будущего строительства (исследование, полный конструктор не согласован).
Общее решение — Product Plan → «Общая фактура материалов для трёх миров»; рецепты/срезы ниже прежние.
Обновлено: 2026-10-27. Активность: **природный выступ состыкован с рельефом main; вид OPEN**.
Текущие слоёные уступы не соответствуют уточнённому замыслу и сохранены для сравнения.
Новый тип3 использует грани RockGenerator и прежний voxel Source/volume-путь/Canvas/три облика.
Референсы/границы — World Authoring → «Земля и отдельные уступы»; порядок — Product Plan.
Регулярная рябь volume-меша исправлена27.10 ограниченной релаксацией прежнего Surface Nets;
три volume-объекта main пересобраны, физическая поверхность общая. Source/main не изменены.
Подробности/границы/evidence — Terrain Authoring → грунт; художественный вид OPEN.
Три формы/три слоя, «Природная форма»/seed, параметры/preview/история/save/reopen/discard и облики/опора проверены.
Main-примеры65%, старые recipes без параметра сохраняют0/прежнюю форму; вид/ручной ввод OPEN.
Справка прежних3 форм — World Authoring → «Уступы v0»; текущий тип — «Земля и отдельные уступы».
Выбор/перенос, точки линий/углы областей и параметры рядом используют прежний Plan;9 типов/история/save/native PASS.
Новые контуры не вводились. Маршрут/границы — World Authoring → «Единое управление областями» / «Подготовка плотных деталей».
Main3×3 и управляемый берег реализованы; focused/native проверки пройдены, авторская оценка открыта, дом ждёт оценки.

## Цель
Ягодный куст29.10: cloud-вид отклонён; один opt-in BushProvider/v7 использует
BranchLayout/tree_surface и прежние tree leaf cards/art/shader. Пять побегов,
мелкие ветви и ягоды с точными branch attachments. Внешний вид принят автором;
центр/верх округлены дополнительными внутренними побегами; 30 ягод диаметром1,1,
15 опор (8 сверху). Принятая форма не изменена. Side/top native кадры и targeted F/save PASS;
остальные формы отложены. Seed/Source/recipe/roundtrip/F/save/main-crop,
старые3 пресета и tree palette regression PASS; общий UI урожая/live regen OPEN.
Scope/owners/ограничения — Inspector I3.15 «Ягодный куст29.10» (game-systems).

Получать воспроизводимый Source одного объекта или локального рельефа; размещение леса/дороги принадлежит planner.
Сохранять рецепты и ручные правки; новые основы должны доходить до `landscape_compact`.

## Владельцы
- `addons/ember_import/ember_voxel_generator.gd`, `ember_voxel_generator_geometry.gd` в той же папке — общий provider.
- `ember_voxel_cliff_generator.gd` в той же папке — плато/прямой/угловой уступ; общий convex-fill — GeneratorGeometry.
- Там же: `ember_voxel_tree_generator.gd`, `ember_voxel_large_tree_generator.gd`, `ember_voxel_rock_generator.gd`,
  `ember_voxel_bush_generator.gd`, `ember_voxel_grass_generator.gd`, `ember_voxel_building_generator.gd` — конкретные генераторы.
- Там же: `ember_voxel_generator_recipe.gd`, `ember_voxel_generator_presets.gd`, `ember_voxel_generation_session.gd`,
  `ember_voxel_generator_panel.gd`, `ember_voxel_generation_panel.gd` — параметры, пресеты, партии и история.
- `scripts/ember_tree_species.gd`, `scripts/ember_tree_surface.gd` — новые породы и публикация оформления.
- `content/editor/voxel_generators/*.tres`, `content/editor/voxel_generator_presets/*.tres` — editor-only рецепты;
  `scripts/ember_voxel_model_resource.gd`, `content/voxel_models/*.tres` — Source, runtime не читает Recipe.
- Рельеф: `addons/ember_import/ember_compact_terrain_generation.gd`, `scripts/prototypes/ember_terrain_generation_math.gd`;
  план/расстановка — соседний owner `scripts/ember_terrain_plan_resource.gd`, не генератор одиночного объекта.

## Принято автором
- Дуб, берёза, клён и ель (16 октября); саванна не принята —
  [Terrain Authoring](../EMBER_TERRAIN_AUTHORING.md) → «Пять пород в основном редакторе».
- Первый workflow камней подтверждён, но это не приёмка всех форм/материалов:
  [Test Plan](../../MIGRATION_TEST_PLAN.md) → «Камни в мастерской генерации — 13 сентября2026…».
- Старые pixel-art/clouds режимы пяти пород имеют отдельную приёмку:
  [Test Plan](../../MIGRATION_TEST_PLAN.md) → «Общие pixel-art/clouds режимы всех5 пород…»; новые породы этим не принимаются.

## Сделано без приёмки
- Пять Sources `vox_painted_*` доступны через обычную библиотеку/мастерскую; личная плотность/движение OPEN.
- `41247dd` сохранил перенос пород; `0476913` — последующие provider/panels/tree surfaces, без приёмки checkpoint.
- Генерация/фактура/покрытия, fine16, крупные зоны и placement имеют записанные QA PASS;
  свои остров/мазки/посадка/weak-PC не приняты — Terrain Authoring → «Открытая приёмка и следующий шаг».
- Западная поляна24×24 м подключена к main; прежний генератор различает остров/сплошную сушу.
  Focused extension/history/save/стык/облики PASS, авторская оценка OPEN — World Authoring → «Западная поляна».

## Открыто
- Саванна: листва/ветвление; ветер, LOD, лес и общий переключатель трёх обликов не закрыты.
- Каменный генератор не публикует `solid_surface`: это пока `tools/publish_rock_shape.gd`, путь отдельной группы.
- Расхождение с границей «не знает облика»: provider вызывает `TreeSurface.publish`, Recipe содержит оформление;
  `tree_surface` сохраняет его в Source. Целевое разделение слоёв ещё не завершено.
- Ранняя рабочая основа саванны в Terrain Authoring не отменяет более позднее «не принята» в NOW.

## Где остановились
На main выбрать NaturalEarthOutcrop → «Генератор»; создание — Мастерская → Уступы → Природный выступ.
Recipe/seed, форма/покрытие, лепка, история/сохранение и опора трёх обликов проверены, вид OPEN.
Перепад земли собран прежними кистями, стык/нижний проход и опора трёх обликов проверены.
Этап4 технически собран; далее этап5 общего редактора, местный масштаб покрытия объекта.
Старые объекты не удалены и не считаются принятыми. Справка о «Уступы v0»: на main выбрать EarthCliffPlateau → «Генератор» →
высота/толщина земли → preview. Все3 формы доступны через «Мастерская генерации → Уступы».
Ручная оценка силуэта/вечера/ввода OPEN. Природная форма регулируется в прежнем генераторе.
Ручное «Тянуть» подключено для внешнего силуэта: один plateau Source доработан, три облика/опора проверены.
Его исходный рецепт защищён от перезаписи ручной формы. Выемки/отверстия/детальный mesh sculpt OPEN;
World Authoring → «Ручной силуэт через Canvas».
Суша/вода и3×3 участков сохраняют прежние открытые gates.
Единый маршрут/owners/найденные ограничения — World Authoring → «Приоритет25.10 · карта3×3».
Main72×72м: частичные sections достроены, старые48×25м и объекты сохранены;
coast v12 в прежнем плане/панели,3 generation-области ограничены новой сушей.
Кисть/история/save/reopen проверены на полной копии main; задержка Undo уменьшена до≈2с,
подготовка/Discard остаются тяжёлыми. Сфера на3×3 не готова за4мин — открытый perf gate,
не принята как масштабированная. Точные ограничения — в том же разделе World Authoring.
Возврат к берегу: общий вид main → «План областей» → «Восточный берег…» → параметры/preview.
Дом25.10: «Мастерская генерации → Здания → Прибрежный дом»; существующий Recipe/Creation.
Размеры/1–2 этажа/высота и свес крыши/цвета; на main `Map/Props/CoastalHouse`, точка(-208,12,208).
Native параметры/preview/Undo/Redo/save/reopen/discard/защита ручной лепки PASS на user:// копии;
main/три глобальных облика/опора PASS. Цвета — рабочая проба; вид/ввод/обход автором OPEN.
Автор положительно оценил первый дом; фасад остаётся пробой. Европейские стили, модульная
сборка по ориентиру Sims и библиотека интерьеров/предметов записаны на исследование в World Authoring.
Modular Builder / Building Tools / Archipack — кандидаты по документации, не установленные зависимости.
Дверь/окна — внешние объёмы, интерьер и взаимодействия не реализованы. Owners/evidence/ограничения —
World Authoring → Building Massing v0. Первое действие: выбрать дом → «Генератор» → изменить этажи.
Опушка25.10 размещена прежним planner на новой поляне:5 деревьев/2 каменные группы,
четыре сохранённые области; крупный бюджет Map теперь учитывается расстановкой. Трава/цветы —
прежняя кисть. Native история/save/три облика/проход PASS; авторский вид/ввод OPEN.
Owners/первое действие — World Authoring → «Прибрежная опушка».
Четыре древесные основы опубликованы, саванна сохранена для отдельного согласования. При возврате к деревьям сверить перенос с world-map;
при возврате открыть готовый дуб → «Генератор» → плотность → preview/Undo → Save/reopen/F6.
Оценить свой ввод/движение; правку саванны согласовать отдельно, остальные четыре породы сохранить.
Цвет листвы29.10: в прежних creation/edit доступны основной/дополнительный цвет и сила
перехода;0 сохраняет прежнюю окраску. Старый осенний клён сохранён, спокойный вариант
на старых sprigs + приглушённая кучка подключены к main. Цвет/history/preview/save/reopen/
discard/validation Forward+ PASS; оба цветовых варианта приняты по кадрам,
освещение/full main/ручная mouse приёмка OPEN. Листопад/покрытия — отложены у World Authoring.
Owners/инструкция/evidence — Terrain Authoring → «Цвет листвы29.10».

## Зависимости
Берёт: параметры/историю у editor, палитры и оформление у materials/objects-looks.
Отдаёт: Source и editor-only Recipe; objects-looks строит вид, world-map/planner выбирает место.

## Ссылки
- [World Authoring](../EMBER_WORLD_AUTHORING_ARCHITECTURE.md) → «1. Generator», «Порядок развития»;
  [Terrain Authoring](../EMBER_TERRAIN_AUTHORING.md) → «Пять пород в основном редакторе».
- Тесты: [generator](../../tools/test_voxel_generator.gd), [session](../../tools/test_voxel_generation_session.gd),
  [editing](../../tools/test_voxel_generator_editing.gd), [деревья](../../tools/test_tree_editor_transfer.gd),
  [камни](../../tools/test_voxel_rock_objects.gd), [рельеф](../../tools/test_terrain_generation_split.gd).
