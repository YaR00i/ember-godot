# RFC: Landscape v2 — authoring земли Ember

Статус: **эксперимент отклонён ручной проверкой 26.09.2026**. Этот RFC хранит
результаты V2; схема временного GPU-preview с bake в dense Surface после мазка
не является выбранным направлением. Новый отдельный terrain pilot и его
открытый визуальный gate описаны в `EMBER_NOW.md`.
Обновлено: 2026-09-25. Изолированный proof-of-architecture находится в
`tools/prototypes/ember_landscape_v2_heightfield.gd`,
`ember_landscape_v2_gpu_preview.gd` и `qa_landscape_v2_architecture.gd`.
До утверждения и отдельного migration-контракта действуют владельцы и правила
`AGENTS.md`, `EMBER_TECHNICAL_HANDOFF.md` и
`EMBER_WORLD_AUTHORING_ARCHITECTURE.md`.

## Решение, которое проверяем

Большая обычная Landscape-кисть должна менять 2D height/control authoring,
а не сотни тысяч fine-вокселей и exact geometry на каждый input sample.
Каноническое игровое представление пока остаётся прежним fine Surface и прежним
renderer. Это **предложение о смене authoring owner** для будущих Landscape-карт,
а не скрытая оптимизация `StrokeJob.step()` и не немедленная миграция карт.

Существующее правило массового world-authoring — «после Apply миром владеет
Surface» — расходится с постоянным `LandscapeDocument`. Если RFC принят,
это правило в `EMBER_WORLD_AUTHORING_ARCHITECTURE.md` надо заменить только
для Landscape-земли: planner/stamp может быть частью канонического
LandscapeDocument, а объекты сцены по-прежнему остаются у `.tscn`.

## Почему это не просто перенос размера чанка

Официальные архитектурные ориентиры подтверждают разделение интерактивного
редактирования и дорогой синхронизации, но не диктуют Ember готовый формат:

- [Unity `SetHeightsDelayLOD`](https://docs.unity.com/en-us/engine/6000.3/script-reference/unityengine/terraindata/setheightsdelaylod)
  откладывает LOD/vegetation до `SyncHeightmap` после жеста.
- [Unreal Landscape Edit Layers](https://dev.epicgames.com/documentation/unreal-engine/landscape-edit-layers-in-unreal-engine)
  отделяют базовый heightmap и недеструктивные слои; компоненты определяют
  региональную структуру.
- [Terrain3D](https://terrain3d.readthedocs.io/en/stable/docs/system_architecture.html)
  создаёт clipmap-сетки один раз, а высоту вершин читает из GPU heightmap;
  [данные разделены на height/control/color regions](https://terrain3d.readthedocs.io/en/stable/api/class_terrain3ddata.html).
- [Voxel Tools](https://voxel-tools.readthedocs.io/en/latest/generators/)
  различает height и volume-подходы. Его недеструктивные modifiers ограничены
  smooth SDF/`VoxelLodTerrain`; переносить их напрямую на блочный Ember нельзя.

Это аргумент в пользу pipeline, не доказательство, что Ember должен перейти
на чужой renderer или plugin. В Godot `ImageTexture.update()` позволяет
[обновлять существующую текстуру](https://docs.godotengine.org/en/4.5/classes/class_imagetexture.html),
но стоимость загрузки регионов и фактический вид надо мерить в Ember.

## Предлагаемая схема владельцев

```text
scene .tscn ──────────────────────── map placement, objects, Save transaction
    │
    └── LandscapeDocument [editor canonical; только после миграции карты]
          ├── BaseHeight: 16 XZ samples / gameplay block
          ├── ControlMaps: material/biome/shore intent, masks
          ├── ordered deterministic EditLayers/Stamps
          ├── Water: ссылка/контракт с существующим water owner, не копия
          └── DetailOverrides: sparse add/remove/replace и Volume-патчи
                 │
                 ├── GPU preview: fixed region grids + region textures
                 └── dirty XZ + halo → deterministic bake
                         └── EmberVoxelModelResource [derived exact cache]
                                └── existing mesher / collision / runtime
```

До миграции конкретной карты её `EmberVoxelModelResource` остаётся canonical.
После миграции у Landscape-карты fine Resource становится **публикуемым
производным артефактом**; прямое редактирование его байтов запрещено либо
маршрутизируется в `DetailOverrides`. Нельзя оставить два независимо
редактируемых источника. Gameplay-loader первоначально продолжает читать
старый fine-формат; scene ownership карты не меняется.

### Минимальный формат, подлежащий отдельному утверждению

Предложение: версионированный editor-only `LandscapeDocument` Resource,
принадлежащий сцене, с размером, world origin, целочисленной высотой каждой
fine XZ-колонки (`0..height_voxels`), control-map bytes, стабильным seed,
упорядоченными слоями с идентификаторами/операциями и sparse Detail/Volume
патчами. Внешний `.tres` под транзакцией Save предпочтительнее большой
встроенной сцены, но конкретную schema и layout региона утвердить лишь после
замеров размера, load/save и миграции. Это не разрешение менять нынешний
`EmberVoxelModelResource`.

`Water` здесь — логический участник композиции, **не второй массив воды**.
Пока вода хранится в `surface_fill_*` существующего fine Resource; RFC не
решает молча, будет ли после миграции источник водных параметров отдельным
scene-owned water Resource или полями документа. До принятия этого решения
генератор обязан сохранять water bytes и использовать одну высоту воды для
берегового preview, bake, collision и gameplay. Морское дно принадлежит форме
земли; поверхность воды остаётся независимым слоем. Береговые правила не
должны выводиться только из цвета текстуры.

### Порядок композиции и Detail

1. `BaseHeight + ControlMaps` задают нормальную сплошную землю.
2. `EditLayers/Stamps` композиционно меняют height/control. Порядок и seed
   сериализованы; `Apply` не обязан разрушать исходные слои.
3. Детерминированный refinement превращает колонки в fine-воксели. Для
   проверки паритета `level` refinement **тождественный**. Террасы,
   квантованные склоны, material-specific breakup и seeded irregularity —
   отдельная версионированная policy, выключенная в exact parity test.
4. `DetailOverrides` применяются последними. `add`, `remove`, `replace`
   являются явными операциями; отсутствие записи означает наследование
   generated voxel. В первоначальном контракте override привязан к
   **абсолютной координате fine-вокселя** и выигрывает при сильном изменении
   base height. Так ручное удаление или добавление не пропадает после
   повторного bake соседнего региона. Для детали, которая должна двигаться
   вместе с поверхностью, нужен отдельный явно помеченный `surface-relative`
   режим с правилами смещения и конфликта — не неявная эвристика.

Heightfield не представляет пещеру, навес, туннель и многоуровневую землю.
Они принадлежат отдельному Fine/Volume пути; когда 3D-правок слишком много
для sparse overrides, карта или область может остаться legacy Surface,
а не превращаться в огромный псевдо-sparse слой. Объектные prefabs и
независимые voxel objects не входят в `LandscapeDocument`.

## Edit → preview → bake → physics

- Вход кисти с timestamp меняет только затронутые height/control samples,
  накапливает dirty rects и один Undo delta. Входные точки не пропускаются.
- Preview использует уже созданные сетки региона. Изменённые CPU samples
  попадают в региональную GPU height/control texture; `ArrayMesh` не
  перестраивается на событие. Межрегионные граничные samples обновляются
  с обеих сторон. Preview — отдельное временное представление, а не второй
  canonical renderer.
- После pause/pointer-up versioned bake читает dirty XZ + необходимый halo
  для slope/terrace/seeded detail. Запись ограничена dirty target. Результат
  зависит от координат, seed, policy version и данных, не от порядка задач.
- Fine Surface уведомляет существующую visual projection. Exact visual должен
  заменить preview без заметного скачка формы. Physics/height sampling/nav
  синхронизируются с **тем же** опубликованным fine-состоянием после
  интерактивной правки; нельзя на время bake выдать старую землю как новую.
- Новый жест до окончания предыдущего bake требует revision/cancellation
  контракта: старый derived job не имеет права перезаписать новый revision.
  Save должен дождаться/довести до конца exact bake или безопасно отказать.

Размеры authoring, preview, bake и render chunks **не обязаны совпадать**.
Прототип использует 64×64 fine XZ samples для preview/bake; это не выбранная
production-константа. Следующий gate сравнивает 32/64/128 на большой мокрой
карте: latency upload, число dirty regions, memory, швы, bake и Undo patch.
Render chunks 16/32 остаются нынешними, пока нет отдельного доказательства
для их изменения.

Undo хранит исходные/новые dirty patches для height/control/layers/overrides,
а не копии всего dense Surface, если измерение подтвердит выигрыш. Undo/Redo
выполняют обратную композицию и пересобирают только зависимые регионы; после
завершения их fine bytes, water, collision и preview должны совпадать с
соответствующим revision. Save/Reopen/Discard работают с одним revision
документа и валидированным derived output, а не с частично выпеченным миром.

## Кэш и запуск

`LandscapeDocument` — источник, fine Surface — проверяемый derived cache.
Cache key включает content hash канонических слоёв и overrides, размеры,
palette/refinement/schema versions и зависимости воды. При отсутствии,
повреждении или устаревании кэш пересоздаётся без потери авторских данных;
публикация/загрузка не принимает silently stale geometry. Startup-cache
и изменение `EmberEditorPreparation` **не входят** в этот RFC-прототип.

## Миграция старых Surface-карт

1. Read-only анализ каждой колонки старой карты: top height, непрерывность
   заполнения, material strata, вода, группы, authored holes и multi-level.
2. Representable solid terrain переносится в height/control; непредставимые
   ручные формы — в Detail/Volume или остаются legacy. Извлечение не меняет
   исходные `.tscn`/`.tres`.
3. Dry-run report: объём overrides, ожидаемые cache bytes, round-trip voxel
   diff по палитре/геометрии/воде, collision/route diff. Нулевой diff — gate
   для автоматической миграции; ненулевой требует явной ручной политики.
4. Миграция одной **копии** карты с Save/Reopen/Discard/Undo/Redo, затем
   Forward+ визуальная приёмка берега, террас и Volume. Старые карты остаются
   загружаемыми, а original Resource — recoverable checkpoint.
5. Лишь после принятия паритета карта переключает authoring owner; runtime
   продолжает читать published fine Surface. Rollback возвращает сцену на
   старую ссылку без реконструкции из нового документа.

## Proof-of-architecture: результаты и пределы

Тест: 14×15 blocks, 16 fine XZ samples/block, высота 32 fine voxels,
записанный `level`/«Площадка» из 70 input samples, радиус 25 fine cells.
Одинаковый исходный полный грунт, фиксированная целевая высота мазка.
Два вида проверки: timestamp replay для задержки и отдельное построение
эталона прежней функцией `level_segment_changes` для точных байтов.
Не прямая ручная работа в основной 3D-вкладке. Godot 4.7.2 Forward+,
Windows/NVIDIA RTX 5070, `Engine.max_fps=0`, VSync mode 1; один прогрев и
три одинаковых измеряемых повтора. Цифры ниже повторно сняты после добавления
palette/terrace preview 24.09.2026. Внутри gesture нет fine writes, physics
или detailed logging. Полный JSON: `user://qa_landscape_v2_architecture.json`.

| Показатель | Forward+ после прогрева |
| --- | ---: |
| Input delay median / p95 | 2.2–2.5 / 4.4–5.0 ms |
| Height brush CPU за 70 входов | 81.0–86.7 ms |
| GPU preview texture update CPU за жест | 11.0–11.7 ms |
| Preview mesh creations до/после жеста | 16 / 16 |
| Texture updates / dirty 64×64 regions | 174 / 8 |
| Frame interval median / p95 / max | ~5.0 / 5.2–5.3 / 5.5–20.0 ms |
| Pointer-up → bake start | 3.8–4.0 ms |
| Dirty fine bake CPU / wall | 65.7–67.2 / 68.8–70.8 ms |
| Dirty columns / actually changed voxels | 23,040 / 192,736 |
| Pointer-up → fine mesh-ready proxy | 868 ms (один измеренный pass) |

Последняя цифра включает уведомление существующей Surface projection и её
завершение (`is_projection_complete()`), не является измерением пикселя на
экране или физики. Input delay тоже синтетический: время от timestamp
запланированной точки до начала обработчика, **не** latency реальной мыши
в редакторе. 5-мс плато кадров не объявляется FPS игры. В этом запуске не
сравнивались большой авторский мир, мокрый берег, Undo/Redo и editor 3D UI.

Итоговые bytes fine Surface **полностью совпали** с текущей `level`-кистью на
этом solid-column fixture: SHA-256 обеих сторон
`bd227df4444e308c40f6b58513a46b9871eca6a87b2d520bc598358350137276`.
Dirty-region bake совпал с full bake. Add/remove/replace overrides пережили
повторную сборку соседних регионов и сильное изменение base height. Это
проверка prototype composition, не проверка существующего Save/Undo.

`user://qa_landscape_v2_architecture_comparison.png` показывает идентичный
top-height силуэт. `user://qa_landscape_v2_gpu_preview.png` показывает
реально отрисованный GPU-preview: форма читается и полосы высоты отмечены,
но геометрия между samples и боковые грани пока схематичны. В изолированном
кадре нет воды, береговой пены или layered material breakup. Перед production
нужны visual contract и проверка совпадения preview с exact на настоящей
карте; текущий preview не должен подменять финальный вид игры.

## Временный ручной gate в основной 3D-вкладке

Это **эксперимент для оценки ощущения**, не принятие RFC. Только отдельная
`scenes/landscape_v2_experimental.tscn` с независимой копией
`content/world_surfaces/landscape_v2_experimental_surface.tres` (включая берег
и воду) показывает переключатель `Landscape V2 Experimental · копия карты` в
обычной панели «Редактировать мир». Все другие сцены остаются Legacy.
Экспериментальные высоты живут только в памяти во время мазка; после отпускания
dirty fine voxels попадают в обычный черновик Surface и штатный Undo/Redo.
Runtime, schema, save-контракт, оригинальная карта и физический Surface owner
не меняются. Не используйте эту копию как авторскую карту.

1. Если сцена была открыта до исправления владельца Surface, закрыть **только**
   её вкладку без сохранения и открыть файл заново (остальные незавершённые
   сцены не трогать). Открыть экспериментальную сцену в **основной 3D-вкладке**
   Godot, выбрать `Земля карты` и включить `Редактировать мир`. Кнопку
   `Создать землю` здесь нажимать не нужно: копия уже содержит берег и воду.
   Дождаться полной штатной
   проекции, затем включить экспериментальный флажок и дождаться сообщения
   `Landscape V2 готов`.
2. В категории `Форма` выбрать `Площадка`. Зафиксировать радиус, глубину,
   палитру и участок; включить `Начать запись мазков`. Провести длинный мазок
   на суше, у берега и увидеть переход preview → exact после отпускания.
   Дождаться сообщения `Точная Surface готова`, остановить запись. Trace
   сохраняется в `user://ember_world_edit_trace_*.json`; в нём есть режим,
   этапы height/texture/bake и timestamp смены preview на exact.
3. Сделать Ctrl+Z/Ctrl+Y, проверить форму и берег. Перед сравнением выполнить
   Ctrl+Z ещё раз, чтобы вернуться к тому же исходному состоянию. Затем
   выключить флажок (Legacy), **не меняя настройки кисти**, и повторить
   сравнимую траекторию с новой
   записью. Отдельно повторить с `Поднять` или `Опустить`.
4. Ответить субъективно: следует ли земля за курсором, виден ли скачок при
   preview → exact, похожа ли форма, плавен ли viewport, целы ли Undo/Redo
   и берег. Цифры trace — вспомогательные; ручная приёмка ещё не выполнена.

Для честного сравнения старый Surface не обновляется во время V2-жеста,
поэтому превью временно скрывает только непрозрачную землю; вода остаётся
отдельной. Временное представление показывает верхнюю форму и палитру с
полосами высоты, но **не** точные voxel-боковины, cave/overhang, все strata
или окончательную пену. Это возможный visual pop, который нужно явно оценить.
Пока эксперимент охватывает только `Площадка`, `Поднять`, `Опустить` и только
карту-копию. В этой временной ветке bake ограничен кадрами, но не является
многопоточным. Ничего не сохранять в production-карты; для чистого повторения
закрыть копию без сохранения и открыть снова.

### Ручная проверка и trace основной 3D-вкладки, 25.09.2026

Серёжа подтвердил: форма V2 во время длинного мазка следует за кистью быстро.
После первого ручного теста preview следующего мазка показывал старый цвет
земли при новой высоте. Регрессионный тест двух последовательных мазков
в `tools/test_landscape_v2_editor_experiment.gd` воспроизвёл это падением:
top palette точной Surface и control/texture preview различались. Локальное
исправление в `ember_landscape_v2_experiment.gd` синхронизирует цвет затронутых
колонок после bake; тот же тест для `Поднять → Опустить → новый мазок` теперь
проходит. Пользователь подтвердил, что цвет стал обновляться. Это принятие
узкого исправления, **не** принятие полного визуального вида V2.

Последняя реальная запись `user://ember_world_edit_trace_335700608.json`:
основная 3D-вкладка Godot 4.7.2 Forward+, инструмент `Опустить`, 398 input
samples за 3.14 с, 138 907 изменённых fine voxels. Brush queue peak 1,
max age необработанного input 1.4 мс. Во время жеста V2 отзывчив;
показатель frame interval за **всю запись**, включая ожидание exact:
median 7.4 мс, p95 22.7 мс, max 630.7 мс. Это один жест, не парный A/B
с Legacy и не обещание скорости на других картах.

После pointer-up: начало bake через 9.6 мс, завершение bake через 393.6 мс,
commit через 961.9 мс, смена preview → exact через 3894.7 мс. Чистые
call-site интервалы `experimental_dirty_bake` 68.4 мс,
`experimental_post_bake_preview_sync` 42.6 мс,
`notify_and_queue_projection` 506.8 мс. Это **не** слагаемые общего wall time:
остальное включает ожидание кадров и очередь. Visual pending peak 126;
127 visual rebuilds затронули 127 разных чанков, все помечены как native,
без зафиксированного fallback и без повторных rebuild того же чанка в этом
жесте. Сумма наблюдаемых adapter calls 2217.8 мс; первый visual rebuild
закончился примерно через 1.01 с после release, последний — через 3.89 с.
`postdraw` — лишь proxy отправки кадра на рендер, не измерение пикселя.

Следовательно, **цикл дублирующих rebuild здесь не обнаружен**. Также не
доказано, что размер чанка или native mesher — единственная причина ожидания:
между bake, notification, очередью projection и сменой preview есть отдельные
интервалы. Пользовательская проблема открыта: после каждого мазка нужно
ждать примерно 3–4 с до следующего, а временный preview всей карты остаётся
слишком бледным и не показывает точный Ember-вид. Увеличивать brush budget
снова не следует: вход уже не является заметной очередью.

### Контракт последовательных мазков — ограниченный эксперимент

**Цель:** позволить автору выполнять последовательные крупные мазки в основной
3D-вкладке без многосекундного вынужденного ожидания после каждого, сохранив
полную траекторию, точный fine voxel result, Undo/Redo и отзывчивый viewport.
Не объявлять целью просто уменьшение одного числа trace: ручное ощущение и
точный вид земли — обязательные gates.

1. В начале нового чата read-only сверить текущий checkout и формально
   согласовать Task Contract. На тестовой копии воспроизвести несколько
   последовательных мазков, отдельно сухо и у берега. Зафиксировать момент,
   когда UI разрешает следующий мазок, и почему: `busy` gate, bake,
   notification, visual/physics projection или preview swap.
2. Разделить минимум три проверяемых направления, не выбирая решение заранее:
   (a) сузить/ускорить действительно необходимый exact work и его публикацию;
   (b) продолжать редактирование transient Landscape, пока предыдущая exact
   projection догоняет, с явными revisions, защитой от устаревшего bake и
   контрактом Undo/Redo/Save/physics; (c) сделать preview достаточно верным
   текущей земле, чтобы ожидание exact не скрывало авторский результат.
   Сопоставить стоимость, сложность и риск каждого варианта. Большие чанки,
   многопоточность и отсрочка всей точности — гипотезы, не готовые решения.
3. Выбрать один ограниченный эксперимент только после измерения; сравнить
   те же операции до/после. Мерить доступность следующего input, backlog,
   frame median/p95/max отдельно во время жеста и после release, времена
   bake/notify/projection, число уникальных/повторных rebuilds, возраст
   необновлённого изменения, preview → exact и полное восстановление данных
   через Undo/Redo. Если узкий вариант не помогает ощущению, остановиться и
   вернуться к выбору архитектуры, не наслаивая случайные оптимизации.

Границы: экспериментальная сцена и editor-path; Legacy 16 остаётся default.
Не менять production owner, schema/save/runtime/native adapter, отдельную
ветку новой воды, материалы, startup cache или world batching без отдельного
согласования. Текущие локальные изменения сохранить. Commit/push — только
по явной команде.

Локальный эксперимент после согласования этого контракта разрешает начинать
следующий мазок после bake/Undo commit, пока visual/physics projection предыдущего
ещё догоняет. Точная Surface остаётся единственным fine-источником; временный
preview продолжает скрывать старую землю до полного завершения **последней**
проекции. Save, Undo/Redo и переключение Legacy/V2 пока ждут exact. Отмена
текущего мазка возвращает его height/control preview к предыдущему принятому
мазку и оставляет ожидающую проекцию под preview. Это проба editor-path только
на карте-копии, не утверждение постоянного Landscape owner.

Адресный `--overlap-only` gate на временной Surface прошёл: второй мазок до
завершения первой проекции, отмена, цвет следующего preview, две команды
Undo/Redo и неизменная вода. `test_world_editor.gd` и `test_world_edit_trace.gd`
прошли. Полный `test_landscape_v2_editor_experiment.gd` отдельно сообщает о
расхождении voxel bytes экспериментальной копии с исходным Холстом мира;
авторские файлы для исправления fixture не менялись. Ни один из этих тестов не
доказывает, что в живой основной 3D-вкладке серия мазков теперь ощущается
быстрее или что бледный preview визуально принят.

После ручных кадров от Серёжи (два preview и один exact) локально исправлена
ещё одна часть временного отображения. Цветовая texture читалась без
`source_color`: изолированный GPU-кадр давал `(167,146,136)` вместо палитры
`(112,84,71)`; после исправления — точно `(112,84,71)`. Искусственное
затемнение по высоте удалено. Теперь editor-preview рисует только участки
сетки exact chunks, которых коснулся мазок; нетронутая земля остаётся в штатной
Surface. При
завершении последней проекции маска preview очищается, включая общий край
GPU-регионов. Адресный тест сначала воспроизводил закрытие нетронутой земли,
затем прошёл с сохранением двух мазков, отмены, цвета, истории и воды.

Предел этого исправления: внутри изменённых chunks временная сетка всё ещё
соединяет высоты склонами и не воспроизводит все воксельные боковины,
toon-освещение и линии точной Surface. Изолированные парные кадры на временной
сцене это показывают; живой вид и плавность на карте-копии требуют повторной
ручной оценки. Полный визуальный паритет означал бы отдельное решение о
представлении preview, а не ещё один множитель цвета.

Ручной gate: на сцене-копии сделать два-три больших мазка подряд, включая
сухой участок и берег, не дожидаясь `Точная Surface готова`; проверить, что
каждый новый мазок появляется сразу, нет скачка формы/цвета и вода не исчезает.
Сравнить новые кадры preview с точной картой: вне мазка должен оставаться
обычный Ember-вид, а цвет затронутого участка должен быть читаемым.
Во время ожидания проверить отмену **текущего** мазка, затем после точного
перехода Undo/Redo, Save/Reopen/Discard и F6 физическую поверхность. Запись
trace должна отдельно показать доступность следующего ввода, очередь и время
до последнего exact; прежний одиночный trace не является парным A/B.

### Что изолированный prototype **не доказал**

- Не измерил основную 3D-вкладку Godot editor и живое ощущение кисти; позднее
  это частично измерено и вручную оценено в разделе выше.
- Не доказал ускорение относительно старого editor path в честном A/B; старый
  путь по этой же записи и в этом же viewport отдельно не измерен.
- Не проверил water/shore/palette strata, overhang/caves, большой filled map,
  сетевые/render-текстуры других размеров, Undo/Redo/Save/Reopen/Discard.
- Не реализовал постоянные layers/stamps, cache, migration или physics sync.
- Не доказал отсутствие visual pop: GPU-preview схематичен, а exact-ready
  proxy занимает ~0.85 s после отпускания на этой копии.

## Поэтапный production-план — только после отдельного согласования

| Gate | Что менять | Как принять и откатить |
| --- | --- | --- |
| 0. RFC/visual contract | Утвердить ownership, water, Detail semantics, preview fidelity, репрезентативные карты | Никаких runtime/schema изменений; RFC можно отклонить без миграции |
| 1. Paired editor A/B | Пассивная диагностика той же 70-input записи в реальной 3D-вкладке; 32/64/128 регионов, мокрый и сухой участки | Доказать эффект и visual/CPU budget; при провале сохранить legacy путь |
| 2. Canonical document | Новый versioned Resource + validation + scene association + единая Save transaction | Новая карта только по opt-in; старые сцены и Surface остаются рабочими |
| 3. Landscape edit & preview | Команды нынешнего editor UI, GPU-preview с Ember-палитрой и точными контурными правилами, dirty tracking, patch Undo | Preview/commit, frames, UI, Undo/Redo, Discard; feature flag возвращает старую кисть |
| 4. Exact bake & physics | Детерминированная композиция, halo, versioned async/bounded jobs, существующий mesher/collision | Byte parity, seam/shore/Volume tests, player/AI route; старый Surface checkpoint |
| 5. Migration pilot | Read-only audit → копия одной Surface-карты → round-trip/save/reopen/Forward+ | Принятие автором; исходные `.tscn`/`.tres` восстановимы без нового документа |
| 6. Wider rollout | Только выбранные карты; validated derived cache/startup — отдельный контракт | Переключение по карте, не глобальный необратимый cutover |

На каждом gate заранее фиксировать scope и не смешивать со startup thumbnails,
world-object batching, погодой, материалами или отдельным volume mesher.
Текущий performance checkpoint `85badfb` остаётся reference. Production
commit/push этим RFC не разрешены; смена основного чата выполняется отдельно
по `.agents/skills/ember-coordinator-handoff/SKILL.md`.

## Решения пользователя перед production

1. Нужен ли автору **постоянный редактируемый** Landscape stack, или после
   явного Apply ему достаточно нынешней ручной Surface? Рекомендация RFC —
   постоянный stack только для обычной Landscape-земли, не для всех объектов.
2. Детали на поверхности должны следовать за поднятым грунтом или оставаться
   в мировых координатах? Рекомендация — оба режима, но явный выбор типа;
   absolute — базовый безопасный контракт для ручных add/remove/replace.
3. Какой preview визуально приемлем во время жеста: схематичная форма или
   почти exact Ember-ступени/берег? Рекомендация — не переключать редактор,
   пока на репрезентативной карте разница не исчезает без заметного pop.

После этих решений и живого A/B можно составить точный пофайловый Task Contract
для нового основного чата. Пока RFC — обсуждаемая архитектура, не команда
переписать существующий editor.
