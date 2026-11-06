"""Build, open or benchmark the isolated Ember 1 km² location (Godot 4.7.2 + Terrain3D 1.1)."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from uuid import uuid4

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
DEFAULT_WORKSPACE = Path.home() / "Documents/Codex/ember-kilometre"


def tuft_study(project, dest):
    # Adapt just the two extension points in the pinned external QA program.
    # Other grass forms keep their original materials, meshes and commands.
    script = (project/"qa_grass_study.gd").read_text("utf8")
    kernel = (project/"qa_grass_study.glsl").read_text("utf8")
    def replace_once(source, old, new):
        if source.count(old) != 1:
            raise ValueError("Incompatible grass QA source: "+old)
        return source.replace(old,new)
    script = replace_once(script,'res://qa_grass_study.glsl','res://kilometre/tuft_study.glsl')
    script = replace_once(script,"var native_arrays:Array=[]","var native_arrays:Array=[]\n var tuft_meshes:Array=[]")
    script = replace_once(script,"(native_arrays if group==1 else cards)","(tuft_meshes[lod] if group==1 else cards)")
    kernel = replace_once(kernel,"if(view.study.w>0.5 && view.study.w<1.5)lod=0u;",
                         "if(view.study.w>0.5 && view.study.w<1.5)lod=view.shape.z<0.5 ? 0u : (px>=15.0 ? 0u : (px>=6.0 ? 1u : 2u));")
    kernel = replace_once(kernel,"max(view.study.z,1.0)","max(view.study.z,0.5)")
    (dest/"tuft_study.gd").write_text(script,"utf8")
    (dest/"tuft_study.glsl").write_text(kernel,"utf8")


def engine_path(value):
    candidate = value or os.environ.get("EMBER_GODOT") or shutil.which("godot") or "D:/downloads/programusiki/Godot_v4.7.2-stable_win64_console.exe"
    return str(Path(candidate).resolve(strict=True))


def setup(workspace, terrain_addon, engine, automatic_workers=False):
    if workspace.is_relative_to(REPO) or REPO.is_relative_to(workspace):
        raise ValueError("Choose a dedicated directory outside the Ember checkout.")
    marker = workspace / ".ember-kilometre"
    if workspace.exists() and any(workspace.iterdir()) and not marker.is_file():
        raise ValueError("Workspace is not an isolated kilometre project. Choose a new directory.")
    workspace.mkdir(parents=True, exist_ok=True)
    project = workspace / "project"
    addon = Path(terrain_addon or os.environ.get("EMBER_TERRAIN3D") or
                 Path.home() / "AppData/Local/Temp/ember-world-systems-qa/project/addons/terrain_3d")
    if not (addon / "terrain.gdextension").is_file() and not (project/"addons/terrain_3d/terrain.gdextension").is_file():
        raise ValueError("Specify the Terrain3D 1.1 addon directory with --terrain-addon.")
    fresh = not (project / "project.godot").is_file()
    marker.touch()
    if fresh:
        for name in ("scripts","addons/ember_import","addons/ember_surface_canvas","addons/zylann.voxel",
                     "assets","content","materials","prefabs","shaders","scenes","art"):
            if (REPO/name).is_dir():
                shutil.copytree(REPO/name,project/name,dirs_exist_ok=True,ignore=shutil.ignore_patterns("*.TMP","*.tmp"))
        shutil.copytree(addon,project/"addons/terrain_3d",dirs_exist_ok=True)
        for name in ("icon.svg","icon.svg.import"):
            shutil.copy2(REPO/name,project/name)
    config = (REPO/"project.godot").read_text("utf8")
    # On the 1 km fixture the automatic pool repeatedly stalled the main loop
    # during the flight. Keep the measured limit local to the field project.
    workers = -1 if automatic_workers else min(4,os.cpu_count() or 1)
    setting = f"worker_pool/max_threads={workers}"
    if re.search(r"(?m)^worker_pool/max_threads=",config):
        config = re.sub(r"(?m)^worker_pool/max_threads=.*$",setting,config)
    elif "[threading]" in config:
        config = config.replace("[threading]","[threading]\n"+setting,1)
    else:
        config += "\n[threading]\n"+setting+"\n"
    config = re.sub(r"(?m)^MCPRuntime=.*\n", "", config)
    config = re.sub(r"(?m)^enabled=PackedStringArray\(.*$", "enabled=PackedStringArray()", config)
    config = config.replace('config/name="Ember Godot"', 'config/name="Ember Kilometre QA"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="EmberKilometreQA"')
    config = config.replace("res://scenes/landscape_compact.tscn","res://kilometre/location.tscn")
    (project/"project.godot").write_text(config,"utf8")
    dest = project/"kilometre"
    dest.mkdir(exist_ok=True)
    for name in ("location.gd","cover.gd","cover.gdshader","ground.gdshaderinc","scenery.gd",
                 "meadow.gd","meadow_roots.glsl","meadow_material.gdshader","bank.gdshaderinc","field_probe.gd","travel_probe.gd","mountain_probe.gd","population.gd"):
        shutil.copy2(HERE/name,dest/name)
    # Use the accepted QA renderer and its licensed card, including its three
    # real indirect draw groups. The isolated project retains its local copy.
    qa = Path(os.environ.get("EMBER_GRASS_QA",str(Path.home()/"AppData/Local/Temp/ember-world-systems-qa/project")))
    for name in ("qa_grass_study.gd","qa_grass_study.glsl","qa_stream_grass.gd","qa_manual_grass.gd",
                 "qa_vegetation_grass.gd","qa_gpu_grass_ground.gd","qa_gpu_grass_shared.gd","qa_gpu_grass.gd",
                 "qa_grass_toon_LICENSE.txt","qa_dylearn/grassleaf.png","qa_dylearn/ATTRIBUTION.txt","qa_dylearn/LICENSE.txt"):
        target = project/name
        if target.is_file():
            continue
        if (qa/name).is_file():
            target.parent.mkdir(exist_ok=True)
            shutil.copy2(qa/name,target)
        elif not target.is_file():
            raise ValueError("Set EMBER_GRASS_QA to the Ember QA project containing "+name)
    tuft_study(project,dest)
    shader = "shaders/ember_compact_sky_reflection_study.gdshader"
    shutil.copy2(REPO/shader,project/shader)
    # Reuse the authored evening light and sky, with camera distances expressed in metres.
    main = (REPO/"scenes/landscape_compact.tscn").read_text("utf8")
    env = main[main.index('[sub_resource type="ProceduralSkyMaterial"'):main.index('[node name="LandscapeCompact"')]
    env = re.sub(r"ssao_radius = ([0-9.]+)",lambda m: f"ssao_radius = {float(m[1])/16}",env)
    sun = main[main.index('[node name="Sun"'):main.index('[node name="Terrain"')]
    sun = sun.replace('parent="Map/Look"','parent="."').replace('directional_shadow_max_distance = 1600.0','directional_shadow_max_distance = 100.0')
    scene = '[gd_scene format=3]\n[ext_resource type="Script" path="res://kilometre/location.gd" id="1"]\n'
    scene += env+'[node name="Kilometre" type="Node3D"]\nscript = ExtResource("1")\n'
    settings = main.split('[node name="PlanarReflection"',1)[1].split('[node ',1)[0]
    names = ("shallow_color","deep_color","water_color_start_m","local_bob_strength","ripple_cell_scale",
             "ripple_morph_strength","water_level_offset_voxels","shore_foam_strength",
             "shore_foam_width_voxels","shore_foam_sharpness","sea_crest_foam_strength","sea_crest_foam_amount")
    water = [(key,val) for key,val in re.findall(r"(?m)^(\w+) = (.+)$",settings) if key in names]
    scene += 'water_settings = {'+", ".join(f'"{k}": {v}' for k,v in water)+'}\n'
    scene += '[node name="Sky" type="WorldEnvironment" parent="."]\nenvironment = SubResource("environment")\n'+sun
    (dest/"location.tscn").write_text(scene,"utf8")
    if fresh or not (project/".godot/global_script_class_cache.cfg").is_file():
        subprocess.run([engine,"--headless","--path",str(project),"--import"],check=True)
    local_recipe = workspace/"recipe.json"
    if not local_recipe.is_file():
        shutil.copy2(HERE/"default.json",local_recipe)
    if os.name == "nt":
        (workspace/"Author.cmd").write_text(
            f'@echo off\n"{sys.executable}" "{HERE / "author.py"}" "%~dp0."\nif errorlevel 1 pause\n',encoding="mbcs")
        for action in ("Play","Generate","Stress"):
            extra = ' --recipe "%~dp0recipe.json"' if action == "Generate" else ""
            line = f'"{sys.executable}" "{HERE / "run.py"}" {action.lower()} --workspace "%~dp0."{extra} %*'
            (workspace/(action+".cmd")).write_text("@echo off\n"+line+"\nif errorlevel 1 pause\n",encoding="mbcs")
    return project


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action",choices=["generate","play","stress","profile","trace","mountain","editor"])
    parser.add_argument("--population",action="store_true",help="For profile, compare the same meadow without/with/without the moving cohort.")
    parser.add_argument("--dynamic-floor",action="store_true",help="For trace, measure the previous moving Terrain3D collision window.")
    parser.add_argument("--auto-workers",action="store_true",help="For trace, compare Godot's automatic worker count to the field default.")
    parser.add_argument("--workspace",type=Path,default=DEFAULT_WORKSPACE)
    parser.add_argument("--godot")
    parser.add_argument("--terrain-addon")
    parser.add_argument("--seed",type=int)
    parser.add_argument("--recipe",type=Path)
    parser.add_argument("--heightmap",type=Path)
    parser.add_argument("--min-height",type=float,default=0)
    parser.add_argument("--max-height",type=float,default=180)
    args = parser.parse_args()
    if args.population and args.action!="profile":
        parser.error("--population requires profile")
    if (args.dynamic_floor or args.auto_workers) and args.action!="trace":
        parser.error("--dynamic-floor and --auto-workers require trace")
    workspace = args.workspace.resolve()
    engine = engine_path(args.godot)
    project = setup(workspace,args.terrain_addon,engine,args.auto_workers)
    env = dict(os.environ,APPDATA=str(workspace/"profile"))
    command = [engine,"--path",str(project)]
    active = project/"active-world.txt"
    if args.action=="generate":
        name = time.strftime("land_%Y%m%d_%H%M%S_")+uuid4().hex[:6]
        output = project/"generated"/name
        recipe = args.recipe or workspace/"recipe.json"
        cmd = [sys.executable,str(HERE/"recipe.py"),"--output",str(output),"--recipe",str(recipe)]
        if args.seed is not None:cmd.extend(["--seed",str(args.seed)])
        if args.heightmap:cmd.extend(["--heightmap",str(args.heightmap),"--min-height",str(args.min_height),"--max-height",str(args.max_height)])
        subprocess.run(cmd,check=True)
        shutil.copy2(recipe,output/"recipe.json")
        dataset = "res://generated/"+name
        subprocess.run(command+["--resolution","640x360","--","--bake",dataset],env=env,check=True,timeout=240)
        if len(list((output/"regions").glob("*.res"))) != 16 or not all((output/f).is_file() for f in ("tree.res","birch.res","water.res")):
            raise RuntimeError("Incomplete baked location")
        pointer = project/(name+".tmp")
        pointer.write_text(dataset,"utf8")
        pointer.replace(active)
        print("Playable dataset:",output)
        return
    if not active.is_file():parser.error("Generate a location first.")
    if args.action=="editor":
        subprocess.run(command+["--editor"],env=env,check=True)
        return
    command+=["--fullscreen","--resolution","2560x1440","--disable-vsync"]
    if args.action in ("stress","profile","trace","mountain"):
        prefix = "route" if args.action=="stress" else args.action if args.action in ("trace","mountain") else "actors" if args.population else "field"
        evidence = workspace/"evidence"/time.strftime(prefix+"_%Y%m%d_%H%M%S")
        env["EMBER_KM_EVIDENCE"]=str(evidence)
        if args.action=="stress":
            command+=["--","--stress"]
        elif args.action=="trace":
            command+=["--script","res://kilometre/travel_probe.gd","--","--field-profile"]
            if args.dynamic_floor:command.append("--moving-floor-reference")
        elif args.action=="mountain":
            command+=["--script","res://kilometre/mountain_probe.gd","--","--field-profile"]
        else:
            command+=["--script","res://kilometre/field_probe.gd","--","--field-profile"]
            if args.population:command.append("--population")
        print("Evidence:",evidence,flush=True)
    subprocess.run(command,env=env,check=True)


if __name__ == "__main__":
    main()
