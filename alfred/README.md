# Alfred 워크플로 (T-54)

`cs <검색어>` → Enter 복사 · ⌘Enter 앱에서 열기. 계정 블록은 홈페이지·아이디만 복사된다.

## 설치

1. 이 폴더(`alfred/`)를 압축하거나 그대로 둔다. 더블클릭 가져기가 안 되면 아래 수동 연결.
2. Alfred 설정 → Workflows → `+` → Open workflow folder → 이 폴더 내용을 넣는다.
3. Script Filter와 Run Script가 동작 폴더를 이 폴더로 보게 한다 (기본값이면 그대로).

## 수동 연결 (2분, 가져오기 실패 시)

1. Inputs → Keyword: 키워드 `cs`, Space 체크.
2. Inputs → Script Filter: Language `/usr/bin/python3`, Script `./search.py "{query}"`, with space 체크.
3. Actions → Run Script: `/bin/zsh` + `./copy-or-open.sh`.
4. Keyword → Script Filter → Run Script 순서로 연결.

## 검증 (Alfred 없이도 됨)

```sh
cd alfred
./search.py "docker" | python3 -m json.tool | head -n 20
do=copy content="x" url="" ./copy-or-open.sh; pbpaste | head -c 100
```

## 보안

- `search.py`는 SQLite 읽기 전용(`mode=ro`). 시크릿 컬럼 자체를 SELECT하지 않는다.
