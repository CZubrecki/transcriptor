import ArgumentParser
import Foundation
import FoundationModels
import Speech
import TranscriptorKit

@main
struct Transcriptor: AsyncParsableCommand {

  // MARK: Internal

  static let configuration = CommandConfiguration(
    commandName: "transcriptor",
    abstract: "Transcribe a video and organize the transcript into structured notes.",
  )

  @Argument(help: "Path to a video file. Omit to process every unprocessed video in videos/.")
  var path: String?

  @Flag(
    name: .long,
    help: "Reprocess videos that already have output. Applies to batch mode only; an explicitly named file is always processed.",
  )
  var force = false

  @Flag(name: .long, help: "Write the transcript only, skipping the organized notes.")
  var transcribeOnly = false

  @Option(name: .long, help: "Locale for transcription, for example en_US.")
  var locale: String?

  mutating func run() async throws {
    let workspace = Workspace(root: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    let resolvedLocale = try await resolveLocale()

    var modelUnavailable = false
    if !transcribeOnly {
      if case .available = SystemLanguageModel.default.availability {} else {
        FileHandle.standardError.write(Data(
          "Apple Intelligence is unavailable, so notes cannot be generated. Writing transcripts only.\n".utf8
        ))
        modelUnavailable = true
      }
    }
    let effectiveTranscribeOnly = transcribeOnly || modelUnavailable

    let videos: [URL]
    if let path {
      videos = [URL(fileURLWithPath: path)]
    } else {
      guard FileManager.default.fileExists(atPath: workspace.videosDirectory.path) else {
        FileHandle.standardError.write(Data(
          "videos directory not found at \(workspace.videosDirectory.path); create it and put video files in it.\n".utf8
        ))
        throw ExitCode(1)
      }
      videos = try workspace.pendingVideos(transcribeOnly: effectiveTranscribeOnly, force: force)
    }

    guard !videos.isEmpty else {
      print("Nothing to do.")
      return
    }

    var failures = 0
    for video in videos {
      do {
        let pipeline = Pipeline(
          workspace: workspace,
          transcriber: SpeechTranscriberEngine(),
          organizer: FoundationModelsOrganizer(),
        )
        let result = try await pipeline.process(
          videoURL: video,
          locale: resolvedLocale,
          transcribeOnly: effectiveTranscribeOnly,
        )
        print(result.organizedPath?.path ?? result.transcriptPath.path)
        if !effectiveTranscribeOnly, result.organizedPath == nil {
          failures += 1
          FileHandle.standardError.write(Data(
            "\(video.lastPathComponent): organized notes were not produced.\n".utf8
          ))
        }
      } catch {
        failures += 1
        FileHandle.standardError.write(Data("failed \(video.lastPathComponent): \(error)\n".utf8))
      }
    }

    if failures > 0 || modelUnavailable { throw ExitCode(1) }
  }

  // MARK: Private

  private func resolveLocale() async throws -> Locale {
    let supported = Set(await SpeechTranscriber.supportedLocales.map(\.identifier))

    if let locale {
      guard supported.contains(locale) else {
        FileHandle.standardError.write(Data(
          "locale \(locale) is not supported for transcription.\n".utf8
        ))
        throw ExitCode(1)
      }
      return Locale(identifier: locale)
    }

    let current = Locale.current.identifier
    if supported.contains(current) {
      return Locale(identifier: current)
    }

    guard supported.contains("en_US") else {
      FileHandle.standardError.write(Data(
        "neither the current locale (\(current)) nor en_US is supported for transcription.\n".utf8
      ))
      throw ExitCode(1)
    }
    FileHandle.standardError.write(Data(
      "the current locale (\(current)) is not supported for transcription; using en_US instead.\n".utf8
    ))
    return Locale(identifier: "en_US")
  }
}
