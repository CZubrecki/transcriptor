import Foundation
import Testing
@testable import TranscriptorKit

@Test
func `output directory uses video basename`() {
  let ws = Workspace(root: URL(fileURLWithPath: "/tmp/proj"))
  let out = ws.outputDirectory(for: URL(fileURLWithPath: "/tmp/proj/videos/WWDC Session 10023.mp4"))
  #expect(out.path == "/tmp/proj/transcriptions/WWDC Session 10023")
}

@Test
func `is processed checks organized by default`() throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let ws = Workspace(root: root)
  let video = ws.videosDirectory.appending(path: "a.mp4")
  let out = ws.outputDirectory(for: video)
  try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
  #expect(ws.isProcessed(videoURL: video, transcribeOnly: false) == false)
  try Data().write(to: out.appending(path: "organized.md"))
  #expect(ws.isProcessed(videoURL: video, transcribeOnly: false) == true)
}

@Test
func `is processed checks transcript when transcribe only`() throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let ws = Workspace(root: root)
  let video = ws.videosDirectory.appending(path: "a.mp4")
  let out = ws.outputDirectory(for: video)
  try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
  try Data().write(to: out.appending(path: "organized.md"))
  #expect(ws.isProcessed(videoURL: video, transcribeOnly: true) == false)
  try Data().write(to: out.appending(path: "full-transcription.md"))
  #expect(ws.isProcessed(videoURL: video, transcribeOnly: true) == true)
}

@Test
func `pending videos filters extensions case insensitive`() throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let ws = Workspace(root: root)
  try FileManager.default.createDirectory(at: ws.videosDirectory, withIntermediateDirectories: true)

  let filesToCreate = ["a.mp4", "b.MOV", "c.m4v", "d.txt", "e.png"]
  for filename in filesToCreate {
    try Data().write(to: ws.videosDirectory.appending(path: filename))
  }

  let pending = try ws.pendingVideos(transcribeOnly: false, force: true)
  let names = pending.map { $0.lastPathComponent }.sorted()
  #expect(names == ["a.mp4", "b.MOV", "c.m4v"])
}

@Test
func `pending videos sorted by last path component`() throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let ws = Workspace(root: root)
  try FileManager.default.createDirectory(at: ws.videosDirectory, withIntermediateDirectories: true)

  let filesToCreate = ["z.mp4", "a.mov", "m.m4v"]
  for filename in filesToCreate {
    try Data().write(to: ws.videosDirectory.appending(path: filename))
  }

  let pending = try ws.pendingVideos(transcribeOnly: false, force: true)
  let names = pending.map { $0.lastPathComponent }
  #expect(names == ["a.mov", "m.m4v", "z.mp4"])
}

@Test
func `pending videos respects force flag with organized`() throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let ws = Workspace(root: root)
  try FileManager.default.createDirectory(at: ws.videosDirectory, withIntermediateDirectories: true)

  let video = ws.videosDirectory.appending(path: "test.mp4")
  try Data().write(to: video)
  let out = ws.outputDirectory(for: video)
  try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
  try Data().write(to: out.appending(path: "organized.md"))

  let withoutForce = try ws.pendingVideos(transcribeOnly: false, force: false)
  #expect(withoutForce.isEmpty == true)

  let withForce = try ws.pendingVideos(transcribeOnly: false, force: true)
  #expect(withForce.count == 1)
}

@Test
func `pending videos transcribe only ignores organized`() throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let ws = Workspace(root: root)
  try FileManager.default.createDirectory(at: ws.videosDirectory, withIntermediateDirectories: true)

  let video = ws.videosDirectory.appending(path: "test.mp4")
  try Data().write(to: video)
  let out = ws.outputDirectory(for: video)
  try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
  try Data().write(to: out.appending(path: "organized.md"))

  let pending = try ws.pendingVideos(transcribeOnly: true, force: false)
  #expect(pending.count == 1)
}
