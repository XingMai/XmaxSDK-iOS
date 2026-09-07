<p align="center">
  <img src="./docs/images/brand/xmax-sdk.png" alt="XmaxSDK — Realtime Interactive Video Generation" width="880">
</p>

<p align="center">
  <a href="https://developer.apple.com/ios/"><img src="https://img.shields.io/badge/iOS-15.0%2B-007AFF" alt="iOS 15.0+"></a>
  <a href="https://www.swift.org/"><img src="https://img.shields.io/badge/Swift-6.0-F05138" alt="Swift 6.0"></a>
  <a href="https://platform.xmaxai.com/"><img src="https://img.shields.io/badge/Realtime-AI-FF9500" alt="Realtime AI"></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/License-MIT-4C9A2A" alt="MIT License"></a>
</p>

Native iOS SDK, providing access to Xmax's real-time, interactive video generation models. The models are optimized for low latency and cost efficiency, enabling instantaneous video transformations across diverse characters, outfits, and aesthetic styles. Also, they can dynamically respond to user gestures, allowing interactive virtual subjects to blend into real-world footage for immersive experiences. XmaxSDK implements an end-to-end pipeline to leverage these novel capabilities through concise Swift APIs, making it easy for developers to build next-generation interactive video experiences within the iOS ecosystem.

<p align="center"><img src="./docs/images/xlab/generation-demo.gif" alt="X-Lab realtime generation demo" width="33%" /><img src="./docs/images/xlab/index-demo.gif" alt="X-Lab index demo" width="33%" /><img src="./docs/images/xlab/storage-demo.gif" alt="X-Lab storage demo" width="33%" /></p>

<br>

## What XmaxSDK does

XmaxSDK offers a complete workflow that covers media acquisition, low-latency video communication, frame-by-frame generation, and in-app rendering. Whether processing live camera feeds, pre-recorded video, or still images, it streams media to our cloud inference service, applies on-device enhancement to the returned video, and renders the result to screen. With the entire workflow abstracted into simple API calls, integrating real-time video generation is seamless and intuitive.

<br>

## What you can build with XmaxSDK

<table>
  <tr>
    <th width="24%" align="left">Realtime Use Case</th>
    <th width="60%" align="left">Description</th>
    <th width="16%" align="center">Demo</th>
  </tr>
  <tr>
    <td rowspan="2" width="24%" valign="middle">
      <strong>Character Swapping</strong>
    </td>
    <td width="60%" valign="middle">
      Replace anyone in your live feed with a designated avatar in real-time.
    </td>
    <td rowspan="2" width="16%" align="center" valign="middle">
      <a href="https://cdn.jsdelivr.net/gh/XingMai/XmaxSDK-iOS@88182780abe60b3df1c44f549487fcf8ab4b660c/docs/videos/use-cases/character-swapping.mp4">
        <img src="./docs/images/use-cases/character-swapping-poster.png" alt="Play the Character Swapping demo" width="120">
        <br>
        <sub>▶ Play demo</sub>
      </a>
    </td>
  </tr>
  <tr>
    <td width="60%" valign="middle">
      <strong>Prompt:</strong> <code>视频中角色替换成参考图中角色</code>
      <br><br>
      <strong>Reference image:</strong> Select a clear image of the desired character with a clean background.
    </td>
  </tr>
  <tr>
    <td rowspan="2" width="24%" valign="middle">
      <strong>Virtual Try-On</strong>
    </td>
    <td width="60%" valign="middle">
      Seamlessly change outfits, preserving exact body shape, natural motion, and an
      authentic fit.
    </td>
    <td rowspan="2" width="16%" align="center" valign="middle">
      <a href="https://cdn.jsdelivr.net/gh/XingMai/XmaxSDK-iOS@88182780abe60b3df1c44f549487fcf8ab4b660c/docs/videos/use-cases/virtual-try-on.mp4">
        <img src="./docs/images/use-cases/virtual-try-on-poster.png" alt="Play the Virtual Try-On demo" width="120">
        <br>
        <sub>▶ Play demo</sub>
      </a>
    </td>
  </tr>
  <tr>
    <td width="60%" valign="middle">
      <strong>Prompt:</strong> <code>视频中人物衣服替换成参考图中衣服</code>
      <br><br>
      <strong>Reference image:</strong> Select a clear image of the target outfit with a clean background.
    </td>
  </tr>
  <tr>
    <td rowspan="2" width="24%" valign="middle">
      <strong>Video Restyling</strong>
    </td>
    <td width="60%" valign="middle">
      Reimagine your world in any style with an immersive visual experience.
    </td>
    <td rowspan="2" width="16%" align="center" valign="middle">
      <a href="https://cdn.jsdelivr.net/gh/XingMai/XmaxSDK-iOS@88182780abe60b3df1c44f549487fcf8ab4b660c/docs/videos/use-cases/video-restyling.mp4">
        <img src="./docs/images/use-cases/video-restyling-poster.png" alt="Play the Video Restyling demo" width="120">
        <br>
        <sub>▶ Play demo</sub>
      </a>
    </td>
  </tr>
  <tr>
    <td width="60%" valign="middle">
      <strong>Prompt:</strong> <code>视频风格变为参考图指定的风格</code>
      <br><br>
      <strong>Reference image:</strong> Select an image that captures the artistic style you want to apply.
    </td>
  </tr>
  <tr>
    <td rowspan="2" width="24%" valign="middle">
      <strong>AI Companions</strong>
    </td>
    <td width="60%" valign="middle">
      Summon virtual characters into your live camera feed and interact with them
      through gestures.
    </td>
    <td rowspan="2" width="16%" align="center" valign="middle">
      <a href="https://cdn.jsdelivr.net/gh/XingMai/XmaxSDK-iOS@88182780abe60b3df1c44f549487fcf8ab4b660c/docs/videos/use-cases/ai-companions.mp4">
        <img src="./docs/images/use-cases/ai-companions-poster.png" alt="Play the AI Companions demo" width="120">
        <br>
        <sub>▶ Play demo</sub>
      </a>
    </td>
  </tr>
  <tr>
    <td width="60%" valign="middle">
      <strong>Prompt:</strong> <code>指定角色在场景中互动</code>
      <br><br>
      <strong>Reference image:</strong> Select a clear image of the virtual character you want to summon with a clean background.
    </td>
  </tr>
  <tr>
    <td rowspan="2" width="24%" valign="middle">
      <strong>Live Photo</strong>
    </td>
    <td width="60%" valign="middle">
      Animate and control characters in your images simply by drawing motion
      trajectories.
    </td>
    <td rowspan="2" width="16%" align="center" valign="middle">
      <a href="https://cdn.jsdelivr.net/gh/XingMai/XmaxSDK-iOS@4351aa869d4e24fd40690c670d8949bff270dee0/docs/videos/use-cases/live-photo.mp4">
        <img src="./docs/images/use-cases/live-photo-poster.png" alt="Play the Live Photo demo" width="120">
        <br>
        <sub>▶ Play demo</sub>
      </a>
    </td>
  </tr>
  <tr>
    <td width="60%" valign="middle">
      <strong>Prompt:</strong> <code>让画面自然动起来</code>
      <br><br>
      <strong>Reference image:</strong> Use the input image as the reference
    </td>
  </tr>
</table>

<br>

## Why XmaxSDK?

<table>
  <thead>
    <tr>
      <th height="104" align="center" valign="middle">
        <img src="./docs/images/why/low-latency.svg" alt="Low latency" width="36" height="36"><br>Low latency
      </th>
      <th height="104" align="center" valign="middle">
        <img src="./docs/images/why/low-cost.svg" alt="Cost efficiency" width="36" height="36"><br>Cost efficiency
      </th>
      <th height="104" align="center" valign="middle">
        <img src="./docs/images/why/high-fidelity.svg" alt="High fidelity" width="36" height="36"><br>High fidelity
      </th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>End-to-end latency is measured in <img src="./docs/images/why/latency-highlight.svg" alt="hundreds of milliseconds" width="192" height="20" align="absmiddle">, ensuring that updates to generation conditions and interaction controls are reflected instantly.</td>
      <td>Run on a <img src="./docs/images/why/gpu-highlight.svg" alt="single RTX 5090" width="126" height="20" align="absmiddle">, reducing inference costs by orders of magnitude versus datacenter GPUs like H100.</td>
      <td>Our models support real-time generation at up to <img src="./docs/images/why/resolution-highlight.svg" alt="1080p" width="48" height="20" align="absmiddle">, delivering production-ready, high-quality video output.</td>
    </tr>
  </tbody>
</table>

<br>

## Prerequisites

- iOS 15.0 or later
- Swift 6
- An Xmax API key

> [!WARNING]
> Never commit your Xmax API key to version control. Pass it securely at
> runtime or use short-lived temporary keys issued by the Xmax API. For step-by-step
> instructions, see [Authentication](https://platform.xmaxai.com/docs/authentication).

<br>

## Installation

Because certain underlying dependencies lack Swift Package Manager support,
XmaxSDK currently supports [**CocoaPods**](#cocoapods) and
[**manual integration**](#manual) only.

### CocoaPods

Add the following to your application's `Podfile`:

```ruby
source 'https://github.com/volcengine/volcengine-specs.git'
source 'https://cdn.cocoapods.org/'

platform :ios, '15.0'

use_frameworks! :linkage => :static

target 'YourApp' do
  pod 'XmaxSDK',
      :git => 'https://github.com/XingMai/XmaxSDK-iOS.git',
      :tag => '1.0.4'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |configuration|
      configuration.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    end
  end
end
```

Install the dependencies:

```bash
pod install --repo-update
```

### Manual

Download
[`XmaxSDK-1.0.4.xcframework.zip`](https://github.com/XingMai/XmaxSDK-iOS/releases/download/1.0.4/XmaxSDK-1.0.4.xcframework.zip),
then follow the [manual integration guide](./docs/installation.md#manual-integration)
to add the required dependencies and configure your Xcode target.

<br>

## Quick Start

### Configure permissions

Add a camera usage description to your application's `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app uses the camera for real-time video input.</string>
```

Customize this message to match your application's user experience. XmaxSDK
automatically prompts for camera access when creating the video stream and throws
an `XmaxError` if permission is denied or unavailable.

<br>

### Generate and display video

The following UIKit snippet creates a camera stream, starts real-time generation,
and binds the output to a video view. Run this within a `@MainActor` async context.

```swift
import UIKit
import XmaxSDK

let client = XmaxClient(
    configuration: XmaxConfiguration(apiKey: "YOUR_XMAX_API_KEY")
)

let realtime = client.createRealtimeManager(
    options: RealtimeConfiguration(model: .x2_0)
)

let localStream = try await realtime.createLocalCameraStream(
    videoFormat: RealtimeVideoFormat(width: 704, height: 1280, fps: 24),
    position: .front
)

let videoView = XmaxRealtimeVideoView(
    localTrack: localStream.videoTrack,
    videoContentMode: .fill
)

let remoteStream = try await realtime.startGeneration(
    localStream: localStream,
    context: RealtimeContext(
        prompt: "视频中角色替换成参考图中角色",
        referencePath: "https://platform.xmaxai.com/images/source/charx/chatx_image1.jpg"
    )
)

videoView.remoteTrack = remoteStream.videoTrack
```

Add the video view to your view hierarchy. The view displays a local camera
preview until the first generated frame arrives, with touch interaction enabled
by default.

<br>

### Using SwiftUI

Use `XmaxRealtimeVideo` as your primary SwiftUI view. Store the local and remote
tracks in observable state, updating them dynamically as streams become available:

```swift
XmaxRealtimeVideo(
    localTrack: localTrack,
    remoteTrack: remoteTrack,
    videoContentMode: .fill
)
```

See the [SwiftUI guide](./docs/usage.md#swiftui) for state binding and the
[example project](#example-project) for a complete implementation.

<br>

### Listen for events

After creating `realtime`, register the listeners you need before creating the
input stream or starting generation.

| Listener | Purpose |
| --- | --- |
| `setStateListener` | Observe pipeline states during real-time generation. |
| `setErrorListener` | Handle fatal errors that prevent the realtime workflow from continuing. |
| `setCameraPreviewReadyListener` | Notify when the initial local camera frame is ready for preview rendering. |
| `setRemoteVideoFrameListener` | Receive generated frames for recording or custom processing. |
| `setNetworkQualityListener` | Monitor uplink and downlink network quality. |
| `setPerformanceAlarmListener` | Detect device performance limitations or recovery, with a suggested video format when available. |

For example, monitor state changes and errors:

```swift
await realtime.setStateListener { state in
    print("State: \(state.connectionState.rawValue)")
}

await realtime.setErrorListener { error in
    print("Error: \(error.code.rawValue) \(error.message)")
}
```

<br>

### Resource Cleanup

- **`disconnect()` — Stop Remote Generation**

  Stops remote generation and cancels billing while keeping the local camera stream
  and preview active. Use this when ending the online session but staying on the
  current screen. You can start a new session later using the same local stream:

  ```swift
  await realtime.disconnect()
  ```

- **`close()` — Full Teardown & Release**

  Ends the remote session, stops local media capture, and releases all engine
  resources. Use this when leaving or dismissing the generation screen:

  ```swift
  await realtime.close()
  ```

> **Note:** These methods are alternatives, not sequential steps. When exiting a
> screen, call `close()` directly—there is no need to call `disconnect()` first.

<br>

> [!TIP]
> For complete usage examples, including image and video inputs, reference images,
> and touch interaction, see the [usage guide](./docs/usage.md).

<br>

## Example Project

A complete example application featuring both UIKit and SwiftUI implementations
is available in [`Examples/XLab`](https://github.com/XingMai/XmaxSDK-iOS/tree/main/Examples/XLab).
It demonstrates real-time generation using live camera feeds, static images, and
local video files.

<p align="center"><img src="./docs/images/xlab/home.jpg" alt="X-Lab home" width="20%" /><img src="./docs/images/xlab/features.jpg" alt="X-Lab SDK features" width="20%" /><img src="./docs/images/xlab/storage.jpg" alt="X-Lab storage service" width="20%" /><img src="./docs/images/xlab/realtime-generation.jpg" alt="X-Lab realtime generation" width="20%" /><img src="./docs/images/xlab/trajectory-generation.jpg" alt="X-Lab trajectory generation" width="20%" /></p>

<br>

## Dependencies

- <ins><strong>VolcEngine RTC SDK for iOS</strong></ins> enables low-latency, real-time audio and video communication.
- <ins><strong>Tencent Cloud COS SDK</strong></ins> handles media upload and download via object storage.

<br>

## Contact us

For bug reports and feature requests, please open a
[GitHub Issue](https://github.com/XingMai/XmaxSDK-iOS/issues). For integration
assistance and technical support, contact us at [sdk@xmax.ai](mailto:sdk@xmax.ai).

<br>

## License

XmaxSDK is available under the terms of the [MIT License](LICENSE).
