#!/bin/bash
# karing-HM：sing-box 核心 OHOS 交叉编译脚本（GOOS=android 分支，绕开 IE TLS）
# 产物：harmony/entry/libs/arm64-v8a/libkaringbox.so + liblog.so + .h
set -e
export PATH="/opt/homebrew/bin:$PATH"
SRC="${1:-/Users/admin/Work/karing-sing-box}"
OUT_DIR="${2:-/Users/admin/Work/karing-HM/harmony/entry/libs/arm64-v8a}"
NDK="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native"
SYSROOT="$NDK/sysroot/usr/include"

export CC="$NDK/llvm/bin/aarch64-unknown-linux-ohos-clang"
export GOOS=android GOARCH=arm64 CGO_ENABLED=1
export CGO_CFLAGS="-I$SYSROOT -I$SYSROOT/aarch64-linux-ohos"
export CGO_LDFLAGS="-L$OUT_DIR -llog"

# liblog stub（OHOS 无 liblog.so，Go android 分支 cgo 需要）
cat > /tmp/liblog_stub.c <<'C_EOF'
#include <stdarg.h>
int __android_log_print(int prio, const char *tag, const char *fmt, ...) { return 0; }
int __android_log_vprint(int prio, const char *tag, const char *fmt, va_list ap) { return 0; }
int __android_log_write(int prio, const char *tag, const char *msg) { return 0; }
C_EOF
$CC -shared -o "$OUT_DIR/liblog.so" /tmp/liblog_stub.c

cd "$SRC"
go build -buildmode=c-shared \
  -tags "netgo osusergo with_gvisor with_quic with_wireguard with_utls with_clash_api" \
  -ldflags "-s -w" \
  -o "$OUT_DIR/libkaringbox.so" ./cmd/libkaringbox
echo "OK -> $OUT_DIR/libkaringbox.so ($(du -h "$OUT_DIR/libkaringbox.so" | cut -f1)) + liblog.so"
