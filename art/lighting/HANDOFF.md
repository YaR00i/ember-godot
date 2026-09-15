# Graphics d97c — передача, 15 сентября 2026

Кандидат реализован и автоматические gates пройдены. Художественная приёмка,
навигация/input в реальном редакторе и интеграция основным координатором OPEN.
Этот graphics task не становится основным координатором. Base aeab62e;
main checkout C:/Users/novos/Projects/ember-godot не редактировался.
Commit/push не выполнены, следующий срез не начат.

## Что переносить

Целиком только семь production files:

- shaders/ember_diorama_light.gdshaderinc — новый общий light response;
- shaders/ember_voxel_toon.gdshader;
- shaders/ember_voxel_transparent.gdshader;
- shaders/ember_voxel_surface_water.gdshader;
- materials/ember_voxel_toon.tres;
- materials/ember_voxel_transparent.tres;
- scripts/ember_lights.gd.

scripts/ember_map_loader.gd принадлежит основному world-editor срезу. Переносить
только одну согласованную строку в _tune_look_environment после прежних
quality-off flags:

```gdscript
EmberLights.apply_diorama_environment(e, _content_node("Look/Sun") as DirectionalLight3D)
```

QA: tools/render_diorama.gd, tools/test_diorama_materials.gd,
tools/run_diorama_qa.ps1, tools/check_graphics_sources.py и art/lighting/**.
В четырёх больших документах переносить только секцию между маркерами
BEGIN/END graphics-d97c-20260915: docs/EMBER_NOW.md,
docs/EMBER_TECHNICAL_HANDOFF.md, docs/EMBER_PRODUCT_PLAN.md,
MIGRATION_TEST_PLAN.md. Полные документы worktree старее main; не заменять ими
актуальные документы и не копировать полный loader. Готовые вырезки находятся
в documentation-sections.md.

## Результат и пределы

Тёплый directional свет даёт сливочно-золотистые освещённые поверхности и
прохладную цветную тень; переходы toon bands/shadow mask смягчены. Материалы
opaque/alpha/water сохраняют отдельных владельцев fragment/depth/alpha.
Вода: broad field, integer hash, network, глубина, alpha, glints, время,
контактная пена и геометрия прежние; изменён только light(). Холодный directional
и локальные лампы сохраняют прежний ответ. Foam/contact/wake не менялись.

Effective ambient записывается только в Environment RID через
[RenderingServer.environment_set_ambient_light](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-environment-set-ambient-light).
Sun/Environment Resources и authored properties не клонируются и не записываются.
Guard применим к текущим тёплым downward Sun сценам и не заменяет day/night schema.
Active sibling Moon запрещает ambient override; warm Moon shader response
проверен отдельно и не объявляется абсолютным определением дня по цвету.

Shader не расширяет реальную PCF penumbra и не создаёт новые просветы в кроне.
Blob silhouettes и слоистые боковые грани дерева остаются свойством модели.
Полосы пляжа сохраняются при shadowOFF и исчезают в unlit: это освещение
существующих stair side faces, не устранённый water seam. Геометрия не исправлена.

## Проверки PASS

11 целевых headless проверок — индивидуальные точные логи в qa:
test_diorama_materials, test_voxel_cartoon_water, test_native_surface_water,
test_world_surface_projection, test_surface_canvas_workflow,
test_voxel_prefab_rebuild, test_world_canvas, test_test_pier,
test_voxel_projection_cache, test_voxel_object_canvas, test_voxel_tools_backend.
Последние логи с underscore именами — финальный regression batch.

Native test-diorama-native.log: пиксельная идемпотентность повторных apply,
exact restoration при clear, automatic disable/enable и pack/save/reopen.
Storage test: все PROPERTY_USAGE_STORAGE Sun/Environment fields, disabled/
missing/freed Sun, scene detach/reattach, Sun-only detach/reattach без Map.ready,
reparent Moon/back, replacement target с отменой pending callback,
20 open/close при удержанном Environment. Legacy Moon не создаёт watcher.
Live disabled Sun остаётся под наблюдением; detached Sun ждёт одноразовый
tree_entered без per-frame poll закрытой карты. Pending weakrefs не удерживают
Node/Environment; протухшие записи очищаются следующим owner вызовом/poll.

38 native viewport PNG: baseline/candidate near+overview уголка, world_canvas,
TestPier, FanTown8/12, холодной ночи, тёплой Moon ночи, CombatLab; дополнительно
unlit/shadowOFF WorldCanvas и water time8.25. Логи candidate-*.log и baseline-*.log
содержат renderer/device, фактический размер, camera pass и METRICS.
QA freeze актёров одинаков для baseline/candidate, production input/physics
не меняет и не заменяет ручную проверку. Фиксированное shader time3.25 только
в fixture; production time path прежний.

source-hash-final.log: после всех regressions и isolated editor import
429 .tres/.tscn в content/scenes/prefabs побайтно прежние. Manifest создан ДО
проверок, не перезаписан после. editor-import-smoke.log относится только к
owned Temp, с отключённым MCP editor plugin и baseline/.gdignore.

## GPU proxy

RTX5070 Vulkan Forward+, последовательные процессы, 120 frames median после
35 warmup. Near/overview GPU ms baseline → candidate:

- уголок: 0.242/0.214 → 0.247/0.219;
- world_canvas: 0.374/0.221 → 0.384/0.226;
- TestPier: 0.601/0.478 → 0.619/0.491;
- FanTown8: 1.468/0.840 → 1.346/0.842;
- FanTown12: 1.621/0.918 → 1.482/0.917;
- холодная ночь: 0.274/0.239 → 0.275/0.240;
- тёплая Moon ночь: 0.276/0.242 → 0.279/0.242;
- CombatLab: 0.323/0.311 → 0.324/0.312.

Drawcalls/objects совпали во всех парных fixture после freeze. FanTown8/12
VRAM совпала (271435792/277606416 bytes); corner +1664 bytes, CombatLab +2688 bytes.
Watcher unchanged-signature CPU ~2.13µs/poll для одной warm environment.
Разница мала и разнонаправленна; доказанного slowdown/optimization нет.
Это viewport timing proxy, не GPU capture, общий FPS или live editor benchmark.

## Ошибки экспериментов отдельно от PASS

Projection constant конфликтовал с builtin; переименован. RS enum type требует
явного cast; исправлен. Попытка renderer-only Sun tint/softness отклонена:
native Light RID API недоступен через предполагаемые методы; весь этот код
удалён, Sun property не менялась. Ранний water candidate повторно умножал
albedo; исправлен до финальных кадров. Local/cold response возвращён stock.

Ранний label warm-moon baseline не попадал в baseline branch; исправлен.
failed-world-unlit-capsule.log: diagnostic вызывал ArrayMesh method на Capsule;
исправлен типовой guard, финальные unlit кадры успешно получены.
Первое сравнение FanTown отличалось на один drawcall из-за движения актёра
между async Surface prep; исправлена только QA fixture, финальные парные counts
точно совпали. Storage fixture reparent имеет float transform round-trip;
возвращает свой исходный transform до exact comparison, helper transform не меняет.

failed-editor-mcp-fixture.log: первый isolated editor smoke повторно включил
MCP autoload через plugin и встретил чужой cache UID; это не PASS. MCP plugin
отключён только в Temp, baseline исключён из scanner; финальный import повторён.
Ранний pre-isolation render читал общий autosave/MCP IPC и не нашёл relative
legacy pack; после отдельного app userdata и absolute read-only pack path
повторён. Авторские карты/Source не сохранялись.
Inherited invalid UID warnings FanTown используют text path fallback;
в целевых финальных runtime проверках SCRIPT ERROR/ERROR/FAIL отсутствуют.

## Открытая приёмка

Основной координатор сначала переносит перечисленный diff с сохранением своего
loader/docs/dirty work. Затем пользователь принимает внешний вид уголка,
Причала и полного холста, ночную читаемость и камеру/input в working/game view,
реальное сохранение/reopen Inspector настроек. До этого контракт не закрыт.
В этой задаче подготовка и автоматическая проверка завершены; управление
возвращается основному координатору.
