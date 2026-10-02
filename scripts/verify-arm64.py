#!/usr/bin/env python3
"""Verify every packaged PE/ELF and prove the compiled codec was retained."""
import argparse
import hashlib
import json
import struct
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
    return {'architecture': expected[0] + ' ARM64', 'binaries': binaries,
            'pyrowave_linked': True, 'sha256': hashlib.sha256(data).hexdigest(),
            'runtime_streaming_verified': False}


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
