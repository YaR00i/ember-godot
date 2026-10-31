# Ember — текущая точка

Актуально: 2026-10-31. Ветка: `codex/runtime-water-region-activity`.
Это короткий вход; действующие решения и gates принадлежат владельцам ниже.

## Активная цель

[Редактор](directions/editor.md): единый редактор земли/объектов, маршрут7 этапов — Product Plan.
Автор тестирует редактор **без сферы**; её оптимизация и `.exe` отложены.
Лепка/общие черновики/история/save/reopen/discard/три облика технически проверены;
ручная полная authoring-приёмка OPEN. Персонажи/Hoshi — параллельное направление.
Текущий приоритет — стоимость отрисовки и плавность мира до дальнейшего наполнения.

## Производительность мира — текущий срез

Единственный owner — [Производительность мира](EMBER_WORLD_PERFORMANCE.md).
Цель: **минимум120FPS/native2560×1440 на RTX5070**,без снижения ближней плотности.
Dense576м:25848patches,64grass/10flowers/8wheat,859props;near/wide/FOV40/70.
Native LOD/feature programs сохранены;трава+цветы main крупнее на25%,плотность прежняя.
Прежние fixes validation/cache IO/overview admission/weak-owner сохранены.
3D physics — встроенный Jolt в project.godot;terrain query p951,137→0,048мс,неFPS.
Native surface5120rays/step30–120Hz/Hoshi/crates и dense cold/return PASS.
Native indexing уменьшил upload vertices≈5x,атрибуты/треугольники/LOD/physics прежние.
Startup/editor5мс→gameplay3мс:clean p958,284/9,142мс;120FPS OPEN.
Cold scatter absent/pending/floor0/0,release281/281,return281exact;physics576trees PASS.
Новая фазовая3мс приёмка coverage PASS;startup≈21,5с. Native pixels/5120rays/brush Undo/save PASS.
Исправлен starvation bounded digest/read slots:near waiter больше не блокирует готового owner.
Native fairness/cancel/teardown/cache/material/Undo/save PASS;static startup timeout90с→21,823с.
Далее wide70:overview publication и render waits;редкие stalls ещё не объяснены.
Нужен restart Godot→F5;ручное ощущение новой physics/предметов OPEN.
Context IO teardown/fully cold startup/ручная камера и размер травы OPEN.
Main:вечер,Sun angular0/filter2/blur1/distance1600;резкость автору нравится.
Source/nodes пока целиком в RAM;Godot static/video не заменяют process/DXGI peaks.
Далее память и реальный GTX1060;его FPS/разрешение и iGPU не заданы,меню качества отложено.
Wind/mixed NPC/физика/город/local lights/wet world/long memory/manual OPEN.
QA на D:;child-only APPDATA/storage wrapper и точные условия — у performance owner.

## Границы и точки возврата

Единая карта — `scenes/landscape_compact.tscn`; внешний576м полигон — только stress fixture.
Карты/Resource — source; меши/коллизия/thumbnail/prefab производные, новая схема не вводилась.
Камень целиком, detailed/live-edge вид и общий конвертер **не приняты**.
Земля/камень не принимают автоматически деревья/воду/траву или все новые редакторы.
Потребители — [Workflow](EMBER_WORKFLOW.md#общие-изменения-и-потребители), owners —
[Handoff](EMBER_TECHNICAL_HANDOFF.md); тесты — [Test Plan](../MIGRATION_TEST_PLAN.md).

- Земля/материалы/общие кисти/слои/масштаб/POM и личные мазки —
  [Terrain Authoring](EMBER_TERRAIN_AUTHORING.md#открытая-приёмка-и-следующий-шаг).
  Трава Б на main подключена; свой F5/движение/стыки и UI125% остаются открытыми.
- [Объекты](directions/objects-looks.md), [материалы](directions/materials.md),
  [генераторы](directions/generators.md): дуб/берёза/клён/ель приняты, саванна нет;
  плоская листваB/остальные облики, личный Save/reopen/forest и общий вид OPEN.
- [World Authoring](EMBER_WORLD_AUTHORING_ARCHITECTURE.md#открытые-решения-перед-кодом-следующих-срезов):
  «Рельеф → План областей → + Объекты» → своя композиция/preview/Apply/Undo/Save/reopen/F6.
  Прямоугольный план принят; типы/смешивание/соседство/группы/посадка/свободный контур OPEN.
  WGEN/WorldPainter/Terrain3D — CLI/API-исследование; новая зависимость/renderer не согласованы.
- [Water Rendering](EMBER_WATER_RENDERING.md#следующий-разбор-моря2710): умеренное море
  предварительно принято по кадрам; свой F6/движение/weak-PC/полный старт OPEN.
  Отклик воды на персонажа — возврат после игровых квестов; погода/полировка отложены.

## Параллельные игровые направления

- [Игровые системы](directions/game-systems.md): «Послание на берегу» функционально принято28.10.
  Квестовые карточки/сценки/механизмы, ящики F/G/удар/бой, листья/срезаемая трава/урожай
  технически реализованы; ручной main/F5/ощущение автор отложил до оптимизации.
  BerryBush v7 принят по виду; общий UI урожая/вся трава не приняты. Выбран возврат вида
  при возвращении в локацию. Детали/первые действия — Inspector Design I3.14/I3.15.
  F-14/полёт остаются внешним экспериментом; текущую цель редактора не заменяют.
- [Персонажи](directions/characters.md): оригинальная Хоши подключена как тестовый лидер;
  native main/ступени/followers проверены, вид/походка/обводка/камера OPEN.
  Авторский тест: рестарт Godot→F5, WASD быстрый ход/Shift шаг; production-риг Миры не принят.
- [Бой](directions/combat.md): baseline-приёмки сохранены; свои условия/дозы/расстановка,
  balance/DPI и группа1–4→бой/Retry/save/load требуют ручной оценки. Декор не Battlefield.
- Собственные очереди этих направлений остаются у их owners; общий performance PASS
  не объявляет принятыми игровой save/input/narrow125% или механики другого чата.

## Стабильность и сохранность

Причины прежних native AV/shutdown/TDR OPEN; повтор exit0 не является crash fix.
Диагностика sandbox editor-exit29.10 — Handoff «Общие игровые системы»/Test Plan.
[JOI Exit](EMBER_JOI_EXIT_PLAN.md#возврат-к-незакрытой-ручной-приёмке): старыйLoad→Save/Load/
Reopen/Delete, диалог→бой/UI125%, physical/exportG4/G5/longA-B OPEN.
Старые карты/Test Pier удалены; legacy saves возвращаются к входу main.
Checkpoints/архивы — [quality-cleanup](directions/quality-cleanup.md); новая уборка требует
проверки употреблений и сохранности чужого dirty state. Commit/branch/push не разрешены.

Маршруты — [README](README.md) и [направления](directions/README.md).
NOW заменяет текущую точку; история измерений и повторные PASS здесь не накапливаются.
