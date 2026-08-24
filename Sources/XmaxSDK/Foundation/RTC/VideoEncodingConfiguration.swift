/// RTC 主视频流编码参数。
struct VideoEncodingConfiguration: Equatable, Sendable {
    let width: Int
    let height: Int
    let frameRate: Int
    let minimumBitrate: Int
    let maximumBitrate: Int

    init(
        width: Int,
        height: Int,
        frameRate: Int,
        minimumBitrate: Int = 0,
        maximumBitrate: Int = -1
    ) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.minimumBitrate = minimumBitrate
        self.maximumBitrate = maximumBitrate
    }
}
