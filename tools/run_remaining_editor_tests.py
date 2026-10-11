"""Retained editor/Forward+ diagnostics with generated native fixtures only."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from run_mixed_editor_tests import ROOT, prepare_project

ENGINE = ROOT / 'tools/godot/Godot_v4.7.2-stable_win64.exe'
DIAGNOSTICS = ('qa_voxel_editor_edit_cost.gd', 'qa_voxel_editor_performance_ab.gd')


def execute(project, args, env, timeout=180):
    try:
        result = subprocess.run([str(ENGINE), '--path', str(project), *args], env=env,
                                capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=timeout)
    except subprocess.TimeoutExpired as error:
        for partial in (error.stdout, error.stderr):
            if partial: print(partial.decode('utf-8', 'replace') if isinstance(partial, bytes) else partial, flush=True)
        raise
    output = result.stdout + result.stderr
    print(output, end='', flush=True)
    if result.returncode or 'ERROR:' in output or 'FAIL' in output:
        raise RuntimeError('disposable editor diagnostic failed')
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--forward', choices=(*DIAGNOSTICS, 'test_diorama_materials.gd'),
                        help='Opt-in visible Forward+ diagnostic, distinct from headless acceptance')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='ember-canvas-smoke-native-') as temporary:
        project = Path(temporary).resolve()
        prepare_project(project)
        env = os.environ.copy()
        env['EMBER_INTERACTION_TEST_ROOT'] = project.as_posix()
        if args.forward:
            shutil.copyfile(ROOT / 'tools' / args.forward, project / 'tools' / args.forward)
            config = project / 'project.godot'
            config.write_text(config.read_text(encoding='utf-8').replace('gl_compatibility', 'forward_plus'), encoding='utf-8')
            command = ['--max-fps', '30', '--script', 'res://tools/' + args.forward]
            if args.forward == 'test_diorama_materials.gd': command += ['--', '--visual']
            execute(project, command, env, timeout=600)
            print('PASS native Forward+ diagnostic; timings describe this synthetic fixture only')
            return
        for plugin in ('ember_import', 'ember_surface_canvas'):
            shutil.copyfile(ROOT / 'addons' / plugin / 'plugin.cfg', project / 'addons' / plugin / 'plugin.cfg')
        setup = '''extends SceneTree
const Fixture = preload("res://tools/fixtures/ember_mixed_editor_test_fixture.gd")
func _init() -> void:
 if not Fixture.prepare(self):
  quit(2)
  return
 print("PASS native editor shape setup")
 quit(0)
'''
        (project / 'tools/prepare_shapes.gd').write_text(setup, encoding='utf-8')
        execute(project, ['--headless', '--script', 'res://tools/prepare_shapes.gd'], env)
        execute(project, ['--headless', '--editor', '--import'], env)
        plugin = project / 'addons/native_shape_gate'
        plugin.mkdir()
        shutil.copyfile(ROOT / 'tools/editor_test_voxel_shapes.gd', plugin / 'plugin.gd')
        (plugin / 'plugin.cfg').write_text('[plugin]\nname="Native shape gate"\ndescription="Disposable test"\nauthor="Ember"\nversion="1"\nscript="plugin.gd"\n', encoding='utf-8')
        config = project / 'project.godot'
        text = config.read_text(encoding='utf-8').replace('enabled=PackedStringArray("res://addons/ember_surface_canvas/plugin.cfg")',
                  'enabled=PackedStringArray("res://addons/ember_surface_canvas/plugin.cfg", "res://addons/ember_import/plugin.cfg", "res://addons/native_shape_gate/plugin.cfg")')
        config.write_text(text.replace('gl_compatibility', 'forward_plus'), encoding='utf-8')
        output = execute(project, ['--editor', '--max-fps', '30', '--resolution', '1600x900'], env, timeout=240)
        if 'SHAPES_EDITOR functional: PASS' not in output:
            raise RuntimeError('native shape editor did not complete its assertions')
        print('PASS native shape EditorPlugin; no historical maps or author voxel sources')


if __name__ == '__main__':
    main()
