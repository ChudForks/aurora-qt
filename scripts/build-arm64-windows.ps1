param([Parameter(Mandatory=$true)][string]$QtRoot,
      [Parameter(Mandatory=$true)][string]$Loader,
      [Parameter(Mandatory=$true)][string]$Glslang)
$ErrorActionPreference = 'Stop'
$SourceRoot = Split-Path $PSScriptRoot -Parent
Set-Location $SourceRoot
function Run([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed: $LASTEXITCODE" }
}
$BuildDir = Join-Path $SourceRoot 'build/arm64-release'
$DeployDir = Join-Path $SourceRoot 'build/Aurora-Windows-ARM64'
New-Item -ItemType Directory -Force $BuildDir,$DeployDir | Out-Null
$env:PATH = "$QtRoot/bin;$env:PATH"
Push-Location $BuildDir
try {
    Run "$QtRoot/bin/qmake.exe" @('-r', "$SourceRoot/moonlight-qt.pro", 'CONFIG+=release', 'CONFIG-=debug', 'PYTHON=python', "PYROWAVE_GLSLANG=$Glslang")
    if (!(Select-String -Path 'app/Makefile.Release' -Pattern 'HAVE_PYROWAVE=1' -Quiet)) { throw 'PyroWave was disabled' }
    Run "$SourceRoot/scripts/jom.exe" @('-j4', 'release')
} finally { Pop-Location }
$App = Join-Path $BuildDir 'app/release/Aurora.exe'
Copy-Item $App $DeployDir
Copy-Item "$SourceRoot/libs/windows/lib/arm64/*.dll" $DeployDir
Copy-Item "$BuildDir/AntiHooking/release/AntiHooking.dll" $DeployDir
Copy-Item $Loader "$DeployDir/vulkan-1.dll"
Run "$QtRoot/bin/windeployqt.exe" @('--release', '--dir', $DeployDir, '--qmldir', "$SourceRoot/app/gui", '--no-compiler-runtime', '--no-opengl-sw', '--no-system-d3d-compiler', '--no-system-dxc-compiler', '--no-ffmpeg', $App)
# Qt can deploy an emulated host ICU DLL; Windows 11 supplies native ICU.
if (Test-Path "$DeployDir/icuuc.dll") { Remove-Item -LiteralPath "$DeployDir/icuuc.dll" }
$VsWhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
$CrtDir = & $VsWhere -latest -find 'VC/Redist/MSVC/*/arm64/Microsoft.VC*.CRT' | Select-Object -Last 1
if (!$CrtDir) { throw 'ARM64 Visual C++ runtime not found' }
# VS also places the x64 emulation companion vcruntime140_1.dll in the ARM64
# redist directory. Copy only native ARM64 CRT DLLs; the final import audit
# independently fails if a required dependency is missing.
foreach ($Dll in Get-ChildItem "$CrtDir/*.dll") {
    $Reader = [IO.BinaryReader]::new([IO.File]::OpenRead($Dll.FullName))
    try {
        $Reader.BaseStream.Position = 0x3c
        $PeOffset = $Reader.ReadUInt32()
        $Reader.BaseStream.Position = $PeOffset + 4
        $Machine = $Reader.ReadUInt16()
    } finally { $Reader.Dispose() }
    if ($Machine -eq 0xaa64) { Copy-Item $Dll.FullName $DeployDir }
    else { Write-Host "Excluding unused emulation companion: $($Dll.Name) machine=$Machine" }
}
Copy-Item "$SourceRoot/app/SDL_GameControllerDB/gamecontrollerdb.txt" $DeployDir
New-Item -ItemType File -Force "$DeployDir/portable.dat" | Out-Null
Copy-Item "$SourceRoot/LICENSE" $DeployDir
Copy-Item "$SourceRoot/README.md" $DeployDir
Copy-Item "$SourceRoot/docs/ARM64.md" $DeployDir
New-Item -ItemType Directory -Force "$DeployDir/licenses" | Out-Null
Copy-Item "$SourceRoot/pyrowave/LICENSE*" "$DeployDir/licenses"
Copy-Item "$SourceRoot/pyrowave/external/vk_mem_alloc.h" "$DeployDir/licenses/VulkanMemoryAllocator.h"
Copy-Item "$SourceRoot/pyrowave/src/vk/vk_allocator.cpp" "$DeployDir/licenses/WiVRn-notices.cpp"
if (Test-Path "$QtRoot/licenses") { Copy-Item "$QtRoot/licenses" "$DeployDir/licenses/Qt" -Recurse -Force }
Run 'python' @('scripts/collect-arm64-licenses.py', "$DeployDir/licenses/dependencies")
Copy-Item "$SourceRoot/docs/VIBEPollo-COMPATIBILITY.md" $DeployDir
git rev-parse HEAD | Set-Content "$DeployDir/SOURCE-COMMIT.txt"
Run 'python' @('scripts/verify-arm64.py', '--root', $DeployDir, '--executable', "$DeployDir/Aurora.exe", '--platform', 'windows', '--report', "$DeployDir/architecture.json")
Compress-Archive -Path "$DeployDir/*" -DestinationPath 'build/Aurora-Windows-ARM64.zip' -Force
(Get-FileHash 'build/Aurora-Windows-ARM64.zip' -Algorithm SHA256).Hash.ToLower() + '  Aurora-Windows-ARM64.zip' | Set-Content 'build/Aurora-Windows-ARM64.zip.sha256'
