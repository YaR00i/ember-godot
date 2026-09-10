# Ember — актуальные проверки и migration gates

## Одиночные объёмные штампы (manual gate открыт)

Автоматически: `tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless
--path . --script res://tools/test_voxel_stamp.gd`. Native: без --headless,
добавить `-- --capture`, screenshot `user://voxel_stamp.png`. Fixtures только user://.
Связанные: test_voxel_selection_interaction, test_voxel_fragment,
test_voxel_merge, test_voxel_object_canvas; plugin check-only.

1. Выделить небольшую разноцветную деталь. В разделе «ОБЪЁМНЫЕ ШТАМПЫ» ввести
   название, «Сохранить выделение как штамп». Источник не меняется.
2. Выбрать пресет → «Разместить штамп…». ЛКМ задаёт опору (для Add — перед
   видимой гранью), стрелки/XYZ уточняют позицию. Проверить поворот 90°,
   отражение и три опоры. Esc не меняет модель.
3. «Добавить»: занятое не перекрашивается. «Заменить»: occupied footprint меняет
   цвета/материальные каналы; пустой угол/дырка шаблона не стирает объект.
   Enter фиксирует один отпечаток. Undo/Redo возвращает geometry/palette/parts.
4. В склейке выбрать часть для новых voxels; новые ячейки получают эту часть,
   replaced occupied сохраняют прежнюю. Проверить Save Canvas и F6 collision.
5. Save/reopen сцены и редактора: пресет в библиотеке, отпечаток в объекте.
   «Редактировать модель штампа…»: изменить шаблон, Save, затем новый отпечаток
   использует новую форму, ранее поставленные не меняются. Проверить discard.
6. Lock, выход за холст/срез, несовпадающие плотности, palette overflow — отказ
   целиком. Маску/изоляцию/скрытие нужно отключить; чужие authored files не удаляются.

Большие штампы измерены отдельно (16384 vox, plan ~60ms); полная производительность
на авторском Причале и визуальная/input-приёмка остаются ручным gate.

## Склейка и разбор текущей формы (manual gate открыт)

Дополнительный gate совмещения: взять `Fragment_new` и нижний блок, нижний
назначить основным. При дробном смещении включить «Совместить сетки»: видны
полупрозрачное прежнее положение и Δ XYZ; сцена за окном не меняется. Снять
checkbox/отменить окно — исходные позиции прежние. Повторить и склеить: результат
совпадает с preview; один Undo возвращает детали и точные дробные позиции,
Redo возвращает склейку. Save/reopen и F6 сохраняют новую геометрию/коллизию.
При смене основной детали checkbox сбрасывается; rotation/scale не округляются.

Автоматически: `tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless
--path . --script res://tools/test_voxel_merge.gd`. `-- --benchmark` дополнительно
измеряет плотные 131072 вокселя; без `--headless`, с `-- --capture` — native
Forward+ preview в `user://voxel_merge.png`. Tests не меняют авторские карты.
Связанные: extraction, fragment, canvas_growth, object_split, assembly_canvas,
groups, object_canvas, native_voxel_resource, selection_interaction.

Ручная приёмка:

1. В 3D выбрать 2–3 native-доски одного родителя, при необходимости сохранить
   их через Canvas. «Ещё… → Склеить voxel-детали…»: выбрать основную,
   обновить preview. В пересечениях красная подсветка; отмена ничего не меняет.
2. Склеить: положение прежнее, одна модель. Ctrl+Z возвращает доски, Ctrl+Shift+Z
   возвращает склейку. Проверить цвета и актуальную collision через F6.
3. Открыть склейку в Canvas, удалить несколько вокселей. В списке
   «Новые воксели → …» выбрать исходную часть и долепить её; выбрать
   «Добавленное» и добавить отдельный выступ. Save, закрыть/открыть Canvas.
4. «Ещё… → Разобрать склейку…»: удалённое не возвращается, лепка остаётся
   в своей части, выступ становится отдельным объектом. Проверить Undo/Redo.
5. Save сцены, перезапуск Godot, F6 Причала: положение и collision не расходятся.
6. Повторить с поворотом 90° и плотностями 16/32. Произвольный относительный
   поворот, несогласованная сетка, лишний script/связь или overflow палитры
   должны дать объяснение без частично изменённой сцены.

Ограничения: ≤32 исходных частей (+Добавленное), ≤524288 ячеек, common parent,
совместимый материал/физика, без воды/custom lights и произвольного resampling.
Большие операции синхронны: замеры отдельных стадий не доказывают отзывчивость
редактора на полной авторской карте. Этот performance/manual gate не закрыт.

## Отделение фрагмента в объект (manual gate открыт)

Дополнение: по умолчанию остаться в Canvas с обновлённой геометрией и ракурсом;
проверить Undo/Redo без выхода. Повторить с включённым «Перейти в 3D к новой детали».
test_voxel_extraction проверяет оба исхода и синхронизацию чистого draft с историей.

`--headless --path . --script res://tools/test_voxel_extraction.gd`: detached
prepare, cut/copy, linked-source independence, material/groups, world position
при наклоне/масштабе, Mesh/Collision parity, one Undo/Redo, pack/save/reopen,
stale transform, late publication failure without partial scene changes,
whole-object cut, cross-section assembly cut/undo, UI confirmation/cancel/commit.
С `-- --benchmark`: 32768 выбранных из 131072 ячеек; отдельно prepare/commit.
Замер 10 сентября: prepare 2381 мс, commit 4431 мс на плотной fixture 128×8×128.
Публикация пока синхронная: заметная пауза на больших объёмах остаётся ограничением,
эти числа не являются доказательством отзывчивости на максимальном Причале.
С `-- --capture` без --headless: native Forward+ подтверждение при 1280×720.
Связанные regressions: object_canvas, assembly_canvas, fragment,
selection_interaction, object_split (tools/test_voxel_*.gd).
Ручной сценарий: открыть доску из сцены в Canvas → выделить край → Save Canvas,
если были правки → «Вырезать в новый объект…» → подтвердить → 3D выделяет
Fragment. Проверить отсутствие сдвига/щели, collision, отдельно сдвинуть деталь,
Undo перемещения, Undo отделения, Redo; сохранить сцену и открыть после рестарта.
Для копирования оригинал не меняется: копия совпадает с ним, сдвинуть отдельно.
Повторить через границу секций, затем открыть общий Canvas сборки. Отмена
подтверждения не создаёт файлов. Проверить понятный отказ для несохранённых
правок/общей модели/Surface/неподдерживаемой физики. Авторский Причал тестами
не изменяется; auto-removal новых файлов не предусмотрен.

## Фрагменты Canvas — фаза 1 (manual gate открыт)

«Рамка по поверхности»: test_voxel_surface_marquee проверяет 6 направлений,
16/32 density, inward depth, обратное протягивание, параллельный луч, bounds clip.
test_voxel_selection_interaction дополнительно проверяет жест сверху: depth 1
выбирает 16 верхних из 32 ячеек, preview не меняет предыдущую маску или source.
Native capture сохраняет user://surface_marquee.png.
Вручную: V → «Рамка по поверхности» → глубина 1 → протянуть по верху доски;
глубина 2 → повторить; повернуть камеру и начать на боку. Объём должен идти
внутрь от начальной грани и не перескакивать на соседние грани. Проверить
Shift/Ctrl, Esc, начало вне объекта, дальнейший перенос/Undo/save/reopen.

UX-коррекция: `tools/test_voxel_selection_interaction.gd` проверяет видимую
поверхность против насквозь, живой detached ghost, mouse-release selection,
integer axis drag, inline commit/Undo/Redo, invalid destination, Esc. С `-- --capture`
без --headless создаёт native Forward+ screenshot 1280×720. Старый selection
regression явно выбирает режим связного цвета вместо нового default marquee.
Актуальный ручной сценарий: V → протянуть рамку по доске; переключить
«Видимая поверхность / насквозь», сравнить внутренние/задние воксели; Shift/Ctrl.
Нажать «Перенос / копия / поворот…» → тянуть X/Y/Z прямо в Canvas → Enter/Esc.
Проверить числовое смещение, 90° и копию, красный запрещённый результат,
Ctrl+Z/Redo, Save/reopen, camera orbit/pan, срез и смену объекта.
Подсветка наведения должна совпадать с hit вокселем, а не с размером кисти.
Нижеследующий двухкликовый/модальный сценарий — исторический gate фазы 1;
он заменён описанным выше и не является текущей инструкцией для пользователя.

Targeted: `--headless --path . --script res://tools/test_voxel_fragment.gd`.
Проверки: чистый preview, материалы/группы, перенос/копия/90°, Undo/Redo,
stale/overlap/locked/bounds/slice refusal, save/reopen, два угла рамки,
add/subtract, cancel и диалог. Замер 16384 выбранных из 131072 ячеек.
Связанные scripts: test_voxel_selection, test_voxel_selection_mask,
test_voxel_groups, test_voxel_object_canvas, test_voxel_assembly_canvas.
Native Forward+ capture: тот же fragment script без --headless, с `-- --capture`.
Вручную: Canvas → Выделение вокселей → Объёмная рамка → включить «Выбирать»
→ два противоположных угла доски (для толщины можно повернуть камеру).
Shift добавляет, Ctrl вычитает второй объём. «Перенос / копия / поворот…»:
смещение/ось/90°/копия → Обновить предпросмотр → Применить. Проверить совпадение,
Undo/Redo, отмену, запрет перекрытия; сохранить Canvas/сцену и открыть снова.
Отделение в новый объект не входит в готовую фазу 1; общий контракт остаётся открыт.

## Поверхность прохода (ручной gate открыт)

`--headless --path . --script res://tools/test_walk_surface.gd`: создание,
редактирование, Undo/Redo, отмена, stale/invalid отказ, pack/save/reopen,
обычный physics ray и реальный EmberPlayer на опоре, отсутствие runtime Mesh.
Связанные gates: test_voxel_canvas_context, test_voxel_assembly_canvas
(включая сохранение секций рядом с опорой), test_voxel_placement,
test_voxel_scene_assembly, test_party_followers.
Native Forward+ capture: тот же script без --headless с `-- --capture`;
проверяет диалог на 1280×720 и 1600×900, но не заменяет редактор.
Вручную: выбрать группу настила → Ещё… → Поверхность прохода…; проверить
preview/применение, размер/наклон/высоту, предупреждения выступов, отмену;
выбрать WalkSurface и повторно открыть; Undo/Redo; переместить всю группу;
переключить «Показать поверхности прохода»; сохранить/перезапустить/F6.
Ожидание: сетка исчезает в игре, герой проходит настил и оба входа, края не
расширяют мост невидимо; общий Canvas секций не теряет опору. Доски и их
коллизии не изменяются. Вход с уступом требует выравнивания или наклонной опоры.

Статус: рабочая матрица проверок, 9 сентября 2026.

Этот документ отвечает на вопрос «что проверить сейчас». Подробные сценарии
завершённых v1/v2-этапов и старые журналы ручной приёмки можно восстановить из
монолитного Git checkpoint `20685ac`; они не определяют текущий порядок и не
заменяют будущие небольшие checkpoints. Условия окончательного выхода из JOI
принадлежат `docs/EMBER_JOI_EXIT_PLAN.md`.

## Основной принцип

Проверка идёт от узкого к широкому:

1. parse/static contract затронутых файлов;
2. самый узкий `tools/test_*.gd`;
3. связанный suite подсистемы;
4. cross-system regressions владельцев данных;
5. save/reopen, Undo/Redo, discard и validation, если менялся editor;
6. обычный Godot 4 Forward+ для UI, render, physics, input и ощущения;
7. полный headless-набор перед самостоятельным checkpoint.

Скриншот подтверждает композицию, но не клики, focus, input, persistence или
игровое ощущение. Ручная приёмка пользователя обязательна там, где результат
зависит от удобства или визуала.

## Безопасный запуск

Godot console:

`tools/godot/Godot_v4.7.2-stable_win64_console.exe`

Один targeted test:

```powershell
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_example.gd
```

Пакетный repository contract:

```powershell
python tools/test_vox_axes.py
```

Никогда не запускать рабочий checkout через `--headless --editor`: это меняет
editor-themed import variants и вызывает массовый повторный импорт. Editor/import
smoke выполняется только в отдельном checkout или import cache.

### Точная voxel-расстановка 2.3 (10 сентября 2026)

Ручная приёмка расстановки подтверждена пользователем.

### Группировка и ряд копий (10 сентября 2026, awaiting manual)

`tools/test_voxel_scene_assembly.gd`: unique user:// fixtures; rotated/nonuniform
parent, linked IDs, preview==commit, world collision relation, whole-row Undo/Redo,
repeat, group/ungroup world poses/owners/unique-name/order, grouped pack/reopen,
последующие наклоны и смещения, COW отдельной копии, byte-identical source,
scene save/reopen, stale/zero-step refusal, внешний NodePath, UI signals/Cancel.
Замер 32 копий печатается отдельно; это fixture-измерение, не гарантия FPS Причала.
`-- --capture` без headless запускает тот же fixture в Forward+ и сохраняет окно
1280×720 и 1600×900 без scaling. Нативный preview не заменяет настоящие editor clicks.
Новый gate и связанные placement/object_canvas/object_split/assembly_canvas PASS;
Forward+ оба размера просмотрены. 32 небольшие fixture-копии: 4.9–6.9 мс
на prepare+commit в двух проходах; для тяжёлых пользовательских моделей это
не является обещанием времени открытия или сохранения Canvas.

Ручной сценарий: выбрать доску → «Ещё… / Дублировать со смещением…» → задать шаг
X и 3 копии → проверить preview → создать. «Повторить дублирование» добавляет
одну следующую доску; смена выбранной детали меняет источник повтора. Наклонить
две доски через точную расстановку. Выбрать доски одного родителя (Ctrl в дереве)
→ «Собрать в группу» → переместить/повернуть группу → «Разгруппировать».
Проверить Cancel, Undo/Redo, сохранение/перезапуск и F6. Новые model-файлы не
появляются до Canvas Save реальной правки. Общий Canvas неровного моста не заявлен.

### Автоматические проверки расстановки 2.3

`test_voxel_placement.gd` использует только unique `user://` fixtures и проверяет
фактические размеры voxel после поворота/nonuniform scale, общий world step,
preview==commit, сохранение полного basis без decomposition, transformed parent,
центр/lower/custom source pivot, snap самой опорной точки, Undo/Redo, discard,
collision/children вместе с корнем сборки, save/reopen и byte-identical sources.
Stale parent/intermediate hierarchy, top-level descendant и non-finite plan
отказывают; ошибочный plan очищает возможность применить предыдущий preview.

`test_voxel_placement_preview.gd` запускается обычным Forward+ без `--editor` на
сохранённом TimberPier из 12 секций. Signal-driven gate проверяет числовой поворот,
смену pivot без скачка уже повёрнутого preview, auto-snap только изменённой оси и
отсутствие live mutation. Native unscaled captures 1280×720 и 1600×900 сохраняют
двухколоночный диалог: controls scroll слева, постоянно видимый target+context
preview справа, Apply/Cancel снаружи. Это не заменяет реальные editor clicks.

Ручной gate: в Причале выбрать `TimberPier/Visual` или отдельную `Part` → «Точная
расстановка…». Отключить snap, дать доске небольшое смещение и произвольный угол;
Cancel не меняет сцену. Открыть снова, выбрать нижний угол, шаг 1, «Привязать
сейчас», повернуть +90° и применить. Проверить Ctrl+Z/Redo, затем сохранить сцену,
перезапустить editor и запустить F6. Для живого настила повторить на нескольких
отдельных досках: scale/наклон не должны самопроизвольно выровняться. Group
creation, duplicate-repeat, склейка и общий Canvas наклонённых деталей этим gate
не заявлены.

### Конверсия простых форм 2.2 (10 сентября 2026)

Assembly Canvas gate: `test_voxel_assembly_canvas.gd` проверяет общий draft,
каналы/группы, мазок через две секции и один Undo, сохранение 2 из 4, неизменные
hash/IDs остальных, batch Undo/Redo, ошибку второго destination без частичного
scene apply, cancel/discard, scene reopen, несовместимое смещение и разные
порядки палитр. `test_voxel_assembly_preview.gd`: Forward+ viewport всей сборки
192×10×256 из 12 секций, только fixtures в user://. Ручной gate: выбрать группу
(не Part) → «Объект / сборка в Canvas» → мазок через стык → Ctrl+Z/Redo → Save →
сохранить сцену → переоткрыть группу/отдельную Part → F6 и пройти через стыки.
Целый editor click lifecycle этим runtime preview не подтверждается.

Оптимизация/резка: PASS `test_voxel_projection_cache`, `test_voxel_object_split`,
`test_voxel_object_canvas`, `test_voxel_canvas_growth`, `test_voxel_shapes`,
`test_voxel_primitive_conversion`. Cache test сравнивает все mesh arrays/indices
и collision faces со старым builder, halo-правку, palette/density/empty и
отсутствие alias на опубликованный mesh. Split test проверяет все каналы,
группы, transformed world anchors, unique IDs, Undo/Redo, source hash и reopen
геометрии/коллизии; physics ray проверяет высоту точно на стыке X и по обе
стороны от него. `benchmark_voxel_save_reuse` A/B (старые повторные сборки
только in-memory): настил 192×10×256, до 11964/14007 мс, после 6674/5085 мс.
`test_voxel_split_preview` проверяет native окно на текущем TimberPier Forward+
без применения; это не полный editor click/physics gate.
Ручной gate: выбрать voxel Visual настила → «Разрезать на секции…» → 64 →
проверить 12 границ/деталей → отменить (нет изменений) → открыть/применить →
Ctrl+Z/Redo → открыть одну Part в Canvas, изменить/сохранить → сохранить сцену →
перезапустить → F6 и пройти через стыки. Сложные overrides/вода должны отказать
без изменений сцены. При сбое диска возможны оставленные recoverable part assets.

Большой бюджет: `test_voxel_shapes` проверяет ровно 524 288, отказ выше порога,
явное разрешение предпросмотра и его сброс после изменения параметров.
`test_voxel_primitive_conversion` включает размеры TimberPier 192×10×256,
физический/декоративный вариант, edit/save/reopen источника, Undo/Redo и сцену.
Ручной gate: TimberPier → при необходимости совместить коллизию → «Форму в
voxel…» → разрешить тяжёлый preview → обновить → преобразовать → мазок →
сохранить Canvas и сцену → перезапуск → F6. Отмена до применения не меняет сцену.

Совмещение коллизии: выбрать TimberPier с небольшим смещением Visual →
«Форму в voxel…» → проверить точные XYZ в подтверждении → «Совместить коллизию
с моделью». Visual не двигается; Collision получает его transform. Повторная
команда открывает conversion dialog (лимит размера остаётся). Ctrl+Z возвращает
расхождение, Redo устраняет его; сохранить/открыть сцену и повторить команду.
Отмена подтверждения ничего не меняет. Headless conversion test проверяет
совмещение/Undo/Redo для трёх форм и отказ для disabled collision; PASS.

5/5 PASS: `test_voxel_primitive_conversion`, `test_voxel_shapes`,
`test_voxel_object_canvas`, `test_voxel_canvas_growth`, `test_voxel_canvas_context`.
Conversion gate: блок/цилиндр/сфера с физикой и без, поворот/неравномерный scale
parent, fit bounds по параметрам PrimitiveMesh (не погрешностям tessellation),
имя/owner, отсутствие двойной коллизии, layer, Undo/Redo, save/reopen/Canvas,
отказ от PlaneMesh/конуса и stale preview. Preview не создаёт files.

Opt-in `tools/editor_test_voxel_conversion.gd` только в disposable
`ember-canvas-smoke-*`: настоящая toolbar-команда на MooringPost96_240,
переключение исходник/voxel, commit→Canvas+окружение, Undo/Redo, scene Save/reopen.
Forward+ functional PASS; native dialog и Canvas captures просмотрены. Не
называть zero-error lifecycle: при автоматическом выходе остаются известные
absolute-get_node diagnostic и scan-aborted; node cache error не наблюдался.

Ручная приёмка: сохранить сцену → выбрать `Map/Props/MooringPost96_240`
или его `Visual` → «Форму в voxel…» под 3D toolbar → сравнить исходник/preview →
«Преобразовать и открыть Canvas». Включить окружение, сделать мазок, сохранить
Canvas и сцену. Отдельно проверить отмену диалога (нет новых объектов/файлов),
Undo/Redo конверсии в 3D, reopen и F6: столб стоит на прежнем месте и имеет
одну обновлённую коллизию. Проверить простые цилиндр и сферу аналогично.
Большой TimberPier/StoneQuay может превышать лимит: явно уменьшить XYZ в
preview; габариты сохраняются fit scale, а не скрытым clamp.

### Object Canvas: переключаемое окружение (10 сентября 2026)

5/5 focused/related scripts PASS: `test_voxel_canvas_context`,
`test_voxel_canvas_growth`, `test_voxel_object_canvas`, `test_voxel_shapes`,
`test_voxel_surface_sculpt`. После уточнения stable anchor повторены context
и object-canvas tests: PASS. Context gate проверяет transform при повороте и
неравномерном масштабе parent/prop, material identity, remap после расширения,
Save Undo/Redo, прозрачность без mutation, исключение target/hidden/physics,
отсутствие scripts/owners у фона, refresh и освобождение при закрытии сцены.

Opt-in `tools/editor_test_voxel_context.gd` только в disposable
`ember-canvas-smoke-*` project: Причал/BarrelA, 60%→100%→off, совпадающий ray pick,
реальный draft stroke/discard без записи source. Forward+ functional PASS,
68 фоновых visuals за ~1.5 мс; captures 1600×900 просмотрены. На автоматическом
выходе только известный warning `Scan thread aborted`, без engine/script errors.

Ручная приёмка: выбрать BarrelA в Причале → «Объект в Canvas» → «Показать
окружение»; рядом должны появиться настил и соседняя бочка. Фон 100% для посадки,
30–60% для лепки. Нарисовать, Undo/Redo, сохранить Canvas и сцену; фон сам по себе
не создаёт unsaved changes. Выключить toggle — прежний изолированный вид.
После изменения соседей в 3D нажать «Обновить окружение». После grow холста
посадка прежних вокселей не меняется. Свет карты/динамика проверяются отдельно F6.

### Проверки расширения и cross-map создания

Команды: `tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path .
--script res://tools/<name>.gd` (в одну строку, последовательно).
Прошли 7/7: `test_voxel_canvas_growth`, `test_voxel_shapes`,
`test_voxel_object_canvas`, `test_voxel_surface_sculpt`, `test_voxel_groups`,
`test_content_migration_report`, `test_content_migration_dashboard`; exit 0,
без script/engine errors. Growth 16³→32³ вместе с Canvas rebuild: 44–51 мс.
Проверяются preview без mutation, remap материала/групп, размеры, запрет
shrink/скрытого округления/переполнения, Undo/Redo, discard, Save Undo/Redo,
геометрия без world-сдвига/масштабирования, коллизия, reopen.

Actual-editor fixture `editor_test_voxel_shapes.gd` расширен переходом
agent_sandbox→test_pier, созданием/Inspector/Save на обеих картах, расширением
и повторной загрузкой сцен. Forward+ functional assertions PASS, node-cache
ошибка после исправления не повторилась. Просмотрены captures новых кнопок и
native growth dialog при 1600×900. Это не утверждение о чистом shutdown всего
редактора: автоматический прогон оставлял progress-dialog/absolute-get_node
diagnostics и scan-aborted при завершении; его нельзя называть zero-error smoke.
Последний Forward+ повтор с ожиданием filesystem завершил все assertions,
включая фактическое открытие creation dialog через кнопку Canvas. Ошибок
node-cache/progress-dialog больше нет; остаются только absolute-get_node и
scan-aborted при автоматическом выходе. Логи временной копии:
`%TEMP%/ember-canvas-smoke-growth-c58d315d40ed4636bf7ab5efd9c87715/growth6-{out,err}.log`.

Ручная приёмка:
1. Сохранить текущие правки, перезапустить редактор для обновления обеих plugin
   панелей. В 3D под штатными инструментами видны «+ Объект» и «Объект в Canvas».
2. Создать блок 16×16×16, открыть Canvas → «Расширить холст…» → 32×32×32 →
   «Применить». Это запас пустых вокселей, а не растяжение объекта.
3. Нарисовать в новом запасе, отменить мазок и расширение, повторить Redo.
   Проверить отдельно «Отмена» в диалоге и отказ от несохранённых изменений.
4. Сохранить Canvas, затем сцену Ctrl+S в 3D. Повторно открыть объект: размеры
   сохраняются, старая часть не сдвинулась, коллизия соответствует форме.
5. Открыть две карты, на каждой создать объект; выбрать его в Inspector,
   сохранить сцену, переключиться назад. Нет node-cache ошибки, объект принадлежит
   нужной карте. Проверить также «+ Объект» в Canvas и отмену создания.

Ограничения: XZ кратны плотности 16/32 и растут симметрично, Y растёт вверх;
до 524 288 ячеек, нет уменьшения и расширения заполненных water channels.

Все test fixtures пишутся в `user://` или временные данные. Авторские `.tres` и
`.tscn` не перезаписываются ради теста. Отключённый `addons/at-icons` остаётся
изолирован через `.gdignore`.

## Как выбрать gate

- Документация без изменения контрактов: `git diff --check`, проверка ссылок и
  `python tools/test_vox_axes.py`.
- Resource/schema: validation, normalization, save/reopen и все consumers.
- Editor mutation: model/action test, Undo/Redo, discard, save/reopen и реальный
  Inspector/workspace.
- Runtime state: pure owner test, transition/serialization и запуск сцены.
- Render/physics/input: headless correctness плюс ручной Forward+.
- Производительность: повторяемый профиль на репрезентативной карте до и после;
  schema меняется только при измеренном доказательстве.
- Migration mutation: read-only inventory → strict parity → ограниченная запись →
  Undo/Redo → reopen → frozen-source hash.

## Surface и voxel authoring

Минимальный suite выбирается по затронутому контракту:

- Resource/serialization: `tools/test_native_voxel_resource.gd`;
- selection и masks: `test_voxel_selection.gd`,
  `test_voxel_selection_mask.gd`;
- groups/palette: `test_voxel_groups.gd`, `test_voxel_palette.gd`;
- sculpt/tools: `test_voxel_surface_sculpt.gd`,
  `test_voxel_tools_backend.gd`;
- Canvas lifecycle: `test_surface_canvas_workflow.gd`,
  `test_surface_height_slice.gd`, `test_native_cutaway.gd`;
- large dense profile: `test_surface_large_profile.gd`;
- derived prefab/preview: `test_voxel_prefab_rebuild.gd`,
  `test_voxel_preview_renderer.gd`;
- physical world: `test_world_surface_projection.gd`,
  `test_fan_town_surface_projection.gd`;
- water boundaries/contact: `test_water_contact_boundaries.gd`;
- scale/tile library: `test_voxel_tile_scale.gd`,
  `test_battlefield_tile_library.gd`.

Editor acceptance дополнительно требует:

- одна mutation = одна понятная Undo/Redo-операция;
- Save/Discard/Cancel при выходе и корректный reopen;
- editor-only selection, visibility, camera и slice не попадают в gameplay data;
- мелкий input не запускает полный remesh/reload;
- Surface, world и battle используют одинаковые palette/water границы;
- обычный Forward+ viewport без швов, исчезающих chunks и renderer warnings.

## Graph, Object Inspector и native content

Основные gates:

- `tools/test_graph_workspace.gd` и `test_graph_lifecycle.gd`;
- `test_object_inspector_model.gd`, `test_object_inspector_actions.gd`,
  `test_object_inspector_panel.gd`;
- `test_action_resource.gd`, `test_action_script.gd`,
  `test_action_chain_authoring.gd`;
- `test_dialogue_authoring.gd`, `test_vn_dialogue_resource.gd`;
- `test_quest_state.gd`, `test_quest_journal_authoring.gd`,
  `test_quest_usage_index.gd`;
- `test_item_resource.gd`, `test_shop_resource.gd`,
  `test_shop_persistence.gd`;
- visual catalogs: `test_visual_library.gd`, `test_map_visual_library.gd`,
  `test_voxel_visual_library.gd`, `test_vn_background_library.gd`,
  `test_vn_portrait_library.gd`;
- scene binding: `test_standalone_trigger_authoring.gd`,
  `test_interact_launch_rules.gd`, `test_scene_edit_roundtrip.gd`.

Ручная проверка проводится минимум на 1280×720 и 1600×900, если менялась
компоновка. Нужно проверить mouse и keyboard focus, dirty-draft guard, validation
на конкретном Resource, save/reopen и сохранение scene-owned children после
reimport.

## Exploration, party и save

Основные gates:

- `tools/test_progress_restore.gd`;
- `test_camera_relative_movement.gd`;
- `test_party_save_v2.gd`, `test_party_followers.gd`,
  `test_party_progression.gd`;
- `test_inventory_equipment.gd`, `test_health_consumables.gd`;
- `test_map_transition.gd`, `test_talk_shop.gd`;
- `test_explore_pause_menu.gd`, `test_defeat_respawn.gd`;
- `test_combat_encounter_transition.gd`, `test_combat_result_bridge.gd`.

Обязательные сценарии save:

1. новый старт и три ручных слота;
2. отдельный autosave и metadata без загрузки полного состояния;
3. v1→v2 один раз с byte-identical backup;
4. несовместимая экипировка возвращается в общую сумку;
5. HP/MP/XP/equipment переоткрываются, derived stats пересчитываются;
6. удаление слота требует подтверждения и оставляет recovery-копию;
7. бой получает предбоевой snapshot, Retry начинает с него, результат
   применяется один раз.

Ручной Forward+ gate проверяет смену лидера через `Tab`, оба режима следования,
переход между картами и сохранение/загрузку из реального pause menu.

## Combat

Базовый suite:

- Resource contracts: `tools/test_battlefield_resource.gd`,
  `test_combat_status_resource.gd`, `test_combat_action_resource.gd`,
  `test_combat_unit_resource.gd`,
  `test_combat_ai_profile_resource.gd`, `test_combat_loot_table_resource.gd`,
  `test_encounter_resource.gd`;
- resolver: `test_combat_prototype.gd`;
- navigation/positioning: `test_combat_grid.gd`;
- controller/HUD: `test_combat_lab.gd`;
- arenas/camera/view: `test_combat_arena_scenes.gd`,
  `test_combat_camera_rig_preview.gd`, `test_combat_vertical_view.gd`;
- animation: `test_combat_vertical_animation.gd`;
- performance: `test_combat_vertical_profile.gd`;
- content/effects: `test_combat_effect_library.gd`,
  `test_combat_personal_actions.gd`;
- inventory/progression: `test_combat_items.gd`,
  `test_party_progression.gd`;
- results/transition: `test_combat_result_bridge.gd`,
  `test_combat_encounter_transition.gd`.

При изменении общей боевой логики сначала запускаются точные targeted tests,
затем все `tools/test_combat*.gd` и соседние Battlefield/Encounter/party/save
gates.

Combat invariants:

- один resolver и один canonical battle snapshot;
- статусы принадлежат canonical `.tres`, а effect validation не принимает
  неизвестные status IDs;
- внутренние status/damage/effect rules не владеют snapshot и не обходят
  публичные `preview/commit`;
- preview и commit используют один зафиксированный результат;
- hostile hit/crit/damage не раскрываются игроку до commit;
- support, healing, movement и mechanisms детерминированы;
- игрок и AI используют одинаковые terrain, range, LOS и path rules;
- movement-only AI pursuit проходит полный result-контракт, меняет клетку и
  завершает ход ровно один раз; отклонённый commit не запускает presentation;
- одна проходимая высота на колонку, без stacked floors;
- animation/HUD не мутируют gameplay state;
- Retry не сохраняет затраты пробной попытки;
- победный результат и XP применяются ровно один раз.

Ручной Combat Lab gate проверяет поле 10×8 и 16×12, camera axis locks и focus,
mouse/keyboard/gamepad navigation, browse/confirm/target/cancel, auto-approach,
Attack/Defend stop marker, статусы, подъём/бросок и отсутствие исчезновения поля
на допустимом наклоне.

## Lighting и Forward+ gate

Профили света проверяются в порядке `0/2/4/8/12/16`: `8` — production,
`12` и `16` — stress. В Play `F3` показывает active/candidate shadows и
frame/render metrics, `F4` переключает профили. Изменение света, материалов,
воды или derived mesh проверяется на production-профиле и минимум одном stress
профиле; подробный художественный gate остаётся в `LIGHTING_GATE.md`.

Механики проверяются на Ember-сценах, а не на `hu_tao_yard`/`hu_tao_p1`.
Forward+ проверка должна подтвердить отсутствие shader/renderer errors,
исчезающих chunks, неверной прозрачности и изменений collision из-за
visual-only эффекта.

## Combat Lab v2.64.4 positional/hold regression gate

Срез зафиксирован в checkpoint `4569f64`; дополнительная ручная проверка кольца
завершений подъёма принята пользователем. Regression gate сохраняет следующие
критерии:

1. непарные support/heal/item/cell/lift-команды используют тот же positional
   planner, что hostile-команды;
2. hover показывает range и возможную stop-cell, confirm открывает targeting,
   cancel возвращает прежний focus;
3. если применение недостижимо за MOVE, герой останавливается на предельной
   клетке и защищается без расхода MP/item/выбранного действия;
   cell-target команда при этом не подсвечивает удалённую пустую клетку как
   выполнимую: её область ограничена MOVE + authored range;
4. подъём может завершиться удержанием; связь живёт только в battle snapshot;
5. удерживаемую цель нельзя атаковать, она пропускает ход без накопления;
6. носитель не перемещается и выбирает только `Бросить`, `Опустить` или
   `Удерживать и защищаться`;
7. первое подтверждение lift-цели проигрывает только presentation-подход и
   подъём; затем доступны `Бросить / Опустить / Удерживать и защищаться`;
   после завершения подъёма они появляются в кольце у носителя без отдельной
   нижней/боковой панели; Cancel из выбора клетки броска возвращает это кольцо;
   Cancel, включая середину подхода, возвращает исходный snapshot и presentation
   без телепорта, сохраняя заранее выбранное M;
8. гибель носителя детерминированно опускает цель на ближайшую допустимую клетку;
9. stale preview не может списать ресурс или применить результат;
10. AI и player route не расходятся;
11. 16×12 cell-target profile остаётся ниже 20 мс в среднем, а UI переиспользует
    один расчёт на refresh;
12. schema Action/Battlefield/save и owner resolver не меняются.

Удерживаемая цель исключена из обычных direct/cell/AOE/status effects. Носитель
получает эффекты штатно, они не переносятся на удерживаемого бойца, а гибель
носителя освобождает цель. Gate проверяет прямую, клеточную и площадную попытку.

Минимальные автоматические gates: `test_combat_grid.gd`,
`test_combat_prototype.gd`, `test_combat_lab.gd`, `test_combat_items.gd`,
`test_combat_personal_actions.gd`; затем весь combat suite и соседние
transition/party/save tests. Ручная приёмка — обычный Forward+ Combat Lab на
обоих размерах поля.

## ActionPlan regression gate (поверх v2.64.4)

- `test_combat_action_plan.gd`: strike/ranged/support/heal/item/lift/cell/spread/
  self/movement; путь заканчивается в stop; MOVE+range; явное M в исходной
  клетке; revival через occupant; stale context; один commit.
- `test_combat_lab.gd`: menu movement/cast/filtered targets; hover A-B-A и
  cell footprint без клика; недопустимая B не сохраняет executable preview;
  3D roots/input и 2D buttons сохраняют instance IDs; public preview не содержит
  скрытых результатов; полный и прерванный lift approach/cancel.
- `test_combat_vertical_animation.gd`: M не проигрывается повторно перед lift;
  cancel сохраняет staged M; throw, duo и defend presentation продолжают работать.
- Затем все `test_combat*.gd`, `test_battlefield*.gd`, `test_encounter*.gd`,
  `test_party*.gd`, `test_*save*.gd` последовательно (shared user:// fixtures).
- Обычный Forward+ render smoke обеих арен выполнен на RTX 5070, без editor/import.
  Ручной gate подтверждён пользователем: реальная мышь и геймпад, hover границы
  дальности, цвет fallback/invalid, M, lift cancel в пути и после подъёма, три
  финальных варианта, читаемость HUD и непрерывность анимации на 10×8/16×12.

Команда targeted test (из checkout; путь exe можно заменить локальным):

```powershell
& C:/Users/novos/Projects/ember-godot/tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_combat_action_plan.gd
```

## Production defeat/Retry gate

Поражение авторской встречи не является persistent result commit. Gate требует:

1. defeat-modal предлагает `Повторить` и `Загрузить сохранение`, а не возврат в
   мир с нулевыми HP или потраченной сумкой;
2. Retry восстанавливает точные предбоевые party, inventory, authored deployment
   и исходное состояние поля, но создаёт новый RNG seed;
3. Retry не меняет `EmberExploreState`, не пишет ручной слот/автосейв и не
   применяет XP, награды, flags или combat counters;
4. load-only панель показывает три ручных слота и отдельный автосейв по metadata
   существующего save v2 owner; пустые слоты недоступны;
5. успешная загрузка открывает сохранённую сцену и очищает process-local combat
   handoff; ошибка сохраняет defeat-modal и возможность Retry;
6. победа по-прежнему применяет результат ровно один раз; authored Action,
   Battlefield и save schemas не меняются.

Минимальный gate — `tools/test_combat_defeat_retry.gd`, затем
`test_combat_lab.gd`, `test_combat_encounter_transition.gd`,
`test_combat_result_bridge.gd`, `test_party_progression.gd`,
`test_party_save_v2.gd`, весь `tools/test_combat*.gd` и соседние encounter/
party/save scripts. Ручная Forward+ приёмка проверяет поражение после расхода MP
и предмета, Retry, новый seed, выбор ручного слота/автосейва, Esc-назад и focus
мышью/клавиатурой/геймпадом.
Текущий gate пройден: 27/27 связанных scripts, Vulkan Forward+ capture и ручной
mouse/gamepad сценарий подтверждены 8 сентября 2026.

## Pre-battle deployment gate

`EmberBattlefieldResource.party_deployment_cells` остаётся единственным authored
owner: первые N клеток задают начальную позицию N героев, а лишние клетки в том
же массиве включают расстановку и образуют разрешённую зону. Ровно N клеток
автоматически пропускают фазу, поэтому `colored_crossing_demo` остаётся
фиксированным первым боем. Для ручной демонстрации E4 расширяет только зону
`vertical_forge_10x8`, не меняя первые четыре позиции.

Gate требует:

1. сохранённая стратегия (только порядок hero IDs, без координат) применяется к
   первым N authored cells до UI; старый/отсутствующий/битый save v2 сохраняет
   прежний порядок, transition передаёт deep copy, direct Lab использует autoload;
2. ready-окно содержит ровно `НАЧАТЬ БОЙ` и `ИЗМЕНИТЬ СТРАТЕГИЮ`; поле и союзники
   видны полностью, а зона, hero tools, timeline, radial commands, AI, action
   commit и расход RNG скрыты/заблокированы;
3. Edit открывает детальный режим: mouse и стандартный grid cursor выбирают героя
   и свободную клетку; занятая героем клетка делает swap, а
   blocked/focus/enemy/out-of-zone отклоняются;
4. `Сбросить` возвращает persisted strategy, `Начать бой` доступно только для
   полного уникального placement и убирает phase-only UI/markers;
5. confirmed manual placement остаётся только в процессе боя и не меняет preset;
6. defeat Retry восстанавливает confirmed custom placement, party, inventory и
   поле с новым seed без повторного открытия расстановки; обычный Lab Reset
   возвращает persisted strategy и открывает ready снова; exact-N игнорирует
   preset и автоматически пропускает ready/edit.

Узкий gate — `tools/test_combat_prebattle_deployment.gd`; непосредственно
связанные `test_combat_lab.gd`, `test_combat_encounter_transition.gd`,
`test_combat_defeat_retry.gd`, `test_encounter_resource.gd`,
`test_battlefield_resource.gd` и дополнительный `test_combat_grid.gd` проходят.
Все 20 `test_combat*.gd`, `test_party_save_v2.gd`,
`test_inventory_equipment.gd`, `test_party_progression.gd` и
`test_battlefield_resource.gd` проходят. Обычные Vulkan Forward+ captures E4 и
inventory прошли без script/renderer errors и подтвердили полностью видимое поле,
ready с двумя actions и встроенный Strategy section. Ручная приёмка реальной
мышью/клавиатурой/геймпадом и menu save/reopen подтверждена пользователем.

## Active party 1–4 gate

### Voxel shapes + empty lifecycle, stage 2.1

`test_voxel_shapes.gd`: точные occupied bounds блока/цилиндра/сферы при 16/32,
диаметры 1/2/3/7/16/17/32, явные отказы height/budget без clamp, no-files preview,
creation Undo/Redo, non-16 world scale и transformed parent, empty Canvas
camera-ray→stroke→save_changes, empty→solid→empty с authored child под Shape,
Undo/Redo/save/reopen, shared linked empty lifecycle, failed destination rollback.
При пустой форме ни прежние voxels, ни коллизия не возвращаются сами.

9/9 headless scripts PASS: voxel_shapes, voxel_object_canvas,
surface_canvas_workflow, voxel_surface_sculpt, voxel_prefab_rebuild,
scene_edit_roundtrip, object_inspector_actions, object_inspector_model,
object_inspector_panel. После empty-aware Inspector изменения повторены shapes,
object_inspector_model и object_inspector_panel: PASS.
Plugin parse и diff-check прошли. Замер generator+prepare: доска 32×2×8 —
8.25 мс; 64×32×64 (131 072 cells) — 594.92 мс. Старый кандидат лимита
128×64×128 занял 4725 мс: лимит окна создания снижен, schema не менялась.

Actual EditorPlugin fixture `tools/editor_test_voxel_shapes.gd` включается только
в disposable ember-canvas-smoke-* project. Fresh import прошёл без ERROR;
Forward+ fixture проверил создание через native dialog, force rebuild нового
пустого native ID, настоящий Canvas mouse/ray first-voxel Save, editor scene Save,
Undo/Redo/reopen и создание доски 16×2×32. Functional assertions PASS. Capture
диалога берётся из его собственного Window viewport. Ошибку бесконечного роста
dialog minimum-size устранили фиксированной высотой preview и scrollable body;
Create/Cancel остаются вне scroll. Автоматический выход иногда по-прежнему даёт
absolute get_node ERROR/scan-aborted после functional PASS — старый editor teardown
долг отмечается отдельно, весь lifecycle не объявляется чистым.

Ручной gate: открыть 3D-сцену → «Проект / Инструменты / Ember: Новая voxel-форма…».
Блок 16×2×32 → «Обновить предпросмотр» → «Создать и открыть Canvas»; проверить
размер/цвет, Undo создания и Redo, затем Ctrl+S сцены. Повторить пустую область:
в Canvas инструмент «Объём», операция «Добавить», клик по нижней плоскости;
Save создаёт геометрию/коллизию. Стереть всё и Save — коллизии нет, Node остаётся
в дереве сцены; Undo/Redo и save/reopen возвращают ожидаемое состояние.
«Отмена» диалога не создаёт source/prefab/scene node. Конверсия 2.2 и точная
расстановка 2.3 описаны отдельными gates выше.

### Voxel object → Canvas → scene, stage 1

`test_voxel_object_canvas.gd` использует unique user:// sources/prefabs/scene:
detached open/discard без файлов, selected-only Save, stable повторный ID/UID,
отдельные mesh/shape, GEN_EDIT_STATE_INSTANCE pack/reopen с nested authored child,
world pose, Undo/Redo с прежними faces, shared edit двух связанных объектов,
CACHE_REUSE нового source/prefab, independent copy и guard Cancel/Discard/Save.
Отказы: удалённый target, изменённый source, недоступная папка и
water-fill правка; исходные файлы/узлы при этом не применяются частично.
Начиная с 2.1 пустая native-модель поддержана, а не является validation отказом.
Native BarrelA проходит preflight, CargoA безопасно отказывается из-за несовпадения
legacy baked geometry. `-- --capture` обычным Forward+ сохраняет object-canvas.png
в fixture папку и печатает абсолютный путь.

13/13 headless gates прошли 9 сентября 2026 без SCRIPT ERROR/ERROR:
voxel_object_canvas, surface_canvas_workflow, voxel_surface_sculpt,
voxel_selection, voxel_selection_mask, voxel_groups, voxel_palette,
voxel_prefab_rebuild, scene_edit_roundtrip, object_inspector_panel,
object_inspector_model, object_inspector_actions, voxel_migration_queue.
Plugin parse-check прошёл. После финального исправления cache/guard повторены
object_canvas и surface_canvas_workflow. Старый migration_queue test пересобрал
четыре generated node UID кровати; эти побочные изменения возвращены точечным patch.
Обычный Forward+ object_canvas --capture на RTX 5070 прошёл: просмотрены Canvas,
геометрия, палитра и scope выбранного экземпляра. Отдельная disposable editor-копия
с открытием test_pier прошла import/plugin activation/layout smoke без ERROR,
exit 0. Для прежних legacy-систем её ember/pack_path указывал на существующий
архив абсолютным путём только в temp project.godot; live project не менялся.

После дефектов ручной приёмки добавлен opt-in EditorPlugin fixture
`tools/editor_test_voxel_object_canvas.gd` (включать только в disposable
ember-canvas-smoke project). Реальный Engine.is_editor_hint=true: Canvas Save,
EditorUndoRedoManager Undo/Redo, scene save/reopen и bounds 1500→1000→1200→1500
при высоте рабочей области 650 прошли без ERROR. `-- --capture` открывает реальный
main-screen Canvas редактора и сохраняет PNG с печатью размера центральной области.
Headless runtime отдельно проверяет непустые уникальные placement_id всех пяти
voxel props Причала. Проверка логов обязательна: exit 0 сам по себе недостаточен.
После исправлений повторены 6/6: voxel_object_canvas, surface_canvas_workflow,
voxel_prefab_rebuild, scene_edit_roundtrip, object_inspector_actions, test_test_pier;
все PASS без ERROR, plugin check-only и git diff --check также прошли.
После уточнения root source signature повторены object_canvas,
surface_canvas_workflow, scene_edit_roundtrip и object_inspector_actions: PASS.
Forward+ в настоящем editor: проверен кадр центральной области 1084×741 внутри
окна 1800×900 — Save, sidebar и Inspector видимы, placement заполнен, prefab
«актуален». Это функциональная/визуальная проверка, не чистый полный lifecycle:
при автоматическом выходе fixture оставался ERROR absolute get_node и scan-aborted.
В старой многократно изменённой smoke-копии также встречался intermittent
get_dependencies. Adjacent stage теперь имеет нераспознаваемый `.tmp` suffix
(точка в имени на Windows не означает hidden attribute), сериализация user://
сохранена для асинхронных editor readers. Новый disposable import прошёл чисто;
повторный actual run проверил Save/Undo/Redo/signature, но полный capture/выход
не завершился; после принудительного предыдущего выхода был DLL-copy diagnostic.
Полный чистый fresh editor lifecycle остаётся открытым, а не считается PASS.

Если остался черновик после прежнего failed Save, сначала попробовать Save после
hotreload кода, не закрывая Canvas. После успешного Save модели проверить
Placement ID: у уже открытого BarrelA с пустым ID вручную поставить
`pier_barrel_a` в Inspector, затем Ctrl+S сцены. Изменение файла не гарантирует
обновление уже открытой dirty-сцены. После этого безопасно перезапускать редактор
ради новой раскладки. Hotreload
существующего placeholder не считается гарантированным; при повторной ошибке
черновик не отбрасывать и не перезапускать редактор до отдельного восстановления.

Ручной gate открыт: в test_pier выбрать Map/Props/BarrelA → «Создать экземпляр» →
исходную бочку → «Редактировать в Canvas», изменить воксель, сохранить → 3D:
изменилась только выбранная, collider следует новой форме. Повторный Save в этом
сеансе не создаёт ещё source; Ctrl+Z/Redo в 3D возвращают форму/ссылки. Сохранить
сцену обычным Ctrl+S, закрыть/открыть: форма и authored children остаются.
Для linked-пары проверить shared-команду (закрыть остальные вкладки сцен), затем
independent copy; изменения исходника не должны затрагивать независимую копию.
Проверить «Остаться», «Отбросить», «Сохранить» при смене объекта и выходе из Canvas.
Новая editing session создаёт новый fork по умолчанию; cross-tab shared update,
water fill и несовпадающий legacy prop пока не поддержаны. Полностью пустая native
модель поддержана последующим этапом 2.1, см. gate выше.

### Test Pier — отдельный exploration gate

`tools/test_test_pier.gd` загружает `scenes/test_pier.tscn` как F6, проверяет
активную пару protagonist/mira, одного follower, Tab, два героя сумки и Q/E,
authored content без legacy hydration, физический пол, ray/capsule к западной
границе воды. Реальный pause-menu load после перемещения A→B возвращает A через
reload сцены; следующий F6-equivalent старт сохраняет пару и A. Сохранение
содержит mapId=test_pier. SHA256 исходных v1/v2 папок остаются неизменны;
тест пишет в unique `user://ember-tests/test-pier-*`.
Обычный Forward+ `-- --capture` сохраняет `pier.png` и `pier-inventory.png`
в fixture папке, печатает абсолютные пути и завершает процесс.
Targeted и Forward+ пройдены 9 сентября 2026. Связанные party_followers,
party_save_v2, progress_restore, map_transition, inventory_equipment,
explore_pause_menu, camera_relative_movement — 7/7 PASS; pack contract и
`git diff --check` пройдены. Ручной gate: F6 именно
test_pier.tscn → пройти настил/берег, обойти грузы и все края (нет падения в воду),
Tab и I/Q/E дают только двух героев, T меняет следование, RMB вращает камеру;
Esc → сохранить, отойти, загрузить, закрыть и снова F6 → прежнее место/пара.
Автоматический edge probe не заменяет ручной обход всех границ.
Regression первого editor-open: `test_voxel_surface_sculpt.gd` запускает отдельный
`--native-selector-probe` и отвергает любой ERROR в его output даже при exit 0.
Реальная test_pier привязывается к selector через обычный refresh_context:
без Surface toolbar скрыт; повторный выбор Map не читает legacy JSON; временные
неизвестные размеры безопасны; native Surface даёт размеры; legacy fan_town
сохраняет прежний полный grid с heights. Sculpt, world_surface_projection и
test_test_pier повторно проходят после исправления. Ручной повтор: закрыть/открыть
test_pier, выбрать Map, F6; новых ошибок `cannot read ... test_pier.json` быть не должно.
Бой/Retry active-party gate ниже этим не закрывается.

Контракт 9 сентября 2026 сохраняет единственные Explore/Party/save owners.
`test_party_save_v2.gd` проверяет 1–4, strict setter, missing/corrupt
`activeHeroIds` → legacy четыре, reopen/adopt с синхронным UI listener и metadata.
`test_party_followers.gd` проверяет solo Mira, пару без ГГ, изменение состава при
прежнем лидере, уход лидера и Tab без смещения игрока.
`test_inventory_equipment.gd` проверяет запрет inactive equip/use/unequip,
циклический выбор пары, roster reorder при открытой сумке и сохранение полного
порядка стратегии. `test_encounter_resource.gd` покрывает compatible subsets и
отказ unsupported/capacity; `test_combat_encounter_transition.gd` — отказ до
смены сцены без мутаций, pending/active lock, snapshot isolation и solo/pair
victory. `test_party_progression.gd` и `test_combat_result_bridge.gd` проверяют
XP только участников, павших, preview=commit и неизменность отсутствующих.
`test_combat_prebattle_deployment.gd` сохраняет exact-four baseline и проверяет
пару в четырёх cells; `test_combat_defeat_retry.gd` добавляет pair Retry с точным
составом, placement, HP/MP/inventory и новым seed без мутаций мира.

9 сентября 2026 прошли 34/34 scripts (exit 0, без SCRIPT ERROR/ERROR/FAIL):
20 combat, 2 battlefield, encounter, inventory, 3 party, а также
health_consumables, progress_restore, explore_pause_menu, map_transition,
defeat_respawn, talk_shop и camera_relative_movement. Запуск последовательный
из-за shared user://. `python tools/test_vox_axes.py` и `git diff --check` прошли.
Обычные Forward+ followers и defeat/retry на RTX 5070 завершились с exit 0;
просмотрены четыре PNG: пара в мире, сумке, ready и после Retry.
Ручной Forward+ gate остаётся открытым:
одиночка и пара в мире, followers, Tab/Q/E и сумка, расстановка/победа/Retry,
save/reopen и возврат лидера. Для безопасных captures tests
`test_party_followers.gd` и `test_combat_defeat_retry.gd` поддерживают
`-- --capture-active` (обычный Forward+, fixture saves, PNG в unique
`user://ember-tests`). Captures не заменяют ручную input-приёмку.

## Migration gates

### G1/G2 — content ownership

- `tools/test_content_migration_report.gd` и
  `test_content_migration_dashboard.gd` остаются read-only;
- `test_migration_workflow_layout.gd` проверяет bounded editor layout;
- `test_voxel_migration_queue.gd` проверяет bounded candidate selection;
- `test_voxel_migration_batch.gd` проверяет mutation/Undo/Redo;
- sandbox parity/batch: `test_voxel_sandbox_migration_parity.gd`,
  `test_voxel_sandbox_native_batch.gd`;
- `fan_town` parity/batch: `test_voxel_fan_town_ready_migration_parity.gd`,
  `test_voxel_fan_town_ready_native_batch.gd`.

Любой новый batch требует точного списка, strict read-only parity, visual review
реальных изменений, ограниченной записи и подтверждения, что frozen JOI source
остался byte-identical. Ready/stale/missing prefab не равны ownership.

### G3 — physical Surface

`test_world_surface_projection.gd`, `test_fan_town_surface_profile.gd` и
`test_fan_town_surface_projection.gd` подтверждают visual/collision/height/route
из одной Surface. Dense storage меняется только после нового измеренного профиля.

### G4/G5 — выход из JOI

Новые runtime-вызовы `EmberPack` запрещены. Существующие fallback удаляются
вертикально после native parity затронутого домена. Финальный gate запускает
проект с физически недоступным sibling `joi-conductor` и проверяет основные
карты, interaction/content catalogs, save/reopen и бой. Полные критерии — в
`docs/EMBER_JOI_EXIT_PLAN.md`.

## Полный checkpoint gate

Перед самостоятельным Git checkpoint:

1. `git diff --check`;
2. `python tools/test_vox_axes.py`;
3. каждый `tools/test_*.gd` отдельным headless-процессом;
4. повтор targeted suites после любого исправления, найденного полным прогоном;
5. обычный Forward+ на изменённых сценах;
6. ручная приёмка пользователя, если она входит в Task Contract;
7. обновлённые GDD/handoff/`EMBER_NOW.md` без журнала промежуточных версий.

Если обязательный gate недоступен, результат помечается `degraded`: указывается
точная причина, что уже доказано и какое ручное действие осталось. Ошибка в
неизменённой подсистеме не скрывается, но отделяется от regressions текущего
среза доказательством baseline.
