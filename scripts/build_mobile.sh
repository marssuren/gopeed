#!/bin/bash

# 设置变量
PROJECT_ROOT="$(pwd)"
OUTPUT_DIR="$PROJECT_ROOT/build/mobile"
GOMOBILE_AAR_OUTPUT="$OUTPUT_DIR/libgopeed_ipfs.aar"
PACKAGE_NAME="github.com/GopeedLab/gopeed/bind/mobile"
JAVA_PACKAGE="org.gopeed.libgopeed"

# 确保构建目录存在
mkdir -p "$OUTPUT_DIR"

# 确保所有Go模块依赖已下载
echo "下载Go依赖..."
go mod download
go mod tidy

# 初始化gomobile
echo "初始化 gomobile..."
go install golang.org/x/mobile/cmd/gomobile@latest
gomobile init

# 为Android构建AAR包
echo "构建Android AAR包..."
gomobile bind \
  -tags nosqlite \
  -ldflags="-w -s -checklinkname=0" \
  -o "$GOMOBILE_AAR_OUTPUT" \
  -target=android \
  -androidapi 21 \
  -javapkg="$JAVA_PACKAGE" \
  "$PACKAGE_NAME"

if [ $? -eq 0 ]; then
    echo "成功生成AAR文件: $GOMOBILE_AAR_OUTPUT"
    echo "你可以将此AAR文件复制到Flutter项目中使用"
    
    # 为Flutter项目创建libs目录并复制AAR
    FLUTTER_LIBS_DIR="$PROJECT_ROOT/ui/flutter/android/app/libs"
    mkdir -p "$FLUTTER_LIBS_DIR"
    cp "$GOMOBILE_AAR_OUTPUT" "$FLUTTER_LIBS_DIR/"
    echo "已复制AAR文件到Flutter项目: $FLUTTER_LIBS_DIR"
else
    echo "构建AAR文件失败"
    exit 1
fi

exit 0