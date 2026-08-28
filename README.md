# XmaxSDK for iOS

XmaxSDK provides native iOS APIs for building real-time interactive video
generation experiences powered by Xmax AI.

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
- CocoaPods
- An Xmax API key

## Installation

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
      :tag => '1.0.0'
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

Use `XmaxVideoView` to display either a local or remote video track:

```swift
let videoView = XmaxVideoView(videoContentMode: .fill)
videoView.track = remoteStream.videoTrack
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

Check device support through `isFrameInterpolationSupported`, or check a
specific video size with `client.createMediaService().supportsFrameInterpolation(for:)`.

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

## Dependencies

XmaxSDK 1.0.0 uses the following official third-party dependencies:

- [VolcEngineRTC](https://docs.volcengine.com/docs/6348/1181844?lang=zh) `3.60.106.600`
- [QCloudCOSXML/Transfer](https://github.com/tencentyun/qcloud-sdk-ios/tree/6.5.7) `6.5.7`

These dependencies are downloaded from their official CocoaPods sources and
are not redistributed by this repository.

For COS integration, XmaxSDK only uses `QCloudCOSXML.framework` and
`QCloudCore.framework` through the Beacon-free `QCloudCore/WithoutMTA`
subspec. QCloudTrack, COSBeaconAPI_Base, and QimeiSDK are not required.

## Distribution

- CocoaPods source distribution is supported.
- Swift Package Manager is not supported in version 1.0.0.
- A prebuilt XCFramework is not included in version 1.0.0.

## Feedback

Please use [GitHub Issues](https://github.com/XingMai/XmaxSDK-iOS/issues) for
bug reports and feature requests.

## License

XmaxSDK is available under the terms of the [MIT License](LICENSE).
