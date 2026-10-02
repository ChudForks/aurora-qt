#!/usr/bin/env python3
"""Verify every packaged PE/ELF and prove the compiled codec was retained."""
import argparse
import hashlib
import json
import struct
import os
from pathlib import Path


def machine(path):
    with path.open('rb') as f:
        head = f.read(64)
        if head[:2] == b'MZ':
            f.seek(struct.unpack_from('<I', head, 0x3c)[0])
            pe = f.read(6)
            if pe[:4] != b'PE\0\0':
                raise ValueError(f'Invalid PE: {path}')
            return 'PE', struct.unpack_from('<H', pe, 4)[0]
        if head[:4] == b'\x7fELF':
            if head[4:6] != b'\x02\x01':
                raise ValueError(f'Expected little-endian ELF64: {path}')
            return 'ELF', struct.unpack_from('<H', head, 18)[0]
    return None


def verify(root, executable, kind):
    expected = ('PE', 0xaa64) if kind == 'windows' else ('ELF', 183)
    binaries = []
    for path in sorted(root.rglob('*')):
        if not path.is_file() or path.is_symlink():
            continue
        arch = machine(path)
        if arch is not None:
            if arch != expected:
                raise ValueError(f'Wrong architecture {arch}: {path}')
            binaries.append(str(path.relative_to(root)))
    if machine(executable) != expected:
        raise ValueError('Application is not native ARM64')
    data = executable.read_bytes()
    # Diagnostics are in the actual integration TU; shader names are in the
    # generated table referenced by the linked decoder, not just source files.
    for marker in (b'pyrowave: Vulkan context ready', b'idwt_0', b'wavelet'):
        if marker not in data:
            raise ValueError(f'PyroWave evidence missing in executable: {marker!r}')
    if kind == 'windows' and os.name == 'nt':
        import_check(root, binaries)
    return {'architecture': expected[0] + ' ARM64', 'binaries': binaries,
            'pyrowave_linked': True, 'sha256': hashlib.sha256(data).hexdigest(),
            'runtime_streaming_verified': False}


def pe_imports(path):
    data = path.read_bytes()
    pe = struct.unpack_from('<I', data, 0x3c)[0]
    sections = struct.unpack_from('<H', data, pe + 6)[0]
    optional_size = struct.unpack_from('<H', data, pe + 20)[0]
    optional = pe + 24
    def offset(rva):
        for index in range(sections):
            section = optional + optional_size + index * 40
            size, address, raw_size, raw = struct.unpack_from('<IIII', data, section + 8)
            if address <= rva < address + max(size, raw_size):
                return raw + rva - address
        raise ValueError(f'Unmapped PE RVA {rva}: {path}')
    import_rva = struct.unpack_from('<I', data, optional + 112 + 8)[0]
    if not import_rva:
        return []
    imports = []
    cursor = offset(import_rva)
    while any(data[cursor:cursor + 20]):
        name_rva = struct.unpack_from('<I', data, cursor + 12)[0]
        name = offset(name_rva)
        imports.append(data[name:data.index(b'\0', name)].decode('ascii').lower())
        cursor += 20
    return imports


def import_check(root, binaries):
    available = {Path(file).name.lower() for file in binaries}
    system = Path(os.environ['SystemRoot']) / 'System32'
    for file in binaries:
        for dependency in pe_imports(root / file):
            if dependency in available or dependency.startswith(('api-ms-', 'ext-ms-')):
                continue
            if not (system / dependency).is_file():
                raise ValueError(f'Unresolved DLL {dependency} imported by {file}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--executable', required=True, type=Path)
    parser.add_argument('--platform', required=True, choices=['windows', 'linux'])
    parser.add_argument('--report', required=True, type=Path)
    args = parser.parse_args()
    report = verify(args.root, args.executable, args.platform)
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
