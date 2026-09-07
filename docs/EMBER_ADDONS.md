# Ember — сторонние Godot addons и assets

Этот файл является реестром внешних зависимостей authoring/runtime. Добавление из Godot Asset Store, Asset Library или GitHub разрешено только после проверки лицензии, версии Godot, статуса поддержки, владельца данных и удаления.

Официальные ориентиры:

- [Godot — Installing plugins](https://docs.godotengine.org/en/stable/tutorials/plugins/editor/installing_plugins.html)
- [Godot — Using the Asset Library](https://docs.godotengine.org/en/stable/community/asset_library/using_assetlib.html)
- [Godot — EditorPlugin](https://docs.godotengine.org/en/stable/classes/class_editorplugin.html)

## Правило принятия

Для каждого кандидата записать:

- название и решаемую авторскую проблему;
- source URL, точную версию/commit и лицензию;
- совместимую версию Godot и support status;
- папки, которые попадут в `addons/` или assets;
- owner/adapter Ember и какие данные addon имеет право менять;
- headless/manual smoke;
- способ отключения и удаления;
- решение: `spike`, `accepted`, `rejected`, `replaced`.

Не принимать addon только потому, что он выглядит удобным в демо. Он должен проходить наш реальный сценарий создания контента и не заводить второй несовместимый формат.

## Workflow-аудит 2026-09-02

Аддон подключается не «на всякий случай», а перед первым срезом, где он реально сокращает authoring. До установки фиксируются один из двух режимов:

- **adapter** — Ember Resource остаётся owner, addon получает только временную/производную проекцию и имеет штатный fallback;
- **replacement** — addon становится единственным owner домена только после конвертера, parity-gate и удаления прежнего writer/runtime. Параллельные owners запрещены.

Текущая маршрутизация:

- voxel preview: Zylann Voxel Tools `1.7x`, принят как removable adapter;
- бой и дискретные игровые поверхности: штатный `GridMap + MeshLibrary`, уже принят;
- интерьеры/архитектурный graybox: Cyclops `1.5.0-dev_3` — **just-in-time candidate** для D3, устанавливать перед одним disposable blockout-spike, не раньше;
- сложный dialogue runtime/localization: Dialogue Manager `4.0.3` — **replacement candidate**, не adapter. До отдельного parity-spike не расширять самописный runtime новыми языками условий/мутаций;
- задания: Questify `1.6.0` — rejected как runtime/store; полезные UX-паттерны уже накладываются на `EmberQuestResource`;
- большие гладкие природные зоны: Terrain3D `1.0.2-stable` — deferred background/macro-terrain candidate. Не использовать для voxel surface, battle cells или gameplay-height owner.

Перед началом нового крупного editor/runtime-среза сначала проверяется этот реестр и актуальная Asset Library. Если готовое решение покрывает authoring и runtime без второго owner, сначала делается один обратимый spike; собственная подсистема появляется только после его измеримого провала.

## Текущие зависимости

### `godot_mcp`

- Статус: installed; development tooling.
- Источник: <https://github.com/KeeVeeG/godot-mcp>.
- Установленная версия: `1.0.0` по `plugin.cfg`; upstream stable `v1.1.0` (`a08c705f66fd907e5b57ceed905d31496482b85d`) проверен 2026-09-02, но не установлен во время product slice.
- Лицензия: MIT по upstream; установленная папка не содержит копию license, поэтому при planned update `1.1.0` её нужно сохранить рядом с addon и зафиксировать SHA-256 release asset.
- Назначение: управление и диагностика открытого Godot editor из инструментов разработки.
- Ownership: не владеет gameplay/content schema.
- Удаление: отключить plugin и удалить `addons/godot_mcp`; игра не должна зависеть от него.

### `at-icons`

- Статус: installed, но изолирован через `addons/at-icons/.gdignore`; editor presentation; plugin сейчас не включён и его SVG не участвуют в asset scan.
- Источник: <https://github.com/voxybuns/at-icons/>.
- Установленная версия: `1.4.0` (`aa5d5cdb7e40719448162e49c4f14b8275f5441d`) по `plugin.cfg`; это текущий stable на 2026-09-02.
- Лицензия: MIT, `addons/at-icons/LICENSE.txt`.
- Назначение: набор иконок для authoring UI.
- Ownership: не владеет gameplay/content schema.
- Import caveat: набор содержит 3 708 SVG с editor-вариантами, зависящими от масштаба и темы Godot. Нельзя запускать рабочий checkout через `--headless --editor`: headless `EDSCALE` способен переписать всю пачку `.editor.ctex/.editor.meta`, после чего обычный GUI снова импортирует её под свой display scale. `.gdignore` предотвращает этот цикл, пока picker не нужен. Targeted tests используют `--headless --path . --script ...` без editor mode; import smoke выполняется только в отдельном cache/checkout.
- Повторное включение: удалить `.gdignore`, включить plugin и открыть обычный GUI; один полный импорт иконок после этого ожидаем.
- Удаление: отключить plugin и удалить `addons/at-icons`; игровые данные не должны зависеть от picker.

## Рассмотренные, но не установленные

### `godot-questify`

- Статус: **rejected как runtime/store; принят только как UX reference**.
- Источник: <https://github.com/TheWalruzz/godot-questify>; release `1.6.0` (`819ea79764da7861cce75d58b012600bd379fd19`), повторно проверен 2026-09-02; MIT; заявлена совместимость Godot 4.4+.
- Полезные идеи: отдельная graph-вкладка, явные Start/Objective/End, поиск Resource, контекстное добавление нод и Undo/Redo.
- Причина отказа от установки: addon инстанцирует собственный quest graph, `Questify` singleton, active-objective state, polling (по умолчанию каждые 0.5 сек) и отдельную сериализацию/десериализацию. Это стало бы вторым владельцем рядом с `EmberQuestResource + EmberExploreState.flags` и нарушило бы принятое правило «quest = видимая проекция общих последствий мира».
- Допустимое использование: повторить понятные UX-паттерны поверх существующего Ember store без копирования runtime/schema.

### `godot_dialogue_manager`

- Статус: **accepted replacement candidate; не устанавливать параллельно**.
- Источник: <https://github.com/nathanhoad/godot_dialogue_manager>; release `v4.0.3` (`ffc0011a1a3ea38fc6e65729e5f987d07dac0c88`) для Godot 4.7, проверен 2026-09-02; MIT.
- Сильные стороны: stateless branching, cues/imports, условия и мутации, BBCode/wait, line tags, синтаксическая диагностика, Godot localization, custom balloon/runtime API и debugger. `mood=...`, portrait/background IDs и другие Ember presentation hints технически могут жить в tags, не требуя fork addon.
- Цена замены: основной upstream authoring — текстовый `.dialogue`, а пользователь предпочитает node graph. Текущий Ember envelope также хранит VN stage/background/portrait state и связывает `set_flag` с action/quest graph. Простое включение addon создаст второго parser/runtime/Resource owner.
- Parity-spike перед принятием: один отдельный `sandbox_notice_talk` должен round-trip пройти `dialogue/choice/set_flag/end`, русскую локализацию, portrait emotion/background tags, live preview и продолжение action chain. Затем выбирается ровно один canonical source; старые `EmberDialogueSession` и writer либо удаляются, либо addon отклоняется. До этого не добавлять в самописный runtime новый язык сложных conditions/mutations.
- Удаление кандидата: пока spike не принят, production `.tres` не конвертируются и plugin/autoload не включаются в основной проект.

## Инструменты 3D-ландшафта, рассмотренные для боя и мира

### Godot `GridMap + MeshLibrary`

- Статус: **accepted; D2.0 projection passed in v1.71, standard scene boundary passed in v1.72, semantic Battlefield Resource boundary passed in v1.76, native 3D painting passed in v1.78, rectangle/guided fill passed in v1.79, authored visual MeshLibrary passed in v1.80, safe resize/deployment passed in v1.81, Encounter Resource/return slice passed in v1.82, radial result lifecycle passed in v1.83, fullscreen tactical HUD composition passed in v1.84**; штатные классы Godot, addon не нужен.
- Источники: <https://docs.godotengine.org/en/stable/tutorials/3d/using_gridmaps.html>, <https://docs.godotengine.org/en/stable/classes/class_gridmap.html>, <https://docs.godotengine.org/en/stable/classes/class_meshlibrary.html>.
- Назначение: 3D-палитра graybox/voxel-тайлов, этажи, collision и быстрый scene layout. После v1.80 тот же штатный путь принят для будущего общего Tile Kit мира и боя; их semantic layout при этом остаётся раздельным.
- Ownership: только visual/spatial projection. Combat snapshot/resolver владеет высотой, проходимостью, panel state, эффектами и изменениями поля; grid movement остаётся pure BFS.
- Ограничение: MeshLibrary экспортирует mesh и опциональные collision/navigation shapes, но не является общим контейнером arbitrary gameplay nodes. Юниты, Geo-фокусы, разрушаемые объекты и VFX создаются отдельными сценами.
- Удаление: projection adapter можно заменить, не меняя encounter data или resolver tests.
- Фактическая приёмка: `combat_lab.tscn` теперь обычная Node3D-сцена со scene-owned GridMap/Camera3D/светом/слоями объектов и CanvasLayer HUD; collision ray-pick, staged actor, Frozen/Wet replacement и 2D parity проходят `test_combat_lab.gd`. С v1.76 layout сохраняется отдельным semantic `EmberBattlefieldResource`; v1.77–v1.79 добавляют Inspector/3D paint, atomic strokes, rectangle/fill и swatches. v1.80 выносит visual items 0–4 в один authored `ember_battlefield_tiles.tres`; v1.81 добавляет safe resize/remap и canonical deployments. v1.82 добавляет native Encounter Resource, visual picker и process-local exploration return. v1.83 остаётся на штатном CanvasLayer/Control: radial HUD следует за Camera3D projection, а result modal/fade закрывают retry/return и idempotent outcome. Для world-mode сначала обязателен один sandbox pilot и one-way migration: GridMap не должен стать вторым владельцем существующей JSON-карты. Следующий вопрос — normalized 16/32 voxel kit, а не новый runtime формат или внешний addon.

### `Cyclops Level Builder`

- Статус: **accepted just-in-time disposable blockout candidate для D3**; не является voxel/map owner и пока не установлен.
- Источник: <https://github.com/blackears/cyclopsLevelBuilder>; release `v1.5.0_dev_3` (`29747a3242fbcc1ba733cd07eee6a39ed3bf81fe`), проверен 2026-09-02; README заявляет Godot 4.7+; MIT.
- Сильная сторона: быстрое построение и редактирование convex-блоков прямо в 3D viewport с collision.
- Граница: это general blockout tool со своим block data, editor plugin и обязательным `CyclopsAutoload`, а не редактор semantic battle cells. Он не решает panel groups, voxel art, preview/commit или изменение боевого snapshot; текущая линейка всё ещё помечена upstream как `dev` и меняла внутренний формат.
- Первый допустимый spike: один новый интерьер/коридор D3, не `fan_town` и не готовая арена. Автор строит стены/лестницы/проёмы, затем конвертирует результат в обычные Godot MeshInstance3D + collision. Runtime и navigation видят только baked result; исходный Cyclops blockout остаётся editor-only и удаляемым.
- Acceptance: blockout заметно быстрее штатных CSG/GridMap, plugin disable/re-enable не ломает baked scene, Undo/Redo работает, export не требует Cyclops runtime. Если конвертация ухудшает voxel-style pipeline или collision ownership — кандидат отклоняется без migration.

### `Terrain3D`

- Статус: **deferred macro/background-terrain candidate; не использовать для основной Ember surface**.
- Источник: <https://github.com/TokisanGames/Terrain3D>; release `v1.0.2-stable` (`0077405b52e353c5e5dc3a094e7ede49833ba6fe`), проверен 2026-09-02; MIT; release заявляет Godot 4.4–4.6+ и требует отдельный Godot 4.7 smoke.
- Сильные стороны: C++ GDExtension, heightmap sculpt/paint, holes, до 32 textures, LOD и foliage для зон от 64×64 м до очень больших пространств.
- Причина паузы: heightmap/clipmap не выражает authored voxel-блоки, нависающие формы и единый мир/бой Tile Kit. Terrain data directory стал бы вторым owner высоты рядом с canonical voxel surface и semantic battle grid.
- Возврат: только если D3 докажет потребность в дальнем гладком фоне/макрорельефе за пределами игровой voxel-поверхности. Один disposable 64×64+ zone spike обязан отделить render-only terrain от общей collision/navigation surface; иначе Terrain3D отклоняется.

### Zylann `Voxel Tools`

- Статус: **accepted Windows editor-preview spike в v2.07**; не является battle/runtime owner.
- Источник: <https://github.com/Zylann/godot_voxel>; GDExtension release `1.7x` / asset `GodotVoxelExtension.zip`, проверен 2026-09-02; SHA-256 `600737572a5e25541ba6f503e842a3717ba19afafa5474510a6ceff995a1d2d8`; MIT (`addons/zylann.voxel/LICENSE.md`). Соответствующий module release 1.7 публикует custom Godot 4.7.2 build, но проект его не использует.
- Установлено: `addons/zylann.voxel/voxel.gdextension`, Windows editor/release DLL, license и editor icons. Бинарники других платформ не копировались; перед экспортом на другую платформу нужен отдельный пакет/gate.
- Назначение: точный derived greedy-mesh после завершения sculpt-жеста через `EmberVoxelToolsPreview` (`EmberVoxelModelResource → padded VoxelBuffer → VoxelMesherCubes`). Во время удержания остаётся более дешёвый штатный heightfield draft. С v2.47 native terrain также используется при наличии column water data: общий `EmberVoxelSurfaceMesher` добавляет поверх него canonical water/foam surfaces; per-voxel transparency по-прежнему безопасно выбирает stock fallback.
- Ownership: единственный writable source — `content/voxel_models/*.tres`. Addon не создаёт `VoxelTerrain`, не сохраняет собственный stream/store и не меняет Ember schema. Прозрачность на уровне отдельных ячеек пока вызывает безопасный fallback на штатный `VoxMesher`.
- Проверка: `test_voxel_tools_backend.gd` проверяет native classes, ZXY buffer order, palette/greedy mesh, world scale, cached relief parity и capability fallback; `test_surface_canvas_workflow.gd` закрепляет native terrain + fill-water composition; `test_surface_large_profile.gd` измеряет exact chunks на большой карте. Полный editor scan и прежние voxel/runtime tests проходят.
- Удаление: удалить `addons/zylann.voxel`; dynamic `ClassDB` adapter вернёт exact preview на штатный `VoxMesher`, `.tres`, Undo/Redo и runtime останутся без migration. Для отсутствующей DLL/класса действует тот же fallback.

### Native Godot voxel authoring APIs

- Статус: **принято в v1.98**, внешняя зависимость не устанавливается.
- Основа: custom `Resource` хранит исходные voxel-данные; `EditorPlugin` main screen даёт самостоятельную рабочую область и с v2.48 подключает штатные unsaved/external-data + editor-layout callbacks; `EditorUndoRedoManager` фиксирует strokes; `SubViewport + ArrayMesh` дают один preview/runtime builder; `EditorImportPlugin` допустим только как one-way `.vox` importer.
- Ownership: `content/voxel_models/*.tres` — единственный writable owner. Mesh, collision, prefab, thumbnail, GridMap и MeshLibrary — производные.
- Причина: штатных API достаточно для Ember props/tiles и material channels; готовые `.vox` importers обычно заканчиваются mesh-импортом и не владеют Ember-свечением, прозрачностью, физикой и 16/32 density.
- Удаление legacy: после parity report всех моделей удаляется каталог fallback и настройка JOI pack path для voxel-домена; архив можно хранить вне runtime-проекта.
