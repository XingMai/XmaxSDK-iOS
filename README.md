# XmaxSDK for iOS

XmaxSDK 的原生 iOS 实现。1.0.0 版本支持 CocoaPods 和 Manual 两种接入方式，暂不支持 Swift Package Manager。

## 开发基线

- Swift 6 language mode
- iOS 15.0+
- UIKit 示例工程

## 目录

```text
Sources/XmaxSDK
├── Core
├── Rendering
├── Transport
├── Media
├── Service
└── Foundation
```

目录按实际能力逐步创建，不添加空模块或占位类型。

## CocoaPods 本地开发

```bash
pod install --project-directory=Examples/XLab
xcodebuild -workspace Examples/XLab/XLab.xcworkspace -scheme XLab \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

XLab 通过 `pod 'XmaxSDK', path: '../..'` 接入当前仓库的 SDK 源码。请使用
`Examples/XLab/XLab.xcworkspace` 打开示例工程。

## 支持的分发方式

- CocoaPods：推荐的默认接入方式。
- Manual：后续提供 XmaxSDK 发行包及独立接入文档。
- Swift Package Manager：1.0.0 暂不支持。

火山 RTC 和腾讯 COS 的二进制依赖将在版本与分发许可确认后接入。公开 API、生命周期和错误边界以跨平台架构规范及 HarmonyOS 基准实现为准。
