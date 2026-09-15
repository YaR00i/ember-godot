# Water W04 review2 — clean highlights, quantized pier shadow and light play

Status: native visual probe complete; user art choice and main integration OPEN.

Review3 added optional `pixel_highlight_cohesion`, default0. At1 the shader averaged
the current light alignment over four neighbouring world cells and nearby animation
phases, closes one-cell gaps between opposite lit neighbours and briefly retains a
near-threshold cell when a neighbour/adjacent phase supports it. The review2 sharp
render remains pixel-exact at cohesion0. Evidence: `qa/review3-close-connected`,
48native frames and a4s 12fps GIF. User rejected it because isotropic neighbour/phase
support let boundary cells travel sideways away from the main shape.

Review4 replaces that rejected behaviour at cohesion1 with one frozen light field
advected along `pixel_highlight_flow_direction` at `pixel_highlight_flow_speed`.
Five-cell spatial filtering shapes the field, but cells receive no independent
neighbour motion: they enter at the leading edge and leave at the trailing edge.
Evidence: `qa/review4-close-flowing`,48native frames and4s GIF. The review2 sharp
control remains pixel-exact at cohesion0. User direction/shape acceptance is OPEN.

Durable review3 evidence, all captured after the current final code:

- `qa/review3-native-test_water_lightplay.log`: sharp response36423, cohesion
  response34601, shadow and caustic assertions PASS.
- `qa/review3-headless-test_water_lightplay.log`: all W04 defaults, including
  cohesion0, PASS.
- `qa/review3-native-test_water_material.log` and
  `qa/review3-headless-test_water_material.log`: custom cohesion clone/save/reopen
  and existing owner/live-time assertions PASS.
- `qa/review3-control-review2-pixel-exact.log`: current cohesion0 and saved review2
  motion-000 are1280x720 pixel-exact with identical pixel SHA-256.
- `qa/review3-source-guard.log`:429 canonical sources unchanged; only the existing
  material stand remains the known source addition.
- `qa/review3-non-water-guard.log`:18 owned non-water files match the fixture.
- `qa/review3-package-run.log`: W03 checkpoint, six48-frame sequences, clean logs
  and reverse-applicable package PASS.
- `qa/review3-reverse-patch-command.log`: direct `git apply --check --reverse` PASS.
- `qa/review3-final-log-audit.log`: all nine exact evidence logs present and clean.

Current review4 evidence: `qa/review4-native-test_water_lightplay.log` validates the
new FLOWING path (96867pixels over8levels) plus prior sharp/shadow/caustics;
`qa/review4-headless-test_water_lightplay.log` and
`qa/review4-headless-test_water_material.log` validate default0 and custom parameter
storage; `qa/review4-control-review2-pixel-exact.log` proves cohesion0 still matches
the saved review2 frame. Review3 logs remain historical evidence for the rejected
algorithm, not claims about current cohesion1 behaviour.

User then clarified that direction alone was insufficient: highlights should have
the broad, bent, connected silhouette of the pier shadow. Review5 replaces the
cohesion1 mask with a thresholded two-octave smooth field, stretched along the flow
axis and sampled only at highlight cell centres. The field coordinate is translated
as one unit, so topology stays intact and only its contour is pixelated. Evidence:
`qa/review5-close-patches` (48 Forward+ frames + GIF),
`qa/review5-native-test_water_lightplay.log`, headless lightplay/material logs and
`qa/review5-control-review2-pixel-exact.log`. Shape0 remains pixel-exact to review2;
review5 user art acceptance is OPEN.

Review5 was then rejected because translating its broad mask read as moving spots.
Review6 returns to the clean review2 optical-normal mask and changes only its motion:
sampling moves from world-cell centres to continuous surface coordinates, while two
weak counter-moving low-frequency offsets make the thresholded edge breathe and bend.
The bright two-band interior has no hash breakup. Evidence:
`qa/review6-close-wobble` (48 Forward+ frames + GIF),
`qa/review6-native-test_water_lightplay.log`, headless lightplay/material logs and
`qa/review6-control-review2-pixel-exact.log`. Smooth motion0 remains pixel-exact to
review2; review6 user art acceptance is OPEN.

User found review6 closer but too soft and visibly travelling toward the sea. Review7
adds independent travel/wobble speeds: the candidate sets travel0.02, wobble1.15,
threshold0.991/core0.998 and strength1.10 in Water Lab. The shape therefore stays near
its original area while its boundary keeps deforming. Evidence:
`qa/review7-close-standing` (48 Forward+ frames + GIF), native/headless lightplay and
material logs, and `qa/review7-control-review2-pixel-exact.log`.

`scenes/water_lab.tscn` and `tools/water_lab.gd` expose the existing ShaderMaterial in
four Russian tabs. `water_lab.bat` prepares a clean generated Forward+ runtime through
`tools/run_water_lab.ps1`; no author map or canonical material is copied back. The
Copy button places portable JSON in the clipboard and `user://water-lab-selection.json`.
`qa/water-lab.png`, `qa/water-lab-capture.log` and `qa/water-lab-native-test.log`
verify the actual RTX5070 UI, live parameter route, presets/reset/export and source
invariance. User tuning and art acceptance remain OPEN.

The first interactive Water Lab build incorrectly aligned the sun to the camera on
every orbit, so the user's90° view change also moved the light. `_update_camera()` now
changes only the camera. `pixel_highlight_view_dependence` adds the second necessary
control:0 uses camera-stable sun-crest alignment,1 uses the physical half-vector and
the stand starts at0.15. Default1 follows an explicit legacy branch and remains
pixel-exact to Review2. Evidence: `qa/water-lab-fixed-sun-a.png`,
`qa/water-lab-fixed-sun-b.png`, current `qa/water-lab-native-test.log` and
`qa/review8-control-review2-pixel-exact.log`.

The first W04 art probe was rejected because random highlight holes looked dirty,
shadow filtering remained soft and the low disposable pier hid its shadow below the
deck. Review2 removes the highlight hash entirely. `pixel_highlight_mix` now replaces
only direct-light GGX with intact two-band world cells; Sky/probe reflections remain
the W01/W02 path. `pixel_highlight_cell_size`, thresholds, strength and tint are
independent controls.

`stylized_shadow_mix` snaps water `LIGHT_VERTEX` to a world-cell centre before the
renderer calculates its directional shadow, then thresholds and posterizes
`ATTENUATION`. The art probe uses `SHADOW_QUALITY_HARD`, zero sun angular distance and
a raised version of the same disposable pier so the boards/posts cast a visible
shadow into open water. Runtime project shadow quality remains unchanged pending a
style-wide decision; the QA hard filter is not hidden in the material.
`underwater_light_mix` nearest-samples the opaque screen/depth buffers, pixelizes a
small normal-driven offset, reconstructs visible bottom world position and adds two
moving cellular light fields. View depth and sampled luminance suppress the effect
in deep or shadowed water.

The canonical material stores all parameters but keeps highlight, shadow and
underwater mix at0. W03 output is therefore the exact control state; the comparison
tool applies candidate values only to its duplicate. This is a screen-space visual
approximation. It does not project light into arbitrary materials, create a volume,
cast shadows from the transparent water or define swimming/refraction gameplay.

Native comparison: unchanged `qa/close-current` plus `qa/review2-close-sharp`,
`review2-close-shadow`, `review2-close-caustics`, and `review2-game-caustics`; each
has48actual Forward+ PNG frames and a4s 12fps GIF. `review3-close-connected` adds the
same evidence for the cohesion candidate. The earlier W04 probe and failed
iterations remain as audit evidence and are not the current recommendation.

`test_water_lightplay.gd` executes the production shader in Forward+: clean direct
lighting changes36423pixels over24levels and reduces >240 bright pixels19181→2245;
snapped/quantized shadow changes20446pixels over8levels; with surface motion disabled,
underwater light changes23996pixels and its time change affects14395. Cohesion changes
345612pixels over8levels versus sharp; review6 smooth motion changes31791pixels with
average0.9425. The disabled rerender is pixel-exact to the saved review2 frame.
Targeted native + save/reopen/headless PASS; the preceding
7native and13headless review2 regressions remain green. The known
QA ReflectionProbe shutdown7TextureRID remains a separate engine diagnostic.

Transfer `refinement.patch`, its marked documentation sections and the production
shader/material plus adjusted/new tests and render tool. No commit/push was made.
