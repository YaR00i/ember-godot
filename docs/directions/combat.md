# Бой
Ориентиры по ролям: Magicka — стихии, Disgaea — вертикальные действия,
Trails/Octopath — ясная подача команд/очереди. Действующие правила и границы заимствования —
[GDD](../EMBER_GAME_DESIGN.md#что-берём-из-референсов); визуальная роль игры не меняет resolver/правила.
Обновлено: 2026-10-28. В этом чате — бой в миссии «Послание на берегу»;
параллельная цель редактора в NOW сохраняется.

## Цель
Тактический бой с единым preview/commit для игрока и ИИ, понятным выбором действий и безопасным
возвратом в исследование; общая библиотека эффектов не требует нового кода для каждой комбинации.

## Владельцы
- `scripts/prototypes/ember_combat_prototype.gd` — единственный resolver; в той же папке
  `ember_combat_status_rules.gd`, `ember_combat_damage_rules.gd`, `ember_combat_effect_rules.gd` — чистые правила.
- Там же: `ember_combat_state_schema.gd`, `ember_combat_action_conditions.gd` — validation и условия;
  `ember_combat_grid.gd` (включая `action_plan`), `ember_combat_terrain.gd` — навигация/план/поле.
- Там же: `ember_combat_lab.gd`, `ember_combat_lab_setup.gd`, `ember_combat_grid_3d_world.gd` — controller/setup/показ.
- `scripts/ember_combat_transition.gd`, `scripts/ember_explore_state.gd` — транзакция и persistent результат.
- `scripts/prototypes/ember_combat_action_resource.gd`, `ember_combat_effect_resource.gd`,
  `ember_combat_status_resource.gd`, `ember_combat_unit_resource.gd`, `ember_battlefield_resource.gd`,
  `ember_encounter_resource.gd` в той же папке; данные — `content/combat/`.
- `scenes/combat_lab.tscn`, `scenes/combat/` — Lab и арены; декор не заменяет клетки Battlefield.

## Принято автором
- ActionPlan: мышь/геймпад, hover, M, lift/cancel, HUD/анимации на 10×8 и 16×12 —
  [Test Plan](../../MIGRATION_TEST_PLAN.md) → «ActionPlan regression gate (поверх v2.64.4)».
- Поражение/Retry/Load подтверждены 8 сентября; предбоевая расстановка и menu save/reopen также подтверждены:
  [Test Plan](../../MIGRATION_TEST_PLAN.md) → «Production defeat/Retry gate», «Pre-battle deployment gate».
- Принят порядок periodic HP: всё лечение до max HP, затем урон; баланс не принят:
  [GDD](../EMBER_GAME_DESIGN.md) → «Промежуточный этап 3.5 · авторская библиотека боя».

## Сделано без приёмки
- Первый bridge ящиков29.10: in-place field переносит прежний pickup_id в units/
  holds, два типа прочности, hit/miss/постановка/повторный подъём/Retry/victory/world
  return/cold save PASS в Forward+. Предметы не имеют ходов/стороны врага. Native
  кадры просмотрены; ручные управление/ощущение OPEN. Общий resolver/preview=commit
  остаётся один. Scope/границы — Inspector I3.15 «Столкновения ящиков и первый перенос в бой29.10».
- Условия приёмов И/ИЛИ, условия шагов эффектов/пояснения без раскрытия RNG, independent doses 1–12,
  несколько независимых врагов из одного шаблона реализованы; свои сочетания/бой/input/баланс OPEN.
- Выбранная arena, Lab setup/presets и обычный бой/AI/Retry/result/Save/cold Load имеют записанные QA PASS:
  [Handoff](../EMBER_TECHNICAL_HANDOFF.md) → «Общие игровые системы»; это не авторская приёмка.
- `6124184` сохранил Lab/условия; `0476913` — effect/status rules, condition groups, enemy instances и UI;
  сообщение checkpoint прямо исключает приёмку чужих линий работы.
- Рабочие изменения других чатов сохранены; новые проверки береговой миссии — ниже.

## Открыто
- Active party 1–4: одиночка/пара, бой/Retry/save/load требуют ручной приёмки; исторический Retry PASS её не заменяет.
- Новые эффекты/дозы/враги, своя арена и DPI/узкое окно/hover/длинные цепочки — manual OPEN.
- Декор compact и semantic клетки не объединены автоматикой: свойства Battlefield задаёт автор.
- Ветки `codex/combat-action-plan-v2644` и `codex/combat-v2643-preservation` имеют по одному коммиту вне HEAD;
  необходимость переноса не подтверждена, ActionPlan owners уже есть в рабочей ветке.
- Многоклеточный страж/части тела — дизайн главы, не подтверждённая готовая механика:
  [GDD](../EMBER_GAME_DESIGN.md) → «Многоклеточные противники и части тела».

## Где остановились
Для береговой миссии прежний Lab/HUD/resolver запускается дочерним узлом мира:
клетка1м, поле5×5м, реальная опора без второго пола, патруль/первый удар/удар сзади.
Победа сохраняет кожу вместе с результатом и возвращает управление без замены Map.
Targeted Forward+ бой/ИИ/result и прежние transition/Retry PASS; автор прошёл миссию28.10.
Переход изменён по просьбе автора: те же мировые модели группы/противников
прыгают в клетки, камера плавно открывает поле без чёрного экрана. Команды/AI
ждут приземления;2/4 героя и1/2 противника проверены. Вид одобрен автором;
отдельные позы/баланс не утверждены. Дуга вынесена в общий чистый ArcMotion
для этого перехода и полёта подбираемого предмета; связанный gate PASS.
Owners/ограничения — Handoff → «Предметы в мире и бутылка».
Прежний отдельный gate: в Lab проверить заморозку мокрой/сухой цели, пояснение
пропуска и hover/Cancel/Esc; затем одиночку/пару. Эта миссия их не принимает.

## Зависимости
Берёт: активную партию/экипировку/сумку у game-systems, декор у world-map, представление героев у characters.
Отдаёт: один result/XP/loot через transition; persistent/save owner остаётся ExploreState.

## Ссылки
- [Handoff](../EMBER_TECHNICAL_HANDOFF.md) → «Combat», «Combat Lab», «Общие игровые системы»;
  [GDD](../EMBER_GAME_DESIGN.md) → этап 3.5; [Test Plan](../../MIGRATION_TEST_PLAN.md) → «Combat» и gates выше.
- Тесты: [resolver](../../tools/test_combat_prototype.gd), [grid](../../tools/test_combat_grid.gd),
  [Lab](../../tools/test_combat_lab.gd), [условия эффектов](../../tools/test_combat_effect_conditions.gd),
  [дозы](../../tools/test_combat_status_stacks.gd), [враги](../../tools/test_combat_enemy_instances.gd),
  [Retry](../../tools/test_combat_defeat_retry.gd), [расстановка](../../tools/test_combat_prebattle_deployment.gd).
