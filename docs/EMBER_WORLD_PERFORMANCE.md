# Ember — производительность мира

Обновлено: 2026-10-31. Это единственный владелец текущего performance-контракта
земли, растительности, объектов, воды и освещения. Здесь хранятся действующие
решения и незакрытые проверки; последовательность старых проб сюда не дописывается.
Активное действие — [NOW](EMBER_NOW.md), продуктовая очередь —
[Product Plan](EMBER_PRODUCT_PLAN.md), архитектура авторинга —
[World Authoring](EMBER_WORLD_AUTHORING_ARCHITECTURE.md).

## Цель и границы

- Минимум **120 FPS при native 2560×1440** на RTX 5070: бюджет кадра 8,33 мс.
  Средний FPS и GPU одного неподвижного ракурса этот порог не принимают.
- Ближняя плотность, состав нагрузки и внутреннее разрешение сохраняются.
  Дальний LOD принимается по покрытию, силуэту и плавности переходов.
- Камера меняет угол и масштаб: FOV 40/70, близкий и широкий/наклонный вид.
  Приёмка включает движение через стыки, холодный старт и возврат.
- Рабочая карта — `scenes/landscape_compact.tscn`; отдельный 576-метровый полигон
  является стресс-fixture, а не второй развиваемой картой.
- Forward+ и существующие Scene/Resource остаются основой. Новый renderer,
  mesher, формат мира или замена terrain не утверждены.
- Автор отложил сферу и `.exe`: сейчас обычный editor/gameplay без сферы.
  Механика сферы и три облика сохранены, отключение не означает удаление.
- GTX 1060 у автора — будущая проверка на реальном слабом ПК. Вариант 3/6 GB,
  CPU/RAM, разрешение и требуемые FPS ещё не заданы. Модель iGPU неизвестна.
  Меню качества/автонастройка сейчас отложены. Проверка 1060 не заменяет порог 5070.

## Доверенная текущая точка

Последняя интеграционная проверка: `D:/Codex/ember-overview-updates-20261031/integrated/`.
Предыдущий indexing baseline: `D:/Codex/ember-ground-publication-20261031/`.
`fine-profile/` и `after-profile/` — CPU phase attribution;`acceptance/` — fixed5мс,
`budget3/` — fixed3мс comparison. Production использует существующий startup barrier.
Native2560×1440,scale1,TAA ON,вечер,real Player/physics,95м/FOV40→70.
Dense576×576м:25848patches,64grass/10flowers/8wheat,859добавленных props.
Обычная трава/цветы увеличены на25% (25560stress patches); плотность/дальность прежние.
На main изменён только tuft_size212grass/flower nodes,камушки/пшеница прежние.

- Устранена повторная полная validation готовой пшеницы: bounded successful
  snapshots всех stored geometry/recipe fields замечают и in-place edits.
  Real-wheat targeted warm5,08→0,32мс,не whole-frame gain.
- Синхронная cache write дала cold wall641,24мс,из них598,475мс Storage.write.
  Теперь immutable payload пишет worker/private Storage. Synthetic slow80мс
  producer82,95мс→41мкс;native worker88,19мс завершился на кадре5,659мс.
  Это доказательство разделения потоков,не парный benchmark скорости диска.
- Observer больше не публикует уходящие overview вне admission deadline.
  Запросы объединяются в `_overview_dirty`; один регион восстанавливает overview
  перед release fine/collision. Coverage пересчитывается по текущему wanted;
  устаревший revision не освобождает новую поверхность. Weak map-owner lookup
  готовой травы очищается при exit/reparent;40000queries13,087→8,330мс изолированно.
- В `project.godot` выбран встроенный **Jolt Physics**, прежние HeightMap/Concave
  формы и controller сохранены. Live query partition: DEFAULT terrain p951,137мс,
  props0,008;Jolt terrain0,048мс,all0,052мс. Это локальный CPU gain≈22–24x,не FPS.
- Render upload земли/стыков теперь использует exact attribute indexing в CPU worker:
  стандартный SurfaceTool.create_from_arrays→index→commit_to_arrays. В fixture26112
  vertices→5253/5448 без удаления треугольников,смены атрибутов/LOD thresholds.
  Ground-upload active-frame median2,646→0,579мс,p954,135→1,137мс;это CPU scope.
  Canonical layout/коллизия/носители обликов остаются fine,temporary upload не сериализуется.
  Native pixels/shadows на flat/slope/mixed и двух LOD biases exact;швы exact.
- Исправлена взаимная блокировка priority queue: ближайший waiter занятого digest/read
  slot повторно вставлялся в текущий dispatch и вытеснял дальнего владельца результата.
  Повторные turns теперь идут в следующий dispatch;band/urgent/FIFO и allowance прежние.
  Cancel/prioritize/release учитывают обе очереди. Регрессия RED→GREEN,реальные
  bounded material/read slots и native cancel/teardown PASS. Без instrumentation
  старый static startup не завершился за90с;исправленный завершился за21,823с.
  Это устранение зависания,не множитель скорости обычного запуска.
- Clean gameplay после queue fix,с Jolt/indexed upload и allowance5→3мс:
  median6,031/6,757мс,p958,284/9,142,
  p999,682/10,687,max19,768/15,729;
  4.81/10.02% кадров>8,33мс.
  **Минимум120FPS не достигнут.** До queue fix p958,334/9,105мс;это наблюдение разных
  clean runs,не точный причинный FPS multiplier. Редкие clean stalls ещё открыты.
- Frozen GPU (мс): near40 median5,434/p955,693;near70 median5,826/p956,061;wide40 median6,109/p956,360;wide70 median6,087/p956,373.
  Это отдельно от gameplay FPS;GPU correctness traces stale и не используются.
- Scatter-cache-cold out/return: absent/pending/floor0/0 в каждом кадре;
  release281/281,return281 exact;Source/shape IDs/transforms576trees exact.
  Geometry/shader caches тёплые;startup21,487с не принимает fully cold startup.
  Дополнительно actual foot gap min−0,00146raw/max0,56130raw:нет провала через землю.
  Correctness wall включает измерительный checker и не заменяет clean FPS.
  GPU fields внутри correctness traces INVALID/stale (timers disabled);
  авторитетны только frozen GPU snapshots и отдельные clean wall timings.
- Existing WorldCanvas.is_world_preparation_complete читает прежний _startup_complete;
  DetailPreparation.frame_budget_us использует5мс под cover,3мс после reveal.
  Editor/активная кисть/owners без такого startup barrier сохраняют5мс,brush cap4мс.
  Phase не дублируется в context:recreate/reparent читает актуального owner.
  Новый fixed3мс после indexing прошёл coverage0/0/release/return,но startup27,799с
  вместо15,003с fixed5мс;выбран фазовый вариант(startup21,487с в текущем run).
  Старый3мс до IO/index fixes с absent4/3 не является текущей приёмкой.
- Runtime sleeping admission завершает bounded sweep один раз на authoritative
  policy/source epoch,а не повторяет его каждый кадр. Новая область/Source/transform/
  footprint/index требуют нового sweep;paused ancestors оставляют retry до resume.
  Editor/custom projection без epoch сохраняет прежний periodic fallback.
  Same-route instrumented sleeping median0,713→0,019мс,p950,916→0,036мс;
  это локальный CPU scope,не множитель FPS. Stable128polls:65386→0повторных bounds reads.
- Повторные SHA/file checks saved material roles перенесены в один worker на context.
  Runtime потребляет приватные saved templates и прежний bounded CPU payload cache;
  cold/changed file перепроверяется прежним sync path только при digest mismatch.
  Independent GPU textures/4mutable images,texture revisions и PNG weak bank сохранены.
  Same-route role bind median1,262→0,285мс,p951,565→0,345;
  digest poll p95all0,049мс. Active queued p954,584→2,414мс;это CPU scopes,не FPS.
  Slow80ms producer80,922мс→native44мкс,worker продолжает IO при идущих кадрах.
  Layout/source guard и coalesced live profile replay сохраняют preview через await.
  Native byte parity/private binding/file-change/cancel/join/Undo/save/reopen PASS.
- Validation/admission regressions RED→GREEN;native pattern-library,
  surface-rules,main-view и dense async/cold PASS. Writer snapshot/cancel-before-
  enqueue/count+bytes/join PASS;Astra review существенных blockers не нашёл.
  Текущий dense run включает прежние malformed-input writer guards.
  Publication admission RED→GREEN: expired budget/quick reverse/stale overview/
  per-region deadline/convergence;travel и native resident-slot reuse PASS.
  Owner lifetime:ancestor reparent/detach/reattach/off-tree и detail preparation PASS.
  Jolt native:5120surface rays(max height error0,00000763raw),step30/60/120Hz,
  Hoshi capsule/movement и physical crates/F/G/push/weights/save/Undo/reopen PASS.
  Editor/game требуют restart для нового backend;ручное ощущение движения/предметов OPEN.

Native LOD resident-деревьев,feature programs,local HeightMap и HP query сохранены.
Прежний LOD wide6,2–6,3→5,7мс,guards editor/preview/look1/2,LOD0 pixel controls —
`D:/Codex/ember-wide-objects-20261031/`;это отдельный GPU gain,не whole FPS.
Material evidence — `D:/Codex/ember-material-path-20261030/acceptance/`;
отклонённый grass map-projection cache — `D:/Codex/ember-cost-breakdown-20261031/`.
Main Sun angular0/filter2/blur1/distance1600;ручная камера/полосы теней/размер травы OPEN.

## Измеренная причина и принятые решения

Attribution31.10: одна возобновлённая задача пшеницы занимала до26,3мс;
повторная полная voxel/ownership validation выполнялась даже при готовом bake.
PatternBake теперь проверяет неизменность сохранённых полей native equality,
хранит до8 приватных успешных validation snapshots и замечает in-place edits.
Real-wheat regression RED→GREEN: warm≈5,08→0,32мс; это не whole-frame FPS.
На cold enlarged route отдельно пойман wall641,24мс с598,475мс синхронного
Storage.write. Это измеренный IO bottleneck; warm probes имели write0 и его
не могли обнаружить. Writer перенесён в bounded worker; cold follow-up подтвердил exact release/return без absent buffers.
Новый3мс runtime allowance проверен после indexing/IO fixes;startup/editor сохраняют5мс.

Те же geometry/draw counts с диагностическим simple LIT fragment/light и прежними
PCSS shadows дают near40/70 GPU 5,592/6,356 вместо примерно 9,4–9,9 мс.
Без shadow receiving — 3,634/4,945 мс. Это нижняя диагностическая граница,
**не готовый художественный материал** и не обещание всего выигрыша в production.
Материал влияет на prepass тоже: near40 depth/shadow/opaque
1,526/0,722/6,312→0,704/0,457/3,141 мс в simple LIT-пробе.
Этот GPU-резерв частично использован feature programs; прежняя simple-LIT
проба не объясняет оставшиеся CPU/IO stalls нового gameplay-маршрута.
Полная замена земли или движка текущими данными не обоснована.

- Active cheap ground/grass/flower уже исключают optical height/POM и manual
  `DEPTH`. Повторное выключение неактивного блока не является новой оптимизацией.
- Ранний flower alpha clip сохраняет artwork и threshold 0,55. Прежняя native
  RGB parity проверена при QA TAA OFF; игровой TAA остался включён.
- Shared foreground budget **5 мс** включает ground, active grass callbacks и
  late scatter/publication. Nested sleeping admission не считается дважды.
- Бюджет 4 мс отклонён: были реально отсутствующие буферы в outer fade band
  примерно 20,8–24 м. Уменьшать allowance до отсутствующей земли/травы нельзя.
- Uniform tables 16 slots не дали общего устойчивого GPU gain и не внедрены.
  Общий sampling guard тоже отклонён; новый cache owner не добавлен.
- Прежний QA-only detailed shader без неактивного voxel-light/quantization дал
  около 0,2–0,8 мс GPU и B/A1 RGB exact в четырёх poses. Он **QA-only**:
  live three looks/anomaly/preview/mixed palette/full gameplay не интегрированы.
  Конкретно `LIGHT_VERTEX` виновным не установлен.
- Overview сохраняет неиндексированные vertices и расширяет AABB. Inventory
  572 непустых overview meshes обнаружил всего 0–1 лишний camera candidate
  в каждом из четырёх poses. Это не actual draws и не shadow-cascade culling;
  найденная неточность не объясняет основную нагрузку. Tight AABB не внедрён.
- ResidencyEdge diagnostic экономил около 0,5 мс near, но грани сохранены:
  HeightMap не доказывает совпадение base и всех render LOD соседей. Не закрыты
  LOD boundary curves, edit/reuse/extension-preview invalidators. Наличие щелей
  нынешний аудит не утверждает.
- Shadow cache не внедрён: sampled shadow generation около 0,5–0,7 мс сама
  не объясняла основной кадр. Кэширование требует invalidation солнца, камеры,
  геометрии, лепки, объектов и анимации; чужой pipeline не доказывает наш выигрыш.
- Отдельный 611 мс outlier не приписан screenshots/driver/disk без корреляции.
  В другом frame 2313 renderer setup занимает 241,52 из 278,31 мс, точная
  операция внутри setup ещё не установлена. Интервал между `_process` не CPU cost.

Скомпилированные программы активных возможностей подключены к runtime ground/cards
в `EmberVoxelSurfaceMaterials.refresh_terrain_features`; источник/формулы shader прежние.
10TERRAIN_FEATURE_FIELDS читаются после scene/profile commands; исходные uniforms/значения
сохранены, compiled code использует constant aliases. Общий LRU≤32Shader, в stress2programs;
нет копий mesh/texture и отдельного renderer. Изменение этих flags через raw
set_shader_parameter требует refresh после пачки; текущие Materials/MapLoader/Projection/
GrassPatch setters подключены. Световые цвета, текстуры, fade/позиция и форма аномалии живые.
ShaderInclude читается через ResourceLoader; итоговый expanded source совпал с измеренным
FileAccess-вариантом. Export gate этим не принимается. Native Godot tool-editor/headless
сохраняют generic path; custom gameplay/editor commands проверены нативными API/render tests.
Полная фиксация всех bool/int и geometry-only/cover-style/mass-branch diagnostics не внедрены:
широкая фиксация мешала бы live controls; узкие варианты не дали общего выигрыша.
Evidence текущего среза: D:/Codex/ember-material-path-20261030/acceptance/, acceptance.log,
production-pixel-parity.json, features-mixed-final-test.log. QA-only meta bypass для A/B находится
только в disposable stage; его нет в production. Старые diagnostic *.log здесь пустые
из-за Console redirection; их .json/PNG — диагностика, не проверка отсутствия runtime errors.

## Владельцы и работающий путь

### Земля и общая физическая поверхность

`scripts/prototypes/ember_terrain_pilot_projection.gd` владеет publication,
fine residency, overview и очередью. `ember_terrain_smooth_surface.gd` готовит
отдельный render_detail и native mesh LOD; каноническая authoring grid остаётся
источником. Native LOD 4096→2048→1024→512 и оба blend modes проверены.
Старый `_queue_ground_lod()` со skip style1 не описывает этот smooth-путь.

`ember_terrain_pilot_mesh.gd` и его `EditorTilePublication`
публикуют точный HeightMapShape3D из той же float32 grid/диагоналей.
Holes/walls/nonuniform placement и deform study используют Concave fallback.
Canonical faces, floor field, picking и navigation не меняются на дальний LOD.
Native rays/cache/offset/affine/deform технически проверены; ручные стыки OPEN.
Физический backend — Jolt Physics (`project.godot`),не новый renderer/addon/формат.
В live query A/B земля,а не props,занимала≈1,14мс в DEFAULT;Jolt с прежними
HeightMap снизил p95 до0,048мс. Exact Concave control дал лишь≈20% и не перенесён.
Совместимость — native surface/step/Hoshi/crates и dense cold/return;ощущение вручную OPEN.
Официальная интеграция: [Using Jolt Physics](https://docs.godotengine.org/en/4.6/tutorials/physics/using_jolt_physics.html).
Brush hover временно удерживает fine surface; runtime remesh не добавляется
на мелкий editor input. История/preview/commit принадлежат прежним editor owners.

### Объекты и растительность

`scripts/prototypes/ember_world_detail_policy.gd` задаёт локальные области,
prepare/fade/release и hysteresis. `scripts/ember_grass_patch.gd` использует
пространственные MultiMesh patches; источник расстановки и плотность не заменены.
Grass prepare 30 м, fade 16–24 м, release 32 м; fine cap 384 прежний.
Clear/stale/worker cancellation, exact scatter и unload/return проверены.

Объекты используют общий native mesh LOD и shared immutable geometry. В runtime
look0 carrier получают и resident-деревья; их экранную детализацию выбирает камера,
а не радиус подготовки игрока. `object_lod_allowed()` сохраняет editor/preview/
look1/2 guards и проверку Source перед публикацией. Тяжёлые
производные carriers живут локально и освобождаются последним потребителем.
Source nodes и физика объектов пока остаются. Реальный HLOD/cluster/impostor
не объявлен реализованным. Восстановление и ввод/история применяют прежнюю
порционную публикацию, один Undo и исключение незавершённого Apply из save.

`scripts/ember_detail_preparation.gd` объединяет foreground allowance и очереди.
Runtime poll epoch/weak context переиспользуются по identity/revision/policy/
transform/brush; patch отдельно проверяет dirty/bounds/material/shader/anomaly.
Editor fast guard отключён; invalidation/lifetime/cancel не заменяются таймером.

### Материалы, вода и кэши

`scripts/ember_voxel_surface_materials.gd` и
`shaders/ember_compact_terrain_body.gdshaderinc` — общий material owner.
Saved CPU packing bounded 16/context по source/file SHA/texture revisions;
редактируемые CPU images и GPU bindings приватны, PNG banks weak/shared.
Нельзя объединять editable preview state ценой утечки между объектами.
Artwork/depth/collision принадлежат своим данным, не shader cache metadata.

Water Regions отбирает immutable eligible cores, сохраняя actual demand,
publication/readiness/cancel. Floor-capture viewport отключён только когда
нет опубликованного water demand; frustum/region count не заменяют этот gate.
Water-camera vertex discard исключён из shadow pass. Один исправленный дефект
не принимает всё self-shadow мерцание зелёных склонов.
Подробности water look/activity — [Water Rendering](EMBER_WATER_RENDERING.md).

Geometry/LOD, water, tree, details, height, solid и anomaly caches остаются
производными: content/version/dependency key, validation, stale/corrupt fallback.
CPU image LRU 24 MiB и geometry disk cache 512 MiB не ограничивают RAM/VRAM мира.
Source terrain и authoring nodes пока целиком в памяти; detail release этого
не исправляет. Масштабирование всей памяти **OPEN**.

Подготовка scatter-кэша: `ember_detail_preparation.gd` принимает immutable
снимок готовых transforms, затем один worker/private Storage выполняет
serialization/ZSTD/flush/atomic rename. До16 активных+ожидающих jobs и8MiB
оценки payload snapshots; сериализованный/сжатый scratch отдельно, это не RAM peak.
Переполнение пропускает необязательную запись, а не публикацию травы. Cancel
проверяется до принятия; принятый content-addressed snapshot валиден после ухода
patch. Обычный patch release не ждёт IO. Context teardown синхронно завершает
принятые записи/join, поэтому latency закрытия карты остаётся отдельным gate.
Runtime scatter reads используют `read_async` того же preparation owner:
до2 активных+готовых результатов на context,private Storage/settings snapshot,
checksum/decompress/decode/transform validation в worker. Completed result держит
слот до budgeted delivery. Production raw input≤4MiB/read;decoded/scratch и
переданные patch данные отдельно,это не общий RAM cap. Sync `read` оставлен
для compatibility/tests. Patch cancel не ждёт IO;context teardown join может ждать.
Материал в подготовке получает те же light/gray/cover обновления,что опубликованный:
устаревший кандидат больше не перезаписывает preview после await. Object edits
инвалидируют также unpainted scatter;null/removed projection не создаёт новый context.
Native slow80ms regression: producer80,788мс→40мкс с продолжающимися кадрами,
не benchmark общего FPS. Native cache/lifetime/material-preview и pattern-library
Undo/Redo/save/reopen PASS;ручное ощущение кисти/движения остаётся OPEN.
Async read evidence: `D:/Codex/ember-jolt-frame-20261031/`:
`profile/` — pre-fix instrumentation,`acceptance/result.json` — финальный dense run.
Начальный failed instrumentation log исключён;startup31,657с с тёплой geometry/shaders
не принимает fully cold startup. GPU correctness traces stale,их не использовать.

`bind_saved_material_roles_async` использует тот же DetailPreparation:одна digest
задача/готовый результат на context,immutable path/layout snapshots,без Node/callback
в worker. Ready только будит consumer;доставка/привязка входят через wait_for_turn.
Ушедший patch отменяет consumer без ожидания IO,task держит слот до join;context
teardown дожидается IO и остаётся latency gate. Синхронный public material path
сохранён для редакторских команд/tests. Мismatch digest вызывает прежнюю sync
перепроверку,чтобы save между observation/delivery не отравил payload key.
GrassPatch проверяет source/layout после await;во время ожидания role binding
последние live profile commands на palette IDs объединяются и воспроизводятся
после получения приватных lookup images. Reset/cancel освобождают временные ссылки.
Малый probe без resident PNG-bank consumer пересоздавал банк≈75мс:он исключён
из оценки warm-field gain,не объясняет автоматически прежний57мс gameplay frame.
Полный cold startup/нулевые consumers/долгая память сохраняют отдельные gates.

Runtime sleeping admission отсекает broad-bin false positives по прежней policy
и свежим cached world bounds; собственный stale bounds cache не добавлен.
`PatternBake._validated` исключает external/tree validation с внешними зависимостями;
независимый Astra review не нашёл пропущенных dependencies/thread-safety blockers.

Render upload использует штатную [SurfaceTool.index](https://docs.godotengine.org/en/4.7/classes/class_surfacetool.html#class-surfacetool-method-index).
prepare_render_upload не генерирует LOD/нормали и не меняет Source:сопоставляет
полные vertex attributes,переназначает base/все LOD indices,сохраняет треугольники.
Уже planar6-vertex путь/неподдержанные каналы/indexed input остаются на прежнем пути.
MeshBuilder.prepare_editor_tile делает CPU indexing после world offset;HeightUpdateJob
использует тот же leaf. GPU allocation/publication остаются на main thread.
Transient render_upload/residency_edge_upload живут до commit;canonical arrays/layout,
physics/navigation/editor и cache schema/version прежние. Это не whole-memory unloading.
Ограничения потоков — [Godot4.7 Thread-safe APIs](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html).
Native5120surface rays,max error0,00000763raw;existing8tools/Undo/Redo/save/reopen и
WorldDetail flat/mixed/LOD/canonical-carrier/height-update regressions PASS.
Личные мазки/движение/сфера/широкие художественные переходы автором ещё не приняты.

`_sync_ground_residency` теперь только помечает уходящие регионы, сохраняя fine,
physics и smooth fields. `_poll_overviews` использует одну транзакцию для completed
job и dirty region: актуальный wanted/revision → overview → release fine.
Deadline проверяется перед каждым регионом;время одной публикации не делится.
До продвижения очереди возможно временное превышение числа fine hosts;это не новый
жёсткий memory cap. Fresh run проверен;после горячей замены скрипта старый overview
без revision требует пересоздания проекции. Source/дальность/плотность прежние.

## Единственная текущая последовательность

1. **Общий бюджет кадра.** Production startup/editor5мс,gameplay3мс;
   clean p95≈8,284/9,142мс;120 gate OPEN. Ground upload убран из
   главного bottleneck:active-frame p954,135→1,137мс. Collision prepare p95≈0,164мс
   в контрольном profile,release host≈0,142мс;это не те же интервалы,что render wait.
   **Следующее действие:** final-frame attribution оставшихся wide70 slow frames,
   особенно overview publication/observer и ожиданий render submission/upload.
   Актуальный scoped run:overview transaction active p95≈2,196мс,
   overview mesh0,764мс,edge0,621мс,residency1,189мс;scopes вложены.
   RenderingServer.mesh_surface_update_index_region найден как штатный кандидат;
   native prototype не завершён,production overview не менялся. Перед внедрением
   нужны pixel/shadow/coverage parity и тот же dense stress,не только наличие API.
   Прежний pipeline control показал stalls без compile counter growth;не объявлять
   shader warmup универсальным исправлением. Cold checker/frozen GPU/clean timings
   различаются;scopes вложены,их p95 не складывать. Старые57мс не объяснены.
   Меньший бюджет повторно не подбирать без новой measured cost/coverage причины.
   Full120 gate OPEN;сфера/города/NPC/wind этим не принимаются.
2. **Хвосты движения и полосы теней.** Привязать stalls к publication/upload/
   physics/renderer setup, не складывая параллельные CPU/GPU интервалы.
   Чёткие тени понравились; тонкие полосы на малых перепадах не воспроизведены.
   Shadow acne/bias — гипотеза, также возможны precision/cascade/LOD/нормали.
   Проверка — тот же slope/camera/motion и изоляция receiving, затем адресные
   controls без отрыва контакта и ухудшения резкости. Bias вслепую не увеличивать.
3. **Полная память и запуск GTX 1060.** Сопоставить source/nodes/physics/
   geometry/textures/renderer на 72/144/288/576 м при той же плотности.
   Считать resource/RID без двойного учёта, process private/working set,
   GPU allocation/residency отдельно, cold/warm peaks и release/return plateau.
   Если растёт именно source/nodes — адресная/ленивая загрузка у прежних owners
   с сохранением save/Undo/physics; не новая схема ради предположения.
4. **После world gate — mixed stress.** Ветер, dense flowers/wheat, массовые
   NPC/Hoshi, физические предметы, деревня/город, local lights и wet world.
   Их частичные механики и редактор уже есть, общий performance gate не пройден.

Порядок не запускает меню качества, новый GI, смену renderer или новый world
planner. Новые идеи остаются у своей темы до конкретной измеренной причины.

## Общая приёмка и оставшиеся gates

Для изменённого фундаментального пути baseline и послеизменённый маршрут
используют одинаковые source/seed/load/camera/native quality. Engine editor,
fixed render snapshot и настоящий gameplay называются отдельно.
Нужны CPU/GPU/wall, p95/p99/max/stalls, память, cold/warm и release/return.
Viewport/camera/FOV/scale читаются из настоящего runtime, не из metadata.
Физика/высота/navigation должны сохранять одну поверхность; pending не равен hole.

Открыты и не принимаются предыдущими локальными PASS:
- 120 FPS, p95/p99/max и невоспроизведённые stalls полного кадра.
- Зелёные склоны self-shadow в движении и новые тонкие полосы жёстких теней.
- Ручные near/far LOD, широкие/наклонные виды, coverage и бесшовные переходы.
- Fully cold startup, длительное движение/память, произвольный teleport.
- Общий wet-world appearance/readiness, wind/mixed нагрузка и слабое устройство.
- Авторские кисть/мышь/125%/save/reopen/discard и полный authoring сценарий.
- Сфера, экспорт, package size/used-record selection и отдельный release startup.
- Причины прежних AV/shutdown/TDR; отсутствие нового вылета не означает fix.

Для editor data/commands обязательны относящиеся Undo/Redo/save/reopen/discard/
validation. Автоматический PASS не заменяет автора. Нужен связанный stress,
а не весь suite без причины; успешные независимые проверки не повторяются.
Подробные исполняемые сценарии — [Test Plan](../MIGRATION_TEST_PLAN.md),
процесс — [Workflow](EMBER_WORKFLOW.md#пайплайн-производительности).

## Что берём из опубликованных игр

- [miHoYo / Zhenzhong Yi, Unity Japan, 2021](https://www.slideshare.net/slideshow/210617-unity-dojo20211mihoyozhenzhongyi/249437133),
  slides 9–10/18–23/35/38–44/56–62: отдельные mobile и PC/console pipelines,
  динамические сутки/погода; дальние cascades обновляют interleaved, soft filtering
  ограничивают penumbra mask, AO считают при половинной ширине/высоте.
  Статические локальные тени/probe data готовят заранее, динамическое дополняют
  и обновляют порционно. Это не доказательство полностью запечённого солнца.
  Принцип — ограничить место/частоту дорогой работы; не копировать 8 cascades
  или миллисекунды чужой платформы. Genshin terrain/grass/streaming не установлены.
- [HoYoverse 4.4, 2024](https://blog.playstation.com/2024/01/19/genshin-impact-version-4-4-brings-new-friends-and-visual-enhancements-jan-31/):
  GFF/Gradient Tint Rock имеют упрощённый mobile вариант. Полезны крупные
  цветовые массы и атмосфера; статья не доказывает fog как маскировку LOD или gain.
  [Версия 4.0](https://blog.playstation.com/2023/08/04/genshin-impact-version-4-0-launches-august-16-first-details/)
  описывает GI в отдельных областях, не алгоритм или бюджет нашей сцены.
- [Campo Santo, Firewatch, GDC 2016](https://media.gdcvault.com/gdc2016/Presentations/Ng_Jane_MakingTheWorld.pdf),
  PDF 45–46/52/29–39: дальнее дерево до 4-triangle billboard, меняющийся alpha
  cutoff сохраняет пышность, упрощаются тени; мир загружается секторами.
  Применимость — coverage/силуэт и отдельная цена теней/памяти. Shadow proxy
  может разойтись с нашей лепкой; переходные volumes требуют адаптации к камере.
- [Guerrilla, Horizon Zero Dawn, GDC 2018](https://media.gdcvault.com/gdc2018/presentations/gilbert_sanders_between_tech_and.pdf),
  Shading → Pixel Program: Alpha: depth-only foliage и дальнейшее shading
  с depth equality. Проверено по индексированному тексту; точный слайд не подтверждён.
  Цель доклада 30 FPS. Forward+ уже имеет prepass, Ember — early alpha clip:
  это повод измерить повторную fragment работу, не добавлять дублирующий renderer.
- [Godot GPU optimization](https://docs.godotengine.org/en/stable/tutorials/performance/gpu_optimization.html):
  batching снижает submissions, но группа целиком ограничивает culling;
  fragment/texture bandwidth и alpha overlap имеют собственную стоимость.
  Один draw не делает её бесплатной. Общий GPU/CPU% не заменяет pass/frame times.
  [Shadow bias](https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html#tweaking-shadow-bias)
  требует проверки контакта/тонких теней, не слепого повышения значения.

- [Godot mesh LOD / meshoptimizer](https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html)
  уже является нашим готовым алгоритмом. Исправлено его подключение к resident
  деревьям вместо нового renderer. [ArrayMesh.shadow_mesh](https://docs.godotengine.org/en/stable/classes/class_arraymesh.html#class-arraymesh-property-shadow-mesh)
  требует тех же позиций вершин и LOD: произвольный дешёвый hull туда не подставлять.
- [Terrain3D architecture](https://github.com/TokisanGames/Terrain3D/blob/main/doc/docs/system_architecture.md):
  geometry clipmaps создают сетку один раз и меняют высоты на GPU. Это подходящий
  внешний ориентир для отдельного terrain-пути,но замена нашего Source/editor/
  трёх обликов/physics требует доказанного terrain-geometry bottleneck и решения автора.
  [Terrain3D foliage](https://terrain3d.readthedocs.io/en/latest/docs/instancer.html)
  использует пространственные MultiMesh cells и отдельный shadow impostor.
  У нас пространственные patches уже есть; чужой размер32м не переносить вслепую.
- [GPUOpen grass,2024](https://gpuopen.com/learn/mesh_shaders/mesh_shaders-procedural_grass_rendering/):
  GPU generation,плавный LOD,компенсация покрытия шириной оставшихся лезвий.
  Это не разрешение уменьшать нашу ближнюю плотность. Mesh shaders не универсальны
  для слабого-PC пути: [NVIDIA](https://developer.nvidia.com/blog/introduction-turing-mesh-shaders/)
  вводит их с Turing;базовый путь для GTX1060 не должен их требовать.
- [Godot-imposter,MIT](https://github.com/zhangjt93/godot-imposter),pin
  `e86fd4786d36202129c7b7d5873131fc21dbbe72`: external-only proof,не установлен.
  Бейкер требует адаптации наших ShaderMaterial alpha/normal;standalone preview
  выявил ещё alpha-weighted blending/edge issues. Первый batch с shader fallback
  INVALID,его GPU цифры отвергнуты. Исправленный standalone — только визуальный
  прототип,без production/performance приёмки. Сейчас выбран существующий native LOD.

## Воспроизводимость и evidence

Последние авторитетные наборы:
- `D:/Codex/ember-overview-updates-20261031/`:fairness-integration-red/green и
  native fairness/cache-read/material/preparation/pattern-library logs;startup-before
  timeout90с, startup-after21,823с. profile-fixed/ — вложенные CPU scopes;
  profile-startup-failed/ и index-update-probe — не приёмка. Integrated/ — чистый
  production dense маршрут после queue fix;verification-summary.json хранит итог.
- `D:/Codex/ember-collision-cost-20261031/`:queries/ — live all/none/repeat;
  partition/ — terrain/props/none в живом step со всеми streamed slots;
  triangles/ — exact Concave control,не production;jolt-query/ — unchanged HeightMap.
  jolt-full/ — full dense/cold/return/actual foot;jolt-final/ — повтор clean/GPU;
  default-return/ — ближайший DEFAULT control;jolt-budget3/ — REJECTED coverage/startup.
  probe/ с disabled Scene INVALID для стоимости collision (все hits0),не baseline.
  Native targeted logs/root-backend.log и verification-summary.json фиксируют границы;
  ранние partition startup и crates missing-fixture/refusal — setup failures,не приёмка.
- `D:/Codex/ember-ground-admission-20261031/`:baseline/ — исходные enlarged routes;
  final/ — production native dense/cold/return/frozen GPU;profile/ — отдельные CPU
  scopes,не cleanFPS. Admission RED→GREEN,travel/native slots/owner lifetime/detail
  preparation logs и verification-summary.json. Baseline первый out имеет117мс
  outlier;warm trace out p9512,718мс. Парный общий FPS gain не заявлен.
- `D:/Codex/ember-active-world-20261031/`: phases/attribution/callback-detail/
  material-detail — CPU isolation;production5 — measured sync-IO stall;
  async-final — enlarged native5ms/cold/return and frozen GPU;main-view — main
  grass before/after. acceptance/ — REJECTED3ms (есть absent buffers),не PASS.
  validation/cache-write RED→GREEN,preparation/cache-maintenance/native logs и
  verification-summary.json фиксируют scope;correctness GPU timers stale,не использовать.
- `D:/Codex/ember-wide-objects-20261031/`: probe/ — cast/LOD attribution; первый unshaded control INVALID
  из-за duplicate render_mode,его lighting цифры отвергнуты. lighting-valid/ —
  исправленный A/B/A: wide40/70 без lighting/receiving дешевле на0,330/0,536мс GPU;
  это не полная цена материала,production освещение сохранено;
  resident-lods/ — cause isolation;acceptance/ — production stress;lod0-parity/ —
  base geometry images;verification-summary.json — verdicts. Surface-lods strict
  attribute parity не прошла;impostor-probe первый batch INVALID,не приёмка.
- `D:/Codex/ember-render-decision-20261030/`: controls/, profile-controls/,
  detailed-controls/, guard-controls/, crisp-gameplay/, verification-summary.json.
  В двух последних shader probes label `profile_tables` наследован harness и
  означает их candidate, а не uniform-table реализацию.
- `D:/Codex/ember-frame-budget-20261030/`: final5/ — coverage/release/return;
  alpha-gameplay/ — прежний полный кадр; alpha-probe/ — GPU A/B/A;
  alpha-pixel/ — parity TAA OFF; HeightMap/epoch/shared-budget logs.
  coverage-final/shared4 — отклонённый budget, не принятый результат.
- `D:/Codex/ember-frame-accounting-20261030/selection-clean-valid/` — прежний
  baseline; selection-clean/ INVALID из-за устаревших stage sources.
- `D:/Codex/ember-active-frame-20261030/` — предыдущие shadow-pass/profiling
  и water/material lifetime доказательства; старые тайминги не текущий baseline.
- `D:/Codex/ember-world-integration-qa-20261029/` — native LOD/physics/3looks;
  `C:/Users/novos/Documents/Codex/2026-10-29/ember-grove-scale/` — 859 props/plan;
  `D:/Codex/ember-optimization-team-20261029/` — общий preservation manifest.

QA workspace/caches на D:; child-only APPDATA/storage wrapper:
`D:/Codex/ember-visible-first-20261029/Run-GodotQa.ps1`.
Не запускать рабочий checkout с `--headless --editor`, не трогать чужие процессы.
Stage sources сверяются с root до прогона и восстанавливаются по SHA после.
CPU image/texture lifetime и холодный cache не подменяются прогретым stage.

## Отложенные сборка и сфера

DerivedDataCache.SHIPPED_CACHES: geometry/water/trees/details/height/solids/anomaly.
PreparedBundle/ExportPlugin используют прежние keys/transport/validation;
runtime local→packaged fallback не применяется к editor/custom test directories.
Diagnostic exporter сохраняет authored data, восстанавливает производные solid
materials из metadata, включает динамические shader/prefab/PNG dependencies.
Startup barrier ждёт ground/physics/LOD, foliage, optional sphere, water и camera
до управления. `--ember-profile` включает StartupDiagnostics; без флага sampler off.

Диагностическая Windows x86_64 release `.exe` проверена на одной main-copy;
это не shipping builder и не приёмка персонажей/игры. Prepared snapshot содержит
лишние варианты; used-record selection, multi-map catalogue, минимальный package,
чистый release startup/другой ПК/экспортные ресурсы остаются OPEN.
Артефакт: `C:/Users/novos/Documents/Codex/2026-10-28/ember-build-probe/`.
Прежняя сфера давала около 40 с подключения, первый render `.exe` около 17 с;
конкретные операции не разделены и отложены автором. Без сферы editor/gameplay
проверяются отдельно; старые 1600×900 export FPS не сравниваются с native1440.

Перед возвратом к сборке согласовать платформу/карты, отбирать только используемые
validated prepared records и не включать рабочие/старые caches. Source bytes,
derived bytes, build/user caches, итоговый пакет, RAM/VRAM и время подготовки/
старта — разные бюджеты. Универсальный предел MB не утверждён. Editor сохраняет
отзывчивость и authoring state; экспорт не заменяет runtime оптимизацию.
Сначала аппаратный и memory gate, затем дополнительный HLOD/bake только по
измеренному ограничению. Кэши удаляемы без потери карты; покадровая история на диск
не сохраняется. Дорогая новая зависимость/owner требует отдельного решения.

## Навигация после сокращения документации

Старые результаты 28–30.10 из World Authoring сжаты в текущие разделы выше.
Незакоммиченные оригиналы сохранены перед переносом:
`D:/Codex/ember-doc-restructure-20261030/original/`, manifest-before.json.
Backup и Git служат истории, не вторым активным backlog. Ссылки evidence остаются
проверкой конкретного утверждения; повторные PASS и журнал команд сюда не дописывать.
