# Ember Godot

## V2.62.1 · позиционная связка парных техник

`Грозовая связка` Миры и Сены проходит только по мокрым врагам одной проводящей
цепи. `Паровой пробой` протагониста и Орика требует Frozen, снимает заморозку и
отбрасывает цель. У каждой техники заранее назначен партнёр, который должен
находиться в настраиваемом радиусе; текущий кандидат — 3 клетки с учётом
перепада высоты. Оба должны быть живы, обладать нужным MP и после применения
оба сдвигаются дальше в очереди.

При наведении панель показывает общую цену (`8+6 MP`), партнёра и точную
дистанцию. Поле подсвечивает радиус, партнёр получает цветной контур, указатель
и подпись `в радиусе / вне радиуса`. Проверка использует позицию после
запланированного перемещения. Скрытые попадание, крит и урон не раскрываются;
save v2 и battlefield schema не менялись.

## V2.61 · опыт и повышение уровня после боя

Авторская встреча теперь хранит награду XP. После победы все четыре постоянных
героя получают её поровну, включая павших; повышение уровня увеличивает
производные характеристики, но сохраняет недостающие HP/MP. Павший герой после
победы возвращается ровно с 1 HP. Окно результата заранее показывает XP и
повышения уровня, а прежний guard `Continue` применяет их только один раз.

Временная кривая вертикального среза — 30 XP до второго уровня и ещё +15 XP к
каждому следующему порогу. Это настраиваемое число для проверки темпа, а не новая
save-схема: save v2 уже хранит level/XP/current HP/MP и переоткрывает результат.

## V2.60.2 · колесо мыши не меняет масштаб боя

Combat CameraRig больше не реагирует на колесо мыши. Авторский
`orthographic_size`, допустимые пределы и шаг масштаба остаются в Inspector, а
общий `OrbitCamera` сохраняет колесо для редакторских viewport, где оно нужно.

## V2.60.1 · адаптивный список боевых команд

Основное кольцо быстрых действий сохранено, но `Умения`, `Магия` и `Предметы`
теперь открываются в прокручиваемой панели рядом с ним. Панель выбирает левую
или правую сторону по экранной позиции героя и текущей камере, не дёргаясь при
небольшом движении около центра. Строки показывают иконку, цену/остаток и причину
недоступности; после выбора команды панель освобождает поле для цели.

## V2.60 · боевые предметы из общей сумки

В Combat Lab появился раздел `Предметы`: лечебная трава, чай для HP+MP и редкая
искра воскрешения используют тот же общий инвентарь, что исследование и save v2.
Предмет тратится только после выбора допустимой цели, занимает полное действие и
не может примениться второй раз через устаревший commit. Победа возвращает
фактический остаток в мир, а Retry восстанавливает предбоевой запас.

Item Resources получили только необходимые authored-поля эффекта и дальности;
второго resolver, каталога или владельца сохранения не появилось. Тестовые числа
остаются настраиваемыми до балансировки главы.

## V2.56.1 · безопасная проверка готовых voxel-prefab

`ensure_saved()` больше не перезаписывает уже актуальные `.tscn/.res` при
обычной загрузке или regression-тесте. Готовый prefab сначала проходит прежнюю
полную validation и переиспользуется из cache; реальная пересборка выполняется
только для stale/missing данных или явной команды редактора.

Это устраняет внешний hot-reload живого mesh в открытом Forward+ viewport —
источник повторяющегося `Parameter "mesh" is null`. Voxel Resource/schema,
геометрия, collision и сцены не менялись.

## V2.56 · stop-line основного редактора

Основной Surface/Graph/Inspector/migration editor закрыт перед отдельной
Q&A-сессией по игровому дизайн-документу. Последний read-only gate проверил все
25 stale prefab, используемых `fan_town`: 25/25 меняют видимые voxel-грани,
18 также меняют collision, а три emissive-модели затрагивают свет или тени. Поэтому
они не выданы за безопасную техническую пересборку и не перенесены вслепую.

Профиль воспроизводится через
`tools/profile_voxel_fan_town_stale_prefabs.gd`, сохраняет подробный JSON только
в `user://` и сверяет SHA-256 источников/Resources/prefab до и после. Этот остаток
теперь считается production art review после дизайн-документа, а не причиной
продолжать бесконечную общую полировку редактора.

## V2.55 · первая ограниченная fan_town voxel-партия

Семь используемых `fan_town` моделей с уже актуальными prefab перенесены из
legacy owner в `EmberVoxelModelResource`: бочка, старый ящик, дверь, подкова,
вывеска таверны, каменный фонарь и окно. Явный список партии прошёл 7/7 strict
parity по metadata, вершинам, нормалям, цветам, индексам и collision source;
dry-run не изменил ни одного файла.

Migration dashboard показывает отдельный фильтр `fan_town: готовые prefab` и
разрешает запись только после повторного dry-run точного списка. Перенос
использует прежний общий importer/store и одну Undo/Redo-транзакцию; новой schema
или второго voxel owner нет. Итоговый baseline: 15 native / 162 legacy voxel
Resources, а prefab остаются 63 ready / 25 stale / 88 missing.

## V2.54.1 · water shader после native chunk rebuild

Surface-вода снова использует прозрачный water/foam shader и в Canvas, и в
world projection. Причина была не в материале: native terrain mesh имеет
локальные координаты чанка, а добавленный water overlay — координаты всей
Surface; их нельзя безопасно смешивать в одном `ArrayMesh` с одним transform.

Сухие чанки сохраняют быстрый Voxel Tools exact path. Чанк с реальной water-mask
или level-fill определяется общим leaf-mesher и собирается прежним точным
Surface path, поэтому вода, пена и world-locked рисунок остаются на своей клетке
без изменения Resource schema или save format. Регрессия проверяет как первый
Canvas chunk, так и воду в чанке со смещением от начала карты.

## V2.54 · физическая Surface-карта fan_town

`fan_town` теперь владеет одной канонической dense Surface 32×32 блока как
источником terrain visual, collision, высоты и маршрута. Её 512×48×512 grid
занимает 12.0 MiB voxel bytes и около 16.0 MiB в текстовом `.tres`; measured
load — примерно 1.0–1.3 с, save — 0.14–0.17 с. Эти числа оставляют schema v4
без sparse/chunk persistence.

Точный native mesher теперь общий для Canvas и world runtime с прежним
GDScript-fallback: sample visual chunk снизился примерно с 19–21 до 5–7 мс.
Transient heightfield считается через WorkerThreadPool, после чего 64 greedy
collision-чанка 4×4 блока строятся примерно за 0.22 с, худший runtime chunk —
около 8 мс. Legacy `Terrain/Mesh` и `Terrain/Collision` остаются активным
fallback до атомарной готовности замены. Forward+ проверен на реальной сцене;
schema, save format и gameplay Resource не менялись.

## V2.48 · lifecycle Surface Canvas и запомненный вид

Уход с вкладки Surface Canvas теперь завершает активный жест и показывает один
Save / Discard / Cancel guard, если canonical Resource изменён. Cancel возвращает
в Canvas, не теряя draft; ошибка сохранения не закрывает его. Закрытие Godot и
общий Save используют штатные `_get_unsaved_status()` / `_save_external_data()`
`EditorPlugin`, поэтому отдельного владельца dirty-state нет.

Camera target/angles/zoom, рабочая region, height slice, grid/region overlays и
режим `дно + вода / только дно` запоминаются отдельно для последних 32 Surface в
`editor_layout.cfg`. Это editor-only состояние: оно проходит validation/clamp,
не участвует в Undo и никогда не сериализуется в gameplay `.tres`. Явно
переданная область из world/battle viewport имеет приоритет над remembered region.

## V2.47 · профиль большой Surface

Dense Surface оставлена канонической: реальная sandbox-карта 384×32×384 занимает
9.84 MiB рабочих dense-каналов, загружается примерно за 0.80 с и сохраняется за
0.13 с. Эти числа не обосновывают migration schema. Воспроизводимый профиль
находится в `tools/test_surface_large_profile.gd` и пишет результаты только в
`user://`.

Измеренные hot paths оптимизированы без нового owner: sparse-aware heightfield
сократил синхронное открытие Canvas примерно с 0.79 до 0.12 с; editor-only
скрытие/изоляция групп повторно использует неизменившийся heightfield (0.71 →
0.019 с). Сухой terrain использует Voxel Tools exact path: один chunk сократился
примерно с 25.5 до 5.9–6.6 мс, а frame-budgeted очередь собирает 1–2 быстрых
chunks за 6–11 мс. Water-bearing chunks сохраняют точный Surface mesher, потому
что water/foam требуют координат всей Surface. Transient selection, group schema
и save format не менялись.

## V2.46 · рампы оттенков

В блоке палитры появилась кнопка **Рамп оттенков…**. Выбранный цвет можно
развернуть в связную последовательность из 3, 5 или 7 образцов: ровный тон,
тёплый свет с холодной тенью либо мягкий пастельный вариант. Диалог показывает
результат до применения.

Рамп не является вторым форматом палитры: после подтверждения это обычные
соседние образцы существующего `palette`. Исходный цвет остаётся в центре, а
ссылки вокселей и оттенков воды безопасно перенумеровываются, поэтому модель
визуально не меняется. Вся операция — один Ctrl+Z; save/reopen использует прежний
`.tres`, schema не менялась.

## V2.45 · цвета и видимость групп

У сохранённой voxel-группы теперь есть собственный цвет подписи. Он используется
для подсветки выбранной группы, входит в Undo/Redo и сохраняется в том же `.tres`,
но не меняет палитру или цвет модели. Старые группы без поля цвета получают
стабильный цвет при первой следующей операции; schema Resource поднята до v4.

**Показывать в просмотре** временно скрывает одну или несколько групп. Это только
состояние текущего Surface Canvas: исходные воксели, вода, collision и runtime не
меняются. Изоляция по-прежнему показывает только одну группу и скрывает воду;
включение изоляции автоматически возвращает выбранную группу в видимый слой.
Удаление/смена Resource очищает устаревшие фильтры.

## V2.44 · компактные семейства кистей и отпечаток формы

Левая рейка сокращена с 12 отдельных строк до 8 инструментов без удаления возможностей. `Объём` переключает `добавить / убрать`; `Рельеф` отдельно задаёт `вверх / вниз` и `сплошная / оболочка`. Предел, скорость, размер и крупный шаг остаются общими контекстными настройками. Внутри по-прежнему используются прежние проверенные операции и один Undo-контракт — новый UI не создаёт второй sculpt backend.

Переключатель маски теперь зависит от типа инструмента. `Красить` и `Материал / вода` меняют точные выбранные воксели и сохраняют выделение после мазка. `Объём`, `Рельеф`, `Площадка`, `Сгладить` и `Склон` используют вертикальный XZ-отпечаток: кисть может создать или убрать форму только в колонках, где есть выделение. После успешного формообразующего мазка исходная voxel-маска очищается как устаревшая; Esc восстанавливает данные и сохраняет её. `Заливка уровня` остаётся отдельной операцией замкнутого слоя и voxel-маску не использует.

`Площадка`, `Сгладить` и `Склон A → B` не объединены с рельефом: у них разные жесты и смысл — фиксированная высота первого касания, усреднение соседей и две опорные точки. Вода также не смешана с level fill: локальный материал принадлежит существующим вокселям, а заливка — отдельному поверхностному слою.

## V2.43 · обычные кисти внутри выделения

Создайте маску в блоке **ВЫДЕЛЕНИЕ ВОКСЕЛЕЙ**, выберите `Красить` или `Материал / вода` и включите **Кисть только внутри выделения**. Курсор и размер кисти не ограничены рамкой маски, но запись происходит только в пересечении отпечатка с выбранными занятыми вокселями. Защищённые именованные группы дополнительно исключаются тем же общим фильтром.

После успешного мазка выделение остаётся, поэтому по нему можно последовательно нанести несколько цветов или локальных материалов. Esc отменяет незавершённый мазок и сохраняет маску; Ctrl+Z/Redo и постороннее изменение Resource очищают её как потенциально устаревшую. Маска остаётся временным состоянием редактора и не сохраняется в `.tres`.

В v2.43 формообразующие инструменты ещё выключали этот режим. Начиная с v2.44 они используют явно подписанный вертикальный XZ-отпечаток выделения.

## V2.42 · именованные группы вокселей

После выделения нажмите **`+ Из выделения`** в блоке `ГРУППЫ ВОКСЕЛЕЙ`: имя, стабильный ID, отсортированные координаты и защита сохраняются прямо в том же `.tres`. Группу можно переименовать без смены ID, заменить её состав текущим выделением, снова выделить, удалить, защитить или изолировать. Каждая операция — один Ctrl+Z; Ctrl+S и повторное открытие сохраняют группы. Пустая группа и повреждённые/повторяющиеся индексы не проходят проверку.

**Защитить воксели от кистей** блокирует изменение формы, цвета и локального материала как обычными кистями, так и `Окрасить выделенное`; незаблокированные воксели того же мазка продолжают работать. Вода — отдельный слой и этой блокировкой не управляется. Изменение образца палитры остаётся намеренно глобальным и визуально меняет все ссылки на образец.

**Изолировать в просмотре** временно показывает только воксели группы и скрывает воду. Это производный вид редактора: исходный Resource не копируется обратно и не становится dirty. Выключение, смена группы/ресурса и скрытие Canvas возвращают полный вид. Runtime игнорирует authoring-группы; геометрия, collision и игровой формат не получают второго владельца.

## V2.41 · выделение вокселей

В правой панели Canvas под палитрой — **ВЫДЕЛЕНИЕ ВОКСЕЛЕЙ**. `Выбирать воксели · V` включает режим клика: один воксель, связные похожего цвета (6 соседей в объёме, включая стенки) либо все похожего цвета. Допуск 0% означает одинаковый RGB, даже если это разные образцы палитры. Shift добавляет, Ctrl вычитает; те же операции доступны списком. Воксели подсвечиваются, счётчик включает внутренние воксели.

Выберите образец палитры → `Окрасить выделенное`: меняются только выбранные занятые воксели, не форма, образцы палитры или вода. Один Ctrl+Z отменяет покраску, Ctrl+S сохраняет `.tres`. Начиная с v2.43 маску также могут использовать обычные кисти `Красить` и `Материал / вода`; формообразующие кисти её не используют. Рабочая область и высотный срез ограничивают поиск/применение; их смена, другая модель, постороннее изменение или Undo сбрасывают устаревшую маску. Сама маска временная, не сохраняется и не добавляет действий в Undo.

Поиск и подготовка подсветки распределены по кадрам. Esc отменяет поиск с сохранением предыдущего результата, повторный Esc выходит из режима. `Снять выделение` очищает маску. В первом срезе лимит 32 768 вокселей: превышение отклоняется целиком, уменьшите рабочую область или допуск. Далее — именованные группы и операции по маске; сохранённых групп пока нет.

## V2.40 · палитра Surface Canvas

Справа в Canvas — **ПАЛИТРА** с цветными образцами. Клик выбирает цвет кисти, `+ Цвет` добавляет образец, `Изменить` открывает штатный выбор RGB/HSV/HEX. Изменение образца перекрашивает всю модель, включая скрытые слои и связанную воду; для локальной покраски используйте кисть `Красить`. До `Применить` данные не меняются. `Заменить…` переназначает все ссылки на другой образец и удаляет старый, не удаляя воксели. Один Ctrl+Z отменяет всю операцию, Ctrl+S сохраняет обычный `.tres`.

`Пипетка · I` → клик по вокселю берёт его исходный цвет без влияния света. I работает при фокусе холста; Esc отменяет. В срезе пипетка видит открытый нижний слой. Нулевой индекс зарезервирован, доступно до 255 цветов. Оттенки заливки и индексы скрытых вокселей безопасно перенумеровываются при замене.

Это первый этап цвета, не редактор групп: далее общее выделение вокселей (добавить/вычесть, связность/похожие цвета), затем именованные группы с изоляцией и защитой. Остальной backlog — `docs/EMBER_EDITOR_UX_AUDIT.md`.

## V2.39 · защищённый срез по высоте

В правой панели **Surface Canvas → Срез по высоте** можно включить отсечение верха и задать число видимых нижних art voxels: `1` показывает только Y=0. Верх не удаляется и не попадает под курсор/кисть. Обычный и Voxel Tools preview строят настоящие закрывающие грани на плоскости среза; picking и защита записи используют один editor-only bounds contract без копии всей voxel-модели. При смене высоты завершается активный жест и заменяется очередь пересборки чанков.

В срезе доступны наращивание/вырезание объёма, покраска и **локальная** кисть материала. Вода скрыта, smart material flood, заливка уровня и колонковые кисти рельефа/сглаживания/склона отключены до выхода из среза. Материальный water-effect проверяется в полном виде. X/Z-область редактирования продолжает ограничивать кисти. Срез не записывается в `.tres`, не меняет runtime/collision и не является режимом одного изолированного слоя или произвольного диапазона Y.

Проверено `test_surface_height_slice.gd`: нижняя граница, roof picking, закрытые грани обоих mesh backends, защита скрытого верха и соседнего участка при всех четырёх кистях, Undo/Redo, полный save/reopen и смена среза во время жеста. Проверен disposable Forward+ viewport; авторские карты не изменялись.

## V2.52 · проверенная sandbox-партия в Godot

Шесть voxel-моделей из `agent_sandbox` сначала проходят dry-run без записи:
будущий Resource сравнивается с legacy по grid/occupancy, metadata и полным
буферам mesh — vertices, normals, colors и indices. Только результат 6/6
разблокирует ограниченную batch-команду; вся партия является одной операцией
Ctrl+Z/Redo и при ошибке откатывается целиком.

Партия уже перенесена: voxel baseline теперь 8 native / 169 legacy. Prefab этих
шести моделей актуальны, сцены продолжают ссылаться на те же ID, а dashboard
показывает завершённое состояние и блокирует повторный перенос. Проверки:
`test_voxel_sandbox_migration_parity.gd`, `test_voxel_migration_batch.gd`,
`test_voxel_sandbox_native_batch.gd` и связанные inventory/dashboard gates.

## V2.51 · фильтруемый dashboard миграции

После `Измерить G1/G2` кнопка `Подробности…` открывает отдельный read-only экран
со всеми 263 записями. Их можно отфильтровать по разделу и состоянию, найти по
ID, тексту ошибки или сцене и прочитать детали owner/prefab/reference. Быстрый
фильтр `Sandbox-партия` показывает шесть legacy voxel-моделей, уже используемых
в проверочных sandbox-сценах.

V2.51 ещё не переносил контент: dashboard только обосновывал первый маленький
набор. V2.52 добавляет guarded dry-run → batch; refresh и фильтры остаются
read-only, JSON сохраняется только в `user://`, schema не меняется. Проверки:
`test_content_migration_dashboard.gd`, `test_content_migration_report.gd` и
`test_migration_workflow_layout.gd`.

## V2.50 · измеримый остаток G1/G2

В `Ember Migration` появился общий read-only отчёт по voxel, цепочкам,
диалогам, предметам, магазинам и VN-арту. Кнопка `Измерить G1/G2` ничего не
переносит: она считает владельцев, validation, ссылки сцен и состояние prefab;
JSON по отдельной команде сохраняется только в `user://`.

Первый baseline: voxel 2 native / 175 legacy, action 13/4, dialogue 2/10,
item 5/19, shop 1/1, VN 2/29. Среди 176 voxel props 56 prefab актуальны,
32 устарели и 88 отсутствуют; один legacy VN-фон потерял файл. Отчёт строится
примерно за 1.3–1.4 с, поэтому запускается только вручную. Targeted test сверяет
полноту шести доменов, JSON и SHA-256 неизменность проекта/JOI. V2.51 добавляет
фильтруемый dashboard; следующим остаётся dry-run/parity выбранной sandbox-партии,
не bulk convert.

## V2.49 · стабильная иерархия Ember Graph

Верхняя строка `Ember Graph` теперь всегда отвечает только за тип документа,
Resource, обновление и основной Save. Во второй строке остаются действия
текущего режима/выбранной ноды; раскладка, дублирование, буфер, dialogue-группы
и полный диагностический Quest-граф собраны в `Ещё…`. Quest drill-down читается
как `Задание › текущая цель`, а не как набор равноправных кнопок.

При 1280×720 шапка больше не переносится на несколько рядов, GraphEdit и правый
редактор остаются видимыми. Положение разделителя сохраняется в editor layout и
не записывается в gameplay Resource. `test_graph_workspace.gd` проверяет narrow
и 1600×900 layout, primary Save и split round-trip; `test_graph_lifecycle.gd`
проходит в Forward+ без утечек. Следующий этап — G1/G2 migration parity и
нативная библиотека контента.

## V2.38.1 · стабильная пересборка Graph

Исправлены найденные общим тестом `move_child: Child is not a child of this node` и утечки при просмотре целей задания. Native GraphEdit откладывает перестановку GraphFrame: отслужившая рамка теперь отвязывает участников, скрывается, освобождает имя и остаётся дочерней до обработки deferred-команд; в выборе/сохранении старые рамки не участвуют. При фокусе на отдельной цели временная корневая карточка задания, не добавленная в дерево, явно освобождается. Документы, история Undo/Redo и игровой runtime не менялись.

`test_graph_workspace.gd` проходит без прежних native errors и RID/ObjectDB warnings. Новый `test_graph_lifecycle.gd` проверяет три открытия/закрытия workspace, серии пересборок групп в одном кадре, уничтожение старых рамок после кадра и отсутствие роста orphan nodes при повторном открытии целей. Следующий Surface-срез по плану — работа со срезами высоты; полный UX-проход Graph ещё не закрыт.

## V2.38 · вода и безопасный Surface Canvas

В `Заливка уровня` появился `Вода · оттенок авто / цвет N`: оттенок берётся из текущей палитры и сохраняется в существующем `surface_fill_palette`, отдельно от воксельного дна. Повторная заливка заменяет связную семью воды целиком, включая понижение уровня; один Ctrl+Z отменяет изменение.

Контакт персонажа выбирает подходящий водоём своего viewport по положению и высоте, а не первую Surface в дереве. Кольцо обрезается по водной маске, дорожки не выходят на берег и исчезают при удалении воды; выход/прыжок/возвращение не соединяются ложным следом. Производный кэш высот сбрасывается при изменении Resource. Контактная маска 12×12 переиспользуется и обновляется с ограничением частоты при небольшом движении; это не новая симуляция или источник collision/Wet.

Canvas: Ctrl+S сохраняет, `*` отмечает правки, переход на другую поверхность предлагает сохранить / отбросить / остаться. Неудачный Save оставляет draft открытым; повторное открытие другой области той же карты не сбрасывает признак изменений. `Вид → Сетка блоков` (G над viewport), `Рамка рабочей области` и `Слои → только дно` позволяют смотреть рисунок без разметки и воды, не меняя Resource. Смена инструмента и уход со вкладки завершают активный жест одной Undo-операцией.

Проверки: `test_water_contact_boundaries.gd`, `test_surface_canvas_workflow.gd`, `test_world_surface_projection.gd`, `test_voxel_surface_sculpt.gd`; Canvas также отрисован в Forward+ на 1280×720 и 1600×900. Авторские карты не перезаписываются этими проверками. Срезы по высоте, большие sparse-карты, Graph UX и полный JOI exit остаются в плане, а не объявляются завершёнными.

**Godot 4.7 Forward+ — единственный активный runtime и authoring-проект Ember.**
Authored maps are `.tscn` + `PackedScene` prefabs; voxel sources are
`content/voxel_models/*.tres`. JOI/Three play приостановлен, а старый
`../joi-conductor/content/ember` остаётся только read-only очередью одноразового
импорта до закрытия exit-gates.

Локальные источники правды: [продуктовый план](docs/EMBER_PRODUCT_PLAN.md),
[технический handoff](docs/EMBER_TECHNICAL_HANDOFF.md),
[план выхода из JOI](docs/EMBER_JOI_EXIT_PLAN.md) и
[план приёмки](MIGRATION_TEST_PLAN.md).

## Open

Target editor: **Godot 4.7.2**, binaries in `tools/godot/`. **`edit.bat`** / **`run.bat`**.

1. Default play scene: `scenes/fan_town.tscn`. WASD walks relative to the current camera yaw, F interacts, RMB rotates yaw. Its four authored doors enter `fan_town_inn/mage/smith/house:start` and each exit returns to the matching exterior region. Mechanics sandbox: `scenes/agent_sandbox.tscn` (same play script, `map_id = agent_sandbox`). Its cabin door enters `agent_sandbox_interior:start`; the interior exit trigger returns to `agent_sandbox:cabin_enter`.
2. First time (or after pack changes): open the map scene, **Проект → Инструменты → Ember: Reimport map from pack**, or select **Map** and **Reimport from Ember pack**. Reimport wipes transforms. Day-to-day: move a prop, Ctrl+S.
3. After import, Scene dock has `Look` / `Terrain` / `Props` / `Regions`. Each prop is a `PackedScene` instance (`res://prefabs/voxels/<modelId>.tscn`) with Omni as a child of the lamp.

## Migration test workflow

The bottom-panel **Ember Migration** tab containing **EMBER · проверка миграции** is the normal test loop. It uses a layout identity distinct from the retired right-side `Ember` dock and stays separate from the native Inspector:

1. Choose light profile 0 / 2 / 4 / 8 / 12 / 16. `8` is production; `12` and `16` are stress profiles. In Play, `F3` shows active/candidate shadows and frame/render metrics; `F4` cycles profiles.
2. Select a node under `Map/Props`; the dock shows separate `.vox` geometry and `.json` metadata paths, instance count, and whether the generated prefab matches their SHA-256 signature.
3. Open **Библиотека voxel-префабов…** even without a map. It shows `Godot / ожидают импорт / всего`; a legacy card has **Перенести в Godot**, while a migrated card has **Открыть Godot Resource**. Migration creates `content/voxel_models/<id>.tres`, rebuilds preview/prefab and supports Ctrl+Z/Redo without changing `.vox/.json`. The selected prop repeats these actions in the bottom panel; legacy source buttons are diagnostics only. Mesh surfaces update in place, and rebuild continues to validate Mesh plus expected Collision / Omni / ShadowBody without changing map transforms, placement ids or generated UIDs.
4. To add a different model use **Библиотека voxel-префабов…**. It shows native Godot models plus an explicitly marked legacy import queue as searchable tiles and renders native `.tscn` previews. The selected model is added to `Map/Props` one tile along +X from the current 3D selection (or at `player_start`), gets a unique `placement_id`, and participates in Undo/Redo. A missing prefab is built only for that selected model.
5. For a map-authored copy use **Дублировать безопасно · +X**. It creates a unique `placement_id`, keeps scene-owned children such as `Interact`, offsets the copy by one tile, and participates in editor Undo/Redo. Move/rotate normally, then Ctrl+S.
6. Use full map reimport only when pack terrain/regions changed; it requires confirmation and overwrites manual prop positions and nested scene edits. Props/transforms/Interact are owned by the Godot `.tscn`; terrain/regions remain one-way JOI import until native Godot tools exist.

Voxel-prop selection uses a compact editor gizmo around its `Mesh`; the child Omni range remains fully active but is excluded from the visible selection frame.

Selecting an `EmberVoxelProp`, its generated `Omni`, or a standalone `EmberInteract` adds one **EMBER OBJECT** block to the native Godot Inspector. Compact collapsible cards separate `Ассет`, `Сцена`, and `Расчёт`; Renderer/Collider start collapsed while relevant Light/Interact state stays open. Doors show one `map → region` destination block with their trigger. `+ Добавить взаимодействие` and `Изменить / Удалить` author the existing scene-owned `EmberInteract` through Undo/Redo. `+ Триггер с цепочкой` additionally builds a canonical action list with all seven ordered `talk/give_item/set_flag/wait/open_shop/change_map/run_script` cards and binds it to the same Interact; shop resumes the queue after Esc, while map change is explicitly terminal. Новые цепочки сохраняются в `res://content/action_scripts/<id>.tres`; старые `content/ember/scripts/<id>.json` мигрируются по одной из Ember Graph. В шаге `Диалог` кнопка `Создать / редактировать диалог` открывает карточки реплик и простого сходящегося выбора; варианты могут записать один typed флаг. Новые диалоги записываются как `res://content/dialogues/<id>.tres`; старые `content/ember/scenes/<id>.json` остаются рабочим read-only fallback до явного `Перенести в .tres`. Оба каталога native-first используются editor и runtime. An unsaved chain form has `Отменить`; an existing action list has `Удалить цепочку`, which deletes only its canonical document + binding and preserves the Interact, shop and other fields in one Undo/Redo action. Light and Collider remain read-only until their ownership/schema is designed.

Для больших сценариев верхняя main-screen вкладка **Ember Graph** использует native `GraphEdit/GraphNode`: выбор `Цепочки действий | Диалоги`, бесконечная сетка, zoom, minimap и auto-arrange. Клик по ноде оставляет справа только её карточку; `Показать все` возвращает полный список. Ответная нода простой dialogue-ветки фокусирует родительскую карточку выбора. Ноды `talk/run_script` имеют переход к связанному диалогу/сценарию в той же вкладке. У `choice` каждый ответ показан отдельным подписанным выходом: новый провод меняет именно его canonical `options[].next`, отключённый/ведущий в никуда выход и недостижимая нода блокируют `Сохранить граф`. Dialogue toolbar создаёт `Реплика | Выбор | Изменить флаг | Конец` в центре текущего viewport, удаляет выбранные ноды с явной диагностикой очищенных входов и назначает выбранную ноду через прежний `startStepId`. Структурный черновик поддерживает локальные ↶/↷; справа явно показан текущий owner (`Legacy JSON` или `Godot Resource`) и доступна одноразовая миграция. Zoom/pan и ручная раскладка больше не сбрасываются при rebuild/save: view хранится отдельно для каждого открытого ресурса, а dialogue-позиции записываются только в существующий `editorLayout` (не gameplay). Дополнительные поля сложных VN-нод при смене связей сохраняются; их property-карточки всё ещё read-only до отдельного VN-properties среза.

В режиме `Цепочки действий` структура теперь редактируется прямо на canvas: тип + `+ Нода`, Delete/кнопка `Удалить`, а новый провод переставляет целевую ноду сразу после исходной. Поскольку canonical action-list остаётся связным массивом, отдельное отсоединение запрещено. `↶/↷` отменяют структурные изменения локального черновика; поля справа синхронизируются перед каждой graph-операцией. Только `Сохранить цепочку` пишет текущий canonical owner через общий Editor Undo/Redo. Справа видны `Legacy JSON | Godot Resource`, источник и кнопка явной миграции. Структурные кнопки в правом card-list скрыты, чтобы у порядка был один owner.

Для действия без видимого prop выберите место или ближайший prop и в нижней вкладке **Ember Migration** нажмите `+ Зона-триггер с цепочкой`. Создаётся scene-owned `root/AuthoredTriggers/trigger_N`, который не находится внутри generated `Map` и поэтому переживает полный reimport. В Inspector настраиваются видимый cyan Box gizmo, точные X/Высота/Z, тип/ссылки и та же canonical цепочка. Игрок измеряет дистанцию до границы объёма, а не до его центра: большая зона работает по всей площади. Создание, размер, цепочка и удаление зоны поддерживают Undo/Redo; после настройки сцену нужно сохранить Ctrl+S.

В форме `Изменить → ПРАВИЛА ЗАПУСКА` можно указать typed bool-флаг из существующего Ember save. `Ожидать Да` требует строго `true`; выключенный вариант принимает `Нет` и ещё отсутствующий флаг. `Иначе` выбирает запасную существующую цепочку; без неё F-подсказка скрывается до выполнения условия. `Только 1 раз` автоматически предлагает устойчивый флаг выполнения и отключает Interact лишь после успешного завершения основной ветки. Запасная ветка или закрытый до конца диалог одноразовый запуск не расходуют. Правила принадлежат scene-owned `EmberInteract`; action JSON и save schema не расширяются.

Там же `Активация` переключает `Клавиша F` и `При входе`. Автозона не создаёт скрытую F-подсказку: её существующий `Area3D` слушает только physics-layer игрока и передаёт событие тому же `EmberPlayer → EmberInteractionUi`. Повторного запуска, пока игрок стоит внутри, нет; для следующего пересечения нужно выйти и войти. Conditions, fallback и one-shot применяются до запуска тем же route evaluator.

`Изменить флаг` авторит прежний typed save contract без сырого JSON: имя — устойчивый ключ вроде `met_blacksmith`; `Да/Нет` выбирается отдельным `Да (true) / Нет (false)`, текст и число получают свои guided-поля. Подсказка прямо в карточке напоминает, что запись флага сама по себе невидима — эффект появляется, когда тот же ключ читает quest/dialogue/object logic.

The acceptance protocol and decision gates are in [MIGRATION_TEST_PLAN.md](MIGRATION_TEST_PLAN.md).
Object Inspector architecture and implementation waves are fixed in [docs/EMBER_OBJECT_INSPECTOR_DESIGN.md](docs/EMBER_OBJECT_INSPECTOR_DESIGN.md).
Migration preserves Ember behavior and art direction, not Three.js implementation details. Renderer/editor/physics gaps are first evaluated against Godot-native nodes, resources, shaders, import hooks and maintained plugins; only then is one replacement contract selected. Roof/cutaway research and explicit non-goals are recorded in the migration plan.

`Ember Graph` v1.29 редактирует основные поля dialogue прямо внутри нод: реплику, имя, speaker/emotion, вопрос и подписи ответов, splash, typed flag и числовую награду. VN-срез дополнительно показывает `defaultBgArtId` сцены, `bgArtId`, `portraitSide` и сворачиваемую постановку первого `actors[0]` (id/speaker/emotion/x/y/scale/flip); расширенные actor-поля и остальные персонажи сохраняются lossless. `Заставка` доступна в toolbar и searchable-палитре. Правая колонка остаётся read-only обзором, чтобы у одного JSON-поля не было двух одновременно активных редакторов. Для крупных веток выделите ноды через Shift+клик, введите имя и нажмите `Группа`: штатный `GraphFrame` двигает их вместе, а `editorGroups` сохраняет только authoring-layout и не меняет runtime-порядок диалога. Новую ноду можно бросить на раскрытый frame; `Свернуть` заменяет участников компактной proxy-нодой: внутренние связи скрыты, но цепи снаружи входят в левый boundary-port и выходят из правого. `Развернуть` восстанавливает ноды и все провода из неизменённого draft. `Убрать из группы` извлекает выбранные ноды, а выбор самого frame/proxy меняет действие на `Удалить группу`; ноды при этом не удаляются. `Ctrl+D`/`Дубликат` копирует выбранные action-шаги или dialogue-ветку: dialogue получает новые ID, внутренние edges переназначаются на копии, общий внешний выход сохраняется, а вход в копию нужно подключить явно. ПКМ по пустому холсту открывает searchable-палитру; ввод фильтрует типы, Enter или двойной клик создаёт ноду в выбранной точке. Если отпустить протянутый провод в пустоте, открывается та же палитра и созданная нода автоматически подключается; для action-list новый шаг вставляется в canonical порядок сразу после источника или перед целью. `Ctrl+C/X/V` и меню `Буфер` переносят выделенный блок между ресурсами одного типа в текущей editor-сессии. Dialogue paste всегда выдаёт новые ID, сохраняет внутренние связи и очищает внешнюю ссылку, если такой цели нет в графе назначения; action paste сохраняет порядок и вставляет блок после текущего выделения. `Ctrl+Z`, `Ctrl+Shift+Z` и `Ctrl+Y` вызывают те же локальные ↶/↷, кроме момента редактирования текста внутри поля. Ошибка теперь находится на самой action/dialogue-ноде: красные badge и сообщение показывают точный broken port/step, а `К первой ошибке` выбирает и центрирует проблему, включая участника свёрнутой группы. Переключение типа, ресурса, Reload или link-navigation при dirty draft требует явного `Отбросить и перейти`; `Остаться` сохраняет черновик и восстанавливает selector. Верхняя панель переносит элементы на новую строку, полный статус остаётся над canvas. Все операции записываются в JSON только по `Сохранить граф`.

`Ember Graph` v1.30 добавляет `▶ Превью сцены`. Окно читает текущий unsaved draft, поэтому текст, фон, portrait side и `actors[0]` обновляются live без Save. Клик по ноде фокусирует соответствующий кадр; `Далее`, варианты ответа, `Назад` и `С начала` проходят canonical `next/options[].next`. Один renderer показывает и полноценные cutscene/VN (фон + stage actors), и обычные `use: talk/shop_intro` как текстовые сцены. Арты и портреты разрешаются непосредственно из прежних `arts/registry.json` и `portraits/<speaker>/registry.json`; `↻ Арты` перечитывает внешние файлы. Если registry указывает на отсутствующий файл, preview показывает точный warning вместо подмены ассета. Это preview Ember scene JSON; 3D `.tscn` по-прежнему проверяются штатными Godot viewport/F6.

`Ember Graph` v1.31 заменяет ручной ввод `defaultBgArtId/bgArtId/artId/speaker/portraitKey` на visual picker. Фоны и splash показывают только CG/background entries, их подпись, ID, миниатюру и `✓/⚠` наличия файла. Персонаж выбирается из существующих portrait registries с миниатюрой, после чего список эмоций перестраивается под него и показывает реальные expression preview. Dialogue speaker/emotion синхронизируются с главным staged actor; в choice меняется только actor. Неизвестный старый ID остаётся выбранным как warning и не стирается самопроизвольно. `Обновить` перечитывает оба каталога.

`Ember Graph` v1.32 не кладёт динамические `ImageTexture` внутрь `OptionButton/PopupMenu`: списки содержат подпись, ID и `✓/⚠`, а выбранный фон, персонаж и emotion показываются отдельным `TextureRect` рядом с полем. Исправлен источник native `0xc0000005` при открытии dialogue/live preview: demo SVG содержал управляющие байты и битый UTF-8, от которых падал Godot 4.7.2 SVG loader. Placeholder теперь валидный UTF-8; picker и preview используют один resolver с decoded-image cache, а preview создаёт только display-sized текстуры.

`Ember Graph` v1.33 начинает перенос каталога фонов в Godot-native authoring. Длинные подписи теперь обрезаются внутри фиксированной ширины и больше не растягивают правую колонку. `+ Фон` открывает системный выбор PNG/JPG/WebP/SVG, копирует изображение в `res://assets/vn_backgrounds/` и создаёт отдельный `EmberVnBackground` `.tres` в `res://content/vn_backgrounds/`; строка `Фоны` и кнопка `Папка` показывают это прямо в редакторе. Native `.tres` имеет приоритет по ID. Прежний JOI `arts/registry.json` остаётся read-only fallback для ещё не перенесённых ассетов и этим интерфейсом не переписывается. Dialogue graph пока сохраняет существующий JSON-контракт: его Resource-миграция будет отдельным вертикальным срезом с runtime/save/Undo тестами.

`Ember Graph` v1.34 делает фон наследуемым свойством сцены. Поле `Фон сцены` задаётся один раз; новые dialogue/choice-ноды без `bgArtId` автоматически используют его, а их picker показывает `↳ Фон сцены` и эффективную миниатюру. `Сделать общим для всей сцены` одной локальной Undo-операцией удаляет только старые per-node overrides, не трогая splash, связи и постановку. Пустой legacy `bgArtId: ""` теперь также корректно получает fallback в общем `EmberVnSceneState`, поэтому editor preview и runtime больше не расходятся.

`Ember Graph` v1.35 фиксирует композицию VN preview: фон находится в нижнем слое, authored `z` сортирует персонажей только внутри ограниченного actor-layer, а диалоговая панель всегда выше портретов. Следующая часть asset migration переносит новые эмоции персонажей в Godot-native `EmberVnPortrait`: кнопка `+ Арт` у поля эмоции копирует PNG/JPG/WebP/SVG в `res://assets/vn_portraits/<speaker>/` и создаёт `.tres` в `res://content/vn_portraits/`. Общий picker/preview resolver объединяет native Resources с прежними `portraits/<speaker>/registry.json`; native `speaker/key` имеет приоритет, legacy JSON остаётся read-only fallback.

`Ember Graph` v1.36 переносит owner документов диалога без массового опасного convert. Новый `EmberDialogueResource` хранит прежний lossless graph document в `res://content/dialogues/<id>.tres`; общий `EmberDialogueCatalog` используется editor, picker и runtime. Для legacy-сцены справа показан источник и кнопка `Перенести в .tres`: после неё native Resource имеет приоритет, старый JSON остаётся неизменным backup/fallback и больше не получает сохранения. Одна Editor Undo возвращает точное legacy-only состояние, Redo снова включает native owner. Новые диалоги сразу создаются native.

`Ember Graph` v1.37 применяет тот же контракт к цепочкам действий. `EmberActionResource` lossless хранит прежние `id/nameRu/steps` в `res://content/action_scripts/<id>.tres`, а общий `EmberActionCatalog` используется picker, validation и `EmberActionScript` executor. Legacy action JSON остаётся fallback/backup до кнопки `Перенести в .tres`; после неё сохранение пишет только Resource. Создание, удаление документа, binding к Interact и миграция участвуют в одном snapshot-aware Undo/Redo, который восстанавливает оба owner и исходный текст legacy JSON без переформатирования. Новые цепочки сразу native.

`Ember Graph` v1.38 переносит authoring магазинов. В шаге `Открыть магазин` кнопка `Создать / редактировать магазин` показывает название, ассортимент, цены покупки/продажи и конечный либо бесконечный запас. Старые записи общего JOI `shops/catalog.json` открываются read-only и переносятся по одной кнопкой `Перенести в .tres`; после этого `EmberShopResource` в `res://content/shops/<id>.tres` становится общим native-first owner для picker, Inspector, runtime shop overlay и `EmberEconomy`. Сохранение и миграция проходят через Editor Undo/Redo, а legacy-каталог остаётся неизменным backup. Новые магазины сразу создаются native.

`Ember Graph` v1.40 продолжает тот же authoring-поток до предмета. В строке ассортимента кнопка `Предмет…` открывает вложенную форму имени, типа, слота, редкости, stack, режима, icon ID, atk/def/heal, sell price/запрета продажи, тегов и описания. `EmberItemResource` в `res://content/items/<id>.tres` имеет приоритет для магазина, inventory, equipment, consumable и economy; прежняя item Dictionary schema не менялась. Legacy items read-only до явной per-item миграции, а общий `items/catalog.json` с пиксельной icon-библиотекой остаётся неизменным fallback. Save/migrate используют Editor Undo/Redo, новые предметы сразу native. Кнопка `Библиотека…` открывает общий tiled `ItemList` с настоящими pixel previews, русскими именами, stable IDs и поиском; такой же item catalog доступен из строки магазина, где выбранный предмет теперь виден иконкой. Архитектура расширения на VN art, portraits, voxel props и maps закреплена в `docs/EMBER_VISUAL_LIBRARY_DESIGN.md`.

`Ember Graph` v1.41 применяет эту библиотеку к уже существующим VN-каталогам. Кнопка `▦` рядом с фоном сцены, override/splash art, персонажем и эмоцией открывает searchable tiles с настоящими thumbnails; compact OptionButton и отдельный selected preview остаются на месте. Фоны фильтруют portrait-kind art, персонаж показывает representative expression и количество эмоций, а expression library перестраивается под speaker. Пустой background tile сохраняет прежнюю семантику `наследовать defaultBgArtId`; неизвестный legacy ID остаётся warning tile. `+ Фон` и `+ Арт` по-прежнему импортируют Godot Resources через существующий `EmberVnAssets`. Native-first portrait resolver явно продолжает поиск в legacy registry, если native override для конкретной эмоции отсутствует; поэтому ещё не перенесённые PNG/SVG видны и в tiles, и в live preview.

`Ember Migration` v1.42 расширил общий tile picker на voxel-префабы. Изначально `EmberVoxelCatalog` читал 176 JOI definitions; с v1.98 тот же picker native-first и показывает legacy только как очередь импорта. Готовые `.tscn` получают thumbnail, отсутствующие помечены `◇`. Выбор добавляет ровно один scene-owned `EmberVoxelProp` в `Map/Props` через Undo/Redo и новый `placement_id`; prefab строится только если выбранная сцена отсутствует или устарела. `test_voxel_visual_library.gd` закрепляет catalog projection и save/reopen.

`Ember Migration` v1.43 устраняет захват редактора длинной bottom-panel формой. В корне остаются только постоянная шапка с `Закрыть`, однострочный статус и вертикальный `ScrollContainer`; операции сгруппированы в сворачиваемые `Свет`, `Voxel`, `Триггеры` и `Обслуживание`. Поэтому высоту можно снова менять штатной границей Godot, а строка соседних нижних вкладок остаётся доступной. `test_migration_workflow_layout.gd` закрепляет layout contract.

`Ember Migration` v1.44 заменяет пустой stock scene-preview реальными voxel thumbnails. Один editor-only `SubViewport` последовательно инстанцирует готовые PackedScenes, отключает их authored lights, кадрирует `Mesh` ортографической камерой и возвращает 128×128 texture в общий tile picker. Cache существует только в памяти и инвалидируется новым mtime prefab; PNG/registry/schema не создаются. Windows Forward+ smoke `test_voxel_preview_renderer.gd` проверяет, что кадр содержит пиксели модели, а не один фон.

`Ember Migration` v1.45 заполняет preview и для плиток `◇`. Если generated `.tscn` отсутствует, `EmberVoxelPrefab.make_preview_instance()` вызывает тот же canonical `.vox/.json` mesher/material/tree contract, но не устанавливает `.res` и не сохраняет prefab. Поэтому все валидные модели видны, статус отсутствующего prefab остаётся честным, а массовой сборки ради UI нет. Memory cache для таких плиток использует source mtimes; Vulkan-тест одновременно проверяет готовый prefab и source-only модель и доказывает отсутствие записи `.tscn`.

`Ember Migration` v1.46 добавляет визуальный выбор назначения двери и шага `Сменить карту`. `EmberMapVisuals` строит 96×96 CPU-схему из той же `EmberTileMesher.surface_grid()`, которая определяет runtime terrain: реальные цвета тайлов, маркеры voxel-пропов и золотая рамка выбранного region. Кнопка `▦` находится рядом с прежними compact map/region полями; выбранное значение по-прежнему сериализуется только как `targetMapId/targetRegionId`. Preview не запускает `.tscn`, не пишет screenshot/cache на диск и не вводит второй map registry.

`Ember Migration` v1.47 начинает продуктовую quest-вертикаль. Quest-marker получил кнопку `Задание`: inline editor создаёт `EmberQuestResource` в `res://content/quests/<id>.tres`, где находятся только название, описание, видимость, отдельный `statusFlagId` и цели с их flag IDs. Сам `<id>` идентифицирует Resource и не записывается в save; общий статус (`active`, `done` либо `true`) и каждая цель читают отдельные typed flags `EmberExploreState`. Второго quest manager/save schema нет. Одна Undo/Redo operation сохраняет Resource и привязывает marker к status flag. В Play клавиша `Q` открывает журнал, который проецирует available/active/done и выполненные цели.

`Ember Migration` v1.48 исправляет неоднозначность первого demo-контракта: `sandbox_notice_quest` использует `sandbox_notice_status` для общего состояния и прежний `sandbox_notice_read` только для цели. Quest editor подписывает внутренний ID, текст и save-флаг каждой цели и объясняет необязательные цели. Journal показывает точные значения относящихся к заданию ключей из текущего слота; debug-кнопка сбрасывает только эти ключи, поэтому старый save можно проверить без удаления всего прогресса. Status lookup кэшируется и не сканирует Resource-каталог каждый кадр.

`Ember Migration` v1.49 соединяет quest authoring с уже существующим `set_flag`. Кнопка `▦` у имени флага в action-chain Inspector, простом dialogue choice и inline-ноде Ember Graph открывает один read-only список: `◆` означает общий status flag задания, `□` — обязательную цель, `◇` — необязательную. Карточка показывает понятное название/текст, поиск находит также технический ID, а выбор подставляет только canonical string key. Нового quest-action, сериализации или runtime executor нет; ручной ввод произвольного world flag остаётся доступен.

`Ember Migration` v1.50 делает задания отдельным видом документа в `Ember Graph`: выберите сверху `Задания`, затем нужный Resource по понятному названию и ID. Центральная нода редактирует identity, status flag, название и описание, связанные ноды — цели, их journal text, completion flag и optional. `+ Задание` создаёт локальный новый черновик, `+ Цель` добавляет цель, Delete удаляет выбранные цели, а ↶/↷ отменяют изменения до единственного `Сохранить задание`. Линии означают принадлежность целей заданию, а не порядок исполнения; ветвление по-прежнему живёт в dialogue/action graph. Сохранение использует тот же Godot Resource и Editor Undo/Redo owner, без новой quest schema.

`Ember Migration` v1.51 связывает задания с миром через уже существующие action chains. В Inspector цепочки и в action/dialogue режимах `Ember Graph` кнопка `Событие задания` открывает понятные варианты `Начать`, `Выполнить цель`, `Завершить`; выбор сохраняется обычным `set_flag`, поэтому новый quest executor не появился. Для объекта используется его `EmberInteract`, для места — scene-owned `Area3D` из `AuthoredTriggers`; активация выбирается как `Клавиша F` или `При входе`. Launch condition теперь сравнивает typed значение, поэтому зону можно честно ограничить условием `sandbox_notice_status == active`, сохранив его через Ctrl+S/reopen и общий Undo/Redo.

`Ember Migration` v1.52 добавляет последовательность целей. В quest-режиме золотые линии по-прежнему означают принадлежность заданию, а синий провод `Цель A → Цель B` записывает `requiresObjectiveIds`: B заблокирована, пока A не выполнена. Несколько входящих проводов означают `выполнить все`, поэтому доступны линейные цепочки, параллельные этапы и их схождение; цикл редактор отвергает. Журнал различает текущие `◆`, заблокированные `◇` и выполненные `✓` цели. Событие остаётся прежним `set_flag`, но общий authored-write gate распознаёт completion-флаг задания, не записывает его раньше зависимостей и показывает понятную notice-карточку. Старые цели без зависимостей и прямой debug/save restore остаются совместимыми.

World-marker slice после v1.52 заменяет системные `Label3D` glyph оригинальными SVG в штатном `Sprite3D`: янтарный `!` означает доступное задание, голубой компас — текущую цель, мятная галочка — завершение/сдачу. Силуэты различаются без цвета, прежний mesh-anchor и LOD 140/190/300 сохранены, а 64 px asset при `pixel_size = 0.00175` не возвращает гигантские значки. Locked цели остаются только в журнале. Контракт и будущая policy описаны в `docs/EMBER_WORLD_MARKERS.md`.

`Ember Migration` v1.53 разделяет у world marker две прежние роли. `quest_id` ссылается на `EmberQuestResource`, поэтому status flag и SVG всегда вычисляются из состояния выбранного задания; `script_id` снова означает только action chain объекта. В Inspector у метки есть отдельные `Цепочка действий`, `Задание` и shortcut `Цель / событие`: он открывает отфильтрованные события выбранного задания, а у ещё не связанной метки выбранная цель атомарно сохраняет и цепочку, и `quest_id`. Старые сцены, где status flag лежал в `script_id`, читаются через legacy fallback и мигрируются при первом сохранении без изменения save v1.

`Ember Migration` v1.54 делает маркер событийным. Runtime сопоставляет прежние `set_flag` шаги action chain с status/objective flags выбранного Quest Resource и без нового поля выводит роль объекта: выдача, конкретная цель или сдача. Поэтому будущая цель скрыта до принятия и prerequisites, выполненное событие исчезает, а последняя обязательная цель получает мятную галочку. Стандартные `quest_available/active/done` считаются состояниями и меняются динамически; только действительно custom icon остаётся фиксированным. Inspector показывает вычисленные `Роль маркера` и `На свежем прохождении`, а не заставляет автора угадывать технический ключ.

`Ember Migration` v1.55 упрощает модификатор `Взаимодействие`, не меняя его scene/runtime schema. Сверху форма показывает человеческий preview `РЕЗУЛЬТАТ В ИГРЕ`; типы, задания, магазины и цепочки отображаются как понятное название + стабильный ID. Основные поля зависят от типа, а условия, fallback, one-shot и редкие quest override спрятаны под `Дополнительно` и автоматически раскрываются, если в существующем объекте уже есть такие данные. Кнопки карточки переносятся по ширине Inspector и разделены по назначению: `Настройки`, `Действия`, `Описание задания`, `+ Событие задания`. Сундук больше нельзя случайно создать пустым Interact — его loot по-прежнему принадлежит импортированной карте.

`Ember Graph` v1.56 начинает объединённый `Quest Flow` без объединения data owners. В графе задания фиолетовые read-only ноды показывают реальные action chains и dialogue branches, которые меняют status либо objective flag; провод ведёт к корню задания или конкретной цели. Кнопка на ноде открывает исходный документ для редактирования. `EmberQuestUsageIndex` только читает native-first каталоги, ничего не сериализует, а вычисленные позиции не попадают в `editorLayout`. Поэтому задание остаётся описанием/зависимостями, диалог — ветвлением, action chain — исполнением, но автор видит их как один flow.

`Ember Graph` v1.57 исправляет геометрию этого flow. Длинный технический ключ больше не заставляет wrapped `Label` вычислять сотни пустых строк: source-ноды ограничены компактной карточкой, строки получают ellipsis и полный tooltip. Правая property-колонка имеет стабильную базовую ширину, а длинное имя выбранной ноды обрезается внутри неё вместо изменения `HSplitContainer`. Ширина по-прежнему регулируется штатным разделителем.

`Ember Graph` v1.58 возвращает source-нодам обычное перемещение мышью. Их координаты живут в session view-state и переживают локальный rebuild вкладки, но фильтр `_apply_cached_quest_layout()` по-прежнему записывает в Quest Resource только `quest_root` и `objective:*`; вычисленные backlinks не становятся authored данными.

`Ember Graph` v1.59 добавляет первый world-authoring слой Quest Flow. Зелёные ноды проецируют `EmberInteract` из текущей открытой сцены и соединяются с фиолетовыми action/dialogue событиями, которые объект действительно запускает. Учитываются native `script_id` и legacy quest-marker route через `resolved_action_script_id()`. `Выбрать в сцене` переключает редактор в 3D и выбирает voxel owner либо самостоятельную Area3D. NodePath используется только для editor-навигации; Quest/Action/scene schema не меняются.

`Ember Graph` v1.60 добавляет guided bind из Quest Flow. Выберите voxel-prop либо самостоятельный Interact в дереве сцены: корень задания предлагает привязать старт/завершение, а objective-нода — выполнение цели. Shortcut компилирует выбранное событие через `EmberQuestStore.action_for_event()` в прежний `set_flag`, создаёт либо дополняет canonical action chain и связывает её с Interact одной Editor Undo/Redo operation. Объект без Interact получает scene-owned `quest_marker` с вычисляемой иконкой; существующий тип взаимодействия не меняется. Повторный bind того же события идемпотентен, а перед терминальным `change_map` шаг вставляется до перехода. Зелёные backlinks обновляются после Save, Ctrl+Z и Redo; editor NodePath по-прежнему не сериализуется.

`Ember Graph` v1.61 разрешает bind ещё не сохранённой цели. Graph передаёт валидированный текущий Quest draft, а общий `action_for_event_in_document()` компилирует event без обращения к устаревшей disk-версии. Одна Editor Undo/Redo operation теперь охватывает Quest Resource, Action Resource и scene-owned Interact; после успешного bind локальная история графа сбрасывается к только что сохранённому состоянию. Поэтому новая `objective_3` сразу привязывается к выбранному объекту, а Ctrl+Z удаляет/восстанавливает весь вертикальный срез атомарно.

`Ember Graph` v1.62 добавляет ComfyUI-подобный drag-to-bind без второго writer. Выбранный несвязанный voxel/Interact появляется зелёной нодой `Готов к привязке`; её выход можно протянуть к отдельным зелёным входам `начать`, `выполнить цель` или `завершить`. Уже связанная зелёная scene-нода поддерживает тот же жест. Connection request только выбирает editor event token и передаёт его прежнему v1.61 `bind_quest_event()`: после commit временная прямая связь заменяется честной проекцией объект → canonical action/dialogue writer → quest target. Кнопки остаются параллельным доступным жестом над тем же методом.

`Ember Graph` v1.63 добавляет обратную безопасную операцию. Зелёный провод объект → фиолетовое action-событие можно разорвать, либо нажать `Отвязать выбранный объект` на writer-ноде: удаляется только точный `set_flag`, остальные шаги сохраняются, а Ctrl+Z/Redo охватывают Resource и scene binding одной операцией. Если цепочка используется несколькими объектами, срабатывает copy-on-write и общая цепочка остаётся неизменной. События внутри dialogue branch отсюда не мутируются — кнопка направляет автора в Dialogue Graph, где виден контекст ветвления.

`Ember Graph` v1.64 делает Quest Flow масштабируемым по представлению, не меняя Resource schema. По умолчанию виден компактный overview: только quest/objective-ноды и синие зависимости; каждая карточка показывает количество action chains, dialogue branches и объектов открытой сцены, содержит прежние bind-кнопки и `Открыть события и объекты`. Drill-down оставляет на canvas одну цель и только её фиолетовые/зелёные backlinks с рабочими open/unbind/drag действиями. `← Обзор` возвращает карту целей, а `Все связи` сохраняет прежнюю полную диагностическую проекцию. Overview, каждый focus и all-links имеют отдельные session-only camera/node positions; только overview-позиции quest/objective могут попасть в canonical `editorLayout`.

`Ember Graph` v1.65 исправляет соединения целей в компактном Quest Flow. В Godot номер порта — это порядковый индекс среди включённых входов GraphNode, поэтому скрытие золотого membership-входа сдвигает синий dependency-вход с `1` на `0`. Render, создание и удаление зависимости теперь используют один расчёт порта; targeted test проверяет границы всех отрисованных GraphEdit connections.

`Ember Migration` v1.66 добавляет изолированный D1 Combat Lab, а не production battle-system. `Проект → Инструменты → Ember: Open/Run Combat Lab` открывает E1 «Мокрый проводник»: 3 героя против 3 врагов, четыре позиционные области, видимая очередь, восемь тестовых действий и live preview урона/статусов/реакций/перемещения. `EmberCombatPrototype` является единым чистым resolver для preview и commit; UI и deterministic enemy turn не копируют таблицу стихий. Lab не пишет save, не создаёт Resource/schema и не связан со снятой Vampire Survivors arena.

`Ember Migration` v1.67 добавляет в ту же Combat Lab контрольный E2 «Цветная переправа» на сетке 7×5. `M` включает выбор доступной клетки; затем игрок выбирает действие/цель, а `F` одним commit фиксирует обе фазы. Pure `EmberCombatGrid` считает reachability, blockers и staged movement, а прежний resolver остаётся единым владельцем range, урона и реакций. Связанные синие панели проводят Wet/молнию, янтарные панели с Жар-фокусом усиливают огонь. E1 остался в переключателе для честного сравнения; это всё ещё изолированный D1, не production battle schema.

`Ember Migration` v1.68 добавляет общую команду `G. Защита`. Она всегда доступна герою, не требует вражеской цели, завершает ход без атаки и вдвое уменьшает следующий входящий урон. На сетке разрешено staged movement → Защита → один confirm. Это базовая боевая команда, а не девятое персональное умение. `Прикрытие` Орика остаётся отдельным умением защиты союзника.

`Ember Migration` v1.69 делает staged movement честно видимым. После выбора клетки активный герой сразу проецируется на destination с янтарной рамкой и подписью `план / ждёт F`; origin показывает `герой → destination`. Это только visual projection: pure snapshot продолжает хранить origin до `F`, `Вернуть` убирает план без mutation, а commit применяет ту же destination.

`Ember Migration` v1.70 завершает D1.5 semantic terrain перед 3D. Клетки имеют целочисленную высоту; один pure `EmberCombatTerrain.can_step()` ограничивает и BFS-движение, и принудительный толчок. Новый режим `E3 · Хранитель оттепели` показывает связанные изменения поверхности до подтверждения: холод заменяет Wet на Frozen у всей tide-группы, огонь возвращает Wet, а `cellChanges` применяются только одним общим commit. 2D grid уже является проекцией этого результата; следующий срез может заменить её на `GridMap`, не меняя resolver.

`Ember Migration` v1.71 добавляет D2.0 native 3D projection в ту же Combat Lab. E2/E3 по умолчанию показываются ортографической камерой через штатный `GridMap + MeshLibrary`: semantic elevation поднимает реальные тайлы, blockers имеют collision, юниты/Жар-фокус остаются отдельными `Node3D`, а reachable/pending/target/`cellChanges` рисуются overlays. Клик идёт camera ray → GridMap collision → canonical `Vector2i` и посылает прежний command; staged actor hit projection уже находится на destination. `Вид · 2D диагностика` возвращает прежнее представление того же snapshot. MeshLibrary пока генерируется как graybox и не является production art/content owner.

`Ember Migration` v1.72 убирает `SubViewport` из основной Combat Lab. `scenes/combat_lab.tscn` теперь является обычной сценой `Node3D`: в дереве явно видны `GridMap`, `Actors`, `Overlays`, `CameraRig/Camera3D`, свет и `WorldEnvironment`, а прежний контроллер интерфейса работает как HUD в `CanvasLayer`. Один `EmberCombatGrid3DWorld` используется основной сценой и старым embedded-адаптером, поэтому ray-pick, staged position и Frozen/Wet projection не дублируются. Graybox `MeshLibrary` пока создаётся projection-слоем; authored `.tres`-палитра и сохранение battle layout остаются следующим D2.1 authoring-срезом.

`Ember Migration` v1.73 расширяет существующий `OrbitCamera` и назначает его scene-owned `CameraRig`. В игре: ПКМ вращает ракурс, СКМ панорамирует поле, колесо меняет масштаб, WASD/стрелки двигают фокус, Q/E поворачивают, Home возвращает сохранённый ракурс. В Inspector у `CameraRig` доступны точка фокуса, distance, yaw/pitch в градусах, ограничения, orthographic/perspective, отдельные orthographic size и FOV, near/far и скорости управления. `@tool` применяет эти параметры к дочернему `Camera3D` прямо в редакторе; боевой HUD только передаёт mouse events с поля и не владеет камерой.

`Ember Migration` v1.74 вводит отдельные открываемые arena-сцены: `scenes/combat/arenas/colored_crossing.tscn` и `thaw_keeper.tscn`. `EmberCombatGrid3DWorld` стал `@tool`-проекцией и в редакторе строит те же 35 клеток, высоты, актёров и E2/E3 semantic preview из существующего pure snapshot; запуск игры для просмотра больше не нужен. Combat Lab инстанцирует E2 arena-сцену, а меню `Проект → Инструменты` содержит отдельные `Open Battle Arena · E2/E3`. `.tscn` владеет визуальной композицией, светом, камерой, декором и будущими spawn anchors; будущий `.tres` будет владеть semantic layout/rules. Transient preview пока не является свободно редактируемой палитрой клеток — authored MeshLibrary и battle Resource остаются следующим D2.1-срезом.

`Ember Migration` v1.75 добавляет live-preview непосредственно в Inspector узла `CameraRig`. Штатный Godot показывает такой кадр только у дочерней `Camera3D`; editor-only панель Ember подключается к тому же `World3D` открытой arena-сцены и синхронизирует transform/projection/size/FOV/clip/cull с `CombatCamera3D`. Она не создаёт второй мир и не участвует в runtime. Кнопка `Выбрать Camera3D` сохраняет доступ к штатным camera-свойствам и встроенному preview Godot. Inspector явно разделяет объективы: ортография использует только `Orthographic Size`, перспектива — только `FOV`; неактивное поле блокируется, а строка под preview показывает применённое значение.

`Ember Migration` v1.76 начинает D2.1 battle-field authoring. `colored_crossing.tres` и `thaw_keeper.tres` являются отдельными `EmberBattlefieldResource`: размеры, 35 типов поверхности, высоты, преграды, panel groups и Geo focus больше не зашиты массивами в resolver. Каждая arena `.tscn` явно ссылается на свой Resource; editor preview и runtime snapshot вызывают один `to_grid_dictionary()`. При выборе `.tres` Inspector показывает цветную мини-карту с высотами/tooltips и ошибки размеров/типов/focus. Это сохранённые semantic data, не второй GridMap-owner. Raw row-major arrays пока остаются переходным Inspector-представлением; следующий срез заменит их удобной paint-палитрой с Undo/Redo.

`Ember Migration` v1.77 добавляет paint-палитру в тот же Battlefield Inspector. Выберите `Обычная`, `Wet`, `Ember`, `Frozen`, `Преграда`, `Высота +/−` или `Перенести фокус`, затем кликните клетку мини-карты. Поле `Группа` связывает панели; пустое автоматически даёт `tide` для Wet и `ember` для Ember. Каждый клик — штатная Editor Undo/Redo operation, `Ctrl+S` сохраняет тот же `.tres`, а открытая arena live-перестраивает GridMap из Resource. Raw arrays остаются видимым storage/diagnostic fallback, но для обычной работы их больше не нужно редактировать.

`Ember Migration` v1.78 переносит те же восемь кистей непосредственно в штатный 3D viewport. Откройте arena-сцену, выберите её корень и включите `Поле боя` в верхней 3D-панели: hover обводит настоящую клетку, ЛКМ рисует, протягивание создаёт непрерывный штрих, `Alt+ЛКМ` берёт поверхность и группу пипеткой. Редактор накапливает штрих только как overlay и изменяет `EmberBattlefieldResource` один раз при отпускании кнопки, поэтому один `Ctrl+Z` отменяет весь штрих; `Ctrl+S` сохраняет прежний `.tres`. ПКМ/СКМ остаются свободны для камеры. `GridMap` не стал вторым владельцем данных, а физический raycast имеет безопасный semantic-surface fallback сразу после открытия сцены.

`Ember Migration` v1.79 добавляет к 3D-палитре форму применения: `Кисть`, `Прямоугольник` и `Заливка`. Прямоугольник показывает все клетки между точкой нажатия и hover; заливка выбирает только связную область с одинаковыми surface, elevation, blocking и group, поэтому не перескакивает на другой этаж или semantic-панель. До отпускания ЛКМ оба режима остаются overlay, а затем создают одну Undo operation. `Esc` отменяет незавершённый preview. Для `Фокуса` массовые формы блокируются. Inspector и 3D теперь используют одну визуальную палитру с цветными swatches; это удобство выбора semantic brush, а не готовая production `MeshLibrary`.

`Ember Migration` v1.80 заменяет генерируемые graybox-копии одной authored `content/combat/tiles/ember_battlefield_tiles.tres`. IDs 0–4 стабильно означают Neutral/Wet/Ember/Frozen/Blocked; все имеют mesh и collision, а общий shader даёт камню inset, воде полосы, Ember светящиеся трещины, льду грани и blocker hazard-pattern. Базовая arena, E2/E3 и Combat Lab ссылаются на один Resource; semantic Battlefield `.tres` и resolver не изменились. Кнопка `Тайлы…` в 3D toolbar открывает MeshLibrary в Inspector, где один editor-only viewport показывает пять реальных meshes и диагностику контракта. Эти материалы являются первым стилизованным battle graybox: любой item позже можно заменить voxel mesh под тем же ID без изменения карт или боя.

`Ember Migration` v1.81 закрывает размер и расстановку Battlefield Resource. Inspector показывает безопасный resize/remap: новые width/depth, девять якорей, число сохранённых/обрезанных/новых клеток и потерянных точек до Apply; клетки, высоты, groups, focus и deployment переносятся одной Undo/Redo operation. В общей палитре появились `Точка героев` и `Точка врагов`; один клик ставит или снимает canonical старт, а E2/E3 preview и runtime размещают тестовых бойцов из Resource вместо скрытых координат. `Размер…` в 3D toolbar открывает те же controls; нельзя удалить последнюю точку стороны, поставить её в blocker/focus или сохранить конфликт двух сторон.

The first roof/cutaway spike is opt-in only in `scenes/agent_sandbox.tscn`. It derives one separate cabin roof section from the existing `ground_z2 + interiorVolumes` data, uses an `Area3D` for occupancy and native `GeometryInstance3D.transparency` for the fade, and deliberately keeps the roof's structural shadow stable while only camera visibility changes. Press `F3` to see `cutaway active/sections`; press `F7` to preview the same fade without entering the cabin map trigger. Production scenes remain disabled until the visual and authoring gates in the migration plan are accepted.

Combat v2.59.2 keeps the existing Battlefield/Grid/Combat resolver. Unit `.tres` files own STR/MAG/DEF/RES/SPD/ACC/LUCK, level/type/size, elemental resistances, deterministic status reduction and push stability; Action `.tres` files own MP cost, accuracy/scaling, Skills/Magic grouping, conditions and push force. Hostile hit/critical rolls are locked internally and the same snapshot is committed once, but the pre-commit HUD deliberately reveals only cost, conditions and possible effect—not hit/miss, crit or damage. The radial menu has separate `Умения`/`Магия` pages without an actor-covering center plate, a bottom hover/focus description, and a top-right enemy study card. AI does not rank choices by the hidden future roll. During staged movement the camera smoothly follows and `F` focuses the visible destination without committing it; path validity is cached outside the per-frame camera path. Support, movement and effect resistance stay deterministic, fall damage stays exact, and save v2 still persists only level/XP/current HP/MP/equipment rather than derived stats.

Spike `scenes/spike.tscn` remains a lighting sandbox.

Pack path: `../joi-conductor/content/ember`. Override: Project Settings → `ember/pack_path`.

## Cursor MCP (Godot addon)

[KeeVeeG/godot-mcp](https://github.com/KeeVeeG/godot-mcp) in `addons/godot_mcp/`. Keep the Godot editor open. Cursor MCP entry runs `tools/godot-mcp.cmd`.

## Import contract

- Axes: MagicaVoxel Z-up → Godot Y-up, `ember(x,y,z) = vox(x,z,y)`.
- Prefabs: mesh + ShadowBody (non-emissive) + Omni in the emissive centroid + trimesh if `physical`.
- Lamp stone casts; window glow voxels do not. `emissiveSuppressHostShadow` opts out.
- door / talk / shop hang on `EmberInteract`; chest interaction and its authored `closedModelId/openModelId` visual reuse `EmberRegion`. Door and region triggers reuse Ember `targetMapId/targetRegionId`; Godot loads `res://scenes/<targetMapId>.tscn` and spawns at the named region. Arrival regions have a short time + frame guard against an immediate return loop, including a restored save position inside a trigger. Talk and script-only regions resolve the existing JOI `scripts/` then `scenes/` contract. The bounded action queue executes authored `talk`, `give_item`, typed `set_flag`, timed `wait` pauses and nested `run_script`; item grants stop on a visible reward card, while mutations remain in `EmberExploreState`. Shop plays its authored `shop_intro`, then uses the current item/shop catalogs and explore economy. I opens the functional party inventory: Q/E select the previous/next clearly marked hero, A/D changes bag/loadout, W/S selects and F uses/equips/unequips. In the world Tab changes the live leader model/name/HP while the previous leader joins the other three visible followers; T or the HUD button switches them between a bounded lively formation and exact leader-trail mode. One CharacterBody remains the only controller. The follow-mode signal is presentation-only and does not fan out through all progress-bound world objects. Party Unit Resources and read-only item definitions are discovered once per play session instead of being reloaded for every HP label or hero tab; mutable HP/MP/equipment are never cached separately. `EmberExploreState` remains the single persistent owner; save v2 keeps level/XP/current HP/MP/five equipment slots for the fixed four-person party, three manual slots and a separate autosave. Derived maxima/stats are recomputed. Missing v2 files migrate matching v1 once after making a byte-exact backup. Manual saves and the autosave can be deleted from the pause menu after a second confirmation; exact recovery copies remain under `deleted_saves`. At zero controlled-hero HP explore input is locked; R returns to the existing `player_start` and restores that hero without losing the rest of the party/world progress. F6 deliberately keeps the explicitly selected scene. Presentation overlays own no gameplay state. `agent_sandbox` alone enables H as a 30-damage manual probe; production scenes leave it disabled.

Automation must not open this working checkout with `--headless --editor`. The disabled `addons/at-icons` package contains 3,708 editor-themed SVGs whose generated variant depends on `EDSCALE` and the active editor theme; `addons/at-icons/.gdignore` now keeps them outside the asset scan. Keep that guard while the plugin is disabled. Run targeted checks as `--headless --path . --script ...` (as below), and use `--check-only` for individual scripts. A real import smoke belongs in a disposable checkout/cache, not the GUI user's live `.godot` directory.

```
python tools/test_vox_axes.py
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_object_inspector_model.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_object_inspector_panel.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_object_inspector_actions.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_voxel_prefab_rebuild.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_scene_edit_roundtrip.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_map_transition.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_explore_pause_menu.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_party_save_v2.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_party_followers.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_camera_relative_movement.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_talk_shop.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_shop_persistence.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_shop_resource.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_item_resource.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_visual_library.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_voxel_visual_library.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_map_visual_library.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_migration_workflow_layout.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_voxel_preview_renderer.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_progress_restore.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_inventory_equipment.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_action_script.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_action_resource.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_action_chain_authoring.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_dialogue_authoring.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_graph_workspace.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_quest_usage_index.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_vn_background_library.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_vn_portrait_library.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_vn_dialogue_resource.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_standalone_trigger_authoring.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_interact_launch_rules.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_health_consumables.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_quest_state.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_quest_journal_authoring.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_defeat_respawn.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_native_cutaway.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_combat_prototype.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_combat_grid.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_combat_arena_scenes.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_combat_camera_rig_preview.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_battlefield_resource.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_combat_lab.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_encounter_resource.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_combat_encounter_transition.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_combat_action_resource.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_combat_effect_library.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_combat_personal_actions.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_combat_unit_resource.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_combat_ai_profile_resource.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_combat_vertical_profile.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_combat_vertical_view.gd
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_combat_vertical_animation.gd
```

Воспроизводимый visual gate библиотеки боя на 1600×900 и 1280×720:

```powershell
tools\godot\Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/capture_combat_content_library.gd
```

## Encounter authoring v1.82

`content/combat/encounters/*.tres` связывает существующее поле, открытую 3D arena-сцену, состав текущего combat prototype и результат боя. В action chain шаг `Начать бой (финал)` выбирает встречу по мини-карте. После победы или поражения Combat Lab возвращает исходную map-сцену на сохранённую позицию и запускает отдельную outcome chain; ссылки на уничтоженные Node/UI между сценами не хранятся.

## Battle result and radial HUD v1.83

Авторская встреча запрашивает полноэкранное окно. В 3D вокруг текущего героя располагаются `M` и доступные действия `1–9`/`G`; круг следует за staged-позицией и камерой, а правая панель остаётся подробным прогнозом. Победа/поражение открывает отдельное центральное окно, поэтому `Продолжить`, `Повторить` и `Вернуться` не могут уехать за край длинной шапки. Переход затемняется, а `EmberCombatTransition` не позволяет повторному сигналу применить результат или награду второй раз.

## Tactical HUD composition v1.84

Двухколоночная лабораторная рамка удалена из 3D-режима: поле занимает весь viewport, очередь ходов является самостоятельной узкой колонкой слева, журнал — отдельной полупрозрачной консолью снизу слева, а снизу справа остаётся только прогноз. Дублирующий список действий скрыт, поскольку команды уже находятся в radial HUD. Ember-плагин отключает Godot Game Embedding для следующих playtest-запусков: встроенное окно движка не поддерживает переключение в fullscreen; отдельный процесс принимает прежний `DisplayServer.WINDOW_MODE_FULLSCREEN`.

В v1.85 radial HUD не закрывает выбор на поле: после `M` кольцо исчезает до клика по клетке, после умения — до выбора допустимого бойца. `Esc` отменяет текущий targeting и возвращает кольцо.

В v1.86 отдельное подтверждение `F` удалено: наведение на допустимую цель показывает прежний прогноз, клик сразу коммитит выбранное действие и staged movement, а `G`/self-action сразу завершает ход. `Esc` сначала отменяет выбор цели, затем открывает pause menu с продолжением, повтором и закрытием игры. Нижняя левая console/log получила строку snapshot-команд (`help`, `units`, `kill`, `heal`, `add hp/status`, `victory`, `defeat`, `turn`, `reset`, `clear`); они не выдают world reward и не обходят штатный result transition.

В v1.87 меню доступно и вне боя на всех сценах с общим `fan_town.gd`: кнопка `Меню · Esc` видна справа сверху, пауза предлагает продолжить, сохранить или сохранить и закрыть игру. Открытые диалог, магазин, сумка и журнал получают первый `Esc`; меню открывается только после их закрытия. UI ставит `SceneTree.paused`, работает в process-always и гарантированно снимает паузу при закрытии или смене карты.

В v1.88 закрыт первый result/reward/quest bridge. Окно победы заранее показывает предметы из прежней outcome chain, но не выдаёт их: единственным владельцем награды остаётся `InteractionUI` после возврата. Результат боя один раз увеличивает typed save-счётчики побед, побеждённых врагов, конкретной встречи и тегов врагов. В редакторе задания и Quest Flow у цели появился режим `Боевой счётчик`, подписанная библиотека доступных событий и требуемое количество; журнал отображает текущий прогресс вроде `1/3`.

В v1.89 Quest Flow позволяет убрать осиротевший action writer после удаления его объекта: на фиолетовой ноде без backlinks появляется компактная кнопка `Удалить лишнее`. Она удаляет один точный quest `set_flag`, удаляет весь Action Resource только когда он опустел и полностью поддерживает Ctrl+Z/Redo. Цепочки, всё ещё назначенные объектам открытой сцены, защищены и используют прежнее `Отвязать` с copy-on-write; общие dialogue branches редактируются только в Dialogue Graph.

В v1.90 шесть бойцов D2 вынесены из `EmberCombatPrototype` в `content/combat/units/*.tres`. Один `EmberCombatUnitResource` хранит имя, сторону, HP, скорость, дальность хода, действия, основной AI action, combat tags, цвет и будущий portrait; runtime копирует их в mutable snapshot. Encounter Inspector показывает визуальные строки состава, позволяет открыть бойца, менять порядок, добавлять и убирать участников с Ctrl+Z. `prototype_roster_order` задаёт стабильный порядок стартовой лабораторной расстановки, поэтому он не зависит от алфавитной сортировки файлов. 3D graybox и HUD используют authored цвет, а enemy resolver — authored `aiActionId`. Список действий пока остаётся прежним проверенным resolver-каталогом; его Resource-миграция является отдельным следующим срезом.

В v1.91 десять действий вынесены в `content/combat/actions/*.tres`. `EmberCombatActionResource` хранит название, подсказку, стихию, тип цели, числовые параметры, цвет/иконку и выбирает один поддерживаемый effect preset; формулы реакций по-прежнему исполняет только `EmberCombatPrototype`. В Inspector бойца raw ID-массив скрыт: вместо него показываются цветные карточки с открытием Resource, сортировкой, удалением, выбором из визуальной библиотеки и Ctrl+Z. У врага основной AI action выбирается только из назначенных карточек. HUD читает те же название, числа, цвет и optional icon, а hot-path использует кэш ссылок Resources без повторного сканирования папки при каждом preview.

В v1.92 одиночный `ai_action_id` заменён переиспользуемым `EmberCombatAiProfileResource` из `content/combat/ai_profiles/*.tres`. Профиль выбирает приоритет цели (минимум/максимум HP, ближняя/дальняя), порядок оценки действий (карточки, сила, задержка), приоритет готовой реакции и защиту ниже указанного процента HP. `enemy_command()` строит только разрешённые прежним resolver preview-варианты и детерминированно ранжирует их; профиль не наносит урон и не владеет pathfinding. В Enemy Inspector профиль выбирается подписанным списком со swatch, открывается отдельной карточкой и меняется через Ctrl+Z. Fixtures: `opportunist`, `relentless`, `guardian`; у стража добавлена карточка `defend` для проверки low-HP поведения.

В v1.93 тип врага ссылается на общий `EmberCombatLootTableResource` из `content/combat/loot_tables/*.tres`. В Enemy Inspector таблица выбирается подписанным списком с иконкой первого предмета; отдельный Loot Inspector показывает визуальные строки общей item-библиотеки, шанс и диапазон количества, поддерживает add/replace/remove и Ctrl+Z. Бросок является pure deterministic preview для финального battle snapshot. `EmberCombatResult` объединяет его с фиксированной наградой встречи, а после возврата generated `give_item` шаги добавляются в прежнюю `InteractionUI` queue: отдельного inventory/reward owner нет, карточки наград и защита от двойного Continue сохраняются.

В v1.94 таблицы больше не нужно искать через Unit Resource. В центральном `Ember Graph` появился режим `Лут врагов`: слева плиточная библиотека всех таблиц с item preview, числом позиций и поиском по таблице/врагу/предмету, справа — полный прежний редактор строк. Быстрый вход находится в `Проект → Инструменты → Ember: Open Loot Library`; assigned table у врага по-прежнему открывается своей кнопкой. Это main-screen проекция canonical `.tres`, а не второй каталог или документ.

В v1.95 враги перемещаются через тот же staged grid contract, что игрок. `EmberCombatGrid` выдаёт достижимые клетки и стоимость BFS-пути с прежними blockers, occupancy и пределом высоты; AI Profile выбирает `Держать позицию` или `Искать клетку для действия`, а `enemy_command()` ранжирует только общие action previews. Если атака ещё недостижима, враг делает отдельный детерминированный ход сближения и объясняет его в журнале. Ближний `enemy_strike` теперь имеет дальность 1; перемещение и последующая атака применяются одним прежним `Combat.commit()` без второго pathfinding или mutable AI-state.

В v1.96 стартовая табличка `sbx_quest_sign` переведена с неоднозначной legacy-связки на native `quest_id = sandbox_notice_quest` + `script_id = sandbox_notice`. Цепочка по-прежнему одновременно запускает задание и выполняет его первую цель, но после F обработанный giver скрывается; `sandbox_notice_read = true` больше не превращает его в ложную зелёную иконку завершения всего задания. Остальные последовательные цели и текущий save не сбрасываются.

В v1.97 размер voxel-арта отделён от gameplay-блока. Поле `voxelsPerBlock` по умолчанию даёт legacy 16, а новая плотность environment-блока равна 32. `VoxMesher` собирает оба варианта в normalized block-space; `EmberVoxelProp` применяет адаптер 16 для мира и может без remesh переключиться на 1.2 для боя. Prefab и normalized mesh по-прежнему кэшируются по `model_id`, но физический размер больше не запекается в mesh. Voxel-библиотека показывает плотность и footprint; старые 176 моделей и карты массово не перезаписываются.

В v1.98 исправлена конечная граница миграции: JOI больше не планируется владельцем voxel-скульптора. `EmberVoxelModelResource` хранит исходную форму, palette/channels, 16/32 density, footprint, physics и light metadata в `content/voxel_models/*.tres`. `EmberVoxelCatalog` и prefab builder native-first; старые `.json + .vox` являются только read-only очередью одноразового импорта. Первый реальный pilot `vox_fan_anvil` уже собирает preview/mesh/collision без чтения JOI. `EmberVoxelLegacyImporter` никогда не пишет обратно; `test_native_voxel_resource.gd` проверяет import → save/reopen → native catalog → prefab. Следующий срез — визуальная очередь миграции и main-screen Godot voxel editor со strokes и Undo/Redo, после чего 175 оставшихся моделей проходят parity report и voxel fallback удаляется.

В v1.99 visual migration queue встроена в прежнюю библиотеку voxel-префабов. Она открывается без карты, показывает `Godot / ожидают импорт / всего`, owner выбранной карточки и действия `Перенести в Godot` либо `Открыть Godot Resource`; `Добавить в сцену` отдельно требует открытую Ember Map. `EmberVoxelModelStore` проводит import и rebuild через общий Editor Undo/Redo: Ctrl+Z удаляет только native `.tres`, возвращает legacy projection и пересобирает derived prefab; Redo повторяет перенос. Старые JOI-файлы остаются byte-identical. Кнопки запуска JOI sculptor и `ember/joi_editor_url` удалены; `.vox/.json` доступны только как legacy diagnostics. Gate: `test_voxel_migration_queue.gd`, `test_migration_workflow_layout.gd` и прежние native/prefab/preview tests.

В v2.00 в main-screen `Ember Graph` добавлен режим `Voxel Surface · pilot`. Это первый shape/UX gate художественного контракта ALLfiring/Ember, а не production world format: один связный холст 4×4 игровых блока хранится временно как обычный `EmberVoxelModelResource` с плотностью 32 art vox/block и строится прежним `VoxMesher`. LMB наращивает, вырезает или красит выбранным цветом; радиус 1/2/4/8 и `Coarse 2×2×2` дают detail/legacy-aligned strokes. RMB/MMB вращает ортографическую камеру, колесо меняет масштаб, presets показывают world/battle ракурс, золотой overlay отделяет gameplay blocks от мелкой формы. Каждый мазок — одна общая Godot Undo/Redo operation; `Сохранить .tres` записывает `res://content/voxel_models/ember_surface_pilot.tres`, смена раздела защищена dirty-guard. Финальный chunk store, material-channel painting и world layout намеренно не вводятся до ручной оценки цельности поверхности. Gate: `test_voxel_surface_sculpt.gd` и projection в `test_graph_workspace.gd`.

V2.01 убирает фриз при мазке, не меняя source-format: только editor preview разделён на участки 16×16 art-вокселей. Мазок перестраивает затронутые участки и соседний участок лишь тогда, когда изменена граничная ячейка. `VoxMesher.build_from_ember_model_region` читает одновоксельный padding из общего массива, поэтому внутренние грани между участками не появляются; полный prefab/runtime mesh остаётся прежним. На pilot benchmark локальная проекция сократилась примерно с 336 мс для полного холста до 9 мс для обычного участка. Тест сравнивает точное число индексов всех preview-chunks с полным mesh и проверяет, что локальная операция минимум в пять раз дешевле.

V2.02 превращает одиночный клик в настоящий sculpt stroke. Пока LMB удерживается, редактор применяет кисть к локальному preview и заполняет все art-voxel клетки между последовательными позициями курсора, поэтому быстрый диагональный жест не оставляет дыр. Канонический Resource остаётся единственным владельцем формы, а отпускание LMB регистрирует уже показанный результат как одну общую Godot Undo/Redo operation без второй пересборки. Один Ctrl+Z отменяет весь путь, Redo возвращает его целиком; Esc до отпускания восстанавливает состояние начала жеста. Следующие отдельные срезы — height slices и material channels.

V2.03 добавляет рельефные кисти `Поднять` и `Углубить`. Они работают по X/Z-колонкам единого voxel-объёма и используют мягкий радиальный falloff: центр получает выбранный `Предел 1/2/4/8/12/16 vox`, края — меньшую высоту. Предел считается от формы при нажатии LMB, поэтому частые события мыши и повторное прохождение внутри одного жеста не создают бесконечную башню или яму; новый отдельный жест может осознанно продолжить форму. Полупрозрачный конус показывает радиус, направление и максимальную высоту до применения. Радиус расширен до 16 art voxels. Данные, local chunk preview, непрерывный drag, Esc и единая Undo/Redo operation остаются прежними. По официальным sculpt-наборам Blender/ZBrush следующими полезными для Ember являются `Уровень/терраса`, `Сгладить` и двухточечная `Рампа`; процедурный шум/штампы идут позже, чтобы не разрушать handmade-композицию.

V2.04 уточняет рельеф по ручному тесту: выбранный предел больше не применяется сразу. Короткое нажатие поднимает/опускает центр на один art-воксель; удержание LMB на месте постепенно наращивает форму со скоростью `2/4/8 vox/сек` до cap. Накопление основано на editor process delta, а не на FPS или числе mouse-motion событий. При переходе в другую X/Z-колонку её buildup начинается заново; radial falloff растёт вместе с центром. Baseline всего жеста остаётся фиксированным, поэтому cap честный, Esc и один Undo возвращают точную форму до нажатия.

V2.05 убирает main-thread пики удерживаемой широкой кисти. Preview больше не вызывает `EmberVoxelModelResource.to_definition()` на каждом уровне: новый общий `VoxMesher.build_from_packed_voxel_region()` читает канонические `PackedByteArray/PackedColorArray` напрямую, но использует тот же padded culling и материалы, что Dictionary/runtime path. На pilot один region снизился примерно с 12.7–13.5 мс до 8.9–9.0 мс. Затронутые чанки складываются в coalescing-очередь и перестраиваются максимум по одному за editor-frame: новый уровень заменяет ещё не показанное старое состояние, поэтому широкая кисть не создаёт один 30–40 мс пик. `Resource.changed` отправляется один раз на pointer-up; golden gameplay grid также обновляется один раз. Source-format, полный runtime mesh и одна Undo operation не изменились.

Hotfix v2.05.1 убирает два editor-шума. `test_map_transition.gd` больше не зависит от global-class registry ради двух динамических свойств autoload: сам `EmberExploreState` по-прежнему отдельно компилируется и проверяется progress/defeat/inventory/health/quest тестами. Surface Canvas больше не пытается вручную менять `SubViewport.size`, когда `SubViewportContainer.stretch=true`: размером владеет штатный container, поэтому предупреждение `Can't change the size` исчезает без изменения preview resolution contract.

V2.06 разделяет живой отклик рельефной кисти и точную объёмную фиксацию. Во время удержания `Поднять/Углубить` preview строит только видимую верхнюю оболочку и открытые боковые ступени из один раз вычисленного padded heightfield; на текущем pilot один чанк занимает примерно 1.5 мс вместо 8.5–8.9 мс точной сетки. На pointer-up те же изменённые чанки заменяются точным volumetric mesh по прежней coalescing-очереди. Канонические voxels, `.tres`, Undo/Redo, prefab/runtime mesher и material surfaces не меняются. Общий точный mesher также перешёл с `SurfaceTool.index()` на прямые indexed `ArrayMesh` buffers. Zylann Voxel Tools 1.7 проверен как возможный нативный backend, но не установлен: текущий gate не оправдывает второй binary/store, пока reversible draft path держит live-frame budget.

Hotfix v2.06.1 делает `test_map_transition.gd` независимым от потенциально устаревшего editor global-class cache для `EmberPlayer`. Runtime-сцены по-прежнему обязаны создавать настоящий `EmberPlayer`, а route-suite проверяет только необходимый ему `CharacterBody3D` body/position contract. Сам `ember_player.gd` отдельно проходит `--check-only`; defeat/respawn и camera tests продолжают проверять поведение игрока типизированно.

V2.07 принимает официальный Zylann Voxel Tools `1.7x` как съёмный Windows GDExtension backend только для точного editor-preview. Канонический `EmberVoxelModelResource` по-прежнему один: adapter перекладывает один padded chunk в `VoxelBuffer`, `VoxelMesherCubes` строит greedy mesh после pointer-up, а отсутствие addon или несовместимая клеточная прозрачность автоматически возвращают штатный `VoxMesher`. Во время удержания остаётся более быстрый heightfield draft. Сам жест больше не копирует весь массив 128×24×128 на каждом уровне и кэширует baseline-высоту затронутых колонок; повторный расчёт большой radius-16 формы в headless gate снизился примерно с 4.3 до 2.2 мс до учёта меньшего числа реальных delta-ячеек. Точная native-проекция одного pilot chunk занимает около 3.0–3.4 мс и выполняется из coalescing-очереди. Gate: `test_voxel_tools_backend.gd` плюс прежний voxel/runtime suite; provenance/removal записаны в `docs/EMBER_ADDONS.md`.

V2.08 делает time-based Raise/Lower инкрементальным по высоте. При переходе, например, с уровня 7 на 8 формула обходит только новую оболочку между этими уровнями; уже созданные этим же жестом слои не пересчитываются и не попадают повторно в change-set. Baseline, radial falloff, итоговая форма, один Undo и save-format не изменились. Headless radius-16 gesture на восемь уровней теперь заканчивает поздний уровень примерно за `0.35 ms`; весь расчёт занимает около `7.1 ms` вместо прежних примерно `9.3 ms` (машинные значения являются ориентиром, обязательный gate — отсутствие роста поздних уровней). Parity-тест сравнивает полный voxel buffer с одноразовым применением высоты и доказывает, что каждая изменённая ячейка входит ровно в один incremental delta.

V2.09 закрывает overlap-сценарий широкого рельефного мазка. Пока LMB удерживается, workspace помнит максимальную обработанную оболочку каждой X/Z-колонки и достигнутую высоту каждого центра кисти: возврат по уже нарисованной области становится no-op, а удержание на ней продолжает рост с прежнего уровня. Частые `InputEventMouseMotion` схлопываются до последней позиции одного editor-frame; общий `line_cells()` восстанавливает непрерывный путь. Для Raise/Lower шаг отпечатков равен половине радиуса — широкая кисть не вызывает десятки почти одинаковых расчётов на каждом art-вокселе, но круги всё ещё существенно перекрываются без разрыва полосы. В headless radius-16 sweep повторный обратный проход по пяти центрам снизился примерно до `1.6 ms` и `0` повторных изменений. Кисти radius 1/2 и нерельефные инструменты сохраняют поклеточный путь.

V2.10 заменяет разреженные круги v2.09 одной непрерывной swept-капсулой между предыдущей и текущей позициями мыши. Разрежение оказалось визуально неверным для высоких конусов: их узкие верхние сечения не перекрывались и оставляли отверстия в гребне. Теперь falloff вычисляется от ближайшей точки всего X/Z-отрезка, поэтому его центральная линия на любой длине получает полную текущую высоту, а боковые склоны остаются гладкими. Один coalesced mouse endpoint по-прежнему даёт один ограниченный проход по bounding-полосе, column/height caches отсекают готовую оболочку. Headless radius-16 sweep занимает около `10.5 ms` для новой полосы и `1.1 ms` для обратного прохода с `0` changes; gap-тест проверяет каждую колонку и каждый добавленный voxel центрального гребня.

V2.11 добавляет отдельную экспериментальную кисть `Поднять оболочку · test`. Она переносит верхнюю поверхность по тому же swept/falloff contract, заполняет только верхние клетки и те вертикальные колонки, которые нужны для закрытия видимых перепадов с четырьмя соседями; скрытый объём над непрерывным фундаментом остаётся полым. Повторное наращивание в одном мазке передвигает старый верх вместо накопления внутренних горизонтальных слоёв, а Undo/save используют тот же `EmberVoxelModelResource`. На 56-voxel radius-16/height-8 ridge получено `2 548` изменённых occupancy-ячеек против `10 316` у solid Raise. Это пока не production-оптимизация: fixed `PackedByteArray` всё равно имеет полный размер, shell calculation на длинном сегменте около `26 ms` против `21 ms`, а общий exact mesher строит внутреннюю нижнюю сторону оболочки (`74 550` против `43 302` индексов). Кисть оставлена явно как visual/data experiment; выигрыш потребует surface-aware derived mesher либо будущего sparse storage, а solid Raise остаётся безопасным default для срезов, пещер и разрушения.

V2.12 делает скорость оболочки явно управляемой и наблюдаемой. Presets теперь покрывают `1/2/4/8/16/32 vox/сек`; первый voxel по-прежнему появляется сразу, следующие вычисляются только из editor process delta, а строка состояния показывает фактически выбранную скорость рядом с текущей высотой. Radius presets расширены до `1/2/4/6/8/12/16/24/32`, height cap — до 24; те же значения доходят до pure solid/shell formulas без старых clamp 8/16. Radius 24/32 являются осознанными XL-режимами: первый shell stamp radius-32 занимает на текущем headless fixture около `33 ms`, тогда как последующие preview chunks остаются frame-budgeted. Tests проверяют metadata UI и то, что shell при одинаковых 0.5 сек действительно получает разные высоты для 1/4/16 vox/sec.

V2.13 добавляет формообразующую кисть `Выровнять площадку`. Первая точка LMB фиксирует высоту на весь жест: swept-круг между последующими позициями достраивает низкие колонки выбранным материалом и срезает высокие, поэтому дороги, дворы и боевые площадки получаются одной непрерывной плоскостью без ряда перекрывающихся stamp-вызовов. `Coarse 2×2×2` округляет плоскость до полного двухвоксельного слоя. Кисть не использует time-based buildup и не меняет source format; live local chunks, save и один общий Undo/Redo остаются прежними. Pure gate проходит смешанные исходные террасы, непрерывный длинный segment, повторный no-op, coarse alignment и exact Undo/Redo.

V2.14 добавляет обратную R&D-кисть `Углубить оболочку · test`. Raise/Lower теперь используют одну pure shell formula с направлением: вниз она переносит видимый верх к меньшей Y, очищает прежний верх и перестраивает кольцо открытых стенок вокруг впадины. На сплошном грунте визуальный результат совпадает с обычным Lower; отличие проявляется на ранее поднятой полой форме, где interior остаётся пустым и не получает скрытого заполнения. Скорость, cap, swept footprint, Esc и один Undo/Redo общие с рельефом. Gate строит полую горку, углубляет внутри неё, проверяет отсутствие старого верха/скрытого объёма/щелей в четырёх направлениях и byte-identical incremental/one-shot result.

V2.15 закрывает отсутствующий camera offset в Surface Canvas. RMB теперь только вращает orbit, MMB сдвигает target камеры по плоскости X/Z, колесо сохраняет прежний orthographic zoom. Кнопка `Центр` возвращает target к середине 4×4 холста, не меняя текущий угол и zoom; presets `Камера мира/боя` сбрасывают также offset. Панорамирование не меняет Resource и не участвует в Undo. Graph gate проверяет реальное изменение target и точный reset.

V2.16 добавляет `Сгладить ступени` с силой `1/2/4/8 vox`. Каждая колонка swept-области один раз за LMB приближается к среднему top девяти соседних колонок не дальше выбранной силы; пустые authored holes не закрываются автоматически. Поэтому одиночные зубцы смягчаются, но крупные террасы не исчезают за один проход, а новый жест осознанно продолжает smoothing. Coarse заканчивает полным двухвоксельным слоем. Derived heightfield строится при открытии canvas и после мазка/Undo обновляет только затронутые X/Z: radius-32 sweep на текущем gate около `14 ms`, revisit около `2.3 ms` с нулевым change-set. Resource/save/local preview/one-gesture Undo остаются прежними.

V2.17 завершает первый набор формообразующих кистей инструментом `Склон A → B`. Первый клик фиксирует исходную поверхность и показывает голубой маркер, второй берёт реальную высоту назначения и одним bounded проходом строит между ними цельный коридор выбранной ширины. Высота меняется линейно вдоль направления, поэтому склон проходит через границы будущих игровых клеток и не требует отдельного лестничного тайла. `Coarse` формирует полные двухвоксельные слои; второй клик является одной Undo/Redo operation, Esc до него снимает точку A без изменения Resource.

V2.18 отделяет размер карты от текущего окна работы. `Выделить участок` принимает два угла на видимой поверхности и показывает проходящую по рельефу голубую рамку; после второго клика все shape/paint/ramp кисти физически фильтруют изменения по выбранному прямоугольнику, но сам участок не копируется и не становится отдельной моделью. Контекст снаружи остаётся видимым и неизменным, `Вся поверхность` снимает маску. Рамка является editor-only state и не сериализуется. Текущий 4×4 Resource остаётся performance pilot; тот же selection contract будет работать на следующем произвольно крупном chunked Surface без фиксированного 7×9 формата.

V2.19 подключает Surface Canvas к настоящей карте боя. В штатной верхней панели 3D появилась кнопка `Вся арена → Surface`: она один раз создаёт `content/combat/surfaces/<field>_surface.tres` размером ровно с текущий `EmberBattlefieldResource`, переносит в стартовую форму semantic-высоты/Wet/Ember/Frozen/blockers и назначает ссылку через Godot Undo/Redo. Повторное открытие редактирует тот же Resource; внутри Canvas можно ограничить кисти прежней голубой рабочей областью. Gameplay по-прежнему читает semantic Battlefield, поэтому мелкий voxel-узор не меняет дальность, pathfinding или высоту клетки. Большие поверхности заполняют preview по одному chunk за кадр. Ошибка `Texture dimensions exceed device maximum` устранена отдельным capped SubViewport: main-screen relayout больше не может запросить GPU-текстуру крупнее 4096 px. Это первый arena-authoring slice; отображение authored surface вместо graybox GridMap и выбор региона глобальной world-сцены идут следующими отдельными вертикальными срезами.

V2.20 делает камеру Surface Canvas пригодной для произвольной арены и включает authored surface в саму боевую сцену. При открытии и по `Home` весь настоящий voxel AABB, включая высоту рельефа, вписывается с запасом; wheel больше не упирается в старый максимум 14. `Камера…` открывает точные yaw/pitch/orthographic size/fit margin и вид сверху, RMB/MMB сохраняют orbit/pan. В arena editor и Play visual `.tres` строится теми же 16×16 chunks поверх единого масштаба `1 visual block = 1.2 battle units`; после готовности graybox GridMap скрывается визуально, но остаётся единственным владельцем collision, cell picking, pathfinding и combat elevation. При повторном sculpt старые chunks остаются видны, пока новые заменяются по одному за кадр. Также исправлено первое сохранение surface: save с `FLAG_CHANGE_PATH` и явный `take_over_path()` гарантируют внешнюю ссылку вместо мегабайтной embedded-копии; ранее созданная embedded поверхность без потери формы внешализируется при следующем `Вся арена → Surface` и сохранении Battlefield.

V2.21 переносит выбор рабочей области в обычный 3D viewport глобальной карты. В верхней панели Ember-карты `Surface-область` принимает два клика по Terrain, рисует голубую block-aligned рамку и передаёт этот `Rect2i` в прежний Surface Canvas; `Открыть область` редактирует только рамку, `Вся карта` снимает scope. Canvas сразу центрирует/вписывает выбранный участок и строит его preview-chunks раньше дальнего контекста. На карту назначается один внешний `content/world_surfaces/<map>_surface.tres`: прямоугольник не копирует voxels и не создаёт patch Resource. Первый seed сохраняет legacy 16-art-voxel высоты и цвета без потери текущего масштаба; новые 32-grid Tile Kit элементы остаются совместимы по footprint. Это authoring pilot: gameplay collision/regions пока остаются прежним scene owner, а проекция общей Surface обратно в world viewport/runtime и chunked storage для большой `fan_town` являются следующим отдельным gate.

Hotfix v2.21.1 делает health/save/defeat smokes устойчивыми к первому проходу индексатора Godot: test scripts явно `preload`-ят `ember_explore_state.gd`, а сценовый Player проверяют через достаточную `CharacterBody3D` + public hook boundary. Это устраняет ложный каскад `Could not parse global class EmberExploreState` → `Cannot infer type`/`Could not resolve progress_state` при открытии проекта. Runtime-типизация не менялась; `ember_explore_state.gd` и все три полных smoke проходят отдельно.

V2.22 замыкает первый визуальный цикл world Surface: после `Открыть область` или `Вся карта` сохранённая общая поверхность постепенно появляется прямо в обычной 3D-сцене и в Play. Новый leaf-компонент `ember_voxel_surface_projection.gd` обслуживает и карту мира, и боевую арену одним `VoxMesher`/material contract, собирая не больше одного 16×16 art-voxel chunk за кадр. До готовности остаётся прежний graybox; при повторном sculpt старая точная поверхность не исчезает, пока чанки заменяются. В world-сцене скрывается только `Terrain/Mesh`, тогда как `Terrain/Collision`, регионы, props, навигационная высота и gameplay grid остаются прежними semantic owners. Surface с чужим `semanticOwner` или размером не заменяет Terrain и показывает configuration warning. Dense `.tres` пока остаётся authoring pilot; следующий отдельный срез — sparse/chunked data owner для больших карт без смены editor UX.

Hotfix v2.22.1 меняет неудобные обязательные два клика на обычное drag-выделение: `Выделить участок` принимает зажатие и протяжку ЛКМ, но два отдельных угла также поддерживаются. Во время жеста видны полупрозрачная голубая область, четыре маркера, размер и подсказка в toolbar. Picking сначала использует настоящую collision-поверхность, затем обязательно пробует map-local plane, если луч перехватил внешний prop/helper; клики в пределах 0.35 клетки от края мягко привязываются к карте. Поэтому выбор не срывается из-за декоративных объектов или пиксельного промаха по границе.

V2.23 начинает общий UI/UX-проход по аддону с главной проблемы 3D viewport: world Surface и Battlefield toolbar теперь появляются только в своей сцене, а не занимают место отключёнными контролами одновременно. У боя кисть/форма/группа видны только при включённом рисовании; библиотека, resize и переход в Surface собраны в `Ещё…`. У карты открытие всей Surface также перенесено в `Ещё…`; короткий статус обрезается, но полный текст доступен в tooltip. Игровые Resources, Undo/Redo и runtime не менялись. Общий аудит и порядок следующих срезов закреплены в `docs/EMBER_EDITOR_UX_AUDIT.md`.

V2.24 пересобирает Surface Canvas как полноценное рабочее пространство. Все десять кистей находятся в стабильной левой колонке; верхняя строка содержит только название активного инструмента и его часто меняемые radius/material/coarse/strength/rate/cap. Камеры мира/боя/сверху, Home-fit, центр и точные значения собраны в одном меню `Вид`; `Сохранить` остаётся справа в неизменной шапке. Справа находится прокручиваемая панель с короткой подсказкой выбранной кисти, рабочей областью и путём Resource; reset виден только у тестового pilot-холста. Viewport и sidebar разделены штатным `HSplitContainer`, а прежний 4096 render-target guard сохранён. Это только editor UI: формулы кистей, один Undo на жест, `.tres` и runtime-проекция не менялись.

Hotfix v2.24.1 выводит это рабочее пространство отдельной main-screen вкладкой `Surface Canvas` рядом с `Ember Graph`. Это тонкий Godot `EditorPlugin`, который создаёт тот же `EmberVoxelSculptWorkspace`; второго формата, renderer или владельца Undo нет. Переходы из world selection и battle arena сразу открывают нужный Resource/область в новой вкладке. Старый видимый пункт `Voxel Surface` убран из selector Ember Graph, чтобы одного назначения не было в двух местах; скрытый embedded workspace оставлен только как recovery при ручном отключении новой вкладки.

V2.25 начинает material-channel этап без нового формата поверхности. Инструмент `Материал / вода` рисует существующий per-voxel канал `transparency` по той же форме, region-mask и радиусу, что цветная кисть; пресеты `плотный / мелкая вода / глубокая вода / прозрачный` сразу видны через общий transparent surface `VoxMesher` в Canvas, world и battle projection. Цвет остаётся независимым художественным слоем и задаётся `Красить`, поэтому прозрачность можно снять без перекраски. Протяжённый жест создаёт один Undo/Redo, Esc возвращает исходный sparse/full channel, а save/reopen сохраняет его в canonical `EmberVoxelModelResource`. Это первый material slice; shine/emissive и отдельный стилизованный water shader не имитируются неработающими UI-полями и остаются следующими вертикальными срезами.

Hotfix v2.25.1 добавляет к материалу режим `Связанная область` — аналог Magic Wand/contiguous fill для voxel-поверхности. Один клик идёт только по четырём соседям видимого верхнего слоя, остаётся на высоте исходной точки и сравнивает реальный RGB palette-color с допуском `точно / 5% / 10% / 20%`. Поэтому вода не перепрыгивает в отдельное озеро того же цвета, не поднимается на берег и не затрагивает скрытый грунт. Editor-only рабочая область является жёсткой границей; слишком большая заливка атомарно отклоняется и просит сначала выделить участок. Весь результат остаётся одним material Undo, а повторное применение уже заданного пресета не запускает лишний remesh.

V2.26 доводит материал до видимой voxel-оболочки и отделяет воду от обычной прозрачности пропов. `Связанная область` теперь обходит шесть соседей и берёт только voxels с хотя бы одной открытой гранью: верхняя гладь естественно продолжается на вертикальную стенку/водопад того же или близкого цвета, но не заполняет невидимый внутренний объём и не перепрыгивает пустой разрыв. World, battle и Surface Canvas назначают transparent-секции отдельный `ember_voxel_surface_water` material; рисунок привязан к общим координатам Surface Resource, поэтому сохраняет один художественный масштаб и не рвётся на chunk seams, дискретно анимируется, использует toon-свет, ступенчатые блики и отдельные вертикальные струи. Это derived visual: форма, collision, gameplay height и канонические `palette + transparency` не меняются. Пресеты переименованы в `глубокая / мелкая / очень прозрачная`, где глубокая вода сохраняет больше цветовой массы.

Hotfix v2.26.1 меняет неудачную раннюю стилизацию на спокойную базу `Minecraft × мультяшная pixel-art диорама`. Вода теперь является цельной полупрозрачной цветовой массой из четырёх крупных квадратных тонов; узор смещается медленно и только целыми texel-шагами. Вертикальные грани используют тот же узор, лишь немного темнее, без частых полос и ложного эффекта водопада. Убраны случайные светящиеся точки, высокий specular, rim и clearcoat: отражения, авторские блики и береговая пена будут отдельными читаемыми слоями после ручной приёмки этой основы, а не частью процедурного шума.

V2.27 исправляет саму модель изображения воды после второго отклонённого visual gate. У Surface `transparency` теперь трактуется как authoring-mask отдельного мелко приподнятого water overlay, а не как команда сделать грунтовый voxel прозрачным. Surface-specific leaf-mesher всегда строит исходные voxels непрозрачным дном, затем greedy-прямоугольниками добавляет только горизонтальную воду над отмеченными верхними гранями; generic voxel-пропы сохраняют прежнюю семантику прозрачности. Шейдер почти бесцветен: дно, камни и цветовые пятна видны из authored voxels, а вода добавляет лёгкий бирюзовый tint и редкие разорванные бело-мятные линии, смещающиеся менее раза в секунду как стоячая рябь. Connected selection снова ограничен одной связной высотой дна; боковой грунт не становится водой. Screen/depth refraction, отражения и контактная пена намеренно отложены до принятия этой базы.

V2.28 заменяет разорванные штрихи на одну связанную pixel-cell сеть: каждый фрагмент считает границу между ближайшими ячейками в мировых X/Z, поэтому линии образуют замкнутый рисунок и проходят через границы greedy-квадов и preview chunks без швов. Под ними четыре широких бирюзовых тона медленно переходят друг в друга дискретными шагами; authored-дно по-прежнему остаётся главным источником камней, пятен и глубины. В шапке `Surface Canvas` появился editor-only переключатель `Слои · дно + вода / только дно`: он временно исключает overlay из preview, но не меняет и не сохраняет другой water-mask. Так дно можно спокойно красить и скульптить, затем одним переключением проверять итоговую композицию. Screen/depth refraction, отражения и береговая пена всё ещё остаются отдельными будущими слоями.

V2.29 делает сетку воды примерно вдвое тоньше и добавляет первый отдельный слой контактной пены. `EmberVoxelSurfaceMesher` строит узкую светло-мятную полосу только вдоль реального края water-mask: у берега, смены высоты и отверстия вокруг более высокого voxel-объекта. Соседняя вода проверяется через canonical Resource даже за пределом текущего preview chunk, поэтому технический стык не превращается в ложный берег. Пена слегка меняет тон дискретными пиксельными шагами, но не рвётся и не перекрывает дно. Это намеренно mask-derived решение: обычный depth-foam у нашей почти прилегающей ко дну мелкой воды закрасил бы весь водоём. Динамический контакт с отдельными scene props/персонажами остаётся будущим вторым слоем и не смешивается с надёжным береговым контуром.

V2.30 добавляет общий инструмент `Заливка уровня` для прудов и будущих плоских сред. Один клик по дну запускает bounded priority-flood, находит ближайшую высоту перелива и заполняет только замкнутую связанную впадину; открытая или слишком большая область отклоняется атомарно. Ручные режимы `+1/+2/+4/+8/+16 vox` позволяют задать уровень явно с той же проверкой протечки. Заливка не добавляет грунтовые voxels и не меняет collision/gameplay height: `EmberVoxelModelResource` v2 хранит по X/Z-колонкам лишь plane level, material kind и необязательный palette tint; нулевой tint берёт читаемый цвет самого материала. Сейчас UI предлагает воду и удаление связного слоя; тот же сериализуемый контракт рассчитан на лаву, яд, туман и лёд без новых кистей или второго renderer. Canvas, world и battle строят одну горизонтальную water surface с прежним shader/foam, Undo/Redo и save/reopen.

V2.31 выравнивает вид воды между `Surface Canvas`, обычной вкладкой `3D` и боем: все три используют один прозрачный material без записи водной плоскости в depth buffer, поэтому authored-дно остаётся видно и в редакторском viewport. Mesher вычисляет из существующих `surface_fill_levels` реальную глубину до дна и передаёт четыре дискретные полосы только как derived UV; глубокие места чуть плотнее и холоднее, мелководье почти бесцветно. В `Заливке уровня` появился береговой отступ `вровень / на 1 / на 2 vox ниже`, по умолчанию один voxel, а пена стала тонкой, нерегулярной и прерывистой на длинных прямых краях. Ни один из этих visual-параметров не меняет грунт, collision или gameplay grid.

Hotfix v2.31.1 делает повторную `Заливку уровня` атомарной заменой, а не наложением новой меньшей маски поверх старой. Перед записью редактор собирает связанную семью прежнего жидкого слоя, включая соседние остаточные кольца с разными уровнями, очищает её целиком и затем записывает новый уровень; отдельный водоём за сухой колонкой остаётся нетронутым. Понижение больше не оставляет высокие полки воды, повышение расширяет ту же операцию, а Undo/Redo восстанавливает всю замену одним шагом. Если editor-only рабочая область разрезает существующую воду, операция безопасно отклоняется и просит расширить область вместо частичного шва.

V2.32 добавляет к общей прозрачной воде два спокойных camera-aware слоя без новой текстуры или данных карты. Ступенчатый Fresnel слегка подмешивает небесно-мятный тон только под косым углом, поэтому ортографический ракурс получает читаемое отражение, но voxel-дно остаётся главным изображением. Небольшая детерминированная часть уже связной ripple-сетки становится короткими бликами: выбор участков стабилен в world coordinates, яркость медленно меняется тремя дискретными шагами, а emission намеренно почти нулевой. Canvas, обычный 3D viewport, мир и бой используют тот же `.tres`; реалистичные screen-space отражения и шум не вводятся.

V2.33 добавляет второй, динамический слой контакта с водой. `EmberVoxelSurfaceProjection.water_surface_sample()` является единственным владельцем преобразования world footprint → canonical water column/plane height. Лёгкий `EmberWaterContact3D` кэширует projection, делает один O(1) sample за кадр и показывает две разорванные pixel-дуги только пока ноги находятся у поверхности; сканирования сцены в hot path нет. Explore player и все боевые юниты получают эффект автоматически. Для отдельного `EmberVoxelProp` автор включает `Вода → Water Contact Enabled` и настраивает радиус; по умолчанию сотни props не получают лишний process. Контактный material отдельный от береговой пены, но оба остаются derived visuals и не меняют fill, collision, navigation или combat Wet semantics.

V2.34 замыкает сохранённую world Surface с Play. Канонический путь `content/world_surfaces/<map_id>_surface.tres` теперь вычисляет сам runtime Resource-контракт, а `EmberMapLoader` подхватывает этот файл по `map_id`, даже если автор ещё не сохранил внешнюю ссылку `Visual Surface` в `.tscn`; явно назначенная ошибочная ссылка по-прежнему не маскируется fallback-ом. В шапке `Surface Canvas` у world-карт есть `▶ Играть карту`: она сначала сохраняет `.tres`, затем запускает именно связанную `scenes/<map_id>.tscn`, а не проектную `fan_town`. Runtime-проекция обрабатывает до 12 маленьких чанков за кадр в бюджете 4 ms, поэтому изменённый участок появляется быстро без возврата к единому блокирующему remesh.

V2.35 делает контактную воду читаемой в движении. `EmberWaterContact3D` измеряет только горизонтальную дельту позиции своего владельца, нормализует скорость в блоках Surface и плавно передаёт индивидуальную силу эффекта через instance shader parameter; общий material не мутируется между персонажами. В покое остаются две спокойные разорванные дуги, при ходьбе quad поворачивается по направлению движения и добавляет короткую переднюю волну плюс две расходящиеся pixel-дорожки сзади. Это тот же O(1) water sample и visual-only слой: Player, боевые preview-юниты и явно включённые props не получают нового movement/gameplay owner.

Hotfix v2.35.1 исправляет ручной visual gate движения: ось следа развёрнута на 180°, поэтому дорожки теперь остаются позади персонажа. Движущийся quad растягивается до 2.5 блоков назад, тогда как calm-ring компенсирует stretch в UV и сохраняет прежний круглый размер у ног. Число shader samples вдоль длинной оси растёт с тем же коэффициентом, поэтому pixel-сегменты остаются примерно квадратными, а не превращаются в длинные полосы.

Hotfix v2.35.2 заменяет растянутый attached-wake настоящей короткой историей движения. Кольцо и bow-wave остаются одним компактным quad у ног, а две тонкие дорожки рождаются у его боковых краёв, сохраняют world position и исходное направление при повороте героя, затем затухают. История ограничена 1.2 блока и 1.1 секунды, семплируется через небольшие интервалы и собирается в один `ImmediateMesh`, поэтому след выглядит оставленным на воде, но не создаёт Node/материал на каждый отпечаток.

V2.36 связывает визуальную воду боевой Surface с уже существующей семантикой `Wet`, не делая renderer владельцем правил. В Inspector `EmberBattlefieldResource` блок `VISUAL SURFACE → ПРАВИЛА ВОДЫ` считает долю art-колонок с водой внутри каждой крупной клетки, предлагает порог 10/25/50% и до записи показывает число будущих изменений. Явная кнопка одной Undo/Redo-операцией обновляет только canonical `terrain_kinds + groups`: покрытая нейтральная клетка становится `Wet/tide`, высохшая прежняя `Wet` очищается, а авторские `Ember/Frozen` не перезаписываются и перечисляются как защищённые. Runtime и реакции по-прежнему читают только Battlefield Resource; дальнейшую ручную правку клетки можно делать прежними кистями.

Hotfix v2.36.1 устраняет ловушку двух связанных Resource в Inspector. При выборе `content/combat/surfaces/<id>_surface.tres` над сырыми voxel-полями появляется карточка `EMBER SURFACE`: она прямо объясняет, что выбран visual owner, открывает его в `Surface Canvas` и даёт кнопку `Открыть правила боя · <id>`. Кнопка разрешает canonical Battlefield Resource по `semanticOwner`, поэтому автор сразу попадает в V2.36 water→Wet preview без ручного поиска соседнего каталога.

Hotfix v2.36.2 исправляет `Ошибка сохранения: File unrecognized` у старых embedded Surface. Путь Godot вида `battlefield.tres::SubResource_id` теперь явно распознаётся как read-only identity, а не файл. При открытии боевой Surface или повторном Save уже открытого Canvas текущий in-memory Resource — вместе со всеми несохранёнными sculpt/water-правками — переносится в canonical `content/combat/surfaces/<field_id>_surface.tres`; затем Battlefield owner сразу сохраняет внешнюю ссылку вместо многомегабайтной вложенной копии. Canvas дополнительно нормализует путь перед каждым Save и при реальной ошибке показывает полный target path.

V2.37 добавляет второй подтверждаемый мост от художественной Surface к боевым правилам: `VISUAL SURFACE → ВЫСОТЫ БОЯ`. Для каждой крупной клетки берётся медиана равномерных точек пола, поэтому одиночный камень, трава или небольшой скол не поднимают всю клетку. Базовый верх `3 vox` и каждые `14 art vox` переводятся в один canonical gameplay elevation — это точная обратная операция к созданию стартовой Battlefield Surface. Inspector заранее показывает число изменений, неровных и пустых клеток; только явная кнопка пишет `elevations` одной Undo/Redo-операцией. Renderer и pathfinding по-прежнему читают Battlefield Resource, а не voxel mesh напрямую.

## Lighting gate

See [LIGHTING_GATE.md](LIGHTING_GATE.md). Walk is in Godot on imported scenes, not WASD in JOI Chromium. Do not use `hu_tao_yard` / `hu_tao_p1` for mechanics.

## Not this repo

- Iris / Complementary
- Crowd, arena waves
- A second renderer inside joi-conductor
