import Testing
@testable import TranscriptorKit

private func seg(_ text: String, _ start: Double = 0) -> TranscriptSegment {
  TranscriptSegment(text: text, start: start, end: start + 1)
}

@Test func estimatesTokensAsQuarterOfCharacters() {
  #expect(TranscriptChunker.estimatedTokens(String(repeating: "a", count: 400)) == 100)
}

@Test func groupsSegmentsUpToTargetTokens() {
  let segments = (0..<10).map { seg(String(repeating: "x", count: 400), Double($0)) }
  let chunks = TranscriptChunker.chunk(segments, targetTokens: 300)
  #expect(chunks.count == 4)
  #expect(chunks[0].count == 3)
  #expect(chunks.flatMap(\.self).count == 10)
}

@Test func neverSplitsASingleSegment() {
  let huge = seg(String(repeating: "y", count: 40_000))
  let chunks = TranscriptChunker.chunk([huge], targetTokens: 300)
  #expect(chunks.count == 1)
  #expect(chunks[0].count == 1)
}

@Test func emptyInputProducesNoChunks() {
  #expect(TranscriptChunker.chunk([], targetTokens: 300).isEmpty)
}

@Test func preservesSegmentOrder() {
  let segments = (0..<6).map { seg("segment \($0) " + String(repeating: "z", count: 400), Double($0)) }
  let chunks = TranscriptChunker.chunk(segments, targetTokens: 300)
  let flattened = chunks.flatMap(\.self).map(\.start)
  #expect(flattened == segments.map(\.start))
}
