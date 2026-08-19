# Transcriptor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS command line tool that transcribes a video's audio on device and organizes the transcript into structured markdown notes for an AI coding agent to learn from.

**Architecture:** A thin `transcriptor` executable over a testable `TranscriptorKit` library.
Audio is streamed out of the container with `AVAssetReader`, converted to the analyzer's format, and transcribed by `SpeechAnalyzer`.
The transcript is chunked to fit a hard 4,096 token context window, mapped chunk by chunk into a `@Generable` struct, merged in Swift, and reduced by one size-bounded model call into a document outline.

**Tech Stack:** Swift 6.3, swift-argument-parser 1.5+, Swift Testing, AVFoundation, Speech (`SpeechAnalyzer`/`SpeechTranscriber`), FoundationModels.

**Spec:** `docs/superpowers/specs/2026-08-19-transcriptor-design.md`

## Global Constraints

- Platform floor is macOS 26.0. Declare as `platforms: [.macOS("26.0")]`. The enum shorthand `.v26` does not exist.
- swift-tools-version is 6.3.
- The on-device model context window is a hard **4,096 tokens** covering prompt and response combined. Exceeding it throws `LanguageModelSession.GenerationError.exceededContextWindowSize`.
- Chunk target is **1,200 estimated tokens**, estimated as `characters / 4`.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest.
- The transcriber's required input format on this hardware is **16 kHz mono**. Always convert; never assume the source matches.
- Map stage chunks are processed **sequentially**, never concurrently.
- Progress and warnings go to **stderr**. stdout stays clean.
- No comments in code unless they explain something genuinely non-obvious.

## Verified Facts

Every API in this plan was type-checked or executed against macOS 26.5 / Swift 6.3.3 / MacOSX26.5.sdk before the plan was written.

- `SystemLanguageModel.default.availability` returned `available`.
- A 30,026 token prompt threw `exceededContextWindowSize` with "the maximum allowed context size of 4096".
- `SpeechAnalyzer.bestAvailableAudioFormat` returned **16000 Hz, 1 channel**.
- A synthesized fixture transcribed end to end into 2 segments with correct `CMTimeRange` timestamps.
- `@Generable` with `@Guide(description:)` and `.count(0...5)` produced correct structured output on a WWDC-style snippet.

**Known accuracy limit:** the ASR layer transcribed "SpeechAnalyzer" as "the speech analyzer class".
Identifier casing is lost before the model sees the text.
The map stage instructions therefore ask the model to reconstruct identifier casing, and this is understood to be imperfect.

## File Structure

| File | Responsibility |
|---|---|
| `Package.swift` | Manifest, platform floor, dependencies |
| `Sources/TranscriptorKit/Workspace.swift` | Resolve `videos/` and `transcriptions/<name>/` paths |
| `Sources/TranscriptorKit/Transcription/TranscriptSegment.swift` | One final ASR result: text plus time range |
| `Sources/TranscriptorKit/Chunking/TranscriptChunker.swift` | Pure segment grouping by token estimate |
| `Sources/TranscriptorKit/Audio/AudioExtractor.swift` | Container to 16 kHz mono PCM buffer stream |
| `Sources/TranscriptorKit/Transcription/Transcribing.swift` | Protocol plus `SpeechTranscriberEngine` |
| `Sources/TranscriptorKit/Organize/ChunkNotes.swift` | `@Generable` per-chunk schema |
| `Sources/TranscriptorKit/Organize/OrganizedDocument.swift` | Merged model handed to the renderer |
| `Sources/TranscriptorKit/Organize/Organizing.swift` | Protocol plus `FoundationModelsOrganizer` |
| `Sources/TranscriptorKit/Organize/Profile.swift` | Instructions seam |
| `Sources/TranscriptorKit/Render/MarkdownRenderer.swift` | Pure model to markdown |
| `Sources/TranscriptorKit/Pipeline.swift` | Stage orchestration over protocols |
| `Sources/transcriptor/Transcriptor.swift` | CLI entry, flags, batch loop |

---

### Task 1: Package scaffold and Workspace

**Files:**
- Create: `Package.swift`, `Sources/TranscriptorKit/Workspace.swift`, `Sources/transcriptor/Transcriptor.swift`
- Test: `Tests/TranscriptorKitTests/WorkspaceTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `Workspace(root: URL)`, `.videosDirectory: URL`, `.outputDirectory(for videoURL: URL) -> URL`, `.isProcessed(videoURL: URL, transcribeOnly: Bool) -> Bool`, `.pendingVideos() throws -> [URL]`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import TranscriptorKit

@Test func outputDirectoryUsesVideoBasename() {
  let ws = Workspace(root: URL(fileURLWithPath: "/tmp/proj"))
  let out = ws.outputDirectory(for: URL(fileURLWithPath: "/tmp/proj/videos/WWDC Session 10023.mp4"))
  #expect(out.path == "/tmp/proj/transcriptions/WWDC Session 10023")
}

@Test func isProcessedChecksOrganizedByDefault() throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  let ws = Workspace(root: root)
  let video = ws.videosDirectory.appending(path: "a.mp4")
  let out = ws.outputDirectory(for: video)
  try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
  #expect(ws.isProcessed(videoURL: video, transcribeOnly: false) == false)
  try Data().write(to: out.appending(path: "organized.md"))
  #expect(ws.isProcessed(videoURL: video, transcribeOnly: false) == true)
  try? FileManager.default.removeItem(at: root)
}

@Test func isProcessedChecksTranscriptWhenTranscribeOnly() throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  let ws = Workspace(root: root)
  let video = ws.videosDirectory.appending(path: "a.mp4")
  let out = ws.outputDirectory(for: video)
  try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
  try Data().write(to: out.appending(path: "organized.md"))
  #expect(ws.isProcessed(videoURL: video, transcribeOnly: true) == false)
  try Data().write(to: out.appending(path: "full-transcription.md"))
  #expect(ws.isProcessed(videoURL: video, transcribeOnly: true) == true)
  try? FileManager.default.removeItem(at: root)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test`
Expected: FAIL, `cannot find 'Workspace' in scope`.

- [ ] **Step 3: Write Package.swift**

```swift
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "transcriptor",
  platforms: [.macOS("26.0")],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
  ],
  targets: [
    .target(name: "TranscriptorKit"),
    .executableTarget(
      name: "transcriptor",
      dependencies: [
        "TranscriptorKit",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]),
    .testTarget(name: "TranscriptorKitTests", dependencies: ["TranscriptorKit"]),
  ]
)
```

- [ ] **Step 4: Implement Workspace**

```swift
import Foundation

public struct Workspace: Sendable {
  public let root: URL

  public init(root: URL) { self.root = root }

  public var videosDirectory: URL { root.appending(path: "videos") }
  public var transcriptionsDirectory: URL { root.appending(path: "transcriptions") }

  public func outputDirectory(for videoURL: URL) -> URL {
    transcriptionsDirectory.appending(path: videoURL.deletingPathExtension().lastPathComponent)
  }

  public func isProcessed(videoURL: URL, transcribeOnly: Bool) -> Bool {
    let marker = transcribeOnly ? "full-transcription.md" : "organized.md"
    return FileManager.default.fileExists(atPath: outputDirectory(for: videoURL).appending(path: marker).path)
  }

  public func pendingVideos(transcribeOnly: Bool, force: Bool) throws -> [URL] {
    let extensions: Set<String> = ["mp4", "mov", "m4v"]
    let all = try FileManager.default.contentsOfDirectory(at: videosDirectory, includingPropertiesForKeys: nil)
      .filter { extensions.contains($0.pathExtension.lowercased()) }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard !force else { return all }
    return all.filter { !isProcessed(videoURL: $0, transcribeOnly: transcribeOnly) }
  }
}
```

Create a placeholder `Sources/transcriptor/Transcriptor.swift` so the executable target builds:

```swift
@main struct Transcriptor {
  static func main() { print("transcriptor") }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test`
Expected: PASS, 3 tests.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: package scaffold and workspace path resolution"
```

---

### Task 2: TranscriptSegment and TranscriptChunker

**Files:**
- Create: `Sources/TranscriptorKit/Transcription/TranscriptSegment.swift`, `Sources/TranscriptorKit/Chunking/TranscriptChunker.swift`
- Test: `Tests/TranscriptorKitTests/TranscriptChunkerTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `TranscriptSegment(text: String, start: TimeInterval, end: TimeInterval)`, `TranscriptChunker.chunk(_ segments: [TranscriptSegment], targetTokens: Int = 1200) -> [[TranscriptSegment]]`, `TranscriptChunker.estimatedTokens(_ text: String) -> Int`

`TranscriptSegment` uses `TimeInterval` rather than `CMTime` so the chunker and renderer stay free of AVFoundation and test without it.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import TranscriptorKit

private func seg(_ text: String, _ start: Double = 0) -> TranscriptSegment {
  TranscriptSegment(text: text, start: start, end: start + 1)
}

@Test func estimatesTokensAsQuarterOfCharacters() {
  #expect(TranscriptChunker.estimatedTokens(String(repeating: "a", count: 400)) == 100)
}

@Test func groupsSegmentsUpToTargetTokens() {
  let segments = (0..<10).map { seg(String(repeating: "x", count: 400), Double($0)) }
  let chunks = TranscriptChunker.chunk(segments, targetTokens: 300)
  #expect(chunks.count == 4)
  #expect(chunks[0].count == 3)
  #expect(chunks.flatMap(\.self).count == 10)
}

@Test func neverSplitsASingleSegment() {
  let huge = seg(String(repeating: "y", count: 40_000))
  let chunks = TranscriptChunker.chunk([huge], targetTokens: 300)
  #expect(chunks.count == 1)
  #expect(chunks[0].count == 1)
}

@Test func emptyInputProducesNoChunks() {
  #expect(TranscriptChunker.chunk([], targetTokens: 300).isEmpty)
}

@Test func preservesSegmentOrder() {
  let segments = (0..<6).map { seg("segment \($0) " + String(repeating: "z", count: 400), Double($0)) }
  let chunks = TranscriptChunker.chunk(segments, targetTokens: 300)
  let flattened = chunks.flatMap(\.self).map(\.start)
  #expect(flattened == segments.map(\.start))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TranscriptChunker`
Expected: FAIL, `cannot find 'TranscriptChunker' in scope`.

- [ ] **Step 3: Implement both types**

```swift
import Foundation

public struct TranscriptSegment: Sendable, Equatable {
  public let text: String
  public let start: TimeInterval
  public let end: TimeInterval

  public init(text: String, start: TimeInterval, end: TimeInterval) {
    self.text = text
    self.start = start
    self.end = end
  }
}
```

```swift
import Foundation

public enum TranscriptChunker {
  public static func estimatedTokens(_ text: String) -> Int {
    text.count / 4
  }

  public static func chunk(
    _ segments: [TranscriptSegment],
    targetTokens: Int = 1200
  ) -> [[TranscriptSegment]] {
    var chunks: [[TranscriptSegment]] = []
    var current: [TranscriptSegment] = []
    var currentTokens = 0

    for segment in segments {
      let tokens = estimatedTokens(segment.text)
      if !current.isEmpty, currentTokens + tokens > targetTokens {
        chunks.append(current)
        current = []
        currentTokens = 0
      }
      current.append(segment)
      currentTokens += tokens
    }
    if !current.isEmpty { chunks.append(current) }
    return chunks
  }
}
```

The `!current.isEmpty` guard is what guarantees an oversized single segment stays in its own chunk rather than producing an empty one.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TranscriptChunker`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/TranscriptorKit/Transcription Sources/TranscriptorKit/Chunking Tests
git commit -m "feat: transcript segment model and token-budget chunker"
```

---

### Task 3: Full transcript renderer

**Files:**
- Create: `Sources/TranscriptorKit/Render/MarkdownRenderer.swift`
- Test: `Tests/TranscriptorKitTests/FullTranscriptRenderTests.swift`

**Interfaces:**
- Consumes: `TranscriptSegment` from Task 2
- Produces: `MarkdownRenderer.fullTranscript(segments:sourcePath:duration:locale:date:) -> String`, `MarkdownRenderer.timestamp(_ seconds: TimeInterval) -> String`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import TranscriptorKit

@Test func formatsTimestampsAsMinutesAndSeconds() {
  #expect(MarkdownRenderer.timestamp(0) == "00:00")
  #expect(MarkdownRenderer.timestamp(65) == "01:05")
  #expect(MarkdownRenderer.timestamp(3725) == "62:05")
}

@Test func rendersFrontmatterAndTimestampedSegments() {
  let segments = [
    TranscriptSegment(text: "Hello there.", start: 0, end: 2),
    TranscriptSegment(text: "Second line.", start: 65, end: 67),
  ]
  let md = MarkdownRenderer.fullTranscript(
    segments: segments,
    sourcePath: "videos/a.mp4",
    duration: 67,
    locale: "en_US",
    date: Date(timeIntervalSince1970: 0))

  #expect(md.hasPrefix("---\n"))
  #expect(md.contains("source: videos/a.mp4"))
  #expect(md.contains("duration: 01:07"))
  #expect(md.contains("locale: en_US"))
  #expect(md.contains("[00:00] Hello there."))
  #expect(md.contains("[01:05] Second line."))
}

@Test func trimsSegmentWhitespace() {
  let md = MarkdownRenderer.fullTranscript(
    segments: [TranscriptSegment(text: "  padded  ", start: 0, end: 1)],
    sourcePath: "v.mp4", duration: 1, locale: "en_US", date: Date(timeIntervalSince1970: 0))
  #expect(md.contains("[00:00] padded"))
  #expect(!md.contains("padded  "))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FullTranscriptRender`
Expected: FAIL, `cannot find 'MarkdownRenderer' in scope`.

- [ ] **Step 3: Implement the renderer**

```swift
import Foundation

public enum MarkdownRenderer {
  public static func timestamp(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded(.down))
    return String(format: "%02d:%02d", total / 60, total % 60)
  }

  public static func fullTranscript(
    segments: [TranscriptSegment],
    sourcePath: String,
    duration: TimeInterval,
    locale: String,
    date: Date
  ) -> String {
    var lines: [String] = []
    lines.append("---")
    lines.append("source: \(sourcePath)")
    lines.append("duration: \(timestamp(duration))")
    lines.append("locale: \(locale)")
    lines.append("transcribed: \(ISO8601DateFormatter().string(from: date))")
    lines.append("---")
    lines.append("")
    lines.append("# Full Transcription")
    lines.append("")
    for segment in segments {
      let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }
      lines.append("[\(timestamp(segment.start))] \(text)")
      lines.append("")
    }
    return lines.joined(separator: "\n")
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter FullTranscriptRender`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/TranscriptorKit/Render Tests
git commit -m "feat: render timestamped full transcript markdown"
```

---

### Task 4: Audio extraction

**Files:**
- Create: `Sources/TranscriptorKit/Audio/AudioExtractor.swift`
- Test: `Tests/TranscriptorKitTests/AudioExtractorTests.swift`, `Tests/TranscriptorKitTests/Support/AudioFixture.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `AudioExtractor.duration(of url: URL) async throws -> TimeInterval`, `AudioExtractor.buffers(from url: URL, to targetFormat: AVAudioFormat) throws -> AsyncThrowingStream<AVAudioPCMBuffer, Error>`, `AudioExtractorError.noAudioTrack`, and the test helper `AudioFixture.write(text:to:) async throws`

`AudioFixture` is used by this task and again by Task 5, so it lives in `Tests/TranscriptorKitTests/Support/`.

- [ ] **Step 1: Write the fixture helper**

Verified working: this produced a 634,920 byte file.

```swift
import AVFoundation

enum AudioFixture {
  static func write(text: String, to url: URL) async throws {
    let synthesizer = AVSpeechSynthesizer()
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

    nonisolated(unsafe) var file: AVAudioFile?
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      nonisolated(unsafe) var finished = false
      synthesizer.write(utterance) { buffer in
        guard let pcm = buffer as? AVAudioPCMBuffer else { return }
        if pcm.frameLength == 0 {
          if !finished { finished = true; continuation.resume() }
          return
        }
        if file == nil {
          file = try? AVAudioFile(forWriting: url, settings: pcm.format.settings)
        }
        try? file?.write(from: pcm)
      }
    }
    file = nil
  }
}
```

- [ ] **Step 2: Write the failing test**

```swift
import Testing
import AVFoundation
@testable import TranscriptorKit

@Test func extractsBuffersInTargetFormat() async throws {
  let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "\(UUID().uuidString).caf")
  try await AudioFixture.write(text: "Testing audio extraction with a reasonably long sentence.", to: url)
  defer { try? FileManager.default.removeItem(at: url) }

  let target = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
  var frames: AVAudioFrameCount = 0
  for try await buffer in try AudioExtractor.buffers(from: url, to: target) {
    #expect(buffer.format.sampleRate == 16000)
    #expect(buffer.format.channelCount == 1)
    frames += buffer.frameLength
  }
  #expect(frames > 16000)
}

@Test func reportsDuration() async throws {
  let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "\(UUID().uuidString).caf")
  try await AudioFixture.write(text: "A short clip.", to: url)
  defer { try? FileManager.default.removeItem(at: url) }
  let duration = try await AudioExtractor.duration(of: url)
  #expect(duration > 0.5)
}

@Test func throwsWhenNoAudioTrack() async throws {
  let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "\(UUID().uuidString).mp4")
  try Data("not a video".utf8).write(to: url)
  defer { try? FileManager.default.removeItem(at: url) }
  let target = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
  await #expect(throws: (any Error).self) {
    for try await _ in try AudioExtractor.buffers(from: url, to: target) {}
  }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter AudioExtractor`
Expected: FAIL, `cannot find 'AudioExtractor' in scope`.

- [ ] **Step 4: Implement AudioExtractor**

The `nonisolated(unsafe)` on `input` is deliberate.
`AVAudioPCMBuffer` is not `Sendable`, and `AVAudioConverter`'s input block is `@Sendable`, but the block runs synchronously inside `convert` before the buffer escapes.
Without this the Swift 6 build emits a concurrency warning on every conversion.

```swift
import AVFoundation
import Foundation

public enum AudioExtractorError: Error, CustomStringConvertible {
  case noAudioTrack(URL)
  case converterUnavailable

  public var description: String {
    switch self {
    case .noAudioTrack(let url): "no audio track in \(url.lastPathComponent)"
    case .converterUnavailable: "could not create an audio converter for this file"
    }
  }
}

public enum AudioExtractor {
  public static func duration(of url: URL) async throws -> TimeInterval {
    try await AVURLAsset(url: url).load(.duration).seconds
  }

  public static func buffers(
    from url: URL,
    to targetFormat: AVAudioFormat
  ) throws -> AsyncThrowingStream<AVAudioPCMBuffer, Error> {
    AsyncThrowingStream { continuation in
      Task {
        do {
          let asset = AVURLAsset(url: url)
          guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioExtractorError.noAudioTrack(url)
          }
          let reader = try AVAssetReader(asset: asset)
          let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
          ])
          reader.add(output)
          reader.startReading()

          var converter: AVAudioConverter?
          while let sample = output.copyNextSampleBuffer() {
            guard let description = CMSampleBufferGetFormatDescription(sample),
                  let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
                  let sourceFormat = AVAudioFormat(streamDescription: asbd)
            else { continue }

            let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
            guard frames > 0, let input = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frames)
            else { continue }
            input.frameLength = frames
            CMSampleBufferCopyPCMDataIntoAudioBufferList(
              sample, at: 0, frameCount: Int32(frames), into: input.mutableAudioBufferList)

            if converter == nil {
              converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
            }
            guard let converter else { throw AudioExtractorError.converterUnavailable }

            let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(frames) * ratio) + 1024
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity)
            else { continue }

            nonisolated(unsafe) let source = input
            var supplied = false
            var conversionError: NSError?
            converter.convert(to: converted, error: &conversionError) { _, status in
              if supplied {
                status.pointee = .noDataNow
                return nil
              }
              supplied = true
              status.pointee = .haveData
              return source
            }
            if let conversionError { throw conversionError }
            if converted.frameLength > 0 { continuation.yield(converted) }
          }
          if reader.status == .failed, let error = reader.error { throw error }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter AudioExtractor`
Expected: PASS, 3 tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/TranscriptorKit/Audio Tests
git commit -m "feat: stream container audio as converted PCM buffers"
```

---

### Task 5: Transcription engine

**Files:**
- Create: `Sources/TranscriptorKit/Transcription/Transcribing.swift`
- Test: `Tests/TranscriptorKitTests/SpeechTranscriberEngineTests.swift`

**Interfaces:**
- Consumes: `AudioExtractor` (Task 4), `TranscriptSegment` (Task 2), `AudioFixture` (Task 4)
- Produces: `protocol Transcribing { func transcribe(url: URL, locale: Locale) async throws -> [TranscriptSegment] }`, `SpeechTranscriberEngine`

- [ ] **Step 1: Write the failing test**

This is an integration test against the real on-device recognizer.
It asserts on lowercased substrings because ASR output casing is not stable.

```swift
import Testing
import Foundation
@testable import TranscriptorKit

@Test func transcribesSynthesizedSpeech() async throws {
  let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "\(UUID().uuidString).caf")
  try await AudioFixture.write(
    text: "The speech analyzer class requires macOS 26 or later.", to: url)
  defer { try? FileManager.default.removeItem(at: url) }

  let segments = try await SpeechTranscriberEngine().transcribe(
    url: url, locale: Locale(identifier: "en_US"))

  #expect(!segments.isEmpty)
  let joined = segments.map(\.text).joined(separator: " ").lowercased()
  #expect(joined.contains("speech analyzer"))
  #expect(segments[0].end > segments[0].start)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SpeechTranscriberEngine`
Expected: FAIL, `cannot find 'SpeechTranscriberEngine' in scope`.

- [ ] **Step 3: Implement the protocol and engine**

The teardown call is `finalizeAndFinishThroughEndOfInput()`.
Results are collected in a task started **before** `analyzer.start` so no early result is missed.

```swift
import Foundation
import Speech
import AVFoundation

public protocol Transcribing: Sendable {
  func transcribe(url: URL, locale: Locale) async throws -> [TranscriptSegment]
}

public enum TranscriptionError: Error, CustomStringConvertible {
  case noCompatibleAudioFormat
  case localeUnsupported(String)

  public var description: String {
    switch self {
    case .noCompatibleAudioFormat: "no compatible audio format for the transcriber"
    case .localeUnsupported(let id): "locale \(id) is not supported for transcription"
    }
  }
}

public struct SpeechTranscriberEngine: Transcribing {
  public init() {}

  public func transcribe(url: URL, locale: Locale) async throws -> [TranscriptSegment] {
    let supported = await SpeechTranscriber.supportedLocales
    guard supported.contains(where: { $0.identifier == locale.identifier }) else {
      throw TranscriptionError.localeUnsupported(locale.identifier)
    }

    let transcriber = SpeechTranscriber(
      locale: locale,
      transcriptionOptions: [],
      reportingOptions: [],
      attributeOptions: [.audioTimeRange])

    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
      FileHandle.standardError.write(Data("installing speech assets for \(locale.identifier)\n".utf8))
      try await request.downloadAndInstall()
    }

    let analyzer = SpeechAnalyzer(modules: [transcriber])
    guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
      throw TranscriptionError.noCompatibleAudioFormat
    }

    let collector = Task {
      var collected: [TranscriptSegment] = []
      for try await result in transcriber.results where result.isFinal {
        collected.append(TranscriptSegment(
          text: String(result.text.characters),
          start: result.range.start.seconds,
          end: result.range.end.seconds))
      }
      return collected
    }

    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    try await analyzer.start(inputSequence: stream)

    do {
      for try await buffer in try AudioExtractor.buffers(from: url, to: format) {
        continuation.yield(AnalyzerInput(buffer: buffer))
      }
    } catch {
      continuation.finish()
      collector.cancel()
      throw error
    }

    continuation.finish()
    try await analyzer.finalizeAndFinishThroughEndOfInput()
    return try await collector.value
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SpeechTranscriberEngine`
Expected: PASS. First run may be slow if speech assets download.

- [ ] **Step 5: Commit**

```bash
git add Sources/TranscriptorKit/Transcription Tests
git commit -m "feat: on-device speech transcription engine"
```

---

### Task 6: Chunk notes schema and map stage

**Files:**
- Create: `Sources/TranscriptorKit/Organize/ChunkNotes.swift`, `Sources/TranscriptorKit/Organize/Profile.swift`, `Sources/TranscriptorKit/Organize/Organizing.swift`
- Test: `Tests/TranscriptorKitTests/MapStageTests.swift`

**Interfaces:**
- Consumes: `TranscriptSegment` (Task 2), `TranscriptChunker` (Task 2)
- Produces: `ChunkNotes` (`@Generable`), `Profile(instructions:)` with `Profile.default`, `protocol Organizing`, `FoundationModelsOrganizer.notes(for chunk: [TranscriptSegment]) async throws -> ChunkNotes?`

- [ ] **Step 1: Write the failing test**

Structured generation is verified working, so this test asserts the schema shape and the split-on-overflow behavior rather than exact model wording.

```swift
import Testing
import Foundation
import FoundationModels
@testable import TranscriptorKit

@Test func extractsStructuredNotesFromATechnicalChunk() async throws {
  guard case .available = SystemLanguageModel.default.availability else { return }
  let chunk = [TranscriptSegment(
    text: "In iOS 26 SwiftUI adds the glass effect modifier. Use it on a view and group them with a glass effect container. Avoid nesting glass inside glass.",
    start: 0, end: 12)]

  let notes = try #require(await FoundationModelsOrganizer().notes(for: chunk))
  #expect(!notes.topic.isEmpty)
  #expect(!notes.keyPoints.isEmpty)
  #expect(notes.keyPoints.count <= 6)
  #expect(notes.terms.count <= 8)
}

@Test func splitsChunksThatOverflowTheContextWindow() async throws {
  guard case .available = SystemLanguageModel.default.availability else { return }
  let oversized = (0..<40).map {
    TranscriptSegment(
      text: "Sentence number \($0) describing an unrelated topic in some detail. " + String(repeating: "filler words here. ", count: 20),
      start: Double($0), end: Double($0) + 1)
  }
  let results = try await FoundationModelsOrganizer().notesSplittingOnOverflow(for: oversized)
  #expect(results.count >= 2)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MapStage`
Expected: FAIL, `cannot find 'FoundationModelsOrganizer' in scope`.

- [ ] **Step 3: Implement the schema**

```swift
import FoundationModels

@Generable
public struct ChunkNotes: Sendable {
  @Guide(description: "Short topic title for this passage")
  public var topic: String

  @Guide(description: "One or two sentence summary of this passage")
  public var summary: String

  @Guide(description: "Key points made in this passage", .count(1...6))
  public var keyPoints: [String]

  @Guide(description: "Named things: frameworks, types, methods, concepts, tools", .count(0...8))
  public var terms: [String]

  @Guide(description: "Actionable recommendations or practices stated", .count(0...5))
  public var guidance: [String]

  @Guide(description: "Constraints, version requirements, limitations, pitfalls", .count(0...5))
  public var caveats: [String]
}
```

- [ ] **Step 4: Implement the profile**

The identifier reconstruction line exists because ASR lowercases and word-splits API names before the model sees them.

```swift
public struct Profile: Sendable {
  public let instructions: String

  public init(instructions: String) { self.instructions = instructions }

  public static let `default` = Profile(instructions: """
    You extract structured study notes from a transcript passage.
    The notes will be read by an AI coding agent learning this material.

    Record only what the passage actually states. Never invent details.
    When the content is technical, reconstruct the conventional casing of \
    identifiers that speech recognition flattened: "speech analyzer" becomes \
    SpeechAnalyzer, "view builder" becomes ViewBuilder. Only do this when you \
    are confident the term is a real identifier. If unsure, write it as spoken.
    Leave a list empty when the passage offers nothing for it.
    """)
}
```

- [ ] **Step 5: Implement the organizer's map stage**

```swift
import Foundation
import FoundationModels

public protocol Organizing: Sendable {
  func notes(for chunk: [TranscriptSegment]) async throws -> ChunkNotes?
  func notesSplittingOnOverflow(for chunk: [TranscriptSegment]) async throws -> [ChunkNotes]
  func outline(topics: [String], terms: [String]) async throws -> DocumentOutline?
}

extension Organizing {
  public func notesSplittingOnOverflow(for chunk: [TranscriptSegment]) async throws -> [ChunkNotes] {
    if let single = try await notes(for: chunk) { return [single] }
    return []
  }
}

public struct FoundationModelsOrganizer: Organizing {
  private let profile: Profile

  public init(profile: Profile = .default) { self.profile = profile }

  public func notes(for chunk: [TranscriptSegment]) async throws -> ChunkNotes? {
    let text = chunk.map(\.text).joined(separator: " ")
    let session = LanguageModelSession(instructions: profile.instructions)
    do {
      return try await session.respond(
        to: "Extract notes from this passage:\n\n\(text)",
        generating: ChunkNotes.self).content
    } catch let error as LanguageModelSession.GenerationError {
      switch error {
      case .exceededContextWindowSize:
        throw OrganizeError.contextOverflow
      default:
        warn("skipping a passage: \(error)")
        return nil
      }
    }
  }

  // Overrides the protocol default to add recursive splitting on overflow.
  public func notesSplittingOnOverflow(for chunk: [TranscriptSegment]) async throws -> [ChunkNotes] {
    do {
      if let single = try await notes(for: chunk) { return [single] }
      return []
    } catch OrganizeError.contextOverflow {
      guard chunk.count > 1 else {
        warn("skipping one oversized segment that cannot be split further")
        return []
      }
      let middle = chunk.count / 2
      let left = try await notesSplittingOnOverflow(for: Array(chunk[..<middle]))
      let right = try await notesSplittingOnOverflow(for: Array(chunk[middle...]))
      return left + right
    }
  }
}

public enum OrganizeError: Error {
  case contextOverflow
}

func warn(_ message: String) {
  FileHandle.standardError.write(Data("warning: \(message)\n".utf8))
}
```

`DocumentOutline` and `outline(topics:terms:)` are defined in Task 7.
To keep this task compiling on its own, add a temporary stub in `Organizing.swift` and replace it in Task 7:

```swift
@Generable
public struct DocumentOutline: Sendable {
  @Guide(description: "Title for the whole document")
  public var title: String
  @Guide(description: "Two or three sentence overview")
  public var overview: String
}

extension FoundationModelsOrganizer {
  public func outline(topics: [String], terms: [String]) async throws -> DocumentOutline? { nil }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter MapStage`
Expected: PASS, 2 tests.

- [ ] **Step 7: Commit**

```bash
git add Sources/TranscriptorKit/Organize Tests
git commit -m "feat: structured chunk note extraction with overflow splitting"
```

---

### Task 7: Merge, dedupe, and the reduce stage

**Files:**
- Create: `Sources/TranscriptorKit/Organize/OrganizedDocument.swift`
- Modify: `Sources/TranscriptorKit/Organize/Organizing.swift` (replace the Task 6 stub)
- Test: `Tests/TranscriptorKitTests/MergeTests.swift`

**Interfaces:**
- Consumes: `ChunkNotes` (Task 6)
- Produces: `OrganizedDocument`, `OrganizedDocument.Section`, `DocumentOutline` with `groups: [OutlineGroup]`, `DocumentMerger.merge(notes:outline:) -> OrganizedDocument`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import TranscriptorKit

private func notes(_ topic: String, terms: [String] = [], points: [String] = ["a point"]) -> ChunkNotes {
  ChunkNotes(topic: topic, summary: "s", keyPoints: points, terms: terms, guidance: [], caveats: [])
}

@Test func fallsBackToLinearOrderWithoutAnOutline() {
  let doc = DocumentMerger.merge(notes: [notes("One"), notes("Two")], outline: nil)
  #expect(doc.sections.count == 2)
  #expect(doc.sections.map(\.title) == ["One", "Two"])
  #expect(!doc.title.isEmpty)
}

@Test func groupsChunksAccordingToTheOutline() {
  let outline = DocumentOutline(
    title: "Session Notes", overview: "An overview.",
    groups: [
      OutlineGroup(title: "Setup", chunkIndices: [0, 2]),
      OutlineGroup(title: "Details", chunkIndices: [1]),
    ])
  let doc = DocumentMerger.merge(
    notes: [notes("A", points: ["p0"]), notes("B", points: ["p1"]), notes("C", points: ["p2"])],
    outline: outline)

  #expect(doc.title == "Session Notes")
  #expect(doc.sections.count == 2)
  #expect(doc.sections[0].title == "Setup")
  #expect(doc.sections[0].keyPoints == ["p0", "p2"])
}

@Test func dedupesTermsCaseInsensitivelyKeepingFirstSpelling() {
  let doc = DocumentMerger.merge(
    notes: [notes("A", terms: ["SwiftUI", "Combine"]), notes("B", terms: ["swiftui", "Observation"])],
    outline: nil)
  #expect(doc.termIndex == ["Combine", "Observation", "SwiftUI"])
}

@Test func ignoresOutOfRangeChunkIndices() {
  let outline = DocumentOutline(
    title: "T", overview: "O",
    groups: [OutlineGroup(title: "Group", chunkIndices: [0, 99])])
  let doc = DocumentMerger.merge(notes: [notes("A")], outline: outline)
  #expect(doc.sections.count == 1)
  #expect(doc.sections[0].keyPoints == ["a point"])
}

@Test func dropsGroupsThatEndUpEmpty() {
  let outline = DocumentOutline(
    title: "T", overview: "O",
    groups: [OutlineGroup(title: "Real", chunkIndices: [0]), OutlineGroup(title: "Empty", chunkIndices: [42])])
  let doc = DocumentMerger.merge(notes: [notes("A")], outline: outline)
  #expect(doc.sections.map(\.title) == ["Real"])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter Merge`
Expected: FAIL, `cannot find 'DocumentMerger' in scope`.

- [ ] **Step 3: Implement the document model and merger**

```swift
import Foundation

public struct OrganizedDocument: Sendable, Equatable {
  public struct Section: Sendable, Equatable {
    public var title: String
    public var summary: String
    public var keyPoints: [String]
    public var guidance: [String]
    public var caveats: [String]
  }

  public var title: String
  public var overview: String
  public var sections: [Section]
  public var termIndex: [String]
}

public enum DocumentMerger {
  public static func merge(notes: [ChunkNotes], outline: DocumentOutline?) -> OrganizedDocument {
    let sections: [OrganizedDocument.Section]
    if let outline, !outline.groups.isEmpty {
      sections = outline.groups.compactMap { group in
        let members = group.chunkIndices.filter { notes.indices.contains($0) }.map { notes[$0] }
        guard !members.isEmpty else { return nil }
        return OrganizedDocument.Section(
          title: group.title,
          summary: members.map(\.summary).joined(separator: " "),
          keyPoints: members.flatMap(\.keyPoints),
          guidance: members.flatMap(\.guidance),
          caveats: members.flatMap(\.caveats))
      }
    } else {
      sections = notes.map {
        OrganizedDocument.Section(
          title: $0.topic, summary: $0.summary,
          keyPoints: $0.keyPoints, guidance: $0.guidance, caveats: $0.caveats)
      }
    }

    var seen: Set<String> = []
    var terms: [String] = []
    for term in notes.flatMap(\.terms) {
      let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
      terms.append(trimmed)
    }

    return OrganizedDocument(
      title: outline?.title.isEmpty == false ? outline!.title : (notes.first?.topic ?? "Transcription"),
      overview: outline?.overview ?? "",
      sections: sections,
      termIndex: terms.sorted { $0.lowercased() < $1.lowercased() })
  }
}
```

- [ ] **Step 4: Replace the Task 6 stub with the real outline types**

Delete the stub `DocumentOutline` and stub `outline(topics:terms:)` extension from `Organizing.swift` and add:

```swift
@Generable
public struct OutlineGroup: Sendable {
  @Guide(description: "Title for this group of passages")
  public var title: String
  @Guide(description: "Zero-based indices of the passages belonging to this group", .count(1...12))
  public var chunkIndices: [Int]
}

@Generable
public struct DocumentOutline: Sendable {
  @Guide(description: "Title for the whole document")
  public var title: String
  @Guide(description: "Two or three sentence overview of what the document covers")
  public var overview: String
  @Guide(description: "Groups of passages, in reading order", .count(1...15))
  public var groups: [OutlineGroup]
}
```

And implement the real reduce on `FoundationModelsOrganizer`:

```swift
public func outline(topics: [String], terms: [String]) async throws -> DocumentOutline? {
  let numbered = topics.enumerated().map { "\($0.offset). \($0.element)" }.joined(separator: "\n")
  let termList = terms.prefix(60).joined(separator: ", ")
  let session = LanguageModelSession(instructions: """
    You organize a list of transcript passage topics into a document outline.
    Group passages that cover the same subject, even when they are far apart.
    Every index you use must come from the list given. Never invent an index.
    Preserve reading order across groups.
    """)
  do {
    return try await session.respond(
      to: "Passage topics:\n\(numbered)\n\nTerms mentioned: \(termList)",
      generating: DocumentOutline.self).content
  } catch {
    warn("outline generation failed, falling back to linear order: \(error)")
    return nil
  }
}
```

The reduce input is only topics and a capped term list, so it cannot overflow regardless of video length.
Returning `nil` on any failure is what makes the reduce an enhancement rather than a dependency.

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter Merge`
Expected: PASS, 6 tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/TranscriptorKit/Organize Tests
git commit -m "feat: merge chunk notes into an organized document"
```

---

### Task 8: Organized markdown renderer

**Files:**
- Modify: `Sources/TranscriptorKit/Render/MarkdownRenderer.swift`
- Test: `Tests/TranscriptorKitTests/OrganizedRenderTests.swift`

**Interfaces:**
- Consumes: `OrganizedDocument` (Task 7)
- Produces: `MarkdownRenderer.organized(_ document: OrganizedDocument) -> String`

- [ ] **Step 1: Write the failing test**

Section omission is the behavior that lets one schema serve technical and non-technical content, so it gets the most coverage.

```swift
import Testing
@testable import TranscriptorKit

private let technical = OrganizedDocument(
  title: "Glass Effects",
  overview: "How glass works.",
  sections: [.init(
    title: "Basics", summary: "The modifier.",
    keyPoints: ["Apply to a view."],
    guidance: ["Group related views."],
    caveats: ["iOS 26 or later."])],
  termIndex: ["GlassEffectContainer", "SwiftUI"])

private let plain = OrganizedDocument(
  title: "A Lecture",
  overview: "About a topic.",
  sections: [.init(
    title: "Opening", summary: "The premise.",
    keyPoints: ["A single point."],
    guidance: [], caveats: [])],
  termIndex: [])

@Test func rendersEveryPopulatedSection() {
  let md = MarkdownRenderer.organized(technical)
  #expect(md.contains("# Glass Effects"))
  #expect(md.contains("How glass works."))
  #expect(md.contains("## Basics"))
  #expect(md.contains("- Apply to a view."))
  #expect(md.contains("### Guidance"))
  #expect(md.contains("### Caveats"))
  #expect(md.contains("GlassEffectContainer"))
}

@Test func omitsEmptySectionsEntirely() {
  let md = MarkdownRenderer.organized(plain)
  #expect(md.contains("## Opening"))
  #expect(!md.contains("### Guidance"))
  #expect(!md.contains("### Caveats"))
  #expect(!md.contains("## Terms"))
}

@Test func omitsOverviewWhenAbsent() {
  var doc = plain
  doc.overview = ""
  let md = MarkdownRenderer.organized(doc)
  #expect(md.contains("# A Lecture"))
  #expect(!md.contains("## Overview"))
}

@Test func noHeadingIsImmediatelyFollowedByAnotherHeading() {
  let md = MarkdownRenderer.organized(plain)
  let lines = md.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
  let headingFollowedByHeading = zip(lines, lines.dropFirst())
    .contains { $0.hasPrefix("#") && $1.hasPrefix("###") }
  #expect(headingFollowedByHeading == false)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter OrganizedRender`
Expected: FAIL, `type 'MarkdownRenderer' has no member 'organized'`.

- [ ] **Step 3: Implement the renderer**

```swift
extension MarkdownRenderer {
  public static func organized(_ document: OrganizedDocument) -> String {
    var lines: [String] = ["# \(document.title)", ""]

    if !document.overview.isEmpty {
      lines.append(contentsOf: ["## Overview", "", document.overview, ""])
    }

    for section in document.sections {
      lines.append("## \(section.title)")
      lines.append("")
      if !section.summary.isEmpty {
        lines.append(contentsOf: [section.summary, ""])
      }
      appendList(&lines, heading: nil, items: section.keyPoints)
      appendList(&lines, heading: "### Guidance", items: section.guidance)
      appendList(&lines, heading: "### Caveats", items: section.caveats)
    }

    if !document.termIndex.isEmpty {
      appendList(&lines, heading: "## Terms", items: document.termIndex)
    }

    return lines.joined(separator: "\n")
  }

  private static func appendList(_ lines: inout [String], heading: String?, items: [String]) {
    guard !items.isEmpty else { return }
    if let heading { lines.append(contentsOf: [heading, ""]) }
    for item in items { lines.append("- \(item)") }
    lines.append("")
  }
}
```

The `guard !items.isEmpty` in `appendList` before the heading is appended is the single line that guarantees no empty heading ever renders.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter OrganizedRender`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/TranscriptorKit/Render Tests
git commit -m "feat: render organized markdown, omitting empty sections"
```

---

### Task 9: Pipeline orchestration

**Files:**
- Create: `Sources/TranscriptorKit/Pipeline.swift`
- Test: `Tests/TranscriptorKitTests/PipelineTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1 through 8
- Produces: `Pipeline(workspace:transcriber:organizer:)`, `Pipeline.process(videoURL:locale:transcribeOnly:) async throws -> PipelineResult`, `PipelineResult(transcriptPath:organizedPath:)`

- [ ] **Step 1: Write the failing test**

Fakes are what let orchestration and its failure paths be tested without a model.

```swift
import Testing
import Foundation
@testable import TranscriptorKit

private struct FakeTranscriber: Transcribing {
  var segments: [TranscriptSegment] = [
    TranscriptSegment(text: "First thing said.", start: 0, end: 2),
    TranscriptSegment(text: "Second thing said.", start: 2, end: 4),
  ]
  func transcribe(url: URL, locale: Locale) async throws -> [TranscriptSegment] { segments }
}

private struct FakeOrganizer: Organizing {
  var outlineResult: DocumentOutline?
  func notes(for chunk: [TranscriptSegment]) async throws -> ChunkNotes? {
    ChunkNotes(topic: "Topic", summary: "Summary.", keyPoints: ["Point."],
               terms: ["Term"], guidance: [], caveats: [])
  }
  func outline(topics: [String], terms: [String]) async throws -> DocumentOutline? { outlineResult }
}

private func makeWorkspace() -> Workspace {
  Workspace(root: URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString))
}

@Test func writesBothDocuments() async throws {
  let ws = makeWorkspace()
  defer { try? FileManager.default.removeItem(at: ws.root) }
  let pipeline = Pipeline(workspace: ws, transcriber: FakeTranscriber(), organizer: FakeOrganizer())
  let video = ws.videosDirectory.appending(path: "demo.mp4")

  let result = try await pipeline.process(videoURL: video, locale: Locale(identifier: "en_US"), transcribeOnly: false)

  let transcript = try String(contentsOf: result.transcriptPath, encoding: .utf8)
  #expect(transcript.contains("[00:00] First thing said."))
  let organizedPath = try #require(result.organizedPath)
  let organized = try String(contentsOf: organizedPath, encoding: .utf8)
  #expect(organized.contains("Point."))
}

@Test func transcribeOnlySkipsTheOrganizedDocument() async throws {
  let ws = makeWorkspace()
  defer { try? FileManager.default.removeItem(at: ws.root) }
  let pipeline = Pipeline(workspace: ws, transcriber: FakeTranscriber(), organizer: FakeOrganizer())
  let video = ws.videosDirectory.appending(path: "demo.mp4")

  let result = try await pipeline.process(videoURL: video, locale: Locale(identifier: "en_US"), transcribeOnly: true)

  #expect(result.organizedPath == nil)
  #expect(FileManager.default.fileExists(atPath: result.transcriptPath.path))
  #expect(!FileManager.default.fileExists(atPath: ws.outputDirectory(for: video).appending(path: "organized.md").path))
}

@Test func transcriptSurvivesAFailingOrganizer() async throws {
  struct FailingOrganizer: Organizing {
    func notes(for chunk: [TranscriptSegment]) async throws -> ChunkNotes? {
      throw OrganizeError.contextOverflow
    }
    func outline(topics: [String], terms: [String]) async throws -> DocumentOutline? { nil }
  }
  let ws = makeWorkspace()
  defer { try? FileManager.default.removeItem(at: ws.root) }
  let pipeline = Pipeline(workspace: ws, transcriber: FakeTranscriber(), organizer: FailingOrganizer())
  let video = ws.videosDirectory.appending(path: "demo.mp4")

  let result = try await pipeline.process(videoURL: video, locale: Locale(identifier: "en_US"), transcribeOnly: false)
  #expect(FileManager.default.fileExists(atPath: result.transcriptPath.path))
}

@Test func emptyTranscriptStillWritesAFile() async throws {
  var fake = FakeTranscriber()
  fake.segments = []
  let ws = makeWorkspace()
  defer { try? FileManager.default.removeItem(at: ws.root) }
  let pipeline = Pipeline(workspace: ws, transcriber: fake, organizer: FakeOrganizer())
  let result = try await pipeline.process(
    videoURL: ws.videosDirectory.appending(path: "demo.mp4"),
    locale: Locale(identifier: "en_US"), transcribeOnly: false)
  #expect(FileManager.default.fileExists(atPath: result.transcriptPath.path))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter Pipeline`
Expected: FAIL, `cannot find 'Pipeline' in scope`.

- [ ] **Step 3: Implement Pipeline**

`AudioExtractor.duration` is tolerated to fail because the fake tests use paths with no real file, and duration is cosmetic frontmatter.

```swift
import Foundation

public struct PipelineResult: Sendable {
  public let transcriptPath: URL
  public let organizedPath: URL?
}

public struct Pipeline: Sendable {
  private let workspace: Workspace
  private let transcriber: any Transcribing
  private let organizer: any Organizing

  public init(workspace: Workspace, transcriber: any Transcribing, organizer: any Organizing) {
    self.workspace = workspace
    self.transcriber = transcriber
    self.organizer = organizer
  }

  public func process(
    videoURL: URL,
    locale: Locale,
    transcribeOnly: Bool
  ) async throws -> PipelineResult {
    let outputDirectory = workspace.outputDirectory(for: videoURL)
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    warn("transcribing \(videoURL.lastPathComponent)")
    let segments = try await transcriber.transcribe(url: videoURL, locale: locale)
    let duration = (try? await AudioExtractor.duration(of: videoURL)) ?? (segments.last?.end ?? 0)

    let transcriptPath = outputDirectory.appending(path: "full-transcription.md")
    try MarkdownRenderer.fullTranscript(
      segments: segments,
      sourcePath: videoURL.path,
      duration: duration,
      locale: locale.identifier,
      date: Date()
    ).write(to: transcriptPath, atomically: true, encoding: .utf8)

    guard !transcribeOnly else {
      return PipelineResult(transcriptPath: transcriptPath, organizedPath: nil)
    }

    let chunks = TranscriptChunker.chunk(segments)
    var allNotes: [ChunkNotes] = []
    for (index, chunk) in chunks.enumerated() {
      warn("organizing passage \(index + 1) of \(chunks.count)")
      do {
        allNotes.append(contentsOf: try await organizer.notesSplittingOnOverflow(for: chunk))
      } catch {
        warn("passage \(index + 1) failed: \(error)")
      }
    }

    guard !allNotes.isEmpty else {
      warn("no passages could be organized, keeping the transcript only")
      return PipelineResult(transcriptPath: transcriptPath, organizedPath: nil)
    }

    let outline = try? await organizer.outline(
      topics: allNotes.map(\.topic),
      terms: Array(Set(allNotes.flatMap(\.terms))).sorted())

    let document = DocumentMerger.merge(notes: allNotes, outline: outline)
    let organizedPath = outputDirectory.appending(path: "organized.md")
    try MarkdownRenderer.organized(document)
      .write(to: organizedPath, atomically: true, encoding: .utf8)

    return PipelineResult(transcriptPath: transcriptPath, organizedPath: organizedPath)
  }
}
```

`Pipeline` calls `notesSplittingOnOverflow`, which every conformer gets by default from the Task 6 protocol extension.
The test fakes therefore stay simple while `FoundationModelsOrganizer` still contributes its recursive splitting override.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter Pipeline`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/TranscriptorKit/Pipeline.swift Tests
git commit -m "feat: pipeline orchestration across transcription and organization"
```

---

### Task 10: CLI

**Files:**
- Modify: `Sources/transcriptor/Transcriptor.swift`
- Test: manual verification, plus `Tests/TranscriptorKitTests/WorkspaceTests.swift` already covers batch selection

**Interfaces:**
- Consumes: `Workspace`, `Pipeline`, `SpeechTranscriberEngine`, `FoundationModelsOrganizer`
- Produces: the `transcriptor` executable

- [ ] **Step 1: Implement the command**

The availability check runs before any work so the user is told immediately, and `transcribeOnly` is forced on rather than failing outright, so the expensive stage still runs.

```swift
import ArgumentParser
import Foundation
import FoundationModels
import TranscriptorKit

@main
struct Transcriptor: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "transcriptor",
    abstract: "Transcribe a video and organize the transcript into structured notes.")

  @Argument(help: "Path to a video file. Omit to process every unprocessed video in videos/.")
  var path: String?

  @Flag(name: .long, help: "Reprocess videos that already have output.")
  var force = false

  @Flag(name: .long, help: "Write the transcript only, skipping the organized notes.")
  var transcribeOnly = false

  @Option(name: .long, help: "Locale for transcription, for example en_US.")
  var locale: String?

  mutating func run() async throws {
    let workspace = Workspace(root: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    let resolvedLocale = Locale(identifier: locale ?? Locale.current.identifier)

    var effectiveTranscribeOnly = transcribeOnly
    if !transcribeOnly, case .available = SystemLanguageModel.default.availability {} else if !transcribeOnly {
      FileHandle.standardError.write(Data(
        "Apple Intelligence is unavailable, so notes cannot be generated. Writing transcripts only.\n".utf8))
      effectiveTranscribeOnly = true
    }

    let videos: [URL]
    if let path {
      videos = [URL(fileURLWithPath: path)]
    } else {
      videos = try workspace.pendingVideos(transcribeOnly: effectiveTranscribeOnly, force: force)
    }

    guard !videos.isEmpty else {
      print("Nothing to do.")
      return
    }

    var failures = 0
    for video in videos {
      if path == nil, !force, workspace.isProcessed(videoURL: video, transcribeOnly: effectiveTranscribeOnly) {
        continue
      }
      do {
        let pipeline = Pipeline(
          workspace: workspace,
          transcriber: SpeechTranscriberEngine(),
          organizer: FoundationModelsOrganizer())
        let result = try await pipeline.process(
          videoURL: video, locale: resolvedLocale, transcribeOnly: effectiveTranscribeOnly)
        print(result.organizedPath?.path ?? result.transcriptPath.path)
      } catch {
        failures += 1
        FileHandle.standardError.write(Data("failed \(video.lastPathComponent): \(error)\n".utf8))
      }
    }

    if failures > 0 { throw ExitCode(1) }
    if effectiveTranscribeOnly, !transcribeOnly { throw ExitCode(1) }
  }
}
```

- [ ] **Step 2: Build and verify the help output**

```bash
swift build
.build/debug/transcriptor --help
```

Expected: usage listing `--force`, `--transcribe-only`, and `--locale`.

- [ ] **Step 3: Verify against a real video**

```bash
mkdir -p videos transcriptions
# place a short mp4 in videos/ first
.build/debug/transcriptor videos/<your-file>.mp4
cat transcriptions/<your-file>/organized.md
```

Expected: both files written; `organized.md` has a title, sections, and no empty headings.

- [ ] **Step 4: Verify batch skip behavior**

```bash
.build/debug/transcriptor
```

Expected: "Nothing to do." because the video now has `organized.md`.

- [ ] **Step 5: Run the full test suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/transcriptor
git commit -m "feat: command line interface with batch and single-file modes"
```

---

## Self-Review Notes

Spec coverage was checked section by section against these tasks.

| Spec section | Task |
|---|---|
| Package layout | 1 |
| Stage 1 audio extraction | 4 |
| Stage 2 transcription | 5 |
| Stage 3 chunking | 2 |
| Stage 4 map, overflow retry, guardrail skip | 6 |
| Stage 5 reduce, bounded input, fallback | 7 |
| Stage 6 rendering, empty section omission | 3, 8 |
| CLI and flags | 10 |
| Error handling table | 4, 5, 6, 9, 10 |
| Testing requirements | 2, 4, 7, 8, 9 |

The four spec-mandated boundary tests all have homes: oversized single segment in Task 2, all-empty optional arrays in Task 8, reduce failure fallback in Task 7, and case-differing term dedupe in Task 7.
