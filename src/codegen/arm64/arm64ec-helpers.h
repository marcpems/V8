// Copyright 2026 the V8 project authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ARM64EC ABI helpers for V8 JIT code generation.
//
// ARM64EC (Emulation Compatible) is an ABI that allows ARM64 code to
// interoperate with x64 code on Windows on ARM. When V8's JIT generates
// code targeting ARM64EC, the generated code runs natively as ARM64 but
// must follow specific calling conventions at EC boundaries.
//
// Key ARM64EC ABI requirements:
// - Entry thunks: When x64 code calls into JIT-generated ARM64 code,
//   an entry thunk must translate from x64 to ARM64 calling convention.
// - Exit thunks: When JIT ARM64 code calls back into x64 code, an exit
//   thunk must translate from ARM64 to x64 calling convention.
// - NEON registers q8-q15 are callee-saved under x64 ABI but only the
//   lower 64 bits (d8-d15) are callee-saved under ARM64.
//   At EC boundaries, all 128 bits of q8-q15 must be preserved.
// - The x18 register (platform register) must not be modified.
// - __os_arm64x_dispatch_call_no_redirect is used for calling x64 functions.
//
// For V8's purposes, most JIT-generated code calls are internal (ARM64 to
// ARM64), which need no thunks. Thunks are only needed at the boundary
// where V8's JIT code interfaces with the Windows runtime or external
// x64 libraries.

#ifndef V8_CODEGEN_ARM64_ARM64EC_HELPERS_H_
#define V8_CODEGEN_ARM64_ARM64EC_HELPERS_H_

#include "include/v8config.h"

#if defined(V8_TARGET_ARCH_ARM64EC)

#include "src/common/globals.h"

namespace v8 {
namespace internal {

// ARM64EC ABI constants.
// Under ARM64EC, the following additional NEON registers must be saved
// at external call boundaries (the full 128-bit q8-q15, not just d8-d15).
constexpr int kArm64ECExtraFpCalleeSavedSize = 8 * 8;  // 8 regs * 8 extra bytes

// Check whether a given external reference requires an EC exit thunk.
// Internal V8 calls between JIT-compiled code don't need thunks since
// they're all ARM64 native.
inline bool NeedsArm64ECExitThunk(Address target) {
  // TODO(nickg): Implement proper detection of x64 targets.
  // For now, all internal V8 calls are ARM64 native and don't need thunks.
  // External function pointers from the OS or loaded DLLs may need thunks,
  // but the Windows kernel handles this transparently through the EC
  // function dispatch mechanism.
  return false;
}

// ARM64EC entry thunk helpers.
// When a JIT'd function can potentially be called from x64 code,
// it needs an entry thunk that the Windows loader can register.
// For V8, this typically only applies to callback functions that are
// passed to external x64 APIs.
//
// The Windows kernel provides __os_arm64x_dispatch_call_no_redirect
// for calling x64 functions from ARM64EC code. V8's runtime uses this
// via the standard C/C++ calling mechanism (the compiler handles it).

}  // namespace internal
}  // namespace v8

#endif  // V8_TARGET_ARCH_ARM64EC

#endif  // V8_CODEGEN_ARM64_ARM64EC_HELPERS_H_
