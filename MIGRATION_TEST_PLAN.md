# Тестовая миграция Ember: Three → Godot 4

## V2.64.2 · free-yaw camera and hostile action auto-approach

1. Запустить E4 или E5. Зажать RMB и двигать мышь влево/вправо: камера плавно
   вращается без ортогональных скачков, а вертикальный наклон остаётся
   зафиксирован. В меню камеры отдельно проверить блокировку каждой оси и
   необязательный toggle ортогональных сторон. `F` возвращает фокус к текущей
   или уже намеченной позиции героя.
2. Выбрать `Удар` и далёкого противника. Цель доступна, даже если сейчас вне
   радиуса. Поле показывает маршрут, реальную позицию удара и маркер
   `АТАКА · СТОП`. Подтверждение одной команды плавно перемещает героя и затем
   выполняет удар, если позиция достижима за MOVE.
3. Выбрать противника дальше полного MOVE. Поле заранее показывает конечную
   клетку `ЗАЩИТА · СТОП`; после подтверждения герой проходит максимум по
   подходящему маршруту и получает `Защиту`. Цель не получает урон, MP/предмет
   выбранной атаки не тратится.
4. Повторить дальней атакой через поле с перепадом высоты и препятствием.
   Конечная позиция должна учитывать authored range, высоту, Jump и LOS, а не
   просто вести героя вплотную к цели.
5. Проверить непозиционные запреты: при нехватке MP, неверном состоянии цели или
   отсутствии обязательного партнёра команда остаётся недоступной и не
   маскируется автоподходом. До commit по-прежнему не видны попадание, крит и
   будущий урон.

Automated gates: все 17 `tools/test_combat*.gd`, отдельно
`test_combat_grid.gd`, `test_combat_lab.gd`, `test_combat_vertical_view.gd` и
`test_combat_vertical_profile.gd`; соседние `test_battlefield_resource.gd`,
`test_encounter_resource.gd`, `test_party_progression.gd` и
`test_party_save_v2.gd`. Измеренный E5 16×12 approach query: 4.73 ms.
Forward+ gate: `combat_vertical_stage3_auto_approach.png`.

## V2.64.1 · staged combat command selection

1. В E4 навести мышь или перевести клавиатурный/геймпадный фокус на доступное
   действие в кольце либо списке `Умения / Магия / Предметы`. Строка остаётся
   открытой, нижняя карточка показывает описание и условия, а поле — дальность
   и допустимые цели. Команда ещё не выбрана, цель не фиксируется, MP/предмет и
   состояние боя не меняются.
2. Подтвердить строку. Только теперь список скрывается и начинается отдельный
   выбор цели; карточка явно пишет `КОМАНДА ПОДТВЕРЖДЕНА`. Наведение по полю
   уточняет цель, но по-прежнему не раскрывает попадание, крит и будущий урон.
3. До выбора цели нажать `Esc/B`. Targeting полностью очищается, список
   открывается на прежней категории, а фокус возвращается к той же строке.
   Безопасный preview её дальности снова виден, но команда не остаётся
   вооружённой. Второй `Esc/B` возвращает к основному кольцу.
4. Повторить с предметом, клеточным заклинанием и `Подъёмом и броском` после
   выбора поднимаемой цели. Отмена всегда снимает всю незавершённую команду и
   возвращает в исходный список; staged-перемещение героя при этом сохраняется
   как отдельное решение хода.
5. В 2D diagnostic/E1 списке действует тот же порядок: focus только помечает
   допустимые цели, подтверждение разрешает их выбор, отмена возвращает фокус в
   список. Self-команда `Защита` по-прежнему выполняется сразу после
   подтверждения, потому что отдельной цели у неё нет.

Automated gate: `test_combat_lab.gd` закрепляет раздельные browse/targeting
состояния, безопасную проекцию дальности, очистку выбранной цели и двухуровневый
`ui_cancel`; все `tools/test_combat*.gd` остаются зелёными. Forward+ gate:
`combat_vertical_stage3_command_browse.png` и
`combat_vertical_stage3_command_target.png`.

## V2.64 · complete personal hero actions

1. Запустить Combat Lab и выбрать E4. Через лабораторную консоль по очереди
   передать ход `turn protagonist`, `turn mira`, `turn orik`, `turn sena`.
   У каждого героя в `Умениях/Магии` видны три личных направления из GDD;
   Земля и `Раздувка` остаются лабораторными кандидатами, а у Сены больше нет
   чужого огненного `Уголька`.
2. Искателем выбрать `Кузнечный скачок`: доступна пустая клетка на уступе с
   перепадом до четырёх уровней. Сначала наметить обычное перемещение, затем
   скачок — герой плавно заканчивает на второй выбранной клетке, а preview не
   меняет состояние заранее. `Накал` показывает над героем статус; следующие
   два атакующих действия сильнее, но входящий урон по нему также выше.
3. Командой `add hp orik -8` ранить Орика, передать ход Мире и применить
   `Глубокую перевязь`. Она лечит 12 HP, но не выше максимума, тратит 10 MP и
   завершает ход. Полностью здоровый союзник не выбирается.
4. Ориком поставить `Ледяной заслон` на пустую клетку. Она получает Frozen,
   становится преградой для движения и LOS до конца боя; исходный Battlefield
   Resource не меняется.
5. Сеной подойти в дальность шесть от янтарного узла и выбрать `Дальний
   контакт`. До клика узел подсвечен допустимой целью; после commit он зеленеет
   и подписывается активным, повторно выбрать его нельзя. `Перегрузка` показывает
   стоимость 10 MP и задержку, но до commit не раскрывает попадание, крит или
   урон.
6. Оценить игровые числа: скачок 5 MP, Накал 6 MP и +2/25%, лечение 12 HP за
   10 MP, заслон 7 MP, контакт 5 MP, Перегрузка 10 MP. Это обратимые Resource-
   параметры; менять schema для баланса не требуется.

Automated gates: `test_combat_personal_actions.gd`,
`test_combat_effect_library.gd`, `test_combat_action_resource.gd`,
`test_combat_grid.gd`, `test_combat_prototype.gd`, `test_combat_lab.gd`,
`test_combat_vertical_animation.gd` и связанные unit/party/save gates.
Forward+ gate: `combat_vertical_stage3_personal_actions.png`.

## V2.62.1 · positional pair techniques

1. В E4 передать ход Сене, наложить Wet на доступного врага и открыть `Умения`.
   `Грозовая связка` показывает цену `8+6 MP`, партнёра Миру, дистанцию и условие
   Wet, но не показывает попадание, крит или будущий урон. При наведении поле
   выделяет радиус 3, а Миру — зелёным контуром, указателем и подписью.
2. Выбрать мокрого врага. Перед атакой Сена и Мира одновременно дают короткий
   визуальный импульс. После commit у Сены снято 8 MP, у Миры 6 MP, обе
   отодвинуты в очереди; цепь задевает только мокрых врагов одной проводящей
   области.
3. Передать ход протагонисту и подготовить Frozen-цель. `Паровой пробой` с
   Ориком снимает Frozen, наносит усиленный удар и применяет force 3, включая
   штатное падение при подходящем рельефе. Оба участника тратят MP и получают
   задержку.
4. Отвести партнёра за три клетки. Строка остаётся видимой, но пишет точную
   дистанцию и `вне радиуса`; контур, указатель и подпись партнёра становятся
   красными. Выбрать перемещение инициатора обратно в радиус: техника должна
   стать доступной в том же ходу, ещё до commit движения.
5. Уменьшить MP партнёра ниже 6 либо вывести его из боя. Техника остаётся видна,
   но недоступна с точной причиной (`нужно 6 MP` / `выведен из боя`). Без Wet
   или Frozen подходящей цели нет. Повтор старого commit не списывает ресурсы
   второй раз.
6. Текущие радиус 3, `8+6 MP`, power и delay — баланс-кандидаты. При проверке оценить,
   ощущается ли совместный приём достаточно ценным для расхода ресурсов и
   задержки двух героев; это можно изменить в Resources без смены schema.

Automated gates: `test_combat_action_resource.gd`, `test_combat_prototype.gd`,
`test_combat_lab.gd`, `test_combat_vertical_animation.gd` и связанные
unit/encounter/party/save gates. `combat_vertical_stage3_pairs.png` и
`combat_vertical_stage3_pairs_far.png` проверяют оба состояния в Forward+.

## V2.61 · equal XP and level-up

1. Запустить авторскую `colored_crossing_demo`, ранить героя, потратить часть MP
   и оставить Орика с 0 HP. До победы persistent party и save не меняются.
2. Завершить бой. Окно показывает `+35 XP каждому герою` и повышение всех
   четверых до уровня 2. Оно не раскрывает и не меняет скрытые боевые броски.
3. Нажать `Продолжить` один раз (быстрый двойной Enter даёт тот же результат).
   Все четверо имеют уровень 2 и 5 XP; живой раненый сохраняет прежний дефицит
   HP/MP, Орик возвращается с 1 HP. Награда и опыт не дублируются.
4. Сохранить в ручной слот и переоткрыть его. Уровни, XP, текущие HP/MP и
   экипировка совпадают; в JSON не появляются max/stat/progression-preview поля.
5. Повторить встречу и выбрать поражение/возврат. XP не выдаётся, павшие не
   поднимаются этим путём. Кривая 30, 45, 60… пока является тестом темпа и может
   быть изменена до производства контента без смены save v2.

Automated gates: `test_party_progression.gd`, `test_combat_result_bridge.gd`,
`test_combat_encounter_transition.gd`, `test_party_save_v2.gd` и все связанные
combat gates. `combat_vertical_stage3_progression.png` проверяет окно победы в
Forward+ на RTX 5070.

## V2.60.2 · no mouse-wheel zoom in combat

1. В E4/E5 навести курсор на поле и прокрутить колесо в обе стороны: масштаб
   боя не меняется. ПКМ, СКМ, плавный фокус `F` и слежение после перемещения
   продолжают работать.
2. Выбрать боевой `CameraRig` в Inspector и изменить `orthographic_size`:
   стартовый/preview масштаб меняется. Пределы и шаг остаются authoring-
   параметрами; запрет касается только wheel input во время боя.
3. Открыть Surface Canvas: его прежний editor-only zoom колесом не изменился.

Automated gates: `test_combat_lab.gd` и `test_combat_camera_rig_preview.gd`.

## V2.60.1 · adaptive command drawer

1. В E4 открыть `Умения`, `Магию` и `Предметы`. Основное кольцо не исчезает и
   не превращается во второе: выбранная категория подсвечена, а рядом появляется
   обычная прокручиваемая панель.
2. Поставить героя ближе к левому и правому краю экрана либо повернуть/сдвинуть
   камеру. Панель выбирает свободную сторону кольца, остаётся внутри viewport и
   не закрывает самого героя. Около центра она не должна быстро прыгать между
   сторонами при небольшом движении камеры.
3. Проверить длинные списки: строка показывает shortcut, иконку, имя, MP либо
   остаток предмета. Недоступное действие остаётся видимым и подписывает причину
   (`не хватает MP` или `нет подходящей цели`); список прокручивается без
   горизонтального скролла.
4. Мышью навести строку, затем повторить клавиатурой/геймпадом. Нижняя карточка
   показывает прежние эффект и условия. Если все строки недоступны, focus
   переходит на `Назад · Esc`, а не пропадает.
5. `Esc/B` и кнопка `Назад` закрывают только панель и возвращают фокус к кольцу.
   Выбор доступной команды скрывает панель и переводит бой в прежний выбор цели;
   скрытый шанс, крит и будущий урон не раскрываются.

Automated gate: `test_combat_lab.gd` проверяет отсутствие второго кольца,
содержимое трёх категорий, focus fallback, закрытие и размещение по обе стороны.
Все 15 combat gates проходят; `combat_vertical_stage3_items.png` подтверждает
композицию в Forward+ на RTX 5070.

## V2.60 · combat items from the shared bag

1. Запустить Combat Lab, выбрать E4 и ранить активного героя. В круге открыть
   `Предметы`: у травы, чая и искры видны иконки и остаток; нижняя карточка
   объясняет восстановление, дальность и допустимую цель.
2. Выбрать лечебную траву. До выбора допустимого раненого союзника число в
   сумке не меняется. После клика цель получает 4 HP, стек уменьшается ровно на
   один, ход завершается. Повтор старой команды не лечит и не списывает снова.
3. Проверить чай на герое с недостающими HP и MP: оба ресурса восстанавливаются
   одним полным действием. Полностью здоровая по нужным ресурсам живая цель не
   должна быть доступна, поэтому припас нельзя случайно потратить впустую.
4. Через консоль лаборатории сделать союзника павшим и подойти в authored
   дальность. Только `Искра возвращения` позволяет выбрать его и возвращает с
   1 HP; обычное лечение не нацеливается на павшего, а искра — на живого.
5. Потратить предмет и нажать `Повторить`: предбоевой запас восстанавливается.
   В authored-встрече победить и вернуться в мир: общая сумка получает точный
   остаток один раз, затем обычный лут добавляется прежней reward-chain.
6. Сохранить и переоткрыть игру после боя. Сумка хранится прежним save v2 owner;
   временные item commands/definitions в JSON не появляются.

Automated gates: все 15 `tools/test_combat*.gd`, `test_party_save_v2.gd`,
`test_item_resource.gd`, `test_inventory_equipment.gd` и
`test_health_consumables.gd`. `test_combat_items.gd` отдельно проверяет полный
ход, HP+MP, воскрешение, полезную цель, точное списание и stale-commit guard.
Forward+ capture `combat_vertical_stage3_items.png` проверяет настоящую страницу
предметов на RTX 5070 без изменения renderer или сцены поля.

## V2.59.2 · staged camera follow + V2.59.1 combat HUD rules

1. Запустить `Проект → Инструменты → Ember: Run Combat Lab`, выбрать E4 10×8.
   Вокруг активного героя нет закрывающей его карточки. Основной круг содержит
   движение, обычный удар, `Умения`, `Магию` и защиту; категории открывают второй
   круг, `Esc/Назад` возвращает на первый.
2. Навести мышь или перевести focus на категорию/приём. Нижняя карточка показывает
   назначение, MP, дальность, эффект и условия. У выбранного враждебного действия
   до клика нигде не видны шанс/бросок попадания, будущий промах, крит или урон.
   Поле также не показывает зависящее от скрытого броска будущее замерзание,
   реакцию или отбрасывание. Увести и вернуть курсор: скрытый resolver-результат
   не перебрасывается.
3. Навести на врага без выбора действия. Справа сверху видны имя, уровень, HP,
   описание, тип, размер, четыре стихийных сопротивления, устойчивость к Wet /
   Frozen / Burning, стойкость к толчку и активные статусы. При уходе с врага
   карточка скрывается.
4. Проверить Болотного огонька: тип `Дух`, Frozen/Burning сокращаются на один ход.
   Проверить Стража: тип `Конструкт`, крупный размер, стойкость 1 блокирует Порыв
   силой 1, но паровой импульс силой 2 способен оттолкнуть при свободном пути.
   Один и тот же статус/толчок не меняет результат без изменения состояния.
5. Кликнуть цель. Только теперь анимация и журнал открывают попадание, крит и
   фактический урон. При промахе ход и MP расходуются, но урон, статус, толчок и
   изменение клетки не происходят. Повторный сигнал старой команды не применяет
   её второй раз.
6. Несколько раз использовать платную магию и умения: действие с ценой выше
   текущего MP становится недоступно. Удар, движение и Защита MP не требуют.
   Retry восстанавливает предбоевые HP/MP и получает новый seed; возврат в мир
   сохраняет фактический остаток MP через прежний save v2 owner.
7. Выбрать перемещение, но ещё не выполнять действие. Камера плавно следует за
   героем к выбранной клетке. Увести камеру и нажать `F`: фокус возвращается на
   новую видимую позицию, при этом state snapshot всё ещё хранит исходную клетку.
   Отмена перемещения плавно возвращает фокус; действие подтверждает путь один раз.

Automated gates: все `tools/test_combat*.gd`, `test_battlefield_resource.gd`,
`test_encounter_resource.gd`, `test_party_save_v2.gd`. Resolver-gate отдельно
фиксирует внутренний reroll guard, скрытый player-facing intent, MP один раз,
отказ stale commit, промах без побочных эффектов, DEF и детерминированные
устойчивости. `capture_combat_vertical.gd` пишет Forward+ кадр
`combat_vertical_stage3_rules.png` только в `user://`.

## V2.58.3 · permanent party, live leader + save v2 performance gate

1. Новый старт создаёт постоянную группу `Искатель / Мира / Орик / Сена`.
   Открыть I: мышью либо Q/E переключить всех четырёх, проверить золотую отметку
   активного героя, level, XP,
   текущие/максимальные HP/MP и пять слотов. Надеть предмет на спутника, закрыть
   и снова открыть сумку: предмет остаётся у выбранного героя, а в мире модель,
   имя и HP controller соответствуют этому выбору.
2. Esc открывает три ручных слота и отдельную строку автосейва. Каждый слот
   показывает локацию, время прохождения, живых героев и локальную дату. Сохранить
   в слот 2, получить урон/изменить экипировку, загрузить слот 2 и проверить
   возврат состояния. Обычные награды/флаги пишут автосейв, не затирая ручной.
3. На копии существующего v1 без v2 загрузить старый слот. До миграции появляется
   byte-for-byte backup, старый JSON остаётся нетронут. Старые HP переходят
   протагонисту пропорционально новой шкале; совместимая экипировка остаётся,
   несовместимая возвращается в сумку. Повторная загрузка читает v2 и не мигрирует
   изменённый v1 ещё раз.
4. Из мира запустить `colored_crossing_demo`: бой получает текущие HP/MP всех
   четырёх как глубокую копию. `Повторить` восстанавливает предбоевой снимок.
   После Continue изменённые HP/MP, флаг, счётчики и награда возвращаются ровно
   один раз даже при повторном сигнале кнопки.
5. В исследовании видны Мира, Орик и Сена с актуальными HP. `T` либо HUD toggle
   переключает мягкую живую формацию и точный «паровозик» по фактически
   пройденному пути. На поворотах и у препятствий спутники не режут маршрут,
   а возвращаются в безопасный след; единственным controller остаётся лидер.
   Закрыть меню и нажимать `Tab`: выбранный герой становится управляемой моделью,
   прежний лидер возвращается в строй, камера/позиция не прыгают. `Q/E` в мире
   не меняют героя и сохраняют своё назначение для журнала/других экранов.
6. У каждого ручного слота и автосейва есть `Удалить`. Первое нажатие требует
   подтверждения, второе за пять секунд очищает загрузку и оставляет byte-exact
   recovery-копию в `deleted_saves`. Миграционный backup v1 не удаляется.
7. Быстро переключить строй 20–40 раз. Не должно быть микрофриза, повторной
   проверки всех дверей/квестовых объектов или записи save; gate проверяет этот
   presentation-only путь отдельно от `progress_changed`.
8. Performance regression: 40 последовательных смен лидера должны укладываться
   в 100 мс, а 40 полных обновлений вкладки инвентаря — в 300 мс на текущем
   локальном gate. Текущий результат около 10.2/191 мс против прежних 6574 мс
   только на смену лидера. Проверка одновременно сверяет имена, HP, экипировку и
   возврат прежней модели в строй, поэтому ускорение не подменяет данные.

Automated gates: `test_party_followers.gd`, `test_party_save_v2.gd`, `test_explore_pause_menu.gd`,
`test_inventory_equipment.gd`, `test_health_consumables.gd`,
`test_progress_restore.gd`, `test_shop_persistence.gd`,
`test_combat_encounter_transition.gd` и все v2.57 combat gates.
Forward+ captures: `tools/capture_party_followers.gd` и
`tools/capture_party_save_v2.gd` сохраняют обе формы строя,
`party_save_v2_slots.png` и `party_save_v2_inventory.png` только в `user://`.

## V2.57.2 · lift selection + status readability + independent camera axes

1. В E4 выбрать `Подъём и бросок`, затем кликнуть по допустимому бойцу. Он
   плавно перемещается над головой активного героя сразу после выбора цели;
   gameplay-клетка ещё не меняется. Клик по янтарной клетке запускает только
   бросок по дуге и применяет внутренне зафиксированный результат.
2. Наложить на врагов `Мокрый`, `Заморозка` или `Горение`, а на героя —
   `Защита`. Над моделью видны цветная форма-иконка, русское имя и число ходов;
   `▼` отличает debuff, `▲` — buff.
3. В `Камера` оставить `Поворот по сторонам · плавно`: переход к следующей
   ортогональной стороне не должен быть мгновенным. Отдельно включить
   горизонтальную блокировку — RMB меняет только наклон; затем вертикальную —
   RMB меняет только горизонтальный поворот. Одновременное включение фиксирует
   весь угол, не запрещая pan/zoom.
4. Увести обзор средней кнопкой и нажать `F`, когда курсор находится над полем,
   кнопкой или пустым местом HUD. Во всех случаях камера плавно возвращается к
   активному бойцу.

Automated gates: `test_combat_vertical_view.gd` проверяет плавную остановку на
90°, обе независимые блокировки и глобальный `F`; `test_combat_vertical_animation.gd`
проверяет ранний projection-only lift, точный throw commit и status badges.
`capture_combat_vertical.gd` сохраняет отдельный Forward+ кадр
`combat_vertical_stage1_feedback.png` с поднятой целью и эффектами.

## V2.57.1 · camera comfort + lightweight combat animation gate

1. Запустить E4 и E5 либо нажать `Сбросить`: камера начинает с общего плана, а
   не с крайнего первого героя. После хода переход к следующему активному бойцу
   занимает короткое плавное движение; F также мягко возвращает фокус.
2. Открыть `Камера`: `Весь план` заменяет обязательную кнопку Home,
   `Инверсия по вертикали` меняет направление pitch, `Фиксация по осям` оставляет
   четыре согласованных направления, `Полная фиксация угла` запрещает вращение,
   сохраняя pan/zoom. Q/E не перехватываются камерой.
3. На E5 опустить pitch до минимального значения и обойти поле вокруг. Камера
   остаётся за всей диагональю арены; ближние клетки не пересекают камеру и не
   исчезают треугольными фрагментами.
4. Выбрать staged-клетку: герой плавно переходит к ней. После commit AI двигается
   по своему рассчитанному пути. `Подъём и бросок` сначала поднимает цель над
   головой бойца, затем проводит её по дуге к точной preview-клетке.
5. Обычная атака получает короткий выпад, повреждение — squash/pulse, защита —
   отдельный pulse. Во время анимации canonical snapshot и уже применённый combat
   result не меняются; новый input безопасно заменяет устаревшую visual-анимацию.

Automated gates: `test_combat_vertical_view.gd`,
`test_combat_vertical_animation.gd`, `test_combat_lab.gd` и все прежние
resolver/grid/AI/Resource/arena/transition gates. `capture_combat_vertical.gd`
сохраняет обычный и минимально наклонённый Forward+ кадр только в `user://`.

## V2.57 · vertical Combat Lab 10×8/16×12 gate

1. Запустить `Проект → Инструменты → Ember: Run Combat Lab` и выбрать
   `E4 · Вертикаль 10×8`. Нажать M: доступные клетки должны учитывать Jump и
   высоту, а спуск с перепадом применяет детерминированный урон после хода.
2. Проверить дальнюю атаку через перепад и преграду: допустимость одновременно
   учитывает горизонтальную и вертикальную дальность и LOS. Внутренний preview
   не меняет snapshot, а commit применяет ровно зафиксированный результат.
3. Выбрать `Подъём и бросок`: первый выбор фиксирует допустимого лёгкого бойца,
   второй — янтарную свободную клетку приземления. Бросок союзника разрешён,
   слишком тяжёлого врага — нет; высота приземления добавляет детерминированный
   урон от падения, который открывается после выполнения.
4. Проверить общий framing, полупрозрачную преграду с прежней collision и
   видимый контур героя. Исторические Q/E и обязательный Home из первой версии
   этого gate заменены актуальным меню камеры в v2.57.1 выше.
5. Выбрать `E5 · Нагрузка 16×12`: видны все 192 dense-колонки, камера охватывает
   поле, движение и AI не дают заметной длинной паузы. Затем вернуть E2 и
   проверить восстановление прежнего 7×5 ракурса.

Измеренный локальный headless-профиль 16×12: reachable 0.39 мс, поиск пути
0.39 мс, AI-команда около 24 мс в среднем. Dense Battlefield остаётся текущим
контрактом; эти значения не доказывают необходимость другой storage schema.

Automated gates: `test_combat_vertical_profile.gd`,
`test_combat_vertical_view.gd`, `test_combat_prototype.gd`,
`test_combat_grid.gd`, `test_combat_lab.gd`, combat Resource/AI gates,
Battlefield/tile/arena/camera gates и encounter transition/result bridge.
Forward+ capture создаётся `tools/capture_combat_vertical.gd` только в
`user://`, не меняя авторские сцены или save.

## V2.56.1 · live mesh hot-reload regression gate

1. Загрузить актуальный `vox_fan_lantern_stone` prefab и его четыре размещения в
   `fan_town`, затем вызвать обычный `ensure_saved()` из отдельного test process.
2. Validation по source signature, mesh, collision, Omni и ShadowBody проходит,
   но SHA-256 и modification time prefab, visual mesh и shadow mesh не меняются.
3. Явная кнопка `Пересобрать prefab` и migration store передают отдельный
   `force_rebuild`; stale/missing prefab по-прежнему собирается и сохраняется.
4. Открытые `agent_sandbox`, Surface Canvas и voxel preview проходят реальный
   Forward+ smoke без `Parameter "mesh" is null`.

Automated gates: `test_voxel_prefab_rebuild.gd`,
`test_native_voxel_resource.gd`, `test_voxel_preview_renderer.gd` и внешний
hash/mtime снимок всего `prefabs/voxels`.

## V2.56 · main editor stop-line / stale-prefab gate

1. Read-only профиль выбирает ровно 25 legacy + stale prefab, реально
   используемых `fan_town`, и сравнивает старый prefab с будущей сборкой через
   канонические окрашенные voxel-грани, collision и Omni/shadow properties.
2. Текущий результат: signature-only кандидатов 0/25; видимые грани меняются у
   25/25, collision у 18/25, три emissive candidates затрагивают свет/тени. Поэтому
   следующий автоматический migration batch не создаётся.
3. SHA-256 legacy source, native Resource, prefab и meshes совпадают до/после
   профиля. Подробный JSON пишется только в `user://`; schema и сцена не меняются.
4. Surface Canvas, Graph, Object Inspector и bounded migration dashboard получают
   stop-line. Следующий этап — design Q&A; content rebuild возвращается только в
   контексте визуально утверждаемой D3-зоны.

Automated gates: `profile_voxel_fan_town_stale_prefabs.gd`,
`test_surface_canvas_workflow.gd`, `test_graph_lifecycle.gd`,
`test_content_migration_dashboard.gd` и сохранённые v2.55 migration gates.

Финальный ручной smoke перед production: открыть Surface, сделать Undo/Redo и
Discard; открыть Graph с dirty draft и отменить уход; проверить фильтр
`fan_town: готовые prefab`; закрыть/открыть editor и убедиться, что layout
сохранился, а массовый import `at-icons` не вернулся.

## V2.55 · bounded fan_town ready-prefab batch gate

1. Явный список содержит ровно семь используемых `fan_town` моделей: barrel,
   crate_old, door, horseshoe, inn_sign, lantern_stone и window. Изменение сцены
   не может молча расширить уже согласованную партию.
2. Read-only preflight даёт 7/7 exact parity: identity, validation, portable
   provenance, metadata, vertices, normals, colors, indices и collision source.
   SHA-256 legacy/Resource/prefab до и после dry-run совпадают.
3. Dashboard имеет отдельный `fan_town: готовые prefab` фильтр. Перенос выключен
   до успешного preflight текущих семи ID и инвалидируется после refresh.
4. Итог: 15 native / 162 legacy voxel owners; семь Resources совпадают с
   transient preview, prefab остаются ready по прежним путям, `fan_town.tscn` и
   JOI не переписаны. Общая операция проходит Ctrl+Z/Redo на disposable fixtures.
5. Forward+ RTX 5070 загружает настоящую `fan_town`, завершает Surface projection
   и показывает прежние props, прозрачную воду/пену и освещение без parse/runtime
   errors.

Automated gates: `test_voxel_fan_town_ready_migration_parity.gd`,
`test_voxel_fan_town_ready_native_batch.gd`, `test_content_migration_report.gd`,
`test_content_migration_dashboard.gd`, `test_voxel_migration_batch.gd`,
`test_voxel_prefab_rebuild.gd` и `test_fan_town_surface_projection.gd`.

## V2.54.2 · editor import-cache gate

1. Отключённый `at-icons` сохраняет `addons/at-icons/.gdignore`; его 3 708 SVG
   не участвуют в asset scan и не вызывают повторный импорт при старте.
2. `project.godot` не включает `at-icons`, а gameplay/runtime не ссылаются на
   файлы дополнения. Удаление `.gdignore` допустимо только при намеренном
   включении picker и означает один ожидаемый импорт в обычном GUI.
3. Автоматические проверки не используют `--headless --editor` в рабочем
   checkout. Targeted tests идут через `--headless --path . --script ...`, а
   editor/import smoke — в отдельном checkout или import cache.
4. Ручной gate: после завершения уже начавшейся операции следующий запуск GUI
   не показывает долгий `Импорт или повторный импорт ассетов` для `at-icons`.

## V2.54.1 · native water-coordinate regression gate

1. Создать level-fill в Surface Canvas и убедиться, что прозрачная вода с
   water/foam shader покрывает фактическую чашу, а не сжимается у начала чанка.
2. Runtime fixture размещает воду во втором 16×16-art-voxel chunk. Её вершины
   после transform обязаны точно совпасть с canonical water-cell.
3. Сухой chunk продолжает использовать native exact backend; только chunk с
   water-mask/fill переключается на stock Surface mesher. Resource schema,
   water channels, collision/navigation и save format не меняются.
4. Forward+ gate: `test_surface_canvas_workflow.gd -- --visual-water`; на кадре
   видны прозрачное дно, спокойные светлые полосы и shoreline foam.

Automated gates: `test_world_surface_projection.gd`,
`test_surface_canvas_workflow.gd`, `test_voxel_surface_sculpt.gd`,
`test_water_contact_boundaries.gd` и `test_surface_large_profile.gd`.

## V2.54 · measured fan_town physical Surface gate

1. Read-only профиль строит будущую `fan_town` Surface только в памяти и пишет
   JSON/round-trip в `user://`. Ожидаются 32×32 блока, grid 512×48×512,
   12 582 912 voxel bytes, около 16.8 MB `.tres`, save <0.2 с и reopen около 1 с.
2. Native exact visual backend общий для сухих Canvas/world runtime chunks. Все
   12 сухих sample chunks проходят native path примерно за 5–7 мс; stock exact
   path обслуживает water-bearing chunks, per-voxel transparency и отсутствие
   Voxel Tools.
3. Heightfield считается в WorkerThreadPool из immutable snapshot. До готовности
   и всех 64 collision chunks legacy Collision активен; затем переключение
   атомарно. Stale результат после повторной правки не может заменить новый.
4. `fan_town.tscn` хранит ссылку на canonical Surface, bounds 32×32 и physics
   opt-in. Floor sample, соседний route и PhysicsServer ray совпадают; runtime
   gate не меняет сцену или `.tres`.
5. Forward+ Vulkan кадр должен завершить ровно 1024 visual и 64 collision chunks
   без seam, сдвига props и parse/runtime errors.

Automated gates: `test_fan_town_surface_profile.gd`,
`test_fan_town_surface_projection.gd`, `test_world_surface_projection.gd` и
`test_surface_large_profile.gd`.

## V2.53 · physical Surface sandbox gate

1. `agent_sandbox.tscn` сохраняет `authored_size_blocks = 24×24` и явный
   `use_visual_surface_physics`; `fan_town` остаётся выключен до отдельного
   профиля. Surface Resource имеет штатный `physical = true`, schema v4 не
   меняется.
2. При старте старый `Terrain/Mesh` и `Terrain/Collision` остаются fallback.
   После готовности visual/physics очередей visual скрыт, collision получает
   layer 0, а 144 производных 2×2-block StaticBody чанка получают layer 1.
   При `Resource.changed` прежние нативные чанки живут до атомарной замены.
3. Collision строит greedy top rectangles из тех же solid-вокселей; вода и
   fill planes не входят в физику. На reference workstation профиль сократился
   с ~1.83 с / 134 мс худшего 4×4 чанка до ~1.11 с / 10–14 мс худшего 2×2.
4. Тот же проход собирает transient top-height cache. Floor sample, PhysicsServer
   ray и маршрут между соседними блоками совпадают по Y; route query после
   rebuild занимает <1 мс вместо ~61 мс повторного dense scan.
5. Reopen сцены сохраняет только map flags и ссылку на прежний `.tres`.
   Collision meshes, route grid и height cache не сериализуются. Forward+
   Vulkan 1280×720 отрисовывает реальный sandbox без parse/runtime errors.

Automated gate: `tools/test_world_surface_projection.gd`. Regression:
`test_surface_large_profile.gd`, Canvas workflow, water boundaries,
selection/groups/palette/slice/sculpt, map transition и native cutaway.

## V2.52 · strict dry-run → native sandbox batch gate

1. До первого переноса dashboard показывал шесть legacy sandbox-кандидатов.
   `Проверить sandbox-партию` строит будущие Resources только в памяти и требует
   6/6 exact parity: identity/validation/provenance, metadata, vertices, normals,
   colors, indices и общий visual/collision mesh. Файлы до успешного dry-run не
   меняются.
2. Только после зелёного отчёта активируется `Перенести проверенную партию`.
   Все шесть Resources и prefab создаются одной операцией Ctrl+Z/Redo; ошибка в
   любой модели откатывает уже записанную часть.
3. Текущее завершённое состояние: `vox_ms8vsb53`, `vox_vil_bush`,
   `vox_vil_counter`, `vox_vil_mailbox`, `vox_vil_planter`, `vox_vil_sign`
   имеют owner `Godot`, prefab `готов` и прежние scene IDs/references. Фильтр
   `Sandbox-партия` сохраняет эти шесть строк для проверки, но обе migration
   кнопки отключены и сообщают, что повторный перенос не требуется.
4. Reopen в новом процессе загружает все `.tres` и PackedScene, validation и
   source hash совпадают с reviewed preview. Forward+ `agent_sandbox` не теряет
   mesh/material/collision; это parity gate, не art approval.
5. Новый baseline: voxel 177 всего / 8 native / 169 legacy; derived prefab
   63 ready / 25 stale / 88 missing. Один нецелевой legacy prefab обновился как
   derived fixture batch Undo test; его ownership остался legacy.

Automated gates: `tools/test_voxel_sandbox_migration_parity.gd` доказывает
read-only exact preflight; `tools/test_voxel_migration_batch.gd` проверяет одну
batch Undo/Redo transaction на disposable legacy fixtures и восстанавливает их
Resource/derived bytes; `tools/test_voxel_sandbox_native_batch.gd` проверяет
финальные шесть Resources/prefab/references и настоящий Forward+ screenshot
`user://ember_sandbox_native_voxel_batch.png`. Затем последовательно идут
content report/dashboard, visual library, prefab rebuild и editor startup.

## V2.51 · filterable G1/G2 dashboard gate

1. В `Ember Migration` сначала нажать `Измерить G1/G2`, затем `Подробности…`.
   Открывается отдельное окно `МИГРАЦИЯ КОНТЕНТА · G1/G2`; нижняя панель не
   растягивается, а окно явно помечено `СНАЧАЛА DRY-RUN`.
2. Без фильтров показано `263 из 263 записей`. Выбор раздела и состояния, а также
   поиск по ID/error/scene обновляют левый список; справа видны owner, validation,
   prefab state и все сцены выбранной voxel-модели.
3. Нажать `Показать sandbox-партию`. Должны остаться ровно `vox_ms8vsb53`,
   `vox_vil_bush`, `vox_vil_counter`, `vox_vil_mailbox`, `vox_vil_planter` и
   `vox_vil_sign`; после v2.52 все шесть native, используются `agent_sandbox` и
   имеют ready prefab. Исторический legacy-candidate state покрыт новым dry-run
   gate и не восстанавливается ради ручной проверки.
4. Выбрать `VN-арт` + `Требует внимания` и найти
   `49bd31e4-b1e2-495d-b57d-eb01994be362`: detail сообщает об отсутствующем
   изображении. Сброс фильтров возвращает полный список.
5. В окне нет произвольного bulk migrate. Ограниченная sandbox-команда доступна
   только после exact dry-run; в завершённом состоянии она disabled.
   `Обновить измерение` остаётся read-only, а `Сохранить JSON` пишет только
   `user://`.

Automated gates: `tools/test_content_migration_dashboard.gd` проверяет полный
список, комбинированные фильтры, sandbox shortcut, detail и отсутствие bulk
action; `tools/test_content_migration_report.gd` проверяет ту же pure projection
против baseline; `tools/test_migration_workflow_layout.gd` проверяет маршрут из
нижней панели. Forward+ screenshot:
`user://ember_content_migration_dashboard_test.png` при аргументе `--visual`.

## V2.50 · read-only G1/G2 inventory gate

1. Открыть нижнюю панель `Ember Migration`, раздел
   `Миграция контента · G1/G2`, и нажать `Измерить G1/G2`. Операция не создаёт
   Resource/prefab, не меняет карты и не пишет в JOI.
2. Сводка показывает отдельные native/legacy/error числа для voxel, action,
   dialogue, item, shop и VN, а для voxel — ещё ready/stale/missing prefab.
   Кнопка `Сохранить JSON` пишет только в `user://`.
3. Reference baseline 5 сентября: voxel 177 всего / 2 native / 175 legacy;
   action 13/4, dialogue 2/10, item 5/19, shop 1/1, VN 2/29.
4. Из 176 prefab-required voxel-моделей 56 актуальны, 32 stale и 88 отсутствуют.
   Это запрещает считать существование старого prefab доказательством parity и
   подтверждает перенос небольшими выбранными партиями.
5. Единственная текущая content-ошибка — отсутствующий файл legacy VN background
   `49bd31e4-b1e2-495d-b57d-eb01994be362`. Scene voxel references без catalog
   owner не найдены. Устаревшие prefab пока только диагностируются.

Automated gate: `tools/test_content_migration_report.gd` проверяет полноту шести
доменов, арифметику, voxel references/derived states, JSON round-trip и SHA-256
неизменность native sources, prefab и frozen JOI voxel archive.
`test_migration_workflow_layout.gd` проверяет UI и настоящий Forward+ снимок.
`test_voxel_migration_queue.gd` временно создаёт native fixture, поэтому его
запускать последовательно, не одновременно с read-only catalog/report tests.

## V2.49 · Graph hierarchy + narrow workspace gate

1. Открыть `Ember Graph` при 1280×720. Выбор типа документа, Resource,
   обновление и основное сохранение остаются в одной верхней строке; смена
   action/dialogue/quest не переносит их на другую высоту.
2. Во второй строке остаются только локальные действия текущего режима и
   выбранной ноды. Раскладка, дублирование, буфер, группы и диагностический
   режим `Все связи` находятся в `Ещё…`; окно не теряет высоту из-за wrap.
3. В Quest Flow `Задание › …` работает как breadcrumb: в фокусе цели кнопка
   возвращает обзор, длинное название обрезается с tooltip. `Все связи` остаётся
   отдельным диагностическим режимом и не выглядит следующим шагом иерархии.
4. Перетащить разделитель правого редактора, закрыть и снова открыть Godot.
   Пропорция восстанавливается из `editor_layout.cfg`, ограничивается безопасным
   диапазоном и не попадает в action/dialogue/quest документы.
5. Проверить 1600×900 и узкую правую колонку: названия и диагностика обрезаются,
   GraphEdit остаётся видимым. Save, draft Undo/Redo, discard guard и камера
   работают по прежним owners.

Automated gates: `tools/test_graph_workspace.gd` фиксирует настоящий layout
1280×720 и 1600×900, overflow ownership, primary Save и round-trip split ratio;
`tools/test_graph_lifecycle.gd` проверяет три mount/unmount цикла и Forward+
снимок. Editor plugin startup проходит без parse/init errors; schema не менялась.

## V2.48 · Surface close + remembered-view gate

1. Изменить Surface и переключиться с `Surface Canvas` на 3D/Script. Появляется
   один диалог `Сохранить и закрыть / Отбросить и закрыть / Остаться в Canvas`;
   Cancel возвращает Canvas с тем же draft.
2. Повторить Save и Discard. Save продолжает переход только после успешной
   validation/записи; для Resource без writable `.tres` пути диалог остаётся
   открыт и данные не теряются. Discard восстанавливает последний saved baseline.
3. С dirty Surface закрыть Godot и проверить штатный общий unsaved prompt.
   `Сохранить` вызывает тот же Surface save, `Не сохранять` завершает редактор,
   Cancel оставляет его открытым. Обычный общий Save также сохраняет external data.
4. Для Surface изменить orbit/pan/zoom, region, height slice, видимость grid/region
   и `только дно`; открыть другую Surface и вернуться. Все значения восстанавливаются,
   но dirty marker и voxel bytes не меняются.
5. Перезапустить редактор и снова открыть Surface: последние 32 per-resource view
   живут в `editor_layout.cfg`, не в `.tres`. Повреждённые/out-of-range значения
   нормализуются; world/battle handoff с явной region использует новую region.

Automated gate: `tools/test_surface_canvas_workflow.gd` проверяет navigation и
close Save/Discard/Cancel, failed save, per-resource/layout round-trip,
validation и отсутствие Resource dirty. `ember_surface_canvas/plugin.gd` и все
view/lifecycle scripts проходят `--check-only`; Graph, slice, sculpt, native
backend, projection, selection/groups/palette regressions остаются зелёными.

## V2.47 · large Surface performance gate

1. Запустить `tools/test_surface_large_profile.gd` на canonical
   `agent_sandbox_surface.tres`. Тест читает авторскую Surface, но save/reopen и
   JSON-отчёт пишет только в `user://`; карта проекта не изменяется.
2. В отчёте зафиксированы grid/dense bytes/occupancy, три cache-bypassed Resource loads,
   синхронный Canvas open, exact/draft/native chunk, frame-budgeted drain,
   connected selection, overlay, group visibility/isolation, validation,
   save и reopen.
3. На reference workstation 384×32×384 = 4 718 592 voxel slots, 557 205 заняты;
   dense рабочие каналы занимают 10 321 920 bytes (9.84 MiB). Load ≈0.80 с,
   save ≈0.13 с: schema остаётся dense v4, sparse/chunk persistence не вводится.
4. Sparse-aware heightfield обязан совпасть с reference column scan; dense
   fixture остаётся на bounded column path. Canvas open ≈0.79 → 0.12 с, а
   editor-only group filter ≈0.71 → 0.019 с без записи view-state в Resource.
5. Exact terrain chunk использует Voxel Tools и затем получает тот же canonical
   water overlay; per-voxel transparency сохраняет stock fallback. Reference
   chunk ≈25.5 → 5.9–6.6 мс, drain собирает 1–2 быстрых chunks за 6–11 мс.
6. Selection cap, atomic overflow и overlay остаются incremental; save/reopen
   byte-identical по voxel/fill/group данным. Проверить Forward+ viewport без
   seam/пропавшей воды; reference full preview завершает 576 chunks примерно за
   6.05 с / 472 rendered frames. Затем regressions selection/groups/palette/
   slice/sculpt, Canvas workflow и world projection.

Automated profile: `tools/test_surface_large_profile.gd`. Correctness gates:
`test_voxel_surface_sculpt.gd`, `test_surface_canvas_workflow.gd`,
`test_voxel_groups.gd`, `test_voxel_selection.gd`,
`test_voxel_selection_mask.gd`, `test_surface_height_slice.gd`,
`test_voxel_palette.gd`, `test_world_surface_projection.gd`.

## V2.46 · palette ramp gate

1. В Surface Canvas выбрать используемый цвет и нажать `Рамп оттенков…`.
2. Переключить три характера света и 3/5/7 оттенков: preview меняется, сама
   модель и dirty-marker до `Применить` не меняются.
3. Применить рамп: исходный цвет остаётся центральным, внешний вид прежних
   вокселей и воды не меняется, новые соседние образцы доступны кисти.
4. Один Ctrl+Z удаляет весь рамп и возвращает индексы; Redo восстанавливает.
   Ctrl+S + reopen сохраняют палитру и обе группы ссылок.
5. У почти заполненной палитры невозможный рамп отклоняется без частичной записи.

Targeted gate: `tools/test_voxel_palette.gd`; Forward+ 1280×720 проверяет кнопку,
диалог и preview. Resource schema и runtime не меняются.

## V2.45 · group color and editor-only visibility gate

1. Для именованной группы изменить `Цвет группы`: selection overlay получает
   этот цвет, но palette и модель не перекрашиваются.
2. Выключить `Показывать в просмотре` у нескольких групп: исчезают только их
   воксели, вода остаётся; `.tres` не становится dirty.
3. Изоляция показывает выбранную группу и скрывает воду; выбранная ранее скрытая
   группа автоматически становится видима. Смена Resource очищает view-фильтры.
4. Цвет проходит Undo/Redo и save/reopen; видимость после reopen не сохраняется.

Targeted gate: `tools/test_voxel_groups.gd`; Resource schema v4 хранит только
authoring-color, runtime rendering/physics его игнорируют.

## V2.44 · compact brush families and shape-footprint gate

1. В левой рейке ровно восемь инструментов. `Объём` показывает `добавить / убрать`; оба режима реально работают и имеют правильный курсор/подсказку. `Рельеф` показывает `вверх / вниз`, `сплошная / оболочка`, предел и скорость; проверить все четыре сочетания без поиска отдельных кистей в списке.
2. Создать несколько несмежных выбранных вокселей. Для Paint/Material переключатель подписан как точная voxel-маска, мазок не выходит за неё и сохраняет выделение. Для Volume/Relief/Level/Smooth/Ramp подпись меняется на колонки выделения.
3. Широкой кистью `Объём · убрать` провести через выбранную и соседнюю колонки: меняется только выбранный XZ-отпечаток. Undo, затем `Рельеф · вверх`: новые воксели появляются над отпечатком, но не над соседями. После успешной формы маска очищается; Ctrl+Z возвращает форму. Esc во время жеста возвращает baseline и сохраняет маску.
4. `Заливка уровня` выключает маску и продолжает проверять целую замкнутую впадину. Защищённые группы, рабочая область и высотный срез продолжают ограничивать конечные записи независимо от профиля кисти.

Automated: `tools/test_voxel_selection_mask.gd`, `tools/test_graph_workspace.gd`; `-- --visual` показывает Relief/Shell и XZ-mask в `user://ember_selection_mask_test.png`. Regression: groups/selection/palette, height slice, Canvas workflow, sculpt/native backend and world projection.

## V2.43 · selection-masked brush gate

1. В Surface Canvas создать маску через V: выбрать несколько несмежных вокселей и оставить рядом похожие, но не выбранные. Переключиться на `Красить`, включить `Кисть только внутри выделения` и провести широкой кистью через всю область: меняется только пересечение кисти с маской.
2. Сделать второй мазок другим цветом: маска остаётся. Ctrl+Z/Redo корректно меняют Resource и очищают подсветку как устаревшую; повторное выделение позволяет продолжить. Ctrl+S/reopen сохраняет изменения, но не временную маску.
3. Повторить с `Материал / вода`: прозрачность меняется только у выбранных занятых вокселей. Воксели защищённой именованной группы остаются неизменными даже внутри маски; остальные выбранные меняются.
4. Начать мазок и нажать Esc: исходные байты восстановлены одним отменённым жестом, маска остаётся пригодной для повтора. Исторически в v2.43 форма отключала маску; v2.44 заменяет это поведение явным XZ-отпечатком.

Automated: `tools/test_voxel_selection_mask.gd`; `-- --visual` сохраняет `user://ember_selection_mask_test.png`. Regression: groups/selection/palette, height slice, Surface workflow, sculpt/native backend and world projection.

## V2.42 · named voxel groups gate

1. Создать маску через V/похожие цвета → `+ Из выделения`, ввести имя. Группа появляется со счётчиком; создание не меняет voxels, но делает Resource dirty. Ctrl+Z/Redo удаляют/возвращают группу одним действием.
2. `Имя…` меняет подпись, стабильный внутренний ID остаётся прежним. `Заменить состав выделением` принимает непустую текущую маску; пустой состав отклоняется. `Выделить группу` восстанавливает её в оранжевую маску.
3. Включить `Защитить воксели от кистей`. Провести Add/Remove/Paint/Material через группу и рядом: группа не меняется, соседние незаблокированные ячейки меняются; UI сообщает о защите. `Окрасить выделенное` соблюдает ту же защиту. Вода и глобальная смена образца палитры остаются отдельными явными операциями.
4. `Изолировать в просмотре`: остаётся только геометрия группы, вода скрыта, picking не попадает в спрятанные воксели. Выключить — полный вид возвращён, dirty не возник. Смена/удаление группы, другой Resource или скрытие Canvas не оставляют старую изоляцию.
5. Ctrl+S/reopen: имя, ID, состав и lock восстановлены; runtime-карта выглядит и сталкивается как раньше. `Удалить группу` не удаляет воксели и отменяется одним Ctrl+Z. Discard возвращает сохранённые группы.
6. Повреждённые данные (повторный/пустой ID, несортированные, повторные или выходящие за массив индексы) останавливают сохранение понятной validation error. Старые Resources с пустым списком продолжают открываться; первая операция группы переводит schema в v3.

Automated: `tools/test_voxel_groups.gd`; `-- --visual` сохраняет user://ember_groups_test.png. Regression: voxel selection/palette, native Resource/import queue, height slice, Surface workflow, sculpt/native backend and world projection.

## V2.41 · voxel selection gate

1. Canvas → справа под палитрой `Выбирать воксели · V`. Клик по стенке выбирает связные в объёме воксели одного RGB, отдельный остров не включается. Допуск сравнивает цвета с исходным, не с предыдущим соседом.
2. `Все похожего цвета` включает остров; `Один воксель` берёт только hit. Shift добавляет, Ctrl вычитает; списки дают тот же результат. Клик не запускает sculpt-кисть и не меняет dirty/Undo.
3. Рабочая область/срез: прежняя маска снята, новый поиск не проходит через скрытые слои/вне области. Счётчик включает внутренние воксели; подсветка depth-tested, не X-ray.
4. Выбрать цвет палитры → `Окрасить выделенное`: меняются только выбранные занятые ячейки. Ctrl+Z/Redo восстанавливают покраску; вода, материалы, геометрия и палитра не меняются. После Undo маска снята, после собственной покраски остаётся.
5. Во время поиска карта не меняется и Apply недоступен. Esc отменяет поиск, сохраняя прежнюю маску. Лимит 32 768 отклоняет результат целиком. Смена модели/области, обычный мазок или изменение палитры отменяют устаревшую маску.
6. Ctrl+S/reopen сохраняет покраску без transient mask. `Снять выделение` очищает маску; обычные кисти НЕ используют её автоматически. Именованные группы — следующий этап.

Automated: `tools/test_voxel_selection.gd`; с GPU `-- --visual` сохраняет user://ember_selection_test.png. Regression: palette, height slice, Surface workflow, sculpt/native mesher, world projection.

## V2.40 · Surface palette gate

1. Открыть Surface Canvas. Справа цветные образцы: выбор синхронизируется с верхним списком кисти, но не меняет модель. При большом числе цветов прокручивается сетка, не растёт весь холст.
2. `+ Цвет` → выбрать RGB/HSV/HEX → `Применить`: появился выбранный образец. До подтверждения и после `Отмена` модель не меняется. В окне 1280×720 Apply/Cancel остаются видимыми, содержимое диалога прокручивается.
3. `Изменить` меняет образец глобально, включая скрытые слои/области и воду с этим оттенком. Предупреждение указывает область действия. Кисть `Красить` по-прежнему локальна.
4. `Заменить…` → выбрать другой цвет: исходный образец исчезает, его воксели остаются с цветом замены. Другие цвета и water tint не съезжают. Ctrl+Z/Redo возвращают все индексы и палитру вместе.
5. `Пипетка · I` → клик по вокселю выбирает его исходный цвет. Пустой клик не красит, Esc отменяет. В срезе берётся цвет доступного нижнего слоя. Во время ввода HEX горячая клавиша I не включает пипетку.
6. Ctrl+S → переоткрыть `.tres`: палитра, геометрия и ссылки воды сохраняются. Смена Surface/скрытие Canvas закрывает диалог, не перенося операцию на другую модель. 255 цветов — предел; нулевой цвет и удаление последнего образца недоступны.

Automated: `tools/test_voxel_palette.gd` (добавить `-- --visual` без headless для снимков); regression: Canvas workflow, height slice, voxel surface sculpt, native backend и world projection. Именованные группы/общее выделение остаются следующими этапами, не частью этой приёмки.

## V2.39 · Surface height slice gate

Automated: `test_surface_height_slice.gd`, `test_surface_canvas_workflow.gd`, `test_voxel_surface_sculpt.gd`, `test_voxel_tools_backend.gd`, `test_world_surface_projection.gd`. Новая проверка использует disposable 2-block модель с верхней крышей и нижними слоями: ray pick, native/stock cap, Add/Remove/Paint/Material возле границы X/Z и Y, Undo/Redo, save/reopen без отсечения данных, смена уровня во время held gesture. `-- --visual` рендерит рабочий Canvas с включённым срезом без запуска рабочего editor/import.

Manual: открыть свою Surface, справа включить `Срез по высоте`, уменьшить `Видно снизу N vox`. Крыша скрыта, плоскость среза закрыта гранями, курсор выбирает видимые воксели. Широкой кистью рисовать по краю выбранного участка: соседние X/Z и скрытый верх не меняются. Выключить срез и сравнить верх, Undo/Redo, сохранить/переоткрыть полную карту. При включении среза вода скрыта; заливка, рельеф и smart flood недоступны. Runtime всегда видит полную модель. Срез не равнозначен физическому cutaway или удалению слоёв.

## V2.38.1 · Graph lifecycle regression gate

Run `test_graph_workspace.gd` and `test_graph_lifecycle.gd` with the project Godot binary, `--headless --path . --script res://tools/<test>.gd`. Require both PASS and no `move_child`, `ObjectDB`, `RID allocations` errors/warnings. The lifecycle test writes no content: it repeatedly reconstructs grouped dialogue drafts in one tick, switches away before deferred native frame ordering finishes, verifies retired frames disappear, drills into quest objectives, then closes/reopens the workspace three times. Orphan-node count must return to the baseline both during use and after teardown.

Manual editor gate: group two dialogue nodes, rename/collapse/expand and Undo/Redo quickly; change to a quest, open an objective, return to overview repeatedly; close/reopen the workspace. Retired frames must never flash, intercept input, appear in saved layout or leave stale wires. Optional disposable Forward+ capture: `--script res://tools/test_graph_lifecycle.gd -- --visual`.

## V2.38 · water boundaries / Surface authoring safety

Исторический остаток v2.38: общий Graph smoke выдавал `move_child` и RID/ObjectDB leaks. Закрыто в v2.38.1, см. lifecycle gate выше.

Автоматические проверки: `test_water_contact_boundaries.gd` (несколько водоёмов, другой viewport, появление/удаление projection, прыжок и возврат, береговая маска кольца и дорожек); `test_surface_canvas_workflow.gd` (реальный клик заливки, tint, неизменное дно, Undo/Redo, save/reopen, dirty navigation, неудачный Save, discard общего Resource, скрытие активной кисти, view-only настройки). Дополнительно прогонять `test_world_surface_projection.gd` и `test_voxel_surface_sculpt.gd`. UI gate: обычный Godot `--script res://tools/test_surface_canvas_workflow.gd -- --visual`, второй запуск с `--wide`; это disposable viewport, не `--editor` и не пользовательская карта.

Ручная приёмка в рабочем редакторе:

1. В заливке выбрать цвет из палитры, кликнуть по дну. Поменять уровень, Undo/Redo, сохранить и открыть заново: дно цело, tint и маска совпадают. Слой `только дно` временно прячет воду, не удаляет её.
2. Ходить вдоль узкого берега, развернуться, выйти и снова зайти в воду. Нет дорожек на суше, сквозных следов после прыжка/телепорта или реакции на Surface другого preview. Крупность маски 12×12 оценить на игровом масштабе.
3. Отредактировать A и открыть B: проверить три ответа диалога. Без валидного пути Save не должен открывать B. Повторно открыть другую область A: звёздочка не пропадает. Уход со вкладки при удержании кисти завершает жест.
4. G над холстом и `Вид → Рамка рабочей области` скрывают только разметку. Ctrl+S сохраняет текущую Surface. Закрытие всего Godot пока не является проверенным этим диалогом сценарием: использовать явный Save перед выходом.

Производительность: кэш не требует повторного вертикального поиска в уже посещённых колонках, но выигрыш FPS не заявляется без отдельного F3 до/после на пользовательской карте.

Статус с **29 августа 2026**: **активная постепенная миграция**. JOI/Three play и editor viewport приостановлены; фокус разработки — этот репозиторий (Godot 4 Forward+). Решение «оставить Three живым runtime» снято.

Целевой продуктовый vision зафиксирован в [`docs/EMBER_PRODUCT_PLAN.md`](docs/EMBER_PRODUCT_PLAN.md): top-down party JRPG, граф зон, пошаговая стихийная боёвка, отношения и сюжетная романтика. Этот файл проверяет и ведёт перенос фундамента под vision; открытые design-решения боя не должны незаметно превращаться здесь в runtime-контракт.

## Что доказываем

Godot считается лучшим основанием для игры, только если одновременно выполняются три условия:

1. Богатый ночной свет с локальными тенями стабилен на целевом ПК.
2. Авторский цикл карты и voxel-пропа не заметно медленнее текущего JOI editor.
3. Базовые механики можно перенести без второго формата данных и без расхождения физической поверхности.

Красивого одного кадра недостаточно. Мы проверяем повторяемую ежедневную работу.

## Источники правды на время полного переезда

- Карта после импорта: `ember-godot/scenes/*.tscn`.
- Размещение и ручная доводка: экземпляры `res://prefabs/voxels/*.tscn` внутри Godot-сцены.
- Voxel-модель после явного импорта: `content/voxel_models/<id>.tres` (`EmberVoxelModelResource`).
- Пара `.vox` + `.json` в `joi-conductor/content/ember/voxels/models` — только read-only очередь одноразового импорта и архив сверки; новые модели там не создаются.
- Сгенерированные Godot mesh/prefab/thumbnail/MeshLibrary — cache результата, а не формат исходного контента.
- Полный reimport карты является разрушительной операцией и всегда требует подтверждения.

Godot получает единственный voxel editor, а не второй sculptor рядом с JOI. Переход поэтапный: импортировать модель → сверить preview/mesh/collision/channels → редактировать и сохранять только `.tres` → перестать читать legacy пару → после общего отчёта заморозить архив JOI.

## Контрольные сцены

- `scenes/fan_town.tscn` — свет, атмосфера, плотная сцена и авторский цикл.
- `scenes/agent_sandbox.tscn` — ходьба, камера, collision, interact, door/shop/map change.
- Не использовать `hu_tao_yard` и `hu_tao_p1` для проверки механик: волны и урон искажают результат.

## Волна 0 — воспроизводимая база

- [x] Проект открывается в Godot 4.7 Forward+ без ошибок parser/runtime.
- [x] `python tools/test_vox_axes.py` проходит.
- [x] Headless editor загружает проект и addon.
- [x] Headless play загружает default scene без ошибок.
- [ ] Снять версию Godot, GPU, разрешение окна и один baseline-скрин.

Выход волны: любой следующий замер можно повторить на той же сцене и конфигурации.

## Волна 1 — свет и понятные настройки

Инструменты:

- Dock `EMBER · проверка миграции` справа в редакторе.
- Узел `Map`: группы `Карта и тест`, `Атмосфера`, `Луна`, `Фонари`, `Камера и качество`.
- В Play: `F3` показывает метрики и фактическое число активных/доступных теней; `F4` переключает 0 → 2 → 4 → 8 → 12 → 16. Профили 12/16 являются stress, production остаётся 8.

Основной протокол для профилей 0/2/4/8; 12/16 прогоняются дополнительно как stress:

1. Запустить `fan_town` в 1600×900 и встать в одну контрольную точку.
2. Включить F3, дождаться 10 секунд прогрева.
3. 60 секунд пройти один и тот же маршрут с одинаковым поворотом камеры.
4. Записать FPS, frame p95, render CPU/GPU, visible draw calls, shadow draw calls.
5. Отметить визуально: тени фонарей читаются, fill не исчез, переключение профиля не вызывает заметного фриза.

Порог первого решения на текущем ПК:

- профиль 4 должен держать frame p95 ≤ 20 ms;
- профиль 8 считается рабочим, если p95 ухудшается не более чем на 25% относительно профиля 4 и нет регулярных кадров > 33 ms;
- переключение 0/2/4/8 не меняет цвет/силу fill, только число локальных умбр;
- качество луны и туман оцениваются отдельно, не подстраиваются между прогонами.

Если профиль 8 не проходит, это не провал Godot: фиксируем рекомендуемый бюджет 4 и повторяем после плотной сцены/персонажей. Если не проходит 4, сначала профилируем atlas/filter/range, а не режем все лампы.

Production-замер 2026-08-26, `fan_town`, 1600×900: budget 8, FPS 200 (cap), frame p95 5.00 ms, render CPU 0.52 ms, GPU 2.15 ms, visible draw calls 30, shadow draw calls 396. Пользователь подтвердил стабильность и отсутствие заметного падения; production-профиль 8 принят. Текущая карта содержит только 11 подходящих lantern-кастеров, поэтому F3 должен показывать `active/candidates`: budget 16 на этой карте не является фактическим тестом 16 теней.

## Волна 2 — ежедневный цикл voxel-пропа

Инструментальная часть готова:

- [x] Dock различает геометрию `.vox` и обязательные metadata `.json`, показывает число instance на открытой сцене.
- [x] У prefab хранится SHA-256 подпись пары исходников; до пересборки видно состояние «актуален / нужна пересборка».
- [x] Точечная пересборка автоматически проверяет `Mesh`, ожидаемые `Collision`, `Omni` и host `ShadowBody`.
- [x] До/после сравниваются hash файла карты и `transform + placement_id` всех instance этой модели.
- [x] Generated mesh/prefab сохраняют стабильные Godot UID при перезаписи, поэтому ссылки сцен не протухают.
- [x] Selection bounds voxel-пропа берутся только из `Mesh` и не раздуваются радиусом дочернего `Omni`.
- [x] Mesh при rebuild обновляется in-place: открытый viewport сразу получает новый цвет/форму без reload сцены.
- [x] Исторический emissive deep-link в JOI работал как временный bridge; v1.98 заменяет его Godot-owned Resource/editor и не считает ссылку конечным authoring workflow.
- [x] Тот же bridge поддерживает `Материал → Прозрачность`; targeted rebuild читает JSON-канал, разделяет opaque/transparent surfaces и сохраняет live mesh identity.
- [x] Headless smoke: `godot --headless --path . --script res://tools/test_voxel_prefab_rebuild.gd`.
- [x] Цвет, изменение формы, emissive и transparency визуально подтверждены пользователем в editor/play. Активное время не записано, поэтому критерий ≤ 90 секунд остаётся неизмеренным и будет снят на следующей обычной правке.

Три одинаковых задания на знакомом пропе:

1. Изменить один цвет/воксель.
2. Изменить форму на 5–10 вокселей.
3. Изменить emissive-окно и проверить положение/свет Omni.

Для каждого задания:

1. В Godot выбрать instance внутри `Map/Props`.
2. Legacy-модель сначала явно перенести в Godot Resource; исходные `.vox/.json` после этого открываются только для диагностики происхождения.
3. Форму, палитру и extra-каналы менять в Godot voxel editor; save пишет только `.tres`, prefab rebuild читает тот же Resource.
4. Нажать `Пересобрать только этот prefab`.
5. Убедиться, что dock сообщил `Mesh + Collision/Omni/ShadowBody` согласно metadata и подтвердил неизменность карты/transforms; затем визуально проверить результат.

Записываем активное время, число ручных шагов и ошибки. Цель: обычная правка ≤ 90 секунд от выбора пропа до результата, без полного reimport карты и без потери transform/placement.

После трёх заданий принимается одно решение:

- native editor проходит ежедневный authoring цикл — выключаем legacy fallback для перенесённой модели;
- нужен глубокий editor bridge (выбор модели/палитры/метаданных из Godot);
- нужен нативный Godot voxel tool. Последний вариант разрешается только после подтверждённого UX-разрыва, а не заранее.

## Волна 3 — безопасное редактирование карты

- [x] Headless round-trip на копии сцены: move/rotate/safe duplicate двери вместе с вложенным `Interact` переживают save/reopen; исходный `.tscn` и JOI JSON не меняются.
- [x] В editor вручную нажать `Дублировать безопасно · +X`, подвигать/повернуть копию, Ctrl+S и повторно открыть сцену — пользователь подтвердил, что copy/move/форма работают.
- [x] Добавить/изменить `Interact` без изменения schema pack: I2 принят вручную, scene-owned mutation проходит Undo/Redo и save/reopen.
- [x] Полный reimport требует подтверждения и явно сообщает, что будут потеряны ручные позиции и вложенные правки.
- [ ] Проверить diff `.tscn`: одна локальная правка не переписывает всю сцену без причины.
- [x] Ownership зафиксирован: props/transforms/вложенный `Interact` после импорта принадлежат Godot `.tscn`; terrain/regions до появления нативных инструментов остаются односторонним импортом из JOI и вручную в Godot не редактируются. Reimport для них намеренно разрушителен и подтверждается.

Выход волны: описан нормальный путь правки и путь восстановления, случайный reimport не уничтожает работу одним кликом.

## Волна 4 — вертикальный срез механик

Проверять в `agent_sandbox`:

- [ ] spawn, ходьба, camera и collision используют одну высотную поверхность; camera-relative WASD уже перенесён из JOI и закреплён headless для yaw 0°/90° и диагонали, ручная проверка collision/ступеней остаётся;
- [x] door и map-trigger используют существующие `targetMapId/targetRegionId`; headless проверяет маршрут `agent_sandbox → agent_sandbox_interior:start → agent_sandbox:cabin_enter` и защиту arrival-trigger от немедленного цикла;
- [x] четыре authored двери `fan_town` имеют Godot-контейнеры и проходят headless round-trip: inn/mage/smith/house → `start` → соответствующий внешний region; первый импорт interior mesh не зависит от editor filesystem rescan;
- [x] вручную подтверждён `F` у `ft_mage_door`: подсказка появляется и переход в `fan_town_mage` выполняется после перезапуска DEBUG;
- [ ] вручную пройти тот же маршрут через F у двери и через trigger выхода;
- [x] talk/shop: F открывает существующие `scriptId/shopId`, resolver сохраняет приоритет `scripts/` → `scenes/`, choice управляется W/S + F (или цифрой), `shop_intro` продолжается в реальный каталог; overlay блокирует ходьбу и освобождает её при закрытии;
- [x] buy/sell + inventory/stock persistence реализованы отдельным gameplay-state срезом: `EmberEconomy` повторяет JOI `coin`/price/stock/stack/unsellable contract, `EmberExploreState` является единственным владельцем состояния, successful transaction пишет Ember save v1 в `user://ember-save-v1/ember_p1/<slot>.json`; UI только отображает/маршрутизирует команды;
- [x] headless проверяет стартовые 20 coin, покупку/продажу, broke/unsellable/out-of-stock, возврат finite stock, сохранение sold-out `0` и round-trip inventory + per-shop stock;
- [x] shop UX вручную принят пользователем в реальном Godot: купить/продать, выбор товара и persistence работают;
- [x] смена карты передаёт точный region, а не всегда использует первый `player_start`; отсутствующая target-сцена не оставляет зависший pending transition;
- [ ] interior/cutaway в объёме вертикального среза: Godot-native roof spike автоматически закрыт только для `agent_sandbox`, ручная визуальная приёмка и authoring gate ещё открыты. Импорт читает существующие `ground_zN + interiorVolumes`, создаёт отдельную секцию крыши, `Area3D` управляет штатной `GeometryInstance3D.transparency`, а структурная тень крыши намеренно остаётся стабильной при изменении только camera visibility. Production-карты пока выключены; стены, scene ownership после reimport и редактирование ролей в Inspector не объявлены решёнными;
- [ ] несколько reload и mount/unmount без оставшихся listener/GPU-ресурсов;
- [x] сохранение/загрузка минимального gameplay state: save v1 содержит inventory/equipment/openedChests/shopStock/flags и текущий map/tile/world position; запуск проекта восстанавливает сохранённую карту и точную позицию, F6 сохраняет явно выбранную сцену, arrival guard защищает spawn внутри trigger/teleport, сундук показывает authored `closedModelId/openModelId`, выдаёт `lootIds` один раз, typed flags и opened chest переживают restart;
- [x] отдельный inventory/equipment экран читает тот же `EmberExploreState`: I открыть/закрыть, A/D переключить equipment/bag, W/S выбрать, F использовать/надеть/снять; слоты JRPG/arena разделены, статы 4/0 + authored bonuses пересчитываются, успешная mutation сохраняется в save v1;
- [x] HP/consumables используют существующие stage/items/save поля: `playerHp`, `hpRestore`, `hp/maxHp`; входящий урон учитывает общий `def`, лечение ограничивается максимумом, предмет списывается тем же inventory owner; `agent_sandbox` включает H как data-driven probe на 30 урона, production-сцены оставляют его выключенным;
- [x] HP/consumables UX вручную принят пользователем: HUD, H damage probe, лечение через F и списание stack работают в реальном Godot;
- [x] defeat/respawn продолжает тот же health owner без новой save schema: нулевое HP блокирует explore/UI, R возвращает в существующий `player_start`, восстанавливает `maxHp` и сохраняет новую позицию, не сбрасывая inventory/equipment/flags/chests/shop stock; `test_defeat_respawn.gd` закрепляет pure и live `agent_sandbox` contract; пользователь вручную подтвердил полный цикл H → поражение → R;
- [x] ограниченный action-list executor использует прежний resolver и выполняет все семь `talk/give_item/set_flag/wait/open_shop/change_map/run_script`; script-only region входит в общий F-путь, диалог/магазин/timed wait приостанавливают очередь, `give_item` показывает reward-карточку, map transition сохраняет target region, mutations проходят через `EmberExploreState`, `sandbox_chain` закреплён headless;
- [x] action-list UX вручную принят пользователем: marker открывает диалог/ветки, `give_item` показывает золотую карточку с приростом и итогом, F продолжает к реальной timed pause, которая завершается автоматически и не проматывается F; монета добавляется в общий inventory;
- [x] quest-marker runtime использует существующие `questStatus/iconId/scriptId/triggerId`: authored `available/active/done` видны как оригинальные SVG `янтарный ! / голубой компас / мятная ✓`, `scriptId` читает typed flag из общего save-state, а связанный `triggerId` запускает прежний action-list без второго quest manager;
- [x] headless `test_quest_state.gd` проверяет pure status/icon projection, Sprite3D assets, размер/центр/mesh-anchor, реальные маркеры `agent_sandbox`, F-binding только у исполнимого события и native giver: `sandbox_notice_read=true` скрывает обработанный старт, а не показывает ложный quest-done;
- [ ] вручную подтвердить quest-state: три разные формы над табличками, F у янтарной таблички, после завершения диалога `!` меняется на мятную галочку; отойти на 140/190/300 units и проверить shrink/fade/hide, затем F5 restart;
- [ ] ручной gate v1.53: выбрать display-only quest-marker, открыть `Изменить`, выбрать `Задание`; затем `Цель / событие` → нужную цель → `Сохранить цепочку`. После Ctrl+S/reopen Inspector показывает отдельно `Задание`, derived `Флаг статуса` и `Сценарий`; F пишет completion flag, зависимая цель разблокируется, marker меняется по общему status. Ctrl+Z/Redo атомарно убирает/возвращает и chain, и quest binding;

Сравнивается поведение, а не внутренняя архитектура Three и Godot. Новые поля проходят всю цепочку schema → import/validation → editor → runtime → serialization → tests.

### Правило Godot-native замены

Three-реализация не является спецификацией для порта. Из неё сохраняются только пользовательский результат, художественное намерение, данные и измеримые ограничения. Перед переносом каждой renderer/editor/physics-функции сначала исследуются штатные узлы, ресурсы, import hooks, visibility/shader-механизмы и поддерживаемые Godot-плагины. Если готового механизма недостаточно, строится одна небольшая Godot-система вокруг выбранного native owner, а не переносится прежний набор обходов и специальных веток.

Для крыш/cutaway сначала отдельно фиксируется желаемый эффект: при входе игрока интерьер читается, крыша и мешающие обзору части корректно скрываются или плавно растворяются, тени не расходятся с видимым кадром, а автор видит и настраивает роли в Godot. Исследовательский spike должен сравнить как минимум:

- отдельные scene-owned узлы/секции крыши и стен с native visibility;
- material/shader fade или dither на отдельных поверхностях без remesh мира;
- отдельную interior-сцену как осознанный вариант без cutaway.

Текущий spike выбрал первый вариант для проверки: существующие `ground_zN + interiorVolumes` импортируются в отдельные runtime-секции крыши, каждая секция владеет своим `Area3D`, mesh и fade. Перестроения мира и per-frame обхода нет. `GeometryInstance3D.transparency` используется как штатный Forward+ fade; `cast_shadow` остаётся включённым, поэтому растворение крыши не перестраивает световой рисунок и не вызывает заметный скачок освещения. F7 в песочнице переключает тот же owner вручную, чтобы эффект и тени можно было осмотреть без входа в мгновенный map-trigger. `test_native_cutaway.gd` закрепляет геометрию, Area3D/fade/shadow continuity, F7-route и opt-in одной сцены.

Это ещё не production-решение. Выход spike: ручная визуальная приёмка крыши и обеих теней, F3 без заметного ухудшения, затем отдельное решение об authoring: сохранять ли производную секцию при импорте, делать ли её scene-owned и как показывать roof/wall roles в Inspector. До этого запрещено включать cutaway на `fan_town`, переносить Three cell tags по умолчанию, скрывать целиком дом, делать per-frame обход сцены/remesh или заводить второй map schema.

### Authoring gate: Object Inspector

Перед следующим gameplay-state срезом зафиксирован proposal [`docs/EMBER_OBJECT_INSPECTOR_DESIGN.md`](docs/EMBER_OBJECT_INSPECTOR_DESIGN.md). Он продолжает Wave 3, а не создаёт второй editor: один `EditorInspectorPlugin` показывает asset/scene/derived компоненты, effective light и content references; первой mutation-волной разрешён только существующий scene-owned `Interact` с Undo/Redo и локальным `.tscn` diff.

- [x] I0: pure object snapshot + reference diagnostics на prop/lantern/door/talk/shop;
- [x] I1/I1.5: read-only Inspector MVP, compact collapsible cards, отдельный door destination, русские source badges, light/effective/source visibility, `Все | Ошибки`, symmetric editor lifecycle и 20 panel lifecycles; migration workflow вынесен из правого слота в bottom panel, чтобы не сжимать native Inspector;
- [x] I2 automated contract: add/edit/remove `Interact`, kind-dependent catalogs, shared import/editor shape helper, Undo/Redo, save/reopen и local diff без записи JOI JSON;
- [x] I2 UI вручную принят пользователем в реальном Godot Inspector; add/edit/remove форма и каталоги работают;
- [x] I2.5 automated: `+ Триггер с цепочкой` создаёт object-bound `Interact + Shape` и canonical action document одной Undo/Redo operation; карточный editor поддерживает все семь canonical шагов `talk/give_item/set_flag/wait/open_shop/change_map/run_script`, runtime читает результат прежним executor; новые документы теперь Godot-native `.tres`, legacy JSON доступен до явной I2.30 миграции;
- [x] chain removal UX разделён явно: несохранённая форма имеет `Отменить`, сохранённая — `Удалить цепочку`; последняя удаляет canonical document + `script_id`, но сохраняет сам Interact/магазин/Shape, а Undo/Redo восстанавливает owner, документ и binding;
- [x] typed flag UX объясняет ключ в save и потребителя; bool выбирается как `Да/Нет` без ручного ввода `true`, text/number переключают подходящее guided-поле, а сериализация остаётся прежней `bool|string|number`;
- [x] I2.5 runtime UX вручную: созданная цепочка выполняет dialogue → reward → timed pause → следующий шаг; reward и пауза визуально различимы. Отдельно остаётся проверить Undo/Redo и reopen авторского JSON на произвольной safe duplicate;
- [x] I2.6 automated: нижний workflow создаёт самостоятельную scene-owned `EmberInteract + BoxShape3D` в `root/AuthoredTriggers`, а Inspector редактирует её bounds, ссылки и ту же canonical action-chain; зона переживает очистку generated `Map`, save/reopen и Undo/Redo, а runtime считает F-дистанцию до поверхности объёма, не до центра;
- [x] I2.6 вручную: создана самостоятельная зона в пустом месте, cyan Box bounds и canonical цепочка работают в editor/play;
- [x] I2.7 automated: scene-owned launch rules используют typed `EmberExploreState.flags` для primary/fallback route; one-shot пишет устойчивый completion-флаг только после успешного окончания primary, не расходуется fallback/отменой и реактивно снимает F-группу; UI, Undo/Redo и save/reopen используют прежний `EmberInteract`;
- [ ] I2.7 вручную: на самостоятельной зоне проверить скрытый F без условия, запасную цепочку, появление основной после флага и исчезновение после успешного one-shot;
- [x] I2.8 automated: `activation_mode=press|enter` сериализуется на том же Interact; enter исключает F-группу, включает только player collision mask и вызывает публичный `EmberPlayer.activate_interact`, поэтому conditions/fallback/one-shot и sequencer едины; возврат на press восстанавливает прежний F-path;
- [ ] I2.8 вручную: переключить standalone-зону на `При входе`, проверить отсутствие F-подсказки, один запуск на пересечение и повтор после выхода/входа;
- [x] I2.9 automated: шаг `talk` открывает карточный редактор прежнего `content/ember/scenes/<id>.json`; линейные реплики и простой сходящийся выбор с одним typed флагом на вариант проходят projection → edit → validation → Undo/Redo → runtime. Сложные stage/splash/cycle/disconnected сцены явно read-only и не имеют кнопки сохранения;
- [ ] I2.9 вручную: создать новый диалог из talk-шага, добавить реплику и выбор из двух ответов, сохранить два native Resources и цепочку, затем проверить обе ветки в Play и Ctrl+Z/Ctrl+Shift+Z;
- [x] I2.10 automated: отдельная main-screen вкладка `Ember Graph` строит native GraphNodes и connections для action-list и полного dialogue graph, включает zoom/minimap/arrange и переиспользует прежние safe editors/writers; выбор ноды фильтрует правую карточку, reply фокусирует parent choice, talk/run_script переходят к связанному графу; standalone action JSON save проходит Undo/Redo;
- [ ] I2.10 вручную: открыть верхнюю вкладку `Ember Graph`, переключить action/dialogue, проверить pan/zoom/minimap/arrange и сохранение простой правки справа. Сложная VN-сцена должна показывать весь граф, но оставаться read-only;
- [x] I2.11 automated: action canvas создаёт/удаляет ноды и трактует новый провод как перестановку target сразу после source; canonical связный массив остаётся единственным schema, локальные ↶/↷ восстанавливают structural draft, card fields синхронизируются до операции, а JSON пишет только прежний Save + Editor Undo/Redo;
- [ ] I2.11 вручную: на safe chain добавить wait-ноду, заполнить справа, перетащить её проводом в середину, удалить/вернуть ↶/↷, сохранить и проверить runtime order; dialogue wires остаются read-only до именованных choice ports;
- [x] I2.12 automated: dialogue choice отображает отдельный подписанный output на каждый вариант; connection/disconnection меняет только соответствующий `options[].next` в локальном черновике, ↶/↷ восстанавливают связи, dangling/unreachable ноды блокируют save, complex VN extras сохраняются, canonical graph JSON проходит Editor Undo/Redo;
- [ ] I2.12 вручную: открыть `sandbox_branch`, поменять местами цели двух ответов проводами, проверить красную диагностику промежуточной недостижимой ветки, вернуть валидный граф, сохранить и пройти оба ответа в Play;
- [x] I2.13 automated: GraphEdit zoom/scroll и node offsets переживают structural/property rebuild; dialogue offsets попадают в существующий `editorLayout` при graph save, action layout остаётся session-only view и не создаёт поля gameplay JSON;
- [ ] I2.13 вручную: отдалить/сдвинуть canvas, передвинуть две dialogue-ноды, изменить связь и сохранить; камера не должна прыгнуть, после reopen позиции нод должны совпасть;
- [x] I2.14 automated: dialogue toolbar создаёт canonical `dialogue/choice/set_flag/end` с уникальным ID и layout в центре viewport, Delete удаляет выбранные steps/layout и очищает входящие next, Set Start меняет прежний `startStepId`; invalid intermediate draft блокирует save, локальный Undo возвращает структуру и layout;
- [ ] I2.14 вручную: добавить реплику, связать `agent_r → новая реплика → end`, назначить её стартом и отменить, затем удалить/отменить удаление; сохранить можно только после восстановления всех достижимых веток;
- [x] I2.15 automated: common dialogue properties и choice labels редактируются прямо в `GraphNode`, одна focus-сессия создаёт одну запись локальной history; Shift-selection собирается в сохраняемый `editorGroups`/native `GraphFrame`, rename/ungroup/Undo и JSON round-trip сохраняют membership, runtime validation игнорирует визуальную оболочку;
- [ ] I2.15 вручную: изменить текст и вариант ответа прямо в нодах; Shift+кликом выбрать две ноды, назвать группу и нажать `Группа`; переместить frame, переименовать, сохранить/reopen, затем `Разгруппировать` и ↶ — поля, camera, node layout и membership не должны сброситься;
- [x] I2.16 automated: native drop-on-frame добавляет или переносит membership в том же `editorGroups`; titlebar `Свернуть/Развернуть` хранит editor-only `collapsed`, скрывает/возвращает members и входит в local Undo; selected-node detach не удаляет frame или соседние ноды;
- [ ] I2.16 вручную: бросить свободную ноду на раскрытый frame, свернуть/переместить/развернуть его, сохранить и открыть заново; затем выбрать одну вложенную ноду и `Убрать из группы`, а сам frame — `Удалить группу`; связи и сами dialogue-ноды должны сохраниться;
- [x] I2.17 automated: collapsed group рендерится compact `GraphNode` proxy без member port-cache; external incoming/outgoing edges перенаправляются на его boundary-порты, internal edges скрыты, expand восстанавливает canonical wiring; тест требует оба proxy-порта и видимые связи с двух сторон;
- [ ] I2.17 вручную: свернуть группу в середине цепи — провод слева должен прийти в proxy, справа продолжиться к следующей ноде; внутри proxy видны число нод/входов/выходов, ошибок `graph_node.cpp ... port_cache` нет;
- [x] I2.18 automated: `Ctrl+D`/`Дубликат` копирует выбранные action steps одним блоком; dialogue clone получает уникальные IDs, +60/+60 layout, remapped internal `next/options[].next`, сохранённые external continuations и одно Undo; новая ветка остаётся выделенной;
- [ ] I2.18 вручную: Shift+кликом выбрать choice и две его реплики, нажать Ctrl+D; копия появляется рядом и остаётся выделенной, её ветви ведут к копиям реплик, но вход с исходной ноды не создаётся автоматически; подключить вход и проверить save/reopen;
- [x] I2.19 automated: ПКМ открывает searchable palette, поиск выбирает canonical dialogue/action type, созданная нода получает координату canvas; output-to-empty и input-to-empty создают и сразу подключают совместимую ноду, action step вставляется в canonical порядок;
- [ ] I2.19 вручную: ПКМ по пустому canvas, найти `Флаг` и создать ноду; затем протянуть выход существующей реплики в пустоту и выбрать `Конец`, а вход другой ноды — в пустоту и выбрать `Изменить флаг`; проверить провода, ↶/↷, Save и reopen. В action-chain протянуть выход шага в пустоту, выбрать `Пауза` и проверить runtime order;
- [x] I2.20 automated: native Ctrl+C/X/V и меню `Буфер` копируют ordered action block и dialogue branch; Cut/Paste дают по одной local-history записи, dialogue paste создаёт уникальные IDs, remap внутренних edges и очищает внешнюю цель, отсутствующую в destination resource;
- [ ] I2.20 вручную: выделить Shift+кликом ветку dialogue, Ctrl+C → открыть другой dialogue → Ctrl+V; копия появляется у курсора с прежней внутренней раскладкой и новыми ID, отсутствующие внешние переходы подсвечиваются до переподключения. Проверить Ctrl+X, ↶, повторный Ctrl+V, Save/reopen; затем повторить ordered block в action-chain;
- [x] I2.20 hotfix automated: Ctrl+Z/Ctrl+Shift+Z используют local draft history; adaptive flow-toolbar не расширяет main screen, а отдельная status-строка остаётся внутри ширины workspace и показывает validation целиком;
- [ ] I2.20 hotfix вручную: вставить ветку, Ctrl+Z должен убрать её, Ctrl+Shift+Z вернуть; красная ошибка недостижимой вставленной ноды видна целиком под toolbar и исчезает после подключения входа;
- [x] Editor stop-line: fast authoring → node-level diagnostics/unsaved guard → минимальные VN properties первого сюжетного эпизода закрыты; дальнейшая общая полировка остановлена, следующий продуктовый срез — quests/combat;
- [x] I2.21 automated: action/dialogue validation возвращает structured step/port diagnostics без второго набора правил; GraphNode показывает badge и сообщение, `К первой ошибке` фокусирует offending node/proxy, repaired graph очищает badge; dirty draft блокирует resource/kind/reload/link navigation до discard/cancel;
- [ ] I2.21 вручную: отключить один choice-output — ошибка видна на исходной ноде и указывает нужный ответ; `К первой ошибке` центрирует её, Undo убирает badge. Затем изменить текст/структуру и выбрать другой ресурс: `Остаться` сохраняет draft и selector, повторный переход + `Отбросить и перейти` открывает новый JSON;
- [x] I2.22 automated: canonical `defaultBgArtId/bgArtId/portraitSide/actors[0]` редактируются в VN scene/node UI; actor edit сохраняет неизвестные поля и остальных actors, splash создаётся из toolbar/palette, local Undo восстанавливает staged actor; runtime session lossless проецирует visual state и default background fallback;
- [ ] I2.22 вручную: открыть `hu_tao_clear_demo`, изменить Default BG, сторону портрета и X/Scale в `Постановка`, Undo/Redo, Save/reopen; добавить `Заставка`, подключить её и убедиться, что `artId/caption` сохранились. Условий выбора в этом срезе нет: первый эпизод их не использует, а отдельного runtime/schema contract ещё нет;
- [x] I2.23 automated (явный пользовательский запрос после stop-line): `▶ Превью сцены` читает unsaved canonical draft, фокусирует выбранную ноду, проходит dialogue/choice/back, показывает text-only `talk/shop_intro`; общий `EmberVnSceneState` совпадает с JOI fallback actor/background/incoming-choice правилами, resolver читает прежние arts/portraits registries;
- [ ] I2.23 вручную: перезапустить редактор, открыть `Ember Graph → Диалоги → hu_tao_clear_demo`, нажать `▶ Превью сцены`; выбрать `intro`, менять Реплику/X/Scale и увидеть live update без Save. Пройти `Далее`, оба ответа, `Назад`, `С начала`; затем выбрать `sandbox_branch` и проверить text-only preview. Текущий UUID-фон `49bd31e4-…` зарегистрирован, но его JPG отсутствует в pack — ожидается warning; `hu_tao_clear_placeholder` проверяет рабочую загрузку фона;
- [x] I2.24 automated: background/splash picker читает только non-portrait arts registry entries и сохраняет canonical ID; speaker picker строится из существующих portrait registries, emotion picker зависит от speaker; identity edit синхронизирует dialogue и actors[0], advanced actor keys сохраняются, missing current IDs остаются warning item;
- [ ] I2.24 вручную: в `hu_tao_clear_demo` раскрыть Default BG/Фон — увидеть две CG-записи с миниатюрой у существующего placeholder и `⚠` у отсутствующего UUID JPG; в `intro` выбрать персонажа `hu_tao`, затем разные bunny-эмоции и увидеть смену портрета live. Раскрыть `Постановка` и убедиться, что там те же dropdown, а Undo/Redo возвращает выбор;
- [x] I2.25 crash regression: повреждённый `hu_tao_clear_placeholder.svg` (control bytes/invalid UTF-8) заменён валидным SVG после воспроизводимого Godot 4.7.2 native `0xc0000005`; picker и live preview разделяют один decoded-image cache, preview использует display-sized textures, динамические thumbnails не хранятся в `OptionButton/PopupMenu`; canonical metadata и Undo/Redo не меняются;
- [ ] I2.25 вручную: трижды открыть `Ember Graph → Диалоги`, переключить `hu_tao_clear_demo`/другой dialogue и раскрыть списки фона, персонажа и эмоции — редактор не закрывается, выбранные изображения видны слева от списка;
- [ ] вручную пройти door/talk/shop runtime-маршруты в `agent_sandbox` после authored изменений;
- [ ] новые light/collider modifiers не добавлять до отдельного vertical ownership/schema решения.

### Ручная приёмка I2.5 — триггер с цепочкой

1. Открыть `scenes/agent_sandbox.tscn`, выбрать декоративный `EmberVoxelProp` без Interact или сделать `Дублировать безопасно · +X`.
2. В `EMBER OBJECT` нажать `+ Триггер с цепочкой`. Оставить предложенный уникальный id и дать понятное название.
3. Добавить по порядку: `Диалог → sandbox_notice_talk`, `Выдать предмет → coin ×1`, `Пауза → 1.5 с`, `Изменить флаг → inspector_chain_done = true`, `Открыть магазин → village_kiosk`. Стрелками поменять порядок и вернуть его обратно; удалить/добавить тестовый шаг.
4. При необходимости добавить последним `Сменить карту → agent_sandbox_interior : start`. Редактор должен отвергать любые шаги после смены карты и обновлять список точек входа при выборе другой карты.
5. Нажать `Сохранить цепочку`, затем Ctrl+S. В карточке Interact должны появиться kind `trigger` и назначенный script id; в `content/ember/scripts/` появляется один JSON.
6. Запустить сцену, подойти к объекту и нажать F: диалог завершается, видна награда и пауза, магазин открывается, после Esc цепочка продолжается. Если добавлена смена карты, она переносит в выбранную точку входа.
7. Остановить Play. В сохранённой цепочке нажать `Удалить цепочку`: JSON и привязка исчезают, но Interact и магазин остаются. Ctrl+Z восстанавливает цепочку, Ctrl+Shift+Z снова удаляет. У новой несохранённой формы `Отменить` просто закрывает её без изменения сцены или файлов.
8. Для проверки общего создания Ctrl+Z после исходного `+ Триггер с цепочкой` по-прежнему удаляет новый Interact и новый JSON вместе; Ctrl+Shift+Z возвращает оба. Сохранить, закрыть и снова открыть сцену — связь остаётся рабочей.

### Ручная приёмка I2.6 — самостоятельная F-зона

1. Открыть `scenes/agent_sandbox.tscn`, выбрать ближайший prop как позиционный ориентир и в нижней вкладке **Ember Migration** нажать `+ Зона-триггер с цепочкой`.
2. В Scene появляется `AuthoredTriggers/trigger_N`, а во viewport — компактный cyan Box только при выборе зоны. Переместить его штатным gizmo в свободное место.
3. В `EMBER OBJECT → Объём триггера` открыть размер, задать X=48, Высота=10, Z=32 и сохранить. Рамка должна обновиться без запуска игры.
4. В карточке `F Взаимодействие` открыть цепочку, добавить короткий диалог и награду, сохранить цепочку и Ctrl+S.
5. В Play войти в объём с двух противоположных краёв: подсказка F появляется у границы, не требует подходить к центру, и запускает ту же очередь действий.
6. После Play проверить Ctrl+Z/Ctrl+Shift+Z для размера и удаления зоны. Закрыть/открыть сцену и выполнить полный reimport карты: `AuthoredTriggers` и его связь с JSON остаются на месте.

### Ручная приёмка I2.7 — условие и одноразовый запуск

1. Выбрать тестовую самостоятельную зону и открыть `F Взаимодействие → Изменить → ПРАВИЛА ЗАПУСКА`.
2. В `Если флаг` ввести `test_gate_open`, оставить `Ожидать Да`. В `Иначе` выбрать короткую цепочку-реплику. Включить `Только 1 раз`: поле выполнения должно автоматически получить устойчивое имя вида `<map>_<trigger>_used`.
3. Сохранить Interact и Ctrl+S. В свернутой карточке должны быть видны условие, resolved запасная цепочка и строка one-shot; отсутствующая ссылка выделяется диагностикой.
4. Запустить сцену без `test_gate_open`: F доступна и выполняет только запасную цепочку. После этого основная зона остаётся доступной — completion-флаг не записан.
5. Любой тестовой цепочкой записать `test_gate_open = Да` и снова войти в зону. Теперь выполняется основная цепочка. Закрыть её Esc до конца: запуск остаётся доступен.
6. Завершить основную цепочку: записывается `<map>_<trigger>_used = Да`, F-подсказка у этой зоны исчезает немедленно и после перезапуска остаётся скрытой.
7. В editor изменить правила и проверить Ctrl+Z/Ctrl+Shift+Z, затем закрыть/открыть сцену: оба bool и все три ключа/ссылки сохраняются без записи правил в action JSON.

### Ручная приёмка I2.8 — автоматическая зона

1. На отдельной самостоятельной зоне открыть `Изменить → ПРАВИЛА ЗАПУСКА` и выбрать `Активация: При входе`. Для первого прогона оставить условие пустым и one-shot выключенным.
2. В Play подойти к границе: F-подсказки у зоны нет. Пересечь cyan bounds — основная цепочка запускается автоматически через тот же overlay.
3. Завершить цепочку, не выходя из зоны: повторного запуска нет. Выйти полностью и войти снова — цепочка запускается ещё раз.
4. Включить условие/fallback: на входе должна выбираться та же ветка, что и в F-режиме. Включить one-shot: успешный primary гасит следующие входы, fallback и Esc — нет.
5. Вернуть `Клавиша F`, сохранить: автозапуск исчезает, подсказка и ручное действие возвращаются. Проверить Undo/Redo и reopen сцены.

### Ручная приёмка I2.9 — карточный диалог

1. Открыть любую цепочку, добавить шаг `Диалог` и нажать `Создать / редактировать диалог`. Оставить предложенный уникальный ID, задать название.
2. Добавить обычную реплику. Затем добавить карточку `Выбор с ответами`, заполнить вопрос, два текста выбора и две ответные реплики.
3. На одном ответе включить `После выбора изменить флаг`, задать имя и проверить типы `Да/Нет`, `Текст` или `Число`.
4. Нажать `Сохранить диалог`, затем `Сохранить цепочку` и Ctrl+S. Повторно открыть форму: карточки и выбранный dialogue ID должны сохраниться.
5. В Play пройти обе ветки. После выбора должна показаться соответствующая ответная реплика, затем обе ветки сходятся в следующую карточку.
6. Остановить Play. Сохранение цепочки и диалога — две явные операции: первый Ctrl+Z отменяет последнюю из них, второй отменяет предыдущую и удаляет новый `scenes/<id>.json`; два Ctrl+Shift+Z возвращают обе. Сложную существующую VN-сцену проверить отдельно: вместо save должна быть причина read-only.

### Ручная приёмка I2.10 — Ember Graph

1. Перезапустить editor и открыть верхнюю вкладку `Ember Graph` рядом с 2D/3D/Скрипт.
2. Выбрать `Цепочки действий`, затем `sandbox_chain`: все шаги должны быть линейными нодами со связями. Проверить pan, zoom, minimap и `Упорядочить`.
3. Выбрать `Диалоги → sandbox_branch`: выбор должен расходиться в две ответные реплики и сходиться в end.
4. Кликнуть вторую ноду: справа должна остаться только её карточка; `Показать все` возвращает список. На talk-ноде открыть связанный диалог в той же вкладке.
5. Изменить безопасное поле в правой карточной форме и сохранить. Граф перечитывает canonical JSON; Ctrl+Z/Ctrl+Shift+Z восстанавливают файл.
6. Открыть `hu_tao_clear_demo`: весь сложный граф виден слева, справа показана причина read-only и отсутствует destructive save.

### Ручная приёмка I2.11 — action graph mutation

1. В `Ember Graph → Цепочки действий` выбрать безопасную копию цепочки.
2. В toolbar выбрать `Пауза`, нажать `+ Нода`: новая нода появляется в конце и автоматически выбирается; справа задать ненулевые секунды.
3. Протянуть провод от первой ноды к новой: новая нода перемещается сразу после первой, весь список остаётся связным. Отдельное удаление провода не разрывает цепочку.
4. Нажать Delete или `Удалить`, затем `↶` и `↷`; нода должна исчезать и возвращаться без записи файла.
5. Нажать `Сохранить цепочку`, проверить Play order. После остановки Ctrl+Z/Ctrl+Shift+Z отменяют/возвращают canonical JSON write.

Пока это object-bound trigger. Standalone volume trigger, визуальное изменение bounds в viewport и полноценный dialogue graph проходят отдельными editor-first срезами.

### I2.26 — native библиотека VN-фонов

1. Открыть `Ember Graph → Диалоги`: длинное имя выбранного `Default BG` не должно расширять правую колонку; полное имя, ID и путь доступны в tooltip.
2. Нажать `+ Фон`, выбрать PNG/JPG/WebP/SVG вне проекта. Редактор копирует его в `res://assets/vn_backgrounds/`, создаёт `res://content/vn_backgrounds/<id>.tres`, сразу выбирает фон и обновляет live preview.
3. Проверить `↶/↷`: выбор нового ID отменяется и возвращается как одна draft-операция. Сам импортированный library asset не удаляется через Undo, чтобы отмена диалога не уничтожала общий ресурс.
4. Нажать `Папка`: открывается каталог изображений. После закрытия/reopen Godot новый фон остаётся в picker и preview.
5. Сравнить JOI `content/ember/arts/registry.json` до/после: native импорт не должен его менять. Старые записи продолжают читаться как `Legacy JSON · только чтение`; при совпадении ID `.tres` имеет приоритет.

Решение принято по прямому запросу владельца проекта: новый authoring owner фонов — Godot Resource, а не исходный JSON. Dialogue documents пока не мигрируются вместе с ним, чтобы не менять одновременно runtime, сериализацию и editor history.

### I2.27 — единый наследуемый фон сцены

1. Выбрать `Фон сцены` один раз. Ноды без собственного override показывают `↳ Фон сцены · <имя>` и ту же миниатюру; live preview сразу обновляется без Save.
2. На старой сцене нажать `Сделать общим для всей сцены · убрать overrides: N`. У dialogue/choice удаляются только `bgArtId`; splash art, actors, edges и прочие неизвестные поля не меняются.
3. Нажать `↶`, затем `↷`: все индивидуальные фоны возвращаются и снова убираются одной draft-операцией.
4. Сохранить граф и открыть заново. В JSON остаётся один `defaultBgArtId`, а ноды наследуют его без копий. Нода с намеренно выбранным другим фоном продолжает работать как локальное исключение.
5. Проверить preview/runtime для старого `bgArtId: ""`: эффективным должен стать `defaultBgArtId`, а не пустой кадр.

### I2.28 — безопасные VN-слои и native portraits

1. Открыть live preview сцены с крупным персонажем: фон остаётся сзади, персонаж может заходить за нижнюю панель, но его изображение никогда не перекрывает имя, реплику или варианты выбора. Поле actor `z` меняет порядок только между персонажами.
2. В dialogue-ноде выбрать персонажа и нажать `+ Арт` рядом с эмоцией. Выбрать PNG/JPG/WebP/SVG: файл копируется в `res://assets/vn_portraits/<speaker>/`, `.tres` создаётся в `res://content/vn_portraits/`, новая эмоция выбирается сразу.
3. Проверить `↶/↷`: назначение новой эмоции отменяется одной draft-операцией, но общий library asset не удаляется.
4. Закрыть/reopen Godot: native speaker/expression остаётся в picker и preview. Legacy `portraits/<speaker>/registry.json` не изменяется; совпадающий native `speaker/key` имеет приоритет.

### I2.29 — Godot-native документы диалогов

1. Открыть `Ember Graph → Диалоги` и выбрать legacy-сцену. Справа виден owner `Legacy JSON`, исходный путь и активная кнопка `Перенести в .tres`.
2. Нажать миграцию: появляется `res://content/dialogues/<id>.tres`, owner меняется на `Godot Resource`, граф/preview не меняются. Исходный `content/ember/scenes/<id>.json` остаётся побайтово прежним.
3. Изменить реплику или фон, сохранить граф, закрыть/reopen Godot и пройти диалог в Play. Editor и runtime должны читать сохранённый `.tres`, а не legacy backup.
4. Сразу после миграции нажать Editor Ctrl+Z: `.tres` исчезает, owner снова `Legacy JSON`, содержимое графа сохраняется. Ctrl+Shift+Z повторяет миграцию.
5. Создать новый диалог через authoring UI: он сразу появляется как `.tres`, без нового файла в JOI `scenes/`.

Автоматический `test_vn_dialogue_resource.gd` закрепляет native-first catalog, runtime parity, неизменность legacy JSON и точное Undo/Redo состояния owner. Массовая конверсия намеренно отсутствует: сцены мигрируются по одной после визуальной проверки.

### I2.30 — Godot-native цепочки действий

1. Открыть `Ember Graph → Цепочки действий` и выбрать небольшую legacy-цепочку, например `sandbox_chain`. Справа видны owner `Legacy JSON`, исходный путь и кнопка `Перенести в .tres`.
2. Нажать миграцию: появляется `res://content/action_scripts/<id>.tres`, owner меняется на `Godot Resource`, порядок и значения нод не меняются. Исходный `content/ember/scripts/<id>.json` остаётся побайтово прежним.
3. Изменить безопасный шаг, сохранить, закрыть/reopen Godot и выполнить цепочку в Play. Picker, validation и executor должны читать `.tres`, а не stale legacy backup.
4. Сразу после миграции нажать Editor Ctrl+Z: `.tres` исчезает и owner снова становится `Legacy JSON`; Ctrl+Shift+Z повторяет перенос. Если после миграции было сохранение, первый Undo отменяет правку, второй — сам перенос.
5. Создать новую цепочку через Inspector или Ember Graph: документ сразу появляется как `.tres`. `Удалить цепочку` удаляет документ и binding, но сохраняет Interact; Undo восстанавливает оба.

Автоматические `test_action_resource.gd` и `test_action_chain_authoring.gd` закрепляют native-first executor, неизменность legacy bytes, save/remove/binding и полный owner-aware Undo/Redo. Массовой конверсии нет.

### I2.31 — Godot-native магазины

1. В `Ember Graph → Цепочки действий` открыть цепочку с шагом `Открыть магазин` (в pack это `sbx_planter_nw_actions`) и нажать `Создать / редактировать магазин`.
2. Для `village_kiosk` сначала виден owner `Legacy JSON`: название, товары и цены доступны для просмотра, Save заблокирован, активна только явная кнопка `Перенести в .tres`.
3. После миграции появляется `res://content/shops/village_kiosk.tres`, owner меняется на `Godot Resource`. Изменить безопасную цену/stock, сохранить, закрыть/reopen Godot и открыть магазин в Play: runtime должен показать новое значение из Resource.
4. Нажать Editor Ctrl+Z после сохранения — возвращается прежняя цена; ещё один Undo отменяет миграцию и снова включает legacy owner. Ctrl+Shift+Z повторяет оба действия. Общий `content/ember/shops/catalog.json` не меняется.
5. В новом шаге `Открыть магазин` выбрать пустое значение, открыть редактор, задать новый ID, название и хотя бы один товар. Он сразу создаётся как отдельный `.tres` и появляется в общем picker без записи в legacy JSON.

Автоматический `test_shop_resource.gd` закрепляет read-only legacy gate, per-shop Resource, runtime/economy parity, embedded editor и owner-aware Undo/Redo. `test_shop_persistence.gd` продолжает проверять buy/sell и save v1 `shopStock`; схема сохранений не менялась.

### I2.32 — Godot-native предметы

1. Открыть native-магазин по I2.31, раскрыть товар и нажать `Предмет…`. Для legacy-предмета видны все текущие поля, owner `Legacy JSON`, заблокированный Save и кнопка `Перенести в .tres`.
2. Перенести безопасный предмет, например `herb`: появляется `res://content/items/herb.tres`, owner становится `Godot Resource`. Общий `content/ember/items/catalog.json`, включая пиксельные icons, не меняется.
3. Изменить название, `hpRestore` или `sellPrice`, сохранить и закрыть/reopen Godot. Inventory, использование consumable и продажа должны читать новые значения из `.tres`.
4. Ctrl+Z сначала возвращает предыдущие характеристики, вторым шагом отменяет миграцию и удаляет native override; Ctrl+Shift+Z повторяет оба действия.
5. В новой строке магазина оставить предмет пустым, нажать `Предмет…`, задать новый ID, название, тип и icon ID. После Save предмет сразу появляется в picker; затем сохранить сам магазин. Новый item создаётся сразу как `.tres`.

Автоматический `test_item_resource.gd` закрепляет read-only gate, embedded editor, runtime inventory/consumable/economy parity, legacy-byte safety и owner-aware Undo/Redo. Save v1 продолжает хранить только ID/count/equipment и не меняется.

### I2.33 — Visual Library для canonical ID

1. Открыть native item editor: рядом с `Иконка` видно selected preview. Нажать `Библиотека…` — появляется tiled `ItemList` с pixel glyph, русским именем и ID; поиск `трава` оставляет `herb`. Двойной клик/Enter или `Выбрать` обновляет прежний `iconId`.
2. В shop listing нажать `Библиотека…`: каталог показывает все native-first items с иконками и локализованными именами. После выбора compact picker, preview и сохраняемый `itemId` совпадают.
3. Сохранить item/shop, закрыть и открыть граф снова: выбранные stable IDs и previews восстановлены. Общий JOI `items/catalog.json` не меняется.
4. В headless texture не создаётся, но `test_visual_library.gd` проверяет декодирование canonical 16×16 image, native `ItemList` tile/search/activation contract и обе editor integrations.

Общий design и порядок расширения на background/portrait/voxel/map previews — `docs/EMBER_VISUAL_LIBRARY_DESIGN.md`. Visual library не владеет content schema и не сериализует thumbnails.

### I2.34 — Visual Library для VN-артов

1. Открыть dialogue в Ember Graph. Возле `Фон сцены` нажать `▦`: grid показывает только background/CG, но не portrait-kind arts. Выбрать фон, сохранить и открыть заново — `defaultBgArtId` и live preview совпадают.
2. В dialogue/choice ноде открыть grid её фона. Первая плитка наследует фон сцены; её выбор очищает только `bgArtId`. В splash та же кнопка выбирает явный `artId` и предлагает `Без фона`.
3. Возле `Персонаж` нажать `▦`: tiles показывают representative portrait и число expressions. После выбора compact speaker, expression list, actor preview и canonical `speaker` синхронизированы.
4. Возле `Эмоция` нажать `▦`: grid содержит только expressions текущего speaker. Выбрать эмоцию — `portraitKey`, dialogue speaker и `actors[0]` следуют прежнему sync contract.
5. Проверить `+ Фон` и `+ Арт`: импорт остаётся рабочим, новый Resource появляется и в compact picker, и в visual grid. Неизвестный legacy ID остаётся warning tile, пока автор явно его не заменит.

`test_visual_library.gd` проверяет фильтрацию/IDs/unknown preservation, а `test_graph_workspace.gd` — наличие общего picker у scene background, speaker и expression без потери прежних VN authoring flows.

Регрессия legacy expressions: пустой native speaker-map не считается найденной эмоцией. `portrait_path()` обязан дойти до `portraits/<speaker>/registry.json`; тест проверяет существующий `hu_tao/bunny_tease` path. В Windows-renderer его thumbnail имеет ненулевой размер и показывается в `ItemList`.

### I2.35 — Visual Library и размещение voxel-prefabs

1. Открыть карту и нижнюю вкладку `Ember Migration`, нажать `Библиотека voxel-префабов…`. Grid содержит все model ID из JOI, русские названия/теги и поиск; уже собранные `.tscn` постепенно получают 128×128 preview из общего transient `SubViewport`.
2. Выбрать существующий prefab: он появляется в `Map/Props` на один тайл по +X от выбранного 3D anchor. Без anchor используется `player_start`. У объекта новый устойчивый `placement_id`, обычный transform-gizmo; Ctrl+Z/Redo удаляет/возвращает instance.
3. Выбрать модель с `◇`: строится только её prefab, а не весь каталог. После появления объект выбирается в Scene dock, Inspector видит прежний `EmberVoxelProp` contract.
4. Передвинуть/повернуть объект, Ctrl+S, закрыть/reopen сцену: model ID, placement ID и transform сохраняются. Полный reimport по-прежнему является отдельной подтверждаемой операцией и может перезаписать `Map/Props`.
5. `test_voxel_visual_library.gd` проверяет полное покрытие canonical каталога и save/reopen нового scene-owned prefab. `test_scene_edit_roundtrip.gd` и `test_voxel_prefab_rebuild.gd` остаются regression gates.

Visual Library не становится voxel writer: форма/цвет/emissive/transparency остаются в JOI, `.tscn/.res` — производный Godot cache. Preview существует только в памяти editor-сессии и не сериализуется.

### I2.36 — Изменяемая нижняя workflow-панель

1. Открыть `Ember Migration`: панель не должна вытеснять строку нижних вкладок за пределы окна. Потянуть верхнюю границу панели вверх/вниз — 3D viewport и содержимое корректно меняют размер.
2. Длинная форма прокручивается внутри панели; горизонтального ухода интерфейса нет. `Свет и производительность` и `Voxel-префабы` открыты, `Триггеры и цепочки` и `Обслуживание карты` по умолчанию свернуты.
3. Нажать `Закрыть` в постоянной шапке — bottom panel скрывается и 3D viewport занимает место. После повторного открытия состояние карты/selection не меняется.
4. Статус последней операции занимает одну строку и не увеличивает минимальную высоту; полный текст доступен в tooltip.

`test_migration_workflow_layout.gd` закрепляет fixed header, close-route, scroll ownership и отсутствие принудительной минимальной высоты.

### I2.37 — Реальные voxel thumbnails

1. Открыть voxel-библиотеку: плитки готовых prefabs не остаются текстовыми — миниатюры появляются постепенно, пока один общий viewport обрабатывает очередь. `◇` по-прежнему означает отсутствующий prefab, не ошибку preview.
2. Проверить разные пропорции (`vox_fan_anvil`, дерево/фонарь, длинный навес): объект целиком помещается в квадрат, показан в одинаковом изометрическом ракурсе и не засвечивается собственным Omni.
3. Закрыть и сразу открыть библиотеку: готовые previews берутся из memory cache без повторного GPU-прогона. После rebuild конкретного prefab новый path mtime создаёт новый cache key.
4. Preview renderer не пишет PNG, registry или metadata и не добавляется в game runtime. Очередь выполняется на main thread по одному prefab; второй importer/voxel renderer отсутствует.

`test_voxel_preview_renderer.gd` в headless закрепляет доступность контракта, а запуск без `--headless` проверяет Forward+/Vulkan texture 128×128 и наличие пикселей модели поверх фона.

### I2.38 — Source previews без массовой сборки

1. Открыть начало voxel-каталога: модели с `◇` также постепенно получают картинку. Сам ромб остаётся полезным статусом `prefab ещё не создан`.
2. Проверить `vox_crate_1`: до открытия и после preview файла `res://prefabs/voxels/vox_crate_1.tscn` нет. Миниатюра строится transient из canonical `.vox/.json`; выбор объекта по-прежнему отдельно создаёт prefab через штатный add flow.
3. Изменение `.vox` или `.json` меняет source mtime cache key; повторное открытие после правки не должно показывать старый кадр. Никакие PNG, registry или derived thumbnails на диск не пишутся.

`EmberVoxelPrefab.make_preview_instance()` вызывает тот же `_build_visual_mesh`, materials и `_make_tree`, что production prefab builder, но пропускает установку `.res` и сохранение `.tscn`. Windows Forward+ тест проверяет одновременно готовый `vox_fan_anvil` и source-only `vox_crate_1`, включая отсутствие нового prefab-файла.

### I2.39 — Визуальный выбор карты и точки входа

1. Выбрать дверь, нажать `Изменить`, затем `▦` рядом с картой. Grid показывает схему каждой canonical карты: цвета поверхности, белые маркеры voxel-пропов, имя и stable ID. Карта без готовой Godot-сцены остаётся видимой, но tooltip честно помечает её предупреждением.
2. Выбрать `agent_sandbox`, открыть `▦` у точки входа: `start`, `notice` и остальные regions используют ту же схему, выбранная зона обведена золотой рамкой. Плитка стандартного входа сохраняет пустой `targetRegionId`.
3. Повторить в Ember Graph/Inspector для шага `Сменить карту`. После выбора карты compact region field сразу перестраивается; после Save/reopen сохраняются точные `targetMapId/targetRegionId`, runtime transition не меняется.
4. Проверить, что открытие/поиск/выбор не запускают целевые `.tscn`, не создают screenshot/thumbnail-файлы и не меняют source map JSON.

`test_map_visual_library.gd` закрепляет общую top-surface проекцию preview/runtime, canonical map/region coverage, обе editor integrations, stable IDs и неизменность map JSON. `test_map_transition.gd` остаётся runtime gate.

### I3.0 — Quest Resource, цели и журнал

1. Выбрать `sbx_quest_sign/Interact`: рядом с `Изменить` появилась кнопка `Задание`. Открыть её — отдельно видны `ID задания` (имя Resource), `Флаг статуса` (save-ключ), название, описание, видимость до принятия и карточки целей с подписями `Внутренний ID / Текст в журнале / Флаг выполнения / Необязательная`.
2. Изменить текст demo-цели, сохранить, Ctrl+Z/Redo: `.tres` и связь marker должны меняться одной операцией. Закрыть/открыть сцену — описание сохраняется; `agent_sandbox.tscn` и JOI map JSON не переписываются.
3. Запустить `agent_sandbox`, нажать `Q`: журнал показывает `Записка у ворот`, жёлтый available-маркер и невыполненную цель. Журнал блокирует движение; `Q` или Esc закрывает его, I/F не открывают параллельный overlay.
4. Закрыть журнал, прочитать табличку и завершить прежний `sandbox_notice`, снова нажать `Q`: статус зелёный done, цель помечена `✓`. После F5 состояние сохраняется через прежний flags save v1.
5. Для проверки active временно записать тем же шагом значение текста `active` во `Флаг статуса` (`sandbox_notice_status`). Journal и marker должны показать голубое active; `ID задания` при этом не меняется и в save не появляется.

### I3.1 — ясный прогресс и безопасная проверка старого save

1. Открыть Play → `Q`. В карточке `Записка у ворот` строка `Слот N` должна перечислять только реально записанные `sandbox_notice_status` и/или `sandbox_notice_read`; если их нет, журнал так и сообщает.
2. Если старый save уже содержит `sandbox_notice_read=true`, карточка честно покажет источник завершения. Нажать `Сбросить прогресс этого задания (тест)`: исчезают только `sandbox_notice_status` и `sandbox_notice_read`, прочие флаги/инвентарь слота сохраняются.
3. После сброса квест снова available. Подойти к южной табличке, выполнить прежнюю цепочку и открыть `Q`: `sandbox_notice_status=active`, а `sandbox_notice_read=true` завершает только первую цель. Стартовый маркер исчезает; следующая доступная цель появляется на своём объекте.
4. В Inspector открыть `Задание`: убедиться, что подсказки различают Resource ID, общий status save-key, внутренний ID цели и её отдельный completion save-key.

### I3.2 — выбор quest-флагов в цепочках и диалогах

1. В Inspector открыть цепочку, добавить `Изменить флаг` и нажать `▦` справа от имени. Библиотека должна показать `◆ Записка у ворот / Статус задания` и `□ Записка у ворот / Прочитать табличку…`; поиск работает по русскому тексту и `sandbox_notice_*`.
2. Выбрать цель: поле получает ровно `sandbox_notice_read`. Тип/значение остаются прежними; установить `Да (true)`, сохранить цепочку, закрыть/открыть — ID и typed value сохраняются.
3. Открыть простой диалог с выбором, включить `После выбора изменить флаг`, открыть такой же `▦` и выбрать статус либо цель. Сохранить/reopen и пройти нужную ветку в Play.
4. В Ember Graph добавить node `Изменить флаг`, выбрать ключ через `▦`, выполнить локальные Undo/Redo и `Сохранить граф`: позиция/камера не сбрасываются, node по-прежнему сериализуется обычным `set_flag`.
5. Ввести вручную произвольный не-квестовый флаг: поле остаётся свободным, библиотека не ограничивает world/dialogue state только заданиями.

`test_quest_journal_authoring.gd` закрепляет Resource/store validation, раздельные quest/status/objective IDs и reference entries; `test_object_inspector_panel.gd`, `test_dialogue_authoring.gd` и `test_graph_workspace.gd` проверяют подстановку в три прежних `set_flag` authoring surface, включая local Undo. Pure flag projection, источник состояния в UI, scoped reset, атомарный Undo/Redo binding и неизменность scene остаются покрыты; `test_quest_state.gd` — marker/runtime gate.

### I3.3 — отдельный граф заданий

1. После перезапуска редактора открыть `Ember Graph` и в левом верхнем списке вместо `Цепочки действий` выбрать `Задания`. В соседнем списке должна находиться строка `Записка у ворот · sandbox_notice_quest`.
2. Открыть её: слева видна корневая нода задания, справа — связанная цель. В корне изменить название/описание/status flag; в цели — текст журнала, completion flag и `Необязательная`. Линия показывает принадлежность цели заданию, не runtime-порядок действий.
3. Нажать `+ Цель`, изменить новую карточку, проверить ↶/↷ и Delete. Последнюю цель удалить нельзя. Панорама, zoom и позиции нод не должны сбрасываться при локальном Undo/Redo.
4. Нажать `Сохранить задание`, закрыть и снова открыть Resource: поля и цели сохраняются в прежнем `.tres`. Глобальный Ctrl+Z/Redo Godot отменяет/возвращает standalone Resource write; scene и JOI JSON не меняются.
5. Нажать `+ Задание`: ID редактируется только до первого сохранения, новый черновик сразу защищён от случайного переключения. После сохранения он появляется в том же списке с `Название · ID`.

`test_graph_workspace.gd` закрепляет отдельный quest mode, root/objective projection, inline authoring, local history, создание и unsaved guard. `test_quest_journal_authoring.gd` проверяет standalone Resource save через общий Editor Undo/Redo owner.

### I3.4 — событие задания на объекте, месте и ветке

1. Выбрать prop с взаимодействием, открыть `Цепочка действий`, нажать `+ Событие задания` и выбрать `Начать задание · Записка у ворот`. В цепочке появляется обычный шаг `sandbox_notice_status = active`; сохранить, закрыть и открыть снова.
2. Для места нажать `+ Зона-триггер с цепочкой`, выставить `Активация: При входе`, затем в цепочке выбрать нужную цель через `+ Событие задания`. В форме условия выбрать status flag задания и typed текст `active`; при необходимости включить `Только один раз`.
3. В `Ember Graph` открыть диалог. Нажать `+ Событие задания`, выбрать цель и соединить созданную `set_flag`-ноду только с нужным выходом ветки. ↶/↷ должны отменять/возвращать её до `Сохранить граф`.
4. В Play сначала войти в зону при отсутствующем/неверном status: основная цепочка не запускается. Начать задание, снова войти: цель выполняется. При one-shot третий вход ничего не выдаёт.
5. Сохранить сцену, закрыть и открыть снова: `При входе`, строковое условие `active`, completion flag и action Resource остаются. Quest Resource не получает NodePath и JOI JSON не меняется.

`test_quest_journal_authoring.gd` проверяет компиляцию start/objective/done presets; `test_graph_workspace.gd` — вставку в action/dialogue local draft и Undo; `test_interact_launch_rules.gd` — typed bool/string routing; `test_standalone_trigger_authoring.gd` — Editor Undo/Redo и save/reopen `Area3D` с `status == active`.

### I3.5 — последовательность целей

1. В `Ember Graph → Задания` добавить вторую цель. Потянуть синий выход первой цели к синему входу второй: должна появиться синяя линия `A → B`, а строка второй цели покажет `После: A`. Золотые линии к корню остаются.
2. Попытаться соединить B обратно с A: цикл не создаётся, статус объясняет отказ. Нажать ↶/↷ — dependency исчезает/возвращается; ПКМ по синей линии удаляет её. Переместить ноды, сохранить и открыть задание заново.
3. В Play открыть Q до выполнения A: A показана голубым `◆`, B серым `◇` с текстом `сначала: A`. Запустить объект/ветку, которая преждевременно выдаёт B: появляется карточка `ЦЕЛЬ ПОКА НЕДОСТУПНА`, completion flag B отсутствует в save.
4. Выполнить A и снова открыть Q: B становится текущей `◆`. Повторить её событие — B получает `✓`; обязательные цели завершают задание как прежде.
5. Для проверки схождения сделать `A → D`, `B → D`, `C → D`: D открывается только после всех трёх. Необязательная цель не блокирует завершение задания сама по себе, но блокирует D, если автор явно провёл из неё зависимость.

`test_quest_journal_authoring.gd` закрепляет Resource round-trip, locked/current projection, ранний runtime reject/notice, unlock и cycle validation. `test_graph_workspace.gd` проверяет два типа проводов, dependency Undo/Redo и cycle rejection. Полный suite защищает прежние action/dialogue/world flags.

### I3.7 — динамические world-маркеры событий

1. На свежем save у объекта выдачи виден янтарный `!`, а у второй цели ничего нет. Скрытая цель не должна показывать F и не должна запускать цепочку.
2. В цепочке выдачи должен быть preset `Начать задание`; после диалога и записи status/objective flags её маркер исчезает вместо смены на общий голубой компас.
3. После выполнения prerequisite появляется только объект следующей цели. Если это последняя обязательная цель, он показывает мятную галочку; после взаимодействия исчезает.
4. Отдельный объект с событием `Завершить задание` показывает галочку только когда обязательные цели выполнены и скрывается после status `done`.
5. В Inspector строки `Роль маркера` и `На свежем прохождении` объясняют решение. Цепочка без start/objective/complete выбранного Quest получает warning и совместимый общий status fallback.

`test_quest_state.gd` закрепляет start/future/locked/final/completed/turn-in projection, stock icon aliases, runtime visibility и F gate. `test_object_inspector_model.gd` закрепляет понятную роль/состояние без изменения scene.

### I3.8 — понятный модификатор взаимодействия

1. В узком Inspector открыть `Взаимодействие`: кнопки должны переноситься, а не уходить за правую границу. `Настройки`, `Действия`, `Описание задания` и `+ Событие задания` открывают разные ожидаемые редакторы.
2. Нажать `Настройки` у двери, разговора, магазина и quest-marker. Блок `РЕЗУЛЬТАТ В ИГРЕ` должен сразу описать F/enter и выбранное назначение; dropdown показывает название контента вместе с ID.
3. На обычном объекте condition/fallback/one-shot скрыты под `Дополнительно`. Раскрыть, сохранить условие, reopen: блок открывается автоматически и значения не теряются.
4. У quest-marker по умолчанию видны только задание, событие/цепочка и заметка. Fallback/custom icon появляются только после `Дополнительно`; подсказка объясняет автоматическую роль маркера.
5. При создании нового Interact вариант `Сундук (из карты)` отсутствует. Существующий импортированный сундук остаётся читаемым, потому что loot/state редактируются владельцем map content, а не пустой shell-формой.

`test_object_inspector_panel.gd` закрепляет outcome preview, readable catalog labels, collapsed/expanded technical rows, quest guidance, wrapped actions и отсутствие пустого chest authoring. `test_object_inspector_actions.gd` и `test_scene_edit_roundtrip.gd` продолжают проверять прежний normalized save/Undo/reopen контракт.

### I3.9 — Quest Flow и обратные связи событий

1. В `Ember Graph → Задания` открыть Resource. Фиолетовые ноды должны показать action/dialogue writers status/objective flags и соединиться с соответствующим корнем или целью.
2. Кнопка `Открыть <id>` переводит к исходной цепочке либо диалогу; Quest Resource при навигации не меняется.
3. Изменить исходный `set_flag`, сохранить и вернуться/обновить Quest: связь должна пересчитаться из catalogs без ручного обновления Quest.
4. Перемещение/auto-arrange производных нод не добавляет их ID в `QuestResource.editorLayout`; save schema и runtime остаются прежними.
5. Source-ноды не выше 180 px при длинном flag/document ID; выбор длинного имени не меняет базовую ширину property-колонки, полный текст остаётся в tooltip.
6. Source-нода двигается мышью и сохраняет позицию в текущем view-state, но после сохранения Quest её ключ отсутствует в `editorLayout`.

`test_quest_usage_index.gd` закрепляет action, direct dialogue и choice writers, target classification и игнорирование чужих flags. `test_graph_workspace.gd` проверяет read-only source nodes, связи, deep-link metadata и прежнее quest editing/Undo.

### I3.10 — объекты открытой сцены в Quest Flow

1. Открыть `agent_sandbox`, затем `sandbox_notice_quest`: слева должны появиться зелёные scene-ноды для объектов, запускающих `sandbox_notice` и `sbx_quest_active_actions`.
2. Зелёный провод ведёт не прямо к цели, а к конкретной фиолетовой action/dialogue ноде; один объект может иметь несколько таких связей.
3. `Выбрать в сцене` переключает в 3D и выбирает voxel prop; для `AuthoredTriggers` выбирается сам `EmberInteract`.
4. Переключение открытой сцены и Refresh перестраивают backlinks. Сохранение Quest не добавляет scene NodePath в Resource.

`test_quest_usage_index.gd` проверяет scene scan/owner/path/multiple events. `test_graph_workspace.gd` закрепляет зелёную ноду, число связей и navigation signal; headless editor boot проверяет plugin bridge.

## Волна 5 — решение

Полная миграция продолжается, если:

- световой gate проходит на профиле 4 или 8;
- два последовательных voxel-задания укладываются в 90 секунд без потерь;
- редактирование карты переживает save/reopen и случайный ошибочный шаг восстанавливается;
- `agent_sandbox` закрывает обязательные механики вертикального среза;
- не возник второй расходящийся JSON/schema/render contract.

Миграция ставится на паузу, если Godot выигрывает только картинкой, но авторский цикл требует постоянного полного reimport, ручной починки prefab или двойного редактирования данных.

## Журнал замеров

Добавлять запись после реального прогона, не по ощущениям. Шаблон записи: дата; сцена/GPU/разрешение; профиль теней; frame p95; CPU render; GPU render; shadow draw calls; время UX-задания; итог. До первого ручного прогона профили 0/2/4/8 считаются неизмеренными.

- 2026-08-27; `fan_town`, 1600×900; профиль 8, active/candidates 8/11; FPS 200 (cap), frame p95 5.00 ms, CPU render 0.55 ms, GPU render 2.56 ms, visible/shadow draw calls 33/374; пользователь подтвердил deep-link, сохранение, targeted rebuild и отображение transparency/emissive; активное время не записано. Итог: функциональный UX и performance-gate пройдены, timed gate пока открыт.

## Ближайший порядок работ

1. Закрыть паспорт baseline волны 0 (версия/GPU/скрин); performance-gate света уже принят на production 8.
2. На следующей обычной правке только записать активное время JOI bridge; функционально цвет/форма/emissive/transparency уже приняты.
3. **Принято:** Object Inspector I0–I2, включая add/edit/remove UI и каталоги, работает в реальном Godot; автоматический lifecycle/Undo/Redo/save/reopen contract закрыт отдельно.
4. **Автоматически закрыто:** action-chain, dialogue, shop и item editors используют отдельные общие native-first каталоги без смены gameplay schema. Legacy-документы мигрируются по одному, новые сразу создаются `.tres`. Следующий gate — ручные I2.29–I2.32 save/reopen/runtime прогоны.
5. **Принято и расширено:** магазин, buy/sell, inventory и stock persistence работают в реальном Godot; v1.38–v1.39 добавляют native assortment и item stats authoring с неизменной save v1 schema. Ручная приёмка I2.31/I2.32 остаётся.
6. Там же вручную пройти дверь/выход и talk-маршруты через назначенные Inspector references; headless-контракты уже закрыты.
7. **Автоматически закрыто:** восстановление map/spawn/chest/flags из того же save v1, включая точную позицию, arrival guard и one-shot loot. Ручная проверка restart остаётся ниже.
8. **Автоматически закрыто:** inventory/equipment экран поверх существующего `EmberExploreState`, equip/unequip, JRPG/arena slots, stats и save round-trip. Ручная UI-приёмка остаётся ниже.
9. **Принято и расширено:** action-list executor разворачивает все семь canonical шагов. Диалог, reward, timed wait и магазин корректно приостанавливают/продолжают очередь; `change_map` завершает её через общий transition owner. Script-only regions показывают F только при рабочем обработчике; пользователь подтвердил ветки, выдачу монеты и паузу на реальном `sandbox_chain`.
10. **Принято:** player HP, armor mitigation, применение `hpRestore`, HUD/inventory presentation и `hp/maxHp` save round-trip. В `agent_sandbox` H наносит 30 тестового урона; пользователь подтвердил damage/heal/use UI в реальном запуске.
11. **Автоматически закрыто:** quest-marker projection и authoring-поля `questStatus/iconId/scriptId`. Ручная приёмка смены `! → ✓` после таблички остаётся ниже.
12. **Принято:** defeat/respawn поверх существующего HP owner; пользователь подтвердил четыре H, блокировку и возврат по R.
13. **Автоматически закрыто:** Godot-native roof spike в `agent_sandbox` строит одну отдельную секцию из `ground_z2 + interiorVolumes`, использует `Area3D`, native transparency и симметричное управление тенями без per-frame traverse/remesh. Следующий gate — ручная приёмка через F7 и решение об authoring; production остаётся выключен.

### Ручная приёмка roof/cutaway spike

1. Открыть и запустить `scenes/agent_sandbox.tscn`. Нажать F3: строка должна показывать `cutaway: 0/1 открыто`, а заголовок — `F7 крыша`.
2. Не заходя в дверь домика, поставить камеру так, чтобы одновременно были видны крыша и её тень. Нажать F7: секция плавно исчезает, счётчик становится `1/1`, но структурная тень крыши остаётся на месте и освещение не прыгает.
3. Нажать F7 ещё раз: крыша плавно возвращается поверх той же неизменной тени, счётчик возвращается к `0/1`.
4. Повторить несколько раз и записать F3 до/после: не должно быть накопления draw calls, скачков p95 или зависшей полупрозрачной секции.
5. Проверить обычный вход через дверь и выход из отдельной interior-сцены. Переход карты остаётся текущим gameplay-контрактом и не зависит от F7.
6. После скриншота/подтверждения выбрать следующий срез: scene-owned authoring секций и стен либо оставить отдельные interior-сцены без production cutaway. До этого не включать флаг на `fan_town`.

### Ручная приёмка save restore

1. Запустить проект через F5, перейти в `agent_sandbox`, отойти от spawn и открыть сундук в регионе `chest`.
2. Остановить и снова запустить проект через F5: должна восстановиться та же карта и точная позиция; сундук показывает, что уже открыт, лут остаётся в inventory.
3. Запустить конкретную сцену через F6: Godot не должен самовольно перенаправлять её на карту из save.

### Ручная приёмка inventory/equipment

1. После получения лута сундука нажать I: должны отображаться монеты, трава и «Пика похоронного бюро»; ходьба заблокирована.
2. В сумке выбрать пику через W/S и нажать F: она уходит в слот «Оружие», `atk` меняется с 4 на 18.
3. A переключает на экипировку; выбрать «Оружие» и нажать F: пика возвращается в сумку, `atk` снова 4.
4. I или Esc закрывает экран. В магазине I ничего не открывает. После F5 restart экипированный предмет и сумка сохраняются.

### Ручная приёмка action-list

1. Запустить `agent_sandbox`, подойти к отдельной воксельной табличке с золотой подписью `СЦЕНАРИЙ · F`: она стоит точно в центре региона `chain_demo`, HUD должен показать `F: Действие`.
2. Нажать F: открываются две существующие реплики `sandbox_notice_talk`; монета ещё не должна выдаваться до завершения диалога.
3. Завершить диалог: появляется отдельная золотая карточка `ПОЛУЧЕНО`, где видны название предмета, `+1` и новое количество монет. До F цепочка дальше не идёт.
4. Нажать F на карточке награды: синяя карточка `ПАУЗА` остаётся на указанное число секунд и продолжает цепочку автоматически; F не проматывает задержку. После неё overlay закрывается, движение снова доступно, а монета видна в сумке.
5. Перезапустить F5: inventory и typed flag `sandbox_chain_done=true` остаются в save v1. Повторный запуск цепочки разрешён существующим authored-контрактом — отдельного one-shot поля здесь не добавлялось.

### Ручная приёмка HP/consumables

1. Запустить `agent_sandbox`: HUD показывает текущее `HP …/…` и подсказку `H тест урона`.
2. Нажать H один раз: HP уменьшается на 30 и кратко появляется сообщение `-30 HP (тест)`; при надетой броне вычитается её `def`, минимум урона — 1.
3. Получить траву из сундука либо использовать уже сохранённую, открыть I, выбрать «Погребальная трава» и нажать F: HP восстанавливается на 4, stack уменьшается на один.
4. При лечении выше максимума HP остаётся на `maxHp`; использование при полном HP показывает `HP уже полный` и всё равно списывает предмет — это сохранённый JOI-контракт.
5. Перезапустить F5: повреждённое/восстановленное HP и inventory сохраняются.
6. Нажать H до нулевого HP: движение, F и I блокируются, HUD показывает `ПОРАЖЕНИЕ · R вернуться к точке входа`.
7. Нажать R: игрок появляется в `player_start` с полным HP; inventory/equipment/flags и открытые сундуки не сбрасываются. После F5 сохраняются полное HP и новая позиция.

### Ручная приёмка quest state

1. Перед запуском очистить scoped progress `sandbox_notice_status`, `sandbox_notice_read`, `sandbox_notice_quest_objective_2` и `sandbox_notice_quest_objective_3` через журнал либо сменить save slot.
2. Запустить `agent_sandbox`: у стартовой таблички виден жёлтый `!`; маркеры второй и третьей целей скрыты, потому что задание ещё не принято.
3. Подойти к стартовой табличке: HUD показывает `F: Новое задание`. Нажать F и завершить диалог: цепочка пишет status active и первую цель, после чего маркер выдачи исчезает.
4. Теперь появляется обычный активный маркер второй цели. Нажать F: он ставит `objective_2` и исчезает; только после этого третья цель получает мятную галочку как последняя обязательная.
5. Нажать F у третьей цели: `objective_3` записывается, marker исчезает, затем выполняется authored переход карты. Повторной подсказки F нет.
6. Перезапустить F5: все три выполненных событийных маркера остаются скрытыми, потому что читают те же typed `flags` save v1.
7. В Inspector у трёх `Interact` проверить строки **Роль маркера** и **На свежем прохождении** вместе с отдельными **Задание** и **Цепочка действий**.

### Ручная приёмка Quest Flow guided bind (v1.60)

1. Открыть `agent_sandbox.tscn`, перейти в `Ember Graph → Задания → sandbox_notice_quest` и выбрать в Scene любое voxel-препятствие без `Interact`. В root/objective карточках строка `Объект` должна показать выбранное имя, кнопки bind становятся активными.
2. На первой objective нажать `□ Выполнение → объект`: появляется canonical action Resource, выбранный prop получает scene-owned `quest_marker`, а после refresh видны фиолетовый writer, зелёный объект и оба вычисляемых провода.
   Проверить также новую ещё не сохранённую objective: отдельное нажатие `Сохранить задание` перед bind не требуется; objective, action и Interact сохраняются одной операцией.
3. Ctrl+Z атомарно убирает Interact, Resource и backlinks; Redo возвращает все три. Сохранить сцену, закрыть/открыть — binding сохраняется без NodePath в Quest Resource.
4. Повторно нажать ту же objective: второго одинакового `set_flag` быть не должно. Привязать другое событие — оно добавляется в ту же цепочку.
5. Выбрать существующий talk/shop/trigger: bind дополняет его цепочку, но не меняет тип взаимодействия. Для цепочки с последним `change_map` quest-event остаётся перед терминальным переходом.

Targeted gates: `test_action_chain_authoring.gd` проверяет компиляцию, создание marker, append/idempotence и атомарный Undo/Redo; `test_graph_workspace.gd` — выбранный scene owner и корректный event token.

### Ручная приёмка зелёного drag-to-bind (v1.62)

1. В открытой карте выбрать voxel без Interact: в Quest Flow появляется зелёная нода `Выбранный объект · … / Готов к привязке`.
2. Протянуть её зелёный output к `Перетащить объект → выполнить цель`. Результат совпадает с кнопкой: сохраняются Quest/Action/Interact, candidate заменяется зелёным backlink через фиолетовый writer.
3. Проверить два отдельных зелёных входа root: `начать` пишет status `active`, `завершить` — `done`; они не перепутаны.
4. Ctrl+Z/Redo обновляет фактические backlinks. Повторный drag на то же событие не создаёт duplicate `set_flag`.
5. Передвинуть candidate, обновить граф и сохранить Quest: её `scene_candidate:*` позиция не появляется в `editorLayout`.

### Ручная приёмка отвязки quest-event (v1.63)

1. Выбрать в Scene объект, уже связанный с целью: на соответствующей фиолетовой action-ноде появляется `Отвязать выбранный объект`.
2. Нажать кнопку либо разорвать зелёный провод объект → action writer. Исчезает только выбранный quest-event; диалог, награда, переход и прочие шаги цепочки остаются.
3. Нажать Ctrl+Z и Redo: Resource, `script_id` объекта и вычисляемые backlinks восстанавливаются/снимаются атомарно.
4. Назначить одну цепочку двум объектам и отвязать событие только от одного. Второй объект должен сохранить исходную общую цепочку; первый получает отдельную сокращённую цепочку либо очищенную привязку, если шаг был единственным.
5. Попытаться разорвать связь с фиолетовой dialogue-нодой: данные не меняются, статус предлагает открыть Dialogue Graph и изменить конкретную ветку там.

Targeted gates: `test_quest_usage_index.gd` хранит точный action writer index, `test_action_chain_authoring.gd` проверяет удаление одного шага и Undo/Redo, `test_graph_workspace.gd` — зелёный disconnect gesture и payload события.

### Ручная приёмка компактного Quest Flow (v1.64)

1. Открыть задание с несколькими целями. Стартовый canvas показывает только задание, цели и синие зависимости — фиолетово-зелёной паутины быть не должно.
2. В каждой карточке проверить сводку `Цепочки / Диалоги / Объекты` и прежние кнопки привязки. Нажать `Открыть события и объекты →` у одной цели.
3. В drill-down остаётся одна цель, связанные с ней action/dialogue writers, объекты открытой сцены и выбранный candidate. Кнопки открыть источник, выбрать объект, отвязать и drag-to-bind работают как раньше.
4. Передвинуть canvas/изменить zoom, нажать `← Обзор`, затем снова открыть ту же цель: overview и focus должны восстановить собственные положения камеры независимо.
5. Нажать `Все связи`: появляется прежний полный диагностический граф. `← Обзор` снова очищает паутину.
6. Сохранить/переоткрыть Quest Resource: focus/all-links и их позиции не появляются в `.tres`; overview сохраняет только `quest_root` и `objective:*` layout.

Targeted gate: `test_graph_workspace.gd` проверяет компактный default, drill-down одной цели, breadcrumb, диагностический full view и раздельное view-state.

### Hotfix портов компактного Quest Flow (v1.65)

1. Открыть задание с последовательностью хотя бы из двух целей: в overview синий провод должен доходить до следующей цели без ошибок `graph_node.cpp ... p_port_idx`.
2. Открыть события одной цели и затем `Все связи`: зависимости остаются видимыми, а переключение режимов не создаёт повторяющихся ошибок портов.
3. Создать и удалить синюю зависимость мышью в overview и full view: оба режима меняют один canonical `requiresObjectiveIds` и корректно работают с Ctrl+Z/Redo.

Targeted gate: `test_graph_workspace.gd` проверяет, что каждый сохранённый GraphEdit connection ссылается на существующий input/output port и что dependency-вход равен `0` в overview и `1` в focus/full view.

### Quest authoring stop-line (принят пользователем 2026-09-01)

Текущий quest-срез закреплён: Resource/журнал, раздельные status/objective flags, optional/dependency-граф, action/dialogue/world bindings, динамические маркеры, компактный Quest Flow, Undo/Redo и save/reopen. Общую полировку и новые абстрактные типы целей останавливаем до появления реальных gameplay event owners.

Возврат обязателен после D2 combat result, завершения inventory/loot events, устойчивых zone events и companion state. Тогда отдельными вертикальными срезами добавляются defeat/count, collect/have/deliver, discover/clear и companion objectives. Активный порядок и stop-lines теперь ведутся локально в `docs/EMBER_PRODUCT_PLAN.md` и этом плане.

### D1.1 — Combat Lab E1 skeleton (v1.66)

1. В Godot открыть `Проект → Инструменты → Ember: Run Combat Lab`. Main scene проекта и save slot не меняются.
2. Проверить четыре области и восемь элементов открытой очереди. Выбор действия должен менять прогноз и подсветку допустимых целей, но не состояние бойцов до выбора цели.
3. Выбрать у Миры `Обливание` и кликнуть допустимую цель в мокрой низине. Этот клик коммитит действие: в журнале появляется Wet/урон, враг отвечает, очередь переходит к следующему герою.
4. Создать и проверить реакции: Water → Wet, Cold по Wet → Frozen, Lightning по мокрой области → цепь по двум врагам, Fire по Frozen → паровой импульс с перемещением.
5. `Прикрытие` уменьшает следующий входящий удар, `Парный импульс` недоступен без подготовленного состояния и появляется после него. Preview до выбора цели называет ожидаемое действие; поле показывает допустимые цели.
6. Нажать R: encounter полностью сбрасывается. Закрыть и запустить снова: save/inventory/quest flags и main scene не менялись.

Targeted gates: `test_combat_prototype.gd` закрепляет pure preview/commit, timeline, реакции, область, guard и enemy command; `test_combat_lab.gd` — 1600×900 UI, очередь, live preview и confirm route. E1 остаётся контрольным вариантом для сравнения с E2; до выбора пространства и E3 production battle Resource/manager не вводить.

### D1.2 — Combat Lab E2 grid comparison (v1.67)

1. Запустить Combat Lab: по умолчанию открывается `E2 · Сетка 7×5`; через верхний selector можно вернуть E1 с четырьмя областями.
2. До движения враги вне range: action buttons недоступны, пустой клик не коммитит ход. Нажать `M`: поле показывает доступные клетки, но не разрешает преграды, занятые клетки и Жар-фокус.
3. Выбрать для Миры D2. Позиция на сетке пока не меняется, но preview уже показывает `B3 → D2`, `Обливание`, цель и Wet. Нажать `Вернуть`: staged cell возвращается в B3 без изменения snapshot.
4. Повторить движение, выбрать действие и допустимую цель: целевой клик одним commit переносит героя, применяет действие, запускает ответ врага и меняет очередь.
5. Синие связанные панели имеют Wet и проводят молнию только внутри своей группы. Янтарные панели, связанные с фиксированным Жар-фокусом, добавляют +2 к огню; preview явно называет бонус.
6. `R` полностью сбрасывает лабораторию; save/quests/inventory/main scene не меняются.

Targeted gates: `test_combat_grid.gd` закрепляет reachability, staged purity, move+action commit, panel conduction, focus bonus и forced movement; `test_combat_lab.gd` — кликабельный 7×5 UI и возврат к E1. Враги пока отвечают без отдельной фазы перемещения, а Жар-фокус ещё нельзя двигать/разрушать: это следующие гипотезы D1, а не скрытая production-готовность.

### D1.3 — Защита без атаки (v1.68)

1. В начале E2 враги вне range, но `G. Защита` доступна. Нажатие `G` сразу завершает ход без отдельного подтверждения.
2. Очередь переходит дальше, а у героя остаётся `Защита`; следующий входящий урон сокращается вдвое и статус расходуется.
3. Нажать `M`, выбрать другую клетку, затем `G`: один внутренний commit применяет перемещение и Защиту.
4. На ходу Орика различаются `Прикрытие` (цель — союзник) и `Защита` (цель — сам Орик, ход без атаки).

### D1.4 — Видимая staged-позиция (v1.69)

1. На ходу Миры нажать `M` и выбрать D2. На D2 сразу видна `Мира · план`, HP и `ждёт F`; клетка обведена янтарным.
2. Исходная B3 больше не притворяется текущей позицией: она показывает `Мира → D2`. Tooltip объясняет origin/destination до confirm.
3. До `F` `state_snapshot()` всё ещё хранит B3. `Вернуть` возвращает обычную карточку Миры на B3; `F` после повторного выбора переносит canonical cell в D2.
4. После staged movement self-target `Защита` выбирается кликом по проекции героя на destination, а не по пустому origin.

### D1.5 — Высота и изменяемая поверхность (v1.70)

1. В E2 клетки верхней террасы показывают `Высота +1`, а A1 — `Высота +2`. В режиме `M` герой может подняться на один уровень, но не может одним шагом войти на двухуровневый уступ.
2. Переключить верхний selector на `E3 · Хранитель оттепели`. Первый ход Орика сразу показывает `Заморозка`, строку `Поле ... → Frozen` и голубую рамку/подпись `Frozen · прогноз` на всех связанных tide-панелях.
3. Выбрать холод и навести курсор на допустимую цель: поле и прогноз показывают Frozen, но canonical `state_snapshot()` сохраняет Wet. Кликнуть цель: все шесть панелей атомарно становятся Frozen вместе с действием и ходом.
4. На ходу Сены выбрать `Уголёк` и навести его на бойца на замёрзшей группе. Preview показывает возвращение поля в Wet; клик по цели применяет оттепель. `R` возвращает исходное мокрое поле.
5. Принудительный `Порыв`/Steam Break не перемещает цель через перепад выше одного уровня: обычное и forced movement используют один terrain rule.

Targeted gates: `test_combat_prototype.gd`, `test_combat_grid.gd`, `test_combat_lab.gd`. `EmberCombatTerrain` остаётся pure leaf для semantic cells и будущего `GridMap` adapter; visual geometry/collision не имеют права решать combat reachability.

### D2.0 — Native 3D GridMap projection (v1.71)

1. Запустить Combat Lab и оставить E2. Верхний selector `Вид · 3D` выбран по умолчанию: поле видно под ортографическим углом, верхняя терраса физически выше, A1 ещё выше, blockers объёмные, герои/враги и Жар-фокус стоят отдельными объектами.
2. Нажать `M`: доступные клетки получают зелёные overlays. Кликнуть D2 — Мира сразу отображается на D2 с подписью `план`, но `state_snapshot()` до выбора цели всё ещё хранит B3. Выбрать действие, навести на бойца для preview и кликнуть по нему: один commit применяет прежний compound command.
3. Переключить E3. При наведении на допустимую цель шесть tide-тайлов имеют Frozen mesh/голубой overlay, но canonical tags остаются Wet. Клик сохраняет те же тайлы Frozen из commit; Fire hover-preview возвращает их в Wet.
4. Переключить `Вид · 2D диагностика`: появляется прежняя таблица 7×5 с теми же юнитами, высотой, reachable и pending field changes. Вернуть 3D — state и выбранный encounter не сбрасываются.
5. Проверить клики по низким и поднятым тайлам. Input использует collision `MeshLibrary` и `GridMap.local_to_map`; экранные координаты, физическая клетка и canonical `Vector2i` должны совпадать.

Targeted gates: три combat tests; `test_combat_lab.gd` дополнительно проверяет 35 GridMap cells, authored Y layers, camera ray D2, staged unit projection, E3 Frozen item/overlay и возврат 2D diagnostics. `NavigationMesh`, production Resource/editor/save и external terrain addons в D2.0 не вводятся.

### D2.0.1 — Обычная 3D-сцена вместо embedded viewport (v1.72)

1. Через `Проект → Инструменты → Ember: Open Combat Lab` открыть `combat_lab.tscn`. Корень сцены — `CombatLab3D (Node3D)`, а `CombatGridMap`, `CombatActors3D`, `CombatOverlays3D`, `CameraRig/CombatCamera3D`, свет и окружение доступны в обычном дереве Godot.
2. Запустить сцену. Поле рисуется основной `Camera3D`, без `SubViewportContainer`; HUD находится в `CanvasLayer` и не создаёт второй мир/renderer.
3. Повторить D2 staged movement и D3 Frozen preview. Оба проходят через тот же `EmberCombatGrid3DWorld`, что и compatibility adapter, поэтому выбор клетки и visual state совпадают.
4. Переключить `Вид · 2D диагностика`, затем E1. Основной 3D-мир скрывается, но snapshot не сбрасывается; возврат в E2/E3 снова показывает ту же сцену.

Targeted gate: `test_combat_lab.gd` проверяет корень `Node3D`, scene-owned `GridMap/Camera3D`, отсутствие embedded viewport в main scene, 35 клеток, ray-pick, staged actor, E3 mutation и 2D parity. Это исправление scene boundary, а не завершённый D2.1 editor: graybox MeshLibrary пока transient, battle layout ещё не сериализуется автором.

### D2.0.2 — Управляемая и authored камера боя (v1.73)

1. Запустить E2 и держать курсор над полем. ПКМ вращает камеру, СКМ сдвигает точку обзора, колесо приближает/отдаляет. WASD/стрелки панорамируют, Q/E вращают; эти клавиши не совершают боевой ход.
2. Нажать Home: камера возвращается к параметрам, сохранённым в `CameraRig` при запуске сцены.
3. Открыть `combat_lab.tscn`, выбрать `CameraRig`. В Inspector группы `Ракурс`, `Объектив`, `Управление в бою` позволяют менять target, distance, yaw/pitch в градусах, ограничения, projection, orthographic size, FOV, near/far и чувствительность. Благодаря `@tool` дочерний `CombatCamera3D` обновляется в 3D viewport до запуска.
4. Для обычного top-down оставить `Ортографическая` и подбирать `Orthographic Size`; FOV в этом режиме геометрически не используется. Чтобы оценить перспективу, выбрать `Перспективная` и затем менять FOV/distance.
5. После смены ракурса проверить клик по низким и поднятым тайлам: ray-pick обязан продолжать возвращать клетку под курсором.

Targeted gate: `test_combat_lab.gd` проверяет wheel zoom, RMB orbit, MMB pan, Inspector projection/FOV, Home reset и ray-pick после reset наряду с прежними combat gates.

### D2.1a — Отдельные arena-сцены и editor preview (v1.74)

1. После перезагрузки addon открыть `Проект → Инструменты → Ember: Open Battle Arena · E2`. В 3D viewport без запуска видны 35 клеток «Цветной переправы», высоты, blockers, актёры, Жар-фокус, CameraRig и свет.
2. Открыть `Open Battle Arena · E3`: tide-панели показывают Frozen preview, потому что scene-root имеет `Editor Preview Mode = E3` и использует прежний pure command preview.
3. Переоткрыть `combat_lab.tscn`: основной lab инстанцирует E2 arena, поэтому 3D editor viewport также больше не пустой; HUD остаётся CanvasLayer и появляется при запуске.
4. В каждой arena-сцене можно отдельно сохранять overrides камеры, света, окружения и добавленный декор. Не редактировать transient preview-клетки как production layout: следующий срез даст authored MeshLibrary palette + semantic `.tres` и validation.
5. `Editor Preview Enabled` на root временно скрывает/возвращает generated preview. Он не меняет runtime snapshot и не записывает combat progress.

Targeted gate: `test_combat_arena_scenes.gd` инстанцирует обе `.tscn`, вызывает тот же preview path и проверяет mode, 35 GridMap cells, camera/actors и отсутствие Frozen-state leak между E2/E3. Принятый масштабируемый контракт: arena `.tscn` — presentation/composition; будущий battle `.tres` — semantic data; resolver — runtime legality/preview/commit.

### D2.1b — CameraRig Inspector live-preview (v1.75)

1. Открыть `colored_crossing.tscn` или `thaw_keeper.tscn` и выбрать `CameraRig`, не дочернюю камеру. Вверху Inspector должен появиться раскрытый блок `Предварительный просмотр CameraRig` с кадром текущей арены.
2. Поменять `target`, `yaw`, `pitch` и `orthographic size`: в ортографии FOV заблокирован, потому что Godot его не использует. Переключить projection на перспективу: теперь блокируется orthographic size, а FOV меняет кадр. Дочерняя `CombatCamera3D`, 3D viewport и Inspector-preview должны показать один ракурс без Play; status preview подписывает активный Size/FOV.
3. Свернуть блок: рендер preview останавливается и Inspector становится компактнее. Развернуть — кадр возвращается. Нажать `Выбрать Camera3D` — Inspector переходит на дочернюю камеру со штатным Godot preview.
4. Переключаться между `CameraRig`, другими объектами и аренами, затем перезагрузить addon. Не должно оставаться лишних preview-камер, окон или ошибок lifecycle.

Targeted gate: `test_combat_camera_rig_preview.gd` проверяет общий `World3D`, совпадение transform/lens, live-sync после authoring-изменения и наличие навигации к дочерней камере. Preview является только editor adapter: он не сериализуется в arena `.tscn` и не создаётся в игре.

### D2.1c — Semantic Battlefield Resource (v1.76)

1. Открыть `colored_crossing.tscn`, выбрать корень и раскрыть поле `Battlefield`; открыть назначенный `colored_crossing.tres`. В Inspector видна мини-карта 7×5: синие Wet, янтарные Ember, тёмные blockers, число внутри — gameplay-высота, золотая рамка — Geo focus.
2. Повторить для `thaw_keeper.tscn`: arena должна ссылаться на отдельный `thaw_keeper.tres`, а не делить изменяемый Resource с E2.
3. Временно изменить `display_name` или `focus_bonus`, Ctrl+S и переоткрыть Resource: значение сохраняется. Вернуть изменение через Ctrl+Z либо вручную. Изменение cell-array в этом переходном срезе допустимо только для технической проверки; paint-палитра будет следующим authoring-срезом.
4. Уменьшить один из четырёх cell-arrays и выбрать Resource: красная диагностика сообщает ожидаемое и найденное число значений. Вернуть значение без запуска игры. У arena root также появляется configuration warning при отсутствующем/невалидном Resource.
5. Запустить Combat Lab E2/E3: движение, Wet/Ember/Frozen, blockers, высоты, focus и ray-pick совпадают с прежним прототипом. Resource является источником semantic cells; `GridMap` остаётся проекцией.

Targeted gate: `test_battlefield_resource.gd` загружает оба `.tres`, проверяет validation, 35 canonical cells, blocker/elevation/focus, ссылки обеих arena-сцен, Inspector mini-map и save/reopen signature. Прежние `test_combat_grid.gd`, `test_combat_arena_scenes.gd`, `test_combat_lab.gd` закрепляют runtime parity.

### D2.1d — Battlefield paint palette + Undo/Redo (v1.77)

1. Открыть `colored_crossing.tscn`, на корне открыть `Battlefield → colored_crossing.tres`. Над мини-картой выбрать `Wet`, оставить `Группа` пустой и кликнуть нейтральную клетку: она становится синей, tooltip получает `группа tide`, а 3D GridMap открытой arena меняется без Play.
2. Нажать Ctrl+Z: Resource, мини-карта и 3D arena возвращают исходную клетку. Ctrl+Shift+Z повторяет изменение. Ctrl+S, закрытие/повторное открытие сохраняют результат. После проверки откатить тестовую правку.
3. Проверить `Ember` с автоматической группой `ember`, затем ввести свой group ID и нарисовать вторую связанную панель. `Обычная` очищает terrain/blocking/group; `Преграда` делает клетку непроходимой.
4. `Высота +` и `Высота −` меняют число клетки и реальную высоту GridMap, не меняя тип поверхности. Высота не опускается ниже 0. `Перенести фокус` двигает золотую рамку и Geo focus объекта.
5. Попытка поставить преграду под текущим focus даёт красную validation-диагностику; перенести focus или очистить клетку — ошибка исчезает. Никакая операция не создаёт второй GridMap/schema.

Targeted gate `test_battlefield_resource.gd` дополнительно проверяет восемь guided tools, terrain+group mutation, height/focus, Undo/Redo и отсутствие утечки истории. Editor startup проверяет регистрацию palette Inspector plugin.

### D2.1e — Native 3D Battlefield Paint Mode (v1.78)

1. Открыть `colored_crossing.tscn` и выбрать корень `BattleArenaColoredCrossing`. В верхней панели 3D нажать `Поле боя`; справа от кнопки доступны те же восемь semantic-кистей, поле группы и короткий статус. На другой сцене без валидного Battlefield Resource кнопка должна быть отключена.
2. Выбрать `Wet`, оставить группу пустой и провести ЛКМ через несколько клеток. Hover и текущий штрих обведены в viewport; быстрый диагональный протяг не оставляет дыр. До отпускания Resource не переписывается, после отпускания весь штрих появляется в GridMap.
3. Один Ctrl+Z отменяет все клетки последнего штриха, один Redo возвращает их. Ctrl+S сохраняет тот же `colored_crossing.tres`; закрыть и открыть arena, убедиться, что результат сохранился, затем откатить тестовую правку.
4. `Alt+ЛКМ` по окрашенной клетке выбирает её surface brush и group. ПКМ orbit, СКМ pan и колесо zoom продолжают работать; выключение `Поле боя` возвращает обычное выделение ЛКМ.
5. Проверить низкую, поднятую и заблокированную клетку. Контур ложится на верхнюю поверхность; picker сначала использует GridMap collision, а при ещё не готовом physics space — ту же semantic геометрию клеток. Координата всегда возвращается как canonical `Vector2i`.

Targeted gates: `test_battlefield_resource.gd` проверяет toolbar, восемь кистей, непрерывную линию, трёхклеточный atomic Undo/Redo и save/reopen; `test_combat_arena_scenes.gd` — общий runtime/editor picker и четыре угла hover. `test_combat_grid.gd`, `test_combat_lab.gd`, `test_combat_camera_rig_preview.gd`, `test_combat_prototype.gd` сохраняют gameplay/camera parity.

### D2.1f — Rectangle, guided fill и visual brush swatches (v1.79)

1. В режиме `Поле боя` открыть второй selector рядом с кистью. `Кисть` сохраняет непрерывный drag; `Прямоугольник` после press показывает рамки всех клеток от anchor до hover; `Заливка` сразу подсвечивает связную область, но применяет её только после release.
2. Выбрать `Wet → Заливка` и нажать на нейтральную область. Клетки с другой высотой, blocking, group или исходной surface не входят в preview. Отпустить ЛКМ — один Ctrl+Z отменяет всю область, один Redo возвращает.
3. Выбрать `Высота + → Прямоугольник`, провести через 2×3 клетки и отпустить. Все шесть высот меняются один раз; Ctrl+Z восстанавливает шесть. Нажатие Esc до release убирает overlay без изменения Resource.
4. Выбрать `Фокус`: selector формы переключается на `Кисть` и блокируется; клик переносит единственный focus. Выбрать другую кисть — формы снова доступны.
5. Открыть dropdown кистей в 3D и Battlefield Inspector: Neutral/Wet/Ember/Frozen/Blocked/Height±/Focus имеют одинаковые цветные swatches и metadata. Это пока semantic legend; production tiles будут отдельной visual MeshLibrary.

Targeted gate `test_battlefield_resource.gd` проверяет 3 формы, visual swatches, Focus lock, прямоугольник 2×3 и synthetic guided-fill, который не пересекает соседнюю область другой высоты. Тест не фиксирует форму пользовательской E2-карты. Все D2 combat/arena/camera gates сохраняют parity.

### D2.1g — Authored visual Battlefield MeshLibrary (v1.80)

1. Перезапустить editor, открыть E2 arena и выбрать корень. Поле больше не выглядит как пять одинаковых одноцветных BoxMesh: Neutral имеет каменную рамку, Wet — голубые полосы, Ember — оранжевые emissive-трещины, Frozen — светлые грани, Blocked — тёмные hazard-полосы и прежнюю высоту.
2. Нажать `Тайлы…` в 3D toolbar. Inspector открывает `ember_battlefield_tiles.tres`; верхний preview показывает все пять meshes рядом с `0 · Neutral` … `4 · Blocked`, под ним зелёная диагностика ID/mesh/collision.
3. Открыть E3 и Combat Lab: визуальный стиль совпадает. Временно выбрать `CombatGridMap` и убедиться, что `Mesh Library` ссылается на тот же внешний `content/combat/tiles/ember_battlefield_tiles.tres`, а не локальный generated Resource.
4. Временно удалить collision shape или переименовать item в копии библиотеки: configuration warning арены и Inspector-диагностика называют точный ID. Вернуть исходную общую библиотеку; production-файл во время проверки не сохранять испорченным.
5. Нарисовать Wet/Ember/Blocked кистью и запустить Combat Lab. Semantic Resource определяет item ID, MeshLibrary только отображает его; movement, reactions, высота и Undo не меняются.

Targeted gate `test_battlefield_tile_library.gd` проверяет один resource path у base/E2/E3/Lab, ID 0–4, mesh, collision, shader pattern и пять Inspector preview instances. Все Battlefield/grid/arena/lab/camera/resolver gates проходят. Следующий visual срез может заменить primitive meshes voxel-art под теми же ID; resize/remap поля остаётся отдельным data gate.

## Общий план после v1.80

Актуальное решение и порядок принадлежат `docs/EMBER_PRODUCT_PLAN.md`, `docs/EMBER_EDITOR_UX_AUDIT.md` и этому плану. Порядок не менять массовой world-конверсией:

### D2.1h — Safe battlefield resize + deployment anchors (v1.81)

1. В Inspector и 3D toolbar автор задаёт width/depth, anchor переноса и видит preview: какие клетки/groups/focus/spawns сохранятся или будут потеряны.
2. Apply меняет все row-major arrays и deployment data одной Editor Undo/Redo action; Cancel не меняет Resource.
3. Party/enemy anchors рисуются отдельным объектным инструментом поверх той же canonical grid. Нельзя сохранить anchor вне поля, в blocker или два anchor одной стороны в одной клетке.
4. Ctrl+S, reopen и arena preview сохраняют layout; пользовательская E2-форма не фиксируется тестом, resize проверяется synthetic fixture.

Реализовано в v1.81. Ручная приёмка:

1. Открыть E2 arena, нажать `Размер…` в 3D toolbar. Inspector Battlefield Resource показывает width/depth и девять anchor-вариантов. Выбрать 9×7 + `Центр`: preview сообщает 35 сохранённых и 28 новых клеток без потерь.
2. Нажать Apply: поле, focus и точки сдвигаются на +1,+1, 3D preview перестраивается. Один Ctrl+Z возвращает 7×5 и все данные, один Redo снова делает 9×7. После проверки откатить к 7×5 и не сохранять тестовое расширение production E2.
3. Выбрать размер, который обрезает край. До Apply жёлтая строка называет потерянные клетки/точки. Если исчезает последняя точка героев или врагов, Apply блокируется красной диагностикой.
4. Включить `Поле боя`, выбрать `Точка героев` или `Точка врагов`. Клик по свободной клетке добавляет `Гn`/`Вn`, повторный клик снимает её; пипетка распознаёт точку. Shape принудительно остаётся одиночной кистью. Нельзя поставить точку на blocker/focus или снять последнюю точку стороны.
5. Запустить Combat Lab: герои/враги стоят на canonical deployment cells из E2/E3 Resource. Изменение точки в editor preview перемещает соответствующего тестового бойца без изменения hardcoded resolver formulas.

Targeted gate `test_battlefield_resource.gd` проверяет resize preview/offset/counts, atomic Undo/Redo всех arrays/focus/deployments, safe crop warning, десять palette tools, runtime placement и save/reopen signature. Battlefield tile/grid/resolver/arena/camera/lab gates сохраняют parity.

### D2.2a — Encounter Resource + library (v1.82)

1. Одна визуальная карточка encounter выбирает arena/battlefield и показывает состав/preview; ручной ID остаётся expert fallback.
2. Resource хранит ссылки и deployment profile, но не копирует cell arrays или action formulas.
3. Validation ловит отсутствующую arena, несовпадающее поле, конфликт anchors и пустую сторону; Undo/Redo/save/reopen обязательны.

Реализовано в v1.82. `EmberEncounterResource` хранит только ссылки на прежние Battlefield/arena, ordered ID участников текущего прототипа, result flags и отдельные outcome action chains. Cell arrays, формулы действий и временный combat state не дублируются. `colored_crossing_demo.tres` — первая canonical встреча; её мини-карта используется и Inspector, и визуальным picker цепочки.

Ручная приёмка:

1. В FileSystem открыть `content/combat/encounters/colored_crossing_demo.tres`. Сверху Inspector видны мини-карта, состав, зелёная validation и кнопки `Открыть данные поля` / `Открыть арену в 3D`.
2. Изменить название, состав или Battlefield, выполнить Ctrl+Z/Ctrl+Y, сохранить и переоткрыть. Ошибка количества starts, пустая сторона, неизвестный ID или отсутствующая arena должны быть названы прямо в Inspector.
3. Открыть цепочку действия и добавить `Начать бой (финал)`. Кнопка `▦` показывает визуальную библиотеку встреч; выбрать `Засада у цветной переправы`. Шаг после боя не допускается: продолжение победы/поражения назначается в Encounter Resource.
4. Запустить Combat Lab. В списке режимов есть `Встреча · Засада у цветной переправы`; она использует выбранное поле, состав и authored deployment cells.

Targeted gate `test_encounter_resource.gd` проверяет catalog, validation, visual miniature, Inspector navigation, save/reopen, roster/deployment projection и terminal `start_battle` normalization.

### D2.2b — Exploration battle action + result lifecycle (v1.82–v1.83)

1. В action chain добавлен terminal шаг `Начать бой` с visual encounter picker. Сценарий: `talk → battle`; `set_flag`/награда/диалог после исхода задаются как `victory_action_script_id` или `defeat_action_script_id` самой встречи.
2. Battle session хранит только process-local encounter ID, return scene path и outcome action ID; Node/UI references через смену сцены не переносятся.
3. Victory/defeat возвращает в исходную сцену, использует прежний save-position restore и затем запускает outcome chain через новый `InteractionUI`. Source interact завершается перед terminal scene switch.
4. Fade и `scene_changed` lifecycle проходят несколько последовательных боёв без утечки listener/session state.

В v1.82 реализован функциональный переход/возврат. В v1.83 завершён result UX: авторский бой запрашивает fullscreen, действия доступны в круговом HUD у активного героя, исход открывает центральное окно `Продолжить / Повторить / Вернуться`, а смена сцен закрыта fade. `EmberCombatTransition` ставит result guard до изменения progress; повторный UI-сигнал не может второй раз выдать flag/reward. `test_combat_encounter_transition.gd` действительно меняет сцены `agent_sandbox → Combat Lab → agent_sandbox`, побеждает через HUD, дважды посылает Continue и проверяет ровно один flag + одну награду после создания нового UI.

Ручная приёмка v1.83:

1. Начать `Засаду у цветной переправы` из мира: игровое окно занимает весь экран, а вокруг активного героя видны движение `M`, команды `1–9` и защита `G`. При вращении/движении камеры круг остаётся у героя.
2. Выбрать клетку: круг переезжает к staged-позиции. Выбрать действие мышью или shortcut, затем допустимую цель: выбор цели один раз коммитит staged movement + действие без отдельного `F`. `G` сразу завершает ход защитой.
3. Победить: поверх поля появляется центральное `ПОБЕДА` с видимой кнопкой `Продолжить`. Двойное нажатие не дублирует переход/награду; после fade загружается исходная локация и outcome chain.
4. При поражении доступны `Повторить` без изменения world progress и `Вернуться` с defeat outcome.

### D2.2b.1 — Tactical HUD composition (v1.84)

1. Остановить текущий embedded playtest и запустить проект заново. Игра открывается отдельным fullscreen-процессом: Godot Game bar и рамка `1600×900` отсутствуют.
2. 3D-поле занимает viewport. Слева отдельной узкой колонкой показана очередь, снизу слева — самостоятельная console/log, снизу справа — компактный прогноз. Большого HSplit/двухколоночного фона нет; очередь не растягивается поперёк карты.
3. В 3D боковой список действий не дублирует radial menu. Кнопки radial имеют читаемую тёмную подложку, цветной контур и shortcut; 2D diagnostic по-прежнему показывает обычный список для мыши.
4. Камера, staged movement, result modal и world return продолжают работать под свободными HUD-слоями.
5. Нажать `M`: radial menu скрывается, после выбора клетки возвращается уже у staged destination. Выбрать атаку: кольцо скрывается до клика по допустимому противнику; клик выполняет ход, после enemy resolver кольцо появляется у следующего героя. `Esc` отменяет targeting, следующий `Esc` открывает паузу.
6. В pause menu проверить `Продолжить`, `Повторить бой`, `Закрыть игру` (последнюю кнопку — в отдельном тестовом запуске). В нижней левой консоли выполнить `help`, `units`, `kill enemies`, затем `reset`: победа должна открыть обычный result modal, а награда — применяться только кнопкой результата.

`test_combat_lab.gd` проверяет fullscreen-field anchors, независимые позиции turn order/console/command card, отсутствие дублирующего 3D action list и hide/restore radial menu в обеих фазах targeting. Godot официально не поддерживает смену window mode при Game Embedding, поэтому плагин ставит editor setting `run/window_placement/game_embed_mode = -1`; headless gates эту пользовательскую настройку не меняют.

### Exploration pause/quit menu (v1.87)

1. Запустить `agent_sandbox`, `fan_town` и любой интерьер: справа сверху видна одна кнопка `Меню · Esc`.
2. Нажать `Esc`: мир и игрок останавливаются, доступны `Продолжить`, `Сохранить игру`, `Сохранить и закрыть игру`. Повторный `Esc` продолжает игру.
3. Открыть сумку, журнал, диалог или магазин и нажать `Esc`: сначала закрывается этот экран, пауза поверх него не открывается. Следующий `Esc` открывает меню игры.
4. Сохранить через меню и проверить сообщение об успехе. Кнопку закрытия проверять в отдельном запуске: она вызывает прежний save owner, снимает pause и завершает только игровой процесс.
5. Открыть меню, продолжить и перейти через дверь: следующая сцена не должна остаться paused.

Targeted gate `test_explore_pause_menu.gd` запускает реальную `agent_sandbox`, проверяет map-owned UI/player wiring, приоритет inventory, pause/resume и ручное сохранение без вызова destructive quit в тесте.

### Battle result → quest counters (v1.88)

1. Открыть `colored_crossing_demo.tres`: в верхней карточке встречи видны награда победы и подписанный ключ события конкретной встречи.
2. Запустить встречу и победить. В result modal до возврата видно `Монета ×5`; это preview прежней victory chain, инвентарь ещё не изменён.
3. Нажать `Продолжить`: после возврата награда показывается и выдаётся один раз. В журнале `Q` боевые цели обновляют число, а повторный сигнал Continue не увеличивает ни предметы, ни счётчики.
4. В Ember Graph открыть `Задания`, выбрать цель и переключить `Событие / флаг` на `Боевой счётчик`. Выбрать подписанное событие (`любые победы`, конкретная встреча, все враги или тег) и поле `Нужно`; ручной bind к объекту для такой цели не требуется.
5. Сохранить, переоткрыть Resource и проверить Undo/Redo. Последовательность целей работает прежними синими связями: закрытая цель не накапливает боевое событие до выполнения prerequisites.

Targeted gates: `test_combat_result_bridge.gd`, `test_combat_encounter_transition.gd`, `test_quest_journal_authoring.gd`, `test_graph_workspace.gd`.

### Quest Flow orphan cleanup (v1.89)

1. В Inspector удалить взаимодействие/старую цепочку с объекта, затем в задании открыть `Все связи` либо поток соответствующей цели.
2. Фиолетовая action-нода без зелёного объекта показывает `Удалить лишнее`; action-нода выбранного объекта вместо этого показывает безопасное `Отвязать`.
3. Нажать `Удалить лишнее`: исчезает только показанный quest-шаг. Если в цепочке были другие действия, они остаются; если шаг был последним, пустой Action Resource удаляется.
4. Проверить Ctrl+Z/Ctrl+Shift+Z: Resource и нода возвращаются/удаляются, граф обновляется без перезапуска редактора.
5. Dialogue writer не получает глобальную кнопку удаления и по-прежнему открывается для правки в Dialogue Graph.

Targeted gates: `test_action_chain_authoring.gd`, `test_graph_workspace.gd`.

### Authored combat units (v1.90)

1. Открыть `content/combat/encounters/colored_crossing_demo.tres`: под мини-картой видны отдельные строки героев и врагов с цветом, именем, ID, HP и скоростью.
2. Нажать строку бойца — Inspector открывает его `.tres` с цветным/portrait preview, сводкой и validation. Изменить HP либо цвет, сохранить и запустить бой: HUD/3D и snapshot используют новое значение без правки resolver-кода.
3. В Encounter поменять двух участников местами кнопками ↑/↓, проверить 3D расстановку, Ctrl+Z/Redo и save/reopen. `+ Добавить` предлагает только бойцов нужной стороны, ещё не находящихся в составе; последнего участника стороны удалить нельзя.
4. У врага должен быть выбран существующий `AI Profile`; отсутствующая ссылка показывает ошибку и блокирует валидность встречи. Combat tags продолжают попадать в result counters.
5. Повторить `colored_crossing_demo`: реакции, timeline, защита, victory modal, награда и возврат в мир работают как до миграции.

Targeted gates: `test_combat_unit_resource.gd`, `test_combat_prototype.gd`, `test_encounter_resource.gd`, `test_combat_lab.gd`, `test_combat_result_bridge.gd`, `test_combat_encounter_transition.gd`.

### Authored combat actions (v1.91)

1. Открыть любой Resource из `content/combat/actions/`: Inspector показывает цвет/иконку, сводку силы, дальности, задержки, цели и effect preset. Несовместимые стихия/цель/эффект дают понятную validation-ошибку.
2. Открыть `content/combat/units/mira.tres`: вместо raw `Action IDs` видны карточки действий. Кнопка карточки открывает единый action Resource; ↑/↓ меняют порядок в radial menu, × удаляет, Ctrl+Z/Redo восстанавливает точный список.
3. Нажать `+ Выбрать действие из библиотеки…`: поиск и цветные tiles показывают только ещё не назначенные действия. При добавлении optional icon используется и в библиотеке, и в боевом HUD; без иконки остаётся authored color swatch.
4. Для врага поле `Основное действие AI` предлагает только его назначенные действия. Удаление выбранного AI action безопасно выбирает оставшееся; последнюю карточку удалить нельзя.

### Combat content library, Earth and Wind (v2.63.1)

1. Перезапустить Godot и выбрать `Проект → Инструменты → Ember: Open Combat
   Content`. В `Ember Graph` открывается единая библиотека с вкладками
   `Эффекты`, `Умения и магия`, `Герои и существа`; поиск фильтрует текущий
   список. Слева видны отдельные колонки `Название / ID / Связи`, справа —
   закреплённая карточка и те же canonical данные. Split перетаскивается без
   обрезания кнопок на 1600×900 и 1280×720.
2. Открыть `earth_wall`: цепочка содержит общий `Каменная преграда`. Удалить
   шаг, нажать Ctrl+Z/Redo и вернуть его через библиотеку. Создать копию эффекта
   с новым stable ID, убедиться, что исходный Resource не изменился; ненужную
   тестовую копию удалить через FileSystem.
3. Создать заведомо неполный тестовый Resource и нажать `Сохранить .tres`:
   библиотека показывает validation errors и не записывает его. После
   исправления кнопка сохраняет тот же canonical `.tres`.
4. Запустить standalone Combat Lab, дождаться хода Миры и открыть `Магия`.
   `Каменный заслон` подсвечивает только пустые клетки в радиусе; после клика
   появляется blocker, через него нельзя пройти и он закрывает LOS. Повторный
   старт боя возвращает исходное поле.
5. `Вздыбить землю` поднимает выбранную клетку на один уровень. Следующий
   расчёт движения, дальности и LOS использует новую высоту; исходный
   Battlefield Resource и save v2 не меняются.
6. Сначала наложить Wet/Burning, затем применить `Раздувку` к клетке источника.
   Состояние детерминированно появляется у соседних бойцов (обеих сторон), Wet
   также расходится по соседним проходимым клеткам. Неподготовленная клетка не
   является допустимой целью.
7. В `Герои и существа` открыть любого бойца, назначить одно из трёх действий,
   изменить порядок и проверить Ctrl+Z. Для production-встречи действие
   появляется только после явного назначения; лабораторная выдача Мире не
   меняет её canonical Unit Resource.
8. Изменить у действия power/range/delay/color, сохранить и повторить Combat Lab: preview, target legality, timeline и HUD используют новое значение. Elemental effect preset продолжает вызывать прежнюю единую формулу resolver, а Resource не содержит второй боевой скрипт.
9. Проверить мышью выбор строк, resize split и кнопки связей; клавиатурой —
   Ctrl+F/N/D/S, Tab и стрелки Tree. Двойной клик открывает выбранный `.tres` в
   Inspector. Empty/error состояния не должны сдвигать основную панель действий.

Targeted gates: `test_combat_action_resource.gd`, `test_combat_unit_resource.gd`, `test_combat_prototype.gd`, `test_combat_grid.gd`, `test_encounter_resource.gd`, `test_combat_lab.gd`, `test_combat_result_bridge.gd`, `test_combat_encounter_transition.gd`.

### Authored combat AI profiles (v1.92)

1. Открыть `content/combat/ai_profiles/opportunist.tres`, `relentless.tres` и `guardian.tres`: Inspector показывает цветную карточку, понятные приоритеты цели/действия/реакции, low-HP поведение и validation.
2. Открыть enemy Unit Resource: под карточками действий виден `Профиль AI` со swatch и подписанным списком. Поменять профиль, открыть его кнопкой, проверить Ctrl+Z/Redo и save/reopen.
3. В Combat Lab ранить одного героя: `opportunist`/`relentless` выбирают минимальное текущее HP с детерминированным ID tie-break. Если доступное действие создаёт подписанную reaction, `opportunist` предпочитает его обычному порядку карточек.
4. Опустить HP стража до 35% или ниже: `guardian` выбирает назначенный `defend` на себя. Выше порога он использует прежний первый доступный удар; отсутствие defend безопасно означает продолжение обычной оценки.
5. Проверить, что target range, valid targets, reaction preview, commit и timeline не обходятся профилем. AI выбирает один из прежних pure previews; результат применяет только общий combat commit.

Targeted gates: `test_combat_ai_profile_resource.gd`, `test_combat_action_resource.gd`, `test_combat_unit_resource.gd`, `test_combat_prototype.gd`, `test_combat_grid.gd`, `test_encounter_resource.gd`, `test_combat_lab.gd`, `test_combat_result_bridge.gd`, `test_combat_encounter_transition.gd`.

### Visual enemy loot tables (v1.93)

1. Открыть enemy Unit Resource: под AI Profile виден `Лут` с иконкой, подписанным picker и кнопкой `Открыть`. Поменять таблицу и проверить Ctrl+Z/Redo; raw Resource field скрыт.
2. Открыть `content/combat/loot_tables/swamp_elite_drops.tres`: строки показывают настоящие item icons, названия/ID, шанс, min/max и удаление. `+ Добавить предмет из библиотеки…` открывает прежнюю визуальную item library; замена и удаление отменяются через Ctrl+Z.
3. Некорректный item ID, пустая таблица, шанс вне 0–100, max меньше min или дубликат предмета должны дать validation, а не тихий runtime fallback. Сохранить/переоткрыть `.tres` без изменения `content_signature()`.
4. Победить в `colored_crossing_demo`: result modal заранее показывает фиксированные пять монет и рассчитанный лут трёх врагов. Повторный refresh того же результата не меняет список.
5. Нажать Continue дважды: после возврата каждая награда показывается прежней reward card и выдаётся ровно один раз. Фиксированная victory chain и generated loot проходят одну `InteractionUI` queue; `EmberCombatResult` сам inventory не меняет.

Targeted gates: `test_combat_loot_table_resource.gd`, `test_combat_unit_resource.gd`, `test_combat_result_bridge.gd`, `test_combat_encounter_transition.gd` плюс прежние action/AI/prototype/grid/encounter/lab gates.

### Central loot library UX (v1.94)

1. Открыть верхнюю вкладку `Ember Graph` и выбрать режим `Лут врагов` либо вызвать `Проект → Инструменты → Ember: Open Loot Library`. Graph canvas должен замениться полноразмерным каталогом, а лишние кнопки нод/сохранения — исчезнуть.
2. Слева видны все Loot Table как плитки с иконкой первого предмета, названием, ID и числом позиций. Поиск находит таблицу по названию/ID, описанию и любому входящему предмету.
3. Один клик по плитке открывает справа canonical таблицу: item icons, шанс, min/max, add/replace/remove. Изменение через этот экран видно при открытии того же `.tres` и у назначенного врага; Ctrl+Z/Redo использует Editor UndoRedo.
4. `Открыть в Inspector` должен передать тот же Resource штатному Inspector. Переключение обратно к цепочкам/диалогам/заданиям восстанавливает прежний GraphEdit без сброса их draft/camera contract.

Targeted gates: `test_graph_workspace.gd`, `test_combat_loot_table_resource.gd`.

### Shared grid movement for enemy AI (v1.95)

1. Открыть любой `content/combat/ai_profiles/*.tres`: в обычных свойствах есть `Позиционирование`, а карточка сверху явно показывает `Держать позицию` либо `Искать клетку для действия`. Сохранить, закрыть и открыть Resource; значение не должно сбрасываться.
2. Запустить E2. Первый враг с ближним `Ударом врага` не атакует через всё поле: он выбирает достижимую клетку и делает подписанный в журнале ход сближения. На следующем подходящем ходу он может переместиться и ударить одной командой.
3. Поставить между врагом и героем blocker, занятую клетку и перепад выше одного уровня. Враг использует только подсвечиваемые для обычного бойца клетки и не проходит сквозь эти ограничения.
4. Повторный reset даёт тот же выбор клетки/цели. Preview не меняет исходный snapshot; движение, урон, timeline delay и status decay появляются только после общего `Combat.commit()`.

Targeted gate: `tools/test_combat_ai_profile_resource.gd` проверяет move+action, movement-only pursuit, occupancy, чистоту snapshot, детерминизм, Inspector и save/reopen; дополнительно проходят grid/prototype/lab/transition tests.

### V1 — Unified voxel scale and Tile Kit

1. ✅ v1.97: `voxelsPerBlock` model metadata: absent = legacy 16, новые environment tiles = 32. `sizeBlocks` остаётся gameplay footprint. С v1.98 writable metadata находится в Godot Resource.
2. ✅ v1.97: один normalized block-space builder обслуживает source preview/world prefab и даёт адаптер для battle 1.2 без remesh. Разные physical sizes больше не кэшируются в mesh по `model_id`.
3. Battle cell остаётся одним блоком; один semantic elevation level на первом kit равен половине блока. Точный Godot world scale задаёт placement adapter.
4. Сначала заменить пять v1.80 primitive items voxel-kit под прежними ID, затем перевести только одну sandbox world surface. Массовый reimport карт запрещён до save/reopen/collision/manual gate.

Ручная приёмка v1.97–v1.98:

1. В Godot voxel-библиотеке `vox_fan_anvil` помечен как `Источник: Godot Resource`, остальные до переноса — как очередь legacy import.
2. Открыть `content/voxel_models/vox_fan_anvil.tres`: density/footprint, palette, voxel data, physics и light metadata переживают save/reopen; абсолютного пути к JOI нет.
3. Добавленные legacy 16 и будущая native 32 модель занимают один блок мира; battle adapter даёт прежний размер 1.2 без remesh.
4. Пересобрать native pilot и один legacy prefab, проверить viewport, collision, save/reopen и то, что файл карты/placement transforms не изменились.
5. Задать заведомо отсутствующий `ember/pack_path`: native pilot по-прежнему строит preview/prefab. Legacy queue ожидаемо недоступна до запуска importer с подключённым архивом.

Targeted gates: `test_native_voxel_resource.gd`, `test_voxel_tile_scale.gd`, `test_voxel_prefab_rebuild.gd`, `test_voxel_preview_renderer.gd`, `test_voxel_visual_library.gd`. JOI tests относятся только к сохранности frozen import archive и больше не являются authoring gate нового контента.

### Visual voxel migration queue (v1.99)

1. Открыть `Ember Migration → Voxel-префабы → Библиотека` без открытой карты. Верхняя строка показывает число Godot Resources, ожидающих импорт и общий размер каталога.
2. Выбрать legacy-карточку: описание говорит `Legacy import queue`, доступно `Перенести в Godot`, а `Открыть Godot Resource` выключено. Preview остаётся видимым.
3. Нажать перенос: карточка становится native, очередь уменьшается на один, prefab пересобирается, доступно открытие `.tres`; `.vox/.json` не меняются.
4. Нажать Ctrl+Z: карточка возвращается в очередь и derived prefab снова соответствует legacy source. Redo повторяет перенос. Добавление модели в сцену остаётся отдельной кнопкой и без Map даёт понятную подсказку.
5. На выбранном `EmberVoxelProp` нижняя панель показывает тот же owner. Старых кнопок `Эмиссия/Прозрачность в JOI` и настройки `ember/joi_editor_url` больше нет.

Targeted gates: `test_voxel_migration_queue.gd`, `test_migration_workflow_layout.gd`, `test_voxel_visual_library.gd`, `test_native_voxel_resource.gd`.

### Style-first Voxel Surface pilot (v2.00)

1. Открыть main-screen `Ember Graph` и выбрать `Voxel Surface · pilot`.
2. Убедиться, что виден единый 4×4 холст, а золотые линии показывают только границы gameplay-блоков — поверхность не должна выглядеть шестнадцатью раздельными плитками.
3. Проверить LMB-инструменты `Нарастить`, `Вырезать`, `Красить`; сравнить кисть 1/4/8 и `Coarse 2×2×2`.
4. RMB/MMB вращает, колесо приближает; `Камера мира` и `Камера боя` возвращают читаемые ортографические presets.
5. Удерживать LMB и быстро провести длинную диагональ и кривую. Линия должна оставаться связной без дыр между отсчётами мыши; preview обновляется во время движения.
6. Один Ctrl+Z отменяет весь drag от нажатия до отпускания, Redo возвращает его. Начать другой drag и нажать Esc до отпускания — форма должна вернуться к состоянию перед жестом без записи в историю.
7. Нажать `Сохранить .tres`, сменить раздел, снова открыть pilot — форма должна совпасть.
8. Не оценивать пока material channels, production chunks, collision и gameplay-height authoring: v2.00–v2.02 проверяют связный volumetric floor, масштаб 32-grid и удобство базовой кисти.

Критерий продолжения: пользователь подтверждает, что наращивание/вырезание даёт нужное ощущение цельной handcrafted-диорамы. Drag-stroke закрыт в v2.02; следующие независимые срезы добавляют height slices и channel painting. Только затем проектируется chunked Surface Resource.

Targeted gates: `test_voxel_surface_sculpt.gd`, sculpt projection в `test_graph_workspace.gd`, `test_native_voxel_resource.gd`.

V2.01 performance gate: повторить несколько мазков кистями 1/4/8 в центре и на золотой границе блока. Короткая локальная пересборка допустима; пауза полного холста после каждого клика — регрессия. На границах preview-chunks не должно быть щелей или лишних внутренних граней; Ctrl+Z/Redo обновляют те же локальные участки.

V2.02 continuous-stroke gate: провести LMB через несколько preview-chunks с высокой скоростью. Видимый путь остаётся связным, отпускание не вызывает повторного скачка mesh, а одна операция Undo/Redo восстанавливает весь жест. Targeted test проверяет связность интерполяции и exact before/after канонического массива.

V2.03 relief-brush gate:

1. Выбрать `Поднять рельеф`, радиус 16 и `Предел 8 vox`: hover-конус показывает широкое основание на поверхности и вершину вверх.
2. Удерживать LMB и несколько раз пройти по одному месту, не отпуская кнопку. Центр не должен подняться выше восьми art voxels относительно формы в момент нажатия; край формирует более низкие ступени без цилиндрической стены.
3. Отпустить и начать второй жест: теперь форму можно осознанно поднять ещё на новый предел. Один Ctrl+Z отменяет только целиком последний жест.
4. Повторить с `Углубить рельеф`: конус смотрит вниз, центр опускается до выбранного предела, края слабее. Esc до отпускания восстанавливает исходную поверхность.
5. Сравнить пределы 1/4/8/16, радиусы 4/8/16 и `Coarse 2×2×2`; сохранить/reopen. Наращивание у верхней границы холста безопасно ограничивается `height_voxels`, углубление не проходит ниже нулевого слоя.

Targeted gate: `test_voxel_surface_sculpt.gd` проверяет точный center cap, меньший edge falloff, progressive targets без превышения cap и прежние continuous/Undo/save контракты.

V2.04 time-based buildup gate:

1. Выбрать `Поднять рельеф`, предел 16 и рост 2 vox/сек. Коротко щёлкнуть — остаётся низкий отпечаток; удерживать на том же месте — центр заметно растёт примерно по два art-вокселя в секунду.
2. Не отпуская LMB, дождаться 16/16: дальнейшее удержание не меняет высоту. Строка состояния показывает текущий прогресс `N/16`.
3. Сравнить рост 2 и 8 vox/сек. Финальная форма и предел одинаковы, меняется только время достижения; частое движение мышью внутри одной колонки не ускоряет buildup.
4. Перетащить кисть на новую колонку: там рост начинается с одного voxel, а не мгновенно наследует время предыдущего места. Выход курсора за viewport/поверхность ставит buildup на паузу.
5. Повторить для углубления, Esc, Ctrl+Z/Redo и save/reopen. Весь путь между pointer-down/up остаётся одной операцией истории.

Automated gate прогоняет последовательные targets 1 → 4 → 8 относительно одного baseline и затем точный cap/repeat для Raise/Lower.

V2.05 buildup performance gate:

1. Выбрать радиус 16, предел 16 и рост 8 vox/сек; удерживать LMB на границе четырёх preview-chunks. Нарастание остаётся управляемым без общего зависания на каждом уровне.
2. Preview может догонять каноническую форму по одному чанку за кадр, но не должен оставлять постоянных щелей; отпускание, Esc и Undo приводят все чанки к одному точному состоянию.
3. Во время удержания внешний Inspector/каталог не должны перезагружаться восемь раз в секунду: `Resource.changed` публикуется один раз на pointer-up, Undo/Redo — прежним action callback.
4. Targeted test сравнивает сумму индексов всех direct Packed preview-chunks с полным runtime mesh и один регион со старым Dictionary path. На текущем pilot direct path около 9 мс против 13 мс; существенное обратное ухудшение — регрессия.

V2.05.1 hotfix gate: `test_map_transition.gd` и отдельный `--check-only ember_explore_state.gd` проходят в одном editor состоянии; progress/defeat/inventory/health/quest tests подтверждают настоящий typed gameplay owner. Открытие/resize `Voxel Surface · pilot` и полный `test_graph_workspace.gd` не выводят предупреждение о ручном изменении размера растянутого SubViewport.

V2.06 low-latency relief gate:

1. Удерживать `Поднять/Углубить` с радиусом 16 на границе чанков. Горка/впадина должна расти без регулярного рывка, пока LMB зажат.
2. Во время удержания разрешён derived heightfield draft: он показывает верх и открытые ступени, но не владеет voxels и не сохраняется.
3. После pointer-up draft по одному чанку заменяется точным volumetric mesh. Форма, боковые грани, прозрачные surfaces, Undo/Redo и save/reopen совпадают с canonical Resource.
4. Targeted benchmark печатает `Exact -> Draft`; на pilot текущий диапазон около `8.5–8.9 ms -> 1.48–1.58 ms`. Draft, который перестал быть быстрее exact, считается регрессией.
5. `test_voxel_preview_renderer.gd`, `test_native_voxel_resource.gd`, `test_voxel_prefab_rebuild.gd`, `test_voxel_tile_scale.gd` и `test_voxel_surface_sculpt.gd` проходят после перехода общего точного mesher на indexed `ArrayMesh`.

V2.06.1 cache-stable transition gate: `ember_player.gd` и `test_map_transition.gd` отдельно проходят `--check-only`; route test использует только `CharacterBody3D` body/position boundary и не требует разрешения имени `EmberPlayer` из editor cache. Полный `test_map_transition.gd`, `test_defeat_respawn.gd` и `test_camera_relative_movement.gd` проходят, поэтому ослабления runtime player contract нет.

V2.07 addon/cached-gesture gate:

1. Перезапустить Godot и открыть `Voxel Surface · pilot`: Output содержит `v2.07`, а отсутствие/наличие addon не меняет `.tres` и набор кистей.
2. Радиусом 16 удерживать Raise/Lower на границе четырёх чанков. Во время LMB показывается дешёвый draft без ритмичного подвисания; после отпускания точная greedy-сетка догоняет по одному чанку за кадр.
3. Проверить Esc и один Ctrl+Z/Redo: live-buffer всего жеста обязан восстановиться целиком; save/reopen совпадает с показанной точной формой.
4. `test_voxel_tools_backend.gd` проверяет native ZXY/palette/scale, cached relief parity и доступность GDExtension. Удаление `addons/zylann.voxel` должно оставить редактор работоспособным через штатный fallback; это отдельный capability smoke, не миграция данных.

V2.08 incremental-relief gate:

1. Output после перезапуска содержит `v2.08`. Выбрать Raise, радиус 16, предел 16 и удерживать LMB на уже высокой части холма: следующий уровень не должен снова обходить или регистрировать нижние слои этого же жеста.
2. Повторить Lower над глубокой впадиной. Первый уровень может быть самым дорогим из-за поиска затронутых колонок; поздние уровни не должны становиться дороже по мере глубины.
3. `test_voxel_surface_sculpt.gd` строит Raise и Lower двумя путями — одним вызовом до высоты 8 и восемью incremental delta — и требует byte-identical buffer. Сумма размеров delta обязана совпасть с one-shot change-set: одна ячейка не может повторно входить в следующие уровни.
4. `test_voxel_tools_backend.gd` печатает `first / last / peak / total` для radius-16 жеста. Числа зависят от машины; регрессией считается рост позднего уровня вместе с уже созданной высотой. Esc, один Ctrl+Z/Redo и save/reopen остаются обязательными ручными проверками.

V2.09 overlap-aware stroke gate (performance принят; radius/2 visual spacing заменён v2.10 после обнаружения щелей в высоком гребне):

1. Выбрать Raise radius 16 и одним удержанием LMB провести широкую полосу туда, затем обратно по уже поднятым 1–2 слоям. Возврат не должен зависать и не должен повторно добавлять ту же оболочку.
2. Остановиться на ранее поднятой точке, не отпуская LMB. Рост продолжается с достигнутого этой точкой уровня, а не пересчитывает уровни от baseline и не ждёт повторного прохождения уже достигнутой высоты.
3. Быстро провести мышь через весь canvas. События одного editor-frame coalesce в один endpoint. Экспериментальный radius/2 stamp spacing этого среза больше не является текущим контрактом: его visual gate провалился и заменён swept-сегментом v2.10.
4. `test_voxel_surface_sculpt.gd` проверяет нулевой change-set обратного overlap-прохода. `test_voxel_tools_backend.gd` печатает `relief sweep forward/revisit`; повторный проход обязан иметь `0 revisit changes`.

V2.10 continuous swept-relief gate:

1. Выбрать Raise radius 16 / height 8–16 и быстро провести прямую и диагональную полосу. Между позициями mouse events не должно быть отдельных конусов, щелей или отверстий: центральный гребень является непрерывной линией полной текущей высоты.
2. Не отпуская LMB, провести обратно по гребню. Overlap-кэш v2.09 остаётся активным: готовая оболочка не меняется и не вызывает прежнего фриза.
3. Swept-капсула вычисляет falloff от всего coalesced X/Z-сегмента, а не от разреженных stamp-центров. Add/Remove/Paint продолжают использовать прежний поклеточный `line_cells()` и не меняют форму.
4. `test_voxel_surface_sculpt.gd` проверяет top и заполненность каждого voxel центральной линии 56-voxel сегмента. `test_voxel_tools_backend.gd` требует `0 revisit changes`; ориентир текущей машины — примерно `10.5 ms -> 1.1 ms` для forward/revisit radius-16 полосы.

V2.11 hollow-shell experiment gate:

1. Выбрать `Поднять оболочку · test` и рядом нарисовать ту же гору обычным `Поднять рельеф`. Снаружи обе обязаны иметь непрерывный верх и закрытые боковые перепады; shell не должна показывать щели при world/battle camera presets.
2. Продолжить удержание и пройти назад по области. Верхняя оболочка передвигается вверх, а её прежнее внутреннее положение очищается; один Ctrl+Z/Redo и save/reopen восстанавливают точный buffer.
3. Не использовать experimental shell как production terrain contract: текущий fixed PackedByteArray не уменьшается, stock exact mesher видит внутреннюю нижнюю сторону, а последующий разрез может открыть полость. Solid Raise остаётся default.
4. `test_voxel_surface_sculpt.gd` проверяет полный верх, четыре направления стенок, пустой interior, incremental parity и сравнение occupancy/mesh. Текущий fixture: `2 548 / 10 316` changed voxels, но `74 550 / 43 302` exact mesh indices для shell/solid. Backend benchmark фиксирует примерно `26 / 21 ms` расчёта длинной полосы; это R&D baseline, не заявка на performance win.

V2.12 shell controls gate:

1. Для `Поднять оболочку · test` последовательно выбрать `1`, `4`, `16`, `32 vox/сек`, каждый раз начать новый мазок на ровной области и держать одинаковое время. Статус обязан показывать выбранное число; 1 растёт заметно медленно, 32 быстро достигает cap.
2. Проверить все радиусы `1/2/4/6/8/12/16/24/32` прямым и диагональным swept-мазком. Размер cursor и реальный footprint совпадают; прежнего скрытого clamp 16 нет.
3. Height cap предлагает `1/2/4/8/12/16/20/24`. Скорость не может поднять центр выше cap или верхней Y-границы canvas.
4. `test_voxel_surface_sculpt.gd` проверяет time-based shell gains и radius-32 formula; `test_graph_workspace.gd` проверяет полный набор metadata в UI. Backend печатает radius-32 first-stamp baseline (~33 ms): XL не должен становиться default и оценивается вручную отдельно от обычных 4–16.

V2.13 fixed-plane gate:

1. Выбрать `Выровнять площадку`, поставить радиус 8 и нажать LMB на нужной высоте: эта первая поверхность становится образцом до отпускания кнопки.
2. Не отпуская LMB, провести через низкую и высокую часть холста. Низ достраивается выбранным цветом, верх срезается, а вся полоса остаётся на одной высоте без дыр и зависаний на повторном проходе.
3. Вернуться по готовой полосе тем же жестом: форма больше не меняется. Отпустить кнопку — один Ctrl+Z возвращает одновременно поднятые и срезанные колонки, Redo восстанавливает площадку.
4. Повторить с `Coarse 2×2×2`: итоговая высота должна закончиться полным двухвоксельным слоем. `Предел` и `vox/сек` для этой кисти скрыты, потому что она следует образцу, а не растёт со временем.

Targeted gates: `test_voxel_surface_sculpt.gd` и sculpt projection в `test_graph_workspace.gd`.

V2.14 hollow-depression gate:

1. Сначала `Поднять оболочку · test` создать широкую полую горку. Не отпуская или новым жестом выбрать `Углубить оболочку · test`, меньший радиус и провести впадину внутри поднятой формы.
2. Верх должен двигаться вниз с выбранной скоростью до cap; старое положение верха исчезает, скрытая полость не заполняется горизонтальными слоями, а по краю впадины нет открытых боковых дыр.
3. На обычном сплошном основании сравнить с `Углубить рельеф`: внешний результат совпадает. Различие кистей относится только к ownership невидимого объёма внутри уже полой оболочки.
4. Проверить радиусы, `Coarse`, Esc и один Ctrl+Z/Redo. Строка статуса явно пишет `Оболочка вниз`; выбранный цвет используется только когда новой поверхности не существовало внутри полости.

Targeted gates: `test_voxel_surface_sculpt.gd`, `test_voxel_tools_backend.gd`, sculpt controls в `test_graph_workspace.gd`.

V2.15 Surface camera navigation gate:

1. RMB вращает камеру вокруг текущей точки, MMB перетаскивает вид по поверхности, колесо меняет ортографический масштаб. MMB не должен менять высоту target или случайно начинать sculpt stroke.
2. После сдвига вращение RMB продолжается вокруг нового офсета. `Центр` возвращает середину холста, сохраняя угол/zoom; `Камера мира` и `Камера боя` возвращают полный preset вместе с центральным offset.
3. Camera navigation является только editor view state: voxels, dirty marker и история Undo не меняются.

Targeted gate: camera controls и target/reset projection в `test_graph_workspace.gd`; `test_voxel_surface_sculpt.gd` остаётся data/brush gate.

V2.16 neighbor-height smoothing gate:

1. Создать Raise/Lower несколько одиночных зубцов и выбрать `Сгладить ступени`, силу 1 или 2. Один LMB-жест смягчает локальные перепады не больше выбранного числа vox; крупная терраса не превращается сразу в плоскость.
2. Повторный проход новым жестом продолжает smoothing. Возврат по уже обработанной части внутри того же удержания ничего не меняет и не вызывает фриза.
3. Проверить силы `1/2/4/8`, радиусы до 32 и `Coarse 2×2×2`. Пустая authored дыра остаётся пустой; её закрывают только Add/Level. Один Ctrl+Z возвращает весь мазок, Esc отменяет live-результат.
4. Performance ориентир текущего headless fixture после построенного при открытии derived heightfield: radius-32 sweep около `14 ms`, revisit около `2.3 ms` и `0` changes. Полный heightfield не пересчитывается на pointer-down; после commit/Undo обновляются только dirty X/Z columns.

V2.17 two-point ramp gate:

1. Выбрать `Склон A → B`, кисть 4–8. Первый LMB на нижней террасе показывает голубую точку A и не меняет Resource; Esc убирает только маркер.
2. Снова поставить A и вторым LMB выбрать верхнюю террасу. Между ними появляется цельный склон выбранной ширины без дыр и скачка высоты больше одного art-voxel на соседнюю колонку.
3. Склон должен пересекать золотые границы игровых блоков без шва. `Coarse 2×2×2` заканчивает высоты полными двухвоксельными слоями.
4. Один Ctrl+Z отменяет весь склон, Redo возвращает его. Save/reopen сохраняет ту же форму; точка A является только editor view state и не сериализуется.

V2.18 surface edit-region gate:

1. Нажать `Выделить участок`, выбрать два противоположных угла. После первого клика видна preview-рамка, после второго — голубая рамка всей рабочей области и подпись X/Z диапазона.
2. Провести `Красить`, `Поднять`, `Выровнять`, `Сгладить` и `Склон A → B` через границу рамки. Внутри изменения применяются, снаружи видимый контекст остаётся byte-identical; обе точки склона должны находиться внутри.
3. Один Ctrl+Z по-прежнему отменяет весь применённый мазок внутри области. Esc при выборе второго угла отменяет только новое выделение и сохраняет прежнюю рабочую область.
4. `Вся поверхность` снимает ограничение. Save/reopen не сохраняет рамку в voxel Resource: это editor-only scope, а не новая мини-карта или gameplay schema.

Targeted gates: `test_voxel_surface_sculpt.gd`, `test_voxel_tools_backend.gd`, controls/strength metadata в `test_graph_workspace.gd`.

V2.19 battlefield Surface handoff gate:

1. Открыть `colored_crossing.tscn`, выбрать корень arena. В 3D toolbar доступна кнопка `Вся арена → Surface`; на обычной сцене без Battlefield Resource она отключена.
2. Нажать кнопку. Godot переключается на `Ember Graph → Voxel Surface`, создаёт/открывает `content/combat/surfaces/colored_crossing_surface.tres` размером 7×5 блоков. Исходные gameplay-высоты и типы клеток читаются как стартовые крупные массы; preview постепенно догружает chunks без зависания одного кадра.
3. Нарисовать деталь, сохранить `.tres`, вернуться в 3D и снова открыть Surface. Должен открыться тот же Resource, а не новый 4×4 pilot. Назначение `Visual Surface` на Battlefield отменяется/возвращается одним Ctrl+Z/Redo до сохранения Battlefield Resource.
4. В Surface Canvas нажать `Камера мира`, развернуть/сузить панели редактора и вернуть их назад. Render target следует за реальным окном, но ни одна сторона не превышает 4096; ошибки `Texture dimensions exceed device maximum` и `rt->color.is_null()` не появляются.
5. Мелкий sculpt не меняет semantic cells, deployment, combat elevation и pathfinding. До следующего visual-projection slice arena в 3D/Play всё ещё показывает прежний GridMap graybox — это ожидаемая граница текущего этапа.

Targeted gates: `test_battlefield_resource.gd`, `test_voxel_surface_sculpt.gd`, `test_graph_workspace.gd`; все запускаются без `--editor`.

V2.20 camera + battle projection gate:

1. Открыть surface арены 7×5. Она сразу целиком находится в кадре с заметным запасом; `Home` возвращает этот кадр после orbit/pan/zoom. Колесо может отдалить карту дальше прежнего лимита 14.
2. Нажать `Камера…`: вручную изменить поворот, наклон, масштаб и запас кадра. RMB обновляет те же значения, MMB меняет только X/Z target. `Сверху` даёт почти вертикальный безопасный ракурс без singularity.
3. Сохранить Surface и Battlefield, вернуться в открытую arena. Пока 16×16 chunks постепенно строятся, виден прежний graybox; после завершения он визуально заменяется общей voxel-поверхностью. Масштаб и центры клеток совпадают, бойцы/overlay/labels не сдвигаются.
4. Нарисовать новый мазок, сохранить и вернуться: старая версия поверхности не исчезает во время обновления, chunks заменяются постепенно. Cell hover/pick, 3D semantic кисти, движение и pathfinding продолжают использовать невидимый GridMap.
5. Для surface, созданной v2.19, ещё раз нажать `Вся арена → Surface`, затем Ctrl+S на Battlefield. В `.tres` поля должна остаться внешняя ссылка на `content/combat/surfaces/...`, а не embedded массив voxels.

Targeted gates: `test_graph_workspace.gd`, `test_combat_arena_scenes.gd`, `test_combat_lab.gd`, `test_combat_grid.gd`, плюс прежний voxel suite.

V2.21 world viewport region gate:

1. Открыть `agent_sandbox.tscn`. В 3D toolbar доступны `Surface-область`, `Открыть область`, `Вся карта`; в battle arena эти world-команды отключены, потому что там отдельный Battlefield owner.
2. Включить `Surface-область`, кликнуть два противоположных блока Terrain. Между кликами голубая рамка показывает preview, после второго статус показывает размер прямоугольника. Esc отменяет только незавершённый выбор.
3. Нажать `Открыть область`. Создаётся один `content/world_surfaces/agent_sandbox_surface.tres`, Map получает внешнюю ссылку `Visual Surface`, а Surface Canvas открывается с той же рамкой. Кисти не меняют данные вне неё; кнопка `Вся поверхность` внутри Canvas снимает scope.
4. Сохранить Surface и сцену, вернуться в карту и открыть другую область. Должен открыться тот же Resource без второй копии/embedded voxels; Ctrl+Z до сохранения сцены отменяет назначение ссылки на Map.
5. `Вся карта` открывает тот же owner без маски. На этом gate world Terrain/collision в 3D ещё не заменяется authored Surface: обратная chunked projection является следующим этапом и не должна подменяться сохранением отдельного patch на каждый выбор.

Targeted gates: `test_voxel_surface_sculpt.gd`, `test_graph_workspace.gd`, `test_map_visual_library.gd`, `test_scene_edit_roundtrip.gd`, `test_map_transition.gd`; все запускаются без `--editor`.

V2.21.1 editor-index gate:

1. После добавления/удаления editor tool-script открыть проект с обновляющимся global-class cache: health/save/defeat tests не должны выдавать каскад `Could not parse global class EmberExploreState`, `Cannot infer type` или `Could not resolve progress_state`.
2. `ember_explore_state.gd` отдельно проходит `--check-only`; test boundary не меняет production typing или save owner.
3. `test_health_consumables.gd`, `test_progress_restore.gd`, `test_defeat_respawn.gd` проходят и `--check-only`, и полное headless выполнение без `--editor`.

V2.22 shared world/battle projection gate:

1. В `agent_sandbox.tscn` выбрать Surface-область, открыть её, изменить заметный участок и сохранить `.tres`. После возврата в 3D та же форма постепенно заменяет legacy Terrain без пустого кадра; в Play виден тот же результат.
2. Пока initial chunks строятся, виден `Terrain/Mesh`. После завершения скрыт только Mesh: `Terrain/Collision`, регионы, props, взаимодействия и перемещение игрока продолжают работать по прежним данным.
3. Повторно изменить Surface: старая точная проекция остаётся видимой, пока новые chunks заменяются по одному за кадр. Resource не создаёт baked Mesh или второй gameplay grid.
4. Назначить Surface другого размера/`semanticOwner`: Terrain остаётся видимым, а Map показывает configuration warning. Вернуть правильную ссылку — projection восстанавливается.
5. Боевые арены сохраняют прежнее отображение и масштаб `1 block = 1.2`: они используют тот же leaf projection вместо копии chunk renderer.

Targeted gates: `test_world_surface_projection.gd`, `test_scene_edit_roundtrip.gd`, `test_map_transition.gd`, `test_combat_grid.gd`, `test_combat_lab.gd`, `test_combat_arena_scenes.gd`, `test_voxel_surface_sculpt.gd`; все запускаются без `--editor`.

V2.22.1 world selection usability gate:

1. Нажать `Выделить участок`, зажать ЛКМ на Terrain и протянуть по диагонали. Во время движения видны голубая заливка, рамка, четыре угла и текущий размер; отпускание фиксирует область.
2. Повторить двумя отдельными кликами: первый оставляет видимый угол и подсказку, второй завершает тот же inclusive Rect2i.
3. Начать/закончить у внешнего края карты и провести через декоративный prop: область привязывается к ближайшей клетке и не срывается из-за первого чужого physics-hit. Далёкий клик вне карты остаётся невалидным.
4. После завершения `Открыть область` активна и открывает именно показанный размер. Esc во время незавершённого выбора ничего не меняет в уже сохранённой Surface.

Automated gate: `test_voxel_surface_sculpt.gd` проверяет inclusive rectangle, local-point mapping, near-edge clamp и far-outside rejection.

V2.23 contextual editor chrome gate:

1. Открыть `agent_sandbox.tscn`: в 3D header видны только `Выделить участок`, `Открыть область`, `Ещё…` и короткий статус world Surface. Отключённой полосы `Поле боя / Кисть / Группа / Тайлы / Размер` нет.
2. Открыть battle arena: world Surface toolbar исчезает. До включения `Поле боя` скрыты brush/shape/group; после включения они появляются рядом с активным инструментом. `Ещё…` содержит библиотеку тайлов, resize и открытие всей арены в Surface.
3. Открыть сцену без `EmberMapLoader` и `EmberCombatGrid3DWorld`: обе Ember-полосы отсутствуют. Вернуться на карту/арену — соответствующая полоса восстанавливается.
4. Сузить окно редактора примерно до 1280 px: Ember-контролы не вытесняют штатные меню Godot. Длинный статус сокращается многоточием, полный текст читается в tooltip.
5. Убедиться, что paint/select gesture, Ctrl+Z/Redo, `Открыть область`, whole-map/arena Surface handoff работают по прежним данным.

Automated gates: `test_battlefield_resource.gd`, `test_voxel_surface_sculpt.gd`. Дальнейшая очередь аудита находится в `docs/EMBER_EDITOR_UX_AUDIT.md`.

V2.24 Surface Canvas workspace gate:

1. Открыть любую world/battle Surface. Вверху остаются стабильные название, `Вид` и `Сохранить`; слева видны десять инструментов; справа — активная подсказка, рабочая область и Resource.
2. Переключить все кисти. Radius/material/coarse остаются в tool-settings, а cap/rate появляются только для Raise/Lower/Shell, strength — только для Smooth. Высота основного viewport не прыгает из-за старой длинной wrapping-полосы.
3. В меню `Вид` проверить world/battle/top presets, Home-fit, возврат центра и popup точных настроек. RMB/MMB/колесо продолжают менять тот же editor-only camera state.
4. В правой панели выделить участок, отменить Esc, применить новую область и вернуть всю поверхность. Рамка и ограничение всех кистей работают как прежде; sidebar прокручивается при малой высоте.
5. Потянуть разделитель справа и сузить main screen примерно до 1280×720. Viewport остаётся usable и никогда не запрашивает render target больше 4096. `Сбросить тестовый холст` виден только у pilot; `Сохранить` пишет прежний Surface Resource.
6. Проверить один мазок, Ctrl+Z/Redo и save/reopen: изменения данных byte-identical прежнему UI.

Automated gates: `test_graph_workspace.gd`, `test_voxel_surface_sculpt.gd`, `test_voxel_tools_backend.gd`.

V2.24.1 dedicated Surface Canvas main-screen gate:

1. Полностью перезапустить Godot после обновления `project.godot`. В верхнем workspace selector рядом с `Ember Graph` видна отдельная вкладка `Surface Canvas`.
2. Нажать вкладку напрямую: если авторская Surface ещё не передана, открывается pilot; повторный переход сохраняет текущий Resource и camera/editor state.
3. В `agent_sandbox` выбрать область и нажать открыть, затем повторить из battle arena. В обоих случаях Godot переключается именно на `Surface Canvas` и показывает переданный Resource/Rect2i.
4. В selector внутри `Ember Graph` больше нет `Voxel Surface`: Graph остаётся владельцем action/dialogue/quest/loot UI. Отключение тонкого `Ember Surface Canvas` plugin оставляет диагностический recovery через старый hidden workspace, но это не основной authoring route.

Automated gate: `test_graph_workspace.gd` проверяет enabled plugin path, отсутствие старого selector entry и прежний общий workspace contract; оба plugin scripts проходят `--check-only`.

V2.25 Surface material-channel gate:

1. В `Surface Canvas` выбрать `Красить`, задать водный цвет и окрасить небольшой участок существующей формы.
2. Выбрать `Материал / вода`: вместо палитры появляется `плотный / мелкая вода / глубокая вода / прозрачный`. Провести один непрерывный мазок по тому же участку — форма и цвет не меняются, но поверхность становится прозрачной.
3. Ctrl+Z/Redo отменяет и возвращает весь протяжённый материал-мазок одной операцией; Esc во время LMB возвращает канал к состоянию до жеста.
4. Выбрать `плотный` и стереть прозрачность только на части участка. Проверить, что соседний цвет сохранён.
5. Сохранить, закрыть/открыть Surface и затем посмотреть её в world/battle сцене: transparent-геометрия совпадает с Canvas. Рабочая голубая область ограничивает material brush так же, как остальные кисти.

Automated gates: `test_voxel_surface_sculpt.gd`, `test_graph_workspace.gd`; оба plugin scripts и material model/actions проходят `--check-only`.

V2.25.1 connected material selection gate:

1. У `Материал / вода` переключить `Применение · кисть` на `Связанная область`: radius/coarse скрываются, появляется похожесть цвета.
2. На участке с двумя соприкасающимися оттенками выбрать `точно`, затем Undo и `близкий 5%`. Первый клик меняет только исходный цвет, второй захватывает близкий оттенок.
3. Проверить, что заливка не переходит через пустой разрыв, в скрытый внутренний объём или в отдельный водоём того же цвета. Голубая рабочая область обрезает обход по своей границе.
4. На слишком большой одноцветной Surface без scope операция не применяет частичный результат и предлагает сначала выделить участок. Повторный клик тем же пресетом не создаёт Undo/remesh.

Automated gates: `test_voxel_surface_sculpt.gd` проверяет exact/similar, connected-only, exposed vertical shell и atomic cap; `test_graph_workspace.gd` проверяет контекстные controls.

V2.26 exposed-shell + stylized water gate:

1. В `Surface Canvas` выбрать `Материал / вода → Связанная область`, покрасить верх возвышенного одноцветного участка и убедиться, что материал продолжается по его открытой вертикальной стенке; внутренние voxels под закрытой поверхностью остаются плотными.
2. Проверить все три water-пресета: `глубокая` наиболее насыщенная, `мелкая` прозрачнее, `очень прозрачная` оставляет тонкую цветную массу. Возврат в `плотный` убирает water shader без смены цвета.
3. Оценить одну и ту же сохранённую Surface в Canvas, обычной world-сцене и battle arena. Пиксельные гребни не должны скакать на границах 16×16 preview chunks; на вертикали видны отдельные движущиеся струи.
4. При орбитальной камере проверить прозрачную сортировку у ступенчатого берега. Водный материал использует alpha depth pre-pass, но сложные вложенные прозрачные объёмы всё равно не являются поддержанным authoring-паттерном этого среза.

Automated gates: `test_voxel_surface_sculpt.gd` проверяет 3D connected exposed shell; `test_world_surface_projection.gd` проверяет отдельный water shader в общем world/battle renderer; generic voxel prefab transparency остаётся прежним материалом.

Hotfix v2.26.1 calm pixel-water visual gate:

1. Перезапустить Godot или перезагрузить изменённый water material, открыть одну и ту же воду в Canvas и world/battle projection. Она выглядит как цельная голубая масса, а не как набор светящихся полос.
2. На неподвижной камере подождать несколько секунд: четыре крупные pixel-тона смещаются редкими целыми шагами без плавного шума, мерцания и случайных ярких точек.
3. Повернуть камеру к вертикальной грани: она остаётся водной и немного темнее поверхности, но не получает отдельные частые «струи». Chunk seams не проявляются.
4. Не ожидать на этом gate отражений, зеркальных бликов или пены: они намеренно остаются следующими независимыми визуальными слоями после утверждения базовой палитры и скорости.

V2.27 clear overlay above authored floor gate:

1. В `Surface Canvas` инструментом `Красить` сделать на ровном дне несколько цветовых пятен/камней. Затем `Материал / вода → Вода · прозрачная` применить поверх: дно остаётся непрозрачным и отчётливо видно через отдельную плоскость воды.
2. Переключить `Связанная область`: выбирается только соприкасающийся похожий цвет на одной высоте дна. Боковые стены, скрытые voxels и отделённый водоём не получают water-mask.
3. В Canvas, world и battle проверить редкие разорванные бело-мятные линии. За несколько секунд они сдвигаются небольшими дискретными шагами; сплошной цветной мозаики, частых полос и яркого процедурного шума нет.
4. Выбрать `Без воды`: overlay исчезает, а исходные цвета/форма дна остаются byte-identical. Один Ctrl+Z возвращает воду; save/reopen сохраняет ту же mask.
5. На этом gate не проверяются refraction/reflection/shore foam. Следующий visual slice может читать screen/depth только после отдельной оценки Forward+ cost и transparent-pass ограничений.

Automated gates: `test_voxel_surface_sculpt.gd` требует одновременно `opaque` floor и `water` overlay; `test_world_surface_projection.gd` проверяет единый water material в общей world/battle projection; generic prefab transparency остаётся прежним.

V2.28 connected water network + floor editing gate:

1. Открыть воду в `Surface Canvas` и подождать несколько секунд. Светлая линия должна образовывать непрерывную сеть замкнутых неровных ячеек, а не отдельные штрихи; движение редкое и ступенчатое, без быстрого мерцания.
2. Осмотреть стык соседних water-квадов и границу 16×16 preview chunks: рисунок и широкие бирюзовые tone bands продолжаются по общим мировым координатам без повторного старта и шва.
3. В шапке выбрать `Слои · только дно`. Water overlay исчезает, но форма и цвет дна остаются; нарисовать камни/пятна, затем вернуть `Слои · дно + вода` и увидеть прежнюю water-mask поверх нового дна.
4. Сохранить и открыть Resource повторно. Переключатель слоёв не сериализуется и не создаёт Undo; `transparency` меняется только инструментом `Материал / вода`.
5. Сверить Canvas, world и battle: материал и масштаб сети одинаковы. Пена у берега, отражения и refraction не входят в этот gate.

Automated gates: `test_voxel_surface_sculpt.gd` проверяет floor-only projection без `water` surface; `test_graph_workspace.gd` проверяет оба viewport mode; `test_world_surface_projection.gd` сохраняет общий world/battle material owner.

V2.29 thin network + shoreline foam gate:

1. Перезагрузить water material и сравнить сетку с v2.28: связные ячейки сохраняются, но светлая линия занимает примерно один пиксель, а не широкую полосу.
2. На границе water-mask проверить узкую непрерывную мятно-белую пену. Она должна идти по берегу и вокруг отверстия, где более высокий voxel-камень/опора вытесняет воду.
3. Осмотреть границу двух 16×16 preview chunks внутри одного водоёма: там нет пены. Реальный разрыв воды, другая высота или край карты создают контур.
4. Переключить `Слои · только дно`: одновременно исчезают water overlay и его derived foam; возврат `дно + вода` восстанавливает оба слоя без изменения Resource.
5. Сверить Canvas, world и battle. Отдельные scene props и персонажи пока не создают динамическую пену — это следующий независимый contact-effect gate.

Automated gates: `test_voxel_surface_sculpt.gd` проверяет четыре края одиночной water-cell и отсутствие ложной пены через chunk seam; `test_world_surface_projection.gd` требует отдельный foam shader material.

V2.30 basin level-fill gate:

1. В `Surface Canvas` выбрать `Заливка уровня`, оставить `Слой · вода / Уровень · авто до края / Берег · на 1 vox ниже` и кликнуть по дну замкнутого пруда. Должна появиться одна горизонтальная прозрачная поверхность чуть ниже ближайшего края; дно, стены и gameplay grid не меняются.
2. Кликнуть на открытой равнине: операция показывает отказ и не оставляет частичной заливки.
3. Проверить ручные `+1/+2/+4/+8/+16 vox`, затем `Слой · удалить`. Каждый клик является одной операцией Ctrl+Z/Redo.
4. Save/reopen сохраняет уровень, материал и оттенок. Та же плоскость видна в world и battle projection.

Automated gates: `tools/test_voxel_surface_sculpt.gd`, `tools/test_world_surface_projection.gd`, `tools/test_graph_workspace.gd`.

V2.31 consistent transparent water + shore-profile gate:

1. Открыть один и тот же пруд в `Surface Canvas`, обычной вкладке `3D` и боевой сцене. Во всех трёх видах через воду отчётливо видно voxel-дно; плоскость не превращается в непрозрачную бирюзовую заливку.
2. В `Заливке уровня` оставить `Берег · на 1 vox ниже` и повторно кликнуть по существующему пруду. Вода опускается относительно найденного spill edge одним Undo, земля не меняется; `Берег · вровень` возвращает прежнюю высоту.
3. Сделать дно с глубиной 1–4+ vox. Мелководье остаётся самым прозрачным, глубокие участки получают несколько спокойных дискретных тонов без нового authored-канала.
4. Осмотреть прямой и ломаный берег: контактная пена заметно тоньше, слегка меняет ширину/альфу и имеет пропуски на длинной прямой, но держит углы и не появляется на preview chunk seam.

Automated gates: `test_voxel_surface_sculpt.gd` проверяет shore inset, derived depth UV и sparse foam; `test_graph_workspace.gd` проверяет новый contextual shoreline control; `test_world_surface_projection.gd` сохраняет один water/foam material owner для world и battle.

Hotfix v2.31.1 atomic level replacement gate:

1. Заполнить пруд вровень, затем повторить авто-заливку с берегом `-1` и `-2 vox`. После каждого понижения вне новой маски не остаётся ни одной колонки воды на старой высоте.
2. Повысить воду обратно: расширенная маска заменяет низкую тем же одним Undo. Undo/Redo поочерёдно восстанавливают обе полные формы без смешанных уровней.
3. Имитировать старый дефект несколькими соприкасающимися кольцами воды разных уровней и снова залить центр. Вся связная семья нормализуется; отдельный пруд того же материала за сухой колонкой не меняется.
4. Ограничить рабочую область так, чтобы она разрезала существующий водоём. Операция отказывается до записи данных и предлагает расширить область/выбрать всю карту.

Automated gate: `tools/test_voxel_surface_sculpt.gd` проверяет shrink/repair/isolation/scope, а также полное Undo/Redo замены.

V2.32 stepped reflection + sparse glint gate:

1. Посмотреть один пруд сверху и под боевым ортографическим углом. Сверху authored-дно почти не тонируется, под косым углом появляется слабая небесно-мятная ступень отражения без непрозрачного зеркала.
2. Подождать 10–20 секунд: только редкие короткие участки связной ripple-сетки меняют яркость тремя отчётливыми шагами. Вся сетка не должна одновременно вспыхивать или превращаться в шум.
3. Сравнить `Surface Canvas`, обычный 3D viewport и battle/world projection при одинаковом ракурсе: цвет, плотность и темп совпадают; смена камеры влияет лишь на ступень отражения.
4. Переключить `Слои · только дно`: отражение и блики исчезают вместе с water overlay, canonical voxel/fill данные и Undo history не меняются.

Automated gate: `tools/test_world_surface_projection.gd` требует общий transparent shader с `sky_reflection_color`, camera `VIEW` и `sparse_glint`; `tools/test_voxel_surface_sculpt.gd` сохраняет прежний water mesh/authoring contract.

V2.33 dynamic water-contact gate:

1. В Play провести explore player с суши в заполненный пруд и обратно. У ног появляются две тонкие разорванные pixel-дуги точно на water plane; на суше эффект полностью скрыт.
2. Открыть боевую арену с `Visual Surface`, поставить/переместить юнита на водную клетку и затем на сухую. Тот же контакт работает в editor preview и runtime, следует staged position и не влияет на доступность хода.
3. Для отдельного `EmberVoxelProp` включить Inspector `Вода → Water Contact Enabled`, подобрать `Water Contact Radius Blocks`, запустить сцену и проверить контакт. Выключенный prop не создаёт визуальный child/process.
4. Поднять объект заметно выше воды или погрузить глубже допустимого порога: ложное кольцо не показывается. Изменение/удаление water fill обновляет видимость без сохранения состояния эффекта.

Automated gates: `tools/test_world_surface_projection.gd` проверяет world sample, wet/dry visibility и общий contact material; `tools/test_combat_arena_scenes.gd` требует contact у preview units; `tools/test_map_transition.gd` требует его у runtime player.

V2.34 saved Surface → Play gate:

1. В `agent_sandbox` открыть участок через `Surface Canvas`, заметно изменить рельеф и нажать `▶ Играть карту`. Кнопка сначала сохраняет Surface и запускает именно `agent_sandbox.tscn`; проектная main scene `fan_town` не открывается.
2. Удалить только сценовую ссылку `Map → Visual Surface`, не удаляя `content/world_surfaces/agent_sandbox_surface.tres`, и запустить сцену. Runtime находит канонический Resource по `map_id` и показывает сохранённую форму; неверная явно назначенная Surface с чужим owner/размером всё ещё даёт warning и не подменяется молча.
3. На карте 24×24 изменённые чанки должны начать появляться сразу и заменить legacy Terrain примерно за несколько кадров/секунд без длинного пустого ожидания и без однокадрового полного remesh-фриза.
4. Вернуться в Canvas, изменить и сохранить снова, затем повторно нажать `▶ Играть карту`: новый процесс читает последние voxels/fill, вода и береговая пена совпадают с Canvas.

Automated gates: `tools/test_world_surface_projection.gd`, `tools/test_voxel_surface_sculpt.gd`, `tools/test_graph_workspace.gd`.

V2.35 movement-directed water wake gate:

1. Запустить связанную world-карту, поставить героя в воду и остановиться: у ног остаются прежние спокойные разорванные дуги без постоянного яркого следа.
2. Пройти по воде вперёд и по диагонали: короткая bow-wave держится перед ногами, две pixel-дорожки расходятся позади и поворачиваются вместе с фактическим направлением, а не с камерой.
3. Резко остановиться: след плавно возвращается к спокойному контакту, не зависает и не вращается на суше. Медленное и быстрое движение дают разную интенсивность.
4. Проверить двух персонажей/юнитов одновременно: instance-параметр одного не меняет яркость другого. В бою staged-перестановка даёт короткий импульс без изменения клетки, pathfinding или Wet semantics.

Automated gates: `tools/test_world_surface_projection.gd` проверяет motion delta, instance uniform и форму wake; `tools/test_map_transition.gd` и `tools/test_combat_arena_scenes.gd` сохраняют player/combat wiring.

Hotfix v2.35.1 wake direction/length gate (архивный; stretched-реализация заменена v2.35.2):

1. Идти по прямой воде: расходящиеся дорожки находятся строго позади героя, bow-wave — перед ним. Развернуться на 180° и убедиться, что стороны сразу меняются местами.
2. При обычной скорости explore-player след занимает примерно 1.5–2 блока позади; на полной интенсивности доступно до 2.5 блоков. Кольцо у ног не растягивается в овал.
3. Осмотреть длинные сегменты под близким ракурсом: pixel-шаг остаётся квадратным и не размазывается вдоль движения.

Его критерии длины и stretched-quad больше не применять; актуальный gate находится ниже.

Hotfix v2.35.2 historical wake gate:

1. Пройти прямо по воде: две дорожки начинаются у левого и правого заднего края кольца, а не из его центра; длина не превышает примерно 1.2 блока.
2. Резко повернуть на 90°: уже оставленные сегменты не поворачиваются вместе с персонажем, новые продолжают реальную траекторию.
3. Остановиться: новые сегменты не появляются, старые плавно исчезают примерно за секунду. Выйти на берег: контактное кольцо исчезает сразу, оставшийся след спокойно затухает.

Automated gate: `tools/test_world_surface_projection.gd` проверяет квадратный local contact quad, появление world-history samples и отдельный vertex-fade material одного trail mesh.

V2.36 Visual Surface water → battle Wet gate:

1. Открыть `content/combat/battlefields/<arena>.tres` и найти в верхнем custom Inspector блок `VISUAL SURFACE → ПРАВИЛА ВОДЫ`. При назначенной Surface показаны количество покрытых водой клеток и количество изменений; без Surface или при несовпадении размеров кнопка недоступна с точной причиной.
2. Переключить порог 10/25/50%: небольшая лужа внутри крупной клетки становится Wet только при подходящем покрытии. До нажатия canonical данные боя и runtime не меняются.
3. Нажать `Применить N изменений`: нейтральная покрытая клетка получает `Wet` и группу `tide`, прежняя Wet без визуальной воды очищается. Один Ctrl+Z возвращает весь набор; Redo применяет его снова.
4. Нарисовать визуальную воду поверх клетки `Ember` или `Frozen`: preview сообщает число защищённых клеток, но не перезаписывает их. После sync ручные battlefield-кисти остаются главным способом явного исключения.
5. Запустить бой и проверить `Douse/Spark/Chill`: реакции читают синхронизированные `terrain_kinds`, а не shader, mesh или water-mask напрямую.

Automated gate: `tools/test_battlefield_resource.gd` проверяет water coverage, добавление и удаление Wet одним Undo/Redo, группу `tide` и наличие guided Inspector controls; combat tests сохраняют прежний canonical runtime consumer.

Hotfix v2.36.1 Surface owner navigation gate:

1. Выбрать в FileSystem `content/combat/surfaces/<arena>_surface.tres`. Вверху Inspector видна карточка `EMBER SURFACE`, объясняющая различие visual Surface и правил боя.
2. `Редактировать в Surface Canvas` возвращает к тому же Resource. `Открыть правила боя · <arena>` выбирает соответствующий `content/combat/battlefields/<arena>.tres`, где сразу виден блок water→Wet.
3. World Surface не показывает ложную кнопку Battlefield; повреждённый или отсутствующий `semanticOwner` даёт disabled-состояние, а не переход к случайному Resource.

Automated gate: `tools/test_battlefield_resource.gd` проверяет разрешение canonical Battlefield path и наличие активной кнопки навигации у связанной Surface.

Hotfix v2.36.2 embedded Surface save gate:

1. Открыть старое поле, где `visual_surface` ещё является `SubResource`, перейти в Canvas и нажать `Сохранить`. Сообщения `File unrecognized` нет; status показывает внешний путь `content/combat/surfaces/<id>_surface.tres`.
2. Закрыть и снова открыть проект: Battlefield ссылается на внешний Surface, последние voxels/transparency/fill сохранены, файл поля больше не содержит повторно embedded voxel bytes.
3. Повторное сохранение пишет тот же `.tres` без новой миграции. Для неизвестной Surface без `semanticOwner` редактор не угадывает путь и показывает направляемую ошибку.

Automated gate: `tools/test_battlefield_resource.gd` создаёт настоящий временный embedded SubResource, отклоняет его `::` path как file destination, externalizes exact object, сохраняет owner и проверяет внешний link после reopen.

V2.37 Visual Surface height → battle elevation gate:

1. Вылепить на боевой Surface широкую площадку примерно на `14 art vox` выше соседней, сохранить Surface и открыть связанный Battlefield Resource.
2. В блоке `VISUAL SURFACE → ВЫСОТЫ БОЯ` до применения показано число изменяемых клеток. Одиночные камушки и небольшие сколы не должны менять coarse-высоту: расчёт берёт медианный пол по равномерным точкам клетки.
3. Неровная клетка с большим перепадом отмечается в отчёте, полностью пустая не перезаписывает прежнее правило. Нажать `Применить N изменений высоты`: меняется только `elevations`; terrain/group/block/deployment остаются прежними.
4. Один Ctrl+Z возвращает весь старый набор высот, Redo снова применяет проекцию. После Ctrl+S и запуска боя movement, подписи `hN` и позиции юнитов читают новые canonical высоты.

Automated gates: `tools/test_battlefield_resource.gd` восстанавливает coarse-высоты из сгенерированной Surface, игнорирует одиночный декоративный spike и проверяет единое Undo/Redo; `tools/test_combat_grid.gd` и `tools/test_combat_prototype.gd` сохраняют runtime elevation contract.
