#!/bin/bash
# 检查 libkaringbox.so 的未定义符号是否都可由 OHOS musl 提供
SO="${1:-/Users/admin/Work/karing-HM/harmony/entry/libs/arm64-v8a/libkaringbox.so}"
MUSL=/tmp/ohos-musl.so
NM=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native/llvm/bin/llvm-nm
if [ ! -f "$MUSL" ]; then echo "no musl"; exit 1; fi
$NM -D "$SO" 2>/dev/null | grep " U " | awk '{print $2}' | sort > /tmp/und.txt
$NM -D "$MUSL" 2>/dev/null | awk '{print $3}' | sort -u > /tmp/musl_syms.txt
echo "=== 缺失符号（so 引用但 musl 无导出）==="
comm -23 /tmp/und.txt /tmp/musl_syms.txt | head -30
echo "count: $(comm -23 /tmp/und.txt /tmp/musl_syms.txt | wc -l)"
