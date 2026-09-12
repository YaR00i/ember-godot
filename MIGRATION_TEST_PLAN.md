# Ember — актуальные проверки и migration gates

## Общий Git checkpoint2026-09-13

Проверены все128 `tools/test_*.gd`:125 PASS с учётом повторных проверок в
изолированном export подготовленного Git index и native screenshot сборки.
Остались3 незелёных gates, не скрывать их при передаче:

- `test_voxel_split_preview.gd:12` ожидает EmberVoxelProp в
  `Map/Terrain/TimberPier/Visual`; сейчас там сборка Node3D с деталями.
- `test_voxel_placement_preview.gd:23` жёстко ожидает12 children той же сборки;
  авторская сцена уже изменена. Native повтор подтверждает устаревшее ожидание.
- `test_voxel_sandbox_native_batch.gd`: устарели prefab signatures для
  vox_ms8vsb53,vox_vil_bush,vox_vil_counter,vox_vil_mailbox,vox_vil_planter,
  vox_vil_sign. Нужна отдельная проверка/пересборка, не переписывать авторские
  assets автоматически ради Git checkpoint.

`test_voxel_assembly_preview.gd` требует настоящего renderer для безусловного
screenshot, native Forward+ PASS. Старые migration_queue/prefab_rebuild tests
пишут production res://, запускать только в disposable copy. Migration_queue
PASS при правильном legacy pack path, prefab_rebuild PASS после первоначальной
пересборки в копии. Рабочие prefab после неуспешного cleanup старого теста
восстановлены точно из подготовленного index; изменения тестов не включены.
Новая генерация/история/породы/кора/выделение/маски/штампы/паттерны/рельеф/
пересборка и связанные gameplay/persistence suites PASS. Пользовательская
визуальная приёмка ели подтверждена отдельно.

## Ель v10: ярусный хвойный профиль (силуэт принят)

«Тип · Ель» или явный выбор type4 используют10. Новая мастерская начинает
с актуальной саванны9; все5 типов доступны рядом. Loaded Recipes сохраняют
алгоритм и отмечены «прежняя форма»; явный reselect обновляет его с Undo.
Старые алгоритмы остаются в дополнительных настройках совместимости.

`tools/test_voxel_spruce_shape.gd`:64/96/128/256×seeds17/371/391, непрерывный
leader,9ярусов/сужение ветвей, >90%leaf row coverage в основной кроне,
max budget/directions, validation/exact fresh-frozen/text roundtrip/collision,
bare/season/thickness support stability, type choice/loaded compatibility,
discard/Apply/publication Undo/Redo/reopen10. Native disposable fixture:
`-- --spruce-shape-only`, seeds371/391/17 и391bare, реальные front/right views.
Финальный targeted PASS,11related suites PASS. Native isolated Forward+
gallery/bare/Apply/Undo/Redo/publication/reopen10 PASS; итоговые front/right/
gallery captures просмотрены, лог без script errors. Первый редкий вариант
исправлен до handoff; тест row coverage ловит голый leader между ярусами.

Ручная приёмка: открыть «Тип · Ель»,96vox,seeds391/17/371, сравнить спереди
и сбоку с референсами — острый leader, широкие нижние/короткие верхние ветви,
неравные вытянутые массы хвои, не шарики и не сплошной конус.
Количество пучков0 → тот же каркас; изменить толщину/цвет/количество,
Apply/Undo/Redo,save/reopen. Старые объекты не должны самопроизвольно меняться.
После принятия формы ели обсудить общую систему листьев/хвои отдельно.
Пользователь выполнил проверку и принял ель («Мне нравится, проверил»).

## Саванна v9: зонтичный профиль (силуэт принят)

Новый «Тип · Саванна» и явный выбор типа →9. Default/saved v2/v3 не
обновляются на load; shared frozen structure1/paint/bark/emitter/Source/Recipe/
workshop/publisher прежние. Изогнутый ствол,3–4 основные стволики и тонкие
боковые развилки под широкой неглубокой слегка выпуклой кроной, без pole.
Foliage_along использует прежний descriptor/projection и доступен для v9.
Профиль кроны учитывает реальный ограниченный размах и на256vox.

`tools/test_voxel_savanna_shape.gd` PASS:12samples64–256, saved v2 golden
parity, no pole, реальная высокая shallow/wide крона, bounded scaffold/max
storage/directions, source validation, fresh/frozen geometry+collision exact,
Recipe text roundtrip, bare/season/thickness support stability, shared
foliage control, UI choice Undo/Redo, discard/Apply/publication Undo/Redo/reopen9.
Oak/maple/birch/types/bark и common generator editing/session regressions PASS.
Native disposable `-- --savanna-shape-only`: №1v2/№2v9/№3v9bare/№4v9seed17,
индивидуальные Apply/Undo/Redo/publication/reopen PASS. Gallery и реальные
передний/правый ортогональные `generation_savanna_front.png`/
`generation_savanna_side.png` просмотрены. Финальный native лог без script
errors; неполный ненормализованный Recipe старого образца был ошибкой fixture,
исправлен нормализацией через общий owner, не изменением старого алгоритма.

Для ручной проверки заново выбрать preset «Тип · Саванна»,height96,
seeds391/17/371. Сравнить спереди/сбоку с фото: тонкий изогнутый ствол,
раскрытые сучья, широкая неглубокая неровная крона, без центральной башенки.
Количество пучков0 показывает тот же каркас. Apply/Undo/Redo,save/reopen
и старые деревья проверить в рабочем редакторе. Художественная приёмка
пользователем отдельно от assertions. Силуэт принят («Проверил, красиво»).
Новая очередь: ель, затем обсуждение листьев/хвои.

## Дуб v8: взрослый раскидистый профиль (силуэт принят)

Пользователь принял форму v8 («форма мне нравится»).

Новый «Тип · Дуб» и явный выбор типа используют v8. Сохранённые v3/v4
остаются прежними; oak suite сохраняет их golden hashes64/128/256.
Массивный искривлённый ствол/непрерывный collar, короткие слитые buttresses,
разные высоты основных сучьев, длинные боковые нижние ветви и вторичные
развилки, несколько восходящих верхних сучьев. Крона глубже по высоте,
внутренние опоры связывают внешние массы, нижние развилки видны.
Shared Source/Recipe/structure1/registry/bark/projection/workshop/publisher;
без новых knobs, leaf microdetail и branch editor не входят.

`tools/test_voxel_oak_crown.gd` PASS: 3seeds×64/96/128/256, max budget,
разные origins/нижний размах/deep foliage/collar, structure/source validation,
fresh/frozen geometry+collision exact/text roundtrip, bare/season/thickness,
UI choice Undo/Redo, discard, Apply/publication Undo/Redo/reopen v8.
Maple/birch/types/bark, generator editing/session regressions PASS.
Native disposable `-- --oak-crown-only` сравнивает №1v4/№2v8/№3v8bare/№4seed17,
индивидуальный Apply/Undo/Redo и publication/reopen PASS. Gallery и передний/
правый ортогональные `generation_oak_mature_front.png`/`generation_oak_mature_side.png`
просмотрены. Прежние copied fan_town UID warnings не исправлялись этим срезом.

Ручная проверка: заново выбрать «Тип · Дуб», height96, seeds391/17/371.
Сравнить с фото спереди/сбоку: массивное плавное основание, широкие кривые
сучья, глубокая неровная крона без одной плоской шапки. Количество пучков0
показывает тот же скелет. Проверить Apply/Undo/Redo/save/reopen и сохранённые
старые деревья. Узнаваемость подтверждает пользователь, не shape asserts.

## Клён v7: высокая крона по фото референсу (силуэт принят)

Пользователь принял силуэт v7 («да, похоже на клён»); возвращаемся к дубу.

V6 ниже — технически проверенный, но не принятый пользователем этап.
Повторный согласованный проход v7 меняет высотное распределение опор и масс:
пять уровней, широкая середина/более узкий округлый верх, внутреннее заполнение
и перекрытие соседних масс. Новый «Тип · Клён»/выбор типа → v7, saved v3/v6
не обновляются. Golden v6 сняты до правки, проверка добавлена в maple suite.
Финальный maple suite PASS: v6 exact golden parity, пять высот/широкая середина/
узкий верх, реальная высота листвы и отсутствие пустых горизонтальных рядов,
12samples и maximal envelope, fresh/frozen/text exact roundtrip, Apply/discard/
publication Undo/Redo/reopen. Oak/birch/types/bark, generator editing/session PASS.
Native `-- --maple-shape-only` Apply/Undo/Redo/publication/reopen PASS;
`generation_maple_upright_native.png`, передний/правый ортогональные
`generation_maple_front.png`/`generation_maple_side.png` просмотрены.

Для ручной проверки v7 заново выбрать preset, height96, seed391/17/371.
Оценить дерево на уровне кроны спереди и сбоку, а не только сверху: сравнить
пропорции с фото пользователя, наличие общей высокой кроны вместо чаши,
широкой середины и более узкой верхушки. Голый каркас показывает ветви на
нескольких высотах. Проверить Apply/Undo/Redo/discard, save/reopen и отдельную
вариацию; старые деревья остаются прежними. Мелкие детали листьев не входят.
После оценки клёна вернуться к дубу; Ель пока не реализовывать.

2026-09-12: `tools/test_voxel_maple_shape.gd` PASS: 3 seed × 64/96/128/256,
ascending/lateral supports, Source/structure validation, extreme envelope,
exact fresh/frozen/text Recipe roundtrip/collision, bare/season/thickness без
перемещения опор, explicit direction/tiered, type choice Undo/Redo,
draft discard/Apply/publication Undo/Redo/reopen. Oak/types/birch/bark и
generator editing/session regressions PASS.
Native disposable `-- --maple-shape-only` individual Apply/Undo/Redo/publication/
reopen PASS; `user://generation_maple_shape_native.png` просмотрен:
№1 старый v3, №2 v6 seed391, №3 тот же v6 без листвы, №4 v6 seed17.

1. Заново выбрать «Тип · Клён», height96, seed391/17/371. Оценить округлую
   связанную крону, раскрывающиеся в стороны восходящие развилки, отсутствие
   отдельной высокой цепочки шариков/низких «тарелок». Оценивать форму, не цвет.
2. «Настроить» одного дерева → количество листвы0 → Apply: проверить голый
   каркас, Undo/Redo. Изменить толщину/сужение ветвей, цвет/заполнение листвы:
   опоры не двигаются, другие варианты неизменны. Discard не меняет source.
3. Сохранить, reopen в Canvas «Генератор», создать вариацию/новую генерацию
   из настроек. Старый saved v3 не обновляется без явного нового каркаса.
4. Проверить высоты64/128/256; 256 соблюдает прежний envelope и может быть
   относительно уже. Детализация листьев пока не входит в оценку этого среза.

Тип «Ель» добавлен в продуктовый план, ещё не реализован.

## Общий рисунок коры (распределение v2 принято пользователем)

2026-09-12: `tools/test_voxel_bark_pattern.gd` PASS: marks rotation covariance
по оси support, surface-only, direction/length/seed determinism, zero/off,
все large_tree породы без изменения occupancy/collision/skeleton, custom colour
в palette[7], exact off colours, native bool/enum descriptors в common creation
и contextual Canvas, Undo/Redo/discard. Birch/oak/types и 6 related suites PASS.
Recipe text roundtrip exact: устранён negative-zero atan2 seam; старые missing
pattern keys остаются off. Native disposable `-- --bark-pattern-only` PASS:
cross birch/longitudinal oak/custom slanted birch/plain oak, toggle/direction/
colour/length Apply Undo, library publication Undo/Redo и reopen.
Capture `user://generation_bark_pattern_native.png` просмотрен.

Полировка v2: новые presets/defaults используют независимые смещённые штрихи
с промежутками, cross/slanted length ограничена радиусом ветви. Saved Recipe
без `bark_pattern_version` остаётся v1; off/on toggle явно выбирает v2,
Undo возвращает старую версию. Bark v1 parity/v2 rotation/thin-support rings,
creation/contextual upgrade Undo, oak/birch/types, editing/session/generator PASS.
Recipe text save/reopen exact colours PASS для обеих версий рисунка.
Native `-- --bark-pattern-only --scattered-bark` Apply/Undo/Redo/publication/
reopen PASS; сравнение №1 v1 birch391 / №2 v2 birch391 / №3 v2 birch17 /
№4 v2 oak371, capture `user://generation_bark_scattered_native.png`.
Gallery и отдельные крупные планы `user://generation_bark_detail_1/2/3.png`
просмотрены.
Пользователь затем принял распределение v2 («да это лучше»); bark gate закрыт.

Дополнительная ручная проверка v2: старое дерево открыть без изменения рисунка;
off/on «Рисунок коры» → Apply/preview должен обновить только окраску.
На берёзе height96, seed391/17/371, без листвы осмотреть ствол крупно с четырёх
сторон: отметины не должны складываться в одинаковые пояса. Density100,
length24 на тонких ветвях — остаются светлые промежутки. Undo возвращает
прежнюю окраску/версию, save/reopen сохраняет выбранное распределение.

1. Заново выбрать «Тип · Берёза»/«Тип · Дуб», height 96. Оценить cross/longitudinal
   рисунок крупным планом на стволе и ветвях. Для удобства временно убрать листву.
2. «Настроить» → прокрутить до «Рисунок коры»: toggle off/on, direction, colour,
   length 2/12/24 и density 0/30/100. До Apply source не меняется; Apply один раз,
   Undo/Redo возвращают exact tree. Геометрия и расположение ветвей неизменны.
3. Изменить радиусы ветвей и проверить соответствие рисунка новой толщине.
   Другие варианты неизменны. Discard возвращает настройки черновика.
4. Сохранить лучший, reopen в Canvas «Генератор», поменять рисунок и сохранить
   вариацию. Reopen/preset/new generation сохраняют параметры; saved old Recipe
   не получает рисунок автоматически. В настройках новой партии блок находится
   в дополнительных параметрах. Это окраска, не объёмные бороздки/шейдер.

## Берёза: тонкий ствол и поникающие веточки (силуэт принят пользователем)

2026-09-12: `tools/test_voxel_birch_shape.gd` PASS: 3 seed × 64/96/128/256,
continuous leader, descending outer twigs, bounded/maximal source/structure,
exact fresh/frozen/text Recipe roundtrip и collision, bare/season/thickness
support stability, draft discard, Apply и common publication Undo/Redo/reopen.
Oak compatibility и 6 related suites PASS. Новый preset/выбор типа → v5,
загрузка saved v3 birch не обновляет алгоритм. Leaf 128 vox примерно 60 ms,
meshing отдельно. Native disposable fixture `-- --birch-shape-only`:
№1 saved-style v3, №2 новый v5, №3 тот же seed без листвы, №4 seed 17;
capture `user://generation_birch_shape_native.png`, normal Forward+ viewport.
Финальный native comparison/individual Apply/Undo/Redo/publication/reopen PASS,
capture просмотрен. Shared type UI/Undo/Redo regression PASS.

1. «Тип · Берёза», height 96, seed 391/17/371. Оценить вытянутый воздушный
   силуэт, тонкий изгибающийся ствол, боковые восходящие ветви и поникающие
   окончания. Не оценивать узнаваемость только по белому цвету коры.
2. «Настроить» одного дерева → количество пучков 0 → Apply; осмотреть bare
   branches, Undo/Redo. Остальные варианты неизменны. Толщина/сужение меняют
   радиусы без перемещения опор, цвет/заполнение/размер листвы — не ветви.
3. Discard черновика; сохранить лучший, reopen в Canvas «Генератор», сохранить
   вариацию. Старый v3 восстанавливается как раньше; новый сохраняет v5/seed/
   каркас. Новый именованный preset используется для новой партии без skeleton.
4. 64 и 256 vox, нижние грани, вращение/3D comparison/остановка между моделями.
   Отдельный проход по детальной форме листвы — после силуэтов остальных presets.

## Полировка дуба: развилки и связная крона (силуэт принят пользователем)

2026-09-12: `tools/test_voxel_oak_crown.gd` PASS: новый oak v4 при 3 seed и
высотах 64/96/128/256, отсутствие высокой центральной оси, несколько ранних
развилок, bounded/maximal geometry и validation, exact fresh/frozen/text Recipe
roundtrip, bare/season без смены каркаса, invalid radii rejection,
individual Apply Undo/Redo и library publication Undo/Redo/reopen в `user://`.
Golden samples сохраняют старый v3 oak byte-identical и геометрию v4 после
ускорения union; types и 6 related suites PASS. На 128 vox leaf build примерно
0.86–0.95 s без meshing. В рабочем checkout не запускать headless editor.
Native opt-in в disposable `ember-generation-smoke-*`, аргумент
`-- --oak-crown-only`: №1 старый v3, №2 новый v4, №3 тот же seed/каркас без
листвы, №4 другой seed; native selection/F/wheel, Apply Undo/Redo, publication
Undo/Redo и Recipe reopen. Capture `user://generation_oak_crown_native.png`.
Финальный native прогон PASS, capture просмотрен; пользователь принял силуэт
дуба («дубы стали похожи на дубы»). Детальная форма листвы — отдельный этап.

1. В мастерской выбрать «Тип · Дуб», height 96, seed 391; затем 17 и 371.
   Оценить широкий округлый силуэт, сильные развилки и боковой объём, а не
   столбик отдельных одинаковых шапок. Сравнить несколько партий через «3D».
2. Выбрать одно дерево → «Настроить» → количество листвы 0, Apply. Проверить
   ход сучьев без листвы; Undo возвращает ту же полную крону. Толщина/сужение
   ветвей сохраняют положение развилок; другие варианты не меняются.
3. Поменять заполнение вдоль ветвей, размер/приплюснутость масс и осенний цвет.
   Apply/Undo/Redo/Discard; сохранить лучший и открыть в Canvas «Генератор».
   Reopen восстанавливает Recipe/seed/каркас; свой preset генерирует новые
   каркасы, а не копирует старый. Старый saved дуб v3 остаётся старым.
4. Проверить 64 и 256 vox, вращение и нижние грани, сравнение до 4/2 деревьев.
   Остановка между кандидатами; на крупном дереве synchronous build ещё может
   задерживать кадр. Узнаваемость дуба и форма кроны требуют оценки пользователя.

## Типы и боковой объём деревьев (ручная художественная приёмка открыта)

2026-09-12: `tools/test_voxel_tree_types.gd` проверяет 4 типа при одинаковом seed
и height 64/128/256, bounded source/structure, exact frozen rebuild, season и
interior foliage 0/30/100 без движения древесины, unchanged branch RNG при 0%,
направления up/lateral/down, максимальные размеры нового типа, Resource text
roundtrip с exact voxel parity, type Undo/Redo в общей панели. Golden pre-type
hashes v1/v2 проверяют сохранение старых формул на seed 371 во всех 3 размерах.
Related: generator/editing/session/large_tree_object/dialog/library_layout PASS.
Native opt-in fixture дополнен четырьмя type presets в разных партиях и общим
сравнением, interior foliage Apply/Undo/Redo, existing library publication и
typed Recipe reopen; capture `user://generation_types_native.png`.
Native сценарий PASS; в первом прогоне выявлено отсутствие нового editing field
из-за сборки candidate controls только при ready. Общая панель обновляет набор
descriptors при выборе другого типа; regression есть в targeted test, следующий
native прогон с реальным полем Apply/Undo/Redo и saved Recipe reopen PASS.

Ручные проверки после сохранения рабочих сцен и перезапуска Godot:

1. «Объекты → Генерация…», пресеты «Тип · Саванна/Дуб/Берёза/Клён»; height 96,
   по одному варианту, одинаковый seed. Все 4 партии остаются в истории; собрать
   галочками «3D» сравнение четырёх. В строках подписан тип, номера над моделями
   совпадают. Саванна прежняя; дуб объёмный, берёза стройная, клён ярусный.
2. Дуб: новые партии с направлением вверх/в стороны/слегка вниз. Проверить,
   что меняется реальный ход ветвей, а не только положение шапок листвы.
3. «Настроить» дуб → «Листва вдоль ветвей» 0/30/100, Apply/Undo/Redo. Меняется
   боковое/внутреннее заполнение, но существующие ветви и другие модели стоят
   на месте. Осенний цвет тоже не перестраивает каркас. Discard возвращает draft.
4. Сохранить лучший, открыть его в Canvas «Генератор», изменить листву/толщину,
   сохранить вариацию. Reopen сохраняет тип, параметры, seed и каркас; старые
   saved v1/v2 деревья восстанавливаются как раньше. Typed presets можно сохранить
   своим именем и использовать для следующей партии без старого skeleton.
5. Height 256 → сравнение до 2. Проверить вращение, нижние грани, scene save без
   temporary candidates, cancel между моделями. Тонкие детали/форма кроны требуют
   художественной оценки, не заменяются автоматической voxel parity.

## Общая мастерская генерации в native 3D (новая рабочая приёмка открыта)

2026-09-12: `test_voxel_generation_session.gd` проверяет provider descriptors,
parameter/seed и candidate choice Undo/Redo, индивидуальный draft/discard/apply
Undo/Redo, unchanged other candidate и exact skeleton, один explicit skeleton
reroll + Undo, осенняя palette только выбранного дерева и exact reopen,
стабильные номера/Label3D между family/pass, solo/gallery,
studio/map suspension с dirty draft и восстановление утратившей nodes галереи,
publication lock после file Undo (не расходятся preview и file Redo), разные seeds,
frozen skeleton, один family/card для двух выбранных вариантов, точный source
и восстановление тех же voxels после recipe reopen, asset-only Save/Undo/Redo,
отсутствие placement/physics/scene serialization у preview, историю всех партий,
освобождение geometry архивных записей, точное восстановление unsaved/saved,
cross-batch comparison, favorite не уменьшает новые партии, фильтры batch/best,
сохранение лучших из архива по очереди и file Undo/Redo архивного варианта,
cancel, limits 4/2, presets save/reopen/duplicate guard,
освобождение discarded Creation (без удержания mesh сигналами/choice history),
защиту использования сохранённого объекта. Все fixtures только `user://`.
Related: generator, generator_editing, large_tree_object/dialog,
object_library_layout; plugin.gd и native fixture `--check-only`.

`editor_test_voxel_generation.gd` opt-in только в disposable
`ember-generation-smoke-*`: реальная library create button, studio scene tab + bottom panel,
четыре exact previews в обычном Forward+ viewport, native selection/center F/
wheel scale, save-only history с filesystem settle между Undo/Redo, preset
reopen, studio save без preview, карта без временных objects, открыть saved source
в существующем Canvas, individual apply + native selection, dirty draft при
scene switch/return, 8 вариантов/2 партии, восстановление точной geometry старого,
сравнение старого/нового, batch filter и confirmation Cancel всей истории без
удаления. Capture
`user://generation_native.png`; adaptive native wheel fit учитывает сохранённый
camera zoom disposable scene, не вмешивается в рабочий editor пользователя.
Прежние UID warnings authored fan_town в копии не относятся к новой генерации.
Результат: новый session test + 5 related suites PASS; native Forward+ полный
сценарий и generate-similar command PASS, cross-batch comparison двух деревьев
в обычном editor capture просмотрено. Новых script errors нет. Предыдущую
мастерскую пользователь принял; ручная приёмка истории всех партий открыта.
Synchronous build не отменяется посреди
одного дерева, лимит памяти — консервативный, без нового GPU performance gate.
В промежуточном native прогоне обнаружены exclusive-window conflict и crash
после confirmation Cancel; lifecycle исправлен явным hide перед queue_free.
Финальный прогон использует реальную Cancel button, полный сценарий PASS без
exclusive-window/script errors, editor штатно закрыт; capture просмотрен.

Рабочая ручная последовательность (сохранить draft/сцену, перезапустить Godot):

1. «Объекты → Генерация…»: отдельная вкладка сцены «Генерация» в Godot 3D и
   нижняя мастерская, не новое окно. Рабочая карта остаётся в своей вкладке.
2. Height 96, 4 варианта → сгенерировать; «Показать сравнение · F», F в 3D, колесо для
   масштаба. Камеру можно свободно вращать стандартной навигацией Godot.
3. Номера над деревьями совпадают со списком. Выбрать №2 в 3D или «Настроить»;
   справа изменить толщину/листву: сначала draft без remesh, затем «Применить».
   №1/3/4 не меняются; Undo/Redo справа возвращает draft и applied geometry.
   «Сбросить правки» тоже undoable. Dirty draft не теряется при попытке сменить
   вариант/сохранить/начать новую партию. Solo/gallery не удаляет остальные.
   Отметить два лучших; Undo/Redo выбора кнопками «↶ Настройки»/«↷».
   Настройки слева относятся только к новой партии.
   Сгенерировать ещё две партии по 4: история содержит 12, даже если первые
   отмечены лучшими; каждая новая партия всё равно имеет 4. Проверить фильтры
   «Все партии»/«Только лучшие»/«Партия 1»; номер и seed старых не меняются.
   «Настроить» старого №2 восстанавливает его одного; добавить галочкой «3D»
   новый №9 для сравнения. Изменить листву №2, Apply/Undo/Redo — только его.
   «Последняя партия в 3D» не удаляет историю. Более 4 одновременно не добавляется,
   если есть дерево выше 128 vox — лимит 2. Снять «3D» не значит снять «лучший».
4. Отметить лучшие из разных партий, включая не показанные в 3D, и сохранить
   выбранные по очереди: одно семейство с concrete вариантами, без placement.
   Ctrl+Z/Shift+Ctrl+Z отменяет/возвращает публикацию по одному варианту.
   Поздние правки файлов и используемые в карте объекты не удаляются историей.
5. «Сохранить свой пресет…»: имя, save; закрыть/открыть панель, выбрать пресет.
   «Объекты → Ещё → Генерировать похожие» загружает настройки saved дерева;
   «Создать вариант из рецепта» редактирует тот же frozen skeleton в Canvas.
6. Попробовать 256 vox: до 2 точных объектов, cancel между деревьями. Сохранить
   studio scene с preview: после reopen temporary objects не сериализованы.
7. С dirty draft переключиться на карту: мастерская paused, в карте никаких
   previews. «Открыть вкладку 3D» возвращает тот же набор и draft. Закрыть именно
   studio scene tab, снова открыть мастерскую: candidates восстанавливаются.
   «Закрыть набор» → Cancel ничего не удаляет; подтвердить удаление — очистить
   temporary candidates, saved library files остаются. Restart editor теряет
   unsaved session: перед ним сохранить лучшие и scene/Canvas drafts.
8. «Настройки дерева → новая партия» переносит параметры для presets/новых seeds.
   «Новый каркас из настроек партии» заменяет только выбранный, Undo возвращает
   прежний каркас. После publication правки через Canvas либо новую партию;
   file Undo не разблокирует local edits. Типы/направление ветвей уже расширены
   следующим срезом выше; редактирование отдельных веток пока не реализовано.

## Общий voxel refresh и 3D viewport (ручная приёмка открыта)

Следующий пользовательский прогон: 205 rebuilt/21 disk rename Failed, другие IDs.
`test_editor_filesystem` проверяет nested weak scan leases/coalescing/release.
`test_voxel_scene_refresh` — два transient FAILED и success без повторного meshing,
а также настоящий FileAccess READ handle на Windows: после release запись проходит
на третьей попытке (PASS), per-model Undo/Redo остаётся exact. Native isolated
library button проверяет отсутствие наших scans внутри batch и retry/history.
Queue ждёт active scan/import до 30 s, публикацию повторяет до 3 s с 100 ms yield;
перед retry проверяются source/prefab/instance conflicts. Save/reopen Source не
переписывается. После reload повторить список ошибок (или всю очередь, если список
сбросился). Финальный рабочий прогон пользователь подтвердил: 226/226 rebuilt,
0 skipped — batch gate принят. Конкретный reader,
удерживавший файл в рабочем Godot, не доказан. Не отключать антивирус для проверки.

Рабочая очередь пользователя 226/226: 196 rebuilt, 30 skips. Fix regression
`tools/test_voxel_refresh_legacy.gd` читает доступные 30 исходных assets из отчёта,
но публикует только user:// copies: indexed/unit-adapter и opaque VOX ShadowBody
compatibility, source/prefab hashes, unchanged bounds/node frames/authored children,
UID, exact Undo bytes/references, Redo и normalized prefab reopen. Все 30 PASS.
Suite безопасно пропускает недоступные local author cases и сообщает tested count.
`test_voxel_scene_refresh` также покрывает equivalent indexing vs custom color,
never-built UID и точные failed IDs. Native isolated editor проверяет existing
no-UID text prefab publication и реальную retry button после исправления fixture
source, без публикации production assets. После перезагрузки plugin (сохранить
draft/scene) в Migration повторить failed IDs; если editor session уже сменился,
запустить всю библиотеку снова. Проверить отсутствие 30 прежних skips, размер,
низ/тени обычных объектов, Undo/Redo и save/reopen. Retry list editor-only.
Repair final: scene_refresh, all 30 legacy author-copy regressions, object Canvas,
generator editing, object library/workshop layout, plugin parse и diff check PASS.
Native isolated Forward+ publication/retry/EditorUndoRedoManager PASS; ERROR нет,
только прежние два tree external mesh UID text-path fallback warnings.

Полная библиотека: `test_voxel_scene_refresh` дополнен очередью без active scene,
deduplicate ID, force rebuild current, cancel после первого, Undo/Redo prefab bytes,
Source hashes и созданием отсутствующего prefab (Undo оставляет recoverable asset).
Команда «Объекты → Пересобрать всю библиотеку» / Ember Migration: следить за N/M,
нажать остановку между моделями, проверить список пропусков, Undo по моделям,
вид снизу у обычных/деревьев и save/reopen размещённых экземпляров. В полном
production каталоге пользователь уже запустил: authored assets тестами не используются
как write-fixture. Очень большой объект может задержать текущий кадр; yield/cancel
между моделями, не прерывает meshing на половине.
Расширенный targeted suite, library/workshop layout, object Canvas и generator
editing прошли; native isolated editor проверяет реальную library button на двух
fixture ID, включая outside-scene asset, прогресс и per-model history. Fixture
source/import setup settle выполняется до capture стартового source hash:
изменения setup/UID import не приписываются library-команде.

`tools/test_voxel_scene_refresh.gd`: обычные/прозрачные модели, четыре inline
instances, subset collision, clockwise winding всех треугольников и нижние грани,
Source/map hashes, prefab UID, transforms/placement_id/authored descendants/visual
overrides. Undo возвращает точные prefab bytes и прежние mesh/shape references,
Redo — подготовленные; старые snapshots не мутируются. Save/reopen, skip current,
отказ при произвольном custom mesh/его surface material, сохранение per-instance
surface material override. Surface configure того же source + explicit
refresh меняет chunks без canonical изменения; доступный native adapter также
проверяется на winding (при отсутствии Voxel Tools используется GDScript fallback).
Headless fixture 2 models/4 props около 0.13 с; это не профиль больших деревьев.
Новый targeted suite и девять related suites PASS (object/assembly Canvas,
generator editing, object library/workshop layout, Surface Canvas workflow,
world Surface projection, native cutaway, projection cache). В актуальных
авторских tree_190013632/tree_1511837690_canvas_1665774388 остаются UID warnings
по старым external meshes с корректным text-path fallback; их исходники не
переписывались. Cold isolated editor также предупреждает о legacy material UIDs.
Это отдельно от ошибок/готовности самой refresh-транзакции.
Native Forward+ scene-refresh before/after captures и сценарий PASS; изображения
просмотрены. После обновления нижние грани обычных voxel props закрыты.

В рабочем Godot: сохранить/отменить Canvas draft, перейти в 3D → «Ещё…» →
«Обновить воксели сцены». Статус открывается в Ember Migration и перечисляет
обновлённые модели/экземпляры/Surface и причины пропуска. Покрутить снизу обычный
объект и дерево, проверить обновление без закрытия сцены, Ctrl+Z/Redo, Ctrl+S и
повторное открытие. Inspector → Rebuild prefab обновляет только выбранный model_id
(все его экземпляры), другие модели не меняются. Проверить авторские mesh-правки:
они должны приводить к пропуску модели, а не исчезать. Source/recipe не пишутся.
Surface requeue идёт асинхронно в штатном frame budget; scene Undo касается
замены экземпляров/prefab, а не canonical source или временных Surface chunks.

`tools/editor_test_voxel_scene_refresh.gd` — opt-in только в отдельной
ember-canvas-smoke-refresh-* копии: реальная кнопка dock, EditorUndoRedoManager,
изменение open inline mesh/shape, неизменность source/map/pose и editor save/reopen.
Native isolated editor сценарий PASS; рабочая пользовательская приёмка открыта.

## Общий редактор рецептов генерации (ручная приёмка открыта)

2026-09-12: после вариаций/bottom fix 15 targeted/related suites PASS без ERROR/WARNING — generator_editing,
workshop_layout, large_tree_object/dialog, generator, tree/bush/grass_generator,
object_canvas, assembly_canvas, projection_cache, stamp, selection_interaction,
surface_canvas_workflow, object_library_layout. Assembly Canvas повторно проверен
после capability guard общей панели (target_name/generator_context).
Native Forward+ generator_editing capture и весь сценарий — PASS; изображение
просмотрено, параметры прокручиваются отдельно, кнопки доступны. Скриншот не
заменяет пользовательскую оценку формы и живой workflow в рабочем editor.

`tools/test_voxel_generator_editing.gd`: exact skeleton capture 64/128/256 и три
формы, неподвижные wood/collision при всех foliage controls, palette-only geometry,
bare tree, thickness без перестановки lines, validation, recipe save/reopen и
детерминированная пересборка. Реальный Canvas: contextual tab, descriptor control,
draft buttons/Ctrl+Z/Ctrl+Shift+Z, exact prefab mesh preview без изменения source,
RMB camera, отдельный variant source/recipe/prefab, scene Undo/Redo/save/reopen,
preview==saved geometry, discard, выбор кисти/смена вкладки, ordinary tab hiding.
Fixtures пишут только в отдельные `user://` sources/recipes/prefabs.
Native Forward+ `-- --capture` сохраняет `user://voxel_generator_editing.png`
и `user://voxel_generator_bottom.png` (камера снизу).

Дополнение 2026-09-12: generator_editing проверяет clockwise triangles всех шести
сторон, family grouping одной карточкой, dropdown concrete variation Place/Edit,
case-insensitive duplicate names, standalone отдельную карточку, update одного
model_id и двух linked props с Undo/Redo source+recipe+mesh, внешний source hash
конфликт. object_canvas проверяет opening точного старого DOWN winding без записи
source и отказ при посторонней ручной mesh-правке; старые BarrelA/CargoA открываются.
Prefab rebuild gate повторно PASS после пересборки только control lantern_stone
prefab/двух mesh; source и карта не изменены, UID/четыре placements сохранены.

Вручную: открыть готовое большое v2 дерево в Canvas → Генератор. Поменять цвет
листвы на осенний, количество 100/30/0, размеры/приплюснутость/сомкнутость;
собирать preview после каждой правки и смотреть, что ветви не перемещаются.
Толщина/сужение меняют только объём ветвей. Проверить draft Undo/Redo, RMB/MMB/zoom,
Esc и выход в Части, затем Save variant — рядом появляется отдельный объект.
Выйти из генератора для общего scene Undo/Redo; сохранить и открыть сцену заново,
открыть variant в Canvas и убедиться, что recipe/cаркас восстановлены.
Исходное дерево и ручная лепка остаются нетронутыми; ручные правки не копируются
в рецепт. Смена объекта сбрасывает parameter draft. Classic/остальные генераторы
ещё не показывают эту вкладку; это не исчезновение их старого инструмента создания.

Проверка вариаций в рабочем editor:
1. Сохранить «Лето», затем «Осень» как новые вариации одного дерева: в Объектах
   одна карточка, справа dropdown; выбранную вариацию можно открыть и поставить.
2. Обновить выбранную «Осень»: изменяются только её экземпляры; выйти из
   Генератора, проверить общий scene Undo/Redo, сохранить и повторно открыть сцену.
3. «Отдельный объект» создаёт самостоятельную карточку. Пустые/повторяющиеся
   имена запрещены. Старые независимые деревья автоматически не объединяются.
4. При ручной лепке обновление поверх вариации блокируется; новый вариант
   доступен, но не включает ручные правки. Другая вариация не должна меняться.
5. Проверить дерево снизу. Для старого уже записанного mesh выбрать prop в
   Inspector → «Rebuild prefab»; исходник/placement не меняются.

## Полировка больших деревьев (художественная приёмка открыта)

Проверено 2026-09-12: все восемь targeted suites — generator, tree_generator,
large_tree_object, large_tree_dialog, object_library_layout, stamp, object_canvas,
editor_filesystem — PASS. Native Forward+ capture диалога при 1280×720 — PASS,
изображение просмотрено: preview и кнопки доступны, параметры прокручиваются
отдельно. Fixture timings: генерация 64/128/256 — 79/329/169 мс; точный prefab
256 — 1414 мс (выше 128 используется предусмотренная плотность 32 vox/block).
Это не заменяет ручную оценку силуэта и поведения в рабочем редакторе.

`test_voxel_large_tree_object`: 64/128/256, height-1 без деревянного spike,
determinism, classic fallback с прежними defaults, влияние новых параметров,
различная ярусная крона, связность v2 fixture, storage envelope крайних параметров,
collision/Canvas и source+recipe+prefab save/reopen, placement Undo/Redo.
`test_voxel_large_tree_dialog`: default v2, invalidation после правки,
classic visibility, точный preview, layout 1280×900; native `-- --capture`
добавляет 1280×720, `user://voxel_large_tree_dialog.png`.

Вручную: Объекты → + Большое дерево → Крупные формы, 64 vox → собрать preview.
Сравнить с classic; проверить толщину ветвей 35/75, сужение 0/80, изгиб 0/80,
начало ветвления 20/50; пучки 80/160, приплюснутость 20/80, сомкнутость 15/85.
Изменения требуют нового preview и не пишут assets. Повторить три формы кроны,
Другой вариант, 128/256, цвета/корни. Создать → Undo/Redo → сохранить сцену →
открыть повторно; старый recipe открывает classic и не меняет старый экземпляр.
Это проверка геометрии/удобства; красивые toon shadows и свет — отдельный срез.

## Обновление файлов после сохранения (ручной gate открыт)

`tools/test_editor_filesystem.gd`: восемь запросов → один scan; импорт/scan
блокирует исполнение, но не теряет запрос; full supersedes source-only;
запрос из scan callback не теряется; слабая ссылка освобождает pending.
Обычный runtime-вызов не обращается к EditorInterface.
Связанные: party_save_v2, party_progression, voxel_object_canvas,
surface_canvas_workflow, voxel_stamp, voxel_generator, voxel_large_tree_object,
voxel_pattern, object_inspector_actions, voxel_selection_interaction,
voxel_merge, voxel_object_split, voxel_primitive_conversion, voxel_shapes.
12 сентября: 15 focused/related gates и 13 parse checks PASS без ERROR/WARNING.

`tools/editor_test_filesystem.gd` — opt-in EditorPlugin только в отдельном
ember-canvas-smoke-* project с отдельным config/name/user:// и cache. Скопировать
скрипт в папку тестового плагина; plugin.cfg использует относительный script.
Legacy pack_path нужен только temp-копии для прежних библиотек. Проверяются
Canvas Save + burst (один scan), Undo/Redo, scene save/reopen, detached discard,
повторная компиляция Party/Explore/progression/save scripts после сканирования.
Non-tool `Script.can_instantiate()` в editor не является parse gate: использовать
`reload(true) == OK`. Каждый запуск создаёт новый scene_path, иначе open_scene
может вернуть восстановленную старую вкладку, а не переписанный fixture-файл.
Логи обязательны: fixture PASS без проверки ERROR/WARNING недостаточен.
12 сентября: финальный native Forward+ запуск на RTX 5070 прошёл весь fixture
и завершился без ERROR/WARNING; diagnostics scans=3, merged=9, pending=0.
При успешном выходе fixture адресует WM_CLOSE_REQUEST только родителю
EditorInterface.get_base_control() (EditorNode), deferred. Propagate root close
ломает child traversal, а прямой SceneTree.quit обходил штатный editor exit
и оставлял Scan thread aborted; это ошибки автоматического выхода fixture,
не parse errors Party/Explore. Этот synthetic lifecycle не закрывает более
широкий ручной Причал/сохранения всех открытых authoring-сцен.

Вручную: после сохранения черновиков и перезапуска Godot очистить Output,
создать/изменить и сохранить несколько штампов и модель Canvas; Undo/Redo,
закрыть/открыть сцену, вернуться в окно после внешней правки. Проверить новые
Party/Explore parse errors и момент их появления. Полную причину прежних
intermittent diagnostics нельзя считать установленной по этому hardening-срезу.

## Одиночные объёмные штампы (manual gate открыт)

Автоматически: `tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless
--path . --script res://tools/test_voxel_workshop_layout.gd` и затем тот же запуск
для `test_voxel_selection_interaction.gd`, `test_voxel_selection_mask.gd`,
`test_voxel_stamp.gd`, `test_voxel_pattern.gd`, `test_voxel_generator.gd` и
`test_voxel_tree_generator.gd`.
Native: без `--headless`, добавить `-- --capture`;
captures `user://voxel_workshop_compact.png`, `user://voxel_workshop_layout.png`
и `user://voxel_stamp.png`. Fixtures только user://.
Связанные: test_voxel_selection_interaction, test_voxel_fragment,
test_voxel_merge, test_voxel_object_canvas; plugin check-only.

1. Слева выбрать `Выделение`, отметить небольшую разноцветную деталь. Открыть
   `Штамп` → `Библиотека` → `+ Новый штамп`, ввести название и сохранить. Источник не меняется.
2. Найти пресет по карточке/миниатюре → `Выбрать`. ЛКМ задаёт опору (для Add — перед
   видимой гранью), стрелки/XYZ уточняют позицию. Проверить поворот 90°,
   отражение и три опоры через прямые кнопки без выпадающих списков. Esc не меняет модель.
3. «Добавить»: занятое не перекрашивается. «Заменить»: occupied footprint меняет
   цвета/материальные каналы; пустой угол/дырка шаблона не стирает объект.
   Enter фиксирует один отпечаток, но тот же штамп остаётся под курсором для
   следующего. Два Enter создают две отдельные Undo-команды; Undo/Redo не снимает
   выбранный штамп и возвращает geometry/palette/parts каждого отпечатка отдельно.
4. В склейке выбрать часть для новых voxels; новые ячейки получают эту часть,
   replaced occupied сохраняют прежнюю. Проверить Save Canvas и F6 collision.
5. Save/reopen сцены и редактора: пресет в библиотеке, отпечаток в объекте.
   «Редактировать модель штампа…»: изменить шаблон, Save, затем новый отпечаток
   использует новую форму, ранее поставленные не меняются. Проверить discard.
6. Lock, выход за холст/срез, несовпадающие плотности, palette overflow — отказ
   целиком. Маска кисти при открытии штампа сохраняется, но её контур и действие
   приостановлены до возврата к совместимой кисти. Изоляцию/скрытие групп нужно
   отключить; чужие authored files не удаляются.
7. Повторить при 1280×720 и 1600×900: параметры и Apply/Cancel не обрезаны,
   footer-подсказка не занимает правую панель, обе панели сворачиваются, Canvas
   расширяется, `Не сохранено`, disabled и красная ошибка явно различимы. Внутри
   `Части` переключить `Выделение / Группы / Вид`: каждый сценарий имеет свой
   локальный scroll и не раскрывает остальные секции длинным полотном.
   Палитра и её пять действий остаются видимыми снизу слева при переключении
   между `Части / Библиотека`; длинная палитра прокручивает только образцы.
   Создать длинное имя группы/части: текст сокращается, ни одна кнопка или строка
   не пересекает правую границу панели.
8. В реальном editor при системном 125% масштабе видны обе правые вкладки. Scoped
   Theme меняет только мастерскую: normal/hover/active/primary/disabled различимы,
   шрифты и editor icons остаются из текущей темы Godot. Карточки прокручиваются
   отдельно, а выбранный штамп и `Выбрать / Редактировать` остаются видимыми.
9. В Object Canvas поле `Объект` меняет только имя выбранного экземпляра сцены.
   Пустое, недопустимое и занятое соседним узлом имя отклоняются; Enter и потеря
   фокуса применяют, Esc отменяет ввод. Undo/Redo и Ctrl+S + reopen сохраняют имя,
   но не меняют display name, model ID и файлы voxel-модели. В Surface поле disabled.
10. В палитре выбрать тёмный цвет и сравнить образец с hex в подписи: normal,
    hover и selected не меняют сам цвет swatch. Более светлая грань в 3D допустима
    как результат освещения; цвет образца должен оставаться точным.
11. Пройти `Кисть → Выделение → Маска → Кисть → Штамп → Кисть`: только текущий
    основной инструмент янтарный, Canvas не меняет размер. В библиотеке ЛКМ по
    модели ничего не лепит. Начать stamp path и сразу выбрать кисть: preview
    отменяется без изменения Resource и не возвращается сам. В активном штампе
    первый `Esc` отменяет только текущий черновик, второй `Esc` возвращает последнюю
    кисть; обычное выделение скрыто, но снова видно по V.
12. Пока штамп выбран и следует за мышью, вращать ПКМ, двигать СКМ и приблизить
    колесом у края Canvas. Черновик не применяется и не сбрасывается, ghost снова
    оказывается под курсором. Камера проходит через боковой ракурс к виду снизу;
    СКМ двигает также по вертикали, а off-center zoom удерживает деталь под мышью.
13. `Сгладить`: на широком бугорке сравнить `Ступени` и `Общий уровень`, затем
    сделать неглубокую ямку и переключить `Обрабатывать ямки`. Пустое отверстие
    не закрывается; радиусы 16/32 не дают заметного стоп-кадра. В `Рельефе`
    проверить прежнее `Наращивание`, затем `Генератор · Почва / Гребни`, отдельно
    сравнить `Детали · лёгкие` с прежним `Детали · мало` (лёгкий вариант должен
    оставлять редкие мягкие перепады примерно на 1–2 вокселя), затем проверить три
    направления и `Другой вариант`. Одинаковый вариант бесшовно продолжается
    соседним мазком, повтор внутри LMB не копит высоту; Undo отменяет весь жест.
14. `Штамп → Библиотека → + Новый источник → Камень`: изменить XYZ,
    `Неровность`, `Сколы`, `Форм в россыпи` 1/4/8 и `Размер форм ±` 0/25/50%,
    нажать `Другой вариант` и сохранить. Миниатюра показывает до четырёх форм,
    карточка — полный размер набора; `Редактировать` возвращает тот же рецепт.
    Затем через `Выбрать` проверить основную форму в `Один` и разные силуэты в
    `Россыпь` с автоматически предложенным шагом и облеганием. `Другой вариант`
    стабильно меняет расположение/выбор форм, preview не меняет Resource, Enter
    применяет, Undo возвращает весь отпечаток. Старые штампы, одноформенные камни
    и паттерны продолжают работать как раньше. В уже поставленном камне изменение
    рецепта будущих отпечатков ничего не меняет.
15. `+ Новый источник → Дерево`: сравнить высоту 10/18/32, толщину ствола,
    радиус кроны, ветвистость и неровность 0/50/100, затем задать разные цвета
    ствола и листвы. Боковая миниатюра должна показывать ствол и до четырёх форм.
    Сохранить набор из 4–6 форм, поставить `Один`, затем провести `Россыпью` по
    ровной и ступенчатой земле. Проверить предложенный шаг, `Другой вариант`,
    облегание, Enter и одну Undo. Редактирование рецепта не меняет уже поставленные
    деревья; старые штампы, камни и паттерны продолжают работать.
16. `+ Новый источник → Куст`: сравнить высоту 4/10/24, размах 2/6/12,
    стебли 1/6/12, пышность и неровность 20/60/100, затем два цвета и набор
    1/4/8 форм. Боковая миниатюра должна показывать низкие широкие силуэты, а
    `Другой вариант` — заметно менять ветвление без распада формы. Сохранить,
    поставить `Один`, провести `Россыпью` по ровной и ступенчатой земле и
    проверить предложенный шаг, облегание, Enter, одну Undo и edit/reopen.
17. `+ Новый источник → Трава`: сравнить высоту 2/6/12, размах 1/2/4,
    2/8/16 травинок, разброс высоты и наклон 0/50/100, два цвета и набор
    1/4/8 форм. Первый выбор предлагает `Россыпь` и полезный шаг; пучки растут
    вверх и привязываются корнем к каждой локальной верхней поверхности без
    внутренней деформации. Боковая грань получает явный отказ. До Enter только
    preview, после Enter одна Undo. В F6 земля остаётся физической, сквозь траву
    можно пройти. Обычный штамп на том же explicit-collision target физичен;
    save/reopen и discard рецепта сохраняют результат.
18. `Выделение → Два этапа`: начать сверху и протянуть область на первой грани.
    После первого отпускания прежнее выделение остаётся, геометрия не меняется,
    голубой preview фиксирует плоскость. Движением мыши внутрь проверить глубину
    1/2/8, точный SpinBox, второй клик и Enter. Повторить на четырёх боковых
    гранях и снизу; направление всегда задаёт первая грань. Почти фронтальный
    ракурс использует вертикальный ruler. Проверить `Новое`, Shift-add, Ctrl-
    subtract, одну Undo/Redo после подтверждения, Esc на обоих этапах, смену
    инструмента, маску кисти и обычную экранную `Рамку`. Ни один draft не меняет
    Resource; рельеф не огибается автоматически.

Большие штампы измерены отдельно (16384 vox, plan ~60ms); полная производительность
на авторском Причале и визуальная/input-приёмка остаются ручным gate.

## Нижняя полка объектов 3D (manual gate открыт)

Автоматически: `tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless
--path . --script res://tools/test_voxel_object_library_layout.gd`, затем
`test_voxel_visual_library.gd`, `test_voxel_large_tree_object.gd` и
`test_voxel_large_tree_dialog.gd`; `plugin.gd --check-only`. Native captures:
layout и large-tree dialog без `--headless` с `-- --capture`, результаты
`user://voxel_object_library.png` и `user://voxel_large_tree_dialog.png`.

1. В 3D нажать `Объекты`: снизу открывается полка, сцена и selection остаются
   видимы; модального окна нет. Повторить вход через Ember Migration.
2. Проверить поиск и фильтры `Все / Готовы в Godot / Ожидают переноса`.
   Выбранная карточка показывает превью, название, стабильный ID, размер, теги и
   owner; `Редактировать шаблон`, `Поставить в сцену` и `Ещё…` не уезжают при
   прокрутке каталога.
3. При выборе объекта сцены шапка пишет `рядом с … · смещение +X`; без selection —
   player_start или начало Map. Сменить selection при открытой полке: подпись и
   anchor должны обновиться.
4. Для native-модели нажать `Редактировать шаблон`: открывается Object Canvas с
   тем же Resource. Подсказка предупреждает, что Save затронет все экземпляры;
   проверить правку, Save, Undo/Redo и reopen на двух экземплярах этой модели.
5. Для legacy-модели кнопка называется `Перенести и редактировать`: одна migration
   Undo-команда создаёт Godot Resource и сразу открывает его в Canvas. Отменить
   перенос после выхода из Canvas и проверить возврат карточки в legacy-фильтр.
6. Поставить native и legacy-модель. Сохраняются прежние Map/Props owner, Undo/Redo,
   Ctrl+S и reopen; legacy prefab собирается существующим import owner. Открытие
   Godot Resource и перенос доступны только для подходящего owner.
7. Повторить при 1280×720 и 1600×900: каталог расширяется, правый details остаётся
   фиксированным, основная кнопка видима, текст не выходит за границы.
8. Нажать `+ Большое дерево`; проверить высоты 64, 128 и 256, толщину ствола,
   размах кроны, ветвистость, неровность, плотность листвы, цвета и
   `Другой вариант`. До `Собрать точный предпросмотр` файлы не создаются, OK
   disabled. После сборки изменение параметра снова требует явного preview.
9. Создать дерево: оно появляется как один обычный объект в `Map/Props` и как
   native-карточка в каталоге. Ctrl+Z/Redo снимает/возвращает placement; Save и
   reopen сцены сохраняют его. `Редактировать шаблон` открывает прежний Canvas.
   Долепить и удалить voxel, проверить Canvas Undo/Redo, Save/reopen и prefab.
10. В `Ещё…` выбрать `Создать вариант из рецепта…`: параметры и seed исходного
    дерева восстановлены, но подтверждение создаёт новый model ID и новый объект,
    не меняя прежние instances. У обычной модели без recipe команда disabled.
11. В F6 пройти персонажем вокруг кроны: ствол и толстые ветви имеют collision,
    листья не образуют невидимую стену. Сравнить silhouette/масштаб 64 и 256 с
    маленьким stamp-деревом 8–32; последнее остаётся в библиотеке штампов.

Ghost под курсором и выбор точки кликом не входят в этот срез: размещение пока
сохраняет прежнюю семантику +X/player_start и отдельно согласуется после UI gate.

## Склейка и разбор текущей формы (manual gate открыт)

Дополнительный gate совмещения: взять `Fragment_new` и нижний блок, нижний
назначить основным. При дробном смещении включить «Совместить сетки»: видны
полупрозрачное прежнее положение и Δ XYZ; сцена за окном не меняется. Снять
checkbox/отменить окно — исходные позиции прежние. Повторить и склеить: результат
совпадает с preview; один Undo возвращает детали и точные дробные позиции,
Redo возвращает склейку. Save/reopen и F6 сохраняют новую геометрию/коллизию.
При смене основной детали checkbox сбрасывается; rotation/scale не округляются.

Автоматически: `tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless
--path . --script res://tools/test_voxel_merge.gd`. `-- --benchmark` дополнительно
измеряет плотные 131072 вокселя; без `--headless`, с `-- --capture` — native
Forward+ preview в `user://voxel_merge.png`. Tests не меняют авторские карты.
Связанные: extraction, fragment, canvas_growth, object_split, assembly_canvas,
groups, object_canvas, native_voxel_resource, selection_interaction.

Ручная приёмка:

1. В 3D выбрать 2–3 native-доски одного родителя, при необходимости сохранить
   их через Canvas. «Ещё… → Склеить voxel-детали…»: выбрать основную,
   обновить preview. В пересечениях красная подсветка; отмена ничего не меняет.
2. Склеить: положение прежнее, одна модель. Ctrl+Z возвращает доски, Ctrl+Shift+Z
   возвращает склейку. Проверить цвета и актуальную collision через F6.
3. Открыть склейку в Canvas, удалить несколько вокселей. В списке
   «Новые воксели → …» выбрать исходную часть и долепить её; выбрать
   «Добавленное» и добавить отдельный выступ. Save, закрыть/открыть Canvas.
4. «Ещё… → Разобрать склейку…»: удалённое не возвращается, лепка остаётся
   в своей части, выступ становится отдельным объектом. Проверить Undo/Redo.
5. Save сцены, перезапуск Godot, F6 Причала: положение и collision не расходятся.
6. Повторить с поворотом 90° и плотностями 16/32. Произвольный относительный
   поворот, несогласованная сетка, лишний script/связь или overflow палитры
   должны дать объяснение без частично изменённой сцены.

Ограничения: ≤32 исходных частей (+Добавленное), ≤524288 ячеек, common parent,
совместимый материал/физика, без воды/custom lights и произвольного resampling.
Большие операции синхронны: замеры отдельных стадий не доказывают отзывчивость
редактора на полной авторской карте. Этот performance/manual gate не закрыт.

## Отделение фрагмента в объект (manual gate открыт)

Дополнение: по умолчанию остаться в Canvas с обновлённой геометрией и ракурсом;
проверить Undo/Redo без выхода. Повторить с включённым «Перейти в 3D к новой детали».
test_voxel_extraction проверяет оба исхода и синхронизацию чистого draft с историей.

`--headless --path . --script res://tools/test_voxel_extraction.gd`: detached
prepare, cut/copy, linked-source independence, material/groups, world position
при наклоне/масштабе, Mesh/Collision parity, one Undo/Redo, pack/save/reopen,
stale transform, late publication failure without partial scene changes,
whole-object cut, cross-section assembly cut/undo, UI confirmation/cancel/commit.
С `-- --benchmark`: 32768 выбранных из 131072 ячеек; отдельно prepare/commit.
Замер 10 сентября: prepare 2381 мс, commit 4431 мс на плотной fixture 128×8×128.
Публикация пока синхронная: заметная пауза на больших объёмах остаётся ограничением,
эти числа не являются доказательством отзывчивости на максимальном Причале.
С `-- --capture` без --headless: native Forward+ подтверждение при 1280×720.
Связанные regressions: object_canvas, assembly_canvas, fragment,
selection_interaction, object_split (tools/test_voxel_*.gd).
Ручной сценарий: открыть доску из сцены в Canvas → выделить край → Save Canvas,
если были правки → «Вырезать в новый объект…» → подтвердить → 3D выделяет
Fragment. Проверить отсутствие сдвига/щели, collision, отдельно сдвинуть деталь,
Undo перемещения, Undo отделения, Redo; сохранить сцену и открыть после рестарта.
Для копирования оригинал не меняется: копия совпадает с ним, сдвинуть отдельно.
Повторить через границу секций, затем открыть общий Canvas сборки. Отмена
подтверждения не создаёт файлов. Проверить понятный отказ для несохранённых
правок/общей модели/Surface/неподдерживаемой физики. Авторский Причал тестами
не изменяется; auto-removal новых файлов не предусмотрен.

## Фрагменты Canvas — фаза 1 (manual gate открыт)

«Двухэтапное выделение»: test_voxel_surface_marquee проверяет 6 направлений,
16/32 density, раздельные footprint/depth bounds, screen ruler, обратное
протягивание, параллельный луч и bounds clip. test_voxel_selection_interaction
проверяет плоский первый этап без commit, второй этап глубиной 2, второй клик,
одну Undo/Redo, Ctrl-subtract и Esc с сохранением прежнего selection; Resource
не меняется. Native capture сохраняет user://surface_marquee.png.
Вручную: V → «Два этапа» → протянуть верх доски → после отпускания вытянуть
голубой объём внутрь → подтвердить вторым кликом или Enter. Повернуть камеру и
начать на каждом боку и снизу; направление не перескакивает на соседние грани.
Проверить точную глубину, Shift/Ctrl, Esc, начало вне объекта, маску кисти,
дальнейший перенос/Undo и отсутствие изменений Resource/save/reopen.

UX-коррекция: `tools/test_voxel_selection_interaction.gd` проверяет видимую
поверхность против насквозь, живой detached ghost, mouse-release selection,
integer axis drag, inline commit/Undo/Redo, invalid destination, Esc. С `-- --capture`
без --headless создаёт native Forward+ screenshot 1280×720. Старый selection
regression явно выбирает режим связного цвета вместо нового default marquee.
Актуальный ручной сценарий: V → протянуть рамку по доске; переключить
«Видимая поверхность / насквозь», сравнить внутренние/задние воксели; Shift/Ctrl.
Нажать «Перенос / копия / поворот…» → тянуть X/Y/Z прямо в Canvas → Enter/Esc.
Проверить числовое смещение, 90° и копию, красный запрещённый результат,
Ctrl+Z/Redo, Save/reopen, camera orbit/pan, срез и смену объекта.
Подсветка наведения должна совпадать с hit вокселем, а не с размером кисти.
Нижеследующий двухкликовый/модальный сценарий — исторический gate фазы 1;
он заменён описанным выше и не является текущей инструкцией для пользователя.

Targeted: `--headless --path . --script res://tools/test_voxel_fragment.gd`.
Проверки: чистый preview, материалы/группы, перенос/копия/90°, Undo/Redo,
stale/overlap/locked/bounds/slice refusal, save/reopen, два угла рамки,
add/subtract, cancel и диалог. Замер 16384 выбранных из 131072 ячеек.
Связанные scripts: test_voxel_selection, test_voxel_selection_mask,
test_voxel_groups, test_voxel_object_canvas, test_voxel_assembly_canvas.
Native Forward+ capture: тот же fragment script без --headless, с `-- --capture`.
Вручную: Canvas → Выделение вокселей → Объёмная рамка → включить «Выбирать»
→ два противоположных угла доски (для толщины можно повернуть камеру).
Shift добавляет, Ctrl вычитает второй объём. «Перенос / копия / поворот…»:
смещение/ось/90°/копия → Обновить предпросмотр → Применить. Проверить совпадение,
Undo/Redo, отмену, запрет перекрытия; сохранить Canvas/сцену и открыть снова.
Отделение в новый объект не входит в готовую фазу 1; общий контракт остаётся открыт.

## Поверхность прохода (ручной gate открыт)

`--headless --path . --script res://tools/test_walk_surface.gd`: создание,
редактирование, Undo/Redo, отмена, stale/invalid отказ, pack/save/reopen,
обычный physics ray и реальный EmberPlayer на опоре, отсутствие runtime Mesh.
Связанные gates: test_voxel_canvas_context, test_voxel_assembly_canvas
(включая сохранение секций рядом с опорой), test_voxel_placement,
test_voxel_scene_assembly, test_party_followers.
Native Forward+ capture: тот же script без --headless с `-- --capture`;
проверяет диалог на 1280×720 и 1600×900, но не заменяет редактор.
Вручную: выбрать группу настила → Ещё… → Поверхность прохода…; проверить
preview/применение, размер/наклон/высоту, предупреждения выступов, отмену;
выбрать WalkSurface и повторно открыть; Undo/Redo; переместить всю группу;
переключить «Показать поверхности прохода»; сохранить/перезапустить/F6.
Ожидание: сетка исчезает в игре, герой проходит настил и оба входа, края не
расширяют мост невидимо; общий Canvas секций не теряет опору. Доски и их
коллизии не изменяются. Вход с уступом требует выравнивания или наклонной опоры.

Статус: рабочая матрица проверок, 9 сентября 2026.

Этот документ отвечает на вопрос «что проверить сейчас». Подробные сценарии
завершённых v1/v2-этапов и старые журналы ручной приёмки можно восстановить из
монолитного Git checkpoint `20685ac`; они не определяют текущий порядок и не
заменяют будущие небольшие checkpoints. Условия окончательного выхода из JOI
принадлежат `docs/EMBER_JOI_EXIT_PLAN.md`.

## Основной принцип

Проверка идёт от узкого к широкому:

1. parse/static contract затронутых файлов;
2. самый узкий `tools/test_*.gd`;
3. связанный suite подсистемы;
4. cross-system regressions владельцев данных;
5. save/reopen, Undo/Redo, discard и validation, если менялся editor;
6. обычный Godot 4 Forward+ для UI, render, physics, input и ощущения;
7. полный headless-набор перед самостоятельным checkpoint.

Скриншот подтверждает композицию, но не клики, focus, input, persistence или
игровое ощущение. Ручная приёмка пользователя обязательна там, где результат
зависит от удобства или визуала.

## Безопасный запуск

Godot console:

`tools/godot/Godot_v4.7.2-stable_win64_console.exe`

Один targeted test:

```powershell
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_example.gd
```

Пакетный repository contract:

```powershell
python tools/test_vox_axes.py
```

Никогда не запускать рабочий checkout через `--headless --editor`: это меняет
editor-themed import variants и вызывает массовый повторный импорт. Editor/import
smoke выполняется только в отдельном checkout или import cache.

### Точная voxel-расстановка 2.3 (10 сентября 2026)

Ручная приёмка расстановки подтверждена пользователем.

### Группировка и ряд копий (10 сентября 2026, awaiting manual)

`tools/test_voxel_scene_assembly.gd`: unique user:// fixtures; rotated/nonuniform
parent, linked IDs, preview==commit, world collision relation, whole-row Undo/Redo,
repeat, group/ungroup world poses/owners/unique-name/order, grouped pack/reopen,
последующие наклоны и смещения, COW отдельной копии, byte-identical source,
scene save/reopen, stale/zero-step refusal, внешний NodePath, UI signals/Cancel.
Замер 32 копий печатается отдельно; это fixture-измерение, не гарантия FPS Причала.
`-- --capture` без headless запускает тот же fixture в Forward+ и сохраняет окно
1280×720 и 1600×900 без scaling. Нативный preview не заменяет настоящие editor clicks.
Новый gate и связанные placement/object_canvas/object_split/assembly_canvas PASS;
Forward+ оба размера просмотрены. 32 небольшие fixture-копии: 4.9–6.9 мс
на prepare+commit в двух проходах; для тяжёлых пользовательских моделей это
не является обещанием времени открытия или сохранения Canvas.

Ручной сценарий: выбрать доску → «Ещё… / Дублировать со смещением…» → задать шаг
X и 3 копии → проверить preview → создать. «Повторить дублирование» добавляет
одну следующую доску; смена выбранной детали меняет источник повтора. Наклонить
две доски через точную расстановку. Выбрать доски одного родителя (Ctrl в дереве)
→ «Собрать в группу» → переместить/повернуть группу → «Разгруппировать».
Проверить Cancel, Undo/Redo, сохранение/перезапуск и F6. Новые model-файлы не
появляются до Canvas Save реальной правки. Общий Canvas неровного моста не заявлен.

### Автоматические проверки расстановки 2.3

`test_voxel_placement.gd` использует только unique `user://` fixtures и проверяет
фактические размеры voxel после поворота/nonuniform scale, общий world step,
preview==commit, сохранение полного basis без decomposition, transformed parent,
центр/lower/custom source pivot, snap самой опорной точки, Undo/Redo, discard,
collision/children вместе с корнем сборки, save/reopen и byte-identical sources.
Stale parent/intermediate hierarchy, top-level descendant и non-finite plan
отказывают; ошибочный plan очищает возможность применить предыдущий preview.

`test_voxel_placement_preview.gd` запускается обычным Forward+ без `--editor` на
сохранённом TimberPier из 12 секций. Signal-driven gate проверяет числовой поворот,
смену pivot без скачка уже повёрнутого preview, auto-snap только изменённой оси и
отсутствие live mutation. Native unscaled captures 1280×720 и 1600×900 сохраняют
двухколоночный диалог: controls scroll слева, постоянно видимый target+context
preview справа, Apply/Cancel снаружи. Это не заменяет реальные editor clicks.

Ручной gate: в Причале выбрать `TimberPier/Visual` или отдельную `Part` → «Точная
расстановка…». Отключить snap, дать доске небольшое смещение и произвольный угол;
Cancel не меняет сцену. Открыть снова, выбрать нижний угол, шаг 1, «Привязать
сейчас», повернуть +90° и применить. Проверить Ctrl+Z/Redo, затем сохранить сцену,
перезапустить editor и запустить F6. Для живого настила повторить на нескольких
отдельных досках: scale/наклон не должны самопроизвольно выровняться. Group
creation, duplicate-repeat, склейка и общий Canvas наклонённых деталей этим gate
не заявлены.

### Конверсия простых форм 2.2 (10 сентября 2026)

Assembly Canvas gate: `test_voxel_assembly_canvas.gd` проверяет общий draft,
каналы/группы, мазок через две секции и один Undo, сохранение 2 из 4, неизменные
hash/IDs остальных, batch Undo/Redo, ошибку второго destination без частичного
scene apply, cancel/discard, scene reopen, несовместимое смещение и разные
порядки палитр. `test_voxel_assembly_preview.gd`: Forward+ viewport всей сборки
192×10×256 из 12 секций, только fixtures в user://. Ручной gate: выбрать группу
(не Part) → «Объект / сборка в Canvas» → мазок через стык → Ctrl+Z/Redo → Save →
сохранить сцену → переоткрыть группу/отдельную Part → F6 и пройти через стыки.
Целый editor click lifecycle этим runtime preview не подтверждается.

Оптимизация/резка: PASS `test_voxel_projection_cache`, `test_voxel_object_split`,
`test_voxel_object_canvas`, `test_voxel_canvas_growth`, `test_voxel_shapes`,
`test_voxel_primitive_conversion`. Cache test сравнивает все mesh arrays/indices
и collision faces со старым builder, halo-правку, palette/density/empty и
отсутствие alias на опубликованный mesh. Split test проверяет все каналы,
группы, transformed world anchors, unique IDs, Undo/Redo, source hash и reopen
геометрии/коллизии; physics ray проверяет высоту точно на стыке X и по обе
стороны от него. `benchmark_voxel_save_reuse` A/B (старые повторные сборки
только in-memory): настил 192×10×256, до 11964/14007 мс, после 6674/5085 мс.
`test_voxel_split_preview` проверяет native окно на текущем TimberPier Forward+
без применения; это не полный editor click/physics gate.
Ручной gate: выбрать voxel Visual настила → «Разрезать на секции…» → 64 →
проверить 12 границ/деталей → отменить (нет изменений) → открыть/применить →
Ctrl+Z/Redo → открыть одну Part в Canvas, изменить/сохранить → сохранить сцену →
перезапустить → F6 и пройти через стыки. Сложные overrides/вода должны отказать
без изменений сцены. При сбое диска возможны оставленные recoverable part assets.

Большой бюджет: `test_voxel_shapes` проверяет ровно 524 288, отказ выше порога,
явное разрешение предпросмотра и его сброс после изменения параметров.
`test_voxel_primitive_conversion` включает размеры TimberPier 192×10×256,
физический/декоративный вариант, edit/save/reopen источника, Undo/Redo и сцену.
Ручной gate: TimberPier → при необходимости совместить коллизию → «Форму в
voxel…» → разрешить тяжёлый preview → обновить → преобразовать → мазок →
сохранить Canvas и сцену → перезапуск → F6. Отмена до применения не меняет сцену.

Совмещение коллизии: выбрать TimberPier с небольшим смещением Visual →
«Форму в voxel…» → проверить точные XYZ в подтверждении → «Совместить коллизию
с моделью». Visual не двигается; Collision получает его transform. Повторная
команда открывает conversion dialog (лимит размера остаётся). Ctrl+Z возвращает
расхождение, Redo устраняет его; сохранить/открыть сцену и повторить команду.
Отмена подтверждения ничего не меняет. Headless conversion test проверяет
совмещение/Undo/Redo для трёх форм и отказ для disabled collision; PASS.

5/5 PASS: `test_voxel_primitive_conversion`, `test_voxel_shapes`,
`test_voxel_object_canvas`, `test_voxel_canvas_growth`, `test_voxel_canvas_context`.
Conversion gate: блок/цилиндр/сфера с физикой и без, поворот/неравномерный scale
parent, fit bounds по параметрам PrimitiveMesh (не погрешностям tessellation),
имя/owner, отсутствие двойной коллизии, layer, Undo/Redo, save/reopen/Canvas,
отказ от PlaneMesh/конуса и stale preview. Preview не создаёт files.

Opt-in `tools/editor_test_voxel_conversion.gd` только в disposable
`ember-canvas-smoke-*`: настоящая toolbar-команда на MooringPost96_240,
переключение исходник/voxel, commit→Canvas+окружение, Undo/Redo, scene Save/reopen.
Forward+ functional PASS; native dialog и Canvas captures просмотрены. Не
называть zero-error lifecycle: при автоматическом выходе остаются известные
absolute-get_node diagnostic и scan-aborted; node cache error не наблюдался.

Ручная приёмка: сохранить сцену → выбрать `Map/Props/MooringPost96_240`
или его `Visual` → «Форму в voxel…» под 3D toolbar → сравнить исходник/preview →
«Преобразовать и открыть Canvas». Включить окружение, сделать мазок, сохранить
Canvas и сцену. Отдельно проверить отмену диалога (нет новых объектов/файлов),
Undo/Redo конверсии в 3D, reopen и F6: столб стоит на прежнем месте и имеет
одну обновлённую коллизию. Проверить простые цилиндр и сферу аналогично.
Большой TimberPier/StoneQuay может превышать лимит: явно уменьшить XYZ в
preview; габариты сохраняются fit scale, а не скрытым clamp.

### Object Canvas: переключаемое окружение (10 сентября 2026)

5/5 focused/related scripts PASS: `test_voxel_canvas_context`,
`test_voxel_canvas_growth`, `test_voxel_object_canvas`, `test_voxel_shapes`,
`test_voxel_surface_sculpt`. После уточнения stable anchor повторены context
и object-canvas tests: PASS. Context gate проверяет transform при повороте и
неравномерном масштабе parent/prop, material identity, remap после расширения,
Save Undo/Redo, прозрачность без mutation, исключение target/hidden/physics,
отсутствие scripts/owners у фона, refresh и освобождение при закрытии сцены.

Opt-in `tools/editor_test_voxel_context.gd` только в disposable
`ember-canvas-smoke-*` project: Причал/BarrelA, 60%→100%→off, совпадающий ray pick,
реальный draft stroke/discard без записи source. Forward+ functional PASS,
68 фоновых visuals за ~1.5 мс; captures 1600×900 просмотрены. На автоматическом
выходе только известный warning `Scan thread aborted`, без engine/script errors.

Ручная приёмка: выбрать BarrelA в Причале → «Объект в Canvas» → «Показать
окружение»; рядом должны появиться настил и соседняя бочка. Фон 100% для посадки,
30–60% для лепки. Нарисовать, Undo/Redo, сохранить Canvas и сцену; фон сам по себе
не создаёт unsaved changes. Выключить toggle — прежний изолированный вид.
После изменения соседей в 3D нажать «Обновить окружение». После grow холста
посадка прежних вокселей не меняется. Свет карты/динамика проверяются отдельно F6.

### Проверки расширения и cross-map создания

Команды: `tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path .
--script res://tools/<name>.gd` (в одну строку, последовательно).
Прошли 7/7: `test_voxel_canvas_growth`, `test_voxel_shapes`,
`test_voxel_object_canvas`, `test_voxel_surface_sculpt`, `test_voxel_groups`,
`test_content_migration_report`, `test_content_migration_dashboard`; exit 0,
без script/engine errors. Growth 16³→32³ вместе с Canvas rebuild: 44–51 мс.
Проверяются preview без mutation, remap материала/групп, размеры, запрет
shrink/скрытого округления/переполнения, Undo/Redo, discard, Save Undo/Redo,
геометрия без world-сдвига/масштабирования, коллизия, reopen.

Actual-editor fixture `editor_test_voxel_shapes.gd` расширен переходом
agent_sandbox→test_pier, созданием/Inspector/Save на обеих картах, расширением
и повторной загрузкой сцен. Forward+ functional assertions PASS, node-cache
ошибка после исправления не повторилась. Просмотрены captures новых кнопок и
native growth dialog при 1600×900. Это не утверждение о чистом shutdown всего
редактора: автоматический прогон оставлял progress-dialog/absolute-get_node
diagnostics и scan-aborted при завершении; его нельзя называть zero-error smoke.
Последний Forward+ повтор с ожиданием filesystem завершил все assertions,
включая фактическое открытие creation dialog через кнопку Canvas. Ошибок
node-cache/progress-dialog больше нет; остаются только absolute-get_node и
scan-aborted при автоматическом выходе. Логи временной копии:
`%TEMP%/ember-canvas-smoke-growth-c58d315d40ed4636bf7ab5efd9c87715/growth6-{out,err}.log`.

Ручная приёмка:
1. Сохранить текущие правки, перезапустить редактор для обновления обеих plugin
   панелей. В 3D под штатными инструментами видны «+ Объект» и «Объект в Canvas».
2. Создать блок 16×16×16, открыть Canvas → «Расширить холст…» → 32×32×32 →
   «Применить». Это запас пустых вокселей, а не растяжение объекта.
3. Нарисовать в новом запасе, отменить мазок и расширение, повторить Redo.
   Проверить отдельно «Отмена» в диалоге и отказ от несохранённых изменений.
4. Сохранить Canvas, затем сцену Ctrl+S в 3D. Повторно открыть объект: размеры
   сохраняются, старая часть не сдвинулась, коллизия соответствует форме.
5. Открыть две карты, на каждой создать объект; выбрать его в Inspector,
   сохранить сцену, переключиться назад. Нет node-cache ошибки, объект принадлежит
   нужной карте. Проверить также «+ Объект» в Canvas и отмену создания.

Ограничения: XZ кратны плотности 16/32 и растут симметрично, Y растёт вверх;
до 524 288 ячеек, нет уменьшения и расширения заполненных water channels.

Все test fixtures пишутся в `user://` или временные данные. Авторские `.tres` и
`.tscn` не перезаписываются ради теста. Отключённый `addons/at-icons` остаётся
изолирован через `.gdignore`.

## Как выбрать gate

- Документация без изменения контрактов: `git diff --check`, проверка ссылок и
  `python tools/test_vox_axes.py`.
- Resource/schema: validation, normalization, save/reopen и все consumers.
- Editor mutation: model/action test, Undo/Redo, discard, save/reopen и реальный
  Inspector/workspace.
- Runtime state: pure owner test, transition/serialization и запуск сцены.
- Render/physics/input: headless correctness плюс ручной Forward+.
- Производительность: повторяемый профиль на репрезентативной карте до и после;
  schema меняется только при измеренном доказательстве.
- Migration mutation: read-only inventory → strict parity → ограниченная запись →
  Undo/Redo → reopen → frozen-source hash.

## Surface и voxel authoring

Минимальный suite выбирается по затронутому контракту:

- Resource/serialization: `tools/test_native_voxel_resource.gd`;
- selection и masks: `test_voxel_selection.gd`,
  `test_voxel_selection_mask.gd`;
- groups/palette: `test_voxel_groups.gd`, `test_voxel_palette.gd`;
- sculpt/tools: `test_voxel_surface_sculpt.gd`,
  `test_voxel_tools_backend.gd`;
- Canvas lifecycle: `test_surface_canvas_workflow.gd`,
  `test_surface_height_slice.gd`, `test_native_cutaway.gd`;
- large dense profile: `test_surface_large_profile.gd`;
- derived prefab/preview: `test_voxel_prefab_rebuild.gd`,
  `test_voxel_preview_renderer.gd`;
- physical world: `test_world_surface_projection.gd`,
  `test_fan_town_surface_projection.gd`;
- water boundaries/contact: `test_water_contact_boundaries.gd`;
- scale/tile library: `test_voxel_tile_scale.gd`,
  `test_battlefield_tile_library.gd`.

Editor acceptance дополнительно требует:

- одна mutation = одна понятная Undo/Redo-операция;
- Save/Discard/Cancel при выходе и корректный reopen;
- editor-only selection, visibility, camera и slice не попадают в gameplay data;
- мелкий input не запускает полный remesh/reload;
- Surface, world и battle используют одинаковые palette/water границы;
- обычный Forward+ viewport без швов, исчезающих chunks и renderer warnings.

## Graph, Object Inspector и native content

Основные gates:

- `tools/test_graph_workspace.gd` и `test_graph_lifecycle.gd`;
- `test_object_inspector_model.gd`, `test_object_inspector_actions.gd`,
  `test_object_inspector_panel.gd`;
- `test_action_resource.gd`, `test_action_script.gd`,
  `test_action_chain_authoring.gd`;
- `test_dialogue_authoring.gd`, `test_vn_dialogue_resource.gd`;
- `test_quest_state.gd`, `test_quest_journal_authoring.gd`,
  `test_quest_usage_index.gd`;
- `test_item_resource.gd`, `test_shop_resource.gd`,
  `test_shop_persistence.gd`;
- visual catalogs: `test_visual_library.gd`, `test_map_visual_library.gd`,
  `test_voxel_visual_library.gd`, `test_vn_background_library.gd`,
  `test_vn_portrait_library.gd`;
- scene binding: `test_standalone_trigger_authoring.gd`,
  `test_interact_launch_rules.gd`, `test_scene_edit_roundtrip.gd`.

Ручная проверка проводится минимум на 1280×720 и 1600×900, если менялась
компоновка. Нужно проверить mouse и keyboard focus, dirty-draft guard, validation
на конкретном Resource, save/reopen и сохранение scene-owned children после
reimport.

## Exploration, party и save

Основные gates:

- `tools/test_progress_restore.gd`;
- `test_camera_relative_movement.gd`;
- `test_party_save_v2.gd`, `test_party_followers.gd`,
  `test_party_progression.gd`;
- `test_inventory_equipment.gd`, `test_health_consumables.gd`;
- `test_map_transition.gd`, `test_talk_shop.gd`;
- `test_explore_pause_menu.gd`, `test_defeat_respawn.gd`;
- `test_combat_encounter_transition.gd`, `test_combat_result_bridge.gd`.

Обязательные сценарии save:

1. новый старт и три ручных слота;
2. отдельный autosave и metadata без загрузки полного состояния;
3. v1→v2 один раз с byte-identical backup;
4. несовместимая экипировка возвращается в общую сумку;
5. HP/MP/XP/equipment переоткрываются, derived stats пересчитываются;
6. удаление слота требует подтверждения и оставляет recovery-копию;
7. бой получает предбоевой snapshot, Retry начинает с него, результат
   применяется один раз.

Ручной Forward+ gate проверяет смену лидера через `Tab`, оба режима следования,
переход между картами и сохранение/загрузку из реального pause menu.

## Combat

Базовый suite:

- Resource contracts: `tools/test_battlefield_resource.gd`,
  `test_combat_status_resource.gd`, `test_combat_action_resource.gd`,
  `test_combat_unit_resource.gd`,
  `test_combat_ai_profile_resource.gd`, `test_combat_loot_table_resource.gd`,
  `test_encounter_resource.gd`;
- resolver: `test_combat_prototype.gd`;
- navigation/positioning: `test_combat_grid.gd`;
- controller/HUD: `test_combat_lab.gd`;
- arenas/camera/view: `test_combat_arena_scenes.gd`,
  `test_combat_camera_rig_preview.gd`, `test_combat_vertical_view.gd`;
- animation: `test_combat_vertical_animation.gd`;
- performance: `test_combat_vertical_profile.gd`;
- content/effects: `test_combat_effect_library.gd`,
  `test_combat_personal_actions.gd`;
- inventory/progression: `test_combat_items.gd`,
  `test_party_progression.gd`;
- results/transition: `test_combat_result_bridge.gd`,
  `test_combat_encounter_transition.gd`.

При изменении общей боевой логики сначала запускаются точные targeted tests,
затем все `tools/test_combat*.gd` и соседние Battlefield/Encounter/party/save
gates.

Combat invariants:

- один resolver и один canonical battle snapshot;
- статусы принадлежат canonical `.tres`, а effect validation не принимает
  неизвестные status IDs;
- внутренние status/damage/effect rules не владеют snapshot и не обходят
  публичные `preview/commit`;
- preview и commit используют один зафиксированный результат;
- hostile hit/crit/damage не раскрываются игроку до commit;
- support, healing, movement и mechanisms детерминированы;
- игрок и AI используют одинаковые terrain, range, LOS и path rules;
- movement-only AI pursuit проходит полный result-контракт, меняет клетку и
  завершает ход ровно один раз; отклонённый commit не запускает presentation;
- одна проходимая высота на колонку, без stacked floors;
- animation/HUD не мутируют gameplay state;
- Retry не сохраняет затраты пробной попытки;
- победный результат и XP применяются ровно один раз.

Ручной Combat Lab gate проверяет поле 10×8 и 16×12, camera axis locks и focus,
mouse/keyboard/gamepad navigation, browse/confirm/target/cancel, auto-approach,
Attack/Defend stop marker, статусы, подъём/бросок и отсутствие исчезновения поля
на допустимом наклоне.

## Lighting и Forward+ gate

Профили света проверяются в порядке `0/2/4/8/12/16`: `8` — production,
`12` и `16` — stress. В Play `F3` показывает active/candidate shadows и
frame/render metrics, `F4` переключает профили. Изменение света, материалов,
воды или derived mesh проверяется на production-профиле и минимум одном stress
профиле; подробный художественный gate остаётся в `LIGHTING_GATE.md`.

Механики проверяются на Ember-сценах, а не на `hu_tao_yard`/`hu_tao_p1`.
Forward+ проверка должна подтвердить отсутствие shader/renderer errors,
исчезающих chunks, неверной прозрачности и изменений collision из-за
visual-only эффекта.

## Combat Lab v2.64.4 positional/hold regression gate

Срез зафиксирован в checkpoint `4569f64`; дополнительная ручная проверка кольца
завершений подъёма принята пользователем. Regression gate сохраняет следующие
критерии:

1. непарные support/heal/item/cell/lift-команды используют тот же positional
   planner, что hostile-команды;
2. hover показывает range и возможную stop-cell, confirm открывает targeting,
   cancel возвращает прежний focus;
3. если применение недостижимо за MOVE, герой останавливается на предельной
   клетке и защищается без расхода MP/item/выбранного действия;
   cell-target команда при этом не подсвечивает удалённую пустую клетку как
   выполнимую: её область ограничена MOVE + authored range;
4. подъём может завершиться удержанием; связь живёт только в battle snapshot;
5. удерживаемую цель нельзя атаковать, она пропускает ход без накопления;
6. носитель не перемещается и выбирает только `Бросить`, `Опустить` или
   `Удерживать и защищаться`;
7. первое подтверждение lift-цели проигрывает только presentation-подход и
   подъём; затем доступны `Бросить / Опустить / Удерживать и защищаться`;
   после завершения подъёма они появляются в кольце у носителя без отдельной
   нижней/боковой панели; Cancel из выбора клетки броска возвращает это кольцо;
   Cancel, включая середину подхода, возвращает исходный snapshot и presentation
   без телепорта, сохраняя заранее выбранное M;
8. гибель носителя детерминированно опускает цель на ближайшую допустимую клетку;
9. stale preview не может списать ресурс или применить результат;
10. AI и player route не расходятся;
11. 16×12 cell-target profile остаётся ниже 20 мс в среднем, а UI переиспользует
    один расчёт на refresh;
12. schema Action/Battlefield/save и owner resolver не меняются.

Удерживаемая цель исключена из обычных direct/cell/AOE/status effects. Носитель
получает эффекты штатно, они не переносятся на удерживаемого бойца, а гибель
носителя освобождает цель. Gate проверяет прямую, клеточную и площадную попытку.

Минимальные автоматические gates: `test_combat_grid.gd`,
`test_combat_prototype.gd`, `test_combat_lab.gd`, `test_combat_items.gd`,
`test_combat_personal_actions.gd`; затем весь combat suite и соседние
transition/party/save tests. Ручная приёмка — обычный Forward+ Combat Lab на
обоих размерах поля.

## ActionPlan regression gate (поверх v2.64.4)

- `test_combat_action_plan.gd`: strike/ranged/support/heal/item/lift/cell/spread/
  self/movement; путь заканчивается в stop; MOVE+range; явное M в исходной
  клетке; revival через occupant; stale context; один commit.
- `test_combat_lab.gd`: menu movement/cast/filtered targets; hover A-B-A и
  cell footprint без клика; недопустимая B не сохраняет executable preview;
  3D roots/input и 2D buttons сохраняют instance IDs; public preview не содержит
  скрытых результатов; полный и прерванный lift approach/cancel.
- `test_combat_vertical_animation.gd`: M не проигрывается повторно перед lift;
  cancel сохраняет staged M; throw, duo и defend presentation продолжают работать.
- Затем все `test_combat*.gd`, `test_battlefield*.gd`, `test_encounter*.gd`,
  `test_party*.gd`, `test_*save*.gd` последовательно (shared user:// fixtures).
- Обычный Forward+ render smoke обеих арен выполнен на RTX 5070, без editor/import.
  Ручной gate подтверждён пользователем: реальная мышь и геймпад, hover границы
  дальности, цвет fallback/invalid, M, lift cancel в пути и после подъёма, три
  финальных варианта, читаемость HUD и непрерывность анимации на 10×8/16×12.

Команда targeted test (из checkout; путь exe можно заменить локальным):

```powershell
& C:/Users/novos/Projects/ember-godot/tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_combat_action_plan.gd
```

## Production defeat/Retry gate

Поражение авторской встречи не является persistent result commit. Gate требует:

1. defeat-modal предлагает `Повторить` и `Загрузить сохранение`, а не возврат в
   мир с нулевыми HP или потраченной сумкой;
2. Retry восстанавливает точные предбоевые party, inventory, authored deployment
   и исходное состояние поля, но создаёт новый RNG seed;
3. Retry не меняет `EmberExploreState`, не пишет ручной слот/автосейв и не
   применяет XP, награды, flags или combat counters;
4. load-only панель показывает три ручных слота и отдельный автосейв по metadata
   существующего save v2 owner; пустые слоты недоступны;
5. успешная загрузка открывает сохранённую сцену и очищает process-local combat
   handoff; ошибка сохраняет defeat-modal и возможность Retry;
6. победа по-прежнему применяет результат ровно один раз; authored Action,
   Battlefield и save schemas не меняются.

Минимальный gate — `tools/test_combat_defeat_retry.gd`, затем
`test_combat_lab.gd`, `test_combat_encounter_transition.gd`,
`test_combat_result_bridge.gd`, `test_party_progression.gd`,
`test_party_save_v2.gd`, весь `tools/test_combat*.gd` и соседние encounter/
party/save scripts. Ручная Forward+ приёмка проверяет поражение после расхода MP
и предмета, Retry, новый seed, выбор ручного слота/автосейва, Esc-назад и focus
мышью/клавиатурой/геймпадом.
Текущий gate пройден: 27/27 связанных scripts, Vulkan Forward+ capture и ручной
mouse/gamepad сценарий подтверждены 8 сентября 2026.

## Pre-battle deployment gate

`EmberBattlefieldResource.party_deployment_cells` остаётся единственным authored
owner: первые N клеток задают начальную позицию N героев, а лишние клетки в том
же массиве включают расстановку и образуют разрешённую зону. Ровно N клеток
автоматически пропускают фазу, поэтому `colored_crossing_demo` остаётся
фиксированным первым боем. Для ручной демонстрации E4 расширяет только зону
`vertical_forge_10x8`, не меняя первые четыре позиции.

Gate требует:

1. сохранённая стратегия (только порядок hero IDs, без координат) применяется к
   первым N authored cells до UI; старый/отсутствующий/битый save v2 сохраняет
   прежний порядок, transition передаёт deep copy, direct Lab использует autoload;
2. ready-окно содержит ровно `НАЧАТЬ БОЙ` и `ИЗМЕНИТЬ СТРАТЕГИЮ`; поле и союзники
   видны полностью, а зона, hero tools, timeline, radial commands, AI, action
   commit и расход RNG скрыты/заблокированы;
3. Edit открывает детальный режим: mouse и стандартный grid cursor выбирают героя
   и свободную клетку; занятая героем клетка делает swap, а
   blocked/focus/enemy/out-of-zone отклоняются;
4. `Сбросить` возвращает persisted strategy, `Начать бой` доступно только для
   полного уникального placement и убирает phase-only UI/markers;
5. confirmed manual placement остаётся только в процессе боя и не меняет preset;
6. defeat Retry восстанавливает confirmed custom placement, party, inventory и
   поле с новым seed без повторного открытия расстановки; обычный Lab Reset
   возвращает persisted strategy и открывает ready снова; exact-N игнорирует
   preset и автоматически пропускает ready/edit.

Узкий gate — `tools/test_combat_prebattle_deployment.gd`; непосредственно
связанные `test_combat_lab.gd`, `test_combat_encounter_transition.gd`,
`test_combat_defeat_retry.gd`, `test_encounter_resource.gd`,
`test_battlefield_resource.gd` и дополнительный `test_combat_grid.gd` проходят.
Все 20 `test_combat*.gd`, `test_party_save_v2.gd`,
`test_inventory_equipment.gd`, `test_party_progression.gd` и
`test_battlefield_resource.gd` проходят. Обычные Vulkan Forward+ captures E4 и
inventory прошли без script/renderer errors и подтвердили полностью видимое поле,
ready с двумя actions и встроенный Strategy section. Ручная приёмка реальной
мышью/клавиатурой/геймпадом и menu save/reopen подтверждена пользователем.

## Active party 1–4 gate

### Voxel shapes + empty lifecycle, stage 2.1

`test_voxel_shapes.gd`: точные occupied bounds блока/цилиндра/сферы при 16/32,
диаметры 1/2/3/7/16/17/32, явные отказы height/budget без clamp, no-files preview,
creation Undo/Redo, non-16 world scale и transformed parent, empty Canvas
camera-ray→stroke→save_changes, empty→solid→empty с authored child под Shape,
Undo/Redo/save/reopen, shared linked empty lifecycle, failed destination rollback.
При пустой форме ни прежние voxels, ни коллизия не возвращаются сами.

9/9 headless scripts PASS: voxel_shapes, voxel_object_canvas,
surface_canvas_workflow, voxel_surface_sculpt, voxel_prefab_rebuild,
scene_edit_roundtrip, object_inspector_actions, object_inspector_model,
object_inspector_panel. После empty-aware Inspector изменения повторены shapes,
object_inspector_model и object_inspector_panel: PASS.
Plugin parse и diff-check прошли. Замер generator+prepare: доска 32×2×8 —
8.25 мс; 64×32×64 (131 072 cells) — 594.92 мс. Старый кандидат лимита
128×64×128 занял 4725 мс: лимит окна создания снижен, schema не менялась.

Actual EditorPlugin fixture `tools/editor_test_voxel_shapes.gd` включается только
в disposable ember-canvas-smoke-* project. Fresh import прошёл без ERROR;
Forward+ fixture проверил создание через native dialog, force rebuild нового
пустого native ID, настоящий Canvas mouse/ray first-voxel Save, editor scene Save,
Undo/Redo/reopen и создание доски 16×2×32. Functional assertions PASS. Capture
диалога берётся из его собственного Window viewport. Ошибку бесконечного роста
dialog minimum-size устранили фиксированной высотой preview и scrollable body;
Create/Cancel остаются вне scroll. Автоматический выход иногда по-прежнему даёт
absolute get_node ERROR/scan-aborted после functional PASS — старый editor teardown
долг отмечается отдельно, весь lifecycle не объявляется чистым.

Ручной gate: открыть 3D-сцену → «Проект / Инструменты / Ember: Новая voxel-форма…».
Блок 16×2×32 → «Обновить предпросмотр» → «Создать и открыть Canvas»; проверить
размер/цвет, Undo создания и Redo, затем Ctrl+S сцены. Повторить пустую область:
в Canvas инструмент «Объём», операция «Добавить», клик по нижней плоскости;
Save создаёт геометрию/коллизию. Стереть всё и Save — коллизии нет, Node остаётся
в дереве сцены; Undo/Redo и save/reopen возвращают ожидаемое состояние.
«Отмена» диалога не создаёт source/prefab/scene node. Конверсия 2.2 и точная
расстановка 2.3 описаны отдельными gates выше.

### Voxel object → Canvas → scene, stage 1

`test_voxel_object_canvas.gd` использует unique user:// sources/prefabs/scene:
detached open/discard без файлов, selected-only Save, stable повторный ID/UID,
отдельные mesh/shape, GEN_EDIT_STATE_INSTANCE pack/reopen с nested authored child,
world pose, Undo/Redo с прежними faces, shared edit двух связанных объектов,
CACHE_REUSE нового source/prefab, independent copy и guard Cancel/Discard/Save.
Отказы: удалённый target, изменённый source, недоступная папка и
water-fill правка; исходные файлы/узлы при этом не применяются частично.
Начиная с 2.1 пустая native-модель поддержана, а не является validation отказом.
Native BarrelA проходит preflight, CargoA безопасно отказывается из-за несовпадения
legacy baked geometry. `-- --capture` обычным Forward+ сохраняет object-canvas.png
в fixture папку и печатает абсолютный путь.

13/13 headless gates прошли 9 сентября 2026 без SCRIPT ERROR/ERROR:
voxel_object_canvas, surface_canvas_workflow, voxel_surface_sculpt,
voxel_selection, voxel_selection_mask, voxel_groups, voxel_palette,
voxel_prefab_rebuild, scene_edit_roundtrip, object_inspector_panel,
object_inspector_model, object_inspector_actions, voxel_migration_queue.
Plugin parse-check прошёл. После финального исправления cache/guard повторены
object_canvas и surface_canvas_workflow. Старый migration_queue test пересобрал
четыре generated node UID кровати; эти побочные изменения возвращены точечным patch.
Обычный Forward+ object_canvas --capture на RTX 5070 прошёл: просмотрены Canvas,
геометрия, палитра и scope выбранного экземпляра. Отдельная disposable editor-копия
с открытием test_pier прошла import/plugin activation/layout smoke без ERROR,
exit 0. Для прежних legacy-систем её ember/pack_path указывал на существующий
архив абсолютным путём только в temp project.godot; live project не менялся.

После дефектов ручной приёмки добавлен opt-in EditorPlugin fixture
`tools/editor_test_voxel_object_canvas.gd` (включать только в disposable
ember-canvas-smoke project). Реальный Engine.is_editor_hint=true: Canvas Save,
EditorUndoRedoManager Undo/Redo, scene save/reopen и bounds 1500→1000→1200→1500
при высоте рабочей области 650 прошли без ERROR. `-- --capture` открывает реальный
main-screen Canvas редактора и сохраняет PNG с печатью размера центральной области.
Headless runtime отдельно проверяет непустые уникальные placement_id всех пяти
voxel props Причала. Проверка логов обязательна: exit 0 сам по себе недостаточен.
После исправлений повторены 6/6: voxel_object_canvas, surface_canvas_workflow,
voxel_prefab_rebuild, scene_edit_roundtrip, object_inspector_actions, test_test_pier;
все PASS без ERROR, plugin check-only и git diff --check также прошли.
После уточнения root source signature повторены object_canvas,
surface_canvas_workflow, scene_edit_roundtrip и object_inspector_actions: PASS.
Forward+ в настоящем editor: проверен кадр центральной области 1084×741 внутри
окна 1800×900 — Save, sidebar и Inspector видимы, placement заполнен, prefab
«актуален». Это функциональная/визуальная проверка, не чистый полный lifecycle:
при автоматическом выходе fixture оставался ERROR absolute get_node и scan-aborted.
В старой многократно изменённой smoke-копии также встречался intermittent
get_dependencies. Adjacent stage теперь имеет нераспознаваемый `.tmp` suffix
(точка в имени на Windows не означает hidden attribute), сериализация user://
сохранена для асинхронных editor readers. Новый disposable import прошёл чисто;
повторный actual run проверил Save/Undo/Redo/signature, но полный capture/выход
не завершился; после принудительного предыдущего выхода был DLL-copy diagnostic.
Полный чистый fresh editor lifecycle остаётся открытым, а не считается PASS.

Если остался черновик после прежнего failed Save, сначала попробовать Save после
hotreload кода, не закрывая Canvas. После успешного Save модели проверить
Placement ID: у уже открытого BarrelA с пустым ID вручную поставить
`pier_barrel_a` в Inspector, затем Ctrl+S сцены. Изменение файла не гарантирует
обновление уже открытой dirty-сцены. После этого безопасно перезапускать редактор
ради новой раскладки. Hotreload
существующего placeholder не считается гарантированным; при повторной ошибке
черновик не отбрасывать и не перезапускать редактор до отдельного восстановления.

Ручной gate открыт: в test_pier выбрать Map/Props/BarrelA → «Создать экземпляр» →
исходную бочку → «Редактировать в Canvas», изменить воксель, сохранить → 3D:
изменилась только выбранная, collider следует новой форме. Повторный Save в этом
сеансе не создаёт ещё source; Ctrl+Z/Redo в 3D возвращают форму/ссылки. Сохранить
сцену обычным Ctrl+S, закрыть/открыть: форма и authored children остаются.
Для linked-пары проверить shared-команду (закрыть остальные вкладки сцен), затем
independent copy; изменения исходника не должны затрагивать независимую копию.
Проверить «Остаться», «Отбросить», «Сохранить» при смене объекта и выходе из Canvas.
Новая editing session создаёт новый fork по умолчанию; cross-tab shared update,
water fill и несовпадающий legacy prop пока не поддержаны. Полностью пустая native
модель поддержана последующим этапом 2.1, см. gate выше.

### Test Pier — отдельный exploration gate

`tools/test_test_pier.gd` загружает `scenes/test_pier.tscn` как F6, проверяет
активную пару protagonist/mira, одного follower, Tab, два героя сумки и Q/E,
authored content без legacy hydration, физический пол, ray/capsule к западной
границе воды. Реальный pause-menu load после перемещения A→B возвращает A через
reload сцены; следующий F6-equivalent старт сохраняет пару и A. Сохранение
содержит mapId=test_pier. SHA256 исходных v1/v2 папок остаются неизменны;
тест пишет в unique `user://ember-tests/test-pier-*`.
Обычный Forward+ `-- --capture` сохраняет `pier.png` и `pier-inventory.png`
в fixture папке, печатает абсолютные пути и завершает процесс.
Targeted и Forward+ пройдены 9 сентября 2026. Связанные party_followers,
party_save_v2, progress_restore, map_transition, inventory_equipment,
explore_pause_menu, camera_relative_movement — 7/7 PASS; pack contract и
`git diff --check` пройдены. Ручной gate: F6 именно
test_pier.tscn → пройти настил/берег, обойти грузы и все края (нет падения в воду),
Tab и I/Q/E дают только двух героев, T меняет следование, RMB вращает камеру;
Esc → сохранить, отойти, загрузить, закрыть и снова F6 → прежнее место/пара.
Автоматический edge probe не заменяет ручной обход всех границ.
Regression первого editor-open: `test_voxel_surface_sculpt.gd` запускает отдельный
`--native-selector-probe` и отвергает любой ERROR в его output даже при exit 0.
Реальная test_pier привязывается к selector через обычный refresh_context:
без Surface toolbar скрыт; повторный выбор Map не читает legacy JSON; временные
неизвестные размеры безопасны; native Surface даёт размеры; legacy fan_town
сохраняет прежний полный grid с heights. Sculpt, world_surface_projection и
test_test_pier повторно проходят после исправления. Ручной повтор: закрыть/открыть
test_pier, выбрать Map, F6; новых ошибок `cannot read ... test_pier.json` быть не должно.
Бой/Retry active-party gate ниже этим не закрывается.

Контракт 9 сентября 2026 сохраняет единственные Explore/Party/save owners.
`test_party_save_v2.gd` проверяет 1–4, strict setter, missing/corrupt
`activeHeroIds` → legacy четыре, reopen/adopt с синхронным UI listener и metadata.
`test_party_followers.gd` проверяет solo Mira, пару без ГГ, изменение состава при
прежнем лидере, уход лидера и Tab без смещения игрока.
`test_inventory_equipment.gd` проверяет запрет inactive equip/use/unequip,
циклический выбор пары, roster reorder при открытой сумке и сохранение полного
порядка стратегии. `test_encounter_resource.gd` покрывает compatible subsets и
отказ unsupported/capacity; `test_combat_encounter_transition.gd` — отказ до
смены сцены без мутаций, pending/active lock, snapshot isolation и solo/pair
victory. `test_party_progression.gd` и `test_combat_result_bridge.gd` проверяют
XP только участников, павших, preview=commit и неизменность отсутствующих.
`test_combat_prebattle_deployment.gd` сохраняет exact-four baseline и проверяет
пару в четырёх cells; `test_combat_defeat_retry.gd` добавляет pair Retry с точным
составом, placement, HP/MP/inventory и новым seed без мутаций мира.

9 сентября 2026 прошли 34/34 scripts (exit 0, без SCRIPT ERROR/ERROR/FAIL):
20 combat, 2 battlefield, encounter, inventory, 3 party, а также
health_consumables, progress_restore, explore_pause_menu, map_transition,
defeat_respawn, talk_shop и camera_relative_movement. Запуск последовательный
из-за shared user://. `python tools/test_vox_axes.py` и `git diff --check` прошли.
Обычные Forward+ followers и defeat/retry на RTX 5070 завершились с exit 0;
просмотрены четыре PNG: пара в мире, сумке, ready и после Retry.
Ручной Forward+ gate остаётся открытым:
одиночка и пара в мире, followers, Tab/Q/E и сумка, расстановка/победа/Retry,
save/reopen и возврат лидера. Для безопасных captures tests
`test_party_followers.gd` и `test_combat_defeat_retry.gd` поддерживают
`-- --capture-active` (обычный Forward+, fixture saves, PNG в unique
`user://ember-tests`). Captures не заменяют ручную input-приёмку.

## Migration gates

### G1/G2 — content ownership

- `tools/test_content_migration_report.gd` и
  `test_content_migration_dashboard.gd` остаются read-only;
- `test_migration_workflow_layout.gd` проверяет bounded editor layout;
- `test_voxel_migration_queue.gd` проверяет bounded candidate selection;
- `test_voxel_migration_batch.gd` проверяет mutation/Undo/Redo;
- sandbox parity/batch: `test_voxel_sandbox_migration_parity.gd`,
  `test_voxel_sandbox_native_batch.gd`;
- `fan_town` parity/batch: `test_voxel_fan_town_ready_migration_parity.gd`,
  `test_voxel_fan_town_ready_native_batch.gd`.

Любой новый batch требует точного списка, strict read-only parity, visual review
реальных изменений, ограниченной записи и подтверждения, что frozen JOI source
остался byte-identical. Ready/stale/missing prefab не равны ownership.

### G3 — physical Surface

`test_world_surface_projection.gd`, `test_fan_town_surface_profile.gd` и
`test_fan_town_surface_projection.gd` подтверждают visual/collision/height/route
из одной Surface. Dense storage меняется только после нового измеренного профиля.

### G4/G5 — выход из JOI

Новые runtime-вызовы `EmberPack` запрещены. Существующие fallback удаляются
вертикально после native parity затронутого домена. Финальный gate запускает
проект с физически недоступным sibling `joi-conductor` и проверяет основные
карты, interaction/content catalogs, save/reopen и бой. Полные критерии — в
`docs/EMBER_JOI_EXIT_PLAN.md`.

## Полный checkpoint gate

Перед самостоятельным Git checkpoint:

1. `git diff --check`;
2. `python tools/test_vox_axes.py`;
3. каждый `tools/test_*.gd` отдельным headless-процессом;
4. повтор targeted suites после любого исправления, найденного полным прогоном;
5. обычный Forward+ на изменённых сценах;
6. ручная приёмка пользователя, если она входит в Task Contract;
7. обновлённые GDD/handoff/`EMBER_NOW.md` без журнала промежуточных версий.

Если обязательный gate недоступен, результат помечается `degraded`: указывается
точная причина, что уже доказано и какое ручное действие осталось. Ошибка в
неизменённой подсистеме не скрывается, но отделяется от regressions текущего
среза доказательством baseline.
