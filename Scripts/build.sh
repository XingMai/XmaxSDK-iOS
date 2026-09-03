#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname -- "$script_dir")
example_dir="$repo_dir/Examples/XLab"
podspec="$repo_dir/XmaxSDK.podspec"
output_root=${1:-"$repo_dir/.build/releases"}

: "${DEVELOPER_DIR:=$(xcode-select -p)}"
export DEVELOPER_DIR

for command_name in pod xcodebuild ditto swift unzip; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "error: required command not found: $command_name" >&2
    exit 1
  fi
done

version=$(sed -n "s/^[[:space:]]*spec\.version[[:space:]]*=[[:space:]]*['\"]\([^'\"]*\)['\"].*/\1/p" "$podspec" | head -n 1)
if [ -z "$version" ]; then
  echo "error: could not read spec.version from $podspec" >&2
  exit 1
fi

release_dir="$output_root/$version"
release_framework="$release_dir/XmaxSDK.xcframework"
release_zip="$release_dir/XmaxSDK-$version.xcframework.zip"
release_checksum="$release_zip.sha256"

if [ -e "$release_dir" ]; then
  echo "error: release output already exists: $release_dir" >&2
  echo "Remove it explicitly before rebuilding the same version." >&2
  exit 1
fi

echo "Installing the locked CocoaPods dependencies..."
pod install --project-directory="$example_dir"

pods_project="$example_dir/Pods/Pods.xcodeproj"
if [ ! -d "$pods_project" ]; then
  echo "error: CocoaPods project was not generated: $pods_project" >&2
  exit 1
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/xmax-xcframework.XXXXXX")
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT HUP INT TERM

device_archive="$work_dir/XmaxSDK-iOS.xcarchive"
simulator_archive="$work_dir/XmaxSDK-iOS-Simulator.xcarchive"
combined_framework="$work_dir/XmaxSDK.xcframework"
device_derived_data="$work_dir/DerivedData-iOS"
simulator_derived_data="$work_dir/DerivedData-iOS-Simulator"

echo "Archiving XmaxSDK for iOS devices..."
xcodebuild archive \
  -quiet \
  -project "$pods_project" \
  -scheme XmaxSDK \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$device_derived_data" \
  -archivePath "$device_archive" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  CODE_SIGNING_ALLOWED=NO \
  IPHONEOS_DEPLOYMENT_TARGET=15.0

echo "Archiving XmaxSDK for iOS Simulator..."
xcodebuild archive \
  -quiet \
  -project "$pods_project" \
  -scheme XmaxSDK \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$simulator_derived_data" \
  -archivePath "$simulator_archive" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  CODE_SIGNING_ALLOWED=NO \
  IPHONEOS_DEPLOYMENT_TARGET=15.0 \
  'EXCLUDED_ARCHS[sdk=iphonesimulator*]='

device_framework="$device_archive/Products/Library/Frameworks/XmaxSDK.framework"
simulator_framework="$simulator_archive/Products/Library/Frameworks/XmaxSDK.framework"

for framework in "$device_framework" "$simulator_framework"; do
  if [ ! -d "$framework" ]; then
    echo "error: expected framework was not archived: $framework" >&2
    exit 1
  fi
done

echo "Creating XmaxSDK.xcframework..."
xcodebuild -create-xcframework \
  -framework "$device_framework" \
  -framework "$simulator_framework" \
  -output "$combined_framework"

mkdir -p "$release_dir"
ditto "$combined_framework" "$release_framework"
ditto --norsrc -c -k --keepParent "$release_framework" "$release_zip"

checksum=$(swift package compute-checksum "$release_zip")
printf '%s  %s\n' "$checksum" "$(basename -- "$release_zip")" > "$release_checksum"
unzip -tqq "$release_zip"

echo
echo "XCFramework: $release_framework"
echo "Release ZIP: $release_zip"
echo "SwiftPM checksum: $checksum"
echo "Checksum file: $release_checksum"
echo
echo "This archive intentionally contains XmaxSDK only; it does not redistribute"
echo "VolcEngineRTC, RealXBase, RTCFFmpeg, QCloudCOSXML, or QCloudCore."
