#!/usr/bin/env python3
"""Archive the exact checked-out application source and recursive submodules."""
import io
import subprocess
import sys
import tarfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
files = subprocess.check_output(['git', 'ls-files', '--recurse-submodules', '-z'], cwd=root).split(b'\0')
commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root)
with tarfile.open(sys.argv[1], 'w:gz') as archive:
    for name in files:
        if name:
            path = Path(name.decode('utf-8'))
            archive.add(root / path, arcname='aurora-qt/' + path.as_posix(), recursive=False)
    info = tarfile.TarInfo('aurora-qt/SOURCE-COMMIT.txt')
    info.size = len(commit)
    archive.addfile(info, io.BytesIO(commit))
