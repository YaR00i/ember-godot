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
- native `EmberVoxelModelResource` в `content/voxel_models/*.tres` владеет формой,
  палитрой и asset metadata; старые `.vox/.json` — исторический import input;
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

- `Asset` — resolved source: native Godot Resource редактируется в мастерской;
  `.vox/.json` показываются только как исторический legacy input до retirement;
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

Действующая map/region граница (2026-10-10): список берётся из native scene
dependencies, точки входа — из сохранённого SceneState `.tscn`, без JOI map JSON.
Inspector target map/region проверяет сохранённые данные, а локальный trigger —
текущий MapLoader, включая несохранённые и вложенные регионы. Один runtime
`find_region` обслуживает binding и spawn. Список карт не загружает меши всей
библиотеки; схема сохранённых регионов появляется при выборе точки входа и не
изображает рельеф. Ручной picker/Save/Reopen/Undo gate пока открыт.

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
- `EmberVnAssets` читает native Resources и импортирует изображения по I2.26/I2.28, не создаёт второй каталог; missing path остаётся видимой диагностикой.
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

По прямому запросу владельца новый фон больше не авторится через JOI `arts/registry.json`. `EmberVnBackground` — один `.tres` на ассет с устойчивым ID, display name, `res://` image path, kind и tags; изображение хранится отдельно в `res://assets/vn_backgrounds/`. `EmberVnAssets` читает только native Resources; старые arts/portrait registries и relative JOI paths удалены. UI не получает второго resolver: picker и live preview используют тот же каталог. Импорт через FileDialog копирует файл и создаёт Resource, выбор ID участвует в local draft Undo/Redo, но отмена не удаляет общий library asset. Dialogue documents native-only по I2.29; asset lookup также native-only. Два исходных фона сохранены, historical арты не импортировались.

### I2.27 — inherited scene background

`defaultBgArtId` становится явным authored default, а `bgArtId` ноды — только optional override. Новый контент не дублирует ID по всем dialogue/choice. Пустой или отсутствующий override одинаково разрешается через общий `EmberVnSceneState`; node picker показывает effective inherited asset. Миграция `inherit_scene_background` является pure lossless operation в существующем graph model и удаляет только per-node `bgArtId`. Кнопка выполняет её одной local Undo/Redo записью до canonical Save. Отдельный фон ноды остаётся доступен для реальной смены локации внутри сцены.

### I2.28 — VN layer contract и Godot-native portraits

Preview использует фиксированные semantic layers: background ниже stage, actor `z` ограничен actor-layer, dialogue panel выше всех портретов. Это presentation contract, а не новое поле сцены. Для ассетов `EmberVnPortrait` хранит один native `speaker_id + portrait_key + image_path` Resource на эмоцию; изображения лежат в `res://assets/vn_portraits/<speaker>/`. `EmberVnAssets` остаётся единственным resolver и читает native `.tres/remap`; старый portrait registry больше не используется, missing saved IDs сохраняются в picker как предупреждения. Импорт `+ Арт` создаёт общий library asset, а выбор эмоции меняет прежнюю строку `portraitKey` одной draft Undo/Redo operation.

### I2.29 — Godot-native dialogue documents

`EmberDialogueCatalog` — единственный native-only owner editor/runtime/pickers: `EmberDialogueResource` в `res://content/dialogues/`, без JOI scenes/<id>.json. Resource lossless хранит прежний graph Dictionary с steps/edges/stage/layout/неизвестными полями; native/remap lookup и IDs проверены в binary PCK.

Ember Graph показывает native owner/source; obsolete migration UI/forwarding удалены. Create/save/delete и Undo/Redo работают только с Resource, snapshot содержит ID/native document. Старые snapshot legacy/legacy_text поля не читаются и не записываются. Исторические диалоги не импортировались. Card projection/typed choice/convergence и защита complex stage document сохранены; Graph authoring и VN asset rendering остаются прежними owners. Tests выполняются через run_story_tests.py, ручной UI/VN render gate OPEN.

### I2.30 — Godot-native action-chain documents

`EmberActionCatalog` — единственный native-only resolver editor/runtime/script picker. `EmberActionResource` lossless хранит прежний action Dictionary в `res://content/action_scripts/`; JOI scripts/<id>.json не читается. Action schema/executor не менялись; missing IDs не получают fallback.

Ember Graph показывает native owner и сохраняет через общий Store/EmberObjectInspectorActions. Snapshot ID/native; Save/delete/Undo/Redo не трогают legacy JSON и не раскрывают его после Undo create. Scene-owned Interact binding, quest copy-on-write/orphan removal и их общая Undo transaction сохранены. Create/edit/Queue/card/binding gates проверяются на нейтральных native fixtures через run_story_tests.py; исторические action Resources не переносились.

### I2.31 — Godot-native shop documents

`EmberShopCatalog` — единственная native-only граница editor/runtime: `res://content/shops/<id>.tres`, Resource/remap lookup и native IDs. JOI shops/catalog.json больше не читается, missing IDs не получают fallback. Listing schema и владельцы экономики/сохранений сохранены. Исторический native village_kiosk пока остаётся с retired сценами; импорт других старых магазинов не выполнялся.

`EmberShopEditor` встроен в canonical шаг `open_shop`: название, item picker, buy/sell price, finite/infinite stock, reorder и delete. Legacy migration UI и forwarding удалены. `EmberObjectInspectorActions` проводит create/save одной Editor Undo/Redo operation; snapshot содержит native document, Undo создания удаляет Resource и не раскрывает fallback. Cancel не пишет draft. `test_shop_resource.gd` и `test_shop_persistence.gd` запускаются через `python tools/run_shop_tests.py` в guarded disposable проекте: UI/create/edit/reorder/delete/discard/validation/Undo/Redo, runtime prices, buy/sell/finite/infinite stock/save reopen, missing/poisoned JSON и binary PCK. Ручной UI/Forward+ gate OPEN.

### I2.32 — Godot-native item documents

`EmberItemCatalog` — единый native-only resolver для shop, inventory, equipment, consumable, economy и иконок. `EmberItemResource` lossless хранит прежний item Dictionary в `res://content/items/<id>.tres`; `EmberItemIconResource` хранит прежний pixel Dictionary (palette + rows) в `res://content/item_icons/<id>.tres`. Сейчас доступны семь актуальных items и шесть используемых icons; old items/catalog.json не читается. Resource/remap lookup и enumeration проверены в binary PCK.

`EmberItemEditor` вложен в строку `EmberShopEditor` и редактирует существующие поля без новой schema: identity/name, kind/slot/rarity/stack/useIn/iconId, atk/def/hpRestore, sell rules, tags и notes. Все предметы native; legacy migration UI и forwarding удалены. Create/save проходят через общий `EmberObjectInspectorActions` и Editor Undo/Redo, Cancel не записывает данные. `test_item_resource.gd` запускается только через `python tools/run_item_resource_test.py` в guarded disposable проекте: create/edit/Undo/Redo/reopen, validation, runtime/economy, missing/poisoned JSON и неизменность shared source SHA.

### I2.33 — shared visual ID library

`EmberVisualLibraryPicker` является общей плиточной проекцией canonical catalogs, а не новым owner. Первый срез использует `EmberItemVisuals`: native icon Resource с прежним `palette + rows` декодируется в nearest-neighbor preview, item editor выбирает `iconId`, а shop listing выбирает `itemId` из одного searchable `ItemList`. Compact OptionButton сохраняется как fallback; изображения не добавляются в его PopupMenu из-за прежнего native-crash Godot 4.7.2. Контракт и очередность VN/voxel/map адаптеров описаны в `docs/EMBER_VISUAL_LIBRARY_DESIGN.md`; `test_visual_library.gd` закрепляет image decode, stable IDs и editor projection.

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

### I3.14 — workflow автора квестов · исследование28.10

Статус: первый UI-срез и назначение разговора цели реализованы28.10,
ручная приёмка удобства OPEN; полный
конструктор типов целей не реализован. Основание — автор прошёл «Послание на берегу» и запросил путь
«Создать квест → источник старта → цели/связи → проверка» без ручной технической сборки.

Текущее доказательство: QuestEditor требует ID/save keys/зависимости строками;
Graph уже проецирует QuestResource objectives, умеет dependency wires, guided
bind/drag-to-bind и scene/action/dialogue backlinks(I3.3–I3.13). Добавление цели
автоматически создаёт ID/flag; поддерживаются flag, combat counter, покупка и сбор со сдачей (I3.15).
QuestStore.normalized_document сохраняет эти два режима; готовых authoring-типов
«иметь предмет», «купить», «поговорить с конкретным NPC» сейчас нет. NPC-stage
mapping, содержимое бутылки, чтение, доступность ракушек, обмен и combat result
для береговой миссии соединялись вручную у своих владельцев. Рабочее прохождение
не доказывает удобство самостоятельной сборки пользователем. Первый срез Graph
просмотрен в нативном Forward+; оценка мыши/удобства остаётся за автором.

Рекомендация: единое место «Квесты» с согласованными представлениями «Этапы» и
прежняя «Схема». Обычная цепочка добавляется «+ Следующая цель» с автоматической
связью; Graph нужен для обзора, параллельных целей/развилок. Карта выбирает объект
или область, схема показывает логику — это разные значения «точки».

Предлагаемый маршрут:
1. Создать: имя/описание; технические имена генерируются и живут в «Дополнительно».
2. Источник старта: выбрать в сцене NPC/объект/область либо предмет/событие из
   библиотеки. Указать **когда**: подобрать, открыть, прочитать, закончить разговор,
   войти в область. У бутылки «прочитать письмо» отличается от «подобрать бутылку»;
   текущий guided scene bind не закрывает authoring Inventory.useScriptId автоматически.
3. Карточка цели: вид действия, цель из picker/карты, количество, текст игроку;
   «При открытии»/«При выполнении» сворачивают spawn/dialogue/reward из прежних owners.
4. «Дальше» связывает последовательность. Для объединения веток явно показать
   «Все»/«Любая», взаимный выбор — отдельное правило. Текущая requiresObjectiveIds
   поддерживает ожидание всех; альтернативы требуют отдельного runtime решения,
   их нельзя обозначать только картинкой проводов.
5. При выборе NPC показать его реплики для состояний: до просьбы, цель в работе,
   можно сдать, после сдачи. Один NPC переиспользуется несколькими этапами; текущий
   QuestGiver.objective_scripts mapping нуждается в понятной форме, а не новом owner.
6. «Проверить» показывает отсутствующий target/диалог/событие/недостижимую цель и
   открывает место ошибки. «Тест сначала/с этапа» использует изолированный прогресс,
   показывает активные/закрытые цели и причину ожидания; не меняет реальные saves.

Семантика перед typed presets:
- «Иметь3 ракушки» читает актуальную сумку; «собрать3 после принятия» считает
  события получения; «передать3» выполняет существующий атомарный exchange.
  Нужно явно выбрать, засчитывать ли уже имеющиеся предметы и расходуются ли они.
- «Купить» проверяет покупку у нужного продавца, а не наличие похожего предмета;
  «победить» слушает committed combat result, «поговорить» — нужный исход диалога.
- Связи/переходы зависят от событий состояния, а не от опроса всей карты каждый кадр.
  Индексы используются для поиска/проверки; сами модели/бойцы/сумка не копируются в Quest.
- Каждый preset встраивается в существующий Resource/Store/Action/сценовый binding
  и общий mutation owner. Если нужное условие не выражается прежней схемой, обосновать
  конкретное расширение и провести validation/UI/runtime/save вертикально. Второй
  quest executor/дублирующие счётчики поверх инвентаря не вводить.

Внешние первичные ориентиры:
- [articy:draft Flow](https://articy.com/help/adx/Flow_WhatsThis.html) и
  [Flow fragments](https://articy.com/help/adx/Flow_Objects_FlowFragment.html):
  этапы со связями, вложенные подробности, создание следующей карточки из провода.
  Для Ember — компактный обзор и переход к прежнему диалогу/действию из карточки.
- [Questify, авторский репозиторий](https://github.com/TheWalruzz/godot-questify):
  Godot-редактор Start/Objective/End, отдельные условия и Any/Exclusive ветви.
  Для Ember — читаемые типы и семантика соединений. Его singleton/save и polling
  не предлагаются для переноса: действующие owners остаются у Ember.
- [Quest Machine, руководство](https://www.pixelcrushers.com/quest_machine/Quest_Machine_Manual.pdf):
  доступные индексированные выдержки подтверждают counter/message/parent conditions;
  прямое чтение PDF вернуло403, полный обзор продукта не выполнен. Выводы выше
  достаточны по articy/Questify; установка/покупка зависимостей не предлагаются.

Проверенная проба Questify: внешний checkout
`C:/Users/novos/Documents/Codex/2026-10-28/quest-workflow/questify-lab`,
revision `a102ab1bd4f0ee4280d5370d9aab2b49f8843325`, MIT. Изолированный editor/import
и нативный Forward+ граф Start→Objective→End с save/reopen PASS. Изучены
quest_editor_view/quest_graph_editor/graph_nodes и граница quest_manager;
в Ember плагин не устанавливался, его runtime/данные/код не переносились.
Внешние доказательства — рядом `questify-native.png`, `questify-native.log`.

Первый полезный срез поверх прежнего `ember_graph_workspace.gd`:
- Ember Graph → Задания → «+ Задание»: прежний черновик с автоматическими ID.
- Каждая карточка: «+ Следующая цель» добавляет цель с requiresObjectiveIds
  текущей цели одним шагом истории и сразу открывает новую карточку.
  «+ Отдельная цель» сохраняет возможность независимых/параллельных целей.
- ID/status/flag свёрнуты в «Дополнительно»; названия карточек и зависимости
  читаемые. Справа — переходы к началу/завершению и целям, прежняя полная
  read-only форма скрыта за отдельным техническим обзором.
- Привязка выбранного сценового объекта к старту/цели/завершению остаётся у
  прежнего guided bind owner(I3.11). Типы целей пока только событие и боевой счётчик.
- `test_quest_graph_workflow.gd`: Next→Next, видимость новой карточки из focus,
  Undo/Redo, раскрытие ключей, save/reopen, validation и discard PASS в нативном
  Forward+; runner — `run_mixed_editor_tests.py --test test_quest_graph_workflow.gd`.
  Кадр/лог: `C:/Users/novos/Documents/Codex/2026-10-28/quest-workflow/ember-native.*`.
  Общие graph/action-chain проверки красные только на ожиданиях числа таблиц
  добычи/восьми типов действий; эти соседние ожидания не исправлялись данным срезом.

Настройка «Поговорить с NPC» в карточке событийной цели:
- Выбор существующего диалога, переход к его редактору, назначение выбранному
  квестовому собеседнику. Можно выбрать сам Talk либо родительский NPC/его облик.
  Начальная поддержка — прежний `ember_quest_giver_interact.gd`, один quest_id
  у NPC; другой квест не переназначается автоматически. Обычный EmberInteract
  не преобразуется в квестового собеседника; для своего NPC есть отдельное создание ниже.
- `EmberObjectInspectorModel.quest_conversation_target` разрешает выбранный узел;
  `EmberObjectInspectorActions.bind_quest_conversation` одним Undo сохраняет
  Quest/Action и objective_scripts. Прежние QuestGiver/Action/Dialogue остаются
  владельцами выполнения; новый тип данных цели/счётчик не добавлен.
- Цепочка: talk → прежний set_flag. Закрытие незаконченного диалога не выполняет
  цель; успешное окончание открывает следующий этап по requiresObjectiveIds.
  По умолчанию подходит любой нормальный конец; режим конкретного ответа теперь
  настраивается в этой же карточке, как описано ниже.
- Изменённый разговор получает частную цепочку, старый Resource/другие потребители
  сохраняются. Назначенный без изменений разговор переиспользует цепочку.
  Снятие назначения через backlink меняет только objective_scripts и отменяется.
  Индекс/проверка очистки учитывают поэтапные ссылки NPC; используемая цепочка
  не удаляется как осиротевшая. Generic set_flag binding к такому NPC блокируется:
  его runtime читает objective_scripts, а не общий script_id.
- QuestGiver помечен @tool для обновления в редакторе через прежний Interact owner.
  Authored main/миссия/реплики не менялись. Возможность подключена к существующему
  Ember Graph и выбору NPC основной карты; новый fixture не становится рабочей картой.
- Focused `test_quest_graph_workflow.gd` в Forward+ PASS: picker/назначение из UI,
  два этапа одного NPC, показ после окончания/отмена без зачёта, сохранение/открытие
  сцены, Undo/Redo, backlink/unbind/Undo, запрет очистки используемой цепочки,
  запрет другого quest_id/неизвестного диалога и сохранение общего старого Action
  при замене. Прежние Next/save/discard/validation также PASS.
  Изолированная parse-проверка plugin.gd PASS с нужной grass-texture dependency;
  это не полная интерактивная проверка редактора. Кадр/лог — прежняя внешняя папка.

Создание своего собеседника из цели:
- Поле имени и «+ Создать собеседника на карте» используют выбранный диалог.
  Копируется временный shore_keeper с очищенными quest/routes/completed_script_id,
  исходный хранитель/принятая миссия не меняются. Новый локальный NPC получает
  уникальное имя узла, отображаемое имя, Visual/body/дистанцию F и маршрут цели.
- Plugin выбирает место рядом с выбранным объектом, иначе player_start.
  `EmberSceneAuthoring.quest_npc_position` использует map.surface_floor_sample —
  прежнюю поверхность игрока/AI; вода или отсутствие земли останавливают создание.
  Это ближайшая точка со смещением на блок, не интерактивное размещение курсором.
- `EmberObjectInspectorActions.create_quest_conversation` использует тот же
  bind_quest_conversation и одну запись Undo для NPC + Quest + Action. Сцена
  помечается изменённой, объект выбирается; Ctrl+S сохраняет .tscn. Ресурсы
  задания/действия записываются при создании, как у прежнего guided bind.
  Очистка истории оставляет добавленного NPC; незавершённое создание не оставляет
  узел при ошибке. Вложенная Visual-сцена сохраняет прежнего владельца.
- Focused native Forward+ PASS: создание через кнопку из нового черновика,
  имя/облик/коллизия/маршрут, один Undo удаляет новый NPC/Quest/Action,
  Redo возвращает их, save/reopen сохраняет вид/позицию/привязку, разговор
  выполняет цель. Отдельно query-checks высоты поверхности/воды/отсутствия земли;
  это контролируемый floor fixture, не ручное размещение на полной main.
  Проверена сохранность NPC после clear_history (найденная ошибка reference
  исправлена). Нативные UI/3D кадры — `ember-native.png`, `ember-native-npc.png`
  в прежней внешней папке; 3D кадр — проверочный fixture, не новая рабочая карта.
  Plugin parse PASS в изолированном checkout/cache.

Ручной gate: на открытой main создать своего NPC/диалог цели, Ctrl+S → reopen/F5,
оценить размещение/подсказку/F, Undo/Redo в реальном редакторе. Настройка передачи
предметов добавлена ниже; следующие срезы — I3.15. Самостоятельная сборка всей
береговой цепочки без технических ключей ещё OPEN; принятая миссия от этого не меняет статус.

Передача предметов NPC из той же карточки:
- «Передать предметы после разговора» → предмет по названию и количество1–999.
  Применяется и к выбранному NPC, и при создании нового. В компактном обзоре
  подробности открываются кнопкой «Разговор / передача NPC», а не накладываются
  длинными формами друг на друга.
- Прежний bind owner составляет talk → exchange_items(costs, rewards={}) →
  set_flag цели. Расход/проверка сумки остаются у EmberExploreState.exchange_items,
  прохождение — у QuestCatalog. Уже имеющиеся предметы подходят; это не счётчик
  новых находок после принятия задания. Цель не хранит копию сумки/условий.
- Первый UI настраивает один вид предмета. Существующий список нескольких costs
  сохраняется целиком и редактируется в прежней цепочке; форма не сокращает его
  до одного предмета при назначении разговора. Награды/торг здесь
  не конструируются — это следующие конкретные сценарии, не скрытая новая схема.
- После сохранения настройки восстанавливаются из Action, не из UI-сессии.
  Передача назначается одной Undo-записью, исходная цепочка остаётся отдельной.
  Targeted headless/native Forward+ PASS: UI→3 ракушки, две в сумке не списываются
  и не выполняют цель, отмена разговора оставляет4, успешная сдача оставляет1,
  повторное взаимодействие не списывает снова, Undo/Redo/reopen восстанавливают
  назначение/поля. Прежние разговор/создание NPC/save/discard проверки также PASS.
  Ручная оценка этой формы на main OPEN; принятые authored квест/карта не менялись.

Конкретный ответ диалога:
- В подробной карточке разговора поле «Засчитать» предлагает любой конец либо
  реальные ответы выбранного диалога (сначала текст ответа, затем вопрос).
  Настройка работает и для существующего NPC, и при создании нового. Поля создания
  NPC свёрнуты, когда выбран существующий собеседник.
- `DialogueGraphModel.quest_choice_options/with_quest_choice_outcome` используют
  существующий option.setFlags. Выбранный ответ записывает true, другие ответы
  того же выбора false — при возврате в этот выбор последнее решение побеждает.
  Прежние флаги других правил/полный граф сохраняются. Явный set_flag той же цели
  в автоматическом шаге отвергается этим preset: его нельзя безопасно переписать
  незаметно. Автор может редактировать такой сложный случай в Dialogue Graph.
- `bind_quest_conversation` создаёт частный Dialogue Resource и talk-only Action;
  безусловный set_flag после разговора отсутствует. Исходный общий диалог/старый
  Action не изменяются. Новый Dialogue + Action + Quest + NPC routing входят в
  одну Undo-запись. Настройка выводится из сохранённых writers; отдельные UI поля
  или второй исполнитель в QuestResource не добавлены.
- Результат применяется штатным InteractionUI после завершения диалога. Закрытие
  до конца не засчитывает даже уже выбранное согласие; отказ оставляет цель
  невыполненной, повторный разговор допускает согласие. Это правило конкретного
  ответа, не произвольное составное условие всех возможных финальных веток.
- Совместить этот режим с безусловным exchange_items запрещено owner-валидацией;
  UI выключает передачу при выборе ответа. Принятие и передача делаются разными
  целями. Сложная условная награда/сдача по ветке требует отдельного сценария.
- QuestUsageIndex прослеживает talk из Action до Dialogue, чтобы NPC оставался
  виден как источник результата. Writers внутри диалога по-прежнему редактируются
  через Dialogue Graph, не generic удалением Action шага.
- Focused native Forward+ PASS: выбор ответа из карточки, private Source неизменён,
  отмена до окончания/отказ/согласие, возврат к выбору, посторонние authored flags,
  Undo/Redo, повторное открытие Dialogue/карточки, NPC backlink и запрет условного
  режима с безусловной сдачей. Прежние разговор/создание NPC/передача/save/discard
  также PASS; изолированный plugin parse PASS. Ручная оценка формы/диалога на main
  OPEN; автор попросил отложить ручную пробу ящика, это не принимает её автоматически.

Напоминание NPC и награда в карточке ·28.10:
- В подробной flag-цели выбор «Разговор выполняет цель» / «Только напомнить ·
  цель не меняется». Выбранный диалог назначается маршруту этого этапа NPC;
  напоминание компилируется только в talk, без set_flag/exchange_items.
- «Выдать награду после разговора» открывает прежний ItemCounts editor:
  выбор предметов/количеств, добавление и удаление нескольких строк. Награда
  компилируется в talk → exchange_items(costs,rewards) → objective set_flag.
  Можно совместить со сдачей предметов в одной атомарной exchange transaction;
  награда по конкретному ответу пока требует отдельного этапа.
- Значения читаются обратно из существующих Action/Dialogue и objective_scripts,
  новых Quest/save полей нет. Назначение/создание NPC, Quest и новый частный
  Action входят в прежний Undo/Redo; исходный общий Action не переписывается.
- Напоминание не допускает costs/rewards/choice-outcome, grant_cinders или записи
  флагов этого квеста из выбранного диалога (включая choice.setFlags). Пустая или
  невыбранная награда объясняется в карточке до сохранения.
- test_quest_npc_options в native Forward+ PASS: режим/чтение назад, две награды,
  отмена/повтор без дублирования, небезопасные сочетания/квестовый writer,
  пустая награда, shared Source/Action, Undo/Redo, scene reopen/cold save/load,
  создание нового reminder NPC. Карточки просмотрены; старый quest workflow
  с выбранным ответом/сдачей/созданием NPC и изолированный plugin parse PASS.
  Свой выбор мышью/узкое окно/DPI/main-сборка всей цепочки автором OPEN.

Свои короткие реплики и разговор после квеста ·28.10:
- «Своя короткая реплика» в подробной карточке открывает TextEdit. Существующая
  команда назначения/создания NPC компилирует текст в обычный Dialogue(line→end),
  сохраняет Dialogue+Action+Quest+маршрут одним Undo. Отдельный режим «Только
  напомнить» и награда работают с таким текстом так же, как с готовым диалогом.
- «Разговор после завершения задания» раскрывает отдельный текст и кнопку
  назначения выбранному NPC. Она меняет только его completed_script_id, а
  objective_scripts всех стадий сохраняются. Сам Action содержит только talk,
  без наград/зачёта; runtime — прежний QuestGiver по projection.status=done.
- Старые Dialogue/Action не переписываются: изменённый текст получает частную
  копию, одинаковый повтор использует прежнюю. Нельзя назначить пустую реплику;
  финальный режим не принимает costs/rewards/choice. Сложный прежний финал
  остаётся до явного назначения нового текста, короткая форма его не обрезает.
- Pure helpers — DialogueGraphModel.short_reply_document/short_reply_text.
  ObjectInspectorActions.bind_quest_conversation принимает editor-only text и
  after_completion через прежние conversation_options. ActionStore validator
  умеет принять IDs отдельно проверенных Dialogue, записываемых тем же Undo;
  отсутствующие обычные ссылки по-прежнему запрещены. Новых runtime/save полей нет.
- test_quest_authoring_journey native Forward+ PASS: своя реплика/создание NPC,
  пустой текст не создаёт объект, свои напоминания/награда, финальная реплика,
  COW/повтор без лишнего Resource, Undo/Redo всех новых записей, scene reopen,
  прохождение/F/зона/награда, отмена/повтор финала и cold save/load. Старый
  quest workflow (выбор ответа/передача/создание NPC/discard) и plugin parse PASS.
  Карточка просмотрена на малом fixture15FPS; полный main/GPU benchmark не шёл.
  Ручные main/мышь/узкое окно/DPI OPEN, production карту/оптимизацию не меняли.

Неназначенные настройки разговора · исправление28.10:
- Воспроизведено стирание обеих новых реплик при выборе объекта/NPC: selection
  перерисовывал карточку из Resources, а поля ещё не были назначены. Теперь
  GraphWorkspace держит editor-only черновики формы по цели и общей финальной
  реплики по квесту. Они переживают выбор адресата, обновление и переход по целям.
- Сохраняются также режим, диалог/исход, сдача/награда, количества и имя создаваемого
  NPC: реплика не превращается из напоминания в выполнение при перерисовке.
  Выбранный NPC показывается в карточке; назначение остаётся явной кнопкой.
- Успешный ack назначения удаляет только назначенную часть; остальные цели и
  финальный текст остаются черновиками. Ошибка назначения не очищает ввод.
  Plugin передаёт conversation_saved только из двух обработчиков разговоров;
  создание зоны/прочие сохранения не принимают за сохранение текста.
- Переход к другому квесту/диалогу и Reload используют прежнее предупреждение
  discard. Отмена сохраняет ввод; подтверждение убирает только черновики.
  «Сбросить неназначенные настройки» возвращает текущую форму/финал к сохранённому
  NPC. Save Quest при таком вводе просит сначала назначить или сбросить его.
- Черновик живёт в текущей сессии, не в Quest Resource/save; это не дисковый
  автосейв. Перед закрытием редактора: «Назначить» → Ctrl+S сцены.
- test_quest_conversation_draft native Forward+15FPS PASS: оба текста/режим/
  награда при смене selection/целей, отсутствие Resource/NPC мутации до назначения,
  блокировка ложного Save, cancel/discard/reset, сохранение других черновиков.
  Цельная цепочка/Undo/Redo/reopen/cold load, прежний quest workflow и NPC options
  PASS; plugin parse PASS. Карточка просмотрена, свой main/мышь/DPI OPEN.
  Изменение ограничено Graph/form setter/двумя conversation ack; код оптимизации
  и основная карта не менялись.

Сборка первой цепочки из карточек ·28.10:

1. Открыть landscape_compact → Ember Graph → «Задания» → «+ Задание».
   Ввести своё название и текст первой цели «Поговорить со смотрителем».
2. Трижды «+ Следующая цель»: «Найти груз», «Поставить ящик на площадку»,
   «Забрать награду». Порядок и служебные ключи создаются автоматически.
3. Открыть первую цель справа → «Разговор / напоминание / награда» → выбрать
   «Груз у берега · просьба» либо включить «Своя короткая реплика» и написать
   свой текст. Развернуть «Новый собеседник», ввести имя и
   «+ Создать собеседника на карте». Это свой NPC, не прежний Хранитель берега.
4. Во второй цели «+ Место, до которого нужно дойти». Поставить/размерить зону
   у будущего ящика. Снова выбрать своего NPC в сцене, открыть эту цель,
   выбрать «Груз у берега · напоминание» или свой текст → «Только напомнить» →
   «Назначить…».
5. В третьей цели «+ Ящик и отмеченная зона». Расставить их на сухой поверхности.
   После создания снова выбрать NPC и назначить ему то же напоминание этой цели.
6. В четвёртой цели выбрать «Груз у берега · награда» или свой текст, оставить «Разговор
   выполняет цель», включить «Выдать награду», добавить «Монета» количеством3
   и нажать «Назначить награду NPC».
7. У выбранного NPC раскрыть «Разговор после завершения задания», написать
   благодарность и нажать «Назначить финальную реплику NPC». Это реплика после
   всего задания, не ещё одна цель и не повторная награда.
8. Ctrl+S сохраняет сцену. Переоткрыть её/F5: разговор → вход к грузу → F взять /
   F поставить на площадку → дождаться остановки → вернуться за наградой.
   Q показывает этап; повтор не должен выдавать ещё3 монеты.

Границы этой инструкции: короткие тексты создаются здесь, готовые диалоги можно
брать из библиотеки. Разговоры с выбором/сложной постановкой редактируются прежним
Dialogue Graph. Режимы/reminder/rewards относятся к flag-целям. Расстановка/gizmo
и мышь проверяются автором; создание нового диалога не заменяет ручную расстановку.

Техническое доказательство сборки: test_quest_authoring_journey PASS Forward+ в
disposable fixture. Название/тексты вводятся в поля Graph,3 зависимости создаются
«Следующая цель», NPC/зона/ящик/два напоминания/награда/финальная реплика назначаются
его controls, тексты вводятся без заготовленных диалогов.
Quest ID/flags/маршруты вручную не задаются. Сохранённая сцена после reopen проходит
настоящие Player/Area3D/F/settle/Dialogue/Quest owners до награды; Undo/Redo последней
привязки сохраняют остальные стадии. Это API-сигналы controls, не проверка мыши.
Размещение в fixture фиксировано вместо map-placement plugin; его прежние checks
сохраняются. Полная main и замеры GPU не запускались; только малая UI-проба15FPS.
Реплики «Груз у берега» получили разные названия в picker; IDs и содержание прежние.

### I3.15 — семейства целей, состояния мира и постановка · план28.10

#### Ящик и грузовая плита в бою05.11

После совместной заслонки в приливной пещере слева находится площадка
«Кабан за заслонкой». F поднимает прочный ящик, вход в отмеченную зону
запускает FieldEncounter на месте. Стартовые клетки стоят рядом с плитой.
Команда «Опустить» предпочитает свободную соседнюю плиту, когда удерживается
мировой предмет. В остальных случаях прежний поиск клетки сохраняется.

FieldEncounter передаёт клетку двери, клетку и порог плиты из Circuit в
боевой снимок. CombatWorldItems читает массу живого опущенного ящика,
занятая дверь удерживает проход открытым. Terrain и навигация читают
одно правило; Circuit отображает его на реальной двери во время боя.
Предпросмотр не меняет сцену. Retry берёт исходный ящик и положение.
После победы маска столкновений ящика восстановлена и физическая плита
снова сама определяет состояние прохода. Боевая проекция в save не пишется.

Полевой вход снимает `fieldGeometry` по реальной физике слоя окружения.
Опора проверяется в центре и под краями капсулы; пересечение капсулы,
отсутствие опоры и перепад за допуском закрывают клетку. Между клетками
проверяются опора в середине и проход капсулы, поэтому тонкая стена или
щель закрывают переход даже между двумя свободными клетками. Тактическая
навигация, линия видимости и толчок читают закрытые переходы. Разметка
автора остаётся верхним ограничением, кроме привязанной открываемой двери.
Из физической проверки исключено только тело этой двери; её состояние
читает механизм. Снимок строится на входе и сохраняет высоту опоры для
постановки бойцов. Плавный уклон считается ходьбой, ступени и уступы
используют боевые правила высоты, прыжка и падения. Генерируемый рельеф
помечается автоматически. Отдельные коллайдеры ступеней и площадок выше
базового уровня можно отметить группой `ember_battle_walkable`.
Высота опоры ищется в пределах 24 единиц от уровня площадки. Если у
обычной встречи перекрыты стартовые места, проверяются четыре соседних
положения со сдвигом на клетку. Встреча с плитой сохраняет привязку к двери.

В той же встрече есть тяжёлый ящик на одну клетку. «Толкнуть» двигает
предмет с включённым Pushable на одну клетку от героя и использует
существующие правила препятствий и занятой клетки. Тяжёлый ящик
нельзя поднять. Плита читает собственные Required Weight и Character
Weight: стоящий на ней герой или враг даёт вес персонажа, поставленный
ящик — свою массу. В пещере порог равен весу одного бойца.

Пещерная встреча проецирует одну видимую плоскую лужу в Wet при входе:
`FieldEncounter.wet_surface_path` указывает на её меш, а клетки берутся
по центрам внутри его прямоугольного следа. Соседние сухие клетки доступны.
Мира получает «Искру» локально для этой встречи. Превью и расчёт цепи
«Искры» учитывают мокрых союзников, врагов и заклинателя на связанной области.
В этой же встрече «Холодный укол» Миры замораживает связанную лужу,
а огонь Кая возвращает воду. Лёд виден на земле после подтверждения.
Сухая кучка листьев задаёт одну клетку по позиции объекта. Кай поджигает
её отдельной командой на клетку, Мира тушит и оставляет Wet. Превью
поджога оранжевое, тушения голубое. Горящая клетка снимает 2 HP в конце
хода стоящего на ней бойца. Это временное состояние боя.

`run_chapter1_blockout_tests.py --pressure-battle` Forward+ PASS: вход из
области с тем же pickup ID, закрытый маршрут, «Опустить», проход и атака,
Retry, победа, возврат на физическую плиту и cold load. Ручная приёмка OPEN.

#### Рыбалка и походная кухня05.11

На `chapter1_coast.tscn` одна точка у кромки воды, рядом походная кухня.
F начинает заброс, удержание F подтягивает рыбу, а удержание во время
рывка отнимает прогресс. Крупная команда «СКОРО РЫВОК» сменяется
«ОТПУСТИ F», поплавок ныряет, круг расходится по поверхности. При начале
рывка один раз звучит короткий синтезированный всплеск. После
успеха или схода F сразу повторяет заброс. Esc отменяет попытку. Вступление
Миры пропускается после первого улова, включая старые сохранения. Уловы
на этой точке повторяемые, без наживки в текущей пробе.

Точка хранит в `catches` вид, относительный вес, длительность спокойной
фазы и рывка, ID бонуса и шанс. Береговая рыбка и окунь имеют разные циклы;
у окуня шанс чешуйки 45%. Рыба и бонус записываются вместе через существующий
ExploreState.exchange_items. При нехватке места попытка не даёт частичной
награды. Старый флаг улова используется для вступительной реплики. Раунд
живёт в UI до закрытия и не попадает в save.

Два рецепта на прежней походной кухне готовят оба вида. Готовое блюдо
восстанавливает 8 HP; `completion_dialogue` открывает реплику Миры после
успешного обмена. Чешуйка доступна как материал в сумке, применение в
прокачке ещё не назначено.

`run_chapter1_blockout_tests.py --fishing` Forward+ PASS: удержание,
предупреждение и штраф, сход/отмена/повтор, видовые награды, целая транзакция,
оба рецепта, реплика и cold load. Ручной темп ловли OPEN.

#### Подсказки для ориентирования05.11

У цели в обеих формах есть необязательное поле **«Куда идти»**
(`directionRu`). В Q-журнале оно показано под открытой целью. J просит
Миру повторить направление по той же текущей цели, что выбрана в HUD.
Доступно, когда Мира в отряде, управляет другой герой, есть активная цель
с направлением и игрок свободен для разговора. Подсказка закрывается F/Esc
и не меняет прогресс. Карточка HUD скрывается на время чтения журнала.

В первом дне служащий и лавочник называют реальные вывески макета, затем
Мира направляет к верстаку, а журнал и J ведут домой после сборки. Реплики
NPC остаются обычными Dialogue, направление хранится в Quest Resource
и выбирается из QuestCatalog.projection. Отдельный save key не нужен.
Forward+ маршрут дня1 проверяет смену четырёх направлений, нажатие J,
совпадение с журналом и завершение задания. Ручное ориентирование OPEN.

#### Тайник с обходом05.11

`chapter1_tide_cache.tscn` размещён в существующей приливной пещере за
совместной заслонкой. Circuit связывает плиту с решёткой, вес ящика — 3,
порог — 2.5. Прежняя Clearance защищает занятый проход. Справа есть
свободный боковой вход. WorldItem с уникальным pickup ID хранит одну
ракушку на оба маршрута, схема состояния и содержимое сумки прежние.
`run_chapter1_blockout_tests.py --tide-cache` Forward+ PASS: коллизия,
порог веса, взять/поставить, обход, F-подбор, cold load и отсутствие
повторного появления. Ручная читаемость входит в общий проход.

#### Рычаг спутника05.11

Существующий lever получает `companion_hero_id` и необязательный
`companion_completion_flag`. Поля сохраняются в snapshot и восстановлении
компонента при правке схемы. Назначение хранится только в PartyFollowers:
тот же спутник временно идёт к точке рычага, проверяет прямой подход и держит
сигнал после прибытия. Рычаг читает состояние через свой Interact. Повторное
F, смена лидера, выход из радиуса, бой или удаление рычага снимают назначение.
Для длинного обхода и перепадов высоты нужен отдельный проход навигации.

В `prefabs/items/chapter1_team_gate.tscn`: наружный рычаг и внутренний latch
через «ЛЮБОЙ» питают дверь. Сохранение пишет только внутренний рычаг и latch
по прежней схеме. Clearance не даёт двери закрыться на игроке или предмете.
Первая проба стоит в приливной пещере. Сценарий для автора — GDD →
«Контекстное разделение партии в головоломках».

`python tools/run_chapter1_blockout_tests.py --team-gate` — Forward+ PASS:
прибытие и открытие, отмена/смена лидера, свободный проход, загрузка до и после
фиксации, выход спутника из удержания. Ручное движение и читаемость OPEN.

#### Действия в мире как цели05.11 — сделано без ручной приёмки

В карточке цели Ember Graph или полной форме задания выбрать **Действие в мире**,
затем действие, предмет/рецепт и **Нужно**. Связи «После» и «+ Следующая цель»
остаются прежними; для сдачи добавить следующую разговорную цель с наградой.
Привязывать отдельный set_flag к каждому ящику/кусту для счётчика не требуется.

- **Разрушить объекты**: выбрать предмет из каталога, например квестовый ящик,
  и количество отдельных разрушений. Считается успешный WorldItem.destroy от
  удара/броска; прочный ящик и повторное воздействие на уничтоженный не считаются.
- **Разгрести кучки листьев / Скосить пучки травы**: количество интерактивных
  LeafPile/CuttableGrass. Раскрытие листьев ногами тоже считается. Обычная массовая
  GrassPatch, её виды и правило высоты этим срезом не изменялись.
- **Собрать предметы в мире**: выбрать предмет и количество единиц. Учитываются
  успешный WorldItem.pickup и BerryBush.harvest; покупки, grant/rewards, крафт и
  возврат собственных inventory drops не считаются. Сбор не списывает предметы.
  Для передачи добавить отдельную цель **Собрать и передать**.
- **Изготовить по рецепту**: выбрать Recipe Resource из `content/recipes/*.tres`
  по названию и число успешных выполнений рецепта. Это число операций, не единиц
  результата. Кухня использует тот же путь. Preview/отмена/нехватка/полная сумка
  не увеличивают прогресс.
- Считаются только active-квесты и открытые prerequisites; до принятия/открытия
  действия не копятся. Цель ограничена требуемым количеством. Один факт не
  завершает две последовательные цели, независимые открытые цели могут получить
  его вместе. Выход из зоны и расход собранного не снимают выполненный счётчик.

Owners: Quest Resource.definition сохраняет `progressMode="world_action"`,
`worldAction`, `worldTargetId`, `requiredCount`. QuestStore нормализует/валидирует,
общие `ember_quest_world_action_fields.gd` и `ember_quest_world_actions.gd` дают
селекторы/описания. Последний не исполняет цели. QuestCatalog.world_action_updates
снимком выбирает доступные цели, ExploreState пишет прежние numeric flags в той
же транзакции и autosave, что мир/сумку. HUD/журнал показывают current/required.
Схема save v2 и прежние режимы целей сохранены. Новые события исполняются прямым
вызовом State в точке commit: отдельный bus/плагин заданий не нужен. Встроенные
[Godot signals](https://docs.godotengine.org/en/stable/getting_started/step_by_step/signals.html)
остаются уведомлением уже целого состояния для UI; сигнал до commit мог бы
разделить запись цели и предмета. Это ограниченное расширение прежнего purchase-пути.

Оставшиеся границы: источник «именно эта яблоня» отдельно не фильтруется; сбор
выбирает тип предмета. Доставка проверяет конкретный pickup_id, полное попадание
BoxShape, отсутствие удержания, малую скорость и выдержку. Она не различает
перенос/толкание/бросок и закрепляется навсегда; одновременное удержание нескольких
ящиков в разных зонах — механизмы/плиты, не этот одноразовый квестовый счётчик.

Проверка: `python tools/run_quest_world_action_tests.py` — изолированный Forward+,
реальные hit/cover/pickup/harvest/craft handlers, early/locked/wrong/duplicate/stack
filters, последовательность, единый autosave, cold load, обе формы, Graph
Undo/Redo/reopen/discard. Ручной свой Quest workflow/мышь/F5 main остаётся OPEN.

#### Перенос груза между картами05.11 — сделано без ручной приёмки

Согласовано автором: с грузом в руках рядом с доступной дверью F входит вместе с
ним, в остальных местах F ставит груз. Недоступная/заблокированная дверь не забирает
приоритет. G сохраняет бросок. Цель — общий путь для будущего задания торговца;
само поручение/сдача/награда этим срезом не добавлены.

- `EmberMapTransition` перед успешным change_scene запоминает ID переносимых предметов
  и героев. Это process-local handoff, не второй persistent owner. При неудаче pending
  очищается, предмет остаётся в исходной сцене. Целевая ExploreScene после spawn через
  `ExploreState.adopt_carried_items` меняет mapId/позицию единственной записи и затем
  восстанавливает физическое тело/переносчика; прибытие сохраняется autosave.
- WorldItems v2 дополнен необязательными `physical` и `carrierHeroId` в прежней записи.
  Старые записи без полей работают. physical содержит текущие экспортируемые свойства
  WorldItem (массу, размер, carry/push/break, threshold/damage, флаги/quest, путь эффекта)
  и returnOrigin. Повреждённые дополнительные данные отбрасываются с сохранением
  базового предмета; путь эффекта ограничен prefab PackedScene. Формат второго save
  не появился, SAVE_VERSION не менялся. Arbitrary script state/содержимое контейнеров
  не сериализуются этим профилем.
- `WorldItem.capture_progress` сохраняет переносчика и профиль, при постановке/броске
  снимает переносчика. Запись чужой карты не перезаписывается старым телом. Authored
  размещение после переноса скрывается/удаляется при возврате, не создаёт второй ящик.
  Родительский Map/ExploreScene задаёт контекст карты до регистрации prefab.
- Возврат из killbox/радиуса на новой карте использует место прибытия текущей карты;
  координаты старого района к ней не применяются. Груз после load восстанавливается
  в руках записанного активного героя. При Tab Scene перепривязывает физическое тело
  между Player/follower представлениями того же героя. Это не независимая навигация
  спутников и не новая система приказов.
- `WorldRecovery` передаёт в deferred registration/recover ID, а не освобождаемый
  Node: проверяет instance перед вызовом. Закрыта воспроизведённая ошибка регистрации
  уже удалённого тела на быстром pickup/load/unload пути.
- `prefabs/items/chapter1_delivery_crate.tscn` размещён в chapter1_woodland рядом с
  входом из центра; ID chapter1_delivery_crate, прочный, масса3/размер12, радиус480.
  Saved сцена и её offline builder обновлены. Это пробный груз без новой награды.

`tools/test_world_carry_transition.gd` / `run_world_carry_tests.py`: native участок
опушка→центр→жилая→дом; F приоритет, profile/однаidentity, save/fresh State/load в руках,
Tab туда/обратно, оставить груз→вернуться на исходную карту без respawn→забрать снова,
бросок/killbox/неудачный переход/старые и испорченные optional записи. PASS и на готовой,
и на чисто подготовленной disposable копии Forward+1280×800/RTX5070; кадр просмотрен.
Regressions physical_crates/world_item_cycle/map_transition/combat_world_items и
world_recovery_detached PASS. Полный suite не запускался; manual F/WASD/камера OPEN.
Доказательства — Migration Test Plan. Ранее сохранённые данные main не менялись тестами.

#### Верстак и кухня05.11 — сделано без ручной приёмки

Согласовано: отдельный интерактивный верстак у Миры и тот же механизм для приготовления
по рецептам. Использованы нынешняя InteractionUi и единственный ExploreState. Рецепт
нужен как отдельная authored Resource, поскольку Action exchange уже умеет транзакцию,
но не содержит редактируемого списка рецептов рабочего места/показа требований.
Переиспользован штатный [Godot Resource/Inspector](https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html),
внешняя библиотека/новый inventory/save-owner не нужны.

- `scripts/ember_craft_recipe_resource.gd`: ID/title/station_kind/description,
  ingredients/results. Только известные Item IDs и положительные целые1–999,
  обе стороны непустые; ошибки блокируют открытие. Resource создаётся/редактируется
  обычным Inspector, без второй копии данных в специальном редакторе.
- `scripts/ember_crafting_station.gd` — EmberInteract adapter. Название, тип рабочего
  места и массив Resources recipes редактируются в Inspector. Рецепт другого типа,
  пустой/дублирующий ID и неверные предметы дают configuration warning/отказ открытия.
  Внешний объект/коллизия/Interaction — одна переносимая prefab-группа.
- `EmberInteractionUi` MODE_CRAFT: требования «есть/нужно», результат, выбор W/S или
  кнопками, создать F/Enter/кнопкой, Esc/«Закрыть» без затрат. Используется та же
  блокировка движения/панель, как у разговора/магазина. Экономический сигнал обновляет
  доступность; при commit inventory читается заново. Удалённое/закрытое условием
  рабочее место не продолжает выдавать предметы.
- `ExploreState.preview_exchange` выделен из прежней exchange_items, чтобы preview
  и commit считали одни правила. Он возвращает копию, ничего не сохраняет/не выдаёт.
  exchange_items применяет результат и сохраняет прежний порядок flags/signals/autosave.
  preview_recipe/craft_recipe валидируют authored данные и используют тот же путь;
  формат save не изменён. Переполнение результата и combat lock не тратят компоненты.
- `prefabs/items/crafting_workbench.tscn` стоит у сада на chapter1_estate;
  `cooking_station.tscn` — в chapter1_home. Обе saved сцены и их исходные offline
  builders обновлены, повторная генерация сохраняет размещение рабочих мест.
- `content/recipes/chapter1_practice_assembly.tres`:2herb→1revival_spark;
  `chapter1_practice_drink.tres`:1apple+1herb→1qingxin_tea. Это учебные рецепты,
  не сюжетный подарок/принятые блюда или баланс. Компоненты доступны в существующих
  chapter1_alchemy/general_store; бесплатная выдача при открытии UI не добавлялась.

Минимальный gate `tools/test_crafting.gd` через `run_crafting_tests.py` в disposable
копии: валидация/preview без мутации/2платных партии/нехватка/overflow/overlap/lock,
устаревшая UI-сумка/мышь/выбор/оба типа/исчезновение station, move+Undo/Redo+save/reopen,
Resource discard и загрузка результата свежим State; открытие/создание на реальной
saved карте дома. Forward+1280×800/RTX5070 PASS, UI-кадр просмотрен. Связанные
test_quest_handover и test_talk_shop Forward+ PASS. Новая fixture preparation ветка
runner не запускалась, использована уже подготовленная isolated копия; рабочий
checkout через --headless --editor не запускался. Evidence — Migration Test Plan.
Manual F/мышь/DPI и игровое ощущение OPEN. Сам рецепт подарка и сюжетная выдача
компонентов по поручениям — следующий контентный выбор, не автоматический результат.

#### Проходимый макет локаций05.11 — сделано без ручной приёмки

По явному запросу автора созданы новые связанные сюжетные карты с простыми коробками
зданий, действующими дверями и привязанными к NPC действиями. Main и генератор зданий
не изменялись этим срезом. Сохранён существующий WorldCanvas/ExploreScene/MapLoader,
native terrain/material/GrassPatch/tree путь; второй runtime/renderer/save-owner не добавлен.

- `scenes/chapter1_{residential,centre,harbor,estate,woodland,coast,tide_cave}.tscn`:
  жилая улица с каналом/мостами/дворами, центр с площадью/лавками, порт,
  подход/сад усадьбы, опушка, берег и заготовка пещеры с гротом.
- `scenes/chapter1_{home,guild,smith,general_store,alchemy,mansion}.tscn`:6интерьеров.
  Три раздельных shop Resources и3явно макетных dialogue Resources; без сюжетных наград.
- Открыть `chapter1_residential.tscn` в Godot и F6. WASD ходьба, F дверь/разговор/магазин,
  проход через выход меняет район. Общий sandbox_storage_root=`user://ember-chapter1-blockout`
  изолирует макет от main saves. Повторный F6 продолжает сохранённое место макета.
  WorldCanvas даёт Кая+Миру для навигации; это не сюжетный старт дня1.
- Коробка здания — дочерний визуал группы; DoorInteraction и return_* marker находятся
  в той же группе. NPC и его Interact также сгруппированы. Для переноса двигать группу,
  для замены внешнего вида сохранять её служебные дочерние узлы и ID.
  Свободные области остаются обычными перемещаемыми Region с именованным ID.
- `EmberMapLoader._region_nodes()` теперь ищет сначала Regions, затем Props рекурсивно,
  без повторов; `occupying_region_id()` использует тот же список. Это закрывает найденный
  дефект: return marker внутри перенесённого дома ранее не обнаруживался. Старый порядок
  свободных entry сохранён. Default Regions/entry стоит первым в новых сценах.
- Offline сборщики: `tools/build_chapter1_blockout.gd`, `build_chapter1_interiors.gd`,
  общий `chapter1_blockout_geometry.gd`. Результат — обычные editable .tscn и native
  `content/world_terrains/chapter1/*.res`. Сборщики — первичное заполнение; повторный
  запуск перезаписывает chapter1-карты, после ручного наполнения без копии не запускать.
- Найденный и исправленный дефект builder: make_interact принимает snake_case ключи,
  camelCase оставлял двери/магазины/диалоги без цели. Пересобраны13карт;12дверей,
  3shop и3talk привязки проверены в сохранённых сценах и реальным runtime.
- Независимая проверка:13saved сцен/terrain validation;7наружных маршрутов до локальной
  правки action IDs (сами наружные переходы не менялись); затем6интерьеров/возвраты,
  3UI-покупки/разговоры, saved move/reopen дома/NPC, cold save/load и проход мостика
  штатным controller. Existing map_transition regression PASS. Тестовые writes — sandbox/user://.
  Новый regression `tools/test_chapter1_blockout.gd`; runner `run_chapter1_blockout_tests.py`.
  GDScript прогнан напрямую в Forward+1280×800/RTX5070; fresh-prepare ветка runner
  не запускалась, проверен синтаксис. Статусы/доказательства — Migration Test Plan.

Ручные клавиши/темп/размеры/камера и художественный вид OPEN. Пещера — макет без
новой водной головоломки, NPC — временные обозначения. Перенос груза и крафт реализованы
отдельными срезами выше; независимое ожидание Миры, сюжет/рыбалка ещё не добавлены.
Ближайший результат — авторский проход и исправление мест, мешающих первому дню.

Запрос автора: продолжать поэтапно, предусмотреть поставить/передвинуть/бросить
предмет, его нахождение в нужном месте, состояния/анимации и постановочные сцены
рядом с диалогами. Ниже рекомендация по устройству, не реализованный универсальный
конструктор и не принятое заранее игровое правило всех будущих задач.

Общий подход: цель описывает проверяемый результат; способы действия и показ
сцены остаются у существующих владельцев. Понятные названия в редакторе — presets
над небольшим числом проверок, не отдельный исполнитель на каждый глагол.
Проверки читают актуальное состояние владельца; события сообщают о совершённом
действии. Quest хранит свой прогресс, но не дублирует состояние предмета/AI/сумки.

Семейства для будущих конкретных срезов:
1. Состояние: иметь N предметов, дверь открыта, рычаг включён, объект разрушен,
   персонаж жив/в нужном состоянии. «Иметь» отличается от исторического «получить».
2. Расположение/отношение: игрок/нужный объект в зоне, предмет в контейнере,
   ящик на плите, объект ориентирован/остановлен. Это одна семья «кто / где /
   дополнительные условия», а не типы для каждого предмета и каждой площадки.
3. Событие: подобрать, прочитать, успешно купить у продавца, передать, применить,
   бросить, закончить разговор с нужным исходом. Содержимое сумки само по себе
   не доказывает покупку или бросок. Фильтры: источник, получатель, тип/экземпляр,
   число, этап отсчёта. Источник — существующий успешный результат действия.
4. Результат встречи/исследования: победить определённую группу, закончить встречу,
   открыть область. Бой уже отдаёт committed result/счётчик; поражение/Retry не
   должны давать победу повторно. Открытие области — у владельца исследования.
5. Время/составные условия: удерживать состояние, защитить область, дождаться
   события, выполнить все/любое/выбор ветви. В нынешней схеме dependencies — ALL;
   ANY/NOT/exclusive нельзя обещать только проводами без runtime/save правил.

Прежняя проба «Ящик → плита → проход»29.10:
- Базовый carry/settle/обратимый проём/безопасность проверены test_pressure_gate и
  прежними zone/carry gates. Общая containment-проверка остаётся в
  ember_object_zone_rules.gd; QuestObjectZone сохраняет прежнюю latch-семантику.
- Прямой контроллер заменён общей схемой ниже. Старый ember_pressure_gate.gd —
  только envelope старых .tscn: создаёт те же2 компонента и использует общий
  Circuit, своей физики/второго исполнителя больше нет. Первая правка в новом
  окне переводит его в обычный Circuit одним Undo, сохраняет физические узлы и
  переносит настройки. Native EUM conversion/Undo/Redo/save/reopen PASS.
- Старый basic builder поддерживает2-компонентный пример для regression gate;
  новый авторский набор и прежняя игровая сцена показывают обе схемы ниже.
  Новых рабочих карт не создавалось; ручная приёмка прежнего управления OPEN.

Конструктор механизмов29.10 · первая версия сделана без ручной приёмки:

Подтверждено автором: единая система создания механизмов-головоломок с проводами;
разрешено переделать прежнюю пробу под неё. Minecraft/LittleBigPlanet приняты как
референсы редактора gameplay; каноническая роль — Product Plan. Положение рычагов
сохраняется, плиты/условия/двери/лампы пересчитываются по текущему миру после load.
Это решение о состоянии обычных механизмов, не отмена прежнего reset спутников.

Как создать и настроить:
1. В3D включить **Механизмы** (либо Ember Graph → Механизмы). Справа открывается
   контекстная панель. Выделить обычный предмет → одна из4 плиток ролей. Для нового
   независимого набора отметить **В новом механизме**; иначе используется текущий.
   Первый набор создаётся автоматически, без площадки и готовых предметов.
2. Выбрать следующий предмет, назначить роль в том же наборе; соединить3D выход→вход.
   **Shift+вход** снимает связь, **Esc** отменяет черновой провод. Тумблер проводов
   скрывает их, сохраняя режим выбора предметов. Условия/задержку/фиксацию добавляет
   **+ Логический блок**; выбрать блок для настройки можно списком или его3D-меткой.
3. Справа — только параметры выбранной роли/блока, те же поля прежней Workspace.
   **Применить параметры** фиксирует форму, **Убрать из механизма** снимает роль/
   блок и провода; физический предмет остаётся. Автоматическая зона двери не требует
   ручной привязки. Параметры не коммитятся на каждый символ. Для сложных соединений
   есть **Полная схема…**: прежний GraphEdit, свойства остаются в боковой панели.
   Готовый starter доступен в расширенной схеме через **Создать набор**.
4. **Отменить / Повторить**, Ctrl+Z/Shift+Ctrl+Z в окне — история той же сцены.
   Провода/создание/параметры/перетаскивание карточек пишутся одной командой на
   действие, не на каждый символ/кадр. **Сохранить сцену** либо обычный Ctrl+S
   редактора сохраняет .tscn. Позиции карточек — editor metadata; перенос карточки
   не передвигает предмет и не перезапускает физику схемы.
5. F6 camera_preset_study → **ИГРАТЬ · ящик, плита, проход**. WASD/F для обычного
   игрока; нужны оба ящика на плитах. Оба рычага управляют лампой через ЛЮБОЙ.
   **Схема механизма · провода** открывает то же окно с живыми значениями/проводами.
   Пока оно открыто, игрок не ходит при наборе текста; закрытие/Esc возвращают
   управление. В F6 правки временные, source не перезаписывается. **Заново**
   создаёт чистую lab-пробу, Esc вне окна возвращает к прежним камерам/квестам.

Состав и правила:
- Источники: plate/lever; логика: all/any/not/hold/latch (ВСЕ/ЛЮБОЙ/НЕ/задержка/фиксация);
  получатели: door/lamp. Входы/выходы первой версии только on/off. ALL/ANY имеют
 2 входа, NOT/door/lamp1. Неподключённые входы false, неподключённый NOT тоже false,
  чтобы незаконченная карточка не активировала выход сама. Узел двери показывает
  команду схемы, реальное закрытие дополнительно защищено датчиком проёма.
- Циклы (в том числе через фиксацию), два провода в один вход, неподходящие типы/неизвестные IDs,
  некорректные параметры/привязки и второй контроллер того же физического объекта
  отклоняются до изменения сцены. Привязки могут вести к обычным объектам той же
  сцены без переподчинения; чужие/вложенные наборы и уже занятый другим механизмом
  объект не получают второго владельца. До128 компонентов в схеме.
  Есть задержка выключения и фиксация; импульсы/счётчики/вложенные схемы/межнаборные
  провода ещё не введены.
- Созданные кнопкой наборы и компоненты получают новые устойчивые IDs; удалённый
  ID не выдаётся заново, чтобы старый save рычага не включал другой новый элемент.
  Обычный Ctrl+D набора копирует и world-item IDs: для независимого набора использовать
  **Создать набор**. Совпадающий circuit_id диагностируется; автоматическая безопасная
  deep-copy всех сохранённых identity — отдельная будущая функция.
- Дверь движется с коллизией одной AnimatableBody3D и ждёт свободного clearance.
  Источник плиты сохраняет прежние containment/carried/settle правила. Runtime
  исчезновение привязанного объекта останавливает вычисление с диагностикой,
  не становится успешным квестовым событием. Игровое ощущение/streaming ещё OPEN.

3D-провода29.10 · сделано без ручной приёмки:
- Запрос автора: LittleBigPlanet-подобный конструктор прямо на карте. Это второй вид
  той же схемы, не новая механика/сохранение. В обычном3D viewport кнопка **Механизмы**,
  выбор набора в боковой панели. Метки физических компонентов следуют мировым точкам; логика
  располагается около набора. Подписи занимают ближайшие свободные экранные места,
  тонкие линии указывают на исходные точки. Объекты от этого не перемещаются.
- Щелчок по зелёному выходу → по синему входу создаёт связь; **Shift+вход** снимает.
  **Esc** или пустое место отменяет черновой провод; выключение режима/смена сцены
  тоже его сбрасывают. Щелчок по метке выбирает компонент в боковой панели.
  Undo/Redo/Ctrl+S — история/сцена
  Godot. Ошибка занятого входа/цикла ничего не меняет.
- Режим обрабатывает порты до инструментов рисования Ember; вне карточек обычный
  выбор предмета и навигация камеры остаются Godot, кисти Ember не запускаются.
  Это authoring, не игровой строительный режим. Роль обычному предмету назначается
  плитками контекстной панели (ниже), включая автоматическую физику двери/плиты.
  Межнаборных проводов и свободного перетаскивания логики в пространстве пока нет.
  Первая проверка — один обычный3D viewport; split-view,
  большие плотные схемы и125% требуют отдельной ручной оценки.
- Godot предоставляет overlay/input forwarding без добавления scene nodes:
  [EditorPlugin](https://docs.godotengine.org/en/stable/classes/class_editorplugin.html#class-editorplugin-private-method-forward-3d-force-draw-over-viewport).
  Переиспользован существующий plugin hook; LBP/Minecraft референсы — Product Plan.
- `ember_mechanism_world_wires.gd` — editor-only экранная проекция портов и команды
  InspectorActions.apply_mechanism_document; физика/serialization не расширены.
  Targeted projection/hit/input/Undo/Redo/reject/cancel PASS. Native Forward+ overlay,
  EditorUndoRedoManager, save/reopen/discard PASS, exit0; вид просмотрен. Evidence:
  прежняя папка mechanism-circuits → world-native.log/native-world-wires.png.
  Ручной input/основной editor/main integration остаётся OPEN; карту не меняли.

Роли обычных объектов29.10 · сделано без ручной приёмки:
- Без готового набора: включить **Механизмы**, выделить один Node3D → плитка роли.
  **Рычаг** — источник переключения по F; **Лампа** — получатель для MeshInstance3D
  либо Light3D; **Дверь** и **Нажимная плита** создают физику/зоны автоматически.
  Выбрать существующий набор либо **В новом механизме**. При первом
  назначении создаётся только Circuit+Component, без площадки/ящиков/декораций.
- Назначить второму предмету другую роль в том же механизме; режим проводов включится
  автоматически. Выход→вход, затем Ctrl+S. Выбор следующего обычного предмета работает
  без выключения проводов. Дверь/плита — исходный сохраняемый объект с mesh-геометрией,
  без чужого RigidBody/CharacterBody/AnimatableBody контроллера. Производная несохраняемая
  часть объекта отклоняется: выбрать исходный scene prop. Служебные узлы добавляются
  дочерними элементами; исходный parent/transform/script не меняются.
- Предмет не меняет script, parent, transform или owner. Circuit/Component хранят
  обычные относительные NodePath к соседним веткам сцены. Новый role+Circuit — один
  Undo, следующие назначения — прежний apply_mechanism_document. Undo не удаляет
  предмет; снять роль можно через «Убрать из механизма», затем назначить другую.
- Автоматическая дверь/плита: `ember_mechanism_role_geometry.gd` объединяет mesh AABB
  в координатах объекта. Door helper содержит AnimatableBody3D+BoxShape и Clearance;
  Plate helper — StaticBody3D+BoxShape и PlateZone над верхней гранью. Это начальная
  прямоугольная аппроксимация, не точная вогнутая коллизия. После изменения геометрии
  размеры Shape поправить в Inspector либо снять/назначить роль заново.
- Дверь первоначально поднимается по локальной Y на высоту AABB+4; высота/время —
  общие свойства компонента. Clearance следует объекту в editor, в runtime остаётся
  на закрытом проходе; собственные тела двери не блокируют её датчик. Имеющиеся
  StaticBody shapes временно отключаются в игре, при снятии/Undo восстанавливаются;
  исходный материал двери сохраняется. При удалении карточки helper снимается,
  Undo возвращает его с owner/зонами. Отдельного контроллера двери нет.
- Плита с пустым полем ящика реагирует на CharacterBody3D либо спокойный RigidBody3D
  (не переносимый сейчас), после settle. Выбран конкретный world-item ящик — прежний
  строгий identity/full-containment путь Rules сохраняется. Статические декорации
  сами по себе не являются нажимающим весом. Physics overlap обновляется по кадрам,
  а не мгновенно; первоначальная пауза Circuit и общий solver прежние.
- Основание реализации: [AnimatableBody3D](https://docs.godotengine.org/en/stable/classes/class_animatablebody3d.html)
  для подвижного тела и [Area3D](https://docs.godotengine.org/en/stable/classes/class_area3d.html)
  для датчиков. Переиспользованы scene Components/Circuit/InspectorActions; metadata
  helper хранит роль/ID, не вторую схему. Runtime caches не являются export-данными.
- Один физический target не назначается повторно тому же или другому механизму.
  Чужие сцены, корни/внутренности другого набора и несовместимый тип отклоняются.
  При загрузке/стриминге target по-прежнему обязан быть доступен: автоматического
  ожидания выгруженных веток нет; прежний main/streaming gate остаётся OPEN.
- `test_mechanism_circuits.gd`: два обычных объекта вне Circuit → роли → F adapter
  → лампа; единственность роли/ошибки типов, Undo/Redo, неизменные hierarchy/transform/
  scripts, source save/reopen/discard и отсутствие runtime adapter в .tscn PASS.
  Native Forward+ форма назначения/провода, scene history/save/reopen/discard PASS,
  exit0; форма/3D просмотрены. Это API-проверка, мышь и основной editor/main OPEN.
  Evidence: mechanism-circuits → roles-native.log/native-role-dialog.png/
  native-ordinary-wires.png. Прежние Graph/plate/legacy regressions PASS.
- Автозоны: отдельные обычные объекты в вложенной группе → назначение плиты/двери →
  провода; actor/лежащий RigidBody, occupied passage, moving collision ray, снятие
  helper/восстановление старой коллизии/Undo/Redo/source reopen PASS, включая Forward+.
  Native editor EUM/назначение/окно1280×720/scroll/провода/save/reopen/discard PASS,
  exit0; вид просмотрен. Evidence: auto-roles-targeted.log/auto-roles-forward.log/
  auto-roles-native.log/native-auto-role-*.png. Мышь/main/streaming OPEN.
- Legacy форма назначения (API/regression, основной вход теперь плитки панели)
  следует UI Pipeline → «Стандарт новых окон и форм Godot»:
  предпочтительно540×340, clamped popup90%, текст в RoleScroll, OK/Cancel снаружи.
  Длинный текст раньше раздувал окно до540×7582; regression проверяет ограниченный
  размер, видимую прокрутку и доступную кнопку подтверждения. Targeted PASS.
- Это расширение существующих scene bindings и формы назначения по принятому
  LBP/Minecraft authoring ориентиру (Product Plan); нового графа/состояния нет.

Задержка выключения29.10 · сделано без ручной приёмки:
- Выбор автора: после ухода с плиты дверь остаётся открытой ещё заданное время.
  В общей схеме выбрать **Задержка выключения**, задать имя/секунды и добавить
  компонент. Переподключить **плита → задержка → дверь**. Вход активен — выход
  включён сразу; повторное нажатие обновляет запас времени. Длительность0,05–120с,
  default3с; отдельного окна или роли физического предмета для логики нет.
- `kind=hold`, Component.hold_seconds → snapshot/validation → общая форма → .tscn.
  `Model.advance` — чистый шаг вычисления значений и нового countdown-state в
  топологическом порядке; Circuit один раз вызывает его в physics tick. Старый
  Model.evaluate остаётся stateless-проекцией. Задержка имеет1вход/1выход;
  циклы по-прежнему запрещены, отсоединённый вход не сохраняет старый сигнал.
- Countdown не export и не save flag. Сохраняется длительность, после загрузки
  сигналы пересчитываются по текущим источникам; незаконченный прошлый отсчёт не
  продолжается. Pause/physics stop останавливает часы. Логическая правка/rebuild
  сбрасывает transient countdown; перемещение карточки не сбрасывает. Дверной
  clearance продолжает отдельно защищать занятый проход после истечения времени.
- Выбор physics delta согласован с [Timer/physics callback](https://docs.godotengine.org/en/stable/classes/class_timer.html):
  отсчёт следует игровому времени/паузе. Отдельные Timer nodes не нужны: их порядок
  и callbacks дублировали бы существующий единый circuit step.
- `_test_hold_gate`: idle/instant-on/off duration/retrigger/zero delta/partition/
  disconnected input/invalid durations, runtime pause и metadata-only layout,
  поле/Undo/serialization без countdown PASS. Native Graph add/wires/seconds/
  EditorUndoRedoManager/save/reopen/discard PASS; окно просмотрено. Evidence:
  mechanism-circuits → hold-current-forward.log/hold-door-forward.log/hold-editor.log/
  native-hold-properties.png. Физическая цепочка плита→hold→дверь проверена Forward+
  после отпускания и истечения времени; текущая source-копия PASS без fixture замен.
  Мышь/main и пользовательское игровое ощущение OPEN.

Фиксация сигнала29.10 · сделано без ручной приёмки:
- Подтверждение автора: состояние сохраняется после загрузки до отдельного сброса.
  В общей схеме выбрать **Фиксация сигнала**, добавить компонент. Два подписанных
  входа **Включить**/**Сброс**,1выход; подписи также видны на3D-портах.
  Пример: плита→Включить, другой рычаг→Сброс, выход→дверь. Короткое включение
  удерживает выход после отпускания. Оба входа активны — сброс побеждает; если
  сброс затем отпущен при ещё активном включении, блок снова включится.
- Kind=latch, новых физических узлов/окон/экспортируемого bool нет. Чистый
  Model.advance принимает previous_latches и возвращает latches вместе с values/
  timers, всё ещё в едином DAG step Circuit. Отсоединённые входы не стирают уже
  сохранённую память; удалить блок и создать новый — другой устойчивый ID.
- Единственный persistent owner — ExploreState.flags, ключ
  mechanism_latch_<circuit_id>_<component_id>; рычаги используют прежний namespace.
  Схема в .tscn хранит kind/ID/провода, не копию игрового состояния. Rebuild/layout/
  Undo не очищают флаг. `set_flags_batch` сначала валидирует весь набор, затем
  фиксирует все изменённые флаги, один progress_changed и один autosave. Каскад
  фиксаций не публикует полусостояние; неизменный вход не пишет каждый кадр.
- При pending spawn restore Circuit ждёт общего существующего барьера загрузки
  и новых overlap кадров: исходящий/ещё не восстановленный мир не должен заново
  активировать сохранённый замок. Это не закрывает прежний streaming/main gate.
- Исследование [Godot Saving games](https://docs.godotengine.org/en/stable/tutorials/io/saving_games.html)
  разделяет persistent данные и реконструкцию сцены; в Ember переиспользуется уже
  существующий State/save-v2 путь, без второго Persist/file owner.
- `_test_latch_gate`: truth table/reset priority/disconnected retained state,
  runtime cascade/atomic observer/один реальный autosave, повторные кадры без записей,
  настоящий load true/reset/load false, invalid batch без частичной мутации,
  pending restore guard, UI labels/layout/Undo/source reopen PASS (Forward+).
  Native palette add/оба входа/провода/EUM/save/reopen/discard PASS; вид просмотрен.
  Shared `test_party_save_v2.gd` PASS, исходные copied inputs frozen.
  Evidence: mechanism-circuits → latch-forward.log/latch-editor.log/
  native-latch-properties.png; ручная мышь/игровая сцена/main OPEN.

Интерфейс механизмов29.10 · направление выбрано автором, сделано без ручной приёмки:
- После нативной пробы автор выбрал **боковую панель и компактные порты в3D**.
  Основной сценарий: выбрать предмет → назначить роль → соединить → настроить
  только нужные параметры. Колесо/плавающая Popit-палитра не выбраны основой.
- Исследование остановлено на3 подходящих первичных источниках:
  [Dreams: Logic & Processing](https://docs.indreams.me/en/create/resources/edit-mode-guide/assembly/gadgets/logic-and-processing)
  — гаджеты, явно именованные порты и microchip как способ убрать нагромождение.
  Берём группировку в выбранный механизм; вложенные microchip-схемы не добавлялись.
  [Unreal Blueprint Basic User Guide](https://dev.epicgames.com/documentation/en-us/unreal-engine/blueprint-basic-user-guide-in-unreal-engine)
  — контекстное добавление и фильтрация; [Components](https://dev.epicgames.com/documentation/en-us/unreal-engine/components-window-in-unreal-engine)
  — выбранный элемент определяет свойства. Берём контекст, а не полный визуальный
  язык программирования. [Blender Node Editors](https://docs.blender.org/manual/en/5.2/interface/controls/nodes/node_editors.html)
  — добавление через меню/поиск и из протянутого порта. Реализовано компактное
  меню5 логических блоков, в том числе от свободного конца провода; поиск пока не нужен.
- UI brief: автор мира, мышь/клавиатура; вход одной кнопкой «Механизмы», выход ею же
  или сменой сцены. Пустой выбор/нет роли → подсказка/4плитки; роль выбрана → параметры;
  логика → то же поле свойств, выбранное списком/портом. Ошибки назначения/validation
  выводятся в панели. Применение параметров явное, Undo/Redo/save — тот же scene owner.
- Сборка прямо в3D: выход → щелчок по пустому месту → меню ВСЕ/ЛЮБОЙ/НЕ/задержка/
  фиксация → выбранный блок. Блок и входящий провод создаются одним Undo, его выход
  сразу продолжает соединение; поля открываются в той же боковой панели. Esc/закрытие
  меню/смена сцены или режима отменяют незавершённое добавление без записи.
  Меню ограничено360×340; отдельная форма/полная схема для этой операции не нужны.
- Место щелчка проецируется на глубину выхода. Положение хранится в component metadata
  `mechanism_world_position` (Vector3 относительно Circuit), в snapshot — optional
  `world_position`. Старые схемы используют прежнее автоматическое размещение.
  Model проверяет конечность координат; вычисления сигналов их не используют.
  Metadata-only правка идёт через прежний Actions/Undo без rebuild/countdown reset.
  Property edit, source save/reopen и Undo сохраняют это размещение.
- Подпись логического блока можно тянуть ЛКМ: движение в плоскости текущего вида
  на исходной глубине. Для другой плоскости сначала повернуть камеру. Порты остаются
  отдельными точками подключения; обычные предметы двигает штатный Godot gizmo.
  После5px начинается preview только в overlay, без записи/Undo/rebuild на motion;
  pointer-up фиксирует local Vector3 одной Actions-командой. Клик без движения,
  Esc, скрытие портов/режима и scene switch не фиксируют перенос; внешняя команда
  истории отменяет незавершённый preview. Явно размещённые блоки больше не прыгают
  между экранными слотами: preview совпадает с commit и сохраняется в source.
- При выбранном выходе свободные допустимые входы зелёные, запрещённые красные.
  Feedback строится из прежнего Model.errors при смене выхода/документа, не на каждый
  кадр: занятый вход и цикл используют те же правила, что команда подключения.
  Наведение на красный вход показывает ограниченную подсказку рядом с курсором.
  Отклонённая связь сохраняет исходный провод для следующей попытки.
- Новый `ember_mechanism_inspector.gd` — только контекстное представление. Он берёт
  **существующий** property-editor Control у Workspace (take_property_editor),
  не создаёт второй алгоритм настроек. Kind/target и ссылки автоматической зоны
  скрыты, actor/предмет плиты и параметры движения/времени остаются контекстными.
  NodePaths в меню отображаются короткими именами с полным путём в tooltip.
- Plugin подключает EditorDock справа. WorldWires в этом режиме оставляет одну
  toolbar кнопку; выбор набора переходит в панель. Порты — точки/короткие подписи,
  Включить/Сброс различаются. Скрытие проводов не включает обратно кисти Ember.
  Свойства по щелчку метки не теряют контекст при обновлении схемы. На scene switch
  окно/панель освобождаются, общий picker возвращается WorldWires до удаления UI.
- Undo/Redo/save/сообщения находятся вне прокрутки; длинные параметры прокручиваются.
  «Убрать из механизма» сохраняет физический предмет. «Полная схема…» — явный
  расширенный GraphEdit, всё ещё прежняя схема; в F6 study старый lab Window сохранён.
- Нативная UX-проба выполнена до переноса, без правки авторской карты. Production
  controls проверены в настоящем EditorDock при1600×900, те же controls — в ограниченном
  1280×720 shared-world preview. Это QA-проба Forward+, не второй production renderer.
  Полное размещение всех нынешних панелей Godot на маленьком мониторе и125%/мышь
  остаются ручными gates; нельзя выдавать preview за принятую основную карту.
- `_test_mechanism_inspector`: palette→roles→wires, те же conditional fields,
  add logic/параметры/снятие/Undo, независимый набор/переключение, ports off/mode on,
  stale scene, повторное подключение панели/общий picker/состояние тумблера PASS.
  Native EUM/save/reopen/discard, компактная панель/порты, viewport mouse-event API,
  cleanup PASS; кадры просмотрены. Дополнительно empty-space gesture, клавиатурный
  выбор настоящего PopupMenu, автоматический вход/продолжение выхода, один EUM action,
  сохранённое3D положение/reopen/discard PASS. Регрессия проверяет hide-before-id_pressed
  порядок PopupMenu; прямой Viewport.push_input этот оконный путь не имитирует.
  Дополнительно drag preview=commit/one-action Undo/Redo/source reopen, отсутствие
  записи на motion/click/Esc/ports-off, прежний component identity, compatible/
  occupied/cycle feedback и захват press+release при записи связи PASS.
  Native Editor EUM/Forward+ drag+подсказка/save/reopen PASS, кадры просмотрены.
  Evidence: mechanism-circuits → gestures-forward.log/auto-roles-forward.log/
  native-wire-drag-preview.png/native-wire-port-feedback.png/native-wire-add-*.png/
  inspector-editor.log/native-inspector-*.png. Ручная приёмка и main OPEN.

Owners и данные:
- `scripts/ember_mechanism_graph.gd`: чистая validation/topological boolean math.
  Scene-owned `ember_mechanism_circuit.gd` — один runtime вычисления/маршрутизации;
  `ember_mechanism_component.gd` — typed authored Node с component_id/kind/label,
  NodePath target/crate/clearance, параметрами движения/покоя. Components читают
  существующие тела и управляют только своим получателем. Runtime рычага —
  ember_mechanism_lever_interact.gd, прежний F/EmberInteract путь.
- `.tscn` хранит circuit_id, links[from,to,port] и дочерние компоненты; ссылки
  компонентов на физические узлы — export NodePath. Layout — graph_position и optional mechanism_world_position metadata.
  Никакого механического графа в QuestResource, нового renderer либо save owner нет.
- Lever bool хранится в ExploreState.flags как mechanism_<circuit_id>_<component_id>.
  Сумка/позиции/тело/находки остаются в прежних world_items. Output values/pressed/
  openness не дублируются в save. Награды/Dialogue/катсцены этим сигналом каждый
  кадр не вызываются; такие команды ещё требуют отдельного event/await контракта.
- `ember_mechanism_workspace.gd` — native Window с Godot GraphEdit, одна сцена/
  выбранный Circuit, live портами и связями; не второй интерпретатор квестов.
  InspectorActions.apply_mechanism_document/replace — единственный путь записи,
  обычный EditorUndoRedoManager и source scene. Plugin лишь открывает окно/вызывает
  create/save. Scene-switch guard отклоняет правку старой карты. Только layout
  применяется отдельно через metadata без пересоздания components/движения двери.
- `ember_pressure_gate_builder.gd`: basic2-component/новый8-component starter из
  тех же узлов. Старый envelope делегирует Circuit; первая edit-команда меняет
  script/компоненты в одном Undo. Исходные физические узлы/IDs сохраняются.

Проверено:
- `test_mechanism_circuits.gd` PASS: AND/OR truth tables/NOT и disconnected case,
  cyclic/duplicate input rejection, реальные обе плиты/дверь, F-адаптер рычага,
  один autosave/read lever flags, переоткрытая сцена с сохранённым миром, native
  GraphEdit signals/add NOT/rewire/Undo/Redo/error/no mutation, layout-only не
  заменяет эффектор, source save/reopen/discard/без runtime lever adapter в source,
  stale scene guard, legacy conversion/Undo/Redo и pause/input return в lab.
- Native editor через EditorUndoRedoManager: wire Undo/Redo, старый envelope без
  компонентов → conversion → Undo/Redo, save_scene_as/reopen/discard несохранённой
  связи, authored-only узлы и NodePaths PASS, exit0. Это API-проверка в реальном
  редакторе, не ручной ввод мышью/125%.
- Native Forward+ play/window/live wires/disconnect/Undo/input return PASS, exit0;
  окно и пример просмотрены. Связанные pressure-gate F/physics/closed/open/occupied/
  save и quest crate placement PASS; прежняя containment математика не менялась.
  Штатный gate: `python tools/run_mixed_editor_tests.py --test test_mechanism_circuits.gd`.
- Evidence: `C:/Users/novos/Documents/Codex/2026-10-29/mechanism-circuits/` →
  circuits.log/registered-runner.log/editor.log/native.log/bindings.log,
  native-editor.png/native-workshop.png/
  native-active.png/native-gameplay.png, regression logs/fixture-path.txt.
  Рабочая основная карта и оптимизация другого чата не менялись. Ручные сборка своей
  схемы/мышь/125%/узкий экран/ощущение F и main/save/streaming OPEN. Старый отдельный
  editor-exit AV сценок не объявляется исправленным успешным выходом этого probe.

Исследование, определившее границы:
- [Microsoft Guide to Redstone](https://learn.microsoft.com/en-us/minecraft/creator/documents/redstoneguide?view=minecraft-bedrock-stable):
  комбинация источников, обработки/передачи и исполнителей. Для Ember взята
  композиция, без силы0–15/затухания по длине/особенностей порядка тиков Minecraft.
- [Media Molecule](https://www.mediamolecule.com/blog/article/emails_from_the_molecule_help):
  advanced logic/microchips/notes и трудности сложных вложенных схем. Для первого
  среза взяты читаемые связи/подписи/наблюдение состояния, группировки остаются
  следующей необходимостью повторяющегося контента. Полный каталог LBP gadgets не
  заявляется проверенным по первичному источнику. Список первой версии — наш контракт.

Примеры общей проверки предмета в месте:
- «Поставь ящик на плиту» = нужный объект внутри объёма + нужная опора/покой.
- «Передвинь статую» = та же проверка места/ориентации; способ перемещения свободный.
- «Брось камень в круг» = событие броска нужного объекта + попадание/состояние зоны.
  Если способ не важен, оставить только положение — перенос и бросок равно подходят.
- «Положи ингредиент в чашу» = принадлежность контейнеру/успешная передача; не
  обязательно запускать полную физику ради состояния «внутри чаши».

Границы до кода таких целей:
- Отличать тип предмета от конкретного экземпляра. Выбор объекта/объёма в3D
  связывается с прежними устойчивыми placement/world-item IDs; NodePath годится
  для editor-навигации, не как новый единственный save-ID.
- Физические кандидаты ограничиваются нужным Area3D/объёмом; движение внутри
  проверять только для активных кандидатов. Одного body_entered недостаточно для
  поворота/покоя внутри зоны; обход всего мира каждый кадр не нужен.
- Для покоя/опоры задать допуски скорости/угла/времени на конкретном примере,
  чтобы дрожание физики не мигало успехом. Эти параметры/ощущение ещё не выбраны.
- Уточнять «есть сейчас», «сделать хотя бы раз», «удерживать N секунд», а также
  учитывать ли уже выполненное. До фиксации результата состояние может исчезнуть;
  повторный зачёт/отмена готовой цели требуют явного правила конкретного квеста.
- После load/streaming повторно читать владельцев; выгруженный объект не считать
  автоматически уничтоженным/перемещённым. Не сохранять сырые ссылки на узлы.
- Анимация представляет действие, а смысловой результат даёт её владелец.
  Открывание двери не становится успешным только по старту клипа; прерывание,
  пропуск, сохранение и финальное состояние должны согласовываться.

Диалоги и постановка — отдельная последовательность действий, не семейство целей:
- Короткая фраза, обычный диалог с выбором и постановочная сцена используют
  существующие Action/Dialogue owners; разные способы показа не заводят второй
  квестовый runner. Этап может запускать показ при открытии/выполнении или ждать
  конкретного результата сцены, если это действительно условие задания.
- Рекомендуемый первый постановочный срез: камера → движение/жест одного NPC →
  реплика → возврат управления. Клипы/дорожки — нативный Godot AnimationPlayer;
  Action ждёт явного результата исполнителя (finished/cancelled/skipped), а не
  угадывает длительность таймером. Полный новый timeline-editor пока не нужен.
- До реализации определить пропуск/отмену, восстановление камеры/input, поведение
  при выходе из сцены/save/load и однократность наград. Дорожка анимации не должна
  повторно списывать предметы при seek/replay. Результат игры фиксируется прежним
  владельцем; показ отражает его и корректно завершается при пропуске.

Проверенные ориентиры:
- [Questify](https://github.com/TheWalruzz/godot-questify), тот же исследованный
  revision из I3.14: Objective/Condition(type,key,value), Any/Not/Exclusive и
  condition_query_requested. Он не приносит готовую физику «перетащи ящик»;
  проверку игрового мира всё равно реализует игра. Перенос его polling не нужен.
- [Yarn Spinner для Godot: Commands](https://yarnspinner.dev/docs/godot/gdscript/05-connecting-to-your-game/01-commands/):
  команда может вернуть Signal/await, и диалог ждёт движения/анимации. Для Ember
  полезен этот контракт ожидания, не установка второго dialogue runner.
- [Godot AnimationPlayer](https://docs.godotengine.org/en/stable/classes/class_animationplayer.html):
  клипы/переходы/дорожки; seek в конец не равен animation_finished. Значит пропуск
  сцены требует явного завершения, а не надежды на сигнал проигрывателя.

«Дойти до места» · сделано28.10, ручная main-приёмка OPEN:
- В карточке flag-цели: «+ Место, до которого нужно дойти». Создаёт обычный
  scene-owned EmberInteract в AuthoredTriggers с activation_mode=enter и прежний
  Action/set_flag; Quest, Action и зона входят в одно Undo/Redo. Новый runtime,
  тип Quest Resource или отдельный save-ID зоны не вводятся.
- После создания кнопка выбирает существующую зону; её прежние Box bounds/gizmo
  позволяют менять размер и место. Работа идёт на открытой основной карте,
  сама landscape_compact автоматическими проверками не переписывается.
- Зачёт — вход именно игрока после всех requiresObjectiveIds; ранний визит не
  запоминается, после открытия цели нужно выйти/войти снова. Первая цель без
  prerequisites также начинает задание. Выполненная цель отключает свой trigger
  через существующее условие по флагу; прогресс переживает save/cold load.
- Owners: ObjectInspectorActions.create_quest_reach_zone, Graph/plugin,
  SceneAuthoring.make_standalone_trigger, EmberInteract → Player → InteractionUi
  → ExploreState.apply_authored_flag. Результат — у прежнего QuestCatalog gate.
  Исправлено отключение monitoring из body_entered (deferred) и переподключение
  progress после повторного прикрепления узла Undo/Redo.
- Native Forward+ test_quest_reach_zone PASS: кнопка/повторный выбор, физический
  вход/ранний вход/повтор, Undo/Redo, scene save/reopen, cold save/load, отказ
  counter-цели/дубликату. Quest workflow/разговор/ответ/передача и launch rules,
  standalone authoring, изолированный plugin parse PASS. Визуальная карточка
  просмотрена; мышь/gizmo, размещение и прохождение на main автором OPEN.

Рабочие этапы этой темы:
1. Принять руками текущий путь «свой NPC → диалог → передать предметы» на main.
2. Область и предмет: одна зона + один ящик, сначала свободно поставить в область,
   затем на той же проверке уточнить «нужно бросить/повернуть/оставить неподвижным».
   Перед кодом сверить существующие перенос/физику/WorldItems и выбрать ощущение.
3. Конкретный ответ диалога реализован в I3.14, его ручная оценка и оставшиеся
   необходимые квестовые механики открыты; катсцены
   выделены автором в отдельную работу после квестов, не начинать их сейчас.
4. Вторая цепочка «Груз у берега» собрана на main (ниже), техническая проверка
   PASS, ручная OPEN. Напоминание NPC и награда в карточке реализованы, I3.14;
   цельная сборка со своими текстами и прохождение после reopen проверены в Forward+
   fixture выше. Следующий gate — собственная сборка/перенастройка автором на main.
   Каталог механик расширять только по конкретному пробелу сценария.
5. После квестового среза вернуться к отклику воды на персонажа — вопрос у Water
   Rendering → «Следующий разбор моря27.10». Сейчас код/вид воды не меняются.

Решение автора о катсценах (после квестовых механик): отдельно исследовать готовые
средства Godot/аддоны для постановки и удобства автора, затем решить, требуется ли
свой editor поверх них. Нужны камеры/переходы/возврат управления, расстановка и
движение персонажей, реплики, процедурные, обычные тестовые и записанные анимации.
Предыдущие обсуждения записанных клипов сохраняются; не сводить всю постановку
к одному способу анимации. Первый будущий шаг — сравнить доступные инструменты
и показать небольшой рабочий пример, объясняя автору процесс без требования
заранее знать, как ставить сцену. Новый timeline/runner заранее не выбран.

Исследование готовых средств катсцен ·28.10 · без установки/реализации:

Задача этого шага — выбрать основу первого показа. Квестовые ручные gates выше
сохраняются; исследование не объявляет их закрытыми. Проверены официальные docs,
GitHub metadata и узкие runtime owners; GUI аддонов/совместимость в Ember пока
не проверялись. В этом шаге меняется только документация.

Рекомендация: первый эпизод на native AnimationPlayer + существующие Action и
Dialogue. AnimationPlayer уже даёт шкалу времени, transform/property/audio и
Animation Playback tracks для клипов других игроков. Это готовый инструмент
постановки, не необходимость сначала писать свой timeline-editor. Простая
последовательность: укрупнить смотрителя → повернуть к группе → реплика →
вернуть игровую камеру/управление. Длительность чтения определяет игрок, её
нельзя подменять таймером анимации.

Сравнение кандидатов и цена подключения:
- [Godot AnimationPlayer/track types](https://docs.godotengine.org/en/stable/tutorials/animation/animation_track_types.html):
  встроенная шкала, импортированные/записанные клипы и движения камеры. Native
  AnimationLibrary остаётся данными клипа; процедурный жест — у visual owner.
  [AnimationTree](https://docs.godotengine.org/en/stable/tutorials/animation/animation_tree.html)
  нужен при реально необходимом смешивании, а не как условие первой сцены.
- [Phantom Camera](https://phantom-camera.dev/): камеры, follow/look-at, приоритеты,
  плавные переходы и viewfinder; пригодный следующий кандидат для удобства камер,
  а не исполнитель всей катсцены. [FAQ](https://phantom-camera.dev/support/faq)
  указывает Godot4.3+ и MIT. Проверенный release v0.11.0.4 (27.10.2026), main
  9874dfe6882724362ee10b15788f7811beb6371a. Подключение к4.7.2/Ember не доказано.
  Старая [страница timeline](https://phantom-camera.dev/timeline-animation)
  предупреждает об ошибках и ссылается на [#99](https://github.com/ramokz/phantom-camera/issues/99),
  но issue уже закрыт и относится к раннему2D workflow. Не считать это текущим
  багом3D без пробы; брать release, не main, если решим сравнивать камеры.
- [Godot Event Sequencer](https://github.com/Amethyst-szs/godot-event-sequencer):
  визуальные Event Items, вызовы методов/ожидания/ветки/макросы. MIT; проверенный
  HEAD12c7c3e52743116c5b9d3a33b3ff796daa55328a (25.12.2023). README обещает docs
  позже. В event_node.gd свой await-runner, event_finished и end_force через
  is_terminating; это не готовое восстановление камер/input Ember. Прямое
  внедрение дублировало бы нынешний Action owner. Полезен как UX-референс списка
  событий; совместимость/отмена в текущем движке не проверены.
- [Dialogic2](https://docs.dialogic.pro/): удобные visual/text timelines для
  диалогов и VN, события/персонажи/переменные. Docs помечают2 как alpha и
  предупреждают об изменении workflow. MIT; проверенный main
  701b67bbe60114e010476d1685f7de1261091c29. Для Ember это замена уже существующих
  Dialogue/Session/сохранений, не узкое дополнение3D-постановки. Оставить ориентиром
  UX; не устанавливать второй dialogue runner ради движения камеры.
- [Godotion](https://github.com/TheSandemon/godotion): многодорожечный editor
  motion graphics, автор заявляет проверку Godot4.7; MIT. Вводит свои MotionTimeline
  и MotionPlayer; preview/Stop по README оставляют позу шкалы и пишут свойства
  сцены, auto-key работает от выделения. Отложен: это отдельный animation owner
  и требует проверки совместимости с черновиками/Undo/Save Ember, а не готовая
  интеграция квестовых катсцен. Работоспособность аддона нами не проверена.

Найденные места подключения в Ember:
- InteractionUi уже ведёт очередь Action, ожидает диалог/таймер и закрывает её
  при отмене; Player._ui_blocks_movement читает UI, ExploreState владеет наградой/
  прогрессом. Показ должен дать finished/cancelled/skipped прежней очереди,
  а не сам повторно выдавать предметы или запускать отдельный квестовый runner.
- FollowCamera сам пишет transform/lens и читает RMB; FieldEncounter уже имеет
  пример временной entry-camera и snapshot/restore режимов актёров. Катсцена
  требует своего ограниченного владения показом, а не повторного запуска боя
  или Tree.paused на весь мир. Нужно восстановить прежнюю active camera, lens,
  input/process режимы, включая ошибку/выход из сцены/отмену.
- HoshiVisual._process автоматически выбирает idle/walk/run и speed_scale каждый
  кадр. Gesture playback требует временного override у character owner, иначе
  locomotion его перебьёт. Этот шаг не меняет Hoshi/риг/библиотеку motion; первая
  проба — со смотрителем и простым поворотом. Записанные/обычные клипы позднее
  используют тот же AnimationPlayer, процедурные слои согласуются с visual owner.
- EmberVnSceneState с use=cutscene сейчас отвечает за2D backdrop/actors projection;
  это не готовая3D-постановка и не повод переиспользовать название как доказательство.

Проба ракурсов29.10 · сделано без ручной приёмки:
- Автор явно выбрал отдельную лёгкую сцену на время оптимизации main. Это
  временная постановочная проба, не вторая рабочая карта. Сценка смотрителя ниже
  отложена до выбора композиции; Quest/Action/Dialogue и игровая камера прежние.
- `scenes/prototypes/camera_preset_study.tscn` → F6. Два простых манекена и предмет;
  шесть планов: общий, средний, крупный, через плечо/встречный, деталь. Кнопки/1–6
  переключают планы, Tab меняет собеседника, Пробел включает движение Б,
  H скрывает панель, R сбрасывает пробу. Слайдеры дистанции/FOV/высоты/перехода
  действуют до перезапуска; это не сохранение пресета из игрового UI.
- На `ShotRig` в Inspector сохраняются стартовый план/линза/переход и NodePath
  primary/secondary/detail anchors. Marker3D у персонажа задаёт точку композиции,
  у предмета — центр детали. Смена/движение привязанных объектов пересчитывает
  кадр; пустая/исчезнувшая основная цель удерживает последний кадр. Пара и
  встречное плечо сохраняют сторону оси разговора; быстрая смена плана прерывает
  предыдущий переход. Препятствия/автоматическое определение размеров разных
  персонажей в этой пробе ещё не решены; anchors и дистанцию выставляет автор.
- Owner пробы — `scripts/prototypes/ember_camera_preset_rig.gd`; UI только
  `ember_camera_preset_study.gd` рядом. Один обычный Camera3D внутри сцены;
  не новая gameplay camera, не timeline/editor и не schema квестовых шагов.
  Новые зависимости/аддоны не установлены; Hoshi/риги/основная карта не менялись.
- Референс Genshin: просмотрен [кадр диалога с Susan на HoYoLAB](https://www.hoyolab.com/article/14820293),
  [исходное изображение](https://upload-os-bbs.hoyolab.com/upload/2023/01/05/111255608/e85f744e689946d3c2ac71b53bf878f7_6235662398411978888.png).
  Видны два собеседника и свободная нижняя зона под реплику. Это наблюдение
  композиции игрового кадра; внутренние camera presets/код Genshin не изучены
  и не объявлены воспроизведёнными. Средний/крупный/встречные планы — наша
  стандартная постановочная проба, не доказанные численные настройки Genshin.
- [Camera3D Godot](https://docs.godotengine.org/en/stable/classes/class_camera3d.html)
  достаточно для этой пробы. [PhantomCamera3D](https://phantom-camera.dev/core-nodes/phantom-camera-3d)
  разделяет follow/look-at/tween, что пригодно при дальнейшем усложнении; пока
  интеграция host/priority не нужна для сравнения шести простых композиций.
- `tools/test_camera_preset_study.gd`: disposable fixture, Forward+15FPS PASS —
  шесть планов/кнопки, цель в frustum, сторона оси, перенос пары, прерывание
  перехода, пустая/исчезнувшая цель, смена привязки, save/reopen и reset.
  Реальный запуск самой сцены из рабочего проекта Forward+ также без ошибок.
  Кадры просмотрены; исправлены обрезанный общий план, чрезмерные3D-подписи
  и место под реплику. Артефакты: `C:/Users/novos/Documents/Codex/2026-10-29/camera-presets/`.
  Ручные кнопки/слайдеры/темп/композиция у автора OPEN. Редактор документов не
  менялся, его Undo/discard не затронут. Квестовые manual gates сохранены.
- Ближайшее: автор сравнивает ракурсы и постановочную пробу ниже в F6; выбранное
  затем переносим в сценку на единой карте, без второго quest/dialogue runner.

Постановочная проба29.10 · движения на штатной шкале · сделано без ручной приёмки:
- Та же `camera_preset_study.tscn`, не новая сцена. `AnimationPlayer` содержит
  редактируемую восьмисекундную `story_example`: Б подходит/поворачивается,
  посылка поднимается по дуге и опускается на вторую подставку, камера меняет
  планы, появляются титры. Это перемещение/поворот манекена целиком, не готовая
  походка, скелетный жест или привязка предмета к кисти.
- F6 → P или кнопка запуска/паузы; ползунок времени останавливает и показывает
  выбранный момент; P продолжает, End показывает финал один раз, Esc возвращает
  исходные свойства. Повтор сначала восстанавливает исходное, не накапливает
  перемещения. После обычного конца/End финальный кадр остаётся для оценки;
  это исход preview, не завершение квеста. При закрытии сцены свойства также
  восстанавливаются. Во время показа фоновые перемещения и ручные ракурсы
  лаборатории не конкурируют с дорожками. Слайдеры runtime не пишут файл.
- Owner управления просмотром — `scripts/prototypes/ember_story_preview.gd`;
  движения/ракурсы/текст хранятся в native AnimationLibrary внутри `.tscn`.
  Снимок затронутых свойств строится до запуска; отсутствующая цель, loop или
  неподдержанная дорожка не запускают частичный показ. Поддержаны value и
  position/rotation/scale3D; method/audio/animation-playback пока отклоняются.
  Вызовы квестовых наград/флагов не помещать на визуальную шкалу.
- `ShotRig` теперь @tool: preview Camera3D может обновляться и при редакторском
  просмотре дорожек; `preview_in_editor` выключает это при необходимости.
  Исправлено воспроизведённое возвращение камеры назад кадром после snap и
  постоянный перезапуск перехода при анимированном FOV. Камера движется по
  выбранному плану, изменение линзы не начинает переход заново каждый кадр.
- Титры дорожки остаются обычной Label. Настоящий разговор/выбор/ожидание F
  теперь подключены отдельно через прежние DialogueSession/InteractionUi — см.
  «Диалог и история29.10» ниже. Action schema, Hoshi и основная карта прежние.

Как автору передвинуть предмет без кода:
1. Открыть `camera_preset_study.tscn`, выбрать `AnimationPlayer`, в нижней панели
   «Анимация» выбрать **story_example**, не RESET.
2. Раскрыть дорожку **Item → position**, выбрать последний ключ на **4.3с**.
   В Inspector значения ключа поменять X с0.8, например, на1.1. Последнее
   положение удерживается до конца автоматически, второй конечный ключ не нужен.
3. Ключ3.65с — верхняя точка дуги, ключ3с — начало движения. Меняя значения
   и время ключей, менять путь/скорость. `Item → rotation` отдельно задаёт поворот.
4. Ctrl+S → F6 → P/End. Новый конечный X должен быть виден в показе. Esc вернёт
   положение до просмотра, а не перепишет ключи в файле.
5. Для другого объекта выбрать его, поставить время на шкале и нажать ключ у
   Position/Rotation в Inspector; разрешить создание дорожки. Поставить второй
   ключ в другом месте/времени. Для удаления/замены узла проверить путь дорожки.
6. `ShotRig → shot` — дискретные номера планов0–5 (в том же порядке, что кнопки
   1–6); `StoryText/Caption → text` — титры; lens_fov — угол обзора. RESET хранит
   исходную редакторскую позу: при изменении исходной расстановки обновить его
   ключи тоже. Runtime-отмена восстанавливает реальное состояние до P, не RESET.
7. В редакторе выделить `ShotRig/Camera3D` и включить штатный Preview для оценки
   кадра; создание/чтение анимации описано в [Godot Animation introduction](https://docs.godotengine.org/en/stable/tutorials/animation/introduction.html).
   [Property/3D tracks](https://docs.godotengine.org/en/stable/tutorials/animation/animation_track_types.html)
   дают этот путь без установки второго timeline editor.

Проверки/следующее:
- `tools/test_story_preview.gd` в disposable native Forward+15FPS PASS:
  движение/поворот/текст/камера, pause/scrub, skip на трёх фазах, cancel/repeat,
  обычный finish/выход, правка конечного ключа через UndoRedo/save/reopen и
  воспроизведение изменённого результата, отказ неверным дорожкам. Связанные
  шесть camera presets также PASS. Это не проверка физических ходьбы/коллизий.
- В изолированном native editor открыта настоящая сцена/панель Animation,
  выбрана story_example, видны дорожки и результат предпросмотра; @tool камера
  обновляется. Direct seek на оригинальном AnimationPlayer при выбранной RESET
  не заменяет смену анимации в панели Godot. Мышь/вставка ключей/реальный editor
  Undo/discard и удобство для автора остаются OPEN, не подменяются API-тестом.
- Evidence: `camera-presets/test_story_preview.gd.native.log`,
  `test_camera_preset_study.gd.native.log`, `story-editor.log`,
  `story-detail.png`, `story-finish.png`, `story-native-editor.png` в каталоге
  `C:/Users/novos/Documents/Codex/2026-10-29/`. Квестовые gates не закрыты.
- Рекомендованный порядок: авторские перемещения/кадры и реальный диалог с
  ожиданием/выбором → клипы походки/жестов через visual owner → запуск из Quest
  через Action и восстановление игровой камеры/input. Передача/прикрепление
  предмета к руке, звук и мимика — следующие отдельные потребности, не скрытая
  реализация текущего среза. Награды остаются в нынешнем квестовом owner.

Диалог и история29.10 · сделано без ручной приёмки:
- Та же сцена/F6/P: в2.2с анимация ждёт настоящий Dialogue «Посылка», две ветви
  ответа и заключительную реплику. После разговора движение продолжается.
  Esc в разговоре отменяет показ/возвращает позы; End до разговора пропускает
  визуальную часть, но всё равно ждёт ответа. End/ползунок/P внутри разговора
  не обходят решение. В истории Esc сначала закрывает только историю.
- Автор: выбрать **StoryPreview → Dialogue**, назначить свой существующий
  `EmberDialogueResource` из `content/dialogues/`; **Dialogue Time** — момент
  остановки внутри клипа. Текст/варианты редактировать в прежнем Ember Graph,
  затем сохранить Dialogue и сцену. Пример — `camera_story_exchange.tres`.
  Прежняя проба использует одиночные поля; новые сценки получают несколько
  разговорных остановок — «Создание сценки автором29.10» ниже.
- История в обычном InteractionUi: **H**/кнопка «История»; показанные реплики,
  спикеры, вопрос и только выбранный ответ. Можно выделять/копировать текст и
  прокручивать журнал. H/Esc возвращают к той же реплике; F/Enter/ответы во
  время журнала не продвигают разговор и не меняют флаги. Ответы доступны
  кнопками, W/S и1–9; Enter/кнопка продолжает. Main F по-прежнему принадлежит
  Player; в отдельной сцене его направляет в тот же advance только lab adapter.
  Длинный текст реплики прокручивается и новая реплика начинается сверху.
- Transcript owner — `EmberDialogueSession`, последние200 записей в памяти
  данного UI. Запись содержит sceneId/stepId/kind/speaker/text; getter возвращает
  копию. Повторный показ пишет новую увиденную запись, refresh не дублирует её;
  непройденные ветви не логируются. Это текстовый журнал, не перечень команд.
  При смене/создании UI журнал исчезает; привязки к save slots, хранения между
  запусками и отдельного архива всех разговоров пока нет. Gameplay save не менялся.
- `InteractionUi.activate_dialogue()` не заменяет открытую Action queue;
  `dialogue_closed(completed)` возвращает исход прямого разговора один раз.
  Действующие flags/choice/Action owners сохранены. Lab использует отдельный
  экземпляр прежнего ExploreState с persistence/restore off, не авторский save.
  Показ и журнал не являются новыми dialogue/quest executors.
- Референс: [Dialogic History](https://docs.dialogic.pro/classes/subsystem_history.html)
  разделяет простой текстовый log, full events и visited events. Взято только
  разделение transcript/исполнение, аддон не установлен. Для текста использован
  [RichTextLabel Godot](https://docs.godotengine.org/en/stable/classes/class_richtextlabel.html)
  с прокруткой/выделением и bbcode off: содержимое реплики — обычный текст.
- Forward+15FPS1280×900/720: test_dialogue_story_history PASS — checkpoint,
  ожидание/две ветви, реальные key events F/H/Enter/S, signals кнопок, history
  modal/copy/limit, skip/cancel/resume, save/reopen привязки, author flags unchanged.
  При первом signal тесте исправлено удаление нажатой кнопки во время pressed:
  старые controls отсоединяются и queue_free, повторный прогон без ошибок.
  Talk/shop, action queue/reward/wait, visual preview и camera regression PASS.
  Кадры разговора/истории просмотрены, рабочая сцена Forward+ открывается без
  ошибок. Mouse/DPI/ощущение/своя main-проверка остаются OPEN.
- Evidence: `C:/Users/novos/Documents/Codex/2026-10-29/dialogue-history/` →
  native.log,720/native.log,workspace.log, test_talk_shop.gd.log,
  test_action_script.gd.log, test_story_preview.gd.log, test_camera_preset_study.gd.log,
  dialogue-choice.png/dialogue-history-answer.png (также в720/).
- Дальнейшие удобства: архив истории с игровым save и очисткой при New/Load,
  озвучка/повтор голоса, скорость появления текста, Auto с остановкой на выборе,
  skip уже прочитанного. Это отложенные решения, не скрытое автопринятие ответа.
  Удобный набор разговоров/движений и жесты остаются дальше; первая связка
  Action/Quest описана ниже. Сохранённые ручные gates квестов не закрывать.

Квест → сценка → награда29.10 · отдельная проба, main не менялась:
- На той же `camera_preset_study.tscn` добавлена панель **«Груз у берега · финал
  квеста»**. F6 → **«Поговорить со смотрителем»** запускает настоящий
  QuestGiver → Action → сценку → Dialogue/выбор → движение предмета → 3 монеты
  и завершение цели. Повторный разговор идёт по прежней completed route без
  награды. **«Сбросить пробу квеста»** начинает этот изолированный финал заново.
  P остаётся отдельным просмотром анимации, он не выдаёт квестовую награду.
- Это проба финала: meet/visit/place заранее выставлены только в отдельном
  ExploreState с persistence/restore off; используются прежний Quest
  `harbor_cargo.tres` и QuestGiver. Реальные saves/main/старый reward Action
  не менялись. Новый `harbor_cargo_story_trial.tres` используется только здесь:
  play_cutscene → exchange_items(3 coin) → reward flag → status done.
- Добавлен один step в существующую Action schema: **play_cutscene** с
  **presentationId**. Store default/validation/normalization, runtime queue,
  карточный editor и Graph add/title/summary/property path поддерживают его.
  Обычный wait не подходит: он ждёт таймер, а не исход Dialogue/показа.
- Автор: открыть сцену с постановочным узлом; в Action/Ember Graph добавить
  **«Показать сценку»**, выбрать **«Передача посылки»** в **«Сценка на карте»**,
  затем обычные награды/флаги. Сохранить прежним Action Save/Undo маршрутом.
  `StoryPreview.presentation_id` — стабильная привязка, `presentation_name` —
  имя в picker. Один и тот же ID должен встречаться в текущей сцене ровно один раз.
  Список умеет читать non-tool placeholders в native editor. Отсутствующий
  сохранённый ID не заменяется автоматически другим; runtime выдаёт notice.
- Один read projection/resolver — `scripts/ember_story_binding.gd`, общий для
  editor и runtime. Нет нового глобального каталога сценок или quest executor.
  Scene-owned presenter — прежний `ember_story_preview.gd`; настроенную сборку
  теперь создаёт форма из раздела ниже, без ручной сборки sibling nodes.
- InteractionUi скрывает Action overlay, сохраняет очередь/блокировку движения
  и ждёт finished. completed/skipped продолжают её; cancel/error/удаление узла
  останавливают, не отмечают NPC выполненным и не доходят до награды. Callback
  отключается и проверяется serial; старый сигнал не возобновляет новую очередь.
  Даже пустая повреждённая привязка не исчезает при runtime-normalization.
- Вложенный показ использует ту же DialogueSession/историю и ExploreState
  ожидающей Action UI; после показа контекст возвращается. Только один reader
  исполняет Dialogue, второй UI держит Action wait. F main остаётся у Player;
  в lab его направляет адаптер сцены. Пропуск всё ещё ждёт явного ответа.
- При успешном Action-показе в lab остаются финальные позы предметов, а
  параметры ShotRig/титры возвращаются; Esc после результата уже не откатывает
  оплаченный показ. При отмене возвращаются исходные позы. Это не persistence
  перемещений WorldItem. Переключение/возврат Camera3D и RMB у EmberFollowCamera
  проверены для новых сборок ниже; полная main/player/streaming/save integration
  остаётся отдельным gate переноса.
- `test_quest_presentation.gd` Forward+15FPS PASS: picker по имени, validation,
  Undo/Redo выбора, native Action save/reopen, отмена/повтор/обычный конец/skip,
  общая история,3 монеты один раз через NPC route, missing/duplicate ID,
  снятие узла и late callback. Dialogue/history, visual preview/cameras,
  talk/shop/action regressions и Graph parse PASS. Кадр результата просмотрен.
  Авторская мышь/темп/полный маршрут main/cold Load остаются OPEN.
- Evidence: `C:/Users/novos/Documents/Codex/2026-10-29/quest-presentation/`:
  native.log,quest-completed.png,graph-parse.log и test_*.log. В настоящем native
  editor non-tool lookup/picker по имени PASS, native-authoring.png просмотрен.
  Один такой процесс после PASS завершился editor-exit0xC0000005; повтор exit0,
  причина OPEN, fix не заявлен. NATIVE CRASH EVIDENCE — native-crash-evidence.json,
  сохранены fixture/cache/launch/исходный probe и оба лога. Мышь автора OPEN.
- Следующее: ручная оценка этой цепочки; перенос принятого в main после
  параллельных оптимизаций с настоящей камерой/input и world-item persistence.
  Несколько разговорных пауз и создание сборки доступны ниже; походка/жесты
  остаются дальнейшими постановочными срезами.

Создание сценки автором29.10 · сделано без ручной приёмки:

Полезный маршрут:
1. Для первой своей пробы открыть `camera_preset_study.tscn`, переключиться
   в **Ember Graph → Создать сценку**. Если плагин ещё старой версии — перезапуск
   редактора обновит кнопку; рабочую карту для этой проверки не менять.
2. Указать название, **ActorA**, **ActorB**, **Item**. Фильтры ищут имена/пути
   объектов уже открытой сцены; имена отображаются как в дереве, без автоперевода.
3. Например, смещение X1.1/Y0/Z0,4 секунды, общий план. **+ Добавить разговор**
   добавляет время и ссылку на существующий Dialogue; для пробы выбрать «Посылка»
   в1с и2с. Время — время анимации: чтение не отнимает секунды у следующего
   движения. Реплики/ответы править прежним Dialogue/Ember Graph.
4. **Создать и открыть шкалу** создаёт один `StorySceneN` на текущей карте.
   Внутри уже настроены camera rig, AnimationPlayer, Dialogue UI и Presentation.
   Отмена/ошибка формы карту не меняют; создание снимается одним Undo/Redo.
   Сохранить сцену Ctrl+S прежде, чем связывать её с Action.
5. Открывается штатная анимация **story**: два ключа перемещения предмета,
   начальный ракурс и переход к детали. Добавлять промежуточные ключи, поворот,
   менять длительность и ракурсы стандартной шкалой Godot. Для оценки кадра —
   `StorySceneN/ShotRig/Camera3D → Preview`; при необходимости закрепить панель
   анимации булавкой. RESET хранит исходную позу: после ручной перестановки
   исходного предмета синхронизировать начальный ключ и RESET его анимаций.
6. Узел **Presentation → Разговоры по времени / Dialogue Cues** хранит список
   остановок. У каждой — Time и обычный Dialogue Resource; исполняются по времени.
   Пустые ссылки, одинаковые моменты и время вне клипа блокируют запуск.
   Одиночные поля в группе «прежняя проба» нужны только старой лаборатории;
   непустой список имеет приоритет. Новая форма не записывает вторую схему диалогов.
7. В цепочке действия цели выбрать **Показать сценку → своё название**. В пробной
   цепочке **«Груз: сценка перед наградой · проба»** заменить первую сценку,
   остальные шаги награды оставить. Список обновляется при открытии без reload
   документа, прежний выбор сохраняется. Сохранить Action обычным owner.
8. F6 → **Поговорить со смотрителем**. Два разговора должны остановить движение;
   после обоих выдаются3 монеты. Отмена возвращает предмет и не выдаёт награду.
   P в прежней лаборатории запускает старый пример, а не выбранную новую сценку.
   Для ещё одной постановки снова использовать «Создать сценку»: Ctrl+D копирует
   стабильные IDs и не является этим маршрутом создания.

#### Клип участника при сдаче задания05.11

В Ember Graph → **Создать сценку** выбрать участников и предмет, затем в
**Анимация участника** выбрать первого или второго участника и клип. Список
берётся из AnimationPlayer под выбранным постановочным персонажем. Клип из
Blender добавляется в AnimationLibrary персонажа после привязки к его ригу.
Для этой формы подходят клипы с дорожками позиции, поворота и масштаба костей
того же скелета. Исходный AnimationPlayer должен быть без autoplay и не играть.
Один клип начинается с начала постановки; длительность сценки должна его покрывать.
Сохранить карту и поставить **Показать сценку** перед сдачей в цепочке действий NPC.

Builder переносит костные дорожки в прежний AnimationPlayer story через
[Animation.copy_track](https://docs.godotengine.org/en/stable/classes/class_animation.html#class-animation-method-copy-track).
Дорожки остаются редактируемыми на штатной шкале, привязки пересчитываются к
корню карты. Presenter сохраняет и возвращает позы через
[Skeleton3D](https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html)
при завершении, пропуске и отмене. Движение управляемого игрока и передача рига
между AnimationTree и постановкой остаются за границей этого среза.

В disposable Forward+ пробе первого дня выбран локальный Hoshi `idle` из
`motion.res` (Quaternius Idle_Loop, происхождение в `motion-source.json`).
Реальная форма → Undo/Redo → save/reopen → кости двигаются при сдаче матери.
Отмена сохраняет подарок и возвращает камеру/позу; повтор с естественным
концом продолжает диалог и сдачу. Полный маршрут и cold load PASS. Клип
добавляется к финалу только в этой копии. Обычный F6 первого дня использует
разговорный финал. Ручной выбор в редакторе и новый импорт своего клипа OPEN.

Владельцы/границы:
- `ember_story_authoring_dialog.gd` — только pending form, фильтры/ссылки;
  `ember_story_authoring.gd` — builder/validation, без записи файлов. Записывает
  сцену прежний Godot Save; добавление/Undo/Redo идёт только через
  `EmberObjectInspectorActions.create_story_scene` и EditorUndoRedoManager.
  Список authored nodes фиксируется до ready(), runtime dialogue controls не
  попадают в `.tscn`. Action Resource не меняется автоматически при создании.
- `EmberStoryDialogueCue` — native Resource только time + прежний Dialogue.
  `Presentation` нормализует новый список/старую одиночную пробу в один поток;
  прежние Session/history/Action/progress owners не заменяются.
- Привязки относительные, источник движения — реальные узлы открытой сцены,
  ключи лежат в AnimationLibrary внутри её `.tscn`. Смещение задано по осям мира
  и переводится в local transform родителя; поворот/масштаб папок учитываются.
  Камера подстраивается под размеры участников/предмета, фокус персонажа —
  верхняя часть корпуса; close-up не должен обрезать голову тестового манекена.
- Камера сборки не перехватывает вид при создании. На runtime-показе включается
  временно; после завершения/отмены возвращается прежняя Camera3D и прежний флаг
  RMB-input у EmberFollowCamera. Одновременно один показ на viewport. Если
  animatable target исчез, показ отменяется; отсутствующие привязки не запускают
  частичную сценку. Main/streaming/коллизии/ощущение и холодный game-save ещё OPEN.
- Первый срез перемещает визуальный Node3D/меш без динамического физического
  тела/CharacterBody в его ветке. Риги/походка/прикрепление к кисти не изменены;
  motion/physics/persistent WorldItems требуют следующего контракта. Это
  native starter + шкала, не новый полноценный cinematic editor.

Проверено:
- `test_story_authoring.gd` в disposable Forward+15FPS: реальная форма и
  независимые фильтры, validation/cancel/create, Undo/Redo/save/reopen/discard,
  authored-only serialization, world-space смещение при rotated/scaled parent,
  защита physics owner, свежий Action picker без потери старого выбора,
  два разговора по обычному времени/skip, reward/cancel/camera/input rollback,
  mutual exclusion и head-in-frame close-up PASS.
- Native editor: та же форма → EditorUndoRedoManager → Undo/Redo → Save/reopen →
  AnimationPlayer **story** PASS, exit0; форма и шкала просмотрены. При просмотре
  уменьшены высота selectors и убран перевод имени Item в «Элемент» через
  [Node.auto_translate_mode](https://docs.godotengine.org/en/stable/classes/class_node.html#class-node-property-auto-translate-mode).
  Fixture warning Scan thread aborted вызван QA shutdown во время scan, не AV.
  Старый editor-exit AV остаётся открытым; успешный текущий выход не является fix.
- Связанные quest presentation/dialogue history/visual preview/camera/talk/shop/
  action gates PASS; финальный plugin parse PASS. Рабочая проба открывается
  Forward+ без ошибок. Input мышью/125%/узкое окно/своя сборка/main — автор OPEN.
- Evidence: `C:/Users/novos/Documents/Codex/2026-10-29/story-authoring/` →
  native.log,editor.log,native-form.png,native-timeline.png,authored-completed.png,
  plugin-parse.log/workspace.log и test_*.log. Новых рабочих карт/аддонов/сейвов
  автора не создавалось; main и риги не менялись.

Цель «Купить»29.10 · сделано без ручной приёмки:
- В существующей карточке цели Ember Graph и полной форме задания выбрать
  **Купить → количество → лавка → товар**. Список товаров берётся из выбранной
  лавки; смена лавки очищает товар. Отсутствующие сохранённые привязки видны,
  validation не позволяет сохранить неизвестный товар/лавку или товар вне её
  ассортимента. ID события покупки вводить не требуется.
- Нормализованный Quest objective: `progressMode="purchase"`, `purchaseShopId`,
  `purchaseItemId`, `requiredCount`; `flagId` остаётся личным числовым save key.
  Catalog использует прежнюю numeric projection/dependencies, журнал и HUD
  показывают количество. Это успешные покупки, а не проверка текущей сумки:
  продажа/использование товара не отнимает уже полученный прогресс.
- Считается только успешный `ExploreState.buy` по нужным shop/item, пока квест
  active и цель доступна. Покупки до принятия/предыдущей цели не копятся;
  завершённая цель не растёт. Одна покупка не закрывает сразу две последовательные
  цели: updates строятся до изменения flags. Текущая лавка продаёт по1 предмету
  за подтверждение; bulk purchase не вводился.
- Inventory/stock и quest flags меняются до единственного autosave существующей
  успешной операции. Отмена окна/нехватка денег/запаса/полная стопка, другой
  товар/лавка, подбор/продажа не засчитываются. Исправлен прежний случай полной
  стопки: `EmberEconomy.buy` возвращает stack_full без списания денег/запаса.
  Replay журнала покупок/новый save owner не вводились; загрузка не порождает событие.
- Owners: QuestStore/QuestCatalog/ExploreState/Economy/InteractionUi прежние;
  общий небольшой `ember_quest_purchase_fields.gd` рисует catalog selectors для
  обоих существующих редакторов, не исполняет цели и не пишет Resources.
- Проба на прежней `camera_preset_study`: кнопка **Начать / сбросить чай ·30 монет**,
  затем **Чай · поговорить со смотрителем** → дочитать F → **Открыть лавку у причала**.
  F покупает выбранный товар, W/S выбирают, A/D покупка/продажа, Esc закрывает.
  Купить2 чая цинсинь по6 → вернуться к смотрителю → прежняя сценка/выбор →
  награда3 монеты, итог21. Повтор NPC не даёт награду. Отдельное lab-state без
  persistence; кнопка сброса заменяет только его сумку/tea flags/stock. Старую
  пробу доставки тестировать отдельно её сбросом; main/save автора не меняются.
- Native Resources пробы: `story_tea_errand` Quest, `story_tea_shop` Shop,
  `story_tea_start/reminder/reward/complete` Action, отдельные `*_talk` Dialogue.
  Presentation использует существующий cargo_delivery; новой карты/runner нет.
- `test_quest_purchase.gd` PASS: ранние/root/locked покупки, два последовательных
  счётчика, неверные item/shop, grant/sell/cancel/funds/stack,1/2→2/2/clamp,
  один autosave покупки и его реальная запись/загрузка в изолированном user://,
  обе формы/validation, Graph Undo/Redo/native Resource save/reopen/discard,
  журнал/HUD count, NPC→обычная лавка→сценка→награда один раз.
  Связанные test_talk_shop/test_action_script/test_quest_state PASS.
- Forward+ native карточка/лавка/1/2 просмотрены, exit0; свидетельства:
  `C:/Users/novos/Documents/Codex/2026-10-29/quest-purchase/` → purchase.log,
  native.log, native-authoring.png, native-shop.png, native-progress.png,
  test_*.log, fixture-path.txt. Ручные мышь/input/узкое окно/свой Quest workflow
  OPEN. Подключение постановочной пробы к main — отдельный оставшийся gate.

Цель «Собрать и передать»29.10 · сделано без ручной приёмки:
- В карточке цели Ember Graph/полной форме выбрать **Собрать и передать →
  количество → предмет**. Счётчик показывает актуальную сумку, включая предметы,
  найденные до поручения:3/3 → выбросить/продать/использовать1 →2/3. Подбор снова
  возвращает3/3. Достигнутое количество не завершает цель само по себе.
- В той же Graph-карточке назначить существующему/созданному NPC реплику и награду
  прежними controls. Отдельный список отдаваемых предметов для этого режима скрыт:
  источник item/count — сама цель. Напоминание остаётся отдельным пассивным
  разговором; выбор ответа с выдачей результата здесь не смешивается с передачей.
  Полная форма Resource настраивает описание/предмет/число; NPC назначается в Graph.
- Schema Quest: `progressMode="handover"`, `handoverItemId`, `requiredCount`;
  `flagId` — прежний bool завершения. Число в сумке не дублируется в flags/save.
  `QuestCatalog.projection/visible_projections` принимают inventory явно; Journal
  и Tracker передают текущую сумку и показывают count. После сдачи done сохраняется,
  даже когда предметов больше нет; projection завершённой цели показывает3/3.
- Прежний compiler quest-события выдаёт Action `handover_quest_items` с
  questId/objectiveId/rewards. Этот шаг нужен вместо копии обычного exchange:
  читает текущие item/count из Quest, проверяет active/available/not done и
  завершает именно этот этап. Правка числа после назначения NPC не оставляет
  устаревший costs в цепочке. Событие напрямую из Dialogue не записывает flag:
  Graph направляет автора к разговору NPC; apply_authored_flag запрещает обход
  сдачи через true/done. Debug/restore set_flag остаётся прежним низким уровнем.
- Runtime остаётся в Action/InteractionUi/ExploreState. Существующий all-or-nothing
  exchange проверяет предметы и вместимость награды; лишь затем одновременно
  меняет inventory/goal flag, до signals/единственного Action autosave. Отмена
  разговора, нехватка, недоступная/закрытая цель, пропавшая привязка и переполненная
  награда ничего не расходуют и не завершают. Повторный запуск не выдаёт награду.
- ActionStore/карточка цепочки/Graph поддерживают новый шаг; target picker показывает
  названия задания/цели. Store валидирует target/rewards и pending Quest в одной
  Undo-команде создания NPC. UsageIndex и маркер распознают успешную сдачу как
  выполнение цели. Item/count/rewards не вписываются в анимационные дорожки.
- Количество одной сдачи ограничено вместимостью стопки выбранного предмета и999
  (контракт exchange); более крупное требование отклоняется validation. Многократные
  частичные взносы/несколько типов предметов/другой контейнер — не входят в срез.
- Проба на прежней camera_preset_study: **Начать / сбросить ракушки** →
  **Ракушки · поговорить со смотрителем**, дочитать F → **Подобрать одну ракушку**×3.
  Выбросить одну →2/3, подобрать →3/3; снова NPC/F → предметы исчезают из сумки,
  награда5монет, «Передано · выполнено». Повтор NPC не увеличивает награду.
  Можно подобрать до поручения или попытаться сдать2/3. Подбор/выбрасывание в lab
  вызываются кнопками через настоящие world-item commands; отдельной физики/игрока
  в этой сцене нет. Меши ракушек показывают оставшиеся records на втором пьедестале.
  Lab-state без persistence, реальный save автора и основная карта не меняются.
  Пробы доставки/чая/ракушек используют одну lab-сумку: запускать по отдельности
  соответствующей кнопкой сброса, не считать три панели независимыми сохранениями.
- Native fixtures: Quest story_shell_handover, Action story_shell_start/deliver/
  complete, отдельные Dialogue *_talk. Сцена одна прежняя, не новый quest runner.
- `test_quest_handover.gd` PASS: pre-owned/live/drop/pickup/3→2→3, HUD, отсутствие
  автоматического done, отказ raw flag, cancel/нехватка/закрытая цель/переполнение
  награды без потерь, один согласованный observer snapshot и один autosave,
  реальная запись/load до и после сдачи, повтор без награды; обе формы/validation,
  Graph Undo/Redo/save/reopen/discard; настоящее NPC bind Undo/Redo, Action card
  roundtrip и изменение requiredCount3→2 после привязки. Прежние purchase/talk_shop/
  action_script/quest_state и quest_npc_options PASS.
- Forward+ форма и цепочка3/3→2/3→сдача просмотрены, exit0. Evidence:
  `C:/Users/novos/Documents/Codex/2026-10-29/quest-handover/` → handover.log,
  native.log, native-authoring.png/native-ready.png/native-dropped.png/
  native-completed.png, npc-regression.log и test_*.log. Ручной input/мышь/125%/
  узкое окно/свой Quest workflow и main остаются OPEN. Прежний editor-exit AV
  постановочной пробы не объявляется исправленным этим срезом.

Прежний предлагаемый контракт сценки смотрителя, отложен до выбора ракурсов:
1. На существующем NPC основной карты показать приближение камеры, поворот NPC,
   одну обычную реплику через нынешний Dialogue и возврат. Без новой карты,
   платной зависимости, изменения рига или полноценного нового редактора.
2. Визуальные дорожки — native AnimationPlayer/AnimationLibrary. Связь показа с
   Action/ожиданием реплики проектировать по действующей очереди; точную schema
   нового шага не утверждать до этой пробы. Call Method track не заменяет await
   чтения диалога; в editor preview такие calls не выполняются.
3. Рекомендуемое правило для согласования: «Пропустить» завершает показ и даёт
   обычное продолжение Action один раз; отмена/ошибка/выход не засчитывают этап.
   Награда/quest flags остаются за пределами анимационных method tracks.
4. [AnimationPlayer.seek](https://docs.godotengine.org/en/stable/classes/class_animationplayer.html#class-animationplayer-method-seek)
   в конец не выдаёт animation_finished; skip/cleanup должны иметь явный исход.
   Async callbacks отменённого показа не могут возобновлять очередь позже.
5. Проверка: native Forward+ показ/чтение/возврат и пропуск на разных фазах;
   cancel/repeat/выход из сцены без зависшего input/камеры/повторной награды;
   authoring Undo/Redo/save/reopen/discard для затронутого пути. Ручная камера/
   темп и простота расстановки — автор. Пока нет нового runtime PASS или GUI-пробы.

Вторая собранная цепочка «Груз у берега» ·28.10:
- `content/quests/harbor_cargo.tres`, `prefabs/items/harbor_cargo_quest.tscn`,
  один instance `Map/Props/HarborCargoQuest` в landscape_compact. Смотритель
  (112,6,280) → найти ящик (112,7.15,328) → F взять/поставить на золотую
  площадку (112,6,376) → вернуться за3 монетами. Прежний квест не изменён.
- Собрано прежними ObjectInspectorActions/Quest/Dialogue/Action owners:
  разговор открывает цепочку, enter-зона/settle-зона завершают свои этапы,
  NPC во время пути только напоминает, reward Action ждёт конца разговора,
  выдаёт монеты и завершает задание. Повторный разговор использует done-route.
- Рамка площадки — сохранённая геометрия по поверхности main, без нового
  runtime или изменения terrain. Смена рельефа потребует поправить эту декорацию.
- `test_quest_harbor_errand.gd` в disposable fixture: композиция через authoring
  owners → PackedScene/reopen → отмена/напоминание/реальный вход/F/settle →
  cold save/load → отмена награды/3 монеты/повтор PASS в Forward+.
  Native RAM-участок настоящей main прошёл ту же цепочку, кадры просмотрены.
  Проверка всех новых production Resources/ссылок/prefab PASS; это не ручная
  приёмка и не полный старт/проход всей карты. Доказательства — Test Plan.
- Напоминания и rewards теперь назначаются из карточки цели (I3.14), существующие
  harbor_cargo_wait/reward читаются формой без миграции. Самостоятельная сборка
  автором всей цепочки из карточек без технических ключей ещё не проверена.

Текущий срез «ящик → зона»:
- Найдены WorldItem3D/WorldItems: физическое тело, pickup_id и сохранение положения
  уже существуют. Готового игрового переноса/толкания в этих owners не найдено.
- Добавлен наблюдатель `ember_quest_object_zone.gd`: кандидат — прежнее физическое
  тело с нужным pickup_id, целиком внутри box-зоны, не в руках, с малой скоростью
  и коротким временем стабилизации. Завершение через прежний apply_authored_flag,
  не второй исполнитель квеста; нынешние prerequisites остаются обязательными.
- `test_quest_object_zone.gd` в disposable headless fixture PASS: границы целого
  объекта/неверный ID/состояние carried, prerequisite, реальное overlap после
  physics steps, стабилизация и сохранение уже зафиксированного результата.
  Это узкая проверка наблюдателя; полный игровой/редакторский сценарий проверен ниже.
- Автор выбрал F взять/повторный F поставить. Перенос добавлен в прежний
  WorldItem3D/WorldItemInteract/Player: carryable item остаётся world_items record,
  не попадает в инвентарь. Player направляет F прежде всего удерживаемому предмету;
  направление соответствует последнему движению. Поза рук/анимация не реализованы.
- «+ Ящик и отмеченная зона» в событийной карточке Graph создаёт составной объект
  на открытой карте, рядом с выбранным объектом/player_start. Plugin проверяет
  сухую поверхность у ящика и зоны; созданные узлы затем двигаются нативными gizmos.
  `create_quest_object_placement` пишет Quest и создаёт узлы одним Undo. На кнопку
  повторно — переход к уже созданной зоне; несколько наборов для одной цели блокируются.
  Если у цели уже есть Action/Dialogue writer, plugin просит добавить отдельную цель.
- Первый подбор ящика без зависимостей начинает его задание — HUD получает active.
  У зависимой цели старт задания остаётся у прежнего источника. Default текст цели
  заменяется на «Поставить ящик в отмеченную зону»; собственный текст сохраняется.
- Перед постановкой проверяются стена, опорная поверхность и свободный объём;
  занятое место не выпускает ящик из рук. После постановки включается прежняя
  физика/коллизия и захватывается позиция. Цель требует покоя0.35с и полного
  попадания bounds с допуском0.15 единицы на контакт физического пола. Уход из
  зоны после фиксации не отменяет пройденный этап. Это первая проба, не бросок.
- Положение/вращение остаются у прежнего world_items/save-v2 owner. Состояние
  «в руках» — временная weak-ссылка; при load предмет восстанавливается в мире
  по последней позиции, а не привязывается к рукам. Metadata старого носителя
  очищается при restore/выходе. Старые бутылки/ракушки по-прежнему подбираются.
- Облик: новый `content/voxel_models/quest_carry_crate.tres` и производный
  `prefabs/voxels/meshes/quest_carry_crate_block.res`, построенный штатным
  EmberVoxelPrefab. `quest_crate` item/visual используют этот Source-derived mesh.
  Старый vox_crate_1 оказался похож на столик и здесь не используется.
- `test_quest_crate_placement.gd`: Graph-кнопка → набор → Undo/Redo → F перенос
  → отказ занятого места → постановка → завершение → save/cold load → scene
  roundtrip/ID/невключение runtime Pickup helper → clear_history PASS в Forward+.
  `test_quest_object_zone.gd` остаётся PASS; прежний world-item цикл PASS. Его
  синтетические props с пустым ID явно не объявляются external imports; production
  VoxelProp/соседний world-editor по этой причине не менялись.
- Возможность подключена к Ember Graph основной карты; авторский main-файл не
  переписывался. Автоматический UI/physics/save прогон — disposable fixture, кадры
  `crate-start.png`, `crate-held.png`, `crate-placed.png`/`crate-native.log` в прежней
  внешней папке. Native plugin parse PASS. Ручной gate на main: создать из карточки,
  Ctrl+S/reopen/F5 → пройти перенос/F/зону, оценить подсказку/скорость/расположение.
- Физический ориентир: [Godot Area3D](https://docs.godotengine.org/en/stable/classes/class_area3d.html)
  обновляет пересечения на physics step; не проверять успех сразу после телепорта.
  Held/settle сейчас проверены контролируемым физическим fixture, не руками автора.

Толкание, бросок и возврат29.10 · сделано без ручной приёмки:
- Автор выбрал F взять/поставить, G бросить по направлению персонажа с постоянной
  силой. Маленький ящик carryable+pushable; большой pushable без carryable, F не
  превращает его в предмет сумки. Толкание — контакт прежнего CharacterBody с тем
  же RigidBody; бросок — одиночный импульс после проверки места и стены до руки.
- Единственный WorldItem3D хранит authored `item_mass`, `visual_size`, `pushable`,
  `return_radius`. Масса применяется к прежнему RigidBody.mass; визуал и collider
  производятся прежним путём. Placement settings переносят поля при восстановлении
  тела; save-v2/worldItems не расширялись. При load скорости нулевые, перенос снят.
- У плиты в прежней общей карточке: «Нужный вес» (0 сохраняет старый режим) и
  «Вес персонажа» (0 исключает персонажей). Суммируются спокойные RigidBody.mass,
  удерживаемые предметы исключены; выбранный конкретный ящик остаётся фильтром.
  Порог/вклад персонажа проходят Model validation → Circuit/Components → Workspace
  → прежние Actions/Undo/.tscn, без второго контроллера или владельца сохранения.
  Сумма относится к телам внутри объёма плиты; передача веса высокой башни через
  цепочку контактов вне этого объёма пока не моделируется.
- Один `ember_world_recovery.gd` Area3D добавляется ExploreScene: общий killbox ниже
  `recovery_floor_y` (по умолчанию −256), проверка перескочивших границу тел раз в0,2с.
  Начальная регистрация и node_added вместо постоянного обхода всей карты.
  WorldItems возвращаются своей командой, прочие RigidBody — к позе регистрации;
  персонажи — ко входу текущей карты без изменения HP/партии/квестов. Скорости и
  ссылка удерживания очищаются. Это техническое возвращение, не возрождение после боя.
- `return_radius=0` отключает ограничение удаления; у пробных и harbor-квестового
  ящиков320 world units (около20м). Anchor — исходная authored-поза; возврат не
  создаёт предмет повторно и не выдаёт награду. Новый ящик из Graph получает тот же
  предел. У обычных выброшенных предметов точка — место появления; после cold load
  их текущая сохранённая поза, а для записи ниже killbox — вход карты. Отдельная
  история anchors динамических drops между загрузками не вводилась.
- Main подключает `prefabs/items/physical_crates.tscn` в Map/Props/PhysicalCrates,
  центр(-56;15,2;520), плита(-32;15,2;456). Маленький весит0,25, большой1, порог0,5,
  персонажи не учитываются. Достаточны большой либо два лёгких груза. Дубли набора
  требуют новых pickup_id и circuit_id; автоматический независимый клонировщик не добавлялся.
- `test_physical_crates.gd`: F/G и полёт тела, реальное толкание движением игрока,
  сумма весов/исключение персонажа, radius/killbox/missed crossing/обычное RigidBody,
  возврат героя без лечения, save/cold load, поля UI/Undo/Redo/source reopen PASS
  в Forward+. Прежние crate placement, world-item cycle и mechanism scope PASS.
  Геометрия скопированного участка main: оба ящика успокоились на прежней smooth
  поверхности, большой включил плиту PASS; кадры просмотрены. QA-копия без props и
  авторских material IDs, не приёмка полного main. Evidence:
  `C:/Users/novos/Documents/Codex/2026-10-29/physical-crates/`.
- Открыто: своё F5 на полном main, мышь/125%/сила и дальность броска/тяжесть толкания,
  совместимость со streaming. Разрушение, анимации рук и баланс весов не входят в срез.
- Основание встраивания: [Godot RigidBody3D](https://docs.godotengine.org/en/stable/classes/class_rigidbody3d.html)
  — force для длительного контакта, impulse для однократного броска;
  [CharacterBody3D](https://docs.godotengine.org/en/latest/classes/class_characterbody3d.html)
  — контакты move_and_slide; [Area3D](https://docs.godotengine.org/en/stable/classes/class_area3d.html)
  — пересечения на physics step. Не вводились новая физика, renderer или save owner.

Столкновения ящиков и первый перенос в бой29.10 · сделано без ручной приёмки:
- Согласовано автором: разрушаемый и прочный переносимые ящики; оба наносят урон
  при броске в противника. Разрушаемый ломается также при сильном контакте с землёй/
  стеной; прочный остаётся целым и снова поднимается. Размер/масса и breakable независимы.
- Main `Map/Props/PhysicalCrates`: прежний SmallCrate разрушаемый, новый SturdyCrate
  того же размера/массы прочный; LargeCrate остаётся только толкаемым.
  F взять/аккуратно поставить, G бросить. Native контакт использует impulse/mass,
  threshold36 world units/sec (пробное число), deferred вызов прежнего destroy/
  break-effect owner. Спокойный контакт не разрушает; непрочные тела имеют до8
  контактов, остальные сохраняют0. `break_impact_speed`/`throw_damage` — exports
  рядом с прежним breakable, placement settings/reopen сохраняют их.
- Первый боевой сценарий — in-place FieldEncounter берегового боя: переносимый
  одноклеточный ящик (visual_size<=16), уже в руках либо на свободной клетке поля.
  Исходное тело приостанавливается/скрывается; тот же pickup_id проецируется в
  прежние battle units/holds. Вход с предметом даёт прежние Бросить/Опустить/
  Удерживать и защищаться. Ящики не получают ходов и не считаются противниками
  для victory. Прочный после попадания занимает ближайшую свободную клетку,
  его можно повторно поднять прежним lift_throw. Подъём неподвижного ящика без RNG.
- Враг получает урон через прежний resolver/preview=commit; базовая сила предмета8
  пока пробная. Промах не наносит урон врагу, но выпускает предмет и соблюдает
  прочность: разрушаемый всё равно разбивается при приземлении, прочный остаётся.
  Уничтожение показывает прежние8 косметических фрагментов.
- `_world_items` меняется только при подтверждённой victory в ExploreState;
  FieldEncounter сообщает мировые позиции, Transition сохраняет их вместе с HP/
  loot/flags. Retry заново берёт начальный battle snapshot, тело остаётся тем же.
  Authored разрушение сохраняет count0, уничтоженный dynamic drop удаляется.
  После возврата реальный прочный ящик снова доступен для F, hold восстанавливается,
  если герой закончил бой с предметом. Второго save или renderer нет.
- Owners: WorldItem3D/ExploreState/FieldEncounter; `ember_combat_world_items.gd` —
  только value adapter. CombatPrototype/StateSchema/CombatLab/Grid3D расширяют
  прежние пути. Schema допускает только идентифицированные world_item:* объекты,
  не подменяет ими hero/enemy. Внешние UI команды/мышь и ощущение автором OPEN.
- `python tools/run_shore_combat_tests.py --native --test test_combat_world_items.gd`:
  weak/strong physical impact, два типа/экспортные поля scene reopen, удержание при
  входе, occupied-cell hit/miss, отсутствие хода предмета, повторный подъём/постановка,
  Retry без потери/копии, victory/реальный F/cold autosave и dynamic tombstone PASS.
  Native held/throw/return кадры просмотрены. Related physical crates, ActionPlan,
  vertical rules (обычные бойцы/AI lift) и обычный shore combat regression PASS.
  Evidence `C:/Users/novos/Documents/Codex/2026-10-29/crate-combat/`.
- Граница: это первая связка переносимого ящика с текущим in-place боем.
  Толкание/весовые плиты внутри боевого snapshot, большие многоклеточные грузы,
  таймеры удержания/формула силы и переход с заменой сцены остаются отдельными gates.

Замечания автора после ручного QA03.11 · исправлено технически,ручной вид/ощущение OPEN:
- Общий `WorldItem3D._sync_carried_pose` сразу при F,каждый physics tick и после
  resume_after_combat выставляет предмет надкапсулой героя с учётом низа его mesh.
  Горизонтальное положение совпадает с героем,yaw следует interaction_forward;
  pickup pitch/roll сбрасываются,масштаб сохраняется. Нового save owner/physics нет.
- Stress создавал16копий SturdyCrate,ломаемого типа там не было. В ручном QA два
  из существующих16тел перемещены к старту,подписаны и имеют разные breakable/impact
  настройки;placement settings сохраняют тип для восстановления. Основная карта не
  менялась. Carry fix принадлежит общему runtime,Ctrl/Shift/новая расстановка — QA.
- Native test_physical_crates:новая регрессия tilted pickup→head/yaw/move/combat resume,
  прежние F/G/вес/void/save/load/Undo/reopen PASS;test_world_strike guards и cold save PASS.
  Ручной gate:F→поворот→поставить/бросить→удар/разрушение на QA и затем main/F5.
  Evidence — Performance03.11 → «Пункт2 после отдыха»;не считать авторской приёмкой.

Удар и разрушение29.10 · сделано без ручной приёмки:
- Согласованный срез: ЛКМ в игровом окне, один удар разбивает маленький ящик.
  Дуга перед персонажем — временный отклик; риг/оружие/Hoshi не менялись. F взять/
  поставить и G бросить сохраняются. В руках удар заблокирован; cooldown350мс.
  Большой и квестовый harbor-ящики неразрушаемы в этой пробе.
- Player._unhandled_input оставляет приоритет GUI. world_strike проверяет прежние
  UI/defeat/combat/flight блокировки, ищет одну цель перед героем и проверяет лучом
  стену/другие тела. receive_world_hit — вход предмета, пригодный для будущей кучки
  листьев; это ещё не общий боевой damage resolver и не атака по персонажам.
- WorldItem.breakable и break_effect — authored exports в .tscn, переносятся через
  прежние placement settings при восстановлении тела. Единственный ExploreState
  destroy_world_item пишет count0 (для authored item) либо убирает dynamic drop,
  отправляет один progress_changed/autosave. Повтор — отказ без save/награды.
  Коллизия/подсказка убираются сразу, тело удаляется; плита теряет груз на physics step.
  Cold load и killbox не восстанавливают предмет с count0. Инвентарь не меняется.
- Разрушение — восемь крупных частей существующего voxel Source, а не восемь
  заменяющих кубиков. Bake разделяет occupancy по октантам и строит закрытые faces
  прежним VoxMesher с исходной палитрой. В Resource.to_definition нужен вложенный
  `.model`; тест проверяет цвета и source SHA. Source/авторская геометрия не пишутся.
  `tools/build_crate_break_effect.gd` создаёт `prefabs/items/quest_crate_break.scn`;
  при изменении исходной модели нужно заново выполнить bake и проверить результат.
  На ударе remesh/voxelization нет. Импорт произвольных объектов не расширялся:
  нынешний MeshImport ограничен одним статичным GLB/материалом и bounded grid.
- Cosmetic effect:8 MeshInstance на общих baked meshes, короткая баллистическая
  подача/проверка пола, удаление через1,1с, максимум4 активных эффекта. Обломки
  не RigidBody, не предметы, не давят на плиту и не попадают в save. Основание:
  [Godot CPU/physics optimization](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html)
  рекомендует ограничивать физические тела и сложность коллизий. Свободное вырезание
  вокселей/разрушение основной Surface/HP предметов не вводились.
- Main использует прежний Map/Props/PhysicalCrates, маленький ящик явно breakable.
  До разрушения стоит сохранить ручной slot, если нужна повторная проба: отсутствие
  ящика сохраняется. Автоматического повторного появления и добычи нет.
- test_world_strike.gd Forward+ PASS: реальный engine mouse-event API/GUI priority,
  открытая сумка, wall/reach/held/big/combat guards, source palette/hash, release
  плиты/промпта/тела, один autosave/cold load/no reward, budget и cleanup. F/G/вес/
  возврат и прежний quest crate placement Forward+ PASS. Бounded копия геометрии
  участка main: strike/цветные обломки/cleanup PASS, нативные кадры просмотрены;
  без props/material IDs основной карты, не приёмка полного main. Evidence:
  `C:/Users/novos/Documents/Codex/2026-10-29/world-strike/`.
- Автор отложил ручную проверку до завершения параллельной оптимизации. Мышь/
  ощущение/полный main/weak-PC OPEN; другой чат оптимизации не менялся. Следующий
  игровой срез листьев описан ниже; ручные gates ящика этим не закрываются.

Кучка листьев29.10 · сделано без ручной приёмки:
- ЛКМ в прежнем world_strike или вход управляемого персонажа в кучку разметает одну authored Area3D, открывая уже лежащий
  под ней предмет; F использует прежний WorldItem pickup. Находка в пробе — пустая
  бутылка, чтобы не добавлять ракушку в квестовый счётчик. На ударе нет inventory grant,
  генерации случайной добычи или создания нового тела. Через ту же сцену позднее
  можно назначить другой существующий item с worldScene; новый catalog не вводился.
- `scripts/ember_leaf_pile.gd`: revealed_flag_id/scatter_effect в .scn, проверка
  непустого ключа/повтора/combat, прежний apply_authored_flag сохраняет раскрытие
  с quest dependency guard. PileVisual скрывается и Area убирается из hit layer;
  корень остаётся видимым для дочерней находки. WorldItem.available_flag_id ссылается
  на тот же ключ. ExploreScene._refresh_world_items обновляет вид/коллизию и
  восстанавливает тело после load, без второго владельца spawn или save.
  Проход29.10: та же Area мониторит layer2, body_entered принимает только EmberPlayer;
  deferred вызов прежнего receive_world_hit выполняется после physics query flush.
  Направление разлёта — горизонтальная скорость входящего персонажа. Мониторинг
  сохраняется после раскрытия: загрузка целой кучки под стоящим игроком не создаёт
  искусственного повторного входа. Следующее реальное пересечение снова доступно.
  Грузы/посторонние тела и combat lock не раскрывают кучку; отдельного tick/polling нет.
- Состояния: целая кучка/скрытый pickup → разметена/доступный pickup → разметена/
  pickup count0. Каждое читается прежними flags/worldItems v2. Повторный удар ничего
  не выдаёт и не сохраняет снова; после подбора ни load, ни killbox не создают новую
  находку. Загрузка более раннего slot возвращает прежнее состояние. Бесконечного
  восстановления ресурсов, случайности, реакции на ветер/огонь нет.
- WorldItem.refresh_availability теперь возобновляет физику существующего скрытого
  тела при повторном открытии доступности, сохраняя запрет на thaw до готовности
  мира и во время переноса. Проверено переключением старого/открытого save, когда
  тело ещё существует, и восстановлением после уже выполненного подбора.
- `tools/build_leaf_pile.gd` готовит два производных native assets:
  `prefabs/items/autumn_leaf_pile.scn` (один mesh/240 плоских карточек/480 triangles,
  одна Area) и `autumn_leaf_scatter.scn` (все240 карточек в4 MultiMesh batches). По поправке автора
  гранёная форма заменена рисованными листьями на прямоугольных плоскостях: нижний
  слой, заполнение середины и редкий край лежат под разными углами. Отдельный лист
  не имеет толщины/изгиба; объём кучки получается расположением карточек. Центр
  поднят примерно до11 world units; прежняя высота была около5.
- Artwork source — `content/material_studies/foliage/autumn_leaf_atlas_v2.png`,
  оригинальный transparent atlas4 вариантов, создан built-in image_gen; точные
  generation/edit prompts — соседний `.prompt.txt`. Builder сохраняет одну общую
  native texture `.res` с прежними tree alpha-safe mipmaps, обе сцены ссылаются на неё; runtime не зависит
  от импорта PNG в авторском editor cache. Рисунок упрощён до крупных мультяшных
  пятен по принятому maple atlas. Общий shader — `ember_tree_leaf_cards.gdshader`,
  прежние foliage light/теневой отклик; alpha scissor0,4, double-sided, linear mip/aniso.
  Remesh на input и физические тела для каждого листа не добавлялись. По замечанию
  автора насыщенность кучки сближена с деревом: общий двухцветный ramp #c7a15c/#9a683c,
  сила100. Прежний PNG v2 сохранён; оба цветовых варианта приняты автором по кадрам.
  Дальнейшее приглушение автор подберёт сам; освещение/full main/ручной ввод OPEN.
  Управление окраской дерева — Terrain Authoring → «Цвет листвы29.10».
- Временный scatter использует прежний ember_world_break_effect: для листьев
  lifetime2,8с/gravity24/launch0,9; crate defaults1,1с/80/1/0,22 прежние.
  Каждый лист начинает движение из точной исходной позы/UV; экспортированные позы
  заполняют отдельный instance buffer при play, не зависят от headless bake GPU state.
  Полный размер до последних0,5с, затем плавное уменьшение. Девять ray samples земли
  только при старте, посадка косметическая по их интерполяции; нет ray на каждый кадр.
  Один общий предел4 активных эффектов, максимум960 летящих листьев/16 batches,
  без saved bodies. При превышении бюджета старейший эффект завершается.
  Кучка не имеет собственного покадрового цикла; находка использует прежний
  WorldItem/physics, доступность обновляется на flag/save events.
- Main: Map/Props/AutumnLeafPile, центр(-88;15,1;440), рядом с PhysicalCrates.
  Рядом Map/Props/AutumnMaple(-136;14,674;408): обычный библиотечный
  `vox_painted_maple_autumn`, Source/Recipe/prefab прежних owners. Цвет «Золотая осень»
  изменён через существующий foliage_color, форма/wood collision клёна сохранены.
  Этот вариант сохранён. AutumnMaplePalette(-40;15;408), `vox_painted_maple_autumn_palette`
  показывает спокойную двухцветную окраску прежнего maple atlas/веточек.
  Builder `tools/build_autumn_maple.gd`; вариация доступна в прежней библиотеке Объекты.
  Flag `autumn_leaf_pile_revealed`, pickup ID `autumn_leaf_bottle`; при независимом
  дублировании назначить новые flag и pickup ID и сохранить одинаковую gate-ссылку
  у Root и HiddenPickup (editable children стандартного Godot). F6 самого prefab
  не заменяет игру через общий ExploreScene; проверять F5 на landscape_compact.
- test_leaf_pile.gd Forward+ PASS: engine LMB/UI/wall/combat guards, скрытый pickup
  не берётся F, reveal без inventory grant и с одним autosave, F ровно один предмет,
  повтор без reward, три настоящих cold save/load, исходный flag/ID при scene reopen,
  существующий и заново созданный pickup через реальный ExploreScene owner, cleanup.
  test_world_strike/test_physical_crates Forward+ PASS. На bounded копии геометрии
  участка main strike/scatter/reveal/F и cleanup PASS; кадры просмотрены. Копия без
  props/material IDs карты, не подтверждение её полного старта или итогового вида.
  Evidence: `C:/Users/novos/Documents/Codex/2026-10-29/leaf-pile/`.
- На рисованных карточках повторно проверены новый native вид/контур/слои/разлёт,
  геометрия main в копии и прежний leaf strike/F/три cold-save состояния PASS.
  Evidence текущего облика: `C:/Users/novos/Documents/Codex/2026-10-29/leaf-palette/`.
  All240 initial vertex/UV continuity, независимые buffers двух эффектов, полный размер
  до финала и прежние три cold-save состояния Forward+ PASS. Shared effect изменён:
  test_world_strike повторно PASS. Autumn Source validation/save/reopen, точное совпадение
  prefab/cold rebuild mesh/collision и original occupancy PASS; native кадры просмотрены.
  Полную F/G матрицу не повторяли: input/WorldItem/данные переноса не менялись.
  После цветового ramp прежний leaf gameplay/three cold saves/240 continuity Forward+
  повторно PASS; два дерева/приглушённая кучка/разлёт просмотрены на копии участка main.
  Проход29.10: test_leaf_pile Forward+ PASS — реальные physics overlaps, non-player/
  combat/reentry guards, одна запись/эффект/находка, reveal cold load/F, старый save
  под неподвижным игроком, прежний strike/save/240 continuity/cleanup. На копии main
  реальный move_and_slide → scatter/reveal/F/cleanup PASS; кадр просмотрен.
  Evidence прохода: `C:/Users/novos/Documents/Codex/2026-10-29/leaf-walk/`.
- Открыто: свой F5/мышь/ощущение/вид на полном main/125%/weak-PC; ручная проверка
  по желанию автора остаётся отложенной до параллельной оптимизации. Массовый лес,
  настройки света и Hoshi другого чата не менялись. Следующие растения/ветер/
  восстановление ресурсов требуют отдельного полезного среза и решения автора.

Срезаемая трава29.10 · сделано без ручной приёмки:
- Отдельный высокий пучок на main `Map/Props/CuttableGrass`(-88;15,1;488), рядом
  с зоной листьев/ящиков. ЛКМ срезает верхушки, остаются короткие стебли; открывается
  одна находка `herb` для обычного F. Проход не скашивает, повторный удар не выдаёт
  вторую находку. Это фиксированная проба, не утверждённая частота урожая/экономика.
- `scripts/ember_cuttable_grass.gd` — тонкий вариант прежнего leaf cover: те же
  receive_world_hit/apply_authored_flag/ExploreScene/WorldItem/save owners. Выключает
  мониторинг шагов и показывает CutStubble по прежнему флагу; без собственного tick.
  Flag `cuttable_grass_revealed`, pickup `cut_grass_herb`. При дублировании назначать
  новые flag/pickup ID, сохраняя ссылку HiddenPickup.available_flag_id на Root flag.
- `tools/build_cuttable_grass.gd` берёт общий baked grass_card_contour.res и
  compact_flower/terrain foliage shader/grass atlas. Стебли обрезаются в bake по
  плоскости4,2 world units, UV сохранены. Runtime не запускает генератор/обрезку.
  По замечанию автора крупные отрезанные карточки заменены отдельными травинками
  из принятого Fixture.grass_blade_mesh:64 шт./4 MultiMesh batches. Специализация
  `scripts/ember_grass_cut_effect.gd` наследует прежний effect budget4: короткий ветер,
  вращение/лёгкое колебание, lifetime0,65с/уменьшение за последние0,24с; без посадки,
  terrain rays и отдельных физических тел. Один непрозрачный pigment вместо atlas
  пучков сохраняет узкую геометрическую форму каждой травинки; общий foliage shader.
  `prefabs/items/cuttable_grass.scn`, `cut_grass_scatter.scn`, `herb_sprig.scn`, shared material
  `prefabs/items/materials/cuttable_grass.res`. Цвет/профиль берутся из grass-slot Source
  main при bake, без отдельного затемнения tint; в asset входит только нужная grass-role,
  не остальные покрытия карты. Масштаб выше обычной травы;01.11 contour8triangles
  на пучок (сокращён с28),три пучка/24triangles,тени ON. Стерня по прежней плоскости4,2;
  тела/flag/награда/положения прежние. Материал/атлас не менялись при смене контура.
  Пучок/стерня и cut wisps используют существующий terrain feature program при первом
  runtime использовании общего материала; без копирования мешей/нового tick.
  Cut wisps:3triangles на травинку вместо10,один изгиб/остриё,без дубликатов обратных
  граней (общий material cull_disabled). Все64травинки/4batches/траектории сохранены.
  Выпекать в изолированной копии через Forward+: dummy headless не сохраняет слои
  Texture2DArray. Native material содержит текстуры, runtime не требует PNG import.
- Существующий `content/items/herb.tres` получил только worldScene herb_sprig;
  прежние имя/стек/лечебное действие/числа не менялись. Подбор кладёт1 herb в inventory,
  не лечит автоматически; используется прежний путь физических предметов.
- `test_cuttable_grass.gd` в Forward+ PASS: проход/UI/wall/combat guards, настоящий
  LMB/stubble/64 коротких травинки, wind drift/постепенное уменьшение, одна reveal запись/без instant loot, F, три cold-save
  состояния, native scene roundtrip/bindings/cut plane и cleanup. Свежий mixed runner
  также PASS. На копии геометрии участка main strike/stubble/scatter/F/cleanup PASS,
  кадры просмотрены; земля/props в пробе упрощены, это не full main/art acceptance.
  Запуск: `python tools/run_mixed_editor_tests.py --test test_cuttable_grass.gd`.
  Текущий VFX/saved batches/узкая форма/без PhysicsBody и свежий runner PASS.
  Evidence: `C:/Users/novos/Documents/Codex/2026-10-29/grass-blade-wisps/`.
- Открыто: свой F5/мышь/вид/ощущение удара на полной main. Автоотрастание, случайность,
  массовая срезаемость GrassPatch, другие растения и реакция на огонь не входят в пробу.
  Уточнение автора: вся обычная трава должна срезаться и восстанавливаться при
  возвращении на локацию, награда учитывается отдельно. Это следующий системный
  срез; текущий одиночный пучок пока сохраняет срез. Правило/границы — GDD,
  массовая растительность/загрузка — World Authoring.

Ягодный куст29.10 · внешний вид принят автором; игровой F5 OPEN:
- Выбор автора: фантастическая красно-малиновая округлая ягода с зелёной чашечкой,
  общий toon shader. Старый cloud-куст и крупные внешние грозди отвергнуты автором.
  Текущая проба — один opt-in округлый куст BushProvider/version7: пять побегов
  из низкого основания, вторичные/тонкие ветви. По отзыву автора добавлены
  направленные внутрь средние/верхние побеги: заполненный центр и округлая верхушка
  вместо открытой чаши. Ориентир формы — компактная голубика Top Hat:
  https://www.berriesunlimited.com/top-hat-blueberry/ (форма, не цвет/вид ягод).
  Они используют существующие
  BranchLayout helpers и tree_surface проекцию: та же листовая текстура дуба,
  карточки/шейдер/кора, отдельный ограниченный shrub_leaf_scale. Старые recipes
  v1–6 и принятые деревья не переводятся на этот вариант. Source —
  `content/voxel_models/vox_forest_berry_bush.tres`, recipe — одноимённый файл в
  `content/editor/voxel_generators/`, производный prefab — в `prefabs/voxels/`.
  `tools/build_berry_bush.gd` после генерации собирает `forest_berry.scn` и
  `berry_bush.scn` с вложенным обычным EmberVoxelProp Plant. Вид генераторного
  куста просмотрен в Forward+. Автор принял округлую форму по верхнему кадру;
  Source/recipe/mesh формы сохранены без изменений. Автор принял внешний вид
  с финальной настройкой: предыдущий размер плодов, большее их количество.
- Авторазмещение — `addons/ember_import/ember_voxel_fruit_placement.gd`: чистый
  post-generation шаг для bush Source. Версия7 хранит точные ветви в прежнем
  Source.tree_surface, рецепт/seed — прежние. Тридцать ягод попарно свисают
  с пятнадцати тонких веточек order3; восемь опор выбраны в верхней кроне для вида сверху,
  остальные распределены по бокам. Attachment задаётся branch_id/t, плодоножка
  короче0,3 world unit, диаметр ягоды1,1 (scale5,5, до последнего увеличения).
  Длинные внешние опоры убраны.
  Источник не меняется, позиции запечены в производную сцену; сканирования/рандома в runtime нет.
  Одинаковый Source/seed даёт одинаковую раскладку. Пустые/неподдерживаемые модели
  возвращают0 точек. Старые bush Sources сохраняют fallback по wood/leaf voxels;
  обычные деревья со своим branch frame ещё не подключены к harvest.
- Это автоматическая сборка текущего куста, не готовый общий UI «урожай» у каждого
  генератора. После правки формы в штатном генераторе нужен повтор post-generation
  сборки; live preview/Undo для совмещённого изменения формы и урожая не реализованы.
  Запрос автора для следующей настройки: доступное поле количества видимых ягод,
  чтобы подбирать его самостоятельно. Seed раскладки — возможная отдельная
  настройка, необходимость и подача пока не определены. Количество видимых плодов
  отделено от количества предметов награды; само поле в UI ещё не добавлено.
  Следующий цельный authoring-срез — подключить этот шаг к существующей команде
  размещения/обновления с preview=commit/Undo/save/discard, сохранив отдельный flag сбора.
- Main `Map/Props/BerryBush` (32;14,62764;520), рядом с FruitTree. F собирает3
  лесные ягоды в сумку, декоративные плоды исчезают, листва/ветки остаются;
  прежний pickup effect показывает перелёт к собирающему персонажу.
- `ember_berry_bush.gd` — тонкий EmberInteract adapter, не новая система ресурсов.
  Item/icon живут в `content/items/forest_berry.tres` и `content/item_icons/forest_berry.tres`.
  Уже существующий ExploreState.exchange_items фиксирует награду и completion flag
  одним изменением перед сигналами/autosave. Flag `berry_bush_harvested` — прежний
  save owner, отдельных WorldItem-записей на кусте нет. Для копии куста нужен свой flag.
  Полная стопка/боевой handoff не выдают награду и не убирают плоды. Повторы закрыты
  и маршрутом one_shot, и проверкой перед обменом. Отрастание/еда не определены.
- Минимальная проверка: `python tools/run_mixed_editor_tests.py --test test_berry_bush.gd`:
  реальный F route, full-stack/combat guards, один autosave, повтор, cold load обеих
  стадий и пересоздание куста после сбора, scene roundtrip/item/icon/physics data
  PASS в Forward+. Source совпадает с сохранённым recipe; пять побегов/leaf-card
  budget/валидность shrub scale, точные branch support/короткие плодоножки/малый размер,
  seed/determinism/Source roundtrip/нулевой count и чужой frame PASS. Прежние3
  пресета сохраняют опоры. Общие tree leaf palette/mesh/collision/history/save/discard
  Forward+ regression PASS; shared fine-only wood projection не вызывает пустой append.
  Native геометрия
  участка основной карты/высота/F PASS. Это не ручной F5 на полной карте.
  Evidence `C:/Users/novos/Documents/Codex/2026-10-29/berry-bush/`:
  `berry-bush-before.png`, `berry-bush-after.png`, `forest-berry-model.png`,
  Текущий округлый вариант: `round-bake.log`, `round-gate.log`, `round-main-gate.log`,
  `round-shrub-side.png`/`round-shrub-top.png` (оба ракурса просмотрены).
  Shared tree regression прошлого среза — `tree-leaf-regression.log`, общий путь
  деревьев этой правкой не менялся. Текущий native F/save/roundtrip/верхние опоры PASS.
  Финальная правка плодов: `more-berries-bake.log`, `more-berries-gate.log`,
  `more-berries-top.png`: 30 ягод вместо20, прежний размер, native F/save PASS.
  Хеши принятого Source/recipe/Plant prefab не изменились.
  В crop-копии проверялась геометрия, материалы земли упрощены. Ручные управление
  и полная карта OPEN; внешний вид принят, остальные формы и общий authoring отложены.
  Оптимизация мира остаётся в соседнем направлении.

Дерево с яблоком29.10 · сделано без ручной приёмки:
- Main `Map/Props/FruitTree`(0;14,5743;520). ЛКМ кратко качает листву принятого дерева,
  одно яблоко падает существующим физическим WorldItem → F. Следующие удары дают
  покачивание без новых плодов. Подбор/висящий/упавший состояния сохраняются.
- `scripts/ember_fruit_tree.gd` — адаптер receive_world_hit к прежним
  ExploreState.apply_authored_flag/WorldItem/ExploreScene owners. Flag
  `fruit_tree_apple_dropped`, pickup `fruit_tree_apple`; hanging visual и gated
  pickup занимают одну authored точку. При drop визуал заменяется тем же плодом
  в физике; нового spawn/save owner нет. UI/wall/combat guards прежнего удара.
- Внешняя Area принимает удар у ствола; принятому oak prefab/его Source не меняли
  геометрию или физику. Hit layer остаётся активным после drop для повторной реакции.
  Для дублирования нужны новые flag/pickup ID с одинаковой ссылкой на available flag.
- Частичный отклик: shared `ember_tree_leaf_cards.gdshader` opt-in define и vertex
  hook в `ember_voxel_surface_light`. Per-instance `tree_hit_sway` двигает только
  карточки листвы, с мягкой зависимостью от высоты; bark shader не включает define.
  Tween physics0,65с/затухание, нулевое состояние очищается на ready/finish/exit.
  Нет Mesh duplicate/remesh/изменения collision/общего Material. Остальные экземпляры
  сохраняют нулевой параметр. Текущая проба — принятый подробный tree-card облик.
- Своя мультяшная модель: `tools/build_fruit_tree.gd` → `prefabs/items/apple.scn`
  (округлый силуэт/верхняя выемка/черенок/лист, общий voxel toon shader) и
  `fruit_tree.scn` (обычный вложенный oak). `content/items/apple.tres` и pixel-icon
  `content/item_icons/apple.tres`; пока fruit/material для подбора, эффект еды не задан.
  Поиск/загрузка сторонних ассетов не требовались.
- Физика плода уточнена: `ember_item_presentation.gd` хранит форму/центр, native
  PhysicsMaterial и затухание рядом с моделью; WorldItem остаётся единственным телом.
  У яблока выпуклая оболочка самого плода без черенка/листа, центр (0;0,13;0),
  friction0,55/bounce0,22, linear/angular damping0,25/0,45. Размер применяется к
  Shape3D, не scale коллизии; общий cache до16 форм очищается при изменении источника.
  Первый drop даёт малый горизонтальный импульс2,5 и вращение1,25 на первом доступном
  physics tick; дальше отскок/перекатывание определяет физический контакт с землёй.
  Нет анимации траектории/принудительной остановки. Очередь импульса временная,
  очищается при restore/carry/recovery; save по-прежнему хранит позу, не скорость.
  Остальные модели сохраняют прежнюю box-форму, пока им не заданы свои настройки.
- Forward+ `test_world_item_physics.gd` PASS: противоположные склоны без стартового
  толчка, вращение/отскок/путь после контакта/успокоение на плоскости, общая форма,
  проверка данных/scene roundtrip/сохранённая поза без старого импульса. Повторный
  fruit gate и crate regression PASS. Evidence:
  `C:/Users/novos/Documents/Codex/2026-10-29/item-physics/`; кадр после падения
  `apple-after-drop.png` просмотрен. Настройки ощущения ещё требуют автора.
- `test_fruit_tree.gd` Forward+ PASS: настоящий LMB/UI/wall/combat, rendered crown
  parameter response, возврат к покою/очистка сохранённой деформации, неизменные mesh/
  collision и соседнее дерево, физическое падение без застревания/F, повторные удары,
  три cold saves/scene+icon roundtrip. Свежий mixed runner PASS. По общей shader
  зависимости tree palette и leaf pile Forward+ regressions PASS. На геометрии main
  strike/fall/F PASS, native кадры просмотрены; полный main/ручное ощущение OPEN.
  Запуск: `python tools/run_mixed_editor_tests.py --test test_fruit_tree.gd`.
  Evidence: `C:/Users/novos/Documents/Codex/2026-10-29/fruit-tree/`.
- Открыто: ручные вид яблока/амплитуда/удар/полная карта. Множественные плоды,
  плодоношение/еда/ветер и общий режим скашивания/восстановления травы не реализованы.
