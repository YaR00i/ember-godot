# Ember — текущая точка

Актуально: 2026-10-13. Ветка: codex/runtime-water-region-activity.
Локальная база кода/Resources/сцен/тестов — 6124184; мир/материалы — 0a7e1c5.
Настройки/наборы Lab, полный цикл, переходы, арена, условия и Старт игры сохранены;
открытые ручные gates прежние. Документы входят в текущий checkpoint.
Origin после fetch — fbd5478, до checkpoint расхождений не было; push не выполнялся.
Арт/локальные файлы остаются на местах; точный архив всех 1046 изменённых/новых
файлов и SHA-256 manifest — `C:/Users/novos/Documents/Codex/2026-10-13/ember-material-depth/checkpoint-b7353afb/`.

## Активная цель

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
понравилось; полный F6/input/performance gate OPEN. Согласован следующий Sol-срез:
стенд4×4м камень→песок, optical relief/POM с отдельной height и прежней опорой;
ещё не реализован. Первый шаг — стенд A/B; контракт/границы — Terrain Authoring.
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
