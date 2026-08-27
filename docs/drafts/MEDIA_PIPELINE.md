# 图片与视频采集链路（临时草稿）

> 状态：临时设计稿，用于后续优化图片与文件视频 Pipeline。
>
> 基线提交：`cc35183 feat: add image and video media pipelines`
>
> 更新：文件视频旧的双 AVAssetReader、独立 PCM 播放与 MediaTimeline 方案已被
> 单 AVPlayer 时间线取代；当前实现以本文末尾“文件视频单播放器链路”为准。

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
        │                         ├── VideoSourceController → NV12 帧
        │                         └── AudioSourceController → PCM 音频帧
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

### 3.3 建立共享音视频时间线

`MediaTimeline` 为视频和音频提供同一个播放锚点：

- 启动时预留 100ms 解码准备时间。
- 循环周期向上对齐到 10ms。
- 正常预览从文件时间 0 开始。
- 生成重启的第一轮可以从点击时记录的文件时间开始，首轮时长为“检查点到
  文件尾”。
- 首轮结束后，后续循环都从文件时间 0 开始，并使用完整文件周期。
- 检查点重启时各轮播放锚点为：

```text
第 0 轮：初始播放锚点
第 1 轮：初始播放锚点 + 对齐后的首轮剩余时长
第 N 轮：第 1 轮锚点 + (N - 1) × 对齐后的完整循环时长
```

视频和音频不会各自以“解码完成时间”开启下一轮，从而避免循环次数增加后逐渐漂移。

停止或重新开始时，Source Controller 先使旧 generation 失效，再取消旧 decoder
任务。decoder 的 `release()` 不直接跨线程操作 `AVAssetReader`；reader 的启动、
逐帧读取与退出取消都由 decoder 自身执行链完成，避免快速重复生成和停止时
`startReading()` 与 `cancelReading()` 并发。

### 3.4 视频解码与推帧

`VideoSourceController` 执行以下步骤：

1. 使用 `VideoFileFrameDecoder` 解码文件。
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
   - `StreamController`：RTC 外部音频流入口。

尚未连接房间时，RTC 音频推帧会被流层忽略，但本地音频仍然播放。连接并发布本地音频后，PCM 帧才真正推给 RTC。

### 3.6 RTC 视频和音频初始化

`VideoController` 按以下顺序创建视频流：

1. 准备媒体文件。
2. 如果有音轨，申请麦克风权限。
3. 启用 RTC 外部视频源。
4. 如果有音轨，启用 RTC 外部音频源。
5. 注册本地预览。
6. 同时启动音视频 decoder。
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
- `Sources/XmaxSDK/Media/MediaTimeline.swift`
- `Sources/XmaxSDK/Media/Video/VideoSourceController.swift`
- `Sources/XmaxSDK/Media/Audio/AudioSourceController.swift`
- `Sources/XmaxSDK/Foundation/Media/Video/VideoFileFrameDecoder.swift`
- `Sources/XmaxSDK/Foundation/Media/Audio/AudioFileFrameDecoder.swift`

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

这个组合入口会先在 SDK 内确立文件视频的暂停检查点，再按需建立
Session 和 RTC 连接，因此未点击生成时不会因预连接产生费用。如果已经
连接，则直接复用当前连接。图片和相机也使用同一入口，但不需要文件
视频检查点。返回的 `remoteStream` 用于绑定生成结果视图。

已经显式调用 `connect(localStream:)` 的高级接入方，仍可继续调用：

```swift
try await realtime.startGeneration(
    context: RealtimeContext(...)
)
```

执行顺序：

```text
记录最近送入 RTC 的帧及其源文件时间
    ↓
立即阻止新帧进入本地 RTC Canvas，使用同一帧覆盖预览
    ↓
清空并暂停本地音频预览，PCM 帧仍继续送入 RTC
    ↓
尚未连接时，创建 Session 并建立 RTC 连接
    ↓
创建 taskID 和 SEI 状态
    ↓
向房间发送 start generation
    ↓
如果当前来源是文件视频，从检查点重新建立 MediaTimeline
    ↓
视频和音频同时从同一个文件时间开始
    ↓
后续视频帧携带当前 taskID 对应的 SEI
    ↓
等待远端生成流确认
    ↓
订阅远端音频，清除静态帧覆盖并显示远端结果
```

图片来源不需要重启，因为它始终输出同一帧。

视频来源会调用：

```swift
mediaController.restartForGeneration()
```

这会：

- 使用最近实际送入 RTC 的目标尺寸 NV12 帧作为检查点画面。
- 记录该帧对应的源文件时间；若尚未产生首帧，则回退到文件时间 0。
- 清空本地待播放音频。
- 释放当前音视频 decoder。
- 创建新的共享时间线。
- 音频和视频同时从检查点开始第一轮，抵达文件尾后再从文件起点循环。

进入暂停时先原子地阻止新的本地视频帧进入 RTC Canvas，使 Canvas 立即保持最后
一帧，同时清空本地音频缓冲并停止后续本地播放；随后在 `XmaxVideoView`
中生成同一帧的静态覆盖。检查点时间线建立完成后恢复底层音视频推送，
但本地音频保持静音。收到匹配 taskID 的远端 ready 后，SDK 才订阅远端音频并
清除覆盖帧，使远端音频和画面在同一 ready 边界对接入方可用。生成失败、取消、
停止或断开时，SDK 取消订阅远端音频并恢复本地音频预览。旧生成操作
持有的恢复闭包带版本校验，不会误清除较新一次操作的暂停画面。

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
接口。目前 iOS 已实现“点击位置检查点”：开始生成时冻结当前处理后视频帧，
音视频从同一源文件时间重新输出，远端结果 ready 后解除冻结。Harmony 仍待同步。

因此当前状态是：图片与视频可以进入 RTC、预览、连接和生成生命周期；下一步可以接入 XLab 做真机端到端调试，并基于本稿继续优化 Pipeline。

## 8. 文件视频单播放器链路

文件视频当前只使用一个 `AVPlayerItem`：

```text
AVPlayerItem
├── AVPlayerLayer
│   └── XmaxVideoView 内部本地预览
├── AVPlayerItemVideoOutput
│   └── NV12 裁剪 / 缩放 / 旋转 → StreamController → RTC
└── MTAudioProcessingTap（PreEffects）
    └── 48 kHz / Mono / PCM16 / 10 ms → StreamController → RTC
```

本地声音由 `AVPlayer` 直接交给系统音频链路播放。Tap 只复制前置 PCM 数据，
不会让接入方再维护一个播放器，也不会再次读取或解码源文件。

生成生命周期：

1. 创建本地视频流时准备一个播放器并开始循环预览。
2. 用户点击生成时立即 `pause()`，以 `currentTime()` 记录检查点；
   `XmaxVideoView` 使用最近输出的目标尺寸帧冻结本地画面并静音。
3. Session 和 RTC 连接成功、生成信令开始后，从检查点精确 seek 并播放，
   但静态冻结帧继续覆盖本地 `AVPlayerLayer`。
4. 本地播放器在远端阶段继续静音运行，为 RTC 持续提供音视频帧；Loading
   期间接入方仍只看到点击位置的静态画面。
5. 匹配 taskID 的远端 ready 到达后，远端画面和音频一起切换，并清除本地
   冻结帧；本地播放器继续在远端视图下方运行。
6. 停止时直接隐藏远端视图，显示持续运行的本地播放器并取消静音；失败或断开
   仍会兜底清除冻结帧。

这条链路不再使用 `VideoFileFrameDecoder`、`AudioFileFrameDecoder`、
`MediaTimeline` 或独立 `AVAudioEngine` 播放器。冻结帧由 `XmaxVideoView`
内部显示，不要求接入方增加 UIImageView 或预览切换逻辑。

## 9. 待讨论与优化项

跨平台修改项统一记录在 `CROSS_PLATFORM_ALIGNMENT.md`，本文件仅维护媒体管线本身的设计和待优化事项。

- [ ] 明确图片和视频的默认输出格式策略。
- [ ] 明确显式 `videoFormat` 是严格输出值还是模型约束前的期望值。
- [ ] 真机评估视频 NV12 目标尺寸预处理的性能和画质。
- [x] 实现生成等待期间的点击位置帧冻结与音视频检查点重启。
- [ ] 完成 XLab 图片与视频端到端调试入口。
