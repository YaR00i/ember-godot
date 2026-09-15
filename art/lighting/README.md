# Свет диорамы — кандидат, 15 сентября 2026

Художественная приёмка и интеграция в основной checkout OPEN. Этот worktree
содержит ограниченный graphics diff на aeab62e. Исходный редактор мира и карты
не менялись. Референсы пользователя сохранены в `references`: bridge, garden,
boards. Это ориентиры, не игровые текстуры.

## Художественный выбор

Сливочно-золотистый ответ тёплого направленного света, прохладный зелёно-бирюзовый
рассеянный свет и тень. Общая light response вынесена в маленький shader include;
opaque voxel, alpha props и water сохраняют отдельные fragment/depth/alpha owners.
Авторские palette/Source/Recipes прежние. Местные лампы остаются плавными: их
N·L не ступенчатый, кольца от toon quantization не добавлены.

Вода сохраняет broad field, integer hash, connected network, UV depth bands,
opacity, sparse glints, движение и контактную пену. Изменён только её световой
ответ. Для холодного направленного света и локальных ламп сохранён stock
diffuse_toon response; custom water irradiance не умножает albedo повторно.
Foam/contact/wake shaders и геометрия не менялись.

Переходы toon bands и существующей shadow mask смягчены. Это не расширение
физической PCF penumbra и не новые просветы под кроной: при attenuation0/1
shader не создаёт подробности shadow mask. Плотные blob тени и слоистость
существующего дерева ограничены его геометрией и authored shadow setup.
Canopy noise, SSAO, bloom, outlines, dithering и дополнительный renderer не добавлены.

## Применение и сохранение

Existing `EmberLights.apply_diorama_environment` меняет только effective ambient
через `RenderingServer.environment_set_ambient_light(environment.get_rid(),…)`.
Environment/Sun properties, их Resource identity, fog/tonemap, transforms,
энергия/цвет/тени автора не записываются и не клонируются. Для текущих authored
Sun сцен ambient получает прохладный оттенок и80% своей исходной мощности;
Source intensity остаётся параметром автора. Нет накопления множителей.

Единственная согласованная вставка в loader, после прежних quality-off flags:

```gdscript
EmberLights.apply_diorama_environment(e, _content_node("Look/Sun") as DirectionalLight3D)
```

Loader принадлежит основному world-editor срезу. При возврате переносить именно
строку в `_tune_look_environment`, а не заменять весь loader файлом worktree.

Guard рассчитан на текущие WorldCanvas/TestPier и legacy FanTown: visible,
positive, warm downward Sun и ambient>=0.08; активный sibling Moon запрещает
day ambient override. Это не универсальная day/night schema. Общий shader
судит по цвету directional light, поэтому тёплый Moon также получает тёплый
light response. Его night atmosphere проверяется отдельно; абсолютное
определение времени суток по цвету не обещается.

Weakref watcher опрашивает только изменяемую сигнатуру. Disabled live Sun
отслеживается для повторного включения. Missing/freed/detached Sun возвращает
authored ambient и убирает per-frame запись. Live detach ждёт одноразового
`tree_entered`, без per-frame poll закрытой карты; смена target отменяет старый
callback. Протухшие weak pending entries очищаются при следующем вызове owner;
они не удерживают Node/Environment. Legacy Moon без Sun watcher не создаёт.

## Воспроизводимая проверка

QA сцена собирается `tools/render_diorama.gd`, режимcorner: существующее
tree522448705, fan rock/barrel и6instances опубликованной деревянной секции,
собственная disposable Surface. Transform/layout принадлежат только fixture.
Измерения и screenshots идут в `art/lighting/qa`. Камеры near/overview фиксированы,
water time3.25s,1280×720 render target (CombatLab:2560×1440), Forward+/Vulkan/RTX5070, MSAA как в проекте,
vsyncoff. Это direct viewport PNG, не background window composite.

`tools/run_diorama_qa.ps1` принимает только принадлежащую задаче Temp-копию с
prefix `ember-graphics-d97c-`; baseline лежит только там в `graphics-baseline`,
candidate накладывает owned files и одну строку loader. Вfinally candidate
восстанавливается. Ни main checkout, ни пользовательский Godot не открываются
для записи. Temp config имеет отдельное app_userdata имя, MCP autoload отключён;
legacy pack path указывает read-only на существующий архив. Для editor/import
smoke также отключён MCP editor plugin и исключена папка graphics-baseline
через .gdignore; встроенные Ember plugins оставлены. Первая неудачная попытка
с MCP сохранена отдельно в failed-editor-mcp-fixture.log.

В screenshot fixture остановлена физика актёров: иначе асинхронная подготовка
Surface сдвигала игрока между процессами и меняла drawcall count. Это только
QA режим, production physics не менялась. Реальное игровое/input поведение
этим freeze не проверяется.

Команды для собственной подготовленной fixture:

```powershell
./tools/run_diorama_qa.ps1 -Fixture <owned Temp project> -Godot <Godot console exe> -OutputDirectory <this worktree>/art/lighting/qa
<Godot console exe> --headless --path <owned Temp project> --script res://tools/test_diorama_materials.gd
<Godot console exe> --path <owned Temp project> --script res://tools/test_diorama_materials.gd -- --visual
python tools/check_graphics_sources.py <owned Temp project> art/lighting/qa/source-hashes.json
```

Storage test сравнивает всеPROPERTY_USAGE_STORAGE поля Sun/Environment до/после,
toggle/reattach/reparent/target-switch, pack/save/reopen вuser:// и legacy Moon.
20open/close с удержаннымEnvironment проверяют freedSun cleanup. Native safety
сравнивает реальные pixel bytes: repeated apply, clear, auto disable/enable,
pack/reopen. Native reparent имеет float round-trip; fixture явно возвращает
свою исходную transform до exact storage comparison, helper её не меняет.

Снимки shadowON/OFF/unlit отделяют authored stair side faces от shadow/shading
и water seams. Эти линии не объявляются исправлением геометрии.

Render GPU/CPU timer — доступный proxy:120frames после35warmup frames,
median viewport render milliseconds,drawcalls/objects/VRAM. Это не GPU capture,
не общий FPS, не cold startup и не measurement пользовательского live editor.
Baseline/candidate запускаются последовательно; системное состояние между
process runs может вносить погрешность. Watcher CPU измеряется отдельно.

## Возврат и открытые gates

Переносить только shaders/include,2voxel materials,EmberLights и выбранные QA
files/art references. Loader — snippet. Большие docs — только добавленные
graphics разделы с датой, без замены чужих актуальных документов.
Никаких commit/push/main writes здесь не выполнено.

Ручная приёмка пользователя OPEN: внешний вид уголка/Причала/холста, night
readability, реальная навигация камеры и editor working/game view input.
Тесты и PNG не заменяют эту приёмку. Следующие features не начаты.

Финальный перечень файлов, проверки, измерения и ошибки экспериментов:
[HANDOFF.md](HANDOFF.md). Все 38 actual viewport PNG сохранены здесь постоянно,
а не только в Temp. После regressions 429 scene/source/prefab hashes совпали.
