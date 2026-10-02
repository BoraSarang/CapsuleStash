#!/usr/bin/env bash
# build_and_run.sh — Capsule Stash (macOS)
# 규칙: workflow.md §4 빌드·검증 게이트
#
# 사용법:
#   ./build_and_run.sh debug macos          # 빌드 + ~/Applications 배포 + 실행
#   ./build_and_run.sh build macos          # 빌드만
#   ./build_and_run.sh test macos smoke     # 스모크 테스트
#   ./build_and_run.sh test macos unit      # 유닛 테스트
#   ./build_and_run.sh clean                # DerivedData 정리

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="CapsuleStash.xcodeproj"
SCHEME="CapsuleStash"
DERIVED="$ROOT/.build/dd"
APP_DEST="$HOME/Applications/CapsuleStash.app"

MODE="${1:-debug}"
PLATFORM="${2:-macos}"
VARIANT="${3:-}"

log()  { printf '\033[1;33m[build]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 이(가) 없습니다. 설치 후 다시 시도하세요."
}

# Xcode 프로젝트가 없으면 project.yml 로 생성한다.
ensure_project() {
  require_tool xcodegen
  if [[ ! -d "$ROOT/$PROJECT" ]]; then
    log "Xcode 프로젝트 생성 (xcodegen)"
    (cd "$ROOT" && xcodegen generate >/dev/null)
  fi
}

do_build() {
  ensure_project
  log "빌드 시작: $SCHEME (Debug)"
  (cd "$ROOT" && xcodebuild \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration Debug \
      -derivedDataPath "$DERIVED" \
      build CODE_SIGNING_ALLOWED=NO)
}

do_deploy() {
  local built="$DERIVED/Build/Products/Debug/CapsuleStash.app"
  [[ -d "$built" ]] || fail "빌드 결과물이 없습니다: $built"

  # rules/platforms/AGENTS.macos.md: 배포 복사 시 기존 .app 삭제는 예외적으로 허용
  mkdir -p "$HOME/Applications"
  if [[ -e "$APP_DEST" ]]; then
    log "기존 앱 삭제 후 교체: $APP_DEST"
    rm -rf "$APP_DEST"
  fi
  cp -R "$built" "$APP_DEST"
  log "배포 완료: $APP_DEST"
}

do_run() {
  pkill -x "CapsuleStash" 2>/dev/null || true
  sleep 0.3
  open -a "$APP_DEST"
  log "실행됨. PID: $(pgrep -x CapsuleStash | tr '\n' ' ')"
}

run_tests() {
  (cd "$ROOT" && xcodebuild \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration Debug \
      -derivedDataPath "$DERIVED" \
      test CODE_SIGNING_ALLOWED=NO)
}

do_test() {
  ensure_project
  local scope="${VARIANT:-unit}"
  log "테스트: $scope (budgets.json test_budget: unit ≤60s)"
  case "$scope" in
    unit|full) run_tests ;;
    smoke)
      # 스모크 = 유닛 테스트 + 빌드 + 실행 후 프로세스 생존 확인
      run_tests
      do_build
      do_deploy
      do_run
      sleep 2
      pgrep -x "CapsuleStash" >/dev/null || fail "앱이 기동 직후 종료됨"
      log "스모크 통과 (프로세스 생존 확인)"
      ;;
    *) fail "알 수 없는 테스트 범위: $scope (unit|smoke|full)" ;;
  esac
}

case "$MODE" in
  build) do_build ;;
  test)  do_test ;;
  clean) log "DerivedData 삭제"; rm -rf "$ROOT/.build" ;;
  debug)
    case "$PLATFORM" in
      macos)
        do_build
        do_deploy
        [[ "$VARIANT" == "nobuild" ]] || do_run
        ;;
      all) log "현재 macOS 만 지원"; do_build; do_deploy; do_run ;;
      *) fail "지원하지 않는 플랫폼: $PLATFORM" ;;
    esac
    ;;
  *) fail "알 수 없는 명령: $MODE" ;;
esac