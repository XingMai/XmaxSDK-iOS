# Usage guide

Start with the [Quick Start](../README.md#quick-start) for camera input and UIKit
rendering. Unless stated otherwise, the examples below reuse its `client`,
`realtime`, `localStream`, and `videoView`. File URLs refer to files supplied by your
app. Run realtime operations in a lifecycle-owned task and update UI on the main
actor.

- [Camera microphone](#camera-microphone)
- [Remote audio volume](#remote-audio-volume)
- [Image and video inputs](#image-and-video-inputs)
- [Upload encoding](#upload-encoding)
- [Reference images](#reference-images)
- [Update generation conditions](#update-generation-conditions)
- [SwiftUI](#swiftui)
- [Touch interaction](#touch-interaction)
- [Lifecycle and errors](#lifecycle-and-errors)
- [Generated video frames](#generated-video-frames)
- [Frame interpolation](#frame-interpolation)
- [Logging](#logging)

<br>

## Camera microphone

Camera input does not use the microphone by default. Opt in when creating the
local camera stream:

```swift
let localStream = try await realtime.createLocalCameraStream(
    position: .front,
    useMicrophone: true
)
```

Add `NSMicrophoneUsageDescription` to your app's `Info.plist`. XmaxSDK requests
microphone permission when creating the stream and throws an `XmaxError` if
permission is denied. Creating the stream only starts camera preview; microphone
capture starts when you call `connect(localStream:)` or the one-call
`startGeneration(localStream:context:)` flow. The microphone is not played back
locally.

`disconnect()` stops microphone capture while preserving camera preview.
Reconnecting the same stream starts capture again. Connection failure or
cancellation also stops capture. `stopLocalCameraStream()` and `close()` release
the local capture resources. Switching cameras does not restart the microphone.

<br>

## Remote audio volume

Creating a camera or image stream sets the remote playback volume to `0` (muted).
Creating a file video stream sets it to `1`. To override the initial volume, call
the existing setter after creating the local stream:

```swift
try await realtime.setRemoteAudioVolume(0.5)
let volume = await realtime.remoteAudioVolume
```

Starting generation, reconnecting the same stream, and switching cameras preserve
the current volume. Creating a new local stream applies its initial volume again.
This controls remote playback only, not microphone capture, audio upload, or local
video preview volume.

<br>

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

<br>

## Upload encoding

Pass a `RealtimeVideoFormat` when creating a camera, image, or video stream to
override its upload bitrate and encoding preference:

```swift
let format = RealtimeVideoFormat(
    width: 832,
    height: 1472,
    fps: 24,
    minimumBitrate: 1500,
    maximumBitrate: 3000,
    encoderPreference: .maintainFramerate
)
let localStream = try await realtime.createLocalCameraStream(
    videoFormat: format,
    position: .front
)
```

Bitrates are in kbps. Each omitted bitrate uses the SDK's reference-table estimate
for the final upload dimensions and frame rate. Explicit values survive model
size adaptation. The minimum must be nonnegative and the maximum must be positive;
if the minimum exceeds the maximum after defaults are applied, encoding
configuration throws an `XmaxError` instead of adjusting the supplied values.

The default preference is `.auto`, balancing frame rate and resolution.
`.maintainFramerate` prioritizes frame rate; `.maintainQuality` prioritizes
resolution. These settings apply to upload encoding, not the server's return size
or remote frame interpolation. Configure them when creating the stream; existing
calls that omit them retain the SDK defaults.

<br>

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

<br>

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

<br>

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

<br>

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

<br>

## Lifecycle and errors

Keep the realtime manager for the lifetime of the generation screen. Handle errors
from throwing calls, cancel the screen's owning task when leaving, and call
`close()` on exit or if startup fails. These lifecycle methods serve different
purposes; they are not required sequential steps:

| Method | Effect |
| --- | --- |
| `await realtime.disconnect()` | Stops generation and closes the remote session, retaining the local preview. |
| `await realtime.close()` | Releases the connection, local media, and RTC resources. |

To stop generation and return to the local preview in UIKit:

```swift
await realtime.disconnect()
videoView.remoteTrack = nil
```

In SwiftUI, clear the remote track in your observable state instead.

Register a state listener before creating the local stream or starting generation:

```swift
await realtime.setStateListener { state in
    print(
        "Xmax realtime state: \(state.connectionState.rawValue), " +
        "session: \(state.sessionID ?? "-"), task: \(state.taskID ?? "-")"
    )
    if case .failure(let error) = state.reason {
        print("Xmax realtime error: \(error.code.rawValue) \(error.message)")
    }
}
```

Handle errors thrown by async calls with `do/catch`. Configuration and permission
failures are reported to the caller without a separate error callback. Failures
that end the realtime workflow are available through `state.reason` after cleanup
completes. The final state is `ready` when usable local media is retained, or `idle`
when it has been released. Normal disconnection reports `.normal`.

<br>

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

<br>

## Frame interpolation

On supported devices running iOS 26 or later, XmaxSDK can interpolate generated
video frames. Frame interpolation is enabled by default and can be changed at
runtime:

```swift
try await realtime.setFrameInterpolationEnabled(false)
```

When interpolation is enabled and supported, XmaxSDK keeps the model generation
size and requests a proportional return size with even dimensions and at most
900000 pixels. For example, generation at 832 × 1472 returns 702 × 1242. Local
capture, model input, and touch coordinates remain at the generation size.

During generation, enabling interpolation requests the smaller return size with
`change_target_size`; disabling it requests the original generation size. The
connection and generation task remain active. Frames at the old size continue to
display without interpolation until frames at the requested size arrive.

Before generation starts, the toggle updates the size used by the next start
request. Switching while another realtime operation is in progress throws an
error. Signaling failures also throw without changing the current configuration;
handle these errors at the call site to give the user feedback.

To inspect the size calculation and device support:

```swift
let media = client.createMediaService()
let returnSize = try media.resolveFrameInterpolationSize(
    CGSize(width: 832, height: 1472)
)
let supported = media.supportsFrameInterpolation(for: returnSize)
```

The calculation itself is device-independent. Unsupported devices retain the
original return size with interpolation disabled. Only frames matching the
requested interpolation size enter the interpolation processor; other sizes
continue to display without interpolation. Processor failures disable
interpolation and are logged without interrupting generation.

<br>

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
