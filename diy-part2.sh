#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#


#
# DIY Part 2 - 修复Rust版本并预下载
#
set -e

echo "=========================================="
echo "DIY Part 2: Fix Rust Version"
echo "=========================================="

cd "$(dirname "$0")" || exit 1
echo "Current dir: $(pwd)"

# ==========================================
# 1. Get ImmortalWrt official Rust config
# ==========================================
echo ">>> Getting ImmortalWrt Rust config..."

IMM_URL="https://raw.githubusercontent.com/immortalwrt/packages/openwrt-24.10/lang/rust/Makefile"
TMP_MK="/tmp/rust_imm.mk"

curl -fsSL "$IMM_URL" -o "$TMP_MK" || {
    echo "ERROR: Failed to download $IMM_URL"
    exit 1
}

# Extract version and hash
RUST_VER=$(grep '^PKG_VERSION:=' "$TMP_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
RUST_HASH=$(grep '^PKG_HASH:=' "$TMP_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')

if [ -z "$RUST_VER" ] || [ -z "$RUST_HASH" ]; then
    echo "ERROR: Failed to parse version or hash"
    cat "$TMP_MK" | head -20
    exit 1
fi

echo "Target version: $RUST_VER"
echo "Target hash: ${RUST_HASH:0:16}..."

# ==========================================
# 2. Update local Makefile
# ==========================================
echo ">>> Updating local Rust Makefile..."

RUST_MK="feeds/packages/lang/rust/Makefile"

if [ ! -f "$RUST_MK" ]; then
    echo "ERROR: Not found: $RUST_MK"
    exit 1
fi

cp "$RUST_MK" "$RUST_MK.bak"

# Replace version and hash
sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$RUST_VER/" "$RUST_MK"
sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$RUST_HASH/" "$RUST_MK"

# Fix URL (remove trailing spaces, use official)
sed -i 's|^PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://static.rust-lang.org/dist/|' "$RUST_MK"
sed -i 's/[[:space:]]*$//' "$RUST_MK"

echo "Updated to: $RUST_VER"

# ==========================================
# 3. Pre-download Rust with mirror fallback
# ==========================================
echo ">>> Pre-downloading Rust $RUST_VER..."

RUST_FILE="rustc-${RUST_VER}-src.tar.xz"
DL_PATH="dl/$RUST_FILE"
SUCCESS=0

# Create dl dir
mkdir -p dl

# Check if already exists and valid
if [ -f "$DL_PATH" ]; then
    echo "File exists, verifying hash..."
    LOCAL_HASH=$(sha256sum "$DL_PATH" | cut -d' ' -f1)
    if [ "$LOCAL_HASH" = "$RUST_HASH" ]; then
        echo "Hash matched, using cached file"
        SUCCESS=1
    else
        echo "Hash mismatch, re-downloading..."
        rm -f "$DL_PATH"
    fi
fi

# Download if needed
if [ "$SUCCESS" -eq 0 ]; then
    # Mirror list
    MIRRORS=(
        "https://mirrors.ustc.edu.cn/rust-static/dist/${RUST_FILE}"
        "https://mirrors.tuna.tsinghua.edu.cn/rustup/dist/${RUST_FILE}"
        "https://static.rust-lang.org/dist/${RUST_FILE}"
    )
    
    for mirror in "${MIRRORS[@]}"; do
        echo "Trying mirror: $mirror"
        
        # Download with timeout
        if wget --timeout=120 -O "${DL_PATH}.tmp" "$mirror" 2>/dev/null || \
           curl -fsSL --connect-timeout 120 -o "${DL_PATH}.tmp" "$mirror" 2>/dev/null; then
            
            # Verify hash
            DL_HASH=$(sha256sum "${DL_PATH}.tmp" | cut -d' ' -f1)
            
            if [ "$DL_HASH" = "$RUST_HASH" ]; then
                mv "${DL_PATH}.tmp" "$DL_PATH"
                echo "Download success from: $mirror"
                SUCCESS=1
                break
            else
                echo "Hash mismatch, trying next mirror..."
                rm -f "${DL_PATH}.tmp"
            fi
        else
            echo "Download failed from this mirror"
        fi
    done
fi

# Check final result
if [ "$SUCCESS" -ne 1 ]; then
    echo "ERROR: All mirrors failed for Rust $RUST_VER"
    exit 1
fi

echo "Rust $RUST_VER ready at: $DL_PATH"

# ==========================================
# 4. Fix ci-llvm if needed
# ==========================================
echo ">>> Checking ci-llvm setting..."

if grep -q "download-ci-llvm=true" "$RUST_MK"; then
    echo "Current: ci-llvm=true (using prebuilt LLVM)"
    echo "To build LLVM from source (more compatible but slower), uncomment below:"
    # sed -i 's/download-ci-llvm=true/download-ci-llvm=false/g' "$RUST_MK"
fi

# Cleanup
rm -f "$TMP_MK"

echo "=========================================="
echo "Rust fix completed: $RUST_VER"
echo "=========================================="
# =========================================================
# 智能修复脚本（兼容 package/ 和 feeds/）
# =========================================================

REPO_ROOT=$(dirname "$(readlink -f "$0")")
CUSTOM_LUA="$REPO_ROOT/istore/istore_backend.lua"

echo "Debug: Repo root is $REPO_ROOT"

# 1. 优先查找 package 目录
TARGET_LUA=$(find package -name "istore_backend.lua" -type f 2>/dev/null)

# 2. 如果 package 中没找到，再查找 feeds
if [ -z "$TARGET_LUA" ]; then
    echo "Not found in package/, searching in feeds/..."
    TARGET_LUA=$(find feeds -name "istore_backend.lua" -type f 2>/dev/null)
fi

# 3. 执行覆盖（逻辑与原脚本相同）
if [ -n "$TARGET_LUA" ]; then
    echo "Found target file: $TARGET_LUA"
    if [ -f "$CUSTOM_LUA" ]; then
        echo "Overwriting with custom file..."
        cp -f "$CUSTOM_LUA" "$TARGET_LUA"
        if cmp -s "$CUSTOM_LUA" "$TARGET_LUA"; then
             echo "✅ Overwrite Success! Files match."
        else
             echo "❌ Error: Copy failed or files do not match."
        fi
    else
        echo "❌ Error: Custom file ($CUSTOM_LUA) not found!"
        ls -l "$REPO_ROOT/istore" 2>/dev/null || echo "Directory not found"
    fi
else
    echo "❌ Error: istore_backend.lua not found in package/ or feeds/!"
fi

#修复DiskMan编译失败
DM_FILE="./luci-app-diskman/applications/luci-app-diskman/Makefile"
if [ -f "$DM_FILE" ]; then
	echo " "

	sed -i '/ntfs-3g-utils /d' $DM_FILE

	cd $PKG_PATH && echo "diskman has been fixed!"
fi

# 修复 libxcrypt 编译报错
# 给 configure 脚本添加 --disable-werror 参数，忽略警告
sed -i 's/CONFIGURE_ARGS +=/CONFIGURE_ARGS += --disable-werror/' feeds/packages/libs/libxcrypt/Makefile

# 自定义默认网关，后方的192.168.30.1即是可自定义的部分
sed -i 's/192.168.[0-9]*.[0-9]*/192.168.30.1/g' package/base-files/files/bin/config_generate

# 自定义主机名
#sed -i "s/hostname='ImmortalWrt'/hostname='360T7'/g" package/base-files/files/bin/config_generate

# 固件版本名称自定义
#sed -i "s/DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION='OpenWrt By gino $(date +"%Y%m%d")'/g" package/base-files/files/etc/openwrt_release

# 取消原主题luci-theme-bootstrap 为默认主题
# sed -i '/set luci.main.mediaurlbase=\/luci-static\/bootstrap/d' feeds/luci/themes/luci-theme-bootstrap/root/etc/uci-defaults/30_luci-theme-bootstrap

# 删除原默认主题
# rm -rf package/lean/luci-theme-bootstrap

# 修改 argon 为默认主题
# sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile
sed -i "s/luci-theme-bootstrap/luci-theme-argon/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
