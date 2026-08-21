import Foundation

public struct Workspace: Sendable {

  // MARK: Lifecycle

  public init(root: URL) {
    self.root = root
  }

  // MARK: Public

  public let root: URL

  public var videosDirectory: URL {
    root.appending(path: "videos")
  }

  public var transcriptionsDirectory: URL {
    root.appending(path: "transcriptions")
  }

  public func outputDirectory(for videoURL: URL) -> URL {
    transcriptionsDirectory.appending(path: videoURL.deletingPathExtension().lastPathComponent)
  }

  public func isProcessed(videoURL: URL, transcribeOnly: Bool) -> Bool {
    let marker = transcribeOnly ? "full-transcription.md" : "organized.md"
    return FileManager.default.fileExists(atPath: outputDirectory(for: videoURL).appending(path: marker).path)
  }

  public func pendingVideos(transcribeOnly: Bool, force: Bool) throws -> [URL] {
    let extensions: Set = ["mp4", "mov", "m4v"]
    let all = try FileManager.default.contentsOfDirectory(at: videosDirectory, includingPropertiesForKeys: nil)
      .filter { extensions.contains($0.pathExtension.lowercased()) }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard !force else { return all }
    return all.filter { !isProcessed(videoURL: $0, transcribeOnly: transcribeOnly) }
  }
}
