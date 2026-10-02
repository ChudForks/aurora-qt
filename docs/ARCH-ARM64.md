# Arch Linux ARM compatibility

The delivered tar is a native AArch64 release build with bundled Qt and
application dependencies. Arch-specific compiler flags are not required merely
because the distribution is Arch. A native pacman package would improve package
management and integration with system libraries; it is not evidence of faster
PyroWave decoding. Do not use -mcpu=native from a cloud runner to target a
Snapdragon laptop: its CPU may differ from the runner's CPU.

## Reproduce the compatibility test

The initial test downloaded the original Linux artifact from build 36948165249,
with SHA-256
`d8797827a3bdd2b0fc32fe291fe9b38c5614872eda6b64fbb52ea66fe7023b34`.
It found that Qt loaded the newer system libssl alongside the older bundled
libcrypto, causing credential creation to fail. The original bundle also omitted
native Qt Wayland plugins. The corrected recipe includes the matching OpenSSL
pair and Qt Wayland platform modules. VA-API libraries come from the host
distribution so they match its graphics drivers. The bundled Ubuntu libva 2.20
crashed during Wayland decoder probing when Weston exposed no wl_drm device;
current Arch libva handles that condition. No CPU-specific codec changes were
needed.

The workflow builds the corrected tar and validates its exact SHA-256. It
verifies the official Arch Linux ARM rootfs signature, updates that rootfs,
and runs on a native AArch64 runner. It records rootfs hash, installed package
versions, the actual GNU libc version, all ELF dependency checks, Vulkan device,
PyroWave smoke output, and X11/Wayland startup logs.

The test uses Arch userspace in a chroot on the Ubuntu runner's kernel. Xvfb and
Weston nested on another Xvfb display check X11 and native Wayland startup;
llvmpipe checks software Vulkan. The nested compositor supplies a keyboard/mouse
seat. A compositor without an input seat exposes a null-input-device crash in
the bundled Qt 6.4 text-input code; that condition is recorded separately. It does
not boot an Arch kernel, measure laptop performance, exercise an Adreno GPU,
or establish input/audio/streaming compatibility on a physical laptop.

Use workflow_dispatch on the arch-arm64-compat branch. Leave package_run_id empty
to build a fresh tar, or specify an existing run containing the
Aurora-Linux-aarch64-Wayland artifact to repeat validation of the same tar.

## Snapdragon 8cx Gen 3

The user's "acx Gen3" is interpreted as Snapdragon 8cx Gen 3. Lenovo lists the
8cx Gen 3 with Adreno 690. This does not establish the exact laptop model.
Mesa's Freedreno/Turnip release notes document A690 support, and Arch Linux ARM
provides the Adreno Vulkan driver as vulkan-freedreno.

For an installed, updated Arch Linux ARM laptop, the relevant userspace tools are:

```sh
sudo pacman -Syu mesa libva vulkan-freedreno vulkan-icd-loader vulkan-tools
vulkaninfo --summary
```

The laptop must also have a suitable kernel, device tree, and GPU firmware for
its exact model. Confirm that vulkaninfo reports Adreno/Turnip, rather than only
llvmpipe software rendering. The presence of a Vulkan version alone does not
prove PyroWave's storage, subgroup, float16 and synchronization requirements.

Extract the tar and run from its Aurora-Linux-aarch64 directory:

```sh
LD_LIBRARY_PATH="$PWD/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  ./usr/bin/pyrowave-smoke
./aurora.sh
```

Save the device name and smoke output. Exit 0 confirms decoder/pipeline
initialization; 77 means the environment cannot perform that test. It does not
decode a frame or test presentation. Then follow ARM64.md's pairing, real video,
audio/input, X11/Wayland and HDR tests using the friend's exact VibePollo release.
VIBEPollo-COMPATIBILITY.md explains the remaining bitstream interoperability test.

Sources:
* https://archlinuxarm.org/platforms/armv8/generic
* https://archlinuxarm.org/about/package-signing
* https://archlinuxarm.org/packages/aarch64/vulkan-freedreno
* https://docs.mesa3d.org/drivers/freedreno.html
* https://docs.mesa3d.org/relnotes/23.1.0.html
* https://archlinuxarm.org/packages/aarch64/libva
* https://github.com/intel/libva/blob/2.20.0/va/wayland/va_wayland.c
* https://psref.lenovo.com/syspool/Sys/PDF/ThinkPad/ThinkPad_X13s_Gen_1/ThinkPad_X13s_Gen_1_Spec.PDF
