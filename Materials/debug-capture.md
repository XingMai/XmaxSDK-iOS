# Remote audio and video debug capture

The Debug-only probe records native remote PCM and both decoded and processed video
timing. Use it to investigate timestamp compatibility before choosing a public
audio/video output contract. It does not assume the audio and video timestamp
fields share a clock, and does not correct timestamps to make them appear aligned.
Build XmaxSDK from source in Debug; distributed Release XCFrameworks omit the probe.

## Run on an iPhone

1. Open `Examples/XLab/XLab.xcworkspace`. After updating source files, run
   `pod install --deployment --no-repo-update` in `Examples/XLab`.
2. Select the **XLab-Diagnostics** scheme and your iPhone, then Run. This scheme
   uses Debug; the existing XLab scheme continues to use Release for Run.
3. Open the **UIKit** realtime generation screen, preferably with a local video
   that contains a clear audio track. Tap **AV Debug 探针**, then
   **开始采集（最多 90 秒）**, before starting remote generation.
4. Run generation for 30–60 seconds. Tap the probe again, select
   **停止采集并导出 ZIP**, and save or share the archive through the system sheet.
   **分享上次诊断包** shares the same archive again.
5. Capture separate runs with frame interpolation disabled and enabled on a
   supported iPhone. For content synchronization measurements, use a source with
   known simultaneous visual and audio markers.

Leaving the screen stops and saves a capture started on that screen. The probe
stops admitting samples after 90 seconds; stop and export explicitly to finalize
its MP4 segments. Documents/XmaxDiagnostics retains directories and archives until
you remove them. The console prints their paths with the `[XmaxAVProbe]` prefix.

The probe records media on the device and exports only when requested. It does not
send diagnostic media to a server. Remote audio must actually be published and
subscribed; local preview audio is not evidence that remote PCM is available.

## Archive contents

| File | Contents |
| --- | --- |
| `events.jsonl` | Native audio clocks, exact video CMTime values, arrival times, opaque room lifetimes, UIDs, observer/subscription state, PCM offsets and video write results. |
| `audio_*.pcm` | Copies of pre-mix and aggregate remote-playback audio, separated by tap, room lifetime, UID, sample rate, channel count and bytes per sample. |
| `video_*.mp4` | Processed video after optional interpolation, encoded without audio. A stream, size or backward PTS change starts another segment. |
| `summary.json` | Counts, diagnostic queue drops, duration limit, PCM bytes and writer errors. |
| `README.txt` | Timestamp and payload interpretation instructions. |

XLab-Diagnostics also registers the public `setRemoteMediaFrameListener`. When
that listener is active, `media_output` events record the delivered stream ID,
track, discontinuity flag, PTS and duration. These fields describe SDK output:
audio uses the sample-based rendering timeline, while video retains processed
frame timing. Original native `audio` and `video_decoded` events remain unchanged,
so the derived output can be compared with its native evidence. An output event
does not itself prove sound-picture content synchronization.

All JSON Lines values are strings. `host_ns` is receiver monotonic arrival time;
it is not media PTS. Audio `render_ms`, `presentation_ms` and `rtp_timestamp` are
stored verbatim. No field is selected as an authoritative synchronization clock.
Schema 2 records `tap=before_mixing` for individual remote users and
`tap=playback_mixed` for aggregate remote playback, whose UID is represented as 0.
The aggregate tap is a diagnostic comparison, not an individual user's audio track.
`audio_callback_seen` records native entry before channel/buffer filtering, and
`native_audio_state` records receiving/decoding/frozen/failed states. These help
distinguish an inactive tap from filtering or unavailable decoded audio. The
two taps explicitly request 48 kHz mono packets of 480 samples through the native
engine format setters; the playback comparison uses read-only mode. Their return
codes are stored in `audio_observer`, and each packet records the actual format.
An empty channel on aggregate playback is attributed to the observer's sole
SDK-owned room and marked as such; a nonempty mismatched channel never writes PCM.
For video, divide `pts_value` by `pts_scale` only if the CMTime flags indicate a
numeric time. `video_segment` records the source timestamp corresponding to zero
in that segment's MP4.

PCM packets are concatenated without inserting silence. Reconstruct timing from
each packet's metadata, not from its byte offset alone. MP4 and PCM are separate
diagnostic evidence, not a synchronized movie ready for playback. A capture with
no audio files still contains observer/subscription information for investigation.

Capture is capped at 90 seconds, 32 MiB of pending media, 2048 pending events,
32 MiB of saved PCM and 32 video segments. Queue drops and video encoder
backpressure are recorded separately from network loss. Encoding can itself add
load, so compare capture results with the probe disabled when investigating
performance. The probe does not change audio subscriptions or volume.

## Debug-only API

Custom debug tools can use the same process-wide recorder:

```swift
#if DEBUG
try await XmaxDebugCapture.shared.start()
// Run the realtime session, then finish before reading or sharing its files.
let archive = try await XmaxDebugCapture.shared.stopAndExport()
#endif
```

The probe does not use or replace `setRemoteVideoFrameListener`, so existing
recording callbacks continue to receive their frames. Release builds contain
the public remote-media output path, while omitting the capture API, diagnostic
playback tap and example controls.
