import Foundation

public struct TranscriptSegment: Sendable, Equatable {
  public let text: String
  public let start: TimeInterval
  public let end: TimeInterval

  public init(text: String, start: TimeInterval, end: TimeInterval) {
    self.text = text
    self.start = start
    self.end = end
  }
}
