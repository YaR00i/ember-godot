# Качество и порядок
Обновлено: 2026-10-23. Активность: Test Pier и оставшийся исходный импорт удалены; проверки используют искусственные данные.

## Цель
Проект без лишнего и устаревшего: понятно, что живое; тесты и документы сжаты; вес репозитория разумный.

## Владельцы
`tools/` (тесты и пробы, ~554 скриптов), `docs/` (карта и NOW), `.gitignore`, ветки Git.

## Принято автором
Ревизия мира, вокселей и материалов 22.10 (отчёт в чате; факты ниже). Checkpoint-коммит `0476913` (537 файлов).

## Сделано без приёмки
В документационном срезе NOW сокращён до около 80 строк; открытые gates/возвраты оставлены у владельцев тем.
Сцены, код и данные этим срезом не удалялись и не переносились.
Роли/границы помощников настроены (Workflow → «Команда и делегирование»); добавлен профиль тестировщика
для узких проверок после передачи кода. Общие/Ember-правила требуют конкретного основания расширения набора.
TOML/обязательные поля и ссылка на профиль проверены; отдельный тестировщик ещё не запускался.
Пилот 22.10: один read-only критик `gpt-6.1-sol` medium; тип `ember_critic` текущей сессией не распознан,
использован `default` с тем же профилем/моделью. Нативная загрузка имени роли остаётся непроверенной.
В изолированном проекте Forward+ настоящая placement session + editor history/API: move, Undo/Redo,
save/reopen/discard PASS. SHA256 861 авторского файла и общих ресурсов копии совпали; авторская карта не сохранялась.
Мышь/горячие клавиши/ощущение — ручная приёмка автора OPEN; Computer Use не использовать (AGENTS).
Evidence: `C:/Users/novos/Documents/Codex/2026-10-22/ember-team-rock-163354/` (commands.jsonl, integrity.json, scene-copy.diff).

## Открыто (факты ревизии 22.10)
- **Git:** рабочая ветка `codex/runtime-water-region-activity`; GitHub-копия отстаёт на 8 коммитов (push только по просьбе автора);
  `main` старая (24.09, −16 коммитов); три побочные ветки сентября не слиты: `combat-action-plan-v2644`, `combat-v2643-preservation`
  (по 1 коммиту), `w04-gameplay-acceptance` (2 коммита, водная лаборатория); worktrees в `~/.codex/worktrees/` и `ember-water-acceptance`, `ember-startup-diag`.
- **Сцены:** после уборки23.10 —53 в `scenes/`;4 входят в статическую цепочку игры, остальные имеют
  editor/test/документальные потребители. `ground_finish_study` и `compact_landform_legacy_study`
  не признаны сиротами: остаются тесты/парное сравнение и ручные gates. Название/дата сами по себе не основание удаления.
- **Скрипты:** `scripts/prototypes/` содержит 41 рабочий скрипт (бой, земля) и 50 исследовательских (деревья, материалы) — название папки вводит в заблуждение.
  Мёртвых скриптов нет. Шейдеров исследований 6 (`ember_compact_sky_reflection_study` 786 строк).
- **Данные:**85 моделей Source после удаления14 старых импортов; свои формы/слияния/штампы сохранены по решению автора.
  Три авторских canvas-варианта старого импорта сохранены как свои объекты. Предыдущая оценка `content/world_terrains`180МБ
  (игра использует `landscape_compact.res`), `content/world_surfaces` 77 МБ, `prefabs/voxels` 281 МБ производных; `.git` 1,7 ГБ;
  `docs/art/` 454 МБ черновиков не в Git (`.aseprite` 3×76 МБ).
- **Документы:** NOW сокращён до около 80 строк; `docs/README.md` устарел по дате; `MIGRATION_TEST_PLAN.md` 6,5 тыс. строк,
  `EMBER_TERRAIN_AUTHORING.md` 4,3 тыс. строк; растут.
- Тесты: нужен «набор после сборки единой карты» (сейчас ~19 целевых + регрессии камня).

## Где остановились
Автор разрешил уборку23.10; уточнил: объекты удалять только из старого импорта, свои черновики не трогать.
Удалены9 сцен: new_landscape/2/3, spike, compact_bark_material_study, compact_clear_water_study,
compact_tree_branch_network_study, compact_tree_branching_study, compact_tree_crown_study;
3 отдельные земли new_landscape/2/3,5 capture-команд и старый migrate_sandbox_voxel_batch с UID.
Удалены9 импортов с prefab/мешами: vox_fan_crate_old/horseshoe/inn_sign/lantern_stone/window,
vox_vil_counter/mailbox/planter/sign. Имена после vox_fan_/vox_vil_ перечислены с общим префиксом.
Всего62 файла /64.60МиБ; изменённых авторских файлов в пакете нет. Городок fan_town с интерьерами уже
удалён прежним retirement. Архив этого пакета вне проекта с ZIP CRC/payload SHA — ниже.
Проверено: каталог99→90 моделей,88 групп библиотеки;0 pending/failed preview. Старые city-reference
checks PASS; native Forward+ старт landscape_compact, игрок, валидный Source и4 mesh props PASS.
Основная сцена/terrain сохранили исходные SHA256. Полный набор не запускался, runtime/editor код не менялся.
Последующий срез удалил Test Pier, его скрипт/UID/Surface и5 исходных импортов:
vox_fan_anvil/barrel/crate_stack/door и vox_vil_bush, с точными prefab/mesh-производными —24 файла/27.65МиБ.
493 остальных Source/prefab/mesh и основная сцена/terrain сохранили SHA256.
Три авторские canvas-вариации импорта и6 новых рисованных моделей сохранены.
`tools/fixtures/ember_editor_mechanics_fixture.gd` создаёт входы только в user:// или защищённом
временном проекте. `test_exploration_mechanics.gd` заменяет `test_test_pier.gd`: пара, движение,
преграда, сумка, pause Save/Load и повторный вход. Каталог/preview/PCK используют3 синтетические модели.
Editor/world/context/conversion/object-canvas проверки используют ту же искусственную поверхность;
тест больших Surface остаётся отдельным. Проба двери строит простой объём; размещение — тестовый куст.
Старые сохранения Причала возвращаются ко входу landscape_compact; данные прогресса не переписываются.
Рабочая карта одна — landscape_compact; новые места при необходимости добавляются генератором.
Новых авторских карт нет. Полный набор не запускался; ручная приёмка мыши не заявляется.
Адресные PASS после переноса: каталог/полка/source-free PCK, импорт→Resource;
exploration Save/Load/re-entry, object-canvas и water; native Forward+ world editor,
context, conversion и object-canvas (Undo/Redo/save/reopen), placement preview и preview renderer.
В старом object-canvas gate исправлено имя действующей боковой панели и завершение тестового процесса;
conversion перед выходом очищает уже проверенную историю, без ошибок teardown.
Новый shrub проверен в выборе размещения; дверь — компиляция скрипта и размер mesh.
После удаления PASS retired references/catalogs/progress round-trip/fallback Причала;
основная карта Forward+ startup, валидный terrain, игрок и4 mesh props. Каталог90→85.
Основная карта/земля и493 защищённых файла неизменны по SHA. Commit/push не выполнялись.

## Сохранённая база и архивы
Архив Test Pier и последних5 исходных импортов:
`C:/Users/novos/Documents/Codex/2026-10-23/ember-pier-retirement/test-pier-and-original-imports.zip`.
ZIP CRC и SHA256 каждого payload проверены до удаления; рядом manifest, снимок493 защищённых файлов,
native dependency graph и логи адресных проверок. Ни один живой native Resource не ссылался на пакет.
Первая уборка23.10: `C:/Users/novos/Documents/Codex/2026-10-23/ember-cleanup/retired-maps-and-imports.zip`;
62 исходных файла, ZIP CRC и SHA256 каждого payload проверены до удаления; рядом retirement-manifest.json,
retirement-plan.json и object-usage.json. Общий builder clear/irregular seabed сохранён: irregular Source
остаётся входом водных проверок. Основная карта/Source и общие материалы в пакет не входят.
Материалы/пять пород — `41247dd`, трава/POM/правила формы — `d9e33a9`, игровые системы — `6124184`,
прежняя мировая база — `0a7e1c5`, её статус — `0848090`; native cleanup — `841b294`; поздний checkpoint — `0476913`.
Единая карта/камень — `f56d572`, земля/дневной свет — `f96963a`. Checkpoint не является приёмкой.
Полный архив до material/tree commit (1084 файлов, проверенный SHA-256 manifest по сохранённой записи):
`C:/Users/novos/Documents/Codex/2026-10-15/ember-checkpoint-trees/`; тяжёлые drafts/captures остаются локальными.
Предыдущий — `C:/Users/novos/Documents/Codex/2026-10-13/ember-material-depth/checkpoint-b7353afb/`.
Историческая передача: `C:/Users/novos/Documents/Codex/2026-10-12/new-chat-2/outputs/EMBER_HANDOFF_2026-10-13.md`.
Прежнее «без commit/push» в статусах проб не описывает нынешний HEAD; актуальную сохранность сверять через Git.

## Зависимости
Не меняет поведение игры; опирается на факты других направлений (что живое).

## Ссылки
`../EMBER_WORKFLOW.md`, `../EMBER_JOI_EXIT_PLAN.md`; evidence ревизии — ember-rock-form-probe/.
