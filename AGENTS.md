# Ember Godot — правила для AI-агентов

Этот репозиторий — единственный активный проект Ember и источник правды о коде,
данных и текущем состоянии. История Codex-чата его не заменяет.

## Начало задачи

До нетривиальных изменений:

1. прочитать этот файл и `docs/EMBER_NOW.md`;
2. проверить `git status --short` и последние релевантные commits;
3. через `rg` найти owners, runtime/editor paths, Resources, serialization и tests;
4. открыть поиском только нужные разделы больших документов;
5. составить и согласовать короткий Task Contract по `docs/EMBER_WORKFLOW.md`.

До завершения исследования и согласования контракта код не менять. Отдельный
task-файл без доказанной необходимости не создавать.

## Маршруты

- процесс задачи: `docs/EMBER_WORKFLOW.md`;
- игровой дизайн: `docs/EMBER_GAME_DESIGN.md`;
- продуктовый порядок: `docs/EMBER_PRODUCT_PLAN.md`;
- техническое состояние: `docs/EMBER_TECHNICAL_HANDOFF.md`;
- UI: `docs/EMBER_UI_PIPELINE.md`;
- выход из JOI: `docs/EMBER_JOI_EXIT_PLAN.md`;
- подробные gates: релевантный раздел `MIGRATION_TEST_PLAN.md`.

`EMBER_NOW.md` содержит только текущую точку и ближайшие шаги. Долговечные
решения остаются в соответствующих канонических документах.

## Неподвижные границы

- Целевой runtime и authoring — Godot 4 Forward+.
- Карты принадлежат `.tscn`; voxel-источник — `content/voxel_models/*.tres`
  (`EmberVoxelModelResource`). Mesh, collision, thumbnail, prefab и MeshLibrary
  являются производными данными.
- `../joi-conductor/content/ember` читает только legacy-importer до закрытия
  `docs/EMBER_JOI_EXIT_PLAN.md`; новые runtime-зависимости от JOI запрещены.
- Не добавлять второй renderer, voxel editor, owner механики или схему данных.
- Общая математика живёт в одном чистом leaf-модуле; UI маршрутизирует команды.
- Preview совпадает с commit; тяжёлая операция фиксируется один раз на
  pointer-up/Enter.
- Editor-only состояние не попадает в gameplay Resource без решения о владельце.
- Цвет группы — authoring metadata, цвет вокселей — palette data.
- Collision, высота и navigation игрока/AI используют одну физическую поверхность.
- Не делать full remesh/reload на мелкий input; большие операции измерять и
  чанкировать на репрезентативной карте.

Изменение данных закрывать вертикально: Resource/schema → validation → editor →
preview/runtime → serialization → targeted tests → документация.

## Проверка и безопасность

Editor-срез требует Undo/Redo, save/reopen, discard, validation и targeted test;
затем связанных regressions и ручного Forward+ для UI/render/physics/input.
Тесты используют fixtures и `user://`, а не перезаписывают авторские карты.

Не удалять пользовательские изменения, не форматировать массово и не применять
`git reset`/`checkout --`. Менять только файлы согласованного среза. Commit,
branch и push выполнять только по явной просьбе пользователя.

Никогда не запускать рабочий checkout через `--headless --editor`. Targeted tests
запускать через `--headless --path . --script ...`; editor/import smoke — только
в отдельном checkout/cache. Пока `at-icons` отключён, сохранять
`addons/at-icons/.gdignore`.

## Завершение thread

Task Contract закрыт только после проверок, нужной ручной приёмки и обновления
долговечных документов и `EMBER_NOW.md`. После самостоятельной завершённой
задачи не начинать следующую feature в том же длинном чате: предложить новый
thread и стартовый промпт. Не дробить один контракт между его фазами, приёмкой и
исправлением найденных во время приёмки ошибок.
