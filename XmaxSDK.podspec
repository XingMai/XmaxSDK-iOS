Pod::Spec.new do |spec|
  spec.name = 'XmaxSDK'
  spec.version = '0.1.0'
  spec.summary = 'Xmax realtime generation SDK for iOS.'
  spec.description = <<-DESC
    XmaxSDK provides the native iOS APIs for Xmax realtime generation.
    Version 1.0 uses CocoaPods and manual integration as its supported
    distribution methods.
  DESC

  spec.homepage = 'https://xmax.ai'
  spec.license = { type: 'MIT', file: 'LICENSE' }
  spec.author = { 'xmax.ai' => 'sdk@xmax.ai' }
  spec.source = {
    git: 'https://github.com/XingMai/XmaxSDK-iOS.git',
    tag: spec.version.to_s
  }

  spec.platform = :ios, '15.0'
  spec.swift_version = '6.0'
  spec.module_name = 'XmaxSDK'
  spec.source_files = 'Sources/XmaxSDK/**/*.swift'

  spec.test_spec 'Tests' do |tests|
    tests.source_files = 'Tests/XmaxSDKTests/**/*.swift'
  end
end
