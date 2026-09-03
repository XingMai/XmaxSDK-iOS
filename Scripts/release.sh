#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname -- "$script_dir")
podspec="$repo_dir/XmaxSDK.podspec"
readme="$repo_dir/README.md"
sdk_info="$repo_dir/Sources/XmaxSDK/XmaxSDKInfo.swift"
example_project="$repo_dir/Examples/XLab/XLab.xcodeproj/project.pbxproj"
publish=false

usage() {
  echo "Usage: $0 [--publish]" >&2
  echo "  no option   Sync versions, lint, and build release artifacts." >&2
  echo "  --publish   Also commit all changes, push the branch and tag, and create the GitHub Release." >&2
}

case ${1:-} in
  '') ;;
  --publish) publish=true ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  usage
  exit 2
fi

for command_name in git ruby; do
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

case "$version" in
  *[!0-9A-Za-z.+-]*|''|.*|*.)
    echo "error: invalid release version: $version" >&2
    exit 1
    ;;
esac

if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$'; then
  echo "error: spec.version is not a semantic version: $version" >&2
  exit 1
fi

git_root=$(git -C "$repo_dir" rev-parse --show-toplevel)
if [ "$git_root" != "$repo_dir" ]; then
  echo "error: expected repository root $repo_dir, found $git_root" >&2
  exit 1
fi

branch=$(git -C "$repo_dir" branch --show-current)
if [ -z "$branch" ]; then
  echo "error: releases cannot be created from a detached HEAD" >&2
  exit 1
fi

if [ "$publish" = true ]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "error: GitHub CLI is required for --publish: https://cli.github.com/" >&2
    exit 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo "error: GitHub CLI is not authenticated; run: gh auth login" >&2
    exit 1
  fi
  if git -C "$repo_dir" rev-parse -q --verify "refs/tags/$version" >/dev/null; then
    echo "error: local tag already exists: $version" >&2
    exit 1
  fi

  set +e
  git ls-remote --exit-code --tags origin "refs/tags/$version" >/dev/null 2>&1
  remote_tag_status=$?
  set -e
  case "$remote_tag_status" in
    0)
      echo "error: remote tag already exists: $version" >&2
      exit 1
      ;;
    2) ;;
    *)
      echo "error: could not check remote tag $version on origin" >&2
      exit 1
      ;;
  esac
fi

echo "Synchronizing release version $version..."
ruby - "$version" "$readme" "$sdk_info" "$example_project" <<'RUBY'
version, readme_path, sdk_info_path, project_path = ARGV
semver = /\d+\.\d+\.\d+(?:[+-][0-9A-Za-z.-]+)?/

files = {
  readme_path => File.read(readme_path),
  sdk_info_path => File.read(sdk_info_path),
  project_path => File.read(project_path)
}

def replace_required(content, pattern, replacement, description)
  count = content.scan(pattern).length
  abort "error: could not find #{description}" if count.zero?
  content.gsub(pattern, replacement)
end

readme = files.fetch(readme_path)
readme = replace_required(
  readme,
  /(:tag\s*=>\s*['"])#{semver}(['"])/,
  "\\1#{version}\\2",
  "the CocoaPods tag in #{readme_path}"
)
readme = replace_required(
  readme,
  /XmaxSDK-#{semver}(?:\.xcframework)?\.zip/,
  "XmaxSDK-#{version}.xcframework.zip",
  "the XCFramework download filename in #{readme_path}"
)
readme = replace_required(
  readme,
  %r{(/releases/download/)#{semver}(/)},
  "\\1#{version}\\2",
  "the GitHub Release download version in #{readme_path}"
)
readme = readme.gsub(
  /(Swift Package Manager is not supported in version )#{semver}/,
  "\\1#{version}"
)
files[readme_path] = readme

files[sdk_info_path] = replace_required(
  files.fetch(sdk_info_path),
  /(public static let version\s*=\s*['"])#{semver}(['"])/,
  "\\1#{version}\\2",
  "XmaxSDKInfo.version in #{sdk_info_path}"
)

files[project_path] = replace_required(
  files.fetch(project_path),
  /(MARKETING_VERSION\s*=\s*)#{semver}(;)/,
  "\\1#{version}\\2",
  "MARKETING_VERSION in #{project_path}"
)

files.each do |path, content|
  File.write(path, content) if File.read(path) != content
end
RUBY

echo "Linting the CocoaPods specification..."
"$script_dir/lint-cocoapods.sh"

release_dir="$repo_dir/.build/releases/$version"
release_zip="$release_dir/XmaxSDK-$version.xcframework.zip"
release_checksum="$release_zip.sha256"

if [ -e "$release_dir" ]; then
  echo "Removing the previous generated artifacts for $version..."
  rm -rf "$release_dir"
fi

echo "Building the GitHub Release artifacts..."
"$script_dir/build.sh"

git -C "$repo_dir" diff --check
git -C "$repo_dir" diff --cached --check

for artifact in "$release_zip" "$release_checksum"; do
  if [ ! -f "$artifact" ]; then
    echo "error: expected release artifact was not generated: $artifact" >&2
    exit 1
  fi
done

if [ "$publish" = false ]; then
  echo
  echo "Release $version is prepared locally. Review the changes before publishing:"
  echo "  git -C $repo_dir status --short"
  echo "  $0 --publish"
  exit 0
fi

echo "Committing all current repository changes for release $version..."
git -C "$repo_dir" add -A
if git -C "$repo_dir" diff --cached --quiet; then
  echo "No new release files need to be committed; using the current HEAD."
else
  git -C "$repo_dir" commit -m "Release $version"
fi

git -C "$repo_dir" tag -a "$version" -m "Release $version"

echo "Pushing branch $branch and tag $version atomically..."
git -C "$repo_dir" push --atomic origin \
  "HEAD:refs/heads/$branch" \
  "refs/tags/$version"

echo "Creating GitHub Release $version and uploading artifacts..."
gh release create "$version" \
  "$release_zip" \
  "$release_checksum" \
  --repo XingMai/XmaxSDK-iOS \
  --verify-tag \
  --generate-notes

echo "Release $version published successfully."
