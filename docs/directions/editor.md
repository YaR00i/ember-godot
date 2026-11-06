# Редактор

Обновлено:2026-11-04. Активно: создание локации в едином редакторе земли/объектов без сферы.
Сфера и `.exe` отложены автором. Ближайшее действие — [NOW](../EMBER_NOW.md).
Продуктовый маршрут7этапов — [Product Plan](../EMBER_PRODUCT_PLAN.md).

## Текущая точка

Строительный участок: «План областей → + Область → Строительный участок».
Готовые дома и ограда с проходом сохраняются в Map/Props независимо от границы.
Три этажа по 3 м, перекрытия по двум углам и стыки прямых и диагональных стен.
«Провести дуговую стену» принимает начало, точку на изгибе и конец на сетке.
Контур показывает толщину стены. Концы можно соединять с прямыми стенами.
«Скруглить угол» с полем «Радиус» заменяет общий угол двух глухих стен
одного этажа плавной дугой. Наведение показывает контур, щелчок применяет.
«Ход с парапетом» в инструменте дуговой стены поднимает настил
к перекрытию следующего этажа и оставляет открытые выходы на башни.
«Площадка башни» создаёт перекрытие с парапетом и одним или двумя проходами
по центрам выбранных граней. «Стыковать ход с башнями» подводит к ним
стену перпендикулярно граням; занятые проходы повторно не выбираются.
«Построить башню» ставит стены от земли и площадку на заданной высоте.
Толщина стены, ширина хода и высота башни задаются в метрах. Стыковка берёт
высоту и ширину из первого прохода и требует совпадающие размеры у второго.
«Круглая площадка» и «Полукруглая площадка» задаются центром и краем.
Полукруг развёрнут к указанному краю. «Крыша по контуру площадки» берёт
её контур, «Перила по краю круга» оставляют вход в точке щелчка.
«Срезы углов → Площадка со срезами» задаёт четыре независимых среза
при постановке перекрытия. Для бокового балкона стена проходит внутри
края перекрытия, а обычные перила закрывают открытый край.
У выбранной дороги «Участки вдоль дороги» открывает выбор стороны и размеров.
«Показать участки» строит контуры; щелчок исключает или возвращает вариант.
«Создать участки» сохраняет выбранные прямоугольники в плане. «Границы»
позволяют отдельно поправить каждый участок после создания.
У выбранного участка «Ограда и вход к дороге» примеряет фасад по щелчку
на соседнем полотне. Enter ставит ограду и короткий подход одной командой.
В параметрах дороги задаются ширина, обочина, уклон и покрытие
«Грунт» или «Брусчатка». Предпросмотр показывает выбранное полотно.
«Сетка 16×16» выравнивает контур покрытия и рельеф на поворотах.
У прежней дороги без указания точности панель предлагает эту сетку.
Для сухой независимой дороги детальный предпросмотр готовит плитки в фоне
и передаёт их применению. Ручная оценка скорости открыта.
Проверка облика свежей карты — [Terrain Authoring](../EMBER_TERRAIN_AUTHORING.md#создание-и-расширение-карты).
При открытии детальной карты земля сначала получает обзорные секции.
Точная поверхность с опорой подключается штатными плитками.
Для перегородок есть открытый проход, для фасада — утопленные окно и дверь.
«Настроить проём» задаёт размеры, верх, переплёт, подоконник, ставни и наличник.
У двери можно выбрать одну или две створки при постановке или через
«Выбрать окно или дверь» на готовой стене.
Крыльцо вдоль фасада поддерживает колонны с козырьком; карниз идёт по верху этажа.
Секции полосы привязываются к крыльцу, кусты клумбы строит общий генератор.
Цвет и материал стены, наличник окна и высота козырька задаются при постановке.
«Выбрать деталь для отделки» меняет текстуру, оттенок и частоту рисунка уже
поставленной стены, каменного парапета, кровли, основания крыльца или
перекрытия. Щелчок по дверному полотну или раме проёма выбирает их отдельно
от стены. Исходная отделка возвращается отдельной кнопкой. Ручной выбор в 3D
остаётся на приёмке.
«Поставить фонтан» ставит садовый или парадный вариант одним щелчком.
Круг показывает размер чаши. Отделку камня можно поменять после постановки.
Пилястра привязывается к глухому участку прямой или диагональной стены.
Кровля ставится над этажом, форма, высота и цвет правятся у сохранённой секции.
У кровли с выступом настраиваются сторона, ширина, вынос и смещение.
Видимая сетка этажей использует общую привязку 0,25 м и показывает узел под
курсором, закреплённое начало и мелкие деления при приближении. Для балкона в выемке
положите перекрытие, проведите стены и поставьте металлические перила или
каменный парапет по краю. Для быстрого выноса от фасада есть сборка с опциональными колоннами.
Выбранное окно двигается вдоль стены с сохранением её основания. В пробе дворца
есть два боковых крыла, парадная площадка и задний сад. «Поставить колонну»
добавляет свободную опору на перекрытие. Беседка собирается из перекрытия,
колонн, обычной крыши и перил. Яблони ставятся точками, изгородь рисуется
отрезками через инструмент «Провести полосу у дома». Для квадратных башен и перехода между ними
используется зубчатый парапет из списка перил. Ручная проба на основной карте,
проход персонажем и лестницы OPEN.
Владелец — World Authoring → «Наружный участок — вход в строительство».

Main-copy04.11: реальная landscape_compact в native editor прошла лепку/покраску,
мазок травы, постановку дуба, Undo/Redo, Save World, discard и native reopen.
Сохранённый результат загружается в обычную Forward+ игру; рабочая авторская карта не перезаписана.
В main перенесены упрощение деревьев и native grass8→6→4 через существующих owners.
Общие3D-цели/Canvas/формы сохраняют прежних owners; Canvas lifecycle/save PASS.
Тест физики обновлён к канонической границе: смена визуальных кубиков не меняет коллизию.
Ручная общая оценка мышью/ощущение и строгий performance gate остаются открытыми.
Ближайшее действие — лепить и наполнять main; редкие зависания отложены автором.
Сводка/evidence/границы переноса — [Performance](../EMBER_WORLD_PERFORMANCE.md#возврат-к-созданию-локации).
Новая ordinary terrain основа остаётся внешним QA-кандидатом: source/physics/grass/
native history/save/return проверены, Ember UI/3looks и дешёвый physics residency OPEN.
Рабочий terrain owner не заменён; evidence/точка возврата — Terrain Authoring/Performance.
Шаг1/joint CPU,ready grass,MapLoader group admission и Hoshi обвязка проверены02.11.
Hoshi detach отклонён;NPC opt-in sleep/wake у stress cohort проверен. Шаг4:CPU main≈97%ядра;
Separate остаётся QA из-заnative errors;Skeleton groups вSafe отклонены по whole-frame regression.
Godot editor отключает Node threading;его WorkerThreadPool jobs уже существуют.
Canvas pointer_up trace теперь включает worker wait (RED→GREEN);FPS gain этим не заявлен.
Native main-copy1152²/full324tiles baseline получен:pick+overlay5,6–13,7мс,
Raise/Smooth stamps median17,3/28,9мс;shutdown error/7leaks не приняты. Это не576м stress.
Native game profile:CharacterBody motion≈38%main/main-only API;release≈15,6–16,3мс.
Единый multicore план/physics architecture gate — Performance;ручная отзывчивость OPEN.
Activity invalidation batch стал дешевле,FPS/120gate ещё OPEN — Performance.
Порядок/evidence/ограничения — Performance → «Единственная текущая последовательность».
Приоритет до наполнения — стоимость кадра и плавность dense мира; текущие цифры,
единственный порядок, owners, исследования и gates —
[Производительность мира](../EMBER_WORLD_PERFORMANCE.md).
Минимум120FPS/native2560×1440 не достигнут; плотность/дальность не сокращать ради PASS.
Локальные тесты/LOD/caches не принимают gameplay/полную память/слабый ПК.
Native LOD/feature programs сохранены. На main grass/flowers крупнее на25% без
смены плотности;обычные smooth/round/protect controls сохранены и проверены native.
Без приёмки:в Play F2 переключает normal/native LIGHTING/wire,Shift+F2 nativeLOD/full.
Native main counts/restore/Source SHA PASS;alpha/vertex caveat и замеры — Performance.
Топология земли в этом диагностическом срезе не менялась;F5/движение проверяет автор.
Убраны repeated wheat validation и main-thread scatter-cache persistence.
Overview release объединён по регионам под budget;reverse/revision/owner lifetime PASS.
Встроенный Jolt в project.godot:terrain query p951,137→0,048мс;surface/step/Hoshi/crates PASS.
Enlarged native cold/release/return PASS;clean p95≈7,969/8,748мс,120FPS OPEN.
Cache read теперь bounded worker;pending material сохраняет light/gray preview.
Native cache/Undo/Redo/save/reopen PASS. Startup/editor5мс,gameplay3мс;плотность/дальность прежние.
Epoch admission убрал повторные неизменные sleeping sweeps;paused resume/resize PASS.
Material digests теперь worker,private textures/live profile replay и native save/Undo PASS.
Native exact indexing уменьшил upload≈5x;pixels/shadows/LOD/physics/brush regressions PASS.
Queue starvation исправлен:near waiter не вытесняет владельца bounded digest/read slots.
Native fairness/cancel/release/cache/material/editor regressions PASS.
Overview Ground меняет indices при сохранении mesh/RID;native pixel/shadow/revision/stress PASS.
Local publication дешевле;общий gain не подтверждён A/B/A. Old-production тоже даёт468мс.
Nearest исключает дальний story routing,точная distance/flags/volume/held pickup сохранены.
Native query A/B/A0,186→0,014мс;launch-rules/crates/cold return PASS.
Grass signature owner lookup вынесен из prop loop:local0,200→0,140мс,exact/native PASS.
Ready-grass Node owner cache:local≈6,3%;reparent/epoch native PASS.
PSO persistence3MB воспроизвёл507мс;64MB control78мс,порог применён,cache enabled.
Current clean max35,7/28,9мс;FOV70 p958,748мс:120FPS OPEN,общий FPS gain не доказан.
Animation pose/morph/secondary bones LOD, активная physics residency и native
shadow geometry proxies реализованы; focused checks PASS, общий population gate у Performance owner.
Object poll1мс/cursor,earlyzero-budget gate,shadow setter coalescing и Hoshi nativeLOD готовы.
Новый игровой stress32NPC+32яблони/32berry/32cuttable:actions/save/return PASS;
median15,133/15,404мс,p9529,452/29,216;120FPS/coverage OPEN,floor0/0,allbodies survive.
Closed pickup interest исправлен:live tiles520→396,безFPS gain. CPU diagnostic нашёл
крупный secondary rig cost. Cached axes gain не дали,правка снята;double-step нет.
Исследование Crimson завершено:developer slides/stateful proxy/shared reactions;
применимость/неизвестное/условиявозврата — короткийвход Performance. Старые120/coverage OPEN.
Stone ray-context nearGPU≈18% дешевле;editor/3looks PASS,общий crowd gain не установлен.
Старый16NPC streaming PASS не принимает эту расширенную нагрузку;owner/evidence выше.
Штатный Godot выбран автором; temporal directional cache отложен, полного Source-unload нет.
Natural-stall attribution/long-session/120FPS OPEN.
Sampler350ms control готов;редкая пауза и ручные мазки/движение OPEN.
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
