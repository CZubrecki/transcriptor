import AVFoundation
import Foundation
import Speech

// MARK: - Transcribing

public protocol Transcribing: Sendable {
  func transcribe(url: URL, locale: Locale) async throws -> [TranscriptSegment]
}

// MARK: - TranscriptionError

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

// MARK: - SpeechTranscriberEngine

public struct SpeechTranscriberEngine: Transcribing {

  // MARK: Lifecycle

  public init() { }

  // MARK: Public

  public func transcribe(url: URL, locale: Locale) async throws -> [TranscriptSegment] {
    let supported = await SpeechTranscriber.supportedLocales
    guard supported.contains(where: { $0.identifier == locale.identifier }) else {
      throw TranscriptionError.localeUnsupported(locale.identifier)
    }

    let transcriber = SpeechTranscriber(
      locale: locale,
      transcriptionOptions: [],
      reportingOptions: [],
      attributeOptions: [.audioTimeRange],
    )

    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
      FileHandle.standardError.write(Data("installing speech assets for \(locale.identifier)\n".utf8))
      try await request.downloadAndInstall()
    }

    let analyzer = SpeechAnalyzer(modules: [transcriber])
    guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
      throw TranscriptionError.noCompatibleAudioFormat
    }

    let collector = Task {
      var collected = [TranscriptSegment]()
      for try await result in transcriber.results where result.isFinal {
        collected.append(TranscriptSegment(
          text: String(result.text.characters),
          start: result.range.start.seconds,
          end: result.range.end.seconds,
        ))
      }
      return collected
    }

    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    try await analyzer.start(inputSequence: stream)

    do {
      for try await buffer in try await AudioExtractor.buffers(from: url, to: format) {
        continuation.yield(AnalyzerInput(buffer: buffer))
      }
    } catch {
      continuation.finish()
      collector.cancel()
      await analyzer.cancelAndFinishNow()
      throw error
    }

    continuation.finish()
    try await analyzer.finalizeAndFinishThroughEndOfInput()
    return try await collector.value
  }
}
