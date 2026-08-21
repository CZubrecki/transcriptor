import AVFoundation
import Testing
@testable import TranscriptorKit

@Test(.enabled(if: Capability.speechSynthesis))
func `extracts buffers in target format`() async throws {
  let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "\(UUID().uuidString).caf")
  try await AudioFixture.write(text: "Testing audio extraction with a reasonably long sentence.", to: url)
  defer { try? FileManager.default.removeItem(at: url) }

  let target = try #require(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
  var frames: AVAudioFrameCount = 0
  for try await buffer in try await AudioExtractor.buffers(from: url, to: target) {
    #expect(buffer.format.sampleRate == 16000)
    #expect(buffer.format.channelCount == 1)
    frames += buffer.frameLength
  }
  #expect(frames > 16000)
}

@Test(.enabled(if: Capability.speechSynthesis))
func `reports duration`() async throws {
  let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "\(UUID().uuidString).caf")
  try await AudioFixture.write(text: "A short clip.", to: url)
  defer { try? FileManager.default.removeItem(at: url) }
  let duration = try await AudioExtractor.duration(of: url)
  #expect(duration > 0.5)
}

@Test
func `throws when no audio track`() async throws {
  let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "\(UUID().uuidString).mp4")
  try await VideoOnlyFixture.write(to: url)
  defer { try? FileManager.default.removeItem(at: url) }
  let target = try #require(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))

  do {
    _ = try await AudioExtractor.buffers(from: url, to: target)
    Issue.record("expected AudioExtractorError.noAudioTrack to be thrown")
  } catch AudioExtractorError.noAudioTrack {
    // expected
  } catch {
    Issue.record("expected AudioExtractorError.noAudioTrack, got \(error)")
  }
}

@Test
func `throws for unreadable container`() async throws {
  let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "\(UUID().uuidString).mp4")
  try Data("not a video".utf8).write(to: url)
  defer { try? FileManager.default.removeItem(at: url) }
  let target = try #require(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
  await #expect(throws: (any Error).self) {
    for try await _ in try await AudioExtractor.buffers(from: url, to: target) { }
  }
}

@Test(.enabled(if: Capability.speechSynthesis))
func `manually cancelling reader marks it cancelled`() async throws {
  let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "\(UUID().uuidString).caf")
  try await AudioFixture.write(
    text: "Testing audio extraction with a reasonably long sentence that yields several buffers.",
    to: url,
  )
  defer { try? FileManager.default.removeItem(at: url) }

  let target = try #require(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
  let reader = try await AudioSampleReader(url: url, targetFormat: target)
  let stream = AsyncThrowingStream<AVAudioPCMBuffer, Error> { try reader.next() }

  var count = 0
  for try await _ in stream {
    count += 1
    if count == 2 { break }
  }
  reader.cancel()
  #expect(reader.readerStatus == .cancelled)
}

@Test(.enabled(if: Capability.speechSynthesis))
func `abandoned stream releases file for subsequent reads`() async throws {
  let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "\(UUID().uuidString).caf")
  try await AudioFixture.write(
    text: "Testing audio extraction with a reasonably long sentence that yields several buffers.",
    to: url,
  )
  defer { try? FileManager.default.removeItem(at: url) }

  let target = try #require(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))

  var abandoned: AsyncThrowingStream<AVAudioPCMBuffer, Error>? =
    try await AudioExtractor.buffers(from: url, to: target)
  var count = 0
  for try await _ in try #require(abandoned) {
    count += 1
    if count == 2 { break }
  }
  abandoned = nil

  var frames: AVAudioFrameCount = 0
  for try await buffer in try await AudioExtractor.buffers(from: url, to: target) {
    #expect(buffer.format.sampleRate == 16000)
    #expect(buffer.format.channelCount == 1)
    frames += buffer.frameLength
  }
  #expect(frames > 16000)
}
