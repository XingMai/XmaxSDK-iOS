<h1 align="center">XmaxSDK for iOS</h1>

<p align="center">
  <a href="https://developer.apple.com/ios/"><img src="https://img.shields.io/badge/iOS-15.0%2B-007AFF" alt="iOS 15.0+"></a>
  <a href="https://www.swift.org/"><img src="https://img.shields.io/badge/Swift-6.0-F05138" alt="Swift 6.0"></a>
  <a href="https://platform.xmaxai.com/"><img src="https://img.shields.io/badge/Realtime-AI-FF9500" alt="Realtime AI"></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/License-MIT-4C9A2A" alt="MIT License"></a>
</p>

Native iOS SDK, providing access to Xmax real-time interactive video generation models. It enables low-latency, high-fidelity video transformations using live video streams, reference images, and user interactions. With just a few lines of code, developers can seamlessly integrate cutting-edge features directly into their apps, such as real-time character replacement, virtual try-on, and mixed-reality companions, and so on.

<p align="center"><img src="./docs/images/xlab/generation-demo.gif" alt="X-Lab realtime generation demo" width="33%" /><img src="./docs/images/xlab/index-demo.gif" alt="X-Lab index demo" width="33%" /><img src="./docs/images/xlab/storage-demo.gif" alt="X-Lab storage demo" width="33%" /></p>

<br>

## Features

- Real-time generation using camera, image, or local video input
- Local media preview and remote generated video rendering
- Front and rear camera switching
- Runtime generation context updates
- Independent local and remote audio volume controls
- Network quality and device performance monitoring
- Remote video frame interpolation on supported devices
- Image and video upload/download with progress callbacks
- Optional image content safety checks
- Structured SDK errors and configurable logging
- Swift concurrency-based APIs

## Requirements

- iOS 15.0 or later
- Swift 6
- Xcode 26 or later for CocoaPods source integration
- Xcode 27 or later for the prebuilt 1.0.1 XCFramework
- An Xmax API key

## Installation

### CocoaPods

XmaxSDK is distributed directly from this GitHub repository through
CocoaPods. Add the required spec sources and XmaxSDK dependency to your
`Podfile`:

```ruby
source 'https://github.com/volcengine/volcengine-specs.git'
source 'https://cdn.cocoapods.org/'

platform :ios, '15.0'

use_frameworks! :linkage => :static

target 'YourApp' do
  pod 'XmaxSDK',
      :git => 'https://github.com/XingMai/XmaxSDK-iOS.git',
      :tag => '1.0.1'
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

Open the generated `.xcworkspace` file to build your application.

Static framework linkage is currently required so that the Objective-C
QCloudCOSXML dependency is exposed as a module that XmaxSDK can import from
Swift.

### Manual

Download
[`XmaxSDK-1.0.1.zip`](https://github.com/XingMai/XmaxSDK-iOS/releases/download/1.0.1/XmaxSDK-1.0.1.zip),
extract `XmaxSDK.xcframework`, then download the exact third-party dependencies
used by this release:

- [VolcEngineRTC `3.60.106.600`](https://hstob-cdn-tos.volccdn.com/volcengine/VolcEngineRTC/3.60.106.600/VolcEngineRTC.zip):
  use `VolcEngineRTC.xcframework`, `RealXBase.xcframework`, and
  `RTCFFmpeg.xcframework` from the downloaded archive.
- [Tencent Cloud COS iOS SDK `6.5.7`](https://github.com/tencentyun/qcloud-sdk-ios/tree/6.5.7):
  use `QCloudCOSXML.framework` and `QCloudCore.framework`. The repository's
  `package.sh` script can be used to build the manual integration artifacts.

Add the frameworks to the application target under **Frameworks, Libraries,
and Embedded Content** using the following settings:

| Framework | Embed setting |
| --- | --- |
| `XmaxSDK.xcframework` | Do Not Embed |
| `QCloudCOSXML.framework` | Do Not Embed |
| `QCloudCore.framework` | Do Not Embed |
| `VolcEngineRTC.xcframework` | Embed & Sign |
| `RealXBase.xcframework` | Embed & Sign |
| `RTCFFmpeg.xcframework` | Embed & Sign |

The XmaxSDK and COS binaries are static. The three VolcEngine binaries are
dynamic and must be embedded and signed by the application target.

Also complete the following configuration:

1. Set **Swift Language Version** to **Swift 6**.
2. Add `-ObjC` to **Other Linker Flags**.
3. Link `Accelerate.framework`, `CoreMedia.framework`,
   `CoreTelephony.framework`, `SystemConfiguration.framework`, `libz.tbd`,
   and `libc++.tbd`.
4. Add the COS `PrivacyInfo.xcprivacy` file to the application target.
5. Confirm that every XCFramework contains a slice for the target platform
   and architecture. Apple silicon simulator builds require an `arm64`
   simulator slice.

Only `QCloudCOSXML.framework` and `QCloudCore.framework` are required for COS.
Do not add `QCloudTrack.framework`, `COSBeaconAPI_Base.framework`, or QimeiSDK.
The third-party frameworks must be present when importing XmaxSDK because its
stable Swift module interface imports `QCloudCOSXML` and `VolcEngineRTC`.

## Privacy Permissions

Applications that use camera input must provide camera and microphone usage
descriptions in their `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app uses the camera for real-time video input.</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app uses the microphone for real-time audio input.</string>
```

Replace these descriptions with text appropriate for your application.

## Getting Started

### Create a client

```swift
import XmaxSDK

let client = XmaxClient(
    configuration: XmaxConfiguration(apiKey: "YOUR_API_KEY")
)

let realtime = client.createRealtimeManager(
    options: RealtimeConfiguration(model: .x2_0)
)
```

### Create a local camera stream

```swift
let localStream = try await realtime.createLocalCameraStream(
    videoFormat: RealtimeVideoFormat(
        width: 704,
        height: 1280,
        fps: 24
    )
)
```

The realtime manager can also create local streams from image data,
`UIImage`, image files, and video files.

Bind the local stream to an `XmaxVideoView` to display the input preview:

```swift
let localVideoView = XmaxVideoView(videoContentMode: .fill)
localVideoView.track = localStream.videoTrack
```

### Start generation

```swift
let remoteStream = try await realtime.startGeneration(
    localStream: localStream,
    context: RealtimeContext(
        prompt: "视频中角色替换成参考图中角色",
        referencePath: "https://platform.xmaxai.com/images/source/charx/chatx_image1.jpg"
    )
)
```

Calling `startGeneration(context:)` again updates the generation context while
reusing the current connection.

### Display video

Bind the remote stream to another `XmaxVideoView` to display the generated
video:

```swift
let remoteVideoView = XmaxVideoView(videoContentMode: .fill)
remoteVideoView.track = remoteStream.videoTrack
```

`XmaxVideoView` also supports trajectory interaction over the generated video.
Interaction is enabled by default and can be controlled with
`isInteractionEnabled`.

### Stop and release resources

```swift
await realtime.stopGeneration()
await realtime.disconnect()
await realtime.close()
```

`disconnect()` preserves the current local preview. Use `close()` when the
realtime session is no longer needed and its media and RTC resources should be
released.

## Frame Interpolation

On supported devices running iOS 26 or later, XmaxSDK can interpolate remote
generated video frames. It is enabled by default and can be changed at runtime:

```swift
try await realtime.setFrameInterpolationEnabled(false)
```

Check whether the current device supports interpolation for a specific video
size with `client.createMediaService().supportsFrameInterpolation(for:)`.

## Logging

XmaxSDK does not emit logs by default. Enable business logs, performance logs,
or both when creating the client:

```swift
let configuration = XmaxConfiguration(
    apiKey: "YOUR_API_KEY",
    loggerOptions: [.business, .performance]
)

let client = XmaxClient(configuration: configuration)
```

Logging configuration is process-wide and shared by all `XmaxClient`
instances.

## Example Project

A runnable example is available in
[`Examples/XLab`](https://github.com/XingMai/XmaxSDK-iOS/tree/main/Examples/XLab).
Open `XLab.xcworkspace` after installing its CocoaPods dependencies to explore
the SDK features shown above.

<p align="center"><img src="./docs/images/xlab/home.jpg" alt="X-Lab home" width="20%" /><img src="./docs/images/xlab/features.jpg" alt="X-Lab SDK features" width="20%" /><img src="./docs/images/xlab/storage.jpg" alt="X-Lab storage service" width="20%" /><img src="./docs/images/xlab/realtime-generation.jpg" alt="X-Lab realtime generation" width="20%" /><img src="./docs/images/xlab/trajectory-generation.jpg" alt="X-Lab trajectory generation" width="20%" /></p>

<br>

## Dependencies

- VolcEngineRTC provides real-time audio and video communication.
- Tencent Cloud COS provides media file upload and download capabilities.

## Distribution

- CocoaPods source distribution is supported.
- Manual XCFramework distribution is available through GitHub Releases.
- Swift Package Manager is not supported in version 1.0.1.

## Feedback

Please use [GitHub Issues](https://github.com/XingMai/XmaxSDK-iOS/issues) for
bug reports and feature requests.

## License

XmaxSDK is available under the terms of the [MIT License](LICENSE).
