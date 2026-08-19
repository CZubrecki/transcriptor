# Transcriptor Design

Date: 2026-08-19
Status: Approved for implementation planning

## Purpose

A macOS command line tool that turns a video file into two markdown documents: a verbatim timestamped transcript, and a hierarchically organized set of notes.
The organized notes are the real product.
Their consumer is an AI coding agent that reads them to learn material it would otherwise have no access to, primarily WWDC sessions and Apple tutorial videos.

Everything runs on device.
There are no network calls except Apple's own one-time download of speech locale assets.

## Constraints

The single constraint that shapes the whole design is the on-device model's context window.

`SystemLanguageModel.default` has a hard limit of 4,096 tokens covering prompt and response combined.
Exceeding it throws `LanguageModelSession.GenerationError.exceededContextWindowSize` rather than truncating silently.
This was verified on the target machine, which reported: "Content contains 30026 tokens, which exceeds the maximum allowed context size of 4096."

A 40 minute WWDC session transcribes to roughly 6,000 words, or upwards of 8,000 tokens.
No design that passes a full transcript to the model in one call can work.
Every stage below that touches the model is bounded in input size by construction.

Target platform is macOS 26 or later, Swift 6.
Verified against macOS 26.5, Swift 6.3.3, Xcode 26.6.

## Verified API surface

These were type-checked against the MacOSX26.5 SDK before this document was written.

- `SpeechTranscriber(locale:transcriptionOptions:reportingOptions:attributeOptions:)`
- `SpeechAnalyzer(modules:)` and `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)`
- `analyzer.start(inputSequence:)` accepting an `AsyncStream<AnalyzerInput>`
- `transcriber.results`, yielding results with `.text` as `AttributedString` and `.isFinal`
- Per-run timestamps via `text.runs.first?.audioTimeRange`, enabled by the `.audioTimeRange` attribute option
- `AssetInventory.assetInstallationRequest(supporting:)` returning an optional request with `downloadAndInstall()`
- `@Generable` structs with `@Guide(description:)` and `.count(range)` constraints, via `session.respond(to:generating:)`

## Pipeline

```
videos/session.mp4
  -> AVAssetReader on the first audio track            Stage 1
  -> AVAudioConverter into the analyzer's format
  -> SpeechAnalyzer + SpeechTranscriber                Stage 2  -> [TranscriptSegment]
  -> TranscriptChunker, ~1,200 token chunks            Stage 3
  -> N sessions, one per chunk, @Generable output      Stage 4  (map)
  -> Swift side merge and dedupe
  -> 1 session over topics and terms only              Stage 5  (reduce)
  -> MarkdownRenderer                                  Stage 6
transcriptions/session/full-transcription.md
transcriptions/session/organized.md
```

## Package layout

A thin executable over a testable library.
The interesting logic must not be trapped behind a `main` function.

```
Package.swift                            swift-argument-parser, platform macOS 26
Sources/transcriptor/                    CLI entry, argument parsing, progress output
Sources/TranscriptorKit/
  Workspace.swift                        videos/ and transcriptions/ path resolution
  Pipeline.swift                         stage orchestration, depends only on protocols
  Audio/AudioExtractor.swift             MP4 to AVAudioPCMBuffer stream
  Transcription/Transcribing.swift       protocol plus SpeechTranscriberEngine
  Transcription/TranscriptSegment.swift  text plus CMTimeRange
  Chunking/TranscriptChunker.swift       pure function
  Organize/ChunkNotes.swift              @Generable schema
  Organize/OrganizedDocument.swift       merged model handed to the renderer
  Organize/Organizing.swift              protocol plus FoundationModelsOrganizer
  Organize/Profile.swift                 instructions seam
  Render/MarkdownRenderer.swift          pure function
Tests/TranscriptorKitTests/
videos/
transcriptions/
```

`Transcribing` and `Organizing` exist as protocols so that `Pipeline` can be tested against fakes without invoking a model.
This is the main reason the library is split from the executable.

## Stage 1: audio extraction

`AVAssetReader` with an `AVAssetReaderTrackOutput` over the first audio track, decompressing to LPCM.
Each sample buffer is converted into an `AVAudioPCMBuffer`.
An `AVAudioConverter` reshapes those buffers into the format reported by `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)`.

No external tools are involved.
There is no file size ceiling because audio is streamed rather than loaded.

If the file has no audio track, that file fails with a clear message and batch processing continues with the next file.

## Stage 2: transcription

Converted buffers are yielded into an `AsyncStream<AnalyzerInput>` passed to `analyzer.start(inputSequence:)`.

`reportingOptions` deliberately omits `.volatileResults`.
Volatile results exist to let live UI show partial text that updates as recognition firms up.
For file transcription they would be discarded, so requesting them is pure waste.
Only results with `isFinal` true are consumed.

`attributeOptions` includes `.audioTimeRange`, which is what makes timestamps available.

Each final result becomes a `TranscriptSegment` holding its text and its `CMTimeRange`.

If the requested locale's assets are not installed, `AssetInventory.assetInstallationRequest(supporting:)` returns a request that is downloaded once, with progress written to stderr.
The target machine already has nine English locales installed, so this is normally a no-op.

## Stage 3: chunking

A pure function over `[TranscriptSegment]`, with no model involvement.

Segments accumulate into a chunk until estimated token count reaches roughly 1,200.
Chunks always break at a segment boundary and never mid sentence.

Token estimation is characters divided by four.
This is deliberately approximate.
The correctness guarantee comes from the retry described in Stage 4, not from estimating accurately.

The 1,200 target against a 4,096 ceiling leaves room for the instructions, the schema definition, and the generated response, all of which draw on the same budget.

## Stage 4: map

One fresh `LanguageModelSession` per chunk.

Sessions are fresh rather than reused so that no chunk can pollute the next, and so that no session accumulates context toward the ceiling across a long video.

Chunks are processed sequentially, not concurrently.
There is a single on-device model, so parallel requests would contend for the same hardware rather than complete sooner.
This is a decision made without measurement and is the first thing to revisit if throughput on long videos disappoints.

The schema:

```swift
@Generable struct ChunkNotes {
  @Guide(description: "Short topic title for this passage")
  var topic: String
  @Guide(description: "One or two sentence summary")
  var summary: String
  @Guide(description: "Key points made", .count(1...6))
  var keyPoints: [String]
  @Guide(description: "Named things: frameworks, types, methods, concepts, tools. Verbatim.", .count(0...8))
  var terms: [String]
  @Guide(description: "Actionable recommendations or practices", .count(0...5))
  var guidance: [String]
  @Guide(description: "Constraints, requirements, version limits, pitfalls", .count(0...5))
  var caveats: [String]
}
```

Field names are one level more abstract than the primary use case requires.
`terms` rather than `apis`, `guidance` rather than `codePatterns`, `caveats` rather than `requirements`.
A WWDC session fills these with `GlassEffectContainer`, "group glass views in a container", and "iOS 26 or later".
A lecture fills the same fields with concepts, practices, and the conditions under which a claim holds.
One schema serves both without either feeling like a form designed for the other.

Every array except `keyPoints` permits zero elements.
Combined with the renderer omitting empty sections, this is what allows non-technical content to produce a clean document rather than a technical template with blanks.

The instructions carry one nudge toward the primary use case: when content is technical, capture type and method names verbatim as spoken.
This prevents `SpeechAnalyzer` being softened into "the speech analysis API" and costs nothing on non-technical content.

**Context overflow retry.**
Catch `exceededContextWindowSize`, split the offending chunk in half, and retry each half.
Recurse to a floor of a single segment.
If a single segment still overflows, skip it with a warning.

**Guardrail violations.**
Catch, skip that chunk, warn, and continue.
One refused chunk must never cost a 40 minute transcript.

## Stage 5: reduce

The reduce input is only the chunk topic titles and term lists.
It never includes summaries, key points, guidance, or caveats.

For a 40 minute video this is roughly 30 short strings plus a term list, a few hundred tokens.
The input therefore cannot overflow regardless of video length.
That bound is structural, which is what makes this pass safe where a naive "summarize all the notes" reduce would fail on long input.

The pass produces a document title, an overview of two or three sentences, and a grouping of chunk indices into sections that merges topics the speaker returned to later.

Grouping is applied in Swift against the real notes.
The model decides only which chunks belong together.
It never rewrites note content.
Term deduplication is case-insensitive Swift, not a model call.

If the reduce fails for any reason, the pipeline falls back to linear transcript order and still emits a complete document.
The reduce is an enhancement and never a dependency.

## Stage 6: rendering

Both renderers are pure functions over their models and unit-test without a model.

`full-transcription.md` contains frontmatter with source path, duration, locale, and date, followed by segments prefixed `[MM:SS]`.

`organized.md` contains the title, the overview, then per section the summary, key points, guidance, and caveats, followed by a document-level term index.

Empty sections are omitted at every level.
A section with no caveats has no Caveats heading.
A document with no caveats anywhere has no such headings at all.

## CLI

```
transcriptor                  every unprocessed video in videos/
transcriptor videos/x.mp4     a single file
  --force                     reprocess even if output exists
  --transcribe-only           run stages 1 and 2, write the transcript, stop
  --locale en_US              defaults to current locale, falling back to en_US
```

Unprocessed means no `organized.md` exists for that video.
Under `--transcribe-only` it instead means no `full-transcription.md` exists, since `organized.md` is never produced in that mode and would otherwise cause every file to be re-transcribed on every run.

Progress and warnings are written to stderr so that stdout remains clean for piping.

There is deliberately no `--organize-only`.
Re-running the LLM stage against an existing transcript would require parsing markdown back into segments, which nothing else in the system needs.
It is worth adding later if prompt iteration becomes frequent.

## Error handling

| Condition | Behavior |
|---|---|
| Apple Intelligence unavailable | Check `SystemLanguageModel.availability` before Stage 4. Write `full-transcription.md`, explain why organizing was skipped, exit non-zero |
| No audio track in file | Fail that file with a clear message, continue the batch |
| Locale assets missing | Download once via `AssetInventory`, progress to stderr |
| Context window exceeded | Split the chunk and retry, down to a single segment |
| Guardrail violation | Skip that chunk, warn, continue |
| One file fails during batch | Log and continue. Exit code reflects whether anything failed |

The principle behind these: transcription is the expensive stage and organizing is cheap.
No failure downstream of transcription may cost the user their transcript.

## Testing

Chunker, merge and dedupe, and renderer are pure functions with real unit tests.
Boundary cases that must be covered:

- A single segment larger than the chunk target
- Notes where every optional array is empty, verifying no empty headings render
- A reduce failure, verifying fallback to linear order still produces a complete document
- Case-differing terms deduplicating to one entry

`Pipeline` is tested against fake `Transcribing` and `Organizing` implementations, exercising orchestration and error paths without a model.

For end-to-end coverage, `AVSpeechSynthesizer` writes known speech to an audio file at test time.
This gives a deterministic fixture with no checked-in binary and no network dependency.

## Out of scope

- Speaker diarization
- Translation or non-English organization output
- Video frame analysis, including slide or code extraction from the picture
- Any cloud model
- Incremental reprocessing of partially completed videos

## Decisions deferred

- Concurrency in the map stage, pending measurement on real videos
- An `--organize-only` flag, pending evidence that prompt iteration is frequent
- Additional profiles beyond the default, pending real non-Apple input. The seam exists in `Profile.swift`; only one profile is built
