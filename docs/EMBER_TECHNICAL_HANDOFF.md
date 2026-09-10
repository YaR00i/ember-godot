# Ember Godot — технический handoff

Актуально: 10 сентября 2026. Editor stop-line v2.56.1, gameplay baseline v2.64.4;
активная группа 1–4 реализована, ручная приёмка ещё открыта.

Документ описывает текущее устройство, owners и реальные долги. Полный прежний
текст можно восстановить из монолитного Git checkpoint `20685ac`; это не
детальная цепочка исторических commits. Журнал каждой версии здесь больше не
ведётся. Ближайшая задача находится в `docs/EMBER_NOW.md`.

## Источники правды

### Одиночный объёмный штамп — первая фаза (manual gate открыт)

Приняты два режима: Add заполняет только пустые целевые ячейки; Replace
переносит цвет и четыре материальных канала в занятые ячейки отпечатка, включая
очистку канала, отсутствующего у шаблона. Пустые ячейки шаблона не стирают цель.
Целевые groups остаются прежними; lock отклоняет затрагивающую его операцию.
Новые ячейки наследуют active merge part/Added, прежняя принадлежность заменённых
занятых ячеек не меняется. Вода/глобальный material/physics цели не переписываются.

Owners: `ember_voxel_stamp.gd` — capture через прежний FragmentExtract, чистый
plan и библиотека; `ember_voxel_stamp_preset.gd` — editor-only Resource с именем,
ссылкой на EmberVoxelModelResource и default anchor. Геометрия сохраняется как
новый `content/voxel_models/vox_stamp_*.tres`, preset — в
`content/editor/voxel_stamps/*.tres`. Source tags меняются на stamp, группы и
merge provenance шаблона очищаются: они не переносятся на чужой объект. При
ошибке записи preset геометрия оставлена для восстановления, сцена не меняется.
Выделение/открытие/preview файлов не создают. Загрузка пресетов использует
CACHE_MODE_IGNORE_DEEP, чтобы видеть отредактированную внешнюю геометрию.

`ember_voxel_stamp_panel.gd` — сохранить выделение, список/refresh, разместить,
редактировать модель. Редактирование использует обычный workspace.open_surface
с прежним navigation save/discard guard. Уже поставленные отпечатки — копии
voxel data, а не ссылки на шаблон. Preset geometry не является вторым renderer.

Размещение расширяет существующий SelectionInteraction: та же геометрическая
привязка/стрелки, число vox, quarter turns, отражение по одной выбранной оси,
anchor = нижний угол / центр основания / центр объёма. ЛКМ выбирает adjacent
для Add или hit для Replace; Enter — одно применение через SculptActions
apply_fragment, Esc — отмена. Source/scope change отменяет preview. Цветной
ghost показывает записываемые ячейки; shading preview условный (не полный remesh).
Ошибочный footprint красный. Кешированный plan применяется только при неизменном
source snapshot. Групповая маска/изоляция/скрытие пока явно несовместимы с этим
срезом; включение во время размещения отменяет preview.

Пределы: 1–32768 occupied voxels, одинаковая плотность 16/32 и material dictionary.
Out-of-bounds/срез, palette overflow, lock и несовместимость — атомарный отказ,
без скрытого обрезания и изменения размера. Large synthetic 16384 occupied /
131072 target cells: plan ~60ms; это не замер полной отзывчивости на Причале.
Пока нет непрерывного мазка, шага, 2D-маски с глубиной и resampling плотности.
Gate: test_voxel_stamp (capture, independence, channels/holes, both modes,
ownership, Undo/Redo, preset/target save/reopen, cache refresh, overflow/lock,
Canvas preview/commit/cancel/edit/discard); native -- --capture пишет
user://voxel_stamp.png. Связанные gates перечислены в MIGRATION_TEST_PLAN.

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

Resource schema 5 добавляет `merge_parts: PackedStringArray` и
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

Дополнительный mode 4 «Рамка по поверхности»: ember_voxel_surface_marquee
определяет входную грань ray/AABB выбранного hit-вокселя, фиксирует Plane и
пересекает последующие лучи с ней. Целочисленные bounds расширяются внутрь
на заданное число слоёв, без обхода рельефа. Существующий Selection.start_box
инкрементально выбирает только занятые ячейки внутри grid/region/slice/isolation.
Контур и preview используют те же bounds. Пустой старт/неоднозначное попадание
отклоняются; камера/режим/глубина при изменении отменяют незавершённый жест.
Никакой сохранённой schema или новой истории Undo для выделения не добавлено.

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
