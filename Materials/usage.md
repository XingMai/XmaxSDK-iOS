# Usage guide

Start with the [Quick Start](../README.md#quick-start) for camera input and UIKit
rendering. Unless stated otherwise, the examples below reuse its `client`,
`realtime`, `localStream`, and `videoView`. File URLs refer to files supplied by your
app. Run realtime operations in a lifecycle-owned task and update UI on the main
actor.

- [Camera microphone](#camera-microphone)
- [Remote audio volume](#remote-audio-volume)
- [Image and video inputs](#image-and-video-inputs)
- [External video input](#external-video-input)
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

Creating a camera, image, or external video stream sets the remote playback volume to `0` (muted).
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

Use the resulting stream with the same preview and generation calls. Local video
audio comes from the file and does not require microphone permission.

<br>

## External video input

Implement `RealtimeExternalVideoSource` to supply frames from your own camera,
decoder, or image-processing pipeline:

```swift
@MainActor
final class MyVideoSource: RealtimeExternalVideoSource {
    let videoFormat = RealtimeVideoFormat(width: 1280, height: 720, fps: 30)
    private(set) var sink: (any RealtimeExternalFrameSink)?

    func start(sink: any RealtimeExternalFrameSink) async throws {
        // Bind your producer's callback and submit frames in source.videoFormat.
        self.sink = sink
    }

    func stop() async {
        // Remove your producer's frame callback before returning.
        sink = nil
    }
}

let source = MyVideoSource()
let localStream = try await realtime.createExternalVideoStream(source: source)
videoView.track = localStream.videoTrack
```

From your producer's frame callback, submit video through the bound sink:

```swift
if sink.isRequestingFrames {
    sink.pushVideo(pixelBuffer, timestamp: presentationTimeStamp)
}
```

Store or capture the sink safely for your callback queue. Frames must be upright
NV12 video-range (`420v`) or BGRA buffers matching `source.videoFormat`. XmaxSDK
automatically processes them to `sink.videoFormat`, applying the model's maximum
pixel area and four-pixel alignment. The processed frame is shared by local preview
and uplink; the source frame rate and encoding options are preserved. The producer
controls frame pacing. Timestamps must be nonnegative and monotonically
increasing, including across loops and seeks. Pixels are copied synchronously;
the buffer may be reused after `pushVideo` returns.

To upload audio as well, implement `hasAudio` on your source and return `true`.
From the audio callback, submit decoded PCM buffers through the same sink:

```swift
if sink.isRequestingFrames {
    sink.pushAudio(audioSampleBuffer)
}
```

The audio buffer's presentation timestamp identifies its first sample and must use
the same monotonic timeline as the video timestamp. Keep timestamps increasing
across loops and seeks; do not independently reset audio and video to zero. Submit
buffers at their playback or capture cadence rather than decoding an entire file
into the sink at once. Invalid timestamps and overlapping audio buffers are
ignored. Gaps start new audio segments without inserting silence.

XmaxSDK copies PCM synchronously, converts it to 48 kHz mono PCM16, and sends it
in 10 ms packets. The PCM format and `hasAudio` must remain unchanged while bound.
Compressed audio must be decoded first. Audio is uploaded only while published;
disconnected audio is not queued for reconnection. XmaxSDK does not play submitted
audio locally. Remote playback remains controlled by `setRemoteAudioVolume` and
starts muted for external sources; set a nonzero volume after creating the stream
if remote audio playback is needed.

External input does not request camera or microphone permission.
Frames also drive the SDK preview, so continue supplying them before generation
and after `disconnect()`. Creating the stream marks it ready once binding succeeds;
it does not wait for the first frame or start a session. Use the same generation
calls as other local streams. Call `sink.reportError(error)` for unrecoverable source
failures; XmaxSDK ends the connection and releases the local stream.

After disconnecting, call `stopExternalVideoStream()` to unbind the source, or use
`close()` to release the manager. Both invalidate the sink and call `source.stop()`;
the app remains responsible for releasing its capture or playback resources.

### Media, generation, and return sizes

`sourceMediaSize` is the original media size in its display orientation.
`resolvedMediaSize` is the processed local media size after applying the model's
pixel limit and four-pixel alignment. `generationSize` is the server generation
canvas (`size`), and `targetSize` is the return resolution (`target_size`).

All local input sources use `resolveMediaSize(_:source:)`. Camera dimensions
must match a configured model resolution bucket before any scaling. Images and
videos and external inputs do not need to match a bucket. Local frames are limited to the model's
`maximumInputPixels`, without enlarging smaller inputs, and aligned to multiples
of 4 with the source aspect ratio preserved where possible. For example,
a 3840 × 2160 video becomes 1920 × 1080 with a 2100000-pixel limit. Upload quality
tiers scale this bounded media size further; local preview uses the media size.

`resolveGenerationSize(_:)` selects the closest model bucket for the server's
generation `size`, or applies model area and alignment rules when there are no
buckets. `resolveTargetSize(_:maximumSize:frameInterpolationEnabled:)` calculates
the separate return `target_size` from the downlink bound and interpolation limit,
with final dimensions aligned to multiples of 4.

The local-frame limit does not cap the memory required to decode the original
image or video. Applications do not need to duplicate these sizing calculations.

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

Camera, image, and video trajectories use `resolvedMediaSize`, computed by
`resolveMediaSize`, not `sourceMediaSize`, the model generation size, or return
`target_size`. The SDK calculates Fit/Fill geometry from `resolvedMediaSize` and
the view dimensions, then sends normalized coordinates in `[0, 1]` relative to
the complete processed media frame. The trajectory overlay uses the same geometry;
received frame dimensions do not update the interaction coordinate basis.
The top-left corner is `(0, 0)` and the bottom-right corner is `(1, 1)`.
Quality-tier and interpolation changes do not change this coordinate basis.
The signaling payload uses `"tracks": [[x, y], ...]`; the server must interpret
these values as normalized media coordinates, not pixels, and map them to the
actual uplink frame dimensions.

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

XmaxSDK calculates the return size from the local media baseline and the current
downlink quality tier, separately from the model generation size. Return width
and height are always multiples of 4. The SDK preserves the exact aspect ratio
when possible; otherwise, it rounds both dimensions down, allowing a small ratio
difference without enlarging the image.

When interpolation is enabled and supported, the return size is also limited to
900000 pixels. For example, a local media baseline of 832 × 1472 at L1 returns
676 × 1196. Lower quality tiers may reduce it further. These return-size changes
do not alter local capture or the model generation size.

During generation, enabling interpolation requests the smaller return size with
`change_target_size`; disabling it requests the current downlink tier's 4-aligned
size. The connection and generation task remain active. Frames at the old size continue to
display without interpolation until frames at the requested size arrive.

Before generation starts, the toggle updates the size used by the next start
request. Switching while another realtime operation is in progress throws an
error. Signaling failures also throw without changing the current configuration;
handle these errors at the call site to give the user feedback.

To inspect the size calculation and device support, pass the original media size
and a downlink size bound. The SDK first applies this bound, reduces the size only
if the interpolation pixel limit is exceeded, then performs the final alignment.
The following example uses the original size as the bound (L1):

```swift
let media = client.createMediaService()
let returnSize = try media.resolveTargetSize(
    CGSize(width: 832, height: 1472),
    maximumSize: CGSize(width: 832, height: 1472),
    frameInterpolationEnabled: true
)
let supported = media.supportsFrameInterpolation(for: returnSize)
```

The calculation itself is device-independent. Unsupported devices retain the
current downlink tier's 4-aligned return size with interpolation disabled. Only
frames matching the requested interpolation size enter the interpolation processor; other sizes
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
