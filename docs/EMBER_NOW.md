# Ember — текущая точка

Актуально: 2026-10-17. Ветка: codex/runtime-water-region-activity.
Материалы/общая кромка/пять пород/их PNG/сцены/проверки сохранены в 41247dd.
Прежние трава/POM/правила формы сохранены локально в d9e33a9.
Прежняя база игровых систем — 6124184; мир/материалы до этих срезов — 0a7e1c5.
Настройки/наборы Lab, полный цикл, переходы, арена, условия и Старт игры сохранены;
открытые ручные gates прежние. Документация сохранённой базы — 0848090.
POM, световые LAB, перенос профиля травы/пресетов и shape LAB входят в d9e33a9.
Fetch/push в текущем checkpoint не выполнялись. Полный архив1084 файлов до commit
(включая арт-черновики/старые captures/локальные файлы), проверенный SHA-256 manifest —
`C:/Users/novos/Documents/Codex/2026-10-15/ember-checkpoint-trees/`.
В Git входят нужные текстуры; тяжёлые drafts/captures и служебные файлы сохранены
в архиве и остаются локально. Предыдущий полный архив — checkpoint-b7353afb/ от13-го.

## Активная цель

**Sol: принятая форма камня перенесена в Source/Prefab; ручная приёмка OPEN.**
Основной объект — content/voxel_models/vox_painted_rock_group.tres: шесть прежних
масс и точные принятые occupied voxels/part IDs, opt-in solid_surface в том же Source.
Prefab строит грани и collider из одних треугольников; Map floor/compact navigation
учитывают этот объект. Старые бугры под ним удалены из Source общей сцены.
Общий editor/F6 просмотр — scenes/compact_environment_material_review.tscn;
дневной/вечерний/ночной свет и боковое/контровое направление проверены.
Evidence: C:/Users/novos/Documents/Codex/2026-10-17/ember-rock-shape-transfer/.
20 октября: этот камень получил тонкую кромку-рамку только по внешнему контуру (силуэту) камня;
ширина — настройка материала в окне паттерна (мм, у cartoon_stone 10; не тоньше ~1.5 px);
cartoon_stone: custom, сила 0.5, другие потребители тоже и рисунок, привязанный к самому
камню (объектно-локальная проекция, facet_bias 0.35). Клавиши 4 (воксели) / 5 (low poly)
в compact_environment_material_review переключают облик камня; 6 (подробный) = тот же low poly +
глубина из рисунка (C2, 20 мм; ползунки в окне материала) и «живые» грани: каждая грань слегка
(Pattern.form_pull_mm, cartoon_stone 30 мм, вариант O1) тянется к форме вокселей Source, рёбра/силуэт/
collider/floor/Source прежние. Source, позиции mesh, collider, floor прежние;
evidence — ember-rock-form-probe/. Автор 20 октября принял вид кромки/рисунка камня.
Открыто: вытяжка рисунка на крутых скосах, weak-PC/движение камеры у глубины, личная приёмка
живых граней и перенос системы на другие объекты. Подробный облик = low poly + глубина из
рисунка + живые грани из вокселей; мозаика граней (ember-rock-form-probe/detail-*.png) отклонена автором.
Это перенос принятой группы, не универсальная замена всех terrain-скал других карт.
Новая оптическая глубина, общий world switch и commit/push не входят в срез.
Следующая цель (решение автора 22 октября): «материал из слоёв» — сначала проба А/Б/В слоёв
на этом камне (рёбра граней, своя плоскость на грань, трещины/сколы), затем отдельный срез
(Product Plan → цель материалов); перед переносом на другие объекты — ревизия направления.
Подробности, проверки и ограничения — Terrain Authoring → форма и цвет камня.

Принятая основа травы перенесена в основной cartoon_grass.
Автор принял показанный результат как рабочую основу («ок, нормально, давай далее»).
Личная проверка в основной игре этим не закрыта.
Точный256px рисунок из painted_light_grass, тон637f50/масштаб2м и прежний профиль
grass_light: low0.64/tint1/fill0.07/cool-warm-shadow. Новых controls/шейдера нет.
Новые/сохранённые назначения обновляются при обычной загрузке. Геометрия/Source/
paint/physics и прежние пучки/их позиции сохранены; это перенос материала покрытия.
Десять focused tests PASS; Forward+54 пары/54 exact LAB colour replay/54 returns,
108 motion frames. Native preview меняет GPU lookup без remesh; Undo/Discard exact;
трава-only shadow region реагирует во всех3 presets, возврат exact.
Последний1254px исходник в этом наборе заменён256px: производный bank1254→256,
фильтрация прочих слоёв может отличаться; их исходники и настройки неизменны.
Evidence: `C:/Users/novos/Documents/Codex/2026-10-17/ember-grass-editor-transfer/`.
Ближайшее действие — личная проверка травы/камня/дороги/грунта/дуба в игре;
уже открытую сцену переоткрыть.6 cold game frames exact;6 кадров прежнего
стенда с POM также exact относительно сохранённой проверки дороги.
Гладкий — основной путь; производные других обликов пока LAB. Новая глубина,
общий world switch и сфера аномалии отложены; commit/push не было.
Старый UI gate302/326px остаётся OPEN; детали у Terrain Authoring.

Камень уже в cartoon_stone: точный raw paint256px/тон90938f/2.4м, без новой глубины.
Прежний POM4см/32 сохраняется в его LAB-сценах с отдельной картой; новый3мм отложен.
Return: `ember-stone-editor-transfer/`; основной материал сохраняет нулевую глубину.

Дорога Б уже в cartoon_sand: общий PNG грунта v4/тонb9a47c/1.5м, без новой глубины.
Сборщик PNG работает с копией; общий источник/тон грунта сохраняются.
Return: `ember-road-editor-transfer/`; Undo/Redo/save/reopen и game matrix проверены.

Грунт v4 уже перенесён в soil_grain с размером0.6м и теми же PNG controls.
Undo/Redo/discard/save/reopen и обычный atlas refresh без remesh проверены.
Return: `ember-soil-editor-transfer/`; подробный master неизменён.

Кора Б дуба уже перенесена, личная проверка автором отложена. Return:
`ember-oak-bark-editor-transfer/`; форма/листва B/покраска/свет/физика прежние.
Сила глубины коры не выбрана: `ember-oak-bark-relief/` сохранена как проба;
автор почти не увидел разницы. Возврат — близко/развилки/движение света в3 обликах.
Остальные материалы/породы и общий production world switch текущим срезом не закрываются.

Камень17 октября нравится как проба («неплохо получилось, мне нравится»), личная
оценка отложена. Возврат: `ember-rock-paint-relief/` — выбрать Б flat/В до3мм,
проверить ближнюю/игровую камеру и движение солнца/камеры в3 обликах. Ни сила,
ни эвристика выделения height из крупных warm/cool пятен ещё не приняты.
6 tests/Forward+ PASS и ограничения сохранены у Terrain Authoring/Technical Handoff.
В сравнении коры фиксирован контроль А каменной пробы; новая глубина не выбрана.
Soil depth, weak-PC/личное движение и универсальный production-конвертер OPEN.

Дорога Б17-го принята рабочей основой; цельность набора нравится как рабочее
направление. Evidence/принятие: `ember-road-painted-refinement/manual-acceptance.json`.
Общий просмотр сохранён в `ember-environment-material-review/`;
финальная приёмка трёх обликов/листья low-poly/личное движение/weak-PC OPEN.

Грунт v4 принят рабочим цветом17 октября («вот хорошая»). Его новая оптическая
глубина отложена автором: ни0.008м, ни0.016м не приняты; в общем сравнении выключена.
Возврат: `ember-soil-depth/`, игровая камера/три пресета/side-back и движение.
Карта height LAB0.28–0.72 даёт перепад до3.5/7мм; существующий optional secondary
POM input/5 tests/162 stills/270 motion PASS. Owners/границы — Terrain Authoring.
Цветовой перенос soil_grain выполнен; новая глубина,
трёхвидовой мир и сфера аномалии остаются OPEN. Изменения не закоммичены.

Трава Б принята рабочей основой16 октября («Сойдёт, давай далее»), полировка отложена.
Её гладкий исходник точный, производные calm16/85%/7 углов и pixel32/контур3.125см
сохранены;9493 transforms прежние. Evidence `ember-grass-derived-looks/`.
Цвет/профиль основного покрытия перенесены выше; геометрические производные пока LAB.

Песчаная дорога16 октября сохранена как контроль А новой пробы выше.
Б17-го принят рабочей основой и перенесён в cartoon_sand, см. текущий срез выше.

Камень Б16 октября («пока подойдет») остаётся принятой цветовой основой.
Рисованный цвет17-го теперь в cartoon_stone; новая глубина остаётся отдельной пробой.
Форма Astra/Source, все три пары цвет/height, POM4см/32 и общий свет сохранены.
Evidence: `ember-rock-texture-refinement/`; это не финальная приёмка B/физики.
Сфера аномалии — отдельный этап после приёмки стиля, здесь не начата.
Проба статическая: общая мировая проекция; локальная привязка движущихся объектов,
переходы, ручные поправки и общий editor/runtime-конвертер остаются OPEN.
Физика камней/floor/navigation и точность convex fit не закрыты. Owners и детали —
Terrain Authoring → «Производные грунта», принятые трава/камень и песчаная дорога.
Изменения не закоммичены.

**Пять пород перенесены в основной authoring/save; дуб, берёза, клён и ель приняты.**
Саванна не принята: автору не подходят листва и ветвление; текущая основа сохранена
для правки. У дуба теперь назначена принятая кора Б (`oak-v3-painted.png`),
отдельные листья v8/B и форма сохранены; перенос описан в Terrain Authoring.
Это текущая реализация в рабочем дереве, поверх checkpoint 41247dd/2c2f76f; без push.
В «Объектах» доступны пять `vox_painted_*` с именами «… · рисованная основа».
Существующие авторские модели/карты не заменены. Генерация → Деревья использует
дуб21/листву B/кору Б, берёзу22, вытянутый клён23, саванну24 и плотную ель25 по умолчанию.
Широкий клён и прежние рецепты воспроизводятся; legacy defaults1–17 не переписаны.

Recipe/GeneratorPanel/GenerationPanel — прежние owners параметров и истории.
Открытие сохранённого дерева → существующая мастерская → «Генератор»:
высота/ствол/ветвление, общая и местная плотность по основной ветви, глубина тона,
приём теней40%, включение кромки и отдельные силы45%/18% доступны для правки.
Source schema7 имеет опциональный `tree_surface`: ограниченные опоры и оформление
готового дерева. Recipe остаётся editor-only; runtime строит из Source, не из Recipe.
Те же Prefab/Store/Catalog/SceneAuthoring сохраняют и размещают объект целиком.
Один общий toon body используется деревьями и остальными объектами; кромка прежняя.
Прежние LAB используют те же общие leaf-модули через тонкие совместимые входы.
Покраска ствола сохраняется; изменение заполненности Source показывает авторские
воксели вместо устаревшей декоративной поверхности. Collider остаётся древесным;
система координат гладкого ствола/voxel collision согласована.

Проверено PASS: ordinary creation/library/workshop, global/local Undo/Redo,
preview/save/reopen/map, обновление вариации и её экземпляров, validation/discard,
нулевая плотность, ручная покраска; отдельный Forward+ runtime из Source без LAB/Recipe.
День/вечер/ночь × side/back × tree/game, отдельная настоящая падающая тень.
Geometry/Source/texture guards строгие; LAB→published у дуба имеет измеренное
отличие до5 RGB8 (среднее≤0.15 RGB8 по кадру). Preview→save/reopen проверяется отдельно
строже; это не утверждение pixel-exact переноса LAB для дуба.
11 проверок PASS;45 native сравнений,30 кадров игровой камеры; отдельно5 готовых
основ из обычного Catalog/Prefab. При выходе editor smoke остались scan/ObjectDB warnings.
Итоговые логи/кадры/verification — `ember-tree-editor-transfer/` от15-го октября.
Owners/ограничения — Terrain Authoring → «Пять пород в основном редакторе».
Личная проверка на своей карте: движение и управление плотностью остаются OPEN.
Следующую правку саванны согласовать отдельно, сохраняя остальные четыре породы.

Трава6187, POM4см/32, ручная покраска земли, камера и единый физический пол сохранены.
Камера0а отложена автором. Ветер/LOD/лес/новые породы не начаты.
Автор напомнил о трёх обликах: новые деревья пока реализованы в гладкой подаче;
voxel-каркас сохранён. Три облика дуба и камня сравнивались в LAB Astra;
основной переключатель и общий конвертер окружения ещё не реализованы.
Старые LAB/evidence сохранены.

## Точка возврата к читаемости диорамы

Камеру автор проверит позже. Этап0а остаётся LAB/manual choice OPEN:
`compact_diorama_readability_study` → F6, исходная / две камеры / quiet PNG /
условная дверь-only scale с collider. Рост Кая1.8м/Миры1.5м прежний;
Source/paint/grass/POM, real step walk/party/save/movement/material gates PASS.
Рекомендация — сначала камера; quiet PNG не устраняет geometry strips.
Первое действие: кадры → камера → свой F6; input/125%/weak-PC OPEN.
Owners/evidence — Terrain Authoring → «Читаемость диорамы — этап0а»;
C:/Users/novos/Documents/Codex/2026-10-14/ember-diorama-readability/.
Имя Кай в GDD/unit display_name; ID/save прежние. Три окружения ALLfiring —
docs/art/references/allfiring/environments/README.md. Другие этапы не начаты.

## Точка возврата к подаче материалов

А принята основой в material_looks LAB; Б/В — необязательные lighting сравнения.
Код/сцены/проверки сохранены в d9e33a9; прямой shaderА, grass_field9621,
POM4см/32, 3 presets×side/back и camera/sun motion PASS. Свои F6/motion/weak-PC
gates прежние; owners — Terrain Authoring → «Три подачи материала и света».
Пробы low poly/pixel уже есть в LAB Astra выше; общий перенос, большой world foliage
и цикл суток не завершены этим срезом.

## Точка возврата к ручным правилам формы

Редактор «Мир → Инструменты → Форма → Сгладить» готов: common heights /
round/protect/clear, Source.surface_rules, один Undo на pointer-up; QA PASS.
Первое действие: свой мазок → Undo/Redo → Save/reopen → F6; форма/мышь/стыки/
near-far/125%/weak-PC OPEN. Guard32×32, один мазок около0.55с на стенде.
Два прежних native QA shutdown0xC0000005/scan-aborted сохранены в evidence;
последние native editor завершения exit0 не закрывают общую stability gate.
Owners/проверки — Terrain Authoring → «Ручные правила гладкого облика»;
evidence — C:/Users/novos/Documents/Codex/2026-10-14/ember-shape-brush/.

## Точка возврата к игровым системам

**Исходный native вылет повторно не воспроизведён; причина остаётся OPEN.**
Повторы cold/warm, формы, быстрый выход, scan/preview и 24 publication cycles
под Windows debugger завершились без исходного AV. Это не новый crash fix.
QA runner теперь сохраняет sandbox/cache/log/launch при native fatal exit до
удаления временного проекта; проверка retention падала до изменения и проходит
после. Подробности/исключённый ошибочный probe — Migration Plan. Возврат к
диагностике: новый AV → NATIVE CRASH EVIDENCE → точный сохранённый сценарий.

Узкая библиотека/боевые пояснения при125% исправлены; manual input OPEN.
Native editor scale1.25 (отдельный APPDATA), 1280×800→1600×900: compact разделы,
перенос toolbar, Save/Back доступны. Create не растёт до500×2229; длинный Delete
и dirty диалог переносят текст в ограниченном окне. Все основные формы/поиск/
Add/Undo/Redo/Save/reopen/dirty Cancel, Usage/Check/Lab dialog bounds PASS.
В бою scale1.25: пояснение шире, Header Reset/Menu/console input/footer доступны,
очередь и длинная цепочка прокручиваются. Wet/frozen/empty hover/Cancel/MP/turn
PASS; скриншоты просмотрены. Owners/evidence — Handoff/Migration Plan;
C:/Users/novos/Documents/Codex/2026-10-22/ember-ui-125/.
Первое действие: своё окно/масштаб → приём/эффекты → Save/Undo → бой/наведение/
прокрутка/Esc. Свои input/другие DPI/размеры/ощущение OPEN, gameplay/save прежние.
Исторический QA exit сохранён; успешные повторы не устанавливают его причину.

Пояснения эффектов: условия выполнены / пропустится с первой причиной и именем
статуса; SELF/CELL/empty/staged snapshot. Наведение обновляет карточку, rolls/
крит/итоговый урон скрыты. Targeted/privacy64 seeds и прежний HUD gate PASS.

Подбор эффектов: поиск имени/ID/описания/условий, preview до Add; no matches/all
used блокируют Add. Filter переживает Add/Undo/Redo, не пишет Resource/history.
Native focused picker/--actions/--effect-conditions PASS; своё удобство OPEN.

Условия отдельных эффектов готовы: все обязательные/ни одного запрещённого
статуса исходной цели до базового действия/шагов цепочки. Неуспех пропускает шаг,
основной урон сохраняется. Pure all-skipped chain не предлагается игроку/ИИ.
SELF/CELL/пустая клетка — GDD → этап 3.5; validation/refs/usage/checker/stale guards.
Targeted/related/15 regressions и native author → обычный бой/AI/Retry/результат/
Save/cold Load PASS. Свои сочетания/input/баланс OPEN; authored content/старые
реакции/save schema прежние. Проверить в Lab заморозку мокрой и сухой цели.

Повторные враги из общего шаблона готовы: ordered enemy rows, независимые
HP/MP/статусы/позиции/очередь, номера перед именами; общий template/AI/loot.
Стартовые характеристики копируются без перезаписи активных HP/статусов.
Loot/counters за каждого, XP встречи один раз. Native author3 → обычный бой/
Retry/Load/re-entry → victory3/loot6/XP35 once/Save/fresh Load PASS.
Свои состав/расстановка/input/narrow/125% OPEN, owners — Handoff/Migration Plan.

Независимые periodic doses готовы: cap1..12, default1 прежний; на пределе заменить
ближайший timer, отдельные сроки/HP. Сначала всё лечение до max HP, затем урон;
последний тик до истечения, снятие всех доз. Прочие modifiers однократны.
StatusRules/Combat, один statuses int|Array[int]; native HP25→30→18 PASS.
Свои дозы/баланс/input OPEN, canonical poison/regen остаются одиночными.
Группы И/ИЛИ без вложенности: mandatory и группы соединены И; пары actor/target
общие у игрока/ИИ/Grid/HUD. Свои условия/input OPEN. Обувь: MOVE/JUMP/стойкость/
Мокрый, примерка/Inventory; только shoes, overworld прежний. Свои обувь/баланс OPEN.
Старт игры: уровни/пять слотов/сумка только new game; default level1/empty/20 coin.
Старые saves используют свои данные. Свои старты/арены/наборы/старый Load/Save/
backup экипировки/narrow/125% OPEN, тесты изолированы; Handoff/Plan хранят gates.
Прежний publication trigger устранён адресным Filesystem update, 12 cycles PASS.
Прежние native exits и текущая диагностика — в начале этого раздела/Migration
Plan; повторять старые случаи как новые падения не нужно.
Дальнейшие расширения — по потребности контента и ручной приёмке.
Instances, дозы, группы, обувь/periodic HP без commit/push.

## Точка возврата к cleanup

F5 — landscape_compact; семь старых сцен и 13 city-only Resources выведены.
Архив: refreshed 998 files с SHA/CRC; общие 93 модели/деривативы сохранены.
Runtime/editor/catalogs native-only; retired saves → native вход с прогрессом.
Вступление боя — colored_crossing_intro → colored_crossing_demo, прежний
new_flag=true сохранён. Native startup/restore/menu/battle/interactions/party,
editor/story/shop/PCK и 16 mixed gates имеют targeted PASS; детали у owners
в Technical Handoff, JOI Exit Plan и MIGRATION_TEST_PLAN.
Manual F5/old Save/Load/Reopen/Delete, диалог → бой, 125% UI и полный
physical/export G4/G5 OPEN; long A/B не запускался, world_canvas physics
не пересматривался. Первый шаг возврата — ручной F5 и старый Load с прогрессом.
Cleanup включён в checkpoint 841b294; отложенная ручная приёмка остаётся открыта.

## Точка возврата к материалам

Перенос принятых травы/света в прежние Pattern/editor/WorldLook готов, QA PASS;
своя ручная приёмка OPEN. Вернуться: вариант травы → параметры/подбор/Undo →
Save/reopen → F6/три пресета/настоящая тень; mouse/narrow/125%/weak-PC OPEN.
Owners/evidence — Terrain Authoring → «Живописный свет», material-workflow-transfer.

**Гладкая мультяшная земля — первый родной тестовый срез готов к пробе.**
`compact_cartoon_ground_study` → F6; в редакторе «Вид мира → Материалы →
Поверхность земли». Сетка16×16 сохранена; один расчёт для mesh/collision/picking.
PNG выбирается в прежнем материале. Native brush/Undo/Redo/Save/Reopen/Discard,
PNG и переключение стиля PASS. Авторские вид/ходьба/input/берег OPEN.
Пока до площади32×32 блока, без ground LOD; owners/gates — Terrain Authoring.
Отдельная проба объёмной фактуры — `compact_cartoon_relief_study` (12×8 м):
камень/песок/грунт, B до/после; вторая проба — карманы/смешивание вместо полос,
неровные гребни, объём и мягкий световой рельеф по PNG камня. Seam/material
weights/physics/picking/paint/Undo/cache/Save/native PASS; вид/ходьба OPEN.
Направление участка автор принял; следующая проба — `compact_cartoon_generated_study`
(24×16 м): реальный generator hills + независимая фактура, B основа/детали.
Generation/wet floor/seed/Save/physics/picking и native editor PASS; новый
остров/четыре покрытия/берег/ходьба OPEN. Панель генератора: сила0–100%, масштаб
0.5–3×, отдельный рисунок деталей; optional Plan fields, strength0 legacy exact.
Selected area32×32, preview/Apply/Undo/Redo/Plan Save/Reopen/Discard и native PASS;
свои настройки/input/weak PC проверить. Обычный плоский берег теперь пересекает
воду с гладкой землёй; contour/depth/seams/dry intent/native preview/Apply/Undo
PASS. Свои движение/wet contact/weak PC и volume/waterfall/swash OPEN.
Берег пока оставляем. Автору не подходит пёстрое распределение покрытий острова.
Приоритет автора — адаптация прежнего генератора и лепки. Первый срез готов:
«Неровности → Рисунок · фактура покрытия» сохраняет покраску/лепку/шаги/воду;
compact_smooth_tools_study8×8 → F6/B/M. Восемь кистей/strides/physics/pick и
native input/Undo/style/Save/Discard PASS; вид/живые мазки/weak PC OPEN.
Два shutdown 0xC0000005 после PASS, последующий clean exit; native cause OPEN.
Bulk panel теперь разделяет создание рельефа/фактуру/покрытия. Detail сохраняет
paint/flow/bed, coverage — heights/water; общий job/brush math/Plan и native
preview/Apply/Undo/Save/Discard PASS, clean exit. Builder тот же job, старый
остров не пересоздавался. Свои зоны/вид/input/weak PC OPEN — Terrain Authoring.
Coverage теперь имеет крупные зоны: размер/частота грунта, broad slope камня,
песок у текущей воды. Paint/selected-area locks в прежнем Plan10, одно Undo;
old recipes1–9/legacy readable, Source/detail/brush/session и native
paint/locks/stale/preview/Undo/recipe/Save/Reopen/Discard PASS, clean exit.
Старую покраску защитить выделением; свои вид/input/weak PC OPEN.
Роща/расстановка берёт smooth опору из общей математики; bounded fields,
physical/legacy/sections и native preview/Undo/manual/Save/Discard PASS;
своя посадка/input/weak PC OPEN. Проба — прежний smooth_tools8×8.
Volumetric Surface сохранён, его smooth вид отдельный; owners — Terrain Authoring.
Общая площадь smooth-карты ограничена отдельно. Новая проба —
`compact_meadow_anomaly_walk_study`:64×48м с явным study guard, поляна/гора
сбоку/речка/малый холмик, прежний Player/stepping/follow camera и local morph.
Standing/walking30/60/120Hz, ceiling pause, Source/paint/flow/reopen headless PASS;
native mound/continuous walk/ceiling PASS, clean exit. Smooth guard32×32 прежний.
Свои F6/вид/
ходьба/input/weak PC/large-world performance OPEN; owners — Terrain Authoring.
Общая форма: новые рецепты/локальные области используют fine16, старые без
параметра сохраняют GROUP8/height4. Гора получила массив с гребнем и плечами;
Plan11, прежние Source/кисти/покрытия/фактура/Undo owners. Проба 32×24м —
`compact_landform_fine_study`, рядом legacy-сравнение. Автору направление формы
понравилось; полный F6/input/performance gate OPEN. POM-стенд камень→песок готов:
`compact_material_depth_study` → F6/B,4см/32steps; Source/physics/QA/берег PASS.
Автор принял направление объёма; стыки/растяжение исправлены в общем texture
core текущего SurfaceMaterials. Native/GPU/две роли/связанные regressions PASS.
Последний вид стыков/проекции принят автором; input/движение/weak PC и close
budget OPEN; единая основа будущих материалов и границы — Terrain Authoring.
Контракт0а камера→шум→пропорции согласован; LAB готова к выбору камеры.
Рост героев сохранён; текущая точка — выше, у активной цели.
Передача: `C:/Users/novos/Documents/Codex/2026-10-12/new-chat-2/outputs/EMBER_HANDOFF_2026-10-13.md`.
Детали и ограничения — Terrain Authoring.

**Материалы земли — раздельные цвет/рельеф/матовость готовы к оценке.**
grass_impasto почти однотонен, выразительность от крупных гребней/света;
soil_grain — мелкое зерно с тихими коричневыми тонами. Прежние варианты сохранены.
Ближайшее действие: автору оценить мазки/зерно в движении/свете/near-far и швы;
галерея — art/references/surface-layers-20261009 (7 runtime+2 editor, ZIP).
Точка возврата: ground_finish_study → old/new grass/soil → F/G/L/ПКМ; та же панель
«Цвет → Рисовать паттерн…» → Цвет/Световой рельеф/Матовость → грань → Save.
Data/legacy/geometry/per-layer Undo/PNG/Save/Cancel/Reopen/3D/F6/PCK QA PASS.
Художественная приёмка/live mouse/швы/weak PC OPEN; owners/gates — Terrain Authoring.
Оптика: показанный вид четырёх профилей принят; отражения/движение/weak PC OPEN.
Возврат object_material_study → Inspector; pixelization трещин/пузырьков отложена.
Прежние stamp/editor-close gates OPEN; QA одна сцена/30 FPS, новых TDR нет.
Авторский свет воды сохранён; погода/объёмный свет и полублоки/диагонали позже.

Точка возврата к большой карте: `Ember · Мир → Рельеф → План областей → + Объекты`.
Прямоугольный план принят; плато/озеро/гора/дорога/роща и смешанный набор до четырёх
готовых native объектов имеют QA, авторская приёмка типов/соседства OPEN.
«Равномерно / Группами», кучность и масштаб группы реализованы в placement;
headless/native/F6 PASS, авторский рисунок/удобство OPEN. Owners — World Authoring.
B — плоская листва большого дерева, размеры 8×4×8/4×2×4: родной генератор готов;
свой вид/Save/Undo/reopen OPEN. C и гладкое дерево — лаборатория; owner/gates — World Authoring.
Ориентир острова 256–512 м, рост по замерам. Terrain/water activity/cache/LOD QA
не закрывает авторский F6 near/far/стыки, weak PC, release .exe/512 м и editor lag.
Runtime jobs не возвращать на brush input; sleep/streaming не начаты.
Длинная GPU-диагностика отложена автором; причина прежнего TDR OPEN. Текущая
QA одна сцена/30 FPS, новых TDR нет; рабочий редактор/авторские сцены не менялись.

## Точки возврата к отложенной приёмке

Материалы — scenes/compact_material_light_study.tscn и *_relief.
Первое действие: «Вид мира → Материалы», сравнить три вида света, повернуть Sun/
камеру, проверить серый цвет и стыки; сохранённый выбор наследует F6.
QA сохранения/Forward+ прошла; художественная оценка, фактура/швы и слабый ПК OPEN —
Terrain Authoring / «Материалы и рабочий интерфейс».
Вода — scenes/compact_sky_reflection_study.tscn: подход 6/20, sea foam/trails,
волна и солнечный блик OPEN; подробности — Water Rendering.
Точка возврата к обтеканию — scenes/compact_wave_obstacle_study.tscn: сравнить
запечённый/живой режимы, пену/границу участка и стоимость на слабом ПК;
ручная приёмка прежнего среза остаётся открыта.
Точка возврата к водопаду — scenes/compact_waterfall_study.tscn, оценка верхних
полос/струи с разных сторон и скорости; живой Ctrl+S/Reopen/Discard остаётся открыт.
Полировка морских разводов, небо/погода и перенос эффектов на все карты позже.

Маршрут к owners и подробным gates — docs/README.md; очередь —
EMBER_PRODUCT_PLAN.md и EMBER_WORLD_AUTHORING_ARCHITECTURE.md.

## Точка возврата к инструментам

Живая опора остаётся открытой; при работе с адресными участками проверить:
живые кисти, создание/расширение, материалы, объекты и Save/Reopen/Discard.
Общие кисти, параметры и наведение приняты; ещё открыты оба следа/каналы,
полный цикл сохранения, узкое окно 1280×720/125%, паттерны/швы, повторный кэш
миниатюр, плавность создания/расширения и самостоятельная оценка открытия карты.

Первое действие возврата: выбрать один незакрытый сценарий на текущей
landscape_compact или тестовой 4×4/5×4 карте, сверить раздел темы и его gate.
Детальная ручная приёмка и измерения — в тематическом входе и MIGRATION_TEST_PLAN.md.
Генератор не закрывает эти gates; порядок — World Authoring Architecture.
Исследование по запросу 2026-10-12 — World Authoring → «Исследование внешних
редакторов»: отдельная лаборатория WGEN/WorldPainter/Terrain3D; первый срез — группы.
Комплект и общий CLI/API запускатель проверены; рабочий режим — скрипты без GUI.
Agent Sandbox после приёмки; Test Pier не переносится автоматически.

## Другие незакрытые направления

- Группа 1–4: одиночка/пара, бой, Retry и save/load ещё требуют ручной приёмки.
  После группы следующий игровой контракт — редактируемые квесты, действия и
  сценки канонического graybox; игровые условия сохраняются по GDD.
- Будущие арены: compact-декор допустим, Battlefield остаётся owner клеток/hitbox;
  боевые Resources этим документационным срезом не менялись.
- Масштаб заглушек: 1 блок = 1 м, Мира 1,5 блока, остальные 1,7–1,8;
  живой масштаб и проходы под препятствиями открыты.
- Мира: компактный чиби-ориентир принят; пробы — docs/art/characters/mira/drafts/,
  движение, край изображения и дальнейший риг открыты. Черновик не production-art.
