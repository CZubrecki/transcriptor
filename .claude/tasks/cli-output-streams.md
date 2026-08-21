# cli-output-streams

## Task
Send every status message to stderr so stdout carries only result paths, as the README already promises.

## Tests
- [x] An empty videos directory reports "Nothing to do." on stderr, leaves stdout empty, and exits 0 - `empty workspace reports nothing to do on standard error` (passing)
- [x] A missing videos directory reports the error on stderr, leaves stdout empty, and exits 1 - `missing videos directory fails on standard error` (passing)

## Slices
- [x] 1. Route status output to the correct stream - turns green: both tests above
- [x] 2. Resolve the transcription locale lazily, so the two CLI tests pass on a runner with no speech locales

## PRs
- tests: https://github.com/CZubrecki/transcriptor/pull/7 (merged)
- slice 1: https://github.com/CZubrecki/transcriptor/pull/8 (merged)
- slice 2:

## Follow-ups
- `@unchecked Sendable` in `AudioExtractor.swift:40` (production) and `PipelineTests.swift:60`. SwiftLint flags both. The production one carries a hand-written thread-safety argument and needs its own task under the full workflow.
- Result paths on stdout are not covered, because asserting on them means running the full pipeline over a real video, which is slow and needs Apple Intelligence. The `print` at line 78 already writes to the correct stream; that edit is stream-preserving and exists only to satisfy the lint rule.

- The formatter's `swiftTestingTestCaseNames` rule rewrites `@Test` function names into backtick-quoted prose, so test names differ from the ones planned in Phase 0.

- Phase 0 missed that `resolveLocale()` runs before the videos checks. `--transcribe-only` skips the Apple Intelligence check but not locale resolution, and a hosted runner has no speech locales, so both CLI tests failed on CI even though they passed locally and under `CI=true`. A local machine has locales, so the simulation could not catch it. Reproduce that condition with `--locale zz_ZZ`.

## Notes
- Both tests drive the built CLI as a subprocess. `Workspace` is rooted at the process's current directory, so pointing the subprocess at a temp directory makes each test hermetic.
- `--transcribe-only` skips the Apple Intelligence availability check, so both tests run on CI rather than needing gating behind `Capability`.
- A clean `swift build --build-tests` produces `.build/debug/transcriptor`, verified, so the test target can locate the binary beside the xctest bundle.
- Current behaviour confirmed by hand: with an empty `videos/`, "Nothing to do." lands on stdout and stderr is empty.
