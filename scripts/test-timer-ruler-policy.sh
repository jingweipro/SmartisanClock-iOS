#!/bin/sh
set -eu

test_binary="${TMPDIR:-/tmp}/smartisan-timer-ruler-policy-tests"
xcrun swiftc \
  SmartisanClockiOS/TimerRulerPolicy.swift \
  Tests/TimerRulerPolicyTests/main.swift \
  -o "$test_binary"
"$test_binary"
