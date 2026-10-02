#!/usr/bin/env python3
"""Collect upstream notices for the v5 Windows dependency bundle."""
import argparse
import json
import urllib.request
from pathlib import Path

# References from moonlight-qt-deps tag v5, rather than moving default branches.
SOURCES = {
    'Detours': ('microsoft/Detours', '9764cebcb1a75940e68fa83d6730ffaf0f669401', ['LICENSE.md']),
    'FFmpeg': ('FFmpeg/FFmpeg', '239f2c733de417201d7ad3b3b8b0d9b63285b2b1', ['COPYING.LGPLv2.1', 'COPYING.LGPLv3', 'LICENSE.md']),
    'SDL3': ('libsdl-org/SDL', '8e37db5e797b6167f3a00d697d816a684bd259c7', ['LICENSE.txt']),
    'SDL2-compat': ('libsdl-org/sdl2-compat', '84b4032aef2742f79bd7b4317a22b84b0fe14155', ['LICENSE.txt']),
    'SDL_ttf': ('libsdl-org/SDL_ttf', 'a883e490e30fb44a5336ea3dcb990c6982c5216f', ['LICENSE.txt']),
    'Vulkan-Headers': ('KhronosGroup/Vulkan-Headers', '2cd90f9d20df57eac214c148f3aed885372ddcfe', ['LICENSE.md']),
    'dav1d': ('videolan/dav1d', 'b546257f770768b2c88258c533da38b91a06f737', ['COPYING']),
    'discord-rpc': ('cgutman/discord-rpc', '7bcf3b3fdd02d4d5072971ef1d5b4e6dd3a765dc', ['LICENSE']),
    'libplacebo': ('haasn/libplacebo', 'b915882db8d349cc1831c3d3978ee7d5f914b10b', ['LICENSE']),
    'OpenSSL': ('openssl/openssl', 'fe686e15d84334b284f883118ed92f64b409b3aa', ['LICENSE.txt']),
    'Opus': ('xiph/opus', 'ddbe48383984d56acd9e1ab6a090c54ca6b735a6', ['COPYING']),
    'Vulkan-Loader': ('KhronosGroup/Vulkan-Loader', 'fb78607414e154c7a5c01b23177ba719c8a44909', ['LICENSE.txt']),
    'Qt6': ('qt/qtbase', 'v6.11.1', ['LICENSES/LGPL-3.0-only.txt', 'LICENSES/GPL-3.0-only.txt']),
}

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    args.destination.mkdir(parents=True, exist_ok=True)
    provenance = {}
    for name, (repo, ref, files) in SOURCES.items():
        provenance[name] = {'repository': f'https://github.com/{repo}', 'ref': ref}
        for file in files:
            url = f'https://raw.githubusercontent.com/{repo}/{ref}/{file}'
            with urllib.request.urlopen(url, timeout=60) as response:
                content = response.read()
            (args.destination / (name + '-' + Path(file).name)).write_bytes(content)
    (args.destination / 'dependency-source-refs.json').write_text(json.dumps(provenance, indent=2) + '\n')
