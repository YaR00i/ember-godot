# Ember editor UX audit

## Update 2026-09-05 · v2.52 guarded sandbox migration

The dashboard now separates non-mutating filtering from an explicit two-step
batch action. `Проверить sandbox-партию` builds all six future Resources in
memory and compares their complete mesh buffers with the legacy preview. The
migration button remains disabled until the exact current IDs pass; refreshing
the inventory invalidates approval. The accepted batch is committed as one
Undo/Redo transaction and rolls back partial output on failure.

All six sandbox models now show green Godot ownership and ready prefabs. The
completed state disables both actions and keeps the six-model scope visible for
inspection. Forward+ checks covered the 1280×720 dashboard and the actual
`agent_sandbox` runtime scene. The visuals match legacy exactly; this does not
promote the graybox scene to final art. Next UX work belongs to the G3 physical
Surface sandbox rather than a broader migration control.

## Update 2026-09-05 · v2.51 filterable migration dashboard

The measured G1/G2 inventory now opens as a separate read-only dashboard rather
than expanding the already crowded bottom dock. Its 263 rows can be filtered by
content domain and ownership/problem state, searched by ID, validation text or
referencing scene, and inspected without leaving the list. A one-click
`Sandbox-партия` view resolves to the six legacy voxel models currently used by
the two `agent_sandbox` scenes and explains each stale prefab in the detail pane.

The screen intentionally has no bulk migration action. Refresh rebuilds the same
report, JSON export still writes only to `user://`, and all filtering is a pure
projection that leaves report schema and canonical sources unchanged. The
1280×720 Forward+ render was inspected for full list/detail/footer visibility.
The next bounded slice is a dry-run/parity check for these six candidates before
any Resource or prefab is written.

## Update 2026-09-05 · v2.50 measured migration inventory

The existing migration bottom panel now exposes one explicitly read-only G1/G2
measurement instead of encouraging a blind bulk conversion. It summarizes six
domains and separates canonical ownership errors from voxel derived-data state.
The first measured baseline is 175 legacy voxel models, 4 actions, 10 dialogues,
19 items, 1 shop and 29 VN assets. Voxel prefab state is independently 56 ready,
32 stale and 88 missing; one legacy VN background points to a missing image.

The report scans scene voxel references and currently finds no unknown owner.
Generation takes about 1.3–1.4 seconds and therefore runs only on the explicit
`Измерить G1/G2` action. Saving writes JSON to `user://` only. SHA-256 gates prove
that native voxel sources, derived prefabs and the frozen JOI archive remain
unchanged. The Forward+ panel was inspected at 1280×720. V2.51 closes the next
bounded read-only dashboard step; bulk migration and fallback removal remain
blocked pending candidate parity.

## Update 2026-09-05 · v2.49 stable Graph hierarchy

The measured problem was one wrapping toolbar owning document navigation,
node creation, selection commands, grouping, clipboard, history and save. At
1280×720 it consumed variable height and made primary actions move between
modes. The workspace now has a stable document row (kind, resource, refresh,
save), a local tool row, and one `Ещё…` popup for arrange/clipboard/group and
diagnostic commands. Quest focus is shown as `Задание › …` breadcrumb rather
than another unrelated action.

The right property column keeps a bounded minimum, clips long status/selection
labels with full tooltip text and persists the split ratio through the native
editor layout callback. This is editor-only state: action/dialogue/quest schema,
Undo owners and runtime are unchanged. Automated layout runs in a fixed
1280×720 host before repeating at 1600×900; lifecycle and real Forward+ visual
checks also pass. Next gate is G1/G2 migration parity and the native content
library.

## Update 2026-09-05 · v2.48 Surface lifecycle and remembered views

Surface Canvas now participates in both relevant Godot lifecycles. Switching
away from its main screen finalizes a held gesture, then routes dirty content
through the existing Resource save/discard owner; Cancel selects Canvas again
and a failed save keeps the modal draft alive. Editor exit and global Save use
the standard `EditorPlugin` unsaved/external-data callbacks rather than a second
dirty flag or custom shutdown owner.

Camera orbit/target/zoom/margin, edit region, height slice, grid/region overlays
and combined/floor layer view are normalized and kept per Surface in the project
editor layout. The store is bounded to 32 recent resources. It is not gameplay
data, does not enter Undo and cannot dirty or rewrite the canonical `.tres`.
Explicit region handoff remains authoritative. Automated workflow covers
Save/Discard/Cancel, failed save, resource switch and layout round-trip; real
editor startup plus Surface/Graph/runtime regressions pass. The Forward+ 1280×720
close modal was inspected with all three actions visible. Next UX gate is Graph
hierarchy and narrow-inspector usability.

## Update 2026-09-05 · v2.47 large Surface profile

The canonical 24×24 sandbox Surface was profiled as a real dense 384×32×384
Resource rather than replaced with a synthetic sparse schema. Its active dense
channels use 9.84 MiB; cache-bypassed text-Resource load is about 0.80 s and save about
0.13 s. Selection overflow remains atomic at 32,768 voxels and its search plus
MultiMesh overlay are already frame-sliced. These measurements do not justify a
persistence migration, so schema v4 and every runtime/save owner stay unchanged.

The measured editor hot paths were narrowed instead. Heightfield construction
visits sparse occupied palette entries through native PackedByteArray search and
keeps the bounded column walk for dense/high-palette inputs. View-only group
filters reuse the canonical heightfield. Grid/region overlays read that cache.
Voxel Tools now builds exact opaque terrain even when column water data exists;
the shared SurfaceMesher appends the canonical water/foam overlay, while local
per-voxel transparency still selects the stock fallback. A 6 ms scheduling
budget can drain multiple fast chunks but always yields after a slow fallback.

Reference result: Canvas synchronous open 0.79 → 0.12 s, group filter 0.71 →
0.019 s, exact chunk 25.5 → 5.9–6.6 ms; 1–2 dry chunks drain in 6–11 ms.
`test_surface_large_profile.gd` records the full JSON in `user://`; sparse/dense
heightfield parity and native-water composition are also correctness-tested.
Next gate is the full close/save/discard lifecycle and remembered camera,
region, slice and layer view.

## Update 2026-09-05 · v2.46 palette ramps

The existing palette panel now expands one selected swatch into a contiguous
3/5/7-color ramp with neutral, warm-light/cool-shadow or soft-pastel shaping.
Preview is local UI state. Apply inserts ordinary palette colors around the exact
source color and remaps voxel plus water-tint indices, so resolved appearance is
unchanged until the author paints with a new shade. The whole insertion is one
existing SculptActions Undo operation and needs no schema or second palette owner.

The test covers ramp generation, capacity, invalid references, source immutability,
resolved voxel/water parity, dialog cancel/confirm, Undo/Redo and save/reopen.
Forward+ 1280×720 verifies the compact sidebar button and ramp dialog. Next gate is
large-Surface profiling of selection/group overlays, storage and chunk rebuild;
dense-to-sparse persistence remains a measured decision, not an assumption.

## Update 2026-09-05 · v2.45 group colors and editor-only visibility

Named groups now carry a saved authoring color used by the selection overlay.
The color is not a palette edit and never reaches runtime rendering. The group
panel also supports hiding several groups at once without mutating the Resource;
water remains visible in this view. Isolation remains a distinct single-group
inspection mode and hides water. Switching/deleting groups prunes stale hidden
IDs, and leaving the workspace clears all view filters.

This closes the first group-organization slice. Palette ramps/sets and explicit
reordering remain separate because they need their own authoring gestures and
validation. Large-map overlay/storage profiling remains the next performance
gate before any dense-to-sparse schema change.

## Update 2026-09-05 · v2.44 compact brush families and shape footprint

The rail now presents eight author-facing tools instead of twelve concrete backend operations. Volume owns Add/Remove; Relief owns Up/Down × Solid/Shell. A new pure `ember_voxel_brush_profiles.gd` maps those contextual controls back to the unchanged model IDs and defines each tool's selection-mask kind. Level, Smooth and Ramp remain separate because their gestures are respectively first-hit plane, neighbourhood averaging and two-point interpolation. Local material and basin fill remain separate data owners.

Selection masking now has two explicit semantics. Paint/Material intersect exact selected voxel indices and retain the mask after commit. Volume/Relief/Level/Smooth/Ramp intersect candidate writes with the selection's derived XZ column set, allowing creation/removal only inside that footprint. A successful shape commit clears stale voxel indices; Esc restores the baseline and preserves them. Surface Fill disables the option because its region is a separately validated connected basin. Named-group locks and height/region bounds remain later gates in the same write path.

Gate: `test_voxel_selection_mask.gd` covers exact paint/material, masked removal, new relief extrusion, commit/cancel lifecycle and save. `test_graph_workspace.gd` checks the eight-family rail, contextual controls and resolution of all six consolidated concrete modes. Forward+ 1600×900 relief/shell/footprint capture was inspected. No Resource schema, runtime, serialization or sculpt algorithm changed.

Next: authoring-friendly palette ramps/group colors and visibility, then profile the selection/group overlay and storage on a genuinely large map before choosing sparse/chunk persistence. Full-editor close lifecycle, remembered views and remaining Graph hierarchy work stay open.

## Update 2026-09-05 · v2.43 selection-masked brushes

The ordinary Paint and Material/water-effect brushes can now intersect their footprint with the existing transient voxel selection through one explicit sidebar toggle. Cursor motion, radius, chunk preview and the existing one-gesture Undo owner remain unchanged; the common live-write and material gates reject indices outside the mask, then apply named-group locks. This is not a second brush implementation and introduces no schema, serialization or runtime change.

A successful masked stroke preserves the mask for repeated color/material passes. Cancel restores the original bytes and also preserves it. Undo/Redo or any unrelated Resource change clears the selection as stale. At v2.43 Add/Remove and column/relief/shell/smooth/ramp tools disabled the option because occupied indices did not define new volume. V2.44 supersedes that limitation with the explicit XZ-footprint rule above.

Gate: `test_voxel_selection_mask.gd` covers masked Paint and Material, unaffected neighbours, retained selection, lock-compatible common writes, Undo/Redo invalidation, cancellation, shape-tool fallback and save/reopen. Forward+ 1600×900 capture was inspected. Selection/groups/palette/slice/Canvas/sculpt/native backend/world projection regressions pass.

Next: design shape semantics as an explicit choice between editing selected occupied voxels and using a selected footprint for extrusion; then large-map sparse/chunk storage, full-editor close lifecycle, remembered views and remaining Graph hierarchy work.

## Update 2026-09-05 · v2.42 named voxel groups

Named groups complete the first reusable-selection workflow. `EmberVoxelModelResource` schema v3 adds `voxel_groups` entries `{id, name, sorted unique indices, locked}`; validation rejects blank/duplicate IDs and invalid ordering/bounds. `ember_voxel_groups.gd` owns normalization, stable unique IDs, CRUD and locked-index union. The sidebar panel owns only stock controls/name dialog. Group operations and schema promotion use the existing SculptActions Undo owner, saved/discarded with the same Resource. Runtime rendering/physics ignore group metadata; compatibility definition exposes it only as authoring metadata.

Create/rename/replace/delete/lock are one-step Undo operations. Select restores members into the transient selection mask. Lock filters voxel shape/color and transparency-material changes at the workspace's common write gates, including mixed selections; surface-fill water remains a separate layer and global palette swatch edits retain their explicit global semantics. UI reports protected attempts. Isolate builds one temporary Resource projection on toggle/source change, containing only canonical member bytes and no water fill; both stock/native chunk mesh and picking consume it. It never writes back, serializes or dirties content. Resource/scope/hide lifecycle clears stale derived state.

Gate: `test_voxel_groups.gd` checks normalization/validation, Unicode name + stable ID, CRUD, lock across batch/live/material writes, isolation source safety, schema, Undo, save/reopen/discard and isolated updates. Forward+ 1280×720 capture inspected. Selection/palette/native migration/slice/Canvas/sculpt/world regressions pass. No external addon was needed.

Next: intentionally masked brush operations (starting with paint/material, then deciding shape semantics), group reordering/visibility colors if real authoring shows the need, and larger-map sparse/chunk storage. Full-editor close lifecycle, remembered views and Graph hierarchy remain open.

## Update 2026-09-05 · v2.41 voxel selection

Transient voxel-index mask now supports single/6-connected similar/all-similar acquisition, RGB tolerance, replace/add/subtract and explicit paint with the active palette swatch. Unlike water's coplanar flood, volume search crosses vertical walls, not disconnected islands or protected slice/region boundaries. Both use existing Model color distance/indexing. `ember_voxel_selection.gd` is an incremental pure job; `ember_voxel_selection_panel.gd` owns controls, mask and one derived MultiMesh overlay. Native Godot APIs suffice: no addon data owner, schema change or new runtime renderer.

Search and overlay transforms use a ~3 ms frame-loop budget; individual completion allocations/union/commit are not hard realtime. A 32,768-voxel cap rejects the entire oversized result and keeps the previous mask. Paint is disabled while busy. Painting uses SculptActions Undo; geometry, material/fill channels and palette stay unchanged. Mask survives its own paint; other source edits/Undo, model/scope changes clear it. Hiding Canvas cancels search and exits acquisition. Mask itself is not serialized or in Undo. Brushes are explicitly NOT masked yet.

Gate: `test_voxel_selection.gd` checks 3D/interior/similarity/islands, bounds, cap/cancel, viewport click (no brush), union/subtraction, water/material protection, one-action Undo, save and mask lifecycle. Forward+ capture inspected at 1280×720. Existing palette, slice, Canvas, native and world tests pass. Existing sculpt timing assertion failed once (packed 14.398 ms vs dictionary 13.702 ms), passed unchanged on repeat (8.513 vs 12.202 ms); no mesher code/test threshold changed to hide timing variability.

Next: named groups with save/Undo/lock/isolate semantics, then supported masked brush operations. Earlier full-editor lifecycle, remembered views, Graph hierarchy and large-map storage backlog stays open.

## Update 2026-09-05 · v2.40 palette authoring

First color slice complete: bounded swatch grid, add/edit via stock ColorPicker, canonical-color eyedropper (I in viewport, Esc), replace-and-remove with explicit replacement. Dialogs distinguish global swatch edits (including hidden/out-of-region voxels and water) from local painting. No live world rebuild on ColorPicker drag; confirmation creates one existing sculpt Undo action. Dialog body scrolls at small viewport sizes, while Apply/Cancel remain visible. Resource switch, Undo that changes the palette, and hidden workspace invalidate pending dialogs.

Pure `ember_voxel_palette_model.gd` computes palette/voxel/water-index remapping; `ember_voxel_palette_panel.gd` owns only UI. Workspace remains the source owner; no new schema, addon or renderer. Zero stays reserved for empty terrain/automatic water tint; max 255 authored colors. Selection retains surviving color identity across index shifts. `test_voxel_palette.gd` checks both remap directions, capacity, source immutability, water, save/discard, Undo/Redo, stale dialogs, eyedropper and slice sampling. Forward+ 1280×720 screenshots verify the panel and dialog.

Next bounded slices: (1) reusable voxel selection with add/subtract, connected/all similar color scope and a visible selection mask; (2) named voxel groups with isolate/lock and round-trip/Undo semantics; (3) palette convenience such as named ramps/reuse, once selection ownership is settled. These are not implemented by this palette slice. Earlier open items (editor-close save lifecycle, remembered views, Graph hierarchy, large-map storage) remain open.

## Update 2026-09-05 · v2.39 height slices

First explicit height-slice gate implemented in the Surface sidebar: enable + lower visible voxel count, with a closed cut surface, matching picking and write protection. It is an upper cut plane from the bottom, not an isolated-layer/range editor. Same-resource navigation retains the view; another resource starts at full height. View state never enters Resources. Changing the limit commits a live gesture before changing bounds; preview chunk requests are replaced, not full model data.

Local volume/color/material brushes are supported. Column relief/level/smooth/ramp, level fill and connected-material flood are deliberately unavailable in a slice; water is temporarily hidden. This limitation is visible in disabled tools and contextual help. `test_surface_height_slice.gd` covers scope, hidden bytes, backend cap parity, round-trip and Undo/Redo; 1280×720 Forward+ capture confirms control visibility. Remaining: whole-editor save lifecycle, remembered view settings, Graph toolbar hierarchy, larger-map storage. General slice ranges and column tools inside slices need their own validated semantics.

## Update 2026-09-05 · v2.38.1 lifecycle gate

The v2.38 Graph blocker below is fixed. Native GraphEdit queues frame ordering (see [engine implementation](https://github.com/godotengine/godot/blob/master/scene/gui/graph_edit.cpp)); synchronous removal raced those deferred commands. Old frames now detach members, retire hidden under unique names and remain children until queued deletion. Active-element queries exclude retiring frames. Quest objective focus also frees the temporary root card that was constructed but never parented. No document schema or Graph layout redesign was introduced.

Full Graph smoke now has no prior move_child or shutdown leak messages. `test_graph_lifecycle.gd` exercises same-tick rebuilds and three mount/unmount cycles with stable orphan-node counts. The toolbar UX and Surface height-slice backlog remain open; this patch only closes the reliability gate.

## Update 2026-09-05 · v2.38

Historical finding, fixed in v2.38.1: `test_graph_workspace.gd` passed assertions but emitted native `move_child` errors and shutdown leaks. No Graph production changes were made in v2.38 itself.

Surface reliability slice implemented: dirty marker and Ctrl+S; save/discard/stay on cross-resource navigation (failed save keeps draft); same-resource area navigation retains baseline; discard restores the shared Resource in place. Hidden workspaces stop live gestures, tool changes retain the gesture's original channel. Grid/region visibility and bed-only inspection are editor state, never serialized into content. Level fill exposes the existing palette tint channel without painting over the bed. Runtime Forward+ layout inspected at 1280×720 and 1600×900; actual docked editor theme/scale remains a manual gate.

Remaining, in order: explicit height slices for volumetric editing; scene/editor-close save integration and persisted camera/view preferences; stable Graph primary toolbar; narrow Inspector hierarchy; migration inventory and native-only exit gates. These are not implied complete by the Surface navigation dialog. For editor-close integration use the native [EditorPlugin save hooks](https://docs.godotengine.org/en/4.5/classes/class_editorplugin.html#class-editorplugin-private-method-get-unsaved-status), with an explicit failed-save gate before claiming loss protection on editor exit.

Status: active UI plan from Godot Migration v2.23. This document covers the
authoring addon only. It does not introduce a second content schema, renderer,
or runtime owner.

## Reference model

The addon follows three established editor conventions:

- Like Blender, the viewport exposes one active tool for the current context.
  Only the tool and its frequently changed settings belong in the top strip.
- Detailed properties belong in the Inspector or a resizable sidebar. They are
  not duplicated as permanent viewport buttons.
- Multi-step jobs belong in a dock or full workspace. A toolbar starts a job;
  it does not contain the whole job.

Primary references:

- Blender Tool System: https://docs.blender.org/manual/en/4.5/interface/tool_system.html
- Blender 3D Viewport Sidebar: https://docs.blender.org/manual/en/5.3/editors/3dview/sidebar.html
- Godot editor plugins and docks: https://docs.godotengine.org/en/stable/tutorials/plugins/editor/making_plugins.html
- Godot Inspector plugins: https://docs.godotengine.org/en/stable/tutorials/plugins/editor/inspector_plugins.html

## Shared layout contract

Every Ember authoring surface should use the same hierarchy:

1. Context: which content or scene is being edited.
2. Active tool: the current gesture or operation.
3. Tool settings: only values used repeatedly while that tool is active.
4. Selection properties: Inspector/sidebar, stable width, scrollable.
5. Secondary actions: one `Ещё…` menu near the active tool.
6. Status: short text in the strip; the full message is available as a tooltip
   or in diagnostics.

Controls that do not apply to the open scene or current mode are hidden, not
disabled in-place. Destructive actions remain named and visually distinct.
Authoring view state may remember panel sizes and selections, but does not enter
gameplay Resources.

## Findings and slices

### P0 — 3D viewport chrome (implemented in v2.23)

The world Surface selector and Battlefield painter were added to the same Godot
container and remained visible together. On a world map this consumed most of
the 3D header with disabled battle controls; on a battle scene the reverse was
also possible.

The toolbars are now contextual and mutually absent outside their valid owner.
Battlefield keeps `Поле боя` and, while painting, brush/shape/group. Tile
library, resize and Surface handoff live in `Ещё…`. World keeps selection and
opening the selected region; whole-map opening lives in `Ещё…`. Long status
text is clipped with the full value in a tooltip.

Manual gate: open `agent_sandbox.tscn`, a combat arena, then a scene without an
Ember map. The header must show respectively World Surface, Battlefield, and no
Ember viewport toolbar. Resize the editor to 1280 px; no Ember control may push
Godot's native viewport menu off-screen.

### P1 — Ember Graph navigation

The workspace already hides many mode-specific controls, but one flow container
still owns navigation, creation, graph editing, grouping, history and saving.
Wrapping changes the graph height and makes actions move between modes.

Next slice:

- stable first row: content kind, resource picker, refresh, save/status;
- local tool row: add-node and selected-node actions only;
- move arrange, clipboard and grouping to menus or keyboard-first commands;
- keep the right editor width stable and persist the split ratio;
- label focused quest/object context as a breadcrumb rather than another action.

No quest/dialogue/action document changes are required.

### P1 — Surface Canvas (implemented in v2.24)

The old canvas placed tool, radius, region, relief parameters, palette, five
camera actions, reset and save in one wrapping row. V2.24 replaces that row
with a stable workspace:

- a narrow left tool rail with one visible selection owner for sculpt tools;
- one top tool-settings strip for radius, strength/rate/cap and material;
- camera presets/settings in a single View menu;
- region actions and current bounds in the scrollable right sidebar;
- save and dirty state in a stable workspace header;
- short contextual help for the active tool instead of one permanent manual;
- a resizable viewport/sidebar split with the existing safe render-target cap.

Brush formulas, Undo/Redo and the Surface Resource remain unchanged.

Manual gate: switch through every tool and confirm that only its relevant
settings appear in the top row; resize the main screen and right sidebar;
exercise every View menu action, area selection, save and pilot reset.

Hotfix v2.24.1 makes the workspace a real Godot main-screen plugin named
`Surface Canvas`, beside `Ember Graph`. The adapter instantiates the same
workspace class and uses the same actions/Resources; it owns no data or render
contract. World and battle handoffs target the dedicated screen. The old
`Voxel Surface` entry is removed from the visible Graph content selector; its
embedded instance remains temporarily as a recovery path if the thin screen
adapter is manually disabled.

### P2 — Inspector authoring

The native Inspector integration is the correct owner, but interaction cards can
show six or more equal-looking buttons. Their importance is not obvious.

Planned hierarchy:

- one primary action matching the component (`Настроить`, `Открыть задание`);
- related creation/link actions in `Добавить…`;
- source/rebuild/navigation in `Ещё…`;
- delete at the end of the menu with explicit wording;
- validation above action buttons, with a direct fix/focus command when known.

Keep all existing Undo/Redo commands and scene-owned references.

### P2 — Migration bottom panel

The bottom panel is already scrollable and sectioned, but it mixes daily object
work with one-time migration and diagnostics. It should become a task dashboard:
`Текущий объект`, `Импорт`, `Диагностика`, with migration sections collapsed by
default after the JOI exit gate. Long logs belong in Output; the panel should
show summary, counts and the next safe action.

### P3 — Visual libraries and forms

The searchable thumbnail libraries are the strongest existing pattern and
should be reused for every visual choice. Forms should use the same label width,
source badges, empty-state copy, primary button placement and destructive color.
Russian author-facing labels should be preferred; technical IDs remain visible
as secondary text with copy support.

## Acceptance rules for later slices

- Test at 1280×720, 1600×900 and a narrow Inspector.
- Keyboard focus must not steal viewport gestures or global Undo/Redo.
- A mode switch must not move the primary save/navigation controls.
- Hidden controls cannot retain an active gesture.
- Tooltips explain effect and ownership, not only repeat the label.
- Every content mutation keeps existing save/reopen and Undo/Redo gates.
- UI-only state never changes canonical `.tres` or scene serialization.

## V2.56 stop-line

Ранее перечисленные Surface lifecycle/view, Graph hierarchy, narrow Inspector и
migration inventory закрыты последующими v2.40–v2.55 срезами и их targeted
gates. Основной editor считается завершённым перед design Q&A. Новая общая
полировка не начинается без конкретного production workflow, который нельзя
выполнить существующими Surface Canvas, Ember Graph, Object Inspector и bounded
migration dashboard.

Последний read-only профиль не нашёл безопасной signature-only партии среди 25
stale `fan_town` prefab: все меняют видимые voxel-грани, 18 меняют collision,
три emissive-кандидата затрагивают свет/тени. Это отдельное визуальное утверждение
контента после дизайн-документа, не UX-долг редактора.
