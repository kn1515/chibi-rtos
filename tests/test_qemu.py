"""Boot QEMU in a real PTY and verify that the Ctrl+C key exits it."""
import errno
import os
from pathlib import Path
import pty
import selectors
import signal
import time

ROOT = Path(__file__).resolve().parents[1]
pid, terminal = pty.fork()
if pid == 0:
    os.chdir(ROOT)
    os.execlp('bash', 'bash', 'scripts/qemu.sh')

output = bytearray()
reaped = False
try:
    with selectors.DefaultSelector() as selector:
        selector.register(terminal, selectors.EVENT_READ)
        deadline = time.monotonic() + 20
        while b'Hello chibi-os\n' not in output.replace(b'\r', b''):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeError('No kernel greeting within 20 seconds')
            for _, _ in selector.select(min(remaining, 1)):
                try:
                    chunk = os.read(terminal, 4096)
                except OSError as exc:
                    if exc.errno == errno.EIO:
                        raise RuntimeError('QEMU exited before the greeting') from exc
                    raise
                if not chunk:
                    raise RuntimeError('Console closed before the greeting')
                output.extend(chunk)

        # Send the actual key byte through a controlling terminal, not kill(SIGINT).
        # This fails if QEMU disables the terminal's signal handling again.
        os.write(terminal, b'\x03')
        deadline = time.monotonic() + 5
        while True:
            child, status = os.waitpid(pid, os.WNOHANG)
            if child:
                reaped = True
                if not os.WIFEXITED(status) or os.WEXITSTATUS(status) != 0:
                    raise RuntimeError(f'Unexpected QEMU exit status: {status}')
                break
            if time.monotonic() >= deadline:
                raise RuntimeError('Ctrl+C did not exit QEMU within 5 seconds')
            for _, _ in selector.select(0.05):
                try:
                    output.extend(os.read(terminal, 4096))
                except OSError as exc:
                    if exc.errno != errno.EIO:
                        raise
    print(output.decode(errors='replace'))
    print('PASS: QEMU Hello chibi-os and terminal Ctrl+C exit')
except Exception:
    print(output.decode(errors='replace'))
    raise
finally:
    if not reaped:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        os.waitpid(pid, 0)
    os.close(terminal)
