# ohos-rust

本项目为 OpenHarmony (鸿蒙) 平台编译 Rust 工具链，并发布预构建包。

**当前版本**: Rust 1.89.0 | **目标平台**: `aarch64-unknown-linux-ohos`

## 获取预构建包

前往 [release 页面](https://github.com/Harmonybrew/ohos-rust/releases) 下载。

## 安装使用

### 方式一：在鸿蒙 PC 中使用

```sh
cd ~
curl -fLO https://github.com/Harmonybrew/ohos-rust/releases/download/1.89.0/rust-1.89.0-aarch64-unknown-linux-ohos.tar.gz
tar -zxf rust-1.89.0-aarch64-unknown-linux-ohos.tar.gz
export PATH=~/rust-1.89.0-aarch64-unknown-linux-ohos/usr/local/bin:$PATH

# 测试
rustc --version
cargo --version
```

### 方式二：在鸿蒙开发板中使用

```sh
# 从 PC 推送到设备
hdc file send rust-1.89.0-aarch64-unknown-linux-ohos.tar.gz /data/local/tmp

# 在设备上安装
hdc shell
cd /data/local/tmp
tar -zxf rust-1.89.0-aarch64-unknown-linux-ohos.tar.gz
export PATH=/data/local/tmp/rust-1.89.0-aarch64-unknown-linux-ohos/usr/local/bin:$PATH
```

### 方式三：在鸿蒙容器中使用

参考 [dockerharmony](https://github.com/hqzing/dockerharmony) 项目。

## 从源码构建

### 方式一：使用 GitHub Actions CI（推荐）

1. Fork 本项目
2. 在 "Actions" 菜单启用工作流
3. 推送代码或手动触发构建

**快速测试流程**：在 Actions 中选择 "Run workflow"，勾选 `dry_run` 选项，可跳过完整编译测试签名流程。

### 方式二：本地 Docker 构建（交叉编译）

```sh
git clone https://github.com/Harmonybrew/ohos-rust.git
cd ohos-rust

# 构建 Docker 镜像
docker build -f x86_64/Dockerfile -t rust-ohos-x86_64 .

# 运行构建
docker run --rm -v "$PWD":/workspace -w /workspace rust-ohos-x86_64 ./x86_64/build.sh

# 快速测试（DRY_RUN 模式）
docker run --rm -v "$PWD":/workspace -w /workspace -e DRY_RUN=true rust-ohos-x86_64 ./x86_64/build.sh
```

### 构建选项

| 环境变量 | 默认值 | 说明 |
|---------|-------|------|
| `DRY_RUN` | `false` | 跳过编译，仅测试签名流程 |
| `STRIP_BINARIES` | `false` | 移除调试符号减小体积 |
| `SCCACHE_REMOTE` | `false` | 启用远程编译缓存 |

**示例**：
```sh
# 带 strip 的完整构建
docker run --rm -v "$PWD":/workspace -w /workspace \
  -e STRIP_BINARIES=true \
  rust-ohos-x86_64 ./x86_64/build.sh
```

## 目录结构

```
ohos-rust/
├── x86_64/                    # x86_64 交叉编译配置
│   ├── Dockerfile             # Docker 构建环境
│   ├── build.sh               # 构建脚本
│   └── scripts/               # 辅助脚本
│       ├── ohos-sdk.sh        # OpenHarmony SDK 安装
│       ├── ohos-openssl.sh    # OpenSSL 安装
│       ├── sccache.sh         # 编译缓存工具
│       └── ohos/              # Clang wrapper
├── patches/                   # Rust 源码补丁
├── tool/                      # 签名工具（打包到产物）
├── install-manual.sh          # 手动安装脚本
├── tmp/                       # 文档和临时文件
│   ├── x86_64-ci-pipeline-detailed.md
│   ├── ohos-rust-release-artifacts.md
│   └── optimization-analysis.md
└── .github/workflows/ci.yml   # GitHub Actions CI
```

## 技术细节

### 编译策略

本项目采用**交叉编译**方式：在 x86_64 Ubuntu Docker 环境中编译 `aarch64-unknown-linux-ohos` 目标。

- **编译器**：OpenHarmony SDK 提供的 Clang (基于 LLVM 18)
- **C 标准库**：musl libc（OHOS 使用 musl）
- **SSL 库**：ohos-openssl（预构建 ARM64 版本）

### 签名要求

OpenHarmony 要求所有 ELF 二进制文件必须签名才能运行。本项目：
1. 在构建时使用 `binary-sign-tool` 进行自签名 (`-selfSign 1`)
2. 将签名工具打包到产物中，用户可在目标机器上重新签名

**注意**：鸿蒙签名可能与文件路径绑定。如遇到签名失效，请使用产物中的 `tool/binary-sign-tool` 重新签名。

## 常见问题

### 1. 部分 cargo crates 无法正常使用

本项目未对 Rust 进行"鸿蒙适配"，仅使用 OHOS SDK 重新编译。Rust 沿用 `aarch64-linux-musl` 的业务逻辑，下载的 crates 也是 musl 版本。

基于鸿蒙对 Linux 的兼容性，大多数 crates 可正常工作，但部分含 C 依赖的 crates 可能有问题。

### 2. 软件包路径问题

Rust 编译时会硬编码 `prefix` 路径。本项目的 `prefix` 是 `/usr/local`。

如遇到路径相关问题：
- **方案一**：将产物中的 `usr/local` 目录移动到你期望的位置，并设置 `PATH`
- **方案二**：修改 `install.sh` 的安装位置后重新打包

### 3. CI 构建时间过长

完整编译约需 60-120 分钟。优化措施：
- Docker 层缓存（已实施）
- sccache 编译缓存（已实施，支持远程缓存）
- DRY_RUN 模式快速测试（已实施）

如需启用远程 sccache 缓存，需配置 S3 兼容存储和 AWS 凭证。

## 相关项目

- [dockerharmony](https://github.com/hqzing/dockerharmony) - 鸿蒙开发容器
- [ohos-openssl](https://github.com/Harmonybrew/ohos-openssl) - 鸿蒙版 OpenSSL

## 许可证

Rust 采用 Apache-2.0/MIT 双许可。本项目构建脚本采用 MIT 许可证。