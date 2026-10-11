# Ember — полный выход из JOI

## Действующее решение: архивировать устаревший контент

Решение автора 2026-10-10: старые города и карты больше не являются актуальным
контентом; новые системы не подгоняются под них. `fan_town` с четырьмя интерьерами
и обе `agent_sandbox` сцены — первая партия для вывода из активного проекта.
Старт F5 выбран и переключён на `scenes/landscape_compact.tscn`.

Контентный архив `~/Documents/EmberArchives/legacy-ember-2026-10-10/` содержит
старые сцены, найденные Resource/prefab зависимости, frozen JOI pack, снимок
общих скриптов и 45 тестов со ссылками на старые карты. ZIP: 1318 файлов,
SHA-256 всех payloads и CRC проверены, manifest.json хранит суммы. Это не полный
standalone checkout: engine/import cache/native addons и все динамические ID
не включены. Семь сцен теперь **выведены из проекта**; наличие архива и этот
retirement не закрывают полный G4/G5. Свежие версии сохранены дополнительно
в retired-scenes-current-2026-10-11.zip: 998 текущих файлов, payload SHA и
ZIP CRC проверены. Архив включает обновлённые прежние payloads, найденные
literal зависимости и текущие native owners. Это не standalone checkout;
engine/import cache не включены. SHA-256 ZIP:
8a59db1cc6e78a67d95e20c7fde985977fae1888292094067b949af69cf5bfe1.

Критерий выхода теперь — отсутствие legacy-зависимости у актуальных сцен,
инструментов и gameplay, а не обязательный перенос всего исторического каталога.
Для retired-only данных достаточно проверенного архива и отсутствия входящих
актуальных ссылок; parity нужна данным, которые продолжают использоваться.

Последовательность небольших контрактов:
1. Общий exploration controller перенесён в `scripts/ember_explore_scene.gd`;
   `world_canvas.gd`, `test_pier.gd` и семь пока активных старых сцен используют
   одного owner. Script UID сохранён, body не менялся, кроме комментария;
   старого файла/compat alias нет. Parse и шесть targeted runtime gates PASS.
2. Map/region selectors, схемы входов и Inspector теперь читают native `.tscn`
   через `EmberInteractionContent`, без map JSON/JOI fallback. Каталог читает
   native dependencies, подробности выбранной карты — saved SceneState без
   запуска узлов. Runtime/Inspector используют общий `MapLoader.find_region`
   для вложенных регионов; default spawn также учитывает их. Targeted QA PASS;
   ручной выбор/Save/Reopen/F5 OPEN. Следующая часть — убрать fallback остальных
   актуальных catalogs по одному домену; архив не переносить ради старых тестов.
3. Первый общий gate `test_map_transition` теперь использует шесть сохранённых/
   переоткрытых native fixtures из `user://` вместо старых городов. Пять маршрутов,
   реальные exploration/player/door/trigger owners и arrival guard сохранены.
   PASS также в отдельном code-only проекте без городов/voxel models/prefabs/JOI;
   `test_combat_encounter_transition` использует ту же native exploration основу,
   настоящий Combat Lab/Encounter, отдельные autosaves и сохраняет gates party,
   XP/loot/counters, repeated Continue, active roster и точного XZ возврата.
   Оба проходят detached QA; намеренно неверные spawn/counter изменения в копии
   обнаружены. Save/chest (`run_progress_restore_test.py`) также независимый:
   saved native map, два synthetic voxel Resources, реальные prefab/mesh,
   loot once, сохранение typed progress и повторное открытие save/scene PASS.
   Prefab writes разрешены только в disposable проекте; рабочий запуск отказан.
   Negative control потери chest key обнаружен. Все эти gates теперь читают
   native items/coin/icons; item compatibility JSON больше не нужен.
   Native chest startup теперь проходит общий
   `MapLoader.refresh_region_runtime` без зависимости от map JSON: вложенные
   регионы, создание closed visual и замена serialized closed по loaded progress,
   block size/repeated refresh PASS. Отказ инициализации в копии обнаружен тестом.
   Retry/defeat также использует shared saved native fixture: реальные Combat Lab,
   modal/focus, corrupt-load guard, prebattle copies и manual/autosave positions
   сохранены; detached QA, seed/position negative controls PASS. Только test change.
   Pause/save menu проверяется на двух saved native maps: настоящие кнопки трёх
   слотов, same/cross-map load с saved XZ, pause/resume и delete/recovery PASS.
   Исправлен конфликт exit autosave с pending restore; обычный departure save
   сохранён. Detached QA/negative controls PASS. Общие interactions также независимы:
   talk/shop/action/launch/quest gates через `run_interaction_tests.py`, synthetic
   native Resources/maps, реальные runtime owners; save reopen и три negative
   controls PASS. Native writers запускаются только в disposable проекте;
   рабочий checkout отказывает до native fixture writes. Inventory/equipment,
   health/consumables, party followers и defeat/respawn также используют saved
   native карту и нейтральные native equipment fixtures (`run_party_tests.py`).
   Equip/use/save reopen, armor/clamp, одиночка/пара/leader/formation/train и
   respawn PASS; runtime/schema не менялись. Четыре negative controls и working
   refusal PASS; source SHA сохранены. Item domain закрыт отдельным срезом:
   `EmberItemCatalog` читает только native items и `EmberItemIconResource` в
   content/item_icons. Шесть прежних native items сохранены; добавлены только
   актуальный coin и шесть используемых icons, Dictionaries равны frozen source.
   Legacy-only предметы/иконки не перечисляются и не импортируются. Item
   migration UI/forwarding удалены, create/save/discard/Undo/Redo остаются общими.
   `run_item_resource_test.py`: poisoned/missing JSON, runtime/editor, old saved
   counts и binary/remap PCK PASS. Неизвестная saved экипировка возвращается
   в сумку без усечения количества; v1 с явным maxHp не читает ненужный stage JSON.
   ShopCatalog также native-only: definition/IDs/owner читают только shop Resources,
   `.tres.remap` проверен в PCK. Shop migration UI/forwarding и compatibility JSON
   удалены; listing/save schema и Economy/ExploreState не менялись.
   `run_shop_tests.py`: native create/edit/discard/Undo/Redo, цены/finite/infinite
   stock, buy/sell/unsellable/full-stack и save reopen PASS; четыре negative
   controls/working refusal PASS. Village_kiosk теперь выведен вместе с city-only
   action/quest/surface Resources; недостающий retired item не импортировался.
   Stock даже отсутствующего shop сохраняется в save. Action/DialogueCatalog также
   native-only: IDs/owner/document, write/delete и Undo snapshots больше не читают
   и не восстанавливают JOI JSON. Snapshot содержит только ID/native document;
   migration UI/forwarding удалены, runtime graph/action schema не менялись.
   `run_story_tests.py`: четыре guarded native authoring gates, simple card
   projection/branch convergence, action+scene+quest binding/clone/orphan Undo и
   binary PCK PASS. Poison/missing JSON, old-shape snapshot, четыре negative
   controls и пять working refusal PASS. Нейтральные native карта/prop/stories
   заменили зависимости этих tests от fan_town/sandbox/Hu Tao; author source SHA
   сохранены. После content retirement осталось 2 combat native actions
   и 2 dialogue files; retained documents не изменены;
   сохранение файла не означает приёмку его historical content. VN assets также
   native-only: EmberVnAssets читает только content/vn_backgrounds/vn_portraits
   Resources, не сканирует arts/portraits registry и не разрешает relative path
   через JOI. Два author фона сохранены, native portraits пока отсутствуют;
   historical graphics не импортировались. run_vn_asset_tests.py: guarded imports,
   unique IDs, fresh metadata reload, CPU image/picker, poison/missing JOI и
   source-free binary/remap PCK PASS. Второй PCK после import в отдельном cache
   читает .ctex без raw source images. Missing saved IDs остаются warning entries.
   VoxelCatalog и VoxelPrefab также native-only: runtime/полка не сканируют
   JOI models и не строят mesh/body/size из старого VOX/JSON. Явная import queue
   принадлежит EmberVoxelLegacyImporter и editor migration report; обычная полка
   её не показывает. В scan остальных сцен найден один настоящий missing source:
   vox_fan_crate_stack на Причале. Сохранён один новый native Resource после exact
   visual/collision parity; 92 прежних источника и все maps/prefabs неизменны.
   material_study_* генерируются лабораторией и не являются отсутствующим контентом.
   run_native_voxel_tests.py: 93 sources, лёгкая shelf metadata, native preview/
   collision, scene save/reopen и binary/remap PCK без JOI PASS. Explicit importer
   queue/batch Undo/Redo и forced interruption PASS; Undo отсутствовавшего native
   source восстанавливает точные прежние derived bytes вместо legacy rebuild.
   Map startup теперь native-only: ExploreScene не вызывает load_map даже для
   пустой сцены. Refresh regions читает только scene-owned свойства и обновляет
   native runtime bindings/chest visuals; footprint не ищется в JSON. Крыши больше
   не строятся из legacy tile map: refresh_cutaway_runtime связывает сохранённые
   Cutaways volumes, включая вложенные, не удаляя authored nodes. Roof child
   reference восстанавливается после scene reopen; fade/shadow contract прежний.
   Старые hydrate_legacy_regions/native_cutaway_enabled flags сохранены лишь для
   serialized compatibility и не включают загрузку JSON. Активные editor paths также native-only: Surface opening/region selection
   не восстанавливают геометрию/размеры из map JSON; object session и scene/catalog
   rebuild отказывают при отсутствии native source, сохраняя готовый prefab.
   Store.owner и content report не сканируют old pack. Убраны editor reimport menu/
   confirmation, selected JSON/VOX import links, shelf migration filter/actions,
   sandbox/fan_town batch dashboard/preflight/forwarding. Diagnostics остаётся
   read-only native inventory; её user:// JSON export и current derived cache
   manifests не являются legacy content и сохраняются.
   Explicit offline voxel importer/parity/Undo APIs остаются для сохранённых tools,
   но не вызываются активным editor UI. EmberPack/load_map helpers ещё физически
   существуют; их export boundary и remaining retired references сверить
   перед city retirement. run_native_editor_tests.py: open/save/discard/Undo/Redo,
   missing source rejection, selector/report/dashboard с poisoned/absent JOI PASS.
   Native scene refresh, story/voxel/PCK и disposable editor/import обоих Ember
   plugins PASS. 713 author source SHA сохранены; manual Forward+ OPEN. run_map_startup_tests.py, четыре negative controls, native transitions,
   save/chest, interactions и party gates PASS. Полный G4/G5 и Forward+ OPEN.
   Ручной Forward+ gate сундука/Save/Load остаётся OPEN и отложен автором.
   Остальные city/content-specific gates вывести с контентом; общие mechanics,
   interactions и editor Undo/save проверки сохраняются. Детали — Test Plan.
   Save destinations/defaults теперь landscape_compact. По решению автора семь
   retired map IDs (даже при наличии сцен) и недоступные карты переносят игрока
   на native вход с сохранением прогресса. Исходные v1/v2 и recovery backup
   сохраняются; schema не менялась. Native координаты действующих карт прежние.
   Menu preflight/rollback и pending restore до scene removal защищают загрузку
   от exit autosave. run_save_destination_tests.py и четыре negative controls PASS.
   Две unused sbx_bush_se_actions/_2 с target agent_sandbox выведены из
   каталога; exact-byte SHA/CRC проверены в supplemental архиве
   legacy-ember-2026-10-10/retired-city-links-2026-10-11.zip. Первоначальный
   архив этих динамических Resources не содержал; он не изменён.
   Report больше не preloads исторические VoxelBatches и не содержит городских
   фильтров. test_retired_city_references.py проверяет актуальные scripts/addons,
   current scenes и text/binary resource paths; три negative controls PASS.
   Save registry остаётся исключением совместимости, surface semanticOwner —
   historical metadata. Offline batch module выведен вместе с city-only tools.
   Mixed editor tests ещё используют авторские старые карты: это отдельный
   следующий срез, не повод удалить их общие проверки.
   Все 11 реальных action Resources читаются native Catalog без retired targets;
   native editor и save/transition regressions PASS. Ручной Forward+ OPEN.
   В supplemental retired-city-tools-2026-10-11.zip сохранены 11 текущих
   скриптов + 11 UID (exact SHA/CRC), включая dirty версии: два party capture,
   две fan_town migration utilities, stale prefab profile, два fan_town Surface
   content gates, два ready-batch gates, sandbox native batch и offline batch
   definitions. Capture заменён run_party_tests.py --visual/--capture-active;
   общий party/save gate остаётся native. Городские batch/parity проверки
   исторического content больше не активные gates; общие native catalog/geometry,
   PCK и explicit import checks сохранены. Editor/voxel/party regressions PASS.
   10 mixed gates теперь independent native: Inspector model/panel/actions,
   standalone trigger, quest journal, scene round-trip, map picker/Graph,
   Surface projection/sculpt. run_mixed_editor_tests.py создаёт только synthetic
   scenes/models/story/images в guarded disposable проекте; исторические
   города/модели/JOI не копируются. General assertions сохранены: ownership,
   add/edit/delete, Undo/Redo, save/reopen, duplicate transforms/IDs, graph
   ports/branches/clipboard/diagnostics, VN actors/fields/cache и physics/routes.
   Surface selector теперь проверяет отказ JSON fallback, physics — explicit
   saved native Resource link вместо удалённого implicit loader fallback.
   Synthetic physics footprint прежний 24x24 blocks/16 density/32 height.
   PASS + Undo/duplicate negative controls + write refusal; Forward+ OPEN.
   Оставшиеся Surface performance, editor shapes/diorama/prefab rebuild и
   test_vox_axes.py переведены на native fixtures. Profile Surface сохраняет
   24x24 blocks/16 density/32 height и 40-cell dry/wet strokes; context map
   synthetic, диагностические A/B scripts parse и не зависят от Причала/городов.
   CPU profile/checks PASS; full visible A/B replay пока OPEN, timings новой
   геометрии не сравниваются с историческими. Prefab gate сохраняет UID/cache/
   timestamps/placements/alpha surfaces; generated model/map PASS. Diorama
   использует saved toy light scenes и сравнивает water parameters с текущим
   native material owner вместо superseded art constants. Forward+ pixel
   idempotence/clear/Sun enable/reopen PASS. Shapes gate запускается actual
   Forward+ editor только в disposable project: create/paint/grow/save на двух
   synthetic maps, callback inline panel, unload/exit PASS.
   Python baseline сохранён exact-byte в mixed-python-baseline-2026-10-11.zip;
   retired content counts/JSON/file expectations выведены, общие static
   contracts сохранены. Shader checks читают нынешние includes без comments;
   synthetic asymmetric VOX + native parser/axis/Resource parity PASS, wrong
   axis negative control FAIL. Ничего из author sources не менялось.
   Save migration IDs остаются compatibility data; семь сцен выведены.
4. Семь архивированных сцен выведены после проверки свежести/входящих ссылок.
   Удалены только .tscn; остальные 704 author map/content/prefab/material files
   сохранили SHA. Exclusive ресурсы пока не удалялись: только после отдельной
   полной сверки текущих code/dynamic/binary/catalog uses. `vox_fan_barrel`/`vox_fan_crate_stack` нужны Причалу; scan
   shared-models.json покрывает лишь прямые ссылки других `.tscn`, не доказывает
   отсутствие code/dynamic/binary uses у остальных моделей.
   Static gate теперь отвергает возвращение retired .tscn; negative control PASS.
   Native startup/cutaway, restore/menu/map/battle/Retry и native editor report/
   dashboard regressions PASS. Ручной F5/old Save/Load остаётся OPEN.
   Content Resource retirement: 13 files — 8 sbx_* actions, sandbox_chain,
   sandbox_notice_quest, village_kiosk, fan_town_surface/agent_sandbox_surface.
   Exact current payloads уже были в refreshed 998-file архиве; SHA/CRC повторно
   проверены до удаления. Внешних source/path/UID ссылок в актуальном контенте
   нет; единственный consumer — Graph lifecycle test — переведён на guarded
   neutral fixture с теми же frame retirement/focus/orphan assertions.
   Остальные 691 data files и 93 voxel sources/prefabs/materials неизменны.
   Actual native catalog gate подтверждает 2 retained combat actions, empty
   shop/quest catalogs, current battle queue и shared Pier models. Old save
   quest flags, shop stock и unknown items проходят exact round-trip без
   definitions и без перезаписи source save. Story/shop/PCK/restore/menu/battle
   regressions PASS; Resource resurrection/incoming shop negative controls PASS.
   colored_crossing_start использует colored_crossing_intro: бывший
   sandbox_notice_talk переименован с сохранением Resource UID, двух реплик,
   переходов и записи new_flag=true. Текст теперь о подготовке к засаде у
   переправы, без направлений к старым сундуку/лавке. Exact прежний диалог
   есть в refreshed архиве. Traversal, UI flag publication и save round-trip
   PASS; ручной диалог → бой OPEN. hu_tao_clear_demo и VN assets неизменны.
5. G4/G5: editor и F5, native authoring/save/reopen, взаимодействия и бой без
   физически доступного JOI; проверить выбранные данные export. Ручные gates
   новых карт/материалов сохраняются. Старые пользовательские saves не удалять.

## Исторический migration baseline

Текущая сверка 2026-09-30: runtime/editor legacy fallback ещё существует;
G4/G5 нельзя считать закрытыми. Обзор реальных owners — Technical Handoff →
«Краткий контекст для синхронизации». Числа и версии в baseline ниже — исторический
снимок миграции, не текущий инвентарь: сейчас найдено 92 native voxel `.tres`,
но число файлов не подтверждает parity и не определяет остаток legacy.

Статус: принято пользователем 2 сентября 2026 года; v2.50 впервые фиксирует
единый read-only baseline G1/G2, v2.51 даёт фильтруемый список всех 263 записей,
а v2.52 после strict dry-run переносит первые шесть sandbox voxel-моделей одной
Undo/Redo batch. V2.53 закрывает physical Surface gate на `agent_sandbox`, а
v2.54 — measured gate на `fan_town`: visual, collision и route heights выводятся
из одного dense Resource. V2.55 после 7/7 strict parity переносит первую
ограниченную партию готовых `fan_town` prefab. Voxel ownership теперь 15 native /
162 legacy; произвольный массовый перенос и
удаление fallback пока запрещены.

V2.56: read-only профиль оставшихся 25 scene-used stale prefab показал реальные
изменения видимых voxel-граней у 25/25 и collision у 18/25. Автоматический batch
не создан; эти модели требуют art review в контексте первой production-зоны
после design Q&A. Это не блокирует stop-line основного редактора и не разрешает
удаление legacy owner.

V2.39: первый explicit height-slice gate закрыт — верхняя плоскость отсечения, closed-cap preview в обоих backend, matching pick/write mask и локальные кисти. Произвольный диапазон слоёв и колонковые операции внутри среза не заявлены. Editor-only состояние не меняет canonical `.tres`. G1 всё ещё требует full-editor lifecycle и масштабирование хранения; G2–G5 не закрыты.

Уточнение G1 на 5 сентября: историческое перечисление v2.00–v2.12 ниже больше не является актуальным остатком кистей. Level/Smooth, slope A→B, shell Raise/Lower, material painting, умный цветовой выбор, отдельная level-fill вода, её tint, bed-only view, перенос world/battle областей, height slices, lifecycle и профиль dense-карты уже реализованы. Shape/Water визуально общие для мира и боя; sandbox и `fan_town` также выводят collision и route heights из той же Surface. Это пока map-level opt-in: остальные карты и G4–G5 не закрыты.

## Конечное состояние

`ember-godot` открывается, редактируется, тестируется и экспортируется без sibling `joi-conductor` и без `ember/pack_path`. JOI/Three/старый sculptor не являются runtime, editor, asset library или content writer. Старый pack хранится отдельно только как архив до завершения сверки и затем может быть удалён без потери игры.

Не переписываем всё одним массовым convert. Каждый домен получает одного Godot owner, visual authoring, runtime parity, save/reopen и тест с намеренно недоступным JOI path. Только после этого его legacy fallback удаляется.

## Владельцы данных

- Карты: `.tscn` владеет композицией, props, regions и interactions. Semantic surface получает один Godot Resource только после sandbox-pilot; он не дублирует scene transforms.
- Voxel-модели: `content/voxel_models/*.tres` (`EmberVoxelModelResource`). Mesh/collision/prefab/thumbnail/MeshLibrary производны.
- Диалоги и цепочки: существующие `content/dialogues/*.tres` и `content/action_scripts/*.tres`; каталоги native-only; historical JSON остаётся в архиве.
- Задания, бойцы, действия, AI, encounters и loot: уже Godot Resources.
- Предметы и магазины: существующие native-only Resources; retired IDs сохраняются в save, старый каталог не переносится целиком.
- VN-фоны и портреты: `assets/vn_*` + native-only Resources; historical graphics не является обязательной очередью импорта.
- Save: Godot остаётся единственным runtime writer. Историческая совместимость формата не является зависимостью от JOI; version bump нужен только при реальном изменении данных.

## Очередность

1. **G1 Voxel ownership/editor.** Native Resource/importer и visual migration queue с Ctrl+Z готовы в v1.98–v1.99. V2.00–v2.12 дают первый style-first shape gate: связный Surface Canvas 4×4, 32-grid, coarse/detail brush, world/battle camera presets, seam-safe frame-budgeted preview, непрерывный drag, time-based bounded Raise/Lower с 1–32 vox/sec, радиусы 1–32, low-latency heightfield draft, overlap-aware caches, coalesced mouse input и непрерывную swept-капсулу без дыр. Hollow-shell остаётся измеримым R&D experiment: она уменьшает filled occupancy, но на fixed array/общем exact mesher пока медленнее и геометрически дороже solid Raise, поэтому не становится новым owner/default. До полного sculpt-gate ещё нужны explicit height slices, Level/Smooth и material-channel painting; chunked world owner проектируется только после ручной приёмки визуального эффекта. Затем parity report, перенос оставшихся моделей и удаление voxel fallback/JOI deep-links.
2. **G2 Content backlog.** Одна общая страница `Миграция контента` показывает legacy/native/missing для dialogue/action/item/shop/VN, умеет открыть owner и переносит по одному либо безопасным batch после dry-run.
3. **G3 Map surface pilot.** Sandbox physical gate закрыт в v2.53, а `fan_town` measured gate — в v2.54: сохранённая Surface проходит 3D paint, collision, height/route query, runtime и save/reopen. Остальной legacy runtime sever относится к G4.
4. **G4 Runtime sever.** Все runtime catalogs становятся native-only. Legacy importers перемещаются в editor-only migration folder и не входят в export.
5. **G5 Physical gate.** Переименовать или временно убрать `joi-conductor`, очистить `ember/pack_path`, запустить headless suite, editor, sandbox, карту, VN, магазин, quest и battle round-trip. После зелёного отчёта архив JOI не нужен проекту.

## Обязательная диагностика

- `legacy remaining`: число и список по каждому домену;
- `native invalid`: Resource, который не проходит validation;
- `reference missing`: scene/document с ID без native owner;
- `derived stale`: prefab/thumbnail/mesh старше source Resource;
- `JOI detached`: тесты проходят при несуществующем pack path.

## Что не делаем

- не поддерживаем двустороннюю синхронизацию;
- не создаём новые Ember-данные в JOI во время миграции;
- не сохраняем абсолютные пути к старому репозиторию в `.tres`;
- не устанавливаем addon, который приносит второй voxel/map/dialogue/quest store;
- не удаляем legacy до checksum/parity и резервной копии.
