# ARM64 audit before implementation

Source: Koloses/aurora-qt master, `2c574a9e79da5b3fa95bab90ffd3d322f5d63ac0`.

The local machine is Windows 11 x64 (Intel i7-12700K), without Visual Studio,
Qt, Vulkan SDK, or installed WSL. Authenticated GitHub Actions is available on
ChudForks/aurora-qt. Native builds will use Windows and Ubuntu ARM64 runners.

## Observed build blockers

* `setup-deps.ps1` requests lowercase `windows-*` release filenames; v5 assets
  are named `Windows-x64.zip` and `Windows-ARM64.zip`.
* `app.pro` unconditionally links `vulkan-1.lib` and searches the SDK's `Lib`
  directory. Windows PyroWave already uses Vulkan-Hpp RAII dynamic dispatch and
  VMA_STATIC_VULKAN_FUNCTIONS=0. There are no direct Vulkan C entry-point calls
  in the integration or codec. Remove this unnecessary import dependency and
  package a separately built ARM64 loader.
* Shader generation checks only whether its generated file exists, allowing
  stale shaders to survive a failed regeneration. It also leaves paths unquoted.
* Existing workflows omit PyroWave shader tools on Windows; the Linux job is
  x86_64-only and downloads x86_64 linuxdeploy tools. Its AppImage script
  explicitly disables Wayland and DRM. A separate native ARM64 path is needed.

## Architecture and feature review

Windows already selects ARM64 FFmpeg, SDL2/SDL3, Opus, OpenSSL, libplacebo,
Discord and Detours libraries. AntiHooking and common-c use those same paths.
The v5 ARM64 archive includes matching Vulkan headers, but no Vulkan loader.
The codec and application must use the same Vulkan-Hpp headers and NDEBUG state;
the source already enforces their include order and release defines.

PyroWave CPU code uses standard C++20, memcpy and fixed-width fields; no x86
intrinsics were found in its source or the Vulkan integration. Common-c's
nanors includes SIMDe for portable SIMD. Global compiler hardening gates CET
on x86_64. No ARM-specific codec rewrite is justified by this audit.

PyroWave negotiation in session.cpp and common-c's SdpGenerator.c is shared by
all architectures. The same decoder feeds Vulkan compute, swapchain presentation,
HDR and 4:4:4 paths. Keyboard, mouse, controller and SDL audio are common paths.
They must be compiled and runtime-tested independently of build success.

Vulkan context selection currently prefers a discrete GPU; it does not retry
all GPUs on initialization failure. ARM64 alone does not imply GPU support.
Decoder requirements include subgroup operations, subgroup size support,
16/8-bit storage, float16, timeline semaphores, synchronization2 and storage image
access. Present-wait is optional. Unsupported devices must fail initialization;
end-to-end testing needs a suitable real GPU and Solarflare host.
