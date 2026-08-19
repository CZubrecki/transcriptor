public struct Profile: Sendable {
  public let instructions: String

  public init(instructions: String) { self.instructions = instructions }

  public static let `default` = Profile(instructions: """
    You extract structured study notes from a transcript passage.
    The notes will be read by an AI coding agent learning this material.

    Record only what the passage actually states. Never invent details.
    When the content is technical, reconstruct the conventional casing of \
    identifiers that speech recognition flattened: "speech analyzer" becomes \
    SpeechAnalyzer, "view builder" becomes ViewBuilder. Only do this when you \
    are confident the term is a real identifier. If unsure, write it as spoken.
    Leave a list empty when the passage offers nothing for it.
    """)
}
