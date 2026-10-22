# Персонажи и анимация
Обновлено: 2026-10-22. Активность: на паузе; активная цель NOW — сборка единой карты.

## Цель
Читаемые герои и спутники в масштабе мира; развивать арт/анимацию от согласованного образа,
сохраняя IDs, управление и party/save owners. Production-персонажи пока не готовы.

## Владельцы
- `scripts/ember_exploration_hero_scale.gd` — размеры заглушек при 1 блоке = 1 м:
  protagonist 1.8, mira 1.5, orik/sena 1.7; collision radius отдельно 2.5/16 блока.
- `scripts/ember_player.gd` — CharacterBody/controller лидера; `scripts/ember_party_followers.gd` —
  капсулы/следование/формация как presentation party state, не отдельные сохранения спутников.
- `scripts/ember_party_state.gd`, `scripts/ember_explore_state.gd` — данные и активный лидер;
  `content/combat/units/protagonist.tres`, `mira.tres`, `orik.tres`, `sena.tres` в той же папке — определения героев.
- `scripts/prototypes/ember_combat_grid_3d_world.gd` — боевая проекция; её анимации не финальный риг героев.
- [Арт Миры](../art/characters/mira/README.md), `docs/art/characters/mira/drafts/` — локальные исходники/пробы.
- `scripts/ember_vn_assets.gd`, `scripts/ember_vn_portrait.gd`, `content/vn_portraits/` — native VN-путь;
  по Handoff каталог portraits пуст, artwork не становится runtime-портретом автоматически.

## Принято автором
- Компактный чиби-ориентир Миры принят: [NOW](../EMBER_NOW.md) → «Другие незакрытые направления»;
  это ориентир пробы, не production art и не принятый риг.
- Имя Кай зафиксировано: [NOW](../EMBER_NOW.md) → «Точка возврата к читаемости диорамы»;
  [GDD](../EMBER_GAME_DESIGN.md) → «Кай — протагонист»; в коде display_name «Кай», ID `protagonist` сохранён.
- Передвижение 3 блока/с, шаг до 1/4 блока и вертикальное догоняние камеры — принятые правила:
  [GDD](../EMBER_GAME_DESIGN.md) → «Передвижение вне боя — принято 13 сентября 2026»;
  живая приёмка новых размеров капсул этим не закрыта.

## Сделано без приёмки
- HeroScale используется Player/Followers; размеры видимой капсулы и физический радиус намеренно различаются.
- Следование/формация, смена лидера Tab/вкладкой сумки и party 1–4 реализованы; свои проходы/бой/save требуют проверки.
- Локальные слои PSD/Aseprite и idle-пробы Миры v1–v3: save/reopen/стык проверены по арт-README,
  плавность/амплитуда/общая кайма не приняты. В этом проходе медиа визуально не проверялись.
- Git: `5b6e390` — масштаб заглушек/Player/Followers; `2c2f76f` — имя Кай;
  на входе tracked-правок нет. `docs/art/characters/mira/` и `.tmp_mira_layer_audit.lua` локальны/untracked.
- Готовый игровой риг, подключённая idle-анимация Миры и отдельный pipeline остальных героев — не подтверждено.

## Открыто
- Личный масштаб/движение, проходы под препятствиями, выбор камеры0а; input/125%/weak-PC.
- Мира: край изображения, тонкие пряди, амплитуда движения и последующий риг; Cubism по арт-README не проверен.
- Общая система обликов персонажей и финальный формат их арта этим срезом не определены.
- Боевая projection-анимация не доказывает готовность художественных анимаций персонажей.
- Арт-README содержит больше локальных согласований, чем NOW; общей production-приёмки в заданных
  канонических статусах не подтверждено. Не повышать статус всех черновиков до готовых ассетов.

## Где остановились
Первое действие: пройти лидером/парой по `landscape_compact`, проверить масштаб/ступени/потолки; камеру сравнить в `compact_diorama_readability_study`.
Для арта открыть последнюю idle v3 Миры и отдельно согласовать край/движение перед работой над ригом.

## Зависимости
Берёт: физическую поверхность/масштаб/камеру у world-map, активную группу и IDs у game-systems.
Отдаёт: вид/размеры/анимационную проекцию героев исследованию и combat; не владеет боевой логикой или save.

## Ссылки
- [Handoff](../EMBER_TECHNICAL_HANDOFF.md) → «Exploration и партия», «Combat Lab»;
  [GDD](../EMBER_GAME_DESIGN.md) → «Лабораторная партия и тестовые герои»; [Мира](../art/characters/mira/README.md).
- [Test Plan](../../MIGRATION_TEST_PLAN.md) → «Передвижение вне боя…», «Exploration, party и save».
- Тесты: [followers](../../tools/test_party_followers.gd), [ступени](../../tools/test_explore_stepping.gd),
  [party/save](../../tools/test_party_save_v2.gd), [боевая анимация](../../tools/test_combat_vertical_animation.gd),
  [VN](../../tools/run_vn_asset_tests.py). Тесты здесь не запускались; художественные gates остаются ручными.
