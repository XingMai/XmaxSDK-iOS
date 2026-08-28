Pod::Spec.new do |spec|
  spec.name = 'XmaxSDK'
  spec.version = '1.0.0'
  spec.summary = 'Xmax realtime generation SDK for iOS.'
  spec.description = <<-DESC
    XmaxSDK provides the native iOS APIs for Xmax realtime generation.
    Version 1.0 uses CocoaPods and manual integration as its supported
    distribution methods.
  DESC

  spec.homepage = 'https://xmax.ai'
  spec.license = { type: 'MIT', file: 'LICENSE' }
  spec.author = { 'XMAX.AI PTE. LTD.' => 'sdk@xmax.ai' }
  spec.source = {
    git: 'https://github.com/XingMai/XmaxSDK-iOS.git',
    tag: spec.version.to_s
  }

  spec.platform = :ios, '15.0'
  spec.swift_version = '6.0'
  spec.module_name = 'XmaxSDK'
  spec.static_framework = true
  spec.source_files = 'Sources/XmaxSDK/**/*.swift'
  spec.preserve_paths = 'THIRD_PARTY_NOTICES.md'

  spec.dependency 'VolcEngineRTC/Core', '3.60.106.600'
  spec.dependency 'VolcEngineRTC/RealXBase', '3.60.106.600'
  spec.dependency 'VolcEngineRTC/RTCFFmpeg', '3.60.106.600'
  spec.dependency 'QCloudCOSXML/Transfer', '6.5.7'

  spec.test_spec 'Tests' do |tests|
    tests.source_files = 'Tests/XmaxSDKTests/**/*.swift'
  end
end
