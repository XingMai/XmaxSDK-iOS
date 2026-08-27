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
- [x] 同步 Core、Service、Media、Stream、Rendering 和测试代码引用。
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
- 相机保留 `replaceLocalCameraStream()`，用于保持相机 Track 语义下更新
  采集格式或位置，不扩展到图片和视频来源。

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

状态：历史方案；iOS 已由 SYNC-014 的单 AVPlayer 链路取代。

> iOS 已移除文件视频使用的 AVAssetReader 音视频 decoder，本节只保留为
> Harmony 排查旧 reader 生命周期问题的历史记录。

统一目标：

- 解码器停止与新一轮创建不得并发操作同一个平台 reader。
- 停止侧只更新生命周期状态并取消解码任务。
- reader 的启动、读取和取消全部由同一条解码执行链完成。
- 音频和视频文件 decoder 采用相同的资源释放规则。

iOS：

- [x] 移除 `release()` 中跨线程调用 `AVAssetReader.cancelReading()` 的逻辑。
- [x] 解码任务退出时在自身执行链中取消仍处于读取状态的 reader。
- [x] 视频帧转换和音频帧处理失败时统一由退出清理负责取消 reader。
- [ ] 真机重复执行生成、停止和重新生成，确认不再发生 reader 崩溃。

Harmony：

- [ ] 检查音视频 decoder 的 `release()` 是否会与读取线程并发访问同一个
  reader/demuxer。
- [ ] 如存在竞态，将 reader 的启动、读取和取消收敛到单一执行链。

## SYNC-012 文件视频本地音频预览

状态：历史方案；iOS 已由 SYNC-014 的 AVPlayer 系统播放与音频 Tap 取代。

统一目标：

- 文件视频包含音轨时，本地预览同步播放音频。
- 本地播放和 RTC 推流复用同一份解码后的 PCM 帧，不进行第二次解码。
- 无外接设备时默认通过扬声器播放，同时保留系统对耳机和蓝牙路由的切换。

iOS：

- [x] 本地音频改由 AVPlayer 系统播放，不再经过 SDK 自建 AVAudioEngine 缓冲。
- [x] 移除 RTC 外部音频源的强制扬声器路由，允许系统选择有线耳机和蓝牙设备。
- [x] 使用前置 `MTAudioProcessingTap` 复制同一播放器的 PCM 数据供 RTC 使用。
- [ ] 真机验证静音模式、扬声器、有线耳机和蓝牙耳机播放。

Harmony：

- [ ] 确认文件视频预览会同步播放本地音轨。
- [ ] 确认扬声器、耳机和蓝牙设备的默认路由行为。

## SYNC-013 文件视频生成点击位置检查点

状态：历史方案；静态帧覆盖和双 reader 时间线已由 SYNC-014 取代。

统一目标：

- 用户点击生成时，以最近实际输出给 RTC 的处理后视频帧作为视觉检查点。
- 生成等待期间，统一视频视图使用该静态帧覆盖本地 RTC Canvas；接入方不增加
  UIImageView 或额外预览逻辑。
- 音频和视频使用同一个源文件时间检查点、同一个 `MediaTimeline` 和同一个播放
  锚点重启。
- 第一轮从检查点播放到文件尾，后续循环从文件起点播放完整文件。
- 点击时先阻止文件视频帧继续进入本地 RTC Canvas；检查点时间线建立后
  恢复底层音视频推送，静态覆盖保留到匹配 taskID 的远端 ready、生成失败
  或取消。
- 进入连接和生成后立即清空并暂停本地音频预览，但不中断 RTC 需要的
  PCM 帧推送。
- 匹配 taskID 的远端 ready 到达时才订阅远端音频，使远端音频和画面
  共用同一 ready 边界；停止、失败或断开时取消订阅并恢复本地音频。
- 只增加一个组合 `startGeneration(localStream:context:)` 公共方法，不增加
  公共模型或内部抽象；`pauseVideoPreview()`、检查点时间和恢复闭包仍属于
  SDK 内部生命周期能力。
- 组合入口必须先暂停文件视频，再按需创建 Session 和 RTC 连接；用户
  未主动点击生成时不预连接，避免提前开始计费。

iOS：

- [x] `VideoSourceController` 在输出目标尺寸 NV12 帧时同步记录源文件时间。
- [x] `XmaxVideoView` 内部支持将 NV12 检查点帧转换为静态预览覆盖。
- [x] `VideoController` 使用 `pauseVideoPreview()` 记录检查点，并从该时间重启
  音视频。
- [x] 暂停入口原子地阻止后续帧进入 RTC Canvas，避免静态帧转换期间画面继续
  播放；检查点时间线建立后恢复底层推流。
- [x] 音频和视频 reader 使用相同 `timeRange` 起点。
- [x] `MediaTimeline` 区分首轮剩余时长和后续完整循环时长。
- [x] 恢复操作使用版本校验，避免旧操作解除新操作的暂停。
- [x] 增加检查点时间线、控制器转发、NV12 静态帧和恢复版本测试。
- [x] 增加按需连接的组合生成入口，并覆盖点击前不创建 Session、连接
  失败恢复预览的测试。
- [x] 本地音频预览与 RTC PCM 推送分离，loading 期间本地静音，远端 ready
  时才订阅远端音频。
- [x] SDK 单元测试 Scheme 真机目标构建通过。
- [ ] 真机验证点击位置、画面构图、声音连续性和远端首帧一致性。
- [ ] 真机连续执行生成、停止、再次生成，验证 reader 生命周期稳定。

Harmony：

- [ ] iOS 真机行为确认后，再确定平台静态覆盖组件和 reader seek 实现。
- [ ] 对齐组合生成入口，但不把内部检查点暴露给接入方。
- [ ] 音视频使用同一检查点和时间线，首轮到文件尾后恢复完整循环。
- [ ] 对齐本地音频暂停和远端 ready 后音视频同时切换的生命周期。

## SYNC-014 文件视频单播放器时间线

状态：iOS 已完成代码调整和 SDK 真机目标编译；Harmony 暂不修改，待 iOS
真机验证后确定平台对应方案。

统一目标：

- 本地文件视频只保留一个播放时钟，预览、生成检查点、RTC 视频帧和 RTC
  音频帧均以该时钟为准。
- 本地预览由平台播放器原生渲染，SDK 统一视频视图内部完成绑定，接入方无需
  额外创建播放器或视图。
- 用户点击生成时同步暂停播放器，检查点直接取播放器当前文件时间；生成开始后
  从该时间 seek 并静音播放。
- loading 和远端生成期间播放器保持运行、保持解码热状态；loading 期间使用
  静态帧遮住本地运动画面，远端 ready 后解除遮罩并由远端视图覆盖本地视图；
  停止生成时只切回持续播放的本地视图并取消静音。
- 远端音频仍只在匹配 taskID 的远端画面 ready 后订阅，音视频共用同一切换
  边界。
- 不强制选择扬声器；有线耳机和蓝牙路由交给系统音频会话处理。

iOS：

- [x] `XmaxVideoView` 内部使用 `AVPlayerLayer` 显示本地文件视频。
- [x] `AVPlayerItemVideoOutput` 从同一个 `AVPlayerItem` 取得 NV12 像素缓冲，
  经目标比例裁剪、缩放和物理旋转后进入 RTC。
- [x] `MTAudioProcessingTap` 从同一个 `AVPlayerItem` 复制 PCM，转换为 48 kHz、
  单声道、PCM16，并切分为 10 ms RTC 音频帧。
- [x] `pauseVideoPreview()` 直接暂停播放器并记录 `currentTime()`，不再生成
  独立 reader 检查点。
- [x] `XmaxVideoView` 使用最近实际输出的目标尺寸帧冻结本地画面；等待远端
  ready 期间 `AVPlayer` 继续为 RTC 解码，但运动画面不再暴露。
- [x] 远端 ready 后解除静态帧冻结；生成失败、停止或断开仍作为兜底恢复路径。
- [x] 生成从检查点精确 seek；失败恢复只在播放器尚未重启时继续播放。
- [x] 文件结束后由同一个播放器 seek 到零继续循环。
- [x] 删除 `VideoFileFrameDecoder`、`AudioFileFrameDecoder`、`MediaTimeline`、
  `VideoSourceController`、`AudioSourceController`、`AudioManager` 和
  `LocalVideoPreviewController`。
- [x] 移除 `setDefaultAudioRoute(.speakerphone)`。
- [x] 公共 API 和公共模型保持不变。
- [x] SDK 真机目标编译通过。
- [ ] 真机验证本地画面方向、目标构图和音画同步。
- [ ] 真机验证点击立即暂停、远端 ready 同时出声出画、停止立即恢复。
- [ ] 真机验证扬声器、有线耳机、AirPods 和其他蓝牙设备路由。
- [ ] 真机重复生成、停止和重新生成，确认播放器和 Tap 生命周期稳定。

Harmony：

- [ ] iOS 真机行为确认后，评估 AVPlayerLayer、VideoOutput、Audio Tap 在
  Harmony 平台的等价能力。
- [ ] 若平台播放器可同时提供原生预览与解码帧，收敛为单播放器时钟。
- [ ] 点击检查点使用播放器当前位置，不再维护独立 reader 墙钟。
- [ ] 本地播放器在远端阶段保持热状态，停止生成时直接恢复显示与声音。
