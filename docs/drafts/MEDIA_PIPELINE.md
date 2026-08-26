# 图片与视频采集链路（临时草稿）

> 状态：临时设计稿，用于后续优化图片与文件视频 Pipeline。
>
> 基线提交：`cc35183 feat: add image and video media pipelines`

当前图片和文件视频都被抽象为“本地外部视频源”。Media 层只产生中性
音视频帧，Core 组装根把帧监听器连接到
`TransportController → StreamController → RtcManager → VolcEngineRTC`
传输链路；Media 与 Transport 之间没有直接依赖。

```text
XmaxRealtimeManaging 公开 API
        │
        ▼
XmaxRealtimeManager
连接、替换、生成生命周期以及业务层组装
        │
        ├── MediaController
        │   保证相机 / 图片 / 视频只存在一个活动来源
        │       ├── 图片：ImageController
        │       │          └── ImageSourceController
        │       │                 └── ImageManager.decode()
        │       │                        └── DecodedImage → BGRA 帧
        │       └── 视频：VideoController
        │                  └── MediaSourceController
        │                         ├── VideoSourceController → NV12 帧
        │                         └── AudioSourceController → PCM 音频帧
        │
        └── TransportController
            统一传输层入口
                    ▲
                    └── Core 注入的中性音视频帧监听器
        │
        ▼
StreamController
        │
        ▼
RtcManager → 火山 RTC
        ├── 外部视频推帧
        └── 外部音频推帧

VideoRenderRegistry → XmaxVideoView
        ├── 图片轨道：UIImageView
        └── 摄像头、视频和远端轨道：RTC Canvas
```

## 1. 统一入口和资源所有权

接入方通过 `XmaxRealtimeManaging` 调用：

```swift
let stream = try await realtime.createLocalImageStream(
    imageData: imageData
)

// 或者
let stream = try await realtime.createLocalImageStream(
    image: image
)

// 或者
let stream = try await realtime.createLocalImageStream(
    fileURL: imageURL
)

// 文件视频
let stream = try await realtime.createLocalVideoStream(
    fileURL: videoURL
)
```

也可以显式指定目标视频格式：

```swift
let format = RealtimeVideoFormat(
    width: 832,
    height: 1472,
    fps: 24
)

let stream = try await realtime.createLocalVideoStream(
    fileURL: videoURL,
    videoFormat: format
)
```

`MediaController` 负责统一所有权：

- 相机、图片、视频只能有一个活动来源。
- 首次创建来源时初始化 RTC Engine。
- 同类型或跨类型替换复用 RTC Engine。
- `disconnect()` 只断开 Session/Room，保留本地来源和预览。
- 必须断开连接后才能彻底调用 `stopLocalImageStream()` 或 `stopLocalVideoStream()`。
- 最终停止本地来源时才销毁 RTC Engine。

相关实现：

- `Sources/XmaxSDK/Core/Realtime/XmaxRealtimeManaging.swift`
- `Sources/XmaxSDK/Core/Realtime/XmaxRealtimeManager.swift`
- `Sources/XmaxSDK/Media/MediaController.swift`

## 2. 图片链路

```text
createLocalImageStream(imageData:/image:/fileURL:, videoFormat:)
    ↓
MediaController
    ↓
ImageController
    ↓
ImageSourceController.prepare()
    ↓
ImageManager.decode()
    ↓
DecodedImage
    ↓
固定 BGRA 视频帧
    ↓
定时重复推送
    ↓
Core 注入的 MediaVideoFrameListener
    ↓
TransportController.pushLocalVideoFrame()
    ↓
StreamController.pushLocalVideoFrame()
    ↓
RtcManager.pushExternalVideoFrame()
```

### 2.1 图片读取与尺寸处理

`ImageSourceController` 执行以下步骤：

1. 将输入收敛为内部 `DecodedImage`：
   - `imageData` 通过 `ImageManager.decode()` 解码。
   - `fileURL` 读取为 `Data` 后解码。
   - `UIImage` 直接提取或规范化像素，不经过 PNG/JPEG 中转。
2. 解码时应用图片方向，并保留实际像素尺寸。
3. 确定候选输出格式：
   - 没有传入 `videoFormat`：使用图片原始尺寸和默认 `24fps`。
   - 传入 `videoFormat`：使用指定宽高和帧率。
4. 通过 `MediaService.resolveModelInputSize()` 调整尺寸：
   - 像素数不足 600,000 时放大。
   - 像素数超过 1,280,000 时缩小。
   - 宽高分别对齐到 32。
5. 将图片按 `.fill` 方式居中裁剪并缩放到目标尺寸。
6. 转换为单平面的 BGRA 数据。

### 2.2 图片持续推帧

准备完成后：

- 立即推送第一帧。
- 创建独立输出任务。
- 默认每秒推送 24 次同一张 BGRA 图片。
- 每帧使用当前单调时钟生成新的 `timestampUs`。
- 图片只转换一次，不会在每次推帧时重新解码和缩放。

### 2.3 RTC 与预览

`ImageController` 按以下顺序创建图片流：

1. 准备图片并获得最终视频格式。
2. 调用 `useExternalVideoSource()`。
3. 创建 `RealtimeVideoTrack(id: "video0")`。
4. 使用同一份 BGRA 帧数据注册 `UIImageView` 本地预览绑定。
5. 开始持续产生图片帧。

图片帧通过 Core 在组装阶段注入的 `MediaVideoFrameListener` 交给 Transport。
`ImageController` 和 `MediaController` 都不依赖 `TransportControlling`。

`XmaxVideoView` 根据轨道绑定自动选择图片或 RTC 渲染，接入方不需要判断
媒体来源。图片预览不会重复解码，也不会占用 RTC 本地 Canvas。图片没有 SDK
管理的音频，因此连接时只发布视频。

相关实现：

- `Sources/XmaxSDK/Media/Image/ImageController.swift`
- `Sources/XmaxSDK/Media/Image/ImageSourceController.swift`
- `Sources/XmaxSDK/Foundation/Media/Image/ImageManager.swift`

## 3. 视频链路

```text
createLocalVideoStream(fileURL:, videoFormat:)
    ↓
VideoController
    ↓
MediaSourceController.prepare()
    ├── MediaFileMetadataManager
    ├── VideoSourceController.configure()
    └── AudioSourceController.configure()（有音轨时）
    ↓
共享 MediaTimeline
    ├── VideoFileFrameDecoder → NV12
    └── AudioFileFrameDecoder → PCM16
    ↓
TransportController
    ↓
StreamController
    ↓
RtcManager
```

### 3.1 读取视频元数据

`MediaFileMetadataManager` 使用 AVFoundation 读取：

- 视频原始宽高。
- `preferredTransform` 对应的 0/90/180/270 度旋转。
- 文件时长。
- 是否包含音频轨道。

如果旋转角度是 90 或 270 度，计算默认输出比例时会交换宽高。

### 3.2 确定视频格式

规则和图片基本一致：

- 未指定格式：采用视频显示尺寸和默认 `24fps`。
- 指定格式：采用传入的宽高和 fps 作为候选格式。
- 最终通过 `MediaService.resolveModelInputSize()` 对齐模型尺寸。

这里的目标格式用于 RTC 编码配置。

视频解码帧仍然保持源文件的 NV12 分辨率和旋转信息，由 RTC 根据编码配置执行缩放和编码；图片则会在进入 RTC 前直接处理成最终尺寸。

### 3.3 建立共享音视频时间线

`MediaTimeline` 为视频和音频提供同一个播放锚点：

- 启动时预留 100ms 解码准备时间。
- 循环周期向上对齐到 10ms。
- 第 N 次循环的播放时间为：

```text
初始播放锚点 + N × 对齐后的循环时长
```

视频和音频不会各自以“解码完成时间”开启下一轮，从而避免循环次数增加后逐渐漂移。

### 3.4 视频解码与推帧

`VideoSourceController` 执行以下步骤：

1. 使用 `VideoFileFrameDecoder` 解码文件。
2. 通过 AVFoundation 输出 NV12。
3. 将 NV12 封装成两个平面：
   - Y 平面。
   - UV 平面。
4. 带上媒体文件的旋转信息。
5. 按目标 fps 采样。
6. 落后超过一个目标帧间隔的帧直接丢弃。
7. 通过 `TransportController` 将帧交给内部 `StreamController`。
8. 到达文件末尾后，根据共享时间线创建下一轮 decoder。

最终 RTC 收到的视频帧为：

```text
VideoFrame
├── pixelFormat: NV12
├── plane 0: Y
├── plane 1: UV
├── timestampUs
└── rotation
```

图片和文件视频在解码后都直接使用同一个 `VideoFrame`：图片是单平面 BGRA，
文件视频是双平面 NV12。链路中不再存在图片专用帧、文件视频专用帧或
`VideoFrame` 协议/默认实现这一类只做字段搬运的中间抽象。

### 3.5 音频解码与推帧

如果视频包含音轨，`AudioSourceController` 会：

1. 使用 AVFoundation 解码音频。
2. 统一转换为：
   - 48kHz。
   - 单声道。
   - PCM16。
3. 切分成每帧 10ms，即 480 个采样点。
4. 使用和视频相同的 `MediaTimeline`。
5. 同时送往：
   - `AudioManager`：本地播放。
   - `TransportController`：RTC 外部音频传输入口。

尚未连接房间时，RTC 音频推帧会被传输层忽略，但本地音频仍然播放。连接并发布本地音频后，PCM 帧才真正推给 RTC。

### 3.6 RTC 视频和音频初始化

`VideoController` 按以下顺序创建视频流：

1. 准备媒体文件。
2. 如果有音轨，申请麦克风权限。
3. 启用 RTC 外部视频源。
4. 如果有音轨，启用 RTC 外部音频源。
5. 注册本地预览。
6. 同时启动音视频 decoder。
7. 创建本地 `RealtimeMediaStream`。

视频没有音轨时，不会：

- 申请麦克风权限。
- 启动 RTC 外部音频源。
- 发布本地音频。

相关实现：

- `Sources/XmaxSDK/Media/Video/VideoController.swift`
- `Sources/XmaxSDK/Media/MediaSourceController.swift`
- `Sources/XmaxSDK/Media/MediaTimeline.swift`
- `Sources/XmaxSDK/Media/Video/VideoSourceController.swift`
- `Sources/XmaxSDK/Media/Audio/AudioSourceController.swift`
- `Sources/XmaxSDK/Foundation/Media/Video/VideoFileFrameDecoder.swift`
- `Sources/XmaxSDK/Foundation/Media/Audio/AudioFileFrameDecoder.swift`

## 4. 连接后的发布

调用：

```swift
let remoteStream = try await realtime.connect(
    localStream: localStream
)
```

连接时，`XmaxRealtimeManager` 会查询：

```swift
await mediaController.hasAudio
```

随后由 Core 使用本地 Track 的最终 `videoFormat` 调用：

```swift
transportController.setVideoEncoderConfig(videoFormat)
```

编码配置属于连接和发布准备，不由相机、图片或视频 Controller 执行。已连接
状态下更新相机采集格式时，Core 会同步更新 Transport 编码配置。

发布规则：

| 本地来源 | 发布视频 | 发布音频 |
| --- | ---: | ---: |
| 相机 | 是 | 否 |
| 图片 | 是 | 否 |
| 无音轨视频 | 是 | 否 |
| 有音轨视频 | 是 | 是 |

目前相机链路还没有麦克风音频，因此相机只发布视频。

## 5. 生成时的行为

调用：

```swift
try await realtime.startGeneration(
    context: RealtimeContext(...)
)
```

执行顺序：

```text
创建 taskID 和 SEI 状态
    ↓
向房间发送 start generation
    ↓
如果当前来源是视频，重新建立 MediaTimeline
    ↓
视频和音频同时从文件起点开始
    ↓
后续视频帧携带当前 taskID 对应的 SEI
    ↓
等待远端生成流确认
```

图片来源不需要重启，因为它始终输出同一帧。

视频来源会调用：

```swift
mediaController.restartForGeneration()
```

这会：

- 清空本地待播放音频。
- 释放当前音视频 decoder。
- 创建新的共享时间线。
- 音频和视频同时从文件开头重新播放。

## 6. 媒体来源更新

图片和视频只提供创建与停止接口。更换来源时显式执行：

```swift
await realtime.disconnect()
try await realtime.stopLocalImageStream()
let stream = try await realtime.createLocalVideoStream(fileURL: videoURL)
_ = try await realtime.connect(localStream: stream)
```

相机仍可在相机 Track 语义下更新采集参数：

```swift
try await realtime.replaceLocalCameraStream(videoFormat: format)
```

不为 Data、UIImage、图片文件和视频文件分别增加 replace 变体。更换图片或
视频来源由接入方明确控制 disconnect、stop、create 和 connect 生命周期。

## 7. 当前尚未完成的部分

核心采集和 RTC 推送链路已经具备，但还有以下接入和体验工作：

- XLab 需要把视频文件选择、创建和停止按钮接到公开 API。
- 鸿蒙版“开始生成时冻结视频首帧、远端结果出现后解除冻结”的预览优化尚未实现。

因此当前状态是：图片与视频可以进入 RTC、预览、连接和生成生命周期；下一步可以接入 XLab 做真机端到端调试，并基于本稿继续优化 Pipeline。

## 8. 待讨论与优化项

跨平台修改项统一记录在 `CROSS_PLATFORM_ALIGNMENT.md`，本文件仅维护媒体管线本身的设计和待优化事项。

- [ ] 明确图片和视频的默认输出格式策略。
- [ ] 明确显式 `videoFormat` 是严格输出值还是模型约束前的期望值。
- [ ] 评估视频在 SDK 内预缩放与交给 RTC 缩放的性能和画质差异。
- [ ] 实现生成等待期间的视频首帧冻结。
- [ ] 完成 XLab 图片与视频端到端调试入口。
