# Alfred 워크플로 (T-54)

`cs <검색어>` → Enter 복사 · ⌘Enter 해당 문서로 이동. 계정 블록은 홈페이지·아이디만 복사된다.

## 설치

```sh
cd alfred
zip -j Capsule-Stash.alfredworkflow info.plist search.py copy-or-open.sh
open Capsule-Stash.alfredworkflow   # Alfred가 가져오기 (재설치는 덮어쓰기 Update)
```

`*.alfredworkflow`는 빌드 산출물이라 커밋하지 않는다.

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
