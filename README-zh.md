# ArtCNNMetal

[English](README.md) | [简体中文](README-zh.md)

基于 Apple Metal 的 ArtCNN C4F16 2× 图像超分，提供 Swift Package 和 macOS 命令行工具。

Swift API 可接入图像工具、视频播放器和处理流水线，处理 `CVPixelBuffer` 视频帧或 `CGImage` 图像；命令行工具可直接放大图片，也可在脚本中批量调用。Metal 资源、模型来源及许可证随包提供。

## 使用

通过 `.package(url: "https://github.com/cinemore/artcnn-metal.git", exact: "0.1.0")` 引入 `ArtCNNMetal` product；本机开发也可使用 `.package(path: "../artcnn-metal")`：

```swift
import ArtCNNMetal
let upscaler = try ArtCNNUpscaler()
let output = try upscaler.enhance(pixelBuffer: input)
let imageOutput = try upscaler.enhance(image: image)
```

固定 C4F16 模型及原生 2× 尺寸，权重内嵌，不需要下载模型。视频输入要求 BT.601／BT.709 矩阵，或带 BT.709 primaries 的 BGRA。未知矩阵拒绝处理。

高层入口内部串行并等待 GPU 完成，每次返回独立输出，不改写原图或先前结果；支持 BGRA 和 VideoToolbox 可转换的像素缓冲，保留显示／颜色附件并缩放 clean aperture。CGImage 入口转为 sRGB BGRA。仅支持 SDR；拒绝 HDR／杜比元数据。

底层 `ArtCNNEngine` 接收调用方的纹理和 command buffer，不代为提交或等待。单实例须串行编码，GPU 完成后才可复用工作区。调用方可提供串行 encoder 和 outputOriginX，在同一 encoder 中继续绘制 A/B 原画侧；内部卷积仍处理完整输入。应用可按自身流水线配置任务调度、取消策略和输出缓冲池。

## 命令行和分发

```sh
swift run artcnn-metal --input input.png --output output.png
swift run artcnn-metal --self-test
swift run artcnn-metal --input input.png --output output.png --bench 5
```

始终输出原生 2×。 发布工作流生成 arm64、x86_64、universal 二进制归档，程序与资源 bundle 必须放在相邻位置。通过共享 Homebrew tap 安装：

```sh
brew install cinemore/tap/artcnn-metal
artcnn-metal --self-test
```

## 验证与治理

```sh
swift test
swift build -c release --product artcnn-metal
.build/release/artcnn-metal --self-test
bun tools/release.ts v0.1.0
```

发布工具采用 Bun／TypeScript。归档、真实 SHA256、manifest 及 Homebrew 配方位于 dist/v0.1.0/；local/Formula 使用同一归档的本地文件 URL，可独立验证安装。重复 staging 目录会被拒绝，避免覆盖已有结果。

CI 包含包测试、Release CLI 的真实 GPU 自检和 iOS 库构建。验证后推送版本 tag 才触发公开发布。HOMEBREW_TAP_TOKEN 配置为共享 cinemore/homebrew-tap 的写权限后，工作流自动提交本包的配方；未配置时，Release 仍附带配方。完整参数、底层接口所有权及发布流程见 [English README](README.md)，实际设备验证边界见 [VALIDATION.md](VALIDATION.md)。

MIT；上游来源、固定模型 revision 和完整许可见 [THIRD-PARTY.md](THIRD-PARTY.md)。
