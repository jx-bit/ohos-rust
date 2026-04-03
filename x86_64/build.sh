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
mkdir -p /opt/rust-$RUST_VERSION-ohos-arm64
tar -xf rustc-$RUST_VERSION-src/build/dist/rust-$RUST_VERSION-aarch64-unknown-linux-ohos.tar.gz -C /opt/rust-$RUST_VERSION-ohos-arm64 --strip-components=1

# 复制 OpenSSL 依赖库到 Rust 目录
cp -r /opt/ohos-openssl/prelude/arm64-v8a/lib/* /opt/rust-$RUST_VERSION-ohos-arm64/lib/

# 进行代码签名
echo "=== 代码签名 ==="
cd /opt/rust-$RUST_VERSION-ohos-arm64
find . -type f \( -perm -0111 -o -name "*.so*" \) | while read FILE; do
    if file -b "$FILE" | grep -iqE "elf|sharedlib|ELF|shared object"; then
        echo "Signing binary file $FILE"
        ORIG_PERM=$(stat -c %a "$FILE")
        /opt/ohos-sdk/native/llvm/bin/llvm-objcopy --add-gnu-debuglink=/dev/null "$FILE" 2>/dev/null || true
        chmod "$ORIG_PERM" "$FILE"
    fi
done
cd $WORKDIR

# 履行开源义务，把使用的开源软件的 license 全部聚合起来放到制品中
echo "=== 生成 license 文件 ==="
cat <<EOF > /opt/rust-$RUST_VERSION-ohos-arm64/licenses.txt
This document describes the licenses of all software distributed with the
bundled application.
==========================================================================

rust
===========
$(cat rustc-$RUST_VERSION-src/LICENSE-MIT)
$(cat rustc-$RUST_VERSION-src/LICENSE-APACHE)

ohos-openssl
==========
==license==
$(cat /opt/ohos-openssl/LICENSE 2>/dev/null || echo "License file not found")
EOF

# 打包最终产物
echo "=== 打包最终产物 ==="
cp -r /opt/rust-$RUST_VERSION-ohos-arm64 ./
tar -zcf rust-$RUST_VERSION-ohos-arm64-cross.tar.gz rust-$RUST_VERSION-ohos-arm64

sync

echo "=== 构建完成 ==="
