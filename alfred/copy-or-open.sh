#!/bin/zsh
# Capsule Stash Alfred 후속 액션 (T-54).
# Script Filter가 넘긴 변수로 복사·열기를 가른다.
# - do=open → capsule:// URL로 앱 열기
# - do=copy → content를 클립보드에 복사
if [ "$do" = "open" ]; then
  open "$url"
else
  printf '%s' "$content" | pbcopy
fi
