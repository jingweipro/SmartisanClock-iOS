# Live Activity Design QA

final result: passed

## Evidence

- Source visual truth: `/tmp/smartisan-live-qa/source-timer.png`
- Lock-screen implementation: `/tmp/smartisan-live-qa/lockscreen-interval-final.png`
- Compact Dynamic Island implementation: `/tmp/smartisan-live-qa/compact-direct-bundle.png`
- Combined comparison: `/tmp/smartisan-live-qa/design-comparison-final.png`
- Viewport: iPhone 16 Pro simulator, 402 x 874 points
- Source pixels: 1206 x 2622, 3x density
- Implementation pixels: 1206 x 2622, 3x density
- Comparison pixels: 1206 x 950; both focused regions normalized to 603 x 950 before joining
- State: active countdown, light Smartisan surface on the lock screen and black system surface in Dynamic Island

## Full-view comparison

The timer screen and lock-screen activity now share the same hierarchy: white embossed mechanical dial, graphite labels, light red countdown digits, and physical circular controls. The Live Activity keeps the smaller system-surface scale without reverting to the previous flat pill-button language.

## Focused-region comparison

The combined comparison verifies the mechanical-dial material, red center pin, restrained red accent, circular button rims, and soft elevation against the in-app timer. The compact Dynamic Island crop confirms that the real bundled clock face is present instead of a code-drawn placeholder or progress ring.

## Required fidelity surfaces

- Fonts and typography: system sans-serif with light monospaced countdown digits; title and status weights match the restrained in-app hierarchy. No wrapping or clipping was observed.
- Spacing and layout rhythm: 12-point lock-screen spacing and 8-point control spacing keep the dial, text, and controls visually balanced. The card fits the system width without overlap.
- Colors and tokens: the app's off-white paper, graphite, secondary gray, and Smartisan red are reused. Dynamic Island uses a brighter red only to retain contrast on black.
- Image quality and assets: the extension loads the project's real `small_blank_clock`, `small_minute_hand`, and `small_minute_hand_shadow` PNGs directly from its bundle. The earlier missing-image fallback and system progress-label overlay were removed.
- Copy and content: `计时器`, `正在倒计时`, pause/resume, and stop retain the app's terminology. Countdown text remains the native continuously updating numeric timer on device.

## Comparison history

1. P1: the first implementation used flat gray/red pill buttons and a progress-ring clock, which visually belonged to a different product. Fixed by rebuilding the card around the app's mechanical dial and round embossed controls.
2. P1: loose extension resources were packaged but not resolved by the default SwiftUI image lookup, leaving only the red center pin. Fixed with direct `Bundle.main` PNG loading; the compact Dynamic Island capture confirms the complete clock face.
3. P2: the circular progress component injected duplicate white countdown text over the clock face. Fixed by removing the system progress ring entirely and retaining the mechanical hand and separate red countdown.
4. P2: experimental localized timer formatting produced `56分钟` / `56 minutes`. Reverted to the native numeric `Text(timerInterval:countsDown:)` presentation used by the working device build.

## Residual test gap

- P3: the simulator automation API cannot hold a touch long enough to capture the expanded Dynamic Island state; compact Dynamic Island, lock screen, build, accessibility labels, and action wiring were verified. The expanded layout uses the same verified dial, typography, and circular controls and compiles in the extension target.

## Findings

No actionable P0, P1, or P2 visual findings remain. The simulator may show `--` for seconds in a locked snapshot while throttling widget refresh; the existing physical-device evidence shows the same native timer API rendering live `mm:ss`, so this is not treated as product visual drift.

## Implementation checklist

- [x] Replace pill controls with embossed circular controls.
- [x] Reuse the project's real timer-clock assets.
- [x] Remove duplicate progress-ring countdown text.
- [x] Verify compact Dynamic Island and lock-screen layouts at 3x density.
- [x] Preserve pause/resume/stop intents and accessibility labels.
