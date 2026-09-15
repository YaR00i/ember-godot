# Water pixel comparison

Review `qa/close-{w01,smooth,fine,coarse}/water-motion.gif` with the same camera.
Fine=one voxel, coarse=two voxels; smooth isolates new turquoise colours with
continuous W01 optics. `game-*` and `wide-*` use the same three variants. Broad
water is a material fixture, not an implemented gameplay island/swimming map.
All PNG/GIF come from actual native Godot rendering; .gdignore skips asset import.

Reproduce in a disposable graphics project that already includes W01:

- godot --path TEMP --script res://tools/render_water_pixel.gd -- --variant=fine --view=close --motion
- replace fine with w01/smooth/coarse; view with game/wide/perspective
- python tools/encode_water_motion.py TEMP/art/water/pixel/qa/close-fine
- godot --path TEMP --script res://tools/test_water_pixel.gd
- godot --path TEMP --script res://tools/test_water_material.gd
- python tools/check_water_sources.py TEMP GRAPHICS_WORKTREE

Native pixel test uses a matching512x512logical viewport; the first mismatched
viewport failure is archived separately. See HANDOFF.md for exact acceptance,
source guard, incremental transfer and known engine/probe limitations.
