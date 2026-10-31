# Ember — актуальные проверки и migration gates

## Игровые системы — библиотека, экипировка, эффекты и статусы, user UI acceptance OPEN

`python tools/run_game_systems_tests.py` — disposable project с текущими native
item/combat/action/dialogue data. Headless navigation/search/empty/missing link,
equipment route как фильтр item, action → прежний combat editor, encounter → Inspector,
Lab → existing scene, existing ItemEditor close и unsaved dialogue guard PASS.
Frozen content/scenes/material hashes проверяются до/после; реальных saves/JOI нет.

`python tools/run_game_systems_tests.py --usage` — saved native fixtures и incoming
navigation. Два файла с одинаковыми ID/именами, dirty cached consumer без связи,
informational ID в action text, внешний script и Resource dependency. Подтверждены
semantic/file refs и отдельные text candidates; one row/file, no cache mutation.
Actual usage button → filter → double-click → exact source path → Back с исходным
поиском. Empty filter не оставляет активный Open. Dirty draft не теряется;
stale saved SHA/deleted source не открывают ID alias, Refresh обновляет names/hash
и разблокирует переход. External FileSystem signal сохраняет выбранную запись.
Прежний conservative Delete guard остаётся. Frozen author data и no-writes PASS.
`--editor` дополнительно проходит native same-ID consumer, Open/Back/dirty guard,
bounded dialog, exact FileSystem route и прокрутку к началу destination card.
Captures usage-links/usage-destination/usage-dirty. Связанные navigation/operations
и existing editor Save/reopen/global Undo/plugin reload проверяются тем же runner.
Manual mouse/keyboard, narrow/125% и dynamic links/saves остаются OPEN.

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
User acceptance/narrow/125% OPEN.

Обувь: `python tools/run_game_systems_tests.py --footwear` — guarded disposable
native item/real form, optional integer/range validation, hidden metadata,
Undo/Redo/Discard/Save/reopen/UID и unsaved fitting. Реальные equip/unequip/Load
через Explore; MOVE открывает новую клетку, JUMP — ступень выше base, отрицательные
бонусы ограничены нулём, вещь вне shoes slot бонусов не даёт. Реальный composed
push+Wet action: сила2 блокируется стойкостью2, Wet3 сокращается до2; barefoot
контроль толкается и получает Wet3, полная защита блокирует статус. Exact
preview/commit/AI совпадают, grid/tags сохранены. V2 хранит shoes ID без derived
stats. `--cycle` дополнительно создаёт обувь в настоящем Forward+ editor,
сохраняет/повторно открывает, сравнивает четыре свойства, выдаёт через Старт игры;
новый игровой процесс снимает/надевает её через native сумку, проверяет боевую
проекцию, result/rewards once/Retry/Save/fresh Load. Author inputs frozen/restored.
Логи: Temp/ember-footwear-{targeted,operations,cycle,regressions,lab-setup,start,
check,party}.log. Дополнительный party suite: bag/health PASS; первый followers
не прошёл только perf gate40 switches (115619us), адресный повтор PASS;
defeat/save-v2/layout PASS. Порог не ослаблялся. Native footwear cycle exit0.
Снимки shoes-fields/shoes-fitting/footwear-inventory в
`C:/Users/novos/AppData/Roaming/EmberSystemsCycle-ember-game-systems-xf15x0uw/ember-tests/game-systems-cycle/`.
Manual OPEN: Игровые системы → Экипировка → Обувь → четыре значения → Примерка
→ Undo/Redo/Save/reopen/Discard → выдать через Старт игры → новая игра → сумка,
снять/надеть → бой, дальность/ступень/толчок/Мокрый → результат/Save/Load.
Сравнить с голым героем; проверить свои числа, ввод, narrow/125% и баланс.
WASD/overworld jump и мокрые свойства клеток сохраняются.

Старт игры: `python tools/run_game_systems_tests.py --start` — guarded native
Resource/default fixture, уровни/пять слотов/allowedHeroIds/stackMax/missing IDs,
пустая bag, malformed shape и singleton Create/Copy/Delete guard. Реальные form
pickers/level/count/Add, локальные Undo/Redo/Discard, Save/reopen/UID и точный
global publication Undo/Redo проверены. Нет записей до Save, deep recipe isolation,
совместимость item/Unit incoming links. Прежний neutral default совпадает с
PartyState.new_game: level1/empty gear/20 coin. Новый старт с Mira level7/weapon/
armor/bag получает derived полные HP/MP, XP0 и battle projection, повторный reset
не удваивает вещи. После изменения recipe Load возвращает прежние level/XP/HP/
gear/bag/flags. Невалидный reset не меняет live progress; invalid boot создаёт
нейтральную временную сессию с disabled persistence и понятным warning.
`--start-editor` и общий `--editor` — настоящий plugin/Forward+ tabs/gear/bag,
Save/reopen/Discard/publication Undo/Redo/UID, width/row-height guards и captures
start-game/start-game-bag. Render проверяется по сохранённым снимкам.
`--cycle` создаёт и сохраняет start в настоящей форме: надетые authored weapon
и shoes, 27 coin/3 authored potions. Новый процесс получает их через ExploreState startup;
тест больше не выдаёт/экипирует оружие вручную. Ordinary battle/Retry/Load/победа/
rewards once/menu Save и третий fresh Load сохраняют итог level2/bag8/flags (три экземпляра врага).
Author files frozen/restored. Clean saved checker: 72 records / 0 issues;
invalid стартовые IDs/levels/dictionaries/item refs диагностируются в fixtures.
Логи: Temp/ember-start-{start,editor,cycle,regressions,check,usage,operations,
workspace,party,interactions}.log; user saves не используются. Capture:
`C:/Users/novos/AppData/Roaming/EmberInteractionTests/game-systems-start-game-4616.png`
и `game-systems-start-game-bag-4616.png`; оба визуально просмотрены.
Manual OPEN: Игровые системы → Старт игры → вкладка героя/уровень/пять слотов →
общая сумка → Undo/Redo/Save/reopen/Discard; своя новая игра/старый Load и бой.
Проверить своё содержимое, input, узкое окно/125%. Записи не выбирать по скрытому
Lab preset; этот раздел меняет только настоящую новую игру.

Этап 5: `python tools/run_game_systems_tests.py --statuses` — новый native статус,
apply/remove effects и composed action создаются через общий Store/Session.
Default duration, все четыре reapply policies, cap, resistance, self-action
decay/expiry проверяются через настоящий Combat.preview/commit. Power/outgoing/
incoming modifiers, removal от ненулевого damage и сохранение при zero damage,
порядок apply→remove/remove→apply, invalid Resource/dependent effect/runtime и
stale statusRulesHash guard PASS. Snapshot одиночных статусов остаётся ID→turns; opt-in dose timers описаны ниже; baseline defaults
не меняют старые пять специальных реакций. Periodic и opt-in дозы — ниже.
Проверены все восемь operation-specific форм, скрытые значения, именованный
status picker/checklist, field Undo/Redo, точные publication bytes/UID/Undo/Redo,
native Save/reopen и удаление fixtures в обратном порядке зависимостей.
`--editor` дополнительно проверяет status rules через native controls/Undo/Save/
reopen и effect picker/checklist/operation switching, captures status-rules,
status-modifiers, effect-status/effect-remove. Настоящий Forward+ 1600×900 PASS.

Условия отдельных эффектов: `python tools/run_game_systems_tests.py --effect-conditions`
— Saved effect/action refs, named status checklists, Undo/Redo/Discard/reopen,
точные publication bytes/UID, independent clone/definition arrays, outgoing и
confirmed incoming refs PASS. Invalid/missing/duplicate/contradictory/whitespace
IDs и target predicates на MOVE_ACTOR блокируются. Все required/ни одного
forbidden, dose presence, SELF/CELL occupant и отсутствие субъекта на пустой
клетке; базовое действие/раннее наложение/снятие не меняют исходную проверку.
Skipped bonus не отменяет базовый урон и не накладывает свой статус; skipped heal
не блокирует самостоятельную атаку. Pure all-skipped chain исключена из targets/
Grid/ИИ; active branch используется actual enemy_command. Fire focus base damage
сохранён. Spread footprint только активного шага; stale/malformed hash guards
не расходуют ход. Targeted и related conditions/condition-groups/operations/usage/
check/15 save-combat-progression regressions PASS.
`--cycle` — native авторинг условия «не Горение»/Undo/Redo/Save/reopen → fresh
normal battle (positive/skipped bonus checks) → Retry/autosave Load/re-entry →
victory3/loot6/XP once → menu Save/Load → cold process Load PASS, exit0 у всех
трёх процессов. Исходные content/scenes/materials заморожены. Forward+ формы и
бой просмотрены, final captures:
`C:/Users/novos/AppData/Roaming/EmberSystemsCycle-ember-game-systems-6b0fam9f/ember-tests/game-systems-cycle/author-effect-conditions-forbidden.png`
и рядом author-effect-conditions/battle/result/fresh-loaded.png. Logs:
`%TEMP%/ember-effect-conditions-{targeted,conditions,condition-groups,operations,usage,check,regressions,cycle}.log`.
Свои условные сочетания, input, narrow/125% и баланс OPEN; это не manual acceptance.

Пояснения условных эффектов: `--effect-conditions` дополнительно проверяет
имена missing/forbidden статусов, success без обещания попадания, unset target,
SELF actor, CELL/empty/staged occupancy, независимые дозы и отсутствие подмены
статуса тегом поверхности/эффектом базового действия. 64 rngSeed при одинаковых
статусах покрывают hit и miss и дают один intent без мутации snapshot; ни rolls,
crit, вычисленного damage/HP или процентов в fixture-тексте нет.
`python tools/run_game_systems_tests.py --effect-intent` — disposable Forward+
1600×900: реальная Combat Lab, смешанная цепочка двух conditional steps, выбор
команды → wet target / frozen target / empty hover обновляет видимый ability info
и прежний intent panel. Hover/Cancel сохраняют state/MP/turn, progress nonpersistent.
Fixture authoring form удаляется перед запуском сцены; scene fullscreen явно
переключён в windowed для проверки реальной ширины карточки. Тот же запуск
проверяет прежний native test_combat_lab: focus/target/Cancel, movement/approach,
radial/drawers/lift/2D-3D и скрытые исходы PASS. 15 --regressions PASS; schema,
авторский контент и правила применения не менялись. Logs:
`%TEMP%/ember-effect-intent-{targeted,native,regressions}.log`; final captures
`C:/Users/novos/AppData/Roaming/EmberInteractionTests/effect-intent-{wet,frozen,empty}-75904.png`, также paths в native log.
Форма в игре просмотрена; manual свой ввод/длинные цепочки/narrow/125% OPEN.

Нативная проверка узкого UI/125%: `python tools/run_game_systems_tests.py --ui-layout`.
По умолчанию evidence в `%TEMP%/ember-ui-layout-evidence`; переменная process env
`EMBER_UI_EVIDENCE` задаёт отдельную папку. Disposable APPDATA хранит собственный
EditorSettings с display_scale3; actual EditorInterface.get_editor_scale=1.25
проверяется, глобальный пользовательский профиль не меняется. Настоящий Forward+
editor1280×800, затем1600×900: module navigation, status/effect/action/unit/AI/loot/
encounter/start/item forms, Save/Back bounds, поиск/shared Add и сложные HP/gear/
AND-OR условия. Native Add/Undo/Redo/Save/reopen и compact module navigation →
dirty Cancel/Discard сохраняют файл и session. Create/delete (long name)/dirty/
usage/check/Lab setup dialogs проверены по границам окон/кнопок; реальная saved
library check завершена. Удаление проверочного файла — только в sandbox,
подтверждение Delete не выполняется; destructive mechanics принадлежат --operations.
В игре content_scale_factor1.25, окно1280×800 (logical viewport1280×720): шесть
conditional steps с длинными именами, wet/frozen/empty hover, scroll к концу,
Cancel без MP/turn/state mutation. Header Reset/Menu, console/input, footer,
Timeline и широкое ability info не выходят за viewport. Inputs/content/scenes/
materials заморожены. --operations/--actions/--usage/--lab-setup/обычный workspace
и native --effect-intent + прежний test_combat_lab — связанные regressions.
Reproduced fixes: library/form toolbar clips; низ навигации; create500×2229;
long-name delete width>1280; боевой Reset вне viewport и ability info шириной145;
после reflow консоль/footer подогнаны по реальному text minimum.
Final captures просмотрены:
`C:/Users/novos/Documents/Codex/2026-10-22/ember-ui-125/`
(editor-library/form-action/effect-picker/create/delete/dirty-cancel/usage/check/
lab-setup/wide-library.png, battle-wet/frozen/empty/scrolled.png). Before рядом в
before/. Logs `%TEMP%/ember-ui-layout-{editor,combat,workspace,operations,actions,usage,lab-setup}.log`.
Один отдельный editor exit0xC0000005 после QA зафиксирован в
`%TEMP%/ember-ui-layout-editor-exit-failure.log`; далее fixture UI освобождён до
удаления, Filesystem settle awaited и завершающие процессы exit0. Это не диагноз
native crash и не закрытие общей stability gate. Собственный ввод/другие DPI/
размеры/ощущение остаются manual OPEN; выбранный layout gate технически закрыт.

Повторная диагностика native exit (2026-10-22): исходный AV не воспроизведён.
Disposable Forward+ cold/warm editor, periodic/dose forms, прежний порядок
fixture cleanup, быстрый выход без settle, 30 FPS/unlimited, активный FileSystem
scan и очередь настоящих scene/material previews проверены отдельными процессами.
24 rapid/sequential Save/Undo/Redo/reopen/edit/delete cycles под Windows debugger
и обычное закрытие через deferred EditorNode close notification завершились exit0.
Первый полный --ui-layout также PASS; исходные authored Resources/maps/saves
не менялись. Это результаты конкретных повторов, не доказательство нового fix.
Evidence: `%TEMP%/ember-editor-crash-20261022/` — repeat.py/debug.py, repro-*.log,
stress-debug.log, exit-compare.log, native-close.log, preview-exit-valid.log.
Первый полный запуск — `%TEMP%/ember-editor-crash-20261022-baseline.log`.
После изменения runner обычный --stability (12 cycles) и frozen authored data
PASS; журнал final-stability.log в той же папке.
Промежуточные диагностические ошибки не считаются PASS: повторное создание уже
существующей fixture, отсутствующая папка preview, прерванный неподключённый close
signal. Неправильная recursive root.propagate_notification(WM_CLOSE_REQUEST)
заблокировала remove_child при unload и дала отдельный AV +0x245241b; этот probe
отброшен, исходные тесты так не закрывались. Он не доказывает причину старого AV.
Правильный close не обходит дерево под lock и прошёл; исходный native stack/dump
для последних исторических вылетов по-прежнему отсутствует.

Исправлена потеря диагностического состояния: `run_game_systems_tests.py`
при exit0xc0000005/0xc0000374/0xc0000409 сохраняет guarded sandbox/cache/log и
параметры запуска в `%TEMP%/ember-native-crash-*` до TemporaryDirectory cleanup.
Отдельный APPDATA внутри sandbox переносится; внешний профиль/посторонние env
не копируются. Каталог содержит состояние в момент аварии, а не чистый fixture
до начала теста: повторный запуск может потребовать минимизации сохранённого
сценария. Это не автоматический native dump/stack capture. Исходный FAIL остаётся
ошибкой процесса. `python tools/test_game_systems_crash_capture.py` — 2 tests PASS;
retention assertion на прежнем runner FAIL. Synthetic exit проверяет capture,
не воспроизводит Godot AV. Следующее действие при новом native сбое — сохранить
этот каталог и подключить debugger к точному сценарию, а не считать exit0 fix.

Периодические HP: `python tools/run_game_systems_tests.py --periodic` — native
templates poison/regeneration и authorable field, новые saved статус/effect/action,
signed control/Undo/Redo/Discard/Save/reopen/UID/invalid bounds. Fixed HP идут после
action effects: сначала все лечения до max HP, затем весь periodic урон, затем
снятие removeOnDamage/decay. HP10/10 при +4/−6 → 4, HP3/10 → 1 независимо от
порядка dictionary; no resurrection, last tick, self/ally timing, cleanse before
tick, bypass guard/процентных modifiers, stale rules и once-only commit PASS.
Exact internal turn_end_preview и commit совпадают без source mutation; player
intent не раскрывает скрытые rolls/итог HP. AI/movement-only fallback, победа/
поражение от яда и освобождение удерживаемого при смерти носителя проверены.
`--periodic-editor` — настоящий native draft/Save/reopen/Undo/Redo/Discard/global
publication bytes/UID, затем отдельный fresh Forward+ процесс с сохранённым −6 HP.
Native Защита: Mira HP3 → 8 (регенерация +5) → 2 (яд −6), оба счётчика 2→1,
HP bars/status names/journal actual amounts и scroll-follow проверены по снимку.
Прежние --statuses, 15 --regressions, --conditions и --check PASS; clean74/0.
Логи: Temp/ember-periodic-{targeted,editor-repeat,statuses,regressions,conditions,
check}.log. Снимки: `C:/Users/novos/AppData/Roaming/EmberInteractionTests/`
`game-systems-periodic-status-form-40848.png`, `periodic-after-74764.png` просмотрены.
Один повторный editor завершился 0xC0000005 после PASS формы при выходе;
Temp/ember-periodic-editor-failure.log сохранён. Первое прохождение и следующий
последовательный повтор завершились штатно; причина не доказана, crash не считать
исправленным. Рабочий editor/cache/авторские карты и пользовательские saves не
использовались. Manual OPEN: Статусы → Яд/Регенерация → HP/длительность → Save →
Effect apply_status → свой приём/бой, обе фазы/снятие/истечение; input/narrow/125%.
Независимые дозы: `python tools/run_game_systems_tests.py --stacks` — guard только
на disposable project. Real form limit/HP, local Undo/Redo/Discard/Save/reopen и
publication exact bytes/UID; max_stacks1..12, >1 только periodic, нейтральный
default1. Реальный resolver: два наложения в цепочке, раздельные сроки/последний
тик/истечение, cap обновляет минимальный timer, исходные arrays неизменны.
Heal-first/clamp/lethal/no resurrection, cleanse всех доз до тика,
removeOnDamage, неизменные power/damage modifiers, legacy scalar и malformed
snapshot arrays; shared exact preview/commit/state+status content stale guards,
conditions и actual AI. `--stacks-editor` — родной plugin: cap3/−6 HP, Undo/Redo,
Save/reopen/Discard/publication, затем отдельный fresh Forward+ Lab: HP25→30→18,
яд ×2 со сроками1/3 → ×1 со сроком2; HUD/3D badge/журнал −12 HP. Снимки:
`C:/Users/novos/AppData/Roaming/EmberInteractionTests/game-systems-status-dose-limit-74460.png`,
`stacks-before-61216.png`, `stacks-after-61216.png` в той же папке просмотрены.
Один editor exit0xC0000005 после PASS формы до runtime: точный лог
Temp/ember-stacks-editor-exit-failure.log; повтор editor+runtime exit0.
Причина не доказана, успешный повтор не закрывает общую stability gate.
`--cycle` также авторит periodic −1/cap2, обычный map battle накапливает две дозы,
завершает результат/rewards once/Save/fresh Load. Исходные авторские файлы frozen.
Логи Temp/ember-stacks-{stacks,periodic,editor,regressions,conditions,
gear-conditions,condition-groups,operations,check,cycle}.log.
Manual OPEN: Статусы → копия Яда/Регенерации → HP/предел доз → Save/reopen →
приём apply_status → бой → несколько наложений с разными сроками/предел/
очистка/смерть/Retry; сравнить журнал и счётчики. Свои числа/input/narrow/125%/
баланс не приняты. Сила/множители не умножаются, статусы не переносятся в save.

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

Этап 6, подбор общих эффектов: установить process env
`EMBER_GAME_SYSTEMS_EDITOR_FOCUS=effect-picker`, запустить
`python tools/run_game_systems_tests.py --editor`. Disposable Forward+ gate
создаёт fixture эффекта с условием Wet и черновик приёма. Поиск по русскому имени/
ID/описанию/тексту условий, очистка и ручная смена OptionButton selection обновляют
preview с правилами/точным path. No matches/all used блокируют Add; filter
переживает Add/Undo/Redo. Поиск/выбор не меняют Resource signature/local history.
Shared ref/условие сохраняются после Save/reopen, Discard сохраняет bytes/UID;
min width 1600×900 PASS, исходные author data frozen. Проверены --actions и
--effect-conditions; runtime/schema не менялись, full combat cycle повторно не
требовался. Логи `%TEMP%/ember-effect-picker-{actions,conditions,editor}.log`.
Native captures `user://game-systems-effect-picker-{preview,empty,used}-<pid>.png`
выведены полными путями в editor log; состояния просмотрены. Свой ввод/подбор/
narrow/125% OPEN.

Этап 6, условия применения: `python tools/run_game_systems_tests.py --conditions`.
Четыре списка actor/target required/forbidden: AND, positive remaining turns,
unknown/duplicates/conflicts, SELF cross-conflict, CELL actor-only; wet terrain
не заменяет unit status. Именованные UI selectors/Add/Remove, duplicate/conflict
guard, исправление missing saved ID, несовместимая CELL запись остаётся доступна.
Local Undo/Redo/Discard, Save/reopen и publication bytes/UID/Undo/Redo, status
relations и confirmed incoming link PASS. Реальный Combat eligible/valid/preview/
commit и Grid подход согласованы; при false condition нет movement/Defend/cost/
turn. Pure preview, multi-status AND, multiple targets, SELF/CELL, AI и no-target
reason проверены. Stale state, changed rules и malformed actionConditionsHash
отклоняются; commit без hashes повторяет predicate check. Старый empty контент
проходит --actions и 15 --regressions. Native --editor проверяет predicate
controls/Undo/Redo/Save/reopen/1600×900 width; capture action-status-conditions.
Numeric rows: actor/target HP/MP, ≥/≤, points/percent, exact integer thresholds.
Malformed keys/enums/types/fractional/negative/>100%, duplicates, contradictory
same-measure bounds и SELF merged conflict отсекаются. Смешанные меры оцениваются
по конкретному максимуму бойца. Typed rows сохраняются/переоткрываются без float
conversion; nested projection/draft edits изолированы. Add/remove, edit value/
comparison/unit, numeric field merge Undo/Redo, Discard, publication bytes/UID
и malformed saved row correction PASS. CELL несовместимые target rows видимы,
Save блокируется. Exact boundary/30.69% не округляется; MP>=10 пропускает оплату
2 MP до 8, SELF HP<=30% пропускает лечение 20→32/100. Numeric/status AND, stale
state/rule hash и независимый commit predicate recheck, eligibility/approach/AI
проверены. Max MP 0 блокирует percent с причиной, MP=0 points допускаются.
--editor проверяет numeric controls/Undo/Redo/Save/reopen/width и capture
action-value-conditions; длинная подпись вынесена над числовой строкой.
--cycle создаёт actor forbidden frozen и HP>=1% через настоящую форму и Save;
новый runtime process подтверждает saved rows, отказ по обоим видам условий и
обычную победу/result/save; третий fresh Load сохраняет predicates/assignment/
shared refs. Author inputs frozen. Логи: Temp/ember-value-conditions-{targeted,
editor,regressions,cycle}.log.
Manual OPEN: Игровые системы → Приёмы → копия/Редактировать → Проверяемые условия;
потребовать Мокрый у цели, запретить Заморозку исполнителю, сохранить/переоткрыть,
проверить объяснение в бою при появлении/исчезновении статуса, Undo/Redo/Discard.
Добавить MP исполнителя ≥10 очков и HP цели ≤30%: проверить ровно 10/30%, ниже/
выше границы, изменить числовую строку и меру, Undo/Redo/Save/reopen/Discard.
Своё содержимое/мышь/клавиатура/узкое окно/125% не приняты автоматическими gates.
Независимые периодические дозы проверяются отдельным gate ниже.

`python tools/run_game_systems_tests.py --condition-groups` — плоские ALL/ANY
группы поверх прежних mandatory AND rules. Real form Add/mode/remove и Undo/Redo,
пустая/невалидная группа не Save, malformed saved content не исправляется молча
и явно удаляется, publication exact bytes/UID Undo/Redo, reopen/Discard, deep
projection/copy и confirmed usage links. Runtime: Wet OR Burning (каждая ветка/
обе/ни одна), mandatory MP и AND разных групп, mixed actor/target alternative,
HP/MP и надетая вещь (bag не считается), ALL/ANY переключение. Eligible/valid,
Grid approach, pure preview/стоимость/один commit, changed-group hash и
независимый CELL commit recheck, SELF/CELL/actual AI используют общие правила.
Malformed/unknown/duplicates/nested/empty groups блокируются; несовместимые
alternative bounds/gear разрешены только в ANY, SELF joint conflict — только ALL.
Native `--cycle` создаёт mixed group «цель Мокрая ИЛИ не Заморожена» в общей форме,
проверяет mode Undo/Redo/Save/reopen и сохранённые mandatory status/numeric/gear.
Fresh ordinary map battle проверяет обе ветки/отказ, result/Save/fresh Load;
author data frozen/restored. Actual Forward+ group form просмотрен, проверяется
workspace width; selector режима и status picker на отдельных строках.
Логи: Temp/ember-groups-{targeted,conditions,gear-conditions,operations,usage,
check,regressions,cycle}.log. Native cycle exit0. Capture:
`C:/Users/novos/AppData/Roaming/EmberSystemsCycle-ember-game-systems-eud9b_80/ember-tests/game-systems-cycle/author-condition-groups.png`.
Manual OPEN: Приёмы → Проверяемые условия → оставить MP исполнителя ≥10 в
обязательных → Добавить группу → ИЛИ → цель Мокрая/цель Горит → Save/reopen →
бой. Проверить каждую альтернативу и отсутствие обеих, переключить И и проверить
оба статуса одновременно; Undo/Redo/Discard, AI, input/narrow/125% и удобство.
Все группы соединены И, вложенности нет; старые Action defaults сохраняются.

`python tools/run_game_systems_tests.py --gear-conditions` — отдельные guarded
item/action fixtures, три AND-правила (надета туника, weapon occupied, shoes empty)
вместе со статусом/MP. Saved pickers/Add/remove/редактирование row/Undo/Redo,
missing-ID correction, CELL saved target removal, Save/reopen и exact bytes/UID
publication Undo/Redo/Discard, deep projection isolation, confirmed item incoming
link PASS. Five-slot compatibility, unknown/malformed rows, duplicates, empty
против occupied/item, два разных weapons в any/exact slot, три accessories,
совместимые два accessories и два одинаковых в разных slots, SELF merge проверены.
Runtime bag-only отказ, any accessory2/exact accessory1, unarmed missing equipment,
SELF и CELL actor rules, eligibility/preview/approach без fallback/cost/turn,
pure/once-only commit и независимая проверка экипировки без stateHash, changed
rule hash, status/MP AND, AI actor/target gear и no-target menu reason PASS.
--editor проверяет тунику по имени, смену any→armor/Undo/Redo, shoes empty,
Save/reopen/width; capture action-equipment-conditions после settled layout.
Первый full --editor прошёл формы, но Lab child не дал ready/log; повторный
последовательный full --editor PASS без изменения launcher. Лог первого отказа:
Temp/ember-gear-conditions-editor-first.log; причина не установлена, gate запуска
на своих данных остаётся ручным. Native --cycle сохраняет worn Fixture.WEAPON
через настоящий picker, fresh runtime отвергает bag-only и проводит ordinary
battle/result/Retry/Save, третий Load сохраняет gear row и assignment. Прежние
--conditions и 15 --regressions PASS; --check/--usage проверяют общие ссылки.
Author inputs frozen; логи Temp/ember-gear-conditions-{targeted,editor,regressions,
previous,cycle,check,usage}.log. Manual OPEN: Приёмы → копия → Экипировка →
надетый предмет/занятый или пустой слот → Save/reopen, Undo/Redo/Discard → бой;
проверить исполнителя/цель и обе позиции аксессуара, отсутствие вещи и наличие
только в сумке, объяснение отказа. Свои inputs/125%/narrow/launch ещё не приняты.

Этап 7: `python tools/run_game_systems_tests.py --encounters` — new native loot
с двумя item rows/chance/count, internal copy-on-edit, numeric Undo/Redo, invalid
range/missing item refusal, exact publication bytes/UID, Save/reopen. New enemy
выбирает AI по ID и shared loot; inline current ref не пропадает, Discard не
меняет HP. Encounter выбирает field/arena refs и ordered rosters с правильной
стороной/без повторов героев; enemy templates можно повторять. Undo/Redo и correction неподдерживаемого outcome enum.
Reopen → native deployment order → Grid.enemy_command без source mutation →
Result.build: guaranteed loot, deterministic repeated projection, equal XP
каждому из двух героев; поражение без victory XP/loot PASS.
`--regressions` включает Unit/AI/Loot/Encounter Resource gates вместе с прежним
save/result/combat набором. `--editor` — native loot controls/Undo/Save/reopen,
shared enemy refs и roster/order/XP через настоящую форму, width/lifecycle PASS.
Captures loot-rows/enemy-links/encounter-summary/encounter-roster. Исходные author
inputs заморожены. Полный запуск выбранного draft в Lab — этап 8; user feel,
manual Save/Load/reward return и narrow/125% остаются открыты.

Повторные враги: `python tools/run_game_systems_tests.py --enemy-instances` —
один saved Unit+Loot → три ordered строки Encounter через настоящие controls.
Remove/Undo/Redo, Save/reopen/Discard/UID, deep clone и confirmed incoming file
link; прежний Inspector предлагает уже используемый enemy template. Герои
не повторяются, missing template и недостаток deployment cells блокируют Save.
Runtime IDs стабильны, обходят столкновения с authored participant IDs; первый
ID и unique roster definitions сохранены. HP/MP/status/cells/nextAt независимы;
новый initial_state не наследует урон/статусы. Shared template edit обновляет
всех в новом бою, не активный snapshot. Actual AI/eligible targets/Grid approach,
три defeated/counters и три независимых rolls общей loot table; повторный Result
детерминирован, defeat без loot. Номер перед именем различим в узкой очереди.
`--cycle` — native Add одинакового шаблона дважды/Undo/Redo/Save/reopen/width;
ordinary map battle с тремя врагами, defeat Retry/autosave Load/re-entry и чистая
победа через штатные действия. Результат: три врага, XP35 один раз, loot6;
потрачен один из трёх potions, после Continue bag8. Double Continue/fresh Load
не дублируют награды. Original author hashes/UID сохранены; все процессы exit0.
Логи: Temp/ember-instances-{targeted,encounters,regressions,lab-setup,operations,
usage,check,cycle}.log. Native captures просмотрены:
`C:/Users/novos/AppData/Roaming/EmberSystemsCycle-ember-game-systems-b87zrv2c/ember-tests/game-systems-cycle/author-enemy-instances.png`,
`battle.png`, `result.png` в той же папке. Manual OPEN: Встречи → один шаблон
врага добавить несколько раз → порядок строк/точки Battlefield → Undo/Redo/
Save/reopen/Discard → Lab и обычный бой → отдельные цели/статусы/убийства/Retry/
результат/Save/Load; свои входы/узкое окно/125% и удобство. Вариации характеристик
отдельных экземпляров и авто-выбор партнёра по шаблону не входят в этот срез.

Этап 8: `python tools/run_game_systems_tests.py --lab` — только disposable import,
saved synthetic Encounter с Mira/Wisp и 9 XP, настоящий runtime process Forward+.
Два запуска: default по карточкам/пустая bag и настройки Mira level 9/armor/herb 3.
Autoload до чтения saves имеет persistence/restore off и private paths. Проверены
request/path/duplicate-arg guards, native selected ID/roster, private party/inventory,
victory/defeat/result/Retry, отсутствие gameplay Load/transition/reward application.
Save/autosave не создают файлы; sentinel по default save path не меняется, private
progress snapshot неизменен (сравнение исключает только timestamp savedAtMs).
Настроенный запуск читает versioned private request, consumes файл, проверяет
реальные stats/equipment/counts, Combat.preview/commit расходует одну траву и
лечит; Retry возвращает полный HP/MP, level/equipment и три исходных расходника.
Арена fixture наследует Thaw Keeper, содержит заметный marker и исходное другое
поле; runtime обязан использовать selected scene/decor/camera и Battlefield встречи.
Проверены active camera/ray picking при дополнительной current camera, произвольное
имя decor node «script», 2D hide/3D restore, deployment и один экземпляр
арены/HUD после Retry. Пустая/обычная 2D/3D сцена и missing core nodes блокируются;
launcher отказывает invalid saved arena до OS.create_process. Derived-script
fixture с _init file sentinel подтверждает отсутствие инстанцирования при validation.
Captures library-lab-deployment/battle/victory/defeat; content/scenes/materials frozen.
`--encounters` проверяет выбор другой арены, Undo/Redo и сохранение двух разных
ссылок arena/field после reopen. `python tools/run_game_systems_tests.py --arena`
запускает семь transition/defeat/Lab/arena/deployment/vertical camera/animation gates в
disposable Forward+ 1600×900/30 FPS: shell paths обновлены, исходный fullscreen
default проверяется до тестового windowed override; pair hover ждёт deferred
drawer focus перед disabled help, picking ждёт actor presentation с deadline.
Staged pose проверяется после достижения клетки, а не по короткому wall timer.
Прежнее library-only включение в disposable baseline воспроизвело эти test races;
исправлены только ожидания теста, assertions/игровое поведение сохранены.
Headless не считается UI layout acceptance; native suite PASS, ручная camera/decor
и свои сцены/narrow/125% OPEN. Normal transition использует selected arena тем же
installer; standalone Lab без authored encounter сохраняет default Arena.
Default navigation gate проверяет Lab button и refusal dirty draft. `--editor`
создаёт saved encounter fixture и запускает его настоящим adapter: проверяет
native setup controls/Undo/Redo/Cancel/reopen, remembered successful session setup,
consumed ID/settings в child log, duplicate-window guard; завершает только свой child.
Windows log проверяется также после закрытия child handle (active log может быть
buffered/locked); waits используют wall-clock deadline, перед quit filesystem
settles после удаления fixtures. Default copy/cache/user saves не используются.
Captures lab-launch/lab-setup. Numeric edits не уничтожают focused controls.
`--operations`, `--regressions`, `python -X utf8 tools/run_save_destination_tests.py`
PASS — в том числе normal encounter return/reward once/defeat retry/save load.
Manual authored launch/play/result/Retry/Close и свой save/use/result/load OPEN;
Тест saved-only, со своей виртуальной прокачкой/сумкой, без user progress/save writes. Выбранная арена проверяется в --lab выше; session-only память
последнего запуска дополнена именованными локальными наборами ниже.

`python tools/run_game_systems_tests.py --lab-setup` — disposable native fixtures:
custom saved hero с собственной базой, все пять slots/два аксессуара, shared
Party formula parity, restrictions, unchanged defaults и detached inputs.
Неверные hero/item/slot/level/count/type, legacy sixth slot, request identity/
duplicate/orphan/path/corrupt/version/size отклоняются; dirty cached card не
влияет на fresh setup. Native level/slot/count/hero controls, локальные Undo/Redo,
Reset, Cancel/reopen и dirty authoring guard PASS. Workspace context не пишется
в gameplay Resources/save. Manual mouse/keyboard/narrow/125% и authored cycle OPEN.

`python tools/run_game_systems_tests.py --presets` — три процесса в отдельном
user dir: Save→cold Load→Forward+ private Lab. CRUD/rename/duplicate name scoped
by roster, exact ID, same roster across encounters/order, deep detached payload.
Corrupt/version/type/oversize files не пишутся; stale Save/Delete/undo и no-op
revision проверяются. Fault injection preserve/publish/rollback сохраняет old
bytes, missing main читает .previous. Native controls Load Undo/Redo, Cancel,
Delete confirm/cancel/restore; missing item остаётся в picker, save/launch blocked.
Cold dialog emits loaded setup; third process получает level 9/armor/herb 3,
uses herb and Retry restores исходные stats/equipment/counts. Preference bytes/
progress snapshots неизменны в бою; сравнение исключает только savedAtMs.
`--presets-editor` — focused actual Forward+ Ember plugin: named preset Save,
новый экземпляр окна → select ID/Load → real adapter child consumed settings.
Capture lab-presets; body/feedback не перекрывают native launch/cancel row.
Frozen author inputs PASS; ручные свои наборы/мышь/narrow/125% OPEN.
Publication 0xC0000005 диагностика и исправление — следующий --stability gate;
последний full --editor после адресного filesystem update PASS, ручной gate OPEN.

`python tools/run_game_systems_tests.py --stability` — guarded disposable native
Forward+ editor, 12 cycles rapid/sequential Save/Undo/Redo/reopen/edit/delete.
Нечётные cycles ждут index updates, чётные повторяют быстрый lifecycle прежнего
repro; после каждого final delete native FileSystem должен убрать запись.
Slow checkpoints проверяют native index presence/absence; cache values, UID и
exact publication bytes проверяются в обоих режимах, full scan count не растёт.
Headless queue gate проверяет file coalescing, busy import/scan, weak leases,
source/full priority и request из callback, runtime no-EditorInterface effects.
Прежний короткий loop воспроизвёл AV на втором Save; Windows invalid-read
code/address сохранены в Temp/ember-editor-crash-20261012/driver-late.log.
Baseline отдельно выдавал get_dependencies errors при изменении/удалении файла
во время full scan. Probe с адресным update_file при прежних cache/forms —
24 cycles без AV/errors; holding scans не падал до bounded timeout, PASS ему
не присваивается. Отключение cache replace не доказано причиной/исправлением.
Production fix сохраняет synchronous writes/cache/UID, убирает full scan из
library published handler, передаёт path общей queue. Native API update_file
восстанавливает/убирает index без background проекта scan; cache не отключается.
Фиксированные slow и rapid gates, исходный full editor и full cycle PASS:
Temp/ember-game-systems-stability-fixed.log, ember-game-systems-stability-rapid-fixed.log,
ember-game-systems-editor-stability-fixed.log, ember-game-systems-cycle-stability-fixed.log.
Author inputs frozen. Полный dump/точный C++ stack не получен; unrelated native/
GPU stability этим gate не принимается. Ручные свои Save/Undo/Redo/reopen OPEN.

`python tools/run_game_systems_tests.py --cycle` — полный автоматический цикл в
disposable native проекте, три отдельных Forward+ процесса, максимум 30 FPS.
Editor через общие Create/forms/pickers/Save создаёт weapon/consumable/status/
effect/action/AI/loot/enemy/field/encounter и назначает новый приём существующей
Mira. Проверены field Undo/Redo, Save/reopen values/UID/bytes/shared refs и Discard
несохранённого MP. Encounter arena picker сохраняет другую inherited сцену с
marker, авторскими CameraRig lens/pitch/light и дополнительной current decor camera.
Normal map action adapter обязан открыть её, сохранить единственный HUD/World,
назначить encounter field до ready, использовать правильную camera для picking,
скрывать весь decor в 2D и возвращать в 3D. Реальный consumable расходуется перед
forced terminal defeat; native Retry сохраняет Arena/HUD instance, восстанавливает
units/HP/MP/equipment/deployment/bag и меняет seed без записи saves/progress.
Второе поражение → native autosave Load → восстановленный XZ/progress/unlock →
повторный вход снова открывает выбранную арену. Затем обычный победный путь.
Исправлен реальный factory failure Create(field): untyped
Array нельзя присвоить typed Array[Vector2i] через generic Resource; assign
сохраняет тип и прежние клетки. Этот путь достигается именно Create без копии.
Обычный Transition берёт saved Encounter, persistent party и inventory из
тестового save owner. Native selection расходует новый potion, лечит 4 HP и
платит action cost; новый приём платит MP и накладывает authored status, native
AI совершает ходы. Победа получена Combat.commit, без console kill/HP=0 подмены.
Result показывает трёх побеждённых, 35 XP, level-up и гарантированный loot ×6. До Continue live
progress неизменен; double Continue даёт уровень 2/XP5, flags/counters и итоговые
4 potion один раз. Native menu Save/Load восстанавливает намеренно изменённое
состояние, manual envelope v2 и SHA неизменны. Третий процесс (другой PID) читает
private save при autoload, восстанавливает позицию, затем повторяет native menu
Load и сравнивает party/HP/MP/XP/all5slots/inventory/flags/active group/strategy/
chests/shop state/map/XZ. Completed encounter не запускается повторно; XP/loot
не дублируются. Native fixture alias зарегистрирован до проверки destination.
Сохранённые author resources/UID неизменны между фазами; temporary records и
Mira assignment откатываются в sandbox, final content/scenes/materials frozen.
Рабочие 691 author SHA совпали, настоящие авторские maps/saves не использованы.
Captures author-weapon/action/encounter, deployment/defeat/defeat-loaded,
battle/result/save/menu-loaded/fresh-loaded;
result.json хранит save/map SHA и payload, manifest — Resource hash/UID. Последний
полный цикл и связанные operations/navigation PASS; runtime captures 1600×900.
Прежний native editor author exit также входил в публикационный сценарий;
его исправление/ограничения — --stability выше. Последний full cycle после fix
PASS: Temp/ember-game-systems-cycle-stability-fixed.log. Авторская mouse/keyboard
приёмка, narrow/125%, свои карты/saves и декоративная смена arena остаются OPEN.
Семь Forward+ regressions — Temp/ember-normal-arena-related-final.log PASS;
15 save/combat/progression gates — Temp/ember-normal-arena-regressions.log PASS.

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
ready registration. Read-only проверка saved каталога в копии: 74 записи,
0 issues; author hashes сравниваются отдельно. Это охват десяти game-system
roots + icon/story ID/dependencies, не full story validation, баланс или dead code.
Ручная оценка удобства отчёта/узкого editor/125% и прежние authored gameplay
gates остаются OPEN; green data report их не закрывает.

## Сквозной редактор28.10 — этап7, подготовка полной сферы OPEN

Один native EditorPlugin replay на изолированной копии main использует прежние команды земли,
WorldEditSessions/CanvasForms/StampPanel: земля/история → две формы/склейка/покраска/выемка/
отделение/штамп/Cancel/история → внешний объект → тот же черновик земли/объекта → общий
Save/fresh Source+scene reopen/Discard/3 looks/canonical collision: EDITOR_FINAL_CYCLE PASS.
Полная сохранённая main-copy в новом Forward+ процессе: boot83928мс, ходьба/опора/3 looks PASS.
Первичный play report FAIL по времени полной сферы; актуальный результат оптимизации —
[Производительность мира](docs/EMBER_WORLD_PERFORMANCE.md#отложенные-сборка-и-сфера) → «Отложенные сборка и сфера». Это gate производительности, не ручная приёмка.
101 author file хеш неизменен. Подробности/следующее действие/evidence — World Authoring →
«Сквозной сценарий редактора · этап7,28.10». Mouse/личный F6/вид OPEN.
_forms_cycle scene-topology reload больше не использует IGNORE_DEEP для живых tool scripts;
новый процесс проверяет настоящее холодное открытие. Успешные части заново не запускались.

Оптимизация подготовки28.10: `test_anomaly_preparation.gd` — aligned RGBAF byte parity/padding,
worker/direct arrays трёх обликов и отмена устаревшего host PASS; `test_solid_display_cache.gd`
Forward+ — каналы volume display/сохранение boundary, disk living hit/геометрия/pull/Source PASS.
`test_object_grass_anomaly.gd` Forward+ — объектная опора/skew transform и terrain deltas PASS;
`test_voxel_preview_disk_cache.gd`/`test_voxel_object_library_updates.gd` — cached-only startup,
прежние cache hits и обычная очередь недостающих previews после открытия PASS.
Full main-copy после terrain/scatter-среза: editor gate111323/map145337мс (не быстрее), game78193мс;
сфера138251мс/702 bindings/324tiles PASS, motion без rebuild/collision/3looks PASS.
Расстановка не сокращалась; ограничения сравнения/evidence принадлежат World Authoring. Изменений Source/scene/history нет,
поэтому ранее успешные Undo/Redo/save/reopen/discard не повторялись.

Продолжение28.10: `test_material_height_cache.gd` — cold/direct/disk byte parity, защита от
мутации потребителем, изменение пикселей/softness/sharpness, corrupt fallback и неизменность
albedo PASS. Native1024px stone/soil/grass disk reopen16/15/14мс вместо15693/17971/18221мс;
хеши одинаковы. В настоящем editor воспроизведён пустой static cache_directory без @tool;
финальный native QA проверяет непустой путь и3 disk hits после исправления.
Полная main-copy: gate91811→34849мс, map128537→67989мс, все work queues пусты.
`test_material_library_depth.gd -- --normal-only` Forward+: profile binding, общий GPU bank,
world scale, shader compile и neutral relief mean RGB=0 PASS; весь тест FAIL на прежнем
negative control «previous plane-normal path exposes tessellation»:0.000291 вместо>0.0005.
Порог/шейдер/фикстура не менялись. Это открытый gate чувствительности прежнего сравнения,
не объявление всего render-теста успешным; повторный широкий прогон не запускался.
Это warm height cache; первый bake не ускорен. Изменены только производные изображения,
Pattern/Source/serialization/history не меняются; прежний save-цикл не повторялся.
Evidence/ограничения — [Производительность мира](docs/EMBER_WORLD_PERFORMANCE.md#отложенные-сборка-и-сфера) → «Отложенные сборка и сфера».

Растительность28.10: `test_detail_preparation.gd` Forward+ PASS; ProbePatch проверяет, что
fresh disk hit не запрашивает endpoint meshes для footprint roots. Cold generation/3looks/
reopen exact CPU transforms, invalidation mask/height/seed/size и stale cancellation PASS.
На main-copy222 hits/0 generations/77878 instances:50223→48659мс; terrain не менялся.
Полный editor Save/Undo не повторялся: Source/ключи/история не менялись. FPS не измерен.
Research/профиль/следующий срез — [Производительность мира](docs/EMBER_WORLD_PERFORMANCE.md#доверенная-текущая-точка) → «Доверенная текущая точка».

Общий PNG bank28.10: `test_material_color_bank.gd` native Forward+ PASS: normalization/mips
и linear means точны относительно прежнего алгоритма, duplicate slots/metadata/white fallback,
общие artwork banks при независимых editable lookups и preview, Texture2D replacement invalidation,
источники неизменны. Контролируемый render до/после установки отдельного reference bank
побайтно одинаков. Это не художественная приёмка основной карты.
Main-copy222→3 banks,77878 instances/222 hits/0 generations; base-level оценка167→1MB.
Wall startup82250мс, против прежних48659; reuse-off control99856мс. Shared run789/789 focused,
control592/593 unfocused callbacks, поэтому ускорение/отсутствие latency regression не доказаны.
Terrain startup/frame scheduling gate — World Authoring; FPS не измерялся.
Source/schema/history/геометрия/шейдер не менялись; полный Save/Undo/сфера не повторялись.

Startup publication budget28.10: `editor_test_terrain_preparation.gd` на disposable native editor
PASS: initial12ms→settled4ms, первый brush отменяет повышенный budget и release его не возвращает;
cold/warm dense+sectioned geometry/UV/colors/collision/field/layout,3looks, overlap latest edit,
continuous stroke до отпускания, open/Discard stale и malformed cache fallback сохранены.
Focused30FPS main-copy before/after: terrain38760→32411мс, ready49146→42573мс,
666→424 callbacks,324 cache hits в обеих пробах,222 patches/77878 instances неизменны.
Max startup process15881us при soft12ms (одна начатая операция может завершиться позже).
Runtime/Source/save/history не менялись, широкая матрица не повторялась. FPS/личный ввод OPEN.
Owners/передача следующего независимого разбора — [Производительность мира](docs/EMBER_WORLD_PERFORMANCE.md#доверенная-текущая-точка) → «Доверенная текущая точка».

Editor tree cache28.10: `editor_test_tree_look_cache.gd` как временный native EditorPlugin в
disposable stage, два fresh процесса на одном user://ember-tests/ каталоге: PASS. Проверены
default CACHE_ROOT до overrides (старый SceneTree тест это пропускал), empty override,
cold4 builds/4 файла/0 hits → warm0 builds/4 hits, geometry трёх обликов дуба/берёзы и Source
побайтно равны, возврат к detailed точен. После проверок матрицу не расширяли.
Main-copy default cache:4 hits/0 builds,324 tiles/222 patches/77878 instances, ready43043→36717мс
от QA origin,37784→31679мс от вызова открытия. Map looks11181→5384мс; focused426/426.
Изменён только @tool; данные/алгоритмы/история/физика не менялись, общий Save/Undo/сфера не повторялись.
Evidence/known UID fallback и fixture shutdown warnings — [Производительность мира](docs/EMBER_WORLD_PERFORMANCE.md#доверенная-текущая-точка) → «Доверенная текущая точка».

Library metadata28.10: `test_voxel_catalog_metadata.gd` headless PASS: cold/warm exact metadata,
нет удержания dense Resource, отдельные copies, live unsaved fields без disk poisoning,
same-size/same-second content edit, malformed/corrupt fallback, Source unchanged.
`test_voxel_object_library_updates.gd` headless PASS: publication, selection/query/filter,
coalescing, hidden/reopen и observer cleanup. Renderer/Source-save/geometry не менялись.
Native main-copy + open library: catalog5136→373мс при startup; open5268→483мс;
ready36466→35105мс,128 entries/вариации/labels/tags/size/выбор/placement flag exact,
cached previews видны, pending0;132 Sources,258 metadata hits/0 misses/6 live reads.
Screenshot доказывает панель/карточки, не mouse feel и не вид всей карты (камера вне неё).
Scope/owners/evidence — [Производительность мира](docs/EMBER_WORLD_PERFORMANCE.md#доверенная-текущая-точка) → «Доверенная текущая точка»; полный save/3looks не повторялся.

Foliage material batch28.10: `test_detail_material_preparation.gd` Forward+ PASS: byte parity
с прежними lookup images, все ImageTexture независимы, preview не меняет соседа, новые saved
presets после смены process frame, разные layouts/пустые роли. `test_detail_preparation.gd`
Forward+ PASS: cold/warm exact transforms,3looks, mask/height/seed/size invalidation, stale cancel
и malformed cache rejection. Main-copy222 hits/77878 instances, transform dictionaries exact.
Save/Undo/schema не менялись; прежний полный цикл не повторялся. Scope/evidence — World Authoring.

Adaptive terrain geometry29.10: test_world_detail_policy PASS, curved mixed24576→12000 vertices,
225 physical ray samples/error budget, exact canonical faces/field, actual material weights,
borders/winding/holes, far v2 cache roundtrip/corrupt faces repair, sectioned collision/mesh offsets.
terrain_shape_update PASS in stable copy (working run encountered unrelated in-progress UI compile).
Native Forward+ main-copy full/adaptive/full PASS:7,99→5,97→7,99m vertices, grass buffers exact,
three collision shapes exact, full topology restore;512² control pixels equal. Warm352 hits/0 misses.
GPU change small, loading≈36s new cache/≈25s warm; no general FPS/startup acceptance.
No author save/history/schema changes; prior Undo/save not rerun. Scope/motion/resize/weak-PC gates —
[Производительность мира](docs/EMBER_WORLD_PERFORMANCE.md#доверенная-текущая-точка) → «Доверенная текущая точка»; no new maps/helpers.

Ground material distance29.10: test_terrain_material_distance PASS (early depth return/hysteresis,
existing fade change, shared uniforms/textures, independent base, actual preview light-profile update).
Native Forward+ material gates:512² parallel ground pixels exact;91 travel steps,0 unsafe far selections;
light/gray/fade updates and look1/2 fallback. Wide A/B/A18,3469→16,1817→18,3503ms GPU,
zero pending/jobs and393/393/393 publications at phase ends. Immediate material selections keep IDs.
Original aggregate probe asserted IDs before camera preparation finished and reports false; retain it.
Separate validation.json accepts only evidenced material gates, not a global preparation/startup fix.
100 author files unchanged; Source/physics/serialization/history unchanged. Manual motion/own map/
weak-PC OPEN. Scope/evidence — [Производительность мира](docs/EMBER_WORLD_PERFORMANCE.md#доверенная-текущая-точка) → «Доверенная текущая точка».

Editor distance policy28.10: test_world_detail_policy PASS (planar reduction, exact border/height/
winding, holes/mixed paint, full/far cache identity+roundtrip); terrain_shape_update PASS.
Native main-copy Forward+ PASS: camera travel/return, exact original instance buffers after unload/
full reload, far edit promotes full, restore complete Source parity;0 sphere preparations/bindings.
100 source files unchanged, no map save. All pending0; manual fast travel/3looks, RAM/VRAM and
resize/multiple viewports OPEN. Source/history schema unchanged, previous save/Undo gates not rerun.
Owners/evidence/remaining phases — [Производительность мира](docs/EMBER_WORLD_PERFORMANCE.md#доверенная-текущая-точка) → «Доверенная текущая точка».

Масштаб Source29.10: `tools/test_terrain_section_windows.gd` PASS —72/144/288/576м,
точные каналы окон/halo/границы/пропущенные секции/flow, ограниченное число адресованных
payloads, повторная validation после изменения, copy-on-write/Undo/Redo/save/reopen/discard.
`qa_world_scale_capacity.gd` создаёт внешние уникальные generated payloads и планы кандидатов;
это не render/FPS PASS. Земля editor проверяется отдельным gate ниже;
реальное население576м проверено отдельным gate ниже; runtime остаётся OPEN.
Owner/evidence — [Производительность мира](docs/EMBER_WORLD_PERFORMANCE.md#доверенная-текущая-точка) → «Доверенная текущая точка».

Ближняя земля/дальний пейзаж29.10: `test_terrain_residency.gd` — одинаковый idle fine set
при72/144/288/576м, budget/protection/return, coarse arrays без fine physics/fields,
границы соседних секций, отмена, outward fine/coarse seam closures и ограниченный query field.
Native Forward+ на внешнем576м:233/252/233/233 fine tiles,576 coarse sections;
освобождение mesh/physics/fields/looks, точный возврат faces/field,4 stale jobs,
обычный edit/Undo/Redo/save/reopen/discard и реальный physics ray vs floor PASS.
Followup отдельно сохраняет offscreen authoring `solid` с `physics_ready=false`,
не накапливает resident fields; малая main остаётся на прежнем пути.
Визуальный стык/движение требует авторской оценки; населённый FPS, Source I/O и все облики OPEN.
Evidence/границы — [Производительность мира](docs/EMBER_WORLD_PERFORMANCE.md#владельцы-и-работающий-путь) → «Владельцы и работающий путь».

Массовая расстановка576м29.10: `test_grove_scaling.gd` PASS —576 объектов,66 в одной
области, bounded cache16, повторяемость, Apply/Undo/Redo/validation/save/reopen/discard.
`test_terrain_smooth_placement.gd` PASS — dense/sectioned опора через шов, вода/уклон,
защита ручных правок, совместимость provenance v1/v2; `test_grove_snapshot_storage.gd` PASS.
`test_tree_look_preparation.gd` PASS — shared mesh identity трёх обликов, независимые
material overrides, canonical fingerprints, PRE_SAVE/snapshot и invalidation Source.
Native Forward+ внешний576м:859 props (503+65 деревьев,291 камень),6 общих tree meshes,
11 независимых проверок опоры, пересечения, отсутствие ложной защиты, один Undo/Redo,
Plan save/reopen и population snapshot/discard PASS. Генерация47,04с, peak cache16;
Baseline: finalize0,94с и apply4,72с синхронно; порционный путь проверен ниже.
Evidence: `C:/Users/novos/Documents/Codex/2026-10-29/ember-grove-scale/`.
Native массовый запуск без shared geometry ранее дал device lost; финальный PASS не закрывает
общий shutdown/TDR gate. Авторская оценка, трава, object residency/LOD и населённый FPS OPEN.

Порционное подключение29.10: `test_grove_publication.gd` PASS — промежуточные экземпляры
не попадают в native packing/Grove snapshot; Ctrl+Z/clear/stale возвращают исходный batch,
ручная правка сохраняется; bounded/sync provenance совпадает; один Undo/Redo, validation,
save/reopen/discard PASS. `test_terrain_plan_grove.gd` PASS; obsolete64 cap expectation обновлён.
Native Forward+ после реального preview:859 props /437 кадров, max149,65мс /34,79с всего,
одна EditorUndoRedoManager entry, Undo25мс/Redo15мс, Plan save/reopen/snapshot discard PASS.
Холодная подготовка модели до1,13с, неделимый deferred look камней и ручной input OPEN.
Owner/evidence — [Производительность мира](docs/EMBER_WORLD_PERFORMANCE.md#владельцы-и-работающий-путь) → «Владельцы и работающий путь»; населённый FPS не принят.

Object detail29.10: `test_object_detail_residency.gd` native Forward+ PASS — bounds hysteresis/
protection, exact base triangles/attribute sample, immutable Source/physical surface,
actual carrier release, save strip/return/alternate looks/manual Mesh replacement protection.
`test_tree_look_preparation.gd` native warm PASS: shared carriers/independent materials/
first switch/provenance/snapshot/invalidation после weak-cache изменения.
Большой native editor A→B→all-far→A PASS:859 roots, last-user release, selection protection,
signature/pose, actual shadows, snapshot save/reopen, native pre/post-save, move Undo/Redo/discard.
Paired wide full→managed:23,761→13,846мс, visible25,87→16,74млн, living carriers152→2;
отдельный return object step785,8мс OPEN. Owner/условия/evidence — [Производительность мира](docs/EMBER_WORLD_PERFORMANCE.md#владельцы-и-работающий-путь) → «Владельцы и работающий путь». Это editor look0; manual art/input/weak-PC и общий FPS OPEN.

Detail return29.10: `test_object_detail_return.gd` native Forward+ PASS — old≈800мс→25–28мс,
exact returned faces/face pixels, signature/physics, weak carrier release, CPU/read cache invalidation.
`test_object_detail_residency.gd` native regression PASS. Native576м all-far→A object step26,928мс,
прежняя signature не меняется. Grass:2304 painted patches4м через12м; A/B/A21 resident,
644/702/644 tufts; old MultiMesh release / identical returned buffers /21 disk hits / mask save-reopen PASS.
После полного ground settle paired frame median15,706→15,730мс; это sparse grass, не dense acceptance.
Dense grass29.10:16–64 пучков/м²,21 resident /10 650 tufts; cold ready23,177→6,296с.
21 cache files трёх обликов byte-identical; native A→B→A release/exact return/21 hits PASS.
`test_grass_local_candidates.gd` red→green25 700→0 distant calls; `test_detail_preparation.gd` PASS.
`test_object_detail_brush.gd` native с пустым кэшем PASS: physical roots/цветы/3облика/история/save.
Старт/движение29.10: shader/template async + pipeline warmup в existing startup gate;
новых grass compilations42/1→42/1, cold frame170→50,637мс, private bindings/pixel parity PASS.
Travel footprint old FAIL/new PASS; seam arrays/exact physics/one overview per region PASS.
Ground/grass shared8мс, brush4мс, fine halo в прежнем budget≤384. Native5м/с:194/194 near ready,
pending grass после остановки0; общий moving frame до87мс ещё OPEN.
Native editor surface cold/warm/exact physics/3looks/live/latest edit/discard PASS (full-detail fixture).
Headless startup PASS; native error-window height после autowrap reflow PASS
(`test_voxel_editor_preparation.gd`, ember-dense-meadow/popup-after.log).
Сплошной луг: test_detail_sleeping PASS — bounded polling/fair queue/priority/ancestor disable/
free/release/reattach; test_detail_budget_phase red→green — continuation после Node._process.
Detail cache regression PASS; native shader regression PASS, включая rim off/on common wrapper.
Цель автора120FPS/2560×1440 native с переменными углами; прежнее≈11% покрытие не её приёмка.
Full25848-patch fixture технически PASS:231 resident/191332 tufts, плотность64/10/8 сохранена;
history/preview-discard/save-reopen/exact wind roots/return PASS. Кадр≈25мс, motion до142мс,
0 unready near:120FPS/полная плавность/вид не приняты. Evidence — [Производительность мира](docs/EMBER_WORLD_PERFORMANCE.md#доверенная-текущая-точка) → «Доверенная текущая точка».
test_detail_budget_progress red→green: unrelated UI не съедает allowance, ground priority/continue.
test_detail_visible_priority red→green: near bands/FIFO, author priority, camera rerank,
residency/Undo cancellation и немедленный explicit cancel без следующего budget turn.
test_ground_foreground_budget red→green: missing core8мс, ready core с queued scatter4мс,
без scatter снова8мс. Это scheduling checks, не доказательство120FPS или полной camera coverage.
test_terrain_resident_slots red→green: release/reuse не меняет tree, освобождает mesh/material/
physics; exact faces,32 повторных прохода, protected overflow bounded, hosts не сериализуются.
test_grass_footprint red→green:23232 решений exact против прежних8 floor probes, без full query
Dictionary, holes/edge/sculpt/origin/scale/rotation/tilt. detail_preparation/local_refresh PASS.
Native576 cold scatter:105,008→82,740с,239/239 buffers exact;FOV40/70,5 tiles/14 support samples,
pending0 после движения. GPU≈14,34мс/движениеp95≈24,16мс:120FPS и stalls остаются OPEN.
Evidence: D:/Codex/ember-cold-scatter-20261029/comparison.json; stage files восстановлены по SHA.
test_detail_startup_gate: реальный WorldCanvas удерживает cover для незавершённого resident
reserve, снимает после готовности и не ждёт sleeping world; gate не сокращён.
Throughput30.10: test_smooth_sample_parity65536 exact; test_detail_worker_parity grass/flowers/
3looks/holes/water/borders/origin/transforms byte-exact, physical candidates/blocky/tilt fallback.
test_detail_worker_lifetime:2 admissions, cancel completed/unfinished, remove/readd/free/release,
await cleanup пока host жив, join/ready ровно один раз. test_detail_sleeping_admission:25000far, broad-bin false-positive reject,
entering prepare radius/увеличение footprint без старого bounds cache,
near/moved/oversized/free/disabled policy; legacy red2048far probes, новый green0far probes.
31.10 `test_detail_sleeping_epochs` RED→GREEN/native Forward+ PASS:после полного
sweep неизменные runtime inputs не перечитывают512footprints (128polls65386→0reads),
anchor внутри того же bin/resize/move/new host/policy changes запускают admission.
Отдельный paused ancestor RED→GREEN:resume повторяет незавершённый admission без
policy change. Editor/custom projection без authoritative epoch сохраняет periodic
fallback;legacy broad-bin admission,owner lifetime,resident poll epoch PASS.
Native pattern-library Undo/Redo/save/reopen PASS;полный dense/cold/release/return
и clean timings — у Performance owner,не приёмка120FPS/ручной кисти.
Preparation cache/Undo/reopen/mask/seed/size/cancel, local refresh и no late tree nodes PASS.
Native576/859props/25848patches/64-10-8/native1440/TAA: Player82,782→56,830с. Immediate4с
east40+4сwest70 без wait_grass, required circle проверяется каждый process frame: pending0/0,
опора без пропусков. Первый east40 — тот же путь, где контроль имел13pending; второй изменён
на возврат, чтобы не упираться в prop, не парный A/B старого второго east.
212/212 overlap buffers exact не доказывают полного unload-return. GPU≈13,2мс, motion
wall p95≈23–26мс/max40мс с QA checker:120FPS/остаточные stalls/manual/weak-PC OPEN.
Wide steady40/70 (distance960/polar1,05, тёплый scatter cache) PASS после settle, GPU14,3/13,6мс;
это не immediate cut. Worker parity native Forward+ PASS со sleep0/vsync off в fixture.
Evidence: D:/Codex/ember-scatter-throughput-20261029/native-final/runtime576-result.json.
Последняя проверка стоимости30.10: test_grass_sleeping_surface_notifications25000far→0probes,
near overlap/outside/return PASS; preparation/local refresh/worker lifetime PASS.
ObjectLOD: test_object_resident_lod RED→GREEN — завершённый worker публикует carrier
для resident-дерева,look0 refresh его сохраняет;Source/collision/preview/manual replacement/
выход из streaming/look1/2 guards PASS. test_object_lod_worker_lifetime:pending не блокирует
main,source.changed/disabled discard,exit join и metadata PASS. Native object_detail_residency/
object_detail_return:faces/channels/materials,physics/authoring fingerprint/save/return PASS.
Native LOD0 pixel control дуб/берёза,near/far,TAA OFF:2exact,2по1pixel±1/255;A/A exact.
Связанный dense576/native1440p/95м gate и актуальные времена — у performance owner ниже;
ручное движение камеры/тени и минимум120FPS остаются OPEN.
GPU A/B/A shadow/unlit/hide — diagnostic, не visual acceptance; качество/плотность прежние.
Прежний reference и условия сравнения — [Производительность мира](docs/EMBER_WORLD_PERFORMANCE.md#доверенная-текущая-точка) → «Доверенная текущая точка»;
D:/Codex/ember-gpu-stalls-20261030/ (reference max252/426мс после sleeping/ObjectLOD fixes).
Последний far-preparation gate: test_object_far_preparation native — async Source load,
legacy/packed worker arrays+Image bytes exact для rock/cliff/house, volume без unused Source read,
physical shape/author fingerprint/save/return/Source invalidation PASS.
test_object_far_preparation_lifetime: nonblocking pending, changed/disabled discard, exit join
CPU+threaded ResourceLoader, CPU cache без GPU carrier PASS. Existing object_detail_return и
object_detail_residency native PASS. Root native без импортированных textures не принимался;
реальный PASS — imported QA stage (CWD/root не импортировался).
Последний material-stalls gate: test_material_height_cache cold/disk/corrupt/private/input/params PASS;
test_object_depth_sun25k, preorder/internal/replacement/missing PASS (5,7мс→7мкс local median).
test_object_depth_preparation native:3 layers/mips byte exact, source immutable, warm cache,
private numeric texture/image и live amplitude isolation PASS. test_object_depth_lifetime:
pending/edit/disabled/exit/signals, source handoff/last-consumer release/removed host PASS.
Far parity initially red на isolated source-identity churn, исправлено; final native far parity
и object_detail_return PASS. compact_material_patterns native: drag/Undo/Redo/discard/PNG/
variant/save-reopen/atlas/finish/side/legacy PASS. Авторский ручной view/input OPEN.
Native576/859props/25848patches/64-10-8/native1440/TAA: warm Player27,169→25,251с;
initial194953instances прежние, immediate required missing0/0/floor PASS. Baseline p95=46,742/41,517,
p99=53,398/48,411,max112,375/52,823мс →final p95=33,392/26,621,p99=40,439/33,940,max47,037/35,812мс.
Motion100%frames>8,33мс, includes QA checker. GPU steady14,346/14,621мс;120FPS/manual OPEN.
Конечные игровые camera poses немного различаются: GPU не выдавать за paired A/B/A выигрыш.
Evidence D:/Codex/ember-material-stalls-20261030/final/result.json и comparison.json; далее
GPU shadow receive/filter/ground и точная причина остающихся≤47мс stalls. Shadow cache не внедрён.
Свет30.10, steady GPU gate: --remote-debug local:///visual profiler/RD timestamps PASS;
actual native1440/TAA/FOV40/70 + wide960/polar1,05, fixed camera и primitive counts в паре.
Shadow render median0,667/0,493мс, opaque10,709/10,982мс; кэш генерации не основной резерв.
Автор после кадров одобрил filter2 при прежнем angular1,4/blur1/distance1600; main изменена
одна строка, остальные bytes сохранены. Near40/70 GPU14,598/14,653→9,613/10,090мс,
wide40/70=14,312/13,205→11,004/10,473; p95выбранного10,369/10,976/11,971/11,371мс.
Это не120FPS и не gameplay/stall acceptance. Старый stage template не включает7 новых
unrelated main mechanics nodes; full current main с ними этим snapshot не принимается.
Focused external test-shadow-filter.gd: OptionButton/history1action/Undo5/Redo2/save/reopen2/
discard/new-owner и softness/range/shadows invariants PASS. Production shader trials не приняты.
Evidence D:/Codex/ember-light-shadow-20261030/. Manual edges/движение и рывки — следующий gate
по решению автора; плотность и разрешение не снижать.
Аудит и prep30.10: targeted cache/rotation/packed/living/physical/return fixes сохранены.
`test_detail_cache_maintenance`:1000files, nonblocking admission,coalescing,cancel/join,disk budget,
не-cache files сохранены. `test_detail_preparation`:cold signature вdispatcher,cache/3looks/
mask/seed/size/source change/cancel/reopen PASS. `test_detail_worker_parity`:pure/mixed object
cells byte exact3looks при yaw/nonuniform transform,live preview fallback. Worker lifetime PASS.
`test_detail_fade_culling`:complete/partial fade boundary,return,disabled policy,anomaly guard;
native A/B/A70°4,03→3,09млн submitted triangles; temporal PNG noise не является pixel-exact gate.
`test_world_detail_policy`:prepare29,fades16–24/release32;budget phase после nodes без double connect.
576м/859props/25848patches/все7mainnodes,native1440p scale1/filter2: warm timing отдельно от
cold-cache correctness на≈95м out40/back70. Cold required0/0,floor0/0; release/return258/258 и
272/272 byte exact. Новому cold stream gate соответствовал исходный fail61/32. Budgets2/4мс
провалили coverage и отклонены; production сохраняет8мс. Actual camera/PNG проверены.
Warm wall p9523,1/24,7,max32,5/36,7;GPU p959,2/9,1мс.120FPS/stalls OPEN. Whole-frame
audit Astra/high: отдельные OFF/ON/OFF и QA-only main callback scopes на том же dense gameplay
маршруте40/70, native1440p. Native-call profiler заметно искажает CPU; его inclusive times не
считать ожидаемой экономией. Native capture ON дал4CowDataerrors, без native capture повтор
дал0runtime errors/329warnings; причина в engine не доказана.
GrassPatch clean fast path/bounds memo реализован. `test_grass_clean_resident` red→green:
clean callbacks пропускают readiness, surface/transform/size invalidation остаются; bounds
следуют parent rotation/nonuniform scale/unit/mode/reparent/reentry. Native local sculpt/paint/
source restore и cache/preview/cancel/3looks в `test_grass_local_refresh`/`test_detail_preparation`
PASS; fade и sleeping admission PASS. Старый `test_detail_sleeping` использует несовместимые
Node3D stubs без policy/map/area и падает одинаково до/после; это не regression этого fix,
его PASS не заявлен. Actual dense1440p clean A/B: median19,32/19,10→15,86/15,53мс,
p9528,40/29,34→24,12/26,23; cold required/floor0/0, unload/exactreturn258/258.120FPS OPEN.
Terrain upload indexing31.10: `test_terrain_render_indexing` RED→GREEN/headless/native
Forward+ PASS. Flat/slope/mixed base и все native LOD triangle attributes exact,
thresholds/canonical layout/physics payload без изменений. Main terrain/shadow pixels
на двух LOD biases и seam pixels exact. Worker supplies compact upload;commit drops
temporary upload. Native `test_world_detail_policy`/5120-ray HeightMap+affine fallback/
`test_terrain_smooth_tools` existing8tools,Undo/Redo,Save/Reopen PASS.
`test_detail_frame_budget` native PASS:existing cover5мс→revealed3мс,active brush
сохраняет5мс context/4мс cap,charged foreground subtracts once,recreate/reparent,
actual WorldCanvas readiness getter. Integrated576m native cold/release/return PASS,
no absent/pending/floor gaps,281exact;120FPS/wide70/rare stalls/manual остаются OPEN.

Priority fairness31.10: `test_detail_turn_fairness` RED→GREEN/headless/native PASS.
Near waiter не вытесняет дальнего владельца bounded slot;реальные digest и два read
slots завершаются. Cancel requeued turn,has_pending_work и release во время dispatch
PASS. Native cache-read/material-async/preparation/pattern-library regressions PASS,
включая live profile/Undo/Redo/save/reopen. Static startup control timeout90с→21,823с;
это deadlock fix,не общий FPS benchmark. Dense result — Performance owner.

Material digests31.10: `test_detail_material_async` RED→GREEN/headless/native PASS —
slow80ms не блокирует producer(native44us),идут кадры,same-second changed/deleted/
recreated saved profile меняет реальные bound pixels;pre/in-flight cancel,один slot,
queued consumer progression и teardown/join. `test_detail_material_preparation` native
сохраняет byte/uniform parity,private images/textures,texture revision/weak bank и bounds.
`test_detail_preparation` дополнен реальным GrassPatch profile edit во время role IO:
последующее publish сохраняет preview;layout/source guard,cold cache/source/seed/mask,
reader exit и native pattern-library Undo/Redo/save/reopen PASS. CPU gain не принимает
120FPS;общий dense/cold/release/return и clean timings — Performance owner.

Saved material/budget30.10: `test_detail_material_preparation` native parity/private textures,
6packed artwork channels, unchanged imported texture identity, same-second user:// file save,
delete/recreate, bounded16/context и release PASS. Native `test_detail_preparation` PASS.
`test_terrain_whole_budget` red→green: observer9000мкс раньше charge87мкс/admit1, теперь
charge≥9000/admit0; обычный кадр admit1. `test_detail_budget_phase` PASS. Общий8мс не снижен.
Dense cold A/B с одинаковыми QA scopes: material_patterns single-call p953,854→1,082мс;
whole wall median19,343/18,043→18,462/15,832;p9526,887/29,192→25,420/25,797;
max40,188/45,049→72,598/55,021мс. Max не улучшен;54,158мс внутри Preparation turn требует
отдельных write/resume scopes, причина не доказана. Native runtime errors0/329existing warnings.
Fresh cold correctness без scopes: required0/0,floor0/0, unload/exactreturn258/258;120FPS OPEN.
Floor/resume30.10: `test_object_floor_signature` red→green: signature не строит bins;
faces/slots/roles hash прежний; actual floor height/role, disabled/layers, mesh/shape replacement,
volume collider faces, yaw±45/tilt/nonuniform scale/negative coordinates/cell-size changes PASS.
512м quad first-query≈6,4мс→6–8мкс; один запрос готовит один bin, не всю площадь.
Native `test_object_detail_brush`:8192triangles/104instances,3looks/roots/Undo/Redo/save/reopen/
discard PASS. `test_detail_worker_parity` extended red→green: resumed object queries только
в budget turn;3looks byte exact/mixed/preview PASS. Lifetime/cancel/free и preparation PASS.
`test_detail_ground_support` red3missing corners→green0 при той же capacity384; policy lead30,
fades16–24/release32. Scope: default4м painted patches/tuft1; более крупные footprints — отдельный gate.
29м версии давали1missing;30м без ground guard оставляли2outside-visible patches в infinite wait.
Эти варианты отклонены. Accepted cold30+support: required0/0,floor0/0, queue settles, unload267/267,
return265exact+2unused hysteresis outside prepare. Final timing p9526,37/26,35→25,13/26,79,
max50,63/40,94→61,38/46,72; общего FPS gain нет. Job poll max8,55→0,40мс/signature17,36→4,76.
Native runtime errors0;3new intentional integer-index division warnings (332total vs329).
Старые72мс не воспроизведены, причина не установлена; gate остаётся OPEN.
Render frame30.10: native test_water_floor_capture_demand — fine publication/dry Source replacement,
hidden/layers, underwater/return, fresh first pixel, far overview без Regions, empty/return/clear,
detached controller callback release PASS. Main-copy79wet consumers/capture ALWAYS/native1440p.
24 grass/flower/ground/stone RGB cases с прежним shader body: exact0 changed pixels. Dense576m
near40/70+wide40/70 A/B/A all-viewportsGPU median≈8,8–9,4→8,2–8,6мс; B p958,6–9,1.
Full gameplay route:2110/2244frames, wall median17,805/16,184,p9525,288/25,602,
max40,645/49,018;0runtime errors/332existing warnings. Performance120FPS/ручной вид OPEN;
этот timing route не повторял полный per-frame coverage/unload exact gate.
Prepared roles: test_detail_material_preparation расширен — texture bytes/non-texture uniforms,
private texture+preview+rim, cross-shader payload, saved SHA/remove/recreate, texture.changed/PNG
bank refresh, bounded16 CPU payloads, no retained GPU bank after last consumer, release PASS.
Native test_detail_preparation3looks/cache/mask/height/seed/size/cancel и worker lifetime PASS.
Native accepted8 после cache: required0/0,floor0/0, release267/267, return265exact+2unused;
spatial checker выбирает консервативных кандидатов и применяет прежний точный radius test.
QA4мс бюджет отклонён:1missing и back route timeout; production8мс прежний.
Terrain shadow water-pass regression: forced refraction/reflection bit в shadow projection
RED error0,00754/0,01210 → GREEN0/0. Реальные водные camera clipping + visible caster negative
controls PASS. Два discard теперь !IN_SHADOW_PASS; sun/filter/bias не менялись. Авторское
мерцание self-shadow зелёного рельефа в движении ещё требует live оценки.
Final post-shadow-fix native gameplay:2091/2285frames, wall median18,252/15,798,
p9525,637/24,502,p9928,984/28,746,max278,305/71,395; rootGPU median7,474/8,402,
p959,074/10,279.0runtime errors/332existing warnings. Frame2313 late stall278,305мс —
renderer setup241,516мс того же кадра; причина внутри setup не доказана.
Clean A–B–A warmed wall12–13,5мс,p9522–23,5; row build≈0,065мс, не главный limiter.
Water core selection revision cache:40 reference cases/halo/hysteresis/edit и wet streaming
release/return/cancel PASS. Observer selection semantics сохранены. CPU dry576core scan
0,390→0,00131мс/call; same warmed clean route median12–13,5→12–13,4мс,
p9522–23,5→19,4–20,8;max51,7мс.0runtime errors/332existing warnings.
Evidence: D:/Codex/ember-frame-accounting-20261030/selection-clean-valid/,
selection-comparison.json, selection-cpu.log, streaming-valid.log. selection-clean/ INVALID.
Native preflight: actual FollowCamera FOV40/70,viewport2560×1440,scale1; native70.png просмотрен.
Dry steady _prepare_water median0,010мс/p950,014; RAM3,93GB/video1,87GB sample, не long gate.
QA430paths restored exact SHA; evidence native-preflight/, stage-restored.json.
Current foreground5ms/HeightMap/poll epoch: test_detail_shared_budget (active debit/prior debit/nested
count once), progress despite unrelated UI, phase/whole-ground, epoch+closed-context/projection
replacement, rotated/negative/affine bounds100cases, native preparation3looks/cancel PASS.
Terrain height-map5120rays: normals/heights exact on fixture, real dense tile maxheight≈0,00000394,
normal0; cold/cache/section offset/holes/walls/nonuniform/deform fallback PASS. Canonical field unchanged.
Dense final5 native1440p/FOV40→70 with real Player: absent0/0,pending0/0,floor0/0,release267/267,
return265exact+2unusedhysteresis,322heightmaps. Legacy pending flags are NOT visible-hole proof;
coverage-final/4ms actual absent≤7 near20,8–24m rejected,611ms outlier source unproved (screenshots possible).
Final alpha-gameplay after own out/back warmup, normal TAA/quality/density: median10,804/11,737,
p9515,024/16,177;p9917,184/18,430;max21,142/36,762;76,56/85,90%frames>8,33;325heightmaps.
0runtime errors; snapshot GPU A/B/A only0,2–0,5ms gain. Alpha RGB exact FOV40/70 in QA TAA OFF;
TAA ON retained in game. Snapshot GPU≈9,1–9,5ms still exceeds120FPS budget. No performance PASS.
Evidence D:/Codex/ember-frame-budget-20261030/: final5/, alpha-gameplay/, alpha-probe/, alpha-pixel/,
heightmap-affine.log, epoch-lifetime.log, shader-final.log, preparation-final.log, *-accepted.log.
Actual camera/native resolution/scale read each clean leg. Long memory, cold caches, wind/mixed,
manual/editor brush feel and green-slope self-shadow remain OPEN.
Stage430recorded paths restored exact SHA,Root unchanged; stage-restored.json. Budget progress fixture
removed a redundant process_frame connection; accepted log has0errors. Native alpha image inspected.
Current terrain feature programs: native test_terrain_material_features validates real scene/profile
commands (light/gray/voxel/anomaly/profile enable/cancel), same uniforms/texture RIDs, private
bindings/shared programs, all3looks ground+cover render parity and ResourceLoader source equality.
Dense576 acceptance at native1440p/TAA/FOV40→70: same-camera A/B/A + cold-scatter coverage/release/
return + minimal paired gameplay. Result/current numbers/open gates —
[Производительность мира](docs/EMBER_WORLD_PERFORMANCE.md#доверенная-текущая-точка).
Evidence D:/Codex/ember-material-path-20261030/: acceptance/, acceptance.log,
production-pixel-parity.json, features-mixed-final-test.log. Full120FPS/stalls/manual/wet/mixed OPEN.
Evidence продолжения — D:/Codex/ember-active-frame-20261030/. Evidence —
D:/Codex/ember-render-frame-20261030/; owner — [Производительность мира](docs/EMBER_WORLD_PERFORMANCE.md#доверенная-текущая-точка) → «Доверенная текущая точка».
Manual motion/native PNG reimport/cold total startup/weak-PC/долгая память OPEN.
Подробности/приоритеты — [Производительность мира](docs/EMBER_WORLD_PERFORMANCE.md#доверенная-текущая-точка) → «Доверенная текущая точка».



Ранний reveal75,7с/32–42pending оставлен только как отклонённая проба в ember-startup-reserve-20261029.
Native minimal25k field: add node≈981мс/25848 property calls; reuse slots≈0,9мс/0 calls PASS.
Контроль sleep0: first grass68→10с/core114→18с, полный local193→98с; cold p95337→33мс,
max473→368мс. Это editor fixture,120FPS не достигнуты. Native full source buffers231/231 exact;
history/preview-discard/save-reopen/return PASS, ground pending/jobs0 перед сравнением.
Legacy pilot projection/save-reopen и travel seam/budget/physics PASS. Ручной main/runtime OPEN.
Evidence — D:/Codex/ember-frame-phases-20261029/ (control-before/after,full-after,slot-probe).
Astra/high audit29.10: legacy harness FOV≈70 при metadata40; старые FPS не принимать как FOV40.
Final FOV40/2560×1440: editor near≈22/wide≈27мс GPU; native prepared snapshot≈18,8мс,
camera/draw calls/visible+shadow primitives совпали, image MAE0,252/255. Не gameplay/streaming.
Две DEPTH-записи ground shader:18,89→13,10→20,20мс GPU, near frame MAE0,238/255;
drift1,31мс, механизм early-Z вероятный. Более дешёвый shader path требует своего gate:
перекрытия персонажа/земли/стыки/вода/depth effects. Код игры аудит не менял.
Terrain/water+grass materials/shadows/pixel count controls — World Authoring, «Сплошной луг29.10».
QA restored/85 hashes unchanged PASS;120FPS не достигнуты. Evidence — D:/Codex/ember-astra-audit-20261029/.
Новый общий performance gate по решению автора29.10 — [Производительность мира](docs/EMBER_WORLD_PERFORMANCE.md) → «Текущие решения и gates»:72/144/288/576м, full coverage64/10/8, FOV40/70/наклонный wide,
cold/move/стыки/A→B→A/memory, plane/slope/mixed geometry controls и настоящий player route.
Editor/snapshot/gameplay раздельно; native1440p/120FPS с учётом p95/p99/max/stalls, не среднего.
После значимых правок фундаментального пути — его stress и связанные correctness regressions;
локальный unit/helper PASS не закрывает общую систему. Порядок/детальная матрица — только у owner.
Команда реализации29.10: test_terrain_cheap_profile headless/native PASS; material-distance PASS;
native foliage24/24RGB exact с реально развёрнутым include-reference. Preset/UI/history/save
путь принят технически. WORLD_DETAIL_POLICY: nativeLOD/actualrayerror/cachecorrupt/roundtrip/
indexedlooks/height-update PASS; smooth uniform/cartoon/tools PASS. Nonblend defect0LOD исправлен:
red→green +persistent assertion и независимый native фактический4096→2048→1024→512 PASS;
fine colors/layout/physics сохранены, true-mode arrays/key битово прежние.
Terra: настоящий main-copy Player/physics/nav/3looks native PASS, GPU≈12,8мс/p9513,47;
dense canonical true editor:25848patches/859props, sourcepalette/12seams/release0/exactreturn PASS,
actualLOD2048→1024→512. GPU near40≈12,76/wide40≈16,26/near70≈15,22/wide70≈14,60мс;
разные poses/wind, не парный A/B. Все sampled GPU>8,33; performance OPEN.
True-field motion wall p95≈27–29/max139–162мс, missingnear0; peak11GiB private/minfree6,34GiB.
Источник — D:/Codex/ember-world-integration-qa-20261029/ (gameplay-result,blend-true/result,lod-render).
Full576 gameplay/Low2 control ещё проверяются; snapshot и ground-only startup их не заменяют.
Water startup576: test_water_runtime_extent red→green PASS, old528м guard заменён общим
Sections cap576м; Regions неизменён. Последние wet22/23/core9216/halo9312/sea/shore/waveheight/
missinghalo/no-dense/rootfields и startup-ready PASS. Новые boundary assertions preview
отличают576valid/>576/malformed; полный native runtime576 повторяет Terra после fix.
WaterRegions streaming: реальный runtime576 достиг480012мс сготовойземлёй/лугом, Playerне создан,
водныйworkerжив/cacheрастёт/committed0 — coldwholeworldprep, неdeadlock/OOM. Новый
test_compact_water_streaming red→green: initialbatch2/required3wet/nearready, canceldeparted/
staleedit/reentry/dry0fields/missinghalo/sea-lake/waves/bindingnear1far0 PASS; globalinlet/edit/Undo PASS.
Actual dry576 water-owner2,134с/0windows/0bytes; focused trueentry22,140с/Playerphysics PASS.
Finalorigin/extent/contactarrival+release/unrelatedbatch/COW snapshot PASS; fullnative576должна
принятьTerra отдельно. Evidence — D:/Codex/ember-water-streaming-foundation-20261029/.
FinalTerra native576 completed: Source/859props/25848patches/64+10+8, Playercreated105,333сcold,
waterready/near239patches195985instances/pending0, forward5/back8tiles/support14/14+15/15PASS.
GPUFOV40median14,382/p9515,112/p9915,347; quality5→2→5=14,382→9,741→14,363.
Остальные40/70near/wideposes GPU≈13,9–14,65мс, разныйQAwind;120неприняты.
Wallmotionp95≈24–25/max128,111мс; overlap212/212buffers exact, НО9,8мoffstart/нетreleaseIDs:
gameplayunload→sameanchorexactreturn неPASS. Editorrelease0/exactreturn остаётся отдельнымPASS.
Wetstream nativeappearance/ручноеощущение/arbitraryteleport ещёOPEN. Source576сухой.
ФонHoshiCompanion оставлен; собственныеengines/monitorзакрыты,209stagepaths restoredSHAexact.
Evidence runtime576-result.json/runtime576-streaming-native.log/stage-preservation.json в
D:/Codex/ember-world-integration-qa-20261029/. Локальные успешные наборы без причины не повторялись.
test_grass_property_refresh red1,731с→green0,431с на5000 списков; test_grass_mask_storage PASS:
read-only snapshot/alias isolation/legacy text/explicit zeros/types/invalid legacy/corrupt blob/Node duplicate.
test_grass_preparation_tree red4→green0 late nodes; cache/sleeping/brush rebase и native physical
grass/flowers/3looks/history/save regressions PASS после последних изменений. Полный suite не запускался.
Вечер сохранён в main, native polygon просмотрен; ручной main/вид/ввод OPEN. Owner/evidence — [Производительность мира](docs/EMBER_WORLD_PERFORMANCE.md#владельцы-и-работающий-путь) → «Владельцы и работающий путь». Успешные terrain/object regressions целиком не повторялись.

Editor no-sphere28.10: native main-copy profiling PASS,0 sphere preparations/bindings,
222 scatter hits/77878instances; two view captures + one near A/B/A grass/flowers hide/restore.
GPU19,685→16,110→19,677мс, original draws/primitives restored; source100 files unchanged.
All samples unfocused/1844×1123, not an .exe comparison or mouse acceptance. Production code unchanged;
no save/history/full regression rerun. Evidence/limits — [Производительность мира](docs/EMBER_WORLD_PERFORMANCE.md#отложенные-сборка-и-сфера) → «Отложенные сборка и сфера».

Windows prepared build28.10: standalone release .exe main, clean user profile, sphere forced in memory:
1333 shipped hits/0 misses/0 local hits,324tiles/222patches/77878instances/702bindings, all queues0,
no runtime ERROR. One current character placeholder warning documented. Cold/warm logs preserve focus;
warm unfocused is not strict A/B. Native screenshot is one game camera, not complete art/controls acceptance.
`test_world_prepared_cache.gd` headless PASS:7categories/empty-local/no-copy/custom-isolation/names/counters.
`test_terrain_prepared_bundle.gd` headless PASS: previous CLI/checksum/corrupt/traversal/version.
`test_world_export_materials.gd` headless PASS: derived overrides+surface materials only, private Mesh,
geometry/metadata exact, source/art materials unchanged; actual cliff+house fresh .scn reopen PASS.
`test_compact_world_startup.gd` Forward+ PASS: cover/player waits for pending foliage, then former
water/camera/input/plain/waterfall/cancel gates. Editor save/history unchanged; broad suite not repeated.
Main/Source protection100 files unchanged. Limits/owners/evidence — World Authoring → Windows-сборка.

## Внешний mesh28.10 — первый статичный камень

`tools/test_external_mesh_source.gd` headless: pristine/legacy owner protection, sculpt/paint/material
mapping invalidation, invalid provenance path, Save/fresh reopen original+edited derivative, original
hash immutable. Only user:// roundtrip; requires the published first external Source fixture.
Native main-context capture (evidence path in World Authoring): existing Session open → side Remove →
Undo/Redo →3 displays → Save/fresh Source/scene-copy reopen → continued sculpt/Discard.
After Save, edited prop never substitutes pristine GLB. Same collider across3 looks; physics ray
and prop.floor sample match. Existing `test_volume_smooth -- --native` guards ordinary voxel props.
Publication: existing catalog IDs lists asset; main has ExternalCoastalRock at(-40,15,862), no new map.
Local anomaly: `tools/test_external_mesh_anomaly.gd` in Forward+ PASS. Real small-map preparation
discovers the published external StandardMaterial prop; original UV/albedo adapter vs Standard on
same geometry mean RGB error≈0.000012. Both local looks/inside/boundary,2 distances/angles,30-frame
movement per look preserve instance/mesh/material/targets (0 builds); global switch/disable restore
the original owner/mesh/material. Existing Map cell size/levels reach adapter. Canonical collision,
original texture and GLB hash unchanged. GPU morph vs independently frozen geometry light/shadow
mean RGB error≈0.000000069; existing test_world_anomaly_surface_light native PASS/0 changed pixels.
Source/history/serialization unchanged by the material adapter; no repeat of successful Save matrix.
Scoped main-context captures prepare the sphere only on this rock, excluding distant terrain/gameplay; full main startup,
F6/mouse/artist acceptance OPEN. Reprepare tool refuses dirty derivative; no forced author overwrite.
Adapter evidence: Documents/Codex/2026-10-28/ember-external-anomaly/{targeted,native-regression,main-capture}.log.
Evidence: Documents/Codex/2026-10-28/ember-external-rock/{capture,source,physics,legacy-native}.log.

## Слои камня Б25.10 — editor-перенос выполнен, ручная приёмка OPEN

Дополнение28.10: тот же test_stone_material_layers проверяет stone_weathering_enabled default-off,
preview/Undo/Redo/Save-copy/fresh reopen/discard и сохранение остальных полей. Main-context on/off
near/far +3 looks/collision PASS; общий parallax shader двух bark consumers компилируется.
Evidence/границы — Terrain Authoring → «Связная фактура стыков28.10». Мышь/сфера OPEN.


`tools/test_stone_material_layers.gd` native PASS: legacy opt-out/finite validation,
два видимых stone-only блока, независимые switches/width/strength/pattern/tint preview,
Undo/Redo, Save-copy/fresh reopen/discard, прежние PNG/depth/rim, form_pull0 и cached
look1/2/0. Slider input сохраняет mesh/preparations; старый A/B/C shader entry компилируется.
`tools/test_depth_control.gd` PASS по непосредственно затронутой глубине/POM.
Native main-copy: тот же WorldEditor preview route; обычный и0.45× камни получают один
профиль, физический scale учтён, geometry/terrain не перестраиваются. Save/reopen/discard,
облики и sphere carrier с consistent per-triangle face IDs PASS; изменение controls и движение
сферы не увеличили sphere.preparations. Layer profiles у clones/source используют одну таблицу.
Световая привязка сферы исправлена; отдельный focused gate ниже. Старый shader/старый
carrier повторяли дефект: он предшествовал Б. Геометрию для исправления света не меняли.
First prepared mesh≈0.64с, один на все экземпляры main; fresh≈0.71с. Это не полный frame/FPS benchmark.
Fresh canonical main/панель читают сохранённые две включённые группы Б; depth20/pull30/rim-off прежние.
Scene/terrain/model/prefab hashes прежние, Pattern изменён только включением Б. Evidence/harness —
`C:/Users/novos/Documents/Codex/2026-10-25/ember-stone-layer-editor/`.
Ручной gate: main detailed → cartoon_stone → оба выключателя/диапазоны → Undo/Redo/Save/reopen/
отмена, затем normal/small/sphere в движении. Physical input/art/weak-PC OPEN. Новые поля не закрывают
общую приёмку камня или универсальную схему слоёв; C не переносился. Исторические A/B/C кадры —
`C:/Users/novos/Documents/Codex/2026-10-25/ember-stone-layers/`.

## Прибрежный дом25.10 — generator/editor/main выполнены, ручная приёмка OPEN

`tools/test_building_generator.gd` native Forward+ PASS: canonical Source/convex owner colours,
deterministic generation, library publish Undo/Redo, exact fractional metre fields, parameter Undo/Redo,
two-storey preview without Source writes, existing variant update, fresh Source/Recipe reopen,
saved-data Undo/Redo, discard and dirty-sculpt protection; existing rock integer controls retained.
All writes user://; the update check compares Source/Recipe data, not serializer incidental bytes.
Native actual main: persisted CoastalHouse at(-208,12,208), ground range12–15 under4-unit foundation;
existing panel and three global world looks, then detailed overview. No shader/script errors.
Shared palette/Prop changes: old rock buffers unchanged and test_stone_material_layers PASS.
Main terrain and previous scene nodes byte-preserved; only one ext_resource and one instance added.
Evidence: `C:/Users/novos/Documents/Codex/2026-10-25/ember-coastal-house/`.
Manual: main → house → Generator → change dimensions/floors/roof/colours → preview/save/reopen;
assess scale/front/side/roof/ground contact and walk around, three looks. Physical input/art OPEN.
Exterior only: windows/door are closed masses. Interior/interaction/settlement not implemented;
moving sphere with house, full suite/FPS/weak-PC not tested. These are not implicit PASS.

## Свет камня/земли в сфере25.10 — sampling исправлен, ручная оценка OPEN

`tools/test_world_anomaly_surface_light.gd` native Forward+ PASS: actual rock prefab,
existing carrier/target texture and sphere vertex path compared with independently baked
same vertices/normals and identity targets. Gray light/shadow fixture excludes pigment/POM/B;
0 pixels differ materially, mean RGB error≈4.19e-8. Before fix2430 pixels differed;
returning only the old light origin in an external QA shader gives1811 and FAIL.
Native main: voxel/low poly interiors, moved field, reverse camera, sphere off; no shader/script errors.
207 mesh identities retained, sphere.preparations stayed1. False dark grid on rock removed,
shadow striping reduced; physical stair silhouettes remain, author art/motion/input gate OPEN.
Scene/terrain/Pattern/Source/prefab bytes unchanged; shader-only slice does not rerun editor save/history.
Evidence/harness: `C:/Users/novos/Documents/Codex/2026-10-25/ember-rock-sphere-fix/`.
Start main detailed → anomaly preview → move sphere over rock → switch inner looks → off.
Global FPS/weak-PC/general rock acceptance not claimed. Full suite not run.

## Роли и текстуры компактной земли — ручная приёмка OPEN

Smooth bark LAB: `test_smooth_bark_material_study.gd` — exact saved Source SHA,
selected17/7 scaffold42/109/63, vertices/indices/paint retained, normal repack,
stable and valid support pairs. `capture_smooth_bark_material_study.gd`:
3 modes (previous/coarse bark/coarse bark+foliage)×3 presets×side/back,
overview/trunk/fork/rear/canopy, trunk/canopy motion and near-far,
transforms, frame table/shape/Source/grass/terrain POM retained, returnА exact,
clean exit0. Existing bark/mapping and old committed marks compatibility PASS.
Foliage material retains source arrays/paint and accepted grass light profile;
new artworks have mipmaps/local scale, old painted image matches A exactly.
This is colour-artwork only; bark height, voxel variant, tree collision/editing
and production generator transfer deferred. Artistic/input/seams/repetition/
weak-PC OPEN — Terrain Authoring → «Гладкое дерево и нарисованная кора».

Leaf-card LAB: `test_tree_leaf_cards_study.gd` — saved scaffold immutable,
deterministic fixed planes/UV/paint/group normals, true transparent margins/
alpha coverage/mipmaps/shared light profile. `capture_tree_leaf_cards_study.gd`:
plain/painted share alpha/geometry, А keeps old rounded render exact;3 presets×
side/back, close/under/rear/motion/orbit8/near-far, Source/terrain/POM/paint guards,
returnА and clean exit0 PASS. One mesh394quad/788tris; current capture includes
visible/shadow primitives and GPU timings. Short one-tree pass does not close
forest overdraw/weak-PC or artistic acceptance. Wind/LOD/voxel/editor/collision
remain deferred — Terrain Authoring → «Аниме-ориентир деревьев».

Branch construction LAB: `test_tree_branching_study.gd` — existing Source17 SHA,
explicit18/no preset upgrade, canonical Source18 and hierarchy validation,
bounded121 supports/48 branches, taper/parent attachments across6 seeds,
deterministic Source/UV/light normals, real sprite roots, private Recipe/Source
save/reopen and existing build_on_structure byte/collision parity. Broken
hierarchy rejected. Historical capture (scene/capture retired23.10; quality-cleanup archive): previous leaf-card17 A,
bare18 B/leaf18 C; returnА exact, immutable old/new Source/geometry/grass/floor,
UV/group normals independent of camera. Native3 presets×side/back in game and
full overview, under/orbit8/motion/near-far, POM4cm/profile guards, clean exit0.
Legacy1–17/seed7,31 parity uses preserved provider-before in isolated QA;
main UI presets unchanged. Artistic/F6/branch joins/card repetition/weak-PC
remain OPEN; initial game camera crops the crown, camera0a gate unchanged.
Owners/evidence — Terrain Authoring → «Построение дерева», ember-tree-construction.

Bare branch network20: `test_tree_branch_network_study.gd` — same Source/Recipe
owner, four parent orders,≤256 lines/≤128 groups (old versions retain128),
seed/taper/real attachments, invalid parent/detached fork/budget rejection,
private save/reopen/rebuild/collision parity, full233-row bark table. Targeted PASS.
Historical capture (scene/capture retired23.10; quality-cleanup archive): bare18/plain20/bark20 comparison,
exact return, three presets×side/back in game and complete tree views,
front/side/rear/overview/orbit8/close/near-far/motion, Source/terrain/paint/grass/
physical floor guards, exit0 PASS. Preserved provider1–19/seed7,31 Source/structure/
palette/collision parity and old18/19 targeted tests PASS in isolated QA.
Art gate OPEN: branch shape/density, sharp endings, bark joins, subpixel fine
shoots, F6/input/weak-PC; game camera still crops tree (unchanged0a gate).
Decorative LAB only; forest budget/editor/collision/foliage acceptance deferred.
Evidence — C:/Users/novos/Documents/Codex/2026-10-14/ember-tree-branch-network/.

Parametric branch21: `test_tree_parametric_study.gd` — opt-in/no preset upgrade,
main count/splits/depth/variation, deterministic Source and real parent radius/
attachment,≤768 supports/≤128 groups, worst count406/supports603, six seeds.
Frozen recipe responds to all four topology edits and seed; appearance retains
supports, incompatible profile rejected. Private Source/Recipe save/reopen,
existing GeneratorPanel descriptors/Undo/Redo/discard, deferred exact Creation
preview and persisted updated structure PASS. Same generic panel; LAB filter
context stays out of Resources. `capture_tree_parametric_study.gd`: bare20/21
plain/bark, three light presets×side/back/game, orbit8/close/near-far/motion,
density35/274/389 branches, preset one-Undo/Redo and discard visual return,
Source/grass/ground mesh/collision/POM/profile guards, exit0 PASS.
Legacy1–20/seed7,31 Source/palette/collision/structure parity uses before21;
existing generator-editing/save/update, old18/19/20 and bark/mapping regressions.
Manual shape/angles/bark joins/thin-shoot aliasing/F6/input/weak-PC/forest budget
remain OPEN; production renderer/collision/leaf transfer deferred.
Evidence — C:/Users/novos/Documents/Codex/2026-10-14/ember-tree-parametric/.

Foliage on21: `test_tree_foliage21_study.gd` — deterministic curved UV cards
on existing Source branch supports, exact stem/root vertices/atlas UV(.5,.94),
finite unit group+whole-crown normals, batch budget across3 presets, unchanged
bare Source21 and shared grass light profile PASS. `capture_tree_foliage21_study`:
bare/plain/painted same scaffold, camera-independent UV/macro normals,3 light
presets×side/back/game, orbit8/close/near-far/motion, existing parameter presets/
Undo-Redo/discard return, grass/paint/ground mesh/collision/POM guards PASS.
Bare21 Source SHA matches parametric evidence; previous19 Source/wood/cards
arrays match pre-foliage fixture exactly. Parametric/crown19/mapping regressions PASS.
Native GPU sample belongs to this complete LAB on RTX5070, not a forest/weak-PC
budget. Author accepted shape/volume21 as a basis; foliage edges/frequency and
bark artwork/shadows/F6/input remain OPEN. Material-only revision2026-10-15:
old/quiet-leaf/quiet-leaf+soft-bark native comparisons,3 lights×side/back/game,
near/far/leaf/bark close-ups, exact return to previous artwork, unchanged
wood/cards/UV/normals/Source/light/ground/grass/physics/POM guards PASS.
Previous accepted front frame matches pixel-for-pixel. Existing native
parameter presets/Undo/Redo/discard PASS; artwork acceptance remains manual.
Contract and evidence — Terrain Authoring → «Построение дерева».
Minimal leaf revision2026-10-15:3 colour variants×3 lights×side/back/game,
near/far/side/rear/close and unchanged wood/cards/UV/macro normals/Source/light/
floor/grass/POM PASS. Old quiet trial frame returns pixel-exactly. Temporary
flat-colour/cast-shadow-off and nearest/no-mip sampler controls restore normal
material/light state pixel-exactly. Nearest largely removes fine dark net;
this is diagnostic evidence, not an accepted rendering replacement. Minimal
artwork acceptance remained OPEN at that diagnostic checkpoint.
Evidence — C:/Users/novos/Documents/Codex/2026-10-14/ember-tree-foliage21/.

Approved leaf-optics trial2026-10-15: `test_tree_leaf_optics.gd` uses private
user:// RGBA fixture; default/opt-in cache identity, unchanged authored PNG,
base alpha of v6/v7, all mip alpha of fixture, retained green mip colour and
filtered mip availability PASS. `capture_tree_leaf_optics.gd`: five stages,
3 presets×side/back/game, near/far/motion, separate rim/transmission, exact
zero-Sun and previous-return frames; Source/wood/cards/UV/macro normals/bark/
base light/paint/grass/ground/collision/POM guards PASS. Controls rendered in
native Forward+; personal F6/input and artistic strength/colour acceptance OPEN.
Foliage21, material texture mapping (including save/reopen), painted-light
regressions PASS. Optical sliders are transient LAB values, not a new saved
profile: their persistent save/reopen is outside this contract. Alpha gaps
produce subtle real ground illumination changes; atmosphere rays, forest
budget/wind/LOD and production transfer deferred.
Evidence — C:/Users/novos/Documents/Codex/2026-10-15/ember-tree-leaf-optics/.

Leaf rim shadow visibility2026-10-27: native Forward+,
`--script res://tools/test_tree_leaf_shadow_visibility.gd` writes user://tree-leaf-shadow-visibility.
Real shadows-only blocker must change diffuse lighting; rim on/off must match
under full occlusion and differ in direct Sun. Authored diffuse receiving0.4 retained.
RED before shader correction, GREEN after: occluded changed80651→0 pixels,
lit changed80651. Exact large-crown moving-line acceptance in landscape_compact OPEN;
same-pose native map capture is diagnostic, not author acceptance.
Evidence — D:/ember-tree-shadow-cutoff-2026-10-27/visibility-regression/.

Separate-leaf samples first stage: texture test includes v8 exact authored RGBA/
base alpha/filtered mips. `capture_leaf_plane_group.gd` extracts one/six existing
cards and compares old/new artwork and new local light; native3 presets×side/
back, near/far/angle5, zero-Sun exact, original tree return and baseline frame
pixel-exact. Source/wood/cards/UV/macro normals/material/grass/paint/floor/
collision/POM guards and existing foliage21 test PASS. Candidate not applied to
tree; personal F6/buttons, artistic colour/mask acceptance, full-tree game camera
and shadow stipple remain OPEN. Evidence — C:/Users/novos/Documents/Codex/2026-10-15/ember-leaf-plane-group/.

Leaf shadow diagnostic: `capture_leaf_shadow_diagnostic.gd` runs private native
controls (no-shadow/angular/bias/filter/geometric/shading normals/solid alpha),
then restores every property/material/mesh. Same baseline frame before/return
and prior sample are pixel-exact; zero-Sun comparison exact. Source/wood/cards/
UV/macro normals/texture mips/grass/floor/physics/POM guards PASS. QA-only floor
and grounded cube receive shadows under3 presets×side/back; near/far/angle/back
captures retained. Depth bias1.6 clears the single-card noise gate (14.95%→0%),
but group and ground shadow coverage/contrast change: don't label this a global
fix or full visual PASS. All project shader/study/material files remain exact.
User art/motion/contact/forest gates OPEN. Evidence — C:/Users/novos/Documents/Codex/2026-10-15/ember-leaf-shadow-diagnostic/.

Leaf receiving response: `capture_leaf_shadow_response.gd` uses private native
Forward+100/60/35/15%×3 presets×side/back, near/far/angle/back. Old/default tree
and samples, baseline return, zero Sun and Omni attenuation pixel-exact. External
shadow-only shield measurably shades right leaf group; shadow contrast weakens
monotonically with strength. Ground receiver ROI exact in all18 comparisons and
external shield control. Source/wood/cards/UV/macro normals/texture mips/grass/
physical floor/POM and21 protected files exact; foliage21/leaf-optics/mapping/
painted-light targeted tests PASS. Single-card strict noise gate remains FAIL
at every strength: do not call this noise repair or caster-selective shading.
Transient sample slider default100%, original stages/tree material unchanged;
personal F6/slider/reset, artistic choice60/35%, motion and tree transfer OPEN.
Evidence — C:/Users/novos/Documents/Codex/2026-10-15/ember-leaf-shadow-response/.

Whole-tree leaf trial: `capture_tree_leaf_transfer.gd` compares original and v8
sample-stage2 clone at100/40/35% under3 presets×side/back×whole-tree/game cameras;
near/far/side/back and8 orbit frames. Old before/default/return and zero-Sun
frames exact. Public sample→tree40% route, independent sample35%, panel return
guards PASS. Source/wood/cards/UV/macro normals/bark/texture/terrain/paint/grass/
physical floor/POM retained;23 protected files exact including shaders/factory.
Same-atlas ground ROI exact at100/40/35% under all3×2 lights and overhead view;
old/new atlas masks differ as expected. Foliage21/leaf-optics tests PASS.
Art35/40%, canopy density/grain, personal F6/input/motion and production transfer
OPEN; unchanged game framing clips canopy, not a camera acceptance. Evidence —
C:/Users/novos/Documents/Codex/2026-10-15/ember-tree-leaves-40/.

Leaf density: `test_tree_foliage21_study.gd` now tests whole-puff retention,
nested reductions, deterministic reproduction,100% original instance/0% empty,
exact remaining positions/UV/colour/custom macro normals/stem/index bounds for
all3 presets; geometric normal packing roundtrip max0.00012894 below0.0005.
Full buffers remain exact; branching/parametric regressions PASS.
`capture_tree_leaf_density.gd`:100/75/60/45%×3 presets×side/back×tree/game,
near/far/side/back/8 orbit frames. Public slider drag does not alter committed
mesh/build count; release commits once, cache instances reused; original material
full mesh/new trial subset routing and0% visibility guards PASS. Default100 and
return100 exact against preserved previous native tree40 frame; baseline
provenance recorded in verification.
Source/wood/bark/texture/shader/material/terrain/paint/grass/physics/POM/light and
22 protected files unchanged. Density alters canopy/ground shadow as expected.
Personal slider/keyboard/F6, artistic density/edge/motion, residual shadow noise
and production Recipe save/reopen integration OPEN. Evidence —
C:/Users/novos/Documents/Codex/2026-10-15/ember-tree-leaf-density/.

Shadow-mode investigation at user-preferred45%: `capture_tree_shadow_modes.gd`
temporary material clone/cast OFF/receive0/AO-off/no-shadow/low0.55/0.80 controls
under3 presets×side/back×tree/game and external shield. Baseline45 equals prior
density45/return exactly; Source/wood/cards/floor/grass and25 protected files exact.
No-leaf-cast changes ground shadow and still receives external; receive0 ground
ROI exact and external drop nearly0 (eroded canopy mask has mixed gaps, not a
pure stencil). Soft/flat form controls retain external/ground shadow response;
AO/form shading remains separate. Project controls unchanged. Artistic local
density/dark-form contract and true internal-only shadow boundary OPEN; don't
label this installed suppression or production acceptance. Evidence —
C:/Users/novos/Documents/Codex/2026-10-15/ember-tree-shadow-modes/.

Leaf/grass style A/B: `capture_tree_grass_light.gd` tests three presets × two
directions × tree camera. Its old game captures duplicate tree (found in rim audit);
real gameplay capture fixed in capture_tree_rim_light below. A equals baseline/return;
new RGB-only blend preserves alpha,885 cards/45% density, mesh arrays/identity,
Source/wood/Recipe/floor/terrain/grass/POM4cm. Ground shadow ROI exact, external
blocker remains visible, zero-Sun rim/transmission no emission. Native PASS.
Targeted foliage21/material-depth PASS; native A form/shadow controls exit B,
including unchanged depth value. HTML rendering/images/view selectors checked.
User accepted calmer B direction; personal movement and F6 toggle OPEN.
Production editor save/Undo and selective self-shadow are outside this LAB.
Evidence — C:/Users/novos/Documents/Codex/2026-10-15/ember-tree-grass-light/.

Tree directional rim: `capture_tree_rim_light.gd` uses accepted B for both states.
Three presets × side/back × tree/game; pre-extraction baseline/OFF/return exact,
rock/actors/grass ROI exact. Mesh identity/arrays,45%/885 cards,Source/wood/Recipe/
terrain/floor/grass/POM4cm retained. Separate bark/leaf contributions; zero strength,
zero-Sun and full external shadow yield exactly zero added rim. Base wood and
historical A restore correctly. Native PASS;11 protected files exact. Controls fit
capture; HTML rendered/images/selectors verified. Art/F6/button/sliders/motion
and weak-PC cost OPEN. Runtime LAB controls temporary, no production Undo/save claim.
Evidence — C:/Users/novos/Documents/Codex/2026-10-15/ember-tree-rim-light/.
Targeted foliage21/material-depth/painted-light PASS. Gameplay capture explicitly
restores comparison0/FOV before freezing and asserts distinct tree/game transforms.
Native button signals/independent sliders PASS; real mouse feel remains manual.
Gameplay frame crops the crown top; full-tree framing is explicitly separate.

Permanent rim workflow: test_style_rim_workflow covers optional Pattern/model fields,
validation/legacy, independent palette/role settings, small GPU lookup, preserved paint,
real material dialog/PalettePanel/Canvas callbacks, one-release/no remesh, Undo/Redo,
Save/Reopen/Discard and saved map master. Related9 material/WorldLook/Canvas/projection/
POM/foliage regressions PASS; world projection uses generated mixed-editor sandbox.
capture_style_rim_workflow:3 presets×side/back×tree/game,24 accepted LAB→saved pairs
exact; map/role controls, Source reopen, zero-Sun,6 full-shadow pairs and ground/POM
PASS. Raster baseline/return gate max1 RGB8/≤16 changed channels; raw geometry/Source/
paint/grass/floor exact. Five protected files SHA-256 exact. Native controls inspected;
actual editor mouse/125%/Save→F6/motion and weak-PC OPEN. Shape/B unchanged.
Evidence: C:/Users/novos/Documents/Codex/2026-10-15/ember-style-rim-transfer/.

Oak bark trial: capture_oak_bark_trial checks A→B→C→A at3 presets×side/back×tree/game;
all12 returns pixel-exact. Near/far/static camera shift, callbacks/UI fit1600×900,
same wood material instances and saved Source rim binding, every wood/leaf uniform
except bark albedo, Source/mesh/45%/885 cards/B/terrain/paint/grass/physics/POM guards PASS.
test_tree_foliage21_study PASS;10 protected SHA exact. Native screenshots inspected;
HTML links/JS checked, local browser rendering unverified. Six bark PNG candidates
saved; only oak fitted. C accepted by user; F6/input/continuous
motion/junction seams/weak-PC OPEN. No production bark Undo/save integration claim;
LAB selector transient/default C. Birch follow-up below; other three unchanged.
Evidence: C:/Users/novos/Documents/Codex/2026-10-15/ember-bark-species/.

Birch22 species trial: test_birch_species_study records five legacy kinds×seed7/31
and oak21 before edits, compares raw Source/collision/palette/structure hashes.
22 opt-in/type boundaries, hierarchy/Source validation, repeatability/seed bounds,
every card on a real branch, count rebuild/mismatch rejection; existing RecipePanel
draft without rebuild/Undo/Redo/prepare/discard/preview→saved Source output equality,
Source/Recipe save/reopen PASS. Four related parametric/foliage/type/editor checks PASS.
capture_birch_species_study: five support-mass comparisons, A13/Б22/В22, bare/near/far/
static shift,3 presets×side/back×tree/game;12 A-return pairs exact. Accepted oak C
return and previous bark-study capture exact; oak material/shape/B/Source/terrain/
paint/grass/physics/POM4cm exact. Visible4 fields/UI1600×900 and7 protected SHA PASS.
LAB smooth mass diagrams are not a claim about unchanged production renderer output.
Birch look accepted; manual F6/input/continuous motion/white thin shoots/junction seams/weak-PC OPEN.
No production atlas/forest/collision migration. Evidence — ember-birch-species/.

Birch controls: capture_birch_controls checks exact accepted initial frame,
global/local slider callbacks, no per-drag build/one release/cache Undo/Redo,
every other crown owner retained, light-only uniforms without mesh rebuild,
reset/Undo-reset/Redo and3 presets×side/back exact returns. Old local history must
not cut a new scaffold after preview regeneration. Same Source/wood/oak/paint/grass/
floor guards; two tab controls fit1600×900. Runtime LAB controls do not claim
production leaf-setting serialization. Evidence — ember-birch-controls/.

Maple23: test_maple_species_study covers type opt-in/unchanged old defaults,
Source/hierarchy/Recipe validation, seed repeatability/bounds, leaf attachment,
Source reopen through saved Recipe, four same fields/draft/no rebuild/Undo/Redo/
prepare/preview=commit/discard. Source birch22 matches accepted hash.
capture_maple_species_study:3 presets×side/back×tree/game,12 A-return pairs exact,
accepted oak21/C and birch22 exact against previous captures; near/far/static shift,
same terrain/paint/grass/physics/POM guards. capture_maple_controls reuses existing
birch control checks for730 cards; accepted birch control regression rerun.
Shared species hooks must preserve old birch directory/controls/shape/light.
Seven protected files exact. Maple art/manual F6/motion/junction seams/weak-PC and
production leaf-setting serialization OPEN. Evidence — ember-maple-species/.

Maple shape variation: test_maple_shapes protects exact wide Source6d9134… and
asserts meaningfully narrower/taller new card bounds, hierarchy/seed validity,
same fifth Recipe field draft/no build/Undo/Redo/prepare/reopen/discard. Existing
Recipe variations reopened to exact Source; no author map writes. Native shape
callback reconstructs old wide exactly; discard/reset restores new upright exactly.
3 presets×side/back×tree/game yield12 exact wide returns; accepted oak/birch exact.
Controls/one-release density, unchanged ground/paint/grass/physics/POM and7 protected
files PASS. Upright art accepted on 2026-10-15; F6/motion/weak-PC and production transfer OPEN.
Evidence — ember-maple-shapes/; saved recipes maple_v1/variations/.

Savanna24: test_savanna_species_study covers opt-in/type/default boundaries,
hierarchy/Source/repeatability/seed bounds/extreme branch counts, shallow3D canopy,
every stem attached, Recipe save/reopen and shared four-field preview=commit/
Undo/Redo/prepare/discard. Accepted birch and both maple Source hashes exact.
capture_savanna_species_study:3 presets×side/back×tree/game,12 old-return pairs
exact, oak21/birch22/upright23 frames exact; near/far/static shift/ground/paint/
grass/physics/POM preserved. capture_savanna_controls reuses same842-card callbacks,
release once/cache/locality/light-only/reset/stale-history/UI fit checks. All PASS;
birch/maple-shapes/parametric/voxel-types regressions and7 protected SHA exact.
Own art/form/F6/motion/weak-PC and production leaf-setting transfer OPEN.
Evidence — ember-savanna-species/; spruce unchanged, no forest performance claim.

Savanna silhouette1: test_savanna_canopy protects rejected shape0 Source exact;
new hierarchy/Source/seed/extreme counts, crown3D bounds/support connectivity,
branch-following centres with quarter-cell rounding, crown_shape rebuild, existing
Recipe save/reopen, count draft/Undo/Redo/prepare/preview=commit/discard PASS.
capture_savanna_canopy:3 directions/bare/mass/rejected + above,3 presets×side/back×
tree/game; count5→7 preview/discard frame exact. Accepted oak/birch/upright maple
and rejected frames exact. Ground/paint/grass/physics/POM/protected SHA exact.
Old savanna/birch/maple-shapes/parametric/voxel-types regressions PASS.
Mass is diagnostic, not final leaf material/shadow. Silhouette accepted as base;
manual motion OPEN. Leaf follow-up below; evidence — ember-savanna-canopy/.

Savanna leaf patches: test_savanna_leaf_patches protects accepted shape1 Source,
structure/layout/wood/collision; actual group attachments vs separate card anchors,
envelope positions except small tip fans; all45 terminal shoots covered at60%,
small fan size/last-segment attachment,zero removes all,repeatability/UV/nested
thinning/sample buffers and Recipe+
same LAB placement reproduction. capture_savanna_leaf_patches:1/6 samples,3 views/
above,3 presets×side/back×tree/game, density60/80, preview count5→7 keeps envelope;
discard/reset frames exact. Accepted3 species+blockout frames exact. Same generic
control callbacks with382 cards: drag/release/cache/locality/Undo/Redo/reset/
stale-history/material-only/UI fit PASS. Canopy/species/foliage21 regressions after
tip coverage;6 prior patch regressions preserved.7 protected SHA and
ground/paint/grass/physics/POM exact. Leaf artwork/coverage/edge/manual motion OPEN;
production foliage save remains separate. Evidence — ember-savanna-tip-cover/;
previous placement report — ember-savanna-leaf-patches/.

Spruce25 silhouette: test_spruce_shape validates opt-in species/defaults, attached
bounded scaffold/alternate seeds/extreme counts, continuous crown support graph;
Recipe save/reopen Source/collision/groups/diagnostic faces exact, scalar branch
values within1e-6 text Resource precision. Same RecipePanel draft/Undo/Redo/
preview==commit/discard. capture_spruce_shape checks3 views×old/wood/crown,above,
preview7→9/discard frame exact,seed31/197 in same daylight,keyboard1–3,
3 presets×side/back×tree/game,6 controls fit;
accepted savanna/oak/birch/upright maple and legacy spruce frames exact. Ground/
paint/grass/physics/POM and9 protected files unchanged. Related regressions:
savanna patches/maple shapes/parametric/voxel types. Evidence — ember-spruce-shape/.
Visual form/F6/motion OPEN; that displayed crown is diagnostic. Needle follow-up:
test_spruce_needles checks Source/layout/wood/collision exact, real branch/t and
mesh stem anchors, endpoint tufts at60%, deterministic/nested/zero density,
offset1/6 samples, Recipe+same LAB options reproduce full buffers. Native checks
3 views/above/1–6 samples/60–80%, preview7→9 preserves needle options, discard/reset
frame exact,3 presets×side/back×tree/game. Provisional volume frame exact;
4 previous species reference gate max1 RGB8/≤8pixels (actual0–1pixel), data strict.
capture_spruce_needle_controls inherits generic release/cache/locality/history/
reset/stale/material-only/UI checks. Foliage21/savanna patches/spruce shape related
regressions,12 protected SHA/ground/paint/grass/physics/POM guards. Evidence
ember-spruce-needles/. Form and needle art not accepted; upper coverage/F6/motion OPEN.

Spruce bough follow-up (old needle/form rejected): test_spruce_bough checks
paired hierarchy/attachments/budgets/seeds/extremes/shape0↔1 fresh==edited Source,
old shape0/9-tier Source/first bough exact;12-tier upper cards>20% increase,
max gap≥15% reduction, max12/splits3/levels4 fits768 segments;
real leaf stem anchors, endpoint/nested/zero density, sample
subset with current density, Recipe save/reopen Source/collision/full cards,
same7-field RecipePanel draft/Undo/Redo/preview==commit/discard. Native captures
one actual limb top/side/wood, sample→whole-tree visibility,3 views/above/60–80%,
preview12→7 preserving same options/discard/reset exact,3 presets×side/back×tree/game.
Generic bough controls cover release/cache/locality/history/reset/stale/material/
UI fit. Related regressions: savanna patches/foliage21/spruce shape/spruce needles.
4 accepted species+previous needle tree reference gate≤8pixels/max1RGB8;15 protected
SHA/ground/paint/grass/physics/POM unchanged. Evidence ember-spruce-density/; prior9-tier frames ember-spruce-bough/.
Current2166 full/1328 at60%; Source4d4733cf…; shape0 dfd9f454… preserved.
Latest crown frames accepted as working base; personal F6/motion remain OPEN;
production appearance save was outside that LAB slice; it is now implemented below.

Main editor transfer (15–16 Oct2026): `test_tree_editor_transfer.gd` covers five ordinary
presets, accepted voxel SHA/counts, complete bark/card prefab, library Undo/Redo exact
bytes, published signature, Source/prefab roundtrip, cold rebuild without Recipe,
scene commit Undo/Redo/map roundtrip, actual RecipePanel global/local signals,
local history/revision guard/preview/discard, existing variation update + scene Undo/Redo,
zero density, invalid controls, Source paint and sculpt fallback. `editor_test_painted_tree_transfer`
uses the real library button, species selection, candidate preview, save-best, reopen
in the existing workshop and its Recipe controls. Disposable editor only.
`test_painted_tree_runtime` runs in a fresh Forward+ process on editor-published objects
or canonical `vox_painted_*` via normal Catalog/Prefab; validates both mesh surfaces
against Source-only reconstruction, trunk ray/collision, map save/reopen. No Recipe run.
`capture_tree_editor_transfer` compares3 presets×side/back×tree/game plus real cast
shadow; preview→publication→reopen separately. Geometry/channel/shader/PNG guards strict;
LAB→published oak uses measured max5RGB8 and mean≤0.15RGB8/frame, other species max1RGB8
at≤32pixels. These are separate from strict preview/save/reopen. Do not report the
LAB oak transfer as pixel-exact. Native game camera/grass/floor/POM guards remain.
Related old generator tests explicitly request legacy presets; shared shader/body and
Store/parity paths require material/rim/workshop/save-snapshot regressions. Toon body
move must be byte-identical to the old body, apart from its entry line.
Evidence: `ember-tree-editor-transfer/`. Own main-editor/F6/motion/weak-PC/forest gates OPEN.

Oak colour B transfer17 Oct: `test_oak_bark_transfer.gd` freezes the old derived
oak in the disposable checkout (`--seed-stale` before the binding change), then
checks oak-only signature invalidation, all five Source hashes, exact wood/leaf
arrays, collision and every non-art shader input. Exercises ordinary stale Prefab
rebuild and existing SceneRefresh on user:// fixtures, including placed instance
Undo/Redo, map save/reopen and rejection of manual bark tint/leaf shadow changes.
`test_tree_editor_transfer` retains preview/paint/history/discard gates; related
`test_voxel_scene_refresh` and `test_voxel_save_snapshots` cover protected overrides.
`capture_oak_bark_transfer` records54 C/B pairs/54 exact returns and19 measured
preview/runtime/reopen cases (all pixel-exact in this run),3 presets×side/back,
game/tree/bark cameras, real cast shadow. A fresh `test_painted_tree_runtime --bases`
checks canonical Sources/prefabs and collision without recipes. Smooth production;
faceted/voxel remain existing LAB derivatives. Bark relief stays LAB-only.
Evidence: `ember-oak-bark-editor-transfer/`; personal F6/input/motion/weak-PC OPEN.

Oak two-look pilot16 Oct: `test_oak_looks.gd` checks deterministic buffers, shared
399 sites/885 cards, unchanged Source/smooth buffers, zero/local density, preserved
leaf receive/tonal controls, source paint on voxel bark, derived mesh and Source
save/reopen/rebake. `capture_oak_looks.gd` compares3 presets × side/back × whole/crown/
bark/game, two cell sizes6.25/12.5cm, smooth/split/voxel and exact return; baseline
uses pre-change common shaders and geometry. Companion excluded from fixed captures;
Kai remains scale reference. Motion/boundary frames, cache build count, Source/wood
collider identity+faces and grass/floor guards. No new editor data or Undo path.
Manual art/F6/input/shimmer/forest gates OPEN; no claim of closed seam,
sphere or export-ready bake. Details — Terrain Authoring → «Три облика одного дуба»;
evidence `C:/Users/novos/Documents/Codex/2026-10-16/ember-oak-looks/`.

Three-look continuation: `test_oak_three_looks` checks deterministic faceted geometry,
13764 triangles vs smooth58868, same399 sites/885 patches, alpha art/receive settings,
zero/local density, source paint, derived roundtrip, unchanged58421 voxel cells and
338328 triangles. CUSTOM2 supplies the source-group rim normal; diffuse CUSTOM1 kept.
`capture_oak_rim_probe` isolates master on/off, face/form rim normal and no-shadow
diagnostic (never adopted). `capture_oak_three_looks`:24 lighting/camera cases,
smooth and return exact, voxel with original rim math exact, two split alternatives,
12 camera/11 boundary frames, no rebake, single collider/Source/floor/grass unchanged.
`test_oak_looks` and `test_style_rim_workflow` PASS. Actual shared rim contribution
is measured from on/off images; artistic acceptance is separate. Ten protected
Source/material/PNG/POM owners unchanged by SHA. Report48 split selections/23 motion
frames rendered in headless Edge. Evidence `ember-oak-three-looks/verification.json`.
No general world/object switch, stone/road trial, export/LOD or character conversion.

Faceted alpha recipe: `test_oak_three_looks` additionally checks deterministic
96 separate components, original artwork unchanged, filtered derived mask and
Resource roundtrip. `capture_oak_leaf_shapes` PASS:18 lighting/camera combinations,
three shapes ×70/100%, previous faceted at0 and return exact, smooth/voxel exact
(72 comparisons),12 orbit frames, no remesh and unchanged Source/ground/grass/collider.
Evidence: `ember-oak-leaf-shapes/`. Controls are temporary LAB settings. Shape is
alpha clipping, not area-preserving polygon replacement; visible coverage decreases.
Day/evening/night artistic acceptance, personal F6/input/flicker remain OPEN.

Material recipe pilot: `test_material_shape_recipes` PASS for identity/determinism,
source/height/alpha protection, deep-groove colour and periodic edges, grass mesh
scale and finite buffers. `test_painted_light_study` regression PASS including
geometry/floor/POM/Source/morph/Player/save-reopen. `capture_material_shapes` PASS:
24 day/evening/night ×side/back ×game/crown/rock/tree cases, three styles,
48 neutral/return exact comparisons, separate POM on/off/return for all3,
16 movement frames; fixed terrain/wood physics, Source, height bytes, grass
instance transforms, no rebake. Ten protected files SHA exact. Evidence:
`ember-material-shapes/`. Whole terrain/rock geometry conversion is not tested:
all views deliberately use the same existing smooth terrain. Recipe authoring,
export/LOD/GPU cost and manual art/input/flicker acceptance remain OPEN.

Coherent world-look LAB16 Oct: `test_terrain_look_bake` PASS — planar anchor and
edge/diagonal continuity, immutable field/art, deterministic rectangular mip cells,
coarse grass survival/fewer strips. `test_material_shape_recipes` regression PASS.
`capture_coherent_looks` Forward+ PASS:3 presets ×3 views ×3 looks;9 coarse-grass
alternates;9 pixel-exact smooth returns;3 POM on/off/return pairs;16 motion frames.
One unchanged physical field/wood collider, Source, authored height, original
scatter and per-look x/z/basis/count guards. Geometry now changes: voxel uses the
canonical mesher, faceted uses shared-field planes. Art/flicker/manual input OPEN;
facet displacement up to0.56m means gameplay contact/morph not accepted. Evidence:
`ember-coherent-world-looks/`. No production cache/export/LOD/general world switch.

Natural rock follow-up16 Oct: `test_natural_rock` PASS — bounded field error at every
fine vertex, boundary anchors, finite complete plane normals, deterministic paired
art and geometry, sparse fractures, untouched field. `capture_natural_rock` PASS:
day/evening/night ×side/back ×rock/game, plain/material ×3 looks;24 exact returns,
3 POM on/off/return pairs, original grass buffers/meshes/materials, physics and
Source guards. Measured field error3.74cm; transition paint fringe has separate
blending. Real art/moving camera/contact/LOD/editor integration OPEN. Evidence:
`ember-natural-rock/`. Original paving pair retained.

Ordinary form controls16 Oct: natural-rock art rejected (rounded foundation).
`capture_rock_form_rules` Forward+ PASS: existing Source rules radius1/protection75%,
1619 stone columns, day/evening ×rock/game ×3 variants,4 exact baseline returns.
Mesh/collision/floor advance together; measured readback difference≤3.13µm from
ArrayMesh face rounding. Source/grass buffers/mesh/material and Sol height guards
PASS;10 protected-file hashes unchanged. `test_terrain_surface_rules` PASS.
HTML8 paired views/B reference/zoom PASS, evidence `ember-rock-form-controls/`.
This control showed that filtering alone could not create missing fractures.
The author then approved Source sculpting: `test_rock_planes` PASS for deterministic
subtractive cuts, untouched input/paint/non-rock columns, retained2.5m peak and
Source save/reopen.213 changed stone columns, cut≤37.5cm. `capture_rock_planes`
Forward+ PASS:12 plain frames/4 exact returns; Source/grass/material/depth guards,
same physical mesh/field/floor, crease-normal processing preserves vertex positions.
Existing adaptive fit error≤3.716cm; neighboring stone normals blend within30°.
Follow-camera look height1.35m in this LAB only, same before/after FOV/distance/pose.
HTML4 pairs/B/zoom PASS; evidence `ember-rock-planes/`, private chiselled-source.res.
The author rejected that art result, then approved the direction of the tilted
flat-face probe. Current `capture_rock_three_looks` compares detailed/faceted/voxel
from one private voxel Resource;14/18-plane fits and native VoxMesher6.25cm.
PASS: Resource validation and save/reopen including part ownership; Source stays
unchanged in all looks; detailed/faceted use identical side slopes, large-rock
lean changes<2° from accepted probe; exact return-frame; same camera/material/light;
original terrain/grass/depth and protected Sol file hashes unchanged. HTML three
panels/full-frame expansion PASS. Evidence `ember-rock-three-looks/`.
OPEN: art, general segmentation, surface correspondence, collider/floor/navigation.
AABB-corner discrepancy≤26.7cm is measured but is not a surface-error bound or pass.
Follow-up Source-first macro cuts, explicitly authorized: `test_rock_surface_detail`
PASS for deterministic source edits, only two permitted masses changed, original
fixture preserved, captured Source equal to independent regeneration, closed
oriented edge pairs in ordinary/faceted meshes, common principal slopes and
voxel-bound extent delta≤6.25cm. Native save/reopen/return-frame/source/grass/depth/
camera guards PASS; prior2° large-rock lean gate retained.727 runtime/material/
content hashes unchanged. HTML A/B + three full frames PASS; evidence
`ember-rock-source-breaks/`. Other looks intentionally regenerated from edited
Source after explicit approval; no longer claim byte-identical endpoints.
Author accepted form as sufficient for continued material work on16 October;
final B art/physics/surface correspondence/general extraction/anomalies OPEN.
Known recipe directions guide convex fitting; not a generic converter.
Next manual material gate: detailed -> faceted -> voxel, then all three side by
side and each with terrain/road/grass/tree. Check game/close camera, motion,
day/evening/night and side/back light; preserve depth/rim/foliage/manual paint.
Scene-wide endpoint style acceptance precedes a separate moving anomaly sphere
slice; no spatial transition or production world-switch acceptance claimed.

Rock material follow-up: source hash + geometry stats exact to Source-first
probe; detailed/faceted height bytes unchanged. `test_material_shape_recipes`
and `test_natural_rock` PASS; native same4cm/32 POM, actual on/off contribution and
exact return for3 looks, common Source save/reopen and scene guards PASS.
Captured3 lighting presets and evening back sun, synchronized POM sun direction.
725 runtime/material/content files unchanged. Report presets/zoom checked in
headless browser. Art, motion shimmer, moving-object anchor, anomaly morph and
production editor/physics gates remain OPEN. Evidence `ember-rock-material-looks/`.

Local leaf density/form controls: fixture tests optional local coverage affects
only selected owner, nested/repeatable/neutral100% returns original instance;
existing positions/UV/custom normals and other groups retained. Native
`capture_tree_leaf_local.gd`:3 presets×side/back×tree/game, near/far/side/back/orbit;
local drag commits once, cached Undo/Redo, reset/undo-reset, F1 frame visibility,
old material full mesh, zero-Sun and unchanged Recipe/Source/wood/terrain/grass/
physics/POM guards PASS. Form-depth100/60/25 retains external shade; shade-only
ground ROI exact in12 pairs. Initial45 and control-return before blocker exact
against prior density45 PNG; current post-blocker frame exact, numerical
post-blocker gate ≤128 pixels/max1 RGB8 level.22 protected files
exact. Transient LAB controls don't claim gameplay Recipe save/reopen integration.
Personal F6/selection/sliders/history/art/edge/motion/weak-PC gates OPEN. Evidence —
C:/Users/novos/Documents/Codex/2026-10-15/ember-tree-leaf-local/.

First bark look rejected: `test_bark_material_study.gd` — deterministic field, inward bounds,
exact previous committed marks v1/v2, branch frame rotation, private source/paint/
roles, matching Recipe reproduction and occupied/collision cells. Existing
test_voxel_bark_pattern covers UI/Undo/Save/Reopen and retained versions;
object lighting/mapping regressions PASS. Historical rejected capture (scene/capture retired23.10):
4 modes×3 presets×side/back, flat/trunk close comparisons, movement, near/far,
transform/local Sun, Source/terrain/grass/physics/POM preserved, return/disabled
exact, relief changes pixels independently of colour, clean exit0. Artistic
selection/F6/input/seams at branch joins/weak-PC and production cache OPEN.
Owners/evidence — Terrain Authoring → «Кора — первая LAB-проба», ember-bark-material.

Readability stage0a: `capture_diorama_readability_study.gd` — one voxel Source,
Kai/Mira from real Player/PartyFollowers/private state, stable1.8/1.5m dimensions.
Fixed source/light/paint: original camera, two candidates, quiet PNG detail,
conditional door-only scale including collider. Measure real body silhouette
in isolated unlit masks; report AABB separately, not as silhouette pixels.
ReturnА exact, Source/terrain geometry/grass buffer/POM retained, Map floor/ray,
matched camera motion and real step crossing with unchanged capsule. Related:
camera-relative movement, material mapping/workflow and party followers/save-v2
through `run_party_tests.py` guarded disposable projects. Their UID text-path
fallback warnings remain in logs; no UID migration implied. F6/mouse/125%/motion/
flicker and camera/door artistic choice OPEN. No global scale/author maps changed;
quiet material filtering does not remove geometry step strips. Evidence/owners —
Terrain Authoring → «Читаемость диорамы — этап0а», ember-diorama-readability.

Material looks LAB: `capture_material_looks_study.gd` — принятый grass_field9621,
А equals current/pre-slice accepted shader, return exact, Б/В visible changes,
3 presets×side/back с одинаковой игровой камерой. World-metric pixel size и
light levels независимы; Source/paint/mesh/collision/grass buffer unchanged,
POM4см/32 и paired textures retained. Реальный process меняет/останавливает Sun;
одинаковые camera/sun trajectories, far/grazing, zero-energy fill exact,
all tuft roots follow shared floor, настоящий Player walk. Material mapping/depth/
workflow и Source rules regressions. Ручная motion/flicker/стыки/near-far/F6/125%
приёмка OPEN; Б lighting diagnostic не доказывает low-poly geometry, pixel filtering
не доказывает готовый pixel-art. Owners/budget — Terrain Authoring → «Три подачи
материала и света»; evidence — ember-material-looks. Рабочий editor не запускать
headless; native capture/import выполняются в disposable QA project/cache.

Солнечные тени панели: `test_world_shadow_controls.gd` native Forward+ проверяет копию
реального Sun, метрический масштаб, один drag/Undo/Redo, cascade/quality IDs, сохранение и
fresh reopen/runtime-ready Map, discard/закрытие владельца, Undo после смены масштаба/карты.
Связанный лёгкий regression — `test_world_look_panel.gd` (в том числе прежний water/Sun snapshot).
Тесты не записывают авторскую карту. По TAA-срезу `test_world_shadow_controls.gd` также проверяет
ряд softness/filter/TAA, один toggle/Undo/Redo с изменением runtime viewport, независимость Hard от
угла Sun, Save/fresh reopen/discard, выключенный stale owner и отсутствие смешивания карт в истории.
`test_shadow_grain_render.gd` native Forward+ воспроизводит зерно на однотонной поверхности с настоящей
мягкой тенью, проверяет снижение с Map TAA+Ultra в покое/движении и возврат при выключении.
`editor_test_shadow_taa.gd` включать только в guarded `ember-shadow-grain/editor-qa/` со своим cache:
4реальных editor viewport, штатный EditorUndoRedoManager toggle/Undo/Redo, EditorInterface save+reload/restore-on-release; exit0.
При изменении viewport AA на основной карте проверить три облика/траву/камень/берег и GPU одного ракурса;
стоимость main viewport не выдавать за полный FPS. TAA sharpness/ghosting и мышь/полёт — ручная приёмка.

Общий voxel-рельеф: `test_terrain_voxel_relief_render.gd` (только native Forward+)
сравнивает настоящий bank/POM shader с геометрическими ступенчатыми плитками: цвет должен
совпадать с ячейкой высоты. Negative control прежней pixel-выборки обязан ухудшать совпадение;
не принимать пустой чёрный render за PASS. Дополнительно на основной карте — paving/sand
near/far и три облика. Editor-only пропадание тени при дереве за камерой проверяется отдельно;
успех F6/plain receiver не закрывает этот ручной gate.

Общий voxel-light: `test_voxel_light_render.gd` только native Forward+ проверяет настоящий terrain/toon
shader на receiver: continuous negative control, flat per-cell light, привязка при переносе камеры,
exact возврат disabled и реальные hard directional shadows. Soft-PCSS кадры — ограничение, не flat-cell PASS.
`test_voxel_light_controls.gd`: две scene-owned настройки в прежней панели, один drag/Undo/Redo,
метрический scale, диапазоны/NaN, отсутствие remesh, Save/fresh reopen/discard и закрытый owner;
временная копия основной карты сохраняет значения/Sun/Source path. POM coupling — тест выше с light enabled.
Дополнение на основной карте: ground/rock/bark/leaves/grass near/far/контровой, три облика и voxel/low-poly
внутри сферы; ползунки и движение сферы не вызывают rebake. Источник/сцену автора не сохранять тестом.
Авторская оценка зерна мягких теней и своего движения остаётся ручной.

Рябь voxel-травы: `test_grass_voxel_light_render.gd`, только native Forward+, основная карта в памяти,
записи только user://. Два фиксированных grass shadow ROI проверяют temporal RGB std<0.003;
сохранить ракурс/ROI при изменении композиции маршрута. Native captures: near/far, движение,
Hard/soft, три облика и voxel-сфера; bindings/отсутствие rebake/scatter и light cell/levels должны сохраниться.
Подстановка прежнего shader во внешнем negative control должна возвращать мерцание и нарушать gate.
Полёт мышью и оценка резкости/шлейфов остаются автору. UI/history/save при этой shader-only правке не повторять.

Зелёное покрытие/размер и оптическая глубина: `test_grass_ground_material.gd`, native Forward+,
user:// копия Pattern: validation, разрешённые grass depth controls/PNG и недоступная подтяжка пучков,
живой size preview (цвет/grass-light/POM согласованы), Undo/Redo размера/глубины/плавности, выключение0мм,
save/fresh reopen/discard и сохранность других глубин. Size/amplitude не должны пересоздавать неизменный height bank;
ссылки на исходные текстуры удерживает derived material. `test_grass_voxel_light_render.gd` — затронутый render gate.
Основная карта: три облика, поле/камера, near/far; свой ввод и заметность2мм остаются авторской оценкой.

Source rules: `test_terrain_surface_rules.gd` проверяет bitmap validation,
default/voxel preservation, geometry cache invalidation, dense/sectioned exact,
window/rebase/extension/copy isolation, draft без remesh, one Undo/Redo, Cancel,
clear, physics/floor, existing session Save/Reopen/Discard и смену вида.
`editor_test_terrain_surface_rules.gd` — настоящий Ember plugin в disposable QA:
controls/pick/press/release, Source heights/paint unchanged, no press remesh,
scene Undo/Redo, voxel switch/return, native Save/Reopen/Discard. Exit0 после
explicit FS scan; предыдущие два shutdown0xC0000005 и scan-aborted warning
не закрывают общую стабильность рабочего редактора. Свои input/125%/F6/weak PC OPEN.
`capture_terrain_surface_rules.gd` — saved Source rules при plain/POM, три light
presets × side/back, shared physics/pick/floor, существующие morph endpoints,
настоящая Player walk. Owners/limits — Terrain Authoring → «Ручные правила».

Shape LAB: `test_terrain_shape_study.gd` — plateau/crest preservation, Source
immutable/material independence, all tile height/normal seams, same mesh/collision
triangles, budgeted/direct job exact, Source Save/Reopen. Optional argv baseline
path сравнивает default field exact с frozen прежним Smooth script из evidence.
`capture_terrain_shape_study.gd` — A/B/C × plain/material ×3 presets ×side/back,
одна игровая камера, actual ray/floor/pick/navigation parity (<0.004мм), все seams
в пяти morph phases, POM4см/32, реальные controls (draft без remesh, explicit Apply),
Player150 ticks на склоне через seam. Targeted + smooth/cartoon/tools/uniform,
mountain morph/depth/mapping/painted/material workflow regressions PASS.
Ручной выбор формы, F6/мышь/near-far/weak-PC OPEN; permanent mask schema/editor
Undo/Save/Discard и скорость большой карты не реализованы. Owners — Terrain Authoring,
«Управляемая форма гладкой земли»; evidence — terrain-shape-study.

Перенос grass light workflow: `test_material_light_workflow.gd` проверяет
opt-in Pattern fields/validation/legacy, независимые palette variants,
small lookup update с прежним texture instance, Projection draft preview,
база не стирает ручные оттенки, подбор одним Undo, Save/Reopen/Discard.
WorldLook presets — один scene Undo/Redo, saved native Sun/Environment,
ambient source восстанавливается, azimuth/exposure/tonemap прежние.
`capture_material_light_workflow.gd`: GPU два реальных terrain-shader варианта
(изменяется только первый); два существующих grass/bevel LAB ×3 presets ×
side/back с фиксированной игровой камерой; transferred vs accepted LAB uniforms
RGB delta<=3/255 (measured<=2/255). Geometry/Source exact, POM4см/32 unchanged;
fill exact zero при shadow-disabled/light energy0, native UI preview/Undo/Discard
и короткая ходьба. Targeted + WorldLook/layers/patterns/depth/mapping/painted PASS.
Свой editor mouse/125%/Save→F6/weak-PC и large world remain OPEN.

Bevel LAB `compact_bevel_light_study`: `capture_bevel_light_study.gd` проверяет
две пары с игровой камеры/side+back sun, A=Sol pixels и возврат A exact,
GPU depth readback exact, sun-off exact, Source/mesh/collision/floor/POM и export
Save/reopen PASS. Вода frozen preview_time только для native QA. Ручные F6/B/L,
реакция фасок/тёмные швы/мерцание/свой проход/weak PC OPEN — Terrain Authoring.

LAB0б `compact_painted_light_study`: `test_painted_light_study.gd` — validation,
Source/height/mesh/collision/floor при A/B и morph, Player playback, save/reopen PASS.
Rays на верхних плоскостях камня и у границы тайлов совпадают с floor (<3мм)
в шести фазах; обычный Smooth default проверен на exact с прежним кодом в evidence.
`capture_painted_light_study.gd` — native Forward+, исходный renderer = disabled
study pixel-exact, A return exact, sun-off rim exact, back/lateral rim и grass on-off меняют кадр,
три Sun-позы с той же игровой камеры, пять morph-фаз,
кадры игрового прохода и GPU timings. Глубина Sol4см/32steps не меняется.
Tufts: compact_grass_field_study12×12м9621 clumps/423324tri, no collision;
малый6×6 сохраняется. Тот же test принимает optional scene path для обеих сцен.
root/material/footprint + inner coverage tested, toggle сохраняет Source/floor/POM,
export Save/reopen PASS; native roots совпадают с floor во всех шести morph-фазах.
Actual unique vertices: stone0, ground clearance >=-12мм, ни один пучок не скрыт.
Посадка проверяется заранее для трёх полей, ширина постоянна и >=30% исходной;
native проверяет фактические transforms против общего floor в каждой фазе.
Renderer baseline проверяется при T-off; T-on/off виден с игровой камеры.
H/mass lighting: no remesh/scatter/Source/floor changes, shared ground/cards flag,
export Save/reopen PASS. Native before/after в трёх Sun poses и H return exact;
H-off sun1 exact предыдущему полю, исходный depth regression PASS.
J/grass colour ramp: shared ground/cards flag, no geometry/scatter/Source changes,
export Save/reopen PASS; native три Sun poses, J return exact и J-off sun1
exact с принятыми мазками. Отвергнуты независимые размытые цветные пятна;
текущая рампа использует общие границы light steps при H-on, ALBEDO прежний.
Native рампы повторно PASS. Текущий low=.64 и shadow fill=.07: presets evening/day/night
× side/back с одной камерой/Source/POM — native PASS. Реальная directional тень
меняет тон; fill on/off exact при shadow-disabled и при light energy0. Это не
измерение глубины кроны. Custom low/tint/shadow/warm/preset Save-Reopen PASS;
source/geometry/POM при трёх preset unchanged. Исходный depth regression PASS.
F6 sliders/color/presets временные, Inspector сохраняет LAB exports;
production MaterialPattern editor/Undo/Discard для новых параметров ещё не сделаны.
Manual OPEN: F6/B/R/G/T/H/J/C/L/O/V/P, свой проход/ПКМ/F1, контактные тени без грязи,
читаемость камня/мазков и полного поля травы, тень героя, мерцание в движении,
просветы у будущих ступеней, полный morph budget и weak PC. Новая ручная оценка —
ослабленный тёмный мазок, оттенок реальной тени, день/вечер/ночь, F6 color controls.
Evidence/ограничения частичных тайлов — Terrain Authoring, «Живописный свет».

LAB глубины материала: `tools/test_material_depth_study.gd` проверяет immutable
Source/heights/paint/water/mesh/collision/floor/picking/navigation при A/B в
трёх существующих morph-обликах и промежуточных фазах, zero/off baseline,
private Pattern ownership, exported scene settings/Source Save-Reopen и no
camera remesh/CPU texture jobs. Fixed-geometry EmberPlayer playback A/B имеет
тот же endpoint. Native `capture_material_depth_study.gd`: Forward+1080p,
near/far/grazing/outer edge/material border/tile seam/actor, 3 облика/2 mid phases/12 поз,
zero pixel exact, water ROI2016 pixels exact/depth readback delta≤0.02мм.
`test_material_texture_mapping`: paired PNG в двух ролях/другом slot/масштабе,
generic factory/validation/Pattern Save-Reopen. Native GPU probe actual height
query: legacy negative control RED, periodic PASS на top и16× taller side;
actual geometric normal сохраняет масштаб в середине morph, CUSTOM0 убраны.
Targeted + material layers/smooth uniform/smooth cartoon/cartoon relief/pattern editor PASS.
GPU/CPU warm AB измерены отдельно (30FPS captures,120FPS timing,VSync off);
close +1мс ориентир не достигнут. Manual artwork/scale/relief/seams/motion/input/
weak PC и весь water/contact pipeline OPEN; owners/status — Terrain Authoring.

Проба объёмной фактуры: `test_cartoon_relief_study.gd` проверяет одинаковые
материалы двух fixtures, реальное изменение высот stone/sand/soil, швы/нормали,
точные mesh/collision triangles, physics/picking, Resource Save/Reopen и B
туда/обратно без изменения источника. Вторая проба: реальные pockets,
нормированные blend weights с GPU quantization, одинаковые веса на seam,
dense/sectioned blend attrs, cache colour roundtrip, distinct blend policy,
scene flag Save/Reopen и paint/Undo/Redo через соседнюю плитку PASS.
`editor_test_cartoon_relief_study.gd`: isolated native editor blend flag/paint/
Undo/Redo/Save/Reopen/Discard PASS.
Native Forward+ до/после с фильтрованным PNG optical relief и regressions
smooth/mesh/cache/WorldLook PASS; формы/переходы/near-far/ходьба/weak PC OPEN.
Сцена — `compact_cartoon_relief_study`, прежние runtime/editor owners.

Сгенерированный остров: `test_cartoon_generated_study.gd` проверяет крупную
основу из existing generation job, неизменность input и каналов воды/подводного
грунта, независимый surface seed, четыре роли, local offset bounds, Resource
Save/Reopen/B и physics/picking. PASS, включая прежнюю relief regression после
выноса общей математики в pure leaf. `editor_test_cartoon_generated_study.gd`
повторно использует native fixture QA: blend flag/paint/Undo/Redo/Save/Reopen/
Discard PASS. Новый остров/четырёхматериальные стыки/вода/ходьба/weak PC OPEN.
`test_terrain_surface_generation.gd` закрывает legacyzero, strength/scale/seed,
budget-independent immutable finishing snapshot, wet/outside/new-sections/cancel/
validation, старые планы, три UI units и Plan Save/Reopen, smooth preview parity.
`editor_test_terrain_surface_generation.gd`: stale preview, actual Apply without
regeneration, one terrain Undo/Redo, Plan settings Save/Undo/Redo, scene reopen
и Discard PASS. Export с surface params stripping PASS. По-прежнему OPEN:
ручные вид/input/near-far/ходьба/weak PC, четырёхматериальные стыки и вода.

Первый гладкий/мультяшный срез: `test_terrain_smooth_cartoon.gd` проверяет
affine height, общие heights/normals на tile seam, dense/sectioned mesh, источник
collision, floor/pick, navigation, style cache keys/UV2/пустой tile, brush halo,
Undo/Redo, Resource и scene Save/Reopen, необязательную PNG и локальный Cancel.
`editor_test_terrain_smooth_cartoon.gd` в disposable editor проверяет настоящие
кисть/EditorUndoRedoManager/Save/Reopen/Discard, существующий выбор вида земли
с Undo/Redo и PNG controls/Save/Reopen. Оба gate PASS; старые material/dock/mesh/
projection/cache/light/look regressions PASS. Scene —
`scenes/compact_cartoon_ground_study.tscn`; own view/near-far/края/берег, живые
кисти и ходьба OPEN. Гладкий режим пока до262144 колонок и без ground LOD;
32×32 блока — граница первого среза, а не performance acceptance.

Адаптация прежних кистей: `test_terrain_smooth_tools.gd` — восемь compact tools,
physical floor/pick, смена вида без изменения источника, material brush сохраняет
coverings/water/holes, selected area/strides/quarter/half/dense-sectioned/Undo/Save.
Native `editor_test_terrain_smooth_tools.gd` проверяет controls/press-release,
материал, направление Down, one stroke Undo/Redo, style/Save/Reopen/Discard.
Сценарии PASS; два shutdown 0xC0000005 после PASS, затем native clean exit;
точный C++ frame/причина OPEN. Обычные voxel Surface, old brushes, WorldEditor,
generator regressions PASS. Native-selector/live view/mouse/weak PC/objects,
объёмный smooth вид OPEN. Bulk generator разделён: `test_terrain_generation_split`
проверяет paint/cap/flow/wet/source/budget/cancel/validation, независимые действия
и параметры, общую brush maths/Plan/UI. `editor_test_terrain_generation_split`
проверяет detail и coverage exact preview/Apply, one Undo/Redo, stale preview,
Plan settings Undo/Save/Reopen и Discard; PASS с clean exit. Художественный
coverage view/ручной input/weak PC OPEN. Крупные зоны реализованы:
`test_terrain_coverage_zones.gd` PASS — grass base/soil size+frequency/broad
slope/actual-water distance, zero soil/sand, seed/budget/dense-section parity,
source channels/detail/macros/legacy knobs independent. На flat24×16 edges:
legacy12369→large442; это тест фрагментации, не художественная приёмка.
Plan10 paint bitmaps: changed/same-colour stroke protection с одним Undo,
explicit whole-selection protection/release, copy safety/rebase/roundtrip,
legacy guard/cancel/limits/UI PASS. Старые Plan/composition/brush scale+
overlap/generation split/surface generation/WorldEditor/smooth placement PASS.
Native Forward+ `editor_test_terrain_coverage_zones.gd` PASS: real paint input,
paint+locks atomic Undo/Redo, protect selection/Undo, profile/knob stale,
protection-only stale refusal, exact preview/Apply, coverage Undo оставляет
ручной мазок/защиту; отдельный detail не меняет covers/locks. Recipe control
Save/Undo, Source+Plan10+locks Save/Reopen/Discard и clean exit PASS.
Свои художественный вид/input/weak PC OPEN; старые authored assets не пересозданы.

Локальная аномалия земли: `test_mountain_anomaly_study.gd` PASS на32×32м/18м
горе, два пятна/8 tiles. Проверяет global seams и exact outside, промежуточные
фазы0/25/50/75/100%, mesh/collision/shared-floor rays, неизменные coverage/Source,
возврат к базе, runtime slider/три кнопки/play-pause и scene Save/Reopen.
Native Forward+ clean exit PASS, фазовые кадры; max phase23,146мс после physics
partition. Smooth cartoon/tools/shore/placement и generation split regressions
PASS. Это тестовая сцена, без новых editor authoring commands/Undo или игровой
схемы аномалии. Свои F6/вид/движение/ходьба/weak PC/большие площади OPEN;
short bevel heightfield, навесы/отдельные кубы и ground LOD не реализованы.

Общая форма fine16 / Plan11: `test_terrain_fine_land.gd` — точная выборка каждой
колонки/высота1, отсутствие потери покраски, совпадение при разных бюджетах,
граница выделения/cancel, массив repeat/off, смешанные старые/новые слои,
version guard, UI defaults/roundtrip/stale, Apply/Undo/Redo/Save/Reopen.
`capture_fine_land.gd` — native Forward+ однотонное/материальное сравнение,
три облика того же Source, mesh/collision/field parity и точный возврат.
Legacy generator/plan/composition/mountain/river/road/anomaly regression сохраняются.
Авторская оценка силуэта/грязи переходов, реальный input/weak PC OPEN.

Расширенный study64×48м: `test_meadow_anomaly_walk.gd` headless PASS — обычный
smooth guard/явный study opt-in, гора сбоку/river+flow, прежний EmberPlayer,
standing rise/fall и walk forward/reverse30/60/120Hz, diagonal/foothill edge,
supported completion без stuck step, capsule contact/carry, ceiling pause/resume,
Source/paint/water/flow invariance, scene Save/Reopen без runtime actor/progress.
Native mound/continuous controller playback/ceiling PASS, clean exit;13 tiles,
phase max54,138мс, не acceptance полного frame budget. Existing
explore stepping (включая high wall/ceiling), camera-relative movement, old32m
anomaly, smooth cartoon/placement, generation split и world look panel PASS.
`test_smooth_uniform_material` PASS: exact attributes/field/collision, halo mix
и empty palette fallback; uniform tile109мс против497мс, не whole-map benchmark.
Manual F6/камера/input/вид/first build/weak PC OPEN; general large world/LOD,
all actors dynamic support и jump через1м стены вне этого study.

Гладкий берег обычной плоской воды: `test_terrain_smooth_shore.gd` — fractional
ground-plane intersections, нулевая глубина контакта, source/ground collision,
tile depth seams/dense-sectioned, dry depression/local levels, legacy/volume,
smooth cache policy и LOD boundary PASS. Native surface-generation QA дополнительно
сравнивает water preview/Apply arrays и точный water Undo/Redo; Save/Reopen/Discard
PASS. Native Forward+ остров снят до/после. Свои берег/near-far/движение/weak PC,
точный wet/contact в узкой derived полосе и volume/waterfall/swash OPEN.

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

Soil v4 production transfer17 Oct: `test_soil_editor_transfer` checks exact accepted
256px artwork, legacy opt-in defaults, existing PNG controls/history, fallback
paint Undo, Save/Reopen/Discard, signed PNG role/periodic metadata, unchanged
height/roughness/finish/light and non-soil lookup rows. Run with the output folder
containing before/content/terrain_materials/soil_grain.tres. Six targeted tests PASS;
`test_compact_material_dock` width gate remains OPEN: frozen/current minimum326px
versus expected302px from old light/rim controls; new PNG controls do not widen it.
`capture_soil_editor_transfer` verifies ordinary projection atlas refresh without
remesh, source/paint/physics,54 pairs/54 exact LAB matches/54 exact returns/108 motion
frames, original stone POM on/off/return, native material panel. `--cold` reloads
published material/terrain in a new process and compares six game frames exactly.
Six frozen old-shader controls: at most3 pixels/max2RGB8 rounding (separate bounded
gate≤32/max2), never report old shader as pixel-exact. New soil height stays LAB.
Evidence `ember-soil-editor-transfer/`; manual F6/input/weak-PC acceptance OPEN.

Road B production transfer17 Oct: `test_road_editor_transfer` checks existing
cartoon_sand tint b9a47c/span1.5m/exact shared accepted PNG, periodic colour-only
metadata, existing PNG controls/tint Undo/Redo, Save/Reopen/Discard, unchanged
finish/height/roughness/light and all other material sampling/mean/tint inputs.
Source texture stays256px after bank builds (resize/mip preparation uses duplicate).
`test_material_texture_mapping` now isolates legacy periodic=false explicitly.
Seven targeted tests PASS including soil editor regression. Configurable existing
soil capture plus road subclass:54 pairs/54 exact LAB/54 exact returns/108 motion,
POM on/off/return and native panel; road cold Save/Reopen six frames strict exact.
Historical soil close comparison uses --cold --close-only --historical-reference:
separate sparse compiler-rounding bound≤32/max2 with exact count and metrics saved;
ordinary cold remains strict. Six frozen road shader controls≤3 pixels/max2RGB8.
Historical soil:4 exact frames;2 evening frames differ at grass-edge(1,46) only,
one pixel/1RGB8. Isolated soil region exact in all6, recorded by report check.
Smooth production/other looks LAB; no new depth. Evidence ember-road-editor-transfer/;
personal live/weak-PC and old UI width gate remain OPEN.

Stone painted colour transfer17 Oct: test_stone_editor_transfer verifies exact raw
B/C paint256px, tint90938f/span2.4m, colour-only periodic metadata, unchanged
authored height/roughness/finish/light/other slots, existing panel Undo/Redo/manual
paint/discard/save/reopen and optional POM binding unchanged after bank publication.
Eight targeted tests PASS including depth/paint-relief and road/soil regressions.
capture_stone_editor_transfer uses actual normal projection shader/material for
54 pairs/54 exact recipe-colour replay/54 returns/108 motion; six cold game frames
exact. Geometry unchanged; two derived textures LAB. Historical4cm/32 POM tested
separately on/off/return; no activation on normal maps. Shader source unchanged,
same compiled resource used for frozen-source guard; initial separate compilation
2 pixels/max9RGB8 delta retained as failed diagnostic, not pixel-exact proof.
Six historical POM-stand frames exact against preserved road-transfer reference;
comparison uses copied controls/output so previous report stays unchanged.
Evidence ember-stone-editor-transfer/; personal live/weak-PC/new3mm choice OPEN.

Grass ground material transfer17 Oct: test_grass_editor_transfer compares exact
embedded accepted artwork/base/span/profile, unchanged other authored fields and
other material lookup inputs, ordinary editor light preview/manual painting/history/
Save-Reopen/Discard.10 tests PASS including light workflow/grass recipe/depth and
stone/road/soil transfer regressions. Native capture uses actual production bank:
54 pairs/54 exact recipe-colour replay/54 returns/108 motion, editor lookup identity,
GPU preview Undo/Discard exact, no remesh; grass-only ROI(1120,650,350,190) responds
to real sun shadows at all3 presets, exact returns. Clump shapes/count/transforms
unchanged. Bank1254→256 means other-layer GPU resampling may differ; only source
art/parameters are claimed unchanged. Existing POM checked separately on/off/return.
Six fresh-process game frames and six historical POM-stand frames exact; previous
report/reference preserved through copied controls in current output folder.
Evidence ember-grass-editor-transfer/; manual live/weak-PC/UI width gate OPEN.

Accepted rock form transfer17 Oct: test_rock_shape_transfer checks exact accepted
occupancy/part IDs, canonical Source validation, 372 triangles vs independent LAB
reference (max vertex delta1.823mm, gate2mm), same render/collision faces, missing
profile negative control, existing object Session/cache/save/Undo/Redo/reopen.
Sculpt falls back to exact voxels; profile arrays must not alias between drafts.
Canvas tracks solid_surface in dirty/save/discard. Native editor test exercises
actual scene open/Canvas Save/Undo/Redo/Discard/ordinary scene Save, user:// assets.
Native saved-scene reopen covers3 light presets×2 directions×2 cameras;12 cold
frames exact, extra overview6 frames, real shadow on/off/return exact. Six rock
physics rays and transformed floor queries agree≤0.1mm; real Player capsule lands
on the plane. Compact navigation reads the new physical surface/cache revision.
Evidence ember-rock-shape-transfer/. Manual art/F6/weak-PC and global conversion OPEN.

Rock form look 20 Oct: test_rock_form_transfer (native) — library mesh has CUSTOM0 and
the same triangles/collider as the previous prefab, floor equals physics ray, GPU rim
lookup 0.5 + crisp band, silhouette frame data CUSTOM1..3 present, 10 mm width, 6 frames match the chosen option (Wb); test_rim_width_control — validation, GPU lookup alpha, live slider preview, Undo/Redo, Save/Reopen, Discard; map rim switch/real shadow/return exact, and with the sun off the rock
image is unchanged by yaw 22.5/45° or a 1.3 m shift (legacy changes ≈200k pixels).
publish_rock_form checks positions bit-identical and paint/UV unchanged. measure_rock_form_probe
and capture_rock_form_probe keep the A/B/C comparison. Manual art/streaks/weak-PC OPEN.
Detailed look 20 Oct: test_rock_detailed_look (native) — key 6 keeps the collider/floor/Source (living faces of
the stone shown, zero pull = the hull), plain
shader for low poly, height map equals the accepted probe C2 (≤1/255), 9 frames within mean 0.02 of the
probe (zero pull), depth sticks to the rock under yaw/shift, key 5 returns 9 low poly frames pixel-exact;
test_depth_control — validation, live amplitude, height re-derived on release only, Undo/Redo, Save/
Reopen, Discard. Motion/flicker, low angles and weak PC OPEN.
Living faces 22 Oct: test_rock_living_faces (native) — stone pull 30 mm validated (NaN/-1/61 rejected), hull
build unchanged by the face refactor (equals the saved library mesh), living mesh 4676 triangles/111 faces/0
fallback, max displacement ≤3 cm (30 mm) and ≤6 cm (60 mm), every hull corner present unchanged, extent within
hull + pull, outward winding, no degenerate triangles, cached + deterministic, zero pull = no mesh; in the scene key 6
uses it with same collider and floor, depth stays bound, editor draft pull 60/30/0 swaps mesh/saved/hull, 5→4→6
reuses the cache, low poly frames return pixel-exact; test_depth_control also covers the pull slider
(release-only preview, Undo/Redo, Save/Reopen). Manual art acceptance, motion/low angle and weak PC OPEN.
Rock in the map 22 Oct: test_landscape_rock_placement (native) — landscape_compact reaches play with
PaintedRockGroup at 16 units per block, collider on the world layer, no floating (0), embedding ≤8 units (5), ≤6% of
footprint columns covered by ground, no water columns, clear of the player start, map floor query finds the rock,
solid_local_unit_m = 1, living faces at metre scale (111 faces, ≤3 cm), depth amplitude 0.32 units / fade ×16, collider
unchanged, Source untouched; frames day/evening, low/detailed/voxel in evidence landscape/. GPU close view: no rock 0.97 ms,
low poly 0.97, detailed 1.8 ms. Map light (mode 0) look OPEN.
Ground and light of the map 22 Oct: test_landscape_ground_materials (headless) — landscape_compact keeps its size
(384x400), heights 12..40 and 80620 wet columns exactly; palette roles soil/grass/sand/grass, painted material ids validate;
no column uses slot 4 (77600 moved to grass); Map uses smooth ground, material blend, light mode 1, day sun 1.15 with 560-unit
shadows, SSAO radius 10.4. test_compact_world_map, test_native_map_references and test_landscape_rock_placement still PASS
(rock does not float). Cost: first launch after a terrain change ~15 s, cached ~2 s (was 0.9 s); GPU game view 0.8 -> 2.4 ms.
Author acceptance of the look OPEN; weak PC not measured.
One anomaly sphere 22 Oct: `test_world_anomaly.gd` PASS in native Forward+ on a copy of
landscape_compact: shared band, both inner looks, three positions, 180 motion/radius frames with
zero geometry preparation and stable mesh/scatter/collision/floor/Source; material and grass edits,
global-look suspension, Undo/Redo, user:// save/reopen/discard. Isolated GPU coverage verifies that
voxel leaf cells draw zero pixels outside/in low poly and detailed cards draw zero inside voxel.
`test_world_anomaly_authoring.gd` PASS; `editor_test_world_anomaly.gd` PASS with the real panel and
EditorUndoRedoManager, native save/reopen/discard/validation; internal displays retain original editor owners.
Evidence `Documents/Codex/2026-10-22/ember-world-anomaly/`. Manual shared-boundary motion, rock/bark
silhouette, leaf/grass transition, brush/selection/input, walk-through and weak PC OPEN; one sphere only.
Anomaly editing regression 23 Oct: `test_world_anomaly_editing.gd` uses the real flatten brush on a working copy:
no preparation during strokes/history, unchanged prop displays survive, explicit preview coalesces edits,
grass cancellation/material reuse and spatial-group coverage, isolated terrain save/reopen/discard/validation.
Run headless for CPU pauses; `editor_test_world_anomaly.gd` in a disposable native Forward+ editor checks
paused opening, explicit preview/return, real EditorUndoRedoManager, save/reopen/discard and ephemeral mode.
No authored map writes; final FPS under an idle GPU and mouse/feel remain manual gates.
Rock look switch 20 Oct: test_rock_look_switch (native) — key 4 builds one quad per exposed
voxel face (11094 vs independent count), corners on the 1/16 grid, outward winding, same
collider/floor/Source; pattern sticks under yaw/shift in the voxel look; key 5 returns the
hull mesh and 6 low-poly frames pixel-exact; voxel mesh built once and reused.

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
Цельный сценарий 23.10 на основной карте/в рабочем native редакторе и Forward+ игре1600×900 PASS:
мазок → один Undo/Redo → штатный Save → fresh validation → discard новой правки → reopen;
Undo/Redo и сохранение параметров сферы, три облика editor/runtime, движение персонажа с опорой,
явный preview/возврат к земле и движение сферы без пересборки. Данные/коллизии между обликами общие.
Тестовый след/настройки возвращены, исходные SHA256 карты и terrain совпали. Replay/evidence и границы —
`docs/directions/world-map.md` → «Принятый контракт · цельная редактируемая локация».
Команды не закрывают ручную мышь/ощущение/общий вид; полный набор не запускался, код не менялся.


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
`tools/test_compact_brush_material_depth.gd` воспроизводит понижение ниже cap в schema 1/2:
live Source/preview, тонкий слой, большой span-снимок, Undo/Redo/Cancel, user:// save/reopen/discard
и validation; отдельно проверяет Resource/projection writers и обновление только глубины.
`tools/editor_test_compact_brush_material_depth.gd` — disposable native Forward+ fixture:
штатные World Editor session/«Сохранить мир», EditorUndoRedoManager, reopen/discard и физическая высота.
Для ручной приёмки заново открыть сцену → «Площадка» вниз → Undo/Redo → Save/reopen → боковые материалы.
Боковая покраска27.10: `test_compact_brush_material_depth -- --side-only` проверяет dense/sectioned,
wall pick detailed/voxel, сохранение верха/высот, новый material slot в detailed mesh, одинаковую
площадь/field, Source==preview, validation/Undo/Redo/Cancel/save/reopen в user://. Прежний height-only
worker — `test_terrain_shape_update`; окрашенные bands не используют corner-only layout reuse.
Native `editor_test_voxel_merge_dock -- --terrain-wall-only`: копия main, прежние level/protect,
стенка через WorldEditor pick, GPU overlay, EditorUndoRedoManager, Save/fresh reopen/Discard,
три вида локального участка. Color-only regression low-poly: мировая высота painted band при тех же
vertices/normals/count; Forward+ `test_compact_brush_material_depth -- --side-look-capture` смотрит
сохранённый участок QA Source с диагностической палитрой, не создавая карту.
Общая холодная загрузка не входит в этот gate; ручной low-poly input
по упрощённому силуэту OPEN. Авторскую main/Source не менять и новых рабочих карт не создавать.
`tools/test_terrain_shape_update.gd` — fixture-only regression высотного CPU worker:
точное совпадение vertex/normal/paint/UV, collision и floor field с полным build;
старое material kernel/smooth math и low-poly сравниваются с исходным алгоритмом.
Включены наружные стены/дыра/high origin, paint/topology invalidation и cancel.
Dense FieldJob сравнивается с прежним generic sampling на той же fixture.
`tools/editor_test_terrain_live_brush.gd` — native Forward+ regression на disposable fixture:
повторное изменение опубликованных mesh vertices **до pointer-up**, отсутствие промежуточных
Undo и одна операция на мазок. Проверяются Undo/Redo, cancel → немедленный новый мазок,
отсутствие позднего repaint старым worker (mesh/physics/field сравниваются с Source),
штатные save/fresh validation/reopen/discard. Устанавливать как временный EditorPlugin
только в `ember-rock-pilot-*` с app name `Ember Rock Pilot`; данные в `user://`.
Прежний PASS кадров не закрывает live gate: до исправления ни одного обновления за 32 события,
несмотря на плавный ввод. Native input replay на копии основной карты измеряет также
первое и повторные обновления до release во всех трёх обликах; evidence — тот же тематический owner.
Focused набор исправления рывков 23.10: этот тест, cap-depth/history/save и uniform materials PASS.
Native Forward+ input replay на копии основной карты, raise/smooth UI r=3.5/depth=4/detail
(UI округляет запрос 3.31; native fixture использует точно 3.31),
32 отпечатка/кадра, три облика, видимая карта: параметры/замеры и evidence —
docs/directions/editor.md → «Результат». Native Undo/Redo/cancel/save/reopen/discard PASS.
Полный набор не требуется: Resource/schema/качество и прочие инструменты не менялись.
Авторская приёмка 23.10: плавность и живой показ земли подходят, небольшая задержка приемлема;
крупные маски по наблюдению автора также без явных зависаний. Все сочетания предельных радиусов,
стыки/облики, ручные история/сохранение и предпросмотр аномалии остаются OPEN.
Предельные UI маски radius8 проверены scripted native input на копии основной карты:
circle/square, raise/smooth detailed; худший square — также voxel/low-poly и coarse.
После оптимизации dense input: max кадра107мс, первый показ165–186мс (detail); полная готовность
после release до2.5с. Parity с прежней кистью на фиксированных клетках всех7 режимов/2 форм,
cap-depth dense/sectioned/broad и native fixture live/history/save/reopen/discard PASS.
Последняя ускоренная кисть принята автором 23.10 как пригодная к работе: остаточные задержки
некритичны. Отдельная ручная матрица всех предельных режимов/стыков/обликов и save-цикл
этим отзывом не закрыты; полный прогон не запускался. Дальнейшая полировка — по конкретной помехе.
Повторный короткий native replay на свежей сохранённой копии: первый hover25мс (старые254мс
не повторились), первый press max square275мс, последующие0.5с max56мс. Cancel/source/projection
и завершение очередей PASS; разовая пауза press не исправлена. Подробности/evidence — editor.md.
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
Smooth опора (2026-10-13): `test_terrain_smooth_placement.gd` PASS — grove/
placement используют ту же physical поверхность, source и voxel0 сохранены;
dense/sections/seed/budget, water, translated/rotated/scaled frame, style stale,
limit/cancel, ручные props, Apply/Undo/Redo/Save/Reopen. Exact old/new float32
field parity и old groups/eight brushes/generation split/shore PASS.
`editor_test_terrain_smooth_placement.gd` Forward+ PASS: native tree grove
support и четыре placement props; preview=Apply, stale style refusal,
Undo/Redo/manual protection/Save/Reopen/Discard/source, clean exit.
Own input/посадка/footprint и weak PC OPEN; пять probes не доказывают посадку
любой сложной нижней геометрии. Ground/water source и Plan schema не расширены.
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
количество/доли/ряды остаются отложены; отдельный срез групп — ниже.

Группы placement (2026-10-12): `test_terrain_plan_placement_groups.gd` проверяет
повтор seed/budget, отличие реального planner от uniform, zero-strength точное
совпадение, density endpoints, стабильные pose/variant общих кандидатов,
maximum seed, invalid pattern/NaN/range, v8 recipe roundtrip, UI 302 px,
invalidation strength/size/mode и отсутствие полей у старого UI/grove.
Дельта групп: Apply=prepared pose/count и возврат исходной пустой сцены PASS;
унаследованы mixed footprint/obstacles, caps, atomic Undo/Redo, protection,
save/reopen/Discard/recovery/export strip. Legacy grove, plan и composition PASS.
На QA-копии скриптовый native Forward+ 24 м проверил group recipe Save,
size/strength stale, Preview=Apply, Undo/Redo/repeat, manual shift/off/on,
Save/Reopen/Discard. 9 tree+bush props; F6 — 9 colliders, floor/движение PASS.
Снимки dock с контролами и 3D просмотрены; mouse/input/художественная приёмка
и большая населённая карта OPEN. Evidence и QA-script:
`C:/Users/novos/Documents/Codex/2026-10-12/new-chat-2/outputs/ember-groups-verification.json`.
Ручной сценарий: + Объекты → набор/плотность около 60–70% → Группами →
кучность/размер → Preview/Apply → Undo/Redo → Ctrl+S/reopen. Проверить просветы,
склон/воду/дорогу и ручной сдвиг одного объекта; старую рощу открыть без Save
и убедиться, что она не меняется. Плотность 0%/100% сохраняет прежний отбор;
число объектов не является фиксированной целью.

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

Прибрежная опушка25.10: `test_terrain_smooth_placement.gd` PASS с расширенным fixture
768×400 и Map budget524288: размещение/опора работают, default cap продолжает отклонять
такой размер; прежние support/section/style/frame/cancel/manual/history/save checks PASS.
Fixture BoxMesh переведён в ArrayMesh перед сохранением, как реальные native props.
`test_detail_brush_rebase.gd` воспроизводил lookup/erase после west rebase; PASS после
поиска по frame: отдельный новый мазок, прежняя маска/Cancel, старый ластик/Undo,
разные flower Sources и library variants/mixed не смешиваются.
Native main-copy PASS: editable plan/Apply/Undo/Redo, brush Cancel/Undo/Redo, Save/reopen/
Discard, validation,0/1/2/0; персонаж пересёк центральный просвет до X≈-234 с опорой тела.
Publication сохранила33 прежних node-блока и terrain bytes; добавлены7 props/47 detail patches,
четыре placement-области. Fresh canonical load:74 Props,5 regions,стиль1/default look2 PASS.
Evidence — `C:/Users/novos/Documents/Codex/2026-10-25/ember-coastal-copse/`.
Ручная художественная оценка/мышь/плотность OPEN; sphere/FPS/weak-PC не запускались.

Западная поляна25.10: `test_terrain_mainland_extension.gd` PASS — extent384×400 →
768×400 без заполнения лишнего края, retained каналы, dry mainland join/материал,
мировые высоты при origin_y=-32, прежний island sampler, validation/plan save/reopen,
UI mainland/нулевой уровень моря. `test_compact_section_selection.gd` PASS — signed
extension, stale/cancel, old world transforms включая сферу, history/save/reopen/discard/
recovery. `test_terrain_generation_split.gd` PASS. `test_terrain_anomaly_section_materials.gd`
PASS — все четыре боковые грани carrier, цвета/overrides/topology совпадают dense/sectioned.
Focused wave clock reprepare PASS; полный водный прогон не запускался.
Native Forward+ на данных main:0/1/2/0, реальный player input через старый стык на
новую землю с опорой тела; сфера готовится и двигается без нового prepare PASS.
Публикация сверила все прежние payloads/authoring masks/world transforms и Source UID;
fresh canonical load проверил сохранённый budget до Source, стиль1/78tiles/очередь0.
Evidence — `C:/Users/novos/Documents/Codex/2026-10-25/ember-new-clearing/`.
Ручной ввод/вид пологого стыка и удобство параметров OPEN. Полный suite/FPS/weak-PC
не проверялись; холодная QA загрузка без сферы22–25с, подготовка сферы заметна.

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
Детальный берег24.10: `tools/test_detail_swash_shore.gd` в native Forward+ проверяет
подклеточное пересечение реальной наклонной земли, сухую сторону, возврат legacy
и неизменность Source; после отзыва также continuous front foam внутри raw-dry
клетки, сухую/глубокую стороны и прежний width control. Два дополнительных RED→PASS
pixel-сценария: calm sheet и shallow trailing face не белятся как новая кромка;
advancing face остаётся пеной. Это защищает устранение двойной полосы, воспроизведённой автором.
`test_detail_swash_geometry`
RED coarse span11.31→PASS near1.41/far11.31, неизменные Source/collision.
GPU test сверяет RGBA carrier: Rage/Gunclamped/Bcrest/Agrain, query(true), прежний
state и перенос всех каналов. Native PASS702сравнения. Web/pattern/trails функции
byte-identical к входу исправления. Текущий main gate: calm/approach/фактический
пик0.66/retreat, detailed+voxel, два ракурса пика и low poly —11кадров;
Water mesh/поля не пересобираются. Geometry/history gates выше повторно не запускались.
Предыдущий gate320wet/query/contact в `ember-smooth-shore/` не повторялся, query не изменён.
Scene/Source SHA прежние; текущий evidence — `C:/Users/novos/Documents/Codex/2026-10-24/ember-double-front/`.
Ручная оценка набега/спада/обоих ракурсов OPEN; это не приёмка следов/обтекания.
«Живая поверхность»24.10: `tools/test_water_crest_foam.gd` native Forward+ PASS:
редкое видимое покрытие, рост перед пиком/decay/expiry, отсутствие во впадине, выключение
strength/amount/wave height/speed и рост покрытия от amount. Используется настоящий
shader fragment/pattern; прежняя волновая математика/web/pattern/sea trails сохранены.
`tools/test_water_crest_controls.gd` PASS на user:// settings fixture: реальная панель,
один Undo на drag/Redo, атомарная F6 validation/snapshot history,
save/fresh reopen/discard. Проверка мыши/горячих клавиш этим не заменена.
На main в памяти14native кадров: четыре фазы9/13.05/14.95/17.1с во всех трёх
обликах плюс два ракурса открытой воды на пике; поля1раз/mesh identity прежние.
`test_detail_swash_shore` PASS; geometry/GPU history suites не повторялись.
Source SHA прежний; Scene меняет только четыре одобренных foam preset значения.
Текущий evidence — `C:/Users/novos/Documents/Codex/2026-10-24/ember-water-liveliness/`.
Текущий повтор этого render gate — «Пена по волне» ниже; controls/save не повторялись.
Авторская оценка редкости/белизны/движения и длительности OPEN; shader-frame PASS
не закрывает всю воду, следы или обтекание. Отдельного GPU benchmark здесь нет.
«Цвет и прозрачность»24.10: `tools/test_water_color_render.gd` native Forward+ PASS:
defaults совпадают с прежними gradient/transmission, оба цвета и endpoints меняют
реальный fragment, мягкость/плотность/прозрачность дают ожидаемые крайние значения.
`tools/test_water_color_controls.gd` PASS: два реальных picker/пять slider, один Undo
на popup/drag, Redo, непротиворечивые endpoints, атомарное отклонение invalid/NaN/alpha,
F6 bulk history, перевод метров16/32, save/fresh reopen/discard и сохранность Sun/foam.
`test_world_look_panel.gd` regression PASS. Main-map в памяти: цветовой вариант в трёх
обликах, opaque/clear/restored; старый/новый default ROI delta0.0001283, fields1 и
неизменные Water mesh refs. Scene/terrain SHA прежние, новый цвет в карту не записан.
Evidence — `C:/Users/novos/Documents/Codex/2026-10-24/ember-water-color/`.
Ручные picker/drag/горячие клавиши и художественная оценка собственных цветов OPEN;
берег/history/контакты не менялись, их suites автоматически не расширялись.
«Единое взаимодействие объектов»24.10: `tools/test_water_interaction_field.gd`
native Forward+ PASS: тихая вода не получает возмущение от неподвижного тела,
движение создаёт отклик в том же поле, остановка сохраняет/затухает историю,
incoming воздействует на стоящее тело, перенос наследует state, finite/CFL bounds,
контакты помещаются с absorbing margin, allocation не выдаёт пятую область за готовую.
`tools/test_water_interaction_controls.gd` PASS: existing prop water flag/radius,
derived component lifecycle без второго saved node, move Undo/Redo, live mode/history,
недоступность legacy arc-only controls в live, save/fresh reopen/discard на user://.
Native main в памяти: один новый painted rock+герой+спутник, calm0/reaction_count0,
обычное движение без field replacement/bake, stop, incoming/три облика, дальний
перенос с private background preparation; fields1 и прежние Water mesh refs.
Репрезентативный handler CPU p50≈0.73/p95≈2.45/max≈4.08мс, 1–2patches на текущем
ПК/30FPS cap; не полный FPS/startup/weak-PC benchmark. Одно поле p50≈1.37/p95≈1.75мс.
`test_compact_wave_obstacles` повторён для изменённого leaf: static cache/CFL/sea/query,
GPU baked/live parity и vertex_error≈0.000545 PASS; `test_water_contact_boundaries` PASS.
`test_landscape_water_integration` явно mode0 и без нового authored prop в fixture:
startup/hide/show/stop/dry/add/remove analytic fallback PASS; это не замена main live gate.
Source SHA прежний; Scene меняет только `WaterInteractionRock` и live mode2.
Main/refraction/радиус сложной формы требуют авторской оценки; мышь и реальные
editor hotkeys не проверены API. Главная приёмка воды/полная fluid simulation OPEN.
Evidence — `C:/Users/novos/Documents/Codex/2026-10-24/ember-water-interaction/`;
границы physics/render/CPU и владельцы — Water Rendering → «Единое взаимодействие объектов с водой».
«Пена по волне»24.10 — shader-only, без смены settings/document/session. Native Forward+
`test_water_crest_foam.gd`: RED→PASS для видимости на пике и подъёме, непрерывности seed
через пик, распада/истечения и скрытого стыка циклов при speed2/lifetime4; прежние zero/
trough/amount gates PASS. `test_water_contact_foam.gd`: RED→PASS для отсутствия замкнутой
обводки в live field, входящей высоты без рассеяния и истечения. Активные клочки,
strength0, width/верхняя часть диапазона, sharpness и legacy path PASS.
Main в памяти: полный цикл detailed, шесть фаз×два ракурса до/после; look1/2 — по
два ракурса одной фазы. Стоя/ход/остановка тел — оба ракурса до/после, плюс остановка
look1/2. Всего56PNG; поле берега1раз, mesh refs прежние, Scene/Source/controller/field/
wave include и принятые foam web/trails/shore byte-identical. History/save/physics suites
не повторять без изменений этих owners. Широкий FPS benchmark не проводился.
Авторская оценка движения OPEN. Evidence — `C:/Users/novos/Documents/Codex/2026-10-24/ember-foam-by-wave/`.
Контроллер камеры во время этого QA обновляется штатно. Ранее замороженный QA мог
оставлять floor camera в старой позиции (17.46м против0м при обновлении); большой
прежний дефект преломления здесь не повторился, причина/ручная проверка остаются OPEN.
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

`tools/test_landscape_water_integration.gd` — native Forward+ на основной карте в памяти с user:// sandbox:
обычный startup обязан сам подключать поздно появившихся героя/спутников; ручной _make_contact_texture запрещён
как подмена этого gate. Проверяет отдельные shader-дуги, hide/show, stop/dry, позднее добавление/удаление
статичного контакта и отсутствие пересборки береговых полей. Скрытые могут оставаться в кэше, но не в upload/бюджете.
Свой F6-проход и форма пены/волны — ручной gate; Source/Scene не сохранять. Без schema/UI/save изменений
прежние проверки Undo/Redo/reopen этого водного интерфейса не повторять.

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

## Оригинальная Хоши в exploration27.10 — technical PASS, manual OPEN

Контракт/owners/сборка — `docs/directions/characters.md` → «Сделано без приёмки».
Игровой toon follow-up: native `test_hoshi_world_light.gd` PASS — та же модель с/без
невидимого сверху перекрытия света: средняя яркость ROI0.083826→0.063988 (drop0.019838).
Negative control только обхода ATTENUATION даёт drop0.000330 и не проходит тот же критерий
drop>0.012. Исходные текстуры/REST не переписываются; отдельно адаптированы unshaded глаза/
брови и world-lit обводка. Основная карта снимается с сохранённым светом, реальным деревом,
тем же местом без shadow occlusion и солнцем; сфера отключена только в RAM, чтобы изолировать
реакцию персонажа на обычный свет. Evidence — `D:/hoshi-world-toon-2026-10-27`.
Персональная оценка лица/цветов/ступеней/обводки и поведения в движении OPEN; вкладка/параметры
персонажей в этом срезе не добавлены. Детализация каскадов вокруг игрока — отдельная открытая задача.
Follow-up «лесенка на земле»: native main split0.1/0.25/0.3, camera200/130/поворот просмотрены.
Увеличение первой зоны улучшило обычную тень, но с полной18м сферой выявились линии земли;
candidate откатан, production split0.1 сохранён. На одинаковом полном voxel main кадре при
split0.25/той же геометрии отключение voxel light flags убирает крупную сетку тени персонажа:
`sphere-resolution/tree-close/voxel-quant25.png` vs `voxel-noquant.png`.
Сетка света LIGHT_VERTEX — подтверждённый источник этих ступеней. Автор уточнил: пиксельные
тени внутри voxel-аномалии нужны; подробные тени должны возвращаться снаружи, low-poly имеет
собственный облик. Глобально сглаживать voxel shadows нельзя; открыта именно чёткость/возврат
детального света за пространственной границей, а не выбор пиксельности внутри.
Evidence и2×одинаковые crop — `D:/hoshi-world-toon-2026-10-27/shadow-grid-comparison.png`.
После уточнения автора Sun split0.3 сохранён: подробная зона30м вместо10м, atlas4096/2каскада/
полная дальность100м/blend прежние. Native main с полной18м сферой и QA receiver offset0:
одна точка/камера, поле внутри/на границе/снаружи/повторно снаружи, отдельно low-poly просмотрены.
Внешняя тень после voxel→detail возвращается: mean RGB ROI0.002538<0.005 PASS;
inside pixel look не выключался, shader изменений нет. Evidence —
`D:/hoshi-shadow-transition-2026-10-27/return-check.json`, `transition-comparison.png`.
Тонкие тени voxel-ступеней заметнее с новым каскадом; bias/receiver-пробы в production не переносились.
Авторская оценка этих линий/непрерывного прохода/других дистанций OPEN.
`test_hoshi_player.gd` native Forward+: загрузка private original VRM-derived сцены,
явный skin→Skeleton binding (регрессия T-pose при разных defaults двух проектов),136 REST unchanged,
скрытие капсулы, фактическая высота collision, сохранённый toon shadow0.73, реальное перемещение,
быстрый клип/остановка/Shift1.2м/с, другой герой/capsule height и возврат Хоши, контакт с полом PASS.
`test_hoshi_main.gd` native: сохранённый main flag, настоящая карта/всё покрытие/свет,
загрузка через обычный spawn, перемещение, inventory movement guard, смена party лидера/возврат PASS.
Source Companion/VRM и REST не изменены; private asset SHA source совпал с исходным файлом.
Процедурные walk/run отвергнуты автором. Вместо них подключена отдельная private AnimationLibrary
из Quaternius Standard (CC0), native RetargetModifier3D,136 исходных REST неизменны.
Полная повторная сборка `stage_hoshi_avatar.py --motions <UAL1_Standard.glb>` PASS;
после неё native `test_hoshi_player.gd` PASS (`ready-motion.log`, errors[]), новые walk/run кадры
просмотрены. Прежний main PASS ниже не считается повторной проверкой новых клипов;
их ручная оценка в игре OPEN.
`test_explore_stepping` PASS. Followers запущен поддержанным disposable runner:
`python tools/run_party_tests.py --test test_party_followers.gd` PASS. Рабочий direct gate отказался
от unsafe fixture, поэтому отказ не считается PASS. Другие party gates не запускались.
Первоначальный Hoshi main capture отключает только сферу в RAM; сохранённые сфера/вода прежние.
Отдельный shadow repro с полной сферой и Camera3D игрока воспроизвёл полосы в тени при
дистанции130/200. Negative control hard splits показывает полосы; blend на том же кадре
их убирает (ROI900:1260×300:630: узких тёмных пикселей631→57, пороги G<90/соседи±5>110).
В Sun main сохранён blend_splits=true, прочие параметры теней прежние. Close/обычная дистанция/
поворот просмотрены; авторское движение через границу остаётся OPEN. Путь/кадры —
`docs/EMBER_WATER_RENDERING.md` → shadow follow-up27.10; временный IPC probe убран из проекта.
Motion/3D outline fidelity/свой F5/manual interaction остаются OPEN. Камень закрывал первый близкий
ракурс; отдельный portrait-only capture изменил только камеру, не повторял успешные игровые gates.
Evidence: `D:/hoshi-ember-2026-10-27/{player-checks.json,main-checks.json,player.log,main.log}`.

## Контакт воды с мешами27.10 — технические проверки, ручной вид OPEN

`tools/test_water_mesh_contact.gd` headless: два раздельных ArrayMesh-островка,
реальные кромки/открытый проход/solid interior, перенос/yaw с повторным использованием
сечения, изменение того же Mesh Resource, полное погружение без ложного круга.
Cache signature стабилен для одинаковых пикселей разных Image и меняется при правке среза.
Существующий solver принимает mesh shape,
сохраняет fluid в проходе и откликается на incoming. Startup готовой воды без contacts
не ждёт пустой patch. На старом circle fallback тест RED, после сечения PASS.
`tools/test_water_mesh_gpu.gd` Forward+30FPS: настоящий controller upload/atlas и
`study_object_distance` показывают две solid-области/воду между ними до и после движения.
`tools/test_water_obstacle_sampling.gd` Forward+: fresh/expired у solid boundary в
реальных live/baked экспортах. Старое смешивание fresh age даёт0.498 вместо0 — RED;
после wet-normalization fresh0/expired1 — PASS в обоих режимах.
`test_water_interaction_field`, `test_water_contact_boundaries`, `test_compact_wave_obstacles`
PASS: calm/motion/stop/history, lifecycle/несколько бассейнов/берег, cache/CFL/query/removal.
`test_water_contact_foam` Forward+ PASS: calm/ambient-only/expired/strength0 без пены,
локальная волна даёт клочки; coverage≈0.289, sharpness/width/legacy работают.
Native-участок основной карты с текущими PNG в памяти: calm0, движение даёт отклик,
stop velocity0, остаток sum|h| после30с≈4.57 против≈42.48 при движении; field не
перестроен от обычного перемещения. Кадры wave/moving/settled просмотрены.
Это технические сигналы, не приёмка формы/силы волн автором. Реальный пример/ограничение
полного startup/PNG-import и сценарий ручного возврата — Water Rendering → «Следующий разбор моря27.10».

## Умеренное море27.10 — белые гребни и остаточные пятна

Owner: Water Rendering → «Умеренное море». Автор выбрал отдельные белые гребни;
охват объекта предыдущим контактом ему понравился. Текущая правка — только shader,
без записи Source/сцены/settings и изменения физической поверхности.

- `tools/test_water_crest_foam.gd`, native Forward+ PASS: рождение/плотность, рост,
  остаток после гребня, затухание, нулевые настройки, слабая амплитуда,
  непрерывность отдельных пятен при смене цикла в ложбине. Возраст проверяется
  в том же production shader, синтетический clock держит время рождения постоянным.
- `tools/test_water_contact_foam.gd`, native Forward+ PASS: прежние calm/ambient-only/
  expired/strength0, разрыв кольца и параметры ширины/резкости; не новый solver test.
- Native Forward+30FPS: участок существующего main вокруг WaterInteractionRock,
  два ракурса, времена2/5/9/12с; диагностическая маска только open_foam отделяет
  новый рисунок от береговой пены/бликов. Камеры отражения/дна обновляются обычно.
  Рабочая карта не сохраняется, новых карт нет. Evidence: `C:/Users/novos/Documents/Codex/2026-10-27/ember-water-contact/`,
  `natural-sea.gd`, `natural-sea.log`, `natural-sea-mask.gd`, `natural-sea-mask.log`,
  `open-natural-*.png`, `contact-white-*.png`,
  `foam-mask-*.png`, `crest-natural-test.log`, `contact-white-test.log`.
- Ручная приёмка OPEN: переоткрыть main/F6, посмотреть белый контакт, отдельные
  гребни и их остатки в движении; оценить плотность/размер/скорость распада.
  Прежние настройки находятся в «Вид мира → Вода → Море и берег».
- Это аналитический след, не накопленная пена, переносимая течением. Полная
  fluid simulation, новый океан, shipping bake/export и новая лодка не выполнены.
  Полный холодный старт и weak-PC из предыдущего среза остаются OPEN.

## Полёт на крыльях27.10 — основа пробы принята автором

Актуальный итог27.10: автор принял управление/ощущение и текущие облака/настройки
как относительно готовую основу отдельной пробы. Это не закрывает будущие крылья,
оружие/врагов, интеграцию main или полноту чужих ресурсов/миссии. Старые manual OPEN
ниже читаются в контексте этой более поздней приёмки базового сценария.

`tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_wing_flight.gd`
— инерция после отпускания, локальный крен/тангаж, тяга/тормоз, подъём/спуск,
30/60/120Hz и нормализация при переворотах; камера целиком наследует ориентацию,
тело остаётся в нижней части кадра. Swept-пересечение только следующих ворот
вперёд, промах/обратный проход, физическое касание/сброс, пауза/продолжение,
шесть ворот/финиш/повтор, private progress без persistence/restore, выход из
flight mode обратно в grounded/camera проверены. PASS 27 октября.
`tools/test_hoshi_wing_takeoff.gd` (тот же Godot, `--path . --script ...`,
Forward+ `--windowed --resolution 1600x900 --max-fps 30 -- --capture`) — PASS:
30/60/120Hz: обычный прыжок → второе нажатие/deploy → полёт без RT; кокон не вращает
physical orientation. Удержание=один boost/толчок, очередь трёх нажатий, удержанный RT
после паузы, сброс очереди. Автовзмахи в ровном полёте, отсутствие при пикировании,
крен в обе стороны не переворачивает тело (±90°) PASS. Реальные Player/площадка/Hoshi,
WASD/поза walk, один прыжок/приземление без крыльев, подавление echo, Space + Joypad A
для раскрытия, Ctrl и RT axis подключённого геймпада для boost, пауза/аварийный сброс PASS.
Воспроизведён стартовый ложный crash от контакта опоры; контакт только StartPlatform
до FLYING теперь поддержка, остальные столкновения сохраняют сброс. Кадры
`user://ember-tests/hoshi-wings/{walking,deploy-cocoon,flight,boost-cocoon}.png`
просмотрены в Forward+. Fixture отключает OS focus-lost guard для явного управления
кадрами; runtime-пауза при потере фокуса сохраняется. Самолётный `test_wing_flight.gd`
PASS после добавления wing orientation hook.
Native-анимации вспомогательных перьев/готовая поза тела не восстановлены; ручные
ритм/размеры/камера/пролёт шести ворот в Hoshi-режиме остаются OPEN по GDD.
Итерация по обратной связи: крутой вираж сравнивается с обычным по фактическому
углу скорости/радиусу и расходу скорости; нейтраль/крен/отрицательный тангаж,
один курок и малая скорость не дают усиления. 30/60/120Hz нового приёма PASS.
Камера: ограниченное запаздывание при переворотах, догоняние полной ориентации,
плавный подъём/возврат и сброс при рестарте PASS. Камера обоих знаков тангажа,
плавный FOV со скоростью/возврат ground lens PASS. Семь camera sliders управляют
реальной камерой; ограничение lag0/30°, осмотр/возврат, Save/Load/Reset/холодное
открытие и legacy JSON без camera PASS. Forward+ RMB + mouse/release PASS;
реальное удобство правого стика требует автора. Native camera-menu.png просмотрен.
 `test_flight_cloud.gd`: время
плотности/пауза/R, сквозной пролёт реального CharacterBody через весь объём PASS;
`-- --capture` в Forward+ сохраняет внешний/внутренний/выходной кадры. Внешний
F-14 также просмотрен с пятью облаками и sky-layer; GPU sun on/off сравнение
подтверждает световую реакцию объёма. Цветовая регрессия в плотной части
дневного облака проверяет yellow cast и белый клиппинг; оба0 в Forward+.
Исправлены повторное умножение EMISSION на плотность и потеря слабого синего
в packed fog buffer. Конфиг облаков проверен через реальные позиции/толщину/visible/material/sky:
reload/R без накопления высоты, count0, clamp, неверный тип без частичного
применения, независимость двух экземпляров сцены PASS. Дополнительный нейтральный
GPU-фон проверяет все sampled края без примеси голубого sky: максимальная разница
RGB0,00393. Natural default и spatial-filter off/192×128 просмотрены отдельно;
Вкладка «Облака»: настоящие сигналы кнопок Save/Reset/Load пишут/читают только
fixture cfg, ползунки и ColorPicker меняют shader; несохранённые правки остаются
по R. Изоляция/невалидный config и прежний flight restart PASS. Native меню и
прокрутка до самозатенения просмотрены; мышь/геймпад автора остаются manual OPEN.
`test_cloud_edge_transport.gd` в Forward+1600×900/30FPS: -- --legacy RED
(22dark blocks/loss0,991); без аргумента GREEN (0/loss0,014). Изолирует тонкий
освещённый край без тени/канта/препятствий, сравнивает с тем же небом без облака.
Общий temporal RGB threshold устраняет extinction-without-light; оценка шума
в движении остаётся ручной. Только native temporal accumulation, spatial blur off.
Новые edge/rim параметры проверены на реальном материале; GPU rim off/on меняет
кадр, дальние облака не меняют верхнюю часть неба, диск настоящего Sun виден.
FogVolume smooth union/box fade и близкий F-14 с/без Obstacles просмотрены;
вертикальная граница в этом ракурсе исчезает без испытательного столба.
Авторская оценка вида/движения остаётся OPEN. Форма/ощущение требуют авторской оценки.
По второй пробе усилен подъём камеры, предельное запаздывание 14°, возврат медленнее;
targeted и Forward+ PASS. Экранный центр тела в сильном манёвре ниже 75% высоты
и остаётся в кадре; новая ручная оценка OPEN. Полётная математика прежняя.

Forward+: та же команда без `--headless`, с `--windowed --resolution 1600x900
--max-fps 30` перед `--script` и `-- --capture` в конце. Кадры меню/крен0/90/180
просмотрены; программные физические клавиши тяги/крена/тангажа, отпускание и
Esc pause/resume и Пробел+Shift+S (эквивалент двух курков и подъёма носа) PASS.
Снимки меню, `maneuver.png`, `tight-turn.png` просмотрены;
положение тела при микродвижениях камеры проверено. Папка: `user://ember-tests/wing-flight/`.
Связанные `test_camera_relative_movement.gd`, `test_explore_stepping.gd` PASS.
Автору понравилась основа управления/вес первой пробы. Новые микродвижения/
запаздывание камеры, крутой вираж на реальном геймпаде и прохождение трассы
автором OPEN. Запуск — `tools/Start-Wing-Flight.cmd`; F5 остаётся
основной картой. Физика AC8 точно не скопирована.

Частные ресурсы: автор запустил отдельную лабораторную AC8, native `.usmap` получен
и проверен чтением F-14D/земли. Внешний `D:/projects/ac8-flight-reference-20261027/reference-flight.gd`
с аргументом `-- --reference-check` через Godot `--script` загрузил оба GLB,
создал trimesh земли, сохранил просмотренный кадр Forward+ — PASS. Контроллер
полёта прежний, его успешные проверки не повторялись из-за замены внешнего вида.
Запуск автору: внешний `Start-F14-Flight.cmd` / рабочий стол `F-14 - Flight Test`.
Итерация по отзыву о «игрушечности»: обороты/отклик смягчены и зависят от скорости,
RT/LT меняют запоминаемую достигнутую скорость, отпущенные курки включают её
поддержание (с компенсацией сопротивления/высоты). Headless flight gate PASS:
208км/ч и разгон → отпускание10с; тормоз → отпускание → меньшее значение;
нейтральный шум курков; малая/средняя/высокая скорости и фактические дуги,
плавный первый кадр вращения, reset. Связанные30/60/120Hz/вираж/камера PASS.
Forward+ physical keyboard release/hold и внешний F-14 overlay PASS.
Обновлённое меню просмотрено отдельно (`--capture --menu-only`), HUD не перекрывает его.
Ощущения новых поворотов/удержания скорости на реальном геймпаде OPEN.
По следующему отзыву RT/LT: `tools/test_flight_trigger_mode.gd` RED воспроизвёл
обычное торможение двух курков перед подтягиванием стика, затем GREEN — режим
готов без падения скорости; HUD ready/active/low-speed и RT/LT percentages PASS.
`test_wing_flight.gd`: достижимые1700–1800км/ч/верхний предел/удержание, slider →
actual motion, Save/Reset без записи/Load и cold scene reopen в отдельном
`user://ember-tests/flight-tuning-<pid>.json`, malformed JSON без потери сессии,
тип/диапазон/nonfinite/unknown validation PASS. Проверки не используют авторский набор.
Forward+ input и панель со всеми шестью слайдерами/кнопками просмотрены;
внешний F-14 overlay/трасса×6 PASS. Реальный ввод/новый вираж/настройки автору OPEN.
Корпус в нейтральном материале, часть текстур/игровые шейдеры не восстановлены,
самолёт в пробном масштабе, collision по корпусу. Один участок основания карты,
без построек/AI/миссии. Свой полёт/читаемость земли OPEN. Основные game/VR-файлы
не менялись; извлечённые ресурсы остаются вне репозитория.

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

## Плоские элементы листвы B (manual gate открыт)

Первый родной перенос выбранного B: только листва большого дерева, размеры
8×4×8/4×2×4 в существующей мелкой сетке; default/absent form=0 прежний.
Ствол/ветви/рисунок коры, palette/material roles и collision_voxels сохраняются.
Recipe.parameters → общий provider/helper → canonical Resource → текущий
prefab и preview/сохранение. Старые модели не пересобираются автоматически.
`test_voxel_foliage_elements.gd`: pre-change SHA для всех5 пород, оба размера,
freeze parity/возврат к обычному, wood/collision equality, short-height clipping,
detached input, ручная voxel-правка/save/reopen и creation Undo/Redo PASS.
`test_voxel_workshop_generator_save.gd` проверяет B/size во всех3 режимах:
точные preview voxels/palette, полные parameters, reopen controls, Undo/Redo,
Discard, stale preview и защиту manual dirty update PASS. Связанные
generator_editing/foliage_species/tree_types PASS. Native Forward+ отдельной
копии: три настоящих prefab с материалами Ember, 12 кадров и workspace save
cycle PASS без script/engine errors. Автоматический цикл не проверяет hot-reload
рабочего editor и не заменяет авторскую художественную приёмку.
Ручной gate: открыть рецепт дерева → «Форма листвы → Плоские элементы · B» →
оба размера → точный preview → новая вариация/Save → reopen; Undo/Redo/Discard.
Проверить вид с родными материалами, скульпт кистью и проход у ствола.
Большая роща/weak PC OPEN. Гладкая крона/ствол и C со скосами остаются в
лаборатории; C требует source/editing/collision решения до реализации.
Owners/границы — EMBER_WORLD_AUTHORING_ARCHITECTURE.

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

26.10 · объёмный штамп: `tools/test_solid_stamp.gd` PASS — concave fixture capture/library/reopen,
полная palette identity при одинаковом RGB, новые owned parts/поворот/зеркало, лимиты без mutation,
carve/paint/Undo-Redo и3 облика. `--native` PASS — Save/Place через прежнюю панель на копии
реального Straight Source (9111 ячеек), detached preview/Cancel/commit==preview, valid active part,
один Undo-Redo/part UI, продолжение Add, общий Save/fresh Source+scene reopen/discard; три облика
сохраняют каноническую объёмную коллизию (уточнённый gate27.10, native повтор PASS).
Данные только user://, авторские файлы неизменны. `test_solid_merge` PASS по shared identity.
`test_voxel_stamp` имеет прежние6 ошибок pointer-line (582/590/592/594/595/598), подтверждены
и на pre-slice baseline в headless/native; общий PASS не заявляется. Мышь/вид на main OPEN.
Owners/ограничения/evidence — World Authoring → «Объёмный штамп».

26.10 · объёмный Smooth: `tools/test_volume_smooth.gd` — local concave/convex/flat/isotropic,
immutable/deterministic donor palette+parts. `--native` — held preview/release/one Undo-Redo,
Cancel stale math+mesh, exact affected chunk faces/colours, validation/save/reopen/discard,
carve after Smooth и сохранность canonical carved physics во всех3 обликах (уточнено27.10:
voxel display cubes не перемещают физическую границу; detailed/low poly дополнительно равны ей).
Прежний `test_voxel_surface_sculpt --smooth-only`
проверяет старый высотный Smooth/history. Main-copy — union/smooth/input Esc/Source+looks;
последняя проверка preview-паузы — тот же объект в native fixture, без полного повтора земли.
Мышь/вид/большие радиусы OPEN; owners/evidence — World Authoring → «Объёмное сглаживание стыка».

26.10 · цельный Canvas: `tools/test_canvas_forms.gd` — user:// fixture, dirty paint до добавления,
две формы/union/carve/separate, один Undo/Redo, общий Save/Source+scene reopen/discard и3 looks/physics.
`--interaction-recovery` проверяет верхний Canvas input: pick/held move без remesh/раннего commit,
release/Undo/Redo/Esc/Save guard; recovery созданного union и отделённого куска, reopen group/discard.
`--lifecycle-only` проверяет повторное открытие dirty Canvas, обновление inactive cache,
снятие технического preview после Save, различие voxel/detail позиций и pose-only Save.
Native main-copy проверяет существующий Straight со sphere, union/carve/separate/Save и повторное
открытие Source/узлов сцены. Mouse feel/вид автора OPEN; новые рабочие карты не создаются.
Как попробовать: уступ → Canvas → «Формы» → +форма/двигать/соединить → вырезать/красить →
выделить/отделить → общий Save. Owners/evidence/границы — World Authoring → «Единый процесс лепки».

26.10 · ручной силуэт: `tools/test_solid_grab.gd` — procedural fixture, volume/profile/история,
invalid output ownership, Remove→volume boundary и native close grass-POM regression.
Actual Canvas API pointer/preview/Esc/release/Undo/Redo проверены на main-copy; Source-save/
Save Undo/Redo/discard, presentation/cache,3 looks/physics/map light и цвета после исправлений PASS.
При повторе проверялись только найденные Save/colour defects; мышь/ощущение OPEN.
Owners/evidence/точный scope — World Authoring → «Ручной силуэт через Canvas».

26.10 · боковая выемка: `tools/test_solid_volume.gd` fixture/user:// — closed boundary,
carve/paint/3 looks, old convex-wall negative control, one Undo/Redo, Grab after carve,
validation/save/reopen/discard PASS. Native main-copy: прежний Canvas stroke API, held preview/
Cancel/release/history/Save Undo/Redo/reopen/discard;3 looks/inner ray/collision/floor PASS.
27.10 · `test_solid_volume -- --physical-looks` фиксирует прежнюю ошибку физического края:
ступенчатый carved volume, sweep края, три облика и возврат, одна каноническая коллизия,
реальный raycast==floor и одинаковые высоты между обликами. Каноническая поверхность содержит
выемки; визуальные voxel-кубики не меняют опору. SOLID_VOLUME и связанный native stamp PASS.
Final cache/material isolation, scene save/restore view, unknown collision protection PASS.
Мышь/ощущение/вид и большой объём OPEN; не повторять полный набор без дефекта.
Owners/evidence — World Authoring → «Единая объёмная лепка».

26.10 · union двух объёмов: `tools/test_solid_merge.gd` fixture/user:// проверяет exact occupied
union/paint/material identity (same RGB, different artwork)/closed seam/3 looks, rotated guides,
topology validation/persistence/separate. `--presentation-only` native — generated material
override не мешает merge, authored override защищён и pre-save не пишет runtime material.
Прежний `test_voxel_merge` PASS. Native main-copy panel/cancel/one Undo-Redo/preview equality/
save-reopen результата/Canvas discard,3 looks/cavity ray/collision/floor PASS.
После сдвига только демонстрационных входов повторить только стык/выемку/облики, не весь сценарий.
Мышь/художественная оценка/сфера/большие сборки OPEN — World Authoring → «Склейка объёмов26.10».

26.10 · «Уступы v0»: природная форма/seed и3 прежних main assets, вечерний Sun/Sky.
Новый параметр/history/save/reopen/discard проверены; после финальной правки математики
повторены только3 формы/9 опор/облики. Старые recipes при0 byte-exact по volume/guides.
`tools/test_cliff_generator.gd` проверяет только3 формы/слои, guides/
reproducibility, прежний recipe editor и library history/save/reopen/discard/manual-dirty.
Native focused QA выполнена; исправленные оболочки/общая панель проверены отдельно,
успешный цикл сохранений не повторялся. Main-copy: placement history/сохранённые позы и9
Prop look/support ray comparisons PASS. Мышь/обход/вид OPEN; большой sphere/union не проверялись.
Owners/точные ограничения/evidence — World Authoring → «Уступы v0».

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

Текущий UI — Surface Canvas → «Формы». Scene commands входят в тот же WorldEditSessions,
без промежуточного Save; прежние отдельные merge dialog/session и dialog-only test удалены.

- `test_canvas_appearance.gd` — Forward+ regression на четырёх настоящих объектах основной карты,
  извлечённых в user:// fixture: чистый Canvas→3D→пустой Save не заменяет вид на voxel preview,
  не меняет материал/свет соседей и сохраняет три облика. Первый реальный мазок создаёт прежний
  preview, Undo до чистого состояния убирает его. RED до исправления / PASS после; main не пишется.
  Ручная оценка после обычного перезапуска Godot OPEN; это не проверка удобства мышью.
  `-- --draft-preview`: carved Source → три вида ready prop против отдельно подготовленной публикации
  (triangles/transform/material/light/physics/floor), stale revision, Undo/Redo, Save/fresh Source reopen.
  `--looks-only` повторяет только виды/Discard/validation/physical restore; `--paint-preview` выбирает
  hull/living путь без изменения occupancy. Carve/paint PASS, author Source/main unchanged.
  Add27.10: `--add-preview` берёт настоящий сохранённый Source с owner0, восстанавливает
  геометрию только в fixture и выполняет добавление. Три вида/material/physics/floor, stale,
  Undo/Redo/save/reopen PASS; `--looks-only` — только затронутые виды/Discard. Floor сравнивает
  поверхность/нормаль с допуском1e-4 и правильный live owner; ссылки разных экземпляров не равны.
  `test_solid_volume -- --addition`: RED→PASS для owner0/occupancy/трёх channels/history/persistence;
  invalid positive owner остаётся rejected. Renderer/cache записи — native Forward+, не headless.

- `test_canvas_forms.gd -- --scene-commands`: existing scene forms/repeat/dirty paint,
  точная маска Paint/face footprint Add/voxel Smooth/явное отключение Grab, heightfield capabilities,
  native preview/Cancel/stale rejection/commit==preview, align/bake, part split, один Undo/Redo,
  save/fresh Source+scene reopen/discard и3 looks==physics. Только user:// fixture.
- `-- --interaction-recovery`: pointer move/release/Esc и история/recovery/discard;
  во время перемещения новая геометрия не строится. API events не заменяют авторскую мышь.
- `editor_test_voxel_merge_dock.gd`: opt-in plugin только в существующем ember-rock-pilot
  checkout. Обычный объект при неактивном world tool, scene merge/repeat с dirty paint,
  FORMS input ownership, part command, World Smooth остаётся в3D, scene history/Save/Source+scene
  reopen/discard/3 looks и неизменность исходников PASS. Имя gate сохранено, старого dock нет.
  `-- --canvas-entry-only` ограничивает прогон реальной toolbar-кнопкой для1/2 объектов,
  dirty paint/repeat/empty selection и действиями Inspector primary/menu; native screenshot/PASS.
  `-- --forms-cycle-only`: main-copy Corner/Straight, held paint→switch→Undo/independent masks,
  placement/union preview Cancel/guard remap/Undo/Redo, carve/paint/separate, StampPanel library user://,
  placement preview Cancel/commit==preview/cavity/Undo/Redo/continue sculpt, validation/Save/fresh Source+
  scene reopen/discard/3 looks==physics PASS. Pure `test_canvas_forms -- --forms-guard-math` checks
  translation/scope/cut/stale/immutable guards. UI теснота/footer и авторская мышь OPEN; Hoshi исключён.
  `-- --shared-mask-only`: main-copy protected paint, Source locked group + exact mask/scope/cut,
  one Undo/Redo, target isolation/restore, Grab blocked in both contexts, clear mask preserving scope,
  Source+scene fresh reopen/validation/discard PASS; session guard не попадает в Source.
  `--shared-mask-direction-only`: только signed face/adjacent при pick на соседней грани и нативная панель.
  Math `test_canvas_forms -- --shared-mask-math`:6 normal directions, voxels/columns, region/height,
  stale/empty enabled masks fail closed PASS. Мышь/формы/склейка этим не принимаются.
  `-- --brush-settings-only`: main-copy, radius128/force5 через смену кисти и 3D↔Canvas, Add/Remove
  depth/Grab softness, ViewStore→ConfigFile save/fresh load/import/normalize, invalid bounds и Source
  unchanged/validation/dirty=false PASS. Новых geometry/history изменений нет, их gate не повторяется.
  Мазок гигантским радиусом не выполняется: это проверка настроек, не гарантия времени расчёта.
  `-- --canvas-plane-only`: shared Source/SurfacePlaneJob, held reference+donor parts, Undo/Redo,
  Cancel/stale, mask/locked/hidden height и legacy columns, profile/3D↔Canvas, validation/3 looks==physics,
  Save/fresh Source+scene reopen/discard на main-copy PASS. `--canvas-plane-transfer-only` повторяет
  только исправленные profile mask и depth12 после прежнего Smooth max8, с кадром нативной панели.
  Мышь/цвет/UX Canvas не приняты; evidence — World Authoring → «Общая плоскость Canvas/3D».
  `-- --world-plane-only`: тот же минимальный цикл на main-copy для Level по поверхности,
  fixed plane/cut-only/donor parts/reference, held/no early history/Cancel/Undo/Redo, прежняя земля,
  validation/3 looks==physics/Save/fresh reopen/discard PASS. `--plane-capture-only` даёт только
  панель/готовый preview. Math `test_volume_smooth -- --plane`:6 направлений/наклон/offset bounds,
  fill vs cut/donor material+part/immutable/cancel PASS. Canvas и реальная мышь этим не принимаются.
  `-- --world-smooth-only`: на копии main реальный Corner, held3D delta==VolumeSmooth (включая
  donor parts), нет раннего commit, один Undo/Redo, pending/Cancel/stale, земля smooth/cancel,
  возврат к объекту без Canvas,3 looks==physics, validation/Save/fresh Source+scene reopen/discard PASS.
  Мышь/вид/большие радиусы остаются автору; evidence — World Authoring → «Сглаживание прямо в3D».
  `-- --world-context-only`: на копии основной карты ground/два уступа, обычный выбор/Alt+Q
  через dirty preview collider, text focus/active gesture guards, unavailable brush/busy refresh,
  общий draft/кисть/радиус, Canvas→другой объект→Canvas→3D и неизменная3D-камера;
  Undo/Redo предыдущей цели, save/fresh Source+scene reopen/discard/validation PASS.
  Evidence — World Authoring → «Один3D-контекст»; input API не принимает реальную мышь.
  Fixture path уникален на процесс, чтобы старое открытое дерево сцены не заменяло свежую fixture.
  После функционального PASS наблюдался engine get_node error при выходе QA; shutdown остаётся OPEN.
  Dirty prop интегрирован отдельным прежним native полным циклом join/Undo/Redo/split/Save/Source+scene
  reopen/Discard/3 looks==physics PASS. `--projection-frame-only` проверяет готовую проекцию после
  изменения размеров union; не повторяет сохранение. Технические проверки этого среза завершены.
- `test_voxel_merge.gd` и `test_voxel_merge_orientation_bake.gd` сохраняют чистый расчёт,
  alignment/overflow и24 поворота. Scene/publication проверяются общим Canvas gate;
  больше не тестируется удалённый standalone publish. `test_solid_merge -- --presentation-only`
  проверяет общий ObjectSession guard generated versus authored material в Forward+.

Owners/стоимость/ограничения — World Authoring → «Единое управление миром и Canvas».
Save rollback остаётся прежним WorldEditSessions: относящиеся failure/stale gates —
`test_world_editor.gd`; Source storage/transaction в этом срезе не менялись, полный прогон не нужен.
Первый native editor запуск содержал устаревший `qa_solid_merge_native.gd` только в disposable
checkout с preload удалённого dialog; это не ошибка рабочего checkout. Функциональный gate PASS;
прежние ObjectDB/scan-aborted shutdown warnings не считаются исправленными.

Ручная приёмка на основной карте: выбрать2 соседние формы → команда соединения → выбрать
основную/при необходимости align+bake → Предпросмотр → отменить либо применить → продолжить
лепку и покраску → Отделить выделение/Разобрать части → Undo/Redo → Save/reopen/F6.
Проверить удобство мыши, возврат в3D, крупные формы и три облика. Новых рабочих карт нет;
сфера и предельная производительность этим функциональным прогоном не закрываются.

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

Три цветочных набора25.10: `tools/test_flower_sets.gd` native Forward+ fixture/user:// PASS.
Actual selector3 Source/разные shapes/независимые overlapping masks, preview/Cancel/paint/erase,
один Undo/Redo, save/reopen/discard refs/shape/mask/size, Source shape validation.
Material editor shape preview/Undo/Redo/Save/reopen/discard без изменения другого Source/масок;
активная sphere подхватывает mesh после shape edit, движение без повторной preparation PASS.
`test_flowered_grass.gd` прежний PNG/tint/обычный editor regression PASS. Main native0/1/2/0,
сфера обоих внутренних обликов и motion/кеш PASS; новая публикация только2 refs/2 nodes,
31 прежний node-блок/terrain bytes прежние. Свежий reopen сверил exact masks/refs/size/seed/owner.
Обычная трава: новая80-triangle форма в0, прежний low1 восстановлен, voxel2 совпадает с исходным
snapshot; оба исходника сохранены. Арт травы/ромашек и двух новых наборов одобрен по картинкам. Сиреневые соцветия затем
укрупнены ~30%/стебли выше ~9% по просьбе автора: native main/две камеры/0/1/2 PASS,
Scene/terrain прежние; размерную поправку ещё оценить (`ember-lilac-scale/main.log`/PNG).
Ручной ввод/горячие клавиши/движение OPEN. Evidence —
`C:/Users/novos/Documents/Codex/2026-10-25/ember-meadow-sets/`:
sets-test.log/old-regression.log/prototype.json/reopen.log/publication.json/native PNG.
Схема Pattern расширена additive flower_shape с default0; старые Resources/выборы совместимы.
Полного suite не было; Source травы/материалы/вода/свет и старый grass_tuft_mesh/recipe не менялись.

Кисть деталей24.10: `tools/test_detail_brush.gd` native Forward+ на искусственном8×8м fixture
и user:// копии, без чтения/записи авторской карты: mask validation/NaN, preview без owner,
paint/erase, один Undo/точный Redo, Cancel/Esc через API pointer, save/fresh reopen/discard,
плотность/seed, три облика без смены XZ/count и без повторной генерации, terrain неизменен — PASS.
Non-default size/jitter/variation/yaw/seed Save/reopen и302px panel PASS отдельно.
Main native integration — отдельное чтение основной карты в памяти: трава/галька, три облика,
панель, сфера/движение без повторных preparations. Примеры опубликованы только тремя scene nodes;
свежая загрузка/владение/точные маски/count67/30 PASS, terrain и прежние байты сцены сохранены.
Source/backend/history checks не заменяют мышь/доступ к кнопке после рестарта importer и вид;
эти gates OPEN. Полного stress/FPS/weak-PC benchmark нет. Evidence —
`C:/Users/novos/Documents/Codex/2026-10-24/ember-detail-brush/`.

31.10: `test_detail_pattern_validation.gd` RED→GREEN покрывает реальный warm wheat
prepare без повторного полного voxel scan, неизменные3meshes, in-place ownership/
palette/nested groups edits и kind invalidation. Native pattern-library и surface-rules
сценарии повторены PASS. `test_detail_cache_write.gd` RED→GREEN: artificial slow80ms
transport не блокирует producer, immutable snapshot/cancel до enqueue, count+byte bounds,
teardown/join. Async writer сохраняет формат и Source; fresh reopen/invalid payload
проверяет `test_detail_preparation` (bad payload проверяется после завершения записи).
`test_detail_cache_read.gd` RED→GREEN/native PASS: slow80ms heartbeat,
private settings snapshot,packaged fallback,malformed transforms,2-slot bound включая
готовые результаты до budgeted delivery,cancel/free/join/map exit,unpainted near/far
object invalidation и invalid cover. `test_detail_preparation` native PASS включает
real cache hit при light/gray edit:готовящийся материал сохраняет актуальный preview,
стабильный light edit не пересоздаёт scatter. Pattern-library native Undo/Redo/save/
reopen PASS;ручная кисть/движение OPEN. Async read не меняет cache key/формат/Source.
Native dense/cold и отклонённый3мс вариант — Performance owner, не helper acceptance.

31.10 admission: `test_terrain_publication_admission.gd` RED→GREEN — observer не
публикует вне бюджета, expired deadline сохраняет fine/physics, quick reverse берёт
текущий wanted, stale overview не освобождает новую поверхность, deadline между
регионами и eventual release. `test_terrain_travel_preparation` сохраняет coverage
до budgeted replacement; native `test_terrain_resident_slots` подтверждает reuse/
physics/brush LOD без scene-tree churn. `test_detail_owner_lifetime` проверяет weak
owner при ancestor reparent/detach/reattach/off-tree;detail preparation PASS.
Native dense/cold/release/return PASS;120FPS и ручная камера OPEN — Performance owner.

31.10 Jolt Physics в `project.godot`:native `test_terrain_heightmap_collision` PASS,
5120rays,max height delta0,00000763raw;cache/offset/hole/edge/affine/deform сохраняют
каноническую поверхность. `test_explore_stepping` PASS на30/60/120Hz,stairs/diagonal/
high wall/ceiling/cancel/camera;`test_hoshi_player` capsule/walk PASS.
`test_physical_crates` native в отдельном guarded mixed sandbox PASS:F/G/push/weights/
recovery/save/load/Undo/reopen;первый запуск без fixture marker REFUSED,не приёмка.
Dense Jolt5ms cold/release281/return281exact/actual foot support PASS.3ms после Jolt
REJECTED:potentially-visible absent4/3,startup≈69s;production5ms. Manual feel после
restart Godot→F5 и full120FPS OPEN. Raw/effective backend — Performance owner.

Библиотека кисти25.10: `tools/test_detail_pattern_library.gd` native Forward+ fixture/user:// PASS:
пять разных форм, mixed/fixed selection, palette lookup, preview/Cancel, общий Undo/Redo, erase,
save/fresh reopen/discard canonical refs/masks/size, validation, стабильные три облика/один bake,
плотность без дубликатов/умножения, пять cold waiters делят один bake;
terrain и canonical source cache прежние. Старые два набора PASS.
Выделенные Solid CPU buffers совпали с прежними arrays/formats для hull/living/voxel.
Main:22 камушка/5 source nodes, прежние67/30, облики/сфера без повторной подготовки; fresh load PASS.
Сохранены исходные terrain/preset/geometry и прежние байты Scene (кроме ссылки и новых nodes).
Физический ввод/вид и FPS/stress OPEN; evidence —
`C:/Users/novos/Documents/Codex/2026-10-25/ember-pattern-library/`.

Природные объёмные черновики: `tools/test_natural_detail_sets.gd` native Forward+ fixture/user://
проверяет оставшиеся wheat/shell (2 набора), не отклонённые voxel-цветы. Выбор/preview/Cancel,
paint/erase/один Undo/Redo, masks/refs/размер save/fresh reopen/discard, стабильные XZ/count/кеш;
Surface Canvas palette/history/Save/reopen/discard, part ownership/erase/bake, fallback добавления
и явный saved-source refresh PASS. Main:10 черновых объёмных деталей; их внешний вид OPEN.
Старые daisy/wildflowers Source файлы сохранены, их выбор отключён/пример снят с main.

`tools/test_detail_stone_looks.gd` native fixture PASS: оба источника small stones используют
hull в detailed/low, hidden в voxel; текстурная цветущая трава без voxel Source остаётся видимой.
Маски/terrain/scatter прежние; один shrinking binding на камни без voxel-only дубля,
sphere motion без подготовки. Main52/52/0 видимых камушков, крупные props сохранены.

Текстурные цветы — основной текущий gate выше (`test_flower_sets.gd`). Прежний
`test_flowered_grass.gd` сохраняет regressions preview/Cancel/erase/Undo/Redo/save/reopen/discard,
PNG/tint/private draft/validation и обычного material editor; он повторён после добавления наборов.
Историческое evidence ромашек — `C:/Users/novos/Documents/Codex/2026-10-25/ember-flower-shapes/`;
текущие формы/наборы и ручная приёмка — World Authoring → «Текстурная цветущая трава».

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
Актуальный аудит27.10: четыре gates PASS; после воспроизведённого отказа PrimitiveMesh
исправлен type guard в voxel light callback, fixture предоставляет нейтральный coverage
input только в изолированной копии. Native Forward+ action-chain PASS, пять UI экранов
просмотрены при1280×800. Это API/render-аудит; новый main-сценарий описан ниже.
Evidence/точный scope аудита — Handoff → «Проверка взаимодействий27.10».

### Конструктор механизмов29.10

- 3D wire-add: source→пустой щелчок→ограниченное меню→hold→door. Native popup
  key selection (Input.parse_input_event с window_id, не Viewport.push_input),
  auto source edge/continue output, один EUM action, Undo/Redo/scene save/reopen/
  discard PASS (inspector-editor.log, native-wire-add-popup/connected.png).
  Targeted inspector: cancel/no mutation, hide-before-id_pressed, node+edge Undo,
 3D metadata retention through property edit/save/reopen, metadata-only identity,
  NaN rejection, ports-off cancellation PASS (auto-roles-forward.log).
  Drag: motion не меняет source/history, preview=commit, один Undo/Redo, сохранённое
  размещение при reopen, click/Esc/ports-off без записи, Component identity PASS.
  Valid/occupied/self-cycle подсветка использует Model.errors; запрет не меняет
  документ/оставляет draft; успешные press+release потребляются при action callback.
  Targeted Forward+ PASS (gestures-forward.log/auto-roles-forward.log). Native Editor
  EUM drag/Undo/Redo/source reopen/цвета/tooltip PASS (inspector-editor.log), кадры
  native-wire-drag-preview.png/native-wire-port-feedback.png просмотрены.
  Ручная мышь/положение меню на мониторе/host125%/main OPEN.
- Inspector UI (`_test_mechanism_inspector`): роли4плитками, один shared property Control,
  compact wire focus, menu add logic, применить/снять/Undo, независимые circuits/picker,
  ports off при editing on, stale scene и teardown/rebind/picker/toggle state PASS
  (inspector-forward.log). Native EUM/viewport mouse-event API/save/reopen/discard
  PASS (inspector-editor.log), EditorDock1600 и те же controls1280 preview просмотрены.
  Полная host-layout1280/125%/реальная мышь/основная карта OPEN. Базовые circuit/physics/
  hold/latch regressions PASS; source schema/save owner не менялись.
- Latch (`_test_latch_gate`): таблица set/reset/reset-priority/retained disconnect,
  cascade two memories/atomic observer+один autosave, неизменные кадры без записи,
  real load true/reset/load false, invalid batch без мутации, pending restore guard,
  именованные входы/layout/Undo/source reopen PASS (latch-forward.log).
  Native palette add/graph connections/set-reset labels/EUM/source save/reopen/discard
  PASS (latch-editor.log/native-latch-properties.png), окно просмотрено.
  `python tools/run_party_tests.py --test test_party_save_v2.gd` PASS; UID warnings
  disposable fixtures с text-path fallback, ошибок нет. Автор/мышь/main OPEN.
- Hold (`_test_hold_gate`): duration/instant-on/retrigger/no startup pulse/zero delta/
  partition/disconnect/invalid duration; runtime pause/layout-only move, field apply/
  Undo/source duration reopen без countdown PASS. Native Graph add/connection requests/
  seconds/EUM/save/reopen/discard PASS, hold-editor.log/native-hold-properties.png.
  Актуальный Forward+ весь test без fixture замен PASS (hold-current-forward.log);
  физическая плита→hold→дверь/выход с плиты/удержание/закрытие дополнительно PASS
  (hold-door-forward.log). Параллельные source-файлы не менялись.
  Пользовательская мышь/ощущение/main OPEN.
- Autogenerated door/plate: `_test_generated_roles` в test_mechanism_circuits;
  вложенная группа/исходные poses, helper назначение/Undo/Redo/снятие/восстановление
  StaticBody shapes, защита несохраняемого target, Character/rigid вес→plate→door,
  occupied passage и закрытый/открытый физический ray, source helpers reopen PASS.
  Runtime Forward+ весь targeted test PASS; последнее дополнение owner guard отдельно
  auto-roles-targeted.log PASS. Native editor роль/compact form/EUM/save/reopen/discard
  PASS (auto-roles-native.log/native-auto-role-*.png). Main/мышь/streaming OPEN.
- Ordinary roles: выделение→форма→lever/lamp→новый пустой Circuit/существующий,
  bounded dialog с длинным сообщением/scroll/доступным OK (регрессия высоты7582px),
  sibling NodePaths без изменения parent/transform/script; runtime F adapter→lamp,
  Undo/Redo/дубли/типовые ошибки, source save/reopen/discard/adapter exclusion PASS
  (`test_mechanism_circuits.gd`). Native Forward+ роль/провода/EUM/save/reopen/discard
  PASS, exit0; просмотр native-role-dialog.png/native-ordinary-wires.png,
  roles-native.log в прежней папке. Мышь/main/streaming OPEN.
- 3D `ember_mechanism_world_wires.gd`: проекция портов/разведение подписей и hit test,
  реальные mouse-event команды выход→вход/Shift+вход, scene Undo/Redo, занятый вход,
  Esc/режим off/смена сцены, тот же serialization path PASS в targeted тесте ниже.
  Native EditorPlugin Forward+ overlay/EditorUndoRedoManager/save/reopen/discard
  PASS, exit0; screenshot просмотрен. Evidence world-native.log/native-world-wires.png
  в прежней папке. Это API input, ручные мышь/навигация/split-view/125%/main OPEN.
- `test_mechanism_circuits.gd`: AND/OR truth tables, NOT/disconnected NOT, cycle/
  duplicate-input rejection, реальные2 плиты→дверь, lever F-adapter→OR lamp и
  один autosave/реальный load flags; source scene+save world reopen. GraphEdit
  connection signals/add NOT/rewire/Undo/Redo/rejection без мутации, metadata-only
  move не меняет эффектор/physics clock, stale scene guard, source save/reopen/
  discard/runtime adapter не попадает в .tscn; legacy envelope→common Circuit
  conversion/Undo/Redo; pause/input return при lab Window PASS.
- Native EditorUndoRedoManager wire Undo/Redo, legacy без components → conversion
  → Undo/Redo, save_scene_as/reopen/discard несохранённой связи, authored-only
  nodes/NodePath PASS, exit0. Native форма просмотрена. Native Forward+ две схемы,
  live wires, отключение/Undo и input return PASS, exit0. Мышь этим не принята.
- Связанные `test_pressure_gate.gd` (F/settle/closed-open ray/occupied gate/
  source/save/load/find/Undo) и `test_quest_crate_placement.gd` PASS. Прежний gate
  сохранён как regression через общий движок; old root-field asserts заменены
  checks компонентов новой .tscn-схемы. Контракт containment прежний.
- Штатный запуск: `python tools/run_mixed_editor_tests.py --test test_mechanism_circuits.gd`.
- Ящики/бой29.10: `python tools/run_shore_combat_tests.py --native --test test_combat_world_items.gd`.
  Реальные weak/strong contacts/два типа, exports scene reopen, world F→held entry,
  identified object units без initiative/outcome, occupied-cell hit и воспроизводимый
  miss (оба типа), preview без persistent mutation, постановка/повторный подъём,
  Retry без копии, victory→тот же world body→F, cold autosave и очистка dynamic
  tombstone PASS. Native кадры просмотрены. Баланс/ручной ввод/full main OPEN.
  Related: physical crates gate, mixed `test_combat_action_plan.gd` и
  `test_combat_vertical_profile.gd`, native `run_shore_combat_tests.py --native` PASS.
  Evidence `C:/Users/novos/Documents/Codex/2026-10-29/crate-combat/`.
- Дерево с яблоком29.10: mixed runner `--test test_fruit_tree.gd`, настоящий Forward+.
  Native LMB/UI/wall/combat, rendered sway response/очистка stale sway/возврат к покою,
  неизменные shared mesh/collision/соседнее дерево, физический drop/F, повторы без
  награды, три cold saves/scene+icon roundtrip PASS. Свежий runner PASS; общая shader
  зависимость — tree palette/leaf pile Forward+ PASS. main-copy strike/drop/F PASS,
  кадры просмотрены. Evidence `C:/Users/novos/Documents/Codex/2026-10-29/fruit-tree/`.
  Вид/ощущение/амплитуда/full main OPEN — Inspector «Дерево с яблоком29.10».
- Физика предметов29.10: mixed runner `--test test_world_item_physics.gd`, Forward+.
  Яблоки без толчка катятся по противоположным склонам в разные стороны; на плоскости
  после падения есть отскок/вращение/путь и затухание до покоя. Общая native-size
  convex Shape3D, default box других моделей, validation/scene reopen, save позы и
  очистка отложенного импульса PASS. Fruit gate (повтор без нового толчка/F/cold saves)
  и physical crates regression PASS. Evidence `C:/Users/novos/Documents/Codex/2026-10-29/item-physics/`.
  Вид/ощущение в полной карте OPEN, коэффициенты пока пробные.
- Ягодный куст29.10: mixed runner `--test test_berry_bush.gd`, Forward+.
  Opt-in ветвистый Source/v7 совпадает с сохранённым recipe; пять побегов/leaf-card
  budget, валидность shrub scale, точные branch_id/t, короткие плодоножки и малые
  ягоды. Seed/детерминизм/Source save/reopen/неизменность/нулевой count/отказ чужому
  frame и прежние3 cloud пресета PASS. Плодовые узлы запечены post-generation builder.
  Уточнение округлой кроны: inward mid/upper shoots, ягоды5,5 scale/диаметр1,1,
  минимум5 опор выше80% recipe height. Native side/top render просмотрен;
  focused F/save/roundtrip/детерминизм и main-crop PASS — `round-*.log`.
  Финальная настройка после приёмки вида: scale5,5/диаметр1,1, количество30 вместо20,
  15 twig attachments (8 сверху). Принятые Source/recipe/mesh сверены хешами и неизменны.
  Native кадр сверху просмотрен, focused F/save/scene roundtrip PASS — `more-berries-*.log`.
  Общая зависимость — `--test test_tree_leaf_palette.gd` Forward+ PASS:
  прежний sprigs mesh/collision, palette/preview/update/history/save/reopen/discard.
  Реальный Player F route, full stack сохраняет урожай/награду, combat lock,
  атомарные3 ягоды+flag/один autosave, повтор без награды, cold states до/после,
  native scene roundtrip/item/icon/physical model validation/recreate after harvest PASS. Native crop
  основной земли, sample высоты и F PASS. Before/after/model кадры просмотрены.
  Evidence `C:/Users/novos/Documents/Codex/2026-10-29/berry-bush/branch-*.log` и
  `tree-leaf-regression.log`; ручной F5/full main,
  общий UI урожая и editor preview/Undo/save/discard совмещённой регенерации OPEN
  Художественный вид принят автором; остальные формы отложены. Scope — Inspector I3.15 «Ягодный куст29.10».
- Срезаемая трава29.10: `--test test_cuttable_grass.gd` у mixed runner, настоящий
  Forward+ для сохранённого native material bank. Walk/UI/wall/combat guards, native
  LMB → stubble/64 узких травинки в4 batches → gated herb/F, одна reveal запись/без instant loot,
  повтор без добычи, три cold saves/scene roundtrip/bindings/cut plane/cleanup PASS.
  Свежий disposable runner PASS; main-copy strike/stubble/scatter/F/cleanup PASS,
  VFX regression: short lifetime/wind drift/shrink, сохранённые64 poses/узкие blade
  meshes/нет PhysicsBody/ground rays PASS, текущие native кадры просмотрены.
  Evidence `C:/Users/novos/Documents/Codex/2026-10-29/grass-blade-wisps/`.
  Ручные F5/вид/ощущение/full main OPEN; scoped owners — Inspector «Срезаемая трава29.10».
- Кучка листьев29.10: `--test test_leaf_pile.gd` у того же runner. Native Forward+
  также проверяет реальный проход: player physics overlap/non-player/combat/reentry,
  одна reveal запись/эффект, cold load/F, старый save под стоящим игроком без самораскрытия.
  main-copy move_and_slide/scatter/reveal/F/cleanup PASS, native кадр просмотрен;
  evidence `C:/Users/novos/Documents/Codex/2026-10-29/leaf-walk/`, ручное ощущение OPEN.
  LMB → Area/cover flag → прежний gated WorldItem → F; invisible/frozen/no-prompt до
  удара, UI/wall/combat guards, одна reveal запись/без instant inventory, повтор без
  добычи, all240 initial vertex/UV continuity/4 batches, independent effect buffers,
  полный размер во время полёта/cleanup2,8с, три cold-save состояния (до/открыто/подобрано), повторное
  появление тела через реальный ExploreScene._refresh_world_items и scene roundtrip PASS.
  Save slots в API0–2, визуально автору1–3. Существующее скрытое тело после возврата
  старого save корректно снова включает физику. Strike/crates Forward+ regressions PASS.
  Геометрия участка main/strike/reveal/F PASS, кадры просмотрены; full main/мышь/125%/
  вид/weak-PC OPEN. Evidence: `C:/Users/novos/Documents/Codex/2026-10-29/leaf-pile/`.
  Текущий облик — рисованный alpha-atlas/плоские карточки: native просмотр слоёв/
  контура/разлёта и тот же leaf gameplay/save gate повторно PASS; evidence
  `C:/Users/novos/Documents/Codex/2026-10-29/leaf-palette/`. Приглушённая палитра/
  общий ramp: leaf gate повторно PASS; unrelated gameplay gates не повторялись.
- Цвет листвы29.10: `--test test_tree_leaf_palette.gd` у mixed runner, настоящий
  Forward+ (shader defaults недоступны в dummy headless renderer). Старые Source/
  Recipe сохраняют силу0; invalid colour/strength rejection, реальные creation/edit
  controls/no remesh на input, local/scene Undo/Redo, preview/update placed instance,
  Source/Recipe/map save/reopen/discard, прежние sprig arrays/UV/collision PASS.
  Native generator-palette.png/main-autumn-maple.png просмотрены, художественная/
  mouse/main/125% приёмка OPEN. Owners — Terrain Authoring «Цвет листвы29.10».
- Удар/разрушение29.10: `--test test_world_strike.gd` у того же runner. Forward+
  Input.parse_input_event(LMB) → unhandled input, открытая сумка/GUI/wall/reach/
  carried/big/combat guards,8 source-coloured fragments, release плиты, один autosave,
  cold load/count0 без resurrection/reward, Source immutable, максимум4эффекта и
  cleanup PASS. Кадры просмотрены; удар на геометрии участка main в копии PASS.
  Связанные test_physical_crates/test_quest_crate_placement Forward+ PASS.
  Evidence: `C:/Users/novos/Documents/Codex/2026-10-29/world-strike/`.
  Ручной F5/реальная мышь/ощущение/полная main и слабый ПК OPEN; автор отложил свой
  прогон до оптимизации другого чата. Cosmetic budget не доказывает общие FPS.
- Ящики/вес/возврат29.10: `--test test_physical_crates.gd` у того же runner;
  Forward+ F/G/реальный контакт толкания/сумма весов, character exclusion,
  radius/killbox/missed crossing/generic RigidBody/HP invariant/save/cold load,
  UI/Undo/Redo/source reopen PASS. Native поля веса просмотрены; геометрия участка
  main в изолированной копии/settle/weighted plate PASS. Связанные crate placement,
  world-item cycle и mechanisms Forward+ PASS. Evidence: `C:/Users/novos/Documents/Codex/2026-10-29/physical-crates/`.
  Ручной gate: main Map/Props/PhysicalCrates → F5 → F/G/толкание/плита/Save/Load;
  оценить дальность/тяжесть и своё размещение. Полный main/streaming/125% OPEN.
  Evidence: `C:/Users/novos/Documents/Codex/2026-10-29/mechanism-circuits/` →
  circuits.log/editor.log/native.log/native-*.png и regression logs/fixture-path.txt.
- Ручное OPEN: Graph → Механизмы → Создать набор → переподключить 2плиты/рычаги
  через ВСЕ/ЛЮБОЙ/НЕ; выбрать physical targets/параметры → Применить; Undo/Redo/
  Ctrl+S/reopen/discard. F6 camera_preset_study → ИГРАТЬ → оба ящика на плитах/
  рычаги/F, открыть схему, посмотреть сигналы, снять связь/Undo/закрыть окно и
  вернуть управление. Main/save/streaming/125%/узкий экран/свой сценарий остаются
  OPEN. Правила и ограничения — Inspector Design I3.15 «Конструктор механизмов29.10».

### Quest: собрать и передать предметы29.10

- `test_quest_handover.gd` disposable PASS: pre-owned/live sum,3/3→drop→2/3→
  pickup→3/3 без автоматического done, HUD, raw flag guard, отказ cancel/missing/
  locked/invalid target/reward stack без потерь. Успех inventory+done+reward в
  одном observer snapshot/одном autosave; реальные user://save/load до и после,
  повтор без награды. Обе формы, invalid item/capacity validation, Graph Undo/
  Redo/save/reopen/discard и NPC bind Undo/Redo; Action form roundtrip, изменение
  requiredCount3→2 после привязки берётся из текущего Quest.
- Прежние test_quest_purchase/talk_shop/action_script/quest_state/quest_npc_options
  PASS. Native Forward+ форма,3/3/2/3/сдача просмотрены, exit0; внешние evidence —
  `2026-10-29/quest-handover/`. Сумка/store автора и main не менялись.
- Ручной OPEN: F6 camera_preset_study → «Начать / сбросить ракушки» → NPC/F →
  подобрать×3 → выбросить/подобрать → NPC/F → сумка0,5монет, повтор без награды.
  Отдельно попытка2/3 и отмена разговора. Настроить item/count/NPC/реплику/награду
  в Graph, Undo/Redo/Ctrl+S/reopen/discard. Проба вызывает world-item commands
  кнопками, не проверяет управление настоящим игроком/физику. Мышь/125%/свой main
  OPEN. Правила/owners — Inspector Design I3.15 «Цель «Собрать и передать»29.10».

### Quest: покупка у выбранного продавца29.10

- `test_quest_purchase.gd` в disposable fixture PASS: ранняя/root/locked покупка,
  успешные1/2→2/2, две последовательные цели не закрываются одним событием,
  wrong item/shop, grant/sell/cancel/broke/stack_full, clamp; один autosave с
  inventory/stock/flags и реальный load_autosave, без нового зачёта на загрузке.
- Обе формы сохраняют purchase поля; validation отвергает товар вне ассортимента.
  Graph изменение/Undo/Redo/native Resource save/reopen/discard, Journal/HUD count,
  NPC→обычная лавка→сценка/выбор→награда один раз PASS. Связанные talk/shop,
  action_script, quest_state PASS. Forward+ native authoring/shop/progress
  просмотрены, exit0. Evidence — внешний `2026-10-29/quest-purchase/`.
- Ручной OPEN: F6 camera_preset_study → «Начать / сбросить чай ·30 монет» →
  «Чай · поговорить со смотрителем»/F → лавка/F×2 → Esc → NPC → сценка/выбор
  → итог21монета; повтор без награды. Настроить свой товар/количество/лавку в
  Graph, Save/reopen/Undo/discard. Мышь/125%/узкое окно/main ещё не принимались.
  Канонические правила и инструкция — Inspector Design I3.15 «Цель «Купить»29.10».

### Камера: отдельная проба ракурсов29.10

- `test_story_authoring.gd` в disposable Forward+15FPS PASS: настоящая форма/
  независимые фильтры, cancel/validation/create/Undo/Redo/scene save/reopen/
  discard, authored-only nodes без transient UI, relative bindings/world-space
  displacement под rotated/scaled folder и physics-owner guard, свежий picker,
  два cues по clock/skip, reward/cancel, head-in-frame и camera/input restore.
- Native editor тот же create через EditorUndoRedoManager, Undo/Redo/Save/reopen,
  выбор story и вид формы/шкалы PASS, exit0. Не ручная мышь/125% приёмка. Прежний
  AV не объявлен исправленным; fixture scan-aborted при shutdown отмечен в логе.
  Связанные quest/history/visual/camera/talk/shop/action и plugin parse PASS.
- Ручное OPEN: на camera_preset_study Ember Graph → Создать сценку → ActorA/B/
  Item, X1.1/4с, два «Посылка» в1/2с → создать/шкала/Ctrl+S → заменить первый
  play_cutscene в пробной цепочке на своё имя → F6/Поговорить/два выбора/монет3;
  затем cancel/Undo/reopen/discard. Инструкция — I3.15 «Создание сценки автором29.10».
  Main/streaming/game-save/rig/physics gate этим не закрыт.
  Evidence: `C:/Users/novos/Documents/Codex/2026-10-29/story-authoring/` →
  native.log,editor.log,native-form.png,native-timeline.png,plugin-parse.log,
  workspace.log и test_*.log. Actor/source/награды автора не менялись.
- `test_quest_presentation.gd` в disposable Forward+15FPS PASS: Action editor
  play_cutscene picker/validation/Undo/Redo/native save/reopen, QuestGiver route
  → dialogue/presentation →3 coins/done, cancel/retry/normal finish/skip,
  shared history, missing/duplicate ID, node exit и старый callback без наград.
  Связанные dialogue/history/visual/camera/talk/shop/action и Graph parse PASS.
  Lab заранее ставит3 предыдущие цели только в своём ExploreState, старый
  Action награды/main/авторский save не меняются. ShotRig settings возвращаются,
  финальные позы остаются только на текущий запуск, не сериализуются в WorldItems.
- Ручное OPEN: F6 → «Поговорить со смотрителем» → выбор → конец → монет3;
  повтор NPC → монет3, reset trial → отмена → монет0. В открытой сцене выбрать
  Action/Graph «Показать сценку» → имя → Save/Undo/reopen/discard. Это API/
  fixture PASS, не ручная приёмка мыши. Main camera/input/world-save gate OPEN.
  Evidence: `C:/Users/novos/Documents/Codex/2026-10-29/quest-presentation/`,
  native.log,quest-completed.png,graph-parse.log и test_*.log.
  Native editor lookup/picker PASS и native-authoring.png просмотрен; один
  процесс затем завершился0xC0000005 при закрытии, повтор exit0. Это не чистый
  PASS первого editor-процесса и не native fix. Evidence/launch/fixture/probe —
  native-crash-evidence.json/editor-shutdown-av.log/probe-shutdown-av.gd в том же
  каталоге; причина остаётся открытой у общей stability gate.
- `test_dialogue_story_history.gd`, runner `run_interaction_tests.py --test …`:
  native Forward+15FPS1280×900/720 PASS — настоящий Dialogue checkpoint/choice/
  resume, real F/H/Enter/S key events, button pressed signals, history modal/
  copy/limit, unchosen branches absent, skip/cancel, binding save/reopen и
  изоляция от реального прогресса. Воспроизведённый free locked pressed button
  исправлен remove_child + queue_free. Talk/shop/action и visual/camera PASS.
  История — последние200 записей в памяти UI, не сохранение и не replay.
- Ручное OPEN: F6/P → дождаться разговора → H → выделение/прокрутка → Esc →
  выбрать ответ кнопкой или W/S/F/Enter → дождаться движения предмета; повтор/
  отмена и свой ресурс Dialogue/Dialogue Time → Ctrl+S/reopen. Main NPC/H/
  клавиатура+мышь/125% и native editor mouse остаются открытыми.
  Evidence — `C:/Users/novos/Documents/Codex/2026-10-29/dialogue-history/`,
  native.log,720/native.log,workspace.log и dialogue-*.png. Авторские saves
  не использованы для проверки; изолированный ExploreState принадлежит lab.
- В этой же сцене `story_example`/`ember_story_preview.gd`. Новый
  `tools/test_story_preview.gd` в disposable Forward+15FPS PASS: движение/поворот/
  титр/ракурс, пауза/scrub, удержание snap после перемотки, skip в0/3.65/7.9с,
  cancel/repeat/обычный finish/выход; правка конечного native ключа UndoRedo,
  save/reopen и показ нового результата; отсутствующая цель/неподдержанная
  дорожка отклоняются до старта. Связанный test_camera_preset_study PASS.
- Native editor в disposable fixture: сцена/панель анимации/story_example
  открыты, дорожки видны; результат preview и @tool камера просмотрены.
  Это не ручная проверка мыши/горячих клавиш редактора. Она OPEN:
  Item.position последний ключ4.3с → X1.1 → Ctrl+S/F6/P/End → Esc;
  затем редакторские Undo/Redo/reopen/discard при изменении ключей.
  RESET — исходная editor-поза; Esc — фактическое состояние до просмотра.
- Evidence: в том же каталоге ниже `test_story_preview.gd.native.log`,
  `test_camera_preset_study.gd.native.log`, `story-editor.log`,
  `story-detail.png`, `story-finish.png`, `story-native-editor.png`.
  Текст — титры; реальный Dialogue/Action/main/риги пока не подключены.
- Owner/референсы/инструкция — Object Inspector Design → I3.15 «Проба ракурсов29.10».
- `tools/test_camera_preset_study.gd`, отдельный fixture project с двумя scripts
  и `scenes/prototypes/camera_preset_study.tscn`, native Forward+15FPS PASS:
  кнопки шести планов/цель в кадре, одна сторона оси, перенос пары, прерванный
  переход, пустая/исчезнувшая цель, смена привязки, save/reopen/reset.
- Запуск сцены из рабочего проекта Forward+ без ошибок, без загрузки main.
  Просмотрены шесть кадров; evidence —
  `C:/Users/novos/Documents/Codex/2026-10-29/camera-presets/native.log`,
  `workspace-scene.log`, `shot-0.png`…`shot-5.png`.
- Ручное OPEN: открыть сцену/F6 → 1–6/Tab → Пробел → слайдеры → H → R.
  Проверить читаемость лиц/плеч/предмета и темп переходов. Runtime-слайдеры
  временные; стартовые значения/NodePath anchors сохраняются в Inspector ShotRig.
  Не приёмка катсцены/интеграции диалога/main. Editor-документы/история не менялись.

### Груз у берега28.10

Цельная authoring-проба28.10:
- test_quest_conversation_draft в native Forward+15FPS PASS после воспроизведения
  потери текста на selection: реплики/финал/режим/награда сохраняются между NPC и
  целями; до назначения Quest/NPC не меняются. Save не выдаёт ложный успех,
  навигация предупреждает, cancel сохраняет, discard/reset убирают неназначенное.
  Назначение второй цели сохраняет черновик первой и финала. Успешный разговор
  подтверждается отдельным ack, zone-save не очищает текст. Черновики сессионные.
  Связанные authoring journey, NPC options, quest workflow/Undo/reopen/discard и
  plugin parse PASS. В test_quest_graph_workflow освобождены два fixture UndoRedo
  после clear_history; это cleanup проверки, не заявление об игровом memory fix.
  Evidence: quest-workflow/pending-native.log/png, pending-journey.log,
  pending-options.log, pending-workflow.log, reply-selection-probe.log.
  Ручное OPEN: текст → выбрать NPC → переключить цель → назначить/сбросить →
  Ctrl+S/reopen/F5. Сохранение черновика между перезапусками не реализовано.
- test_quest_authoring_journey в native
  Forward+15FPS PASS: свои тексты без заготовленных диалогов, пустой текст не
  создаёт NPC, напоминания/награда и отдельный completed_script_id, COW старой
  реплики/повтор без лишнего Resource, Undo/Redo Dialogue+Action+Quest+NPC,
  scene reopen, физический маршрут/F/зона и точная награда. После done виден
  свой финальный текст; отмена/повтор и cold save/load не дублируют монеты.
  Старый quest workflow и изолированный plugin parse PASS. Evidence:
  quest-workflow/short-reply-native.log/png, short-reply-workflow.log.
  Малая native UI-проба не является benchmark; полная main не запускалась.
  Ручное OPEN: свои тексты/напоминания → награда → финальная реплика →
  Ctrl+S/reopen/F5/прохождение, мышь/узкое окно/DPI. Инструкция — I3.14.
- `python tools/run_mixed_editor_tests.py --test test_quest_authoring_journey.gd`
  запускает тот же сценарий без окна: поля названия/4 целей, «Следующая цель»,
  создание NPC/места/ящика, свои тексты/напоминания/3 монеты/финал из карточки.
  Нет ручной записи quest flags/objective_scripts; callback adapters выполняют
  те же authoring owners с фиксированными позициями вместо editor map-selection.
- Сцена и saves — disposable fixtures. Авторские карты, saves и файлы
  оптимизации этой проверкой не меняются. В harbor_cargo различены4 display name,
  чтобы picker показывал просьбу/напоминание/награду/финал.
- Авторская сборка на main/мышь/gizmo/DPI всё ещё OPEN; пошаговый путь и известные
  ограничения — Inspector Design I3.14 → «Сборка первой цепочки из карточек».

Карточка NPC: напоминание и награда28.10:
- `test_quest_npc_options.gd` в disposable mixed fixture/native Forward+ PASS:
  режим напоминания и две награды из UI, пустая награда не сохраняется, talk-only
  не меняет цель/сумку, старый общий Action и исходный Dialogue не переписываются;
  отмена разговора/повтор, точные количества, Undo/Redo, scene save/reopen и cold
  save/load с завершённой целью, чтение настроек назад, создание reminder NPC.
- Reminder+reward и choice+reward запрещены; диалог с записью флага квеста
  нельзя назначить напоминанием. Runtime owners и Quest/save schema прежние.
- Старый native quest workflow: два разговора/выбранный ответ/создание NPC/
  передача/отмена/Undo/Redo/reopen/discard PASS; изолированный plugin parse PASS.
- Evidence в прежней папке quest-workflow: npc-options-native.log,
  npc-reminder.png/npc-reward.png, ember-native.log/conversation-plugin-check.log.
- Ручное OPEN: main → Ember Graph → «Груз у берега» → выбрать CargoKeeper →
  цель «Найти ящик» → «Только напомнить» и диалог; последняя цель → награда3 монеты.
  Назначить → Undo/Redo → Ctrl+S/reopen/F5; отменить/завершить/повторить разговор.
  Оценить мышь/расположение карточки/узкое окно/125%. Новый полный main-прогон
  для этой editor-формы не выполнялся; нижний PASS цепочки относится к сборке.

Срез: вторая цепочка из существующих механик, main/Map/Props/HarborCargoQuest.
Смотритель(112,6,280) → место/ящик(112,7.15,328) → F взять/поставить в золотую
зону(112,6,376) → вернуться/3 монеты. Прежняя береговая миссия сохранена.
- `python tools/run_mixed_editor_tests.py --test test_quest_harbor_errand.gd`
  и тот же gate в Forward+ PASS: создание через authoring owners/упаковка/reopen,
  отмена разговора/напоминание без зачёта, физический вход/F/settle, сохранение
  после постановки и cold load с верным маршрутом NPC, отмена награды и повтор
  без лишних монет. Проверки работают в disposable fixture, авторские saves не трогают.
- `errand-main.gd`/`errand-main.log`: Forward+ PASS того же маршрута на RAM-окне
  реальной landscape_compact с настоящим рельефом/физикой и прежними игроком/UI.
  Props вне поручения исключены только из RAM-пробы. Это не полный старт/ходьба
  по всей карте; API-расстановка игрока не доказывает ручной ввод/доступность маршрута.
  Форма золотой рамки подогнана к Surface, кадры до/перенос/после просмотрены.
- `errand-assets.gd`/log PASS новых production Quest/Action/Dialogue и ссылок
  финального prefab, стабильного crate pickup_id и сохранённой рамки.
- Evidence: `C:/Users/novos/Documents/Codex/2026-10-28/quest-workflow/`:
  `errand-native.log`, `errand-main-start/intro/carry/placed/done.png`, asset/main logs.
- Ручная приёмка OPEN: переоткрыть main/F5 → найти нового смотрителя у берега →
  пройти все4 стадии по F → Q/3 монеты → Save/Load → повтор разговора без награды.
  Создание всей цепочки автором без ключей OPEN; gaps — Inspector Design I3.15.

### Послание на берегу27.10

Одна проверяемая цепочка на `landscape_compact`, технические owners — Handoff →
«Предметы в мире и бутылка». Автор выбрал клетку1м; первая поляна5×5м.

- `python tools/run_world_item_tests.py --native`: world/inventory transfer,
  физический drop/pickup, атомарное открытие, чтение,0/2/3 ракушки/обмен,
  отсутствие дубликатов, старыйv2/Load в той же сцене, ItemEditor и draft
  Undo/Redo/save/reopen/discard — PASS. Reward endpoint в **этом** тесте задан fixture.
- `python tools/run_shore_combat_tests.py --native`: настоящий Combat/HUD/AI
  до победы, enemy initiative после расстановки, двойная задержка при rear,
  Map/scene identity,1м, отсутствие боевого пола/Environment, scaled camera/picking,
  кожа в autosave **до** receipt, отсутствие повторной выдачи, итоговые10 монет — PASS.
  Отдельная defeat-fixture(HP героев обнулены только в тесте) проверяет in-place
  Retry: новая попытка/seed без повторной расстановки и без изменения persistent party.
  Победа после Retry достигнута обычными preview/commit/ИИ без изменения HP.
- `python tools/run_save_destination_tests.py --test test_combat_encounter_transition.gd`
  и `--test test_combat_defeat_retry.gd`: прежняя отдельная арена/result/Retry/Load PASS.
  Coverage texture даётся fixture в памяти; `_refresh_world_items` не трогает
  уже выведенную из дерева exploration-сцену. Авторские карты/saves не меняются.
- Связанные interaction4 gates, inventory_equipment, party_save_v2 и
  quest_journal_authoring — PASS; diagnostic journal включается явно в тесте.
  Чистый `test_combat_prototype.gd` в disposable project PASS: baseline состав
  прежний, добавление шаблона кабана не подселяет его в лабораторные бои.

Main evidence: `C:/Users/novos/Documents/Codex/2026-10-27/ember-shore-mission/`.
`main-mission.gd` запускает настоящий controller/содержимое main с RAM dense_window
участка без сохранения карты, реальные PNG текстуры алиасами в памяти, Forward+30FPS.
Проход делается API/F route с переносом игрока между точками, не ручным ходом.
`main-mission.log`: SHORE_MAIN_MISSION PASS — бутылка/drop/open/read/хранитель/
3 ракушки/настоящий бой/кожа/одноразовая награда, identity мира сохранена;
screen→cell picking PASS. Просмотрены boar-on-main/battle-on-main/mission-complete.
Старый `main-bottle.log` закрывает только этапы до сдачи ракушек. Этот проход
не доказывает полный холодный старт/экспорт/weak-PC и ручное управление.

28.10 автор подтвердил прохождение всей миссии от начала до конца: функциональный
ручной gate закрыт. Это не отдельная приёмка баланса/authoring/всех визуальных деталей.
Маршрут для повторной проверки: обычный F5 → береговая бутылка(F) → сумка(открыть/выбросить/
подобрать/прочитать) → хранитель за домом(согласиться/позже) →3 ракушки →
хранитель → кабан(ЛКМ/со спины/враг первый) → расстановка/бой → победа/кожа →
хранитель/награда. Q/повтор и свой Save/Load между этапами/перезапуск отдельно
ещё OPEN: сообщение о прохождении не подтверждает все эти варианты.
Ввод/ощущение инициативы и арт/анимации остаются отдельной оценкой;
автоматическое поле на любом склоне и переработка всей authoring UI не заявлены.

Обратная связь28.10: `python tools/run_shore_combat_tests.py --test test_explore_feedback.gd --native`:
focus bottle/NPC, отдельный outline material без изменения source, F на выделенный
предмет, переключение/сбор/уход/сумка/диалог/combat lock, HUD скрытых/активных/
завершённых целей, stage toast и resume без нового toast — PASS.
`test_shore_combat.gd` Forward+ PASS: завершение эффекта/блокировка и возврат
команд, прежние AI/result/Retry/награда. World-item regression PASS.
Native main-feedback прошёл всю миссию; после исправления stencil/размера[F]
повторён только визуальный участок bottle/NPC/shell/HUD(`feedback-ui-final.log`) PASS.
Новый UI/эффект вручную ещё OPEN; main кадры/лог —
`ember-shore-mission/main-feedback.log`, `feedback-*.png` в прежнем evidence folder.

Вход отпрыжками28.10 заменяет прежнее затемнение по просьбе автора.
`python tools/run_shore_combat_tests.py --native` PASS:2 героя/1 враг и4 героя/
2 экземпляра одного enemy template. Те же мировые Node identities остаются видимыми,
позиция лидера проходит дугу и совпадает с semantic клеткой после посадки;
black cover/непрозрачный Lab fade отсутствуют, команды заблокированы в движении.
У полного состава без deployment panel первый AI не действует до посадки.
Прежние Retry/result/skin/reward и возврат управления остаются PASS.
Враги связываются по combat_unit_id внутри своей field zone; сторонние зоны не
подменяют одноимённый шаблон. Источники рига/модели Хоши не редактируются.
`main-hop.gd`/`main-hop.log` — native PASS Hoshi/спутник/кабан на RAM-участке main,
квестовые флаги подготовлены явно только для visual probe. Это не новое доказательство
всей цепочки и не ручная оценка темпа. `hop-before/mid/landed.png`,
`hop-transition.gif` —56 native кадров, финальная запись fixed30FPS(26 кадров входа),
это offline запись движения, не замер производительности. Вид одобрен автором.

Подбор28.10:
`python tools/run_world_item_tests.py --native` PASS: тот же ItemVisual отделяется
от физического тела только после выдачи, повтор не создаёт grant/эффект, подъём,
движущийся collector, схлопывание и освобождение эффекта, autosave во время показа.
Связанный combat hop/result/Retry gate PASS после переноса общей формулы дуги
в `ember_arc_motion.gd`. `main-pickup.gd`/log: native визуальная проба бутылки и
ракушки на RAM-участке main рядом с Хоши PASS; это не повтор всей принятой миссии.
`pickup-pop.gif` —39 native кадров bottle pickup в fixed30FPS, `pickup-bottle-10/18.png`
и `pickup-shell-10/18.png` показывают полёт/сжатие. Запись не является замером FPS.
Новая анимация подбора вручную OPEN.

Запуск полного набора или отдельного теста
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

Актуальный ручной gate: на основной карте выбрать свой voxel-объект → «Создать экземпляр» →
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

### Exploration/editor mechanics — без Test Pier

Test Pier и последние пять исходных импортов удалены23.10.2026. Старые записи
PASS/пути в этом документе описывают исторические прогоны и не требуют их возврата.
`tools/test_exploration_mechanics.gd` заменяет прежний `test_test_pier.gd`:
пара protagonist/mira, follower, Tab и сумка/Q/E, физический пол и преграда,
pause Save/Load с reload и повторный вход. Запись — unique user://ember-tests/.
`tools/fixtures/ember_editor_mechanics_fixture.gd` создаёт тестовые объекты/воду/пол;
редакторная сцена/Surface появляются только в защищённом временном проекте.
Три искусственные Source/mixed prefab/source-only принадлежат native fixture;
реальные карты и авторская библиотека в эти прогоны не копируются.

Адресный запуск: `python tools/run_remaining_editor_tests.py --mechanics-test
test_exploration_mechanics.gd`. В том же runner доступны `--mechanics-editor`
для editor_test_world_editor/voxel_context/voxel_conversion/voxel_object_canvas.gd
и `--mechanics-native` для test_voxel_placement_preview/voxel_preview_renderer.gd.
World editor сохраняет кисть/water/один Undo/Redo/Save/reopen и объектный fork;
его тестовая поверхность320×64×128 покрывает операции, а большие бюджеты остаются
у test_surface_large_profile. `run_native_voxel_tests.py` проверяет каталог,
полку и source-free PCK на3 синтетических моделях.

После удаления: `python tools/test_retired_city_references.py` и
`--headless --path . --script res://tools/test_retired_content_catalogs.gd`
проверяют отсутствие retired-ссылок/моделей, fallback старого сохранения Причала
во вход landscape_compact и неизменное round-trip старого прогресса.
Ручной проход управления относится к основной карте; API/PASS не заменяет мышь,
горячие клавиши и ощущение игры. Старый ручной gate обхода Причала снят вместе со сценой.
Бой/Retry active-party gate ниже этим не закрывается.

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


## Расширение main3×3 и редактируемое море —25 октября2026

Контракт/текущая истина — World Authoring → «Приоритет25.10 · карта3×3».
Focused: `tools/test_terrain_coast_expansion.gd`; related selection/lake regressions.
History regression: `tools/test_section_brush_history_tiles.gd` and
`tools/test_compact_section_brush_batches.gd`; caps/base/side and bounded dirty tiles.
На копии main: старые channels/overrides/flows/rules/poses сохраняются; partial25m edge
достраивается; coast repeat/move/off/manual protection, UI/Undo/Redo/save/reopen/discard.
Forward+ на временной копии проекта: три облика, берег/стык, raise/smooth через стык,
видимое изменение до release, один Undo на мазок, Cancel и отсутствие позднего remesh
после Discard. Авторская мышь/горячие клавиши/композиция OPEN; API их не закрывает.
Дополнительный риск масштаба: full3×3 сфера TIMEOUT241с, готовое движение не проверено;
следующий focused gate — её подготовка, не полный прогон редактора.
Не повторять эту матрицу после каждого визуального изменения; расширять по конкретному риску.


## Планер берега25.10 — технически выполнен, ручной ввод OPEN

Owner результата/ограничений — World Authoring → «Планер берега»; полный контракт здесь не дублируется.
- `tools/test_coast_planner_workflow.gd` PASS: drag ghost/no terrain write/one Undo,
  exact Undo/Redo/Esc/add/Delete/map hit; focus после поля, validation, compressed Plan,
  обычный/deferred save rollback, foreign-file conflict, retry/reopen/Discard/Save As;
  native publication после clean Discard. Terrain-файл не переписывается от точек/плана.
- `tools/test_coast_preview_looks.gd` PASS:2→0→1→2, совпадение preview/commit geometry,
  отсутствие изменения Source, возврат hidden tiles при Cancel.
- `tools/test_terrain_coast_expansion.gd` PASS после исправления exclusive upper bounds.
- `tools/test_grove_snapshot_storage.gd`: RED1050002B → GREEN812B; native instance ref,
  исключение derived texture/runtime node, сохранение pose/metadata/авторского child,
  повторный restore не разворачивает prefab. `test_terrain_plan_grove` и
  `test_world_recovery_async` PASS. BoxMesh fixture приведён к runtime ArrayMesh contract;
  производственный свет ради теста не менялся.
- Native Forward+ main-copy:72 voxel preview tiles; Apply/Undo/Redo/Save/Discard/reopen PASS.
  Related early replay:20 input updates before release do not publish terrain; one Undo.
  Bounded jobs ускорены в QA driver, поэтому wall time этого replay не является замером FPS.
  Recovery458MB/hang →5606B, worker completes, Save completes. Новая карта проекта не создавалась.
- Main migration:247 SceneState nodes/properties и Plan.data совпали с живым backup,
  Source SHA256 не изменился; Plan.res150814B. Актуальное сжатие масок/размер main —
  «Маски травы / локальность / вход берега» ниже. Backup/evidence: Documents/Codex/2026-10-25/ember-planner-review.
- Старый рабочий editor завершился после live script reload; MCP отключился, причина не
  подтверждена. Повторять этот reload не требуется; свежий disposable editor прошёл сценарий.
  Main проверена/опубликована без headless editor, через Resource publisher и atomic scene-reference migration.
Ручной gate: открыть Godot/main заново, проверить клик/список/точки/клавиши/панель и свой
Preview/Apply/Undo/Save. Автоматический PASS не закрывает ощущение ввода, композицию,
скорость подготовки большого берега или full3×3 sphere gate.


## Повторное чтение цвета растительности26.10 — technical PASS, manual OPEN

`tools/test_foliage_color_reuse.gd` — native Forward+, user://; reference отключает только
новый shortcut и использует прежний weighted fallback.24 картинки (grass/flower/ground/
bank-depth stone ×6 условий): single/mixed same IDs, distinct IDs, gray, blade-off,
legacy smooth-off; light modes0/1/2. Exact RGB, покрытие не пустое. Шейдер ограничен
прежним painterly/blades, не меняет weights и не вводит uniforms/varyings/schema.
Прежний `test_foliage_indexing` с before snapshots:12 GPU sphere кадров0 changed pixels,
geometry/bounds/target mapping прежние. Main-copy:3 looks×2 расстояния,76 323 instances,
220 masks/221 buffers exact; рабочие scene/terrain/Plan byte-identical.
Профиль/замеры/границы — World Authoring → «Повторное использование цвета растительности26.10».
Editor/history/serialization не менялись, полный save-cycle не повторять без новой причины.
Evidence: Documents/Codex/2026-10-26/ember-foliage-color-reuse. Manual feel/большая сфера OPEN.


## Индексация растительности25.10 — technical PASS, manual OPEN

`tools/test_foliage_indexing.gd` — native Forward+, user:// fixture. Для сравнительной проверки
CLI args задают внешний output и `record` (до правки); без record старый before.bin/кадры
сравниваются с новым builder. Обычный запуск без before выполняет compactness/table/render
visibility проверки и не зависит от авторской карты. Не использовать headless для render.
Пять исходных meshes: exact expanded position/normal/tangent/color/UV/UV2/order/AABB,
indices/compactness. До реализации RED (нет indices), после GREEN. Подготовка сферой
той же позиции/normal получает те же target rows после индексации;12 GPU кадров травы /
сиреневых соцветий (2 looks×3 положения×2 объекта) —0 changed pixels, покрытие не пустое.
Main-copy A/B: прежний builder против нового на тех же materials,3 looks×2 расстояния;
211 patch meshes exact,76 323 instances /220 masks /221 buffers без изменений. Source
scene/terrain/Plan SHA256 прежние. Средний выигрыш не трактовать как FPS-гарантию; подробный
профиль и границы — World Authoring → «Маски, локальное обновление», индексация25.10.
Editor/history/save code не менялся, полный save-cycle не повторяется для mesh-only среза.
Evidence: Documents/Codex/2026-10-25/ember-foliage-indexing. Авторский feel/вид и большая
сфера основной3×3 карты остаются открытыми.


## Подготовка и подключение земли25.10 — technical PASS, manual OPEN

Owner/профиль/ограничения — World Authoring → «Подготовка земли в редакторе».
`tools/editor_test_terrain_preparation.gd` запускается native Forward+ EditorPlugin только
в disposable checkout, fixtures/cache в user://. Не запускать working `--headless --editor`.
Dense/sectioned cold-warm, вода и три облика; vertices/UV/colours/collision/field/layout
совпадают с прежним mesher. После удаления повторной GPU-упаковки только packed normals /
tangents допускают<=1e-4; cold/warm нового пути byte-equal. Независимый старый mesher15
случаев и render при трёх углах солнца PASS (max1/255, mean<6e-7).
Новый input при частичной публикации отменяет старую; до commit видимые mesh/physics/field
прежние. Непрерывный мазок публикуется до release. Open/Discard с prepared resources не
подключает их к новому Source; неизменённые tiles сохраняют pick field/layout. Invalid
CPU cache отвергается и пересчитывается. Runtime cache/shape/history regressions PASS.
Полная main-copy native проверяет прежние masks/76323 detail buffers, локальную правку,
Undo/Redo, native Save/reopen/discard; source files рабочей карты byte-identical.
Max terrain process8–10мс; cold≈54.7с/reopen≈36.55с, полное ожидание не считать ускоренным.
Профили — наблюдения одного сценария, не shipping FPS и не ручная приёмка.
Evidence: Documents/Codex/2026-10-25/ember-terrain-publication-study.


## Трава Б26.10 — main integration technical PASS, manual OPEN

Owners/границы — Terrain Authoring → «Объёмная трава Б на основной карте26.10».
- `test_grass_cards_main.gd` native Forward+: настоящая landscape_compact,125 обычных узлов,
  110 непустых/72 280 пучков. Проверены8 треугольников, UV полного атласа без palette overwrite,
  правильные atlas/grass slot, переходы GrassPatch1→2→0, opaque прежних обликов,
  byte-exact buffers возврата и неизменные density/seed/size/transform авторских узлов.
  Сняты game camera/общий/близкий/движение; own visual acceptance OPEN.
- `test_detail_preparation` PASS: fresh-node/disk reopen, exact cached transforms трёх обликов,
  отмена старой маски и отказ от невалидного кэша.
- `test_grass_local_refresh` PASS: sculpt/paint/restore затрагивают только близкие patches,
  покраска песка убирает траву; дальние экземпляры сохранены.
Scene/terrain/cartoon_grass/общая фабрика и общий shader SHA256 прежние; PNG атласа совпадает
с принятой пробой Б, mipmaps включены. Только обычная детальная трава получает новый mesh.
Первый full-map cold capture превысил180с; диагностика подтвердила последовательную подготовку,
а не зависшие/неактивные узлы; повторный full-map прогон PASS. Общая загрузка/FPS не закрыты.
Сфера18м выключена только в capture RAM; её performance gate не затронут. Есть прежнее
предупреждение UID берёзы с успешным path fallback, без ошибок шейдера/тестов.
Evidence: `D:/aion2-grass-study-2026-10-26/main-map/{main-checks.json,main.log,preparation.log,refresh.log}`.
Ручное действие: перезапустить Godot, F5/main detailed, оценить обычный маршрут/склоны/свет/движение.

## Трава/цветы на объекте27.10 — technical PASS, manual OPEN

`test_object_detail_brush.gd`, native Forward+: распознавание grass/stone по физической грани,
preview/Cancel, Undo/Redo, стабильные104 instances/3 looks, root height, detailed-only lean,
цветы, локальная инвалидация после движения/перекраски, save/reopen/discard/validation — PASS.
Повторная root query ограничена local bucket320 из8192 треугольников fixture.
`test_solid_volume -- --physical-looks`: floor sample совпал с physics ray в3 обликах.
`test_object_grass_anomaly.gd`: object-root shift0, terrain endpoint deltas сохранены — PASS.
Отдельный native ground preview/cleanup PASS после исправления exit-уведомления.
Полный ground harness ранее имел один cold-preview timing failure; повторялся только этот
проваленный сценарий, остальные успешные проверки не дублировались. Его известный1 ObjectDB
leak при выходе не исправлялся в этом срезе. Авторский ввод/вид/долгая сессия OPEN.
Main: две EDM1-маски через прежнюю кисть, свежий Save точен, предыдущие значения/size/seed
сохранены; terrain/voxel Sources/collisions неизменны. Owners/evidence — Terrain Authoring →
«Трава и цветы на уступе». Наклон внутри сферы наследуется от исходного scatter, не отдельного blend.

## Узкое смешивание volume-покраски27.10 — technical PASS, manual OPEN

`test_volume_material_blend.gd` PASS: нормализованные положительные веса/непустые slots,
непрерывность общей точки между треугольниками, два покрытия/тройной стык, узкая полоса,
чистая трава вдали, детерминизм. Source/вершины/нормали/CUSTOM0 прежние; voxel без смешивания.
`test_solid_volume.gd` PASS: выемка/paint, Undo/Redo/save/reopen/discard/validation;
его известный1 ObjectDB leak при выходе не закрыт этим срезом.
Native Forward+ main3 looks просмотрены;3 volume-prefab свежая validation PASS,
физические грани точны, сцена/terrain/Source/внешние collision.res не изменены.
Evidence/ограничение доминирующего height-профиля — Terrain Authoring → «Узкий переход объёмной покраски».
Вид и управление автором OPEN; художественный грунт этим срезом не принят.

## Общая дистанция глубины27.10 — technical PASS, manual OPEN

`tools/test_material_depth_distance.gd`, native Forward+ в disposable project:
прежняя панель near/far → земля/solid/alternate-материал сферы; Undo/Redo,
смена3 обликов, пересоздание материала, разные world units, независимость масштаба рисунка,
безопасный интервал при near≥far, save/fresh reopen/discard — PASS.
Валидный bounded Source основной карты; меш/коллизия сохраняются, preparations сферы0.
Evidence — Terrain Authoring → правило расстояния; ручная оценка затухания OPEN.

## Регулярная рябь объёмной поверхности27.10 — technical PASS, manual OPEN

`--headless --path . --script res://tools/test_volume_surface_fairing.gd`:
наклонный бинарный объём, угол ошибки граней13.651° RED →1.977° GREEN;
среднее расстояние до аналитической плоскости0.07559→0.01084 вокселя, max0.02131.
Проверяются ограничение перемещения0.35 вокселя, исходные ячейки, неизменные bounds/Source.
`test_solid_volume` PASS: боковая выемка, покраска, связная замкнутая поверхность,
Grab после вырезания, Undo/Redo/save/fresh reopen/discard/validation на user://.
`test_solid_volume -- --physical-looks` Forward+ PASS: единая canonical collision,
surface_floor_sample совпадает с physics ray, облик не меняет физическую высоту.
Native disposable publication:3 реальных volume-prefab main проверены в3 обликах с физикой;
сохранены выемки/paint ownership. После рабочей публикации fresh load/validation и совпадение
mesh/collider PASS. SHA256 main/terrain/трёх voxel Sources прежние. Производные mesh/collision
обновлены, коллизии вынесены в бинарные .res без раздувания текстовых prefab.
Forward+ просмотр main detailed/low poly/voxel и серого материала PASS; чувство кисти/сфера/
свой проход остаются авторскими gates, не закрывать их этими API-проверками.
Использован прежний Surface Nets с ограниченной релаксацией; это не принятие Б/В грунта,
нового общего mesher или глобальный прогон. Сборка/публикация материалов — Forward+:
headless попытка в disposable checkout дала null images при сериализации Texture2DArray,
её выходы отброшены; финальные материалы/коллизии подготовлены и свежезагружены нативно.
Evidence/backup/скрипты публикации: `C:/Users/novos/Documents/Codex/2026-10-27/ember-volume-fairing/`.

## Общая глубина библиотеки27.10 — technical PASS, manual OPEN

`--path . --script res://tools/test_material_library_depth.gd` (Forward+): реальные library IDs
soil/grass/stone, один Pattern-редактор → profiles земли и многоматериального объекта;
независимость амплитуд, выключение одного материала, Undo/Redo/save/reopen/discard/validation,
нет remesh/collider change, возврат трёх обликов. Одинаковые рецепты делят GPU-банк;
амплитуда не пересоздаёт карты. Для числовой проверки использован обычный реальный Dialog,
а не ручной ввод; собственная мышь/ощущение остаются автору.
Нейтральная карта высоты должна сохранять освещение формы; отдельный `-- --normal-only`
проверяет это после исправления POM-нормали. Старый plane-normal путь — отрицательный контроль.
На том же нейтральном поле RGB-разница нового пути0, прежнего0.001064; gate отделяет
нормаль формы от видимой внутренней триангуляции.
`test_landscape_material_authoring`: прежний цикл брусчатки/карты/покраски/сохранения PASS.
Его fixture адаптирован к секционной main через ограниченное dense_window: прежняя проверка
сравнивала пустые legacy top_materials; та же ошибка воспроизведена до текущих изменений.
`test_stone_material_layers`: прежние слои/регуляторы/история/сохранение PASS;
`test_object_pattern_scale`: масштаб/геометрия/облики/привязка параметров сферы PASS.
После POM-нормали повторяется только относящийся render gate, не вся матрица истории.
Копия main: просмотр трёх обликов, после исправления нормали повторный подробный кадр.
Дальние участки/сфера ограничены только в capture RAM; полный FPS/load/свой motion не закрыты.
Последний подробный кадр: GPU9.52мс для этого ограниченного ракурса, не сравнение полного мира.
Смешанная высота нескольких профилей на одной границе не заявлена: пока один доминирующий ray.
Исходные рисунки и авторская карта не записывались. Evidence:
`C:/Users/novos/Documents/Codex/2026-10-27/ember-material-library/`.

## Локальный масштаб покрытия27.10 — technical PASS, manual OPEN

`--path . --script res://tools/test_object_pattern_scale.gd` (Forward+): независимость двух
экземпляров/общего Source/Pattern; три облика; размер узла; неизменность mesh/collision/амплитуды
глубины; привязка копий материалов сферы без подготовки; история/save/reopen/discard.
Render сравнивает проекции земли/объекта и старую ошибочную привязку света как отрицательный контроль.
`tools/editor_test_object_pattern_scale.gd` — EditorPlugin только в disposable ember-rock-pilot:
настоящий Inspector/SpinBox → native Undo/Redo → Save/reopen/discard PASS.
Surface Canvas в этом fixture отключён, чтобы его прежний восстановленный черновик не перехватывал
3D-навигацию; это не проверка полного Canvas-перехода. Ручной ввод остаётся автору.
Копия основной карты: три облика и изменение масштаба одного NaturalEarthOutcrop просмотрены;
дальние участки скрыты/подготовка ограничена в capture RAM, это не замер полной загрузки/FPS.
Авторская карта/PNG травы не записывались. Evidence:
`C:/Users/novos/Documents/Codex/2026-10-27/ember-object-pattern-scale/`.
Не повторять успешные проверки без относящегося изменения; художественный вид OPEN.

## Маски травы / локальность / вход берега25.10 — technical PASS, manual OPEN

Результат и единственный профиль — World Authoring → «Маски, локальное обновление».
- `test_grass_mask_storage`: legacy load, compact Save/reopen/Node duplicate, exact numeric types,
  explicit zeros/fractional values, bounded decode/validation, corrupt blob and invalid legacy retention.
  Full256-cell sample:5549→≈600B, без квантования.
- `test_grass_local_refresh`: реальный projection/GrassPatch, sculpt4 nearby of8 vs old8,
  paint removes grass from sand, brush-grid revision unchanged, same-size section restore retains
  far scatter, empty new tool cache initializes without rescatters.
- `test_detail_brush` Forward+ PASS: маска/кисть/история/save/reopen/discard и облики.
  `test_section_brush_history_tiles` PASS: footprints/caps/base/side/Discard не регрессировали.
- `test_coast_planner_workflow` переведён с нижнего private handler на forward_input. RED на
  реальном guard; GREEN после маршрутизации. Native main-copy дополнительно вызывает plugin
  `_forward_3d_gui_input`, numeric field focus → point press/ghost/release/Undo/Redo.
- Native main-copy:220 masks exact,76323 instance buffers byte-exact with live editor;
  local brush25 of221, Source Undo exact, compact scene134587B, reopen/discard restores masks.
- Публикация после закрытия автором Godot: fresh saved main,220 masks/34811 cells,
  все247 Typed SceneState nodes/properties совпали при нормализации storage alias.
  Actual137012B<500KiB, terrain/Plan SHA256 прежние. Source UID/прочие поля не переписаны.
Не считать это закрытием производительности: на копии малый sculpt settle≈15.6с,
reopen≈60с; baseline GPU≈94ms with details /40ms hidden only on copy. Background editor/Hoshi
оставались активны. Мышь/ощущение/свой просмотр и оптимизация оставшихся CPU/GPU этапов OPEN.
Evidence: Documents/Codex/2026-10-25/ember-grass-coast-performance. Другие успешные gates
не повторять без нового относящегося изменения/дефекта.
