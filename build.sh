#!/bin/bash
# 构建 AlexToolBox.app：release 构建 → 组装 bundle → ad-hoc 签名。
#
# SwiftUI 的宏插件只在 Xcode 工具链里提供，Command Line Tools 缺失时显式指定 Xcode。
set -euo pipefail

cd "$(dirname "$0")"

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

APP="build/AlexToolBox.app"
CONTENTS="$APP/Contents"

swift build -c release --product AlexToolBox
BIN_PATH=$(swift build -c release --show-bin-path)

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_PATH/AlexToolBox" "$CONTENTS/MacOS/AlexToolBox"
cp Resources/Info.plist "$CONTENTS/Info.plist"

codesign --force --sign - --identifier dev.alexblock.alextoolbox "$APP"
codesign --verify --verbose=1 "$APP"

echo "$(pwd)/$APP"
