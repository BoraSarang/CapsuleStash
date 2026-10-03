# Raycast 확장 (T-54)

`capsule://` scheme 경유 검색·저장. PLAN대로 별도 TS 저장소로 분리해 Store 발행하는 게
최종형이고, 여기 스캐폴드는 그 전 단계 (타입체크 통과 상태).

## 명령

- Search Capsules (필수 인자 query) → `capsule://search?query=` 열기
- Save Clipboard to Inbox → 클립보드를 수신함 JSON으로 저장 (앱 규격과 동일)

## 검증

```sh
cd extensions/raycast
npm install
./node_modules/.bin/tsc --noEmit   # 통과 확인됨
```

Store 발행 전 `ray develop` 실동작 + 아이콘 교체(`assets/capsule.png`는 단색 임시본).

## 수신함 규격

`{"version":1,"text":"...","url"?,"source":"Raycast"}` →
`~/Library/Application Support/CapsuleStash/Inbox/inbox-<uuid>.json`.
앱의 `InboxPayload.read`가 그대로 읽는다 (Swift 테스트 `testRaycastPayloadShape`).
