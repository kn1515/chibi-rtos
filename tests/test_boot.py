"""Run the actual RV64 binary in S-mode. UART is mocked, not a Duo emulator."""
from pathlib import Path
import struct
import subprocess
import unittest
import zlib

from elftools.elf.elffile import ELFFile
from unicorn import Uc, UC_ARCH_RISCV, UC_MODE_RISCV64
from unicorn import UC_HOOK_CODE, UC_HOOK_MEM_READ, UC_HOOK_MEM_WRITE
from unicorn.riscv_const import (
    UC_RISCV_REG_A0, UC_RISCV_REG_A1, UC_RISCV_REG_PC,
    UC_RISCV_REG_PRIV, UC_RISCV_REG_SP, UC_RISCV_REG_SIE,
    UC_RISCV_REG_SSTATUS, UC_RISCV_REG_STVEC,
)

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
BASE = 0x80200000
UART = 0x04140000


class BootTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binary = (BUILD / 'chibi-os.bin').read_bytes()
        with (BUILD / 'chibi-os.elf').open('rb') as f:
            elf = ELFFile(f)
            cls.entry = elf.header['e_entry']
            cls.machine = elf.header['e_machine']
            cls.symbols = {
                s.name: s.entry['st_value']
                for s in elf.get_section_by_name('.symtab').iter_symbols()
            }
            cls.undefined = [s.name for s in elf.get_section_by_name('.symtab').iter_symbols()
                             if s.name and s.entry['st_shndx'] == 'SHN_UNDEF']

    def test_link_layout(self):
        self.assertEqual(self.machine, 'EM_RISCV')
        self.assertEqual(self.entry, BASE)
        self.assertEqual(self.undefined, [])
        s = self.symbols
        self.assertEqual(len(self.binary), s['__image_end'] - BASE)
        self.assertLessEqual(s['__image_end'], s['__bss_start'])
        self.assertEqual(s['__bss_start'] % 8, 0)
        self.assertEqual(s['__bss_end'] % 8, 0)
        self.assertEqual(s['__stack_top'] % 16, 0)
        self.assertEqual(s['__stack_top'] - s['__stack_bottom'], 16384)
        self.assertLessEqual(s['__kernel_end'], BASE + 0x100000)

    def emulate(self, corrupt_data=False):
        s = self.symbols
        cpu = Uc(UC_ARCH_RISCV, UC_MODE_RISCV64)
        cpu.mem_map(BASE, 0x100000)
        cpu.mem_map(UART, 0x1000)
        # A dirty initial RAM image catches missing BSS initialization.
        cpu.mem_write(BASE, b'\xa5' * 0x100000)
        cpu.mem_write(BASE, self.binary)
        if corrupt_data:
            cpu.mem_write(s['data_cookie'], b'\0' * 8)
        cpu.reg_write(UC_RISCV_REG_PRIV, 1)  # supervisor mode
        cpu.reg_write(UC_RISCV_REG_A0, 7)
        cpu.reg_write(UC_RISCV_REG_A1, 0x81200000)
        cpu.reg_write(UC_RISCV_REG_SIE, 0x222)
        output = bytearray()
        reads = [0, 0]
        stopped = []
        writes = []

        def on_read(uc, access, address, size, value, data):
            self.assertEqual((address, size), (UART + 0x14, 4))
            reads[0] += 1
            status = 0 if reads[0] <= 3 else 0x20
            if output.endswith(b'\n'):
                reads[1] += 1
                if reads[1] > 3:
                    status |= 0x40
            uc.mem_write(address, struct.pack('<I', status))

        def on_write(uc, access, address, size, value, data):
            self.assertEqual(size, 4)
            writes.append((address, value))
            if address == UART:
                self.assertGreater(reads[0], 3, 'must wait for THRE')
                output.append(value & 255)
            else:
                self.assertEqual((address, value), (UART + 4, 0))

        def on_code(uc, address, size, data):
            if address in (s['kernel_halt'], s['trap_entry']):
                stopped.append(address)
                uc.emu_stop()

        cpu.hook_add(UC_HOOK_MEM_READ, on_read, begin=UART, end=UART + 0xff)
        cpu.hook_add(UC_HOOK_MEM_WRITE, on_write, begin=UART, end=UART + 0xff)
        cpu.hook_add(UC_HOOK_CODE, on_code)
        cpu.emu_start(BASE, BASE + 0x100000, timeout=2_000_000, count=100000)
        self.assertEqual(stopped, [s['kernel_halt']],
                         f'kernel trapped or timed out, PC={cpu.reg_read(UC_RISCV_REG_PC):#x}')
        self.assertEqual(cpu.reg_read(UC_RISCV_REG_SP), s['__stack_top'])
        self.assertEqual(cpu.reg_read(UC_RISCV_REG_SSTATUS) & 2, 0)
        self.assertEqual(cpu.reg_read(UC_RISCV_REG_SIE), 0)
        self.assertEqual(cpu.reg_read(UC_RISCV_REG_STVEC), s['trap_entry'])
        self.assertGreater(reads[1], 3, 'must wait for TEMT before parking')
        self.assertEqual(writes[0], (UART + 4, 0))
        return cpu, bytes(output)

    def test_raw_binary_hello_and_boot_arguments(self):
        cpu, output = self.emulate()
        self.assertEqual(output, b'Hello chibi-os\r\n')
        for symbol, expected in [('boot_hart_id', 7), ('boot_dtb', 0x81200000),
                                 ('boot_count', 1)]:
            value, = struct.unpack('<Q', cpu.mem_read(self.symbols[symbol], 8))
            self.assertEqual(value, expected)
        print('UART emulation:', output.decode().strip())

    def test_corrupted_data_is_reported(self):
        _, output = self.emulate(corrupt_data=True)
        self.assertEqual(output, b'chibi-os: startup memory check failed\r\n')

    def test_fit_contents_and_checksums(self):
        def get(node, prop, kind='s'):
            return subprocess.check_output(
                ['fdtget', '-t', kind, str(BUILD / 'chibi-os.itb'), node, prop],
                text=True).strip()

        self.assertEqual(get('/configurations', 'default'), 'conf-duo')
        self.assertEqual(get('/configurations/conf-duo', 'kernel'), 'kernel')
        self.assertEqual(get('/configurations/conf-duo', 'fdt'), 'fdt')
        self.assertEqual(get('/images/kernel', 'arch'), 'riscv')
        self.assertEqual(get('/images/kernel', 'os'), 'linux')
        self.assertEqual(get('/images/kernel', 'compression'), 'none')
        self.assertEqual(int(get('/images/kernel', 'load', 'x'), 16), BASE)
        self.assertEqual(int(get('/images/kernel', 'entry', 'x'), 16), BASE)
        for name, expected in [('kernel', self.binary), ('fdt', (BUILD / 'duo.dtb').read_bytes())]:
            data = bytes(int(b, 16) for b in get(f'/images/{name}', 'data', 'bx').split())
            self.assertEqual(data, expected)
            self.assertEqual(get(f'/images/{name}/hash-1', 'algo'), 'crc32')
            crc = int(get(f'/images/{name}/hash-1', 'value', 'x'), 16)
            self.assertEqual(crc, zlib.crc32(data))
        self.assertLess((BUILD / 'chibi-os.itb').stat().st_size, 0x100000)


if __name__ == '__main__':
    unittest.main(verbosity=2)
