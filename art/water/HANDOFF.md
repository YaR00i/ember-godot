# Water W01 — optical waves, real reflection and light-driven glints

2026-09-15. User approved calm stylized water after the material library.
Implemented in graphics d97c, existing Surface water owner. Main checkout is
read-only; main integration and manual art/input acceptance remain OPEN.
No commit/push. Previous lighting/M01/M02 evidence and the pre-W01 backup remain.

## Transfer

Production: shaders/ember_voxel_surface_water.gdshader and
materials/ember_voxel_surface_water.tres. Existing diorama include unchanged.
Source/schema/mesher/Resource/editor/physics/terrain/author scenes unchanged.
The shader also services the authored Pier backdrop via its existing material;
do not replace the whole authored scene to apply W01.

Targeted test update: tools/test_water_pattern_seams.gd only isolates optical
waves/specular from the legacy camera-colour continuity diagnostic and recognizes
the new render-mode string in its unshaded noise diagnostic.
New QA: tools/test_water_material.gd, tools/render_water_refinement.gd,
tools/render_water_stand.gd, tools/encode_water_motion.py,
tools/check_water_sources.py. render_water_refinement extends the existing owned
tools/render_diorama.gd; both are QA dependencies, not another production renderer.

Pre-W01 shader and material are in checkpoint-pre-w01 with .gdignore. They are
read as text only for controlled QA comparisons, never assigned as runtime assets.
W01 diff against that checkpoint will be supplied as refinement.patch.
Transfer only the W01 documentation excerpts, never whole stale graphics docs.

## Material behavior

Two world/block-coordinate wave fields, bent by continuous shared noise, perturb the optical top-face
normal. No vertex displacement, water-level change or collider change. Side
normals of the existing harbour BoxMesh remain geometric. The field preserves
the existing coordinate_scale and complete-map coordinates across technical
chunks/independent translated halves. Screen-footprint suppression reduces
subpixel wave detail, without a claim of alias-free rendering at every scale.

The accepted stylized diffuse remains in the shared/custom light response.
It uses the geometric normal of the physical plane, so tiny optical slopes
cannot cross toon thresholds and paint long stripes. Optical normals affect
the real specular/reflection path instead. This is an intentional stylized
separation of body colour from surface reflection, not a displaced liquid mesh.
The global diffuse_toon render flag was removed: in Godot 4.7.2 its indirect
specular path multiplies by metallic, zeroing dielectric water reflections.
specular_occlusion_disabled also avoids the ambient-luminance heuristic zeroing
sky reflection when diffuse ambient is off. Both findings were traced to the
[Godot 4.7.2 renderer](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl).

Direct specular uses GGX distribution, Smith visibility and Schlick Fresnel;
default specular0.36 yields F0≈0.0207, matching water's approximate dielectric
normal-incidence reflectance. Surface roughness defaults0.28. Stylized body is
not a complete energy-conserving liquid BRDF. No spectral dispersion/refraction,
caustics, true planar mirror or fluid simulation added.

Sky/ReflectionProbe reflections use Godot's normal indirect-specular path.
Library/material never creates lights, Sky, probes, a camera or another pass.
The optional fixed sky colour remains a separate artistic tint with default
reflection_strength0. Existing decorative dash controls remain, gated by
decorative_glints=false, including authored backdrop overrides. Body emission
defaults0, so water is not self-luminous at night.

Existing UV.x derived 1–4+art-voxel depth bands remain the source of colour/alpha.
Shallow opacity0.56→0.42, deep0.78 retained. This is not metre-based scene-depth
absorption. Broad colour islands retained but patch_strength0.35 suppresses them;
palette tint, foam geometry/shader, contacts and wakes keep existing owners.
Terraced authored bottoms still show their actual side faces through clear water.

ShaderMaterial-only controls: wave_length1.6 block units, wave_speed0.35 radians/s,
wave_strength0.10 normal slope, surface_roughness0.28, highlight_strength0.36,
body_emission0, patch_strength0.35, decorative_glints=false. No per-object or
per-voxel schema fields/editor persistence tools were introduced.

## Evidence and limits

Native Vulkan Forward+ on Godot4.7.2/RTX5070, disposable Temp graphics project.
Baseline/candidate use the same camera, frozen water/foam times and QA environment.
Baseline Surface values are read exactly from the pre-W01 .tres; the Pier
background uses the original scene's explicit water parameters plus the old
shader's defaults, retaining coordinate_scale16 and render priority0.

`stand-before/stand-close/stand-night` and48actual motion PNG are a demonstration
with QA-only Sky, one local ReflectionProbe and lights with specular enabled.
water-motion.gif is encoded from those frames at12fps with a shared palette.
The normal motion is continuous; legacy colour bands remain stepped. GIF
quantization is not a claim about native colour fidelity or runtime FPS.

`w01-before/candidate-corner/pier` compare a configured QA environment with a
probe. `w01-authored-before/candidate-world/pier` retain authored environment and
light settings, without added Sky/probe or changed light_specular. They still
include the previously authorized diorama lighting candidate and freeze actor
physics solely for repeatable imagery, not input/gameplay acceptance.

Actual Sky and local-object reflections need scene reflection sources. Authored
BG_COLOR/no-Sky environments cannot supply an actual reflected sky, and absent
probes cannot reflect off-screen geometry. Direct glints require light_specular>0.
Production environment/light integration is a separate main-owner step.
Probe cubemap/box projection is approximate, especially on broad flat water;
it is not a planar mirror and may have displaced/blurred object reflections.

Known engine cleanup warning remains: a native scene with one ReflectionProbe
reports7TextureRIDs on shutdown, previously isolated in M02 and matching
[Godot#122498](https://github.com/godotengine/godot/issues/122498). No engine fix,
upgrade or production probe lifecycle claim. The no-probe Sky/alpha test exits
without this warning. Failed first/no-diffuse-toon Sky tests are retained: they
exposed the ambient-based specular-occlusion issue, then passed after both
render flags were corrected. No failure was relabelled as PASS.

Manual: inspect motion/brightness/colour/depth near and far on day/night maps;
check water/foam against rocks, pier supports, authored terrain and gameplay
contacts; accept visual direction before production environment integration.

## Validation

Results/log index and final source guard are recorded in qa/ and README.md.

Headless PASS: test_water_material, test_native_surface_water,
test_voxel_cartoon_water, test_water_contact_boundaries, test_water_pattern_seams,
test_voxel_palette, test_voxel_prefab_rebuild, test_diorama_materials,
test_voxel_fragment, test_world_surface_projection. Fragment's unchanged test
reports one ObjectDB instance at shutdown; baseline causality was not measured.
Diorama test retains old FanTown invalid UID/text-path fallback warnings.
These diagnostics are not silently included in a clean-shutdown claim.

Native material probe: shallow/deep red backing transmission0.7843/0.4118;
actual red/green Sky reflection0.1529 in its own channel, direct and ambient0.
Native normal/time/specular stand and exact custom material reopen PASS.
Native split/noise/perspective-camera diagnostic passes; its legacy colour-only
continuity portion explicitly disables optical waves/specular so a real
highlight is not mistaken for a colour interpolation cut.
429canonical source bytes unchanged;18non-water shader/material/library files
identical in graphics and QA. These checks do not require old water PNG equality:
the W01 water appearance is intentionally changed.

All12M02 material-library native PNG re-rendered byte-identical, preserving
colour/highlight/texture/alpha/emission/leaf response. Native Surface stock versus
native adapter water/foam returns0different pixels/8171visible water pixels.
Native object water motion changes6913pixels in the final gate. The isolated
headless editor import completed with exit0/noERROR/SCRIPTERROR, retaining only
the already recorded FanTown invalid UID/text-path fallback warnings.
GPU timers in QA logs are one-run viewport proxies with QA probes/environment,
not matched gameplay FPS or an optimization claim.
