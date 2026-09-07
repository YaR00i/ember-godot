# Ember Object Inspector — дизайн и дорожная карта

Статус: активный authoring-контракт, 28 августа 2026 года.

Этот документ описывает авторский Inspector в Godot для Ember-объектов. Он не разрешает новый формат карты, второй voxel editor или произвольный набор runtime-компонентов. Канонические ограничения остаются в [`MIGRATION_TEST_PLAN.md`](../MIGRATION_TEST_PLAN.md) и [`EMBER_TECHNICAL_HANDOFF.md`](EMBER_TECHNICAL_HANDOFF.md).

Статус на 2026-08-29: I0–I2 реализованы, I2 UI вручную принят пользователем в реальном Godot Inspector. I2.5 добавляет object-bound `Триггер с цепочкой`: карточный редактор всех семи canonical шагов `talk/give_item/set_flag/wait/open_shop/change_map/run_script` пишет существующий `content/ember/scripts/<id>.json`, назначает его scene-owned `Interact` и объединяет обе мутации в одну Undo/Redo operation. I2.6 расширяет тот же owner самостоятельными Box-зонами в `root/AuthoredTriggers`: они имеют Inspector bounds + viewport gizmo, переживают reimport/save/reopen и используют ту же action-chain без новой schema. I2.7 добавляет на тот же scene-owned Interact условие typed bool-флага, fallback chain и persistent one-shot completion; I2.8 переключает этот же owner между F и Area3D body-entered без второго sequencer. В runtime `give_item` останавливается на видимой reward-карточке, `wait` является реальной непроматываемой задержкой, магазин продолжает очередь после закрытия, а смена карты является явным финалом. Runtime и schema не дублируются.

## 1. Решение

Сделать один контекстный Ember-блок внутри штатного Godot Inspector через `EditorInspectorPlugin`.

Он должен отвечать на пять вопросов без раскрытия generated-узлов prefab:

1. Что это за объект и откуда он взялся?
2. Какие компоненты реально действуют на экземпляре?
3. Какие значения пришли из voxel asset, какие принадлежат `.tscn`, а какие вычислены runtime?
4. Какой свет, collider, interaction и content script получит объект в игре?
5. Что можно безопасно изменить здесь, а что нужно открыть в JOI или пересобрать?

В интерфейсе используем знакомое автору слово **«Модификаторы»**, но в данных сохраняем существующие типизированные компоненты и scene-owned дочерние узлы. Порядок карточек фиксированный; это не вычисляемый Blender stack.

## 2. Почему сейчас

Световой и voxel UX gates уже пройдены, двери, talk и read-only shop работают. Главный оставшийся риск миграции — не производительность, а ежедневное авторство:

- текущий `EmberVoxelProp` показывает только `model_id` и `placement_id`;
- свет спрятан в generated `Omni`, collider — в generated `Collision`, а их исходные параметры лежат в JOI metadata;
- `Interact` виден только если вручную раскрыть дочерний узел;
- `script_id`, `shop_id`, target map/region не дают рядом сведений о том, существует ли ссылка и что она запускает;
- прямое редактирование generated child выглядит допустимым, хотя targeted rebuild его перезапишет;
- migration dock полезен для rebuild, но не должен становиться вторым Inspector.

Это непосредственно закрывает незавершённую часть GitHub issue [#22](https://github.com/YaR00i/joi-conductor/issues/22): добавить/изменить `Interact` и сохранить локальный `.tscn` diff. Механики issue [#23](https://github.com/YaR00i/joi-conductor/issues/23) продолжаются после authoring gate, а не параллельно с временным UI.

## 3. Что уже является контрактом

Из JOI нельзя переносить UI один к одному, но нужно сохранить его модель:

- один `WorldObject` для выбора из viewport, Outliner и Library;
- компоненты Transform, Renderer, Collider, Light, Volume/Trigger, Interactivity и другие;
- происхождение значения `asset | instance | legacy | default`;
- instance override не переписывает asset неявно;
- удалённый у экземпляра компонент хранится как явное состояние и может быть восстановлен;
- reference-поля используют каталоги сцен, scripts, shops, maps и regions, а не свободный текст без проверки.

В Godot уже закреплено:

- `.tscn` владеет экземплярами props, transform и вложенным `Interact`;
- `.vox + .json` в JOI владеют формой, палитрой и asset metadata;
- generated mesh/prefab, `Mesh`, `Collision`, `Omni`, `ShadowBody` — производный cache;
- terrain и regions пока импортируются односторонне;
- полный reimport разрушителен и подтверждается отдельно.

PR [#17](https://github.com/YaR00i/joi-conductor/pull/17) закрепил двери как существующий `interactivity.kind = door` поверх voxel placement и точные `targetMapId/targetRegionId`. PR [#18](https://github.com/YaR00i/joi-conductor/pull/18) закрепил items/shops как отдельные каталоги. Inspector должен показывать ссылки на эти данные, а не копировать их в `.tscn`.

## 4. Заимствованные паттерны

### Godot

Используем штатный [`EditorInspectorPlugin`](https://docs.godotengine.org/en/stable/classes/class_editorinspectorplugin.html): он умеет добавлять custom controls в Inspector выбранного объекта. Plugin регистрируется и снимается симметрично через `add_inspector_plugin` / `remove_inspector_plugin`.

Обычные `@export_group` полезны для простых Node API, но недостаточны для объединения asset metadata, scene-owned children и resolved runtime state. Поэтому экспортные поля остаются сериализацией узла, а Ember summary строится custom Inspector-слоем.

### Unity

Из Unity Prefab Inspector берём явное различие asset и instance: изменённые свойства, добавленные/удалённые компоненты, `Apply` и `Revert` должны быть видны, а не угадываться. См. [Prefab instance Inspector](https://docs.unity3d.com/ja/current/Manual/prefab-instance-inspector-reference.html) и [instance overrides](https://docs.unity3d.com/ja/current/Manual/PrefabInstanceOverrides.html).

Для Ember это означает:

- каждый effective field показывает источник;
- scene override выделяется одним спокойным индикатором;
- `Сбросить к asset` и `Применить к asset` — разные действия;
- применение к asset никогда не происходит при обычном вводе поля.

### Unreal

Из Unreal Details Panel берём один selection flow: viewport и Outliner выбирают один объект и показывают одни Details; панель можно закрепить и фильтровать. См. [Unreal Editor Interface](https://dev.epicgames.com/documentation/unreal-engine/unreal-editor-interface) и [Details Panel UI](https://dev.epicgames.com/documentation/en-us/unreal-engine/details-panel-ui?application_version=4.27).

Для Ember это означает:

- search по полям и модификаторам;
- lock Inspector на текущем объекте;
- фильтры `Все | Изменено | Ошибки`;
- позднее — multi-selection только по пересечению совместимых полей.

### Blender

Из [Blender modifiers](https://docs.blender.org/manual/en/latest/modeling/modifiers/introduction.html) берём неразрушающие карточки, enable/disable, Add Modifier и компактное меню карточки.

Не берём drag-reorder: Ember Collider, Light и Interact не являются последовательными операциями над геометрией. Фиктивный порядок создаст ожидание, что перестановка меняет результат.

### Godot Asset Store и сторонние addons

Готовые плагины и ассеты разрешены и желательны, если они сокращают authoring work, но не меняют владельца данных незаметно. Перед добавлением:

1. сначала проверить штатный Godot API и уже установленный addon;
2. проверить совместимость с закреплённой версией Godot, лицензию, support status, дату обновления и issue tracker;
3. предпочитать Featured/Community или стабильный tagged release; Testing asset допускается только в изолированном spike;
4. зафиксировать источник, версию, лицензию, назначение и способ удаления в `docs/EMBER_ADDONS.md`;
5. импортировать только нужные файлы и проверить diff до включения plugin;
6. оборачивать addon одним Ember adapter/owner, если он касается данных или runtime;
7. иметь smoke на enable/disable, save/reopen и отсутствие утечек.

Addon не может вводить второй action graph, quest database, dialogue schema, inventory owner или renderer рядом с действующим контрактом. Если он требует такой параллельной системы, сначала оформляется migration/replace decision с условием удаления старого owner.

## 5. Информационная архитектура

### 5.1 Заголовок объекта

Верхний Ember-блок показывает:

- имя scene node;
- `placement_id` и `model_id`;
- тип: Voxel Prop, Region, Interact, Map;
- ownership badges: `Asset`, `Scene`, `Generated`;
- состояние prefab: актуален / source изменён / ошибка;
- быстрые действия: `Открыть source`, `Пересобрать prefab`, `Дублировать безопасно`.

Transform остаётся в штатном Godot Inspector. Не создаём второй набор Position/Rotation/Scale.

### 5.2 Сводка модификаторов

Карточки идут в фиксированном порядке:

1. `Voxel Renderer` — asset-derived, read-only: модель, размер сетки, surfaces opaque/transparent, source paths.
2. `Collider` — effective read-only в первой версии: есть ли physical metadata, тип generated shape, collision layer/mask.
3. `Emissive Light` — asset-derived summary: emissive voxel count/centroid, strength, range, shadows, flicker, suppress host shadow; ниже effective Godot energy/range и статус shadow candidate.
4. `Interact` — scene-owned и редактируемый: kind, trigger, script, shop, target map/region, note.
5. `References & diagnostics` — разрешённые content-ссылки, ошибки, предупреждения rebuild/reimport.

Если компонента нет, он не занимает большую пустую карточку. Доступные scene-owned компоненты предлагаются через `+ Добавить модификатор`.

### 5.3 Источник и effective value

Каждое неоднозначное поле отображается так:

```text
Дальность света       2.3 тайла     Asset
Effective range       36.8 Godot    Derived · tile size 16
Тени                  Да            Asset · production budget may cull
```

Используем три категории, не смешивая их:

- `Asset` — `.vox/.json`; редактируется через официальный JOI deep-link;
- `Scene` — `.tscn`; редактируется с Undo/Redo;
- `Derived` — generated/runtime; только для чтения, с указанием формулы/owner.

Цветовая маркировка не должна быть единственным различием: рядом всегда есть текстовый badge и tooltip.

### 5.4 Content references

`script_id`, `shop_id`, `target_map_id`, `target_region_id`, `trigger_id` получают специализированные editors:

- searchable selector из существующего каталога;
- статус `resolved` или конкретная ошибка;
- человекочитаемое имя рядом с id;
- краткий preview без копии редактора: тип сцены/action list, число шагов, первая реплика; для shop — число listings;
- кнопка `Открыть источник`;
- target region фильтруется выбранной target map.

Inspector не редактирует граф диалога и ассортимент магазина. Он только назначает и проверяет reference.

### 5.5 Light summary

Для светящегося voxel-пропа Inspector показывает отдельно authored и effective значения:

- число emissive-вокселей и их centroid;
- emissive strength;
- casts local light;
- range в тайлах и Godot units;
- shadow requested;
- host shadow suppressed / `ShadowBody`;
- torch/lantern flicker;
- текущий Map production budget и статус `candidate`, но не обещание постоянного shadow slot;
- наличие `Mesh`, `Omni`, `ShadowBody`, `Collision` после последнего build.

Дочерний generated `Omni` не является authoring API. Если он выбран напрямую, Inspector показывает предупреждение и кнопку `Выбрать владеющий EmberVoxelProp`.

## 6. Черновой макет

```text
┌ Ember Object ────────────────────────────────┐
│ ft_mage_door             Voxel Prop · Scene  │
│ model vox_fan_door · placement ft_mage_door │
│ prefab актуален                              │
│ [Source] [Rebuild] [Safe duplicate]          │
├ Модификаторы ────────────────────────────────┤
│ ▾ Voxel Renderer                    Asset    │
│   16×28×4 · opaque 1 · transparent 0         │
│ ▾ Collider                          Asset    │
│   Physical · Trimesh · generated             │
│ ▾ Interact                           Scene   │
│   Kind          Door                         │
│   Trigger       mage_enter          resolved │
│   Target map    fan_town_mage       resolved │
│   Target region start               resolved │
│   Script        —                            │
│   [Remove modifier]                          │
│                                               │
│ [+ Добавить модификатор]                     │
├ Диагностика ─────────────────────────────────┤
│ Нет ошибок · local scene diff expected       │
└───────────────────────────────────────────────┘
```

## 7. Разрешённые операции

### Первая версия

- читать identity, metadata, generated state и references;
- добавлять/удалять только существующий `Interact` как scene-owned child;
- менять существующие поля `EmberInteract`;
- выбирать scripts/shops/maps/regions из существующих каталогов;
- открывать source и запускать targeted rebuild;
- все scene mutations проводить через `EditorUndoRedoManager`;
- одна завершённая правка поля = одна undo operation.

### Не в первой версии

- прямое редактирование generated `Omni`, `Collision`, `Mesh`, `ShadowBody`;
- произвольное добавление GDScript к объекту как gameplay modifier;
- копирование JSON сцены/script/shop внутрь `.tscn`;
- новый Godot-only `LightOverride` или `ColliderOverride` до вертикального schema/ownership решения;
- reorder карточек;
- встроенный dialogue/shop/voxel editor;
- массовое редактирование несовместимых типов.

## 8. Валидация и безопасность

Inspector показывает проблему там, где автор её создаёт:

- duplicate/missing `placement_id`;
- отсутствующий model source;
- stale prefab signature;
- `Interact` без обязательного поля своего kind;
- missing script/shop/map/region/trigger;
- target region не принадлежит target map;
- generated child изменён вручную и будет потерян при rebuild;
- scene-owned modifier имеет неправильного `owner` и не сохранится;
- collider/light metadata расходятся с фактически собранным prefab.

Ошибка блокирует только опасную операцию, а не весь Inspector. Предупреждение содержит действие: `Выбрать`, `Открыть`, `Исправить`, `Пересобрать`.

## 9. Архитектурная граница

Предлагаемые owners:

- `ember_object_inspector_model.gd` — pure read model: собирает identity/components/sources/diagnostics из выбранного узла и pack; не создаёт UI и не пишет сцену;
- `ember_object_inspector_plugin.gd` — `EditorInspectorPlugin`, только selection routing и UI composition;
- `ember_object_inspector_actions.gd` — scene-owned команды add/remove/edit `Interact` через Undo/Redo;
- существующие `EmberVoxelPrefab`, `EmberSceneAuthoring`, `EmberPack` и deep-links переиспользуются, не копируются;
- существующий migration dock остаётся владельцем benchmark/rebuild workflow, но общие leaf-функции можно вызвать из Inspector.

Не добавлять всю систему в `plugin.gd` или `ember_tools_dock.gd`: оба остаются orchestration.

## 10. Дорожная карта

### I0 — контракт и fixture

Цель: зафиксировать read model до UI.

- inventory существующих Ember nodes и generated children;
- pure snapshot для обычного prop, lantern, door, talk NPC, shop;
- reference resolver `scripts → scenes`, shops/items, maps/regions;
- диагностика stale/missing/owner;
- headless snapshots на `agent_sandbox` и одном `fan_town` lantern/door.

Выход: один object snapshot объясняет текущий runtime без чтения `.tscn` вручную. Сцены не меняются.

### I1 — read-only Inspector MVP

Цель: сделать выбор объекта понятным до добавления новых editor mutations.

- зарегистрировать Inspector plugin симметрично;
- header, ownership badges, prefab freshness;
- карточки Renderer, Collider, Light, Interact и References;
- source/rebuild/select-owner actions;
- search `Все | Ошибки` минимум;
- lifecycle smoke enable/disable plugin и смены selection.

Выход: выбранный фонарь показывает полный effective light contract; выбранная дверь показывает destination и resolved status.

### I2 — Interact authoring

Цель: закрыть оставшийся authoring пункт issue #22.

- `+ Interact` создаёт ровно один scene-owned `EmberInteract` и shape по общему helper;
- kind-dependent fields;
- dropdown/preview scripts, shops, maps, regions, triggers;
- remove/restore, Undo/Redo;
- save/reopen;
- локальный `.tscn` diff без полного reimport и без изменения JOI JSON.

Выход: на safe duplicate можно добавить talk/shop/door, сохранить, открыть заново и пройти headless runtime.

### I3 — source/override UX

Цель: исключить случайное редактирование не того owner.

- modified/source filters;
- field-level badges и reset;
- explicit `Применить к asset` только для уже существующих JOI deep-link workflows, без скрытой записи;
- warning на generated child;
- lock Inspector;
- compact content preview.

Выход: автор без чтения документа отличает asset edit, scene edit и derived result.

### I2.5 — Trigger + action-chain authoring

Цель: создавать проверенный ранее gameplay flow без ручной правки JSON.

- `+ Триггер с цепочкой` создаёт object-bound `EmberInteract`, `Shape` и canonical action-list одной Undo operation;
- существующий `Цепочка действий` открывается внутри карточки Interact;
- шаги добавляются, удаляются и переставляются кнопками; поля используют каталоги dialogues/items/scripts/shops/maps/regions;
- writer меняет только `content/ember/scripts/<id>.json`, runtime читает его прежним `EmberActionScript`;
- `give_item` показывает название, фактический прирост и итоговое количество; `wait.sec > 0` показывает отдельное состояние паузы, которое F не пропускает;
- `open_shop` возобновляет оставшуюся очередь после Esc; `change_map` обязан быть последним и переносит authored `targetMapId/targetRegionId` через существующий transition owner;
- несохранённая форма отменяется без mutation; удаление сохранённой цепочки не удаляет весь Interact, а одной Undo operation очищает его `script_id` и canonical JSON, сохраняя shop/type/Shape и остальные scene-owned поля;
- `set_flag` не показывает сырой `true`: имя объяснено как устойчивый save-key, bool имеет выбор `Да/Нет`, а text/number используют свои guided inputs; JSON по-прежнему хранит canonical typed `bool|string|number`;
- Undo/Redo синхронно восстанавливает `.tscn`-ссылку и JSON; новое имя после первого сохранения неизменно, чтобы не ломать references;
- полноценный dialogue graph и authored region-shape editing остаются следующими отдельными срезами.

Выход: автор выбирает prop, создаёт триггер, собирает `talk → item → flag`, сохраняет сцену и получает исполнимый F-flow без кода.

### I2.6 — Standalone volume triggers

Цель: создавать F-события в пространстве без декоративного объекта и без ручного редактирования дерева сцены.

- единственная команда в bottom workflow создаёт `EmberInteract + BoxShape3D` под scene-owned `root/AuthoredTriggers`, а не внутри generated `Map`;
- позиция берётся из выбранного spatial anchor, иначе из существующего `player_start`; автор затем перемещает зону штатным Godot transform gizmo;
- Inspector использует прежние Interact и action-chain формы и добавляет только X/Высота/Z для Box; отдельного trigger schema/editor/runtime нет;
- cyan wire gizmo показывается только у выбранной самостоятельной зоны и не является runtime-геометрией;
- F-дистанция вычисляется до поверхности Box/Sphere, поэтому протяжённый объём не имеет мёртвого центра;
- создание, изменение bounds, chain binding и удаление являются раздельными Undo/Redo actions;
- `AuthoredTriggers` переживает generated Map clear, Ctrl+S и reopen; `test_standalone_trigger_authoring.gd` закрепляет ownership и round-trip.

Выход: автор ставит невидимую F-зону, видит её границы, собирает цепочку и получает исполнимое событие без кода или JSON.

### I2.7 — Launch rules: condition, fallback, one-shot

Цель: собирать типичный JRPG gate без кода и без нового condition graph.

- поля `condition_flag_id/condition_expected/fallback_script_id/one_shot/completion_flag_id` принадлежат существующему scene-owned `EmberInteract` и проходят общий `INTERACT_FIELDS` Undo/Redo owner;
- условие читает только typed bool из `EmberExploreState.flags`: `Да` равно строго `true`, `Нет` также принимает отсутствующий ключ;
- при failed condition fallback запускается тем же `EmberInteractionUi`; без fallback Interact выходит из F-группы и не показывает мёртвую подсказку;
- completion key предлагается из стабильных map/object ids, но сохраняется явно, поэтому дальнейшее переименование node не ломает старый save;
- one-shot записывает completion только при успешном окончании основной цепочки. Fallback, Esc/abort и незавершённый reward/wait его не расходуют;
- progress signal реактивно пересчитывает доступность без `_process`, scene traverse или второй state owner;
- pure `EmberInteractRules` отвечает только за route; action JSON, executor и Ember save v1 не получают новых типов;
- `test_interact_launch_rules.gd` закрепляет обе ветки, expected false/absent, completion/abort; standalone round-trip test закрепляет bool/string scene serialization.

Выход: автор связывает сюжетный флаг с основной и запасной цепочкой, включает одноразовость и получает persistent поведение без ручного JSON.

### I2.8 — Press / enter activation

Цель: тем же authoring flow создавать ручные события и автоматические JRPG-сцены.

- `activation_mode=press|enter` является строковым scene-owned полем `EmberInteract`, нормализуется в `press` и проходит прежний Undo/Redo/save/reopen;
- `press` сохраняет группу `ember_interact` и volume-distance подсказку F;
- `enter` удаляет объект из F-группы, включает monitoring только на player physics mask 2 и использует штатный `Area3D.body_entered`;
- callback не выполняет action сам: он вызывает общий `EmberPlayer.activate_interact`, который применяет тот же route и передаёт работу единственному `EmberInteractionUi`;
- один `body_entered` означает один запуск на пересечение; standing overlap не опрашивается по кадрам. Повтор возможен только после выхода/нового входа;
- condition без fallback, завершённый one-shot и открытый UI безопасно блокируют автоматический запуск;
- `test_interact_launch_rules.gd` проверяет masks/group, body-entered execution, completion и обратное переключение в F.

Выход: автор меняет один dropdown и превращает проверенную F-цепочку в автоматическую зону без копирования действий.

### I2.9 — Dialogue cards inside talk step

Цель: создавать обычные JRPG-разговоры без ручной правки JSON и без преждевременного graph editor.

- кнопка внутри canonical `talk`-шага открывает существующий dialogue ID либо предлагает устойчивый новый ID;
- `ember_dialogue_store.gd` является единственным projection/writer для прежнего `content/ember/scenes/<id>.json`;
- безопасный поднабор: линейные реплики и выбор, где каждый вариант ведёт в одну ответную реплику, после чего ветки сходятся; вариант может записать один typed `bool|string|number` флаг;
- speaker/name/portrait expression/text, вопрос и ответы редактируются карточками; перестановка и удаление не создают runtime-состояния;
- actors, background, portraitSide, splash, произвольные циклы, разные продолжения веток и несвязанные шаги блокируют запись и показывают причину read-only;
- сохранение диалога — отдельная Undo/Redo operation, после него talk dropdown принимает новый ID; цепочка сохраняется своей прежней operation;
- `EmberDialogueSession` остаётся runtime owner traversal, а editorLayout только пересобирается из карточек;
- `test_dialogue_authoring.gd` закрепляет projection существующих fixtures, сложную read-only сцену, typed choice flag, convergence, Undo/Redo и bridge в action-chain UI.

Выход: автор собирает разговор с простой развилкой из Inspector и сразу проходит его тем же runtime, не создавая второй dialogue schema.

### I2.10 — Full-size Ember Graph workspace

Цель: убрать большие сценарии из узкой колонки Inspector, сохранив один writer и один runtime contract.

- существующий `EditorPlugin` становится main-screen plugin с верхней вкладкой `Ember Graph`, а Inspector остаётся summary/launcher;
- `ember_graph_workspace.gd` использует штатные `GraphEdit/GraphNode`, zoom, grid, minimap и arrange; отдельный canvas/addon/schema не создаётся;
- action lists визуализируются как последовательные ноды, dialogue JSON — как полный граф по `next/options[].next`, включая сложные read-only VN-сцены;
- справа переиспользуются `EmberActionChainEditor` и `EmberDialogueEditor`, поэтому catalogs, validation и typed fields не расходятся;
- selection является навигацией: одна выбранная нода фильтрует соответствующую карточку справа, reply-ноды простого choice указывают на parent choice, `Показать все` сбрасывает фильтр, talk/run_script открывают связанный ресурс без выхода из workspace;
- action/document writes используют тот же `EmberObjectInspectorActions` и Undo/Redo; сложный dialogue graph не получает частичный writer;
- перемещение/auto-arrange пока меняет только editor view. Прямое создание и соединение нод требует отдельного vertical contract с validation циклов, веток и сохранением layout;
- `test_graph_workspace.gd` закрепляет action/dialogue connections, complex visibility/read-only, navigation options и standalone JSON Undo/Redo.

Выход: автор читает крупную сеть как в node editor, а безопасные правки делает в той же полноразмерной вкладке без второй системы данных.

### I2.11 — Mutable action-list graph

Цель: дать action-chain реальное node authoring, не превращая последовательный JSON-массив во второй graph schema.

- toolbar создаёт одну из семи canonical action-нод; Delete удаляет выбранные, но не позволяет оставить пустую цепочку;
- connection request означает reorder: target переносится сразу после source, затем все canonical последовательные связи перестраиваются;
- disconnection не создаёт недостижимый fragment, потому что action list по контракту всегда один связный маршрут;
- структурные операции сначала считывают текущие поля safe card editor, затем создают локальный snapshot draft;
- `↶/↷` принадлежат только несохранённой структуре; окончательная `Сохранить цепочку` остаётся единственной external JSON mutation и Editor Undo/Redo action;
- add/move/remove справа скрыты в graph mode, чтобы порядок не имел двух UI owners; Inspector card editor остаётся неизменным;
- dialogue connections не переиспользуют эту семантику: для choice нужны именованные output ports и отдельная graph validation волна;

### I2.12 — Named dialogue branches

- `ember_dialogue_graph_model.gd` — чистая структурная проекция прежнего `steps[].next/options[].next`; serialization и runtime ему не принадлежат;
- choice-нода получает отдельный подписанный output на каждый ответ, поэтому провод однозначно меняет один `options[index].next`;
- connection/disconnection работают в локальном черновике с ↶/↷; отсутствующая цель и недостижимая от `startStepId` нода блокируют сохранение и показываются в toolbar;
- `Сохранить граф` пишет canonical scene JSON через тот же `EmberObjectInspectorActions` и одну Editor Undo/Redo operation;
- смена связей дублирует документ losslessly и не удаляет `actors/bgArtId/portraitSide` и другие VN-поля; сложные property-карточки пока остаются read-only;
- `test_graph_workspace.gd` закрепляет порты, независимые targets, invalid intermediate draft, Undo/Redo, complex-field preservation и graph JSON round-trip.

### I2.13 — Stable graph view and layout ownership

- zoom, scroll и node offsets кэшируются по `kind:resourceId`, поэтому card edit, wire mutation, Undo/Redo и save/reopen внутри сессии не возвращают canvas к `(0, 0)`;
- для dialogue координаты нод являются authoring-данными уже существующего `editorLayout` и записываются вместе с `Сохранить граф`;
- action-list не получает нового layout-поля: его ручная раскладка остаётся session-only editor view, canonical gameplay JSON остаётся массивом шагов;
- `test_graph_workspace.gd` двигает ноду и камеру, запускает rebuild, проверяет view и затем проверяет сохранённые `editorLayout.x/y`.

### I2.14 — Dialogue node lifecycle

- toolbar создаёт только runtime-supported authoring types `dialogue/choice/set_flag/end`; ID генерируется устойчиво, позиция берётся из центра текущего GraphEdit viewport;
- Delete удаляет canonical step и его `editorLayout`, а входящие `next/options[].next` очищает вместо скрытого перенаправления;
- `Сделать стартом` является единственным UI-owner прежнего `startStepId`; недостижимая после смены старта часть графа видна диагностикой и блокирует save;
- add/delete/start входят в тот же локальный draft history и не пишут диск до `Сохранить граф`;
- `test_graph_workspace.gd` закрепляет add/connect/set-start/delete/Undo и восстановление layout.
- smoke проверяет add, Delete, reorder, local undo/redo и прежний canonical save.

### I2.15 — Inline authoring и visual groups

- Основные свойства `dialogue`, `choice`, `splash`, `set_flag`, `grant_cinders` редактируются непосредственно внутри `GraphNode`; изменение живёт в том же canonical draft, а focus enter/exit образуют одну локальную Undo/Redo-операцию.
- Правая dialogue-карточка остаётся read-only обзором. Это намеренно исключает два активных UI-owner одного поля и расхождение при rebuild.
- Shift-selection одной или нескольких dialogue-нод создаёт именованный native `GraphFrame`. Frame можно двигать вместе с участниками, переименовывать и удалять без удаления самих нод.
- Состав frame хранится в опциональном `editorGroups[{id,title,members}]`. Это только authoring metadata: dialogue executor, edge schema и порядок runtime не знают о группе.
- Одна нода входит не более чем в одну группу; удаление step очищает membership, пустая группа удаляется. Validation ловит повторный ID, неизвестный member и двойное членство.
- `GraphFrame` в Godot экспериментален, поэтому собственником остаётся простой `editorGroups`, а не Control-состояние. Будущий collapsible/reusable subgraph сможет заменить представление без миграции gameplay JSON.
- Настоящий вложенный reusable subgraph с входными/выходными портами сознательно не смешивается с этой волной: он требует отдельного runtime-контракта вызова, scope переменных, диагностики циклов и save-versioning.
- `test_graph_workspace.gd` закрепляет inline edit + Undo, choice label, create/rename/ungroup/Undo, attach к frame и save/reopen membership.

### I2.16 — Collapsible frame workflow

- Drop свободной dialogue-ноды на раскрытый `GraphFrame` обрабатывается штатным `graph_elements_linked_to_frame_request`, но mutation выполняет наш pure model: membership переносится из прежней группы и входит в local Undo/Redo.
- Кнопка titlebar `Свернуть/Развернуть` хранит опциональный bool `collapsed` в той же editor-only группе. В compact view остаются название и число нод; gameplay edges и executor не меняются.
- Свернутый frame получает позицию из минимального `editorLayout` участников. Его перенос двигает attached nodes штатным GraphEdit-механизмом, поэтому после раскрытия сохраняется новая раскладка.
- `Убрать из группы` снимает membership только с выбранных нод; пустой frame удаляется. Если выбран сам frame, кнопка становится `Удалить группу`, но ноды и связи остаются.
- Вложенные frame и скрытые runtime-порты не вводятся: это всё ещё visual organization, а не второй dialogue executor.
- `test_graph_workspace.gd` закрепляет drop membership, collapse/visibility/Undo, selective detach и сохранение соседних members.
- Hotfix v1.22 не оставляет member `GraphNode.visible=false`: Godot продолжал строить connection geometry и обращался к очищенному port cache. В compact-view member-ноды и их линии вообще не создаются; draft/layout остаются источником восстановления. Перенос компактного frame применяет delta к `editorLayout` участников до rebuild.

### I2.17 — Boundary ports компактной группы

- Collapsed visual теперь представлен компактным proxy `GraphNode`, потому что `GraphFrame` не имеет connection slots. Proxy не является gameplay step и определяется только editor `group_id`.
- Edge внутри одной свёрнутой группы не рисуется. Edge снаружи внутрь перенаправляется на левый proxy-port; изнутри наружу — с правого proxy-port; между двумя свёрнутыми группами соединяются их proxy.
- Несколько runtime edges могут агрегироваться в один visual boundary-wire к той же цели. Заголовок показывает количество members, входящих и исходящих edges; canonical `next/options[].next` не меняются.
- Delete/select/rename распознают proxy как группу раньше обычной GraphNode, поэтому компактное представление нельзя случайно удалить как dialogue step.
- `test_graph_workspace.gd` закрепляет отсутствие member-ноды, compact size, оба boundary-порта, proxy connections, move delta и expand restore.

### I2.18 — Reversible branch duplication

- `Ctrl+D` и toolbar `Дубликат` используют один handler. В action-list выбранные шаги копируются подряд после последнего selected index; порядок и все typed fields сохраняются.
- Dialogue duplication живёт в pure `EmberDialogueGraphModel.duplicate_steps`: выбранным steps выдаются уникальные `<old>_copy_N`, complex fields копируются losslessly, layout получает offset `+60/+60`.
- Edge между двумя выбранными steps переназначается на новые IDs. Edge из копии наружу остаётся прежним общим continuation; внешние входы в выбранную ветку не копируются, чтобы дубликат не стал достижимым без явного авторского wire.
- Новые ноды выделяются после rebuild. Одна команда даёт одну запись local Undo/Redo и ничего не пишет до общего Save.
- Frame/proxy сам по себе не дублируется в этой волне: команда требует реальные selected step IDs, не editor group representation.
- `test_graph_workspace.gd` закрепляет action block order/Undo и dialogue ID/remap/external exit/layout/selection/Undo.

### I2.19 — Searchable palette и create-from-wire

- ПКМ по пустому месту `GraphEdit` открывает одну контекстную палитру доступных canonical типов. Поиск сопоставляет и русское название, и сохранённый type; Enter активирует первый результат.
- Позиция новой ноды вычисляется в координатах графа с учётом текущих pan/zoom и привязывается к выбранному шагу сетки. Камера и существующая ручная раскладка не меняются.
- Если автор отпускает выходной wire в пустоте, палитра запоминает source node/port и после выбора сразу создаёт и подключает новую ноду. Если в пустоте отпущен провод от входа, новая нода создаётся перед target; типы без выхода из списка исключаются.
- Dialogue меняет только локальный graph draft. Action-list остаётся canonical массивом: output-to-empty вставляет шаг после source, input-to-empty — перед target. Общий Save и Editor Undo/Redo остаются единственным disk writer.
- Toolbar `+ Нода` переиспользует тот же create helper, поэтому палитра не создаёт параллельную систему authoring.
- `test_graph_workspace.gd` закрепляет поиск, координату, оба направления auto-wire и action insertion order.

### I2.20 — Session clipboard с безопасным remap

- Native сигналы `copy_nodes_request`, `cut_nodes_request`, `paste_nodes_request` и видимое меню `Буфер` вызывают один набор handlers. Clipboard живёт только в `Ember Graph` текущей editor-сессии и не пишет системный буфер или JSON.
- Action copy хранит ordered deep-copy выбранных canonical steps. Paste вставляет весь блок после последней выбранной ноды или в конец; Cut разрешён только если в цепочке остаётся хотя бы один шаг.
- Dialogue copy хранит lossless step dictionaries и относительный `editorLayout`. Paste использует тот же pure clone/remap path, что `Ctrl+D`, выдаёт новые collision-free IDs и размещает ветку у курсора с сохранением взаимного расположения.
- Внутренние `next/options[].next` переназначаются на новые IDs. Внешний переход сохраняется только если target существует в destination graph; отсутствующая cross-resource цель очищается и становится видимой graph-validation ошибкой до Save.
- Copy ничего не добавляет в history. Cut и Paste создают по одной записи local ↶/↷; disk writer остаётся прежним общим Save + Editor Undo/Redo.
- Frame/proxy не копируется как runtime-subgraph: clipboard работает только с реальными step nodes. `test_graph_workspace.gd` закрепляет action order, Cut/Paste persistence, одну Undo и dialogue remap/cross-resource sanitation.
- Hotfix v1.27 связывает `Ctrl+Z`, `Ctrl+Shift+Z`/`Ctrl+Y` с той же local history; focused `LineEdit/TextEdit` сохраняет собственное текстовое сочетание. Переполненный однострочный toolbar заменён адаптивным `HFlowContainer`, а status/validation вынесены в отдельную autowrap-строку над canvas, поэтому ошибка больше не уезжает за правый край.

### Stop-line редактора перед возвратом к gameplay

Редактор не развивается бесконечно. Для вертикального JRPG-среза после I2.18 остаются ровно три обязательные стадии:

1. **Fast authoring — закрыто:** searchable context palette/create-from-wire в I2.19 и Copy/Cut/Paste с безопасным ID remap в I2.20.
2. **Diagnostics — закрыто в I2.21:** ошибка на конкретной node/port, переход к проблеме, broken-edge visibility и предупреждение о несохранённом draft.
3. **VN properties — закрыто в I2.22:** реально существующие в первом эпизоде actor/portrait side/emotion/background/splash. Choice conditions не добавлены без потребителя и runtime-семантики.

После этих стадий editor gate считается достаточным и работа возвращается к quests/combat. Reusable runtime-subgraphs, массовые scene modifiers и универсальный visual scripting не входят в stop-line и допускаются только по требованию реального контента.

### I2.22 — минимальные VN properties

- Scene-level `defaultBgArtId` редактируется над read-only обзором; node-level `bgArtId` и `portraitSide` живут прямо в canonical GraphNode draft.
- Сворачиваемая секция `Постановка` редактирует только основной `actors[0]`: `id`, `speaker`, `portraitKey`, `x/y/scale`, `flipX`. Она умеет создать или удалить главного актёра, но не выдаёт себя за полноценный stage compositor.
- Мутация deep-copy меняет только выбранное поле: `lockY/floorY/z/rotate` и любые будущие неизвестные поля, а также actors[1..N], не теряются.
- `splash` вошёл в authoring palette с прежними `artId/captionRu/next`. `EmberDialogueSession.current_visual_state()` отдаёт UI исходные visual-поля и fallback `defaultBgArtId`, не создавая второго формата сцены.
- Choice conditions намеренно отсутствуют: текущий JSON имеет только `setFlags` как эффект ответа, ни один сюжетный fixture не требует condition, а runtime не определяет predicate. Возврат к этому вопросу требует конкретного квестового сценария и полного schema → editor → runtime → tests среза.

Это завершает stop-line общей полировки Ember Graph. Следующая работа должна снова давать gameplay-вертикаль quests/combat, а не расширять универсальный node editor.

### I2.23 — Live preview сцен (явно запрошенное дополнение)

- `▶ Превью сцены` открывает отдельное окно, но использует текущий in-memory dialogue draft: Save для preview не нужен.
- Клик по GraphNode меняет preview-кадр; поля внутри ноды и постановки обновляют его сразу. Навигация preview следует только canonical `next/options[].next` и имеет локальные Back/Restart без gameplay mutation.
- `EmberVnSceneState` — общий pure owner stage-проекции для editor и `EmberDialogueSession`: default background, fallback actor и inheritance состава перед choice повторяют прежний JOI `sceneStage.ts` contract.
- `EmberVnAssets` только читает прежние registry/path. Он не импортирует и не копирует арты в Godot, не создаёт второй каталог; missing path остаётся видимой диагностикой.
- `use: talk/shop_intro` показывает текст/выбор без VN stage, как прежний `ScenePlayer`. Произвольные `.tscn` не входят в Ember scene JSON preview: для них owner — штатный Godot viewport и F6.

### I2.24 — visual asset/character picker

- Ручные ID-поля background/splash/speaker/emotion заменены `OptionButton`, но serialization остаётся прежней строкой ID.
- Background picker фильтрует `kind: portrait`, показывает caption + ID + 48px thumbnail и отдельно маркирует missing file. Старый неизвестный ID добавляется warning-item и сохраняется до явного выбора.
- Speaker picker перечисляет только директории с `portraits/<speaker>/registry.json`; emotion picker перестраивается из `expressions` выбранного speaker и показывает label/key/thumbnail.
- Выбор identity в dialogue синхронизирует `speaker/portraitKey` шага и основного `actors[0]`, не трогая координаты и расширенные actor keys. В choice picker постановки меняет только actor.
- Каталог остаётся read-only проекцией JOI pack; новый Godot asset registry не создаётся.

### I2.21 — Node diagnostics и unsaved-draft guard

- `ActionStore.validation_diagnostics` и `DialogueGraphModel.validation_diagnostics` являются structured-проекцией прежнего validation owner: `message + stepId/stepIndex + port`. Старые `validation_errors` теперь только возвращают те же messages, поэтому Save/runtime не получают второго набора правил.
- Каждая проблемная GraphNode получает красный title badge и autowrap-сообщение. Для broken dialogue edge diagnostic хранит точный named output port; collapsed proxy агрегирует ошибки своих members без создания runtime-ноды.
- Кнопка `К первой ошибке` выбирает offending step и прокручивает canvas к нему; если member скрыт в collapsed frame, выбирается его proxy. Global document error остаётся в общей status-строке.
- Dirty определяется сравнением текущего normalized draft с initial history snapshot, включая inline fields и dialogue layout. Смена kind/resource, Reload и переход по link при dirty draft не выполняются сразу: selector восстанавливается, а modal предлагает `Отбросить и перейти` или `Остаться`.
- Save по-прежнему сбрасывает history через прежний writer без лишнего modal. Переключение main-screen tab само по себе не уничтожает draft, поэтому отдельное блокирование вкладки не требуется.
- `test_graph_workspace.gd` закрепляет exact broken port, badge/message, focus action, исчезновение ошибки после Undo, action-step mapping и оба исхода discard guard.

Выход: большую action-chain можно собирать и переставлять на canvas, сохраняя прежний executor и JSON.

### I4 — viewport diagnostics и multi-edit

Цель: ускорить повторяющуюся расстановку после принятия single-object UX.

- toggles для collider/light/interact gizmos;
- радиус/centroid/trigger bounds overlays;
- multi-selection показывает только общие компоненты;
- mixed values отображаются явно;
- batch edit создаёт одну Undo action и меняет только выбранные совместимые объекты.

Выход: десять фонарей можно проверить или изменить общим допустимым полем без traversal/rebuild мира на каждый input.

### I5 — новые modifiers только по вертикальному контракту

Кандидаты: instance light override, collider override, visibility/cutaway role. Каждый допускается только после решения:

1. где сериализуется;
2. кто нормализует/валидирует;
3. как импортируется;
4. как preview совпадает с runtime;
5. как переживает rebuild/reimport;
6. какие targeted tests закрывают reset/inherit.

Без этого `+ Добавить модификатор` показывает только уже поддержанные типы.

## 11. Порядок относительно миграции

Inspector становится authoring gate между текущими Wave 3/4 и следующим gameplay-state срезом:

1. I0–I1: сначала видимость существующих контрактов.
2. I2: закрыть Add/change Interact и local diff в Wave 3.
3. Ручной UX-прогон talk/shop/door через Inspector в `agent_sandbox`.
4. Затем продолжить buy/sell, inventory/save и cutaway из Wave 4.
5. I3–I4 выполнять по фактическим неудобствам, не блокируя весь vertical slice.

GitHub остаётся единственным трекером: обновить issue #22 этим design doc или завести один связанный Inspector issue внутри milestone Ember; не создавать вторую доску.

## 12. Критерии принятия Inspector foundation

- Один выбранный `EmberVoxelProp` объясняет asset, scene и generated состояние в одной панели.
- Фонарь показывает authored и effective свет без выбора дочернего `Omni`.
- Door/talk/shop показывают resolved content refs и конкретные ошибки.
- Add/edit/remove `Interact` проходит Undo/Redo, Ctrl+S, reopen и runtime smoke.
- Одна локальная правка даёт локальный `.tscn` diff; JOI JSON не меняется.
- Targeted rebuild не теряет scene-owned `Interact` и transform.
- Plugin enable/disable и 20 смен selection не накапливают controls/signals.
- Не появилось нового schema, второго Inspector dock или копии content editor.

### I2.25 — crash-safe visual picker

Godot 4.7.2 завершал editor native `0xc0000005` внутри SVG loader: demo `hu_tao_clear_placeholder.svg` содержал управляющие байты и битый UTF-8. Asset исправлен; picker и live preview используют один `EmberVnAssets` с decoded-image cache, а preview создаёт только display-sized textures. Popup entries намеренно text/status-only; визуальный preview выбранного background, speaker и portrait принадлежит соседнему `TextureRect`. JSON ID, registry ownership и Undo/Redo не изменены.

### I2.26 — Godot-native VN backgrounds

По прямому запросу владельца новый фон больше не авторится через JOI `arts/registry.json`. `EmberVnBackground` — один `.tres` на ассет с устойчивым ID, display name, `res://` image path, kind и tags; изображение хранится отдельно в `res://assets/vn_backgrounds/`. `EmberVnAssets` объединяет native Resources и legacy registry, причём `.tres` имеет приоритет, а JSON остаётся только compatibility input. UI не получает второго resolver: picker и live preview используют тот же каталог. Импорт через FileDialog копирует файл и создаёт Resource, выбор ID участвует в local draft Undo/Redo, но отмена не удаляет общий library asset. Dialogue JSON здесь намеренно не заменён: это отдельный будущий schema → editor → runtime → serialization срез.

### I2.27 — inherited scene background

`defaultBgArtId` становится явным authored default, а `bgArtId` ноды — только optional override. Новый контент не дублирует ID по всем dialogue/choice. Пустой или отсутствующий override одинаково разрешается через общий `EmberVnSceneState`; node picker показывает effective inherited asset. Миграция `inherit_scene_background` является pure lossless operation в существующем graph model и удаляет только per-node `bgArtId`. Кнопка выполняет её одной local Undo/Redo записью до canonical Save. Отдельный фон ноды остаётся доступен для реальной смены локации внутри сцены.

### I2.28 — VN layer contract и Godot-native portraits

Preview использует фиксированные semantic layers: background ниже stage, actor `z` ограничен actor-layer, dialogue panel выше всех портретов. Это presentation contract, а не новое поле сцены. Для ассетов `EmberVnPortrait` хранит один native `speaker_id + portrait_key + image_path` Resource на эмоцию; изображения лежат в `res://assets/vn_portraits/<speaker>/`. `EmberVnAssets` остаётся единственным resolver и объединяет native `.tres` с legacy portrait registry, native identity имеет приоритет. Импорт `+ Арт` создаёт общий library asset, а выбор эмоции меняет прежнюю строку `portraitKey` одной draft Undo/Redo operation.

### I2.29 — Godot-native dialogue documents

`EmberDialogueCatalog` становится единственным read owner для editor/runtime/pickers: сначала ищет `EmberDialogueResource` в `res://content/dialogues/`, затем использует прежний JOI `scenes/<id>.json` как legacy fallback. Сам graph document не переводится в новую параллельную schema — Resource lossless хранит тот же Dictionary с `steps`, edges, stage, layout и неизвестными полями.

Миграция только явная и по одной сцене. Ember Graph показывает текущий owner и кнопку `Перенести в .tres`; операция создаёт native Resource, не переписывая и не удаляя legacy JSON. После этого canonical save пишет только `.tres`, а native-first runtime видит тот же документ. Undo восстанавливает полный снимок обоих owners, поэтому отмена миграции удаляет Resource и возвращает исходный JSON; Redo повторяет перенос. Новые диалоги сразу native. Массовый importer не вводится, чтобы каждая VN-сцена проходила preview/save/reopen/runtime acceptance отдельно.

### I2.30 — Godot-native action-chain documents

`EmberActionCatalog` становится единственным read owner для action editor, reference pickers, validation и runtime executor. Native `EmberActionResource` хранит прежний lossless `id/nameRu/steps` Dictionary в `res://content/action_scripts/`; JOI `scripts/<id>.json` остаётся fallback до явной миграции. Новой action schema или второго executor нет.

Ember Graph показывает owner и запускает одну Editor Undo/Redo миграцию. После неё save пишет только Resource, старый JSON не меняется. Snapshot включает native document, legacy document и исходный legacy text, поэтому Undo восстанавливает не только семантику, но и байты JSON без formatter diff. Создание/удаление action document вместе с scene-owned Interact binding использует тот же snapshot-aware mutation path. Новые цепочки native с первого сохранения; массовая конверсия отсутствует.

### I2.31 — Godot-native shop documents

`EmberShopCatalog` — единственная native-first граница для editor и runtime: `res://content/shops/<id>.tres` имеет приоритет, общий JOI `shops/catalog.json` остаётся read-only fallback. Новой listing schema и второго owner экономики нет.

`EmberShopEditor` встроен в canonical шаг `open_shop`: название, item picker, buy/sell price, finite/infinite stock, reorder и delete. Legacy owner блокирует Save до явной per-shop миграции. `EmberObjectInspectorActions` проводит save/migrate одной Editor Undo/Redo operation; snapshot содержит только native override, поэтому Undo возвращает legacy-only owner и никогда не переписывает общий каталог. Новые магазины сразу native. `test_shop_resource.gd` проверяет UI projection, runtime/economy parity, legacy-byte safety и полный Undo/Redo.

### I2.32 — Godot-native item documents

`EmberItemCatalog` заменяет прямое чтение `items[]` единым native-first resolver для shop, inventory, equipment, consumable и economy. `EmberItemResource` lossless хранит прежний item Dictionary в `res://content/items/<id>.tres`; legacy `items/catalog.json` остаётся read-only fallback и продолжает владеть общей pixel-icon библиотекой.

`EmberItemEditor` вложен в строку `EmberShopEditor` и редактирует существующие поля без новой schema: identity/name, kind/slot/rarity/stack/useIn/iconId, atk/def/hpRestore, sell rules, tags и notes. Legacy owner блокирует Save до явной миграции; новый предмет сразу native. Save/migrate проходят через общий `EmberObjectInspectorActions` и Editor Undo/Redo. `test_item_resource.gd` проверяет UI, owner switch, inventory/use/economy parity и неизменность legacy bytes.

### I2.33 — shared visual ID library

`EmberVisualLibraryPicker` является общей плиточной проекцией canonical catalogs, а не новым owner. Первый срез использует `EmberItemVisuals`: legacy `palette + rows` декодируется в nearest-neighbor preview, item editor выбирает `iconId`, а shop listing выбирает `itemId` из одного searchable `ItemList`. Compact OptionButton сохраняется как fallback; изображения не добавляются в его PopupMenu из-за прежнего native-crash Godot 4.7.2. Контракт и очередность VN/voxel/map адаптеров описаны в `docs/EMBER_VISUAL_LIBRARY_DESIGN.md`; `test_visual_library.gd` закрепляет image decode, stable IDs и editor projection.

### I2.34 — VN visual libraries

`EmberVnVisuals` проецирует существующий `EmberVnAssets` в те же tile entries: background, speaker representative и speaker-scoped expression. Ember Graph добавляет `▦` рядом с compact fields, но вызывает прежние draft mutation, actor sync, import и live-preview callbacks. Empty background сохраняет inherit/default semantics, portrait-kind не попадает в background, missing legacy ID остаётся warning entry. Thumbnail/cache по-прежнему принадлежит `EmberVnAssets`; visual adapter ничего не сериализует.

### I2.35 — voxel prefab library

Нижняя workflow-панель использует тот же `EmberVisualLibraryPicker` для native Godot models и явно помеченной очереди legacy import. `EmberVoxelVisuals` хранит только read-only projection; отсутствующая сцена помечается и создаётся только при явном выборе. Добавление идёт в существующий `Map/Props` через `EmberSceneAuthoring`, получает уникальный `placement_id` и одну Editor Undo/Redo action. С v1.98 writable owner — `EmberVoxelModelResource`; projection/prefab не становятся вторым registry или writer.

### I2.36 — bottom workflow layout

Длинные операции migration dock не являются прямыми minimum-size детьми bottom panel. Постоянная шапка содержит явное `Закрыть`, статус ограничен одной строкой, а все разделы находятся в вертикальном `ScrollContainer` и сворачиваются независимо. Godot снова владеет высотой и строкой нижних вкладок; изменение layout не затрагивает map/prefab/content ownership.

### I2.37 — voxel preview renderer

Stock `EditorResourcePreview` вернул `null` для generated PackedScenes в ручном gate. `EmberVoxelPreviewRenderer` поэтому использует один editor-only main-thread `SubViewport`: готовый prefab инстанцируется без записи, authored lights отключаются, `Mesh.get_aabb()` задаёт ортографический кадр, texture кэшируется по path + mtime. Очередь последовательна и не входит в runtime; preview generator worker-thread, PNG cache и новая asset schema не вводятся.

### I2.38 — source-only voxel previews

Отсутствующий prefab больше не оставляет пустую tile: `EmberVoxelPrefab.make_preview_instance()` собирает transient дерево теми же внутренними mesher/material/tree функциями, но не проходит `_install_mesh_resource`/`ResourceSaver`. Поэтому `◇` является только статусом cache, не потерей визуальной информации. Source preview cache зависит от mtime `.vox/.json`; добавление объекта остаётся единственной операцией, создающей отсутствующий prefab.

### I2.39 — visual map/region destinations

Door form и action-card `change_map` сохраняют compact `OptionButton`, но получают рядом общий `▦` picker. `EmberMapVisuals` является read-only адаптером canonical map resolver: runtime и preview используют одну pure `EmberTileMesher.surface_grid()`, затем editor рисует CPU-схему поверхности, prop markers и region outline. Выбор возвращает только существующие `targetMapId/targetRegionId`; Popup, texture cache и layout не сериализуются. Scene execution, screenshot cache, новый registry и второй map format не вводятся.

### I3.0 — quest description authoring

`EmberQuestResource.id` является только стабильным именем авторского Resource и не попадает в save. `statusFlagId` отдельно связывает `quest_marker.script_id` с общим typed status (`active/done/true`); каждая цель читает собственный `flagId`. Inline `EmberQuestEditor` открывается у marker, а один `EmberObjectInspectorActions.save_quest_for_interact()` объединяет запись Resource и marker binding в Undo/Redo. Runtime `EmberQuestJournalUi` является pure projection `EmberQuestCatalog + EmberExploreState.flags`, не хранит прогресс и не вводит новые action types. Поэтому цепочки и диалоги продолжают менять квесты прежним `set_flag`.

### I3.1 — quest progress clarity

Quest editor явно подписывает четыре разные роли: Resource ID, status save-key, внутренний ID строки и completion save-key цели. Journal показывает только относящиеся к карточке значения текущего save и в debug разрешает scoped reset этих ключей через существующий `EmberExploreState.clear_flags()`. Это не новая система save/reset и не скрытая мутация Resource. Demo намеренно разделён на `sandbox_notice_quest`, `sandbox_notice_status` и `sandbox_notice_read`; каталог кэширует status-to-Resource index, чтобы marker projection не сканировала каталог каждый кадр.

### I3.2 — quest flag references

`EmberQuestStore.flag_reference_entries()` является editor-only read projection существующих Resources: status и objectives превращаются в searchable карточки для общего `EmberVisualLibraryPopup`. Action-chain `set_flag`, простой dialogue choice и inline dialogue Graph node используют одну проекцию и сохраняют только выбранную строку в прежнее поле `flag`. Произвольный ручной flag остаётся разрешён. Picker не является registry, не владеет прогрессом и не добавляет новый action type; Graph choice участвует в прежнем local draft Undo.

### I3.3 — first-class quest graph

`Ember Graph` получает третий document kind `quest`, но не третий runtime graph: список читает прежний `EmberQuestStore`, корневая нода проецирует поля одного `EmberQuestResource`, а objective-ноды — его существующий массив целей. Связи root → objective вычисляются из containment и не редактируют порядок исполнения. Inline-поля, добавление/удаление цели и создание Resource входят в локальную draft history; несохранённый новый Resource защищён navigation guard. Единственный disk write проходит через `EmberObjectInspectorActions.save_quest_document()` и общий Editor Undo/Redo owner. Dialogue/action по-прежнему отвечают за ветвление и изменение typed flags.

### I3.4 — quest event binding

Quest Resource не получает прямые `NodePath` к объектам и областям. Он остаётся описанием для журнала; объект, ветка диалога или место являются источником события и меняют canonical status/objective flag через прежний `set_flag` executor.

- Action-chain Inspector и Action/Dialogue Graph показывают authoring-presets `Начать задание`, `Выполнить цель`, `Завершить задание`. Это не новые runtime-типы: выбор quest/objective компилируется в существующий `set_flag(statusFlagId, "active"|"done")` либо `set_flag(objective.flagId, true)`.
- Для выбранного prop используется его прежняя кнопка `Цепочка действий` → `+ Событие задания`. Если взаимодействия ещё нет, `+ Триггер с цепочкой` сохраняет `EmberInteract + EmberActionResource` одной Editor Undo/Redo operation. В форме взаимодействия выбирается активация `Клавиша F`/`При входе`.
- Для места используется scene-owned `EmberInteract` с `Area3D + CollisionShape3D`; штатный `body_entered` запускает ту же action chain. Stable map/placement IDs используются только для authoring/backlinks, runtime не хранит хрупкий путь к сценовой ноде внутри Quest Resource.
- Object/location binding имеет gate и one-shot. Launch rule использует общий typed-value editor и точное сравнение, поэтому условие `statusFlagId == "active"` не требует дублирующего boolean-флага. Старые boolean scene values остаются совместимыми.
- Следующий UX-срез — read-only `Используется в` в Quest Graph: объекты, trigger volumes, action nodes и dialogue branches, с переходом к владельцу и диагностикой отсутствующей ссылки. Это editor-only индекс, не поле Quest Resource.

Пример: `Диалог → Начать «Записка у ворот»` сохраняет `sandbox_notice_status = "active"`. Ветка ответа `Помочь → Выполнить цель «Прочитать табличку»` сохраняет `sandbox_notice_read = true`. Вход в authored Area3D может выполнить тот же preset автоматически; повтор блокируется one-shot completion flag. Квестовый runtime при этом не знает, был источником NPC, сундук или область.

### I3.5 — последовательность целей

Цель получает `requiresObjectiveIds: String[]`. Это dependency DAG, а не порядковый номер: один синий провод `A → B` означает, что B откроется после A; несколько входов в B означают `all`. Поэтому одной схемой выражаются `A → B → C`, параллельные `A → B` и `A → C`, а также схождение `B + C → D`. Exclusive/any-of ветки не угадываются заранее и требуют отдельного сюжетного сценария.

- Золотые root→objective connections остаются вычисляемым containment. Синие objective→objective connections редактируются, удаляются ПКМ и участвуют в local Undo/Redo.
- Store нормализует зависимости, проверяет missing/self/duplicate/cycle и не позволяет сохранить неоднозначные duplicate completion flags. Удаление цели очищает входящие ссылки; переименование переносит ссылки и layout key.
- `EmberQuestCatalog.projection()` добавляет objective `available/locked/missingPrerequisiteIds`; журнал показывает `◆` текущую, `◇` заблокированную с пояснением и `✓` выполненную.
- Runtime не получает второй quest executor. `EmberExploreState.apply_authored_flag()` проверяет только записи из action/dialogue authoring. Обычный `set_flag` completion-ключа проходит, если все prerequisites выполнены; иначе save не меняется и `EmberInteractionUi` показывает notice. Прямой `set_flag` остаётся для restore/debug/точечного ремонта старого save.
- Старые Resources без `requiresObjectiveIds` нормализуются в пустой список и работают как прежде. Save v1 по-прежнему хранит только typed flags.

### I3.6 — quest-bound world marker

`EmberInteract` больше не перегружает `script_id` двумя значениями. Для `quest_marker` поле `quest_id` является ссылкой на описание задания; status key берётся через `EmberQuestCatalog.status_flag_id_for()`, а status/icon являются pure projection текущих `EmberExploreState.flags`. `script_id` снова везде означает только исполняемый dialogue/action document.

- Inspector показывает выбранное задание, derived status flag и отдельную цепочку объекта.
- `Цель / событие` создаёт/открывает эту цепочку и фильтрует start/objective/complete по связанному quest. Если marker ещё не связан, выбранный event передаёт editor-only `_editorQuestId`; единый `save_chain()` удаляет transient key до записи и одной Undo/Redo operation сохраняет `quest_id + script_id + Action Resource`.
- Quest editor сохраняет Resource и `quest_id`; legacy status flag удаляется из `script_id`, но существующий настоящий action document сохраняется.
- Legacy marker без `quest_id` продолжает находить Quest по прежнему `script_id=statusFlagId` и action по bound region. Первый Inspector save переводит его на новый контракт.
- Save v1, Quest Resource и Action Resource не получили нового runtime state или editor-layout поля.

### I3.7 — event-aware world marker

World marker не повторяет общий статус задания на каждом связанном объекте. `EmberQuestState.marker_projection()` сопоставляет уже сохранённые `set_flag` шаги цепочки с `statusFlagId` и `objective.flagId`, поэтому роль является производной: start, конкретная objective, complete либо совместимый summary fallback.

- Start виден только до принятия. Objective скрыта до начала задания, пока заблокирована dependencies, и после собственного completion. Complete виден только когда все обязательные цели готовы, затем исчезает после явного done.
- Последняя доступная обязательная objective использует done/check presentation, потому что её активация завершит обязательный набор. Все остальные текущие цели используют active/compass.
- Runtime той же projection ограничивает не только Sprite3D, но и F/enter actionability: скрытую будущую цель нельзя активировать обходным путём.
- Inspector показывает роль и fresh-save visibility; цепочка без события выбранного задания получает warning и остаётся на summary fallback для старых декоративных markers.
- Нового marker-role поля, quest key, save state или action type нет. Стандартные quest icon IDs динамические; custom icon ID остаётся явным override.

### I3.8 — guided Interact modifier

Одна плоская форма больше не смешивает частые поля с launch-rule и fallback деталями. `EmberInteractEditor` остаётся проекцией прежнего `EmberSceneAuthoring.INTERACT_FIELDS`, но организует их по авторскому намерению.

- Русские названия типов и catalog options показывают `nameRu · stable_id`; metadata OptionButton по-прежнему хранит только canonical ID.
- Read-only блок `РЕЗУЛЬТАТ В ИГРЕ` объясняет текущую комбинацию `activation → action/destination` до Save.
- Основные поля зависят от типа. `Дополнительно` скрывает condition/fallback/one-shot и quest fallback/custom icon; существующие технические значения автоматически раскрывают блок, поэтому данные не становятся невидимой ловушкой.
- Для quest-marker подсказка прямо говорит, что роль и stock icon выводятся из события цепочки. Карточка сначала показывает вычисленные роль/состояние/иконку, затем редкие fallback и auto save-key.
- Кнопки authoring используют `HFlowContainer`, поэтому узкий Inspector переносит их вместо обрезания. Названия отражают разные owners: настройки scene Interact, action document, Quest Resource и quest-event preset.
- `chest` доступен только при редактировании уже импортированного chest Interact. Новый пустой shell создать нельзя: loot/state остаются владельцем map region.

Нового editor state в `.tscn`, новой interaction schema и второго runtime router нет.

### I3.9 — объединённый Quest Flow без вложенного runtime-графа

Quest-нода не владеет копиями диалогов, action chains или сценовых объектов. Вместо этого `EmberQuestUsageIndex` строит editor-only обратный индекс по уже существующим `set_flag` writers.

- Фиолетовая read-only нода означает конкретный шаг action chain, dialogue `set_flag` либо `choice.setFlags`, который меняет status/цель открытого задания.
- Провод source → quest/objective вычисляется по `statusFlagId` и `objective.flagId`; он не сериализуется и не редактируется как dependency.
- Кнопка source-ноды открывает canonical action/dialogue document в той же вкладке. Изменение выполняется его собственным editor и Undo/Redo owner.
- Производные ноды не попадают в `QuestResource.editorLayout`; Quest сохраняет только корень и цели. Нового executor, события, NodePath или save state нет.
- Source-карточка остаётся компактной независимо от длины ID: короткий заголовок и ellipsis показываются на canvas, полный title/flag доступен в tooltip. Правая property-колонка не пересчитывает split по выбранному имени.
- Вычисляемую source-ноду можно двигать как остальные. Её позиция хранится только в session view-state; фильтр quest layout не допускает `action:*`/`dialogue:*` ключи в Resource.
- Масштабируемый следующий срез — добавить в тот же индекс scene-owned `EmberInteract`/`Area3D` backlinks и затем drag-to-bind, который создаёт либо меняет canonical action step одной Undo operation. Это будет authoring shortcut, а не перенос объекта внутрь Quest Resource.

Так автор получает ComfyUI-подобную общую картину, но документы остаются независимыми: один диалог может обслуживать несколько заданий, цепочка переиспользоваться несколькими объектами, а удаление визуальной проекции ничего не удаляет из контента.

### I3.10 — backlinks открытой сцены

`EmberQuestUsageIndex.scene_entries()` обходит только текущий edited scene root и находит scene-owned `EmberInteract`, чей `resolved_action_script_id()` запускает показанный action/dialogue writer.

- Зелёная нода представляет authoring owner: voxel prop либо самостоятельный trigger `Area3D`.
- Один объект может вести к нескольким фиолетовым событиям одной цепочки; это честно показывает, что одно F-взаимодействие способно начать задание и выполнить цель.
- `Выбрать в сцене` передаёт относительный NodePath плагину, который повторно разрешает его в текущем root, выбирает owner через штатный `EditorSelection` и открывает 3D.
- Scene backlinks пересчитываются при смене открытой сцены/Refresh и остаются session-only. Они не добавляют NodePath в Quest Resource и не владеют action document.
- Следующий отдельный срез — guided bind выбранного scene object к выбранной quest objective. Он обязан сохранить/создать canonical Action Resource и Interact одной существующей Editor Undo operation; простой визуальный провод не является gameplay mutation.

### I3.11 — guided bind объекта к событию задания

Quest Flow использует текущий `EditorSelection` как явный authoring target. Корневая нода предлагает `Старт` и `Завершение`, objective-нода — `Выполнение`; кнопка доступна только для выбранного voxel-prop либо standalone `EmberInteract` текущей сцены.

- `quest://...` остаётся editor-only token и через единственный `EmberQuestStore.action_for_event()` превращается в существующий `set_flag`.
- `EmberObjectInspectorActions.bind_quest_event()` создаёт или дополняет canonical action document, затем делегирует прежним `save_chain()` / `save_standalone_chain()`. Resource snapshot и scene fields входят в одну Editor Undo/Redo operation.
- Если voxel-prop ещё не имеет Interact, создаётся scene-owned `quest_marker` с `quest_id` и `script_id`; это сразу включает общую dynamic marker projection. Существующий talk/shop/trigger не преобразуется и не теряет свою семантику.
- Повторное назначение одинакового flag/value не создаёт дубль. Если цепочка заканчивается терминальным `change_map`, событие вставляется перед ним.
- После do/undo/redo общий mutation owner отправляет refresh, поэтому зелёные backlinks пересчитываются. Ни выбранный NodePath, ни визуальный провод не становятся gameplay data.
- Bind использует текущий валидированный Quest Flow draft, а не только сохранённый catalog document. `action_for_event_in_document()` остаётся тем же compiler boundary; optional Quest snapshot добавляется в ту же Undo operation, что Action Resource и scene fields. После commit граф перечитывает сохранённый Resource и считает draft чистым.

Этот guided bind остаётся единственным mutation owner. Добавленный в v1.62 drag является только вторым жестом над тем же методом, а не отдельным writer.

### I3.12 — зелёный drag-to-bind

Текущий выбранный scene owner, если он ещё не представлен backlink-нодой, получает session-only зелёную candidate-ноду. У неё один output; quest root имеет раздельные input `начать`/`завершить`, каждая objective — input `выполнить`.

- Graph connection request не сохраняет визуальный провод. Он выбирает `quest://` token и вызывает тот же `quest_event_bind_requested`, что кнопка v1.60.
- После canonical commit индекс перестраивается, candidate исчезает, а автор видит фактический путь `scene object → action/dialogue writer → quest target`.
- Уже существующая зелёная scene-нода также может быть source для drag, используя свой `owner_path`; selection path остаётся editor-only.
- Candidate draggable, её session position защищена тем же layout filter и не попадает в Quest Resource.
- Не удалять кнопки bind: они нужны для клавиатуры, узкого viewport и однозначной альтернативы drag.

### I3.13 — очистка осиротевших quest-событий

Удалённый `EmberInteract` не является владельцем переиспользуемого Action Resource, поэтому Quest Flow может обнаружить фиолетовый writer без зелёного объекта открытой сцены. Такая нода теперь явно помечается действием `Удалить лишнее`.

- Кнопка доступна только action writer без backlinks открытой сцены. Если цепочка ещё назначена объекту, автор сначала выбирает объект и использует прежнее безопасное `Отвязать` с copy-on-write.
- Удаляется только точный `set_flag`, сверенный по `writerIndex + flag/value`. Остальные шаги цепочки сохраняются; полностью опустевший Action Resource удаляется.
- Изменение выполняет `EmberObjectInspectorActions.remove_unbound_quest_event()` через общий Editor Undo/Redo. Do/undo/redo пересчитывают Quest Flow; Quest Resource, scene NodePath и runtime schema не меняются.
- Dialogue writer по-прежнему удаляется только внутри Dialogue Graph, поскольку одна ветка может иметь несколько потребителей.
- `Открыть` и `Удалить лишнее` находятся в одной компактной строке, чтобы служебная карточка не разрасталась по высоте.
