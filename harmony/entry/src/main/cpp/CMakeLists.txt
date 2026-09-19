# karing-HM VPN 数据面 NDK 构建
cmake_minimum_required(VERSION 3.5.0)
project(karing_vpn)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

include_directories(${NATIVERENDER_ROOT_PATH})

add_library(karing_vpn SHARED vpn_tun.cpp)
target_link_libraries(karing_vpn PUBLIC libace_napi.z.so libhilog_ndk.z.so libc++_shared.so)

# sing-box 核心桥（dlopen 加载 libkaringbox_core.so）
add_library(karingbox SHARED karingbox_napi.cpp)
target_link_libraries(karingbox PUBLIC libace_napi.z.so libhilog_ndk.z.so dl)
