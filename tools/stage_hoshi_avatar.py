"""Stage the user's local Hoshi avatar; model/textures never enter source Git."""
import argparse
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--companion', type=Path, required=True)
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--motions', type=Path, help='Quaternius Universal Animation Library Standard GLB')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    source = args.companion.resolve()
    if not (source / 'assets/Hoshi_v1.vrm').is_file():
        parser.error('The companion source must contain assets/Hoshi_v1.vrm')
    output = root / 'assets/local_characters/hoshi'
    output.mkdir(parents=True, exist_ok=True)
    code = (root / 'tools/fixtures/hoshi_avatar_bake.gd.txt').read_text(encoding='utf-8')
    code = code.replace('__HOSHI_OUTPUT__', output.as_posix()).replace('__HOSHI_REPORT__', (output / 'source-checks.json').as_posix())
    startup = None
    if hasattr(subprocess, 'STARTUPINFO'):
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 0
    with tempfile.TemporaryDirectory(prefix='ember-hoshi-stage-') as temp:
        script = Path(temp) / 'bake.gd'
        script.write_text(code, encoding='utf-8')
        with (output / 'build.log').open('w', encoding='utf-8') as log:
            result = subprocess.run([str(args.godot.resolve()), '--path', str(source), '--script', str(script), '--rendering-method', 'gl_compatibility'], stdout=log, stderr=subprocess.STDOUT, startupinfo=startup, timeout=120)
        text = (output / 'build.log').read_text(encoding='utf-8')
        if result.returncode or 'HOSHI_ORIGINAL_BAKE_PASS' not in text or 'ERROR:' in text:
            raise RuntimeError('Hoshi staging failed; inspect ' + str(output / 'build.log'))
    if args.motions:
        with (output / 'motion-build.log').open('w', encoding='utf-8') as log:
            result = subprocess.run([str(args.godot.resolve()), '--headless', '--path', str(root), '--script', 'res://tools/retarget_hoshi_locomotion.gd', '--', 'source=' + args.motions.resolve().as_posix()], stdout=log, stderr=subprocess.STDOUT, startupinfo=startup, timeout=120)
        if result.returncode or 'QUATERNIUS_RETARGET_PASS' not in (output / 'motion-build.log').read_text(encoding='utf-8'):
            raise RuntimeError('Motion retarget failed; inspect ' + str(output / 'motion-build.log'))
    if not (output / 'motion.res').is_file():
        raise RuntimeError('Provide --motions with the Quaternius Standard GLB; the rejected procedural gait is not used.')
    print('Hoshi staged locally:', output / 'avatar.scn')


if __name__ == '__main__':
    main()
