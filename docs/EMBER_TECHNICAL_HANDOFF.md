# Ember Godot — технический handoff

Актуально: 11 сентября 2026. Editor stop-line v2.56.1, gameplay baseline v2.64.4;
активная группа 1–4 реализована, ручная приёмка ещё открыта.

Документ описывает текущее устройство, owners и реальные долги. Полный прежний
текст можно восстановить из монолитного Git checkpoint `20685ac`; это не
детальная цепочка исторических commits. Журнал каждой версии здесь больше не
ведётся. Ближайшая задача находится в `docs/EMBER_NOW.md`.

## Источники правды

### Публикация файлов редактору

`addons/ember_import/ember_editor_filesystem.gd` — общий editor-only адаптер
обновления индекса после авторских команд Ember. Все прежние прямые `scan()`
и `scan_sources()` в ember_import идут через него. Запись source/prefab остаётся
синхронной и принадлежит прежним транзакциям; очередь откладывает только
обнаружение файлов. Запросы объединяются после 150 ms без новых запросов,
ожидают окончания `is_scanning/is_importing`; полный scan имеет приоритет над
source-only. Ожидание использует кадры редактора и wall-clock, не gameplay timer.
Нет зависимости runtime Party/Explore от этой очереди и нет изменения schema.
`diagnostics()` даёт число scans, merged, busy waits и pending; слабая ссылка
не удерживает уничтоженный filesystem. Runtime-вызов без явного filesystem
ничего не делает. Очередь не чинит UID и не подавляет parse errors.
Intermittent загрузка Party/Explore в рабочем editor пока не воспроизведена:
её нельзя считать доказанно устранённой только по успешным headless gates.

### Воксельная мастерская и одиночный объёмный штамп (manual gate открыт)

2026-09-13: общая кнопка workspace «Сохранить», `save_changes()` и Ctrl+S
в активной вкладке «Генератор» идут через тот же `save_variant()`/Creation,
что и кнопка генератора. Режим публикации остаётся явно выбранным:
новая вариация / обновление выбранной / отдельный объект. Сохраняются точный
preview source/prefab и весь Recipe.parameters, не старый sculpt Resource.
Без актуального preview или контекста — явный отказ, без fallback к sculpt
save; ошибки публикации возвращаются в footer, успешная публикация снимает
preview. Manual dirty обновления проверяется непосредственно перед Save.
Никакой новой schema/owner и автоматической перегенерации при сохранении.
`test_voxel_workshop_generator_save.gd` пишет только user:// и проверяет все
три режима, полные параметры/voxels/palette, reopen controls, Undo/Redo,
Discard, stale preview и защиту manual dirty; headless/native Forward+ PASS.

Нативный UI workspace перестроен без нового owner: компактные основные
инструменты и постоянный compact PalettePanel слева, контекст
Object/Model/Part/Preset сверху, активные параметры над правыми вкладками
Parts/Library и контекстная помощь в footer. Палитра сохраняет прежние signals,
Undo owner и диалоги; локально прокручивается только сетка swatches.
`WorkshopSwatchButton` принудительно оставляет icon tint белым во всех состояниях,
поэтому ImageTexture swatch показывает точный цвет palette data, а не цветовую
модуляцию активной темы Godot.
Поле `Объект` в context bar редактирует имя текущего scene instance через
`ember_voxel_object_session.gd` и общий scene Undo/Redo; Surface оставляет поле
disabled, а display name/model ID ресурса показываются отдельно и не меняются.
`Parts` разделён на локальные `Selection/Groups/View`: выбор режима и операции
использует прямые сегменты, а groups/slice/region больше не образуют один общий
длинный scroll. Горизонтальный scroll отключён, group selector не подбирает
ширину по длиннейшему имени, а длинные labels/buttons используют wrap/ellipsis.
Панели сворачиваются; dirty/error/disabled состояния различимы. Библиотека
показывает карточки с миниатюрами, вычисленными в памяти из preset geometry,
не записывая кеш и не меняя Resource schema. Сетка карточек прокручивается
локально, поэтому выбранный пресет и `Разместить / Редактировать` не уезжают;
редко используемая форма capture свёрнута. OptionButton остаются внутренними
значениями существующего plan, но mode/axis/turn/mirror/anchor представлены
синхронизированными взаимоисключающими сегментами. Scoped factory
`ember_voxel_workshop_theme.gd` сначала копирует активную Godot Theme, затем
централизованно переопределяет только workshop Controls; editor fonts/icons/DPI
сохраняются, соседние плагины не затрагиваются. `test_voxel_workshop_layout.gd`
закрывает 1280×720/1600×900, постоянную левую палитру, три подраздела Parts,
переключение режимов и сегментов, закреплённые
library actions, стабильный Canvas, collapse, active operation, empty library
и dirty/error states.

Transient authoring state принадлежит самому `EmberVoxelSculptWorkspace`:
`BRUSH / SELECTION / SELECTION_TRANSFORM / STAMP_LIBRARY / STAMP_DRAFT /
COLOR_PICK / REGION_SELECT`. Переход атомарно отменяет старый черновик, синхронно
меняет ввод, один primary highlight, контекстные параметры, курсор и панели.
Последняя кисть хранится отдельно от визуального ItemList selection, поэтому
выделение и штамп не оставляют вторую янтарную подсветку. Библиотека штампов
navigation-only и не пропускает LMB в кисть; `Esc` из временного режима возвращает
последнюю кисть. Высота строки параметров зарезервирована, поэтому Canvas не
скачет при скрытии несовместимых controls.

Объектная библиотека 3D отделена от библиотеки штампов Canvas и от migration
dashboard. `ember_voxel_object_library_panel.gd` регистрируется plugin как
постоянная нижняя полка `Объекты`; входы — кнопка `Объекты` в 3D-toolbar и
`Открыть полку объектов` в Ember Migration. Полка использует прежнюю проекцию
`EmberVoxelVisuals`, `EmberVisualLibraryPicker`, in-memory preview renderer и
канонические string IDs: нового owner/schema/кеша нет. В основном слое находятся
	поиск, фильтры owner, карточки, фиксированный details, `Поставить в сцену` и
	прямая команда `Редактировать шаблон`. Native-модель открывается тем же
	`workspace.open_surface`; legacy-модель сначала проходит существующий migration
	Undo, затем открывается как Godot Resource. Подсказка предупреждает, что это
	общая модель и изменения видны во всех экземплярах. Низкоуровневые
	`Открыть Godot Resource / Перенести в Godot` остаются в `Ещё…`.
При смене owner-фильтра карточки заново получают уже рассчитанные Texture2D из
session-кеша панели, поэтому `Все → Готовы в Godot → Все` не теряет миниатюры.
Plugin явно показывает фактическую цель размещения и обновляет её при смене
selection: +X от выбранного Node3D либо player_start/начало Map. Сам алгоритм
размещения, Undo и scene ownership не менялись. `test_voxel_object_library_layout.gd`
	закрывает компактную ширину/высоту, фильтры, metadata, обе прямые actions и отсутствие
модального PopupPanel; native capture — `user://voxel_object_library.png`.

Приняты два режима: Add заполняет только пустые целевые ячейки; Replace
переносит цвет и четыре материальных канала в занятые ячейки отпечатка, включая
очистку канала, отсутствующего у шаблона. Пустые ячейки шаблона не стирают цель.
Целевые groups остаются прежними; lock отклоняет затрагивающую его операцию.
Новые ячейки наследуют active merge part/Added, прежняя принадлежность заменённых
занятых ячеек не меняется. Вода/глобальный material/physics цели не переписываются.

Owners: `ember_voxel_stamp.gd` — capture через прежний FragmentExtract, чистый
plan и библиотека; `ember_voxel_stamp_preset.gd` — editor-only Resource с именем,
ссылкой на EmberVoxelModelResource, default anchor и опциональным editor-only
рецептом генератора. Геометрия сохраняется как
новый `content/voxel_models/vox_stamp_*.tres`, preset — в
`content/editor/voxel_stamps/*.tres`. Source tags меняются на stamp, группы и
merge provenance шаблона очищаются: они не переносятся на чужой объект. При
ошибке записи preset геометрия оставлена для восстановления, сцена не меняется.
Выделение/открытие/preview файлов не создают. Загрузка пресетов использует
CACHE_MODE_IGNORE_DEEP, чтобы видеть отредактированную внешнюю геометрию.

	`ember_voxel_stamp_panel.gd` — сохранить выделение, карточки/refresh, выбрать,
редактировать модель. Редактирование использует обычный workspace.open_surface
с прежним navigation save/discard guard. Уже поставленные отпечатки — копии
voxel data, а не ссылки на шаблон. Preset geometry не является вторым renderer.

Размещение расширяет существующий SelectionInteraction: та же геометрическая
привязка/стрелки, число vox, quarter turns, отражение по одной выбранной оси,
anchor = нижний угол / центр основания / центр объёма. ЛКМ выбирает adjacent
	для Add или hit для Replace; Enter — одно применение через SculptActions
	apply_fragment и немедленное перевооружение тем же пресетом. Первый Esc при
	готовом черновике отменяет только черновик, второй Esc без черновика возвращает
	последнюю кисть. Resource Undo/Redo без незавершённого черновика также сохраняет
	выбранный штамп; несовместимый source/scope change отменяет preview. Цветной
ghost показывает записываемые ячейки; shading preview условный (не полный remesh).
Ошибочный footprint красный. Кешированный plan применяется только при неизменном
source snapshot. Маска кисти не влияет на stamp plan: её snapshot и toggle
сохраняются, контур и действие приостанавливаются на время библиотеки/черновика и
восстанавливаются при возврате к совместимой кисти. Штамп не заменяет сохранённое
выделение своим результатом. Изоляция/скрытие групп явно несовместимы с этим
срезом; их включение во время размещения отменяет preview.

Пределы: 1–32768 occupied voxels, одинаковая плотность 16/32 и material dictionary.
Out-of-bounds/срез, palette overflow, lock и несовместимость — атомарный отказ,
без скрытого обрезания и изменения размера. Large synthetic 16384 occupied /
131072 target cells: plan ~60ms; это не замер полной отзывчивости на Причале.
Путь, линия, шаг, детерминированная россыпь, облегание рельефа, объёмное
вдавливание и 2D-паттерн с глубиной уже реализованы; впереди наборы из нескольких
независимых пресетов и resampling плотности. Gate: `test_voxel_workshop_layout`,
`test_voxel_selection_interaction`, `test_voxel_selection_mask`,
`test_voxel_stamp`, `test_voxel_pattern`, `test_voxel_generator` и
`test_voxel_tree_generator`, `test_voxel_bush_generator`,
`test_voxel_grass_generator` плюс связанные
sculpt/groups tests.
Native `-- --capture` пишет stamp/selection изображения в `user://`. Связанные
gates перечислены в MIGRATION_TEST_PLAN.

Первый generated-volume provider — `Камень`. Реестр
`ember_voxel_generator.gd` проверяет тип рецепта и маршрутизирует его в чистый
`ember_voxel_rock_generator.gd`; рецепт (`ember_voxel_generator_recipe.gd`)
содержит generator ID, seed и параметры. Provider строит детерминированный
эллипсоид с noise-неровностью и плоскими сколами, оставляет крупнейший связный
компонент и устойчивое нижнее пятно. Результат сразу является каноническим
`EmberVoxelModelResource` с tags `stamp/generated/rock`, поэтому placement,
palette/channel mapping, locks, preview и Undo не дублируются. Обновление рецепта
перезаписывает geometry того же preset только для будущих отпечатков.

Второй provider — `Дерево` (`ember_voxel_tree_generator.gd`). Он использует
общие bounded helpers `ember_voxel_generator_geometry.gd` для voxel-линий,
сфер и сохранения крупнейшего 6-связного компонента. Recipe хранит высоту,
толщину ствола, радиус/неровность кроны, ветвистость, trunk/foliage colors,
плотность и параметры набора форм. Provider сначала собирает перекрывающиеся
части кроны, затем связные ствол/ветви, гарантирует нижний контакт и возвращает
обычный `EmberVoxelModelResource` с palette из ствола и листвы и tags
`stamp/generated/tree`. Thumbnail для tree- и bush-tag использует боковую
проекцию; камни и прочие источники сохраняют вид сверху. Placement и cache совпадают с
камнем; отдельного forest owner нет. Максимальный gate из восьми деревьев
высотой до 32 vox занимает примерно 220 ms на тестовой машине.

Третий stamp-provider — `Куст` (`ember_voxel_bush_generator.gd`). Recipe хранит
высоту 4–24, радиус размаха, число стеблей, пышность/неровность листвы, два
цвета, плотность и параметры набора. Низкий центральный кластер и боковые
кластеры образуют широкую массу, а стебли прокладываются 6-связными voxel-шагами
к общему основанию до фильтра крупнейшего компонента. Результат имеет tags
`stamp/generated/bush`; bush-tag, как tree-tag, включает боковую миниатюру.
Save/edit/reopen/cache/placement/scatter остаются общими. Восемь максимальных
форм высотой до 24 vox строятся примерно за 190 ms на тестовой машине.

Четвёртый stamp-provider — `Трава` (`ember_voxel_grass_generator.gd`). Он строит
редкие двухцветные voxel-пучки высотой 2–12 с контролем размаха, числа травинок,
разброса высоты и наклона. Recipe рекомендует штатную `Россыпь`, root-level snap
и только верхнюю поверхность; column-conform скрыт, потому что он независимо
сдвигал бы колонки наклонной травинки. Все формы имеют явный нулевой
`collision_voxels`. Stamp-plan создаёт смешанный канал только когда target или
source его требуют: legacy occupied target становится physical=1, декоративная
трава остаётся 0, а legacy occupied stamp на explicit target получает 1. Undo
возвращает исходный пустой legacy-канал. Максимальный набор из восьми форм
строится примерно за 1 ms на тестовой машине.

Пятый provider в том же registry — `large_tree`, но его consumer не Stamp:
`ember_voxel_large_tree_generator.gd` возвращает обычный канонический
`EmberVoxelModelResource` высотой 64–256 vox. Он адаптирует MIT-идеи
`NGNT/treegen-pinegen` (атрибуция и лицензия в `docs/THIRD_PARTY_NOTICES.md`):
seeded ветвление, сужающиеся voxel-линии и кластеры листвы на концах ветвей.
Реализация Ember отдельная, sparse и ограниченная 4 194 304 ячейками хранения и
360 000 занятыми voxels. Высота выше 128 автоматически требует существующие
32 vox/block из-за предела восьми блоков по Y. Результат не имеет stamp-tag и
идёт через прежние Catalog, Prefab, Object Library, Map/Props и Canvas.

Создание теперь маршрутизируется в `ember_voxel_generation_panel.gd`: общая
нижняя мастерская native Godot editor и отдельная editor-only вкладка сцены
`addons/ember_import/editor/Генерация.tscn` (Environment/key/fill; не карта),
provider `creation_fields`/`creation_presets`/`editing_fields`
в прежнем registry. `ember_voxel_generation_session.gd` владеет editor-only
batch/candidate lifecycle, отдельного viewport/renderer нет. Точная geometry
строится один раз на вариант через прежний `prepare_recipe`; commit не
перебрасывает seed. До 4 simultaneous prepared previews (выше 128 vox до 2),
один полный candidate за editor frame; cancel между вариантами, не внутри
синхронного leaf builder. Batch замораживает параметры до начала, изменения
controls относятся к следующему проходу. `candidates` хранит историю ВСЕХ партий,
`preview_ids` — независимый working set до 4/2. Favorite не занимает 3D-лимит и
не уменьшает следующую партию. Каждый record имеет batch/number/seed и frozen
Recipe; UI фильтрует all/best/batch и создаёт до 40 строк на странице.
`unload_prepared_geometry` освобождает packed mesh и полные voxel arrays,
сохраняя identity metadata и существующий publication owner/file history.
Перед preview/save `ensure_loaded` восстанавливает unsaved из точного Recipe
с прежним model_id; published — из concrete source/prefab с IGNORE_DEEP cache,
не теряя поздние авторские правки. Identity-only resource не публикуется.
«Настроить» архивного открывает его одного; «3D» собирает сравнение разных партий,
«Последняя партия в 3D» возвращает последний working set с лимитом всех recipes
(включая individual reroll 64 → 256). История очищается только явным закрытием
набора/editor; persistence истории между запусками пока нет.
Временная mesh-only hierarchy owner=null, без physics/Script/processing;
centered pivot не меняет geometry и обеспечивает осмысленный native F center,
масштаб меняется колесом. Preview marker исключает temporary pivot из placement
anchor. Scene pack не включает previews. Scene switch приостанавливает session и
сохраняет candidates/dirty draft, возвращение открывает ту же native scene tab;
при потере studio nodes восстанавливается только `preview_candidates`, не вся
история. Непросматриваемые варианты остаются лёгкими recipe records.
Close collection подтверждает удаление unsaved, закрытие editor освобождает всё;
session не является persistent asset. Номера монотонны внутри session независимо
от family, Label3D совпадает со списком; selected number выделен, есть solo.

Расширение типов деревьев (2026-09-12) остаётся внутри прежнего LargeTreeProvider.
Defaults и missing keys сохраняют v2 «Саванну» (v1 без generation_version остаётся
classic). Explicit `tree_type` 1/2/3 либо `branch_direction` >0 нормализуются в v3:
стилизованные дуб/берёза/клён и направление auto/up/lateral/down. Типы меняют
trunk/branch envelope, уровни ветвления, taper reach и объём масс кроны, не только
palette. «Саванна» использует прежние формулы с тем же seed; golden voxel hashes
до расширения проверены на 64/128/256 для v1/v2. В старый Resource новых полей
не добавлено: authoring параметры остаются Recipe.parameters.
Структура сохраняет version=1, допускает параметры generator v2/v3. У новых
типов дополнительные foliage groups имеют optional bool `along`; их anchors/RNG
state фиксированы даже при 0% заполнения. `foliage_along` масштабирует только
эти группы при build_on_structure; wood/collision coordinates не меняются.
Тип/направление создают новый skeleton только при new generation/explicit reroll,
не являются editing fields готового каркаса. Общие fields/presets содержат 4
type profiles и прежние 3 базы; descriptor `identity` даёт readable summary
для истории через `creation_description`, без tree-specific routing в UI.
Общая workshop панель пересобирает candidate controls по набору descriptor keys
при смене возможностей выбранного Recipe, не только при `_ready`; новый optional
field появляется при переходе Savanna → Oak и исчезает при обратном переходе.
`_canopy_flatten` — одна математика профиля для fresh/frozen build. Тип не отключает
управление flatten: новые круглые массы сохраняют регулируемую приплюснутость.
Native isolated сравнение 4 типов и typed editing/publication/reopen PASS;
художественная оценка пользователя остаётся открытой. Default leaf build 128 vox
для дуба/клёна примерно 0.45–0.5 s (не включает prefab meshing); frame queue
ограничивает batch, но не прерывает synchronous leaf builder посреди дерева.

Полировка дуба v4 (2026-09-12) не заменяет старые алгоритмы. Новый preset
«Тип · Дуб» и явный выбор дуба в настройках новой партии задают v4; загрузка
сохранённого Recipe оставляет v1/v2/v3. Normalization разрешает v4 только для
tree_type=1, остальные типы остаются v3. Build dispatch остаётся в единственном
LargeTreeProvider. Вместо высокой центральной оси — низкая развилка и несколько
изогнутых taper boughs с продолжениями/вторичными ветвями. Неравные перекрывающиеся
ellipsoid groups вокруг сучьев и между ними формируют широкую связную крону,
а не вертикальные уровни одинаковых шаров. Прежние branch/crown/season fields
сохранены; новый редактор веток и новые UI owners не добавлялись.
Frozen structure остаётся version=1, для v4 хранит quarter-voxel anchors,
положительные finite Vector3 `radii`, bool `along` и стабильный `noise_radius`.
Validation проверяет новую metadata; fresh/frozen используют один foliage helper
и один noise profile. Quarter quantization сохраняет exact Resource text
roundtrip без дрейфа геометрии. Foliage amount/along/season не меняют support lines;
fresh bare v4 разрешён. Общие Recipe draft/Apply/Undo и library publisher прежние.
Только oak union пропускает existing leaf cells и точки за максимальным contour:
golden voxel hashes до/после ускорения совпадают, старые calls не меняют поведение.
`test_voxel_oak_crown.gd` проверяет 3 seed, 64/96/128/256, v3 golden parity,
new v4 geometry parity, bounded/maximal build, exact Recipe save/reopen,
bare/season, invalid radii, workshop Apply и file publication Undo/Redo.
Oak/types tests и 6 related suites PASS. 128 vox leaf примерно 0.86–0.95 s,
meshing отдельно; batch queue не делает synchronous builder прерываемым.
Native fixture `-- --oak-crown-only` сравнивает old/new/bare/other seed в обычном
Forward+ viewport и проверяет individual Apply/Undo/Redo, publication/reopen.
Финальный native прогон PASS; capture с четырьмя сравниваемыми объектами просмотрен.
Пользователь принял силуэт дуба; voxel parity сама по себе эту оценку не заменяет.

Берёза v5 (2026-09-12) — следующий профиль в том же leaf provider. Новый preset
и явный выбор берёзы в новой партии opt-in v5; saved v3 birch не обновляется.
v4 остаётся дубом, v5 только tree_type=2; переход к другой породе нормализуется
в её совместимый алгоритм. Ствол — непрерывная slender polyline до 98% высоты,
ветви распределены спирально с taper envelope к вершине, внешние twigs поникают.
Небольшие верхние lateral shoots исключают голый верхний столб без stack шаров.
Листва — вытянутые volumes вдоль поникающих опор, с просветами; individual leaf
geometry не добавлена и запланирована после прохода по силуэтам presets.
Общие `_support_point`, `_record_crown_volume`, `_volume_noise`,
`_paint_crown_volumes` обслуживают oak/birch. Это переименование/переиспользование
математики v4, не новый owner/Resource/schema/renderer. Frozen version=1 metadata
та же: anchors/radii/along/noise_radius; unused oak marker больше не нужен,
старые структуры с ним по-прежнему читаются. Bare/season/crown filling сохраняют
wood/collision, branch thickness/taper меняют радиусы, не support coordinates.
Скелет до 123 lines/58 groups, прежние source storage/occupancy limits.
`test_voxel_birch_shape.gd` проверяет 3 seed × 64/96/128/256, descending twigs,
continuous leader, exact fresh/frozen collision и Recipe text roundtrip,
extreme settings, season/thickness support stability, draft discard,
individual Apply Undo/Redo и common publication Undo/Redo/reopen в `user://`.
Targeted PASS; oak golden parity и 6 related suites PASS. Leaf 128 vox около
60 ms, meshing не включён. Native fixture использует тот же comparison helper
с `-- --birch-shape-only` и capture `generation_birch_shape_native.png`.
Финальный native comparison/Apply/Undo/Redo/publication/reopen PASS, capture
просмотрен. Shared UI type choice/Undo/Redo regression PASS.
Силуэт берёзы принят пользователем; пользователь согласовал сначала формы
остальных presets, затем отдельный проход по листве. Branch editor/shaders позже.

Общий рисунок коры (2026-09-12): `ember_voxel_bark_pattern.gd` — чистый leaf,
не renderer/Resource/новый generator owner. Recipe.parameters: `bark_pattern`
(missing=false), `bark_pattern_direction` 0/1/2 (поперёк/вдоль/наклонно),
`bark_pattern_color`, `bark_pattern_length` 2–24 vox, `bark_pattern_density` 0–100.
Preset берёзы включает cross/5/70/тёмный цвет, дуба longitudinal/14/65/коричневый;
остальные породы могут использовать тот же блок. Старые Recipe без ключей
воспроизводятся без рисунка, алгоритмы/skeleton versions не обновляются.
Builder передаёт деревянные supports в общий `_emit`; classic сохраняет только
временные lines для проекции рисунка, не приобретает frozen editing capability.
Marks вычисляются только на exposed wood, поиск nearest tapered support через
8-voxel spatial buckets; локальные longitudinal/circumferential координаты,
неровные прерывистые tile strokes с детерминированной длиной/плотностью, без RNG
генерации. Edited thickness/taper передают effective radii, исходные опоры
структуры неизменны. Frame coordinates/radii quantized; canonical positive zero
для atan2 устраняет смену стороны seam после text serialization (-0 → +0).
Palette[0..6] прежняя, pattern colour добавляется как [7] только при marks;
voxel occupancy, leaf coordinates/palette и collision не меняются. Toggle off
возвращает точную прежнюю окраску. Схема gameplay Source не расширяется.
Descriptors общие для creation/editing; generic bool CheckButton и enum
OptionButton поддержаны в workshop/contextual panel, Undo/Redo/discard sync
без remesh на мелком input. Heavy projection/meshing — explicit Apply/preview.
`test_voxel_bark_pattern.gd`: rotation covariance на цилиндре (следование
ветви, не world Y), interior skip, broken strokes/direction/length/determinism,
zero/off, every species occupancy/collision/skeleton invariance, custom palette,
exact off colours, common creation bool Undo/Redo, contextual bool/enum/discard.
Targeted PASS; oak/birch/types roundtrip/publication и 6 related suites PASS.
Native `-- --bark-pattern-only` показывает cross birch/longitudinal oak/custom
slanted birch/plain oak, проверяет bool/enum/colour/length Apply/Undo и publication
reopen. PASS, capture `generation_bark_pattern_native.png` просмотрен.
Художественная приёмка рисунка открыта. Volume grooves/material shaders позже.

Полировка распределения коры v2 (2026-09-12): скрытый editor Recipe parameter
`bark_pattern_version` отделён от geometry/skeleton revision. Missing=1 точно
сохраняет прежний `_stroke`; новые defaults/presets=2. В том же leaf v2 размещает
независимые штрихи с jitter по высоте и окружности, переменной длиной и margins
между отметинами, без общих центров горизонтальных поясов. Cross/slanted length
ограничена максимумом 20% окружности effective support radius (минимум 1 vox);
longitudinal length остаётся пользовательской. Seed воспроизводим, RNG каркаса
не затронут. Нет новых ручных knobs, gameplay schema/mesher/publisher прежние.
Явное включение toggle в creation/candidate/Canvas выбирает v2; для уже
включённого v1 пользователь делает off/on, затем Apply/preview. Изменение версии
входит в тот же Undo action; обычная загрузка/правка цвета v1 его не обновляет.
Дополнительные bark gates: missing/explicit v1 exact parity, v2 rotation
covariance и отсутствие плотных поперечных колец на тонкой опоре при density100
для seed17/371/391; creation/contextual upgrade Undo возвращает v1.
Text Recipe save/reopen воспроизводит точные voxel colour bytes для v1 и v2.
Bark/oak/birch/types, generator editing/session и общий generator PASS.
Native disposable `-- --bark-pattern-only --scattered-bark`: №1 v1 birch391,
№2 v2 birch391, №3 v2 birch17, №4 v2 oak371; индивидуальный Apply/Undo/Redo,
publication/reopen PASS. Художественная приёмка v2 остаётся открытой.
Native gallery `generation_bark_scattered_native.png` и крупные планы
`generation_bark_detail_1/2/3.png` просмотрены: v2 даёт более редкие раздельные
отметины вместо регулярных тёмных поясов. Эти captures не заменяют оценку
пользователем; fixture временно центрирует только preview node и возвращает
его позицию до publication, Source/Recipe от этого не меняются.
Пользователь принял распределение коры v2 («да это лучше»).

Клён v6 (2026-09-12): `_build_maple` в прежнем large_tree provider использует
общие quarter anchors, tapered lines, frozen crown volumes и `_volume_noise`/
`_paint_crown_volumes`. Стройный trunk/leader, восходящие раскрывающиеся веером
опоры с боковыми ответвлениями; перекрывающиеся неравные массы кроны вокруг
развилок и внутри, округлый верх без отдельной цепочки шаров. Корни умеренные.
Новый «Тип · Клён»/явный выбор maple → generation_version6; saved v3 остаётся3.
Source/Recipe/structure version1/registry/session/publisher owners прежние.
Validation принимает v6 только с tree_type3 и корректным frozen noise profile;
geometry revision не меняется при правке листвы/сезона/толщины существующего
каркаса. Старые `_build_sculpted`/oak/birch paths не менялись. Direction override
и вытянутый/ярусный silhouette остаются доступны через прежние descriptors.
`test_voxel_maple_shape.gd`: 3 seed × 64/96/128/256, ascending/lateral supports,
bounded/validated Source/structure, exact fresh/frozen/text roundtrip/collision,
bare/season/thickness support invariance, extreme envelope, direction/tiered,
native type choice Undo/Redo, draft discard/Apply/publication Undo/Redo/reopen.
Targeted PASS; types/birch/bark PASS. Leaf build128 около0.58–0.64s, meshing
отдельно; height256 ограничен прежним storage envelope.
Native disposable `-- --maple-shape-only`: №1 saved-style v3, №2 v6 seed391,
№3 тот же v6 bare, №4 v6 seed17. Individual Apply/Undo/Redo/publication/reopen
PASS, `generation_maple_shape_native.png` просмотрен. Oak/birch/types/bark и
generator editing/session regressions PASS. Ручная приёмка формы
клёна пользователем открыта, детализация листвы — отдельный следующий проход.
Тип «Ель» добавлен пользователем в план; хвойный профиль в прежнем registry,
не реализован этим контрактом. Отдельная система генерации не требуется.

Клён v7, повторная полировка по фото пользователя (2026-09-12): v6 не принят —
крона слишком плоская/чашеобразная. `_build_maple_upright` в том же provider
создаёт продолжающийся leader и боковые опоры на пяти высотах, максимальный
размах в средней части, уменьшающийся к округлой верхушке. Крупные массы на
концах/внутри ветвей и core volumes связывают соседние высоты, не один общий
веер и не отдельные тарелки на столбе. Общие tapered lines/quarter anchors/
crown volumes/noise/projection сохранены; без новой схемы, renderer или knobs.
Новые preset/явный выбор maple → v7. `_build_maple` v6 остаётся неизменным;
validation принимает v6/v7 для tree_type3 с прежним frozen noise profile.
Golden v6 seed371 на64/128/256 сняты перед доработкой: 3008355434/2969065940/
970442213, включены в targeted regression. Frozen editing не двигает опоры.
Тест дополнен five-level/middle-versus-top reach и реальной высотой листвы/
отсутствием полностью пустых горизонтальных рядов внутри кроны. Ограничение
vertical crown radius — максимум10% высоты для сохранения occupied budget
при максимальных параметрах; прежние storage/structure limits не повышаются.
Художественная приёмка v7 открыта. Следующий согласованный шаг после проверки
клёна — повторный проход дуба; не менять его этим контрактом. Ель остаётся в плане.
Финальный maple targeted PASS, включая maximum occupied/storage envelope и
отсутствие пустых горизонтальных рядов в реальной листве для12samples.
Leaf128 примерно0.80–0.94s, meshing отдельно. Oak/birch/types/bark и common
generator editing/session regressions PASS. Native disposable
`-- --maple-shape-only` сравнивает №1 v6/№2 v7/№3 v7 bare/№4 v7 seed17;
Apply/Undo/Redo/publication/reopen PASS. Capture `generation_maple_upright_native.png`
и `generation_maple_front.png`/`generation_maple_side.png` просмотрены.
Front/right selected через настоящий native camera PopupMenu, включая engine
internal children; numpad-only input не переключал вид в fixture и не принят
как свидетельство. Финальные captures показывают передний/правый ортогональный
вид, не одинаковую перспективу. Preview node временно центрируется только для
проверки вида и возвращается в исходную позицию до publication. Художественную
узнаваемость клёна подтверждает пользователь, не эти автоматические критерии.

Клён v7 принят пользователем («да, похоже на клён»).

Дуб v8 по фото взрослого раскидистого дерева (2026-09-12): новый preset и
явный выбор дуба opt-in v8, `_build_oak` v4 не менялся. Normalization не
обновляет старый Recipe; validation принимает8 только дляtree_type1,
прежний frozen structure1 сохраняет quarter anchors, taper lines, groups,
noise, grid и pivot. `_build_oak_mature` в прежнем LargeTreeProvider создаёт
5сегментов искривлённого массивного ствола до60% высоты, collar и короткие
толстые buttresses;5–7 основных сучьев начинаются на разных высотах22–56%.
Сучья состоят из3сегментов с боковыми изгибами, нижние длиннее верхних,
3двухсегментные вторичные ветви на каждом и3 восходящих верхних развилки.
Более мелкие crown volumes на разных высотах и внутренние along volumes
связывают крону, не закрывая все нижние развилки. Preset width14/spread78/
curve70/cluster115, существующие параметры направления/формы/листвы/толщины/
коры переиспользованы. Shared bark/paint/emitter и saved v1–v7 unchanged.
Leaf vertical radius capped10.5% высоты; reach ограничен прежним storage budget.

Oak targeted PASS:12samples64–256, saved v3/v4 golden parity, staggered origins,
lower reach, deep real foliage/collar, extreme/directions/tiered, exact fresh/
frozen/text geometry+collision, bare/season/thickness support stability,
UI type choice Undo/Redo, discard/Apply/publication Undo/Redo/reopen v8.
Leaf128 примерно0.56–0.60s, meshing отдельно. Maple/birch/types/bark и common
editing/session regressions PASS. Native disposable Forward+ v4/v8/bare/seed17,
Apply/Undo/Redo/publication/reopen PASS; gallery/front/right captures просмотрены.
Native `generation_oak_mature_front.png`/`generation_oak_mature_side.png` —
настоящие передний/правый ортогональные виды, preview position возвращается
перед публикацией. Пользователь принял форму дуба v8; leaf microdetail и
branch editor позже. Новых schema/panel/renderer/ручных knobs нет.

Саванна v9 (2026-09-12), согласованный зонтичный профиль после принятия дуба:
`_build_savanna_umbrella` в прежнем LargeTreeProvider, opt-in новый preset/
явный выбор type0; defaults v2 и saved v2/v3 не обновляются при load.
Validation принимает9 только сtype0, общий frozen structure1/quarter anchors/
crown volumes/noise/bark/paint/emitter/Source/Recipe/workshop/publisher сохранён.
Изогнутый4-сегментный ствол до30–55% высоты,3–4 раскрывающихся основных
стволика с3сегментами, по3 вторичные развилки и тонкие концевые ответвления.
Без центрального верхнего pole. Широкие shallow volumes перекрываются;
внутренние немного выше внешних, перепады зависят от bounded reach, иначе
при256vox/storage cap крона становилась слишком глубокой. Vertical radius
capped7.5% высоты, storage/occupied/structure limits прежние. Preset width8/
spread80/thickness60/taper80/curve80/flatten65/cluster115/root25.
Общий foliage_along descriptor виден в creation/editing v9; старый v2 скрыт
как прежде. Saved structure и правки листвы/толщины продолжают общую систему.

Savanna targeted PASS:12samples64–256, saved v2 golden parity, no pole,
shallow/wide real foliage, bounded max settings/directions, exact fresh/frozen
geometry+collision/text roundtrip, bare/season/thickness, descriptor/UI choice/
discard/Apply/publication Undo/Redo/reopen9. Leaf128 примерно0.17–0.19s,
meshing отдельно. Oak/maple/birch/types/bark и common editing/session PASS.
Форма саванны принята пользователем. Новая очередь: ель, затем обсуждение
общей системы листьев/хвои, не автоматическая реализация микродеталей.
Native disposable Forward+ `-- --savanna-shape-only` v2/v9/bare/seed17,
индивидуальные Apply/Undo/Redo/publication/reopen PASS; gallery и настоящие
передний/правый ортогональные captures `generation_savanna_front.png`/
`generation_savanna_side.png` просмотрены. Старый sample Recipe fixture
нормализуется до установки controls, что устранило bool(null) script error;
финальный лог без script errors. Copied fan_town UID warnings не менялись.

Ель v10 (2026-09-13): `_build_spruce` в прежнем LargeTreeProvider, type4,
новый preset «Тип · Ель». Непрерывный восьмисегментный тонкий leader,
девять вращаемых ярусов по3–4 основные ветви, каждая из двух сегментов
и одной боковой веточки. Нижние ветви длинные/слегка провисающие, верхние
короткие/восходящие; вытянутые веточные volumes и тонкие перекрывающиеся
внутренние masses покрывают leader. Это не solid cone и не отдельные иголки.
Формат frozen structure1/quarter anchors и common paint/bark/emitter прежние.
Max120 lines/118 groups, storage/occupied caps сохранены; foliage/thickness
редактируются через существующие descriptors без движения опор.
`LATEST_VERSIONS=[9,8,5,7,10]` — общая таблица provider для явного выбора
одного из пяти типов. New panel open без Recipe использует preset саванны9;
public default_recipe остаётся v2 для совместимости. Loaded recipes сохраняют
версию, выбранный тип помечается «прежняя форма»; reselect явно обновляет
профиль с Undo. Preset/loaded params не заменяются автоматически.
Targeted spruce проверяет64/96/128/256×3seeds, сужение ярусов/leader, >90%
leaf row coverage в основной кроне, bounded maximal/directions, validation,
fresh/frozen/text exact, bare/season/thickness, choice/draft/Apply/publication
Undo/Redo/reopen10. Native fixture `-- --spruce-shape-only` сравнивает три seeds
и голый каркас; captures спереди/справа оцениваются отдельно от assertions.
Первый слишком редкий native вариант исправлен перекрытием внутренних объёмов;
Пользователь проверил и принял форму ели («Мне нравится, проверил»).
Финальный spruce targeted PASS,11related suites PASS (savanna/oak/birch/maple/
types/bark/editing/session/generator/large tree dialog/object). Session test
теперь проверяет Undo к исходным настройкам актуального пресета, не hardcoded
v2/thickness75. Leaf128 около0.22–0.23s, meshing отдельно.
Native isolated Forward+ gallery/bare/individual Apply/Undo/Redo/publication/
reopen10 PASS, финальные `generation_spruce_front.png`/`generation_spruce_side.png`/
`generation_spruce_native.png` просмотрены. Лог без script errors; copied UID
warnings и scan-abort warning при штатном quit не исправлялись этим срезом.
Следующий шаг — обсуждение общей системы листьев/хвои, затем отдельный контракт.

Pixel-art foliage prototype2026-09-13 (дуб v8; визуальная приёмка открыта):
`ember_voxel_foliage_pattern.gd` — чистый leaf-модуль dressing существующих crown
volumes, не новый provider/renderer/scaffold. `foliage_style=0/1` (missing=0),
`foliage_detail=0..100` (missing=55) нормализуются LargeTreeProvider и сохраняются
в прежней Recipe.parameters. Capability пока только tree_type1/version8;
прочие породы игнорируют стиль и не получают controls, прежний oak preset остаётся0.
Связное ядро и12–28 неодинаковых перекрывающихся lobes с детерминированным seed
обслуживают shared `_paint_crown_volumes` fresh/frozen path. Detail задаёт размер/
число групп и грубый согласованный край, amount плавно уменьшает объёмы, не
выбрасывает случайные целые исходные supports. Пятна используют существующие
palette4–6 по группам; старые boolean leaves оставляют прежний noise-emitter exact.
Frozen structure1/quarter supports не меняются, кора/collision прежние.
Creation и individual/contextual editing используют registry descriptors;
detail появляется только при style1. Сохранённые presets сохраняют оба поля,
не хранят каркас. Шейдер, индивидуальные листья/иголки и ветер не добавлялись.
Contextual GeneratorPanel теперь сравнивает ключи descriptors при изменении
черновика и пересобирает только набор controls при смене capability/style.
Controls сначала отсоединяются, затем queue_free после завершения input signal;
это общий lifecycle для зависимых полей, не специальная ветка UI только для дуба.
Undo/Redo/Discard также восстанавливают нужный набор полей без remesh.
`test_voxel_foliage_pattern.gd` проверяет64/96/128/256×seeds17/391, missing/old
parity, validation/scaffold/wood/collision stability, fresh/frozen/text exact,
amount/detail/season, isolated voxel check, preset roundtrip и creation Undo/Redo.
Native fixture `-- --oak-foliage-only` сравнивает old/new/detail90 на одном
каркасе seed391 и seed17; individual Apply/Discard/Undo/Redo, publication/
Undo/Redo/reopen. Captures `generation_oak_foliage_native.png`, `_front.png`,
`_side.png`, `_old_front.png`; оценка пользователя нужна отдельно от assertions.
Foliage targeted и7related suites (oak/types/bark/editing/session/large-tree-object/
generator) PASS; native Forward+ PASS, лог без script errors. Сохранены прежние
copied UID warnings и scan-abort при quit. Fresh foliage64–256 около0.21–0.67s,
meshing не входит в это измерение. Скриншоты подтверждают более крупные цветовые
пятна; направление первого dressing ещё не принято пользователем. Дополнительные
`generation_oak_foliage_preview.png`/`_old_preview.png` — прямой снимок 3D viewport,
не AI-рендер/монтаж; light/shader существующие, art polishing остаётся открытым.

Surface pattern revision2 (2026-09-13, после замечания о нечитаемом паттерне):
тот же FoliagePattern, без второго provider/renderer. `foliage_pattern_version`
нормализуется1..2: new defaults2, missing1 сохраняет первый prototype. Явный
выбор/reselect «Пиксель-арт» обновляет только pattern revision с Undo в creation,
individual и contextual panels. `foliage_pattern_strength=0..100` (default65)
сохраняется в прежней Recipe и presets; field виден только в актуальном pixel
oak/revision2. Рецепты других пород и прежний style0 не меняются.
Revision2 фиксирует геометрию dressing на прежней Detail55 для новых деревьев;
скрытый `foliage_geometry_detail` хранит эту часть identity (default55). При
явном обновлении уже настроенного pixel v1 он захватывает текущую Detail, чтобы
не сбросить принятую custom крону. Это Recipe metadata, не новый ручной control.
Пользовательская
Detail теперь задаёт размер узора3–9vox. `_emit` вызывает pure `colorize` после
всего union: exposed cells определяются по membership leaves/wood, оттенок4/5/6
вычисляется из целочисленной 3D lattice, seed и смещённого ступенчатого ромбового
мотива. Ориентация/размер motifs варьируются по tiles, итог не зависит от порядка
групп/Dictionary. Воксели не добавляются/удаляются, wood/collision не трогаются.
Strength смешивает только leaf palette4/6 с базовой5:0 скрывает рисунок,100 даёт
полный контраст. Никаких дополнительных palette indices, baked sunlight или
shader. Цвет сезона меняет palette, не координаты рисунка.
Targeted дополнен reversed insertion order, оттенками поверхности, missing/1
parity, strength0/20/65/100 palette-only, Detail occupancy/collision invariance,
upgrade/reselect Undo и динамическими contextual fields. Native
`-- --foliage-surface-only` сравнивает strengths20/65/100 на одном seed391/
каркасе, четвёртый — Detail85. Individual strength Apply/Undo/Redo, Discard,
publication/reopen/contextual lifecycle проверяются прежней fixture.
Surface targeted и4related suites (oak/bark/editing/session) PASS; native
Forward+ strengths20/65/100 и Detail85, palette-only Apply/Undo/Redo, publication/
reopen/contextual fields PASS, лог без script errors. Captures показывают
заметный средний/сильный узор, art acceptance остаётся открытым. Fresh64–256
около0.23–0.72s, meshing отдельно; native screenshot не меняет shader/light.

Structural variation (2026-09-13, после leaf trials): пользователь отметил
слишком похожие каркасы и предпочёл pixel-art. Read-only audit6 seeds показал
одинаковые70 segments/6 высот главных сучьев oak8 и90 segments/5 уровней maple7.
Передача seed/new batch работает; причина — жёсткая схема пород, не foliage.
Новые oak11/maple12 продолжают те же mature/upright builders с version guards;
legacy RNG/геометрия8/7 не изменены. Единственный pure plan owner —
`ember_voxel_tree_variation.gd`: собственный deterministic RNG независимо от
leaf RNG/общего поворота, ограниченные count/level/height/length/radius/bend/
rise/twig/upper-fork и согласованная направленная асимметрия. Species builders
сохраняют envelope, quarter anchors, rasterization, collision и storage budgets.
Oak main4–8, twig1–4, upper1–3; maple levels4–6, переменное количество сучьев
на уровне, twig1–2, max24 main. Frozen format1 и максимум128 lines/groups прежние.
`structure_diversity`0–100 (default65) принадлежит Recipe.parameters и presets,
виден только в creation11/12.0 использует точную старую geometry8/7. Он не
является dressing field замороженного объекта; смена каркаса — прежняя явная
команда с Undo/Redo. Registry/type choices→11/12, advanced compatibility choices
дополнены, normalization/structure validation знают версии. Saved8/7 не обновляются.
FoliagePattern поддерживает oak8/11 без изменения алгоритма/цветов; maple foliage
прежняя. Другие породы и будущие character/age/multistem profiles вне среза.
`test_voxel_tree_variation.gd`:6 seeds ×64/128/256, yaw-invariant heights/lengths/
connectivity fingerprint и разные counts, validation/fresh-frozen/text, diversity0
legacy parity, frozen immunity, extreme3seeds/directions, presets/UI Undo/Redo.
Исторические oak/maple/foliage suites явно продолжают8/7/8 geometry gates;
проверки type UI/publication соответствуют актуальным11/12. Native fixture
`-- --tree-variation-only` (+`--maple-shape-only`) сравнивает bare17/371/391
и dressing17, выравнивая первый trunk segment по X только для представления.
Individual Apply/Discard/Undo/Redo/publication/reopen и явная skeleton regeneration
через кнопку/Undo/Redo проверяются в disposable copy. Визуальная приёмка открыта.
Variation targeted и7related suites oak/maple/types/bark/foliage/editing/session
PASS. Native oak/maple Forward+ PASS, включая явную замену каркаса/Undo/Redo;
логи без script errors, copied UID warnings/scan-abort оставлены прежними.
Шесть default seeds дают oak53–71 segments вместо постоянных70, maple55–83
вместо90. Это наблюдение для протестированной партии, не общий min/max алгоритма.
Captures `generation_oak_variation_native/front/side/preview.png` и maple аналог
просмотрены; пользователь принял разнообразие дуба/клёна.

Продолжение2026-09-13: TreeVariation поддерживает также birch13/savanna14/
spruce15 через общий slender plan; oak11/maple12 RNG stream не менялся.
Birch main7–14, twig1–3, поникающие тонкие побеги и непрерывный leader;
savanna main3–5, twig1–4/fan, неравномерные места развилок и плоский ceiling;
spruce levels7–10, max36 main, twig0–1, разная длина/высоты ветвей вокруг leader.
Предел128 lines/groups, quarter anchors, physical wood и общий rasterizer прежние.
Creation presets/type reselect→14/11/13/12/15; совместимость знает13–15.
Saved5/9/10 не обновляются; diversity0 воспроизводит5/9/10 exact geometry.
Frozen editing не заменяет topology: только явная regeneration с Undo/Redo.
Shared descriptor показывает один diversity knob для11–15 и foliage_along
для новой savanna14; oak-only foliage trials не перенесены на другие породы.
Targeted variation расширен на все5 пород, включая limits/fresh-frozen/text/
legacy parity/UI/presets. Historical birch/savanna/spruce gates явно используют
5/9/10, новые UI checks —13/14/15. Native fixture выбирает revision из type preset
и имеет отдельные species captures. Художественная приёмка новых трёх открыта.

Variation и10 related suites PASS. Native birch/savanna/spruce Forward+ PASS,
включая explicit regeneration/Undo/Redo, Apply/Discard/publication/reopen.
Bare/dressed comparison captures просмотрены; birch final fixture также даёт
front/side/preview. В тестовой партии6seeds: birch85–105 segments (было107),
savanna41–77 (56), spruce85–105 (120); oak/maple counts прежние для11/12.

Oak composition16 (2026-09-13, screenshots №29–31): latest type versions теперь
14/16/13/12/15. Старые8/11 не меняются; normalize/type validation/frozen source
знают16. Pure TreeVariation.oak_composition использует отдельный seed stream,
не меняя прежний plan11/12/13/14/15. Diversity>0: главные ветви образуют2–4
неравномерных fan направления на переменных высотах, end heights независимы
от ascending index. Trunk height/lean и leader reach/height меняются по seed.
Два tapering continuations и их реальные side twigs продолжают trunk tip;
inner masses принадлежат их supports. Не добавляются filler sphere, второй
skeleton owner или renderer. Diversity0 exact8 geometry; old11 RNG untouched.
FoliagePattern capabilities включают16, pixel-art/colorize math неизменны.
Новый type preset и explicit same-type reselect выбирают16 с Undo; frozen editing
сохраняет base generation version и topology. Regenerate candidate использует
только batch recipe через прежний history/Apply/publication путь.
Targeted variation дополнен6 seeds на reported96/trunk8/spread80/diversity100/
pixel/detail55/contrast25/along85: два physical leaders с taper, вариативные
fork heights и trunk tops, поддержанная центральная листва, same bare structure.
Общие gates all5species/heights64/128/256/limits/directions/presets/text/history
сохранены. Native fixture --tree-variation-only --composition-dressed сравнивает
три pixel дуба17/371/391 и bare17, actual Forward+; individual editing/history,
explicit regeneration/Undo/Redo, publication/reopen. Variation и8related suites
oak/types/bark/editing/large-tree/generator/foliage/session PASS; native clean
Forward+ PASS без script/engine errors, captures просмотрены, diff --check чистый.
Art gate открыт, старые общие migration gates не менялись.

Oak lateral17 (2026-09-13): пользователь подтвердил рандомность16, но крона
слишком тянулась вверх без боковых побегов. Latest type versions14/17/13/12/15;
compatibility enum/normalize/validation/frozen/FoliagePattern знают17. Сохранённые
8/11/16 не обновляются; diversity0 exact8. TreeVariation.oak_laterals — отдельный
pure seed stream:1–3 shoots/limb по branchiness0/62/100; diversity влияет на
anchor/turn/length/rise. New secondary replaces historical upward twigs; прежние
RNG draws всё равно потребляются, поэтому main limbs/trunk/leaders exact16.
Secondary roots лежат на knee→elbow основных сучьев, стороны чередуются, рост
преимущественно наружу/слегка вверх. Two tapering segments +fork/leaf volumes
несут боковые плечи и нижний край кроны; lower trunk не получает filler foliage.
Existing branch_direction override учитывается; physical lines и frozen supports
используют прежний owner. Max8limbs×3shoots×3segments +main/trunk/leaders <=114
segments; groups<=104. Pixel-art paint/colorize math unchanged. Type preset и
explicit reselect выбирают17; existing regenerate/history/preset/publication
путь прежний. No new controls/schema/renderer.
Variation targeted дополнен6reported seeds: bounded count по branchiness,
exact16 primary lines, sideways physical branches, anchors на parent segment,
distinct secondary layouts, frozen16 даже сparameters17 остаётся exact16.
All5species64/128/256/extremes/directions/fresh-frozen/text/history сохранены.
Native --tree-variation-only --composition-dressed теперь использует latest17:
3pixel seeds17/371/391 и bare17, individual edit/regeneration/Undo/Redo/
Discard/publication/reopen; captures generation_oak_variation_*.png просмотрены.
Variation и8related oak/types/bark/editing/large-tree/generator/foliage/session
PASS; native Forward+ PASS без script/engine errors; diff --check чистый.
Art gate открыт; старые migration gates не менялись.

Trial leaf shoots (2026-09-13): пользователь сохранил pixel1 как эксперимент
и согласовал отдельный style2 в прежнем oak8 dressing. Normalization сохраняет
old default0; `foliage_leaf_size=3..12` (default5) — единственный новый ручной
параметр. Common descriptors показывают его только для style2, pixel detail/
strength скрываются; Recipe/preset/публикация остаются прежними owners.
`FoliagePattern.paint_shoots` использует quarter crown supports, ближайшую wood
клетку и seed. Внутреннее ядро0.36 радиуса соединяется с древесиной зелёным
черешком;6–24 направленных побега несут по4 неодинаковых тонких ромбовых листа.
Воксельная пластинка имеет приподнятую жилку/согнутые края и опущенный кончик;
цвет согласован внутри побега, palette4/5/6 без новых индексов. Черешки являются
leaf dressing, не новым физическим scaffold. Высота/occupied/storage прежние
ограниченные; unsupported species оставляют прежнюю листву. Нет alpha/второго
renderer, shaders или нового формата каркаса. Pixel surface colorize не трогает2.
Targeted foliage проверяет64/96/128/256, exact wood/collision/scaffold,
fresh/frozen/text equality, размеры3/8/12, amount0, сезон palette-only и создание
style Undo/Redo. Native disposable `-- --leaf-shoots-only` сравнивает old0,
shoots5/8 на seed391 и shoots5 seed17, индивидуальные size Apply/Discard/Undo/
Redo, publication/reopen и contextual dynamic fields/Undo/Discard. Артефакты
`generation_leaf_shoots_native/front/side/preview/detail.png`; detail — реальный
увеличенный 3D viewport, не mockup. Визуальная приёмка остаётся отдельным gate.
Foliage targeted и4related oak/bark/editing/session PASS, disposable native
size Apply/Discard/Undo/Redo/publication/reopen/contextual PASS, script errors
не обнаружены. Geometry64–256 около0.28–0.87s, без meshing. Native96/seed391
old0:182_680 vertices/91_340 triangles; shoots2:348_560/174_280 (~1.9× triangles),
occupied125_212→75_250. Тонкие пластины открывают больше граней; не объявлять
trial лесным perf gate. Финальная оптимизация renderer/mesh остаётся отложенной.

Trial leaf clouds (2026-09-13, после трёх reference images): отдельный style3
для oak8/11, не замена pixel1/shoots2. Тот же FoliagePattern чисто собирает
центральную связанную массу и7–10 неодинаковых уплощённых подушек на frozen
crown volumes. Редкие пары folded leaves на outer rim используют прежние
_leaf/_stem; дерево/collision не меняются. Внутри спокойные крупные массы,
без равномерного покрытия побегами и без нового renderer/формата структуры.
Recipe.parameters: foliage_leaf_accents0–100 (missing/default35), leaf_size3–12
переиспользован как «Размер деталей». Только два conditional controls уstyle3;
foliage_amount/cluster_size/flatten/cohesion остаются общими. Accents selection
deterministic/nested и не пересобирает cloud body; больше accents добавляет детали.
Old styles0/1/2 exact; missing style0. Palette4 darken.42/6 lighten.18 только3.
`test_voxel_foliage_pattern.gd` включает clouds на8/11 ×64/96/128/256 ×17/391,
budgets/wood/collision/supports, fresh-frozen/text, amount0, UI Undo/Redo/Discard,
presets и extremes size3/12. `-- --clouds-only` запускает этот поднабор отдельно.
Native fixture `-- --foliage-clouds-only`: один oak8/height96/seed391 вpixel1,
shoots2, clouds3 accents35/80; individual accents Apply/Discard/Undo/Redo,
publication/reopen, contextual conditional controls/Undo/Discard. PASS, actual
captures `generation_foliage_clouds_native/front/side/preview/detail.png`
просмотрены. Освещение ещё отличается от рисованных references; art gate открыт.
Read-only prefab mesh audit на oak8/height96/seed391: cloud3 occupied94_068,
vertices217_464/triangles108_732; pixel1 193_576/96_788, shoots2 348_560/174_280,
old0 182_680/91_340. Cloud менее затратен, чем shoots, но примерно на12% больше
triangles, чемpixel; не обещать forest performance по одному объекту.
Fresh cloud geometry64–256 около0.15–0.52s, prefab meshing измеряется отдельно.
Полный foliage и7related suites oak/types/bark/editing/large-tree/generator/
variation PASS; clouds-only PASS. Общие старые migration gates не менялись.

Общие режимы листвы (2026-09-13, отдельное согласие пользователя):
FoliagePattern.supported покрывает volume-based versions4–17 всех5 tree_type.
Pixel1/cloud3 используют исходные center/radii/along crown volumes каждой
породы; никакой замены scaffold дубовым или отдельного species renderer.
supports_style отделяет oak-only shoot2 (oak8/11/16/17); option2 disabled в
creation/candidate/contextual UI остальных пород, enum ids неизменны.
Явный выбор другой породы после shoot2 сбрасывает style0 в том же Recipe Undo.
Прежние controls detail/strength/leaf_size/accents переиспользуются; style0,
каркас/physical не менялись, сохранённые assets не пересобираются при открытии.
Legacy versions1–3 остаются прежним путём без volume dressing. Новый
test_voxel_foliage_species проверяет all5/style1+3/seeds17+371/64+256,
wood/collision, full scaffold, свежую freeze parity, контраст palette-only,
bare foliage, storage budget, сериализацию точной geometry, UI/Undo/Redo/
Discard. Он и5related suites PASS; native Forward+ gallery10 деревьев в
disposable copy PASS без script/engine errors, capture просмотрен.
Пользователь принял текущую итерацию и запросил commit/push;
художественная полировка иных проб вне этого среза.

Cloud caps revision2 (2026-09-13, обратная связь о тарелках/рисунке): тот же
style3 и frozen volumes, без нового skeleton/owner. Broad central dome и3–5
upper lobes выше опоры, нижний срез; прежнее forced flatten/radial ring убрано.
Авторское canopy flatten сохранено. Sparse folded accents используют прежние
leaf/stem primitives; дерево/кора/physical/supports неизменны. FoliagePattern
colorize переиспользует pixel-art coordinate-owned surface motifs после union:
foliage_detail0–100 (scale9→3) меняет только indices, не occupancy/structure;
foliage_pattern_strength0–100 только palette4/6, не indices. Четыре conditional
controls: leaf_size, leaf_accents, detail, strength. Shape controls общие.
Recipe.parameters.foliage_cloud_version: defaults2, normalize missing1/clamp1–2.
Revision1 painter/palette точные прежние; old styles0/1/2 неизменны. Центральный
needs_style_upgrade используется creation/candidate/contextual UI: явный
reselect style3 устанавливает2; draft/local history и contextual Undo возвращают1.
Native fixture теперь сравнивает old cloud1 иcaps2 strength20/65/100, detail55/85
на одном oak8/96/seed391. Pattern Apply/Undo/Redo, accent Discard/Apply/history,
publication/reopen/contextual switching PASS; actual captures просмотрены.
Targeted дополнительно проверяет old cloud1/missing parity (occupied94_068),
явный contextual upgrade/Undo, pattern occupancy/structure и palette-only contrast.
Read-only caps2 mesh audit96/391: occupied98_840, vertices187_160,
triangles93_580 (pixel96_788, shoots174_280). Один объект, не forest benchmark.
Fresh caps geometry64–256 около0.16–0.65s, meshing отдельно. Clouds-only/full
foliage и8related oak/types/bark/editing/large-tree/generator/variation/session
PASS; diff --check чистый. Art gate открыт, старые migration gates не менялись.

Параметры партии и выбранного кандидата разделены. Общие editing descriptors
применяются к frozen Recipe: draft имеет local Undo/Redo без meshing, Apply строит
одну revision вне preview и только после успешной подготовки заменяет geometry.
Source model_id/seed/family сохраняются. Recipe-only history пересобирает один
candidate при Apply Undo/Redo, не удерживает старые mesh. Явная «Новый каркас из
настроек партии» очищает structure только выбранного, также undoable. Dirty draft
блокирует смену кандидата/new batch/save до Apply/Discard; native selection следует
тому же правилу. Settings выбранного переносятся в batch и прежний preset store.
После первой publication local editing/geometry history блокируются для данного
candidate, даже если file Save отменён: иначе file Redo вернул бы старые bytes при
другом preview. Published edits идут через прежний Canvas либо новую генерацию.

`ember_voxel_tree_object_creation.gd` остаётся единственным prepared publication
owner: `save_to_library` публикует source/prefab прежним Store + recipe в
`content/editor/voxel_generators`, без instance. Scene history восстанавливает
точные три файла; удаления отказываются при поздних byte changes или использовании
в author-owned instance/сохранённой карте `res://scenes`. Файлы разных concrete
вариантов не затрагиваются. Choice history хранит model_id, не full Creation;
signals не замыкают refcount cycle на candidate. Save batch использует shared
filesystem scan lease; queue сохраняет один chosen unsaved из всей истории за
frame, загружает его по необходимости и освобождает архивную geometry после Save.
Transient подготовка одного архивного объекта может добавляться к 3D working set;
вся история одновременно не remesh-ится. Scene switch/cancel останавливает queue
между объектами и освобождает scan lease. Одинаковое название проходов продолжает
family; смена названия создаёт новую, не удаляя предыдущие records.

`ember_voxel_generator_presets.gd` сохраняет тот же Recipe в отдельном editor-only
`content/editor/voxel_generator_presets`: normalized parameters + seed, без
structure/family identity; Resource.resource_name задаёт имя. Три встроенных
стартовых профиля и пользовательские пресеты, duplicate name не перезаписывается.
«Ещё → Генерировать похожие» использует параметры saved source для новых каркасов;
редактирование существующей структуры остаётся contextual Canvas `Генератор`.
Gameplay не читает presets/recipes. Первый creation UI provider — large_tree;
новым object providers нужны descriptors/defaults/budget в том же registry, не
новая панель/serialization. Старый tree dialog сохранён только для совместимости
старого API/tests, production creation больше его не открывает. Старый commit
с placement по-прежнему доступен прежнему contextual consumer.

Полировка крупных деревьев добавила recipe parameter `generation_version`:
отсутствующий/1 выбирает прежний алгоритм с прежними defaults; новые default
recipes и диалог выбирают 2 (`Крупные формы`). Это версии одного существующего
provider, не второй editor/Resource owner. v2 задаёт широкую/вытянутую/ярусную
крону, толщину и сужение ветвей, изгиб, начало ветвления, размер/приплюснутость
пучков, сомкнутость кроны и корневые выступы. Листва — перекрывающиеся цельные
объёмы с согласованным шумом контура, без per-voxel hash-прореживания; макро-
просветы задаются сомкнутостью. Верхний leaf pole достигает height-1, ствол не
обрезается верхним пределом. Размах автоматически ограничен прежним storage
budget, особенно на 256 vox; параметры не обещают неограниченную ширину.
Старые recipes/поставленные assets не перегенерируются. Два consumer UI остаются
раздельны по назначению: крупные деревья — объекты, маленькие — прежние штампы.
В общей панели основные controls находятся слева, расширенные свернуты.
Leaf-density видна только classic, `foliage_amount` — v2; прежние параметры
алгоритма и 16/32 grid density доступны в дополнительных настройках.
Свет/шейдер и ручная правка индивидуальных ветвей не входят в этот срез.

Общая contextual вкладка Canvas `Генератор` добавлена рядом с `Части`/
`Библиотека`. `ember_voxel_generator_panel` строит controls по provider descriptors
из существующего registry (`editing_fields`); панель не содержит математики дерева.
Первый подключённый provider — large_tree v2. Classic и остальные providers
пока не имеют редактора структуры и не показывают вкладку; их создание/штампы
сохраняют прежние пути. Для подключения нового provider нужны descriptors,
structure validation/capture и build на структуре в том же registry/provider,
а не второй editor. Общий `prepare_recipe` продолжает существующую prepared-asset
transaction; нынешнее имя файла tree_object_creation историческое.

Editor-only `EmberVoxelGeneratorRecipe.structure` — provider-owned Dictionary.
Дерево хранит version, tapered line endpoints/radii/profile, canopy anchors,
RNG states, baseline parameters и pivot/grid. Новые v2 objects сохраняют каркас
вместе с рецептом; старый v2 recipe без structure захватывается от его исходных
параметров только по Prepare, без записи старого asset. Изменение листвы не меняет
древесину/коллизию, branch thickness/taper не переставляют развилки. Количество
пучков задаёт стабильное group thinning 0–100%, включая bare tree. Palette-only
варианты сохраняют геометрию; shape noise/RNG независимы от цветов. Pivot сохраняет
положение древесины при увеличении grid для кроны. Gameplay model schema не менялась.

Параметры имеют отдельный draft UndoRedo (кнопки и Ctrl+Z/Ctrl+Shift+Z в активной
вкладке), сборка только по кнопке. Preview берёт Mesh из точного prepared prefab
в существующий Forward+ viewport; исходный Canvas Resource не подменяется.
`CanvasMode.GENERATOR` исключает кисть/штамп/выделение, камера продолжает работать.
Выход из вкладки или Esc убирает preview; выбор кисти возвращает вкладку Части.
Сбросить возвращает recipe baseline; смена объекта сбрасывает parameter draft.
Save имеет три режима: новая именованная вариация в семействе, обновление
выбранной вариации и отдельный объект со своим семейством. Каждый вариант
по-прежнему имеет отдельные canonical source/recipe/prefab и concrete model_id
в сцене. Editor-only recipe хранит family_id/family_title/variation_name;
Object Library проецирует семейство одной карточкой с dropdown вариаций.
Поиск включает имена/ID вариантов; Place/Edit работают с выбранным concrete ID.
Ранее сохранённые независимые модели не группируются автоматически. Новый variant
ставится рядом с original через один scene Undo; assets остаются восстановимыми.
После публикации общий asset_changed обновляет библиотеку и чистый Canvas.
Обновление выбранной вариации использует существующий shared ObjectSession:
один scene Undo/Redo восстанавливает source, recipe и mesh/collision всех её
экземпляров в активной сцене, не меняя transforms и другие вариации. Другие сцены
ссылаются на тот же asset и увидят обновление при повторной загрузке; защита от
конфликта с другой открытой сценой сохранена. Подготовка проверяет hashes source/
recipe; сохранённая ручная лепка и несохранённый Canvas draft блокируют overwrite.
Ручная лепка исходника не переносится в recipe variant и никогда им не затирается;
обычный Save Canvas по-прежнему сохраняет ручную лепку.
Осенний цвет доступен через поле цвета, без автоматического сезонного preset.
Индивидуальные ветви/пучки, другие providers и
shader/light остаются следующими согласуемыми срезами.

Исправлен clockwise winding DOWN-граней в единственном VoxMesher. Build contract
prefab теперь normalized-block-v2-bottom-winding: существующий ensure_saved
пересобирает устаревшие производные meshes по явному Place/Rebuild, не source.
Старые scene instances требуют явного обновления для исправления вида.
ObjectSession принимает только точную предыдущую DOWN-перестановку visual и
collision при прежних normals/colors/indices, но отвергает произвольные ручные
mesh-правки. Opening не пишет assets. Контрольный lantern_stone prefab и два его
производных mesh пересобраны gate; canonical source, map и placements не менялись.

Общий refresh 2026-09-12: Inspector Rebuild prefab / migration dock targeted
rebuild теперь выполняют editor-only `ember_voxel_scene_refresh` для всех
экземпляров выбранного model_id в активной сцене. Команда «Обновить воксели сцены»
доступна в 3D toolbar «Ещё…» и Ember Migration → Voxel-префабы. Она группирует
модели по concrete ID и обновляет только устаревшие signatures; между моделями
уступает кадр, сверяет source/prefab hashes и snapshots до публикации.
ObjectSession.prepare_geometry_refresh сравнивает точную текущую/старую DOWN
геометрию, включая ShadowBody, и захватывает mesh/shape replacement. Source,
recipe, scene-файл и transforms не пишутся; авторские descendants и overrides
сохраняются. Несовпадающая модель целиком пропускается с понятной причиной.
Несохранённый Canvas блокирует обе команды. Store.install_derived_prefab
публикует только prefab через user:// staging + атомарный rename, сохраняя UID.
В отличие от старого external-mesh rebuild, никаких live ArrayMesh mutations:
scene Undo/Redo восстанавливает точные старые/new instance snapshots и prefab
bytes/геометрию, сохраняя recoverable resources. Обновление создаёт новые inline
derived mesh; старые неиспользуемые external mesh-файлы не удаляются.
Команда также вызывает SurfaceProjection.refresh_geometry: configure(same
Resource) остаётся no-op, явный refresh заново ставит chunks в штатную очередь
с бюджетом кадра, не эмитит canonical Resource.changed. Surface chunks —
несериализованные производные данные; Undo/Redo экземпляров лишь повторяет их
requeue по неизменённому source, а не восстанавливает устаревший Surface renderer.
Ручная проверка рабочего 3D viewport и Source/manual override cases открыта.

Полная библиотека: «Объекты → Пересобрать всю библиотеку» (также Ember Migration)
делает snapshot уникальных concrete Catalog.ids, включая вариации и отсутствующие
в активной сцене объекты. `SceneRefresh.rebuild_library` обрабатывает строго одну
модель за раз, между моделями уступает кадр; прогресс/cancel находятся в dock.
Cancel останавливает перед следующим объектом, законченные остаются опубликованы.
`rebuild_catalog_model` проверяет сохранённый prefab и его open instances против
canonical native/legacy source, не мигрирует legacy и не пишет source/recipe.
Ошибки/ручные mesh/material изменения дают пропуск с причиной. История Undo
отдельная на каждую модель (exact prefab bytes + instance snapshots); впервые
созданный derived prefab остаётся recoverable при Undo. После публикации history
освобождает dense draft/baseline buffers, не готовит весь batch заранее.
Один большой объект всё ещё может занять заметное время; это последовательная
очередь, а не worker-thread meshing. Пользовательская очередь 226/226 завершилась:
196 rebuilt, 24 legacy indexed/unit-adapter false conflicts и 6 publication failures.
Поправка допускает exact expanded triangles текущего/старого DOWN кандидата:
индексы могут переиспользовать вершины, но позиции/нормали/tangents/colors/materials
и collision обязаны совпадать. Для старого VOX ShadowBody воспроизводится известный
opaque-only кандидат. Это opt-in refresh, не общее ослабление Canvas Save validation.
В open instances replacement buffers приводятся к старым units; node frames,
authored descendants и pose неизменны. Published prefab остаётся normalized.
UID задаётся только в generated staging header перед публикацией bytes,
без повторной ResourceSaver.set_uid/.uidren транзакции. Подробная стадия ошибки
возвращается в dock. «Повторить пропущенные модели» использует только failed IDs
последней очереди в текущем editor session; список не сериализуется.
30 исходных failed assets проверены read-only с копиями prefab в user://:
publication/UID/bounds/descendants/Undo/Redo/reopen/source hashes PASS.
Production assets тестами не пересобираются; пользовательский повтор остаётся gate.
Повторная рабочая очередь дала 205/226 rebuilt, 21 ошибок rename Failed на другом
наборе IDs. Library batch теперь держит weak scan lease общей Filesystem очереди:
наши scan requests coalesce до конца/cancel, уже активный scan/import ожидается
до 30 секунд. Временный rename failure повторяется до 3 секунд с кадрами/100 ms,
prepared mesh не вычисляется заново. Перед retry повторно проверяются source hash,
prefab bytes и open instance snapshots; конфликт прекращает retry. Один successful
publish = один Undo action. Постоянная ошибка остаётся skip с disk path.
Windows DirAccess rename может удалить destination перед MoveFile, не является
true atomic replace: если destination исчез при сбое, восстанавливаются прежние
bytes, при неудаче rollback сохраняются recovery bytes в user:// и показывается
путь. Рабочий источник конкретного read lock не установлен (scan/preview/другой
reader); open-handle Windows fixture воспроизводит Failed и проходит после release
на третьей попытке. Native isolated library queue/retry/no-scan-during-batch PASS.

Resource schema 6 добавляет необязательный `collision_voxels`. Пустой массив
полностью совместим со старыми моделями и означает прежнюю коллизию по всем
занятым voxels; заполненный массив того же размера отмечает только физические
voxels. Prefab строит collision mesh из этого подмножества. У большого дерева
это ствол и толстые ветви, листья и тонкие кончики не физичны. Fragment, growth,
extract/split, merge и assembly сохраняют канал; при смешивании старого source с
масочным старый occupied считается физичным. Canvas-лепка делает новый voxel
физичным, удаление очищает бит, а перекрашивание существующего листа его не
меняет. Dirty/discard и object save учитывают канал.

Рецепт камня дополнительно хранит `variant_count` (1–8) и `size_variation`
(0–50%). Primary geometry остаётся единственным сериализованным voxel-источником.
`Generator.build_variants` детерминированно строит остальные формы из recipe seed;
`Stamp.prepare_generated_variants` держит их только в transient cache пресета и
проверяет ключ по рецепту, voxels, palette и material. `Россыпь` получает индекс
формы из того же seeded placement stream и передаёт массив geometries в один
общий `plan_many`; палитра, каналы, bounds, locks, preview и одна Undo-команда
остаются общими. Для прежних и авторских пресетов variant count равен одному и
дополнительное случайное число не потребляется, поэтому старый scatter не дрейфует.
Одиночный/путь/линия используют primary geometry. Максимальный тестовый набор из
восьми форм до 32³ строится примерно за 290 ms один раз при выборе источника.

Повторяемое размещение вынесено из Stamp в чистый
`ember_voxel_brush_placement.gd`: line/path spacing, seeded scatter jitter и
surface snap общие для авторских и generated источников. Старые методы Stamp
делегируют в модуль и сохраняют API. Сценовый `ember_voxel_placement_session.gd`
остаётся отдельным владельцем transform существующих Node3D и к этой логике не
относится. Максимальный тестовый камень 32×32×32 строится примерно за 60 ms;
generator gate также проверяет determinism, multi-form variant set, connectivity,
base contact, save/edit/reopen, regular stamp preview/commit/Undo и scatter reuse.

### Склейка и принадлежность вокселей (ручная приёмка открыта)

Дополнение: `Merge.plan(inputs, align_grid=false)` допускает явное совмещение
origin в frame основной детали по общей большей плотности. Basis проверяется
прежним строгим правилом; вращение/масштаб не меняются. `adjustments` возвращает
исходные frames и delta_vox/delta_world; Session сохраняет прежние scene poses
для stale validation и Undo, а prefab строит сразу по согласованному plan.
Никакого промежуточного движения scene nodes нет. Dialog checkbox «Совместить
сетки» пересчитывает preview, cyan translucent ghost показывает исходное
положение; primary change сбрасывает checkbox и старый preview. Δ указаны по
осям сетки основной детали, не обязательно мировым. Отмена/снятие checkbox
не меняет сцену. Это grid alignment, не surface contact snapping.
`test_voxel_merge` проверяет пользовательские fractional positions, смешанную
плотность, отказ от произвольного вращения даже при alignment, one Undo/Redo,
save/reopen; native capture — `user://voxel_merge_alignment.png`.

Принятый контракт: истинная склейка 2–32 обычных native voxel-props одного
родителя и разбор текущей формы, отдельно от Node-группировки. Relative basis
должен быть signed quarter-turn без отражения/изменения масштаба, origin — на
общей voxel-сетке; повороты не округляются. Плотности 16/32 повышаются до большей,
каждый низкоплотный занятый voxel занимает 8 высокоплотных, каналы сохраняются.
Пересечение выигрывает основная деталь, выбранная в preview. Палитра >255
занятых цветов, разные общие material/physics settings, вода, custom light и
authored generated-node overrides отклоняются. Общий холст ≤524288 ячеек,
XZ≤256, Y≤8*density; максимум 32 исходные части (плюс «Добавленное»).

Resource schema 6 добавляет `merge_parts: PackedStringArray` и
`voxel_part_ids: PackedInt32Array`: 0 — Добавленное/пусто, положительное значение —
индекс имени +1. Пустая пара совместима со старыми источниками. Это только
авторинг, runtime геометрию строит из прежних voxels/channels. Ни снимков старой
геометрии, ни второго источника нет. Группы выделения остаются независимыми.
Validator проверяет размер, диапазон и отсутствие владельца у пустой ячейки;
to_definition, COW save/reopen, dirty/discard учитывают поля.

Owners: `ember_voxel_merge.gd` — чистые plan/separate; `ember_voxel_parts.gd` —
принадлежность после мазка/перенумерации. SculptActions фиксирует ids вместе
с геометрией одним Undo, в live-режиме — на pointer-up и только затронутые indices.
Fragment, growth, extraction и regular sections переносят ids; общий Canvas
секций объединяет одинаковые каталоги частей, несовпадение явно отклоняет.
Canvas selector «Новые воксели → …» не ограничивает маску и не меняет группы.

`ember_voxel_merge_session.gd` проверяет источники/ссылки/позиции до публикации,
готовит все производные prefab, публикует новые immutable assets существующим
Store и только затем заменяет scene nodes одним Undo. Отказ не меняет scene;
уже опубликованные файлы остаются для восстановления. Original nodes удержаны
историей, Undo возвращает имена, владельцев, sibling order, источники и collision.
World mesh frame сохраняется через scene-owned root, не overrides prefab children.
`ember_voxel_merge_dialog.gd` — native preview с основной деталью и красным
overlap overlay; plugin More IDs 8/9. Перед командой нужен чистый Canvas.

Gate: `test_voxel_merge.gd`, опции `-- --capture` и `-- --benchmark`. Проверены
overlap, promotion, группы/каналы, лепка/live Undo, growth/crop/sections,
save/reopen, scene Undo/Redo, dirty/discard/COW, stale pose и ошибка публикации.
Dense synthetic 131072 occupied: plan 328ms, separate 297ms, mesh/collision 504ms,
publish 855ms. Это не полное время команды и не замер авторского Причала.
Операции пока синхронны; responsive background jobs остаются техническим долгом.

### Фрагменты Canvas — фаза 1

Отделение реализовано в ember_voxel_fragment_extract (чистые crop/remainder,
palette/4 material channels/groups) и ember_voxel_extraction_session (scene
transaction). Две команды панели вызывают подтверждение в workspace. Несохранённый
Canvas сначала сохраняется пользователем; shared-edit и Surface не поддерживаются.
Новая геометрия обрезается по выделенным занятым ячейкам, XZ дополняются до блоков
канонического Resource. Точная crop-origin входит в world placement, не в schema.
Generated child transforms остаются prefab-default: адаптер размещения целиком
в scene-owned prop.transform, иначе override масштаба детей терялся при reopen.
Новые source/prefab immutable: все assets публикуются ДО применения scene refs;
частичная ошибка не меняет сцену, уже созданные файлы остаются для восстановления.
ObjectSession.save поддерживает fresh_asset для уникальной публикации;
AssemblySession.save(...,true) возвращает подготовленные планы без применения.
Undo/Redo восстанавливает ссылки, геометрию/collision и наличие нового узла,
не перезаписывая и не удаляя файлы. Новый placement_id уникален, новая деталь
сосед исходного объекта/сборки (не ломает прямой состав регулярных секций).
После успеха по умолчанию Canvas перечитывает исходный объект/сборку и сохраняет
ракурс; переключатель «Перейти в 3D к новой детали» возвращает прежнее поведение.
Выбор хранится только в workspace. state_applied сигнал транзакции обновляет
чистый открытый Canvas после Undo/Redo; несохранённый draft не перезаписывается,
а получает предупреждение. Копия остаётся на том же месте до ручного сдвига.
Отдельные световые источники, активная заливка, нестандартные render/physics
настройки отклоняются явно; геометрические offsets поддерживаются при совпадении
Mesh/Collision frames. Скрипты, сокеты и прочие authored nodes остаются у оригинала.

Mode 4 теперь называется «Двухэтапное выделение».
`ember_voxel_surface_marquee` определяет входную грань ray/AABB выбранного
hit-вокселя, фиксирует Plane и отдельно выдаёт плоский footprint и его расширение
внутрь. Первый LMB-drag замораживает только footprint. Затем движение мыши по
экранной проекции внутренней нормали либо SpinBox задаёт 1..axis-size слоёв;
если нормаль почти направлена в камеру, используется вертикальный screen ruler.
Второй LMB или Enter подтверждает один общий selection history action. До этого
прежнее выделение и Resource не меняются; Esc/смена инструмента отменяют draft.
Существующий Selection.start_box инкрементально выбирает только занятые ячейки
внутри grid/region/slice/isolation. Контур и ghost используют те же bounds.
Никакой сохранённой schema или отдельного Undo owner не добавлено.

Существующие ember_voxel_selection/panel продолжают владеть временным выделением.
После UX-коррекции рамка протягивается мышью в экранной плоскости. Новый leaf
ember_voxel_selection_gesture инкрементально проверяет центры занятых вокселей
в рамке: видимая поверхность требует совпадения с первым hit существующего
Model.pick; насквозь включает внутренние/задние воксели. Region/slice/isolation
сохраняются; лимит 32768. Это не выбор по любому касанию грани рамкой.
Временный ember_voxel_selection_interaction только маршрутизирует жесты и
рисует ghost/оси/рамку; SelectionPanel остаётся владельцем принятого выделения.
До отпускания мыши source/selection не меняются. Смена камеры отменяет рамку,
смена модели/области отменяет незавершённый жест. Shift/Ctrl сохраняются.
ember_voxel_fragment — чистая целочисленная математика; поворот на 90° сохраняет
нижний угол AABB выделения, затем применяется смещение. Цвета, четыре канала
материала и voxel_groups переносятся/копируются вместе. Вода не преобразуется.
Перекрытия, locks и выход за grid/region/slice не обрезаются, а блокируют операцию.
Основной UI переноса теперь немодальный: voxel-snapped screen handles X/Y/Z,
числовые поля/ось/копия в существующей панели, cyan ghost и red invalid ghost.
Тот же leaf rotate_cell используется preview и plan. Нет full remesh на motion:
MultiMesh ghost + чистый план, события объединены до кадра. Исходное выделение
остаётся оранжевым ориентиром до применения. Enter commit, Esc cancel; Ctrl+S
требует сначала применить/отменить перенос. Применение идёт
через существующий EmberVoxelSculptActions, один Undo; штатное сохранение Canvas.
Нет новой schema/источника геометрии. Отделение описано в начале этого раздела.

### Поверхность прохода — явная физическая опора

Первый срез для исследовательских сцен: ember_walk_surface/session/dialog/gizmo
в addons/ember_import. Пользователь явно создаёт прямоугольную опору поверх
декора, задаёт локальные размеры, положение и наклон менее 44°. Owner — карта
`.tscn`: обычный scriptless StaticBody3D с BoxShape3D (слой 1), без игрового Mesh.
Это согласованное разделение декоративной геометрии и общей физической опоры,
не поверхность только для героя. Исходные коллизии не отключаются. Клеточная
Battlefield Resource автоматически не обновляется; инструмент не заменяет её.
Editor gizmo и preview не сериализуются; источники voxel/prefab не меняются.
Выбор группы прикрепляет опору внутрь; выбор voxel prop — рядом, сохраняя prefab.
Общий Canvas регулярных секций пропускает маркированную опору и сохраняет её;
разгруппировка группы с helper пока безопасно отклоняется.
Операция атомарна с Undo/Redo, отмена preview не меняет сцену. Красные рамки —
консервативные габариты видимого декора, не доказательство физического прохода.
Вход надо состыковать с землёй; автоматического подъёма на ступени пока нет.

### Группы и linked-ряды — awaiting manual

`ember_voxel_scene_assembly.gd` координирует scene-owned reparent/duplicate через
существующие EmberSceneAuthoring и Placement validation; не пишет voxel assets.
Группировка ограничена 2–32 обычными native props одного родителя. Для разборки
принимается обычный Node3D с 1–32 direct props, без script/scene_file_path,
собственных visibility/process/group/signal зависимостей. World transforms
сохраняются через точные local matrices; owner, имя и sibling index возвращаются
Undo. Сохраняемые ссылки сцены и signals проверяются до reparent; динамические
строковые пути внутри произвольных скриптов автоматически не переписываются.
Source shape/channels не затрагиваются, разбор работает с текущими деталями.

Ряд: одна обычная деталь, 1–32 новых экземпляра, позиции из мирового шага выбранной
voxel-сетки Placement. Preview — shared mesh copies, commit использует прежний
EmberSceneAuthoring.make_duplicate/attach_duplicate с уникальными placement IDs.
Нет remesh или записи source/prefab; последующий обычный Canvas Save делает COW.
Смена source/hierarchy/pose после preview отклоняет commit. UI хранит последний
мировой шаг до перезагрузки плагина; повтор создаёт одну копию текущей выбранной
детали и выбирает её для следующего повтора. Undo каждой команды неделим.

### Точная voxel-расстановка — этап 2.3, принята пользователем

`ember_voxel_placement_session.gd` меняет только `transform` выбранного корня
сцены: одного native EmberVoxelProp или существующей сборки/wrapper с 2–32
native voxel descendants. Это session-only authoring state без новой schema;
EmberVoxelModelResource и prefab открываются только для проверки и не записываются.
Top-level descendants отклоняются, потому что не последовали бы за корнем.

Координаты — мировые XYZ выбранной опорной точки в единицах выбранной voxel-сетки
с world origin 0. Всегда доступен общий шаг 1; дополнительные варианты получают
три фактические длины ребра из `Mesh.global_basis / source density`, поэтому
конверсионный/nonuniform scale не выдаётся за nominal размер. Привязка округляет
опорную точку, а не origin узла. Auto-snap округляет только редактируемую ось;
явная команда — все XYZ. Pivot: local AABB center/lower corner; у одной модели
custom — её source voxel coordinates, у сборки — grid offset от lower corner.

`ember_voxel_placement_math.gd` применяет числовой delta X→Y→Z слева к полному
исходному world basis и вычисляет origin по pivot. Decompose/recompose нет, поэтому
неравномерный scale/shear сохраняется. Local transform получается через исходный
`parent.global_transform.affine_inverse()`, включая transformed parents. Изменение
pivot само не сдвигает уже построенный preview. `ember_voxel_placement_dialog.gd`
показывает безопасные Mesh-копии target и прежний CanvasContext окружения; live
сцена до подтверждения не меняется. Apply — одна `.tscn` Undo/Redo-команда вместе
с коллизией/children. Stale target/parent/hierarchy/source отменяет commit.
Group creation, duplicate-repeat, merge и Canvas произвольной сборки не входят.

### Общий Canvas секций — принят пользователем 10 сентября

`ember_voxel_assembly_session.gd` — координатор ObjectSession, не второй source
owner. Временный EmberVoxelModelResource объединяет плотную стыковку XZ с общей
Y и basis. Палитры объединяются по Color (index0 остаётся empty), каналы и group
indices переводятся в общий адрес. Контекст исключает всю группу, frame общий.
При Save сравниваются нормализованные срезы draft/baseline; только изменённые
секции используют `ObjectSession.save(resource, prepare_only=true)`.
Store пишет fresh independent assets, и лишь после всех успешных публикаций
одна операция применяет все snapshots. Undo/Redo меняет ссылки без записи файлов;
старые версии остаются доступны. Каждое реальное Save создаёт новые assets только
изменённых секций; это осознанный COW tradeoff, автоматической очистки нет.
Если запись оборвалась, scene refs не менялись, но новые orphan copies могут
остаться. Обычный ObjectSession.save без второго аргумента сохраняет прежний путь.
Расширение общего холста отключено: секция должна владеть каждой ячейкой, нет
скрытого присваивания промежутков. Поддержаны прежние группы после XZ-разрезания
без миграции. Отдельный выбор Part сохраняет индивидуальный Canvas.

### Canvas save reuse и явные секции — приняты пользователем 10 сентября

`ember_voxel_object_session.gd` строит detached baseline один раз на save;
сравнение live/source остаётся независимым, включая shared targets.
`scripts/ember_voxel_projection_cache.gd` — ephemeral geometry cache, не новый
renderer/schema. Полные XZ Y-slabs (~65536 cells, до 8 слоёв) сохраняют порядок
y/z/x; зависимости включают соседний слой. Используется прежний
`VoxMesher._build_culled`; объединение создаёт новые массивы в прежних opaque/
transparent surfaces. Palette/density/grid invalidation полный, occupancy/
transparency — по изменённым slab+halo. Scene layout/collision faces неизменны.
Коллизия, shadow body и сериализация пока полные, асинхронный Save не реализован.

`ember_voxel_object_split.gd` режет native-only источники на равномерные XZ
секции с полной Y; `ember_voxel_split_dialog.gd` показывает read-only геометрию
и границы. Новые `.tres`/prefabs остаются под существующим Store/Prefab;
исходник в сцене заменяется Node3D-группой, transform компенсирует центр каждого
нового prefab. Каналы и group indices пересчитываются без потерь, пустые секции
сохраняются. Один Undo восстанавливает исходник и оставляет новые assets.
Частичная ошибка публикации не меняет сцену, но оставляет опубликованные новые
assets для восстановления; автоматическая очистка не реализована. Первый
вариант: 2–32 секции, размеры 32/64/128, <=524288 исходных ячеек; вода, aggregate
lights, scripts/extra children/generated overrides получают явный отказ.

### Конверсия простых форм — этап 2.2, awaiting manual

«Форму в voxel…» в 3D использует `ember_voxel_primitive_conversion.gd` и
`ember_voxel_conversion_dialog.gd` (наследует существующее окно создания).
Источник остаётся EmberVoxelModelResource; генерация — прежние Shapes,
публикация — Store, новый prefab — прежний Prefab/SceneAuthoring.

Поддержаны BoxMesh, закрытый CylinderMesh с равными радиусами и полная SphereMesh
с height=diameter. Непрозрачный одноцветный StandardMaterial3D, без textures/
ShaderMaterial/overlay. Выбрать можно MeshInstance или его простой контейнер.
Scene-local leaf visual заменяется EmberVoxelProp с прежним именем в прежнем
контейнере. Скрипты, children/prefab ownership, сохраняемые signal connections,
несовпадающая/составная/движущаяся коллизия получают отказ. Простой StaticBody
контейнер сохраняется; старая CollisionShape удаляется из дерева, новая voxel
collision внутри prop наследует layer/mask/physics material. Декорация остаётся
без коллизии. Undo возвращает исходные nodes/owners/indices; assets не удаляет.

Fit transform компенсирует padding, нижний voxel-origin и округление разрешения;
сохраняет исходные размер по параметрам, центр и parent transforms. Фактический
voxel step явно показан в preview; 16→32 удваивает разрешение, не world bounds.
Это не snap/выравнивание для склейки. Кривые получают ступенчатую аппроксимацию.
Перед публикацией inspect сверяет source mesh, размеры, материал, transform и
коллизию с prepared state. До применения не создаёт файлов. Общий лимит 524288
storage cells; выше 131072 preview требует явного разрешения, сбрасываемого при
изменении параметров. Более крупные плиты требуют явного снижения XYZ.

### Окружение Object Canvas — awaiting manual

`ember_voxel_canvas_context.gd` создаёт только MeshInstance3D/MultiMeshInstance3D
в прежнем Canvas SubViewport. Mesh/material references доступны только для чтения;
скрипты, коллизия, анимации, игровые lights/cameras не инстанцируются. Выбранный
prop subtree исключён, иначе старый prefab перекрывал бы изменяемый draft.
Visibility-фильтр исключает скрытые и shadows-only visuals. До 4096 visuals;
при переполнении явный отказ без частично применённого нового фона.

Session отдаёт weak-target контекст и mapping canvas→scene на основе исходного
mesh adapter, текущего prop transform и размеров draft. Stable anchor сохраняет
совмещение при grow/Save/Undo/Redo. Кисть продолжает ray picking только canonical
draft; фон не входит в selection, Undo, Resource или scene serialization.
Прозрачность — per-instance override, source material не меняется. Фон строится
по toggle/«Обновить окружение», а не на каждый мазок; polling проверяет живость
сцены и положение target без remesh. При закрытии исходной сцены фон снимается.
Новый Canvas-сеанс начинает с выключенным фоном; это ephemeral authoring state.
Свет студийный, не финальный свет карты; проверка посадки, не второй renderer.

### Воксельные формы — этап 2.1, awaiting manual

Корректирующий проход 10 сентября: видимая 3D-панель создания/открытия voxel
объекта, «+ Объект» и «Расширить холст…» в Canvas. Grow-only расчёт в leaf
`ember_voxel_canvas_growth.gd`, исполнение в прежнем SculptActions. Remap всех
плотных voxel/material каналов и групп, XZ symmetric padding, Y вверх;
schema не меняется. Workspace baseline/discard включает размеры и перенесённые
каналы. До 524 288 ячеек, без уменьшения и заполненных water channels.

Read-only migration report и prefab status больше не используют CACHE_MODE_REPLACE:
он очищал SceneState активных экземпляров при смене карты/обновлении панели.
Store публикует отдельный PackedScene без staging inheritance и возвращает
опубликованную cache identity; Creation инстанцирует именно её. Публикация и
явная пересборка прогревают editor node-path cache. Пользовательские сцены,
файлы моделей и сохранения этот проход не переписывает.

Этап 1 Save/UI принят пользователем 10 сентября 2026. Новый вход без выбранного
объекта: «Проект → Инструменты → Ember: Новая voxel-форма…». Dialog предлагает
пустую область, блок XYZ, цилиндр (диаметр XZ + высота), сферу (один диаметр),
плотность 16/32 и цвет. Чистый `ember_voxel_shapes.gd` заполняет прежний Resource;
`ember_voxel_shape_creation.gd` переиспользует Store/Prefab/SceneAuthoring и
одну creation Undo-команду. До подтверждения нет assets; после него открывается
Canvas. Preview и commit используют один подготовленный prefab. Сцена сохраняется
пользователем; Undo не удаляет созданные source/prefab файлы.

Размер occupied-формы точный, XZ-storage округляется до блоков и явно показан
отдельно. В пустой модели редактируется вся сетка вместе с запасом XZ. Только
генератор теперь ограничен 524 288 storage cells: 32×2×8 prepare около 8–10 мс,
64×32×64 около 595 мс; 128×64×128 занял 4.7 с, поэтому такой размер отклоняется,
не округляется и не ограничивает уже существующие Resources.

Пустота поддержана в общем native prefab builder, включая force rebuild. Mesh
остаётся пустым ArrayMesh; generated Collision/Shape остаётся без Shape Resource,
то есть без физической коллизии. Стабильные узлы сохраняют authored descendants
и overrides. SceneSession понимает empty parity и обратимые переходы empty/solid.
Только object Canvas «Объём/Добавить» получает fallback на нижнюю плоскость через
тот же ray picker; обычный Surface picking не меняется. Inspector не считает
отсутствие коллизии у пустого source ошибкой. Этап 2.2 реализован отдельной
конверсией, этап 2.3 — отдельной точной расстановкой выше.

### Воксельный объект в Canvas — этап 1

Inspector обычного EmberVoxelProp предлагает «Редактировать в Canvas», общую
модель с предупреждением, linked instance и независимую копию. Сессия
`ember_voxel_object_session.gd` — editor-only detached draft и транзакция;
канонический источник остаётся EmberVoxelModelResource, производные данные строит
тот же EmberVoxelPrefab через read-only `prepare_resource`. Surface Canvas и его
Save/Discard/Cancel guard переиспользованы; ресурс и callback меняются вместе
после решения пользователя. После Save старой shared-модели входящий draft
перечитывается, чтобы не открыть устаревшую копию.

Первый реальный selected-only Save создаёт независимые model_id/source/prefab;
просто открыть/Save без изменений/Discard ничего не создают. Следующие Save той
же сессии сохраняют ID. Новая сессия консервативно создаёт новый ID: число объектов
в текущей сцене не доказывает уникальность source во всём проекте. Shared Save
обновляет связанные mesh/shape в текущей сцене, сохраняя placement, transforms,
authored descendants и instance overrides; при других открытых сценах он
блокируется до их сохранения/закрытия. Это не полная cross-tab синхронизация.

EmberVoxelModelStore stage-запись готовит source и prefab до публикации, сохраняет
UID и обновляет cache identities без изменения старых Undo mesh/shape. Generated
данные применяются явно; scene-file сохраняет пользователь. Undo/Redo возвращают
source/ссылки/геометрию, новые неиспользуемые assets остаются для восстановления.
Preflight отклоняет внешний source/geometry change, удалённый target, validation,
неподдерживаемое изменение water fill. Legacy требует прежнего
migration parity и совпадения baked объекта с source; несовпадение блокируется
без импорта/перезаписи. В Причале BarrelA доступен; CargoA пока блокируется.

Исправления ручной приёмки: EmberVoxelProp исполняет canonical scale adapter и в
editor (`@tool`), но не создаёт runtime WaterContact там. Canvas использует
растягиваемый viewport без обратной зависимости minimum size от render target;
верхняя строка переносится. Пять authored cargo/barrel Причала имеют постоянные
placement_id. ResourceSaver сериализует транзакцию вне editor-индекса в user://,
затем публикует через соседний временный файл с atomic rename. Editor preview
читает сериализацию асинхронно: `user://ember-editor-staging/<pid>-<ticks>/`
сохраняется как восстановимый технический cache, не canonical source. Во время
editor-сессии он не удаляется; отдельный cleanup subsystem пока не добавлен.
Runtime tests удаляют свои временные файлы сразу. Root source signature также
обновляется после публикации и при Undo/Redo, чтобы Inspector отражал актуальность.

### Тестовая локация

Тестовый Причал: `scenes/test_pier.tscn` — самостоятельная authored сцена для F6,
без боя/сюжетных триггеров. `scripts/test_pier.gd` наследует `fan_town.gd`,
переключает тот же `EmberExploreState` на `user://ember-test-pier-v2` до
world spawn и задаёт активную пару protagonist/mira. После pause load bootstrap
сохраняет pending restore выбранного слота; outgoing scene не пишет поверх него
свой autosave. Новый F6 читает только собственный namespace. Legacy root также
изолирован. Лабораторные saves и main_scene не меняются.
У `EmberMapLoader.hydrate_legacy_regions` default true для прежних карт;
Причал отключает legacy region hydration и native cutaway.
Editor Surface selector также учитывает native opt-out: без Surface нет выбора,
существующий Resource даёт размеры без JOI; explicit open без Resource сообщает,
что конвертация простых форм не поддерживается. Legacy selector сохраняет
JSON-grid-first с прежними heights; неизвестные native размеры не запускают import.
Terrain/Props/Regions/Backdrop и коллизия принадлежат `.tscn`: примитивы — явный graybox, грузы —
существующие voxel-prefabs. Runtime-генератора карты или нового owner нет.
Ручная input/physics/визуальная приёмка остаётся открытой.

Этот репозиторий владеет runtime, Godot editor plugins, сценами и новым
контентом Ember. `../joi-conductor` — временный read-only архив legacy pack для
явного одноразового импорта. Новые механики, модели, карты и решения создаются
здесь.

Канонические документы:

- текущая точка: `docs/EMBER_NOW.md`;
- продукт и порядок: `docs/EMBER_PRODUCT_PLAN.md`;
- игровой дизайн: `docs/EMBER_GAME_DESIGN.md`;
- рабочий процесс: `docs/EMBER_WORKFLOW.md`;
- выход из JOI: `docs/EMBER_JOI_EXIT_PLAN.md`;
- автоматические и ручные gates: `MIGRATION_TEST_PLAN.md`;
- editor UX: `docs/EMBER_EDITOR_UX_AUDIT.md`;
- addons и ownership: `docs/EMBER_ADDONS.md`.

## Неподвижные технические границы

- Godot 4 Forward+ — единственный runtime и authoring target.
- Карты принадлежат `.tscn`; canonical voxel-модель —
  `content/voxel_models/*.tres` (`EmberVoxelModelResource`). Mesh, collision,
  thumbnail, prefab и MeshLibrary являются производными данными.
- Не создаются второй renderer, voxel editor, combat resolver, gameplay owner
  или параллельная schema.
- Preview и commit используют один расчёт. Editor-only selection, overlays,
  camera и layout не сериализуются в gameplay Resource.
- Collision, высота и navigation игрока/AI читают одну физическую поверхность.
- Legacy JOI читается только importer-ом; новые runtime-зависимости запрещены.

## Карта owners

### Voxel Surface и производные данные

- `scripts/ember_voxel_model_resource.gd` — canonical palette, voxels, groups,
  water/fill и schema Surface.
- `addons/ember_import/ember_voxel_sculpt_model.gd` — чистая editor-модель;
  `ember_voxel_sculpt_actions.gd` — mutation/Undo; workspace только связывает UI.
- `scripts/ember_voxel_surface_mesher.gd` и
  `scripts/ember_voxel_surface_materials.gd` — visual projection.
- `scripts/ember_voxel_surface_physics.gd` и
  `scripts/ember_voxel_surface_projection.gd` — collision, height и world sample.
- `content/world_surfaces/<map_id>_surface.tres` — canonical world Surface;
  `content/combat/surfaces/*.tres` — visual Surface боевого поля.

### Exploration, interactions и content

- `scripts/ember_map_loader.gd` — загрузка карты и нативной Surface.
- `scripts/ember_interact.gd`, `ember_interact_rules.gd` и
  `ember_interaction_ui.gd` — scene-owned binding и запуск взаимодействия.
- `scripts/ember_action_script.gd` — runtime action chain; `.tres`-источники
  находятся в `content/action_scripts/`.
- `scripts/ember_dialogue_resource.gd`, `ember_quest_resource.gd`,
  `ember_item_resource.gd` и `ember_shop_resource.gd` — canonical Resources
  соответствующих систем. Их catalogs остаются native-first.
- `addons/ember_import/ember_graph_workspace.gd` — единый крупный authoring
  workspace; специализированные editors/inspectors не владеют runtime state.

### Party, save и переход в бой

- `scripts/ember_explore_state.gd` — единственный mutable/save owner мира,
  партии, общей сумки, флагов и прогресса.
- `scripts/ember_party_state.gd` — чистая нормализация, derived stats, XP и
  level-up; он ничего не сохраняет самостоятельно.
- `scripts/ember_combat_transition.gd` — guarded-транзакция мир → бой → мир.
  Бой получает глубокую копию предбоевого состояния и возвращает результат один
  раз.
- Save v2 хранит три ручных файла и отдельный autosave в
  `user://ember-save-v2/ember_p1/`. Для каждого из четырёх постоянных героев
  сохраняются level, XP, текущие HP/MP и пять слотов экипировки; derived stats
  пересчитываются.
- Одноразовая v1→v2 миграция сначала делает byte-identical backup. Удаление слота
  также оставляет recovery-копию в `deleted_saves`.

### Combat

- `scripts/prototypes/ember_combat_prototype.gd` — единственный pure resolver,
  command preview/commit и stale-result guard.
- `scripts/prototypes/ember_combat_status_rules.gd`,
  `ember_combat_damage_rules.gd` и `ember_combat_effect_rules.gd` — внутренние
  stateless-модули правил. Они не являются вторым resolver и не владеют snapshot.
- `scripts/prototypes/ember_combat_state_schema.gd` — runtime-проверка входного
  snapshot и рассчитанного result на границе `preview/commit`.
- `scripts/prototypes/ember_combat_terrain.gd` — общая математика высоты,
  distance, LOS и terrain reactions.
- `scripts/prototypes/ember_combat_grid.gd` — dense Battlefield navigation,
  reachable/path, staged movement и positional planning.
- `scripts/prototypes/ember_combat_lab.gd` — controller команды, targeting и HUD.
- `scripts/prototypes/ember_combat_grid_3d_world.gd` и представления grid —
  projection/animation, а не второй gameplay owner.
- `scripts/prototypes/ember_combat_action_resource.gd`,
  `ember_combat_effect_resource.gd`, `ember_combat_status_resource.gd`,
  `ember_combat_unit_resource.gd`,
  `ember_battlefield_resource.gd` и `ember_encounter_resource.gd` — authoring
  contracts; экземпляры находятся в `content/combat/`.

## Текущее состояние editor и Surface

Surface Canvas поддерживает палитру, локальную кисть и пипетку, selection,
именованные/цветные группы, editor-only visibility, 3/5/7 palette ramps,
height slice, region editing, sculpt, water fill, bottom-only view, chunk preview,
Undo/Redo и guarded save/discard/reopen.

Кисти высоты используют один pointer-down heightfield и существующий
`EmberVoxelModelResource`. `Сгладить` имеет локальный и common-level планы;
common median считается разреженной гистограммой, а во время LMB оба режима
перестраивают дешёвую draft-сетку с точным remesh после commit. `Рельеф` состоит
из прежнего time-based `Наращивания` и editor-only генератора на штатном
`FastNoiseLite`: world/model-locked `Почва` (FBM) и `Гребни` (ridged), seed,
масштаб, octaves и signed/up/down displacement. `Детали · лёгкие` используют
отдельную разреженную кривую с жёстким пределом 1–2 vox при любой высоте, не
меняя прежние плотные уровни. Strongest-influence cache делает
результат независимым от event density; lower clamp сохраняет нижний voxel
исходно занятой колонки. Preview и один Undo используют общий stroke owner.
Нового gameplay terrain/schema/renderer нет.

Большая 24×24 Surface измерена на реальном dense Resource. Sparse-aware
heightfield, editor-only cache и native chunk backend ускорили hot paths без
смены schema. Подтверждённый профиль sandbox:

- dense channels: 9.84 MiB;
- load около 0.80 с, save около 0.13 с;
- synchronous Canvas open около 0.12 с вместо 0.79 с;
- group filter около 0.019 с вместо 0.71 с;
- exact chunk около 5.9–6.6 мс вместо 25.5 мс.

Оснований для sparse/chunk persistence нет. Воспроизводимый gate —
`tools/test_surface_large_profile.gd`, подробности —
`docs/EMBER_SURFACE_LARGE_PROFILE.md`.

`agent_sandbox` и `fan_town` используют одну physical Surface для visual,
collision и route heights. `fan_town` 32×32 хранит около 12 MiB voxel bytes;
load 1.0–1.3 с и save 0.14–0.17 с не обосновывают новую schema. Native mesher
обслуживает сухие чанки; water-bearing chunks сохраняют точную full-map
координатную проекцию шейдера без швов. Новая физика заменяет legacy collision
атомарно после полного rebuild.

Surface Canvas, Ember Graph, Object Inspector и bounded migration dashboard
находятся на stop-line. Общий polish не продолжается без конкретного production
workflow, который текущие инструменты не закрывают.

## Текущее состояние миграции G1/G2/G3

Read-only report и dashboard показывают ownership, состояние prefab, usage и
ошибки без записи canonical content. Strict dry-run сравнивает occupancy,
metadata, mesh arrays и collision до разрешения ограниченной batch mutation.

Текущий voxel ownership: 15 native / 162 legacy. Derived baseline: 63 ready /
25 stale / 88 missing. Шесть используемых sandbox-моделей и семь ready-моделей
`fan_town` перенесены ограниченными Undo/Redo batches. Остальные 25 scene-used
stale prefab меняют видимые грани, 18 — collision, поэтому их нельзя
пересобирать вслепую; это будущая visual review по необходимости production-зоны.

`ensure_saved()` идемпотентен для актуального prefab. Принудительный rebuild
разрешён только явной editor-командой или подтверждённой migration mutation.
Отключённый `at-icons` изолирован через `.gdignore`; автоматизация не запускает
live checkout с `--headless --editor`.

## Текущее состояние партии и exploration loop

Партия постоянна: протагонист, Мира, Орик и Сена. В мире выбранный лидер остаётся
единственным controller, а трое спутников — presentation-проекция безопасного
пути. `Tab` меняет лидера, `T` переключает живую формацию и «паровозик»; это
session-only state и не расширяет save v2.

Inventory/equipment, shop, HP/consumables, quests, action chains, dialogue и
переходы между картами существуют в graybox. Нативные catalogs являются
основным путём; оставшиеся `EmberPack` fallback удаляются только вертикальными
миграционными срезами после parity.

## Текущее состояние Combat Lab

Два dense-поля 10×8 и 16×12 используют одну проходимую высоту на колонку. Jump,
height-aware range, LOS, падение, толчок, подъём/бросок, pathfinding и AI проходят
через общие terrain/resolver rules. Последний измеренный E5 16×12 поиск unit-
целей для auto-approach занимает около 5 мс. Исправленный поиск cell-целей
занимает около 12 мс вместо 378 мс: он ограничен MOVE + authored range и один
раз кэшируется на UI-refresh. Оснований менять dense Battlefield нет.

Бой поддерживает:

- постоянную партию, STR/MAG/DEF/RES/SPD/ACC/LUCK, derived EVA/CRIT, HP/MP,
  equipment, XP/level-up и возврат результата в save v2;
- единый hostile RNG, зафиксированный в preview и применяемый без reroll;
  попадание, крит и урон не раскрываются игроку до commit;
- детерминированные поддержку, лечение, предметы, механизмы и устойчивости;
- Wet, Frozen, Burning, Guard и Overheated через canonical status Resources;
  пар/проводимость, Землю и Ветер — через reusable
  `status → effect → action → unit` Resources;
- три личных направления каждого героя и две authored парные техники с
  фиксированным партнёром, радиусом, общей MP-ценой и задержкой;
- предмет из общей сумки за полный ход с точным списанием одного stack;
- равный XP всем четырём героям, сохранение дефицита HP/MP и возврат павшего с
  1 HP после победы;
- поэтапный UI `browse → confirm action → target → commit`, корректный cancel и
  адаптивный список `Умения / Магия / Предметы` рядом с основным кольцом;
- свободный плавный yaw при заблокированном pitch по умолчанию, отдельный
  orthogonal toggle, независимые axis locks, authored camera values и отсутствие
  mouse-wheel zoom во время боя;
- общий positional auto-approach для непарных hostile/support/heal/item/cell/
  lift-команд: достижимая позиция завершает выбранную команду, а недоход
  останавливает героя и применяет Defend без расхода MP, item или команды;
- cell-target действия подсвечивают только клетки, где эффект выполним в этот
  ход после MOVE; lift-target остаётся на месте до завершения presentation-подхода;
- battle-only связь удержания без новых authored Resources: поднятая цель не
  занимает клетку и пропускает очередь, а носитель получает только синтетические
  `Бросить / Опустить / Удерживать и защищаться`; player и AI используют одну
  legality/preview реализацию.

Projection-only animation queue показывает движение, подъём, дугу броска,
выпад, hit squash и defend pulse после уже рассчитанного preview. Status badges
показывают тип и длительность buff/debuff. Эти проекции не мутируют snapshot.

Единая нативная библиотека `статусы / эффекты / умения и магия / герои и существа`
создаёт, дублирует и связывает canonical `.tres`, блокируя save при validation
errors. Новая низкоуровневая операция всё ещё требует реализации и targeted
resolver test; редактор не генерирует gameplay-код.

### Единый ActionPlan поверх v2.64.4 (2026-09-08)

`Grid.action_plan_context` кэширует navigation/movement fields и filters;
`Grid.action_plan` принимает клетку и возвращает `originCell`, `movementPath`,
`destination`, `applicationCell`, `effectCell`, `occupantId`, `cellContent`,
`footprint`, `ok`, `reason`, `commitRule` и приватный `resolved`. Старые
`approach_*_command_preview` — адаптеры этого входа. Выбранная AI-команда
проходит тот же вход с фиксированной позицией; scoring AI не переписан.
Существующий AI pursuit без authored команды сохраняет прежний movement-only
resolver result. Все legality rules остаются в Combat/Terrain, пути — в Grid.

HUD инвалидирует контекст при изменении snapshot или ручной клетки M, а смена
действия выбирает отдельный кэш. Mouse/keyboard cell hover обновляет только план,
подсказку и overlays. 3D переиспользует клеточные overlay meshes/materials;
2D меняет стили существующих кнопок. Hover не вызывает `_refresh()`, rebuild
GridMap/бойцов или polling. Public projection содержит только intent и footprint,
без hit/crit/damage и без зависящих от скрытого исхода cellChanges.

Первый lift-confirm сохраняет неизменяемый план и запускает отдельный Tween
представления поверх тех же unit roots. Подход завершается перед поднятием.
Cancel работает и во время подхода: цель возвращается, носитель идёт по уже
пройденной части маршрута обратно; ранее выбранное M сохраняется. До final
commit snapshot не меняется. Throw/Lower/Hold идут через тот же ActionPlan и
Combat.preview/commit; повторная цель подъёма на стадии броска запрещена.
Action/Effect/Battlefield/save schemas не менялись.

После сигнала завершения presentation HUD показывает существующее круговое меню
у фактической stop-cell носителя только с `Бросить / Опустить / Удержать +
защита`; прежний `CombatLiftChoice` остаётся скрытым. Выход из выбора клетки
броска возвращает это кольцо, а отмена уже из кольца откатывает presentation.
Gameplay resolver и schema этим UI-маршрутом не меняются.

Проверки: `test_combat_action_plan.gd` охватывает классы команд, M в исходной
клетке, revival через клетку, fallback и stale context; `test_combat_lab.gd` —
hover A-B-A, 2D без пересоздания кнопок, 3D без пересоздания units/input,
скрытые поля, lift approach/cancel, включая отмену в середине пути.
Baseline 16×12: cell-query 12.37 ms; после — 12.28 ms. Cached cell ActionPlan
5.04 ms. Forward+ smoke на RTX 5070 подтвердил рендер обоих полей и
обновление overlays; CPU обработчика hover около 9.8/18.1 ms (10×8/16×12).
Замер с ожиданием кадра 29.1/35.5 ms не равен стоимости запроса или среднему FPS.
Пройдено 24/24 combat/battlefield/encounter/party/save scripts (exit 0, без
SCRIPT ERROR/ERROR); после финального UI wiring повторены lab/animation/view.
Основной ActionPlan принят пользователем после ручной проверки в Forward+.
После переноса lift-завершений позиция, фокус и читаемость кольца дополнительно
приняты пользователем в реальном бою 8 сентября 2026.

### Production defeat/Retry lifecycle (2026-09-08)

Поверх checkpoint `4569f64` поражение отделено от persistent result commit:
`EmberCombatTransition.finish` принимает defeat как некоммитируемый исход, а
боевой HUD больше не возвращает нулевые HP/MP и потраченную сумку в мир. Retry
переиспользует уже существующие process-local party/inventory snapshots и
authored deployment, полностью пересобирает battle snapshot и создаёт новый RNG
seed; видимого предбоевого save slot и новой schema нет.

Вместо прежнего `Вернуться` defeat-modal предлагает `Повторить` или
`Загрузить сохранение`. Load-only панель показывает metadata трёх ручных слотов
и автосейва; загрузку и восстановление сцены по-прежнему выполняет единственный
`EmberExploreState`, а transition только проверяет target scene, меняет сцену и
очищает process-local combat handoff после успешного запуска. Пустой/недоступный
слот не уничтожает активную возможность Retry.

`test_combat_defeat_retry.gd` проверяет запрет defeat commit, неизменность
persistent owner и файлов сохранений после Retry, точное восстановление party,
inventory и deployment, новый seed, focus load-only панели, ручной слот,
автосейв и очистку handoff. Связанные combat lab, encounter transition, result,
party progression и save v2 gates также проходят; весь согласованный набор —
27/27 scripts. Обычный Vulkan Forward+ на RTX 5070 дошёл до load-only состояния
без renderer/script errors. In-engine capture 2560×1440 подтвердил отсутствие
clipping и видимый focus первого доступного слота. Реальный mouse/gamepad input
принят пользователем 8 сентября 2026.

### Предбоевая расстановка (checkpoint `e4b6b7e`, принята 2026-09-08)

Расстановка продолжает существующий Battlefield owner без новой schema.
`party_deployment_cells[0..N-1]` задают default positions активных героев; если
в массиве есть дополнительные клетки, весь массив становится разрешённой зоной
и Combat Lab открывает process-local prebattle phase. При ровно N клетках фаза
пропускается, поэтому `colored_crossing_demo` остаётся фиксированным обучающим
боем. У E4 `vertical_forge_10x8` сохранены прежние первые четыре позиции и
добавлена широкая зона слева для демонстрации.

Save v2 без повышения версии получил optional `battleStrategy`: это строгий
порядок четырёх hero IDs, нормализуемый `EmberPartyState`. Отсутствующее или
битое значение возвращает прежний combat roster order
`mira → orik → sena → protagonist`, поэтому старые saves не меняют authored
расстановку. `EmberExploreState` остаётся единственным mutable/save owner;
инвентарь редактирует draft и применяет его только кнопкой сохранения.
`EmberCombatTransition` передаёт глубокую process-local копию вместе с party и
inventory, а direct Lab читает тот же persisted preset из autoload без ownership.

Чистые eligibility/default/strategy/validate/move/swap/apply функции живут в
`EmberCombatGrid`. На поле с extra cells стратегия применяется до UI. Сначала
HUD показывает компактное окно ровно с `НАЧАТЬ БОЙ` и `ИЗМЕНИТЬ СТРАТЕГИЮ` над
полностью видимым полем без зоны и hero tools; оба режима блокируют timeline,
commands, AI, commit и RNG. Второе действие открывает прежний детальный режим с
бирюзовой зоной, mouse/standard focus/grid cursor, move/swap и Reset к persisted
strategy. 3D/2D projections получают только phase context; staged combat
projection явно отключена во всём prebattle, включая current actor.

Defeat Retry пересобирает прежние party/inventory/field с новым seed, применяет
последний confirmed placement и не открывает фазу снова. Обычный Lab Reset во
время active battle очищает confirmed choice, возвращает persisted strategy и
снова открывает ready. Exact-N поля игнорируют preset и оба режима.
Encounter/Unit/Action/Battlefield Resources не изменялись.

Все 20 `test_combat*.gd`, save/inventory/party progression/Battlefield gates и
два обычных Vulkan Forward+ запуска прошли. Captures подтвердили компактный ready
над полностью видимым полем и встроенный раздел «Стратегия» без clipping.
Реальная ручная приёмка мышью/клавиатурой/геймпадом и save/reopen через меню
подтверждена пользователем.

## Активная группа 1–4 — контракт 9 сентября 2026

`EmberExploreState.active_hero_ids` — единственный mutable owner состава.
`set_active_hero_ids(ids, autosave)` принимает 1–4 уникальных точных String IDs
каталога между боями; некорректный ввод или текущая транзакция отклоняются без
мутаций. Полная `party` сохраняет данные всех четырёх героев. Additive поле
`activeHeroIds` в save v2 хранит состав; отсутствие поля и повреждённое поле
целиком восстанавливают legacy четыре. Это recovery сохранения, а не сюжетное
событие. Load/adopt нормализуют лидера после полной установки данных, чтобы
синхронные UI listeners не вернули старую compatibility-проекцию.

Мир, followers, сумка, Tab/Q/E и стратегия показывают только active IDs. Уход
лидера выбирает первого активного без перемещения CharacterBody/камеры. Общий
сохранённый `battleStrategy` остаётся полным порядком четырёх IDs; UI переставляет
активную проекцию в прежних позициях active, сохраняя позиции отсутствующих.

Transition проверяет совместимость active subset с `Encounter.party_unit_ids`
и вместимостью поля до смены сцены; ошибки передаются existing interaction UI.
Состав копируется отдельно от полной party/inventory/strategy. Encounter
фильтрует authored roster до создания units/cells, сохраняя authored порядок.
Direct Lab/preview без world handoff сохраняет authored roster; legacy четыре
на exact-N поле по-прежнему фиксированы, пара на четырёх cells получает extra
deployment zone. Retry восстанавливает исходные состав, HP/MP, inventory и
confirmed placement с новым seed. XP/preview/result учитывают только участников
боя, включая павших; отсутствующие HP/MP/XP/equipment не меняются.

Автоматические gates расширены на одиночку/пару без protagonist, 1–4 состав,
setter/save corruption/load/adopt/metadata, inactive inventory, followers,
совместимость, production victory и pair Retry. Ручная Forward+ приёмка ещё
открыта. Новые story commands, reserve UI, герои и контент главы сюда не входят.

## Следующий технический срез

Актуальный порядок всегда берётся из `docs/EMBER_NOW.md`. Graybox-дизайн принят;
после приёмки активной группы следующий контракт — редактируемые квесты,
действия и сценки. Парные техники остаются на своём authored-радиусе; их
auto-approach не был добавлен скрыто. Текущие Action/Battlefield/save schemas,
один resolver и один navigation owner сохранены.

## Известные долги

- Нативных voxel Resources значительно меньше legacy-моделей; generated prefab
  не доказывает ownership.
- Physical world Surface есть у sandbox и `fan_town`, battle Surface — у
  `colored_crossing`; остальные карты ещё используют legacy terrain.
- Несколько catalog/loader классов всё ещё используют `EmberPack`; новые вызовы
  туда запрещены.
- 25 scene-used stale voxel prefab требуют visual review перед миграцией.
- Первый малый сквозной D3-участок ещё не собран.
- Финальный запуск без физически доступного sibling JOI не пройден.

## Проверки

Godot console: `tools/godot/Godot_v4.7.2-stable_win64_console.exe`.
Targeted scripts находятся в `tools/test_*.gd`; fixtures сохраняются в
`user://`, авторские карты не перезаписываются. Актуальные suites и ручные gates
перечислены в `MIGRATION_TEST_PLAN.md`.

Рабочий checkout нельзя запускать через `--headless --editor`. Изменения UI,
render, physics, input и игрового ощущения после headless gates проверяются в
обычном Godot 4 Forward+.
