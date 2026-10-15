# Ember — текущая точка

Актуально: 2026-10-15. Ветка: codex/runtime-water-region-activity.
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

**Пять пород — рабочие основы приняты; следующий срез ещё не начат.**
Дуб21/B/кора C, берёза22, вытянутый клён23 (широкий сохранён), саванна24 и ель25
имеют свою кору/листву в LAB. Пользователь принял последние кадры ели как основу.
Рекомендация следующего контракта — перенос оформления в существующий generator/
editor/save без нового renderer/редактора, сначала один вертикальный пример.
Общий план трёх обликов продолжается после закрепления authoring/save; камера0а
отложена автором, форма земли/общая кромка уже реализованы и имеют свои gates ниже.
Контракт переноса надо исследовать/согласовать; данная запись не разрешает его код.

**Ель25 — уплотнены верх и ярусы, кадры приняты как рабочая основа.**
По просьбе пользователя12 ярусов вместо9 в прежней высоте; вдоль лидера13 сайтов
хвои вместо11. Лапа/BranchLayout/PNG/свет B сохранены; прежний9-ярусный кадр — сравнение.
Те же Provider25/shape1/Recipe/SpeciesStudy owners: cap12 только25/shape1,
473 ветви/552 сегмента/85 опор; Source4d4733cf…;2166 full/1328 cards при60%.
Максимум12 tiers/splits3/levels4 укладывается в прежний лимит768 сегментов.
F6 compact_tree_spruce_bough_study: прежние7 shape controls, global/local/depth/
receiving/rim/history, лапа3 views и4 reference species. Save appearance transient LAB.
Проверены меньший max gap, больше верхней хвои, неизменная первая лапа и9-tier
Source007ce55b…, shape0 dfd9f454…, seeds/extremes/attachments/nested/zero/sample.
Recipe save/reopen/preview12→7/discard/reset/Undo/Redo/locality/cache/UI PASS;
день/вечер/ночь×side/back×tree/game и4 related regressions PASS.
15 protected SHA/ground/paint/grass/physics/POM4см сохранены; reference gate≤8px/max1RGB8.
Evidence C:/Users/novos/Documents/Codex/2026-10-15/ember-spruce-density/index.html.
Личный F6/motion и дальнейшая полировка OPEN; выбор последних кадров принят.
Owner/gates — Terrain Authoring → «Разветвлённая лапа ели25»; предыдущая проба —
ember-spruce-bough/. Production appearance save/ветер/LOD/forest/пикселизация вне среза.
Код/PNG сохранены в 41247dd. PNG inspected, HTML links/JS checked; browser render unverified.

**Точка возврата — саванна24 с мелкой листвой и покрытием кончиков.**
Общая/локальная плотность, ветвление и свет редактируются в прежнем LAB;
production-перенос сохранения листвы остаётся OPEN; текущий вид оставлен основой.
Shape1/низкая развилка/70 ветвей/20 опор и древесина сохранены exact; shape0 отклонена.
Свой PNG savanna_v1/leaf-atlas-v3-small-patches: маленькие округлые листочки,
спокойные поля/прозрачные каналы, built-in imagegen, полный prompt/SHA рядом.
Новые карточки распределены по объёмам ветвей: группы связаны с реальными побегами,
а сами плоскости заполняют опоры кроны, включая середину. Не меняют Source/schema.
Canopy-envelope opt-in только24/shape1; прежние карты/породы/шейдеры/свет B сохранены.
Текущая проба — 576 full/382 cards при60%, size1.05; на45 конечных побегах по3 малые
плоскости вдоль последних40% веточки, size×.65. Терминальные пучки имеют приоритет
в прежнем бюджете global/local thinning;0% по-прежнему убирает всю листву.
F6 compact_tree_savanna_leaf_study: принятый объём, новая листва,1/6-card sample;
справа прежние «Ветви»/«Листва и свет» с Undo/Redo, shadow40%,rim45/18%,reset.
SpeciesStudy.trial_card_options сохраняет envelope при Recipe preview/discard.
Native3 ракурса+верх,3 presets×side/back×tree/game,60/80 density и1/6 samples PASS;
принятые3 дерева/саванна blockout frame exact. Source b2c04fd0…, дерево и collision exact.
Preview/discard и density reset frame exact; controls/locality/cache/stale-history/
Undo/Redo/UI fit PASS. Save/reopen Recipe+те же LAB options повторяют full cards.
После правки — canopy/species/foliage21 regressions;7 protected SHA/floor/paint/
grass/physics/POM4см PASS. Шесть прежних регрессий листовой пробы сохранены.
Evidence: C:/Users/novos/Documents/Codex/2026-10-15/ember-savanna-tip-cover/index.html;
проба до покрытия кончиков сохранена в соседнем ember-savanna-leaf-patches/.
Owner/границы — Terrain Authoring → «Саванна24», мелкая листва. Ближайший gate —
личная F6/motion-проверка и возможная дальнейшая полировка саванны.
Форма/дуб/берёза/оба клёна сохранены; источник/генератор/общий shader прежние.
Foliage/light settings transient LAB; production save transfer/ветер/LOD/forest/
tree collision/пикселизация вне среза. Без агентов/branch/commit/push.
PNG просмотрены, HTML links/JS проверены, browser render не проверен.
Перенос кромки в WorldLook/Pattern/model.material завершён; workflow/9 regressions
и24 LAB→saved сравнения PASS. Свой editor input/125%/Save→F6/motion/weak-PC OPEN.
Точка возврата — Terrain Authoring → «Передача общей световой кромки»;
evidence ember-style-rim-transfer/. Рябь/избирательность внутренних теней прежние.

**Точка возврата — локальная плотность и глубина тёмных участков Sol.**
Пользователь выбрал45% пучков как ориентир, позиции подходят, нужно меньше местами.
Foliage21Study стартует trial5: общая плотность45%, принимаемые тени40%, depth100%
(low0.24). Выбор одной из8 частей показывает рамку, F1 скрывает её вместе с UI.
«Пучки в выбранной части»0–100% — множитель общей плотности, целые branch+t пучки.
Пример Часть8 справа/owner67/local50%:399→380 пучков,885→843 cards;
все другие части/positions/UV/colour/custom macro normals прежние.
BranchingFixture owns crown_leaf_groups + optional local_coverage в derived thinning;
Foliage21Study owns UI/cache. Release/Enter/focus commit once, no per-drag rebuild;
повторный набор использует тот же mesh. Новый branch preview очищает local overrides.
Local/depth/reset Undo/Redo uses existing RecipePanel.history, Recipe.parameters прежние.
Сброс частей/света возвращает local100% и depth100%, общую45% сохраняет.
Глубина тёмных участков100/60/25% → existing leaf low0.24/0.544/0.81;
меняет только градацию формы, не выключает исключительно взаимные тени.
Shader/common light/texture/cast mode/receiving strength0.4/Sun/AO прежние.
Внешние и наземные тени сохранены; local thinning естественно меняет тень кроны.
Native3 presets×side/back×tree/game/near/far/side/back/motion, drag/one build/cache/
Undo/Redo/reset/F1/zero-Sun/external blocker/ground guards PASS. Fixture local-only/
nested/whole-puff/repeatability и foliage21/parametric regressions PASS.
Current baseline/control-return/post-blocker frame exact; post-blocker gate допускает
max1 RGB8 level/≤128 pixels (в текущем прогоне0). Source/full geometry/wood/Recipe/
terrain/paint/grass/physics/POM и22 protected files exact; last one-shot thinning60ms,
не цена полного генератора/леса. Личный F6/selection/sliders/history/edge/motion gate OPEN.

Для отдельной оценки локальных правок:45% + local50% правой части + depth60% при3 пресетах.
Точная избирательность внутренних теней остаётся отдельным решением: ATTENUATION
не сообщает caster. Как у травы cast OFF убирает также тень кроны на земле;
receive0 игнорирует внешнюю тень. Рябь shadow map не объявлена исправленной.
Кучность частично fixed2–3 cards/site; отдельного распределения по пятнам пока нет.
Производственный editor/Recipe/save transfer, view clipping/wind/LOD/атмосфера не начаты.

Форма каркаса21, спокойная листва B,45%, кромка и кора C приняты основой. Локальные
варианты плотности и личный F6/motion остаются OPEN. Historical materials доступны,
full Source seed7/main8/splits3/levels4/variation40 и1967 cards/23604tris сохранены.
Existing LargeTreeProvider/BranchLayout/Recipe/GeneratorPanel owners, версии1–21,
голый21/count/editor/Undo/save gates прежние; старые19 buffers точные.
POM4см/32steps, трава6187, ручная покраска и единая физическая поверхность сохранены.
Atlasv8 separate leaves/alpha-safe mips на filtered sampler; default дубовая кора C,
прежняя v4_soft доступна через отдельный LAB-переключатель. Берёза имеет свой атлас.
Старая оптикаv7: saturation1.18/transmission0.28/rim0.23, пять стадий/ползунки доступны.
Плоскость/группа1/6 cards и их независимый sample stage2 сохранены; новые tree controls
в gameplay Resources не записываются. Основная игровая камера/этап0а прежние,
в её текущем кадре часть кроны обрезается: это не принятие камеры.

Evidence — C:/Users/novos/Documents/Codex/2026-10-15/ember-tree-leaf-local/;
предыдущие density/shadow/full-tree trials — ember-tree-leaf-density/,
ember-tree-shadow-modes/, ember-tree-leaves-40/; ранние samples/диагностика/референсы
сохранены и перечислены в Terrain Authoring → «Исследование рисованной листвы».
Owner/контракт — Terrain Authoring → «Построение дерева»; tree-gen/MIT — THIRD_PARTY_NOTICES.
Полный authoring B/tree collision/forest/weak-PC остаются OPEN; кромка перенесена.
Без агентов/commit/push; чужие незавершённые файлы сохранены.

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
Low-poly геометрия, pixel-art перерисовка, большой world foliage и цикл суток не начаты.

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

**Общие игровые системы — единый «Старт игры» готов, ручная приёмка OPEN.**
Раздел библиотеки: четыре вкладки героев, уровень 1–99/пять слотов, общая сумка
с предметами/монетами. Одна GameStart recipe; stats/progress у Party/ExploreState.
Применяется только к новой игре: XP0, полные derived HP/MP. Надетые вещи выдаются
отдельно от сумки. Исходный default прежний: level1/empty gear/20 coin.
Save/reopen/Undo/Redo/Discard/validation/UID, singleton guards и links готовы.
Невалидный reset не трогает live progress; invalid boot без пригодного save —
нейтральная сессия с disabled persistence. Save v2/load/migration не менялись.
Targeted/native Forward+ и три процесса author/new game/battle/result/fresh Load
PASS; checker 72 records/0 issues, save/combat/party/interactions regressions PASS.
Ближайшее действие: свой комплект → Save/reopen → новая игра/старый
Load/обычный бой, Undo/Discard/input/narrow/125% OPEN. Owners/gates — Handoff/Plan.
Приёмы: статус/HP/MP/надетый предмет/слот занят или пуст, все условия «И»;
bag не считается. Action Resource → единый conditions leaf/Combat/Grid/AI/HUD.
Empty defaults сохраняют поведение; CELL actor-only, SELF merge, exact percent,
conflicts/stale commit проверены. Свои условия/объяснения/input OPEN.
Следующие отдельные срезы: periodic/stacks/OR при необходимости, свойства обуви.
Авторский контент сохранён; commit/push нет. Первый editor Lab child не подтвердил ready;
последовательный повтор и full cycle PASS, причина отказа/свои launch OPEN.
Прежний publication 0xC0000005 trigger устранён адресным Filesystem update;
12 rapid/sequential native cycles PASS, свои повторные Save/Undo/Redo/reopen OPEN.
Точный C++ frame/dump и общая GPU stability не доказаны; детали — Handoff.
Выбранная арена/наборы Lab/«Где используется»/формы/примерка готовы. Ordinary battle
Retry/Load/re-entry/победа/rewards once/возврат/fresh Load PASS. Свои арены/наборы/
saves/narrow/125%, old Load/Save и backup экипировки OPEN. Library test изолирован.
Возврат — свой authored encounter из карты и набор; подробности — Handoff/Plan.

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
