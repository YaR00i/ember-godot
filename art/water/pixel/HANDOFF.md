# Water W02 — pixel optical ripples, art acceptance OPEN

2026-09-15. User approved a native A/B after liking W01 movement: pixel-shaped
reflections/highlights with a more turquoise palette, inspired by the movement
of resort water in ZZZ. This is a continuation of the existing Surface water
material in graphics d97c, not main editor implementation or a new renderer.
User also described future occasional swimming between islands; no swimming
mechanics, new travel rules or character water interaction are defined here.

Production changes: `shaders/ember_voxel_surface_water.gdshader` and
`materials/ember_voxel_surface_water.tres` only. No Source/mesh/physics/level,
scene environment, foam/contact/wake, object/editor schema or material-library
change. Main checkout remains read-only. Commit/push were not requested.

## Material

`reflection_pixel_size` is a cell size in the existing normalized block-space:
0.0625 = one voxel, 0.125 = two voxels when the normal block scale is used.
Canonical candidate is one voxel; two-voxel native comparison is also supplied.
`reflection_pixel_strength` 0..1 blends continuous and cell-sampled wave slopes;
0 restores continuous W01 optics. Both parameters live on ShaderMaterial and
survive independent clone/save/reopen. No per-voxel material schema added.

Cells use `floor(surface_coordinate / size)` at a fixed world grid. Wave time
is continuous, and the same bent two-direction field from W01 is sampled at
the cell centers. Optical NORMAL drives existing Godot Sky/probe reflections
and existing direct GGX highlights. VIEW is never angularly quantized; with
perspective viewing, reflection composition can still vary within a cell.
This is pixel-shaped optics, not a full-screen or final-colour pixel filter.

Original continuous slopes still determine the optional body-facing tint and
opacity. Broad depth/palette/patch bands retain their W01 behavior; the body is
not newly pixelated. Side normals remain geometric. Derivatives come from the
continuous coordinate: cells fade into continuous optics between0.75and2pixels
of conservative screen footprint, retaining W01's wave-detail suppression.
This reduces subpixel detail; arbitrary camera paths are not proven alias-free.

New .tres colours: tint(0.12,0.78,0.80), shallow(0.20,0.78,0.76),
deep(0.035,0.40,0.52). Opacity0.42/0.78, wavelength1.6, speed0.35,
slope0.10, roughness0.28, dielectric specular0.36, patch0.35 stay unchanged.
Authored embedded materials can still override colour: applying the shared
shader does not rewrite those scene-owned values. Retune them after art acceptance.
No bottom refraction, caustics, planar mirror, geometry waves or fluid simulation.

## Native evidence

`tools/render_water_pixel.gd` extends the W01 stand, reuses the same Source and
Surface mesher, lights/Sky/probe. No author map is modified or saved. Close/game/
wide views include exact W01 material reconstruction and one-/two-voxel candidates.
Close `smooth` uses W02 colours with pixel strength0 to isolate colour from optics.
Perspective candidate and frozen-water camera-translation frames are included.
The broad44x44material fixture adds simple disposable island markers and an
opaque distant-water ring outside the Source footprint, without an overlapping
second layer over its actual transparent shallow/deep water.

11sequences each have48actual native PNG at12samples/s, encoded by the existing
GIF tool. These are4second demonstrations, not generated artwork or measured FPS.
The frozen camera-translation strips have24frames for each of the4fine views.
Seven final-code captures(close/game/wide fine/coarse, perspectivefine) are
byte-identical to their preceding captures after the final equivalent shader
branch refinement; `qa/final-code-spot-check.log` records this.

The wide direct-sun example exposes fairly dense repeating glints at wavelength1.6;
this is a real art decision still open for long island travel. Do not call W02
accepted or silently integrate a different wavelength/sun setup to hide it.
All stands have QA-only configured reflections/specular lights. Production
Sky/probe/light integration remains the main owner step, including W01 limits.

## Validation and retained diagnostics

11headless gates PASS: water material/pixel, native Surface, cartoon object
water, contacts, pattern seams, palette, prefab rebuild, diorama, fragment,
world projection. Native5gates PASS: material, pixel, seams, native Surface,
cartoon water. Isolated headless editor import PASS (never working checkout).
429canonical Source bytes unchanged; the existing material stand is the sole
Source addition from M01. W01 checkpoint hashes match its final manifest;
unchanged W01 QA code is verified against its manifest;18graphics-owned non-water
files are identical between graphics worktree and disposable fixture. Other main
owner files are not replaced to match this older graphics checkout.

Native optical diagnostic executes the production fragment and only replaces
the colour output to expose NORMAL. Within-cell max0; split at worldx=-0.63
(not a cell edge), significant pixels0/average0; negative/positive coordinates
covered. Disabling pixels restores continuous variation in475/576samplecells;
changing size/time changes the field; subpixel cells exactly converge to smooth
normals. Real Sky/alpha probes stay0.1529red/green reflected channel, shallow/deep
red backing0.7843/0.4118. Native stock/adapter water0different/8171visible pixels;
object water motion6741changed pixels.

An initial diagnostic failed because camera unprojection used the project's
logical1280x720viewport while the captured image was512x512; its probes sampled
clamped black borders. Explicit matching `content_scale_size` fixed the fixture.
Original failure/log/images remain in `qa/failed-logical-viewport`; it is not
reported as a production bug or relabelled PASS. Active final logs have no
ERROR/SCRIPTERROR/FAIL. Existing FanTown/Sandbox UID warnings and fragment1ObjectDB
shutdown warning remain separate. QA ReflectionProbe retains the previously
isolated Godot4.7.2 shutdown7TextureRID warning, no engine lifecycle fix/claim.
QA evidence directory has .gdignore to avoid importing hundreds of render frames.

## Transfer and manual acceptance

W02 `refinement.patch` is incremental to W01 (water2files, material storage test,
new pixel capture/test+UIDs); reverse apply check is supplied. QA additionally
needs prior W01 stand/helpers/diorama include, checkpoint-w01 as ignored text
backup, and pixel evidence. Transfer only `documentation-sections.md` into the
current main docs, never these stale whole graphics docs.

Manual: choose one-/two-voxel look from animations, inspect game/near/wide water,
day/night brightness and terrain/rock/pier contacts in Forward+. Main integration,
art/input acceptance, swimming and actual bottom refraction remain OPEN.
