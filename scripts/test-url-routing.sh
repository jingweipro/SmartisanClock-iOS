#!/bin/zsh
set -eu

ROOT_VIEW="${0:A:h:h}/SmartisanClockiOS/RootView.swift"

for route in world alarm stopwatch timer; do
  /usr/bin/grep -Fq "case \"$route\"" "$ROOT_VIEW"
done

if /usr/bin/grep -Fq 'url.host == "ringing"' "$ROOT_VIEW"; then
  print -u2 "External ringing URL route must remain disabled"
  exit 1
fi
