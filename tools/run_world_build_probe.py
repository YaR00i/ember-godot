"""Run a packaged native game without the checkout; preserve per-stage diagnostics."""
import argparse
import json
from pathlib import Path
import subprocess
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--exe', type=Path, required=True)
    parser.add_argument('--user-dir', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--seconds', type=int, default=12)
    parser.add_argument('--timeout', type=int, default=600)
    parser.add_argument('--sphere', action='store_true')
    parser.add_argument('--require-empty', action='store_true')
    args = parser.parse_args()
    exe = args.exe.resolve(strict=True)
    args.out.mkdir(parents=True, exist_ok=True)
    before = {str(p.relative_to(args.user_dir)): p.stat().st_size
              for p in args.user_dir.glob('ember-*-cache/*') if p.is_file()}
    if args.require_empty and before:
        raise RuntimeError('Cold probe requires no local derived records; nothing was deleted.')
    previous = set((args.user_dir / 'startup-logs').glob('*.jsonl'))
    command = [str(exe), '--log-file', str((args.out / 'engine.log').resolve()), '--',
               '--ember-profile', f'--ember-profile-exit={args.seconds}']
    if args.sphere:
        command.append('--ember-profile-sphere')
    began = time.monotonic()
    launch_unix = time.time()
    process = subprocess.Popen(command, cwd=exe.parent)
    try:
        code = process.wait(timeout=args.timeout)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
        raise RuntimeError('This probe process timed out; inspect its partial JSONL log.')
    elapsed = time.monotonic() - began
    logs = set((args.user_dir / 'startup-logs').glob('*.jsonl')) - previous
    if len(logs) != 1:
        raise RuntimeError(f'Exit {code}: expected one new startup log, received {logs}; see {args.out / "engine.log"}')
    log = logs.pop()
    target = args.out / 'startup.jsonl'
    target.write_bytes(log.read_bytes())
    if log.with_suffix('.png').exists():
        (args.out / 'world.png').write_bytes(log.with_suffix('.png').read_bytes())
    events = [json.loads(line) for line in target.read_text(encoding='utf-8').splitlines()]
    end = next((event for event in reversed(events) if event['event'] == 'end'), {})
    begin_event = next((event for event in events if event['event'] == 'begin'), {})
    # On Windows st_ctime is file creation time. The first log opens in the
    # world's _ready; keep this interval separate from in-world preparation.
    pre_log_seconds = log.stat().st_ctime - launch_unix
    result = {'exit': code, 'launch_to_exit_seconds': elapsed, 'local_records_before': len(before),
              'launch_to_log_open_seconds': pre_log_seconds,
              'approx_launch_to_world_enter_seconds': pre_log_seconds - begin_event.get('at_ms', 0) / 1000,
              'stages': [event for event in events if event['event'] in ('stage', 'world_revealed')],
              'end': end}
    (args.out / 'result.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({k: result[k] for k in ('exit', 'launch_to_exit_seconds', 'local_records_before')}), flush=True)
    if code or end.get('reason') != 'complete' or not end.get('state', {}).get('play_ready'):
        raise RuntimeError('Packaged world did not reach play readiness.')
    state = end['state']
    for key in ('terrain_pending', 'physics_pending', 'lod_pending', 'look_pending', 'foliage_pending'):
        if state.get(key, 0):
            raise RuntimeError(f'World revealed with unfinished work: {key}={state[key]}')
    if args.sphere and not state.get('sphere', {}).get('ready'):
        raise RuntimeError('Sphere did not reach readiness.')
    engine_log = (args.out / 'engine.log').read_text(encoding='utf-8', errors='replace')
    if 'ERROR:' in engine_log:
        raise RuntimeError('Runtime errors remain; inspect engine.log before accepting this build.')


if __name__ == '__main__':
    main()
