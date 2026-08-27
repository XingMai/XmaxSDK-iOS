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
├── Stream
├── Media
├── Service
└── Foundation
```

目录按实际能力逐步创建，不添加空模块或占位类型。

业务层通过与层同名的 Controller 向 Core 暴露能力。Core 只依赖
`MediaControlling`、`StreamControlling` 和 `RenderControlling`，不直接调用
业务层内部组件。Media 只产生中性音视频帧，Core 在组装阶段将帧监听器连接到
Stream；Media 与 Stream 之间没有直接依赖。

## 远端视频插帧

iOS 26 及以上的受支持设备默认开启远端生成画面的 2 倍帧率插值。SDK 无论
是否开启插帧，远端画面都统一通过解码帧管线交给 `XmaxVideoView` 渲染，因此
运行时切换不会更换 RTC Canvas。

```swift
let realtime = client.createRealtimeManager(
    options: RealtimeConfiguration(
        model: .x2_0,
        isFrameInterpolationEnabled: true
    )
)

try await realtime.setFrameInterpolationEnabled(false)
```

接入方可以通过 `isFrameInterpolationSupported` 查询当前设备的全局能力，或通过
`XmaxClient.createMediaService().supportsFrameInterpolation(for:)` 检查指定
视频尺寸。`MediaService` 将插帧输入限制在 100 万像素以内，以兼容旧版约
90 万像素的 32 对齐规格；初始化时请求开启但实际尺寸不受支持，SDK 会继续
无插帧播放并通过错误监听器上报 `FRAME_INTERPOLATION_UNSUPPORTED`；运行时
显式开启失败则同时抛出该错误。

## CocoaPods 本地开发

```bash
pod install --project-directory=Examples/XLab
xcodebuild -workspace Examples/XLab/XLab.xcworkspace -scheme XLab \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

XLab 通过 `pod 'XmaxSDK', path: '../..'` 接入当前仓库的 SDK 源码。请使用
`Examples/XLab/XLab.xcworkspace` 打开示例工程。

## 日志配置

XmaxSDK 默认不输出日志。接入方可以在创建全局配置时选择需要输出的日志类型：

```swift
let configuration = XmaxConfiguration(
    apiKey: apiKey,
    loggerOptions: [.business, .performance]
)
let client = XmaxClient(configuration: configuration)
```

- `.business`：Room、API、Realtime、Storage 等业务运行日志。
- `.performance`：RTC 视频上下行、网络质量、系统性能及性能告警日志。
- `.all`：输出以上全部日志。
- `[]`：不输出 XmaxSDK 日志，也是默认值。

日志配置为进程级配置，由所有 `XmaxClient` 共享。

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
