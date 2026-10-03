# TODO — Capsule Stash (macos)
> PLAN: docs/plans/PLAN_v0.1_macos.md | 프로필: custom | 최종 갱신 2026-10-04

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
- [x] T-08 `build_and_run.sh` + DebugPanel(`⌘⇧D`) + `error_message_ko.json` 11개 코드
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
- [x] T-13 블록 편집 UI (카드 인라인 편집 + 코드 에디터: 줄번호 룰러, Tab→공백, ⌘Enter 저장·esc 취소, 연필/더블클릭 진입, 구조형은 시트 유지)
- [x] T-14 드래그 앤 드롭으로 블록 추가 (상세 화면 드롭: 파일→이미지·파일 블록, 텍스트→텍스트, URL→웹 링크, 카드 선점 플래그로 중복 방지, 하이라이트)
- [x] T-18 다크모드 대응 (외관 고정 해제, `ThemeToken.all` 단일 테이블 적응형 토큰 24종, 설정 모양 선택, 하드코딩 색상 제거, 버튼 대비 수정, 토큰 테스트 확장)

## 3차

- [x] T-10 Credential Keychain 암호화 저장 + Touch ID 해제 + 클립보드 자동삭제 (시크릿만 Keychain 블록 ID 단위 보관, JSON엔 홈페이지·아이디만, 삭제 시 정리, DebugPanel Keychain 건수)
- [x] T-15 Credential `⌘1`/`⌘2` 필드 단위 복사 단축키 (팔레트 하이라이트 행: `⌘1` 아이디 항상, `⌘2` Secret 1은 Vault 해제 시만, `credentialCopyText` 게이트 + 테스트)
- [x] T-16 전각·태그 검색 확장 (전각 영숫자 정규화, `tag:` 필터·따옴표·# 지원, 사용법 힌트 갱신, 테스트 4건)
- [x] T-17 앱 종료 후 자동잠금 옵션 (종료 시 Vault 잠금 + 클립보드 비밀값 삭제, 설정 토글 기본 켜짐, 테스트 1건)
- [x] T-25 한·영 다국어 (설정 언어 선택, 기본 시스템·미지원 시 영어, `Localizable.xcstrings` + `LText` 변수 래퍼, 상대날짜 로케일, 테스트 3건. purposeHint·로그·동적 토스트는 한국어 유지)
- [x] T-26 마크다운 렌더링 (카드 표시용 미니 파서: 제목·인용·불릿·펜스 코드, 원문 유지, 테스트 1건)
- [x] T-27 모두 접기·펼치기 + 블록 드래그 순서 변경 (`setAllBlocksCollapsed`, `moveBlockTo`+카드 DnD, 테스트 2건)
- [x] T-28 웹 단일 타입 + 실화면 썸네일 (`webLink`→`webArchive` 통합·별칭·마이그레이션, 저장 시점 스크린샷, 테스트 2건)
- [x] T-29 삭제 확인 (블록 삭제 alert, Workspace·Project는 기존 유지, 태그는 즉시 복구 가능이라 제외)
- [x] T-30 제목 자동완성 + PDF 보기·내보내기 (`suggestedTitle`, 아카이브/PDF 개별 보기, `NSSavePanel` 내보내기, 테스트 1건)
- [x] T-31 접힘 UX (접힌 카드 연필→펼쳐서 편집, 제목 탭 펼치기, 하단 접기 버튼)
- [x] T-32 이미지·파일 보기·복사 (썸네일 더블클릭 QuickLook, 파일 타일 더블클릭 열기, …메뉴 이미지 복사)
- [x] T-33 메뉴바 열기 정리 (메인 창만 열기, 퀵 서치 자동 팝업 제거. 최근 항목도 동일)
- [x] T-34 카드 드래그 범위 축소 (타이틀 영역만, 헤더 버튼 클릭 삼킴 해소) + 편집 시트 드롭 첨부
- [x] T-35 같은 문서 안 Project 순서 변경 (행 드래그, `moveProjectTo`, 하이라이트, 테스트 1건)
- [x] T-36 글로벌 단축키 변경 (설정에서 직접 기록, 기본 `⌘.`, 메뉴·툴바 표시 연동, 테스트 2건)
- [x] T-37 카드 더보기 팝오버·폴더 열기 (Menu 대신 Button+팝오버, 폴더 버튼은 Finder 표시, 경로 복사는 메뉴로, 팝오버·시트 로케일 명시)
- [x] T-38 본문 우측 플로팅 블록 바로가기 (타입색 점 레일, 클릭 스크롤 이동, 접힘은 펼치고 이동)
- [x] T-39 헤더 드래그 배지 축소 (타이틀 onDrag가 버튼 클릭 방해 가능)
- [x] T-40 마크다운 인라인 서식 (굵게·기울임·코드, `·`/`•` 불릿 인식)
- [x] T-41 타이틀 칸 전체 클릭 토글로 접기/펼치기 (버튼 제외)
- [x] T-42 썸네일 히트영역 행 고정 (fill 오버플로가 헤더 버튼 덮던 문제)
- [x] T-43 팔레트 검색 블록 이동 (펼치고 해당 위치로 스크롤)
- [x] T-44 바로가기 패널 고정폭·자동닫기·구분색·아이콘 정렬 (너비 210, 벗어나면 닫힘, tagBackground)
- [x] T-45 타입 배지 고정폭 정렬 (너비 92 + minimumScaleFactor)
- [x] T-46 코드 문자열 영어 대응 (번들 언어 동기화 + `L10n` 코드 조회 + 토스트·알림·메뉴·개수 포맷 키, 키 271개. 목적어 힌트·로그 제외던 T-25 방침에서 동적 토스트까지 포함으로 확대)
      - 순서 변경 전용 ⇅ 핸들 (배지 드래그 유지, 타이틀 클릭 방해 분리)
      - 마크다운 전체 드래그 복사 (본문 최상위 `.textSelection`)
- [x] T-47 GitHub Releases 기반 업데이트 확인 (자동 설치 없음, 릴리스 페이지 이동)
      - `ReleaseChecker` (노트 디코딩·404 구분·User-Agent 번들 버전·순수 버전 비교/주기 함수) + `AppState` 상태·주기(기본 매주)·확인시각 영속화
      - 설정 정보에 상태·자동 확인·확인 버튼, 메인 창 시트(노트는 MarkdownBody), 메뉴바 하단 버전/업데이트 표시
      - `.github/workflows/release.yml` (v*.*.* 태그 → 버전 일치 검증 → 테스트 → Release 빌드 → ad-hoc 서명·ZIP → 릴리스 발행)
      - 테스트 8건 (비교·주기·디코딩·기본값). 첫 릴리스 발행 전이라 API 404 → "게시된 릴리스가 없습니다" 정상

## 보류 / 결정 필요 (해결됨)

- [x] Dock 아이콘 표시 여부 → 설정(⌘,) 일반에 토글 추가, 기본 숨김(아니오, `LSUIElement` YES). 켜면 즉시 `.regular` 전환

## 1.0 (계획, PLAN: docs/plans/PLAN_v1.0_macos.md)

- [x] M1 안전망 → v0.2.0: T-50 일괄 내보내기(JSON/MD 왕복), T-51 자동 백업(1일 1회·7세대·복원)
      - T-50: `LibraryTransfer` (버전 봉투·스냅샷·ID 재발급·Markdown·파일명) + 사이드바(Workspace/Project별 JSON/MD)·설정(전체·가져오기), 테스트 8건. `persistableSnapshot` 비격리화, UTType.markdown→plainText(배포 타깃)
      - T-51: `BackupStore` (기동 1일 1회·7세대·토글·복원=가져오기 재사용) + 설정 자동 백업·지금 백업·복원·마지막 시각, 테스트 6건. 키 303개
- [ ] M2 모으기 → v0.3.0: T-48 Share 확장(수신함·App Group 전제), T-53 URL scheme + Shortcuts
- [ ] M3 어디서든 → v0.4.0: T-52 CloudKit 동기화 (시크릿 제외 [HARD] 유지)
- [ ] M4 꺼내기 확장 → v0.5.0: T-54 Raycast 확장 + Alfred 워크플로, T-55 스마트 그룹(검색 문법 재사용), T-56 중첩 태그
- [ ] M5 브라우저 → v1.0: T-49 Safari Web Extension (App Group 파일 교환)

## 1.0 이후 (연기)

- [ ] OCR, 휴지통·버전 기록, 모바일(iOS), 협업·공유 금고