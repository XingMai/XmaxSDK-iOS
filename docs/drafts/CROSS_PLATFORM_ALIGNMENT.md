# iOS 与 Harmony 对齐清单（临时）

> 用途：记录先在 iOS 落地、后续需要检查或同步到 Harmony 的设计决策和实现差异。
>
> 维护方式：所有模块共用本清单，每项使用独立编号；不为每个问题重复创建清单文件。

## 状态说明

- `已确认`：跨平台行为已经确定。
- `iOS 已完成`：iOS 实现已落地，Harmony 尚待处理。
- `已对齐`：两个平台均已完成并验证。
- `无需同步`：确认属于平台特有实现。

## SYNC-001 图片输入 API

状态：已确认；iOS 与 Harmony 均已完成代码调整，待端到端运行验证。

统一行为：

- 图片支持文件、编码后的二进制数据和平台图片对象。
- 编码后的二进制数据是图片 Pipeline 的基础输入形式。
- 文件、二进制数据和平台图片对象最终收敛为内部已解码图片。

平台映射：

| 输入语义 | iOS | Harmony |
| --- | --- | --- |
| 文件输入 | `URL` | file URI/path |
| 编码图片数据 | `Data` | `ArrayBuffer`/`Uint8Array` |
| 平台图片对象 | `UIImage` | `PixelMap` |

iOS：

- [x] 增加 `imageData: Data` 创建接口。
- [x] 保留 `fileURL` 创建接口，并读取为 Data 后解码。
- [x] 增加 `UIImage` 创建便利接口。
- [x] `UIImage` 直接规范化为已解码图片，不经过 PNG/JPEG 中转。
- [ ] XLab 改用 Data 或 UIImage，删除图片临时文件中转。
- [ ] 真机验证 Data、UIImage 和 fileURL 三种入口。

Harmony：

- [x] 使用 `ArrayBuffer`、`Uint8Array` 和 `PixelMap` 作为公开图片输入，不增加 `EncodedImage` 包装类型。
- [x] 对齐文件、二进制数据和平台图片对象入口。
- [x] 三种入口统一收敛为内部 `DecodedImage`，再转换为循环输出的视频帧。
- [x] `PixelMap` 入口先创建 SDK 自有快照，不修改或释放接入方对象。
- [ ] 真机验证文件、二进制数据和 `PixelMap` 三种入口。

## SYNC-002 视频输入 API

状态：已确认，iOS 当前实现无需修改。

统一行为：

- 视频以文件作为标准输入，不增加整段二进制数据入口。
- 避免将完整视频读入内存，以及由此产生的大块内存占用和数据复制。
- 平台相册选择得到临时文件时，接入方应先复制到自身可控的缓存目录，再传给 SDK。

iOS：

- [x] 保持 `fileURL: URL` 创建接口。
- [x] 不增加 `videoData: Data` 接口。
- [ ] XLab 从 `PHPickerViewController` 获取视频临时文件并复制到缓存目录。
- [ ] 评估后续是否需要增加 `AVAsset` 便利入口；不影响文件核心链路。

Harmony：

- [ ] 确认当前视频文件 URI/path 入口与 iOS 文件语义一致。
- [ ] 确认相册或媒体选择器返回临时资源时的持久化策略。

## SYNC-003 图片处理职责收敛

状态：已确认；iOS 与 Harmony 均已完成代码调整和构建验证，待图片流端到端运行验证。

统一行为：

- Service 层只保留与模型业务约束相关的输入尺寸计算。
- Foundation 层负责图片解码、方向处理、裁剪、缩放和视频帧像素转换。
- Media 层只负责图片帧的准备、定时输出和生命周期。
- 图片选择属于接入方 UI，不由 SDK Service 呈现。

iOS：

- [x] `MediaService` 只保留 `resolveModelInputSize()`。
- [x] 删除图片选择、通用缩放和 JPEG 压缩公开接口。
- [x] 删除 `ProcessedImage`、`ImageProcessingMetadata` 和 `ImageProcessingResult`。
- [x] 将 `ImageProcessingSession` 收敛为内部 `DecodedImage`。
- [x] `ImageManager` 只负责 `decode()`。
- [x] Core Graphics 裁剪、缩放和 BGRA 转换统一由 `DecodedImage` 执行。
- [x] 真机 SDK 测试目标编译通过。
- [ ] 图片流端到端运行验证。

Harmony：

- [x] `MediaServicing` 只保留 `resolveModelInputSize()`，继续通过 `XmaxClient.createMediaService()` 对外提供模型尺寸规则。
- [x] 删除 Service 层的图片选择、通用缩放、JPEG 编码能力和 `ProcessedImage`。
- [x] 将模型尺寸规则与底层图片像素处理分离。
- [x] 增加内部 `DecodedImage`，统一持有已解码图片尺寸、视频帧像素转换和平台资源生命周期。
- [x] `ImageManager` 负责文件、编码数据和 `PixelMap` 解码；Media 层不再直接调用 CoreFileKit 或 ImageKit 解码 API。
- [x] 编码图片继续使用平台二进制类型，不增加没有独立职责的 `EncodedImage`。
- [x] Harmony HAR 构建通过。
- [ ] 图片流端到端运行验证。

## SYNC-004 iOS Manager 命名规范

状态：已对齐；iOS 真机测试目标编译与 Harmony HAR 构建均已通过。

iOS 规范：

- Foundation 能力协议统一使用 `*Managing`。
- Foundation 默认实现统一使用 `*Manager`。
- Core 对外或业务编排 Manager 使用 `Xmax` 前缀，与 Foundation Manager 区分。
- Foundation 组件不再使用 `*Providing` 或 `*Provider` 命名。
- 成员变量与初始化参数同步使用 `*Manager` 语义，例如 `rtcManager` 和 `storageManager`。

iOS：

- [x] 重命名 Audio、Image、MediaFileMetadata、Permission、RTC 和 Storage 基础能力。
- [x] 将进程级 RTC Engine 资源管理器重命名为 `RtcEngineManager`。
- [x] 同步 Core、Service、Media、Stream、Render 和测试代码引用。
- [x] 真机 SDK 测试目标编译通过。

Harmony：

- [x] Foundation 能力协议从 `*Providing` 统一重命名为 `*Managing`。
- [x] Foundation 默认实现从 `*Provider` 统一重命名为 `*Manager`。
- [x] 将 `RtcProviding`、`RtcProvider` 分别重命名为 `RtcManaging`、`RtcManager`，并同步成员变量和构造参数引用。
- [x] Core 对外或业务编排 Manager 保留 `Xmax` 前缀，与 Foundation Manager 区分。
- [x] Harmony HAR 构建通过。

## SYNC-005 业务层统一 Controller 边界

状态：iOS 已收口为 Stream、Media 统一边界并完成编译验证；Harmony 仍使用 Transport 命名。

iOS 规范：

- 具有多个协作组件和统一状态的业务层，通过与层同名的 Controller 向 Core 暴露能力。
- Core 只依赖业务层的 `*Controlling` 协议，不直接持有层内子 Controller。
- `StreamController` 内部协调 Room、Encoding、Quality，并统一管理 RTC 流状态。
- `MediaController` 内部协调 Camera、Image、Video、平台已有的 Interaction 能力以及本地媒体所有权。
- 业务层子组件保留具体职责，不单独向 Core 暴露。

iOS：

- [x] 新增 `StreamControlling` 和 `StreamController`。
- [x] Core 不再直接依赖 Room、Encoding 和 Quality Controller。
- [x] 将媒体统一入口及相机、图片、视频组件从 Core 下沉至 Media。
- [x] 新增 `MediaControlling`，Core 仅通过 `MediaController` 使用媒体层。
- [x] `MediaControlling` 和 `StreamControlling` 的方法使用规范化中文文档注释，明确参数、返回值、失败条件和生命周期语义。
- [x] Stream 层统一入口使用 `setVideoEncoderConfig()` 设置视频编码器配置；Foundation 层的 RTC 适配方法仍保留 `configureVideoEncoding()`。
- [x] 真机 SDK 测试目标编译通过。

Harmony：

- [x] 新增 `TransportControlling` 和 `TransportController`，统一协调 Room、Stream、Encoding 和 Quality。
- [x] 新增 `MediaControlling` 和 `MediaController`，统一协调 Camera、Image、Video、Interaction 和本地媒体所有权。
- [x] Core 不再直接持有 Transport 或 Media 层的内部子 Controller。
- [x] 相机、图片、视频和交互组件从 Core 下沉到 Media，并仅通过 `TransportControlling` 配置编码、推送媒体帧和发送交互轨迹。
- [x] 业务层接口沿用 JSDoc 规范，逐项说明 `@param`、`@returns` 和重要生命周期语义。
- [x] Transport 层统一入口使用 `setVideoEncoderConfig()`；Foundation 层保留 `RtcManaging.configureVideoEncoding()`。
- [x] Harmony HAR 构建通过。

> Media 与流层的直接依赖已在后续审视中废止，见 SYNC-008。

## SYNC-006 图片与视频来源 API 收敛

状态：已对齐；iOS 测试目标与 Harmony SDK、XLab 均已编译通过。

统一行为：

- 图片和视频只提供 `createLocalImageStream()`、`createLocalVideoStream()`
  以及对应的停止接口。
- 不提供图片或视频 `replaceLocal*Stream()`，避免每种输入形式同时扩展
  create 和 replace 变体。
- 更换图片或视频来源由接入方显式执行 disconnect、stop、create，并按需
  重新 connect；SDK 不隐藏跨连接生命周期的复合操作。
- 相机位置通过 `switchCamera()` 切换；需要更新采集格式时，由接入方显式执行
  stop 后 create，与图片和视频来源保持一致。

iOS：

- [x] 删除 Data、UIImage、图片文件和视频文件的 replace 公共入口。
- [x] 删除 Core、Media 实现及对应 replace 测试。
- [x] 使用 stop 后 create 的测试覆盖媒体所有权和 RTC 生命周期。
- [x] XmaxSDK 单元测试 Scheme 真机目标编译通过。

Harmony：

- [x] 删除图片和视频 replace 公共入口及 Core、Media 实现。
- [x] XLab 改为 disconnect、stop、create、connect 的显式切换编排。
- [x] Harmony HAR 与 XLab HAP 构建通过。

## SYNC-007 图片轨道本地预览

状态：iOS 已完成；Harmony 待同步。

统一目标：

- 接入方只需要把 `RealtimeVideoTrack` 交给统一视频视图，不判断来源类型。
- 图片轨道直接使用平台图片组件渲染处理后的静态帧。
- 摄像头、视频文件和远端轨道继续使用 RTC 渲染。
- 图片预览复用送入 RTC 的处理后像素，不重复解码图片。

iOS：

- [x] `ImageSourceController` 保留处理后的 BGRA 图片帧。
- [x] 图片轨道注册 UIKit 渲染绑定，由 `XmaxVideoView` 内部使用
  `UIImageView` 显示。
- [x] 视频、摄像头和远端轨道继续使用 RTC Canvas。
- [x] SDK 单元测试 Scheme 真机目标编译通过。

Harmony：

- [ ] 图片轨道注册 PixelMap 预览，由统一视频组件内部使用 Image 渲染。
- [ ] 视频、摄像头和远端轨道继续使用 RTC Surface。
- [ ] 完成 HAR 与 XLab HAP 编译验证。

## SYNC-008 Media 与流层分层解耦

状态：iOS 已完成并通过 SDK 真机目标构建；Harmony 待同步。

统一目标：

- Media 层只负责媒体采集、解码、帧生产、本地 Track 和预览生命周期。
- Stream 层只负责编码配置、房间发布、SEI 和 RTC 帧传输。
- Media 层不依赖 `StreamControlling`，也不定义 `push`、`publish` 或
  `send` 等传输语义。
- Media 通过中性音视频帧监听器输出帧，由 Core 组装根连接到 Stream。
- 视频编码配置在连接前由 Core 使用本地 Track 的最终格式设置；已连接相机
  更新格式时由 Core 同步更新。

iOS：

- [x] 从 `MediaController`、`CameraController`、`ImageController` 和
  `VideoController` 移除 `StreamControlling` 依赖。
- [x] 增加内部 `MediaVideoFrameListener` 和 `MediaAudioFrameListener`，只
  表达 Media 产生中性帧的事件。
- [x] 在 `XmaxRealtimeManager` 组装阶段把帧监听器连接到 Stream。
- [x] 将编码配置从媒体来源创建迁移到 `connect()`，并覆盖已连接相机更新。
- [x] SDK 单元测试 Scheme 真机目标构建通过。

Harmony：

- [ ] 从 Media 统一入口及相机、图片、视频、交互子组件移除 Transport
  依赖。
- [ ] 通过中性音视频帧回调或事件把 Media 输出连接到 Transport。
- [ ] 将编码配置迁移到 Core 的连接与已连接相机更新生命周期。
- [ ] 完成 HAR 与 XLab HAP 编译验证。

## SYNC-009 媒体帧模型收敛

状态：iOS 已完成并通过 SDK 真机目标构建；Harmony 待审视和同步。

统一目标：

- Media 内部只流转统一的 `VideoFrame` 和 `AudioFrame`，不按图片、视频文件
  或 RTC 来源重复定义字段相同的帧模型。
- `VideoFrame` 是具体值类型，不保留只有单一实现的协议与默认实现组合。
- 图片解码后直接生成单平面 BGRA `VideoFrame`；视频文件解码后直接生成
  双平面 NV12 `VideoFrame`。
- 文件解码器使用帧、结束和错误闭包回调，不额外定义只被一个适配器实现的
  Listener 协议。
- Media 对 Core 只保留视频帧和音频帧两个语义回调，不按来源重复定义
  Listener 别名。

iOS：

- [x] 将 `VideoFrame` 从协议收敛为具体 `struct`。
- [x] 删除 `BufferVideoFrame`、`ImageVideoFrameData` 和
  `VideoFileDecodedFrame`。
- [x] 图片准备一次性返回最终 `RealtimeVideoFormat` 和预览 `VideoFrame`，
  不通过额外可选属性传递预览帧状态。
- [x] 删除音视频文件 Decoder Listener 协议和 Source 层转发适配器。
- [x] 只保留 `MediaVideoFrameListener` 与 `MediaAudioFrameListener`。
- [x] SDK 单元测试 Scheme 真机目标构建通过。

Harmony：

- [ ] 盘点图片、视频文件和 RTC 链路中的帧类型，删除字段重复的来源专用模型。
- [ ] 若视频帧接口只有一个实现，收敛为具体值类型。
- [ ] 删除只负责把 Decoder 事件转发给 Source 的 Listener/Adapter 层。
- [ ] Media 对 Core 只暴露统一视频帧和音频帧事件。
- [ ] 完成 HAR 与 XLab HAP 编译验证。

## SYNC-010 文件视频目标尺寸与预览一致

状态：iOS 已完成并通过 SDK 真机目标构建；Harmony 待审视和同步。

统一目标：

- 根据源视频显示尺寸和模型约束计算目标显示尺寸。
- 文件视频解码后按照目标比例居中裁剪，并缩放为目标尺寸再进入 RTC。
- 本地预览和 RTC 编码复用同一份目标尺寸视频帧，不依赖 RTC 内部缩放策略。
- 在进入 RTC 前物理旋转 NV12 像素，使视频帧物理宽高等于目标显示宽高，
  并将帧旋转信息重置为 0。
- 本地预览和 RTC 编码均不得依赖旋转元数据，避免不同 RTC 路径解释不一致。
- 目标尺寸处理属于解码后的像素处理，不增加额外的视频编码。

iOS：

- [x] 将目标显示尺寸和旋转映射为裁剪、缩放使用的中间 NV12 尺寸。
- [x] 使用 Accelerate/vImage 居中裁剪并缩放 NV12 的 Y 与 UV 平面。
- [x] 物理旋转 NV12 的 Y 与 UV 平面，输出最终显示尺寸并重置旋转信息。
- [x] 本地 RTC 预览和 RTC 外部推帧使用同一份已定向 NV12 帧。
- [x] 创建本地文件视频轨道后、返回接入方绑定预览前设置 RTC 编码格式，避免
  未连接阶段的本地 Canvas 使用默认横向尺寸。
- [x] 增加目标尺寸、NV12 居中裁剪和顺时针旋转测试。
- [x] SDK 单元测试 Scheme 真机目标构建通过。
- [ ] 真机验证本地预览与生成输入构图一致。

Harmony：

- [ ] 确认文件视频当前是否在进入 RTC 前处理为模型目标尺寸。
- [ ] 若仍发送源尺寸帧，增加目标比例居中裁剪和缩放处理。
- [ ] 确保本地预览和 RTC 推流复用同一份目标尺寸帧。
- [ ] 确认本地文件视频预览是否依赖编码格式；如依赖，在返回本地轨道前应用
  最终视频格式。
- [ ] 完成 HAR、XLab HAP 构建和真机画面一致性验证。

## SYNC-011 文件解码器安全停止

状态：iOS 已实现；Harmony 待核对。

统一目标：

- 解码器停止与新一轮创建不得并发操作同一个平台 reader。
- 停止侧只更新生命周期状态并取消解码任务。
- reader 的启动、读取和取消全部由同一条解码执行链完成。
- 音频和视频文件 decoder 采用相同的资源释放规则。

iOS：

- [x] 移除 `release()` 中跨线程调用 `AVAssetReader.cancelReading()` 的逻辑。
- [x] 解码任务退出时在自身执行链中取消仍处于读取状态的 reader。
- [x] 视频帧转换和音频帧处理失败时统一由退出清理负责取消 reader。
- [x] 停止媒体源时取消父任务并等待音视频子任务全部退出，退出完成前不得创建
  下一组 reader。
- [ ] 真机重复执行生成、停止和重新生成，确认不再发生 reader 崩溃。

Harmony：

- [ ] 检查音视频 decoder 的 `release()` 是否会与读取线程并发访问同一个
  reader/demuxer。
- [ ] 如存在竞态，将 reader 的启动、读取和取消收敛到单一执行链。

## SYNC-012 文件视频本地音频预览

状态：iOS 已实现；Harmony 待核对。

统一目标：

- 文件视频包含音轨时，本地预览同步播放音频。
- 本地播放和 RTC 推流复用同一份解码后的 PCM 帧，不进行第二次解码。
- 无外接设备时默认通过扬声器播放，同时保留系统对耳机和蓝牙路由的切换。

iOS：

- [x] 本地音频使用 `AVAudioEngine` 播放解码后的 48 kHz、单声道 PCM16。
- [x] 移除 RTC 外部音频源的强制扬声器路由，允许系统选择有线耳机和蓝牙设备。
- [x] 本地预览和 RTC 推流复用同一份 10 ms PCM 帧，不使用第二个播放器或
  `MTAudioProcessingTap`。
- [x] 生成期间只把本地 PCM 播放器音量设为 0，不停止播放器或音频引擎；统一
  媒体时间轴和 RTC PCM 推帧保持连续。
- [ ] 真机验证静音模式、扬声器、有线耳机和蓝牙耳机播放。

Harmony：

- [ ] 确认文件视频预览会同步播放本地音轨。
- [ ] 确认扬声器、耳机和蓝牙设备的默认路由行为。

## SYNC-013 文件视频生成点击位置检查点

状态：已废弃。iOS 真机体验确认不再采用点击检查点、播放器暂停、精确 seek
或静态帧覆盖；当前方案见 SYNC-014。Harmony 不需要同步本节历史实现。

## SYNC-014 文件视频统一解码时间线

状态：iOS 已实现；Harmony 暂不修改，待 iOS 真机验证后同步。

统一目标：

- 文件音频和视频分别由 `AVAssetReader` 解码，共享同一个单调绝对时间轴和循环
  边界。
- 同一份目标尺寸 NV12 帧同时用于 `XmaxVideoView` 本地预览和 RTC 外部视频源；
  同一份 10 ms PCM 帧同时用于 `AVAudioEngine` 本地播放和 RTC 外部音频源。
- 本地预览由 SDK 统一视频视图内部完成，接入方无需额外创建播放器或视图。
- 用户点击生成、等待连接和 Loading 时统一媒体时间轴始终持续运行，不暂停、不 seek、
  不建立点击检查点，也不显示静态冻结帧。
- Loading 和远端生成期间 reader 保持解码热状态；远端 ready 后由远端视图覆盖
  本地视图，停止生成时先让后续本地视频帧绕过 RTC，再切回持续解码的本地视图
  并恢复 PCM 播放器音量。
- 远端音频仍只在匹配 taskID 的远端画面 ready 后订阅，音视频共用同一切换
  边界。
- 不强制选择扬声器；有线耳机和蓝牙路由交给系统音频会话处理。

iOS：

- [x] `XmaxVideoView` 内部使用 `AVSampleBufferDisplayLayer` 显示处理后的本地帧，
  主线程来不及显示时只保留最新帧。
- [x] 视频 reader 输出 NV12，经目标比例裁剪、缩放和物理旋转后同时进入预览与
  RTC。
- [x] 音频 reader 输出 48 kHz、单声道、PCM16，并按共享时间轴切分、调度为
  10 ms PCM 帧。
- [x] 音视频 reader 使用同一绝对起点和循环长度，不依赖两个播放器各自的时钟。
- [x] RTC 音频会话变化只影响本地 `AVAudioEngine`，不暂停视频解码和 RTC 推帧。
- [x] 删除 `pauseVideoPreview()`、生成检查点、恢复闭包和冻结帧覆盖能力。
- [x] 生成开始、Loading、远端显示和停止生成不改变媒体时间线。
- [x] 无活动生成任务时，本地视频帧只用于预览，不调用 RTC 推帧，避免 RTC
  退房锁阻塞统一 reader。
- [x] 文件结束后音视频 reader 按共享循环边界创建下一轮 reader。
- [x] reader 仅由所属解码任务访问；停止时等待任务退出，避免
  `startReading()` 与跨线程 `cancelReading()` 竞态。
- [x] 移除 `setDefaultAudioRoute(.speakerphone)`。
- [x] 公共 API 和公共模型保持不变。
- [x] SDK 真机目标编译通过。
- [ ] 真机验证本地画面方向、目标构图和音画同步。
- [ ] 真机验证 Loading 持续播放、远端 ready 同时出声出画、停止立即恢复。
- [ ] 真机验证扬声器、有线耳机、AirPods 和其他蓝牙设备路由。
- [ ] 真机重复生成、停止和重新生成，确认 reader 和音频引擎生命周期稳定。

Harmony：

- [ ] iOS 真机行为确认后，对齐音视频共享绝对时间轴和循环边界。
- [ ] 本地预览与 RTC 复用同一份处理后视频帧和 PCM 帧，不重复解码。
- [ ] 对齐 reader 单所有者和停止等待屏障，避免读取与释放并发。
- [ ] 对齐生成期间媒体时间线持续运行，不实现点击检查点或冻结帧覆盖。
- [ ] 本地解码在远端阶段保持热状态，停止生成时直接恢复显示与声音。

## SYNC-015 远端视频插帧

状态：iOS 已实现并通过编译验证；Harmony 暂不修改，待 iOS 26 真机验证后再
决定跨平台公开语义。

iOS 设计：

- [x] `RealtimeConfiguration` 支持设置初始插帧开关，默认开启；不支持时自动
  降级为原帧播放。
- [x] `XmaxRealtimeManaging` 支持查询能力、查询实际开关状态以及运行时切换。
- [x] `MediaServicing` 支持检查当前系统、设备与指定分辨率的组合是否可插帧。
- [x] 远端视频始终使用 RTC VideoSink 和 SDK 自渲染，关闭插帧时原帧直通。
- [x] iOS 26 使用 `VTFrameProcessor` 在相邻帧间插入一帧，不实现 x4 模式。
- [x] `MediaService` 以 100 万像素作为兼容旧版约 90 万像素对齐规格的业务
  上限；Foundation 只通过 VideoToolbox 校验平台能力，不持有业务阈值。
- [x] 初始化配置不受支持时自动关闭插帧、继续普通播放并回调
  `FRAME_INTERPOLATION_UNSUPPORTED`。
- [x] 运行时显式开启不受支持的已有流时保持原状态，并回调和抛出同一错误。
- [x] XLab 在 iOS 26 及以上使用 `704 × 1280 / 24fps` 摄像头格式并默认请求
  插帧；较低系统继续使用 `832 × 1472 / 24fps` 且默认关闭。
- [x] SEI 只确认远端流；首个处理后视频帧进入 SDK 缓存后，才订阅远端音频并
  完成生成等待，远端轨道绑定时立即提交缓存首帧。
- [ ] iOS 26 支持机型真机验证画面、帧率、性能和运行时切换。

Harmony：

- [ ] iOS 真机验证完成后，再评估 Harmony 是否提供等价能力与统一公开开关。

## SYNC-016 生成期间切换摄像头

状态：iOS 已实现并通过编译验证；XLab 过渡动画与 Harmony 对齐待后续处理。

iOS 设计：

- [x] 未生成时，`switchCamera()` 复用当前相机 Track 直接切换镜头。
- [x] 生成中切换时，SDK 保留 RTC 连接，自动执行停止生成、切换镜头和使用
  缓存条件恢复生成。
- [x] 通过 Stream 已有的生成任务判断启动窗口，不新增重复运行状态。
- [x] RTC 连接或生成正在启动，以及断开流程执行期间拒绝切换。
- [ ] XLab 增加水平翻转与模糊过渡动画。

Harmony：

- [ ] 对齐生成期间切换摄像头的停止、切换与恢复生成语义。
