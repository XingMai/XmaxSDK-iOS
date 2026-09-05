<p align="right">
  <img src="./docs/images/language/zh-active.svg" alt="简体中文" height="28">
  &nbsp;&nbsp;
  <a href="./README.en.md"><img src="./docs/images/language/en.svg" alt="English" height="28"></a>
</p>

<p align="center">
  <img src="./docs/images/brand/xmax-sdk.png" alt="XmaxSDK — 实时交互视频生成" width="880">
</p>

<p align="center">
  <a href="https://developer.apple.com/ios/"><img src="https://img.shields.io/badge/iOS-15.0%2B-007AFF" alt="iOS 15.0+"></a>
  <a href="https://www.swift.org/"><img src="https://img.shields.io/badge/Swift-6.0-F05138" alt="Swift 6.0"></a>
  <a href="https://platform.xmaxai.com/"><img src="https://img.shields.io/badge/Realtime-AI-FF9500" alt="实时 AI"></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/License-MIT-4C9A2A" alt="MIT 许可证"></a>
</p>

XmaxSDK 是原生 iOS SDK，可接入 Xmax AI 的实时交互视频生成模型。SDK 支持以实时视频流、参考图和用户交互驱动低延迟、高保真的视频变换。只需几行代码，即可在应用中集成实时角色替换、虚拟试穿、混合现实伙伴和交互式图像动画等能力。

## 用 XmaxSDK 构建实时交互视频体验

XmaxSDK 将实时视频生成所需的输入、传输、生成和渲染能力整合到一套 API 中。输入可以来自实时相机、静态图片或本地视频；提示词和参考图定义生成方向，触控手势则可以持续改变画面中的动作。

### 实时转换视频

让摄像头画面或本地视频在播放过程中实时生成新的视觉内容，构建角色替换、虚拟试穿、风格转换和混合现实伙伴等体验。SDK 在应用内同时管理原始输入和生成结果的渲染，便于自然地衔接预览与生成画面。

### 让图片响应你的手势

静态图片也可以成为可交互的动态画布。XmaxSDK 捕获用户在生成画面上的多点触控轨迹，并将轨迹提交给当前生成任务，让图片中的人物或主体跟随手势移动。

<p align="center"><img src="./docs/images/xlab/generation-demo.gif" alt="X-Lab 实时生成演示" width="33%" /><img src="./docs/images/xlab/index-demo.gif" alt="X-Lab 首页演示" width="33%" /><img src="./docs/images/xlab/storage-demo.gif" alt="X-Lab 存储演示" width="33%" /></p>

<br>

## 为什么选择 XmaxSDK？

| 低延迟 | 低成本 | 高保真 |
| --- | --- | --- |
| 面向连续实时交互优化视频链路，让输入、生成与画面反馈紧密衔接。 | 按需启动、更新和停止生成任务，并内置渲染、交互与存储能力，降低运行和接入成本。 | 在视频转换过程中保留主体细节和画面一致性，获得稳定、自然的生成结果。 |

<br>

## 使用 XmaxSDK

### 开始之前

- iOS 15.0 或更高版本
- Swift 6
- Xmax API Key

> [!WARNING]
> 请勿将 Xmax API Key 提交到版本控制系统。请在运行时安全地提供凭证，或使用 Xmax API 签发的临时 Key。详情参阅[身份认证](https://platform.xmaxai.com/docs/authentication)。

### 安装

#### CocoaPods

XmaxSDK 通过 CocoaPods 直接从本 GitHub 仓库分发。请在应用的 `Podfile` 中添加所需的 Specs 源和 XmaxSDK 依赖：

```ruby
source 'https://github.com/volcengine/volcengine-specs.git'
source 'https://cdn.cocoapods.org/'

platform :ios, '15.0'

use_frameworks! :linkage => :static

target 'YourApp' do
  pod 'XmaxSDK',
      :git => 'https://github.com/XingMai/XmaxSDK-iOS.git',
      :tag => '1.0.3'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |configuration|
      configuration.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
      configuration.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = ''
    end
  end
end
```

安装依赖：

```bash
pod install --repo-update
```

打开生成的 `.xcworkspace` 文件并构建应用。

必须使用静态 Framework 链接，以便将 Objective-C `QCloudCOSXML` 依赖暴露为 Swift 可导入的模块。

#### 手动集成

下载 [`XmaxSDK-1.0.3.xcframework.zip`](https://github.com/XingMai/XmaxSDK-iOS/releases/download/1.0.3/XmaxSDK-1.0.3.xcframework.zip)，解压得到 `XmaxSDK.xcframework`，并下载本版本使用的精确第三方依赖：

- [VolcEngineRTC `3.60.106.600`](https://hstob-cdn-tos.volccdn.com/volcengine/VolcEngineRTC/3.60.106.600/VolcEngineRTC.zip)：使用下载包中的 `VolcEngineRTC.xcframework`、`RealXBase.xcframework` 和 `RTCFFmpeg.xcframework`。
- [腾讯云 COS iOS SDK `6.5.7`](https://github.com/tencentyun/qcloud-sdk-ios/releases/download/6.5.7/QCloudCOSXML-6.5.7.zip)：使用官方发布包中的 `QCloudCOSXML.xcframework` 和 `QCloudCore.xcframework`。

在应用 Target 的 **Frameworks, Libraries, and Embedded Content** 中添加这些 Framework，并采用以下嵌入设置：

| Framework | 嵌入设置 |
| --- | --- |
| `XmaxSDK.xcframework` | Do Not Embed |
| `QCloudCOSXML.xcframework` | Do Not Embed |
| `QCloudCore.xcframework` | Do Not Embed |
| `VolcEngineRTC.xcframework` | Embed & Sign |
| `RealXBase.xcframework` | Embed & Sign |
| `RTCFFmpeg.xcframework` | Embed & Sign |

XmaxSDK 和 COS 二进制文件为静态 Framework。三个 VolcEngine 二进制文件为动态 Framework，必须由应用 Target 嵌入并签名。

完成以下配置：

1. 将 **Swift Language Version** 设为 **Swift 6**。
2. 在 **Other Linker Flags** 中添加 `-ObjC`。
3. 链接 `Accelerate.framework`、`CoreMedia.framework`、`CoreTelephony.framework`、`SystemConfiguration.framework`、`libz.tbd` 和 `libc++.tbd`。
4. 将 COS 的 [`PrivacyInfo.xcprivacy`](https://github.com/tencentyun/qcloud-sdk-ios/blob/6.5.7/QCloudCOSXML/PrivacyInfo.xcprivacy) 文件添加到应用 Target。
5. 确认每个 XCFramework 都包含目标平台和架构对应的 Slice。Apple 芯片上的模拟器构建需要 `arm64` 模拟器 Slice。

COS 只需要 `QCloudCOSXML.xcframework` 和 `QCloudCore.xcframework`。请勿添加 `QCloudTrack.xcframework`、`COSBeaconAPI_Base.xcframework` 或 QimeiSDK。导入 XmaxSDK 时必须存在第三方 Framework，因为它的稳定 Swift 模块接口会导入 `QCloudCOSXML` 和 `VolcEngineRTC`。

#### 支持的分发方式

- 支持通过 CocoaPods 源码分发。
- 可通过 GitHub Releases 手动集成 XCFramework。
- 版本 1.0.3 暂不支持 Swift Package Manager。

### 配置隐私权限

使用相机输入时，请在应用的 `Info.plist` 中提供相机用途说明：

```xml
<key>NSCameraUsageDescription</key>
<string>此应用使用相机提供实时视频输入。</string>
```

如果本地视频输入包含音频，还需要提供麦克风用途说明：

```xml
<key>NSMicrophoneUsageDescription</key>
<string>此应用使用麦克风提供实时音频输入。</string>
```

请根据应用实际用途修改这些说明。创建本地媒体流时，XmaxSDK 会检查并请求所需的运行时权限。如果权限不可用，SDK 会报告 `XmaxError`。

### 构建第一个实时生成体验

#### 创建客户端

```swift
import XmaxSDK

let client = XmaxClient(
    configuration: XmaxConfiguration(apiKey: "YOUR_API_KEY")
)

let realtime = client.createRealtimeManager(
    options: RealtimeConfiguration(model: .x2_0)
)
```

实时操作使用 Swift Concurrency，应在宿主应用中由生命周期明确的 `Task` 调用。

可以在实时管理器上注册连接状态和错误监听器：

```swift
await realtime.setStateListener { state in
    print(
        "Xmax realtime state: \(state.connectionState.rawValue), " +
        "session: \(state.sessionID ?? "-"), task: \(state.taskID ?? "-")"
    )
}

await realtime.setErrorListener { error in
    print("Xmax realtime error: \(error.code.rawValue) \(error.message)")
}
```

#### 创建输入流

获得相机权限后，创建实时相机流：

```swift
let localStream = try await realtime.createLocalCameraStream(
    videoFormat: RealtimeVideoFormat(
        width: 704,
        height: 1280,
        fps: 24
    ),
    position: .front
)
```

也可以使用静态图片或本地视频文件作为输入源：

```swift
let imageStream = try await realtime.createLocalImageStream(
    fileURL: imageFileURL
)
let videoStream = try await realtime.createLocalVideoStream(
    fileURL: videoFileURL
)
```

同一时间只能有一个本地输入流处于活动状态。

#### 预览输入

在 UIKit 中，将本地流绑定到 `XmaxRealtimeVideoView`：

```swift
let realtimeVideoView = XmaxRealtimeVideoView(
    localTrack: localStream.videoTrack,
    videoContentMode: .fill
)
```

在 SwiftUI 中，使用 `XmaxRealtimeVideo` 渲染本地和远端轨道：

```swift
XmaxRealtimeVideo(
    localTrack: localStream.videoTrack,
    remoteTrack: remoteVideoTrack,
    videoContentMode: .fill
)
```

#### 开始生成

使用提示词和可选的远程参考图 URL 构建 `RealtimeContext`：

```swift
let remoteStream = try await realtime.startGeneration(
    localStream: localStream,
    context: RealtimeContext(
        prompt: "视频中角色替换成参考图中角色",
        referencePath: referenceImageURL
    )
)
```

在 UIKit 中，将生成轨道赋给同一个实时视频视图：

```swift
realtimeVideoView.remoteTrack = remoteStream.videoTrack
```

在 SwiftUI 中，更新 `XmaxRealtimeVideo` 使用的远端轨道：

```swift
remoteVideoTrack = remoteStream.videoTrack
```

`XmaxRealtimeVideoView` 和 `XmaxRealtimeVideo` 会在生成结果下方保持本地预览；收到首个远端帧后才显示生成结果；当 `remoteTrack` 变为 `nil` 时恢复本地预览。

如果需要在 SDK 外录制或处理生成结果，请在开始生成前注册最终帧监听器：

```swift
await realtime.setRemoteVideoFrameListener { frame in
    recorder.append(
        pixelBuffer: frame.pixelBuffer,
        presentationTimeStamp: frame.presentationTimeStamp,
        duration: frame.duration
    )
}
```

监听器会在专用的串行后台队列中接收最终渲染管线接受的帧，包括可选帧插值处理后的结果。帧时间戳不一定从零开始，因此录制器应以收到的第一帧为基准重设输出时间线。请快速将每帧转交给录制管线，避免在回调中进行同步编码。此 API 当前只提供视频帧，不包含生成音频。

不再需要帧回调时，请清除监听器：

```swift
await realtime.setRemoteVideoFrameListener(nil)
```

如需更新正在运行的生成任务，请提交包含新提示词或参考图的 Context：

```swift
try await realtime.startGeneration(
    context: RealtimeContext(
        prompt: "将人物服装替换成参考图中的服装",
        referencePath: anotherReferenceImageURL
    )
)
```

#### 停止并释放资源

```swift
await realtime.stopGeneration()
await realtime.disconnect()
await realtime.close()
```

`stopGeneration()` 会终止当前生成任务，同时保留远端连接和本地预览。`disconnect()` 会关闭远端会话，同时保留本地预览。`close()` 会释放所有本地媒体和 RTC 资源；实时工作流不再需要时应调用该方法。

### 触控交互

在生成任务运行期间，`XmaxRealtimeVideoView` 和 `XmaxRealtimeVideo` 会捕获生成视频上的多点触控轨迹，并将其提交给当前任务。宿主应用无需自行实现手势追踪或坐标转换。

轨迹交互默认启用。在 UIKit 中，如果触控输入需要由外围界面处理，可将其关闭：

```swift
realtimeVideoView.isInteractionEnabled = false
```

在 SwiftUI 中，构造 `XmaxRealtimeVideo` 时设置 `isInteractionEnabled`：

```swift
XmaxRealtimeVideo(
    localTrack: localStream.videoTrack,
    remoteTrack: remoteVideoTrack,
    isInteractionEnabled: false
)
```

### 上传参考图

`RealtimeContext.referencePath` 需要远程图片 URL。如需使用设备上的图片，请通过存储管理器上传，并提供返回的 URL：

```swift
let storage = try client.createStorageManager()

let uploaded = try await storage.uploadImage(
    at: imageFileURL,
    contentType: "image/jpeg"
)

let referenceImageURL = uploaded.url.absoluteString
```

存储管理器使用从 Xmax 获取的临时凭证。宿主应用中不会嵌入腾讯云凭证。

### 帧插值

在运行 iOS 26 或更高版本的受支持设备上，XmaxSDK 可以对远端生成视频帧进行插值。帧插值默认启用，可在运行时修改：

```swift
try await realtime.setFrameInterpolationEnabled(false)
```

使用 `client.createMediaService().supportsFrameInterpolation(for:)` 检查当前设备是否支持指定视频尺寸的帧插值。

### 日志

SDK 日志默认关闭。创建客户端时，可以启用业务日志、性能日志或两者同时启用：

```swift
let configuration = XmaxConfiguration(
    apiKey: "YOUR_API_KEY",
    loggerOptions: [.business, .performance]
)

let client = XmaxClient(configuration: configuration)
```

日志配置在进程范围内生效，并由所有 `XmaxClient` 实例共享。

<br>

## 示例工程

[`Examples/XLab`](https://github.com/XingMai/XmaxSDK-iOS/tree/main/Examples/XLab) 提供了同时包含 UIKit 和 SwiftUI 实现的可运行示例应用。该应用演示了使用相机、图片和本地视频输入进行实时生成，以及自定义提示词、参考图选择和轨迹渲染。

<p align="center"><img src="./docs/images/xlab/home.jpg" alt="X-Lab 首页" width="20%" /><img src="./docs/images/xlab/features.jpg" alt="X-Lab SDK 功能" width="20%" /><img src="./docs/images/xlab/storage.jpg" alt="X-Lab 存储服务" width="20%" /><img src="./docs/images/xlab/realtime-generation.jpg" alt="X-Lab 实时生成" width="20%" /><img src="./docs/images/xlab/trajectory-generation.jpg" alt="X-Lab 轨迹生成" width="20%" /></p>

<br>

## 第三方依赖

- VolcEngine RTC SDK for iOS 提供实时音视频通信能力。
- 腾讯云 COS SDK 提供通过对象存储传输图片和视频的能力。

<br>

## 联系我们

如需报告 Bug 或提出功能建议，请使用 [GitHub Issues](https://github.com/XingMai/XmaxSDK-iOS/issues)。如有接入问题或需要技术支持，请联系 [sdk@xmax.ai](mailto:sdk@xmax.ai)。

<br>

## 许可证

XmaxSDK 基于 [MIT License](LICENSE) 发布。
