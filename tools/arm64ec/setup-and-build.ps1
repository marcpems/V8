#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Sets up a blank Windows on ARM machine to build and test V8 for ARM64EC.

.DESCRIPTION
    This script installs prerequisites, fetches the V8 source code,
    applies ARM64EC patches to third-party submodules, generates the
    build configuration, builds V8, and runs the test suites.

    Run from an elevated PowerShell prompt on a Windows 11 ARM64 machine.

.PARAMETER WorkDir
    Root directory for the V8 checkout. Defaults to C:\v8-dev.

.PARAMETER SkipPrereqs
    Skip prerequisite installation (use if already installed).

.PARAMETER SkipFetch
    Skip fetching V8 source (use if already fetched).

.PARAMETER BuildOnly
    Only generate + build, skip prereqs and fetch.

.PARAMETER TestOnly
    Only run tests (assumes build exists).

.EXAMPLE
    .\setup-and-build.ps1
    .\setup-and-build.ps1 -WorkDir D:\v8-test -SkipPrereqs
    .\setup-and-build.ps1 -TestOnly
#>

param(
    [string]$WorkDir = "C:\v8-dev",
    [switch]$SkipPrereqs,
    [switch]$SkipFetch,
    [switch]$BuildOnly,
    [switch]$TestOnly
)

$ErrorActionPreference = "Stop"
$Branch = "marcpe_Arm64EC_experimental"
$ForkUrl = "https://github.com/marcpems/v8.git"

function Write-Step($msg) {
    Write-Host "`n=== $msg ===" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# 1. Prerequisites
# ---------------------------------------------------------------------------
if (-not $SkipPrereqs -and -not $BuildOnly -and -not $TestOnly) {
    Write-Step "Installing prerequisites"

    # Git
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "Installing Git..."
        winget install --id Git.Git -e --accept-package-agreements --accept-source-agreements
        $env:PATH += ";C:\Program Files\Git\cmd"
    }
    Write-Host "Git: $(git --version)"

    # Python 3
    if (-not (Get-Command python3 -ErrorAction SilentlyContinue)) {
        Write-Host "Installing Python 3..."
        winget install --id Python.Python.3.13 -e --accept-package-agreements --accept-source-agreements
    }
    Write-Host "Python: $(python3 --version)"

    # Visual Studio Build Tools (if full VS is not installed)
    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vsWhere) -or -not (& $vsWhere -latest -property installationPath)) {
        Write-Host "No Visual Studio installation found."
        Write-Host "Please install Visual Studio 2022+ with the following workloads:"
        Write-Host "  - Desktop development with C++"
        Write-Host "  - ARM64/ARM64EC build tools"
        Write-Host ""
        Write-Host "Or run:"
        Write-Host '  winget install --id Microsoft.VisualStudio.2022.Community -e --override "--add Microsoft.VisualStudio.Workload.NativeDesktop --add Microsoft.VisualStudio.Component.VC.Tools.ARM64EC --includeRecommended --passive"'
        throw "Visual Studio is required. Install it and re-run this script."
    }
    $vsPath = & $vsWhere -latest -property installationPath
    Write-Host "Visual Studio: $vsPath"

    # depot_tools
    $depotToolsDir = Join-Path $WorkDir "depot_tools"
    if (-not (Test-Path $depotToolsDir)) {
        Write-Host "Cloning depot_tools..."
        git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git $depotToolsDir
    }
    if ($env:PATH -notlike "*depot_tools*") {
        $env:PATH = "$depotToolsDir;$env:PATH"
        [System.Environment]::SetEnvironmentVariable("PATH", "$depotToolsDir;$([System.Environment]::GetEnvironmentVariable('PATH', 'User'))", "User")
        Write-Host "Added depot_tools to PATH (user scope)."
    }
    Write-Host "depot_tools: $depotToolsDir"
}

# Ensure depot_tools is on PATH for subsequent steps.
# Also check common install locations if WorkDir depot_tools doesn't exist yet.
$depotToolsDir = Join-Path $WorkDir "depot_tools"
$depotToolsCandidates = @(
    $depotToolsDir,
    "d:\depot_tools",
    "$env:USERPROFILE\depot_tools",
    "C:\depot_tools"
)
foreach ($candidate in $depotToolsCandidates) {
    if (Test-Path $candidate) {
        $depotToolsDir = $candidate
        break
    }
}
if ($env:PATH -notlike "*depot_tools*") {
    $env:PATH = "$depotToolsDir;$env:PATH"
}
Write-Host "Using depot_tools: $depotToolsDir"

# Use local VS toolchain (avoids GCS auth issues on personal machines)
$env:DEPOT_TOOLS_WIN_TOOLCHAIN = "0"

# ---------------------------------------------------------------------------
# 2. Fetch V8
# ---------------------------------------------------------------------------
$v8Dir = Join-Path $WorkDir "v8"

if (-not $SkipFetch -and -not $BuildOnly -and -not $TestOnly) {
    Write-Step "Fetching V8 source code"

    if (-not (Test-Path $WorkDir)) {
        New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    }
    Push-Location $WorkDir
    try {
        if (-not (Test-Path ".gclient")) {
            fetch v8
        } else {
            Write-Host ".gclient already exists, running gclient sync..."
        }
        gclient sync -D
    } finally {
        Pop-Location
    }

    # Add fork remote and checkout branch
    Write-Step "Checking out ARM64EC branch"
    Push-Location $v8Dir
    try {
        $remotes = git remote
        if ($remotes -notcontains "marcpems") {
            git remote add marcpems $ForkUrl
        }
        git fetch marcpems $Branch
        git checkout -b $Branch "marcpems/$Branch" 2>$null
        if ($LASTEXITCODE -ne 0) {
            git checkout $Branch
            git reset --hard "marcpems/$Branch"
        }
    } finally {
        Pop-Location
    }
}

# ---------------------------------------------------------------------------
# 3. Apply patches to submodules
# ---------------------------------------------------------------------------
if (-not $TestOnly) {
    Write-Step "Applying ARM64EC patches to third-party dependencies"

    Push-Location $v8Dir
    try {
        $patchDir = Join-Path $v8Dir "patches\arm64ec"
        $patchMap = @{
            "build.patch"      = "build"
            "abseil-cpp.patch" = "third_party\abseil-cpp"
            "fp16.patch"       = "third_party\fp16\src"
            "highway.patch"    = "third_party\highway\src"
            "dragonbox.patch"  = "third_party\dragonbox\src"
            "libcxx.patch"     = "third_party\libc++\src"
            "protobuf.patch"   = "third_party\protobuf"
        }

        foreach ($patch in $patchMap.GetEnumerator()) {
            $patchFile = Join-Path $patchDir $patch.Key
            $targetDir = Join-Path $v8Dir $patch.Value

            if (-not (Test-Path $patchFile) -or (Get-Item $patchFile).Length -eq 0) {
                Write-Host "  Skipping $($patch.Key) (empty or missing)"
                continue
            }
            if (-not (Test-Path $targetDir)) {
                Write-Host "  Skipping $($patch.Key) (target dir missing: $($patch.Value))"
                continue
            }

            Write-Host "  Applying $($patch.Key) to $($patch.Value)..."
            # Check if patch is already applied
            $result = git -C $targetDir apply --check $patchFile 2>&1
            if ($LASTEXITCODE -eq 0) {
                git -C $targetDir apply $patchFile
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "Failed to apply $($patch.Key) — may need manual resolution."
                }
            } else {
                Write-Host "    Already applied or conflicts — skipping."
            }
        }
    } finally {
        Pop-Location
    }
}

# ---------------------------------------------------------------------------
# 4. Generate build configuration
# ---------------------------------------------------------------------------
$outDir = "out\arm64ec"

if (-not $TestOnly) {
    Write-Step "Generating ARM64EC build configuration"

    Push-Location $v8Dir
    try {
        $gnArgs = @(
            'target_cpu="arm64ec"'
            'target_os="win"'
            'is_clang=true'
            'v8_control_flow_integrity=false'
            'v8_enable_pointer_compression=true'
            'use_lld=false'
            'is_component_build=false'
            'enable_rust=false'
        ) -join ' '

        # Use cmd to avoid PowerShell quote-stripping
        cmd /c "gn gen $outDir --args=""$gnArgs"""
        if ($LASTEXITCODE -ne 0) { throw "gn gen failed" }
    } finally {
        Pop-Location
    }
}

# ---------------------------------------------------------------------------
# 5. Build
# ---------------------------------------------------------------------------
if (-not $TestOnly) {
    Write-Step "Building V8 for ARM64EC"

    Push-Location $v8Dir
    try {
        # Build d8 shell, unittests, and cctests
        ninja -C $outDir d8 v8 `
            test/unittests:v8_unittests `
            test/unittests:v8_heap_base_unittests `
            test/cctest:cctest
        if ($LASTEXITCODE -ne 0) { throw "Build failed" }

        Write-Host "`nBuild complete. Verifying binary..." -ForegroundColor Green
        dumpbin /headers "$outDir\d8.exe" | Select-String "machine"
    } finally {
        Pop-Location
    }
}

# ---------------------------------------------------------------------------
# 6. Run tests
# ---------------------------------------------------------------------------
Write-Step "Running ARM64EC test suites"

Push-Location $v8Dir
try {
    # Quick smoke test
    Write-Host "`n--- Smoke test ---"
    & "$outDir\d8.exe" -e "print('V8 ARM64EC is working: ' + typeof Promise)"
    if ($LASTEXITCODE -ne 0) { Write-Warning "Smoke test failed" }

    # Heap base unittests (fast, should be 100%)
    Write-Host "`n--- v8_heap_base_unittests ---"
    & "$outDir\v8_heap_base_unittests.exe"
    if ($LASTEXITCODE -ne 0) { Write-Warning "Heap base unittests had failures" }

    # V8 unittests via test runner (handles process isolation)
    Write-Host "`n--- unittests (quickcheck) ---"
    python3 tools/run-tests.py --outdir=$outDir --arch=arm64ec unittests `
        -j 4 --timeout=120 --quickcheck

    # CC tests via test runner
    Write-Host "`n--- cctest (quickcheck) ---"
    python3 tools/run-tests.py --outdir=$outDir --arch=arm64ec cctest `
        -j 4 --timeout=120 --quickcheck

    # JavaScript tests
    Write-Host "`n--- mjsunit (quickcheck) ---"
    python3 tools/run-tests.py --outdir=$outDir --arch=arm64ec mjsunit `
        -j 4 --timeout=120 --quickcheck

} finally {
    Pop-Location
}

Write-Step "Done"
Write-Host @"

Summary
-------
  V8 checkout:  $v8Dir
  Build output: $v8Dir\$outDir
  Branch:       $Branch
  d8 binary:    $v8Dir\$outDir\d8.exe

To rebuild after changes:
  cd $v8Dir
  ninja -C $outDir d8

To run a specific test:
  $v8Dir\$outDir\cctest.exe <test-name>
  python3 tools/run-tests.py --outdir=$outDir --arch=arm64ec cctest -j 4
"@
