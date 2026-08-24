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

## CocoaPods 接入

由于火山 RTC 使用独立的 CocoaPods Specs 仓库，接入方需要在 `Podfile`
顶部声明两个官方源：

```ruby
source 'https://github.com/volcengine/volcengine-specs.git'
source 'https://cdn.cocoapods.org/'

platform :ios, '15.0'

use_frameworks!

target 'YourApp' do
  pod 'XmaxSDK', '0.1.0'
end

# Xcode 27 no longer accepts the lower deployment targets declared by the
# current COS and RTC podspecs. Keep generated Pods targets aligned with
# XmaxSDK's iOS 15 minimum.
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |configuration|
      configuration.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
      configuration.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = ''
    end
  end
end
```

XmaxSDK 当前锁定以下官方依赖：

- `VolcEngineRTC 3.60.106.600`：Core、RealXBase 和 RTCFFmpeg。
- `QCloudCOSXML/Transfer 6.5.7`：无 Beacon 的上传下载精简版。

> `QCloudCOSXML 6.5.7` 的官方 podspec 会为宿主 Target 设置
> `EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64`。使用 Apple Silicon 模拟器时，
> 请在 App Target 的 Build Settings 中将该项覆盖为空。XLab 已包含此覆盖；
> 真机编译不需要处理。

## 支持的分发方式

- CocoaPods：推荐的默认接入方式。
- Manual：后续提供 XmaxSDK 发行包及独立接入文档。
- Swift Package Manager：1.0.0 暂不支持。

火山 RTC 和腾讯 COS 均由 CocoaPods 从各自官方源下载，本仓库不托管、
打包或再分发第三方二进制。公开 API、生命周期和错误边界以跨平台架构规范及
HarmonyOS 基准实现为准。第三方版权及许可声明见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
