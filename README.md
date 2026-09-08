# Ember Godot

Единственный активный Godot 4 Forward+ проект Ember: runtime, игровые сцены,
редакторские инструменты и новый canonical content находятся здесь.

Текущая точка разработки и ближайшая задача: `docs/EMBER_NOW.md`. Этот README
нужен для открытия проекта и навигации, а не для хранения журнала версий.

## Быстрый запуск

Целевая версия — Godot 4.7.2. Проверенный бинарник находится в `tools/godot/`.

- `edit.bat` — открыть проект в редакторе;
- `run.bat` — запустить основную сцену;
- проектная play-сцена — `scenes/fan_town.tscn`;
- механический sandbox — `scenes/agent_sandbox.tscn`;
- текущая боевая лаборатория — `scenes/combat_lab.tscn`.

Основное управление исследованием: WASD относительно поворота камеры, `F` для
взаимодействия, RMB для поворота, `Tab` для смены лидера и `T` для переключения
живой формации/«паровозика».

## Основные authoring-инструменты

После открытия проекта plugin `Ember Migration Tools` предоставляет:

- `Surface Canvas` — dense voxel Surface, палитра, группы, sculpt, вода и
  ограниченная пересборка;
- `Ember Graph` — action chains, dialogue, quests и связанные каталоги;
- `Ember: Open Combat Lab` — текущий воспроизводимый боевой runtime-срез;
- `Ember: Open Combat Content` — единая библиотека effects → actions → units;
- `Ember Migration` — read-only inventory, dashboard и ограниченные операции
  переноса после strict parity;
- нативный Inspector — scene-owned interactions и специализированные Resource
  panels.

Карты после переноса принадлежат `.tscn`. Voxel-источник находится в
`content/voxel_models/*.tres`; mesh, collision, thumbnail, prefab и MeshLibrary —
производные данные. Полная повторная миграция карты используется только при
изменении legacy terrain/regions: она перезаписывает импортируемую раскладку и не
является обычным способом редактирования.

## Проверки

Targeted Godot test запускается так:

```powershell
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_example.gd
```

Действующие suites и ручные gates перечислены в `MIGRATION_TEST_PLAN.md`.
Пакетный Python contract check:

```powershell
python tools/test_vox_axes.py
```

Никогда не запускайте рабочий checkout с `--headless --editor`: editor-themed
imports зависят от локальной темы и могут вызвать массовый повторный импорт.
Editor/import smoke выполняется только в отдельном checkout или import cache.

## Ownership и миграция

- Godot Resources, `.tscn`, runtime и editor plugins этого репозитория — текущий
  источник правды.
- `../joi-conductor/content/ember` — временный read-only legacy-архив только для
  явного importer path.
- Новый runtime, preview и save не получают зависимостей от JOI.
- Наличие generated prefab само по себе не доказывает migration ownership или
  parity.
- Не создаются второй renderer, второй voxel editor, параллельный save owner или
  альтернативная schema.

## Карта документации

- `AGENTS.md` — короткие обязательные правила для AI-агента;
- `docs/EMBER_NOW.md` — текущий milestone и ближайшие шаги;
- `docs/EMBER_WORKFLOW.md` — Task Contract и процесс реализации;
- `docs/EMBER_GAME_DESIGN.md` — игровые правила вертикального среза;
- `docs/EMBER_PRODUCT_PLAN.md` — видение и продуктовый порядок D0–D5;
- `docs/EMBER_TECHNICAL_HANDOFF.md` — актуальные owners и технические контракты;
- `MIGRATION_TEST_PLAN.md` — действующие автоматические и ручные gates;
- `docs/EMBER_JOI_EXIT_PLAN.md` — условия окончательного выхода из JOI;
- `docs/EMBER_UI_PIPELINE.md` — маршрут editor и player-facing UI;
- `docs/EMBER_EDITOR_UX_AUDIT.md` и
  `docs/EMBER_OBJECT_INSPECTOR_DESIGN.md` — глубокие reference-документы.

Большие документы следует открывать поиском по нужному разделу. Старый подробный
changelog README и промежуточные v1/v2-инструкции можно восстановить из
монолитного Git checkpoint `20685ac`; они не описывают текущий порядок разработки
и не заменяют будущие небольшие checkpoints.

## Текущая граница

Основной editor находится на принятом stop-line. Общий polish не продолжается
без конкретного production workflow, который невозможно выполнить текущими
инструментами. Ближайший игровой срез и обязательные ограничения всегда берутся
из `docs/EMBER_NOW.md`, а не из истории чата или старого changelog.
