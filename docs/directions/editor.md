# Редактор

Обновлено:2026-10-31. Активно: единый редактор земли/объектов без сферы.
Сфера и `.exe` отложены автором. Ближайшее действие — [NOW](../EMBER_NOW.md).
Продуктовый маршрут7этапов — [Product Plan](../EMBER_PRODUCT_PLAN.md).

## Текущая точка

Main-copy: общие3D-цели/черновики/история/Canvas, кисти/маски, формы/библиотека и
save/reopen/discard технически проверены. Ручная общая оценка остаётся открытой.
Приоритет до наполнения — стоимость кадра и плавность dense мира; текущие цифры,
единственный порядок, owners, исследования и gates —
[Производительность мира](../EMBER_WORLD_PERFORMANCE.md).
Минимум120FPS/native2560×1440 не достигнут; плотность/дальность не сокращать ради PASS.
Локальные тесты/LOD/caches не принимают gameplay/полную память/слабый ПК.
Native LOD/feature programs сохранены. На main grass/flowers крупнее на25% без
смены плотности;обычные smooth/round/protect controls сохранены и проверены native.
Убраны repeated wheat validation и main-thread scatter-cache persistence.
Overview release объединён по регионам под budget;reverse/revision/owner lifetime PASS.
Встроенный Jolt в project.godot:terrain query p951,137→0,048мс;surface/step/Hoshi/crates PASS.
Enlarged native cold/release/return PASS;clean p95≈8,284/9,142мс,120FPS OPEN.
Cache read теперь bounded worker;pending material сохраняет light/gray preview.
Native cache/Undo/Redo/save/reopen PASS. Startup/editor5мс,gameplay3мс;плотность/дальность прежние.
Epoch admission убрал повторные неизменные sleeping sweeps;paused resume/resize PASS.
Material digests теперь worker,private textures/live profile replay и native save/Undo PASS.
Native exact indexing уменьшил upload≈5x;pixels/shadows/LOD/physics/brush regressions PASS.
Queue starvation исправлен:near waiter не вытесняет владельца bounded digest/read slots.
Native fairness/cancel/release/cache/material/editor regressions PASS.
Далее wide70 overview publication и render waits;ручные мазки/движение OPEN.
Restart Godot→F5 и ручное ощущение physics/мазки/размер/камера/тени OPEN.
Очередь overview сошлась без оставшихся лишних fine;scopes/evidence у performance owner.

## Владельцы

- `addons/ember_import/plugin.gd` — вход; `ember_world_editor.gd` — мир,
  `ember_voxel_stamp_panel.gd` — штампы, `scenes/*.tscn` — карта.
- В том же addon `ember_voxel_sculpt_workspace.gd`, `ember_voxel_sculpt_model.gd`,
  `ember_voxel_sculpt_actions.gd` — мастерская объекта, модель и команды.
- `ember_voxel_model_store.gd`/`ember_voxel_object_session.gd` — публикация/сессия;
  `scripts/ember_voxel_model_resource.gd`, `content/voxel_models/*.tres` — Source.
- `ember_compact_material_pattern_dialog.gd` — Pattern; graph/Inspector и библиотека
  игровых систем маршрутизируют прежние команды, gameplay owners не дублируют.
- [World Authoring](../EMBER_WORLD_AUTHORING_ARCHITECTURE.md) — общие Canvas/3D,
  лепка/формы/планеры; [Terrain Authoring](../EMBER_TERRAIN_AUTHORING.md) — земля/материалы.
- [Handoff](../EMBER_TECHNICAL_HANDOFF.md) — технические границы;
  [Test Plan](../../MIGRATION_TEST_PLAN.md) — относящиеся проверки.

## Принято автором

- Плавность/живой показ кисти и её пригодность к работе приняты23.10.
  Небольшая задержка отображения приемлема в проверенном сценарии;
  это не приёмка всех сочетаний max masks/обликов/краёв или полного save-цикла.
- Панель поверхности прохода/voxel-кисти/устранение левитации над балкой приняты13.09;
  точный scope сохранён в Test Plan → «Поверхность прохода».
- Чистый возврат из Canvas подтверждён27.10; силуэт природного выступа принят28.10.
  Это не общая приёмка камня/materials или всех инструментов.

## Сделано без полной ручной приёмки

Общий Smooth, плоскость/срез/маска/protect/clear, общие параметры и входы Canvas↔3D,
merge/carve/paint/separate/library/place/sculpt проверены с прежней историей и save.
Alt+Q под курсором/обычный выбор используют общие черновики и прежнюю кисть/радиус.
Параметры radius/depth/force/softness и три облика сохраняют Source/историю;
preview/cancel/Undo/Redo/save/fresh reopen/discard проверены на fixtures/main-copy.
В объёмных объектах сохранены palette/material channels, легальная часть0 и carved boundary.

Объёмная замена земли отклонена27.10 по форме/текстурам; main её не содержит.
Землю править её кистями без растяжения покрытия, отдельные элементы ставить на перепады.
ExternalCoastalRock сохраняет исходный GLB и прежний source/derived путь.
NaturalEarthOutcrop состыкован с площадкой main; физика едина в трёх обликах, вид OPEN.
Локальный «Покрытие→Размер рисунка» готов:1× в единицах земли, Source/общий Pattern неизменны.
Общая глубина покрытий подключена; следующая художественная приёмка/библиотека — materials.

## Открыто

- Личная мышь/кисть/сохранение, оба следа/каналы, max radius8/формы/облики/края,
  живая опора/стыки, narrow1280×720/125%, thumbnail cache и Pattern302/326px.
- Три облика/materials/камень целиком, личный F6/reopen и приемлемое время открытия.
- Создание/расширение/ручная композиция планера и полный authoring маршрут;
  UI/история API не заменяют удобство и визуальную оценку.
- Новые тонкие полосы на малых перепадах и зелёные склоны self-shadow в движении;
  чёткость теней понравилась, причина полос ещё не воспроизведена.
- 120FPS/stalls/fully-cold/полная RAM/VRAM/weak-PC/export/wind/mixed/wet-world —
  [performance gates](../EMBER_WORLD_PERFORMANCE.md#общая-приёмка-и-оставшиеся-gates).
- Нет authoring-команды создания `solid_surface` из частей: workspace сохраняет
  существующие данные; производную публикацию пока делает `tools/publish_rock_shape.gd`.
- Причины прежних AV/shutdown/TDR открыты. Отсутствие нового вылета не является fix.
- Hoshi/персонажи/игровые механики принадлежат параллельным направлениям.

## Где остановились

Feature programs подключены; ручная приёмка и общий120FPS gate открыты.
Следующее — измеренный остаток общего кадра/тяжёлые кадры, затем полосы теней и memory/1060.
Ручные gates редактора сохраняются к авторской итоговой оценке.
Новая система инструментов/renderer/схема и новая рабочая карта не вводятся.

## Согласованный срез · обновление земли без рывков (23.10)

Сохранённый контракт живой кисти: видимый mesh меняется во время зажатого мазка,
Source/материалы/три облика и одна Undo-команда сохраняются. Mesh/physics/floor
публикуются прежним projection; отпускание фиксирует операцию, cancel восстанавливает.

### Результат · живая кисть принята автором

Пригодность/живой показ приняты23.10 в проверенном сценарии; полный manual gate выше открыт.
Evidence: `C:/Users/novos/Documents/Codex/2026-10-23/ember-brush-live/`.

### Предельные маски · рабочая кисть принята автором

UI radius≤8блоков; текущий алгоритм принят23.10, дальнейшая полировка не блокирует локацию.
При новом симптоме измерять публикации/задержку показа/полный кадр, не только helper throughput.

### Blender Sculpt · исследование применимости

Референс инструментов — связный stroke/dirty areas/attributes/local updates, а не второй editor.
Потоки/частичный GPU upload требуют своей измеренной причины; детали общих Canvas/3D owners —
[World Authoring](../EMBER_WORLD_AUTHORING_ARCHITECTURE.md), принятые критерии — выше.
