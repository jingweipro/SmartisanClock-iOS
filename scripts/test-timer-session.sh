#!/bin/sh
set -eu

test_binary="${TMPDIR:-/tmp}/smartisan-timer-session-tests"
xcrun swiftc \
  SmartisanClockiOS/TimerSession.swift \
  Tests/TimerSessionTests/main.swift \
  -o "$test_binary"
"$test_binary"
