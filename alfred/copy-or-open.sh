#!/bin/zsh
# Capsule Stash Alfred 후속 액션 (T-54).
# $1 = Alfred가 넘긴 arg (Enter=복사 내용, ⌘Enter=열 URL), $do로 분기한다.
# 예전처럼 $content 변수에 의존하지 않는다 — mod 변수가 아이템 변수를
# 덮어쓰면 URL이 비어 `open ""`이 워크플로 폴더를 열기 때문이다 (2026-10-04 실측).
if [ "$do" = "open" ]; then
  open "$1"
else
  printf '%s' "$1" | pbcopy
fi
