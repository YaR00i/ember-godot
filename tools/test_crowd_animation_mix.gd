extends "res://tools/test_world_gameplay_stress.gd"
## Native Forward+; use mode=cpu-hub and EMBER_STRESS_MOTIONS=<retargeted motion.res>.
## Uses the existing populated world, physics and Hoshi presentation owners.
const MIX:=["idle","walk","run","talk","sit","dance"]
var observing:=false
var last_clips:Dictionary={}
var seen:Dictionary={}
var changes:Dictionary={}
var phases:Dictionary={}
var simultaneous_changes:=0
var minimum_clip_types:=99

func _initialize()->void:
 var path:=OS.get_environment("EMBER_STRESS_MOTIONS")
 if run_mode!="cpu-hub" or path.is_empty():
  printerr("Requires mode=cpu-hub and EMBER_STRESS_MOTIONS=<six-clip AnimationLibrary>");quit(2);return
 var library:=load(path) as AnimationLibrary
 if library==null:printerr("Cannot load stress animation library");quit(2);return
 for clip:String in MIX:
  if not library.has_animation(clip):printerr("Missing stress clip: ",clip);quit(2);return
 Hoshi._motion_library=library
 input_hashes[path]=FileAccess.get_sha256(path)
 progress.animation_mix_source={"path":path,"sha256":input_hashes[path],"clips":MIX}
 progress.performance_gate="OPEN: mixed animation correctness; background applications and clean performance measured separately"

func _process(_dt:float)->bool:
 if observing:
  var types:Dictionary={};var changed:=0
  for i in population_visuals.size():
   var visual=population_visuals[i];var clip:String=visual.current_motion
   types[clip]=true;seen[clip]=true
   if last_clips.has(i) and last_clips[i]!=clip:changes[i]=int(changes.get(i,0))+1;changed+=1
   last_clips[i]=clip
   phases[str(i)+":"+clip+":"+str(int(visual.motion.current_animation_position*20.0))]=true
  minimum_clip_types=mini(minimum_clip_types,types.size())
  simultaneous_changes=maxi(simultaneous_changes,changed)
 return false

func cpu_hub_comparison(scene:Node)->void:
 progress.pass_scope="Six real native animation clips and per-NPC transitions in dense gameplay; not 120FPS acceptance"
 progress.animation_mix={"staggered":{},"burst":{}}
 await frames(3)
 observing=true
 await create_timer(11.0).timeout
 observing=false
 progress.animation_mix.staggered={"clips_seen":seen.keys(),"minimum_simultaneous_clip_types":minimum_clip_types,"changed_actors":changes.size(),"max_changed_in_one_frame":simultaneous_changes,"unique_phase_samples":phases.size()}
 check(seen.size()==MIX.size() and minimum_clip_types==MIX.size(),"all six different animations active simultaneously")
 check(changes.size()==population_actors.size(),"each NPC changes animation independently")
 check(secondary_policy_status(scene)=={"heroes":8,"ordinary":32,"hero_active_solvers":8,"ordinary_active_solvers":0},"eight important heroes keep full secondary quality")
 # Separate the usual staggered changes from a deliberate all-at-once burst.
 simultaneous_changes=0;observing=true
 for i in population_actors.size():
  var actor=population_actors[i]
  actor.animation_slot=(actor.animation_cycle.find(population_visuals[i].current_motion)+1)%MIX.size()
  actor.animation_age=0.0;actor.animation_phase_offset=0.0
 await frames(45)
 observing=false
 progress.animation_mix.burst={"changed_in_one_frame":simultaneous_changes,"population":population_status(scene)}
 check(simultaneous_changes==population_actors.size(),"all NPCs can request different next animations in one frame")
 check(progress.animation_mix.burst.population.fallen==0 and progress.animation_mix.burst.population.pending_body_support==0,"mixed animation physical bodies retain ground support")
 var timing:=await cpu_sample(scene,false)
 progress.animation_mix.wall_observation=timing
 progress.animation_mix.timing_scope="Background-load observation only; not a clean comparison with older uniform-motion stress"
 record("animation_mix_checked")
