#!/usr/bin/env python3
"""Run either isolated prototype against simulated devices; never opens Bluetooth."""
import argparse
import os
from pathlib import Path
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('editor', choices=('bestline', 'commandlinekit'))
parser.add_argument('--worktree', type=Path, help='Override the prototype worktree location')
parser.add_argument('--history-file', type=Path, help='Opt in to saving commands to this file')
args = parser.parse_args()
worktree = (args.worktree or Path('/private/tmp/timebox-repl-' + args.editor)).expanduser().resolve()
binary = worktree / '.build/debug/timeboxctl'
if not binary.is_file():
    parser.error(f'Build first: swift build --package-path {worktree} --product timeboxctl')
scratch = Path(tempfile.mkdtemp(prefix='timebox-repl-try-', dir='/private/tmp'))
config = scratch / 'config.yml'
config.write_text('''default: desk
devices:
  desk:
    mac: 00:11:22:33:44:55
    model: evo
  mini:
    mac: 00:11:22:33:44:66
    model: mini
''')
command = [str(binary), 'repl', '--mock', '--device', 'desk', '--config', str(config), '--editor', args.editor]
if args.history_file:
    command += ['--history-file', str(args.history_file.expanduser().resolve())]
print(f'PROTOTYPE: {args.editor}; simulated desk/Evo and mini/Mini. Config: {config}', flush=True)
print('Try brightness 20, target mini, target, Tab, Up, Ctrl-R, then quit. All device writes are simulated.', flush=True)
os.environ.pop('TIMEBOX_ADDRESS', None)
os.execv(str(binary), command)
