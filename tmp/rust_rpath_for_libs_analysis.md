# Rust rpath 配置详细分析

## 概述

本文档详细分析了 Rust 1.89.0 源码中 `--set rust.rpath=true` 配置的工作原理，以及在 OpenHarmony 构建中的应用。

## 重要发现

**正确的配置项：** `--set rust.rpath=true`

经过对 Rust 1.89.0 源码的全面搜索，发现以下 rpath 相关配置：

1. `rust.rpath` - 控制是否为 rustc 和工具链构建 rpath
2. `target.rpath` - 控制特定目标的 rpath 配置

**注意：** 之前构建脚本中使用的 `--set rust.rpath-for-libs=true` 配置项在 Rust 1.89.0 中不存在，已修正为正确的 `--set rust.rpath=true`。

## 实际存在的 rpath 配置

### 1. 配置文件定义

**文件位置：** `src/bootstrap/src/core/config/toml/rust.rs`

```rust
define_config! {
    struct Rust {
        // ... 其他配置 ...
        rpath: Option<bool> = "rpath",
        // ... 其他配置 ...
    }
}
```

**文件位置：** `src/bootstrap/src/core/config/toml/target.rs`

```rust
pub struct Target {
    // ... 其他配置 ...
    pub rpath: Option<bool>,
    // ... 其他配置 ...
}
```

### 2. 配置解析

**文件位置：** `src/bootstrap/configure.py`

```python
o("rpath", "rust.rpath", "build rpaths into rustc itself")
```

这个配置通过 `--set rust.rpath=true` 或 `--set rust.rpath=false` 来设置。

### 3. 配置使用

**文件位置：** `src/bootstrap/src/core/config/config.rs`

```rust
pub fn rpath_enabled(&self, target: TargetSelection) -> bool {
    self.target_config.get(&target).and_then(|t| t.rpath).unwrap_or(self.rust_rpath)
}
```

这个函数决定是否启用 rpath，优先使用目标特定的配置，如果没有则使用全局配置。

## rpath 的工作原理

### 1. rpath 的添加

**文件位置：** `src/bootstrap/src/core/builder/cargo.rs`

```rust
// Dealing with rpath here is a little special, so let's go into some
// detail. First off, `-rpath` is a linker option on Unix platforms
// which adds to the runtime dynamic loader path when looking for
// dynamic libraries. We use this by default on Unix platforms to ensure
// that our nightlies behave the same on Windows, that is they work out
// of box. This can be disabled by setting `rpath = false` in `[rust]`
// table of `bootstrap.toml`
//
// Ok, so astute might be wondering "why isn't `-C rpath` used
// here?" and that is indeed a good question to ask. This codegen
// option is the compiler's current interface to generating an rpath.
// Unfortunately it doesn't quite suffice for us. The flag currently
// takes no value as an argument, so the compiler calculates what it
// should pass to the linker as `-rpath`. This unfortunately is based on
// the **compile time** directory structure which when building with
// Cargo will be very different than the **runtime** directory structure
//
// All that's a really long winded way of saying that if we use
// `-Crpath` then executables generated have the wrong rpath of
// something like `$ORIGIN/deps` when in fact the way we distribute
// rustc requires the rpath to be `$ORIGIN/../lib`.
//
// So, all in all, to set up the correct rpath we pass the linker
// argument manually via `-C link-args=-Wl,-rpath,...`. Plus isn't it
// fun to pass a flag to a tool to pass a flag to pass a flag to a tool
// to change a flag in a binary?
if builder.config.rpath_enabled(target) && helpers::use_host_linker(target) {
    let libdir = builder.sysroot_libdir_relative(compiler).to_str().unwrap();
    let rpath = if target.contains("apple") {
        // Note that we need to take one extra step on macOS to also pass
        // `-Wl,-instal_name,@rpath/...` to get things to work right. To
        // do that we pass a weird flag to the compiler to get it to do
        // so. Note that this is definitely a hack, and we should likely
        // flesh out rpath support more fully in the future.
        self.rustflags.arg("-Zosx-rpath-install-name");
        Some(format!("-Wl,-rpath,@loader_path/../{libdir}"))
    } else if !target.is_windows()
        && !target.contains("cygwin")
        && !target.contains("aix")
        && !target.contains("xous")
    {
        self.rustflags.arg("-Clink-args=-Wl,-z,origin");
        Some(format!("-Wl,-rpath,$ORIGIN/../{libdir}"))
    } else {
        None
    };
    if let Some(rpath) = rpath {
        self.rustflags.arg(&format!("-Clink-args={rpath}"));
    }
}
```

### 2. rpath 的作用

**$ORIGIN 的含义：**
- `$ORIGIN` 是一个特殊的 rpath 变量
- 它代表可执行文件或动态库所在的目录
- 在运行时被动态链接器解析为实际路径

**不同平台的 rpath 设置：**

1. **Linux/Unix（非 Windows、Cygwin、AIX、Xous）：**
   ```
   -Wl,-z,origin
   -Wl,-rpath,$ORIGIN/../lib
   ```
   - `-z,origin` 启用 `$ORIGIN` 支持
   - `-rpath,$ORIGIN/../lib` 设置相对于可执行文件的库路径

2. **macOS：**
   ```
   -Zosx-rpath-install-name
   -Wl,-rpath,@loader_path/../lib
   ```
   - `@loader_path` 是 macOS 的 `$ORIGIN` 等价物
   - `-Zosx-rpath-install-name` 是 Rust 特殊的 macOS 处理

3. **Windows/Cygwin/AIX/Xous：**
   - 不设置 rpath（这些平台有不同的动态库查找机制）

### 3. 目录结构说明

**编译时目录结构：**
```
rustc-$RUST_VERSION-src/
├── build/
│   └── <arch>-unknown-linux-ohos/
│       └── stage2/
│           ├── bin/
│           │   └── rustc          ← 可执行文件
│           └── lib/               ← 库文件
```

**运行时目录结构（分发包）：**
```
rust-$RUST_VERSION-ohos-arm64/
├── bin/
│   └── rustc                  ← 可执行文件
└── lib/                       ← 库文件
    ├── libstd-*.so
    ├── librustc_*.so
    └── ...                     ← 其他依赖库
```

**rpath 解析示例：**

对于 `rustc-$RUST_VERSION-ohos-arm64/bin/rustc`：
- `$ORIGIN` = `/path/to/rust-$RUST_VERSION-ohos-arm64/bin`
- `$ORIGIN/../lib` = `/path/to/rust-$RUST_VERSION-ohos-arm64/lib`

这样 rustc 可执行文件就能找到同目录下的 `lib` 目录中的所有库文件。

## 正确的配置方式

### 正确的配置
```bash
--set rust.rpath=true
```

### 配置文件方式
```toml
[rust]
rpath = true
```

或针对特定目标：
```toml
[target.aarch64-unknown-linux-ohos]
rpath = true
```

## 配置的影响

### 当 `rust.rpath = true` 时：

1. **编译时添加的链接器参数：**
   ```
   -Clink-args=-Wl,-z,origin
   -Clink-args=-Wl,-rpath,$ORIGIN/../lib
   ```

2. **运行时行为：**
   - rustc 可执行文件会自动查找 `$ORIGIN/../lib` 目录
   - 不需要设置 `LD_LIBRARY_PATH` 环境变量
   - 实现了可移植性（可以安装到任意位置）

3. **分发包结构：**
   ```
   rust-$RUST_VERSION-ohos-arm64/
   ├── bin/
   │   ├── rustc
   │   ├── cargo
   │   └── ...
   └── lib/
       ├── libstd-*.so
       ├── librustc_*.so
       ├── libssl.so*           ← 依赖库
       ├── libcrypto.so*        ← 依赖库
       └── ...
   ```

### 当 `rust.rpath = false` 时：

1. **不添加 rpath 链接器参数**

2. **运行时行为：**
   - rustc 可执行文件不会自动查找库文件
   - 需要手动设置 `LD_LIBRARY_PATH` 环境变量
   - 不可移植（依赖固定路径）

3. **使用方式：**
   ```bash
   export LD_LIBRARY_PATH=/path/to/rust/lib:$LD_LIBRARY_PATH
   /path/to/rust/bin/rustc
   ```

## 在 OpenHarmony 构建中的应用

### 问题背景

在 OpenHarmony 上构建 Rust 时，我们需要：

1. **编译 OpenSSL 和 zlib 等依赖库**
2. **将这些依赖库复制到 Rust 的 lib 目录**
3. **确保 Rust 可执行文件能找到这些依赖库**

### 解决方案

使用 `--set rust.rpath=true` 配置：

```bash
./configure \
    --build=aarch64-unknown-linux-ohos \
    --enable-profiler \
    --disable-docs \
    --tools=cargo,clippy,rustdocs,rustfmt,rust-analyzer,rust-analyzer-proc-macro-srv,analysis,src,wasm-component-ld \
    --enable-extended \
    --enable-sanitizers \
    --set build.print-step-timings \
    --enable-verbose-tests \
    --set build.metrics \
    --enable-verbose-configure \
    --enable-sccache \
    --disable-manage-submodules \
    --enable-locked-deps \
    --enable-cargo-native-static \
    --set rust.codegen-units-std=1 \
    --set dist.compression-profile=balanced \
    --dist-compression-formats=xz \
    --set build.optimized-compiler-builtins \
    --disable-llvm-static-stdcpp \
    --set rust.remap-debuginfo \
    --debuginfo-level-std=1 \
    --set rust.codegen-backends=llvm \
    --set rust.rpath=true \
    --release-channel=stable
```

### 构建流程

1. **编译依赖库到 `/opt/deps`**
   ```bash
   mkdir /opt/deps
   cd /opt/deps
   
   # 编译 OpenSSL
   curl -fLO https://github.com/openssl/openssl/releases/download/openssl-3.3.4/openssl-3.3.4.tar.gz
   tar -zxf openssl-3.3.4.tar.gz
   cd openssl-3.3.4
   ./Configure --prefix=/opt/deps --openssldir=/etc/ssl no-legacy no-module no-engine linux-aarch64
   make -j$(nproc)
   make install_sw
   
   # 编译 zlib
   curl -fLO https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz
   tar -zxf zlib-1.3.1.tar.gz
   cd zlib-1.3.1
   ./configure --prefix=/opt/deps
   make -j$(nproc)
   make install
   ```

2. **编译 Rust（使用 rpath）**
   ```bash
   ./configure \
       --build=aarch64-unknown-linux-ohos \
       --set rust.rpath=true \
       ...
   
   python3 x.py dist --host=aarch64-unknown-linux-ohos --target aarch64-unknown-linux-ohos -j$(nproc)
   ```

3. **提取 Rust 分发包**
   ```bash
   mkdir -p /opt/rust-1.89.0-ohos-arm64
   tar -xf rustc-1.89.0-src/build/dist/rust-1.89.0-aarch64-unknown-linux-ohos.tar.gz \
       -C /opt/rust-1.89.0-ohos-arm64 --strip-components=1
   ```

4. **复制依赖库到 Rust 目录**
   ```bash
   cp /opt/deps/lib/*so* /opt/rust-1.89.0-ohos-arm64/lib
   ```

5. **打包最终产物**
   ```bash
   cp -r /opt/rust-1.89.0-ohos-arm64 ./
   tar -zcf rust-1.89.0-ohos-arm64-native.tar.gz rust-1.89.0-ohos-arm64
   ```

### 运行时行为

用户下载并解压后：

```bash
tar -zxf rust-1.89.0-ohos-arm64-native.tar.gz
cd rust-1.89.0-ohos-arm64
export PATH=$(pwd)/bin:$PATH

# 现在 rustc 可以正常运行
rustc --version
```

**工作原理：**

1. 运行 `/path/to/rust-1.89.0-ohos-arm64/bin/rustc`
2. rustc 可执行文件查看其 rpath：`$ORIGIN/../lib`
3. `$ORIGIN` 解析为 `/path/to/rust-1.89.0-ohos-arm64/bin`
4. `$ORIGIN/../lib` 解析为 `/path/to/rust-1.89.0-ohos-arm64/lib`
5. 在这个目录找到所有依赖库：
   - `libstd-*.so`（Rust 标准库）
   - `librustc_*.so`（Rust 编译器库）
   - `libssl.so*`（OpenSSL）
   - `libcrypto.so*`（OpenSSL）
   - `libz.so*`（zlib）

### 可移植性验证

**场景 1：默认安装位置**
```
/opt/rust-1.89.0-ohos-arm64/
├── bin/
│   └── rustc
└── lib/
    └── libssl.so*

运行：/opt/rust-1.89.0-ohos-arm64/bin/rustc
$ORIGIN = /opt/rust-1.89.0-ohos-arm64/bin
$ORIGIN/../lib = /opt/rust-1.89.0-ohos-arm64/lib ✓
```

**场景 2：移动到其他位置**
```
mv /opt/rust-1.89.0-ohos-arm64 /home/user/my-rust

/home/user/my-rust/
├── bin/
│   └── rustc
└── lib/
    └── libssl.so*

运行：/home/user/my-rust/bin/rustc
$ORIGIN = /home/user/my-rust/bin
$ORIGIN/../lib = /home/user/my-rust/lib ✓
```

**场景 3：在 OpenHarmony 设备上使用**
```
hdc file send rust-1.89.0-ohos-arm64-native.tar.gz /data
hdc shell

cd /data
tar -zxf rust-1.89.0-ohos-arm64-native.tar.gz
export PATH=/data/rust-1.89.0-ohos-arm64/bin:$PATH

rustc --version
$ORIGIN = /data/rust-1.89.0-ohos-arm64/bin
$ORIGIN/../lib = /data/rust-1.89.0-ohos-arm64/lib ✓
```

## 技术细节

### 1. 为什么不使用 `-Crpath`？

Rust 编译器提供了 `-Crpath` 选项，但 bootstrap 不使用它，原因如下：

**`-Crpath` 的问题：**
- 不接受参数值
- 编译器自动计算 rpath 路径
- 基于编译时目录结构
- 对于 Cargo 构建会产生错误的路径（如 `$ORIGIN/deps`）

**手动设置 rpath 的优势：**
- 完全控制 rpath 路径
- 可以设置运行时需要的正确路径（`$ORIGIN/../lib`）
- 适应分发包的目录结构

### 2. 链接器参数详解

**`-Wl,-z,origin`**
- 告诉链接器启用 `$ORIGIN` 支持
- `$ORIGIN` 是 ELF 文件的特殊 rpath 变量
- 在运行时被动态链接器解析

**`-Wl,-rpath,$ORIGIN/../lib`**
- 设置运行时动态库搜索路径
- 使用相对路径实现可移植性
- 多个 rpath 可以用冒号分隔

### 3. rpath 的优先级

动态链接器查找库的顺序：

1. **DT_RPATH**（编译时设置的 rpath）
2. **LD_LIBRARY_PATH**（环境变量）
3. **DT_RUNPATH**（如果存在）
4. **系统默认路径**（如 `/lib`, `/usr/lib`）

使用 rpath 可以让程序优先查找相对路径的库，避免依赖系统库。

### 4. 验证 rpath

可以使用 `readelf` 命令查看可执行文件的 rpath：

```bash
readelf -d /path/to/rustc | grep RPATH
```

输出示例：
```
0x000000000000000f (RPATH)              Library rpath: [$ORIGIN/../lib]
```

## 总结

### 关键要点

1. **正确的配置是 `--set rust.rpath=true`**
   - 不存在 `--set rust.rpath-for-libs=true` 配置
   - 这是 Rust 1.89.0 的实际配置方式

2. **rpath 实现可移植性**
   - 使用相对路径 `$ORIGIN/../lib`
   - 不依赖固定的安装路径
   - 可以安装到任意位置

3. **依赖库处理**
   - 编译依赖库到临时目录 `/opt/deps`
   - 复制依赖库到 Rust 的 lib 目录
   - 通过 rpath 自动查找这些库

4. **OpenHarmony 特殊考虑**
   - 系统库可能不完整
   - 需要自包含的发行版
   - rpath 确保运行时能找到依赖库

### 配置对比

| 配置 | 是否存在 | 作用 |
|------|---------|------|
| `--set rust.rpath=true` | ✓ | 为 rustc 和工具链构建 rpath |
| `[target.xxx].rpath=true` | ✓ | 为特定目标构建 rpath |

### 实际应用

在 OpenHarmony 构建中，正确的配置是：

```bash
./configure \
    --build=aarch64-unknown-linux-ohos \
    --set rust.rpath=true \
    ...
```

然后复制依赖库：

```bash
cp /opt/deps/lib/*so* /opt/rust-$RUST_VERSION-ohos-arm64/lib
```

这样就能实现完全可移植的 Rust 分发包，用户可以在任意位置安装使用。
