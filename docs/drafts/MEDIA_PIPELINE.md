# 图片与视频采集链路（临时草稿）

> 状态：临时设计稿，用于后续优化图片与文件视频 Pipeline。
>
> 基线提交：`cc35183 feat: add image and video media pipelines`
>
> 更新：文件视频使用双 `AVAssetReader` 和共享 `MediaPlaybackTimeline`，当前实现
> 以本文末尾“文件视频统一解码链路”为准。

当前图片和文件视频都被抽象为“本地外部视频源”。Media 层只产生中性
音视频帧，Core 组装根把帧监听器连接到
`StreamController → RtcManager → VolcEngineRTC`
流链路；Media 与 Stream 之间没有直接依赖。

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
        │                         └── VideoPlayerController
        │                                ├── 视频 reader → NV12 帧
        │                                └── 音频 reader → PCM 音频帧
        │
        └── StreamController
            统一流层入口
                    ▲
                    └── Core 注入的中性音视频帧监听器
        │
        ▼
RtcManager → 火山 RTC
        ├── 外部视频推帧
        └── 外部音频推帧

VideoRenderRegistry → XmaxVideoView
        ├── 图片轨道：UIImageView
        ├── 文件视频：AVSampleBufferDisplayLayer
        ├── 摄像头：RTC Canvas
        └── 远端轨道：RTC VideoSink → 远端帧管线
                         ├── 关闭插帧：解码帧直通
                         └── 开启插帧：VideoToolbox x2 插帧
                                      ↓
                              AVSampleBufferDisplayLayer
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

图片帧通过 Core 在组装阶段注入的 `MediaVideoFrameListener` 交给 Stream。
`ImageController` 和 `MediaController` 都不依赖 `StreamControlling`。

`XmaxVideoView` 根据轨道绑定自动选择图片、本地 RTC Canvas 或远端自渲染，
接入方不需要判断媒体来源。图片预览不会重复解码，也不会占用 RTC 本地
Canvas。图片没有 SDK 管理的音频，因此连接时只发布视频。

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
    └── VideoPlayerController.configure()
    ↓
共享 MediaPlaybackTimeline
    ├── 视频 AVAssetReader → NV12
    └── 音频 AVAssetReader → PCM16
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

这里的目标格式同时用于实际视频帧处理、本地预览和 RTC 编码配置。

视频解码帧会在进入 RTC 前按照目标比例居中裁剪、缩放并物理旋转。最终 NV12
的物理宽高就是目标显示宽高，旋转信息重置为 0。本地预览和 RTC 编码因此直接
消费同一份已定向像素，不依赖 RTC 对旋转元数据采用一致的渲染策略。

### 3.3 统一音视频时间轴

文件视频由音频和视频 `AVAssetReader` 解码，两条链路共享同一个单调绝对时间轴、
起点和循环边界。视频处理后的同一份 NV12 帧同时用于本地预览和 RTC；音频切分
后的同一份 10 ms PCM 帧同时用于本地 `AVAudioEngine` 和 RTC。生成开始、Loading、
远端显示和停止生成都不会暂停统一时间轴或覆盖冻结帧；生成期间只停止本地 PCM
的声音输出，播放器、解码和 RTC 推帧继续运行。

### 3.4 视频解码与推帧

`VideoPlayerController` 的视频 reader 执行以下步骤：

1. 使用 `AVAssetReaderTrackOutput` 解码文件。
2. 通过 AVFoundation 输出源文件 NV12。
3. 根据目标显示尺寸和源文件旋转信息确定裁剪、缩放的中间尺寸。
4. 使用 Accelerate/vImage 按目标比例居中裁剪并高质量缩放 NV12：
   - Y 平面使用 `vImageScale_Planar8`。
   - UV 平面使用 `vImageScale_CbCr8`，保持色度分量配对。
5. 将 Y 与 UV 平面物理旋转到最终显示方向：
   - Y 平面使用 `vImageRotate90_Planar8`。
   - UV 平面将 CbCr 作为 16 位像素使用 `vImageRotate90_Planar16U`，保持
     CbCr 配对。
6. 将最终显示尺寸 NV12 封装成两个平面：
   - Y 平面。
   - UV 平面。
7. 将帧旋转信息重置为 0，避免本地预览和编码分别解释旋转元数据。
8. 按目标 fps 采样。
9. 落后超过一个目标帧间隔的帧直接丢弃。
10. 通过 Core 注入的中性视频帧监听器交给 Stream 统一入口。
11. 到达文件末尾后，根据共享时间线创建下一轮 decoder。

最终 RTC 收到的视频帧为：

```text
VideoFrame
├── pixelFormat: NV12
├── plane 0: Y
├── plane 1: UV
├── timestampUs
└── rotation: 0
```

图片和文件视频在解码后都直接使用同一个 `VideoFrame`：图片是单平面 BGRA，
文件视频是双平面 NV12。链路中不再存在图片专用帧、文件视频专用帧或
`VideoFrame` 协议/默认实现这一类只做字段搬运的中间抽象。

### 3.5 音频解码与推帧

如果视频包含音轨，`VideoPlayerController` 的音频 reader 会：

1. 使用 AVFoundation 解码音频。
2. 统一转换为：
   - 48kHz。
   - 单声道。
   - PCM16。
3. 切分成每帧 10ms，即 480 个采样点。
4. 使用和视频相同的 `MediaPlaybackTimeline`。
5. 同时送往：
   - `LocalAudioPreviewPlayer`：本地播放。
   - `StreamController`：RTC 外部音频流入口。

尚未连接房间时，RTC 音频推帧会被流层忽略，但本地音频仍然播放。连接并发布本地音频后，PCM 帧才真正推给 RTC。

### 3.6 RTC 视频和音频初始化

`VideoController` 按以下顺序创建视频流：

1. 准备媒体文件。
2. 如果有音轨，申请麦克风权限。
3. 启用 RTC 外部视频源。
4. 如果有音轨，启用 RTC 外部音频源。
5. 注册本地预览。
6. 同时启动共享时间轴上的音视频 reader。
7. 创建本地 `RealtimeMediaStream`。

`XmaxRealtimeManager` 取得最终 `RealtimeVideoFormat` 后，会在把本地轨道返回给
接入方之前设置 RTC 视频编码格式。因此接入方把轨道绑定到 `XmaxVideoView` 时，
RTC 本地 Canvas 已使用与文件帧相同的显示宽高；建立实时连接时会再次校验并
应用该格式。

视频没有音轨时，不会：

- 申请麦克风权限。
- 启动 RTC 外部音频源。
- 发布本地音频。

相关实现：

- `Sources/XmaxSDK/Media/Video/VideoController.swift`
- `Sources/XmaxSDK/Media/MediaSourceController.swift`
- `Sources/XmaxSDK/Media/Video/VideoPlayerController.swift`
- `Sources/XmaxSDK/Media/Video/MediaPlaybackTimeline.swift`
- `Sources/XmaxSDK/Media/Audio/PCMFramePacketizer.swift`
- `Sources/XmaxSDK/Media/Audio/LocalAudioPreviewPlayer.swift`

## 4. 连接与发布

接入方需要提前建立实时连接时，可以显式调用：

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
streamController.setVideoEncoderConfig(videoFormat)
```

编码配置属于连接和发布准备，不由相机、图片或视频 Controller 执行。已连接
状态下更新相机采集格式时，Core 会同步更新 Stream 编码配置。

发布规则：

| 本地来源 | 发布视频 | 发布音频 |
| --- | ---: | ---: |
| 相机 | 是 | 否 |
| 图片 | 是 | 否 |
| 无音轨视频 | 是 | 否 |
| 有音轨视频 | 是 | 是 |

目前相机链路还没有麦克风音频，因此相机只发布视频。

`connect(localStream:)` 会在调用时创建 Session 并建立 RTC 连接，因此
可能从此时开始产生实时服务费用。不需要预连接的产品应使用下一节的
组合生成入口。

## 5. 生成时的行为

推荐调用：

```swift
let remoteStream = try await realtime.startGeneration(
    localStream: localStream,
    context: RealtimeContext(...)
)
```

这个组合入口会按需建立 Session 和 RTC 连接，因此未点击生成时不会因预连接
产生费用。如果已经连接，则直接复用当前连接。文件视频 reader 始终持续运行，
返回的 `remoteStream` 用于绑定生成结果视图。

已经显式调用 `connect(localStream:)` 的高级接入方，仍可继续调用：

```swift
try await realtime.startGeneration(
    context: RealtimeContext(...)
)
```

执行顺序：

```text
本地 reader 持续输出预览音视频帧
    ↓
静音本地音频预览，播放器和 PCM 时间轴保持运行
    ↓
尚未连接时，创建 Session 并建立 RTC 连接
    ↓
创建 taskID 和 SEI 状态
    ↓
向房间发送 start generation
    ↓
后续视频帧携带当前 taskID 对应的 SEI
    ↓
等待远端生成流确认
    ↓
提前注册 RTC VideoSink，等待首个处理后视频帧
    ↓
缓存可立即显示的远端首帧
    ↓
订阅远端音频并结束生成等待
```

Loading 和远端显示期间，本地 reader 都持续为 RTC 输出当前音视频帧，不维护
点击检查点、冻结帧或恢复闭包。收到匹配 taskID 的 SEI 只代表远端流已经确认；
SDK 会继续等待该流首个解码帧完成直通或插帧处理并进入缓存，之后才订阅远端
音频、结束 `startGeneration()` 并发出生成状态。接入方绑定远端轨道时，SDK
先向 `XmaxVideoView` 提交缓存首帧，因此不需要在示例工程猜测切换延迟。生成
失败、取消、停止或断开时，SDK 先清除生成任务，使后续本地视频帧立即绕过
RTC，再取消订阅远端音频并恢复本地音频预览音量。

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

核心采集和 RTC 推送链路已经具备，XLab 已接入图片与视频文件选择和公开创建
接口。目前 iOS 文件视频采用统一 reader 持续解码方案：生成期间不暂停、不 seek、不覆盖
冻结帧，远端结果 ready 后只切换显示和音频。

因此当前状态是：图片与视频可以进入 RTC、预览、连接和生成生命周期；下一步可以接入 XLab 做真机端到端调试，并基于本稿继续优化 Pipeline。

## 8. 文件视频统一解码链路

文件视频当前使用共享时间轴的音视频 reader：

```text
MediaPlaybackTimeline
├── 视频 AVAssetReader
│   └── NV12 裁剪 / 缩放 / 旋转
│       ├── AVSampleBufferDisplayLayer → XmaxVideoView 本地预览
│       └── StreamController → RTC
└── 音频 AVAssetReader
    └── 48 kHz / Mono / PCM16 / 10 ms
        ├── AVAudioEngine → 本地预览声音
        └── StreamController → RTC
```

两个 reader 使用同一个绝对起点和循环长度。RTC 音频订阅或离房导致共享
`AVAudioSession` 重配置时，视频 reader 和 RTC 帧调度不受影响；本地音频恢复后
直接消费统一时间轴之后产生的新 PCM 帧。

生成生命周期：

1. 创建本地视频流时准备共享时间轴并启动音视频 reader。
2. 用户点击生成时保持 reader 和本地音频播放器运行，只静音本地预览音量。
3. Session 和 RTC 连接建立期间，reader 继续输出本地预览；生成任务建立后，
   当前音视频帧开始送入 RTC。
4. 匹配 taskID 的远端 ready 到达后，远端画面和音频一起切换；本地音视频
   reader 继续在远端视图下方运行。
5. 停止时清除生成任务，使本地视频帧不再进入 RTC 调用，再直接隐藏远端视图；
   本地视频持续显示，本地音频播放器只需恢复音量。

这条链路不使用双 `AVPlayer`、`MTAudioProcessingTap` 或冻结帧覆盖层。每个 reader
只由所属解码任务访问；停止时等待音视频任务全部退出，之后才允许重新配置。

## 9. 待讨论与优化项

跨平台修改项统一记录在 `CROSS_PLATFORM_ALIGNMENT.md`，本文件仅维护媒体管线本身的设计和待优化事项。

- [ ] 明确图片和视频的默认输出格式策略。
- [ ] 明确显式 `videoFormat` 是严格输出值还是模型约束前的期望值。
- [ ] 真机评估视频 NV12 目标尺寸预处理的性能和画质。
- [x] 文件视频生成期间保持统一 reader 持续运行，并隔离 RTC 音频会话变化。
- [ ] 完成 XLab 图片与视频端到端调试入口。

## 10. 远端视频帧与插帧链路

远端视频统一使用自渲染，不因插帧开关在 RTC Canvas 与自渲染之间切换：

```text
VolcEngineRTC 解码
    ↓ BGRA CVPixelBuffer（自动转正、关闭镜像）
RtcRemoteVideoSink
    ↓ DecodedVideoFrame
RemoteVideoFramePipeline
    ├── 插帧关闭：原帧直通
    └── 插帧开启：VTFrameProcessor 在相邻帧间生成 1 帧
    ↓
RenderController 缓存最新可显示帧
    ↓ 绑定远端轨道时立即提交缓存帧
XmaxVideoView
    ↓
AVSampleBufferDisplayLayer
```

插帧只在 iOS 26 及以上、`MediaService` 判定实际视频尺寸不超过 100 万像素，且
`VTLowLatencyFrameInterpolationConfiguration` 接受该尺寸时开启。100 万像素
边界兼容旧版约 90 万像素的 32 对齐规格，包括 `704 × 1280`、`992 × 992` 和
`1120 × 840`，但会拒绝 `1120 × 1120`。初始化配置不受支持时，SDK 自动回退
到原帧直通并通过错误监听器提示；接入方运行时显式开启不受支持的现有流时抛出
同一类错误。关闭插帧始终成功，并清理帧处理器和待输出帧。

插帧处理器在收到第一张真实远端帧后，按该帧的尺寸和像素格式惰性创建；不根据
本地流规格提前预热。实际远端帧规格发生变化时，帧管线会按新规格重建处理器并
继续自动降级保护。
