FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    g++ \
    make \
    ninja-build \
    file \
    curl \
    ca-certificates \
    python3 \
    git \
    cmake \
    sudo \
    gdb \
    libssl-dev \
    pkg-config \
    xz-utils \
    unzip \
    patch \
    && rm -rf /var/lib/apt/lists/*

# Fix git safe directory for CI
RUN git config --global --add safe.directory /workspace

COPY x86_64/scripts/ohos-sdk.sh /scripts/
RUN sh /scripts/ohos-sdk.sh

COPY x86_64/scripts/ohos-openssl.sh /scripts/
RUN sh /scripts/ohos-openssl.sh

COPY x86_64/scripts/ohos/aarch64-unknown-linux-ohos-clang.sh /usr/local/bin/
COPY x86_64/scripts/ohos/aarch64-unknown-linux-ohos-clang++.sh /usr/local/bin/

# env
# OPENSSL_DIR: 指定 OHOS OpenSSL 预编译库路径
ENV AARCH64_UNKNOWN_LINUX_OHOS_OPENSSL_DIR=/opt/ohos-openssl/prelude/arm64-v8a

# OPENSSL_NO_VENDOR=1: 禁用 openssl-src vendored 模式，使用预编译的 ohos-openssl
ENV AARCH64_UNKNOWN_LINUX_OHOS_OPENSSL_NO_VENDOR=1

# OPENSSL_STATIC=1: 强制静态链接 OpenSSL (使用 libssl.a/libcrypto.a)
# 注: openssl-sys 支持 TARGET_OPENSSL_STATIC 格式，仅对交叉编译目标生效
ENV AARCH64_UNKNOWN_LINUX_OHOS_OPENSSL_STATIC=1

ENV TARGETS=aarch64-unknown-linux-ohos

ENV \
    CC_aarch64_unknown_linux_ohos=/usr/local/bin/aarch64-unknown-linux-ohos-clang.sh \
    AR_aarch64_unknown_linux_ohos=/opt/ohos-sdk/native/llvm/bin/llvm-ar \
    CXX_aarch64_unknown_linux_ohos=/usr/local/bin/aarch64-unknown-linux-ohos-clang++.sh

# 注: RUST_CONFIGURE_ARGS 已删除，实际配置参数由 build.sh 的 ./configure 直接传递
# 官方 CI 通过 src/ci/run.sh 读取此变量，但 ohos-rust 的 build.sh 是独立脚本

ENV SCRIPT="python3 ../x.py dist --host=$TARGETS --target $TARGETS"

COPY x86_64/scripts/sccache.sh /scripts/
RUN sh /scripts/sccache.sh
