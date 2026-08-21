import Foundation
import Testing
@testable import TranscriptorKit

// MARK: - FakeTranscriber

private struct FakeTranscriber: Transcribing {
  var segments: [TranscriptSegment] = [
    TranscriptSegment(text: "First thing said.", start: 0, end: 2),
    TranscriptSegment(text: "Second thing said.", start: 2, end: 4),
  ]

  func transcribe(url _: URL, locale _: Locale) async throws -> [TranscriptSegment] {
    segments
  }
}

// MARK: - FakeOrganizer

private struct FakeOrganizer: Organizing {
  var outlineResult: DocumentOutline?

  func notes(for _: [TranscriptSegment]) async throws -> ChunkNotes? {
    ChunkNotes(
      topic: "Topic",
      summary: "Summary.",
      keyPoints: ["Point."],
      terms: ["Term"],
      guidance: [],
      caveats: [],
    )
  }

  func outline(topics _: [String], terms _: [String]) async throws -> DocumentOutline? {
    outlineResult
  }
}

private func makeWorkspace() -> Workspace {
  Workspace(root: URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString))
}

/// Each segment alone estimates to 1250 tokens (5000 chars / 4), which exceeds the chunker's
/// 1200-token target, so every segment starts and ends its own chunk: `count` segments in,
/// `count` single-segment chunks out. Verified empirically via the per-chunk stderr warnings.
private func makeChunkableSegments(count: Int) -> [TranscriptSegment] {
  (0..<count).map { index in
    TranscriptSegment(
      text: String(repeating: "word ", count: 1000),
      start: Double(index) * 10,
      end: Double(index) * 10 + 9,
    )
  }
}

// MARK: - VariableOutcomeOrganizer

/// Behaves differently per call, keyed by call order rather than chunk content, which is safe
/// because Pipeline processes chunks strictly sequentially.
private final class VariableOutcomeOrganizer: Organizing, @unchecked Sendable {

  // MARK: Lifecycle

  init(failingIndices: Set<Int> = [], emptyIndices: Set<Int> = []) {
    self.failingIndices = failingIndices
    self.emptyIndices = emptyIndices
  }

  // MARK: Internal

  func notes(for _: [TranscriptSegment]) async throws -> ChunkNotes? {
    let index = callIndex
    callIndex += 1
    if failingIndices.contains(index) { throw OrganizeError.contextOverflow }
    if emptyIndices.contains(index) { return nil }
    return ChunkNotes(
      topic: "Topic \(index)",
      summary: "Summary.",
      keyPoints: ["Point \(index)."],
      terms: ["Term"],
      guidance: [],
      caveats: [],
    )
  }

  func outline(topics _: [String], terms _: [String]) async throws -> DocumentOutline? {
    nil
  }

  // MARK: Private

  private let failingIndices: Set<Int>
  private let emptyIndices: Set<Int>
  private var callIndex = 0

}

@Test
func `writes both documents`() async throws {
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

@Test
func `transcribe only skips the organized document`() async throws {
  let ws = makeWorkspace()
  defer { try? FileManager.default.removeItem(at: ws.root) }
  let pipeline = Pipeline(workspace: ws, transcriber: FakeTranscriber(), organizer: FakeOrganizer())
  let video = ws.videosDirectory.appending(path: "demo.mp4")

  let result = try await pipeline.process(videoURL: video, locale: Locale(identifier: "en_US"), transcribeOnly: true)

  #expect(result.organizedPath == nil)
  #expect(FileManager.default.fileExists(atPath: result.transcriptPath.path))
  #expect(!FileManager.default.fileExists(atPath: ws.outputDirectory(for: video).appending(path: "organized.md").path))
}

@Test
func `transcript survives A failing organizer`() async throws {
  struct FailingOrganizer: Organizing {
    func notes(for _: [TranscriptSegment]) async throws -> ChunkNotes? {
      throw OrganizeError.contextOverflow
    }

    func outline(topics _: [String], terms _: [String]) async throws -> DocumentOutline? {
      nil
    }
  }
  let ws = makeWorkspace()
  defer { try? FileManager.default.removeItem(at: ws.root) }
  let pipeline = Pipeline(workspace: ws, transcriber: FakeTranscriber(), organizer: FailingOrganizer())
  let video = ws.videosDirectory.appending(path: "demo.mp4")

  let result = try await pipeline.process(videoURL: video, locale: Locale(identifier: "en_US"), transcribeOnly: false)
  #expect(FileManager.default.fileExists(atPath: result.transcriptPath.path))
}

@Test
func `empty transcript still writes A file`() async throws {
  var fake = FakeTranscriber()
  fake.segments = []
  let ws = makeWorkspace()
  defer { try? FileManager.default.removeItem(at: ws.root) }
  let pipeline = Pipeline(workspace: ws, transcriber: fake, organizer: FakeOrganizer())
  let result = try await pipeline.process(
    videoURL: ws.videosDirectory.appending(path: "demo.mp4"),
    locale: Locale(identifier: "en_US"),
    transcribeOnly: false,
  )
  #expect(FileManager.default.fileExists(atPath: result.transcriptPath.path))
}

@Test
func `minority of failed passages still writes organized notes`() async throws {
  var fake = FakeTranscriber()
  fake.segments = makeChunkableSegments(count: 5)
  let organizer = VariableOutcomeOrganizer(failingIndices: [0])
  let ws = makeWorkspace()
  defer { try? FileManager.default.removeItem(at: ws.root) }
  let pipeline = Pipeline(workspace: ws, transcriber: fake, organizer: organizer)

  let result = try await pipeline.process(
    videoURL: ws.videosDirectory.appending(path: "demo.mp4"),
    locale: Locale(identifier: "en_US"),
    transcribeOnly: false,
  )

  let organizedPath = try #require(result.organizedPath)
  #expect(FileManager.default.fileExists(atPath: organizedPath.path))
  #expect(result.passagesOrganized == 4)
  #expect(result.passagesFailed == 1)
}

@Test
func `majority of failed passages withholds organized notes`() async throws {
  var fake = FakeTranscriber()
  fake.segments = makeChunkableSegments(count: 5)
  let organizer = VariableOutcomeOrganizer(failingIndices: [0, 1, 2])
  let ws = makeWorkspace()
  defer { try? FileManager.default.removeItem(at: ws.root) }
  let pipeline = Pipeline(workspace: ws, transcriber: fake, organizer: organizer)
  let video = ws.videosDirectory.appending(path: "demo.mp4")

  let result = try await pipeline.process(
    videoURL: video,
    locale: Locale(identifier: "en_US"),
    transcribeOnly: false,
  )

  #expect(result.organizedPath == nil)
  #expect(!FileManager.default.fileExists(atPath: ws.outputDirectory(for: video).appending(path: "organized.md").path))
  #expect(FileManager.default.fileExists(atPath: result.transcriptPath.path))
  #expect(result.passagesOrganized == 2)
  #expect(result.passagesFailed == 3)
}

@Test
func `empty result without throwing counts as A failed passage`() async throws {
  var fake = FakeTranscriber()
  fake.segments = makeChunkableSegments(count: 5)
  let organizer = VariableOutcomeOrganizer(emptyIndices: [2])
  let ws = makeWorkspace()
  defer { try? FileManager.default.removeItem(at: ws.root) }
  let pipeline = Pipeline(workspace: ws, transcriber: fake, organizer: organizer)

  let result = try await pipeline.process(
    videoURL: ws.videosDirectory.appending(path: "demo.mp4"),
    locale: Locale(identifier: "en_US"),
    transcribeOnly: false,
  )

  #expect(result.organizedPath != nil)
  #expect(result.passagesFailed == 1)
  #expect(result.passagesOrganized == 4)
}
