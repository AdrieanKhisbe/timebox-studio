#!/usr/bin/env python3
"""Exercise real REPL terminal handling with mock device writes only."""
import errno
import fcntl
import os
from pathlib import Path
import pty
import re
import select
import struct
import subprocess
import sys
import termios
import time

binary = str(Path(sys.argv[1] if len(sys.argv) > 1 else '.build/debug/timeboxctl').resolve())
environment = dict(os.environ, TERM='xterm-256color')
environment.pop('NO_COLOR', None)
environment.pop('TIMEBOX_ADDRESS', None)
ansi = re.compile(rb'\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07]*(?:\x07|\x1b\\)')
pipe = subprocess.run([binary, 'repl', '--mock'], input='brightness 20\nquit\n', text=True,
                      capture_output=True, env=environment, timeout=10)
assert pipe.returncode == 0, pipe.stderr
assert 'simulated (' in pipe.stdout and '\x1b' not in pipe.stdout and 'timebox>' not in pipe.stdout
invalid = subprocess.run([binary, 'repl', '--mock', '--editor', 'invalid'], text=True,
                         capture_output=True, env=environment, timeout=10)
assert invalid.returncode != 0 and 'connection open' not in invalid.stdout.lower()

for ending in (b'quit\r', b'\x03', b'\x04'):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 100, 0, 0))
    before = termios.tcgetattr(slave)
    process = subprocess.Popen([binary, 'repl', '--mock'], stdin=slave, stdout=slave, stderr=slave, env=environment)
    transcript = bytearray()
    tail = b''

    def receive(needle, timeout=5):
        global tail
        start = len(transcript)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if not select.select([master], [], [], max(0, deadline - time.monotonic()))[0]:
                break
            try:
                data = os.read(master, 65536)
            except OSError as error:
                if error.errno == errno.EIO:
                    break
                raise
            if not data:
                break
            transcript.extend(data)
            combined = tail + data
            for _ in range(combined.count(b'\x1b[6n')):
                os.write(master, b'\x1b[1;1R')
            tail = next((combined[-n:] for n in (3, 2, 1) if combined.endswith(b'\x1b[6n'[:n])), b'')
            if needle in ansi.sub(b'', bytes(transcript[start:])):
                return True
        return False

    try:
        assert receive(b'timebox> '), bytes(transcript)
        assert b'\x1b[1;34mtimebox\x1b[1;31m>\x1b[0m ' in transcript
        # Finish the editor's initial redraw/cursor query before entering input.
        receive(b'never-present', timeout=.15)
        if ending == b'quit\r':
            os.write(master, b'bright\t 20\r')
            assert receive(b'simulated ('), bytes(transcript)
            receive(b'never-present', timeout=.15)
        os.write(master, ending)
        assert receive(b'Disconnected.'), bytes(transcript)
        assert process.wait(timeout=3) == 0
        after = termios.tcgetattr(slave)
        before[3] &= ~getattr(termios, 'PENDIN', 0)
        after[3] &= ~getattr(termios, 'PENDIN', 0)
        assert after == before, 'Terminal settings were not restored'
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=3)
        os.close(master)
        os.close(slave)
print('REPL pipe, invalid options, prompt colors, completion, Ctrl-C/EOF and terminal restoration passed.')
