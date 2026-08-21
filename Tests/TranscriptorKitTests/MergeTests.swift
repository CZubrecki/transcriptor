import Testing
@testable import TranscriptorKit

private func notes(_ topic: String, terms: [String] = [], points: [String] = ["a point"]) -> ChunkNotes {
  ChunkNotes(topic: topic, summary: "s", keyPoints: points, terms: terms, guidance: [], caveats: [])
}

@Test
func `falls back to linear order without an outline`() {
  let doc = DocumentMerger.merge(notes: [notes("One"), notes("Two")], outline: nil)
  #expect(doc.sections.count == 2)
  #expect(doc.sections.map(\.title) == ["One", "Two"])
  #expect(!doc.title.isEmpty)
}

@Test
func `groups chunks according to the outline`() {
  let outline = DocumentOutline(
    title: "Session Notes",
    overview: "An overview.",
    groups: [
      OutlineGroup(title: "Setup", chunkIndices: [0, 2]),
      OutlineGroup(title: "Details", chunkIndices: [1]),
    ],
  )
  let doc = DocumentMerger.merge(
    notes: [notes("A", points: ["p0"]), notes("B", points: ["p1"]), notes("C", points: ["p2"])],
    outline: outline,
  )

  #expect(doc.title == "Session Notes")
  #expect(doc.sections.count == 2)
  #expect(doc.sections[0].title == "Setup")
  #expect(doc.sections[0].keyPoints == ["p0", "p2"])
}

@Test
func `dedupes terms case insensitively keeping first spelling`() {
  let doc = DocumentMerger.merge(
    notes: [notes("A", terms: ["SwiftUI", "Combine"]), notes("B", terms: ["swiftui", "Observation"])],
    outline: nil,
  )
  #expect(doc.termIndex == ["Combine", "Observation", "SwiftUI"])
}

@Test
func `ignores out of range chunk indices`() {
  let outline = DocumentOutline(
    title: "T",
    overview: "O",
    groups: [OutlineGroup(title: "Group", chunkIndices: [0, 99])],
  )
  let doc = DocumentMerger.merge(notes: [notes("A")], outline: outline)
  #expect(doc.sections.count == 1)
  #expect(doc.sections[0].keyPoints == ["a point"])
}

@Test
func `drops groups that end up empty`() {
  let outline = DocumentOutline(
    title: "T",
    overview: "O",
    groups: [OutlineGroup(title: "Real", chunkIndices: [0]), OutlineGroup(title: "Empty", chunkIndices: [42])],
  )
  let doc = DocumentMerger.merge(notes: [notes("A")], outline: outline)
  #expect(doc.sections.map(\.title) == ["Real"])
}

@Test
func `recovers chunks the outline never referenced`() {
  let outline = DocumentOutline(
    title: "T",
    overview: "O",
    groups: [OutlineGroup(title: "Middle", chunkIndices: [1])],
  )
  let doc = DocumentMerger.merge(
    notes: [notes("A", points: ["p0"]), notes("B", points: ["p1"]), notes("C", points: ["p2"])],
    outline: outline,
  )
  #expect(doc.sections.map(\.title) == ["Middle", "A", "C"])
  #expect(doc.sections[1].keyPoints == ["p0"])
  #expect(doc.sections[2].keyPoints == ["p2"])
}

@Test
func `first group to claim an index wins on duplicates`() {
  let outline = DocumentOutline(
    title: "T",
    overview: "O",
    groups: [
      OutlineGroup(title: "First", chunkIndices: [0]),
      OutlineGroup(title: "Second", chunkIndices: [0, 1]),
    ],
  )
  let doc = DocumentMerger.merge(
    notes: [notes("A", points: ["p0"]), notes("B", points: ["p1"])],
    outline: outline,
  )
  #expect(doc.sections.map(\.title) == ["First", "Second"])
  #expect(doc.sections[0].keyPoints == ["p0"])
  #expect(doc.sections[1].keyPoints == ["p1"])
}

@Test
func `every chunk appears exactly once with duplicates and orphans`() {
  let outline = DocumentOutline(
    title: "T",
    overview: "O",
    groups: [
      OutlineGroup(title: "First", chunkIndices: [0, 1]),
      OutlineGroup(title: "Second", chunkIndices: [1]),
    ],
  )
  let doc = DocumentMerger.merge(
    notes: [notes("A", points: ["p0"]), notes("B", points: ["p1"]), notes("C", points: ["p2"])],
    outline: outline,
  )
  let allKeyPoints = doc.sections.flatMap(\.keyPoints)
  #expect(allKeyPoints.sorted() == ["p0", "p1", "p2"])
  #expect(doc.sections.map(\.title) == ["First", "C"])
}

@Test
func `skips outline generation when too many topics`() async throws {
  let organizer = FoundationModelsOrganizer()
  let phrases = [
    "Configuring the speech transcriber for a chosen locale",
    "Converting audio buffers into the analyzer input format",
    "Handling context window limits when summarizing long passages",
    "Grouping related topics into a coherent document outline",
    "Streaming sample buffers without loading the whole file",
  ]
  let topics = (0..<51).map { "\(phrases[$0 % phrases.count]) (part \($0))" }
  let start = ContinuousClock.now
  let outline = try await organizer.outline(topics: topics, terms: [])
  let elapsed = start.duration(to: .now)
  #expect(outline == nil)
  #expect(elapsed < .seconds(1))
}
