#!/bin/sh
set -e

WORKDIR=$(pwd)
RUST_VERSION="1.89.0"

# ========================================
# 构建选项（可通过环境变量覆盖）
# ========================================
# DRY_RUN: 跳过编译，生成模拟产物测试流程
DRY_RUN=${DRY_RUN:-false}

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

if [ "$DRY_RUN" = "true" ]; then
    echo ">>> [DRY RUN MODE] 跳过编译，生成模拟产物"
    
    # DRY RUN 逻辑：生成模拟文件
    cd $WORKDIR
    
    # 关键修复：必须显式创建 build/dist 目录，因为 x.py dist 被跳过了
    BUILD_DIST="$WORKDIR/rustc-$RUST_VERSION-src/build/dist"
    MOCK_DIR="$BUILD_DIST/mock-install"
    TARGET_NAME="rust-$RUST_VERSION-aarch64-unknown-linux-ohos"
    TARGET_DIR="$BUILD_DIST/$TARGET_NAME"

    # 清理旧目录
    rm -rf "$MOCK_DIR" "$TARGET_DIR"

    echo "创建目录: $MOCK_DIR"
    mkdir -p "$BUILD_DIST"
    mkdir -p "$MOCK_DIR/bin"
    mkdir -p "$MOCK_DIR/lib"
    mkdir -p "$MOCK_DIR/lib/rustlib/aarch64-unknown-linux-ohos/bin"

    echo "复制模拟二进制文件..."
    cp /bin/ls "$MOCK_DIR/bin/cargo"
    cp /bin/ls "$MOCK_DIR/bin/rustc"
    cp /bin/ls "$MOCK_DIR/bin/rustfmt"
    cp /bin/ls "$MOCK_DIR/bin/clippy-driver"
    cp /bin/ls "$MOCK_DIR/lib/libtest.so"
    cp /bin/ls "$MOCK_DIR/lib/rustlib/aarch64-unknown-linux-ohos/bin/rust-lld"

    echo "打包模拟产物..."
    # 重命名目录
    mv "$MOCK_DIR" "$TARGET_DIR"

    # 生成模拟 install.sh
    cat > "$TARGET_DIR/install.sh" << 'EOF'
#!/bin/sh
# 模拟安装脚本，将 bin/lib 目录拷贝到 --prefix 指定的位置
PREFIX=""
for arg in "$@"; do
    case "$arg" in
        --prefix=*) PREFIX="${arg#*=}" ;;
    esac
done

if [ -n "$PREFIX" ]; then
    echo "Mock installing to $PREFIX..."
    mkdir -p "$PREFIX/bin" "$PREFIX/lib"
    cp -r bin/* "$PREFIX/bin/" 2>/dev/null || true
    cp -r lib/* "$PREFIX/lib/" 2>/dev/null || true
    echo "Mock installation complete."
fi
EOF
    chmod +x "$TARGET_DIR/install.sh"

    # 打包
    cd "$BUILD_DIST"
    tar -czf "$TARGET_NAME.tar.gz" "$TARGET_NAME"
    ls -lh "$TARGET_NAME.tar.gz"
    cd $WORKDIR
    
    echo "模拟产物已生成"
else
    echo ">>> [FULL BUILD MODE] 执行真实编译"

    # 步骤 1: 跳过 make prepare（OHOS 不是官方支持的平台）
    # make prepare  # OHOS 没有官方预构建工具链，跳过此步骤

    # 步骤 2: 启动 sccache
    echo "=== 启动 sccache 服务器 ==="
    SCCACHE_IDLE_TIMEOUT=10800 sccache --start-server || true

    # 步骤 3: 运行构建脚本
    echo "=== 运行官方构建脚本 ==="
    echo "=== SCRIPT: python3 ../x.py dist --host=$TARGETS --target $TARGETS ==="
    python3 x.py dist --host=$TARGETS --target $TARGETS -j$(nproc)

    # 步骤 4: 显示 sccache 统计信息
    echo "=== 显示 sccache 统计信息 ==="
    sccache --show-adv-stats || true
fi

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

# 直接安装到指定路径（扁平结构）
sh install.sh --prefix="$RUST_INSTALL_DIR" --verbose

echo "=== 产物位置: $RUST_INSTALL_DIR ==="
ls -la "$RUST_INSTALL_DIR/" || echo "目录不存在"

echo "=== 复制 OpenSSL 依赖库 ==="
mkdir -p "$RUST_INSTALL_DIR/lib"
cp -r /opt/ohos-openssl/prelude/arm64-v8a/lib/* "$RUST_INSTALL_DIR/lib/" 2>/dev/null || true

# 进行代码签名
echo "=== 代码签名 ==="
cd "$RUST_INSTALL_DIR"

SIGN_TOOL="/opt/ohos-sdk/linux/toolchains/lib/binary-sign-tool"
if [ ! -f "$SIGN_TOOL" ]; then
    echo "✗ 签名工具不存在: $SIGN_TOOL"
    exit 1
fi

chmod +x "$SIGN_TOOL"
echo "使用签名工具: $SIGN_TOOL"

find . -type f | while read -r FILE; do
    if file -b "$FILE" | grep -qiE "elf"; then
        echo "Signing: $FILE"
        ORIG_PERM=$(stat -c %a "$FILE")
        chmod +w "$FILE"

        SIGNED_TMP="${FILE}.signed"
        if "$SIGN_TOOL" sign -inFile "$FILE" -outFile "$SIGNED_TMP" -selfSign 1; then
            mv "$SIGNED_TMP" "$FILE"
            chmod "$ORIG_PERM" "$FILE"
        else
            echo "✗ Failed to sign: $FILE"
            rm -f "$SIGNED_TMP"
            exit 1
        fi
    fi
done
[ $? -ne 0 ] && exit 1
cd $WORKDIR

# 履行开源义务
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
FINAL_DIR="$WORKDIR/rust-$RUST_VERSION-aarch64-unknown-linux-ohos"
rm -rf "$FINAL_DIR"

# 直接复制安装目录
cp -r "$RUST_INSTALL_DIR" "$FINAL_DIR"

# 将签名工具打包进去
mkdir -p "$FINAL_DIR/tool"
cp $WORKDIR/tool/binary-sign-tool "$FINAL_DIR/tool/"

tar -zcf rust-$RUST_VERSION-aarch64-unknown-linux-ohos.tar.gz rust-$RUST_VERSION-aarch64-unknown-linux-ohos

sync

echo "=== 构建完成 ==="
echo ""
echo "构建选项汇总:"
echo "  DRY_RUN: $DRY_RUN"
echo ""
echo "产物位置: $WORKDIR/rust-$RUST_VERSION-aarch64-unknown-linux-ohos.tar.gz"
ls -lh rust-$RUST_VERSION-aarch64-unknown-linux-ohos.tar.gz