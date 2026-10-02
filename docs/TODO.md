# TODO — Capsule Stash (macos)
> PLAN: docs/plans/PLAN_v0.1_macos.md | 프로필: custom | 최종 갱신 2026-10-02

## MVP (완료)

- [x] T-01 Xcode 프로젝트 생성 (`project.yml` + xcodegen, SwiftUI, bundle `com.borasarang.CapsuleStash`)
      - `CapsuleStashTests` 유닛 타깃 포함, 스킴에 test 액션 연결
- [x] T-02 데이터 모델 정의 (Workspace/Project 문서/Block/Credential, 2단)
      - Codable 구조체 + `Application Support/CapsuleStash/library.json` 로 시작 → T-11에서 SwiftData 하이브리드로 전환 (JSON은 1회 이관 후 동결)
      - v1(3단) 파일은 기동 시 자동 마이그레이션 (`DataStore.migrate`, 테스트 2건)
- [x] T-03 왼쪽 트리 UI 2단 (Workspace → Project 문서, 즐겨찾기·최근사용·Vault 푸터)
      - SMART 행은 Workspace 행과 텍스트 시작점 공유
      - 사이드바 드래그 조절(로컬 상태, 떨림 방지) + 숨기기/보이기(`⌥⌘S`)
- [x] T-04 오른쪽 블록 UI (Text/Markdown/Code/Shell/WebLink/WebArchive/Image/File/Credential, 접기·펼치기·복사·순서변경)
      - 블록 편집 시트(제목·본문·타입별 필드, 헤더/제목/푸터 고정 + 중간 스크롤) + 태그 추가/제거 + `copyPayload(includeSecrets:)` Vault 연동
      - 블록 추가는 생성 우선 플로우(입력 시트 → 저장 시 생성, 취소 시 미생성)
- [x] T-05 메뉴바 상주(`MenuBarExtra`) + 글로벌 단축키(Carbon `RegisterEventHotKey`, `⌘⇧Space`) + Command Palette
- [x] T-06 검색 시스템 (전체 텍스트 + `type:` / `project:` 필터, 따옴표 지원)
- [x] T-07 DESIGN 토큰 확정 (`docs/DESIGN.md` §2 ↔ `CapsuleStash/Design/Theme.swift`)
- [x] T-08 `build_and_run.sh` + DebugPanel(`⌘⇧D`) + `error_message_ko.json` 10개 코드
- [x] 설정(`⌘,`, 네이티브 Settings 씬): 로그인 시 실행 / 단축키 상태·재등록 / 클립보드 자동 삭제 간격(안 함·10초·30초·1분) / 백그라운드 Vault 잠금 / 생체 인증 해제 / 저장소 경로·Finder / 버전·번들
- [x] T-19 앱 아이콘·메뉴바 아이콘 적용 (`KnowledgeVault-macOS26-Icons.zip` README 기준, `Assets.xcassets/AppIcon.appiconset` Light/Dark + `MenuBar.imageset` 템플릿, `MenuBarExtra(image: "MenuBar")`)
- [x] T-20 블록 추가 메뉴 정렬 (`BlockTypeLabel` 아이콘 22pt 고정폭, popover+타이틀바 메뉴 공통, 빈 상태 문구 정리)
- [x] T-21 Credential 시트 API Key 안내 (KEY는 패스워드란, 홈페이지·아이디 선택 입력, purposeHint 갱신)
- [x] T-22 Credential Secret 2칸 (`secondSecret`, Naver Client ID+Secret 대응, 카드 조건부 표시, 검색·기본복사 제외, 구버전 호환 디코딩, 테스트 2건)
- [x] 사이드바 너비 조정 (기본 200, 최소 140, 현재 240 적용. 테스트의 실설정 오염 수정 포함)
- [x] T-23 Project 워크스페이스 간 드래그 이동 (행 onDrag + 섹션 onDrop·하이라이트, `moveProject`, 같은 곳·없는 id는 무시, 테스트 2건)
- [x] T-24 툴바·본문 폴리시 (검색 가짜 필드→버튼 단층화, `+` Menu→Button+공유 팝오버·30×28 대칭, 타입 목록 심볼 제거, 사이드바 푸터 문구 제거, 본문 860 고정폭 해제)

### 검증 결과 (2026-10-02 누적)
- 유닛 67개 통과 (모델 / 검색 / CRUD / 태그·편집 / 토큰 고정 / 첨부 / 웹카드 / 사이드바 너비·토글 / 마이그레이션 / 저장소 격리 / 비밀값 격리 / Keychain / SwiftData / 드래그 이동)
- `[HARD]` 비밀값 격리: 디스크(JSON·SQLite)에 시크릿 0건 — 스냅샷에서 비움 + Keychain 별도 보관 (테스트 `testPersistableSnapshotStripsCredentials` 등)
- 성능: Cold Start 565ms (예산 ≤1.5s), RSS 124MB (예산 ≤300MB)
- 빌드·배포·실행: `./build_and_run.sh debug macos`

## 2차

- [x] T-11 SwiftData (하이브리드) 영구 저장소 + 마이그레이션 (DataStore 인터페이스 유지, `SwiftDataBackend` 경계 변환, library.json 1회 이관 후 동결, 블록 ID 승계·시크릿 제외, 순서 보존)
- [x] T-09 Web Archive/PDF 저장 + 오프라인 보기 (헤드리스 WKWebView `createWebArchiveData`+`createPDF`, 카드 저장·다시 저장·보기, 실파일 뱃지, 삭제 시 정리, `E-MAC-WEB-0002`)
- [x] T-12 이미지·파일 블록 실제 바이너리 보관 (`Application Support/CapsuleStash/images`, `files`)
      - 파일 선택기 + 카드 드래그앤드롭 + 썸네일 + 고아 파일 정리 + 삭제 시 동반 정리(`removeBlockFiles`, 블록·Project·Workspace) + 대용량 리사이즈(긴 변 2048, 알파 유지)
- [ ] T-13 블록 편집 UI (본문 인라인 편집, 코드 편집기)
- [ ] T-14 드래그 앤 드롭으로 블록/이미지 추가
- [x] T-18 다크모드 대응 (외관 고정 해제, `ThemeToken.all` 단일 테이블 적응형 토큰 24종, 설정 모양 선택, 하드코딩 색상 제거, 버튼 대비 수정, 토큰 테스트 확장)

## 3차

- [x] T-10 Credential Keychain 암호화 저장 + Touch ID 해제 + 클립보드 자동삭제 (시크릿만 Keychain 블록 ID 단위 보관, JSON엔 홈페이지·아이디만, 삭제 시 정리, DebugPanel Keychain 건수)
- [ ] T-15 Credential `⌘1`/`⌘2` 필드 단위 복사 단축키
- [ ] T-16 全角/부분 검색 옵션, 태그 기반 스마트 필터 확장
- [ ] T-17 앱 종료 후 자동잠금 옵션

## 보류 / 결정 필요
- [ ] 앱 전환 시 Dock 아이콘 유지 여부 (MVP는 유지, `LSUIElement` 전환은 메뉴바 전용 모드 도입 시)