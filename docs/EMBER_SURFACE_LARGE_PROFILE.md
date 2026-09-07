# Ember Surface — профиль большой dense-карты

Дата: 5 сентября 2026. Версия редактора: v2.47. Reference runtime: Godot
4.7.2, Windows; CPU-профиль запускается headless, визуальная проверка — Forward+.
Источник: read-only
`content/world_surfaces/agent_sandbox_surface.tres`; все временные save/reopen
файлы и JSON пишутся в `user://`.

## Данные и решение

Surface имеет 24×24 игровых блока, voxel-grid 384×32×384 и 4 718 592 dense
slots. Занято 557 205 (11.8%). `voxels`, `transparency` и три column channels
занимают 10 321 920 bytes (9.84 MiB) в несжатом рабочем представлении.

`ResourceLoader.CACHE_MODE_IGNORE` для текстового `.tres` стабильно занимает
около 0.80 с (после прогрева OS cache), save — 0.13 с,
reopen сохранённого файла — 0.81 с. Это заметная, но ограниченная стоимость;
она не доказывает необходимость второго storage owner, sparse serializer или
chunk persistence. Каноническая schema v4 остаётся dense.

## Измеренные пути

- Синхронный `Surface Canvas.open_surface`: 0.79 → 0.12 с.
- Полный heightfield: 0.61 → 0.045 с; reference и optimized arrays совпадают.
- Hide/isolate group view: 0.71 → 0.019 с; clear — около 0.018 с.
- Exact 16×32×16 chunk: 25.5 → 5.9–6.6 мс в среднем.
- Frame drain: 1–2 быстрых chunks за 6–11 мс; медленный fallback
  остаётся ограничен одним законченным chunk за итерацию.
- Полная Forward+ сборка 576 chunks завершилась за 6.05 с / 472 rendered frames
  без видимых швов или пропавших участков; disposable screenshot сохранён в
  `user://ember_large_surface_profile.png`.
- Connected selection до atomic cap: около 0.10 с pure work; UI выполняет её
  3 ms slices. Подготовка MultiMesh overlay для 32 768 voxels — около 0.044 с,
  обычно 10 slices. Здесь production-код не менялся.
- Преобразование 32 768 изменённых индексов в 144 затронутых chunks — около
  0.015 с. Оно выполняется один раз при commit, не на каждом pointer move.

## Обоснованные изменения

1. При occupancy ≤33% и palette index ≤32 heightfield перечисляет ненулевые
   palette entries через native `PackedByteArray.find`; dense/high-palette
   модели сохраняют прежний bounded column scan.
2. Editor-only visibility/isolation не меняет terrain, поэтому повторная
   пересборка использует уже вычисленный canonical heightfield. View filter не
   попадает в Resource или Undo.
3. Grid и region overlays читают тот же heightfield cache вместо повторного
   поиска верхнего voxel по Y.
4. Voxel Tools строит exact terrain для сухих chunks. Water/foam использует
   координаты полной Surface для бесшовного shader pattern, тогда как native
   terrain mesh локален своему chunk; поэтому water-bearing chunks целиком
   обслуживает прежний точный SurfaceMesher. Это сохраняет корректность без
   второго render owner или смены schema. При отсутствии native classes также
   действует stock fallback.
5. Preview queue имеет 6 ms soft budget: быстрые chunks группируются в один
   кадр, а один дорогой chunk всё равно завершается и затем управление
   возвращается editor loop.

## Повторение

```powershell
tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_surface_large_profile.gd
```

Отчёт: `user://ember_large_surface_profile.json`. Значения времени являются
диагностическими, а не жёсткими CI thresholds; correctness закреплена
сравнением heightfield, round-trip и связанными Surface-тестами.

## Дополнение v2.54: fan_town runtime

Перед включением `fan_town` отдельный read-only профиль измерил её будущую
Surface 32×32: grid 512×48×512, 12 582 912 voxel bytes, 1 707 008 занятых
ячеек и файл 16 778 680 bytes. Seed занимает около 0.26 с, save 0.14–0.17 с,
reopen 1.0–1.1 с. Поэтому dense schema и `.tres` сохранены.

Stock visual chunk занимал в среднем 19–21 мс и доходил примерно до 40 мс;
существующий Voxel Tools exact backend дал 5–7 мс на сухих chunks. Он вынесен в общий
`ember_voxel_native_mesher.gd`, а старый editor adapter оставлен совместимым
тонким именем. Water-bearing chunks, per-voxel transparency и отсутствие native
classes включают stock fallback; water/foam остаётся у того же SurfaceMesher.

Без общего heightfield 256 collision chunks 2×2 блока занимали 2.6–2.8 с и до
14–18 мс каждый. Один transient heightfield строится около 0.15–0.17 с в
WorkerThreadPool; с ним 64 чанка 4×4 блока занимают около 0.22 с, а полный
runtime chunk вместе с PhysicsServer shape — до 8 мс. Кэш, mesh, route grid и
collision не сериализуются. Фактический gate загрузил сцену за 1.28 с, включил
физику за 0.77 с и собрал все 1024 visual chunks за 6.47 с headless; Forward+
Vulkan подтвердил 1024/64 chunks без швов.

Повторение: `tools/test_fan_town_surface_profile.gd` (read-only профиль),
`tools/migrate_fan_town_surface.gd` (dry-run; запись только с `--apply`) и
`tools/test_fan_town_surface_projection.gd` (сохранённая сцена).
