# AGENTS.local.md — 프로젝트별 확장 규칙
> 위치: /Users/lee/Documents/Apps/CapsuleStash/AGENTS.local.md
> 이 파일은 프로젝트 특화 규칙만 기록. 공통 가이드는 재작성 금지.

## 1. 프로젝트 정보
- **프로젝트명**: Capsule Stash (번들/코드명: CapsuleStash)
- **플랫폼**: macos
- **기술 스택**: Swift + SwiftUI + AppKit 연동 (Menu Bar Extra, NSStatusItem, WKWebView, Quick Look) + SwiftData/SQLite + Keychain
- **선정 이유**: 메뉴바 상주 + 글로벌 단축키 + 블록 혼합 문서 + 오프라인 저장을 네이티브로 구현하기 위함
- **design_profile**: custom — 확정됨
- **작업 모드 기본값**: 정식

## 2. 번들ID / 앱 ID
- macOS bundleIdentifier: `com.borasarang.CapsuleStash` (변경 시 파괴적 변경 가드 적용, 사용자 확인 필수)

## 3. 성능 예산 Override (필요 시)
- budgets.json 기본값 우선, 변경점 없음
- 적용값: Cold Start macos ≤1.5s, 메모리 ≤300MB, 60fps, lcp 해당없음 (네이티브 앱)
- 초과 시 WARN + `bd create --label perf`

## 4. 프로젝트 특화 예외 규칙
- Credential 블록은 일반 텍스트 검색 인덱스에 비밀값 포함 금지, Keychain 또는 별도 암호화 DB 사용
- Shell 명령어 자동 실행 금지 (1차 버전은 복사만 지원)
- `~/Applications/CapsuleStash.app` 복사 시 기존 파일 삭제만 예외적으로 허용 (rules/platforms/AGENTS.macos.md)
- 시스템 UI (설정창·디버그 패널·권한 요청)는 native 규칙 준수 (custom 프로필과 무관)
- 원본 기획: `/Users/lee/Documents/AGENTS/apps-docs/CapsuleStash.md`

## 5. 디자인 토큰 (custom 프로필일 때)
- 색/폰트/간격 등은 docs/DESIGN.md에 정의, 여기서는 프로필만 확정
