# Building V8 for Windows ARM64EC

This document describes how to build V8 targeting the Windows ARM64EC ABI.

## Overview

ARM64EC (Emulation Compatible) is a Windows ABI that allows native ARM64 code
to interoperate seamlessly with x64 code running under emulation on Windows on
ARM. V8 built for ARM64EC generates native ARM64 machine code for maximum
performance while being loadable by x64 processes.

## Prerequisites

- Visual Studio 2022 (17.3+) with ARM64EC support
- Windows 11 on ARM (for testing)
- Clang (from depot_tools or standalone)
- Standard V8 build dependencies (depot_tools, python3, etc.)

## Quick Start

```bash
# From the V8 checkout directory:
gn gen out/arm64ec --args='target_cpu="arm64ec" target_os="win" is_clang=true v8_control_flow_integrity=false'
ninja -C out/arm64ec d8
```

Or use the provided args file:

```bash
gn gen out/arm64ec --args='import("//gni/arm64ec.gni")'
ninja -C out/arm64ec d8
```

## How It Works

### Build System
- `target_cpu="arm64ec"` is recognized as a valid target alongside x64, arm64, etc.
- Clang-cl compiles with `--target=arm64ec-windows-msvc`, producing native ARM64 code
- MSVC `link.exe` is used for linking (lld-link does not support ARM64EC)
- The `/MACHINE:ARM64EC` linker flag is set automatically

### Code Generation
- V8's JIT compiler generates ARM64 instructions natively (same codegen as arm64)
- All ARM64 assembler, macro-assembler, and backend sources are reused
- An additional `V8_TARGET_ARCH_ARM64EC` define enables EC-specific behavior

### Key Differences from ARM64
1. **No Pointer Authentication (PAC)**: ARM64EC does not support PAC instructions.
   `v8_control_flow_integrity` must be set to `false`.
2. **Linker**: MSVC `link.exe` is required; lld-link is not supported.
3. **ABI Boundaries**: At transitions between ARM64EC code and x64 emulated code,
   the Windows kernel handles calling convention translation automatically.
4. **NEON**: NEON instructions work natively. At EC boundaries, the kernel
   preserves full 128-bit NEON register state.

### Architecture Detection
- `V8_TARGET_ARCH_ARM64` is always defined (ARM64EC is a superset of ARM64)
- `V8_TARGET_ARCH_ARM64EC` is additionally defined
- `V8_HOST_ARCH_ARM64` is always defined
- `V8_HOST_ARCH_ARM64EC` is additionally defined
- MSVC defines `_M_ARM64EC` (checked before `_M_AMD64`)

## Troubleshooting

### Link errors with lld-link
Ensure you are not forcing `use_lld=true`. The build system automatically
selects MSVC `link.exe` for ARM64EC targets.

### PAC/BTI instruction errors
Set `v8_control_flow_integrity=false` in your build args. ARM64EC does not
support pointer authentication instructions.

### Missing toolchain data
Ensure your Visual Studio installation includes the ARM64EC workload
(part of the ARM64 build tools).
