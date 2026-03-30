# V8 ARM64EC Build Setup

Automated setup script for building and testing V8 on Windows ARM64EC.

## Prerequisites

- **Windows 11 on ARM** (ARM64 device)
- **Visual Studio 2022+** with the **ARM64/ARM64EC build tools** workload
- An **elevated PowerShell** prompt (Run as Administrator)

The script will install any missing tools (Git, Python 3, depot\_tools)
automatically. If Visual Studio is not detected it will print install
instructions and exit.

## Quick Start

```powershell
# Clone the fork and run the setup script
git clone https://github.com/marcpems/v8.git v8-setup
cd v8-setup
git checkout marcpe_Arm64EC_experimental

# Run the full setup (elevated PowerShell)
.\tools\arm64ec\setup-and-build.ps1
```

This will:

1. Install prerequisites (Git, Python 3, depot\_tools).
2. Fetch V8 and all dependencies via `fetch v8` / `gclient sync`.
3. Check out the `marcpe_Arm64EC_experimental` branch.
4. Apply ARM64EC patches to third-party submodules.
5. Generate the GN build configuration.
6. Build `d8`, `v8`, and test executables.
7. Run smoke tests, unit tests, cctests, and mjsunit.

## Script Options

| Flag | Description |
|------|-------------|
| `-WorkDir <path>` | Root directory for the checkout (default: `C:\v8-dev`) |
| `-SkipPrereqs` | Skip prerequisite installation |
| `-SkipFetch` | Skip `fetch v8` / `gclient sync` (use existing checkout) |
| `-BuildOnly` | Only generate + build; skip prereqs and fetch |
| `-TestOnly` | Only run tests; assumes a build already exists |

### Examples

```powershell
# Full setup in a custom directory
.\setup-and-build.ps1 -WorkDir D:\my-v8

# Already have prereqs installed
.\setup-and-build.ps1 -SkipPrereqs

# Rebuild after code changes
.\setup-and-build.ps1 -BuildOnly

# Re-run tests without rebuilding
.\setup-and-build.ps1 -TestOnly
```

## Manual Build Steps

If you prefer to run each step yourself:

```powershell
# 1. Set environment
$env:DEPOT_TOOLS_WIN_TOOLCHAIN = "0"

# 2. Fetch (one-time)
mkdir C:\v8-dev; cd C:\v8-dev
fetch v8
gclient sync -D

# 3. Checkout branch
cd v8
git remote add marcpems https://github.com/marcpems/v8.git
git fetch marcpems marcpe_Arm64EC_experimental
git checkout marcpe_Arm64EC_experimental

# 4. Apply patches
git -C build apply patches\arm64ec\build.patch
git -C third_party\abseil-cpp apply patches\arm64ec\abseil-cpp.patch
git -C third_party\fp16\src apply patches\arm64ec\fp16.patch
git -C third_party\highway\src apply patches\arm64ec\highway.patch
git -C third_party\dragonbox\src apply patches\arm64ec\dragonbox.patch
git -C third_party\libc++\src apply patches\arm64ec\libcxx.patch
git -C third_party\protobuf apply patches\arm64ec\protobuf.patch

# 5. Generate + Build
gn gen out\arm64ec --args="target_cpu=""arm64ec"" target_os=""win"" is_clang=true v8_control_flow_integrity=false use_lld=false is_component_build=false enable_rust=false"
ninja -C out\arm64ec d8

# 6. Test
.\out\arm64ec\d8.exe -e "print('hello from arm64ec')"
python3 tools/run-tests.py --outdir=out/arm64ec --arch=arm64ec unittests -j 4 --quickcheck
```

## What the Patches Fix

The ARM64EC compiler (`--target=arm64ec-pc-windows-msvc`) defines both
`__x86_64__` and ARM64 macros. Several third-party libraries use `__x86_64__`
to gate x86-specific inline assembly or intrinsics, which then fails to
compile on ARM64EC. The patches exclude ARM64EC from these x86 code paths.

| Patch | Library | Issue Fixed |
|-------|---------|-------------|
| `build.patch` | Chromium build system | Toolchain, clang target triple, `/MACHINE:ARM64EC`, environment files |
| `abseil-cpp.patch` | Abseil | `rdtsc` asm, `prefetchw` asm, `__cpuid`, architecture detection |
| `fp16.patch` | FP16 | `immintrin.h` / `x86intrin.h` includes, `_castu32_f32` intrinsics |
| `highway.patch` | Highway SIMD | `HWY_ARCH_X86_64` dual-architecture detection |
| `dragonbox.patch` | Dragonbox | `_addcarry_u64` intrinsic |
| `libcxx.patch` | libc++ | `_umul128` / `__shiftright128` intrinsics in Ryu |
| `protobuf.patch` | Protobuf | `btc` x86 inline assembly |

## Test Results (Expected)

| Suite | Pass Rate | Notes |
|-------|-----------|-------|
| `v8_heap_base_unittests` | 100% | Core heap infrastructure |
| `unittests` | ~99% | JIT codegen tests may crash |
| `cctest` | ~95% | Branch-combine and atomic codegen tests crash |
| `mjsunit` | ~89% | JS execution; JIT-generated code issues |

Failures are concentrated in JIT code-generation tests that emit native
instructions — these require further ARM64EC ABI adaptation in V8's
compiler backends.

## Troubleshooting

**`gclient sync` fails with 401 / GCS auth error**
Set `$env:DEPOT_TOOLS_WIN_TOOLCHAIN = "0"` to use your local Visual Studio
instead of downloading the toolchain from Google Cloud Storage.

**`gn gen` fails with "Undefined identifier arm64ec"**
Ensure you are on the `marcpe_Arm64EC_experimental` branch and that
the `build.patch` has been applied to the `build/` submodule.

**Link error LNK4279 treated as error**
The `build.patch` adds `/IGNORE:4279` to suppress ARM64EC thunk mismatch
warnings. Re-apply the patch if you see this.

**Missing `environment.arm64` file at build time**
Run `gclient sync -D` with `DEPOT_TOOLS_WIN_TOOLCHAIN=0` to regenerate
the MSVC environment files.
