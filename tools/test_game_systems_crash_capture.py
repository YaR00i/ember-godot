"""Diagnostic retention only; a synthetic exit is not a Godot crash repro."""
import contextlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import run_game_systems_tests as gate


class NativeCrashCaptureTests(unittest.TestCase):
    def test_fatal_exit_retains_recoverable_sandbox_and_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            project = root / 'ember-game-systems-fixture'
            project.mkdir()
            source = project / 'fixture.tres'
            source.write_bytes(b'author fixture bytes')
            (project / '.godot').mkdir()
            (project / '.godot' / 'cache').write_bytes(b'failed process state')
            profile = project / '.qa-appdata'
            profile.mkdir()
            (profile / 'settings.tres').write_bytes(b'isolated settings')
            evidence = root / 'evidence'
            evidence.mkdir()
            env = {'EMBER_GAME_SYSTEMS_TEST_ROOT': project.as_posix(),
                   'APPDATA': str(profile), 'EMBER_GAME_SYSTEMS_EDITOR_FOCUS': 'periodic',
                   'EMBER_UI_EVIDENCE': 'old/captures', 'UNRELATED_SECRET': 'not for capture'}
            result = subprocess.CompletedProcess([], 0xc0000005, 'last output\n', 'native failure\n')
            with patch.object(gate.subprocess, 'run', return_value=result), \
                    patch.object(gate.tempfile, 'mkdtemp', return_value=str(evidence)), \
                    contextlib.redirect_stdout(io.StringIO()) as output:
                with self.assertRaisesRegex(RuntimeError, 'exit code 3221225477'):
                    gate.execute(project, ['--editor'], env)
            self.assertIn('NATIVE CRASH EVIDENCE: ' + str(evidence), output.getvalue())
            launch = json.loads((evidence / 'replay.json').read_text(encoding='utf-8'))
            recovered = Path(launch['command'][2])
            self.assertTrue(recovered.is_relative_to(evidence))
            self.assertTrue(recovered.name.startswith('ember-game-systems-'))
            source.unlink()  # The original sandbox can now disappear.
            self.assertEqual((recovered / 'fixture.tres').read_bytes(), b'author fixture bytes')
            self.assertEqual((recovered / '.godot' / 'cache').read_bytes(), b'failed process state')
            self.assertEqual((evidence / 'process.log').read_text(), 'last output\nnative failure\n')
            self.assertEqual(launch['exit_code'], '0xc0000005')
            overrides = launch['environment_overrides']
            self.assertEqual(Path(overrides['APPDATA']), recovered / '.qa-appdata')
            self.assertEqual(overrides['EMBER_GAME_SYSTEMS_TEST_ROOT'], recovered.as_posix())
            self.assertNotIn('UNRELATED_SECRET', overrides)

    def test_normal_failure_and_author_project_do_not_create_captures(self):
        with tempfile.TemporaryDirectory(prefix='ember-game-systems-fixture-') as directory:
            project = Path(directory).resolve()
            env = {'EMBER_GAME_SYSTEMS_TEST_ROOT': project.as_posix()}
            result = subprocess.CompletedProcess([], 1, '', '')
            with patch.object(gate.tempfile, 'mkdtemp') as create:
                self.assertIsNone(gate.preserve_native_crash(project, [], env, result))
                result.returncode = -1073741819  # Signed access-violation exit.
                self.assertIsNone(gate.preserve_native_crash(project, [], {}, result))
                (project / '.git').write_text('author checkout guard')
                self.assertIsNone(gate.preserve_native_crash(project, [], env, result))
                create.assert_not_called()


if __name__ == '__main__':
    unittest.main()
