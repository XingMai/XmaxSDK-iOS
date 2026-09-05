<p align="center">
  <img src="./docs/images/brand/xmax-sdk.png" alt="XmaxSDK — Realtime Interactive Video Generation" width="880">
</p>

<p align="center">
  <a href="https://developer.apple.com/ios/"><img src="https://img.shields.io/badge/iOS-15.0%2B-007AFF" alt="iOS 15.0+"></a>
  <a href="https://www.swift.org/"><img src="https://img.shields.io/badge/Swift-6.0-F05138" alt="Swift 6.0"></a>
  <a href="https://platform.xmaxai.com/"><img src="https://img.shields.io/badge/Realtime-AI-FF9500" alt="Realtime AI"></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/License-MIT-4C9A2A" alt="MIT License"></a>
</p>

XmaxSDK is a native iOS SDK that provides access to Xmax's real-time, interactive video
generation models. It enables low-latency, cost-efficiency, and high-fidelity video
transformations, conditioned on reference images, text prompts, and user interactions.
With concise Swift APIs, developers can integrate features such as real-time character
swapping, virtual try-on, or AI companions into iOS applications.

<p align="center"><img src="./docs/images/xlab/generation-demo.gif" alt="X-Lab realtime generation demo" width="33%" /><img src="./docs/images/xlab/index-demo.gif" alt="X-Lab index demo" width="33%" /><img src="./docs/images/xlab/storage-demo.gif" alt="X-Lab storage demo" width="33%" /></p>

<br>

## What XmaxSDK does

XmaxSDK gives an end-to-end pipeline covering media capture, low-latency video
communication, frame-by-frame generation, and in-app rendering. Whether
processing live camera feeds, pre-recorded video, or still images, the SDK streams
input to our cloud AI engine, applies on-device enhancement to the returned video,
and renders the result. With the entire workflow abstracted into simple API calls,
integrating real-time video generation is seamless and intuitive.

<br>

## What you can build with XmaxSDK

<table>
  <tr>
    <th width="24%" align="left">Use Case</th>
    <th width="60%" align="left">Description</th>
    <th width="16%" align="center">Demo</th>
  </tr>
  <tr>
    <td width="24%" valign="middle">
      <strong>Character Swapping</strong>
    </td>
    <td width="60%" valign="middle">
      Replace anyone in your live feed with a designated avatar in real-time.
    </td>
    <td width="16%" align="center" valign="middle">
      <a href="https://cdn.jsdelivr.net/gh/XingMai/XmaxSDK-iOS@cfcee886daadc7f8b901e652361b20cd4ec42591/docs/videos/use-cases/character-swapping.mp4">
        <img src="./docs/images/use-cases/character-swapping-poster.png" alt="Play the XmaxSDK demo" width="120">
        <br>
        <sub>▶ Play demo</sub>
      </a>
    </td>
  </tr>
  <tr>
    <td width="24%" valign="middle">
      <strong>Virtual Try-On</strong>
    </td>
    <td width="60%" valign="middle">
      Seamlessly change outfits, preserving exact body shape, natural motion, and an
      authentic fit.
    </td>
    <td width="16%" align="center" valign="middle">
      <a href="https://cdn.jsdelivr.net/gh/XingMai/XmaxSDK-iOS@cfcee886daadc7f8b901e652361b20cd4ec42591/docs/videos/use-cases/character-swapping.mp4">
        <img src="./docs/images/use-cases/character-swapping-poster.png" alt="Play the XmaxSDK demo" width="120">
        <br>
        <sub>▶ Play demo</sub>
      </a>
    </td>
  </tr>
  <tr>
    <td width="24%" valign="middle">
      <strong>Video Restyling</strong>
    </td>
    <td width="60%" valign="middle">
      Reimagine your world in any style with an immersive visual experience.
    </td>
    <td width="16%" align="center" valign="middle">
      <a href="https://cdn.jsdelivr.net/gh/XingMai/XmaxSDK-iOS@cfcee886daadc7f8b901e652361b20cd4ec42591/docs/videos/use-cases/character-swapping.mp4">
        <img src="./docs/images/use-cases/character-swapping-poster.png" alt="Play the XmaxSDK demo" width="120">
        <br>
        <sub>▶ Play demo</sub>
      </a>
    </td>
  </tr>
  <tr>
    <td width="24%" valign="middle">
      <strong>AI Companions</strong>
    </td>
    <td width="60%" valign="middle">
      Summon virtual characters into your live camera feed and interact with them
      through gestures.
    </td>
    <td width="16%" align="center" valign="middle">
      <a href="https://cdn.jsdelivr.net/gh/XingMai/XmaxSDK-iOS@cfcee886daadc7f8b901e652361b20cd4ec42591/docs/videos/use-cases/character-swapping.mp4">
        <img src="./docs/images/use-cases/character-swapping-poster.png" alt="Play the XmaxSDK demo" width="120">
        <br>
        <sub>▶ Play demo</sub>
      </a>
    </td>
  </tr>
  <tr>
    <td width="24%" valign="middle">
      <strong>Live Photo</strong>
    </td>
    <td width="60%" valign="middle">
      Animate and control characters in your images simply by drawing motion
      trajectories.
    </td>
    <td width="16%" align="center" valign="middle">
      <a href="https://cdn.jsdelivr.net/gh/XingMai/XmaxSDK-iOS@d4f8a4ada6c3a30b98373d30ec7a63791f4851b1/docs/videos/use-cases/live-photo.mp4">
        <img src="./docs/images/use-cases/live-photo-poster.png" alt="Play the Live Photo demo" width="120">
        <br>
        <sub>▶ Play demo</sub>
      </a>
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
      <td>End-to-end latency is measured in hundreds of milliseconds, ensuring that updates to generation conditions and interaction controls are reflected almost instantly.</td>
      <td>Our models run efficiently on a single RTX 5090 GPU, reducing inference costs by orders of magnitude compared to setups requiring datacenter GPUs like H100.</td>
      <td>Our models support real-time generation at up to 1080p, delivering production-ready, high-quality video output.</td>
    </tr>
  </tbody>
</table>

<br>

## How to use XmaxSDK?

### Prerequisites

- iOS 15.0 or later
- Swift 6
- An Xmax API key

> [!WARNING]
> Do not commit an Xmax API key to version control. Supply credentials securely at
> runtime, or use a temporary key issued by the Xmax API. See
> [Authentication](https://platform.xmaxai.com/docs/authentication) for details.

### Installation

Because some of its dependencies do not support Swift Package Manager, XmaxSDK
currently supports only [**CocoaPods**](#cocoapods) and
[**manual integration**](#manual).

#### CocoaPods

Add the following to your application's `Podfile`:

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

Install the dependencies:

```bash
pod install --repo-update
```

#### Manual

Download
[`XmaxSDK-1.0.3.xcframework.zip`](https://github.com/XingMai/XmaxSDK-iOS/releases/download/1.0.3/XmaxSDK-1.0.3.xcframework.zip),
then follow the [manual integration guide](./docs/installation.md#manual-integration)
to add the required dependencies and configure your Xcode target.

### Quick Start

#### Configure permissions

Add a camera usage description to your application's `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app uses the camera for real-time video input.</string>
```

Use wording appropriate for your app. XmaxSDK requests permission when creating
the camera stream and throws an `XmaxError` if permission is unavailable.

#### Generate and display video

The following UIKit example previews the camera, starts generation, and displays
the result in the same view. Run it in a main-actor async context, using an API key
supplied securely at runtime (`apiKey`) and your preview container (`containerView`).

```swift
import UIKit
import XmaxSDK

let client = XmaxClient(
    configuration: XmaxConfiguration(apiKey: apiKey)
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
videoView.frame = containerView.bounds
videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
containerView.addSubview(videoView)

let remoteStream = try await realtime.startGeneration(
    localStream: localStream,
    context: RealtimeContext(prompt: "Transform the scene into an anime style")
)
videoView.remoteTrack = remoteStream.videoTrack
```

The view shows the local preview until the first generated frame arrives. Touch
interaction is enabled by default.

<details>
<summary>Using SwiftUI</summary>

Use `XmaxRealtimeVideo` in place of the UIKit view. Store the local and remote
tracks in observable state and update them as streams become available:

```swift
XmaxRealtimeVideo(
    localTrack: localTrack,
    remoteTrack: remoteTrack,
    videoContentMode: .fill
)
```

See the [SwiftUI guide](./docs/usage.md#swiftui) for state binding and the
[example project](#example-project) for a complete implementation.

</details>

#### Clean up

Keep the realtime manager and video view available for cleanup. When leaving the
generation screen, cancel its owning task and release the connection and media
resources:

```swift
await realtime.close()
videoView.removeFromSuperview()
```

Handle errors from throwing calls and clean up if startup fails. For image and
video inputs, reference images, live updates, and advanced controls, see the
[usage guide](./docs/usage.md).

<br>

## Example Project

A runnable reference application with UIKit and SwiftUI implementations is available
in [`Examples/XLab`](https://github.com/XingMai/XmaxSDK-iOS/tree/main/Examples/XLab).
The application demonstrates realtime generation with camera, image, and local
video inputs, together with custom prompts, reference image selection, and
trajectory rendering.

<p align="center"><img src="./docs/images/xlab/home.jpg" alt="X-Lab home" width="20%" /><img src="./docs/images/xlab/features.jpg" alt="X-Lab SDK features" width="20%" /><img src="./docs/images/xlab/storage.jpg" alt="X-Lab storage service" width="20%" /><img src="./docs/images/xlab/realtime-generation.jpg" alt="X-Lab realtime generation" width="20%" /><img src="./docs/images/xlab/trajectory-generation.jpg" alt="X-Lab trajectory generation" width="20%" /></p>

<br>

## Third-party dependencies

- VolcEngine RTC SDK for iOS provides real-time audio and video communication.
- Tencent Cloud COS SDK provides image and video transfer through object storage.

<br>

## Contact us

For bug reports and feature requests, use
[GitHub Issues](https://github.com/XingMai/XmaxSDK-iOS/issues). For integration
questions and technical support, contact [sdk@xmax.ai](mailto:sdk@xmax.ai).

<br>

## License

XmaxSDK is available under the terms of the [MIT License](LICENSE).
