# Material library d97c — 2026-09-15

Первый срез согласован пользователем: библиотека и native стенд; инструменты
назначения объектам/вокселям и editor Save/Undo исключены. Реализация/автоматические
gates PASS, art/input acceptance и main integration OPEN. Main checkout не
редактировался, Resource/schema/mesher/physics/editor не менялись, commit/push нет.
Предыдущий art/lighting/HANDOFF.md и его доказательства сохранены отдельно.
После библиотеки пользователь хочет обсудить остальные материалы и воду:
отражения, блики, движение и глубину; здесь водный срез не начинался.

## Diff и зависимость

- materials/library/*.tres — девять готовых built-in ShaderMaterial ресурсов;
- scripts/ember_material_library.gd — стабильный каталог, validation и create;
- shaders/ember_material_opaque.gdshader;
- shaders/ember_material_transparent.gdshader;
- shaders/ember_material_surface.gdshaderinc — shared свойства/fragment/light;
- scenes/material_library_stand.tscn;
- tools/material_library_stand.gd — disposable preview/UI/camera;
- tools/test_material_library.gd;
- tools/render_material_library.gd;
- tools/check_material_library_guard.py;
- art/materials/** — docs/PNG/логи.

Обязательная зависимость: прежний shaders/ember_diorama_light.gdshaderinc из
lighting diff, используется без изменения. Для библиотеки достаточно этого
include; интеграция прежнего lighting helper/loader/voxel/water materials
остаётся отдельной. Старые shaders/materials не переключаются на новую библиотеку.
Четыре docs получают ТОЛЬКО новую помеченную materials-library-d97c-20260915
секцию, готовые вырезки в documentation-sections.md. Не заменять старые полные
docs/loader основного checkout. Это отдельный diff от предыдущего света.

## Стабильные preset IDs

matte — нейтральная полностью матовая поверхность;
wood — тёплый древесный цвет, широкий слабый блик;
stone — прохладный камень, почти матовый;
sand — земля/песок, матовый;
leaf — непрозрачная листва, light-driven thin transmission;
metal — metallic0.92, roughness0.32, направленный блик и Sky reflection;
glass — прозрачный shader, opacity0.24, roughness0.12;
crystal — прозрачный shader, opacity0.66, roughness0.24, насыщенный цвет;
emissive — opaque glow, energy1.8, цвет свечения следует поверхности по умолчанию.
Путь: res://materials/library/<id>.tres. IDs не локализованы, UI имена русские.

API: EmberMaterialLibrary.create(id, options) возвращает НОВЫЙ независимый
ShaderMaterial без publication path; original preset и соседний экземпляр не
меняются. Shader код общий/immutable. Unknown ID/options или неверные значения
дают null; validate_options возвращает конкретные ошибки. Назначение material
surface/override принадлежит вызывающему владельцу, здесь только QA samples.

## Параметры и хранение

base_color: Color0..1; use_vertex_color: bool. По умолчанию tint умножается на
COLOR mesh; palette не переписывается. use_vertex_color=false позволяет получить
один ровный выбранный цвет поверхности.
surface_roughness0.04..1; surface_metallic0..1; highlight_strength0..1.
opacity0.02..1 работает ТОЛЬКО в transparent shader. Opaque slider отключён,
уменьшение opacity не переводит opaque material в alpha pipeline.
transmission_strength0..1 и transmission_color: Color0..1; artistic response
от реального света с обратной стороны, не физическая SSS и не emission.
emission_energy0..16; emission_color: Color0..1; emission_follow_base: bool.
Выбор отдельного цвета активен после отключения следования цвету поверхности.

Все свойства сохраняются как shader parameters в ShaderMaterial .tres.
Это пока НЕ назначение preset ID объекту и НЕ per-voxel persistence:

- palette остаётся владельцем цвета вокселя; base_color — material tint;
- transparency уже существует и mesher превращает byte amount в alpha;
  новый opacity множитель автоматически в Source НЕ пишется;
- emissive уже существует как voxel канал, а emissive_strength/explicit lights
  принадлежат модели/существующему prefab. Здесь shader energy/color не связаны
  с ними и не создают Omni. Независимый per-voxel emission color не хранится;
- shine — существующий канал, но не готовая модель roughness/metallic;
- transmittance — существующий канал, здесь transmission shader multiplier
  к нему автоматически не подключён;
- roughness, metallic, preset ID и отдельные emission/transmission colors
  существуют только в ShaderMaterial; Source поля не добавлялись;
- resource.material Dictionary не используется как случайное хранилище новых
  IDs: там уже есть semantic metadata других owners.

Сопоставление/нормализацию каналов и editor commands должен согласовать следующий
срез с owner редактора; не превращать этот список в молчаливую миграцию.

## Native стенд и пределы

Девять одинаковых voxel samples создаются existing VoxMesher packed-region path;
источник только disposable массивы, никаких Resource/prefab publications.
Цветные opaque backings дают видимый фон за стеклом. UI меняет только clones,
reset создаёт свежий preset instance. День, ночь с ОТДЕЛЬНЫМ Omni и контровой
свет; камера orbit/zoom/reset. ProceduralSky/ambient/glow принадлежат только стенду.
UI не EditorPlugin и не второй owner editor данных. Размер доказательств1600×900.

Для direct highlights свет должен иметь light_specular>0. Stand lights имеют1;
существующие Ember light factories местами имеют0. Их поля здесь не менялись.
При интеграции не обещать видимый солнечный блик без проверки реальной сцены.
Custom specular lobe художественный, не заявление о полном physical GGX.
Emission не создаёт light; ореол требует scene glow. Glass/crystal не имеют
refraction/colored shadows. Alpha front/behind opaque проверен; это не гарантия
любого пересечения нескольких прозрачных объектов. Thin leaf лучше оценить
на настоящей форме листа/кроны: cube stand проверяет response, не моделирует крону.

Шейдеры используют Godot ALPHA/ROUGHNESS/METALLIC/EMISSION и custom light outputs:
[официальная spatial shader reference](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html).
Diffuse irradiance не умножает ALBEDO дважды. Shadow math прежняя, никакого noise/
TIME, новой water/reflection системы или дополнительных production lights.

## Проверки и воспроизведение

Godot4.7.2 / Forward+ / Vulkan1.4.351 / RTX5070, отдельная подготовленная копия
C:/Users/novos/AppData/Local/Temp/ember-graphics-d97c-20260915. Отдельное app userdata;
MCP editor/autoload отключены в Temp, graphics-baseline/.gdignore, Ember plugins
сохранены. Working checkout через --headless --editor не запускался.

Console exe: C:/Users/novos/Projects/ember-godot/tools/godot/Godot_v4.7.2-stable_win64_console.exe.
Для подготовленной копии:

```powershell
$materialFixture = 'C:/Users/novos/AppData/Local/Temp/ember-graphics-d97c-20260915'
$materialGodot = 'C:/Users/novos/Projects/ember-godot/tools/godot/Godot_v4.7.2-stable_win64_console.exe'
& $materialGodot --headless --path $materialFixture --script res://tools/test_material_library.gd
& $materialGodot --path $materialFixture --script res://tools/render_material_library.gd
# Interactive stand, no automatic Source writes:
& $materialGodot --path $materialFixture res://scenes/material_library_stand.tscn
```

qa/test_material_library.log PASS:9IDs, bounds/NaN/type validation, immutable
originals, instance independence, custom parameters save/reopen для всех9presets,
scene geometry, UI signal routing/reset/day/night. Native UI сигналы проверены
программно; реальное управление мышью остаётся manual gate.
qa/native-library.log PASS:day/night/backlight PNG; emission without lights;
custom emission save/reopen pixel bytes идентичны; alpha behind/front depth;
direct specular и light-driven transmission. Center pixel dull0.1686→shiny0.2353;
leaf dark green0→thin0.498; custom red emission(1,0,0) без lights.

Связанные gates PASS: test_diorama_materials, test_voxel_palette,
test_voxel_prefab_rebuild, test_native_surface_water; точные логи qa/.
editor-import-library.log:isolated --headless --editor --import exit0,
scan/classes/reimport/layout завершены, нет ERROR/SCRIPT ERROR.
Inherited FanTown invalid UID warnings используют text path fallback.

qa/previous-look-source-guard.log PASS:429 старых source/scene/prefab files
побайтно прежние; единственное добавление — owned stand.tscn. Старый manifest
art/lighting/qa/source-hashes.json НЕ перезаписан. Шесть re-render near/overview
уголка(day/night) и Причала с водой побайтно совпали с прежними candidate PNG.
Оригинальные 38 lighting PNG/logs не заменены; новые guard PNG/logs только здесь.
Это compatibility evidence, не FPS/GPU optimization benchmark библиотеки.

Ранние QA ошибки исправлены до финальных PASS: неверные guessed mesher method/
Environment enum заменены фактическим packed-region API и default Sky reflection;
Variant String inference задан явно; exact float== slider assertion заменён
approx comparison. Custom crystal screenshot сначала не синхронизировал UI
после программного edit; fixture обновляет selection перед capture. Production
renderer/storage bugs этими ранними QA ошибками не объявляются.

## Передача и приёмка

User acceptance OPEN:оценивает основные характеры, цвет/свечение, читаемость
стекла/кристалла, металл/листву на реальных формах и stand camera/pickers/sliders.
Main owner выбирает момент интеграции только перечисленного нового diff.
Назначение mixed materials в voxel объекте, save/discard/Undo/Redo и baked mesh
cache invalidation — следующий отдельный контракт; здесь не реализованы.
Воду обсуждаем отдельно после первого библиотечного среза.
