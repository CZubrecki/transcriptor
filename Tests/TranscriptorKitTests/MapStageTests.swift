import Testing
import Foundation
import FoundationModels
@testable import TranscriptorKit

@Test func extractsStructuredNotesFromATechnicalChunk() async throws {
  guard case .available = SystemLanguageModel.default.availability else { return }
  let chunk = [TranscriptSegment(
    text: "In iOS 26 SwiftUI adds the glass effect modifier. Use it on a view and group them with a glass effect container. Avoid nesting glass inside glass.",
    start: 0, end: 12)]

  let notes = try #require(await FoundationModelsOrganizer().notes(for: chunk))
  #expect(!notes.topic.isEmpty)
  #expect(!notes.keyPoints.isEmpty)
  #expect(notes.keyPoints.count <= 6)
  #expect(notes.terms.count <= 8)
}

@Test func splitsChunksThatOverflowTheContextWindow() async throws {
  guard case .available = SystemLanguageModel.default.availability else { return }
  let oversized = (0..<40).map {
    TranscriptSegment(
      text: "Sentence number \($0) describing an unrelated topic in some detail. " + String(repeating: "filler words here. ", count: 20),
      start: Double($0), end: Double($0) + 1)
  }
  let results = try await FoundationModelsOrganizer().notesSplittingOnOverflow(for: oversized)
  #expect(results.count >= 2)
}
