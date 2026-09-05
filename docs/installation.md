# Installation guide

For CocoaPods, follow the [README installation steps](../README.md#cocoapods).
This guide covers manual integration of XmaxSDK 1.0.3.

## Manual integration

### Download the frameworks

Download
[`XmaxSDK-1.0.3.xcframework.zip`](https://github.com/XingMai/XmaxSDK-iOS/releases/download/1.0.3/XmaxSDK-1.0.3.xcframework.zip)
and extract `XmaxSDK.xcframework`. Use the exact dependency versions below:

- [VolcEngineRTC `3.60.106.600`](https://hstob-cdn-tos.volccdn.com/volcengine/VolcEngineRTC/3.60.106.600/VolcEngineRTC.zip):
  use `VolcEngineRTC.xcframework`, `RealXBase.xcframework`, and
  `RTCFFmpeg.xcframework` from the downloaded archive.
- [Tencent Cloud COS iOS SDK `6.5.7`](https://github.com/tencentyun/qcloud-sdk-ios/releases/download/6.5.7/QCloudCOSXML-6.5.7.zip):
  use `QCloudCOSXML.xcframework` and `QCloudCore.xcframework` from the official
  release archive.

### Configure embedding

Add the frameworks to the application target under **Frameworks, Libraries, and
Embedded Content**:

| Framework | Embed setting |
| --- | --- |
| `XmaxSDK.xcframework` | Do Not Embed |
| `QCloudCOSXML.xcframework` | Do Not Embed |
| `QCloudCore.xcframework` | Do Not Embed |
| `VolcEngineRTC.xcframework` | Embed & Sign |
| `RealXBase.xcframework` | Embed & Sign |
| `RTCFFmpeg.xcframework` | Embed & Sign |

The XmaxSDK and COS binaries are static. The three VolcEngine binaries are dynamic
and must be embedded and signed by the application target.

### Configure the target

1. Set the deployment target to **iOS 15.0** or later and **Swift Language Version**
   to **Swift 6**.
2. Add `-ObjC` to **Other Linker Flags**.
3. Link `Accelerate.framework`, `CoreMedia.framework`,
   `CoreTelephony.framework`, `SystemConfiguration.framework`, `libz.tbd`,
   and `libc++.tbd`.
4. Add the COS
   [`PrivacyInfo.xcprivacy`](https://github.com/tencentyun/qcloud-sdk-ios/blob/6.5.7/QCloudCOSXML/PrivacyInfo.xcprivacy)
   file to the application target.
5. Confirm that every XCFramework contains a slice for the target platform and
   architecture. Apple silicon simulator builds require an `arm64` simulator slice.

Only `QCloudCOSXML.xcframework` and `QCloudCore.xcframework` are required for COS.
Do not add `QCloudTrack.xcframework`, `COSBeaconAPI_Base.xcframework`, or QimeiSDK.
The third-party frameworks must be present when importing XmaxSDK because its stable
Swift module interface imports `QCloudCOSXML` and `VolcEngineRTC`.

Continue with the [Quick Start](../README.md#quick-start) to configure permissions
and start generation.
