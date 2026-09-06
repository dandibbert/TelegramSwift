#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer
TOOLS="${RUNNER_TEMP:-/tmp}/player-build-tools"
export PATH="$TOOLS/bin:$PATH"
export XCODE_XCCONFIG_FILE="${RUNNER_TEMP:-/tmp}/player-unsigned.xcconfig"
cat > "$XCODE_XCCONFIG_FILE" <<'CONFIG'
CODE_SIGNING_ALLOWED = NO
CODE_SIGNING_REQUIRED = NO
CODE_SIGN_IDENTITY =
DEVELOPMENT_TEAM =
ENABLE_USER_SCRIPT_SANDBOXING = NO
COMPILER_INDEX_STORE_ENABLE = NO
CONFIG
prepare() {
  xcodebuild -version
  git config --global url.https://github.com/.insteadOf git@github.com:
  git config --global url.https://gitlab.com/.insteadOf git@gitlab.com:
  git submodule sync --recursive
  git -c protocol.version=2 submodule update --init --recursive --depth 1 --jobs 4 2>&1 | tee build/logs/submodules.log
  brew install ninja autoconf automake libtool yasm nasm pkg-config meson
  python3 -m venv "$TOOLS"
  "$TOOLS/bin/pip" install 'cmake==3.31.6'
  # The pinned iOS submodule omits the FFmpeg 7.1 source required by the Mac
  # framework project. Use the exact official release commit, never latest.
  local ffsrc=submodules/telegram-ios/submodules/ffmpeg/Sources/FFMpeg/ffmpeg-7.1
  if [[ ! -f "$ffsrc/configure" ]]; then
    git init "$ffsrc"
    git -C "$ffsrc" remote add origin https://github.com/FFmpeg/FFmpeg.git
    git -C "$ffsrc" fetch --depth 1 origin b08d7969c550a804a59511c7b83f2dd8cc0499b8
    git -C "$ffsrc" checkout --detach FETCH_HEAD
  fi
  test "$(git -C "$ffsrc" rev-parse HEAD)" = b08d7969c550a804a59511c7b83f2dd8cc0499b8
  cp configurations/Stable.xcconfig Telegram-Mac/Release.xcconfig
  printf '\nSFEED_URL =\nSANDBOX_YES = NO\nAPPCENTER_SECRET =\n' >> Telegram-Mac/Release.xcconfig
  printf 'no\n' > scripts/rebuild
}
native() {
  bash scripts/configure_frameworks.sh 2>&1 | tee build/logs/frameworks.log
  # This marker is created only after every framework and generated header is
  # complete. CI must never save a partial native build as a reusable cache.
  touch build/.native-ready
}
application() {
  # The external verifier in this Xcode build diagnoses an absent private
  # module while inspecting the versioned CodeSyntax framework. Keep module
  # verification enabled, but use Xcode's compiler-backed verifier instead.
  # Do not disable diagnostics, skip failed targets or manufacture an app.
  local status=0
  xcodebuild build -workspace Telegram-Mac.xcworkspace -scheme Telegram \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath build/DerivedData -resultBundlePath build/Application.xcresult -jobs 3 \
    MODULE_VERIFIER_KIND=builtin CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    2>&1 | tee build/logs/application.log || status=$?
  if [[ $status -ne 0 ]]; then
    grep -nE 'error:|fatal error:|BUILD FAILED|The following build commands failed:' build/logs/application.log > build/logs/errors.txt || true
    cat build/logs/errors.txt
    # Include generated maps/headers, not just a misleading final exit code.
    find build/DerivedData/Build -path '*CodeSyntax*' \( -name '*.modulemap' -o -name '*diagnostic-filename-map.json' \) -type f -print -exec cat {} \; > build/logs/module-maps.txt
  fi
  return "$status"
}
package_app() {
  test -f packages/EnhancedMediaPlayer/Package.swift
  grep -q 'ensurePersonalCredentials' packages/ApiCredentials/Sources/ApiCredentials/Config.swift
  local original=build/DerivedData/Build/Products/Release/Telegram.app
  local app='build/output/Telegram Player.app'
  test -d "$original"
  mkdir -p build/output
  rm -rf "$app"
  cp -R "$original" "$app"
  local plist="$app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Telegram Player' "$plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleName Telegram Player' "$plist"
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" = io.github.dandibbert.TelegramPlayer
  codesign --force --deep --sign - "$app"
  codesign --verify --deep --strict "$app"
  local exe
  exe=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")
  lipo -info "$app/Contents/MacOS/$exe" | tee build/logs/architectures.log
  # This is a no-credentials launch smoke test, not a logged-in playback test.
  "$app/Contents/MacOS/$exe" > build/logs/launch.log 2>&1 &
  local pid=$!
  trap 'kill "$pid" 2>/dev/null || true' EXIT
  sleep 8
  if ! kill -0 "$pid" 2>/dev/null; then
    tail -80 build/logs/launch.log
    echo 'Application exited during first-launch smoke test' >&2
    exit 1
  fi
  kill "$pid"
  wait "$pid" 2>/dev/null || true
  trap - EXIT
  cp docs/ENHANCED_PLAYER.md build/output/README.md
  cat > build/output/BUILD.txt <<INFO
Commit: $(git rev-parse HEAD)
Xcode: $(xcodebuild -version | tr '\n' ' ')
Signing: ad-hoc personal build, not notarized
Credentials: first-launch dialog; API hash stays in the local Keychain
Validation: codesign verification and eight-second launch smoke test
Not validated: account login or real MP4/HLS playback
INFO
  ditto -c -k --sequesterRsrc --keepParent "$app" build/Telegram-Player-macOS.zip
  shasum -a 256 build/Telegram-Player-macOS.zip | tee build/Telegram-Player-macOS.sha256
}
case "${1:-all}" in
  prepare) prepare ;;
  native) native ;;
  application) application ;;
  package) package_app ;;
  all) prepare; native; application; package_app ;;
  *) echo 'Usage: ci-build-player.sh [prepare|native|application|package|all]' >&2; exit 2 ;;
esac
