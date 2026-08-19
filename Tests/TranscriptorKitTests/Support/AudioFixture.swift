import AVFoundation

enum AudioFixture {
  static func write(text: String, to url: URL) async throws {
    let synthesizer = AVSpeechSynthesizer()
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

    nonisolated(unsafe) var file: AVAudioFile?
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      nonisolated(unsafe) var finished = false
      synthesizer.write(utterance) { buffer in
        guard let pcm = buffer as? AVAudioPCMBuffer else { return }
        if pcm.frameLength == 0 {
          if !finished { finished = true; continuation.resume() }
          return
        }
        if file == nil {
          file = try? AVAudioFile(forWriting: url, settings: pcm.format.settings)
        }
        try? file?.write(from: pcm)
      }
    }
    file = nil
  }
}

enum VideoOnlyFixture {
  static func write(to url: URL) async throws {
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: 160, AVVideoHeightKey: 120])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB])
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
