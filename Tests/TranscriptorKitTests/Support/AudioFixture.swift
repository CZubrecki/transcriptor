import AVFoundation

// MARK: - AudioFixtureError

enum AudioFixtureError: Error {
  case noVoiceAvailable
  case timedOut
}

// MARK: - AudioFixture

enum AudioFixture {
  /// Synthesis reports completion only through its buffer callback, and on a
  /// machine without a usable speech session that callback never arrives. The
  /// deadline turns that into a failure instead of an indefinite hang.
  static let deadline = Duration.seconds(30)

  static func write(text: String, to url: URL) async throws {
    guard let voice = AVSpeechSynthesisVoice(language: "en-US") else {
      throw AudioFixtureError.noVoiceAvailable
    }
    let synthesizer = AVSpeechSynthesizer()
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = voice

    let synthesis = AsyncStream<Void>.makeStream()
    var file: AVAudioFile?
    synthesizer.write(utterance) { buffer in
      guard let pcm = buffer as? AVAudioPCMBuffer else { return }
      guard pcm.frameLength > 0 else {
        synthesis.continuation.finish()
        return
      }
      if file == nil {
        file = try? AVAudioFile(forWriting: url, settings: pcm.format.settings)
      }
      try? file?.write(from: pcm)
    }

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        for await _ in synthesis.stream { }
      }
      group.addTask {
        try await Task.sleep(for: deadline)
        throw AudioFixtureError.timedOut
      }
      try await group.next()
      group.cancelAll()
    }
  }
}

// MARK: - VideoOnlyFixture

enum VideoOnlyFixture {
  static func write(to url: URL) async throws {
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: 160,
      AVVideoHeightKey: 120,
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB],
    )
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    var pixelBuffer: CVPixelBuffer?
    CVPixelBufferCreate(nil, 160, 120, kCVPixelFormatType_32ARGB, nil, &pixelBuffer)
    for frame in 0..<10 {
      while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
      adaptor.append(pixelBuffer!, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10))
    }
    input.markAsFinished()
    await writer.finishWriting()
  }
}
