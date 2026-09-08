# Ember — текущая точка

Обновлено: 2026-09-08  
Git checkpoint: `4569f64` (`main`/`origin/main`; defeat/Retry-срез пока находится в рабочем дереве)

Этот файл — короткая стартовая точка для нового Codex-thread. Он не заменяет
GDD, продуктовый план, технический handoff или migration gates. Если здесь и в
коде есть расхождение, сначала проверить код, tests и Git, затем обновить файл.

## Текущий milestone

- Основной Ember editor остановлен на принятом stop-line v2.56.1. Общая полировка
  не продолжается без конкретного production workflow, который редактор пока не
  позволяет выполнить.
- Базовый GDD вертикального среза принят. Расширение GDD v1.5 зафиксировано как
  план, но ещё не реализовано в коде.
- Combat Lab доведён до v2.64.4: вертикальные поля, камера и preview; постоянная
  партия и save v2; характеристики, предметы, XP, парные приёмы; редактор
  боевого контента; поэтапный выбор действий; общий auto-approach для непарных
  hostile/support/heal/item/cell/lift-команд; battle-only удержание поднятой цели.
  Исправляющий срез ограничил cell-target preview реальными MOVE + range,
  сохранил цель подъёма на месте до подхода и сократил measured 16×12 cell-query
  примерно с 378 мс до 12 мс без смены schema.
- В checkpoint `4569f64` зафиксирован единый клеточный ActionPlan: живой hover,
  movement/cast envelope, точный stop/fallback, общий вход player/AI-команд,
  обратимый presentation-подход и подъём. 24/24 combat/battlefield/encounter/
  party/save scripts прошли, обычный Forward+ smoke обоих полей выполнен, а
  основной сценарий принят пользователем вручную. Завершения поднятия перенесены
  из отдельной панели в кольцо у носителя; позиция, фокус и читаемость кольца
  дополнительно приняты пользователем в реальном бою 8 сентября 2026.
- Поверх `4569f64` в рабочем дереве закрыт production lifecycle поражения:
  неудачная попытка не может применить HP/MP, предметы, флаги или награды к миру;
  Retry восстанавливает предбоевые party/inventory/deployment и создаёт новый
  RNG seed; вместо возврата с поражением можно выбрать один из трёх ручных
  слотов или автосейв. Новый сквозной gate и связанные transition/result/party/
  save tests прошли; 27/27 связанных regression scripts зелёные. Обычный
  Forward+ на RTX 5070 дошёл до load-only окна без renderer/script errors, а
  in-engine capture подтвердил компоновку и видимый focus первого слота.
  Ручная приёмка мышью/геймпадом подтверждена пользователем 8 сентября 2026.
- Workflow Phase A/B создаёт короткую точку входа и отделяет актуальные
  канонические документы от истории, сохранённой в Git. Gameplay, Resources,
  schema и runtime эти фазы не меняют.

Последний подтверждённый baseline для checkpoint `20685ac`: прошёл
`python tools/test_vox_axes.py` и полный набор из 82 `tools/test_*.gd`.

## Следующий игровой срез

Defeat/Retry gate закрыт. Следующий короткий срез — предбоевая расстановка.
Затем нужен один небольшой сквозной D3 production-
участок. Парный auto-approach остаётся отдельным будущим решением:
парные техники по-прежнему используют собственный authored-радиус партнёра.
Большой player-facing UI согласуется позже отдельным HTML-прототипом перед
переносом в Godot.

## Ключевые owners текущего боевого среза

- `scripts/prototypes/ember_combat_prototype.gd` — чистый resolver,
  preview и commit;
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

Для текущего v2.64.4 regression gate минимум:

- `tools/test_combat_action_plan.gd`, `tools/test_combat_grid.gd`;
- `tools/test_combat_defeat_retry.gd`, `tools/test_combat_encounter_transition.gd`;
- `tools/test_combat_prototype.gd`;
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

## Как обновлять этот файл

Обновлять только после принятого среза или изменения ближайшего порядка работ.
Здесь нужны факты о текущей точке, ближайшие 1–3 шага, owners, gates и открытые
риски. Длинные объяснения, журналы версий и завершённая история остаются в
канонических документах и Git.
