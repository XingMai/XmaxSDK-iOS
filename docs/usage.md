# Usage guide

Start with the [Quick Start](../README.md#quick-start) for camera input and UIKit
rendering. Unless stated otherwise, the examples below reuse its `client`,
`realtime`, `localStream`, and `videoView`. File URLs refer to files supplied by your
app. Run realtime operations in a lifecycle-owned task and update UI on the main
actor.

- [Image and video inputs](#image-and-video-inputs)
- [Reference images](#reference-images)
- [Update generation conditions](#update-generation-conditions)
- [SwiftUI](#swiftui)
- [Touch interaction](#touch-interaction)
- [Lifecycle and errors](#lifecycle-and-errors)
- [Generated video frames](#generated-video-frames)
- [Frame interpolation](#frame-interpolation)
- [Logging](#logging)

## Image and video inputs

Replace camera-stream creation in the Quick Start with one of the following.
Only one local input stream may be active at a time.

For a still image:

```swift
let localStream = try await realtime.createLocalImageStream(
    fileURL: imageFileURL
)
```

For a local video:

```swift
let localStream = try await realtime.createLocalVideoStream(
    fileURL: videoFileURL
)
```

Use the resulting stream with the same preview and generation calls. If the video
contains audio, also add a microphone usage description to `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app uses the microphone for real-time audio input.</string>
```

Use wording appropriate for your app. XmaxSDK checks and requests the required
runtime permissions when creating a local stream and reports an `XmaxError` if
permission is unavailable.

## Reference images

`RealtimeContext.referencePath` accepts a remote image URL. To use an on-device
image, upload it before starting generation and pass the resulting URL:

```swift
let storage = try client.createStorageManager()
let uploaded = try await storage.uploadImage(
    at: imageFileURL,
    contentType: "image/jpeg"
)
let referenceImageURL = uploaded.url.absoluteString

let remoteStream = try await realtime.startGeneration(
    localStream: localStream,
    context: RealtimeContext(
        prompt: "Replace the video character with the reference character",
        referencePath: referenceImageURL
    )
)
videoView.remoteTrack = remoteStream.videoTrack
```

The storage manager uses temporary credentials obtained from Xmax. Tencent Cloud
credentials are not embedded in the host application. If the reference image is
already hosted remotely, supply its URL directly without uploading it again.

## Update generation conditions

While generation is active, call `startGeneration(context:)` with a new prompt or
reference image URL. The existing stream and view bindings remain in use:

```swift
try await realtime.startGeneration(
    context: RealtimeContext(prompt: "Transform the scene into an oil painting")
)
```

To keep using a reference image, include its URL in the new context's
`referencePath`.

## SwiftUI

Use `XmaxRealtimeVideo` instead of `XmaxRealtimeVideoView`. Keep the local and
remote tracks in observable state owned by the generation screen. A preview view
can receive those tracks as inputs:

```swift
import SwiftUI
import XmaxSDK

struct GenerationPreview: View {
    let localTrack: RealtimeVideoTrack?
    let remoteTrack: RealtimeVideoTrack?

    var body: some View {
        XmaxRealtimeVideo(
            localTrack: localTrack,
            remoteTrack: remoteTrack,
            videoContentMode: .fill
        )
    }
}
```

In the owning screen or observable model, declare the tracks as optional state.
For example, a SwiftUI screen can use:

```swift
@State private var localTrack: RealtimeVideoTrack?
@State private var remoteTrack: RealtimeVideoTrack?
```

Assign `localStream.videoTrack` to `localTrack` as soon as the local stream is
created, then assign the result of `startGeneration` to `remoteTrack`:

```swift
remoteTrack = remoteStream.videoTrack
```

Render `GenerationPreview(localTrack: localTrack, remoteTrack: remoteTrack)` in the
screen's body. Both UIKit and SwiftUI views keep the local preview active beneath
the generated output, wait for the first remote frame before showing it, and
restore the preview when the remote track is set to `nil`.

See the [SwiftUI example](../Examples/XLab/XLab/Modules/XLRealtime/SwiftUI/RealtimeView.swift)
and its [session controller](../Examples/XLab/XLab/Modules/XLRealtime/SwiftUI/RealtimeSessionController.swift)
for a complete implementation.

## Touch interaction

During an active generation task, both realtime video views capture multi-touch
trajectories over the generated video and submit them to the active task. Gesture
tracking and coordinate conversion are handled by the SDK.

Interaction is enabled by default. To let surrounding UIKit controls handle touch
input instead:

```swift
videoView.isInteractionEnabled = false
```

In SwiftUI, set `isInteractionEnabled` when constructing the video view:

```swift
XmaxRealtimeVideo(
    localTrack: localTrack,
    remoteTrack: remoteTrack,
    isInteractionEnabled: false
)
```

## Lifecycle and errors

Keep the realtime manager for the lifetime of the generation screen. Handle errors
from throwing calls, cancel the screen's owning task when leaving, and call
`close()` on exit or if startup fails. These lifecycle methods serve different
purposes; they are not three required sequential steps:

| Method | Effect |
| --- | --- |
| `await realtime.stopGeneration()` | Stops generation, retaining the connection and local preview. |
| `await realtime.disconnect()` | Closes the remote session, retaining the local preview. |
| `await realtime.close()` | Releases the connection, local media, and RTC resources. |

To stop generation and return to the local preview in UIKit:

```swift
await realtime.stopGeneration()
videoView.remoteTrack = nil
```

In SwiftUI, clear the remote track in your observable state instead.

Register connection-state and fatal-error listeners before starting generation:

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

The error listener reports fatal realtime errors. Recoverable errors are thrown
by the corresponding async calls and should be handled by the caller.

## Generated video frames

To record or process output outside the SDK, register a final-frame listener before
starting generation. Here, `recorder` represents your app's recording pipeline,
not an SDK-provided object:

```swift
await realtime.setRemoteVideoFrameListener { frame in
    recorder.append(
        pixelBuffer: frame.pixelBuffer,
        presentationTimeStamp: frame.presentationTimeStamp,
        duration: frame.duration
    )
}
```

The listener receives frames accepted by the final render pipeline, after optional
frame interpolation, on a dedicated serial background queue. Frame timestamps do
not necessarily start at zero; rebase the recording timeline to the first received
frame. Transfer frames to a thread-safe recording pipeline quickly and avoid
synchronous encoding in the callback. This API exposes video frames only, not
generated audio.

Clear the listener when frame delivery is no longer needed:

```swift
await realtime.setRemoteVideoFrameListener(nil)
```

## Frame interpolation

On supported devices running iOS 26 or later, XmaxSDK can interpolate generated
video frames. Frame interpolation is enabled by default and can be changed at
runtime:

```swift
try await realtime.setFrameInterpolationEnabled(false)
```

Check support for a specific video size with
`client.createMediaService().supportsFrameInterpolation(for:)`.

## Logging

SDK logging is disabled by default. Enable business logs, performance logs, or both
when creating the client, using an API key supplied securely at runtime:

```swift
let configuration = XmaxConfiguration(
    apiKey: apiKey,
    loggerOptions: [.business, .performance]
)
let client = XmaxClient(configuration: configuration)
```

Logging configuration is process-wide and shared by all `XmaxClient` instances.
