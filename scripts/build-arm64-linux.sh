#!/usr/bin/env bash
set -euo pipefail
source_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$source_root"
test "$(uname -m)" = aarch64
mkdir -p build/arm64-release build/Aurora-Linux-aarch64
deploy="$source_root/build/Aurora-Linux-aarch64"
cd build/arm64-release
qmake6 -r "$source_root/moonlight-qt.pro" CONFIG+=release CONFIG-=debug PREFIX=/usr
grep -q 'HAVE_PYROWAVE=1' app/Makefile.Release
grep -q 'HAS_WAYLAND' app/Makefile.Release
grep -q 'HAS_X11' app/Makefile.Release
grep -q 'HAVE_FFMPEG' app/Makefile.Release
make -j"$(nproc)" release
make INSTALL_ROOT="$deploy" install
cd "$source_root"
export QMAKE=qmake6 QML_SOURCES_PATHS="$source_root/app/gui" APPIMAGE_EXTRACT_AND_RUN=1
export EXTRA_QT_MODULES=waylandcompositor
export EXTRA_PLATFORM_PLUGINS='libqwayland-egl.so;libqwayland-generic.so'
# Qt's TLS plugin loads libssl dynamically. Bundling only the linked libcrypto
# mixes it with newer distro libssl and breaks identity creation on Arch.
openssl_libdir="$(pkg-config --variable=libdir openssl)"
linuxdeploy-aarch64.AppImage --appdir "$deploy" --executable "$deploy/usr/bin/aurora" \
  --library "$openssl_libdir/libssl.so.3" --library "$openssl_libdir/libcrypto.so.3" \
  --exclude-library='libva*.so*' --plugin qt
# VA-API loads distro-specific video drivers. Use the host's matching libva
# family rather than overriding it with Ubuntu 2.20 (which crashes if a
# Wayland compositor exposes no wl_drm device). VA-API remains compiled in.
if compgen -G "$deploy/usr/lib/libva*.so*" > /dev/null; then
    echo 'VA-API libraries must come from the host distribution' >&2
    exit 1
fi
test -f "$deploy/usr/lib/libssl.so.3"
test -f "$deploy/usr/plugins/platforms/libqwayland-egl.so"
test -f "$deploy/usr/plugins/platforms/libqwayland-generic.so"
mkdir -p "$deploy/licenses"
cp LICENSE README.md docs/ARM64.md "$deploy/"
cp docs/VIBEPollo-COMPATIBILITY.md "$deploy/"
if test -f docs/ARCH-ARM64.md; then cp docs/ARCH-ARM64.md "$deploy/"; fi
cp pyrowave/LICENSE* "$deploy/licenses/"
cp pyrowave/external/vk_mem_alloc.h "$deploy/licenses/VulkanMemoryAllocator.h"
cp pyrowave/src/vk/vk_allocator.cpp "$deploy/licenses/WiVRn-notices.cpp"
mkdir -p "$deploy/licenses/distribution"
for notice in /usr/share/doc/*/copyright; do
    cp -L "$notice" "$deploy/licenses/distribution/$(basename "$(dirname "$notice")").txt"
done
g++ -std=c++20 -O2 -DNDEBUG -DVULKAN_HPP_NO_STRUCT_CONSTRUCTORS \
  -Ipyrowave/src -Ipyrowave/external -Iapp/streaming/video/pyrowave \
  scripts/pyrowave-smoke.cpp app/streaming/video/pyrowave/pyrowave_vk.cpp \
  build/arm64-release/pyrowave/libpyrowave.a $(pkg-config --cflags --libs sdl2) \
  -lvulkan -ldl -pthread -o "$deploy/usr/bin/pyrowave-smoke"
cp app/SDL_GameControllerDB/gamecontrollerdb.txt "$deploy/"
git rev-parse HEAD > "$deploy/SOURCE-COMMIT.txt"
# This tar contains an AppDir. No FUSE is required for the launcher.
cat > "$deploy/aurora.sh" <<'EOF'
#!/usr/bin/env sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export LD_LIBRARY_PATH="$root/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export QT_PLUGIN_PATH="$root/usr/plugins"
export QML2_IMPORT_PATH="$root/usr/qml"
exec "$root/usr/bin/aurora" "$@"
EOF
chmod +x "$deploy/aurora.sh"
python3 scripts/verify-arm64.py --root "$deploy" --executable "$deploy/usr/bin/aurora" --platform linux --report "$deploy/architecture.json"
set +e
"$deploy/usr/bin/pyrowave-smoke" > "$deploy/pyrowave-smoke.log" 2>&1
smoke_result=$?
set -e
cat "$deploy/pyrowave-smoke.log"
test "$smoke_result" = 0 || test "$smoke_result" = 77
echo "$smoke_result" > "$deploy/pyrowave-smoke.exit-code"
ldd "$deploy/usr/bin/aurora" | tee "$deploy/dependencies.txt"
if grep -q 'not found' "$deploy/dependencies.txt"; then exit 1; fi
tar -C build -czf build/Aurora-Linux-aarch64.tar.gz Aurora-Linux-aarch64
(cd build && sha256sum Aurora-Linux-aarch64.tar.gz > Aurora-Linux-aarch64.tar.gz.sha256)
