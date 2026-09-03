#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname -- "$script_dir")

: "${DEVELOPER_DIR:=$(xcode-select -p)}"
XCODE_XCCONFIG_FILE="$repo_dir/Configurations/CocoaPodsLint.xcconfig"

export DEVELOPER_DIR
export XCODE_XCCONFIG_FILE

exec pod lib lint "$repo_dir/XmaxSDK.podspec" \
  --sources='https://github.com/volcengine/volcengine-specs.git,https://cdn.cocoapods.org/' \
  --allow-warnings \
  --skip-tests \
  "$@"
