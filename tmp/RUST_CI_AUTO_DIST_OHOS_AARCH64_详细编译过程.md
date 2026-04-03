# Rust 官方 CI Auto 阶段 dist-ohos-aarch64 详细编译过程文档

## 文档概述

本文档详细描述了 Rust 官方 CI 系统中 Auto 阶段 `dist-ohos-aarch64` 任务的完整编译过程。该任务负责构建完整的 Rust 工具链发行版，目标是 OpenHarmony (OhOS) aarch64 架构。

**文档版本**: 1.0
**Rust 版本**: 1.89.0
**最后更新**: 2026-04-02
**参考源码**: ../rust/rust-1.89.0/

---

## 1. 概述

### 1.1 任务基本信息

- **任务名称**: `dist-ohos-aarch64`
- **执行阶段**: Auto 阶段（代码合并到 master 分支前的完整检查阶段）
- **目标架构**: aarch64-unknown-linux-ohos (OpenHarmony ARM64)
- **构建类型**: 完整发行版构建 (dist)

### 1.2 任务目的

该任务的主要目的是：
1. 构建 Rust 编译器 (rustc) 的 OpenHarmony ARM64 版本
2. 构建标准库 (rust-std) 的 OpenHarmony ARM64 版本
3. 构建所有扩展工具 (cargo, clippy, rustfmt, rust-analyzer 等)
4. 生成完整的发行版压缩包
5. 验证构建质量和性能指标
6. 上传构建产物到 S3 存储

### 1.3 技术栈

- **构建系统**: x.py (Python 引导脚本)
- **编译器**: LLVM (通过 OhOS SDK)
- **目标系统**: OpenHarmony 5.0.0.71-Release
- **容器环境**: Ubuntu 24.04
- **缓存系统**: SCCache (S3 后端)
- **CI 系统**: GitHub Actions

---

## 2. CI 触发和任务调度

### 2.1 触发条件

`dist-ohos-aarch64` 任务在以下情况下触发：

1. **Auto 阶段触发**:
   - 代码通过 bors 合并到 master 分支前
   - 作为完整检查流程的一部分

2. **GitHub Actions 工作流**:
   - 文件位置: `.github/workflows/ci.yml`
   - 工作流名称: `CI`
   - 触发事件: `bors` 合并操作

### 2.2 任务定义

**任务定义位置**: `src/ci/github-actions/jobs.yml:215`

```yaml
auto:
  - name: dist-ohos-aarch64
    <<: *job-linux-4c
```

**配置说明**:
- 使用 `job-linux-4c` 模板配置
- 该模板定义了标准的 Linux 构建环境

### 2.3 运行器配置

**运行器类型**: `ubuntu-24.04-4core-16gb`

**配置详情**:
- **CPU**: 4 核心
- **内存**: 16GB RAM
- **操作系统**: Ubuntu 24.04
- **网络**: GitHub Actions 托管网络
- **存储**: 临时构建存储空间

**资源限制**:
- 构建时间限制: 6 小时 (默认)
- 磁盘空间: ~50GB 可用空间
- 网络带宽: GitHub Actions 标准带宽

---

## 3. 任务矩阵计算

### 3.1 计算过程

**执行命令** (`.github/workflows/ci.yml:74-79`):

```bash
cd src/ci/citool
CARGO_INCREMENTAL=0 cargo run calculate-job-matrix >> $GITHUB_OUTPUT
```

### 3.2 计算步骤详解

1. **读取任务定义**:
   - 读取 `src/ci/github-actions/jobs.yml` 文件
   - 解析所有任务配置
   - 识别 `auto` 阶段的任务

2. **分析 Git 上下文**:
   - 当前分支: `master`
   - 提交信息: bors 合并信息
   - 变更文件列表
   - PR 相关信息 (如果有)

3. **确定运行类型**:
   - `run_type`: 'auto' (自动构建)
   - 区别于 'try' (PR 构建) 和 'rollup' (定期构建)

4. **生成任务矩阵**:
   - 包含 `dist-ohos-aarch64` 任务
   - 生成任务配置 JSON
   - 包含所有必要的参数和环境变量

5. **输出到 GitHub Actions**:
   - 格式: JSON 格式的任务列表
   - 输出目标: `$GITHUB_OUTPUT`
   - 触发后续的 matrix 构建

### 3.3 矩阵输出示例

```json
{
  "include": [
    {
      "name": "dist-ohos-aarch64",
      "runs_on": "ubuntu-24.04-4core-16gb",
      "docker_image": "dist-ohos-aarch64",
      "env": {
        "TARGETS": "aarch64-unknown-linux-ohos"
      }
    }
  ]
}
```

---

## 4. Docker 镜像准备

### 4.1 镜像构建配置

**Dockerfile 位置**: `src/ci/docker/host-x86_64/dist-ohos-aarch64/Dockerfile`

**基础镜像**: `ubuntu:24.04`

**镜像分层策略**:
- 基础层: Ubuntu 24.04
- 依赖层: 系统工具和库
- SDK 层: OhOS SDK 和 OpenSSL
- 配置层: 环境变量和脚本
- 缓存层: SCCache

### 4.2 依赖安装阶段

**安装命令**:

```dockerfile
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
    && rm -rf /var/lib/apt/lists/*
```

**依赖说明**:
- `g++`: C++ 编译器 (系统编译器)
- `make`: GNU Make 构建工具
- `ninja-build`: Ninja 构建系统 (更快)
- `file`: 文件类型识别工具
- `curl`: HTTP 客户端 (下载依赖)
- `ca-certificates`: SSL 证书
- `python3`: Python 解释器 (x.py 需要)
- `git`: 版本控制工具
- `cmake`: CMake 构建系统
- `sudo`: 权限提升工具
- `gdb`: GNU 调试器
- `libssl-dev`: OpenSSL 开发库
- `pkg-config`: 包配置工具
- `xz-utils`: XZ 压缩工具
- `unzip`: ZIP 解压工具

### 4.3 OhOS SDK 安装

**安装脚本**: `src/ci/docker/scripts/ohos-sdk.sh`

**脚本内容**:

```bash
#!/bin/sh
set -ex

URL=https://repo.huaweicloud.com/openharmony/os/5.0.0-Release/ohos-sdk-windows_linux-public.tar.gz

curl $URL | tar xz -C /tmp linux/native-linux-x64-5.0.0.71-Release.zip
mkdir /opt/ohos-sdk
cd /opt/ohos-sdk
unzip -qq /tmp/linux/native-linux-x64-5.0.0.71-Release.zip
rm /tmp/linux/native-linux-x64-5.0.0.71-Release.zip
```

**SDK 信息**:
- **版本**: 5.0.0.71-Release
- **下载源**: 华为云镜像 (repo.huaweicloud.com)
- **安装路径**: `/opt/ohos-sdk/`
- **包大小**: ~2.5GB (压缩后)

**安装过程**:
1. 从华为云下载 SDK 压缩包
2. 解压到临时目录 `/tmp`
3. 提取 `linux/native-linux-x64-5.0.0.71-Release.zip`
4. 创建目标目录 `/opt/ohos-sdk`
5. 解压 SDK 内容到目标目录
6. 清理临时文件

**SDK 包含内容**:
- **LLVM 工具链**: `/opt/ohos-sdk/native/llvm/bin/`
  - `clang`: C 编译器
  - `clang++`: C++ 编译器
  - `llvm-ar`: 归档工具
  - `llvm-nm`: 符号表工具
  - 其他 LLVM 工具
- **系统根目录**: `/opt/ohos-sdk/native/sysroot/`
  - OhOS 系统头文件
  - OhOS 系统库
  - musl libc 实现
- **工具链**: `/opt/ohos-sdk/native/llvm/lib/`
  - LLVM 运行时库
  - 编译器支持库

### 4.4 OhOS OpenSSL 安装

**安装脚本**: `src/ci/docker/scripts/ohos-openssl.sh`

**脚本内容**:

```bash
#!/bin/sh
set -ex

URL=https://github.com/ohos-rs/ohos-openssl/archive/refs/tags/0.1.0.tar.gz

mkdir -p /opt/ohos-openssl
curl -fL $URL | tar xz -C /opt/ohos-openssl --strip-components=1
```

**OpenSSL 信息**:
- **版本**: 0.1.0
- **下载源**: GitHub (ohos-rs/ohos-openssl)
- **安装路径**: `/opt/ohos-openssl/`
- **预编译库路径**: `/opt/ohos-openssl/prelude/arm64-v8a`

**安装过程**:
1. 创建目标目录 `/opt/ohos-openssl`
2. 从 GitHub 下载源码压缩包
3. 解压到目标目录 (移除顶层目录)
4. 预编译库已包含在源码中

**OpenSSL 库内容**:
- **头文件**: `/opt/ohos-openssl/include/`
- **预编译库**: `/opt/ohos-openssl/prelude/arm64-v8a/`
  - `libssl.a`: SSL/TLS 库
  - `libcrypto.a`: 加密库
  - 其他支持库

### 4.5 编译器包装器安装

#### 4.5.1 C 编译器包装器

**文件位置**: `src/ci/docker/scripts/ohos/aarch64-unknown-linux-ohos-clang.sh`

**脚本内容**:

```bash
#!/bin/sh
exec /opt/ohos-sdk/native/llvm/bin/clang \
  -target aarch64-linux-ohos \
  --sysroot=/opt/ohos-sdk/native/sysroot \
  -D__MUSL__ \
  "$@"
```

**安装位置**: `/usr/local/bin/aarch64-unknown-linux-ohos-clang.sh`

#### 4.5.2 C++ 编译器包装器

**文件位置**: `src/ci/docker/scripts/ohos/aarch64-unknown-linux-ohos-clang++.sh`

**脚本内容**:

```bash
#!/bin/sh
exec /opt/ohos-sdk/native/llvm/bin/clang++ \
  -target aarch64-linux-ohos \
  --sysroot=/opt/ohos-sdk/native/sysroot \
  -D__MUSL__ \
  "$@"
```

**安装位置**: `/usr/local/bin/aarch64-unknown-linux-ohos-clang++.sh`

#### 4.5.3 包装器作用

1. **调用 OhOS SDK 中的 LLVM clang/clang++**:
   - 直接使用 SDK 提供的编译器
   - 确保版本兼容性

2. **设置正确的目标 triple**:
   - `-target aarch64-linux-ohos`
   - 告诉编译器目标架构和系统

3. **指定 sysroot 路径**:
   - `--sysroot=/opt/ohos-sdk/native/sysroot`
   - 指定 OhOS 系统根目录
   - 包含系统头文件和库

4. **定义 __MUSL__ 宏**:
   - `-D__MUSL__`
   - OhOS 使用 musl libc
   - 启用 musl 特定的代码路径

5. **传递所有参数**:
   - `"$@"`
   - 保留原始编译参数
   - 支持额外的编译选项

### 4.6 环境变量配置

#### 4.6.1 目标配置

```bash
set -ex

URL=https://repo.huaweicloud.com/openharmony/os/5.0.0-Release/ohos-sdk-windows_linux-public.tar.gz

curl $URL | tar xz -C /tmp linux/native-linux-x64-5.0.0.71-Release.zip
mkdir /opt/ohos-sdk
cd /opt/ohos-sdk
unzip -qq /tmp/linux/native-linux-x64-5.0.0.71-Release.zip
rm /tmp/linux/native-linux-x64-5.0.0.71-Release.zip
```

**说明**: 定义编译目标架构

#### 4.6.2 编译器工具链

```bash
ENV \
    CC_aarch64_unknown_linux_ohos=/usr/local/bin/aarch64-unknown-linux-ohos-clang.sh \
    AR_aarch64_unknown_linux_ohos=/opt/ohos-sdk/native/llvm/bin/llvm-ar \
    CXX_aarch64_unknown_linux_ohos=/usr/local/bin/aarch64-unknown-linux-ohos-clang++.sh
```

**说明**:
- `CC_*`: C 编译器路径
- `AR_*`: 归档工具路径
- `CXX_*`: C++ 编译器路径
- 针对特定目标架构的配置

#### 4.6.3 OpenSSL 配置

```bash
ENV AARCH64_UNKNOWN_LINUX_OHOS_OPENSSL_DIR=/opt/ohos-openssl/prelude/arm64-v8a
ENV AARCH64_UNKNOWN_LINUX_OHOS_OPENSSL_NO_VENDOR=1
```

**说明**:
- 指定 OpenSSL 库的位置
- 禁用 vendored OpenSSL (使用预编译版本)

#### 4.6.4 Rust 配置参数

```bash
ENV RUST_CONFIGURE_ARGS \
    --enable-profiler \
    --disable-docs \
    --tools=cargo,clippy,rustdocs,rustfmt,rust-analyzer,rust-analyzer-proc-macro-srv,analysis,src,wasm-component-ld \
    --enable-extended \
    --enable-sanitizers
```

**配置说明**:
- `--enable-profiler`: 启用性能分析支持
  - 支持 perf 工具
  - 支持 profiler 工具
  - 生成性能分析数据

- `--disable-docs`: 跳过文档构建
  - 加快构建速度
  - 减少构建时间约 30%
  - 文档可以单独构建

- `--tools`: 指定要构建的扩展工具列表
  - `cargo`: 包管理器
  - `clippy`: Rust linter
  - `rustdocs`: 文档生成工具
  - `rustfmt`: 代码格式化工具
  - `rust-analyzer`: 语言服务器
  - `rust-analyzer-proc-macro-srv`: 宏分析服务器
  - `analysis`: 分析工具
  - `src`: 源代码工具
  - `wasm-component-ld`: WebAssembly 组件链接器

- `--enable-extended`: 启用扩展工具链
  - 包含所有标准工具
  - 启用额外功能

- `--enable-sanitizers`: 启用内存清理器支持
  - AddressSanitizer: 内存错误检测
  - ThreadSanitizer: 线程安全检测
  - LeakSanitizer: 内存泄漏检测
  - UndefinedBehaviorSanitizer: 未定义行为检测

### 4.7 构建脚本定义

```bash
ENV SCRIPT python3 ../x.py dist --host=$TARGETS --target $TARGETS
```

**实际执行的命令**:
```bash
python3 ../x.py dist --host=aarch64-unknown-linux-ohos --target aarch64-unknown-linux-ohos
```

**说明**:
- `python3 ../x.py`: 调用 Rust 构建引导脚本
- `dist`: 构建发行版
- `--host`: 指定主机架构 (编译器运行平台)
- `--target`: 指定目标架构 (编译产物目标平台)

### 4.8 SCCache 安装

**安装脚本**: `src/ci/docker/scripts/sccache.sh`

**脚本内容**:

```bash
#!/bin/sh

# ignore-tidy-linelength

set -ex

case "$(uname -m)" in
    x86_64)
        url="https://ci-mirrors.rust-lang.org/rustc/2025-02-24-sccache-v0.10.0-x86_64-unknown-linux-musl"
        ;;
    aarch64)
        url="https://ci-mirrors.rust-lang.org/rustc/2025-02-24-sccache-v0.10.0-aarch64-unknown-linux-musl"
        ;;
    *)
        echo "unsupported architecture: $(uname -m)"
        exit 1
esac

curl -fo /usr/local/bin/sccache "${url}"
chmod +x /usr/local/bin/sccache
```

**SCCache 作用**:
- **编译缓存**: 缓存编译结果，加速重复构建
- **CI 环境**: 使用 S3 后端存储缓存
- **本地环境**: 使用本地文件系统缓存
- **性能提升**: 可减少 50-80% 的构建时间

**SCCache 配置**:
- **版本**: v0.10.0
- **下载源**: Rust CI 镜像服务器
- **安装位置**: `/usr/local/bin/sccache`
- **S3 Bucket**: `rust-lang-ci-sccache2`
- **S3 Region**: `us-west-1`

---

## 5. Docker 镜像缓存和构建

### 5.1 镜像校验和计算

**计算过程** (`src/ci/docker/run.sh:79-109`):

1. **创建临时文件**:
   - 文件路径: `/tmp/.docker-hash-key.txt`

2. **写入镜像名称**:
   - 内容: `dist-ohos-aarch64`

3. **追加 Dockerfile 内容**:
   - 读取整个 Dockerfile
   - 追加到校验文件

4. **查找 COPY 命令引用的文件**:
   - 解析 Dockerfile 中的 COPY 命令
   - 识别所有引用的文件路径

5. **按排序顺序追加文件内容**:
   - 确保一致的哈希值
   - 避免文件顺序影响

6. **追加系统架构信息**:
   - `$(uname -m)`: 系统架构
   - 确保跨平台一致性

7. **追加缓存版本号**:
   - 当前版本: "2"
   - 用于强制重建镜像

8. **计算 SHA512 校验和**:
   - 使用 `sha512sum` 命令
   - 生成唯一的镜像标识符

**校验和用途**:
- **镜像标签**: 用作 Docker 镜像标签
- **缓存识别**: 用于识别镜像缓存
- **依赖跟踪**: 确保依赖变化时重建镜像
- **版本控制**: 支持镜像版本管理

### 5.2 镜像标签生成

**标签生成脚本**:

```bash
REGISTRY=ghcr.io
REGISTRY_USERNAME=${GITHUB_REPOSITORY_OWNER:-rust-lang}
IMAGE_TAG=${REGISTRY}/${REGISTRY_USERNAME}/rust-ci:${cksum}
CACHE_IMAGE_TAG=${REGISTRY}/${REGISTRY_USERNAME}/rust-ci-cache:${cksum}
```

**示例标签**:
```
ghcr.io/rust-lang/rust-ci:a1b2c3d4e5f6...
ghcr.io/rust-lang/rust-ci-cache:a1b2c3d4e5f6...
```

**标签说明**:
- `rust-ci`: 最终镜像标签
- `rust-ci-cache`: 缓存镜像标签
- 校验和: 128 字符的 SHA512 哈希值

### 5.3 镜像构建策略

#### 5.3.1 Auto/Try CI 环境

**配置位置** (`.github/workflows/ci.yml:188-223`):

**构建步骤**:

1. **登录到 Docker Registry**:
   ```bash
   docker login ghcr.io -u $REGISTRY_USERNAME -p $REGISTRY_PASSWORD
   ```

2. **创建 buildx 构建驱动器**:
   ```bash
   docker buildx create --use --driver docker-container \
     --driver-opt image=ghcr.io/rust-lang/buildkit:buildx-stable-1
   ```

3. **使用 registry 缓存后端构建镜像**:
   ```bash
   docker buildx \
     build \
     --rm \
     -t rust-ci \
     -f "$dockerfile" \
     "$context" \
     --cache-from type=registry,ref=${CACHE_IMAGE_TAG} \
     --cache-to type=registry,ref=${CACHE_IMAGE_TAG},compression=zstd \
     --output=type=docker
   ```

4. **推送最终镜像到 registry**:
   ```bash
   docker tag rust-ci "${IMAGE_TAG}"
   docker push "${IMAGE_TAG}"
   ```

5. **推送缓存镜像到 registry**:
   ```bash
   docker push "${CACHE_IMAGE_TAG}"
   ```

**构建参数说明**:
- `--rm`: 构建完成后删除中间容器
- `-t rust-ci`: 临时标签
- `-f "$dockerfile"`: 指定 Dockerfile 路径
- `"$context"`: 构建上下文路径
- `--cache-from`: 从 registry 拉取缓存
- `--cache-to`: 推送缓存到 registry
- `compression=zstd`: 使用 Zstandard 压缩
- `--output=type=docker`: 输出为 Docker 镜像

#### 5.3.2 缓存策略

**缓存层级**:
1. **基础层缓存**: Ubuntu 24.04 基础镜像
2. **依赖层缓存**: 系统依赖安装结果
3. **SDK 层缓存**: OhOS SDK 和 OpenSSL 安装结果
4. **配置层缓存**: 环境变量和脚本配置
5. **构建缓存**: SCCache 编译缓存

**缓存命中条件**:
- Dockerfile 内容未变化
- 引用的文件内容未变化
- 系统架构相同
- 缓存版本号相同

**缓存失效条件**:
- Dockerfile 内容变化
- 引用的文件内容变化
- 系统架构变化
- 缓存版本号更新
- 手动触发重建

---

## 6. Docker 容器执行

### 6.1 容器启动配置

**执行脚本**: `src/ci/scripts/run-build-from-ci.sh`

**脚本内容**:

```bash
#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

source "$(cd "$(dirname "$0")" && pwd)/../shared.sh"

export CI="true"
export SRC=.

echo "::add-matcher::src/ci/github-actions/problem_matchers.json"

rustup self uninstall -y || true

if [ -z "${IMAGE+x}" ]; then
    src/ci/run.sh
else
    src/ci/docker/run.sh "${IMAGE}"
fi
```

**脚本说明**:
1. **设置严格模式**:
   - `set -euo pipefail`: 严格错误处理
   - `IFS=$'\n\t'`: 设置字段分隔符

2. **加载共享脚本**:
   - 包含 CI 通用函数
   - 设置环境变量

3. **设置 CI 环境变量**:
   - `CI="true"`: 标识 CI 环境
   - `SRC="."`: 源码目录

4. **添加问题匹配器**:
   - 解析编译错误格式
   - 在 GitHub Actions 中显示错误

5. **清理 rustup**:
   - 移除系统安装的 rustup
   - 避免版本冲突

6. **执行构建**:
   - 如果 IMAGE 未设置: 直接运行
   - 如果 IMAGE 已设置: 在 Docker 中运行

### 6.2 卷挂载配置

**标准环境** (`src/ci/docker/run.sh:338-365`):

```bash
docker run \
  --volume $root_dir:/checkout:ro \           # 源码目录（只读）
  --volume $objdir:/checkout/obj \              # 对象目录（读写）
  --volume $HOME/.cargo:/cargo \                # Cargo 缓存
  --volume /tmp/toolstate:/tmp/toolstate \      # 工具状态
  --workdir /checkout/obj \                      # 工作目录
  --privileged \                                 # 特权模式（ptrace 等）
  --env LOCAL_USER_ID=$id \                     # 用户 ID 映射
  rust-ci \
  /checkout/src/ci/run.sh
```

**卷挂载说明**:
- **源码目录**: 只读挂载，防止修改
- **对象目录**: 读写挂载，存储构建产物
- **Cargo 缓存**: 持久化 Cargo 依赖缓存
- **工具状态**: 存储工具状态信息
- **工作目录**: 设置容器内工作目录
- **特权模式**: 允许 ptrace 等操作
- **用户 ID 映射**: 保持文件权限一致性

### 6.3 Docker-in-Docker 环境

**配置脚本**:

```bash
docker create -v /checkout --name checkout ghcr.io/rust-lang/alpine:3.4 /bin/true
docker cp . checkout:/checkout
docker run --volumes-from checkout ...
```

**说明**:
- 创建数据容器存储源码
- 复制源码到数据容器
- 使用 volumes-from 共享源码
- 适用于 Docker-in-Docker 环境

### 6.4 环境变量传递

**核心环境变量**:

```bash
--env SRC=/checkout \
--env CARGO_HOME=/cargo \
--env DEPLOY=1 \                                # 启用发布模式
--env DEPLOY_ALT \
--env CI=true \
--env GITHUB_ACTIONS \
--env GITHUB_REF \
--env GITHUB_WORKFLOW_RUN_ID \
--env GITHUB_REPOSITORY \
--env TOOLSTATE_REPO \
--env TOOLSTATE_PUBLISH=1 \                     # Auto 阶段启用
--env CI_JOB_NAME=dist-ohos-aarch64 \
--env BASE_COMMIT=<last-bors-merge> \
--env CODEGEN_BACKENDS=llvm,cranelift \
--env OBJDIR_ON_HOST=$objdir
```

**环境变量说明**:
- `SRC`: 源码目录路径
- `CARGO_HOME`: Cargo 主目录
- `DEPLOY`: 启用发布模式
- `CI`: 标识 CI 环境
- `GITHUB_ACTIONS`: GitHub Actions 标识
- `GITHUB_REF`: Git 引用信息
- `GITHUB_WORKFLOW_RUN_ID`: 工作流运行 ID
- `GITHUB_REPOSITORY`: 仓库信息
- `TOOLSTATE_REPO`: 工具状态仓库
- `TOOLSTATE_PUBLISH`: 发布工具状态
- `CI_JOB_NAME`: CI 任务名称
- `BASE_COMMIT`: 基础提交哈希
- `CODEGEN_BACKENDS`: 代码生成后端
- `OBJDIR_ON_HOST`: 对象目录主机路径

### 6.5 SCCache 配置

**Auto CI 环境** (`src/ci/docker/run.sh:277-289`):

```bash
if [ "$SCCACHE_BUCKET" != "" ]; then
    args="$args --env SCCACHE_BUCKET"
    args="$args --env SCCACHE_REGION"
    args="$args --env AWS_REGION"
    args="$args --env AWS_ACCESS_KEY_ID"
    args="$args --env AWS_SECRET_ACCESS_KEY"
fi
```

**SCCache 配置**:
- **Bucket**: `rust-lang-ci-sccache2`
- **Region**: `us-west-1`
- **认证**: AWS IAM 凭证
- **缓存类型**: 分布式缓存

**SCCache 环境变量**:
- `SCCACHE_BUCKET`: S3 bucket 名称
- `SCCACHE_REGION`: S3 区域
- `AWS_REGION`: AWS 区域
- `AWS_ACCESS_KEY_ID`: AWS 访问密钥 ID
- `AWS_SECRET_ACCESS_KEY`: AWS 秘密访问密钥

---

## 7. Rust 构建执行

### 7.1 构建入口

**容器内执行**: `/checkout/src/ci/run.sh`

**主要构建命令**:

```bash
cd /checkout/obj
python3 ../x.py dist --host=aarch64-unknown-linux-ohos --target aarch64-unknown-linux-ohos
```

**构建说明**:
- 切换到对象目录
- 调用 x.py 构建脚本
- 构建发行版 (dist)
- 指定主机和目标架构

### 7.2 x.py 构建流程

**x.py 是 Python 引导脚本**，执行以下步骤：

#### 7.2.1 配置解析

1. **读取 config.toml**:
   - 如果存在配置文件
   - 解析配置选项
   - 合并默认配置

2. **解析命令行参数**:
   - `dist`: 构建命令
   - `--host`: 主机架构
   - `--target`: 目标架构
   - 其他构建选项

3. **合并环境变量配置**:
   - 读取 `RUST_CONFIGURE_ARGS`
   - 应用环境变量配置
   - 优先级: 命令行 > 环境变量 > 配置文件

#### 7.2.2 Bootstrap 设置

1. **检测 stage0 编译器版本**:
   - 读取 `src/stage0.txt`
   - 确定需要的编译器版本
   - 验证版本兼容性

2. **下载或使用缓存的 stage0 编译器**:
   - 检查本地缓存
   - 从官方服务器下载
   - 验证下载完整性
   - 解压到本地目录

3. **设置构建环境**:
   - 配置编译器路径
   - 设置环境变量
   - 初始化构建目录

#### 7.2.3 依赖解析

1. **分析需要构建的 crate**:
   - 读取 Cargo.toml 文件
   - 解析依赖关系
   - 识别工作空间成员

2. **确定构建依赖关系**:
   - 构建依赖图
   - 分析构建顺序
   - 检测循环依赖

3. **生成构建图**:
   - 创建有向无环图
   - 确定并行构建策略
   - 优化构建顺序

#### 7.2.4 编译执行

**Stage 编译过程**:

1. **Stage 0: 使用预编译的 Rust 编译器**:
   - 下载的 stage0 编译器
   - 用于编译 Stage 1 编译器
   - 不需要构建时间

2. **Stage 1: 使用 Stage 0 编译器构建 Rust 编译器**:
   - 编译 rustc (Rust 编译器)
   - 编译标准库组件
   - 生成 Stage 1 工具链

3. **Stage 2: 使用 Stage 1 编译器构建最终编译器**:
   - 如果需要，编译 Stage 2
   - 用于最终发布版本
   - 确保编译器自举

#### 7.2.5 工具链构建

**构建组件**:

1. **编译标准库**:
   - `library/std`: 标准库
   - `library/core`: 核心库
   - `library/alloc`: 内存分配库
   - 针对目标架构编译

2. **编译编译器**:
   - `compiler/rustc`: Rust 编译器
   - 编译器前端和后端
   - 代码生成组件

3. **构建扩展工具**:
   - `cargo`: 包管理器
   - `clippy`: Rust linter
   - `rustfmt`: 代码格式化工具
   - `rust-analyzer`: 语言服务器
   - `rust-analyzer-proc-macro-srv`: 宏分析服务器
   - `analysis`: 分析工具
   - `src`: 源代码工具
   - `wasm-component-ld`: WebAssembly 组件链接器

#### 7.2.6 发行版打包

1. **创建目录结构**:
   - 按照发行版规范组织
   - 创建必要的子目录
   - 设置正确的权限

2. **复制编译产物**:
   - 复制编译器二进制文件
   - 复制标准库文件
   - 复制扩展工具
   - 复制依赖库

3. **生成 tarball 压缩包**:
   - 使用 tar 和 gzip 压缩
   - 生成标准命名格式
   - 计算校验和

### 7.3 交叉编译细节

**目标 triple**: `aarch64-unknown-linux-ohos`

**编译器调用链**:

```
rustc (host)
  ↓
CC_aarch64_unknown_linux_ohos
  ↓
aarch64-unknown-linux-ohos-clang.sh
  ↓
/opt/ohos-sdk/native/llvm/bin/clang -target aarch64-linux-ohos --sysroot=/opt/ohos-sdk/native/sysroot
```

**调用链说明**:
1. **rustc**: Rust 编译器 (x86_64 host)
2. **CC_aarch64_unknown_linux_ohos**: 环境变量指定的 C 编译器
3. **aarch64-unknown-linux-ohos-clang.sh**: 编译器包装脚本
4. **clang**: 实际的 LLVM clang 编译器

**链接过程**:
- 使用 OhOS SDK 的 llvm-ar
- 链接 OhOS musl libc
- 链接 OpenSSL 库（从 `/opt/ohos-openssl/prelude/arm64-v8a`）
- 生成 aarch64-unknown-linux-ohos 目标文件

---

## 8. 构建产物

### 8.1 输出目录结构

**主输出目录**: `obj/dist-ohos-aarch64/build/dist/`

**典型目录结构**:

```
obj/dist-ohos-aarch64/build/dist/
├── rust-1.89.0-aarch64-unknown-linux-ohos/
│   ├── rustc/
│   │   ├── bin/
│   │   │   └── rustc
│   │   └── lib/
│   │       ├── librustc_*.so
│   │       └── ...
│   ├── rust-std-aarch64-unknown-linux-ohos/
│   │   └── lib/
│   │       └── rustlib/
│   │           └── aarch64-unknown-linux-ohos/
│   │               ├── libstd-*.rlib
│   │               ├── libcore-*.rlib
│   │               └── ...
│   ├── cargo/
│   │   ├── bin/
│   │   │   └── cargo
│   │   └── lib/
│   │       └── ...
│   ├── rustfmt/
│   │   ├── bin/
│   │   │   └── rustfmt
│   │   └── lib/
│   ├── clippy/
│   │   ├── bin/
│   │   │   └── clippy
│   │   └── lib/
│   ├── rust-analyzer/
│   │   ├── bin/
│   │   │   └── rust-analyzer
│   │   └── lib/
│   ├── rust-analyzer-proc-macro-srv/
│   ├── analysis/
│   ├── src/
│   ├── wasm-component-ld/
│   └── ...
└── rust-1.89.0-aarch64-unknown-linux-ohos.tar.gz
```

### 8.2 构建的组件

#### 8.2.1 核心组件

- **rustc**: Rust 编译器
  - 位置: `rustc/bin/rustc`
  - 功能: 编译 Rust 代码
  - 依赖: LLVM 后端

- **rust-std**: 标准库
  - 位置: `rust-std-aarch64-unknown-linux-ohos/lib/rustlib/`
  - 功能: 提供 Rust 标准库
  - 包含: std, core, alloc 等

- **cargo**: 包管理器
  - 位置: `cargo/bin/cargo`
  - 功能: 管理依赖和项目
  - 依赖: rustc

#### 8.2.2 扩展工具

- **clippy**: Rust linter
  - 位置: `clippy/bin/clippy`
  - 功能: 代码质量检查
  - 用途: 静态分析

- **rustfmt**: 代码格式化工具
  - 位置: `rustfmt/bin/rustfmt`
  - 功能: 自动格式化代码
  - 用途: 代码风格统一

- **rust-analyzer**: 语言服务器
  - 位置: `rust-analyzer/bin/rust-analyzer`
  - 功能: IDE 集成支持
  - 用途: 代码补全、跳转等

- **rust-analyzer-proc-macro-srv**: 宏分析服务器
  - 功能: 分析过程宏
  - 用途: 宏展开和检查

- **analysis**: 分析工具
  - 功能: 代码分析
  - 用途: 性能分析等

- **src**: 源代码工具
  - 功能: 源码处理
  - 用途: 源码分析

- **wasm-component-ld**: WebAssembly 组件链接器
  - 功能: WASM 组件链接
  - 用途: WebAssembly 支持

### 8.3 发行版特性

#### 8.3.1 启用的特性

- **性能分析器支持**:
  - 支持 perf 工具
  - 支持 profiler 工具
  - 生成性能分析数据

- **内存清理器**:
  - AddressSanitizer: 内存错误检测
  - ThreadSanitizer: 线程安全检测
  - LeakSanitizer: 内存泄漏检测
  - UndefinedBehaviorSanitizer: 未定义行为检测

- **扩展工具链**:
  - 包含所有标准工具
  - 启用额外功能
  - 支持完整的开发体验

- **LLVM 和 Cranelift 后端**:
  - LLVM: 主要代码生成后后端
  - Cranelift: 实验性后端
  - 支持多种优化策略

#### 8.3.2 禁用的特性

- **文档生成**:
  - 为了加快构建速度
  - 文档可以单独构建
  - 减少构建时间约 30%

---

## 9. 构建后处理

### 9.1 指标收集

**CPU 使用率统计** (`.github/workflows/ci.yml:160-161`):

```bash
src/ci/scripts/collect-cpu-stats.sh
```

**构建指标**:
- **编译时间**: 总编译耗时
- **内存使用**: 峰值内存使用
- **缓存命中率**: SCCache 命中率
- **构建产物大小**: 最终产物大小
- **磁盘 I/O**: 读写操作统计
- **网络使用**: 下载流量统计

### 9.2 指标后处理

**后处理脚本** (`.github/workflows/ci.yml:283-303`):

```bash
if [ -f build/metrics.json ]; then
  METRICS=build/metrics.json
elif [ -f obj/build/metrics.json ]; then
  METRICS=obj/build/metrics.json
fi

PARENT_COMMIT=`git rev-list --author='bors <bors@rust-lang.org>' -n1 --first-parent HEAD^1`

./build/citool/debug/citool postprocess-metrics \
    --job-name ${CI_JOB_NAME} \
    --parent ${PARENT_COMMIT} \
    ${METRICS} >> ${GITHUB_STEP_SUMMARY}
```

**后处理步骤**:
1. **查找指标文件**:
   - 检查 `build/metrics.json`
   - 检查 `obj/build/metrics.json`
   - 确定指标文件位置

2. **获取父提交**:
   - 查找上一个 bors 合并
   - 获取父提交哈希
   - 用于性能对比

3. **处理指标**:
   - 调用 citool 处理指标
   - 对比当前和父提交指标
   - 生成性能报告

**指标对比**:
- 与父提交的指标对比
- 显示性能回归或改进
- 输出到 GitHub Actions 摘要
- 标记显著变化

### 9.3 DataDog 上传

**上传命令** (`.github/workflows/ci.yml:305-313`):

```bash
./build/citool/debug/citool upload-build-metrics build/cpu-usage.csv
```

**上传条件**:
- 非 PR CI 环境
- DataDog API Key 可用
- 网络连接正常

**DataDog 配置**:
- **API 端点**: DataDog API
- **认证**: API Key
- **指标类型**: 构建指标
- **时间序列**: 按时间存储

**上传内容**:
- CPU 使用率时间序列
- 内存使用时间序列
- 构建阶段耗时
- 缓存命中率统计

---

## 10. 产物上传

### 10.1 S3 上传

**上传脚本** (`.github/workflows/ci.yml:271-281`):

```bash
src/ci/scripts/upload-artifacts.sh
```

**上传条件**:

```yaml
if: github.event_name == 'push' || env.DEPLOY == '1' || env.DEPLOY_ALT == '1'
```

**S3 配置**:
- **Bucket**: `rust-lang-ci2`
- **Region**: `us-west-1`
- **访问凭证**: GitHub Secrets
  - `ARTIFACTS_AWS_ACCESS_KEY_ID`
  - `ARTIFACTS_AWS_SECRET_ACCESS_KEY`

**上传内容**:
- 构建产物 tarball
- 构建指标文件
- 工具状态文件
- 镜像信息文件

**上传策略**:
- 使用多部分上传
- 支持断点续传
- 自动重试机制
- 校验和验证

### 10.2 Docker 镜像信息记录

**镜像标签保存** (`src/ci/docker/run.sh:217-220`):

```bash
info="$dist/image-$image.txt"
mkdir -p "$dist"
echo "${IMAGE_TAG}" > "$info"
```

**文件位置**: `obj/dist-ohos-aarch64/build/dist/image-dist-ohos-aarch64.txt`

**信息内容**:
- Docker 镜像标签
- 镜像校验和
- 构建时间戳
- 构建环境信息

---

## 11. 构建完成和验证

### 11.1 构建成功条件

**必须满足的条件**:
1. 所有编译步骤成功完成
2. 所有测试通过（如果有）
3. 产物生成成功
4. 上传到 S3 成功
5. 指标收集完成
6. 没有错误或警告

### 11.2 错误处理

**错误类型**:
- **编译错误**: 代码问题
  - 语法错误
  - 类型错误
  - 链接错误

- **依赖问题**: 依赖错误
  - 缺少依赖
  - 版本冲突
  - 下载失败

- **配置错误**: 环境问题
  - 环境变量错误
  - 路径配置错误
  - 权限问题

- **网络错误**: 下载失败
  - 连接超时
  - DNS 解析失败
  - 服务器错误

- **资源错误**: 资源不足
  - 磁盘空间不足
  - 内存不足
  - CPU 时间限制

**错误报告**:
- **GitHub Actions 日志**: 详细错误信息
- **问题匹配器**: 格式化错误显示
- **构建摘要**: 错误汇总信息
- **通知机制**: 发送错误通知

### 11.3 构建验证

**验证步骤**:
1. **产物完整性检查**:
   - 验证 tarball 完整性
   - 检查校验和
   - 验证文件权限

2. **功能测试**:
   - 测试编译器基本功能
   - 测试标准库可用性
   - 测试扩展工具

3. **性能验证**:
   - 检查构建时间
   - 对比历史性能
   - 标记性能回归

4. **安全检查**:
   - 扫描安全漏洞
   - 检查依赖安全性
   - 验证签名

---

## 12. 完整执行流程图

```
┌─────────────────────────────────────────────────────────────┐
│ GitHub Actions (auto 阶段触发)                              │
│ 分支: master                                                │
│ 触发器: bors 合并                                           │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ calculate_job_matrix 任务                                    │
│ - 读取 jobs.yml                                             │
│ - 分析 Git 上下文                                            │
│ - 生成任务矩阵                                               │
│ - 输出: dist-ohos-aarch64 任务                              │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ Docker 镜像准备                                              │
│ - 计算镜像校验和                                             │
│ - 检查缓存镜像                                               │
│ - 构建或拉取镜像                                             │
│ - 推送到 ghcr.io                                             │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ Docker 容器启动                                              │
│ - 挂载源码目录 (只读)                                        │
│ - 挂载对象目录 (读写)                                        │
│ - 配置环境变量                                               │
│ - 配置 SCCache (S3)                                         │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ 容器内构建执行                                                │
│ - 执行 /checkout/src/ci/run.sh                              │
│ - python3 x.py dist --host=aarch64-unknown-linux-ohos       │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ x.py 构建流程                                                │
│ 1. 配置解析                                                  │
│ 2. Bootstrap 设置                                           │
│ 3. 依赖解析                                                  │
│ 4. Stage 0 编译 (使用预编译编译器)                          │
│ 5. Stage 1 编译 (使用 Stage 0)                              │
│ 6. 标准库编译                                                │
│ 7. 扩展工具编译                                              │
│ 8. 发行版打包                                                │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ 交叉编译细节                                                  │
│ - 使用 OhOS SDK (5.0.0.71)                                 │
│ - 使用 OhOS OpenSSL (0.1.0)                                 │
│ - 目标: aarch64-linux-ohos                                  │
│ - Sysroot: /opt/ohos-sdk/native/sysroot                    │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ 构建产物生成                                                  │
│ - rustc 编译器                                               │
│ - rust-std 标准库                                            │
│ - cargo 包管理器                                             │
│ - clippy, rustfmt, rust-analyzer 等                         │
│ - 输出: obj/dist-ohos-aarch64/build/dist/                  │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ 构建后处理                                                    │
│ - 收集 CPU 使用率                                           │
│ - 生成构建指标                                               │
│ - 对比父提交指标                                             │
│ - 上传到 DataDog                                             │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ 产物上传                                                      │
│ - 上传到 S3 (rust-lang-ci2)                                 │
│ - 保存 Docker 镜像标签                                       │
│ - 生成构建摘要                                               │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ 构建完成                                                      │
│ - 验证所有步骤成功                                           │
│ - 报告构建结果                                               │
│ - 通知 bors                                                  │
└─────────────────────────────────────────────────────────────┘
```

---

## 13. 关键文件和路径总结

### 13.1 配置文件

**GitHub Actions 配置**:
- `.github/workflows/ci.yml`: GitHub Actions 工作流定义
- `src/ci/github-actions/jobs.yml`: CI 任务定义
- `src/ci/github-actions/problem_matchers.json`: 错误匹配规则

**Docker 配置**:
- `src/ci/docker/host-x86_64/dist-ohos-aarch64/Dockerfile`: Docker 镜像定义

### 13.2 脚本文件

**CI 脚本**:
- `src/ci/scripts/run-build-from-ci.sh`: CI 构建入口
- `src/ci/docker/run.sh`: Docker 容器运行脚本
- `src/ci/scripts/shared.sh`: CI 共享函数

**安装脚本**:
- `src/ci/docker/scripts/ohos-sdk.sh`: OhOS SDK 安装脚本
- `src/ci/docker/scripts/ohos-openssl.sh`: OhOS OpenSSL 安装脚本
- `src/ci/docker/scripts/sccache.sh`: SCCache 安装脚本

**编译器包装器**:
- `src/ci/docker/scripts/ohos/aarch64-unknown-linux-ohos-clang.sh`: C 编译器包装器
- `src/ci/docker/scripts/ohos/aarch64-unknown-linux-ohos-clang++.sh`: C++ 编译器包装器

**其他脚本**:
- `src/ci/scripts/collect-cpu-stats.sh`: CPU 统计收集
- `src/ci/scripts/upload-artifacts.sh`: 产物上传脚本

### 13.3 工具

**CI 工具**:
- `src/ci/citool/`: CI 任务管理工具
- `x.py`: Rust 构建引导脚本

### 13.4 输出目录

**构建输出**:
- `obj/dist-ohos-aarch64/build/dist/`: 构建产物目录
- `obj/dist-ohos-aarch64/build/dist/rust-1.89.0-aarch64-unknown-linux-ohos.tar.gz`: 最终产物
- `obj/dist-ohos-aarch64/build/dist/image-dist-ohos-aarch64.txt`: Docker 镜像标签

**中间文件**:
- `obj/dist-ohos-aarch64/build/`: 构建中间文件
- `obj/dist-ohos-aarch64/build/metrics.json`: 构建指标
- `obj/dist-ohos-aarch64/build/cpu-usage.csv`: CPU 使用率

### 13.5 外部依赖

**OhOS SDK**:
- 下载地址: https://repo.huaweicloud.com/openharmony/os/5.0.0-Release/
- 文件名: ohos-sdk-windows_linux-public.tar.gz
- 版本: 5.0.0.71-Release

**OhOS OpenSSL**:
- 下载地址: https://github.com/ohos-rs/ohos-openssl
- 版本: 0.1.0
- 预编译库: arm64-v8a

**SCCache**:
- 下载地址: https://ci-mirrors.rust-lang.org/rustc/
- 版本: v0.10.0
- S3 Bucket: rust-lang-ci-sccache2

**产物存储**:
- S3 Bucket: rust-lang-ci2
- S3 Region: us-west-1

---

## 14. 性能优化要点

### 14.1 缓存策略



**Docker 镜像层缓存**:
- 基础层: Ubuntu 24.04 (官方镜像)
- 依赖层: 系统依赖安装结果
- SDK 层: OhOS SDK 和 OpenSSL 安装结果
- 配置层: 环境变量和脚本配置

**SCCache 编译缓存**:
- 编译对象缓存
- 链接产物缓存
- 分布式缓存 (S3)
- 缓存命中率: 50-80%

**Cargo 依赖缓存**:
- Cargo 依赖缓存
- 注册表缓存
- 索引缓存

### 14.2 并行构建

**x.py 并行编译**:
- 自动检测 CPU 核心数
- 并行编译多个 crate
- 并行链接多个目标

**多核利用**:
- 4 核心 CPU
- 每核心处理多个任务
- 负载均衡优化

### 14.3 资源限制

**内存限制**:
- 16GB RAM
- 峰值内存监控
- OOM 保护机制

**磁盘空间管理**:
- 自动清理临时文件
- 压缩中间产物
- 监控磁盘使用

**网络优化**:
- 并行下载依赖
- 断点续传支持
- CDN 加速

### 14.4 构建优化

**禁用文档生成**:
- 节省约 30% 构建时间
- 文档可单独构建
- 减少构建产物大小

**使用预编译的 stage0**:
- 跳过 bootstrap 编译
- 使用官方预编译版本
- 减少初始构建时间

**增量编译支持**:
- 只重新编译变更的 crate
- 依赖关系跟踪
- 增量链接优化

---

## 15. 常见工作流程

### 15.1 本地构建 OhOS

**步骤**:

1. **确保 Docker 已安装并运行**:
   ```bash
   docker --version
   docker ps
   ```

2. **运行 OhOS 发行版构建**:
   ```bash
   cargo run --manifest-path src/ci/citool/Cargo.toml -- run-local dist-ohos-aarch64 > ./tmp/output_$(date +%Y%m%d_%H%M%S).log 2>&1
   ```

3. **查看构建产物**:
   ```bash
   ls -la obj/dist-ohos-aarch64/build/dist/
   ```

**构建产物位置**: `obj/dist-ohos-aarch64/build/dist/`

### 15.2 模拟官方 CI

**要完全模拟 OhOS 的官方 Rust CI**:

1. **使用 CI 工具**:
   - 始终使用 `citool` 进行本地 CI 模拟
   - 确保环境一致性

2. **设置 DEPLOY=1**:
   - 启用发行版构建模式
   - 生成完整的发行版

3. **使用 Docker**:
   - 构建在 Docker 中进行
   - 保持与 CI 环境一致

4. **检查环境**:
   - CI 为 OhOS 构建设置特定环境变量
   - 验证所有依赖可用

5. **验证产物**:
   - 检查构建完整性
   - 验证产物格式
   - 测试基本功能

### 15.3 调试构建问题

**调试步骤**:

1. **启用详细日志**:
   ```bash
   RUST_BACKTRACE=1 cargo build --verbose
   ```

2. **检查环境变量**:
   ```bash
   env | grep -i rust
   env | grep -i ohos
   ```

3. **验证工具链**:
   ```bash
   clang --version
   /usr/local/bin/aarch64-unknown-linux-ohos-clang.sh --version
   ```

4. **检查依赖**:
可用性:
   ```bash
   ls -la /opt/ohos-sdk/
   ls -la /opt/ohos-openssl/
   ```

5. **查看构建日志**:
   ```bash
   cat ./tmp/output_*.log
   ```

---

## 16. 故障排除

### 16.1 常见错误

**编译错误**:
- **症状**: 编译失败，语法错误
- **原因**: 代码问题或依赖问题
- **解决**: 检查代码语法，更新依赖

**链接错误**:
- **症状**: 链接失败，未定义符号
- **原因**: 库缺失或版本不匹配
- **解决**: 检查依赖，更新 SDK

**权限错误**:
- **症状**: Permission denied
- **原因**: 文件权限问题
- **解决**: 检查文件权限，修复权限

**网络错误**:
- **症状**: 下载失败，连接超时
- **原因**: 网络问题或服务器问题
- **解决**: 检查网络连接，重试下载

**资源不足**:
- `症状`: OOM, 磁盘空间不足
- **原因**: 资源限制
- **解决**: 增加资源，清理空间

### 16.2 调试技巧

**启用调试模式**:
```bash
RUST_LOG=debug cargo build
```

**检查构建缓存**:
```bash
sccache --show-stats
```

**清理构建缓存**:
```bash
cargo clean
sccache --zero-stats
```

**重新构建**:
```bash
cargo build --rebuild
```

---

## 17. 参考资源

### 17.1 官方文档

- **Rust 编译指南**: https://rustc-dev-guide.rust-lang.org/
- **Rust 构建系统**: https://rust-lang.github.io/rustc/
- **OpenHarmony 文档**: https://docs.openharmony.cn/

### 17.2 源码参考

- **Rust 源码**: https://github.com/rust-lang/rust
- **OhOS OpenSSL**: https://github.com/ohos-rs/ohos-openssl
- **SCCache**: https://github.com/mozilla/sccache

### 17.3 社区资源

- **Rust 论坛**: https://users.rust-lang.org/
- **Rust Discord**: https://discord.gg/rust-lang
- **OpenHarmony 社区**: https://gitee.com/openharmony

---

## 18. 附录

### 18.1 环境变量完整列表

**构建环境变量**:
- `CI`: CI 环境标识
- `SRC`: 源码目录
- `CARGO_HOME`: Cargo 主目录
- `DEPLOY`: 发布模式标识
- `TOOLSTATE_PUBLISH`: 工具状态发布标识
- `CI_JOB_NAME`: CI 任务名称
- `BASE_COMMIT`: 基础提交哈希
- `CODEGEN_BACKENDS`: 代码生成后端

**目标特定变量**:
- `TARGETS`: 目标架构
- `CC_aarch64_unknown_linux_ohos`: C 编译器
- `AR_aarch64_unknown_linux_ohos`: 归档工具
- `CXX_aarch64_unknown_linux_ohos`: C++ 编译器

**OpenSSL 变量**:
- `AARCH64_UNKNOWN_LINUX_OHOS_OPENSSL_DIR`: OpenSSL 目录
- `AARCH64_UNKNOWN_LINUX_OHOS_OPENSSL_NO_VENDOR`: 禁用 vendored OpenSSL

**SCCache 变量**:
- `SCCACHE_BUCKET`: S3 bucket
- `SCCACHE_REGION`: S3 区域
- `AWS_REGION`: AWS 区域
- `AWS_ACCESS_KEY_ID`: AWS 访问密钥
- `AWS_SECRET_ACCESS_KEY`: AWS 秘密密钥

### 18.2 构建时间估算

**典型构建时间** (4 核心, 16GB RAM):
- **冷构建** (无缓存): 2-3 小时
- **热构建** (有缓存): 30-60 分钟
- **增量构建** (小变更): 10-20 分钟

**构建阶段耗时**:
- 依赖下载: 5-10 分钟
- Stage 0 准备: 5 分钟
- Stage 1 编译: 30-60 分钟
- 标准库编译: 20-40 分钟
- 扩展工具编译: 30-60 分钟
- 产物打包: 5-10 分钟

### 18.3 磁盘空间需求

**构建过程空间需求**:
- **源码**: ~500MB
- **依赖**: ~2GB
- **构建产物**: ~5GB
- **缓存**: ~3GB
- **临时文件**: ~2GB
- **总计**: ~12-15GB

**最终产物大小**:
- **tarball**: ~1-2GB
- **解压后**: ~3-5GB

---

**文档结束**

如有问题或建议，请联系 Rust CI 团队或提交 Issue 到 Rust 仓库。
