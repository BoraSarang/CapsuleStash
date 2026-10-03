# Safari Web Extension (T-49)

현재 탭을 `capsule://save`로 넘겨 수신함에 저장. App Group 없이 동작한다
(URL scheme 경유 — T-53 실동작 검증됨).

## 구조

- `manifest.json` (MV3) · `popup.html` · `popup.js` · `icons/` (임시 단색, 발행 전 교체)
- 선택 텍스트 저장은 2단계 (content script 추가 예정)

## Safari에 올리기 (수동, 3분)

1. Safari → 설정 → 고급 → "메뉴 막대에서 개발자용 메뉴 보기" 켜기.
2. 개발자용 → "서명되지 않은 확장 허용".
3. Xcode로 열기: 새로운 Safari Extension App 타깃을 만들고 이 폴더 파일을 넣거나,
   `safari-web-extension-converter`로 변환 후 실행.
4. 팝업에서 "현재 탭 저장" → 앱 Inbox 문서에 저장됨.

## 검증 (Safari 없이도 됨)

```sh
cd extensions/safari
python3 -c "import json; json.load(open('manifest.json'))"
node -e "console.log(require('./popup.js').capsuleSaveURL('t','https://e.com'))"
# 나온 URL은 앱 테스트 testParsesSafariExtensionURL과 같은 규격
```

## 한계

- 실동작(팝업 클릭→저장)은 Safari에서 수동 확인 필요.
- Xcode Safari Extension 타깃 배선은 유료 팀 서명과 함께 (현재 adhoc).
