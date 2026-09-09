"""Boot the same command as make qemu; require a greeting and clean monitor exit."""
import os
from pathlib import Path
import selectors
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
expected = b'Hello chibi-os\r\n'
process = subprocess.Popen(
    ['bash', 'scripts/qemu.sh'], cwd=ROOT,
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
)
output = bytearray()
try:
    with selectors.DefaultSelector() as selector:
        selector.register(process.stdout, selectors.EVENT_READ)
        deadline = time.monotonic() + 20
        while expected not in output:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeError('QEMU did not print the kernel greeting within 20 seconds')
            events = selector.select(min(remaining, 1))
            if not events and process.poll() is not None:
                raise RuntimeError(f'QEMU exited early ({process.returncode})')
            for key, _ in events:
                chunk = os.read(key.fileobj.fileno(), 4096)
                if not chunk:
                    raise RuntimeError('QEMU closed the console before the greeting')
                output.extend(chunk)
    # The kernel parks forever. Quit through QEMU's terminal multiplexer.
    tail, _ = process.communicate(input=b'\x01x', timeout=5)
    output.extend(tail)
    if process.returncode != 0:
        raise RuntimeError(f'QEMU exited with status {process.returncode}')
    print(output.decode(errors='replace'))
    print('PASS: QEMU virt/OpenSBI -> S-mode -> Hello chibi-os')
except Exception:
    print(output.decode(errors='replace'))
    raise
finally:
    if process.poll() is None:
        process.kill()
        process.communicate()
