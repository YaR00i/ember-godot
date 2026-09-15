# Water W01 review

Native screenshots and real-frame motion are in qa/. Main integration/art/input OPEN.

Compare stand-before.png against stand-close.png; the same camera/time/QA
environment shows only the water material change. stand-night.png includes a
separate warm OmniLight; water creates no light. water-motion.gif is a4s
sequence of48real native frames at12fps, not an AI-generated animation.

Review actual authored cases separately: w01-authored-before/candidate-pier
and -world near/overview. QA cases w01-before/candidate-pier and -corner use
added Sky/ReflectionProbe/specular lights and are explicitly demonstrations.

Reproduce in the owned disposable Temp project, never --headless --editor in
the working checkout:

- godot --path TEMP --script res://tools/render_water_stand.gd
- python tools/encode_water_motion.py TEMP/art/water/qa
- godot --path TEMP --script res://tools/render_water_refinement.gd -- --mode=pier --label=w01-candidate --water-probe
- add --water-baseline with labelw01-before for the pre-W01 material
- use --water-authored instead of --water-probe to keep authored environment/lights
- godot --path TEMP --script res://tools/test_water_material.gd
- godot --path TEMP --script res://tools/test_water_pattern_seams.gd
- python tools/check_water_sources.py TEMP GRAPHICS_WORKTREE

See HANDOFF.md for exact owners, parameters, known probe warning and integration limits.
