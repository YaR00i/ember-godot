# Ember — актуальные проверки и migration gates

## Игровые системы — библиотека, экипировка, эффекты и статусы, user UI acceptance OPEN

`python tools/run_game_systems_tests.py` — disposable project с текущими native
item/combat/action/dialogue data. Headless navigation/search/empty/missing link,
equipment route как фильтр item, action → прежний combat editor, encounter → Inspector,
Lab → existing scene, existing ItemEditor close и unsaved dialogue guard PASS.
Frozen content/scenes/material hashes проверяются до/после; реальных saves/JOI нет.

`python tools/run_game_systems_tests.py --editor` — import только disposable,
реальный Forward+ editor/Ember plugin. Все modules/width, links/editor route,
item window close и фактические plugin disable/enable/remount/teardown PASS.
Снимки `user://game-systems-*.png`; user acceptance и удобство ещё OPEN.
1280×720 host/minimum width проверен без окна. Ручной узкий editor/125% OPEN:
диагностический runtime mode/resize после внешнего item Window застопорил
ожидание capture, поэтому этот probe не считается PASS. Лог сохранён отдельно
в Temp/ember-game-systems-editor-resize-diagnostic.log; рабочий editor не затронут.
`python tools/run_game_systems_tests.py --operations` — copy/create draft всех
native kinds (equipment — item subset), no file before Save, local Undo/Redo,
validation/collision, Save/reopen/UID и exact-byte publication Undo/Redo.
Internal loot rows/arrays независимы; external effect refs остаются общими.
File/live-source conflict не перезаписывает чужие правки. Delete fixture проверяет
exact backup, Undo bytes и refusal при incoming ID; search/navigation/Cancel
не скрывают dirty draft. В конце test copies удаляются, frozen inputs неизменны.

Forward+ editor gate проверяет общий draft field UI, Undo/Redo и реальный Save/
reopen, публикацию в GLOBAL_HISTORY=0 без карты и фактический publication Undo/
Redo; затем plugin unload/reload. Новый Resource context был scene-bound; его
заменил RefCounted context, это проверяется по actual history ID и file effects.
Capture использует force_draw нативного viewport, поскольку ожидание post_draw
при idle отдельном Window может не завершиться; это не подавление save/errors.
Связанные native item authoring/binary PCK, Graph workspace/lifecycle PASS.
Этап 3: один item screen/Store, фильтры и Create по типу; формы всех семи kinds.
`--operations` проверяет guard/Cancel dirty filter, возврат списка после close,
один Undo numeric input, hidden armor metadata/bonuses/extension metadata, unknown
allowedHeroIds и native Save/reopen всех новых доступных настроек. Signed max
HP/MP и совместимость проверяются через прежний PartyState; delay/range/restore
расходника — через реальный combat command/preview/commit с расходом одной штуки.
Armor без текущего/legacy допустимого slot и нулевая задержка отклоняются. Forward+ captures показывают
общую библиотеку, расходник и gear draft; при draft список скрыт, ширина формы и
hub проверена в настоящем 1600×900 editor. Пользовательский narrow/125% gate OPEN.
Этап 4: `python tools/run_party_tests.py --test test_equipment_layout.gd` —
weapon/armor/shoes/accessory1/2, universal accessories, restricted footwear,
два одинаковых аксессуара, explicit target/wrong-slot refusal и owned refunds
без stackMax truncation. Native UI target доходит до прежнего Explore owner.
V2 old layout: weapon сохранён, body/accessory переименованы, head/arena/unknown
IDs возвращены; level/XP/HP/MP/flags сохранены. Load source bytes неизменны,
repeat normalize/load не дублирует вещи; corrupt migration backup блокирует
Save. Успешный Save оставляет exact SHA backup; новый layout повторно загружается.
`--visual --test test_equipment_layout.gd` — Forward+ menu/capture, пять слотов и
explicit accessory2. Текст переносится; content scroll удерживает узкое меню
внутри панели, width guard PASS. Полный party suite (6 gates) PASS.
`--operations` также проверяет editor-only примерку: published → draft delta,
герой/уровень/исходный комплект, incompatibility, accessory2 и сохранение контекста
при Undo без dirty/serialization leak. `--editor` проверяет то же в настоящем
Forward+, captures fitting/fields и фактический plugin reload/global Undo.
`python tools/run_game_systems_tests.py --regressions` — publication faults,
restart/delete, progression, combat items/result/prototype; fault gate принимает
ровно 10 объявленных injected write errors и отклоняет неожиданные ошибки.
Save-publication map fixture теперь native user:// вместо retired agent_sandbox.
Связанные retired destination/pause/transition/defeat, items/PCK/Graph и
`python tools/test_vox_axes.py` PASS. 691 original author inputs неизменны.
User acceptance/narrow/125% OPEN. Footwear MOVE/JUMP/knockback/wet modifiers и
авторские стартовые комплекты ещё не реализованы.

Этап 5: `python tools/run_game_systems_tests.py --statuses` — новый native статус,
apply/remove effects и composed action создаются через общий Store/Session.
Default duration, все четыре reapply policies, cap, resistance, self-action
decay/expiry проверяются через настоящий Combat.preview/commit. Power/outgoing/
incoming modifiers, removal от ненулевого damage и сохранение при zero damage,
порядок apply→remove/remove→apply, invalid Resource/dependent effect/runtime и
stale statusRulesHash guard PASS. Snapshot остаётся ID→turns; baseline defaults
не меняют старые пять специальных реакций. Отдельных стаков/periodic damage нет.
Проверены все восемь operation-specific форм, скрытые значения, именованный
status picker/checklist, field Undo/Redo, точные publication bytes/UID/Undo/Redo,
native Save/reopen и удаление fixtures в обратном порядке зависимостей.
`--editor` дополнительно проверяет status rules через native controls/Undo/Save/
reopen и effect picker/checklist/operation switching, captures status-rules,
status-modifiers, effect-status/effect-remove. Настоящий Forward+ 1600×900 PASS.
`--regressions` включает Status Resource, Effect Library, Action Resource, Grid,
ActionPlan и Personal Actions. Combat Lab отдельно PASS в disposable Forward+
1600×900: headless запуск дал пять layout failures, оконный gate их не повторил.
Исходные
авторские данные не меняются. Manual feel/UI/narrow/125% остаются OPEN.

Этап 6: `python tools/run_game_systems_tests.py --actions` — native constructor
создаёт лечебный EFFECT_CHAIN, выбирает shared effects, блокирует дубли,
переставляет/удаляет шаги с Undo/Redo. Incompatible saved force видим и может
быть исправлен; неверный draft не публикуется. Text conditions явно informational.
Save/reopen сохраняет порядок/shared refs, publication Undo/Redo — bytes/UID;
Discard не меняет published MP. Новый Unit выбирает приём по имени, сохраняет
порядок, Undo/Redo, удаление и unknown-ID correction. Затем настоящий grid бой
читает native assignment: MP cost/menu/range/target/effects/delay/preview purity
и commit PASS. Дальность проверяется в grid, D1 zones не считаются distance gate.
`--editor` проверяет constructor/steps/assignment controls, Save/reopen/Undo и
ширину 1600×900; captures action-constructor/action-steps/action-assignment.
Переключение session не направляет changed в old queued form. Native Forward+
и related operations/status/save/combat regressions PASS; manual UI gate OPEN.

Этап 7: `python tools/run_game_systems_tests.py --encounters` — new native loot
с двумя item rows/chance/count, internal copy-on-edit, numeric Undo/Redo, invalid
range/missing item refusal, exact publication bytes/UID, Save/reopen. New enemy
выбирает AI по ID и shared loot; inline current ref не пропадает, Discard не
меняет HP. Encounter выбирает field/arena refs и ordered rosters с правильной
стороной/без дублей, Undo/Redo и correction неподдерживаемого outcome enum.
Reopen → native deployment order → Grid.enemy_command без source mutation →
Result.build: guaranteed loot, deterministic repeated projection, equal XP
каждому из двух героев; поражение без victory XP/loot PASS.
`--regressions` включает Unit/AI/Loot/Encounter Resource gates вместе с прежним
save/result/combat набором. `--editor` — native loot controls/Undo/Save/reopen,
shared enemy refs и roster/order/XP через настоящую форму, width/lifecycle PASS.
Captures loot-rows/enemy-links/encounter-summary/encounter-roster. Исходные author
inputs заморожены. Полный запуск выбранного draft в Lab — этап 8; user feel,
manual Save/Load/reward return и narrow/125% остаются открыты.

Этап 8: `python tools/run_game_systems_tests.py --lab` — только disposable import,
saved synthetic Encounter с Mira/Wisp и 9 XP, настоящий runtime process Forward+.
Autoload до чтения saves имеет persistence/restore off и private paths. Проверены
request/path/duplicate-arg guards, native selected ID/roster, private party/inventory,
victory/defeat/result/Retry, отсутствие gameplay Load/transition/reward application.
Save/autosave не создают файлы; sentinel по default save path не меняется, private
progress snapshot неизменен (сравнение исключает только timestamp savedAtMs).
Captures library-lab-battle/victory/defeat. Исходные content/scenes/materials frozen.
Default navigation gate проверяет Lab button и refusal dirty draft. `--editor`
создаёт saved encounter fixture и запускает его настоящим adapter: проверяет
consumed ID в child log, duplicate-window guard и завершает только свой child.
Windows log проверяется также после закрытия child handle (active log может быть
buffered/locked); default copy/cache/user saves не используются. Capture lab-launch.
`--operations`, `--regressions`, `python -X utf8 tools/run_save_destination_tests.py`
PASS — в том числе normal encounter return/reward once/defeat retry/save load.
Manual authored launch/play/result/Retry/Close и полный save/use/result/load OPEN;
тест пока saved-only, без персональной прокачки/сумки и декоративной смены арены.

Общая проверка библиотеки: `python tools/run_game_systems_tests.py --check` —
disposable fixtures с duplicate ID в двух точных файлах, filename/envelope
mismatch, missing ID/external dependency, unsupported enum, wrong Resource и
wrong nested effect. Отчёт читает saved data при изменённом cached Resource;
source hashes и parent dirty cache неизменны. Duplicate start блокируется,
проверяются search/exact path и dirty navigation refusal. Utility использует
существующие validators; SCRIPT ERROR в child log означает incomplete report.
`--editor` дополнительно проверяет настоящий Forward+ scan с dirty draft,
readable bounded feedback/report, FileSystem selection и Inspector exact filepath
для дубля; captures library-check-dirty/report. No auto repair; discard остаётся
явным действием. Service process пропускает gameplay save restore и MCP shared
ready registration. Read-only проверка рабочего saved каталога: 71 запись,
0 issues; author hashes сравниваются отдельно. Это охват девяти game-system
roots + icon/story ID/dependencies, не full story validation, баланс или dead code.
Ручная оценка удобства отчёта/узкого editor/125% и прежние authored gameplay
gates остаются OPEN; green data report их не закрывает.

## Роли и текстуры компактной земли — ручная приёмка OPEN

Боковые параметры + нижняя сетка (2026-10-07): `test_compact_material_dock.gd`
PASS — 302 px/шрифт 20 px, видимая сетка/закреплённый Save, повтор/сворачивание,
dirty switch с Save/Discard, запись исходного opened_path, локальная история,
stale Save не теряет draft, inline new name, Cancel/Reopen. Основной patterns
suite PASS (drag, side fallback, PNG, tones/finish, variants, atlas). Native
`editor_test_compact_material_dock.gd` PASS в изолированном Forward+ 1600×900/125%:
реальная двухпанельная компоновка с видимой сеткой, drag/фокусный Ctrl+Z/Y,
PNG обеих граней, сохранение/переключение/Cancel/Reopen, collapsed draft,
viewport/command guards, первоначальный слот при изменении palette selection,
EditorUndoRedoManager назначения, Save/Reopen/terrain Discard, scene switch
с сохранением material draft и отказом назначения чужой карте, без terrain write
или remesh. QA-only variants имеют уникальные ID; авторские варианты не меняются.
`+ Карта` также PASS в связанном native regression. Авторская приёмка UI/фактуры,
глобальное обновление второй живой карты, weak PC и узкий shell OPEN.

`test_compact_material_patterns.gd` проверяет общий ресурс 16×16,
validation, покраску клетки, Undo/Redo редактора, Cancel без записи,
сохранение/повторное открытие в `user://` и обновление texture uniform.
Также проверяет необязательные бока, переключение граней, Undo к пустому
fallback, PNG выбранной грани и её атлас. Исходные RGBA8-тона при экспорте и
импорте совпадают даже после дробного ColorPicker-значения.
`capture_compact_material_relief_swatches.gd` проверяет Forward+ рельеф и Sun
на четырёх материалах; `capture_compact_material_relief_study.gd` снимает
одну землю/камеру/свет/фазу воды с исходными и новыми вариантами.
`test_compact_material_light.gd` проверяет панель трёх вариантов, серый режим,
SSAO, Undo/Redo, Save/Reopen/Discard, наследование runtime uniforms и отсутствие
remesh/recollision/изменения terrain. `test_world_look_panel.gd` сохраняет
регрессию света/воды/их сохранения. Native QA проверяет те же controls через
EditorUndoRedoManager, Save, новый процесс/Reopen и настоящий F6.
`capture_compact_material_light.gd` снимает три варианта на той же геометрии,
палитре и камере; отдельные одноцветные swatches, Sun/camera и AO on/off.
В живой `compact_material_light_study.tscn`: «Вид мира → Материалы»,
переключить 0/1/2, отдельно отключить AO, вращать Sun и камеру. В сером режиме
должна читаться разница отделки; в пластике — подвижный блик покрытия.
Ctrl+S → F6 → Reopen должны сохранять выбор. Изменение F6-пробы не записывается
само; постоянный вид выбирают в редакторе. Вращение не меняет физическую поверхность.
Скругления геометрии/volumetric fog не заявлены. Технические gates PASS,
ручная художественная оценка с игровой камеры и стоимость на слабом ПК OPEN.
Трава/грунт (2026-10-09): test_ground_material_surface PASS — finite/ranges,
legacy default0, одинаковые palette/top/side artwork, semantic/detail lookup,
controls только grass/soil, no-remesh и scene Save/Reopen. test_compact_material_
patterns/dock/light и WATER_MATERIAL PASS; три новых поля входят в draft Undo/
Redo/Save/Cancel. editor_test_ground_material_surface PASS на одной 8м isolated
Forward+ сцене/30FPS: реальные panel routing/три доступных слайдера/pinned Save,
Undo/Redo, fresh-disk file/reopen/cancel, scene history/Save и настоящий F6.
Та же source scene/варианты/lookup проверены внутри настоящего PortableQA PCK.
7 runtime+2 editor PNG/manifest/ZIP — art/references/ground-surfaces-20261009;
evidence — user://ember_terrain_diagnostics/ground_surfaces_20261009.
GPU details on/off median0.342/0.328мс, p950.358/0.348, 90кадров/1920×1080/30FPS,
17draws; это малая RTX5070 проба, large map/weak PC OPEN. Native42.2с,
VRAMsystem3057→4317MiB/GPU23%/48°C, новых153/4101 нет; scan-aborted при close OPEN.
Manual: ground_material_study → F/G/L/ПКМ, сравнить силу/размер/свет/near-far/швы;
Редактировать мир → Цвет → grass_surface/soil_surface → Рисовать паттерн… →
новые три поля → Save/Cancel/Undo → Ctrl+S/F6/Reopen. Перенос на свою карту и
художественная оценка OPEN. Световой рельеф не меняет силуэт/physics; wind/grass
geometry/weather/sand/water/generator и optics pixelization остаются позже.

Independent surfaces: test_material_surface_layers PASS — optional fields/
finite/ranges/levels, legacy fallbacks/baked uniform default, palette-independent
relief/roughness, atlas binding, same terrain geometry, per-layer/per-face stroke
Undo/Redo/PNG/Save/Cancel/Reopen. Pattern/dock/light/ground/WATER_MATERIAL regressions
PASS. Native editor_test_ground_material_surface на GroundFinishStudy: слои,
независимость цвета, relief Undo/Redo, roughness side PNG, новые scalar params,
Save/fresh disk/Cancel/Reopen, no-remesh/3D/F6 grass_impasto PASS; PortableQA PCK
проверяет тот же тест новых data/legacy. Art gallery surface-layers-20261009:
7runtime+2editor PNG/ZIP; evidence surface_layers_20261009. Native36с/VRAMsystem
2882→4075MiB/GPU12%/45°C, новых153/4101 нет; прежний scan-aborted/stamp OPEN.
GPU отделка on/off median0.357/0.329мс, p950.361/0.332,90frames/30FPS/17draws.
Manual: ground_finish_study F/G/L/ПКМ → новая трава/грунт и old control; в панели
Цвет → Рисовать паттерн… выбрать слой и грань, проверить реальный mouse stroke,
Undo/Save/Cancel/PNG/Reopen; shadow/reflection feel, швы/near-far/weak PC OPEN.
Отделка не меняет geometry/collision, полный catalogue не переносится автоматически.

Painted grass: test_ground_material_surface также проверяет validation,
прежнюю палитру, отдельный top/side рисунок, совпадение terrain geometry/soil IDs
двух проб PASS. Native тот же driver с EMBER_GROUND_STUDY_PATH=painted scene:
panel/Undo/Redo/Save/fresh disk/Cancel/Reopen/3D/F6 PASS; runtime grass_id=grass_painted.
PortableQA PCK проверяет оба источника/варианты. Evidence painted_grass_20261009,
PNG/manifest/ZIP art/references/painted-grass-20261009. Native38.6с/3094→4267MiB/
GPU17%/46°C, новых153/4101 нет. Художественная оценка мазков/повтора/side/near-far,
перенос на авторские карты и weak PC OPEN; shader normals не меняют geometry/physics.

Материалы объектов (2026-10-09): role/cache/remap/geometry/COLOR/collision,
lighting presets/manual Sun/one Undo/no-remesh, generator editing и merge PASS.
`test_voxel_optics.gd` PASS: optional types/ranges/finite/unknown finish, четыре
resolved профиля, source deepcopy/TRES/HTML colors, opt-in shader, compatible merge
и отказ несовместимых stamp/merge; uniform/profile Undo/Redo, save-off-reopen-enable
без mesh/source changes, same-family regeneration сохраняет авторскую оптику.
Exact before/after всех шести примеров: sources/palette/alpha/vertices/normals/
COLOR/CUSTOM0/indices/transforms/collision PASS.
`editor_test_object_material_study.gd` PASS: одна isolated Forward+ сцена/30 FPS,
Inspector/light/optics/profile routing, Undo/Redo, Save/fresh-disk/Reopen/Discard;
F6 наследует оба профиля/probe_kind/neutral light/strength/seed/colors. Оптика,
сохранённая выключенной, включается после reopen без remesh.
`test_object_material_study_export.gd` PASS в настоящем PortableQA PCK: шесть
baked mesh/custom stream/material/collision/source без каталога/генерации.
Export/shader compile без ERROR. Evidence:
user://ember_terrain_diagnostics/object_finishes_20261009; 9PNG/manifest/timing и
ZIP — art/references/object-finishes-20261009. GPU median details on/off при
1920×1080/90 кадрах после прогрева: 0.483/0.470 мс, p95 0.788/1.003; 102 draw calls.
Разница на уровне шума RTX5070 пробы; большая карта/weak-PC budget OPEN.
Native editor49с: VRAMbaseline3306/peak4593MiB, GPU28%,52°C, новых153/4101 нет.
Прежние editor-close get_node-outside-tree/scan-aborted и шесть stamp pointer-line/
draft-Undo FAIL остаются OPEN.
Ручной gate: object_material_study → корень → Inspector → «Профили льда и кристалла».
Сравнить четыре профиля на сростках и probe_kind простой формы; повернуть свет/
камеру, оценить тонкие трещины/пузырьки/неровность блика и устойчивость вдали,
cloud/scale/seed/colors, преломление фона, предмет впереди/позади, края/воду/стекло.
Ctrl+S → F6 → Reopen сохраняет выбор. F — профили, C — clouds, O — оптика,
R — искажение, 1/2/3 — свет; runtime выбор временный. Авторская художественная
оценка, масштаб/движение, реальные модели/массовый rebuild/weak PC OPEN.
Screen capture не содержит других прозрачных объектов; thickness/две внутренние
пробы — приближение, полного объёмного многослойного преломления нет.
Wind/terrain-sand/volumetric light отложены.

`test_party_followers.gd` проверяет рост заглушек и смену высоты коллизии
лидера вместе с героем.
В живом 3D-редакторе: «Цвет» → роль и вариант → «Рисовать паттерн»;
вести непрерывный штрих по сетке Canvas, взять тон правой кнопкой,
изменить все три цвета, отменить/повторить, нажать «Отмена» без сохранения и
проверить старый рисунок. Экспортировать PNG 16×16, изменить в Aseprite
только тремя тонами, импортировать и сохранить. Создать `grass_autumn`,
добавить материал карты копией травы, назначить новый вариант и покрасить
рядом с обычной травой. Проверить Undo/Redo назначения и добавления слота,
Save/Reopen, вторую карту с тем же вариантом и отсутствие изменения весенней
травы при правке осенней.
Проверить Миру как лидера и follower рядом с блоком высотой 1 м: высота
должна читаться около 1,5 блока, коллизия и проход под навесом — как в кадре.

`test_compact_map_creation.gd` проверяет роли и варианты новой карты, validation,
назначение в 3D UI, Undo/Redo, Save/Reopen, пробу поверхности, передачу слота
в mesh/шейдер, два вида травы в атласе и отсутствие перестройки tile при смене варианта.
`test_compact_world_map.gd` проверяет,
что старый берег без ролей сохраняет прежнее поведение; расширение карты
сохраняет таблицу ролей через `test_compact_map_extension.gd`.

В обычном Forward+ открыть новую compact-карту: на земле должны быть видны
стилизованные рисунки травы, грунта, песка и камня на верхних и боковых гранях.
Проверить с игровой камеры масштаб рисунка, повторение без заметных швов и
новую воду в движении. В «Редактировать мир» → «Цвет» должны быть
`Грунт`, `Трава`, `Песок`, `Камень` со свотчами. Смена роли выбранного цвета
должна менять рисунок всех его ячеек сразу, без перестройки tile. Проверить
Ctrl+Z/Y, Ctrl+S и повторное открытие.
На старом `landscape_compact.tscn` роли не должны угадываться по оттенку;
назначить роль вручную и увидеть соответствующую текстуру; проверить
Undo/Discard без изменения исходного Resource. Автоматические тесты и runtime
Forward+ кадр не закрывают художественную приёмку в живом 3D editor.
Сравнить `scenes/new_landscape4.tscn` и
`scenes/compact_terrain_lighting_study.tscn` на одной камере: объём боковых
граней, читаемость теней и насыщенность песка/травы. Study-сцена использует
тот же Resource земли, но отдельный свет; перенос света на карты требует
ручного художественного решения.
В «Редактировать мир» справа открыть «Вид мира»: проверить силу и тон
солнца/окружения, поворот/высоту солнца, размер/мягкость и выключение теней, яркость, контраст и
насыщенность. Сравнить боковые грани на одном ракурсе с выключенными тенями:
они должны остаться видимыми гранями, без чёрных провалов. Изменить параметры,
проверить Ctrl+Z/Y, Ctrl+S, повторное открытие этой карты и независимость
другой карты. Проверить редактор и F6, а воду — в движении у берега.
`test_world_look_panel.gd` покрывает Undo/Redo и save/reopen значений,
`test_diorama_materials.gd` — применение света без записи в authored поля,
`test_water_material.gd`, `test_water_flow.gd` и `test_water_pattern_seams.gd`
— новый материал. Полный прибой на компактной карте этим срезом не заявлен.
Прежний runtime Forward+ замер `new_landscape4` (48×48 блоков, 144 tile)
на одинаковой камере: 117 видимых draw calls в обоих вариантах, медиана
GPU кадра 0,343 мс с четырьмя текстурами и 0,331 мс с пустыми ролями.
Новый атлас вариантов отдельно не профилирован. Это только standalone окно
при параллельно открытом редакторе, не его FPS.

## Landscape Compact в обычной карте и 3D-редакторе — ручная приёмка OPEN

`scenes/landscape_compact.tscn` связывает одну карту с собственным
`content/world_terrains/landscape_compact.res`. Старые Test Pier, World Canvas,
Landscape V2 Experimental и их dense Surface не меняются. Источник пилота
`content/terrain_pilot/beach_region.res` также не публикуется этой сценой.
В этой карте `Map.compact_terrain` заменяет dense ground; предметы по-прежнему
являются scene-owned voxel-объектами. Для боя отдельной смены owner ещё нет.

Автоматика: `tools/test_compact_world_map.gd` проверяет единственный источник
земли сцены, mesh/collision, пробы высоты/воды, попадание кисти, UI маршрутизацию,
мазок/Undo/Redo/Discard, Save/Reopen и откат Resource при ошибке сохранения сцены.
`tools/test_compact_brush_overlap.gd` сравнивает оптимизированный повторный мазок
с полным обходом для подъёма, опускания и неровностей, включая Undo/Redo.
`tools/test_compact_brush_scale.gd` сравнивает крупный и детальный режимы на
ровной карте, проверяет 2×2-группы и шаги высоты ¼/½ блока, два последовательных
шага по 4 вокселя, квадратный и круглый
след, крупную покраску и воду без изменения высоты, непрерывность длинного
мазка, Undo/Redo и save/reopen. `tools/test_compact_map_creation.gd` также
проверяет общие элементы профиля при переключении формы/цвета/воды в 3D UI.
`tools/test_compact_world_map.gd` также замеряет 16 последовательных движений
кисти в 3D-вкладке с обновлением tile между событиями и проверяет наведение
на верхнюю грань и бок ступени до перестроения её коллизии.
`tools/test_compact_hover_pick.gd` проверяет попадание в 49 точек ровной карты
по лучам камеры: выделение не должно притягиваться к переднему краю.
`tools/test_compact_large_profile.gd` создаёт только в `user://` временную
карту 1536×1600 ячеек (16× площадь берега) и проверяет reload, первый и полный
прогруз, длинный мазок «Неровностями» радиуса 4, Undo/Redo. Headless baseline
на 2026-09-27: 600 tile, Resource load ~9 мс, первый tile ~12 мс, все tile
~5,2 с, первый отпечаток ~23 мс, худшее из 16 движений ~12 мс. Это профиль
земли без города/объектов и не прогноз FPS живого редактора.
`tools/test_world_editor.gd` подтверждает прежний dense редактор и его общую
транзакцию; `tools/test_terrain_pilot_brushes.gd` — математику рельефа. Hidden
Forward+ `tools/prototypes/qa_landscape_compact_capture.gd` загружает карту с
героями без legacy JSON и сохраняет `user://landscape_compact_capture.png`.
Снимок подтверждает запуск и видимую землю, но не заменяет живой 3D editor.

Ручной gate: пользователь проверил UI и рисование на новой ровной карте в
обычном Godot: интерфейс в целом подходит, задержка мала, но тонкие ступени
«Поднять» и «Неровностей» слишком шумные. Для следующей приёмки после
 перезапуска Godot сравнить «Основной · 2×2» (четыре квадрата 8×8 вокселей
 на блок) со ступенями 4 и 8 вокселей, «Средне · 8×8» и «Детально · 16×16»,
а также «Форма · квадрат» и «Форма · круг»: на ровной карте сделать одинаковые
 мазки «Поднять» и «Неровности», оценить силуэт издалека и вблизи, тёмные
 границы ступеней и плавность во время движения. При наведении должны быть
 видны полупрозрачные белые границы блока 16×16 и четырёх квадратов 8×8
 с мягким затуханием за жёлтым контуром кисти. При смене радиуса 0,5/2/4/8
 блоков белая сетка должна расширяться и сужаться вместе с ним, выступая
 примерно на два подблока; выбранная кистью клетка — жёлтая.
 Поводить курсором через центр, углы, края и
 ступени и по свежему мазку: сетка не должна пропадать или просвечивать сквозь
 ближнюю землю, мягкий контур должен совпадать с реальным охватом кисти.
 После этого переключиться на
 «Цвет» и «Вода» в основном режиме: квадраты должны окрашиваться и заполняться по
той же сетке, сохраняя уже нарисованные перепады высоты.
Затем проверить ранее открытый сценарий:
открыть `scenes/landscape_compact.tscn` в обычном Forward+ редакторе,
включить «Редактировать мир», провести длинные мазки «Рельефом» и
«Неровностями» радиуса 1–4 блока, затем проверить радиусы 1/2/4/8, мягкий рельеф,
площадку по точке и заданной высоте, крупность/деталь неровностей, сглаживание,
покраску и воду; убедиться, что предпросмотр и сохранённый результат совпадают.
Провести большой и длинный мазки, оценить задержку и швы участков. Проверить
 Ctrl+Z/Y сразу после отпускания мыши и после выхода курсора за пределы вида,
 Ctrl+S, закрытие/повторное открытие, Discard и аварийный черновик. В Output не
 должно появляться «Невозможно отменить, пока нажаты кнопки мыши».
Поставить voxel-объект на землю, сдвинуть его и индивидуально отредактировать.
F6-ходьбу героев по берегу и воде проверить отдельным игровым gate после нативной
3D-приёмки. Старую Surface не должно быть видно или физически ощутимо в этой карте.
Без ручной проверки срез остаётся кандидатом.

## Новая компактная карта · ровная земля — ручная приёмка OPEN

Боковой вход «+ Карта» (2026-10-07): `test_compact_map_dock.gd` PASS —
302 px/шрифт 20 px, pinned actions при прокрутке, flat/coast/long ID,
no-preview-writes, reopen того же candidate, изменение поля инвалидирует preview,
Create сохраняет точные данные после прежней конвертации в sections, duplicate и
Cancel. `test_compact_map_creation` / `test_compact_map_coast` / section selection
PASS. `editor_test_compact_map_dock.gd` — только disposable Forward+ 1600×900/125%:
создание и открытие, вне edit mode/без Map, повторный «+ Карта», validation/duplicate,
Cancel с dirty terrain и несохранёнными параметрами генератора, возврат страницы,
камера/input guard, Undo/Redo/Save/Reopen/Discard, scene switch — PASS.
Связанный native `editor_test_terrain_dock.gd` после переноса также PASS для
«+ Участок»/repeat/preview/Apply/Cancel/Undo/Save/scene switch. Старые неисправные
qa_selection experiments временно исключаются из импорта, затем ignore снимается.
`test_compact_dialog_layout.gd` проверяет новое создание, но его прежний gate
legacy address-extension Window ≤500×320 FAIL: фактически 446×423. Отдельная
baseline-проба без новой панели воспроизвела тот же размер; legacy окно в этом
срезе не менялось. Этот тест целиком не считается PASS. Ручная приёмка нового
входа «+ Карта» и весь shell при 1280×750/125% OPEN.

Адресная основа (2026-10-03): новые карты сохраняют schema 2 прежнего terrain
Resource, плотная schema 1 читается без миграции при открытии. Перевод черновика
при добавлении отдельного участка публикуется только явным Save.
`test_compact_map_sections.gd` проверяет все каналы/flow/боковые исключения,
неполный край и свободный адрес, пустоту без mesh/коллизии, отдельные версии
payloads для кисти/Undo/Redo/cancel/cap, Save/Reopen/Discard, immutable recovery,
смену палитры, физическую высоту и navigation у стыка и вдали от начала координат.
Шесть участков в оболочке 528 м дают 216 tile вместо полной сетки.
`editor_test_compact_map_sections.gd` включается только в одноразовой native
Forward+ копии: диалог/отмена/геометрическое preview=Apply, часть края,
западный сдвиг и Undo, заполнение пустого адреса, EditorUndoRedoManager,
кисть через стык, Save/Reopen/Discard и настоящий F6. Playback fixture
`test_compact_map_sections_playback.gd` провёл обычного персонажа с X=720 до
X≈812 через границу X=768; физический пол совпал с terrain (Y≈12).
Дополнительный regression: несохранённый north resize → Discard возвращает
размер и anchors, сохраняя независимый сдвиг Props; recovery → Discard делает
то же. Повреждённая layout metadata отвергается без изменения сцены. Save/Reopen
принимает новый baseline. Native проверяет mismatch 72×48 / 48×48 → явная
кнопка исправления → Undo/Redo → обычный preview/Apply, затем resize/Discard/F6.
Действующий вход «+ Участок» проверяется `test_compact_section_selection.gd`:
signed адреса, несколько новых участков, сохранение занятой земли/потока/каналов,
общий seed независимо от бюджета, переход, cancel/validation/stale candidate,
мировые позиции при росте слева/сверху (включая повёрнутый Map), единый Undo/Redo,
recovery/Discard и Save/Reopen. `editor_test_compact_section_selection.gd` в
disposable Forward+ проверяет настоящий input, Enter/Back/Esc/камеру, occupied
отказ, смешанное выделение, preview=Apply, единый native history и два пути Save
с открытым preview без сериализации временных transforms; Discard/Reopen и F6.
Подтверждение проходит через `get_ok_button().pressed`, включая внутренний
обработчик AcceptDialog: после успеха окно закрыто, при stale candidate остаётся
видимый отказ без изменения земли. `-- --confirm-button-regression` сокращает
прогон до проверки настоящей кнопки и числа участков 4 → 7. Прежний прямой вызов
`confirmed` обходил закрытие окна и не покрывал пользовательское применение.
`-- --section-budget-regression` проверяет первый Apply → повторный «+ Участок»
без выхода из редактирования → открытие параметров, затем отказ большой области
через настоящую кнопку Next и действующий water owner. Окно причины видимо,
не больше 560×320, показывает размер/120 м; выделение, Resource и файл не меняются.
После закрытия можно выделить меньшую область и снова открыть параметры.
Native regression воспроизводил скрытый отказ до fix, после fix прошёл;
снимок самого окна проверен. Ручная оценка в авторском редакторе OPEN.
`test_compact_section_selection_playback.gd` проверяет ходьбу и коллизию новой
земли слева/сверху после runtime загрузки. Native панель/параметры прошли 125%
в 1600×900 и 1280×750. Прежний адресный fixture обращается к внутреннему adapter,
он больше не описывает основной пользовательский вход.
Ручной gate: «+ Участок» → щелчок или протягивание пустого места → «Далее:
рельеф и вода» → параметры/preview, назад/отмена/Apply, кисть через шов,
Ctrl+Z/Y, Save/Reopen и F6. Авторская оценка удобства/формы стыка и слабый ПК OPEN.
Заполненные 256 м terrain/water измерены отдельной render fixture, см. ниже;
512 м, плотные объекты, большой настоящий F6 и слабый ПК OPEN. Прежнее ограничение
плотных полей 120 м заменено regional water owner с ограниченной оболочкой 528 м;
она не является автоматической приёмкой масштаба и производительности.

Общий panel host (2026-10-07): `test_world_panel_host.gd` PASS для единственного
active route, repeat без сброса, pending guard, reentrant Cancel, stale close,
точного восстановления toolbar/workspace, numeric focus, camera/history,
scene-bound Cancel и независимого material draft. `editor_test_world_panel_host.gd`
PASS в disposable Forward+ 1600×900/125% для шести routes: взаимные переходы,
guards, повтор «+ Карта»/кисти, возврат Tools/Рельеф и отсутствие source/mesh/transform
изменений. Все семь прежних native dock suites PASS: terrain/map/material/object
brush/placement/shape/duplicate; Undo/Save/Reopen/Discard/Create→Canvas сохраняются.
Некоторые завершения native QA сохраняют прежнюю ошибку absolute get_node и scan
aborted после функционального PASS; zero-warning shutdown не заявляется.
Ручной gate OPEN: смена инструментов с правками/без, Apply/Create/Save/Cancel,
сворачивание preview, камера и возврат в Tools/Рельеф. Узкий shell gate сохраняется.

Перенос в dock (2026-10-07): `test_terrain_dock_panels.gd` PASS — ширина
302 px/шрифт 20 px, маршруты, режимы generator/plateau/sections, ready/invalidation,
закреплённый footer при прокрутке. Generation/section-selection/plan/composition
headless PASS. Обновлённый `editor_test_terrain_composition.gd` и F6 PASS:
правые параметры вместо Window, камера/защита от рисования под preview,
инвалидирование по полю, Cancel возвращает план, preview=Apply, Undo/Redo,
Save/Reopen/Discard и прежняя физическая ходьба. Native 1600×900/125% PASS;
1280×750/125% shell с левым Scene dock и native 3D toolbar обрезается справа,
полная узкая компоновка OPEN. `editor_test_terrain_dock.gd` проверяет shared
путь «+ Участок», второй участок в том же режиме, отмену/возврат инструментов,
сохранение и смену сцены — PASS (1600×900/125%). В старой QA-копии
неисправные `qa_selection` experiments временно исключены через `.gdignore`: без
изоляции native Godot падал с access violation при filesystem refresh. Игнор
после теста снимается; production файлы этим не меняются. Автор подтвердил
работу бокового workflow 2026-10-07; узкий shell и художественная оценка плато OPEN.

Композиция сухой земли и плато (2026-10-06):
`tools/test_terrain_plan_composition.gd` — immutable input, плавный край/уровень,
детерминизм разных budgets, отсутствие накопления, перенос/выключение с возвратом
старого следа, порядок пересечений, защита ручных правок, v1/malformed patches,
cancel/wet refusal, scope validation (payload локален, структура глобальна),
атомарные terrain+plan Undo/Redo, stale Apply, Save/Reopen/Discard/recovery.
QA PCK с v2 provenance проверен `test_terrain_plan_export.gd`: разметка и локальные
следы исключены из экспортируемой сцены, применённая земля сохраняется.
`editor_test_terrain_composition.gd` — disposable Forward+ 1600×900/125%
с боковыми настройками:
настоящее 3D выделение/параметры, preview mesh == applied mesh, неизменная плитка
сохраняется, повтор, настоящая compact brush и защищённые места, перенос/off,
Save/Reopen/Discard. `test_terrain_composition_playback.gd` ждёт startup barrier
по wall clock, затем проверяет физическую ходьбу/опору. Native/F6 PASS;
авторская форма и удобство, сложные склоны/большая карта/weak PC OPEN.
Связанные generation/section selection/plan/brush tests PASS. Старый pilot-session
FAIL `_pending[0]` большой кисти воспроизводится и без новой local validation;
он не считается пройденным. Ограничения и возврат — Terrain Authoring / World Layout.

Сохраняемый прямоугольный план (2026-10-06): `tools/test_terrain_plan.gd` проверяет
scene metadata, копирование параметров, Undo/Redo, metadata-only Save без записи
terrain/смены source, Reopen/Discard, recovery/удаление/повреждённый черновик,
валидацию, отказ scene Save, перенос зон при расширении карты и export stripping.
`test_terrain_plan_export.gd` в реальном QA PCK подтвердил удаление разметки
из экспортированной сцены при сохранении applied terrain; исходная сцена сохраняет план.
Native harness
`tools/editor_test_terrain_plan.gd` — только disposable QA: реальные 3D input,
add/rename/resize/delete/Esc, сохранённые параметры, bounded панели, preview/Apply,
terrain Undo/Redo, Save/Reopen/Discard и F6 с физическим движением. Native/F6 PASS;
работа планера подтверждена автором 2026-10-06; форма генерируемой земли ещё
не принята — слишком много игровых перепадов. Открыто: наложение
границ на высокий рельеф и зона >96 м (план допустим, генерация пока отказывает).
Свободные контуры, смешивание слоёв и генерация большой зоны по частям не входят.

Локальное озеро (2026-10-08): `test_terrain_plan_lake.gd` PASS — уровни/глубина,
замкнутый поднятый берег без воды с внешней стороны, неизменные море/внешняя земля,
repeat/budget, move/off с восстановлением всех channels, ручная высота/покрытие/
вода/side paint/flow, v2 read+explicit upgrade, translated flow keys, NaN/границы,
wet refusal/corrupt provenance, 302 px/20 px UI, atomic Undo/Redo, Save/Reopen/
Discard/recovery. После общего baseline/projection для русла расчёт области
24×24 м около 1,4 с, повтор с проверкой следа около 3,2 с; бюджет 4 мс,
измеренный максимум шага до 4,4 мс. Это headless composition, без shader fields/3D;
не замер native brush FPS или weak PC.
`editor_test_terrain_plan_lake.gd` и `test_terrain_plan_lake_playback.gd` PASS в
disposable Forward+ 1600×900/125%: настоящее выделение/параметры, recipe-only Save,
exact candidate/water vertices preview=Apply, stale input/cancel, одна Undo,
brush protection/move/off, Save/Reopen/Discard. Существующий trial shader +
WaterRegions в preview/F6; отмена pending worker 2,2–5,3 мс в данных fixtures.
F6 ждёт startup, проверяет ходьбу/опору, lake 5 м/sea 2 м и closed component,
снимки UI и игрового обзора просмотрены. Старые plan/plateau/dock/plains/generator/
panel-host regressions PASS. Настоящий PCK с v3 проверен прежним
`test_terrain_plan_export.gd`: plan/provenance удалены, applied terrain retained.
Исходная сцена сохраняет план; exporter/source schema не менялись.
У штатного QA shutdown остаётся scan-thread warning; audio QA использует Dummy.
Ручной gate OPEN: + Озеро → выделение сухой земли хотя бы 8×8 м → уровень выше
моря, но дно выше основания → глубина/ширина берега → Save recipe/preview/Apply;
изменить уровень, повторить; кистью поправить берег/воду, перенести/выключить
и «Обновить области». Проверить крестики/сохранность правок, Undo/Save/Reopen/F6.
Длинная работа, авторская форма/соседние слои, weak PC и сложные planar/underwater
эффекты двух уровней OPEN; русло/слияние/водопад/свободный контур не входят.

Русло между водоёмами (2026-10-08): `test_terrain_plan_river.gd` PASS —
непрерывная centreline, уровни водоёмов на концах, склон только после выхода,
касательное течение, стык wet profile/outer bank, immutable input/outside,
repeat/budget, move/off/delete со всеми channels и пустым исходным flow.
Защита height/water/material/side/flow и стабильный повтор защищённого следа,
новый уровень lake recipe, uphill/dry endpoints/low bed/NaN/self-crossing refusal,
v3 read/upgrade с сохранением before lake channels, translated points/flow keys,
plan roundtrip, atomic Undo/stale Apply, fresh scene/terrain Save-Reopen/Discard/
recovery с points и before/after flow, dock 302 px/20 px. Fixture 48×48 м,
lake 20×20 + river ~31 м:
composition около 2,0 с, repeat около 4,1 с, измеренный worst step 4,65 мс,
35 changed tiles; это локальный CPU job, не оценка shader build/игрового FPS.
`editor_test_terrain_plan_river.gd` + `test_terrain_plan_river_playback.gd` PASS
в guarded native Forward+ 1600×900/125%: реальный handler click/Enter/Backspace/Esc,
camera pass, recipe-only Save, exact candidate и water vertices preview=Apply,
числовой stale preview, одна Undo/Redo, repeat/move/off/сохранение выбранной реки
после compose, Save с fresh disk load/scene Reopen/Discard. F6 после startup
подтвердил опору/ходьбу, lake 80 vox, river 53 vox, sea 32 vox и curved flow.
Обзор F6 просмотрен; текущий shader/WaterRegions/mesher не заменялись.
`test_terrain_plan_river_export.gd` PASS из настоящего v4 PCK: authoring metadata
удалены, готовые lake/slope/flow сохранены. Source scene/terrain не изменены export.
Plan/plateau/lake/dock/panel-host regressions PASS; прежний shutdown scan warning
остаётся. Ручной gate OPEN: + Река → точки от озера к морю/озеру → Enter →
параметры → preview/Apply → изменение ширины/глубины/потока → повтор → Ctrl+S/F6;
проверить форму/волны, берег, Undo, перенаметить линию/off и «Обновить области»,
ручные правки/крестики/возврат. Длинная авторская работа, слабый ПК, multi-height
planar/underwater эффекты OPEN; развилки, third body и водопады не входят.

Локальная гора (2026-10-08): `test_terrain_plan_mountain.gd` PASS — абсолютная
высота вершины, ровный верх/склон/стык подножия, вытянутая форма, defaults под
размер выделения, raise-only на более высокой исходной земле. Immutable source,
прежние water/material/cap/side/flow, repeat/budget/move/off/delete, защита
ручной высоты/покрытия/воды/side/flow, wet/NaN/tiny/oversize refusal, порядок
с плато, v4 read/upgrade без потери before_flows, гора рядом с существующей рекой
и возврат всех слоёв, translated patches, dock 302 px/20 px, stale Apply,
atomic Undo/Redo, fresh Save-Reopen/Discard/recovery. Fixture 48×48 м, область
24×24 м, peak 12 м / summit 4 м / slope 10 м: composition около 1,7 с, repeat
3,7 с, worst step 4,11 мс, 32 changed tiles. Это standalone headless CPU job,
без native mesh/shader cost и не замер слабого ПК; конкурентная QA/export
нагрузка увеличивает wall timings и сама по себе не доказывает brush regression.
`editor_test_terrain_plan_mountain.gd` + `test_terrain_plan_mountain_playback.gd`
PASS в guarded native Forward+ 1600×900/125%: настоящее 3D выделение, общий
dock, recipe-only Save, exact candidate/ground vertices preview=Apply, stale
поля/Cancel/camera pass, Undo/Redo, repeat, brush protection/move/off, fresh
disk/scene Save-Reopen/Discard. F6 — ходьба/опора на вершине 192 vox, physics
ray совпадает с source height, море 32 vox сохраняется. Native 3D и F6 снимки
просмотрены; все прежние render/physics owners сохранены.
`test_terrain_plan_mountain_export.gd` PASS из v5 PCK: plan/provenance удалены,
готовая гора, внешняя земля и море сохранены. Plan/plateau/lake/river/dock/host
regressions PASS; штатный shutdown scan-thread warning остаётся.
Ручной gate OPEN: + Гора → область от 8×8 м → высота вершины от основания →
ширина верха/склонов → preview/Apply → Ctrl+S/F6; менять widths/высоту,
повторить, поправить кистью, перенести/off/delete и «Обновить области».
Проверить вершину/подножие, сохранность правок/крестики, Undo и save/reopen.
Ширины должны помещаться в меньшей стороне; higher input не срезается,
storage ceiling после удаления не сжимается. Художественная форма, соседние
слои/большая область/длинная работа/weak PC OPEN; свободный контур, шум
вершин, slope materials, маршрут подъёма и водопад в этот срез не входят.

Дорога/тропа на готовой суше (2026-10-08): `test_terrain_plan_road.gd` PASS —
общая кривая и коридор с рекой, уровни концов после предыдущей горы, линейный
продольный профиль/ровное сечение, soil role/мягкий край, неизменные внешняя земля,
вода/flow. Immutable input, repeat/budget/reverse/move/off/delete с восстановлением
прежней горы и всех channels; защита height/material/water/side/flow, grade/wet/
NaN/missing-soil refusal, v5 read/upgrade без потери original channels, translated
points/patches. Dock 302 px/20 px, stale preview/Apply, atomic Undo/Redo,
fresh Save/Reopen/Discard/recovery. Fixture 48×48 м, гора 24×24 м + дорога 32 м,
40 changed tiles; composition около 5,5 с, repeat около 10,2 с, worst step 6,45 мс
при параллельной native QA нагрузке. Эти CPU timings не являются изолированным
benchmark, замером brush FPS или слабого ПК; retained footprint ограничен 256 tile.
`editor_test_terrain_plan_road.gd` PASS в guarded native Forward+ 1600×900/125%:
click/Enter/Backspace/Esc/camera pass, общий dock, recipe-only Save, exact candidate
и ground vertices preview=Apply, stale/cancel, Undo/Redo, repeat, реальная кисть,
move/off/возврат предыдущей горы/сохранение выбранной дороги, fresh disk/scene
Save-Reopen/Discard. Обзор 3D просмотрен. Окончательное перенамечивание fixture
проверяется сверху: oblique picker правильно выбирает видимую гору, а не скрытую
за ней ручную выемку; production picking не изменён для теста.
`test_terrain_plan_road_playback.gd` PASS в F6: после startup и приземления —
физическое движение около 6 м, опора в 110/120 кадров и в конце, physics ray
совпадает с source height 96 vox, soil и sea 32 vox сохранены. F6 обзор просмотрен.
`test_terrain_plan_road_export.gd` PASS из настоящего v6 PCK: plan/provenance
удалены, готовая дорога, соседняя гора и море сохранены. Export source не меняет.
Plan/plateau/lake/river/mountain/dock/host headless regressions PASS.

Роща / forest placement (2026-10-08): `test_terrain_plan_grove.gd` PASS —
immutable terrain/input plan, deterministic seed/budget, spacing, road/water/
manual mesh exclusions, slope, 64/256 bounds, cancel/stale; ordinary props,
exact Preview→Apply provenance, atomic Undo/Redo, repeat без накопления,
move/off/delete с защитой ручных сдвигов/удалений, свежие scene Save/Reopen,
Discard/recovery с native prefab identity. v6 read без open-migration,
v7 validation/translation, invalid parameters и UI 302 px/stale/mode-switch PASS.
Packed mesh/property arrays сравниваются по содержимому SHA256, не по
Resource instance ID; байтовое изменение и стабильная копия покрыты regression.
`editor_test_terrain_plan_grove.gd` PASS: настоящее прямоугольное выделение,
общий dock, recipe-only Save, native prefab preview=Apply, Undo/Redo/repeat,
off/on с сохранением вручную перемещённого дерева, fresh disk и Discard.
`test_terrain_plan_grove_playback.gd` PASS в Forward+ F6: 4 ordinary trees,
mesh/collision сохранены, игрок стоит на земле и движется; обзор просмотрен.
`test_terrain_plan_grove_export.gd` PASS из настоящего v7 PCK: plan/member/group
metadata отсутствуют, 4 native prefab props с mesh/collision и исходная земля
сохранены. Export не меняет авторскую сцену. Проверка ограничена fixture 24 м,
30 FPS; initial default fan_town был открыт редактором вместе с fixture,
по завершении оставлена только роща. NVML всей системы: 2656 → 3644 MiB,
max GPU 17%, 45°C; новые driver events отсутствуют. Это не benchmark большого
леса/слабого ПК и не закрывает прежний GPU-incident gate.
Native log/NVML/summary, export check и просмотренные кадры сохранены в
`user://ember_terrain_diagnostics/grove_20261008_36112/`.
Авторские плотность/внешний вид/выбор вариантов, пересечения на рабочей карте,
проход между деревьями, большая/населённая карта и длинный cycle OPEN.

Общая расстановка объектов (2026-10-08): `test_terrain_plan_placement.gd` PASS —
mixed native prop fixtures с разными размерами, circle clearance/spacing,
неизменные земля/вода/road, Native voxel base band без кроны, mesh override fallback,
ручной voxel blocker/mesh stale, spatial grid против прямой проверки соседей
(negative coordinates/large fallback), invalid clearance и v7 no-open-migration.
Повторены atomic Undo/Redo, seed/budget/cancel, move/off/delete, protection/
tombstones, fresh Save/Reopen, Discard/recovery и export strip через прежние owners.
UI 302 px: тип/поиск сохраняют скрытый выбор, смешанный набор/сводка/clear,
clearance invalidates Apply, road/grove mode regression PASS. Plan/dock/exact
placement/grove headless regressions PASS; terrain channels не расширялись.
`editor_test_terrain_plan_placement.gd` PASS в Forward+: один подготовленный
24 м fixture/30 FPS, 10 props / tree+bush+rock. Камень опубликован прежним
workshop transaction в QA copy; куст без recipe разрешён. Real rectangle,
common dock, recipe-only Save, exact prefab preview=Apply, stale clearance,
Undo/Redo/repeat, manual shift/off/on, fresh disk/Discard PASS. F6 — все meshes,
10 colliders, floor/движение PASS; обзор просмотрен. После UI-компоновки короткий
capture-only gate PASS: сводка выбранного набора/clear выше списка, один tab.
`test_terrain_plan_placement_export.gd` PASS из настоящего v8 PCK: все три
model_ids / 10 props, mesh/collision/земля сохранены, plan/member/group metadata
не экспортированы. Дополнительный headless native-source footprint gate подтвердил
настоящие inline ArrayMesh references и основание дерева меньше кроны.
NVML/WDDM всей системы functional run: 2817,8 → 3813 MiB, max GPU 16%, 44°C;
короткий UI run peak 3395 MiB/13%. Новых driver events нет. Это не benchmark
большой населённой карты/слабого ПК и не закрывает прежний GPU-incident gate.
Evidence — `user://ember_terrain_diagnostics/placement_20261008_13588/`.
Авторские удобство/типы/интервалы/соседство/проход, реальные mixed карты и большой
preview/Apply/память OPEN. Arbitrary gameplay assemblies/новые маски,
количество/доли/кучность/паттерны не реализованы этим срезом.

Повторный `editor_test_terrain_plan_river.gd` подтвердил общий path input и весь
native Preview/Apply/Undo/Save цикл. При последующем play-current-scene единично
потерян Vulkan device: BLIT/UI breadcrumbs, затем signal 11 с `nvoglv64.dll` в
стеке. Отдельный свежий запуск сохранённой river fixture в F6 PASS (fields/flow,
опора/движение, lake 80/middle 53/sea 32 vox). Это не доказательство исправления:
воспроизводимость сбоя после длинного preview-cycle OPEN, причина не установлена.
Автор сообщил о падении своей игры и потере одного монитора во время QA.
Windows System подтвердил nvlddmkm 153 и Display 4101; WER LiveKernelEvent 117
и BEX64 Godot в nvoglv64.dll. NVIDIA driver 617.14 (32.0.16.1714).
Инцидент затронул общий графический драйвер, а не только тестовый процесс;
связь с QA вероятна, точный триггер не доказан. Графические тесты остановлены,
QA процессов не осталось. Мониторы восстановлены после перезапуска.
По отдельному согласованию пройдена одна ограниченная диагностика: сохранённая
river fixture 48×48 м / 4 региона, один editor + обычный F6 child, 30 FPS,
короткий ready/play/stop без полного authoring-cycle. Editor layout содержал
65 открытых сцен; на проверке одна, после неё оставлен чистый layout и сохранён
старый backup. NVML/WDDM: вся система baseline 2700,8 MiB → peak 3931 MiB из
12227 MiB → 2674 MiB после выхода; GPU peak 22%, 45°C. 44 samples за 36 с,
Godot RAM peak 1560,5 MiB. Эти числа включают фоновые приложения; WDDM
per-process used_memory=N/A, субсекундные пики не исключены. Fields/flow/опора/
движение PASS; новый Display/nvlddmkm timeout отсутствует. Это baseline,
не воспроизведение длинного исходного цикла и не доказательство исправления.
Production renderer/driver/shader не менялись; временные датчики удалены.
Далее согласовать узкую Preview/Cancel→F6 проверку удержания полей/памяти:
Regions.close лишь останавливает worker; Study._exit_tree сохраняет ссылку,
а Sea GPU release привязан к PREDELETE. Удержание ресурсов неактивной сценой
нужно измерить; подтверждённой утечки/источника TDR пока нет. Не возвращать
65 сцен/полный стресс и не менять TDR registry/драйвер для маскировки сбоя.
Артефакты сохранены в `user://ember_terrain_diagnostics/gpu_20261008_road_river/`:
`original-crash.log`, `first-clean-f6.log`, `native.log`, `gpu.csv`, `summary.json`.
Возврат: saved `river_native_5104.tscn` в guarded `ember-river-preview-*` QA,
одна открытая сцена, предварительно проверить отсутствие параллельной GPU нагрузки.
Штатный shutdown scan-thread warning остаётся.
Ручной gate OPEN: + Дорога → точки на суше → Enter
→ ширина/мягкий край/допустимый уклон → preview/Apply → Ctrl+S/F6; изменить параметры,
повторить, сделать правку кистью, перенаметить «Линию дороги»/off/delete →
«Обновить области». Проверить возврат старого следа, крестики, Undo/Save/Reopen,
форму изгибов/стыки/проходы. Уклон ограничивает расчётный профиль; защищённые правки,
тесные изгибы и боковые откосы не получают обещания универсальной проходимости.
Слой работает на готовой сухой земле; вода/нет земли/понижение под скрытую воду
дают отказ. Before-generation constraints, мосты/развилки/новые покрытия,
индивидуальные высоты точек и object exclusions не входят. Длинная авторская работа,
соседние слои/большая карта/weak PC и художественная приёмка OPEN.

Игровая суша (2026-10-07): `tools/test_terrain_playable_land.gd` PASS для контрольных
высот прежних профилей, параметров/defaults/NaN/границ, flat fraction/size/micro/transition,
непрерывности на границах и при смене второго ближайшего соседа, seed/budget,
неизменного source, 302 px/20 px UI, stale Apply, plateau isolation и recipe Save/Reopen.
Расчёт 48 м ~0,46 с, 96 м с площадками 8 м ~1,76 с/худший шаг 4,43 мс; это sampler
job, без 3D/физики/полной подготовки и без обещания скорости слабого ПК.
`editor_test_terrain_playable_land.gd` + `test_terrain_playable_land_playback.gd`
PASS в disposable Forward+ 1600×900/125%: новые поля, сохранённый рецепт отдельно
от земли, repeat/invalidation/cancel, exact mesh preview=Apply, одна terrain Undo/Redo,
Save/Reopen/Discard, камера и pinned actions. F6 проверяет движение и опорную грань
на одном маршруте. Generation/dock/plan/composition regressions PASS; прежний
экспортный owner/schema не менялись, новый реальный PCK в этом срезе не проверялся.
Ручной gate OPEN: «Рельеф → План областей → Параметры области → Игровая суша»;
сравнить 0/80/100%, 8/16/32 м, неровность 0/0,1/0,5 м и переход 0,5/2/4 м
(не больше четверти размера). Проверить края площадок/берег, Undo/Save/Reopen,
пройти разные склоны в F6. Это генерация с заменой правок внутри области;
защита ручной кисти при переносе плато остаётся отдельным прежним gate.
Авторская форма/удобство/проходимость, большая настоящая карта и weak PC OPEN.

Генератор выбранной области (2026-10-03): `tools/test_compact_terrain_generation.gd`
проверяет deterministic sampling независимо от work budget, отличия profiles/seed,
cancel/validation/legacy, область через несколько участков, внешние каналы и
переход 2 м, расширение height ceiling без перестройки прежних tile, stale preview,
Undo/Redo, Save/Reopen/Discard, физическую высоту/navigation и точный mesher preview.
Fixture до 96×96 м и 28 м по высоте, без авторских файлов; замер расчёта отдельно
от validation и 3D-сборки. Старый creation coast после переноса sampling в общий
leaf сохраняет результат и проверяется `test_compact_map_coast.gd`.
`editor_test_compact_terrain_generation.gd` работает только в одноразовой native
копии: прежний edit_region, окно/отмена, настоящая OK-кнопка с закрытием после
commit, exact candidate, EditorUndoRedoManager,
Save/Reopen/Discard и F6 по изрезанному рельефу с неизменным маркером ниже земли;
playback проверяет горизонтальное движение и настоящую опорную грань капсулы
у ступенек. Headless также проверяет высоту входа/сохранённой позиции и сохранность
маркера. Native/F6 PASS;
это не художественное принятие.
`-- --dialog-regression` в той же disposable native копии воспроизводит первый
popup при 125%, статус ошибки/повторный popup и metadata 72×48 против terrain
48×48; проверяет ограниченный размер и доступность preview. Проверены реальные
1600×900 и 1280×750 (native editor minimum при 125%); окна карты/участка
также открыты без применения. Размер 1280×720 при иных настройках остаётся ручным.
Ручной gate: новая compact-копия/рабочая область
до 96 м → «Сгенерировать рельеф…» → параметры → явный предпросмотр; отменить,
сравнить profiles/seed, применить, проверить соседние правки и обычные кисти,
Undo/Redo/Save/Reopen/F6. Проходимость сложных склонов, перенастройка существующих
объектов, 256–512 м, слабый ПК, узкое окно/125% и специальные поля воды OPEN.

`tools/test_compact_map_creation.gd` создаёт сцену и Resource только в `user://`,
проверяет совпадение предпросмотра с записанным Resource, отказ от перезаписи
существующей карты, обязательное обновление предпросмотра после изменения
параметров, корректный `.tscn` с единственным compact owner, кисть, Undo/Redo и
save/reopen. Максимальный предпросмотр 4×4 участков (96×96 блоков) остаётся в
памяти до Apply. `tools/test_compact_map_extension.gd` проверяет рост на четырёх
сторонах, сохранение прежних каналов, Undo/Redo, Save/Reopen и предельный размер;
`tools/test_large_landscape_test.gd` проверяет большую авторскую сцену, кисть
рельефа и существующую воду без правки её Resource.
`tools/test_compact_map_coast.gd` проверяет второй пресет «Берег»:
повторяемость seed, квадраты 8×8 и шаг 4 вокселя, непрерывный стык участков,
наличие суши, песка и воды, validation, Save/Reopen, физическую высоту,
воду, кисть с Undo и нативный предпросмотр. Подготовка данных 4×4 в
headless занимает около 0,65 с; в отдельном Forward+ окне 576 tile сложной
карты собраны за ~2,54 с. Для ручной приёмки открыть «+ Карта», выбрать
«Берег», указать 4×4 и обновить предпросмотр. После создания осмотреть берег
в 3D, стыки через каждые 24 блока, воду и доступность кистей; затем сделать
мазок, Ctrl+Z/Y, Ctrl+S и повторно открыть сцену. Оценить окно на 1280×720.
Видимый тест не является замером ввода в редакторе; рисунок берега пока
не принят автором.
`tools/test_compact_map_open_performance.gd` создаёт одноразовую ровную карту
4×4 в `user://`, измеряет подготовку, сохранение, загрузку сцены, вход карты
и сборку 576 tile; проверяет одну верхнюю грань внутреннего tile и совпадение
физического попадания с высотой земли. На текущей машине headless сборка
после упрощения ровного tile занимает ~0,97 с против ~2,48 с до правки.
Тест также проверяет, что запрос предупреждений во время очереди tile не
обходит повторно все колонки, а ошибочная высота после сборки даёт
предупреждение. В живом Forward+ редакторе закрытие и повторное открытие
ровной сцены 4×4 после этой правки заняло ~0,75 с против ~27,8 с; ручную
плавность открытия и работы с картой должен подтвердить автор.
`tools/profile_compact_terrain_pipeline.gd` читает берег, создаёт только
одноразовые fixtures в `user://` и пишет сравнимый JSON для ровной карты и
сложного берега 4×4: подготовка, файл, вход в карту, задержки кадров,
validation, верхние/боковые/водные грани, Mesh Resource, nodes, visual и обе
части collision.
`tools/test_terrain_mesh_rectangles.gd` проверяет покрытие каждой клетки
видимой землёй, боковыми стенами и водой, высоту, цвет и глубину воды до и после детальной
правки одной колонки; треугольники коллизии берутся из того же ground mesh.
Для крупной сетки 8×8 тест отдельно проверяет ступени, воду, детальный
fallback и шов с соседним tile, включая детальную колонку за швом.
Срез ground side runs (2026-10-05): ровная 16×16 площадка с двумя слоями
материала в opt-in runtime сократилась с 774 до 54 vertices; editor default
сохраняет 774. Test проверяет оба режима и section window, точное совпадение
water arrays между ними, все четыре стены,
материалы/semantic alpha, разрыв, разную cap depth и единичное боковое исключение.
Коллизия остаётся из тех же итоговых ground faces. Addressed-map/projection и
clear-water seam regressions PASS. В отдельной native QA editor команды
preview/Apply, кисть/Undo/Redo, Save/Reopen/Discard прошли; F6-персонаж прошёл
через стык X=720→811,64, on_floor=true, поверхность Y=12 совпала с физикой.
Native policy QA дополнительно проверил фактический editor tile: 774 vertices
и точные faces старого mesher; F6 на этом же fixture использовал 18 vertices.
Лог `qa_ground_runtime_policy_final.log` в текущем Temp QA. Сообщённая автором
плавность кисти после удаления editor coalescing остаётся ручным OPEN gate;
фоновые 10 FPS при sleep=100 мс не считать измерением активного редактирования.
`tools/test_compact_section_brush_batches.gd` воспроизводит radius=8, coarse/square,
strength=48 на 96×120 м / 20 участках: 61 504 изменённых колонок в первом шаге,
163 456 после перемещения. Stall budget 1/2 с намеренно отделён от frame budget:
старый путь занимал 2,86/6,30 с, исправленный ~0,14/0,32 с. Тест проверяет общий
source/document payload, сохранение untouched/baseline, Undo/Redo и 48 комбинаций
кисти против dense источника через неполный стык. Связанные scale/overlap/addressed
regressions PASS. Native Forward+ QA изменил 134 912 колонок: шаги 141/147/146 мс,
проверки данных/Undo/Redo, Save/Reopen/Discard и F6-ходьба PASS; лог
`qa_section_brush_batches_final.log` в текущей Temp QA. Ручной повтор trace автора
остаётся OPEN; PASS не обещает отсутствие пауз широкого мазка.
Игровой ground LOD: `tools/test_terrain_ground_lod.gd` на независимом шумовом
fixture проверяет точные ближние vertices/normals/colors/UV/faces, защищённые
border triangles, границы и semantic material ID каждого дальнего triangle,
меньшее число indices, прежние collision/water, отсутствие camera rebuild,
отмену при закрытии и выключенную policy. World startup test проверяет LOD gate.
Native `editor_test_compact_map_sections.gd` проверяет ноль editor LOD jobs/Thread
и прежний lod_bias после команд/кисти/Undo/Save/Reopen/Discard; F6 проверяет
пустую очередь при появлении героя и ходьбу через стык. Оба сценария PASS.
Forward+ ground-only A/B 192×120 м / 40 участков: дальние primitives −8,6%, ближние
прежние, jobs не меняются при движении камеры, существенного FPS gain нет.
Подробные startup/memory/geometry замеры — Terrain Authoring; native artifacts
`qa_selection/ground_lod_native.json`, near/far PNG, `qa_ground_lod_editor_native.log`.
Ручная оценка переключения LOD/материалов/стыков на авторской карте, экспорт и
слабый ПК OPEN. Это не приёмка водной геометрии или persistent geometry cache.
Точная runtime water geometry: `tools/test_terrain_water_indexing.gd` разворачивает
indices и проверяет полный прежний порядок vertices/normals/colors/UV у каждого
triangle. Dense/sectioned, grouped/fine, неполный tile, несколько уровней/материалов,
границы, walls/swash/falling sheet, collision/source, повторная правка и выключенная
policy PASS. Native editor подтвердил отсутствие water index buffer после
команд/кисти/Undo/Save/Reopen/Discard; F6-ходьба через стык PASS
(`qa_water_index_editor_native.log`). В F6 water geometry индексируется только
при загрузке/изменении входов; shader и physical surface прежние. Два Forward+
A/B 192×120 м / 40 участков: water vertices −81%, primitives/draw calls прежние,
дальний GPU median около −14%, VRAM −122,3 MiB, общий кадр около 5 мс прежний.
Артефакты `qa_selection/water_geometry_on/off.json`, round1 JSON и
`qa_water_geometry_final_on/off.log`; замеры и ограничения — Water Rendering.
Ручная F6-приёмка берега/набега/водопада, ближнего/дальнего вида и стыков OPEN.
Runtime water LOD: `tools/test_terrain_water_lod.gd` проверяет near arrays/order,
dense/sectioned/partial tile, защищённые patch/tile boundaries, holes/depth/material,
walls/swash/sheet, collision/source, отсутствие camera jobs, remesh без column
revision, worker cancellation и disabled policy. Общий worker/WorldCanvas barrier
земли и воды, ground/indexing/startup/swashes/waterfall/regions regressions PASS.
Native editor не строит gameplay LOD при командах/кисти/Undo/Save/Reopen/Discard;
F6 seam walk с pending_runtime_lod_count=0 PASS (`qa_water_lod_editor_native.log`).
Два Forward+ A/B на 192×120 м: дальний primitives −18,6%, GPU median около −7,8%,
ближние primitives прежние. Запуск дольше около 3,7 с, VRAM +4,7 MiB; это не
оптимизация загрузки. Визуальная проба wave_height=4 на 50/100/212,5 м без новых
дыр/длинных швов; полные метрики/ограничения — Water Rendering. QA artifacts
`qa_selection/water_lod_final_on.json`, `qa_water_lod_final_native.log`,
`qa_water_lod_wave_native.log`, max-wave near/far PNG. Ручная оценка LOD-перехода,
берега/водопада/материалов/стыков, экспорт и слабый ПК OPEN.
Runtime geometry cache: `tools/test_terrain_geometry_cache.gd` проверяет fresh
Resource/save/reopen, exact near arrays/collision, warm ground+water LOD без derive
CPU, локальное кольцо invalidation/Undo, рост без distant invalidation, swash/sheet
при том же revision, missing/corrupt/version/malformed/I-O fallback, bounded disk,
camera без jobs и закрытие во время worker I/O без временных файлов. PASS;
старый береговой cache и ground/water/indexing/projection/startup regressions PASS.
Прямая передача cache CPU arrays в LOD: cold/warm имеют ноль LOD readbacks,
cache-disabled путь остаётся доступным. Expanded cache test сравнивает exact
near/collision и реальную curved waterfall geometry после fresh reload; corruption,
local edit/Undo и cancel/fallback сохраняются. Headless/native cache и ground/water
LOD/indexing/projection/startup PASS. Key/read/validation затем перенесены в тот же
worker: до 32 tiles/пачку, мягкий предел 64 MiB плюс одна запись 16 MiB.
Expanded cache suite headless/native PASS: multi-batch exact parity, edit+water
во время чтения/stale rejection, document replacement, рост с ранее pending
адресами, cancel/I-O/semantic corruption и sync fallback. Cold miss build/write
остаётся main; отдельный producer до игры описан ниже.
Native 256 м WorldCanvas 15,28 → 14,77–14,99 с, main process CPU 6,82 → 1,70–1,71 с;
RAM/пики/FPS не объявляются исправленными. Полные фазы/границы — Terrain Authoring.
Native editor activity harness проверяет пустые runtime geometry cache/keys,
snapshots/requests/ready arrays/jobs и нулевые LOD readbacks; brush/Undo/Redo/Discard/
Save/Reopen/F6 PASS (`qa_selection/prepare_editor.log`). Manual/cold editor timing,
авторский большой F6/визуальный LOD/512 м/export/weak PC остаются OPEN.
Native editor sections test проверяет ноль geometry cache/jobs после кисти и
Undo/Redo/Save/Reopen/Discard, затем два F6: cold writes, warm hits/0 misses,
герой после pending=0 и ходьба через стык PASS (`qa_geometry_cache_editor_retry.log`).
Первый QA editor save crash не воспроизвёлся в отдельном повторе; причина не
установлена, production save не менялся. Большой Forward+ geometry benchmark
192×120 м: disabled/cold/warm 19,72/26,69/4,89 с, GPU/geometry прежние; первый
запуск дороже, это не полный игровой startup. Подробные метрики/артефакты —
Terrain Authoring. Ручной повтор F6 авторской карты после Save/local edit/Undo,
LODs/берег/водопад, экспорт, 256–512 м/слабый ПК и cold editor timing OPEN.
Explicit offline geometry producer: `tools/test_prepare_terrain_geometry_cache.gd`
запускает headless CLI дочерним процессом; сохранённые scene/Resource, inferred/
explicit water policy, base+final coast варианты, warm 0 geometry/LOD builds,
curved waterfall и exact near/collision против обычной native сборки, local edit
с сохранением пригодных ключей, corruption repair, invalid/ambiguous/empty source,
options/destination/I-O rejection и source hashes — headless/native PASS.
CLI строит только derived caches, редактор/brush/авторские файлы не меняются.
Связанные water CLI, ground/water LOD и WorldCanvas startup tests PASS.
Native WorldCanvas 256 м: cold geometry 85,91 с → offline-prepared 14,95 с;
coast/component caches warm в обоих случаях. Geometry/LOD misses и derive CPU=0,
pending=0 до героя, ходьба PASS, source hash прежний. Offline geometry preparation
83,80 с / 55,1 MiB; полные фазы и ограничения — Terrain Authoring. Portable export,
512 м/weak PC/авторский F6 и прежний cold editor timing остаются OPEN.
Prepared export: `test_terrain_prepared_bundle.gd` — CLI selection/manifest/checksum,
ограниченные имена/размеры, traversal/duplicate/version rejection, custom isolation,
corrupt local → valid packaged и отсутствие копирования в local cache PASS.
`test_terrain_prepared_runtime.gd` запускается в отдельном exported PCK с приватным
user directory: empty local caches, water/coast/near/LOD hits без derivation, exact
arrays/collision/curved waterfall, corrupted local, edit/restore — headless/native PASS.
Настоящий EditorExportPlugin добавил 9483 records/58,66 MiB на 256 м; PCK WorldCanvas
native startup 13,27 с, все caches hits/0 builds/misses/writes, pending=0 до героя,
physics walk и source hash PASS. User cache directories не созданы. Unfocused run
не доказывает дополнительный performance gain. Артефакты/лимиты — Terrain Authoring.
Release `.exe`/другой ПК/512 м остаются OPEN; исходные export preset/templates отсутствуют.
Related geometry/cache/water regions/startup regressions PASS. Native редактор с
новой export registration прошёл brush/Undo/Redo/Discard/Save/Reopen/F6 и сохранил
нулевые runtime geometry/LOD jobs (`qa_selection/portable_editor.log`).
Runtime water activity: `test_compact_water_activity.gd` — 20/5 Гц, seam scheduling,
актуальная физика, немедленный query promote/lease, hysteresis, settings/reset и
no-observers fallback; source unchanged. `test_compact_water_activity_gpu.gd` —
3159 native readback сравнений: seam height/foam/wetness/age на 20 Гц, far interior
на 5 Гц, query current, восстановление и release border RID. Прежние 702 GPU
parity/migration/history/release сравнений, regions/cache/swash/startup PASS.
Большая controller fixture 192×120 м: GPU records −46,2%, полные dispatches
−50,6% с дополнительными seam dispatches, geometry прежняя, устойчивый выигрыш
кадра не доказан. Детали/артефакты — Water Rendering → «Runtime-частота морского набега».
`editor_test_compact_water_activity.gd` + playback PASS: настоящий editor не
создаёт runtime border records/buffers или LOD jobs, brush/Undo/Redo/Discard и
Save/Reopen корректны; F6 ждёт подготовки, защищает Player при удалённой камере,
frozen preview возвращает full rate, live preview снова включает activity.
Ручной F6: отдалить/вернуть камеру, берег/пена/мокрый след, стыки, герой у воды;
плавность 5 Гц вдали, слабый ПК и экспорт OPEN. Sleep/streaming не реализованы.
Water shader/parameter cost: `test_compact_water_parameter_updates.gd` —
unchanged broadcast без writes, независимые water/ground caches, mutable wake
age, rebind/new region и прямое изменение base material. Regions/activity/
swash/river/contact regressions PASS. Native A/B pinned water/ground/shaft time,
одна geometry/материалы: wide/underwater exact PNG, near/editor optics/wake
1 pixel × 1/255; warmed reflection 7 pixels × 1/255 (original repeat 6).
Первый reflection A/B имел transient 2/255, он не принят как steady-state.
Near GPU 2,456 → 2,317…2,366 мс, wide общего устойчивого frame gain не доказывает.
Stationary 40-region contact upload 70,45…70,50 → 9,30…9,38 мкс/вызов,
0 повторных regional writes. Подробные условия — Water Rendering →
«Стоимость рисования поверхности и передача параметров».
Native editor gate: brush/Undo/Redo/Discard, все contact/wake uniforms равны
base после rebind, Save/Reopen с новым root/F6; detail-distance/sun PASS
(sun fixture 1600×900). QA Save использует новое имя, native extension — отдельную
копию DLL; завершение `water_cost_editor_unique.log` без engine/script errors.
Предыдущие QA попытки с общей вкладкой/DLL имели platform errors и не заменяют
этот завершающий прогон; production Save/extension не менялись.
Ручной Save/F6: пена box/cylinder, движение/затухание следа, river/sea/run-up,
sun/scene reflection, underwater и near/far return; слабый ПК/экспорт OPEN.
Большая проба: `benchmark_compact_world_scale.gd`, build/validation/serialization
256×256 м/121 payloads; native cold/warm с настоящими geometry/LOD/water owners,
180 кадров на случай, player-height/wide cameras, Windows memory, две occlusion
A/B пары на view. Cold 172,06 с / warm 29,04–31,52 с, water disk hits 121 и geometry
near hits 4306/4306; frame/draws/память — Terrain Authoring → «Проба заполненного
острова 256 м». Occlusion near/wide exact PNG; shore/reflection — 10 pixel mismatch
(до 85/255), повторяет cold/warm и extra-margin probe. Visual gate FAILED/OPEN,
production occlusion не включено. Это render harness, не полная F6 игра с героем;
512 м, движение/physics walk, экспорт, населённый мир и слабый ПК OPEN.
192×120 м ground-only сравнение подтвердило −37% ground geometry, water vertex
count прежний; детали — Terrain Authoring → «Производительность и границы
доказательств». Ручная приёмка большой карты, материалы при приближении,
длинный мазок и слабый ПК OPEN; прежний cold-water editor timing gate не закрыт.
После оптимизации пользователь повторяет короткую запись в обычной 3D-вкладке:
на большой карте один мазок «Поднять» и один мазок «Неровности» радиусом 8,
дождаться появления всех квадратов после отпускания, сохранить JSON и
сравнить время `pending_tiles` до нуля и кадры после мазка с прежней записью.
Визуально проверить боковые ступени, воду и Undo/Redo; затем Save/Reopen на
тестовой сцене. Автоматический замер построителя не заменяет этот живой gate.
Видимый `tools/profile_compact_terrain_forward.gd` сравнивает те же 4×4
источники в отдельном Forward+ окне, сохраняет снимки и GPU/draw-call
счётчики в `user://ember_terrain_diagnostics`. После объединения верхних
площадок берег собрался за ~4,49 с против ~5,80 с до изменения на RTX 5070;
редакторская кнопка и работа с объектами в этот замер не входят.
`tools/test_terrain_diagnostics.gd`
проверяет read-only захват и сохранение отчёта, этапы записи настоящей кисти
и Undo, а тест создания карты —
доступность кнопки в компактном 3D-редакторе. В Forward+ открыть большую
компактную карту, включить «Редактировать мир» → «Дополнительно» →
«Начать запись 3D». Сделать один мазок «Поднять» радиусом 8 блоков и один
мазок «Неровности» тем же радиусом; дождаться обновления земли, затем нажать
«Остановить и сохранить запись». Передать JSON из пути, который показан в
панели; кнопка «Открыть папку записей» должна открыть его каталог в проводнике.
`tools/test_world_recovery_async.gd` проверяет на одноразовой карте размера
4×4, что рабочий поток записывает отделённый снимок, новая правка не меняет
его задним числом, явная запись ждёт завершения и восстановление читает
последнее состояние. После обновления Godot отдельно записать один короткий
мазок и остановить запись примерно через 15 с (буфер хранит последние 3600
кадров): в JSON поле `periodic_recovery` покажет время снимка и фоновой записи.
Сравнить кадры после отпускания с файлом
`terrain_1790619561_86969276.json`, где один вызов
`_get_configuration_warnings()` занял 362 мс из 369 мс кадра.
Для проверенного editor draft счётчик `warning_validation_count` не должен
расти после мазка, а такого стоп-кадра быть не должно. Если пауза останется,
сверить `editor_process_usec`/`dirty_status_usec` и очередь tile; не считать
любой другой длинный кадр автоматически той же причиной. Проверить Undo/Redo,
Save/Reopen и восстановление аварийного черновика на тестовой карте.
Фактическая запись автора `terrain_1790620238_38676066.json`: один проход
радиусом 8, 921 кадр без усечения, `warning_validation_count=0`, максимум
кадра 72,6 мс во время мазка и 9,2 мс через 1–3 с после отпускания. Пауза
повторной полной validation не воспроизвелась; дальнейшая плавность самой
большой кисти остаётся отдельной задачей.
Для проверки отдельного позднего кадра записать также несколько секунд
движения курсором без нажатия, а после каждого мазка ещё две секунды водить
курсором по земле. Сравнивать одинаковые кисть, режим, маршрут и состояние
карты; разная длина мазков не даёт точного сравнения FPS. Отдельно сверить
число шагов кисти длиннее 33 мс и кадров после отпускания.
Проверить наличие обоих мазков, их первых/последующих шагов,
этапов `brush_collect`, `resource_write`, `projection_apply`, `undo_commit`,
`grid_preview`, кадров во время мазка и после него. Для крупной кисти сначала
поводить ею без нажатой кнопки по уже подсвеченным и новым tile: сетка должна
следовать за курсором без задержки. Несколько раз пройти тем же маршрутом
туда и обратно и сравнить FPS: возвращение к недавним участкам должно быть
плавным. Первый вход в новый tile может быть дороже. Затем рисовать через
стык tile и по воде: белые линии должны оставаться
на высоте земли, жёлтая клетка — под курсором, а соседние готовые tile не
должны мигать. Сравнить `grid_preview`, frame p95 и движение кисти с прошлой
записью `terrain_1790589027_207039440.json`; `undo_commit` оценивать отдельно
после отпускания. Само включение записи не должно менять
карту, Undo/Redo или сохранение; после теста откатить пробные мазки, если они
не нужны на карте. Для проверки шейдерной сетки на большой
карте после полного перезапуска Godot войти в «Редактировать мир», начать
запись до первого мазка и провести курсором по новым участкам и обратно.
Повторить маршрут после мазка. Шейдерная сетка не должна создавать отдельные
узлы/mesh при наведении; в записи `hovers[].grid.tiles_created` и
`tiles_rebuilt` должны оставаться нулевыми, `overlay_tiles_changed` отмечает
только смену подсвеченных участков. Сравнить `frame_interval_usec`, `focused`,
GPU/CPU viewport и draw calls с `terrain_1790597380_61788494.json` (там
20 пауз по 279–395 мс до шейдерного варианта). При выходе из режима сетка
должна исчезнуть; после нового входа и Save/Reopen — появиться лишь под курсором.
Отчёт удерживает последние 3600 кадров и 2000 наведений, а также до 2000
шагов мазков; поля `truncated_*` показывают превышение лимита. Отдельно включить
«Измерить производительность карты», дождаться отчёта и проверить FPS,
frame p95, CPU/GPU viewport, visible/shadow draw calls вместе с CPU-этапами
земли. Нулевое GPU-время при недоступном таймере означает «н/д», а не нулевую
нагрузку. Повторить после нескольких мазков рельефа и воды без Save; убедиться,
что карта и Undo не изменились от самого замера.
После объединения площадок дополнительно сделать на ровной земле широкую
ступень и одну детальную правку внутри неё, затем добавить воду. Проверить
верх и бок ступени, отсутствие щелей на границе tile, коллизию под курсором,
плавность во время мазка, Undo/Redo и Save/Reopen в обычном 3D viewport.
`tools/test_compact_dialog_layout.gd` проверяет первый показ обоих диалогов и
предпросмотр: окно не разрастается из-за текста за пределы заданного размера.
`tools/test_compact_extension_preview.gd` проверяет 3D-проекцию всех четырёх
сторон, отмену без сдвига сцены и ограниченную сборку тайлов на карте 4×4.
`tools/test_compact_projection_noop.gd` проверяет, что повторное открытие
неизменённой земли не сбрасывает готовые и ожидающие tile, а Apply/Undo
участка на четырёх сторонах сохраняют внутренние mesh и collision; для
карты 4×4 в очередь ставятся 168 tile вместо полной карты 5×4 из 720.

В обычном Forward+ Godot открыть 3D-панель и нажать «+ Карта» (либо выбрать
«Ember: Новая компактная карта…» в меню). Ввести свободный ID, оставить 1×1
 участок и высоту 8, обновить предпросмотр и создать карту. Высота новой ровной
 карты задаётся шагом 4 вокселя. Проверить, что новая сцена открылась, земля
 ровная и зелёная, а «Редактировать мир» сразу показывает четыре квадрата 8×8
 на блок и позволяет провести мазок. Проверить Ctrl+Z/Y, Ctrl+S и повторное открытие сцены. Повторный
ID должен давать отказ без изменения файлов. Создание файлов не отменяется
Ctrl+Z; это согласовано отдельно от Undo/Redo дальнейшего редактирования.
При первом открытии проверить, что окно целиком помещается на экране, нижние
кнопки видны, а большая пустая область под параметрами отсутствует. То же
проверить для «+ Участок» до и после выбора стороны.
Визуальная и живая UI-приёмка обновлённого диалога остаётся открытой.

Для теста большого мира открыть `scenes/large_landscape_test.tscn` после
перезапуска Godot. Несколько раз включить «Редактировать мир» и открыть/закрыть
«+ Участок»: земля не должна исчезать и собираться с нуля. После выбора стороны
в предпросмотре и при подтверждении новой полосы прежняя площадь должна
оставаться видимой; только полоса и стык достраиваются по очереди. В 3D режиме
«Редактировать мир» провести длинный мазок
«Рельеф ↑» и «Неровности» радиуса 1–4 блока в основном и детальном режимах;
оценить задержку во время движения мыши. Добавить воду текущей кистью и
проверить её вид через границу внутренних tile. Сделать Ctrl+Z/Y, Ctrl+S,
закрыть и снова открыть сцену. Затем нажать «+ Участок», добавить участок
справа: сначала выбрать «Ровный · короткий переход» и «Продолжить край»,
сравнить их форму непосредственно в 3D до подтверждения. Проверить, что на
стыке нет разрыва высоты, материала и воды, а отмена закрывает предпросмотр
без изменения карты. Подтвердить ровный участок, проверить новую поверхность;
повторить слева на отдельной копии или
после Undo, убедившись, что прежний рельеф и PlayerStart сдвинулись вместе.
Проверить Undo/Redo расширения и Save/Reopen. Записать ощущения и F3/FPS при
движении камеры; headless времена построения не заменяют эту проверку.

## Компактная земля: изолированный pilot 2026-09-26 — ручная приёмка OPEN

`scenes/terrain_region_pilot.tscn` читает только преобразованную копию берега
`content/terrain_pilot/beach_region.res`. Старые `.tscn` и Surface не
изменяются; Ctrl+S внутри pilot пишет черновик в `user://`, R открывает его.
Это проба нового source/mesh/collision пути, ещё не встроенная кисть нативного
3D-редактора и не migration-контракт.

Автоматика: `--headless --path . --script res://tools/test_terrain_pilot_projection.gd`
проверяет схему, привязку к хэшу копии, mesh/collision, локальную правку,
save/reopen и площадь 4×; `tools/test_terrain_pilot_session.gd` проверяет сцену,
кисти высоты/материала/воды, Undo/Redo и десять последовательных мазков.
Тот же тест проверяет поле и кнопки радиуса 1/2/4/8 блоков, охват и границу
8-блочной кисти, один большой и длинный мазок, их Undo/Redo и save/reopen.
`tools/test_terrain_pilot_brushes.gd` проверяет мягкий рельеф с глубиной и
спадом к краю, площадку по точке и числом, генератор с крупностью/детализацией
и устойчивым вариантом, сглаживание, непрерывность малого мазка при быстром
вводе, Undo/Redo, отмену при смене параметров и черновик. Замеры крупной кисти
разделяют обработку ввода, первый обновлённый участок и полное обновление.
Hidden Forward+ `tools/prototypes/qa_terrain_pilot_capture.gd` и
`qa_terrain_pilot_compare.gd` сохраняют пилот и прежний exact вид при одной
камере. Headless времена не заменяют живой editor/F6 UX и не учитывают объекты.

Ручной gate: открыть pilot как сцену и через F6 провести длинный и повторный
мазок на суше и у воды; сравнить его вид со старой копией берега при близкой
камере, особенно ступени, боковые грани, мелководье, швы участков и поведение
камеры. Поменять радиус в поле «Радиус · блоки» или кнопками 1/2/4/8,
проверить видимый контур и задержку одного и нескольких мазков радиусом 8 блоков.
В списке «Кисть» выбрать «Рельеф ↑/↓» и попробовать глубину 1 и 8 на одном
склоне. Затем «Неровности»: сравнить крупность 8/16/32/64 ячейки и деталь 0/3,
нажать «Другой рисунок». «Площадкой» выровнять небольшую область сначала по
высоте точки, затем по заданной мировой высоте; проверить край, Undo/Redo и
сохранение. «Сгладить» — убрать локальный выступ. При быстром движении маленькой
кисти не должно оставаться дыр между отпечатками.
Проверить режимы 1–6, отмену текущего мазка Esc, Ctrl+Z/Y, Ctrl+S,
закрытие и R. Отдельно оценить, остаётся ли автору понятно, какой результат
получается во время рисования. При визуальном отказе не мигрировать источники.

## Холст мира2026-09-14 — основа создана, визуальная приёмка открыта

`scenes/world_canvas.tscn` and `content/world_surfaces/world_canvas_surface.tres`
are a separate24×25 native map. TestPier scene/source and author props preserved;
project main scene unchanged. No legacy hydration or decorative water plane.
Source density16, height128/origin−32; dry floor+6, deep floor−20, sea0.
Coast maximum neighboring X step1vox; broad sand and no fine random relief.
`tools/world_canvas_layout.gd` authors initial content only, not a runtime provider.
`tools/build_world_canvas.gd -- --write` REFUSES existing Source overwrite.

PASS targeted: `--headless --path . --script tools/test_world_canvas.gd`:
validation/full grid/shore/fill; empty Props stays native; isolated F6 bootstrap
waits Surface physics; land/shore/deep rays match floor; wall paint; seam raise;
Undo/Redo/cancel; work-area plane pick in native frame; water level/Undo; loaded-path cache publication and baseline
immutability; post-Save Undo/repeat Save/reopen. Tests save ONLY `user://` fixtures
and verify hashes of authored scene/source and TestPier scene/source afterward.
World input sea0 stores32, not31; actual mesh/contact sample verifies top0.085
(established visual bias). Old authored fill arrays are not migrated.
Opt-in `tools/editor_test_world_canvas.gd` runs ONLY disposable ember-world-native
copies: native world opening, wall paint, water/working view, shared native Save,
reopen and post-Save Ctrl+Z/repeat Save PASS. The native shortcut is required:
direct per-scene UndoRedo.undo bypasses the manager's global redo stack and may
produce Inconsistent redo history diagnostics during native Save.
Related WorldEditor/SurfaceProjection/native water/Canvas workflow/TestPier PASS.
Standalone `tools/render_world_canvas.gd` Forward+ overview inspected. This uses
an extra fixture-only fixed camera; no editor-camera transform override or
author-file writes. Initial projection≈12s and shared map Save≈2.2–2.9s here,
not FPS/max radius results.
Native screenshot framing is separate from the functional fixture: background
synthetic F did not reach viewport focus. A QA-only camera transform immediately
before force_draw avoids the editor restoring its cursor on an intervening frame.
Explicit renderer camera transform and direct native 3D render-target capture
PASS / inspected; the background window composite was stale, not a missing map.
No claim of native camera-shortcut/manual ergonomics acceptance. Existing UID
fallback / occasional outside-tree get_node and scan-aborted teardown diagnostics
remain separate from functional PASS.

Manual: open WorldCanvas→3D→Редактировать мир; frame the full map using the
native viewport controls; view gentle sand and visible shallow floor; hide water to inspect
bottom; sculpt/paint/place objects; F6 walk. Approve layout before UX changes.
Do not treat the native fixture or screenshot as acceptance of camera/brush feel.

## Редактор мира прямо в 3D2026-09-14 — ручная приёмка OPEN

Весь утверждённый набор доступен через «Редактировать мир» в3D: общий Surface
карты, индивидуальные voxel-объекты, retained Canvas drafts, форма/покраска/берег/
дно/сглаживание/открытая вода/мягкое вытягивание/существующая кисть объектов.
Авторский Причал, две проверочные Surface-пропы и art/config drafts не заменялись.
Новая земля появляется только после явного выбора участка пользователем.

Автоматика: `--headless --path . --script tools/test_world_editor.gd` PASS.
Native UI construction; exact draft switching; one-action Undo/Redo/cancel;
empty construction-plane growth; negative-origin water; save/reopen; individual
rotated/scaled instance/source untouched; multi-asset publication failure + late
scene failure with exact rollback; prepare/finish native scene boundary; external
file conflict; deleted target; recovery/no newer-draft overwrite; soft grab;
partitioned leaf parity (7modes); exposed wall paint; clipped/locked water;
unrelated mesh identity; initial-worker edits; last-column physics removal;
exact ledge underside/seam fallback and accelerated ordinary heightfield PASS.
Blank-ground recovery/publication path and native owned snapshot after its root
is freed PASS. Requested water top/world origin (including voxel top-face offset)
and out-of-grid rejection PASS. New unplaced recipe variation previews retain
their existing explicit generator Save-and-place, not implicit world publication.

Related PASS: test_voxel_surface_sculpt, test_world_surface_projection,
test_surface_canvas_workflow, test_voxel_object_canvas, test_voxel_fragment,
test_native_surface_water, test_voxel_canvas_growth, test_voxel_canvas_context,
test_voxel_object_brush, test_voxel_cartoon_water, test_water_pattern_seams,
test_water_contact_boundaries, test_surface_height_slice. Final affected subset
rerun after Resource-copy/history/physics fixes. Existing Fragment test reports
one UndoRedo ObjectDB leak at exit; new World fixture explicitly frees its history.

Native opt-in fixture tools/editor_test_world_editor.gd ONLY in disposable
Temp/ember-world-native-* copy with own project user:// and cached imports.
Never enable that fixture plugin or --headless --editor in authored checkout.
Forward+ full24×25 Pier: native dock, create2×2 foundation, paint/water, real
EditorUndoRedoManager cross-target history, shared Canvas return, unique prop,
common Save and native menu Save/reopen, working-water Node.visible unchanged,
new collision present / StoneQuay collision not disabled, RMB pass/text shortcuts
PASS. Screenshot inspected. This drives native APIs/controller, not manual feel.
Native ray pick + mouse press/release→raise→one Undo→saved draft restored PASS;
empty-space construction-grid drawing checked without script errors.

Profiles (CPU fixture, not FPS): source19,660,800B; radius64 calculation≈0.66s,
apply+delta≈0.28s, history packing≈0.12s; raw delta2.59MB versus measured retained
history≈4.53MB. Full initial mesh+physics≈21.4s; ready projection at one seam edit
3visual≈38ms +3physics≈27ms. Native foundation stroke+frame0.6–1.3s, shared
source/prefab/scene Save≈11s. Full-filled terrain/max radius8blocks, peak transient
memory and idle recovery cost are not implied by these sparse-fixture numbers.

Ручной gate (контракт не закрывать заранее):

1. Open TestPier→3D→«Редактировать мир». На свободном месте выбрать участок,
   создать землю; не перекрыть старый Причал. Убедиться, что остальные колонки
   новой Surface пусты. На пустом месте поднять грунт от видимой плоскости.
2. Сделать длинный пологий берег/дно, проверить длину спуска; покрасить песок
   сверху и по вертикальной стенке. Мазки через границы фрагментов/ограниченного
   прямоугольника. Undo/Redo, Esc до завершения, обрезка on/off, большой радиус.
3. Добавить открытый уровень воды, менять/убирать её локально. Проверить живые
   пятна/пену/швы у берега и объектов; hide water→дно→обычный игровой вид.
   Godot scene lighting/environment controls remain native, not authored toggles.
4. Расставить несколько избранных/последних объектов повторными мазками без
   поиска. Выбрать одну повёрнутую/масштабированную доску; тянуть мягко, красить;
   Canvas→3D→земля: черновики и общая история остаются. Другие экземпляры/источник
   не меняются. При незавершённом мазке переключение цели не портит данные.
5. Ctrl+S (включая фокус текстового поля), Save menu, Save all/exit; reopen с теми
   же origin/source/unique bindings и всеми material/fill/authoring parameters.
   Нативное закрытие Save/Discard/Cancel, повторный вход/Recovery после аварии.
   Внешнее изменение source/deleted target: понятная ошибка, черновик не потерян.
6. RMB/MMB/Alt navigation; brackets outside text; F центр под курсором с возвратом
   обычного selection; камера не теряется. Проверить широкий viewport/dock layout.
   Для UI-кандидата проверить 1280×720 при масштабе 125%: слева выбрать
   «Форма» → «Неровности», затем «Покраска» и «Вода»; справа должны меняться
   нужные параметры без скачка размера 3D-вида. Вкладка `Ember · Мир` должна
   открываться при входе в режим и исчезать при выходе; штатный Inspector
   остаётся доступным. Раскрыть «Область и вид»/«Дополнительно», вернуться к
   кисти и проверить, что радиус, глубина, Ctrl+S и `+ Карта` доступны.
   На компактной карте переключить «Поднять» → «Сгладить» (включая детальный
   режим) → «Площадка» → «Покрасить» → «Вода» → «Убрать воду»: общий радиус
   сохраняется, сила видна там, где она действует, палитра — только при покраске
   и добавлении воды. Площадка показывает высоту при выключенной опции
   «высота по точке». Проверить, что переключение не меняет уже нарисованную землю.
   Сравнить с широким референсом: свои панели Ember графитовые, выбранная кисть
   и основные действия оранжевые, иконки различимы и понятны рядом с текстом;
   цвета штатного Godot и материала самой карты не считаются цветом UI Ember.
7. F6: новый берег/дно/навес визуально соответствует физике; старые части Причала
   всё ещё физические. Navigation остаётся top-surface, multi-level caves не scope.
   Коллизия индивидуального объекта обновляется при публикации, не во время drag.

Если максимальная кисть/Save/initial build мешают работе, сначала измерить их на
репрезентативном заполненном участке, а не заявлять «оптимизированный FPS».
Обновить текущую ручную приёмку после ответа пользователя и лишь затем закрыть
контракт. Не выполнять commit/push без отдельной просьбы.

## Мультяшная вода / поставленный prefab2026-09-14 — последний рисунок принят

Пользователь подтвердил последнюю коррекцию разрыва пятен («окей работает»).
Ниже сохранены автоматические и расширенные ручные gates; это не подтверждение
всех экзотических transform combinations или полного игрового прохождения.

tools/test_voxel_cartoon_water.gd PASS: ordinary/cached preparation retains
explicit fill, shared water geometry/material, dry-vs-wet collider face equality,
source definition unchanged, PackedScene save/reopen, actual harbour BayWater
material uses shared shader + background mode. Native disposable Forward+ PASS:
shoal/rock islands/pier, two frozen water animation samples visibly differ;
scene state read only, gameplay not launched. Related world Surface projection,
projection cache, contact boundaries, surface sculpt, Canvas workflow, palette PASS.
Pilot derived rebuild verified water presence and unchanged source/scene hashes.
Art correction: rotated/warped broad patches, shorter/thinner subdued glints;
tools/test_water_pattern_seams.gd PASS headless/native Forward+: independently
translated adjacent planes versus one plane have pixel diff0; animation PASS.
Standalone and combined native captures inspected. Cartoon water, world projection
and contact boundaries rerun PASS. Disable editor grid to distinguish its lines
from water seams; this fixture does not validate arbitrary author transforms.
Perspective reflection regression isolates camera reflection without patch contrast,
network or glints: abrupt quantized Fresnel reproduced FAIL (max jump0.168627),
continuous reflection PASS (0.003922, threshold0.012); seam diff0/motion still PASS.
Manual: tilt/move perspective camera and inspect long cuts through otherwise
continuous patches. Deliberate pixel-art patch/depth boundaries remain discrete.
Remaining user tear independently reproduced on harbour BoxMesh1800×2×1500
using live editor camera; visible even in unshaded continuous grayscale noise.
GPU X/Y lattice-boundary probe: old float hash FAIL591498 torn pixels; integer
hash PASS0. Native seam/motion/reflection still PASS. Check actual author view:
patches should cross former straight cuts continuously; their layout changes.
Manual: reopen 3D scene if cached old mesh persists; inspect water on placed pilot,
background harbour, gentle shoal and depth, shadows, moving broad patches, sparse
glints, thin shore/contact foam, chunk seams at offset/rotation/scale; reopen saved
scene, verify voxel geometry/collider unchanged. Deep water deliberately hides more
floor than shallow water. No full library rebuild, swimming or new physical water.
Latest author scene judgement accepted the corrected pattern; broader gates above
are not implied solely by this acceptance or automated PASS.

## Компактная проба реки — ручная художественная приёмка открыта

World Canvas startup gate (2026-10-05): `test_compact_world_startup.gd` в native
и headless воспроизводит период готовой земли/неготовых берегов и проверяет
отсутствие героя, cover/HUD, движение после открытия, стабильный вид, водопад,
карту без water controller и отмену при удалении сцены. Native `--cancel-startup`
проверяет закрытие Esc во время расчёта. QA-only `editor_test_compact_world_startup`
с `--world-startup-f6` и playback probe проверяет два настоящих F6 на копии
96×120 м / 20 участков и продолжение 3D setup. QA terrain привязывается по path,
дублирующий UID старой profiling fixture не должен подменять карту. Скриншоты
loading/loaded проверены. Авторские карты не используются для записи тестов.
Автор подтвердил работу запуска F6 (2026-10-05). Отдельный manual выход Esc
до завершения подготовки не зафиксирован. Ожидание не ускоряет CPU build;
disk cache остаётся отдельным контрактом; срез дальних деталей описан ниже.

Water detail distance gate (2026-10-05): согласованы и реализованы только
мелкие разводы/оптическая рябь по расстоянию камеры, defaults 40/100 м.
`test_world_look_panel.gd` закрывает drag одним Undo, оба значения в переносе F6,
нечисловые/вне диапазона snapshots, Save/Reopen/Discard. Native Forward+
`test_compact_water_detail_distance.gd` проверяет реальный fragment на near/mid/far,
непрерывность между региональными материалами, возврат камеры, перекрещённые
пороги и полный ближний материал. `test_compact_water_editor_preview.gd`
проверяет обновление региональных uniforms без нового build/foam history и с
прежней физической высотой; `test_compact_water_sun.gd` — реальный блик на
упрощённом пути. Guarded native editor проверил оба ползунка, Undo/Redo,
Save/Reopen/Discard; настоящий F6 загрузил 22/64 м во всех регионах.
Контрольная 192×120 м / 40 участков сохраняет геометрию/draw calls, медиана
дальнего кадра снижена примерно на 5%; точные данные/ограничения — документ воды.
Автор подтвердил работу среза дальности (2026-10-05). Это не закрывает прежние
отдельные художественные gates солнца/морского набега/речных разводов.
Слабый ПК/заполненные 256–512 м, геометрический LOD, остановка невидимых регионов
и постоянный кэш береговых данных этим gate не закрываются.

Static regional water disk cache gate (2026-10-05): реализован в существующем
Regions/SeaSwash, disposable helper `ember_compact_water_cache.gd`,
`user://ember-water-region-cache`. Source Resources/геометрия/шейдерная анимация
не меняются. Content/version/core/halo/origin key учитывает water/height/flow
payload соседей, ocean flags и labels компонентов (включая влияние flow за halo).
`test_compact_water_cache.gd` сравнивает fresh Save/Reopen с обычным расчётом:
records/info/static GPU records/shore/height, physical height/foam/wetness query,
palette-only reuse, локальную правку/Undo, дальний inlet и внешний flow. Проверены
fresh history, truncation/checksum/version/malformed/missing/I-O fallback,
cancellation и quota без удаления авторского fixture. Headless и native Forward+
cache parity прошли; исходные 702 GPU сравнения сохранены. Повторный runtime F6
проверяется с ожиданием World Canvas startup barrier, не только готовности поля.
Измерять worker phases, cache I/O/hits, geometry queue, main-thread upload и полный
запуск по отдельности; кэш не обещает сократить первый старт/RAM/VRAM/кадр.
Точные замеры, native editor Save/Reopen/Discard/F6 и ограничения — документ воды.
Component cache extension: fresh warm Resource должен иметь component_disk_hits
по всем участкам/component_builds=0, labels/spills и fields/query exact с расчётом.
Palette-only, local edit/Undo, distant inlet, neighbour flow, sparse growth/new
neighbour и минимальный waterfall drop проверяются независимо; malformed component
payload/type/range/dimensions/version/missing ремонтируются, coast cache сохраняется.
CLI `test_prepare_compact_water_cache.gd`: terrain/scene, source bytes unchanged,
ready cache, invalid path/source/argument и I/O failure. Авторские файлы не трогать;
подготовка не создаёт remesh/physics/GPU jobs и не закрывает shipping bake gate.
Расширенный water-cache suite PASS headless/native; CLI, regional seam/query и
WorldCanvas startup/input/camera/cancellation PASS. Guarded native editor:
brush/Undo/Redo/Discard/Save/Reopen/F6 PASS, fresh reopen 20 component hits/0 builds,
local brush 9 builds, Undo/Redo/Discard 9 disk hits. Runtime LOD/activity в editor
не появились. Отдельная 256 м native WorldCanvas fixture проверила startup barrier
и ходьбу; методика и before/after в Terrain Authoring → «Проба заполненного острова
256 м». Это не авторская приёмка большого F6 или weak-PC/export.
Native editor commands/runtime correct, но полный региональный harness FAIL:
один cold gap 105,84 мс после declared sleep превысил gate 100 мс. Причина пика
не изолирована; cold timing OPEN, порог не ослаблять и не объявлять весь suite PASS.
Manual OPEN: повторный F6 собственной карты, берег/пена/мокрый след после правки
и Undo. Заполненные 256–512 м/слабый ПК, geometry LOD, невидимые регионы и общий
streaming остаются отдельными gates.

Региональный water preparation gate (2026-10-04): `test_compact_water_regions.gd`
проверяет halo/seam/current-query parity, озеро через границу участка, дальнюю
связность после открытия/Undo inlet, persistent reuse/cancellation и источник.
`test_compact_sea_swash_gpu.gd` в native Forward+ проверяет исходные 702 сравнения,
GPU→GPU перенос истории заменённого поля и release. `test_compact_water_editor_preview`
проверяет тот же setup/контакты/параметры/Save и изменение света regional ground.
Guarded `editor_test_compact_water_regions.gd` включается только как QA plugin в
`Ember River Preview QA`, с копией 96×120 м и правильным path terrain (дублирующий
ext_resource UID удалить только в копии). Реальные Next/preview/Apply до 192×120,
одно Undo/Redo, Discard/отмена pending work, Save/Reopen/F6 проверены программно.
Поля построены один раз на стабильную revision; idle не повторяет field/mesh build.
Fixture сохраняет сырой межкадровый промежуток, declared OS sleep и отдельный
stall gate без этого sleep, а также CPU preparation/upload/bind/publication stats.
Исходный 10-секундный main-thread build был RED. Цифры и ограничения остаются
у Water Rendering → «Действующий путь пробы», не копируются в этот gate.
Manual OPEN: активная 3D/F6, прибой/пена/мокрый песок на стыках, новая локальная
правка/быстрые Undo/Discard во время подготовки, длительный lifecycle, слабый ПК,
полностью заполненные 256–512 м и общая память/CPU/GPU/draw calls. Разные водные
уровни и общий planar/underwater plane не объявлены принятыми этим срезом.

Обтекание неподвижных препятствий сравнивается в `scenes/compact_wave_obstacle_study.tscn`.
`test_compact_wave_obstacles.gd` использует fixtures: отражающий Box/Circle,
CFL, конечность и ограниченность height, ослабление lee/сохранение боковой волны,
live seek от того же bake, большие/обратные time jumps, выключение, неизменность
terrain и disk cache invalidation при повороте/удалении. Sea/query/removal читают
общую поправку. Forward+ проверяет реальное vertex displacement и равенство
GPU поля обоих режимов при одном времени. `test_world_look_panel` проверяет enum
Undo/Redo, цельный F6 snapshot, запрет дробного mode и Save/Reopen/Discard.
`capture_compact_wave_obstacles.gd` снимает реальную реку/море при mode 0/1/2,
проверяет отсутствие animation remesh/column revision и новых solver steps в bake,
pause/restore при runtime движении без новых bake файлов; ABBA timing суммирует
GPU timestamps активных viewports и отдельно замеряет solver CPU. Это сравнение
на RTX 5070, не доказательство FPS слабого ПК. Native disposable QA прошёл 3D
shared field, F6 OptionButton/strength/apply/ack, одну Undo/Redo, программный Save
и fresh-process Reopen/второй F6; известные shutdown warnings остаются.
Ручной gate: обе формы/направления/размеры препятствий, тонкий гребень и пена,
граница участка/замыкание цикла, 3D/F6, перемещение в editor, strength 0/1,
native Ctrl+S/Reopen/Discard и длительная работа/целевой слабый ПК. Не принимать
это как симуляцию горизонтального течения, движущихся тел или произвольных mesh.

Один водопад вынесен в `scenes/compact_waterfall_study.tscn`, действующий результат —
`EMBER_WATER_RENDERING.md` → «Пробный водопад». `test_compact_waterfall.gd` использует
fixture: направление/перепад, отсутствие uphill перелива, lower-wet маска,
неизменные Resource/ground collision, жизнь/скорость/отключение impact и пены,
чистый rebuild, общий Water mesh/material/query и отсутствие remesh анимации.
Forward+ дополнительно проверяет изменение реального кадра при выключенных прочих
волнах и удаление струи/impact при силе 0.
`test_compact_waterfall_approach.gd` отдельно воспроизводит подмешивание верхнего
дна: смена цвета opaque поверхности за струёй должна оставить её тело неизменным.
Также проверяет видимые/движущиеся верхние полосы, локальность (дальняя/нижняя вода
не меняется), разворот вместе с направлением перелива и отключение силой 0;
обе ошибки дали RED до соответствующей правки общего shader.
`test_world_look_panel.gd` переносит
четыре отличающихся waterfall значения одним snapshot/Undo и сохраняет их в сцене.
Native disposable QA проверил editor 3D поле, видимые F6 регуляторы, apply/ack,
один Undo/Redo, программный Save, fresh-process Reopen/второй F6 и нижний ракурс.
При закрытии QA editor остаются известные scan-aborted/ObjectDB warnings;
этот PASS не объявляет весь lifecycle редактора чистым и не заменяет native Ctrl+S.
Ручной gate: 3D/F6, край/основание струи и низкие боковые ракурсы, плавность/скорость
при 0,2/1/2, неровность при 0/0,65/1, пена при 0/0,75/1, сила при 0/1,
Undo/Redo и Ctrl+S/Reopen/Discard. Проверить, что верхняя вода и сухой берег не
получают нижний impact, нет дыр или лишних прямоугольных стенок; оценить затухание
дуг/web. Общие underwater/planar planes ещё не принимаются для нескольких уровней.

`tools/test_compact_water_editor_preview.gd` проверяет общий tool-контроллер,
поля пены/течения, скрытие старого кругового контакта, Undo/Redo настроек и
сериализацию без производных узлов.
Проверяет также реальные сохранённые sky/obstacle/waterfall сцены: одобренные
Sun/ripple значения и сечения Box/Cylinder при уровнях 15,27/16,02. Это ловит
риг, оставшийся над водой после понижения уровня, который fixture не обнаруживал.
Native scene branch проверяет material identity, ripple field и два точных контура.
Только в disposable checkout его editor
режим дополнительно проверяет перемещение/отключение объекта и обновление
после правки земли; `-- --native-scene` снимает реальную вкладку 3D в Forward+.
`tools/test_compact_river_phase.gd` проверяет шаг фазы на прямом и повёрнутом
потоке, непрерывность текущего изгиба и обоих берегов, пустое течение и
неизменность исходного Resource. Это не тест нескольких отдельных русел.
`tools/test_world_look_panel.gd` проверяет вкладки «Свет и цвет»/«Вода», общий
scene owner регуляторов, один шаг Undo за drag, Save/Reopen/Discard и отключение
ссылок закрытой сцены. Runtime snapshot проверяется как одно Undo/Redo,
Save/Reopen/Discard; неверный scene/node path, NaN, диапазон и неизвестные поля
не должны частично менять сцену. Повтор того же набора не создаёт новый Undo.
Preview-тест дополнительно проверяет независимость
береговой/объектной ширины, обновление движущегося аналитического контура,
образцы расходящихся дуг, скрытие второго flat wake и затухание после остановки.
Живой образец обязан сохранить исходную точку при следующем emission.
`tools/test_compact_water_sun.gd` запускается в disposable Forward+:
на fixture настоящий Sky/sun должен давать блик в реке и море; diagnostic
настоящего fragment проверяет одинаковые roughness/specular при flow 0/1,
glints 0/0,32/1 и sky roughness 0/0,45. Пустой край coastal state texture
не должен наклонять нормаль плоской воды к ложной высоте 0. Обе причины
по отдельности воспроизведены RED → GREEN. Native runtime capture той же
пробной карты фиксирует камеру/свет/время: `tools/capture_compact_water_sun.gd`,
`docs/art/references/compact-water-sun-before-after.png`. Manual gate: 3D/F6,
река → устье → море, низкий ракурс, движение/форма блика на морском набеге.
Сила/размытость неба и блики остаются у прежнего World Look/scene owner.
`tools/test_compact_ripple_field.gd` — disposable Forward+: настоящая новая
текстура/fragment, переиспользование без генерации на кадрах, конечные значения,
невыделяющийся периодический край, shape morph и его отключение/плавный соседний
кадр. `test_world_look_panel.gd` дополнительно проверяет Sun+water snapshot,
отказ без частичного применения при неверном угле, общий Undo/Redo, drag одной
оси, независимость другой и Save/Reopen rotation существующего Sun.
Manual: новые ползунки размера/деформации/скорости ряби, glints 0/0,32/1,
размер солнца 0,5–1° и 2,9°, низкий ракурс/3D/F6. Изменить поворот/высоту/силу
солнца в F6, применить в редактор, Ctrl+Z/Y, Ctrl+S, Reopen и новый F6.
Сравнение реального renderer — `docs/art/references/compact-water-ripple-comparison.gif`.
Нативный QA UI/debugger/Undo/Save/fresh reopen пройден программно; ручной визуальный
gate и слабый ПК остаются открыты. Авторские scene/terrain прежние.

`tools/test_compact_water_arc_response.gd` запускается в disposable Forward+
через `--path <qa-copy> --script res://tools/test_compact_water_arc_response.gd`:
диагностический fragment вызывает реальные функции шейдера без копии wave math.
Проверяет выступающий по течению центр при flow +Z/-Z и плавное нарастание новой
реакции; до исправления обе проверки были красными. Реальная функция пенных
разводов должна увеличивать их длительность при росте lifetime и давать ноль
при strength 0 и river speed 0. Общий width pulse проверяется на GPU: плавность
по времени, ограниченная ширина и возвращение к постоянной при силе 0.
Реальная shore foam функция должна сохранять корень у мокрой границы на ширинах
0,4/1,8/6 и при максимальных motion/pulse; увеличение ширины растит только
внешний край, сухая сторона и дальняя вода остаются пустыми. До исправления
фиксированный distance 0,4 давал ноль на ширинах 0,4/1,8, после — пену.
Уровень воды: GPU diagnostic по world vertex Y проверяет сдвиг −0,5;
preview regression проверяет аналогичный сдвиг physical query/возврат при 0 без
изменения authoring levels, column revision или field rebuild. Отрицательное
значение включено в общий snapshot Undo/Redo/Save/Reopen и native F6-перенос.
Ручной gate: 0/−0,35/−0,75 в 3D/F6, мелководье/море, оба берега, контакт объектов,
камера погружения; нижние грани воды на дне. Само смещение уровня не добавляет
воду на сушу; морской набег проверяется отдельно ниже.
Новый параметр проходит snapshot Undo/Redo/Save/Reopen и настоящий F6-перенос
в отдельном native editor, затем повторный F6 после нового открытия.
`capture_compact_water_surface.gd` сравнивает
до/после при одинаковой фазе/авторских значениях и проверяет отсутствие rebuild
terrain-полей от изменения новых регуляторов.
`tools/test_compact_sea_swash.gd` PASS headless и Forward+ в disposable copy:
реальная очередь projection после остановки должна возобновиться и создать
dry-bank вершины в прежнем Water mesh, затем убрать их при снятии поля.
Проверяются приход/пена/откат/высыхание, покрытие и билинейная высота query,
reach 0, high-bank barrier, flow guard, landlocked puddle и неизменные authoring
channels/column revision. Forward+ часть использует настоящий water/ground shader:
пиксель песка меняется при набеге, темнеет после отката, возвращает исходный цвет
после высыхания. Неверная выборка экранного пикселя/экспозиция fixture исправлены;
render failure завершает тест ненулевым кодом и не печатает итоговый PASS.
Sea history проверяет рождение сетки на прошедшем входящем гребне, отсутствие
следа впереди него, старение на откате и запрет новых births при выключенной волне.
GPU diagnostic вызывает настоящую `study_sea_foam_trails`/общую pattern функцию,
изолируя её цвет от освещения: longer lifetime сохраняет больше старых линий;
sea trail strength 0, sea height 0 и полное старение дают ноль; river strength 0
не выключает морской рисунок. Birth/death и смена ширины при откате непрерывны,
дальность/сила подхода меняют offshore профиль, но сохраняют высоту у берега.
Query включает ранний профиль за прежним порогом 15 вокселей. River GPU regression
сохраняет прежний результат после выделения общей pattern функции.
`capture_compact_water_surface.gd -- --sea-swash` проверяет завершение очереди,
отсутствие field rebuild от скаляров и записывает один и тот же цикл до/после.
`-- --sea-foam` сравнивает тот же набег без сетки/с ней; переключается только
морская trail strength, остальные авторские параметры/фаза одинаковые.
`-- --sea-approach` сравнивает точки рождения 6/20 нового профиля, без field rebuild.
GPU history теперь проверяется `tools/test_compact_sea_swash_gpu.gd` в native
Forward+: сравнение с CPU reference через несколько циклов, rewind, выключение,
смена drying, холодные запросы, текущая билинейная физика и перенос истории
существующего поля; повтор frozen preview не делает dispatch, удаление owner
освобождает GPU handles. Headless сохраняет прежний reference для data gates.
На RTX 5070 / авторских 96×48 м / 113 117 активных клетках CPU-подготовка
обновления ~1,58 мс вместо ~47. Активные 90 кадров native 3D: median 6,98 мс /
p95 7,86; настоящий F6: median 7,17 / p95 10,65. Coast/terrain rebuild = 0,
scene/terrain-файлы неизменны. Детали и caveats — Water Rendering → «Морской набег».
После установки использовать обычное переоткрытие редактора: принудительный
keep-state reload изменённого sea leaf завершил редактор. Он восстановлен.
Отдельные GPU/pixel tests чистые; native `--editor --script` fixture сохраняет
Godot window/cleanup warnings и не доказывает чистый lifecycle всего editor.
Все пять sea/sand значений прошли snapshot Undo/Redo/Save/Reopen/Discard,
настоящие F6-ползунки/кнопку/debugger, единый native Undo/Redo, Save и новый
editor → второй F6. При выходе остаются прежние Godot scan/ObjectDB warnings.
Manual: оба морских берега, устье, высокие ступени, несколько периодов,
height 0/2,8/4, reach 0/10/16, period 4/9/16, wet strength 0/0,55/1,
drying 3/12/20, уровень 0/−0,35/−0,75, низкий ракурс/плавность; река сохраняет
свой путь. Морская сетка: соединение с гребнем, дрейф/распад на откате, strength
0/0,38/1, lifetime 0,3/2,2/4, отсутствие белого следа на осушенном песке.
Пять новых sea exports проходят общий snapshot/validation/Undo/Redo/Save/Reopen/
Discard: approach distance/strength, crest foam и отдельные sea trails strength/lifetime.
Manual: начало 6/20, сила 0/0,65/1, морская пена 0/1 отдельно от разводов;
включая coastal obstacle patches. Речные настройки сохраняются.
Нет автоматической приёмки переворачивающегося гребня, полной fluid
physics, погоды, больших карт или телефона. `EMBER_WATER_RENDERING.md` — результат/границы.
Native ordinary-editor QA в отдельной копии проверил настоящий
EditorUndoRedoManager через ползунок панели и штатные Save/Reload. Итоговый PASS
без script/shader errors; при выходе Godot предупреждает `Scan thread aborted`.
Живая пользовательская Save/Reopen/Discard и художественная приёмка открыты.
F6-перенос дополнительно проверяется с настоящим editor debugger: несколько
ползунков → «Применить в редактор» → единый Undo/Redo → Ctrl+S → закрыть редактор,
открыть заново → следующий F6 с теми же значениями. Без применения исходная
сцена не меняется; standalone не предлагает активную кнопку переноса.
В disposable editor автоматический `reload_scene_from_path` после F6 выводит
внутренний `List::erase`; это воспроизведено также без debugger plugin/переноса.
Отдельный открытый случай, не подменять им проверку обычного Save/Reopen.
`tools/capture_compact_water_arcs.gd` сравнивает мягкий/чёткий гребень, контакт,
движение/остановку и ширину панели; `-- --live-motion` снимает настоящую F6-пробу
движения камня. Forward+ runtime capture завершился с exit 0 без ошибок/предупреждений.

`tools/test_compact_river_study.gd` проверяет изогнутое мокрое русло, векторы
течения, одинаковую глубину общих вершин, неизменность исходной пробы,
validation и save/reopen. `tools/test_compact_river_water_contact.gd` проверяет
выбор compact projection, маску у берега, след в потоке, исчезновение контакта
на сухой земле и сечение прямоугольного/круглого объекта. Тест расширения карты проверяет перенос векторов на старых
блоках. Контакт с `top_level=true` обязан сохранять ссылку на прямого
родителя; Forward+ capture проверяет, что R8-маска двух объектов дошла до
материала поверхности. При белизне гребня 1 проверить низкий ракурс и оба
берега: короткая рябь не должна рисовать частые полигональные белые полосы.
Forward+ кадры в двух
моментах и проба с выключенными речными волнами создаются
`tools/capture_compact_river_study.gd`; этот же захват сравнивает три ракурса
при «Искажении» 0, 0,005, 0,015 и 0,035, отдельно нулевую высоту волн, пену 0 и
приближённый 3D-вид редактора без камеры дна. Близкий ракурс сравнивает
узкую/широкую/мягкую пену, неподвижный/сильный ход и максимальную белизну
гребня; кадр F6 показывает всю панель без обрезки. Старые кадры отражений и
подводного вида снимаются через `tools/capture_compact_sky_reflection_study.gd`.
Manual: открыть `scenes/compact_sky_reflection_study.tscn` и сначала в обычной
вкладке 3D проверить береговую пену и контуры камня/столба.
В «Редактировать мир → Вид мира → Вода» сравнить «Белизна гребня» 0/1,
«Чёткость гребня» 0/1, расстояние между волнами и раскрытие дуг;
центр дуги должен идти впереди её краёв по потоку. «Неровность гребня»
0/0,45/1 меняет фактуру узкой пенной линии, а не сетку поверхности;
ширину/чёткость объектной кромки менять независимо от береговой пены.
Параметры остаются также у `PlanarReflection` в Inspector. Изменение настроек не должно
перестраивать землю. Сдвинуть камень, Undo/Redo, вернуть исходное положение;
контур должен обновляться без старого круга. Ползунок отменяется одним Ctrl+Z.
Сравнить блики 0/0,32, разводы 0/0,38, затухание 0,3/2,2/4 с и разрывы
береговой пены 0/0,4/1, изменение толщины 0/0,45/1. Проверить неровную сетку:
линии соединяются с гребнем, плавно движутся и распадаются без скачков/ровной решётки.
Проверить толщину у обоих берегов и квадратного/круглого объекта, вблизи и издалека;
внутренняя грань контакта остаётся отсечённой. Фактура затухает после гребня;
цвет/глубина сохраняются, крупные волны остаются читаемыми. Проверить
«Применить в редактор» и единый Ctrl+Z/Redo до сохранения выбранных значений.
Save/Reopen и Discard должны
сохранить/восстановить авторские значения и заново вывести временные поля.
Затем запустить F6 (камера открывается на реке), от верхнего расширения пройти
вдоль русла до устья, повернуть камеру низко над
водой, кнопкой «К морю» сравнить с прежней гладью. Сравнить
«Скорость реки» и «Волны реки» при 0 и текущих значениях; заметить, нет ли
регулярных полос, резкой границы движения у устья или разрыва поверхности.
Низко над водой пройти и посмотреть вдоль реки в обе стороны при максимальной
высоте волн и «Плюпанье»: гребни на мелководье не должны проваливаться через
дно, выходить поверх суши или открывать угловатые пустоты. Сравнить «Пена у
берега» при 0 и 0,6, ширину от 0,7 до 4 вокселей, чёткость при 0 и 1 и
«Ход пены» при 0 и 3,5: кромка должна оставаться на мокрой стороне и идти с
волной, включая устье. Белизна гребня при 0 не должна менять волну, при 1
должна следовать за ней; подобрать более слабое игровое значение. У камня и
столба сравнить контакт на двух фазах: линии должны повторять разные формы,
не рваться и двигаться вместе с поверхностью; герой сохраняет обычный след при движении.
Кнопкой «Проба следа: двигать камень» включить движение: у помеченного камня
должны расходиться несколько задних дуг с небольшим изгибом воды; при остановке
след затухает. Сила реакции 0 отключает этот отклик; скорость/раскрытие меняют его
рисунок. Сравнить скорость 0,4–0,5 и время появления 0,35–0,6 с: дуга должна
плавно нарастать и не перескакивать при появлении следующей.
Контур движущегося камня следует его форме, дуги остаются на воде.
В нативном 3D-виде и F6 поднять «Искажение» до текущего значения: светлые
пятна не должны возникать у берега, а песчаные ступени не должны сильно
искривляться. Проверить погружённую часть персонажа возле берега.
Оценить песчаный спуск, затем подводный режим и прежнее море. Художественная
приёмка пены и контактов открыта; нынешний морской набег на низкий сухой песок
проверять по gate выше, отдельный водопад — по сценарию в начале этого раздела.

## Мягкий край берега2026-09-14 — ручная приёмка открыта

Смежная проверка 2026-09-30: `test_compact_material_patterns.gd` сообщает
`PNG import did not update draft`. Тот же отказ воспроизведён в disposable copy
без нового coastal include/wetness блока ground shader. PNG importer, dialog
и авторские материалы водным срезом не менялись; этот gate остаётся открытым
для отдельной диагностики в теме материалов.

tools/test_voxel_shore_soft_edge.gd PASS: parallel coast stroke radius16/depth4/
length60/−X, quiet full center depth and cross-rim jumps≤1 voxel, midpoint/rim
strength, repeated gesture and split-event invariance. Real UI roughness15,
surviving colors unchanged, no water mutations, Undo/Redo/save/reopen/discard.
Native disposable Forward+ PASS; before/after captures inspected. Shore/facets/
surface pattern related PASS. No general ≤1 guarantee for other depth/noise.
Manual: Undo previous steep cut, «Новое начало», set source anchor at shore,
paint along and toward−X with reported settings; compare soft rim, repeat and
Undo. Exposed green below sand is original data: use sand paint after sculpt.
Verify water/props unchanged. Acceptance on actual author coast remains open.

## Совместный берег / песчаные стенки / открытая вода2026-09-14

tools/test_voxel_coastal_workflow.gd PASS: quiet gentle slope, non-accumulating
separate/adjacent strokes, presets/custom/legacy profile, persistent/reset anchor,
exposed walls versus buried terrain, shortcut radius, actual UI water fill from
dry source, level lowering/fringe removal, scope-clipped replacement preserving
outside water, count limit, old basin guard, Undo/Redo, save/reopen/discard.
Shore/surface pattern + six related suites PASS (facets, surface sculpt, Canvas
workflow, palette, water boundaries, height slice). Disposable native Forward+
PASS; combined coastal_workflow_native.png inspected, no author map mutations.
Manual acceptance remains open: depth8/12 + presets, custom length96/256; paint
separate overlapping/adjacent strokes from same anchor, then «Новое начало»;
sand chosen colors/coverage/scale on top and step walls, masks/locks; open water
height and click below plane, lower level/remove, region edge, Undo/save/reopen.
For already carved steep coast Undo first: gentle preset does not raise terrain.
Compare floor-only and floor+water views; shader readability is not accepted by
these technical checks. The following first-trial limitations are historical.

## Рисунок поверхности / песок — первая проба2026-09-14

tools/test_voxel_surface_pattern.gd PASS: controls/seed, top voxels only,
occupied/heights/channel invariance, repeat/coarse/segment density, 0/100 endpoints,
profile serialization/defaults/fresh workspace reopen, shore shortcut/plain paint,
actual picker beneath water, one Undo/Redo, source save/reopen/cancel/discard,
region clipping, locked voxel, height-slice guard and canonical palette edits.
Seven related suites PASS: shore, facets, surface sculpt, Canvas workflow, palette,
water contact boundaries, height slice. Native disposable Forward+ PASS; floor
and combined-water captures inspected. This is not user artistic acceptance.
Manual: shore → «Оформить дно», or Покраска → рисунок поверхности/песок; select
base and patch colors, size8/24/64, coverage0/35/100, repeat/adjacent strokes and
new seed. Verify shape/water untouched, Ctrl+Z, save/reopen, group mask/locks.
For clearer color judgement use «Слои · только дно», then return combined view.
Side walls/buried layers are not painted; contrast comes from chosen colors.

## Отмель и дно — первая проба2026-09-14

Automated tools/test_voxel_shore_relief.gd PASS: fixed origin, monotonic shoal,
width/direction/roughness/seed, carving/depth/deep holes, coarse/density/revisits,
edge/region clipping, real pick, editor profile/tool switch, one Undo/Redo,
save/reopen/cancel/discard, unchanged water channels and preview water surfaces.
Related faceted relief, surface sculpt (water fills), palette, water contact
boundaries, Surface Canvas workflow PASS. Native disposable Forward+ PASS.
Manual: Canvas → Рельеф → Генератор → берег и дно; paint toward ±X/±Z from first
click; compare width4/24/64, roughness0/15/40, coarse, edit region, Undo, reopen.
Test existing water fill then floor-only view; same plane, props/pier unchanged.
Water appearance not artistically accepted by technical capture; no shader
redesign in this slice. Gate remains open until user's scene/visual acceptance.

## Передвижение вне боя — 13 сентября 2026 (ручная приёмка открыта)

`tools/test_explore_stepping.gd` PASS: настоящая CharacterBody capsule и
StaticBody collision, плавный физический подъём до 1/4 блока при 30/60/120 Hz,
декоративная ступень 0.5 world units, последовательные ступени, диагональный
подход, отказ у высокой стены/низкого потолка, release без зависания.
Camera gate: initial height без задержки, upward lag/catch-up, XZ direct,
малый downward recovery не удаляет ascent lag, descent direct и reset.
Native Vulkan Forward+ на RTX 5070 проходит тот же fixture с -- --capture;
mid-ascent capture просмотрен. Это автоматический input/physics/render fixture,
не ручная оценка движения в пользовательском редакторе.

Related headless PASS: camera_relative_movement, party_followers, party_save_v2,
health_consumables, inventory_equipment, explore_pause_menu и test_test_pier.
Pier gate использует изолированный user:// save root, проверяет menu load/reopen
и неизменность обычных v1/v2 saves. Логи Temp/ember-explore-step.log,
ember-explore-step-forward.log и ember-explore-test_*.log.

Ручной gate: F6 Причала → WASD через края досок и обратно; затем пройти несколько
ступеней подряд и по диагонали, отпустить движение на подъёме. Герой не должен
резко прыгать/зависать; камера плавно догоняет новую высоту, XZ без задержки.
Высокие грузы остаются препятствиями. Проверить Миру следом, Tab и сумку,
save/load после остановки наверху. Сцену/authoring sources тесты не переписывают.
Свободный jump, sprint и изменение боевого MOVE/JUMP сюда не входят.

## Общий Git checkpoint2026-09-13

Новый checkpoint после Grab/clip/library/merge scene-axis bake:16 повторных
targeted suites PASS — grab/bend/boundary_clip/fragment/stamp/pattern/
selection_interaction/merge_orientation_bake/merge/object_library_updates/
object_library_layout/object_canvas/scene_assembly/object_split/shapes/
editor_filesystem. Логи Temp/ember-checkpoint-test_*.log. Staged16 canonical
sources validate и15 prefabs load/instantiate PASS (ember-checkpoint-assets.log);
авторские файлы проверялись read-only. Fragment fixture:1 ObjectDB leaked on exit;
prefab vox_shape_block_1205809337_canvas_1838453066: mesh UID fallback на
существующий staged .res path. Не zero-warning gate и не общий128-suite repeat.
Checkpoint сохраняет авторские boards/merges/scene; .codex/config.toml/Mira drafts
исключены. Открытые manual/live editor gates не объявлены закрытыми самим Git.

Отдельный срез2026-09-13: opt-in exact orientation bake при склейке.
`test_voxel_merge_orientation_bake.gd` PASS: все24 proper signed-axis rotations,
density16→32, exact world cell centers/colors/6 channels/parts/groups/overlap
сопоставлены с обычным merge. Primary-grid alignment report прежний при bake;
common arbitrary/nonuniform/reflection/shear запрещены только при bake, обычная
склейка сохраняет прежние capability. Проверены baked height limits, source
immutability, UI error/recovery/default off, display toggle independence,
полный visible viewport, one Undo/Redo, source hashes, save/reopen и unmerge.
Canvas открывает canonical flat bridge clean; top ray pick и sculpt/Undo PASS.
Related8 PASS: merge/shapes/scene_assembly/object_canvas/object_split/
assembly_canvas/object_library_updates/layout. Logs Temp/ember-merge-bake.log
и ember-bake-test_*.log; это не общий regression checkpoint.
Disposable native Forward+ merge-bake-editor-verified.log: enabled/local flat/
commit/frame/Canvas open/Canvas clean=true; captures merge-editor-baked-local.png
и merge-editor-baked-canvas.png просмотрены. После DONE в teardown есть get_node
outside active scene tree + scan abort; полностью зелёный editor lifecycle этим
probe не заявляется. Рабочий editor/авторские assets probe не менял.
Ручной gate: пересклеить пользовательский настил с «Запечь ориентацию сцены»,
открыть Canvas, проверить ориентацию/кисти, Apply/Undo/save/reopen. Старые assets
и авторская сцена не переписываются автоматически; unsupported угол не округлять.

Отдельный UI fix2026-09-13: preview склейки/разбора в ориентации сцены.
`test_voxel_merge.gd` PASS: rotated primary + rotated/nonuniform scaled parent,
rebase world translation; shared frame у result/ghost/overlap; toggle off/on
без remesh/replan/Resource/scene mutation; gui_input drag/zoom/reset;
preview целиком виден над длинным alignment status без scrolling. Commit при
локальном виде не меняет scene frame; Undo/Redo и save/reopen сохраняют pose;
разбор имеет тот же default scene toggle. Existing sculpt/discard/alignment
checks остаются. Related7 suites PASS: shapes/scene_assembly/object_canvas/
object_split/assembly_canvas/object_library_updates/layout. Не общий прогон.
Native Forward+ visual/input gate: сравнить горизонтальный настил в scene/local
режимах, вращение/zoom/reset и применение/Undo в рабочем редакторе.
Автоматические logs: Temp/ember-merge-orientation.log, ember-merge-test_*.log.
Disposable native editor Forward+ PASS: generation-smoke/merge-orientation-
editor-final.log (default/scene basis/local basis/orbit/reset=true). Captures
app_userdata/Ember Generation Smoke 20260912/merge-editor-scene/local/orbit.png
просмотрены: весь viewport виден, настил горизонтален только в scene view.
Gui_input проверен через signal routing; настоящие mouse gestures и Apply на
пользовательском мостике — ручной gate. Startup UID warnings и scan abort при
завершении относятся к disposable copy, новых compilation errors нет.

Отдельный targeted fix2026-09-13: актуализация открытой библиотеки объектов.
`test_voxel_object_library_updates.gd` PASS: успешный install нового/существующего
asset уведомляет после публикации files/cache; source read/validation/roundtrip,
нет изменения draft; error не уведомляет. Соседние saves coalesce в один refresh;
query/filter/selection/unrelated textures остаются; hidden shelf откладывает
refresh до visibility; observer отключается при разрушении панели.
Related PASS: object_library_layout, object_canvas (Undo/Redo/save/reopen),
workshop_generator_save, editor_filesystem, shapes и object_split. Всего7 suites
PASS; не полный повтор всех scripts.
Native disposable editor Forward+ reproduced before fix: save=true, AUTO0,
REOPEN0, direct refresh1; после fix AUTO1/REOPEN1 без ручного refresh или
пересборки всех объектов. Логи generation-smoke/library-before.log,
library-after.log; targeted Temp/ember-library-test_*.log. Дополнительный native
library-after-final.log: asset опубликован при скрытом shelf, при реальном
повторном показе bottom panel REOPEN1/VISIBLE=true для нового второго ID.
Startup UID warnings в disposable copy и scan-thread-aborted при закрытии
тестового editor не являются новыми compilation errors или ошибками публикации.
Ручной gate: в живом редакторе с обновлённым плагином найти384406539, создать
новую форму при открытой библиотеке, сохранить независимую Canvas-копию,
найти её по ID без очистки текущего поиска/смены фильтра/перезапуска библиотеки.
MCP живого редактора был недоступен; пользовательская сцена/доска не менялись.

Проверены все128 `tools/test_*.gd`:125 PASS с учётом повторных проверок в
изолированном export подготовленного Git index и native screenshot сборки.
На момент checkpoint оставались3 незелёных gates:

- `test_voxel_split_preview.gd:12` ожидает EmberVoxelProp в
  `Map/Terrain/TimberPier/Visual`; сейчас там сборка Node3D с деталями.
- `test_voxel_placement_preview.gd:23` жёстко ожидает12 children той же сборки;
  авторская сцена уже изменена. Native повтор подтверждает устаревшее ожидание.
- `test_voxel_sandbox_native_batch.gd`: устарели prefab signatures для
  vox_ms8vsb53,vox_vil_bush,vox_vil_counter,vox_vil_mailbox,vox_vil_planter,
  vox_vil_sign. Нужна отдельная проверка/пересборка, не переписывать авторские
  assets автоматически ради Git checkpoint.

Повторная проверка2026-09-13 закрыла все3 оставшихся gates:

- split preview теперь использует отдельную native доску80×3×80 в `user://`:
  четыре секции64vox, край16×3×16, без изменения исходника/pose и без записи
  производных данных до Apply. Реальная резка/Undo покрыта object_split.
- placement preview проверяет нынешнюю сборку Причала с валидными native
  деталями, без жёсткого равенства12 children. Все старые rotation/pivot/snap/
  no-mutation/layout проверки сохранены; native1280×720 и1600×900 PASS.
- sandbox native batch PASS: все6 Resources совпадают с reviewed conversion,
  prefab актуальны, candidate queue пустая. Пересборка и запись assets не нужны.

Headless и native Forward+ split/placement PASS; captures просмотрены.
Полный набор scripts после этих исправлений повторно не запускался: это
закрытие трёх известных gates, не новый общий regression checkpoint.

## Общая обрезка по границе (ручная приёмка открыта)

`test_voxel_boundary_clip.gd` PASS: strict defaults/backward layouts, crop
canvas/region/slice для move/copy/rotate/bend/Grab/stamp/scatter/indent/pattern;
полностью cropped move/Grab и dialog preview пустой геометрии. Все populated
channels, owners и group membership вне editable mask сохраняются; locked
source/destination остаются защищёнными. Validation, один Undo/Redo и
Resource save/reopen для clipped транзакций. Editor toggle не меняет Resource,
переживает tool switch и roundtrip существующего view store.
UI fragment ghost использует final selected destinations; toggle пересчитывает
активный preview, Apply совпадает с ним. `test_voxel_grab.gd` дополнен live crop
preview на slice, exact pointer-up, восстановлением crop через Undo/Redo,
доступностью Grab на срезе и отменой жеста при смене общего режима.

Related targeted PASS: bend, fragment, stamp, pattern, selection_interaction,
selection_mask, workshop_layout, surface_height_slice, surface_sculpt.
Предсуществующий fragment fixture сообщает1 ObjectDB leak; новые clip/Grab
проверки не сообщают leaks/script errors. Не повторный полный regression run.
Native Forward+ Grab clip1280×720 PASS, disposable generation-smoke;
capture просмотрен, тогл читается в «Части → Вид», срез12vox, cropped preview
помечен «Черновик». Логи Temp/ember-boundary-*.log и
generation-smoke/native-boundary-clip-final.log.

Ручной gate: уникальная доска → включить «Обрезать по границе» → тянуть через
край холста/выбранной области → оценить crop → Undo/Redo → save/reopen/F6.
Повторить штамп/паттерн у края, strict отказ при выключенной опции; подтвердить
сохранность контекста снаружи и locked групп. Crop — намеренная потеря части
объёма, восстанавливаемая Undo; автоматического расширения нет.

## Grab: кисть «Тянуть · мягко» (ручная приёмка открыта)

`test_voxel_grab.gd` PASS: инкрементальный pure job, центр следует захвату,
мягкость влияет на соседей, stationary outside, все6 channels/groups/part IDs,
validation/один Undo/Redo/stale/save/reopen. Доски толщиной1 и2vox остаются
face-connected при многокомпонентной тяге. Bounds/region/slice/locked/water/
authored-light отказы; canonical source не меняется до release.
UI проверяет реальный pick/ray/plane, LMB down/motion/up, transient preview
в существующем chunk renderer, exact preview=commit, Escape/смену инструмента,
Save и Ctrl+S во время жеста (блокируются без discard).
Kernel ~30ms для64×32×32 fixture/radius12, ~480ms для128×32×128/radius32;
тяжёлые jobs кадрами, coalescing latest endpoint, affected chunks only.
Related PASS: bend, fragment, surface_sculpt, workshop_layout,
selection_interaction, object_canvas, object_split, selection_mask,
workshop_generator_save и stamp. Stamp UI assertions переведены с позиции
кнопки на tool ID, т.к. Grab теперь вторая видимая кисть после лепки.
Native Forward+1280×720 PASS на disposable generation-smoke, Canvas capture
просмотрен: кисть видима, radius/softness читаются, preview помечен «Черновик».
Логи: Temp/ember-grab-test_voxel_*.log и generation-smoke/native-grab-final.log.
Полный regression suite здесь повторно не запускался.

Ручной gate: на уникальной копии доски выбрать «Тянуть · мягко»; radius12–24,
softness75%; вытянуть угол, затем центр. Оценить мягкость, непрерывность и
рисунок; отпускание/выход мыши за Canvas/Esc; Undo/Redo; save/reopen и F6
collision. Большой radius32 может давать задержку preview; жест ждёт финальный
endpoint; strict не обрезает данные, общий clip описан выше. Общая ручная
цепочка с доской ещё открыта.

## Изгиб объёма и ручная цепочка с доской (приёмка открыта)

`test_voxel_bend.gd` PASS: pure preview, все6 byte channels, группы/part IDs,
сохранение occupied count и толщины поперечного слоя, signed дуга/конец/оси,
одна Undo/Redo, save/reopen, discard/stale, visible workshop command и
selection/whole-object scope. Bounds/slice/region/overlap/locked/empty/limit/
water/authored-light отказы без записи.32768/131072 cells plan ~108ms
на текущем host; UI строит полный mesh только по явному обновлению preview.
Related PASS: fragment, selection_interaction, object_canvas, object_split,
placement, selection_mask, workshop_layout, split_preview, placement_preview.
Native Forward+ bend и workshop layout PASS в disposable generation-smoke;
preview и компактный rail просмотрены. Логи: Temp/ember-bend-test_*.log и
Temp/ember-generation-smoke-20260912/native-*-bend.log / native-*-preview.log.
Старый fragment fixture сообщает ObjectDB leak при выходе; bend fixture — без него.

Ручная проверка (авторские доски тестами не меняются):

1. Создать уникальную копию доски и открыть её Canvas.
2. Без выделения нажать слева «Изгиб…»; длина выбирается по длинной оси.
3. Выбрать направлениеY, дугу и2–4vox → обновить preview → Apply.
4. Если не хватает запаса, увеличить холст; отказ не обрезает объект.
5. Проверить рисунок/толщину, Undo/Redo, save/reopen и F6 collision.
6. Проверить изгиб выделенного фрагмента и отмену без Apply.

Остальная итоговая цепочка доска→копии→unique→merge→sculpt→split→extract→
stamp/pattern→water→save/reopen→F6 остаётся пользовательским gate, не считается
завершённой по результатам этих targeted tests.

`test_voxel_assembly_preview.gd` требует настоящего renderer для безусловного
screenshot, native Forward+ PASS. Старые migration_queue/prefab_rebuild tests
пишут production res://, запускать только в disposable copy. Migration_queue
PASS при правильном legacy pack path, prefab_rebuild PASS после первоначальной
пересборки в копии. Рабочие prefab после неуспешного cleanup старого теста
восстановлены точно из подготовленного index; изменения тестов не включены.
Новая генерация/история/породы/кора/выделение/маски/штампы/паттерны/рельеф/
пересборка и связанные gameplay/persistence suites PASS. Пользовательская
визуальная приёмка ели подтверждена отдельно.

## Общие pixel-art/clouds режимы всех5 пород (текущая итерация принята)

Пользователь2026-09-13 завершил текущую итерацию деревьев и запросил Git
checkpoint/push. Итог принят для текущего редакторского среза; trial-режимы
не объявляются окончательными. Старые3 gates впоследствии закрыты отдельно выше.
Перед commit повторно прошли13 targeted suites: tree_variation, birch_shape,
maple_shape, savanna_shape, spruce_shape, oak_crown, tree_types, bark_pattern,
large_tree_object, generator, generator_editing, foliage_species,
workshop_generator_save. Логи сохранены как Temp/ember-tree-checkpoint-*.log;
diff --check PASS. Предыдущие foliage_pattern/generation_session и native
Forward+ gates PASS; полный набор128 scripts здесь повторно не запускался.

2026-09-13, согласованный последний срез деревьев: style1/3 доступны всем
volume-based tree types в creation/candidate/contextual UI через тот же
FoliagePattern. Сохраняются center/radii/along, wood/physical и style0;
готовые assets не пересобираются автоматически. Shoot2 только oak8/11/16/17,
option disabled у остальных; explicit type change после shoot2→style0/Undo.
`test_voxel_foliage_species.gd` writes only user://: обе пробы/all5 типов,
64/256/seeds17/371, frozen scaffold/wood/collision/fresh freeze parity,
storage budget/bare foliage/contrast palette-only/serialization exact geometry,
creation/contextual controls, Undo/Redo/Discard PASS. Related tree_types,
foliage_pattern, generation_session, generator_editing, workshop_generator_save
PASS; diff --check PASS. Native Forward+ disposable gallery10 specimens PASS
без script/engine errors; foliage_species_native.png просмотрен.
Ручной gate: все5 пресетов, одинаковый seed, style1↔3, проверить породный
силуэт (зонтик саванны, вытянутая берёза, ярусы и вершина ели), detail/strength
и параметры облаков. Сохранить выбранные варианты и повторно открыть Recipe.
Новые регуляторы/режимы/полировка листовых побегов вне текущего среза.

## Сохранение рецепта из воксельной мастерской (manual gate открыт)

2026-09-13: общая «Сохранить» / save_changes() / Ctrl+S при активной вкладке
«Генератор» используют save_variant()/Creation, не sculpt Resource.
Сохраняется точный preview вместе с полными Recipe.parameters по выбранному
режиму; без preview — отказ без fallback, manual dirty update защищён.
`test_voxel_workshop_generator_save.gd` (writes only user://): все3 режима,
стиль1/3, выраженность25/42, детализация70, полная equality parameters,
preview voxels/palette, reopen controls, Undo/Redo, Discard, stale preview,
manual dirty отказ и сохранность исходника при новой вариации/объекте PASS.
Native Forward+ на disposable copy PASS без script/engine errors;
`workshop_generator_save_native.png` просмотрен. Это нативный workspace
test, не проверка hot-reload активного пользовательского editor.
Related generator_editing/foliage_pattern/object_canvas targeted PASS;
diff --check PASS. Форма/математика пород и листвы не менялись.
Ручной gate: во вкладке «Генератор» поменять стиль/выраженность, собрать
preview, сохранить общей кнопкой или Ctrl+S и открыть сохранённую вариацию.
После изменения параметра без нового preview Save должна явно отказать.

## Боковое вторичное ветвление дуба17 (приёмка открыта)

Побеги из середины основных сучьев идут преимущественно наружу и раздваиваются;
leaf masses формируют плечи и нижнюю крону, lower trunk открыт. Shared plan/
physical/frozen/Recipe/UI/history; нет нового ползунка. Branchiness0/62/100→
1/2/3 secondary shoots/limb, diversity меняет placement/length/rise.
Primary composition16 exact (старые RNG draws сохранены), pixel math прежняя.
New presets/type reselect17; old16/frozen unchanged; diversity0 exact8.
Variation targeted:6reported seeds96/8/80/diversity100, count/sideward growth/
physical parent anchors/primary16 parity/frozen16 non-upgrade; также all5species,
limits/extremes/directions/fresh-frozen/text/presets/history. PASS.
Native --tree-variation-only --composition-dressed: latest17,3pixel seeds иbare,
individual Apply/Discard/regeneration/Undo/Redo/publication/reopen.
Ручной gate: повторно выбрать «Дуб», pixel-art, новая партия с diversity65/100;
сравнить спереди/сбоку нижние плечи и bare secondary forks; branchiness30/80.
Старый кандидат обновляется только явной regeneration/Undo. Save/reopen preset
иobject; art gate оценивается пользователем отдельно от counts/coverage.
Variation и8related oak/types/bark/editing/large-tree/generator/foliage/session
PASS; native Forward+ PASS без script/engine errors, captures просмотрены;
diff --check чистый. Старые общие migration gates не менялись.

## Композиция дуба16 (приёмка открыта)

Пользователь оставляет pixel-art основой. Новая composition16 исправляет
ascending ladder и capped trunk/пустой центр; два physical tapering leaders
с реальными побегами поддерживают внутреннюю крону. Старые8/11/frozen exact,
type preset/reselect выбирают16; diversity0 exact8. Pixel-art math прежняя.
Variation targeted:6reported seeds/96/width8/spread80/diversity100/pixel55/
contrast25/along85, different fork-height profiles/trunk tops, два реальных
продолжения trunk tip, центральная foliage coverage и identical bare structure.
Также all5species64/128/256, budgets, frozen/text/preset/history/directions.
Native disposable --tree-variation-only --composition-dressed: три dressed
seeds17/371/391 и bare17, editing/Discard/history, regeneration/Undo/Redo,
publication/reopen; captures generation_oak_variation_native/front/side/preview.
Ручной gate: повторно выбрать «Дуб», pixel-art, diversity65/100, новая партия;
сравнить несколько силуэтов и bare roots/центральные развилки без capped tip.
На старом кандидате новая форма только через «Новый каркас из настроек партии»;
проверить Undo, затем сохранить preset/object/reopen. Не считать art принятым
по одному coverage/count test. Другие породы/leaf modes вне этого среза.
Variation и8related oak/types/bark/editing/large-tree/generator/foliage/session
PASS; native clean Forward+ PASS без script/engine errors, captures просмотрены.

## Пробные лиственные облака дуба8/11 (приёмка открыта)

Style3 сохраняет pixel1 и shoots2. Body — связанные неодинаковые уплощённые
подушки, leaf accents — редкие пары folded leaves по краям. Общий provider,
frozen supports, Recipe.parameters/presets; дерево/collision не меняются.
`test_voxel_foliage_pattern.gd -- --clouds-only`:8/11 ×64/96/128/256 ×17/391,
exact wood/physical/supports, fresh-frozen/text, amount0, bounded extremes3/12,
nested accents/body, UI/Undo/Redo/Discard/reusable presets. PASS.
Disposable native `-- --foliage-clouds-only`: один дуб96/seed391, pixel1/shoots2/
clouds3 accents35/80. Individual Apply/Discard/Undo/Redo, publication/reopen,
contextual style switching/Undo/Discard PASS; captures native/front/side/
preview/detail просмотрены, script errors нет.
Ручной gate: на выбранном дубе поменять «Стиль листвы» на «Лиственные облака ·
пробные», размер деталей5, выраженность35, amount100. Сравнить на одном frozen
каркасе сpixel/shoots; затем accents0/80 иsize3/8. Оценивать силуэт издали,
неравномерные листовые акценты вблизи, просветы и вид снизу. Save/reopen object
иpreset, Apply Undo/Redo. Другие породы/шэйдеры/лесной performance gate отдельно.
Read-only mesh audit на96/seed391: clouds108_732 triangles, pixel96_788,
shoots174_280, old91_340. Это один объект, не forest benchmark.

Вторая проба cloud_version2 по пользовательской обратной связи: объёмные
шапки над ветвями вместо кольца тонких подушек; shared surface pattern после
union. Каркас не меняется. Старый cloud1/missing version exact, upgrade явным
reselect style3/Undo. Targeted дополнен pattern detail15/85 (same occupancy и
structure, different indices), contrast0/20/100 (palette only), old cloud1 golden
94_068 и contextual upgrade/Undo. Native fixture: cloud1 иcaps2 на одном
oak8/96/391, contrast20/65/100, detail55/85; Apply/Discard/Undo/Redo/publication/
reopen/contextual switching PASS; captures просмотрены, script errors нет.
Ручной gate второй пробы: повторно выбрать «Лиственные облака · пробные»,
detail55/contrast65/size5/accents35, Apply. Сравнить silhouette с первой пробой,
менять detail15/85 иcontrast20/100 независимо; сохранить/reopen recipe/preset,
Undo upgrade. Оценить дубовые шапки сверху/сбоку/снизу и форму на других seeds.
Read-only caps2 mesh96/391:93_580 triangles /187_160 vertices, не forest gate.
Clouds-only/full foliage и8related oak/types/bark/editing/large-tree/generator/
variation/session PASS; старые migration gates не изменены.

## Разнообразие каркасов дуба11/клёна12 (принято пользователем)

Новые presets и явный reselect типа используют11/12. Сохранённые8/7 и каркасы
не меняются автоматически. Creation-only «Разнообразие каркаса»0–100 (default65)
меняет структурный план, не foliage.0 — exact old geometry; frozen settings
листвы/толщины не регенерируют сучья. Pixel-art дуба сохранён и работает с11.
Для текущего старого batch/preset повторно выбрать «Дуб»/«Клён» перед генерацией.

`test_voxel_tree_variation.gd`:6 seeds ×64/128/256 для каждой породы, distinct
yaw-invariant structural fingerprints и минимум3 разных counts, source/structure
validation, exact fresh/frozen/text, frozen immunity, diversity0 legacy parity,
max settings3seeds/direction overrides, reusable preset и draft Undo/Redo.
Native disposable `-- --tree-variation-only` (+`--maple-shape-only`): bare seeds
17/371/391 и leaf dressing17, одинаковое направление первого trunk segment,
Apply/Discard/Undo/Redo/publication/reopen, explicit new skeleton button/Undo/Redo.

Ручной gate: новая партия4, height96, amount0, diversity65 и100; оценить не
только поворот, но длины, высоты сучьев, развилки и асимметрию. Дуб должен быть
раскидистым, клён — высокой округлой кроной. После выбора вернуть foliage100,
у дуба pixel-art; менять один frozen вариант, сохранить preset/object и reopen.
Дуб/клён приняты пользователем. Для других пород следующий gate ниже; не считать
доказательством разнообразия лишь разницу voxel hash или одну хорошую картинку.
Variation targeted и7related oak/maple/types/bark/foliage/editing/session PASS;
native oak/maple Forward+ PASS, логи без script errors. Captures
`generation_oak_variation_native/front/side/preview.png` и maple аналог просмотрены.
Explicit regeneration/Undo/Redo проверен кнопкой в обеих native fixtures.
Общий perf леса/карты этим не закрывается.

## Разнообразие берёзы13/саванны14/ели15 (приёмка открыта)

Тот же TreeVariation и creation-only «Разнообразие каркаса», не новый provider.
Старые5/9/10 и frozen objects не обновляются;0% даёт exact previous geometry.
Перевыбрать тип или взять новый type preset перед генерацией новой партии.
`test_voxel_tree_variation.gd` теперь проверяет все5 пород:6 seeds ×64/128/256,
distinct yaw-invariant fingerprints и минимум3 counts, source/structure budgets,
fresh/frozen/text, zero parity, frozen immunity, extremes/directions, presets/UI.
Historical birch/savanna/spruce suites продолжают5/9/10, UI gates знают13/14/15.
Native disposable: `-- --tree-variation-only` + соответствующий
`--birch-shape-only` / `--savanna-shape-only` / `--spruce-shape-only`.
Проверить сравнение bare seeds17/371/391/dressed17, individual Apply/Discard/
Undo/Redo/publication/reopen, explicit skeleton regeneration/Undo/Redo.

Ручная проверка: партия4, высота96/128, листва0, разнообразие65 затем100.
Берёза остаётся стройной с тонкими поникающими побегами, саванна — широким
плоским зонтом на разных развилках, ель — с центральной осью и сужением к вершине.
Вернуть листву100, менять только выбранный frozen вариант, сохранить/reopen
object и preset. Листовые побеги/хвоя/shaders/оптимизация леса этим не закрываются.

Variation и10related suites PASS. Native birch/savanna/spruce Forward+ PASS, включая сравнение трёх bare seeds
и dressed17, Apply/Discard/Undo/Redo/publication/reopen/explicit regeneration.
Captures birch/savanna/spruce `generation_*_variation_native/front/
side/preview.png` просмотрены. Copied UID warnings не относятся к этому срезу;
script/parse errors отсутствуют. Шесть проверенных seeds: birch85–105 segments
(раньше107), savanna41–77 (56), spruce85–105 (120). Это наблюдение, не min/max.

## Пробные листовые побеги дуба v8 (приёмка открыта)

Pixel surface оставлен пользователем как эксперимент, не заменяет default0.
Новый отдельный style2 «Листовые побеги · пробные» доступен у актуального дуба:
creation settings, справа у конкретного кандидата, Canvas «Генератор» у saved.
Размер листика3–12vox (default5), количество/along/цвет/пучки общие. Другие породы,
ветер/shaders вне среза. Зелёные черешки не имеют физической collision.

Ручной gate: дуб96/seed391 old0 vs shoots2, size5 vs8, издалека и вблизи,
просветы/читаемость листиков/дубовый силуэт. Изменить только один вариант,
Apply/Undo/Redo/Discard, bare amount0, осень цветом; сохранить preset и объект,
reopen. Author-owned карты/исходники не меняются ради проверок.
Targeted `test_voxel_foliage_pattern.gd` дополнен style2:64/96/128/256, exact
scaffold/wood/collision, fresh/frozen/text, size3/8/12, amount0, season и UI Undo.
Native `-- --leaf-shoots-only`: №1 old0, №2 shoots5, №3 shoots8 (seed391),
№4 shoots5 seed17; size Apply/Discard/Undo/Redo, publication/reopen/contextual
dynamic fields/Undo/Discard. Не считать одиночные деревья готовым perf gate леса.
Targeted foliage и4related oak/bark/editing/session PASS; native Forward+ PASS,
лог без script errors. Geometry64–256~0.28–0.87s, meshing отдельно. Native дуб96:
old91_340 triangles, shoots174_280 (~1.9×), occupied125_212→75_250. Визуальную
приёмку открытых листиков/просветов всё ещё должен выполнить пользователь.

## Пробная пиксель-арт листва дуба v8 (оставлена как эксперимент)

Следующий пробный срез — surface pattern revision2: первая форма разнообразнее,
но рисунок пользователь счёл нечитаемым. Повторно выбрать «Пиксель-арт» для
обновления только паттерна старого дерева/рецепта. Missing revision оставляет1.
Detail теперь меняет масштаб3–9vox без изменения occupied/collision; новая
«Выраженность» меняет только palette. Проверить Detail30/55/85 и strength20/65/
100 на одном каркасе. Targeted дополнен reversed-order equality, old revision
parity, zero-strength uniform palette, occupancy invariance и reselect Undo.
Native disposable fixture `-- --foliage-surface-only`: №1 strength20, №2 strength65,
№3 strength100 (одна геометрия/seed391/Detail55), №4 Detail85/strength65;
individual Apply/Discard/Undo/Redo/publication/reopen/contextual fields.
Галерея и прямые viewport captures `_weak_preview.png`, `_preview.png`,
`_strong_preview.png`. Приёмка читаемости/не-мозаичности паттерна открыта.
Surface targeted и4related (oak/bark/editing/session) PASS; native Forward+
palette-only Apply/Undo/Redo/Discard/publication/reopen/contextual fields PASS,
финальный лог без script errors. Прямые captures просмотрены. Hidden geometry
detail сохраняет custom crown85 при upgrade1→2; exact occupancy/collision
проверены отдельно targeted. Fresh64–256 около0.23–0.72s, meshing отдельно.

Новый стиль включается явно: выбрать актуальный «Дуб» → «Листва · дуб» →
«Пиксель-арт · пробная». У выбранного кандидата то же переключение доступно
справа; у сохранённого объекта — Canvas «Генератор». «Детализация» появляется
только для нового стиля. Остальные породы и старые алгоритмы не изменяются.

`tools/test_voxel_foliage_pattern.gd`:64/96/128/256×seeds17/391, old/missing
parity, source/structure validation, exact scaffold/wood/bark/collision,
fresh/frozen/text roundtrip, amount0/35/100, detail0/55/100, season palette-only,
отсутствие одиночных leaf voxels, max budget, reusable preset и draft Undo/Redo.
Contextual panel старого сохранённого дуба: смена style0/1 добавляет/убирает
detail control; Undo/Redo/Discard восстанавливают поля без изменения source.
Native disposable fixture `-- --oak-foliage-only`: old/new/detail90 на одном
каркасе seed391 плюс seed17, индивидуальные Apply/Discard/Undo/Redo,
publication Undo/Redo/reopen. Общая галерея и front/side/old-front captures.
Никакие авторские assets/карты не пересобираются ради теста.
Foliage targeted и7related suites PASS; native Forward+ PASS. Время fresh
geometry64–256 около0.21–0.67s (meshing отдельно), old/new captures просмотрены.
Копия оставляет прежние UID warnings, не исправляемые этим срезом; script errors
не было. Визуальная приёмка пользователя пока открыта.

Ручная проверка с пользователем:

1. Сгенерировать дуб с прежней и новой листвой на одинаковом seed. Оценить
   сохранение дубового силуэта, читаемость небольших групп, естественность краёв
   и просветов. Это воксельный dressing, не новый шейдер/освещение/2D sprite.
2. Настроить только один вариант: Detail20/55/90, количество35/100, размер и
   сомкнутость. Apply/Undo/Redo/Discard должны затрагивать только его крону;
   ствол/кора/ветви/коллизия не перемещаются.
3. Количество0 показывает прежний скелет; смена цвета на осень не меняет форму.
   Сохранить свой preset, снова выбрать его для новой партии и другого seed;
   сохранить выбранный объект и открыть Canvas «Генератор» после reopen.
4. Подтвердить направление первого дуба прежде адаптации к остальным породам.

## Ель v10: ярусный хвойный профиль (силуэт принят)

«Тип · Ель» или явный выбор type4 используют10. Новая мастерская начинает
с актуальной саванны9; все5 типов доступны рядом. Loaded Recipes сохраняют
алгоритм и отмечены «прежняя форма»; явный reselect обновляет его с Undo.
Старые алгоритмы остаются в дополнительных настройках совместимости.

`tools/test_voxel_spruce_shape.gd`:64/96/128/256×seeds17/371/391, непрерывный
leader,9ярусов/сужение ветвей, >90%leaf row coverage в основной кроне,
max budget/directions, validation/exact fresh-frozen/text roundtrip/collision,
bare/season/thickness support stability, type choice/loaded compatibility,
discard/Apply/publication Undo/Redo/reopen10. Native disposable fixture:
`-- --spruce-shape-only`, seeds371/391/17 и391bare, реальные front/right views.
Финальный targeted PASS,11related suites PASS. Native isolated Forward+
gallery/bare/Apply/Undo/Redo/publication/reopen10 PASS; итоговые front/right/
gallery captures просмотрены, лог без script errors. Первый редкий вариант
исправлен до handoff; тест row coverage ловит голый leader между ярусами.

Ручная приёмка: открыть «Тип · Ель»,96vox,seeds391/17/371, сравнить спереди
и сбоку с референсами — острый leader, широкие нижние/короткие верхние ветви,
неравные вытянутые массы хвои, не шарики и не сплошной конус.
Количество пучков0 → тот же каркас; изменить толщину/цвет/количество,
Apply/Undo/Redo,save/reopen. Старые объекты не должны самопроизвольно меняться.
После принятия формы ели обсудить общую систему листьев/хвои отдельно.
Пользователь выполнил проверку и принял ель («Мне нравится, проверил»).

## Саванна v9: зонтичный профиль (силуэт принят)

Новый «Тип · Саванна» и явный выбор типа →9. Default/saved v2/v3 не
обновляются на load; shared frozen structure1/paint/bark/emitter/Source/Recipe/
workshop/publisher прежние. Изогнутый ствол,3–4 основные стволики и тонкие
боковые развилки под широкой неглубокой слегка выпуклой кроной, без pole.
Foliage_along использует прежний descriptor/projection и доступен для v9.
Профиль кроны учитывает реальный ограниченный размах и на256vox.

`tools/test_voxel_savanna_shape.gd` PASS:12samples64–256, saved v2 golden
parity, no pole, реальная высокая shallow/wide крона, bounded scaffold/max
storage/directions, source validation, fresh/frozen geometry+collision exact,
Recipe text roundtrip, bare/season/thickness support stability, shared
foliage control, UI choice Undo/Redo, discard/Apply/publication Undo/Redo/reopen9.
Oak/maple/birch/types/bark и common generator editing/session regressions PASS.
Native disposable `-- --savanna-shape-only`: №1v2/№2v9/№3v9bare/№4v9seed17,
индивидуальные Apply/Undo/Redo/publication/reopen PASS. Gallery и реальные
передний/правый ортогональные `generation_savanna_front.png`/
`generation_savanna_side.png` просмотрены. Финальный native лог без script
errors; неполный ненормализованный Recipe старого образца был ошибкой fixture,
исправлен нормализацией через общий owner, не изменением старого алгоритма.

Для ручной проверки заново выбрать preset «Тип · Саванна»,height96,
seeds391/17/371. Сравнить спереди/сбоку с фото: тонкий изогнутый ствол,
раскрытые сучья, широкая неглубокая неровная крона, без центральной башенки.
Количество пучков0 показывает тот же каркас. Apply/Undo/Redo,save/reopen
и старые деревья проверить в рабочем редакторе. Художественная приёмка
пользователем отдельно от assertions. Силуэт принят («Проверил, красиво»).
Новая очередь: ель, затем обсуждение листьев/хвои.

## Дуб v8: взрослый раскидистый профиль (силуэт принят)

Пользователь принял форму v8 («форма мне нравится»).

Новый «Тип · Дуб» и явный выбор типа используют v8. Сохранённые v3/v4
остаются прежними; oak suite сохраняет их golden hashes64/128/256.
Массивный искривлённый ствол/непрерывный collar, короткие слитые buttresses,
разные высоты основных сучьев, длинные боковые нижние ветви и вторичные
развилки, несколько восходящих верхних сучьев. Крона глубже по высоте,
внутренние опоры связывают внешние массы, нижние развилки видны.
Shared Source/Recipe/structure1/registry/bark/projection/workshop/publisher;
без новых knobs, leaf microdetail и branch editor не входят.

`tools/test_voxel_oak_crown.gd` PASS: 3seeds×64/96/128/256, max budget,
разные origins/нижний размах/deep foliage/collar, structure/source validation,
fresh/frozen geometry+collision exact/text roundtrip, bare/season/thickness,
UI choice Undo/Redo, discard, Apply/publication Undo/Redo/reopen v8.
Maple/birch/types/bark, generator editing/session regressions PASS.
Native disposable `-- --oak-crown-only` сравнивает №1v4/№2v8/№3v8bare/№4seed17,
индивидуальный Apply/Undo/Redo и publication/reopen PASS. Gallery и передний/
правый ортогональные `generation_oak_mature_front.png`/`generation_oak_mature_side.png`
просмотрены. Прежние copied fan_town UID warnings не исправлялись этим срезом.

Ручная проверка: заново выбрать «Тип · Дуб», height96, seeds391/17/371.
Сравнить с фото спереди/сбоку: массивное плавное основание, широкие кривые
сучья, глубокая неровная крона без одной плоской шапки. Количество пучков0
показывает тот же скелет. Проверить Apply/Undo/Redo/save/reopen и сохранённые
старые деревья. Узнаваемость подтверждает пользователь, не shape asserts.

## Клён v7: высокая крона по фото референсу (силуэт принят)

Пользователь принял силуэт v7 («да, похоже на клён»); возвращаемся к дубу.

V6 ниже — технически проверенный, но не принятый пользователем этап.
Повторный согласованный проход v7 меняет высотное распределение опор и масс:
пять уровней, широкая середина/более узкий округлый верх, внутреннее заполнение
и перекрытие соседних масс. Новый «Тип · Клён»/выбор типа → v7, saved v3/v6
не обновляются. Golden v6 сняты до правки, проверка добавлена в maple suite.
Финальный maple suite PASS: v6 exact golden parity, пять высот/широкая середина/
узкий верх, реальная высота листвы и отсутствие пустых горизонтальных рядов,
12samples и maximal envelope, fresh/frozen/text exact roundtrip, Apply/discard/
publication Undo/Redo/reopen. Oak/birch/types/bark, generator editing/session PASS.
Native `-- --maple-shape-only` Apply/Undo/Redo/publication/reopen PASS;
`generation_maple_upright_native.png`, передний/правый ортогональные
`generation_maple_front.png`/`generation_maple_side.png` просмотрены.

Для ручной проверки v7 заново выбрать preset, height96, seed391/17/371.
Оценить дерево на уровне кроны спереди и сбоку, а не только сверху: сравнить
пропорции с фото пользователя, наличие общей высокой кроны вместо чаши,
широкой середины и более узкой верхушки. Голый каркас показывает ветви на
нескольких высотах. Проверить Apply/Undo/Redo/discard, save/reopen и отдельную
вариацию; старые деревья остаются прежними. Мелкие детали листьев не входят.
После оценки клёна вернуться к дубу; Ель пока не реализовывать.

2026-09-12: `tools/test_voxel_maple_shape.gd` PASS: 3 seed × 64/96/128/256,
ascending/lateral supports, Source/structure validation, extreme envelope,
exact fresh/frozen/text Recipe roundtrip/collision, bare/season/thickness без
перемещения опор, explicit direction/tiered, type choice Undo/Redo,
draft discard/Apply/publication Undo/Redo/reopen. Oak/types/birch/bark и
generator editing/session regressions PASS.
Native disposable `-- --maple-shape-only` individual Apply/Undo/Redo/publication/
reopen PASS; `user://generation_maple_shape_native.png` просмотрен:
№1 старый v3, №2 v6 seed391, №3 тот же v6 без листвы, №4 v6 seed17.

1. Заново выбрать «Тип · Клён», height96, seed391/17/371. Оценить округлую
   связанную крону, раскрывающиеся в стороны восходящие развилки, отсутствие
   отдельной высокой цепочки шариков/низких «тарелок». Оценивать форму, не цвет.
2. «Настроить» одного дерева → количество листвы0 → Apply: проверить голый
   каркас, Undo/Redo. Изменить толщину/сужение ветвей, цвет/заполнение листвы:
   опоры не двигаются, другие варианты неизменны. Discard не меняет source.
3. Сохранить, reopen в Canvas «Генератор», создать вариацию/новую генерацию
   из настроек. Старый saved v3 не обновляется без явного нового каркаса.
4. Проверить высоты64/128/256; 256 соблюдает прежний envelope и может быть
   относительно уже. Детализация листьев пока не входит в оценку этого среза.

Тип «Ель» добавлен в продуктовый план, ещё не реализован.

## Общий рисунок коры (распределение v2 принято пользователем)

2026-09-12: `tools/test_voxel_bark_pattern.gd` PASS: marks rotation covariance
по оси support, surface-only, direction/length/seed determinism, zero/off,
все large_tree породы без изменения occupancy/collision/skeleton, custom colour
в palette[7], exact off colours, native bool/enum descriptors в common creation
и contextual Canvas, Undo/Redo/discard. Birch/oak/types и 6 related suites PASS.
Recipe text roundtrip exact: устранён negative-zero atan2 seam; старые missing
pattern keys остаются off. Native disposable `-- --bark-pattern-only` PASS:
cross birch/longitudinal oak/custom slanted birch/plain oak, toggle/direction/
colour/length Apply Undo, library publication Undo/Redo и reopen.
Capture `user://generation_bark_pattern_native.png` просмотрен.

Полировка v2: новые presets/defaults используют независимые смещённые штрихи
с промежутками, cross/slanted length ограничена радиусом ветви. Saved Recipe
без `bark_pattern_version` остаётся v1; off/on toggle явно выбирает v2,
Undo возвращает старую версию. Bark v1 parity/v2 rotation/thin-support rings,
creation/contextual upgrade Undo, oak/birch/types, editing/session/generator PASS.
Recipe text save/reopen exact colours PASS для обеих версий рисунка.
Native `-- --bark-pattern-only --scattered-bark` Apply/Undo/Redo/publication/
reopen PASS; сравнение №1 v1 birch391 / №2 v2 birch391 / №3 v2 birch17 /
№4 v2 oak371, capture `user://generation_bark_scattered_native.png`.
Gallery и отдельные крупные планы `user://generation_bark_detail_1/2/3.png`
просмотрены.
Пользователь затем принял распределение v2 («да это лучше»); bark gate закрыт.

Дополнительная ручная проверка v2: старое дерево открыть без изменения рисунка;
off/on «Рисунок коры» → Apply/preview должен обновить только окраску.
На берёзе height96, seed391/17/371, без листвы осмотреть ствол крупно с четырёх
сторон: отметины не должны складываться в одинаковые пояса. Density100,
length24 на тонких ветвях — остаются светлые промежутки. Undo возвращает
прежнюю окраску/версию, save/reopen сохраняет выбранное распределение.

1. Заново выбрать «Тип · Берёза»/«Тип · Дуб», height 96. Оценить cross/longitudinal
   рисунок крупным планом на стволе и ветвях. Для удобства временно убрать листву.
2. «Настроить» → прокрутить до «Рисунок коры»: toggle off/on, direction, colour,
   length 2/12/24 и density 0/30/100. До Apply source не меняется; Apply один раз,
   Undo/Redo возвращают exact tree. Геометрия и расположение ветвей неизменны.
3. Изменить радиусы ветвей и проверить соответствие рисунка новой толщине.
   Другие варианты неизменны. Discard возвращает настройки черновика.
4. Сохранить лучший, reopen в Canvas «Генератор», поменять рисунок и сохранить
   вариацию. Reopen/preset/new generation сохраняют параметры; saved old Recipe
   не получает рисунок автоматически. В настройках новой партии блок находится
   в дополнительных параметрах. Это окраска, не объёмные бороздки/шейдер.

## Берёза: тонкий ствол и поникающие веточки (силуэт принят пользователем)

2026-09-12: `tools/test_voxel_birch_shape.gd` PASS: 3 seed × 64/96/128/256,
continuous leader, descending outer twigs, bounded/maximal source/structure,
exact fresh/frozen/text Recipe roundtrip и collision, bare/season/thickness
support stability, draft discard, Apply и common publication Undo/Redo/reopen.
Oak compatibility и 6 related suites PASS. Новый preset/выбор типа → v5,
загрузка saved v3 birch не обновляет алгоритм. Leaf 128 vox примерно 60 ms,
meshing отдельно. Native disposable fixture `-- --birch-shape-only`:
№1 saved-style v3, №2 новый v5, №3 тот же seed без листвы, №4 seed 17;
capture `user://generation_birch_shape_native.png`, normal Forward+ viewport.
Финальный native comparison/individual Apply/Undo/Redo/publication/reopen PASS,
capture просмотрен. Shared type UI/Undo/Redo regression PASS.

1. «Тип · Берёза», height 96, seed 391/17/371. Оценить вытянутый воздушный
   силуэт, тонкий изгибающийся ствол, боковые восходящие ветви и поникающие
   окончания. Не оценивать узнаваемость только по белому цвету коры.
2. «Настроить» одного дерева → количество пучков 0 → Apply; осмотреть bare
   branches, Undo/Redo. Остальные варианты неизменны. Толщина/сужение меняют
   радиусы без перемещения опор, цвет/заполнение/размер листвы — не ветви.
3. Discard черновика; сохранить лучший, reopen в Canvas «Генератор», сохранить
   вариацию. Старый v3 восстанавливается как раньше; новый сохраняет v5/seed/
   каркас. Новый именованный preset используется для новой партии без skeleton.
4. 64 и 256 vox, нижние грани, вращение/3D comparison/остановка между моделями.
   Отдельный проход по детальной форме листвы — после силуэтов остальных presets.

## Полировка дуба: развилки и связная крона (силуэт принят пользователем)

2026-09-12: `tools/test_voxel_oak_crown.gd` PASS: новый oak v4 при 3 seed и
высотах 64/96/128/256, отсутствие высокой центральной оси, несколько ранних
развилок, bounded/maximal geometry и validation, exact fresh/frozen/text Recipe
roundtrip, bare/season без смены каркаса, invalid radii rejection,
individual Apply Undo/Redo и library publication Undo/Redo/reopen в `user://`.
Golden samples сохраняют старый v3 oak byte-identical и геометрию v4 после
ускорения union; types и 6 related suites PASS. На 128 vox leaf build примерно
0.86–0.95 s без meshing. В рабочем checkout не запускать headless editor.
Native opt-in в disposable `ember-generation-smoke-*`, аргумент
`-- --oak-crown-only`: №1 старый v3, №2 новый v4, №3 тот же seed/каркас без
листвы, №4 другой seed; native selection/F/wheel, Apply Undo/Redo, publication
Undo/Redo и Recipe reopen. Capture `user://generation_oak_crown_native.png`.
Финальный native прогон PASS, capture просмотрен; пользователь принял силуэт
дуба («дубы стали похожи на дубы»). Детальная форма листвы — отдельный этап.

1. В мастерской выбрать «Тип · Дуб», height 96, seed 391; затем 17 и 371.
   Оценить широкий округлый силуэт, сильные развилки и боковой объём, а не
   столбик отдельных одинаковых шапок. Сравнить несколько партий через «3D».
2. Выбрать одно дерево → «Настроить» → количество листвы 0, Apply. Проверить
   ход сучьев без листвы; Undo возвращает ту же полную крону. Толщина/сужение
   ветвей сохраняют положение развилок; другие варианты не меняются.
3. Поменять заполнение вдоль ветвей, размер/приплюснутость масс и осенний цвет.
   Apply/Undo/Redo/Discard; сохранить лучший и открыть в Canvas «Генератор».
   Reopen восстанавливает Recipe/seed/каркас; свой preset генерирует новые
   каркасы, а не копирует старый. Старый saved дуб v3 остаётся старым.
4. Проверить 64 и 256 vox, вращение и нижние грани, сравнение до 4/2 деревьев.
   Остановка между кандидатами; на крупном дереве synchronous build ещё может
   задерживать кадр. Узнаваемость дуба и форма кроны требуют оценки пользователя.

## Типы и боковой объём деревьев (ручная художественная приёмка открыта)

2026-09-12: `tools/test_voxel_tree_types.gd` проверяет 4 типа при одинаковом seed
и height 64/128/256, bounded source/structure, exact frozen rebuild, season и
interior foliage 0/30/100 без движения древесины, unchanged branch RNG при 0%,
направления up/lateral/down, максимальные размеры нового типа, Resource text
roundtrip с exact voxel parity, type Undo/Redo в общей панели. Golden pre-type
hashes v1/v2 проверяют сохранение старых формул на seed 371 во всех 3 размерах.
Related: generator/editing/session/large_tree_object/dialog/library_layout PASS.
Native opt-in fixture дополнен четырьмя type presets в разных партиях и общим
сравнением, interior foliage Apply/Undo/Redo, existing library publication и
typed Recipe reopen; capture `user://generation_types_native.png`.
Native сценарий PASS; в первом прогоне выявлено отсутствие нового editing field
из-за сборки candidate controls только при ready. Общая панель обновляет набор
descriptors при выборе другого типа; regression есть в targeted test, следующий
native прогон с реальным полем Apply/Undo/Redo и saved Recipe reopen PASS.

Ручные проверки после сохранения рабочих сцен и перезапуска Godot:

1. «Объекты → Генерация…», пресеты «Тип · Саванна/Дуб/Берёза/Клён»; height 96,
   по одному варианту, одинаковый seed. Все 4 партии остаются в истории; собрать
   галочками «3D» сравнение четырёх. В строках подписан тип, номера над моделями
   совпадают. Саванна прежняя; дуб объёмный, берёза стройная, клён ярусный.
2. Дуб: новые партии с направлением вверх/в стороны/слегка вниз. Проверить,
   что меняется реальный ход ветвей, а не только положение шапок листвы.
3. «Настроить» дуб → «Листва вдоль ветвей» 0/30/100, Apply/Undo/Redo. Меняется
   боковое/внутреннее заполнение, но существующие ветви и другие модели стоят
   на месте. Осенний цвет тоже не перестраивает каркас. Discard возвращает draft.
4. Сохранить лучший, открыть его в Canvas «Генератор», изменить листву/толщину,
   сохранить вариацию. Reopen сохраняет тип, параметры, seed и каркас; старые
   saved v1/v2 деревья восстанавливаются как раньше. Typed presets можно сохранить
   своим именем и использовать для следующей партии без старого skeleton.
5. Height 256 → сравнение до 2. Проверить вращение, нижние грани, scene save без
   temporary candidates, cancel между моделями. Тонкие детали/форма кроны требуют
   художественной оценки, не заменяются автоматической voxel parity.

## Общая мастерская генерации в native 3D (новая рабочая приёмка открыта)

2026-09-12: `test_voxel_generation_session.gd` проверяет provider descriptors,
parameter/seed и candidate choice Undo/Redo, индивидуальный draft/discard/apply
Undo/Redo, unchanged other candidate и exact skeleton, один explicit skeleton
reroll + Undo, осенняя palette только выбранного дерева и exact reopen,
стабильные номера/Label3D между family/pass, solo/gallery,
studio/map suspension с dirty draft и восстановление утратившей nodes галереи,
publication lock после file Undo (не расходятся preview и file Redo), разные seeds,
frozen skeleton, один family/card для двух выбранных вариантов, точный source
и восстановление тех же voxels после recipe reopen, asset-only Save/Undo/Redo,
отсутствие placement/physics/scene serialization у preview, историю всех партий,
освобождение geometry архивных записей, точное восстановление unsaved/saved,
cross-batch comparison, favorite не уменьшает новые партии, фильтры batch/best,
сохранение лучших из архива по очереди и file Undo/Redo архивного варианта,
cancel, limits 4/2, presets save/reopen/duplicate guard,
освобождение discarded Creation (без удержания mesh сигналами/choice history),
защиту использования сохранённого объекта. Все fixtures только `user://`.
Related: generator, generator_editing, large_tree_object/dialog,
object_library_layout; plugin.gd и native fixture `--check-only`.

`editor_test_voxel_generation.gd` opt-in только в disposable
`ember-generation-smoke-*`: реальная library create button, studio scene tab + bottom panel,
четыре exact previews в обычном Forward+ viewport, native selection/center F/
wheel scale, save-only history с filesystem settle между Undo/Redo, preset
reopen, studio save без preview, карта без временных objects, открыть saved source
в существующем Canvas, individual apply + native selection, dirty draft при
scene switch/return, 8 вариантов/2 партии, восстановление точной geometry старого,
сравнение старого/нового, batch filter и confirmation Cancel всей истории без
удаления. Capture
`user://generation_native.png`; adaptive native wheel fit учитывает сохранённый
camera zoom disposable scene, не вмешивается в рабочий editor пользователя.
Прежние UID warnings authored fan_town в копии не относятся к новой генерации.
Результат: новый session test + 5 related suites PASS; native Forward+ полный
сценарий и generate-similar command PASS, cross-batch comparison двух деревьев
в обычном editor capture просмотрено. Новых script errors нет. Предыдущую
мастерскую пользователь принял; ручная приёмка истории всех партий открыта.
Synchronous build не отменяется посреди
одного дерева, лимит памяти — консервативный, без нового GPU performance gate.
В промежуточном native прогоне обнаружены exclusive-window conflict и crash
после confirmation Cancel; lifecycle исправлен явным hide перед queue_free.
Финальный прогон использует реальную Cancel button, полный сценарий PASS без
exclusive-window/script errors, editor штатно закрыт; capture просмотрен.

Рабочая ручная последовательность (сохранить draft/сцену, перезапустить Godot):

1. «Объекты → Генерация…»: отдельная вкладка сцены «Генерация» в Godot 3D и
   нижняя мастерская, не новое окно. Рабочая карта остаётся в своей вкладке.
2. Height 96, 4 варианта → сгенерировать; «Показать сравнение · F», F в 3D, колесо для
   масштаба. Камеру можно свободно вращать стандартной навигацией Godot.
3. Номера над деревьями совпадают со списком. Выбрать №2 в 3D или «Настроить»;
   справа изменить толщину/листву: сначала draft без remesh, затем «Применить».
   №1/3/4 не меняются; Undo/Redo справа возвращает draft и applied geometry.
   «Сбросить правки» тоже undoable. Dirty draft не теряется при попытке сменить
   вариант/сохранить/начать новую партию. Solo/gallery не удаляет остальные.
   Отметить два лучших; Undo/Redo выбора кнопками «↶ Настройки»/«↷».
   Настройки слева относятся только к новой партии.
   Сгенерировать ещё две партии по 4: история содержит 12, даже если первые
   отмечены лучшими; каждая новая партия всё равно имеет 4. Проверить фильтры
   «Все партии»/«Только лучшие»/«Партия 1»; номер и seed старых не меняются.
   «Настроить» старого №2 восстанавливает его одного; добавить галочкой «3D»
   новый №9 для сравнения. Изменить листву №2, Apply/Undo/Redo — только его.
   «Последняя партия в 3D» не удаляет историю. Более 4 одновременно не добавляется,
   если есть дерево выше 128 vox — лимит 2. Снять «3D» не значит снять «лучший».
4. Отметить лучшие из разных партий, включая не показанные в 3D, и сохранить
   выбранные по очереди: одно семейство с concrete вариантами, без placement.
   Ctrl+Z/Shift+Ctrl+Z отменяет/возвращает публикацию по одному варианту.
   Поздние правки файлов и используемые в карте объекты не удаляются историей.
5. «Сохранить свой пресет…»: имя, save; закрыть/открыть панель, выбрать пресет.
   «Объекты → Ещё → Генерировать похожие» загружает настройки saved дерева;
   «Создать вариант из рецепта» редактирует тот же frozen skeleton в Canvas.
6. Попробовать 256 vox: до 2 точных объектов, cancel между деревьями. Сохранить
   studio scene с preview: после reopen temporary objects не сериализованы.
7. С dirty draft переключиться на карту: мастерская paused, в карте никаких
   previews. «Открыть вкладку 3D» возвращает тот же набор и draft. Закрыть именно
   studio scene tab, снова открыть мастерскую: candidates восстанавливаются.
   «Закрыть набор» → Cancel ничего не удаляет; подтвердить удаление — очистить
   temporary candidates, saved library files остаются. Restart editor теряет
   unsaved session: перед ним сохранить лучшие и scene/Canvas drafts.
8. «Настройки дерева → новая партия» переносит параметры для presets/новых seeds.
   «Новый каркас из настроек партии» заменяет только выбранный, Undo возвращает
   прежний каркас. После publication правки через Canvas либо новую партию;
   file Undo не разблокирует local edits. Типы/направление ветвей уже расширены
   следующим срезом выше; редактирование отдельных веток пока не реализовано.

## Общий voxel refresh и 3D viewport (ручная приёмка открыта)

Следующий пользовательский прогон: 205 rebuilt/21 disk rename Failed, другие IDs.
`test_editor_filesystem` проверяет nested weak scan leases/coalescing/release.
`test_voxel_scene_refresh` — два transient FAILED и success без повторного meshing,
а также настоящий FileAccess READ handle на Windows: после release запись проходит
на третьей попытке (PASS), per-model Undo/Redo остаётся exact. Native isolated
library button проверяет отсутствие наших scans внутри batch и retry/history.
Queue ждёт active scan/import до 30 s, публикацию повторяет до 3 s с 100 ms yield;
перед retry проверяются source/prefab/instance conflicts. Save/reopen Source не
переписывается. После reload повторить список ошибок (или всю очередь, если список
сбросился). Финальный рабочий прогон пользователь подтвердил: 226/226 rebuilt,
0 skipped — batch gate принят. Конкретный reader,
удерживавший файл в рабочем Godot, не доказан. Не отключать антивирус для проверки.

Рабочая очередь пользователя 226/226: 196 rebuilt, 30 skips. Fix regression
`tools/test_voxel_refresh_legacy.gd` читает доступные 30 исходных assets из отчёта,
но публикует только user:// copies: indexed/unit-adapter и opaque VOX ShadowBody
compatibility, source/prefab hashes, unchanged bounds/node frames/authored children,
UID, exact Undo bytes/references, Redo и normalized prefab reopen. Все 30 PASS.
Suite безопасно пропускает недоступные local author cases и сообщает tested count.
`test_voxel_scene_refresh` также покрывает equivalent indexing vs custom color,
never-built UID и точные failed IDs. Native isolated editor проверяет existing
no-UID text prefab publication и реальную retry button после исправления fixture
source, без публикации production assets. После перезагрузки plugin (сохранить
draft/scene) в Migration повторить failed IDs; если editor session уже сменился,
запустить всю библиотеку снова. Проверить отсутствие 30 прежних skips, размер,
низ/тени обычных объектов, Undo/Redo и save/reopen. Retry list editor-only.
Repair final: scene_refresh, all 30 legacy author-copy regressions, object Canvas,
generator editing, object library/workshop layout, plugin parse и diff check PASS.
Native isolated Forward+ publication/retry/EditorUndoRedoManager PASS; ERROR нет,
только прежние два tree external mesh UID text-path fallback warnings.

Полная библиотека: `test_voxel_scene_refresh` дополнен очередью без active scene,
deduplicate ID, force rebuild current, cancel после первого, Undo/Redo prefab bytes,
Source hashes и созданием отсутствующего prefab (Undo оставляет recoverable asset).
Команда «Объекты → Пересобрать всю библиотеку» / Ember Migration: следить за N/M,
нажать остановку между моделями, проверить список пропусков, Undo по моделям,
вид снизу у обычных/деревьев и save/reopen размещённых экземпляров. В полном
production каталоге пользователь уже запустил: authored assets тестами не используются
как write-fixture. Очень большой объект может задержать текущий кадр; yield/cancel
между моделями, не прерывает meshing на половине.
Расширенный targeted suite, library/workshop layout, object Canvas и generator
editing прошли; native isolated editor проверяет реальную library button на двух
fixture ID, включая outside-scene asset, прогресс и per-model history. Fixture
source/import setup settle выполняется до capture стартового source hash:
изменения setup/UID import не приписываются library-команде.

`tools/test_voxel_scene_refresh.gd`: обычные/прозрачные модели, четыре inline
instances, subset collision, clockwise winding всех треугольников и нижние грани,
Source/map hashes, prefab UID, transforms/placement_id/authored descendants/visual
overrides. Undo возвращает точные prefab bytes и прежние mesh/shape references,
Redo — подготовленные; старые snapshots не мутируются. Save/reopen, skip current,
отказ при произвольном custom mesh/его surface material, сохранение per-instance
surface material override. Surface configure того же source + explicit
refresh меняет chunks без canonical изменения; доступный native adapter также
проверяется на winding (при отсутствии Voxel Tools используется GDScript fallback).
Headless fixture 2 models/4 props около 0.13 с; это не профиль больших деревьев.
Новый targeted suite и девять related suites PASS (object/assembly Canvas,
generator editing, object library/workshop layout, Surface Canvas workflow,
world Surface projection, native cutaway, projection cache). В актуальных
авторских tree_190013632/tree_1511837690_canvas_1665774388 остаются UID warnings
по старым external meshes с корректным text-path fallback; их исходники не
переписывались. Cold isolated editor также предупреждает о legacy material UIDs.
Это отдельно от ошибок/готовности самой refresh-транзакции.
Native Forward+ scene-refresh before/after captures и сценарий PASS; изображения
просмотрены. После обновления нижние грани обычных voxel props закрыты.

В рабочем Godot: сохранить/отменить Canvas draft, перейти в 3D → «Ещё…» →
«Обновить воксели сцены». Статус открывается в Ember Migration и перечисляет
обновлённые модели/экземпляры/Surface и причины пропуска. Покрутить снизу обычный
объект и дерево, проверить обновление без закрытия сцены, Ctrl+Z/Redo, Ctrl+S и
повторное открытие. Inspector → Rebuild prefab обновляет только выбранный model_id
(все его экземпляры), другие модели не меняются. Проверить авторские mesh-правки:
они должны приводить к пропуску модели, а не исчезать. Source/recipe не пишутся.
Surface requeue идёт асинхронно в штатном frame budget; scene Undo касается
замены экземпляров/prefab, а не canonical source или временных Surface chunks.

`tools/editor_test_voxel_scene_refresh.gd` — opt-in только в отдельной
ember-canvas-smoke-refresh-* копии: реальная кнопка dock, EditorUndoRedoManager,
изменение open inline mesh/shape, неизменность source/map/pose и editor save/reopen.
Native isolated editor сценарий PASS; рабочая пользовательская приёмка открыта.

## Общий редактор рецептов генерации (ручная приёмка открыта)

2026-09-12: после вариаций/bottom fix 15 targeted/related suites PASS без ERROR/WARNING — generator_editing,
workshop_layout, large_tree_object/dialog, generator, tree/bush/grass_generator,
object_canvas, assembly_canvas, projection_cache, stamp, selection_interaction,
surface_canvas_workflow, object_library_layout. Assembly Canvas повторно проверен
после capability guard общей панели (target_name/generator_context).
Native Forward+ generator_editing capture и весь сценарий — PASS; изображение
просмотрено, параметры прокручиваются отдельно, кнопки доступны. Скриншот не
заменяет пользовательскую оценку формы и живой workflow в рабочем editor.

`tools/test_voxel_generator_editing.gd`: exact skeleton capture 64/128/256 и три
формы, неподвижные wood/collision при всех foliage controls, palette-only geometry,
bare tree, thickness без перестановки lines, validation, recipe save/reopen и
детерминированная пересборка. Реальный Canvas: contextual tab, descriptor control,
draft buttons/Ctrl+Z/Ctrl+Shift+Z, exact prefab mesh preview без изменения source,
RMB camera, отдельный variant source/recipe/prefab, scene Undo/Redo/save/reopen,
preview==saved geometry, discard, выбор кисти/смена вкладки, ordinary tab hiding.
Fixtures пишут только в отдельные `user://` sources/recipes/prefabs.
Native Forward+ `-- --capture` сохраняет `user://voxel_generator_editing.png`
и `user://voxel_generator_bottom.png` (камера снизу).

Дополнение 2026-09-12: generator_editing проверяет clockwise triangles всех шести
сторон, family grouping одной карточкой, dropdown concrete variation Place/Edit,
case-insensitive duplicate names, standalone отдельную карточку, update одного
model_id и двух linked props с Undo/Redo source+recipe+mesh, внешний source hash
конфликт. object_canvas проверяет opening точного старого DOWN winding без записи
source и отказ при посторонней ручной mesh-правке; старые BarrelA/CargoA открываются.
Prefab rebuild gate повторно PASS после пересборки только control lantern_stone
prefab/двух mesh; source и карта не изменены, UID/четыре placements сохранены.

Вручную: открыть готовое большое v2 дерево в Canvas → Генератор. Поменять цвет
листвы на осенний, количество 100/30/0, размеры/приплюснутость/сомкнутость;
собирать preview после каждой правки и смотреть, что ветви не перемещаются.
Толщина/сужение меняют только объём ветвей. Проверить draft Undo/Redo, RMB/MMB/zoom,
Esc и выход в Части, затем Save variant — рядом появляется отдельный объект.
Выйти из генератора для общего scene Undo/Redo; сохранить и открыть сцену заново,
открыть variant в Canvas и убедиться, что recipe/cаркас восстановлены.
Исходное дерево и ручная лепка остаются нетронутыми; ручные правки не копируются
в рецепт. Смена объекта сбрасывает parameter draft. Classic/остальные генераторы
ещё не показывают эту вкладку; это не исчезновение их старого инструмента создания.

Проверка вариаций в рабочем editor:
1. Сохранить «Лето», затем «Осень» как новые вариации одного дерева: в Объектах
   одна карточка, справа dropdown; выбранную вариацию можно открыть и поставить.
2. Обновить выбранную «Осень»: изменяются только её экземпляры; выйти из
   Генератора, проверить общий scene Undo/Redo, сохранить и повторно открыть сцену.
3. «Отдельный объект» создаёт самостоятельную карточку. Пустые/повторяющиеся
   имена запрещены. Старые независимые деревья автоматически не объединяются.
4. При ручной лепке обновление поверх вариации блокируется; новый вариант
   доступен, но не включает ручные правки. Другая вариация не должна меняться.
5. Проверить дерево снизу. Для старого уже записанного mesh выбрать prop в
   Inspector → «Rebuild prefab»; исходник/placement не меняются.

## Полировка больших деревьев (художественная приёмка открыта)

Действующий creation owner — `EmberVoxelGenerationPanel` / GenerationSession;
параметры сохранённого объекта открываются в workshop generator panel. Старый
недоступный tree-object dialog и его отдельный тест удалены. Генераторы,
Creation, Resource/recipe schema и версии старых моделей этим cleanup не менялись.

`test_voxel_large_tree_object`: 64/128/256, height-1 без деревянного spike,
determinism, classic fallback с прежними defaults, влияние новых параметров,
различная ярусная крона, связность v2 fixture, storage envelope крайних параметров,
collision/Canvas и source+recipe+prefab save/reopen, placement Undo/Redo.
`test_voxel_generation_session`: текущие defaults, classic visibility, draft
edit/apply/discard, exact preview/publication и версия recipe при reopen; размеры
1280×900/1280×720 без увеличения окна. `test_voxel_workshop_generator_save`:
правка требует нового preview, Save/Undo/Redo/reopen сохраняют exact geometry,
palette и весь recipe. Все три targeted gates PASS. Это не native editor capture
и не ручная оценка силуэта/удобства; 125% и реальный dock остаются manual gate.

Вручную: Объекты → Генерация… → Деревья, 64 vox → собрать preview.
Classic проверить на сохранённом старом recipe; проверить толщину ветвей 35/75, сужение 0/80, изгиб 0/80,
начало ветвления 20/50; пучки 80/160, приплюснутость 20/80, сомкнутость 15/85.
Изменения требуют нового preview и не пишут assets. Повторить три формы кроны,
Другой вариант, 128/256, цвета/корни. Создать → Undo/Redo → сохранить сцену →
открыть повторно; старый recipe открывает classic и не меняет старый экземпляр.
Это проверка геометрии/удобства; красивые toon shadows и свет — отдельный срез.

## Обновление файлов после сохранения (ручной gate открыт)

`tools/test_editor_filesystem.gd`: восемь запросов → один scan; импорт/scan
блокирует исполнение, но не теряет запрос; full supersedes source-only;
запрос из scan callback не теряется; слабая ссылка освобождает pending.
Обычный runtime-вызов не обращается к EditorInterface.
Связанные: party_save_v2, party_progression, voxel_object_canvas,
surface_canvas_workflow, voxel_stamp, voxel_generator, voxel_large_tree_object,
voxel_pattern, object_inspector_actions, voxel_selection_interaction,
voxel_merge, voxel_object_split, voxel_primitive_conversion, voxel_shapes.
12 сентября: 15 focused/related gates и 13 parse checks PASS без ERROR/WARNING.

`tools/editor_test_filesystem.gd` — opt-in EditorPlugin только в отдельном
ember-canvas-smoke-* project с отдельным config/name/user:// и cache. Скопировать
скрипт в папку тестового плагина; plugin.cfg использует относительный script.
Legacy pack_path нужен только temp-копии для прежних библиотек. Проверяются
Canvas Save + burst (один scan), Undo/Redo, scene save/reopen, detached discard,
повторная компиляция Party/Explore/progression/save scripts после сканирования.
Non-tool `Script.can_instantiate()` в editor не является parse gate: использовать
`reload(true) == OK`. Каждый запуск создаёт новый scene_path, иначе open_scene
может вернуть восстановленную старую вкладку, а не переписанный fixture-файл.
Логи обязательны: fixture PASS без проверки ERROR/WARNING недостаточен.
12 сентября: финальный native Forward+ запуск на RTX 5070 прошёл весь fixture
и завершился без ERROR/WARNING; diagnostics scans=3, merged=9, pending=0.
При успешном выходе fixture адресует WM_CLOSE_REQUEST только родителю
EditorInterface.get_base_control() (EditorNode), deferred. Propagate root close
ломает child traversal, а прямой SceneTree.quit обходил штатный editor exit
и оставлял Scan thread aborted; это ошибки автоматического выхода fixture,
не parse errors Party/Explore. Этот synthetic lifecycle не закрывает более
широкий ручной Причал/сохранения всех открытых authoring-сцен.

Вручную: после сохранения черновиков и перезапуска Godot очистить Output,
создать/изменить и сохранить несколько штампов и модель Canvas; Undo/Redo,
закрыть/открыть сцену, вернуться в окно после внешней правки. Проверить новые
Party/Explore parse errors и момент их появления. Полную причину прежних
intermittent diagnostics нельзя считать установленной по этому hardening-срезу.

## Одиночные объёмные штампы (manual gate открыт)

Автоматически: `tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless
--path . --script res://tools/test_voxel_workshop_layout.gd` и затем тот же запуск
для `test_voxel_selection_interaction.gd`, `test_voxel_selection_mask.gd`,
`test_voxel_stamp.gd`, `test_voxel_pattern.gd`, `test_voxel_generator.gd` и
`test_voxel_tree_generator.gd`.
Native: без `--headless`, добавить `-- --capture`;
captures `user://voxel_workshop_compact.png`, `user://voxel_workshop_layout.png`
и `user://voxel_stamp.png`. Fixtures только user://.
Связанные: test_voxel_selection_interaction, test_voxel_fragment,
test_voxel_merge, test_voxel_object_canvas; plugin check-only.

1. Слева выбрать `Выделение`, отметить небольшую разноцветную деталь. Открыть
   `Штамп` → `Библиотека` → `+ Новый штамп`, ввести название и сохранить. Источник не меняется.
2. Найти пресет по карточке/миниатюре → `Выбрать`. ЛКМ задаёт опору (для Add — перед
   видимой гранью), стрелки/XYZ уточняют позицию. Проверить поворот 90°,
   отражение и три опоры через прямые кнопки без выпадающих списков. Esc не меняет модель.
3. «Добавить»: занятое не перекрашивается. «Заменить»: occupied footprint меняет
   цвета/материальные каналы; пустой угол/дырка шаблона не стирает объект.
   Enter фиксирует один отпечаток, но тот же штамп остаётся под курсором для
   следующего. Два Enter создают две отдельные Undo-команды; Undo/Redo не снимает
   выбранный штамп и возвращает geometry/palette/parts каждого отпечатка отдельно.
4. В склейке выбрать часть для новых voxels; новые ячейки получают эту часть,
   replaced occupied сохраняют прежнюю. Проверить Save Canvas и F6 collision.
5. Save/reopen сцены и редактора: пресет в библиотеке, отпечаток в объекте.
   «Редактировать модель штампа…»: изменить шаблон, Save, затем новый отпечаток
   использует новую форму, ранее поставленные не меняются. Проверить discard.
6. Lock, выход за холст/срез, несовпадающие плотности, palette overflow — отказ
   целиком. Маска кисти при открытии штампа сохраняется, но её контур и действие
   приостановлены до возврата к совместимой кисти. Изоляцию/скрытие групп нужно
   отключить; чужие authored files не удаляются.
7. Повторить при 1280×720 и 1600×900: параметры и Apply/Cancel не обрезаны,
   footer-подсказка не занимает правую панель, обе панели сворачиваются, Canvas
   расширяется, `Не сохранено`, disabled и красная ошибка явно различимы. Внутри
   `Части` переключить `Выделение / Группы / Вид`: каждый сценарий имеет свой
   локальный scroll и не раскрывает остальные секции длинным полотном.
   Палитра и её пять действий остаются видимыми снизу слева при переключении
   между `Части / Библиотека`; длинная палитра прокручивает только образцы.
   Создать длинное имя группы/части: текст сокращается, ни одна кнопка или строка
   не пересекает правую границу панели.
8. В реальном editor при системном 125% масштабе видны обе правые вкладки. Scoped
   Theme меняет только мастерскую: normal/hover/active/primary/disabled различимы,
   шрифты и editor icons остаются из текущей темы Godot. Карточки прокручиваются
   отдельно, а выбранный штамп и `Выбрать / Редактировать` остаются видимыми.
9. В Object Canvas поле `Объект` меняет только имя выбранного экземпляра сцены.
   Пустое, недопустимое и занятое соседним узлом имя отклоняются; Enter и потеря
   фокуса применяют, Esc отменяет ввод. Undo/Redo и Ctrl+S + reopen сохраняют имя,
   но не меняют display name, model ID и файлы voxel-модели. В Surface поле disabled.
10. В палитре выбрать тёмный цвет и сравнить образец с hex в подписи: normal,
    hover и selected не меняют сам цвет swatch. Более светлая грань в 3D допустима
    как результат освещения; цвет образца должен оставаться точным.
11. Пройти `Кисть → Выделение → Маска → Кисть → Штамп → Кисть`: только текущий
    основной инструмент янтарный, Canvas не меняет размер. В библиотеке ЛКМ по
    модели ничего не лепит. Начать stamp path и сразу выбрать кисть: preview
    отменяется без изменения Resource и не возвращается сам. В активном штампе
    первый `Esc` отменяет только текущий черновик, второй `Esc` возвращает последнюю
    кисть; обычное выделение скрыто, но снова видно по V.
12. Пока штамп выбран и следует за мышью, вращать ПКМ, двигать СКМ и приблизить
    колесом у края Canvas. Черновик не применяется и не сбрасывается, ghost снова
    оказывается под курсором. Камера проходит через боковой ракурс к виду снизу;
    СКМ двигает также по вертикали, а off-center zoom удерживает деталь под мышью.
13. `Сгладить`: на широком бугорке сравнить `Ступени` и `Общий уровень`, затем
    сделать неглубокую ямку и переключить `Обрабатывать ямки`. Пустое отверстие
    не закрывается; радиусы 16/32 не дают заметного стоп-кадра. В `Рельефе`
    проверить прежнее `Наращивание`, затем `Генератор · Почва / Гребни`, отдельно
    сравнить `Детали · лёгкие` с прежним `Детали · мало` (лёгкий вариант должен
    оставлять редкие мягкие перепады примерно на 1–2 вокселя), затем проверить три
    направления и `Другой вариант`. Одинаковый вариант бесшовно продолжается
    соседним мазком, повтор внутри LMB не копит высоту; Undo отменяет весь жест.
14. `Штамп → Библиотека → + Новый источник → Камень`: изменить XYZ,
    `Неровность`, `Сколы`, `Форм в россыпи` 1/4/8 и `Размер форм ±` 0/25/50%,
    нажать `Другой вариант` и сохранить. Миниатюра показывает до четырёх форм,
    карточка — полный размер набора; `Редактировать` возвращает тот же рецепт.
    Затем через `Выбрать` проверить основную форму в `Один` и разные силуэты в
    `Россыпь` с автоматически предложенным шагом и облеганием. `Другой вариант`
    стабильно меняет расположение/выбор форм, preview не меняет Resource, Enter
    применяет, Undo возвращает весь отпечаток. Старые штампы, одноформенные камни
    и паттерны продолжают работать как раньше. В уже поставленном камне изменение
    рецепта будущих отпечатков ничего не меняет.
15. `+ Новый источник → Дерево`: сравнить высоту 10/18/32, толщину ствола,
    радиус кроны, ветвистость и неровность 0/50/100, затем задать разные цвета
    ствола и листвы. Боковая миниатюра должна показывать ствол и до четырёх форм.
    Сохранить набор из 4–6 форм, поставить `Один`, затем провести `Россыпью` по
    ровной и ступенчатой земле. Проверить предложенный шаг, `Другой вариант`,
    облегание, Enter и одну Undo. Редактирование рецепта не меняет уже поставленные
    деревья; старые штампы, камни и паттерны продолжают работать.
16. `+ Новый источник → Куст`: сравнить высоту 4/10/24, размах 2/6/12,
    стебли 1/6/12, пышность и неровность 20/60/100, затем два цвета и набор
    1/4/8 форм. Боковая миниатюра должна показывать низкие широкие силуэты, а
    `Другой вариант` — заметно менять ветвление без распада формы. Сохранить,
    поставить `Один`, провести `Россыпью` по ровной и ступенчатой земле и
    проверить предложенный шаг, облегание, Enter, одну Undo и edit/reopen.
17. `+ Новый источник → Трава`: сравнить высоту 2/6/12, размах 1/2/4,
    2/8/16 травинок, разброс высоты и наклон 0/50/100, два цвета и набор
    1/4/8 форм. Первый выбор предлагает `Россыпь` и полезный шаг; пучки растут
    вверх и привязываются корнем к каждой локальной верхней поверхности без
    внутренней деформации. Боковая грань получает явный отказ. До Enter только
    preview, после Enter одна Undo. В F6 земля остаётся физической, сквозь траву
    можно пройти. Обычный штамп на том же explicit-collision target физичен;
    save/reopen и discard рецепта сохраняют результат.
18. `Выделение → Два этапа`: начать сверху и протянуть область на первой грани.
    После первого отпускания прежнее выделение остаётся, геометрия не меняется,
    голубой preview фиксирует плоскость. Движением мыши внутрь проверить глубину
    1/2/8, точный SpinBox, второй клик и Enter. Повторить на четырёх боковых
    гранях и снизу; направление всегда задаёт первая грань. Почти фронтальный
    ракурс использует вертикальный ruler. Проверить `Новое`, Shift-add, Ctrl-
    subtract, одну Undo/Redo после подтверждения, Esc на обоих этапах, смену
    инструмента, маску кисти и обычную экранную `Рамку`. Ни один draft не меняет
    Resource; рельеф не огибается автоматически.

Большие штампы измерены отдельно (16384 vox, plan ~60ms); полная производительность
на авторском Причале и визуальная/input-приёмка остаются ручным gate.

## Нижняя полка объектов 3D (manual gate открыт)

Старый недоступный `VoxelVisualLibraryPopup` удалён из migration dock; кнопка
«Открыть полку объектов» по-прежнему выдаёт `voxel_library_requested`, который
plugin направляет в постоянную нижнюю полку. Добавление идёт через её
`place_requested`; native Resource и refresh Inspector после migration сохранены.
Cleanup gate PASS: migration_workflow_layout, voxel_object_library_layout,
voxel_visual_library, voxel_object_library_updates, object_inspector_model,
object_inspector_panel, object_inspector_actions, plugin `--check-only`.
Общий `tools/test_vox_axes.py` остаётся FAIL по двум прежним shader-string
ожиданиям. Проверка dock теперь направлена на SceneRefresh, а не на отсутствующий
прямой ensure_saved и неиспользуемые snapshot/hash helpers; шейдеры не менялись.
Пять невызванных helpers удалены из Explore/Graph/Combat/dock. Связанные gates
PASS: party_save_v2, graph_workspace, graph_lifecycle, combat_prototype,
voxel_scene_refresh. Graph ожидает существующие 9 семейств, включая soft Grab;
preview/commit/Undo/serialization и UI владельцев этим cleanup не менялись.
Ручной вход через Migration/«Объекты» и добавление/Undo остаются в gate ниже.

Автоматически: `tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless
--path . --script res://tools/test_voxel_object_library_layout.gd`, затем
`test_voxel_visual_library.gd`, `test_voxel_large_tree_object.gd`,
`test_voxel_generation_session.gd`, `test_voxel_workshop_generator_save.gd`;
`plugin.gd --check-only`. Native shelf capture: layout без `--headless` с
`-- --capture`, `user://voxel_object_library.png`. Реальную генерацию проверяет
`editor_test_voxel_generation.gd`, только в disposable editor copy.

1. В 3D нажать `Объекты`: снизу открывается полка, сцена и selection остаются
   видимы; модального окна нет. Повторить вход через Ember Migration.
2. Проверить поиск и фильтры `Все / Готовы в Godot / Ожидают переноса`.
   Выбранная карточка показывает превью, название, стабильный ID, размер, теги и
   owner; `Редактировать шаблон`, `Поставить в сцену` и `Ещё…` не уезжают при
   прокрутке каталога.
3. При выборе объекта сцены шапка пишет `рядом с … · смещение +X`; без selection —
   player_start или начало Map. Сменить selection при открытой полке: подпись и
   anchor должны обновиться.
4. Для native-модели нажать `Редактировать шаблон`: открывается Object Canvas с
   тем же Resource. Подсказка предупреждает, что Save затронет все экземпляры;
   проверить правку, Save, Undo/Redo и reopen на двух экземплярах этой модели.
5. Для legacy-модели кнопка называется `Перенести и редактировать`: одна migration
   Undo-команда создаёт Godot Resource и сразу открывает его в Canvas. Отменить
   перенос после выхода из Canvas и проверить возврат карточки в legacy-фильтр.
6. Поставить native и legacy-модель. Сохраняются прежние Map/Props owner, Undo/Redo,
   Ctrl+S и reopen; legacy prefab собирается существующим import owner. Открытие
   Godot Resource и перенос доступны только для подходящего owner.
7. Повторить при 1280×720 и 1600×900: каталог расширяется, правый details остаётся
   фиксированным, основная кнопка видима, текст не выходит за границы.
8. Нажать `+ Большое дерево`; проверить высоты 64, 128 и 256, толщину ствола,
   размах кроны, ветвистость, неровность, плотность листвы, цвета и
   `Другой вариант`. До `Собрать точный предпросмотр` файлы не создаются, OK
   disabled. После сборки изменение параметра снова требует явного preview.
9. Создать дерево: оно появляется как один обычный объект в `Map/Props` и как
   native-карточка в каталоге. Ctrl+Z/Redo снимает/возвращает placement; Save и
   reopen сцены сохраняют его. `Редактировать шаблон` открывает прежний Canvas.
   Долепить и удалить voxel, проверить Canvas Undo/Redo, Save/reopen и prefab.
10. В `Ещё…` выбрать `Создать вариант из рецепта…`: параметры и seed исходного
    дерева восстановлены, но подтверждение создаёт новый model ID и новый объект,
    не меняя прежние instances. У обычной модели без recipe команда disabled.
11. В F6 пройти персонажем вокруг кроны: ствол и толстые ветви имеют collision,
    листья не образуют невидимую стену. Сравнить silhouette/масштаб 64 и 256 с
    маленьким stamp-деревом 8–32; последнее остаётся в библиотеке штампов.

Ghost под курсором и выбор точки кликом не входят в этот срез: размещение пока
сохраняет прежнюю семантику +X/player_start и отдельно согласуется после UI gate.

## Склейка и разбор текущей формы (manual gate открыт)

Пользовательский UI — общая правая `Ember · Мир` и нижняя «Склейка», без Window.
`test_voxel_merge_dock.gd` PASS: width302/font20, pinned preview/Apply/Cancel,
явный расчёт, field invalidation, view-only orientation, bound context, stale parent,
Canvas guard, reuse, merge/unmerge, Undo/Redo/Save-Reopen и source hashes.
`editor_test_voxel_merge_dock.gd` PASS в disposable Forward+ 1600×900/125%:
панели внутри shell, explicit alignment/bake, повтор с тем же набором,
pending защита от другой selection/режима/map/shape, камера/collapse/orbit,
merge preview==commit, одна Undo/Redo, Save/Reopen; настоящий Canvas dirty guard,
discard/sculpt/save и source stale rejection перед обновлённым unmerge.
Cancel/Esc/возврат Рельеф/scene change очищают refs; terrain file/built tiles прежние.
Связанные merge/bake24/split/conversion/shapes/object-brush/host targeted PASS;
host/placement native regressions PASS. В части QA shutdown остаётся прежний
absolute get_node/scan-aborted после PASS; zero-warning lifecycle не заявляется.
Live удобство и F6 нового UI, большой preview и весь shell1280/125% OPEN.

Дополнительный gate совмещения: взять `Fragment_new` и нижний блок, нижний
назначить основным. При дробном смещении включить «Совместить сетки»: видны
полупрозрачное прежнее положение и Δ XYZ; сцена в 3D не меняется. Снять
checkbox/отменить панель — исходные позиции прежние. Повторить и склеить: результат
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

«Двухэтапное выделение»: test_voxel_surface_marquee проверяет 6 направлений,
16/32 density, раздельные footprint/depth bounds, screen ruler, обратное
протягивание, параллельный луч и bounds clip. test_voxel_selection_interaction
проверяет плоский первый этап без commit, второй этап глубиной 2, второй клик,
одну Undo/Redo, Ctrl-subtract и Esc с сохранением прежнего selection; Resource
не меняется. Native capture сохраняет user://surface_marquee.png.
Вручную: V → «Два этапа» → протянуть верх доски → после отпускания вытянуть
голубой объём внутрь → подтвердить вторым кликом или Enter. Повернуть камеру и
начать на каждом боку и снизу; направление не перескакивает на соседние грани.
Проверить точную глубину, Shift/Ctrl, Esc, начало вне объекта, маску кисти,
дальнейший перенос/Undo и отсутствие изменений Resource/save/reopen.

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

## Поверхность прохода (ручная приёмка подтверждена 13 сентября)

Пользователь подтвердил «все работает» после исправления перекрывающихся опор.
Панель в основном 3D-окне, voxel-кисти и отсутствие левитации над балкой приняты.
Ниже сохранены сценарии повторной проверки; остальные editor/combat gates
и известный teardown diagnostic этой приёмкой не закрываются.

Перед запрошенным commit/push повторно PASS: test_explore_stepping,
test_walk_surface_mask, test_test_pier (exit 0). Логи:
Temp/ember-checkpoint-test_explore_stepping.log,
Temp/ember-checkpoint-test_walk_surface_mask.log,
Temp/ember-checkpoint-test_test_pier.log.

Ручная регрессия 13 сентября: удалённая mask область оставалась коллизионной
из-за второй активной опоры. В saved test_pier найдены WalkSurface и
WalkSurface_new на одинаковом source/pose/allowed. Read-only subtree/реальный
EmberPlayer probe: старая опора держит Y≈1.958, после её отключения в fixture
герой стоит на балке Y≈−0.042. Лог Temp/ember-walk-support-probe.log. Авторская
сцена не переписывалась, editor MCP недоступен.
`test_walk_surface_mask.gd` дополнительно проверяет неоднозначный source-open
без создания третьего helper, явный warning/resolve, ordinary Apply refusal,
отключение дубликата без удаления Node, physical erased-cell clearance,
Undo/Redo layers, saved inactive layer и reopening source→active helper. PASS.
6 related suites PASS: walk_surface, voxel_scene_assembly, voxel_assembly_canvas,
voxel_placement, voxel_object_library_layout, test_test_pier.
Native fixture: видимая «Оставить эту опору», emit реальной кнопки, native Undo/
Redo, save/reopen и source reuse PASS. Снимок walk-panel-editor-duplicate-warning
просмотрен. Логи Temp/ember-walk-duplicate-test.log, ember-walk-duplicate-editor.log.
Последний native rebuild-after-update gate PASS:
Temp/ember-walk-duplicate-editor-final.log; known teardown get_node diagnostic.
Ручной шаг: открыть Map/Props/WalkSurface_new, «Оставить эту опору», save/F6;
проверить стойку на балке и отсутствие старой коллизии над удалёнными клетками.

Voxel/brush срез 13 сентября: `tools/test_walk_surface_mask.gd` проверяет
ограничение ширины щелей, открытые края и рваные концы, отсечение нижней балки,
точность объединённых collider rectangles, voxel scale 16/32/nonuniform,
быстрый мазок без пропусков, restore только allowed, одну action на мазок,
черновые Undo/Redo/abort, отсутствие записи preview, сценовые Apply/Undo/Redo,
collision hole и save/reopen. Настоящий EmberPlayer проходит плоские стыки
без проседания; fractional origin не округляется при открытии. PASS.
Замер fixture 192×256 — около 26–33 ms generation, 5 rectangles. Opt-in
`-- --benchmark-native` читает существующий prefab, не меняет source/сцену.
Логи: Temp/ember-walk-mask-final.log, ember-walk-mask-test.log.
8 headless suites PASS: walk_surface, walk_surface_mask, explore_stepping,
voxel_scene_assembly, voxel_assembly_canvas, voxel_placement,
voxel_object_library_layout, test_test_pier. Native Forward+ fixture functional
PASS: реальный viewport ЛКМ erase/restore, draft Undo/Redo, orbit с активной
кистью, compact/expanded «Положение» при 1280×720/1600×900, Apply/сценовые Undo/
Redo/save/Cancel. Captures walk-panel-editor-voxel[-position]-720/900.png
просмотрены; логи Temp/ember-walk-mask-editor-final.log и последней проверки
ember-walk-mask-editor-review.log. Последний native rebind/duplicate/Undo gate:
Temp/ember-walk-mask-editor-rebind.log. На exit остаётся прежняя ошибка get_node
outside active scene tree; не заявлять zero-warning editor lifecycle.

Ручной gate: выбрать только настил/его группу → «Поверхность прохода» →
«По геометрии». Проверить соответствие сетки размеру vox исходника, щель/допуск,
сохранность внешних концов. «Убрать» ЛКМ и протягиванием; «Вернуть» не создаёт
клеток за контуром. Отменить мазок кнопкой и незавершённый мазок Esc; камера
вращается и при активной кисти. Раскрыть «Положение», Apply, native Undo/Redo,
save/reopen/F6. Сетка в игре отсутствует, малые зазоры не вызывают проседания,
оставленные отверстия и пустота за концами не имеют добавленной коллизии.
Исходные доски и авторская карта автоматически не перезаписываются.
Если прямоугольник уже существует, сначала открыть именно WalkSurface, затем
выбрать доски и нажать «По геометрии». Проверить, что после Apply число опор
не выросло; Undo возвращает исходную форму/привязку. Новая опора рядом со старым
необрезанным прямоугольником не устранит его коллизию за краями.

13 сентября: прежний диалог заменён нижней панелью «Опора» и черновиком
в основном 3D-окне. `test_walk_surface.gd` дополнительно проверяет отсутствие
scene-tree mutation и сериализации при активном preview, invalid plan clear/
refusal/recovery, Cancel и scene switch cleanup. Native editor fixture
`tools/editor_test_walk_surface_panel.gd` устанавливается только в disposable
ember-canvas-smoke-walk-panel-* project; обычный рабочий editor не запускается
headless. Новый ручной gate: открыть панель, вращать/приближать основную камеру,
изменить Y/size/tilt, Apply/Undo/Redo/save/reopen, Cancel и переключить сцену.

Related headless PASS: voxel_scene_assembly, voxel_assembly_canvas,
voxel_placement, voxel_object_library_layout, test_test_pier. Native Forward+
editor fixture PASS: actual plugin command, свободный viewport orbit/zoom,
preview без dirty/serialization, Apply, native Undo/Redo, save и Cancel.
Layout 1280×720/1600×900: адаптивные колонки без горизонтальной прокрутки полей,
captures walk-panel-editor-preview-720/900.png просмотрены. Логи:
Temp/ember-walk-panel-test.log, ember-walk-panel-direct.log и ember-walk-panel-*.log.
Первый fresh import копии диагностировал существующий legacy pack fallback;
для fixture задан исходный pack_path только в disposable config. Не добавлено
новых production JOI calls. Неиспользуемая zylann extension в fixture отключена
после library-copy failure. UID fallback старых сцен и get_node outside active
tree после функционального PASS остаются отдельными startup/teardown diagnostics;
это не zero-warning/full editor lifecycle gate.

`--headless --path . --script res://tools/test_walk_surface.gd`: создание,
редактирование, Undo/Redo, отмена, stale/invalid отказ, pack/save/reopen,
обычный physics ray и реальный EmberPlayer на опоре, отсутствие runtime Mesh.
Связанные gates: test_voxel_canvas_context, test_voxel_assembly_canvas
(включая сохранение секций рядом с опорой), test_voxel_placement,
test_voxel_scene_assembly, test_party_followers.
Исторические captures диалога на 1280×720/1600×900 относятся к предыдущему UI;
для нового flow применяется native editor fixture выше.
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
Перенос её UI в dock 2026-10-07 имеет отдельную незакрытую ручную приёмку ниже;
подтверждение старой расстановки не закрывает новый layout/input gate.

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

UI 2026-10-07: дублирование в `Ember · Мир`, preview в нижней «Копии объектов».
`test_voxel_scene_assembly` PASS с новой компоновкой, 302 px/font20/pinned footer,
UI signals и no-scene preview/Cancel; Forward+ captures 1280×720/1600×900 PASS.
`editor_test_voxel_duplicate_dock` PASS native Forward+ 1600×900/125% в отдельном
checkout: весь split layout внутри shell, numeric Enter, bound row/reopen/collapse,
dirty guards/camera/no brush; Create==preview, весь ряд одним Undo/Redo, Save/Reopen,
last-step repeat на текущем selected target, stale parent refusal, новый context
reset axes/count, Esc/Cancel/terrain-page return/scene change, source SHA/terrain
file/built tiles сохранны. Новый UI руками автором и полный shell 1280/125% OPEN.

Ручной сценарий: выбрать доску → «Ещё… / Дублировать со смещением…» → справа задать шаг
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
новый split layout: parameters dock 302 px/font20 справа, target+context viewport
снизу, scroll и pinned Apply/Cancel. Collapse/reflow сохраняет план, Cancel освобождает
geometry. Test собирает failures до финального exit, включая async capture;
ошибка дочернего capture не допускает ложный общий PASS. Это не весь editor shell.

`editor_test_voxel_placement_dock.gd` native Forward+ PASS в отдельном checkout
1600×900/125%: весь dock/preview внутри shell, pinned actions, numeric Enter с
реальным focused LineEdit/input; pivot без скачка, repeat того же target, другой
selected node не перепривязывает pending plan. Camera pass/без brush input,
collapse, dirty guard (+Map/world toggle), clean переход +Map/Cancel, bound Apply,
один Undo/Redo, Save/Reopen, Cancel/private geometry cleanup, stale parent refusal,
Esc в 3D и сохранность draft при возврате к рельефу/scene switch PASS. Source SHA,
terrain file и built tiles неизменны. Прежние QA shutdown/scan warnings остаются;
zero-warning lifecycle не заявляется. `editor_test_object_brush_dock` и
`editor_test_compact_material_dock` после интеграции PASS; новый UI руками автором
ещё не принят.

Ручной gate: в Причале выбрать `TimberPier/Visual` или отдельную `Part` → «Точная
расстановка…» → параметры в `Ember · Мир`, preview в нижней «Расстановка».
Отключить snap, дать доске небольшое смещение и произвольный угол;
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
`test_voxel_split_preview` — compatibility preview fixture в user://; modal API
сохранён, пользовательский workflow ниже использует dock. Это не полный physics gate.
Ручной gate: выбрать voxel Visual настила → «Разрезать на секции…» → 64 →
проверить 12 границ/деталей → отменить (нет изменений) → открыть/применить →
Ctrl+Z/Redo → открыть одну Part в Canvas, изменить/сохранить → сохранить сцену →
перезапустить → F6 и пройти через стыки. Сложные overrides/вода должны отказать
без изменений сцены. При сбое диска возможны оставленные recoverable part assets.

Общий dock для секций/конверсии: `test_voxel_remaining_docks.gd` PASS для
302 px/font20, pinned действий, явного preview/invalidation, split краёв/размеров,
conversion block/cylinder/sphere, compare без расчёта, density rescale, guards,
stale/Cancel/reuse, large consent/reset, Undo/Redo/Save-Reopen и source hash.
`editor_test_voxel_remaining_docks.gd` PASS в disposable Forward+ 1600×900/125%:
обе панели внутри shell, 64/32 sections, bound repeat/pending, camera/collapse,
numeric Enter/field Esc, compare/density, настоящий Canvas dirty/discard для обоих
Apply, stale source/pose, physical fit/collision layer/один collider, conversion→Canvas,
одна Undo/Redo, Save/Reopen, Cancel/viewport Esc/return Рельеф/scene cleanup.
Preview tabs сохраняются после возврата из Canvas; terrain file/built tiles прежние.
Shared host/merge/terrain native regressions PASS; remaining/merge/shape/host/
split/conversion/object-brush targeted PASS. Старый pier-specific editor helper
адаптирован к dock и parse PASS, его повтор не подменяется новым fixture.
Авторское удобство, F6/стыки большой сборки и полный shell1280/125% OPEN.
В части QA shutdown остаются прежние absolute get_node/scan-aborted после PASS;
zero-warning lifecycle не заявляется. Совмещение коллизии требует явного подтверждения.

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
команда открывает conversion dock (лимит размера остаётся). Ctrl+Z возвращает
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
Исторический Forward+ functional PASS для этой pier fixture; текущий helper
адаптирован к dock и parse PASS, повтор OPEN. Новый полный fixture — выше. Не
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

Общий play controller — `scripts/ember_explore_scene.gd`, один owner для города,
Причала и World Canvas/compact maps. Переезд сохраняет UID и body, обновлены
scene/extends paths; локальная UID-cache запись перенаправлена без полного
editor/import. Parse нового controller/world_canvas/test_pier и runtime gates
test_test_pier, explore_pause_menu, map_transition, combat_encounter_transition,
progress_restore, compact_world_startup PASS. Нет старого файла/compat alias.
Ручные F5/F6/save/input остаются в соответствующих gates; удаление карт этим
переездом не выполнено, архивированные сцены ещё активны до замены fixtures.

Inspector source labels: native Resource определяется по resolved owner и
показывается как `Godot Resource (.tres)`, Asset tooltip направляет в мастерскую.
`test_object_inspector_model` проверяет эти подписи с недоступным legacy pack,
`test_object_inspector_panel` — существующий UI; оба PASS, snapshot read-only.
Map/region references теперь native-only через `EmberInteractionContent`:
`test_native_map_references.gd` проверяет отдельные `user://` scenes с недоступным
JOI, исключение non-map, missing/path-traversal IDs, instance/inheritance,
map-local transforms, обновление дочерней сцены в ту же секунду и detached cache.
Проверка каталога не загружает PackedScene; metadata не вызывает Node `_init`
и не меняет ни source scene, ни удерживаемый live cached PackedScene.
Runtime explicit/default spawn и Interact binding видят вложенный регион через
общий MapLoader; existing collision/safe_spawn остаются прежними owners.
Inspector model проверяет native landscape_compact destination и несохранённый
локальный trigger без JOI, честно отмечает missing entrance/non-map. Старый
mage `start` существует только в legacy hydration, в saved scene он MISSING;
копия старого входа ради теста не создаётся.
`test_map_visual_library.gd` проверяет native region scheme/highlight, current
landscape card/entry, stable door/change-map IDs и неизменный SHA `.tscn`.
Список карт text-only: без массовой загрузки terrain/prefab; схемы — в выборе
точки входа, не preview рельефа. CPU PNG landscape entry просмотрен; настоящий
picker/Forward+ выбор и Save/Reopen/Undo ещё OPEN. Автоматические gates PASS:
native_map_references, map_visual_library, object_inspector_model/panel,
action_resource/script, interact_launch_rules, quest_state, map_transition,
progress_restore, compact_world_startup. Полный G4/G5 не закрыт.

Измерение отдельным headless script в текущем checkout: сбор всех подробных
snapshots стоил около 19 с cold. После разделения discovery/selected details
каталог + список 26 карт — 1,35 с first / 17 мс repeat; это не native-editor
FPS/latency gate. Полная metadata выбранного тяжёлого Причала всё ещё требует
загрузки его dependencies; масштабирование region-query остаётся отдельным
performance вопросом. Данные/меши всех карт при открытии списка не загружаются.

Старт F5 выбран `landscape_compact`, не старый город. `test_progress_restore`
использует настроенную main_scene вместо фиксированного fan_town и проходит;
compact_world_startup после первого сбоя прошёл на повторе с новым стартом.
`test_world_canvas` остаётся FAIL по опоре героя; тот же FAIL воспроизведён с
прежними main_scene/ember map_id через process-only override, без изменения
рабочего project.godot. Причина не установлена, ручной Forward+ F5 OPEN.
Новая точка входа не означает закрытый JOI-detached/export gate.

Основные gates:

- `tools/test_graph_workspace.gd` и `test_graph_lifecycle.gd`;
- `test_object_inspector_model.gd`, `test_object_inspector_actions.gd`,
  `test_object_inspector_panel.gd`;
- `test_action_resource.gd`/`test_action_chain_authoring.gd` через `python tools/run_story_tests.py`;
- `test_action_script.gd` через interaction runner;
- `test_dialogue_authoring.gd`/`test_vn_dialogue_resource.gd` через story runner;
- `test_quest_state.gd`, `test_quest_journal_authoring.gd`,
  `test_quest_usage_index.gd`;
- `test_item_resource.gd` через `python tools/run_item_resource_test.py`;
- `test_shop_resource.gd`/`test_shop_persistence.gd` через `python tools/run_shop_tests.py`;
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

`tools/test_map_transition.gd` больше не использует `fan_town`/`agent_sandbox`:
`tools/fixtures/ember_exploration_test_fixture.gd` создаёт шесть небольших native
maps с compact ground, Regions и дверями, сохраняет и переоткрывает `.tscn` в
уникальном `user://ember-tests/`. Process-local PackedScene aliases обслуживают
обычные `res://scenes/<map_id>.tscn` destinations без изменения runtime router;
тест удерживает Resources до конца процесса. В авторский `res://` ничего не пишет.
Пять door → nested entry → exit → matching return маршрутов проходят настоящие
EmberExploreScene/MapLoader/Player/Interact/Region, проверяют HUD/water contact,
точные XZ spawn, неизменные scene SHA и отсутствие немедленного return bounce.
Отдельно проверены single consume, wrong-map handoff, missing-scene cleanup,
1200 ms expiry и разрешение другого trigger. Ожидание scene handoff ограничено.
Progress storage/restore/persistence изолируются до autoload `_ready`, реальные
пользовательские saves не читаются и не записываются.

ItemCatalog теперь native-only; helper не создаёт items/catalog.json и не даёт
synthetic wallet override. Скопированные current native items/icons включают coin;
старые map/model JSON не нужны. Это не полный G4/G5 остальных доменов.
Отдельный headless code-only QA без всех top-level map scenes,
voxel models, prefabs, sibling JOI и editor/import cache также PASS, без ERROR;
скопированы общий код/шейдеры/materials, native items и fixed combat type preloads.
UID warnings в отдельной копии используют корректные text paths. Рабочий gate
PASS; regressions native_map_references, progress_restore, combat_encounter_transition
PASS. Negative control только в disposable copy: замена selected region spawn
на default spawn вызывает ожидаемый FAIL по всем пяти return routes, SCRIPT
ERROR нет. Это проверяет способность нового gate поймать настоящую регрессию.
Изменены только тестовые файлы; ручные игровые gates ниже остаются
открытыми, новых визуальных/игровых изменений этим срезом не заявлено.

`tools/test_combat_encounter_transition.gd` также использует сохранённую/
переоткрытую native карту из того же helper, не `agent_sandbox`. Общий `prepare`
изолирует progress storage до autoload `_ready`; wallet и items читаются из
native catalog без item JSON. Combat Lab,
Encounter/arena/party и victory action остаются текущими native owners.
После инициализации тест включает persistence/restore только в своём `user://`
и пишет настоящий pre-battle autosave; возврат проверяет departure XZ.
Сохранены проверки deep strategy snapshot, HP/MP/inventory, result modal,
XP/level-up/fallen-at-1, fixed/rolled loot, counters/flags, двойного Continue,
rejected/active roster и сохранности неактивных героев. SHA fixture `.tscn`
не меняется. Production code этим cleanup не менялся.

Detached headless QA без семи старых сцен, voxel models/prefabs/JOI PASS:
копируются shared code/materials, native items/combat resources, Combat Lab,
native arena и только `colored_crossing_victory.tres`; editor/import не запускается.
Negative control в отдельной копии намеренно дважды применяет counter deltas:
gate выдаёт ожидаемый FAIL, без SCRIPT ERROR. Связанные map_transition,
combat_result_bridge, combat_defeat_retry, party_save_v2, progress_restore —
PASS. Retry gate теперь также использует native fixture; его independent
retirement checks перечислены в «Production defeat/Retry gate» ниже.
Item fallback удалён отдельным native item срезом; ручная игровая/Forward+ приёмка OPEN.

Save/chest gate `tools/test_progress_restore.gd` теперь запускается командой
`python tools/run_progress_restore_test.py`. Runner копирует code/shaders,
materials, native items и fixed combat type preloads в disposable проект;
старые города, voxel models/prefabs, sibling JOI и рабочий editor cache не копируются.
Test guard сверяет environment root, sandbox marker и отсутствие `.git`:
прямой запуск в рабочем checkout возвращает REFUSED до fixture model writes,
даже если environment root подставлен равным рабочему пути.
Autoload storage изолируется до `_ready`; собственные saves/maps — в уникальном
`user://ember-tests/`, два маленьких synthetic native voxel Resources и их
производные prefab/mesh — только в temporary `res://`. Coin/herb/meat_bun
читаются из native owners, item compatibility JSON отсутствует.

Проверяются saved native region properties, exact x/y/elev spawn с single consume
и wrong-map guard, main-path redirect/explicit-scene distinction, typed flags,
shop stock и сохранность других chest keys. Настоящие Player/Region дают F prompt,
loot поверх inventory один раз. Повторно открываются save и сама scene с fresh
Region.opened=false: ключ открытия, inventory и отказ повторной добычи сохраняются.
Runtime autoload получает прогресс через existing adopt/load owner до scene readiness.
Без test-side `Region.refresh_chest_visual` проверяются automatic closed/open
модели, реальный mesh, source signature и placement. Fixtures содержат сундук без
visual, вложенный сундук и сериализованный closed prefab, который после загрузки
opened progress заменяется на open. Block size 8 применяется к новым и reused
visuals/mesh scale; повторный общий refresh не пересоздаёт unchanged visuals,
в том числе с включённым compatibility flag при отсутствующем map JSON.
Scene/model source SHA после runtime неизменны.
Это reopen в том же процессе, не отдельный OS restart или ручной F5.

Headless gate и map_transition/combat_encounter_transition/combat_defeat_retry/
native_map_references/party_save_v2/explore_pause_menu PASS; ERROR/SCRIPT ERROR нет.
Negative controls только в копии: потеря opened chest key ловит duplicate loot и
потерю progress; пропуск startup region initialization ловит отсутствующие/неверные
closed/open visuals при загрузке, включая serialized/nested cases. Оба дают
ожидаемый FAIL без SCRIPT ERROR. 887 защищённых author voxel/prefab/material/JOI
voxel файлов сохранили SHA. UID warnings используют text paths.

Startup integration owner — `MapLoader.refresh_region_runtime`, вызываемый общим
ExploreScene до player/UI. Legacy JSON не дополняет saved properties ни при каких
hydration flags; native runtime refresh всех Regions выполняется без него.
Schema, save owner и loot rules не изменены. Native startup/load gate headless PASS;
ручной Forward+ OPEN: закрытый сундук → открытие → Save/Load → сразу открытая модель,
без повторной добычи, корректные масштаб/placement. Автор отложил ручную проверку;
её gate сохраняется OPEN. Inventory/health/followers и item cleanup готовы;
Item/shop domains native-only; Actions/dialogues также native-only; VN assets, voxel catalog/builder и map startup также native-only; legacy editor paths и полный G4/G5 OPEN.

`tools/test_explore_pause_menu.gd` использует две saved/reopened native maps из
общего fixture helper, не `agent_sandbox`. Progress storage/persistence/restore
изолируются до autoload `_ready`; все scene/save/recovery writes — в уникальный
`user://ember-tests/`. Native source/item JSON отсутствуют; wallet принадлежит
native coin Resource. PackedScene aliases удерживаются до конца
теста; fixture scene SHA не меняются. Само меню и Player/ExploreState остаются
настоящими owners, тест нажимает их кнопки, не заменяет обработчики UI.

Сохранены modal-blocker/pause/resume и все slot/autosave controls. Три ручных слота
имеют разные flags/inventory/XZ; их кнопки Save/Load проверяют metadata, same-map
reload и cross-map return, release pause и сохранность manual/autosave bytes.
Delete проверяет первый/второй click, смену target slot, истечение подтверждения,
separate autosave, disabled load/delete после удаления, точные recovery SHA и
неизменность других slots. Ожидания scene handoff ограничены; deferred focus
завершается перед следующей кнопкой, как при обычных пользовательских действиях.

Обнаружен и исправлен реальный load conflict: exit autosave уходящей сцены после
чтения слота записывал прежнюю позицию, очищал pending restore и перезаписывал
autosave. Общий ExploreScene теперь проверяет existing restore flag через
`ExploreState.has_pending_spawn_restore()` перед exit save. Другого save owner,
нового serialized state или временного выключения persistence нет. Обычный map
departure по-прежнему autosaves; UI load сохраняет ожидающие данные/позицию.

Working и detached code-only gate PASS без old scenes/voxel libraries/prefabs/JOI/
editor cache; копируются shared code/shaders/materials/native items и fixed combat
type preloads. Negative controls только в копии: прежний unconditional exit save
ловится saved-position/autosave assertions; delete confirmation без target/deadline
ловится cross-slot/expired-confirmation assertions. Ожидаемый FAIL, SCRIPT ERROR нет.
Related map_transition/combat_encounter_transition/combat_defeat_retry/party_save_v2,
isolated save/chest и save publication PASS (у publication десять ожидаемых write
failure ERROR). 887 защищённых файлов сохранили SHA; исходный pause gate совпадает
с проверенным архивом. Новая ручная Forward+/mouse/keyboard приёмка остаётся OPEN.

Защита записи save v2 — `tools/test_save_publication.gd`: уникальные `user://`
fixtures, manual/autosave, отказ открытия/неполная запись/ошибка сохранения
прежнего файла/публикации/rollback; exact previous bytes, отсутствие `saved` и
изменения remembered progress при ошибке. Десять `EXPECTED SAVE FAILURE` и
соответствующие `ember save: cannot publish` ERROR ожидаемы; SCRIPT ERROR нет.
Моделируется состояние файлов после прерывания между шагами; новый Explore owner
восстанавливает слот через metadata/load_latest, delete не воскрешает `.previous`.
Это не испытание отключением питания. Связанные regressions: party_save_v2,
progress_restore, map_transition, combat_defeat_retry, explore_pause_menu.
Автоматические gates PASS; ручной gate OPEN: в обычной игре сохранить слот,
изменить позицию/инвентарь, загрузить его, перезапустить игру и снова загрузить;
убедиться, что меню автосейва и удаление слота работают привычно.

Общие interaction gates запускаются через `python tools/run_interaction_tests.py`
(либо `--test <имя>`): `test_talk_shop.gd`, `test_action_script.gd`,
`test_interact_launch_rules.gd`, `test_quest_state.gd`. Старые city/story assertions
архивированы; общие mechanics сохранены на synthetic native dialogue/action/shop/
quest Resources и saved/reopened native maps. Action/dialogue одинакового ID
проверяют прежний приоритет resolver; neutral VN document проверяет projection
artId/portraitSide/background/actor lockY/scale/inherited cast без старой графики.
Это projection gate, не VN render/export acceptance.

Тесты используют настоящий ExploreScene/Player/InteractionUI/Interact/Region и
существующие catalogs/economy/quest/save owners. Talk проверяет три реплики, две
ветки и release movement; shop intro переходит в native shop, покупка списывает
wallet/stock, exhausted listing не выдаёт предмет, wallet/inventory/stock переживают
save reopen. Action сохраняет порядок talk→reward→typed flag→wait, F-region route,
timed wait, pause/resume after shop и change-map с nested entry. Настоящий progress
autoload пишет ровно один autosave после reward continuation; reward/flag reopen PASS.
Launch сохраняет bool/string primary/fallback, editor disclosure/русские labels,
completion только после успешного primary, отказ при abort, F↔enter и сохранённый
one-shot после reopen. Quest проверяет three-step prerequisites, start/objective/
final visibility, F groups, original SVG/LOD и anchor над mesh center.

Runner копирует общий code/shaders/materials, current native items, original marker
SVG и fixed combat type preloads; historical scenes/models/prefabs/dialogues/actions/
shops/quests/VN/JOI и editor cache не копируются. Native fixture writes разрешены
только при совпадении environment root, sandbox marker и отсутствии `.git`.
Все четыре direct working-checkout запуска возвращают REFUSED (даже при подставленном
matching root); author interaction Resource SHA не меняются. Autoload изолируется
до `_ready`, в том числе при отказе. Scene/save writes — уникальный
`user://ember-tests/`, native content/store mutations — disposable `res://`.
ItemCatalog и ShopCatalog native-only; current coin/items/icons копируются,
synthetic shops создаются native. Empty compatibility JSON и fixture wallet
больше не нужны; остальные catalog domains этим не закрыты.
SVG растеризуются из исходных файлов в held process-local ImageTexture aliases:
asset pixels используются без рабочего import cache; это не проверка export/import.

Четыре gates PASS без ERROR; native content source SHA и скопированные shared
inputs после runtime неизменны. В копиях намеренно удвоенная награда, отсутствующий
completion flag и неверный marker clearance дают ожидаемый FAIL без SCRIPT ERROR.
Related map_transition/combat_encounter_transition/combat_defeat_retry/pause_menu/
party_save_v2 и isolated save/chest PASS. 887 защищённых файлов сохранили SHA;
четыре исходных gates совпадают с проверенным content archive. Новая ручная
Forward+/мышь/клавиатура/длительный restart не проводились и остаются OPEN.

Native item/catalog gate — `python tools/run_item_resource_test.py`:

- seven current items (six existing + lossless coin), six native pixel icons;
- missing/poisoned item JSON не меняет definitions/IDs/owners/icons/pixels, retired
  и invalid IDs не разрешаются; coin/icons Dictionaries равны frozen legacy source;
- ItemEditor create/edit/cancel/validation, embedded shop editor, save/Undo/Redo,
  runtime healing/sell price/reopen используют один ItemCatalog и native owner;
- retired saved ID/count остаётся в inventory: unknown equipped item возвращается
  без усечения 250→251 до 99, load/re-save не добавляет его повторно;
- party/save v2 теперь guarded disposable gate на synthetic equipment; v1 с valid
  явным maxHp не читает stage JSON, HP ratio и exact backup сохранены;
- отдельный PCK содержит binary .res + .tres.remap; fresh source-free процесс
  разрешает все семь items/шесть icons, исходных .tres и sibling JOI нет. Это
  focused catalog gate, не full export/import или Forward+ acceptance;
- native mutations ограничены matching env root + marker + no .git. Direct item,
  pack writer и party/save working runs REFUSED; current source SHA неизменны.

Native item/editor/PCK и пять party gates PASS; четыре interactions, семь native
transition/combat regressions, save/chest и item/icon часть visual-library gate
PASS. В копиях fake missing-ID fallback, неверная icon source, retired-stack clamp
и потерянный editor Undo обнаруживаются без SCRIPT ERROR. Inspector/plugin/graph
routing roots parse PASS; 887 защищённых файлов сохранили SHA. General Python
по-прежнему имеет два прежних shader-string FAIL; manual icon picker/equip/heal/
shop/save restart/Forward+ OPEN. Остальные catalog fallbacks остаются отдельными.

Native shop gates — `python tools/run_shop_tests.py` (либо `--test <имя>`):

- `test_shop_resource.gd`: missing/poisoned shops JSON не меняет IDs/owner/source/
  definitions/prices; invalid IDs не разрешаются. Create/edit через настоящий
  ShopEditor/InspectorActions, embedded open_shop editor, validation missing item/
  duplicate listing, reorder/delete/finite checkbox projection/discard/Undo/Redo
  и Resource reopen сохраняют одного owner. Undo create не раскрывает legacy;
- `test_shop_persistence.gd`: trade price/wallet/count, finite decrement/return,
  last unit→zero→reject, broke/unsellable, infinite stock без persisted entry,
  isolated stock двух магазинов, прежняя full-stack clamp семантика. Save v2
  сохраняет inventory + раздельные остатки, включая zero и retired shop/item IDs;
  missing shop trade не мутирует progress. Listing/save schema и Economy/ExploreState
  этим shop cleanup не менялись; ShopStore/editor стали native-only;
- `test_shop_catalog_pack.gd`: binary Resources + remap в PCK, fresh source-free
  process разрешает два neutral shop IDs, цены и finite/infinite stock без source
  .tres/JSON/JOI. Native pack leaf общий с item PCK gate, source SHA неизменны;
- native writes — только matching environment root + marker + no .git; все три
  direct working runs REFUSED. Runner не копирует historical shops/cities/JOI;
  test shops/key создаются только в temporary res://, saves — unique user://;
- fake missing-ID fallback, lost stock decrement, missing editor Undo и неверный
  source-file-only remap lookup в отдельных копиях дают ожидаемый FAIL без
  SCRIPT ERROR. Shop/editor/economy/PCK gates, четыре interactions, пять party
  gates и item/editor/PCK regressions PASS. Native plugin/graph/Inspector roots
  parse PASS; author content и 887 защищённых файлов сохранили SHA. General
  Python имеет два прежних shader-string FAIL; ручной UI/Forward+/restart OPEN.

Native village_kiosk не переписан и не объявлен current content: найденные ссылки
принадлежат retired сцене/двум sbx actions, один listing — missing parlor_talisman.
Вывод этого Resource проводится вместе с content retirement (JOI Exit Plan).
Тесты общих механик больше не зависят от него; retired data не импортируется
ради PASS. Работающие runtime/catalog и экспорт-проверка здесь не заменяют
ручную визуальную/input приёмку новой карты.

Native action/dialogue gates — `python tools/run_story_tests.py` (либо `--test <имя>`):

- action_resource/vn_dialogue_resource: guarded native create/edit, Resource
  reopen, runtime queue/dialogue resolution, delete/restore/Undo/Redo и IDs/owner.
  Missing/poisoned JSON не разрешается, snapshots имеют только ID/native, старые
  legacy/legacy_text поля игнорируются без read/write/delete исходного JSON;
- dialogue_authoring: три native реплики, две сходящиеся choice branches, typed
  flag, card compiler/runtime parity, complex stage protection, editor bridge,
  roundtrip и Undo/Redo. Action-chain talk step принимает ID нового диалога;
- action_chain_authoring: saved native map/clean prop вместо fan_town. Action
  document + scene-owned Interact/shape в одной Undo operation, terminal map/order
  validation, remove-chain сохраняет Interact; Quest draft binding, objective
  bind/unbind, shared-chain clone и orphan removal сохранены с Undo/Redo;
- binary PCK: four neutral action/six dialogue Resources + .tres.remap доступны
  fresh source-free процессу без source .tres/JSON/JOI. Action-over-dialogue ID
  priority, queue order/typed flag и выбор второй ветки дают прежний результат;
- runner копирует shared code/items/icons/materials/marker SVG/fixed combat
  preloads, historical stories/cities/voxel libraries/JOI не копируются. Reference
  validation получает одну saved native res:// карту только после guard. Native
  mutations требуют matching env root + marker + no .git; пять direct working
  runs REFUSED, autoload изолируется до _ready. Save/data fixtures — unique user://;
- четыре authoring + PCK gates, четыре interactions, shop/editor/PCK, четыре native
  transitions/retry/pause regressions и editor routing roots parse PASS. Fake
  action/dialogue fallback и сломанный action/dialogue Undo в отдельных копиях
  обнаруживаются без SCRIPT ERROR. Source SHA/author catalogs и 887 защищённых
  файлов неизменны. General Python имеет два прежних shader-string FAIL;
- 13 author action/2 dialogue files сохранены, historical content не считается
  автоматически актуальным. VN image render/layers не менялись; native-only asset gates — ниже;
  full Graph/VN visual/input, Ctrl+S/reopen и общие G4/G5 остаются OPEN. Большой
  legacy graph_workspace suite получил только актуальные assertions отсутствия
  migration buttons; целиком detached/manual он этим срезом не принят.

Native VN assets — `python tools/run_vn_asset_tests.py`:

- Background/portrait import пишет только в guarded disposable project: env root,
  marker, no .git; autoload изолируется до _ready, sources/poison JSON — user://.
  Duplicate basename получает новый ID, missing source отклоняется. Native
  descriptor/image reopen, fresh metadata reload при held stale Resource PASS;
- art/portrait registry poison и absent JOI не влияют на каталог, relative native
  path не разрешается в старый pack. CPU SVG/JPG decoding и общий visual picker
  PASS; background inheritance, speaker-scoped keys и unknown saved ID сохранены;
- source-free PCK с .res/.tres.remap перечисляет два current backgrounds + один
  fixture и speaker/expression. Отдельный editor/import идёт только в временном
  checkout/cache; второй PCK исключает raw images и читает imported Texture2D
  remaps/.ctex. Это data/image-read gate, не визуальная приёмка Forward+;
- четыре working runs REFUSED; три mutations (legacy art fallback, relative pack
  path, сломанная .remap enumeration) обнаружены targeted gates без SCRIPT ERROR.
  Source SHA (21 story/VN и 887 защищённых файлов) неизменны;
- два авторских фона/images и пустой native portrait каталог сохранены. Историческая
  графика не импортируется ради прежних demo IDs. Native story gates повторены;
  общие G4/G5 и ручные Graph/VN import/preview, Undo/Redo, Save/Reopen OPEN.

Native voxel catalog — `python tools/run_native_voxel_tests.py`:

- Runner копирует 93 current native sources и три выбранных prop derivatives с
  declared dependencies; historical cities/JOI/editor cache не копируются. Native
  fixtures требуют env root + marker + no .git, autoload изолируется до _ready;
- Poison JSON и отсутствующий JOI не влияют на IDs/owner/definition/source paths/
  signature/runtime loading. Shelf metadata не раскрывает geometry channels;
  native crate/barrel дают прежние mesh bounds и collider. Standalone .res и
  source-free binary .res/.tres.remap PCK enumerate/preview PASS;
- Voxel visual library: native shelf metadata/scale/tags, scene-owned placement ID,
  transform, saved scene reopen PASS. Все copied source/derivative hashes сохранены;
- vox_fan_crate_stack нужен test_pier: existing importer дал exact visual/collision
  parity, сохранён один новый Resource; исходный material="wood" нормализуется в
  preflight в dictionary тем же способом, что importer, без изменения JSON.
  material_study_* — generated lab IDs, не candidates массового импорта;
- `python tools/run_voxel_migration_tests.py --verify-interruption`: JSON + VOX
  synthetic queue/batch, Undo/Redo, frozen legacy hashes и kill после native write
  PASS. Queue gate создаёт до импорта installed derivatives: Undo восстанавливает
  exact .tscn/mesh/shadow bytes, не пересобирает legacy source через runtime;
- Working native runs REFUSED; fake catalog/prefab fallback обнаруживаются без
  SCRIPT ERROR. Projection-cache regression и session/report/plugin parse PASS.
  573 author source/scene/prefab/material hashes и 887 baseline hashes неизменны;
- Ручной Forward+: Причал (ящики/бочка, внешний вид и столкновения), добавление
  native модели с полки, Canvas Undo/Redo, Save/Reopen остаются OPEN. Hydration,
  legacy editor paths и общие G4/G5 этим срезом не закрыты.

Native map startup — `python tools/run_map_startup_tests.py`:

- Saved small native map + poison legacy JSON с теми же entry/chest IDs, чужими
  kind/loot/targets и размерами 375×257. Обе старые hydration flags true: startup
  сохраняет scene-owned свойства, nested entry transform, сундук/one-time loot и
  native progress при reopen с недоступным pack. Saved fixture SHA неизменен;
- Empty authored scene с load_map spy не вызывает automatic reimport даже при
  доступном old map JSON. Saved footprint остаётся native; ZERO во время
  deserialization не подменяется JSON dimensions. Editor reimport отдельно;
- test_native_cutaway больше не требует agent_sandbox/roof JSON. Две saved volumes,
  одна вложенная: startup не удаляет Cutaways, Roof reference жив после reopen,
  repeated refresh не дублирует signal. Player entry/exit, 0.22s fade, transparency,
  preview и stable structural shadow PASS с poison/absent JSON. Per-frame loop
  не добавлен; native roof geometry задаётся saved Mesh/CollisionShape nodes;
- Runner копирует shared code/items/icons/materials/fixed combat preloads, не
  historical maps/voxel sources/prefabs/JOI. Root env + marker + no .git guard;
  autoload изолируется до _ready, scene/JSON writes только unique user://. Два
  direct working runs REFUSED; 713 author map/content/prefab/material SHA сохранены;
- Четыре negative controls в отдельных копиях: region hydration, JSON footprint,
  удаление saved Cutaways, automatic reimport дают ожидаемый FAIL без SCRIPT ERROR.
  Save/chest, four interactions, five party и map/battle/Retry/pause gates PASS;
- Ручной Forward+ остаётся OPEN: landscape_compact/F5, native region/spawn/chest,
  Save/Load/Reopen, saved cutaway reveal/input/render при наличии authored roof.
  Это не приёмка retired sandbox и не новая система рисования интерьеров. Legacy
  editor paths, content retirement и общий physical G4/G5 пока не закрыты.

Native editor dependencies — `python tools/run_native_editor_tests.py`:

- Synthetic native shape/source/prefab создаются только в guarded disposable
  project. Poisoned JOI model/map и absent pack: native object open, detached draft
  discard, palette save/reopen, full Undo/Redo, catalog rebuild PASS. Missing source
  при наличии старого JSON отклоняется без создания .tres/изменения готового mesh;
- Store.owner/Report.build native-only; selector берёт размеры из visual_surface,
  а при его отсутствии отказывает вместо восстановления из map JSON. Plugin
  routing использует тот же map owner; новый editor/renderer/schema не появляется;
- Report/dashboard tests используют нейтральный fixture, проверяют sums/rows,
  missing derived status, stable ID/search/attention и user:// JSON export/reopen.
  Legacy owner/city batches/import/preflight controls отсутствуют. Собственные
  JSON-отчёты/cache manifests нынешнего Ember сохраняются;
- Shelf popup сохраняет native action IDs 0/2/3, удаляет legacy action 1. ToolsDock
  и plugin не имеют old reimport/JSON/VOX/migration controls/forwarding. Model,
  interaction, generation и scene refresh callbacks сохранены;
- Три direct working native runs REFUSED; fake object/Store/report/selection
  fallbacks дают ожидаемый FAIL без SCRIPT ERROR. 713 author map/content/prefab/
  material SHA неизменны. Related scene refresh Undo/Redo, story/voxel binary PCK,
  explicit offline import queue/batch/forced interruption PASS;
- Editor/import smoke запускается только в отдельном checkout/cache с включёнными
  Ember Import и Surface Canvas plugins, без JOI/city maps/author voxel sources.
  Parse/enter/exit PASS; это не ручная UI приёмка. Forward+: Surface открыть/выбрать
  область, объект/полка/Canvas Save/Cancel/Undo/Redo/Reopen и native diagnostics OPEN;
- Старые loader/EmberPack/offline import helpers ещё физически есть. Explicit
  offline migration eligibility теперь отдельный API; обычный owner не читает JSON.
  Physical/export G4/G5, remaining old scene references и city retirement OPEN.

Incoming city references: `python tools/test_retired_city_references.py`
сканирует active scripts/addons/current scenes/content/prefabs, включая строковые
пути внутри binary Resources. Исключения: семь retired scenes,
save compatibility registry, historical semanticOwner. Retired offline batch
module теперь отсутствует; его возвращение в addons вызывает FAIL.
Три negative controls: current scene destination, action targetMapId, active
preload offline module. Static PASS не доказывает произвольные dynamic paths.
Две unused action Resources с agent_sandbox target выведены из каталога после
exact-byte SHA/CRC supplemental ZIP; 11 оставшихся реальных Resources читаются
через native Catalog без retired targets. Native editor report/dashboard и
save/transition/encounter/defeat gates PASS. Manual Forward+ OPEN; historical
смешанные tests перенесены ниже; семь сцен выведены отдельным срезом. Shared derivatives сохраняются.

City-only test/tool retirement: 11 scripts + 11 UID сохранены exact-byte SHA/CRC
в supplemental retired-city-tools-2026-10-11.zip и выведены из checkout. Retired:
party captures (native runner captures остаются), fan_town Surface importer/profile/
projection gates, ready batch importer/parity/native gates, stale prefab profile,
sandbox native batch и offline VoxelBatches. Native editor/party/voxel regression
gates PASS; author scenes/content/prefabs/materials неизменны. Mixed Inspector,
Graph, scene round-trip, Surface sculpt/physics/perf, shapes/diorama/rebuild и
test_vox_axes.py оставлены: их general assertions нельзя удалить вместе с картой.
Перенос Inspector/Graph/sculpt/scene/physics выполнен ниже; остальные OPEN.
Save compatibility tests с retired IDs остаются и не требуют старых файлов сцен.

Mixed native editor gates: `python tools/run_mixed_editor_tests.py` (или --test)
запускает 10 сохранённых tests на generated native scenes/models/dialogues/quests/
shops/VN PNG в guarded disposable проекте. Исторические карты, native авторские
voxel sources и JOI не копируются; autoload saves изолируются до _ready.
- Inspector model/panel/actions: owner/components, source/stale signature,
  references/missing entry, derived light, UI/signals/20 lifecycles, add/edit/remove
  Undo/Redo и owned Interact/Shape save/reopen PASS.
- Scene round-trip/standalone/quest: duplicate IDs/transforms/Interact, authored
  sibling survival, typed flag gates/bounds, resource+binding Undo, journal и
  sequential combat counters PASS. Source map/model hashes сохраняются.
- Graph/map picker: branching ports/validation, duplicate/clipboard/internal ID
  remap, frame/group/view state, draft Undo, primary Save, quest events/flow,
  staged actor metadata и shared-cache live VN preview PASS; synthetic content
  сохраняет формы документов, которые нужны assertions. Duplicate layout
  проверяется относительно исходной позиции, а не координат исторического графа.
- Sculpt: прежние color/material/relief/smoothing/ramp/storage/selection/stroke
  Undo/Redo/save gates PASS. Missing native Surface не получает legacy JSON grid.
- Physics: synthetic 24x24 blocks, 16 density, 32 height; сохранённый explicit
  .tscn→Surface link, stale async snapshot restart, 36 collision chunks,
  navigation and PhysicsServer ray, authored flags save/reopen PASS.
- Negative controls: skipped Inspector Undo и zero Graph duplicate offset
  вызывают controlled FAIL; missing disposable guard REFUSED без native writes.
  Source map/model SHA и frozen shared items/materials контролируются.
Manual input/125% UI остаётся OPEN. Остальные gates перенесены ниже.

Remaining native gates: run_mixed_editor_tests.py включает 15 tests.
- Prefab rebuild: generated opaque+transparent lamp/native source + saved map;
  first ArrayMesh install keeps cache identity, existing rebuild preserves UID,
  bytes/timestamps, instance mesh/physical footprint, alpha shader/vertex alpha
  и placement transforms. PASS без исторических моделей/карт.
- Large Surface profile: 24x24 blocks/16 density/32 height; generated stepped
  fill layers provide 40-cell dry/wet lines, object context saved separately.
  Snapshot, independent column heights, chunks/selection/group filters,
  validation and save/reopen PASS; measurements describe synthetic CPU inputs.
  test_native_perf_fixture.gd validates dimensions/channels/strokes/context and
  parses both preserved A/B diagnostics. Long visible A/B runs остаются OPEN:
  run_remaining_editor_tests.py --forward qa_voxel_editor_edit_cost.gd /
  qa_voxel_editor_performance_ab.gd. Current scene needs no author Pier.
- Diorama: saved synthetic day/night scenes, constructors vs canonical material,
  authored environment/Sun/Moon SHA/fields, repeated apply, inactive watcher,
  clear/reentry/reopen PASS. Water checks follow current native Material fields,
  not superseded accepted-look numbers. --forward test_diorama_materials.gd
  passes actual Forward+ pixel idempotence, exact clear, automatic Sun changes
  and pack/reopen rendering; 30 FPS cap, no author scene.
- Shapes: python tools/run_remaining_editor_tests.py imports only in a disposable
  project, then runs real Forward+ EditorPlugin at 1600x900/30 FPS. Empty shape,
  first floor/ray/paint/collider, save/reopen, board form/footer bounds, two
  generated maps, canvas growth, inline create callback, cancel and plugin unload
  PASS. Captures inspected; live author input/125% UI still OPEN. Headless
  renderer is not used to claim pixel/UI acceptance.
- Python test_vox_axes.py: exact old version archived; content-specific inventory/
  lantern/tree/city JSON checks retired. General native/static contracts remain,
  include expansion/comment removal checks current shared light math. Generated
  asymmetric VOX size/cells/palette/Z-up -> Y-up PASS without skip/JOI. Separate
  test_vox_axes_native.gd passes real VoxParser/VoxMesher/Resource occupancy/source
  SHA parity; wrong mapping in a copied leaf triggers controlled FAIL.
711 author scenes/content/prefabs/materials remained byte-identical. Static city
reference gate now covers these tests too. Old IDs remain only compatibility
fixtures/registry; scene removal выполнен ниже, полный G4/G5 OPEN.

City scene retirement: семь .tscn отсутствуют физически. Свежий supplemental
архив содержит 998 current payloads/owners; все SHA и ZIP CRC проверены до
удаления. Старые сцены отличались от исходного архива после controller cleanup.
Удалены только fan_town + house/inn/mage/smith и обе agent_sandbox; source hash
gate подтверждает неизменность остальных 704 maps/content/prefabs/materials.
Shared barrel/crate_stack и все прочие модели/деривативы/shops/actions оставлены.
Resource retirement требует отдельной dynamic/binary/catalog сверки.
- test_retired_city_references.py: отсутствие active links и retired files PASS;
  восстановленный в temporary fixture fan_town.tscn вызывает controlled FAIL.
- Native map startup/cutaway, save destination/v1/v2/backup, pause menu, map
  transition, combat encounter/defeat Retry и native editor/report/dashboard
  runners PASS без копирования старых городов. Python axis/static PASS.
- F5 остаётся landscape_compact. Manual F5/old Save Load → native вход с
  прогрессом и последующий Save/Reopen OPEN. Рабочий editor не перезапускался.
  Полный physical/export G4/G5 этим не закрыт.

Retired content catalogs: `python tools/run_retired_content_test.py` копирует
текущие native data в disposable project, без author scenes/JOI. 13 retired
Resources удалены после проверки exact copies в refreshed archive. Actual
catalogs: 2 combat actions/2 dialogues, 0 shop/quest; current battle queue
preserves colored_crossing_intro -> colored_crossing_demo. Shared barrel/crate
sources разрешаются, retired canonical Surfaces отсутствуют. Save round-trip
сохраняет old flags/stock/unknown item counts и source SHA, retired quest не
появляется в journal/shop_view пустой. Frozen input hashes PASS.
Graph lifecycle перенесён на MixedFixture: 3 mount/unmount, same-frame deferred
frame retirement, focused quest и отсутствие orphan growth PASS; now 16 mixed
gates. Existing story authoring/PCK, shop/create/economy/PCK и save/transition/
combat gates PASS. Static Resource resurrection/incoming shop negative controls
PASS. Остальные 691 map/content/prefab/material files и все 93 модели неизменны.
Current battle introduction: renamed sandbox_notice_talk → colored_crossing_intro
с прежним Resource UID; две реплики о переправе заменяют sandbox directions.
Actual catalog gate проверяет отсутствие старого ID, порядок talk/start_battle,
две dialogue остановки без ранней записи прогресса, автоматический end с точным
new_flag=true, публикацию через EmberInteractionUi и save/load этого флага вместе
с историческими flags/stock/items. Ручной диалог → бой, F5/Load/full G4/G5 OPEN.

Save destinations перед city retirement: `python tools/run_save_destination_tests.py`
проверяет семь retired IDs, доступную retired scene и missing map → native вход
landscape_compact; unknown items/counts, flags/chests/party и original v2 SHA.
V1 migration сохраняет исходный файл и exact recovery backup; active native map
сохраняет XYZ. Реальное pause menu проходит cross-map load/native spawn;
при недоступном default сцена, пауза, inventory, slot и pending не меняются.
Четыре negative controls обнаруживают retired scene reuse, потерю entry flag,
преждевременный v1 resolve и adopt до preflight. Все PASS в disposable projects.
Связанные pause/map/encounter/defeat gates PASS; party и progress/chest PASS.
Ручная приёмка OPEN: F5, старый Save/Load → вход новой карты с прежним прогрессом,
Save/Reopen нового положения и обычный Load текущей карты. Старые сцены выведены.

Общие bag/health/party gates запускаются через `python tools/run_party_tests.py`
(либо `--test <имя>`): `test_inventory_equipment.gd`, `test_health_consumables.gd`,
`test_party_followers.gd`, `test_defeat_respawn.gd`, `test_party_save_v2.gd`. Сохранённая/переоткрытая native
карта принадлежит shared exploration fixture; реальные ExploreScene/MapLoader/
Player/InventoryUI/InteractionUI/Followers и autoload ExploreState остаются owners.
Synthetic weapon_jrpg (atk 14), weapon_arena (atk 10), body armor (def 8)
создаются только в disposable native item catalog; coin/consumables и combat units
берутся из текущих native Resources. Historical scenes/models/prefabs/JOI и
рабочий editor cache не копируются. Item reader не требует JSON; current icons
также копируются native. Полный G4/G5 остальных доменов этим не закрыт.

Inventory сохраняет двусторонние equip/unequip/stat/slot assertions, strategy
explicit save, active/inactive guards, выбор героев Q/E и блокировку движения.
Живое меню экипирует настоящего progress owner; equipment/counts переживают save
reopen. Health сохраняет armor mitigation, heal/clamp/full-HP consumption, failed
use immutability, текущий HP при save/reopen без derived maxHp; H action проходит
через реальный Player и autoload, проверяется HUD. Debug damage 30 задаётся только
health fixture. Defeat/respawn сохраняет lethal clamp, defeat HUD/input lock,
возврат в native spawn/full HP и inventory/equipment/flags.

Followers сохраняет block-scale/collision, четыре героя с одним CharacterBody,
Tab/leader HUD/targeted damage, formation spread и ordered train trail, solo/pair
и roster changes без phantom companions. Исходный счётчик progress сигналов в
lambda теперь использует общий Dictionary: прежний scalar capture не давал
надёжно проверить fan-out. Намеренный лишний progress emit теперь вызывает FAIL.
Для малого native ground тот же train path (104 шага по 0.5) начинается внутри
карты; perf bounds (40 toggles/leader switches) сохранены.

Все четыре gates PASS без ERROR; saved map/item source SHA и copied current
items/combat/materials неизменны. Четыре working direct runs REFUSED даже с matching
root; author content SHA сохранены, autoload изолируется до _ready. Native writes
требуют environment root + sandbox marker + отсутствие .git, scene/save writes —
unique user://ember-tests. Неверный atk, выключенная armor mitigation, phantom
followers и noisy mode progress в отдельных копиях дают ожидаемый FAIL без
SCRIPT ERROR. Четыре interaction gates и шесть save/transition regressions PASS;
887 защищённых файлов сохранили SHA, исходные четыре tests есть в content archive.
Общий Python static scan снова имеет только два прежних shader-string FAIL:
устаревшие route/H-probe strings заменены действующими native contract labels.

Capture modes сохранены через runner: `python tools/run_party_tests.py --visual`
для сумки и `--capture-active` для пары в мире/сумке (Forward+, disposable project,
PNG в user://). В этом срезе новый render/capture/manual input не проводился;
ручные Tab/Q/E/H, оба строя, лечение/equip, defeat/respawn и save/reopen остаются OPEN.

Основные gates:

- `tools/test_progress_restore.gd` через `python tools/run_progress_restore_test.py`;
- `test_camera_relative_movement.gd`;
- `test_party_progression.gd`;
- party/save v2, inventory/equipment, health/consumables, followers и defeat/respawn — через party runner;
- `test_map_transition.gd`; talk/shop/action/launch/quest — через interaction runner;
- `test_explore_pause_menu.gd`;
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

`tools/test_combat_defeat_retry.gd` использует saved/reopened native map через общий
exploration fixture helper вместо `agent_sandbox`. До autoload `_ready` изолируются
storage/restore; только после setup включаются реальные test-owned manual/autosave
записи. Wallet/items/icons читаются native-only без item JSON; map/model JSON,
старые города и sibling JOI не нужны. Source PackedScene удерживается до конца теста,
scene writes идут только в уникальный `user://ember-tests/`; SHA scene после runtime
не меняется. Production Combat Lab/Encounter/Battlefield/save owner и visual capture
режимы сохранены, gameplay код этим cleanup не менялся.

Сохранены все mechanics/modal/focus/corrupt-load/pair Retry assertions. Persistent
party/inventory/flags теперь сравниваются с копией до defeated attempt, а manual и
autosave содержат разные позиции: загрузка через настоящие UI buttons возвращает
правильные saved XZ вместе с HP/MP/inventory/flags и очищает active handoff.
Тест PASS также в disposable code-only проекте без семи городов, voxel libraries,
prefabs, sibling JOI и editor/import cache. Копируются code/shaders/materials,
native items/combat, Combat Lab/native arena и `colored_crossing_victory.tres`
(Encounter validation требует native victory action даже на defeat route).
В отдельной копии reused Retry seed и подмена saved spawn стартовым дают ожидаемый
FAIL без ERROR/SCRIPT ERROR; второй control ловит обе manual/autosave позиции.
Related map_transition/combat_encounter_transition/combat_result_bridge/party_save_v2/
explore_pause_menu и isolated save/chest PASS. 887 защищённых файлов сохранили SHA;
исходный старый Retry gate совпадает с версией в проверенном content archive.
Новая ручная Forward+ приёмка не проводилась; прежняя игровая приёмка ниже сохраняется.

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
Forward+ fixture проверил создание, force rebuild нового
пустого native ID, настоящий Canvas mouse/ray first-voxel Save, editor scene Save,
Undo/Redo/reopen и создание доски 16×2×32. Functional assertions PASS.
UI теперь проверяется `editor_test_voxel_shape_dock.gd` ниже; прежний helper
адаптирован к dock/нижнему preview и остаётся отдельным Canvas lifecycle fixture.
Автоматический выход иногда по-прежнему даёт
absolute get_node ERROR/scan-aborted после functional PASS — старый editor teardown
долг отмечается отдельно, весь lifecycle не объявляется чистым.

UI 2026-10-07: «+ Форма» → параметры в `Ember · Мир`, preview в нижней
«Новая форма», Create/Cancel закреплены. `test_voxel_shape_dock` PASS:
302 px/font20, четыре типа, no-files/no-instance preview, collapse, invalidate,
guard direct stale commit, Cancel, prepared==installed, Create/Undo/Redo/Save-Reopen,
large acknowledgement/reset. `test_voxel_shapes`, merge, object_split,
primitive_conversion и object_brush PASS; legacy modal subclasses остаются работоспособны.
`editor_test_voxel_shape_dock` PASS в disposable checkout с Surface Canvas plugin,
Forward+ 1600×900/125%: панели внутри shell, pinned footer, numeric Enter invalidation,
repeat/camera/no brush/collapse/dirty guards, Create открывает прежний Canvas,
один Undo/Redo и Save-Reopen, Cancel/no-files, empty floor→first voxel→Save/collider,
возврат к рельефу/scene change, terrain SHA/built tiles неизменны. Captures — user://,
чтобы PNG не пересекались с native asset scan. Живое удобство, авторский F6 и
полный shell 1280/125% OPEN; склейка/конверсия/разрезание используют общий dock,
их текущие gates — в соответствующих разделах.
После интеграции `editor_test_voxel_placement_dock` и `editor_test_compact_map_dock`
PASS: прежние параметры, guards, отмена и shared-dock переходы сохраняются.

Ручной gate: открыть 3D-сцену → «+ Форма» или «Проект / Инструменты / Ember:
Новая voxel-форма…» → справа параметры/снизу preview.
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
followers запускается через `python tools/run_party_tests.py --capture-active`,
`test_combat_defeat_retry.gd` — с `-- --capture-active` (обычный Forward+,
fixture saves, PNG в unique `user://ember-tests`). Captures не заменяют ручную input-приёмку.

## Migration gates

### G1/G2 — content ownership

- `tools/test_content_migration_report.gd` и
  `test_content_migration_dashboard.gd` остаются read-only;
- `test_migration_workflow_layout.gd` проверяет bounded editor layout;
- `test_voxel_migration_queue.gd` и `test_voxel_migration_batch.gd` запускаются
  через `python tools/run_voxel_migration_tests.py --verify-interruption`.
  Runner создаёт отдельный временный проект с искусственными JSON/VOX моделями;
  проверяются migration/Resources/prefab, одна batch Undo/Redo-операция и hashes
  frozen fixtures. Дополнительный child принудительно завершается после записи,
  до Undo/cleanup. Прямой `--script` в рабочем проекте отказывает до mutation.
  Авторские voxel Resources/prefabs, материалы и sibling JOI не копируются;
  working editor/cache не импортируется и не используется как write target.
  Эти gates проверяют механизм переноса, а не parity настоящей партии;
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
3. каждый `tools/test_*.gd` отдельным headless-процессом; mutation queue/batch
   миграции — только через изолированный runner из Migration gates;
4. повтор targeted suites после любого исправления, найденного полным прогоном;
5. обычный Forward+ на изменённых сценах;
6. ручная приёмка пользователя, если она входит в Task Contract;
7. обновлённые GDD/handoff/`EMBER_NOW.md` без журнала промежуточных версий.

Если обязательный gate недоступен, результат помечается `degraded`: указывается
точная причина, что уже доказано и какое ручное действие осталось. Ошибка в
неизменённой подсистеме не скрывается, но отделяется от regressions текущего
среза доказательством baseline.
## Гранёный рельеф — 13 сентября2026 (user visual accepted; runtime walk open)

User accepted2026-09-13: «неплохо, мне нравится», reported all checks done.
Editor visual acceptance recorded; actual player walk over facets was not
explicitly confirmed, so physics/manual runtime gate is not silently closed.
Git checkpoint repeat:15 current generation/sculpt/brush suites +test_test_pier,
test_voxel_prefab_rebuild,test_scene_edit_roundtrip PASS (18 total). Logs retained
as Temp/*-generation-checkpoint.log; fan_town UID fallback warnings remain.

test_voxel_faceted_relief PASS: deterministic seeded Voronoi planes, tilt/width/
depth controls, width0 disables grooves, directional and amplitude limits,
linear planes +constant flat heights inside brush plateau, edge clipping,
coarse/exact segment density equivalence and no revisit accumulation.
Workspace actual initial surface picking → existing generative segment route →
commit, one Undo/Redo, canonical save/reopen, cancel/discard, region clipping;
editor-only profile normalize/clamp/export/import/tool rail restoration without
dirtying source. Fixtures user://, no authored maps/models rewritten.
Five related suites PASS: voxel_surface_sculpt, surface_canvas_workflow,
voxel_workshop_layout, voxel_tools_backend, surface_height_slice.
An initial suite list named nonexistent test_voxel_brush_profiles; runner
stopped there, corrected final list includes the actual6 suites. No test invented.

Native --script tools/test_voxel_faceted_relief.gd --rendering-method forward_plus
only in disposable ember-generation-smoke-*; facet-native-ui.log EXIT0/PASS,
Vulkan Forward+ RTX5070. user://faceted_relief_native.png personally viewed;
labels unclipped at1440×900, plateau planes/voxel stairs/grooves visible.
First art capture used compatibility _activate_tool_id (forces buildup);
fixture now restores the actual tool rail profile and checks generator mode.
First prefix controls clipped text; explicit minimum widths fixed before final capture.
Radius32 math~80–90ms; density32 4×4 with baseline heightfield~190–207ms.
These are not complete runtime input/remesh/physics performance acceptance.

Manual: ordinary Canvas → Рельеф → Генератор → Характер · грани; selected colour,
scale16/32, height8/12, tilt0/60, width0/1/2, depth0/3/6 and variant button.
Draw actual continuous/repeated/adjacent strokes on a disposable map, check
recognisable broad planes, boundaries/masks, Undo/Redo, save/reopen/discard and
runtime physical support. No cosmic colour/glass/glow/low-poly shader implemented.

## Кристаллы и лёд — 13 сентября2026 (manual art acceptance open)

No-platform/large-size follow-up: extended crystal suite PASS. New presets have
crystal_base_enabled=false; missing=true reproduces old voxels. Toggle changes
footprint; disabled size is inert; disjoint8 prisms retain >2x central volume.
All rock types build at32×128×32; crystal64×128×64,256×32×64,32×256×32 validate.
Density-aware limits, >64 preview limit1, over-budget256³ rejected pre-allocation;
over-budget candidate Apply leaves source unchanged and reports524288 limit.
Studio bool+size gating/Undo, candidate large draft+Apply/neighbour reload,
source/recipe/preset save/reopen80-voxel height and saved Canvas toggle/Undo/discard.
Crystal measured extended forms about0.13–0.33с before remesh (not a general upper bound).
8 related regressions PASS; native follow-up crystal-footing-verify.log PASS;
fixture exercises footing Apply/Undo/Redo and saved large128-height
preparation/remesh/discard. No-platform capture personally viewed.

tools/test_voxel_crystal_objects.gd PASS: all morphology controls affect occupancy
for pointed/broken/ice presets; surface seed does not change form; source remains
opaque/no glow; extreme3³/count8/width20/lean100/base0/chips100 at density16/32;
normalization,64³/8 prisms build~948ms before remesh +bounded working set2.
Common studio type selector shows/hides cluster settings +Undo; count input
Undo/Redo; batch, candidate draft/discard/isolated Apply +exact geometry Undo/Redo;
library publication exact palette/voxels and all recipe params reopen;
custom preset, canonical saved reload; saved Canvas controls/preview/draft
Undo/Redo/discard with source SHA unchanged. Fixtures only user://.
Expanded rock suite:9 presets each8/8 diverse/repeatable/connected/grounded/schema;
old voxel_generator/generation_session/generator_editing/workshop_generator_save/
object_library_layout/object_brush/stamp PASS (9 total suites including crystals).

Existing native editor_test_voxel_generation.gd -- --rocks-only --crystals
only in disposable ember-generation-smoke-*; initial PASS: actual three presets,
batch distinct seeds, dimensions/chips +cluster count discard/lean Apply/Undo/Redo,
publication/full recipe reopen, saved Canvas cluster controls/discard/comparison.
Capture user://generation_crystals_native.png personally viewed (initial and final forms).
Art tune increases lean and lowers ice footing; first retest ended at stage=ready
without completion/error in crystals-native-accept.log; not counted as PASS.
Initial successful log crystals-native.log; final retest crystals-native-verify.log
completed editor_test_voxel_rock_objects: PASS after art tune.
Existing isolated UID duplicate/fallback/scan-aborted warnings remain.
Initial development parse/type errors were fixed before targeted PASS; no author
assets/scenes edited and no headless --editor in main checkout.

Manual next: Генерация → Камни → three crystal/ice presets; different seeds,
count/width/variation/lean/tips/base, ensure recognisable groups not identical
spikes; publish → scene → Canvas/recipe/save/reopen/Undo/discard. Shader/glass/glow
not implemented; faceted landscape has its separate agreed slice above.

## Оформление камней — 13 сентября2026 (ручная визуальная приёмка открыта)

Refinement gates: old moss missing fields reproduces12% highlight; strength0
produces no index6 and palette5==6; explicit accent colour at100 exact,25 lerp;
new style1 repeat determinism, irregularity/branching/style visible effect with
exact occupancy; vein controls do not change accepted layer indices. Max64³
branched dressing separately measured (ROCK_64_VEIN_BUILD_MS). Studio/candidate/
saved Canvas new fields +disabled accent colour at0, explicit same-mode vein
upgrade, style Undo/Redo/discard, saved accent exact preview and recipe reopen.
Related suites are the same seven below. Native --rocks-only --rock-surfaces
adds actual moss accent colour/zero/Undo/Redo and vein irregularity Apply/Undo;
logs rocks-refine-native.log /rocks-refine-final.log /rocks-refine-accept.log
in isolated Temp project.8 suites PASS; final rock log
Temp/test_voxel_rock_objects-refinement-accept.log: plain796ms, layers+moss1180ms,
new vein+moss1399ms before remesh. Branch count leaves main phase/pockets fixed.
New screenshot remains generation_rock_surfaces_native.png; warnings same cache.
Manual next: compare new presets, set moss accent0 then arbitrary accent colour,
adjust vein width/irregularity/branches +surface_seed, save/reopen. User accepted
layers/ice-like slabs, new moss/vein acceptance pending. No shader change.

Expanded tools/test_voxel_rock_objects.gd PASS: шесть presets (три plain, три
оформленных),8/8 distinct на каждый preset; bare-vs-dressed occupancy exact,
channels unchanged, deterministic independent surface_seed; patches/layers/vein/
moss/combinations, every surface parameter effect, moss excludes bottom,
normalization/tiny extreme3³ density16/32, legacy body preserved. Max64³ build
около0.8с plain /1.2с dressing (не полный mesh/publish benchmark).
Общий studio: disabled inert layer controls, isolated surface draft/Apply/
Undo/Redo without shape/other candidate change; chosen publication +full recipe
and exact palette/voxel save/reopen; custom preset, canonical saved reload;
saved Canvas surface fields/draft Undo/Redo/discard/preview; derived mesh colours
match canonical palette within byte quantization<=1/255,>=3 visible tints.
Fixture initial exact-float mesh assertion failed because ArrayMesh quantizes
vertex colors; fixed tolerance without changing renderer or palette. Final probe
prints max palette error. Fixtures only user://, author maps unchanged.

Related PASS: voxel_generator, generation_session, generator_editing,
workshop_generator_save, object_library_layout, object_brush, voxel_stamp.
Native existing editor_test_voxel_generation.gd -- --rocks-only --rock-surfaces
in Temp/ember-generation-smoke-20260912 PASS: actual studio/provider/presets,
three dressed families, distinct shape seeds, independent surface Apply +exact
occupancy, Undo/Redo, publication/reopen, saved contextual discard, comparison,
return to trees retains six records. Personally viewed Forward+ capture:
user://generation_rock_surfaces_native.png (moss/vein/layered plate).
Logs rocks-surfaces-native.log and rocks-surfaces-final.log in isolated project.
Existing UID duplicate/fallback +scan-aborted-on-exit warnings; not clean lifecycle.

Manual: библиотека → Генерация → Камни → presets «Оформление»; оценить рисунок
на разных размерах/сидах и в свете карты. Настроить каждый слой отдельно и вместе;
менять только surface_seed, силуэт должен остаться; Apply/Undo/Redo/discard;
сохранить выбранный → библиотека/сцена → Canvas/рецепт → переоткрыть. Ручные
sculpt edits не должны быть перезаписаны recipe preview. Пользователь подтвердил
первый rock workflow «работает», не новую визуальную приёмку покрытия.

## Камни в мастерской генерации — 13 сентября2026 (первый workflow подтверждён)

`tools/test_voxel_rock_objects.gd` первоначальный PASS: три presets, old/new normalization bounds,
8/8 unique geometries на каждую форму, repeat determinism, connectivity,
ground contact, schema/palette и mesh vertex colors, measured max64³ build,
bounded candidate working set. Общий panel: provider/field rebuild, XYZ vector
input+Undo/Redo, batch, индивидуальный draft/discard/Apply+geometry Undo/Redo,
published color/dimensions/type/seed recipe reopen, custom preset без family/
structure, canonical saved reload, saved Canvas recipe exact preview без source
write (SHA), archive/favorites retain, provider-switch Undo/Redo, отказ в
cross-provider revision, legacy load без upgrade и explicit same-type opt-in v2.
Все fixtures в user://; авторские сцены/исходники не перезаписываются.
Related PASS: voxel_generator, generation_session, generator_editing,
workshop_generator_save, object_library_layout, object_brush, voxel_stamp.

Opt-in native editor fixture: `tools/editor_test_voxel_generation.gd`
с user arg `--rocks-only`, только в disposable ember-generation-smoke-*.
Vulkan Forward+ RTX5070 PASS: реальная library Generation button/главный plugin,
provider selector/presets, партии всех3 форм, distinct seeds, VectorField draft/
discard, individual Apply/Undo/Redo, publish+recipe reopen, comparison3 форм,
return to trees с сохранением6 archive records. Captures:
user://generation_rocks_native.png и generation_rocks_ui_native.png просмотрены.
Logs Temp/ember-generation-smoke-20260912/rocks-native*.log; есть старые UID
duplicate/fallback warnings и scan-aborted на exit. Не заявлять clean lifecycle.
64³ build около0.8с; >48 max2 candidates, otherwise4; cancel между candidates.

Manual gate: библиотека → «Генерация…» → «Камни» → каждый из3 presets;
сгенерировать несколько seeds и оценить узнаваемость форм/разнообразие.
Изменить XYZ, сколы, неровность, цвет → настройки партии и выбранного камня
независимы. Apply/Undo/Redo/discard; сохранить лучший в библиотеку, открыть Canvas,
вернуться к деревьям, найти тот же камень и расставить scene object brush.
Save/reopen карты — экземпляры/ориентация остаются; рецепт/пользовательский preset
сохраняет тип, XYZ, цвет, seed и параметры. Старый stamp recipe не мигрируется
при загрузке, явный выбор формы включает v2. Шейдеры/рисунок/кусты ещё вне среза.

## Scene object placement brush — 13 сентября2026 (ручная приёмка открыта)

Пользователь2026-09-13 проверил кисть в редакторе: «ок, работает».
Базовый workflow подтверждён; это не отдельное подтверждение каждого пункта
ниже. Save/reopen и полный набор переключений остаются ручными gates.

UI 2026-10-07: отдельная «Кисть объектов…» перенесена в `Ember · Мир`; внутри
режима мира используются те же controls категории «Объекты». Параметры
прокручиваются, Stop закреплён; камера/placement input остаются прежними.
`editor_test_object_brush_dock.gd` PASS native Forward+ в отдельном checkout:
1600×900/125%, весь dock внутри shell, shared controls/reopen/sync, 302 px/font20
и pinned footer; поле отменяет unfinished preview, настоящий click проходит
plugin route до physical picking/commit; preview совпадает, Undo/Redo/Save-Reopen
PASS. Stop/Esc/scene change и переход +Map/Cancel возвращают controls/toolbars;
не меняются исходный model, terrain file и built tiles. `editor_test_compact_map_dock`
после интеграции PASS. Exit выдаёт прежние QA shutdown/scan warnings;
zero-warning lifecycle не заявляется. Удобство автора и весь shell 1280/125% OPEN.

Headless `tools/test_voxel_object_brush.gd`: canonical fixture в user://,
фактический bottom pivot/scale/yaw/bury, transformed parent, preview ≠ scene edit,
preview excluded from PackedScene, unique batch IDs/scene owner, pointer-up batch,
sticky template, один Undo и Redo после смены контекста, save/reopen transforms,
source SHA unchanged, cancel/Esc/256 cap, event-independent spacing carry,
real elevated StaticBody ray и no-hit без y=0 fallback — PASS.
Related PASS: voxel_placement, placement_preview, object_library_layout,
object_library_updates, scene_assembly, object_split, object_canvas.
Library layout также проверяет отдельный brush signal с выбранным model ID.

Native editor probe в отдельном Temp/ember-generation-smoke-20260912:
Vulkan Forward+ RTX5070, plugin input route + native settings/SpinBox bindings,
hover/drag ghosts (до release ноль instances), pointer-up три instances на y=8,
sticky brush, настоящий EditorUndoRedoManager undo/redo, camera pass и Esc PASS.
Лог brush-native.log; user://object-brush-native-preview.png / commit.png
просмотрены. Это автоматический editor input/render fixture, не ручной мазок
на пользовательской карте. Disposable cache выдаёт UID duplicate/fallback
warnings и scan-aborted при выходе; zero-warning lifecycle не заявляется.

Ручной gate: библиотека → выбрать доску/камень/дерево → «Расставлять кистью…»;
в правой панели изменить шаг/Y/масштаб/заглубление → клик и мазок на земле,
затем на настиле; прокрутить параметры и проверить закреплённое выключение.
Объект больше не требуется выбирать повторно, preview соответствует result.
Ctrl+Z/Redo — весь мазок, Save/reopen — реальные экземпляры и их ориентация.
ПКМ/СКМ/Alt не расставляют объекты; Esc выключает. Начать мазок и уйти за
поверхность/окно — незавершённые ghosts исчезают без scene edits.
После выключения возвращается обычное выделение. Проверить выбор другого
шаблона, переключение Surface/Battlefield/Walk Surface tools и открытие Canvas.

### Кусты в общей мастерской2026-09-13

Agreed slice: bush v2 в существующем provider/studio, три крупных формы и
pixel-art/leaf clouds; без ягод, цветов, анимации или нового placement owner.
Missing generation_version сохраняет компактный v1 и его random sequence.
test_voxel_bush_objects — PASS headless и native Forward+ RTX5070 в disposable
Temp/ember-generation-smoke-20260912. Шесть form/style recipes, determinism,
различие occupancy по seed и неподвижная форма при diversity0, ground stems,
storage budget, заметные параметры, palette-only strength/detail/colour edits.
Настоящие UI bindings проверяют options values[1,3], batch, candidate Apply,
draft/discard, isolated neighbour, Undo/Redo, source+recipe+custom preset save,
reopen и saved generator editor. Assets только user://ember-tests, карты не меняются.
Native comparison: user://generation_bushes_native.png; это runtime render/UI
fixture, не ручная проверка кисти и полного input в рабочем Godot editor.

Ручной gate: Объекты → Генерация → Кусты; проверить три пресета с несколькими
сидами, оба режима, размер/пышность/уплощение. Цвета рисунка доступны отдельно,
strength0 возвращает только основной цвет. Сохранить выбранный куст, найти в
библиотеке, открыть его настройки, сохранить вариацию; Undo/Redo и reopen.
Расставить несколько кустов общей кистью на земле, проверить pivot/contact,
масштаб и вид из обычной игровой камеры. После этого закрыть визуальную приёмку.

Уточнение2026-09-13: первый визуал v2 отклонён. Новый согласованный шаг — только
базовый силуэт v3 без рисунка, не все формы. test_voxel_bush_silhouette PASS:
3seeds,6-connected geometry, широкая нижняя масса вместо заострённого низа,
one foliage colour, opt-in нового preset и неизменная репродукция старого v2.
BUSH v3 остаётся в общих source/recipe/preset/save/edit/history owners.
Native bush_objects --basic-silhouette в disposable Forward+ fixture PASS;
comparison user://generation_bush_basic_native.png: v2 слева, v3 дваseed справа,
одинаковые параметры размеров и отключённый рисунок. Полный UI roundtrip и
Undo/Redo покрываются bush_objects с новым default preset.
Ручной gate теперь сначала только «Кусты · Базовый силуэт · пробный»:
проверить широкое основание, неодинаковые пучки, небольшую пустоту у ветвей,
несколькоseed и вид со всех сторон. Не включать рисунок для приёмки формы.
Этот v3 также отклонён как «шапочки», его визуальный gate не закрыт приёмкой.
Следующая согласованная проба — v4, только «Кусты · Крупные листовые пучки · пробный»:
побеги от земли, плотный центр из перекрытий, крупные наклонённые внешние группы,
без общей юбки/купола. Старые v1–v3 воспроизводятся; другие presets остаются v2.
Восемь suites PASS: bush_silhouette, bush_objects, bush_generator, generator,
generator_editing, generation_session, workshop_generator_save, workshop_layout.
Silhouette проверяет пять seed × два режима, связность и normalized reproduction;
общий objects fixture — save/reopen/presets/Apply/discard/Undo/Redo.
Native --shoot-shrub Forward+ RTX5070 PASS; generation_bush_shoots_native.png:
v3 слева, v4 seeds73/391 справа. Рисунок0, одноцветный кадр не является
подтверждением читаемости объёма или ручного editor/input.
Ручной gate открыт: несколько seed, оба режима, вид со всех сторон и игровой
камеры, толщина внешних пучков, читаемость побегов и плотность центра; затем
save/reopen и кисть на карте. После явного принятия вернуться к рисунку и
другим формам, не раньше.

V4 впоследствии отвергнут пользователем как «монстр», приёмка не закрыта.
Новые references/approval: только базовый v5 cloud shrub с независимым основанием
и числом веток. Base_height0–32, высота листвы8–96, ветки1–12. Recipe/source/
preset/save/edit/history owners общие, v1–v4 load не обновляется автоматически.
Восемь bush/generator/session/workshop suites PASS; silhouette — пятьseed ×
два режима, сохранённый контур при подъёме, connectivity и крайние количества.
Objects fixture — base SpinBox binding/Undo/Redo, candidate height Apply,
source+recipe+custom preset roundtrip, saved height binding/Undo/discard.
Native --cloud-shrub Forward+ RTX5070 PASS, generation_bush_clouds_native.png:
два низких seed, основание16/12веток; max storage524288 и pure build≈0.49–0.55s.
Ручной gate теперь «Кусты · Облака листвы · пробный»: base0/2/16/32 и ветки1/3/12,
листва не растягивается при подъёме, нижний каркас расходится и поддерживает массы.
Проверить оба режима/пышность/край/цвета, вид со всех сторон и игровой камеры;
сохранить вариацию, reopen, Undo/Redo и кисть на карте. Ягоды/цветы вне scope.
Пользователь2026-09-13 подтвердил базовый визуал v5 («вот эти хорошие»):
cloud shape gate принят. Остальные крайние настройки и полный ручной
input/save/placement checklist не объявлять пройденными без подтверждения.

Следующий согласованный срез2026-09-13 реализован: низкий раскидистый и высокий
ветвистый на облачной основе, explicit v6; принятый базовый preset остаётся v5.
Восемь bush/generator/session/workshop suites PASS. Silhouette проверяет оба
v6 ×3seed ×2режима, exact normalized roundtrip, v2 distinction, base0/32 ×
ветки1/12, maximum524288/source validation/connectivity. Objects — реальные
studio type bindings/Undo и публикация/reopen/saved edit/height history/discard
обоих новых типов на user:// fixtures. Native --cloud-profiles Forward+
RTX5070 PASS; generation_bush_profiles_native.png — три пресета рядом.
Ручной gate двух v6 форм открыт: низкий широкий/высокий вытянутый характер,
несколько seed, оба режима, основание/ветки/пышность/край/цвета, вид со всех
сторон и игровой камеры; save/reopen/Undo/Redo и посадка кистью на карте.
Old recipes v1–v5 не мигрируют, ягоды/цветы/renderer work вне scope.
## Editor startup preparation gate — 2026-09-14

Accepted startup optimization contract: editor project opening, not F5/F6.
Native exclusive preparation Window waits for scan/import, stable restored
scenes, existing object catalog/preview queue and pending Surface projection.
No authored scene/model writes; existing SubViewport, Resources and cache owners.

PASS `--headless --path . --script res://tools/test_voxel_editor_preparation.gd`:
scan/import block catalog, catalog begins once after settling, previews block
release, error/timeout explicit continuation, shelf usable after early timeout,
window/plugin exit cancellation. Does not replace native input/visual acceptance.

PASS related `test_voxel_object_library_updates.gd` (publication, coalescing,
failed publication, dirty hidden reopening, clean cache reuse, source unchanged),
`test_voxel_object_library_layout.gd`, `test_voxel_visual_library.gd` (245 models,
selection/serialization fixture). PASS native Forward+ WITHOUT `--headless`:
`test_voxel_preview_renderer.gd` verifies real128px model pixels, prefab and source
branch without new/overwritten prefab, duplicate/cancel/requeue, in-flight cache
invalidation, invalid root, load failure followed by same-path repair and source
publication invalidation. A user://8MiB loading fixture checks renderer exit while
the resource is still loading, token disposal and another renderer's shared-path
pixels. Native preparation fixture checks compact error-window/continuation
button layout. The malformed user:// fixture intentionally logs parse
errors; final test PASS0. Fixtures removed, canonical files untouched.

Four disposable normal-editor runs with copied cache/eight restored tabs prepared
245 previews with0 failures. Final frame-queue run:27.975s from gate begin to ready;
actual plugin library-opening command3.531ms,queue0, cache245. Third run also
restores Objects selected. Second diagnostic completion incorrectly waited for
stale scan-progress fraction; third/fourth use actual scan/import APIs and DONE
SETTLED. This was a probe defect, not a stuck startup gate. Native Window snapshot
inspected. Old warmed main-thread load+instantiate max1.891s; first post-change
instrumented run request max0.117ms/instantiate max253.033ms. Full startup remains
long and main-thread engine restoration still blocks before ready. No general
FPS/memory/total startup guarantee. Original editor was not restarted, live MCP
unavailable, audit teardown warnings retained. Never headless editor in live tree.

Current manual gate OPEN: save current scenes/Canvas; close Godot; reopen project
normally. The first run after introducing persistent preview cache may prepare
all missing images; wait for completion. Close/reopen a second time without asset
changes: no Ember preparation Window should appear, and Objects should immediately
show cached thumbnails with working search/filter/selection/placement. Add or edit
one voxel object and reopen: only its thumbnail should regenerate, then subsequent
reopen should be quiet again. Scene Surface preparation remains independent and may
continue in the background. Headless `test_voxel_preview_disk_cache.gd` checks
cross-instance reuse, changed/new source, invalidation and damaged image;
`test_voxel_editor_preparation.gd` checks that a clean queue does not request the
modal window; `test_voxel_object_library_updates.gd` checks publication refresh.
Do not call the contract fully closed before normal Forward+ acceptance. Water
chunk implementation is recorded below; Save remains a separate audit.

## Wet Surface native terrain — 2026-09-14

Accepted first performance slice: existing native adapter composes opaque terrain
with unchanged Surface water/foam. Wet greedy terrain baked to complete-Surface
block coordinates, identity chunk visual; dry/slice native local transforms,
draft and stock fallback retained. Canvas and world/battle share the adapter.
No authored map/model writes, schema/shader/physics/prefab changes.

PASS `--headless --path . --script res://tools/test_native_surface_water.gd`:
offset shallow tint/level fill, exposed rock and cross-chunk cavity; water/foam
arrays equal stock, terrain face area per plane/axis/color equal despite greedy
triangulation/normal compression, Canvas/runtime shader space, bottom-only/slice,
missing-native caller fallback, source unchanged.
PASS native Forward+ same script without `--headless`, offscreen: frozen water/foam
under translated/rotated/scaled parent compare0different pixels,8171visible vs
empty control. UPDATE_ALWAYS + force_draw prevent false blank render acceptance.

Related PASS: surface_canvas_workflow, surface_height_slice, world_surface_projection
(also native Forward+), voxel_surface_sculpt, water_contact_boundaries,
voxel_cartoon_water (prefab collision/source/save/reopen), voxel_projection_cache,
voxel_tools_backend. Native Canvas water/slice captures inspected. Native
water_pattern_seams PASS: split0pixels, noise tears0, reflection jump0.00392.

Matched Forward+ old94ec785/new Canvas in same process, alternating order,
64×32×64 slab/dry and wet16×32×16 chunks,8repeats/7warm: wet median
16.975→6.173ms (2.75×), dry4.704→4.382ms. CPU work, not gameplay FPS.
Evidence: Temp/ember-addon-audit-20260914/WATER_RESULTS.md and comparison logs.

Manual acceptance OPEN, using the ordinary Forward+ editor/map:
1. Shore editing across chunk boundaries: water plane/foam/color/pattern unchanged.
2. Held sculpt draft→pointer-up exact mesh, bottom-only and height slice, no jump
   in terrain/water position when changing views or adding/removing water.
3. Undo/Redo, save/reopen and discard on a user-owned test copy.
4. F6: bank movement/physical surface and water contact/wake unchanged.
The live editor was not restarted. Startup gate manual acceptance remains separate;
Save/retained-memory implementation is recorded below.

## Object Save/Undo memory — 2026-09-14

Accepted slice: existing ObjectSession/ModelStore, immutable in-memory compressed
published source/prefab bytes for Undo assets. Repeated same-session old publication
reused only after path/source/prefab hash match; unknown baseline prepared fallback.
Independent geometry validation retained; node resource references, UIDs, scene/
prefab formats, history depth and staging lifetime unchanged. Shared transaction
handles generation and replay; UID header stream preserves body.

PASS headless test_voxel_save_snapshots: exact byte/hash/UID roundtrip, fresh cache/
SceneState path, prepared/replay second-rename rollback, corrupt payload rejected,
no failed event/snapshot, Undo after reopen/cache release, collider restore,
external live mutation guard,2MiB UTF8 body/two UID rewrites. Related object_canvas,
object_library_updates, shapes, scene_refresh, canvas_growth, scene_assembly and
canvas_context PASS. All fixture files outside authored assets.
PASS native Forward+ editor disposable copy: EditorUndoRedoManager shared save/
Undo/Redo, editable authored child/pose, scene save/reopen physical geometry,
fresh SceneState path and failure rollback. Copy-only canonical fixture dirs avoid
legacy/catalog lookup noise; inherited UID/teardown warnings retained.

One-process94ec785/current192×10×256 fixture,3Save per mode: warm mean4.999→3.967s,
cold6.508→5.489s, Undo3.674→2.030s, Redo3.679→2.074s; history delta166.65→85.01MiB
per repeated Save, snapshot≈1.28MiB. CPU/static memory, not FPS or OS/GPU memory.
History still retains real mesh/shape versions; no depth limit or format change.
Evidence: Temp/ember-addon-audit-20260914/SAVE_RESULTS.md.

Manual gate OPEN: ordinary Forward+ editor, representative object/test scene,
2–3Save then Undo/Redo; selected edit preserves sibling/shared ID semantics; shared
edit updates linked instances; authored pose/socket/materials unchanged; scene
save/reopen/discard and F6 collision. Save scenes/Canvas before any manual restart.
Agent did not stop/restart the original editor; startup/water acceptance remain separate.

## Startup wait / catalog metadata / bounded prefetch — 2026-09-14

Accepted next startup slice preserves Catalog/Visuals/PreviewRenderer/preparation
owners and canonical Resources. Native shelf metadata excludes dense geometry
conversion; default full definitions and legacy resolution unchanged. At most2
active/prefetched threaded tokens; same-path revisions must not join old tasks.
Existing single SubViewport, camera, ordering and revision/cache checks retained.

PASS targeted: test_voxel_visual_library (full-metadata parity, native channel
exclusion, legacy equality and scene roundtrip), object_library_updates, layout,
editor_preparation. Native test_voxel_preview_renderer: real prefab/source pixels,
bounded ahead window, cancellation drains every ahead token, requeue, pending
prefetch invalidation, no duplicate same-path revision load, renderer exit/task
disposal and shared-path survivor. Fixtures user://, no authored model writes.

Disposable native editor8 restored tabs/247 thumbnails: cap0/full projection
28.379/29.039s gate; chosen cap2/metadata24.301/22.729s. Mean18.1% less wait; repeat
29.039→22.729s, shelf0.421ms,pending0,failures0. Cap4 exploratory full-editor38.871s
discarded; its standalone timing does not describe current cap2. Warm desktop
copy measurements, not cold-cache/whole-startup/FPS or memory guarantees. Existing
UID/teardown diagnostics retained. Evidence SPEED_RESULTS.md in startup audit Temp.

Startup accepted2026-09-14: user «ок, работает» after normal project opening.
Publication/search/filter/lifecycle regression checks PASS automatically. Original
project not launched as an editor or restarted by the agent. Other gates separate.

## Generated-object exact preview / sparse rows — 2026-09-14

Accepted continuation after startup acceptance. Existing shared VoxMesher culling
skips entirely empty X-rows and hoists row index; original face order/occlusion/
palette/alpha/collider semantics preserved. No provider/recipe/Resource schema,
renderer/Creation/session/UI lifetime or persistent cache changes.

One-process alternating-order2 repeats ×5 latest types,128vox/cloud foliage/seed371:
exact prefab748–1487→431–1060ms by case means (29–44% less wait);10/10 exact
surface arrays/names and collider faces equal. Headless CPU fixture, not full
batch, source build, interactive native editor latency or FPS claim.

PASS: large_tree_object64/128/256, generation_session, generator_editing,
workshop_generator_save, projection_cache with sparse edges/slab crossings/alpha,
object_canvas, shapes, cartoon_water, world_surface_projection. user:// fixtures.
Native disposable editor full generation test PASS twice current +once baseline:
draft/apply/archive reload/comparison, publication/asset Undo/Redo, preset roundtrip,
scene save/reopen/discard, generate-similar and types. First current run crashed
after PASS on teardown; baseline and current repeat did not. Repeat previews
pending0 at quit. Cause unproven, failure trace retained; no general shutdown claim.
Evidence Temp/ember-addon-audit-20260914/GENERATOR_RESULTS.md.

Manual ACCEPTED2026-09-14: user «окей работает» after the requested workshop
check. Ordinary generator-operation gate closed; test-editor teardown crash
cause remains unproven as described above.
Shape/colours/collision and existing generation limits/versions remain unchanged.

### Native scene Ctrl+S after editor preparation — 2026-09-14

Regression: completed native preparation Window queue_free caused signal11 on
Ctrl+S in restored test_pier; direct pack/save succeeded. Keep one completed
controller hidden/inactive until owning plugin exit, release modal flags and
shelf/filesystem references, and ignore repeated continuation. No scene/model
data or serialization changes. Exact C++ internals remain unproved.

PASS test_voxel_editor_preparation (retention/inactivity/modal/ref cleanup,
idempotence, readiness/errors/timeout/exit) and object_library_updates.
Disposable Forward+ same8 tabs/current previews: original native Ctrl+S crashed;
corrected3 saves +place2 ember_surface_pilot water objects +placement Undo/Redo
+fourth Ctrl+S +reopen retains2 water objects PASS; closed without crash.
Final key-event probe had no List::erase/progress errors. Earlier timer direct
Save/deferred Save probes are diagnostic only; the latter explicitly suppresses
progress and is not valid clean acceptance. Known outside-tree/scan-aborted
shutdown diagnostics retained. Evidence Temp/ember-scene-save-crash-20260914-060850.

Manual acceptance CLOSED 2026-09-14: user confirmed the reported Ctrl+S crash fix
with «отлично». No original map writes by automated editor checks; no attribution
of earlier teardown failure without further evidence.
