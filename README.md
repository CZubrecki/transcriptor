# transcriptor

A macOS command line tool that transcribes a video's audio entirely on device and organizes the transcript into structured markdown notes.

The organized notes are the point.
Their intended consumer is an AI coding agent that reads them to learn material it otherwise has no access to, primarily WWDC sessions and Apple developer videos.

Everything runs locally.
The only network activity is Apple's own one-time download of speech locale assets.

## Requirements

macOS 26 or later, with Apple Intelligence enabled.
Swift 6.3.
Without Apple Intelligence the tool still transcribes, writes the transcript, explains that notes were skipped, and exits non-zero.

## Usage

```bash
make release

.build/release/transcriptor videos/session.mp4   # one file
.build/release/transcriptor                      # every unprocessed video in videos/
```

| Flag | Effect |
|---|---|
| `--force` | Reprocess videos that already have output. Batch mode only; a named file is always processed |
| `--transcribe-only` | Write the transcript and stop, skipping the notes |
| `--locale en_US` | Transcription locale. Defaults to the current locale, falling back to `en_US` |

Output lands in `transcriptions/<video-name>/`:

- `full-transcription.md` - verbatim, timestamped, with frontmatter
- `organized.md` - title, overview, sections of key points, guidance, and caveats

Progress and warnings go to stderr; stdout carries only result paths, so it pipes cleanly.

## Development

Run `make` on its own to list the targets.

| Target | Runs |
|---|---|
| `make build` | `swift build` |
| `make release` | `swift build -c release` |
| `make test` | `swift test` |
| `make run ARGS="..."` | `swift run transcriptor ...` |
| `make clean` | `swift package clean` |

## How it works

The on-device model has a hard 4,096 token context window covering prompt and response together, and throws rather than truncating.
Every design decision follows from that.

```
video -> AVAssetReader -> AVAudioConverter -> SpeechAnalyzer -> segments
      -> ~1,200 token chunks
      -> one model call per chunk, sequential  (map)
      -> Swift merge, dedupe, orphan recovery
      -> one size-bounded model call over topics only  (reduce)
      -> markdown
```

Audio is pulled one buffer at a time rather than produced eagerly, so memory stays flat regardless of video length.

The reduce pass sees only chunk topic titles and a capped term list, never the notes themselves, and is skipped entirely above 50 passages.
Completeness never depends on it: the merger consumes each chunk index at most once and appends any chunk the model failed to reference, so the outline affects organization only and can never cause loss or duplication.

If more than half the passages fail to organize, `organized.md` is deliberately not written, so the video stays eligible for a retry instead of being marked done.

## Measured limitations

These were measured on real hardware, not estimated.

**Speech recognition destroys compound API identifiers before the model ever sees them.**

| Spoken | Transcribed |
|---|---|
| `SpeechAnalyzer` | speech analyzer |
| `AVAudioConverter` | AVAudio converter |
| `ViewBuilder` | view builder |
| `SwiftUI` | `SwiftUI` |

Well-known product names survive; multi-word identifiers do not.
The model is asked to restore them and largely fails, and it will occasionally invent a plausible-looking identifier that does not exist.
A strengthened prompt was tested and rejected: it recovered slightly more identifiers but began fabricating content in the summary and caveat fields, which are far more valuable.

**Treat the terms list as topic hints, not a symbol index.**
The heading says so in the output.
Validating candidates against real framework headers would remove this limit and is the obvious next step.

The summaries, key points, guidance, and caveats are accurate and do not fabricate, which is where the value is.

## Design documents

- Spec: `docs/superpowers/specs/2026-08-19-transcriptor-design.md`
- Implementation plan: `docs/superpowers/plans/2026-08-19-transcriptor.md`
