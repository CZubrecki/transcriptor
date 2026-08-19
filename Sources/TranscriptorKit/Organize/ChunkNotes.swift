import FoundationModels

@Generable
public struct ChunkNotes: Sendable {
  @Guide(description: "Short topic title for this passage")
  public var topic: String

  @Guide(description: "One or two sentence summary of this passage")
  public var summary: String

  @Guide(description: "Key points made in this passage", .count(1...6))
  public var keyPoints: [String]

  @Guide(description: "Named things: frameworks, types, methods, concepts, tools", .count(0...8))
  public var terms: [String]

  @Guide(description: "Actionable recommendations or practices stated", .count(0...5))
  public var guidance: [String]

  @Guide(description: "Constraints, version requirements, limitations, pitfalls", .count(0...5))
  public var caveats: [String]
}
