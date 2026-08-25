# Lighting gate

Look at `scenes/fan_town.tscn` in Godot 4 Forward+ (night, orbit camera). Tick only what you see. JOI play/editor stay put until this passes.

## Must pass

- [ ] Night fill from many lanterns, not a flat ambient wash
- [ ] Several lamp umbras on the ground at once (OmniLight shadows, not one sun blob)
- [ ] Looking around does not hitch or freeze the editor/game

## Optional (nice, not a reason to rewrite JOI)

- [ ] Windows glow as fill without stealing umbra budget
- [ ] Fog / bloom from the map `light` block feels like the JOI look preset

## If it fails

Stay in JOI for mechanics (`agent_sandbox`) and content. Do not extend the Three atlas. Do not start Godot play.

## If it passes

Next is walk/camera using Ember tile math, still reading `content/ember`. Map editor last. JOI Conductor stays the soul/session shell.
