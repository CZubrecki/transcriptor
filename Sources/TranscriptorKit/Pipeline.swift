import Foundation

// MARK: - PipelineResult

public struct PipelineResult: Sendable {
  public let transcriptPath: URL
  public let organizedPath: URL?
  public let passagesOrganized: Int
  public let passagesFailed: Int
}

// MARK: - Pipeline

public struct Pipeline: Sendable {

  // MARK: Lifecycle

  public init(workspace: Workspace, transcriber: any Transcribing, organizer: any Organizing) {
    self.workspace = workspace
    self.transcriber = transcriber
    self.organizer = organizer
  }

  // MARK: Public

  public func process(
    videoURL: URL,
    locale: Locale,
    transcribeOnly: Bool,
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
      date: Date(),
    ).write(to: transcriptPath, atomically: true, encoding: .utf8)

    guard !transcribeOnly else {
      return PipelineResult(transcriptPath: transcriptPath, organizedPath: nil, passagesOrganized: 0, passagesFailed: 0)
    }

    let chunks = TranscriptChunker.chunk(segments)
    var allNotes = [ChunkNotes]()
    var failedChunks = 0
    for (index, chunk) in chunks.enumerated() {
      warn("organizing passage \(index + 1) of \(chunks.count)")
      do {
        let notes = try await organizer.notesSplittingOnOverflow(for: chunk)
        if notes.isEmpty {
          failedChunks += 1
        } else {
          allNotes.append(contentsOf: notes)
        }
      } catch {
        failedChunks += 1
        warn("passage \(index + 1) failed: \(error)")
      }
    }

    if failedChunks > 0 {
      warn("organized \(chunks.count - failedChunks) of \(chunks.count) passages; \(failedChunks) failed")
    }

    guard !allNotes.isEmpty else {
      warn("no passages could be organized, keeping the transcript only")
      return PipelineResult(
        transcriptPath: transcriptPath,
        organizedPath: nil,
        passagesOrganized: 0,
        passagesFailed: failedChunks,
      )
    }

    guard failedChunks * 2 <= chunks.count else {
      warn("more than half the passages failed to organize (\(failedChunks) of \(chunks.count)); "
        + "organized notes were not written, keeping the transcript only")
      return PipelineResult(
        transcriptPath: transcriptPath,
        organizedPath: nil,
        passagesOrganized: chunks.count - failedChunks,
        passagesFailed: failedChunks,
      )
    }

    let outline = try? await organizer.outline(
      topics: allNotes.map(\.topic),
      terms: Array(Set(allNotes.flatMap(\.terms))).sorted(),
    )

    let document = DocumentMerger.merge(notes: allNotes, outline: outline)
    let organizedPath = outputDirectory.appending(path: "organized.md")
    try MarkdownRenderer.organized(document)
      .write(to: organizedPath, atomically: true, encoding: .utf8)

    return PipelineResult(
      transcriptPath: transcriptPath,
      organizedPath: organizedPath,
      passagesOrganized: chunks.count - failedChunks,
      passagesFailed: failedChunks,
    )
  }

  // MARK: Private

  private let workspace: Workspace
  private let transcriber: any Transcribing
  private let organizer: any Organizing

}
