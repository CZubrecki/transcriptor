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
