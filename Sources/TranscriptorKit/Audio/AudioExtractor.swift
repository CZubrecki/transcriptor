import AVFoundation
import Foundation

// MARK: - AudioExtractorError

public enum AudioExtractorError: Error, CustomStringConvertible {
  case noAudioTrack(URL)
  case converterUnavailable
  case conversionFailed(String)

  public var description: String {
    switch self {
    case .noAudioTrack(let url): "no audio track in \(url.lastPathComponent)"
    case .converterUnavailable: "could not create an audio converter for this file"
    case .conversionFailed(let reason): "audio conversion failed: \(reason)"
    }
  }
}

// MARK: - AudioExtractor

public enum AudioExtractor {
  public static func duration(of url: URL) async throws -> TimeInterval {
    try await AVURLAsset(url: url).load(.duration).seconds
  }

  public static func buffers(
    from url: URL,
    to targetFormat: AVAudioFormat,
  ) async throws -> AsyncThrowingStream<AVAudioPCMBuffer, Error> {
    let reader = try await AudioSampleReader(url: url, targetFormat: targetFormat)
    return AsyncThrowingStream { try reader.next() }
  }
}

// MARK: - AudioSampleReader

/// The unfolding closure above invokes `next()` serially, never concurrently,
/// so the unsynchronized mutable state here is safe despite `@unchecked Sendable`.
final class AudioSampleReader: @unchecked Sendable {

  // MARK: Lifecycle

  init(url: URL, targetFormat: AVAudioFormat) async throws {
    let asset = AVURLAsset(url: url)
    guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
      throw AudioExtractorError.noAudioTrack(url)
    }
    assetReader = try AVAssetReader(asset: asset)
    output = AVAssetReaderTrackOutput(track: track, outputSettings: [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVLinearPCMIsFloatKey: true,
      AVLinearPCMBitDepthKey: 32,
      AVLinearPCMIsNonInterleaved: false,
    ])
    assetReader.add(output)
    assetReader.startReading()
    self.targetFormat = targetFormat
  }

  deinit {
    assetReader.cancelReading()
  }

  // MARK: Internal

  private(set) var droppedSampleCount = 0

  var readerStatus: AVAssetReader.Status {
    assetReader.status
  }

  func cancel() {
    assetReader.cancelReading()
  }

  func next() throws -> AVAudioPCMBuffer? {
    while let sample = output.copyNextSampleBuffer() {
      guard
        let description = CMSampleBufferGetFormatDescription(sample),
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
        let sourceFormat = AVAudioFormat(streamDescription: asbd)
      else {
        droppedSampleCount += 1
        continue
      }

      let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
      guard frames > 0 else { continue }
      guard let input = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frames) else {
        droppedSampleCount += 1
        continue
      }
      input.frameLength = frames
      CMSampleBufferCopyPCMDataIntoAudioBufferList(
        sample,
        at: 0,
        frameCount: Int32(frames),
        into: input.mutableAudioBufferList,
      )

      if converter == nil {
        converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
      }
      guard let converter else { throw AudioExtractorError.converterUnavailable }

      let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
      let capacity = AVAudioFrameCount(Double(frames) * ratio) + 1024
      guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
        throw AudioExtractorError.conversionFailed("could not allocate output buffer")
      }

      nonisolated(unsafe) let source = input
      nonisolated(unsafe) var supplied = false
      var conversionError: NSError?
      let status = converter.convert(to: converted, error: &conversionError) { _, statusPointer in
        if supplied {
          statusPointer.pointee = .noDataNow
          return nil
        }
        supplied = true
        statusPointer.pointee = .haveData
        return source
      }
      if let conversionError { throw conversionError }
      if status == .error { throw AudioExtractorError.conversionFailed("converter returned .error") }
      if converted.frameLength > 0 { return converted }
    }
    if assetReader.status == .failed { throw assetReader.error ?? AudioExtractorError.conversionFailed("reader failed") }
    if droppedSampleCount > 0 {
      FileHandle.standardError.write(Data("warning: skipped \(droppedSampleCount) unreadable audio samples\n".utf8))
    }
    return nil
  }

  // MARK: Private

  private let assetReader: AVAssetReader
  private let output: AVAssetReaderTrackOutput
  private let targetFormat: AVAudioFormat
  private var converter: AVAudioConverter?

}
