#!/bin/sh
set -e

WORKDIR=$(pwd)
RUST_VERSION="1.89.0"

# 如果存在旧的目录和文件，就清理掉
rm -rf *.tar.gz \
    *.tgz \
    deps \
    rustc-* \
    rust-$RUST_VERSION-ohos-arm64

# ========================================
# 下载 Rust 源码
# ========================================
echo "=== 下载 Rust 源码 ==="
curl -fLO https://static.rust-lang.org/dist/rustc-$RUST_VERSION-src.tar.gz
tar -zxf rustc-$RUST_VERSION-src.tar.gz
cd rustc-$RUST_VERSION-src

# ========================================
# 应用 patches
# ========================================
echo "=== 应用 patches ==="
patch -p1 < $WORKDIR/patches/0001-rustc-ohos-auto-sign-fix-1.89.0.patch

# ========================================
# 完全模拟官方 CI 的 configure 步骤
# 参考：src/ci/docker/host-x86_64/dist-ohos-aarch64/Dockerfile
# ========================================
echo "=== 配置 Rust 构建 ==="
./configure \
    --enable-profiler \
    --disable-docs \
    --tools=cargo,clippy,rustdocs,rustfmt,rust-analyzer,rust-analyzer-proc-macro-srv,analysis,src,wasm-component-ld \
    --enable-extended \
    --enable-sanitizers

# ========================================
# 完全模拟官方 CI 的构建步骤
# 参考：src/ci/docker/host-x86_64/dist-ohos-aarch64/Dockerfile
# ========================================

# 步骤 1: 跳过 make prepare（OHOS 不是官方支持的平台）
echo "=== 跳过 make prepare（OHOS 没有预构建工具链）==="
# make prepare  # OHOS 没有官方预构建工具链，跳过此步骤

# 步骤 2: 启动 sccache
echo "=== 启动 sccache 服务器 ==="
SCCACHE_IDLE_TIMEOUT=10800 sccache --start-server || true

# 步骤 3: 运行构建脚本（完全模拟官方 Dockerfile 的 SCRIPT）
echo "=== 运行官方构建脚本 ==="
echo "=== SCRIPT: python3 ../x.py dist --host=$TARGETS --target $TARGETS ==="

# ========================================
# 完全模拟官方 CI 的构建命令
# 参考：src/ci/docker/host-x86_64/dist-ohos-aarch64/Dockerfile
# SCRIPT: python3 ../x.py dist --host=$TARGETS --target $TARGETS
# ========================================
python3 x.py dist --host=$TARGETS --target $TARGETS -j$(nproc)

# 步骤 4: 显示 sccache 统计信息
echo "=== 显示 sccache 统计信息 ==="
sccache --show-adv-stats || true

cd $WORKDIR

# ========================================
# 提取主要的 Rust 分发包
# ========================================
echo "=== 提取 Rust 分发包 ==="
echo "=== 检查构建产物 ==="
ls -la rustc-$RUST_VERSION-src/build/dist/ || echo "dist 目录不存在"
echo "=== 查找 tar.gz 文件 ==="
find rustc-$RUST_VERSION-src/build/dist/ -name "*.tar.gz" || echo "没有找到 tar.gz 文件"

# 调用 install.sh 安装到临时目录
echo "RUST_INSTALL_DIR=/tmp/rust-install"
export RUST_INSTALL_DIR="/tmp/rust-install"
rm -rf "$RUST_INSTALL_DIR"
mkdir -p "$RUST_INSTALL_DIR"

echo "===RUST_INSTALL_DIR 安装 rustc ==="
cd rustc-$RUST_VERSION-src/build/dist/
tar -zxf rust-$RUST_VERSION-aarch64-unknown-linux-ohos.tar.gz
cd rust-$RUST_VERSION-aarch64-unknown-linux-ohos

# - --prefix=/opt/rust → 安装到 /opt/rust/bin, /opt/rust/lib 等
# - --destdir=/tmp/rust-install → 安装到 /tmp/rust-install/usr/local/bin, /tmp/rust-install/usr/local/lib 等（保持原有的 /usr/local 结构）
sh install.sh --destdir="$RUST_INSTALL_DIR" --verbose

echo "=== 复制 OpenSSL 依赖库到安装目录 ==="
mkdir -p "$RUST_INSTALL_DIR/usr/local/lib"
cp -r /opt/ohos-openssl/prelude/arm64-v8a/lib/* "$RUST_INSTALL_DIR/usr/local/lib/" 2>/dev/null || true

# 进行代码签名
echo "=== 代码签名 ==="
cd "$RUST_INSTALL_DIR"
find . -type f \( -perm -0111 -o -name "*.so*" \) | while read FILE; do
    if file -b "$FILE" | grep -iqE "elf|sharedlib|ELF|shared object"; then
        echo "Signing binary file $FILE"
        ORIG_PERM=$(stat -c %a "$FILE")
        if /opt/ohos-sdk/ohos/toolchains/lib/binary-sign-tool sign -inFile "$FILE" -outFile "$FILE" -selfSign 1; then
            echo "✓ Signed successfully: $FILE"
        else
            echo "✗ Signing failed (non-critical): $FILE"
        fi
        chmod "$ORIG_PERM" "$FILE"
    fi
done
cd $WORKDIR

# 履行开源义务，把使用的开源软件的 license 全部聚合起来放到制品中
echo "=== 生成 license 文件 ==="
cat <<EOF > "$RUST_INSTALL_DIR/licenses.txt"
This document describes the licenses of all software distributed with the
bundled application.
==========================================================================

rust
==========
$(cat rustc-$RUST_VERSION-src/LICENSE-MIT)
$(cat rustc-$RUST_VERSION-src/LICENSE-APACHE)

ohos-openssl
==========
==license==
$(cat /opt/ohos-openssl/LICENSE 2>/dev/null || echo "License file not found")
EOF

# 打包最终产物
echo "=== 打包最终产物 ==="
cp -r "$RUST_INSTALL_DIR" ./rust-$RUST_VERSION-ohos-arm64
tar -zcf rust-$RUST_VERSION-ohos-arm64-cross.tar.gz rust-$RUST_VERSION-ohos-arm64

sync

echo "=== 构建完成 ==="
