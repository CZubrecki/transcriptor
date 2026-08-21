# cli-output-streams

## Task
Send every status message to stderr so stdout carries only result paths, as the README already promises.

## Tests
- [ ] An empty videos directory reports "Nothing to do." on stderr, leaves stdout empty, and exits 0 - `emptyWorkspaceReportsNothingToDoOnStandardError`
- [ ] A missing videos directory reports the error on stderr, leaves stdout empty, and exits 1 - `missingVideosDirectoryFailsOnStandardError`

## Slices
- [ ] 1. Route status output to the correct stream - turns green: both tests above

## PRs
- tests:
- slice 1:

## Follow-ups
- `@unchecked Sendable` in `AudioExtractor.swift:40` (production) and `PipelineTests.swift:60`. SwiftLint flags both. The production one carries a hand-written thread-safety argument and needs its own task under the full workflow.
- Result paths on stdout are not covered, because asserting on them means running the full pipeline over a real video, which is slow and needs Apple Intelligence. The `print` at line 78 already writes to the correct stream; that edit is stream-preserving and exists only to satisfy the lint rule.

## Notes
- Both tests drive the built CLI as a subprocess. `Workspace` is rooted at the process's current directory, so pointing the subprocess at a temp directory makes each test hermetic.
- `--transcribe-only` skips the Apple Intelligence availability check, so both tests run on CI rather than needing gating behind `Capability`.
- A clean `swift build --build-tests` produces `.build/debug/transcriptor`, verified, so the test target can locate the binary beside the xctest bundle.
- Current behaviour confirmed by hand: with an empty `videos/`, "Nothing to do." lands on stdout and stderr is empty.
