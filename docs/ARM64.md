# Building and testing Aurora ARM64

These packages retain PyroWave and standard codecs. Build success is separate
from GPU compatibility and streaming validation. Consult architecture.json and
the accompanying validation report for checks actually performed.

## Reproduce

Clone recursively and check out the commit in SOURCE-COMMIT.txt. Run the
`ARM64 packages` workflow (`.github/workflows/build-arm64.yml`) with
workflow_dispatch. Windows uses a native Windows 11 ARM64 runner, MSVC ARM64,
Qt 6.11.1 ARM64, v5 Moonlight dependencies and a native Vulkan loader. The shader
compiler and SPIR-V optimizer are also built natively. Ubuntu uses a native
24.04 ARM64 runner, Qt 6, FFmpeg, SDL2, libplacebo, OpenSSL and Opus packages.
The workflow records dependency versions and builds all submodules.

For local Windows builds, install the same dependencies, load the VS ARM64
developer environment, and run scripts/build-arm64-windows.ps1 with -QtRoot,
-Loader (path to an ARM64 vulkan-1.dll) and -Glslang. spirv-opt must be on PATH.
For Linux, install the packages listed in the workflow and put ARM64 linuxdeploy
and its Qt plugin on PATH, then run `bash scripts/build-arm64-linux.sh`.

## Use

Windows: extract the entire ZIP to a writable folder and run Aurora.exe.
portable.dat keeps settings in that folder. Install the GPU vendor's native
Vulkan driver; the included loader does not supply a GPU driver.

Linux: extract the tar and run `./Aurora-Linux-aarch64/aurora.sh`. This AppDir
bundle targets Ubuntu 24.04 or a compatible newer ARM64 distribution (glibc
2.39 baseline); older distributions are not guaranteed. Host GPU drivers,
EGL/GL/Vulkan ICDs and the display/audio session remain system dependencies.
The corrected Linux packaging also uses the host's VA-API libraries (libva.so.2,
libva-drm.so.2, libva-x11.so.2 and libva-wayland.so.2). On Arch Linux ARM install
libva with the appropriate Mesa/Vulkan drivers; see ARCH-ARM64.md for the tested
environment and hardware checks.
X11 and Wayland are compiled in. The archive does not require FUSE.

## Real-hardware validation procedure

The intended host is VibePollo with PyroWave support. See
VIBEPollo-COMPATIBILITY.md: negotiation matches, but its newer vendored bitstream
has not been tested against this WiVRn-derived Aurora decoder. Use the friend's
exact host version for the end-to-end test.

The Linux package also includes `usr/bin/pyrowave-smoke`, which checks native
wire layout and creates headless decoder shader pipelines. Exit 77 means the
available Vulkan device cannot perform this test, not successful decoding.
The result and device name are recorded in pyrowave-smoke.log. This test does
not execute a streamed frame or validate swapchain presentation.

1. Check the SHA-256 against the sidecar. On Windows run
   `Get-FileHash Aurora-Windows-ARM64.zip -Algorithm SHA256`; on Linux run
   `sha256sum -c Aurora-Linux-aarch64.tar.gz.sha256`.
2. Confirm native architecture (`dumpbin /headers Aurora.exe` or
   `file usr/bin/aurora`). Run verify-arm64.py over the extracted package.
3. Run `vulkaninfo --summary` and save full `vulkaninfo` output. Check 16/8-bit
   storage, float16, subgroup operations/size, timeline semaphores,
   synchronization2, storage-image access and swapchain presentation support.
   ARM64 does not imply these capabilities. HDR needs a suitable display,
   surface format, driver and compositor.
4. Launch the GUI in an actual desktop session. Verify settings survive restart,
   discovery and manual host entry, pairing PIN, keyboard, relative/absolute
   mouse, a controller including rumble, and stereo/multichannel audio.
5. Pair a compatible Sunshine/Solarflare host. Stream H.264, HEVC and AV1
   separately where supported. Record resolution, refresh rate, hardware
   decoder, audio and input results. Do not infer them from GUI startup.
6. On Solarflare, enable PyroWave; in Aurora select forced PyroWave. Stream a
   moving scene for at least ten minutes. Save both logs showing PyroWave
   negotiation, `pyrowave: Vulkan context ready`, successful decoder creation
   and presented frames. Check visible movement, pacing, input, audio and
   reconnect. Repeat at 1080p60 and the desired higher resolution/refresh rate.
7. Repeat PyroWave SDR 4:2:0, 4:4:4 and HDR10 where hardware permits, with
   packet loss if available. On Linux repeat under X11 and Wayland. Verify
   no Vulkan validation errors or synchronization corruption. Present-wait
   is optional; record whether the driver supports it.
8. Report each separately: compilation, GUI startup, conventional streaming,
   PyroWave decoder initialization, end-to-end PyroWave, HDR/4:4:4, input/audio.
   Record OS, GPU/driver, host commit, logs, duration and observed failures.

## Licensing

Aurora retains GPL-3.0 and upstream attribution; PyroWave retains its own
notices. Dependencies keep their original licenses. Corresponding application
source is the recorded commit of this fork plus its recursive submodule refs.
The workflows record dependency provenance; preserve their notices when
redistributing binaries.
