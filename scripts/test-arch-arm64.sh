#!/usr/bin/env bash
# Test the unchanged Ubuntu-built tar in current Arch userspace on a native
# ARM64 CPU. The runner's kernel is Ubuntu; GPU/display tests are headless.
set -euo pipefail
test "$(uname -m)" = aarch64
package=$(realpath "$1")
expected_sha=${2:-d8797827a3bdd2b0fc32fe291fe9b38c5614872eda6b64fbb52ea66fe7023b34}
test "$(sha256sum "$package" | cut -d' ' -f1)" = "$expected_sha"
results="$PWD/arch-results"
mkdir -p "$results"
sha256sum "$package" > "$results/tested-package.sha256"
uname -a > "$results/runner-kernel.txt"
arch_root="$RUNNER_TEMP/aurora-arch-root"
mkdir -p "$arch_root" "$RUNNER_TEMP/aurora-arch-download"
cd "$RUNNER_TEMP/aurora-arch-download"
# The official OS mirror endpoint is HTTP; authenticity is checked against
# the published signing-key fingerprint before extracting or executing it.
curl -fL --retry 3 http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz -o rootfs.tar.gz
curl -fL --retry 3 http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz.sig -o rootfs.tar.gz.sig
mkdir -m 700 gnupg
gpg --homedir "$PWD/gnupg" --keyserver hkps://keyserver.ubuntu.com --recv-keys 68B3537F39A313B3E574D06777193F152BDBE6A6
gpg --homedir "$PWD/gnupg" --status-fd 1 --verify rootfs.tar.gz.sig rootfs.tar.gz > "$results/rootfs-signature.txt" 2>&1
grep -q 'VALIDSIG 68B3537F39A313B3E574D06777193F152BDBE6A6' "$results/rootfs-signature.txt"
sha256sum rootfs.tar.gz > "$results/rootfs.sha256"
sudo tar --numeric-owner -xpf rootfs.tar.gz -C "$arch_root"
sudo mount --bind "$arch_root" "$arch_root"
sudo mkdir -p "$arch_root/proc" "$arch_root/dev" "$arch_root/sys" "$arch_root/test-results" "$arch_root/opt/aurora-test"
# Replace the image's absolute systemd-resolved symlink within this root only.
sudo rm -f "$arch_root/etc/resolv.conf"
sudo cp /etc/resolv.conf "$arch_root/etc/resolv.conf"
sudo mount -t proc proc "$arch_root/proc"
sudo mount --rbind /dev "$arch_root/dev"
sudo mount --make-rslave "$arch_root/dev"
sudo mount --rbind /sys "$arch_root/sys"
sudo mount --make-rslave "$arch_root/sys"
sudo mount --bind "$results" "$arch_root/test-results"
cleanup() {
  sudo chroot "$arch_root" /usr/bin/gpgconf --kill all || true
  sudo umount "$arch_root/test-results" || true
  sudo umount -R "$arch_root/sys" || true
  sudo umount -R "$arch_root/dev" || true
  sudo umount "$arch_root/proc" || true
  sudo umount "$arch_root" || true
  sudo chown -R "$(id -u):$(id -g)" "$results"
}
trap cleanup EXIT
sudo tar -xzf "$package" -C "$arch_root/opt/aurora-test"
sudo chroot "$arch_root" /bin/bash -s <<'ARCH'
set -euo pipefail
pacman-key --init
pacman-key --populate archlinuxarm
pacman -Syu --noconfirm
pacman -S --noconfirm --needed xorg-server-xvfb xorg-xauth weston \
  vulkan-tools vulkan-swrast mesa libglvnd libx11 libxcb libxkbcommon-x11 \
  alsa-lib libpulse freetype2 harfbuzz fontconfig ttf-dejavu binutils python
pacman -Q > /test-results/arch-package-versions.txt
cat /etc/os-release > /test-results/arch-os-release.txt
getconf GNU_LIBC_VERSION > /test-results/arch-glibc.txt
cd /opt/aurora-test/Aurora-Linux-aarch64
export LD_LIBRARY_PATH="$PWD/usr/lib"
export QT_PLUGIN_PATH="$PWD/usr/plugins"
export QML2_IMPORT_PATH="$PWD/usr/qml"
ldd usr/bin/aurora > /test-results/application-ldd.txt 2>&1
if grep -E 'not found|version .*not found' /test-results/application-ldd.txt; then exit 1; fi
# Dynamic plugins also need compatible system libraries; check each ELF.
python - <<'PY'
import pathlib, subprocess
failures = []
with open('/test-results/all-elf-ldd.txt', 'w') as log:
    for path in sorted(pathlib.Path('usr').rglob('*')):
        if not path.is_file() or path.is_symlink(): continue
        with path.open('rb') as source:
            if source.read(4) != b'\x7fELF': continue
        result = subprocess.run(['ldd', str(path.resolve())], capture_output=True, text=True)
        output = result.stdout + result.stderr
        log.write(f'\n{path}\n{output}')
        if 'not found' in output: failures.append(str(path))
if failures: raise SystemExit('Unresolved ELF dependencies: ' + ', '.join(failures))
PY
vulkaninfo --summary > /test-results/vulkan-summary.txt 2>&1
./usr/bin/pyrowave-smoke > /test-results/pyrowave-smoke.log 2>&1
grep -q 'PASS: PyroWave decoder and Vulkan shader pipelines initialized' /test-results/pyrowave-smoke.log
set +e
QT_QPA_PLATFORM=xcb QT_QUICK_BACKEND=software timeout 20s xvfb-run -a ./aurora.sh > /test-results/x11-startup.log 2>&1
x11_result=$?
set -e
test "$x11_result" = 124
if grep -E 'QQmlApplicationEngine failed|Qt Fatal:|could not be initialized|error while loading shared libraries' /test-results/x11-startup.log; then exit 1; fi
# Weston uses Arch libraries, rather than the bundle's LD_LIBRARY_PATH.
export XDG_RUNTIME_DIR=/tmp/aurora-arch-runtime
mkdir -m 700 "$XDG_RUNTIME_DIR"
env -u LD_LIBRARY_PATH -u QT_PLUGIN_PATH -u QML2_IMPORT_PATH \
  weston --backend=headless --renderer=pixman --socket=aurora-test --idle-time=0 \
  --log=/test-results/weston.log &
weston_pid=$!
trap 'kill "$weston_pid" 2>/dev/null || true' EXIT
for attempt in $(seq 1 30); do
  test -S "$XDG_RUNTIME_DIR/aurora-test" && break
  sleep 1
done
test -S "$XDG_RUNTIME_DIR/aurora-test"
set +e
WAYLAND_DISPLAY=aurora-test QT_QPA_PLATFORM=wayland QT_QUICK_BACKEND=software \
  timeout 20s ./aurora.sh > /test-results/wayland-startup.log 2>&1
wayland_result=$?
set -e
test "$wayland_result" = 124
if grep -E 'QQmlApplicationEngine failed|Qt Fatal:|could not be initialized|error while loading shared libraries' /test-results/wayland-startup.log; then exit 1; fi
printf '%s\n' 'PASS: unchanged package dependency resolution, software Vulkan/PyroWave initialization, X11 and Wayland GUI startup in Arch Linux ARM userspace.' \
  'UNVERIFIED: Arch kernel boot, Snapdragon Adreno GPU, real display/input/audio, VibePollo streaming, and performance.' > /test-results/result.txt
ARCH
