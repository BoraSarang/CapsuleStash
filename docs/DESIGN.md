# DESIGN.md — Capsule Stash (custom)
> AGENTS.local.md 프로필: custom | 플랫폼: macos | v0.1 확정

## 1. 방향
- 블록 기반 혼합 문서 + 메뉴바 Command Palette 중심 자체 디자인 시스템
- 시스템 UI (메뉴·알림·DebugPanel·권한 요청)는 native 준수
- 기준 목업: `docs/mockup-v0.1.html` (토큰 값은 목업 CSS 변수에서 1:1 이관)

## 2. 토큰 (확정) — 구현: `CapsuleStash/Design/Theme.swift`

> appearance 고정: custom 토큰은 라이트(paper) 전용이라 `Theme.applyFixedAppearance()` 가
> 앱 기동 시 `NSApplication.shared.appearance = .aqua` 로 고정한다. 시스템 다크모드에서
> TextField/TextEditor/Menu/팝오버가 뒤집히면 고정색과 충돌해 글자가 안 보이는 깨짐이 발생하기 때문이다.
> 모든 입력 컨트롤은 시스템 색에 의존하지 않고 명시적 토큰 색을 지정한다.
> 다크모드 대응은 2차(T-18).

### 2.1 색
| 토큰 | 값 | 용도 |
|---|---|---|
| `ink` | `#16150F` | 본문·버튼 primary 배경 |
| `sidebar` | `#1B1A15` | 사이드바 배경 |
| `sidebarElevated` | `#242219` | 사이드바 푸터 카드 |
| `sidebarHover` | `#2A2820` | 사이드바 호버 (예약) |
| `sidebarLine` | `#38352A` | 사이드바 구분선 |
| `sidebarText` | `#D9D3C4` | 사이드바 1단계 라벨 |
| `sidebarMuted` | `#8A857A` | 사이드바 보조 라벨 |
| `paper` | `#FAF7F0` | 콘텐츠 배경 |
| `titlebar` | `#E9E2D3` | 툴바 배경 |
| `card` | `#FFFFFF` | 블록 카드 배경 |
| `line` | `#E8E0D1` | 카드/구분선 |
| `codeBackground` | `#14130F` | 코드 블록 배경 |
| `codeForeground` | `#F2EAD9` | 코드 블록 전경 |
| `tagBackground` | `#EFE8D6` | 태그 칩 |
| `muted` | `#8A857A` | 본문 보조 텍스트 |
| `accent` | `#FF5C00` | 캡슐 오렌지 (액센트) |
| `accentSoft` | `#FFE9D6` | 액센트 연배경 |
| `sage` | `#5F6F52` | IMAGE/FILE 배지 |
| `gold` | `#C99A2E` | 즐겨찾기 별 |

### 2.2 블록 타입 배지 색 (`Theme.badgeColor(for:)`)
| 타입 | 색 |
|---|---|
| `text` / `markdown` | `ink` |
| `code` / `shell` | `accent` |
| `webLink` / `webArchive` | `#2D5BD7` |
| `image` / `file` | `sage` |
| `credential` | `#7A2EE0` |

### 2.3 폰트
- 시리프 표시 제목: `Font.system(design: .serif)` (macOS New York) — `Theme.serif(_:)`
- 본문: San Francisco 기본 (시스템)
- 코드/배지: `Font.system(design: .monospaced)` — `Theme.monoBody` / `Theme.monoCaption`

### 2.4 간격·라운드
| 토큰 | 값 |
|---|---|
| `blockSpacing` | 14pt |
| `blockPadding` | 16pt |
| `contentPadding` | 30pt |
| `cardRadius` | 14pt |
| `controlRadius` | 8pt |

## 3. 화면
- **메인**: 좌 트리 2단 (Workspace → Project 문서) + 우 블록 리스트
- **팔레트**: `⌘⇧Space`(Carbon 글로벌 핫키, 앱 비활성 상태에서도 동작) → 검색 → `↵` 열기 / `↑↓` 이동 / `esc` 닫기 / 행의 `복사` 버튼
- **설정**(`⌘,`): 일반(로그인 시 실행) / Command Palette(단축키 상태·재등록) / 보안(클립보드 자동 삭제 간격·백그라운드 Vault 잠금) / 저장소(경로·Finder) / 정보
- **DebugPanel**: `⌘⇧D` — ERROR/PERF/CACHE 카운트 + 로그 목록
- **승인 흐름**: 신규 화면은 제안 → 사용자 결정 → 구현

## 4. 목업 대비 의도적 차이
- 팔레트 `⌘C` 복사 → **제외**. 검색창이 포커스 상태라 `⌘C`가 텍스트 복사와 충돌한다. 같은 기능은 결과 행의 `복사` 버튼이 담당한다.
- Credential `⌘1`/`⌘2` 단축키 → **T-10에서 구현**(Vault 잠금과 Touch ID 정책 확정 후). MVP는 행 버튼만 제공.
- 팔레트 Credential 행의 `복사`는 아이디·홈페이지만 복사하며 비밀값은 복사하지 않는다([HARD]).

## 5. 검색 문법
- 자유 텍스트: `docker`
- 타입 필터: `type:code` (BlockType rawValue)
- 프로젝트 필터: `project:macOS`, 공백 포함 시 `project:"서버 관리"`

## 7. 아이콘 (T-19, 2026-10-02)
- 원본: `/Users/lee/Documents/AGENTS/apps-files/KnowledgeVault-macOS26-Icons.zip` (`mac_icons/README.md` 기준)
- `CapsuleStash/Resources/Assets.xcassets/AppIcon.appiconset` — Light/Dark 16~1024, `ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon` + `CFBundleIconName=AppIcon` (빌드 시 `AppIcon.icns` 자동 생성 확인)
- `CapsuleStash/Resources/Assets.xcassets/MenuBar.imageset` — 16/18/19/20/22pt @1x/@2x, `template-rendering-intent` 유지 (라이트/다크 자동 틴트)
- `CapsuleStashApp.swift`: `MenuBarExtra(systemImage:)` → `MenuBarExtra(image: "MenuBar")` (기존 `capsule` SF Symbol 분기 제거)
- 의미: 상단 다이아몬드=지식 워크스페이스, 중간 리본=스니펫, 하단 키홀=금고, 세로선=블록 분리, 가로 갭=프로젝트 분리

## 6. 예외 기록
- 저장 날짜 표기 `yyyy-MM-dd` 고정 (`ko_KR`, 시스템 로케일 무관)
- 웹 링크 = 북마크(주소+메모, 브라우저로 열기). 웹 아카이브 = 본문 오프라인 보관(실파일은 T-09, MVP는 주소·설명·메모만). 카드에 URL 행 상시 표시(클릭 시 열기), 사이트명 없으면 URL 호스트 표시, 없으면 안내 문구. 타입 선택·입력 시 `purposeHint` 한 줄 설명 표시
- 팔레트 `⌘C` 제거 — 검색창 텍스트 복사와 충돌 (§4)
- Web 아카이브/이미지는 MVP에서 메타데이터 + 파일명만 보관, 실제 바이너리 저장은 T-09
- 블록 편집 시트 — 목업에 편집 UI가 없으나 우측 콘텐츠 수정 수단으로 MVP에 추가 (헤더 `편집` 버튼 + `···` 메뉴 → `BlockEditorSheet`)
- 사이드바 인덴트 — 목업 DOM(`.proj` 박스 + 좌측 가이드선)이 기준. 단 Collection은 사용자 요청으로 프로젝트명보다 1단계 추가 들여쓰기 (목업은 동일선)
- 타이틀바 `+ 새로 만들기` — 목업 `.newbtn`(잉크 필) 스타일로 변경, DebugPanel 버튼과 함께 trailing 그룹 배치 (secondaryAction은 leading에 붙어 검색창과 겹침)
- 타이틀바 검색창 — 커스텀 배경+테두리 가짜 필드는 시스템 툴바 렌더링과 겹쳐 두 겹으로 보이므로 진짜 네이티브 `TextField(.roundedBorder)` 사용. 클릭 시 포커스를 팔레트로 넘김
- 이미지 `보기` → `경로 복사`로 변경 (원본 뷰어는 T-12)
- `Menu`+borderlessButton 라벨은 appearance에 따라 전경색이 무시되어 paper 위에서 안 보일 수 있음 → `블록 추가`는 `Button`+`popover` 으로 구현
- 블록 추가는 생성 우선: 타입 선택 → 입력 시트 → 저장 시 생성, 취소 시 미생성 (빈 블록 즉시 생성 폐지, `insertBlock`)
- 이미지/파일 첨부: 편집 시트의 `이미지 추가…`/`파일 추가…` 파일 선택기 + 카드에 Finder 드래그앤드롭. 실파일은 `Application Support/CapsuleStash/{images,files}` 보관, 카드에 썸네일 표시
- 3단→2단 축소 (사용자 확정): Collection이 곧 하나의 프로젝트(문서) 개념이므로 중간 단 삭제, 블록을 담는 문서를 Project라 부름. 旧 묶음명은 태그·색으로 승계, 비어 있던 묶음은 빈 문서로 보존, 문서 id는 Collection id 승계. v1 파일은 기동 시 자동 마이그레이션 후 v2로 저장 (`DataStore.migrate`, `LegacyV1*`)
- SMART 행은 Workspace 행과 텍스트 시작점 공유 (행패딩 8 + 아이콘 11 + 간격 6)
- 사이드바 드래그 떨림 방지: 드래그 중 너비는 열 로컬 상태로만 갱신, 종료 시 1회 저장 (AppState 직접 갱신 시 앱 전체 리렌더 + 이미지 재로드 발생)
- 이름 입력은 기본 `NSAlert` 대신 `NameInputSheet`(가로 100% 입력창, Enter=확인, esc=취소). Workspace/Project/Collection 추가·이름 변경에 적용, 삭제 확인은 SwiftUI `alert`로 통일 (Collection 삭제는 기존에 확인 없이 삭제되어 함께 추가)
- 사이드바는 `HStack` + 커스텀 `ResizeHandle`로 드래그 조절(220~340) + 숨기기/보이기 + 더블클릭 토글. `HSplitView`는 좌측에 시스템 여백을 만들어 보도블럭처럼 보이므로 사용 금지. 타이틀바 `sidebar.left` 버튼과 `⌥⌘S` 단축키, 너비·상태는 UserDefaults 유지
- 액션 버튼은 아이콘 전용(`CapsuleIconButton`, 26×24 고정) + hover 툴팁으로 통일 — 아이콘+텍스트 버튼의 두 줄 깨짐 방지. 텍스트 유지: 다이얼로그 푸터(취소/저장/추가/확인)·메뉴 항목·칩/네비게이션 행 (목업 `.iconbtn`과 다름)