"""Focused authored-map/interaction gate; all mutations stay in a disposable project.

Default: reuse existing code-copy helper, add the chapter assets, import only the
disposable project, then run Forward+. --fixture reuses an already prepared copy.
--resume-interiors preserves the successful exterior-route evidence from a prior
run while retrying only changed interior bindings, relocation, bridge and save.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def prepare(source, destination):
    sys.path.insert(0, str(source / 'tools'))
    from run_interaction_tests import prepare_project
    prepare_project(destination)
    shutil.copyfile(source / 'scenes/combat_lab.tscn', destination / 'scenes/combat_lab.tscn')
    for folder in ('content/terrain_materials', 'content/shops', 'content/dialogues', 'content/action_scripts', 'content/recipes'):
        shutil.copytree(source / folder, destination / folder, dirs_exist_ok=True)
    for quest in (source / 'content/quests').glob('chapter1_*.tres'):
        shutil.copyfile(quest, destination / 'content/quests' / quest.name)
    for asset in (source / 'scenes').glob('chapter1_*.tscn'):
        shutil.copyfile(asset, destination / 'scenes' / asset.name)
    for asset in (source / 'scenes').glob('traversal_*_park.tscn'):
        shutil.copyfile(asset, destination / 'scenes' / asset.name)
    shutil.copytree(source / 'content/world_terrains/chapter1', destination / 'content/world_terrains/chapter1')
    for relative in ('prefabs/voxels/vox_painted_maple_autumn_palette.tscn',
                     'content/voxel_models/vox_painted_maple_autumn_palette.tres',
                     'prefabs/voxels/meshes/grass_card_contour.res',
                     'prefabs/items/crafting_workbench.tscn', 'prefabs/items/cooking_station.tscn',
                     'prefabs/items/shared_world_water.tscn',
                     'prefabs/items/chapter1_delivery_crate.tscn', 'prefabs/items/quest_crate.tscn',
                     'prefabs/items/chapter1_zipline.tscn',
                     'prefabs/items/chapter1_ice_slope.tscn',
                     'prefabs/items/chapter1_pipe_slide.tscn',
                     'prefabs/items/chapter1_team_gate.tscn',
                     'prefabs/items/chapter1_tide_cache.tscn',
                     'prefabs/items/chapter1_fishing_stop.tscn',
                     'prefabs/items/chapter1_tide_battle.tscn', 'prefabs/items/shore_boar_visual.tscn',
                     'prefabs/items/autumn_leaf_pile.scn', 'prefabs/items/autumn_leaf_scatter.scn',
                     'content/material_studies/foliage/autumn_leaf_atlas_v2.res',
                     'prefabs/voxels/meshes/quest_carry_crate_block.res',
                     'content/voxel_models/quest_carry_crate.tres'):
        original = source / relative
        if not original.exists():
            if relative.endswith('.tres'):
                continue
            raise FileNotFoundError(original)
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(original, target)
    (destination / 'project.godot').write_text('''config_version=5
[application]
config/name="EmberChapter1Gate"
config/use_custom_user_dir=true
config/custom_user_dir="ember-tests/chapter1-gate"
[autoload]
EmberExploreProgress="*res://scripts/ember_explore_state.gd"
[physics]
3d/physics_engine="Jolt Physics"
[rendering]
renderer/rendering_method="gl_compatibility"
''', encoding='utf-8')


def run(source, project, script_source, godot, resume, existing, day1=False, day1_clip=False, team_gate=False, tide_cache=False, fishing=False, pressure_battle=False, zipline=False, ice_slope=False, pipe_slide=False, traversal_parks=False):
    target = project / 'tools/test_chapter1_blockout.gd'
    if target.resolve() != script_source.resolve():
        shutil.copyfile(script_source, target)
    command = [str(godot), '--path', str(project), '--rendering-method', 'forward_plus',
               '--windowed', '--resolution', '1280x800', '--max-fps', '60',
               '--script', 'res://tools/test_chapter1_blockout.gd']
    if resume:
        command += ['--', '--resume-interiors']
    elif day1_clip:
        command += ['--', '--day1-clip']
    elif day1:
        command += ['--', '--day1']
    elif team_gate:
        command += ['--', '--team-gate']
    elif tide_cache:
        command += ['--', '--tide-cache']
    elif fishing:
        command += ['--', '--fishing']
    elif pressure_battle:
        command += ['--', '--pressure-battle']
    elif zipline:
        command += ['--', '--zipline']
    elif ice_slope:
        command += ['--', '--ice-slope']
    elif pipe_slide:
        command += ['--', '--pipe-slide']
    elif traversal_parks:
        command += ['--', '--traversal-parks']
    if not existing:
        imported = subprocess.run([str(godot), '--headless', '--editor', '--path', str(project), '--quit'],
                                  capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=180)
        if imported.returncode or 'SCRIPT ERROR:' in imported.stdout + imported.stderr:
            print(imported.stdout + imported.stderr)
            raise SystemExit('disposable import failed')
    result = subprocess.run(command, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=600)
    output = result.stdout + result.stderr
    print(output, end='')
    if result.returncode or 'ERROR:' in output or 'CHECK FAIL' in output or 'CHAPTER1 BLOCKOUT PASS' not in result.stdout:
        raise SystemExit(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--fixture', type=Path)
    parser.add_argument('--godot', type=Path)
    parser.add_argument('--resume-interiors', action='store_true')
    parser.add_argument('--day1', action='store_true', help='Check only the authored first-day quest route')
    parser.add_argument('--day1-clip', action='store_true', help='Check Day 1 with a staged local Hoshi clip at handover')
    parser.add_argument('--team-gate', action='store_true', help='Check the companion lever and cave gate')
    parser.add_argument('--tide-cache', action='store_true', help='Check both paths to the cave cache')
    parser.add_argument('--fishing', action='store_true', help='Check the coastal catch and cooking route')
    parser.add_argument('--pressure-battle', action='store_true', help='Check the cave encounter with a crate and pressure gate')
    parser.add_argument('--zipline', action='store_true', help='Check the woodland cable shortcut')
    parser.add_argument('--ice-slope', action='store_true', help='Check ice and ordinary movement on the woodland map')
    parser.add_argument('--pipe-slide', action='store_true', help='Check steering and obstacles in the woodland pipe')
    parser.add_argument('--traversal-parks', action='store_true', help='Check the ice, vine and cable parks')
    args = parser.parse_args()
    source = args.source.resolve()
    godot = args.godot or source / 'tools/godot/Godot_v4.7.2-stable_win64_console.exe'
    script = Path(__file__).with_name('test_chapter1_blockout.gd')
    if args.fixture:
        if args.day1_clip:
            parser.error('--day1-clip writes quest fixtures and requires a fresh disposable project')
        run(source, args.fixture.resolve(), script, godot, args.resume_interiors, True, args.day1, team_gate=args.team_gate, tide_cache=args.tide_cache, fishing=args.fishing, pressure_battle=args.pressure_battle, zipline=args.zipline, ice_slope=args.ice_slope, pipe_slide=args.pipe_slide, traversal_parks=args.traversal_parks)
    else:
        with tempfile.TemporaryDirectory(prefix='ember-chapter1-gate-') as temporary:
            project = Path(temporary)
            prepare(source, project)
            if args.day1_clip:
                local = Path('assets/local_characters/hoshi')
                (project / local).mkdir(parents=True, exist_ok=True)
                for name in ('avatar.scn', 'motion.res'):
                    shutil.copyfile(source / local / name, project / local / name)
            run(source, project, script, godot, args.resume_interiors, False, args.day1, args.day1_clip, args.team_gate, args.tide_cache, args.fishing, args.pressure_battle, args.zipline, args.ice_slope, args.pipe_slide, args.traversal_parks)


if __name__ == '__main__':
    main()
