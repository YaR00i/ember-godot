# Ember Visual Library

Статус: I2.39, общий picker реализован для item icons, shop items, VN backgrounds, speakers, expressions, полного voxel-каталога, карт и special locations/regions.

## Решение

Визуальная библиотека — это не новый asset database. Она строит плитки из уже существующего canonical resolver и возвращает его стабильный string ID. Save/runtime продолжают хранить `iconId`, `itemId`, `bgArtId`, `speaker` и `portraitKey`; thumbnail, фильтр и выделение являются только editor state.

Для ID-каталогов используется штатный Godot [`ItemList`](https://docs.godotengine.org/en/stable/classes/class_itemlist.html) в `ICON_MODE_TOP`: он уже поддерживает иконки, несколько колонок, tooltip, поиск по первой букве, выбор и активацию Enter/double-click. Ember добавляет один общий `EmberVisualLibraryPicker` с поисковой строкой и явной кнопкой подтверждения.

`EditorResourcePicker` не заменяет этот слой: по документации это стандартный Inspector-control для поля, которое непосредственно ссылается на `Resource`. Gameplay Ember намеренно хранит стабильные ID, а не пути/ссылки на editor resources, поэтому превращать `itemId` или `speaker` в Resource property только ради UI нельзя. Для настоящих `.tres`, texture и scene references следует использовать штатный [`EditorResourcePicker`](https://docs.godotengine.org/en/stable/classes/class_editorresourcepicker.html).

Для выбора внешнего файла остаётся [`FileDialog`](https://docs.godotengine.org/en/stable/classes/class_filedialog.html) с thumbnail display. Импорт создаёт/обновляет canonical asset, после чего visual library перечитывает resolver. FileDialog не становится вторым каталогом.

Для файлов и Godot Resources thumbnail должен запрашиваться через [`EditorResourcePreview`](https://docs.godotengine.org/en/stable/classes/class_editorresourcepreview.html). Собственный `EditorResourcePreviewGenerator` допустим только если встроенное превью сцены/ресурса не показывает нужный Ember-вид; генератор обязан быть thread-safe и кэшировать результат по Resource metadata.

## Реализованный вертикальный срез

- `EmberItemCatalog` по-прежнему владеет native-first item definitions и read-only legacy pixel-icon definitions.
- `EmberItemVisuals` декодирует `palette + rows` в `Image`, масштабирует только nearest-neighbor и кэширует editor textures. Новых icon-файлов и нового registry нет.
- `EmberVisualLibraryPicker` показывает плитки 56×56, локализованное имя, ID, tooltip и поиск. Двойной клик/Enter или кнопка `Выбрать` возвращает только ID.
- `EmberItemEditor` показывает выбранную иконку рядом с прежним compact picker и открывает `Библиотека…`.
- каждая строка `EmberShopEditor` показывает иконку/локализованное имя предмета и открывает общую `БИБЛИОТЕКУ ПРЕДМЕТОВ`.
- `EmberVoxelVisuals` проецирует native-first `EmberVoxelCatalog`. Перенесённые модели читаются из `content/voxel_models/*.tres`; ещё не перенесённые `.json/.vox` явно помечаются очередью legacy import. Один main-thread `SubViewport` размером 128×128 рендерит готовый PackedScene либо transient instance из того же resolved source. Текстуры кэшируются только в памяти по prefab/source mtime. `◇` означает лишь отсутствие собранного prefab.
- выбор voxel-плитки создаёт один scene-owned instance в `Map/Props` с новым `placement_id`, обычным transform-gizmo и Editor Undo/Redo. Каталог не получает нового registry, а UI не запускает массовую пересборку prefabs.
- headless не создаёт GPU texture, но тестирует исходный `Image`, catalog IDs и ItemList contract.
- `EmberMapVisuals` строит производную 96×96 схему карты через общий `EmberTileMesher.surface_grid()`: это та же top-surface проекция, которую использует runtime mesh. Цвета берутся из canonical tileset, voxel props помечаются точками, выбранный region — золотой рамкой. Door form и action `change_map` открывают общий picker кнопкой `▦`, сохраняя только прежние `targetMapId/targetRegionId`.

## Порядок расширения

1. **Реализовано:** VN background и portrait используют тот же picker, а texture берут из существующего `EmberVnAssets.art_thumbnail/portrait_thumbnail`. Сохранение и импорт Resource не менялись. Пустая плитка background означает наследование scene default, а не новый ID; expressions фильтруются выбранным speaker. Native-first lookup считается успешным только для непустой записи с путём, иначе resolver продолжает поиск в legacy portrait registry.
2. **Реализовано:** voxel props перечисляют все существующие model IDs. Штатный preview не прошёл ручной gate; отдельный `EditorResourcePreviewGenerator` также не выбран, поскольку его callbacks выполняются в worker thread. Один transient main-thread `SubViewport` инстанцирует PackedScene или вызывает тот же prefab mesher без save, кадрирует только `Mesh`, отключает authored lights и рендерит очередь по одному объекту. Это preview-adapter того же prefab contract, не второй renderer/runtime/importer.
3. **Реализовано:** карты и special locations используют CPU-схему canonical map JSON, а не запуск scene/screenshot. Texture живёт только в memory cache по mtime карты и не входит в `.tscn`/JSON schema; gameplay map/region IDs остаются прежними. При появлении полноценного native map owner адаптер должен перейти на общий resolver, а не создать второй каталог.
4. Персонажи и экипировка вне VN: portraits/item icons приходят из уже существующих resolvers. Нельзя создавать отдельный список только для конкретного editor card.
5. Audio/VFX: waveform/thumbnail добавляется как новый entry renderer общего picker, но выбранное значение остаётся canonical content ID.

Каждый следующий тип принимается по вертикальному контракту: resolver → visual entry projection → picker → selected preview → save/reopen → runtime ID parity → targeted test. OptionButton можно оставить компактным fallback, но тяжёлые динамические изображения внутри его PopupMenu не используются: раньше такой rebuild вызывал native crash Godot 4.7.2; thumbnail живёт в `TextureRect`/`ItemList`.
