# Ember — текущая точка

Обновлено: 2026-09-15

## Художественный свет и материалы — отдельная графическая задача

По явной просьбе пользователя создана отдельная задача
«Ember — художественный свет и материалы» с ролью graphics designer / technical
artist. Это не смена координатора редактора. Переданы три пользовательских
pixel-art референса: мост/кот, сад у воды и крупный вид тёплых досок.
Направление: тёплый свет, прохладные цветные тени, крупные спокойные пятна под
кронами, читаемые материалы и согласованная вода без нового мелкого шума.
Первый результат — один законченный эталонный уголок и реальные Forward+
снимки до/после, затем проверки полного холста, Причала и ночного света.

Графическая задача `01a0a187-0fc9-7a03-ab0b-ba17e686e6c7` завершила реализацию
и автоматические проверки в отдельном worktree `d97c`, вернув управление
основному координатору. Текущие незакоммиченные
WorldEditor/WorldCanvas изменения доступны ей read-only в основном checkout;
render fixtures создаются в собственной disposable копии с наложением только
graphics diff. Основной checkout, авторские Source/сцены, palettes/Recipes,
editor/Save/Undo/brushes/physics остаются вне её области записи.
`ember_map_loader.gd` уже изменён редактором. Согласован только точечный вызов
existing EmberLights helper в `_tune_look_environment`, с возвратом отдельным
snippet. Нельзя молча менять scene-owned Environment/Sun storage fields:
in-place правка в @tool может попасть в штатный Save даже без прямого Source
write. Guard/idempotence/night и неизменность authored полей при pack/reopen
обязательны и прошли в fixtures. Основной координатор проверил состав handoff,
однострочный loader diff и финальные логи: 11 targeted headless gates PASS,
native pixel/storage/lifecycle/save-reopen PASS; финальный source hash gate
подтвердил неизменность 429 scene/source/prefab файлов. Подготовлены 38 native
viewport PNG. Холодная ночь и FanTown8/12 в парных fixtures побайтно прежние.
Передача: `C:/Users/novos/.codex/worktrees/d97c/ember-godot/art/lighting/HANDOFF.md`;
семь production files, отдельная строка loader и только помеченные graphics
секции документации. Полный старый loader/docs не заменяют main dirty work.
Реальная PCF penumbra/просветы кроны не добавлены; stair side faces берега
остаются. GPU timings — viewport proxy, не доказательство FPS/оптимизации.
Commit/push и автоматический перенос результата в основной checkout не разрешены.
Ручная художественная приёмка открыта до возвращения пользователя.
Генерация карты по зонам моря/рек/дорог/домов остаётся отдельной будущей идеей,
не входит в графический срез. Основной агент не ведёт параллельных code writes.

В той же графической задаче пользователь отдельно согласовал библиотеку
материалов и нативный стенд: матовая поверхность, дерево, камень, земля/песок,
просвечивающая листва, металл, стекло, кристалл и свечение. Реализация и
автоматические проверки этого нового среза завершены в `d97c`; основной
координатор прочитал отдельный `art/materials/HANDOFF.md`, просмотрел дневной
native стенд и проверил финальные логи. Library validation/independence/custom
save-reopen для девяти presets PASS, native day/night/backlight/alpha-depth/
emission/specular/transmission PASS, четыре связанные regressions PASS.
Source guard: 429 прежних файлов побайтно сохранены; добавлена только owned
stand scene. Шесть предыдущих lighting/water PNG совпали побайтно; прежние
lighting handoff/38 PNG не заменены. Библиотека зависит только от неизменного
`ember_diorama_light.gdshaderinc`; параметры пока хранятся в ShaderMaterial,
не в per-voxel preset IDs. Main integration и ручная art/input приёмка открыты,
commit/push отсутствуют; предыдущий кандидат света также ждёт ручной приёмки.
Назначение объектам/вокселям, editor Save/Undo и изменение Resource/
mesher/schema исключены; подключение к редактору требует отдельного среза
основного координатора. Presets переиспользуют общий свет, не меняя defaults
прежних voxel/water materials. Вода и расширение набора обсуждаются после
библиотеки. Основной checkout остаётся read-only для графической задачи.

Пользователь затем согласовал refinement библиотеки: GGX highlights,
контролируемый цвет/перелив кристалла, слабая фактура color/roughness/normal и
отражение окружения на disposable стенде. M02 реализация и material/storage/
compatibility gates завершены; основной координатор прочитал отдельный
`art/materials/refinement/HANDOFF.md`, проверил финальные логи и дневной native
снимок. Новые controls/custom save-reopen/independence PASS; native GGX/tint/
angular spectrum/reflection/weak texture/independent relief/alpha/emission/
transmission PASS. Четыре related regressions PASS; 429 прежних Source файлов
и шесть старых corner/day/night/Pier PNG побайтно прежние. Подготовлены 18 M02
PNG, отдельный patch/docs excerpts. Первый M01 snapshot сохранён отдельно в
`art/materials/checkpoint-m01/.gdignore`; прежние QA/handoff не перезаписаны.
Native isolation Godot4.7.2: без ReflectionProbe shutdown log чистый; с одним
probe — предупреждение 7 Texture RIDs при finalize, соответствующее открытому
Godot issue https://github.com/godotengine/godot/issues/122498. Это shutdown
diagnostic, не измеренная live-editor VRAM accumulation. Движок не обновлять/
не патчить, warning не маскировать; production probes/editor/water вне среза.
Library presets probes не создают. Native комбинированный reflection test
с двумя atlas даёт 14 Texture RIDs warning; это НЕ clean lifecycle PASS.
Cleanup limitation учитывается отдельно от material/storage/compatibility
PASS при интеграции. Main integration, art/input и shimmer на authored формах
OPEN; редактор/вода/production probes/engine fix не начинались.

После M02 пользователь отдельно согласовал W01 воды в graphics `d97c`:
спокойная стилизованная поверхность, smooth normal ripples без изменения уровня,
настоящие sky/environment reflections, light/view-driven highlights и более
прозрачное мелководье. Срез начат в existing water shader/material/QA с отдельным
pre-W01 checkpoint. Source/editor/schema/mesher/physics/main не менять; Sky/
ReflectionProbe/specular lights только disposable QA, production интеграция
среды/света отдельно. Проверить authored WorldCanvas/Pier и QA reflection stand
раздельно, стыки/global field/пену/alpha/объектную воду/день-ночь и движение.
Прежние water PNG служат baseline, не требование byte-identity нового вида;
lighting/M01/M02 checkpoints и исходные файлы остаются защищёнными.
W01 реализация и автоматические gates завершены; основной координатор прочитал
`art/water/HANDOFF.md`, проверил финальные логи и лично сравнил authored Pier
до/после плюс кадр motion stand. 10 headless gates PASS; native material
Sky/shallow-deep/reopen, Surface adapter-v-stock, object motion и split/noise
continuity PASS. 429 canonical Source файлов сохранены, 18 non-water render
files одинаковы, все 12 M02 material PNG повторно побайтно прежние. Подготовлены
89 PNG и GIF из 48 реальных кадров/12fps; это QA-среда, не gameplay FPS.
Production diff: existing water shader/.tres; отдельный targeted seam diagnostic
и новые QA tools/patch/docs excerpts. Ручная art/input приёмка и main integration
открыты. Authored no-Sky/no-probe карты не получают отражения окружения молча;
production Sky/probe/light_specular — отдельное решение владельца карты.
Known one-probe shutdown 7 Texture RIDs warning и fragment ObjectDB diagnostic
оставлены явными, не включены в clean lifecycle PASS. Commit/push отсутствуют.
Пользователь посмотрел W01 и отметил, что вода выбивается из pixel-art стиля.
W01 НЕ финальный принятый визуал для интеграции. Graphics пересмотрел рефы и
обсуждает более графичную воду: спокойная garden/boards база, ограниченные
bridge accents, ясные бирюзовые зоны, broken light-driven glints и упрощённые
низкоконтрастные отражения. Направление следующей итерации ещё ожидает согласия;
нового кода нет, W01 baseline/QA/patch сохраняются.
Последующее уточнение пользователя: движение/переливы W01 нравятся; сохранить
их, пикселизировать отражения/блики и сделать цвет бирюзовее. Ориентир движения
— пляжный курорт ZZZ, не полная замена воды рисованными штрихами. Native A/B
W02 native A/B завершён: 1/2-voxel cells optical normal с плавным временем/
alpha/VIEW и смягчением мелких деталей вдали. Основной координатор прочитал
`art/water/pixel/HANDOFF.md`, проверил финальные логи и game/wide fine кадры.
11 headless и 5 native gates PASS, 429 Source bytes сохранены, 18 owned
non-water files одинаковы, incremental patch/checkpoint/docs готовы. Есть
11 GIF по 48 native кадров и camera-motion strips. На широком плане прямой
солнечный рисунок плотный/повторяющийся; это открытое art-решение, не повод
молча менять wavelength/свет. Визуальный выбор fine/coarse не принят,
main integration OPEN; известные shutdown diagnostics сохранены отдельно.
Source/editor/schema/mesher/physics/foam/wakes не менять; production environment
integration OPEN. Пользователь хочет иногда плавать между островами — будущий
игровой ориентир, не реализованная механика и не основание расширять W02:
плавание/след/refraction в этот срез не входят.
W03 graphics продолжил тот же water owner после прямого уточнения пользователя:
цвет заметно бирюзовее, поверх W01/W02 добавлена тонкая движущаяся светлая сеть,
которая художественно показывает грани волн. Это ALBEDO-рисунок поверхности,
не физическая каустика на дне; geometry/collision/body emission не меняются.
Основной координатор прочитал `art/water/flow/HANDOFF.md`, проверил 12 headless
и 6 native PASS logs и лично посмотрел close/wide кадры. 429 canonical author
Source bytes сохранены, 18 non-water graphics files одинаковы, incremental
patch/checkpoint/docs готовы. На близком плане сеть читается; на расстоянии/
глубине намеренно исчезает. На широком прямом солнце прежние плотные белые
W02 reflections всё ещё требуют art-решения. Main integration, ручная приёмка,
реальные bottom caustics/refraction/swimming OPEN; commit/push отсутствуют.
W04 по запросу пользователя подготовил native A/B трёх независимых water
light-play branches: sparse pixel highlight, hard directional shadow shaping и
shallow screen/depth refraction + caustic light play. Все mix в canonical .tres
равны 0: W03 сохраняется bit-exact до художественного выбора. Основной
координатор прочитал `art/water/lightplay/HANDOFF.md`, проверил 13 headless и
7 native PASS logs и лично посмотрел current/sharp/shadow/caustics/game кадры.
429 Source сохранены, 18 non-water files одинаковы, W03 checkpoint/hash и
isolated import PASS; пять GIF по 48 Forward+ кадров готовы. Sharp блик стал
разбитым на пиксельные кластеры, но вблизи остаётся плотным; подводная игра
света screen-space и на одном кадре тонкая — оценивать в движении. Это не
физическая проекция света в материалы дна/volume/refraction gameplay. Art/
main-map/input acceptance OPEN; main checkout/commit/push не затронуты.
После пользовательского фидбека W04 review2 убрал random hash-крошку из блика:
теперь это цельные двухступенчатые optical world-cells. Тень получает snapped
LIGHT_VERTEX и ступени ATTENUATION; QA pier поднят над водой для читаемого
силуэта досок/опор. Основной координатор лично посмотрел review2 sharp/shadow/
caustics/game кадры и проверил отдельные 7 native + 13 headless PASS logs.
Белых пикселей >240 стало 19181→2245; W03 checkpoint и canonical mix=0
сохранены. Новый блик значительно чище, тень причала читается и не привязана к
анимации воды. Важная граница: чистый пиксельный край тени в QA использует
глобальный RenderingServer SHADOW_QUALITY_HARD/zero angular distance. Runtime/
project setting не менялся; принимать hard shadows нужно отдельно для всей
сцены, а не скрыто внутри water integration. W04 art acceptance OPEN.
Review3 по уточнению пользователя сохраняет крупные clean highlights review2,
но добавляет регулируемую cohesion0..1: соседние world-cells и близкие phases
поддерживают связную середину блика без history buffer/нового owner. Основной
координатор просмотрел кадры0/12/24/36: форма заметно спокойнее и реже рвётся.
После запроса на durable evidence сохранены и лично проверены отдельные логи:
connected-vs-sharp native response, cohesion0/default, clone/save/reopen,
pixel-exact review2 control с одинаковым SHA256, 429 Source guard, 18 non-water
guard, W03 checkpoint/package/reverse-patch и clean audit9 логов — PASS.
Исходный review2 при cohesion0 неизменен; W03 canonical defaults/global shadow
settings/main checkout/commit/push не затронуты. Review3 art confirmation OPEN.

## Холст мира — отдельная основа для следующей UX-итерации

По согласованию добавлена `scenes/world_canvas.tscn`:24×25blocks/16vox,
свободная суша слева, изогнутый песчаный берег, пологий спуск132vox,
мелководье и дно до−20world units; уровень воды0, Surface origin−32.
Одна обычная `content/world_surfaces/world_canvas_surface.tres`; никаких
дублирующих water planes, сохранённых mesh/physics или декоративных объектов.
Причал и его авторская Surface не заменялись. Main scene проекта прежняя.
F6 продолжает существующий play controller с изолированными `user://` saves,
дожидаясь готовности Surface physics до spawn. Пустая Props больше не вызывает
legacy reimport при наличии валидной сохранённой общей Surface.

Проверка существующей загруженной карты выявила и исправила Surface publication
cache: IGNORE-loaded Resource очищает path перед takeover и удерживается как
новый canonical cache identity, без in-place изменения baseline.
World water input теперь следует существующей fill schema (boundary level,
не top-voxel index): sea0→fill32 при origin−32. Старые authored fill arrays
не мигрируются. tools/test_world_canvas.gd PASS: пологий профиль, реальные
floor rays/spawn, стена, seam brush/cancel/Undo, повторный Save/reopen с кэшем.
Disposable native Forward+ PASS с настоящим Ctrl+Z через native input;
обход глобальной redo stack прямым per-history undo исключён из нового fixture.
Выбор рабочей области читает footprint из size_blocks общей Surface;
проверка native frame PASS. Первичная сборка полного холста≈12s, общий map Save
≈2.2–2.9s в fixtures. Standalone Forward+ overview и прямой снимок нативного
3D render target просмотрены; background window composite был устаревшим,
это не исчезновение Surface. Наведение камеры остаётся ручным gate.
WorldEditor/SurfaceProjection/native water/Canvas workflow/TestPier PASS.
UX интерфейса пока не менялся; следующая приёмка — открыть холст в3D, посмотреть
масштаб, берег/воду, попробовать кисти и подтвердить основу.

## Редактор мира в 3D — реализован, ручная приёмка открыта

Пользователь утвердил полный план «Редактор мира Ember прямо в 3D». Добавлен
нативный режим «Редактировать мир»: земля карты / индивидуальный voxel-объект,
форма, покраска стенок, сглаживание, берег/дно, генератор, открытая вода,
мягкое вытягивание, существующая кисть объектов и editor-only избранная полка.
Canvas и 3D используют тот же Resource-черновик и историю текущей сцены;
переключение инструментов и возврат в 3D ничего не публикуют на диск.

В авторский Причал новая земля автоматически НЕ добавлялась. Пользователь
выделяет прямоугольник строительной плоскости и нажимает «Создать землю».
Общая Surface имеет весь размер24×25,16vox/block,128vox по высоте и
`Map.surface_origin=(0,-32,0)`. Основание заполняется только в пустых колонках
выбранного участка; существующие объекты, вода и физика Причала сохраняются.
Радиус карты1vox–8blocks. Остальная новая Surface пуста и доступна кистям.

Общий Save проверяет все черновики текущей сцены, публикует source/prefab/сцену,
при ошибке восстанавливает точные файлы и сохраняет несохранённые черновики.
Обычная кнопка/Ctrl+S используют штатный scene Save; external-data hook меню
завершает обновлённый native PackedScene без повторного EditorInterface.save_scene.
Recovery — только `user://ember_world_drafts`, с проверкой внешних файлов.
Мазки хранят sparse packed deltas; обновляются затронутые mesh/physics-фрагменты
и соседние границы. Для навеса/пустоты новой земли физика использует точные
voxel faces в существующем SurfacePhysics; обычный берег — прежний heightfield.

PASS: tools/test_world_editor.gd + связанные Canvas/object/water/projection
regressions; disposable native Forward+ на полном Причале — общая история,
shared Canvas, индивидуальный объект, общий и штатный menu Save/reopen,
наличие коллайдера новой земли при сохранённой StoneQuay physics.
Профиль CPU fixture: source19,660,800B; radius64 calculation≈0.66–0.82s,
packed voxel payload2,589,192B; retained history≈4.53MB; региональное обновление
одного voxel на границе:3 visual≈38ms +3 physics≈27ms. Native общий Save≈11s.
Это не FPS и не гарантия для полностью заполненной карты/максимальной кисти.

Ближайший шаг — ручной полный сценарий из MIGRATION_TEST_PLAN: берег/песчаные
стенки/вода/повторная расстановка/изменение одной доски/возврат к земле/Save/reopen,
затем камера/F, Save/Discard/Cancel при закрытии и игровое движение F6.
Контракт до этой приёмки НЕ закрыт. Commit/push этого среза не запрошены.
Авторские scene/art/config правки не перезаписывались.

## Предыдущий checkpoint оптимизации

Git: checkpoint оптимизации и исправления Ctrl+S запрошен пользователем 2026-09-14.
Commit: `perf(editor): optimize startup, voxel workflows and fix scene save crash`.
Базовый checkpoint — `94ec785`; авторский Причал с двумя проверочными объектами,
художественные черновики и локальные настройки Codex остаются вне этого коммита.

Ctrl+S crash2026-09-14: пользователь сообщил вылет после размещения двух
`ember_surface_pilot` с водой в Причале. В disposable Forward+ копии вылет
воспроизведён обычным native Ctrl+S даже до размещения новых объектов. Причинный
переключатель в проверенном сценарии — удаление завершённого окна подготовки:
оно теперь скрывается, снимает exclusive/transient, освобождает shelf/filesystem
references и остаётся одним неактивным controller до plugin._exit_tree.
Загрузка/миниатюры, scene/model owners, данные и Save/Undo pipeline прежние.
Readiness/error/timeout/exit + inactive-window/repeated-finish guard и library
updates PASS. Native Ctrl+S:3 saves Причала → place2 water prefabs → Undo/Redo →
4th save → reopen retains2 water objects PASS, editor closed without crash.
Inherited get_node outside-tree/scan-aborted teardown diagnostics retained;
точная C++ причина и связь с прежним generator teardown crash не доказаны.
Ручная приёмка исправления вылета при Ctrl+S закрыта 2026-09-14: пользователь
подтвердил результат ответом «отлично».

Генераторы/точный prefab-предпросмотр2026-09-14: следующий срез согласован
(«ок, работает. давай далее») и реализован. Existing VoxMesher._build_culled
пропускает целиком пустые X-строки через packed-array scan и hoists row index;
y/z/x face order, соседняя окклюзия, palette/alpha, collision и shader-space прежние.
Provider/recipe/Resource/Creation/GenerationSession/UI не менялись; no greedy
replacement, second renderer, async lifecycle или persistent cache added.
Matched one-process/alternating order/2 repeats ×5 latest tree types,128 vox,seed371,
cloud foliage: exact prefab means0.748–1.487→0.431–1.060s;29–44% less wait,
all10 visual arrays/names and collider faces exactly equal. Source generation
0.113–0.666s measured separately; not a whole batch/FPS/general-tree guarantee.
Large-tree64/128/256, generation session/editing/workshop save, projection cache
(sparse edges/slab boundaries/alpha), object Canvas, shapes, cartoon water/world
projection PASS. Native editor full generation workflow PASS twice with current
code; first run crashed after PASS during teardown, baseline and repeat closed
without crash (repeat preview pending0). Cause unproven, logs retained; no blanket
clean-shutdown claim. Генераторный срез принят пользователем2026-09-14:
«окей работает». Ручная приёмка обычной работы генераторов закрыта;
причина отдельного сбоя тестового редактора при завершении остаётся неизвестной.

Ускорение подготовки2026-09-14 согласовано («давай») и реализовано. Existing
Catalog/Visuals берут native identity/grid metadata без to_definition/разворачивания
dense geometry; default full definitions и legacy import остаются прежними.
Existing PreviewRenderer заранее грузит максимум2 PackedScene tokens, рисует
по одному в прежнем SubViewport. Cancel/exit освобождают все prefetched tokens;
replacement revision ждёт потребления старого same-path token. В копии Forward+
редактора с8 restored tabs/247 previews gate28.379/29.039→24.301/22.729s;
mean28.709→23.515s (≈18%); последний matched repeat29.039→22.729s. Shelf open
0.421ms,pending0,0 failures. Candidate4 был хуже в полном редакторе и не принят;
его standalone8.139s не является замером текущего cap2. Metadata/full-catalog
parity, library publication/layout/readiness и native preview pixels/cancel/
requeue/pending invalidation/exit/shared-path disposal PASS. Восстановление сцен
Godot и source-file parsing остаются затратными; no cold OS-cache/total-startup/
memory/FPS guarantee. Startup принят пользователем2026-09-14: «ок, работает».
Подтверждена работа после обычного открытия проекта; regression gates PASS.
Генераторный срез реализован и принят пользователем; подробности выше.

Save/Undo memory optimization2026-09-14 согласован и реализован. Existing
ObjectSession/ModelStore сохраняют source/prefab и node snapshots; независимый
baseline rebuild/проверка внешней геометрии сохранены. Undo assets используют
ZSTD-снимки точных опубликованных .tres/.tscn bytes в памяти; повторный Save той
же сессии переиспользует проверенный предыдущий снимок. Unknown/reopened baseline
сохраняет старый prepared fallback. UID staging обновляется streaming header,
body verbatim; atomic publication/rollback/UID/cache/SceneState сохранены.
Matched192×10×256 object, один headless process/3Save per mode: warm4.999→3.967s,
cold6.508→5.489s; Undo3.674→2.030s, Redo3.679→2.074s. History growth166.65→85.01MiB
за повторный Save; snapshot≈1.28MiB. Это CPU/static memory fixture, не FPS.
Snapshot integrity/exact bytes/UID/cache/rollback/2MiB UID body, object Canvas,
library updates, shapes, scene refresh, growth, assembly/context PASS. Disposable
native editor shared Save/Undo/Redo/editable descendants/save/reopen/rollback PASS.
Manual acceptance OPEN: обычный объект,2–3Save, Undo/Redo, linked/selected identity,
save/reopen/discard и F6 collision. Versions needed for Undo still retain geometry;
no history depth limit added. Catalog/startup и generator ускорены выше.

Water chunk optimization2026-09-14 согласован пользователем и реализован.
Shared `EmberVoxelNativeMesher.build_surface_region` обслуживает Canvas и
world/battle: native opaque terrain + прежние Surface water/foam. Для мокрого
чанка greedy terrain vertices переводятся в full-map block coordinates;
identity visual transform сохраняет MODEL_MATRIX scale воды и local VERTEX пены.
Dry/slice, draft и stock fallback сохранены; schema/shaders/physics/авторские
scenes и Resources не менялись. Matched Forward+ Canvas before/after из94ec785,
один процесс/чередование порядка/7warm repeats: wet median16.975→6.173ms (2.75×),
dry4.704→4.382ms; это CPU build данного чанка, не обещание FPS всей карты.
Native Surface water geometry/face-area/colors/offsets/shader-space/fallback PASS;
Forward+ frozen water/foam:0different pixels,8171visible pixels vs empty control.
Canvas workflow, height slice, world projection, sculpt, contact boundaries,
cartoon water, projection cache, native backend и GPU water seams PASS.
Ручная приёмка OPEN: берег/вода через чанки, draft→pointer-up, bottom-only/slice,
Undo/Redo, save/reopen/discard и F6 movement/contact. Save/retained-memory
срез реализован выше. Подробности/gates в handoff и MIGRATION_TEST_PLAN.

Оптимизация запуска2026-09-14: пользователь уточнил лаг при открытии проекта
в Godot и согласовал подготовку до начала работы. Implemented native
«Подготовка Ember…»: ждёт filesystem scan/import и восстановления сцен,
затем catalog +245 preview textures и pending Surface projection; editor input
закрыт modal Window до готовности. Existing shelf/renderer/SubViewport/Resources
сохранены. PackedScene files грузятся threaded, instantiate/render остаются main
thread; cancel/requeue и invalidation не публикуют устаревшие картинки. Чистое
открытие полки переиспользует catalog; publication/filesystem events помечают dirty.
Timeout120s/ошибка дают явное «Продолжить без готовых миниатюр».
Readiness/timeout/exit, publication updates/cache, layout и visual library PASS;
Forward+ preview pixels/cancel/requeue/invalidation/failed-file repair, renderer
exit during load/shared-path survivor и native error-window layout PASS. Queue
покадровая, без Node-bound await; abandoned loader tokens освобождаются без preview.
Четыре disposable editor-start прохода:245 thumbnails,0 failures, gate≈28s после
начала; последний frame-queue run:27.975s, открытие полки3.531ms,pending0. Это не обещание
общего speedup запуска: Godot restoration и большие instantiate всё ещё могут
паузы до ready. Агент не перезапускал рабочий editor; startup принят пользователем
2026-09-14 («ок, работает») после следующего ускорения, описанного выше. Water chunk
реализован выше; Save optimization также реализован отдельным срезом выше.

Новый checkpoint2026-09-14 запрошен пользователем: кусты, берег/дно/песок,
открытая заливка и мультяшная вода, включая сохранённый pilot source и derived
prefab/mesh. Commit title: `feat(editor): checkpoint bushes, coast and cartoon water`.
Последний рисунок воды принят («окей работает»): разрывы устранены integer hash.
Далее отдельный чат для аудита/оптимизации выросшего ember_import; текущий чат
сохраняется для следующего редактора карты. Новый чат сначала исследует owners,
замеряет горячие пути и согласует короткий контракт, без реализации во время
ориентации, без subagents/commit/push. Startup-срез выше реализован после согласования. Арт-черновики
Mira, PIXEL_ART_WORKFLOW/references и .codex/config.toml не входят в checkpoint.

Текущая проба2026-09-14: мультяшная вода по рефам4–5 — крупные движущиеся
цветовые пятна, независимые редкие короткие блики, слабая cell-сетка; тело
бирюзовое и заметнее прежней прозрачной плёнки, дно видно на отмели. Existing
Surface water shader общий для Canvas/Surface projection/placed prefab и фона
test_pier (непрозрачный background mode). Prefab теперь добавляет explicit fill
через SurfaceMesher и не включает water/foam в коллизию. Generic glass прежнее.
Производный ember_surface_pilot prefab/mesh обновлены; source bytes не менялись,
в test_pier изменён только материал фона, геометрия прежняя. Копия прежних derived
файлов лежит в Temp/ember-generation-smoke-20260912/pilot-before-water-rebuild-20260914.
Cartoon water + world projection + cache + contact boundaries + sculpt + Canvas
workflow + palette PASS; native disposable Forward+ PASS, два cartoon_water_*.png
кадра проверяют движение. Последний рисунок воды в авторской 3D сцене принят;
при старом cached mesh переоткрыть сцену, не пересобирать всю библиотеку.
Commit/push запрошен для checkpoint выше. После оптимизации пользователь хочет обсудить кисти
редактирования мира прямо в 3D-вкладке, на большем масштабе; реализация не начата.

Уточнение рисунка: поле крупных пятен повёрнуто и плавно изогнуто, чтобы убрать
прямоугольную плиточность. Блики приглушены, длина около3–7 пикселей рисунка,
толщина0.8, плотность0.045; пена у объектов не менялась. Новый
test_water_pattern_seams PASS headless/native Forward+: одна плоскость и две
независимо размещённые соседние совпали пиксельно (diff0), движение PASS.
Cartoon water, world projection, contact boundaries повторно PASS; native кадры
проверены. Это проверка контролируемого стыка, не приёмка всех стыков авторской
карты; ровную сетку 3D-редактора отдельно отключить при визуальной проверке.
Следующая коррекция: длинные обрывы через пятна воспроизведены как quantized
camera Fresnel даже без рисунка. Отражение теперь непрерывное smoothstep;
пиксельные пятна/глубина/пена прежние. Native perspective reflection probe:
max adjacent RGB jump0.1686 до исправления (FAIL),0.00392 после (PASS),
seam diff0 и движение PASS. Это отдельный дефект отражения, не окончательная
причина пользовательского разрыва пятен; авторская арт-приёмка остаётся открытой.
Настоящий разрыв рисунка затем воспроизведён на BoxMesh1800×2×1500 в ракурсе
открытого test_pier, даже в unshaded continuous grayscale noise. Float/fract hash
заменён целочисленным lattice hash: значения соседних узлов теперь согласованы.
Native GPU boundary probe:591498 torn pixels со старым hash (FAIL),0 с новым
(PASS). Seam diff0, motion/reflection PASS; рисунок и блики перераспределились,
масштаб/пиксельность/пена/геометрия сохранены. Пользователь подтвердил исправление.

Последняя доработка2026-09-14: берег больше не наследует резкий край гранёного
рельефа; falloff мягкий по всему радиусу, facet rim оставлен прежним. Проверен
параллельный берегу мазок с radius16/depth4/length60/direction−X/roughness15:
Undo/Redo, repeat, save/reopen/discard и native Forward+ PASS. При quiet roughness0
край поднимается ступенями ≤1 voxel; это не обещание для любой глубины/noise.
Цвета не переносились: после снятия песка открывается существующий зелёный грунт,
его оформить через «Оформить дно». Авторская визуальная приёмка остаётся открытой.

Предыдущий срез: удобство берега, песчаные стенки и открытая вода (2026-09-14).
Canvas → Рельеф → Генератор → «Характер · берег и дно · пробный»: пресеты
«Пологий / Средний / Крутой / Свой», «Длина спуска · vox»4–256; длина пресета
зависит от глубины. Первое начало/исходная поверхность общие для нескольких
мазков до «Новое начало»; повтор не углубляет готовый склон. Начало только
session state: сбрасывается при открытии источника/discard/смене размеров.
Кисть только снимает грунт: старый крутой склон надо отменить перед пологим.
«Оформить дно» переносит радиус в тот же sand paint: два выбранных цвета,
крупные пятна8–64 vox, доля/seed; рисунок продолжается по открытым стенкам
ступеней, скрытый грунт и вода не перекрашиваются. Height slice выключить.
Заливка уровня → «Открытая вода в участке»: абсолютная высота от низа Canvas,
клик по дну ниже неё; связанная область ограничена рабочим участком (либо всем
Canvas). Замкнутые борта не нужны. Понижение убирает старую водную кромку внутри
участка, вода снаружи остаётся прежней. Старый режим замкнутой впадины сохранён.
Настройки сохраняются через editor profiles; Resource/schema и shaders прежние.
Coastal workflow, shore, surface pattern и шесть related suites PASS; disposable
native Forward+ PASS, user://coastal_workflow_native.png. Проверены реальные
кнопки/picker, отдельные мазки, Undo/Redo, source save/reopen/discard и границы.
Художественная приёмка на авторской отмели открыта. Прозрачная вода пока слабо
читается; технический PASS не является принятием её внешнего вида. Авторские
карты/причал не изменены, commit/push не выполнен.
Кусты v6 пользователь оценил «сойдет»: приёмка направления силуэта, не замена
оставшихся ручных проверок крайних настроек/scene placement.
Базовый checkpoint: `255ceee` — деревья/листва/сохранение мастерской.
Предыдущий UI checkpoint: `48774a0`; каноническая глава: `647a882`.

Этот файл — короткая стартовая точка для нового Codex-thread. Он не заменяет
GDD, продуктовый план, технический handoff или migration gates. Если здесь и в
коде есть расхождение, сначала проверить код, tests и Git, затем обновить файл.

## Текущий milestone

Checkpoint2026-09-13 запрошен пользователем: кисть расстановки, камни/оформление,
кристаллы/лёд/размеры и гранёный рельеф вместе с сохранённой сценой/ресурсами.
Пользователь принял визуал рельефа («мне нравится») и сообщил, что проверки
выполнил; отдельное игровое прохождение по новым граням явно не подтверждено.
Первый визуал кустов отклонён пользователем2026-09-13: комки кроны/сердечки,
слишком слитная масса; технический PASS не означает художественной приёмки.
Следующий силуэт v3 тоже отклонён: «как шапочки». По просмотренным референсам
согласована одна проба от побегов, не переделка всех типов. Пресет
«Кусты · Крупные листовые пучки · пробный» явно включает generation_version4:
расходящиеся от земли побеги, перекрытия масс в центре и крупные наклонённые
листовые группы снаружи; общей зелёной юбки и купола нет. Рисунок по умолчанию0.
Старые v1–v3 recipes и две остальные формы v2 не мигрируют.
Восемь targeted/related suites PASS, включая source/recipe/preset roundtrip,
Apply/discard и Undo/Redo. Native Forward+ comparison:
user://generation_bush_shoots_native.png — v3 слева и два v4 seed справа.
Одноцветный кадр проверяет силуэт, но не доказывает читаемость объёма в игре.
V4 отклонён пользователем («монстр»): огромные листья на оголённых побегах.
По новым трём референсам согласованы облака листвы с регулируемым веточным
основанием. Первый preset теперь «Кусты · Облака листвы · пробный», explicit v5,
по умолчанию облака/strength60. Перекрывающиеся неровные массы прячут каркас;
base_height0–32 поднимает листву целиком, height8–96 — отдельная высота листвы,
stem_count1–12 — основные расходящиеся ветки. Рисунок и контур считаются в
локальных координатах облаков, поэтому подъём их не перегенерирует.
Старые v1–v4 не мигрируют; остальные формы остаются v2. Общие saved recipe,
source/preset/history owners сохранены; storage limit524288 прежний.
Native Forward+ cloud probe PASS: user://generation_bush_clouds_native.png,
два низких seed и основание16/12веток. Targeted/related suites PASS, включая
новую высоту в bindings/Apply/save/reopen/Undo/Redo и крайние количества веток.
Базовая облачная форма v5 принята пользователем2026-09-13 («вот эти хорошие»).
Это принятие визуального направления, не отдельное подтверждение всех крайних
настроек, save/reopen и расстановки на пользовательской карте; эти gates открыты.
Следующий срез согласован и реализован: два других типа переведены на облачную
основу через explicit v6. Низкий раскидистый — широкое плотное перекрытие;
высокий ветвистый — вытянутый центр и облака на разных высотах. Принятый базовый
preset остаётся v5, сохранённые v1–v5 не мигрируют. Base_height и ветки1–12
доступны для всех новых типов, оба режима/цвета/пышность/край сохранены.
Восемь targeted/related suites PASS; source/recipe/preset roundtrip, saved editor
и Undo/Redo проверены, включая оба v6 и максимальные сетки. Native Forward+
comparison PASS: user://generation_bush_profiles_native.png — три формы рядом.
Ручная визуальная приёмка двух новых форм открыта. Ягоды/цветы вне среза.

Кустики реализованы в общей мастерской генерации: третий раздел «Кусты»,
три формы, пиксель-арт/лиственные облака, отдельные цвета рисунка и стеблей.
Новая версия2: высота8–96 vox, радиус4–30, пышность, уплощение, разнообразие.
Рецепты без версии остаются прежним компактным штампом без миграции.
test_voxel_bush_objects: headless и native Forward+ RTX5070 PASS; save/reopen,
presets, isolated Apply/discard и Undo/Redo проверены на user:// fixtures.
Native comparison: user://generation_bushes_native.png в disposable smoke-project.
Ручная приёмка новых кустов в рабочем редакторе ещё открыта: формы/сиды/цвета,
сохранение и повторное открытие, расстановка кистью на пользовательской сцене.
Базовая форма v5 принята выше; следующий срез требует своего согласования.
Ягоды/цветы/анимация вне scope.
Локальные .codex/config.toml и художественные черновики/референсы вне checkpoint.
Повторная checkpoint-проверка:15 generation/sculpt/placement suites и3
scene/prefab/pier suites PASS; старые fan_town UID fallback warnings остаются.

Гранёный рельеф2026-09-13: первый согласованный срез реализован в обычном
Canvas → Рельеф → Генератор → Характер · грани. Модельная Voronoi-разбивка
с seeded plane на участок, масштаб4–64 vox, наклон0–100%, стык шириной0–4
и глубиной0–16 vox; ширина0 отключает углубления. Общая высота ограничивает
весь перепад, направление оба/вверх/вниз сохраняется. Внутри80% отпечатка
постоянная сила, внешний край плавный; поверхность остаётся воксельной.
Настройки в существующем editor-only brush profile; voxel Resource/schema/
mesher/physics/Undo/save owners прежние. Почва/гребни не изменены.
6 targeted suites PASS; отдельная native Forward+ workspace fixture PASS,
кадр просмотрен (поля подписаны, picking/commit/Undo/Redo/save/cancel/region).
Математика radius32 около80–90мс; 4×4 density32 с расчётом baseline heightfield
около190–207мс, это не верхняя граница полного remesh/input. Ручная приёмка
визуала на пользовательской карте принята; отдельный runtime walk gate открыт.
Космическая окраска/блеск/glow вне среза.

Кристаллы/крупные камни — доработка2026-09-13: добавлен crystal_base_enabled.
Новые crystal/ice presets без подставки; отсутствующий ключ старого рецепта
сохраняет основание. При выключении отдельные призмы не удаляются; размер
основания не влияет на геометрию и отключён в studio/candidate/Canvas UI.
Rock v2 размеры X/Z3–256, Y3–128 при density16 /3–256 при32; v1 по-прежнему3–32.
Общий Shapes limit524288 storage cells с округлением X/Z не увеличен; ошибка
не изменяет candidate/source. Выше64 — один preview, не один вариант в истории.
Расширенные crystal tests и8 related suites PASS: separate prisms, compatibility,
large geometry, UI/Apply/rejection/Undo/save/reopen. Native Forward+ retest PASS:
toggle/Undo/Redo, saved128-height prepare/remesh/discard; no-platform capture просмотрен.
Прозрачность/шейдеры/секционирование больших объектов вне среза.

Кристаллы/лёд2026-09-13: первый согласованный geometry-only срез реализован
в существующем Rock provider/studio. В «Камни → Форма объекта» добавлены
«Сросток кристаллов» и «Ледяные глыбы»; presets острых сростков, обломанных
столбов, широких ледяных глыб. Управление количеством1–8, толщиной2–20 vox,
разбросом высоты/толщины, наклоном, вершиной и размером общего основания.
Oriented convex prisms имеют общий solid footing и сохраняются как canonical
voxel source; нет mesh-only шипов. XYZ3–64 и density16/32 прежние. Обычные
камни0–2 и старые recipes не менялись; crystal fields скрыты для этих форм.
Общие batch/candidate edit/draft/discard/Apply/Undo/Redo/save/reopen/custom
preset/Canvas; recipe.seed — форма, surface_seed — оформление.9 targeted
suites PASS; max64³/8 elements около0.95с до remesh. Native Forward+ initial
probe и повторный после art tune PASS; итоговый кадр просмотрен. Ручная оценка новых форм открыта.
Прозрачность/блеск/glow не включены. Гранёный генеративный рельеф по третьему
референсу реализован отдельным следующим срезом, см. выше.

Доработка мха/жилы2026-09-13 после визуальной оценки: пользователь принял слои
(в том числе ледяные варианты), не принял автоматический светлый мох/ровную жилу.
Добавлены moss_highlight_color/strength (0 — только основной цвет), новая
mineral_vein_style1 с крупными изгибами, переменной шириной, включениями и<=2
короткими tapering branches; управляются irregularity/branching. Старый style0
сохранён, explicit выбор «Прожилка» opts-in новый style в studio/candidate/Canvas.
Undo возвращает style, source и параметры; load не мигрирует. Старый мох без
новых параметров сохраняет прежний12% tint. Presets мха/жилы обновлены; слои,
силуэт/каналы/коллизия и общий шейдер прежние.8 targeted suites PASS,
native Forward+ probe PASS; max64³ с новой жилой около1.4с до remesh.
Изменение числа ответвлений не сдвигает основную жилу. Ручная оценка открыта.

Оформление камней2026-09-13: согласованы крупные пятна породы, связная
прожилка/слои и островки мха; без мелкой крапинки, кристаллов и новых шейдеров.
Реализованы независимый surface_seed, контраст/размер пятен, цвет/направление/
поворот/толщина/шаг минералов, покрытие/цвет/размер островков/спуск мха.
Слои сочетаются; три новые готовые комбинации дополняют три прежние формы.
Оформление меняет только palette/цвет занятых voxels, не силуэт и физику.
Старые recipes без оформления остаются одноцветными, algorithm1 не мигрируется.
Общие studio/candidate/Canvas fields, draft/discard/Apply/Undo и recipe/preset
save/reopen; недействующие настройки слоя отключены. Targeted rock suite и7
related PASS; native Forward+ --rocks-only --rock-surfaces PASS, capture просмотрен.
64³ geometry около0.8с, с тремя слоями оформления около1.2с (без remesh).
Ручная визуальная оценка оформления пользователем ещё открыта.

Камни2026-09-13: первый согласованный срез реализован; пользователь проверил
и подтвердил «работает». Полная ручная цепочка сохранения карты ещё открыта.
В существующей мастерской генерации теперь явный выбор «Деревья / Камни»;
пресеты: валун, угловатый камень, плоская плита. Размеры XYZ3–64 vox,
неровность, сколы, цвет и density16/32 сохраняются в общем editor-only рецепте.
Общий batch/seed/favorites/archive/save/edit workflow; выбранный камень можно
настроить отдельно с Apply/discard/Undo/Redo, опубликованный — через Canvas.
У камней нет отдельного branch structure: форма детерминирована seed/planes.
Старые rock recipes остаются на algorithm1 и пределах3–32; новые пресеты — v2.
Явный выбор формы opt-in v2, загрузка старого рецепта ничего не мигрирует.
Source/prefab/maps остаются прежними owners; расстановка — уже принятая кисть.
Новый test_voxel_rock_objects и7 related suites PASS; native Vulkan Forward+
editor fixture PASS (реальный selector/presets/vector fields/batches/Apply/
discard/Undo/Redo/publication/reopen/comparison/return to trees).
По8 seeds на каждую форму:8/8 distinct, connected/grounded/schema PASS.
64³ build около0.8с, поэтому working set для размеров>48 ограничен2 candidates,
остальные —4; cancel между полными candidates. Нет remesh на каждый spin input.
Captures и предупреждения disposable editor — в MIGRATION_TEST_PLAN.
Следующий шаг: оценка оформления камней на карте. Кристаллы, шейдеры,
random object sets и новые кусты не реализованы.

Кисть расстановки2026-09-13: первый согласованный срез реализован; пользователь
проверил в редакторе и подтвердил «ок, работает». Отдельное ручное подтверждение
save/reopen и всех переключений инструментов ещё не получено.
В нижней библиотеке выбрать объект → «Расставлять кистью…»; выбранный
шаблон остаётся активным между мазками. Настройки: шаг в блоках, поворот Y,
общий масштаб и заглубление в vox плотности шаблона. Прозрачное превью без
коллизии; клик ставит экземпляр, протяжка ЛКМ — до256 экземпляров за один Undo.
Esc выключает; ПКМ/СКМ/Alt сохраняют камеру. Потеря фокуса/поверхности или
пропущенное отпускание отменяют незавершённый мазок, а не создают объекты.
Создаются обычные EmberVoxelProp в Map/Props; карта владеет transforms/IDs,
voxel-источник не меняется. Это не штамп Canvas и не набор случайных вариантов.
Новый test_voxel_object_brush и7 связанных suites PASS; отдельный native Vulkan
Forward+ fixture PASS (маршрут plugin input, settings bindings, hover/drag,
pointer-up, elevated surface, Undo/Redo, camera/Esc), captures просмотрены.
В disposable editor есть UID fallback/duplicate warnings и scan-aborted на exit;
не заявлять clean editor lifecycle или ручную приёмку пользовательской карты.
Первый следующий срез камней реализован выше; кусты ещё не начаты.

Параллельный согласованный gameplay-срез 13 сентября: движение вне боя ускорено
до 3 блоков/с; EmberPlayer физически плавно поднимается на ступени до 1/4 блока.
FollowCamera плавно догоняет только высоту при подъёме, XZ без задержки.
Проверки stepping и связанных party/save/health/inventory/pause/pier gates PASS;
native Forward+ fixture PASS. Пользователь подтвердил «работает» в живой игре;
мелкое проседание между досками решается отдельной физической опорой настила.
Этот срез не завершает мастерскую и не запускает пролог.
Подробные правила — GDD, implementation/gates — handoff и MIGRATION_TEST_PLAN.

Git checkpoint2026-09-13 запрошен пользователем после запекания ориентации.
Включены Grab/мягкий Bend, общий boundary clip, актуализация библиотеки,
merge view/orbit и exact scene-axis bake, связанные tests/docs, сохранённые
пользователем доски/склейки/производные prefab/meshes и test_pier/surface pilot.
Локальный .codex/config.toml и Mira drafts остаются вне Git checkpoint.
Повторно16 targeted suites PASS (Grab/Bend/clip/fragment/stamp/pattern/selection/
bake/merge/library updates/layout/object Canvas/scene assembly/object split/
shapes/filesystem);16 sources +15 prefabs schema/load/instantiate PASS без записи.
Есть диагностические warnings:1 ObjectDB instance у fragment fixture на exit,
один prefab mesh UID fallback к существующему .res path. Не заявлять zero-warning
или новый полный128-suite прогон; manual editor gates остаются как описаны ниже.

Checkpoint2026-09-13: пользователь принял ель и запросил общий commit/push
редактора, генераторов и сохранённых объектов. Проверены все128 scripts:
125 прошли (assembly screenshot — native Forward+). Последующие targeted
проверки закрыли3 оставшихся gates: placement/split preview адаптированы к
нынешнему authoring, sandbox native batch PASS без пересборки6 prefab.
Это отдельная проверка оставшихся gates, не повторный полный запуск всех scripts.
Подробности в MIGRATION_TEST_PLAN.md.
Это сохранение текущей точки, не объявление всего редактора завершённым.
Будущие настройки характера деревьев и управляемые вариации записаны в
EMBER_PRODUCT_PLAN.md рядом с отложенными shaders/light/mesh optimization.
Пользователь завершил текущую итерацию деревьев и запросил commit/push.
Форма пород, разнообразие, пробные режимы листвы и сохранение параметров
зафиксированы; дальше деревья не дорабатывать без нового запроса.
Оптимизация mesh/шейдеры и расширенные настройки характера остаются
отложенными в продуктовой дорожной карте. Основной редактор ещё не объявлен
полностью завершённым; ручная итоговая цепочка с доской остаётся открытой.
Перед Git checkpoint повторно прошли13 targeted suites: variation, формы
всех5 пород, tree_types, bark, large_tree_object, generator/editing,
foliage_species и workshop_generator_save. diff --check PASS; Forward+
проверки листвы и сохранения выполнены в предыдущих срезах на disposable copy.

Текущий срез — opt-in «Запечь ориентацию сцены» при склейке. Pure Merge.plan
переносит exact proper quarter rotation scene frame в existing slot mapping,
сохраняя world cells, шесть каналов, palette, merge parts/groups/overlap.
Alignment остаётся в сетке основной детали; reported world shifts прежние.
Uniform scale остаётся в scene frame; rotation запекается в Resource, поэтому
обычный Canvas и библиотека получают ориентацию сцены без второго view owner.
Произвольный угол, reflection/shear/nonuniform scale и превышение новых grid
limits отклоняются без округления/публикации. Тогл default off, только склейка;
отдельный display toggle не меняет данные. Старые склейки не мигрируют.
Новый test_voxel_merge_orientation_bake PASS:24 rotations, density16/32,
aligned secondary, colors/channels/groups/parts/overlap, rejection/recovery,
single Undo/Redo, save/reopen, Canvas open/pick/sculpt/Undo и unmerge.
Также8 related suites PASS: merge/shapes/scene_assembly/object_canvas/
object_split/assembly_canvas/object_library_updates/layout. Disposable native
Forward+ цепочка bake→commit→Canvas подтверждена: preview локально горизонтален,
world frame совпадает, Canvas flat/clean; captures просмотрены. В probe после
DONE зарегистрирован get_node outside active tree при teardown (и scan abort);
это не объявлено полностью зелёным editor lifecycle gate. Живой пользовательский
gate (повторная склейка/кисти/save/reopen) открыт. Авторские модели и мост не
менялись, Git не запрошен.

Предыдущий срез — ориентация предпросмотра склейки/разбора. Тогл «Ориентация как
в сцене» включён по умолчанию: preview учитывает scene frame основной детали,
выключение показывает локальные оси. Translation/common uniform scale
перебазированы только для изолированного viewport; rotation/relative scale
сохраняются. Ghosts прежних позиций и overlap используют ту же presentation.
ЛКМ/СКМ вращают камеру, колесо приближает, «Сбросить вид» возвращает fit.
Переключение не пересчитывает merge и не меняет Resource/commit frame.
Preview поднят над длинным status, виден без прокрутки. Merge targeted и7
related suites PASS: shapes/scene_assembly/object_canvas/object_split/
assembly_canvas/object_library_updates/layout. Disposable native editor
Forward+ PASS: горизонтальный настил scene view / вертикальный local view,
orbit/reset, captures просмотрены; viewport целиком виден. Ручной gate в
живом редакторе (mouse/zoom/apply на пользовательском мостике) остаётся открыт;
пользовательский мост/сцена/источники не меняются.
Commit/push не запрошен.

Предыдущий срез — исправление обнаружения новых сохранённых объектов в библиотеке.
Пользовательская доска сохранена в native .tres, но открытый shelf держал старый
список; обычная нижняя вкладка «Объекты» не вызывала open_for/refresh.
Причина воспроизведена в disposable native editor: после успешного install
AUTO0/REOPEN0, прямой refresh1. Теперь ModelStore уведомляет observers только
после успешной публикации окончательных files/cache identities; shelf coalesces
refresh и подписан на visibility / EditorFileSystem.filesystem_changed.
Query, owner filter, selection и unrelated cached thumbnails сохраняются.
Нет нового catalog/schema или переименования; canonical owner прежний.
Targeted library_updates/layout/object_canvas/generator_save/editor_filesystem/shapes/object_split
PASS. Native editor Forward+ повтор показывает AUTO1/REOPEN1 без remesh/import
библиотеки. Живой редактор пользователя через MCP недоступен; ручная проверка
в нём открыта. После загрузки обновлённого плагина искать384406539; имя модели
остаётся «Новая форма», имя экземпляра «опорная доска» — отдельное поле.
Авторские assets/scenes не менялись нами; commit/push не запрошен.

Предыдущий срез — общая опция «Обрезать по границе» в «Части → Вид →
Рабочая область». По умолчанию strict; clip сохраняется в editor view store
глобально для мастерской, не в объекте и не отдельно для каждой кисти.
Подключены Grab, перенос/копия/поворот/изгиб фрагмента, штамп/россыпь,
вдавливание и паттерны. Результат ограничен canvas/region/slice; при move/
deform исходная часть снаружи результата удаляется, при copy исходник остаётся.
Существующая геометрия вне editable mask не участвует в удалении. Locked и
проверка занятых destinations сохраняются. Preview показывает обрезанный
результат, количество crop отображается; один Undo возвращает отсечённое.
Смена тогла пересчитывает fragment/stamp preview и отменяет незавершённый Grab.
Grab теперь доступен при height slice; hidden vox остаются защищённым контекстом.
Boundary clip + Grab +9 related targeted suites PASS; native Forward+ Grab
clip Canvas1280×720 PASS на disposable copy, capture просмотрен.
Ручной gate: включить обрезку, потянуть доску через край области/холста;
проверить отсечение и Undo, затем штамп/паттерн на краю и save/reopen.
Авторские assets/сцена не изменялись нами; commit/push не запрошен.

Предыдущий согласованный срез — кисть «Тянуть · мягко» прямо в Canvas.
Пользователь уточнил: точная команда изгиба неудобна вместо Grab. Теперь
ЛКМ захватывает форму, тяга идёт в плоскости экрана, соседний объём следует
с мягким краем; radius1–32vox и softness0–100% в существующих tool profiles.
Preview — отдельный transient draft в том же chunk renderer, исходник не
меняется до отпускания. Pointer-up применяет точный последний результат
одним SculptActions Undo; Esc/смена инструмента отменяют, Save/Ctrl+S во время
жеста блокируются без потери черновика. Общая Fragment remap-транзакция
переносит все6 byte channels, groups/part IDs; обратное sampling и forward
seeds заполняют вытягиваемый объём, количество vox может изменяться.
Работа jobs/coalescing порциями ~4ms, без full remesh на mouse event.
Первый срез: canvas≤524288 cells, influence≤32768 occupied vox, bounded
candidates/drag; без water fill/authored lights/hidden or isolated groups,
locked не затрагиваются; strict отказывает на region/slice, опциональный clip
описан выше. Grab +10 related suites PASS;
native Forward+ Canvas capture1280×720 просмотрен. Kernel ~30ms на доске
и ~480ms при radius32 на524288 cells, большие jobs обновляются с задержкой.
Ручная приёмка открыта: уникальная доска → «Тянуть · мягко», radius12–24,
softness75%, потянуть угол/центр → отпускание/Esc → Undo/Redo → save/reopen/F6.
Авторские доски и сцена пользователя не менялись; commit/push не запрошен.

Предыдущий срез — точная деформация «Изгиб…» в левом rail мастерской.
Гнёт выделение или весь объект без выделения: ось длины, направление, дуга
с закреплёнными концами / загнутый конец, signed сила в vox. Общая fragment
remap-математика и SculptActions Undo; цвета/material channels/collision/groups/
part IDs перемещаются вместе. Preview явно обновляется, одна Apply/Undo.
Ограничение32768 occupied vox, без перекрытия/locked; для canvas/slice/region
действует общий strict/clip режим выше;
заливка воды и отдельные authored lights отклоняются. Авторасширения нет.
Bend targeted +9 related suites PASS; sandbox native batch PASS отдельно.
Native Forward+ bend/workshop layout/split/placement preview PASS, captures
просмотрены. Ручной gate: уникальная копия доски → изгиб2–4vox → Undo/Redo →
save/reopen → F6; исходная доска и её пользовательские копии не менялись.
Команда остаётся дополнительным точным инструментом, не заменой Grab.
Пользовательская приёмка всей ручной цепочки остаётся открытой.

Последний принятый генераторный срез — общие режимы листвы для всех5 типов деревьев.
Pixel-art1 и clouds3 доступны саванне/дубу/берёзе/клёну/ели в creation,
candidate editing и contextual Generator; те же FoliagePattern и volumes.
Каркас/physical и прежняя листва0 не менялись; параметры pattern/clouds
общие, без новых controls/schema. Shoot trial2 остаётся только дубу;
явный переход с него на другую породу выбирает прежнюю листву с Undo.
Существующие assets не пересобираются автоматически. Новый species targeted
проверяет обе пробы/все5 пород/64–256/seeds17/371/wood+collision/fresh-frozen/
serialization/UI/Undo/Redo/Discard; он и5related suites PASS. Native Forward+
disposable gallery10 деревьев PASS, capture просмотрен. Пользователь принял
текущий итог и завершил итерацию; это не объявление trial-режимов финальными.

Предыдущий согласованный срез — сохранение рецепта из воксельной мастерской.
В активной вкладке «Генератор» общая Save/save_changes()/Ctrl+S публикует
точный preview и все параметры через существующую Creation-транзакцию,
по выбранному режиму. Нет preview — отказ без сохранения старого sculpt
исходника; manual dirty update защищён. Новый user:// targeted тест и
native Forward+ workspace gate PASS: все3 режима/полные параметры/reopen/
Undo/Redo/Discard/stale preview. Related editing/foliage/object canvas PASS.
Пользователю проверить Save/Ctrl+S после
редактирования стиля и выраженности; художественная приёмка дуба17 открыта.

Предыдущий согласованный срез — боковое вторичное ветвление дуба17. Пользователь
подтвердил рандомность16, но попросил закрыть боковые пробелы настоящими ветками.
Тот же TreeVariation планирует1–3 lateral shoots на крупный сук по «Ветвистости»;
«Разнообразие» меняет anchors/turn/length/rise. Побеги из средней части сучьев
растут наружу, раздваиваются и несут боковые/нижние leaf masses. Нижний ствол
остаётся открытым. Primary composition16 и его RNG сохранены; pixel-art math
прежняя. Новые presets/type reselect используют17, старые8/11/16/frozen exact;
diversity0 exact8. Нет новых ползунков/схемы/renderer. Для новой партии повторно
выбрать «Дуб»; старый кандидат — явная regeneration из настроек партии/Undo.
Variation targeted включает secondary count/sideward growth/physical anchors,
primary16 parity и frozen16 non-upgrade; all5species/limits/history gates PASS.
Variation и8related oak/types/bark/editing/large-tree/generator/foliage/session
PASS; native Forward+ Apply/Discard/regeneration/Undo/Redo/publication/reopen
PASS без script/engine errors, captures просмотрены; art gate открыт.

Предыдущий срез — композиция дуба16 после screenshots №29–31:
пользователь оставляет pixel-art основой, clouds/shoots — экспериментами.
Отдельный pure oak_composition в TreeVariation меняет высоты/азимуты крупных
развилок и баланс крон; два tapering leaders продолжают ствол в верхнюю крону,
их реальные побеги несут связующую внутреннюю листву. Нет filler sphere,
нового renderer/схемы/ползунка. Pixel-art math не менялась. Новые type presets
и явный reselect «Дуб» используют16; сохранённые8/11 и frozen trees не меняются.
Разнообразие0 сохраняет exact прежнюю8 geometry. Для новой партии повторно
выбрать «Дуб»; для старого кандидата дополнительно явная команда «Новый каркас
из настроек партии», с Undo. Targeted проверяет reported параметры96/8/80,
6seeds, реальные leaders/центральную листву и fork-height diversity; общий
variation suite продолжает все5 пород/limits/fresh-frozen/text/preset/history.
Variation targeted и8related oak/types/bark/editing/large-tree/generator/
foliage/session PASS; native Forward+ editing/regeneration/Undo/Redo/
publication/reopen PASS без script/engine errors; captures просмотрены;
художественная приёмка пользователя открыта. Другие породы/новая листва вне среза.

Предыдущий срез — вторая проба «Лиственных облаков» дуба8/11: style3
в том же FoliagePattern/Recipe/workshop/contextual Generator. Вместо кольца
тонких подушек — крупные объёмные купола над ветвями, редкие пары листиков
по краям. Общий surface pattern из pixel-art наносится после объединения масс:
«Размер рисунка · детализация»0–100 (выше — мельче пятна) и «Выраженность
рисунка»0–100 (контраст палитры), не меняют форму или frozen scaffold.
Размер деталей3–12 и выраженность листиков0–100 (default35) сохранены.
Recipe.parameters.foliage_cloud_version: новые defaults2, missing1. Первая
проба и стили0/1/2 exact; для старого кандидата/preset/object повторно выбрать
«Лиственные облака · пробные»: upgrade явный, Undo возвращает прежнюю пробу.
Native Forward+ сравнение на одном scaffold/Apply/Discard/Undo/Redo/
publication/reopen PASS; clouds-only, полный foliage и8related suites
oak/types/bark/editing/large-tree/generator/variation/session PASS.
Визуальная приёмка пользователя открыта; другие породы/shaders/perf леса вне среза.

Предыдущий срез: пользователь принял разнообразие дуба11/клёна12 и видит
потенциал листовых побегов. Тот же механизм адаптирован для берёзы13/саванны14/ели15.
Seed раньше менял координаты, но схема сучьев/развилок оставалась
слишком фиксированной. Общий pure TreeVariation планирует количество/высоты/
длины/изгибы/асимметрию и вторичные развилки в пределах породного envelope.
Новые type presets и явный reselect используют14/11/13/12/15; старые рецепты и frozen skeleton
не обновляются автоматически. Один creation-only «Разнообразие каркаса»0–100%
(default65);0 воспроизводит прежнюю geometry. Pixel-art дуба поддерживает11,
его математика/настройки не менялись; пользователь считает его лучшим пробным.
Берёза меняет ритм тонких поникающих побегов, саванна — развилки под плоской
зонтичной кроной, ель — ярусы/длины/вторичные побеги вокруг центральной оси.
Будущие характер/возраст/многоствольность и полировка листовых побегов вне среза.
Новый targeted проверяет6 seeds ×64/128/256 для всех пяти пород, yaw-invariant
структурные различия/counts, old parity при0, fresh/frozen/text, extreme seeds/
directions, preset/draft Undo/Redo. Ручная приёмка берёзы/саванны/ели открыта.
Variation targeted и10related oak/maple/birch/savanna/spruce/types/bark/foliage/
editing/session PASS. Native disposable всех пяти пород:
Forward+ bare/dressed comparison, индивидуальные
Apply/Discard/Undo/Redo/publication/reopen и explicit regeneration/Undo/Redo PASS;
скриншоты просмотрены. Новый план не является character/age editor или forest
performance gate. Для текущих старых настроек повторно выбрать тип перед batch.

История листовых проб (не текущая задача):
Текущий согласованный срез — пробная пиксель-арт листва актуального дуба v8:
переключатель прежняя/пиксель-арт и одна новая «Детализация», через общий
provider/Recipe/workshop/contextual Generator. Крупные объёмы получают связанные
неодинаковые группы с неровным ступенчатым краем и согласованными цветовыми
пятнами. Каркас, кора и коллизия не меняются; missing fields оставляют старую
геометрию. Остальные породы, иголки, ветер и shaders вне текущего среза.
Реализация готовится к визуальной приёмке пользователя; не объявлять её принятой
по автоматическим tests. Затем адаптировать подход к другим породам по результату.
Foliage targeted и7 связанных suites PASS (oak/types/bark/editing/session/
large-tree-object/generator); native disposable Forward+ Apply/Discard/Undo/Redo/
publication/reopen PASS. Геометрия64–256 около0.21–0.67s, meshing отдельно.
Канонический owner/совместимость — в technical handoff, ручной сценарий — gates.
После проверки пользователь отметил разнообразие формы, но слабую читаемость
рисунка. Согласован следующий пробный срез: FoliagePattern revision2 наносит
согласованные ступенчатые листовые пятна на поверхность уже собранной кроны,
независимо от порядка перекрытия объёмов. «Детализация» меняет масштаб рисунка,
новая «Выраженность» — контраст; они не перестраивают крону. Missing pattern
revision сохраняет первый рисунок1; явный выбор «Пиксель-арт» (в том числе
повторный) включает2 с Undo/Redo. Приёмка нового рисунка открыта, другие породы/
иголки/шейдер/свет не входят в этот срез.
Surface targeted и4related suites (oak/bark/editing/session) PASS; native
Forward+ сравнение strengths20/65/100, individual Apply/Discard/Undo/Redo,
publication/reopen/contextual fields PASS. Прямые viewport captures просмотрены.
Обновление custom pixel v1 сохраняет старую форму через скрытый geometry detail;
этот переход проверен на Detail85. Fresh geometry около0.23–0.72s, mesh отдельно.

Пользователь оставил pixel surface как пробный вариант. Следующий согласованный
срез — «Листовые побеги · пробные» (style2) только для актуального дуба8.
Тот же FoliagePattern строит компактное внутреннее ядро и зелёные побеги с четырьмя
поочерёдными согнутыми ромбовыми листьями; ближайшая древесина frozen scaffold
задаёт привязку/направление. Wood, bark и collision не меняются. Один новый
контрол — размер листика3–12vox (default5), остальные общие amount/along/цвет/
размер пучков. Old0 и pixel1 сохраняются, shaders/ветер/другие породы вне среза.
Визуальная приёмка этого подхода открыта; тестовый дуб96/seed391 сначала
сравнивается со старым на одном каркасе, затем размеры5/8 и другой seed.
Foliage targeted и4related (oak/bark/editing/session) PASS; disposable native
Forward+ size Apply/Discard/Undo/Redo, publication/reopen/contextual PASS.
Fresh64–256 около0.28–0.87s, meshing отдельно. Дуб96/seed391:75_250 occupied
вместо125_212, но174_280 triangles вместо91_340 (~1.9×): trial не является
готовой оптимизацией для леса. Native captures просмотрены, art gate открыт.

- Реализован поток «Объекты → Генерация…»: отдельная native вкладка сцены
  `addons/ember_import/editor/Генерация.tscn` с нейтральным светом и общая нижняя
  мастерская. Настройки новой партии слева, варианты в центре, выбранного дерева
  справа. Постоянные номера над объектами совпадают со списком; native selection
  маршрутизируется к конкретному кандидату, есть solo/gallery. Черновик параметров
  не remesh-ит; Apply пересобирает только выбранное дерево, Undo/Redo хранит Recipe,
  не старые mesh. Каркас сохраняется при правках листвы/толщины; его замена из
  настроек партии — отдельная команда с Undo. Dirty draft требует Apply/Discard
  перед сменой кандидата/новой партией/save. По очереди до 4 вариантов,
  выше 128 vox — до 2; остановка между кандидатами. История всех партий сохраняет
  каждый готовый вариант, seed/Recipe/каркас и постоянный номер; фильтры всех
  партий/лучших/конкретной партии, страницы по 40 записей. Непросматриваемые
  варианты освобождают geometry; «Настроить» восстанавливает один, галочки «3D»
  собирают сравнение между партиями в пределах 4/2. Отметка «лучший» независима
  от 3D и не уменьшает следующую партию. Сохранить лучшие из всей истории
  в библиотеку можно без размещения; одно имя — одно семейство, другие имена
  начинают другое. Recipe/seed/frozen skeleton сохраняются с concrete source.
  Параметры и выбор имеют локальные Undo/Redo, публикация — scene history по
  варианту с защитой последующих файловых правок/использования в карте.
  Три базовых пресета + именованные editor-only Recipe пресеты без каркаса и
  family identity; «Ещё → Генерировать похожие» повторно использует параметры
  сохранённого объекта, не его старый каркас. Штампы и contextual Canvas
  «Генератор» сохранены. Новая common infrastructure сейчас подключает только
  large_tree; мастерскую пользователь принял, новый срез истории партий ждёт
  ручной приёмки. Scene save/reopen исключает временные nodes. Смена сцены приостанавливает
  session без потери галереи/черновика; закрытую studio scene можно восстановить
  только для просматриваемых candidates. Явное закрытие набора подтверждает
  удаление unsaved истории. Сохранение лучших идёт по одному варианту за frame,
  не оставляет geometry архивных записей загруженной после публикации.
  После первой публикации candidate immutable для local history даже после file
  Undo: изменение через Canvas или параметры для новой партии, без preview/file
  Redo divergence. Временный набор живёт только до закрытия набора/редактора.
  Новый session test и 5 related suites PASS. Изолированный native Forward+
  studio/map/dirty draft/individual apply/selection/F+wheel/save-only history/
  preset/studio save/Canvas edit/generate-similar/confirmation Cancel/discard PASS,
  включая историю 8 вариантов/2 партий, точное восстановление архивного дерева,
  cross-batch comparison и saved archive, capture сравнения просмотрен.
  Confirmation hide-before-free устранил
  exclusive-window conflict промежуточного native прогона. Прежние UID
  warnings fan_town в copied assets не исправлялись этим срезом.
  Следующий срез реализован в прежнем provider: «Саванна» оставлена нынешним
  типом, добавлены стилизованные дуб/берёза/клён (generation_version=3).
  Типы различаются высотой ветвления, размахом и профилем кроны; направление
  «По типу / Вверх / В стороны / Слегка вниз». Новые типы имеют дополнительные
  frozen опоры листвы вдоль ветвей и параметр 0–100%, редактируемый без движения
  древесины. 4 type presets плюс 3 прежних; имя типа видно в истории.
  Старые v1/v2 остаются byte-identical на golden samples 64/128/256; отсутствие
  новых ключей не переводит старый рецепт в v3. UI/Recipe/preview/publication
  используют прежние owners, отдельного species generator нет. Новый targeted
  tree types test и 6 related suites PASS; native common workshop сравнение
  4 типов/4 партий, interior foliage Apply/Undo/Redo, publication/reopen PASS.
  Панель обновляет candidate descriptors при смене типа: прежняя одноразовая
  сборка скрывала новый editing field, regression добавлен. Художественная
  приёмка типов открыта; генерация 128 vox около 0.45–0.5 s, meshing отдельно,
  тяжёлые операции остаются explicit и по одному объекту за frame.
  После замечания пользователя о «шапках на столбе» реализована отдельная v4
  для нового дуба: ранние развилки, несколько сильных изогнутых сучьев вместо
  центральной высокой оси, широкая связная крона из перекрывающихся неравных
  объёмов. «Тип · Дуб» и новый выбор типа дуб используют v4; загрузка старого
  Recipe не обновляет алгоритм. Саванна/берёза/клён и сохранённые v1/v2/v3 не
  изменены. Каркас прежнего формата version=1 хранит радиусы объёмов и шум;
  индивидуальные правки листвы/цвета не двигают древесину. Targeted oak crown
  и tree types PASS, 6 related suites PASS. Проверены 3 seed и высоты 64–256,
  точный fresh/frozen/text roundtrip, bare view, Apply/publication Undo/Redo.
  Union листвы v4 пропускает уже заполненные клетки и заведомо внешние точки,
  golden hashes подтверждают неизменность geometry; 128 vox примерно 0.86–0.95 s
  без prefab meshing, 256 ограничен прежним storage budget. Изолированный native
  Forward+ сравнивает старый дуб, новый, тот же каркас без листвы и другой seed;
  финальный native Apply/Undo/Redo/publication/reopen PASS, capture просмотрен.
  Пользователь принял новый силуэт дуба: «дубы стали похожи на дубы».
  Следующий согласованный срез — берёза v5 в том же provider: тонкий непрерывный
  изогнутый leader, лёгкие восходящие ветви и поникающие внешние веточки,
  вытянутая воздушная крона. Новый preset «Тип · Берёза»/выбор типа используют v5,
  старые Recipe не обновляются. Quarter anchors, crown volumes/noise и foliage
  projection общие с дубом; Source/Recipe/workshop/publisher owners не менялись.
  Birch targeted PASS: 3 seed, 64/96/128/256, maximal build, exact fresh/frozen/
  text roundtrip и collision, foliage/season/thickness без движения опор,
  draft discard, Apply/publication Undo/Redo/reopen. Leaf 128 vox около 60 ms,
  meshing отдельно. Oak golden compatibility и 6 related suites PASS.
  Tree types UI choice/Undo/Redo PASS. Финальный native Forward+ old/new/bare/
  second seed comparison, individual Apply/Undo/Redo и publication/reopen PASS;
  capture просмотрен. Прежние copied fan_town UID warnings не менялись.
  Пользователь принял силуэт берёзы («вполне да берёзы»).
  Реализован общий «Рисунок коры» для large_tree: toggle, направление поперёк/
  вдоль/наклонно, цвет, длина 2–24 vox и насыщенность 0–100%. Один чистый BarkPattern
  leaf обслуживает все породы; координаты штрихов идут в локальном frame ветви,
  пространственные buckets ограничивают поиск ближайшей опоры. Это окраска
  exposed wood, не геометрия/шейдер. Dedicated palette[7] добавляется только
  при наличии штрихов; shape/collision/leaf palette не меняются. Новый preset
  берёзы — тёмные поперечные штрихи, дуба — продольные коричневые; missing keys
  старых рецептов оставляют рисунок выключенным. Общие bool/choice descriptors
  работают в мастерской и contextual Canvas, explicit Apply/preview сохранён.
  Bark targeted, oak/birch/types и 6 related suites PASS; negative-zero atan2
  seam после Recipe text roundtrip устранён, exact voxel roundtrip PASS.
  Native isolated bark comparison/toggle/direction/colour/length Apply/Undo/
  publication/reopen PASS, capture просмотрен; распределение затем улучшено до v2.
  Распределение коры v2 убирает общий центр горизонтальных рядов: отдельные
  штрихи смещены по высоте/окружности, разделены промежутками; поперечная/
  наклонная длина ограничена толщиной опоры. Новые defaults/presets используют
  v2, missing `bark_pattern_version` сохраняет v1 без автоматического изменения
  готовых деревьев. Явное off/on «Рисунок коры» обновляет только этот алгоритм
  в workshop/Canvas; Undo восстанавливает прежнюю версию. Bark/oak/birch/types,
  generator editing/session и общий generator PASS; native Apply/Undo/Redo/
  publication/reopen PASS. Пользователь принял распределение коры v2 («да это лучше»).
  Реализован следующий согласованный срез — клён v6: стройный ствол, несколько
  восходящих развилок, веерное раскрытие в стороны и связная округлая крона
  вместо боковых «тарелок»/шариков на высокой оси. Новый preset/выбор типа
  используют v6, saved v3 maple не обновляется автоматически. Frozen lines,
  crown volumes/noise, Source/Recipe/registry/workshop/publisher общие; новых
  ручных knobs нет. Maple targeted PASS: 3 seed × 64/96/128/256, extreme envelope,
  source/structure validation, fresh/frozen/text exact roundtrip, bare/season/
  thickness support stability, type choice Undo/Redo, Apply/discard/publication
  Undo/Redo/reopen. Oak/birch/types/bark и generator editing/session PASS;
  native Forward+ old/new/bare/second
  seed comparison, individual Apply/Undo/Redo и publication/reopen PASS,
  capture просмотрен. Пользователь не принял v6: по фото референса нужна высокая
  крона с широкой серединой и более узким округлым верхом, не плоская чаша.
  Согласована доработка клёна v7: ветви на пяти высотах, размах уменьшается к
  верхушке; перекрывающиеся массы и заполнение внутренней кроны связывают уровни.
  Новые preset/выбор типа → v7, saved v3/v6 остаются прежними. Source/Recipe/
  frozen structure/publisher owners и набор ручных параметров не меняются.
  Финальный maple targeted PASS: 3 seed ×64/96/128/256, v6 golden parity,
  five heights/middle-versus-top reach, реальная высокая крона без пустых
  горизонтальных рядов, maximal occupied/storage envelope, exact fresh/frozen/
  text roundtrip, Apply/discard/publication Undo/Redo/reopen. Oak/birch/types/
  bark и generator editing/session regressions PASS. Native Forward+ comparison
  v6/v7/bare/seed17 и отдельные передний/правый ортогональные виды проверены,
  Apply/Undo/Redo/publication/reopen PASS; captures просмотрены.
  Следующий согласованный шаг после ручной проверки клёна — вернуться к дубу,
  а не начинать ель. Пользователь принял клён v7: «да, похоже на клён».
  Согласован и реализован повторный дуб v8 по фото взрослого раскидистого дерева:
  массивный изгибающийся ствол с непрерывным расширением основания и короткими
  слитыми buttresses, сучья из разных точек/высот, кривые боковые нижние ветви,
  вторичные развилки и восходящие верхние сучья. Более небольшие объёмы листвы
  на разных высотах и внутренние опоры заменяют общую плоскую шапку; нижние
  развилки остаются видимыми. Новый «Тип · Дуб»/явный выбор типа → v8;
  saved v3/v4 не обновляются. Source/Recipe/frozen structure version1/bark/
  workshop/publisher общие, без новых ручных параметров. Oak targeted PASS:
  12samples64–256, v3/v4 golden parity, разные высоты развилок/нижний размах/
  глубокая реальная крона/плавное основание, bounded extreme и направления,
  fresh/frozen/text exact geometry/collision, bare/season/thickness, type choice/
  discard/Apply/publication Undo/Redo/reopen. Maple/birch/types/bark и common
  generator editing/session PASS. Native isolated Forward+ v4/v8/bare/seed17
  Apply/Undo/Redo/publication/reopen PASS; форма просмотрена спереди и справа.
  Пользователь принял форму дуба v8 («форма мне нравится»).
  Согласована зонтичная саванна v9 по фото: изогнутый ствол разделяется на
  несколько опорных стволиков, сеть более тонких боковых ветвей и широкая
  неглубокая слегка выпуклая крона без обязательной центральной верхней оси.
  Развилка меняет высоту от seed, внутренние/внешние массы перекрываются;
  перепады кроны зависят от bounded размаха, не только номинальной высоты.
  Новый «Тип · Саванна»/явный выбор типа →v9; default и saved v2/v3 не
  обновляются на загрузке. Формат frozen structure1, common paint/bark/emitter,
  Source/Recipe/workshop/publisher прежние. Shared foliage_along теперь
  доступен для v9, без новой панели/ручных knobs. Targeted savanna PASS:
  12samples64–256, v2 golden parity, shallow/wide elevated canopy/no pole,
  max budget/directions, source/structure/fresh-frozen geometry+collision,
  text roundtrip, bare/season/thickness, type choice/discard/Apply/publication
  Undo/Redo/reopen. Oak/maple/birch/types/bark и common editing/session PASS.
  Native disposable Forward+ v2/v9/bare/seed17 сравнение, индивидуальные
  Apply/Undo/Redo/publication/reopen PASS; передний/правый ортогональные
  captures просмотрены. Ошибки неполного старого Recipe в fixture устранены;
  финальный лог без script errors. Прежние copied UID warnings не менялись.
  Пользователь принял саванну v9 («Проверил, красиво»). По новой договорённости
  сначала ель, затем обсуждение общей системы листьев/хвои.
  Реализована ель v10 в прежнем provider: непрерывный тонкий leader, девять
  ярусов сокращающихся к верхушке ветвей, лёгкое провисание нижних сучьев,
  вытянутые объёмы хвои на веточках и перекрывающиеся внутренние опоры.
  Frozen structure1/Source/Recipe/workshop/bark/publisher прежние; размер64–256,
  Apply меняет хвою/толщину без движения каркаса, отдельные иголки не добавлены.
  Все пять типов стоят рядом, явный выбор использует актуальные версии9/8/5/7/10.
  Новая мастерская начинает с v9, loaded Recipes не обновляются и помечены
  «прежняя форма», старые алгоритмы остаются в настройках совместимости.
  Spruce targeted и11related suites PASS. Native isolated Forward+ триseeds/
  bare/individual Apply/Undo/Redo/publication/reopen10 PASS; финальные
  front/right/gallery captures просмотрены, лог без script errors.
  Пользователь проверил и принял ель («Мне нравится, проверил»).
  Следующий шаг — обсуждение общей системы листьев/хвои, без автоматической
  реализации до согласования визуального направления.
  Согласованный порядок: пройти формы остальных presets, затем отдельный проход
  по форме/распределению/деталям листвы. Редактор веток позже;
  шейдеры/свет/оптимизация mesh остаются отдельными последующими этапами.

- Реализована общая contextual вкладка Canvas `Генератор`, первый provider —
  large_tree v2 (`Крупные формы`). Editor recipe хранит сохранённый каркас;
  листва/цвета независимы от древесины, толщина/сужение сохраняют развилки.
  Draft parameters Undo/Redo, точный shared-viewport preview, cancel/discard,
  Save: новая именованная вариация / обновить выбранную / отдельный объект.
  Семейство имеет одну карточку библиотеки с выбором concrete вариации; публикация
  сразу обновляет каталог. Shared update source+recipe+instances Undo/Redo,
  hash-conflict и защита ручной лепки реализованы; другие варианты не меняются.
  Classic/обычные модели/остальные providers вкладку пока не показывают.
  Ручная лепка не переносится в variant; overwrite при ручных правках запрещён. Художественная
  и рабочая editor приёмка открыты; individual branches и другие providers позже.
  Исправлены нижние voxel faces в общем mesher. Inspector → «Rebuild prefab»
  теперь явно обновляет все экземпляры этой модели в активной 3D-сцене с Undo/Redo,
  не только external mesh-файл. 3D → «Ещё…» → «Обновить воксели сцены» обновляет
  устаревшие модели и requeue Surface; source/recipe/transforms не меняются,
  ручные mesh-правки пропускаются, несохранённый Canvas блокирует команду.
  Opening старых объектов совместим
  только с точным прежним winding, не произвольными изменениями mesh.
  Расширенный generator_editing и native Forward+/bottom captures PASS и просмотрены;
  текущие focused/related regressions перечислены в MIGRATION_TEST_PLAN.md.
  Общий refresh targeted + 9 related suites PASS; реальная кнопка и editor history
  проверены в изолированной Forward+ копии, native before/after просмотрены.
  Ручная рабочая 3D-приёмка и профиль на больших деревьях остаются открыты.
  Добавлена «Объекты → Пересобрать всю библиотеку»: все concrete модели/вариации
  по очереди, включая не размещённые, прогресс/отмена в Migration; source/recipe
  не меняются. Undo по одной модели; конфликты пропускаются с объяснением.
  Проверена fixture queue, cancellation, never-built asset и library layout;
  реальная library button/queue/Undo проверены в изолированном Forward+ editor.
  Рабочая очередь 226/226 первоначально дала 196 rebuilt/30 skips. Исправлены false conflicts
  старого indexed/unit-adapter mesh и known opaque VOX ShadowBody, staging UID
  публикация без .uidren; 30 failed assets прошли read-only copy regression с
  сохранением размера/frames/descendants и точным Undo/Redo. Есть retry failed IDs
  в Migration; последующий рабочий повтор пользователем завершён.
  Native isolated no-UID publication/retry button/history и 6 focused/related
  suites PASS; прежние tree external mesh UID warnings остаются отдельными.
  Следующий рабочий прогон дал 205 rebuilt/21 rename Failed (другие IDs).
  Library scan lease теперь откладывает наши scan до конца очереди, ждёт active
  import/scan и делает bounded disk-publication retry без remesh, с conflict
  checks. Real Windows open-file retry и native batch/history PASS. Пользователь
  подтвердил финальный 226/226 rebuilt, 0 skipped: рабочий batch gate принят.
  Конкретный внешний reader прежнего Failed не установлен.
  Оптимизацию voxel-геометрии отдельно обсудить после завершения редактора:
  vertex reuse/greedy meshing/LOD только после Forward+ измерений, не в этом fix.

- Стабилизация публикации файлов после Save: прямые filesystem scan-вызовы
  ember_import переведены в общую editor-only очередь с объединением запросов
  и ожиданием окончания import/scan. Источники, синхронная запись, Undo/Redo,
  Party/Explore и plugin composition не меняются. Новый test_editor_filesystem
  проверяет coalescing, busy wait, source-only escalation, reentrant request
  и уничтоженный filesystem. 13 parse checks и 15 focused/related gates прошли;
  native Forward+ synthetic Canvas Save/Undo/Redo/scene reopen и Party/Explore
  reload прошли с чистым выходом и без ERROR/WARNING. Ручная повторная проверка intermittent parse
  diagnostics в рабочем editor остаётся открытой; это не доказанная поломка
  размера плагина и не повод разделять owners.

- После UI checkpoint `48774a0` пользователь согласовал продолжение кистей:
  [план кистей](EMBER_BRUSH_WORKSHOP_PLAN.md). Default — фиксированная глубина
  за мазок, без повторного наслоения до отпускания; наращивание явно отдельно.
  Точная лепка, следование поверхности/`Только одна грань` и постоянная маска с
  XZ/XY/YZ-ориентацией приняты пользователем. Маска входит в общий Undo и задаёт
  направление объёмной кисти на тонком ребре. Объёмные штампы, путь, линия,
  плоские паттерны и новый детерминированный режим `Россыпь` реализованы в
  существующих owners без новой gameplay/schema границы. Ручная приёмка россыпи
  и итоговый lifecycle/F6 gate открыты. Canvas теперь имеет единое transient-
  состояние для кисти, выделения, переноса, библиотеки/черновика штампа, пипетки
  и выбора рабочей области: один основной инструмент подсвечен за раз, `Esc`
  возвращает последнюю кисть, а смена инструмента сначала отменяет черновик.
  Следующий input/brush-срез реализован и ждёт ручной приёмки: камера получает
  RMB/MMB/колесо поверх активного штампа без потери черновика, pitch расширен до
  осмотра снизу, pan работает в плоскости экрана, zoom привязан к курсору.
  `Сгладить` имеет режимы `Ступени` и `Общий уровень` с сохраняемым тоглом
  `Обрабатывать ямки`; широкий LMB-preview использует дешёвую draft-сетку, а
  медиана общего уровня считается без сортировки полного массива. Точная сетка
  достраивается по отпусканию. `Рельеф` разделён на прежнее явное `Наращивание`
  и новый детерминированный `Генератор`: `Почва / Гребни`, высота, размер формы,
  детализация (`лёгкие` дают редкие мягкие перепады до 1–2 вокселей, прежние
  `мало / средне / много` сохранены), направления `Оба / Вверх / Вниз` и
  сохраняемый `Другой вариант`.
  Рисунок закреплён в координатах модели, считается от pointer-down поверхности
  и не зависит от частоты input-событий. Targeted sculpt/workflow/layout/backend
  gates прошли; визуальная проверка ощущения и профилирование на Причале открыты.

- Нативная переработка **Воксельной мастерской** выполнена в UI-ветви рабочего
  дерева без изменения gameplay/schema/renderer. Пользователь принял композицию
  и перенос длинных подсказок из правой панели в footer, постоянную палитру и
  нижнюю полку объектов, включая сохранение превью при смене фильтров; полный
  ручной сценарий Причала ещё открыт. Scoped Theme сохраняет editor fonts/icons/DPI, но задаёт
  единые графитовые кнопки, cyan hover и amber active/primary; он не влияет на
  остальные окна Godot. `Части` разделены на локальные `Выделение / Группы / Вид`;
  длинный общий скролл и дублирующие справочные абзацы убраны. Палитра со всеми
  действиями закреплена снизу слева и не зависит от `Части / Библиотека` справа.
  Образцы палитры имеют отдельную theme variation и больше не наследуют tint
  editor-кнопок: цвет внутри swatch показывает точное palette data, включая
  pressed/hover состояния.
  В Object Canvas поле `Объект` переименовывает выбранный экземпляр сцены через
  общий Undo/Redo, не меняя display name, model ID или файлы voxel-модели.
  Для объектов сцены добавлена отдельная постоянная нижняя полка `Объекты`:
  поиск, фильтры `Все / Готовы в Godot / Ожидают переноса`, крупные карточки,
  выбранное превью и закреплённые команды `Поставить в сцену` и
  `Редактировать шаблон`. Готовая модель открывается в общем Canvas напрямую;
  legacy-модель сначала переносится в Godot Resource. Интерфейс явно предупреждает,
  что правка шаблона затронет все его экземпляры. Полка открывается
  из 3D-toolbar или Ember Migration, не закрывает контекст модальным окном и
  явно пишет место добавления. Текущая семантика не изменилась: рядом с выделенным
  объектом со смещением +X, иначе у player_start/начала Map; ghost под курсором —
  отдельный будущий срез, если будет принят как следующий UX-шаг.
  [План UI](EMBER_EDITOR_UI_REWORK_PLAN.md) фиксирует owners,
  результат, captures и приёмку. Текущий UI-срез готов к Git checkpoint;
  открыты только явно перечисленные более широкие ручные gates.

- Объёмные штампы реализованы; базовое размещение пользователь подтвердил,
  ручная приёмка новой россыпи открыта. В Мастерской
  `Штамп` — основной инструмент слева; справа вкладка `Библиотека` с карточками
  и производными in-memory миниатюрами. Создание скрыто за `+ Новый источник`,
  а `Выбрать / Редактировать` закреплены под прокручиваемыми карточками.
  Параметры режима, оси, поворота, зеркала и опоры выбираются напрямую короткими
  сегментами вместо раскрывающихся списков. Выделение → название → `Сохранить как
  штамп`; карточка → `Выбрать`. ЛКМ ставит опору, XYZ уточняют положение,
  Enter применяет один отпечаток и оставляет штамп выбранным. Первый Esc отменяет
  текущий черновик, второй возвращает последнюю кисть. Повороты 90°, отражение по одной оси, три
  опорные точки. «Добавить» сохраняет занятое, «Заменить» переносит цвет/каналы;
  пустоты не стирают. Один Undo, новые voxels наследуют active part/Добавленное.
  «Редактировать модель штампа…» открывает прежний Canvas с save/discard.
  Geometry — прежние voxel_models/*.tres; presets — content/editor/voxel_stamps.
  До 32768 vox, одинаковая плотность и общие настройки материала; маска кисти
  на время размещения сохраняется, но явно приостанавливается и восстанавливается
  с совместимой кистью. Изоляция и скрытые группы несовместимы, lock сохраняется.
  Новый layout gate и stamp + selection interaction/fragment/merge/extraction/
  object canvas прошли; native Forward+ 1280×720/1600×900 captures проверены.
  16384 / 131072 cells: plan ~60–100ms; путь из 31 точки и россыпь из 25 точек
  планируются меньше чем за 1ms на тестовой машине, без remesh на каждый input.
  `Путь`, `Линия`, шаг и 2D-паттерн с глубиной реализованы. `Россыпь` добавляет
  поперечное смещение, локальную привязку к поверхности, случайные повороты 90°
  и `Другой вариант` при стабильном preview/commit. Опциональное `Облегать рельеф`
  укладывает целые столбики штампа по исходной поверхности с пределом 1–8 vox;
  цвета, каналы, part provenance и шесть направлений сохранены. До Enter
  Ctrl+Z/Ctrl+Shift+Z правят только шаги черновика, после Enter весь мазок — одна
  Resource Undo-команда. Синтетические 25 штампов 8×4×8 с облеганием на модели
  131072 cells планируются примерно за 25.5ms. Набор из нескольких штампов и
  конверсия плотности остаются впереди.
  Объёмный штамп также получил явный третий режим `Вдавить`: его высота зеркально
  становится глубиной удаления внутрь первой грани. Очищаются voxel-каналы и part
  provenance; поддержаны `Один`, `Путь`, `Линия`, `Россыпь`, шесть нормалей,
  облегание рельефа, атомарный lock/границы и одна Undo-команда. Розовый preview
  показывает удаляемый объём. Снежный бортик и уплотнение материала не входят.
  UX-полировка унифицировала размещение: одиночный клик, отпускание пути и вторая
  точка линии создают только черновик; Enter применяет, Esc отменяет, а
  Ctrl+Z/Ctrl+Shift+Z правят повторяемые отпечатки до commit. Полный ghost следует
  мыши ещё до первого клика, чужие параметры лепки скрываются, настройки каждого
  пресета помнятся в текущем Canvas. Библиотека штампов является navigation-only:
  ЛКМ по Canvas в ней не запускает оставшуюся кисть. Неактивное обычное выделение
  хранится без оранжевой заливки; активная маска показывает только контур, а в
  несовместимом режиме — статус `Маска сохранена · не действует`. Ручная проверка ощущения остаётся открытой;
  возможный общий `Быстрый режим` пока только отдельное будущее решение.
  Склейка и совмещение сеток подтверждены пользователем перед этим этапом.

- Первый модульный генеративный источник реализован как `Камень` внутри общей
  библиотеки штампов. Editor-only рецепт хранит seed, размер XYZ, неровность,
  сколы и плотность; его производная геометрия остаётся обычным
  `EmberVoxelModelResource`. Рецепт можно повторно открыть и изменить, не меняя
  уже размещённые воксели. После сохранения камень использует без специальных
  веток прежние `Один / Путь / Линия / Россыпь`, облегание, повороты, Enter и
  Undo. Семплирование линии, пути и посадки россыпи вынесено в общий чистый
  `ember_voxel_brush_placement.gd`; прежние Stamp API оставлены совместимыми.
  Генератор сохраняет один связный объём и устойчивое основание. Targeted
  generator/stamp/pattern/layout gates и ручная оценка формы остаются текущей
  точкой приёмки; большой камень 32³ строится примерно за 60 ms на тестовой машине.
  Рецепт камня теперь может готовить 1–8 детерминированных форм и разброс их
  размеров до ±50%. Одиночный штамп, путь и линия сохраняют основную форму;
  штатная `Россыпь` выбирает форму для каждой точки по своему seed и показывает
  число форм в активных параметрах. Производные варианты не сериализуются и не
  попадают в gameplay: они один раз строятся в editor-cache при выборе карточки.
  Старые рецепты без новых полей остаются одноформенными. Максимальный набор из
  восьми форм до 32³ готовится примерно за 290 ms; движение preview его не
  перестраивает. Ручная проверка разнообразия и расстояния между камнями открыта.
  Второй provider добавлен в ту же систему как `Дерево`: recipe задаёт высоту,
  толщину ствола, размер/неровность кроны, ветвистость, отдельные цвета ствола и
  листвы, плотность и тот же набор из 1–8 форм. Provider строит физически связные
  ствол, ветви и составную крону с нижним контактом; библиотека показывает дерево
  сбоку, а не бесполезным видом сверху. `Один` сажает primary tree, штатная
  `Россыпь` создаёт детерминированный лес тем же общим plan/Enter/Undo. Восемь
  максимальных деревьев до 32 vox высотой готовятся примерно за 220 ms. Сезоны,
  ветер, gameplay-компоненты и смешивание разных пород в одном рецепте не входят.
  Третий stamp-provider добавлен как `Куст`: высота 4–24 vox, размах, число
  стеблей, пышность и неровность листвы, отдельные цвета и 1–8 форм. Низкая
  широкая масса листвы и 6-связные ступенчатые стебли дают читаемый куст, а не
  уменьшенное дерево; боковая миниатюра показывает до четырёх вариантов. После
  сохранения он использует ту же одиночную посадку и `Россыпь`, Enter и один
  Undo. Максимальный набор готовится примерно за 190 ms; ручная оценка диапазона
  силуэтов и посадки на рельеф открыта. Четвёртый stamp-provider — `Трава`:
  редкие двухцветные пучки высотой 2–12 vox, размах, 2–16 травинок, разброс
  высоты, наклон и 1–8 форм. Первый выбор открывает штатную `Россыпь`; каждый
  пучок корнем привязывается к локальной верхней поверхности и остаётся
  вертикальным. Боковые грани отклоняются, а несовместимое column-conform скрыто.
  Grass source хранит явную нулевую collision-маску. Общий Stamp-plan теперь
  корректно переводит legacy-землю в смешанную маску: земля остаётся физической,
  трава — проходимой, обычные старые штампы на masked target — физическими.
  Восемь максимальных форм готовятся примерно за 1 ms; ручной визуальный и F6
  gate открыт. Смешанная россыпь нескольких пресетов остаётся далее.
  После завершения серии генеративных этапов отдельный UX-срез двухэтапного
  выделения реализован и ждёт совместной ручной приёмки; он не меняет owners
  генераторов или gameplay schema.

- После ручной проверки большой tree-base пользователь согласовал полировку
  по широкой кроне/сильным развилкам. Recipe v2 `Крупные формы` добавляет три
  формы кроны, толщину/сужение/изгиб ветвей, начало ветвления, размер и
  приплюснутость пучков, сомкнутость и корневые выступы. Старые recipes без версии
  остаются classic; уже созданные модели не изменяются. Preview закреплён справа,
  параметры скроллятся слева; точная генерация только по кнопке. Художественная
  приёмка новой формы открыта. Свет/шейдер по pixel-art refs остаются после editor.
  Автопроверка нового среза: восемь suites PASS; native Forward+ dialog capture
  1280×720 просмотрен. Художественная приёмка и живой editor input ещё открыты.

- Большие деревья отделены от штампов и добавлены в существующую полку 3D
  `Объекты` как обычные native voxel-модели высотой 64–256 vox. Кнопка
  `+ Большое дерево` открывает явную генерацию: высота, толщина ствола, размах
  кроны, ветвистость, неровность, плотность листвы, два цвета и seed. Preview
  строится только по кнопке и является той же подготовленной геометрией, которая
  затем сохраняется и ставится в `Map/Props`; параметрические правки до этого не
  пишут файлы. Рядом с `.tres`/prefab сохраняется editor-only recipe; команда
  `Ещё… → Создать вариант из рецепта…` создаёт новый независимый объект, не
  меняя поставленные деревья. Готовый объект открывается прежним Canvas.
  Resource schema 6 добавляет необязательный `collision_voxels`: пустой канал
  сохраняет старое правило «всё занятое физично», а у дерева коллизию имеют
  ствол и толстые ветви, но не листья. Перенос, crop, split, merge, assembly,
  growth, dirty/discard и Undo сохраняют канал; новые вручную долепленные voxels
  физичны по умолчанию. Генерация 64/128/256 занимает примерно 12/57/190 ms,
  точный prefab 256 — около 2.4 s на тестовой машине. Forward+ capture проверен;
  ручная оценка силуэта, размера в сцене, Canvas и F6-коллизии открыта. Маленькое
  дерево 8–32, куст 4–24 и трава 2–12 остаются штампами для россыпи. Первый
  профиль большого объекта — лиственное дерево; породы, ветер, сезоны и forest
  scatter не входят. После завершения редакторских этапов отдельно обсуждается
  принятый по визуальным референсам срез материалов, света и мультяшных теней;
  текущие генераторы не подменяют этот будущий shader/light contract.

- Для склейки добавлено явное «Совместить сетки». Основная деталь неподвижна,
  остальные сдвигаются к ближайшей ячейке общей сетки только в preview.
  Голубой ghost показывает прежнее положение, подписи — Δ XYZ в вокселях.
  До «Склеить» сцена не меняется; одна Undo возвращает исходные дробные позиции.
  При смене основной детали согласие на выравнивание сбрасывается. Это не
  притягивание поверхностей и не округление поворотов/масштаба. Проверены
  смещения пары пользователя, 16/32, cancel, Undo/Redo, save/reopen и Forward+.
  Новая ручная проверка: выбрать нижний блок основным, включить совмещение,
  проверить ghost, склеить и отменить. Авторский Причал не изменялся.

- Склейка и разбор реализованы, ручная приёмка открыта. В 3D: «Ещё… →
  Склеить voxel-детали…» / «Разобрать склейку…». 2–32 обычных native-детали
  одного родителя, согласованная сетка, относительные повороты 90°, плотности
  16/32 → 32. В preview выбирается основная деталь; красным показаны перекрытия.
  Resource schema 6 хранит отдельные merge_parts + voxel_part_ids, не группы
  выделения. Новые воксели → выбранная часть либо «Добавленное»; удалённые
  при разборе не возвращаются. Перенос/копия, расширение, crop и секции сохраняют
  принадлежность. Сохранить/отменить Canvas до команды сцены; Undo/Redo и
  immutable-файлы используют прежний owner. Проверены targeted merge, связанные
  regressions и native Forward+ preview; тестовые данные только user://.
  Для 131072 занятых ячеек: расчёт ~0.33 с, разбор ~0.30 с, mesh/collision ~0.50 с,
  публикация ~0.85 с (синтетический плотный участок, не замер всего Причала).
  Большие операции пока синхронные; пауза явно обозначена. Неподдержанные
  transforms/материалы/поведение/вода отклоняются, скрытого выравнивания нет.

- Отделение фрагмента реализовано: «Вырезать в новый объект…» / «Скопировать
  в новый объект…» в панели выделения. Сначала Save Canvas (маска сохраняется),
  затем подтверждение операции. По умолчанию остаёмся в обновлённом Canvas;
  «Перейти в 3D к новой детали» включает возврат к Fragment. Выбор помнится
  до закрытия workspace; camera/view сохраняются, чистый Canvas следует Undo/Redo.
  Работает для выбранного экземпляра и общего Canvas секций: новая деталь —
  сосед исходного объекта/сборки, положение и collision сохраняются.
  One Undo восстанавливает ссылки и убирает деталь; новые файлы не удаляются.
  Targeted extraction + пять связанных regressions и native Forward+ пройдены.
  Ручная приёмка отделения открыта. Surface, shared-edit, собственные источники
  света и нестандартные physics/render overrides явно отклоняются.

- Прежняя «Рамка по поверхности» переработана в принятое «Двухэтапное
  выделение». Первая грань фиксирует плоскость, первый LMB-drag задаёт плоскую
  область, а движение после отпускания регулирует глубину внутрь по нормали.
  Второй клик или Enter подтверждает; SpinBox даёт точное число. До второго
  подтверждения прежнее выделение и Resource не меняются. Esc/смена инструмента
  отменяют draft, Shift/Ctrl фиксируются до первого нажатия, итог создаёт одну
  selection Undo-команду. Общая математика поддерживает шесть направлений,
  ограничивает глубину границей grid и имеет вертикальный screen fallback для
  почти фронтальной грани. Pure и interaction gates прошли; ручная Forward+
  приёмка сверху/сбоку/снизу и проверка ощущения открыты. Обычная экранная рамка
  и перенос остаются прежними; рельеф автоматически не огибается.

- Работа с фрагментами Canvas, фаза 1 + UX-коррекция: рамка протягиванием мыши,
  видимая поверхность / насквозь, существующие Shift/Ctrl add/subtract.
  Курсор выбора обводит конкретный воксель вместо показа кисти. Перенос/копия/
  повороты 90° теперь прямо в Canvas: ghost, стрелки X/Y/Z с voxel snap,
  числовые поля в панели; Enter применяет, Esc отменяет. Один Undo,
  сохранение цветов/каналов/групп. Прежний модальный dialog не является UI-входом.
  Защищённые воксели, перекрытие, выход за холст/region/slice отклоняются целиком.
  Семь автоматических gates пройдены, native Forward+ screenshot проверен;
  ручная приёмка обновлённого взаимодействия открыта.
  Выделение и UX подтверждены пользователем. Отделение в объект добавлено выше;
  до закрытия всего этапа нужна его ручная приёмка.

- Поверхность прохода: реализован первый прямоугольный helper для исследования.
  13 сентября отдельный диалог заменён нижней панелью «Опора»:
  «Ещё… → Поверхность прохода…»: размер, положение, наклон и черновик
  прямо в основном 3D-окне со свободной камерой, предупреждения выступов. Обычный
  StaticBody3D сохраняется в сцене; сетка видна только редактору. Undo/Redo,
  save/reopen и проход настоящим контроллером проверяются test_walk_surface.
  Пользователь подтвердил работу панели в основном 3D-окне и voxel-кистей.
  Targeted/related и disposable native Forward+ editor functional PASS;
  orbit/zoom/Apply/Undo/Redo/save/Cancel и адаптивная компоновка 720p/900p проверены.
  Fresh-copy UID/teardown diagnostics отдельно описаны в migration gates.
  Следующий принятый срез 13 сентября реализован: «По геометрии» создаёт
  voxel-разметку верхнего настила; короткие щели закрываются только между
  исходными опорами. Кисти «Убрать»/«Вернуть» работают по целым vox-клеткам,
  «Вернуть» ограничено исходной генерацией. Отмена/повтор мазка — в черновике,
  Apply — одна сценовая операция; сохранённый scriptless StaticBody3D содержит
  разметку в metadata и объединённые BoxShape3D. Положение раскрывается отдельно.
  Mask/controller/serialization и 8 связанных headless gates PASS; native brush
  flow PASS в disposable editor fixture: erase/restore, draft Undo/Redo,
  orbit с активной кистью, compact/expanded layout 720p/900p, Apply/save/Cancel.
  Прежние UID/teardown diagnostics остаются отдельно. Ручной gate на авторском
  мосту принят пользователем; клеточные высоты боя автоматически не обновляются.
  После отчёта о левитации найдены две совпадающие активные опоры в сохранённом
  пилоте Map/Props: WalkSurface и более обрезанная WalkSurface_new. Physics/real
  EmberPlayer probe без записи подтвердил: старый helper держал героя на Y≈1.958;
  после отключения в fixture герой стоит на настоящей балке Y≈−0.042.
  Теперь source-open переиспользует единственную связанную активную опору,
  неоднозначность не создаёт новую. Совпадающие mask/source/pose опоры явно
  показаны в панели; «Оставить эту опору» применяет черновик и отключает дубликат
  одной Undo/Redo action, сохраняя оба узла. Пользователь подтвердил «все работает»
  после исправления: удалённые клетки больше не держат героя над балкой.
  Gameplay-срез принят; следующий этап пользователь продолжает в существующем
  редакторском чате. В checkpoint входят код, tests/docs и сохранённый test_pier;
  локальный .codex/config.toml и Mira drafts остаются вне коммита.
  Предыдущая сборка/размножение приняты пользователем.

- Режим работы принят 10 сентября: основной агент сам исследует, меняет код и
  проверяет результат в текущем thread. Субагенты, включая read-only/review, —
  только по отдельной явной просьбе пользователя для конкретной задачи;
  прежняя схема обязательного делегирования отменена. См. AGENTS.md и workflow.

- Основной Ember editor остановлен на принятом stop-line v2.56.1. Общая полировка
  не продолжается без конкретного production workflow, который редактор пока не
  позволяет выполнить.
- Каноническая стартовая глава зафиксирована в GDD: портовый остров, аномалия,
  особняк, три направления расследования, дневник деда, ночное проникновение и
  древний комплекс под маяком. «Затопленная кузница» сохраняется как
  неканоническая лаборатория уже принятых механик.
- Для Миры утверждены текущие костюм, палитра, вид спереди/сзади и пропорции под
  одеждой. Исходные листы и границы решения хранятся в
  `docs/art/characters/mira`; это ориентир для следующих художественных итераций,
  а не готовый runtime-ассет или финальный production art lock.
- В контентном проходе главы зафиксированы сцена спасения, обе дороги в комплекс,
  общий порядок помещений, обычный бой, исследователь, ограниченное разделение
  пары, водная и воздушно-тепловая головоломки, авторские разрушаемые секции,
  многоклеточные противники с частями тела и интерактивные объекты боя. Финальный
  страж встроен в центральную конструкцию; две его функциональные части создают
  окна для последовательной стабилизации водного и воздушно-теплового узлов, а
  второй решённый узел завершает бой восстановлением равновесия. Форма,
  разумность и общение со стражем остаются открытыми. Эти новые правила пока
  являются дизайном: runtime, Resources и schema под них ещё не менялись.
- 9 сентября 2026 целиком принята спецификация graybox главы: размеры диорам,
  арена 12×10 со стражем 3×3, целевой маршрут 76–85 минут, планируемые флаги,
  состояния сцен и команды камеры/звука/затемнения/параллельного выполнения,
  обязательные водные действия с механизмами без MP за обычное боевое действие,
  минимальные assets/UI-состояния и шесть этапов реализации. Контентный план
  готов к техническим контрактам; реализация и реальная приёмка ещё впереди.
  Точный баланс проверяется в graybox; финальные art/UI, литературные реплики
  и открытые сюжетные загадки этим решением не закрываются.
- Combat Lab доведён до v2.64.4: вертикальные поля, камера и preview;
  лабораторная партия и save v2; характеристики, предметы, XP, парные приёмы;
  редактор боевого контента; поэтапный выбор действий; общий auto-approach для
  непарных hostile/support/heal/item/cell/lift-команд; battle-only удержание
  поднятой цели.
  Исправляющий срез ограничил cell-target preview реальными MOVE + range,
  сохранил цель подъёма на месте до подхода и сократил measured 16×12 cell-query
  примерно с 378 мс до 12 мс без смены schema.
- Боевая основа переведена на композицию без второго resolver: пять статусов
  стали canonical `.tres`, а правила статусов, урона и reusable effect steps
  вынесены из фасада `EmberCombatPrototype` в чистые внутренние модули. Публичные
  `preview/commit`, 21 действие, 7 бойцов, AI, RNG и save v2 не менялись;
  границы runtime snapshot/result теперь валидируются до применения результата.
  Редкий movement-only AI pursuit приведён к полному result-контракту, а его
  presentation запускается только после успешного commit: враг больше не
  возвращается в исходную клетку и не оставляет очередь на своём ходу.
- В checkpoint `4569f64` зафиксирован единый клеточный ActionPlan: живой hover,
  movement/cast envelope, точный stop/fallback, общий вход player/AI-команд,
  обратимый presentation-подход и подъём. 24/24 combat/battlefield/encounter/
  party/save scripts прошли, обычный Forward+ smoke обоих полей выполнен, а
  основной сценарий принят пользователем вручную. Завершения поднятия перенесены
  из отдельной панели в кольцо у носителя; позиция, фокус и читаемость кольца
  дополнительно приняты пользователем в реальном бою 8 сентября 2026.
- В checkpoint `4951f4e` закрыт production lifecycle поражения:
  неудачная попытка не может применить HP/MP, предметы, флаги или награды к миру;
  Retry восстанавливает предбоевые party/inventory/deployment и создаёт новый
  RNG seed; вместо возврата с поражением можно выбрать один из трёх ручных
  слотов или автосейв. Новый сквозной gate и связанные transition/result/party/
  save tests прошли; 27/27 связанных regression scripts зелёные. Обычный
  Forward+ на RTX 5070 дошёл до load-only окна без renderer/script errors, а
  in-engine capture подтвердил компоновку и видимый focus первого слота.
  Ручная приёмка мышью/геймпадом подтверждена пользователем 8 сентября 2026.
- В checkpoint `e4b6b7e` предбоевая расстановка расширена одним
  сохраняемым порядком группы в save v2 без координат и новой schema. На поле с
  extra `party_deployment_cells` preset применяется до UI: компактное ready-окно
  предлагает начать бой или открыть детальную расстановку; зона и hero tools
  появляются только во втором режиме. Reset возвращает persisted strategy,
  Defeat Retry — точный confirmed placement с новым seed, обычный Lab Reset —
  strategy и ready. Exact-N `colored_crossing_demo` игнорирует preset и остаётся
  фиксированным. Исправлена stale staged-проекция первого/current героя; regression
  проверяет его реальную 3D-позицию. Все 20 combat tests и связанные save,
  inventory, party progression и Battlefield gates зелёные; обычные Vulkan
  Forward+ captures ready/inventory прошли. Ручная input/save-reopen приёмка
  подтверждена пользователем.
- Workflow Phase A/B создаёт короткую точку входа и отделяет актуальные
  канонические документы от истории, сохранённой в Git. Gameplay, Resources,
  schema и runtime эти фазы не меняют.

Последний подтверждённый baseline для checkpoint `20685ac`: прошёл
`python tools/test_vox_axes.py` и полный набор из 82 `tools/test_*.gd`.

## Следующий игровой срез

Группировка и повторное дублирование реализованы, ручная приёмка ожидается:
«Ещё…» → «Собрать в группу» / «Разгруппировать» / «Дублировать со смещением…» /
«Повторить дублирование». Группа — 2–32 обычных native voxel-детали одного
родителя, без склейки геометрии. Разбор сохраняет текущие transforms и правки;
внешние сохраняемые NodePath/node-ссылки и сигналы блокируют перенос. Дублирование
одной детали создаёт 1–32 linked-копии с мировым voxel-шагом и preview;
повтор добавляет одну копию выбранной детали с прежним мировым шагом.
Каждая операция — один Undo/Redo; source/prefab не записываются. Новая группа
произвольно наклонённых деталей пока не открывается общим Canvas.

Точная voxel-расстановка 2.3 принята пользователем 10 сентября. Выбранный
обычный voxel-объект либо существующая сборка из 2–32 native частей открывается
через «Точная расстановка…». Диалог показывает мировые XYZ и смещения в вокселях,
общую сетку с шагом 1 и варианты по фактическим размерам voxel-рёбер деталей.
Привязка двигает выбранную опорную точку: центр, нижний угол либо свои координаты;
для одной модели свои XYZ являются source voxel-координатами. Доступны числовые
повороты и ±90° по всем осям. Полный исходный basis сохраняется без скрытого
выравнивания масштаба/наклона; transformed parent учитывается через affine
transform. Preview — read-only копия выбранного и окружения, сцена меняется только
одной Undo/Redo-командой после «Применить», sources/prefabs не записываются.
Склейка и Canvas произвольно наклонённых деталей остаются следующими контрактами.
Targeted/related gates и native Forward+ layout 1280×720/1600×900 PASS;
пользователь подтвердил работу точной расстановки в editor.

Общий Canvas сборки: выбрать группу секций → «Объект / сборка в Canvas».
`ember_voxel_assembly_session.gd` координирует существующие object sessions;
общий draft не сохраняется отдельным источником. Мазок пересекает границы,
изменённые секции публикуются независимыми копиями, затем обновляются вместе
одним Save Undo. Неизменённые sources не записываются. Ошибка подготовки/записи
не меняет сцену; уже записанные новые копии остаются для восстановления.
Поддержаны состыкованные native-секции одной плотности/ориентации, полная общая
Y, 2–32 части, до 524288 ячеек. Отдельные повороты/зазоры/перекрытия и вода
отклоняются, расширение общего холста пока отключено. Существующие группы после
разрезания поддержаны без нового marker/schema. Общий мазок и save/reopen приняты
пользователем 10 сентября; Forward+ общий preview 12 секций также проверен.

Оптимизация/секции: убраны повторные baseline-сборки внутри Canvas Save.
Для объектов >131072 ячеек добавлен session-only cache внутренних Y-участков;
на выходе тот же mesh/коллизия и прежний source schema. Cache освобождается
при смене объекта. Замер 192×10×256: Save 12/14 с → 6.7/5.1 с (два прохода,
headless; не обещание UI FPS). Коллизия и сериализация пока пересобираются целиком.
«Разрезать на секции…»: native voxel-only, XZ 32/64/128, полная Y, 2–32 части,
до 524288 исходных ячеек, preview границ/количества, отдельные sources/prefabs,
сохранение world placement и каналов, один Undo/Redo. Вода/свет/сложное поведение
и отдельные overrides отклоняются явно. При ошибке записи сцена не меняется,
уже записанные новые файлы оставляются для восстановления. Примитивы сначала
преобразовать; прямой рез oversized StoneQuay ещё не поддержан.
6 focused/related tests PASS; окно секций проверено в Forward+ на реальном
источнике TimberPier без изменения авторской сцены. Разрезание и последующее
открытие сборки приняты пользователем 10 сентября.

Большие объекты: порог создания/конверсии и расширения холста поднят до
524 288 ячеек; выше 131 072 предпросмотр формы требует явного разрешения.
Параметры изменены — разрешение сбрасывается. Расширение показывает предупреждение
перед применением. Большой TimberPier разрезан на 12 секций и сохранён в авторской
сцене пользователем; прежний автоматический Forward+ gate также пройден.

Уточнение 2.2: при несовпадении transform простой формы и её коллизии команда
«Форму в voxel…» предлагает «Совместить коллизию с моделью», показывает точное
локальное смещение и переносит только transform коллизии одной Undo-командой.
Размеры shape и остальные ограничения не обходятся. Targeted conversion test и
parse плагина PASS; ручная проверка кнопки на TimberPier ожидается.

9 сентября принят к реализации план «Воксельная мастерская окружения» в
`docs/EMBER_PRODUCT_PLAN.md`. Наполнение пролога приостановлено; тестовый Причал —
площадка приёмки инструментов. Выполненный этап 1: обычный voxel-объект из сцены →
Canvas → независимое сохранение выбранного экземпляра по умолчанию → обновлённые
геометрия и коллизия. Явные linked/independent copy и shared edit, без второго
source owner. Реализация выполнена; 13/13 focused/related headless gates прошли,
10 сентября пользователь подтвердил работоспособность после исправлений Save/UI
и разрешил следующий этап. Текущий срез 2.1 — создание пустой модели, блока,
цилиндра и сферы; полный empty→solid→empty lifecycle. Команда редактора
«Ember: Новая voxel-форма…» даёт явный предпросмотр и создание с открытием Canvas.
Создание подтверждено пользователем. По его обратной связи выполнен проход:
«+ Объект» / «Объект в Canvas» на панели 3D, создание из Canvas и
«Расширить холст…» для объекта. XZ растёт симметрично, Y вверх, без изменения
world-геометрии; одна Undo-команда, save/reopen/discard. До 524 288 ячеек,
без уменьшения/водной заливки. Исправлены подмена live SceneState read-only
проверками prefab и публикация экземпляра из устаревшего prepared PackedScene.
Корректирующий проход принят пользователем 10 сентября. Следующий небольшой
проход добавляет «Показать окружение», видимость фона 0–100% и «Обновить окружение»
в Object Canvas. Фон — read-only Mesh/MultiMesh snapshot открытой сцены без
скриптов/физики, точное относительное совмещение с draft; свет остаётся Canvas.
5/5 focused/related gates прошли, Forward+ Причала: 68 visuals около 1.5 мс,
окружение принято пользователем. Реализован этап 2.2: команда «Форму в voxel…»
для BoxMesh, закрытого равного цилиндра и полной сферы; preview исходник/voxel,
один Undo, совпадающая primitive collision заменяется voxel collision, позиция
и габариты по параметрам сохранены явно показанной подгонкой масштаба.
5/5 focused/related gates и actual-editor functional pass; ручная приёмка
конверсии впереди. Расстановка/привязка/опорная точка 2.3 теперь реализованы
отдельной preview-командой и ожидают ручной editor-приёмки.
Forward+ capture на RTX 5070 и открытие test_pier в отдельной editor-копии прошли
без ошибок; это не заменяет ручное управление в рабочем редакторе.
После ручного отчёта исправлены editor-placeholder Save, несжимаемый Canvas и
отсутствующие placement_id пяти props Причала. Отдельный actual-editor fixture
проверил функциональные assertions Canvas Save/Undo/Redo/reopen и сжатие
1500→1000→1500. Forward+ center 1084×741 проверен: Save/sidebar/Inspector
укладываются, prefab актуален. Полный чистый fresh editor lifecycle не подтверждён:
intermittent dependency diagnostic, ошибка автоматического выхода и незавершённый
последний smoke описаны в MIGRATION_TEST_PLAN. Пользовательская проверка Save/UI
подтверждена 10 сентября; это не закрывает отдельный долг автоматического smoke.
Несохранённый черновик после старой
ошибки сначала пробовать сохранить через hotreload, не закрывая редактор.
В Причале начинать с `BarrelA`: native source прошёл preflight.
`CargoA` имеет несовпадающий legacy baked mesh и пока
получает безопасный отказ без пересборки. Новый Canvas-сеанс по умолчанию делает
новый source при первом Save; следующие Save этого сеанса сохраняют тот же ID.
Общую модель можно сохранять после закрытия других вкладок сцен; автоматическое
обновление их несохранённых экземпляров не заявлено. Затем склейка/разделение,
оба вида кистей, вода/дно. Принятые решения не переоткрываются.

По отдельному согласованному контракту добавлена `scenes/test_pier.tscn`:
F6 запускает свободный Причал с ГГ и Мирой, без боя и сюжетного сценария.
Геометрия и коллизия редактируются в самой сцене; это graybox с существующими
voxel-грузами и простыми формами окружения. F5 и лаборатории не переключены.
Сохранения Причала изолированы в `user://ember-test-pier-v2`; меню использует
прежний Explore/save owner, повторный запуск восстанавливает собственное место.
Targeted gate и Forward+ capture проходят; ручная прогулка, края, камера,
Tab/сумка/Q/E и меню save/reopen ждут пользовательской приёмки.
При первом открытии обнаружено legacy-чтение в editor Surface selector;
исправлены автоматическая привязка, explicit Surface open и fallback размеров.
Причал без voxel Surface не предлагает Surface selection и не ищет JSON в JOI.
После обновления повторить открытие сцены/выбор Map и F6.
Это не закрывает ручной боевой gate активной группы ниже.

Контентный план канонического graybox принят. 9 сентября согласован технический
Task Contract активной группы 1–4 героев в существующих Explore/Party/save owners;
реализация выполнена, 34/34 связанных headless gates и pack contract прошли.
Обычные Forward+ запуски followers и defeat/retry завершились с exit 0 на
RTX 5070; просмотрены captures пары в мире, сумке, ready и после Retry.
Контракт остаётся открытым до ручной Forward+ приёмки одиночки/пары,
сумки/Tab/Q/E, боя/Retry и save/reopen.
Затем — контракт редактируемых квестов,
действий и сцен; дальнейшая сборка следует шести принятым этапам GDD.
Реализация ограничена согласованной активной группой; числовой баланс встречи
уточняется в пробном graybox-бою, полный маршрут требует сквозной ручной приёмки.

До канонического боя парой требуется завершить текущий контракт активной группы
и её сохранения без второго party/save owner. Парный auto-approach
остаётся отдельным будущим решением: парные техники по-прежнему используют
собственный authored-радиус партнёра. Большой player-facing UI согласуется позже
отдельным HTML-прототипом перед переносом в Godot.

## Ключевые owners текущего боевого среза

- `scripts/prototypes/ember_combat_prototype.gd` — чистый resolver,
  preview и commit;
- `scripts/prototypes/ember_combat_status_resource.gd` и
  `content/combat/statuses/*.tres` — canonical статусы;
- `scripts/prototypes/ember_combat_status_rules.gd`,
  `ember_combat_damage_rules.gd` и `ember_combat_effect_rules.gd` — внутренние
  чистые правила, вызываемые единственным resolver;
- `scripts/prototypes/ember_combat_grid.gd` — dense Battlefield, navigation,
  staged selection и общий positional auto-approach;
- `scripts/prototypes/ember_combat_lab.gd` — контроллер выбора, targeting и HUD;
- `scripts/prototypes/ember_combat_grid_3d_world.gd` и
  `scripts/prototypes/ember_combat_grid_view.gd` — представление поля;
- `scripts/prototypes/ember_combat_action_resource.gd` и
  `scripts/prototypes/ember_combat_unit_resource.gd` — authoring-контракты;
- `scripts/ember_explore_state.gd` — единственный mutable/save owner мира;
- `scripts/ember_party_state.gd` — чистая нормализация и прогрессия партии;
- `scripts/ember_combat_transition.gd` — защищённая транзакция мир ↔ бой.

Перед изменением проверить эти пути через `rg`: список помогает найти вход,
но не гарантирует, что owner не изменился после последнего обновления файла.

## Ближайшие проверки

Для активной группы расширены save/progression/followers/inventory/encounter,
production transition, result и Retry gates; подробности в migration test plan.
Безопасные opt-in `-- --capture-active` у party followers и defeat Retry tests
дают Forward+ изображения пары, не меняя пользовательские сохранения.

Для текущего v2.64.4 regression gate минимум:

- `tools/test_combat_prebattle_deployment.gd`;
- `tools/test_combat_action_plan.gd`, `tools/test_combat_grid.gd`;
- `tools/test_combat_defeat_retry.gd`, `tools/test_combat_encounter_transition.gd`;
- `tools/test_combat_prototype.gd`;
- `tools/test_combat_status_resource.gd`, `tools/test_combat_effect_library.gd`;
- `tools/test_combat_lab.gd`;
- `tools/test_combat_items.gd`, `tools/test_combat_personal_actions.gd`,
  `tools/test_combat_vertical_animation.gd`, `tools/test_combat_vertical_profile.gd`;
- все `tools/test_combat*.gd`;
- связанные battlefield, encounter, party progression и save tests;
- ручная проверка Combat Lab в Godot 4 Forward+.

Не запускать рабочий checkout с `--headless --editor`. Обычные targeted scripts
запускаются только через `--headless --path . --script ...`.

## Неподвижные границы

- Не создавать второй combat resolver, voxel editor или параллельный save owner.
- Surface мира остаётся dense до измеренного доказательства обратного.
- Не менять schema только ради удобства следующей реализации.
- Preview и commit используют один расчёт; случайный результат фиксируется до
  commit, но скрытые шансы попадания и крита не раскрываются игроку.
- Визуальный и gameplay-код не получают новых runtime-зависимостей от JOI.
- Пользовательские незавершённые изменения не удаляются и не перезаписываются.
- Commit, branch и push выполняются только по явной просьбе пользователя.

## Состояние workflow-миграции

Phase A и B зафиксированы в checkpoint `2c38bc5`: созданы короткий router/current-state,
Task Contract и lifecycle thread; README, product plan, handoff и test plan
очищены от технической летописи. Точная старая история остаётся в checkpoint
`20685ac`. Подробный GDD намеренно не сокращён: это действующий игровой документ,
а не changelog.

Phase C успешно воспроизвела старт независимого Codex-thread: он нашёл текущую
точку, owners, tests и v2.64.3 без истории исходного разговора и без полного
чтения больших документов. Найденные расхождения исправлены, правило cell/AOE
при удержании подтверждено пользователем.

Workflow Task Contract Phase A–C закрыт. Commit/push следующих срезов возможны
только по явной просьбе пользователя.

Основной Codex-thread сам ведёт обсуждение, реализацию и проверки milestone.
Делегирование — только по отдельной явной просьбе пользователя для конкретной задачи.
Если потребуется сменить длинный основной thread, используется проверяемая мягкая
передача по `.agents/skills/ember-coordinator-handoff/SKILL.md`: новый координатор
сначала без изменений пересказывает понимание проекта и нашего рабочего ритма,
старый координатор исправляет расхождения и только затем передаёт общение.

## Пиксельные персонажи

Pixel-art authoring2026-09-13: согласован [процесс слоёв](art/PIXEL_ART_WORKFLOW.md).
Фронтальная голова Миры распределена в отдельной рабочей копии 32×64:
4 папки, локальные Multiply/Hard Light, исходные формы/глаза и RGBA-итог сохранены.
Exact comparison, save/reopen и изоляция переключаемых эффектов проверены.
Ручная приёмка удобства слоёв открыта; ракурс¾, анимация и runtime вне среза.
Авторские исходники и другие текущие editor-срезы не изменены.

Мира: `body_fit_v1` отклонена — фронтальная голова была соединена с боковым телом.
Пользователь нарисовал настоящий фронтальный каркас в `mira_head_style_front.aseprite`,
видимая папка `Тело`. Техническая подложка `front_body_shading_v1` отклонена
как база для рисования одежды. Автор добавил тени в `mira_front_base_layers_v1.aseprite`.
Примерка `costume_front_v1` оставлена как вариант: посадка неплохая, сходство
недостаточное. Отдельная `docs/art/characters/mira/drafts/costume_front_v2`
приближает одежду к канону: свободные рукава, ремни, подвеска, диагональная накидка
и фигурный подол; без шляпы. Авторские cels/голова сохранены, локальные эффекты
изолированы, 32×64 и точный save/reopen проверены. Силуэт 23×50, 29 итоговых цветов.
Художественная приёмка v2 открыта; анимация и Godot-импорт не начаты.
По следующей просьбе добавлена отдельная проба `costume_hat_v1`:
широкая наклонённая шляпа, лента и янтарная подвеска, папка независимо отключается.
32×64, силуэт 30×59; исходные cels/позиции сохранены, y18–63 совпадает с v2,
отключение шляпы возвращает v2, эффекты и save/reopen проверены. Приёмка открыта.
Затем шляпа смещена на 3px вниз; `costume_hat_back_v1` добавляет её задние поля
за головой по референсу пользователя. Все ранее видимые пиксели/исходные cels
сохранены, переключение и save/reopen точные; художественная приёмка открыта.
После авторской правки смешанного слоя в `mira_hat_original_lowered_fold_v2.aseprite`
создана отдельная `user_costume_finish_v1`: авторская шляпа, накидка под волосами,
новая чистая покраска одежды. 32×64, 31 итоговый цвет; исходные cels головы/тела,
маски/переключение эффектов и save/reopen проверены. Исходник нетронут.
Пользователь оставил покраску как вариант и попросил непиксельную чиби-пробу.
`docs/art/characters/mira/drafts/chibi_live2d_v1` содержит PNG-эскиз по канону:
мягкие полу-чиби пропорции, фронтальная A-поза. Шахматный фон нарисован,
раздельного PSD/рига нет; приёмка дизайна открыта. Это не смена общего стиля
и не решение об интеграции Live2D в runtime.
По просьбе сделать чиби компактнее добавлена `mira_chibi_compact_front_v2.png`
в ту же папку: большая голова, короткие торс/конечности, упрощённый костюм,
белый фон. Пользователь принял дизайн компактной v2 («так лучше, подойдет»)
2026-09-14: ориентир следующих чиби-проб. Предыдущий вариант сохранён.
`drafts/chibi_layers_v1` — первый проход разделения: PSD и нативная копия Aseprite,
6 папок/35 слоёв, сменная проба закрытых глаз. Утверждённый PNG не изменён.
Нейтральная сборка, независимое чтение PSD, Aseprite save/reopen и смена глаз точные.
Маски на пересечениях материалов, белая кайма и скрытые перекрытия ещё требуют
доработки. Прямой импорт PSD в Aseprite не сработал; нативная копия собрана из частей.
Вид закрытых век принят 2026-09-14 («да подходит»); остальные маски и Cubism
не приняты/не проверены, рига/дыхания нет; общий/pixel-art канон не заменён.

По просьбе «попробуй» добавлена отдельная `drafts/chibi_layers_v2`:
маска материалов головы, скрытая кожа под чёлкой, запас на швах до 4px.
Нейтральная сборка/утверждённые закрытые глаза сохранены точно; независимое
чтение PSD, Aseprite save/reopen и малые жёсткие сдвиги проверены. Разрывы
внутри силуэта в диагностике головы: 3488→11px, корпуса: 1118→0px.
Это не анимация/риг: внешняя белая кайма, тонкие пряди и художественная приёмка
открыты. Следующая точка — принять/дочистить материал перед пробой Cubism.

По согласию «вау, давай далее» выполнена `drafts/chibi_idle_v1`: GIF-петля 4s
и нативный Aseprite (6 папок/36 исходных слоёв/50 кадров). Тихий подъём
головы/корпуса/прядей и моргание двумя принятыми позами. Пиксели деталей v2
не перерисованы; контрольные кадры, save/reopen, стык петли, тайминги GIF проверены.
Ручная приёмка движения открыта. Imagegen не дал настоящую альфу при очистке
края: RGB-шахматка отвергнута; белая кайма/тонкие пряди не исправлены.
Cubism/SDK/runtime не начаты. Следующая точка — оценить петлю и дочистить материал.

По замечанию о белом фоне между локонами добавлена `drafts/chibi_idle_v2`:
удалены четыре замкнутых белых участка (2290px), только локальная альфа.
Цвета, движения и тайминги v1 сохранены; прежние файлы не перезаписаны.
Исправленные части сохранены отдельно для дальнейшего разделения/рига.
Внешняя тонкая кайма остаётся открытой задачей, Cubism/runtime не изменены.

`drafts/chibi_idle_v3` продолжает локальную чистку альфы: два белых просвета
у нижних локонов с обеих сторон и 33 отдельные белые точки вокруг них.
365px сверх v2; прежние исправления включены, RGB/движения/тайминги сохранены.
Нижние области проверяются отдельно; прежние версии сохранены, внешняя кайма
и Cubism/runtime остаются вне текущей правки.

## Как обновлять этот файл

Обновлять только после принятого среза или изменения ближайшего порядка работ.
Здесь нужны факты о текущей точке, ближайшие 1–3 шага, owners, gates и открытые
риски. Длинные объяснения, журналы версий и завершённая история остаются в
канонических документах и Git.
