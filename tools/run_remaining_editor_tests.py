"""Retained editor/Forward+ diagnostics with generated native fixtures only."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from run_mixed_editor_tests import ROOT, prepare_project
from run_interaction_tests import prepare_project as prepare_code

ENGINE = ROOT / 'tools/godot/Godot_v4.7.2-stable_win64.exe'
DIAGNOSTICS = ('qa_voxel_editor_edit_cost.gd', 'qa_voxel_editor_performance_ab.gd')
MECHANICS = ('test_voxel_object_canvas.gd', 'test_voxel_placement_preview.gd',
             'test_voxel_cartoon_water.gd', 'test_exploration_mechanics.gd',
             'test_native_voxel_resource.gd', 'test_voxel_preview_renderer.gd')
EDITOR_MECHANICS = ('editor_test_world_editor.gd', 'editor_test_voxel_context.gd',
                    'editor_test_voxel_conversion.gd', 'editor_test_voxel_object_canvas.gd')


def run_mechanics(test, editor=False, native=False):
    # The prefixes retain the existing editor-script safety gates.
    with tempfile.TemporaryDirectory(prefix='ember-world-native-ember-canvas-smoke-') as temporary:
        project = Path(temporary).resolve()
        prepare_code(project)
        for name in (test, 'test_native_voxel_catalog.gd'):
            shutil.copyfile(ROOT / 'tools' / name, project / 'tools' / name)
        (project / '.editor-mechanics-test-sandbox').write_text('generated inputs only\n', encoding='utf-8')
        (project / '.voxel-native-test-sandbox').write_text('generated inputs only\n', encoding='utf-8')
        (project / '.voxel-native-count').write_text('3', encoding='utf-8')
        env = os.environ.copy()
        env['EMBER_VOXEL_TEST_ROOT'] = project.as_posix()
        execute(project, ['--headless', '--script', 'res://tools/test_native_voxel_catalog.gd', '--', '--prepare-only'], env)
        config = project / 'project.godot'
        text = config.read_text(encoding='utf-8')
        if editor or native:
            text = text.replace('gl_compatibility', 'forward_plus')
        if editor:
            for addon in ('ember_import', 'ember_surface_canvas'):
                shutil.copyfile(ROOT / 'addons' / addon / 'plugin.cfg', project / 'addons' / addon / 'plugin.cfg')
            gate = project / 'addons/mechanics_gate'
            gate.mkdir()
            shutil.copyfile(ROOT / 'tools' / test, gate / 'plugin.gd')
            (gate / 'plugin.cfg').write_text('[plugin]\nname="Mechanics fixture gate"\ndescription="Disposable"\nauthor="Ember"\nversion="1"\nscript="plugin.gd"\n', encoding='utf-8')
            text += '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/ember_surface_canvas/plugin.cfg","res://addons/ember_import/plugin.cfg","res://addons/mechanics_gate/plugin.cfg")\n'
        config.write_text(text, encoding='utf-8')
        args = ['--editor'] if editor else ([] if native else ['--headless']) + ['--script', 'res://tools/' + test]
        args += ['--log-file', str(project / 'mechanics-live.log')]
        if test == 'test_voxel_preview_renderer.gd':
            # This gate deliberately loads broken files and asserts retry/failure.
            result = subprocess.run([str(ENGINE), '--path', str(project), *args], env=env,
                                    capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=180)
            print(result.stdout + result.stderr, end='', flush=True)
            if result.returncode or 'PASS voxel preview renderer' not in result.stdout or 'SCRIPT ERROR' in result.stderr:
                raise RuntimeError('preview fixture gate failed')
        else:
            output = execute(project, args, env)
            if 'PASS' not in output: raise RuntimeError('mechanics gate did not finish')


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
    parser.add_argument('--mechanics-test', choices=MECHANICS)
    parser.add_argument('--mechanics-native', choices=MECHANICS)
    parser.add_argument('--mechanics-editor', choices=EDITOR_MECHANICS)
    args = parser.parse_args()
    if args.mechanics_test or args.mechanics_native or args.mechanics_editor:
        run_mechanics(args.mechanics_test or args.mechanics_native or args.mechanics_editor,
                      editor=bool(args.mechanics_editor), native=bool(args.mechanics_native))
        return
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
