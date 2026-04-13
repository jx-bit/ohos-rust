#!/bin/sh
set -ex

URL=https://cidownload.openharmony.cn/version/Master_Version/OpenHarmony_6.1.0.31/20260311_020435/version-Master_Version-OpenHarmony_6.1.0.31-20260311_020435-ohos-sdk-full_6.1-Release.tar.gz

curl -fL -o /tmp/ohos-sdk-full.tar.gz $URL
tar -zxf /tmp/ohos-sdk-full.tar.gz -C /opt
rm /tmp/ohos-sdk-full.tar.gz

cd /opt/ohos-sdk

# 仅删除 Windows 组件，保留 linux 和 ohos
rm -rf windows

# 解压 Linux 主机工具链（交叉编译器 clang、签名工具等）
cd linux
unzip -q native-linux-x64-*.zip
unzip -q toolchains-linux-x64-*.zip 2>/dev/null || true
rm -rf *.zip

# SDK 6.1 将 x86_64 工具链放在 linux/native 下
# 为了兼容旧版脚本 (期望 /opt/ohos-sdk/native)，创建软链接
ln -sf linux/native /opt/ohos-sdk/native

cd ../ohos
unzip -q native-*.zip
unzip -q toolchains-*.zip
rm -rf *.zip
