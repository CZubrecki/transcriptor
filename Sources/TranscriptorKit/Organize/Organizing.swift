import Foundation
import FoundationModels

public protocol Organizing: Sendable {
  func notes(for chunk: [TranscriptSegment]) async throws -> ChunkNotes?
  func notesSplittingOnOverflow(for chunk: [TranscriptSegment]) async throws -> [ChunkNotes]
  func outline(topics: [String], terms: [String]) async throws -> DocumentOutline?
}

extension Organizing {
  public func notesSplittingOnOverflow(for chunk: [TranscriptSegment]) async throws -> [ChunkNotes] {
    if let single = try await notes(for: chunk) { return [single] }
    return []
  }
}

public struct FoundationModelsOrganizer: Organizing {
  private let profile: Profile

  public init(profile: Profile = .default) { self.profile = profile }

  public func notes(for chunk: [TranscriptSegment]) async throws -> ChunkNotes? {
    let text = chunk.map(\.text).joined(separator: " ")
    let session = LanguageModelSession(instructions: profile.instructions)
    do {
      return try await session.respond(
        to: "Extract notes from this passage:\n\n\(text)",
        generating: ChunkNotes.self).content
    } catch let error as LanguageModelSession.GenerationError {
      switch error {
      case .exceededContextWindowSize:
        throw OrganizeError.contextOverflow
      case .guardrailViolation:
        warn("skipping a passage: content refused by safety guardrails: \(error)")
        return nil
      default:
        warn("skipping a passage: \(error)")
        return nil
      }
    }
  }

  // Overrides the protocol default to add recursive splitting on overflow.
  public func notesSplittingOnOverflow(for chunk: [TranscriptSegment]) async throws -> [ChunkNotes] {
    do {
      if let single = try await notes(for: chunk) { return [single] }
      return []
    } catch OrganizeError.contextOverflow {
      guard chunk.count > 1 else {
        warn("skipping one oversized segment that cannot be split further")
        return []
      }
      let middle = chunk.count / 2
      let left = try await notesSplittingOnOverflow(for: Array(chunk[..<middle]))
      let right = try await notesSplittingOnOverflow(for: Array(chunk[middle...]))
      return left + right
    }
  }
}

public enum OrganizeError: Error {
  case contextOverflow
}

func warn(_ message: String) {
  FileHandle.standardError.write(Data("warning: \(message)\n".utf8))
}

@Generable
public struct OutlineGroup: Sendable {
  @Guide(description: "Title for this group of passages")
  public var title: String
  @Guide(description: "Zero-based indices of the passages belonging to this group", .count(1...12))
  public var chunkIndices: [Int]
}

@Generable
public struct DocumentOutline: Sendable {
  @Guide(description: "Title for the whole document")
  public var title: String
  @Guide(description: "Two or three sentence overview of what the document covers")
  public var overview: String
  @Guide(description: "Groups of passages, in reading order", .count(1...15))
  public var groups: [OutlineGroup]
}

extension FoundationModelsOrganizer {
  public func outline(topics: [String], terms: [String]) async throws -> DocumentOutline? {
    guard topics.count <= 50 else {
      warn("skipping outline generation: too many passages (\(topics.count)) to group reliably")
      return nil
    }
    let numbered = topics.enumerated()
      .map { "\($0.offset). \(String($0.element.prefix(100)))" }
      .joined(separator: "\n")
    let termList = terms.prefix(60).joined(separator: ", ")
    let session = LanguageModelSession(instructions: """
      You organize a list of transcript passage topics into a document outline.
      Group passages that cover the same subject, even when they are far apart.
      Every index you use must come from the list given. Never invent an index.
      Preserve reading order across groups.
      """)
    do {
      return try await session.respond(
        to: "Passage topics:\n\(numbered)\n\nTerms mentioned: \(termList)",
        generating: DocumentOutline.self).content
    } catch {
      warn("outline generation failed, falling back to linear order: \(error)")
      return nil
    }
  }
}
