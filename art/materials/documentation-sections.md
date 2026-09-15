## docs/EMBER_NOW.md

<!-- BEGIN materials-library-d97c-20260915; transfer this section only -->
## Библиотека материалов — первый срез, manual OPEN

2026-09-15: в graphics worktree d97c реализованы9ShaderMaterial presets и
native comparison stand:matte/wood/stone/sand/leaf/metal/glass/crystal/emissive.
Независимые экземпляры, цвет/блеск/прозрачность/просвечивание/свечение, day/night.
Автоматические native/storage/compatibility gates PASS, art/input и main
integration OPEN. Source/schema/editor/mesher не менялись. Предыдущий lighting
handoff сохранён отдельно;6старых viewport PNG совпали побайтно,429Source files
прежние, добавлена только сцена стенда. Передача:art/materials/HANDOFF.md.
Назначение объектам/вокселям и editor Save/Undo — следующий контракт owner
редактора. По просьбе пользователя после библиотеки обсудить остальные материалы
и воду:отражения/блики/движение/глубину; здесь воду не менять.
<!-- END materials-library-d97c-20260915 -->

## docs/EMBER_TECHNICAL_HANDOFF.md

<!-- BEGIN materials-library-d97c-20260915; transfer this section only -->
## Material library — 2026-09-15, manual OPEN

New built-in ShaderMaterial presets in materials/library, stable IDs:
matte,wood,stone,sand,leaf,metal,glass,crystal,emissive. EmberMaterialLibrary.create
returns independent material parameter instances; shared immutable shader code.
New opaque/transparent wrappers share material include and reuse unchanged
diorama light include. Existing voxel/water material defaults/response unchanged.
No Source/schema/prefab/mesher/editor change. Properties persist only in
ShaderMaterial; per-voxel palette/emissive/shine/transparency/transmittance exist
but are not automatically wired to these parameters. No new Source preset IDs
or independent per-voxel emission colors. Full mapping/limits:art/materials/HANDOFF.md.
Native stand is disposable comparison, not EditorPlugin. Native alpha depth,
emission/no-light/reopen pixels, specular, transmission PASS; custom resource
save/reopen/instance independence/validation PASS. Four related regressions PASS.
Six prior corner/day/night/Pier PNG are byte-identical;429previous Source files
unchanged plus one owned stand.tscn. Separate new QA/docs from lighting evidence.
Main integration, art/input and later editor assignment/Save/Undo remain OPEN.
<!-- END materials-library-d97c-20260915 -->

## docs/EMBER_PRODUCT_PLAN.md

<!-- BEGIN materials-library-d97c-20260915; transfer this section only -->
## Graphics library first slice — 2026-09-15, manual OPEN

User-approved bounded library/stand implemented in d97c;9presets, independent
parameters, day/night native comparison. No change to product ordering or editor
scope. Art/input acceptance and main integration pending. Object/per-voxel
assignment tools are a subsequent editor-owner contract. Existing water left
unchanged; discuss reflection/life/depth and other materials after library review.
Details:art/materials/HANDOFF.md.
<!-- END materials-library-d97c-20260915 -->

## MIGRATION_TEST_PLAN.md

<!-- BEGIN materials-library-d97c-20260915; transfer this section only -->
## Material library gate — 2026-09-15, manual OPEN

PASS test_material_library:9stable presets, parameter validation, immutable
originals, independent instances, custom resource save/reopen for all9, stand
UI signals/reset/day/night. Native render_material_library PASS:1600x900 day/
night/backlight, emission with no lights, customized emission save/reopen exact
pixels, opaque-front/behind-glass depth, actual specular/transmission response.
Related diorama materials/palette/prefab/native water gates PASS.
Isolated editor --import completed without ERROR/SCRIPT ERROR, inherited UID
fallback warnings recorded.429old Source/scene/prefab byte hashes unchanged;
only owned stand.tscn added. Six old day/night corner and Pier native viewport
PNG byte-identical. Evidence separated in art/materials/qa; prior lighting QA
not overwritten. Manual art, real mouse/camera/picker/slider use and main
integration OPEN. Per-voxel assignment and editor Undo/Save/reopen require the
next agreed editor contract; this gate does not claim them.
<!-- END materials-library-d97c-20260915 -->
