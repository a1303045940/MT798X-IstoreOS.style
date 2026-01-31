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

echo "=========================================="
echo " 修复 Rust
echo "=========================================="

#!/bin/bash
# DIY Part 2 - 使用国内镜像下载 Rust

cd openwrt

# 获取 ImmortalWrt 版本和哈希
curl -fsSL \
  https://raw.githubusercontent.com/immortalwrt/packages/openwrt-24.10/lang/rust/Makefile \
  -o /tmp/rust-imm.mk

VER=$(grep '^PKG_VERSION:=' /tmp/rust-imm.mk | cut -d'=' -f2 | tr -d ' ')
HASH=$(grep '^PKG_HASH:=' /tmp/rust-imm.mk | cut -d'=' -f2 | tr -d ' ')

echo "需要下载 Rust $VER，哈希 $HASH"

# 更新本地 Makefile
sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$VER/" feeds/packages/lang/rust/Makefile
sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$HASH/" feeds/packages/lang/rust/Makefile

# 清理旧文件
rm -f dl/rustc-1.*-src.tar.xz*

# 🔥 关键：尝试多个镜像源
RUST_FILE="rustc-${VER}-src.tar.xz"
SUCCESS=0

# 镜像源列表（按速度排序）
MIRRORS=(
  "https://mirrors.ustc.edu.cn/rust-static/dist/${RUST_FILE}"      # 中科大
  "https://mirrors.tuna.tsinghua.edu.cn/rustup/dist/${RUST_FILE}"  # 清华
  "https://mirrors.cloud.tencent.com/rust-static/dist/${RUST_FILE}" # 腾讯
  "https://static.rust-lang.org/dist/${RUST_FILE}"                  # 官方
)

for MIRROR in "${MIRRORS[@]}"; do
  echo "尝试下载: $MIRROR"
  if wget --timeout=60 --tries=2 -O "dl/${RUST_FILE}.tmp" "$MIRROR" 2>/dev/null; then
    # 验证哈希
    DL_HASH=$(sha256sum "dl/${RUST_FILE}.tmp" | cut -d' ' -f1)
    if [ "$DL_HASH" = "$HASH" ]; then
      mv "dl/${RUST_FILE}.tmp" "dl/${RUST_FILE}"
      echo "✅ 下载成功: $MIRROR"
      SUCCESS=1
      break
    else
      echo "❌ 哈希不匹配，尝试下一个镜像"
      rm -f "dl/${RUST_FILE}.tmp"
    fi
  else
    echo "❌ 下载失败，尝试下一个镜像"
  fi
done

if [ "$SUCCESS" -ne 1 ]; then
  echo "所有镜像源都失败"
  exit 1
fi

rm -f /tmp/rust-imm.mk
echo "Rust $VER 准备完成"
echo "=========================================="
echo "Rust 修复完成"
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
