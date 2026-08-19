import Foundation

public enum TranscriptChunker {
  public static func estimatedTokens(_ text: String) -> Int {
    text.count / 4
  }

  public static func chunk(
    _ segments: [TranscriptSegment],
    targetTokens: Int = 1200
  ) -> [[TranscriptSegment]] {
    var chunks: [[TranscriptSegment]] = []
    var current: [TranscriptSegment] = []
    var currentTokens = 0

    for segment in segments {
      let tokens = estimatedTokens(segment.text)
      if !current.isEmpty, currentTokens + tokens > targetTokens {
        chunks.append(current)
        current = []
        currentTokens = 0
      }
      current.append(segment)
      currentTokens += tokens
    }
    if !current.isEmpty { chunks.append(current) }
    return chunks
  }
}
