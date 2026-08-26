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

状态：已确认，iOS 已完成。

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

- [x] 增加 `imageData: Data` 创建和替换接口。
- [x] 保留 `fileURL` 创建和替换接口，并读取为 Data 后解码。
- [x] 增加 `UIImage` 创建和替换便利接口。
- [x] `UIImage` 直接规范化为已解码图片，不经过 PNG/JPEG 中转。
- [ ] XLab 改用 Data 或 UIImage，删除图片临时文件中转。
- [ ] 真机验证 Data、UIImage 和 fileURL 三种入口。

Harmony：

- [ ] 检查现有 `ArrayBuffer`、`Uint8Array` 和 `PixelMap` 能力。
- [ ] 对齐文件、二进制数据和平台图片对象入口。
- [ ] 验证三种入口进入同一图片处理链路。

## SYNC-002 视频输入 API

状态：已确认，iOS 当前实现无需修改。

统一行为：

- 视频以文件作为标准输入，不增加整段二进制数据入口。
- 避免将完整视频读入内存，以及由此产生的大块内存占用和数据复制。
- 平台相册选择得到临时文件时，接入方应先复制到自身可控的缓存目录，再传给 SDK。

iOS：

- [x] 保持 `fileURL: URL` 创建和替换接口。
- [x] 不增加 `videoData: Data` 接口。
- [ ] XLab 从 `PHPickerViewController` 获取视频临时文件并复制到缓存目录。
- [ ] 评估后续是否需要增加 `AVAsset` 便利入口；不影响文件核心链路。

Harmony：

- [ ] 确认当前视频文件 URI/path 入口与 iOS 文件语义一致。
- [ ] 确认相册或媒体选择器返回临时资源时的持久化策略。

## SYNC-003 图片处理职责收敛

状态：已确认，iOS 已完成代码调整和真机目标编译，待运行验证。

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

- [ ] 检查 Service 层是否包含图片选择、通用缩放或编码能力。
- [ ] 将模型尺寸规则与底层图片像素处理分离。
- [ ] 评估是否需要将已解码图片抽象统一为 `DecodedImage` 对应模型。

## SYNC-004 iOS Manager 命名规范

状态：已确认，iOS 已完成代码调整和真机目标编译。

iOS 规范：

- Foundation 能力协议统一使用 `*Managing`。
- Foundation 默认实现统一使用 `*Manager`。
- Core 对外或业务编排 Manager 使用 `Xmax` 前缀，与 Foundation Manager 区分。
- Foundation 组件不再使用 `*Providing` 或 `*Provider` 命名。
- 成员变量与初始化参数同步使用 `*Manager` 语义，例如 `rtcManager` 和 `storageManager`。

iOS：

- [x] 重命名 Audio、Image、MediaFileMetadata、Permission、RTC 和 Storage 基础能力。
- [x] 将进程级 RTC Engine 资源管理器重命名为 `RtcEngineManager`。
- [x] 同步 Core、Service、Media、Transport、Rendering 和测试代码引用。
- [x] 真机 SDK 测试目标编译通过。

Harmony：

- [ ] 无需照搬 iOS 类型名；检查同层级能力是否使用平台一致的命名规则。

## SYNC-005 业务层统一 Controller 边界

状态：iOS 已完成 Transport 与 Media 边界收口和真机目标编译。

iOS 规范：

- 具有多个协作组件和统一状态的业务层，通过与层同名的 Controller 向 Core 暴露能力。
- Core 只依赖业务层的 `*Controlling` 协议，不直接持有层内子 Controller。
- `TransportController` 内部协调 Room、Stream、Encoding 和 Quality。
- `MediaController` 内部协调 Camera、Image、Video 以及本地媒体所有权。
- 业务层子组件保留具体职责，不单独向 Core 暴露。

iOS：

- [x] 新增 `TransportControlling` 和 `TransportController`。
- [x] Core 不再直接依赖 Room、Stream、Encoding 和 Quality Controller。
- [x] 将媒体统一入口及相机、图片、视频组件从 Core 下沉至 Media。
- [x] 新增 `MediaControlling`，Core 仅通过 `MediaController` 使用媒体层。
- [x] 真机 SDK 测试目标编译通过。

Harmony：

- [ ] 检查 Core 是否直接持有 Transport 或 Media 层的内部组件。
- [ ] 评估是否需要用同层统一入口收口房间、流、编码、质量和媒体来源管理。
