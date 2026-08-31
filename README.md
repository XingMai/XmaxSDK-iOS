<h1 align="center">XmaxSDK for iOS</h1>

<p align="center">
  <a href="https://developer.apple.com/ios/"><img src="https://img.shields.io/badge/iOS-15.0%2B-007AFF" alt="iOS 15.0+"></a>
  <a href="https://www.swift.org/"><img src="https://img.shields.io/badge/Swift-6.0-F05138" alt="Swift 6.0"></a>
  <a href="https://platform.xmaxai.com/"><img src="https://img.shields.io/badge/Realtime-AI-FF9500" alt="Realtime AI"></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/License-MIT-4C9A2A" alt="MIT License"></a>
</p>

Native iOS SDK, providing access to the real-time interactive video generation
models from Xmax AI. It supports low latency, high fidelity video transformations
driven by live video streams, reference images, and user interactions. With just a
few lines of code, developers can integrate features such as real-time character
swap, virtual try-on, mixed reality companions, and interactive image animation
directly into their apps.

<p align="center"><img src="./docs/images/xlab/generation-demo.gif" alt="X-Lab realtime generation demo" width="33%" /><img src="./docs/images/xlab/index-demo.gif" alt="X-Lab index demo" width="33%" /><img src="./docs/images/xlab/storage-demo.gif" alt="X-Lab storage demo" width="33%" /></p>

<br>

## Features

- Real-time video generation from live camera streams, still images, and local video
  files, guided by prompts, reference images, and user interactions
- In-application rendering of local media input and generated output
- Multi-touch trajectory input for controlling subject movement in generated video
  streams
- Image and video transfer through Xmax-managed object storage
- Native Swift 6 APIs with async/await support
- SwiftUI ready

## Requirements

- iOS 15.0 or later
- Swift 6
- An Xmax API key

> [!WARNING]
> Do not commit an Xmax API key to version control. Supply credentials securely at
> runtime, or use a temporary key issued by the Xmax API. See
> [Authentication](https://platform.xmaxai.com/docs/authentication) for details.

## Installation

### CocoaPods

XmaxSDK is distributed directly from this GitHub repository through CocoaPods. Add
the required spec sources and XmaxSDK dependency to the application's `Podfile`:

```ruby
source 'https://github.com/volcengine/volcengine-specs.git'
source 'https://cdn.cocoapods.org/'

platform :ios, '15.0'

use_frameworks! :linkage => :static

target 'YourApp' do
  pod 'XmaxSDK',
      :git => 'https://github.com/XingMai/XmaxSDK-iOS.git',
      :tag => '1.0.2'
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

Open the generated `.xcworkspace` file to build the application.

Static framework linkage is required so that the Objective-C `QCloudCOSXML`
dependency is exposed as a module that XmaxSDK can import from Swift.

### Manual

Download
[`XmaxSDK-1.0.2.zip`](https://github.com/XingMai/XmaxSDK-iOS/releases/download/1.0.2/XmaxSDK-1.0.2.zip),
extract `XmaxSDK.xcframework`, and download the exact third-party dependencies used
by this release:

- [VolcEngineRTC `3.60.106.600`](https://hstob-cdn-tos.volccdn.com/volcengine/VolcEngineRTC/3.60.106.600/VolcEngineRTC.zip):
  use `VolcEngineRTC.xcframework`, `RealXBase.xcframework`, and
  `RTCFFmpeg.xcframework` from the downloaded archive.
- [Tencent Cloud COS iOS SDK `6.5.7`](https://github.com/tencentyun/qcloud-sdk-ios/tree/6.5.7):
  use `QCloudCOSXML.framework` and `QCloudCore.framework`. The repository's
  `package.sh` script can be used to build the manual integration artifacts.

Add the frameworks to the application target under **Frameworks, Libraries, and
Embedded Content** using the following settings:

| Framework | Embed setting |
| --- | --- |
| `XmaxSDK.xcframework` | Do Not Embed |
| `QCloudCOSXML.framework` | Do Not Embed |
| `QCloudCore.framework` | Do Not Embed |
| `VolcEngineRTC.xcframework` | Embed & Sign |
| `RealXBase.xcframework` | Embed & Sign |
| `RTCFFmpeg.xcframework` | Embed & Sign |

The XmaxSDK and COS binaries are static. The three VolcEngine binaries are dynamic
and must be embedded and signed by the application target.

Complete the following configuration:

1. Set **Swift Language Version** to **Swift 6**.
2. Add `-ObjC` to **Other Linker Flags**.
3. Link `Accelerate.framework`, `CoreMedia.framework`,
   `CoreTelephony.framework`, `SystemConfiguration.framework`, `libz.tbd`,
   and `libc++.tbd`.
4. Add the COS `PrivacyInfo.xcprivacy` file to the application target.
5. Confirm that every XCFramework contains a slice for the target platform and
   architecture. Apple silicon simulator builds require an `arm64` simulator slice.

Only `QCloudCOSXML.framework` and `QCloudCore.framework` are required for COS.
Do not add `QCloudTrack.framework`, `COSBeaconAPI_Base.framework`, or QimeiSDK.
The third-party frameworks must be present when importing XmaxSDK because its stable
Swift module interface imports `QCloudCOSXML` and `VolcEngineRTC`.

## Privacy Permissions

For camera-based input, provide a camera usage description in the application's
`Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app uses the camera for real-time video input.</string>
```

If a local video input contains audio, also provide a microphone usage description:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app uses the microphone for real-time audio input.</string>
```

Replace these descriptions with text appropriate for the application. XmaxSDK checks
and requests the required runtime permissions when a local media stream is created.
If permission is unavailable, the SDK reports an `XmaxError`.

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

Realtime operations use Swift Concurrency and should be invoked from a
lifecycle-aware `Task` owned by the host application.

Connection-state and error listeners may be registered on the realtime manager:

```swift
await realtime.setStateListener { state in
    print(
        "Xmax realtime state: \(state.connectionState.rawValue), " +
        "session: \(state.sessionID ?? "-"), task: \(state.taskID ?? "-")"
    )
}

await realtime.setErrorListener { error in
    print("Xmax realtime error: \(error.code.rawValue) \(error.message)")
}
```

### Create an input stream

After camera permission has been granted, create a live camera stream:

```swift
let localStream = try await realtime.createLocalCameraStream(
    videoFormat: RealtimeVideoFormat(
        width: 704,
        height: 1280,
        fps: 24
    ),
    position: .front
)
```

Still images and local video files can also be used as input sources:

```swift
let imageStream = try await realtime.createLocalImageStream(
    fileURL: imageFileURL
)
let videoStream = try await realtime.createLocalVideoStream(
    fileURL: videoFileURL
)
```

Only one local input stream may be active at a time.

### Preview the input

In UIKit, bind the local stream to an `XmaxVideoView`:

```swift
let localVideoView = XmaxVideoView(
    track: localStream.videoTrack,
    videoContentMode: .fill,
    isInteractionEnabled: false
)
```

In SwiftUI, render the same track with `XmaxVideo`:

```swift
XmaxVideo(
    track: localStream.videoTrack,
    videoContentMode: .fill,
    isInteractionEnabled: false
)
```

### Start generation

Construct a `RealtimeContext` with a prompt and, when applicable, a remote reference
image URL:

```swift
let remoteStream = try await realtime.startGeneration(
    localStream: localStream,
    context: RealtimeContext(
        prompt: "视频中角色替换成参考图中角色",
        referencePath: referenceImageURL
    )
)
```

In UIKit, render the generated output with a separate `XmaxVideoView`:

```swift
let remoteVideoView = XmaxVideoView(
    track: remoteStream.videoTrack,
    videoContentMode: .fill
)
```

In SwiftUI, render the generated track with `XmaxVideo`:

```swift
XmaxVideo(track: remoteStream.videoTrack)
```

To record or process the generated output outside the SDK, register a final-frame
listener before starting generation:

```swift
await realtime.setRemoteVideoFrameListener { frame in
    recorder.append(
        pixelBuffer: frame.pixelBuffer,
        presentationTimeStamp: frame.presentationTimeStamp,
        duration: frame.duration
    )
}
```

The listener receives the frames accepted by the final render pipeline, after
optional frame interpolation, on a dedicated serial background queue. Frame time
stamps do not necessarily start at zero, so a recorder should rebase its output
timeline to the first received frame. Transfer each frame to the recording pipeline
quickly and avoid synchronous encoding in the callback. This API currently exposes
video frames only; generated audio is not included.

Clear the listener when frame delivery is no longer required:

```swift
await realtime.setRemoteVideoFrameListener(nil)
```

To update an active generation task, submit a new context containing the revised
prompt or reference image:

```swift
try await realtime.startGeneration(
    context: RealtimeContext(
        prompt: "将人物服装替换成参考图中的服装",
        referencePath: anotherReferenceImageURL
    )
)
```

### Stop and release resources

```swift
await realtime.stopGeneration()
await realtime.disconnect()
await realtime.close()
```

`stopGeneration()` terminates the active generation task while retaining the
remote connection and local preview. `disconnect()` closes the remote session
while preserving the local preview. `close()` releases all local media and RTC
resources and should be called when the realtime workflow is no longer required.

## Touch Interaction

During an active generation task, `XmaxVideoView` and `XmaxVideo` capture
multi-touch trajectories over the generated video and submit them to the active
task. The host application does not need to implement gesture tracking or coordinate
conversion.

Trajectory interaction is enabled by default. In UIKit, disable it when touch input
must be handled by the surrounding user interface:

```swift
remoteVideoView.isInteractionEnabled = false
```

In SwiftUI, set `isInteractionEnabled` when constructing `XmaxVideo`:

```swift
XmaxVideo(
    track: remoteStream.videoTrack,
    isInteractionEnabled: false
)
```

## Reference Image Upload

`RealtimeContext.referencePath` requires a remote image URL. To use an on-device
image, upload it through the storage manager and supply the resulting URL:

```swift
let storage = try client.createStorageManager()

let uploaded = try await storage.uploadImage(
    at: imageFileURL,
    contentType: "image/jpeg"
)

let referenceImageURL = uploaded.url.absoluteString
```

The storage manager uses temporary credentials obtained from Xmax. Tencent Cloud
credentials are not embedded in the host application.

## Frame Interpolation

On supported devices running iOS 26 or later, XmaxSDK can interpolate remote
generated video frames. Frame interpolation is enabled by default and can be changed
at runtime:

```swift
try await realtime.setFrameInterpolationEnabled(false)
```

Check whether the current device supports interpolation for a specific video size
with `client.createMediaService().supportsFrameInterpolation(for:)`.

## Logging

SDK logging is disabled by default. Enable business logs, performance logs, or both
when creating the client:

```swift
let configuration = XmaxConfiguration(
    apiKey: "YOUR_API_KEY",
    loggerOptions: [.business, .performance]
)

let client = XmaxClient(configuration: configuration)
```

Logging configuration is process-wide and shared by all `XmaxClient` instances.

## Example Project

A runnable reference application with UIKit and SwiftUI implementations is available
in [`Examples/XLab`](https://github.com/XingMai/XmaxSDK-iOS/tree/main/Examples/XLab).
The application demonstrates realtime generation with camera, image, and local
video inputs, together with custom prompts, reference image selection, and
trajectory rendering.

<p align="center"><img src="./docs/images/xlab/home.jpg" alt="X-Lab home" width="20%" /><img src="./docs/images/xlab/features.jpg" alt="X-Lab SDK features" width="20%" /><img src="./docs/images/xlab/storage.jpg" alt="X-Lab storage service" width="20%" /><img src="./docs/images/xlab/realtime-generation.jpg" alt="X-Lab realtime generation" width="20%" /><img src="./docs/images/xlab/trajectory-generation.jpg" alt="X-Lab trajectory generation" width="20%" /></p>

## Dependencies

- VolcEngine RTC SDK for iOS provides real-time audio and video communication.
- Tencent Cloud COS SDK provides image and video transfer through object storage.

## Distribution

- CocoaPods source distribution is supported.
- Manual XCFramework distribution is available through GitHub Releases.
- Swift Package Manager is not supported in version 1.0.2.

## Feedback

For bug reports and feature requests, use
[GitHub Issues](https://github.com/XingMai/XmaxSDK-iOS/issues). For integration
questions and technical support, contact [sdk@xmax.ai](mailto:sdk@xmax.ai).

## License

XmaxSDK is available under the terms of the [MIT License](LICENSE).
