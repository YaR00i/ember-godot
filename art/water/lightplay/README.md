# W04 review2 visual choices

- `close-current`: unchanged W03 control.
- `review2-close-sharp`: intact cyan-white light cells without random breakup.
- `review3-close-connected`: the same cells with spatial/phase cohesion and gap hold.
- `review4-close-flowing`: one advected light field; all boundary cells share its
  right/down flow instead of receiving isotropic neighbour support.
- `review5-close-patches`: broad curved connected light regions, shaped like shadow
  silhouettes and translated intact across the water.
- `review6-close-wobble`: the clean review2 optical highlights sampled continuously;
  their edges bend and breathe instead of switching between world cells.
- `review7-close-standing`: sharper continuous highlights with almost no translation;
  their boundary still deforms through an independently timed wobble.
- `review2-close-shadow`: clean cells plus the snapped/quantized pier shadow.
- `review2-close-caustics`: review2 shadow plus shallow bottom light/refraction.
- `review2-game-caustics`: the full review2 candidate at normal fixture scale.

Every listed directory contains48native PNG frames and `water-motion.gif`.

Run `water_lab.bat` for live Forward+ tuning. The stand edits a material duplicate;
`Копировать настройки` writes portable JSON to the clipboard and user data folder.
The Water Lab sun is fixed in world space. `Зависимость от камеры` ranges from0
(stable authored pattern) to1 (physical half-vector response); the stand starts at0.15.
