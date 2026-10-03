# PLAN_v0.1_macos.md
> 생성일: 2026-10-02 | 플랫폼: macos | 작성자: OpenCode
> 원본 기획: /Users/lee/Documents/AGENTS/apps-docs/CapsuleStash.md (CapsuleStash 종합 계획서)

## 1. 목표 (1줄)
텍스트·Markdown·코드·웹페이지·이미지·계정정보를 하나의 Collection에 묶어 저장하고 메뉴바 Command Palette에서 즉시 검색·복사하는 Mac용 개인 지식 워크스페이스 Capsule Stash의 MVP를 구축한다.

## 2. 범위
- 플랫폼: macos
- 기술 스택: Swift + SwiftUI + AppKit 연동 (Menu Bar Extra, NSStatusItem, 글로벌 단축키, WKWebView, Quick Look) + SwiftData/SQLite + Keychain + 선정 이유 1줄: 메뉴바 상주와 오프라인 아카이브를 네이티브 성능으로 구현하기 위함
- design_profile: custom (시스템 UI는 native 준수, 블록 문서·팔레트는 자체 디자인 시스템, 토큰은 docs/DESIGN.md)
- 정보 구조: Workspace → Project → Collection → Block (3단계 고정, 추가 분류는 태그+검색)
- MVP 포함: Workspace/Project/Collection CRUD + 트리 UI + Text/Markdown/Code/Image/WebLink 블록 + 블록별 복사 + 전체 복사 + 전체 텍스트 검색 + 타입/Project 필터 + 메뉴바 상주 + 글로벌 단축키 + Command Palette 기본 검색·복사
- MVP 제외 (2·3차): Web Archive/PDF 오프라인 저장, 드래그앤드롭 정렬 고도화, 브라우저 확장, 클립보드 빠른 저장, OCR, 태그 시스템 고도화, Credential 암호화 관리 + Touch ID + 클립보드 자동삭제, iCloud 동기화, 버전 기록·백업·export

## 3. 문서 위치
- PLAN: 본 문서 (docs/plans/PLAN_v0.1_macos.md)
- TODO: docs/TODO.md T-번호 등록
- DESIGN: docs/DESIGN.md 갱신 (custom 토큰 정의)
- API: docs/api/ENDPOINTS.md (해당 없음, 로컬 앱이므로 미생성)
- 원본 기획 보관: /Users/lee/Documents/AGENTS/apps-docs/CapsuleStash.md

## 4. 성능 예산
- budgets.json 참조 + macos 플랫폼 규칙 적용
- Cold Start ≤1.5s, 메모리 RSS ≤300MB, 60fps 유지
- 테스트 예산: smoke ≤10s, unit ≤60s, full ≤5m (기본 피드백 루프는 smoke+unit만)
- 초과 시 WARN + `bd create --label perf` (실패 처리 아님)

## 5. 에러 코드
- 사용할 에러 코드 범위: E-MACOS-CAPSULE-0001~ (형식: E-{PLATFORM}-{CATEGORY}-{NUM4})
- error_message_ko.json에 한국어 메시지 등록 예정 (정식 모드 DoD)

## 6. 빌드 & 검증 계획
- 문서 작성 → 코드 구현 → 테스트 → `./build_and_run.sh debug macos` (프로젝트 생성 후 스크립트 도입 예정, 당장은 `xcodebuild` 직접 빌드)
- 결과물: `~/Applications/Capsule Stash.app` 복사 (구 `CapsuleStash.app` 잔재는 배포 시 제거)
- 테스트: smoke/unit 우선, full은 변경 범위 클 때
- DebugPanel 검증 항목: ERROR 0, PERF/CACHE 예산, 로그 마스킹 (토큰·비밀번호 미출력)
- 다음 단계: Xcode 프로젝트 생성 후 빌드 게이트 확정

## 7. 예외 규칙 (있으면)
- Shell 블록 자동 실행 금지 → 복사로만 제공 (보안)
- Credential 비밀값 검색 인덱스·로그·DebugPanel 출력 금지 (Keychain 격리)
- 본 공통 규칙과 충돌하는 요청은 거부하지 말고 예외 1줄을 docs/DESIGN.md에 기록하고 진행 ([HARD]는 사용자 승인 필요)

## 8. 실행 기록 (2026-10-02, MVP 완료)
- T-01~T-08 구현 완료. 유닛 43개 통과, 빌드·배포·실행 확인.
- 저장 계층은 SwiftData 대신 Codable + `Application Support/CapsuleStash/library.json` (2차 T-11에서 SwiftData 전환).
- Credential 비밀값은 MVP에서 **메모리 전용**: `DataStore.persistableSnapshot(from:)` 이 `credential` 을 `nil` 로 바꿔 디스크에 기록하며, 로그·검색 인덱스에도 들어가지 않는다. 복사는 `copyPayload(includeSecrets:)` 가 Vault 잠금과 연동. Keychain + Touch ID 는 T-10.
- 디자인 시스템은 라이트 전용으로 고정 (`Theme.applyFixedAppearance()`). 다크모드는 T-18.
- 팔레트 `⌘C` 는 검색창 텍스트 복사와 충돌해 제외, 결과 행 `복사` 버튼으로 대체 (`docs/DESIGN.md` §4).
- 목업 대조 수정: 사이드바 `.proj` 인덴트, 블록 편집 시트, 태그 편집, 날짜 `yyyy-MM-dd`, `블록 추가` popover. 창 캡처로 대조 확인.
- 성능 측정: Cold Start 565ms / RSS 124MB / 저장소 준비 0–3ms.
- 2단 확정 (Workspace → Project 문서): 중간 단 삭제, 旧 묶음명은 태그·색 승계, 빈 묶음은 빈 문서 보존, 문서 id 승계. v1 파일 자동 마이그레이션 + 즉시 v2 저장. 테스트는 `CAPSULESTASH_TEST_DIR` 격리 (테스트 호스트가 앱이라 실제 파일 접근 차단, md5 불변 확인).
- T-19 아이콘 적용 (2026-10-02): `KnowledgeVault-macOS26-Icons.zip` README 기준 `Assets.xcassets` 추가. AppIcon Light/Dark + MenuBar 템플릿. 빌드 성공, `AppIcon.icns`+`Assets.car(MenuBar 2건)` 확인, 유닛 56개 통과, `~/Applications` 배포·실행 확인.
- T-20 블록 추가 메뉴 정렬: `BlockTypeLabel` 아이콘 22pt 고정폭 (popover+타이틀바 메뉴 공통).
- T-21/22 Credential Secret 2칸: `secondSecret` + 편집 시트 Secret 1/2 + 카드 조건부 표시, 검색·기본복사 제외 [HARD].
- T-23 Project 드래그 이동: 행 onDrag + 섹션 onDrop·하이라이트 + `moveProject`.
- T-10 Keychain 영구 저장 (2026-10-02): 시크릿만 Keychain 블록 ID 단위 보관, JSON엔 홈페이지·아이디만. 기동 시 복원, 삭제 시 정리, Vault 해제는 Touch ID·Face ID 우선(설정 토글, 미지원 기기는 바로 해제). 클립보드 자동삭제는 기존 유지. 유닛 64개 통과, `library.json` 시크릿 0건 확인.
- T-11 SwiftData 하이브리드 (2026-10-02): `Stores/SwiftDataBackend.swift` 신규 (SDWorkspace/SDProject/SDBlock + 경계 매핑). DataStore 구조체 인터페이스 유지, 저장만 교체. library.json→database.sqlite 1회 이관 후 동결, 실패 시 JSON 폴백. 블록 ID 승계(Keychain 연결), 순서(sortOrder) 보존, 시크릿 컬럼 없음. 실데이터 이관 확인(2 WS/2 PRJ/25 BLK), 재실행 시 DB 무변경. 유닛 67개 통과.
- T-24~T-36 + Dock 설정 + T-25 한·영 + T-26~T-32 (2026-10-02~03): 툴바·본문 폴리시, Credential Secret 2칸 대신 Secret 1/2 라벨 정리, Project DnD·문서 순서, SwiftData 순서 정규화, Keychain 정리 통합, Web Archive 실파일, 인라인 편집, 외부 드롭, 팔레트 단축키, 전각·tag 검색, 종료 잠금, Dock 토글, 다크모드 적응형 토큰, 다국어 카탈로그 220종, 마크다운 렌더링, 웹 단일화, 삭제 확인, 제목 자동완성, PDF 보기·내보내기, 접힘 UX, 이미지 QuickLook, 메뉴바 열기 정리, 드래그 범위, 단축키 변경(기본 ⌘.). 유닛 100개, 전부 `~/Applications/Capsule Stash.app` 배포·실행 확인.
