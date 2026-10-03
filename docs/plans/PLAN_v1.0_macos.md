# PLAN_v1.0_macos.md
> 생성일: 2026-10-04 | 플랫폼: macos | 작성자: OpenCode
> 전제: v0.1_macos 완료 (T-01~T-47, 테스트 113개) + 저장소 공개 + 릴리즈 파이프라인
> 배경: 릴리즈 전 경쟁 조사 (SnippetsLab·Quiver·Anybox·Raycast·Dash·Bear·Obsidian·1Password)

## 1. 목표 (1줄)
"넣는 속도(수집)·잃지 않는 확신(안전·동기화)·꺼내는 확장(연동·정리)"을 채워 Capsule Stash를 매일 쓰는 1.0으로 만든다.

## 2. 범위
- 플랫폼: macos (기존 스택 유지: Swift+SwiftUI+SwiftData+Keychain)
- 1.0 포함 (E1~E5, T-48~T-56):
  - E1 수집 경로: T-48 Share 확장, T-49 브라우저 확장
  - E2 데이터 안전: T-50 일괄 내보내기, T-51 자동 백업
  - E3 동기화: T-52 CloudKit 동기화
  - E4 외부 연동: T-53 URL scheme + Shortcuts, T-54 Raycast 확장 + Alfred 워크플로
  - E5 스마트 정리: T-55 스마트 그룹, T-56 중첩 태그
- 1.0 제외 (1.0 이후로 연기): OCR, 휴지통·버전 기록, 모바일(iOS), 협업·공유 금고

## 3. 마일스톤 (순서 이유 포함)
- M1 안전망 → v0.2.0: T-50, T-51. 데이터를 더 모으기 전에 "날아가도 복구"를 먼저 깐다.
- M2 모으기 → v0.3.0: T-48, T-53. Share 확장+URL scheme으로 넣는 경로를 연다.
- M3 어디서든 → v0.4.0: T-52. 저장소가 안정된 뒤 동기화 (백업 없는 동기화는 사고 경로).
- M4 꺼내기 확장 → v0.5.0: T-54, T-55, T-56. 검색 문법 재사용이라 동기화 뒤에 붙이기 좋다.
- M5 브라우저 → v1.0: T-49. 가장 무거운 타깃이라 마지막. 끝나면 1.0 태그·릴리즈.

## 4. 태스크 정의
- T-48 Share 확장: 선택 텍스트·URL을 실행 중인 앱에서 바로 저장. 수신함(Project 지정, 기본 Inbox 문서) + Vault 잠금 시 계정형 제외. 별도 appex 타깃.
- T-49 브라우저 확장: Safari Web Extension으로 현재 탭 저장 (Anybox Quick Save 대응). `nativeMessaging` 없이 App Group 파일로 교환.
- T-50 일괄 내보내기: Workspace/Project→JSON(스키마 버전 명시)·Markdown. NSSavePanel, 가져오기 복원까지 왕복 테스트.
- T-51 자동 백업: 기동 시 1일 1회 스냅샷, 7세대 보관, 설정 토글. 복원 흐름 포함.
- T-52 CloudKit 동기화: SwiftData+CloudKit. 시크릿은 Keychain이라 동기화 대상 아님을 테스트로 고정 ([HARD] 유지).
- T-53 URL scheme + Shortcuts: `capsule://search?query=`·`capsule://save?text=`·`capsule://open?project=`, App Intents 2종 (저장·검색복사).
- T-54 Raycast 확장 + Alfred 워크플로: Raycast 확장은 별도 TS 저장소(Store 발행), Alfred 워크플로는 repo 내 동봉.
- T-55 스마트 그룹: 기존 검색 문법(`type:`·`project:`·`tag:`)을 저장 조건으로 재사용. 사이드바 SMART 섹션에 상주.
- T-56 중첩 태그: `부모/자식` 표기, `tag:` 접두 매칭, 기존 태그 자동 승계 (마이그레이션 불필요).

## 5. 아키텍처 전제 (먼저 결정)
- App Group 컨테이너: Share·브라우저 확장이 본체 저장소에 닿으려면 그룹 컨테이너 이전이 전제 (T-48 착수 전).
- 하이브리드 저장소+CloudKit 궁합: SwiftData 네이티브 동기화 vs 직접 동기 중 T-52 설계 시 결정, JSON 폴백 유지.
- 시크릿 동기화 정책: 기본 제외. 동기화한다면 E2E 별도 설계 (1.0 범위 밖이면 제외로 못박기).

## 6. 공통 DoD (전체 태스크)
- 한·영 문자열 전수 등록 (T-46 정책: 코드 문자열 `L10n`, UI 리터럴 카탈로그 키).
- 유닛 테스트: 순수 함수(비교·문법·주기)+경계(마이그레이션·삭제 정리) 패턴 유지.
- [HARD] 유지: 디스크·동기화·로그에 시크릿 0건, Shell 자동실행 금지.
- `./build_and_run.sh test macos unit` + debug 배포·실행 확인.

## 7. 실행 기록
- 2026-10-04 M1 완료 → v0.2.0: T-50(테스트 8건)·T-51(테스트 6건), 127개 통과, debug 배포·실행 중. 키 303개.
