#!/usr/bin/env python3
"""Throwaway acceptance comparison: actual timeboxctl REPL, simulated devices only."""
import argparse
import errno
import fcntl
import json
import os
from pathlib import Path
import pty
import re
import select
import signal
import struct
import subprocess
import tempfile
import termios
import time

parser = argparse.ArgumentParser(description=__doc__)
repository = next(parent for parent in Path(__file__).resolve().parents if (parent / '.git').exists())
parser.add_argument('--output', type=Path, default=repository / 'private/research/repl-editor-comparison-results.json')
parser.add_argument('--binary', action='append', help='EDITOR=/absolute/path/to/timeboxctl')
parser.add_argument('--interrupt-attempts', type=int, default=0, help='Repeat fresh-process Ctrl-C acceptance after the ordinary comparison')
args = parser.parse_args()
binaries = dict(item.split('=', 1) for item in (args.binary or [
    'commandlinekit=/private/tmp/timebox-repl-commandlinekit/.build/debug/timeboxctl',
    'bestline=/private/tmp/timebox-repl-bestline/.build/debug/timeboxctl',
]))
scratch = Path(tempfile.mkdtemp(prefix='timebox-repl-compare-', dir='/private/tmp'))
config = scratch / 'config.yml'
config.write_text('''default: desk
devices:
  desk:
    mac: 00:11:22:33:44:55
    model: evo
  mini:
    mac: 00:11:22:33:44:66
    model: mini
  bureau-évo:
    mac: 00:11:22:33:44:77
    model: evo
''')
initial_config = config.read_bytes()
ansi = re.compile(rb'\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07]*(?:\x07|\x1b\\)')

class Session:
    def __init__(self, binary, editor, history=None):
        self.master, self.slave = pty.openpty()
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 100, 0, 0))
        self.original_termios = termios.tcgetattr(self.slave)
        env = dict(os.environ, TERM='xterm-256color', NO_COLOR='1')
        env.pop('XPC_SERVICE_NAME', None)
        env.pop('TIMEBOX_ADDRESS', None)
        command = [binary, 'repl', '--mock', '--device', 'desk', '--config', str(config), '--editor', editor]
        if history:
            command += ['--history-file', str(history)]
        self.process = subprocess.Popen(command, stdin=self.slave, stdout=self.slave, stderr=self.slave, env=env, start_new_session=True)
        self.transcript = bytearray()
        self.query_tail = b''
        self.receive(until=b'timebox> ', timeout=8)
        # Drain initial cursor queries/redraws before injecting control bytes.
        self.receive(timeout=.15)
        if self.process.poll() is not None:
            raise RuntimeError(self.text())

    def receive(self, until=None, timeout=1):
        start = len(self.transcript)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if not select.select([self.master], [], [], max(0, deadline - time.monotonic()))[0]:
                break
            try:
                data = os.read(self.master, 65536)
            except OSError as error:
                if error.errno == errno.EIO:
                    break
                raise
            if not data:
                break
            self.transcript.extend(data)
            combined = self.query_tail + data
            for _ in range(combined.count(b'\x1b[6n')):
                os.write(self.master, b'\x1b[1;1R')
            # Retain only an incomplete cursor-query prefix across read chunks.
            self.query_tail = next((combined[-n:] for n in (3, 2, 1) if combined.endswith(b'\x1b[6n'[:n])), b'')
            if until and until in bytes(self.transcript[start:]):
                break
        return bytes(self.transcript[start:])

    def send(self, text):
        os.write(self.master, text.encode() if isinstance(text, str) else text)

    def text(self):
        return ansi.sub(b'', bytes(self.transcript)).decode('utf-8', errors='replace')

    def command(self, text):
        start = len(self.transcript)
        self.send(text + '\r')
        self.receive(until=b'timebox> ', timeout=3)
        self.receive(timeout=.12)
        return ansi.sub(b'', bytes(self.transcript[start:])).decode('utf-8', errors='replace')

    def close(self, artifact):
        try:
            if self.process.poll() is None:
                # Finish a previous command's redraw/cursor query before typing
                # cleanup input. Injecting bytes during DSR would test a race in
                # the harness rather than an editor's normal ready prompt.
                self.receive(timeout=.2)
                self.send(b'\x15quit\r')
                self.receive(until=b'Disconnected.', timeout=2)
            if self.process.poll() is None:
                try:
                    self.process.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    os.killpg(self.process.pid, signal.SIGTERM)
                    self.process.wait(timeout=2)
            self.receive(timeout=.05)
            after = termios.tcgetattr(self.slave)
            comparable = list(after)
            original_comparable = list(self.original_termios)
            # macOS may retain PENDIN after tcsetattr: kernel retype bookkeeping,
            # not failure to restore raw/canonical/echo/signal settings.
            comparable[3] &= ~getattr(termios, 'PENDIN', 0)
            original_comparable[3] &= ~getattr(termios, 'PENDIN', 0)
            term_restored = comparable == original_comparable
            changed = {str(i): [repr(before), repr(actual)] for i, (before, actual) in enumerate(zip(self.original_termios, after)) if before != actual}
            artifact.write_bytes(self.transcript)
            return {'exit_code': self.process.returncode, 'termios_restored': term_restored, 'termios_exact': after == self.original_termios, 'termios_changes': changed, 'transcript': str(artifact)}
        finally:
            os.close(self.master)
            os.close(self.slave)

results = {'scratch': str(scratch), 'scope': 'mock device transport; PTY byte/control-flow checks, not human visual or real Bluetooth validation', 'editors': {}}
for editor, binary in binaries.items():
    checks = {}
    results['editors'][editor] = checks
    if not Path(binary).is_file():
        checks['error'] = 'Binary not built: ' + binary
        continue
    base = [binary, 'repl', '--mock', '--device', 'desk', '--config', str(config), '--editor', editor]
    pipe = subprocess.run(base, input='brightness 20\ncolor 0000FF\ntarget mini\ntarget\nquit\n', text=True, capture_output=True, timeout=10)
    checks['pipe_fallback'] = {'exit_code': pipe.returncode, 'simulated_writes': pipe.stdout.count('simulated ('), 'ansi_free': '\x1b' not in pipe.stdout + pipe.stderr, 'target_mini': 'mini' in pipe.stdout}
    wrong_scope = subprocess.run([binary, 'brightness', '20', '--mock', '--editor', editor, '--config', str(config)], text=True, capture_output=True, timeout=5)
    checks['editor_option_rejected_outside_repl'] = wrong_scope.returncode != 0
    history = scratch / (editor + '-history')
    session = Session(binary, editor, history)
    try:
        checks['brightness'] = 'simulated (' in session.command('brightness 20')
        session.command('target mini')
        session.command('target dek\x1b[Ds')
        checks['cursor_edit'] = 'Target: desk |' in session.command('target')
        checks['command_completion'] = 'simulated (' in session.command('bright\t 30')
        session.command('target mi\t')
        checks['target_completion'] = 'Target: mini |' in session.command('target')
        checks['unknown_target_keeps_target'] = 'Target unchanged:' in session.command('target nonexistent')
        session.command('target desk')
        session.command('target bureau-évo')
        checks['unicode_alias'] = 'Target: bureau-évo |' in session.command('target')
        session.command('target desk')
        session.command('color FF0000')
        start = len(session.transcript)
        session.send(b'\x1b[A\r')
        session.receive(until=b'simulated (', timeout=2)
        checks['history_up'] = b'simulated (' in bytes(session.transcript[start:])
        session.receive(timeout=.15)
        start = len(session.transcript)
        session.send(b'\x12brightness')
        search_output = session.receive(timeout=.25)
        checks['ctrl_r_search_prompt'] = b'reverse-i-search' in search_output
        if checks['ctrl_r_search_prompt']:
            session.send(b'\r')
            checks['ctrl_r_recalls_executable_command'] = b'simulated (' in session.receive(until=b'simulated (', timeout=2)
        else:
            checks['ctrl_r_recalls_executable_command'] = False
            session.send(b'\x15')
        session.receive(timeout=.1)
        fcntl.ioctl(session.slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 60, 0, 0))
        os.killpg(session.process.pid, signal.SIGWINCH)
        checks['resize_then_command'] = 'simulated (' in session.command('brightness 40')
        session.send('quit\r')
        session.receive(until=b'Disconnected.', timeout=2)
    finally:
        checks['editing_session'] = session.close(scratch / (editor + '-editing.pty'))
    checks['history_file_created'] = history.exists()
    checks['history_contains_commands'] = history.exists() and 'brightness 20' in history.read_text()
    session = Session(binary, editor, history)
    try:
        # Last saved entry is quit, followed backward by brightness 40.
        session.send(b'\x1b[A\x1b[A\r')
        checks['history_reloaded_in_new_process'] = b'simulated (' in session.receive(until=b'simulated (', timeout=2)
    finally:
        checks['history_reload_session'] = session.close(scratch / (editor + '-history-reload.pty'))

    session = Session(binary, editor)
    try:
        session.send(b'\x04')
        session.receive(timeout=.4)
        checks['empty_ctrl_d_exits'] = session.process.poll() is not None
    finally:
        checks['ctrl_d_session'] = session.close(scratch / (editor + '-ctrl-d.pty'))

    session = Session(binary, editor)
    try:
        session.send(b'\x03')
        session.receive(timeout=.5)
        checks['ctrl_c_exits'] = session.process.poll() is not None
    finally:
        checks['ctrl_c_session'] = session.close(scratch / (editor + '-ctrl-c.pty'))
        checks['ctrl_c_clean_exit'] = checks['ctrl_c_exits'] and checks['ctrl_c_session']['exit_code'] == 0 and checks['ctrl_c_session']['termios_restored']

    session = Session(binary, editor)
    try:
        session.send(b'\x1b[200~brightness 20\rcolor FF0000\x1b[201~')
        before_enter = session.receive(timeout=.35)
        checks['bracketed_paste_no_early_execution'] = b'simulated (' not in before_enter
        checks['bracketed_paste_mode_announced'] = b'\x1b[?2004h' in session.transcript
        # Cancel the pasted input rather than execute a multiline device command.
        session.send(b'\x03')
        session.receive(timeout=.4)
    finally:
        checks['paste_session'] = session.close(scratch / (editor + '-paste.pty'))

    session = Session(binary, editor)
    try:
        session.send(b'\x1b[200~brightness 60\x1b[201~\r')
        checks['single_line_bracketed_paste_executes'] = b'simulated (' in session.receive(until=b'simulated (', timeout=2)
    finally:
        checks['single_line_paste_session'] = session.close(scratch / (editor + '-single-paste.pty'))
    checks['interrupt_stress'] = []
    for attempt in range(args.interrupt_attempts):
        session = Session(binary, editor)
        try:
            if attempt % 2:
                session.send('brightness ')
                session.receive(timeout=.08)
            session.send(b'\x03')
            session.receive(timeout=.4)
        finally:
            outcome = session.close(scratch / f'{editor}-interrupt-{attempt}.pty')
            checks['interrupt_stress'].append({'attempt': attempt + 1, 'exit_code': outcome['exit_code'], 'termios_restored': outcome['termios_restored']})

results['config_unchanged'] = config.read_bytes() == initial_config
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(results, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(results, ensure_ascii=False, indent=2))
