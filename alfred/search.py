#!/usr/bin/env python3
"""Capsule Stash Alfred Script Filter (T-54).

SwiftData SQLite를 읽기 전용으로 뒤져 Alfred JSON을 뱉는다.
[HARD] 시크릿은 SQLite에 없다 (password/secondSecret은 Keychain 전용).
계정 블록의 content 변수에는 홈페이지·아이디만 담는다.

사용법: python3 search.py "docker"
검증:   python3 -c "import json,sys; json.load(sys.stdin)" < <(python3 search.py "x")
"""
import json
import os
import sqlite3
import sys
import urllib.parse

DB = os.path.expanduser("~/Library/Application Support/CapsuleStash/database.sqlite")
LIMIT = 9
CONTENT_TRUNCATE = 20000


def capsule_url(query: str) -> str:
    return "capsule://search?query=" + urllib.parse.quote(query)


def open_project_url(project: str) -> str:
    """⌘Enter용. 앱이 해당 문서를 선택한다 (T-53 `open` 액션)."""
    return "capsule://open?project=" + urllib.parse.quote(project)


def like_pattern(query: str) -> str:
    return "%" + "%".join(query.split()) + "%"


def main() -> None:
    query = sys.argv[1].strip() if len(sys.argv) > 1 else ""
    if not query:
        print(json.dumps({"items": [{
            "title": "Capsule Stash 검색",
            "subtitle": "cs 키워드 뒤에 검색어를 입력하세요",
            "valid": False,
        }]}))
        return
    if not os.path.exists(DB):
        print(json.dumps({"items": [{
            "title": "저장소를 찾지 못했습니다",
            "subtitle": "Capsule Stash를 한 번 실행하세요",
            "valid": False,
        }]}))
        return

    pattern = like_pattern(query)
    items = []
    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    try:
        # 문서 히트 (이름·메모 매칭)
        rows = con.execute(
            """SELECT p.ZNAME, w.ZNAME, p.ZNOTE
               FROM ZSDPROJECT p JOIN ZSDWORKSPACE w ON p.ZWORKSPACE = w.Z_PK
               WHERE p.ZNAME LIKE ? ESCAPE '\\' OR p.ZNOTE LIKE ? ESCAPE '\\'
               LIMIT ?""",
            (pattern, pattern, LIMIT),
        ).fetchall()
        for name, ws, note in rows:
            url = open_project_url(name or "")
            items.append({
                "uid": f"project:{name}",
                "title": name or "(제목 없음)",
                "subtitle": f"{ws} · Enter 앱에서 문서 열기",
                "arg": url,
                "variables": {"do": "open", "url": url},
                "mods": {"cmd": {"subtitle": "앱에서 문서 열기",
                                 "arg": url,
                                 "variables": {"do": "open"}}},
            })
        # 블록 히트 (제목·본문·언어·URL·태그 매칭)
        rows = con.execute(
            """SELECT b.ZTITLE, b.ZCONTENT, b.ZTYPERAW, b.ZLANGUAGE, b.ZURL,
                      b.ZSITENAME, b.ZCREDHOMEPAGE, b.ZCREDUSERNAME,
                      p.ZNAME, w.ZNAME
               FROM ZSDBLOCK b
               JOIN ZSDPROJECT p ON b.ZPROJECT = p.Z_PK
               JOIN ZSDWORKSPACE w ON p.ZWORKSPACE = w.Z_PK
               WHERE b.ZTITLE LIKE ? ESCAPE '\\' OR b.ZCONTENT LIKE ? ESCAPE '\\'
                  OR b.ZLANGUAGE LIKE ? ESCAPE '\\' OR b.ZURL LIKE ? ESCAPE '\\'
                  OR b.ZSITENAME LIKE ? ESCAPE '\\'
               LIMIT ?""",
            (pattern, pattern, pattern, pattern, pattern, LIMIT),
        ).fetchall()
        for (title, content, typeraw, lang, url, site,
             homepage, username, project, ws) in rows:
            is_cred = typeraw == "credential"
            if is_cred:
                # [HARD] 비밀값 제외 — 홈페이지·아이디만 클립보드에 담는다
                clip = "\n".join(x for x in
                                 [homepage or "", username or ""] if x)
                detail = f"{project} · 계정 (홈페이지·아이디만 복사)"
            else:
                clip = content or title or ""
                detail = f"{project} · {typeraw or 'text'}"
                if site:
                    detail += f" · {site}"
            clip = clip[:CONTENT_TRUNCATE]
            # ⌘Enter는 문서로 점프 (팔레트만 여는 search가 아님).
            # mod가 arg를 URL로 덮어쓰므로 변수 병합 여부와 무관하게 동작한다.
            open_url = open_project_url(project or "")
            items.append({
                "uid": f"block:{project}:{title}",
                "title": title or "(제목 없음)",
                "subtitle": f"{ws} / {detail} — Enter 복사, ⌘Enter 문서로 이동",
                "arg": clip,
                "variables": {"do": "copy", "url": open_url},
                "text": {"copy": clip},
                "mods": {"cmd": {"arg": open_url,
                                 "subtitle": "앱에서 문서 열기",
                                 "variables": {"do": "open"}}},
            })
    finally:
        con.close()

    if not items:
        search = capsule_url(query)
        items = [{"title": "결과 없음",
                  "subtitle": "Enter를 눌러 앱에서 전체 검색하기",
                  "arg": search,
                  "variables": {"do": "open", "url": search}}]
    print(json.dumps({"items": items[:LIMIT]}, ensure_ascii=False))
    # 시크릿 가드: 출력에 password 컬럼이 섞일 수 없지만, 혹시 모를 본문 노출 확인용
    # (계정 블록 본문은 Keychain 값이라 SQLite에 없음 — 구조상 보장)


main()
