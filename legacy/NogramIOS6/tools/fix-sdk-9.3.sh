#!/bin/sh
# Prepares theos/sdks' iPhoneOS9.3.sdk for linking iOS 6 (armv7) binaries.
#
# It is the theos SDK to use for armv7: its .tbd files still list the
# armv7-only symbols (objc_msgSend_stret, _Unwind_SjLj_*, __modsi3), which the
# 10.3 one lacks. It has two gaps a current ld64 trips over:
#
#  1. libSystem.tbd re-exports /usr/lib/system/liblaunch.dylib, but the SDK
#     ships no stub for it ("file not found: liblaunch.dylib").
#  2. libsystem_c.tbd does not list memcpy/memmove/memset, which clang emits
#     for struct copies and zeroing. On device they resolve through the
#     libSystem umbrella whichever sub-library exports them (libsystem_c on
#     iOS 6, libsystem_platform later), so listing them here is correct.
#
# The "linking in .tbd file ... built for iOS Simulator" warnings that remain
# are harmless: ld64 reads these v1 stubs, which also list i386/x86_64, as
# Simulator ones, but still resolves the armv7 symbols from them.
#
# Idempotent. Run once after copying the SDK into $THEOS/sdks.
set -e
SDK="${THEOS:?set THEOS}/sdks/iPhoneOS9.3.sdk"
[ -d "$SDK" ] || { echo "no SDK at $SDK"; exit 1; }

STUB="$SDK/usr/lib/system/liblaunch.tbd"
if [ ! -f "$STUB" ]; then
cat > "$STUB" <<'TBD'
---
archs:           [ armv7, armv7s, arm64, i386, x86_64 ]
platform:        ios
install-name:    /usr/lib/system/liblaunch.dylib
current-version: 765.1.2
compatibility-version: 1
exports:
  - archs:       [ armv7, armv7s, arm64, i386, x86_64 ]
    symbols:     [ _launch_data_alloc, _launch_data_free, _launch_msg ]
...
TBD
fi

LIBC="$SDK/usr/lib/system/libsystem_c.tbd"
if ! grep -q ' _memcpy,' "$LIBC"; then
    sed -i.bak 's/___memcpy_chk,/_memcpy, _memmove, _memset, ___memcpy_chk,/' "$LIBC" && rm -f "$LIBC.bak"
fi
echo "patched $SDK"
